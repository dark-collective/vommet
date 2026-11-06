//! Camera background blur for Vommet calls on Linux and Windows, where the
//! WebRTC library has no frame processing of its own. The flutter_webrtc fork
//! hands every camera frame (I420) to [`vommet_blur_process_fn`]'s function,
//! which finds the person with a segmentation model and blurs the rest in
//! place. Same approach and numbers as the Android and Apple versions.
//!
//! The C functions are exported from rust_lib_commet, which re-exports this
//! crate; the Dart side looks them up there.

mod segmenter;

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Instant;

pub use segmenter::{ModelError, Segmenter};

/// MediaPipe's selfie segmenter (Apache-2.0), converted by
/// tools/export_weights.py.
pub const MODEL: &[u8] = include_bytes!("../model/selfie_segmenter.bin");

/// How much the mask from one run carries into the next, so the edge
/// doesn't flicker.
const MASK_KEEP: f32 = 0.4;

pub struct Blur {
    state: Mutex<State>,
    too_slow: AtomicBool,
}

struct State {
    seg: Segmenter,
    radius: usize,
    slow_ms: f64,
    /// The smoothed mask, at model size.
    mask: Vec<f32>,
    have_mask: bool,
    frames: u64,
    avg_ms: f64,
    small: Vec<f32>,
    tmp: Vec<f32>,
}

impl Blur {
    pub fn new(radius: usize, slow_ms: u32) -> Result<Self, ModelError> {
        let seg = Segmenter::load(MODEL)?;
        let (mw, mh) = seg.input_size();
        Ok(Self {
            state: Mutex::new(State {
                seg,
                radius: radius.max(2),
                slow_ms: slow_ms as f64,
                mask: vec![0.0; mw * mh],
                have_mask: false,
                frames: 0,
                avg_ms: 0.0,
                small: Vec::new(),
                tmp: Vec::new(),
            }),
            too_slow: AtomicBool::new(false),
        })
    }

    /// Set once frames took too long on average (or something failed);
    /// frames then pass through untouched.
    pub fn too_slow(&self) -> bool {
        self.too_slow.load(Ordering::Relaxed)
    }

    /// Blurs the background of an I420 frame in place. The planes must hold
    /// `width` x `height` (luma) and the rounded-up half (chroma) at their
    /// strides.
    #[allow(clippy::too_many_arguments)]
    pub fn process(
        &self,
        y: &mut [u8],
        stride_y: usize,
        u: &mut [u8],
        stride_u: usize,
        v: &mut [u8],
        stride_v: usize,
        width: usize,
        height: usize,
    ) {
        if self.too_slow() || width == 0 || height == 0 {
            return;
        }
        let Ok(mut st) = self.state.lock() else {
            return;
        };
        let start = Instant::now();
        let (cw, ch) = (width.div_ceil(2), height.div_ceil(2));
        // The mask is refreshed every other frame; it moves little in 33 ms.
        if !st.have_mask || st.frames % 2 == 0 {
            st.segment(y, stride_y, u, stride_u, v, stride_v, width, height);
        }
        let luma_radius = (st.radius / 4).max(1);
        st.blend_plane(y, stride_y, width, height, 4, luma_radius);
        st.blend_plane(u, stride_u, cw, ch, 2, luma_radius);
        st.blend_plane(v, stride_v, cw, ch, 2, luma_radius);

        let ms = start.elapsed().as_secs_f64() * 1000.0;
        st.frames += 1;
        st.avg_ms = if st.frames == 1 {
            ms
        } else {
            st.avg_ms * 0.9 + ms * 0.1
        };
        if st.frames > 30 && st.avg_ms > st.slow_ms {
            log::warn!(
                "background blur too slow ({:.0} ms a frame), turning it off",
                st.avg_ms
            );
            self.too_slow.store(true, Ordering::Relaxed);
        }
    }
}

impl State {
    #[allow(clippy::too_many_arguments)]
    fn segment(
        &mut self,
        y: &[u8],
        stride_y: usize,
        u: &[u8],
        stride_u: usize,
        v: &[u8],
        stride_v: usize,
        w: usize,
        h: usize,
    ) {
        let (mw, mh) = self.seg.input_size();
        let input = self.seg.input_mut();
        for my in 0..mh {
            let sy = (((my as f32 + 0.5) / mh as f32 * h as f32) as usize).min(h - 1);
            for mx in 0..mw {
                let sx = (((mx as f32 + 0.5) / mw as f32 * w as f32) as usize).min(w - 1);
                let yv = y[sy * stride_y + sx] as f32;
                let uv = u[(sy >> 1) * stride_u + (sx >> 1)] as f32 - 128.0;
                let vv = v[(sy >> 1) * stride_v + (sx >> 1)] as f32 - 128.0;
                let px = &mut input[(my * mw + mx) * 3..][..3];
                px[0] = ((yv + 1.402 * vv) / 255.0).clamp(0.0, 1.0);
                px[1] = ((yv - 0.344 * uv - 0.714 * vv) / 255.0).clamp(0.0, 1.0);
                px[2] = ((yv + 1.772 * uv) / 255.0).clamp(0.0, 1.0);
            }
        }
        let have = self.have_mask;
        let out = self.seg.run();
        for (m, &p) in self.mask.iter_mut().zip(out) {
            *m = if have {
                *m * MASK_KEEP + p * (1.0 - MASK_KEEP)
            } else {
                p
            };
        }
        self.have_mask = true;
    }

