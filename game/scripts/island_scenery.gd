extends Node3D
## Lugares construídos para a ilha: arcos solares, entrepostos e santuários.
## Cada conjunto é instanciado por material; as pistas ficam livres em todas as variantes.
## As bandeiras e aves são animadas na GPU, sem trabalho por frame em GDScript.

const ROUTE_CELL := 256.0
const SITE_RADIUS := 125.0
const SITE_SPECS := [
	[0, 0.12, "Porto do Sol", "port"],
	[3, 0.45, "Anel dos Ventos", "ring"],
	[5, 0.50, "Observatório das Águias", "needles"],
	[7, 0.40, "Farol das Marés", "beacon"],
	[9, 0.40, "Entreposto da Lagoa", "port"],
	[12, 0.40, "Mercado da Savana", "port"],
	[16, 0.35, "Santuário do Cenote", "ring"],
	[18, 0.55, "Jardim das Agulhas", "needles"],
	[20, 0.40, "Relógio das Dunas", "ring"],
	[24, 0.40, "Porto do Oásis", "port"],
	[26, 0.50, "Coroa de Cristal", "needles"],
	[30, 0.50, "Vigia da Floresta", "beacon"],
]

var sites: Array[Dictionary] = []
var _terrain: Node
var _info: Dictionary
var _routes: Dictionary = {}
var _batches: Dictionary = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _shapes: Array[Shape3D] = []
var _bodies: Array[RID] = []
var _site_origin := Vector3.ZERO
var _site_yaw := 0.0
var _body: RID
var _stone := Color("ba875d")
var _accent := Color("58c7c1")

func setup(info: Dictionary, terrain: Node) -> void:
	_info = info
	_terrain = terrain
	_make_resources()
	_index_routes()
	for spec in SITE_SPECS:
		if int(spec[0]) >= info.sections.size():
			continue
		var section: Dictionary = info.sections[int(spec[0])]
		var site := _find_site(section.variants[0], float(spec[1]))
		if site.is_empty():
			continue
		_site_origin = site.position
		_site_yaw = site.yaw
		_palette(str(section.biome))
		_body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(_body, 1)
		PhysicsServer3D.body_set_collision_mask(_body, 0)
		PhysicsServer3D.body_set_space(_body, get_world_3d().space)
		_bodies.append(_body)
		match str(spec[3]):
			"port": _port()
			"ring": _sanctuary()
			"needles": _needles()
			"beacon": _beacon()
		_flush_batches(str(spec[2]))
		_birds(sites.size())
		sites.append({"name": spec[2], "position": _site_origin, "kind": spec[3]})
	set_meta("landmarks", sites)
	print("ilha: %d conjuntos de monumentos e entrepostos" % sites.size())

func _exit_tree() -> void:
	for body in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()

func _make_resources() -> void:
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 0.92
	var weathered_stone := ShaderMaterial.new()
	weathered_stone.shader = preload("res://shaders/island_stone.gdshader")
	_terrain.apply_biome(weathered_stone, _info)
	_materials.stone = weathered_stone
	var metal := stone.duplicate() as StandardMaterial3D
	metal.metallic = 0.52
	metal.roughness = 0.46
	_materials.metal = metal
	var glow := stone.duplicate() as StandardMaterial3D
	glow.emission_enabled = true
	glow.emission = Color("6fe2d4")
	glow.emission_energy_multiplier = 0.65
	_materials.glow = glow
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://shaders/island_fabric.gdshader")
	_materials.fabric = fabric
	var bird := ShaderMaterial.new()
	bird.shader = preload("res://shaders/island_birds.gdshader")
	_materials.bird = bird
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_meshes.box = cube
	var column := CylinderMesh.new()
	column.top_radius = 0.5
	column.bottom_radius = 0.5
	column.height = 1.0
	column.radial_segments = 12
	_meshes.column = column
	var taper := CylinderMesh.new()
	taper.top_radius = 0.24
	taper.bottom_radius = 0.5
	taper.height = 1.0
	taper.radial_segments = 6
	_meshes.taper = taper
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 1.0
	dome.radial_segments = 16
	dome.rings = 8
	_meshes.dome = dome
	_meshes.ring = _ring_mesh()
	_meshes.trim = _ring_mesh(0.927, 0.952, 0.096)
	_meshes.fabric = _triangle_mesh(false)
	_meshes.bird = _triangle_mesh(true)

