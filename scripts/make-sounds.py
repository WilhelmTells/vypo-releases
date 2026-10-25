#!/usr/bin/env python3 -I
"""Synthesizes vypo's start/stop sounds into Resources/Sounds (44.1 kHz mono 16-bit WAV).

Each sound is a short sine blip: a quick attack, a body of a few tens of milliseconds and an exponential
decay, with a faint second harmonic for warmth. Start and stop sounds of a pair differ in pitch or
direction, so you can tell them apart without looking. Requires numpy. Run from the repository root:

    python3 -I scripts/make-sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
PEAK_DB = -20.0
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")


def tone(freq, body, decay, harmonics=(), attack=0.003, delay=0.0, glide=0.0):
    """A sine blip. `glide` bends the pitch by that ratio over attack and body; `delay` starts it later."""
    n = int((delay + attack + body + decay * 6) * SR)
    t = np.arange(n) / SR
    tt = np.clip(t - delay, 0, None)
    f = freq * (1 + glide * np.clip(tt / (attack + body), 0, 1))
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = np.sin(phase)
    for mult, db in harmonics:
        sig += 10 ** (db / 20) * np.sin(phase * mult)
    env = np.where(tt < attack, tt / attack, np.where(tt < attack + body, 1.0, np.exp(-(tt - attack - body) / decay)))
    env[t < delay] = 0
    return sig * env


def mix(*parts):
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[: len(p)] += p
    return out


def write(path, sig):
    sig = sig / np.abs(sig).max() * 10 ** (PEAK_DB / 20)
    fade = int(0.004 * SR)
    sig[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())


WARM = [(2, -26)]
BELL = [(2.76, -22), (5.4, -32)]
SOUNDS = {
    "glide-short": (tone(440, 0.03, 0.02, WARM, glide=0.4), tone(616, 0.03, 0.024, WARM, glide=-0.4)),
    "glide": (tone(440, 0.05, 0.025, WARM, glide=0.25), tone(550, 0.05, 0.03, WARM, glide=-0.25)),
    "glide-low": (tone(392, 0.05, 0.028, WARM, glide=0.25), tone(490, 0.05, 0.032, WARM, glide=-0.25)),
    "soft": (tone(523, 0.035, 0.025, WARM), tone(349, 0.045, 0.03, WARM)),
    "duo": (mix(tone(392, 0.025, 0.02, WARM), tone(523, 0.03, 0.03, WARM, delay=0.06)),
            mix(tone(523, 0.025, 0.02, WARM), tone(392, 0.03, 0.03, WARM, delay=0.06))),
    "deep": (tone(330, 0.04, 0.03, [(2, -20)]), tone(220, 0.05, 0.035, [(2, -20)])),
    "bell": (tone(659, 0.02, 0.04, BELL), tone(494, 0.02, 0.045, BELL)),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (start, stop) in SOUNDS.items():
        write(os.path.join(OUT, f"{name}-start.wav"), start)
        write(os.path.join(OUT, f"{name}-stop.wav"), stop)
    print("Wrote", len(SOUNDS) * 2, "files to Resources/Sounds")
