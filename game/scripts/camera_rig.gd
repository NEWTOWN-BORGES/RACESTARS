extends Camera3D
## Câmera de perseguição: atrás e acima do veículo, inclina nas curvas e abre o
## campo de visão com a velocidade.

const OFFSET := Vector3(0.0, 4.4, 10.5)

var player: Node3D
var _shake := 0.0
var _kick := 0.0
var _t := 0.0

func kick(amount := 1.0) -> void:
	_kick = maxf(_kick, amount)

func snap() -> void:
	global_position = player.global_position + OFFSET
	look_at(player.global_position + Vector3(0, 1.6, -16), Vector3.UP)

func shake(amount := 0.8) -> void:
	_shake = amount

func _process(dt: float) -> void:
	if player == null:
		return
	var p := player.global_position
	var f: float = player.speed_fraction()
	_t += dt
	var target := p + Vector3(0.0, lerpf(OFFSET.y, 3.5, f), lerpf(OFFSET.z, 8.8, f))
	var pos := global_position
	pos.x = lerpf(pos.x, target.x, 1.0 - exp(-dt * 6.0))
	pos.y = lerpf(pos.y, target.y, 1.0 - exp(-dt * 6.0))
	pos.z = target.z
	global_position = pos
	look_at(p + Vector3(player.lateral_velocity * 0.12, 1.6, -16.0), Vector3.UP)
	rotate_object_local(Vector3.FORWARD, -player.steer_visual * deg_to_rad(5.0))
	_kick = maxf(0.0, _kick - dt * 2.5)
	fov = lerpf(70.0, 92.0, f) + _kick * 6.0
	# tremor leve que cresce com a velocidade (vibração do motor/ar)
	var hum: float = (0.02 + 0.07 * f) if player.running else 0.0
	_shake = maxf(0.0, _shake - dt * 1.8)
	h_offset = sin(_t * 37.0) * hum + randf_range(-1.0, 1.0) * _shake * 0.4
	v_offset = sin(_t * 53.0 + 1.3) * hum * 0.7 + randf_range(-1.0, 1.0) * _shake * 0.4