    /// Blurs one plane at 1/`factor` size and mixes it back outside the person.
    fn blend_plane(
        &mut self,
        plane: &mut [u8],
        stride: usize,
        w: usize,
        h: usize,
        factor: usize,
        radius: usize,
    ) {
        let (sw, sh) = ((w / factor).max(1), (h / factor).max(1));
        self.small.clear();
        self.small.resize(sw * sh, 0.0);
        self.tmp.clear();
        self.tmp.resize(sw * sh, 0.0);
        for sy in 0..sh {
            for sx in 0..sw {
                let (mut sum, mut n) = (0u32, 0u32);
                for yy in (sy * factor..(sy + 1) * factor).take_while(|&yy| yy < h) {
                    for xx in (sx * factor..(sx + 1) * factor).take_while(|&xx| xx < w) {
                        sum += plane[yy * stride + xx] as u32;
                        n += 1;
                    }
                }
                self.small[sy * sw + sx] = if n == 0 { 0.0 } else { sum as f32 / n as f32 };
            }
        }
        for _ in 0..2 {
            box_blur(&self.small, &mut self.tmp, sw, sh, radius, true);
            box_blur(&self.tmp, &mut self.small, sw, sh, radius, false);
        }

        let (mw, mh) = self.seg.input_size();
        let (fx, fy) = (sw as f32 / w as f32, sh as f32 / h as f32);
        let (mfx, mfy) = (mw as f32 / w as f32, mh as f32 / h as f32);
        for row in 0..h {
            let by = (row as f32 + 0.5) * fy - 0.5;
            let my = (row as f32 + 0.5) * mfy - 0.5;
            let line = &mut plane[row * stride..][..w];
            for (col, px) in line.iter_mut().enumerate() {
                let m = sample(&self.mask, mw, mh, (col as f32 + 0.5) * mfx - 0.5, my);
                if m >= 0.98 {
                    continue;
                }
                let blurred = sample(&self.small, sw, sh, (col as f32 + 0.5) * fx - 0.5, by);
                let v = *px as f32 * m + blurred * (1.0 - m) + 0.5;
                *px = v.clamp(0.0, 255.0) as u8;
            }
        }
    }
}

fn box_blur(src: &[f32], dst: &mut [f32], w: usize, h: usize, r: usize, horizontal: bool) {
    let (len, lines) = if horizontal { (w, h) } else { (h, w) };
    let at = |line: usize, i: usize| {
        if horizontal {
            src[line * w + i]
        } else {
            src[i * w + line]
        }
    };
    let last = len - 1;
    let r = r as isize;
    let clamp = |i: isize| i.clamp(0, last as isize) as usize;
    let norm = 1.0 / (2 * r + 1) as f32;
    for line in 0..lines {
        let mut sum: f32 = (-r..=r).map(|k| at(line, clamp(k))).sum();
        for i in 0..len {
            let idx = if horizontal { line * w + i } else { i * w + line };
            dst[idx] = sum * norm;
            let ii = i as isize;
            sum += at(line, clamp(ii + r + 1)) - at(line, clamp(ii - r));
        }
    }
}

fn sample(a: &[f32], w: usize, h: usize, x: f32, y: f32) -> f32 {
    let (x, y) = (x.max(0.0), y.max(0.0));
    let (x0, y0) = ((x as usize).min(w - 1), (y as usize).min(h - 1));
    let (x1, y1) = ((x0 + 1).min(w - 1), (y0 + 1).min(h - 1));
    let (ax, ay) = ((x - x0 as f32).min(1.0), (y - y0 as f32).min(1.0));
    let top = a[y0 * w + x0] * (1.0 - ax) + a[y0 * w + x1] * ax;
    let bottom = a[y1 * w + x0] * (1.0 - ax) + a[y1 * w + x1] * ax;
    top * (1.0 - ay) + bottom * ay
}

