extends Node3D
## Coloca no mapa tudo o que vem do Blender e de map.json: rochas, árvores, ruínas, túneis,
## pontes, aqueduto, teto da fenda, lago com água, ilhas flutuantes, relva, bandeirolas,
## e os portões da corrida (checkpoints) com as balizas de cada caminho.

signal checkpoint_passed(index: int)
signal finish_passed

const CELL_GROUP := 512.0
const ROCK_PROPS := ["rock_spire_a", "rock_spire_b", "rock_spire_c", "boulder_a", "boulder_b", "mesa", "arch",
	"arch_giant", "arch_twin", "rock_ring", "rock_fin", "butte", "canyon_roof"]
# forma de colisão de cada peça: convexa, malha exata, ou cilindro [raio, altura] (troncos, colunas)
const COLLIDE := {
	"rock_spire_a": "convex", "rock_spire_b": "convex", "rock_spire_c": "convex", "boulder_a": "convex",
	"boulder_b": "convex", "mesa": "trimesh", "arch": "trimesh", "arch_giant": "trimesh", "arch_twin": "trimesh",
	"rock_ring": "trimesh", "rock_fin": "convex", "butte": "convex", "pillar": [1.3, 13.0], "tower_pod": "convex",
	"tree_acacia": [0.6, 6.0], "tree_acacia_b": [0.5, 5.0], "tree_mushroom": [1.1, 12.0],
	"crystals_cyan": [2.2, 4.0], "crystals_mag": [2.2, 4.0], "ruin_column": [1.6, 12.0], "ruin_wall": "trimesh",
	"ruin_tower": [9.5, 70.0],
}
const VIS_RANGE := {"butte": 4200.0, "mesa": 3400.0, "arch_giant": 3400.0, "arch_twin": 2800.0, "rock_ring": 2600.0,
	"rock_fin": 3000.0, "ruin_tower": 4200.0, "arch": 2400.0, "rock_spire_c": 2600.0, "rock_spire_a": 2200.0,
	"tower_pod": 1800.0}
const LEVEL_COLORS := {0: Color("#52f2ff"), 1: Color("#ff8a3d"), 2: Color("#ffd23d"), 3: Color("#ffffff")}

var info: Dictionary
var terrain: Node
var props := {}
var rock_mat: ShaderMaterial
var rock_mat_dark: ShaderMaterial
var checkpoints: Array = []      # [{pos, dir, w, node, column}]
var player: Node3D
var tunnel_boxes: Array = []     # [{origin, fwd, len, floor, top}]
var roof_pos := Vector3.ZERO
var roof_dir := Vector2.ZERO
var _warm: Node3D
var _warm_frames := 0

func setup(map_info: Dictionary, t: Node) -> void:
	info = map_info
	terrain = t
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = preload("res://shaders/rock.gdshader")
	terrain.apply_biome(rock_mat, info)
	rock_mat_dark = rock_mat.duplicate()
	rock_mat_dark.set_shader_parameter("darken", 0.75)
	_place_props()
	_place_set_pieces()
	_place_water()
	_place_islands()
	_place_grass()
	_place_banners()
	_place_checkpoints()
	_place_route_posts()

# ------------------------------------------------------------------ peças do Blender
func _prop(name: String) -> Dictionary:
	if props.has(name):
		return props[name]
	var scene: PackedScene = load("res://assets/models/%s.glb" % name)
	var inst := scene.instantiate()
	var mesh: Mesh = _find_mesh(inst).mesh
	inst.free()
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
			(m as StandardMaterial3D).specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	props[name] = {"mesh": mesh, "shape": shape, "cyl": c is Array}
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

func _shape_xf(name: String, t: Transform3D) -> Transform3D:
	# cilindros: centro a meia altura (o modelo nasce no chão)
	if props[name].cyl:
		var c: Array = COLLIDE[name]
		return t * Transform3D(Basis(), Vector3(0, c[1] * 0.5, 0))
	return t

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
			if not bodies.has(key):
				var b := StaticBody3D.new()
				add_child(b)
				bodies[key] = b
			var cs := CollisionShape3D.new()
			cs.shape = P.shape
			cs.transform = _shape_xf(name, t)
			bodies[key].add_child(cs)
	for key in groups:
		for name in groups[key]:
			_multimesh(props[name].mesh, groups[key][name], rock_mat if name in ROCK_PROPS else null,
				VIS_RANGE.get(name, 1500.0), true)

