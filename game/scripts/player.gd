extends CharacterBody3D
## Veículo do jogador: anda sempre para frente (-Z), cada vez mais rápido.
## Controles: ← → / A D, ou tocar/segurar nos lados da tela (ou arrastar o dedo).

signal crashed
signal near_miss

const START_SPEED := 42.0      # m/s (~150 km/h)
const MAX_SPEED := 125.0       # m/s (~450 km/h)
const ACCEL := 1.0             # m/s por segundo
const LAT_MAX := 30.0          # velocidade lateral máxima (m/s)
const LAT_ACCEL := 140.0
const HOVER := 0.75

var running := false
var speed := 0.0
var lateral_velocity := 0.0
var steer := 0.0
var steer_visual := 0.0
var autopilot := false
var last_hit := ""
var debug_ap := false
var _ap_target := 0.0
var _ap_box := BoxShape3D.new()
var _ap_query := PhysicsShapeQueryParameters3D.new()
var world: Node = null
var _t := 0.0
var _touches := {}

@onready var model: Node3D = $Model
@onready var engine_light: OmniLight3D = $EngineLight

var _near_cd := 0.0

func _ready() -> void:
	# sensor um pouco maior que o veículo: obstáculo passando rente = "zum!"
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9.0, 2.4, 5.0)
	cs.shape = box
	cs.position = Vector3(0.0, 1.6, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_shape_entered.connect(func(_rid, _body, _bi, _li):
		if running and _near_cd <= 0.0:
			_near_cd = 0.3
			near_miss.emit())
	_ap_box.size = Vector3(3.3, 1.1, 4.2)
	_ap_query.shape = _ap_box
	_ap_query.exclude = [get_rid()]

func start() -> void:
	running = true
	speed = START_SPEED

func speed_fraction() -> float:
	return clampf((speed - START_SPEED) / (MAX_SPEED - START_SPEED), 0.0, 1.0)

func _physics_process(dt: float) -> void:
	_t += dt
	_near_cd -= dt
	steer = _autopilot() if autopilot else _read_input()
	if running:
		speed = minf(MAX_SPEED, speed + ACCEL * dt)
		var lat_max := LAT_MAX * (0.85 + 0.35 * speed_fraction())
		lateral_velocity = move_toward(lateral_velocity, steer * lat_max, LAT_ACCEL * dt)
		var hit := move_and_collide(Vector3(lateral_velocity, 0.0, -speed) * dt)
		if hit:
			last_hit = str(hit.get_collider_shape().shape.get_class()) if hit.get_collider_shape() else "?"
			running = false
			speed = 0.0
			lateral_velocity = 0.0
			crashed.emit()
	steer_visual = lerpf(steer_visual, lateral_velocity / LAT_MAX, 1.0 - exp(-dt * 7.0))
	model.rotation = Vector3(0.0, -steer_visual * 0.12, -steer_visual * 0.55)
	model.position.y = HOVER + sin(_t * 4.0) * 0.06
	engine_light.light_energy = 1.2 + 0.4 * sin(_t * 30.0) if running else 0.6

# ------------------------------------------------------------------ entrada
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = {"start": e.position, "pos": e.position}
		else:
			_touches.erase(e.index)
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index].pos = e.position

func _read_input() -> float:
	var k := Input.get_axis("steer_left", "steer_right")
	if absf(k) > 0.01:
		return k
	if _touches.is_empty():
		return 0.0
	var w := get_viewport().get_visible_rect().size.x
	var v := 0.0
	for t in _touches.values():
		var dx: float = t.pos.x - t.start.x
		if absf(dx) > 24.0:
			v += clampf(dx / (w * 0.1), -1.0, 1.0)      # arrastando: controle analógico
		else:
			v += -1.0 if t.pos.x < w * 0.5 else 1.0      # segurando: lado da tela
	return clampf(v, -1.0, 1.0)

# ------------------------------------------------------------------ piloto automático (testes e vitrine)
func _autopilot() -> float:
	## Testa faixas a cada 1,5 m: "empurra" a caixa do veículo para a frente (cast_motion)
	## e de lado até a faixa; escolhe a que deixa andar mais longe.
	if not running:
		return 0.0
	var space := get_world_3d().direct_space_state
	var tunnel_x := NAN
	if world:
		var ahead: float = world.ridge_ahead(global_position)
		if (ahead > 0.0 and ahead < 700.0) or world.in_tunnel(global_position):
			tunnel_x = world.nearest_tunnel_x(global_position.x)
	var look := 80.0 + speed * 1.3
	var lat := LAT_MAX * (0.85 + 0.35 * speed_fraction())
	var origin := global_position + Vector3(0.0, 1.6, 0.0)
	var best_x := global_position.x
	var best_score := -INF
	var cur_score := -INF
	for i in range(-16, 17):
		var off := i * 1.5
		var lane := origin + Vector3(off, 0.0, 0.0)
		var forward_from := lane
		if absf(off) > 0.3:
			# chegar na faixa: anda de lado enquanto segue em frente
			var t := absf(off) / lat + 0.15
			_ap_query.transform = Transform3D(Basis(), origin)
			_ap_query.motion = Vector3(off, 0.0, -speed * t)
			var r := space.cast_motion(_ap_query)
			if r[0] < 0.999:
				continue
			forward_from = lane + Vector3(0.0, 0.0, -speed * t)
		_ap_query.transform = Transform3D(Basis(), forward_from)
		_ap_query.motion = Vector3(0.0, 0.0, -look)
		var free: float = space.cast_motion(_ap_query)[0] * look + (origin.z - forward_from.z)
		var score := free - absf(off) * 0.15
		if not is_nan(tunnel_x):
			score -= absf(global_position.x + off - tunnel_x) * 1.0
		if absf(global_position.x + off - _ap_target) < 0.8:
			cur_score = score
		if score > best_score:
			best_score = score
			best_x = global_position.x + off
	if cur_score > -INF and cur_score >= best_score - 15.0:
		best_x = _ap_target
	_ap_target = best_x
	if debug_ap and Engine.get_physics_frames() % 15 == 0:
		print("AP x=%.1f d=%d alvo=%.1f melhor=%d" % [global_position.x, int(-global_position.z), best_x, int(best_score)])
	var dx := best_x - global_position.x
	return clampf(dx * 0.9 - lateral_velocity * 0.05, -1.0, 1.0)
