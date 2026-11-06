//! Automatic gain control: a port of libwebrtc's AGC2 adaptive digital
//! controller (`modules/audio_processing/agc2`, webrtc-sdk m150, BSD-3-Clause,
//! Copyright The WebRTC project authors), which is what Chrome and Element
//! Call run when the browser has no analog microphone volume to steer.
//!
//! Why our own: on Linux and Windows, libwebrtc's `autoGainControl` runs the
//! legacy AGC1 in analog mode, which expects to move the system microphone
//! volume, and the native desktop audio path never gives it that volume. Only
//! its digital half runs, and quiet or distant speech comes out lower and
//! muffled (Vommet issue 868). The prebuilt libwebrtc has no way to switch its
//! own AGC2 on, but our capture post-processor runs right where AGC2 would
//! (after noise suppression, at the end of the capture chain), so the same
//! algorithm runs here instead and libwebrtc's AGC stays off.
//!
//! Per 10 ms block: a voice probability (RNNoise's, where AGC2 has its own RNN
//! VAD of the same family) gates a speech level estimate; a saturation
//! protector keeps headroom for the speech peaks; a noise floor estimate caps
//! the gain so background noise isn't boosted above -50 dBFS; the gain moves
//! at most 6 dB/s toward bringing speech to -5 dBFS minus the headroom, ramped
//! per sample. Then the fixed gain (our microphone volume slider, AGC2's
//! `fixed_digital` stage) and the limiter, whose gain curve is AGC2's own
//! interpolated table. It never touches the OS microphone volume.
//!
//! Samples are floats on the int16 scale, as libwebrtc hands them over.

// The constants and the limiter's gain curve are AGC2's, digit for digit.
#![allow(clippy::excessive_precision)]

/// AGC2 `AdaptiveDigital` defaults (api/audio/audio_processing.h).
const HEADROOM_DB: f32 = 5.0;
const MAX_GAIN_DB: f32 = 50.0;
const INITIAL_GAIN_DB: f32 = 15.0;
const MAX_GAIN_CHANGE_DB_PER_SECOND: f32 = 6.0;
const MAX_OUTPUT_NOISE_LEVEL_DBFS: f32 = -50.0;

/// agc2_common.h.
const MIN_LEVEL_DBFS: f32 = -90.31;
const FRAME_DURATION_MS: i32 = 10;
const SUB_FRAMES_IN_FRAME: usize = 20;
const LIMITER_THRESHOLD_FOR_AGC_GAIN_DBFS: f32 = -1.0;
const VAD_CONFIDENCE_THRESHOLD: f32 = 0.95;
const ADJACENT_SPEECH_FRAMES_THRESHOLD: i32 = 12;
const LEVEL_ESTIMATOR_TIME_TO_CONFIDENCE_MS: i32 = 400;
const LEVEL_ESTIMATOR_LEAK_FACTOR: f32 = 1.0 - 1.0 / LEVEL_ESTIMATOR_TIME_TO_CONFIDENCE_MS as f32;
const SATURATION_PROTECTOR_INITIAL_HEADROOM_DB: f32 = 20.0;
const SATURATION_PROTECTOR_BUFFER_SIZE: usize = 4;
const MAX_FLOAT_S16: f32 = 32767.0;
const MIN_FLOAT_S16: f32 = -32768.0;

/// Largest block we accept: 10 ms at 96 kHz.
pub const MAX_FRAME: usize = 960;

fn float_s16_to_dbfs(v: f32) -> f32 {
    // agc2_common / audio_util FloatS16ToDbfs.
    if v <= 1.0 {
        return MIN_LEVEL_DBFS;
    }
    20.0 * v.log10() + MIN_LEVEL_DBFS
}

fn db_to_ratio(db: f32) -> f32 {
    10f32.powf(db / 20.0)
}

/// SpeechLevelEstimatorImpl.
#[derive(Clone, Copy)]
struct LevelEstimatorState {
    time_to_confidence_ms: i32,
    numerator: f32,
    denominator: f32,
}

struct SpeechLevelEstimator {
    initial_level_dbfs: f32,
    preliminary: LevelEstimatorState,
    reliable: LevelEstimatorState,
    level_dbfs: f32,
    is_confident: bool,
    num_adjacent_speech_frames: i32,
}

