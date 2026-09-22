package com.hifirend

/**
 * Process-wide snapshot of what the renderer is doing.
 *
 * The service owns playback and must keep running with no UI at all, so the
 * screen cannot own this state — it reads it. Both live in the same process,
 * which is why a singleton is enough and no binder is involved.
 *
 * Everything is @Volatile and written from jUPnP, decoder and USB threads, so
 * reads are cheap and never block the audio path.
 */
object RendererState {

    @Volatile var rendererName: String = "HiFi Renderer"

    @Volatile var transportState: String = "NO_MEDIA_PRESENT"
    @Volatile var title: String? = null
    @Volatile var artist: String? = null
    @Volatile var album: String? = null
    @Volatile var albumArtUri: String? = null
    @Volatile var durationSeconds: Int = 0
    @Volatile var positionSeconds: Int = 0

    /** Source format as decoded, e.g. FLAC / MP3 / AAC. */
    @Volatile var sourceFormat: String? = null
    @Volatile var sourceRate: Int = 0
    @Volatile var sourceBits: Int = 0
    @Volatile var channels: Int = 0

    /** What the DAC was actually configured to. */
    @Volatile var deviceBits: Int = 0
    @Volatile var altSetting: Int = -1

    @Volatile var dacName: String? = null

    /** Stable vendor:product key for the selected DAC; keys its remembered volume. */
    @Volatile var dacKey: String? = null

    /**
     * Every rate the selected DAC can clock. Empty when unknown, in which case
     * nothing may be refused on the strength of it.
     */
    @Volatile var dacRates: List<Int> = emptyList()
    @Volatile var dacConnected: Boolean = false

    /** How many USB audio devices are attached; more than one needs a choice. */
    @Volatile var dacCount: Int = 0

    /**
     * True only when samples reach the DAC unaltered, end to end. Lossy
     * sources are still bit-perfect in the sense that matters here -- nothing
     * is resampled or attenuated after decoding -- but a fallback path is not,
     * and neither is anything a remote sender pre-processed.
     */
    @Volatile var bitPerfect: Boolean = false

    /**
     * True when the audio was already resampled or attenuated before it
     * reached this renderer, which today means an AirPlay guest.
     *
     * Separate from [bitPerfect] because the screen owes the owner more than a
     * missing tick. Losing the tick is equally consistent with the fallback
     * output, with nothing playing, and with a guest streaming -- and only the
     * last of those is a working, deliberate, non-bit-perfect path. Saying
     * nothing would let the three blur together, which is the one thing the
     * badge exists to prevent.
     */
    @Volatile var senderAltered: Boolean = false

    /**
     * Who is streaming to us, when that could be worked out, for the screen to
     * name in place of a track it does not know.
     *
     * Only ever a real name. AirPlay 1 sends no sender name in its headers, so
     * this is resolved the long way round -- see [com.hifirend.airplay
     * .DacpSenderName] -- and comes back empty often enough that the screen
     * must read perfectly well without it.
     */
    @Volatile var senderName: String? = null

    /** Which output is carrying audio: "usb" or "android". */
    @Volatile var output: String = "usb"

    /**
     * How many tracks are in the renderer's own playlist, and where in it we
     * are (1-based; 0 when nothing is current).
     *
     * Only the OpenHome source has a playlist to be at a position in. The DLNA
     * source is told one track at a time and genuinely does not know what comes
     * next, so the screen must not offer to skip through a list that is not
     * there -- [playlistLength] is 0 then, and the buttons stay away.
     */
    @Volatile var playlistLength: Int = 0
    @Volatile var playlistPosition: Int = 0

    /** True when repeat is on, which makes next and previous always available. */
    @Volatile var playlistRepeat: Boolean = false

    /**
     * Seen: music playing while the panel stayed dark. Only the vendor's
     * background-activity permission fixes it, and only the user can grant it.
     */
    @Volatile var screenWakeRefused: Boolean = false

    /** Percent as reported by the DAC, or -1 when it exposes no volume control. */
    @Volatile var dacVolume: Int = -1
    @Volatile var dacVolumeSupported: Boolean = false

    /**
     * Whether the DAC reports its own volume back: trusted | untrusted |
     * unknown. A device that accepts a volume but always answers with its
     * maximum cannot be polled, so its physical knob goes unnoticed -- which
     * the screen should say rather than quietly showing a stale number.
     */
    @Volatile var dacVolumeReadback: String = "unknown"

    @Volatile var underruns: Long = 0

    /**
     * Why the last track did not play, in words meant for the screen. The
     * A *code* naming the sentence, not the sentence: the wording lives in
     * lib/l10n so it exists in every language the app ships in. The
     * engine's own wording is kept in [lastErrorDetail] rather than shown as
     * the headline -- see [com.hifirend.upnp.Problem].
     */
    @Volatile var lastError: String? = null

    /**
     * Values filling the placeholders in [lastError]'s sentence, in order.
     *
     * Integers because every parameterised failure counts something: a sample
     * rate in hertz, a number of tracks. They are formatted where they are
     * shown, not here, since only the screen knows the reader's conventions.
     */
    @Volatile var lastErrorArgs: List<Int> = emptyList()

