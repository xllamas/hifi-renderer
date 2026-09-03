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

    private external fun nativeStartStream(fd: Int): String
    private external fun nativePushStreamData(data: ByteArray, len: Int): Boolean
    private external fun nativeEndStream()
    private external fun nativeStopStream()
    private external fun nativeStreamStatus(): String
    private external fun nativeStreamPositionSeconds(): Int

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
    fun startStream(fd: Int): String =
        loadError?.let { """{"ok":false,"message":"native library failed to load"}""" }
            ?: nativeStartStream(fd)

    fun pushStreamData(data: ByteArray, len: Int): Boolean =
        if (isLoaded) nativePushStreamData(data, len) else false

    fun endStream() { if (isLoaded) nativeEndStream() }
    fun stopStream() { if (isLoaded) nativeStopStream() }

    fun streamStatus(): String =
        loadError?.let { """{"running":false}""" } ?: nativeStreamStatus()

    fun streamPositionSeconds(): Int = if (isLoaded) nativeStreamPositionSeconds() else 0
}