impl SpeechLevelEstimator {
    fn new() -> Self {
        let initial_level_dbfs =
            (-SATURATION_PROTECTOR_INITIAL_HEADROOM_DB - INITIAL_GAIN_DB - HEADROOM_DB)
                .clamp(-90.0, 30.0);
        let state = LevelEstimatorState {
            time_to_confidence_ms: LEVEL_ESTIMATOR_TIME_TO_CONFIDENCE_MS,
            numerator: initial_level_dbfs,
            denominator: 1.0,
        };
        SpeechLevelEstimator {
            initial_level_dbfs,
            preliminary: state,
            reliable: state,
            level_dbfs: initial_level_dbfs,
            is_confident: false,
            num_adjacent_speech_frames: 0,
        }
    }

    fn update(&mut self, rms_dbfs: f32, speech_probability: f32) {
        if speech_probability < VAD_CONFIDENCE_THRESHOLD {
            // Not a speech frame.
            if self.num_adjacent_speech_frames >= ADJACENT_SPEECH_FRAMES_THRESHOLD {
                // A long enough speech sequence was just observed.
                self.reliable = self.preliminary;
            } else if self.num_adjacent_speech_frames > 0 {
                // Too short: roll back.
                self.preliminary = self.reliable;
            }
            self.num_adjacent_speech_frames = 0;
        } else {
            self.num_adjacent_speech_frames += 1;
            let buffer_is_full = self.preliminary.time_to_confidence_ms == 0;
            if !buffer_is_full {
                self.preliminary.time_to_confidence_ms -= FRAME_DURATION_MS;
            }
            let leak = if buffer_is_full {
                LEVEL_ESTIMATOR_LEAK_FACTOR
            } else {
                1.0
            };
            self.preliminary.numerator =
                self.preliminary.numerator * leak + rms_dbfs * speech_probability;
            self.preliminary.denominator = self.preliminary.denominator * leak + speech_probability;
            let level_dbfs = self.preliminary.numerator / self.preliminary.denominator;
            if self.num_adjacent_speech_frames >= ADJACENT_SPEECH_FRAMES_THRESHOLD {
                self.level_dbfs = level_dbfs.clamp(-90.0, 30.0);
            }
        }
        self.is_confident = self.reliable.time_to_confidence_ms == 0
            || (self.num_adjacent_speech_frames >= ADJACENT_SPEECH_FRAMES_THRESHOLD
                && self.preliminary.time_to_confidence_ms == 0);
    }

    #[allow(dead_code)] // kept for parity with AGC2
    fn initial_level_dbfs(&self) -> f32 {
        self.initial_level_dbfs
    }
}

/// SaturationProtectorBuffer + SaturationProtectorImpl.
#[derive(Clone, Copy)]
struct SaturationState {
    headroom_db: f32,
    buffer: [f32; SATURATION_PROTECTOR_BUFFER_SIZE],
    next: usize,
    size: usize,
    max_peaks_dbfs: f32,
    time_since_push_ms: i32,
}

impl SaturationState {
    fn new() -> Self {
        SaturationState {
            headroom_db: SATURATION_PROTECTOR_INITIAL_HEADROOM_DB,
            buffer: [0.0; SATURATION_PROTECTOR_BUFFER_SIZE],
            next: 0,
            size: 0,
            max_peaks_dbfs: MIN_LEVEL_DBFS,
            time_since_push_ms: 0,
        }
    }

    fn push_back(&mut self, v: f32) {
        self.buffer[self.next] = v;
        self.next = (self.next + 1) % SATURATION_PROTECTOR_BUFFER_SIZE;
        if self.size < SATURATION_PROTECTOR_BUFFER_SIZE {
            self.size += 1;
        }
    }

    fn front(&self) -> Option<f32> {
        if self.size == 0 {
            return None;
        }
        let i = if self.size == SATURATION_PROTECTOR_BUFFER_SIZE {
            self.next
        } else {
            0
        };
        Some(self.buffer[i])
    }

    fn update(&mut self, peak_dbfs: f32, speech_level_dbfs: f32) {
        const PEAK_ENVELOPER_SUPER_FRAME_LENGTH_MS: i32 = 400;
        const MIN_MARGIN_DB: f32 = 12.0;
        const MAX_MARGIN_DB: f32 = 25.0;
        const ATTACK: f32 = 0.998_849_369_936_505_2;
        const DECAY: f32 = 0.999_769_767_998_156_5;
        self.max_peaks_dbfs = self.max_peaks_dbfs.max(peak_dbfs);
        self.time_since_push_ms += FRAME_DURATION_MS;
        if self.time_since_push_ms > PEAK_ENVELOPER_SUPER_FRAME_LENGTH_MS {
            self.push_back(self.max_peaks_dbfs);
            self.max_peaks_dbfs = MIN_LEVEL_DBFS;
            self.time_since_push_ms = 0;
        }
        let delayed_peak_dbfs = self.front().unwrap_or(self.max_peaks_dbfs);
        let difference_db = delayed_peak_dbfs - speech_level_dbfs;
        let k = if difference_db > self.headroom_db {
            ATTACK
        } else {
            DECAY
        };
        self.headroom_db = self.headroom_db * k + difference_db * (1.0 - k);
        self.headroom_db = self.headroom_db.clamp(MIN_MARGIN_DB, MAX_MARGIN_DB);
    }
}

