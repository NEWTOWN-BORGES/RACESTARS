extends Node3D
## Coloca no mundo tudo o que vem do Blender e de map.json: rochas, árvores, ruínas, túneis,
## pontes, aqueduto, tetos de pedra, lagos e rios, ilhas flutuantes, relva e flores, bandeirolas,
## manadas, as estruturas colossais (vêem-se a muitos km) e os portões do circuito com as balizas.
## Tudo é estático (sem animações) para ser leve no telemóvel. As colisões das peças são criadas
## direto no servidor de física (muito mais leve que nós).

signal checkpoint_passed(index: int)
signal finish_passed
signal pad_hit

const CELL_GROUP := 1024.0       # peças agrupadas em quadrados de 1 km (um MultiMesh por tipo)
const COVER_GROUP := 256.0       # relva/flores em quadrados mais pequenos (vêem-se só de perto)
const ROCK_PROPS := ["rock_spire_a", "rock_spire_b", "rock_spire_c", "boulder_a", "boulder_b", "mesa", "arch",
	"arch_giant", "arch_twin", "rock_ring", "rock_fin", "butte", "canyon_roof"]
# forma de colisão de cada peça: convexa, malha exata, ou cilindro [raio, altura] (troncos, colunas)
const COLLIDE := {
	"rock_spire_a": "convex", "rock_spire_b": "convex", "rock_spire_c": "convex", "boulder_a": "convex",
	"boulder_b": "convex", "mesa": "trimesh", "arch": "trimesh", "arch_giant": "trimesh", "arch_twin": "trimesh",
	"rock_ring": "trimesh", "rock_fin": "convex", "butte": "convex", "pillar": [1.3, 13.0], "tower_pod": "convex",
	"tree_acacia": [0.6, 6.0], "tree_acacia_b": [0.5, 5.0], "tree_mushroom": [1.1, 12.0],
	"crystals_cyan": [2.2, 4.0], "crystals_mag": [2.2, 4.0], "crystals_cyan_big": "convex", "crystals_mag_big": "convex",
	"ruin_column": [1.6, 12.0], "ruin_wall": "trimesh", "ruin_tower": [9.5, 70.0],
	"cactus": [0.8, 7.0], "palm": [0.6, 7.0], "pine": [0.7, 8.0], "tree_giant": [3.8, 30.0], "dead_tree": [0.5, 8.0],
	"colosso_estatua": "trimesh", "colosso_costelas": "trimesh", "colosso_nave": "trimesh",
}
const VIS_RANGE := {"butte": 4200.0, "mesa": 3400.0, "arch_giant": 3400.0, "arch_twin": 2800.0, "rock_ring": 2600.0,
	"rock_fin": 3000.0, "ruin_tower": 4200.0, "arch": 2400.0, "rock_spire_c": 2600.0, "rock_spire_a": 2200.0,
	"tower_pod": 1800.0, "tree_giant": 2600.0, "crystals_cyan_big": 1800.0, "crystals_mag_big": 1800.0,
	"bush": 700.0, "cactus": 1000.0, "dead_tree": 1000.0}
# pedras baixas, cristais pequenos: passa-se por cima (não são obstáculos)
const RIDE_OVER := ["boulder_a", "boulder_b", "crystals_cyan", "crystals_mag", "pebbles"]
const COLOSSAL_VIS := 14000.0     # as estruturas colossais vêem-se até 14 km
const LEVEL_COLORS := {0: Color("#52f2ff"), 1: Color("#ff8a3d"), 2: Color("#ffd23d"), 3: Color("#ffffff")}

var info: Dictionary
var terrain: Node
var props := {}
var rock_mat: ShaderMaterial
var rock_mat_dark: ShaderMaterial
var foliage_mat: ShaderMaterial
var checkpoints: Array = []      # [{pos, dir, w, node, column}]
var player: Node3D
var cave_boxes: Array = []       # [{origin, fwd, len, half_w, top}] túneis e tetos (para o som e a luz)
var spawn_points: Array = []     # [[Vector3, Vector2 direção]] pontos dos caminhos (renascer / viajar no mapa)
var _bodies: Array = []          # RIDs no servidor de física
var _shapes: Array = []          # formas criadas aqui: guardar a referência (senão são libertadas e a colisão desaparece)
var _warm: Node3D
var _warm_frames := 0
var _space: RID
## Prova escolhida: {id, name, type, laps, start, gates (portões físicos), finish (ou {})}. Em exploração
## é a grande corrida (os seus portões ficam como marcos) e as outras provas mostram só o pórtico de partida.
var event: Dictionary = {}
var explore := false

