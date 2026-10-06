extends Node
## Efeitos de velocidade: riscos de vento passando pela câmera, poeira levantada,
## rastro brilhante das turbinas e borrão radial nas bordas da tela.

var player: Node3D
var cam: Camera3D
var streaks: CPUParticles3D
var dust: CPUParticles3D
var trail: CPUParticles3D
var blur_layer: CanvasLayer
var blur: ColorRect
var blur_enabled := true

func setup(p: Node3D, c: Camera3D) -> void:
	player = p
	cam = c
	_make_streaks()
	_make_dust()
	_make_trail()
	_make_blur()

func _unshaded(color: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.disable_receive_shadows = true
	return m

func _fade_ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.0))
	g.add_point(0.15, c)
	g.add_point(0.7, c)
	return g

func _make_streaks() -> void:
	streaks = CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.045, 0.045, 4.0)
	bm.material = _unshaded(Color(1, 1, 1, 0.55), true)
	streaks.mesh = bm
	streaks.amount = 110
	streaks.lifetime = 0.55
	streaks.local_coords = true
	streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	streaks.emission_box_extents = Vector3(16.0, 8.0, 30.0)
	streaks.position = Vector3(0.0, 0.0, -52.0)
	streaks.direction = Vector3(0, 0, 1)
	streaks.spread = 0.0
	streaks.gravity = Vector3.ZERO
	streaks.initial_velocity_min = 90.0
	streaks.initial_velocity_max = 140.0
	streaks.color_ramp = _fade_ramp(Color(1, 0.98, 0.92, 0.5))
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.emitting = false
	cam.add_child(streaks)

func _make_dust() -> void:
	dust = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := _unshaded(Color(0.96, 0.85, 0.66, 0.45), false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	dust.mesh = q
	dust.amount = 70
	dust.lifetime = 0.9
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.6, 0.1, 0.6)
	dust.position = Vector3(0.0, 0.2, 2.2)
	dust.direction = Vector3(0, 0.35, 1)
	dust.spread = 25.0
	dust.gravity = Vector3(0, -2.0, 0)
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 12.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 2.2
	dust.color_ramp = _fade_ramp(Color(0.96, 0.85, 0.66, 0.4))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.emitting = false
	player.add_child(dust)

func _make_trail() -> void:
	trail = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _unshaded(Color(0.5, 0.95, 1.0, 0.8), true)
	trail.mesh = sm
	trail.amount = 90
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	trail.emission_points = PackedVector3Array([Vector3(-1.5, 1.6, 1.9), Vector3(1.5, 1.6, 1.9), Vector3(0.0, 1.6, 2.1)])
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 4.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 2.0
	trail.initial_velocity_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	trail.scale_amount_curve = curve
	trail.color_ramp = _fade_ramp(Color(0.55, 0.95, 1.0, 0.7))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.emitting = false
	player.add_child(trail)

func _make_blur() -> void:
	blur_layer = CanvasLayer.new()
	blur_layer.layer = 0
	add_child(blur_layer)
	blur = ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/speed_blur.gdshader")
	blur.material = mat
	blur.visible = false
	blur_layer.add_child(blur)

func update(running: bool, speed: float, frac: float, in_tunnel: bool) -> void:
	if player == null:
		return
	streaks.emitting = running
	streaks.initial_velocity_min = speed * 1.4 + 30.0
	streaks.initial_velocity_max = speed * 1.9 + 40.0
	dust.emitting = running and not in_tunnel
	trail.emitting = running
	var s := (0.012 + 0.06 * pow(frac, 1.3)) if running else 0.0
	blur.visible = blur_enabled and s > 0.005
	if blur.visible:
		(blur.material as ShaderMaterial).set_shader_parameter("strength", s)
