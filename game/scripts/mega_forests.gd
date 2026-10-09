extends Node3D
## Additive, deterministic forests. The original map, routes and vegetation stay intact.
## Large canopies persist at every quality tier; only low undergrowth is reduced.

const GRID := 256.0
const CHUNK := 512.0
const ROAD_MARGIN := 75.0
const TREES_PER_GROVE := 120
const GROVE_RADIUS := 390.0

var _map: Node3D
var _terrain: Node
var _info: Dictionary
var _routes: Dictionary = {}
var _obstacles: Dictionary = {}
var _batches: Dictionary = {}
var _bodies: Dictionary = {}
var _shapes: Array[Shape3D] = []
var _ferns: Array[MultiMeshInstance3D] = []
var _canopies: Array[MultiMeshInstance3D] = []
var _quality := "balanced"
var _rng := RandomNumberGenerator.new()
var _groves: Array[Dictionary] = []
var _tree_count := 0
var _fern_count := 0

func setup(map: Node3D) -> void:
	_map = map
	_terrain = map.terrain
	_info = map.info
	_rng.seed = 841731
	_index_routes()
	_index_obstacles()
	for zone in _info.get("zones", []):
		if String(zone.biome) in ["forest", "jungle"]:
			_grow_zone(zone)
	_flush()
	set_quality(_quality)
	set_meta("groves", _groves)
	set_meta("tree_count", _tree_count)
	set_meta("fern_count", _fern_count)
	# Placement indices can be large; gameplay only retains batches and colliders.
	_routes.clear()
	_obstacles.clear()
	print("mega forests: %d groves, %d towering trees, %d ferns" % [_groves.size(), _tree_count, _fern_count])

func set_quality(tier: String) -> void:
	_quality = tier if tier in ["stable", "mobile", "balanced", "ultra"] else "balanced"
	for fern in _ferns:
		fern.multimesh.visible_instance_count = int(fern.multimesh.instance_count * (0.12 if _quality == "stable" else 0.25 if _quality == "mobile" else 0.6 if _quality == "balanced" else 1.0))
		fern.visibility_range_end = 420.0 if _quality == "stable" else 650.0 if _quality == "mobile" else 1100.0
	for canopy in _canopies:
		# Todos os troncos e copas persistem; o perfil estável limita a distância de sombra na luz.
		canopy.visibility_range_end = 3200.0 if _quality in ["stable", "mobile"] else 4800.0
		canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _quality == "mobile" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _exit_tree() -> void:
	for body in _bodies.values():
		PhysicsServer3D.free_rid(body)
	_bodies.clear()

func _xz(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[2]))

func _index_routes() -> void:
	for section in _info.get("sections", []):
		for variant in section.variants:
			_index_route(variant.route, float(variant.get("hw", 46.0)))
	for event in _info.get("events", []):
		_index_route(event.get("route", []), float(event.get("half_w", 46.0)))
		for gate in event.get("gates", []):
			_index_disk(_xz(gate.p), maxf(110.0, float(gate.get("w", 100.0)) * 0.5 + 65.0))
		for key in ["start", "finish"]:
			if not event.get(key, {}).is_empty():
				_index_disk(_xz(event[key].p), 160.0)
	for gate in _info.get("checkpoints", []):
		_index_disk(_xz(gate.p), float(gate.get("w", 200.0)) * 0.5 + 70.0)
	for key in ["start", "finish"]:
		if not _info.get(key, {}).is_empty():
			_index_disk(_xz(_info[key].p), 170.0)

func _index_route(route: Array, half_width: float) -> void:
	# Every original segment, including hairpins and final endpoints, is protected.
	var clearance := half_width + ROAD_MARGIN
	for i in range(route.size() - 1):
		var a := _xz(route[i])
		var b := _xz(route[i + 1])
		var low := (a.min(b) - Vector2.ONE * clearance) / GRID
		var high := (a.max(b) + Vector2.ONE * clearance) / GRID
		for z in range(floori(low.y), floori(high.y) + 1):
			for x in range(floori(low.x), floori(high.x) + 1):
				_routes.get_or_add(Vector2i(x, z), []).append([a, b, clearance])

