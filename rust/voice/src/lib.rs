//! Microphone noise suppression run inside libwebrtc's audio pipeline.
//!
//! libwebrtc hands every 10 ms capture block, after its own processing, to
//! [`vommet_capture_process`]: on desktop through our flutter_webrtc fork's
//! `setCapturePostProcessor`, on Android through flutter_webrtc's
//! `AudioProcessingController` and the JNI entry point in `android.rs`. Dart
//! drives it through the `vommet_voice_*` C functions below (`dart:ffi`), on
//! every platform the same way.
//!
//! Two engines: RNNoise (tiny, runs anywhere) and DeepFilterNet3 (clearly
//! better, about 5 % of a fast core). In automatic mode a short benchmark on a
//! background thread decides which one this machine can afford, and a watchdog
//! falls back to RNNoise for the rest of the session if DeepFilterNet3 starts
//! running late during a call.
//!
//! After noise suppression comes automatic gain control when it's on
//! ([`agc`], AGC2's adaptive digital controller, used on desktop in place of
//! libwebrtc's own), then the microphone volume.

use std::ffi::{c_int, c_void};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32, AtomicU64, AtomicU8, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

pub mod agc;
#[cfg(target_os = "android")]
mod android;
pub mod dfn3;
mod resample;

mod ffi {
    use std::ffi::{c_float, c_int, c_void};
    extern "C" {
        pub fn rnnoise_create(model: *mut c_void) -> *mut c_void;
        pub fn rnnoise_destroy(st: *mut c_void);
        #[allow(dead_code)] // only the tests ask
        pub fn rnnoise_get_frame_size() -> c_int;
        pub fn rnnoise_process_frame(
            st: *mut c_void,
            out: *mut c_float,
            input: *const c_float,
        ) -> c_float;
    }
}

pub const MODE_OFF: u8 = 0;
pub const MODE_STANDARD: u8 = 1;
pub const MODE_BEST: u8 = 2;
pub const MODE_AUTO: u8 = 3;

pub const ENGINE_NONE: u8 = 0;
pub const ENGINE_RNNOISE: u8 = 1;
pub const ENGINE_DFN3: u8 = 2;

/// Both engines work on 10 ms at 48 kHz, which is exactly what libwebrtc
/// delivers when it processes at 48 kHz (Linux). Other rates (Windows uses the
/// capture device's, often 16 kHz) are resampled to it and back.
const RATE: c_int = 48_000;
/// Lowest and highest processing rates we resample; anything else passes
/// through untouched.
const MIN_RATE: c_int = 8_000;
const MAX_RATE: c_int = 96_000;
const FRAME: c_int = 480;
const FRAME_US: f32 = 10_000.0;

/// Automatic mode picks DeepFilterNet3 when the benchmark's slow hops (90th
/// percentile) take at most this share of the 10 ms budget.
const AUTO_BUDGET: f32 = 0.25;
/// During a call, fall back to RNNoise once DeepFilterNet3's average hop
/// exceeds this share of the budget. The average moves slowly, so a single
/// preempted hop doesn't trigger it.
const WATCHDOG_BUDGET: f32 = 0.5;
const WATCHDOG_ALPHA: f32 = 0.02;
const WATCHDOG_WARMUP_HOPS: u32 = 100;
/// The silence watchdog: on a resampled stream (Windows hands the filter the
/// 16 kHz output of its Voice Capture DSP), DeepFilterNet3 can take speech
/// for noise and send (near) zeros. An RNNoise that only listens cleans the
/// same input; a hop is "signal" when both the input and what RNNoise keeps
/// of it are above -60 dBFS. Over signal hops only, the watchdog averages
/// (SILENCE_ALPHA) how often DeepFilterNet3's output came out at least 30 dB
/// below its input; once SILENCE_MIN_HOPS signal hops are in and that share
/// reaches SILENCE_SHARE, the stream falls back to RNNoise. Steady noise,
/// which both engines rightly remove, gives no signal hops, so a fan or room
/// noise while the user listens or pauses can't trip it; speech that
/// DeepFilterNet3 lets through keeps the share low.
const SILENCE_ALPHA: f32 = 0.03;
const SILENCE_SHARE: f32 = 0.75;
const SILENCE_MIN_HOPS: u32 = 30;
/// DeepFilterNet3's output lags its input by this many 10 ms hops.
const DFN3_DELAY_HOPS: usize = 3;
/// -60 dBFS as a mean square on the int16 scale.
const SILENCE_IN_MS: f32 = 32768.0 * 32768.0 * 1e-6;
/// "Silenced": the output's mean square below the input's times this (-30 dB).
const SILENCE_ATTENUATION: f32 = 1e-3;

static MODE: AtomicU8 = AtomicU8::new(MODE_OFF);
/// What the benchmark chose for automatic mode; ENGINE_NONE until it finishes.
static AUTO_CHOICE: AtomicU8 = AtomicU8::new(ENGINE_NONE);
/// Set by the watchdog; cleared whenever the mode is set again.
static DEMOTED: AtomicBool = AtomicBool::new(false);
/// Set with [DEMOTED] when the silence watchdog (not the speed one) fired.
static DEMOTED_SILENT: AtomicBool = AtomicBool::new(false);
/// How often the silence watchdog fired since the library loaded.
static SILENCE_DEMOTIONS: AtomicU64 = AtomicU64::new(0);
static MODEL: OnceLock<Option<dfn3::Model>> = OnceLock::new();
static PREPARING: AtomicBool = AtomicBool::new(false);

static FRAMES_PROCESSED: AtomicU64 = AtomicU64::new(0);
static FRAMES_BYPASSED: AtomicU64 = AtomicU64::new(0);
/// Of FRAMES_PROCESSED, the blocks that came at another rate than 48 kHz.
static FRAMES_RESAMPLED: AtomicU64 = AtomicU64::new(0);
static LAST_RATE: AtomicI32 = AtomicI32::new(0);
static LAST_ENGINE: AtomicU8 = AtomicU8::new(ENGINE_NONE);
/// f32 bits: RNNoise's voice probability, the DFN3 watchdog average (µs) and
/// the benchmark's 90th-percentile hop (µs).
static LAST_VAD: AtomicU32 = AtomicU32::new(0);
static DFN3_AVG_US: AtomicU32 = AtomicU32::new(0);
/// Microphone volume (f32 bits), applied after noise suppression; 1.0 leaves
/// the audio alone.
static GAIN: AtomicU32 = AtomicU32::new(0x3f80_0000);
/// Highest microphone volume, as in Discord's 0-200 % input slider.
pub const MAX_GAIN: f32 = 2.0;
static BENCH_P90_US: AtomicU32 = AtomicU32::new(0);

