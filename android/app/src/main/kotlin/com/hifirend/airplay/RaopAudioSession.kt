package com.hifirend.airplay

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.concurrent.thread

/**
 * The three UDP sockets a RAOP session runs on, and the decryption of what
 * arrives on the first of them.
 *
 * A sender expects to be told three ports at SETUP and will not start without
 * them:
 *
 *   audio    the RTP stream itself, encrypted ALAC
 *   control  retransmit requests and sync packets, sender <-> receiver
 *   timing   NTP-ish exchange the sender uses to place audio in time
 *
 * Only the audio port is read here. Control and timing are bound and drained
 * so the sender sees open ports and its packets are not answered with ICMP
 * unreachable -- which some senders treat as the receiver having gone away --
 * but nothing is done with them yet. Sync and retransmission are what separate
 * "plays" from "plays without dropouts", and they come after audio exists at
 * all.
 *
 * Sockets are bound to the wildcard address rather than to an interface,
 * because the sender is not necessarily on IPv4: macOS was observed connecting
 * over link-local `fe80::` and then a global `2806:` address. Android's
 * wildcard bind is dual-stack, so one socket serves both families; binding to
 * a chosen IPv4 address would have quietly refused every IPv6 sender.
 */
class RaopAudioSession(
    aesKey: ByteArray?,
    private val aesIv: ByteArray?,
    private val onAlacFrame: (ByteArray, Int) -> Unit,
) {

    private val key = aesKey?.let { SecretKeySpec(it, "AES") }

    private var audio: DatagramSocket? = null
    private var control: DatagramSocket? = null
    private var timing: DatagramSocket? = null
    private val running = AtomicBoolean(false)

    val packets = AtomicLong(0)
    val bytesDecrypted = AtomicLong(0)
    val undecryptable = AtomicLong(0)

    var audioPort = 0; private set
    var controlPort = 0; private set
    var timingPort = 0; private set

    fun start(): Boolean {
        stop()
        return try {
            val a = DatagramSocket(0)
            val c = DatagramSocket(0)
            val t = DatagramSocket(0)
            // A sender that stops mid-track leaves these idle; a read timeout
            // keeps the threads answerable to stop() rather than parked in
            // receive() for ever.
            a.soTimeout = 2_000
            c.soTimeout = 2_000
            t.soTimeout = 2_000
            audio = a; control = c; timing = t
            audioPort = a.localPort; controlPort = c.localPort; timingPort = t.localPort
            running.set(true)
            thread(name = "raop-audio", isDaemon = true) { readAudio(a) }
            thread(name = "raop-control", isDaemon = true) { drain(c, "control") }
            thread(name = "raop-timing", isDaemon = true) { drain(t, "timing") }
            Log.i(TAG, "airplay: audio=$audioPort control=$controlPort timing=$timingPort " +
                "(key=${key != null} iv=${aesIv != null})")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "airplay: could not bind audio sockets: ${e.message}")
            stop()
            false
        }
    }

    fun stop() {
        running.set(false)
        runCatching { audio?.close() }
        runCatching { control?.close() }
        runCatching { timing?.close() }
        audio = null; control = null; timing = null
    }

    private fun drain(socket: DatagramSocket, what: String) {
        val buf = ByteArray(2048)
        var seen = 0L
        while (running.get()) {
            val p = DatagramPacket(buf, buf.size)
            try {
                socket.receive(p)
                seen++
            } catch (e: java.net.SocketTimeoutException) {
                continue
            } catch (e: Throwable) {
                if (running.get()) Log.w(TAG, "airplay: $what socket ended: ${e.message}")
                return
            }
        }
        Log.i(TAG, "airplay: $what socket closed after $seen packets")
    }

    private fun readAudio(socket: DatagramSocket) {
        // The largest a RAOP audio datagram gets; 352 frames of stereo 16-bit
        // is 1408 bytes before ALAC even compresses it, and the header is 12.
        val buf = ByteArray(2048)
        var loggedFirst = false
        while (running.get()) {
            val p = DatagramPacket(buf, buf.size)
            try {
                socket.receive(p)
            } catch (e: java.net.SocketTimeoutException) {
                continue
            } catch (e: Throwable) {
                if (running.get()) Log.w(TAG, "airplay: audio socket ended: ${e.message}")
                return
            }
            packets.incrementAndGet()

            val payload = rtpPayload(p.data, p.length) ?: continue
            val plain = decrypt(payload)
            if (plain == null) {
                undecryptable.incrementAndGet()
                continue
            }
            bytesDecrypted.addAndGet(plain.size.toLong())
            if (!loggedFirst) {
                loggedFirst = true
                // The first packet is the one worth describing: if the key or
                // the IV were wrong this is plausible-looking noise, and the
                // element type is the cheapest tell that it is not.
                Log.i(TAG, "airplay: first audio packet, ${p.length} bytes on the wire, " +
                    "${plain.size} decrypted, ${describeAlac(plain)}")
            }
            onAlacFrame(plain, plain.size)
        }
    }

    /**
     * Strips the RTP header, or returns null for something that is not audio.
     *
     * The header is the standard twelve bytes. A retransmitted packet arrives
     * with payload type 0x56 and four bytes of its own in front, which is why
     * the type is checked rather than assumed -- feeding a resend's header
     * into the decoder as though it were audio produces a burst of noise
     * rather than a clean failure.
     */
    fun rtpPayload(data: ByteArray, length: Int): ByteArray? {
        if (length <= RTP_HEADER) return null
        val type = (data[1].toInt() and 0x7F)
        val offset = when (type) {
            PT_AUDIO -> RTP_HEADER
            PT_RESEND -> RTP_HEADER + 4
            else -> return null
        }
        if (length <= offset) return null
        return data.copyOfRange(offset, length)
    }

    /**
     * AES-128-CBC over the whole blocks only.
     *
     * RAOP encrypts `floor(n/16)` blocks and leaves the remaining bytes in
     * clear at the end of the packet -- there is no padding, and treating the
     * tail as ciphertext corrupts the last few samples of every frame. The IV
     * is the one from the SDP each time and is not chained between packets,
     * because packets can be lost and a chained receiver would never resync.
     */
    fun decrypt(payload: ByteArray): ByteArray? {
        val k = key ?: return null
        val iv = aesIv ?: return null
        val whole = (payload.size / 16) * 16
        if (whole == 0) return payload.copyOf()
        return try {
            val cipher = Cipher.getInstance("AES/CBC/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, k, IvParameterSpec(iv))
            val out = ByteArray(payload.size)
            cipher.doFinal(payload, 0, whole, out, 0)
            System.arraycopy(payload, whole, out, whole, payload.size - whole)
            out
        } catch (e: Throwable) {
            null
        }
    }

    /**
     * Whether the decrypted bytes look like an ALAC element at all.
     *
     * Not validation -- it is a sanity line for the log. ALAC frames begin
     * with a three-bit element type, and a stereo stream opens with a channel
     * pair element (1). Seeing that on the first packet is good evidence the
     * key and IV were right; seeing anything else means they were not, and
     * that is worth knowing before the decoder is blamed.
     */
    fun describeAlac(frame: ByteArray): String {
        if (frame.isEmpty()) return "empty"
        val element = (frame[0].toInt() and 0xE0) ushr 5
        val name = when (element) {
            0 -> "SCE (mono)"
            1 -> "CPE (stereo)"
            3 -> "LFE"
            6 -> "FIL"
            7 -> "END"
            else -> "element $element"
        }
        return "first element $name"
    }

    private companion object {
        const val TAG = "hifirend"
        const val RTP_HEADER = 12
        const val PT_AUDIO = 0x60
        const val PT_RESEND = 0x56
    }
}
