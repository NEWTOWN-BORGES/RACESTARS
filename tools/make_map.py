"""
RACESTARS — gera o MUNDO ABERTO (24 x 24 km) com 16 áreas de ~6 km e uma prova de sprint em cada.

Uso:  python tools/make_map.py        (precisa de numpy, scipy, pillow e zstandard)

Gera em game/assets/map/:
  height.zst    alturas em "células" (metros / 8), float16, 3073 x 3073, linha = z, coluna = x (zstd)
  biome.zst     mapa de biomas RGBA8 1536 x 1536 (R relva, G selva/musgo, B vermelho, A branco) (zstd)
  map.json      festival, autoestradas, provas (portões e caminhos por nível), túneis, pontes,
                aquedutos, água, peças, vegetação, fauna
  minimap.png   mapa visto de cima (2048 px)

Áreas (4 x 4, de noroeste para sudeste):
  Desfiladeiro de Arenito | Fenda Vermelha     | Picos das Águias   | Costa Branca
  Colinas Verdes          | Savana             | Maciço das Ilhas   | Lagoa Azul
  Selva do Cenote         | Prado do Aqueduto  | Deserto das Dunas  | Vale dos Arcos
  Floresta Gigante        | Planície de Sal    | Vale dos Cristais  | Oásis
O festival (onde se começa) fica no centro, no cruzamento das autoestradas.
Cada prova tem 2 trechos; cada trecho tem caminhos alternativos em níveis diferentes
(subterrâneo, chão, alto, água) e o jogador escolhe o melhor.
"""
import json, math, os
import numpy as np
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter, gaussian_filter1d, distance_transform_edt, binary_dilation, zoom
from PIL import Image, ImageDraw
import zstandard

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'game', 'assets', 'map'))
SIZE, RES = 24576.0, 3073
CELL = SIZE / (RES - 1)          # 8 m
HALF = SIZE / 2
AREA = 6144.0
GROUND = 4.0
WATER_Y = 0.0
FALL_Y = -34.0
ROAD_HW = 42.0                   # estradas das provas: 84 m de largura
HWY_HW = 24.0                    # autoestradas entre áreas
rng = np.random.default_rng(23)

# ------------------------------------------------------------------ ruído
_perm = rng.permutation(512)
def _vnoise(x, z):
    xi = np.floor(x).astype(np.int64); zi = np.floor(z).astype(np.int64)
    fx = (x - xi).astype(np.float32); fz = (z - zi).astype(np.float32)
    u = fx * fx * (3 - 2 * fx); v = fz * fz * (3 - 2 * fz)
    def h(a, b):
        return (_perm[(_perm[a & 511] + b) & 511] / 511.0).astype(np.float32)
    return (h(xi, zi) * (1 - u) + h(xi + 1, zi) * u) * (1 - v) + (h(xi, zi + 1) * (1 - u) + h(xi + 1, zi + 1) * u) * v

def fbm(x, z, oct=5):
    s = np.zeros_like(x, dtype=np.float32); a = 0.5; f = 1.0; n = 0.0
    for i in range(oct):
        s += a * _vnoise(x * f + i * 17.3, z * f - i * 9.1); n += a; a *= 0.5; f *= 2.03
    return s / n

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def yaw_of(dx, dz):  # yaw do Godot para que o "para frente" (-Z) aponte em (dx, dz)
    return float(math.atan2(-dx, -dz))

# ------------------------------------------------------------------ áreas
AREAS = [  # (coluna, linha, chave, nome, bioma, relevo, trechos)
    (0, 0, 'arenito', 'Desfiladeiro de Arenito', 'sandstone', 'rock', 'DD'),
    (1, 0, 'fenda', 'Fenda Vermelha', 'red', 'rock', 'HH'),
    (2, 0, 'picos', 'Picos das Águias', 'peaks', 'hills', 'PP'),
    (3, 0, 'costa', 'Costa Branca', 'coast', 'low', 'CC'),
    (0, 1, 'colinas', 'Colinas Verdes', 'meadow', 'hills', 'BB'),
    (1, 1, 'savana', 'Savana', 'savanna', 'hills', 'VV'),
    (2, 1, 'macico', 'Maciço das Ilhas', 'massif', 'hills', 'M'),
    (3, 1, 'lagoa', 'Lagoa Azul', 'lagoon', 'low', 'LL'),
    (0, 2, 'selva', 'Selva do Cenote', 'jungle', 'hills', 'FF'),
    (1, 2, 'prado', 'Prado do Aqueduto', 'meadow', 'hills', 'GG'),
    (2, 2, 'dunas', 'Deserto das Dunas', 'desert', 'dunes', 'AE'),
    (3, 2, 'arcos', 'Vale dos Arcos', 'arches', 'rock', 'RR'),
    (0, 3, 'floresta', 'Floresta Gigante', 'forest', 'hills', 'TT'),
    (1, 3, 'sal', 'Planície de Sal', 'salt', 'flat', 'SS'),
    (2, 3, 'cristais', 'Vale dos Cristais', 'crystals', 'rock', 'KK'),
    (3, 3, 'oasis', 'Oásis', 'oasis', 'dunes', 'OO'),
]
def area_center(i, j):
    return np.array([-HALF + AREA * (i + 0.5), -HALF + AREA * (j + 0.5)])
FESTIVAL = np.array([0.0, 0.0])

# R relva, G selva/musgo, B vermelho (areia/rocha e relva dourada), A branco (calcário/sal/praia)
B_CH = {'desert': (0, 0, 0.1, 0), 'meadow': (1, 0, 0, 0.9), 'coast': (0.9, 0, 0, 1), 'sandstone': (0.25, 0, 0, 0.45),
        'jungle': (0.55, 1, 0, 0.35), 'red': (0, 0, 1, 0), 'peaks': (0.75, 0.15, 0, 1), 'savanna': (0.7, 0, 0.3, 0.15),
        'massif': (0.75, 0.2, 0, 1), 'lagoon': (0.6, 0, 0, 1), 'arches': (0, 0, 0.55, 0.1), 'forest': (0.95, 0.55, 0, 0.3),
        'salt': (0, 0, 0, 1), 'crystals': (0.3, 0.35, 0.35, 0.6), 'oasis': (0.1, 0, 0.2, 0.2)}

# ------------------------------------------------------------------ grelha e terreno base
print('terreno base...')
xs = np.linspace(-HALF, HALF, RES).astype(np.float32)
X, Z = np.meshgrid(xs, xs)                    # linhas = z, colunas = x
n_dune = 4.5 * fbm(X / 240, Z / 240) + 2.0 * (np.sin((X * 0.6 + Z * 0.8) / 34 + fbm(X / 90, Z / 90) * 7) * 0.5 + 0.5)
n_hill = fbm(X / 900 + 11, Z / 900)
n_macro = fbm(X / 2600 - 4, Z / 2600 + 8, oct=3)
RELIEF = {
    'dunes': 2.0 + 1.6 * n_dune + 16 * smooth(0.45, 0.8, n_hill),
    'rock': 2.0 + n_dune + 12 * n_hill,
    'hills': 2.0 + 0.5 * n_dune + 34 * np.clip(n_hill - 0.32, 0, 1) + 10 * n_macro,
    'low': 1.5 + 0.4 * n_dune + 6 * n_hill,
    'flat': 3.0 + 0.15 * n_dune,
}
# pesos das áreas (transição suave nas fronteiras, com ondulação)
warp_x = 380 * (fbm(X / 1500 + 3, Z / 1500) - 0.5)
warp_z = 380 * (fbm(X / 1500, Z / 1500 - 7) - 0.5)
W_area = []
for (i, j, *_ ) in AREAS:
    c = area_center(i, j)
    d = np.maximum(np.abs(X + warp_x - c[0]), np.abs(Z + warp_z - c[1]))
    W_area.append((1 - smooth(2750, 3450, d)).astype(np.float32))
wsum = np.maximum(sum(W_area), 1e-4)
H = np.zeros_like(X)
for k, a in enumerate(AREAS):
    H += RELIEF[a[5]] * W_area[k] / wsum
del RELIEF
# montanhas na borda do mundo
edge = np.maximum(np.abs(X), np.abs(Z))
H = H + (180 + 40 * fbm(X / 300, Z / 300) - H) * smooth(11850, 12150, edge)
H = H.astype(np.float32)

def sample_arr(A, P):
    fx = (P[:, 0] + HALF) / CELL; fz = (P[:, 1] + HALF) / CELL
    i = np.clip(np.floor(fx).astype(int), 0, RES - 2); j = np.clip(np.floor(fz).astype(int), 0, RES - 2)
    u = fx - i; v = fz - j
    return A[j, i] * (1 - u) * (1 - v) + A[j, i + 1] * u * (1 - v) + A[j + 1, i] * (1 - u) * v + A[j + 1, i + 1] * u * v

def sample(P):
    return sample_arr(H, P)

def height_at(x, z):
    return float(sample(np.array([[x, z]]))[0])

def grid_box(xmin, xmax, zmin, zmax):
    i0 = max(0, int((xmin + HALF) / CELL)); i1 = min(RES, int((xmax + HALF) / CELL) + 2)
    j0 = max(0, int((zmin + HALF) / CELL)); j1 = min(RES, int((zmax + HALF) / CELL) + 2)
    return slice(j0, j1), slice(i0, i1)

# ------------------------------------------------------------------ caminhos
def catmull(points, step=2.0, alpha=0.5):
    """Curva Catmull-Rom centrípeta (sem laçadas nem bicos quando os troços têm comprimentos muito
    diferentes); devolve os pontos e o parâmetro (índice do ponto de controlo) de cada um."""
    P = np.array(points, dtype=float)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out, own = [], []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        t0 = 0.0
        t1 = t0 + max(np.linalg.norm(p1 - p0), 1e-3) ** alpha
        t2 = t1 + max(np.linalg.norm(p2 - p1), 1e-3) ** alpha
        t3 = t2 + max(np.linalg.norm(p3 - p2), 1e-3) ** alpha
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for k in range(n):
            t = t1 + (t2 - t1) * k / n
            A1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            A2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            A3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            B1 = (t2 - t) / (t2 - t0) * A1 + (t - t0) / (t2 - t0) * A2
            B2 = (t3 - t) / (t3 - t1) * A2 + (t - t1) / (t3 - t1) * A3
            out.append((t2 - t) / (t2 - t1) * B1 + (t - t1) / (t2 - t1) * B2)
            own.append(i - 1 + k / n)
    out.append(P[-2]); own.append(len(points) - 1)
    return np.array(out), np.array(own)

class Sec:
    def __init__(s, key, A, B, biome, ref, tag):
        s.key, s.biome, s.tag = key, biome, tag
        s.A = np.array(A, float); s.B = np.array(B, float)
        d = s.B - s.A; s.Ls = float(np.linalg.norm(d)); s.eu = d / s.Ls
        s.ev = np.array([-s.eu[1], s.eu[0]])
        o = 1.0 if np.dot(s.ev, (s.A + s.B) / 2 - ref) >= 0 else -1.0
        s.IN = -o                      # w positivo = para dentro (para o centro da área)
        s.paths = []
        s.deco = []                    # (nome, x, z, yaw, escala, afundar, y ou None)
    def W(s, u, w):
        return s.A + s.eu * u * s.Ls + s.ev * (s.IN * w)
    def UW(s, Xg, Zg):
        um = (Xg - s.A[0]) * s.eu[0] + (Zg - s.A[1]) * s.eu[1]
        vm = (Xg - s.A[0]) * s.ev[0] + (Zg - s.A[1]) * s.ev[1]
        return um, vm * s.IN
    def box(s, u0, u1, w0, w1, pad):
        pts = np.array([s.W(u, w) for u in (u0, u1) for w in (w0, w1)])
        return grid_box(pts[:, 0].min() - pad, pts[:, 0].max() + pad, pts[:, 1].min() - pad, pts[:, 1].max() + pad)
    def yaw(s):
        return yaw_of(s.eu[0], s.eu[1])

class Path:
    def __init__(p, sec, name, level, ctrl, hw, hfun=None, ground=False, hctrl=None, world=False, closed=False):
        p.sec, p.name, p.level, p.hw = sec, name, level, hw
        pts = ctrl if world else [sec.W(u, w) for u, w in ctrl]
        if closed:   # circuito: a curva dá a volta e acaba onde começou
            n_ = len(pts)
            P, own = catmull([pts[-1]] + list(pts) + [pts[0], pts[1]], 2.0)
            keep = (own >= 1.0) & (own <= n_ + 1.0)
            P, own = P[keep], own[keep] - 1.0
        else:
            P, own = catmull(pts, 2.0)
        if not world:
            P[0] = sec.A; P[-1] = sec.B
        p.P = P
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        p.S = np.concatenate([[0], np.cumsum(seg)]); p.L = float(p.S[-1])
        p.u = ((P - sec.A) @ sec.eu) / sec.Ls if sec is not None else p.S / p.L
        t = np.gradient(P, axis=0); p.T = t / np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-6)
        if ground:   # segue o chão, suavizado
            h = np.clip(gaussian_filter1d(sample(P), 35, mode='wrap' if closed else 'nearest'), 2.5, 45.0 if closed else 30.0)
        elif hctrl is not None:
            h = np.interp(own, np.arange(len(hctrl)), hctrl)
        else:
            h = hfun(p.u).astype(float)
        if ground:   # perto dos portões todos os caminhos estão à mesma altura (os primeiros 120 m ao nível do portão)
            we = smooth(120, 420, p.S) * smooth(120, 420, p.L - p.S)
        else:
            we = smooth(0, 90, p.S) * smooth(0, 90, p.L - p.S)
        p.h = GROUND + (h - GROUND) * we          # altura a que se conduz
        p.ht = p.h.copy()                          # altura a que se esculpe o terreno
        p.jumps = []
        if sec is not None:
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
    """Corte reto auxiliar (fendas, abismo, faixas)."""
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
    elif mode == 'fill': new = np.where(D[ok] <= hw, tgt, np.maximum(cur, new))   # aterra à volta, mas a estrada fica sempre à vista
    sub[ok] = new
    H[sj, si] = sub.reshape(Xs.shape)

def stamp_rect(sec, u0, u1, w0, w1, top, corner=90, edge=12, wobble=40, flat=False, rough=0.0):
    """Planalto/colina de cantos redondos; top = altura absoluta; rough = picos por cima."""
    sj, si = sec.box(u0, u1, w0, w1, edge + wobble + 40)
    Xs, Zs = X[sj, si], Z[sj, si]
    um, wm = sec.UW(Xs, Zs)
    cu = (u0 + u1) / 2 * sec.Ls; hu = (u1 - u0) / 2 * sec.Ls; cw = (w0 + w1) / 2; hwid = (w1 - w0) / 2
    qx = np.abs(um - cu) - hu + corner; qz = np.abs(wm - cw) - hwid + corner
    sdf = np.hypot(np.maximum(qx, 0), np.maximum(qz, 0)) + np.minimum(np.maximum(qx, qz), 0) - corner
    sdf = sdf + wobble * (fbm(Xs / 160 + sec.Ls, Zs / 160) - 0.5)
    m = 1 - smooth(-edge, 0, sdf)
    t = top if flat else top + 4 * (fbm(Xs / 90 + 2, Zs / 90) - 0.5)
    if rough > 0:
        inner = smooth(0, edge * 2, -sdf)
        t = t + rough * inner * fbm(Xs / 260 + 5, Zs / 260, oct=4) ** 1.6
    sub = H[sj, si]
    H[sj, si] = np.maximum(sub, sub + (t - sub) * m)

