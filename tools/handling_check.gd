extends "res://../tools/physics_check.gd"
## Real sloped hulls, water edges and recovery spaces, using production scripts.
const Safe = preload("res://scripts/safe_respawn.gd")
const MapScript = preload("res://scripts/map.gd")

func hill(degrees: float, rate: int, transition := false) -> void:
	Engine.physics_ticks_per_second = rate
	var fixture := Node3D.new()
	root.add_child(fixture)
	var angle := deg_to_rad(degrees)
	var ramp := box(fixture, Vector3(0, -0.5 / cos(angle), 0), Vector3(100, 1, 600 / cos(angle)))
	ramp.rotation.x = angle
	var start_z := 120.0
	if transition:
		ramp.scale.z = 0.5
		ramp.position.z = -150.0
		ramp.position.y = tan(angle) * 150.0 - 0.5 / cos(angle)
		box(fixture, Vector3(0, -1, 150), Vector3(100, 2, 300))
		start_z = 40.0
	var start_y := 1.1 if transition else -tan(angle) * start_z + 1.1
	var pod = vehicle(fixture, Vector3(0, start_y, start_z), Vector3(0, 0 if transition else tan(angle) * 60.0, -60))
	pod.on_ground = true
	await prepare(pod)
	var max_error := 0.0
	var supported := 0
	for tick in rate * 3:
		await physics_frame
		if tick > rate and pod.position.z < (0 if transition else 300):
			max_error = maxf(max_error, absf(pod.position.y - (-tan(angle) * pod.position.z + 1.1)))
			supported += 1 if pod.on_ground else 0
	var label := "hill %s° %sHz transition=%s" % [degrees, rate, transition]
	check(pod.position.z < start_z - 100.0, label + " travels >100m without getting stuck")
	check(max_error < 1.4, label + " follows actual slope height")
	check(supported > rate, label + " maintains suspension support")
	check(absf(pod.visual_pitch - angle) < 0.16, label + " visible nose follows uphill/downhill")
	print(label, " pos=", pod.position, " pitch=", rad_to_deg(pod.visual_pitch), " error=", max_error)
	await dispose(fixture)

func water_test() -> void:
	Engine.physics_ticks_per_second = 60
	var fixture := Node3D.new()
	root.add_child(fixture)
	var generator = MapScript.new()
	var body: StaticBody3D = generator._water_body()
	var collision := CollisionShape3D.new()
	collision.shape = generator._water_support_shape(Vector2(200, 200))
	body.add_child(collision)
	fixture.add_child(body)
	generator.free()
	var pod = vehicle(fixture, Vector3(0, 1.1, 110), Vector3(0, -1, -45))
	var impacts := [0]
	pod.scraped.connect(func(_v): impacts[0] += 1)
	await prepare(pod)
	for i in 100:
		await physics_frame
	check(impacts[0] == 0, "No invisible collision at water edge")
	check(pod.position.z < 30 and pod.on_water and pod.on_ground, "Crosses water edge and regains hover")
	pod.place(Vector3(0, 24, 0), Vector2(0, -1), 0)
	pod.vel = Vector3(0, -95, 0)
	pod.running = false
	var submerged := false
	for i in 180:
		await physics_frame
		submerged = submerged or pod.position.y < -0.05
	check(not submerged, "Fast vertical landing does not tunnel through water")
	check(pod.on_water and absf(pod.position.y - 1.1) < 0.15, "Fast water landing settles")
	check((body.collision_layer & pod.SOLID_MASK) == 0, "Water cannot obstruct hull or camera")
	await dispose(fixture)

func roof_and_recovery() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0, -1, 0), Vector3(300, 2, 300))
	box(fixture, Vector3(0, 3.9, 0), Vector3(20, 0.6, 40))
	var pod = vehicle(fixture, Vector3(0, 1.1, 0), Vector3.ZERO)
	pod.running = false
	await prepare(pod)
	for i in 120:
		await physics_frame
	check(pod.on_ground and absf(pod.position.y - 1.1) < 0.12, "Low tunnel roof never becomes floor or loses support")
	var space: PhysicsDirectSpaceState3D = pod.get_world_3d().direct_space_state
	check(not Safe.candidate(space, Vector3(40, 0, 40), Vector2(0, -1), [pod.get_rid()]).is_empty(), "Recovery accepts wide clear surface")
	check(Safe.candidate(space, Vector3(0, 0, 0), Vector2(0, -1), [pod.get_rid()]).is_empty(), "Recovery rejects insufficient roof clearance")
	check(Safe.candidate(space, Vector3(0, 0, 148), Vector2(0, -1), [pod.get_rid()]).is_empty(), "Recovery rejects edge without full hull support")
	pod._touches[3] = Vector2(1,1)
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.pressed = false
	pod._input(release)
	check(pod._touches.is_empty(), "Touch release over HUD clears held steering/brake")
	await dispose(fixture)

func bank_and_ledge() -> void:
	Engine.physics_ticks_per_second = 60
	var fixture := Node3D.new()
	root.add_child(fixture)
	var bank := box(fixture, Vector3(0,-0.5,0), Vector3(100,1,300))
	bank.rotation.z = deg_to_rad(20)
	var pod = vehicle(fixture, Vector3(0,1.1,0), Vector3.ZERO)
	pod.running = false
	await prepare(pod)
	for i in 120:
		await physics_frame
	check(pod.on_ground and absf(pod.model.rotation.z - deg_to_rad(20)) < 0.08, "Vehicle follows banked surface laterally")
	await dispose(fixture)
	fixture = Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0,-1,50), Vector3(100,2,100))
	pod = vehicle(fixture, Vector3(0,1.1,20), Vector3(0,0,-60))
	pod.on_ground = true
	await prepare(pod)
	var left_edge := false
	var fell := false
	for i in 70:
		await physics_frame
		if pod.position.z < -10:
			left_edge = left_edge or not pod.on_ground
			fell = fell or pod.vel.y < -8
	check(left_edge and fell, "Ledge releases suspension into gravity; no hovering across holes")
	check(pod.visual_pitch < -0.05, "Airborne nose follows descending trajectory")
	await dispose(fixture)
	fixture = Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0,-1,0), Vector3(100,2,200))
	box(fixture, Vector3(0,30,-20), Vector3(100,60,2))
	pod = vehicle(fixture, Vector3(0,1.1,0), Vector3(0,0,-50))
	pod.on_ground = true
	await prepare(pod)
	var highest := 0.0
	for i in 120:
		await physics_frame
		highest = maxf(highest, pod.position.y)
	check(highest < 2.0 and pod.position.z > -20, "Vertical wall cannot become climbable support")
	await dispose(fixture)

func run() -> void:
	if "--steep" in OS.get_cmdline_user_args():
		await hill(40, 60, true)
		quit(1 if failures else 0)
		return
	for rate in [30, 60, 120]:
		await hill(30, rate)
		await hill(-30, rate)
	await hill(40, 60, true)
	await hill(15, 60, true)
	await water_test()
	await roof_and_recovery()
	await bank_and_ledge()
	print("HANDLING_CHECK: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
