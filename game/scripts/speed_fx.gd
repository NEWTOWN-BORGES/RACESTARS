extends Node
## Efeitos visuais alimentados pela mesma amostra física usada pela câmera.
## Os emissores pertencem à cena: setup configura recursos, nunca duplica nós.

const FXState = preload("res://scripts/speed_fx_state.gd")
const EXHAUST_SHADER = preload("res://shaders/exhaust.gdshader")
const BLUR_SHADER = preload("res://shaders/speed_blur.gdshader")
const PROFILES := {
	"low": [24, 12, 24, 16, 12, 8],
	"mobile": [40, 20, 40, 24, 20, 12],
	"pc": [80, 40, 80, 60, 36, 24],
}

var player: Node3D
var cam: Camera3D
var dust: CPUParticles3D
var smoke: CPUParticles3D
var water_spray: CPUParticles3D
var landing: CPUParticles3D
var streaks: CPUParticles3D # Alias para ferramentas antigas de captura.
var trail: CPUParticles3D
var wind_nodes: Array[CPUParticles3D] = []
var trails: Array[CPUParticles3D] = []
var particle_nodes: Array[CPUParticles3D] = []
var flame_nodes: Array[MeshInstance3D] = []
var blur_layer: CanvasLayer
var blur: ColorRect
var blur_enabled := true
var _engine_light: OmniLight3D
var _flame_materials: Array[ShaderMaterial] = []
var _quality := ""
var _flash := 0.0
var _thrust := 0.0
var _time := 0.0
var _wind_fov := -1.0
var _wind_aspect := -1.0

func setup(p: Node3D, c: Camera3D) -> void:
	player = p
	cam = c
	dust = player.get_node("SurfaceFX/Dust")
	smoke = player.get_node("SurfaceFX/DriftDust")
	water_spray = player.get_node("SurfaceFX/WaterSpray")
	landing = player.get_node("SurfaceFX/Landing")
	_engine_light = player.get_node("EngineLight")
	_engine_light.shadow_enabled = false
	_engine_light.omni_range = 9.0
	particle_nodes.assign([dust, smoke, water_spray, landing])
	wind_nodes.clear()
	trails.clear()
	flame_nodes.clear()
	_flame_materials.clear()
	var soft_quad := _soft_quad()
	_configure_surface(dust, soft_quad, 0.75, Vector3(2.7, 0.08, 2.0))
	_configure_surface(smoke, soft_quad, 0.85, Vector3(3.4, 0.08, 2.6))
	smoke.initial_velocity_min = 5.0
	smoke.initial_velocity_max = 11.0
	smoke.gravity = Vector3(0, 0.9, 0)
	_configure_surface(water_spray, soft_quad, 0.6, Vector3(3.0, 0.05, 1.8))
	water_spray.direction = Vector3(0, 0.65, 1).normalized()
	water_spray.gravity = Vector3(0, -7.0, 0)
	water_spray.initial_velocity_min = 4.0
	water_spray.initial_velocity_max = 9.0
	_configure_surface(landing, soft_quad, 0.5, Vector3(2.5, 0.08, 2.5))
	landing.one_shot = true
	landing.explosiveness = 1.0
	landing.direction = Vector3.UP
	landing.spread = 82.0
	landing.gravity = Vector3(0, -3.0, 0)
	var flame_mesh := _flame_mesh()
	for side in ["Left", "Right"]:
		var nozzle: Node3D = player.get_node("Model/Exhaust" + side)
		var flame: MeshInstance3D = nozzle.get_node("Flame")
		flame.mesh = flame_mesh
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = EXHAUST_SHADER
		flame.material_override = material
		_flame_materials.append(material)
		flame_nodes.append(flame)
		var emitter: CPUParticles3D = nozzle.get_node("Trail")
		_configure_trail(emitter)
		trails.append(emitter)
		particle_nodes.append(emitter)
	for side in ["Left", "Right", "Top", "Bottom"]:
		var emitter: CPUParticles3D = cam.get_node("Wind/" + side)
		_configure_wind(emitter)
		wind_nodes.append(emitter)
		particle_nodes.append(emitter)
	streaks = wind_nodes[0]
	trail = trails[0]
	blur_layer = get_parent().get_node("SpeedOverlay")
	blur = blur_layer.get_node("PeripheralBlur")
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_material := ShaderMaterial.new()
	blur_material.shader = BLUR_SHADER
	blur.material = blur_material
	_quality = ""
	_wind_fov = -1.0
	_wind_aspect = -1.0
	set_quality("mobile" if OS.has_feature("mobile") else "pc")
	reset()

func _unshaded(additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _soft_quad(additive := false) -> QuadMesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.6))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var material := _unshaded(additive)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = material
	return quad