func _triangle_mesh(bird: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]
	if bird:
		# Duas asas triangulares; as pontas articulam-se no shader.
		points = [Vector3(0, 0, -0.7), Vector3(-2.8, 0, 0.3), Vector3(0, 0, 0.7),
			Vector3(0, 0, -0.7), Vector3(0, 0, 0.7), Vector3(2.8, 0, 0.3)]
	else:
		points = [Vector3(-0.5, 0, 0), Vector3(0.1, -1.0, 0), Vector3(0.5, 0, 0)]
	for p in points:
		st.set_normal(Vector3.UP if bird else Vector3.BACK)
		st.set_uv(Vector2(p.x + 0.5, maxf(0.0, -p.y)))
		st.add_vertex(p)
	return st.commit()

func _ring_mesh(inner := 0.89, outer := 1.0, depth := 0.095) -> ArrayMesh:
	# Arco de 300 graus, secção retangular chanfrada pela luz. A abertura é deliberada.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 40:
		var a := deg_to_rad(-60.0 + float(i) * 7.5)
		var b := a + deg_to_rad(7.5)
		var corners: Array[Vector3] = []
		for angle in [a, b]:
			for edge in [Vector2(inner, -depth), Vector2(outer, -depth), Vector2(outer, depth), Vector2(inner, depth)]:
				corners.append(Vector3(cos(angle) * edge.x, sin(angle) * edge.x, edge.y))
		var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
		if i == 0:
			faces.append([3, 2, 1, 0])
		if i == 39:
			faces.append([4, 5, 6, 7])
		for face in faces:
			for index in [face[0], face[1], face[2], face[0], face[2], face[3]]:
				st.add_vertex(corners[index])
	st.generate_normals()
	return st.commit()

func _index_routes() -> void:
	for section in _info.sections:
		for variant in section.variants:
			_index_route(variant.route, float(variant.hw))
	for event in _info.get("events", []):
		_index_route(event.get("route", []), 42.0)

func _index_route(route: Array, half_width: float) -> void:
	# Segments every 8 samples, including the final endpoint. Distance is to segments,
	# so a long straight or a hairpin cannot slip between sparse point checks.
	for i in range(0, route.size() - 1, 8):
		var end := mini(i + 8, route.size() - 1)
		var a := Vector2(float(route[i][0]), float(route[i][2]))
		var b := Vector2(float(route[end][0]), float(route[end][2]))
		var low := (a.min(b) - Vector2.ONE * half_width) / ROUTE_CELL
		var high := (a.max(b) + Vector2.ONE * half_width) / ROUTE_CELL
		for z in range(floori(low.y), floori(high.y) + 1):
			for x in range(floori(low.x), floori(high.x) + 1):
				_routes.get_or_add(Vector2i(x, z), []).append([a, b, half_width])

func _clear_of_routes(p: Vector2, radius: float) -> bool:
	var low := (p - Vector2.ONE * radius) / ROUTE_CELL
	var high := (p + Vector2.ONE * radius) / ROUTE_CELL
	for z in range(floori(low.y), floori(high.y) + 1):
		for x in range(floori(low.x), floori(high.x) + 1):
			for seg in _routes.get(Vector2i(x, z), []):
				var closest := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
				if p.distance_to(closest) < radius + float(seg[2]) + 20.0:
					return false
	return true

