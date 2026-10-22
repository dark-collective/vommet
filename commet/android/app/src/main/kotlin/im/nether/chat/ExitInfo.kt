package im.nether.chat

import android.app.Activity
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

// Vommet diagnostics: why did the previous run end? Native and Java crashes
// kill the process before Dart can record anything, so on the next launch we
// ask Android (11+) for the exit reason, and read what our own uncaught
// exception handler saved. Only code identifiers are kept: the exception's
// class name and stack frames (class.method:line), never its message.
object ExitInfo {
    private const val CRASH_FILE = "vommet_last_java_crash.json"
    private const val PREFS = "vommet_exit_info"
    private const val LAST_REPORTED = "last_reported_ts"
    private var handlerInstalled = false

    fun register(engine: FlutterEngine, activity: Activity) {
        installCrashHandler(activity.applicationContext)
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.chat/exit_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "lastExit") {
                    result.success(lastExit(activity.applicationContext))
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun installCrashHandler(context: Context) {
        if (handlerInstalled) return
        handlerInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        val file = File(context.filesDir, CRASH_FILE)
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                var root: Throwable = error
                while (root.cause != null && root.cause !== root) root = root.cause!!
                val frames = JSONArray()
                for (f in root.stackTrace.take(25)) {
                    frames.put("${f.className}.${f.methodName}:${f.lineNumber.coerceAtLeast(0)}")
                }
                file.writeText(JSONObject()
                    .put("type", root.javaClass.name)
                    .put("outer", error.javaClass.name)
                    .put("frames", frames)
                    .put("ts", System.currentTimeMillis())
                    .toString())
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    // Returns null when there is nothing new to report.
    private fun lastExit(context: Context): Map<String, Any?>? {
        val out = HashMap<String, Any?>()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lastReported = prefs.getLong(LAST_REPORTED, 0L)
        var ts = 0L

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = am.getHistoricalProcessExitReasons(context.packageName, 0, 1)
                .firstOrNull()
            if (info != null && info.timestamp > lastReported) {
                ts = info.timestamp
                out["reason"] = reasonName(info.reason)
                out["status"] = info.status
                out["importance"] = info.importance
                out["age_ms"] = System.currentTimeMillis() - info.timestamp
                if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val trace = try {
                        info.traceInputStream?.use { NativeTrace.parse(it.readBytes()) }
                    } catch (_: Throwable) {
                        null
                    }
                    if (trace != null) {
                        out["native_frames"] = trace.frames
                        out["native_thread"] = trace.thread
                        out["abort_kind"] = trace.abortKind
                    }
                }
            }
        }

        val file = File(context.filesDir, CRASH_FILE)
        if (file.exists()) {
            try {
                val json = JSONObject(file.readText())
                val crashTs = json.optLong("ts")
                if (crashTs > lastReported) {
                    out["java_error_type"] = json.optString("type")
                    out["java_outer_type"] = json.optString("outer")
                    val frames = json.optJSONArray("frames") ?: JSONArray()
                    out["java_frames"] = (0 until frames.length()).map { frames.getString(it) }
                    if (ts == 0L) {
                        ts = crashTs
                        out["age_ms"] = System.currentTimeMillis() - crashTs
                    }
                }
            } catch (_: Throwable) {
            }
            file.delete()
        }

        if (ts == 0L) return null
        prefs.edit().putLong(LAST_REPORTED, ts).apply()
        return out
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "unknown"
    }
}
