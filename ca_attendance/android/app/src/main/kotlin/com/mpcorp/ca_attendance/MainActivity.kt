package com.mpcorp.ca_attendance

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// FlutterFragmentActivity (not FlutterActivity) so androidx BiometricPrompt can
/// attach to it. Wires up the hardware-keystore method channel.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mpcorp.ca_attendance/keystore",
        ).setMethodCallHandler(BiometricKeystore(this))
    }
}
