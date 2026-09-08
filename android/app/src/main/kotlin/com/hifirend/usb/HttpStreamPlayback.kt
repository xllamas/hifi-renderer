package com.hifirend.usb

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.util.Log
import com.hifirend.NativeBridge
import com.hifirend.RendererState
import org.json.JSONObject
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

private const val TAG = "hifirend"
private const val VOLUME_POLL_MS = 2_000L
private const val VOLUME_SETTLE_MS = 1_500L

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

    /**
     * The device the engine currently has open, or null when it is on Android
     * audio.
     *
     * Needed because a detach broadcast says only that *some* USB device went
     * away, and the phone sits on a powered hub with half a dozen of them.
     * Stopping playback for any of them was wrong in the ordinary case and
     * actively destructive in one particular one: plugging the DAC in makes it
     * enumerate twice, and the detach between the two attaches stopped the
     * track that was about to be moved onto it.
     */
    @Volatile
    var openDeviceKey: String? = null
        private set
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
        if (m.contains("wav") || m.contains("l16") || m.contains("l24") ||
            m.contains("aif")) return false
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

    /**
     * The engine stopped with an error after playback had been reported as
     * started. Configure() runs on the decoder thread once the source's rate
     * and depth are known, so its failures land here rather than in play()'s
     * return value.
     */
    var onPlaybackError: ((String) -> Unit)? = null

    /**
     * The source ran out while the tail is still playing.
     *
     * Returns true if a next track was started, in which case this one hands
     * over seamlessly and the engine is never stopped. False means there was
     * nothing queued, and the tail is left to play out normally.
     */
    var onSourceExhausted: (() -> Boolean)? = null

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

    /**
     * Restarts the current track on a DAC that has just become usable.
     *
     * The engine picks its output when a track starts, so a DAC switched on
     * mid-track changed only what the renderer advertised while the sound
     * stayed on the phone's speaker. From the shelf that reads as the app
     * ignoring the hardware.
     *
     * The track restarts from the beginning rather than continuing where it
     * was. Carrying the position across meant seeking, which needs a known
     * content length and duration and quietly did nothing when either was
     * missing; restarting needs neither and is what was asked for. A few
     * seconds repeated is a small price for the output actually changing.
     *
     * Every path says why, including the ones that decline. The first attempt
     * at this had silent early returns and a test that produced no log line at
     * all -- five possible reasons and no way to tell which, which is the
     * position this project has learned not to argue from.
     */
    fun adoptAttachedDac(reason: String): Boolean {
        val uri = currentUri
        val running = engineRunning
        val output = RendererState.output
        val probe = UsbAudioProbe(context)
        val device = runCatching { probe.findAudioDevice() }.getOrNull()
        val authorised = device != null && usbManager.hasPermission(device)

        if (!running || output != "android" || uri == null || device == null || !authorised) {
            Log.i(TAG, "not moving to the DAC ($reason): playing=$running " +
                "output=$output track=${if (uri == null) "none" else "yes"} " +
                "device=${device?.let { probe.describeForUi(it) } ?: "none"} " +
                "authorised=$authorised")
            return false
        }

        Log.i(TAG, "DAC usable mid-track ($reason): restarting the track on " +
            "${probe.describeForUi(device)}")
        val result = play(uri, durationSeconds = trackDurationSeconds,
                          mimeHint = lastKnownMime)
        if (!result.contains(""""ok":true""")) {
            Log.w(TAG, "could not restart on the DAC: $result")
            return false
        }
        return true
    }

    /**
     * Opens the output device for a *push* source, returning its descriptor.
     *
     * AirPlay does not fetch anything, so it never goes through [play] -- but
     * it needs the same device opened the same way, with the same permission
     * check, the same interface claims and the same fallback to Android audio
     * when there is no DAC. Duplicating that logic is how the two paths would
     * drift; sharing it means [stop] already knows how to close what this
     * opened, and [openDeviceKey] already tells the detach handler which
     * device matters.
     *
     * Returns -1 for "no DAC, use Android audio", which is what the engine
     * expects a descriptor of -1 to mean.
     */
    fun openOutputForPush(): Int {
        val probe = UsbAudioProbe(context)
        val device = probe.findAudioDevice()
        val conn = when {
            device == null -> {
                Log.i(TAG, "no USB audio device; using Android audio")
                null
            }
            !usbManager.hasPermission(device) -> {
                Log.i(TAG, "no USB permission for ${probe.describeForUi(device)}; " +
                    "using Android audio")
                null
            }
            else -> usbManager.openDevice(device).also {
                if (it == null) Log.w(TAG, "could not open the DAC; using Android audio")
            }
        }
        if (conn != null && device != null) {
            for (i in 0 until device.interfaceCount) {
                val itf = device.getInterface(i)
                if (itf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) {
                    conn.claimInterface(itf, true)
                }
            }
        }
        connection = conn
        openDeviceKey = if (conn != null && device != null) probe.deviceKey(device) else null
        return conn?.fileDescriptor ?: -1
    }

    fun play(
        uri: String,
        seekSeconds: Int = 0,
        rangeStart: Long = 0,
        durationSeconds: Int = 0,
        header: ByteArray? = null,
        mimeHint: String = "",
        gapless: Boolean = false,
    ): String {
        // A gapless start must not stop the engine: the previous track's tail
        // is still in the ring and is what covers the time this one needs to
        // open and start decoding.
        if (gapless) retireWatcher() else stop()
        // A new track starts with a clean slate; the engine clears its own
        // error, and a stale one here would be read as this track failing.
        lastEngineError = null
        fetchFailure = null
        engineRunning = false
        RendererState.lastError = null
        RendererState.lastErrorDetail = null

        // No DAC, or one we cannot open, is not a failure: the engine falls
        // back to Android's own output. A file descriptor of -1 is how that is
        // asked for. Everything above here -- decoders, transport, playlist,
        // widget -- behaves identically; only the bit-perfect guarantee is
        // lost, and the engine reports that rather than hiding it.
        val probe = UsbAudioProbe(context)
        val device = probe.findAudioDevice()

        // A gapless change of track must reuse the connection already
        // streaming. Opening a second one and force-claiming the interfaces
        // detaches them from the first, which kills the transfers mid-flight:
        // the first attempt at this produced 14 transfer errors and 107 bad
        // packets at the exact moment of hand-over, and the stream never
        // recovered. The engine keeps the sink bound to the original
        // descriptor, so there is nothing to reopen.
        val existing = connection
        if (gapless && existing != null) {
            Log.i(TAG, "gapless: reusing the open USB connection")
            return startDecoding(uri, existing.fileDescriptor, seekSeconds, rangeStart,
                                 durationSeconds, header, mimeHint, gapless = true)
        }

        val conn = when {
            device == null -> {
                Log.i(TAG, "no USB audio device; using Android audio")
                null
            }
            !usbManager.hasPermission(device) -> {
                Log.i(TAG, "no USB permission for ${probe.describeForUi(device)}; " +
                    "using Android audio")
                null
            }
            else -> usbManager.openDevice(device).also {
                if (it == null) Log.w(TAG, "could not open the DAC; using Android audio")
            }
        }

        if (conn != null && device != null) {
            for (i in 0 until device.interfaceCount) {
                val itf = device.getInterface(i)
                if (itf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) {
                    conn.claimInterface(itf, true)
                }
            }
        }
        connection = conn
        openDeviceKey = if (conn != null && device != null) probe.deviceKey(device) else null
        val fd = conn?.fileDescriptor ?: -1

        return startDecoding(uri, fd, seekSeconds, rangeStart, durationSeconds, header,
                             mimeHint, gapless = gapless)
    }

    /**
     * Starts the decoder and the fetch for [uri] against an already-chosen
     * output. Split out so a gapless change of track can skip the device
     * acquisition entirely and keep the stream that is playing.
     */
    private fun startDecoding(
        uri: String,
        fd: Int,
        seekSeconds: Int,
        rangeStart: Long,
        durationSeconds: Int,
        header: ByteArray?,
        mimeHint: String,
        gapless: Boolean,
    ): String {
        if (durationSeconds > 0) trackDurationSeconds = durationSeconds
        val mime = mimeHint.ifBlank { lastKnownMime }

        if (usePlatformDecoder(mime)) {
            // MediaCodec fetches the URL itself, so the HTTP pipe is unused here.
            currentUri = uri
            var failure: String? = null
            val ok = aac.start(uri, fd, seekSeconds) { failure = it }
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
            fd, seekSeconds, relaxed = false, mime = mime, gapless = gapless
        )
        if (!started.contains("\"ok\":true")) {
            stop()
            return started
        }

        currentUri = uri
        fetching.set(true)
        // The sink is open now, so this is the first moment the DAC's volume
        // can be set at all.
        runCatching { restoreVolume() }
            .onFailure { Log.w(TAG, "volume restore failed: ${it.message}") }
        val fetchGeneration = generation
        thread(name = "http-fetch", isDaemon = true) {
            fetch(uri, rangeStart, header, fetchGeneration)
        }
        startWatcher()
        Log.i(TAG, "stream: fetching $uri")
        return """{"ok":true,"uri":"${uri.replace("\"", "\\\"")}"}"""
    }

    private fun open(target: URL, rangeStart: Long): HttpURLConnection =
        (target.openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            // Same-protocol hops are handled here; a hop that changes protocol
            // is not, and [fetch] picks those up by hand. See there for why.
            instanceFollowRedirects = true
            // Some DLNA servers behave differently for unknown agents, and
            // a few refuse to stream without a Range header at all.
            setRequestProperty("User-Agent", "HiFiRenderer/1.0 DLNADOC/1.50")
            setRequestProperty("Connection", "close")
            if (rangeStart > 0) setRequestProperty("Range", "bytes=$rangeStart-")
        }

    private fun fetch(uri: String, rangeStart: Long, header: ByteArray?, mine: Int) {
        var stream: InputStream? = null
        var conn: HttpURLConnection? = null
        // Where we are actually talking to, which is very often not [uri].
        //
        // A Tidal track through BubbleUPnP arrives as a URL on the controller's
        // own proxy, and that proxy answers 302 to a token-bearing URL on
        // Tidal's CDN:
        //
        //     GET  http://192.168.100.122:57645/proxy/tidal/D0CF....flac
        //     302  http://lgf.audio.tidal.com/mediatracks/...?token=1788...
        //
        // So the host that has to be reachable is not the one the controller
        // named, and until this was tracked a failure reported the controller's
        // address for a fetch that never got near it -- pointing anyone
        // debugging it at the wrong machine.
        var attempting = uri
        try {
            conn = open(URL(uri), rangeStart)
            var code = conn.responseCode

            // Java will not follow a redirect that changes protocol, and says
            // nothing about refusing: it hands back the 3xx as though the
            // server had meant it. An http proxy URL redirecting to an https
            // CDN -- which is the shape of every streaming service behind a
            // local proxy -- would therefore surface as "the server answered
            // HTTP 302", which is true and useless.
            var hops = 0
            while (code in 300..399 && hops < 5) {
                val location = conn!!.getHeaderField("Location") ?: break
                val next = URL(URL(attempting), location)
                Log.i(TAG, "stream: $code redirect to ${next.protocol}://${next.host}")
                conn.disconnect()
                attempting = next.toString()
                conn = open(next, rangeStart)
                code = conn.responseCode
                hops++
            }

            // Java follows same-protocol redirects itself, without a word, so
            // the loop above never sees the common case -- an http proxy URL
            // hopping to an http CDN. The connection does know where it ended
            // up, and that is the only place the real host can be read from.
            runCatching { conn!!.url?.toString() }.getOrNull()
                ?.takeIf { it.isNotBlank() }?.let { attempting = it }
            if (runCatching { URL(attempting).host }.getOrNull()
                != runCatching { URL(uri).host }.getOrNull()) {
                Log.i(TAG, "stream: served by ${URL(attempting).host} " +
                    "after a redirect (the controller named ${URL(uri).host})")
            }
            if (code !in 200..299) {
                Log.e(TAG, "stream: HTTP $code for $attempting")
                noteFetchFailure(mine, "the server answered HTTP $code for this track")
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

            // What the server actually served, as opposed to what the
            // controller said it would. A transcoding server announces itself
            // here: contentFeatures carries the DLNA profile it converted to,
            // and a chunked response with no length is the usual sign that the
            // bytes are being produced on the fly rather than read from a file.
            listOf("Content-Type", "Content-Length", "Content-Range",
                   "transferMode.dlna.org", "contentFeatures.dlna.org",
                   "Transfer-Encoding", "Server", "Accept-Ranges")
                .mapNotNull { h -> conn.getHeaderField(h)?.let { "$h: $it" } }
                .forEach { Log.i(TAG, "served: $it") }

            // Give the decoder the real header first so STREAMINFO is known,
            // then the ranged audio. dr_flac resynchronises to the next frame.
            if (header != null) {
                NativeBridge.pushStreamData(header, header.size)
                Log.i(TAG, "stream: prepended ${header.size}-byte FLAC header")
            }

            stream = conn.inputStream
            val buf = ByteArray(32 * 1024)
            var total = 0L
            while (fetching.get() && generation == mine) {
                val n = stream.read(buf)
                if (n < 0) break
                if (n > 0) {
                    total += n
                    // The generation check is what stops a fetch that outlived
                    // its track from pushing its bytes into the next one's
                    // decoder -- the streams are swapped underneath it, and
                    // the corruption would be silent.
                    if (generation != mine) break
                    // Blocks when the native buffer is full; that backpressure
                    // is what stops a fast server buffering a whole album.
                    if (!NativeBridge.pushStreamData(buf, n)) break
                }
            }
            Log.i(TAG, "stream: fetched $total bytes")
        } catch (e: Throwable) {
            // A redirect Java followed by itself leaves the final URL on the
            // connection, and if the failure happened after that hop it is the
            // address that actually refused us.
            runCatching { conn?.url?.toString() }.getOrNull()
                ?.takeIf { it.isNotBlank() }?.let { attempting = it }
            Log.e(TAG, "stream: fetch failed against $attempting: " +
                "${e::class.java.simpleName}: ${e.message}")
            // Name the host that actually failed. With a proxying controller
            // that is usually not the one the controller advertised, and a
            // message blaming the wrong machine sends the next hour of
            // debugging in the wrong direction.
            val host = runCatching { URL(attempting).host }.getOrNull() ?: "the media server"
            noteFetchFailure(mine, when (e) {
                is java.net.UnknownHostException -> "$host could not be resolved"
                is java.net.SocketTimeoutException -> "$host stopped responding"
                is java.net.ConnectException -> "$host could not be reached"
                else -> "the track could not be fetched from $host " +
                    "(${e::class.java.simpleName})"
            } + ": ${e.message}")
        } finally {
            runCatching { stream?.close() }
            runCatching { conn?.disconnect() }
            NativeBridge.endStream()
        }
    }

    /**
     * Records a fetch failure against the track that was being fetched.
     *
     * The generation check matters after a gapless hand-over: the outgoing
     * track's fetch thread is still alive, and a failure it hits belongs to
     * the track that has already finished, not to the one now playing. Without
     * this, a server dropping at exactly the wrong moment would blame the next
     * track for the previous one's problem.
     */
    private fun noteFetchFailure(mine: Int, reason: String) {
        if (generation != mine) return
        fetchFailure = reason
    }

    /** Real pause: the stream stays open and keeps its place. */
    fun pause() = NativeBridge.setStreamPaused(true)

    fun resume() = NativeBridge.setStreamPaused(false)

    /**
     * Copies engine status into the shared snapshot so the screen can show what
     * the DAC is actually doing, rather than what was requested.
     */
    @Volatile private var engineRunning = false

    /** Whether audio is flowing, through either sink. */
    val isEngineRunning: Boolean get() = engineRunning

    /**
     * Whether the decoder is alive, as distinct from the sink.
     *
     * A gapless change of track leaves the sink running on purpose, so the
     * sink's own flag stopped being a usable proxy for "playback is
     * progressing": a decoder that failed after the hand-over left the stream
     * running and empty, and the transport went on reporting PLAYING over
     * silence -- the exact failure the error reporting exists to prevent.
     */
    @Volatile private var decoding = false

    @Volatile private var lastVolumeReadAt = 0L
    @Volatile private var volumeSetAt = 0L

    /**
     * Whether to re-read the DAC's volume now.
     *
     * Two seconds is plenty to notice someone turning the DAC's own knob, and
     * the settle window after a write keeps a stale read from overwriting a
     * value the user just chose.
     */
    private fun volumeReadDue(): Boolean {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - volumeSetAt < VOLUME_SETTLE_MS) return false
        if (now - lastVolumeReadAt < VOLUME_POLL_MS) return false
        lastVolumeReadAt = now
        return true
    }

    /** Called whenever this app sets the volume, to open the settle window. */
    fun noteVolumeSet() {
        volumeSetAt = android.os.SystemClock.elapsedRealtime()
    }

    @Volatile private var volumeRestored = false

    /** A different DAC must not inherit the level restored for the last one. */
    fun forgetRestoredVolume() {
        volumeRestored = false
        NativeBridge.forgetVolumeLearning()
    }

    /**
     * Puts the DAC at a known level the first time we can talk to it.
     *
     * Otherwise the starting volume is whatever the hardware happens to hold --
     * where it powered up, or, on a device whose volume cannot be read back,
     * its maximum. This app drives real amplifiers, and a first track arriving
     * at full scale can do damage before anyone reaches a control.
     *
     * Once per device rather than once per track, so that a DAC with a working
     * physical knob is not overridden every time a track changes.
     */
    private fun restoreVolume() {
        if (volumeRestored) return
        val wanted = VolumeMemory.remembered(context, RendererState.dacKey)
        if (!NativeBridge.setDacVolume(wanted)) return   // no host volume control
        volumeRestored = true
        RendererState.dacVolume = wanted
        noteVolumeSet()
        Log.i(TAG, "volume: restored to $wanted% for ${RendererState.dacKey}")
    }

    /**
     * The engine's own error, mirrored each poll.
     *
     * Deliberately not read back from RendererState.lastError: that field
     * accumulates the most recent error from anywhere and is never cleared, so
     * a failure on one track would still be sitting there when the next one
     * started and would kill it instantly. The engine clears its error when a
     * stream starts, so mirroring it exactly -- blank included -- is what makes
     * this describe the current track and not the last one.
     */
    @Volatile private var lastEngineError: String? = null

    /**
     * An error that the engine has actually given up on. A message alongside a
     * still-running stream is a transient it recovered from, and treating that
     * as fatal would stop playback that was about to be fine.
     */
    private val engineError: String?
        get() = lastEngineError?.takeIf { !decoding }

    private fun publishEngineState() {
        try {
            val j = JSONObject(NativeBridge.streamStatus())
            RendererState.sourceFormat = j.optString("sourceFormat").takeIf { it.isNotBlank() }
            RendererState.sourceRate = j.optInt("rate")
            RendererState.sourceBits = j.optInt("sourceBits")
            RendererState.channels = j.optInt("channels")
            RendererState.deviceBits = j.optInt("deviceBits")
            RendererState.altSetting = j.optInt("altSetting", -1)
            RendererState.underruns = j.optLong("underruns")
            RendererState.positionSeconds = j.optInt("positionSeconds")
            engineRunning = j.optBoolean("running")
            decoding = j.optBoolean("decoding")
            // Composed by the engine, which is the only layer that sees both
            // the sink and where the samples came from. It is deliberately not
            // re-derived here from `output`: a USB sink carrying a guest's
            // pre-resampled AirPlay stream is not bit-perfect, and that is
            // invisible from this side.
            RendererState.bitPerfect = j.optBoolean("bitPerfect")
            RendererState.senderAltered = j.optBoolean("senderAltered")
            RendererState.output = j.optString("output").takeIf { it.isNotBlank() } ?: "usb"
            RendererState.dacVolumeSupported = j.optBoolean("volumeSupported")
            j.optString("volumeReadback").takeIf { it.isNotBlank() }
                ?.let { RendererState.dacVolumeReadback = it }
            // Read back from the hardware rather than echoing what was set: on
            // a DAC with its own knob the two can differ.
            //
            // Rate limited, and suppressed briefly after we set it. This poll
            // runs every 400 ms, which is far more often than a volume control
            // changes, and each read is a control transfer to the DAC. Worse,
            // polling that fast fights the UI: the slider shows the value the
            // user just chose, a read that crossed with the write returns the
            // old one, and the slider jumps back before settling -- which looks
            // exactly like the app ignoring the user.
            if (RendererState.dacVolumeSupported && volumeReadDue()) {
                NativeBridge.getDacVolume().takeIf { it >= 0 }
                    ?.let { RendererState.dacVolume = it }
            }
            lastEngineError = j.optString("error").takeIf { it.isNotBlank() }
            lastEngineError?.let {
                val described = com.hifirend.upnp.Problem.describe(it)
                RendererState.lastError = described.code
                RendererState.lastErrorArgs = described.args
                RendererState.lastErrorDetail = described.detail
            }
        } catch (_: Throwable) {
            // Status is telemetry; never let it disturb playback.
        }
    }

    /**
     * Watches for the track ending. The decoder runs ahead of the DAC, so
     * "fetch complete" is not "playback complete" -- only the native engine
     * knows when the last sample has actually gone out.
     */
    /**
     * Retires the current watcher without stopping playback.
     *
     * A gapless change of track leaves the engine running, so the old watcher
     * has to be told to stand down some other way -- otherwise two of them
     * poll the same engine and both try to advance the queue.
     */
    private fun retireWatcher() {
        generation++
        fetching.set(false)
    }

    @Volatile private var generation = 0

    /**
     * Why the fetch stopped, when it stopped for a reason of its own.
     *
     * The decoder cannot tell a server that vanished from a file that was
     * never FLAC: both reach it as a stream that ended early, so it reports
     * what it sees -- "not a decodable FLAC stream". That message then went to
     * the screen and told someone whose media server had dropped off the
     * network that their track was in an unsupported format, which is both
     * wrong and sends them looking in the wrong place. The fetch knows the
     * real reason; this is where it is kept so it can outrank the decoder's
     * downstream complaint.
     */
    @Volatile private var fetchFailure: String? = null

    private fun startWatcher() {
        val mine = generation
        watcher = thread(name = "track-watcher", isDaemon = true) {
            var handedOver = false
            while (fetching.get() && generation == mine) {
                Thread.sleep(200)
                if (!fetching.get() || generation != mine) return@thread
                publishEngineState()

                // The window for a seamless change of track: the decoder is
                // out of source but the ring still holds the tail. Ask once.
                if (!handedOver && NativeBridge.streamReadyForNext()) {
                    handedOver = true
                    val advanced = runCatching { onSourceExhausted?.invoke() ?: false }
                        .onFailure { Log.e(TAG, "onSourceExhausted threw: ${it.message}") }
                        .getOrDefault(false)
                    if (advanced) {
                        Log.i(TAG, "handed over to the next track without stopping")
                        return@thread
                    }
                }

                // An engine that stopped while we still believe we are playing
                // has failed -- most often because the DAC refused the format
                // or the alt-setting. Silence with a PLAYING transport is the
                // worst possible way to report that.
                // A failed fetch is the cause; whatever the decoder made of
                // the truncated stream is only the symptom. Reporting the
                // symptom sends people looking at their files when the problem
                // is their network.
                val failure = fetchFailure ?: engineError
                if (failure != null) {
                    Log.e(TAG, "engine stopped with error: $failure")
                    fetching.set(false)
                    runCatching { onPlaybackError?.invoke(failure) }
                        .onFailure { Log.e(TAG, "onPlaybackError threw: ${it.message}") }
                    return@thread
                }

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
        openDeviceKey = null
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
