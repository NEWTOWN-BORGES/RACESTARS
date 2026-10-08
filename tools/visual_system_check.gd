extends SceneTree
var failed := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(label)
func run() -> void:
	var race = load("res://scenes/main.tscn").instantiate()
	root.add_child(race)
	await process_frame
	var visual = race.environment_system
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	check(race.get_node("Audio") == race.audio and race.get_node("SpeedFX") == race.fx, "Controladores duplicados")
	for profile in ["mobile", "balanced", "ultra"]:
		visual.set_quality(profile)
		var env: Environment = visual.environment
		check(env.ssil_enabled == (forward and profile == "ultra"), "SSIL incompatível: " + profile)
		check(env.volumetric_fog_enabled == (forward and profile == "ultra"), "Volumetria incompatível: " + profile)
		check(visual.reflections.get_child_count() == (0 if profile == "mobile" else 2), "Orçamento de reflexos: " + profile)
		check(visual.ambient.dust.amount == (16 if profile == "mobile" else (64 if profile == "ultra" else 36)), "Orçamento ambiente: " + profile)
	visual.set_quality("mobile")
	check(not visual.environment.glow_enabled, "Perfil leve mantém bloom")
	check(visual.get_node("SurfaceWear").get_child_count() == 1, "Desgaste ausente")
	# Exercita a construção do volume mesmo no servidor de testes sem GPU Vulkan.
	visual._rebuild_local_lighting(false, true)
	check(visual.volumes.get_child_count() == 1, "Volume local inválido")
	visual.set_quality("mobile")
	race.player.place(Vector3(800, 90, 600), Vector2(0, -1), 0)
	race.camera_rig.snap()
	check(race.cam.global_position.distance_to(race.player.global_position) < 25, "Viagem deixou câmera atrás")
	paused = true
	var elapsed: float = race.elapsed
	await process_frame
	await process_frame
	check(is_equal_approx(elapsed, race.elapsed), "Pausa avançou corrida")
	paused = false
	race.queue_free()
	await process_frame
	print("VISUAL_SYSTEM_CHECK: ", checks, " verificações, ", failed, " falhas")
	quit(1 if failed else 0)
