extends SceneTree
## Synthetic hardware events exercise the real bindings, vehicle and menu/HUD.
## This does not replace testing a physical DualShock 4 / DualSense on Windows.
var checks := 0
var failures := 0
var pod

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func key(code: Key, pressed: bool, physical := false) -> void:
	var event := InputEventKey.new()
	event.pressed = pressed
	if physical:
		event.physical_keycode = code
	else:
		event.keycode = code
	dispatch(event)

func axis(code: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = code
	event.axis_value = value
	dispatch(event)

func button(code: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = pressed
	dispatch(event)

func binding_count() -> int:
	var result := 0
	for action in ["steer_left", "steer_right", "brake", "recover", "camera_cycle", "pause_game"]:
		result += InputMap.action_get_events(action).size()
	return result

func run() -> void:
	Input.use_accumulated_input = false
	var controls = load("res://scripts/controls.gd")
	if controls == null:
		check(false, "Production controls script could not load")
		quit(1)
		return
	controls.setup()
	var count := binding_count()
	controls.setup()
	check(count > 12 and binding_count() == count, "Repeated setup must retain bindings without duplicating them")
	pod = load("res://scripts/podracer.gd").new()
	var model := Node3D.new()
	model.name = "Model"
	pod.add_child(model)
	root.add_child(pod)
	pod.set_physics_process(false)
	pod.set_process(false)
	await process_frame
	for physical in [false, true]:
		for entry in [[KEY_LEFT, 1.0], [KEY_RIGHT, -1.0]]:
			key(entry[0], true, physical)
			pod._read_input()
			check(is_equal_approx(pod.steer_target, entry[1]), "Arrow direction, physical=%s code=%s" % [physical, entry[0]])
			key(entry[0], false, physical)
			pod._read_input()
			check(is_zero_approx(pod.steer_target), "Arrow release returns steering to neutral")
		key(KEY_DOWN, true, physical)
		pod._read_input()
		check(pod.braking, "Down arrow brakes, physical=%s" % physical)
		key(KEY_DOWN, false, physical)
	for entry in [[KEY_A, 1.0], [KEY_D, -1.0]]:
		key(entry[0], true, true)
		pod._read_input()
		check(is_equal_approx(pod.steer_target, entry[1]), "Physical A/D direction")
		key(entry[0], false, true)
	for code in [KEY_S, KEY_SPACE]:
		key(code, true, true)
		pod._read_input()
		check(pod.braking, "Physical S/Space brake")
		key(code, false, true)
	axis(JOY_AXIS_LEFT_X, 0.5)
	pod._read_input()
	var half: float = pod.steer_target
	check(half < -0.05 and half > -0.9, "Half analogue steering must remain proportional")
	axis(JOY_AXIS_LEFT_X, 1.0)
	pod._read_input()
	check(is_equal_approx(pod.steer_target, -1.0) and absf(pod.steer_target) > absf(half), "Full analogue steering is stronger than half")
	axis(JOY_AXIS_LEFT_X, -0.5)
	pod._read_input()
	check(is_equal_approx(pod.steer_target, -half), "Analogue steering is symmetric")
	axis(JOY_AXIS_LEFT_X, 0.1)
	pod._read_input()
	check(is_zero_approx(pod.steer_target), "Stick drift inside deadzone cannot turn vehicle")
	axis(JOY_AXIS_LEFT_X, 0.0)
	pod._read_input()
	check(is_zero_approx(pod.steer_target), "Stick release returns steering to neutral")
	for entry in [[JOY_BUTTON_DPAD_LEFT, 1.0], [JOY_BUTTON_DPAD_RIGHT, -1.0]]:
		button(entry[0], true)
		pod._read_input()
		check(is_equal_approx(pod.steer_target, entry[1]), "D-pad steers vehicle")
		button(entry[0], false)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.8)
	pod._read_input()
	check(pod.braking, "L2 engages brake")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	pod._read_input()
	check(not pod.braking, "L2 release disengages brake")
	for entry in [[JOY_BUTTON_X, "brake"], [JOY_BUTTON_Y, "recover"], [JOY_BUTTON_B, "camera_cycle"], [JOY_BUTTON_START, "pause_game"]]:
		button(entry[0], true)
		check(Input.is_action_pressed(entry[1]), "PlayStation button engages %s" % entry[1])
		button(entry[0], false)
		check(not Input.is_action_pressed(entry[1]), "PlayStation button releases %s" % entry[1])
	var size := root.get_visible_rect().size
	pod._touches = {0: Vector2(size.x * 0.1, size.y * 0.8)}
	pod._read_input()
	check(is_equal_approx(pod.steer_target, 1.0), "Android left touch retained")
	pod._touches = {0: Vector2(size.x * 0.3, size.y * 0.8), 1: Vector2(size.x * 0.8, size.y * 0.8)}
	pod._read_input()
	check(is_equal_approx(pod.steer_target, -1.0) and pod.braking, "Android right plus brake multitouch retained")
	pod._touches.clear()
	await process_frame
	await menu_checks()
	await hud_checks()
	pod.queue_free()
	await process_frame
	print("CONTROLLER_CHECK ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func menu_checks() -> void:
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var focus := root.gui_get_focus_owner()
	check(focus is Button and menu.main_box.is_ancestor_of(focus), "Main menu gives focus to an actionable button")
	menu._show(menu.races_box)
	await process_frame
	focus = root.gui_get_focus_owner()
	check(focus is Button and menu.races_box.is_ancestor_of(focus), "Race selection receives controller focus")
	button(JOY_BUTTON_DPAD_DOWN, true)
	await process_frame
	button(JOY_BUTTON_DPAD_DOWN, false)
	check(root.gui_get_focus_owner() != focus, "D-pad navigates race menu")
	menu.races_box.get_child(menu.races_box.get_child_count() - 1).grab_focus()
	button(JOY_BUTTON_A, true)
	await process_frame
	button(JOY_BUTTON_A, false)
	await process_frame
	check(menu.main_box.visible, "Cross activates Back without a mouse")
	menu._show(menu.races_box)
	await process_frame
	button(JOY_BUTTON_B, true)
	await process_frame
	button(JOY_BUTTON_B, false)
	check(menu.main_box.visible, "Circle returns from race menu")
	menu.queue_free()
	await process_frame

func hud_checks() -> void:
	var hud = load("res://scripts/hud.gd").new()
	hud.player = pod
	root.add_child(hud)
	await process_frame
	button(JOY_BUTTON_START, true)
	await process_frame
	button(JOY_BUTTON_START, false)
	check(hud.pause_panel.visible and paused, "Options pauses the offline game")
	var focus := root.gui_get_focus_owner()
	check(focus is Button and hud.pause_panel.is_ancestor_of(focus), "Pause opens with a focused button")
	button(JOY_BUTTON_DPAD_DOWN, true)
	await process_frame
	button(JOY_BUTTON_DPAD_DOWN, false)
	check(root.gui_get_focus_owner() != focus, "D-pad navigates while the scene tree is paused")
	button(JOY_BUTTON_START, true)
	await process_frame
	button(JOY_BUTTON_START, false)
	check(not hud.pause_panel.visible and not paused, "Options resumes the offline game")
	hud.multiplayer_mode = true
	hud._toggle_pause()
	axis(JOY_AXIS_LEFT_X, 1.0)
	pod._read_input()
	check(not paused and hud.pause_panel.visible, "LAN pause keeps the multiplayer simulation running")
	check(pod.controls_blocked and is_zero_approx(pod.steer_target) and pod.braking, "LAN pause blocks steering and brakes despite a held stick")
	hud._toggle_pause()
	pod._read_input()
	check(not pod.controls_blocked and is_equal_approx(pod.steer_target, -1.0) and not pod.braking, "Closing LAN pause restores held analogue input")
	hud.open_map()
	pod._read_input()
	check(not paused and pod.controls_blocked and is_zero_approx(pod.steer_target) and pod.braking, "LAN map also blocks driving without stopping the simulation")
	button(JOY_BUTTON_B, true)
	await process_frame
	button(JOY_BUTTON_B, false)
	pod._read_input()
	check(not hud.map_panel.visible and not pod.controls_blocked and is_equal_approx(pod.steer_target, -1.0), "Circle closes LAN map and restores driving")
	hud.show_results(false)
	await process_frame
	focus = root.gui_get_focus_owner()
	check(focus is Button and hud.results_panel.is_ancestor_of(focus) and focus.visible, "Guest results focus a visible action")
	pod._read_input()
	check(pod.controls_blocked and is_zero_approx(pod.steer_target) and pod.braking, "Results prevent controller navigation from moving the vehicle")
	axis(JOY_AXIS_LEFT_X, 0.0)
	paused = false
	hud.queue_free()
	await process_frame
