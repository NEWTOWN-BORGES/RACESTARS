"""
RACESTARS — gera o MAPA da corrida (6 x 6 km, de A até B, ~18 km de percurso).

Uso:  python tools/make_map.py        (precisa de numpy, scipy, pillow e zstandard)

Gera em game/assets/map/:
  height.zst    alturas em "células" (metros / 4), float16, 1537 x 1537, linha = z, coluna = x (zstd)
  biome.zst     mapa de biomas RGBA8 768 x 768 (R relva, G selva/musgo, B rocha vermelha, A calcário branco) (zstd)
  map.json      portões, caminhos (por nível), túneis, pontes, aqueduto, lago, peças, vegetação
  minimap.png   mapa visto de cima

A corrida tem 8 trechos entre portões. Em cada trecho há caminhos alternativos em níveis
diferentes (subterrâneo, chão, alto, água) e o jogador escolhe o melhor:
  A  deserto: estrada com dunas OU crista de areia com fendas para saltar
  B  colinas verdes: vale à volta OU túnel por baixo OU topo da colina com fendas e ruínas
  C  lago: estrada da margem OU caminho de pedra sobre a água (OU a direito pela água, mais lento)
  D  desfiladeiro de arenito: leito com curvas apertadas OU beira de cima com pontes e um salto
  E  abismo e dunas: salto do abismo OU desvio pela ponta
  F  selva e cenote: estrada da selva OU gruta + cenote OU ponte partida por cima do cenote
  G  prado: estrada entre ruínas OU tubo subterrâneo OU por cima do aqueduto (com falha para saltar)
  H  fenda vermelha com teto OU por cima com saltos -> META
"""
import json, math, os
import numpy as np
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter, gaussian_filter1d
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'game', 'assets', 'map'))
SIZE, RES = 6144.0, 1537
CELL = SIZE / (RES - 1)
HALF = SIZE / 2
GROUND = 4.0
WATER_Y = 0.0
FALL_Y = -34.0
ROAD_HW = 42.0                   # estradas largas: 84 m
CENTER = np.array([100.0, 0.0])
rng = np.random.default_rng(11)

# ------------------------------------------------------------------ ruído
_perm = rng.permutation(512)
def _vnoise(x, z):
    xi = np.floor(x).astype(np.int64); zi = np.floor(z).astype(np.int64)
    fx = x - xi; fz = z - zi
    u = fx * fx * (3 - 2 * fx); v = fz * fz * (3 - 2 * fz)
    def h(a, b):
        return _perm[(_perm[a & 511] + b) & 511] / 511.0
    return (h(xi, zi) * (1 - u) + h(xi + 1, zi) * u) * (1 - v) + (h(xi, zi + 1) * (1 - u) + h(xi + 1, zi + 1) * u) * v

def fbm(x, z, oct=5):
    s = np.zeros_like(x, dtype=np.float32); a = 0.5; f = 1.0; n = 0.0
    for i in range(oct):
        s += a * _vnoise(x * f + i * 17.3, z * f - i * 9.1); n += a; a *= 0.5; f *= 2.03
    return s / n

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

# ------------------------------------------------------------------ grelha e terreno base
xs = np.linspace(-HALF, HALF, RES).astype(np.float32)
X, Z = np.meshgrid(xs, xs)                    # linhas = z, colunas = x
dunes = 4.5 * fbm(X / 240, Z / 240) + 2.0 * (np.sin((X * 0.6 + Z * 0.8) / 34 + fbm(X / 90, Z / 90) * 7) * 0.5 + 0.5)
H = (GROUND - 2.5 + dunes).astype(np.float32)
# maciço central (com ilhas flutuantes por cima, visível de todo o lado)
mr = np.hypot((X - CENTER[0]) / 1300, (Z - CENTER[1]) / 1200) + 0.16 * (fbm(X / 420 + 3, Z / 420) - 0.5)
massif = smooth(1.0, 0.88, mr)
mh = 105 + 70 * fbm(X / 520 + 5, Z / 520) + 25 * smooth(0.55, 0.6, fbm(X / 260, Z / 260 + 4))
H = H + (mh - H) * massif
# montanhas na borda
edge = np.maximum(np.abs(X), np.abs(Z))
H = H + (165 + 30 * fbm(X / 130, Z / 130) - H) * smooth(2880, 3010, edge)

def sample(P):
    fx = (P[:, 0] + HALF) / CELL; fz = (P[:, 1] + HALF) / CELL
    i = np.clip(np.floor(fx).astype(int), 0, RES - 2); j = np.clip(np.floor(fz).astype(int), 0, RES - 2)
    u = fx - i; v = fz - j
    return H[j, i] * (1 - u) * (1 - v) + H[j, i + 1] * u * (1 - v) + H[j + 1, i] * (1 - u) * v + H[j + 1, i + 1] * u * v

def height_at(x, z):
    return float(sample(np.array([[x, z]]))[0])

def grid_box(xmin, xmax, zmin, zmax):
    i0 = max(0, int((xmin + HALF) / CELL)); i1 = min(RES, int((xmax + HALF) / CELL) + 2)
    j0 = max(0, int((zmin + HALF) / CELL)); j1 = min(RES, int((zmax + HALF) / CELL) + 2)
    return slice(j0, j1), slice(i0, i1)

# ------------------------------------------------------------------ caminhos
def catmull(points, step=2.0):
    P = np.array(points, dtype=float)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for k in range(n):
            t = k / n; t2 = t * t; t3 = t2 * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return np.array(out)

def yaw_of(dx, dz):  # yaw do Godot para que o "para frente" (-Z) aponte em (dx, dz)
    return float(math.atan2(-dx, -dz))

class Sec:
    def __init__(s, i, key, A, B, biome):
        s.i, s.key, s.biome = i, key, biome
        s.A = np.array(A, float); s.B = np.array(B, float)
        d = s.B - s.A; s.Ls = float(np.linalg.norm(d)); s.eu = d / s.Ls
        s.ev = np.array([-s.eu[1], s.eu[0]])
        o = 1.0 if np.dot(s.ev, (s.A + s.B) / 2 - CENTER) >= 0 else -1.0
        s.IN = -o                      # w positivo = para dentro (para o maciço)
        s.paths = []
    def W(s, u, w):
        return s.A + s.eu * u * s.Ls + s.ev * (s.IN * w)
    def UW(s, Xg, Zg):
        um = (Xg - s.A[0]) * s.eu[0] + (Zg - s.A[1]) * s.eu[1]
        vm = (Xg - s.A[0]) * s.ev[0] + (Zg - s.A[1]) * s.ev[1]
        return um, vm * s.IN
    def yaw(s):
        return yaw_of(s.eu[0], s.eu[1])

