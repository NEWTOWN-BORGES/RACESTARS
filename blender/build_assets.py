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
    'base': {'c': '#ffffff'},
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
    # veículo 'Vespa' (dois motores puxando a cabine)
    'p_orange': {'c': '#d9692e', 'r': 0.55}, 'p_rust': {'c': '#8e3b22', 'r': 0.8}, 'p_metal': {'c': '#8d9096', 'r': 0.45},
    'p_dark': {'c': '#26262c', 'r': 0.6}, 'p_cream': {'c': '#e8dcc6', 'r': 0.6},
    'p_beam': {'c': '#ffb0f0', 'e': '#ff4fd8', 's': 5.0, 'r': 0.3}, 'p_fire': {'c': '#ffd8a0', 'e': '#ffa040', 's': 5.0, 'r': 0.3},
    'rock': {'c': '#c99a68'}, 'rock_dark': {'c': '#8a5a3c'},
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
    if name == 'base':  # cor vem dos vértices (atributo 'Col')
        attr = nt.nodes.new('ShaderNodeVertexColor'); attr.layer_name = 'Col'
        nt.links.new(attr.outputs['Color'], bsdf.inputs['Base Color'])
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
        """Cria o objeto. As cores 'comuns' viram cor de vértice num único material
        (menos chamadas de desenho no celular); só os materiais que brilham ficam separados."""
        bm = self.bm; bm.normal_update()
        me = bpy.data.meshes.new(self.name); bm.to_mesh(me); bm.free()
        final = ['base']; remap = {}
        for i, name in enumerate(self.mats):
            if 'e' in PAL[name]:
                if name not in final: final.append(name)
                remap[i] = final.index(name)
            else:
                remap[i] = 0
        col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
        for p in me.polygons:
            c = srgb(PAL[self.mats[p.material_index]]['c']) + [1.0]
            for li in p.loop_indices: col.data[li].color = c
            p.material_index = remap[p.material_index]
        me.color_attributes.active_color = col
        for m in final: me.materials.append(M(m))
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

def _arch_span(m, cx, R, base_z, rise, width, depth, seed, rings=25):
    """Ponte em arco entre duas pernas (varredura de um retângulo)."""
    path, norms = [], []
    for k in range(rings):
        a = math.pi * (1 - k / (rings - 1))
        path.append(Vector((cx + R * math.cos(a), 0, base_z + R * rise * math.sin(a))))
        norms.append(Vector((math.cos(a) * rise, 0, math.sin(a))).normalized())
    before = set(m.bm.verts)
    m.sweep('sand', path, norms, width, -depth / 2, depth / 2)
    new = [v for v in m.bm.verts if v not in before]
    m.paint(new, lambda f: 'moss' if f.normal.z > 0.65 else BANDS[int((f.calc_center_median().x + 200) / (width * 0.7)) % 4])
    m.jitter(new, width * 0.12, 0.6 / width * 2, seed, radial=False)

def make_arch_giant(name, seed):
    """Arco de pedra gigante: vão de ~40 m de largura e ~35 m de altura."""
    rnd = random.Random(seed); m = Mesh(name)
    gap, leg_r, leg_h = 44.0, 10.0, 26.0
    for sx in (-1, 1):
        vs, _ = strata_column(m, rnd, leg_r, leg_h, 4, x0=sx * (gap / 2 + leg_r * 0.8), segs=10, moss_top=False)
        m.jitter([v for v in vs if v.co.z > 0.3], 1.3, 0.12, seed + sx)
    _arch_span(m, 0, gap / 2 + leg_r * 0.8, leg_h - 1.5, 0.55, 10.0, 14.0, seed + 3, rings=33)
    return m.done()

def make_arch_twin(name, seed):
    """Dois arcos lado a lado (três pernas)."""
    rnd = random.Random(seed); m = Mesh(name)
    gap, leg_r, leg_h = 16.0, 4.5, 16.0
    step = gap + leg_r * 1.6
    for x in (-step, 0.0, step):
        vs, _ = strata_column(m, rnd, leg_r, leg_h, 3, x0=x, moss_top=False)
        m.jitter([v for v in vs if v.co.z > 0.3], 0.5, 0.3, seed + int(x))
    for c in (-step / 2, step / 2):
        _arch_span(m, c, step / 2, leg_h - 0.8, 0.7, 4.0, 5.5, seed + int(c) + 9)
    return m.done()

