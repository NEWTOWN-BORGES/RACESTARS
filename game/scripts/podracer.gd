extends CharacterBody3D
## Veículo "Vespa": flutua sobre o terreno, acelera sozinho, vira, salta nas rampas,
## raspa nas paredes (perde velocidade) e bate de frente (volta ao último portão).
## Controles: segurar o lado esquerdo/direito da tela (ou arrastar); os dois lados = travar.
## Teclado: ← → / A D para virar, ↓ / S para travar.

signal crashed
signal scraped(strength: float)

const MAX_SPEED := 125.0       # m/s (450 km/h)
const ACCEL := 20.0
const BRAKE := 45.0
const TURN_LOW := 1.6          # rad/s devagar
const TURN_HIGH := 0.95        # rad/s no máximo
const GRIP := 2.6              # quão rápido a velocidade se alinha com o nariz (derrapagem)
const HOVER := 1.1
const SPRING := 70.0
const DAMP := 10.0
const GRAVITY := 24.0
const CRASH_IMPACT := 50.0     # contra rochas e peças
const CRASH_IMPACT_WALL := 72.0  # contra as encostas do terreno (desfiladeiros): mais tolerante

var running := false
var heading := 0.0
var vel := Vector3.ZERO
var steer := 0.0
var braking := false
var on_ground := false
var ground_normal := Vector3.UP
var steer_visual := 0.0
var autopilot := false
var route: Array = []
var _route_i := 0
var _touches := {}
var _t := 0.0

const MODEL_OFFSET := Vector3(0.0, 0.0, 4.0)   # o modelo nasce na cabine; recua para o centro ficar na origem

@onready var model: Node3D = $Model

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	wall_min_slide_angle = deg_to_rad(10.0)

func speed() -> float:
	return Vector2(vel.x, vel.z).length()

func speed_fraction() -> float:
	return clampf(speed() / MAX_SPEED, 0.0, 1.0)

func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))

func place(pos: Vector3, dir: Vector2, start_speed: float) -> void:
	global_position = pos + Vector3(0, HOVER + 0.5, 0)
	heading = atan2(-dir.x, -dir.y)
	vel = forward() * start_speed
	rotation = Vector3(0.0, heading, 0.0)
	ground_normal = Vector3.UP
	model.basis = Basis()
	_route_i = _nearest_route(pos)