struct SaturationProtector {
    num_adjacent_speech_frames: i32,
    headroom_db: f32,
    preliminary: SaturationState,
    reliable: SaturationState,
}

impl SaturationProtector {
    fn new() -> Self {
        SaturationProtector {
            num_adjacent_speech_frames: 0,
            headroom_db: SATURATION_PROTECTOR_INITIAL_HEADROOM_DB,
            preliminary: SaturationState::new(),
            reliable: SaturationState::new(),
        }
    }

    fn analyze(&mut self, speech_probability: f32, peak_dbfs: f32, speech_level_dbfs: f32) {
        if speech_probability < VAD_CONFIDENCE_THRESHOLD {
            if self.num_adjacent_speech_frames >= ADJACENT_SPEECH_FRAMES_THRESHOLD {
                self.reliable = self.preliminary;
            } else if self.num_adjacent_speech_frames > 0 {
                self.preliminary = self.reliable;
            }
            self.num_adjacent_speech_frames = 0;
        } else {
            self.num_adjacent_speech_frames += 1;
            self.preliminary.update(peak_dbfs, speech_level_dbfs);
            if self.num_adjacent_speech_frames >= ADJACENT_SPEECH_FRAMES_THRESHOLD {
                self.headroom_db = self.preliminary.headroom_db;
            }
        }
    }
}

/// NoiseFloorEstimator (noise_level_estimator.cc).
struct NoiseFloorEstimator {
    samples: usize,
    min_noise_energy: f32,
    first_period: bool,
    preliminary_set: bool,
    preliminary_noise_energy: f32,
    noise_energy: f32,
    counter: i32,
}

impl NoiseFloorEstimator {
    const UPDATE_PERIOD_NUM_FRAMES: i32 = 500;

    fn new(samples: usize) -> Self {
        let sample_rate_hz = samples as f32 * 100.0;
        let min_noise_energy = sample_rate_hz * 2.0 * 2.0 / 100.0;
        NoiseFloorEstimator {
            samples,
            min_noise_energy,
            first_period: true,
            preliminary_set: false,
            preliminary_noise_energy: min_noise_energy,
            noise_energy: min_noise_energy,
            counter: Self::UPDATE_PERIOD_NUM_FRAMES,
        }
    }

    fn energy_to_dbfs(&self, energy: f32) -> f32 {
        const MIN_DBFS: f32 = -90.308_998_699_194_36;
        let rms_square = energy / self.samples as f32;
        if rms_square <= 1.0 {
            return MIN_DBFS;
        }
        10.0 * rms_square.log10() + MIN_DBFS
    }

    fn analyze(&mut self, frame: &[f32]) -> f32 {
        let frame_energy: f32 = frame.iter().map(|x| x * x).sum();
        if frame_energy <= self.min_noise_energy {
            // Ignore frames when muted or below the minimum measurable energy.
            return self.energy_to_dbfs(self.noise_energy);
        }
        if self.preliminary_set {
            self.preliminary_noise_energy = self.preliminary_noise_energy.min(frame_energy);
        } else {
            self.preliminary_noise_energy = frame_energy;
            self.preliminary_set = true;
        }
        if self.counter == 0 {
            // Full period observed.
            self.first_period = false;
            // Update the estimate: fast decay, slow attack (kAttack 0.5).
            self.noise_energy = if self.noise_energy < self.preliminary_noise_energy {
                0.5 * self.preliminary_noise_energy + 0.5 * self.noise_energy
            } else {
                self.preliminary_noise_energy
            };
            self.counter = Self::UPDATE_PERIOD_NUM_FRAMES;
            self.preliminary_set = false;
        } else if self.first_period {
            // While the first period is not yet complete, use the preliminary
            // estimate.
            self.noise_energy = self.preliminary_noise_energy;
            self.counter -= 1;
        } else {
            // A full period has been observed at least once.
            self.noise_energy = self.noise_energy.min(self.preliminary_noise_energy);
            self.counter -= 1;
        }
        self.energy_to_dbfs(self.noise_energy)
    }
}

