package com.hifirend.usb

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.PowerManager
import android.util.Log
import com.hifirend.NativeBridge
import kotlin.concurrent.thread

private const val TAG = "hifirend"

/**
 * Holds the USB connection open for the lifetime of playback.
 *
 * The native sink wraps the file descriptor but does not own it, so the
 * connection must outlive the stream -- closing it early pulls the descriptor
 * out from under the isochronous transfers.
 */
class UsbPlayback(private val context: Context) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var connection: UsbDeviceConnection? = null

    // Held only while streaming. Without it the CPU can idle mid-transfer and
    // the DAC starves -- the isochronous engine has no way to catch up.
    private var wakeLock: PowerManager.WakeLock? = null

    /** Feeds a picked file into the streaming engine. */
    private var pump: Thread? = null
    @Volatile private var pumping = false

    fun play(path: String, loop: Boolean): String =
        onOpenDac { fd -> NativeBridge.playWav(fd, path, loop) }

    /**
     * Streams a generated tone, for the rate sweep.
     *
     * [bits] is the source depth, which is what selects the alt-setting; the
     * sweep passes a depth the DAC declared rather than a fixed one, because
     * asking a 16-bit device for 24 fails at configure and would be reported as
     * the rate failing.
     */
    fun playTone(rate: Int, bits: Int, channels: Int, hz: Int): String =
        onOpenDac { fd -> NativeBridge.playTone(fd, rate, bits, channels, hz) }

    /**
     * Plays one of the user's own files, to answer "does my actual library
     * play cleanly".
     *
     * Routed through the streaming engine rather than the file player, because
     * that is where the decoders are: the file player only knows WAV, and a
     * real library is FLAC. The bytes come from the content resolver instead of
     * a socket, which is the only difference that matters -- pushStreamData
     * blocks when the native ring is full, so a local file applies the same
     * backpressure a slow server would and cannot buffer itself into memory.
     */
    fun playFile(uri: String, mime: String): String =
        onOpenDac { fd ->
            val result = NativeBridge.startStream(fd, mime = mime)
            if (result.contains("\"ok\":true")) pumpFile(Uri.parse(uri))
            result
        }

    /** Stream health for [playFile]; the file player's counters are separate. */
    fun fileStatus(): String = NativeBridge.streamStatus()

    private fun pumpFile(uri: Uri) {
        pumping = true
        pump = thread(name = "file-source") {
            var total = 0L
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    val buf = ByteArray(32 * 1024)
                    while (pumping) {
                        val n = input.read(buf)
                        if (n < 0) break
                        if (n > 0) {
                            total += n
                            if (!NativeBridge.pushStreamData(buf, n)) break
                        }
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "file source: ${e::class.java.simpleName}: ${e.message}")
            } finally {
                NativeBridge.endStream()
                Log.i(TAG, "file source: pushed $total bytes")
            }
        }
    }

    /**
     * Opens and claims the DAC, runs [body] against its descriptor, and tears
     * the whole thing down again if the engine did not take.
     *
     * The connection must outlive the stream -- native wraps the descriptor but
     * does not own it -- so it is held here rather than by the caller.
     */
    private inline fun onOpenDac(body: (Int) -> String): String {
        stop()

        val probe = UsbAudioProbe(context)
        val device = probe.findAudioDevice()
            ?: return """{"ok":false,"message":"No USB audio device connected."}"""
        if (!usbManager.hasPermission(device)) {
            return """{"ok":false,"message":"USB permission not granted yet. Probe the DAC first."}"""
        }

        val conn = usbManager.openDevice(device)
            ?: return """{"ok":false,"message":"Could not open the DAC."}"""

        // Claim both audio interfaces with force=true so the kernel's
        // snd-usb-audio driver lets go. Without this the alt-setting switch and
        // the clock rate request both fail.
        for (i in 0 until device.interfaceCount) {
            val itf = device.getInterface(i)
            if (itf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) {
                val ok = conn.claimInterface(itf, true)
                Log.i(TAG, "claim if=${itf.id} alt=${itf.alternateSetting} -> $ok")
            }
        }

        connection = conn
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "hifirend:playback").apply {
            setReferenceCounted(false)
            acquire(4 * 60 * 60 * 1000L)  // bounded so a leak cannot drain the battery
        }
        val result = body(conn.fileDescriptor)
        if (!result.contains("\"ok\":true")) stop()
        return result
    }

    fun stop() {
        // Both engines, because this owns the connection either of them wrapped
        // and neither knows about the other. Stopping the stream is also what
        // unblocks a pump thread parked in pushStreamData waiting for ring
        // space that is never going to appear.
        pumping = false
        NativeBridge.stopPlayback()
        NativeBridge.stopStream()
        pump?.join(2_000)
        pump = null
        connection?.close()
        connection = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    fun status(): String = NativeBridge.playbackStatus()
}
