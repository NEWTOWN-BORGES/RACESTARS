extends SceneTree
## Integração dos efeitos e colisão real do braço, sem carregar o mapa de 24 km.
const State = preload("res://scripts/speed_fx_state.gd")
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
	race.set_script(null)
	for name in ["Terrain", "Map", "HUD", "Audio"]:
		race.get_node(name).free()
	root.add_child(race)
	var player = race.get_node("Player")
	player.set_physics_process(false)
	var rig = race.get_node("CameraRig")
	var fx = race.get_node("SpeedFX")
	rig.setup(player)
	fx.setup(player, rig.camera)
	fx.setup(player, rig.camera)
	check(fx.particle_nodes.size() == 10 and fx.flame_nodes.size() == 2, "Setup duplicou emissores")
	player.running = true
	player.vel = Vector3(0, -200, -100)
	player.on_ground = true
	player.ground_valid = true
	player.ground_point = Vector3(0, -1.1, 0)
	var state := State.new()
	state.capture(player, false)
	check(is_equal_approx(state.speed_mps, 100.0), "Queda vertical alterou velocidade visual")
	fx.update_state(state, 1.0)
	check(fx.dust.emitting and not fx.water_spray.emitting, "Poeira em chão seco")
	var full_thrust: float = fx.flame_nodes[0].scale.z
	player.braking = true
	state.capture(player, false)
	fx.update_state(state, 1.0)
	check(fx.flame_nodes[0].scale.z < full_thrust * 0.65 and fx.streaks.emitting, "Travagem não separa chama e vento")
	state.on_water = true
	fx.update_state(state, 0.1)
	check(not fx.dust.emitting and not fx.smoke.emitting and fx.water_spray.emitting, "Água emite areia")
	state.on_ground = false
	fx.update_state(state, 0.1)
	check(not fx.dust.emitting and not fx.water_spray.emitting, "Salto emite partículas de chão")
	state.on_ground = true
	state.on_water = false
	state.in_tunnel = true
	fx.update_state(state, 0.1)
	check(not fx.dust.emitting, "Túnel emite areia")
	state.in_tunnel = false
	fx.landing_burst(24.0, state)
	check(fx.landing.emitting, "Aterragem não emite pulso")
	fx.set_quality("low")
	fx.update_state(state, 0.1)
	check(fx.dust.amount == 24 and not fx.blur.visible and not player.get_node("EngineLight").visible, "Perfil baixo inválido")
	fx.boost_flash()
	for i in 6:
		fx.update_state(state, 1.0 / 30.0)
	var flash30: float = fx._flash
	fx.boost_flash()
	for i in 12:
		fx.update_state(state, 1.0 / 60.0)
	check(is_equal_approx(flash30, fx._flash), "Boost depende do FPS")
	state.running = false
	fx.update_state(state, 1.0)
	check(not fx.trail.emitting and not fx.streaks.emitting and not fx.dust.emitting, "Fim da corrida continua a emitir")
	fx.reset()
	check(not fx.flame_nodes[0].visible and not fx.landing.emitting, "Reset preservou chama/pulso")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 20, 2)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(0, 4, 8)
	race.add_child(wall)
	await physics_frame
	await physics_frame
	rig.snap()
	check(rig.camera.global_position.z < 7.0, "Snap colocou câmera atrás da parede")
	state.capture(player, false)
	rig.update_state(state, 0.0)
	for i in 5:
		await physics_frame
	check(rig.camera.global_position.z < 7.0 and rig.camera.position.z > 0, "Braço não resolve parede")
	rig.toggle()
	for i in 3:
		await physics_frame
	var cockpit: Vector3 = player.model.global_transform * Vector3(0, 2.55, 0.9)
	check(rig.camera.global_position.distance_to(cockpit) < 0.01, "Braço moveu câmera em primeira pessoa")
	rig.toggle()
	check(rig.camera.global_position.z < 7.0, "Troca de câmera atravessa parede")
	player.global_position = Vector3(1000, 0, 1000)
	rig.snap()
	check(rig.camera.global_position.distance_to(player.global_position) < 25.0, "Viagem interpola posição anterior")
	race.queue_free()
	await process_frame
	print("SPEED_FX_CHECK: ", checks, " verificações, ", failures, " falhas")
	quit(1 if failures else 0)
