extends Camera3D
## Câmera de perseguição: atrás e acima do veículo, inclina nas curvas e abre o
## campo de visão com a velocidade.

const OFFSET := Vector3(0.0, 4.4, 10.5)

var player: Node3D
var _shake := 0.0

func snap() -> void:
	global_position = player.global_position + OFFSET
	look_at(player.global_position + Vector3(0, 1.6, -16), Vector3.UP)

func shake(amount := 0.8) -> void:
	_shake = amount

func _process(dt: float) -> void:
	if player == null:
		return
	var p := player.global_position
	var target := p + OFFSET
	var pos := global_position
	pos.x = lerpf(pos.x, target.x, 1.0 - exp(-dt * 6.0))
	pos.y = lerpf(pos.y, target.y, 1.0 - exp(-dt * 6.0))
	pos.z = target.z
	global_position = pos
	look_at(p + Vector3(player.lateral_velocity * 0.12, 1.6, -16.0), Vector3.UP)
	rotate_object_local(Vector3.FORWARD, -player.steer_visual * deg_to_rad(5.0))
	fov = lerpf(68.0, 84.0, player.speed_fraction())
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 1.8)
		h_offset = randf_range(-1.0, 1.0) * _shake * 0.4
		v_offset = randf_range(-1.0, 1.0) * _shake * 0.4
	else:
		h_offset = 0.0
		v_offset = 0.0
