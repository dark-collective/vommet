package im.nether.chat

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Vommet: its own FileProvider subclass, so it can't clash in the manifest
/// merge with FileProviders declared by plugins.
class VommetClipboardProvider : FileProvider()

/// Vommet: "Copy image". The pasteboard plugin only writes images on iOS.
/// The PNG goes to a cache file shared through VommetClipboardProvider, and
/// its content URI onto the clipboard (pasting apps get read access).
object VommetClipboard {
    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "im.nether.vommet/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "writeImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.arguments as? ByteArray
                if (bytes == null || bytes.isEmpty()) {
                    result.error("bad_args", "expected PNG bytes", null)
                    return@setMethodCallHandler
                }
                try {
                    val dir = File(activity.cacheDir, "clipboard").apply { mkdirs() }
                    // Only the latest copied image is kept.
                    dir.listFiles()?.forEach { it.delete() }
                    val file = File(dir, "image-${System.currentTimeMillis()}.png")
                    file.writeBytes(bytes)
                    val uri = FileProvider.getUriForFile(
                        activity, "${activity.packageName}.vommetclipboard", file)
                    val clipboard =
                        activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newUri(activity.contentResolver, "Image", uri))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("clipboard_failed", e.javaClass.simpleName, null)
                }
            }
    }
}
