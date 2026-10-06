"""
RACESTARS — gera o MAPA da corrida (deserto de 4 x 4 km, de A até B).

Uso:  python tools/make_map.py        (precisa de numpy, scipy e pillow)

Gera em game/assets/map/:
  height.bin    alturas (float32, 1025 x 1025, 4 m por amostra; linha = z, coluna = x)
  map.json      percurso, portões (checkpoints), largada/meta, peças, gruta e teto do desfiladeiro
  minimap.png   mapa visto de cima (para o minimapa do jogo)

Coordenadas do Godot: X para a direita, Z para "trás" (a corrida vai de z=+1850 até z=-1750).
O percurso passa por: deserto aberto -> volta em torno de uma mesa (atalho por uma GRUTA
que atravessa a mesa) -> DESFILADEIRO -> campo de ARCOS de pedra -> ABISMO para saltar
(ou contornar) -> DUNAS com saltos -> desfiladeiro estreito com TETO (caverna) -> META.
"""
import json, math, os
import numpy as np
from scipy.spatial import cKDTree
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'game', 'assets', 'map'))
SIZE, RES = 4096.0, 1025
CELL = SIZE / (RES - 1)
HALF = SIZE / 2
rng = np.random.default_rng(42)

# ------------------------------------------------------------------ ruído
_perm = rng.permutation(512)
def _vnoise(x, z):
    xi = np.floor(x).astype(np.int64); zi = np.floor(z).astype(np.int64)
    fx = x - xi; fz = z - zi
    u = fx * fx * (3 - 2 * fx); v = fz * fz * (3 - 2 * fz)
    def h(a, b):
        return (_perm[(_perm[a & 511] + b) & 511] / 511.0)
    return (h(xi, zi) * (1 - u) + h(xi + 1, zi) * u) * (1 - v) + (h(xi, zi + 1) * (1 - u) + h(xi + 1, zi + 1) * u) * v

def fbm(x, z, oct=5):
    s = np.zeros_like(x); a = 0.5; f = 1.0; n = 0.0
    for i in range(oct):
        s += a * _vnoise(x * f + i * 17.3, z * f - i * 9.1); n += a; a *= 0.5; f *= 2.03
    return s / n

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

# ------------------------------------------------------------------ percurso
CTRL = [(-1500, 1850), (-1500, 1450), (-1350, 1200), (-1000, 1150), (-700, 1150),
        (-500, 850), (-300, 700), (-100, 850), (100, 1150), (500, 1180), (900, 1100),
        (1250, 900), (1500, 600), (1450, 250), (1550, -50), (1300, -250),
        (900, -250), (400, -100), (-100, -200), (-600, -350), (-1100, -450), (-1350, -650),
        (-1350, -950), (-1150, -1200), (-800, -1300), (-400, -1450),
        (0, -1500), (300, -1350), (600, -1450), (900, -1650), (1300, -1750)]
# tipo de trecho por ponto de controle: 0 aberto, 1 desfiladeiro, 2 desfiladeiro estreito
KIND = [0] * 11 + [1] * 5 + [0] * 10 + [2] * 3 + [0] * 2
CAVE_A, CAVE_B = 4, 8           # a gruta liga o ponto 4 ao 8 (atalho pela mesa)
CHASM_CTRL = 22                 # abismo perto do ponto 21-22
ROOF_CTRL = 27                  # teto de pedra (caverna) no desfiladeiro estreito

def catmull(points, step=2.0):
    P = np.array(points, dtype=float)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out, owner = [], []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        seg = np.linalg.norm(p2 - p1); n = max(2, int(seg / step))
        for k in range(n):
            t = k / n; t2 = t * t; t3 = t2 * t
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append(q); owner.append(i - 1 + t)
    out.append(P[-2]); owner.append(len(points) - 1)
    return np.array(out), np.array(owner)

route, owner = catmull(CTRL)
seg = np.linalg.norm(np.diff(route, axis=0), axis=1)
S = np.concatenate([[0], np.cumsum(seg)])
L = S[-1]
tang = np.gradient(route, axis=0); tang /= np.linalg.norm(tang, axis=1, keepdims=True)
print(f'percurso: {L:.0f} m, {len(route)} amostras')

def ctrl_s(i):
    return S[np.argmin(np.abs(owner - i))]

# fator de desfiladeiro (0..1) e meia-largura da pista ao longo do percurso
kind_at = np.array([KIND[min(int(round(o)), len(KIND) - 1)] for o in owner])
canyon = np.convolve((kind_at > 0).astype(float), np.ones(61) / 61, mode='same')
slot = np.convolve((kind_at == 2).astype(float), np.ones(61) / 61, mode='same')
halfw = 30 - 14 * slot

