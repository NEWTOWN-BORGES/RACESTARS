extends SceneTree
## Capturas do cenário real, sem alterar posições guardadas ou dados do mapa.
## godot --path game --script ../tools/visual_check.gd -- --out=/tmp/racestars-visual

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output := "/tmp/racestars-visual"
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	if DisplayServer.get_name() == "headless":
		push_error("As capturas precisam de um renderizador gráfico; headless não desenha imagens.")
		quit(1)
		return
	var race = load("res://scenes/main.tscn").instantiate()
	root.add_child(race)
	await process_frame
	if "--no-shadows" in OS.get_cmdline_user_args():
		race.sun.shadow_enabled = false
	race.set_process(false)
	race.player.set_physics_process(false)
	race.camera_rig.set_physics_process(false)
	race.camera_rig.arm.set_physics_process_internal(false)
	race.hud.visible = false
	race.fx.blur_layer.hide()
	for particle in race.fx.particle_nodes + race.fx.flame_nodes:
		particle.visible = false
	# Concluir o aquecimento antes das fotografias, que não avançam a corrida.
	for frame in 5:
		await process_frame
	var scenery: Node
	for child in race.map.get_children():
		if child.has_meta("landmarks"):
			scenery = child
	assert(scenery != null, "Não foram criados os cenários da ilha")
	var views: Array = []
	for site in scenery.get_meta("landmarks"):
		if site.name == "Porto do Sol":
			views.append(["01-porto", site.position + Vector3(240, 135, 230), site.position + Vector3(0, 46, 0)])
		elif site.name == "Farol das Marés":
			views.append(["02-costa", site.position + Vector3(-230, 125, 260), site.position + Vector3(0, 48, 0)])
		elif site.name == "Santuário do Cenote":
			views.append(["03-santuario", site.position + Vector3(230, 155, 245), site.position + Vector3(0, 65, 0)])
	DirAccess.make_dir_recursive_absolute(output)
	for view in views:
		if not only.is_empty() and only != view[0]:
			continue
		race.cam.global_position = view[1]
		race.cam.look_at(view[2])
		race.cam.fov = 67.0
		if race.environment_system.has_method("update_region"):
			race.environment_system.update_region(view[2], 0.0, false, true)
		race.terrain.update_now()
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = output.path_join(view[0] + ".png")
		var error := root.get_texture().get_image().save_png(path)
		assert(error == OK, "Falha a guardar " + path)
		print("CAPTURE ", path)
	race.queue_free()
	await process_frame
	quit()
