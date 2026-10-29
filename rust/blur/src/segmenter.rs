//! Runs the person segmentation model (MediaPipe's selfie segmenter,
//! Apache-2.0, the one the web and mobile apps use) without an inference
//! runtime: tools/export_weights.py turns the .tflite into a small graph of
//! the eleven kinds of layer it uses, and this file evaluates it in plain Rust.
//! The math mirrors TFLite's reference kernels (SAME padding, half-pixel
//! bilinear resize).

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ModelError {
    #[error("not a segmentation model")]
    BadMagic,
    #[error("unsupported model version {0}")]
    Version(u32),
    #[error("model truncated")]
    Truncated,
    #[error("bad model: {0}")]
    Invalid(&'static str),
}

const CONV: u32 = 1;
const DWCONV: u32 = 2;
const HSWISH: u32 = 3;
const RELU: u32 = 4;
const SIGMOID: u32 = 5;
const GAP: u32 = 6;
const MUL_C: u32 = 7;
const ADD: u32 = 8;
const RESIZE2X: u32 = 9;
const TCONV2X: u32 = 10;

#[derive(Clone, Copy)]
struct Shape {
    h: usize,
    w: usize,
    c: usize,
}

impl Shape {
    fn len(&self) -> usize {
        self.h * self.w * self.c
    }
}

enum Op {
    /// Weights as [ky][kx][cin][cout], so the inner loop runs over outputs.
    Conv {
        i: usize,
        o: usize,
        k: usize,
        stride: usize,
        same: bool,
        w: Vec<f32>,
        b: Vec<f32>,
    },
    /// Weights as [ky][kx][c]; always SAME padding.
    DwConv {
        i: usize,
        o: usize,
        k: usize,
        stride: usize,
        w: Vec<f32>,
        b: Vec<f32>,
    },
    HardSwish(usize, usize),
    Relu(usize, usize),
    Sigmoid(usize, usize),
    GlobalAvgPool(usize, usize),
    /// a * b, b being 1x1xC (squeeze-excite).
    MulChannels(usize, usize, usize),
    Add(usize, usize, usize),
    Resize2x(usize, usize),
    /// 2x2 stride 2 transposed conv; weights as [ky][kx][cin][cout].
    TConv2x {
        i: usize,
        o: usize,
        w: Vec<f32>,
        b: Vec<f32>,
    },
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    fn u32(&mut self) -> Result<u32, ModelError> {
        let b = self
            .data
            .get(self.pos..self.pos + 4)
            .ok_or(ModelError::Truncated)?;
        self.pos += 4;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn usize(&mut self) -> Result<usize, ModelError> {
        Ok(self.u32()? as usize)
    }

    fn f16s(&mut self) -> Result<Vec<f32>, ModelError> {
        let n = self.usize()?;
        let b = self
            .data
            .get(self.pos..self.pos + 2 * n)
            .ok_or(ModelError::Truncated)?;
        self.pos += 2 * n;
        Ok(b.chunks_exact(2)
            .map(|c| f16_to_f32(u16::from_le_bytes([c[0], c[1]])))
            .collect())
    }
}

fn f16_to_f32(h: u16) -> f32 {
    let sign = ((h >> 15) as u32) << 31;
    let exp = ((h >> 10) & 0x1f) as u32;
    let frac = (h & 0x3ff) as u32;
    let bits = match exp {
        0 if frac == 0 => sign,
        0 => {
            // subnormal: normalize
            let mut e = 127 - 15 + 1;
            let mut f = frac;
            while f & 0x400 == 0 {
                f <<= 1;
                e -= 1;
            }
            sign | (e << 23) | ((f & 0x3ff) << 13)
        }
        0x1f => sign | 0x7f80_0000 | (frac << 13),
        _ => sign | ((exp + 127 - 15) << 23) | (frac << 13),
    };
    f32::from_bits(bits)
}

/// [cout][ky][kx][cin] -> [ky][kx][cin][cout]
fn to_out_last(w: &[f32], cout: usize, k: usize, cin: usize) -> Vec<f32> {
    let mut t = vec![0.0; w.len()];
    for co in 0..cout {
        for ky in 0..k {
            for kx in 0..k {
                for ci in 0..cin {
                    t[((ky * k + kx) * cin + ci) * cout + co] = w[((co * k + ky) * k + kx) * cin + ci];
                }
            }
        }
    }
    t
}

/// (output size, padding before) of TF's SAME padding.
fn same_pad(n: usize, k: usize, s: usize) -> (usize, usize) {
    let out = n.div_ceil(s);
    let total = ((out - 1) * s + k).saturating_sub(n);
    (out, total / 2)
}

pub struct Segmenter {
    shapes: Vec<Shape>,
    ops: Vec<Op>,
    tensors: Vec<Vec<f32>>,
    output: usize,
}

impl Segmenter {
    pub fn load(data: &[u8]) -> Result<Self, ModelError> {
        if data.get(..4) != Some(b"VSEG".as_slice()) {
            return Err(ModelError::BadMagic);
        }
        let mut r = Reader { data, pos: 4 };
        let version = r.u32()?;
        if version != 1 {
            return Err(ModelError::Version(version));
        }
        let nt = r.usize()?;
        let no = r.usize()?;
        if nt == 0 || no == 0 || nt > 10_000 || no > 10_000 {
            return Err(ModelError::Invalid("counts"));
        }
        let mut shapes = Vec::with_capacity(nt);
        for _ in 0..nt {
            let s = Shape {
                h: r.usize()?,
                w: r.usize()?,
                c: r.usize()?,
            };
            if s.len() == 0 || s.len() > 1 << 24 {
                return Err(ModelError::Invalid("tensor size"));
            }
            shapes.push(s);
        }
        let t = |i: u32| -> Result<usize, ModelError> {
            let i = i as usize;
            if i < nt {
                Ok(i)
            } else {
                Err(ModelError::Invalid("tensor index"))
            }
        };
        let mut ops = Vec::with_capacity(no);
        for _ in 0..no {
            let kind = r.u32()?;
            let op = match kind {
                CONV => {
                    let (i, o) = (t(r.u32()?)?, t(r.u32()?)?);
                    let (k, cin, cout, stride, same) =
                        (r.usize()?, r.usize()?, r.usize()?, r.usize()?, r.u32()? != 0);
                    let w = r.f16s()?;
                    let b = r.f16s()?;
                    if k == 0
                        || stride == 0
                        || w.len() != cout * k * k * cin
                        || b.len() != cout
                        || shapes[i].c != cin
                        || shapes[o].c != cout
                    {
                        return Err(ModelError::Invalid("conv"));
                    }
                    Op::Conv {
                        i,
                        o,
                        k,
                        stride,
                        same,
                        w: to_out_last(&w, cout, k, cin),
                        b,
                    }
                }
                DWCONV => {
                    let (i, o) = (t(r.u32()?)?, t(r.u32()?)?);
                    let (k, c, stride) = (r.usize()?, r.usize()?, r.usize()?);
                    let w = r.f16s()?;
                    let b = r.f16s()?;
                    if k == 0
                        || stride == 0
                        || w.len() != k * k * c
                        || b.len() != c
                        || shapes[i].c != c
                        || shapes[o].c != c
                    {
                        return Err(ModelError::Invalid("depthwise conv"));
                    }
                    Op::DwConv {
                        i,
                        o,
                        k,
                        stride,
                        w,
                        b,
                    }
                }
                HSWISH | RELU | SIGMOID | GAP | RESIZE2X => {
                    let (i, o) = (t(r.u32()?)?, t(r.u32()?)?);
                    let (si, so) = (shapes[i], shapes[o]);
                    let ok = match kind {
                        GAP => so.h == 1 && so.w == 1 && so.c == si.c,
                        RESIZE2X => so.h == 2 * si.h && so.w == 2 * si.w && so.c == si.c,
                        _ => so.len() == si.len(),
                    };
                    if !ok {
                        return Err(ModelError::Invalid("shapes"));
                    }
                    match kind {
                        HSWISH => Op::HardSwish(i, o),
                        RELU => Op::Relu(i, o),
                        SIGMOID => Op::Sigmoid(i, o),
                        GAP => Op::GlobalAvgPool(i, o),
                        _ => Op::Resize2x(i, o),
                    }
                }
                MUL_C | ADD => {
                    let (a, b, o) = (t(r.u32()?)?, t(r.u32()?)?, t(r.u32()?)?);
                    let (sa, sb, so) = (shapes[a], shapes[b], shapes[o]);
                    if kind == MUL_C {
                        if sb.h != 1 || sb.w != 1 || sb.c != sa.c || so.len() != sa.len() || b == o {
                            return Err(ModelError::Invalid("mul"));
                        }
                        Op::MulChannels(a, b, o)
                    } else {
                        if sb.len() != sa.len() || so.len() != sa.len() || b == o {
                            return Err(ModelError::Invalid("add"));
                        }
                        Op::Add(a, b, o)
                    }
                }
                TCONV2X => {
                    let (i, o) = (t(r.u32()?)?, t(r.u32()?)?);
                    let (cin, cout) = (r.usize()?, r.usize()?);
                    let w = r.f16s()?;
                    let b = r.f16s()?;
                    let (si, so) = (shapes[i], shapes[o]);
                    if w.len() != cout * 4 * cin
                        || b.len() != cout
                        || si.c != cin
                        || so.c != cout
                        || so.h != 2 * si.h
                        || so.w != 2 * si.w
                    {
                        return Err(ModelError::Invalid("transposed conv"));
                    }
                    Op::TConv2x {
                        i,
                        o,
                        w: to_out_last(&w, cout, 2, cin),
                        b,
                    }
                }
                _ => return Err(ModelError::Invalid("op kind")),
            };
            ops.push(op);
        }
        if r.pos != data.len() {
            return Err(ModelError::Invalid("trailing data"));
        }
        // Every op reads earlier tensors and writes a later one.
        let mut written = vec![false; nt];
        written[0] = true;
        for op in &ops {
            let (ins, o): (&[usize], usize) = match op {
                Op::Conv { i, o, .. } | Op::DwConv { i, o, .. } | Op::TConv2x { i, o, .. } => {
                    (std::slice::from_ref(i), *o)
                }
                Op::HardSwish(i, o)
                | Op::Relu(i, o)
                | Op::Sigmoid(i, o)
                | Op::GlobalAvgPool(i, o)
                | Op::Resize2x(i, o) => (std::slice::from_ref(i), *o),
                Op::MulChannels(a, b, o) | Op::Add(a, b, o) => {
                    if !written[*a] || !written[*b] || written[*o] {
                        return Err(ModelError::Invalid("graph order"));
                    }
                    written[*o] = true;
                    continue;
                }
            };
            if ins.iter().any(|&i| !written[i]) || written[o] {
                return Err(ModelError::Invalid("graph order"));
            }
            written[o] = true;
        }
        let output = match ops.last() {
            Some(
                Op::Conv { o, .. }
                | Op::DwConv { o, .. }
                | Op::TConv2x { o, .. }
                | Op::HardSwish(_, o)
                | Op::Relu(_, o)
                | Op::Sigmoid(_, o)
                | Op::GlobalAvgPool(_, o)
                | Op::Resize2x(_, o)
                | Op::MulChannels(_, _, o)
                | Op::Add(_, _, o),
            ) => *o,
            None => unreachable!(),
        };
        if shapes[0].c != 3 || shapes[output].c != 1 {
            return Err(ModelError::Invalid("input or output channels"));
        }
        let tensors = shapes.iter().map(|s| vec![0.0; s.len()]).collect();
        Ok(Self {
            shapes,
            ops,
            tensors,
            output,
        })
    }

    /// (width, height) the model sees.
    pub fn input_size(&self) -> (usize, usize) {
        (self.shapes[0].w, self.shapes[0].h)
    }

    /// The input, HWC RGB in 0..1; fill it, then call [`run`](Self::run).
    pub fn input_mut(&mut self) -> &mut [f32] {
        &mut self.tensors[0]
    }

    /// Runs the model; returns the person probability per pixel (input size).
    pub fn run(&mut self) -> &[f32] {
        for n in 0..self.ops.len() {
            let o = match &self.ops[n] {
                Op::Conv { o, .. }
                | Op::DwConv { o, .. }
                | Op::TConv2x { o, .. }
                | Op::HardSwish(_, o)
                | Op::Relu(_, o)
                | Op::Sigmoid(_, o)
                | Op::GlobalAvgPool(_, o)
                | Op::Resize2x(_, o)
                | Op::MulChannels(_, _, o)
                | Op::Add(_, _, o) => *o,
            };
            // Take the output out so the inputs can be borrowed alongside it;
            // load() checked no op reads its own output.
            let mut out = std::mem::take(&mut self.tensors[o]);
            let so = self.shapes[o];
            let ts = &self.tensors;
            let sh = &self.shapes;
            match &self.ops[n] {
                Op::Conv {
                    i,
                    k,
                    stride,
                    same,
                    w,
                    b,
                    ..
                } => conv(&ts[*i], sh[*i], &mut out, so, *k, *stride, *same, w, b),
                Op::DwConv {
                    i, k, stride, w, b, ..
                } => dwconv(&ts[*i], sh[*i], &mut out, so, *k, *stride, w, b),
                Op::TConv2x { i, w, b, .. } => tconv2x(&ts[*i], sh[*i], &mut out, so, w, b),
                Op::HardSwish(i, _) => {
                    for (d, &x) in out.iter_mut().zip(&ts[*i]) {
                        *d = x * (x + 3.0).clamp(0.0, 6.0) * (1.0 / 6.0);
                    }
                }
                Op::Relu(i, _) => {
                    for (d, &x) in out.iter_mut().zip(&ts[*i]) {
                        *d = x.max(0.0);
                    }
                }
                Op::Sigmoid(i, _) => {
                    for (d, &x) in out.iter_mut().zip(&ts[*i]) {
                        *d = 1.0 / (1.0 + (-x).exp());
                    }
                }
                Op::GlobalAvgPool(i, _) => {
                    let c = so.c;
                    out.iter_mut().for_each(|d| *d = 0.0);
                    for px in ts[*i].chunks_exact(c) {
                        for (d, &x) in out.iter_mut().zip(px) {
                            *d += x;
                        }
                    }
                    let n = (sh[*i].h * sh[*i].w) as f32;
                    out.iter_mut().for_each(|d| *d /= n);
                }
                Op::MulChannels(a, b, _) => {
                    let s = &ts[*b];
                    for (d, px) in out.chunks_exact_mut(so.c).zip(ts[*a].chunks_exact(so.c)) {
                        for ((d, &x), &m) in d.iter_mut().zip(px).zip(s) {
                            *d = x * m;
                        }
                    }
                }
                Op::Add(a, b, _) => {
                    for ((d, &x), &y) in out.iter_mut().zip(&ts[*a]).zip(&ts[*b]) {
                        *d = x + y;
                    }
                }
                Op::Resize2x(i, _) => resize2x(&ts[*i], sh[*i], &mut out),
            }
            self.tensors[o] = out;
        }
        &self.tensors[self.output]
    }
}

#[allow(clippy::too_many_arguments)]
fn conv(
    a: &[f32],
    si: Shape,
    out: &mut [f32],
    so: Shape,
    k: usize,
    s: usize,
    same: bool,
    w: &[f32],
    b: &[f32],
) {
    let (cin, cout) = (si.c, so.c);
    let (pt, pl) = if same && k > 1 {
        (same_pad(si.h, k, s).1, same_pad(si.w, k, s).1)
    } else {
        (0, 0)
    };
    for oy in 0..so.h {
        for ox in 0..so.w {
            let d = &mut out[(oy * so.w + ox) * cout..][..cout];
            d.copy_from_slice(b);
            for ky in 0..k {
                let iy = (oy * s + ky) as isize - pt as isize;
                if iy < 0 || iy >= si.h as isize {
                    continue;
                }
                for kx in 0..k {
                    let ix = (ox * s + kx) as isize - pl as isize;
                    if ix < 0 || ix >= si.w as isize {
                        continue;
                    }
                    let px = &a[(iy as usize * si.w + ix as usize) * cin..][..cin];
                    let wk = &w[(ky * k + kx) * cin * cout..][..cin * cout];
                    for (&x, wr) in px.iter().zip(wk.chunks_exact(cout)) {
                        for (d, &wv) in d.iter_mut().zip(wr) {
                            *d += x * wv;
                        }
                    }
                }
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn dwconv(a: &[f32], si: Shape, out: &mut [f32], so: Shape, k: usize, s: usize, w: &[f32], b: &[f32]) {
    let c = si.c;
    let pt = same_pad(si.h, k, s).1;
    let pl = same_pad(si.w, k, s).1;
    for oy in 0..so.h {
        for ox in 0..so.w {
            let d = &mut out[(oy * so.w + ox) * c..][..c];
            d.copy_from_slice(b);
            for ky in 0..k {
                let iy = (oy * s + ky) as isize - pt as isize;
                if iy < 0 || iy >= si.h as isize {
                    continue;
                }
                for kx in 0..k {
                    let ix = (ox * s + kx) as isize - pl as isize;
                    if ix < 0 || ix >= si.w as isize {
                        continue;
                    }
                    let px = &a[(iy as usize * si.w + ix as usize) * c..][..c];
                    let wk = &w[(ky * k + kx) * c..][..c];
                    for ((d, &x), &wv) in d.iter_mut().zip(px).zip(wk) {
                        *d += x * wv;
                    }
                }
            }
        }
    }
}

fn tconv2x(a: &[f32], si: Shape, out: &mut [f32], so: Shape, w: &[f32], b: &[f32]) {
    let (cin, cout) = (si.c, so.c);
    for iy in 0..si.h {
        for ix in 0..si.w {
            let px = &a[(iy * si.w + ix) * cin..][..cin];
            for ky in 0..2 {
                for kx in 0..2 {
                    let d = &mut out[((2 * iy + ky) * so.w + 2 * ix + kx) * cout..][..cout];
                    d.copy_from_slice(b);
                    let wk = &w[(ky * 2 + kx) * cin * cout..][..cin * cout];
                    for (&x, wr) in px.iter().zip(wk.chunks_exact(cout)) {
                        for (d, &wv) in d.iter_mut().zip(wr) {
                            *d += x * wv;
                        }
                    }
                }
            }
        }
    }
}

/// Bilinear 2x upscale with half-pixel centers.
fn resize2x(a: &[f32], si: Shape, out: &mut [f32]) {
    let axis = |n: usize| -> Vec<(usize, usize, f32)> {
        (0..2 * n)
            .map(|i| {
                let src = ((i as f32 + 0.5) / 2.0 - 0.5).max(0.0);
                let i0 = src as usize;
                (i0, (i0 + 1).min(n - 1), src - i0 as f32)
            })
            .collect()
    };
    let (ys, xs) = (axis(si.h), axis(si.w));
    let c = si.c;
    let ow = 2 * si.w;
    for (oy, &(y0, y1, fy)) in ys.iter().enumerate() {
        for (ox, &(x0, x1, fx)) in xs.iter().enumerate() {
            let d = &mut out[(oy * ow + ox) * c..][..c];
            let p00 = &a[(y0 * si.w + x0) * c..][..c];
            let p01 = &a[(y0 * si.w + x1) * c..][..c];
            let p10 = &a[(y1 * si.w + x0) * c..][..c];
            let p11 = &a[(y1 * si.w + x1) * c..][..c];
            for ch in 0..c {
                let top = p00[ch] * (1.0 - fx) + p01[ch] * fx;
                let bot = p10[ch] * (1.0 - fx) + p11[ch] * fx;
                d[ch] = top * (1.0 - fy) + bot * fy;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The picture tools' fixture was made from: a shaded background with a
    /// head-and-shoulders shape (f64 math, then f32, like numpy).
    fn picture() -> Vec<f32> {
        let mut x = Vec::with_capacity(256 * 256 * 3);
        for row in 0..256 {
            for col in 0..256 {
                let (yy, xx) = (row as f64 / 256.0, col as f64 / 256.0);
                let head = ((xx - 0.5) / 0.18).powi(2) + ((yy - 0.38) / 0.24).powi(2) < 1.0;
                let body = ((xx - 0.5) / 0.38).powi(2) + ((yy - 1.05) / 0.42).powi(2) < 1.0;
                let skin = [0.85, 0.65, 0.55];
                for c in 0..3 {
                    let v = if head || body {
                        skin[c]
                    } else {
                        (6.0 * xx + c as f64).sin() * (4.0 * yy - c as f64).cos() * 0.25 + 0.5
                    };
                    x.push(v as f32);
                }
            }
        }
        x
    }

    #[test]
    fn matches_reference_logits() {
        let mut seg = Segmenter::load(crate::MODEL).unwrap();
        assert_eq!(seg.input_size(), (256, 256));
        seg.input_mut().copy_from_slice(&picture());
        let start = std::time::Instant::now();
        let mask_len = seg.run().len();
        eprintln!("one run: {:?}", start.elapsed());
        assert_eq!(mask_len, 256 * 256);
        let Some(Op::Sigmoid(logits, _)) = seg.ops.last() else {
            panic!("model doesn't end in a sigmoid");
        };
        let logits = &seg.tensors[*logits];
        // Every 8th pixel (from 4) of the reference interpreter's logits,
        // which match TFLite's to about 1e-5 relative.
        let want: Vec<f32> = include_bytes!("test_logits.bin")
            .chunks_exact(4)
            .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
            .collect();
        let mut worst = 0f32;
        for (n, &w) in want.iter().enumerate() {
            let (row, col) = (4 + 8 * (n / 32), 4 + 8 * (n % 32));
            let got = logits[row * 256 + col];
            worst = worst.max((got - w).abs() / w.abs().max(1.0));
        }
        eprintln!("worst relative logit error {worst}");
        assert!(worst < 1e-3, "worst relative logit error {worst}");
    }

    #[test]
    fn rejects_bad_models() {
        assert!(Segmenter::load(b"nope").is_err());
        assert!(Segmenter::load(&crate::MODEL[..1000]).is_err());
        let mut v = crate::MODEL.to_vec();
        v.push(0);
        assert!(Segmenter::load(&v).is_err());
    }

    #[test]
    fn f16_conversion() {
        assert_eq!(f16_to_f32(0x3c00), 1.0);
        assert_eq!(f16_to_f32(0xc000), -2.0);
        assert_eq!(f16_to_f32(0x0001), 2f32.powi(-24));
        assert_eq!(f16_to_f32(0x7bff), 65504.0);
        assert_eq!(f16_to_f32(0x8000), -0.0);
    }
}