class Path:
    def __init__(p, sec, name, level, ctrl, hw, hfun=None, ground=False):
        p.sec, p.name, p.level, p.hw = sec, name, level, hw
        P = catmull([sec.W(u, w) for u, w in ctrl], 2.0)
        P[0] = sec.A; P[-1] = sec.B
        p.P = P
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        p.S = np.concatenate([[0], np.cumsum(seg)]); p.L = float(p.S[-1])
        p.u = ((P - sec.A) @ sec.eu) / sec.Ls
        t = np.gradient(P, axis=0); p.T = t / np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-6)
        if ground:   # segue o chão, suavizado
            h = np.clip(gaussian_filter1d(sample(P), 35, mode='nearest'), 2.5, 14.0)
        else:
            h = hfun(p.u).astype(float)
        we = smooth(0, 90, p.S) * smooth(0, 90, p.L - p.S)
        p.h = GROUND + (h - GROUND) * we          # altura a que se conduz
        p.ht = p.h.copy()                          # altura a que se esculpe o terreno
        p.jumps = []
        sec.paths.append(p)

    def s_at_u(p, u):
        return float(p.S[int(np.argmin(np.abs(p.u - u)))])

    def kicker(p, s0, rise=3.0, run=42.0, drop=6.0, terrain=True):
        """Rampa de salto: sobe em curva até ao lábio em s0 e cai a pique."""
        t = np.clip((p.S - (s0 - run)) / run, 0, 1)
        k = rise * t * t * (1 - np.clip((p.S - s0) / drop, 0, 1))
        p.h += k
        if terrain:
            p.ht += k
        p.jumps.append(float(s0))

    def at_s(p, s):
        i = int(np.argmin(np.abs(p.S - s)))
        return p.P[i], p.T[i], float(p.h[i])

class Line:
    """Corte reto auxiliar (fendas, abismo)."""
    def __init__(q, a, b, h, hw):
        a = np.array(a, float); b = np.array(b, float)
        n = max(2, int(np.linalg.norm(b - a) / 2))
        q.P = np.linspace(a, b, n); q.ht = np.full(n, h, float); q.hw = hw

def carve(p, shoulder, mode='set', hw=None):
    """Aproxima o terreno da altura do caminho (dentro de hw), com encosta de largura shoulder."""
    global H
    hw = p.hw if hw is None else hw
    P, ht = p.P, p.ht
    pad = hw + shoulder + 8
    sj, si = grid_box(P[:, 0].min() - pad, P[:, 0].max() + pad, P[:, 1].min() - pad, P[:, 1].max() + pad)
    Xs, Zs = X[sj, si], Z[sj, si]
    D, I = cKDTree(P).query(np.stack([Xs.ravel(), Zs.ravel()], 1), distance_upper_bound=pad, workers=-1)
    ok = np.isfinite(D)
    sub = H[sj, si].ravel().copy()
    cur = sub[ok]; tgt = ht[I[ok]]
    w = 1 - smooth(hw, hw + shoulder, D[ok])
    new = cur + (tgt - cur) * w
    if mode == 'cut': new = np.minimum(cur, new)
    elif mode == 'fill': new = np.maximum(cur, new)
    sub[ok] = new
    H[sj, si] = sub.reshape(Xs.shape)

def stamp_rect(sec, u0, u1, w0, w1, top, corner=90, edge=12, wobble=40, flat=False):
    """Planalto/colina de cantos redondos com paredões; top = altura absoluta."""
    global H
    um, wm = sec.UW(X, Z)
    cu = (u0 + u1) / 2 * sec.Ls; hu = (u1 - u0) / 2 * sec.Ls; cw = (w0 + w1) / 2; hwid = (w1 - w0) / 2
    qx = np.abs(um - cu) - hu + corner; qz = np.abs(wm - cw) - hwid + corner
    sdf = np.hypot(np.maximum(qx, 0), np.maximum(qz, 0)) + np.minimum(np.maximum(qx, qz), 0) - corner
    sdf = sdf + wobble * (fbm(X / 160 + sec.i * 7, Z / 160) - 0.5)
    m = 1 - smooth(-edge, 0, sdf)
    t = top if flat else top + 4 * (fbm(X / 90 + 2, Z / 90) - 0.5)
    H = np.maximum(H, H + (t - H) * m)

def crossings(a, b, tol=3.0):
    """Índices de a onde o caminho a cruza o caminho b."""
    d, _ = cKDTree(b.P).query(a.P)
    out, i = [], 0
    while i < len(d):
        if d[i] < tol:
            j = i
            while j + 1 < len(d) and d[j + 1] < tol * 3:
                j += 1
            out.append(i + int(np.argmin(d[i:j + 1]))); i = j + 1
        i += 1
    return out

def cross_angle(a, k, b):
    _, j = cKDTree(b.P).query(a.P[k])
    return abs(math.asin(max(-1.0, min(1.0, float(np.cross(a.T[k], b.T[j]))))))

# ------------------------------------------------------------------ trechos
HUBS = [(-2350, 2450), (-2400, 850), (-2250, -1250), (-450, -2380), (1500, -2280),
        (2420, -480), (2330, 1380), (700, 2330), (-1050, 1550)]
KEYS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']
BIOMES = {'A': 'desert', 'B': 'meadow', 'C': 'coast', 'D': 'sandstone', 'E': 'desert', 'F': 'jungle', 'G': 'meadow', 'H': 'red'}
TITLES = {'A': 'Deserto das Dunas', 'B': 'Colinas Verdes', 'C': 'Lago do Caminho de Pedra', 'D': 'Desfiladeiro de Arenito',
          'E': 'Abismo', 'F': 'Selva do Cenote', 'G': 'Prado do Aqueduto', 'H': 'Fenda Vermelha'}
