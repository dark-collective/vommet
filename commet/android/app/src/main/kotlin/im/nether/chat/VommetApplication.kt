package im.nether.chat

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import io.flutter.FlutterInjector

// Vommet: initializes Flutter with the renderer flags from RendererChoice
// before anything creates an engine. With no choice set, Flutter starts
// exactly as before (lazily, from the first engine).
class VommetApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(UiLaunchCounter)
        val args = RendererChoice.shellArgs(this)
        if (args.isEmpty()) return
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, args)
            Log.i("VommetRenderer", "engine flags: ${args.joinToString(" ")}")
        } catch (e: Exception) {
            Log.w("VommetRenderer", "renderer flags not applied", e)
        }
    }

    // Counts launches of the main window for RendererChoice's fallback; push
    // and background starts never draw, so they don't count.
    private object UiLaunchCounter : ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
            if (activity is MainActivity && savedInstanceState == null) {
                RendererChoice.countUiLaunch(activity)
            }
        }
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityResumed(activity: Activity) {}
        override fun onActivityPaused(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }
}
