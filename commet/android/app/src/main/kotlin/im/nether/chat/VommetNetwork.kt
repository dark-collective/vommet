package im.nether.chat

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vommet: whether the active network is roaming, for the "When roaming"
// automatic media download choice (Vommet issue 75). connectivity_plus only
// says "mobile".
object VommetNetwork {
    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "im.nether.vommet/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRoaming" -> result.success(isRoaming(activity))
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun isRoaming(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val caps = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)
            } else {
                manager.activeNetworkInfo?.isRoaming ?: false
            }
        } catch (e: Exception) {
            false
        }
    }
}
