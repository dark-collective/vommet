package im.nether.chat

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Vommet issue 681: switches the launcher icon between the two built into
 * the app. Each icon is a launcher entry (activity-alias in
 * AndroidManifest.xml) for the same main window; the picked one is turned on
 * and the other off. DONT_KILL_APP keeps the app running, though some
 * launchers still restart it or drop a home screen shortcut to the old entry.
 */
object LauncherIcon {
    private const val TAG = "LauncherIcon"

    /** Icon name (as Dart sends it) to alias class, and whether the manifest enables it. */
    private val aliases = linkedMapOf(
        "original" to Pair("im.nether.chat.MainActivity", false),
        "v" to Pair("im.nether.chat.LauncherV", true),
    )

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.vommet/launcher_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        val icon = call.arguments as? String
                        if (icon == null || icon !in aliases) {
                            result.error("bad_icon", "Unknown launcher icon: $icon", null)
                            return@setMethodCallHandler
                        }
                        try {
                            set(app, icon)
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to switch the launcher icon", e)
                            result.error("failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun set(context: Context, icon: String) {
        val pm = context.packageManager
        fun component(cls: String) = ComponentName(context.packageName, cls)
        fun enabled(cls: String, byDefault: Boolean) =
            when (pm.getComponentEnabledSetting(component(cls))) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> byDefault
                else -> false
            }
        // The picked entry first, so there is always one to open the app from.
        val ordered = aliases.entries.sortedBy { it.key != icon }
        for ((name, alias) in ordered) {
            val (cls, byDefault) = alias
            val want = name == icon
            if (enabled(cls, byDefault) == want) continue
            pm.setComponentEnabledSetting(
                component(cls),
                if (want) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
