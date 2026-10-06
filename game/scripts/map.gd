extends Node3D
## Coloca no mapa tudo o que vem do Blender (rochas, arcos, mesa com gruta, teto do
## desfiladeiro, portais) e os portões da corrida (checkpoints) lidos de map.json.

signal checkpoint_passed(index: int)
signal finish_passed

const CELL_GROUP := 512.0
const ROCK_PROPS := ["rock_spire_a", "rock_spire_b", "rock_spire_c", "boulder_a", "boulder_b", "mesa", "arch",
	"arch_giant", "arch_twin", "rock_ring", "rock_fin", "butte", "cave_mesa", "canyon_roof", "gate"]
const COLLIDE := {
	"rock_spire_a": "convex", "rock_spire_b": "convex", "rock_spire_c": "convex", "boulder_a": "convex",
	"boulder_b": "convex", "mesa": "trimesh", "arch": "trimesh", "arch_giant": "trimesh", "arch_twin": "trimesh",
	"rock_ring": "trimesh", "rock_fin": "convex", "butte": "convex", "cave_mesa": "trimesh", "canyon_roof": "trimesh",
	"gate": "trimesh",
}

var info: Dictionary
var props := {}
var rock_mat: ShaderMaterial
var rock_mat_dark: ShaderMaterial
var checkpoints: Array = []      # [{pos, dir, w, node, column}]
var player: Node3D
var cave_a := Vector2.ZERO
var cave_b := Vector2.ZERO
var roof_pos := Vector3.ZERO
var roof_dir := Vector2.ZERO

func setup(map_info: Dictionary, terrain: Node) -> void:
	info = map_info
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = preload("res://shaders/rock.gdshader")
	rock_mat_dark = rock_mat.duplicate()
	rock_mat_dark.set_shader_parameter("darken", 0.75)
	_place_props()
	_place_set_pieces()
	_place_checkpoints()
	_place_route_posts(terrain)

func _prop(name: String) -> Dictionary:
	if props.has(name):
		return props[name]
	var scene: PackedScene = load("res://assets/models/%s.glb" % name)
	var inst := scene.instantiate()
	var mesh: Mesh = _find_mesh(inst).mesh
	inst.free()
	var shape: Shape3D = null
	match COLLIDE.get(name, ""):
		"convex": shape = mesh.create_convex_shape(true, true)
		"trimesh": shape = mesh.create_trimesh_shape()
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).vertex_color_use_as_albedo = true
			(m as StandardMaterial3D).specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	props[name] = {"mesh": mesh, "shape": shape}
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
			cs.transform = t
			bodies[key].add_child(cs)
	for key in groups:
		for name in groups[key]:
			var xs: Array = groups[key][name]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = props[name].mesh
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if name in ROCK_PROPS:
				mmi.material_override = rock_mat
			mmi.visibility_range_end = 2600.0
			add_child(mmi)

