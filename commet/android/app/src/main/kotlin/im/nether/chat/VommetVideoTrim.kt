package im.nether.chat

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Vommet issue 1051: one bounded worker; cancellation belongs to its engine. */
object VommetVideoTrim {
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean()
    fun register(engine: FlutterEngine, context: Context) {
        val main = Handler(Looper.getMainLooper())
        val jobs = mutableMapOf<Int, AtomicBoolean>() // accessed only on the main thread
        val directory = File(context.cacheDir, "media_open").canonicalFile
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.chat/video_trim").setMethodCallHandler { call, result ->
            if (call.method == "supported") result.success(Build.VERSION.SDK_INT == 35)
            else if (call.method == "cancel") {
                jobs[call.argument<Int>("id")]?.set(true); result.success(null)
            } else if (call.method in listOf("probe", "copy") && Build.VERSION.SDK_INT == 35) {
                val id = call.argument<Int>("id")
                val source = call.argument<String>("source")?.let { File(it).canonicalFile }
                val target = call.argument<String>("target")?.let { File(it).canonicalFile }
                if (id == null || source == null || source.parentFile != directory ||
                    (call.method == "copy" && (target == null || target.parentFile != directory || target == source || !target.exists() || target.length() != 0L))) {
                    result.error("unsupported", null, null)
                } else if (!busy.compareAndSet(false, true)) result.error("busy", null, null)
                else {
                    val canceled = AtomicBoolean()
                    jobs[id] = canceled
                    worker.execute {
                        val deadline = SystemClock.elapsedRealtime() + 30_000
                        val check = { check(!canceled.get() && SystemClock.elapsedRealtime() < deadline) }
                        try {
                            val value = if (call.method == "probe") {
                                val info = VideoTrimCopy.inspect(source.path, check)
                                mapOf("cutsUs" to info.cuts, "durationUs" to info.duration)
                            } else VideoTrimCopy.copy(source.path, target!!.path,
                                call.argument<Number>("startUs")!!.toLong(), call.argument<Number>("endUs")?.toLong(), check)
                            main.post { result.success(value) }
                        } catch (_: Exception) { main.post { result.error("unsupported", null, null) } }
                        finally { busy.set(false); main.post { jobs.remove(id) } }
                    }
                }
            } else result.notImplemented()
        }
    }
}
