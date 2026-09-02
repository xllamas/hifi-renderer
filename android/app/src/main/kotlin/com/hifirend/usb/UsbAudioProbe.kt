package com.hifirend.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import com.hifirend.NativeBridge
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

private const val TAG = "hifirend"
private const val ACTION_USB_PERMISSION = "com.hifirend.USB_PERMISSION"

/**
 * M1: find an attached USB audio device, get permission, hand its file
 * descriptor to the native prober.
 *
 * Device selection is by USB *class*, never by VID/PID -- the app has to work
 * with DACs we do not own, so anything advertising the audio class is a
 * candidate.
 */
class UsbAudioProbe(private val context: Context) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

    /** Every attached device, annotated with whether it looks like a DAC. */
    fun listDevices(): String = buildString {
        val devices = usbManager.deviceList.values
        appendLine("attached USB devices: ${devices.size}")
        if (devices.isEmpty()) {
            appendLine("  (none -- check the OTG cable and that the DAC is powered)")
        }
        for (d in devices) {
            appendLine(describe(d))
        }
    }

    private fun describe(d: UsbDevice): String = buildString {
        appendLine("  %04x:%04x  %s %s".format(d.vendorId, d.productId,
            d.manufacturerName ?: "?", d.productName ?: "?"))
        appendLine("    class=${d.deviceClass} interfaces=${d.interfaceCount} audio=${isAudioDevice(d)}")
        for (i in 0 until d.interfaceCount) {
            val itf = d.getInterface(i)
            appendLine("    if=${itf.id} alt=${itf.alternateSetting} " +
                "class=${itf.interfaceClass} sub=${itf.interfaceSubclass} eps=${itf.endpointCount}")
        }
    }

    fun isAudioDevice(d: UsbDevice): Boolean {
        if (d.deviceClass == UsbConstants.USB_CLASS_AUDIO) return true
        for (i in 0 until d.interfaceCount) {
            if (d.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_AUDIO) return true
        }
        return false
    }

    fun findAudioDevice(): UsbDevice? = usbManager.deviceList.values.firstOrNull { isAudioDevice(it) }

    /**
     * Opens the device and runs the native probe. Requests permission first if
     * we do not already hold it; the user sees a system dialog.
     */
    suspend fun probe(): String {
        val device = findAudioDevice()
            ?: return listDevices() + "\nno USB audio device found"

        if (!usbManager.hasPermission(device)) {
            Log.i(TAG, "requesting USB permission for ${device.deviceName}")
            if (!requestPermission(device)) {
                return listDevices() + "\nUSB permission denied by user"
            }
        }

        val connection = usbManager.openDevice(device)
            ?: return listDevices() + "\nopenDevice failed (permission or device gone)"

        // The AudioControl interface must be taken away from the kernel's
        // snd-usb-audio driver before class control transfers will work --
        // without this, the UAC2 clock GET_RANGE (the only way to learn a UAC2
        // device's real sample rates) fails with LIBUSB_ERROR_IO.
        // force=true is what performs the kernel detach.
        val control = (0 until device.interfaceCount)
            .map { device.getInterface(it) }
            .firstOrNull {
                it.interfaceClass == UsbConstants.USB_CLASS_AUDIO && it.interfaceSubclass == 1
            }
        var claimed = false
        if (control != null) {
            claimed = connection.claimInterface(control, true)
            Log.i(TAG, "claimInterface(AudioControl if=${control.id}, force=true) -> $claimed")
        }

        return try {
            val report = NativeBridge.probeUsbDevice(connection.fileDescriptor)
            buildString {
                append(listDevices())
                appendLine("AudioControl claimed: $claimed" +
                    if (!claimed) " (clock rate query will fail)" else "")
                append(report)
            }
        } finally {
            // Release so the kernel driver can rebind; otherwise the DAC stays
            // detached from system audio after a probe.
            if (claimed && control != null) connection.releaseInterface(control)
            // The native side wrapped this fd but does not own it.
            connection.close()
        }
    }

    private suspend fun requestPermission(device: UsbDevice): Boolean =
        suspendCancellableCoroutine { cont ->
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    if (intent.action != ACTION_USB_PERMISSION) return
                    context.unregisterReceiver(this)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    Log.i(TAG, "USB permission granted=$granted")
                    if (cont.isActive) cont.resume(granted)
                }
            }
            val filter = IntentFilter(ACTION_USB_PERMISSION)
            // Required from API 34; the broadcast originates from our own
            // PendingIntent, so it is never externally exported.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }

            val pi = PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_USB_PERMISSION).setPackage(context.packageName),
                PendingIntent.FLAG_IMMUTABLE
            )
            usbManager.requestPermission(device, pi)

            cont.invokeOnCancellation { runCatching { context.unregisterReceiver(receiver) } }
        }
}
