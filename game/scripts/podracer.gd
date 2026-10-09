extends CharacterBody3D
## Veículo "Vespa": flutua sobre o terreno (e sobre a água), acelera sozinho, vira, salta,
## raspa nas paredes (perde velocidade) e bate de frente (volta ao último portão).
## Quanto mais rápido, mais aberta é a curva. O TRAVÃO é um travão de mão: travar e virar
## solta a traseira e o veículo DERRAPA (fecha a curva quase sem perder velocidade);
## uma derrapagem comprida dá um pequeno impulso à saída. Bater não pára a corrida:
## ressalta e perde velocidade. Pedras no chão não são obstáculos (passa-se por cima).
## Toque: metade esquerda do ecrã = virar (◀ ▶), metade direita = travão de mão.
## Teclado: ← → / A D para virar, ↓ / S / Espaço para travar.

signal crashed                      # só para quedas no abismo (tratado pela corrida)
signal scraped(strength: float)     # raspão ou batida (o carro continua)
signal landed(strength: float)
signal boosted(amount: float)

const MAX_SPEED := 125.0        # m/s (450 km/h)
const ACCEL := 19.0
const TURN_LOW := 1.9           # rad/s quando vai devagar
const TURN_HIGH := 0.55         # rad/s à velocidade máxima (curva larga)
const GRIP := 2.6               # quão rápido a velocidade se alinha com o nariz
const HB_TURN := 2.2            # travão de mão + virar: vira muito mais
const HB_GRIP := 0.35           # ...com a traseira solta (derrapa)
const HB_DECEL := 7.0           # perde só um pouco de velocidade a derrapar
const HB_DECEL_STRAIGHT := 14.0 # travão de mão a direito: trava mais
const BOOST_MAX := 16.0         # m/s a mais depois de uma boa derrapagem
const PAD_PUSH := 18.0          # m/s que uma placa de aceleração dá
const SPEED_CAP := 160.0        # nunca passa disto (576 km/h), nem com placas e descidas
const HOVER := 1.1
const SPRING := 70.0
const DAMP := 16.75           # amortecimento quase crítico: aterra sem saltitar
const GRAVITY := 24.0
const SUPPORT_MIN_Y := 0.64    # até ~50 graus; paredes nunca sustentam a nave
const WATER_SPEED := 0.8        # na água anda mais devagar
const SOLID_MASK := 1           # camada 1: paredes, rochas altas, troncos, túneis, pontes
const RIDE_MASK := 3            # o raio do chão também vê a camada 2 (pedras baixas: passa-se por cima)
const MODEL_OFFSET := Vector3(0.0, 0.0, 4.0)   # o modelo nasce na cabine; recua para o centro ficar na origem

var running := false
var controls_blocked := false
var heading := 0.0
var vel := Vector3.ZERO
var steer := 0.0
var steer_target := 0.0
var braking := false
var on_ground := false
var on_water := false
var drifting := false
var drift_charge := 0.0
var boost := 0.0
var slip := 0.0
var ground_normal := Vector3.UP
var ground_valid := false
var ground_point := Vector3.ZERO
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
# animação do corpo (molas): inclinação para a frente/trás, para os lados e suspensão
var visual_pitch := 0.0          # + = nariz para cima
var _pitch_v := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _heave := 0.0
var _heave_v := 0.0
var _hulls: Array[CollisionShape3D] = []
var _hull_rest: Array[Transform3D] = []
var _hull_tilt := Basis.IDENTITY
var _ground_pitch := 0.0         # inclinação do chão entre a frente e a traseira

@onready var model: Node3D = $Model