func setup(map_info: Dictionary, t: Node) -> void:
	info = map_info
	terrain = t
	_space = get_world_3d().space
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = preload("res://shaders/rock.gdshader")
	terrain.apply_biome(rock_mat, info)
	rock_mat_dark = rock_mat.duplicate()
	rock_mat_dark.set_shader_parameter("darken", 0.75)
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = preload("res://shaders/foliage.gdshader")
	var t0 := Time.get_ticks_msec()
	_place_props()
	var t1 := Time.get_ticks_msec()
	_place_set_pieces()
	_place_water()
	_place_ocean()
	_place_islands()
	var t2 := Time.get_ticks_msec()
	_place_cover()
	_place_banners()
	_place_herds()
	_place_colossi()
	var scenery := preload("res://scripts/island_scenery.gd").new()
	add_child(scenery)
	scenery.setup(info, terrain)
	_place_checkpoints()
	_place_route_posts()
	_place_pads()
	var t3 := Time.get_ticks_msec()
	_place_veg()
	print("vegetação: %d ms" % (Time.get_ticks_msec() - t3))
	print("mapa: peças %d ms, cenário %d ms, resto %d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])

func _exit_tree() -> void:
	for b in _bodies:
		PhysicsServer3D.free_rid(b)
	_bodies.clear()

# ------------------------------------------------------------------ peças do Blender
func _prop(name: String) -> Dictionary:
	if props.has(name):
		return props[name]
	var scene: PackedScene = load("res://assets/models/%s.glb" % name.trim_suffix("_big"))
	var inst := scene.instantiate()
	var mesh: Mesh = _find_mesh(inst).mesh
	inst.free()
	if props.has(name.trim_suffix("_big")):
		mesh = props[name.trim_suffix("_big")].mesh
	var shape: Shape3D = null
	var c = COLLIDE.get(name, "")
	if c is Array:
		var cyl := CylinderShape3D.new()
		cyl.radius = c[0]
		cyl.height = c[1]
		shape = cyl
	elif c == "convex":
		shape = mesh.create_convex_shape(true, true)
	elif c == "trimesh":
		shape = mesh.create_trimesh_shape()
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).vertex_color_use_as_albedo = true
			(m as StandardMaterial3D).specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			if not m.emission_enabled and m.metallic < 0.3:
				m.roughness = maxf(m.roughness, 0.78)
			if name.trim_suffix("_big") in ["tree_acacia", "tree_acacia_b", "tree_giant", "bush", "pine", "palm", "fern"] and not m.emission_enabled:
				mesh.surface_set_material(i, foliage_mat)
	props[name] = {"mesh": mesh, "shape": shape, "cyl": c is Array, "h": (c[1] if c is Array else 0.0)}
	return props[name]

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null

func _xf(pos: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)

func _new_body(layer: int) -> RID:
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(b, layer)
	PhysicsServer3D.body_set_collision_mask(b, 0)
	PhysicsServer3D.body_set_space(b, _space)
	_bodies.append(b)
	return b

func _place_props() -> void:
	var groups := {}
	var bodies := {}
	for p in info.props:
		var name: String = p[0]
		var pos := Vector3(p[1], p[2], p[3])
		var key := Vector2i(floori(pos.x / CELL_GROUP), floori(pos.z / CELL_GROUP))
		var t := _xf(pos, p[4], p[5])
		groups.get_or_add(key, {}).get_or_add(name, []).append(t)
		var P := _prop(name)
		if P.shape:
			# pedras baixas e cristais pequenos ficam na camada 2: o veículo passa por cima
			var soft: bool = name in RIDE_OVER
			var bkey := Vector3i(key.x, key.y, 1 if soft else 0)
			if not bodies.has(bkey):
				bodies[bkey] = _new_body(2 if soft else 1)
			# cilindros: centro a meia altura (o modelo nasce no chão)
			var st := t * Transform3D(Basis(), Vector3(0, P.h * 0.5, 0)) if P.cyl else t
			PhysicsServer3D.body_add_shape(bodies[bkey], P.shape.get_rid(), st)
	for key in groups:
		for name in groups[key]:
			_multimesh(props[name].mesh, groups[key][name], rock_mat if name in ROCK_PROPS else null,
				VIS_RANGE.get(name, 1500.0), true)

