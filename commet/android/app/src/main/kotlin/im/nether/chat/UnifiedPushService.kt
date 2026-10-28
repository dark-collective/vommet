package im.nether.chat

import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import org.unifiedpush.flutter.connector.UnifiedPushReceiver

private const val TAG = "CustomUnifiedPushReceiver"

class CustomUnifiedPushReceiver : UnifiedPushReceiver() {
    override fun getEngine(context: Context): FlutterEngine {
        Log.d(TAG, "OnMessage received")
        var engine = VommetMainActivity.engine
        if (engine == null) {
            engine = FlutterEngine(context,  emptyArray(), true, false)

            engine.localizationPlugin.sendLocalesToFlutter(
                context.resources.configuration
            )

            Log.d(TAG, "Executing new entry point")


            val flutterLoader = FlutterInjector.instance().flutterLoader()

            if (!flutterLoader.initialized()) {
                throw java.lang.AssertionError(
                    "DartEntrypoints can only be created once a FlutterEngine is created."
                )
            }
            val entryPoint = DartEntrypoint(flutterLoader.findAppBundlePath(), "unifiedPushEntry")
            Log.d(TAG, entryPoint.toString())


            engine.dartExecutor.executeDartEntrypoint(
                entryPoint
            )
        }
        return engine
    }

    // Vommet issue 777: a new endpoint means the current registration is
    // live; unregister the ones the connector forgot at the distributor.
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "org.unifiedpush.flutter.connector.NEW_ENDPOINT") {
            try {
                VommetUnifiedPushCleanup.removeForgotten(context)
            } catch (e: Exception) {
                Log.w(TAG, "couldn't remove forgotten UnifiedPush registrations", e)
            }
        }
    }
}