func _ready() -> void:
	preload("res://scripts/model_materials.gd").apply_vehicle(model)
	motion_mode = MOTION_MODE_FLOATING
	collision_mask = SOLID_MASK
	wall_min_slide_angle = 0.0
	for child in get_children():
		if child is CollisionShape3D:
			_hulls.append(child)
			_hull_rest.append(child.transform)

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
	velocity = vel
	_touches.clear()
	braking = false
	steer_target = 0.0
	_hull_tilt = Basis.IDENTITY
	for i in _hulls.size():
		_hulls[i].transform = _hull_rest[i]
	rotation = Vector3(0.0, heading, 0.0)
	ground_normal = Vector3.UP
	ground_valid = false
	ground_point = Vector3.ZERO
	on_ground = false
	on_water = false
	drifting = false
	drift_charge = 0.0
	boost = 0.0
	_air_time = 0.0
	model.basis = Basis()
	visual_pitch = 0.0
	_pitch_v = 0.0
	_roll = 0.0
	_roll_v = 0.0
	_heave = 0.0
	_heave_v = 0.0
	_ground_pitch = 0.0
	steer = 0.0
	_route_i = _nearest_route(pos)

# placa de aceleração no chão (circuitos e reta do sal)
func pad_boost() -> void:
	if not running:
		return
	boost = maxf(boost, BOOST_MAX * 1.4)
	var f := forward()
	var along := Vector3(vel.x, 0.0, vel.z).dot(f)
	var push := clampf(MAX_SPEED + BOOST_MAX * 1.4 - along, 0.0, PAD_PUSH)   # placas seguidas não somam sem fim
	vel.x += f.x * push
	vel.z += f.z * push
	_pitch_v += 0.6           # o nariz levanta com o empurrão
	boosted.emit(boost)