## MultiMesh com alcance de visão contado a partir do centro do grupo (mais o raio do grupo).
func _multimesh(mesh: Mesh, xs: Array, mat: Material, vis: float, shadows: bool) -> MultiMeshInstance3D:
	var c := Vector3.ZERO
	for x in xs:
		c += x.origin
	c /= maxf(1.0, xs.size())
	var rad := 0.0
	for x in xs:
		rad = maxf(rad, Vector2(x.origin.x - c.x, x.origin.z - c.z).length())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, Transform3D(xs[i].basis, xs[i].origin - c))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = c
	if mat:
		mmi.material_override = mat
	mmi.visibility_range_end = vis + rad
	mmi.visibility_range_end_margin = 40.0
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

## Vários MultiMesh, um por quadrado do mapa (para o alcance de visão funcionar bem).
func _grouped(mesh: Mesh, xs: Array, group: float, vis: float, mat: Material = null, shadows := false) -> void:
	var g := {}
	for x in xs:
		g.get_or_add(Vector2i(floori(x.origin.x / group), floori(x.origin.z / group)), []).append(x)
	for k in g:
		_multimesh(mesh, g[k], mat, vis, shadows)

func _place_static(name: String, xf: Transform3D, mat: Material, double_shadow := false) -> MeshInstance3D:
	var P := _prop(name)
	var mi := MeshInstance3D.new()
	mi.mesh = P.mesh
	mi.transform = xf
	if mat:
		mi.material_override = mat
	if double_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # tetos fazem sombra por dentro
	mi.visibility_range_end = 5200.0
	add_child(mi)
	var shape: Shape3D = P.shape if P.shape else P.mesh.create_trimesh_shape()
	_shapes.append(shape)
	PhysicsServer3D.body_add_shape(_new_body(1), shape.get_rid(), xf)
	return mi

func _cave(origin: Vector3, yaw: float, length: float, half_w: float, top: float) -> void:
	cave_boxes.append({"origin": origin, "fwd": Vector3(-sin(yaw), 0.0, -cos(yaw)), "len": length, "half_w": half_w, "top": top})

func _place_set_pieces() -> void:
	# túneis (feitos à medida no Blender: a tampa segue o terreno por cima)
	for t in info.tunnels:
		var pos := Vector3(t.p[0], t.p[1], t.p[2])
		_place_static(t.name, Transform3D(Basis(Vector3.UP, t.yaw), pos), rock_mat, true)
		_cave(pos, t.yaw, float(t.len), float(t.get("thw", 18.0)) + 1.0, pos.y + 16.0)
	# pontes de pedra
	for b in info.bridges:
		_place_static(b.name, Transform3D(Basis(Vector3.UP, b.yaw), Vector3(b.p[0], b.p[1], b.p[2])), rock_mat)
	# aqueduto (troços de 40 m, com uma falha para saltar)
	for a in info.aqueducts:
		var P := _prop("aqueduct_seg")
		var seg_shape: Shape3D = P.mesh.create_trimesh_shape()
		props["aqueduct_seg"].shape = seg_shape
		var fwd := Vector3(-sin(a.yaw), 0.0, -cos(a.yaw))
		var xs: Array = []
		var body := _new_body(1)
		for i in int(a.n):
			if i in a.missing:
				continue
			var xf := Transform3D(Basis(Vector3.UP, a.yaw), Vector3(a.p[0], a.p[1], a.p[2]) + fwd * (i * float(a.seg)))
			xs.append(xf)
			PhysicsServer3D.body_add_shape(body, seg_shape.get_rid(), xf)
		_multimesh(P.mesh, xs, null, 3400.0, true)
	# tetos de pedra sobre as fendas (viram caverna)
	for r in info.roofs:
		var rp := Vector3(r.p[0], r.p[1], r.p[2])
		var fwd := Vector3(-sin(r.yaw), 0.0, -cos(r.yaw))
		_place_static("canyon_roof", _xf(rp - fwd * 90.0, r.yaw, 1.0), rock_mat_dark, true)
		_cave(rp - fwd * 90.0, r.yaw, 180.0, 40.0, rp.y + 24.0)
	# pórticos de partida e chegada (arco largo por cima da estrada)
	var hw := float(event.get("half_w", 46.0))
	if event.type == "circuit":
		var g: Dictionary = event.gates[-1]
		_portal(g, event.name.to_upper(), 0.0, hw)
	else:
		_portal(event.start, "LARGADA", 30.0, hw)
	if not event.get("finish", {}).is_empty():
		var fin: Dictionary = event.finish
		_portal(fin, "META", 0.0, hw)
		_add_trigger(Vector3(fin.p[0], fin.p[1], fin.p[2]), Vector2(fin.dir[0], fin.dir[1]), float(fin.w), -1)
	if explore:   # as outras provas: só o pórtico com o nome, para se encontrarem a explorar
		for e in info.get("events", []):
			if e.id == event.id:
				continue
			var ehw := 46.0 if e.type == "drag" else 34.0
			_portal(e.gates[-1] if e.type == "circuit" else e.start, String(e.name).to_upper(), 0.0 if e.type == "circuit" else 30.0, ehw)

