#!/usr/bin/env python3
"""Turn MediaPipe's selfie_segmenter.tflite into the compact graph that
src/segmenter.rs runs (no inference runtime involved).

Usage: export_weights.py selfie_segmenter.tflite selfie_segmenter.bin

Needs the `tflite` (flatbuffer schema) and `numpy` packages. The format, all
little endian:

  b"VSEG" u32 version=1 u32 tensor_count u32 op_count
  per tensor: u32 h, w, c                (activations only; NHWC, batch 1)
  per op:     u32 kind, then its fields (see KINDS), then for ops with
              weights: u32 count + count f16 values, the same for the bias

Tensor 0 is the 256x256x3 input, the last op writes the output (256x256x1).
"""
import struct
import sys

import numpy as np
import tflite

CONV, DWCONV, HSWISH, RELU, SIGMOID, GAP, MUL_C, ADD, RESIZE2X, TCONV2X = range(1, 11)


def load(path):
    buf = open(path, "rb").read()
    model = tflite.Model.GetRootAsModel(buf, 0)
    g = model.Subgraphs(0)
    names = {v: k for k, v in tflite.BuiltinOperator.__dict__.items() if not k.startswith("_")}

    def raw(t):  # constant data of tensor t
        b = model.Buffers(g.Tensors(t).Buffer())
        return b.DataAsNumpy().tobytes() if b.DataLength() else None

    def shape(t):
        return tuple(int(x) for x in g.Tensors(t).ShapeAsNumpy())

    consts = {}  # dequantized tensor id -> f16 array (original fp16 values)
    ops = []
    for i in range(g.OperatorsLength()):
        op = g.Operators(i)
        oc = model.OperatorCodes(op.OpcodeIndex())
        code = max(oc.BuiltinCode(), oc.DeprecatedBuiltinCode())
        name = "CUSTOM:" + oc.CustomCode().decode() if code == 32 else names.get(code, str(code))
        ins = [op.Inputs(j) for j in range(op.InputsLength())]
        outs = [op.Outputs(j) for j in range(op.OutputsLength())]
        if name == "DEQUANTIZE":
            assert g.Tensors(ins[0]).Type() == 1  # FLOAT16
            consts[outs[0]] = np.frombuffer(raw(ins[0]), dtype="<f2").reshape(shape(ins[0]))
            continue
        ops.append((name, ins, outs, op))
    return g, model, consts, ops, shape


def export(src, dst):
    g, model, consts, ops, shape = load(src)
    ids = {}  # tflite activation tensor -> our index
    shapes = []

    def tid(t):
        if t not in ids:
            s = shape(t)
            assert len(s) == 4 and s[0] == 1, s
            ids[t] = len(shapes)
            shapes.append(s[1:])
        return ids[t]

    tid(g.Inputs(0))
    out = []
    for name, ins, outs, op in ops:
        o = op.BuiltinOptions()
        if name == "CONV_2D":
            x = tflite.Conv2DOptions()
            x.Init(o.Bytes, o.Pos)
            assert x.FusedActivationFunction() == 0 and x.DilationWFactor() == 1
            assert x.StrideW() == x.StrideH()
            w, b = consts[ins[1]], consts[ins[2]]
            cout, kh, kw, cin = w.shape
            same = x.Padding() == 0
            # 1x1 convs are padding-agnostic; 3x3 only appears with stride 2 SAME.
            out.append((CONV, [tid(ins[0]), tid(outs[0]), kh, cin, cout, x.StrideW(), int(same)], [w, b]))
        elif name == "DEPTHWISE_CONV_2D":
            x = tflite.DepthwiseConv2DOptions()
            x.Init(o.Bytes, o.Pos)
            assert x.FusedActivationFunction() == 0 and x.DepthMultiplier() == 1 and x.Padding() == 0
            w, b = consts[ins[1]], consts[ins[2]]
            _, k, _, c = w.shape
            out.append((DWCONV, [tid(ins[0]), tid(outs[0]), k, c, x.StrideW()], [w, b]))
        elif name in ("HARD_SWISH", "RELU", "LOGISTIC"):
            kind = {"HARD_SWISH": HSWISH, "RELU": RELU, "LOGISTIC": SIGMOID}[name]
            out.append((kind, [tid(ins[0]), tid(outs[0])], []))
        elif name == "AVERAGE_POOL_2D":
            assert shape(outs[0])[1:3] == (1, 1)
            out.append((GAP, [tid(ins[0]), tid(outs[0])], []))
        elif name in ("MUL", "ADD"):
            a, b = shape(ins[0]), shape(ins[1])
            if name == "MUL":
                assert b[1:3] == (1, 1), b  # squeeze-excite scale
                out.append((MUL_C, [tid(ins[0]), tid(ins[1]), tid(outs[0])], []))
            else:
                assert a == b
                out.append((ADD, [tid(ins[0]), tid(ins[1]), tid(outs[0])], []))
        elif name == "RESIZE_BILINEAR":
            x = tflite.ResizeBilinearOptions()
            x.Init(o.Bytes, o.Pos)
            assert x.HalfPixelCenters() and not x.AlignCorners()
            i_s, o_s = shape(ins[0]), shape(outs[0])
            assert o_s[1] == 2 * i_s[1] and o_s[2] == 2 * i_s[2]
            out.append((RESIZE2X, [tid(ins[0]), tid(outs[0])], []))
        elif name == "CUSTOM:Convolution2DTransposeBias":
            opts = list(op.CustomOptionsAsNumpy())
            assert opts[:12] == [1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0], opts  # VALID, stride 2
            w, b = consts[ins[1]], consts[ins[2]]
            cout, kh, kw, cin = w.shape
            assert (kh, kw) == (2, 2)
            out.append((TCONV2X, [tid(ins[0]), tid(outs[0]), cin, cout], [w, b]))
        else:
            raise SystemExit("unsupported op " + name)
    assert ids[g.Outputs(0)] == out[-1][1][1]

    with open(dst, "wb") as f:
        f.write(b"VSEG" + struct.pack("<III", 1, len(shapes), len(out)))
        for s in shapes:
            f.write(struct.pack("<III", *s))
        for kind, fields, weights in out:
            f.write(struct.pack("<I", kind) + struct.pack("<%dI" % len(fields), *fields))
            for a in weights:
                a = np.ascontiguousarray(a, dtype="<f2").ravel()
                f.write(struct.pack("<I", a.size) + a.tobytes())
    return shapes, out


if __name__ == "__main__":
    export(sys.argv[1], sys.argv[2])