func _find_site(variant: Dictionary, fraction: float) -> Dictionary:
	var route: Array = variant.route
	var best: Dictionary = {}
	var best_score := INF
	var sea := float(_info.get("ocean", {}).get("y", _info.get("water_y", 0.0)))
	var half := float(_info.size) * 0.5 - SITE_RADIUS - 30.0
	for shift in [0.0, 0.07, -0.07, 0.14, -0.14]:
		var index := clampi(int((fraction + float(shift)) * route.size()), 1, route.size() - 2)
		var p := Vector2(route[index][0], route[index][2])
		var next := Vector2(route[index + 1][0], route[index + 1][2])
		var direction := (next - p).normalized()
		var side := Vector2(-direction.y, direction.x)
		for offset in [220.0, -220.0, 310.0, -310.0, 410.0, -410.0]:
			var q := p + side * float(offset)
			if absf(q.x) > half or absf(q.y) > half or not _clear_of_routes(q, SITE_RADIUS):
				continue
			var center_h: float = _terrain.height_at(q.x, q.y)
			var min_h := center_h
			var max_h := center_h
			for i in 8:
				var sample := q + Vector2.from_angle(float(i) * TAU / 8.0) * SITE_RADIUS
				var h: float = _terrain.height_at(sample.x, sample.y)
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
			if min_h < sea + 3.0 or max_h - min_h > 60.0:
				continue
			var score := (max_h - min_h) * 2.0 + absf(float(offset)) * 0.07 + absf(float(shift)) * 100.0
			if score < best_score:
				best_score = score
				best = {"position": Vector3(q.x, center_h, q.y), "yaw": atan2(direction.x, direction.y)}
	return best

func _palette(biome: String) -> void:
	_stone = Color("ba875d")
	_accent = Color("4db9bf")
	if biome in ["coast", "lagoon", "salt", "oasis"]:
		_stone = Color("c6c9bc")
		_accent = Color("288f9d")
	elif biome in ["jungle", "forest", "meadow", "savanna"]:
		_stone = Color("8c9b86")
		_accent = Color("d88448")
	elif biome in ["peaks", "massif", "crystals"]:
		_stone = Color("626f80")
		_accent = Color("72c6d2")
	elif biome == "red":
		_stone = Color("b37962")

func _ground(local: Vector3) -> Vector3:
	var p := _site_origin + Basis(Vector3.UP, _site_yaw) * local
	return Vector3(local.x, float(_terrain.height_at(p.x, p.z)) - _site_origin.y + local.y, local.z)

func _part(kind: String, at: Vector3, size: Vector3, color: Color, material := "stone", collide := true, rotation := Vector3.ZERO) -> void:
	var local_basis := Basis.from_euler(rotation)
	var site_basis := Basis(Vector3.UP, _site_yaw)
	var world := Transform3D(site_basis * local_basis.scaled(size), _site_origin + site_basis * at)
	var key := kind + ":" + material
	_batches.get_or_add(key, []).append([world, color])
	if not collide:
		return
	var shape: Shape3D
	# Ring collision is added separately: its opening must remain usable.
	if kind == "column" or kind == "taper":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf(size.x, size.z) * 0.5
		cylinder.height = size.y
		shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape = box
	_shapes.append(shape)
	var body_xf := Transform3D(site_basis * local_basis, world.origin)
	PhysicsServer3D.body_add_shape(_body, shape.get_rid(), body_xf)

func _foundation(at: Vector3, width: float, depth: float, top: float) -> void:
	# Sink supports below the lowest corner instead of floating on uneven terrain.
	var base := _ground(at).y
	for dx in [-width * 0.5, width * 0.5]:
		for dz in [-depth * 0.5, depth * 0.5]:
			base = minf(base, _ground(at + Vector3(dx, 0, dz)).y)
	var height := maxf(3.0, top - base + 2.0)
	_part("box", Vector3(at.x, top - height * 0.5, at.z), Vector3(width, height, depth), _stone.darkened(0.19))

func _ring(at: Vector3, radius: float, tilt := 0.0) -> void:
	_part("ring", at, Vector3.ONE * radius, _stone.lightened(0.1), "stone", false, Vector3(0, 0, tilt))
	# Twenty simple boxes follow the stone, leaving both the central opening and break clear.
	for i in 20:
		var angle := deg_to_rad(-52.5 + float(i) * 15.0) + tilt
		var offset := Vector3(cos(angle), sin(angle), 0) * radius * 0.945
		var shape := BoxShape3D.new()
		shape.size = Vector3(radius * 0.12, radius * 0.25, radius * 0.19)
		_shapes.append(shape)
		var basis := Basis(Vector3.UP, _site_yaw)
		var xf := Transform3D(basis * Basis(Vector3.FORWARD, -angle), _site_origin + basis * (at + offset))
		PhysicsServer3D.body_add_shape(_body, shape.get_rid(), xf)
	_part("trim", at, Vector3.ONE * radius, _accent, "metal", false, Vector3(0, 0, tilt))

