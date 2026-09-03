package com.hifirend.usb

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.util.Log
import com.hifirend.NativeBridge
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

private const val TAG = "hifirend"

/**
 * Fetches a track over HTTP and feeds it to the native decoder.
 *
 * HTTP stays in Kotlin because redirects, TLS and byte-range requests are
 * solved problems here; the audio engine only wants bytes. This is the path a
 * DLNA controller drives — BubbleUPnP proxying Tidal hands us a plain HTTP
 * FLAC URL, so that is the shape it is built for.
 *
 * The USB connection must outlive the stream: native wraps the file descriptor
 * but does not own it, so closing early pulls it out from under the transfers.
 */
class HttpStreamPlayback(private val context: Context) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var connection: UsbDeviceConnection? = null
    private val fetching = AtomicBoolean(false)
    private val aac = AacDecoder()

    /**
     * True for formats the native decoders do not handle, which go through
     * MediaCodec instead. Kept as a deny-list rather than an allow-list: an
     * unknown format is more likely to be something the platform can decode
     * than something dr_flac or minimp3 can.
     */
    private fun usePlatformDecoder(mime: String): Boolean {
        val m = mime.lowercase()
        if (m.contains("flac")) return false
        if (m.contains("mpeg") || m.contains("mp3")) return false
        if (m.contains("wav") || m.contains("l16") || m.contains("l24")) return false
        return m.contains("aac") || m.contains("mp4") || m.contains("m4a") ||
               m.contains("ogg") || m.contains("opus") || m.contains("vorbis")
    }

    @Volatile
    var currentUri: String? = null
        private set

    /**
     * Called on the watcher thread when a track reaches its natural end.
     * Controllers poll GetTransportInfo, so if the renderer keeps reporting
     * PLAYING after a track finishes they never advance the playlist.
     */
    @Volatile
    var onTrackFinished: (() -> Unit)? = null

    private var watcher: Thread? = null

    @Volatile
    private var contentLength: Long = -1

    @Volatile
    private var trackDurationSeconds: Int = 0

    /** "fLaC" + metadata blocks, cached so a seek can prepend them. */
    @Volatile
    private var flacHeader: ByteArray? = null

    @Volatile
    private var audioStart: Long = 0

    /** From the server's Content-Type, used when the controller sent no DIDL. */
    @Volatile
    private var lastKnownMime: String = ""

    /**
     * Fetches and caches the FLAC header, and finds where audio actually
     * begins.
     *
     * A decoder starting mid-file cannot work from frame headers alone: FLAC
     * allows bit depth and sample rate to be encoded as "refer to STREAMINFO",
     * so without the header the format is undeterminable and the open fails.
     * Prepending the real header to ranged data solves that, and also keeps the
     * byte-offset estimate honest by excluding metadata (which can be large
     * when a file embeds album art) from the audio length.
     */
    private fun ensureHeader(uri: String): ByteArray? {
        flacHeader?.let { return it }
        return try {
            val conn = (URL(uri).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 15_000
                setRequestProperty("User-Agent", "HiFiRenderer/1.0 DLNADOC/1.50")
                setRequestProperty("Range", "bytes=0-262143")
            }
            val head = conn.inputStream.use { it.readBytes() }
            conn.disconnect()
            if (head.size < 8 || head[0] != 'f'.code.toByte() || head[1] != 'L'.code.toByte() ||
                head[2] != 'a'.code.toByte() || head[3] != 'C'.code.toByte()) {
                Log.w(TAG, "seek: not a native FLAC stream, cannot prepend header")
                return null
            }
            var p = 4
            while (p + 4 <= head.size) {
                val last = (head[p].toInt() and 0x80) != 0
                val len = ((head[p + 1].toInt() and 0xFF) shl 16) or
                          ((head[p + 2].toInt() and 0xFF) shl 8) or
                          (head[p + 3].toInt() and 0xFF)
                p += 4 + len
                if (last) break
            }
            if (p > head.size) {
                Log.w(TAG, "seek: FLAC metadata larger than probe window")
                return null
            }
            audioStart = p.toLong()
            head.copyOfRange(0, p).also {
                flacHeader = it
                Log.i(TAG, "seek: cached ${it.size}-byte FLAC header, audio starts at $audioStart")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "seek: header fetch failed: ${e.message}")
            null
        }
    }

    /**
     * Seeks by re-requesting the stream with an HTTP byte range.
     *
     * The byte offset is estimated from the time fraction, because FLAC is
     * variable bitrate and the exact mapping lives in a seektable we do not
     * have while streaming. The landing point is therefore approximate -- which
     * is how DLNA renderers generally seek, since the alternative is decoding
     * and discarding everything up to the target.
     *
     * Reported position uses the requested time as its base, so the controller
     * shows what the user asked for rather than drifting by the estimate error.
     */
    fun seek(uri: String, seconds: Int, durationSeconds: Int): String {
        val len = contentLength
        val dur = if (durationSeconds > 0) durationSeconds else trackDurationSeconds
        if (len <= 0 || dur <= 0) {
            return """{"ok":false,"message":"Cannot seek: track length unknown."}"""
        }
        val header = ensureHeader(uri)
            ?: return """{"ok":false,"message":"Cannot seek: this stream has no readable FLAC header."}"""

        // Interpolate within the audio portion only; metadata is not audio.
        val audioBytes = len - audioStart
        val offset = (audioStart + audioBytes * (seconds.toDouble() / dur))
            .toLong().coerceIn(audioStart, len - 1)
        Log.i(TAG, "seek to ${seconds}s -> byte $offset of $len (audio from $audioStart, ${dur}s)")
        return play(uri, seekSeconds = seconds, rangeStart = offset,
                    durationSeconds = dur, header = header, mimeHint = lastKnownMime)
    }

    fun play(
        uri: String,
        seekSeconds: Int = 0,
        rangeStart: Long = 0,
        durationSeconds: Int = 0,
        header: ByteArray? = null,
        mimeHint: String = "",
    ): String {
        stop()

        val device = UsbAudioProbe(context).findAudioDevice()
            ?: return """{"ok":false,"message":"No USB audio device connected."}"""
        if (!usbManager.hasPermission(device)) {
            return """{"ok":false,"message":"USB permission not granted. Open the app and probe the DAC once."}"""
        }
        val conn = usbManager.openDevice(device)
            ?: return """{"ok":false,"message":"Could not open the DAC."}"""

        for (i in 0 until device.interfaceCount) {
            val itf = device.getInterface(i)
            if (itf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) {
                conn.claimInterface(itf, true)
            }
        }
        connection = conn

        if (durationSeconds > 0) trackDurationSeconds = durationSeconds
        // The cached header is prepended below, so the decoder always sees a
        // well-formed stream and never needs relaxed (headerless) mode.
        // The decoder is chosen from the MIME type. The controller's DIDL is
        // the better source -- it describes the file, whereas a server's
        // Content-Type is often a generic octet-stream.
        val mime = mimeHint.ifBlank { lastKnownMime }

        if (usePlatformDecoder(mime)) {
            // MediaCodec fetches the URL itself, so the HTTP pipe is unused here.
            currentUri = uri
            var failure: String? = null
            val ok = aac.start(uri, conn.fileDescriptor, seekSeconds) { failure = it }
            if (!ok) {
                stop()
                return """{"ok":false,"message":"${(failure ?: "platform decoder failed").replace("\"", "\\\"")}"}"""
            }
            fetching.set(true)
            startWatcher()
            Log.i(TAG, "stream: $uri via MediaCodec ($mime)")
            return """{"ok":true,"uri":"${uri.replace("\"", "\\\"")}","decoder":"platform"}"""
        }

        val started = NativeBridge.startStream(
            conn.fileDescriptor, seekSeconds, relaxed = false, mime = mime
        )
        if (!started.contains("\"ok\":true")) {
            stop()
            return started
        }

        currentUri = uri
        fetching.set(true)
        thread(name = "http-fetch", isDaemon = true) { fetch(uri, rangeStart, header) }
        startWatcher()
        Log.i(TAG, "stream: fetching $uri")
        return """{"ok":true,"uri":"${uri.replace("\"", "\\\"")}"}"""
    }

    private fun fetch(uri: String, rangeStart: Long, header: ByteArray?) {
        var stream: InputStream? = null
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(uri).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 30_000
                instanceFollowRedirects = true
                // Some DLNA servers behave differently for unknown agents, and
                // a few refuse to stream without a Range header at all.
                setRequestProperty("User-Agent", "HiFiRenderer/1.0 DLNADOC/1.50")
                setRequestProperty("Connection", "close")
                if (rangeStart > 0) setRequestProperty("Range", "bytes=$rangeStart-")
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.e(TAG, "stream: HTTP $code for $uri")
                NativeBridge.endStream()
                return
            }
            // A ranged request answers 206 with only the remaining length, so
            // the full length must come from Content-Range to stay usable for
            // the next seek.
            contentLength = if (rangeStart > 0) {
                conn.getHeaderField("Content-Range")
                    ?.substringAfter('/', "")?.toLongOrNull() ?: contentLength
            } else {
                conn.contentLengthLong
            }
            conn.contentType?.substringBefore(';')?.trim()?.takeIf { it.isNotEmpty() }
                ?.let { lastKnownMime = it }
            Log.i(TAG, "stream: HTTP $code, type=${conn.contentType}, " +
                "len=${conn.contentLengthLong}, total=$contentLength, range=$rangeStart")

            // Give the decoder the real header first so STREAMINFO is known,
            // then the ranged audio. dr_flac resynchronises to the next frame.
            if (header != null) {
                NativeBridge.pushStreamData(header, header.size)
                Log.i(TAG, "stream: prepended ${header.size}-byte FLAC header")
            }

            stream = conn.inputStream
            val buf = ByteArray(32 * 1024)
            var total = 0L
            while (fetching.get()) {
                val n = stream.read(buf)
                if (n < 0) break
                if (n > 0) {
                    total += n
                    // Blocks when the native buffer is full; that backpressure
                    // is what stops a fast server buffering a whole album.
                    if (!NativeBridge.pushStreamData(buf, n)) break
                }
            }
            Log.i(TAG, "stream: fetched $total bytes")
        } catch (e: Throwable) {
            Log.e(TAG, "stream: fetch failed: ${e::class.java.simpleName}: ${e.message}")
        } finally {
            runCatching { stream?.close() }
            runCatching { conn?.disconnect() }
            NativeBridge.endStream()
        }
    }

    /** Real pause: the stream stays open and keeps its place. */
    fun pause() = NativeBridge.setStreamPaused(true)

    fun resume() = NativeBridge.setStreamPaused(false)

    /**
     * Watches for the track ending. The decoder runs ahead of the DAC, so
     * "fetch complete" is not "playback complete" -- only the native engine
     * knows when the last sample has actually gone out.
     */
    private fun startWatcher() {
        watcher = thread(name = "track-watcher", isDaemon = true) {
            while (fetching.get()) {
                Thread.sleep(400)
                if (!fetching.get()) return@thread
                if (NativeBridge.streamFinished()) {
                    Log.i(TAG, "track finished: $currentUri")
                    fetching.set(false)
                    runCatching { onTrackFinished?.invoke() }
                        .onFailure { Log.e(TAG, "onTrackFinished threw: ${it.message}") }
                    return@thread
                }
            }
        }
    }

    fun stop() {
        fetching.set(false)
        aac.stop()
        NativeBridge.stopStream()
        connection?.close()
        connection = null
        currentUri = null
    }

    /** Called when the track changes; the cached header belongs to one file. */
    fun resetHeaderCache() {
        flacHeader = null
        audioStart = 0
        contentLength = -1
    }

    fun status(): String = NativeBridge.streamStatus()
    fun positionSeconds(): Int = NativeBridge.streamPositionSeconds()
}
