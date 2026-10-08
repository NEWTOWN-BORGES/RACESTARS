extends Node3D
## Motes próximos do jogador. Partículas antigas ficam no mundo, sem arrastar o cenário.
var dust: CPUParticles3D
var _material: ShaderMaterial
var _previous := Vector3.INF

func _ready() -> void:
	dust = CPUParticles3D.new()
	dust.name = "AmbientDust"
	dust.emitting = false
	dust.amount = 36
	dust.lifetime = 4.0
	dust.preprocess = 1.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(22, 6, 22)
	dust.direction = Vector3(1, 0.15, 0.4).normalized()
	dust.spread = 25
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.25
	dust.initial_velocity_max = 1.2
	dust.scale_amount_min = 0.015
	dust.scale_amount_max = 0.07
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.2, 0.75, 1])
	gradient.colors = PackedColorArray([Color(1,1,1,0), Color.WHITE, Color.WHITE, Color(1,1,1,0)])
	dust.color_ramp = gradient
	var mesh := QuadMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/ambient_dust.gdshader")
	mesh.material = _material
	dust.mesh = mesh
	add_child(dust)

func set_quality(quality: String) -> void:
	dust.amount = 16 if quality == "mobile" else (64 if quality == "ultra" else 36)

func update_environment(player: Node3D, cave: bool) -> void:
	var p := player.global_position
	if _previous.is_finite() and p.distance_to(_previous) > 120.0:
		dust.restart()
	_previous = p
	global_position = p + Vector3.UP * 3.0
	_material.set_shader_parameter("tint", Color(0.64, 0.8, 0.88, 0.10) if cave else Color(0.95, 0.82, 0.56, 0.12))
	dust.emitting = not player.on_water and (cave or p.y < player.ground_point.y + 12.0) and player.ground_valid