func _building(at: Vector3, width: float, height: float, yaw: float) -> void:
	var g := _ground(at)
	_foundation(at, width + 3.0, width + 3.0, g.y + 1.0)
	_part("column", g + Vector3(0, height * 0.5, 0), Vector3(width, height, width), _stone.lightened(0.12))
	_part("dome", g + Vector3(0, height, 0), Vector3(width * 1.06, width * 0.57, width * 1.06), _stone.lightened(0.24), "stone", false)
	# Roof collision encloses the decorative dome without introducing sharp box corners.
	var dome_shape := SphereShape3D.new()
	dome_shape.radius = width * 0.5
	_shapes.append(dome_shape)
	var site_basis := Basis(Vector3.UP, _site_yaw)
	var roof_xf := Transform3D(site_basis.scaled(Vector3(1, 0.57, 1)), _site_origin + site_basis * (g + Vector3(0, height, 0)))
	PhysicsServer3D.body_add_shape(_body, dome_shape.get_rid(), roof_xf)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	_part("box", g + forward * (width * 0.493) + Vector3(0, height * 0.38, 0), Vector3(width * 0.21, height * 0.70, 0.7), Color("293e43"), "metal", false, Vector3(0, yaw, 0))
	_part("box", g + forward * (width * 0.52) + Vector3(0, height * 0.76, 0), Vector3(width * 0.32, 0.8, 2.5), _accent, "metal", false, Vector3(0, yaw, 0))

func _flag(at: Vector3, height: float, width: float) -> void:
	var g := _ground(at)
	_part("column", g + Vector3(0, height * 0.5, 0), Vector3(0.6, height, 0.6), _stone.darkened(0.4), "metal")
	_part("box", g + Vector3(width * 0.5, height, 0), Vector3(width + 0.5, 0.4, 0.4), _stone.darkened(0.4), "metal", false)
	_part("fabric", g + Vector3(width * 0.5, height - 0.4, 0), Vector3(width, height * 0.55, width), _accent, "fabric", false)

func _port() -> void:
	var g := _ground(Vector3(0, 0, 25))
	_foundation(Vector3(0, 0, 25), 53, 28, g.y + 5)
	for x in [-24.0, 24.0]:
		_part("taper", g + Vector3(x, 21, 0), Vector3(13, 48, 17), _stone)
	_ring(g + Vector3(0, 73, 0), 53, -0.16)
	# Low buildings gather around a clear forecourt, stepping down the land.
	for spec in [[-66, -24, 22, 13], [-42, -60, 29, 16], [3, -72, 24, 12], [45, -53, 32, 18], [74, -15, 20, 12], [64, 31, 25, 15]]:
		var at := Vector3(float(spec[0]), 0, float(spec[1]))
		_building(at, float(spec[2]), float(spec[3]), atan2(-at.x, -at.z))
	for at in [Vector3(-39, 0, -12), Vector3(40, 0, 3), Vector3(-13, 0, -45)]:
		_flag(at, 23, 11)

func _sanctuary() -> void:
	var g := _ground(Vector3.ZERO)
	_foundation(Vector3.ZERO, 56, 34, g.y + 7)
	_part("box", g + Vector3(0, 9, 0), Vector3(46, 4, 30), _stone.lightened(0.14))
	for x in [-29.0, 29.0]:
		_part("taper", g + Vector3(x, 28, 0), Vector3(17, 61, 19), _stone)
	_ring(g + Vector3(0, 88, 0), 68, 0.19)
	# Broken processional arc, with progressively shorter columns toward the gap.
	for i in 8:
		var angle := -2.5 + float(i) * 0.58
		var at := Vector3(cos(angle) * 84, 0, sin(angle) * 71)
		var base := _ground(at)
		var h := 18.0 + float((i * 7) % 17)
		_foundation(at, 13, 13, base.y + 2)
		_part("taper", base + Vector3(0, h * 0.5, 0), Vector3(9, h, 9), _stone.darkened(float(i % 3) * 0.07))
		_part("box", base + Vector3(0, h, 0), Vector3(13, 2.0, 13), _stone.lightened(0.12))
		if i % 2 == 0:
			_part("box", base + Vector3(0, h - 5, -4.7), Vector3(1.4, 6, 0.4), _accent, "glow", false)
	for i in 5:
		var at := _ground(Vector3(-59 + i * 13, 0, -56 - (i % 2) * 11))
		_part("box", at + Vector3(0, 3, 0), Vector3(11, 6, 8), _stone.darkened(0.1), "stone", true, Vector3(0.1, i * 0.7, 0.12))