/// GainApplier with ramping (gain_applier.cc), no hard clipping.
struct GainApplier {
    last_gain_factor: f32,
    current_gain_factor: f32,
}

impl GainApplier {
    fn new(initial_gain_factor: f32) -> Self {
        GainApplier {
            last_gain_factor: initial_gain_factor,
            current_gain_factor: initial_gain_factor,
        }
    }

    fn apply(&mut self, frame: &mut [f32]) {
        let (last, end) = (self.last_gain_factor, self.current_gain_factor);
        let close_to_one = (1.0 - 1.0 / MAX_FLOAT_S16..=1.0 + 1.0 / MAX_FLOAT_S16).contains(&end);
        if last == end && close_to_one {
        } else if last == end {
            frame.iter_mut().for_each(|x| *x *= end);
        } else {
            let increment = (end - last) / frame.len() as f32;
            let mut gain = last;
            for x in frame.iter_mut() {
                *x *= gain;
                gain += increment;
            }
        }
        self.last_gain_factor = end;
    }
}

/// What AdaptiveDigitalGainController::Process gets per frame.
struct FrameInfo {
    speech_probability: f32,
    speech_level_dbfs: f32,
    speech_level_reliable: bool,
    noise_rms_dbfs: f32,
    headroom_db: f32,
    limiter_envelope_dbfs: f32,
}

/// AdaptiveDigitalGainController (adaptive_digital_gain_controller.cc).
struct AdaptiveDigitalGainController {
    applier: GainApplier,
    max_gain_change_db_per_10ms: f32,
    frames_to_gain_increase_allowed: i32,
    last_gain_db: f32,
}

impl AdaptiveDigitalGainController {
    fn new() -> Self {
        AdaptiveDigitalGainController {
            applier: GainApplier::new(db_to_ratio(INITIAL_GAIN_DB)),
            max_gain_change_db_per_10ms: MAX_GAIN_CHANGE_DB_PER_SECOND * FRAME_DURATION_MS as f32
                / 1000.0,
            frames_to_gain_increase_allowed: ADJACENT_SPEECH_FRAMES_THRESHOLD,
            last_gain_db: INITIAL_GAIN_DB,
        }
    }

    /// Gain to bring `input_level_dbfs` to `-HEADROOM_DB`, in [0, MAX_GAIN_DB].
    fn compute_gain_db(input_level_dbfs: f32) -> f32 {
        if input_level_dbfs < -(HEADROOM_DB + MAX_GAIN_DB) {
            MAX_GAIN_DB
        } else if input_level_dbfs < -HEADROOM_DB {
            -HEADROOM_DB - input_level_dbfs
        } else {
            0.0
        }
    }

    fn limit_gain_by_noise(target_gain_db: f32, input_noise_level_dbfs: f32) -> f32 {
        let max_allowed_gain_db = MAX_OUTPUT_NOISE_LEVEL_DBFS - input_noise_level_dbfs;
        target_gain_db.min(max_allowed_gain_db.max(0.0))
    }

    fn limit_gain_by_low_confidence(
        target_gain_db: f32,
        last_gain_db: f32,
        limiter_audio_level_dbfs: f32,
        estimate_is_confident: bool,
    ) -> f32 {
        if estimate_is_confident || limiter_audio_level_dbfs <= LIMITER_THRESHOLD_FOR_AGC_GAIN_DBFS
        {
            return target_gain_db;
        }
        let limiter_level_dbfs_before_gain = limiter_audio_level_dbfs - last_gain_db;
        let new_target_gain_db =
            (LIMITER_THRESHOLD_FOR_AGC_GAIN_DBFS - limiter_level_dbfs_before_gain).max(0.0);
        new_target_gain_db.min(target_gain_db)
    }