func _fade_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	return gradient

func _particle_defaults(emitter: CPUParticles3D, lifetime: float) -> void:
	emitter.emitting = false
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.color_ramp = _fade_ramp()
	emitter.randomness = 0.35

func _configure_surface(emitter: CPUParticles3D, mesh: Mesh, lifetime: float, extents: Vector3) -> void:
	_particle_defaults(emitter, lifetime)
	emitter.mesh = mesh
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.emission_box_extents = extents
	emitter.direction = Vector3(0, 0.2, 1).normalized()
	emitter.spread = 38.0
	emitter.gravity = Vector3(0, 0.7, 0)
	emitter.initial_velocity_min = 3.0
	emitter.initial_velocity_max = 7.0
	emitter.scale_amount_min = 0.6
	emitter.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 1))
	emitter.scale_amount_curve = curve

func _configure_trail(emitter: CPUParticles3D) -> void:
	_particle_defaults(emitter, 0.16)
	emitter.mesh = _soft_quad(true)
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	emitter.direction = Vector3.BACK
	emitter.spread = 4.0
	emitter.gravity = Vector3.ZERO
	emitter.initial_velocity_min = 6.0
	emitter.initial_velocity_max = 12.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	emitter.scale_amount_curve = curve

func _configure_wind(emitter: CPUParticles3D) -> void:
	_particle_defaults(emitter, 0.22)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 2.0)
	mesh.material = _unshaded(true)
	emitter.mesh = mesh
	emitter.local_coords = true
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.direction = Vector3.BACK
	emitter.spread = 0.0
	emitter.gravity = Vector3.ZERO
	emitter.initial_velocity_min = 45.0
	emitter.initial_velocity_max = 65.0