func _portal(d: Dictionary, text: String, ahead: float, half_w: float) -> void:
	var dir := Vector3(d.dir[0], 0, d.dir[1]).normalized()
	var pos := Vector3(d.p[0], d.p[1], d.p[2]) + dir * ahead
	var yaw := atan2(-dir.x, -dir.z)
	var span := (half_w + 6.0) / 47.0
	var gm := MeshInstance3D.new()
	gm.mesh = _prop("gate").mesh
	gm.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(7.6 * span, 3.6, 3.6)), pos)
	gm.visibility_range_end = 4000.0
	add_child(gm)
	var gb := _new_body(1)
	var side := Vector3(-dir.z, 0, dir.x)
	var cyl := CylinderShape3D.new()
	cyl.radius = 6.0
	cyl.height = 40.0
	_shapes.append(cyl)
	for sg in [-1.0, 1.0]:
		PhysicsServer3D.body_add_shape(gb, cyl.get_rid(), Transform3D(Basis(), pos + side * sg * 47.0 * span + Vector3(0, 20, 0)))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 512 if text.length() < 12 else 320
	lbl.pixel_size = 0.03
	lbl.outline_size = 48
	lbl.modulate = Color("#ffd36e")
	lbl.outline_modulate = Color("#3a1d10")
	lbl.position = pos + Vector3(0, 58, 0)
	lbl.rotation.y = yaw
	lbl.visibility_range_end = 2500.0
	add_child(lbl)

## Dentro de um túnel ou debaixo de um teto de pedra (eco no som, luz mais baixa).
func in_cave(p: Vector3) -> bool:
	for t in cave_boxes:
		var rel: Vector3 = p - t.origin
		if rel.length_squared() > (t.len + 60.0) * (t.len + 60.0):
			continue
		var a: float = rel.dot(t.fwd)
		if a > 0.0 and a < t.len and p.y < t.top:
			var side := Vector3(-t.fwd.z, 0, t.fwd.x)
			if absf(rel.dot(side)) < t.half_w:
				return true
	return false

# ------------------------------------------------------------------ água, ilhas, relva, bandeirolas
func _place_ocean() -> void:
	if not info.has("ocean"):
		return
	var ocean: Dictionary = info.ocean
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ocean.gdshader")
	mat.set_shader_parameter("heightmap", terrain.height_texture)
	mat.set_shader_parameter("sea_mask", load(String(ocean.mask)))
	mat.set_shader_parameter("map_size", float(info.size))
	mat.set_shader_parameter("height_cell", float(info.cell))
	mat.set_shader_parameter("sea_y", float(ocean.y))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * float(ocean.size)
	var surface := MeshInstance3D.new()
	surface.name = "Ocean"
	surface.mesh = mesh
	surface.material_override = mat
	surface.position.y = float(ocean.y)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	# Caixas unidas pelo gerador: só na costa/mar, nunca sob túneis ou abismos.
	var body := StaticBody3D.new()
	body.name = "OceanSurface"
	body.set_meta("water", true)
	for rect in ocean.get("collision_rects", []):
		var shape := BoxShape3D.new()
		shape.size = Vector3(float(rect[2]), 2.0, float(rect[3]))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(float(rect[0]), float(ocean.y) - 1.0, float(rect[1]))
		body.add_child(collision)
	add_child(body)

func _place_water() -> void:
	var wmat := ShaderMaterial.new()
	wmat.shader = preload("res://shaders/water.gdshader")
	wmat.set_shader_parameter("heightmap", terrain.height_texture)
	wmat.set_shader_parameter("map_size", float(info.size))
	wmat.set_shader_parameter("height_cell", float(info.cell))
	for w in info.waters:
		var sx := float(w.sx) * 2.0
		var sz := float(w.sz) * 2.0
		var pm := PlaneMesh.new()
		pm.size = Vector2(sx, sz)
		pm.subdivide_width = clampi(int(sx / 120.0), 2, 24)
		pm.subdivide_depth = clampi(int(sz / 120.0), 2, 24)
		pm.material = wmat
		var xf := Transform3D(Basis(Vector3.UP, float(w.yaw)), Vector3(w.c[0], float(w.y), w.c[1]))
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.transform = xf
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 6000.0
		add_child(mi)
		# superfície "dura": o veículo flutua sobre a água
		var body := StaticBody3D.new()
		body.set_meta("water", true)
		body.transform = xf
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(sx, 2.0, sz)
		cs.shape = box
		cs.position = Vector3(0, -1.0, 0)
		body.add_child(cs)
		add_child(body)