    fn process(&mut self, info: &FrameInfo, frame: &mut [f32]) {
        let input_level_dbfs = info.speech_level_dbfs + info.headroom_db;
        let target_gain_db = Self::limit_gain_by_low_confidence(
            Self::limit_gain_by_noise(Self::compute_gain_db(input_level_dbfs), info.noise_rms_dbfs),
            self.last_gain_db,
            info.limiter_envelope_dbfs,
            info.speech_level_reliable,
        );

        // Forbid increasing the gain until enough adjacent speech frames are
        // observed.
        let mut first_confident_speech_frame = false;
        if info.speech_probability < VAD_CONFIDENCE_THRESHOLD {
            self.frames_to_gain_increase_allowed = ADJACENT_SPEECH_FRAMES_THRESHOLD;
        } else if self.frames_to_gain_increase_allowed > 0 {
            self.frames_to_gain_increase_allowed -= 1;
            first_confident_speech_frame = self.frames_to_gain_increase_allowed == 0;
        }
        let gain_increase_allowed = self.frames_to_gain_increase_allowed == 0;

        let mut max_gain_increase_db = self.max_gain_change_db_per_10ms;
        if first_confident_speech_frame {
            // No gain increase happened while waiting for a long enough speech
            // sequence, so temporarily allow a faster one.
            max_gain_increase_db *= ADJACENT_SPEECH_FRAMES_THRESHOLD as f32;
        }

        let mut difference_db = target_gain_db - self.last_gain_db;
        if !gain_increase_allowed {
            difference_db = difference_db.min(0.0);
        }
        let change_db =
            difference_db.clamp(-self.max_gain_change_db_per_10ms, max_gain_increase_db);
        if change_db != 0.0 {
            self.applier.current_gain_factor = db_to_ratio(self.last_gain_db + change_db);
        }
        self.applier.apply(frame);
        self.last_gain_db += change_db;
    }
}

/// AGC2's limiter gain curve, InterpolatedGainCurve's piecewise-linear table
/// (interpolated_gain_curve.h): gain = m[i] * level + q[i] in the knee and
/// limiter regions.
#[rustfmt::skip]
const LIMITER_X: [f32; 32] = [
    30057.296875, 30148.986328125, 30240.67578125, 30424.052734375,
    30607.4296875, 30790.806640625, 30974.18359375, 31157.560546875,
    31340.939453125, 31524.31640625, 31707.693359375, 31891.0703125,
    32074.447265625, 32257.82421875, 32441.201171875, 32624.580078125,
    32807.95703125, 32991.33203125, 33174.7109375, 33358.08984375,
    33541.46484375, 33724.84375, 33819.53515625, 34009.5390625,
    34200.05859375, 34389.81640625, 34674.48828125, 35054.375,
    35434.86328125, 35814.81640625, 36195.16796875, 36575.03125,
];
#[rustfmt::skip]
const LIMITER_M: [f32; 32] = [
    -3.515235675877192989e-07, -1.050251626111275982e-06, -2.085213736791047268e-06, -3.443004743530764244e-06,
    -4.773849468620028347e-06, -6.077375928725814447e-06, -7.353257842623861507e-06, -8.601219633419532329e-06,
    -9.821013009059242904e-06, -1.101243378798244521e-05, -1.217532644659513608e-05, -1.330956911260727793e-05,
    -1.441507538402220234e-05, -1.549179251014720649e-05, -1.653970684856176376e-05, -1.755882840370759368e-05,
    -1.854918446042574942e-05, -1.951086778717581183e-05, -2.044398024736437947e-05, -2.1348627342376858e-05,
    -2.222496914328075945e-05, -2.265374678245279938e-05, -2.242570917587727308e-05, -2.220122041762806475e-05,
    -2.19802095671184361e-05, -2.176260204578284174e-05, -2.133731686626560986e-05, -2.092481918225530535e-05,
    -2.052459603874012828e-05, -2.013615448959171772e-05, -1.975903069251216948e-05, -1.939277899509761482e-05,
];
#[rustfmt::skip]
const LIMITER_Q: [f32; 32] = [
    1.010565876960754395, 1.031631827354431152, 1.062929749488830566, 1.104239225387573242,
    1.144973039627075195, 1.185109615325927734, 1.224629044532775879, 1.263512492179870605,
    1.301741957664489746, 1.339300632476806641, 1.376173257827758789, 1.412345528602600098,
    1.447803974151611328, 1.482536554336547852, 1.516532182693481445, 1.549780607223510742,
    1.582272171974182129, 1.613999366760253906, 1.644955039024353027, 1.675132393836975098,
    1.704526185989379883, 1.718986630439758301, 1.711274504661560059, 1.703639745712280273,
    1.696081161499023438, 1.688597679138183594, 1.673851132392883301, 1.659391283988952637,
    1.645209431648254395, 1.631297469139099121, 1.617647409439086914, 1.604251742362976074,
];
/// DbfsToLinear(kLimiterMaxInputLevelDbFs).
const LIMITER_MAX_INPUT_LEVEL_LINEAR: f32 = 36766.300710566735;