secs = [Sec(i, k, HUBS[i], HUBS[i + 1], BIOMES[k]) for i, k in enumerate(KEYS)]

# chão plano à volta de cada portão (antes dos trechos, para os caminhos partirem dele)
for hub in HUBS:
    d = np.hypot(X - hub[0], Z - hub[1])
    H = H + (GROUND - H) * (1 - smooth(70, 150, d))

tunnels, bridges, aqueducts, lakes, props, extra = [], [], [], [], [], {}

def add_prop(name, x, z, yaw, sc, sink=1.0, y=None):
    props.append([name, round(float(x), 2), round(float((height_at(x, z) if y is None else y) - sink), 2), round(float(z), 2),
                  round(float(yaw), 3), round(float(sc), 3)])

def tunnel(sec, p, u0, u1, top, name):
    """Bloco de túnel (modelado no Blender) entre u0 e u1 do caminho p; tampa à altura 'top'."""
    s0, s1 = p.s_at_u(u0), p.s_at_u(u1)
    a, _, h0 = p.at_s(s0)
    b, _, _ = p.at_s(s1)
    t = (b - a) / np.linalg.norm(b - a)       # direção da corda (o túnel é reto)
    tunnels.append({'name': name, 'p': [float(a[0]), float(h0), float(a[1])], 'yaw': yaw_of(t[0], t[1]),
                    'len': float(np.linalg.norm(b - a)), 'height': float(top - h0)})

def bridge(p, s, length, name, deck=None, broken=0.0, width=30.0, deep=46.0):
    c, t, h = p.at_s(s)
    deck = h if deck is None else deck
    start = c - t * length / 2
    bridges.append({'name': name, 'p': [float(start[0]), float(deck), float(start[1])], 'yaw': yaw_of(t[0], t[1]),
                    'len': float(length), 'width': float(width), 'broken': float(broken), 'deep': float(deep)})

# A — deserto: estrada com dunas OU crista de areia com fendas -----------------------------
def sec_A(s):
    road = Path(s, 'estrada das dunas', 1, [(0, 0), (0.12, 0), (0.3, -110), (0.5, 90), (0.7, -100), (0.88, 40), (1, 0)], ROAD_HW, ground=True)
    for f in (0.36, 0.55, 0.74):
        road.kicker(f * road.L, rise=3.0)
    ridge = Path(s, 'crista de areia', 2, [(0, 0), (0.06, 80), (0.16, 230), (0.3, 270), (0.7, 270), (0.84, 230), (0.94, 80), (1, 0)], 20,
                 hfun=lambda u: GROUND + 20 * smooth(0.04, 0.18, u) * (1 - smooth(0.82, 0.96, u)))
    gaps = [0.38, 0.52, 0.66]
    for g in gaps:
        ridge.kicker(ridge.s_at_u(g) - 28, rise=2.0, run=30)
    carve(road, 60)
    carve(ridge, 38, 'fill')
    for g in gaps:  # fendas na crista (quem cai continua cá em baixo)
        c, t, _ = ridge.at_s(ridge.s_at_u(g)); n = np.array([-t[1], t[0]])
        carve(Line(c - n * 70, c + n * 70, GROUND + 1, 22), 6, 'cut')
    extra.setdefault('arches_over', []).extend([(road, 0.22, 'arch_giant', 1.6), (road, 0.62, 'arch_giant', 1.6), (road, 0.9, 'arch_giant', 1.7)])

# B — colinas verdes: vale / túnel / topo com fendas e ruínas -----------------------------
def sec_B(s):
    TOP = 58.0
    stamp_rect(s, 0.27, 0.77, -290, 210, TOP, corner=110, edge=10, wobble=50, flat=True)
    tun = Path(s, 'túnel da colina', 0, [(0, 0), (0.12, 0), (0.5, 0), (0.88, 0), (1, 0)], 19,
               hfun=lambda u: GROUND + (-4 - GROUND) * smooth(0.12, 0.27, u) * (1 - smooth(0.77, 0.9, u)))
    valley = Path(s, 'vale das colinas', 1, [(0, 0), (0.1, 150), (0.28, 360), (0.5, 400), (0.72, 360), (0.9, 150), (1, 0)], ROAD_HW, ground=True)
    valley.kicker(0.42 * valley.L); valley.kicker(0.6 * valley.L)
    def hh(u):
        return np.where(u < 0.778, GROUND + (TOP - GROUND) * smooth(0.04, 0.27, u), GROUND + 1)
    hill = Path(s, 'topo da colina', 2, [(0, 0), (0.05, -30), (0.14, -120), (0.27, -150), (0.5, -150), (0.77, -150), (0.86, -90), (0.94, -30), (1, 0)], 30, hfun=hh)
    hill.kicker(hill.s_at_u(0.775), rise=2.5, run=40)
    crev = [0.42, 0.62]
    hill.kicker(hill.s_at_u(crev[1]) - 40, rise=2.0, run=34)
    carve(hill, 26)
    for g in crev:  # fendas que atravessam a colina (quem cai sai pelo vale)
        c, t, _ = hill.at_s(hill.s_at_u(g))
        uu = float((c - s.A) @ s.eu) / s.Ls
        carve(Line(s.W(uu, -340), s.W(uu, -85), GROUND + 1, 30), 7, 'cut')
    bridge(hill, hill.s_at_u(crev[0]), 110, 'ponte_b', deck=TOP)
    carve(tun, 12, 'set')
    tunnel(s, tun, 0.27, 0.77, TOP, 'tunel_b')
    carve(valley, 60)
    extra['b_hill'] = (hill, TOP)