# perfil de altura do percurso
s_ch = ctrl_s(CHASM_CTRL) - 120
route_h = 4 + 3 * np.sin(S / 700.0) - 2 * canyon
ramp = smooth(s_ch - 90, s_ch - 14, S) * (1 - smooth(s_ch - 14, s_ch - 6, S))
route_h += 9 * ramp
dunes_on = smooth(ctrl_s(23) - 50, ctrl_s(23) + 50, S) * (1 - smooth(ctrl_s(25) - 50, ctrl_s(25) + 50, S))
route_h += dunes_on * 5 * np.maximum(0, np.sin((S - ctrl_s(23)) / 55.0 * math.pi)) ** 2

# ------------------------------------------------------------------ terreno
xs = np.linspace(-HALF, HALF, RES)
X, Z = np.meshgrid(xs, xs)               # linhas = z, colunas = x
tree = cKDTree(route)
D, I = tree.query(np.stack([X.ravel(), Z.ravel()], axis=1), workers=-1)
D = D.reshape(X.shape); I = I.reshape(X.shape)
rh = route_h[I]; cf = canyon[I]; hw = halfw[I]

dunes = 6 * fbm(X / 260, Z / 260) + 2.2 * (np.sin((X * 0.6 + Z * 0.8) / 34 + fbm(X / 90, Z / 90) * 7) * 0.5 + 0.5)
M = fbm(X / 650 + 3.7, Z / 650 - 1.3)
mesas = 42 * smooth(0.6, 0.63, M) + 22 * smooth(0.68, 0.705, M)
mesas *= smooth(130, 280, D)
open_h = dunes + mesas
plateau = 64 + 9 * fbm(X / 180, Z / 180) + 6 * smooth(0.55, 0.6, fbm(X / 300 + 9, Z / 300))
wall_w = 12 + 4 * (1 - slot[I])
h_canyon = rh + (plateau - rh) * smooth(hw, hw + wall_w, D)
h_canyon = h_canyon + (open_h - h_canyon) * smooth(360, 520, D)
h_open = rh + (open_h - rh) * smooth(hw, hw + 90, D)
H = h_open + (h_canyon - h_open) * cf

# atalho pela GRUTA: a estrada contorna uma mesa; a gruta atravessa-a em linha reta.
# A peça do Blender (túnel com teto) fica no meio; o resto da mesa é feito aqui no terreno.
A = np.array(CTRL[CAVE_A], float); B = np.array(CTRL[CAVE_B], float)
ab = B - A; chord = float(np.linalg.norm(ab)); u_ab = ab / chord; n_ab = np.array([-u_ab[1], u_ab[0]])
CAVE_T0, CAVE_T1, CAVE_W = 120.0, chord - 120.0, 140.0   # onde começa/acaba a peça e a largura dela
ta = (X - A[0]) * u_ab[0] + (Z - A[1]) * u_ab[1]           # metros ao longo da corda
na = (X - A[0]) * n_ab[0] + (Z - A[1]) * n_ab[1]           # metros para o lado (+ = lado sem estrada)
ha = route_h[np.argmin(np.abs(owner - CAVE_A))]; hb = route_h[np.argmin(np.abs(owner - CAVE_B))]
mesa_top = (ha + hb) / 2 + 53 + 3 * fbm(X / 60, Z / 60)
# dentro da volta da estrada (polígono: estrada de 4 a 8 + corda) ou até 200 m do outro lado
from PIL import ImageDraw
loop = route[(owner >= CAVE_A) & (owner <= CAVE_B)]
poly = Image.new('L', (RES, RES), 0)
ImageDraw.Draw(poly).polygon([((x + HALF) / CELL, (z + HALF) / CELL) for x, z in loop], fill=255)
inside_loop = np.asarray(poly, dtype=np.float32) / 255.0
north = smooth(-8, 4, na) * (1 - smooth(200, 214, na + 6 * fbm(X / 40, Z / 40)))
in_mesa = smooth(CAVE_T0 + 2, CAVE_T0 + 12, ta) * (1 - smooth(CAVE_T1 - 12, CAVE_T1 - 2, ta))
in_mesa *= np.maximum(north, inside_loop)
in_mesa *= smooth(hw + 34, hw + 50, D + 8 * fbm(X / 40 + 3, Z / 40))         # sem invadir a estrada
H = np.maximum(H, H + (mesa_top - H) * in_mesa)
# chão plano no corredor da gruta
t = np.clip(ta / chord, 0, 1)
dch = np.hypot(X - (A[0] + t * ab[0]), Z - (A[1] + t * ab[1]))
chord_h = ha + (hb - ha) * t
H = H + (chord_h - H) * (1 - smooth(16, 60 - 36 * in_mesa, dch))

