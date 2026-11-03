# DeepFilterNet3 weights

`dfn3.bin` holds the weights of [DeepFilterNet3](https://github.com/Rikorose/DeepFilterNet)
by Hendrik Schröter and contributors, licensed MIT OR Apache-2.0 (`LICENSE-MIT`,
`LICENSE-APACHE`). `src/voice_filter/dfn3.rs` runs the network and compiles the file
into the library.

Source: `models/DeepFilterNet3.zip` at tag v0.5.6, `checkpoints/model_120.ckpt.best`
(sha256 `23b92884f63ccf54bb026014604625ab231657b6480df65db4095c4c171e6003`), converted
with `export_weights.py` (batch norms folded, float16).

`testdata/` is one second of speech from the Valentini/VCTK noisy speech set (CC BY 4.0,
University of Edinburgh) with synthetic typing clicks and fan-like hum mixed in at 0 dB,
plus the output of a NumPy reference implementation of the streaming network, which was
itself checked against grazder's torchDF ONNX export (124 dB SNR over 9 s).