def make_rock_ring(name, seed):
    """Anel de pedra meio enterrado: passa-se pelo buraco (~15 m)."""
    rnd = random.Random(seed); m = Mesh(name)
    Rr, w, cz = 13.5, 7.0, 6.0
    path, norms = [], []
    a0 = math.asin(max(-1.0, min(1.0, (-cz - 1.0) / Rr)))
    n = 40
    for k in range(n + 1):
        a = lerp(a0, math.pi - a0, k / n)
        path.append(Vector((Rr * math.cos(a), 0, cz + Rr * math.sin(a))))
        norms.append(Vector((math.cos(a), 0, math.sin(a))))
    before = set(m.bm.verts)
    m.sweep('sand', path, norms, w, -4.5, 4.5)
    new = [v for v in m.bm.verts if v not in before]
    m.paint(new, lambda f: 'moss' if f.normal.z > 0.7 else BANDS[int((f.calc_center_median().z + 50) / 4.0) % 4])
    m.jitter(new, 0.9, 0.18, seed, radial=False)
    for sx in (-1, 1):
        vs = m.ico('rust', 5.0, T(sx * 13.5, 0, 0.5) @ S(1.4, 1.3, 0.6), sub=1)
        m.jitter(vs, 0.8, 0.3, seed + sx, radial=False)
    return m.done()

def make_rock_fin(name, seed):
    """Lâmina de rocha alta e fina, em camadas."""
    rnd = random.Random(seed); m = Mesh(name)
    L, Tk, H, tiers = 30.0, 6.0, 44.0, 6
    z = 0.0
    for i in range(tiers):
        h = H / tiers; k = 1 - i * 0.11
        vs = m.box(BANDS[(i + rnd.randint(0, 1)) % 4], rnd.uniform(-1, 1), rnd.uniform(-0.4, 0.4), z + h / 2, L * k, Tk * (1 - i * 0.07), h, RZ(rnd.uniform(-4, 4)))
        z += h
    allv = list(m.bm.verts)
    bmesh.ops.subdivide_edges(m.bm, edges=list(m.bm.edges), cuts=2, use_grid_fill=True)
    m.jitter([v for v in m.bm.verts if v.co.z > 0.3], 1.2, 0.15, seed, radial=False)
    m.cone('moss', 3.5, 2.0, 1.2, T(0, 0, z + 0.3), segs=8)
    return m.done()

def make_butte(name, seed):
    """Formação gigante (marco no horizonte): ~100 m de largura, ~70 m de altura."""
    rnd = random.Random(seed); m = Mesh(name)
    vs, top = strata_column(m, rnd, 48.0, 66.0, 5, segs=16)
    m.jitter([v for v in vs if v.co.z > 0.3], 5.0, 0.04, seed)
    for (x, y, r, h) in [(52, 10, 10, 50), (-50, -14, 8, 40), (20, -46, 7, 34)]:
        v2, _ = strata_column(m, rnd, r, h, 4, x0=x, y0=y)
        m.jitter([v for v in v2 if v.co.z > 0.3], r * 0.12, 0.2, seed + int(x))
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

