extends Node3D
## Seguimento independente da nave; o braço resolve a colisão antes de renderizar.

const FXState = preload("res://scripts/speed_fx_state.gd")
const FOLLOW_HEIGHT := 2.4
const ARM_MARGIN := 0.30
const MAX_OFFSET := 0.08

@export_range(0.0, 1.0, 0.05) var shake_intensity := 1.0

var player: Node3D
var first_person := false:
	set(value):
		if first_person == value:
			return
		first_person = value
		if is_node_ready() and is_instance_valid(player):
			snap()

@onready var follow: Node3D = $FollowPivot
@onready var rotation_pivot: Node3D = $FollowPivot/RotationPivot
@onready var arm: SpringArm3D = $FollowPivot/RotationPivot/SpringArm3D
@onready var camera: Camera3D = $FollowPivot/RotationPivot/SpringArm3D/Camera3D

var _state: FXState
var _snap_state := FXState.new()
var _noise := FastNoiseLite.new()
var _snap_shape := SphereShape3D.new()
var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _shake := 0.0
var _kick := 0.0
var _t := 0.0

func _ready() -> void:
	# Player (0) -> Race/amostra (10) -> pivôs (20) -> braço interno (30).
	process_physics_priority = 20
	arm.process_physics_priority = 30
	arm.collision_mask = 1
	arm.margin = ARM_MARGIN
	_noise.seed = 417
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	# Só usada no snap: envolve conservadoramente o plano próximo em paisagem.
	_snap_shape.radius = 0.60
	arm.set_physics_process_internal(false)
	set_physics_process(false)

func setup(target: Node3D) -> void:
	player = target
	arm.clear_excluded_objects()
	if player is CollisionObject3D:
		arm.add_excluded_object(player.get_rid())
	set_physics_process(true)
	snap()

func update_state(state: FXState, _dt: float) -> void:
	# A amostra é reutilizada pela corrida. Aplicar somente no passo físico.
	_state = state

func snap() -> void:
	if not is_node_ready() or not is_instance_valid(player):
		return
	# Não reutilizar a posição de antes de viajar/renascer.
	_snap_state.capture(player, false)
	_state = _snap_state
	_yaw = _state.heading
	_pitch = _target_pitch(_state.pitch)
	_roll = 0.0
	_shake = 0.0
	_kick = 0.0
	_t = 0.0
	transform = Transform3D.IDENTITY
	follow.transform = Transform3D.IDENTITY
	rotation_pivot.transform = Transform3D.IDENTITY
	arm.transform = Transform3D.IDENTITY
	camera.transform = Transform3D.IDENTITY
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	arm.set_physics_process_internal(not first_person)
	if first_person:
		arm.spring_length = 0.0
		_apply_cockpit()
	else:
		follow.global_position = _state.position + Vector3.UP * FOLLOW_HEIGHT
		rotation_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
		arm.spring_length = lerpf(19.0, 17.0, _state.speed_ratio)
	camera.fov = _target_fov(_state)
	if not first_person:
		_snap_arm_position()
	reset_physics_interpolation()

func toggle() -> void:
	first_person = not first_person

func shake(amount := 0.8) -> void:
	_shake = maxf(_shake, clampf(amount, 0.0, 1.5))

func kick(amount := 1.0) -> void:
	_kick = maxf(_kick, clampf(amount, 0.0, 1.5))

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player) or _state == null:
		return
	_t += dt
	_shake = move_toward(_shake, 0.0, 1.8 * dt)
	_kick = move_toward(_kick, 0.0, 2.5 * dt)
	if first_person:
		_apply_cockpit()
	else:
		follow.global_position = follow.global_position.lerp(
			_state.position + Vector3.UP * FOLLOW_HEIGHT, 1.0 - exp(-10.0 * dt))
		_yaw = lerp_angle(_yaw, _state.heading, 1.0 - exp(-5.0 * dt))
		_pitch = lerpf(_pitch, _target_pitch(_state.pitch), 1.0 - exp(-4.0 * dt))
		var roll_target := _state.steering * deg_to_rad(3.0)
		roll_target *= 1.0 if _state.on_ground else 0.4
		_roll = lerpf(_roll, roll_target, 1.0 - exp(-6.0 * dt))
		rotation_pivot.rotation = Vector3(_pitch, _yaw, _roll)
		arm.spring_length = lerpf(arm.spring_length,
			lerpf(19.0, 17.0, _state.speed_ratio), 1.0 - exp(-5.0 * dt))
	camera.fov = lerpf(camera.fov, _target_fov(_state), 1.0 - exp(-5.0 * dt))
	_apply_shake()

func _target_pitch(visual_pitch: float) -> float:
	return clampf(deg_to_rad(-6.0) + visual_pitch * 0.6,
		deg_to_rad(-25.0), deg_to_rad(25.0))

func _target_fov(state: FXState) -> float:
	var curve := pow(clampf(state.speed_ratio, 0.0, 1.0), 2.4)
	if first_person:
		return clampf(78.0 + 14.0 * curve + 3.0 * state.boost_ratio + _kick,
			78.0, 95.0)
	return clampf(72.0 + 16.0 * curve + 5.0 * state.boost_ratio + 2.0 * _kick,
		72.0, 93.0)

func _apply_cockpit() -> void:
	var model: Node3D = player.model
	global_transform = Transform3D(
		model.global_basis * Basis(Vector3.RIGHT, -0.06),
		model.global_transform * Vector3(0.0, 2.55, 0.9))

func _apply_shake() -> void:
	var hum := 0.0
	if _state.running:
		hum = 0.034 * _state.speed_ratio
		hum *= 1.0 if _state.on_ground else 0.25
	var amount := (hum + _shake * 0.045) * shake_intensity
	amount *= 0.35 if first_person else 1.0
	camera.h_offset = clampf(_noise.get_noise_1d(_t * 14.0) * amount, -MAX_OFFSET, MAX_OFFSET)
	camera.v_offset = clampf(_noise.get_noise_1d(_t * 14.0 + 73.0) * amount, -MAX_OFFSET, MAX_OFFSET)
	camera.rotation.z = _noise.get_noise_1d(_t * 11.0 + 191.0) * amount * 0.14

func _snap_arm_position() -> void:
	# O braço normalmente escreve a posição local no seu passo interno. No snap
	# precisamos de uma posição válida já nesta frame, antes desse passo ocorrer.
	# Uma varredura conservadora evita mostrar a câmera do outro lado de uma parede.
	arm.force_update_transform()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _snap_shape
	query.transform = arm.global_transform
	query.motion = arm.global_basis.z * arm.spring_length
	query.collision_mask = arm.collision_mask
	query.margin = ARM_MARGIN
	if player is CollisionObject3D:
		query.exclude = [player.get_rid()]
	var space := get_world_3d().direct_space_state
	var distance := 0.0
	# cast_motion ignora formas já sobrepostas na origem; nesse caso ficar junto
	# da âncora é mais seguro que atravessar a parede.
	if space.intersect_shape(query, 1).is_empty():
		var fractions := space.cast_motion(query)
		distance = maxf(0.0, arm.spring_length * fractions[0] - ARM_MARGIN)
	camera.position = Vector3(0.0, 0.0, distance)
