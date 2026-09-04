package com.hifirend

/**
 * Single entry point to libhifirend.so.
 *
 * M0 only proves the library loads and links. The USB engine hangs off this
 * object from M1 onward, so keep all JNI declarations here rather than
 * scattering `external fun` across the codebase.
 */
object NativeBridge {

    /** Null when the native library failed to load; the reason is kept for the UI. */
    val loadError: String? = try {
        System.loadLibrary("hifirend")
        null
    } catch (e: UnsatisfiedLinkError) {
        e.message ?: "UnsatisfiedLinkError"
    }

    val isLoaded: Boolean get() = loadError == null

    private external fun nativeSelfTest(): String

    private external fun nativeProbeUsbDevice(fd: Int): String

    private external fun nativePlayWav(fd: Int, path: String, loop: Boolean): String

    private external fun nativeStopPlayback()

    private external fun nativePlaybackStatus(): String

    private external fun nativeStartStream(fd: Int, seekSeconds: Int, relaxed: Boolean, mime: String, gapless: Boolean): String
    private external fun nativePushStreamData(data: ByteArray, len: Int): Boolean
    private external fun nativeEndStream()
    private external fun nativeStopStream()
    private external fun nativeStreamStatus(): String
    private external fun nativeStreamPositionSeconds(): Int
    private external fun nativeSetStreamPaused(paused: Boolean)
    private external fun nativeStreamFinished(): Boolean
    private external fun nativeStreamReadyForNext(): Boolean
    private external fun nativeGetDacVolume(): Int
    private external fun nativeSetDacVolume(percent: Int): Boolean
    private external fun nativeForgetVolumeLearning()
    private external fun nativeStartPcmStream(fd: Int, rate: Int, channels: Int, seekSeconds: Int): String
    private external fun nativePushPcm(data: ByteArray, len: Int): Boolean
    private external fun nativePcmEndOfStream()

    /** ABI, libusb version and Oboe link status, or the load failure. */
    fun selfTest(): String = loadError?.let { "native library failed to load: $it" } ?: nativeSelfTest()

    /**
     * Runs the UAC capability probe over an open usbfs descriptor. The fd stays
     * owned by the caller's UsbDeviceConnection; native only wraps it.
     */
    fun probeUsbDevice(fd: Int): String =
        loadError?.let { "native library failed to load: $it" } ?: nativeProbeUsbDevice(fd)

    /** Starts bit-perfect playback of a WAV file. The fd stays owned by the caller. */
    fun playWav(fd: Int, path: String, loop: Boolean): String =
        loadError?.let { """{"ok":false,"message":"native library failed to load: $it"}""" }
            ?: nativePlayWav(fd, path, loop)

    fun stopPlayback() {
        if (isLoaded) nativeStopPlayback()
    }

    fun playbackStatus(): String =
        loadError?.let { """{"running":false}""" } ?: nativePlaybackStatus()

    /** Opens the DAC and starts a decoder waiting for bytes. */
    fun startStream(
        fd: Int,
        seekSeconds: Int = 0,
        relaxed: Boolean = false,
        mime: String = "",
        gapless: Boolean = false,
    ): String =
        loadError?.let { """{"ok":false,"message":"native library failed to load"}""" }
            ?: nativeStartStream(fd, seekSeconds, relaxed, mime, gapless)

    fun pushStreamData(data: ByteArray, len: Int): Boolean =
        if (isLoaded) nativePushStreamData(data, len) else false

    fun endStream() { if (isLoaded) nativeEndStream() }
    fun stopStream() { if (isLoaded) nativeStopStream() }

    fun streamStatus(): String =
        loadError?.let { """{"running":false}""" } ?: nativeStreamStatus()

    fun streamPositionSeconds(): Int = if (isLoaded) nativeStreamPositionSeconds() else 0

    /**
     * The decoder has run out of source while the tail is still playing.
     *
     * The window in which the next track can be started without a gap. It
     * opens well before [streamFinished], which is only true once the ring has
     * drained and the output has already gone quiet.
     */
    fun streamReadyForNext(): Boolean = if (isLoaded) nativeStreamReadyForNext() else false

    fun setStreamPaused(paused: Boolean) { if (isLoaded) nativeSetStreamPaused(paused) }

    /** True once the track reached its natural end rather than being stopped. */
    fun streamFinished(): Boolean = if (isLoaded) nativeStreamFinished() else false

    /** Opens the DAC for PCM decoded by the platform (MediaCodec). */
    fun startPcmStream(fd: Int, rate: Int, channels: Int, seekSeconds: Int): String =
        loadError?.let { """{"ok":false,"message":"native library failed to load"}""" }
            ?: nativeStartPcmStream(fd, rate, channels, seekSeconds)

    fun pushPcm(data: ByteArray, len: Int): Boolean =
        if (isLoaded) nativePushPcm(data, len) else false

    fun pcmEndOfStream() { if (isLoaded) nativePcmEndOfStream() }

    /** Volume the DAC itself reports, or -1 when it has no volume control. */
    fun getDacVolume(): Int = if (isLoaded) nativeGetDacVolume() else -1

    /**
     * Discards what was learned about the previous DAC's volume behaviour --
     * whether it reports honestly, and what it was last set to. Those facts
     * describe a device, so they outlive a stream but must not outlive a
     * change of device.
     */
    fun forgetVolumeLearning() {
        if (isLoaded) nativeForgetVolumeLearning()
    }

    fun setDacVolume(percent: Int): Boolean =
        if (isLoaded) nativeSetDacVolume(percent) else false
}
