//! Rational-ratio resampling, one 10 ms block at a time, so the engines (48 kHz
//! only) also run when libwebrtc processes the microphone at another rate. On
//! Windows that is the capture device's own rate, often 16 kHz for a headset
//! or Bluetooth microphone; on Android it depends on the device.
//!
//! A polyphase windowed-sinc filter: upsample by `up`, low-pass, keep every
//! `down`-th sample, computing only the samples that are kept. Ten
//! milliseconds at any whole-hundred rate is a whole number of samples on both
//! sides, so every block maps to exactly one block and no fractional position
//! carries over. The filter delays the audio by about 1 ms each way.

/// Filter length in samples at the higher of the two rates, per unit of the
/// larger ratio term; about 80 dB of stopband with the Kaiser window below.
const TAPS_PER_SIDE: usize = 32;
const KAISER_BETA: f64 = 8.0;
/// Cutoff (the filter's half-amplitude point) as a share of the lower rate's
/// Nyquist frequency.
const CUTOFF: f64 = 0.9;

pub struct Resampler {
    up: usize,
    down: usize,
    /// Input samples each output sample looks at.
    taps: usize,
    /// Phase-major: `coeffs[phase * taps + j]` weighs the input `j` samples
    /// before the current one.
    coeffs: Vec<f32>,
    /// The last `taps - 1` input samples, then the current block.
    buf: Vec<f32>,
    block_in: usize,
    block_out: usize,
}

fn gcd(a: usize, b: usize) -> usize {
    if b == 0 {
        a
    } else {
        gcd(b, a % b)
    }
}

/// Zeroth-order modified Bessel function of the first kind, for the Kaiser
/// window.
fn bessel_i0(x: f64) -> f64 {
    let (mut sum, mut term) = (1.0, 1.0);
    let q = x * x / 4.0;
    for k in 1..50 {
        term *= q / (k * k) as f64;
        sum += term;
        if term < sum * 1e-12 {
            break;
        }
    }
    sum
}

impl Resampler {
    /// A resampler for 10 ms blocks from `from` Hz to `to` Hz. Both must be
    /// positive multiples of 100.
    pub fn new(from: usize, to: usize) -> Self {
        let g = gcd(from, to);
        let (up, down) = (to / g, from / g);
        let len = TAPS_PER_SIDE * up.max(down);
        let len = len.div_ceil(up) * up;
        let taps = len / up;

        // Cutoff in cycles per sample at the upsampled rate (from * up).
        let fc = 0.5 * CUTOFF * from.min(to) as f64 / (from * up) as f64;
        let mid = (len - 1) as f64 / 2.0;
        let i0_beta = bessel_i0(KAISER_BETA);
        let mut h: Vec<f64> = (0..len)
            .map(|n| {
                let t = n as f64 - mid;
                let x = 2.0 * fc * t;
                let sinc = if x == 0.0 {
                    1.0
                } else {
                    (std::f64::consts::PI * x).sin() / (std::f64::consts::PI * x)
                };
                let r = t / mid.max(1.0);
                let w = bessel_i0(KAISER_BETA * (1.0 - r * r).max(0.0).sqrt()) / i0_beta;
                sinc * w
            })
            .collect();
        // Unity gain at DC: each output sums one phase, i.e. 1/up of the taps.
        let sum: f64 = h.iter().sum();
        for c in &mut h {
            *c *= up as f64 / sum;
        }

        let mut coeffs = vec![0f32; up * taps];
        for phase in 0..up {
            for j in 0..taps {
                coeffs[phase * taps + j] = h[phase + j * up] as f32;
            }
        }
        let block_in = from / 100;
        Resampler {
            up,
            down,
            taps,
            coeffs,
            buf: vec![0.0; taps - 1 + block_in],
            block_in,
            block_out: to / 100,
        }
    }

