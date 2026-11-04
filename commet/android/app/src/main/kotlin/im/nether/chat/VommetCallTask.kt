package im.nether.chat

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vommet issue 285: hangs up the call when the app is swiped away from
// recents. Android tells services, not activities, that their task was
// removed, so Dart (AndroidCallTask) keeps this service started while a call
// is going. onTaskRemoved asks Dart to hang up (the engine is cached in
// MainActivity, so it outlives the activity) and stops the service once
// that's done, or after 5 s. A removal Android doesn't report (force stop)
// is still cleaned up by the stale-membership sweep at next start.
//
// Vommet issue 855: the service runs in the foreground (type microphone, plus
// camera when that permission is granted) with an ongoing "Call in progress"
// notification. Without it Android cuts the microphone and then freezes the
// network once the screen is off or the app is in the background, so the call
// went silent and dropped. The notification's "Hang up" action goes through
// the same Dart path as the swipe. Without RECORD_AUDIO, or when Android
// refuses the foreground start, it stays a plain started service as before.
object VommetCallTask {
    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.vommet/call_task")
        ch.setMethodCallHandler { call, result ->
            val intent = Intent(app, CallTaskService::class.java)
            when (call.method) {
                "start" -> try {
                    intent.putExtra(CallTaskService.EXTRA_ROOM_NAME, call.argument<String>("roomName"))
                    intent.putExtra(CallTaskService.EXTRA_TITLE, call.argument<String>("title"))
                    intent.putExtra(CallTaskService.EXTRA_CHANNEL_NAME, call.argument<String>("channelName"))
                    intent.putExtra(CallTaskService.EXTRA_HANG_UP, call.argument<String>("hangUp"))
                    if (CallTaskService.canRunInForeground(app)) {
                        ContextCompat.startForegroundService(app, intent)
                    } else {
                        // Not allowed a microphone-type foreground service:
                        // a plain service still hangs up on swipe-away.
                        app.startService(intent)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    // Android 12+ refuses starting foreground services from
                    // the background (ForegroundServiceStartNotAllowedException).
                    Log.w("VommetCallTask", "Could not start the call service", e)
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
        callDart("taskRemoved", done)
    }

    // False when there is no Dart side to hang up.
    fun hangUp(): Boolean = callDart("hangUp") {}

    private fun callDart(method: String, done: () -> Unit): Boolean {
        val ch = channel
        if (ch == null) {
            done()
            return false
        }
        ch.invokeMethod(method, null, object : MethodChannel.Result {
            override fun success(result: Any?) = done()
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = done()
            override fun notImplemented() = done()
        })
        return true
    }
}

class CallTaskService : Service() {
    companion object {
        const val ACTION_HANG_UP = "im.nether.chat.HANG_UP"
        const val EXTRA_ROOM_NAME = "roomName"
        const val EXTRA_TITLE = "title"
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_HANG_UP = "hangUp"
        private const val CHANNEL_ID = "vommet_calls"
        private const val NOTIFICATION_ID = 855
        private const val TAG = "VommetCallTask"

        private fun granted(context: Context, permission: String): Boolean =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        // A microphone-type foreground service needs RECORD_AUDIO.
        fun canRunInForeground(context: Context): Boolean =
            granted(context, Manifest.permission.RECORD_AUDIO)
    }

    private var inForeground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANG_UP) {
            Log.i(TAG, "Hang up pressed on the call notification")
            // Dart's session listener sends "stop" once the calls are gone;
            // with no engine there is nobody to do that, so stop here.
            if (!VommetCallTask.hangUp()) stopSelf()
            return START_NOT_STICKY
        }
        startInForeground(intent)
        return START_NOT_STICKY
    }

    private fun startInForeground(intent: Intent?) {
        if (!canRunInForeground(this)) {
            Log.w(TAG, "No microphone permission, running as a plain service")
            return
        }
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            // A camera type without the permission throws on Android 14+.
            if (granted(this, Manifest.permission.CAMERA)) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(intent), type)
            inForeground = true
        } catch (e: Exception) {
            Log.w(TAG, "Could not run the call service in the foreground", e)
            // Dart repeats "start" (call connected, app resumed), maybe from
            // the background: a refused repeat must not end a service that is
            // already in the foreground. A first start that fails must stop,
            // or startForegroundService crashes the app after a few seconds.
            if (!inForeground) stopSelf()
        }
    }

    private fun buildNotification(intent: Intent?): android.app.Notification {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Call in progress"
        val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Calls"
        val hangUp = intent?.getStringExtra(EXTRA_HANG_UP) ?: "Hang up"
        val roomName = intent?.getStringExtra(EXTRA_ROOM_NAME)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Creating an existing channel again only updates its name.
            val channel = NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW)
            channel.setSound(null, null)
            channel.enableVibration(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }

        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        // The launcher intent brings the existing task to the front.
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            PendingIntent.getActivity(this, 0, it, immutable or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val hangUpIntent = PendingIntent.getService(
            this, 1,
            Intent(this, CallTaskService::class.java).setAction(ACTION_HANG_UP),
            immutable or PendingIntent.FLAG_UPDATE_CURRENT)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle(title)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, hangUp, hangUpIntent)
        if (!roomName.isNullOrEmpty()) builder.setContentText(roomName)
        if (open != null) builder.setContentIntent(open)
        return builder.build()
    }

    override fun onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "Swiped away during a call, hanging up")
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
