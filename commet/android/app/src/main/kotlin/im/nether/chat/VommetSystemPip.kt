package im.nether.chat

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vommet issue 1081: the system's picture-in-picture window. While a video
// plays in the media viewer, the app arms it; leaving the app (home, swipe
// up) then shrinks the main window into the floating window. Android 12+
// does that itself (auto-enter); older versions enter on onUserLeaveHint.
// The app shows only the video while it is in the window.
object VommetSystemPip {
    private const val TAG = "VommetSystemPip"
    private var channel: MethodChannel? = null
    private var armed = false
    private var aspect: Rational? = null

    // Android counts any activity the app starts itself (share sheet, file
    // picker, a link in another app) as the user leaving, on 8-11 and for
    // 12+ auto-enter alike. Those must not open the window: disarmed from
    // the launch until the app is back in front.
    private var ownLaunch = false

    fun register(engine: FlutterEngine, activity: Activity) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.chat/system_pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setArmed" -> {
                        armed = call.argument<Boolean>("on") ?: false
                        val num = call.argument<Int>("aspectNum")
                        val den = call.argument<Int>("aspectDen")
                        aspect = if (num != null && den != null && num > 0 && den > 0) Rational(num, den) else null
                        activity.runOnUiThread {
                            apply(activity)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun available(activity: Activity): Boolean =
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    @RequiresApi(Build.VERSION_CODES.O)
    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
        aspect?.let { builder.setAspectRatio(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(armed && !ownLaunch)
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun apply(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !available(activity)) return
        try {
            activity.setPictureInPictureParams(params())
        } catch (e: RuntimeException) {
            Log.w(TAG, "Couldn't set picture-in-picture params", e)
        }
    }

    /** Android 8 to 11: the user is leaving the app (home, recents). */
    fun onUserLeaveHint(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (!armed || ownLaunch || !available(activity)) return
        if (activity.isInPictureInPictureMode) return
        try {
            activity.enterPictureInPictureMode(params())
        } catch (e: RuntimeException) {
            Log.w(TAG, "Couldn't enter picture in picture", e)
        }
    }

    /** The app is about to start an activity of its own. */
    fun beforeOwnLaunch(activity: Activity) {
        if (ownLaunch) return
        ownLaunch = true
        if (armed) apply(activity)
    }

    /** The app is in front again: re-arm for the next time it's left. */
    fun onResume(activity: Activity) {
        if (!ownLaunch) return
        ownLaunch = false
        if (armed) apply(activity)
    }

    /** [dismissed]: the user closed the window instead of going back to the app. */
    fun onModeChanged(inPip: Boolean, dismissed: Boolean) {
        channel?.invokeMethod("changed", mapOf("inPip" to inPip, "dismissed" to dismissed))
    }
}
