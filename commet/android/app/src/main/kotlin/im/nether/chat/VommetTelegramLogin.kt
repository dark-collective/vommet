package im.nether.chat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vommet issue 801: on a phone the Telegram login QR code can't be scanned
// from the same screen, so the tg://login link is handed to the Telegram app
// instead. It goes only to Telegram's own apps (by package name), never to
// whichever app registers tg:// links, which could take over the login.
object VommetTelegramLogin {
    // Listed under <queries> in the manifest.
    private val packages = listOf(
        "org.telegram.messenger", // Google Play
        "org.telegram.messenger.web", // telegram.org
        "org.thunderdog.challegram", // Telegram X
    )

    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.chat/telegram_login")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> result.success(installed(activity).isNotEmpty())
                    "openLogin" -> {
                        val url = call.argument<String>("url")
                        if (url == null || !url.startsWith("tg://login?token=")) {
                            result.success(false)
                        } else {
                            result.success(open(activity, url))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installed(activity: Activity): List<String> = packages.filter {
        try {
            activity.packageManager.getPackageInfo(it, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun open(activity: Activity, url: String): Boolean {
        for (pkg in installed(activity)) {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(pkg))
                return true
            } catch (_: ActivityNotFoundException) {
            }
        }
        return false
    }
}
