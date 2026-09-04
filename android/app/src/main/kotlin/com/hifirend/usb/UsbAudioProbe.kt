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
    fun deviceKey(d: UsbDevice): String =
        "%04x:%04x:%s".format(d.vendorId, d.productId, serialOf(d) ?: "-")

    /** Null unless we hold permission and the device actually reports one. */
    private fun serialOf(d: UsbDevice): String? = try {
        if (usbManager.hasPermission(d)) d.serialNumber?.trim()?.takeIf { it.isNotEmpty() }
        else null
    } catch (_: Throwable) {
        null
    }

    /**
     * Whether a remembered key refers to this device.
     *
     * Not string equality, because the key is not stable: the serial can only
     * be read while we hold permission, and on this phone permission lapses on
     * every replug. A key stored as vendor:product:serial therefore stops
     * matching the same device as soon as the grant expires, and the renderer
     * silently reverts to whichever DAC sorts first -- the user's choice
     * quietly discarded, with nothing on screen to explain it.
     *
     * So vendor and product must match, and the serial is only allowed to
     * *rule out* a device when both sides actually know it. That is exactly the
     * case it exists for: telling two of the same model apart.
     */
    private fun keyRefersTo(stored: String, d: UsbDevice): Boolean {
        val prefix = "%04x:%04x:".format(d.vendorId, d.productId)
        if (!stored.startsWith(prefix)) return false
        val storedSerial = stored.removePrefix(prefix)
            .takeIf { it.isNotBlank() && it != "-" }
        val actualSerial = serialOf(d)
        if (storedSerial == null || actualSerial == null) return true
        return storedSerial == actualSerial
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
            devices.firstOrNull { keyRefersTo(preferred, it) }?.let { return it }
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
            """"preferred":${preferred != null && keyRefersTo(preferred, d)},""" +
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

        val probed = probeOne(device)
            ?: return failure("open_failed",
                "Could not open the device. It may have been unplugged, or another app holds it.")

        dumpCapabilities(describeForUi(device), probed.json)
        dumpOthers(device)

        // Envelope adds what only the Android layer knows.
        return """{"ok":true,"claimedAudioControl":${probed.claimedAudioControl},""" +
            """"attachedDevices":$attached,"dac":${probed.json}}"""
    }

    private class Probed(val json: String, val claimedAudioControl: Boolean)

    /**
     * Opens one device and runs the native parser against it.
     *
     * The AudioControl interface must be taken away from the kernel's
     * snd-usb-audio driver before class control transfers will work -- without
     * this, the UAC2 clock GET_RANGE (the only way to learn a UAC2 device's
     * real sample rates) fails with LIBUSB_ERROR_IO. force=true is what
     * performs the kernel detach, and it must be released again or the device
     * stays detached from system audio.
     */
    private fun probeOne(device: UsbDevice): Probed? {
        val connection = usbManager.openDevice(device) ?: return null
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
            Probed(NativeBridge.probeUsbDevice(connection.fileDescriptor), claimed)
        } finally {
            if (claimed && control != null) connection.releaseInterface(control)
            // The native side wrapped this fd but does not own it.
            connection.close()
        }
    }

    /**
     * Dumps the other attached audio devices too.
     *
     * A support dump that describes only the selected DAC is misleading on the
     * setup most likely to be producing a support request in the first place --
     * someone with two devices attached, wondering why the app prefers one of
     * them. Devices we do not already hold permission for are named but not
     * opened: prompting for each one would put a stack of system dialogs in
     * front of a user who only opened the settings screen.
     */
    private fun dumpOthers(selected: UsbDevice) {
        val selectedKey = deviceKey(selected)
        for (d in listAudioDevices()) {
            if (deviceKey(d) == selectedKey) continue
            if (!usbManager.hasPermission(d)) {
                Log.i(TAG, "caps: ${describeForUi(d)} attached, no permission; not probed")
                continue
            }
            val other = runCatching { probeOne(d) }.getOrNull()
            if (other == null) {
                Log.i(TAG, "caps: ${describeForUi(d)} attached, could not open")
            } else {
                dumpCapabilities(describeForUi(d), other.json)
            }
        }
    }

    /**
     * The selected device's capability table, or null when it cannot be read.
     *
     * Never prompts: this is called to answer questions about the renderer's
     * capabilities (what formats to advertise, for instance), which can happen
     * at any moment, and a permission dialog appearing out of nowhere would be
     * worse than not knowing.
     */
    fun selectedCapabilities(): org.json.JSONObject? {
        val device = findAudioDevice() ?: return null
        if (!usbManager.hasPermission(device)) return null
        val probed = runCatching { probeOne(device) }.getOrNull() ?: return null
        return runCatching { org.json.JSONObject(probed.json) }
            .getOrNull()
            ?.takeIf { it.optBoolean("ok") }
    }

    /**
     * Writes the whole capability table to logcat.
     *
     * The app has to work with DACs we will never physically have, and this
     * table is the only thing that explains why a given one behaves as it does.
     * A user can capture it with `adb logcat -s hifirend` and send it, which
     * turns "it does not work on my DAC" into something actionable.
     *
     * Chunked because logcat drops anything past roughly 4 kB in one message,
     * and a device with many alt-settings comfortably exceeds that -- silently,
     * which would make the dump look complete when it was truncated.
     */
    private fun dumpCapabilities(name: String, json: String) {
        val chunk = 3000
        if (json.length <= chunk) {
            Log.i(TAG, "caps [$name]: $json")
            return
        }
        val parts = (json.length + chunk - 1) / chunk
        for (i in 0 until parts) {
            val end = minOf((i + 1) * chunk, json.length)
            Log.i(TAG, "caps [$name] ${i + 1}/$parts: ${json.substring(i * chunk, end)}")
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