func _place_islands() -> void:
	var xs: Array = []
	for i in info.islands:
		xs.append(_xf(Vector3(i[0], i[1], i[2]), i[3], i[4]))
	_grouped(_prop("float_island").mesh, xs, 4096.0, 6000.0)

func _place_cover() -> void:
	for spec in [["grass_tuft", "grass", 300.0], ["flowers", "flowers", 260.0], ["fern", "ferns", 280.0]]:
		var xs: Array = []
		for g in info[spec[1]]:
			xs.append(_xf(Vector3(g[0], g[1], g[2]), g[3], g[4]))
		_grouped(_prop(spec[0]).mesh, xs, COVER_GROUP, spec[2])

func _place_banners() -> void:
	# bandeirolas penduradas entre dois postes, por cima da estrada (como nas imagens)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var colors := [Color("#e5483a"), Color("#ffd23d"), Color("#3fb6e6"), Color("#f4eee2"), Color("#7ac25a")]
	var meshes := {}
	var xs := {}
	for b in info.banners:
		var span := snappedf(float(b[4]), 10.0)
		if not meshes.has(span):
			meshes[span] = _banner_mesh(span, colors, mat)
			xs[span] = []
		xs[span].append(Transform3D(Basis(Vector3.UP, float(b[3])), Vector3(b[0], float(b[1]) - 0.5, b[2])))
	for span in meshes:
		_grouped(meshes[span], xs[span], CELL_GROUP, 1600.0)

func _banner_mesh(span: float, colors: Array, mat: Material) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := 22.0
	var n := int(span / 4.0)
	for k in n:
		var x0 := -span * 0.5 + k * span / n
		var x1 := x0 + span / n * 0.8
		var sag0 := top - 5.0 * (1.0 - pow(2.0 * (x0 / span), 2.0))
		var sag1 := top - 5.0 * (1.0 - pow(2.0 * (x1 / span), 2.0))
		st.set_color(colors[k % colors.size()])
		st.add_vertex(Vector3(x0, sag0, 0))
		st.add_vertex(Vector3(x1, sag1, 0))
		st.add_vertex(Vector3((x0 + x1) * 0.5, (sag0 + sag1) * 0.5 - 2.6, 0))
	for sg in [-1.0, 1.0]:  # postes
		var px: float = sg * span * 0.5
		for q in [[Vector3(px - 0.35, 0, 0), Vector3(px + 0.35, 0, 0), Vector3(px + 0.25, top + 1.0, 0), Vector3(px - 0.25, top + 1.0, 0)],
				[Vector3(px, 0, -0.35), Vector3(px, 0, 0.35), Vector3(px, top + 1.0, 0.25), Vector3(px, top + 1.0, -0.25)]]:
			st.set_color(Color("#5a4038"))
			st.add_vertex(q[0]); st.add_vertex(q[1]); st.add_vertex(q[2])
			st.add_vertex(q[0]); st.add_vertex(q[2]); st.add_vertex(q[3])
	st.generate_normals()
	st.set_material(mat)
	return st.commit()

# ------------------------------------------------------------------ manadas (estáticas)
func _place_herds() -> void:
	var by_kind := {}
	for h in info.herds:
		by_kind.get_or_add(String(h[0]), []).append(_xf(Vector3(h[1], h[2], h[3]), h[4], h[5]))
	for kind in by_kind:
		_grouped(_prop(kind).mesh, by_kind[kind], CELL_GROUP, 1300.0, null, true)

# ------------------------------------------------------------------ estruturas colossais
## Materiais com a neblina leve das estruturas colossais (vêem-se a sair do horizonte).
func _far_fog(m: ShaderMaterial) -> void:
	var env: Environment = get_world_3d().environment
	if env:
		m.set_shader_parameter("fog_col", env.fog_light_color)

func _colossal_mesh(name: String, cache: Dictionary) -> Mesh:
	if cache.has(name):
		return cache[name]
	var mesh: Mesh = _prop(name).mesh.duplicate()
	for i in mesh.get_surface_count():
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/colossal.gdshader")
		_far_fog(m)
		var src := mesh.surface_get_material(i)
		if src is StandardMaterial3D and (src as StandardMaterial3D).emission_enabled:
			m.set_shader_parameter("emit_color", (src as StandardMaterial3D).emission)
			m.set_shader_parameter("emit", (src as StandardMaterial3D).emission_energy_multiplier)
		mesh.surface_set_material(i, m)
	cache[name] = mesh
	return mesh