func _needles() -> void:
	for spec in [[0, 0, 119, 20], [-36, 14, 82, 15], [32, 29, 66, 17], [-60, -22, 41, 12], [52, -24, 49, 11]]:
		var at := Vector3(float(spec[0]), 0, float(spec[1]))
		var g := _ground(at)
		var h := float(spec[2])
		var w := float(spec[3])
		_foundation(at, w * 1.8, w * 1.8, g.y + 4)
		_part("taper", g + Vector3(0, h * 0.5, 0), Vector3(w, h, w), _stone)
		_part("taper", g + Vector3(0, h + 4, 0), Vector3(w * 0.55, 19, w * 0.55), _accent, "metal")
		_part("box", g + Vector3(0, h * 0.54, -w * 0.34), Vector3(1.8, h * 0.52, 0.8), _accent, "glow", false)
	for i in 6:
		var angle := float(i) * TAU / 6.0
		var at := _ground(Vector3(cos(angle) * 81, 0, sin(angle) * 74))
		_part("column", at + Vector3(0, 3, 0), Vector3(11, 6, 11), _stone.darkened(0.15))
		_part("dome", at + Vector3(0, 7, 0), Vector3(6, 5, 6), _accent, "metal", false)

func _beacon() -> void:
	var g := _ground(Vector3.ZERO)
	_foundation(Vector3.ZERO, 44, 44, g.y + 7)
	_part("taper", g + Vector3(0, 48, 0), Vector3(26, 91, 26), _stone.lightened(0.12))
	for y in [25.0, 62.0, 92.0]:
		_part("column", g + Vector3(0, y, 0), Vector3(29 - y * 0.09, 3.0, 29 - y * 0.09), _accent, "metal")
	for x in [-8.0, 8.0]:
		_part("box", g + Vector3(x, 108, 0), Vector3(5, 30, 9), _stone)
	_part("dome", g + Vector3(0, 111, 0), Vector3(8, 17, 8), _accent, "glow", false)
	_part("box", g + Vector3(0, 124, 0), Vector3(23, 4, 14), _stone)
	_building(Vector3(-54, 0, 28), 28, 18, 1.0)
	_building(Vector3(41, 0, 39), 21, 13, -1.0)
	_flag(Vector3(-32, 0, -21), 29, 13)
	_flag(Vector3(31, 0, -38), 21, 10)

func _flush_batches(label: String) -> void:
	for key in _batches:
		var parts: Array = _batches[key]
		var split: PackedStringArray = str(key).split(":")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes[split[0]]
		mm.instance_count = parts.size()
		for i in parts.size():
			var xf: Transform3D = parts[i][0]
			xf.origin -= _site_origin
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, parts[i][1])
		var instance := MultiMeshInstance3D.new()
		instance.name = label + " " + str(key)
		instance.position = _site_origin
		instance.multimesh = mm
		instance.material_override = _materials[split[1]]
		instance.visibility_range_end = 4300.0 if split[1] != "fabric" else 1300.0
		instance.visibility_range_end_margin = 120.0
		if split[1] in ["fabric", "glow"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if split[1] == "fabric":
			instance.extra_cull_margin = 5.0
		add_child(instance)
	_batches.clear()

func _birds(seed_index: int) -> void:
	if seed_index % 2 != 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _meshes.bird
	mm.instance_count = 9
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(float(i) / 9.0, float(i % 4) / 4.0, float(i % 3) / 3.0, float(seed_index) * 0.07))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Aves costeiras"
	instance.multimesh = mm
	instance.material_override = _materials.bird
	instance.position = _site_origin + Vector3(0, 174, 0)
	instance.custom_aabb = AABB(Vector3(-190, -25, -190), Vector3(380, 65, 380))
	instance.visibility_range_end = 2100.0
	instance.visibility_range_end_margin = 120.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
