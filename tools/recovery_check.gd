extends SceneTree
const Safe = preload("res://scripts/safe_respawn.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var race = load("res://scenes/main.tscn").instantiate()
	root.add_child(race)
	race.set_process(false)
	race.set_physics_process(false)
	race.player.set_physics_process(false)
	await physics_frame
	await physics_frame
	var viable := 0
	var total := 0
	var space: PhysicsDirectSpaceState3D = race.get_world_3d().direct_space_state
	for event in race.info.events + [{"start": race.info.start, "gates": race.info.checkpoints}]:
		for gate in [event.start] + event.gates:
			total += 1
			var pos := Vector3(gate.p[0], gate.p[1], gate.p[2])
			var dir := Vector2(gate.dir[0], gate.dir[1])
			var safe := Safe.candidate(space, pos, dir, [race.player.get_rid()])
			if not safe.is_empty():
				viable += 1
			else:
				print("Blocked recovery gate at ", pos)
	print("RECOVERY GATES: ", viable, "/", total, " directly safe; blocked gates search earlier checkpoints")
	check(viable > total * 0.75, "World supplies clear recovery candidates")
	race.state = race.State.RACE
	race.next_cp = 1
	race.t_race = 123.0
	race.player.global_position = Vector3(0,-100,0)
	race.player.running = true
	race.player.braking = false
	race._stuck_p = race.player.global_position
	for i in 365:
		race._check_stuck(1.0 / 60.0)
	check(race.player.global_position.y > -50, "Automatic recovery unsticks real player without restart")
	check(race.next_cp == 1 and race.t_race == 123.0, "Recovery preserves checkpoints and timer")
	check(race.player.vel.length() <= 12.1 and race.player.running, "Recovery resumes at controllable speed")
	var pos: Vector3 = race.player.global_position
	race.player.braking = true
	for i in 600:
		race._check_stuck(1.0 / 60.0)
	check(race.player.global_position == pos, "Holding brake never triggers automatic recovery")
	race.player.global_position = Vector3(0,-100,0)
	race.hud.recover_pressed.emit()
	check(race.player.global_position.y > -50, "HUD recovery button resumes without pausing/restarting")
	check(race.next_cp == 1 and race.t_race == 123.0, "Manual recovery preserves progress")
	race.queue_free()
	await process_frame
	print("RECOVERY_CHECK: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