# ------------------------------------------------------------------ mesa com gruta e teto de pedra (mapa da corrida)
def make_cave_mesa(name, L=680.0, W=400.0, Hm=58.0):
    """Mesa enorme atravessada por uma gruta reta (atalho). Gruta ao longo de +Y, chão em z=0."""
    m = Mesh(name)
    THW, TWALL, TARCH = 13.0, 10.0, 6.0
    def width(y): return W * (0.45 + 0.55 * math.sin(math.pi * y / L)) / 2
    def top(x, y): return Hm + 7 * noise.noise(Vector((x * 0.02, y * 0.02, 1.3))) + 4 * noise.noise(Vector((x * 0.07, y * 0.07, 4.1)))
    def atop(x): return TWALL + TARCH * math.sqrt(max(0.0, 1 - (x / THW) ** 2))
    def band(z): return BANDS[int((z + 40) / 6.5) % 4]
    us = [i / 14.0 - 1 for i in range(29)]
    ys = [i * L / 60 for i in range(61)]
    grid = [[m.bm.verts.new((u * width(y), y, top(u * width(y), y))) for u in us] for y in ys]
    for j in range(len(ys) - 1):
        for i in range(len(us) - 1):
            f = m.bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])); f.normal_update()
            if f.normal.z < 0: f.normal_flip()
            f.material_index = m.mi('moss' if f.normal.z > 0.9 else 'sand')
    BOT = -22.0
    for sx in (-1, 1):  # paredões laterais
        for y0, y1 in zip(ys, ys[1:]):
            x0, x1 = sx * width(y0), sx * width(y1)
            t0, t1 = top(x0, y0), top(x1, y1)
            for k in range(6):
                za0, za1 = lerp(BOT, t0, k / 6), lerp(BOT, t0, (k + 1) / 6)
                zb0, zb1 = lerp(BOT, t1, k / 6), lerp(BOT, t1, (k + 1) / 6)
                bulge = lambda z, y: 2.5 * noise.noise(Vector((y * 0.05, z * 0.08, sx * 3.0)))
                pts = [(x0 + sx * bulge(za0, y0), y0, za0), (x1 + sx * bulge(zb0, y1), y1, zb0), (x1 + sx * bulge(zb1, y1), y1, zb1), (x0 + sx * bulge(za1, y0), y0, za1)]
                m.face(band((za0 + za1) / 2), pts, want=(sx, 0, 0))
    ts = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
    for yf, sg in ((0.0, -1), (L, 1)):  # faces da frente e de trás com a boca da gruta
        w = width(yf)
        cols_l = [-w + (w - THW) * i / 10 for i in range(11)]
        cols_in = [-THW + i * 1.3 for i in range(21)]
        cols_r = [THW + (w - THW) * i / 10 for i in range(11)]
        for group, zb in ((cols_l, lambda x: BOT), (cols_in, atop), (cols_r, lambda x: BOT)):
            for a, b in zip(group, group[1:]):
                Ha, Hb = top(a, yf), top(b, yf)
                for t0, t1 in zip(ts, ts[1:]):
                    za0, za1 = lerp(zb(a), Ha, t0), lerp(zb(a), Ha, t1); zb0, zb1 = lerp(zb(b), Hb, t0), lerp(zb(b), Hb, t1)
                    m.face(band((za0 + za1 + zb0 + zb1) / 4), [(a, yf, za0), (b, yf, zb0), (b, yf, zb1), (a, yf, za1)], want=(0, sg, 0))
    sec = [(-THW, -1.0), (-THW, TWALL)] + [(x, atop(x)) for x in cols_in[1:-1]] + [(THW, TWALL), (THW, -1.0)]
    for y0, y1 in zip(ys, ys[1:]):  # interior da gruta
        for (xa, za), (xb, zb_) in zip(sec, sec[1:]):
            cx, cz = (xa + xb) / 2, (za + zb_) / 2
            jit = lambda x, z, y: Vector((0.8 * noise.noise(Vector((x * 0.2, y * 0.05, z * 0.2))), 0, 0.6 * noise.noise(Vector((z * 0.2, y * 0.05, x * 0.2)))))
            pa = Vector((xa, y0, za)) + jit(xa, za, y0); pb = Vector((xb, y0, zb_)) + jit(xb, zb_, y0)
            pc = Vector((xb, y1, zb_)) + jit(xb, zb_, y1); pd = Vector((xa, y1, za)) + jit(xa, za, y1)
            m.face('rock_dark', [pa, pb, pc, pd], want=(-cx, 0, 4.0 - cz))
    return m.done()

def make_canyon_roof(name, L=180.0, W=100.0):
    """Laje de pedra que cobre o desfiladeiro estreito: vira caverna com luz no fim."""
    m = Mesh(name)
    nx, ny = 26, 46
    def bottom(x, y):
        z = 27 + 4 * noise.noise(Vector((x * 0.05, y * 0.05, 2.0))) + 2 * noise.noise(Vector((x * 0.2, y * 0.2, 5.0)))
        spike = max(0.0, noise.noise(Vector((x * 0.11, y * 0.11, 9.0))) - 0.25) * 18
        return z - spike
    xs = [-W / 2 + W * i / (nx - 1) for i in range(nx)]; ys = [L * j / (ny - 1) for j in range(ny)]
    bot = [[m.bm.verts.new((x, y, bottom(x, y))) for x in xs] for y in ys]
    TOP = 80.0
    topv = [[m.bm.verts.new((x, y, TOP)) for x in xs] for y in ys]
    for j in range(ny - 1):
        for i in range(nx - 1):
            f = m.bm.faces.new((bot[j][i], bot[j][i + 1], bot[j + 1][i + 1], bot[j + 1][i])); f.normal_update()
            if f.normal.z > 0: f.normal_flip()
            f.material_index = m.mi('rock_dark')
            g = m.bm.faces.new((topv[j][i], topv[j][i + 1], topv[j + 1][i + 1], topv[j + 1][i])); g.normal_update()
            if g.normal.z < 0: g.normal_flip()
            g.material_index = m.mi('sand')
    for j, sg in ((0, -1), (ny - 1, 1)):  # bordas da frente e de trás (entrada da caverna)
        for i in range(nx - 1):
            f = m.bm.faces.new((bot[j][i], bot[j][i + 1], topv[j][i + 1], topv[j][i])); f.normal_update()
            if f.normal.y * sg < 0: f.normal_flip()
            f.material_index = m.mi(BANDS[i % 4])
    return m.done()