/// Automatic gain control on or off.
static AGC_ON: AtomicBool = AtomicBool::new(false);
/// Set when AGC is switched on, so the audio thread starts it afresh.
static AGC_RESTART: AtomicBool = AtomicBool::new(false);
static AGC_FRAMES: AtomicU64 = AtomicU64::new(0);
/// f32 bits of the controller's state after the last block.
static AGC_GAIN_DB: AtomicU32 = AtomicU32::new(0);
static AGC_SPEECH_DBFS: AtomicU32 = AtomicU32::new(0);
static AGC_NOISE_DBFS: AtomicU32 = AtomicU32::new(0);
static AGC_HEADROOM_DB: AtomicU32 = AtomicU32::new(0);
static AGC_CONFIDENT: AtomicBool = AtomicBool::new(false);

struct Rnnoise(*mut c_void);

// The state is only ever touched from inside STATE's lock.
unsafe impl Send for Rnnoise {}

impl Rnnoise {
    fn new() -> Option<Self> {
        // SAFETY: a null model selects the built-in weights.
        let st = unsafe { ffi::rnnoise_create(std::ptr::null_mut()) };
        (!st.is_null()).then_some(Rnnoise(st))
    }
}

impl Drop for Rnnoise {
    fn drop(&mut self) {
        // SAFETY: created by rnnoise_create and dropped once.
        unsafe { ffi::rnnoise_destroy(self.0) }
    }
}

/// The pair of resamplers for one processing rate.
struct Resampling {
    rate: c_int,
    to_engine: resample::Resampler,
    from_engine: resample::Resampler,
    block: [f32; FRAME as usize],
}

struct State {
    rnnoise: Option<Rnnoise>,
    dfn3: Option<Box<dfn3::Dfn3>>,
    avg_us: f32,
    hops: u32,
    /// Silence watchdog (see SILENCE_ALPHA): its listening RNNoise and its
    /// output, the mean square of the last hops' input and of what RNNoise
    /// kept of it (newest first), the signal hops seen and the silenced share.
    listener: Option<Rnnoise>,
    listened: [f32; FRAME as usize],
    input_history: [(f32, f32); DFN3_DELAY_HOPS + 1],
    signal_hops: u32,
    silenced_share: f32,
    scratch: [f32; FRAME as usize],
    resampling: Option<Box<Resampling>>,
    /// RNNoise's voice probability for the current block, when it ran.
    vad: Option<f32>,
}

static STATE: Mutex<State> = Mutex::new(State {
    rnnoise: None,
    dfn3: None,
    avg_us: 0.0,
    hops: 0,
    listener: None,
    listened: [0.0; FRAME as usize],
    input_history: [(0.0, 0.0); DFN3_DELAY_HOPS + 1],
    signal_hops: 0,
    silenced_share: 0.0,
    scratch: [0.0; FRAME as usize],
    resampling: None,
    vad: None,
});

/// The gain controller and, when the noise suppression engine doesn't give
/// a voice probability (off, or DeepFilterNet3), an RNNoise of its own that
/// only listens: it runs on a 48 kHz copy of the block.
struct AgcRun {
    agc: Option<Box<agc::Agc>>,
    vad: Option<Rnnoise>,
    to_vad: Option<(c_int, resample::Resampler)>,
    block: [f32; FRAME as usize],
    discard: [f32; FRAME as usize],
}

static AGC_STATE: Mutex<AgcRun> = Mutex::new(AgcRun {
    agc: None,
    vad: None,
    to_vad: None,
    block: [0.0; FRAME as usize],
    discard: [0.0; FRAME as usize],
});

/// Sets the noise suppression mode. The app sets it again at every call
/// start and when the microphone volume changes; with the same mode a
/// demotion stays, so a stream DeepFilterNet3 silenced (or was too slow for)
/// keeps RNNoise for the rest of the app run. Only another mode, the user's
/// own choice, clears it.
pub fn set_mode(mode: u8) {
    if MODE.swap(mode, Ordering::Relaxed) != mode {
        DEMOTED.store(false, Ordering::Relaxed);
        DEMOTED_SILENT.store(false, Ordering::Relaxed);
    }
    if mode == MODE_BEST || mode == MODE_AUTO {
        prepare();
    }
}

pub fn mode() -> u8 {
    MODE.load(Ordering::Relaxed)
}

/// Loads DeepFilterNet3 and runs the automatic-mode benchmark on a background
/// thread, once per process, so the audio thread never waits for either.
fn prepare() {
    if MODEL.get().is_some() || PREPARING.swap(true, Ordering::Relaxed) {
        return;
    }
    let spawned = std::thread::Builder::new().name("voice-filter-prepare".into()).spawn(|| {
        let model = match dfn3::Model::load() {
            Ok(m) => Some(m),
            Err(e) => {
                log::error!("voice filter: DeepFilterNet3 failed to load: {e}");
                None
            }
        };
        let choice = match &model {
            Some(m) => {
                let p90 = benchmark(m);
                BENCH_P90_US.store(p90.to_bits(), Ordering::Relaxed);
                let fits = p90 <= AUTO_BUDGET * FRAME_US;
                log::info!(
                    "voice filter: DeepFilterNet3 takes {p90:.0} us per 10 ms (90th percentile); automatic mode uses {}",
                    if fits { "DeepFilterNet3" } else { "RNNoise" }
                );
                if fits { ENGINE_DFN3 } else { ENGINE_RNNOISE }
            }
            None => ENGINE_RNNOISE,
        };
        let _ = MODEL.set(model);
        AUTO_CHOICE.store(choice, Ordering::Relaxed);
    });
    if spawned.is_err() {
        PREPARING.store(false, Ordering::Relaxed);
    }
}

/// 90th-percentile time of one DeepFilterNet3 hop on noisy synthetic audio,
/// running every stage so it measures the worst case.
fn benchmark(model: &dfn3::Model) -> f32 {
    let mut d = dfn3::Dfn3::new(model.clone());
    let mut seed = 0x1234_5678u32;
    let mut frame = [0f32; FRAME as usize];
    let mut times = Vec::with_capacity(300);
    for hop in 0..330 {
        for (i, x) in frame.iter_mut().enumerate() {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            let noise = (seed >> 9) as f32 / (1u32 << 23) as f32 - 0.5;
            let t = (hop * FRAME as usize + i) as f32 / RATE as f32;
            *x = 0.05 * noise + 0.1 * (2.0 * std::f32::consts::PI * 220.0 * t).sin();
        }
        let start = Instant::now();
        d.process(&mut frame);
        if hop >= 30 {
            times.push(start.elapsed().as_secs_f32() * 1e6);
        }
    }
    times.sort_by(|a, b| a.total_cmp(b));
    times[times.len() * 9 / 10]
}

