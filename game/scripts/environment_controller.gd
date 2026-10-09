extends Node3D
## Orquestra iluminação/atmosfera independentemente das regras da corrida.
const Quality := preload("res://scripts/visual_quality.gd")
var quality := "balanced"
var environment: Environment
var sun: DirectionalLight3D
var player: Node3D
var map: Node3D
var effects: Node
var ambient: Node3D
var reflections: Node3D
var volumes: Node3D
# Nevoeiro seco, marítimo e húmido, misturado nas fronteiras das zonas existentes.
# Não é necessário recalcular o cubemap do céu quando o jogador muda de bioma.
var _region_clock := 0.0
var _region_color := Color(0.68, 0.73, 0.75)
var _region_begin := 350.0
var _region_end := 5700.0
var _region_energy := 0.56
var _scale_ceiling := 1.0
var _scale_floor := 1.0
var _frame_seconds := 0.0
var _frame_count := 0
var _recovery_windows := 0
var _warmup_seconds := 4.0
var _contact_shadow: MeshInstance3D

func setup(world: WorldEnvironment, light: DirectionalLight3D, vehicle: Node3D, level: Node3D, fx: Node, preference: String) -> void:
	environment = world.environment.duplicate(true)
	world.environment = environment
	sun = light
	player = vehicle
	map = level
	effects = fx
	ambient = preload("res://scripts/global_vfx.gd").new()
	ambient.name = "GlobalVFX"
	add_child(ambient)
	reflections = Node3D.new()
	reflections.name = "Reflection"
	add_child(reflections)
	volumes = Node3D.new()
	volumes.name = "Atmosphere"
	add_child(volumes)
	var wear := preload("res://scripts/surface_wear.gd").new()
	wear.name = "SurfaceWear"
	add_child(wear)
	wear.setup(map)
	_make_contact_shadow()
	set_quality(preference)
	update_region(player.global_position, 0.0, false, true)