    /// Resamples one 10 ms block. `input` must hold `from / 100` samples and
    /// `output` `to / 100`.
    pub fn process(&mut self, input: &[f32], output: &mut [f32]) {
        debug_assert_eq!(input.len(), self.block_in);
        debug_assert_eq!(output.len(), self.block_out);
        let hist = self.taps - 1;
        self.buf[hist..].copy_from_slice(input);
        for (k, y) in output.iter_mut().enumerate() {
            let p = k * self.down;
            let (i, phase) = (p / self.up, p % self.up);
            // The current input sample sits at buf[hist + i]; walk backwards.
            let newest = hist + i;
            let c = &self.coeffs[phase * self.taps..(phase + 1) * self.taps];
            let mut acc = 0f32;
            for (j, w) in c.iter().enumerate() {
                acc += w * self.buf[newest - j];
            }
            *y = acc;
        }
        self.buf.copy_within(self.block_in.., 0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(rate: usize, hz: f64, n: usize, start: usize) -> Vec<f32> {
        (start..start + n)
            .map(|i| {
                (1000.0 * (2.0 * std::f64::consts::PI * hz * i as f64 / rate as f64).sin()) as f32
            })
            .collect()
    }

    fn rms(x: &[f32]) -> f64 {
        (x.iter().map(|s| (*s as f64).powi(2)).sum::<f64>() / x.len() as f64).sqrt()
    }

    /// Least-squares fit of a `hz` sinusoid over whole periods; returns its
    /// amplitude and the RMS of what the fit leaves (distortion, noise,
    /// aliases).
    fn fit(x: &[f32], rate: usize, hz: f64) -> (f64, f64) {
        let (mut a, mut b) = (0f64, 0f64);
        let w = |i: usize| 2.0 * std::f64::consts::PI * hz * i as f64 / rate as f64;
        for (i, s) in x.iter().enumerate() {
            a += *s as f64 * w(i).sin();
            b += *s as f64 * w(i).cos();
        }
        let (a, b) = (2.0 * a / x.len() as f64, 2.0 * b / x.len() as f64);
        let err: Vec<f32> = x
            .iter()
            .enumerate()
            .map(|(i, s)| (*s as f64 - a * w(i).sin() - b * w(i).cos()) as f32)
            .collect();
        ((a * a + b * b).sqrt(), rms(&err))
    }

    /// A tone survives the trip to 48 kHz and back at its level and without
    /// picking up distortion.
    #[test]
    fn round_trip_keeps_a_tone() {
        for rate in [8_000, 16_000, 24_000, 32_000, 44_100] {
            let mut up = Resampler::new(rate, 48_000);
            let mut down = Resampler::new(48_000, rate);
            let (n, mut out) = (rate / 100, Vec::new());
            let input = sine(rate, 1000.0, n * 50, 0);
            let mut b48 = [0f32; 480];
            let mut back = vec![0f32; n];
            for block in input.chunks(n) {
                up.process(block, &mut b48);
                down.process(&b48, &mut back);
                out.extend_from_slice(&back);
            }
            // The last 400 ms: 400 whole periods of 1 kHz, past the start-up.
            let (amp, residual) = fit(&out[out.len() - n * 40..], rate, 1000.0);
            assert!((amp / 1000.0 - 1.0).abs() < 0.02, "{rate}: amplitude {amp}");
            assert!(residual < 1000.0 * 0.01, "{rate}: residual {residual}");
        }
    }

    /// Upsampling 16 kHz leaves little energy above the old Nyquist (the
    /// images an unfiltered upsampler would make).
    #[test]
    fn upsampling_suppresses_images() {
        let mut up = Resampler::new(16_000, 48_000);
        let input = sine(16_000, 6000.0, 160 * 40, 0);
        let mut out = Vec::new();
        let mut b48 = [0f32; 480];
        for block in input.chunks(160) {
            up.process(block, &mut b48);
            out.extend_from_slice(&b48);
        }
        // The 6 kHz tone's first image is at 10 kHz; measure it with a
        // single-bin DFT over the second half.
        let tail = &out[out.len() / 2..];
        let bin = |hz: f64| {
            let (mut re, mut im) = (0f64, 0f64);
            for (i, s) in tail.iter().enumerate() {
                let ph = 2.0 * std::f64::consts::PI * hz * i as f64 / 48_000.0;
                re += *s as f64 * ph.cos();
                im += *s as f64 * ph.sin();
            }
            (re * re + im * im).sqrt()
        };
        let ratio = bin(10_000.0) / bin(6_000.0);
        assert!(ratio < 0.01, "image at {ratio}");
    }
}
