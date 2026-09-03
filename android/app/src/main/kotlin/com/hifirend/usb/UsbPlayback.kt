package com.hifirend.usb

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.util.Log
import com.hifirend.NativeBridge

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
    private var connection: UsbDeviceConnection? = null

    fun play(path: String, loop: Boolean): String {
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
        val result = NativeBridge.playWav(conn.fileDescriptor, path, loop)
        if (!result.contains("\"ok\":true")) stop()
        return result
    }

    fun stop() {
        NativeBridge.stopPlayback()
        connection?.close()
        connection = null
    }

    fun status(): String = NativeBridge.playbackStatus()
}