def stamp_ellipse(c, ru, rv, yaw_u, f):
    """Aplica f(sub, r) numa elipse de semi-eixos ru (ao longo de yaw_u) e rv; r=1 na borda."""
    pad = max(ru, rv) * 1.4 + 60
    sj, si = grid_box(c[0] - pad, c[0] + pad, c[1] - pad, c[1] + pad)
    Xs, Zs = X[sj, si], Z[sj, si]
    a = (Xs - c[0]) * yaw_u[0] + (Zs - c[1]) * yaw_u[1]
    b = -(Xs - c[0]) * yaw_u[1] + (Zs - c[1]) * yaw_u[0]
    r = np.hypot(a / ru, b / rv) + 0.08 * (fbm(Xs / 150, Zs / 150) - 0.5)
    H[sj, si] = f(H[sj, si], r)

def crossings(a, b, tol=3.0):
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

# ------------------------------------------------------------------ peças grandes
tunnels, bridges, aqueducts, waters, roofs, props = [], [], [], [], [], []

def add_prop(name, x, z, yaw, sc, sink=1.0, y=None):
    props.append([name, round(float(x), 2), round(float((height_at(x, z) if y is None else y) - sink), 2), round(float(z), 2),
                  round(float(yaw), 3), round(float(sc), 3)])

def tunnel(sec, p, u0, u1, name, clear=22.0, top=None, thw=18.0):
    """Bloco de túnel (modelado no Blender) entre u0 e u1 do caminho p. A tampa acompanha o terreno
    por cima (montanha, colina ou chão), suavizado, e o terreno à volta da tampa é acertado a ela."""
    s0, s1 = p.s_at_u(u0), p.s_at_u(u1)
    a, _, h0 = p.at_s(s0)
    b, _, _ = p.at_s(s1)
    L = float(np.linalg.norm(b - a)); t = (b - a) / L; n = np.array([-t[1], t[0]])
    ys = np.arange(0.0, L + 24.0, 24.0); ys[-1] = L
    pts = a + np.outer(ys, t)
    W = max(84.0, 2 * thw + 48.0)          # largura da tampa (o vão por dentro tem 2*thw)
    prof = np.minimum(sample(pts + n * (W / 2 + 16)), sample(pts - n * (W / 2 + 16)))
    prof = gaussian_filter1d(prof, 3, mode='nearest')
    prof = np.maximum(prof, h0 + clear)
    if top is not None:          # um caminho passa por cima da tampa: a tampa fica à altura dele
        prof = np.maximum(np.full_like(prof, top), h0 + clear)
    band = Line(a, b, 0.0, max(46.0, W / 2 + 4))
    band.P = pts; band.ht = prof
    carve(band, 36, 'set')
    seg = (p.S >= s0 - 120) & (p.S <= s1 + 120)   # a faixa da tampa estende-se para lá das bocas: reabre o caminho
    sub = Line(a, b, 0.0, p.hw); sub.P = p.P[seg]; sub.ht = p.ht[seg]
    carve(sub, 12, 'set')
    tunnels.append({'name': name, 'p': [float(a[0]), float(h0), float(a[1])], 'yaw': yaw_of(t[0], t[1]),
                    'len': L, 'tops': [round(float(v - h0), 2) for v in prof], 'step': 24.0, 'w': W, 'thw': thw})

def bridge(p, s, length, name, deck=None, broken=0.0, width=30.0, deep=46.0):
    c, t, h = p.at_s(s)
    deck = h if deck is None else deck
    start = c - t * length / 2
    bridges.append({'name': name, 'p': [float(start[0]), float(deck), float(start[1])], 'yaw': yaw_of(t[0], t[1]),
                    'len': float(length), 'width': float(width), 'broken': float(broken), 'deep': float(deep)})

def water(sec, u0, u1, w0, w1, y=WATER_Y):
    """Superfície de água retangular (rodada como o trecho)."""
    c = sec.W((u0 + u1) / 2, (w0 + w1) / 2)
    waters.append({'c': [float(c[0]), float(c[1])], 'sx': float(abs(w1 - w0) / 2), 'sz': float((u1 - u0) * sec.Ls / 2),
                   'yaw': sec.yaw(), 'y': float(y)})

def lake(sec, uc, wc, ru, rv, depth=10.0, shore=0.2):
    """Escava um lago elíptico (eixo maior ao longo do trecho) e põe a água."""
    c = sec.W(uc, wc)
    def f(sub, r):
        tgt = WATER_Y - 1.0 - depth * smooth(1.0, 0.6, r)
        w = 1 - smooth(1.0, 1.0 + shore, r)
        return np.minimum(sub, sub + (tgt - sub) * w)
    stamp_ellipse(c, ru, rv, sec.eu, f)
    water(sec, uc - ru * 1.25 / sec.Ls, uc + ru * 1.25 / sec.Ls, wc - rv * 1.3, wc + rv * 1.3)

def arches_over(sec, p, fracs, name='arch_giant', sc=1.6):
    for f in fracs:
        c, t, h = p.at_s(f * p.L)
        sec.deco.append((name, c[0], c[1], yaw_of(t[0], t[1]), sc, 0.5, h))

# ================================================================== trechos
# A — deserto: estrada com dunas OU crista de areia com fendas
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
    for g in gaps:
        c, t, _ = ridge.at_s(ridge.s_at_u(g)); n = np.array([-t[1], t[0]])
        carve(Line(c - n * 70, c + n * 70, GROUND + 1, 22), 6, 'cut')
    arches_over(s, road, (0.22, 0.62, 0.9))

