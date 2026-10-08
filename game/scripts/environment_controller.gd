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

func set_quality(value: String) -> void:
	quality = value if value in Quality.NAMES else "balanced"
	var high := quality == "ultra"
	var light := quality == "mobile"
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
	environment.fog_depth_begin = 700.0
	environment.fog_depth_end = 7000.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.adjustment_enabled = not light
	environment.adjustment_contrast = 1.035
	environment.adjustment_saturation = 0.98
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_64 if light else (Sky.RADIANCE_SIZE_256 if high else Sky.RADIANCE_SIZE_128)
	sun.light_color = Color(1.0, 0.90, 0.77)
	sun.light_energy = 1.25
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
	environment.ambient_light_energy = move_toward(environment.ambient_light_energy, 0.30 if cave else 0.65, dt * 1.2)
	ambient.update_environment(player, cave)
