#!/usr/bin/env python3
"""Original title-screen audio for Isles of Mythos, dedicated to CC0-1.0.

No third-party sample is embedded. The cannon hit is a layered low sine thump,
a falling pitch, filtered noise, and a noise tail. The music bed is an 8-bar
D-dorian hornpipe at 120 BPM (bass, melody, harmony, kick, snare, hat) rendered
twice so the short delay tail matches the loop point.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SR_BOOM = 44100
SR_BED = 22050
BPM = 120


def _write_wav(path: Path, samples: list[float], sample_rate: int) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    if peak > 1.0:
        samples = [s / peak * 0.89 for s in samples]
    if max(abs(s) for s in samples) < 0.2:
        raise SystemExit(f"{path.name} is silent")
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767.0))))
            for s in samples
        )
        handle.writeframes(frames)


def _lowpass(values: list[float], cutoff: float, sample_rate: int) -> list[float]:
    dt = 1.0 / sample_rate
    alpha = dt / (dt + 1.0 / (2.0 * math.pi * cutoff))
    out: list[float] = []
    state = 0.0
    for sample in values:
        state += alpha * (sample - state)
        out.append(state)
    return out


def _synth_boom() -> list[float]:
    count = int(SR_BOOM * 1.75)
    rng = random.Random(1701)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]
    body = _lowpass(noise, 420.0, SR_BOOM)
    crack = _lowpass(noise, 2400.0, SR_BOOM)
    tail = _lowpass(noise, 180.0, SR_BOOM)
    samples: list[float] = []
    phase_drop = 0.0
    phase_sub = 0.0
    for index in range(count):
        t = index / SR_BOOM
        freq = 96.0 * math.exp(-t * 3.4) + 32.0
        phase_drop += 2.0 * math.pi * freq / SR_BOOM
        phase_sub += 2.0 * math.pi * 46.0 / SR_BOOM
        thump = math.sin(phase_drop) * math.exp(-t * 3.6)
        sub = math.sin(phase_sub) * math.exp(-t * 1.7)
        # Second layer, 28 ms later, an octave-ish lower, so the hit stacks.
        delayed = 0.0
        delay = int(0.028 * SR_BOOM)
        if index >= delay:
            td = (index - delay) / SR_BOOM
            delayed = math.sin(phase_sub * 0.5) * math.exp(-td * 2.2) * 0.55
        air = body[index] * math.exp(-t * 7.5)
        snap = crack[index] * math.exp(-t * 28.0)
        wash = tail[index] * math.exp(-t * 2.1) * 0.55
        samples.append(thump * 0.62 + sub * 0.48 + delayed + air * 0.42 + snap * 0.28 + wash)
    return samples


def _midi(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def _env(time: float, duration: float) -> float:
    attack = 0.012
    release = 0.045
    if time < 0.0 or time >= duration:
        return 0.0
    if time < attack:
        return time / attack
    if time > duration - release:
        return max(0.0, (duration - time) / release)
    return 1.0


def _synth_bed() -> list[float]:
    beat = int(SR_BED * 60 / BPM)  # 11025 samples, exact
    beats = 32  # 8 bars
    count = beat * beats
    rng = random.Random(1407)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count * 2)]
    hat_noise = _lowpass(noise, 5000.0, SR_BED)
    snare_noise = _lowpass(noise, 1800.0, SR_BED)
    # D-dorian hornpipe, one note per beat. Two phrases of the sailor shape.
    melody = [
        62, 65, 69, 69, 67, 65, 64, 62,
        65, 67, 69, 69, 67, 65, 64, 62,
        69, 69, 71, 69, 67, 65, 64, 62,
        62, 65, 69, 65, 64, 65, 64, 62,
    ]
    harmony = [note - 3 for note in melody]
    bass_roots = [38, 38, 36, 38, 41, 36, 38, 38]
    samples = [0.0] * (count * 2)
    for pass_index in range(2):
        base = pass_index * count
        for index in range(count):
            t = index / SR_BED
            beat_index = index // beat
            into = (index % beat) / SR_BED
            bar = beat_index // 4
            mix = 0.0
            mel_env = _env(into, 0.46)
            vibrato = 1.0 + 0.008 * math.sin(2.0 * math.pi * 5.2 * t)
            mel = _midi(melody[beat_index]) * vibrato
            harm = _midi(harmony[beat_index])
            for partial in range(1, 6):
                mix += math.sin(2.0 * math.pi * mel * partial * t) / partial * mel_env * 0.22
                mix += math.sin(2.0 * math.pi * harm * partial * t) / partial * mel_env * 0.08
            root = bass_roots[bar]
            if beat_index % 2 == 0:
                bass_env = _env(into, 0.42)
                mix += math.sin(2.0 * math.pi * _midi(root) * t) * bass_env * 0.42
                mix += math.sin(2.0 * math.pi * _midi(root + 12) * t) * bass_env * 0.12
            if into < 0.09:
                kick_t = into
                kick_f = 150.0 * math.exp(-kick_t * 28.0) + 48.0
                mix += math.sin(2.0 * math.pi * kick_f * kick_t) * math.exp(-kick_t * 18.0) * 0.55
            if beat_index % 2 == 1 and into < 0.14:
                mix += snare_noise[base + index] * math.exp(-into * 16.0) * 0.28
            if into < 0.025 or (0.22 < into < 0.245):
                mix += hat_noise[base + index] * 0.07
            samples[base + index] += mix
    # Periodic delay from the second pass only, fed by the already-rendered buffer.
    delay = int(0.16 * SR_BED)
    looped = samples[count:]
    wet: list[float] = []
    for index, dry in enumerate(looped):
        echo = looped[index - delay] if index >= delay else looped[index - delay + count]
        wet.append(dry * 0.86 + echo * 0.16)
    return wet


def main() -> None:
    _write_wav(ROOT / "cannon_boom.wav", _synth_boom(), SR_BOOM)
    _write_wav(ROOT / "shanty_bed.wav", _synth_bed(), SR_BED)
    print("wrote cannon_boom.wav and shanty_bed.wav")


if __name__ == "__main__":
    main()
