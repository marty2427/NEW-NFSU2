#!/usr/bin/env python3
"""Fyzikalne motivovany model zvuku motoru (bez nahravek).

Jak to funguje (zjednodusene jako ve skutecnem aute):
  1. kazdy valec pri vyfuku vypusti kratky tlakovy puls (kazdy trochu jinak silny a jinak nacasovany),
  2. pulsy projdou svody a vyfukovym potrubim (rezonance trubky = "barva" zvuku),
  3. pri plnem plynu se zvuk mirne zkresli (ostrejsi, agresivnejsi), tlumic ubere vysky,
  4. prida se sum sani, vyfuku a mechaniky, ktery pulzuje v rytmu motoru.
Vse se pocita "do kruhu" (ve frekvencni oblasti), takze smycka navazuje presne a bez lupnuti.
"""
import numpy as np

SR = 44100

# Typy motoru. bank = poradi zazehu jako zlomky cyklu (2 otacky klikovky) pro kazdou vetev vyfuku.
ENGINES = {
    # Octavia RS 2.0 TSI: turbo a tlumice = hlubsi, hladsi, kultivovany zvuk
    "r4": dict(
        attack=0.00028, spread=0.1, jitter=(0.03, 0.1, 1.4), banks=[[0.0, 0.25, 0.5, 0.75]], cyl_var=0.035, time_var=0.003, header_m=0.38, pipe_m=[2.9],
        muffler_hz=560.0, bypass=0.18, drive=1.2, formants=[(150, 2.4, 1.6), (420, 1.8, 2.5), (1100, 1.5, 3.5), (2600, 0.9, 4.0)],
        intake=0.30, hiss=0.10, mech=0.06, pops=0.0, rpm_on=[1000, 2200, 3600, 5000, 6600], rpm_off=[900, 3200, 6000]),
    # Silvia SR20DET s primym vyfukem: chrapla, hlasita, "tunerska"
    "r4s": dict(
        attack=0.00028, spread=0.1, jitter=(0.03, 0.1, 1.4), banks=[[0.0, 0.25, 0.5, 0.75]], cyl_var=0.07, time_var=0.004, header_m=0.55, pipe_m=[2.3],
        muffler_hz=1100.0, bypass=0.3, drive=2.0, formants=[(190, 2.4, 1.8), (520, 2.2, 2.5), (1500, 2.0, 3.5), (3400, 1.0, 4.0)],
        intake=0.34, hiss=0.11, mech=0.07, pops=0.10, rpm_on=[1100, 2400, 3900, 5500, 7100], rpm_off=[1000, 3500, 6500]),
    # Mustang 5.0 V8: dve vetve vyfuku s nepravidelnymi zazehy = typicke "bublani"
    "v8": dict(
        attack=0.00024, spread=0.15, jitter=(0.04, 0.14, 1.8),
        banks=[[0.0, 0.25, 0.625, 0.875], [0.125, 0.375, 0.5, 0.75]], cyl_var=0.08, time_var=0.005, header_m=0.6, pipe_m=[2.6, 2.78],
        muffler_hz=800.0, bypass=0.26, drive=1.8, formants=[(140, 2.2, 1.8), (430, 1.8, 2.5), (1150, 1.8, 3.5), (2500, 1.2, 4.0)],
        intake=0.30, hiss=0.12, mech=0.05, pops=0.05, rpm_on=[800, 1900, 3100, 4500, 6000], rpm_off=[750, 2800, 5500]),
    # BMW M3 S54: radovy sestivalec bez turba, toci 8000 - kovove jeci, hlasite sani
    "r6": dict(
        banks=[[0.0, 1 / 3, 2 / 3], [1 / 6, 0.5, 5 / 6]], cyl_var=0.06, time_var=0.003, header_m=0.45, pipe_m=[2.4, 2.55],
        muffler_hz=1300.0, bypass=0.3, drive=1.6, formants=[(380, 1.8, 2.5), (1050, 2.4, 3.5), (2600, 2.2, 4.0), (4200, 1.2, 4.0)],
        intake=0.42, hiss=0.08, mech=0.08, pops=0.03, rpm_on=[1000, 2500, 4200, 6000, 7900], rpm_off=[900, 3800, 7200]),
    # Supra 2JZ-GTE: sestivalec s turbem - hladky, hlubsi, "huci"
    "r6t": dict(
        attack=0.00022, spread=0.15, jitter=(0.04, 0.12, 1.6),
        banks=[[0.0, 1 / 3, 2 / 3], [1 / 6, 0.5, 5 / 6]], cyl_var=0.05, time_var=0.003, header_m=0.5, pipe_m=[2.7, 2.85],
        muffler_hz=800.0, bypass=0.22, drive=1.4, formants=[(220, 1.8, 2.2), (620, 1.8, 3.0), (1500, 1.6, 3.5), (3000, 1.0, 4.0)],
        intake=0.28, hiss=0.11, mech=0.05, pops=0.06, rpm_on=[1000, 2300, 3700, 5200, 6900], rpm_off=[900, 3300, 6300]),
    # Skyline RB26: sestivalec s turbem a primym vyfukem - chraplavy, ostry
    "r6s": dict(
        attack=0.0002, spread=0.15, jitter=(0.04, 0.12, 1.6),
        banks=[[0.0, 1 / 3, 2 / 3], [1 / 6, 0.5, 5 / 6]], cyl_var=0.06, time_var=0.004, header_m=0.42, pipe_m=[2.2, 2.32],
        muffler_hz=1400.0, bypass=0.34, drive=2.2, formants=[(300, 1.8, 2.5), (860, 2.6, 3.5), (2200, 2.4, 4.0), (3900, 1.4, 4.0)],
        intake=0.3, hiss=0.14, mech=0.07, pops=0.1, rpm_on=[1100, 2500, 4100, 5900, 7900], rpm_off=[1000, 3700, 7200]),
    # Impreza EJ257: plochy ctyrvalec - ruzne dlouhe svody = typicke nepravidelne "bublani"
    "boxer": dict(
        attack=0.00026, spread=0.12, jitter=(0.035, 0.12, 1.5),
        banks=[[0.0, 0.26, 0.5, 0.76]], cyl_var=0.09, time_var=0.004, header_m=0.7, pipe_m=[2.6],
        muffler_hz=620.0, bypass=0.22, drive=1.6, formants=[(140, 2.6, 1.8), (520, 2.0, 3.0), (1300, 1.6, 3.5), (2700, 1.0, 4.0)],
        intake=0.3, hiss=0.12, mech=0.05, pops=0.08, rpm_on=[900, 2100, 3500, 5000, 7400], rpm_off=[850, 3100, 6400]),
    # RX-7 13B: wankel - ostre vyfukove pulsy, bzucivy "brap", vysoke otacky
    "rot": dict(
        attack=0.0002, spread=0.12, jitter=(0.035, 0.12, 1.6),
        banks=[[0.0, 0.25, 0.5, 0.75]], cyl_var=0.04, time_var=0.003, header_m=0.4, pipe_m=[1.9],
        muffler_hz=1800.0, bypass=0.4, drive=2.6, formants=[(420, 2.2, 2.5), (1200, 3.0, 3.5), (2900, 2.6, 4.0)],
        intake=0.38, hiss=0.12, mech=0.03, pops=0.12, rpm_on=[1100, 2700, 4500, 6400, 8400], rpm_off=[1000, 4000, 7600]),
}


