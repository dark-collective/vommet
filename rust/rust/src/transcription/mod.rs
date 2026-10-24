//! On-device speech-to-text for voice messages (#70): whisper.cpp through
//! whisper-rs. Audio never leaves the device.

pub mod audio;

use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{anyhow, Result};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

pub struct Transcript {
    pub text: String,
    /// Detected (or hinted) language code, e.g. "en".
    pub language: Option<String>,
    /// Mean probability of the text tokens, 0..1. Low values usually mean
    /// mumbling, noise or a language the model handles badly.
    pub confidence: f32,
}

pub enum Outcome {
    Done(Transcript),
    Cancelled,
}

/// The loaded model, kept between messages: loading base takes longer than
/// transcribing a short message.
static MODEL: Mutex<Option<(String, Arc<WhisperContext>)>> = Mutex::new(None);

/// One transcription at a time; whisper already uses every core it is given.
static RUN: Mutex<()> = Mutex::new(());

/// Cancel flags of running or queued jobs, by job id.
fn jobs() -> &'static Mutex<HashMap<i32, Arc<AtomicBool>>> {
    static JOBS: OnceLock<Mutex<HashMap<i32, Arc<AtomicBool>>>> = OnceLock::new();
    JOBS.get_or_init(Default::default)
}

pub fn cancel(job: i32) {
    if let Some(flag) = jobs().lock().unwrap().get(&job) {
        flag.store(true, Ordering::Relaxed);
    }
}

/// Drops the cached model, e.g. before its file is deleted.
pub fn unload_model() {
    *MODEL.lock().unwrap() = None;
}

fn load_model(path: &str) -> Result<Arc<WhisperContext>> {
    let mut slot = MODEL.lock().unwrap();
    if let Some((loaded, ctx)) = slot.as_ref() {
        if loaded == path {
            return Ok(ctx.clone());
        }
    }
    *slot = None;
    static HOOKS: OnceLock<()> = OnceLock::new();
    // Without this whisper.cpp logs every layer to stderr.
    HOOKS.get_or_init(whisper_rs::install_logging_hooks);
    let ctx = WhisperContext::new_with_params(path, WhisperContextParameters::default())
        .map_err(|e| anyhow!("could not load the speech model: {e}"))?;
    let ctx = Arc::new(ctx);
    *slot = Some((path.to_owned(), ctx.clone()));
    Ok(ctx)
}

/// Our x86 builds turn off -march=native (cargokit.yaml), which leaves ggml's
/// defaults: SSE4.2, AVX, AVX2, BMI2, FMA and F16C. Older or low-end CPUs (some
/// Celerons and Pentiums) lack them and would crash on an illegal instruction.
fn check_cpu() -> Result<()> {
    #[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
    {
        if !(std::arch::is_x86_feature_detected!("sse4.2")
            && std::arch::is_x86_feature_detected!("avx")
            && std::arch::is_x86_feature_detected!("avx2")
            && std::arch::is_x86_feature_detected!("bmi2")
            && std::arch::is_x86_feature_detected!("fma")
            && std::arch::is_x86_feature_detected!("f16c"))
        {
            anyhow::bail!("unsupported CPU: transcription needs AVX2");
        }
    }
    Ok(())
}

unsafe extern "C" fn abort_requested(flag: *mut c_void) -> bool {
    (*(flag as *const AtomicBool)).load(Ordering::Relaxed)
}

struct JobGuard(i32);

impl Drop for JobGuard {
    fn drop(&mut self) {
        jobs().lock().unwrap().remove(&self.0);
    }
}

