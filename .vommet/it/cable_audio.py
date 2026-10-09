"""VB-CABLE helper for the Windows capture test (#78).

    python cable_audio.py check <wav>   # environment control: play the wav to
                                        # the cable's playback side while
                                        # recording "CABLE Output"; print
                                        # devices and the level heard
    python cable_audio.py loop <wav>    # play the wav into the cable forever

Lines start with "CAPTURE env" so the harness can surface them. Needs
sounddevice and numpy (pip).
"""
import sys
import wave

import numpy as np
import sounddevice as sd


def log(line):
    print(f"CAPTURE env {line}", flush=True)


def find(names, kind):
    """First device (any host API) whose name contains one of [names] and
    has [kind] channels. The cable's playback side is "CABLE Input" in
    newer VB-CABLE packs and "Speakers (VB-Audio Virtual Cable)" in Pack43."""
    for i, d in enumerate(sd.query_devices()):
        if d[f"max_{kind}_channels"] > 0 and any(
                n.lower() in d["name"].lower() for n in names):
            return i
    return None


def load(path):
    with wave.open(path) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
        signal = data.astype(np.float32) / 32768.0
        # Normalize to -1 dBFS peak: synthesized speech comes out quiet.
        peak = float(np.max(np.abs(signal))) or 1.0
        return signal * (0.89 / peak), w.getframerate()


mode, path = sys.argv[1], sys.argv[2]
signal, rate = load(path)
out_dev = find(["CABLE Input", "VB-Audio Virtual Cabl"], "output")
in_dev = find(["CABLE Output"], "input")

if mode == "check":
    default_in, default_out = sd.default.device
    for i, d in enumerate(sd.query_devices()):
        api = sd.query_hostapis(d["hostapi"])["name"]
        log(f"device {i} [{api}] in={d['max_input_channels']} "
            f"out={d['max_output_channels']} {d['name']}")
    log(f"default in={default_in} out={default_out}; "
        f"cable in={in_dev} out={out_dev}")
    if in_dev is None or out_dev is None:
        log("FAIL no CABLE devices")
        sys.exit(1)
    rec = sd.playrec(signal[: rate * 3], samplerate=rate, channels=1,
                     input_mapping=[1], output_mapping=[1],
                     device=(in_dev, out_dev), blocking=True)
    rms = float(np.sqrt(np.mean(np.square(rec[rate // 2:]))))
    log(f"loopback rms={rms:.4f} (signal rms={float(np.sqrt(np.mean(np.square(signal)))):.4f})")
elif mode == "loop":
    if out_dev is None:
        log("FAIL no cable playback device")
        sys.exit(1)
    while True:
        sd.play(signal, samplerate=rate, device=out_dev, blocking=True)
