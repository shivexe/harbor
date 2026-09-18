package dev.harbor.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "harbor/security").setMethodCallHandler { call, result ->
            if (call.method != "unlock") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("busy", "Unlock is already active", null)
            } else {
                val manager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
                val intent = manager.createConfirmDeviceCredentialIntent("Unlock Harbor", "Confirm your device screen lock")
                if (!manager.isDeviceSecure || intent == null) {
                    result.error("screen_lock_required", "Configure a secure device screen lock", null)
                } else {
                    pending = result
                    startActivityForResult(intent, 4101)
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 4101) {
            pending?.success(resultCode == Activity.RESULT_OK)
            pending = null
        }
    }
}
