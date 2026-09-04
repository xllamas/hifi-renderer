package com.hifirend

import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.hifirend.usb.UsbAudioProbe
import com.hifirend.RendererControl
import com.hifirend.ServiceHealth
import com.hifirend.power.VendorAutostart
import com.hifirend.upnp.RendererUpnpService
import com.hifirend.usb.UsbPlayback
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the panel lit while in use; ScreenPolicy clears this after the
        // idle timeout so a renderer left alone for hours does not burn the
        // display. The CPU is held awake separately by the playback wake lock.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Allow the service to bring this up to wake the screen when playback
        // starts. setShowWhenLocked/setTurnScreenOn is the supported route from
        // API 27; below that the deprecated window flags are the only option.
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // The spec wants the renderer always active, so it comes up with the
        // app rather than waiting to be switched on. Promotion to a foreground
        // service that survives the UI and starts at boot is M6.
        startService(Intent(this, RendererUpnpService::class.java))
        noteUsbAttachIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        noteUsbAttachIntent(intent)
    }

    /**
     * Android launched us because a matching USB device was attached.
     *
     * Permission comes with this intent implicitly, and if the user ticked
     * "use by default for this device" it arrives on every future attach with
     * no dialog at all. That is the only route to permission surviving an
     * unplug -- a grant from requestPermission() lasts just for the one
     * attachment, which is why hot-plugging otherwise prompts every time.
     */
    private fun noteUsbAttachIntent(intent: Intent?) {
        if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
        Log.i("hifirend", "USB device attached; launched with implicit permission")
        runCatching { UsbAudioProbe(applicationContext).refreshDacPresence() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The real command channel arrives with RendererService in M3. For now
        // this exists purely so the M0 skeleton is verifiable on a device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "selfTest" -> result.success(NativeBridge.selfTest())
                    "probeUsb" -> scope.launch {
                        // Permission is a user dialog and the probe does blocking
                        // control transfers, so neither belongs on the UI thread.
                        val report = try {
                            withContext(Dispatchers.IO) { UsbAudioProbe(applicationContext).probe() }
                        } catch (e: Throwable) {
                            "probe threw: ${e::class.java.simpleName}: ${e.message}"
                        }
                        result.success(report)
                    }
                    "playWav" -> scope.launch {
                        val path = call.argument<String>("path") ?: ""
                        val loop = call.argument<Boolean>("loop") ?: false
                        val r = try {
                            withContext(Dispatchers.IO) { playback.play(path, loop) }
                        } catch (e: Throwable) {
                            """{"ok":false,"message":"${e::class.java.simpleName}: ${e.message}"}"""
                        }
                        result.success(r)
                    }
                    "stopPlayback" -> scope.launch {
                        withContext(Dispatchers.IO) { playback.stop() }
                        result.success(null)
                    }
                    "playbackStatus" -> result.success(playback.status())
                    "rendererState" -> {
                        // Cheap, and keeps the screen honest about the DAC even
                        // when permission arrives after the app started.
                        runCatching { UsbAudioProbe(applicationContext).refreshDacPresence() }
                        result.success(RendererState.toJson())
                    }
                    "playPause" -> result.success(RendererControl.playPause())
                    "stopPlayback2" -> result.success(RendererControl.stop())
                    "setDacVolume" -> {
                        val pct = call.argument<Int>("percent") ?: 0
                        result.success(
                            RendererControl.transport?.setDacVolume(pct) ?: false
                        )
                    }
                    "setRendererName" -> {
                        val name = call.argument<String>("name")?.trim().orEmpty()
                        if (name.isEmpty()) {
                            result.success(false)
                        } else {
                            getSharedPreferences("hifirend_upnp", MODE_PRIVATE)
                                .edit().putString("friendly_name", name).apply()
                            RendererState.rendererName = name
                            result.success(true)
                        }
                    }
                    "applianceStatus" -> {
                        val health = ServiceHealth(applicationContext)
                        result.success(
                            """{"health":${health.toJson()},""" +
                            ""","manufacturer":"${VendorAutostart.manufacturer()}"""" +
                            ""","hasVendorSettings":${VendorAutostart.hasVendorSettings(this)}""" +
                            ""","ignoringBatteryOptimizations":${
                                VendorAutostart.isIgnoringBatteryOptimizations(this)}}"""
                        )
                    }
                    "listDacs" ->
                        result.success(UsbAudioProbe(applicationContext).listAudioDevicesJson())
                    "selectDac" -> {
                        val key = call.argument<String>("key")
                        UsbAudioProbe(applicationContext).preferredDeviceKey =
                            key?.takeIf { it.isNotBlank() }
                        runCatching { UsbAudioProbe(applicationContext).refreshDacPresence() }
                        // The renderer advertises what the selected DAC accepts,
                        // so this changes the device's capabilities and every
                        // controller that already discovered us is now wrong.
                        RendererControl.outputDeviceChanged()
                        result.success(true)
                    }
                    "openVendorAutostart" ->
                        result.success(VendorAutostart.open(this) ?: "")
                    "requestBatteryExemption" ->
                        result.success(VendorAutostart.requestIgnoreBatteryOptimizations(this))
                    "startUpnp" -> {
                        startService(Intent(this, RendererUpnpService::class.java))
                        result.success(true)
                    }
                    "stopUpnp" -> {
                        stopService(Intent(this, RendererUpnpService::class.java))
                        result.success(true)
                    }
                    "listTestFiles" -> result.success(
                        (externalCacheDir?.listFiles()
                            ?.filter { it.name.endsWith(".wav") }
                            ?.sortedBy { it.name }
                            ?.joinToString("\n") { it.absolutePath }) ?: "")
                    else -> result.notImplemented()
                }
            }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val playback by lazy { UsbPlayback(applicationContext) }

    override fun onDestroy() {
        playback.stop()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.hifirend/renderer"
    }
}
