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
    @Volatile var dacConnected: Boolean = false

    /**
     * True only when samples reach the DAC unaltered. Lossy sources are still
     * bit-perfect in the sense that matters here -- nothing is resampled or
     * attenuated after decoding -- but a fallback path would not be.
     */
    @Volatile var bitPerfect: Boolean = false

    /** Percent as reported by the DAC, or -1 when it exposes no volume control. */
    @Volatile var dacVolume: Int = -1
    @Volatile var dacVolumeSupported: Boolean = false

    @Volatile var underruns: Long = 0
    @Volatile var lastError: String? = null

    val isPlaying: Boolean get() = transportState == "PLAYING"

    /** e.g. "FLAC 24/96" — what the spec asks the main screen to show. */
    fun formatBadge(): String? {
        val f = sourceFormat ?: return null
        if (sourceRate <= 0) return f
        val khz = sourceRate / 1000.0
        val rateText = if (khz == khz.toInt().toDouble()) "${khz.toInt()}" else "%.1f".format(khz)
        return if (sourceBits > 0) "$f $sourceBits/$rateText" else "$f $rateText kHz"
    }

    fun clearTrack() {
        title = null; artist = null; album = null; albumArtUri = null
        durationSeconds = 0; positionSeconds = 0
        sourceFormat = null; sourceRate = 0; sourceBits = 0; channels = 0
        deviceBits = 0; altSetting = -1; bitPerfect = false
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
        append(",\"bitPerfect\":").append(bitPerfect)
        append(",\"dacVolume\":").append(dacVolume)
        append(",\"dacVolumeSupported\":").append(dacVolumeSupported)
        append(",\"underruns\":").append(underruns)
        append(",\"lastError\":").append(q(lastError))
        append("}")
    }
}