# abismo: vala funda atravessando a pista (dá para saltar ou contornar)
ich = np.argmin(np.abs(S - s_ch)); c0 = route[ich]; tn = tang[ich]; nrm = np.array([-tn[1], tn[0]])
along = (X - c0[0]) * nrm[0] + (Z - c0[1]) * nrm[1]
across = (X - c0[0]) * tn[0] + (Z - c0[1]) * tn[1]
trench = (1 - smooth(14, 20, np.abs(across))) * (1 - smooth(360, 400, np.abs(along)))
H = H + (-45 - H) * trench

# bordas do mapa: montanhas altas
edge = np.maximum(np.abs(X), np.abs(Z))
H = H + (150 + 20 * fbm(X / 120, Z / 120) - H) * smooth(1930, 2040, edge)
H = H.astype(np.float32)

def height_at(x, z):
    fx = (x + HALF) / CELL; fz = (z + HALF) / CELL
    i, j = int(np.clip(np.floor(fx), 0, RES - 2)), int(np.clip(np.floor(fz), 0, RES - 2))
    u, v = fx - i, fz - j
    return float(H[j, i] * (1 - u) * (1 - v) + H[j, i + 1] * u * (1 - v) + H[j + 1, i] * (1 - u) * v + H[j + 1, i + 1] * u * v)

# ------------------------------------------------------------------ portões (checkpoints)
skip = [(ctrl_s(CAVE_A) - 40, ctrl_s(CAVE_B) + 40), (s_ch - 420, s_ch + 420)]
cps = []
s = 450.0
while s < L - 250:
    if any(a <= s <= b for a, b in skip):
        s += 40; continue
    i = int(np.argmin(np.abs(S - s)))
    w = 2 * halfw[i] + (90 if canyon[i] < 0.5 else 24)
    cps.append({'p': [float(route[i, 0]), float(route_h[i]), float(route[i, 1])], 'dir': [float(tang[i, 0]), float(tang[i, 1])], 'w': float(w), 's': float(s)})
    s += 620
fin_i = len(route) - 1
finish = {'p': [float(route[fin_i, 0]), float(route_h[fin_i]), float(route[fin_i, 1])], 'dir': [float(tang[fin_i, 0]), float(tang[fin_i, 1])], 'w': 90.0}
start = {'p': [float(route[0, 0]), float(route_h[0]), float(route[0, 1])], 'dir': [float(tang[0, 0]), float(tang[0, 1])]}

# ------------------------------------------------------------------ peças (rochas, arcos, formações)
props = []
def yaw_of(dx, dz):  # yaw do Godot para que o "para frente" (-Z) aponte em (dx, dz)
    return float(math.atan2(-dx, -dz))
def add(name, x, z, yaw, sc, sink=1.0):
    props.append([name, float(x), float(height_at(x, z) - sink), float(z), float(yaw), float(sc)])

# arcos sobre a pista (atravessa-se por baixo)
for frac, name, sc in [(0.07, 'arch_giant', 1.0), (0.37, 'arch_giant', 1.15), (0.41, 'arch_twin', 1.3), (0.45, 'arch_giant', 1.0),
                       (0.49, 'rock_ring', 1.6), (0.53, 'arch_giant', 1.2), (0.7, 'arch_giant', 1.1), (0.95, 'arch_giant', 1.25)]:
    i = int(np.argmin(np.abs(S - frac * L)))
    if any(a <= S[i] <= b for a, b in skip) or canyon[i] > 0.3:
        continue
    add(name, route[i, 0], route[i, 1], yaw_of(tang[i, 0], tang[i, 1]), sc, 0.5)
# campo de arcos e formações pelo deserto aberto
kinds = [('rock_spire_a', 3), ('rock_spire_b', 3), ('rock_spire_c', 2), ('boulder_a', 3), ('boulder_b', 2),
         ('arch', 2), ('arch_giant', 1.2), ('arch_twin', 1), ('rock_ring', 1), ('rock_fin', 1.6), ('butte', 0.6), ('mesa', 0.6)]
names = [k for k, _ in kinds]; w = np.array([v for _, v in kinds]); w /= w.sum()
radius = {'rock_spire_a': 7, 'rock_spire_b': 6, 'rock_spire_c': 9, 'boulder_a': 4, 'boulder_b': 6, 'arch': 16, 'arch_giant': 44,
          'arch_twin': 30, 'rock_ring': 20, 'rock_fin': 18, 'butte': 70, 'mesa': 30}