def _resonator(f, f0, gain, q):
    """Rezonancni vrchol (pasmova propust 2. radu) - prenos na frekvencich f."""
    s = 1j * f / f0
    return gain * (s / q) / (s * s + s / q + 1.0)


def _comb(f, delay_s, reflect, damp_hz):
    """Trubka: zvuk se odrazi od konce a vraci se (hrebenovy filtr s tlumenim vysek)."""
    loop = reflect * np.exp(-2j * np.pi * f * delay_s) / (1.0 + 1j * f / damp_hz)
    return 1.0 / (1.0 - loop)


def _circular_noise(n, rng, f, lo, hi):
    """Sum v pasmu lo-hi Hz, ktery jde opakovat dokola."""
    spec = np.fft.rfft(rng.standard_normal(n))
    shape = (f / lo) / (1.0 + (f / lo) ** 2) * 2.0 / (1.0 + (f / hi) ** 2)
    x = np.fft.irfft(spec * shape, n)
    return x / (np.std(x) + 1e-12)


def engine_loop(kind, rpm, load, seed=1, seconds=1.1):
    """Vrati smycku zvuku motoru pri danych otackach. load = 1 plny plyn, 0 = bez plynu."""
    e = ENGINES[kind]
    rng = np.random.default_rng(seed * 7919 + int(rpm) + int(load * 13))
    cycle = 120.0 / rpm
    cycles = max(6, int(round(seconds / cycle)))
    n = int(round(cycles * cycle * SR))
    cycle = n / (cycles * SR)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    w = 2.0 * np.pi * f
    x_rel = np.clip((rpm - 800.0) / 6000.0, 0.0, 1.0)

    # --- 1. Vyfukove pulsy ---
    tau_d = np.clip(0.055 * cycle, 0.0007, 0.0040) * (1.0 if load > 0.5 else 1.5)   # doznivani pulsu
    tau_r = e.get("attack", 0.00016) if load > 0.5 else 0.00045                                     # nabeh pulsu (bez plynu mekci)
    pulse = 1.0 / (1.0 / tau_d + 1j * w) - 1.0 / (1.0 / tau_r + 1j * w)
    pulse = pulse / np.max(np.abs(pulse)) * (1j * w / (2.0 * np.pi * 300.0))        # vyzarovani z koncovky
    bank_spec = []
    all_times = []
    cyl_index = 0
    for bank in e["banks"]:
        spec = np.zeros(len(f), dtype=complex)
        for phase in bank:
            cyl_index += 1
            crng = np.random.default_rng(1000 + cyl_index)
            cyl_amp = 1.0 + e["cyl_var"] * crng.uniform(-1.0, 1.0)                 # kazdy valec trochu jiny
            cyl_delay = e["header_m"] * crng.uniform(0.0, e.get("spread", 0.25)) / 480.0            # ruzne dlouhe svody
            for k in range(cycles):
                jit_on, jit_off, t_off = e.get("jitter", (0.05, 0.22, 2.5))
                jit_a = (jit_on if load > 0.5 else jit_off) * rng.standard_normal()
                jit_t = e["time_var"] * (1.0 if load > 0.5 else t_off) * rng.standard_normal()
                amp = cyl_amp * (1.0 + jit_a)
                if load < 0.5:
                    amp *= 0.45
                    if rng.random() < e["pops"] * (0.4 + x_rel):                   # obcasne "prasknuti" do vyfuku
                        amp *= rng.uniform(2.2, 3.6)
                t0 = (k + phase + jit_t) * cycle + cyl_delay
                all_times.append(t0 % (cycles * cycle))
                spec += amp * np.exp(-1j * w * t0)
        bank_spec.append(spec * pulse)

    # --- 2. Svody (kratka trubka), zkresleni pri zatizeni ---
    header = _comb(f, 2.0 * e["header_m"] / 480.0, -0.42, 3500.0)
    banks_t = [np.fft.irfft(s * header, n) for s in bank_spec]
    peak = max(np.max(np.abs(b)) for b in banks_t) + 1e-12
    drive = e["drive"] * (0.55 + 0.6 * x_rel) if load > 0.5 else 0.5
    banks_t = [np.tanh(b / peak * drive) + 0.25 * np.tanh(b / peak * drive * 3.0) * (1.0 if load > 0.5 else 0.2) for b in banks_t]

    # --- 3. Potrubi, tlumic, rezonance karoserie ---
    out = np.zeros(n)
    muffler_hz = e["muffler_hz"] * (1.0 if load > 0.5 else 0.6)
    muffler = 1.0 / (1.0 + 1j * f / muffler_hz) * (1.0 - e["bypass"]) + e["bypass"] / (1.0 + 1j * f / 7000.0)
    body = 1.0 + sum(_resonator(f, f0, g, q) for f0, g, q in e["formants"])
    highpass = (1j * f / 38.0) ** 2 / (1.0 + 1j * f / 38.0) ** 2
    for i, b in enumerate(banks_t):
        mix = b if len(banks_t) == 1 else b + 0.3 * banks_t[1 - i]              # propojeni vetvi (H-pipe)
        pipe = _comb(f, 2.0 * e["pipe_m"][i] / 420.0, -0.5, 1400.0)
        out += np.fft.irfft(np.fft.rfft(mix) * pipe * muffler * body * highpass, n)
    out /= np.sqrt(np.mean(out ** 2)) + 1e-12

    # --- 4. Sumy pulzujici v rytmu motoru ---
    t = np.arange(n) / SR
    env_fire = np.zeros(n)
    width = max(cycle / (len(all_times) / cycles) * 0.35, 0.0006)
    for t0 in all_times:
        d = (t - t0 + 0.5 * n / SR) % (n / SR) - 0.5 * n / SR
        env_fire += np.exp(-0.5 * (d / width) ** 2)
    env_fire /= np.mean(env_fire) + 1e-12
    env_intake = np.roll(env_fire, int(0.5 * cycle / len(e["banks"][0]) * SR))        # sani je posunute proti vyfuku
    intake = _circular_noise(n, rng, f, 220.0, 1700.0) * (0.35 + 0.65 * env_intake)
    hiss = _circular_noise(n, rng, f, 1500.0, 7000.0) * (0.25 + 0.75 * env_fire)
    mech = _circular_noise(n, rng, f, 2200.0, 6500.0) * (0.5 + 0.5 * np.cos(2.0 * np.pi * t / cycle * 4.0) ** 2)
    k_load = 1.0 if load > 0.5 else 0.35
    out += intake * e["intake"] * k_load * (0.5 + 0.8 * x_rel)
    out += hiss * e["hiss"] * k_load * (0.4 + 1.2 * x_rel)
    out += mech * e["mech"] * (0.6 + 1.4 * x_rel)

    # --- 5. Hlasitost: stejna stredni uroven u vsech smycek, bez orezani spicek ---
    out /= np.sqrt(np.mean(out ** 2)) + 1e-12
    out = np.tanh(out * 0.2 / 0.9) * 0.9                 # stredni uroven ~0.19, mekke omezeni spicek
    return out


def turbo_whistle(seconds=1.6, seed=5):
    """Hvizd turba: uzky pisklavy ton s jemnym kolisanim, opakovatelny."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    shape = np.exp(-0.5 * ((f - 5200.0) / 140.0) ** 2) + 0.35 * np.exp(-0.5 * ((f - 10400.0) / 300.0) ** 2) \
        + 0.05 * (f / 3000.0) / (1.0 + (f / 3000.0) ** 2)
    x = np.fft.irfft(spec * shape, n)
    return x / np.max(np.abs(x))