func _place_colossi() -> void:
	var rock_far := ShaderMaterial.new()
	rock_far.shader = preload("res://shaders/rock_far.gdshader")
	terrain.apply_biome(rock_far, info)
	_far_fog(rock_far)
	var cache := {}
	for c in info.get("colossi", []):
		var name: String = c[0]
		var xf := _xf(Vector3(c[1], c[2], c[3]), c[4], c[5])
		var P := _prop(name)
		var mi := MeshInstance3D.new()
		if name in ROCK_PROPS:
			mi.mesh = P.mesh
			mi.material_override = rock_far
		else:
			mi.mesh = _colossal_mesh(name, cache)
		mi.transform = xf
		mi.visibility_range_end = COLOSSAL_VIS
		mi.extra_cull_margin = 20.0
		add_child(mi)
		if P.shape and name != "float_island":
			var st: Transform3D = xf * Transform3D(Basis(), Vector3(0, P.h * 0.5, 0)) if P.cyl else xf
			PhysicsServer3D.body_add_shape(_new_body(1), P.shape.get_rid(), st)

# ------------------------------------------------------------------ portões
func _add_trigger(pos: Vector3, dir: Vector2, w: float, index: int) -> Area3D:
	var a := Area3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 140.0, 16.0)
	cs.shape = box
	a.add_child(cs)
	a.position = pos + Vector3(0, 40, 0)
	a.rotation.y = atan2(-dir.x, -dir.y)
	a.body_entered.connect(func(b):
		if b == player:
			if index < 0:
				finish_passed.emit()
			else:
				checkpoint_passed.emit(index))
	add_child(a)
	return a

func _place_checkpoints() -> void:
	var pylon := CylinderMesh.new()
	pylon.top_radius = 1.6
	pylon.bottom_radius = 2.4
	pylon.height = 44.0
	var pylon_mat := StandardMaterial3D.new()
	pylon_mat.albedo_color = Color("#3b3a40")
	pylon.material = pylon_mat
	var light_mat := StandardMaterial3D.new()
	light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_mat.albedo_color = Color("#7ff6ff")
	light_mat.emission_enabled = true
	light_mat.emission = Color("#52f2ff")
	light_mat.emission_energy_multiplier = 3.0
	var col_mat := StandardMaterial3D.new()
	col_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	col_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	col_mat.albedo_color = Color(0.35, 0.95, 1.0, 0.35)
	col_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	col_mat.disable_fog = true
	for i in event.gates.size():
		var c: Dictionary = event.gates[i]
		var pos := Vector3(c.p[0], c.p[1], c.p[2])
		var dir := Vector2(c.dir[0], c.dir[1])
		var side := Vector3(-dir.y, 0, dir.x)
		var node := Node3D.new()
		add_child(node)
		var w := float(c.w) * 0.6 if float(c.w) >= 150.0 else float(c.w) - 20.0   # distância entre os dois pilares
		for sg in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = pylon
			mi.position = pos + side * sg * w * 0.5 + Vector3(0, 20, 0)
			mi.visibility_range_end = 3000.0
			node.add_child(mi)
			var lamp := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(4.0, 4.0, 4.0)
			bm.material = light_mat
			lamp.mesh = bm
			lamp.position = mi.position + Vector3(0, 23, 0)
			lamp.visibility_range_end = 3000.0
			node.add_child(lamp)
		var beam := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(w, 0.9, 0.9)
		bb.material = light_mat
		beam.mesh = bb
		beam.position = pos + Vector3(0, 43, 0)
		beam.rotation.y = atan2(-dir.x, -dir.y)
		beam.visibility_range_end = 3000.0
		node.add_child(beam)
		var lbl := Label3D.new()
		lbl.text = String(c.get("name", ""))
		lbl.font_size = 256
		lbl.pixel_size = 0.04
		lbl.outline_size = 32
		lbl.modulate = Color("#fff1d6")
		lbl.outline_modulate = Color("#2a1a10")
		lbl.position = pos + Vector3(0, 52, 0)
		lbl.rotation.y = beam.rotation.y
		lbl.visibility_range_end = 1200.0
		node.add_child(lbl)
		var column := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 9.0
		cm.bottom_radius = 9.0
		cm.height = 700.0
		cm.radial_segments = 12
		cm.material = col_mat
		column.mesh = cm
		column.position = pos + Vector3(0, 350, 0)
		column.visible = false
		node.add_child(column)
		_add_trigger(pos, dir, float(c.w), i)
		checkpoints.append({"pos": pos, "dir": dir, "w": c.w, "node": node, "column": column})