# C — lago: margem / caminho de pedra / água ---------------------------------------------
def sec_C(s):
    global H
    lc = s.W(0.5, -150); ru, rv = 0.37 * s.Ls, 330.0
    um, wm = s.UW(X, Z)
    r = np.hypot((um - 0.5 * s.Ls) / ru, (wm + 150) / rv) + 0.1 * (fbm(X / 200, Z / 200) - 0.5)
    tgt = WATER_Y - 1.0 - 10 * smooth(1.0, 0.6, r)
    w = 1 - smooth(1.0, 1.2, r)
    H = np.minimum(H, H + (tgt - H) * w)
    lakes.append({'c': [float(lc[0]), float(lc[1])], 'r': float(max(ru, rv) * 1.3), 'y': WATER_Y})
    stamp_rect(s, 0.15, 0.85, -720, -540, 38, corner=120, edge=16, wobble=80)   # penhascos brancos do lado de fora
    shore = Path(s, 'margem do lago', 1, [(0, 0), (0.12, 200), (0.3, 310), (0.5, 330), (0.7, 310), (0.88, 200), (1, 0)], ROAD_HW, ground=True)
    shore.kicker(0.5 * shore.L)
    gaps = [(0.37, 0.39), (0.6, 0.62)]
    def ch(u):
        h = GROUND + (1.6 - GROUND) * smooth(0.08, 0.16, u) * (1 - smooth(0.84, 0.92, u))
        for a, b in gaps:
            h = np.where((u > a) & (u < b), -5.0, h)
        return h
    cw = Path(s, 'caminho de pedra', 3, [(0, 0), (0.5, 0), (1, 0)], 14, hfun=ch)
    cw.h = np.maximum(cw.h, WATER_Y)     # nas falhas do caminho conduz-se por cima da água
    carve(shore, 60)
    carve(cw, 5)
    extra['c_lake'] = (s, lc)
    extra.setdefault('arches_over', []).extend([(cw, 0.3, 'arch_giant', 0.95), (cw, 0.5, 'arch_giant', 0.95), (cw, 0.72, 'arch_giant', 0.95)])

# D — desfiladeiro de arenito: leito com ganchos / beira com pontes e salto -------------
def sec_D(s):
    TOP = 56.0
    stamp_rect(s, 0.07, 0.93, -380, 380, TOP, corner=140, edge=10, wobble=60)
    us = np.linspace(0, 1, 60)
    taper = smooth(0.06, 0.13, us) * (1 - smooth(0.87, 0.94, us))
    ctrl = [(float(u), float(200 * math.sin(2 * math.pi * (u - 0.07) / 0.29) * t)) for u, t in zip(us, taper)]
    canyon = Path(s, 'leito do desfiladeiro', 0, ctrl, 34, hfun=lambda u: np.full_like(u, GROUND))
    rim = Path(s, 'beira do desfiladeiro', 2, [(0, 0), (0.04, -60), (0.1, -150), (0.17, -80), (0.24, 0), (0.5, 0), (0.86, 0), (0.92, 0), (1, 0)], 28,
               hfun=lambda u: np.where(u < 0.926, GROUND + (TOP - GROUND) * smooth(0.0, 0.17, u), GROUND + 1))
    rim.kicker(rim.s_at_u(0.924), rise=2.5, run=40)
    xs_ = [k for k in crossings(rim, canyon) if 0.2 < rim.u[k] < 0.9]
    for n, k in enumerate(xs_):
        a = max(cross_angle(rim, k, canyon), 0.35)
        half = (34 + 10) / math.sin(a)
        if n == 1:   # este cruzamento não tem ponte: salta-se
            rim.kicker(float(rim.S[k]) - half - 3, rise=3.0, run=40)
        else:
            bridge(rim, float(rim.S[k]), 2 * half + 44, f'ponte_d{n}', deck=TOP)
    carve(rim, 30)
    carve(canyon, 10, 'set')
    extra['d_rim'] = (rim, TOP)

# E — abismo + dunas ---------------------------------------------------------------------
def sec_E(s):
    road = Path(s, 'salto do abismo', 1, [(0, 0), (0.12, 0), (0.3, 60), (0.42, 0), (0.55, -90), (0.72, 80), (0.88, -40), (1, 0)], ROAD_HW, ground=True)
    det = Path(s, 'desvio do abismo', 1, [(0, 0), (0.12, 0), (0.24, -200), (0.33, -480), (0.43, -200), (0.55, -90), (0.72, 80), (0.88, -40), (1, 0)],
               ROAD_HW, ground=True)
    s_ch = road.s_at_u(0.33)
    c, t, _ = road.at_s(s_ch)
    road.kicker(s_ch - 26, rise=9.0, run=90, drop=8)
    for p in (road, det):
        for f in (0.62, 0.7, 0.78, 0.86):
            p.kicker(p.s_at_u(f), rise=3.0)
    carve(road, 60); carve(det, 60)
    n = np.array([-t[1], t[0]])
    carve(Line(c - n * 370, c + n * 370, -48.0, 21), 5, 'cut')

# F — selva e cenote ---------------------------------------------------------------------
def sec_F(s):
    global H
    FLOOR = -20.0
    pc = s.W(0.5, 0)
    jungle = Path(s, 'estrada da selva', 1, [(0, 0), (0.1, 160), (0.3, 280), (0.5, 330), (0.7, 280), (0.9, 160), (1, 0)], ROAD_HW, ground=True)
    jungle.kicker(0.35 * jungle.L); jungle.kicker(0.68 * jungle.L)
    top = Path(s, 'ponte do cenote', 1, [(0, 0), (0.04, -70), (0.17, -75), (0.25, 0), (0.43, 0), (0.57, 0), (0.75, 0), (0.83, -75), (0.96, -70), (1, 0)], 24,
               hfun=lambda u: np.full_like(u, GROUND))
    under = Path(s, 'gruta do cenote', 0, [(0, 0), (0.06, 0), (0.2, 0), (0.23, 0), (0.4, 0), (0.432, 0), (0.48, 38), (0.52, 38),
                                           (0.568, 0), (0.6, 0), (0.77, 0), (0.8, 0), (0.94, 0), (1, 0)], 19,
                 hfun=lambda u: GROUND + (FLOOR - GROUND) * smooth(0.05, 0.2, u) * (1 - smooth(0.8, 0.95, u)))
    carve(jungle, 60)
    carve(top, 30)
    d = np.hypot(X - pc[0], Z - pc[1]) + 12 * (fbm(X / 50, Z / 50) - 0.5)   # cenote: poço redondo
    H = H + (FLOOR - H) * (1 - smooth(100, 128, d))
    carve(under, 12, 'set')
    tunnel(s, under, 0.2, 0.432, GROUND, 'tunel_f1')
    tunnel(s, under, 0.568, 0.8, GROUND, 'tunel_f2')
    # laje fina à medida do poço: as pontas não podem tapar as bocas do túnel por baixo
    bridge(top, top.s_at_u(0.5), 0.136 * s.Ls, 'ponte_f', deck=GROUND, broken=44.0, width=26.0, deep=0.0)
    extra['f_cenote'] = (pc, FLOOR)

