package im.nether.chat

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Vommet issue 593: its own FileProvider subclass, so it can sit next to
/// other FileProviders in the manifest.
class VommetUpdateProvider : FileProvider()

/// Vommet issue 593: opens a downloaded, already verified update APK in
/// Android's package installer (ReleaseUpdate.apply in Dart). When Vommet may
/// not install apps yet, it opens that switch instead and returns false; the
/// bar's Install button then works on the next tap.
object VommetUpdates {
    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.chat/updates")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("args", "no path", null)
                    return@setMethodCallHandler
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !activity.packageManager.canRequestPackageInstalls()
                    ) {
                        activity.startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")
                            )
                        )
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        activity, "${activity.packageName}.vommetupdates", File(path)
                    )
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    )
                    result.success(true)
                } catch (e: Exception) {
                    result.error("install", e.message, null)
                }
            }
    }
}