# ------------------------------------------------------------------ veículo da corrida
def make_vespa(name):
    """'Vespa': dois motores grandes à frente puxando uma cabine pequena (frente = +Y)."""
    m = Mesh(name)
    zc = 1.3
    for sx in (-1, 1):
        x = sx * 2.3
        m.cone('p_orange', 0.85, 0.8, 5.6, T(x, 7.6, zc) @ RX(-90), segs=16)
        m.cone('p_rust', 0.82, 0.62, 1.2, T(x, 4.2, zc) @ RX(-90), segs=16)
        for yb in (5.6, 7.4, 9.2):
            m.cone('p_metal', 0.88, 0.88, 0.22, T(x, yb, zc) @ RX(-90), segs=16, caps=False)
        m.cone('p_dark', 0.95, 0.86, 0.5, T(x, 10.6, zc) @ RX(-90), segs=16)
        m.cone('p_metal', 0.7, 0.7, 0.05, T(x, 10.86, zc) @ RX(-90), segs=12)
        for k in range(12):  # coroa de espinhos na entrada de ar
            a = k / 12 * math.tau
            p = Vector((x + math.cos(a) * 0.95, 10.75, zc + math.sin(a) * 0.95))
            d = Vector((math.cos(a) * 0.5, 1.0, math.sin(a) * 0.5)).normalized()
            m.cone('p_metal', 0.12, 0.0, 0.55, T(*p) @ align_z(d) @ T(0, 0, 0.27), segs=4)
        m.cone('p_dark', 0.66, 0.5, 0.35, T(x, 3.45, zc) @ RX(-90), segs=14)
        m.cone('p_fire', 0.48, 0.48, 0.05, T(x, 3.27, zc) @ RX(-90), segs=14)
        m.box('p_orange', x, 7.0, zc + 1.0, 0.25, 2.2, 0.9, RY(-sx * 12))      # freio aerodinâmico
        m.box('p_cream', x + sx * 0.3, 8.0, zc + 0.05, 0.06, 4.0, 0.25)          # faixa lateral
        m.box('p_beam', sx * 1.45, 8.0, zc, 0.22, 0.22, 0.22)                    # emissor do raio
        for dz in (0.35, -0.35):  # cabos até a cabine
            a = Vector((x - sx * 0.6, 3.9, zc + dz)); b = Vector((sx * 0.45, 0.2, 1.15 + dz * 0.5))
            dvec = b - a
            m.cone('p_dark', 0.05, 0.05, dvec.length, T(*((a + b) / 2)) @ align_z(dvec), segs=5)
    m.box('p_beam', 0, 8.0, zc, 2.7, 0.08, 0.08)                                 # raio de energia entre os motores
    # cabine
    m.cone('p_orange', 0.95, 0.55, 3.2, T(0, -1.2, 1.1) @ RX(-90) @ S(1, 0.75, 1), segs=14)
    m.cone('p_orange', 0.55, 0.05, 0.9, T(0, 0.85, 1.1) @ RX(-90) @ S(1, 0.75, 1), segs=14)
    m.cone('p_rust', 0.96, 0.96, 0.35, T(0, -2.7, 1.1) @ RX(-90) @ S(1, 0.75, 1), segs=14)
    for sx in (-1, 1):
        m.cone('p_orange', 0.42, 0.42, 1.8, T(sx * 1.05, -2.0, 0.85) @ RX(-90), segs=10)
        m.cone('p_dark', 0.3, 0.3, 0.06, T(sx * 1.05, -2.92, 0.85) @ RX(-90), segs=10)
    m.sphere('p_dark', 0.62, T(0, -1.0, 1.55) @ S(1, 1.3, 0.55), u=12, v=6)
    m.sphere('v_helmet', 0.3, T(0, -1.1, 1.85), u=10, v=6)
    m.box('p_cream', 0, -1.6, 1.62, 0.3, 1.6, 0.06)
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