func set_route(r: Array) -> void:
	route = r
	_route_i = 0
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
	# Apoio central define contacto. Normais das extremidades antecipam mudanças
	# suaves de declive sem apoiar a nave através de buracos ou em tetos.
	var hit := _support_probe(space, global_position, 3.0)
	ground_valid = not hit.is_empty()
	var ground_y := -INF
	var support_normal := Vector3.UP
	on_water = false
	if ground_valid:
		ground_point = hit.position
		ground_y = hit.position.y
		support_normal = hit.normal
		on_water = hit.collider != null and hit.collider.has_meta("water")
		var sum_normal: Vector3 = support_normal * 2.0
		for offset: float in [-4.0, 4.0]:
			var sample_pos := global_position + forward() * offset
			var end_hit := _support_probe(space, sample_pos, 6.0)
			if end_hit.is_empty():
				continue
			# Um andar por cima ou abaixo não pertence à mesma superfície.
			var expected_y: float = ground_y - support_normal.dot(sample_pos - global_position) / support_normal.y
			if absf(end_hit.position.y - expected_y) < 2.0:
				sum_normal += end_hit.normal
		support_normal = sum_normal.normalized()
		ground_normal = ground_normal.lerp(support_normal, 1.0 - exp(-18.0 * dt)).normalized()
		_ground_pitch = atan2(-support_normal.dot(forward()), support_normal.y)
	var err := (ground_y + HOVER) - global_position.y
	if running:
		var v := speed()
		var vh := Vector3(vel.x, 0.0, vel.z)
		slip = 0.0 if v < 5.0 else forward().signed_angle_to(vh, Vector3.UP)
		var hb_turning := braking and absf(steer) > 0.1
		var turn := steer * turn_rate(v) * (1.0 if on_ground else 0.25)
		if hb_turning:
			turn *= HB_TURN
		heading += turn * dt
		var fwd := forward()
		var along := vh.dot(fwd)
		var side := vh - fwd * along
		var top := MAX_SPEED * (WATER_SPEED if on_water else 1.0) + boost
		if braking:
			along = move_toward(along, 10.0, (HB_DECEL if hb_turning else HB_DECEL_STRAIGHT) * dt)
		elif on_ground:
			if along > top:
				along = move_toward(along, top, ACCEL * 0.6 * dt)
			else:
				along = move_toward(along, top, ACCEL * (1.0 - 0.5 * clampf(along / MAX_SPEED, 0.0, 1.0)) * dt)
		elif along > top:          # no ar o ar também trava um pouco o excesso
			along = move_toward(along, top, ACCEL * 0.25 * dt)
		along = minf(along, SPEED_CAP)
		# travão de mão: a traseira solta-se e a velocidade continua para onde ia (derrapagem)
		var grip := (HB_GRIP if braking else GRIP) * (1.0 if on_ground else 0.08)
		side *= exp(-grip * dt)
		# a velocidade lateral que se perde vira velocidade para a frente (derrapar não "trava"),
		# mas nunca mais do que a velocidade com que se entrou (virar não pode dar velocidade)
		var lost := side.length() * (1.0 - exp(-grip * dt))
		var along_acc := along
		along += lost * (0.85 if braking else 0.5)
		along = minf(along, maxf(along_acc, sqrt(maxf(v * v - side.length_squared(), 0.0))))
		vh = fwd * along + side
		vel.x = vh.x
		vel.z = vh.z
		# carga da derrapagem -> impulso ao largar
		drifting = braking and on_ground and v > 30.0 and absf(slip) > 0.18
		if drifting:
			drift_charge = minf(drift_charge + dt, 2.5)
		elif not braking:
			if drift_charge > 0.6:
				boost = BOOST_MAX * clampf(drift_charge / 2.0, 0.35, 1.0)
				var f2 := forward()
				vel.x += f2.x * boost * 0.6
				vel.z += f2.z * boost * 0.6
				boosted.emit(boost)
			drift_charge = 0.0
		boost = move_toward(boost, 0.0, dt * 9.0)
	elif on_ground:
		vel.x *= exp(-1.2 * dt)
		vel.z *= exp(-1.2 * dt)
	# A gravidade tira energia numa subida e devolve-a numa descida; propulsão
	# compensa gradualmente. Não converte uma queda vertical em avanço gratuito.
	if running and on_ground and ground_valid and not on_water:
		var gravity_tangent := Vector3.DOWN.slide(support_normal) * GRAVITY
		vel.x += gravity_tangent.x * dt
		vel.z += gravity_tangent.z * dt
		var horizontal_speed := speed()
		if horizontal_speed > SPEED_CAP:
			vel.x *= SPEED_CAP / horizontal_speed
			vel.z *= SPEED_CAP / horizontal_speed
	# Suspensão amortecida em relação ao declive: subir uma rampa não comprime
	# a mola como se fosse uma aterragem. A integração implícita é estável com dt maior.
	var was_air := not on_ground
	var landing_speed := maxf(0.0, -vel.dot(support_normal))
	if ground_valid and err > -0.9 and err < 3.0:
		var ground_vy := -(support_normal.x * vel.x + support_normal.z * vel.z) / support_normal.y
		var relative_vy := vel.y - ground_vy
		vel.y = ground_vy + (relative_vy + err * SPRING * dt) / (1.0 + DAMP * dt + SPRING * dt * dt)
		on_ground = true
	else:
		vel.y -= GRAVITY * dt
		on_ground = false
	if on_ground and was_air and _air_time > 0.35 and landing_speed > 8.0:
		landed.emit(landing_speed)
	if on_ground and was_air:   # a suspensão encolhe na aterragem e o nariz bate
		_heave_v -= clampf(landing_speed * 0.12, 0.0, 6.0)
		_pitch_v -= clampf(landing_speed * 0.02, 0.0, 1.2)
	# Água só é apoio: impedir atravessar a superfície numa queda rápida, sem
	# laterais sólidas nem teletransporte ao aproximar a margem.
	if on_water and ground_valid and vel.y < 0.0 and global_position.y >= ground_y:
		vel.y = maxf(vel.y, (ground_y + 0.15 - global_position.y) / dt)
	_air_time = 0.0 if on_ground else _air_time + dt
	rotation = Vector3(0.0, heading, 0.0)
	# A caixa física acompanha a superfície, independentemente da animação.
	# Uma caixa sempre horizontal enterrava o nariz nas rampas inclinadas.
	var approach_surface := ground_valid and err > -5.0 and vel.dot(support_normal) < 2.0
	var align_surface := on_ground or approach_surface
	var local_up := Basis(Vector3.UP, -heading) * support_normal if align_surface else Vector3.UP
	var tilt_pitch := atan2(-support_normal.dot(forward()), support_normal.y) if align_surface else clampf(atan2(vel.y, maxf(speed(), 12.0)), -0.22, 0.22)
	var tilt_roll := -atan2(local_up.x, local_up.y) if align_surface else 0.0
	var tilt_target := Basis.from_euler(Vector3(clampf(tilt_pitch, -0.85, 0.85), 0, clampf(tilt_roll, -0.65, 0.65)))
	_hull_tilt = _hull_tilt.slerp(tilt_target, 1.0 - exp(-18.0 * dt))
	for i in _hulls.size():
		_hulls[i].transform = Transform3D(_hull_tilt, Vector3.ZERO) * _hull_rest[i]
	var before := vel
	velocity = vel
	move_and_slide()
	vel = velocity
	# deslizar numa encosta não pode transformar a queda em velocidade para a frente
	var h_before := Vector2(before.x, before.z).length()
	var h_after := Vector2(vel.x, vel.z).length()
	if h_after > h_before + 0.05 and h_after > 0.0:
		var k := (h_before + 0.05) / h_after
		vel.x *= k
		vel.z *= k
	if running:
		# O deslizamento flutuante conserva o módulo da velocidade; reconstruir a
		# componente tangente evita que uma parede transforme impacto em aceleração.
		# Só a componente contra a parede ressalta: um raspão preserva o embalo.
		var worst := 0.0
		var wall_velocity := Vector3(before.x, 0.0, before.z)
		var touched_wall := false
		var touched_support := false
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var n := c.get_normal()
			if n.y > SUPPORT_MIN_Y:
				touched_support = true
				continue
			if n.y < -SUPPORT_MIN_Y:
				touched_support = true
				vel.y = minf(vel.y, 0.0)
				continue
			var hn := Vector3(n.x, 0.0, n.z).normalized()
			var impact := maxf(-wall_velocity.dot(hn), 0.0)
			worst = maxf(worst, impact)
			if impact > 0.0:
				touched_wall = true
				wall_velocity += hn * (impact + minf(impact * 0.18, 10.0))
		if touched_wall:
			vel.x = wall_velocity.x
			vel.z = wall_velocity.z
			# A parede não deve travar uma queda nem lançar o veículo para cima.
			if not touched_support:
				vel.y = before.y
			if wall_velocity.length() > 4.0 and worst > 20.0:
				heading = lerp_angle(heading, atan2(-wall_velocity.x, -wall_velocity.z), 0.35)
		if worst > 6.0:
			if autopilot and worst > 50.0:
				print("  batida forte: impacto=", snappedf(worst, 0.1), " em ", global_position)
			drift_charge = 0.0
			scraped.emit(worst)
	_update_visual(dt)

