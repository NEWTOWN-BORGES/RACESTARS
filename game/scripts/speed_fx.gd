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
var smoke: CPUParticles3D      # fumo/areia da derrapagem
var _flash := 0.0

func setup(p: Node3D, c: Camera3D) -> void:
	player = p
	cam = c
	_make_streaks()
	_make_dust()
	_make_trail()
	_make_smoke()
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
	q.size = Vector2(2.4, 2.4)
	var m := _unshaded(Color(0.96, 0.85, 0.66, 0.45), false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# nuvem redonda e macia (sem textura ficariam quadrados)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	q.material = m
	dust.mesh = q
	dust.amount = 90
	dust.lifetime = 0.45
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(3.2, 0.1, 5.0)
	dust.position = Vector3(0.0, -0.6, 2.0)
	dust.direction = Vector3(0, 0.5, 1)
	dust.spread = 40.0
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
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _unshaded(Color(1.0, 0.5, 0.22, 0.6), true)
	trail.mesh = sm
	trail.amount = 90
	trail.lifetime = 0.16
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	# bocais de escape das duas turbinas da Vespa
	trail.emission_points = PackedVector3Array([Vector3(-2.3, 1.3, 0.7), Vector3(2.3, 1.3, 0.7)])
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 4.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 2.0
	trail.initial_velocity_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	trail.scale_amount_curve = curve
	trail.color_ramp = _fade_ramp(Color(1.0, 0.5, 0.25, 0.55))
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

func _make_smoke() -> void:
	smoke = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0)
	var m := _unshaded(Color(1, 0.95, 0.85, 0.5), false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	m.albedo_texture = tex
	q.material = m
	smoke.mesh = q
	smoke.amount = 60
	smoke.lifetime = 0.7
	smoke.local_coords = false
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	smoke.emission_points = PackedVector3Array([Vector3(-2.6, 0.2, 5.5), Vector3(2.6, 0.2, 5.5)])
	smoke.direction = Vector3(0, 0.6, 1)
	smoke.spread = 35.0
	smoke.gravity = Vector3(0, 1.5, 0)
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 9.0
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.4
	smoke.color_ramp = _fade_ramp(Color(0.95, 0.88, 0.74, 0.55))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.emitting = false
	player.add_child(smoke)

## Clarão das turbinas quando sai o impulso da derrapagem.
func boost_flash() -> void:
	_flash = 1.0

func update(running: bool, speed: float, frac: float, in_tunnel: bool, on_ground := true) -> void:
	if player == null:
		return
	smoke.emitting = running and player.drifting
	_flash = maxf(0.0, _flash - 0.03)
	trail.scale_amount_min = 1.0 + _flash * 1.8
	trail.scale_amount_max = 1.0 + _flash * 1.8
	streaks.emitting = running
	streaks.initial_velocity_min = speed * 1.4 + 30.0
	streaks.initial_velocity_max = speed * 1.9 + 40.0
	dust.emitting = running and on_ground and not in_tunnel and speed > 25.0
	trail.emitting = running
	var s := (0.012 + 0.06 * pow(frac, 1.3)) if running else 0.0
	blur.visible = blur_enabled and s > 0.005
	if blur.visible:
		(blur.material as ShaderMaterial).set_shader_parameter("strength", s)
