extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Este teste precisa de renderização real.")
		quit(1)
		return
	var race = load("res://scenes/main.tscn").instantiate()
	root.add_child(race)
	await process_frame
	race.set_process(false)
	race.set_physics_process(false)
	race.player.set_physics_process(false)
	race.camera_rig.set_physics_process(false)
	race.camera_rig.arm.set_physics_process_internal(false)
	race.hud.hide()
	race.fx.blur_layer.hide()
	var groves: Array = race.map.get_node("MegaForests").get_meta("groves")
	var grove: Dictionary = groves[0]
	race.cam.global_position = grove.viewpoint + Vector3(0, 20, 0)
	race.cam.look_at(grove.position + Vector3(0, 65, 0))
	race.cam.fov = 67
	DirAccess.make_dir_recursive_absolute("/tmp/racestars-a15")
	for profile in ["mobile", "stable"]:
		race.environment_system.set_quality(profile)
		race.environment_system.update_region(race.cam.global_position, 0, false, true)
		race.terrain.update_now()
		for i in 8:
			await process_frame
			await RenderingServer.frame_post_draw
		var start := Time.get_ticks_msec()
		var draws := 0.0
		var primitives := 0.0
		for i in 6:
			await process_frame
			await RenderingServer.frame_post_draw
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		root.get_texture().get_image().save_png("/tmp/racestars-a15/" + profile + ".png")
		print("RENDER_BUDGET ", JSON.stringify({"profile":profile,"draw_calls":draws/6,"primitives":primitives/6,"scale":root.scaling_3d_scale,"software_ms_per_frame":(Time.get_ticks_msec()-start)/6.0}))
	race.queue_free()
	await process_frame
	quit()
