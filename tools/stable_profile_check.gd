extends SceneTree
var failures := 0
var checks := 0
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
	await process_frame
	race.set_process(false)
	race.set_physics_process(false)
	race.player.set_physics_process(false)
	var visual = race.environment_system
	var quality = load("res://scripts/visual_quality.gd")
	check(quality.is_a15_model("SM-A155F") and quality.is_a15_model("SM-A156B"), "A15 4G/5G não reconhecido")
	check(not quality.is_a15_model("SM-A157") and not quality.is_a15_model("SM-S921B"), "Deteção altera outros modelos")
	visual.set_quality("mobile")
	var original_counts: Array = []
	for batch in race.map._decor_batches:
		original_counts.append(batch.node.multimesh.visible_instance_count)
	var original_lods: Array = []
	for chunk in race.terrain.chunks:
		original_lods.append(chunk.lod)
	var bodies: int = race.map._bodies.size()
	var heights: PackedFloat32Array = race.terrain.heights.duplicate()
	var pose: Transform3D = race.player.global_transform
	visual.set_quality("stable")
	check(Engine.max_fps == 30, "Perfil não limita apresentação a 30 FPS")
	check(Engine.physics_ticks_per_second == 60, "Perfil alterou frequência da física")
	check(root.msaa_3d == Viewport.MSAA_2X and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Antialiasing incompatível")
	check(root.scaling_3d_scale <= 0.80001 and root.scaling_3d_scale >= 0.4, "Resolução 3D fora do orçamento")
	check(not race.sun.shadow_enabled and visual.reflections.get_child_count() == 0, "Passes caros ativos")
	check(visual.ambient.dust.amount == 6 and race.fx._quality == "low", "Orçamento de partículas inválido")
	check(race.terrain._view_distance == 3000.0, "Vista distante não reduzida")
	var original_total := 0
	var stable_total := 0
	for batch in race.map._decor_batches:
		original_total += batch.node.multimesh.instance_count
		stable_total += batch.node.multimesh.visible_instance_count
	check(stable_total < original_total * 0.5, "Decoração não reduzida substancialmente")
	check(race.map._bodies.size() == bodies and race.terrain.heights == heights, "Perfil mudou colisões ou terreno")
	check(race.player.global_transform == pose, "Perfil mudou posição do jogador")
	var initial_scale: float = root.scaling_3d_scale
	visual._warmup_seconds = 0.0
	for i in 200:
		visual.adapt_performance(0.05)
	check(root.scaling_3d_scale < initial_scale and root.scaling_3d_scale >= visual._scale_floor - 0.00001, "Sobrecarga não reduz resolução de forma limitada")
	var reduced: float = root.scaling_3d_scale
	for i in 1000:
		visual.adapt_performance(1.0 / 30.0)
	check(root.scaling_3d_scale > reduced and root.scaling_3d_scale <= initial_scale, "Recuperação não restaura nitidez")
	visual.set_quality("mobile")
	check(Engine.max_fps == 0 and is_equal_approx(root.scaling_3d_scale, 1.0) and root.msaa_3d == Viewport.MSAA_2X, "Sair do A15 não restaura renderização")
	check(race.sun.shadow_enabled and race.terrain._view_distance == 4800.0, "Sombras/distância não restauradas")
	var counts_restored := true
	for i in original_counts.size():
		counts_restored = counts_restored and race.map._decor_batches[i].node.multimesh.visible_instance_count == original_counts[i]
	check(counts_restored, "Densidade não restaurada")
	var lods_restored := true
	for i in original_lods.size():
		lods_restored = lods_restored and race.terrain.chunks[i].lod == original_lods[i]
	check(lods_restored, "LOD não restaurado")
	race.queue_free()
	await process_frame
	print("STABLE_PROFILE_CHECK ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