/// Transcribes [audio] (a whole voice message file) with the ggml model at
/// [model_path]. [language] is a code like "en", or None to auto-detect.
/// [progress] gets 0..100.
pub fn transcribe(
    job: i32,
    model_path: &str,
    audio: Vec<u8>,
    mime_type: Option<&str>,
    language: Option<&str>,
    progress: impl FnMut(i32) + 'static,
) -> Result<Outcome> {
    let cancelled = Arc::new(AtomicBool::new(false));
    jobs().lock().unwrap().insert(job, cancelled.clone());
    let _guard = JobGuard(job);

    check_cpu()?;
    let pcm = audio::decode_to_whisper_pcm(audio, mime_type)?;
    if pcm.len() < audio::WHISPER_RATE as usize / 10 {
        return Ok(Outcome::Done(Transcript {
            text: String::new(),
            language: None,
            confidence: 0.0,
        }));
    }

    let _run = RUN.lock().unwrap_or_else(|e| e.into_inner());
    if cancelled.load(Ordering::Relaxed) {
        return Ok(Outcome::Cancelled);
    }

    let ctx = load_model(model_path)?;
    let mut state = ctx
        .create_state()
        .map_err(|e| anyhow!("whisper state: {e}"))?;

    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .min(8);
    params.set_n_threads(threads as i32);
    params.set_language(Some(language.unwrap_or("auto")));
    params.set_translate(false);
    params.set_no_timestamps(true);
    params.set_no_context(true);
    params.set_suppress_blank(true);
    params.set_suppress_nst(true);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_progress_callback_safe(progress);
    // Not set_abort_callback_safe: whisper-rs 0.16 casts its user data to the
    // wrong type there, so it reads garbage and aborts at random.
    // SAFETY: `cancelled` outlives `state.full` below, and an atomic load is
    // fine from whichever thread ggml calls this on.
    unsafe {
        params.set_abort_callback(Some(abort_requested));
        params.set_abort_callback_user_data(Arc::as_ptr(&cancelled) as *mut c_void);
    }

    if let Err(e) = state.full(params, &pcm) {
        if cancelled.load(Ordering::Relaxed) {
            return Ok(Outcome::Cancelled);
        }
        return Err(anyhow!("transcription failed: {e}"));
    }
    if cancelled.load(Ordering::Relaxed) {
        return Ok(Outcome::Cancelled);
    }

    let eot = ctx.token_eot();
    let mut text = String::new();
    let mut prob_sum = 0f64;
    let mut prob_count = 0usize;
    for segment in state.as_iter() {
        // Whisper invents "Thank you." and the like over silence.
        if segment.no_speech_probability() > 0.8 {
            continue;
        }
        if let Ok(s) = segment.to_str_lossy() {
            text.push_str(&s);
        }
        for i in 0..segment.n_tokens() {
            if let Some(token) = segment.get_token(i) {
                // Special tokens (timestamps, language, EOT) sort after EOT.
                if token.token_id() < eot {
                    prob_sum += token.token_probability() as f64;
                    prob_count += 1;
                }
            }
        }
    }

    let language = whisper_rs::get_lang_str(state.full_lang_id_from_state()).map(str::to_owned);
    Ok(Outcome::Done(Transcript {
        text: text.trim().to_owned(),
        language,
        confidence: if prob_count == 0 {
            0.0
        } else {
            (prob_sum / prob_count as f64) as f32
        },
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Needs a model and a recording, so it only runs when asked:
    /// VOMMET_WHISPER_MODEL=ggml-base.bin VOMMET_VOICE_FILE=voice.ogg \
    ///   cargo test --release --lib real_model -- --ignored --nocapture
    #[test]
    #[ignore]
    fn real_model() {
        let model = std::env::var("VOMMET_WHISPER_MODEL").expect("VOMMET_WHISPER_MODEL");
        let file = std::env::var("VOMMET_VOICE_FILE").expect("VOMMET_VOICE_FILE");
        let language = std::env::var("VOMMET_LANGUAGE").ok();
        let audio = std::fs::read(&file).unwrap();
        let start = std::time::Instant::now();
        let outcome = transcribe(1, &model, audio, None, language.as_deref(), |_| {}).unwrap();
        let Outcome::Done(t) = outcome else {
            panic!("cancelled")
        };
        println!(
            "{file}: {:?} ({:?}, confidence {:.2}) in {:?}",
            t.text,
            t.language,
            t.confidence,
            start.elapsed()
        );
        assert!(!t.text.is_empty());
    }

    #[test]
    #[ignore]
    fn real_model_cancel() {
        let model = std::env::var("VOMMET_WHISPER_MODEL").expect("VOMMET_WHISPER_MODEL");
        let file = std::env::var("VOMMET_VOICE_FILE").expect("VOMMET_VOICE_FILE");
        let audio = std::fs::read(file).unwrap();
        let handle = std::thread::spawn(move || transcribe(2, &model, audio, None, None, |_| {}));
        std::thread::sleep(std::time::Duration::from_millis(300));
        cancel(2);
        assert!(matches!(
            handle.join().unwrap().unwrap(),
            Outcome::Cancelled
        ));
    }
}
