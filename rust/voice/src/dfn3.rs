//! Streaming DeepFilterNet3 (Schröter et al., MIT OR Apache-2.0), one 10 ms hop
//! at a time, in plain Rust.
//!
//! This follows torchDF's streaming formulation of the model
//! (github.com/grazder/DeepFilterNet, `torch_df_streaming.py`), with its
//! optional stage skipping. The weights in `third_party/deepfilternet/dfn3.bin` come from
//! the official v0.5.6 checkpoint via `export_weights.py`, with batch norms
//! folded in. No inference runtime is involved: the whole network is about 2.1 M
//! weights and 3.5 M multiply-adds per hop.

use std::collections::HashMap;
use std::sync::Arc;

use realfft::num_complex::Complex32;
use realfft::{ComplexToReal, RealFftPlanner, RealToComplex};

pub const HOP: usize = 480;
const FFT: usize = 960;
const NF: usize = FFT / 2 + 1;
const NB_ERB: usize = 32;
const NB_DF: usize = 96;
const DF_ORDER: usize = 5;
const CONV_LOOKAHEAD: usize = 2;
const LOOKAHEAD: usize = 2;
const CH: usize = 64;
const HIDDEN: usize = 256;
const ALPHA: f32 = 0.99;
const MIN_DB: f32 = -10.0;
const MAX_DB_ERB: f32 = 30.0;
const MAX_DB_DF: f32 = 20.0;
const SILENCE: f32 = 1e-7;
const LSNR_MIN: f32 = -15.0;
const LSNR_MAX: f32 = 35.0;
const X_FRAMES: usize = if DF_ORDER > CONV_LOOKAHEAD {
    DF_ORDER
} else {
    CONV_LOOKAHEAD
};
const Y_FRAMES: usize = DF_ORDER + CONV_LOOKAHEAD;

static WEIGHTS: &[u8] = include_bytes!("../third_party/deepfilternet/dfn3.bin");

#[derive(Debug, thiserror::Error)]
pub enum Dfn3Error {
    #[error("weights file is malformed: {0}")]
    BadWeights(&'static str),
    #[error("weights file lacks tensor {0}")]
    MissingTensor(String),
    #[error("tensor {name} has {got} values, expected {want}")]
    WrongSize {
        name: String,
        got: usize,
        want: usize,
    },
}

struct Tensors(HashMap<String, Vec<f32>>);

impl Tensors {
    fn parse(bytes: &[u8]) -> Result<Self, Dfn3Error> {
        let mut r = Reader { bytes, pos: 0 };
        if r.take(4)? != b"VDF3" {
            return Err(Dfn3Error::BadWeights("magic"));
        }
        if r.u32()? != 1 {
            return Err(Dfn3Error::BadWeights("version"));
        }
        let count = r.u32()?;
        let mut map = HashMap::new();
        for _ in 0..count {
            let name_len = r.u16()? as usize;
            let name = std::str::from_utf8(r.take(name_len)?)
                .map_err(|_| Dfn3Error::BadWeights("name"))?
                .to_owned();
            let rank = r.take(1)?[0] as usize;
            let mut len = 1usize;
            for _ in 0..rank {
                len *= r.u32()? as usize;
            }
            let data = r.take(len * 2)?;
            let values = data
                .chunks_exact(2)
                .map(|b| f16_to_f32(u16::from_le_bytes([b[0], b[1]])))
                .collect();
            map.insert(name, values);
        }
        Ok(Tensors(map))
    }