func _support_probe(space: PhysicsDirectSpaceState3D, p: Vector3, rise: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * rise, p + Vector3.DOWN * 14.0)
	q.exclude = [get_rid()]
	q.collision_mask = RIDE_MASK
	var hit := space.intersect_ray(q)
	# Se o raio começou acima de um teto, procurar de novo a partir da nave.
	if not hit.is_empty() and hit.position.y > global_position.y + 1.5:
		q.from = p
		hit = space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < SUPPORT_MIN_Y:
		return {}
	return hit

func _update_visual(dt: float) -> void:
	# o corpo do veículo é animado com molas (o corpo físico só gira em Y com o rumo):
	# - no chão o nariz segue a inclinação entre a frente e a traseira; no ar segue a trajetória
	# - inclina-se para dentro das curvas e acompanha o declive lateral
	# - a suspensão encolhe nas aterragens e o veículo balança um pouco
	var lat := vel.dot(forward().cross(Vector3.UP))
	steer_visual = lerpf(steer_visual, clampf(steer * 0.7 + lat / 40.0, -1.0, 1.0), 1.0 - exp(-dt * 6.0))
	var hspeed := Vector2(vel.x, vel.z).length()
	var tp: float
	if on_ground:
		tp = _ground_pitch
	else:
		tp = atan2(vel.y, maxf(hspeed, 12.0)) * 0.9
	if braking and running:
		tp -= 0.045                     # transferência de carga para o nariz
	tp = clampf(tp, -0.75, 0.75)
	_pitch_v = (_pitch_v + (tp - visual_pitch) * 90.0 * dt) / (1.0 + 15.0 * dt + 90.0 * dt * dt)
	visual_pitch += _pitch_v * dt
	var lup := (Basis(Vector3.UP, -heading) * ground_normal).normalized() if on_ground else Vector3.UP
	var tr := steer_visual * 0.4 - atan2(lup.x, lup.y)
	_roll_v = (_roll_v + (tr - _roll) * 55.0 * dt) / (1.0 + 12.0 * dt + 55.0 * dt * dt)
	_roll += _roll_v * dt
	_heave_v = (_heave_v - _heave * 90.0 * dt) / (1.0 + 14.0 * dt + 90.0 * dt * dt)
	_heave = clampf(_heave + _heave_v * dt, -1.2, 0.8)
	model.basis = (Basis(Vector3.RIGHT, visual_pitch) * Basis(Vector3.BACK, _roll)).orthonormalized()
	var bob := sin(_t * 9.0) * 0.05 + sin(_t * 23.0) * 0.02 * speed_fraction() if on_ground else sin(_t * 4.0) * 0.08
	model.position = model.basis * MODEL_OFFSET + Vector3(0.0, _heave + bob, 0.0)