# ------------------------------------------------------------------ peças do mapa grande (túneis, pontes, aqueduto, ruínas)
def make_tunnel(name, L, Hl, W=84.0):
    """Bloco de túnel: tampa plana a Hl (por cima passa-se de carro), túnel de 36 m de largura por baixo.
    Chão aberto em z=0 (o chão é o terreno), ao longo de +Y desde a origem."""
    m = Mesh(name)
    THW, TWALL, TARCH = 18.0, 11.0, 7.0
    BOT = -3.0
    def top(x, y): return Hl + 0.4 * noise.noise(Vector((x * 0.05, y * 0.05, 1.3)))
    def atop(x): return TWALL + TARCH * math.sqrt(max(0.0, 1 - (x / THW) ** 2))
    def band(z): return BANDS[int((z + 40) / 6.5) % 4]
    n_y = max(8, int(L / 12)); ys = [i * L / n_y for i in range(n_y + 1)]
    us = [i / 10.0 - 1 for i in range(21)]
    grid = [[m.bm.verts.new((u * W / 2, y, top(u * W / 2, y))) for u in us] for y in ys]
    for j in range(len(ys) - 1):
        for i in range(len(us) - 1):
            f = m.bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])); f.normal_update()
            if f.normal.z < 0: f.normal_flip()
            f.material_index = m.mi('moss')
    for sx in (-1, 1):  # paredes de fora (ficam enterradas no terreno)
        for y0, y1 in zip(ys, ys[1:]):
            x = sx * W / 2
            m.face('rock_dark', [(x, y0, BOT), (x, y1, BOT), (x, y1, top(x, y1)), (x, y0, top(x, y0))], want=(sx, 0, 0))
    ts = [0, 0.2, 0.4, 0.6, 0.8, 1.0]
    for yf, sg in ((0.0, -1), (L, 1)):  # bocas do túnel
        cols_l = [-W / 2 + (W / 2 - THW) * i / 6 for i in range(7)]
        cols_in = [-THW + i * 1.5 for i in range(25)]
        cols_r = [THW + (W / 2 - THW) * i / 6 for i in range(7)]
        for group, zb in ((cols_l, lambda x: BOT), (cols_in, atop), (cols_r, lambda x: BOT)):
            for a, b in zip(group, group[1:]):
                Ha, Hb = top(a, yf), top(b, yf)
                for t0, t1 in zip(ts, ts[1:]):
                    za0, za1 = lerp(zb(a), Ha, t0), lerp(zb(a), Ha, t1); zb0, zb1 = lerp(zb(b), Hb, t0), lerp(zb(b), Hb, t1)
                    m.face(band((za0 + za1 + zb0 + zb1) / 4), [(a, yf, za0), (b, yf, zb0), (b, yf, zb1), (a, yf, za1)], want=(0, sg, 0))
        # moldura de pedra clara à volta da boca
        for a, b in zip(cols_in, cols_in[1:]):
            za, zb_ = atop(a), atop(b)
            m.face('cream', [(a, yf + sg * 0.6, za), (b, yf + sg * 0.6, zb_), (b, yf + sg * 0.6, zb_ + 2.2), (a, yf + sg * 0.6, za + 2.2)], want=(0, sg, 0))
    sec = [(-THW, -1.0), (-THW, TWALL)] + [(x, atop(x)) for x in [-THW + i * 1.5 for i in range(1, 24)]] + [(THW, TWALL), (THW, -1.0)]
    for y0, y1 in zip(ys, ys[1:]):  # interior
        for (xa, za), (xb, zb_) in zip(sec, sec[1:]):
            cx, cz = (xa + xb) / 2, (za + zb_) / 2
            jit = lambda x, z, y: Vector((0.7 * noise.noise(Vector((x * 0.2, y * 0.05, z * 0.2))), 0, 0.5 * noise.noise(Vector((z * 0.2, y * 0.05, x * 0.2)))))
            pa = Vector((xa, y0, za)) + jit(xa, za, y0); pb = Vector((xb, y0, zb_)) + jit(xb, zb_, y0)
            pc = Vector((xb, y1, zb_)) + jit(xb, zb_, y1); pd = Vector((xa, y1, za)) + jit(xa, za, y1)
            m.face('rock_dark', [pa, pb, pc, pd], want=(-cx, 0, 5.0 - cz))
    return m.done()