## Circuito: só o próximo portão tem a coluna de luz; os já passados desaparecem.
## Exploração (next_index < 0): todos os portões ficam, sem colunas.
func highlight(next_index: int, hide_passed := true) -> void:
	for i in checkpoints.size():
		checkpoints[i].column.visible = i == next_index
		checkpoints[i].node.visible = next_index < 0 or i >= next_index or not hide_passed

# ------------------------------------------------------------------ faixas de impulso (chevrons que brilham no chão)
func _place_pads() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plate := Color("#1d2a3a")
	st.set_color(plate)
	for v in [Vector3(-7, 0.15, -9), Vector3(7, 0.15, -9), Vector3(7, 0.15, 9), Vector3(-7, 0.15, -9), Vector3(7, 0.15, 9), Vector3(-7, 0.15, 9)]:
		st.add_vertex(v)
	for k in 3:   # três chevrons a apontar para a frente (-Z)
		var z0 := 5.0 - k * 6.0
		st.set_color(Color("#7ff6ff") if k != 1 else Color("#ffd36e"))
		for q in [[Vector3(-6, 0.3, z0), Vector3(0, 0.3, z0 - 4.5), Vector3(0, 0.3, z0 - 2.0)], [Vector3(-6, 0.3, z0), Vector3(0, 0.3, z0 - 2.0), Vector3(-6, 0.3, z0 + 2.5)],
				[Vector3(6, 0.3, z0), Vector3(0, 0.3, z0 - 2.0), Vector3(0, 0.3, z0 - 4.5)], [Vector3(6, 0.3, z0), Vector3(6, 0.3, z0 + 2.5), Vector3(0, 0.3, z0 - 2.0)]]:
			for v in q:
				st.add_vertex(v)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color("#3fe6ff")
	mat.emission_energy_multiplier = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mesh := st.commit()
	var xs: Array = []
	for pd in info.get("pads", []):
		var xf := Transform3D(Basis(Vector3.UP, float(pd[3])), Vector3(pd[0], float(pd[1]) + 0.1, pd[2]))
		xs.append(xf)
		var a := Area3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(16.0, 8.0, 20.0)
		cs.shape = box
		a.add_child(cs)
		a.transform = xf.translated_local(Vector3(0, 3, 0))
		a.body_entered.connect(func(b):
			if b == player:
				pad_hit.emit())
		add_child(a)
	if not xs.is_empty():
		_grouped(mesh, xs, CELL_GROUP, 1200.0)

# ------------------------------------------------------------------ vegetação densa (ficheiro binário veg.zst)
## 2 palavras de 32 bits por planta: x,z (meio metro) | y (1/64 m), tipo, rumo, escala.
const VEG_VIS := {"pine": 1100.0, "tree_acacia": 1100.0, "tree_acacia_b": 1000.0, "tree_giant": 2600.0, "palm": 1000.0,
	"cactus": 800.0, "bush": 420.0, "tree_mushroom": 1600.0, "dead_tree": 800.0, "fern": 320.0, "boulder_a": 700.0,
	"crystals_cyan": 900.0, "crystals_mag": 900.0}
const VEG_GROUP := 512.0
func _place_veg() -> void:
	var n := int(info.get("veg_count", 0))
	if n == 0 or not FileAccess.file_exists("res://assets/map/veg.zst"):
		return
	var types: Array = info.veg_types
	var raw := FileAccess.get_file_as_bytes("res://assets/map/veg.zst").decompress(n * 8, FileAccess.COMPRESSION_ZSTD)
	var words := raw.to_int32_array()
	var half := float(info.size) * 0.5
	var groups := {}          # Vector3i(tipo, gx, gz) -> [Transform3D]
	var bodies := {}          # Vector2i(gx, gz) -> RID (troncos)
	var shapes := []
	for ty in types:
		_prop(String(ty))
	for t in types.size():
		shapes.append(props[types[t]].shape)
	for i in n:
		var w0: int = words[i * 2]
		var w1: int = words[i * 2 + 1]
		var x := float(w0 & 0xFFFF) * 0.5 - half
		var z := float((w0 >> 16) & 0xFFFF) * 0.5 - half
		var y := float(w1 & 0xFFFF) / 64.0 - 100.0
		var t := (w1 >> 16) & 0xF
		var yaw := float((w1 >> 20) & 0x3F) / 64.0 * TAU
		var sc := 0.6 + float((w1 >> 26) & 0x3F) * 0.03
		var gx := floori(x / VEG_GROUP)
		var gz := floori(z / VEG_GROUP)
		var xf := _xf(Vector3(x, y, z), yaw, sc)
		groups.get_or_add(Vector3i(t, gx, gz), []).append(xf)
		var shp: Shape3D = shapes[t]
		if shp and props[types[t]].cyl and not (types[t] in RIDE_OVER):   # troncos são sólidos; arbustos, fetos e cristais não
			var key := Vector2i(gx, gz)
			if not bodies.has(key):
				bodies[key] = _new_body(1)
			PhysicsServer3D.body_add_shape(bodies[key], shp.get_rid(), xf * Transform3D(Basis(), Vector3(0, props[types[t]].h * 0.5, 0)))
	for key in groups:
		var name: String = types[key.x]
		_multimesh(props[name].mesh, groups[key], null, VEG_VIS.get(name, 900.0), name != "fern" and name != "bush")

