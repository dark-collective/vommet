//! Voice message transcription (#70), see `crate::transcription`. Desktop
//! and Android; elsewhere every call reports that it isn't available.

use crate::frb_generated::StreamSink;

/// One update from a running transcription: progress until `result` is set
/// or `cancelled` is true.
#[derive(Clone)]
pub struct TranscriptionEvent {
    /// 0..100
    pub progress: i32,
    pub result: Option<TranscriptionResult>,
    pub cancelled: bool,
}

#[derive(Clone)]
pub struct TranscriptionResult {
    pub text: String,
    /// Detected (or hinted) language code, e.g. "en".
    pub language: Option<String>,
    /// Mean probability of the text tokens, 0..1.
    pub confidence: f32,
}

/// Runs off the UI thread; the stream ends after the result or cancellation,
/// or with an error.
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos", target_os = "android"))]
pub fn transcribe_voice_message(
    job: i32,
    model_path: String,
    audio: Vec<u8>,
    mime_type: Option<String>,
    language: Option<String>,
    sink: StreamSink<TranscriptionEvent>,
) -> anyhow::Result<()> {
    use crate::transcription::{self, Outcome};

    let progress_sink = sink.clone();
    let outcome = transcription::transcribe(
        job,
        &model_path,
        audio,
        mime_type.as_deref(),
        language.as_deref(),
        move |p| {
            // whisper overshoots on clips shorter than its 30 s window.
            let _ = progress_sink.add(TranscriptionEvent {
                progress: p.clamp(0, 100),
                result: None,
                cancelled: false,
            });
        },
    )?;
    let event = match outcome {
        Outcome::Done(t) => TranscriptionEvent {
            progress: 100,
            result: Some(TranscriptionResult {
                text: t.text,
                language: t.language,
                confidence: t.confidence,
            }),
            cancelled: false,
        },
        Outcome::Cancelled => TranscriptionEvent {
            progress: 0,
            result: None,
            cancelled: true,
        },
    };
    let _ = sink.add(event);
    Ok(())
}

#[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos", target_os = "android")))]
pub fn transcribe_voice_message(
    job: i32,
    model_path: String,
    audio: Vec<u8>,
    mime_type: Option<String>,
    language: Option<String>,
    sink: StreamSink<TranscriptionEvent>,
) -> anyhow::Result<()> {
    let _ = (job, model_path, audio, mime_type, language, sink);
    anyhow::bail!("transcription isn't available on this platform yet")
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_transcription(job: i32) {
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos", target_os = "android"))]
    crate::transcription::cancel(job);
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos", target_os = "android")))]
    let _ = job;
}

/// Frees the loaded speech model (call before deleting its file).
#[flutter_rust_bridge::frb(sync)]
pub fn unload_transcription_model() {
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos", target_os = "android"))]
    crate::transcription::unload_model();
}
