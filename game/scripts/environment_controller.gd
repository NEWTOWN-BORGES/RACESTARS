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
	set_quality(preference)
	update_region(player.global_position, 0.0, false, true)

func set_quality(value: String) -> void:
	quality = value if value in Quality.NAMES else "balanced"
	var high := quality == "ultra"
	var light := quality == "mobile"
	RenderingServer.global_shader_parameter_set("cinematic_detail", 0.35 if light else (1.0 if high else 0.65))
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
	sun.directional_shadow_max_distance = 120.0 if light else (300.0 if high else 220.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if light else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 0.3 if forward and high else 0.0
	effects.set_quality("mobile" if light else "pc")
	ambient.set_quality(quality)
	get_viewport().msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_2X
	_rebuild_local_lighting(not light, forward and high)

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
	environment.fog_depth_end = lerpf(environment.fog_depth_end, _region_end, blend)
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
