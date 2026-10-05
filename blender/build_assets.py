"""
RACESTARS — modelagem dos objetos do mapa e do veículo no Blender (procedural).

Uso (qualquer um dos dois):
  blender -b -P blender/build_assets.py -- [--preview]      # Blender 5.0+ instalado
  python blender/build_assets.py [--preview]                # com `pip install bpy==5.0.1`

Gera:
  game/assets/models/<peça>.glb     -> importados automaticamente pelo Godot
  blender/racestars_assets.blend    -> todas as peças lado a lado, para editar no Blender
  blender/preview.png               -> render das peças (só com --preview)

Convenções:
  * 1 unidade = 1 metro. A base de cada peça fica em z=0 (chão).
  * "Para frente" do jogo é +Y no Blender (vira -Z no Godot).
  * Cada peça é UM objeto com vários materiais (cores chapadas, low-poly).
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'game', 'assets', 'models'))
BLEND = os.path.join(HERE, 'racestars_assets.blend')
PREVIEW = os.path.join(HERE, 'preview.png')
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]

# ------------------------------------------------------------------ paleta
# c = cor base (sRGB), e = cor de emissão, s = força da emissão, r = rugosidade
PAL = {
    'sand_light': {'c': '#f3dcb0'}, 'sand': {'c': '#e9bf86'}, 'sand_orange': {'c': '#e39a5e'},
    'rust': {'c': '#c9643f'}, 'rust_dark': {'c': '#94493b'},
    'cream': {'c': '#efe3c8'}, 'cream_dark': {'c': '#cdbd9d'},
    'orange_band': {'c': '#e07a45'}, 'glyph': {'c': '#7a3428'},
    'moss': {'c': '#8fbf5a'}, 'moss_dark': {'c': '#5f8f4a'}, 'grass': {'c': '#9cc463'},
    'leaf_light': {'c': '#8cc06a'}, 'leaf': {'c': '#4f8a59'}, 'leaf_dark': {'c': '#2f5a46'},
    'trunk': {'c': '#5a4038'},
    'rock_lav': {'c': '#a79cc4'}, 'rock_grey': {'c': '#8f8aa8'},
    'crystal_cyan': {'c': '#7ff6ff', 'e': '#3fe6ff', 's': 2.5, 'r': 0.25},
    'crystal_mag': {'c': '#ff8fe0', 'e': '#ff4fd0', 's': 2.5, 'r': 0.25},
    'neon_cyan': {'c': '#9ffcff', 'e': '#52f2ff', 's': 2.2, 'r': 0.3},
    'lamp': {'c': '#ffe9b8', 'e': '#ffd28a', 's': 4.0},
    'gill_glow': {'c': '#9ffcf0', 'e': '#5ff9e0', 's': 2.0},
    'spot_glow': {'c': '#e8ffb0', 'e': '#c4ff6a', 's': 2.5},
    'cap_violet': {'c': '#7a5aa8'}, 'stem': {'c': '#eadfcc'},
    'tunnel': {'c': '#2f2a4c'}, 'tunnel_floor': {'c': '#1d1a30'},
    'window': {'c': '#352c3e'},
    # veículo
    'v_white': {'c': '#f4eee2', 'r': 0.5}, 'v_red': {'c': '#e5483a', 'r': 0.5}, 'v_navy': {'c': '#272b47', 'r': 0.6},
    'v_glass': {'c': '#1d4558', 'r': 0.1}, 'v_helmet': {'c': '#ff9d2e', 'r': 0.4},
    'v_glow': {'c': '#bffbff', 'e': '#7ff6ff', 's': 2.2, 'r': 0.2},
}

def srgb(h):
    h = h.lstrip('#'); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]

_mats = {}
def M(name):
    if name in _mats: return _mats[name]
    spec = PAL[name]
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    col = srgb(spec['c'])
    bsdf.inputs['Base Color'].default_value = (*col, 1)
    bsdf.inputs['Roughness'].default_value = spec.get('r', 0.9)
    bsdf.inputs['Metallic'].default_value = 0.0
    if 'e' in spec:
        bsdf.inputs['Emission Color'].default_value = (*srgb(spec['e']), 1)
        bsdf.inputs['Emission Strength'].default_value = spec.get('s', 3.0)
    m.diffuse_color = (*col, 1)
    _mats[name] = m
    return m

# ------------------------------------------------------------------ utilidades de geometria
def T(x=0, y=0, z=0): return Matrix.Translation((x, y, z))
def S(x=1, y=1, z=1): return Matrix.Diagonal((x, y, z, 1))
def RX(d): return Matrix.Rotation(math.radians(d), 4, 'X')
def RY(d): return Matrix.Rotation(math.radians(d), 4, 'Y')
def RZ(d): return Matrix.Rotation(math.radians(d), 4, 'Z')
def lerp(a, b, t): return a + (b - a) * t
def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))); return t * t * (3 - 2 * t)
def align_z(direction):
    """Matriz de rotação que leva +Z para `direction`."""
    return Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()

COLL = None

class Mesh:
    def __init__(self, name):
        self.name = name; self.bm = bmesh.new(); self.mats = []
    def mi(self, mat):
        if mat not in self.mats: self.mats.append(mat)
        return self.mats.index(mat)
    def _faces(self, verts):
        fs = set()
        for v in verts: fs.update(v.link_faces)
        return fs
    def _tag(self, verts, mat):
        i = self.mi(mat)
        for f in self._faces(verts): f.material_index = i
        return verts
    def cone(self, mat, r1, r2, depth, mtx=Matrix(), segs=12, caps=True):
        r = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth, matrix=mtx)
        return self._tag(r['verts'], mat)
    def sphere(self, mat, r, mtx=Matrix(), u=12, v=8):
        rr = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=r, matrix=mtx)
        return self._tag(rr['verts'], mat)
    def ico(self, mat, r, mtx=Matrix(), sub=2):
        rr = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=r, matrix=mtx)
        return self._tag(rr['verts'], mat)
    def cube(self, mat, mtx=Matrix()):
        rr = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mtx)
        return self._tag(rr['verts'], mat)
    def box(self, mat, cx, cy, cz, sx, sy, sz, rot=Matrix()):
        return self.cube(mat, T(cx, cy, cz) @ rot @ S(sx, sy, sz))
    def face(self, mat, pts, want=None):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs); f.material_index = self.mi(mat); f.normal_update()
        if want is not None and f.normal.dot(Vector(want)) < 0: f.normal_flip()
        return f
    def paint(self, verts, fn):
        """Repinta as faces ligadas a `verts` com fn(face) -> nome do material (ou None)."""
        for f in self._faces(verts):
            f.normal_update(); m = fn(f)
            if m: f.material_index = self.mi(m)
    def jitter(self, verts, amp, freq, seed=0.0, radial=True, zmin=None):
        off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
        for v in verts:
            if zmin is not None and v.co.z <= zmin: continue
            n = noise.noise(v.co * freq + off)
            if radial:
                d = Vector((v.co.x, v.co.y, 0))
                if d.length > 1e-6: v.co += d.normalized() * n * amp
            else:
                v.co += Vector((noise.noise(v.co * freq + off), noise.noise(v.co * freq + off * 2), n)) * amp
    def sweep(self, mat, path, normals, w, y0, y1, caps=True):
        """Varre um retângulo ao longo de um caminho no plano XZ (y entre y0 e y1)."""
        rings = []
        for p, n in zip(path, normals):
            a = p + n * (w / 2); b = p - n * (w / 2)
            rings.append([self.bm.verts.new((a.x, y0, a.z)), self.bm.verts.new((a.x, y1, a.z)),
                          self.bm.verts.new((b.x, y1, b.z)), self.bm.verts.new((b.x, y0, b.z))])
        i = self.mi(mat)
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(4):
                f = self.bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k])); f.material_index = i
        if caps:
            for r in (rings[0], rings[-1]):
                f = self.bm.faces.new(r); f.material_index = i
        bmesh.ops.recalc_face_normals(self.bm, faces=list({f for r in rings for v in r for f in v.link_faces}))
    def done(self, smooth=False):
        bm = self.bm; bm.normal_update()
        me = bpy.data.meshes.new(self.name); bm.to_mesh(me); bm.free()
        for m in self.mats: me.materials.append(M(m))
        for p in me.polygons: p.use_smooth = smooth
        ob = bpy.data.objects.new(self.name, me); COLL.objects.link(ob)
        return ob

# ------------------------------------------------------------------ peças do mapa
BANDS = ['sand_light', 'sand', 'sand_orange', 'rust']

def strata_column(m, rnd, R, H, tiers, x0=0, y0=0, segs=8, moss_top=True, bands=BANDS, lean=0.0):
    """Coluna de arenito em camadas (estilo 'Race the Sun' + Monument Valley)."""
    z = 0.0; r = R; th = H / tiers; ox, oy = x0, y0; allv = []
    for i in range(tiers):
        sub = rnd.choice([2, 3]); r_top = r * rnd.uniform(0.8, 0.92); rot = RZ(rnd.uniform(0, 360))
        for j in range(sub):
            h = th / sub; a = lerp(r, r_top, j / sub); b = lerp(r, r_top, (j + 1) / sub)
            col = bands[(i * 2 + j + rnd.randint(0, 1)) % len(bands)]
            allv += m.cone(col, a, b, h, T(ox, oy, z + h / 2) @ rot, segs=segs, caps=(i == 0 and j == 0))
            z += h
        r_next = r_top * rnd.uniform(0.8, 0.94)
        if i < tiers - 1:  # degrau com musgo
            allv += m.cone('moss', r_top, r_next, 0.25, T(ox, oy, z + 0.12) @ rot, segs=segs, caps=False)
            z += 0.25
        r = r_next; ox += lean * th; oy += lean * th * 0.3
    if moss_top:
        allv += m.cone('moss', r * 1.04, r * 0.55, 1.0, T(ox, oy, z + 0.45), segs=segs)
        allv += m.cone('moss_dark', r * 1.06, r * 1.02, 0.45, T(ox, oy, z + 0.05), segs=segs, caps=False)
    return allv, z

def make_spire(name, seed, R, H, tiers, lean=0.0):
    rnd = random.Random(seed); m = Mesh(name)
    vs, top = strata_column(m, rnd, R, H, tiers, lean=lean)
    m.jitter([v for v in vs if v.co.z > 0.3], R * 0.12, 0.25, seed)
    return m.done()

def make_mesa(name, seed):
    rnd = random.Random(seed); m = Mesh(name)
    vs, top = strata_column(m, rnd, 20, 15, 3, segs=14)
    m.jitter([v for v in vs if v.co.z > 0.3], 2.2, 0.08, seed)
    # dois pináculos ao lado
    for (x, y, r, h) in [(18, 6, 4, 22), (-15, -9, 3, 17)]:
        v2, _ = strata_column(m, rnd, r, h, 3, x0=x, y0=y)
        m.jitter([v for v in v2 if v.co.z > 0.3], r * 0.12, 0.3, seed + 1)
    return m.done()

def make_arch(name, seed):
    """Arco natural: dá para passar por baixo (vão de 14 m x 14 m)."""
    rnd = random.Random(seed); m = Mesh(name)
    gap, leg_r, leg_h = 14.0, 3.6, 14.0
    for sx in (-1, 1):
        vs, _ = strata_column(m, rnd, leg_r, leg_h, 3, x0=sx * (gap / 2 + leg_r * 0.85), moss_top=False)
        m.jitter([v for v in vs if v.co.z > 0.3], 0.4, 0.3, seed)
    R = gap / 2 + leg_r * 0.85; path = []; norms = []
    for k in range(25):
        a = math.pi * (1 - k / 24)
        p = Vector((R * math.cos(a), 0, leg_h - 0.5 + R * 0.75 * math.sin(a)))
        n = Vector((math.cos(a) * 0.75, 0, math.sin(a))).normalized()
        path.append(p); norms.append(n)
    before = set(m.bm.verts)
    m.sweep('sand', path, norms, 4.2, -2.6, 2.6)
    new = [v for v in m.bm.verts if v not in before]
    m.paint(new, lambda f: 'moss' if f.normal.z > 0.6 else BANDS[int((f.calc_center_median().x + 30) / 4.5) % 4])
    m.jitter(new, 0.5, 0.35, seed + 2, radial=False)
    return m.done()

def make_boulder(name, seed, r):
    m = Mesh(name)
    vs = m.ico('rock_lav', r, S(1.0, 0.85, 0.62) @ T(0, 0, 0.75 * r), sub=2)
    m.jitter(vs, r * 0.18, 0.6 / r * 1.5, seed, radial=False)
    for v in vs: v.co.z = max(v.co.z, 0.0)
    m.paint(vs, lambda f: 'moss' if f.normal.z > 0.82 and f.calc_center_median().z > r * 0.6 else ('rock_grey' if f.normal.z < -0.2 else None))
    return m.done()

def make_pillar(name, seed):
    rnd = random.Random(seed); m = Mesh(name)
    m.box('cream_dark', 0, 0, 0.5, 3.2, 3.2, 1.0)
    m.cone('cream', 1.25, 1.05, 11, T(0, 0, 6.5), segs=10)
    m.cone('orange_band', 1.18, 1.16, 0.9, T(0, 0, 9.3), segs=10, caps=False)
    m.cone('crystal_cyan', 1.2, 1.2, 0.25, T(0, 0, 6.2), segs=10, caps=False)
    top = m.box('cream', 0, 0, 12.4, 3.0, 3.0, 0.9, RY(rnd.uniform(-6, 6)))
    m.box('moss', 0.3, 0.2, 12.9, 2.2, 2.0, 0.25)
    return m.done()

def make_gate(name):
    m = Mesh(name)
    for sx in (-1, 1):
        m.box('cream_dark', sx * 6.2, 0, 0.6, 3.6, 3.6, 1.2)
        m.cone('cream', 1.4, 1.25, 9.6, T(sx * 6.2, 0, 6.0), segs=10)
        m.cone('crystal_cyan', 1.36, 1.36, 0.3, T(sx * 6.2, 0, 4.0), segs=10, caps=False)
    m.box('cream', 0, 0, 11.6, 17.0, 2.8, 2.4)
    m.box('orange_band', 0, -1.45, 11.7, 16.2, 0.12, 0.9)
    for k in range(-6, 7):
        m.box('crystal_cyan', k * 1.2, -1.53, 11.7, 0.35, 0.06, 0.55, RY(45))
    m.box('moss', 0, 0, 12.9, 16.0, 2.2, 0.3)
    return m.done()

def make_crystals(name, seed, mat):
    rnd = random.Random(seed); m = Mesh(name)
    base = m.ico('rock_lav', 2.6, S(1.3, 1.1, 0.5), sub=1)
    m.jitter(base, 0.5, 0.7, seed, radial=False)
    for v in base: v.co.z = max(v.co.z, 0.0)
    for k in range(8):
        d = Vector((rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), 1.0)).normalized()
        L = rnd.uniform(3.5, 9.0) * (1.0 if k else 1.3); r = rnd.uniform(0.5, 1.1)
        p = Vector((rnd.uniform(-1.6, 1.6), rnd.uniform(-1.2, 1.2), 0.3))
        R_ = align_z(d) @ RZ(rnd.uniform(0, 60))
        m.cone(mat, r, r, L * 0.75, T(*p) @ R_ @ T(0, 0, L * 0.375), segs=6)
        m.cone(mat, r, 0.02, L * 0.25, T(*p) @ R_ @ T(0, 0, L * 0.75 + L * 0.125), segs=6)
    return m.done()

def canopy(m, cx, cy, cz, R, seed):
    vs = m.cone('leaf', R, R * 0.86, 1.0, T(cx, cy, cz) @ RZ(seed * 37), segs=10)
    m.jitter(vs, R * 0.08, 0.5, seed, radial=True)
    m.paint(vs, lambda f: 'leaf_light' if f.normal.z > 0.5 else ('leaf_dark' if f.normal.z < -0.5 else 'leaf'))

def make_acacia(name, seed, H=10.0):
    rnd = random.Random(seed); m = Mesh(name)
    t1 = rnd.uniform(-12, 12)
    m.cone('trunk', 0.55, 0.38, H * 0.45, RY(t1) @ T(0, 0, H * 0.225), segs=7)
    top1 = (RY(t1) @ Vector((0, 0, H * 0.45, 1))).to_3d()
    t2 = -t1 * 1.4
    m.cone('trunk', 0.38, 0.25, H * 0.32, T(*top1) @ RY(t2) @ T(0, 0, H * 0.16), segs=7)
    top2 = top1 + (RY(t2) @ Vector((0, 0, H * 0.32, 1))).to_3d()
    for ang in (35, -40):
        m.cone('trunk', 0.24, 0.12, H * 0.3, T(*top1) @ RX(ang * 0.4) @ RY(ang) @ T(0, 0, H * 0.15), segs=6)
    canopy(m, top2.x, top2.y, top2.z + 0.2, H * 0.42, seed)
    canopy(m, top1.x + H * 0.25, top1.y + 0.5, top1.z + H * 0.18, H * 0.3, seed + 1)
    canopy(m, top1.x - H * 0.28, top1.y - 0.4, top1.z + H * 0.12, H * 0.26, seed + 2)
    return m.done()

def make_mushroom(name, seed, H=15.0):
    rnd = random.Random(seed); m = Mesh(name)
    bend = rnd.uniform(-8, 8)
    m.cone('stem', 1.1, 0.75, H * 0.5, RY(bend) @ T(0, 0, H * 0.25), segs=10)
    p1 = (RY(bend) @ Vector((0, 0, H * 0.5, 1))).to_3d()
    m.cone('stem', 0.75, 0.6, H * 0.45, T(*p1) @ RY(-bend) @ T(0, 0, H * 0.225), segs=10)
    top = p1 + (RY(-bend) @ Vector((0, 0, H * 0.45, 1))).to_3d()
    Rc = H * 0.42
    cap = m.sphere('cap_violet', Rc, T(*top) @ S(1, 1, 0.42), u=18, v=10)
    m.paint(cap, lambda f: 'gill_glow' if f.normal.z < -0.25 else None)
    for k in range(10):
        a = rnd.uniform(0, math.tau); rr = rnd.uniform(0.25, 0.8) * Rc
        z = top.z + 0.42 * math.sqrt(max(0.0, Rc * Rc - rr * rr))
        m.ico('spot_glow', rnd.uniform(0.25, 0.5), T(top.x + rr * math.cos(a), top.y + rr * math.sin(a), z), sub=1)
    return m.done()

def make_tower(name, seed):
    rnd = random.Random(seed); m = Mesh(name)
    m.cone('cream_dark', 2.8, 2.4, 1.2, T(0, 0, 0.6), segs=12)
    R = 3.6; zc = 1.2 + R * 1.6 * 0.95
    m.sphere('cream', R, T(0, 0, zc) @ S(1, 1, 1.6), u=16, v=10)
    m.cone('orange_band', R * 0.98, R * 0.94, 0.9, T(0, 0, zc + R * 0.75), segs=16, caps=False)
    m.sphere('moss', R * 0.55, T(0, 0, zc + R * 1.52) @ S(1, 1, 0.45), u=12, v=6)
    for k in range(rnd.randint(3, 5)):
        a = rnd.uniform(-160, -20); el = rnd.uniform(-0.3, 0.5)
        d = Vector((math.cos(math.radians(a)) * math.cos(el), math.sin(math.radians(a)) * math.cos(el), math.sin(el) * 1.6))
        n = Vector((d.x, d.y, d.z / 1.6)).normalized()
        p = Vector((0, 0, zc)) + Vector((d.x * R, d.y * R, d.z * R)) * 0.99
        m.cone('orange_band', 0.62, 0.62, 0.2, T(*p) @ align_z(n), segs=10)
        m.cone('window', 0.45, 0.45, 0.24, T(*(p + n * 0.03)) @ align_z(n), segs=10)
    return m.done()

def make_float_island(name, seed, R=26.0):
    rnd = random.Random(seed); m = Mesh(name)
    top = m.cone('grass', R, R * 0.97, 2.5, T(0, 0, -1.25), segs=16)
    m.jitter(top, R * 0.06, 0.12, seed)
    m.paint(top, lambda f: 'grass' if f.normal.z > 0.5 else 'moss_dark')
    z = -2.5; r = R * 0.97
    for i in range(5):
        h = R * 0.32; r2 = r * (0.72 if i < 4 else 0.0)
        vs = m.cone(BANDS[(i + 1) % 4], r, max(r2, 0.2), h, T(0, 0, z - h / 2) @ RZ(rnd.uniform(0, 90)), segs=12, caps=False)
        m.jitter(vs, R * 0.07, 0.15, seed + i, radial=True)
        z -= h; r = r2
    for k in range(5):
        a = rnd.uniform(0, math.tau); rr = rnd.uniform(0, R * 0.6); h = rnd.uniform(5, 9)
        x, y = rr * math.cos(a), rr * math.sin(a)
        m.cone('trunk', 0.35, 0.22, h * 0.6, T(x, y, h * 0.3), segs=6)
        canopy(m, x, y, h * 0.65, h * 0.38, seed + k)
    return m.done()

def make_grass(name, seed):
    rnd = random.Random(seed); m = Mesh(name)
    for k in range(7):
        a = rnd.uniform(0, math.tau); h = rnd.uniform(0.35, 0.8); w = 0.07
        x, y = rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25)
        lx, ly = math.cos(a) * w, math.sin(a) * w; tx, ty = rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15)
        m.face(rnd.choice(['grass', 'moss', 'leaf_light']), [(x - lx, y - ly, 0), (x + lx, y + ly, 0), (x + tx, y + ty, h)])
    return m.done()

def make_pebbles(name, seed):
    rnd = random.Random(seed); m = Mesh(name)
    for k in range(4):
        r = rnd.uniform(0.15, 0.4)
        vs = m.ico(rnd.choice(['rock_lav', 'cream_dark', 'sand']), r, T(rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8), r * 0.3) @ S(1, 0.8, 0.5), sub=1)
    return m.done()

# ------------------------------------------------------------------ cordilheira com túnel
RIDGE_W, RIDGE_L = 60.0, 180.0      # largura (repete sem emenda no eixo X) e comprimento do túnel
TUN_HW, TUN_WALL, TUN_ARCH = 7.0, 7.0, 4.0   # meia-largura, altura da parede, altura do arco

def ridge_H(x, y):
    p = 2 * math.pi * x / RIDGE_W
    h = 30 + 5 * math.sin(p + 0.7) + 3.5 * math.sin(2 * p + y * 0.035 + 1.1) + 2.5 * math.cos(3 * p - y * 0.02) + 5 * math.sin(y * 0.022 + 0.4)
    h += 8 * max(0.0, math.sin(p + y * 0.012 + 2.0)) ** 3
    return h

def arch_top(x):
    return TUN_WALL + TUN_ARCH * math.sqrt(max(0.0, 1 - (x / TUN_HW) ** 2))

def cliff_band(x, z):
    zb = z + 0.9 * math.sin(2 * math.pi * x / RIDGE_W * 2)
    seq = [(4, 'rust'), (8, 'sand_orange'), (13, 'sand'), (17, 'sand_light'), (22, 'sand_orange'), (27, 'rust'), (99, 'sand')]
    for lim, name in seq:
        if zb < lim: return name

def make_ridge(name):
    m = Mesh(name)
    W, L = RIDGE_W, RIDGE_L
    left = [-W / 2 + i * 1.5 for i in range(16)] + [-TUN_HW]
    inner = [-TUN_HW + i * 0.7 for i in range(21)]
    right = [TUN_HW] + [TUN_HW + 0.5 + i * 1.5 for i in range(16)]
    right[-1] = W / 2
    xs_all = sorted(set([round(x, 4) for x in left + inner + right]))
    ys = [i * 4.0 for i in range(int(L / 4) + 1)]
    # topo da montanha (grade de alturas)
    grid = [[m.bm.verts.new((x, y, ridge_H(x, y))) for x in xs_all] for y in ys]
    for j in range(len(ys) - 1):
        for i in range(len(xs_all) - 1):
            f = m.bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])); f.normal_update()
            if f.normal.z < 0: f.normal_flip()
            f.material_index = m.mi('grass' if f.normal.z > 0.82 else 'sand')
    # paredões da frente (y=0) e de trás (y=L) com a boca do túnel
    ts = [0, 0.1, 0.22, 0.36, 0.5, 0.64, 0.78, 0.9, 1.0]
    def bulge(x, z, H):
        k = smoothstep(9.5, 13.0, abs(x)) * (1 - (z / H) ** 3)
        return 1.8 * (0.5 + 0.5 * math.sin(2 * math.pi * x / W * 4 + z * 0.35)) * k
    for yface, sgn in ((0.0, -1), (L, 1)):
        for group, zb in ((left, lambda x: 0.0), (inner, arch_top), (right, lambda x: 0.0)):
            for a, b in zip(group, group[1:]):
                Ha, Hb = ridge_H(a, yface), ridge_H(b, yface)
                for t0, t1 in zip(ts, ts[1:]):
                    za0, za1 = lerp(zb(a), Ha, t0), lerp(zb(a), Ha, t1)
                    zb0, zb1 = lerp(zb(b), Hb, t0), lerp(zb(b), Hb, t1)
                    pts = [(a, yface + sgn * bulge(a, za0, Ha), za0), (b, yface + sgn * bulge(b, zb0, Hb), zb0),
                           (b, yface + sgn * bulge(b, zb1, Hb), zb1), (a, yface + sgn * bulge(a, za1, Ha), za1)]
                    cz = (za0 + za1 + zb0 + zb1) / 4
                    m.face(cliff_band((a + b) / 2, cz), pts, want=(0, sgn, 0))
    # interior do túnel: paredes + arco (normais para dentro)
    sec = [(-TUN_HW, 0.0), (-TUN_HW, TUN_WALL)] + [(x, arch_top(x)) for x in inner[1:-1]] + [(TUN_HW, TUN_WALL), (TUN_HW, 0.0)]
    ty = [i * 6.0 for i in range(int(L / 6) + 1)]
    for y0, y1 in zip(ty, ty[1:]):
        for (xa, za), (xb, zb_) in zip(sec, sec[1:]):
            cx, cz = (xa + xb) / 2, (za + zb_) / 2
            m.face('tunnel', [(xa, y0, za), (xb, y0, zb_), (xb, y1, zb_), (xa, y1, za)], want=(-cx, 0, 3.0 - cz))
    m.face('tunnel_floor', [(-TUN_HW, 0, 0.12), (TUN_HW, 0, 0.12), (TUN_HW, L, 0.12), (-TUN_HW, L, 0.12)], want=(0, 0, 1))
    # luzes: faixas neon nas paredes, luminárias no teto, tracejado no chão
    for sx in (-1, 1):
        m.box('neon_cyan', sx * (TUN_HW - 0.06), L / 2, 2.4, 0.1, L - 2, 0.1)
    for y in range(6, int(L), 12):
        m.box('lamp', 0, y, TUN_WALL + TUN_ARCH - 0.2, 2.6, 0.7, 0.25)
    for y in range(3, int(L), 6):
        m.box('neon_cyan', 0, y, 0.15, 0.3, 2.2, 0.05)
    # moldura da boca (frente e trás) + farol em losango acima
    for yface, sgn in ((0.0, -1), (L, 1)):
        path, norms = [], []
        off = 0.75
        path.append(Vector((-TUN_HW - off, 0, 0))); norms.append(Vector((1, 0, 0)))
        path.append(Vector((-TUN_HW - off, 0, TUN_WALL))); norms.append(Vector((1, 0, 0)))
        for k in range(1, 20):
            a = math.pi * (1 - k / 20)
            path.append(Vector(((TUN_HW + off) * math.cos(a), 0, TUN_WALL + (TUN_ARCH + off) * math.sin(a))))
            norms.append(Vector((math.cos(a) / (TUN_HW + off), 0, math.sin(a) / (TUN_ARCH + off))).normalized())
        path.append(Vector((TUN_HW + off, 0, TUN_WALL))); norms.append(Vector((1, 0, 0)))
        path.append(Vector((TUN_HW + off, 0, 0))); norms.append(Vector((1, 0, 0)))
        y0, y1 = (yface - 1.4, yface + 0.4) if sgn < 0 else (yface - 0.4, yface + 1.4)
        m.sweep('cream', path, norms, 1.5, y0, y1)
        inner_path = [p - n * 0.9 for p, n in zip(path, norms)]
        yy = y0 - 0.02 if sgn < 0 else y1 + 0.02
        m.sweep('neon_cyan', inner_path, norms, 0.28, yy, yy + (0.25 if sgn < 0 else -0.25))
        m.cube('neon_cyan', T(0, yface + sgn * 1.0, TUN_WALL + TUN_ARCH + 3.2) @ RY(45) @ S(1.6, 0.3, 1.6))
    return m.done()

# ------------------------------------------------------------------ veículo
def make_faisca(name):
    """Corredor terrestre 'Faísca': cabine central + 2 turbinas laterais. Frente = +Y."""
    m = Mesh(name)
    zc = 0.85
    m.cone('v_white', 0.78, 0.3, 4.0, T(0, 0.1, zc) @ RX(-90) @ S(1, 0.78, 1), segs=14)
    m.cone('v_white', 0.3, 0.04, 0.9, T(0, 2.55, zc) @ RX(-90) @ S(1, 0.78, 1), segs=14)
    m.box('v_red', 0, 0.2, zc + 0.6, 0.28, 3.4, 0.08)
    m.cone('v_navy', 0.62, 0.62, 0.2, T(0, -1.92, zc) @ RX(-90) @ S(1, 0.78, 1), segs=14)
    m.cone('v_glow', 0.3, 0.3, 0.05, T(0, -2.03, zc) @ RX(-90), segs=12)
    m.sphere('v_glass', 0.56, T(0, 0.55, zc + 0.42) @ S(0.85, 1.5, 0.7), u=14, v=8)
    m.sphere('v_helmet', 0.3, T(0, 0.2, zc + 0.62), u=12, v=8)
    for sx in (-1, 1):
        x = sx * 1.5
        m.cone('v_white', 0.56, 0.56, 3.2, T(x, 0, zc) @ RX(-90), segs=14)
        m.cone('v_white', 0.56, 0.18, 0.9, T(x, 2.05, zc) @ RX(-90), segs=14)
        m.cone('v_red', 0.575, 0.575, 0.45, T(x, 0.7, zc) @ RX(-90), segs=14, caps=False)
        m.cone('v_navy', 0.6, 0.6, 0.25, T(x, -1.65, zc) @ RX(-90), segs=14)
        m.cone('v_navy', 0.42, 0.42, 0.06, T(x, -1.79, zc) @ RX(-90), segs=14)
        m.cone('v_glow', 0.34, 0.34, 0.06, T(x, -1.84, zc) @ RX(-90), segs=14)
        m.box('v_navy', sx * 0.95, -0.35, zc, 1.0, 0.7, 0.22)
        # aleta varrida para trás
        rf, rb = Vector((x + sx * 0.1, 0.3, zc + 0.45)), Vector((x + sx * 0.1, -1.3, zc + 0.45))
        tb, tf = Vector((x + sx * 0.85, -1.85, zc + 1.45)), Vector((x + sx * 0.8, -1.05, zc + 1.42))
        nrm = (rb - rf).cross(tf - rf).normalized() * 0.06
        quad = [rf, rb, tb, tf]
        top = [m.bm.verts.new(p + nrm) for p in quad]; bot = [m.bm.verts.new(p - nrm) for p in quad]
        fs = [m.bm.faces.new(top), m.bm.faces.new(list(reversed(bot)))]
        for k in range(4): fs.append(m.bm.faces.new((top[k], bot[k], bot[(k + 1) % 4], top[(k + 1) % 4])))
        for f in fs: f.material_index = m.mi('v_red')
        m.box('v_white', x + sx * 0.82, -1.5, zc + 1.44, 0.12, 0.7, 0.08)
    return m.done()

# ------------------------------------------------------------------ montagem
def build_all():
    global COLL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    COLL = bpy.data.collections.new('RACESTARS'); bpy.context.scene.collection.children.link(COLL)
    B = []
    B.append(make_faisca('faisca'))
    B.append(make_spire('rock_spire_a', 11, 6.0, 30.0, 4))
    B.append(make_spire('rock_spire_b', 23, 4.5, 22.0, 3, lean=0.04))
    B.append(make_spire('rock_spire_c', 37, 7.5, 40.0, 5, lean=-0.02))
    B.append(make_mesa('mesa', 5))
    B.append(make_arch('arch', 9))
    B.append(make_boulder('boulder_a', 3, 3.2))
    B.append(make_boulder('boulder_b', 8, 4.5))
    B.append(make_pillar('pillar', 4))
    B.append(make_gate('gate'))
    B.append(make_crystals('crystals_cyan', 12, 'crystal_cyan'))
    B.append(make_crystals('crystals_mag', 19, 'crystal_mag'))
    B.append(make_acacia('tree_acacia', 7))
    B.append(make_acacia('tree_acacia_b', 31, 8.0))
    B.append(make_mushroom('tree_mushroom', 2))
    B.append(make_tower('tower_pod', 6))
    B.append(make_float_island('float_island', 15))
    B.append(make_grass('grass_tuft', 1))
    B.append(make_pebbles('pebbles', 2))
    B.append(make_ridge('ridge_tunnel'))
    return B

def export(objs):
    os.makedirs(OUT, exist_ok=True)
    for ob in objs:
        for o in bpy.context.scene.objects: o.select_set(False)
        ob.select_set(True); bpy.context.view_layer.objects.active = ob
        path = os.path.join(OUT, ob.name + '.glb')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
        print('exportado', os.path.relpath(path, os.path.join(HERE, '..')), len(ob.data.polygons), 'faces')

def layout(objs):
    """Arruma as peças em duas fileiras no .blend (grandes atrás, pequenas na frente)."""
    big = ['ridge_tunnel', 'mesa', 'arch', 'rock_spire_c', 'rock_spire_a', 'rock_spire_b', 'float_island']
    def width(ob): return max(v.co.x for v in ob.data.vertices) - min(v.co.x for v in ob.data.vertices)
    rows = {0: [o for o in objs if o.name not in big], 1: [o for o in objs if o.name in big]}
    for row, items in rows.items():
        x = 0.0; y = 0.0 if row == 0 else 70.0
        for ob in items:
            w = width(ob); x += w / 2 + (3 if row == 0 else 8)
            ob.location = (x, y, 45 if ob.name == 'float_island' else 0); x += w / 2
        dx = -x / 2
        for ob in items: ob.location.x += dx

def preview():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 24; sc.cycles.device = 'CPU'
    try: sc.cycles.use_denoising = True
    except Exception: pass
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    w = bpy.data.worlds.new('ceu'); sc.world = w
    w.use_nodes = True if w.node_tree is None else True
    bg = w.node_tree.nodes.get('Background'); bg.inputs[0].default_value = (*srgb('#bfe2f2'), 1); bg.inputs[1].default_value = 0.9
    sun = bpy.data.lights.new('sol', 'SUN'); sun.energy = 3.5; sun.color = srgb('#fff1d8')
    so = bpy.data.objects.new('sol', sun); so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35)); COLL.objects.link(so)
    gm = bpy.data.meshes.new('chao'); bmc = bmesh.new(); bmesh.ops.create_grid(bmc, x_segments=1, y_segments=1, size=400); bmc.to_mesh(gm); bmc.free()
    gm.materials.append(M('sand_light')); g = bpy.data.objects.new('chao', gm); COLL.objects.link(g)
    cam = bpy.data.cameras.new('cam'); cam.lens = 24; co = bpy.data.objects.new('cam', cam); COLL.objects.link(co)
    co.location = (0, -125, 62); co.rotation_euler = (math.radians(64), 0, 0)
    sc.camera = co; sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    for ob in (so, g, co): bpy.data.objects.remove(ob)

if __name__ == '__main__':
    objs = build_all()
    export(objs)
    layout(objs)
    if '--preview' in ARGS: preview()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
    print('salvo', BLEND)
