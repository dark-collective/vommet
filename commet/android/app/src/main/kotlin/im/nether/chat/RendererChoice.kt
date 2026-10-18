package im.nether.chat

import android.content.Context
import android.util.Log

// Vommet: the Android renderer choice (Settings › Advanced › Renderer). On some
// phones Impeller drops single letters from text, and which renderer avoids it
// depends on the GPU. Flutter reads its engine flags once per process, so
// VommetApplication applies the choice before any engine (activity, push
// receiver, background service) starts; a change takes effect on next launch.
object RendererChoice {
    private const val TAG = "VommetRenderer"
    private const val PREFS = "FlutterSharedPreferences"

    // Written by Preferences.androidRenderer; shared_preferences adds "flutter.".
    private const val CHOICE_KEY = "flutter.android_renderer"

    // App launches with a non-default renderer that never drew a frame. The
    // Dart side removes it after the first frame; two in a row fall back to
    // the default so a renderer that can't start doesn't lock the app.
    private const val UNCONFIRMED_KEY = "flutter.android_renderer_unconfirmed"
    private const val MAX_UNCONFIRMED = 2L

    fun shellArgs(context: Context): Array<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val choice = prefs.getString(CHOICE_KEY, null) ?: return emptyArray()
        if (prefs.getLong(UNCONFIRMED_KEY, 0L) >= MAX_UNCONFIRMED) {
            Log.w(TAG, "renderer '$choice' never drew a frame, back to the default")
            prefs.edit().remove(CHOICE_KEY).remove(UNCONFIRMED_KEY).apply()
            return emptyArray()
        }
        return when (choice) {
            "opengles" -> arrayOf("--enable-impeller=true", "--impeller-backend=opengles")
            "skia" -> arrayOf("--enable-impeller=false")
            else -> emptyArray()
        }
    }

    // Called when the main window opens (VommetApplication.UiLaunchCounter).
    fun countUiLaunch(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(CHOICE_KEY, null) == null) return
        prefs.edit().putLong(UNCONFIRMED_KEY, prefs.getLong(UNCONFIRMED_KEY, 0L) + 1).commit()
    }
}