func _multimesh(mesh: Mesh, xs: Array, mat: Material, vis: float, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.visibility_range_end = vis
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func _place_static(name: String, xf: Transform3D, mat: Material, double_shadow := false) -> MeshInstance3D:
	var P := _prop(name)
	var mi := MeshInstance3D.new()
	mi.mesh = P.mesh
	mi.transform = xf
	if mat:
		mi.material_override = mat
	if double_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # tetos fazem sombra por dentro
	add_child(mi)
	var shape: Shape3D = P.shape if P.shape else P.mesh.create_trimesh_shape()
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.transform = xf
	b.add_child(cs)
	add_child(b)
	return mi

func _place_set_pieces() -> void:
	# túneis (feitos à medida no Blender)
	for t in info.tunnels:
		var pos := Vector3(t.p[0], t.p[1], t.p[2])
		_place_static(t.name, Transform3D(Basis(Vector3.UP, t.yaw), pos), rock_mat, true)
		var fwd := Vector3(-sin(t.yaw), 0.0, -cos(t.yaw))
		tunnel_boxes.append({"origin": pos, "fwd": fwd, "len": float(t.len), "floor": pos.y, "top": pos.y + float(t.height)})
	# pontes de pedra
	for b in info.bridges:
		_place_static(b.name, Transform3D(Basis(Vector3.UP, b.yaw), Vector3(b.p[0], b.p[1], b.p[2])), rock_mat)
	# aqueduto (troços de 40 m, com uma falha para saltar)
	for a in info.aqueducts:
		var P := _prop("aqueduct_seg")
		var seg_shape: Shape3D = P.mesh.create_trimesh_shape()
		var fwd := Vector3(-sin(a.yaw), 0.0, -cos(a.yaw))
		var xs: Array = []
		var body := StaticBody3D.new()
		add_child(body)
		for i in int(a.n):
			if i in a.missing:
				continue
			var xf := Transform3D(Basis(Vector3.UP, a.yaw), Vector3(a.p[0], a.p[1], a.p[2]) + fwd * (i * float(a.seg)))
			xs.append(xf)
			var cs := CollisionShape3D.new()
			cs.shape = seg_shape
			cs.transform = xf
			body.add_child(cs)
		_multimesh(P.mesh, xs, null, 3400.0, true)
	# teto de pedra sobre a fenda vermelha (vira caverna)
	var r: Dictionary = info.roof
	roof_pos = Vector3(r.p[0], r.p[1], r.p[2])
	roof_dir = Vector2(-sin(r.yaw), -cos(r.yaw))
	_place_static("canyon_roof", _xf(roof_pos - Vector3(roof_dir.x, 0, roof_dir.y) * 90.0, r.yaw, 1.0), rock_mat_dark, true)
	# portais de largada e chegada (arco largo por cima da estrada)
	for spec in [[info.start, "LARGADA", 30.0], [info.finish, "META", 0.0]]:
		var d: Dictionary = spec[0]
		var dir := Vector3(d.dir[0], 0, d.dir[1])
		var pos := Vector3(d.p[0], d.p[1], d.p[2]) + dir * float(spec[2])
		var yaw := atan2(-d.dir[0], -d.dir[1])
		var gm := MeshInstance3D.new()
		gm.mesh = _prop("gate").mesh
		gm.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(7.6, 3.6, 3.6)), pos)
		add_child(gm)
		var gb := StaticBody3D.new()
		add_child(gb)
		var side := Vector3(-dir.z, 0, dir.x)
		for sg in [-1.0, 1.0]:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 6.0
			cyl.height = 40.0
			cs.shape = cyl
			cs.position = pos + side * sg * 47.0 + Vector3(0, 20, 0)
			gb.add_child(cs)
		var lbl := Label3D.new()
		lbl.text = spec[1]
		lbl.font_size = 512
		lbl.pixel_size = 0.03
		lbl.outline_size = 48
		lbl.modulate = Color("#ffd36e")
		lbl.outline_modulate = Color("#3a1d10")
		lbl.position = pos + Vector3(0, 58, 0)
		lbl.rotation.y = yaw
		add_child(lbl)
	var fin: Dictionary = info.finish
	_add_trigger(Vector3(fin.p[0], fin.p[1], fin.p[2]), Vector2(fin.dir[0], fin.dir[1]), float(fin.w), -1)

