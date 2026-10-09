package im.nether.chat

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Vommet: receives ACTION_SEND / ACTION_SEND_MULTIPLE from other apps' share
 * sheets. It copies the shared content into the cache while it still holds the
 * sender's read grant, queues it for Dart (VommetShare), then brings the main
 * window forward. A separate activity because MainActivity is singleTop: a
 * share would otherwise start a second MainActivity inside the sender's task.
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shareIntent = intent
        Thread {
            val payload = try {
                VommetShare.read(applicationContext, shareIntent)
            } catch (e: Exception) {
                Log.e(VommetShare.TAG, "Failed to read shared content", e)
                null
            }
            if (payload != null) VommetShare.offer(payload)
            runOnUiThread {
                startActivity(Intent(this, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                })
                finish()
            }
        }.start()
    }
}

object VommetShare {
    const val TAG = "VommetShare"
    private const val CHANNEL = "im.nether.vommet/share"
    private const val CACHE_DIR = "shared"
    private const val KEEP_MS = 24L * 60 * 60 * 1000

    private val pending = mutableListOf<Map<String, Any?>>()
    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takePending") {
                    val taken = synchronized(pending) {
                        val copy = ArrayList(pending)
                        pending.clear()
                        copy
                    }
                    result.success(taken)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    fun offer(payload: Map<String, Any?>) {
        synchronized(pending) { pending.add(payload) }
        mainHandler.post { channel?.invokeMethod("sharesAvailable", null) }
    }

    @Suppress("DEPRECATION")
    fun read(context: Context, intent: Intent): Map<String, Any?>? {
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND ->
                listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else -> return null
        }
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()

        val root = File(context.cacheDir, CACHE_DIR)
        prune(root)
        val dir = File(root, System.currentTimeMillis().toString())

        val files = uris.mapIndexedNotNull { index, uri ->
            // Only content:// — a file:// URI could point at our own private
            // files and smuggle them into a chat.
            if (uri.scheme != ContentResolver.SCHEME_CONTENT) return@mapIndexedNotNull null
            try {
                copy(context, uri, dir, index)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to copy shared item $index", e)
                null
            }
        }

        if (files.isEmpty() && text.isNullOrBlank()) return null
        return mapOf("files" to files, "text" to text)
    }

    private fun copy(context: Context, uri: Uri, dir: File, index: Int): Map<String, Any?> {
        val resolver = context.contentResolver
        var name: String? = null
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
        }
        val safeName = (name ?: uri.lastPathSegment ?: "shared")
            .substringAfterLast('/')
            .replace(Regex("[\\\\:*?\"<>|\\u0000]"), "_")
            .ifBlank { "shared" }

        val target = File(File(dir, index.toString()).apply { mkdirs() }, safeName)
        val input = resolver.openInputStream(uri) ?: throw IllegalStateException("no stream")
        input.use { src -> target.outputStream().use { dst -> src.copyTo(dst) } }

        return mapOf(
            "path" to target.absolutePath,
            "name" to safeName,
            "mime" to resolver.getType(uri),
            "size" to target.length(),
        )
    }

    private fun prune(root: File) {
        val cutoff = System.currentTimeMillis() - KEEP_MS
        root.listFiles()?.forEach { if (it.lastModified() < cutoff) it.deleteRecursively() }
    }
}