    /** The technical message behind [lastError], or null when there is none. */
    @Volatile var lastErrorDetail: String? = null

    /**
     * What went wrong with the last track, when [lastError] is a summary
     * rather than a reason -- "stopped after 3 tracks in a row could not be
     * played" says the source looks gone, but not *why* each one failed. A
     * refusal before fetching has no engine detail to fall back on, so without
     * this the screen had nothing to say about the cause at all.
     */
    @Volatile var lastErrorCause: String? = null
    @Volatile var lastErrorCauseArgs: List<Int> = emptyList()

    /**
     * Puts [headline] on the screen, with [cause] beneath it when the headline
     * is a summary. Null clears it. Every field is set together, so no writer
     * can leave a previous failure's cause or arguments behind.
     */
    fun report(
        headline: com.hifirend.upnp.Problem.Described?,
        cause: com.hifirend.upnp.Problem.Described? = null,
    ) {
        lastError = headline?.code
        lastErrorArgs = headline?.args ?: emptyList()
        lastErrorDetail = cause?.detail ?: headline?.detail
        lastErrorCause = cause?.code
        lastErrorCauseArgs = cause?.args ?: emptyList()
    }

    val isPlaying: Boolean get() = transportState == "PLAYING"

    /** e.g. "FLAC 24/96" — what the spec asks the main screen to show. */
    fun formatBadge(): String? {
        val f = sourceFormat ?: return null
        if (sourceRate <= 0) return f
        val khz = sourceRate / 1000.0
        val rateText = if (khz == khz.toInt().toDouble()) "${khz.toInt()}" else "%.1f".format(khz)
        return if (sourceBits > 0) "$f $sourceBits/$rateText" else "$f $rateText kHz"
    }

    /**
     * Forgets what the engine was carrying, while keeping which track it was.
     *
     * The format badge describes a stream that is *running*. Once playback
     * stops there is no stream, and leaving "FLAC 24/96 — bit-perfect" on the
     * screen makes a claim about a DAC that is now idle. That is the one claim
     * this app may not make loosely: it exists to show when the path is
     * bit-perfect, so a badge that outlives the audio undermines the only
     * thing it is for.
     *
     * The track identity is deliberately left alone. A stop that followed a
     * failure still has to say which track failed.
     */
    fun clearFormat() {
        sourceFormat = null; sourceRate = 0; sourceBits = 0; channels = 0
        deviceBits = 0; altSetting = -1; bitPerfect = false; output = "usb"
        senderAltered = false
        positionSeconds = 0
    }

    fun clearTrack() {
        title = null; artist = null; album = null; albumArtUri = null
        durationSeconds = 0; senderName = null
        clearFormat()
    }

    private fun q(s: String?): String =
        if (s == null) "null" else "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    fun toJson(): String = buildString {
        append("{")
        append("\"rendererName\":").append(q(rendererName))
        append(",\"transportState\":").append(q(transportState))
        append(",\"title\":").append(q(title))
        append(",\"artist\":").append(q(artist))
        append(",\"album\":").append(q(album))
        append(",\"albumArtUri\":").append(q(albumArtUri))
        append(",\"durationSeconds\":").append(durationSeconds)
        append(",\"positionSeconds\":").append(positionSeconds)
        append(",\"formatBadge\":").append(q(formatBadge()))
        append(",\"sourceFormat\":").append(q(sourceFormat))
        append(",\"sourceRate\":").append(sourceRate)
        append(",\"sourceBits\":").append(sourceBits)
        append(",\"channels\":").append(channels)
        append(",\"deviceBits\":").append(deviceBits)
        append(",\"altSetting\":").append(altSetting)
        append(",\"dacName\":").append(q(dacName))
        append(",\"dacConnected\":").append(dacConnected)
        append(",\"dacCount\":").append(dacCount)
        append(",\"bitPerfect\":").append(bitPerfect)
        append(",\"senderAltered\":").append(senderAltered)
        append(",\"senderName\":").append(q(senderName))
        append(",\"output\":").append(q(output))
        append(",\"playlistLength\":").append(playlistLength)
        append(",\"playlistPosition\":").append(playlistPosition)
        append(",\"playlistRepeat\":").append(playlistRepeat)
        append(",\"dacVolume\":").append(dacVolume)
        append(",\"dacVolumeSupported\":").append(dacVolumeSupported)
        append(",\"dacVolumeReadback\":").append(q(dacVolumeReadback))
        append(",\"underruns\":").append(underruns)
        append(",\"lastError\":").append(q(lastError))
        append(",\"lastErrorArgs\":").append(lastErrorArgs.joinToString(",", "[", "]"))
        append(",\"lastErrorDetail\":").append(q(lastErrorDetail))
        append(",\"lastErrorCause\":").append(q(lastErrorCause))
        append(",\"lastErrorCauseArgs\":").append(lastErrorCauseArgs.joinToString(",", "[", "]"))
        append("}")
    }
}
