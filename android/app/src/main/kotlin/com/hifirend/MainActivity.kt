package com.hifirend

import com.hifirend.usb.UsbAudioProbe
import com.hifirend.usb.UsbPlayback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

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
