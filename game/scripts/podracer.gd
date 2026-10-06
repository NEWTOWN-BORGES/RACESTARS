extends CharacterBody3D
## Veículo "Vespa": flutua sobre o terreno (e sobre a água), acelera sozinho, vira, salta,
## raspa nas paredes (perde velocidade) e bate de frente (volta ao último portão).
## Quanto mais rápido, mais aberta é a curva: nas curvas apertadas é preciso TRAVAR.
## Travar e virar ao mesmo tempo faz o veículo derrapar e fechar a curva.
## Toque: metade esquerda do ecrã = virar (◀ ▶), metade direita = travão.
## Teclado: ← → / A D para virar, ↓ / S / Espaço para travar.

signal crashed
signal scraped(strength: float)
signal landed(strength: float)

const MAX_SPEED := 125.0        # m/s (450 km/h)
const ACCEL := 19.0
const BRAKE := 52.0
const MIN_BRAKE_SPEED := 14.0
const TURN_LOW := 1.9           # rad/s quando vai devagar
const TURN_HIGH := 0.48         # rad/s à velocidade máxima (curva com ~260 m de raio)
const BRAKE_TURN := 1.45        # travar + virar fecha mais a curva
const GRIP := 2.6               # quão rápido a velocidade se alinha com o nariz (derrapagem)
const HOVER := 1.1
const SPRING := 70.0
const DAMP := 10.0
const GRAVITY := 24.0
const WATER_SPEED := 0.8        # na água anda mais devagar
const CRASH_IMPACT := 50.0      # contra rochas e peças
const CRASH_IMPACT_WALL := 72.0 # contra as encostas do terreno: mais tolerante
const MODEL_OFFSET := Vector3(0.0, 0.0, 4.0)   # o modelo nasce na cabine; recua para o centro ficar na origem

var running := false
var heading := 0.0
var vel := Vector3.ZERO
var steer := 0.0
var steer_target := 0.0
var braking := false
var on_ground := false
var on_water := false
var ground_normal := Vector3.UP
var steer_visual := 0.0
var autopilot := false
var route: Array = []
var input_left := false
var input_right := false
var _route_i := 0
var _kappa := PackedFloat32Array()
var _touches := {}
var _t := 0.0
var _air_time := 0.0

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

static func turn_rate(v: float) -> float:
	return lerpf(TURN_LOW, TURN_HIGH, clampf(v / MAX_SPEED, 0.0, 1.0))

func place(pos: Vector3, dir: Vector2, start_speed: float) -> void:
	global_position = pos + Vector3(0, HOVER + 0.5, 0)
	heading = atan2(-dir.x, -dir.y)
	vel = forward() * start_speed
	rotation = Vector3(0.0, heading, 0.0)
	ground_normal = Vector3.UP
	model.basis = Basis()
	steer = 0.0
	_route_i = _nearest_route(pos)

func set_route(r: Array) -> void:
	route = r
	_kappa.resize(route.size())
	for i in route.size():
		var a: Array = route[maxi(i - 2, 0)]
		var b: Array = route[i]
		var c: Array = route[mini(i + 2, route.size() - 1)]
		var d1 := Vector2(b[0] - a[0], b[2] - a[2])
		var d2 := Vector2(c[0] - b[0], c[2] - b[2])
		var ds := (d1.length() + d2.length()) * 0.5
		_kappa[i] = absf(d1.angle_to(d2)) / maxf(ds, 0.1) if d1.length() > 0.01 and d2.length() > 0.01 else 0.0

