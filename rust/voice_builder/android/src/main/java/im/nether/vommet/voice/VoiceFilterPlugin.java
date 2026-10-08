package im.nether.vommet.voice;

import androidx.annotation.NonNull;

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin;
import com.cloudwebrtc.webrtc.audio.AudioProcessingController;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Installs {@link VoiceFilterProcessor} into flutter_webrtc's capture
 * post-processing when Dart calls "install". flutter_webrtc creates its audio
 * processing controller with its peer connection factory, so Dart calls this
 * once a call has started; it returns false if that hasn't happened yet.
 */
public class VoiceFilterPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private static boolean installed = false;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "im.nether.vommet/voice_filter");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!call.method.equals("install")) {
            result.notImplemented();
            return;
        }
        synchronized (VoiceFilterPlugin.class) {
            if (!installed) {
                FlutterWebRTCPlugin webrtc = FlutterWebRTCPlugin.sharedSingleton;
                AudioProcessingController controller =
                        webrtc == null ? null : webrtc.getAudioProcessingController();
                if (controller == null) {
                    result.success(false);
                    return;
                }
                System.loadLibrary("vommet_voice");
                controller.capturePostProcessing.addProcessor(new VoiceFilterProcessor());
                installed = true;
            }
        }
        result.success(true);
    }
}
