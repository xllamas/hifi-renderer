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

    /** ABI, libusb version and Oboe link status, or the load failure. */
    fun selfTest(): String = loadError?.let { "native library failed to load: $it" } ?: nativeSelfTest()

    /**
     * Runs the UAC capability probe over an open usbfs descriptor. The fd stays
     * owned by the caller's UsbDeviceConnection; native only wraps it.
     */
    fun probeUsbDevice(fd: Int): String =
        loadError?.let { "native library failed to load: $it" } ?: nativeProbeUsbDevice(fd)
}
