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

use std::ffi::{c_int, c_void};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32, AtomicU64, AtomicU8, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

#[cfg(target_os = "android")]
mod android;
pub mod dfn3;

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
/// delivers when it processes at 48 kHz (the usual case on desktop).
const RATE: c_int = 48_000;
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

static MODE: AtomicU8 = AtomicU8::new(MODE_OFF);
/// What the benchmark chose for automatic mode; ENGINE_NONE until it finishes.
static AUTO_CHOICE: AtomicU8 = AtomicU8::new(ENGINE_NONE);
/// Set by the watchdog; cleared whenever the mode is set again.
static DEMOTED: AtomicBool = AtomicBool::new(false);
static MODEL: OnceLock<Option<dfn3::Model>> = OnceLock::new();
static PREPARING: AtomicBool = AtomicBool::new(false);

static FRAMES_PROCESSED: AtomicU64 = AtomicU64::new(0);
static FRAMES_BYPASSED: AtomicU64 = AtomicU64::new(0);
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

struct State {
    rnnoise: Option<Rnnoise>,
    dfn3: Option<Box<dfn3::Dfn3>>,
    avg_us: f32,
    hops: u32,
    scratch: [f32; FRAME as usize],
}

static STATE: Mutex<State> = Mutex::new(State {
    rnnoise: None,
    dfn3: None,
    avg_us: 0.0,
    hops: 0,
    scratch: [0.0; FRAME as usize],
});

pub fn set_mode(mode: u8) {
    MODE.store(mode, Ordering::Relaxed);
    DEMOTED.store(false, Ordering::Relaxed);
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
    pub dfn3_average_us: f32,
    pub benchmark_p90_us: f32,
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
        dfn3_average_us: f(&DFN3_AVG_US),
        benchmark_p90_us: f(&BENCH_P90_US),
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
    pub demoted: u8,
    pub reserved: u8,
    pub dfn3_average_us: f32,
    pub benchmark_p90_us: f32,
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
        demoted: s.demoted as u8,
        reserved: 0,
        dfn3_average_us: s.dfn3_average_us,
        benchmark_p90_us: s.benchmark_p90_us,
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
        process(sample_rate_hz, num_frames, buffer);
        apply_gain(num_frames, buffer);
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

fn process(sample_rate_hz: c_int, num_frames: c_int, buffer: *mut f32) {
    if buffer.is_null() || num_frames <= 0 {
        return;
    }
    LAST_RATE.store(sample_rate_hz, Ordering::Relaxed);

    // Only this thread takes the lock outside of tests, so try_lock never
    // waits; if it ever fails, pass the audio through untouched.
    let Ok(mut state) = STATE.try_lock() else {
        FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
        return;
    };
    let state = &mut *state;

    let engine = wanted_engine();
    LAST_ENGINE.store(engine, Ordering::Relaxed);
    // Free whatever isn't in use, so switching back starts from a clean state.
    if engine != ENGINE_RNNOISE {
        state.rnnoise = None;
    }
    if engine != ENGINE_DFN3 {
        state.dfn3 = None;
    }
    if engine == ENGINE_NONE {
        return;
    }
    if sample_rate_hz != RATE || num_frames != FRAME {
        FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
        return;
    }
    // SAFETY: libwebrtc gives us num_frames (== FRAME here) valid samples,
    // which nothing else touches during this call.
    let samples = unsafe { std::slice::from_raw_parts_mut(buffer, FRAME as usize) };

    if engine == ENGINE_DFN3 {
        let Some(Some(model)) = MODEL.get() else {
            return;
        };
        let d = state.dfn3.get_or_insert_with(|| {
            state.avg_us = 0.0;
            state.hops = 0;
            Box::new(dfn3::Dfn3::new(model.clone()))
        });
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
                None => {
                    FRAMES_BYPASSED.fetch_add(1, Ordering::Relaxed);
                    return;
                }
            },
        };
        let p = samples.as_mut_ptr();
        // SAFETY: RNNoise supports processing in place.
        let vad = unsafe { ffi::rnnoise_process_frame(rn.0, p, p) };
        LAST_VAD.store(vad.to_bits(), Ordering::Relaxed);
    }
    FRAMES_PROCESSED.fetch_add(1, Ordering::Relaxed);
}

#[cfg(test)]
mod tests {
    use super::*;

    // The engine state is global, so the tests run one at a time.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn noise_energy_ratio(hops: usize) -> f64 {
        let mut seed = 1u32;
        let mut noise = || {
            seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            ((seed >> 16) as i32 % 2000 - 1000) as f32
        };
        let (mut energy_in, mut energy_out) = (0f64, 0f64);
        for i in 0..hops {
            let mut buf: Vec<f32> = (0..480).map(|_| noise()).collect();
            let before: f64 = buf.iter().map(|s| (*s as f64).powi(2)).sum();
            vommet_capture_process(std::ptr::null_mut(), 48_000, 480, buf.as_mut_ptr());
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
    fn standard_suppresses_white_noise_and_bypasses_other_rates() {
        let _g = SERIAL.lock();
        set_mode(MODE_STANDARD);
        let ratio = noise_energy_ratio(300);
        assert!(ratio < 0.1, "{ratio}");
        assert_eq!(stats().engine, ENGINE_RNNOISE);

        let mut buf = vec![123.0f32; 160];
        let bypassed = stats().frames_bypassed;
        vommet_capture_process(std::ptr::null_mut(), 16_000, 160, buf.as_mut_ptr());
        assert!(buf.iter().all(|s| *s == 123.0));
        assert_eq!(stats().frames_bypassed, bypassed + 1);
        set_mode(MODE_OFF);
    }

    #[test]
    fn best_uses_rnnoise_until_dfn3_is_ready_then_dfn3() {
        let _g = SERIAL.lock();
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

    #[test]
    fn gain_scales_and_clips_whatever_the_mode() {
        let _g = SERIAL.lock();
        set_mode(MODE_OFF);
        set_gain(1.5);
        let mut buf = vec![1000.0f32, -1000.0, 30000.0, -30000.0];
        buf.resize(480, 0.0);
        vommet_capture_process(std::ptr::null_mut(), 48_000, 480, buf.as_mut_ptr());
        assert_eq!(&buf[..4], &[1500.0, -1500.0, 32767.0, -32768.0]);

        // Other block sizes and rates are scaled too (noise suppression
        // bypasses them, the volume doesn't).
        let mut buf = vec![100.0f32; 160];
        vommet_capture_process(std::ptr::null_mut(), 16_000, 160, buf.as_mut_ptr());
        assert!(buf.iter().all(|s| *s == 150.0));

        set_gain(f32::NAN);
        assert_eq!(gain(), 1.0);
        set_gain(9.0);
        assert_eq!(gain(), MAX_GAIN);
        set_gain(1.0);
    }

    #[test]
    fn off_leaves_audio_alone() {
        let _g = SERIAL.lock();
        set_mode(MODE_OFF);
        let mut buf: Vec<f32> = (0..480).map(|i| i as f32).collect();
        vommet_capture_process(std::ptr::null_mut(), 48_000, 480, buf.as_mut_ptr());
        assert!(buf.iter().enumerate().all(|(i, s)| *s == i as f32));
        assert_eq!(stats().engine, ENGINE_NONE);
    }
}
