"""Generate the original, dependency-free PCM WAV effects in assets/weapons/."""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
DEST = Path(__file__).resolve().parents[1] / "assets" / "weapons"


def envelope(t, start, attack, decay):
    age = t - start
    if age < 0:
        return 0.0
    return min(age / attack, 1.0) * math.exp(-age / decay)


def render(name, duration, seed, generator):
    rng = random.Random(seed)
    samples = []
    low = 0.0
    high = 0.0
    for index in range(int(duration * RATE)):
        t = index / RATE
        noise = rng.uniform(-1.0, 1.0)
        low += 0.075 * (noise - low)
        high += 0.55 * (noise - high)
        samples.append(generator(t, noise, low, noise - high))
    peak = max(abs(value) for value in samples)
    scale = 0.82 / max(peak, 0.001)
    path = DEST / name
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", int(math.tanh(value * scale) * 32767)) for value in samples))
    print(f"{path.name}: {duration:.2f}s")


def shot(is_carbine):
    def sample(t, noise, low, high):
        attack = envelope(t, 0.002, 0.001, 0.017 if is_carbine else 0.022)
        body = envelope(t, 0.007, 0.007, 0.085 if is_carbine else 0.105)
        tail = envelope(t, 0.05, 0.02, 0.17)
        echo = envelope(t, 0.16, 0.01, 0.05)
        freq = (105 if is_carbine else 82) * math.exp(-t * 11) + 45
        bass = math.sin(2 * math.pi * freq * t) * body
        mechanical = envelope(t, 0.065, 0.001, 0.023) * high
        return 0.9 * attack * noise + 0.88 * bass + 0.27 * tail * low + 0.13 * echo * noise + 0.21 * mechanical

    return sample


def clicks(t, noise, low, high, events):
    result = 0.0
    for start, strength, pitch in events:
        pulse = envelope(t, start, 0.0015, 0.014)
        age = max(0, t - start)
        result += strength * pulse * (0.72 * high + 0.4 * math.sin(2 * math.pi * pitch * age))
    return result


def reload(t, noise, low, high):
    events = [(0.04, 0.7, 1150), (0.18, 0.5, 880), (0.42, 0.65, 760), (0.64, 1, 510), (0.86, 0.75, 1200), (0.98, 0.8, 720)]
    scrape = envelope(t, 0.19, 0.05, 0.15) + envelope(t, 0.71, 0.03, 0.11)
    return clicks(t, noise, low, high, events) + 0.11 * scrape * (high + low)


def dry_fire(t, noise, low, high):
    return clicks(t, noise, low, high, [(0.015, 0.9, 950), (0.068, 0.3, 580)])


def equip(t, noise, low, high):
    swish = envelope(t, 0.015, 0.04, 0.10)
    return 0.17 * swish * (high + low) + clicks(t, noise, low, high, [(0.16, 0.45, 450), (0.22, 0.6, 900)])


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    render("carbine_fire.wav", 0.55, 186, shot(True))
    render("pistol_fire.wav", 0.58, 223, shot(False))
    render("reload.wav", 1.15, 316, reload)
    render("dry_fire.wav", 0.24, 481, dry_fire)
    render("equip.wav", 0.36, 529, equip)
