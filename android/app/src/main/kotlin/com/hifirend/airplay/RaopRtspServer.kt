package com.hifirend.airplay

import android.util.Base64
import android.util.Log
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * The RTSP half of an AirPlay 1 receiver: everything up to the point audio
 * starts arriving.
 *
 * A session is a fixed conversation, and this handles all of it:
 *
 *   OPTIONS    prove we are an AirPort Express (Apple-Challenge)
 *   ANNOUNCE   the SDP: codec parameters, AES key, AES IV
 *   SETUP      the sender's ports, ours in reply
 *   RECORD     audio begins
 *   FLUSH      seek or pause
 *   TEARDOWN   session over
 *   SET_PARAMETER  volume, progress, metadata
 *
 * One session at a time, deliberately. RAOP allows a receiver to refuse a
 * second sender with `453 Not Enough Bandwidth`, and refusing is right for an
 * appliance with one DAC: the alternative is two guests silently fighting over
 * the output, which is the same collision two UPnP protocols would cause and
 * which the source arbitration already exists to prevent.
 *
 * This class knows nothing about audio. It resolves a session and hands it to
 * [onSessionReady]; decoding and playback are the next layer's problem. That
 * split is what lets the handshake be proven against a real iPhone before any
 * of the audio path exists.
 */
class RaopRtspServer(
    private val crypto: RaopCrypto,
    private val hardwareAddress: ByteArray,
    private val onSessionReady: (RaopSessionParams) -> Unit,
    private val onTeardown: () -> Unit,
) {

    @Volatile var port: Int = 0
        private set

    private var server: ServerSocket? = null
    private val running = AtomicBoolean(false)
    private val busy = AtomicBoolean(false)

    fun start(): Int {
        stop()
        val s = ServerSocket(0)          // any free port; mDNS publishes it
        server = s
        port = s.localPort
        running.set(true)
        thread(name = "raop-rtsp", isDaemon = true) { accept(s) }
        Log.i(TAG, "AirPlay RTSP listening on port $port")
        return port
    }

    fun stop() {
        running.set(false)
        runCatching { server?.close() }
        server = null
    }

    private fun accept(s: ServerSocket) {
        while (running.get()) {
            val socket = try {
                s.accept()
            } catch (e: IOException) {
                if (running.get()) Log.w(TAG, "AirPlay accept failed: ${e.message}")
                return
            }
            // A sender holds the RTSP socket open for the whole session, so
            // each connection gets a thread rather than being multiplexed.
            // There is only ever one of consequence.
            thread(name = "raop-session", isDaemon = true) { serve(socket) }
        }
    }

    private fun serve(socket: Socket) {
        val already = !busy.compareAndSet(false, true)
        // A TEARDOWN tears down once. Without this the explicit teardown and
        // the socket-closed teardown both fire, which is invisible while the
        // callback only logs and is a double free of ports and decoder state
        // as soon as it does anything real. Declared out here because the
        // `finally` has to read it.
        var torndown = false
        try {
            socket.tcpNoDelay = true
            val input = socket.getInputStream()
            val output = socket.getOutputStream()
            var announced: Map<String, String> = emptyMap()

            while (running.get() && !socket.isClosed) {
                val request = try {
                    Rtsp.read(input) ?: break
                } catch (e: IOException) {
                    Log.w(TAG, "AirPlay session read failed: ${e.message}")
                    break
                }
                Log.i(TAG, "airplay: ${request.method} ${request.uri}")

                if (already) {
                    // Someone is already connected. Say so properly rather
                    // than dropping the socket, so the second sender reports
                    // "in use" instead of "could not connect".
                    output.write(reply(request, "453 Not Enough Bandwidth").toBytes())
                    output.flush()
                    continue
                }

                val response = when (request.method) {
                    "OPTIONS" -> options(request, socket.localAddress)
                    "ANNOUNCE" -> {
                        announced = Rtsp.parseSdpAttributes(String(request.body, Charsets.UTF_8))
                        Log.i(TAG, "airplay: announced ${announced.keys}")
                        reply(request)
                    }
                    "SETUP" -> setup(request, announced)
                    "RECORD" -> reply(request).header("Audio-Latency", "2205")
                    "FLUSH", "SET_PARAMETER", "GET_PARAMETER" -> reply(request)
                    "TEARDOWN" -> {
                        torndown = true
                        runCatching { onTeardown() }
                        reply(request).header("Connection", "close")
                    }
                    else -> reply(request, "501 Not Implemented")
                }
                output.write(response.toBytes())
                output.flush()
                if (request.method == "TEARDOWN") break
            }
        } catch (e: Throwable) {
            Log.w(TAG, "AirPlay session ended: ${e::class.java.simpleName}: ${e.message}")
        } finally {
            runCatching { socket.close() }
            if (!already) {
                busy.set(false)
                // Only if the sender never said so itself -- a dropped socket
                // is the other way a session ends, and the commonest one when
                // a phone walks out of range.
                if (!torndown) runCatching { onTeardown() }
            }
        }
    }

    /**
     * Every reply carries the sender's CSeq back. Omitting it, or returning a
     * different one, ends the session at once and without explanation, which
     * makes it the single easiest thing to get wrong here.
     */
    private fun reply(request: RtspRequest, status: String = "200 OK") =
        RtspResponse(status).apply {
            request.cseq?.let { header("CSeq", it) }
            header("Server", "AirTunes/105.1")
        }

    private fun options(request: RtspRequest, local: InetAddress): RtspResponse {
        val response = reply(request).header(
            "Public",
            "ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER")
        val challenge = request["Apple-Challenge"] ?: return response
        val answer = runCatching {
            crypto.appleResponse(challenge, local.address, hardwareAddress)
        }.getOrNull()
        if (answer == null) {
            // Advertised but cannot prove itself. Saying so once is worth more
            // than a sender-side "cannot connect" with no cause.
            Log.w(TAG, "airplay: challenged, but no RAOP key is present -- " +
                "the sender will refuse this session (see ${RaopCrypto.KEY_ASSET})")
            return response
        }
        return response.header("Apple-Response", answer)
    }

    /**
     * Answers with the ports we will listen on.
     *
     * The sender's own ports arrive in the Transport header and are needed to
     * send timing and retransmit requests back. Ports are not bound here --
     * the audio layer owns them -- so this reports what it was told to report.
     */
    private fun setup(request: RtspRequest, announced: Map<String, String>): RtspResponse {
        val transport = request["Transport"].orEmpty()
        val control = transport.field("control_port")
        val timing = transport.field("timing_port")

        val params = RaopSessionParams(
            aesKey = announced["rsaaeskey"]?.let { runCatching { crypto.decryptAesKey(it) }.getOrNull() },
            aesIv = announced["aesiv"]?.let {
                runCatching { Base64.decode(RaopCrypto.pad(it), Base64.DEFAULT) }.getOrNull()
            },
            formatParameters = announced["fmtp"].orEmpty(),
            senderControlPort = control,
            senderTimingPort = timing,
        )
        runCatching { onSessionReady(params) }
            .onFailure { Log.w(TAG, "AirPlay session setup failed: ${it.message}") }

        return reply(request)
            .header("Transport",
                "RTP/AVP/UDP;unicast;mode=record;server_port=${params.serverAudioPort};" +
                    "control_port=${params.serverControlPort};timing_port=${params.serverTimingPort}")
            .header("Session", "1")
    }

    private fun String.field(name: String): Int =
        Regex("$name=(\\d+)").find(this)?.groupValues?.get(1)?.toIntOrNull() ?: 0

    private companion object {
        const val TAG = "hifirend"
    }
}

/**
 * What a completed handshake yields. The audio layer needs all of it and
 * nothing else, which is why the RTSP server can be finished and tested before
 * that layer exists.
 */
data class RaopSessionParams(
    val aesKey: ByteArray?,
    val aesIv: ByteArray?,
    /** ALAC configuration from the SDP: frame length, bit depth, channels, rate. */
    val formatParameters: String,
    val senderControlPort: Int,
    val senderTimingPort: Int,
    var serverAudioPort: Int = 0,
    var serverControlPort: Int = 0,
    var serverTimingPort: Int = 0,
) {
    override fun equals(other: Any?): Boolean =
        other is RaopSessionParams &&
            aesKey.contentEquals(other.aesKey) && aesIv.contentEquals(other.aesIv) &&
            formatParameters == other.formatParameters &&
            senderControlPort == other.senderControlPort &&
            senderTimingPort == other.senderTimingPort

    override fun hashCode(): Int =
        ((aesKey?.contentHashCode() ?: 0) * 31 + (aesIv?.contentHashCode() ?: 0)) * 31 +
            formatParameters.hashCode()
}