def make_bridge(name, L, W=30.0, broken=0.0, seed=3, deep=46.0):
    """Ponte natural de pedra: tabuleiro plano em z=0 (passa-se por cima), arco por baixo,
    pilares nas pontas que descem para dentro das paredes. Ao longo de +Y desde a origem.
    broken > 0: falta um troço no meio (salto!)."""
    m = Mesh(name)
    def under(y):
        t = y / L
        return -4.0 - deep * (1 - math.sin(math.pi * t)) ** 1.6
    def band(z): return BANDS[int((z + 60) / 5.0) % 4]
    def piece(y0, y1, jag0, jag1):
        n = max(4, int((y1 - y0) / 4)); ys = [y0 + (y1 - y0) * i / n for i in range(n + 1)]
        rings = []
        for k, y in enumerate(ys):
            wob = 1.2 * noise.noise(Vector((y * 0.07, seed, 0.3)))
            wt = W / 2 + wob; wb = W / 2 * 0.86 + wob
            zt = 0.0; zb = under(y) + 0.8 * noise.noise(Vector((y * 0.1, seed, 1.7)))
            if (k == 0 and jag0) or (k == len(ys) - 1 and jag1):
                zt -= 1.5
            rings.append([m.bm.verts.new((-wt, y, zt)), m.bm.verts.new((wt, y, zt)),
                          m.bm.verts.new((wb, y, zb)), m.bm.verts.new((-wb, y, zb))])
        for r0, r1 in zip(rings, rings[1:]):
            yc = (r0[0].co.y + r1[0].co.y) / 2
            for k in range(4):
                f = m.bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
                f.normal_update(); zc = f.calc_center_median().z
                f.material_index = m.mi('moss' if (k == 0 and zc > -0.5) else band(zc))
        for r, want in ((rings[0], (0, -1, 0)), (rings[-1], (0, 1, 0))):
            f = m.bm.faces.new(r); f.normal_update()
            if f.normal.dot(Vector(want)) < 0: f.normal_flip()
            f.material_index = m.mi('rust')
    if broken > 0:
        piece(0.0, L / 2 - broken / 2, False, True)
        piece(L / 2 + broken / 2, L, True, False)
    else:
        piece(0.0, L, False, False)
    bmesh.ops.recalc_face_normals(m.bm, faces=list(m.bm.faces))
    return m.done()

def make_aqueduct_seg(name, seg=40.0, deck=20.0, W=20.0):
    """Troço de aqueduto (como nas imagens): pilares, arco e tabuleiro por cima (passa-se por cima)."""
    m = Mesh(name)
    for y in (1.6, seg - 1.6):  # pilares
        m.box('cream', 0, y, (deck - 3 - 12) / 2, W * 0.8, 3.2, deck - 3 + 12)
        m.box('cream_dark', 0, y, -11.5 + 0.8, W * 0.9, 4.4, 1.6)
    m.box('cream', 0, seg / 2, deck - 1.6, W, seg, 3.2)          # tabuleiro
    for sx in (-1, 1):                                           # muretes baixos
        m.box('cream_dark', sx * (W / 2 - 0.4), seg / 2, deck + 0.35, 0.8, seg, 0.7)
    m.box('orange_band', 0, seg / 2, deck - 3.6, W * 0.82, seg, 0.8)  # friso
    path, norms = [], []
    R = seg / 2 - 3.2; base = deck - 3.4 - R * 0.95
    for k in range(17):  # arco entre os pilares
        a = math.pi * (1 - k / 16)
        path.append(Vector((0, 0, 0)))
        path[-1] = Vector((R * math.cos(a) + seg / 2, 0, base + R * 0.95 * math.sin(a)))
        norms.append(Vector((math.cos(a), 0, math.sin(a) * 0.95)).normalized())
    before = set(m.bm.verts)
    m.sweep('cream', path, norms, 2.6, -W * 0.4, W * 0.4)
    new = [v for v in m.bm.verts if v not in before]
    for v in new:  # a varredura é no plano XZ: roda para o plano YZ
        v.co = Vector((v.co.y, v.co.x, v.co.z))
    bmesh.ops.recalc_face_normals(m.bm, faces=list({f for v in new for f in v.link_faces}))
    allv = list(m.bm.verts)
    m.jitter(allv, 0.15, 0.4, 5.0, radial=False)
    return m.done()

