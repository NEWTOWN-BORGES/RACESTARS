extends RefCounted
## Uma amostra do veículo para câmera, partículas e áudio. Unidades: metros e segundos.

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var heading := 0.0
var pitch := 0.0
var running := false
var speed_mps := 0.0
var speed_ratio := 0.0
var throttle := 0.0
var boost_ratio := 0.0
var steering := 0.0
var on_ground := false
var on_water := false
var drifting := false
var ground_valid := false
var ground_point := Vector3.ZERO
var ground_normal := Vector3.UP
var ground_distance := INF
var in_tunnel := false

func capture(player: Node3D, cave: bool) -> void:
	position = player.global_position
	velocity = player.vel
	heading = player.heading
	pitch = player.visual_pitch
	running = player.running
	speed_mps = player.speed()
	speed_ratio = player.speed_fraction()
	throttle = 1.0 if running and not player.braking else 0.0
	boost_ratio = clampf(player.boost / player.BOOST_MAX, 0.0, 1.0) if running else 0.0
	steering = player.steer_visual
	on_ground = player.on_ground
	on_water = player.on_water
	drifting = running and player.drifting
	ground_valid = player.ground_valid
	ground_point = player.ground_point
	ground_normal = player.ground_normal
	ground_distance = maxf(0.0, position.y - ground_point.y) if ground_valid else INF
	in_tunnel = cave
