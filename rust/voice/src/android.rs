//! JNI entry point for Android, where flutter_webrtc's
//! `AudioProcessingAdapter.ExternalAudioFrameProcessing` hands us each capture
//! block as a direct `ByteBuffer` over libwebrtc's own float buffer (the same
//! one desktop gets). Called from
//! `im.nether.vommet.voice.VoiceFilterProcessor` in the app.

use jni_sys::{jclass, jint, jobject, JNIEnv};

#[no_mangle]
pub extern "system" fn Java_im_nether_vommet_voice_VoiceFilterProcessor_nativeProcess(
    env: *mut JNIEnv,
    _class: jclass,
    num_frames: jint,
    buffer: jobject,
) {
    if env.is_null() || buffer.is_null() || num_frames <= 0 {
        return;
    }
    // SAFETY: a JNIEnv pointer handed to a native method is valid for the
    // call, and every JVM we run on implements JNI 1.4.
    let (data, capacity) = unsafe {
        let functions = &(**env).v1_4;
        (
            (functions.GetDirectBufferAddress)(env, buffer) as *mut f32,
            (functions.GetDirectBufferCapacity)(env, buffer),
        )
    };
    // The buffer is num_bands * 160 floats; num_frames of them are the block.
    if data.is_null() || capacity < num_frames as i64 * 4 {
        return;
    }
    crate::vommet_capture_process(std::ptr::null_mut(), num_frames * 100, num_frames, data);
}
