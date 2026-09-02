package com.hifirend

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The real command channel arrives with RendererService in M3. For now
        // this exists purely so the M0 skeleton is verifiable on a device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "selfTest" -> result.success(NativeBridge.selfTest())
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val CHANNEL = "com.hifirend/renderer"
    }
}