def make_ruin_column(name, seed):
    """Coluna antiga partida, com musgo."""
    rnd = random.Random(seed); m = Mesh(name)
    m.box('cream_dark', 0, 0, 0.6, 4.4, 4.4, 1.2)
    m.cone('cream', 1.7, 1.75, 0.8, T(0, 0, 1.6), segs=12)
    h = rnd.uniform(9, 14)
    vs = m.cone('cream', 1.45, 1.3, h, T(0, 0, 2.0 + h / 2), segs=12)
    m.jitter([v for v in vs if v.co.z > h], 1.2, 0.8, seed, radial=False)
    m.cone('orange_band', 1.48, 1.48, 0.5, T(0, 0, 2.0 + h * 0.3), segs=12, caps=False)
    m.cone('moss', 1.6, 1.2, 0.6, T(0, 0, 2.0 + h - 0.1), segs=10)
    for k in range(2):  # pedaços caídos
        r = rnd.uniform(0.9, 1.3); a = rnd.uniform(0, math.tau)
        m.cone('cream', r, r, rnd.uniform(1.6, 2.6), T(math.cos(a) * 4, math.sin(a) * 4, r * 0.8) @ RX(90) @ RZ(rnd.uniform(0, 90)), segs=10)
    return m.done()

def make_ruin_wall(name, seed):
    """Muro em ruínas com uma porta em arco (como as construções das imagens)."""
    rnd = random.Random(seed); m = Mesh(name)
    Lw, Tk, Hw = 18.0, 2.6, 11.0
    door_hw, door_h = 3.2, 7.0
    cols = [-Lw / 2 + i * Lw / 18 for i in range(19)]
    def top_h(x): return Hw - (abs(x) > 4) * rnd.uniform(0, 3.5) - max(0.0, x - 3) * 0.5
    tops = [top_h(x) for x in cols]
    for (xa, ha), (xb, hb) in zip(zip(cols, tops), zip(cols[1:], tops[1:])):
        xc = (xa + xb) / 2
        def zb(x):
            if abs(x) < door_hw:
                return door_h - door_hw + math.sqrt(max(0.0, door_hw ** 2 - x * x))
            return 0.0
        for sy in (-1, 1):
            m.face('cream', [(xa, sy * Tk / 2, zb(xa)), (xb, sy * Tk / 2, zb(xb)), (xb, sy * Tk / 2, hb), (xa, sy * Tk / 2, ha)], want=(0, sy, 0))
        m.face('moss', [(xa, -Tk / 2, ha), (xb, -Tk / 2, hb), (xb, Tk / 2, hb), (xa, Tk / 2, ha)], want=(0, 0, 1))
        if abs(xc) < door_hw:
            m.face('cream_dark', [(xa, -Tk / 2, zb(xa)), (xb, -Tk / 2, zb(xb)), (xb, Tk / 2, zb(xb)), (xa, Tk / 2, zb(xa))], want=(0, 0, -1))
    for sx, x in ((-1, cols[0]), (1, cols[-1])):
        h = tops[0] if sx < 0 else tops[-1]
        m.face('cream_dark', [(x, -Tk / 2, 0), (x, Tk / 2, 0), (x, Tk / 2, h), (x, -Tk / 2, h)], want=(sx, 0, 0))
    for x in (-door_hw - 0.4, door_hw + 0.4):
        m.box('orange_band', x, 0, door_h * 0.5, 0.6, Tk + 0.3, door_h)
    m.box('cream_dark', 0, 0, 0.4, Lw + 1, Tk + 1.2, 0.8)
    return m.done()