/// The engine the audio thread should use right now.
fn wanted_engine() -> u8 {
    let dfn3_ready = matches!(MODEL.get(), Some(Some(_)));
    let dfn3_or_fallback = || {
        if dfn3_ready && !DEMOTED.load(Ordering::Relaxed) {
            ENGINE_DFN3
        } else {
            // Covers loading time and a watchdog fallback.
            ENGINE_RNNOISE
        }
    };
    match MODE.load(Ordering::Relaxed) {
        MODE_STANDARD => ENGINE_RNNOISE,
        MODE_BEST => dfn3_or_fallback(),
        MODE_AUTO => match AUTO_CHOICE.load(Ordering::Relaxed) {
            ENGINE_DFN3 => dfn3_or_fallback(),
            _ => ENGINE_RNNOISE,
        },
        _ => ENGINE_NONE,
    }
}

pub struct Stats {
    pub frames_processed: u64,
    pub frames_bypassed: u64,
    pub last_sample_rate: i32,
    pub last_voice_probability: f32,
    pub engine: u8,
    pub auto_choice: u8,
    pub demoted: bool,
    /// The demotion came from the silence watchdog.
    pub demoted_silent: bool,
    pub silence_demotions: u64,
    pub dfn3_average_us: f32,
    pub benchmark_p90_us: f32,
    pub frames_resampled: u64,
}

pub fn stats() -> Stats {
    let f = |a: &AtomicU32| f32::from_bits(a.load(Ordering::Relaxed));
    Stats {
        frames_processed: FRAMES_PROCESSED.load(Ordering::Relaxed),
        frames_bypassed: FRAMES_BYPASSED.load(Ordering::Relaxed),
        last_sample_rate: LAST_RATE.load(Ordering::Relaxed),
        last_voice_probability: f(&LAST_VAD),
        engine: LAST_ENGINE.load(Ordering::Relaxed),
        auto_choice: AUTO_CHOICE.load(Ordering::Relaxed),
        demoted: DEMOTED.load(Ordering::Relaxed),
        demoted_silent: DEMOTED_SILENT.load(Ordering::Relaxed),
        silence_demotions: SILENCE_DEMOTIONS.load(Ordering::Relaxed),
        dfn3_average_us: f(&DFN3_AVG_US),
        benchmark_p90_us: f(&BENCH_P90_US),
        frames_resampled: FRAMES_RESAMPLED.load(Ordering::Relaxed),
    }
}

/// Address to hand to the plugin's `setCapturePostProcessor`.
pub fn process_fn_address() -> usize {
    vommet_capture_process as *const () as usize
}

/// Stats for Dart; field order and types are mirrored in voice_filter.dart.
#[repr(C)]
pub struct VommetVoiceStats {
    pub frames_processed: u64,
    pub frames_bypassed: u64,
    pub last_sample_rate: i32,
    pub last_voice_probability: f32,
    pub engine: u8,
    pub auto_choice: u8,
    /// 0 not demoted, 1 DeepFilterNet3 too slow, 2 its output stayed silent.
    pub demoted: u8,
    pub reserved: u8,
    pub dfn3_average_us: f32,
    pub benchmark_p90_us: f32,
    pub frames_resampled: u64,
}

/// Sets the microphone volume: 0.0 silent, 1.0 unchanged, up to [`MAX_GAIN`].
pub fn set_gain(gain: f32) {
    let gain = if gain.is_finite() {
        gain.clamp(0.0, MAX_GAIN)
    } else {
        1.0
    };
    GAIN.store(gain.to_bits(), Ordering::Relaxed);
}

pub fn gain() -> f32 {
    f32::from_bits(GAIN.load(Ordering::Relaxed))
}

#[no_mangle]
pub extern "C" fn vommet_voice_set_gain(gain: f32) {
    set_gain(gain);
}

/// Turns automatic gain control on or off. Turning it on starts from AGC2's
/// initial state (15 dB, adapting from there).
pub fn set_agc(on: bool) {
    if on && !AGC_ON.swap(true, Ordering::Relaxed) {
        AGC_RESTART.store(true, Ordering::Relaxed);
    }
    if !on {
        AGC_ON.store(false, Ordering::Relaxed);
    }
}

pub fn agc_enabled() -> bool {
    AGC_ON.load(Ordering::Relaxed)
}

/// Automatic gain control stats for Dart; mirrored in voice_filter_native.dart.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VommetAgcStats {
    /// Blocks the controller processed.
    pub frames: u64,
    /// The adaptive gain applied to the last block, before the volume.
    pub gain_db: f32,
    /// Estimated speech level of the input.
    pub speech_level_dbfs: f32,
    /// Estimated noise floor of the input.
    pub noise_dbfs: f32,
    /// Headroom the saturation protector keeps for speech peaks.
    pub headroom_db: f32,
    pub enabled: u8,
    /// The speech level estimate has seen enough speech to be trusted.
    pub confident: u8,
    pub reserved: [u8; 6],
}

pub fn agc_stats() -> VommetAgcStats {
    let f = |a: &AtomicU32| f32::from_bits(a.load(Ordering::Relaxed));
    VommetAgcStats {
        frames: AGC_FRAMES.load(Ordering::Relaxed),
        gain_db: f(&AGC_GAIN_DB),
        speech_level_dbfs: f(&AGC_SPEECH_DBFS),
        noise_dbfs: f(&AGC_NOISE_DBFS),
        headroom_db: f(&AGC_HEADROOM_DB),
        enabled: agc_enabled() as u8,
        confident: AGC_CONFIDENT.load(Ordering::Relaxed) as u8,
        reserved: [0; 6],
    }
}

/// 0 = off, anything else = on.
#[no_mangle]
pub extern "C" fn vommet_voice_set_agc(on: u8) {
    set_agc(on != 0);
}

/// Fills `out` (ignored when null).
#[no_mangle]
pub extern "C" fn vommet_voice_agc_stats(out: *mut VommetAgcStats) {
    if out.is_null() {
        return;
    }
    // SAFETY: the caller passes a valid, writable VommetAgcStats.
    unsafe { out.write(agc_stats()) };
}

/// 0 = off, 1 = standard (RNNoise), 2 = best (DeepFilterNet3), 3 = automatic.
#[no_mangle]
pub extern "C" fn vommet_voice_set_mode(mode: u8) {
    set_mode(mode);
}

#[no_mangle]
pub extern "C" fn vommet_voice_mode() -> u8 {
    mode()
}

/// Address of [`vommet_capture_process`], for flutter_webrtc's
/// `setCapturePostProcessor` on desktop.
#[no_mangle]
pub extern "C" fn vommet_voice_process_fn() -> usize {
    process_fn_address()
}

/// Fills `out` (ignored when null).
#[no_mangle]
pub extern "C" fn vommet_voice_stats(out: *mut VommetVoiceStats) {
    if out.is_null() {
        return;
    }
    let s = stats();
    let v = VommetVoiceStats {
        frames_processed: s.frames_processed,
        frames_bypassed: s.frames_bypassed,
        last_sample_rate: s.last_sample_rate,
        last_voice_probability: s.last_voice_probability,
        engine: s.engine,
        auto_choice: s.auto_choice,
        demoted: match (s.demoted, s.demoted_silent) {
            (false, _) => 0,
            (true, false) => 1,
            (true, true) => 2,
        },
        reserved: 0,
        dfn3_average_us: s.dfn3_average_us,
        benchmark_p90_us: s.benchmark_p90_us,
        frames_resampled: s.frames_resampled,
    };
    // SAFETY: the caller passes a valid, writable VommetVoiceStats.
    unsafe { out.write(v) };
}