fn limiter_gain(input_level: f32) -> f32 {
    if input_level <= LIMITER_X[0] {
        return 1.0;
    }
    if input_level >= LIMITER_MAX_INPUT_LEVEL_LINEAR {
        return 32768.0 / input_level;
    }
    // Index of the last x not above input_level (lower_bound - 1).
    let i = LIMITER_X.partition_point(|&x| x < input_level) - 1;
    LIMITER_M[i] * input_level + LIMITER_Q[i]
}

/// Limiter (limiter.cc + fixed_digital_level_estimator.cc).
struct Limiter {
    filter_state_level: f32,
    last_scaling_factor: f32,
    factors: Vec<f32>,
}

impl Limiter {
    const DECAY_FILTER_CONSTANT: f32 = 0.997_125_9;
    const ATTACK_FIRST_SUBFRAME_INTERPOLATION_POWER: i32 = 8;

    fn new() -> Self {
        Limiter {
            filter_state_level: 0.0,
            last_scaling_factor: 1.0,
            factors: vec![0.0; MAX_FRAME],
        }
    }

    fn level_envelope(&mut self, frame: &[f32]) -> [f32; SUB_FRAMES_IN_FRAME] {
        let sub = frame.len() / SUB_FRAMES_IN_FRAME;
        let mut envelope = [0f32; SUB_FRAMES_IN_FRAME];
        for (k, e) in envelope.iter_mut().enumerate() {
            for x in &frame[k * sub..(k + 1) * sub] {
                *e = e.max(x.abs());
            }
        }
        // Make the envelope increase happen one subframe earlier, so the
        // limiter starts reducing the gain before a peak arrives.
        for k in 0..SUB_FRAMES_IN_FRAME - 1 {
            if envelope[k] < envelope[k + 1] {
                envelope[k] = envelope[k + 1];
            }
        }
        // Instant attack, slow decay.
        for e in envelope.iter_mut() {
            if *e <= self.filter_state_level {
                *e = *e * (1.0 - Self::DECAY_FILTER_CONSTANT)
                    + self.filter_state_level * Self::DECAY_FILTER_CONSTANT;
            }
            self.filter_state_level = *e;
        }
        envelope
    }

    /// Envelope level of the last frame (LastAudioLevel).
    fn last_audio_level(&self) -> f32 {
        self.filter_state_level
    }

    fn process(&mut self, frame: &mut [f32]) {
        let n = frame.len();
        let sub = n / SUB_FRAMES_IN_FRAME;
        let envelope = self.level_envelope(frame);
        let mut scaling = [0f32; SUB_FRAMES_IN_FRAME + 1];
        scaling[0] = self.last_scaling_factor;
        for (s, e) in scaling[1..].iter_mut().zip(envelope.iter()) {
            *s = limiter_gain(*e);
        }
        let factors = &mut self.factors[..n];
        let is_attack = scaling[0] > scaling[1];
        if is_attack {
            let p = Self::ATTACK_FIRST_SUBFRAME_INTERPOLATION_POWER;
            for (i, f) in factors[..sub].iter_mut().enumerate() {
                let t = i as f32 / sub as f32;
                *f = (1.0 - t).powi(p) * (scaling[0] - scaling[1]) + scaling[1];
            }
        }
        for k in if is_attack { 1 } else { 0 }..SUB_FRAMES_IN_FRAME {
            let (start, end) = (scaling[k], scaling[k + 1]);
            let diff = (end - start) / sub as f32;
            for j in 0..sub {
                factors[k * sub + j] = start + diff * j as f32;
            }
        }
        for (x, f) in frame.iter_mut().zip(factors.iter()) {
            *x = (*x * f).clamp(MIN_FLOAT_S16, MAX_FLOAT_S16);
        }
        self.last_scaling_factor = scaling[SUB_FRAMES_IN_FRAME];
    }
}

/// What the controller did on the last block, for stats and tests.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct AgcState {
    pub gain_db: f32,
    pub speech_level_dbfs: f32,
    pub speech_level_confident: bool,
    pub noise_dbfs: f32,
    pub headroom_db: f32,
}

/// AGC2 adaptive digital + fixed gain + limiter for one stream of 10 ms
/// blocks of `samples` samples (`samples` a multiple of 20, up to
/// [`MAX_FRAME`]: every APM processing rate qualifies).
pub struct Agc {
    samples: usize,
    speech: SpeechLevelEstimator,
    saturation: SaturationProtector,
    noise: NoiseFloorEstimator,
    controller: AdaptiveDigitalGainController,
    fixed: GainApplier,
    limiter: Limiter,
    last: AgcState,
}

