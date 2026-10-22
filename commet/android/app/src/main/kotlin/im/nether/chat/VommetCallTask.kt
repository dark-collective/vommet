package im.nether.chat

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vommet issue 285: hangs up the call when the app is swiped away from
// recents. Android tells services, not activities, that their task was
// removed, so Dart (AndroidCallTask) keeps this plain, non-foreground service
// started while a call is going. onTaskRemoved asks Dart to hang up (the
// engine is cached in MainActivity, so it outlives the activity) and stops
// the service once that's done, or after 5 s. A removal Android doesn't
// report (force stop, or the service already stopped by the background
// limits) is still cleaned up by the stale-membership sweep at next start.
object VommetCallTask {
    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.vommet/call_task")
        ch.setMethodCallHandler { call, result ->
            val intent = Intent(app, CallTaskService::class.java)
            when (call.method) {
                "start" -> try {
                    app.startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // Android 8+ refuses starting services from the background.
                    result.success(false)
                }
                "stop" -> {
                    app.stopService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    fun taskRemoved(done: () -> Unit) {
        val ch = channel
        if (ch == null) {
            done()
            return
        }
        ch.invokeMethod("taskRemoved", null, object : MethodChannel.Result {
            override fun success(result: Any?) = done()
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = done()
            override fun notImplemented() = done()
        })
    }
}

class CallTaskService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i("VommetCallTask", "Swiped away during a call, hanging up")
        var stopped = false
        val stop: () -> Unit = {
            if (!stopped) {
                stopped = true
                stopSelf()
            }
        }
        Handler(Looper.getMainLooper()).postDelayed(stop, 5000)
        VommetCallTask.taskRemoved(stop)
        super.onTaskRemoved(rootIntent)
    }
}