placed = [(p[1], p[3], radius[p[0]] * p[5]) for p in props]
tries = 0
while len(props) < 520 and tries < 20000:
    tries += 1
    x, z = rng.uniform(-1880, 1880, 2)
    d, i = tree.query([x, z])
    if canyon[i] > 0.4 and d < 500:
        continue
    name = rng.choice(names, p=w)
    sc = float(rng.uniform(0.8, 1.35))
    r = radius[name] * sc
    near_road = d < halfw[i] + r + 6
    if near_road and not (name.startswith('rock_spire') or name.startswith('boulder')):
        continue
    if d < halfw[i] - 4:                      # rochas soltas podem ficar na beira da pista
        continue
    if dch[int((z + HALF) / CELL), int((x + HALF) / CELL)] < 260 or abs(across[int((z + HALF) / CELL), int((x + HALF) / CELL)]) < 40 and abs(along[int((z + HALF) / CELL), int((x + HALF) / CELL)]) < 420:
        continue
    if any((x - px) ** 2 + (z - pz) ** 2 < (r + pr + 10) ** 2 for px, pz, pr in placed):
        continue
    yaw = float(rng.uniform(-math.pi, math.pi))
    if name in ('arch', 'arch_giant', 'arch_twin', 'rock_ring') and d < 300:
        yaw = yaw_of(tang[i, 0], tang[i, 1]) + float(rng.uniform(-0.4, 0.4))
    add(name, x, z, yaw, sc, 1.5 if name in ('butte', 'mesa') else 0.8)
    placed.append((x, z, r))
# pedras no chão do desfiladeiro (perto das paredes)
for k in range(80):
    i = int(rng.integers(0, len(route)))
    if canyon[i] < 0.8:
        continue
    side = rng.choice([-1, 1]); off = halfw[i] - rng.uniform(1, 6)
    x = route[i, 0] - tang[i, 1] * off * side; z = route[i, 1] + tang[i, 0] * off * side
    add(str(rng.choice(['boulder_a', 'boulder_b'])), x, z, float(rng.uniform(-3, 3)), float(rng.uniform(0.5, 0.9)), 0.6)

# gruta (mesa com túnel) e teto de pedra no desfiladeiro estreito
mid = A + u_ab * (CAVE_T0 + CAVE_T1) / 2
cave = {'p': [float(mid[0]), float((ha + hb) / 2), float(mid[1])], 'yaw': yaw_of(u_ab[0], u_ab[1]),
        'len': float(CAVE_T1 - CAVE_T0), 'w': CAVE_W}
ir = int(np.argmin(np.abs(owner - ROOF_CTRL)))
roof = {'p': [float(route[ir, 0]), float(route_h[ir]), float(route[ir, 1])], 'yaw': yaw_of(tang[ir, 0], tang[ir, 1])}

os.makedirs(OUT, exist_ok=True)
H.tofile(os.path.join(OUT, 'height.bin'))
step = 4
data = {'size': SIZE, 'res': RES, 'cell': CELL, 'length': float(L), 'fall_y': -25.0,
        'route': [[round(float(route[i, 0]), 1), round(float(route_h[i]), 2), round(float(route[i, 1]), 1)] for i in range(0, len(route), step)],
        'checkpoints': cps, 'start': start, 'finish': finish, 'props': props, 'cave': cave, 'roof': roof}
json.dump(data, open(os.path.join(OUT, 'map.json'), 'w'))

# ------------------------------------------------------------------ minimapa (relevo sombreado + rota)
small = H[::2, ::2]
gy, gx = np.gradient(small)
shade = np.clip(0.75 + (gx * -0.7 + gy * -0.7) * 0.08, 0.35, 1.15)
base = np.where(small[..., None] > 40, np.array([196, 150, 106]), np.array([226, 196, 150]))
base = np.where(small[..., None] < -10, np.array([90, 60, 50]), base)
img = np.clip(base * shade[..., None], 0, 255).astype(np.uint8)
im = Image.fromarray(img).resize((512, 512), Image.BILINEAR)
from PIL import ImageDraw
dr = ImageDraw.Draw(im)
to_px = lambda x, z: ((x + HALF) / SIZE * 512, (z + HALF) / SIZE * 512)
dr.line([to_px(x, z) for x, z in route[::10]], fill=(255, 255, 255), width=4)
for c in cps:
    px, py = to_px(c['p'][0], c['p'][2]); dr.ellipse([px - 5, py - 5, px + 5, py + 5], fill=(80, 230, 255))
px, py = to_px(*start['p'][::2]); dr.ellipse([px - 8, py - 8, px + 8, py + 8], fill=(80, 255, 120))
px, py = to_px(*finish['p'][::2]); dr.rectangle([px - 8, py - 8, px + 8, py + 8], fill=(255, 80, 80))
im.save(os.path.join(OUT, 'minimap.png'))
print(f'portões: {len(cps)}  peças: {len(props)}  altura min/max: {H.min():.1f}/{H.max():.1f}')