def make_ruin_tower(name, seed):
    """Torre antiga alta e estreita (marco na paisagem, como a das imagens)."""
    rnd = random.Random(seed); m = Mesh(name)
    z = 0.0; r = 10.0
    tiers = [(14, 10.0), (12, 8.6), (11, 7.4), (10, 6.6), (9, 5.6), (7, 4.6)]
    for i, (h, rr) in enumerate(tiers):
        m.cone('cream' if i % 2 == 0 else 'sand_light', rr, rr * 0.94, h, T(0, 0, z + h / 2) @ RZ(i * 13), segs=12)
        m.cone('orange_band', rr * 1.04, rr * 1.04, 0.9, T(0, 0, z + h - 0.45), segs=12, caps=False)
        for k in range(4):  # janelas em arco
            a = math.radians(k * 90 + i * 20)
            p = Vector((math.cos(a) * rr * 0.96, math.sin(a) * rr * 0.96, z + h * 0.55))
            m.box('window', p.x, p.y, p.z, 1.6, 1.6, h * 0.35, RZ(math.degrees(a)))
        z += h
    vs = m.cone('cream', 4.6, 2.0, 6.0, T(0, 0, z + 3.0), segs=12)
    m.jitter([v for v in vs if v.co.z > z + 1], 1.4, 0.5, seed, radial=False)
    m.sphere('moss', 5.0, T(-2, 1, z + 1.5) @ S(1, 1, 0.5), u=10, v=6)
    for k in range(5):  # trepadeiras de musgo
        a = rnd.uniform(0, math.tau); zz = rnd.uniform(8, z - 8)
        m.sphere('moss_dark', rnd.uniform(1.5, 2.6), T(math.cos(a) * 8.5, math.sin(a) * 8.5, zz) @ S(1, 1, 1.6), u=8, v=6)
    return m.done()

# ------------------------------------------------------------------ montagem
def build_all():
    global COLL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    COLL = bpy.data.collections.new('RACESTARS'); bpy.context.scene.collection.children.link(COLL)
    B = []
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
    B.append(make_arch_giant('arch_giant', 41))
    B.append(make_arch_twin('arch_twin', 43))
    B.append(make_rock_ring('rock_ring', 47))
    B.append(make_rock_fin('rock_fin', 53))
    B.append(make_butte('butte', 59))
    B.append(make_ruin_column('ruin_column', 61))
    B.append(make_ruin_wall('ruin_wall', 67))
    B.append(make_ruin_tower('ruin_tower', 71))
    B.append(make_aqueduct_seg('aqueduct_seg'))
    mj = os.path.normpath(os.path.join(HERE, '..', 'game', 'assets', 'map', 'map.json'))
    if os.path.exists(mj):  # túneis e pontes feitos à medida do mapa
        import json
        info = json.load(open(mj))
        for t in info['tunnels']:
            B.append(make_tunnel(t['name'], t['len'], t['height']))
        for k, b in enumerate(info['bridges']):
            B.append(make_bridge(b['name'], b['len'], b['width'], b['broken'], seed=k + 3, deep=b.get('deep', 46.0)))
    B.append(make_canyon_roof('canyon_roof'))
    B.append(make_vespa('vespa'))
    return B

def export(objs):
    os.makedirs(OUT, exist_ok=True)
    for ob in objs:
        for o in bpy.context.scene.objects: o.select_set(False)
        ob.select_set(True); bpy.context.view_layer.objects.active = ob
        path = os.path.join(OUT, ob.name + '.glb')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_materials='EXPORT', export_cameras=False, export_lights=False,
                                  export_vertex_color='ACTIVE')
        print('exportado', os.path.relpath(path, os.path.join(HERE, '..')), len(ob.data.polygons), 'faces')

def layout(objs):
    """Arruma as peças em duas fileiras no .blend (grandes atrás, pequenas na frente)."""
    big = ['canyon_roof', 'ruin_tower', 'aqueduct_seg', 'butte', 'arch_giant', 'mesa', 'arch_twin', 'rock_ring', 'rock_fin', 'arch', 'rock_spire_c', 'float_island']
    def width(ob): return max(v.co.x for v in ob.data.vertices) - min(v.co.x for v in ob.data.vertices)
    isbig = lambda o: o.name in big or o.name.startswith(('tunel', 'ponte'))
    rows = {0: [o for o in objs if not isbig(o)], 1: [o for o in objs if isbig(o)]}
    for row, items in rows.items():
        x = 0.0; y = 0.0 if row == 0 else 110.0
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
    co.location = (0, -190, 95); co.rotation_euler = (math.radians(64), 0, 0)
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