/// A new blur (blur radius in pixels at full size, and the average frame
/// time in ms above which it gives up), or null if the model won't load.
#[no_mangle]
pub extern "C" fn vommet_blur_create(radius: u32, slow_frame_ms: u32) -> *mut Blur {
    match catch_unwind(|| Blur::new(radius as usize, slow_frame_ms)) {
        Ok(Ok(blur)) => Box::into_raw(Box::new(blur)),
        Ok(Err(e)) => {
            log::warn!("background blur unavailable: {e}");
            std::ptr::null_mut()
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Frees a blur from [`vommet_blur_create`]. Nothing may still be calling
/// the process function with it.
///
/// # Safety
/// `blur` is null or came from `vommet_blur_create` and isn't used again.
#[no_mangle]
pub unsafe extern "C" fn vommet_blur_destroy(blur: *mut Blur) {
    if !blur.is_null() {
        drop(Box::from_raw(blur));
    }
}

/// Whether the blur gave up (frames too slow, or it failed).
///
/// # Safety
/// `blur` is null or a live blur from `vommet_blur_create`.
#[no_mangle]
pub unsafe extern "C" fn vommet_blur_too_slow(blur: *const Blur) -> bool {
    blur.as_ref().is_some_and(Blur::too_slow)
}

/// The address of the frame function to hand to the flutter_webrtc fork's
/// vommetCreateProcessedVideoTrack, with a blur as its user data.
#[no_mangle]
pub extern "C" fn vommet_blur_process_fn() -> usize {
    process_frame as usize
}

#[allow(clippy::too_many_arguments)]
extern "C" fn process_frame(
    user_data: *mut c_void,
    y: *mut u8,
    stride_y: i32,
    u: *mut u8,
    stride_u: i32,
    v: *mut u8,
    stride_v: i32,
    width: i32,
    height: i32,
) {
    // SAFETY: the fork passes the blur it was given and a frame it owns,
    // with planes of the sizes its strides and dimensions describe.
    let Some(blur) = (unsafe { (user_data as *const Blur).as_ref() }) else {
        return;
    };
    if y.is_null() || u.is_null() || v.is_null() || width <= 0 || height <= 0 {
        return;
    }
    let (w, h) = (width as usize, height as usize);
    let (cw, ch) = (w.div_ceil(2), h.div_ceil(2));
    let (sy, su, sv) = (stride_y as usize, stride_u as usize, stride_v as usize);
    if sy < w || su < cw || sv < cw {
        return;
    }
    let (y, u, v) = unsafe {
        (
            std::slice::from_raw_parts_mut(y, sy * (h - 1) + w),
            std::slice::from_raw_parts_mut(u, su * (ch - 1) + cw),
            std::slice::from_raw_parts_mut(v, sv * (ch - 1) + cw),
        )
    };
    let result = catch_unwind(AssertUnwindSafe(|| {
        blur.process(y, sy, u, su, v, sv, w, h);
    }));
    if result.is_err() {
        log::warn!("background blur failed, turning it off");
        blur.too_slow.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(w: usize, h: usize) -> (Vec<u8>, Vec<u8>, Vec<u8>) {
        let (cw, ch) = (w.div_ceil(2), h.div_ceil(2));
        let y = (0..w * h).map(|i| ((i % w) * 255 / w) as u8).collect();
        (y, vec![100; cw * ch], vec![150; cw * ch])
    }

    #[test]
    fn blurs_odd_sizes_without_panicking() {
        let blur = Blur::new(16, 1_000_000).unwrap();
        for (w, h) in [(640, 480), (321, 241), (1, 1), (2, 3)] {
            let (mut y, mut u, mut v) = frame(w, h);
            let (cw, _) = (w.div_ceil(2), h.div_ceil(2));
            for _ in 0..3 {
                blur.process(&mut y, w, &mut u, cw, &mut v, cw, w, h);
            }
        }
        assert!(!blur.too_slow());
    }

    #[test]
    fn background_gets_blurred() {
        // Nothing in this picture is a person, so it all blurs: a sharp
        // gradient comes back smoother.
        let blur = Blur::new(16, 1_000_000).unwrap();
        let (w, h) = (320, 240);
        let mut y: Vec<u8> = (0..w * h)
            .map(|i| if (i % w / 8) % 2 == 0 { 0 } else { 255 })
            .collect();
        let (mut u, mut v) = (vec![128; 160 * 120], vec![128; 160 * 120]);
        let start = Instant::now();
        blur.process(&mut y, w, &mut u, 160, &mut v, 160, w, h);
        eprintln!("one 320x240 frame: {:?}", start.elapsed());
        let row = &y[120 * w..121 * w];
        let jumps = row.windows(2).map(|p| (p[0] as i32 - p[1] as i32).abs()).max().unwrap();
        assert!(jumps < 64, "still sharp: {jumps}");
    }

    #[test]
    fn c_abi_round_trip() {
        let blur = vommet_blur_create(16, 1_000_000);
        assert!(!blur.is_null());
        let f: extern "C" fn(*mut c_void, *mut u8, i32, *mut u8, i32, *mut u8, i32, i32, i32) =
            unsafe { std::mem::transmute(vommet_blur_process_fn()) };
        let (mut y, mut u, mut v) = frame(64, 48);
        f(blur.cast(), y.as_mut_ptr(), 64, u.as_mut_ptr(), 32, v.as_mut_ptr(), 32, 64, 48);
        // A stride smaller than the width is refused, not read past.
        f(blur.cast(), y.as_mut_ptr(), 10, u.as_mut_ptr(), 32, v.as_mut_ptr(), 32, 64, 48);
        unsafe {
            assert!(!vommet_blur_too_slow(blur));
            vommet_blur_destroy(blur);
            assert!(!vommet_blur_too_slow(std::ptr::null()));
        }
    }
}
