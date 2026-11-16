#!/usr/bin/env python3
"""Vygeneruje vsechny zvuky hry (motor, pneumatiky, nitro, vitr, narazy) do assets/sounds.

Zvuky jsou cele synteticke (zadne nahravky), takze jsou vlastni praci projektu.
Motor pocita tools/motor_synth.py (model vyfukovych pulsu, potrubi a tlumice).
Spusteni:  python3 tools/generuj_zvuky.py
Potrebuje: numpy, scipy
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, sosfiltfilt

import motor_synth

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
rng = np.random.default_rng(2427)


def save(name, x, peak=0.9):
    """peak=None: hlasitost se nemeni (smycky motoru maji uz srovnanou stredni uroven)."""
    x = np.asarray(x, dtype=np.float64)
    if peak is not None:
        x = x / (np.max(np.abs(x)) + 1e-9) * peak
    wavfile.write(os.path.join(OUT, name), SR, (x * 32767).astype(np.int16))
    print(f"{name:22s} {len(x) / SR:5.2f} s  rms={np.sqrt(np.mean(x ** 2)):.3f}")


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


def loopable_noise(seconds, shaper):
    """Sum, ktery jde plynule opakovat: vygeneruje se delsi a konec se prolne do zacatku."""
    n = int(seconds * SR)
    fade = int(0.25 * SR)
    raw = shaper(rng.standard_normal(n + fade + SR))[SR:]  # prvni vterinu zahodit (nabeh filtru)
    out = raw[:n].copy()
    w = np.linspace(0.0, 1.0, fade)
    out[:fade] = raw[:fade] * w + raw[n:n + fade] * (1.0 - w)
    return out


def impact(seconds, thud_hz, crunch):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * thud_hz * t * (1.0 - 0.4 * t / seconds)) * np.exp(-t * 14.0)
    noise = rng.standard_normal(n)
    crack = bandpass(noise, 800, 6000) * np.exp(-t * 22.0)
    body = bandpass(noise, 150, 900) * np.exp(-t * 9.0)
    rattle = bandpass(rng.standard_normal(n), 2500, 7000) * np.exp(-t * 6.0) * (rng.random(n) > 0.985).astype(float)
    rattle = lowpass(rattle * 30.0, 6000)
    return thud * 1.0 + crack * crunch + body * 0.8 + rattle * crunch * 0.6


def main():
    os.makedirs(OUT, exist_ok=True)
    # --- Motory: pro kazdy typ nekolik smycek v ruznych otackach, zvlast pod plynem a bez plynu.
    #     Hra mezi sousednimi smyckami prolina a jen malo meni vysku tonu (zni to prirozeneji).
    for old in os.listdir(OUT):
        if old.startswith("motor_") and old.endswith(".wav"):
            os.remove(os.path.join(OUT, old))
    for kind, spec in motor_synth.ENGINES.items():
        for rpm in spec["rpm_on"]:
            save(f"motor_{kind}_plyn_{rpm}.wav", motor_synth.engine_loop(kind, rpm, 1.0), None)
        for rpm in spec["rpm_off"]:
            save(f"motor_{kind}_volno_{rpm}.wav", motor_synth.engine_loop(kind, rpm, 0.0), None)
    save("turbo_hvizd.wav", motor_synth.turbo_whistle(), 0.5)

    # --- Kvileni pneumatik: uzkopasmovy sum s kolisanim ---
    def squeal(x):
        a = bandpass(x, 900, 1500, 3)
        b = bandpass(x, 1900, 2600, 3) * 0.5
        n = len(x)
        wob = 0.75 + 0.25 * np.sin(2 * np.pi * 5.3 * np.arange(n) / SR) * np.sin(2 * np.pi * 0.7 * np.arange(n) / SR)
        return (a + b) * wob
    save("pneumatiky.wav", loopable_noise(2.0, squeal))

    # --- Nitro: syceni plynu + hluboke duneni ---
    def nitro(x):
        n = len(x)
        hiss = highpass(x, 2500) * 0.6
        roar = bandpass(x, 90, 500) * 1.6
        return (hiss + roar) * (0.85 + 0.15 * np.sin(2 * np.pi * 9.0 * np.arange(n) / SR))
    save("nitro.wav", loopable_noise(1.5, nitro))

    # --- Vitr v rychlosti ---
    save("vitr.wav", loopable_noise(2.5, lambda x: lowpass(x, 700) + 0.3 * bandpass(x, 700, 2500)))

    # --- Narazy ---
    save("naraz_1.wav", impact(0.6, 70, 0.9))
    save("naraz_2.wav", impact(0.5, 95, 1.3))
    save("naraz_3.wav", impact(0.8, 55, 0.7))
    # Skrabani o zed
    save("skrabani.wav", loopable_noise(1.2, lambda x: bandpass(x, 1200, 5000) * (0.6 + 0.4 * (np.abs(lowpass(x, 30)) * 20.0).clip(0, 1))))

    # --- Preraeni (kratke "tuknuti") a odfuk turba ---
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    save("razeni.wav", (np.sin(2 * np.pi * 140 * t) + 0.5 * bandpass(rng.standard_normal(n), 500, 3000)) * np.exp(-t * 45.0), 0.7)
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    blow = bandpass(rng.standard_normal(n), 1500, 7000) * np.exp(-t * 7.0) * (1.0 - np.exp(-t * 120.0))
    blow *= 0.7 + 0.3 * np.sin(2 * np.pi * 38.0 * t)          # "trepotani" odfukoveho ventilu
    save("turbo_odfuk.wav", blow, 0.8)


if __name__ == "__main__":
    main()
