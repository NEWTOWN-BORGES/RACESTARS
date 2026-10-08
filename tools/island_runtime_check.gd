extends SceneTree
## Real physics regression for ocean coverage and dry underground routes.
## From the repository root:
## godot --headless --path game --script ../tools/island_runtime_check.gd -- --mode=explorar

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var race: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(race)
	await physics_frame
	await physics_frame
	var space := race.get_world_3d().direct_space_state
	# Four corners are deep ocean within the original terrain extent.
	for point in [Vector2(-12160, -12160), Vector2(12160, -12160), Vector2(-12160, 12160), Vector2(12160, 12160)]:
		probe(space, point, 10.0, -90.0, true, "sea corner")
	# Sample the extension beyond the heightmap and the physical ocean/coast.
	probe(space, Vector2(13000, 0), 10.0, -90.0, true, "open sea")
	probe(space, Vector2(-12000, 0), 10.0, -90.0, true, "western bay")
	# Cast below each tunnel's roof: a water surface here would flood the
	# underground routes even when the visible ocean shader discards it.
	for tunnel in race.info.tunnels:
		if float(tunnel.p[1]) >= 0.0:
			continue
		var forward := Vector2(-sin(float(tunnel.yaw)), -cos(float(tunnel.yaw)))
		# Avoid exact heightfield cell boundaries: a ray on a shared triangle
		# edge can miss in Godot Physics (the Maciço center has x == 3072).
		var point := Vector2(tunnel.p[0], tunnel.p[2]) + forward * float(tunnel.len) * 0.5 + Vector2(0.25, 0.25)
		probe(space, point, 0.5, float(tunnel.p[1]) - 8.0, false, String(tunnel.name))
	print("OCEAN_PHYSICS failures=", failures)
	race.queue_free()
	await process_frame
	quit(1 if failures else 0)

func probe(space: PhysicsDirectSpaceState3D, point: Vector2, top: float, bottom: float, expect_water: bool, tag: String) -> void:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, top, point.y), Vector3(point.x, bottom, point.y), 3)
	var hit := space.intersect_ray(ray)
	var wet: bool = not hit.is_empty() and hit.collider != null and hit.collider.has_meta("water")
	var good := not hit.is_empty() and wet == expect_water
	if expect_water and not hit.is_empty():
		good = good and absf(hit.position.y) < 0.01
	if not good:
		failures += 1
	print("PASS " if good else "FAIL ", tag, " point=", point, " y=", hit.get("position", Vector3.INF).y, " water=", wet)