func _physics_process(dt: float) -> void:
	_t += dt
	if autopilot:
		_autopilot()
	else:
		_read_input()
	var space := get_world_3d().direct_space_state
	# chão: raio para baixo
	var from := global_position + Vector3(0, 3.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -14.0, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var ground_y := -INF
	if not hit.is_empty():
		ground_y = hit.position.y
		ground_normal = ground_normal.slerp(hit.normal, 0.25)
	var err := (ground_y + HOVER) - global_position.y
	if running:
		var f := speed_fraction()
		var turn := steer * lerpf(TURN_LOW, TURN_HIGH, f) * (1.0 if on_ground else 0.55)
		heading += turn * dt
		var fwd := forward()
		var vh := Vector3(vel.x, 0.0, vel.z)
		var along := vh.dot(fwd)
		var side := vh - fwd * along
		if braking:
			along = move_toward(along, 15.0, BRAKE * dt)
		elif on_ground:
			along = move_toward(along, MAX_SPEED, ACCEL * (1.0 - 0.5 * f) * dt)
		side *= exp(-GRIP * (1.0 if on_ground else 0.3) * dt)
		vh = fwd * along + side
		vel.x = vh.x
		vel.z = vh.z
	elif on_ground:
		vel.x *= exp(-1.2 * dt)
		vel.z *= exp(-1.2 * dt)
	# flutuar: mola empurra para cima; perto do chão puxa de leve; longe = queda livre (salto)
	if err > 0.0:
		vel.y += (err * SPRING - vel.y * DAMP) * dt
		on_ground = true
	elif err > -0.9:
		vel.y += (err * SPRING * 0.35 - GRAVITY) * dt
		vel.y *= exp(-3.0 * dt)
		on_ground = true
	else:
		vel.y -= GRAVITY * dt
		on_ground = false
	rotation = Vector3(0.0, heading, 0.0)
	var before := vel
	velocity = vel
	move_and_slide()
	vel = velocity
	if running:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var n := c.get_normal()
			if n.y > 0.6:
				continue
			var impact := -before.dot(n)
			if impact > CRASH_IMPACT:
				running = false
				vel = Vector3.ZERO
				crashed.emit()
				break
			elif impact > 6.0:
				vel *= 1.0 - clampf(impact / 160.0, 0.0, 0.45)
				scraped.emit(impact)
	_update_visual(dt)

func _update_visual(dt: float) -> void:
	# inclinação no espaço local do corpo (o corpo só gira em Y com o rumo)
	var lat := vel.dot(forward().cross(Vector3.UP))
	steer_visual = lerpf(steer_visual, clampf(steer * 0.7 + lat / 40.0, -1.0, 1.0), 1.0 - exp(-dt * 6.0))
	var up := (ground_normal if on_ground else Vector3.UP)
	up = (Basis(Vector3.UP, -heading) * up).normalized()
	var x := up.cross(Vector3.BACK).normalized()
	var target := Basis(x, up, x.cross(up).normalized())
	target = target * Basis(Vector3.BACK, steer_visual * 0.4)
	if not on_ground:
		target = target * Basis(Vector3.RIGHT, clampf(vel.y / 60.0, -0.35, 0.35))
	model.basis = model.basis.slerp(target.orthonormalized(), 1.0 - exp(-dt * 8.0)).orthonormalized()
	model.position = model.basis * MODEL_OFFSET + Vector3(0.0, sin(_t * 9.0) * 0.05, 0.0)

# ------------------------------------------------------------------ entrada
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = {"start": e.position, "pos": e.position}
		else:
			_touches.erase(e.index)
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index].pos = e.position

func _read_input() -> void:
	var k := Input.get_axis("steer_left", "steer_right")
	braking = Input.is_action_pressed("brake")
	if absf(k) > 0.01 or braking:
		steer = -k
		return
	var w := get_viewport().get_visible_rect().size.x
	var left := false
	var right := false
	var analog := 0.0
	for t in _touches.values():
		var dx: float = t.pos.x - t.start.x
		if absf(dx) > 30.0:
			analog += clampf(dx / (w * 0.12), -1.0, 1.0)
		elif t.pos.x < w * 0.5:
			left = true
		else:
			right = true
	braking = left and right
	steer = 0.0 if braking else -(analog + (1.0 if right else 0.0) - (1.0 if left else 0.0))
	steer = clampf(steer, -1.0, 1.0)

# ------------------------------------------------------------------ piloto automático (testes)
func _nearest_route(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in range(0, route.size(), 4):
		var r: Array = route[i]
		var d := Vector2(r[0] - p.x, r[2] - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best

func _autopilot() -> void:
	if route.is_empty():
		return
	var p := global_position
	for k in 40:
		var n := mini(_route_i + 1, route.size() - 1)
		var r0: Array = route[_route_i]
		var r1: Array = route[n]
		if Vector2(r1[0] - p.x, r1[2] - p.z).length() < Vector2(r0[0] - p.x, r0[2] - p.z).length():
			_route_i = n
		else:
			break
	var ahead := int((30.0 + speed() * 0.9) / 8.0)
	var r: Array = route[mini(_route_i + ahead, route.size() - 1)]
	var to := Vector2(r[0] - p.x, r[2] - p.z)
	var want := atan2(-to.x, -to.y)
	var diff := wrapf(want - heading, -PI, PI)
	steer = clampf(diff * 2.5, -1.0, 1.0)
	braking = absf(diff) > 0.5 and speed() > 60.0
