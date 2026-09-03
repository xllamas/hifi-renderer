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

    private companion object {
        const val PREFS_USB = "hifirend_usb"
        const val KEY_PREFERRED = "preferred_dac"
    }

    private fun jsonString(s: String?): String {
        if (s == null) return "null"
        val b = StringBuilder("\"")
        for (c in s) {
            when {
                c == '"' -> b.append("\\\"")
                c == '\\' -> b.append("\\\\")
                c.code < 0x20 -> b.append("\\u%04x".format(c.code))
                else -> b.append(c)
            }
        }
        return b.append('"').toString()
    }

    private fun failure(code: String, message: String): String =
        """{"ok":false,"error":${jsonString(code)},"message":${jsonString(message)}}"""

    fun isAudioDevice(d: UsbDevice): Boolean {
        if (d.deviceClass == UsbConstants.USB_CLASS_AUDIO) return true
        for (i in 0 until d.interfaceCount) {
            if (d.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_AUDIO) return true
        }
        return false
    }

    /**
     * Every attached USB audio device, in a stable order.
     *
     * A renderer is rarely alone on the bus: a hub carrying power and Ethernet
     * is the normal way to run one, and someone comparing two DACs will have
     * both plugged in. Sorting by key keeps the list from reshuffling between
     * reads, which would make the settings list jump around.
     */
    fun listAudioDevices(): List<UsbDevice> =
        usbManager.deviceList.values.filter { isAudioDevice(it) }.sortedBy { deviceKey(it) }

    /**
     * Stable identity for a DAC across reconnects and reboots.
     *
     * The device node (/dev/bus/usb/001/003) is renumbered on every enumeration
     * so it cannot be a preference key. Serial number distinguishes two
     * identical DACs, but reading it needs permission, so vendor:product is the
     * fallback -- imperfect only in the rare case of two of the same model.
     */
    fun deviceKey(d: UsbDevice): String {
        val serial = try {
            if (usbManager.hasPermission(d)) d.serialNumber else null
        } catch (_: Throwable) {
            null
        }
        return "%04x:%04x:%s".format(d.vendorId, d.productId, serial ?: "-")
    }

    /**
     * A readable name for the DAC.
     *
     * Many devices repeat the manufacturer inside the product string -- the
     * reference DAC reports "SMSL" and "SMSL USB AUDIO" -- so naively joining
     * them yields "SMSL SMSL USB AUDIO".
     */
    fun describeForUi(d: UsbDevice): String {
        val maker = d.manufacturerName?.trim().orEmpty()
        val product = d.productName?.trim().orEmpty()
        val name = when {
            product.isEmpty() -> maker
            maker.isEmpty() -> product
            product.startsWith(maker, ignoreCase = true) -> product
            else -> "$maker $product"
        }
        return name.ifBlank { "USB audio device %04x:%04x".format(d.vendorId, d.productId) }
    }

    private fun prefs() = context.getSharedPreferences(PREFS_USB, Context.MODE_PRIVATE)

    var preferredDeviceKey: String?
        get() = prefs().getString(KEY_PREFERRED, null)
        set(value) = prefs().edit().apply {
            if (value == null) remove(KEY_PREFERRED) else putString(KEY_PREFERRED, value)
        }.apply()

    /**
     * The DAC to use: the one the user chose if it is present, otherwise the
     * first available. Falling back rather than failing matters because the
     * chosen DAC may simply be unplugged, and a renderer that refuses to play
     * when a perfectly good DAC is attached is worse than one that adapts.
     */
    fun findAudioDevice(): UsbDevice? {
        val devices = listAudioDevices()
        if (devices.isEmpty()) return null
        val preferred = preferredDeviceKey
        if (preferred != null) {
            devices.firstOrNull { deviceKey(it) == preferred }?.let { return it }
            Log.i(TAG, "preferred DAC $preferred not attached; using ${describeForUi(devices.first())}")
        }
        return devices.first()
    }

    /** All audio devices as JSON, for the settings list. */
    fun listAudioDevicesJson(): String {
        val preferred = preferredDeviceKey
        val active = findAudioDevice()
        val items = listAudioDevices().joinToString(",") { d ->
            val key = deviceKey(d)
            """{"key":${jsonString(key)},"name":${jsonString(describeForUi(d))},""" +
            """"vendorId":"%04x","productId":"%04x",""".format(d.vendorId, d.productId) +
            """"hasPermission":${usbManager.hasPermission(d)},""" +
            """"interfaces":${d.interfaceCount},""" +
            """"preferred":${key == preferred},""" +
            """"active":${active != null && deviceKey(active) == key}}"""
        }
        return """{"devices":[$items],"preferredKey":${jsonString(preferred)}}"""
    }

    /**
     * Refreshes the shared snapshot's view of the DAC.
     *
     * Presence has to be re-read rather than cached: devices come and go, and
     * permission may be granted long after the app first looked. A stale "no
     * DAC" is actively misleading -- it tells the user to fix a problem that
     * does not exist while playback works perfectly.
     */
    fun refreshDacPresence() {
        val device = findAudioDevice()
        com.hifirend.RendererState.let { st ->
            st.dacConnected = device != null && usbManager.hasPermission(device)
            st.dacName = device?.let { describeForUi(it) }
            st.dacCount = listAudioDevices().size
        }
    }

    /**
     * Opens the device and runs the native probe. Requests permission first if
     * we do not already hold it; the user sees a system dialog.
     */
    suspend fun probe(): String {
        val attached = usbManager.deviceList.size
        val device = findAudioDevice()
            ?: return failure("no_device",
                if (attached == 0) "No USB device detected. Check the OTG cable and that the DAC is powered."
                else "$attached USB device(s) attached, but none advertises the USB audio class.")

        if (!usbManager.hasPermission(device)) {
            Log.i(TAG, "requesting USB permission for ${device.deviceName}")
            if (!requestPermission(device)) {
                return failure("permission_denied",
                    "Permission is required to talk to the DAC directly.")
            }
        }

        val connection = usbManager.openDevice(device)
            ?: return failure("open_failed",
                "Could not open the device. It may have been unplugged, or another app holds it.")

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
            val dac = NativeBridge.probeUsbDevice(connection.fileDescriptor)
            // Envelope adds what only the Android layer knows.
            """{"ok":true,"claimedAudioControl":$claimed,"attachedDevices":$attached,"dac":$dac}"""
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
