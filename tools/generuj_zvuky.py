#!/usr/bin/env python3
"""Vygeneruje vsechny zvuky hry (motor, pneumatiky, nitro, vitr, narazy) do assets/sounds.

Zvuky jsou cele synteticke (zadne nahravky), takze jsou vlastni praci projektu.
Spusteni:  python3 tools/generuj_zvuky.py
Potrebuje: numpy, scipy
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, sosfiltfilt

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
rng = np.random.default_rng(2427)


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
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


def engine_loop(firing_hz, cylinders, uneven, brightness, cycles=12):
    """Smycka motoru. Jeden cyklus motoru = `cylinders` zazehu; kazdy zazeh je kratky tlumeny puls.

    firing_hz  - frekvence zazehu (4valec pri 3000 ot/min = 100 Hz)
    uneven     - nepravidelnost zazehu (V8 "bublani")
    brightness - kolik vyssich tonu (vyssi otacky = ostrejsi zvuk)
    """
    n = int(round(SR / firing_hz * cylinders * cycles))
    period = n / (cylinders * cycles)            # vzorku na jeden zazeh (upraveno, aby smycka presne navazovala)
    firing_hz = SR / period
    t = np.arange(n)
    x = np.zeros(n)
    offsets = np.linspace(0.0, 1.0, cylinders, endpoint=False)
    offsets = offsets + uneven * np.array([0.0, 0.35, -0.2, 0.3, -0.1, 0.25, -0.3, 0.1][:cylinders]) / cylinders
    amps = 1.0 + 0.25 * np.array([0.0, -0.6, 0.4, -0.3, 0.7, -0.5, 0.2, -0.8][:cylinders])
    cycle_len = period * cylinders
    for c in range(cylinders):
        phase = (t / cycle_len - offsets[c]) % 1.0            # 0..1 v ramci cyklu motoru
        tt = phase * cycle_len / SR                           # cas od zazehu (s)
        # vyfukovy puls: rychly nabeh, tlumene doznivani s rezonanci vyfuku
        pulse = np.exp(-tt * firing_hz * 2.2) * np.sin(2 * np.pi * firing_hz * 1.0 * tt + 0.3)
        pulse += 0.5 * np.exp(-tt * firing_hz * 3.0) * np.sin(2 * np.pi * firing_hz * 2.02 * tt)
        pulse += brightness * 0.35 * np.exp(-tt * firing_hz * 4.0) * np.sin(2 * np.pi * firing_hz * 3.97 * tt)
        pulse += brightness * 0.2 * np.exp(-tt * firing_hz * 5.0) * np.sin(2 * np.pi * firing_hz * 6.1 * tt)
        x += amps[c] * pulse
    # mechanicky sum (sani, rozvody) modulovany zazehy
    noise = loopable_noise(n / SR, lambda z: bandpass(z, 600, 3500))[:n]
    mod = 0.6 + 0.4 * np.sin(2 * np.pi * (t / period))
    x += noise * mod * 0.10 * (0.5 + brightness) * np.max(np.abs(x)) * 0.5
    x = lowpass(np.tile(x, 3), 1800 + 5000 * brightness)       # trikrat za sebou = filtry jsou ustalene, smycka sedi
    x = highpass(x, 25)[2 * n:]                                 # bez stejnosmerne slozky
    return np.tanh(x / np.max(np.abs(x)) * 1.6)                 # lehke zkresleni = plnejsi zvuk


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
    # --- Motory: dve vrstvy (nizke a vysoke otacky), hra mezi nimi prolina a meni vysku tonu ---
    # Radovy ctyrvalec (Octavia, Silvia): referencni otacky 2500 a 5500 ot/min
    save("motor_r4_nizky.wav", engine_loop(2500 / 60 * 2, 4, 0.0, 0.25))
    save("motor_r4_vysoky.wav", engine_loop(5500 / 60 * 2, 4, 0.0, 0.9))
    # V8 (Mustang): nepravidelne zazehy = bublavy zvuk; reference 2000 a 4500 ot/min
    save("motor_v8_nizky.wav", engine_loop(2000 / 60 * 4, 8, 1.0, 0.2))
    save("motor_v8_vysoky.wav", engine_loop(4500 / 60 * 4, 8, 0.8, 0.8))

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
