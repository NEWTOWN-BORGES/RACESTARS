extends "res://../tools/physics_check.gd"
const Controls = preload("res://scripts/controls.gd")

func nitro_drive() -> void:
	Engine.physics_ticks_per_second = 60
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0,-1,0), Vector3(1000,2,2000))
	var pod = vehicle(fixture, Vector3(0,1.1,0), Vector3(0,0,-120))
	pod.on_ground = true
	pod.nitro_charge = 100.0
	pod.nitro_requested = true
	await prepare(pod)
	var peak := 0.0
	for i in 120:
		await physics_frame
		peak = maxf(peak, pod.speed())
	check(peak > 145.0 and peak <= pod.SPEED_CAP + 0.1, "Nitro accelerates actual hull within speed cap")
	check(absf(pod.nitro_charge - 50.0) < 1.5, "Nitro consumption matches elapsed physics time")
	pod.controls_blocked = true
	var remaining: float = pod.nitro_charge
	for i in 20:
		await physics_frame
	check(not pod.nitro_active and pod.nitro_charge == remaining, "Pause controls block nitro consumption")
	pod.place(Vector3(0,0,0), Vector2(0,-1),0)
	check(pod.nitro_charge == remaining, "Recovery cannot refill nitro")
	pod.nitro_charge = 0.0
	pod.controls_blocked = false
	pod.nitro_requested = true
	pod._update_nitro(0.1)
	check(not pod.nitro_active and pod.nitro_charge == 0, "Empty tank cannot boost")
	pod.add_nitro(150.0, "TEST")
	check(pod.nitro_charge == 100.0, "Recharge caps at 100 percent")
	await dispose(fixture)

func drift_charge_test() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0,-1,0), Vector3(1000,2,1000))
	var pod = vehicle(fixture, Vector3(0,1.1,0),Vector3(0,0,-85))
	pod.heading = 0.5
	pod.on_ground = true
	pod.braking = true
	pod.nitro_charge = 10.0
	await prepare(pod)
	for i in 60:
		await physics_frame
	check(pod.nitro_charge > 15.0, "Actual drifting recharges nitro")
	await dispose(fixture)

func near_pass(collide: bool) -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0,-1,0),Vector3(500,2,1000))
	box(fixture,Vector3(2.5 if collide else 5.5,5,-40),Vector3(2,10,40))
	var pod = vehicle(fixture,Vector3(0,1.1,10),Vector3(0,0,-85))
	pod.on_ground = true
	pod.nitro_charge = 20.0
	var awards := [0]
	pod.nitro_awarded.connect(func(_amount,reason):
		if reason == "QUASE BATIDA": awards[0] += 1)
	await prepare(pod)
	for i in 100:
		await physics_frame
	check(awards[0] == (0 if collide else 1), "Actual collision is not a near-miss reward" if collide else "Passing obstacle closely grants one nitro reward")
	await dispose(fixture)

func jump_reward() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var angle := deg_to_rad(8.0)
	var ramp := box(fixture,Vector3(0,-tan(angle)*50 - 0.5/cos(angle),50),Vector3(120,1,100/cos(angle)))
	ramp.rotation.x = angle
	box(fixture,Vector3(0,-1,-245),Vector3(120,2,400))
	var pod = vehicle(fixture,Vector3(0,-tan(angle)*80 + 1.1,80),Vector3(0,0,-125))
	pod.on_ground = true
	pod.nitro_charge = 20.0
	var awards := [0]
	pod.nitro_awarded.connect(func(_amount,reason):
		if reason == "SALTO": awards[0] += 1)
	await prepare(pod)
	for i in 150:
		await physics_frame
	check(awards[0] == 1 and pod.nitro_charge > 28.0, "Real ramp jump rewards nitro once after landing")
	await dispose(fixture)

func camera_and_inputs() -> void:
	var race = load("res://scenes/main.tscn").instantiate()
	race.set_script(null)
	for name in ["Terrain","Map","HUD","Audio"]:
		race.get_node(name).free()
	root.add_child(race)
	var pod = race.get_node("Player")
	pod.set_physics_process(false)
	var rig = race.get_node("CameraRig")
	rig.setup(pod)
	rig.set_physics_process(false)
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_RIGHT_X
	motion.axis_value = 0.7
	Input.parse_input_event(motion.duplicate())
	await process_frame
	for i in 60:
		rig._update_look(1.0/60)
	check(rig._look_yaw < -1.0, "Right stick rotates camera independently")
	check(Input.get_axis("steer_left","steer_right") == 0, "Camera stick never steers vehicle")
	motion.axis_value = 0
	Input.parse_input_event(motion.duplicate())
	await process_frame
	for i in 300:
		rig._update_look(1.0/60)
	check(absf(rig._look_yaw) < 0.01, "Camera returns behind vehicle after releasing stick")
	rig._look_yaw = 1.0
	rig.snap()
	check(rig._look_yaw == 0 and rig._look_pitch == 0, "Recovery clears camera look offsets")
	motion.axis = JOY_AXIS_TRIGGER_RIGHT
	motion.axis_value = 1.0
	Input.parse_input_event(motion.duplicate())
	await process_frame
	pod._read_input()
	check(pod.nitro_requested and not pod.braking, "R2 activates nitro without braking")
	motion.axis_value = 0
	Input.parse_input_event(motion.duplicate())
	await process_frame
	var size := root.get_visible_rect().size
	pod._touches = {0:Vector2(20,size.y-30),1:Controls.nitro_touch_rect(size).get_center()}
	pod._read_input()
	check(pod.nitro_requested and pod.input_left and not pod.braking, "Android multitouch can steer and nitro together")
	for hz in [30,60,120]:
		pod.running = true
		pod.braking = false
		pod.nitro_requested = true
		pod.nitro_charge = 100.0
		for i in hz * 2:
			pod._update_nitro(1.0/hz)
		check(absf(pod.nitro_charge-50.0)<0.01,"Nitro drain independent of physics rate %d"%hz)
	race.queue_free()
	await process_frame

func run() -> void:
	Input.use_accumulated_input = false
	Controls.setup()
	await nitro_drive()
	await drift_charge_test()
	await near_pass(false)
	await near_pass(true)
	await jump_reward()
	await camera_and_inputs()
	print("NITRO_CHECK: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
