package im.nether.chat

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.view.View
import android.view.inputmethod.InputMethodManager
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant


// Vommet issue 681: the main window's class. Its launcher entries are
// activity-aliases (AndroidManifest.xml, LauncherIcon); the original icon's
// alias keeps the name ".MainActivity", so home screen shortcuts made before
// the rename still open the app.
class VommetMainActivity: FlutterActivity() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        dropReplayedNotificationIntent(this)
        val engine = provideEngine(this)
        // Vommet issue 593: the release bar's Install button.
        VommetUpdates.register(engine, this)
        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        registerMethods(flutterEngine, this);
        // Vommet: share target hand-off (ShareReceiverActivity). Main window
        // only, so a bubble's engine never takes the shares.
        VommetShare.register(flutterEngine, this)
        // Vommet issue 681: the launcher icon picked in Settings.
        LauncherIcon.register(flutterEngine, this)
    }

    // Vommet: secure messaging setup channel (screenshot blocking, autofill
    // service), see VommetSecureScreen.
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        flutterEngine?.let { VommetSecureScreen.register(it, this) }
    }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            // Vommet issue 285: hang up when swiped away mid-call.
            VommetCallTask.register(eng, context)
            return eng
        }
    }
}

/** The main window's class under its old name, for code that still uses it. */
typealias MainActivity = VommetMainActivity

abstract class BaseActivity : FlutterActivity() {

    abstract var entryPoint: String

    override fun getDartEntrypointFunctionName() = entryPoint

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        registerMethods(flutterEngine, this);
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
}

class BubbleActivity : BaseActivity() {
    override var entryPoint = "bubble"
}

fun registerMethods(flutterEngine: FlutterEngine, activity: Activity) {
    ExitInfo.register(flutterEngine, activity)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chat.commet.commetapp/utils").apply {
        setMethodCallHandler { call, result ->
            if(call.method == "dismissKeyboard") {
                hideKeyboard(activity);
                result.success(null);
            }
            if(call.method == "isKeyboardOpen") {
                result.success(isKeyboardOpen(activity));
            }
            // Vommet issue 85: Settings' "Open matrix.to links" row.
            if(call.method == "openByDefaultSettings") {
                result.success(VommetOpenByDefault.open(activity));
            }
            if(call.method == "matrixToLinksAllowed") {
                result.success(VommetOpenByDefault.matrixToAllowed(activity));
            }

            if(call.method == "openWidgetWindow") {

                val url = call.argument<String>("url");
                val socketPath = call.argument<String>("socket");
                val page = call.argument<String>("page");

                val intent = Intent().apply {
                    component = ComponentName(activity.applicationContext,  MatrixWidgetActivity::class.java)
                    addFlags(Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT or Intent.FLAG_ACTIVITY_MULTIPLE_TASK or Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra("url", url)
                    putExtra("socket", socketPath)
                    putExtra("page", page)
                }

                activity.startActivity(intent)
                result.success(null);
            }

            // Vommet: custom notification sounds (NotificationSounds in Dart).
            if(call.method == "importNotificationSound") {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("UNSUPPORTED", "Needs Android 10", null)
                } else {
                    try {
                        result.success(importNotificationSound(activity,
                            call.argument<String>("path")!!, call.argument<String>("name")!!))
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
            }

            if(call.method == "deleteNotificationSound") {
                try {
                    activity.contentResolver.delete(Uri.parse(call.argument<String>("uri")!!), null, null)
                } catch (e: Exception) {
                    // Already gone, or the user deleted it.
                }
                result.success(null)
            }
        }
    }
    // Vommet: "Copy image" clipboard channel.
    VommetClipboard.register(flutterEngine, activity)
    // Vommet: roaming check for automatic media download.
    VommetNetwork.register(flutterEngine, activity)
}

fun hideKeyboard(activity: Activity) {
    val imm = activity.getSystemService(Activity.INPUT_METHOD_SERVICE) as InputMethodManager
    //Find the currently focused view, so we can grab the correct window token from it.
    var view = activity.getCurrentFocus()
    //If no view currently has focus, create a new one, just so we can grab a window token from it
    if (view == null) {
        view = View(activity)
    }
    imm.hideSoftInputFromWindow(view.getWindowToken(), 0)
}

fun isKeyboardOpen(activity: Activity): Boolean {
    val insets = ViewCompat.getRootWindowInsets(activity.window.decorView.rootView)
    return insets?.isVisible(WindowInsetsCompat.Type.ime()) == true
}

/// Vommet: copies a picked sound into the shared Notifications folder, so the
/// system (which plays channel sounds) can read it. Apps can add files there
/// without storage permission from Android 10.
@RequiresApi(Build.VERSION_CODES.Q)
fun importNotificationSound(activity: Activity, path: String, name: String): String {
    val resolver = activity.contentResolver
    val values = ContentValues().apply {
        put(MediaStore.Audio.Media.DISPLAY_NAME, name)
        put(MediaStore.Audio.Media.RELATIVE_PATH, "Notifications/Vommet")
        put(MediaStore.Audio.Media.IS_NOTIFICATION, true)
        put(MediaStore.Audio.Media.IS_PENDING, 1)
    }

    val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    val uri = resolver.insert(collection, values) ?: throw Exception("Could not create the sound file")
    try {
        resolver.openOutputStream(uri).use { out ->
            java.io.File(path).inputStream().use { it.copyTo(out!!) }
        }
        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
    } catch (e: Exception) {
        resolver.delete(uri, null, null)
        throw e
    }
    return uri.toString()
}
