#!/usr/bin/env python3
"""Vygeneruje plan obriho mesta do data/mesto.json (hra ho jen nacte).

Mesto je poskladane podle skutecnych mest:
  - reka s nabrezimi a mosty (Praha, Pariz),
  - stare mesto s krivolakymi ulickami uvnitr okruzni tridy (Viden - Ringstrasse),
  - paprskove bulvary a druhy okruh (Moskva, Pariz),
  - pravidelna mrizka s dlouhymi bloky (Manhattan, Barcelona),
  - mestska dalnice dokola (Boulevard Peripherique),
  - predmesti s dlouhymi zatocenymi ulicemi a prumyslova ctvrt s velkymi bloky.

Postup: hlavni tahy se zadaji krivkami a najdou se jejich krizeni; mezi ne se nasypou body
(hustota podle ctvrti) a spoji se tak, aby se ulice nikde nekrizily (Gabrieluv graf);
pak se sit procisti (ostre uhly, slepe ulice, ulice moc blizko sebe) a retezy bodu
se spoji do plynule zatocenych ulic.

Spusteni:  python3 tools/generuj_mesto.py [nahled.png]
Potrebuje: numpy, scipy (Pillow jen pro nahled)
"""
import json
import math
import os
import sys
from collections import defaultdict

import numpy as np
from scipy.spatial import Delaunay, cKDTree

SEED = 2427
rng = np.random.default_rng(SEED)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "mesto.json")

SIDEWALK = 4.5
R0 = 3900.0                 # zakladni polomer mesta (m)
RIVER_HALF = 78.0           # vzdalenost osy nabrezi od osy reky
W = {"magistrala": 13.5, "dalnice": 13.5, "bulvar": 11.0, "obvod": 9.5, "nabrezi": 9.5, "horska": 8.0, "trida": 9.5, "ulice": 8.0, "ulicka": 6.5}
PRIORITY = {"magistrala": 6, "dalnice": 5, "bulvar": 4, "obvod": 4, "nabrezi": 4, "horska": 4, "trida": 2, "ulice": 1, "ulicka": 1}
NO_ATTACH = ("dalnice", "magistrala", "horska")     # na tyto tahy se mistni ulice nenapojuji
HILL_CENTER = math.radians(-115.0)     # smer, kde za mestem lezi kopce
HILL_HALF = math.radians(38.0)
HILL_RREF = 4400.0
BRIDGE_CLEAR = 7.8                     # vyska mostovky nad spodni silnici (m)
WATER_LEVEL = 0.0
MIN_ANGLE = math.radians(48.0)
WARNED = set()


# ---------------------------------------------------------------------------
#  Tvar mesta
# ---------------------------------------------------------------------------
def r_perimeter(th):
    return R0 * (1.0 + 0.07 * np.sin(2 * th + 1.0) + 0.045 * np.sin(3 * th + 2.3))


def r_highway(th):
    return 0.62 * r_perimeter(th) * (1.0 + 0.035 * np.sin(4 * th + 0.7))


def r_ring2(th):
    return 1400.0 * (1.0 + 0.05 * np.sin(3 * th + 0.4))


def r_ring3(th):
    return 0.82 * r_perimeter(th) * (1.0 + 0.03 * np.sin(5 * th + 1.3))


def r_inner(th):
    return 630.0 * (1.0 + 0.09 * np.sin(2 * th + 0.5) + 0.05 * np.sin(5 * th + 1.0))


def river_z(x):
    return 250.0 + 620.0 * (x / 3600.0) ** 2 + 55.0 * np.sin(x / 420.0 + 0.8)


def ring(fn, step_deg=0.5):
    th = np.radians(np.arange(0.0, 360.0, step_deg))
    r = fn(th)
    return np.stack([r * np.cos(th), r * np.sin(th)], axis=1)


def polyline_length(pl):
    return float(np.sum(np.linalg.norm(np.diff(pl, axis=0), axis=1)))


def resample(pl, step):
    """Body po priblizne stejnych vzdalenostech (vcetne obou koncu)."""
    seg = np.linalg.norm(np.diff(pl, axis=0), axis=1)
    acc = np.concatenate([[0.0], np.cumsum(seg)])
    total = acc[-1]
    n = max(1, int(round(total / step)))
    t = np.linspace(0.0, total, n + 1)
    return np.stack([np.interp(t, acc, pl[:, 0]), np.interp(t, acc, pl[:, 1])], axis=1)


