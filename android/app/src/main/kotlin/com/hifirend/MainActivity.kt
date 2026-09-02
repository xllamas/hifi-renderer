package com.hifirend

import com.hifirend.usb.UsbAudioProbe
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
                    else -> result.notImplemented()
                }
            }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    companion object {
        private const val CHANNEL = "com.hifirend/renderer"
    }
}