# ------------------------------------------------------------------ balizas ao longo de cada caminho (cor = nível)
func _place_route_posts() -> void:
	var by_level := {}
	for sec in info.sections:
		for v in sec.variants:
			var route: Array = v.route
			var lvl := int(v.level)
			for k in range(2, route.size() - 1, 3):   # pontos para renascer / viajar
				var a: Array = route[k]
				var b: Array = route[k + 1]
				spawn_points.append([Vector3(a[0], a[1], a[2]), Vector2(b[0] - a[0], b[2] - a[2]).normalized(), lvl])
			var off := float(v.hw) + 4.0
			for k in range(8, route.size() - 8, 15):
				var a: Array = route[k]
				var b: Array = route[k + 1]
				var d := Vector2(b[0] - a[0], b[2] - a[2]).normalized()
				var side := Vector2(-d.y, d.x)
				for sg in [-1.0, 1.0]:
					var x: float = a[0] + side.x * sg * off
					var z: float = a[2] + side.y * sg * off
					var y: float = a[1] if lvl == 2 or lvl == 3 else terrain.height_at(x, z)
					if lvl == 0:
						off = minf(off, 15.0)   # dentro dos túneis as balizas ficam junto às paredes
						x = a[0] + side.x * sg * off
						z = a[2] + side.y * sg * off
						y = a[1]
					by_level.get_or_add(lvl, []).append(Transform3D(Basis(), Vector3(x, y + 2.0, z)))
	for lvl in by_level:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.4
		mesh.bottom_radius = 0.5
		mesh.height = 5.0
		mesh.radial_segments = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LEVEL_COLORS[lvl]
		mat.emission_enabled = true
		mat.emission = LEVEL_COLORS[lvl]
		mat.emission_energy_multiplier = 0.9 if lvl == 0 else 0.5
		mesh.material = mat
		_grouped(mesh, by_level[lvl], CELL_GROUP, 900.0)

## Ponto de caminho mais perto: em 3D (renascer depois de cair) ou só no plano, fora dos
## túneis (viajar para um sítio tocado no mapa).
func nearest_spawn(p: Vector3, flat := false) -> Array:
	var best: Array = []
	var bd := INF
	for s in spawn_points:
		var q: Vector3 = s[0]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if not flat:
			d += 9.0 * (q.y - p.y) * (q.y - p.y)
		if d < bd and not (flat and in_cave(q + Vector3(0, 2, 0))):
			bd = d
			best = s
	return best

## Zona do mundo (índice em info.zones) onde está o ponto.
func zone_at(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in info.zones.size():
		var c: Array = info.zones[i].c
		var d := maxf(absf(p.x - c[0]), absf(p.z - c[1]))
		if d < bd:
			bd = d
			best = i
	return best

# ------------------------------------------------------------------ aquecer os shaders (evita engasgos na 1ª vez que algo aparece)
func warmup(cam: Camera3D) -> void:
	_warm = Node3D.new()
	cam.add_child(_warm)
	var meshes: Array = []
	for name in props:
		if props[name].has("mesh"):
			meshes.append([props[name].mesh, rock_mat if name in ROCK_PROPS else null])
	var k := 0
	for m in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		if m[1]:
			mi.material_override = m[1]
		mi.position = Vector3((k % 8 - 4) * 0.02, (k / 8) * 0.02 - 0.05, -2.0)
		mi.scale = Vector3.ONE * 0.0005
		_warm.add_child(mi)
		k += 1
	_warm_frames = 4

func _process(_dt: float) -> void:
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0 and is_instance_valid(_warm):
			_warm.queue_free()