func _index_disk(p: Vector2, radius: float) -> void:
	var low := (p - Vector2.ONE * radius) / GRID
	var high := (p + Vector2.ONE * radius) / GRID
	for z in range(floori(low.y), floori(high.y) + 1):
		for x in range(floori(low.x), floori(high.x) + 1):
			_obstacles.get_or_add(Vector2i(x, z), []).append([p, radius])

func _index_obstacles() -> void:
	# Mesh bounds cover authored monument footprints, including rotated structures.
	for collection in ["props", "colossi"]:
		for p in _info.get(collection, []):
			var prop: Dictionary = _map._prop(String(p[0]))
			var bounds: AABB = prop.mesh.get_aabb()
			var scale_factor := float(p[5])
			var center := bounds.get_center()
			var radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5 * scale_factor
			var offset := Vector2(center.x, center.z).rotated(-float(p[4])) * scale_factor
			_index_disk(Vector2(float(p[1]), float(p[3])) + offset, radius + 12.0)
	for collection in ["tunnels", "bridges", "aqueducts"]:
		for item in _info.get(collection, []):
			var a := _xz(item.p)
			var direction := Vector2(-sin(float(item.yaw)), -cos(float(item.yaw)))
			var length := float(item.get("len", float(item.get("n", 1)) * float(item.get("seg", 40.0))))
			var width := float(item.get("w", item.get("width", 100.0))) * 0.5 + 50.0
			for i in range(ceili(length / 60.0) + 1):
				_index_disk(a + direction * minf(float(i) * 60.0, length), width + 40.0)
	for roof in _info.get("roofs", []):
		_index_disk(_xz(roof.p), 190.0)
	for cave in _map.cave_boxes:
		var origin: Vector3 = cave.origin
		var direction: Vector3 = cave.fwd
		for i in range(ceili(float(cave.len) / 60.0) + 1):
			var p: Vector3 = origin + direction * minf(i * 60.0, float(cave.len))
			_index_disk(Vector2(p.x, p.z), float(cave.half_w) + 65.0)
	for child in _map.get_children():
		for landmark in child.get_meta("landmarks", []):
			var p: Vector3 = landmark.position
			_index_disk(Vector2(p.x, p.z), 175.0)

func _clear(p: Vector2, canopy_radius: float) -> bool:
	var key := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	for segment in _routes.get(key, []):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, segment[0], segment[1])) < float(segment[2]):
			return false
	# Search neighbouring cells so canopies also clear protected footprints.
	var low := (p - Vector2.ONE * canopy_radius) / GRID
	var high := (p + Vector2.ONE * canopy_radius) / GRID
	for z in range(floori(low.y), floori(high.y) + 1):
		for x in range(floori(low.x), floori(high.x) + 1):
			for disk in _obstacles.get(Vector2i(x, z), []):
				if p.distance_to(disk[0]) < float(disk[1]) + canopy_radius:
					return false
	for water in _info.get("waters", []):
		var local := (p - Vector2(water.c[0], water.c[1])).rotated(float(water.yaw))
		if absf(local.x) < float(water.sx) + canopy_radius + 15.0 and absf(local.y) < float(water.sz) + canopy_radius + 15.0:
			return false
	return true

func _grow_zone(zone: Dictionary) -> void:
	var biome := String(zone.biome)
	var centers: Array[Vector2] = []
	var zone_center := Vector2(zone.c[0], zone.c[1])
	# Groves follow the road's large curves, with ragged edges ~100–200m from it.
	for section in _info.get("sections", []):
		if String(section.biome) != biome or centers.size() >= 4:
			continue
		var route: Array = section.variants[0].route
		for fraction in [0.25, 0.72]:
			var i := clampi(int(route.size() * float(fraction)), 0, route.size() - 2)
			var anchor := _xz(route[i])
			var along := (_xz(route[i + 1]) - anchor).normalized()
			for side in [1.0, -1.0]:
				var center := anchor + Vector2(-along.y, along.x) * float(side) * 430.0
				if absf(center.x - zone_center.x) > 2650.0 or absf(center.y - zone_center.y) > 2650.0:
					continue
				var spaced := true
				for previous in centers:
					if previous.distance_to(center) < 900.0:
						spaced = false
				if not spaced:
					continue
				centers.append(center)
				_grow_grove(center, anchor, biome)
				break
			if centers.size() >= 4:
				break