func _place_static(name: String, pos: Vector3, yaw: float, s: float, mat: Material) -> void:
	var P := _prop(name)
	var mi := MeshInstance3D.new()
	mi.mesh = P.mesh
	mi.transform = _xf(pos, yaw, s)
	if mat:
		mi.material_override = mat
	if name in ["cave_mesa", "canyon_roof"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # teto faz sombra por dentro
	add_child(mi)
	if P.shape:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = P.shape
		b.transform = mi.transform
		b.add_child(cs)
		add_child(b)

func _place_set_pieces() -> void:
	var c: Dictionary = info.cave
	var fwd := Vector3(-sin(c.yaw), 0.0, -cos(c.yaw))
	var mid := Vector3(c.p[0], c.p[1], c.p[2])
	# a gruta foi modelada começando na origem e indo para a frente: recua meia gruta
	_place_static("cave_mesa", mid - fwd * c.len * 0.5, c.yaw, 1.0, rock_mat)
	cave_a = Vector2(mid.x, mid.z) - Vector2(fwd.x, fwd.z) * c.len * 0.5
	cave_b = Vector2(mid.x, mid.z) + Vector2(fwd.x, fwd.z) * c.len * 0.5
	var r: Dictionary = info.roof
	roof_pos = Vector3(r.p[0], r.p[1], r.p[2])
	roof_dir = Vector2(-sin(r.yaw), -cos(r.yaw))
	_place_static("canyon_roof", roof_pos - Vector3(roof_dir.x, 0, roof_dir.y) * 90.0, r.yaw, 1.0, rock_mat_dark)
	# portais de largada e chegada
	for spec in [[info.start, "LARGADA"], [info.finish, "META"]]:
		var d: Dictionary = spec[0]
		var pos := Vector3(d.p[0], d.p[1], d.p[2])
		var yaw := atan2(-d.dir[0], -d.dir[1])
		_place_static("gate", pos + Vector3(d.dir[0], 0, d.dir[1]) * (12.0 if spec[1] == "LARGADA" else 0.0), yaw, 3.6, null)
		var lbl := Label3D.new()
		lbl.text = spec[1]
		lbl.font_size = 512
		lbl.pixel_size = 0.02
		lbl.outline_size = 48
		lbl.modulate = Color("#ffd36e")
		lbl.outline_modulate = Color("#3a1d10")
		lbl.position = pos + Vector3(d.dir[0], 0, d.dir[1]) * (12.0 if spec[1] == "LARGADA" else 0.0) + Vector3(0, 52, 0)
		lbl.rotation.y = yaw
		add_child(lbl)
	var fin: Dictionary = info.finish
	_add_trigger(Vector3(fin.p[0], fin.p[1], fin.p[2]), Vector2(fin.dir[0], fin.dir[1]), 110.0, -1)

func in_cave(p: Vector3) -> bool:
	var ab := cave_b - cave_a
	var t := clampf(((p.x - cave_a.x) * ab.x + (p.z - cave_a.y) * ab.y) / ab.length_squared(), 0.0, 1.0)
	if Vector2(p.x, p.z).distance_to(cave_a + ab * t) < 16.0 and t > 0.0 and t < 1.0:
		return true
	var rel := Vector2(p.x - roof_pos.x, p.z - roof_pos.z)
	return absf(rel.dot(roof_dir)) < 90.0 and absf(rel.dot(Vector2(-roof_dir.y, roof_dir.x))) < 40.0

# ------------------------------------------------------------------ portões
func _add_trigger(pos: Vector3, dir: Vector2, w: float, index: int) -> Area3D:
	var a := Area3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 80.0, 14.0)
	cs.shape = box
	a.add_child(cs)
	a.position = pos + Vector3(0, 30, 0)
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
	pylon.top_radius = 1.1
	pylon.bottom_radius = 1.6
	pylon.height = 34.0
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
		for sg in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = pylon
			mi.position = pos + side * sg * c.w * 0.5 + Vector3(0, 15, 0)
			node.add_child(mi)
			var lamp := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.6, 2.6, 2.6)
			bm.material = light_mat
			lamp.mesh = bm
			lamp.position = mi.position + Vector3(0, 18, 0)
			node.add_child(lamp)
		var beam := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(c.w, 0.6, 0.6)
		bb.material = light_mat
		beam.mesh = bb
		beam.position = pos + Vector3(0, 33, 0)
		beam.rotation.y = atan2(-dir.x, -dir.y)
		node.add_child(beam)
		var column := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 6.0
		cm.bottom_radius = 6.0
		cm.height = 600.0
		cm.radial_segments = 12
		cm.material = col_mat
		column.mesh = cm
		column.position = pos + Vector3(0, 300, 0)
		column.visible = false
		node.add_child(column)
		_add_trigger(pos, dir, c.w + 20.0, i)
		checkpoints.append({"pos": pos, "dir": dir, "w": c.w, "node": node, "column": column})

func highlight(next_index: int) -> void:
	for i in checkpoints.size():
		checkpoints[i].column.visible = i == next_index
		checkpoints[i].node.visible = i >= next_index

# ------------------------------------------------------------------ balizas ao longo do percurso
func _place_route_posts(terrain: Node) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.45
	mesh.height = 5.0
	mesh.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ff8a3d")
	mat.emission_enabled = true
	mat.emission = Color("#ff6a1d")
	mat.emission_energy_multiplier = 0.6
	mesh.material = mat
	var xs: Array[Transform3D] = []
	var route: Array = info.route
	for k in range(0, route.size() - 1, 15):
		var a: Array = route[k]
		var b: Array = route[mini(k + 1, route.size() - 1)]
		var d := Vector2(b[0] - a[0], b[2] - a[2]).normalized()
		var side := Vector2(-d.y, d.x)
		for sg in [-1.0, 1.0]:
			var x: float = a[0] + side.x * sg * 34.0
			var z: float = a[2] + side.y * sg * 34.0
			var y: float = terrain.height_at(x, z)
			xs.append(Transform3D(Basis(), Vector3(x, y + 2.0, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 900.0
	add_child(mmi)
