package im.nether.chat

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Vommet Deep Search: the battery state, so the background search index
 * pauses on battery saver, or below 20% while not charging. Reads the
 * sticky battery broadcast; nothing is registered or kept.
 */
object VommetPower {
    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.vommet/power")
            .setMethodCallHandler { call, result ->
                if (call.method == "state") {
                    try {
                        result.success(state(app))
                    } catch (e: Exception) {
                        result.error("failed", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun state(context: Context): Map<String, Any> {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val battery: Intent? =
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1
        return mapOf(
            "saver" to (power?.isPowerSaveMode ?: false),
            "percent" to percent,
            "charging" to charging,
        )
    }
}
