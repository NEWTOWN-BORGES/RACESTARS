extends Node3D
## Veículo de outro jogador (PvP local): desenhado a partir do estado que chega pela rede,
## um pouco no passado (~0,12 s) e interpolado, para andar suave mesmo com pacotes atrasados.
## Não tem colisão: os veículos atravessam-se (como fantasmas).

const DELAY := 0.12

var player_id := 0
var player_name := ""
var color := Color.WHITE
var progress := 0.0
var finished_time := 0.0
var speed := 0.0
var _buf: Array = []      # [{t, pos, heading, quat, speed}]
var _clock := 0.0
var model: Node3D
var label: Label3D

func setup(id: int, pname: String, c: Color) -> void:
	player_id = id
	player_name = pname
	color = c
	model = preload("res://assets/models/vespa.glb").instantiate()
	add_child(model)
	tint(model, c)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.6
	light.omni_range = 10.0
	light.position = Vector3(0, 1.6, 1.0)
	add_child(light)
	label = Label3D.new()
	label.text = pname
	label.font_size = 96
	label.pixel_size = 0.04
	label.outline_size = 18
	label.modulate = c.lightened(0.3)
	label.outline_modulate = Color(0.1, 0.05, 0.02)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 7.0, 0)
	label.fixed_size = false
	add_child(label)

## Pinta um veículo com a cor do jogador (camada aditiva por cima das cores do modelo).
static func tint(node: Node, c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35)
	_apply_overlay(node, mat)

static func _apply_overlay(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = mat
	for ch in n.get_children():
		_apply_overlay(ch, mat)

func push_state(s: PackedFloat32Array) -> void:
	if s.size() < 12:
		return
	if not _buf.is_empty() and _buf[-1].pos.distance_to(Vector3(s[0], s[1], s[2])) > 300.0:
		_buf.clear()   # viajou pelo mapa: salta direto para lá
	_buf.append({"t": _clock, "pos": Vector3(s[0], s[1], s[2]), "heading": s[3],
		"quat": Quaternion(s[4], s[5], s[6], s[7]).normalized(), "speed": s[8]})
	progress = s[9]
	finished_time = s[10]
	if _buf.size() > 30:
		_buf.pop_front()
	if _buf.size() == 1:
		global_position = _buf[0].pos

func _process(dt: float) -> void:
	_clock += dt
	if _buf.is_empty():
		return
	var t := _clock - DELAY
	var a: Dictionary = _buf[0]
	var b: Dictionary = _buf[_buf.size() - 1]
	for i in _buf.size() - 1:
		if _buf[i].t <= t and _buf[i + 1].t >= t:
			a = _buf[i]
			b = _buf[i + 1]
			break
	var k := 0.0 if b.t <= a.t else clampf((t - a.t) / (b.t - a.t), 0.0, 1.0)
	if t > b.t:   # sem pacotes novos: continua um bocadinho na mesma direção
		a = b
		k = 0.0
	global_position = a.pos.lerp(b.pos, k)
	rotation = Vector3(0.0, lerp_angle(a.heading, b.heading, k), 0.0)
	model.quaternion = a.quat.slerp(b.quat, k)
	model.position = model.basis * Vector3(0.0, 0.0, 4.0)
	speed = lerpf(a.speed, b.speed, k)
