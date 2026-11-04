"""Write a speech-like test signal for the capture test (#78): a warbling
harmonic voice (pitch gliding 120-240 Hz, 4 Hz syllable envelope) peaking near
-6 dBFS, 48 kHz mono 16-bit. A steady tone would be removed by WebRTC's noise
suppression, which the app enables on the microphone.

    python make_signal.py out.wav [seconds]
"""
import math
import struct
import sys
import wave

path = sys.argv[1]
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 10
rate = 48000
frames = bytearray()
phase = 0.0
for n in range(int(rate * seconds)):
    t = n / rate
    f0 = 180 + 60 * math.sin(2 * math.pi * 0.7 * t)
    phase += 2 * math.pi * f0 / rate
    voice = sum(math.sin(k * phase) / k for k in range(1, 8))
    envelope = max(0.0, math.sin(2 * math.pi * 4 * t)) ** 0.5
    sample = 0.5 * 0.55 * voice * envelope
    frames += struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767))
with wave.open(path, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(bytes(frames))
