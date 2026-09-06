package com.hifirend

import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
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
        // The panel is held lit by ScreenPolicy, which lets go once the
        // renderer has been quiet long enough that a display left on all night
        // would just be burning. Registering here rather than setting the flag
        // outright is the point: the previous version added FLAG_KEEP_SCREEN_ON
        // in onCreate and nothing ever removed it, so the idle timeout fired
        // into a listener that did not exist and the screen never blanked.
        // The CPU is held awake separately by the playback wake lock.
        com.hifirend.power.ScreenState.apply = { on -> runOnUiThread { keepScreenOn(on) } }

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

    private fun keepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
                    // The sweep force-claims the audio interfaces, which
                    // detaches them from any stream already running and kills
                    // its transfers mid-flight. Refuse rather than corrupt what
                    // is playing.
                    "pickAudioFile" -> {
                        pickResult?.success("{}")   // a picker left open
                        pickResult = result
                        // "*/*" with an audio hint rather than "audio/*": some
                        // providers type a FLAC as octet-stream, and a picker
                        // that hides the file the user came for is worse than
                        // one that shows too much.
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES,
                                arrayOf("audio/*", "application/octet-stream"))
                        }
                        runCatching { startActivityForResult(intent, PICK_AUDIO) }
                            .onFailure {
                                Log.w("hifirend", "no document picker: ${it.message}")
                                pickResult = null
                                result.success("{}")
                            }
                    }
                    "playFile" -> scope.launch {
                        val uri = call.argument<String>("uri") ?: ""
                        val mime = call.argument<String>("mime") ?: ""
                        val r = if (RendererState.isPlaying) {
                            """{"ok":false,"message":"Stop playback before testing a file."}"""
                        } else if (uri.isEmpty()) {
                            """{"ok":false,"message":"No file chosen."}"""
                        } else try {
                            withContext(Dispatchers.IO) { playback.playFile(uri, mime) }
                        } catch (e: Throwable) {
                            """{"ok":false,"message":"${e::class.java.simpleName}: ${e.message}"}"""
                        }
                        result.success(r)
                    }
                    "fileStatus" -> result.success(playback.fileStatus())
                    "playTone" -> scope.launch {
                        val r = if (RendererState.isPlaying) {
                            """{"ok":false,"message":"Stop playback before running the sweep."}"""
                        } else try {
                            withContext(Dispatchers.IO) {
                                playback.playTone(
                                    call.argument<Int>("rate") ?: 44100,
                                    call.argument<Int>("bits") ?: 16,
                                    call.argument<Int>("channels") ?: 2,
                                    call.argument<Int>("hz") ?: 1000,
                                )
                            }
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
                    "nextTrack" -> result.success(RendererControl.next())
                    "previousTrack" -> result.success(RendererControl.previous())
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
                    "onboardingStatus" -> {
                        val health = ServiceHealth(applicationContext)
                        result.success(
                            """{"hasRun":${Onboarding.hasRun(applicationContext)}""" +
                            ""","notifications":${
                                Onboarding.notificationsEnabled(applicationContext)}""" +
                            ""","ignoringBatteryOptimizations":${
                                VendorAutostart.isIgnoringBatteryOptimizations(this)}""" +
                            ""","manufacturer":"${VendorAutostart.manufacturer()}"""" +
                            ""","hasVendorSettings":${
                                VendorAutostart.hasVendorSettings(this)}""" +
                            ""","unexpectedDeaths":${health.unexpectedDeaths}}"""
                        )
                    }
                    "requestNotifications" ->
                        result.success(Onboarding.requestNotifications(this))
                    "openNotificationSettings" ->
                        result.success(Onboarding.openNotificationSettings(this))
                    "setOnboardingDone" -> {
                        Onboarding.setHasRun(
                            applicationContext, call.argument<Boolean>("done") ?: true)
                        result.success(true)
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
                    "getServerConversion" ->
                        result.success(
                            com.hifirend.upnp.ServerConversion.isEnabled(applicationContext))
                    "setServerConversion" -> {
                        val on = call.argument<Boolean>("enabled") ?: false
                        com.hifirend.upnp.ServerConversion.setEnabled(applicationContext, on)
                        // Changes what the renderer advertises, so controllers
                        // that already discovered us are now wrong.
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


    /** Held across the picker Activity, which answers in onActivityResult. */
    private var pickResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_AUDIO) return
        val pending = pickResult ?: return
        pickResult = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pending.success("{}")
            return
        }
        val name = displayName(uri) ?: uri.lastPathSegment ?: "file"
        // The extension wins over the provider's answer. Providers routinely
        // report a FLAC as application/octet-stream, and the decoder is chosen
        // from this string -- a generic type means "try FLAC, then give up",
        // which is exactly wrong for the MP3 in someone's library.
        val mime = mimeFromName(name) ?: contentResolver.getType(uri) ?: ""
        Log.i("hifirend", "picked '$name' as $mime")
        pending.success(
            """{"uri":"""" + esc(uri.toString()) +
            """","name":"""" + esc(name) + """","mime":"""" + esc(mime) + """"}""")
    }

    private fun displayName(uri: Uri): String? = runCatching {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    }.getOrNull()

    /**
     * Extension to MIME, covering what the engine can actually decode. Anything
     * unrecognised returns null so the provider's own answer is used, and an
     * empty type still works -- the decoder falls back to sniffing.
     */
    private fun mimeFromName(name: String): String? =
        when (name.substringAfterLast('.', "").lowercase()) {
            "flac" -> "audio/flac"
            "mp3" -> "audio/mpeg"
            "wav", "wave" -> "audio/wav"
            "aif", "aiff", "aifc" -> "audio/aiff"
            "m4a", "mp4" -> "audio/mp4"
            "aac" -> "audio/aac"
            "ogg", "oga" -> "audio/ogg"
            "opus" -> "audio/opus"
            else -> null
        }

    private fun esc(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val playback by lazy { UsbPlayback(applicationContext) }

    override fun onDestroy() {
        playback.stop()
        // Detach the window from the screen policy, but only on a real finish:
        // on a configuration change the replacement activity registers before
        // this runs, and clearing unconditionally would leave its window
        // unmanaged and the panel stuck however it happened to be.
        if (isFinishing) com.hifirend.power.ScreenState.apply = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.hifirend/renderer"
        private const val PICK_AUDIO = 4802
    }
}