# G — prado: estrada das ruínas / tubo / aqueduto ----------------------------------------
def sec_G(s):
    DECK = 20.0
    meadow = Path(s, 'estrada das ruínas', 1, [(0, 0), (0.12, 150), (0.3, 90), (0.45, 220), (0.6, 100), (0.78, 210), (0.9, 120), (1, 0)], ROAD_HW, ground=True)
    meadow.kicker(0.35 * meadow.L); meadow.kicker(0.7 * meadow.L)
    tube = Path(s, 'tubo subterrâneo', 0, [(0, 0), (0.5, 0), (1, 0)], 19,
                hfun=lambda u: GROUND + (-18 - GROUND) * smooth(0.06, 0.18, u) * (1 - smooth(0.82, 0.94, u)))
    aq = Path(s, 'aqueduto', 2, [(0, 0), (0.025, -120), (0.055, -170), (0.16, -170), (0.84, -170), (0.945, -170), (0.975, -120), (1, 0)], 10,
              hfun=lambda u: GROUND + DECK * smooth(0.06, 0.16, u) * (1 - smooth(0.84, 0.94, u)))
    a0 = s.W(0.16, -170); a1 = s.W(0.84, -170)
    L = float(np.linalg.norm(a1 - a0)); nseg = int(L // 40); t = (a1 - a0) / L
    su = (aq.P - a0) @ t
    on_deck = (su >= 0) & (su <= nseg * 40)
    aq.h = np.where(on_deck, GROUND + DECK, aq.h)
    aq.ht = np.where((su >= -6) & (su <= nseg * 40 + 6), GROUND, aq.h)
    gap = [nseg // 2 - 1, nseg // 2]
    in_gap = (su > gap[0] * 40) & (su < (gap[-1] + 1) * 40)
    aq.h = np.where(in_gap, GROUND, aq.h)        # na falha cai-se para o prado
    aq.jumps.append(float(aq.S[int(np.argmin(np.abs(su - gap[0] * 40)))]))
    aqueducts.append({'p': [float(a0[0]), GROUND, float(a0[1])], 'yaw': yaw_of(t[0], t[1]), 'n': nseg, 'seg': 40.0, 'deck': DECK, 'missing': gap})
    carve(meadow, 60)
    carve(aq, 24, hw=24)          # rampas largas (o tabuleiro tem 20 m)
    carve(tube, 12, 'set')
    tunnel(s, tube, 0.18, 0.44, GROUND, 'tunel_g1')
    tunnel(s, tube, 0.54, 0.82, GROUND, 'tunel_g2')
    extra['g_tower'] = s.W(0.5, 360)

# H — fenda vermelha com teto / por cima com saltos -> META ------------------------------
def sec_H(s):
    TOP = 64.0
    stamp_rect(s, 0.08, 0.86, -330, 330, TOP, corner=120, edge=9, wobble=60)
    slot = Path(s, 'fenda vermelha', 0, [(0, 0), (0.08, 0), (0.2, 140), (0.34, -120), (0.48, 110), (0.62, -100), (0.76, 60), (0.86, 0), (1, 0)], 22,
                hfun=lambda u: np.full_like(u, GROUND))
    rim = Path(s, 'por cima da fenda', 2, [(0, 0), (0.04, -80), (0.12, -160), (0.2, -70), (0.3, 0), (0.6, 0), (0.84, 0), (0.93, 0), (1, 0)], 28,
               hfun=lambda u: np.where(u < 0.858, GROUND + (TOP - GROUND) * smooth(0.0, 0.18, u), GROUND + 1))
    rim.kicker(rim.s_at_u(0.856), rise=2.5, run=40)
    for k in crossings(rim, slot):
        if 0.2 < rim.u[k] < 0.85:
            a = max(cross_angle(rim, k, slot), 0.35)
            rim.kicker(float(rim.S[k]) - (22 + 6) / math.sin(a) - 3, rise=2.5, run=36)
    carve(rim, 30)
    carve(slot, 6, 'set')
    ir = int(np.argmin(np.abs(slot.u - 0.55)))
    extra['roof'] = {'p': [float(slot.P[ir, 0]), float(slot.h[ir]), float(slot.P[ir, 1])], 'yaw': yaw_of(slot.T[ir, 0], slot.T[ir, 1])}

for s in secs:
    {'A': sec_A, 'B': sec_B, 'C': sec_C, 'D': sec_D, 'E': sec_E, 'F': sec_F, 'G': sec_G, 'H': sec_H}[s.key](s)
    print(f'trecho {s.key}: {s.Ls:.0f} m  ' + ' | '.join(f'{p.name} ({p.L:.0f} m)' for p in s.paths))

# ------------------------------------------------------------------ biomas
B_CH = {'desert': (0, 0, 0, 0), 'meadow': (1, 0, 0, 0.9), 'coast': (0.9, 0, 0, 1), 'sandstone': (0.25, 0, 0, 0.45),
        'jungle': (0.55, 1, 0, 0.35), 'red': (0, 0, 1, 0)}
allP = np.vstack([p.P for s in secs for p in s.paths])
allS = np.concatenate([np.full(len(p.P), s.i) for s in secs for p in s.paths])
path_hw = np.concatenate([np.full(len(p.P), p.hw) for s in secs for p in s.paths])
path_tree = cKDTree(allP)
STEP = 2
Xd, Zd = X[::STEP, ::STEP], Z[::STEP, ::STEP]
grid_pts = np.stack([Xd.ravel(), Zd.ravel()], 1)
_, I = path_tree.query(grid_pts, workers=-1)
sec_id = allS[I].reshape(Xd.shape)
biome = np.zeros(Xd.shape + (4,), np.float32)
for s in secs:
    biome[sec_id == s.i] = B_CH[s.biome]
biome = gaussian_filter(biome, sigma=(22, 22, 0))
md = massif[::STEP, ::STEP]
biome = biome * (1 - md[..., None]) + np.array([0.75, 0.2, 0.0, 1.0], np.float32) * md[..., None]
road_d, _ = cKDTree(np.vstack([p.P for s in secs for p in s.paths if p.level == 1])).query(grid_pts, workers=-1)
road = (1 - smooth(18, 34, road_d)).reshape(Xd.shape)          # caminhos de terra nas zonas verdes
biome[..., 0] *= 1 - 0.85 * road
biome[..., 1] *= 1 - 0.85 * road
beach = 1 - smooth(WATER_Y + 1.5, WATER_Y + 5, H[::STEP, ::STEP])  # praia sem relva
biome[..., 0] *= 1 - beach; biome[..., 1] *= 1 - beach
cw_path = [p for s in secs for p in s.paths if p.level == 3][0]
cd, _ = cKDTree(cw_path.P).query(grid_pts, workers=-1)
stone = (1 - smooth(12, 16, cd)).reshape(Xd.shape)              # caminho de pedra branca
biome[..., 3] = np.maximum(biome[..., 3], stone)
biome[..., 0] *= 1 - stone
biome = np.clip(biome, 0, 1)
biome8 = (biome[:768, :768] * 255).astype(np.uint8)

def biome_at(x, z):
    i = int(np.clip((x + HALF) / (CELL * STEP), 0, biome.shape[1] - 1)); j = int(np.clip((z + HALF) / (CELL * STEP), 0, biome.shape[0] - 1))
    return biome[j, i]

def slope_at(x, z):
    e = 4.0
    dx = height_at(x + e, z) - height_at(x - e, z); dz = height_at(x, z + e) - height_at(x, z - e)
    return math.hypot(dx, dz) / (2 * e)

def free_of_paths(x, z, margin):
    for i in path_tree.query_ball_point([x, z], 220):
        if math.hypot(allP[i, 0] - x, allP[i, 1] - z) < path_hw[i] + margin:
            return False
    return True

def in_tunnel(x, z):
    for t in tunnels:
        f = np.array([-math.sin(t['yaw']), -math.cos(t['yaw'])])
        rel = np.array([x - t['p'][0], z - t['p'][2]])
        a = rel @ f; b = rel @ np.array([-f[1], f[0]])
        if 0 < a < t['len'] and abs(b) < 25:
            return True
    return False

# ------------------------------------------------------------------ peças
for p, f, name, sc in extra.get('arches_over', []):   # arcos por cima dos caminhos
    c, t, h = p.at_s(f * p.L)
    add_prop(name, c[0], c[1], yaw_of(t[0], t[1]), sc, 0.5, y=h)

# obstáculos dentro dos caminhos (é preciso desviar); nos caminhos estreitos são menos e mais pequenos
OBST = {'desert': ['boulder_a', 'boulder_b', 'rock_spire_b', 'rock_spire_a'], 'meadow': ['ruin_column', 'boulder_a', 'boulder_b'],
        'coast': ['rock_spire_b', 'boulder_b', 'ruin_column'], 'sandstone': ['boulder_a', 'boulder_b', 'rock_spire_b'],
        'jungle': ['crystals_cyan', 'crystals_mag', 'boulder_a', 'tree_mushroom'], 'red': ['boulder_b', 'rock_spire_a', 'rock_spire_c']}
for s in secs:
    for p in s.paths:
        if p.level == 3:
            continue
        wide = p.hw >= 40
        d = 260.0
        while d < p.L - 240:
            c, t, h = p.at_s(d)
            if not any(abs(d - j) < 220 for j in p.jumps) and abs(h - height_at(c[0], c[1])) < 1.5:
                n = np.array([-t[1], t[0]])
                q = c + n * float(rng.uniform(0.2, 0.6 if wide else 0.5) * p.hw * rng.choice([-1, 1]))
                if in_tunnel(q[0], q[1]):   # dentro dos túneis: cristais que brilham (vêem-se no escuro)
                    name, sc = str(rng.choice(['crystals_cyan', 'crystals_mag'])), float(rng.uniform(0.9, 1.2))
                elif wide:
                    name = str(rng.choice(OBST[s.biome])); sc = float(rng.uniform(0.6, 0.95))
                    if name.startswith('tree'):
                        sc = float(rng.uniform(1.0, 1.4))
                else:
                    name, sc = str(rng.choice(['boulder_a', 'boulder_b'])), float(rng.uniform(0.45, 0.7))
                add_prop(name, q[0], q[1], float(rng.uniform(-3, 3)), sc, 0.8)
            d += (170.0 if wide else 330.0) * float(rng.uniform(0.8, 1.3))

# espalhadas pelo mapa, conforme o bioma
SCATTER = {
    'desert': [('rock_spire_a', 3), ('rock_spire_b', 3), ('rock_spire_c', 2), ('boulder_a', 2), ('boulder_b', 2), ('arch', 2),
               ('arch_giant', 1.2), ('arch_twin', 1), ('rock_ring', 1), ('rock_fin', 1.5), ('butte', 0.7), ('mesa', 0.6)],
    'red': [('rock_spire_a', 3), ('rock_spire_c', 3), ('rock_fin', 2), ('butte', 1), ('arch', 1.5), ('boulder_b', 2)],
    'sandstone': [('tree_acacia', 3), ('tree_acacia_b', 2), ('tower_pod', 1.2), ('rock_spire_b', 1.5), ('boulder_a', 1.5), ('arch', 1)],
    'meadow': [('tree_acacia', 3), ('tree_acacia_b', 3), ('ruin_column', 2), ('ruin_wall', 2), ('tower_pod', 0.8), ('boulder_a', 1.5),
               ('arch_giant', 0.5), ('pillar', 1)],
    'coast': [('tree_acacia_b', 2), ('rock_spire_b', 2.5), ('rock_spire_a', 1.5), ('boulder_b', 1.5), ('ruin_column', 1), ('arch', 1)],
    'jungle': [('tree_mushroom', 4), ('tree_acacia', 1.5), ('crystals_cyan', 2), ('crystals_mag', 2), ('boulder_a', 1.5), ('pillar', 0.5)],
}
RADIUS = {'rock_spire_a': 7, 'rock_spire_b': 6, 'rock_spire_c': 9, 'boulder_a': 4, 'boulder_b': 6, 'arch': 16, 'arch_giant': 44,
          'arch_twin': 30, 'rock_ring': 20, 'rock_fin': 18, 'butte': 70, 'mesa': 30, 'tree_acacia': 7, 'tree_acacia_b': 6,
          'tree_mushroom': 9, 'tower_pod': 8, 'ruin_column': 3, 'ruin_wall': 10, 'crystals_cyan': 4, 'crystals_mag': 4, 'pillar': 4}
BIG = ('butte', 'mesa', 'arch_giant', 'arch_twin', 'rock_ring', 'rock_fin', 'arch')
grid_occ = {}
def occupied(x, z, r):
    gx, gz = int(x // 100), int(z // 100)
    for a in range(gx - 2, gx + 3):
        for b in range(gz - 2, gz + 3):
            for px, pz, pr in grid_occ.get((a, b), []):
                if (x - px) ** 2 + (z - pz) ** 2 < (r + pr + 8) ** 2:
                    return True
    return False
def occupy(x, z, r):
    grid_occ.setdefault((int(x // 100), int(z // 100)), []).append((x, z, r))

count, tries = 0, 0
while count < 1500 and tries < 80000:
    tries += 1
    x, z = (float(v) for v in rng.uniform(-2850, 2850, 2))
    if massif[int((z + HALF) / CELL), int((x + HALF) / CELL)] > 0.2:
        continue
    d, i = path_tree.query([x, z])
    if d > 650:
        continue
    s = secs[int(allS[i])]
    kinds = SCATTER[s.biome]
    names = [k for k, _ in kinds]; w = np.array([v for _, v in kinds], float); w /= w.sum()
    name = str(rng.choice(names, p=w))
    sc = float(rng.uniform(0.8, 1.3))
    r = RADIUS[name] * sc
    if not free_of_paths(x, z, r + 6):
        continue
    if height_at(x, z) < WATER_Y + 1.0:
        continue
    if (name.startswith('tree') or name in ('tower_pod', 'ruin_column', 'ruin_wall') or name in BIG) and slope_at(x, z) > 0.35:
        continue
    if occupied(x, z, r):
        continue
    add_prop(name, x, z, float(rng.uniform(-math.pi, math.pi)), sc, 1.5 if name in ('butte', 'mesa') else 0.6)
    occupy(x, z, r); count += 1
# rochedos no lago (como as pedras no mar das imagens)
s, lc = extra['c_lake']
for k in range(60):
    q = s.W(float(rng.uniform(0.18, 0.82)), float(rng.uniform(-430, 130)))
    if free_of_paths(q[0], q[1], 14) and height_at(q[0], q[1]) < WATER_Y - 1:
        add_prop(str(rng.choice(['rock_spire_a', 'rock_spire_b', 'rock_spire_c'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(0.9, 1.6)), 3.0)
# cenote: árvore enorme no meio
pc, floor = extra['f_cenote']
add_prop('tree_acacia', pc[0], pc[1], 0.4, 4.2, 0.5, y=floor)
# ruínas no topo da colina (B) e torre no prado (G)
hill, TOPB = extra['b_hill']
for f in (0.33, 0.47, 0.56, 0.7):
    c, t, h = hill.at_s(hill.s_at_u(f)); n = np.array([-t[1], t[0]])
    for sg in (-1, 1):
        q = c + n * sg * float(rng.uniform(42, 70))
        add_prop(str(rng.choice(['ruin_column', 'ruin_wall'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(1.0, 1.4)), 0.5, y=TOPB)
tw = extra['g_tower']
add_prop('ruin_tower', tw[0], tw[1], 0.3, 1.0, 0.5)
# casas-ovo na beira do desfiladeiro de arenito
rim, TOPD = extra['d_rim']
for f in np.linspace(0.28, 0.85, 10):
    c, t, h = rim.at_s(rim.s_at_u(float(f))); n = np.array([-t[1], t[0]])
    q = c + n * float(rng.choice([-1, 1])) * float(rng.uniform(60, 140))
    if free_of_paths(q[0], q[1], 10) and abs(height_at(q[0], q[1]) - TOPD) < 6:
        add_prop('tower_pod', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(1.0, 1.5)), 0.5)
# bandeirolas por cima dos caminhos de chão
banners = []
for s in secs:
    for p in s.paths:
        if p.level in (1, 3):
            for f in (0.12, 0.5, 0.88):
                c, t, h = p.at_s(f * p.L)
                if abs(h - height_at(c[0], c[1])) < 2:
                    banners.append([round(float(c[0]), 1), round(float(h), 2), round(float(c[1]), 1), round(yaw_of(t[0], t[1]), 3), float(p.hw * 2 + 16)])
# ilhas flutuantes por cima do maciço e da selva
islands = []
for k in range(27):
    if k < 22:
        a = rng.uniform(0, 2 * math.pi); r = rng.uniform(0, 1000)
        x, z, y = CENTER[0] + math.cos(a) * r * 1.1, CENTER[1] + math.sin(a) * r, float(rng.uniform(260, 420))
    else:
        q = secs[5].W(float(rng.uniform(0.1, 0.9)), float(rng.uniform(150, 700)))
        x, z, y = float(q[0]), float(q[1]), float(rng.uniform(380, 480))
    islands.append([round(float(x), 1), round(y, 1), round(float(z), 1), round(float(rng.uniform(-3, 3)), 2), round(float(rng.uniform(1.5, 4.5)), 2)])
# relva (tufos) perto dos caminhos nas zonas verdes
grass = []
for k in range(90000):
    if len(grass) >= 9000:
        break
    q = allP[int(rng.integers(0, len(allP)))] + rng.normal(0, 70, 2)
    b = biome_at(q[0], q[1])
    if b[0] + b[1] < 0.6 or not free_of_paths(q[0], q[1], 2):
        continue
    h = height_at(q[0], q[1])
    if h < WATER_Y + 1.2 or slope_at(q[0], q[1]) > 0.3:
        continue
    grass.append([round(float(q[0]), 1), round(h - 0.2, 2), round(float(q[1]), 1), round(float(rng.uniform(-3, 3)), 2), round(float(rng.uniform(0.8, 1.6)), 2)])

# ------------------------------------------------------------------ portões, partida, meta, rotas
checkpoints = []
for k in range(1, len(HUBS) - 1):
    d = secs[k - 1].paths[0].T[-1] + secs[k].paths[0].T[0]; d = d / np.linalg.norm(d)
    checkpoints.append({'p': [float(HUBS[k][0]), GROUND, float(HUBS[k][1])], 'dir': [float(d[0]), float(d[1])], 'w': 200.0,
                        'name': TITLES[KEYS[k]]})
d0 = secs[0].paths[0].T[0]
start = {'p': [float(HUBS[0][0]), GROUND, float(HUBS[0][1])], 'dir': [float(d0[0]), float(d0[1])], 'name': TITLES['A']}
fe = secs[-1].paths[0].T[-1]
finish = {'p': [float(HUBS[-1][0]), GROUND, float(HUBS[-1][1])], 'dir': [float(fe[0]), float(fe[1])], 'w': 200.0}

def route_of(p):
    idx = list(range(0, len(p.P), 4))
    if idx[-1] != len(p.P) - 1:
        idx.append(len(p.P) - 1)
    return [[round(float(p.P[i, 0]), 1), round(float(p.h[i]), 2), round(float(p.P[i, 1]), 1)] for i in idx]

sections = [{'key': s.key, 'title': TITLES[s.key], 'biome': s.biome,
             'variants': [{'name': p.name, 'level': p.level, 'hw': p.hw, 'length': round(p.L), 'route': route_of(p)} for p in s.paths]} for s in secs]

# ------------------------------------------------------------------ saída
os.makedirs(OUT, exist_ok=True)
# alturas em meia precisão (float16, em células) e biomas, comprimidos com zstd (APK mais pequeno)
import zstandard
zc = zstandard.ZstdCompressor(level=19)
open(os.path.join(OUT, 'height.zst'), 'wb').write(zc.compress((H / CELL).astype(np.float16).tobytes()))
open(os.path.join(OUT, 'biome.zst'), 'wb').write(zc.compress(biome8.tobytes()))
for old in ('height.bin', 'biome.bin'):
    if os.path.exists(os.path.join(OUT, old)):
        os.remove(os.path.join(OUT, old))
CH = 128
nch = (RES - 1) // CH
chunks = []
for cz in range(nch):
    for cx in range(nch):
        blk = H[cz * CH:(cz + 1) * CH + 1, cx * CH:(cx + 1) * CH + 1]
        chunks.append([round(float(blk.min()), 1), round(float(blk.max()), 1)])
data = {'size': SIZE, 'res': RES, 'cell': CELL, 'ground': GROUND, 'water_y': WATER_Y, 'fall_y': FALL_Y,
        'biome_res': int(biome8.shape[0]), 'chunk_cells': CH, 'chunks': chunks,
        'start': start, 'finish': finish, 'checkpoints': checkpoints, 'sections': sections,
        'tunnels': tunnels, 'bridges': bridges, 'aqueducts': aqueducts, 'lakes': lakes, 'roof': extra['roof'],
        'props': props, 'grass': grass, 'islands': islands, 'banners': banners}
json.dump(data, open(os.path.join(OUT, 'map.json'), 'w'), separators=(',', ':'), ensure_ascii=False)

# ------------------------------------------------------------------ minimapa
MM = 384
hs = H[::4, ::4]
gy, gx = np.gradient(hs)
shade = np.clip(0.8 + (-gx * 0.55 - gy * 0.35) / 3.5, 0.45, 1.15)
bz = np.array(Image.fromarray((biome * 255).astype(np.uint8), 'RGBA').resize(hs.shape[::-1], Image.BILINEAR)).astype(np.float32) / 255
sand = np.array([214, 184, 140]); grassc = np.array([126, 168, 84]); jung = np.array([62, 112, 58]); red = np.array([190, 98, 64])
col = np.zeros(hs.shape + (3,), np.float32); col[:] = sand
col = col * (1 - bz[..., 2:3]) + red * bz[..., 2:3]
col = col * (1 - bz[..., 0:1] * 0.9) + grassc * bz[..., 0:1] * 0.9
col = col * (1 - bz[..., 1:2] * 0.8) + jung * bz[..., 1:2] * 0.8
col *= shade[..., None]
lk = lakes[0]
in_lake = np.hypot(X[::4, ::4] - lk['c'][0], Z[::4, ::4] - lk['c'][1]) < lk['r']
col = np.where(((hs < WATER_Y) & in_lake)[..., None], np.array([70, 140, 190]) * (0.85 + 0.15 * shade[..., None]), col)
img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).resize((MM, MM), Image.LANCZOS)
dr = ImageDraw.Draw(img)
def to_px(P):
    return [((x + HALF) / SIZE * MM, (z + HALF) / SIZE * MM) for x, z in P[::6]]
LCOL = {0: (60, 230, 255), 1: (255, 255, 255), 2: (255, 160, 40), 3: (235, 245, 255)}
for lvl in (1, 3, 2, 0):
    for s in secs:
        for p in s.paths:
            if p.level != lvl:
                continue
            pts = to_px(p.P)
            if lvl == 0:
                for a, b in zip(pts[::2], pts[1::2]):
                    dr.line([a, b], fill=LCOL[0], width=3)
            else:
                dr.line(pts, fill=(40, 25, 15), width=6)
                dr.line(pts, fill=LCOL[lvl], width=3)
for k, hb in enumerate(HUBS):
    x, y = (hb[0] + HALF) / SIZE * MM, (hb[1] + HALF) / SIZE * MM
    c = (80, 220, 90) if k == 0 else ((230, 60, 50) if k == len(HUBS) - 1 else (255, 230, 120))
    dr.ellipse([x - 6, y - 6, x + 6, y + 6], fill=c, outline=(30, 20, 10), width=2)
img.save(os.path.join(OUT, 'minimap.png'))
total = sum(s.paths[0].L for s in secs)
print(f'percurso (caminho principal): {total:.0f} m | portões: {len(checkpoints)} | túneis: {len(tunnels)} | pontes: {len(bridges)} | '
      f'peças: {len(props)} | relva: {len(grass)} | ilhas: {len(islands)} | altura min/max: {H.min():.1f}/{H.max():.1f}')
