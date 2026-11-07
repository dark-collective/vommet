package im.nether.vommet.voice;

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter;

import java.nio.ByteBuffer;

/**
 * Hands each 10 ms capture block (a direct buffer over libwebrtc's floats)
 * to the Rust filter, which processes it in place. The mode lives on the Rust
 * side and is set from Dart, so this stays installed.
 */
class VoiceFilterProcessor implements AudioProcessingAdapter.ExternalAudioFrameProcessing {
    @Override
    public void initialize(int sampleRateHz, int numChannels) {}

    @Override
    public void reset(int newRate) {}

    @Override
    public void process(int numBands, int numFrames, ByteBuffer buffer) {
        nativeProcess(numFrames, buffer);
    }

    private static native void nativeProcess(int numFrames, ByteBuffer buffer);
}