# B — colinas verdes: vale / túnel / topo com fendas e ruínas
def sec_B(s):
    TOP = 58.0
    stamp_rect(s, 0.27, 0.77, -290, 210, TOP, corner=110, edge=10, wobble=50, flat=True)
    tun = Path(s, 'túnel da colina', 0, [(0, 0), (0.12, 0), (0.5, 0), (0.88, 0), (1, 0)], 19,
               hfun=lambda u: GROUND + (-4 - GROUND) * smooth(0.12, 0.27, u) * (1 - smooth(0.77, 0.9, u)))
    valley = Path(s, 'vale das colinas', 1, [(0, 0), (0.1, 150), (0.28, 360), (0.5, 400), (0.72, 360), (0.9, 150), (1, 0)], ROAD_HW, ground=True)
    valley.kicker(0.42 * valley.L); valley.kicker(0.6 * valley.L)
    hill = Path(s, 'topo da colina', 2, [(0, 0), (0.05, -30), (0.14, -120), (0.27, -150), (0.5, -150), (0.77, -150), (0.86, -90), (0.94, -30), (1, 0)], 30,
                hfun=lambda u: np.where(u < 0.778, GROUND + (TOP - GROUND) * smooth(0.04, 0.27, u), GROUND + 1))
    hill.kicker(hill.s_at_u(0.775), rise=2.5, run=40)
    crev = [0.42, 0.62]
    hill.kicker(hill.s_at_u(crev[1]) - 40, rise=2.0, run=34)
    carve(hill, 26)
    for g in crev:
        c, t, _ = hill.at_s(hill.s_at_u(g))
        uu = float((c - s.A) @ s.eu) / s.Ls
        carve(Line(s.W(uu, -340), s.W(uu, -85), GROUND + 1, 30), 7, 'cut')
    bridge(hill, hill.s_at_u(crev[0]), 110, f'ponte_{s.tag}', deck=TOP, width=2 * hill.hw + 8)
    carve(valley, 60)
    carve(tun, 12, 'set')
    tunnel(s, tun, 0.27, 0.77, f'tunel_{s.tag}')
    for f in (0.33, 0.47, 0.56, 0.7):  # ruínas no topo
        c, t, h = hill.at_s(hill.s_at_u(f)); n = np.array([-t[1], t[0]])
        for sg in (-1, 1):
            q = c + n * sg * float(rng.uniform(42, 70))
            s.deco.append((str(rng.choice(['ruin_column', 'ruin_wall'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(1.0, 1.4)), 0.5, TOP))

# C — costa: margem / caminho de pedra sobre a água / penhascos brancos
def sec_C(s):
    lake(s, 0.5, -150, 0.37 * s.Ls, 330.0)
    stamp_rect(s, 0.15, 0.85, -720, -540, 38, corner=120, edge=16, wobble=80)
    shore = Path(s, 'margem', 1, [(0, 0), (0.12, 200), (0.3, 310), (0.5, 330), (0.7, 310), (0.88, 200), (1, 0)], ROAD_HW, ground=True)
    shore.kicker(0.5 * shore.L)
    gaps = [(0.37, 0.39), (0.6, 0.62)]
    def ch(u):
        h = GROUND + (1.6 - GROUND) * smooth(0.08, 0.16, u) * (1 - smooth(0.84, 0.92, u))
        for a, b in gaps:
            h = np.where((u > a) & (u < b), -5.0, h)
        return h
    cw = Path(s, 'caminho de pedra', 3, [(0, 0), (0.5, 0), (1, 0)], 14, hfun=ch)
    cw.h = np.maximum(cw.h, WATER_Y)
    carve(shore, 60)
    carve(cw, 5)
    arches_over(s, cw, (0.3, 0.5, 0.72), sc=0.95)
    for k in range(40):   # rochedos na água, como as pedras do mar das imagens
        q = s.W(float(rng.uniform(0.18, 0.82)), float(rng.uniform(-430, 130)))
        if height_at(q[0], q[1]) < WATER_Y - 1 and abs(float((q - s.A) @ s.ev)) > 30:
            s.deco.append((str(rng.choice(['rock_spire_a', 'rock_spire_b', 'rock_spire_c'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(0.9, 1.6)), 3.0, None))

# D — desfiladeiro de arenito: leito com ganchos / beira com pontes e salto
def sec_D(s):
    TOP = 56.0
    stamp_rect(s, 0.07, 0.93, -420, 420, TOP, corner=140, edge=10, wobble=60)
    us = np.linspace(0, 1, 60)
    taper = smooth(0.19, 0.26, us) * (1 - smooth(0.87, 0.94, us))   # o leito só serpenteia depois de a beira chegar lá acima
    ph = float(rng.uniform(0, 0.1))
    ctrl = [(float(u), float(200 * math.sin(2 * math.pi * (u - 0.07 + ph) / 0.29) * t)) for u, t in zip(us, taper)]
    canyon = Path(s, 'leito do desfiladeiro', 0, ctrl, 34, hfun=lambda u: np.full_like(u, GROUND))
    rim = Path(s, 'beira de cima', 2, [(0, 0), (0.04, -60), (0.1, -150), (0.17, -80), (0.24, 0), (0.5, 0), (0.7, -170), (0.8, -310), (0.92, -310), (0.97, -120), (1, 0)], 28,
               hfun=lambda u: np.where(u < 0.926, GROUND + (TOP - GROUND) * smooth(0.0, 0.17, u), GROUND + 1))
    rim.kicker(rim.s_at_u(0.924), rise=2.5, run=40)
    xs_ = [k for k in crossings(rim, canyon) if 0.02 < rim.u[k] < 0.9]
    for n, k in enumerate(xs_):
        a = max(cross_angle(rim, k, canyon), 0.35)
        half = (34 + 10) / math.sin(a)
        if n == 1 and rim.h[k] > TOP - 1:
            rim.kicker(float(rim.S[k]) - half - 3, rise=3.0, run=40)
        else:
            bridge(rim, float(rim.S[k]), 2 * half + 44, f'ponte_{s.tag}{n}', deck=float(rim.h[k]), width=2 * rim.hw + 8)
    carve(rim, 30)
    carve(canyon, 10, 'set')
    for f in np.linspace(0.28, 0.85, 8):   # casas-ovo na beira
        c, t, h = rim.at_s(rim.s_at_u(float(f))); n = np.array([-t[1], t[0]])
        q = c + n * float(rng.choice([-1, 1])) * float(rng.uniform(60, 140))
        if abs(height_at(q[0], q[1]) - TOP) < 6:
            s.deco.append(('tower_pod', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(1.0, 1.5)), 0.5, None))

# E — abismo + dunas
def sec_E(s):
    road = Path(s, 'salto do abismo', 1, [(0, 0), (0.12, 0), (0.3, 60), (0.42, 0), (0.55, -90), (0.72, 80), (0.88, -40), (1, 0)], ROAD_HW, ground=True)
    det = Path(s, 'desvio do abismo', 1, [(0, 0), (0.12, 0), (0.24, 200), (0.33, 480), (0.43, 200), (0.55, -90), (0.72, 80), (0.88, -40), (1, 0)],
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

# F — selva e cenote
def sec_F(s):
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
    rpit = 0.068 * s.Ls
    stamp_ellipse(pc, rpit, rpit, s.eu, lambda sub, r: sub + (FLOOR - sub) * (1 - smooth(0.78, 1.0, r)))
    carve(under, 12, 'set')
    tunnel(s, under, 0.2, 0.432, f'tunel_{s.tag}1', top=GROUND)
    tunnel(s, under, 0.568, 0.8, f'tunel_{s.tag}2', top=GROUND)
    bridge(top, top.s_at_u(0.5), 0.136 * s.Ls, f'ponte_{s.tag}', deck=GROUND, broken=44.0, width=2 * top.hw + 8, deep=0.0)
    s.deco.append(('tree_giant', pc[0], pc[1], 0.4, 1.6, 0.5, FLOOR))

# G — prado: estrada das ruínas / tubo / aqueduto
def sec_G(s):
    DECK = 20.0
    meadow = Path(s, 'estrada das ruínas', 1, [(0, 0), (0.12, 150), (0.3, 90), (0.45, 220), (0.6, 100), (0.78, 210), (0.9, 120), (1, 0)], ROAD_HW, ground=True)
    meadow.kicker(0.35 * meadow.L); meadow.kicker(0.7 * meadow.L)
    tube = Path(s, 'tubo subterrâneo', 0, [(0, 0), (0.5, 0), (1, 0)], 19,
                hfun=lambda u: GROUND + (-18 - GROUND) * smooth(0.06, 0.18, u) * (1 - smooth(0.82, 0.94, u)))
    aq = Path(s, 'aqueduto', 2, [(0, 0), (0.03, -60), (0.07, -150), (0.11, -170), (0.16, -170), (0.84, -170), (0.89, -170), (0.93, -150), (0.97, -60), (1, 0)], 10,
              hfun=lambda u: GROUND + DECK * smooth(0.06, 0.16, u) * (1 - smooth(0.84, 0.94, u)))
    a0 = s.W(0.16, -170); a1 = s.W(0.84, -170)
    L = float(np.linalg.norm(a1 - a0)); nseg = int(L // 40); t = (a1 - a0) / L
    su = (aq.P - a0) @ t
    aq.h = np.where((su >= 0) & (su <= nseg * 40), GROUND + DECK, aq.h)
    aq.ht = np.where((su >= 0) & (su <= nseg * 40), GROUND, aq.h)
    gap = [nseg // 2 - 1, nseg // 2]
    aq.h = np.where((su > gap[0] * 40) & (su < (gap[-1] + 1) * 40), GROUND, aq.h)
    aq.jumps.append(float(aq.S[int(np.argmin(np.abs(su - gap[0] * 40)))]))
    aqueducts.append({'p': [float(a0[0]), GROUND, float(a0[1])], 'yaw': yaw_of(t[0], t[1]), 'n': nseg, 'seg': 40.0, 'deck': DECK, 'missing': gap})
    carve(meadow, 60)
    carve(aq, 24, hw=24)
    carve(tube, 12, 'set')
    tunnel(s, tube, 0.18, 0.44, f'tunel_{s.tag}1')
    tunnel(s, tube, 0.54, 0.82, f'tunel_{s.tag}2')
    tw = s.W(0.5, 380)
    s.deco.append(('ruin_tower', tw[0], tw[1], 0.3, 1.0, 0.5, None))

# H — fenda vermelha com teto / por cima com saltos
def sec_H(s):
    TOP = 64.0
    stamp_rect(s, 0.08, 0.91, -330, 330, TOP, corner=120, edge=9, wobble=60)
    slot = Path(s, 'fenda vermelha', 0, [(0, 0), (0.08, 0), (0.2, 115), (0.34, -100), (0.48, 90), (0.62, -85), (0.76, 50), (0.86, 0), (1, 0)], 28,
                hfun=lambda u: np.full_like(u, GROUND))
    rim = Path(s, 'por cima da fenda', 2, [(0, 0), (0.04, -80), (0.12, -160), (0.2, -70), (0.3, 0), (0.6, 0), (0.74, -70), (0.84, -130), (0.9, -125), (0.95, -60), (1, 0)], 28,
               hfun=lambda u: np.where(u < 0.902, GROUND + (TOP - GROUND) * smooth(0.0, 0.18, u), GROUND + 1))
    rim.kicker(rim.s_at_u(0.9), rise=2.5, run=40)
    for k in crossings(rim, slot):
        if 0.02 < rim.u[k] < 0.85:
            a = max(cross_angle(rim, k, slot), 0.35)
            rim.kicker(float(rim.S[k]) - (28 + 6) / math.sin(a) - 3, rise=2.5, run=36)
    carve(rim, 30)
    carve(slot, 6, 'set')
    ir = int(np.argmin(np.abs(slot.u - 0.55)))
    roofs.append({'p': [float(slot.P[ir, 0]), float(slot.h[ir]), float(slot.P[ir, 1])], 'yaw': yaw_of(slot.T[ir, 0], slot.T[ir, 1])})

# P / M — montanha: túnel por baixo / estrada de montanha com ganchos por cima / vale à volta
def mountain(s, u0, u1, w0, w1, TOP, valley_w, pass_side, round_=False, rough=60.0):
    corner = (u1 - u0) * s.Ls * 0.45 if round_ else 160
    stamp_rect(s, u0, u1, w0, w1, TOP, corner=corner, edge=260, wobble=120, rough=rough)
    tun = Path(s, 'túnel', 0, [(0, 0), (u0 - 0.1, 0), (0.5, 0), (u1 + 0.1, 0), (1, 0)], 19,
               hfun=lambda u: GROUND + (-6 - GROUND) * smooth(u0 - 0.12, u0 + 0.01, u) * (1 - smooth(u1 - 0.01, u1 + 0.12, u)))
    vw = valley_w
    valley = Path(s, 'vale', 1, [(0, 0), (0.12, vw * 0.4), (0.3, vw * 0.9), (0.5, vw), (0.7, vw * 0.9), (0.88, vw * 0.4), (1, 0)], ROAD_HW, ground=True)
    # estrada de montanha: curvas largas a subir pela encosta, cumeada, curvas largas a descer
    ps = pass_side
    wm = abs(w0) if ps < 0 else abs(w1)
    up = [(u0 - 0.14, ps * 200, GROUND + 2), (u0 - 0.05, ps * wm * 0.55, GROUND + (TOP - GROUND) * 0.3),
          (u0 + (u1 - u0) * 0.18, ps * wm * 0.8, GROUND + (TOP - GROUND) * 0.68)]
    mid = [(0.5, ps * wm * 0.6, TOP + 2)]
    down = [(1 - a, w, h) for a, w, h in reversed(up)]
    pts = [(0, 0, GROUND)] + up + mid + down + [(1, 0, GROUND)]
    pas = Path(s, 'estrada da montanha', 2, [(a, w) for a, w, _ in pts], 30, hctrl=[h for _, _, h in pts])
    carve(pas, 26)
    carve(valley, 60)
    carve(tun, 12, 'set')
    tunnel(s, tun, u0 - 0.02, u1 + 0.02, f'tunel_{s.tag}')
    for f in (0.3, 0.5, 0.7):  # bandeirolas e pinheiros no cimo
        q = s.W(f * (u1 - u0) + u0, ps * 640)
        s.deco.append(('pine', q[0], q[1], 0.0, 1.4, 0.5, None))

def sec_P(s):
    mountain(s, 0.3, 0.7, -950, 560, 120.0, 820, -1)

def sec_M(s):
    mountain(s, 0.22, 0.78, -1150, 1150, 170.0, 1550, -1, round_=True, rough=70.0)

# V — savana: trilho / atravessar o charco / colinas de pedra (kopjes)
def sec_V(s):
    lake(s, 0.5, 0, 0.18 * s.Ls, 190.0, depth=3.0, shore=0.35)
    road = Path(s, 'trilho da savana', 1, [(0, 0), (0.12, 160), (0.32, 300), (0.5, 330), (0.68, 300), (0.88, 160), (1, 0)], ROAD_HW, ground=True)
    road.kicker(0.25 * road.L); road.kicker(0.75 * road.L)
    pond = Path(s, 'pelo charco', 3, [(0, 0), (0.5, 0), (1, 0)], 30, ground=True)
    pond.h = np.maximum(pond.h, WATER_Y)
    pond.ht = pond.h.copy()
    hills = []
    for k, (uc, hh) in enumerate([(0.3, 30.0), (0.5, 36.0), (0.7, 28.0)]):   # colinas de granito
        stamp_rect(s, uc - 0.06, uc + 0.06, -470, -230, hh, corner=120, edge=40, wobble=30)
        hills.append((uc, hh))
    def kh(u):
        h = np.full_like(u, GROUND)
        for uc, hh in hills:
            h = np.maximum(h, GROUND + (hh - GROUND) * (1 - smooth(0.035, 0.065, np.abs(u - uc))))
        return h
    kop = Path(s, 'colinas de pedra', 2, [(0, 0), (0.08, -200), (0.2, -350), (0.8, -350), (0.92, -200), (1, 0)], 24, hfun=kh)
    for uc, _ in hills:
        kop.kicker(kop.s_at_u(uc + 0.045), rise=2.0, run=30, terrain=False)
    carve(road, 60)
    carve(pond, 30, 'cut')
    carve(kop, 20, 'fill')
    for uc, _ in hills:  # pedras soltas nas colinas
        for k in range(4):
            q = s.W(uc + float(rng.uniform(-0.05, 0.05)), float(rng.uniform(-470, -230)))
            s.deco.append((str(rng.choice(['boulder_a', 'boulder_b'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(1.0, 1.8)), 0.8, None))

# L — lagoa azul: praia / bancos de areia / falésia com saltos
def sec_L(s):
    lake(s, 0.5, -120, 0.4 * s.Ls, 360.0, depth=6.0, shore=0.35)
    stamp_rect(s, 0.12, 0.88, -760, -560, 34, corner=140, edge=14, wobble=90)
    beach = Path(s, 'praia', 1, [(0, 0), (0.12, 220), (0.3, 330), (0.5, 350), (0.7, 330), (0.88, 220), (1, 0)], ROAD_HW, ground=True)
    beach.kicker(0.4 * beach.L); beach.kicker(0.62 * beach.L)
    def bars(u):
        h = GROUND + (1.0 - GROUND) * smooth(0.06, 0.14, u) * (1 - smooth(0.86, 0.94, u))
        for a in (0.24, 0.36, 0.48, 0.6, 0.72):
            h = np.where((u > a) & (u < a + 0.05), -2.5, h)
        return h
    sb = Path(s, 'bancos de areia', 3, [(0, 0), (0.5, 0), (1, 0)], 18, hfun=bars)
    sb.h = np.maximum(sb.h, WATER_Y)
    TOP = 34.0
    cliff = Path(s, 'falésia', 2, [(0, 0), (0.06, -300), (0.14, -660), (0.86, -660), (0.94, -300), (1, 0)], 26,
                 hfun=lambda u: GROUND + (TOP - GROUND) * smooth(0.05, 0.15, u) * (1 - smooth(0.85, 0.95, u)))
    inlets = [0.35, 0.6]
    for g in inlets:
        cliff.kicker(cliff.s_at_u(g) - 34, rise=2.5, run=34)
    carve(beach, 60)
    carve(sb, 8)
    carve(cliff, 30)
    for g in inlets:  # enseadas que cortam a falésia (a água entra)
        uu = g
        carve(Line(s.W(uu, -820), s.W(uu, -520), -3.0, 26), 10, 'cut')
    for k in range(30):  # palmeiras na praia
        q = s.W(float(rng.uniform(0.12, 0.88)), float(rng.uniform(230, 420)))
        if WATER_Y + 1 < height_at(q[0], q[1]) < 10 and abs(float(np.min(np.linalg.norm(beach.P - q, axis=1)))) > ROAD_HW + 8:
            s.deco.append(('palm', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(0.9, 1.4)), 0.3, None))

# R — vale dos arcos: avenida de arcos / saltar de mesa em mesa / leito seco
def sec_R(s):
    road = Path(s, 'avenida dos arcos', 1, [(0, 0), (0.15, 120), (0.35, 40), (0.5, 140), (0.65, 40), (0.85, 120), (1, 0)], ROAD_HW, ground=True)
    arches_over(s, road, (0.15, 0.3, 0.45, 0.6, 0.75, 0.88), sc=1.6)
    MH = 0.072       # meia-largura de cada mesa (em u); falhas de ~0.025 (~90 m) para saltar
    mesas = [(0.257, 52.0), (0.426, 48.0), (0.595, 44.0), (0.764, 40.0)]
    for uc, hh in mesas:
        stamp_rect(s, uc - MH, uc + MH, -460, -240, hh, corner=60, edge=8, wobble=12, flat=True)
    def mh(u):
        h = GROUND + (mesas[0][1] - GROUND) * smooth(0.06, 0.17, u)
        for k, (uc, hh) in enumerate(mesas):
            on = (u > uc - MH) & (u < uc + MH)
            h = np.where(on, hh, h)
        h = np.where((u > mesas[0][0] + MH) & ~np.any([(u > uc - MH) & (u < uc + MH) for uc, _ in mesas], axis=0), GROUND, h)
        return np.where(u > mesas[-1][0] + MH, GROUND, h)
    hop = Path(s, 'de mesa em mesa', 2, [(0, 0), (0.06, -110), (0.13, -280), (0.2, -350), (0.8, -350), (0.87, -280), (0.94, -110), (1, 0)], 24, hfun=mh)
    for uc, hh in mesas:
        hop.kicker(hop.s_at_u(uc + MH - 0.004), rise=2.5, run=30, terrain=False)
    carve(hop, 6, hw=26, mode='fill')
    us = np.linspace(0, 1, 40)
    wash = Path(s, 'leito seco', 0, [(float(u), float(330 + 110 * math.sin(u * 9.0) * smooth(0.05, 0.15, u) * (1 - smooth(0.85, 0.95, u))) * (smooth(0.0, 0.12, u) * (1 - smooth(0.88, 1.0, u)))) for u in us],
                26, hfun=lambda u: GROUND + (-10 - GROUND) * smooth(0.08, 0.16, u) * (1 - smooth(0.84, 0.92, u)))
    carve(road, 60)
    carve(wash, 14, 'set')

# K — vale dos cristais: estrada entre cristais gigantes / gruta de cristal
def sec_K(s):
    TOP = 70.0
    stamp_rect(s, 0.3, 0.7, -320, 260, TOP, corner=150, edge=60, wobble=80, rough=40)
    road = Path(s, 'vale dos cristais', 1, [(0, 0), (0.12, 220), (0.3, 420), (0.5, 460), (0.7, 420), (0.88, 220), (1, 0)], ROAD_HW, ground=True)
    cave = Path(s, 'gruta de cristal', 0, [(0, 0), (0.18, 0), (0.5, 0), (0.82, 0), (1, 0)], 19,
                hfun=lambda u: GROUND + (-6 - GROUND) * smooth(0.18, 0.3, u) * (1 - smooth(0.7, 0.82, u)))
    carve(road, 60)
    carve(cave, 12, 'set')
    tunnel(s, cave, 0.27, 0.73, f'tunel_{s.tag}')
    for f in np.linspace(0.1, 0.9, 12):   # cristais gigantes ao longo do vale
        c, t, h = road.at_s(f * road.L); n = np.array([-t[1], t[0]])
        for sg in (-1, 1):
            q = c + n * sg * float(rng.uniform(ROAD_HW + 14, ROAD_HW + 60))
            s.deco.append((str(rng.choice(['crystals_cyan_big', 'crystals_mag_big'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(2.5, 4.5)), 0.8, None))

# O — oásis: dunas à volta / pelas lagoas com palmeiras / crista de areia
def sec_O(s):
    for k, (uc, wc) in enumerate([(0.32, 0), (0.55, 30), (0.75, -20)]):
        lake(s, uc, wc, 150.0, 110.0, depth=3.0, shore=0.5)
        for m in range(10):
            a = rng.uniform(0, 2 * math.pi); r = rng.uniform(1.15, 1.6)
            q = s.W(uc + math.cos(a) * 150 * r / s.Ls, wc + math.sin(a) * 110 * r)
            s.deco.append(('palm', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(0.9, 1.5)), 0.3, None))
    road = Path(s, 'dunas à volta', 1, [(0, 0), (0.12, 200), (0.32, 300), (0.55, 330), (0.75, 300), (0.9, 160), (1, 0)], ROAD_HW, ground=True)
    for f in (0.3, 0.5, 0.7):
        road.kicker(f * road.L, rise=3.0)
    pools = Path(s, 'pelas lagoas', 3, [(0, 0), (0.32, 0), (0.55, 30), (0.75, -20), (1, 0)], 30, ground=True)
    pools.h = np.maximum(pools.h, WATER_Y)
    ridge = Path(s, 'crista de areia', 2, [(0, 0), (0.05, -60), (0.12, -190), (0.2, -260), (0.8, -260), (0.88, -190), (0.95, -60), (1, 0)], 20,
                 hfun=lambda u: GROUND + 24 * smooth(0.04, 0.18, u) * (1 - smooth(0.82, 0.96, u)))
    for g in (0.4, 0.6):
        ridge.kicker(ridge.s_at_u(g) - 28, rise=2.0, run=30)
    carve(road, 60)
    carve(pools, 30, 'cut')
    carve(ridge, 40, 'fill')
    for g in (0.4, 0.6):
        c, t, _ = ridge.at_s(ridge.s_at_u(g)); n = np.array([-t[1], t[0]])
        carve(Line(c - n * 70, c + n * 70, GROUND + 1, 22), 6, 'cut')

# S — planície de sal: estrada entre pilares de sal / lagoas espelho / gruta de sal
def sec_S(s):
    sj, si = s.box(0.0, 1.0, -900, 900, 200)
    um, wm = s.UW(X[sj, si], Z[sj, si])
    m = (1 - smooth(800, 1000, np.abs(wm))) * smooth(-150, 50, um) * (1 - smooth(s.Ls - 50, s.Ls + 150, um))
    H[sj, si] = H[sj, si] + (3.0 + 0.3 * (fbm(X[sj, si] / 60, Z[sj, si] / 60) - 0.5) - H[sj, si]) * m
    lake(s, 0.5, 0, 0.36 * s.Ls, 110.0, depth=1.5, shore=0.25)
    road = Path(s, 'entre os pilares', 1, [(0, 0), (0.12, 200), (0.3, 300), (0.5, 260), (0.7, 300), (0.88, 200), (1, 0)], ROAD_HW, ground=True)
    mirror = Path(s, 'lagoas espelho', 3, [(0, 0), (0.5, 0), (1, 0)], 30, ground=True)
    mirror.h = np.maximum(mirror.h, WATER_Y)
    cave = Path(s, 'gruta de sal', 0, [(0, 0), (0.05, -120), (0.12, -330), (0.17, -420), (0.2, -420), (0.8, -420), (0.83, -420), (0.88, -330), (0.95, -120), (1, 0)], 19,
                hfun=lambda u: GROUND + (-16 - GROUND) * smooth(0.12, 0.2, u) * (1 - smooth(0.8, 0.88, u)))
    carve(road, 60)
    carve(cave, 12, 'set')
    tunnel(s, cave, 0.21, 0.79, f'tunel_{s.tag}')
    for f in np.linspace(0.1, 0.9, 14):   # pilares de sal brancos
        c, t, h = road.at_s(f * road.L); n = np.array([-t[1], t[0]])
        q = c + n * float(rng.choice([-1, 1])) * float(rng.uniform(ROAD_HW + 12, ROAD_HW + 90))
        s.deco.append((str(rng.choice(['rock_spire_b', 'rock_spire_a', 'crystals_cyan_big'])), q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(1.0, 2.2)), 0.8, None))

# T — floresta gigante: trilho / cumes com saltos / leito do rio
def sec_T(s):
    road = Path(s, 'trilho da floresta', 1, [(0, 0), (0.12, -160), (0.3, 120), (0.5, -140), (0.7, 150), (0.88, -80), (1, 0)], ROAD_HW, ground=True)
    ridge = Path(s, 'cumes', 2, [(0, 0), (0.05, 120), (0.12, 300), (0.2, 380), (0.8, 380), (0.88, 300), (0.95, 120), (1, 0)], 22,
                 hfun=lambda u: GROUND + 32 * smooth(0.05, 0.17, u) * (1 - smooth(0.83, 0.95, u)))
    gaps = [0.36, 0.55, 0.72]
    for g in gaps:
        ridge.kicker(ridge.s_at_u(g) - 28, rise=2.0, run=30)
    river = Path(s, 'leito do rio', 3, [(0, 0), (0.04, -120), (0.1, -320), (0.17, -400), (0.83, -400), (0.9, -320), (0.96, -120), (1, 0)], 30,
                 hfun=lambda u: GROUND + (-2.5 - GROUND) * smooth(0.06, 0.11, u) * (1 - smooth(0.89, 0.94, u)))
    carve(road, 60)
    carve(ridge, 40, 'fill')
    for g in gaps:
        c, t, _ = ridge.at_s(ridge.s_at_u(g)); n = np.array([-t[1], t[0]])
        carve(Line(c - n * 70, c + n * 70, GROUND + 1, 22), 6, 'cut')
    carve(river, 14, 'set', hw=36)
    river.h = np.maximum(river.h, WATER_Y)
    water(s, 0.1, 0.9, -440, -360)
    for f in np.linspace(0.08, 0.92, 16):   # árvores gigantes junto ao trilho (obstáculos)
        c, t, h = road.at_s(f * road.L); n = np.array([-t[1], t[0]])
        q = c + n * float(rng.choice([-1, 1])) * float(rng.uniform(ROAD_HW + 10, ROAD_HW + 50))
        s.deco.append(('tree_giant', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(0.9, 1.3)), 0.5, None))

BUILD = {'A': sec_A, 'B': sec_B, 'C': sec_C, 'D': sec_D, 'E': sec_E, 'F': sec_F, 'G': sec_G, 'H': sec_H,
         'P': sec_P, 'M': sec_M, 'V': sec_V, 'L': sec_L, 'R': sec_R, 'K': sec_K, 'O': sec_O, 'S': sec_S, 'T': sec_T}

# ================================================================== mundo: a corrida em serpentina por todas as áreas
# Linha 0 de oeste para este, linha 1 de este para oeste, etc. Cada área tem um portão à entrada
# (na fronteira com a anterior), um no meio e um à saída; o percurso de A a B passa por todas.
order = []
for j in range(4):
    cols = range(4) if j % 2 == 0 else range(3, -1, -1)
    for i in cols:
        order.append(next(a for a in AREAS if a[0] == i and a[1] == j))

border_cache = {}
def border_point(a_from, a_to):
    """Ponto na fronteira entre duas áreas vizinhas, desviado do meio para a corrida serpentear."""
    key = tuple(sorted([(a_from[0], a_from[1]), (a_to[0], a_to[1])]))
    if key not in border_cache:
        ca, cb = area_center(a_from[0], a_from[1]), area_center(a_to[0], a_to[1])
        d = (cb - ca) / np.linalg.norm(cb - ca)
        side = np.array([-d[1], d[0]])
        border_cache[key] = (ca + cb) / 2 + side * float(rng.choice([-1, 1])) * float(rng.uniform(700, 1400))
    return border_cache[key]

hubs, sec_specs = [], []
first, last = order[0], order[-1]
start = area_center(first[0], first[1]) + np.array([-2400.0, -900.0])
hubs.append(start)
for n, a in enumerate(order):
    c = area_center(a[0], a[1])
    exit_p = border_point(a, order[n + 1]) if n + 1 < len(order) else c + np.array([-2400.0, 900.0])
    codes = a[6]
    if len(codes) == 1:          # maciço: um só trecho de fronteira a fronteira
        sec_specs.append((a, codes[0], hubs[-1], exit_p, c))
    else:
        entry = hubs[-1]
        d = exit_p - entry
        side = np.array([-d[1], d[0]]) / max(np.linalg.norm(d), 1.0)
        # o meio fica do lado contrário ao desvio das fronteiras: a corrida faz um zigue-zague pela área
        lean = -np.sign(np.dot((entry + exit_p) / 2 - c, side)) or 1.0
        mid = c + side * lean * float(rng.uniform(600, 1100))
        sec_specs.append((a, codes[0], entry, mid, c))
        hubs.append(mid)
        sec_specs.append((a, codes[1], mid, exit_p, c))
    hubs.append(exit_p)

print('chão plano nos portões...')
for hb in hubs:
    sj, si = grid_box(hb[0] - 160, hb[0] + 160, hb[1] - 160, hb[1] + 160)
    d = np.hypot(X[sj, si] - hb[0], Z[sj, si] - hb[1])
    H[sj, si] = H[sj, si] + (GROUND - H[sj, si]) * (1 - smooth(70, 150, d))

secs = []
for k, (a, code, A_, B_, c) in enumerate(sec_specs):
    s = Sec(code, A_, B_, a[4], c, f'{k:02d}{code.lower()}')
    s.area = a
    BUILD[code](s)
    secs.append(s)
    print(f'{k:2d} {a[3]:<24} {code}  {s.Ls:5.0f} m  ' + ' | '.join(f'{p.name} ({p.L:.0f})' for p in s.paths))

# ================================================================== provas novas: dois circuitos com voltas e uma reta de arranque
# Ficam em sítios do mundo longe dos caminhos da grande corrida e trazem cenário próprio:
# túneis, ponte sobre um rio, saltos, monumentos gigantes e faixas de impulso.
print('provas novas...')
class EvSec:
    def __init__(s, key, title, biome, kind, laps):
        s.key = s.code = key; s.tag = key; s.title = title; s.biome = biome
        s.kind, s.laps = kind, laps
        s.paths, s.deco, s.plan = [], [], []        # plan: colossos a pôr depois (nome, x, z, yaw, escala, afundar)
        s.pads, s.gates_s = [], []                   # faixas de impulso (s, desvio lateral) e portões (s)
        s.no_obst = False

pts_main = np.vstack([p.P for s_ in secs for p in s_.paths])
ev_secs, ev_pts = [], []

def place_shape(local, region, margin, closed=True, angles=16, step=250.0):
    L = np.array(local, float); L = L - L.mean(0)
    seq = np.vstack([L, L[:1]]) if closed else L
    dense = np.vstack([np.linspace(a, b, max(2, int(np.linalg.norm(b - a) / 40))) for a, b in zip(seq, seq[1:])])
    tree = cKDTree(np.vstack([pts_main] + ev_pts))
    best = None
    for ang in np.linspace(0, 2 * math.pi, angles, endpoint=False):
        R = np.array([[math.cos(ang), -math.sin(ang)], [math.sin(ang), math.cos(ang)]])
        rd = dense @ R.T
        for cx in np.arange(region[0], region[1] + 1, step):
            for cz in np.arange(region[2], region[3] + 1, step):
                w = rd + (cx, cz)
                if np.abs(w).max() > 11000:
                    continue
                m = float(tree.query(w)[0].min())
                if best is None or m > best[0]:
                    best = (m, ang, cx, cz)
    m, ang, cx, cz = best
    R = np.array([[math.cos(ang), -math.sin(ang)], [math.sin(ang), math.cos(ang)]])
    W = L @ R.T + (cx, cz)
    print(f'  lugar: centro ({cx:.0f},{cz:.0f}) rodado {math.degrees(ang):.0f}°, a {m:.0f} m dos outros caminhos')
    return [np.array(v) for v in W]

def straight_spots(p, n, run=600.0, keep_off=(), gap=150.0, dev=14.0):
    """n sítios onde a estrada segue quase a direito durante 'run' metros (placas de aceleração:
    o impulso nunca atira o veículo para uma curva). Longe (gap) de túneis, saltos e portões."""
    closed = p_closed(p)
    ds = float(np.median(np.diff(p.S))); w = max(2, int(run / ds)); N = len(p.P)
    PP = np.vstack([p.P, p.P[1:w + 1]]) if closed else p.P
    score = np.full(N, np.inf)
    for i in range(0, N, max(1, int(20 / ds))):
        if i + w >= len(PP):
            break
        a_, b_ = PP[i], PP[i + w]; t_ = (b_ - a_) / max(np.linalg.norm(b_ - a_), 1e-6)
        q = PP[i:i + w + 1] - a_
        score[i] = float(np.abs(q[:, 0] * t_[1] - q[:, 1] * t_[0]).max())   # quanto se afasta da reta
    out = []
    for i in np.argsort(score):
        sv = float(p.S[i])
        if score[i] > dev or len(out) >= n:
            break
        if sv < 200:
            continue
        if any(abs(sv - o) < p.L / (n + 3) for o in out):
            continue
        if any(min(abs(sv - k), abs(sv - k + p.L), abs(sv - k - p.L)) < gap for k in keep_off):
            continue
        out.append(sv + 60.0)
    return sorted(out)

def p_closed(p):
    return float(np.linalg.norm(p.P[0] - p.P[-1])) < 20.0

def s_near(p, q):
    return float(p.S[int(np.argmin(np.linalg.norm(p.P - q, axis=1)))])

def hill_at(c, t, ru, rv, top, flat=False):
    """Colina (ou mesa de topo plano) elíptica, alongada ao longo de t."""
    def f(sub, r):
        if flat:
            return np.maximum(sub, sub + (top - sub) * (1 - smooth(0.82, 1.0, r)))
        return np.maximum(sub, sub + (top - sub) * (1 - smooth(0.25, 1.0, r)) ** 1.3)
    stamp_ellipse(c, ru, rv, t, f)

def ravine(p, sv, depth, half, length=420.0):
    """Ravina a atravessar o caminho em s (cortada depois de esculpir o caminho)."""
    c, t, _ = p.at_s(sv); n = np.array([-t[1], t[0]])
    carve(Line(c - n * length / 2, c + n * length / 2, depth, half), 6, 'cut')

def guardians_at(ev, p, sv, sc=1.0, off=80.0):
    c, t, _ = p.at_s(sv); n = np.array([-t[1], t[0]])
    for sg in (-1, 1):
        q = c + n * sg * (p.hw + off * sc)
        ev.plan.append(('colosso_estatua', q[0], q[1], yaw_of(-t[0], -t[1]), sc, 4.0))

def over_track(ev, p, sv, name, sc, sink=2.0):
    c, t, _ = p.at_s(sv)
    ev.plan.append((name, c[0], c[1], yaw_of(t[0], t[1]), sc, sink, 'over'))

# ---------- Circuito da Floresta: túnel debaixo de uma colina, ponte sobre um rio, salto numa ravina, árvores gigantes
LOC_F = [(0, 0), (600, 0), (1200, 0), (1800, 0), (2400, 250), (2800, 700), (2800, 1000), (2800, 1150), (2800, 1750),
         (2800, 1900), (2500, 2300), (1900, 2500), (1300, 2500), (800, 2300), (300, 1900), (-200, 1300), (-500, 700), (-500, 250)]
Wf = place_shape(LOC_F, (-10600, -7600, 1300, 4900), 320, step=150.0)
evf = EvSec('floresta', 'Circuito da Floresta', 'forest', 'circuit', 3)
fp = Path(None, 'circuito da floresta', 1, Wf, 34, ground=True, world=True, closed=True)
evf.paths.append(fp)
sB, sC = s_near(fp, Wf[7]), s_near(fp, Wf[8])
sR = s_near(fp, (Wf[11] + Wf[12]) / 2)                        # rio
sJ = s_near(fp, Wf[12] * 0.45 + Wf[13] * 0.55)                  # ravina do salto
fp.kicker(sJ - 16 - 6 - 4, rise=3.0, run=40)
tB = (Wf[8] - Wf[7]) / np.linalg.norm(Wf[8] - Wf[7])
hill_at((Wf[7] + Wf[8]) / 2, tB, 520, 380, float(np.max(sample(np.array([(Wf[7] + Wf[8]) / 2])))) + 80)
carve(fp, 50)
tunnel(None, fp, sB / fp.L, sC / fp.L, 'tunel_cf', thw=fp.hw + 4, clear=36.0)
cR, tR, hR = fp.at_s(sR); nR = np.array([-tR[1], tR[0]])
carve(Line(cR - nR * 520, cR + nR * 520, -9.0, 24), 14, 'cut')
waters.append({'c': [float(cR[0]), float(cR[1])], 'sx': 34.0, 'sz': 520.0, 'yaw': yaw_of(nR[0], nR[1]), 'y': float(WATER_Y)})
bridge(fp, sR, 2 * (24 + 14) + 34, 'ponte_cf', deck=float(hR), width=2 * fp.hw + 8, deep=30.0)
ravine(fp, sJ, GROUND - 14, 16)
guardians_at(evf, fp, s_near(fp, Wf[2]), 1.0)
for f_ in np.linspace(0.62, 0.95, 9):                            # árvores gigantes a ladear a estrada
    c, t, _ = fp.at_s(f_ * fp.L); n = np.array([-t[1], t[0]])
    for sg in (-1, 1):
        q = c + n * sg * (fp.hw + float(rng.uniform(45, 75)))
        evf.plan.append(('tree_giant', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(4.0, 6.0)), 2.0))
cin = np.mean(np.array(Wf), axis=0)
evf.plan.append(('tree_giant', cin[0], cin[1], 0.3, 9.0, 3.0))  # a árvore-mundo no meio do circuito
evf.gates_s = [fp.L * k / 6 for k in range(1, 6)] + [0.0]
evf.pads = [(sv, 0.0) for sv in straight_spots(fp, 4, keep_off=[sB, sC, sJ, sR] + evf.gates_s)]
ev_secs.append(evf); ev_pts.append(fp.P)
print(f'  Circuito da Floresta: {fp.L:.0f} m, placas em', [round(a) for a, _ in evf.pads])

# ---------- Circuito dos Monumentos: anel gigante, arco colossal, túnel debaixo de uma mesa, salto, pirâmide e obeliscos
LOC_M = [(0, 0), (700, 0), (1400, 0), (2000, 200), (2400, 600), (2500, 1100), (2300, 1600), (1900, 1900), (1700, 1900),
         (1100, 1900), (900, 1900), (400, 1700), (0, 1300), (-300, 800), (-350, 300)]
Wm = place_shape(LOC_M, (1500, 4600, 1500, 4600), 320, step=150.0)
evm = EvSec('monumentos', 'Circuito dos Monumentos', 'desert', 'circuit', 3)
mp_ = Path(None, 'circuito dos monumentos', 1, Wm, 34, ground=True, world=True, closed=True)
evm.paths.append(mp_)
sB, sC = s_near(mp_, Wm[8]), s_near(mp_, Wm[9])
sJ = s_near(mp_, (Wm[11] + Wm[12]) / 2)
mp_.kicker(sJ - 20 - 6 - 4, rise=3.0, run=40)
tB = (Wm[9] - Wm[8]) / np.linalg.norm(Wm[9] - Wm[8])
hill_at((Wm[8] + Wm[9]) / 2, tB, 440, 300, float(np.max(sample(np.array([(Wm[8] + Wm[9]) / 2])))) + 70, flat=True)
carve(mp_, 50)
tunnel(None, mp_, sB / mp_.L, sC / mp_.L, 'tunel_cm', thw=mp_.hw + 4, clear=36.0)
ravine(mp_, sJ, GROUND - 16, 20)
over_track(evm, mp_, s_near(mp_, Wm[1]) + 40, 'rock_ring', 11.0)
over_track(evm, mp_, s_near(mp_, (Wm[4] + Wm[5]) / 2), 'arch_giant', 4.5)
guardians_at(evm, mp_, s_near(mp_, (Wm[13] + Wm[14]) / 2), 1.05)
cin = np.mean(np.array(Wm), axis=0)
evm.plan.append(('piramide', cin[0], cin[1], 0.4, 2.2, 6.0))
for k in range(4):
    a = 0.4 + math.pi / 4 + k * math.pi / 2
    q = cin + np.array([math.cos(a), math.sin(a)]) * 470
    evm.plan.append(('obelisco', q[0], q[1], a, 1.6, 1.0))
c0, t0, _ = mp_.at_s(25.0); n0 = np.array([-t0[1], t0[0]])
for sg in (-1, 1):
    q = c0 + n0 * sg * (mp_.hw + 30)
    evm.plan.append(('obelisco', q[0], q[1], yaw_of(t0[0], t0[1]), 0.6, 1.0))
evm.gates_s = [mp_.L * k / 6 for k in range(1, 6)] + [0.0]
evm.pads = [(sv, 0.0) for sv in straight_spots(mp_, 3, keep_off=[sB, sC, sJ] + evm.gates_s)]
ev_secs.append(evm); ev_pts.append(mp_.P)
print(f'  Circuito dos Monumentos: {mp_.L:.0f} m, placas em', [round(a) for a, _ in evm.pads])

# ---------- Reta do Sal (drag): 3 km planos, faixas de impulso alternadas, pilares de cristal, guardiões na meta
DRAG_LEN = 3000.0
LOC_D = [(0, 0), (1133, 0), (2266, 0), (3400, 0)]
Wd = place_shape(LOC_D, (-4300, -1800, 7000, 11000), 250, closed=False, angles=8, step=150.0)
evd = EvSec('drag', 'Reta do Sal', 'salt', 'drag', 1)
evd.no_obst = True
dp = Path(None, 'reta do sal', 1, Wd, 46, hfun=lambda u: np.full_like(u, GROUND), world=True)
evd.paths.append(dp)
carve(dp, 220, 'set', hw=dp.hw + 70)
carve(dp, 30, 'set')
drag_line = (Wd[0], Wd[-1])
for k, sv in enumerate(np.arange(450.0, DRAG_LEN - 300, 380.0)):
    evd.pads.append((float(sv), 17.0 * (1 if k % 2 == 0 else -1)))
for sv in np.arange(100.0, dp.L, 200.0):                       # pilares de cristal dos dois lados
    c, t, _ = dp.at_s(sv); n = np.array([-t[1], t[0]])
    for sg in (-1, 1):
        q = c + n * sg * (dp.hw + 28)
        evd.deco.append(('crystals_cyan_big', q[0], q[1], float(rng.uniform(-3, 3)), float(rng.uniform(2.6, 3.4)), 0.8, None))
guardians_at(evd, dp, DRAG_LEN + 60, 1.1, off=70)
c0, t0, _ = dp.at_s(10.0); n0 = np.array([-t0[1], t0[0]])
for sg in (-1, 1):
    q = c0 + n0 * sg * (dp.hw + 35)
    evd.plan.append(('obelisco', q[0], q[1], yaw_of(t0[0], t0[1]), 0.8, 1.0))
evd.gates_s = []
ev_secs.append(evd); ev_pts.append(dp.P)
print(f'  Reta do Sal: {DRAG_LEN:.0f} m (+{dp.L - DRAG_LEN:.0f} m para travar)')
all_secs = secs + ev_secs

# nenhum caminho fica enterrado: corta (sem nunca encher) o chão que ficou acima de cada estrada,
# por exemplo quando um caminho vizinho, esculpido depois, levantou o terreno por cima dela
for s_ in all_secs:
    for p in s_.paths:
        carve(p, 4, 'cut', hw=p.hw * 0.9)

# ------------------------------------------------------------------ colinas por todo o mundo
# Por cima de tudo o que foi esculpido soma-se um campo de colinas suave (U): as estradas sobem e descem
# com o chão. Perto do que é rígido (túneis, pontes, aqueduto, tetos, água) e dos abismos U vai a zero,
# para essas peças ficarem exatamente onde foram desenhadas.
print('colinas...')
AMP = {'sandstone': 32, 'red': 30, 'peaks': 50, 'coast': 22, 'meadow': 58, 'savanna': 44, 'massif': 50, 'lagoon': 20,
       'jungle': 46, 'desert': 56, 'arches': 36, 'forest': 52, 'salt': 14, 'crystals': 40, 'oasis': 50}
amp = np.zeros_like(H)
for k, a in enumerate(AREAS):
    amp += W_area[k] / wsum * AMP[a[4]]
n1 = fbm(X / 1350 + 31, Z / 1350 - 17, oct=3)
n2 = fbm(X / 540 - 5, Z / 540 + 23, oct=3)
hills = 0.78 * smooth(0.3, 0.72, n1) + 0.22 * smooth(0.25, 0.75, n2)
del n1, n2
MR = 32.0
NM = int(SIZE / MR) + 1
mxs = np.linspace(-HALF, HALF, NM)
MX, MZ = np.meshgrid(mxs, mxs)
pin = np.zeros((NM, NM), bool)
def pin_segment(a, b, r):
    a = np.asarray(a, float); b = np.asarray(b, float)
    i0 = max(0, int((min(a[0], b[0]) - r + HALF) / MR)); i1 = min(NM, int((max(a[0], b[0]) + r + HALF) / MR) + 2)
    j0 = max(0, int((min(a[1], b[1]) - r + HALF) / MR)); j1 = min(NM, int((max(a[1], b[1]) + r + HALF) / MR) + 2)
    px, pz = MX[j0:j1, i0:i1], MZ[j0:j1, i0:i1]
    d = b - a; L2 = max(float(d @ d), 1e-6)
    t = np.clip(((px - a[0]) * d[0] + (pz - a[1]) * d[1]) / L2, 0, 1)
    dist = np.hypot(px - (a[0] + t * d[0]), pz - (a[1] + t * d[1]))
    pin[j0:j1, i0:i1] |= dist < r
def fwd_of(yaw):
    return np.array([-math.sin(yaw), -math.cos(yaw)])
for t in tunnels:
    a = np.array([t['p'][0], t['p'][2]]); pin_segment(a, a + fwd_of(t['yaw']) * t['len'], 150)
for b in bridges:
    a = np.array([b['p'][0], b['p'][2]]); pin_segment(a, a + fwd_of(b['yaw']) * b['len'], 130)
for aq in aqueducts:
    a = np.array([aq['p'][0], aq['p'][2]]); pin_segment(a, a + fwd_of(aq['yaw']) * aq['n'] * aq['seg'], 110)
for r in roofs:
    a = np.array([r['p'][0], r['p'][2]]); pin_segment(a - fwd_of(r['yaw']) * 190, a + fwd_of(r['yaw']) * 20, 150)
for w in waters:
    c = np.array(w['c']); f = fwd_of(w['yaw']); n = np.array([-f[1], f[0]])
    for o in np.linspace(-w['sx'], w['sx'], max(2, int(w['sx'] / 60) + 1)):
        pin_segment(c + n * o - f * w['sz'], c + n * o + f * w['sz'], 120)
pin_segment(drag_line[0], drag_line[1], 300)      # a reta do sal fica perfeitamente plana
deep = H[::4, ::4][:NM, :NM] < -12.0
pin |= binary_dilation(deep, iterations=4)
pin_d = distance_transform_edt(~pin) * MR
free_c = smooth(0.0, 400.0, pin_d).astype(np.float32)
M_free = zoom(free_c, RES / NM, order=1)   # 769 -> 3073 (cantos alinhados)
assert M_free.shape == (RES, RES), M_free.shape
U = (1.3 * amp * hills * M_free).astype(np.float32)
del amp, hills, M_free
# serras e picos LONGE dos caminhos: as estradas correm em vales, com montanhas à volta e no horizonte
print('serras...')
pts_all = np.vstack([p.P for s_ in all_secs for p in s_.paths])
occ = np.zeros((NM, NM), bool)
occ[np.clip(np.round((pts_all[:, 1] + HALF) / MR).astype(int), 0, NM - 1), np.clip(np.round((pts_all[:, 0] + HALF) / MR).astype(int), 0, NM - 1)] = True
path_d = distance_transform_edt(~occ) * MR
AMP_FAR = {'sandstone': 150, 'red': 170, 'peaks': 300, 'coast': 70, 'meadow': 160, 'savanna': 110, 'massif': 260, 'lagoon': 60,
           'jungle': 180, 'desert': 130, 'arches': 140, 'forest': 190, 'salt': 50, 'crystals': 210, 'oasis': 110}
ampf = np.zeros((NM, NM), np.float32)
for k, a in enumerate(AREAS):
    ampf += (W_area[k][::4, ::4] / wsum[::4, ::4])[:NM, :NM] * AMP_FAR[a[4]]
rg = 1.0 - np.abs(2.0 * fbm(MX / 1500 + 7, MZ / 1500 - 3, oct=4) - 1.0)     # cristas (ruído "ridged")
mass = smooth(0.25, 0.7, fbm(MX / 3200 - 9, MZ / 3200 + 4, oct=2))
far_c = ampf * (0.25 + 0.75 * rg ** 1.6) * (0.45 + 0.55 * mass) * smooth(240.0, 1150.0, path_d) * free_c
far_c *= 1 - smooth(11000.0, 11800.0, np.maximum(np.abs(MX), np.abs(MZ)))   # a borda já tem a sua cordilheira
FAR = zoom(far_c.astype(np.float32), RES / NM, order=1)
U += FAR
print('  serras: altura média %.0f m, máx %.0f m' % (float(FAR.mean()), float(FAR.max())))
del FAR, far_c, ampf, rg, mass, path_d, occ, MX, MZ, pin_d, free_c
H += U
gz_, gx_ = np.gradient(U, CELL)
slope_u = np.hypot(gx_, gz_)
print('  inclinação das colinas: mediana %.1f%%  p90 %.1f%%  p99 %.1f%%  máx %.1f%%' % tuple(100 * np.percentile(slope_u, q) for q in (50, 90, 99, 100)))
del gz_, gx_, slope_u

def U_at(x, z):
    return float(sample_arr(U, np.array([[x, z]]))[0])

for s_ in all_secs:
    for p in s_.paths:
        uu = sample_arr(U, p.P)
        p.h = p.h + uu
        p.ht = p.ht + uu
hub_y = [GROUND + U_at(hb[0], hb[1]) for hb in hubs]

# ------------------------------------------------------------------ biomas
print('biomas...')
STEP = 2
biome = np.zeros((RES // STEP + 1, RES // STEP + 1, 4), np.float32)
for k, a in enumerate(AREAS):
    w = (W_area[k] / wsum)[::STEP, ::STEP]
    biome += w[..., None] * np.array(B_CH[a[4]], np.float32)
Xd, Zd = X[::STEP, ::STEP], Z[::STEP, ::STEP]
grid_pts = np.stack([Xd.ravel(), Zd.ravel()], 1)
allP = np.vstack([p.P for s in all_secs for p in s.paths])
path_hw = np.concatenate([np.full(len(p.P), p.hw) for s in all_secs for p in s.paths])
path_tree = cKDTree(allP)
ground_paths = np.vstack([p.P for s in all_secs for p in s.paths if p.level == 1])
road_d, _ = cKDTree(ground_paths).query(grid_pts, workers=-1)
road = (1 - smooth(18, 34, road_d)).reshape(Xd.shape)            # caminhos de terra nas zonas verdes
biome[..., 0] *= 1 - 0.85 * road
biome[..., 1] *= 1 - 0.85 * road
beach = 1 - smooth(WATER_Y + 1.5, WATER_Y + 5, H[::STEP, ::STEP])  # praias sem relva
biome[..., 0] *= 1 - beach; biome[..., 1] *= 1 - beach
biome[..., 3] = np.maximum(biome[..., 3], beach * 0.8)
biome = np.clip(biome, 0, 1)
BRES = 1536
biome8 = (biome[:BRES, :BRES] * 255).astype(np.uint8)
area_idx = np.argmax(np.stack([w[::8, ::8] for w in W_area]), axis=0)   # área de cada ponto (de 64 em 64 m)

def area_at(x, z):
    i = int(np.clip((x + HALF) / (CELL * 8), 0, area_idx.shape[1] - 1)); j = int(np.clip((z + HALF) / (CELL * 8), 0, area_idx.shape[0] - 1))
    return AREAS[int(area_idx[j, i])]

def biome_at(x, z):
    i = int(np.clip((x + HALF) / (CELL * STEP), 0, biome.shape[1] - 1)); j = int(np.clip((z + HALF) / (CELL * STEP), 0, biome.shape[0] - 1))
    return biome[j, i]

def slope_at(x, z):
    e = 6.0
    dx = height_at(x + e, z) - height_at(x - e, z); dz = height_at(x, z + e) - height_at(x, z - e)
    return math.hypot(dx, dz) / (2 * e)

def free_of_paths(x, z, margin):
    for i in path_tree.query_ball_point([x, z], 260):
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
print('peças...')
for s in all_secs:   # decoração própria de cada trecho (as alturas fixas sobem com as colinas)
    for name, x, z, yaw, sc, sink, y in s.deco:
        add_prop(name, x, z, yaw, sc, sink, y=None if y is None else y + U_at(x, z))

OBST = {'desert': ['boulder_a', 'rock_spire_b', 'rock_spire_a', 'cactus'], 'meadow': ['ruin_column', 'boulder_a', 'pine'],
        'coast': ['rock_spire_b', 'palm', 'ruin_column'], 'sandstone': ['boulder_a', 'rock_spire_b', 'tree_acacia'],
        'jungle': ['crystals_cyan', 'tree_mushroom', 'boulder_a'], 'red': ['rock_spire_a', 'rock_spire_c', 'boulder_b'],
        'peaks': ['pine', 'boulder_b', 'rock_spire_b'], 'savanna': ['tree_acacia', 'boulder_b', 'tree_acacia_b'],
        'massif': ['pine', 'boulder_a', 'ruin_column'], 'lagoon': ['palm', 'boulder_b', 'rock_spire_b'],
        'arches': ['rock_spire_a', 'cactus', 'rock_fin'], 'forest': ['tree_giant', 'pine', 'tree_mushroom'],
        'salt': ['crystals_cyan_big', 'rock_spire_b', 'boulder_a'], 'crystals': ['crystals_mag_big', 'crystals_cyan_big', 'rock_spire_c'],
        'oasis': ['palm', 'cactus', 'boulder_a']}
for s in all_secs:   # obstáculos dentro dos caminhos (desviar, ou passar por cima das pedras baixas)
    if getattr(s, 'no_obst', False):
        continue
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
                if in_tunnel(q[0], q[1]):
                    name, sc = str(rng.choice(['crystals_cyan', 'crystals_mag'])), float(rng.uniform(0.9, 1.2))
                elif wide:
                    name = str(rng.choice(OBST[s.biome])); sc = float(rng.uniform(0.6, 1.0))
                    if name.startswith('tree') or name in ('pine', 'palm'):
                        sc = float(rng.uniform(0.9, 1.3))
                else:
                    name, sc = str(rng.choice(['boulder_a', 'boulder_b'])), float(rng.uniform(0.45, 0.7))
                add_prop(name, q[0], q[1], float(rng.uniform(-3, 3)), sc, 0.8)
            d += (190.0 if wide else 340.0) * float(rng.uniform(0.8, 1.3))

SCATTER = {
    'desert': [('rock_spire_a', 3), ('rock_spire_b', 3), ('rock_spire_c', 2), ('boulder_a', 2), ('arch', 2), ('arch_giant', 1),
               ('rock_ring', 1), ('rock_fin', 1.5), ('butte', 0.7), ('mesa', 0.6), ('cactus', 3), ('dead_tree', 1)],
    'red': [('rock_spire_a', 3), ('rock_spire_c', 3), ('rock_fin', 2), ('butte', 1), ('arch', 1.5), ('boulder_b', 2), ('cactus', 1)],
    'sandstone': [('tree_acacia', 3), ('tree_acacia_b', 2), ('tower_pod', 1.2), ('rock_spire_b', 1.5), ('boulder_a', 1.5), ('arch', 1), ('bush', 1.5)],
    'meadow': [('tree_acacia', 3), ('tree_acacia_b', 2), ('pine', 2), ('ruin_column', 2), ('ruin_wall', 2), ('tower_pod', 0.8),
               ('boulder_a', 1.5), ('arch_giant', 0.4), ('bush', 3)],
    'coast': [('palm', 3), ('tree_acacia_b', 1), ('rock_spire_b', 2), ('rock_spire_a', 1.5), ('boulder_b', 1.5), ('ruin_column', 1), ('bush', 2)],
    'jungle': [('tree_mushroom', 4), ('tree_giant', 1), ('tree_acacia', 1), ('crystals_cyan', 2), ('crystals_mag', 2), ('boulder_a', 1.5), ('bush', 2)],
    'peaks': [('pine', 6), ('boulder_b', 2), ('rock_spire_c', 1), ('bush', 2), ('rock_fin', 0.8)],
    'savanna': [('tree_acacia', 6), ('tree_acacia_b', 4), ('boulder_b', 2), ('bush', 3), ('dead_tree', 1)],
    'massif': [('pine', 4), ('tree_acacia', 2), ('boulder_a', 2), ('bush', 2), ('ruin_column', 1)],
    'lagoon': [('palm', 6), ('bush', 2), ('boulder_b', 1), ('rock_spire_b', 1)],
    'arches': [('arch', 3), ('arch_twin', 2), ('rock_ring', 2), ('rock_fin', 2), ('rock_spire_a', 2), ('cactus', 2), ('butte', 1)],
    'forest': [('tree_giant', 4), ('pine', 4), ('tree_mushroom', 1), ('bush', 3), ('boulder_a', 1)],
    'salt': [('crystals_cyan_big', 2), ('rock_spire_b', 3), ('crystals_cyan', 2), ('boulder_a', 1)],
    'crystals': [('crystals_cyan_big', 3), ('crystals_mag_big', 3), ('crystals_cyan', 2), ('crystals_mag', 2), ('rock_spire_c', 1), ('rock_fin', 1)],
    'oasis': [('cactus', 3), ('palm', 2), ('dead_tree', 1), ('rock_spire_b', 1), ('boulder_a', 1), ('bush', 1)],
}
RADIUS = {'rock_spire_a': 7, 'rock_spire_b': 6, 'rock_spire_c': 9, 'boulder_a': 4, 'boulder_b': 6, 'arch': 16, 'arch_giant': 44,
          'arch_twin': 30, 'rock_ring': 20, 'rock_fin': 18, 'butte': 70, 'mesa': 30, 'tree_acacia': 7, 'tree_acacia_b': 6,
          'tree_mushroom': 9, 'tower_pod': 8, 'ruin_column': 3, 'ruin_wall': 10, 'crystals_cyan': 4, 'crystals_mag': 4, 'pillar': 4,
          'cactus': 3, 'palm': 5, 'pine': 5, 'tree_giant': 16, 'bush': 3, 'dead_tree': 5, 'crystals_cyan_big': 10, 'crystals_mag_big': 10}
BIG = ('butte', 'mesa', 'arch_giant', 'arch_twin', 'rock_ring', 'rock_fin', 'arch', 'tree_giant')
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

# ------------------------------------------------------------------ estruturas colossais (marcos que se vêem do horizonte)
# Umas por cima das estradas (arcos, anéis, esqueleto, guardiões dos dois lados), outras longe dos caminhos.
print('colossos...')
colossi = []
FOOT = {'colosso_estatua': 46, 'colosso_costelas': 0, 'colosso_nave': 470, 'rock_ring': 0, 'arch_giant': 0,
        'rock_spire_c': 9, 'rock_spire_a': 7, 'butte': 70, 'tree_giant': 14, 'tree_mushroom': 6, 'crystals_cyan': 4,
        'crystals_mag': 4, 'ruin_tower': 11, 'rock_fin': 17, 'float_island': 0, 'piramide': 135, 'obelisco': 12}

def far_from_paths(x, z, r):
    d, i = path_tree.query([x, z])
    return d > r + path_hw[i] + 10

def ground_min(x, z, r):
    pts = [(x, z)] + [(x + r * f * math.cos(a), z + r * f * math.sin(a)) for f in (0.5, 1.0) for a in np.linspace(0, 2 * math.pi, 9)[:-1]]
    return float(min(sample(np.array(pts))))

def colossus(name, x, z, yaw, sc, sink=3.0, y=None, foot=None, occ=True):
    r = FOOT.get(name, 10) * sc if foot is None else foot
    y0 = ground_min(x, z, max(r, 20.0)) if y is None else y
    colossi.append([name, round(float(x), 1), round(float(y0 - sink), 2), round(float(z), 1), round(float(yaw), 3), round(float(sc), 3)])
    if occ and r > 0:
        occupy(x, z, r)

def zone(key):
    a = next(x for x in AREAS if x[2] == key)
    return a, area_center(a[0], a[1])

def roads_of(key):
    return [p for s_ in secs if s_.area[2] == key for p in s_.paths if p.level == 1 and p.hw >= 40]

def straight_spot(p, f0, f1, half=150.0, avoid=()):
    best, bs = None, 1e9
    for sv in np.linspace(f0 * p.L, f1 * p.L, 48):
        if any(abs(sv - j) < half + 120 for j in p.jumps) or any(abs(sv - a) < 700 for a in avoid):
            continue
        c, t, h = p.at_s(sv)
        if abs(h - height_at(c[0], c[1])) > 2.0:
            continue
        i0 = int(np.argmin(np.abs(p.S - (sv - half)))); i1 = int(np.argmin(np.abs(p.S - (sv + half))))
        bend = float(np.degrees(np.arccos(np.clip(p.T[i0] @ p.T[i1], -1, 1))))
        if bend < bs:
            best, bs = sv, bend
    return best if bs < 25 else None

def legs_free(c, t, offsets, r):
    n = np.array([-t[1], t[0]])
    for lat, alo in offsets:
        q = c + n * lat + t * alo
        if not free_of_paths(q[0], q[1], r) or occupied(q[0], q[1], r):
            return False
    return True

def over_road(key, name, sc, legs, leg_r, sink=2.0, f0=0.2, f1=0.8, half=150.0, count=1):
    """Põe 'count' estruturas por cima das estradas da zona (pernas fora de todos os caminhos)."""
    placed = 0
    for p in roads_of(key):
        used = []
        for _ in range(3):
            if placed >= count:
                return placed
            sv = straight_spot(p, f0, f1, half, used)
            if sv is None:
                break
            used.append(sv)
            c, t, h = p.at_s(sv)
            offs = [(lat * sc, alo * sc) for lat, alo in legs]
            if not legs_free(c, t, offs, leg_r * sc):
                continue
            nrm = np.array([-t[1], t[0]])
            feet = [c + nrm * lat + t * alo for lat, alo in offs] + [c]
            y = float(min(sample(np.array(feet))))
            colossus(name, c[0], c[1], yaw_of(t[0], t[1]), sc, sink, y=y, occ=False)
            for q in feet[:-1]:
                occupy(q[0], q[1], leg_r * sc)
            placed += 1
    return placed

def guardians(key, sc=1.0, count=1):
    """Dois gigantes de pedra, um de cada lado da estrada, virados para quem chega."""
    placed = 0
    for p in roads_of(key):
        if placed >= count:
            break
        sv = straight_spot(p, 0.12, 0.45, 120)
        if sv is None:
            continue
        c, t, h = p.at_s(sv); n = np.array([-t[1], t[0]])
        off = p.hw + 80 * sc
        qs = [c + n * off, c - n * off]
        if all(free_of_paths(q[0], q[1], 46 * sc) and not occupied(q[0], q[1], 46 * sc) for q in qs):
            for q in qs:
                colossus('colosso_estatua', q[0], q[1], yaw_of(-t[0], -t[1]), sc, 4.0)
            placed += 1
    return placed

def off_road(key, name, n, sc_rng, clear=60.0, sink=3.0, tries=400, spread=2700.0, at_center=False):
    a, c = zone(key)
    placed = 0
    for _ in range(tries):
        if placed >= n:
            break
        q = c + rng.uniform(-spread, spread, 2)
        if area_at(q[0], q[1])[2] != key:
            continue
        sc = float(rng.uniform(*sc_rng))
        r = FOOT[name] * sc
        if not far_from_paths(q[0], q[1], r + clear) or occupied(q[0], q[1], r) or height_at(q[0], q[1]) < WATER_Y + 1.5:
            continue
        colossus(name, q[0], q[1], float(rng.uniform(-math.pi, math.pi)), sc, sink, y=height_at(q[0], q[1]) if at_center else None)
        placed += 1
    return placed

def sky_islands(key, n, sc_rng, alt=(380, 650)):
    a, c = zone(key)
    for _ in range(n):
        q = c + rng.uniform(-2500, 2500, 2)
        sc = float(rng.uniform(*sc_rng))
        colossus('float_island', q[0], q[1], float(rng.uniform(-math.pi, math.pi)), sc, 0.0,
                 y=height_at(q[0], q[1]) + float(rng.uniform(*alt)), foot=0, occ=False)

# monumentos das provas novas (planeados junto com as pistas)
LEGS = {'rock_ring': 13.5, 'arch_giant': 30.0}
for ev in ev_secs:
    for item in ev.plan:
        name, x, z, yaw, sc, sink = item[:6]
        if len(item) > 6:   # por cima da pista: as pernas assentam no chão mais baixo dos dois lados
            f_ = np.array([-math.sin(yaw), -math.cos(yaw)]); n_ = np.array([-f_[1], f_[0]])
            feet = [np.array([x, z]) + n_ * sg * LEGS[name] * sc for sg in (-1, 1)] + [np.array([x, z])]
            colossus(name, x, z, yaw, sc, sink, y=float(min(sample(np.array(feet)))), occ=False)
            for q in feet[:2]:
                occupy(q[0], q[1], 60 * sc / 10)
        else:
            colossus(name, x, z, yaw, sc, sink)

RIBS = [(sg * 80.0, a) for sg in (-1, 1) for a in (-120.0, -40.0, 40.0, 120.0)]
ARCH = [(-150.0, 0.0), (150.0, 0.0)]
RING = [(-160.0, 0.0), (160.0, 0.0)]
n_over = 0
n_over += over_road('arcos', 'arch_giant', 5.0, ARCH, 52, count=2)
n_over += over_road('dunas', 'colosso_costelas', 1.0, RIBS, 14)
n_over += over_road('savana', 'colosso_costelas', 0.9, RIBS, 14)
n_over += over_road('lagoa', 'rock_ring', 12.0, RING, 60)
n_over += over_road('oasis', 'rock_ring', 11.0, RING, 60)
n_over += over_road('colinas', 'rock_ring', 12.0, RING, 60)
n_over += over_road('arenito', 'arch_giant', 4.0, ARCH, 52)
n_over += over_road('prado', 'arch_giant', 4.5, ARCH, 52)
n_guard = 0
for key in ('fenda', 'colinas', 'prado', 'sal', 'picos', 'floresta'):
    n_guard += guardians(key, float(rng.uniform(0.9, 1.15)))
off_road('dunas', 'colosso_nave', 1, (1.25, 1.35), clear=100, sink=12.0, tries=4000, spread=2900, at_center=True)
off_road('sal', 'colosso_nave', 1, (1.1, 1.2), clear=100, sink=8.0, tries=4000, spread=2900, at_center=True)
off_road('arenito', 'rock_spire_c', 5, (8.0, 11.0), clear=90)
off_road('arenito', 'butte', 2, (3.0, 3.6), clear=120)
off_road('fenda', 'rock_fin', 5, (5.0, 7.0), clear=80)
off_road('fenda', 'rock_spire_c', 3, (8.0, 10.0), clear=90)
off_road('picos', 'rock_spire_a', 5, (9.0, 12.0), clear=90)
off_road('picos', 'ruin_tower', 1, (3.2, 3.8), clear=80)
off_road('costa', 'rock_spire_a', 4, (7.0, 10.0), clear=90)
off_road('colinas', 'ruin_tower', 2, (3.0, 3.6), clear=80)
off_road('savana', 'tree_giant', 3, (5.0, 6.5), clear=60)
off_road('macico', 'ruin_tower', 2, (3.5, 4.0), clear=80)
off_road('lagoa', 'rock_spire_a', 4, (7.0, 10.0), clear=90)
off_road('selva', 'tree_mushroom', 4, (14.0, 19.0), clear=60)
off_road('selva', 'tree_giant', 2, (5.5, 7.0), clear=60)
off_road('prado', 'ruin_tower', 2, (3.2, 3.8), clear=80)
off_road('dunas', 'rock_spire_c', 3, (8.0, 11.0), clear=90)
off_road('arcos', 'butte', 3, (3.0, 3.8), clear=120)
off_road('arcos', 'rock_fin', 3, (5.0, 7.0), clear=80)
off_road('floresta', 'tree_giant', 5, (5.0, 7.0), clear=60)
off_road('floresta', 'tree_mushroom', 2, (14.0, 18.0), clear=60)
off_road('sal', 'crystals_cyan', 6, (12.0, 18.0), clear=60)
off_road('cristais', 'crystals_mag', 5, (12.0, 18.0), clear=60)
off_road('cristais', 'crystals_cyan', 5, (12.0, 18.0), clear=60)
off_road('cristais', 'rock_spire_c', 2, (8.0, 10.0), clear=90)
off_road('oasis', 'rock_spire_c', 3, (7.0, 10.0), clear=90)
off_road('oasis', 'tree_giant', 1, (5.0, 6.0), clear=60)
sky_islands('macico', 6, (5.5, 8.5))
sky_islands('picos', 3, (5.0, 7.0))
sky_islands('selva', 3, (5.0, 7.0))
sky_islands('cristais', 3, (5.0, 7.0))
sky_islands('floresta', 2, (5.0, 6.5))
from collections import Counter
print('  colossos:', len(colossi), '| por cima das estradas:', n_over, '| pares de guardiões:', n_guard, '|',
      dict(Counter(c_[0] for c_ in colossi)))

count, tries = 0, 0
while count < 22000 and tries < 600000:
    tries += 1
    if rng.random() < 0.6:
        q = allP[int(rng.integers(0, len(allP)))] + rng.normal(0, 550, 2)
        x, z = float(np.clip(q[0], -11700, 11700)), float(np.clip(q[1], -11700, 11700))
    else:
        x, z = (float(v) for v in rng.uniform(-11700, 11700, 2))
    a = area_at(x, z)
    kinds = SCATTER[a[4]]
    names = [k for k, _ in kinds]; w = np.array([v for _, v in kinds], float); w /= w.sum()
    name = str(rng.choice(names, p=w))
    sc = float(rng.uniform(0.8, 1.3))
    r = RADIUS[name] * sc
    if not free_of_paths(x, z, r + 6):
        continue
    if height_at(x, z) < WATER_Y + 1.0:
        continue
    if (name in ('tree_acacia', 'tree_acacia_b', 'pine', 'palm', 'tree_giant', 'cactus', 'bush', 'tower_pod', 'ruin_column', 'ruin_wall', 'tree_mushroom') or name in BIG) \
            and slope_at(x, z) > 0.35:
        continue
    if occupied(x, z, r):
        continue
    add_prop(name, x, z, float(rng.uniform(-math.pi, math.pi)), sc, 1.5 if name in ('butte', 'mesa') else 0.6)
    occupy(x, z, r); count += 1
print('  espalhadas:', count)

# bandeirolas por cima dos caminhos de chão (perto dos portões)
banners = []
for s in all_secs:
    for p in s.paths:
        if p.level in (1, 3):
            for f in (0.08, 0.92):
                c, t, h = p.at_s(f * p.L)
                if abs(h - height_at(c[0], c[1])) < 2:
                    banners.append([round(float(c[0]), 1), round(float(h), 2), round(float(c[1]), 1), round(yaw_of(t[0], t[1]), 3), float(p.hw * 2 + 16)])

# ilhas flutuantes (por cima do maciço, da selva e dos cristais)
islands = []
for key, n_, hy in (('macico', 20, (300, 460)), ('selva', 6, (300, 420)), ('cristais', 6, (260, 380)), ('floresta', 4, (320, 420))):
    a = next(x for x in AREAS if x[2] == key); c = area_center(a[0], a[1])
    for k in range(n_):
        q = c + rng.uniform(-2400, 2400, 2)
        islands.append([round(float(q[0]), 1), round(float(rng.uniform(*hy)), 1), round(float(q[1]), 1), round(float(rng.uniform(-3, 3)), 2),
                        round(float(rng.uniform(1.5, 4.5)), 2)])

# relva, flores e fetos (sem colisão) perto dos caminhos nas zonas verdes
ground_cover = {'grass_tuft': [], 'flowers': [], 'fern': []}
tries = 0
while sum(len(v) for v in ground_cover.values()) < 30000 and tries < 400000:
    tries += 1
    q = allP[int(rng.integers(0, len(allP)))] + rng.normal(0, 80, 2)
    b = biome_at(q[0], q[1])
    if b[0] + b[1] < 0.55 or not free_of_paths(q[0], q[1], 2):
        continue
    h = height_at(q[0], q[1])
    if h < WATER_Y + 1.2 or slope_at(q[0], q[1]) > 0.3:
        continue
    a = area_at(q[0], q[1])[4]
    roll = rng.random()
    if a in ('jungle', 'forest') and roll < 0.35:
        kind = 'fern'
    elif a in ('meadow', 'savanna', 'lagoon', 'forest', 'massif', 'peaks', 'coast') and roll < 0.25:
        kind = 'flowers'
    else:
        kind = 'grass_tuft'
    ground_cover[kind].append([round(float(q[0]), 1), round(h - 0.2, 2), round(float(q[1]), 1), round(float(rng.uniform(-3, 3)), 2),
                               round(float(rng.uniform(0.8, 1.6)), 2)])

# fauna: manadas a pastar (estáticas)
# ------------------------------------------------------------------ vegetação densa (florestas a sério)
# Dezenas de milhares de árvores, arbustos e fetos, com manchas e clareiras, longe das estradas.
# Vai num ficheiro binário à parte (veg.zst) para o map.json não crescer: 2 palavras de 32 bits por planta.
print('vegetação...')
VEG_TYPES = ['pine', 'tree_acacia', 'tree_acacia_b', 'tree_giant', 'palm', 'cactus', 'bush', 'tree_mushroom', 'dead_tree',
             'fern', 'boulder_a', 'crystals_cyan', 'crystals_mag']
VEG = {'forest': (1600, {'pine': 46, 'tree_acacia': 14, 'tree_giant': 3, 'bush': 22, 'fern': 15}),
       'jungle': (1500, {'tree_mushroom': 6, 'tree_giant': 3, 'tree_acacia': 28, 'tree_acacia_b': 8, 'fern': 30, 'bush': 25}),
       'meadow': (520, {'tree_acacia': 30, 'tree_acacia_b': 20, 'bush': 35, 'pine': 15}),
       'peaks': (560, {'pine': 70, 'bush': 20, 'boulder_a': 10}),
       'massif': (640, {'pine': 50, 'tree_acacia': 15, 'bush': 35}),
       'savanna': (300, {'tree_acacia': 40, 'tree_acacia_b': 30, 'bush': 20, 'dead_tree': 10}),
       'coast': (280, {'palm': 50, 'bush': 40, 'tree_acacia_b': 10}),
       'lagoon': (380, {'palm': 60, 'bush': 40}),
       'oasis': (120, {'palm': 40, 'cactus': 40, 'bush': 20}),
       'desert': (35, {'cactus': 50, 'dead_tree': 25, 'boulder_a': 25}),
       'sandstone': (150, {'tree_acacia': 35, 'bush': 35, 'cactus': 20, 'boulder_a': 10}),
       'red': (45, {'cactus': 40, 'dead_tree': 30, 'boulder_a': 30}),
       'arches': (50, {'cactus': 60, 'dead_tree': 20, 'bush': 20}),
       'salt': (12, {'crystals_cyan': 100}),
       'crystals': (260, {'crystals_cyan': 30, 'crystals_mag': 30, 'pine': 20, 'bush': 20})}
# o que já ocupa o chão (colossos e peças grandes): grelha de 32 m
occ_v = np.zeros((NM, NM), bool)
for cell_items in grid_occ.values():
    for px_, pz_, pr_ in cell_items:
        if pr_ < 6:
            continue
        r_ = int(pr_ / MR) + 1
        ci, cj = int(round((px_ + HALF) / MR)), int(round((pz_ + HALF) / MR))
        occ_v[max(0, cj - r_):cj + r_ + 1, max(0, ci - r_):ci + r_ + 1] = True
# à beira das estradas as árvores são mais cerradas (é o que se vê a alta velocidade)
ROADSIDE = {'forest': 0.8, 'jungle': 0.8, 'meadow': 0.55, 'massif': 0.5, 'peaks': 0.5, 'savanna': 0.4,
            'crystals': 0.4, 'coast': 0.35, 'lagoon': 0.35, 'sandstone': 0.2}

def veg_ok(q):
    """Tira o que cai na estrada, em peças grandes, na água ou em encostas a pique."""
    d_, i_ = path_tree.query(q, workers=-1)
    q = q[d_ > path_hw[i_] + 22]
    oi = np.clip(np.round((q[:, 0] + HALF) / MR).astype(int), 0, NM - 1); oj = np.clip(np.round((q[:, 1] + HALF) / MR).astype(int), 0, NM - 1)
    q = q[~occ_v[oj, oi]]
    e_ = 5.0
    hx = (sample(q + [e_, 0]) - sample(q - [e_, 0])) / (2 * e_); hz = (sample(q + [0, e_]) - sample(q - [0, e_])) / (2 * e_)
    h_ = sample(q)
    return q[(h_ > WATER_Y + 1.5) & (np.hypot(hx, hz) < 0.65)]

veg_q, veg_t = [], []
def veg_add(q, mix):
    names = list(mix); w_ = np.array([mix[nm] for nm in names], float); w_ /= w_.sum()
    ty = rng.choice(len(names), size=len(q), p=w_)
    veg_q.append(q); veg_t.append(np.array([VEG_TYPES.index(names[t]) for t in ty], np.int64))

for k, a in enumerate(AREAS):
    dens, mix = VEG[a[4]]
    c = area_center(a[0], a[1])
    n = int(dens * (AREA / 1000.0) ** 2 * 1.9)
    q = c + rng.uniform(-AREA / 2 - 350, AREA / 2 + 350, (n, 2))
    ii = np.clip(((q[:, 0] + HALF) / (CELL * 8)).astype(int), 0, area_idx.shape[1] - 1)
    jj = np.clip(((q[:, 1] + HALF) / (CELL * 8)).astype(int), 0, area_idx.shape[0] - 1)
    keep = area_idx[jj, ii] == k
    clump = fbm(q[:, 0] / 650 + k * 3.1, q[:, 1] / 650 - k * 1.7, oct=3)
    d_road, _ = path_tree.query(q, workers=-1)
    near = ROADSIDE.get(a[4], 0.0) * (1 - smooth(70, 280, d_road))
    keep &= rng.random(n) < np.maximum(smooth(0.3, 0.62, clump), near)
    keep &= np.abs(q).max(axis=1) < 11700
    veg_add(veg_ok(q[keep]), mix)
# Circuito da Floresta: floresta cerrada dos dois lados da pista (mais cerrada junto à estrada)
for ev_ in ev_secs:
    if ev_.biome != 'forest':
        continue
    for fp_ in ev_.paths:
        n = int(fp_.L * 2 * 440 * 3200e-6)
        k_ = rng.integers(0, len(fp_.P), n)
        nrm = np.stack([-fp_.T[k_, 1], fp_.T[k_, 0]], 1)
        off = rng.uniform(fp_.hw + 20, fp_.hw + 460, n) * rng.choice([-1.0, 1.0], n)
        q = fp_.P[k_] + nrm * off[:, None] + rng.normal(0, 6, (n, 2))
        q = q[rng.random(n) < 1 - smooth(fp_.hw + 160, fp_.hw + 460, np.abs(off))]
        q = veg_ok(q)
        veg_add(q, {'pine': 42, 'tree_acacia': 22, 'tree_acacia_b': 6, 'tree_giant': 4, 'tree_mushroom': 2, 'bush': 14, 'fern': 10})
        print(f'  floresta do circuito: {len(q)} plantas')
veg_q = np.vstack(veg_q); veg_t = np.concatenate(veg_t)
nveg = len(veg_q)
vy = sample(veg_q) - 0.3
yaw_q = rng.integers(0, 64, nveg)
sc_q = np.where(np.isin(veg_t, [VEG_TYPES.index('tree_giant')]), rng.integers(4, 22, nveg), rng.integers(7, 30, nveg))  # escala 0.6 + q*0.03
qx = np.clip(np.round((veg_q[:, 0] + HALF) * 2), 0, 65535).astype(np.uint32)
qz = np.clip(np.round((veg_q[:, 1] + HALF) * 2), 0, 65535).astype(np.uint32)
qy = np.clip(np.round((vy + 100.0) * 64), 0, 65535).astype(np.uint32)
w0 = qx | (qz << 16)
w1 = qy | (veg_t.astype(np.uint32) << 16) | (yaw_q.astype(np.uint32) << 20) | (sc_q.astype(np.uint32) << 26)
veg_words = np.stack([w0, w1], 1).astype('<u4')
from collections import Counter as _C
print('  plantas:', nveg, dict(_C(VEG_TYPES[t] for t in veg_t)))
# o chão das florestas fica mais escuro (copas por cima)
trees_mask = np.isin(veg_t, [VEG_TYPES.index(n_) for n_ in ('pine', 'tree_acacia', 'tree_acacia_b', 'tree_giant', 'tree_mushroom', 'palm')])
hist, _, _ = np.histogram2d(veg_q[trees_mask, 1], veg_q[trees_mask, 0], bins=biome.shape[:2], range=[[-HALF, HALF], [-HALF, HALF]])
canopy = np.clip(gaussian_filter(hist.astype(np.float32), 2.5) * 6.0, 0, 1)
biome[..., 1] = np.clip(biome[..., 1] + canopy * 0.55, 0, 1)
biome[..., 0] = np.clip(biome[..., 0] + canopy * 0.3, 0, 1)
biome8 = (biome[:BRES, :BRES] * 255).astype(np.uint8)

print('fauna...')
herds = []
HERD_AREAS = {'savanna': 12, 'meadow': 3, 'coast': 2, 'lagoon': 2, 'forest': 3, 'peaks': 2, 'massif': 2, 'oasis': 2}
for a in AREAS:
    c = area_center(a[0], a[1])
    for k in range(HERD_AREAS.get(a[4], 0)):
        for _ in range(20):
            hc = c + rng.uniform(-2400, 2400, 2)
            if free_of_paths(hc[0], hc[1], 120) and height_at(hc[0], hc[1]) > WATER_Y + 2 and slope_at(hc[0], hc[1]) < 0.2:
                break
        else:
            continue
        kind = 'grazer' if a[4] != 'savanna' or rng.random() < 0.7 else 'grazer_tall'
        for m in range(int(rng.integers(5, 11))):
            q = hc + rng.normal(0, 28, 2)
            if free_of_paths(q[0], q[1], 60):
                herds.append([kind, round(float(q[0]), 1), round(height_at(q[0], q[1]), 2), round(float(q[1]), 1),
                              round(float(rng.uniform(-math.pi, math.pi)), 2), round(float(rng.uniform(0.85, 1.2)), 2)])

# ------------------------------------------------------------------ corrida, portões, rotas
def route_of(p):
    idx = list(range(0, len(p.P), 4))
    if idx[-1] != len(p.P) - 1:
        idx.append(len(p.P) - 1)
    return [[round(float(p.P[i, 0]), 1), round(float(p.h[i]), 2), round(float(p.P[i, 1]), 1)] for i in idx]

checkpoints = []
for k in range(1, len(hubs) - 1):
    d = secs[k - 1].paths[0].T[-1] + secs[k].paths[0].T[0]; d = d / np.linalg.norm(d)
    checkpoints.append({'p': [float(hubs[k][0]), round(hub_y[k], 2), float(hubs[k][1])], 'dir': [float(d[0]), float(d[1])], 'w': 200.0,
                        'name': secs[k].area[3]})
d0 = secs[0].paths[0].T[0]
start = {'p': [float(hubs[0][0]), round(hub_y[0], 2), float(hubs[0][1])], 'dir': [float(d0[0]), float(d0[1])]}
fe = secs[-1].paths[0].T[-1]
finish = {'p': [float(hubs[-1][0]), round(hub_y[-1], 2), float(hubs[-1][1])], 'dir': [float(fe[0]), float(fe[1])], 'w': 200.0}
def gate_at(p, sv, extra=40.0):
    c, t, h = p.at_s(sv % p.L if p.L > 0 else sv)
    return {'p': [round(float(c[0]), 1), round(float(h), 2), round(float(c[1]), 1)], 'dir': [round(float(t[0]), 4), round(float(t[1]), 4)],
            'w': float(2 * p.hw + extra)}
events, pads = [], []
for ev in ev_secs:
    p = ev.paths[0]
    e = {'id': ev.key, 'name': ev.title, 'type': ev.kind, 'laps': ev.laps, 'length': round(p.L if ev.kind == 'circuit' else DRAG_LEN),
         'route': route_of(p), 'gates': [gate_at(p, sv) for sv in ev.gates_s]}
    if ev.kind == 'circuit':
        st = gate_at(p, p.L - 70.0)
    else:
        st = gate_at(p, 25.0)
        e['finish'] = gate_at(p, DRAG_LEN, 60.0)
    e['start'] = {'p': st['p'], 'dir': st['dir']}
    events.append(e)
    for sv, lat in ev.pads:
        c, t, h = p.at_s(sv); n = np.array([-t[1], t[0]]); q = c + n * lat
        pads.append([round(float(q[0]), 1), round(float(h), 2), round(float(q[1]), 1), round(yaw_of(t[0], t[1]), 3)])

sections = [{'key': s.code if hasattr(s, 'code') else s.key, 'title': s.area[3], 'biome': s.biome,
             'variants': [{'name': p.name, 'level': p.level, 'hw': p.hw, 'length': round(p.L), 'route': route_of(p)} for p in s.paths]} for s in secs]
zones = [{'name': a[3], 'biome': a[4], 'c': [float(area_center(a[0], a[1])[0]), float(area_center(a[0], a[1])[1])]} for a in AREAS]

# ------------------------------------------------------------------ verificação dos caminhos
# Procura buracos (o caminho passa por cima do nada, sem ponte, água ou salto) e paredes (o chão sobe
# acima da estrada) ao longo de todos os caminhos, para apanhar erros antes de ir para o jogo.
print('a verificar os caminhos...')
def support_along(p):
    sup = sample(p.P).astype(float)
    def frame(pp, yaw):
        f = fwd_of(yaw); n = np.array([-f[1], f[0]]); rel = p.P - pp
        return rel @ f, rel @ n
    for b_ in bridges:
        al, sd = frame(np.array([b_['p'][0], b_['p'][2]]), b_['yaw'])
        on = (al >= -2) & (al <= b_['len'] + 2) & (np.abs(sd) <= b_['width'] / 2 + 1) & (np.abs(p.h - b_['p'][1]) < 6)
        sup = np.where(on, np.maximum(sup, b_['p'][1]), sup)
    for aq in aqueducts:
        al, sd = frame(np.array([aq['p'][0], aq['p'][2]]), aq['yaw'])
        seg = np.floor(al / aq['seg']).astype(int)
        on = (al >= 0) & (al <= aq['n'] * aq['seg']) & (np.abs(sd) <= 10) & ~np.isin(seg, aq['missing']) \
             & (np.abs(p.h - aq['p'][1] - aq['deck']) < 6)
        sup = np.where(on, np.maximum(sup, aq['p'][1] + aq['deck']), sup)
    for t in tunnels:
        al, sd = frame(np.array([t['p'][0], t['p'][2]]), t['yaw'])
        lid = t['p'][1] + np.interp(al, np.arange(len(t['tops'])) * t['step'], t['tops'])
        on = (al > 0) & (al < t['len']) & (np.abs(sd) < 40) & (p.h > t['p'][1] + 16)
        sup = np.where(on, np.maximum(sup, lid), sup)
    for w in waters:
        al, sd = frame(np.array(w['c']), w['yaw'])
        on = (np.abs(al) <= w['sz']) & (np.abs(sd) <= w['sx'])
        sup = np.where(on, np.maximum(sup, w['y']), sup)
    return sup

def runs(mask):
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j + 1 < len(mask) and mask[j + 1]:
                j += 1
            out.append((i, j)); i = j + 1
        else:
            i += 1
    return out

problems = 0
for k, s_ in enumerate(all_secs):
    for p in s_.paths:
        sup = support_along(p)
        gap = p.h - sup
        jump_ok = np.zeros(len(p.S), bool)
        for j in p.jumps:
            jump_ok |= (p.S >= j - 5) & (p.S <= j + 260)
        wet = np.zeros(len(p.S), bool)
        for w in waters:
            f = fwd_of(w['yaw']); n = np.array([-f[1], f[0]]); rel = p.P - np.array(w['c'])
            wet |= (np.abs(rel @ f) <= w['sz'] + 30) & (np.abs(rel @ n) <= w['sx'] + 30)
        hole = (gap > 4.0) & ~jump_ok & ~(wet & (gap < 7.0))
        drop_ok = np.zeros(len(p.S), bool)
        for j in p.jumps:
            drop_ok |= (p.S >= j - 2) & (p.S <= j + 15)   # a falésia logo a seguir ao lábio de um salto
        wall = (gap < -3.0) & ~drop_ok
        ceil = np.zeros(len(p.S), bool)
        for t in tunnels:
            f = fwd_of(t['yaw']); n = np.array([-f[1], f[0]]); rel = p.P - np.array([t['p'][0], t['p'][2]])
            al, sd = rel @ f, rel @ n
            inside = (al > 0) & (al < t['len']) & (np.abs(sd) < 17)
            lid = t['p'][1] + np.interp(al, np.arange(len(t['tops'])) * t['step'], t['tops'])
            ceil |= inside & (p.h > t['p'][1] + 12) & (p.h < lid - 2)
        # peças retas (túneis, aqueduto, pontes): o caminho tem de ir pelo meio delas
        crooked = np.zeros(len(p.S), bool)
        for t in tunnels:
            f = fwd_of(t['yaw']); n = np.array([-f[1], f[0]]); rel = p.P - np.array([t['p'][0], t['p'][2]])
            al, sd = rel @ f, rel @ n
            inside = (al > 10) & (al < t['len'] - 10) & (np.abs(sd) < 30) & (np.abs(p.h - t['p'][1]) < 8)
            crooked |= inside & (np.abs(sd) > 6)
        for aq in aqueducts:
            f = fwd_of(aq['yaw']); n = np.array([-f[1], f[0]]); rel = p.P - np.array([aq['p'][0], aq['p'][2]])
            al, sd = rel @ f, rel @ n
            crooked |= (al > 0) & (al < aq['n'] * aq['seg']) & (np.abs(sd) < 30) & (np.abs(sd) > 3) & (np.abs(p.h - aq['p'][1] - aq['deck']) < 3)
        for b_ in bridges:
            f = fwd_of(b_['yaw']); n = np.array([-f[1], f[0]]); rel = p.P - np.array([b_['p'][0], b_['p'][2]])
            al, sd = rel @ f, rel @ n
            crooked |= (al > 0) & (al < b_['len']) & (np.abs(sd) < 60) & (np.abs(sd) > b_['width'] / 2 - p.hw * 0.5) & (np.abs(p.h - b_['p'][1]) < 3)
        for kind, m in (('BURACO', hole), ('PAREDE', wall), ('TETO', ceil), ('TORTO', crooked)):
            for i0, i1 in runs(m):
                if p.S[i1] - p.S[i0] < 6:
                    continue
                problems += 1
                ii = (i0 + i1) // 2
                print(f'  ! {kind:6s} trecho {k:2d} {s_.key} «{p.name}» s={p.S[i0]:.0f}-{p.S[i1]:.0f} (u={p.u[ii]:.2f}) '
                      f'em ({p.P[ii, 0]:.0f},{p.P[ii, 1]:.0f}) estrada={p.h[ii]:.1f} chão={sup[ii]:.1f}')
print('  problemas nos caminhos:', problems)

# ------------------------------------------------------------------ saída
print('a gravar...')
os.makedirs(OUT, exist_ok=True)
zc = zstandard.ZstdCompressor(level=19, threads=-1)
# alturas em passos de 12,5 cm perto dos caminhos e 50 cm longe deles (serras): comprime muito melhor
# e o erro (máx. 6 cm nas estradas, 25 cm nas serras) não se vê
occ_q = np.zeros((NM, NM), bool)
occ_q[np.clip(np.round((pts_all[:, 1] + HALF) / MR).astype(int), 0, NM - 1), np.clip(np.round((pts_all[:, 0] + HALF) / MR).astype(int), 0, NM - 1)] = True
near_q = zoom((distance_transform_edt(~occ_q) * MR < 450.0).astype(np.float32), RES / NM, order=1) > 0.5
qstep = np.where(near_q, 1.0 / 64.0, 1.0 / 16.0).astype(np.float32)
open(os.path.join(OUT, 'height.zst'), 'wb').write(zc.compress((np.round(H / CELL / qstep) * qstep).astype(np.float16).tobytes()))
del occ_q, near_q, qstep
open(os.path.join(OUT, 'biome.zst'), 'wb').write(zc.compress(biome8.tobytes()))
open(os.path.join(OUT, 'veg.zst'), 'wb').write(zc.compress(veg_words.tobytes()))
CH = 128
nch = (RES - 1) // CH
chunks = []
for cz in range(nch):
    for cx in range(nch):
        blk = H[cz * CH:(cz + 1) * CH + 1, cx * CH:(cx + 1) * CH + 1]
        chunks.append([round(float(blk.min()), 1), round(float(blk.max()), 1)])
data = {'size': SIZE, 'res': RES, 'cell': CELL, 'ground': GROUND, 'water_y': WATER_Y, 'fall_y': FALL_Y,
        'biome_res': BRES, 'chunk_cells': CH, 'chunks': chunks, 'zones': zones,
        'start': start, 'finish': finish, 'checkpoints': checkpoints, 'sections': sections,
        'tunnels': tunnels, 'bridges': bridges, 'aqueducts': aqueducts, 'waters': waters, 'roofs': roofs,
        'props': props, 'grass': ground_cover['grass_tuft'], 'flowers': ground_cover['flowers'], 'ferns': ground_cover['fern'],
        'islands': islands, 'banners': banners, 'herds': herds, 'colossi': colossi, 'events': events, 'pads': pads,
        'veg_count': int(nveg), 'veg_types': VEG_TYPES}
json.dump(data, open(os.path.join(OUT, 'map.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
# lista curta das corridas para o menu (sem ler o map.json inteiro)
ev_menu = [{'id': 'grande', 'name': 'Grande Corrida', 'type': 'sprint', 'laps': 1,
            'length': round(sum(min(v['length'] for v in sc['variants']) for sc in data['sections']))}]
ev_menu += [{k: e[k] for k in ('id', 'name', 'type', 'laps', 'length')} for e in data['events']]
json.dump(ev_menu, open(os.path.join(OUT, 'events.json'), 'w'), ensure_ascii=False, indent=1)

# ------------------------------------------------------------------ minimapa
MM = 2048
hs = H[::3, ::3][:1024, :1024]
gy, gx = np.gradient(hs)
shade = np.clip(0.8 + (-gx * 0.55 - gy * 0.35) / 5.0, 0.45, 1.15)
bz = np.stack([np.array(Image.fromarray((biome[..., k] * 255).astype(np.uint8), 'L').resize(hs.shape[::-1], Image.BILINEAR)) for k in range(4)], -1).astype(np.float32) / 255
sand = np.array([214, 184, 140]); grassc = np.array([126, 168, 84]); jung = np.array([62, 112, 58]); red = np.array([190, 98, 64]); white = np.array([236, 232, 222])
col = np.zeros(hs.shape + (3,), np.float32); col[:] = sand
col = col * (1 - bz[..., 3:4] * (1 - bz[..., 0:1]) * 0.8) + white * bz[..., 3:4] * (1 - bz[..., 0:1]) * 0.8
col = col * (1 - bz[..., 2:3] * 0.8) + red * bz[..., 2:3] * 0.8
col = col * (1 - bz[..., 0:1] * 0.9) + grassc * bz[..., 0:1] * 0.9
col = col * (1 - bz[..., 1:2] * 0.8) + jung * bz[..., 1:2] * 0.8
col *= shade[..., None]
in_water = np.zeros(hs.shape, bool)
Xm, Zm = X[::3, ::3][:1024, :1024], Z[::3, ::3][:1024, :1024]
for wb in waters:
    cy, sy = math.cos(wb['yaw']), math.sin(wb['yaw'])
    rx = (Xm - wb['c'][0]) * cy - (Zm - wb['c'][1]) * sy
    rz = (Xm - wb['c'][0]) * sy + (Zm - wb['c'][1]) * cy
    in_water |= (np.abs(rx) < wb['sx']) & (np.abs(rz) < wb['sz']) & (hs < WATER_Y)
col = np.where(in_water[..., None], np.array([70, 140, 190]) * (0.85 + 0.15 * shade[..., None]), col)
img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).resize((MM, MM), Image.LANCZOS)
dr = ImageDraw.Draw(img)
dr.rectangle([0, 0, MM - 1, MM - 1], outline=(25, 18, 12), width=6)   # fora do mapa o minimapa fica escuro (sem riscas)
def to_px(P):
    return [((x + HALF) / SIZE * MM, (z + HALF) / SIZE * MM) for x, z in P[::8]]
LCOL = {0: (60, 230, 255), 1: (255, 255, 255), 2: (255, 160, 40), 3: (225, 240, 255)}
for lvl in (1, 3, 2, 0):
    for s in secs:
        for p in s.paths:
            if p.level != lvl:
                continue
            pts = to_px(p.P)
            if lvl == 0:
                for a_, b_ in zip(pts[::2], pts[1::2]):
                    dr.line([a_, b_], fill=LCOL[0], width=4)
            else:
                dr.line(pts, fill=(40, 25, 15), width=7)
                dr.line(pts, fill=LCOL[lvl], width=3)
for ev in ev_secs:
    for p in ev.paths:
        pts = to_px(p.P)
        dr.line(pts, fill=(40, 25, 15), width=8)
        dr.line(pts, fill=(255, 90, 200) if ev.kind == 'circuit' else (120, 255, 255), width=4)
for k, hb in enumerate(hubs):
    x, y = (hb[0] + HALF) / SIZE * MM, (hb[1] + HALF) / SIZE * MM
    c = (80, 220, 90) if k == 0 else ((230, 60, 50) if k == len(hubs) - 1 else (255, 230, 120))
    dr.ellipse([x - 7, y - 7, x + 7, y + 7], fill=c, outline=(30, 20, 10), width=2)
img.save(os.path.join(OUT, 'minimap.png'))
total = sum(s.paths[0].L for s in secs)
print(f'corrida (caminho principal): {total / 1000:.1f} km | portões: {len(checkpoints)} | túneis: {len(tunnels)} | pontes: {len(bridges)} | '
      f'água: {len(waters)} | peças: {len(props)} | cobertura: {sum(len(v) for v in ground_cover.values())} | manadas: {len(herds)} animais | '
      f'colossos: {len(colossi)} | altura min/max: {H.min():.1f}/{H.max():.1f}')