func _flame_mesh() -> ArrayMesh:
	# Dois quads cruzados: a origem fica no bocal e o comprimento segue +Z.
	var vertices := PackedVector3Array([
		Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(0.6, 0, 1), Vector3(-0.6, 0, 1),
		Vector3(0, -0.6, 0), Vector3(0, 0.6, 0), Vector3(0, 0.6, 1), Vector3(0, -0.6, 1),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Alterar orçamento só ao trocar de perfil; amount reinicia a simulação CPU.
func set_quality(profile: String) -> void:
	if not PROFILES.has(profile):
		push_warning("Perfil de efeitos desconhecido: " + profile)
		return
	if profile == _quality:
		return
	_quality = profile
	if dust == null:
		return
	var counts: Array = PROFILES[profile]
	dust.amount = counts[0]
	smoke.amount = counts[1]
	water_spray.amount = counts[2]
	landing.amount = counts[5]
	for emitter in wind_nodes:
		emitter.amount = int(counts[3]) / 4
	for emitter in trails:
		emitter.amount = counts[4]
	if profile == "low":
		_engine_light.visible = false
		blur.visible = false

func _place_surface(emitter: CPUParticles3D, state: FXState) -> void:
	emitter.global_transform = Transform3D(Basis(Vector3.UP, state.heading), state.ground_point + Vector3.UP * 0.12)

func _fit_wind() -> void:
	var viewport_size := cam.get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	if absf(_wind_fov - cam.fov) < 0.1 and absf(_wind_aspect - aspect) < 0.001:
		return
	_wind_fov = cam.fov
	_wind_aspect = aspect
	# Dimensionar na face mais distante da caixa. Ao avançar, os riscos saem
	# para as bordas em vez de atravessar a faixa central de visão.
	var half_height := tan(deg_to_rad(cam.fov * 0.5)) * 30.0
	var half_width := half_height * aspect
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		half_width = half_height
		half_height = half_width / aspect
	for i in 4:
		var emitter := wind_nodes[i]
		if i < 2:
			emitter.position = Vector3(half_width * (0.82 if i == 1 else -0.82), 0, -26)
			emitter.emission_box_extents = Vector3(half_width * 0.18, half_height, 4)
		else:
			emitter.position = Vector3(0, half_height * (0.84 if i == 2 else -0.84), -26)
			emitter.emission_box_extents = Vector3(half_width * 0.64, half_height * 0.16, 4)

func boost_flash() -> void:
	_flash = 1.0

func landing_burst(strength: float, state: FXState) -> void:
	if landing == null or not state.running or not state.ground_valid:
		return
	if not state.on_ground or state.ground_distance >= 2.5:
		return
	if state.in_tunnel and not state.on_water:
		return
	_place_surface(landing, state)
	var impact := clampf(strength / 30.0, 0.15, 1.0)
	landing.color = Color(0.68, 0.9, 1.0, 0.38 * impact) if state.on_water else Color(0.96, 0.85, 0.66, 0.34 * impact)
	landing.initial_velocity_min = 3.0 + impact * 3.0
	landing.initial_velocity_max = 6.0 + impact * 8.0
	landing.scale_amount_min = 0.35
	landing.scale_amount_max = (0.8 if state.on_water else 1.7) * impact
	landing.restart()
	landing.emitting = true

func update_state(state: FXState, delta: float) -> void:
	if player == null:
		return
	_time += delta
	_flash = move_toward(_flash, 0.0, 3.0 * delta)
	var ratio := clampf(state.speed_ratio, 0.0, 1.0)
	var boost := clampf(state.boost_ratio, 0.0, 1.0) if state.running else 0.0
	var ground_fade := 0.0
	if state.ground_valid:
		ground_fade = 1.0 - smoothstep(1.1, 2.5, state.ground_distance)
		for emitter in [dust, smoke, water_spray]:
			_place_surface(emitter, state)
	var surface_active := state.running and state.on_ground and ground_fade > 0.0 and state.speed_mps > 25.0
	var surface_strength := ground_fade * smoothstep(0.2, 0.8, ratio)
	dust.emitting = surface_active and not state.on_water and not state.in_tunnel
	smoke.emitting = dust.emitting and state.drifting
	water_spray.emitting = surface_active and state.on_water
	dust.color = Color(0.96, 0.85, 0.66, 0.24 * surface_strength)
	smoke.color = Color(0.96, 0.85, 0.66, 0.32 * surface_strength)
	water_spray.scale_amount_min = 0.22
	water_spray.color = Color(0.68, 0.9, 1.0, 0.32 * surface_strength)
	dust.scale_amount_max = 0.7 + 0.9 * surface_strength
	smoke.scale_amount_max = 0.9 + 1.2 * surface_strength
	water_spray.scale_amount_max = 0.4 + 0.6 * surface_strength
	_fit_wind()
	var wind_strength := smoothstep(0.6, 1.0, ratio) if state.running else 0.0
	for emitter in wind_nodes:
		emitter.emitting = wind_strength > 0.001
		emitter.color = Color(0.85, 0.94, 1.0, (0.22 + _flash * 0.08) * wind_strength)
		emitter.initial_velocity_min = 25.0 + ratio * 30.0
		emitter.initial_velocity_max = 35.0 + ratio * 40.0
	var target_thrust := 0.0
	if state.running:
		target_thrust = 0.2 + 0.65 * clampf(state.throttle, 0.0, 1.0) + 0.35 * boost + 0.15 * _flash
	_thrust = lerpf(_thrust, target_thrust, 1.0 - exp(-8.0 * delta))
	var pulse := 1.0 + 0.035 * sin(_time * 31.0) + 0.015 * sin(_time * 47.0)
	for i in flame_nodes.size():
		var flame := flame_nodes[i]
		flame.visible = _thrust > 0.01
		flame.scale = Vector3(0.75 + 0.25 * _thrust, 0.75 + 0.25 * _thrust, maxf(0.05, (0.8 + _thrust * 4.5) * pulse))
		_flame_materials[i].set_shader_parameter("thrust", _thrust)
		_flame_materials[i].set_shader_parameter("boost", boost)
	for emitter in trails:
		emitter.emitting = state.running and _thrust > 0.05
		emitter.color = Color(1.0, 0.52 + 0.18 * boost, 0.24 + 0.3 * boost, minf(0.5, _thrust * 0.4))
		emitter.scale_amount_min = 0.12 + _thrust * 0.12
		emitter.scale_amount_max = 0.2 + _thrust * 0.18
	_engine_light.visible = _quality != "low" and _thrust > 0.01
	_engine_light.light_energy = _thrust * 1.6 * pulse
	_engine_light.light_color = Color(1.0, 0.58 + boost * 0.18, 0.3 + boost * 0.2)
	var blur_strength := (0.025 + 0.01 * boost) * smoothstep(0.75, 1.0, ratio) if state.running else 0.0
	blur.visible = blur_enabled and _quality != "low" and blur_strength > 0.0001
	(blur.material as ShaderMaterial).set_shader_parameter("strength", blur_strength)
	(blur.material as ShaderMaterial).set_shader_parameter("boost", boost)
	if not state.running:
		landing.emitting = false

## Respawn e viagem: descartar partículas antigas junto com os pulsos visuais.
func reset() -> void:
	_flash = 0.0
	_thrust = 0.0
	_time = 0.0
	for emitter in particle_nodes:
		emitter.restart()
		emitter.emitting = false
	for flame in flame_nodes:
		flame.visible = false
	for material in _flame_materials:
		material.set_shader_parameter("thrust", 0.0)
	_engine_light.visible = false
	blur.visible = false
	(blur.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