def offset_curve(pl, dist):
    d = np.gradient(pl, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    return pl + np.stack([-d[:, 1], d[:, 0]], axis=1) * dist


def radial(angle_deg, drift_deg, wobble, phase, start=None):
    a = math.radians(angle_deg)
    u = np.linspace(0.0, 1.0, 220)
    th = a + math.radians(drift_deg) * u + wobble * np.sin(2 * np.pi * u * 1.4 + phase) * u * (1.0 - 0.3 * u)
    r0 = (r_inner(a) * 0.93) if start is None else start(a) * 0.96
    r1 = r_perimeter(th[-1]) * 1.04
    r = r0 + (r1 - r0) * u
    return np.stack([r * np.cos(th), r * np.sin(th)], axis=1)


def hill_to_world(pts):
    """Body v souradnicich kopcu (a = metry podel okraje mesta, v = metry ven od okraje) -> svet."""
    pts = np.asarray(pts, dtype=float)
    th = HILL_CENTER + pts[:, 0] / HILL_RREF
    r = r_perimeter(th) + pts[:, 1]
    return np.stack([r * np.cos(th), r * np.sin(th)], axis=1)


def left_of(h):
    return np.array([-h[1], h[0]])


def tangent_path(elements, step=12.0):
    """Cesta slozena z primek a oblouku (jako kdyz se jede autem): seznam prvku
    ("bod", stred) nebo ("kruh", stred, polomer, smer), smer +1 = doleva, -1 = doprava."""
    cs = []
    for el in elements:
        if el[0] == "bod":
            cs.append((np.array(el[1], dtype=float), 0.0, 1.0))
        else:
            cs.append((np.array(el[1], dtype=float), float(el[2]), float(el[3])))
    tang = []          # pro kazdou dvojici: (bod na prvnim, bod na druhem, smer)
    for (c1, r1, d1), (c2, r2, d2) in zip(cs[:-1], cs[1:]):
        dvec = c2 - c1
        dist = np.linalg.norm(dvec)
        q = d2 * r2 - d1 * r1
        ang_left = math.atan2(dvec[1], dvec[0]) + math.acos(max(-1.0, min(1.0, q / dist)))
        h = np.array([math.cos(ang_left - math.pi / 2), math.sin(ang_left - math.pi / 2)])
        tang.append((c1 - d1 * r1 * left_of(h), c2 - d2 * r2 * left_of(h), h))
    out = []
    for k, (p1, p2, h) in enumerate(tang):
        n = max(1, int(np.linalg.norm(p2 - p1) / 20.0))
        for i in range(n):
            out.append(p1 + (p2 - p1) * i / n)
        if k + 1 < len(tang):
            c, r, d = cs[k + 1]
            a0 = math.atan2(*(p2 - c)[::-1])
            p_out = tang[k + 1][0]
            a1 = math.atan2(*(p_out - c)[::-1])
            sweep = (a1 - a0) * d % (2 * math.pi)
            m = max(2, int(r * sweep / step))
            for i in range(m):
                a = a0 + d * sweep * i / m
                out.append(c + r * np.array([math.cos(a), math.sin(a)]))
    out.append(tang[-1][1])
    return np.array(out)


MAG = {"a": 3661.2, "b": 1266.5, "rot": 9.295, "cx": 212.7, "cz": -1236.8, "w1": 214.5, "p1": 6.0252, "w2": 64.3, "p2": 3.7723}


def magistrala_curve():
    """Mestska magistrala: velka "osmicka" pres cele mesto (zataci na obe strany, sama sebe krizi mostem)."""
    m = MAG
    t = np.radians(np.arange(0.0, 360.0, 0.2))
    x = m["a"] * np.cos(t) + m["w1"] * np.sin(3 * t + m["p1"])
    z = m["b"] * np.sin(2 * t) + m["w2"] * np.sin(5 * t + m["p2"])
    rot = math.radians(m["rot"])
    xr = x * math.cos(rot) - z * math.sin(rot) + m["cx"]
    zr = x * math.sin(rot) + z * math.cos(rot) + m["cz"]
    return np.stack([xr, zr], axis=1)


def hill_roads():
    """Horske silnice v kopcich za mestem: serpentiny, hrebenovka a dva dlouhe sjezdy."""
    roads = []
    # Serpentiny: sest vlasenek nad sebou, nahore se napoji na hrebenovku
    u, v0, dv, rh = 215.0, 190.0, 195.0, 32.0
    el = [("bod", (-u, -55.0)), ("kruh", (-u + 55.0, 45.0), 55.0, -1)]
    for k in range(6):
        side = 1.0 if k % 2 == 0 else -1.0
        el.append(("kruh", (side * u, v0 + k * dv), rh, side))
    top = v0 + 5 * dv + rh
    el.append(("kruh", (-u + 300.0, top + 80.0), 80.0, 1))
    el.append(("bod", (-u + 380.0, 1700.0)))
    roads.append(("serpentiny", tangent_path(el)))
    # Hrebenovka: od zapadniho okraje mesta sikmo nahoru, po hrebeni nad serpentinami a na vychode zase dolu
    pts = [(-2650, -55), (-2650, 70), (-2560, 250), (-2330, 400), (-2210, 640), (-1960, 790), (-1850, 1040),
           (-1620, 1220), (-1480, 1420), (-1000, 1540), (-500, 1440), (0, 1560), (500, 1450), (1000, 1560),
           (1480, 1430), (1640, 1210), (1870, 1050), (1950, 800), (2200, 650), (2340, 410), (2570, 250),
           (2650, 70), (2650, -55)]
    roads.append(("hrebenovka", catmull_rom(np.array(pts, dtype=float), 14.0)))
    return [(name, resample(hill_to_world(pts), 14.0)) for name, pts in roads]


def build_majors():
    """Hlavni tahy: (nazev, trida, uzavreny, lomena cara)."""
    majors = []
    majors.append(("obvod", "obvod", True, resample(ring(r_perimeter), 20.0)))
    majors.append(("dalnice", "dalnice", True, resample(ring(r_highway), 20.0)))
    majors.append(("ring", "bulvar", True, resample(ring(r_inner), 20.0)))
    majors.append(("okruh2", "bulvar", True, resample(ring(r_ring2), 20.0)))
    majors.append(("okruh3", "bulvar", True, resample(ring(r_ring3), 20.0)))
    # Paprsky (uhel 0 = vychod, 90 = jih); mezi vychodem a jihovychodem tece reka, tam zadny neni
    for k, (ang, drift, wob, ph) in enumerate([(-160, 6, 0.06, 0.3), (-124, -7, 0.07, 1.7), (-90, 5, 0.05, 2.9),
                                              (-52, -4, 0.03, 0.9), (-17, 5, 0.03, 4.1), (54, 7, 0.07, 2.2),
                                              (92, -6, 0.06, 5.0), (131, 6, 0.07, 3.6)]):
        majors.append((f"paprsek{k}", "bulvar", False, resample(radial(ang, drift, wob, ph), 20.0)))
    # Vedlejsi paprsky az od druheho okruhu (ve velkem meste by jinak mezi hlavnimi bylo prilis daleko)
    for k, (ang, drift, wob, ph) in enumerate([(-142, -4, 0.04, 2.0), (-107, 5, 0.04, 0.4), (-71, -5, 0.04, 3.3),
                                              (-34, 3, 0.02, 1.2), (73, -5, 0.05, 4.4), (111, 5, 0.05, 1.0)]):
        majors.append((f"vedlejsi{k}", "bulvar", False, resample(radial(ang, drift, wob, ph, r_ring2), 20.0)))
    # Reka a jeji dve nabrezi
    x = np.arange(-4900.0, 4900.0, 10.0)
    river = np.stack([x, river_z(x)], axis=1)
    majors.append(("nabrezi_s", "nabrezi", False, resample(offset_curve(river, -RIVER_HALF), 20.0)))
    majors.append(("nabrezi_j", "nabrezi", False, resample(offset_curve(river, RIVER_HALF), 20.0)))
    # Magistrala a horske silnice
    majors.append(("magistrala", "magistrala", True, resample(magistrala_curve(), 20.0)))
    for name, pl in hill_roads():
        majors.append((name, "horska", False, pl))
    return majors, river


# ---------------------------------------------------------------------------
#  Geometrie
# ---------------------------------------------------------------------------
def seg_intersections(a0, a1, b0, b1):
    """Pruseciky vsech usecek A (n x 2) se vsemi useckami B (m x 2). Vraci indexy a parametry."""
    da = (a1 - a0)[:, None, :]
    db = (b1 - b0)[None, :, :]
    diff = b0[None, :, :] - a0[:, None, :]
    den = da[..., 0] * db[..., 1] - da[..., 1] * db[..., 0]
    with np.errstate(divide="ignore", invalid="ignore"):
        t = (diff[..., 0] * db[..., 1] - diff[..., 1] * db[..., 0]) / den
        u = (diff[..., 0] * da[..., 1] - diff[..., 1] * da[..., 0]) / den
    ok = (np.abs(den) > 1e-9) & (t >= 0.0) & (t < 1.0) & (u >= 0.0) & (u < 1.0)
    ia, ib = np.nonzero(ok)
    return ia, ib, t[ia, ib], u[ia, ib]


def point_polyline_dist(points, pl):
    """Nejmensi vzdalenost kazdeho bodu od lomene cary."""
    a = pl[:-1]
    b = pl[1:]
    best = np.full(len(points), 1e18)
    ab = b - a
    ab2 = np.sum(ab * ab, axis=1) + 1e-12
    for i in range(0, len(points), 4000):
        p = points[i:i + 4000, None, :]
        t = np.clip(np.sum((p - a[None]) * ab[None], axis=2) / ab2[None], 0.0, 1.0)
        proj = a[None] + ab[None] * t[..., None]
        d = np.min(np.linalg.norm(p - proj, axis=2), axis=1)
        best[i:i + 4000] = d
    return best


def catmull_rom(points, step=18.0):
    """Plynula krivka prochazejici vsemi body (stredove parametrizovana)."""
    pts = np.asarray(points, dtype=float)
    if len(pts) == 2:
        return pts.copy()
    ext = np.concatenate([[2 * pts[0] - pts[1]], pts, [2 * pts[-1] - pts[-2]]])
    out = [pts[0]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        n = max(2, int(round(np.linalg.norm(p2 - p1) / step)))
        t0 = 0.0
        t1 = t0 + np.linalg.norm(p1 - p0) ** 0.5
        t2 = t1 + np.linalg.norm(p2 - p1) ** 0.5
        t3 = t2 + np.linalg.norm(p3 - p2) ** 0.5
        for k in range(1, n + 1):
            t = t1 + (t2 - t1) * k / n
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            out.append((t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2)
    return np.array(out)


def bent_segment(a, b, sag):
    """Mirne prohnuta ulice mezi dvema body (sag = vyboceni uprostred v metrech)."""
    d = b - a
    length = np.linalg.norm(d)
    n = max(3, int(round(length / 18.0)))
    t = np.linspace(0.0, 1.0, n + 1)[:, None]
    perp = np.array([-d[1], d[0]]) / length
    ctrl = (a + b) * 0.5 + perp * sag * 2.0
    return a * (1 - t) ** 2 + ctrl * 2 * (1 - t) * t + b * t ** 2


# ---------------------------------------------------------------------------
#  Ctvrti
# ---------------------------------------------------------------------------
GRID_SECTOR = (math.radians(-50.0), math.radians(-19.0))


def district(p):
    x, z = p
    r = math.hypot(x, z)
    th = math.atan2(z, x)
    south = z > river_z(x)
    if r < r_inner(th):
        return "stare"
    if r < r_highway(th):
        if GRID_SECTOR[0] < th < GRID_SECTOR[1]:
            return "mrizka"
        return "jih" if south else "mesto"
    if r > r_perimeter(th):
        return "kopce"
    if south and x > -400.0:
        return "prumysl"
    return "predmesti"


SPACING = {"stare": 82.0, "mesto": 108.0, "jih": 118.0, "mrizka": 125.0, "predmesti": 150.0, "prumysl": 205.0, "kopce": 400.0}
LOCAL_CLASS = {"stare": "ulicka", "mesto": "ulice", "jih": "ulice", "mrizka": "ulice", "predmesti": "ulice", "prumysl": "trida", "kopce": "ulice"}


# ---------------------------------------------------------------------------
#  Sit ulic
# ---------------------------------------------------------------------------
class City:
    def __init__(self):
        self.pts = []            # [x, z]
        self.connect = []        # smi se na bod napojit mistni ulice?
        self.major = []          # bod lezi na hlavnim tahu
        self.edges = {}          # (i, j) i<j -> dict(cls, geom (od i do j) nebo None)

    def add_point(self, p, major=False, connect=True):
        self.pts.append([float(p[0]), float(p[1])])
        self.major.append(major)
        self.connect.append(connect)
        return len(self.pts) - 1

    def add_edge(self, i, j, cls, geom=None):
        if i == j:
            return
        if i > j:
            i, j = j, i
            if geom is not None:
                geom = geom[::-1]
        self.edges[(i, j)] = {"cls": cls, "geom": geom}

    def adjacency(self):
        adj = defaultdict(set)
        for (i, j) in self.edges:
            adj[i].add(j)
            adj[j].add(i)
        return adj


MAG_JUNCTIONS = []      # body, kde se magistrala krizi urovnove (krizovatka); jinde mostem / podjezdem


def magistrala_crossings(majors):
    """Vsechna krizeni magistraly s ostatnimi hlavnimi tahy: (poloha podel magistraly v m, nazev, uhel, bod)."""
    mag = [m for m in majors if m[0] == "magistrala"][0][3]
    pa = np.concatenate([mag, mag[:1]])
    seg = np.linalg.norm(np.diff(pa, axis=0), axis=1)
    acc = np.concatenate([[0.0], np.cumsum(seg)])
    res = []
    for name, cls, closed, pb in majors:
        if name == "magistrala":
            continue
        if closed:
            pb = np.concatenate([pb, pb[:1]])
        ia, ib, t, u = seg_intersections(pa[:-1], pa[1:], pb[:-1], pb[1:])
        for k in range(len(ia)):
            da = pa[ia[k] + 1] - pa[ia[k]]
            db = pb[ib[k] + 1] - pb[ib[k]]
            ang = math.degrees(math.acos(min(1.0, abs(np.dot(da, db)) / (np.linalg.norm(da) * np.linalg.norm(db)))))
            res.append((acc[ia[k]] + seg[ia[k]] * t[k], name, ang, pa[ia[k]] + da * t[k]))
    res.sort(key=lambda r: r[0])
    return res, acc[-1]


def choose_junctions(majors):
    """Vybere par krizeni magistraly s bulvary jako obycejne krizovatky (najezdy), dost daleko od sebe i od mostu."""
    res, total = magistrala_crossings(majors)
    chosen = []
    cands = [r for r in res if (r[1].startswith("vedlejsi") or r[1].startswith("paprsek") or r[1].startswith("okruh")) and r[2] >= 58.0]
    cands.sort(key=lambda r: -r[2])
    for c in cands:
        def gap(s1, s2):
            d = abs(s1 - s2) % total
            return min(d, total - d)
        if any(gap(c[0], o[0]) < 1900.0 for o in chosen):
            continue
        if any(gap(c[0], o[0]) < 330.0 for o in res if o is not c):
            continue
        chosen.append(c)
    MAG_JUNCTIONS[:] = [c[3] for c in chosen]
    return res, chosen


def is_junction(name_a, name_b, p):
    """Ma byt krizeni dvou hlavnich tahu obycejna krizovatka? (jinak most / podjezd)"""
    if "magistrala" not in (name_a, name_b):
        return True
    return any(np.linalg.norm(p - q) < 3.0 for q in MAG_JUNCTIONS)


def node_majors(majors):
    """Najde krizeni hlavnich tahu a rozdeli je na useky mezi krizovatkami."""
    choose_junctions(majors)
    cuts = [[] for _ in majors]          # pro kazdy tah: (poloha podel cary, bod)
    grade = [[] for _ in majors]         # mimourovnova krizeni: poloha podel cary
    crossings = []
    for i in range(len(majors)):
        for j in range(i + 1, len(majors)):
            pa = majors[i][3]
            pb = majors[j][3]
            if majors[i][2]:
                pa = np.concatenate([pa, pa[:1]])
            if majors[j][2]:
                pb = np.concatenate([pb, pb[:1]])
            ia, ib, t, u = seg_intersections(pa[:-1], pa[1:], pb[:-1], pb[1:])
            for k in range(len(ia)):
                p = pa[ia[k]] + (pa[ia[k] + 1] - pa[ia[k]]) * t[k]
                da = pa[ia[k] + 1] - pa[ia[k]]
                db = pb[ib[k] + 1] - pb[ib[k]]
                ang = math.degrees(math.acos(min(1.0, abs(np.dot(da, db)) / (np.linalg.norm(da) * np.linalg.norm(db)))))
                junction = is_junction(majors[i][0], majors[j][0], p)
                crossings.append((majors[i][0], majors[j][0], p, ang, junction))
                if junction:
                    cuts[i].append((ia[k] + t[k], p))
                    cuts[j].append((ib[k] + u[k], p))
                else:
                    grade[i].append(ia[k] + t[k])
                    grade[j].append(ib[k] + u[k])
    return cuts, crossings, grade


def build_major_graph(city, majors, cuts, grade):
    node_at = {}

    def node_for(p):
        key = (round(p[0] / 2.0), round(p[1] / 2.0))
        if key not in node_at:
            node_at[key] = city.add_point(p, major=True, connect=True)
        return node_at[key]

    for m, (name, cls, closed, pl) in enumerate(majors):
        cs = sorted(cuts[m], key=lambda c: c[0])
        if len(cs) < 2:
            continue
        if closed:
            full = np.concatenate([pl, pl[:1]])
            spans = [(cs[k], cs[(k + 1) % len(cs)]) for k in range(len(cs))]
        else:
            full = pl
            spans = [(cs[k], cs[k + 1]) for k in range(len(cs) - 1)]
        nseg = len(full) - 1
        for (s0, p0), (s1, p1) in spans:
            # Geometrie useku mezi dvema krizovatkami
            if s1 > s0:
                idx = list(range(int(math.floor(s0)) + 1, int(math.floor(s1)) + 1))
            else:                        # uzavreny tah: usek pres "sev"
                idx = list(range(int(math.floor(s0)) + 1, nseg)) + list(range(0, int(math.floor(s1)) + 1))
            geom = np.array([p0] + [full[i] for i in idx] + [p1])
            keep = [0] + [i for i in range(1, len(geom)) if np.linalg.norm(geom[i] - geom[i - 1]) > 1.0]
            geom = geom[keep]
            length = polyline_length(geom)
            if length < 60.0:
                print(f"  POZOR: kratky usek {name} {length:.0f} m u ({p0[0]:.0f}, {p0[1]:.0f})")
            a = node_for(p0)
            b = node_for(p1)
            # Body, kde se smi napojit mistni ulice (na dalnici zadne)
            n_sub = 1 if cls in NO_ATTACH else max(1, int(round(length / rng.uniform(160.0, 200.0))))
            fine = resample(geom, 20.0)
            bounds = np.linspace(0, len(fine) - 1, n_sub + 1).round().astype(int)
            # Napojeni mistnich ulic nesmi lezet na moste ani tesne u nej
            if grade[m] and n_sub > 1:
                gpts = np.array([full[min(int(g), nseg - 1)] for g in grade[m]])
                ok = [0]
                for bnd in bounds[1:-1]:
                    if np.min(np.linalg.norm(gpts - fine[bnd], axis=1)) > 110.0:
                        ok.append(bnd)
                ok.append(bounds[-1])
                bounds = np.array(ok)
                n_sub = len(bounds) - 1
            prev = a
            for k in range(n_sub):
                part = fine[bounds[k]:bounds[k + 1] + 1]
                nxt = b if k == n_sub - 1 else city.add_point(part[-1], major=True, connect=True)
                city.add_edge(prev, nxt, cls, part)
                prev = nxt


def local_points(city, majors, river):
    """Body mistnich ulic: nahodne s rozestupem podle ctvrti, v mrizkove ctvrti pravidelne."""
    major_geom = [m[3] if not m[2] else np.concatenate([m[3], m[3][:1]]) for m in majors]
    cand = []
    # Pravidelna mrizka (Manhattan): dlouhe bloky natocene podle osy vysece
    axis = (GRID_SECTOR[0] + GRID_SECTOR[1]) * 0.5 + math.radians(4.0)
    ex = np.array([math.cos(axis), math.sin(axis)])
    ey = np.array([-ex[1], ex[0]])
    origin = ex * 1500.0
    for i in range(-20, 21):
        for j in range(-26, 27):
            p = origin + ex * i * 178.0 + ey * j * 98.0 + rng.uniform(-4.0, 4.0, 2)
            if district(p) == "mrizka":
                cand.append((p, "mrizka"))
    grid_pts = np.array([c[0] for c in cand])
    # Nahodne body (Poissonuv disk s promennou hustotou)
    accepted = []
    cell = 100.0
    buckets = defaultdict(list)
    tries = rng.uniform(-R0 * 1.15, R0 * 1.15, (440000, 2))
    scale = rng.uniform(0.92, 1.18, len(tries))
    for p, sc in zip(tries, scale):
        r = math.hypot(p[0], p[1])
        if r > r_perimeter(math.atan2(p[1], p[0])):
            continue
        dist = district(p)
        if dist == "mrizka":
            continue
        if abs(p[1] - river_z(p[0])) < RIVER_HALF:
            continue
        s = SPACING[dist] * sc
        gx, gz = int(p[0] // cell), int(p[1] // cell)
        ok = True
        reach = int(s // cell) + 1
        for ix in range(gx - reach, gx + reach + 1):
            for iz in range(gz - reach, gz + reach + 1):
                for q, sq in buckets[(ix, iz)]:
                    if (q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2 < (0.5 * (s + sq)) ** 2:
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                break
        if ok:
            buckets[(gx, gz)].append((p, s))
            accepted.append((p, dist))
    cand += accepted
    pts = np.array([c[0] for c in cand])
    # Body moc blizko hlavnich tahu (a mrizky) pryc
    keep = np.ones(len(pts), dtype=bool)
    spacing = np.array([SPACING[c[1]] for c in cand])
    for geom in major_geom:
        d = point_polyline_dist(pts, geom)
        keep &= d > np.maximum(0.56 * spacing, 72.0)
    if len(grid_pts):
        tree = cKDTree(grid_pts)
        d, _ = tree.query(pts)
        is_grid = np.array([c[1] == "mrizka" for c in cand])
        keep &= is_grid | (d > 85.0)
    for p, k in zip(pts, keep):
        if k:
            city.add_point(p, major=False, connect=True)
    return major_geom


def gabriel_edges(city, major_geom):
    pts = np.array(city.pts)
    tri = Delaunay(pts)
    cand = set()
    for s in tri.simplices:
        for a, b in ((s[0], s[1]), (s[1], s[2]), (s[0], s[2])):
            cand.add((min(a, b), max(a, b)))
    tree = cKDTree(pts)
    major = np.array(city.major)
    connect = np.array(city.connect)
    good = []
    for i, j in cand:
        if (i, j) in city.edges:
            continue
        if major[i] and major[j]:
            continue
        if not (connect[i] and connect[j]):
            continue
        mid = (pts[i] + pts[j]) * 0.5
        rad = np.linalg.norm(pts[i] - pts[j]) * 0.5
        if rad * 2.0 > 2.3 * SPACING[district(mid)]:
            continue
        near = tree.query_ball_point(mid, rad * 0.985)
        if any(k != i and k != j for k in near):
            continue
        good.append((i, j))
    # Mistni ulice nesmi krizit hlavni tah (ani reku - tu hlidaji nabrezi)
    good = np.array(good)
    a0 = pts[good[:, 0]]
    a1 = pts[good[:, 1]]
    # zkratit o kousek, aby napojeni v koncovem bode nebylo "krizeni"
    d = a1 - a0
    a0s = a0 + d * 0.02
    a1s = a1 - d * 0.02
    bad = np.zeros(len(good), dtype=bool)
    for geom in major_geom:
        ia, _, _, _ = seg_intersections(a0s, a1s, geom[:-1], geom[1:])
        bad[ia] = True
    for (i, j), b in zip(good, bad):
        if not b:
            mid = (pts[i] + pts[j]) * 0.5
            city.add_edge(int(i), int(j), LOCAL_CLASS[district(mid)])


def edge_dir(city, i, j):
    """Smer, kterym ulice (i, j) vychazi z bodu i."""
    key = (min(i, j), max(i, j))
    g = city.edges[key]["geom"]
    p = np.array(city.pts)
    if g is None:
        d = p[j] - p[i]
    elif key[0] == i:
        d = g[min(2, len(g) - 1)] - g[0]
    else:
        d = g[-1 - min(2, len(g) - 1)] - g[-1]
    return d / (np.linalg.norm(d) + 1e-12)


def edge_len(city, key):
    g = city.edges[key]["geom"]
    if g is None:
        p = city.pts
        return math.hypot(p[key[0]][0] - p[key[1]][0], p[key[0]][1] - p[key[1]][1])
    return polyline_length(g)


def prune(city):
    """Odstrani ostre uhly, trojuhelniky, prilis huste krizovatky a slepe ulice."""
    removed = 0
    # Trojuhelnikove bloky: pryc nejdelsi mistni stranu
    adj = city.adjacency()
    for i in list(adj):
        for j in list(adj[i]):
            if j <= i:
                continue
            for k in adj[i] & adj[j]:
                if k <= j:
                    continue
                tri = [(i, j), (j, k), (i, k)]
                tri = [t for t in tri if t in city.edges and PRIORITY[city.edges[t]["cls"]] <= 2]
                if tri and rng.random() < 0.9:
                    longest = max(tri, key=lambda t: edge_len(city, t))
                    if longest in city.edges:
                        del city.edges[longest]
                        adj[longest[0]].discard(longest[1])
                        adj[longest[1]].discard(longest[0])
                        removed += 1
    changed = True
    while changed:
        changed = False
        adj = city.adjacency()
        for i, nb in adj.items():
            if len(nb) < 2:
                continue
            dirs = sorted(((math.atan2(*edge_dir(city, i, j)[::-1]), j) for j in nb))
            n = len(dirs)
            for k in range(n):
                a0, j0 = dirs[k]
                a1, j1 = dirs[(k + 1) % n]
                gap = (a1 - a0) % (2 * math.pi)
                if n == 2 and k == 1:
                    continue
                if gap < MIN_ANGLE or len(nb) > 5:
                    k0 = (min(i, j0), max(i, j0))
                    k1 = (min(i, j1), max(i, j1))
                    c0 = PRIORITY[city.edges[k0]["cls"]]
                    c1 = PRIORITY[city.edges[k1]["cls"]]
                    if c0 >= 4 and c1 >= 4:
                        if gap < MIN_ANGLE and i not in WARNED:
                            WARNED.add(i)
                            print(f"  POZOR: ostry uhel hlavnich tahu {math.degrees(gap):.0f} st u ({city.pts[i][0]:.0f}, {city.pts[i][1]:.0f})")
                        continue
                    if c0 != c1:
                        victim = k0 if c0 < c1 else k1
                    else:
                        victim = k0 if edge_len(city, k0) > edge_len(city, k1) else k1
                    del city.edges[victim]
                    removed += 1
                    changed = True
                    break
            if changed:
                break
    return removed


def thin(city, share):
    """Nahodne ubere cast mistnich ulic mezi ctyrsmernymi krizovatkami (vzniknou vetsi bloky a T-krizovatky)."""
    adj = city.adjacency()
    keys = [k for k, e in city.edges.items() if PRIORITY[e["cls"]] <= 2]
    rng.shuffle(keys)
    for k in keys:
        mid = (np.array(city.pts[k[0]]) + np.array(city.pts[k[1]])) * 0.5
        if rng.random() < share.get(district(mid), 0.1) and len(adj[k[0]]) >= 4 and len(adj[k[1]]) >= 4:
            del city.edges[k]
            adj[k[0]].discard(k[1])
            adj[k[1]].discard(k[0])


def drop_dead_ends(city):
    while True:
        adj = city.adjacency()
        dead = [i for i, nb in adj.items() if len(nb) == 1]
        if not dead:
            break
        for i in dead:
            for j in adj[i]:
                city.edges.pop((min(i, j), max(i, j)), None)
    # jen nejvetsi souvisla cast
    adj = city.adjacency()
    seen = {}
    comp = 0
    for s in adj:
        if s in seen:
            continue
        stack = [s]
        seen[s] = comp
        while stack:
            u = stack.pop()
            for v in adj[u]:
                if v not in seen:
                    seen[v] = comp
                    stack.append(v)
        comp += 1
    sizes = defaultdict(int)
    for v in seen.values():
        sizes[v] += 1
    best = max(sizes, key=sizes.get)
    for k in list(city.edges):
        if seen[k[0]] != best:
            del city.edges[k]


# ---------------------------------------------------------------------------
#  Spojeni retezu bodu do zatocenych ulic
# ---------------------------------------------------------------------------
def merge_chains(city, forced):
    """Vrati (uzly, ulice): body se dvema ulicemi stejne tridy se stanou zatackou jedne delsi ulice."""
    pts = np.array(city.pts)
    adj = city.adjacency()

    def is_node(i):
        nb = list(adj[i])
        if len(nb) != 2 or i in forced:
            return True
        k0 = (min(i, nb[0]), max(i, nb[0]))
        k1 = (min(i, nb[1]), max(i, nb[1]))
        if city.edges[k0]["cls"] != city.edges[k1]["cls"]:
            return True
        d0 = edge_dir(city, i, nb[0])
        d1 = edge_dir(city, i, nb[1])
        turn = math.pi - math.acos(max(-1.0, min(1.0, float(np.dot(d0, d1)))))
        return turn > math.radians(52.0)          # ostra zatacka zustane "rohem" (krizovatkou dvou ulic)

    nodes = [i for i in adj if is_node(i)]
    node_set = set(nodes)
    streets = []
    done = set()
    for start in nodes:
        for nxt in adj[start]:
            if (start, nxt) in done:
                continue
            chain = [start, nxt]
            while chain[-1] not in node_set:
                a, b = chain[-2], chain[-1]
                c = [v for v in adj[b] if v != a][0]
                chain.append(c)
            done.add((chain[0], chain[1]))
            done.add((chain[-1], chain[-2]))
            keys = [(min(chain[k], chain[k + 1]), max(chain[k], chain[k + 1])) for k in range(len(chain) - 1)]
            cls = city.edges[keys[0]]["cls"]
            if city.edges[keys[0]]["geom"] is not None:
                parts = []
                for k, key in enumerate(keys):
                    g = city.edges[key]["geom"]
                    g = g if key[0] == chain[k] else g[::-1]
                    parts.append(g if k == 0 else g[1:])
                geom = np.concatenate(parts)
            elif len(chain) == 2:
                a, b = pts[chain[0]], pts[chain[1]]
                length = np.linalg.norm(b - a)
                mid = (a + b) * 0.5
                dist = district(mid)
                if dist != "mrizka" and rng.random() < 0.55 and length > 90.0:
                    geom = bent_segment(a, b, length * rng.uniform(0.02, 0.055) * rng.choice([-1.0, 1.0]))
                else:
                    geom = np.array([a, b])
            else:
                geom = catmull_rom(pts[chain])
            streets.append({"a": chain[0], "b": chain[-1], "cls": cls, "geom": geom, "chain": chain})
    return nodes, streets


def fix_parallel(streets):
    """Dve ulice mezi stejnou dvojici krizovatek nebo smycka: jeden vnitrni bod se musi stat krizovatkou."""
    forced = set()
    seen = {}
    for s in streets:
        key = (min(s["a"], s["b"]), max(s["a"], s["b"]))
        if s["a"] == s["b"] or key in seen:
            victim = s if len(s["chain"]) > 2 else seen.get(key, s)
            if len(victim["chain"]) > 2:
                forced.add(victim["chain"][len(victim["chain"]) // 2])
                if victim["a"] == victim["b"] and len(victim["chain"]) > 4:
                    forced.add(victim["chain"][len(victim["chain"]) // 4])
        seen.setdefault(key, s)
    return forced


def street_dir(s, at_start):
    g = s["geom"]
    d = (g[1] - g[0]) if at_start else (g[-2] - g[-1])
    return d / np.linalg.norm(d)


def compute_trims(nodes, streets):
    """Stejny vypocet jako ve hre (CityMap): o kolik se ulice u krizovatky zkrati."""
    at = defaultdict(list)
    for idx, s in enumerate(streets):
        at[s["a"]].append((idx, True))
        at[s["b"]].append((idx, False))
    trims = {}
    min_gap = {}
    for n in nodes:
        arr = []
        for idx, start in at[n]:
            d = street_dir(streets[idx], start)
            arr.append((math.atan2(d[1], d[0]) % (2 * math.pi), W[streets[idx]["cls"]], idx))
        arr.sort()
        d = 3.0
        gap_min = 9.0
        for k in range(len(arr)):
            a = arr[k]
            b = arr[(k + 1) % len(arr)]
            theta = (b[0] - a[0]) % (2 * math.pi)
            if len(arr) == 1:
                continue
            if len(arr) == 2 and theta > math.pi:
                continue
            gap_min = min(gap_min, theta)
            if theta < math.pi * 0.95:
                d = max(d, max(a[1], b[1]) / math.tan(theta * 0.5) + 1.0)
        trims[n] = min(d, 34.0)
        min_gap[n] = gap_min
    return trims, min_gap, at


def validate(city, nodes, streets):
    """Najde ulice, ktere by ve hre delaly potize. Vraci mnozinu useku (dvojic bodu) k odstraneni."""
    trims, min_gap, at = compute_trims(nodes, streets)
    victims = set()
    problems = defaultdict(int)

    def kill(s, why):
        if PRIORITY[s["cls"]] >= 4:
            problems["hlavni tah: " + why] += 1
            return False
        ch = s["chain"]
        k = len(ch) // 2
        victims.add((min(ch[k - 1], ch[k]), max(ch[k - 1], ch[k])))
        problems[why] += 1
        return True

    # 1. Ostre uhly v krizovatkach
    for n in nodes:
        if min_gap[n] < math.radians(44.0):
            cands = sorted((streets[idx] for idx, _ in at[n]), key=lambda s: (PRIORITY[s["cls"]], -polyline_length(s["geom"])))
            kill(cands[0], "ostry uhel")
    # 2. Prilis kratke ulice (krizovatky by se prekryvaly)
    lengths = [polyline_length(s["geom"]) for s in streets]
    for s, length in zip(streets, lengths):
        if length < trims[s["a"]] + trims[s["b"]] + 16.0:
            kill(s, "kratka ulice")
    # 3. Prilis ostre zatacky (vnitrni okraj by se prekrizil)
    for s in streets:
        g = s["geom"]
        if len(g) < 3:
            continue
        d = np.diff(g, axis=0)
        seg = np.linalg.norm(d, axis=1)
        d = d / seg[:, None]
        turn = np.arccos(np.clip(np.sum(d[:-1] * d[1:], axis=1), -1.0, 1.0))
        radius = np.minimum(seg[:-1], seg[1:]) / np.maximum(turn, 1e-6)
        if np.min(radius) < W[s["cls"]] + SIDEWALK + 9.0:
            kill(s, "ostra zatacka")
    # 4. Ulice moc blizko sebe
    samples = []
    for idx, s in enumerate(streets):
        g = resample(s["geom"], 12.0)
        seg = np.linalg.norm(np.diff(g, axis=0), axis=1)
        acc = np.concatenate([[0.0], np.cumsum(seg)])
        for p, a in zip(g, acc):
            samples.append((p[0], p[1], idx, a, acc[-1] - a))
    arr = np.array([(s[0], s[1]) for s in samples])
    tree = cKDTree(arr)
    pairs = tree.query_pairs(13.5 * 2 + 2 * SIDEWALK + 7.0)
    for i, j in pairs:
        si, sj = samples[i], samples[j]
        if si[2] == sj[2]:
            continue
        a, b = streets[si[2]], streets[sj[2]]
        if "magistrala" in (a["cls"], b["cls"]) and PRIORITY[a["cls"]] >= 4 and PRIORITY[b["cls"]] >= 4:
            continue
        need = W[a["cls"]] + W[b["cls"]] + 2 * SIDEWALK + 7.0
        if math.hypot(si[0] - sj[0], si[1] - sj[1]) >= need:
            continue
        shared = {a["a"], a["b"]} & {b["a"], b["b"]}
        ok = False
        for n in shared:
            da = si[3] if a["a"] == n else si[4]
            db = sj[3] if b["a"] == n else sj[4]
            if a["a"] == n and a["b"] == n:
                da = min(si[3], si[4])
            if b["a"] == n and b["b"] == n:
                db = min(sj[3], sj[4])
            if da < trims[n] + 42.0 and db < trims[n] + 42.0:
                ok = True
        if not ok:
            pa, pb = PRIORITY[a["cls"]], PRIORITY[b["cls"]]
            victim = a if (pa, -lengths[si[2]]) < (pb, -lengths[sj[2]]) else b
            kill(victim, "ulice blizko sebe")
    return victims, problems, trims


# ---------------------------------------------------------------------------
#  Bloky (plochy mezi ulicemi), vodni plochy, volne plochy
# ---------------------------------------------------------------------------
def trace_faces(nodes, streets):
    """Obejde vsechny bloky. Blok = seznam (ulice, smer vpred?); blok lezi vpravo od smeru chuze."""
    at = defaultdict(list)
    for idx, s in enumerate(streets):
        da = street_dir(s, True)
        db = street_dir(s, False)
        at[s["a"]].append((math.atan2(da[1], da[0]), idx, True))
        at[s["b"]].append((math.atan2(db[1], db[0]), idx, False))
    for n in at:
        at[n].sort()
    pos = {}
    for n, arr in at.items():
        for k, (_, idx, start) in enumerate(arr):
            pos[(idx, start)] = (n, k)
    faces = []
    used = set()
    for idx in range(len(streets)):
        for fwd in (True, False):
            if (idx, fwd) in used:
                continue
            face = []
            cur = (idx, fwd)
            while cur not in used:
                used.add(cur)
                face.append(cur)
                e, f = cur
                # dorazime do koncove krizovatky; pokracujeme sousedni ulici (o jednu dal po smeru uhlu)
                n, k = pos[(e, not f)]
                arr = at[n]
                _, e2, start2 = arr[(k + 1) % len(arr)]
                cur = (e2, start2)
            faces.append(face)
    return faces


def face_polygon(face, streets):
    out = []
    for e, fwd in face:
        g = streets[e]["geom"]
        g = g if fwd else g[::-1]
        out.extend(g[:-1].tolist())
    return np.array(out)


def polygon_area(poly):
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


# ---------------------------------------------------------------------------
#  Okruhy
# ---------------------------------------------------------------------------
def shortest_path(graph, src, dst, banned):
    import heapq
    dist = {src: 0.0}
    prev = {}
    heap = [(0.0, src)]
    while heap:
        d, u = heapq.heappop(heap)
        if u == dst:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, w, e in graph[u]:
            if v in banned and v != dst:
                continue
            nd = d + w
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                prev[v] = (u, e)
                heapq.heappush(heap, (nd, v))
    if dst not in prev:
        return None
    path = []
    u = dst
    while u != src:
        p, e = prev[u]
        path.append((p, u, e))
        u = p
    return path[::-1]


def make_circuit(name, anchors, node_pos, streets, prefer):
    """Okruh pres zadane body: mezi nimi nejkratsi cesta, zadna krizovatka dvakrat."""
    graph = defaultdict(list)
    for idx, s in enumerate(streets):
        w = polyline_length(s["geom"]) * prefer.get(s["cls"], 1.0)
        graph[s["a"]].append((s["b"], w, idx))
        graph[s["b"]].append((s["a"], w, idx))
    ids = list(node_pos)
    arr = np.array([node_pos[i] for i in ids])
    tree = cKDTree(arr)
    stops = []
    for p in anchors:
        _, k = tree.query(p)
        if ids[k] not in stops:
            stops.append(ids[k])
    banned = set()
    route = []
    for k in range(len(stops)):
        a, b = stops[k], stops[(k + 1) % len(stops)]
        ban = set(banned) | (set(stops) - {a, b})
        path = shortest_path(graph, a, b, ban)
        if path is None:
            print(f"  POZOR: okruh {name}: nenalezena cesta mezi body {k} a {k + 1}")
            return None
        for u, v, e in path:
            route.append([e, streets[e]["a"] == u and streets[e]["b"] == v])
            if v != stops[0]:
                banned.add(v)
    # kontrola: zadna ulice dvakrat
    if len({r[0] for r in route}) != len(route):
        print(f"  POZOR: okruh {name} pouziva nekterou ulici dvakrat")
        return None
    length = sum(polyline_length(streets[e]["geom"]) for e, _ in route)
    return {"nazev": name, "ulice": route, "delka": round(length)}


def ring_circuit(name, cls, streets):
    """Okruh po uzavrenem tahu jedne tridy (dalnice)."""
    at = defaultdict(list)
    ids = [k for k, s in enumerate(streets) if s["cls"] == cls]
    for k in ids:
        at[streets[k]["a"]].append(k)
        at[streets[k]["b"]].append(k)
    first = ids[0]
    route = [[first, True]]
    node = streets[first]["b"]
    while True:
        nxt = [k for k in at[node] if k != route[-1][0]]
        if not nxt or nxt[0] == first:
            break
        k = nxt[0]
        fwd = streets[k]["a"] == node
        route.append([k, fwd])
        node = streets[k]["b"] if fwd else streets[k]["a"]
    # po smeru hodin pri pohledu shora (stejne jako ostatni okruhy)
    length = sum(polyline_length(streets[e]["geom"]) for e, _ in route)
    return {"nazev": name, "ulice": route, "delka": round(length)}


# ---------------------------------------------------------------------------
#  Vysky: prirodni teren, sklony silnic, mosty a podjezdy, vyskova mapa
# ---------------------------------------------------------------------------
TERRAIN = {"x0": -6400.0, "z0": -7700.0, "cell": 16.0, "nx": 801, "nz": 851}


def smooth(v, a, b):
    t = np.clip((np.asarray(v, dtype=float) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def terrain(x, z):
    """Prirodni teren (m n. hladinou reky): udoli reky, mirne zvlnene mesto, kopce za mestem, hory na obzoru."""
    x = np.asarray(x, dtype=float)
    z = np.asarray(z, dtype=float)
    r = np.hypot(x, z)
    th = np.arctan2(z, x)
    dr = np.abs(z - river_z(x))
    base = 4.0 + 34.0 * smooth(dr, 90.0, 2400.0)
    und = (17.0 * np.sin(x / 610.0 + 0.5) * np.cos(z / 740.0 - 0.8) + 10.0 * np.sin((x + z) / 390.0 + 2.0)) * smooth(dr, 120.0, 800.0)
    old = 26.0 * np.exp(-((x + 120.0) ** 2 + (z + 260.0) ** 2) / (2.0 * 340.0 ** 2))
    t = np.maximum(base + und + old, 3.0)          # mesto nikde neklesne pod hladinu reky
    v = r - r_perimeter(th)
    noise = np.sin(x / 530.0 + 1.3) * np.sin(z / 470.0 + 0.2) + 0.5 * np.sin((x - z) / 260.0 + 2.1)
    dth = np.abs((th - HILL_CENTER + np.pi) % (2 * np.pi) - np.pi)
    ws = 1.0 - smooth(dth, HILL_HALF, HILL_HALF + 0.25)
    def ramp(q):
        return np.clip((q - 20.0) / 1330.0, 0.0, 1.0)
    slope = (ramp(v - 70.0) + 2.0 * ramp(v) + ramp(v + 70.0)) / 4.0          # rovnomerny svah se zaoblenymi konci
    noise2 = np.sin(x / 430.0 + 0.7) * np.cos(z / 390.0 + 1.1) + 0.5 * np.sin((x + 2.0 * z) / 300.0)
    bumps = 24.0 * noise2 * smooth(v, 150.0, 600.0)                            # kopecky a sedla podel silnic
    peaks = 260.0 * smooth(v, 1450.0, 3200.0) * (1.0 + 0.45 * noise)           # vrcholy za hrebenem
    hills = 200.0 * slope * (1.0 + 0.1 * noise) + bumps + peaks
    rim = 28.0 * smooth(v, 0.0, 700.0) + 150.0 * smooth(v, 900.0, 2500.0) * (1.0 + 0.25 * noise)
    t = t + np.where(v > 0.0, ws * hills + (1.0 - ws) * rim, 0.0)
    # koryto reky
    bed = WATER_LEVEL - 3.5
    k = smooth(dr, RIVER_HALF - 22.0, RIVER_HALF - 13.0)
    return bed + (t - bed) * k


def stations(geom):
    return np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(geom, axis=0), axis=1))])


def merge_intervals(iv, gap=12.0):
    out = []
    for a, b in sorted(iv):
        if out and a <= out[-1][1] + gap:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def find_grade_crossings(streets, majors):
    """Mimourovnova krizeni (ulice se krizi bez krizovatky) + rozhodnuti, ktera vede horem."""
    mag_line = [m for m in majors if m[0] == "magistrala"][0][3]
    mag_tree = cKDTree(mag_line)
    found = []
    mags = [k for k, st in enumerate(streets) if st["cls"] == "magistrala"]
    for i in mags:
        a = streets[i]["geom"]
        sa = stations(a)
        for j, other in enumerate(streets):
            if j == i or PRIORITY[other["cls"]] < 4 or (other["cls"] == "magistrala" and j < i):
                continue
            b = other["geom"]
            if np.min(b[:, 0]) > np.max(a[:, 0]) + 5 or np.max(b[:, 0]) < np.min(a[:, 0]) - 5 or \
               np.min(b[:, 1]) > np.max(a[:, 1]) + 5 or np.max(b[:, 1]) < np.min(a[:, 1]) - 5:
                continue
            ia, ib, t, u = seg_intersections(a[:-1], a[1:], b[:-1], b[1:])
            sb = stations(b)
            for k in range(len(ia)):
                s1 = sa[ia[k]] + (sa[ia[k] + 1] - sa[ia[k]]) * t[k]
                s2 = sb[ib[k]] + (sb[ib[k] + 1] - sb[ib[k]]) * u[k]
                if min(s1, sa[-1] - s1) < 6.0 and min(s2, sb[-1] - s2) < 6.0:
                    continue                      # spolecna krizovatka, ne krizeni
                pt = a[ia[k]] + (a[ia[k] + 1] - a[ia[k]]) * t[k]
                _, near = mag_tree.query(pt)
                found.append({"p": pt, "mag": i, "s_mag": s1, "other": j, "s_other": s2, "loop": near * 20.0,
                              "river": other["cls"] == "nabrezi", "self": other["cls"] == "magistrala"})
    # Skupiny blizkych krizeni dostanou stejne reseni (jinak by se magistrala musela houpat prilis prudce)
    found.sort(key=lambda c: c["loop"])
    over = True
    k = 0
    while k < len(found):
        group = [found[k]]
        while k + 1 < len(found) and found[k + 1]["loop"] - group[-1]["loop"] < 520.0:
            k += 1
            group.append(found[k])
        k += 1
        if any(c["river"] or c["self"] for c in group):
            mag_up = True
        else:
            mag_up = over
            over = not over
        for c in group:
            c["mag_up"] = mag_up
    out = []
    for c in found:
        if c["mag_up"]:
            out.append({"p": c["p"], "up": c["mag"], "s_up": c["s_mag"], "low": c["other"], "s_low": c["s_other"]})
        else:
            out.append({"p": c["p"], "up": c["other"], "s_up": c["s_other"], "low": c["mag"], "s_low": c["s_mag"]})
    return out


def compute_spans(streets, crossings):
    """Useky ulic, ktere jsou mostem (nad jinou ulici nebo nad rekou) a ktere vedou pod mostem."""
    for st in streets:
        st["mosty"] = []
        st["podjezdy"] = []
        g = resample(st["geom"], 4.0)
        st["fine"] = g
        st["fine_s"] = stations(g)
        # nad rekou
        inside = np.abs(g[:, 1] - river_z(g[:, 0])) < RIVER_HALF - W["nabrezi"] - SIDEWALK - 0.5
        if st["cls"] != "nabrezi" and inside.any():
            idx = np.nonzero(inside)[0]
            breaks = np.nonzero(np.diff(idx) > 1)[0]
            starts = np.concatenate([[idx[0]], idx[breaks + 1]])
            ends = np.concatenate([idx[breaks], [idx[-1]]])
            for a, b in zip(starts, ends):
                st["mosty"].append([float(st["fine_s"][a]) - 3.0, float(st["fine_s"][b]) + 3.0])
    for c in crossings:
        up, low = streets[c["up"]], streets[c["low"]]
        d_up = point_polyline_dist(up["fine"], low["geom"])
        near = np.nonzero((d_up < W[low["cls"]] + SIDEWALK + 3.0) & (np.abs(up["fine_s"] - c["s_up"]) < 260.0))[0]
        c["span"] = [float(up["fine_s"][near[0]]) - 4.0, float(up["fine_s"][near[-1]]) + 4.0]
        up["mosty"].append(c["span"])
        d_low = point_polyline_dist(low["fine"], up["geom"])
        near = np.nonzero((d_low < W[up["cls"]] + SIDEWALK + 2.0) & (np.abs(low["fine_s"] - c["s_low"]) < 260.0))[0]
        c["under"] = [float(low["fine_s"][near[0]]) - 2.0, float(low["fine_s"][near[-1]]) + 2.0]
        low["podjezdy"].append(c["under"])
    for st in streets:
        total = st["len"]
        st["mosty"] = [[max(0.0, a), min(total, b)] for a, b in merge_intervals(st["mosty"])]
        st["podjezdy"] = [[max(0.0, a), min(total, b)] for a, b in merge_intervals(st["podjezdy"])]


def solve_heights(nodes, streets, crossings):
    """Vyska kazdeho bodu kazde ulice: blizko terenu, s omezenym sklonem, plynule, mosty dost vysoko."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.linalg import spsolve
    var = {}
    count = 0
    for n in nodes:
        var[("n", n)] = count
        count += 1
    for k, st in enumerate(streets):
        m = len(st["geom"])
        vi = [var[("n", st["a"])]] + list(range(count, count + m - 2)) + [var[("n", st["b"])]]
        count += m - 2
        st["vi"] = np.array(vi)
        st["s"] = stations(st["geom"])
    rows_i, rows_j, rows_v, rhs = [], [], [], []

    def add(terms, value, weight):
        r = len(rhs)
        for j, v in terms:
            rows_i.append(r)
            rows_j.append(j)
            rows_v.append(v * weight)
        rhs.append(value * weight)

    done = set()
    for k, st in enumerate(streets):
        g = st["geom"]
        t = terrain(g[:, 0], g[:, 1])
        cls = st["cls"]
        wd = {"nabrezi": 0.5, "horska": 0.1}.get(cls, 0.05)
        wg = {"magistrala": 14.0, "dalnice": 14.0, "horska": 13.0}.get(cls, 8.0)
        # mosty pres reku: mirne klenute, drzi se nad vodou
        on_bridge = np.zeros(len(g), dtype=bool)
        for a, b in st["mosty"]:
            on_bridge |= (st["s"] >= a) & (st["s"] <= b)
        for i in range(len(g)):
            v = st["vi"][i]
            if on_bridge[i] and t[i] < WATER_LEVEL + 3.0:
                add([(v, 1.0)], WATER_LEVEL + 7.5, 0.25)
            elif v not in done or 0 < i < len(g) - 1:
                add([(v, 1.0)], t[i], wd)
            done.add(v)
        ds = np.diff(st["s"])
        for i in range(len(g) - 1):
            w_here = wg * (1.6 if i < 2 or i > len(g) - 4 else 1.0)       # u krizovatek rovneji
            add([(st["vi"][i + 1], 1.0 / ds[i]), (st["vi"][i], -1.0 / ds[i])], 0.0, w_here)
        for i in range(1, len(g) - 1):
            add([(st["vi"][i - 1], 1.0), (st["vi"][i], -2.0), (st["vi"][i + 1], 1.0)], 0.0, 2.0 * (18.0 / max(ds[i - 1], ds[i])) ** 2)
    # plynuly prujezd krizovatkou u ulic, ktere pokracuji rovne
    at = defaultdict(list)
    for k, st in enumerate(streets):
        if len(st["geom"]) >= 2:
            at[st["a"]].append((k, street_dir(st, True), st["vi"][1], np.linalg.norm(st["geom"][1] - st["geom"][0])))
            at[st["b"]].append((k, street_dir(st, False), st["vi"][-2], np.linalg.norm(st["geom"][-1] - st["geom"][-2])))
    for n, arr in at.items():
        for i in range(len(arr)):
            for j in range(i + 1, len(arr)):
                if float(np.dot(arr[i][1], arr[j][1])) < -0.85 and streets[arr[i][0]]["cls"] == streets[arr[j][0]]["cls"]:
                    add([(arr[i][2], 1.0), (var[("n", n)], -2.0), (arr[j][2], 1.0)], 0.0, 2.0)
    # mosty a podjezdy
    for c in crossings:
        up, low = streets[c["up"]], streets[c["low"]]
        lc = low["vi"][int(np.argmin(np.abs(low["s"] - c["s_low"])))]
        for i in np.nonzero((up["s"] >= c["span"][0] - 6.0) & (up["s"] <= c["span"][1] + 6.0))[0]:
            add([(up["vi"][i], 1.0), (lc, -1.0)], BRIDGE_CLEAR, 6.0)
        for i in np.nonzero((low["s"] >= c["under"][0] - 4.0) & (low["s"] <= c["under"][1] + 4.0))[0]:
            if low["vi"][i] != lc:
                add([(low["vi"][i], 1.0), (lc, -1.0)], 0.0, 4.0)
    a = coo_matrix((rows_v, (rows_i, rows_j)), shape=(len(rhs), count)).tocsr()
    h = spsolve((a.T @ a).tocsc(), a.T @ np.array(rhs))
    node_h = {n: float(h[var[("n", n)]]) for n in nodes}
    worst = defaultdict(float)
    for st in streets:
        st["h"] = h[st["vi"]]
        grade = np.abs(np.diff(st["h"])) / np.maximum(np.diff(st["s"]), 0.1)
        worst[st["cls"]] = max(worst[st["cls"]], float(grade.max()))
    print("  nejvetsi sklon: " + ", ".join(f"{k} {v * 100:.0f} %" for k, v in sorted(worst.items())))
    low_clear = 99.0
    for c in crossings:
        up, low = streets[c["up"]], streets[c["low"]]
        hu = float(np.interp(c["s_up"], up["s"], up["h"]))
        hl = float(np.interp(c["s_low"], low["s"], low["h"]))
        low_clear = min(low_clear, hu - hl)
    print(f"  mimourovnovych krizeni {len(crossings)}, nejmensi vyska mostu nad silnici {low_clear:.1f} m")
    hs = np.array(list(node_h.values()))
    print(f"  vysky krizovatek: {hs.min():.0f} az {hs.max():.0f} m")
    return node_h


def build_heightmap(streets, lots, path):
    """Vyskova mapa terenu (mrizka 16 m): prirodni teren srovnany k silnicim. Ulozi se jako int16 po 2 cm."""
    tm = TERRAIN
    xs = tm["x0"] + np.arange(tm["nx"]) * tm["cell"]
    zs = tm["z0"] + np.arange(tm["nz"]) * tm["cell"]
    gx, gz = np.meshgrid(xs, zs)                      # [nz, nx]
    nat = terrain(gx, gz)
    fixed = np.full(nat.shape, np.inf)
    cell = tm["cell"]
    for st in streets:
        w = W[st["cls"]]
        rad = w + SIDEWALK + 24.0
        g = resample(st["geom"], 8.0)
        sg = stations(g)
        hh = np.interp(sg * (st["s"][-1] / max(sg[-1], 1e-6)), st["s"], st["h"])
        skip = np.zeros(len(g), dtype=bool)
        for a, b in st["mosty"]:
            skip |= (sg >= a - 2.0) & (sg <= b + 2.0)
        reach = int(rad // cell) + 1
        for (px, pz), ph, sk in zip(g, hh, skip):
            if sk:
                continue
            ix = int(round((px - tm["x0"]) / cell))
            iz = int(round((pz - tm["z0"]) / cell))
            x0, x1 = max(ix - reach, 0), min(ix + reach + 1, tm["nx"])
            z0, z1 = max(iz - reach, 0), min(iz + reach + 1, tm["nz"])
            if x0 >= x1 or z0 >= z1:
                continue
            dx = xs[x0:x1][None, :] - px
            dz = zs[z0:z1][:, None] - pz
            mask = dx * dx + dz * dz <= rad * rad
            sub = fixed[z0:z1, x0:x1]
            np.minimum(sub, np.where(mask, ph - 0.35, np.inf), out=sub)
    # volne plochy: teren pod urovni plochy (plocha ma vlastni povrch)
    for lot in lots:
        if lot["typ"] == "reka":
            continue
        poly = []
        low = 1e9
        for e, fwd, _ in lot["ulice"]:
            g = streets[e]["geom"] if fwd else streets[e]["geom"][::-1]
            poly.extend(g[:-1].tolist())
            low = min(low, float(streets[e]["h"].min()))
        poly = np.array(poly)
        x0 = max(int((poly[:, 0].min() - tm["x0"]) / cell), 0)
        x1 = min(int((poly[:, 0].max() - tm["x0"]) / cell) + 2, tm["nx"])
        z0 = max(int((poly[:, 1].min() - tm["z0"]) / cell), 0)
        z1 = min(int((poly[:, 1].max() - tm["z0"]) / cell) + 2, tm["nz"])
        px = gx[z0:z1, x0:x1]
        pz = gz[z0:z1, x0:x1]
        inside = np.zeros(px.shape, dtype=bool)
        for (ax, az), (bx, bz) in zip(poly, np.roll(poly, -1, axis=0)):
            cond = (az > pz) != (bz > pz)
            xi = ax + (pz - az) / np.where(bz - az == 0, 1e-9, bz - az) * (bx - ax)
            inside ^= cond & (px < xi)
        sub = fixed[z0:z1, x0:x1]
        np.minimum(sub, np.where(inside, low - 1.2, np.inf), out=sub)
    # koryto reky ma prednost (nabrezi je zed, ne svah)
    river_bed = np.abs(gz - river_z(gx)) < RIVER_HALF - 12.0
    fixed[river_bed] = WATER_LEVEL - 3.5
    is_fixed = np.isfinite(fixed)
    d_fixed = np.where(is_fixed, fixed - nat, 0.0)
    d = d_fixed.copy()
    c = (cell / 110.0) ** 2
    for _ in range(320):
        avg = np.zeros_like(d)
        avg[1:, :] += d[:-1, :]
        avg[:-1, :] += d[1:, :]
        avg[:, 1:] += d[:, :-1]
        avg[:, :-1] += d[:, 1:]
        avg[0, :] += d[0, :]
        avg[-1, :] += d[-1, :]
        avg[:, 0] += d[:, 0]
        avg[:, -1] += d[:, -1]
        d = np.where(is_fixed, d_fixed, avg / (4.0 + c))
    height = nat + d
    # maska povrchu: 255 = mestska dlazba, 0 = trava (kopce a okoli)
    r = np.hypot(gx, gz)
    v = r - r_perimeter(np.arctan2(gz, gx))
    mask = (255.0 * (1.0 - smooth(v, 20.0, 90.0))).astype(np.uint8)
    with open(path, "wb") as fh:
        fh.write(np.clip(np.round(height / 0.02), -32000, 32000).astype("<i2").tobytes())
        fh.write(mask.tobytes())
    print(f"  vyskova mapa {tm['nx']} x {tm['nz']} bodu, {os.path.getsize(path) / 1e6:.1f} MB, vysky {height.min():.0f} az {height.max():.0f} m")
    return height


# ---------------------------------------------------------------------------
def main():
    majors, river = build_majors()
    cache = "/tmp/claude-0/mesto_cache.pkl"
    use_cache = "--cache" in sys.argv and os.path.exists(cache)
    if not use_cache:
        cuts, crossings, grade = node_majors(majors)
        for a, b, p, ang, junction in crossings:
            if "magistrala" in (a, b):
                print(f"  magistrala x {b if a == 'magistrala' else a}: {'krizovatka' if junction else 'most/podjezd'}, uhel {ang:.0f} st u ({p[0]:.0f}, {p[1]:.0f})")
            if ang < (50.0 if junction else 32.0):
                print(f"  POZOR: tahy {a} x {b} se krizi pod uhlem {ang:.0f} st u ({p[0]:.0f}, {p[1]:.0f})")
        city = City()
        build_major_graph(city, majors, cuts, grade)
        n_major = len(city.pts)
        major_geom = local_points(city, majors, river)
        print(f"bodu: hlavni tahy {n_major}, mistni {len(city.pts) - n_major}")
        gabriel_edges(city, major_geom)
        print(f"useku po spojeni: {len(city.edges)}")
        prune(city)
        thin(city, {"stare": 0.10, "mesto": 0.16, "jih": 0.16, "mrizka": 0.0, "predmesti": 0.2, "prumysl": 0.12})
        prune(city)
        drop_dead_ends(city)

    if use_cache:
        import pickle
        with open(cache, "rb") as fh:
            city, nodes, streets = pickle.load(fh)
        print("sit ulic nactena z mezipameti")
    forced = set()
    for it in range(0 if use_cache else 60):
        nodes, streets = merge_chains(city, forced)
        extra = fix_parallel(streets)
        if extra - forced:
            forced |= extra
            continue
        victims, problems, trims = validate(city, nodes, streets)
        print(f"kolo {it}: krizovatek {len(nodes)}, ulic {len(streets)}, problemy {dict(problems)}")
        if not victims:
            break
        for v in victims:
            city.edges.pop(v, None)
        drop_dead_ends(city)
    else:
        if not use_cache:
            print("POZOR: sit se nepodarilo uplne procistit")
    if not use_cache and os.path.isdir("/tmp/claude-0"):
        import pickle
        with open(cache, "wb") as fh:
            pickle.dump((city, nodes, streets), fh)

    # --- Precislovani ---
    node_id = {n: k for k, n in enumerate(sorted(nodes))}
    pts = np.array(city.pts)
    total = 0.0
    by_class = defaultdict(float)
    for s in streets:
        s["len"] = polyline_length(s["geom"])
        total += s["len"]
        by_class[s["cls"]] += s["len"]
        s["ctvrt"] = district(s["geom"][len(s["geom"]) // 2])
    print(f"silnic celkem {total / 1000.0:.1f} km: " + ", ".join(f"{k} {v / 1000.0:.1f}" for k, v in sorted(by_class.items())))

    # --- Vysky, mosty, podjezdy ---
    crossings = find_grade_crossings(streets, majors)
    compute_spans(streets, crossings)
    node_h = solve_heights(nodes, streets, crossings)
    out_nodes = [[round(float(pts[n][0]), 2), round(float(pts[n][1]), 2), round(node_h[n], 2)] for n in sorted(nodes)]
    crossing_streets = {c["up"] for c in crossings} | {c["low"] for c in crossings}

    # --- Bloky ---
    faces = trace_faces(nodes, streets)
    lots = []
    areas = []
    for face in faces:
        poly = face_polygon(face, streets)
        area = polygon_area(poly)
        areas.append(area)
    outer = int(np.argmin(areas)) if abs(min(areas)) > abs(max(areas)) else int(np.argmax(areas))
    sign = -1.0 if areas[outer] > 0 else 1.0
    info = []
    for k, face in enumerate(faces):
        if k == outer:
            continue
        poly = face_polygon(face, streets)
        area = abs(areas[k])
        c = poly.mean(axis=0)
        in_river = np.mean(np.abs(poly[:, 1] - river_z(poly[:, 0])) < RIVER_HALF + 14.0)
        node_list = [streets[e]["a"] if f else streets[e]["b"] for e, f in face]
        simple = len(set(node_list)) == len(node_list) and len({e for e, _ in face}) == len(face) \
            and not any(e in crossing_streets or streets[e]["cls"] in ("magistrala", "horska") for e, _ in face)
        info.append({"k": k, "area": area, "c": c, "river": in_river, "simple": simple, "face": face, "poly": poly})

    def lot_entry(typ, f):
        # blok lezi vpravo od smeru chuze; strana +1 = vpravo ve smeru ulice od "a" do "b"
        side_fwd = 1 if areas[f["k"]] * 1.0 > 0 else -1
        # orientace: kladna plocha (v souradnicich x, z) = po smeru hodin pri pohledu shora
        return {"typ": typ, "ulice": [[int(e), bool(fw), int(side_fwd if fw else -side_fwd)] for e, fw in f["face"]],
                "stred": [round(float(f["c"][0]), 1), round(float(f["c"][1]), 1)], "plocha": round(f["area"])}

    used_faces = set()
    for f in info:
        if f["river"] > 0.9:
            lots.append(lot_entry("reka", f))
            used_faces.add(f["k"])
    land = [f for f in info if f["k"] not in used_faces and f["simple"]]

    def compact(f):
        per = polyline_length(np.concatenate([f["poly"], f["poly"][:1]]))
        return 4 * math.pi * f["area"] / (per * per)

    def pick(typ, target, lo, hi, count=1, min_compact=0.5):
        cands = [f for f in land if f["k"] not in used_faces and lo <= f["area"] <= hi and compact(f) >= min_compact]
        cands.sort(key=lambda f: np.linalg.norm(f["c"] - np.array(target)))
        for f in cands[:count]:
            lots.append(lot_entry(typ, f))
            used_faces.add(f["k"])
            print(f"  plocha {typ}: {f['area'] / 10000.0:.1f} ha u ({f['c'][0]:.0f}, {f['c'][1]:.0f})")

    pick("namesti", (0, -60), 7000, 30000)
    pick("trenink", (700, 250), 45000, 160000, min_compact=0.55)          # blizko centra (start hry)
    pick("trenink", (1500, 1900), 70000, 260000, min_compact=0.55)        # prumyslova ctvrt
    pick("trenink", (-1900, -1300), 60000, 220000, min_compact=0.55)      # severozapadni predmesti
    for target in [(-1100, -500), (500, -1100), (1700, -700), (-800, 900), (900, 1300), (-2000, 600),
                   (2100, 400), (-300, -1900), (300, 2000), (-1500, 1700), (1900, -1700), (-400, 400)]:
        pick("plocha", target, 9000, 45000, min_compact=0.45)

    # --- Okruhy ---
    node_pos = {n: pts[n] for n in nodes}
    circuits = []
    hw = [k for k, s in enumerate(streets) if s["cls"] == "dalnice"]
    c1 = make_circuit("Centrum", [(-560, -280), (120, -640), (640, -130), (560, 200), (330, 60), (0, 0), (-330, 80)],
                      node_pos, streets, {"bulvar": 0.8, "nabrezi": 0.85, "ulicka": 1.0, "ulice": 1.1, "dalnice": 3.0})
    c2 = make_circuit("Nabrezi", [(-1500, 330), (-600, 170), (500, 200), (1500, 360), (1500, 560), (500, 370), (-600, 340), (-1500, 520)],
                      node_pos, streets, {"nabrezi": 0.5, "bulvar": 0.9, "dalnice": 3.0})
    c3 = ring_circuit("Dalnice", "dalnice", streets)
    c4 = make_circuit("Velky okruh", [(-560, -280), (-1250, -650), (-330, -1360), (760, -1150), (1400, -500), (640, -130), (330, 60), (-330, 80)],
                      node_pos, streets, {"bulvar": 0.75, "nabrezi": 0.9, "dalnice": 3.0, "magistrala": 3.0})
    c5 = ring_circuit("Magistrala", "magistrala", streets)
    hw_pts = hill_to_world([(-215, 0), (165, 1520), (2650, 0), (1300, 0)])
    c6 = make_circuit("Kopce", [tuple(p) for p in hw_pts], node_pos, streets, {"horska": 0.4, "obvod": 0.7})
    for c in (c1, c2, c3, c4, c5, c6):
        if c:
            # start na nejdelsi ulici okruhu (rovinka pro rozjezd)
            k = max(range(len(c["ulice"])), key=lambda i: streets[c["ulice"][i][0]]["len"])
            c["ulice"] = c["ulice"][k:] + c["ulice"][:k]
            circuits.append(c)
            print(f"  okruh {c['nazev']}: {c['delka'] / 1000.0:.1f} km, {len(c['ulice'])} ulic")

    data = {
        "popis": "Plan mesta - vygenerovano skriptem tools/generuj_mesto.py (neupravovat rucne, zmeny delat ve skriptu)",
        "polomer": R0,
        "uzly": out_nodes,
        "ulice": [{"a": node_id[s["a"]], "b": node_id[s["b"]], "trida": s["cls"], "w": W[s["cls"]], "ctvrt": s["ctvrt"],
                   "mosty": [[round(a, 1), round(b, 1)] for a, b in s["mosty"]],
                   "podjezdy": [[round(a, 1), round(b, 1)] for a, b in s["podjezdy"]],
                   "body": [[round(float(p[0]), 2), round(float(p[1]), 2), round(float(y), 2)] for p, y in zip(s["geom"], s["h"])]} for s in streets],
        "plochy": lots,
        "okruhy": circuits,
        "reka": [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in river[::8] if math.hypot(p[0], p[1]) < R0 * 1.25],
        "teren": dict(TERRAIN, soubor="teren.bin", voda=WATER_LEVEL),
    }
    build_heightmap(streets, lots, os.path.join(os.path.dirname(OUT), "teren.bin"))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print(f"ulozeno {OUT} ({os.path.getsize(OUT) / 1024.0:.0f} kB): {len(out_nodes)} krizovatek, {len(streets)} ulic, {len(lots)} ploch")

    images = [a for a in sys.argv[1:] if not a.startswith("--")]
    if images:
        preview(images[0], data)


def preview(path, data):
    from PIL import Image, ImageDraw
    size = 2600
    scale = size / 12800.0

    def tr(p):
        return (size / 2 + p[0] * scale, size / 2 + (p[1] + 900.0) * scale)

    im = Image.new("RGB", (size, size), (18, 20, 28))
    dr = ImageDraw.Draw(im)
    colors = {"reka": (30, 70, 130), "trenink": (90, 90, 40), "plocha": (60, 75, 60), "namesti": (110, 80, 50)}
    for lot in data["plochy"]:
        poly = []
        for e, fwd, _ in lot["ulice"]:
            body = data["ulice"][e]["body"]
            body = body if fwd else body[::-1]
            poly.extend(tr(p) for p in body[:-1])
        dr.polygon(poly, fill=colors[lot["typ"]])
    style = {"magistrala": ((255, 90, 90), 5), "horska": ((140, 230, 140), 3), "dalnice": ((255, 170, 60), 5), "bulvar": ((235, 235, 245), 4), "obvod": ((200, 200, 215), 3), "nabrezi": ((150, 200, 255), 3),
             "trida": ((190, 170, 150), 2), "ulice": ((150, 155, 170), 2), "ulicka": ((170, 150, 190), 1)}
    for s in sorted(data["ulice"], key=lambda s: PRIORITY[s["trida"]]):
        col, wd = style[s["trida"]]
        dr.line([tr(p) for p in s["body"]], fill=col, width=wd)
    ccol = [(0, 230, 255), (255, 80, 200), (120, 255, 120), (255, 255, 80)]
    for k, c in enumerate(data["okruhy"]):
        for e, fwd in c["ulice"]:
            dr.line([tr(p) for p in data["ulice"][e]["body"]], fill=ccol[k % 4], width=2)
    im.save(path)


if __name__ == "__main__":
    main()