func set_quality(value: String) -> void:
	quality = value if value in Quality.NAMES else "balanced"
	var high := quality == "ultra"
	var stable := quality == "stable"
	var light := quality in ["stable", "mobile"]
	RenderingServer.global_shader_parameter_set("cinematic_detail", 0.18 if stable else (0.35 if light else (1.0 if high else 0.65)))
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var version := Engine.get_version_info()
	var compat_glow := int(version.major) > 4 or int(version.minor) >= 6
	environment.glow_enabled = not light and (RenderingServer.get_current_rendering_method() != "gl_compatibility" or compat_glow)
	environment.glow_intensity = 0.35 if high else 0.22
	environment.glow_bloom = 0.015
	environment.glow_hdr_threshold = 1.2
	environment.ssao_enabled = forward and not light
	environment.ssil_enabled = forward and high
	environment.volumetric_fog_enabled = forward and high
	environment.volumetric_fog_density = 0.0015
	environment.volumetric_fog_length = 96.0
	environment.fog_enabled = true
	environment.fog_depth_curve = 1.45
	environment.fog_sun_scatter = 0.22
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.adjustment_enabled = not light
	environment.adjustment_contrast = 1.055
	environment.adjustment_saturation = 0.93
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_64 if light else (Sky.RADIANCE_SIZE_256 if high else Sky.RADIANCE_SIZE_128)
	sun.light_color = Color(1.0, 0.88, 0.71)
	sun.light_energy = 1.38
	sun.shadow_enabled = not stable
	_contact_shadow.visible = stable
	sun.directional_shadow_max_distance = 120.0 if light else (300.0 if high else 220.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if light else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 0.3 if forward and high else 0.0
	effects.set_quality("low" if stable else ("mobile" if light else "pc"))
	ambient.set_quality(quality)
	map.set_quality(quality)
	map.terrain.set_quality(quality)
	var forests := map.get_node_or_null("MegaForests")
	if forests:
		forests.set_quality(quality)
	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# Apenas o mundo 3D é escalado; interface/toques permanecem na resolução nativa.
	_scale_ceiling = clampf(600.0 / maxf(float(get_window().size.y), 1.0), 0.5, 0.8) if stable else 1.0
	_scale_floor = maxf(0.4, _scale_ceiling * 0.8) if stable else 1.0
	viewport.scaling_3d_scale = _scale_ceiling
	Engine.max_fps = 30 if stable else 0
	_frame_seconds = 0.0
	_frame_count = 0
	_recovery_windows = 0
	_warmup_seconds = 4.0
	_rebuild_local_lighting(not light, forward and high)

func adapt_performance(dt: float) -> void:
	if quality != "stable":
		return
	if _warmup_seconds > 0.0:
		_warmup_seconds -= dt
		return
	_frame_seconds += minf(dt, 0.15)
	_frame_count += 1
	if _frame_seconds < 3.0:
		return
	var frame_time := _frame_seconds / maxf(1.0, _frame_count)
	_frame_seconds = 0.0
	_frame_count = 0
	var viewport := get_viewport()
	if frame_time > 1.0 / 27.0:
		viewport.scaling_3d_scale = maxf(_scale_floor, viewport.scaling_3d_scale * 0.92)
		_recovery_windows = 0
	elif frame_time < 1.0 / 29.6:
		_recovery_windows += 1
		if _recovery_windows >= 3:
			viewport.scaling_3d_scale = minf(_scale_ceiling, viewport.scaling_3d_scale + 0.025)
			_recovery_windows = 0
	else:
		_recovery_windows = 0

func _exit_tree() -> void:
	Engine.max_fps = 0

func _make_contact_shadow() -> void:
	# Um único disco suave substitui a sombra do veículo sem um passe de shadowmap.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		for point in [Vector3.ZERO, Vector3(cos(TAU * i / 24), 0, sin(TAU * i / 24)), Vector3(cos(TAU * (i + 1) / 24), 0, sin(TAU * (i + 1) / 24))]:
			st.set_color(Color(0.05, 0.065, 0.075, 0.32 if point == Vector3.ZERO else 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(point * Vector3(5.0, 1.0, 8.0))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_contact_shadow = MeshInstance3D.new()
	_contact_shadow.name = "VehicleContactShadow"
	_contact_shadow.mesh = st.commit()
	_contact_shadow.material_override = material
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact_shadow)

func _rebuild_local_lighting(probes: bool, fog: bool) -> void:
	for child in reflections.get_children():
		child.free()
	for child in volumes.get_children():
		child.free()
	if probes:
		_add_probe("Outdoor", player.global_position + Vector3.UP * 6.0, false)
	if not map.cave_boxes.is_empty():
		var cave: Dictionary = map.cave_boxes[0]
		var center: Vector3 = cave.origin + cave.fwd * minf(float(cave.len) * 0.5, 45.0)
		center.y = float(cave.top) - 8.0
		if probes:
			_add_probe("Interior", center, true)
		if fog:
			var volume := FogVolume.new()
			volume.name = "CaveMist"
			volume.position = center
			volume.size = Vector3(30, 14, 50)
			var material := FogMaterial.new()
			material.density = 0.025
			material.albedo = Color(0.65, 0.73, 0.8)
			volume.material = material
			volumes.add_child(volume)

func _add_probe(label: String, pos: Vector3, interior: bool) -> void:
	var probe := ReflectionProbe.new()
	probe.name = label
	probe.position = pos
	probe.size = Vector3(110, 48, 110) if not interior else Vector3(40, 22, 55)
	probe.max_distance = 90.0
	probe.interior = interior
	probe.box_projection = interior
	probe.intensity = 0.45 if interior else 0.6
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.enable_shadows = false
	reflections.add_child(probe)

func update_environment(cave: bool, dt: float) -> void:
	update_region(player.global_position, dt, cave)
	ambient.update_environment(player, cave)
	_contact_shadow.visible = quality == "stable" and player.on_ground and player.ground_valid and player.ground_normal.y > 0.65
	if _contact_shadow.visible:
		var normal: Vector3 = player.ground_normal
		var forward: Vector3 = player.forward().slide(normal).normalized()
		_contact_shadow.global_transform = Transform3D(Basis(normal.cross(forward), normal, forward), player.ground_point + normal * 0.07)

func update_region(pos: Vector3, dt: float, cave := false, immediate := false) -> void:
	_region_clock -= dt
	if _region_clock <= 0.0 or immediate:
		_region_clock = 0.5
		var color := Color(0, 0, 0, 0)
		var begin := 0.0
		var end := 0.0
		var energy := 0.0
		var total := 0.0
		for zone in map.info.zones:
			var distance := Vector2(pos.x - float(zone.c[0]), pos.z - float(zone.c[1])).length_squared()
			var weight := 1.0 / pow(1.0 + distance / 1600000.0, 2.0)
			var palette := _biome_atmosphere(String(zone.biome))
			color += (palette[0] as Color) * weight
			begin += float(palette[1]) * weight
			end += float(palette[2]) * weight
			energy += float(palette[3]) * weight
			total += weight
		_region_color = color / maxf(total, 0.000001)
		_region_begin = begin / maxf(total, 0.000001)
		_region_end = end / maxf(total, 0.000001)
		_region_energy = energy / maxf(total, 0.000001)
	var blend := 1.0 if immediate else 1.0 - exp(-dt * 1.5)
	environment.fog_light_color = environment.fog_light_color.lerp(_region_color, blend)
	environment.fog_depth_begin = lerpf(environment.fog_depth_begin, _region_begin, blend)
	environment.fog_depth_end = lerpf(environment.fog_depth_end, minf(_region_end, 3200.0) if quality == "stable" else _region_end, blend)
	environment.ambient_light_energy = lerpf(environment.ambient_light_energy, 0.30 if cave else _region_energy, blend)

func _biome_atmosphere(biome: String) -> Array:
	match biome:
		"sandstone", "red", "desert", "arches", "savanna":
			return [Color(0.76, 0.66, 0.52), 320.0, 5800.0, 0.54]
		"jungle", "forest", "oasis":
			return [Color(0.53, 0.68, 0.66), 180.0, 4400.0, 0.57]
		"coast", "lagoon", "salt":
			return [Color(0.65, 0.77, 0.81), 460.0, 6500.0, 0.60]
		_:
			return [Color(0.62, 0.70, 0.77), 380.0, 5700.0, 0.56]