/// Called by libwebrtc on its audio thread with 10 ms of mono audio, float
/// samples on the int16 scale, processed in place.
#[no_mangle]
pub extern "C" fn vommet_capture_process(
    _user_data: *mut c_void,
    sample_rate_hz: c_int,
    num_frames: c_int,
    buffer: *mut f32,
) {
    // A panic must not unwind into libwebrtc's audio thread. If one happens
    // the state lock is poisoned, and from then on audio passes through.
    let caught = std::panic::catch_unwind(|| {
        let vad = process(sample_rate_hz, num_frames, buffer);
        if !(agc_enabled() && apply_agc(sample_rate_hz, num_frames, buffer, vad)) {
            apply_gain(num_frames, buffer);
        }
    });
    if caught.is_err() {
        FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
    }
}

/// Scales the block by the microphone volume, clipping at the int16 range.
fn apply_gain(num_frames: c_int, buffer: *mut f32) {
    let gain = gain();
    if gain == 1.0 || buffer.is_null() || num_frames <= 0 {
        return;
    }
    // SAFETY: libwebrtc gives us num_frames valid samples, which nothing else
    // touches during this call.
    let samples = unsafe { std::slice::from_raw_parts_mut(buffer, num_frames as usize) };
    for x in samples {
        *x = (*x * gain).clamp(-32768.0, 32767.0);
    }
}

/// Automatic gain control, then the microphone volume as its fixed gain,
/// then its limiter. `vad` is RNNoise's voice probability for this block when
/// noise suppression ran it. False when the block wasn't touched (a size AGC2
/// can't split, such as 44.1 kHz's 441 samples): the caller then applies the
/// volume alone.
fn apply_agc(sample_rate_hz: c_int, num_frames: c_int, buffer: *mut f32, vad: Option<f32>) -> bool {
    // Only 10 ms blocks at a rate the listening RNNoise can resample from.
    let ten_ms = (MIN_RATE..=MAX_RATE).contains(&sample_rate_hz)
        && sample_rate_hz % 100 == 0
        && num_frames == sample_rate_hz / 100;
    if buffer.is_null() || !ten_ms {
        return false;
    }
    // Only the audio thread takes this lock outside of tests.
    let Ok(mut run) = AGC_STATE.try_lock() else {
        return false;
    };
    let run = &mut *run;
    let n = num_frames as usize;
    if AGC_RESTART.swap(false, Ordering::Relaxed) {
        run.agc = None;
        run.vad = None;
        run.to_vad = None;
    }
    if run.agc.as_ref().map(|a| a.samples()) != Some(n) {
        match agc::Agc::new(n) {
            Some(a) => run.agc = Some(Box::new(a)),
            None => {
                run.agc = None;
                return false;
            }
        }
    }
    // SAFETY: libwebrtc gives us num_frames valid samples, which nothing else
    // touches during this call.
    let samples = unsafe { std::slice::from_raw_parts_mut(buffer, n) };

    let speech_probability = match vad {
        Some(v) => {
            // Noise suppression's RNNoise already listened; ours would only
            // go stale.
            run.vad = None;
            run.to_vad = None;
            v
        }
        None => listen(run, sample_rate_hz, samples),
    };
    LAST_VAD.store(speech_probability.to_bits(), Ordering::Relaxed);

    let Some(a) = run.agc.as_mut() else {
        return false;
    };
    a.process(samples, speech_probability, gain());
    let st = a.state();
    AGC_GAIN_DB.store(st.gain_db.to_bits(), Ordering::Relaxed);
    AGC_SPEECH_DBFS.store(st.speech_level_dbfs.to_bits(), Ordering::Relaxed);
    AGC_NOISE_DBFS.store(st.noise_dbfs.to_bits(), Ordering::Relaxed);
    AGC_HEADROOM_DB.store(st.headroom_db.to_bits(), Ordering::Relaxed);
    AGC_CONFIDENT.store(st.speech_level_confident, Ordering::Relaxed);
    AGC_FRAMES.fetch_add(1, Ordering::Relaxed);
    true
}

/// Voice probability of `samples` from the gain controller's own RNNoise,
/// which hears a 48 kHz copy and leaves the block alone. 0 (no speech, so the
/// gain doesn't rise) when RNNoise can't start.
fn listen(run: &mut AgcRun, sample_rate_hz: c_int, samples: &[f32]) -> f32 {
    if run.vad.is_none() {
        run.vad = Rnnoise::new();
    }
    let Some(rn) = run.vad.as_ref() else {
        return 0.0;
    };
    if samples.len() == FRAME as usize {
        run.to_vad = None;
        run.block.copy_from_slice(samples);
    } else {
        let to_vad = match run.to_vad.take() {
            Some((rate, r)) if rate == sample_rate_hz => run.to_vad.insert((rate, r)),
            _ => run.to_vad.insert((
                sample_rate_hz,
                resample::Resampler::new(sample_rate_hz as usize, RATE as usize),
            )),
        };
        to_vad.1.process(samples, &mut run.block);
    }
    // SAFETY: both buffers hold 480 samples, as RNNoise expects.
    unsafe { ffi::rnnoise_process_frame(rn.0, run.discard.as_mut_ptr(), run.block.as_ptr()) }
}

