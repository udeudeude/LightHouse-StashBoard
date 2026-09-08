package com.udeudeude.lighthouse

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lighthouse/display",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "physicalDpi" -> {
                    val metrics = resources.displayMetrics
                    result.success(
                        mapOf(
                            "xdpi" to metrics.xdpi.toDouble(),
                            "ydpi" to metrics.ydpi.toDouble(),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