func _physics_process(dt: float) -> void:
	_t += dt
	if autopilot:
		_autopilot()
	else:
		_read_input()
	steer = move_toward(steer, steer_target, dt * 5.0)
	var space := get_world_3d().direct_space_state
	# chão (ou água): raio para baixo
	var from := global_position + Vector3(0, 3.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -14.0, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var ground_y := -INF
	on_water = false
	if not hit.is_empty():
		ground_y = hit.position.y
		ground_normal = ground_normal.lerp(hit.normal, 0.25).normalized()
		on_water = hit.collider != null and hit.collider.has_meta("water")
	var err := (ground_y + HOVER) - global_position.y
	if running:
		var v := speed()
		var turn := steer * turn_rate(v) * (1.0 if on_ground else 0.55)
		if braking and absf(steer) > 0.1:
			turn *= BRAKE_TURN
		heading += turn * dt
		var fwd := forward()
		var vh := Vector3(vel.x, 0.0, vel.z)
		var along := vh.dot(fwd)
		var side := vh - fwd * along
		var top := MAX_SPEED * (WATER_SPEED if on_water else 1.0)
		if braking:
			along = move_toward(along, MIN_BRAKE_SPEED, BRAKE * dt)
		elif on_ground:
			if along > top:
				along = move_toward(along, top, ACCEL * 0.6 * dt)
			else:
				along = move_toward(along, top, ACCEL * (1.0 - 0.5 * clampf(along / MAX_SPEED, 0.0, 1.0)) * dt)
		# travar solta a traseira: derrapa mais
		var grip := GRIP * (0.55 if braking else 1.0) * (1.0 if on_ground else 0.3)
		side *= exp(-grip * dt)
		vh = fwd * along + side
		vel.x = vh.x
		vel.z = vh.z
	elif on_ground:
		vel.x *= exp(-1.2 * dt)
		vel.z *= exp(-1.2 * dt)
	# flutuar: mola empurra para cima; perto do chão puxa de leve; longe = queda livre (salto)
	var was_air := not on_ground
	var vy_before := vel.y
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
	if on_ground and was_air and _air_time > 0.35 and vy_before < -8.0:
		landed.emit(-vy_before)
	_air_time = 0.0 if on_ground else _air_time + dt
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
			var col := c.get_collider()
			var limit := CRASH_IMPACT_WALL if col and col.has_meta("terrain") else CRASH_IMPACT
			if impact > limit:
				if autopilot:
					print("  colisão: ", col, " normal=", n, " impacto=", snappedf(impact, 0.1))
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
	if braking and running:
		target = target * Basis(Vector3.RIGHT, 0.06)   # nariz levanta ao travar
	if not on_ground:
		target = target * Basis(Vector3.RIGHT, clampf(vel.y / 60.0, -0.35, 0.35))
	model.basis = model.basis.slerp(target.orthonormalized(), 1.0 - exp(-dt * 8.0)).orthonormalized()
	model.position = model.basis * MODEL_OFFSET + Vector3(0.0, sin(_t * 9.0) * 0.05, 0.0)

# ------------------------------------------------------------------ entrada
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index] = e.position

func _read_input() -> void:
	var k := Input.get_axis("steer_left", "steer_right")
	var kb_brake := Input.is_action_pressed("brake")
	var size := get_viewport().get_visible_rect().size
	input_left = false
	input_right = false
	var touch_brake := false
	for pos: Vector2 in _touches.values():
		if pos.x < size.x * 0.5:
			if pos.x < size.x * 0.18:
				input_left = true
			else:
				input_right = true
		else:
			touch_brake = true
	if k < -0.01:
		input_left = true
	elif k > 0.01:
		input_right = true
	braking = kb_brake or touch_brake
	steer_target = (1.0 if input_left else 0.0) - (1.0 if input_right else 0.0)

# ------------------------------------------------------------------ piloto automático (testes)
## Desvio de obstáculos do piloto automático (testes): raios para a frente; foge para o lado
## contrário de cada obstáculo, com mais força quanto mais perto estiver.
func _avoid(v: float) -> float:
	var space := get_world_3d().direct_space_state
	var fwd := forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var reach := 30.0 + v * 1.0
	var push := 0.0
	for off: float in [-8.0, -3.0, 3.0, 8.0]:
		var from := global_position + Vector3(0, 1.3, 0) + right * off   # à altura da caixa do veículo
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * reach)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.collider != null and hit.collider.has_meta("terrain")):
			continue
		var lat: float = (hit.position - global_position).dot(right)
		var k: float = 1.0 - from.distance_to(hit.position) / reach
		push += (1.0 if lat > 0.0 else -1.0) * (0.6 + 1.6 * k)
	return clampf(push, -2.0, 2.0)

func _nearest_route(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in range(0, route.size(), 2):
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
		if n != _route_i and Vector2(r1[0] - p.x, r1[2] - p.z).length() <= Vector2(r0[0] - p.x, r0[2] - p.z).length() + 0.5:
			_route_i = n
		else:
			break
	var v := speed()
	var ahead := int((24.0 + v * 0.55) / 8.0)
	var r: Array = route[mini(_route_i + ahead, route.size() - 1)]
	var to := Vector2(r[0] - p.x, r[2] - p.z)
	var want := atan2(-to.x, -to.y)
	var diff := wrapf(want - heading, -PI, PI)
	steer_target = clampf(diff * 3.0 + _avoid(v), -1.0, 1.0)
	# trava antes das curvas fechadas: velocidade que a curva aguenta a cada distância à frente
	braking = false
	var d := 0.0
	for j in range(1, 30):
		var idx := mini(_route_i + j, route.size() - 1)
		d += 8.0
		var kap := _kappa[idx] if idx < _kappa.size() else 0.0
		if kap < 0.002:
			continue
		var allowed := MAX_SPEED
		while allowed > 20.0 and allowed * kap > turn_rate(allowed) * 0.8:
			allowed -= 5.0
		if v * v - allowed * allowed > 2.0 * BRAKE * 0.55 * d:
			braking = true
			break