/// Runs noise suppression on the block in place; returns RNNoise's voice
/// probability when it ran.
fn process(sample_rate_hz: c_int, num_frames: c_int, buffer: *mut f32) -> Option<f32> {
    if buffer.is_null() || num_frames <= 0 {
        return None;
    }
    LAST_RATE.store(sample_rate_hz, Ordering::Relaxed);

    // Only this thread takes the lock outside of tests, so try_lock never
    // waits; if it ever fails, pass the audio through untouched.
    let Ok(mut state) = STATE.try_lock() else {
        FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
        return None;
    };
    let state = &mut *state;
    state.vad = None;

    let engine = wanted_engine();
    LAST_ENGINE.store(engine, Ordering::Relaxed);
    // Free whatever isn't in use, so switching back starts from a clean state.
    if engine != ENGINE_RNNOISE {
        state.rnnoise = None;
    }
    if engine != ENGINE_DFN3 {
        state.dfn3 = None;
        state.listener = None;
    }
    if engine == ENGINE_NONE {
        state.resampling = None;
        return None;
    }
    let native = sample_rate_hz == RATE && num_frames == FRAME;
    let resamplable = (MIN_RATE..=MAX_RATE).contains(&sample_rate_hz)
        && sample_rate_hz % 100 == 0
        && num_frames == sample_rate_hz / 100;
    if !native && !resamplable {
        FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
        return None;
    }
    // SAFETY: libwebrtc gives us num_frames valid samples, which nothing else
    // touches during this call.
    let samples = unsafe { std::slice::from_raw_parts_mut(buffer, num_frames as usize) };

    if native {
        state.resampling = None;
        let Ok(frame) = <&mut [f32; FRAME as usize]>::try_from(samples) else {
            return None;
        };
        if !run_engine(state, engine, frame, false) {
            FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
            return None;
        }
    } else {
        // Built on the first block at a new rate (a few thousand filter
        // coefficients, once per rate change).
        let mut rs = match state.resampling.take() {
            Some(rs) if rs.rate == sample_rate_hz => rs,
            _ => {
                let rate = sample_rate_hz as usize;
                Box::new(Resampling {
                    rate: sample_rate_hz,
                    to_engine: resample::Resampler::new(rate, RATE as usize),
                    from_engine: resample::Resampler::new(RATE as usize, rate),
                    block: [0.0; FRAME as usize],
                })
            }
        };
        rs.to_engine.process(samples, &mut rs.block);
        let ok = run_engine(state, engine, &mut rs.block, true);
        if ok {
            rs.from_engine.process(&rs.block, samples);
        }
        state.resampling = Some(rs);
        if !ok {
            FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
            return None;
        }
        FRAMES_RESAMPLED.fetch_add(1, Ordering::Relaxed);
    }
    FRAMES_PROCESSED.fetch_add(1, Ordering::Relaxed);
    state.vad
}

