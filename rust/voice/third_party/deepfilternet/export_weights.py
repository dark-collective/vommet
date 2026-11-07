"""Converts the DeepFilterNet3 checkpoint into dfn3.bin for src/voice_filter/dfn3.rs.

Source: models/DeepFilterNet3.zip from https://github.com/Rikorose/DeepFilterNet
at tag v0.5.6 (checkpoints/model_120.ckpt.best), MIT OR Apache-2.0.

Batch norms are folded into the preceding convolution (weights scaled per output
channel, the shift becomes a bias), grouped-linear weights are stored output-major
so every layer is a set of dot products, and everything is written as float16.

File format (little endian):
    b"VDF3", u32 version (1), u32 tensor count, then per tensor:
    u16 name length, name (utf-8), u8 rank, u32 dims[rank], f16 data[prod(dims)]

Usage: python export_weights.py model_120.ckpt.best dfn3.bin   (needs torch, numpy)
"""
import struct
import sys

import numpy as np
import torch

EPS_BN = 1e-5


def main(src, dst):
    sd = torch.load(src, map_location="cpu", weights_only=False)
    sd = {k: v.numpy().astype(np.float64) for k, v in sd.items() if hasattr(v, "numpy") and v.ndim > 0}
    out = {}

    def bn(prefix):
        scale = sd[prefix + "weight"] / np.sqrt(sd[prefix + "running_var"] + EPS_BN)
        shift = sd[prefix + "bias"] - sd[prefix + "running_mean"] * scale
        return scale, shift

    def full_conv(name, conv, norm):
        # Plain (or grouped) conv followed by batch norm: fold into weight + bias.
        w = sd[conv]
        s, b = bn(norm)
        out[name + ".w"] = w * s[:, None, None, None]
        out[name + ".b"] = b

    def separable(name, dw, pw, norm):
        # Depthwise conv, pointwise conv, batch norm: fold the norm into the pointwise.
        s, b = bn(norm)
        out[name + ".dw"] = sd[dw]
        out[name + ".pw"] = sd[pw][:, :, 0, 0] * s[:, None]
        out[name + ".b"] = b

    def channel_scale(name, conv, norm):
        # Depthwise 1x1 conv + batch norm = per-channel affine.
        s, b = bn(norm)
        out[name + ".w"] = sd[conv][:, 0, 0, 0] * s
        out[name + ".b"] = b

    def glinear(name, key):
        out[name] = sd[key].transpose(0, 2, 1)  # [G, I/G, H/G] -> [G, H/G, I/G]

    def gru(name, prefix, layers):
        for l in range(layers):
            for kind in ("weight_ih", "weight_hh", "bias_ih", "bias_hh"):
                out[f"{name}.{l}.{kind}"] = sd[f"{prefix}{kind}_l{l}"]

    full_conv("enc.erb_conv0", "enc.erb_conv0.1.weight", "enc.erb_conv0.2.")
    for i in (1, 2, 3):
        p = f"enc.erb_conv{i}."
        separable(f"enc.erb_conv{i}", p + "0.weight", p + "1.weight", p + "2.")
    s, b = bn("enc.df_conv0.3.")
    out["enc.df_conv0.w"] = sd["enc.df_conv0.1.weight"]
    out["enc.df_conv0.pw"] = sd["enc.df_conv0.2.weight"][:, :, 0, 0] * s[:, None]
    out["enc.df_conv0.b"] = b
    separable("enc.df_conv1", "enc.df_conv1.0.weight", "enc.df_conv1.1.weight", "enc.df_conv1.2.")
    glinear("enc.df_fc_emb", "enc.df_fc_emb.0.weight")
    glinear("enc.emb_gru.lin_in", "enc.emb_gru.linear_in.0.weight")
    gru("enc.emb_gru.gru", "enc.emb_gru.gru.", 1)
    glinear("enc.emb_gru.lin_out", "enc.emb_gru.linear_out.0.weight")
    out["enc.lsnr.w"] = sd["enc.lsnr_fc.0.weight"][0]
    out["enc.lsnr.b"] = sd["enc.lsnr_fc.0.bias"]

    glinear("erb_dec.emb_gru.lin_in", "erb_dec.emb_gru.linear_in.0.weight")
    gru("erb_dec.emb_gru.gru", "erb_dec.emb_gru.gru.", 2)
    glinear("erb_dec.emb_gru.lin_out", "erb_dec.emb_gru.linear_out.0.weight")
    for i in (3, 2, 1, 0):
        channel_scale(f"erb_dec.conv{i}p", f"erb_dec.conv{i}p.0.weight", f"erb_dec.conv{i}p.1.")
    for i in (3, 2, 1):
        p = f"erb_dec.convt{i}."
        separable(f"erb_dec.convt{i}", p + "0.weight", p + "1.weight", p + "2.")
    full_conv("erb_dec.conv0_out", "erb_dec.conv0_out.0.weight", "erb_dec.conv0_out.1.")

    s, b = bn("df_dec.df_convp.3.")
    out["df_dec.df_convp.w"] = sd["df_dec.df_convp.1.weight"]
    out["df_dec.df_convp.pw"] = sd["df_dec.df_convp.2.weight"][:, :, 0, 0] * s[:, None]
    out["df_dec.df_convp.b"] = b
    glinear("df_dec.df_gru.lin_in", "df_dec.df_gru.linear_in.0.weight")
    gru("df_dec.df_gru.gru", "df_dec.df_gru.gru.", 2)
    glinear("df_dec.df_skip", "df_dec.df_skip.weight")
    glinear("df_dec.df_out", "df_dec.df_out.0.weight")

    # ERB band widths, from the forward filterbank (each band is a run of ones).
    fb = sd["erb_fb"]
    out["erb_widths"] = (fb > 0).sum(axis=0).astype(np.float64)

    with open(dst, "wb") as f:
        f.write(b"VDF3" + struct.pack("<II", 1, len(out)))
        for name, arr in out.items():
            n = name.encode()
            f.write(struct.pack("<H", len(n)) + n + struct.pack("<B", arr.ndim))
            f.write(struct.pack(f"<{arr.ndim}I", *arr.shape))
            f.write(np.ascontiguousarray(arr, dtype="<f2").tobytes())
    print(f"wrote {dst}: {len(out)} tensors, {sum(a.size for a in out.values())} values")


if __name__ == "__main__":
    main(*sys.argv[1:3])