impl Agc {
    /// None when `samples` isn't a block size AGC2 handles.
    pub fn new(samples: usize) -> Option<Self> {
        if samples == 0 || samples > MAX_FRAME || !samples.is_multiple_of(SUB_FRAMES_IN_FRAME) {
            return None;
        }
        Some(Agc {
            samples,
            speech: SpeechLevelEstimator::new(),
            saturation: SaturationProtector::new(),
            noise: NoiseFloorEstimator::new(samples),
            controller: AdaptiveDigitalGainController::new(),
            fixed: GainApplier::new(1.0),
            limiter: Limiter::new(),
            last: AgcState::default(),
        })
    }

    pub fn samples(&self) -> usize {
        self.samples
    }

    pub fn state(&self) -> AgcState {
        self.last
    }

    /// Processes one block in place. `speech_probability` is the voice
    /// activity detector's output for this block (0..1); `fixed_gain` the
    /// linear gain applied after the adaptive one and before the limiter
    /// (the microphone volume slider). Blocks of another size are left alone.
    pub fn process(&mut self, frame: &mut [f32], speech_probability: f32, fixed_gain: f32) {
        if frame.len() != self.samples {
            return;
        }
        let speech_probability = if speech_probability.is_finite() {
            speech_probability.clamp(0.0, 1.0)
        } else {
            0.0
        };

        let mut peak = 0f32;
        let mut energy = 0f32;
        for x in frame.iter() {
            peak = peak.max(x.abs());
            energy += x * x;
        }
        let peak_dbfs = float_s16_to_dbfs(peak);
        let rms_dbfs = float_s16_to_dbfs((energy / self.samples as f32).sqrt());

        let noise_rms_dbfs = self.noise.analyze(frame);
        self.speech.update(rms_dbfs, speech_probability);
        let speech_level_dbfs = self.speech.level_dbfs;
        self.saturation
            .analyze(speech_probability, peak_dbfs, speech_level_dbfs);
        let headroom_db = self.saturation.headroom_db;
        let limiter_envelope_dbfs = float_s16_to_dbfs(self.limiter.last_audio_level());

        self.controller.process(
            &FrameInfo {
                speech_probability,
                speech_level_dbfs,
                speech_level_reliable: self.speech.is_confident,
                noise_rms_dbfs,
                headroom_db,
                limiter_envelope_dbfs,
            },
            frame,
        );

        let fixed_gain = if fixed_gain.is_finite() {
            fixed_gain.max(0.0)
        } else {
            1.0
        };
        self.fixed.current_gain_factor = fixed_gain;
        self.fixed.apply(frame);

        self.limiter.process(frame);

        self.last = AgcState {
            gain_db: self.controller.last_gain_db,
            speech_level_dbfs,
            speech_level_confident: self.speech.is_confident,
            noise_dbfs: noise_rms_dbfs,
            headroom_db,
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rms_dbfs(x: &[f32]) -> f32 {
        let e: f32 = x.iter().map(|v| v * v).sum();
        float_s16_to_dbfs((e / x.len() as f32).sqrt())
    }

    #[test]
    fn limiter_curve_matches_agc2_table_ends() {
        // Identity below the knee, unity gain at the first point.
        assert_eq!(limiter_gain(1000.0), 1.0);
        assert_eq!(limiter_gain(LIMITER_X[0]), 1.0);
        // Continuous across the first knee point (m*x+q ≈ 1 there).
        let g = limiter_gain(LIMITER_X[0] + 0.01);
        assert!((g - 1.0).abs() < 1e-3, "{g}");
        // Never lets the envelope through above full scale.
        for level in [32_768.0f32, 34_000.0, 36_000.0, 40_000.0, 100_000.0] {
            assert!(
                limiter_gain(level) * level <= 32_768.5,
                "{level}: {}",
                limiter_gain(level) * level
            );
        }
    }

    #[test]
    fn limiter_holds_a_hot_signal_under_full_scale() {
        let mut lim = Limiter::new();
        let mut max_out = 0f32;
        for block in 0..100 {
            let mut f: Vec<f32> = (0..480)
                .map(|i| {
                    60_000.0
                        * (2.0 * std::f32::consts::PI * 440.0 * (block * 480 + i) as f32 / 48_000.0)
                            .sin()
                })
                .collect();
            lim.process(&mut f);
            max_out = f.iter().fold(max_out, |m, x| m.max(x.abs()));
        }
        assert!(max_out <= 32_768.0, "{max_out}");
    }

    /// Syllable-like bursts: 200 ms of a -50 dBFS tone the VAD calls speech,
    /// 100 ms of a -80 dBFS noise bed it doesn't. (A steady tone alone would
    /// be the noise floor, which AGC2 rightly refuses to boost.)
    fn bursts(agc: &mut Agc, seconds: usize, mut each: impl FnMut(&Agc, bool)) {
        let tone = 32768.0 * 10f32.powf(-50.0 / 20.0) * std::f32::consts::SQRT_2;
        let bed = 32768.0 * 10f32.powf(-80.0 / 20.0) * 3f32.sqrt();
        let mut seed = 3u32;
        for block in 0..seconds * 100 {
            let talking = block % 30 < 20;
            let mut f: Vec<f32> = (0..480)
                .map(|i| {
                    seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    let noise = bed * ((seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0);
                    let t = (block * 480 + i) as f32 / 48_000.0;
                    let s = if talking {
                        tone * (2.0 * std::f32::consts::PI * 300.0 * t).sin()
                    } else {
                        0.0
                    };
                    s + noise
                })
                .collect();
            agc.process(&mut f, if talking { 1.0 } else { 0.0 }, 1.0);
            each(agc, talking);
        }
    }

    #[test]
    fn gain_moves_at_most_6_db_per_second_once_confident() {
        let mut agc = Agc::new(480).unwrap();
        let mut gains = vec![INITIAL_GAIN_DB];
        let mut bursts_seen = 0;
        let mut was_talking = false;
        bursts(&mut agc, 10, |a, talking| {
            gains.push(a.state().gain_db);
            if talking && !was_talking {
                bursts_seen += 1;
            }
            was_talking = talking;
        });
        // 0.06 dB per 10 ms, except one catch-up step of 12 x 0.06 when a
        // burst has been speech for 12 blocks in a row.
        let steps: Vec<f32> = gains.windows(2).map(|w| w[1] - w[0]).collect();
        let fast = steps.iter().filter(|d| **d > 0.06 + 1e-4).count();
        assert!(steps.iter().all(|d| *d <= 0.72 + 1e-4), "{steps:?}");
        assert!(
            fast <= bursts_seen,
            "{fast} fast steps for {bursts_seen} bursts"
        );
        // Target: -5 dBFS minus the 12 dB minimum headroom for a tone, from
        // -50 dBFS: 33 dB. After 10 s it's on its way.
        let last = *gains.last().unwrap();
        assert!(last > 25.0 && last <= 33.5, "{last}");
    }

    #[test]
    fn no_gain_increase_without_speech() {
        // Same quiet input, but the VAD says "no speech": the gain never rises
        // above where it started.
        let mut agc = Agc::new(480).unwrap();
        let amp = 32768.0 * 10f32.powf(-50.0 / 20.0) * std::f32::consts::SQRT_2;
        for block in 0..500 {
            let mut f: Vec<f32> = (0..480)
                .map(|i| {
                    amp * (2.0 * std::f32::consts::PI * 300.0 * (block * 480 + i) as f32 / 48_000.0)
                        .sin()
                })
                .collect();
            agc.process(&mut f, 0.1, 1.0);
            assert!(agc.state().gain_db <= INITIAL_GAIN_DB + 1e-4);
        }
    }

    #[test]
    fn noise_is_not_boosted_above_minus_50_dbfs() {
        // Steady noise at -60 dBFS RMS that the VAD calls speech (worst case):
        // the noise cap keeps the gain at no more than 10 dB.
        let mut agc = Agc::new(480).unwrap();
        let mut seed = 7u32;
        let amp = 32768.0 * 10f32.powf(-60.0 / 20.0) * 3f32.sqrt();
        let mut out_tail = Vec::new();
        for block in 0..1500 {
            let mut f: Vec<f32> = (0..480)
                .map(|_| {
                    seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    amp * ((seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0)
                })
                .collect();
            agc.process(&mut f, 1.0, 1.0);
            if block >= 1400 {
                out_tail.extend_from_slice(&f);
            }
        }
        let level = rms_dbfs(&out_tail);
        assert!(
            level <= -49.0,
            "noise came out at {level} dBFS, gain {}",
            agc.state().gain_db
        );
    }

    #[test]
    fn rejects_block_sizes_agc2_cannot_split() {
        assert!(Agc::new(441).is_none());
        assert!(Agc::new(0).is_none());
        assert!(Agc::new(2000).is_none());
        for n in [80, 160, 320, 480, 960] {
            assert!(Agc::new(n).is_some(), "{n}");
        }
    }
}