    fn get(&mut self, name: &str, want: usize) -> Result<Vec<f32>, Dfn3Error> {
        let v = self
            .0
            .remove(name)
            .ok_or_else(|| Dfn3Error::MissingTensor(name.to_owned()))?;
        if v.len() != want {
            return Err(Dfn3Error::WrongSize {
                name: name.to_owned(),
                got: v.len(),
                want,
            });
        }
        Ok(v)
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], Dfn3Error> {
        let end = self
            .pos
            .checked_add(n)
            .ok_or(Dfn3Error::BadWeights("length"))?;
        let s = self
            .bytes
            .get(self.pos..end)
            .ok_or(Dfn3Error::BadWeights("truncated"))?;
        self.pos = end;
        Ok(s)
    }
    fn u16(&mut self) -> Result<u16, Dfn3Error> {
        let b = self.take(2)?;
        Ok(u16::from_le_bytes([b[0], b[1]]))
    }
    fn u32(&mut self) -> Result<u32, Dfn3Error> {
        let b = self.take(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
}

fn f16_to_f32(h: u16) -> f32 {
    let sign = ((h >> 15) as u32) << 31;
    let exp = ((h >> 10) & 0x1f) as u32;
    let mant = (h & 0x3ff) as u32;
    let bits = match (exp, mant) {
        (0, 0) => sign,
        (0, m) => {
            // Subnormal: normalise.
            let shift = m.leading_zeros() - 21;
            sign | ((113 - shift) << 23) | (((m << shift) & 0x3ff) << 13)
        }
        (31, 0) => sign | 0x7f80_0000,
        (31, m) => sign | 0x7f80_0000 | (m << 13),
        (e, m) => sign | ((e + 112) << 23) | (m << 13),
    };
    f32::from_bits(bits)
}

/// Dot product with independent accumulators so it vectorises.
#[inline]
fn dot(a: &[f32], b: &[f32]) -> f32 {
    let mut acc = [0f32; 8];
    let ca = a.chunks_exact(8);
    let cb = b.chunks_exact(8);
    let (ra, rb) = (ca.remainder(), cb.remainder());
    for (x, y) in ca.zip(cb) {
        for i in 0..8 {
            acc[i] += x[i] * y[i];
        }
    }
    let mut s = (acc[0] + acc[4]) + (acc[1] + acc[5]) + ((acc[2] + acc[6]) + (acc[3] + acc[7]));
    for (x, y) in ra.iter().zip(rb) {
        s += x * y;
    }
    s
}

#[inline]
fn sigmoid(x: f32) -> f32 {
    1.0 / (1.0 + (-x).exp())
}

fn relu(v: &mut [f32]) {
    for x in v {
        *x = x.max(0.0);
    }
}

/// Grouped linear layer, weights stored [groups][out/groups][in/groups].
struct GroupedLinear {
    w: Vec<f32>,
    groups: usize,
    ig: usize,
    hg: usize,
}

impl GroupedLinear {
    fn load(
        t: &mut Tensors,
        name: &str,
        input: usize,
        output: usize,
        groups: usize,
    ) -> Result<Self, Dfn3Error> {
        Ok(Self {
            w: t.get(name, input * output / groups)?,
            groups,
            ig: input / groups,
            hg: output / groups,
        })
    }
    fn forward(&self, x: &[f32], out: &mut [f32]) {
        for g in 0..self.groups {
            let xs = &x[g * self.ig..(g + 1) * self.ig];
            for h in 0..self.hg {
                let row = (g * self.hg + h) * self.ig;
                out[g * self.hg + h] = dot(&self.w[row..row + self.ig], xs);
            }
        }
    }
}

struct GruLayer {
    w_ih: Vec<f32>,
    w_hh: Vec<f32>,
    b_ih: Vec<f32>,
    b_hh: Vec<f32>,
}

impl GruLayer {
    fn load(t: &mut Tensors, prefix: &str, layer: usize) -> Result<Self, Dfn3Error> {
        let g = 3 * HIDDEN;
        Ok(Self {
            w_ih: t.get(&format!("{prefix}.{layer}.weight_ih"), g * HIDDEN)?,
            w_hh: t.get(&format!("{prefix}.{layer}.weight_hh"), g * HIDDEN)?,
            b_ih: t.get(&format!("{prefix}.{layer}.bias_ih"), g)?,
            b_hh: t.get(&format!("{prefix}.{layer}.bias_hh"), g)?,
        })
    }

    /// PyTorch GRU cell; `h` is updated in place, gate order r, z, n.
    fn step(&self, x: &[f32], h: &mut [f32], scratch: &mut [f32]) {
        let (gi, gh) = scratch.split_at_mut(3 * HIDDEN);
        for r in 0..3 * HIDDEN {
            gi[r] = dot(&self.w_ih[r * HIDDEN..(r + 1) * HIDDEN], x) + self.b_ih[r];
            gh[r] = dot(&self.w_hh[r * HIDDEN..(r + 1) * HIDDEN], h) + self.b_hh[r];
        }
        for i in 0..HIDDEN {
            let r = sigmoid(gi[i] + gh[i]);
            let z = sigmoid(gi[HIDDEN + i] + gh[HIDDEN + i]);
            let n = (gi[2 * HIDDEN + i] + r * gh[2 * HIDDEN + i]).tanh();
            h[i] = (1.0 - z) * n + z * h[i];
        }
    }
}

/// SqueezedGRU_S: ReLU(grouped linear in) -> GRU layers -> optional ReLU(grouped linear out).
struct SqueezedGru {
    lin_in: GroupedLinear,
    layers: Vec<GruLayer>,
    lin_out: Option<GroupedLinear>,
}

impl SqueezedGru {
    fn forward(
        &self,
        x: &[f32],
        hidden: &mut [f32],
        out: &mut [f32],
        gru_in: &mut [f32],
        gates: &mut [f32],
    ) {
        self.lin_in.forward(x, gru_in);
        relu(gru_in);
        for (l, layer) in self.layers.iter().enumerate() {
            let h = &mut hidden[l * HIDDEN..(l + 1) * HIDDEN];
            layer.step(gru_in, h, gates);
            gru_in.copy_from_slice(h);
        }
        match &self.lin_out {
            Some(lin) => {
                lin.forward(gru_in, out);
                relu(out);
            }
            None => out.copy_from_slice(gru_in),
        }
    }
}

/// Depthwise conv over frequency (kernel 3, padding 1) on a [CH][f] map.
fn depthwise3(input: &[f32], f: usize, w: &[f32], stride: usize, out: &mut [f32]) {
    let fo = (f + 2 - 3) / stride + 1;
    for c in 0..CH {
        let x = &input[c * f..(c + 1) * f];
        let k = &w[c * 3..c * 3 + 3];
        for o in 0..fo {
            let mut acc = 0.0;
            for (j, kj) in k.iter().enumerate() {
                let i = (o * stride + j) as isize - 1;
                if i >= 0 && (i as usize) < f {
                    acc += kj * x[i as usize];
                }
            }
            out[c * fo + o] = acc;
        }
    }
}

/// Pointwise conv [cin][f] -> [cout][f] plus bias.
fn pointwise(input: &[f32], cin: usize, f: usize, w: &[f32], b: &[f32], out: &mut [f32]) {
    let cout = b.len();
    for co in 0..cout {
        let o = &mut out[co * f..(co + 1) * f];
        o.fill(b[co]);
        for ci in 0..cin {
            let wv = w[co * cin + ci];
            let x = &input[ci * f..(ci + 1) * f];
            for (oo, xx) in o.iter_mut().zip(x) {
                *oo += wv * xx;
            }
        }
    }
}

/// Depthwise transposed conv over frequency (kernel 3, stride 2, padding 1,
/// output padding 1): [CH][f] -> [CH][2f].
fn depthwise_transposed3(input: &[f32], f: usize, w: &[f32], out: &mut [f32]) {
    let fo = 2 * f;
    for c in 0..CH {
        let o = &mut out[c * fo..(c + 1) * fo];
        o.fill(0.0);
        let k = &w[c * 3..c * 3 + 3];
        for fi in 0..f {
            let x = input[c * f + fi];
            for (j, kj) in k.iter().enumerate() {
                let idx = (2 * fi + j) as isize - 1;
                if idx >= 0 && (idx as usize) < fo {
                    o[idx as usize] += x * kj;
                }
            }
        }
    }
}

struct Separable {
    dw: Vec<f32>,
    pw: Vec<f32>,
    b: Vec<f32>,
}

impl Separable {
    fn load(t: &mut Tensors, name: &str) -> Result<Self, Dfn3Error> {
        Ok(Self {
            dw: t.get(&format!("{name}.dw"), CH * 3)?,
            pw: t.get(&format!("{name}.pw"), CH * CH)?,
            b: t.get(&format!("{name}.b"), CH)?,
        })
    }
}

struct ChannelAffine {
    w: Vec<f32>,
    b: Vec<f32>,
}

impl ChannelAffine {
    fn load(t: &mut Tensors, name: &str) -> Result<Self, Dfn3Error> {
        Ok(Self {
            w: t.get(&format!("{name}.w"), CH)?,
            b: t.get(&format!("{name}.b"), CH)?,
        })
    }
    /// out = relu(input * w + b) + add
    fn forward_add(&self, input: &[f32], f: usize, add: &[f32], out: &mut [f32]) {
        for c in 0..CH {
            for i in 0..f {
                let k = c * f + i;
                out[k] = (input[k] * self.w[c] + self.b[c]).max(0.0) + add[k];
            }
        }
    }
}

struct Net {
    erb_conv0_w: Vec<f32>,
    erb_conv0_b: Vec<f32>,
    erb_conv: [Separable; 3],
    df_conv0_w: Vec<f32>,
    df_conv0_pw: Vec<f32>,
    df_conv0_b: Vec<f32>,
    df_conv1: Separable,
    df_fc_emb: GroupedLinear,
    enc_gru: SqueezedGru,
    lsnr_w: Vec<f32>,
    lsnr_b: f32,
    erb_gru: SqueezedGru,
    convp: [ChannelAffine; 4], // conv3p, conv2p, conv1p, conv0p
    convt3: Separable,
    convt2: Separable,
    convt1: Separable,
    conv0_out_w: Vec<f32>,
    conv0_out_b: f32,
    df_convp_w: Vec<f32>,
    df_convp_pw: Vec<f32>,
    df_convp_b: Vec<f32>,
    df_gru: SqueezedGru,
    df_skip: GroupedLinear,
    df_out: GroupedLinear,
    erb_widths: Vec<usize>,
}

impl Net {
    fn load(bytes: &[u8]) -> Result<Self, Dfn3Error> {
        let mut t = Tensors::parse(bytes)?;
        let gru = |t: &mut Tensors,
                   p: &str,
                   layers: usize,
                   li_groups: usize,
                   out: Option<usize>|
         -> Result<SqueezedGru, Dfn3Error> {
            let emb = CH * NB_ERB / 4;
            Ok(SqueezedGru {
                lin_in: GroupedLinear::load(t, &format!("{p}.lin_in"), emb, HIDDEN, li_groups)?,
                layers: (0..layers)
                    .map(|l| GruLayer::load(t, &format!("{p}.gru"), l))
                    .collect::<Result<_, _>>()?,
                lin_out: match out {
                    Some(g) => Some(GroupedLinear::load(
                        t,
                        &format!("{p}.lin_out"),
                        HIDDEN,
                        emb,
                        g,
                    )?),
                    None => None,
                },
            })
        };
        let emb = CH * NB_ERB / 4;
        let widths: Vec<usize> = t
            .get("erb_widths", NB_ERB)?
            .iter()
            .map(|w| *w as usize)
            .collect();
        if widths.iter().sum::<usize>() != NF {
            return Err(Dfn3Error::BadWeights("erb widths"));
        }
        Ok(Self {
            erb_conv0_w: t.get("enc.erb_conv0.w", CH * 9)?,
            erb_conv0_b: t.get("enc.erb_conv0.b", CH)?,
            erb_conv: [
                Separable::load(&mut t, "enc.erb_conv1")?,
                Separable::load(&mut t, "enc.erb_conv2")?,
                Separable::load(&mut t, "enc.erb_conv3")?,
            ],
            df_conv0_w: t.get("enc.df_conv0.w", CH * 9)?,
            df_conv0_pw: t.get("enc.df_conv0.pw", CH * CH)?,
            df_conv0_b: t.get("enc.df_conv0.b", CH)?,
            df_conv1: Separable::load(&mut t, "enc.df_conv1")?,
            df_fc_emb: GroupedLinear::load(&mut t, "enc.df_fc_emb", CH * NB_DF / 2, emb, 32)?,
            enc_gru: gru(&mut t, "enc.emb_gru", 1, 16, Some(16))?,
            lsnr_w: t.get("enc.lsnr.w", emb)?,
            lsnr_b: t.get("enc.lsnr.b", 1)?[0],
            erb_gru: gru(&mut t, "erb_dec.emb_gru", 2, 16, Some(16))?,
            convp: [
                ChannelAffine::load(&mut t, "erb_dec.conv3p")?,
                ChannelAffine::load(&mut t, "erb_dec.conv2p")?,
                ChannelAffine::load(&mut t, "erb_dec.conv1p")?,
                ChannelAffine::load(&mut t, "erb_dec.conv0p")?,
            ],
            convt3: Separable::load(&mut t, "erb_dec.convt3")?,
            convt2: Separable::load(&mut t, "erb_dec.convt2")?,
            convt1: Separable::load(&mut t, "erb_dec.convt1")?,
            conv0_out_w: t.get("erb_dec.conv0_out.w", CH * 3)?,
            conv0_out_b: t.get("erb_dec.conv0_out.b", 1)?[0],
            df_convp_w: t.get("df_dec.df_convp.w", 2 * DF_ORDER * (CH / 2) * DF_ORDER)?,
            df_convp_pw: t.get("df_dec.df_convp.pw", 4 * DF_ORDER * DF_ORDER)?,
            df_convp_b: t.get("df_dec.df_convp.b", 2 * DF_ORDER)?,
            df_gru: gru(&mut t, "df_dec.df_gru", 2, 8, None)?,
            df_skip: GroupedLinear::load(&mut t, "df_dec.df_skip", emb, HIDDEN, 16)?,
            df_out: GroupedLinear::load(&mut t, "df_dec.df_out", HIDDEN, NB_DF * DF_ORDER * 2, 16)?,
            erb_widths: widths,
        })
    }
}

/// Preallocated working memory, so a hop never allocates.
struct Scratch {
    gru_in: Vec<f32>,
    gates: Vec<f32>,
    e0: Vec<f32>,
    e1: Vec<f32>,
    e2: Vec<f32>,
    e3: Vec<f32>,
    c0: Vec<f32>,
    c1: Vec<f32>,
    a: Vec<f32>,
    b: Vec<f32>,
    c: Vec<f32>,
    emb_in: Vec<f32>,
    emb: Vec<f32>,
    gains: Vec<f32>,
    df_c: Vec<f32>,
    df_out: Vec<f32>,
    df_p: Vec<f32>,
    fft_in: Vec<f32>,
    fft_out: Vec<f32>,
    spec: Vec<Complex32>,
    cur: Vec<Complex32>,
    fft_scratch: Vec<Complex32>,
    coefs: Vec<Complex32>,
}

impl Scratch {
    fn new(fft_scratch: usize) -> Self {
        let z = |n| vec![0f32; n];
        let zc = |n| vec![Complex32::new(0.0, 0.0); n];
        Self {
            gru_in: z(HIDDEN),
            gates: z(6 * HIDDEN),
            e0: z(CH * NB_ERB),
            e1: z(CH * NB_ERB / 2),
            e2: z(CH * NB_ERB / 4),
            e3: z(CH * NB_ERB / 4),
            c0: z(CH * NB_DF),
            c1: z(CH * NB_DF / 2),
            a: z(CH * NB_DF),
            b: z(CH * NB_DF),
            c: z(CH * NB_DF),
            emb_in: z(CH * NB_ERB / 4),
            emb: z(CH * NB_ERB / 4),
            gains: z(NB_ERB),
            df_c: z(HIDDEN),
            df_out: z(NB_DF * DF_ORDER * 2),
            df_p: z(2 * DF_ORDER * NB_DF),
            fft_in: z(FFT),
            fft_out: z(FFT),
            spec: zc(NF),
            cur: zc(NF),
            fft_scratch: zc(fft_scratch),
            coefs: zc(DF_ORDER * NB_DF),
        }
    }
}

/// Recurrent state; everything one hop needs from the previous ones.
struct State {
    erb_norm: Vec<f32>,
    unit_norm: Vec<f32>,
    analysis_mem: Vec<f32>,
    synthesis_mem: Vec<f32>,
    erb_buf: Vec<f32>,     // [CONV_LOOKAHEAD + 1][NB_ERB]
    spec_buf: Vec<f32>,    // [2][CONV_LOOKAHEAD + 1][NB_DF]
    c0_buf: Vec<f32>,      // [CH][DF_ORDER][NB_DF]
    x_buf: Vec<Complex32>, // [X_FRAMES][NF]
    y_buf: Vec<Complex32>, // [Y_FRAMES][NF]
    h_enc: Vec<f32>,
    h_erb: Vec<f32>,
    h_df: Vec<f32>,
}

impl State {
    fn new() -> Self {
        let lin = |a: f32, b: f32, n: usize| -> Vec<f32> {
            (0..n)
                .map(|i| a + (b - a) * i as f32 / (n - 1) as f32)
                .collect()
        };
        Self {
            erb_norm: lin(-60.0, -90.0, NB_ERB),
            unit_norm: lin(0.001, 0.0001, NB_DF),
            analysis_mem: vec![0.0; HOP],
            synthesis_mem: vec![0.0; HOP],
            erb_buf: vec![0.0; (CONV_LOOKAHEAD + 1) * NB_ERB],
            spec_buf: vec![0.0; 2 * (CONV_LOOKAHEAD + 1) * NB_DF],
            c0_buf: vec![0.0; CH * DF_ORDER * NB_DF],
            x_buf: vec![Complex32::new(0.0, 0.0); X_FRAMES * NF],
            y_buf: vec![Complex32::new(0.0, 0.0); Y_FRAMES * NF],
            h_enc: vec![0.0; HIDDEN],
            h_erb: vec![0.0; 2 * HIDDEN],
            h_df: vec![0.0; 2 * HIDDEN],
        }
    }
}

/// [c][f] -> [f][c]
fn to_channels_last(input: &[f32], c: usize, f: usize, out: &mut [f32]) {
    for ci in 0..c {
        for fi in 0..f {
            out[fi * c + ci] = input[ci * f + fi];
        }
    }
}

/// [f][c] -> [c][f]
fn to_channels_first(input: &[f32], f: usize, c: usize, out: &mut [f32]) {
    for fi in 0..f {
        for ci in 0..c {
            out[ci * f + fi] = input[fi * c + ci];
        }
    }
}

/// Depthwise conv (stride 1 or 2) -> pointwise -> ReLU, on [CH][f] maps.
fn separable(
    l: &Separable,
    input: &[f32],
    f: usize,
    stride: usize,
    tmp: &mut [f32],
    out: &mut [f32],
) {
    let fo = (f - 1) / stride + 1;
    depthwise3(input, f, &l.dw, stride, tmp);
    pointwise(&tmp[..CH * fo], CH, fo, &l.pw, &l.b, out);
    relu(&mut out[..CH * fo]);
}

/// Depthwise transposed conv (doubles frequency) -> pointwise -> ReLU.
fn separable_transposed(l: &Separable, input: &[f32], f: usize, tmp: &mut [f32], out: &mut [f32]) {
    depthwise_transposed3(input, f, &l.dw, tmp);
    pointwise(&tmp[..CH * 2 * f], CH, 2 * f, &l.pw, &l.b, out);
    relu(&mut out[..CH * 2 * f]);
}

/// Shared, immutable model (weights and FFT plans); cheap to clone.
#[derive(Clone)]
pub struct Model {
    net: Arc<Net>,
    fft: Arc<dyn RealToComplex<f32>>,
    ifft: Arc<dyn ComplexToReal<f32>>,
    window: Arc<Vec<f32>>,
}

impl Model {
    /// Decodes the weights compiled into the library.
    pub fn load() -> Result<Self, Dfn3Error> {
        let mut planner = RealFftPlanner::<f32>::new();
        let window = (0..FFT)
            .map(|n| {
                let w = (0.5 * std::f32::consts::PI * (n as f32 + 0.5) / (FFT / 2) as f32).sin();
                (0.5 * std::f32::consts::PI * w * w).sin()
            })
            .collect();
        Ok(Self {
            net: Arc::new(Net::load(WEIGHTS)?),
            fft: planner.plan_fft_forward(FFT),
            ifft: planner.plan_fft_inverse(FFT),
            window: Arc::new(window),
        })
    }
}

/// One audio stream's denoiser.
pub struct Dfn3 {
    model: Model,
    st: State,
    s: Scratch,
    /// Run every stage on every hop (the default). When false, stages are
    /// skipped on hops the model judges noise-only or clean, with torchDF's
    /// thresholds (-10/30/20 dB); that saves CPU but mutes speech buried in
    /// loud noise. libDF's own defaults (-15/35/35 dB) span the model's whole
    /// output range, so the official tools effectively always apply too.
    pub always_apply: bool,
    /// Last local SNR estimate in dB.
    pub last_lsnr: f32,
}

impl Dfn3 {
    pub fn new(model: Model) -> Self {
        let scratch = model
            .fft
            .get_scratch_len()
            .max(model.ifft.get_scratch_len());
        Self {
            model,
            st: State::new(),
            s: Scratch::new(scratch),
            always_apply: true,
            last_lsnr: 0.0,
        }
    }

    /// Enhances one hop in place. Samples are full scale ±1.0. The output is
    /// delayed by 30 ms (one hop of overlap-add plus two hops of lookahead).
    pub fn process(&mut self, frame: &mut [f32]) {
        debug_assert_eq!(frame.len(), HOP);
        let energy: f32 = frame.iter().map(|x| x * x).sum::<f32>() / HOP as f32;
        if energy < SILENCE {
            // Digital silence: output silence and leave the state alone.
            frame.fill(0.0);
            return;
        }
        let net = &*self.model.net;
        let window = &*self.model.window;
        let st = &mut self.st;
        let s = &mut self.s;

        // Analysis: window [previous hop, this hop], real FFT, libDF's scaling.
        s.fft_in[..HOP].copy_from_slice(&st.analysis_mem);
        s.fft_in[HOP..].copy_from_slice(frame);
        for (x, w) in s.fft_in.iter_mut().zip(window) {
            *x *= w;
        }
        st.analysis_mem.copy_from_slice(frame);
        // Sizes are fixed, so the FFT cannot fail.
        let _ = self
            .model
            .fft
            .process_with_scratch(&mut s.fft_in, &mut s.spec, &mut s.fft_scratch);
        let wnorm = (2 * HOP) as f32 / (FFT * FFT) as f32;
        for c in s.spec.iter_mut() {
            *c *= wnorm;
        }
        st.x_buf.copy_within(NF.., 0);
        st.x_buf[(X_FRAMES - 1) * NF..].copy_from_slice(&s.spec);
        st.y_buf.copy_within(NF.., 0);
        st.y_buf[(Y_FRAMES - 1) * NF..].copy_from_slice(&s.spec);

        // ERB features: band energies in dB, exponentially mean-normalised.
        st.erb_buf.copy_within(NB_ERB.., 0);
        let mut start = 0;
        for (b, &w) in net.erb_widths.iter().enumerate() {
            let e: f32 = s.spec[start..start + w]
                .iter()
                .map(|c| c.norm_sqr())
                .sum::<f32>()
                / w as f32;
            start += w;
            let db = 10.0 * (e + 1e-10).log10();
            st.erb_norm[b] = db + ALPHA * (st.erb_norm[b] - db);
            st.erb_buf[CONV_LOOKAHEAD * NB_ERB + b] = (db - st.erb_norm[b]) / 40.0;
        }
        // Complex features for the deep-filter bins, unit-normalised.
        let t = CONV_LOOKAHEAD + 1;
        for ch in 0..2 {
            let base = ch * t * NB_DF;
            st.spec_buf
                .copy_within(base + NB_DF..base + t * NB_DF, base);
        }
        for f in 0..NB_DF {
            let m = s.spec[f].norm();
            st.unit_norm[f] = m + ALPHA * (st.unit_norm[f] - m);
            let d = st.unit_norm[f].sqrt();
            st.spec_buf[(t - 1) * NB_DF + f] = s.spec[f].re / d;
            st.spec_buf[t * NB_DF + (t - 1) * NB_DF + f] = s.spec[f].im / d;
        }

        // Encoder. erb_conv0: 3x3 conv over [time][freq] (+ folded norm), ReLU.
        for c in 0..CH {
            let k = &net.erb_conv0_w[c * 9..c * 9 + 9];
            for f in 0..NB_ERB {
                let mut acc = net.erb_conv0_b[c];
                for kt in 0..3 {
                    for kf in 0..3 {
                        let fi = f as isize + kf as isize - 1;
                        if fi >= 0 && (fi as usize) < NB_ERB {
                            acc += k[kt * 3 + kf] * st.erb_buf[kt * NB_ERB + fi as usize];
                        }
                    }
                }
                s.e0[c * NB_ERB + f] = acc.max(0.0);
            }
        }
        separable(&net.erb_conv[0], &s.e0, NB_ERB, 2, &mut s.a, &mut s.e1);
        separable(&net.erb_conv[1], &s.e1, NB_ERB / 2, 2, &mut s.a, &mut s.e2);
        separable(&net.erb_conv[2], &s.e2, NB_ERB / 4, 1, &mut s.a, &mut s.e3);
        // df_conv0: grouped 3x3 conv (real part -> channels 0..32, imaginary
        // part -> 32..64), pointwise, ReLU.
        for c in 0..CH {
            let src = &st.spec_buf[(c / (CH / 2)) * t * NB_DF..];
            let k = &net.df_conv0_w[c * 9..c * 9 + 9];
            for f in 0..NB_DF {
                let mut acc = 0.0;
                for kt in 0..3 {
                    for kf in 0..3 {
                        let fi = f as isize + kf as isize - 1;
                        if fi >= 0 && (fi as usize) < NB_DF {
                            acc += k[kt * 3 + kf] * src[kt * NB_DF + fi as usize];
                        }
                    }
                }
                s.a[c * NB_DF + f] = acc;
            }
        }
        pointwise(
            &s.a,
            CH,
            NB_DF,
            &net.df_conv0_pw,
            &net.df_conv0_b,
            &mut s.c0,
        );
        relu(&mut s.c0);
        separable(&net.df_conv1, &s.c0, NB_DF, 2, &mut s.a, &mut s.c1);
        // Embedding: channels-last flatten of both paths, summed, through the GRU.
        to_channels_last(&s.c1, CH, NB_DF / 2, &mut s.b);
        net.df_fc_emb.forward(&s.b[..CH * NB_DF / 2], &mut s.emb_in);
        relu(&mut s.emb_in);
        to_channels_last(&s.e3, CH, NB_ERB / 4, &mut s.b);
        for (e, x) in s.emb_in.iter_mut().zip(&s.b) {
            *e += x;
        }
        net.enc_gru.forward(
            &s.emb_in,
            &mut st.h_enc,
            &mut s.emb,
            &mut s.gru_in,
            &mut s.gates,
        );
        let lsnr =
            sigmoid(dot(&net.lsnr_w, &s.emb) + net.lsnr_b) * (LSNR_MAX - LSNR_MIN) + LSNR_MIN;
        self.last_lsnr = lsnr;

        let (apply_gains, apply_df, apply_zeros) = if self.always_apply {
            (true, true, false)
        } else {
            (
                (MIN_DB..=MAX_DB_ERB).contains(&lsnr),
                (MIN_DB..=MAX_DB_DF).contains(&lsnr),
                lsnr <= MIN_DB,
            )
        };

        // ERB decoder -> one gain per band. Skipped hops keep the old GRU state.
        if apply_gains {
            let f4 = NB_ERB / 4;
            let f2 = NB_ERB / 2;
            net.erb_gru.forward(
                &s.emb,
                &mut st.h_erb,
                &mut s.emb_in,
                &mut s.gru_in,
                &mut s.gates,
            );
            to_channels_first(&s.emb_in, f4, CH, &mut s.b);
            net.convp[0].forward_add(&s.e3, f4, &s.b, &mut s.c);
            separable(&net.convt3, &s.c, f4, 1, &mut s.a, &mut s.b);
            net.convp[1].forward_add(&s.e2, f4, &s.b, &mut s.c);
            separable_transposed(&net.convt2, &s.c, f4, &mut s.a, &mut s.b);
            net.convp[2].forward_add(&s.e1, f2, &s.b, &mut s.c);
            separable_transposed(&net.convt1, &s.c, f2, &mut s.a, &mut s.b);
            net.convp[3].forward_add(&s.e0, NB_ERB, &s.b, &mut s.c);
            for f in 0..NB_ERB {
                let mut acc = net.conv0_out_b;
                for c in 0..CH {
                    let k = &net.conv0_out_w[c * 3..c * 3 + 3];
                    for (j, kj) in k.iter().enumerate() {
                        let fi = f as isize + j as isize - 1;
                        if fi >= 0 && (fi as usize) < NB_ERB {
                            acc += kj * s.c[c * NB_ERB + fi as usize];
                        }
                    }
                }
                s.gains[f] = sigmoid(acc);
            }
        } else {
            s.gains.fill(0.0);
        }

        // Deep-filter decoder -> DF_ORDER complex taps per low bin. Skipped
        // hops keep the old c0 window and GRU state.
        if apply_df {
            for c in 0..CH {
                let base = c * DF_ORDER * NB_DF;
                st.c0_buf
                    .copy_within(base + NB_DF..base + DF_ORDER * NB_DF, base);
                let last = base + (DF_ORDER - 1) * NB_DF;
                st.c0_buf[last..last + NB_DF].copy_from_slice(&s.c0[c * NB_DF..(c + 1) * NB_DF]);
            }
            net.df_gru.forward(
                &s.emb,
                &mut st.h_df,
                &mut s.df_c,
                &mut s.gru_in,
                &mut s.gates,
            );
            net.df_skip.forward(&s.emb, &mut s.gru_in);
            for (c, k) in s.df_c.iter_mut().zip(&s.gru_in) {
                *c += k;
            }
            net.df_out.forward(&s.df_c, &mut s.df_out);
            // df_convp: grouped conv over the 5-hop c0 window (32 channels per
            // group, 5 outputs per group), then pointwise + ReLU.
            let oc = 2 * DF_ORDER;
            let cg = CH / 2;
            for o in 0..oc {
                let g = o / DF_ORDER;
                let out = &mut s.a[o * NB_DF..(o + 1) * NB_DF];
                out.fill(0.0);
                for ci in 0..cg {
                    let c = g * cg + ci;
                    for kt in 0..DF_ORDER {
                        let wv = net.df_convp_w[(o * cg + ci) * DF_ORDER + kt];
                        let x = &st.c0_buf
                            [(c * DF_ORDER + kt) * NB_DF..(c * DF_ORDER + kt + 1) * NB_DF];
                        for (oo, xx) in out.iter_mut().zip(x) {
                            *oo += wv * xx;
                        }
                    }
                }
            }
            pointwise(
                &s.a[..oc * NB_DF],
                oc,
                NB_DF,
                &net.df_convp_pw,
                &net.df_convp_b,
                &mut s.df_p,
            );
            relu(&mut s.df_p);
            for f in 0..NB_DF {
                for k in 0..DF_ORDER {
                    let re = s.df_out[f * oc + 2 * k].tanh() + s.df_p[(2 * k) * NB_DF + f];
                    let im = s.df_out[f * oc + 2 * k + 1].tanh() + s.df_p[(2 * k + 1) * NB_DF + f];
                    s.coefs[k * NB_DF + f] = Complex32::new(re, im);
                }
            }
        }

        // Apply to the spectrum LOOKAHEAD hops back: band gains, then the deep
        // filter over the last DF_ORDER spectra for the low bins.
        s.cur
            .copy_from_slice(&st.y_buf[(DF_ORDER - 1) * NF..DF_ORDER * NF]);
        if apply_gains || apply_zeros {
            let mut start = 0;
            for (b, &w) in net.erb_widths.iter().enumerate() {
                for c in &mut s.cur[start..start + w] {
                    *c *= s.gains[b];
                }
                start += w;
            }
        }
        if apply_df {
            for f in 0..NB_DF {
                let mut acc = Complex32::new(0.0, 0.0);
                for k in 0..DF_ORDER {
                    acc += st.x_buf[k * NF + f] * s.coefs[k * NB_DF + f];
                }
                s.cur[f] = acc;
            }
        }
        debug_assert!(LOOKAHEAD == Y_FRAMES - DF_ORDER);

        // Synthesis: unnormalised inverse FFT (libDF's scaling), window,
        // overlap-add with the previous hop's tail.
        s.cur[0].im = 0.0;
        s.cur[NF - 1].im = 0.0;
        let _ =
            self.model
                .ifft
                .process_with_scratch(&mut s.cur, &mut s.fft_out, &mut s.fft_scratch);
        for (x, w) in s.fft_out.iter_mut().zip(window) {
            *x *= w;
        }
        for i in 0..HOP {
            frame[i] = s.fft_out[i] + st.synthesis_mem[i];
        }
        st.synthesis_mem.copy_from_slice(&s.fft_out[HOP..]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TESTDATA: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/third_party/deepfilternet/testdata"
    );

    fn read_i16(name: &str) -> Vec<f32> {
        let bytes = std::fs::read(format!("{TESTDATA}/{name}")).expect("fixture");
        bytes
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
            .collect()
    }

    /// Output vs the NumPy reference (fp32 weights, see export_weights.py), on
    /// one second of speech with loud keyboard typing that crosses the
    /// stage-skipping thresholds both ways.
    fn check(always_apply: bool, expected: &str) {
        let input = read_i16("fixture_in.i16");
        let want = read_i16(expected);
        let mut d = Dfn3::new(Model::load().expect("weights"));
        d.always_apply = always_apply;
        let mut got = Vec::with_capacity(input.len());
        for hop in input.chunks_exact(HOP) {
            let mut frame = hop.to_vec();
            d.process(&mut frame);
            got.extend(frame);
        }
        let signal: f64 = want.iter().map(|x| (*x as f64).powi(2)).sum();
        let noise: f64 = want
            .iter()
            .zip(&got)
            .map(|(a, b)| ((a - b) as f64).powi(2))
            .sum();
        let snr = 10.0 * (signal / noise.max(1e-30)).log10();
        // fp16 weights and i16 fixtures cost some precision; a wrong layer
        // lands far below this.
        eprintln!("SNR vs reference: {snr:.1} dB");
        assert!(snr > 40.0, "SNR vs reference {snr:.1} dB");
    }

    #[test]
    fn matches_reference_with_stage_skipping() {
        check(false, "fixture_skip_out.i16");
    }

    #[test]
    fn matches_reference_always_applying() {
        check(true, "fixture_all_out.i16");
    }

    #[test]
    fn f16_decoding() {
        assert_eq!(f16_to_f32(0x3c00), 1.0);
        assert_eq!(f16_to_f32(0xc000), -2.0);
        assert_eq!(f16_to_f32(0x0001), 5.960_464_5e-8);
        assert_eq!(f16_to_f32(0x7bff), 65504.0);
    }

    /// cargo test --release -- --ignored --nocapture dfn3_speed
    #[test]
    #[ignore]
    fn dfn3_speed() {
        let input = read_i16("fixture_in.i16");
        let mut d = Dfn3::new(Model::load().expect("weights"));
        d.always_apply = true;
        let hops = 3000;
        let start = std::time::Instant::now();
        for i in 0..hops {
            let k = (i % 100) * HOP;
            let mut frame = input[k..k + HOP].to_vec();
            d.process(&mut frame);
        }
        let us = start.elapsed().as_secs_f64() * 1e6 / hops as f64;
        println!(
            "dfn3: {us:.0} us per 10 ms hop = {:.1} % of one core",
            us / 100.0
        );
    }
}
