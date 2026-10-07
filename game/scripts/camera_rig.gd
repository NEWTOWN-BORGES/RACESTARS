extends Camera3D
## Câmera: perseguição baixa atrás do veículo (padrão) ou primeira pessoa (cabine).
## Abre o campo de visão e treme mais quanto maior a velocidade.

var player: Node3D
var first_person := false
var _yaw := 0.0
var _shake := 0.0
var _kick := 0.0
var _t := 0.0
var _pitch := 0.0

func snap() -> void:
	_yaw = player.heading
	_process(0.0)

func shake(amount := 0.8) -> void:
	_shake = amount

func kick(amount := 1.0) -> void:
	_kick = maxf(_kick, amount)

func toggle() -> void:
	first_person = not first_person

func _process(dt: float) -> void:
	if player == null:
		return
	_t += dt
	var f: float = player.speed_fraction()
	var p: Vector3 = player.global_position
	if first_person:
		var mb: Basis = player.model.global_basis
		global_position = player.model.global_position + mb * Vector3(0.0, 2.55, 0.9)
		global_basis = mb * Basis(Vector3.RIGHT, -0.06)
		fov = lerpf(78.0, 96.0, f)
	else:
		_yaw = lerp_angle(_yaw, player.heading, 1.0 - exp(-dt * 5.0))
		var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
		var dist := lerpf(19.0, 16.0, f)
		var height := lerpf(5.4, 4.3, f)
		# a câmara acompanha a inclinação: sobe atrás nas descidas e olha para cima nas subidas
		_pitch = lerpf(_pitch, clampf(player.visual_pitch, -0.6, 0.6), 1.0 - exp(-dt * 4.0)) if dt > 0.0 else player.visual_pitch
		var target := p + back * dist * cos(_pitch * 0.7) + Vector3(0, height - sin(_pitch * 0.7) * dist, 0)
		global_position = global_position.lerp(target, 1.0 - exp(-dt * 12.0)) if dt > 0.0 else target
		var look := p - back * 26.0 + Vector3(0, 2.4 + tan(_pitch * 0.6) * 26.0, 0)
		look_at(look, Vector3.UP)
		rotate_object_local(Vector3.BACK, player.steer_visual * deg_to_rad(4.0))
		fov = lerpf(72.0, 90.0, f)
	_kick = maxf(0.0, _kick - dt * 2.5)
	fov += _kick * 5.0
	var hum: float = (0.015 + 0.06 * f) if player.running else 0.0
	_shake = maxf(0.0, _shake - dt * 1.8)
	h_offset = sin(_t * 37.0) * hum + randf_range(-1.0, 1.0) * _shake * 0.4
	v_offset = sin(_t * 53.0 + 1.3) * hum * 0.7 + randf_range(-1.0, 1.0) * _shake * 0.4
