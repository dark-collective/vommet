package im.nether.chat

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vommet: secure messaging setup (Vommet issue 129). Blocks screenshots and
// screen recording while a recovery key is on screen (FLAG_SECURE), and says
// which app is the autofill service, so the app can warn that Google Password
// Manager is only end-to-end encrypted with on-device encryption turned on.
object VommetSecureScreen {
    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.chat/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        activity.runOnUiThread {
                            if (on) {
                                activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        }
                    }
                    "autofillService" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val manager = activity.getSystemService(AutofillManager::class.java)
                            result.success(manager?.autofillServiceComponentName?.packageName)
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