# ------------------------------------------------------------------ entrada
func _input(e: InputEvent) -> void:
	# Soltar sobre um botão HUD também termina o comando iniciado na pista.
	if e is InputEventScreenTouch and not e.pressed:
		_touches.erase(e.index)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index] = e.position

func _read_input() -> void:
	if controls_blocked:
		steer_target = 0.0
		input_left = false
		input_right = false
		braking = true
		return
	var axis := Input.get_axis("steer_left", "steer_right")
	var size := get_viewport().get_visible_rect().size
	var touch_left := false
	var touch_right := false
	var touch_brake := false
	for pos: Vector2 in _touches.values():
		if pos.x < size.x * 0.5:
			if pos.x < size.x * 0.18:
				touch_left = true
			else:
				touch_right = true
		else:
			touch_brake = true
	var touch_axis := (1.0 if touch_left else 0.0) - (1.0 if touch_right else 0.0)
	# Preservar a amplitude do analógico: uma pequena inclinação dá uma curva suave.
	steer_target = clampf(-axis + touch_axis, -1.0, 1.0)
	input_left = steer_target > 0.05
	input_right = steer_target < -0.05
	braking = Input.is_action_pressed("brake") or touch_brake

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
		q.collision_mask = SOLID_MASK
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.collider != null and hit.collider.has_meta("terrain")):
			continue
		var lat: float = (hit.position - global_position).dot(right)
		var k: float = 1.0 - from.distance_to(hit.position) / reach
		push += (1.0 if lat > 0.0 else -1.0) * (0.6 + 1.6 * k)
	return clampf(push, -2.0, 2.0)

## Ponto do caminho mais perto, procurado primeiro à volta de onde já se ia: nos circuitos a rota
## repete as voltas e a largada fica junto ao fim de cada volta (não pode saltar uma volta à frente).
func _nearest_route(p: Vector3) -> int:
	if route.is_empty():
		return 0
	var best := _scan_route(p, maxi(_route_i - 150, 0), mini(_route_i + 600, route.size()))
	var r: Array = route[best]
	if Vector2(r[0] - p.x, r[2] - p.z).length() > 150.0:
		best = _scan_route(p, 0, route.size())
	return best

func _scan_route(p: Vector3, a: int, b: int) -> int:
	var best := a
	var bd := INF
	for i in range(a, b):
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
	# curvas fechadas: puxa o travão de mão (derrapa) quando a curva logo à frente é mais apertada
	# do que o veículo consegue fazer a esta velocidade
	braking = false
	for j in range(1, 10 + int(v / 12.0)):   # mais rápido = olha mais longe
		var idx := mini(_route_i + j, route.size() - 1)
		var kap := _kappa[idx] if idx < _kappa.size() else 0.0
		if v * kap > turn_rate(v) * 0.85 and absf(diff) > 0.04:
			braking = true
			break