/// Runs `engine` on one 48 kHz block in place. False when it couldn't run
/// (DeepFilterNet3 not loaded, RNNoise failed to start); the block is then
/// unchanged.
fn run_engine(
    state: &mut State,
    engine: u8,
    samples: &mut [f32; FRAME as usize],
    resampled: bool,
) -> bool {
    if engine == ENGINE_DFN3 {
        let Some(Some(model)) = MODEL.get() else {
            return false;
        };
        let d = state.dfn3.get_or_insert_with(|| {
            state.avg_us = 0.0;
            state.hops = 0;
            state.input_history = [(0.0, 0.0); DFN3_DELAY_HOPS + 1];
            state.signal_hops = 0;
            state.silenced_share = 0.0;
            state.listener = None;
            Box::new(dfn3::Dfn3::new(model.clone()))
        });
        let mean_square = |b: &[f32]| b.iter().map(|x| x * x).sum::<f32>() / b.len() as f32;
        if resampled {
            let in_ms = mean_square(samples);
            if state.listener.is_none() {
                state.listener = Rnnoise::new();
            }
            let kept_ms = match state.listener.as_ref() {
                Some(rn) => {
                    // SAFETY: both buffers hold 480 samples, as RNNoise expects.
                    unsafe {
                        ffi::rnnoise_process_frame(
                            rn.0,
                            state.listened.as_mut_ptr(),
                            samples.as_ptr(),
                        )
                    };
                    mean_square(&state.listened)
                }
                None => 0.0,
            };
            state.input_history.rotate_right(1);
            state.input_history[0] = (in_ms, kept_ms);
        }
        let start = Instant::now();
        for (s, x) in state.scratch.iter_mut().zip(samples.iter()) {
            *s = x / 32768.0;
        }
        d.process(&mut state.scratch);
        for (x, s) in samples.iter_mut().zip(state.scratch.iter()) {
            *x = s * 32768.0;
        }
        let us = start.elapsed().as_secs_f32() * 1e6;
        state.hops = state.hops.saturating_add(1);
        state.avg_us = if state.hops == 1 {
            us
        } else {
            state.avg_us + WATCHDOG_ALPHA * (us - state.avg_us)
        };
        DFN3_AVG_US.store(state.avg_us.to_bits(), Ordering::Relaxed);
        // The input this output came from.
        let (in_ms, kept_ms) = state.input_history[DFN3_DELAY_HOPS];
        if resampled && in_ms > SILENCE_IN_MS && kept_ms > SILENCE_IN_MS {
            let silenced = (mean_square(samples) < in_ms * SILENCE_ATTENUATION) as u8 as f32;
            state.signal_hops = state.signal_hops.saturating_add(1);
            state.silenced_share += SILENCE_ALPHA * (silenced - state.silenced_share);
            if state.signal_hops >= SILENCE_MIN_HOPS
                && state.silenced_share >= SILENCE_SHARE
                && !DEMOTED_SILENT.swap(true, Ordering::Relaxed)
            {
                DEMOTED.store(true, Ordering::Relaxed);
                SILENCE_DEMOTIONS.fetch_add(1, Ordering::Relaxed);
                log::warn!(
                    "voice filter: DeepFilterNet3 silenced speech at {} Hz, switching to RNNoise",
                    LAST_RATE.load(Ordering::Relaxed)
                );
            }
        }
        if state.hops > WATCHDOG_WARMUP_HOPS && state.avg_us > WATCHDOG_BUDGET * FRAME_US {
            DEMOTED.store(true, Ordering::Relaxed);
            log::warn!(
                "voice filter: DeepFilterNet3 averages {:.0} us per 10 ms, switching to RNNoise",
                state.avg_us
            );
        }
    } else {
        let rn = match state.rnnoise.as_ref() {
            Some(rn) => rn,
            None => match Rnnoise::new() {
                Some(rn) => state.rnnoise.insert(rn),
                None => return false,
            },
        };
        let p = samples.as_mut_ptr();
        // SAFETY: RNNoise supports processing in place.
        let vad = unsafe { ffi::rnnoise_process_frame(rn.0, p, p) };
        LAST_VAD.store(vad.to_bits(), Ordering::Relaxed);
        state.vad = Some(vad);
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    // The engine state is global, so the tests run one at a time, each from
    // the defaults (also after another test failed halfway).
    static SERIAL: Mutex<()> = Mutex::new(());

    fn serial() -> std::sync::MutexGuard<'static, ()> {
        let g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        set_mode(MODE_OFF);
        set_agc(false);
        set_gain(1.0);
        g
    }

    fn noise_energy_ratio(hops: usize) -> f64 {
        noise_energy_ratio_at(48_000, hops)
    }

    fn noise_energy_ratio_at(rate: c_int, hops: usize) -> f64 {
        let n = rate / 100;
        let mut seed = 1u32;
        let mut noise = || {
            seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            ((seed >> 16) as i32 % 2000 - 1000) as f32
        };
        let (mut energy_in, mut energy_out) = (0f64, 0f64);
        for i in 0..hops {
            let mut buf: Vec<f32> = (0..n).map(|_| noise()).collect();
            let before: f64 = buf.iter().map(|s| (*s as f64).powi(2)).sum();
            vommet_capture_process(std::ptr::null_mut(), rate, n, buf.as_mut_ptr());
            if i >= hops / 3 {
                energy_in += before;
                energy_out += buf.iter().map(|s| (*s as f64).powi(2)).sum::<f64>();
            }
        }
        energy_out / energy_in
    }

    #[test]
    fn frame_size_matches_libwebrtc_block() {
        assert_eq!(unsafe { ffi::rnnoise_get_frame_size() }, FRAME);
    }

    #[test]
    fn standard_suppresses_white_noise_and_bypasses_odd_blocks() {
        let _g = serial();
        set_mode(MODE_STANDARD);
        let ratio = noise_energy_ratio(300);
        assert!(ratio < 0.1, "{ratio}");
        assert_eq!(stats().engine, ENGINE_RNNOISE);

        // A block that isn't 10 ms passes through untouched.
        let mut buf = vec![123.0f32; 100];
        let bypassed = stats().frames_bypassed;
        vommet_capture_process(std::ptr::null_mut(), 16_000, 100, buf.as_mut_ptr());
        assert!(buf.iter().all(|s| *s == 123.0));
        assert_eq!(stats().frames_bypassed, bypassed + 1);
        set_mode(MODE_OFF);
    }

    /// Windows hands us the capture device's rate, often 16 kHz; both
    /// engines run there too, through the resampler.
    #[test]
    fn other_rates_are_resampled_and_suppressed() {
        let _g = serial();
        for mode in [MODE_STANDARD, MODE_BEST] {
            set_mode(mode);
            if mode == MODE_BEST {
                for _ in 0..500 {
                    if matches!(MODEL.get(), Some(Some(_))) {
                        break;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(20));
                }
            }
            for rate in [16_000, 32_000, 44_100] {
                let (processed, resampled) = (stats().frames_processed, stats().frames_resampled);
                let ratio = noise_energy_ratio_at(rate, 300);
                assert!(ratio < 0.1, "mode {mode} at {rate}: {ratio}");
                assert_eq!(stats().last_sample_rate, rate);
                assert_eq!(stats().frames_processed, processed + 300);
                assert_eq!(stats().frames_resampled, resampled + 300);
            }
        }
        set_mode(MODE_OFF);
    }

    #[test]
    fn best_uses_rnnoise_until_dfn3_is_ready_then_dfn3() {
        let _g = serial();
        set_mode(MODE_BEST);
        for _ in 0..500 {
            if matches!(MODEL.get(), Some(Some(_))) {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(matches!(MODEL.get(), Some(Some(_))), "model never loaded");
        let ratio = noise_energy_ratio(300);
        assert_eq!(stats().engine, ENGINE_DFN3);
        assert!(ratio < 0.1, "{ratio}");
        assert_ne!(stats().auto_choice, ENGINE_NONE);
        set_mode(MODE_OFF);
    }

    /// Best mode with the model loaded, starting from fresh engines: one
    /// block in Off frees whatever an earlier test left.
    fn ready_best() {
        set_mode(MODE_OFF);
        run(48_000, &[0.0; 480]);
        set_mode(MODE_BEST);
        for _ in 0..500 {
            if matches!(MODEL.get(), Some(Some(_))) {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(matches!(MODEL.get(), Some(Some(_))), "model never loaded");
    }

    /// 8 s of what libwebrtc handed the filter on Windows: the Voice Capture
    /// DSP's 16 kHz output of the capture smoke test's synthetic speech
    /// (smoke run 41878964235).
    fn dsp_clip() -> Vec<f32> {
        include_bytes!("../testdata/windows_dmo_16k.i16")
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32)
            .collect()
    }

    fn dbfs(x: &[f32]) -> f64 {
        let ms = x.iter().map(|s| (*s as f64).powi(2)).sum::<f64>() / x.len() as f64;
        10.0 * (ms / (32768.0 * 32768.0)).max(1e-30).log10()
    }

    /// Real path: DeepFilterNet3 rates the DSP's speech as noise and returns
    /// exact zeros; the silence watchdog must hand the stream to RNNoise so
    /// the speech gets through.
    #[test]
    fn windows_voice_capture_dsp_speech_is_not_silenced() {
        let _g = serial();
        ready_best();
        let input = dsp_clip();
        let demotions = stats().silence_demotions;
        let out = run(16_000, &input);
        let (level_in, level_out) = (dbfs(tail(&input, 16_000, 2)), dbfs(tail(&out, 16_000, 2)));
        assert!(
            level_out > level_in - 30.0,
            "speech silenced: in {level_in:.1} dBFS, out {level_out:.1} dBFS"
        );
        assert_eq!(stats().engine, ENGINE_RNNOISE);
        assert!(stats().demoted && stats().demoted_silent);
        assert_eq!(stats().silence_demotions, demotions + 1);
        set_mode(MODE_OFF);
        assert!(!stats().demoted && !stats().demoted_silent);
    }

    /// Steady background noise above -60 dBFS on a 16 kHz stream (a fan
    /// while the user listens): DeepFilterNet3 zeroes it, rightly, and must
    /// stay in charge.
    #[test]
    fn silence_watchdog_keeps_dfn3_on_steady_noise() {
        let _g = serial();
        ready_best();
        let demotions = stats().silence_demotions;
        let mut seed = 11u32;
        let noise: Vec<f32> = (0..16_000 * 5)
            .map(|_| {
                seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12_345);
                (((seed >> 8) & 0xffff) as f32 / 32768.0 - 1.0) * 320.0
            })
            .collect();
        let out = run(16_000, &noise);
        let (level_in, level_out) = (dbfs(tail(&noise, 16_000, 3)), dbfs(tail(&out, 16_000, 3)));
        // About -45 dBFS in; DeepFilterNet3 zeroes it.
        assert!(
            level_in > -50.0 && level_out < -80.0,
            "in {level_in:.1}, out {level_out:.1}"
        );
        assert_eq!(stats().engine, ENGINE_DFN3);
        assert!(!stats().demoted, "demoted on steady noise");
        assert_eq!(stats().silence_demotions, demotions);
        set_mode(MODE_OFF);
    }

    /// The watchdog only watches resampled streams (48 kHz platforms keep
    /// DeepFilterNet3 whatever it does), and ignores inputs below -60 dBFS.
    #[test]
    fn silence_watchdog_ignores_native_rate_and_quiet_input() {
        let _g = serial();
        ready_best();
        let demotions = stats().silence_demotions;
        let clip = dsp_clip();
        let mut up = resample::Resampler::new(16_000, 48_000);
        let mut native = vec![0f32; clip.len() * 3];
        for (i, o) in clip.chunks_exact(160).zip(native.chunks_exact_mut(480)) {
            up.process(i, o);
        }
        run(48_000, &native);
        assert_eq!(stats().engine, ENGINE_DFN3);
        assert!(!stats().demoted, "demoted at 48 kHz");
        // The same speech 30 dB down, below the -60 dBFS level gates.
        set_mode(MODE_BEST);
        let quiet: Vec<f32> = clip.iter().map(|s| s * 0.03).collect();
        run(16_000, &quiet);
        assert_eq!(stats().engine, ENGINE_DFN3);
        assert!(!stats().demoted, "demoted on a quiet input");
        assert_eq!(stats().silence_demotions, demotions);
        set_mode(MODE_OFF);
    }

    #[test]
    fn gain_scales_and_clips_whatever_the_mode() {
        let _g = serial();
        set_mode(MODE_OFF);
        set_gain(1.5);
        let mut buf = vec![1000.0f32, -1000.0, 30000.0, -30000.0];
        buf.resize(480, 0.0);
        vommet_capture_process(std::ptr::null_mut(), 48_000, 480, buf.as_mut_ptr());
        assert_eq!(&buf[..4], &[1500.0, -1500.0, 32767.0, -32768.0]);

        // Other block sizes and rates are scaled too.
        let mut buf = vec![100.0f32; 160];
        vommet_capture_process(std::ptr::null_mut(), 16_000, 160, buf.as_mut_ptr());
        assert!(buf.iter().all(|s| *s == 150.0));

        set_gain(f32::NAN);
        assert_eq!(gain(), 1.0);
        set_gain(9.0);
        assert_eq!(gain(), MAX_GAIN);
        set_gain(1.0);
    }

    /// Clean speech (VCTK through DeepFilterNet3, CC BY 4.0, see
    /// third_party/deepfilternet/README.md) looped to `secs` at `rate`,
    /// scaled so its active speech sits at `speech_dbfs`, plus steady white
    /// noise at `noise_dbfs`: a talker at some distance from the microphone in
    /// a quiet room.
    fn talker(rate: c_int, secs: usize, speech_dbfs: f32, noise_dbfs: f32) -> Vec<f32> {
        let bytes = include_bytes!("../third_party/deepfilternet/testdata/fixture_all_out.i16");
        let clip: Vec<f32> = bytes
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32)
            .collect();
        let clip = if rate == RATE {
            clip
        } else {
            let mut r = resample::Resampler::new(RATE as usize, rate as usize);
            let n = rate as usize / 100;
            let mut out = vec![0f32; clip.len() / 480 * n];
            for (i, o) in clip.chunks_exact(480).zip(out.chunks_exact_mut(n)) {
                r.process(i, o);
            }
            out
        };
        let scale = 10f32.powf((speech_dbfs - active_dbfs(&clip, rate)) / 20.0);
        let noise_amp = 32768.0 * 10f32.powf(noise_dbfs / 20.0) * 3f32.sqrt();
        let mut seed = 99u32;
        (0..secs * rate as usize)
            .map(|i| {
                seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                let noise = ((seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0) * noise_amp;
                clip[i % clip.len()] * scale + noise
            })
            .collect()
    }

    /// Level of the loudest half of the 10 ms blocks (the speech, not the
    /// pauses), in dBFS.
    fn active_dbfs(x: &[f32], rate: c_int) -> f32 {
        let n = rate as usize / 100;
        let mut e: Vec<f64> = x
            .chunks_exact(n)
            .map(|b| b.iter().map(|v| (*v as f64).powi(2)).sum::<f64>() / n as f64)
            .collect();
        e.sort_by(|a, b| b.total_cmp(a));
        let top = &e[..e.len() / 2];
        let ms = top.iter().sum::<f64>() / top.len() as f64;
        (10.0 * (ms / (32768.0f64 * 32768.0)).log10()) as f32
    }

    /// Runs `input` through the capture post-processor in 10 ms blocks and
    /// returns the output.
    fn run(rate: c_int, input: &[f32]) -> Vec<f32> {
        let n = rate / 100;
        let mut out = input.to_vec();
        for block in out.chunks_exact_mut(n as usize) {
            vommet_capture_process(std::ptr::null_mut(), rate, n, block.as_mut_ptr());
        }
        out
    }

    /// The last `secs` seconds of `x`, after the controller has settled.
    fn tail(x: &[f32], rate: c_int, secs: usize) -> &[f32] {
        &x[x.len() - secs * rate as usize..]
    }

    #[test]
    fn agc_brings_quiet_and_distant_speech_to_one_level() {
        let _g = serial();
        for mode in [MODE_OFF, MODE_STANDARD] {
            set_mode(mode);
            let mut levels = Vec::new();
            // A close talker and the same one much farther away (-15 dB).
            for speech_dbfs in [-35.0, -50.0] {
                set_agc(false);
                set_agc(true);
                let frames = agc_stats().frames;
                let input = talker(RATE, 30, speech_dbfs, -75.0);
                let output = run(RATE, &input);
                let out_dbfs = active_dbfs(tail(&output, RATE, 10), RATE);
                let s = agc_stats();
                eprintln!(
                    "mode {mode}: speech in {speech_dbfs} dBFS -> out {out_dbfs:.1} dBFS, gain {:.1} dB, \
                     speech estimate {:.1} dBFS (confident {}), noise {:.1} dBFS, headroom {:.1} dB",
                    s.gain_db, s.speech_level_dbfs, s.confident, s.noise_dbfs, s.headroom_db
                );
                // Brought up to a normal speaking level (AGC2 aims at -5 dBFS
                // minus the 12-25 dB peak headroom for the speech level).
                assert!(
                    (-30.0..=-12.0).contains(&out_dbfs),
                    "mode {mode}: {speech_dbfs} came out at {out_dbfs}"
                );
                assert_eq!(s.frames, frames + 3000);
                assert_eq!(s.confident, 1, "never trusted its speech estimate");
                levels.push(out_dbfs);
            }
            // 15 dB apart going in, within 4 dB coming out.
            assert!(
                (levels[0] - levels[1]).abs() <= 4.0,
                "mode {mode}: {levels:?}"
            );
        }
        set_agc(false);
        set_mode(MODE_OFF);
    }

    #[test]
    fn agc_gain_rises_no_faster_than_6_db_per_second() {
        let _g = serial();
        set_mode(MODE_OFF);
        set_agc(false);
        set_agc(true);
        let input = talker(RATE, 20, -55.0, -75.0);
        let mut gains = Vec::new();
        for block in input.chunks_exact(480) {
            let mut b = block.to_vec();
            vommet_capture_process(std::ptr::null_mut(), RATE, FRAME, b.as_mut_ptr());
            gains.push(agc_stats().gain_db);
        }
        // Starts from AGC2's 15 dB; each step is at most 0.06 dB up, except
        // the one catch-up step (12 x 0.06) when speech is first confirmed
        // after a pause.
        assert!((gains[0] - 15.0).abs() < 0.8, "{}", gains[0]);
        let big_steps = gains
            .windows(2)
            .filter(|w| w[1] - w[0] > 0.06 + 1e-3)
            .count();
        let max_step = gains
            .windows(2)
            .map(|w| w[1] - w[0])
            .fold(f32::MIN, f32::max);
        assert!(max_step <= 0.72 + 1e-3, "{max_step}");
        // Over any 1 s window, ignoring catch-up steps, under 6 dB plus those.
        for w in gains.windows(101) {
            assert!(
                w[100] - w[0] <= 6.0 + big_steps as f32 * 0.72,
                "{} -> {}",
                w[0],
                w[100]
            );
        }
        // Still climbing toward its target (-5 dBFS minus about 19 dB of
        // headroom, so about 31 dB) after 20 s; it only moves while speaking.
        assert!(gains.last().unwrap() > &22.0, "{:?}", gains.last());
        set_agc(false);
    }

    #[test]
    fn agc_never_clips_loud_speech_even_at_double_volume() {
        let _g = serial();
        // A loud talker close to the microphone with the volume slider at
        // 200 %: the limiter bends the peaks under full scale instead of
        // slicing them off as plain gain does.
        let input = talker(RATE, 15, -12.0, -70.0);
        let full_scale = |x: &[f32]| x.iter().filter(|v| v.abs() >= 32767.0).count();
        set_mode(MODE_STANDARD);
        set_gain(MAX_GAIN);
        let plain = full_scale(tail(&run(RATE, &input), RATE, 10));
        set_agc(true);
        let output = run(RATE, &input);
        let with_agc = full_scale(tail(&output, RATE, 10));
        let peak = output.iter().fold(0f32, |m, v| m.max(v.abs()));
        eprintln!(
            "loud speech at 200 %: {plain} samples at full scale without AGC, {with_agc} with it, \
             peak {peak}, gain {:.1} dB",
            agc_stats().gain_db
        );
        assert!(plain > 1000, "{plain}");
        assert!(with_agc * 20 < plain, "{with_agc} vs {plain}");
        assert!(agc_stats().gain_db < 3.0, "{}", agc_stats().gain_db);
    }

    #[test]
    fn agc_does_not_pump_room_noise_up() {
        let _g = serial();
        set_mode(MODE_OFF);
        set_agc(false);
        set_agc(true);
        // Nobody talking: a fan at -60 dBFS for 30 s.
        let input = talker(RATE, 30, -200.0, -60.0);
        let output = run(RATE, &input);
        let out_dbfs = active_dbfs(tail(&output, RATE, 10), RATE);
        eprintln!(
            "noise only: out {out_dbfs:.1} dBFS, gain {:.1} dB",
            agc_stats().gain_db
        );
        // AGC2 keeps noise at or under -50 dBFS whatever its VAD says.
        assert!(out_dbfs <= -49.0, "{out_dbfs}");
        set_agc(false);
    }

    /// Windows hands over the device's rate; AGC runs there too, with its
    /// RNNoise listening to a resampled copy.
    #[test]
    fn agc_runs_at_other_rates() {
        let _g = serial();
        for mode in [MODE_OFF, MODE_STANDARD] {
            set_mode(mode);
            for rate in [16_000, 32_000] {
                set_agc(false);
                set_agc(true);
                let output = run(rate, &talker(rate, 30, -50.0, -75.0));
                let out_dbfs = active_dbfs(tail(&output, rate, 10), rate);
                eprintln!("mode {mode} at {rate}: -50 dBFS speech -> {out_dbfs:.1} dBFS");
                assert!(
                    (-30.0..=-12.0).contains(&out_dbfs),
                    "mode {mode} at {rate}: {out_dbfs}"
                );
            }
        }
        // 44.1 kHz blocks (441 samples) can't be split in 20; they get the
        // plain volume instead.
        set_mode(MODE_OFF);
        set_gain(1.5);
        let frames = agc_stats().frames;
        let mut buf = vec![100.0f32; 441];
        vommet_capture_process(std::ptr::null_mut(), 44_100, 441, buf.as_mut_ptr());
        assert!(buf.iter().all(|s| *s == 150.0));
        assert_eq!(agc_stats().frames, frames);
        set_gain(1.0);
        set_agc(false);
        set_mode(MODE_OFF);
    }

    /// What the app does today on desktop with AGC on: libwebrtc's AGC1 never
    /// sees a microphone volume to steer, and our filter leaves the level
    /// alone. This is the level the tests above must beat.
    #[test]
    fn without_agc_quiet_speech_stays_quiet() {
        let _g = serial();
        set_mode(MODE_STANDARD);
        set_agc(false);
        let input = talker(RATE, 10, -50.0, -75.0);
        let out_dbfs = active_dbfs(tail(&run(RATE, &input), RATE, 5), RATE);
        eprintln!("no AGC: -50 dBFS speech -> {out_dbfs:.1} dBFS");
        assert!(out_dbfs < -45.0, "{out_dbfs}");
        assert_eq!(agc_stats().enabled, 0);
        set_mode(MODE_OFF);
    }

    #[test]
    fn off_leaves_audio_alone() {
        let _g = serial();
        set_mode(MODE_OFF);
        let mut buf: Vec<f32> = (0..480).map(|i| i as f32).collect();
        vommet_capture_process(std::ptr::null_mut(), 48_000, 480, buf.as_mut_ptr());
        assert!(buf.iter().enumerate().all(|(i, s)| *s == i as f32));
        assert_eq!(stats().engine, ENGINE_NONE);
    }
    /// The app sets the same mode again at every call start and when the
    /// microphone volume changes: a silenced stream must stay on RNNoise.
    #[test]
    fn silence_demotion_survives_the_same_mode_again() {
        let _g = serial();
        ready_best();
        let clip = dsp_clip();
        run(16_000, &clip);
        assert_eq!(stats().engine, ENGINE_RNNOISE);
        set_mode(MODE_BEST);
        let out = run(16_000, &clip[..16_000]);
        assert_eq!(
            stats().engine,
            ENGINE_RNNOISE,
            "same mode again re-enabled DeepFilterNet3"
        );
        assert!(stats().demoted && stats().demoted_silent);
        assert!(dbfs(&out[8_000..]) > dbfs(&clip[8_000..16_000]) - 30.0);
        set_mode(MODE_OFF);
    }

    /// Choosing another mode and back is the user's own choice: it clears
    /// the demotion and DeepFilterNet3 runs again.
    #[test]
    fn another_mode_clears_the_silence_demotion() {
        let _g = serial();
        ready_best();
        let clip = dsp_clip();
        run(16_000, &clip);
        assert!(stats().demoted_silent);
        set_mode(MODE_STANDARD);
        set_mode(MODE_BEST);
        assert!(!stats().demoted && !stats().demoted_silent);
        // Fewer blocks than the watchdog needs to judge.
        run(16_000, &clip[..1_600]);
        assert_eq!(stats().engine, ENGINE_DFN3);
        set_mode(MODE_OFF);
    }
}