func _grow_grove(center: Vector2, viewpoint: Vector2, biome: String) -> void:
	var accepted: Array[Vector2] = []
	var start_count := _tree_count
	for attempt in 7000:
		if accepted.size() >= TREES_PER_GROVE:
			break
		var angle := _rng.randf_range(0.0, TAU)
		var radius := sqrt(_rng.randf()) * GROVE_RADIUS * (0.87 + 0.13 * sin(angle * 3.0 + center.x))
		var p := center + Vector2.from_angle(angle) * radius
		var species := "tree_giant" if _rng.randf() < 0.78 else ("pine" if biome == "forest" else "palm")
		var prop: Dictionary = _map._prop(species)
		var bounds: AABB = prop.mesh.get_aabb()
		var height := _rng.randf_range(78.0, 150.0) if species == "tree_giant" else _rng.randf_range(60.0, 110.0)
		var scale_factor := height / maxf(bounds.size.y, 1.0)
		var canopy_radius := maxf(bounds.size.x, bounds.size.z) * scale_factor * 0.4
		if not _clear(p, canopy_radius):
			continue
		var crowded := false
		for previous in accepted:
			if previous.distance_squared_to(p) < 29.0 * 29.0:
				crowded = true
				break
		if crowded:
			continue
		var h: float = _terrain.height_at(p.x, p.y)
		if h < float(_info.get("water_y", 0.0)) + 3.0:
			continue
		var slope_x: float = absf(_terrain.height_at(p.x + 12.0, p.y) - h)
		var slope_z: float = absf(_terrain.height_at(p.x, p.y + 12.0) - h)
		if maxf(slope_x, slope_z) > 13.0:
			continue
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_factor), Vector3(p.x, h - bounds.position.y * scale_factor - 0.4, p.y))
		_add_instance(species, xf)
		_add_trunk(prop, xf)
		accepted.append(p)
		_tree_count += 1
		# A restrained fern layer, substantially cheaper than the original ground cover.
		if accepted.size() % 3 == 0:
			var fern := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * _rng.randf_range(2.0, 4.0)), Vector3(p.x + 8.0, _terrain.height_at(p.x + 8.0, p.y + 8.0), p.y + 8.0))
			_add_instance("fern", fern)
			_fern_count += 1
	if _tree_count > start_count:
		_groves.append({"name": "Floresta Monumental" if biome == "forest" else "Selva Monumental", "biome": biome,
			"position": Vector3(center.x, _terrain.height_at(center.x, center.y), center.y),
			"viewpoint": Vector3(viewpoint.x, _terrain.height_at(viewpoint.x, viewpoint.y) + 4.0, viewpoint.y),
			"tree_count": _tree_count - start_count, "radius": GROVE_RADIUS})

func _add_instance(species: String, xf: Transform3D) -> void:
	var cell := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	_batches.get_or_add(cell, {}).get_or_add(species, []).append(xf)

func _add_trunk(prop: Dictionary, xf: Transform3D) -> void:
	if not prop.get("shape"):
		return
	var cell := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	if not _bodies.has(cell):
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_set_space(body, get_world_3d().space)
		_bodies[cell] = body
	var shape: Shape3D = prop.shape
	if not _shapes.has(shape):
		_shapes.append(shape)
	var trunk_xf := xf * Transform3D(Basis(), Vector3(0, float(prop.h) * 0.5, 0))
	PhysicsServer3D.body_add_shape(_bodies[cell], shape.get_rid(), trunk_xf)

func _flush() -> void:
	for cell in _batches:
		for species in _batches[cell]:
			var transforms: Array = _batches[cell][species]
			var origin: Vector3 = transforms[0].origin
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _map._prop(species).mesh
			mm.instance_count = transforms.size()
			for i in transforms.size():
				mm.set_instance_transform(i, Transform3D(transforms[i].basis, transforms[i].origin - origin))
			var node := MultiMeshInstance3D.new()
			node.name = "Mega_%s_%d_%d" % [species, cell.x, cell.y]
			node.multimesh = mm
			node.position = origin
			node.visibility_range_end_margin = 180.0
			add_child(node)
			if species == "fern":
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_ferns.append(node)
			else:
				_canopies.append(node)
	_batches.clear()
