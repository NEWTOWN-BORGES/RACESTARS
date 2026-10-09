extends SceneTree
## Real collision fixtures using the production vehicle hull, at several physics rates.
var controller: Script = preload("res://scripts/podracer.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func box(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = size
	shape.shape = geometry
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)
	return body

func vehicle(parent: Node3D, pos: Vector3, incoming: Vector3):
	var pod = controller.new()
	var model := Node3D.new()
	model.name = "Model"
	pod.add_child(model)
	var collision := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(5.4, 1.2, 10.0)
	collision.shape = hull
	collision.position = Vector3(0, 1.7, 0)
	pod.add_child(collision)
	pod.autopilot = true
	pod.running = true
	pod.position = pos
	pod.vel = incoming
	if Vector2(incoming.x, incoming.z).length() > 0.01:
		pod.heading = atan2(-incoming.x, -incoming.z)
	pod.set_physics_process(false)
	parent.add_child(pod)
	return pod

func prepare(pod) -> void:
	await physics_frame
	await physics_frame
	pod.set_physics_process(true)

func dispose(fixture: Node3D) -> void:
	fixture.queue_free()
	await process_frame
	await physics_frame

func landing(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0, -1, 0), Vector3(1000, 2, 1000))
	var pod = vehicle(fixture, Vector3(0, 14, 0), Vector3(0, -8, 0))
	pod.running = false
	var events := [0]
	pod.landed.connect(func(_strength: float): events[0] += 1)
	await prepare(pod)
	var peak_late_speed := 0.0
	for tick in rate * 4:
		await physics_frame
		if tick > rate * 3:
			peak_late_speed = maxf(peak_late_speed, absf(pod.vel.y))
	check(absf(pod.position.y - 1.1) < 0.12, "Landing hover height at %d Hz" % rate)
	check(peak_late_speed < 0.5, "Landing settles without repeated bouncing at %d Hz" % rate)
	check(pod.on_ground, "Landing regains support at %d Hz" % rate)
	check(events[0] == 1, "Landing emits a single impact at %d Hz" % rate)
	print("LANDING ", rate, " Hz: y=", pod.position.y, " late_vy=", peak_late_speed, " events=", events[0])
	await dispose(fixture)

func wall_contact(incoming: Vector3, label: String) -> Dictionary:
	Engine.physics_ticks_per_second = 60
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(1, 50, 0), Vector3(2, 100, 1000))
	var pod = vehicle(fixture, Vector3(-8, 50, 0), incoming)
	var impacts := [0]
	pod.scraped.connect(func(_strength: float): impacts[0] += 1)
	await prepare(pod)
	var contacted := false
	var after := Vector3.ZERO
	var at_contact := Vector3.ZERO
	var contact_tick := 0
	for tick in 90:
		await physics_frame
		if not contacted and impacts[0] > 0:
			contacted = true
			after = pod.vel
			at_contact = pod.position
			contact_tick = tick
		if contacted and tick >= contact_tick + 12:
			break
	var incoming_speed := Vector2(incoming.x, incoming.z).length()
	var outgoing_speed := Vector2(after.x, after.z).length()
	check(contacted, label + " produces actual wall contact")
	check(outgoing_speed <= incoming_speed + 0.05, label + " cannot gain horizontal speed")
	check(after.x < -0.1, label + " rebounds away from wall")
	check(at_contact.x - pod.position.x > 0.5, label + " separates from wall within 0.2 seconds")
	if incoming.y < -1.0:
		check(after.y <= incoming.y + 0.1, label + " preserves downward fall through side contact")
	print("WALL ", label, ": incoming=", incoming, " outgoing=", after, " separation=", at_contact.x - pod.position.x, " contacts=", impacts[0])
	var result := {"retained": outgoing_speed / incoming_speed, "tangent": absf(after.z)}
	await dispose(fixture)
	return result

func ramp_gap() -> void:
	Engine.physics_ticks_per_second = 60
	var fixture := Node3D.new()
	root.add_child(fixture)
	# An eight-degree takeoff terminates at z=0; the landing deck starts at z=-45.
	var angle := deg_to_rad(8.0)
	var ramp := box(fixture, Vector3(0, -tan(angle) * 50.0 - 0.5 / cos(angle), 50), Vector3(120, 1, 100.0 / cos(angle)))
	ramp.rotation.x = angle
	box(fixture, Vector3(0, -1, -245), Vector3(120, 2, 400))
	var pod = vehicle(fixture, Vector3(0, -tan(deg_to_rad(8.0)) * 80.0 + 1.1, 80), Vector3(0, 0, -125))
	pod.on_ground = true
	await prepare(pod)
	var launch_velocity := -INF
	var gap_air := false
	var cleared := false
	var recovered := false
	var max_speed := 0.0
	for tick in 180:
		await physics_frame
		max_speed = maxf(max_speed, pod.speed())
		if pod.position.z < 0 and launch_velocity == -INF:
			launch_velocity = pod.vel.y
		if pod.position.z < -10 and pod.position.z > -40 and not pod.on_ground:
			gap_air = true
		if pod.position.z <= -45 and pod.position.z > -50:
			cleared = pod.position.y > 0.0
		if pod.position.z < -90 and pod.on_ground and absf(pod.position.y - 1.1) < 0.25:
			recovered = true
	check(launch_velocity > 8.0, "Ramp gives upward launch velocity")
	check(gap_air, "Vehicle is airborne over the gap")
	check(cleared, "Vehicle clears the 45 metre gap")
	check(recovered, "Vehicle recovers hover after ramp landing")
	check(max_speed < 126.0, "Ramp and landing do not create horizontal speed")
	print("RAMP: launch_vy=", launch_velocity, " max_speed=", max_speed, " cleared=", cleared, " recovered=", recovered)
	await dispose(fixture)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--controller="):
			controller = load(arg.trim_prefix("--controller="))
	for rate in [30, 60, 120]:
		await landing(rate)
	var glancing := await wall_contact(Vector3(30, 0, -100), "glancing")
	var head_on := await wall_contact(Vector3(100, 0, 0), "head-on")
	await wall_contact(Vector3(30, -18, -100), "falling glancing")
	check(glancing.retained > head_on.retained + 0.35, "Glancing contact retains substantially more speed than head-on")
	check(glancing.tangent > 95.0, "Glancing contact preserves travel along wall")
	await ramp_gap()
	print("PHYSICS_CHECK: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