## Dentro de um túnel ou debaixo do teto de pedra (eco no som, luz mais baixa).
func in_cave(p: Vector3) -> bool:
	for t in tunnel_boxes:
		var rel: Vector3 = p - t.origin
		var a: float = rel.dot(t.fwd)
		if a > 0.0 and a < t.len and p.y < t.floor + 16.0:
			var side := Vector3(-t.fwd.z, 0, t.fwd.x)
			if absf(rel.dot(side)) < 19.0:
				return true
	var rel2 := Vector2(p.x - roof_pos.x, p.z - roof_pos.z)
	return absf(rel2.dot(roof_dir)) < 90.0 and absf(rel2.dot(Vector2(-roof_dir.y, roof_dir.x))) < 40.0 and p.y < roof_pos.y + 24.0

# ------------------------------------------------------------------ água, ilhas, relva, bandeirolas
func _place_water() -> void:
	var wmat := ShaderMaterial.new()
	wmat.shader = preload("res://shaders/water.gdshader")
	for lk in info.lakes:
		var r := float(lk.r)
		var pm := PlaneMesh.new()
		pm.size = Vector2(r * 2.0, r * 2.0)
		pm.subdivide_width = 8
		pm.subdivide_depth = 8
		pm.material = wmat
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.position = Vector3(lk.c[0], float(lk.y), lk.c[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# superfície "dura": o veículo flutua sobre a água
		var body := StaticBody3D.new()
		body.set_meta("water", true)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r * 2.0, 2.0, r * 2.0)
		cs.shape = box
		cs.position = Vector3(lk.c[0], float(lk.y) - 1.0, lk.c[1])
		body.add_child(cs)
		add_child(body)

func _place_islands() -> void:
	var xs: Array = []
	for i in info.islands:
		xs.append(_xf(Vector3(i[0], i[1], i[2]), i[3], i[4]))
	var mmi := _multimesh(_prop("float_island").mesh, xs, null, 6000.0, false)
	mmi.extra_cull_margin = 50.0

func _place_grass() -> void:
	var groups := {}
	for g in info.grass:
		var key := Vector2i(floori(g[0] / CELL_GROUP), floori(g[2] / CELL_GROUP))
		groups.get_or_add(key, []).append(_xf(Vector3(g[0], g[1], g[2]), g[3], g[4]))
	var mesh: Mesh = _prop("grass_tuft").mesh
	for key in groups:
		var mmi := _multimesh(mesh, groups[key], null, 320.0, false)
		mmi.visibility_range_end_margin = 40.0

func _place_banners() -> void:
	# bandeirolas penduradas entre dois postes, por cima da estrada (como nas imagens)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var colors := [Color("#e5483a"), Color("#ffd23d"), Color("#3fb6e6"), Color("#f4eee2"), Color("#7ac25a")]
	for b in info.banners:
		var span := float(b[4])
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
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.transform = Transform3D(Basis(Vector3.UP, float(b[3])), Vector3(b[0], float(b[1]) - 0.5, b[2]))
		mi.visibility_range_end = 1600.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

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
	for i in info.checkpoints.size():
		var c: Dictionary = info.checkpoints[i]
		var pos := Vector3(c.p[0], c.p[1], c.p[2])
		var dir := Vector2(c.dir[0], c.dir[1])
		var side := Vector3(-dir.y, 0, dir.x)
		var node := Node3D.new()
		add_child(node)
		var w := float(c.w) * 0.6
		for sg in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = pylon
			mi.position = pos + side * sg * w * 0.5 + Vector3(0, 20, 0)
			node.add_child(mi)
			var lamp := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(4.0, 4.0, 4.0)
			bm.material = light_mat
			lamp.mesh = bm
			lamp.position = mi.position + Vector3(0, 23, 0)
			node.add_child(lamp)
		var beam := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(w, 0.9, 0.9)
		bb.material = light_mat
		beam.mesh = bb
		beam.position = pos + Vector3(0, 43, 0)
		beam.rotation.y = atan2(-dir.x, -dir.y)
		node.add_child(beam)
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

func highlight(next_index: int) -> void:
	for i in checkpoints.size():
		checkpoints[i].column.visible = i == next_index
		checkpoints[i].node.visible = i >= next_index

# ------------------------------------------------------------------ balizas ao longo de cada caminho (cor = nível)
func _place_route_posts() -> void:
	var by_level := {}
	for sec in info.sections:
		for v in sec.variants:
			var route: Array = v.route
			var lvl := int(v.level)
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
		_multimesh(mesh, by_level[lvl], null, 900.0, false)

# ------------------------------------------------------------------ aquecer os shaders (evita engasgos na 1ª vez que algo aparece)
func warmup(cam: Camera3D) -> void:
	_warm = Node3D.new()
	cam.add_child(_warm)
	var meshes: Array = []
	for name in props:
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
