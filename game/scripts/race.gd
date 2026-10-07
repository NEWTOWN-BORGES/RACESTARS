extends Node3D
## Mundo de 24 km com dois modos, sozinho ou PvP local (vários telemóveis na mesma rede):
##  - EXPLORAR: andar à vontade, sem relógio; o MAPA permite viajar para qualquer sítio.
##  - CORRIDA: circuito de A até B que passa por todas as zonas, com portões em ordem e
##    vários caminhos/atalhos em cada trecho.
## Bater não pára; ao cair num abismo volta-se ao caminho mais perto de onde se estava.
##
## Argumentos de teste (depois de `--`):
##   --mode=explorar|corrida  --autoplay  --variant=N|sorte  --log  --shots=2,6  --shotdir=/caminho
##   --quit=SEG  --cp=N (começa no portão N)  --at=x,z,dx,dz[,y]  --fpv  --nohud  --travel=x,z

enum State { WAIT, COUNTDOWN, RACE, FINISHED, FREE }

const RemoteRacer = preload("res://scripts/remote_racer.gd")
const SAVE_PATH := "user://save.cfg"
const SAVE_KEY := "race_v5"
const SUN_AZIMUTH := 35.0
const SUN_ELEVATION := 42.0
const HINT := "Esquerda do ecrã: virar   ·   direita: TRAVÃO DE MÃO (travar + virar = derrapar)"
const HINT_EXPLORE := "Explora à vontade   ·   MAPA: ver o mundo e viajar   ·   travar + virar = derrapar"

var state := State.COUNTDOWN
var info: Dictionary
var t_race := 0.0
var t_count := 3.6
var best := 0.0
var next_cp := 0
var respawn_timer := -1.0
var elapsed := 0.0
var args := {}
var shots: Array = []
var _last_count := 4
var fx: Node
var audio: Node
var _fps_acc := 0.0
var _fps_n := 0
var _quality := 2
var mp := false                    # corrida PvP
var remotes := {}                  # id -> remote_racer
var results := {}                  # id -> tempo de chegada
var _send_t := 0.0
var _gate_len: Array = []          # distância entre portões consecutivos (para a posição na corrida)
var explore := false               # modo exploração (mundo livre)
var _safe: Array = []              # últimas posições seguras [[pos, heading]] (para renascer)
var _safe_t := 0.0
var _zone := -1
var _hint_t := 0.0

@onready var terrain = $Terrain
@onready var map = $Map
@onready var player = $Player
@onready var cam = $Camera
@onready var hud = $HUD
@onready var sun: DirectionalLight3D = $Sun
@onready var env: Environment = $WorldEnvironment.environment

func _ready() -> void:
	DisplayServer.screen_set_keep_on(true)
	_setup_input()
	args = _parse_args()
	explore = String(args.get("mode", Net.mode)) == "explorar"
	mp = Net.online and Net.players.size() > 1
	var az := deg_to_rad(SUN_AZIMUTH)
	var el := deg_to_rad(SUN_ELEVATION)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/map.json"))
	terrain.setup(info)
	terrain.focus = cam
	map.player = player
	map.setup(info, terrain)
	map.checkpoint_passed.connect(_on_checkpoint)
	map.finish_passed.connect(_on_finish)
	hud.map_size = float(info.size)
	hud.player = player
	hud.multiplayer_mode = mp
	hud.camera_pressed.connect(func(): cam.toggle())
	hud.pause_action.connect(_on_pause_action)
	hud.travel_requested.connect(_travel)
	hud.set_mode(explore)
	hud.zones = info.zones
	for c in info.checkpoints:
		hud.gates.append(Vector2(c.p[0], c.p[2]))
	hud.gates.append(Vector2(info.finish.p[0], info.finish.p[2]))
	player.set_route(_build_route())
	player.autopilot = args.has("autoplay")
	player.crashed.connect(_on_fall)
	player.scraped.connect(_on_scrape)
	player.landed.connect(_on_land)
	player.boosted.connect(_on_boost)
	var st: Dictionary = info.start
	var start_pos := Vector3(st.p[0], st.p[1], st.p[2])
	var start_dir := Vector2(st.dir[0], st.dir[1])
	if mp:   # grelha de partida lado a lado
		var ids := Net.sorted_ids()
		var side := Vector3(-start_dir.y, 0, start_dir.x)
		start_pos += side * (ids.find(Net.my_id()) - (ids.size() - 1) * 0.5) * 16.0
		RemoteRacer.tint(player.model, Net.color_of(Net.my_id()))
		for id in ids:
			if id == Net.my_id():
				continue
			var r = RemoteRacer.new()
			add_child(r)
			r.setup(id, Net.players[id].name, Net.color_of(id))
			r.global_position = Vector3(st.p[0], st.p[1] + 1.5, st.p[2]) + side * (ids.find(id) - (ids.size() - 1) * 0.5) * 16.0
			r.rotation.y = atan2(-start_dir.x, -start_dir.y)
			remotes[id] = r
		Net.peer_state.connect(_on_peer_state)
		Net.peer_finished.connect(_on_peer_finished)
		Net.countdown_started.connect(func():
			if not explore:
				state = State.COUNTDOWN
				t_count = 3.6)
		Net.everyone_back_to_menu.connect(func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/menu.tscn"))
		state = State.WAIT
	if args.has("cp"):
		next_cp = int(args["cp"])
		var c: Dictionary = info.checkpoints[next_cp - 1]
		player.place(Vector3(c.p[0], c.p[1], c.p[2]), Vector2(c.dir[0], c.dir[1]), 0.0)
	else:
		player.place(start_pos, start_dir, 0.0)
	if args.has("at"):   # teste: --at=x,z,dx,dz[,y] coloca o veículo em qualquer ponto do mapa
		var a := String(args["at"]).split(",")
		var ap := Vector3(float(a[0]), 0.0, float(a[1]))
		ap.y = terrain.height_at(ap.x, ap.z) if a.size() < 5 else float(a[4])
		player.place(ap, Vector2(float(a[2]), float(a[3])).normalized(), 0.0)
	terrain.update_now()
	cam.player = player
	cam.first_person = args.has("fpv")
	cam.snap()
	fx = preload("res://scripts/speed_fx.gd").new()
	add_child(fx)
	fx.setup(player, cam)
	audio = preload("res://scripts/audio.gd").new()
	add_child(audio)
	best = _load_best()
	map.highlight(-1 if explore else next_cp)
	map.warmup(cam)
	_measure_gates()
	if args.has("nohud"):
		hud.visible = false
	if explore:
		state = State.FREE
		player.running = true
		audio.start_run()
		hud.set_center("", "", HINT_EXPLORE)
		_hint_t = 7.0
		if args.has("travel"):
			var tv := String(args["travel"]).split(",")
			_travel(Vector2(float(tv[0]), float(tv[1])))
	elif mp:
		hud.set_center("", "À espera dos outros jogadores...", HINT)
		Net.report_loaded()
	else:
		hud.set_center("", "", HINT)
	if args.has("shots"):
		for s in String(args["shots"]).split(","):
			shots.append(float(s))

## Rota do piloto automático (testes): escolhe um caminho por trecho com --variant=N ou --variant=sorte.
func _build_route() -> Array:
	var out: Array = []
	var v = args.get("variant", "0")
	for sec in info.sections:
		var vs: Array = sec.variants
		var k := 0
		if String(v) == "sorte":
			k = randi() % vs.size()
		elif int(v) < vs.size():
			k = int(v)
		if args.has("log"):
			print("trecho ", sec.key, ": ", vs[k].name)
		var r: Array = vs[k].route
		out.append_array(r if out.is_empty() else r.slice(1))   # o 1.º ponto repete o portão
	return out

func _setup_input() -> void:
	var binds := {"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D], "brake": [KEY_DOWN, KEY_S, KEY_SPACE]}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			out[s.substr(0, i)] = s.substr(i + 1)
		else:
			out[s] = true
	return out

func _process(dt: float) -> void:
	elapsed += dt
	var p: Vector3 = player.global_position
	match state:
		State.COUNTDOWN:
			t_count -= dt
			var n := int(ceil(t_count - 0.6))
			if n != _last_count and n >= 1 and n <= 3:
				_last_count = n
				hud.set_center(str(n), "", HINT)
				audio.beep(false)
			if t_count <= 0.6 and state == State.COUNTDOWN:
				state = State.RACE
				player.running = true
				hud.set_center("JÁ!", info.sections[0].title)
				audio.beep(true)
				audio.start_run()
		State.RACE, State.FREE:
			if state == State.RACE:
				t_race += dt
			if t_race > 1.2 and respawn_timer < 0.0 and hud.center_label.text == "JÁ!":
				hud.set_center("")
			if _hint_t > 0.0:
				_hint_t -= dt
				if _hint_t <= 0.0 and respawn_timer < 0.0:
					hud.set_center("")
			if p.y < float(info.fall_y) and player.running:
				player.running = false
				_on_fall()
			if respawn_timer >= 0.0:
				respawn_timer -= dt
				if respawn_timer < 0.0:
					respawn()
			_track_safe(dt)
			_adapt_quality(dt)
			_check_stuck(dt)
	var target := _next_target()
	hud.set_nav(p, player.heading, target, not explore)
	hud.set_race(t_race, best, next_cp, info.checkpoints.size(), player.speed() * 3.6)
	var cave: bool = map.in_cave(p)
	# dentro da gruta / sob o teto de pedra a luz ambiente cai (fica mais escuro)
	env.ambient_light_energy = move_toward(env.ambient_light_energy, 0.28 if cave else 0.7, dt * 1.2)
	fx.update(player.running, player.speed(), player.speed_fraction(), cave, player.on_ground)
	if int(elapsed * 2.0) != int((elapsed - dt) * 2.0):   # zona onde estamos (aviso ao entrar)
		var z: int = map.zone_at(p)
		if z != _zone:
			_zone = z
			hud.show_zone(info.zones[z].name)
	audio.update(player.running, player.speed_fraction(), cave, dt, player.drifting)
	if mp:
		_mp_update(dt)
	if not shots.is_empty() and elapsed >= shots[0]:
		var t: float = shots.pop_front()
		var dir: String = args.get("shotdir", OS.get_user_data_dir())
		DirAccess.make_dir_recursive_absolute(dir)
		var path := "%s/shot_%05.1f.png" % [dir, t]
		get_viewport().get_texture().get_image().save_png(path)
		print("PRINT ", path, "  portão=", next_cp, "  t=", snappedf(t_race, 0.1), "  fps=", Engine.get_frames_per_second())
	if args.has("log") and mp and int(elapsed) != int(elapsed - dt):
		for id in remotes:
			print("   adversário %s: progresso %.2f  pos=%s" % [Net.players[id].name, remotes[id].progress, remotes[id].global_position.round()])
	if args.has("log") and int(elapsed * 2.0) != int((elapsed - dt) * 2.0):
		print("t=%.1f  pos=(%d,%d,%d)  v=%d km/h  chão=%s  portão=%d  estado=%d%s" % [t_race, p.x, p.y, p.z, player.speed() * 3.6,
			player.on_ground, next_cp, state, ("  deriva" if player.drifting else "")])
	if args.has("quit") and elapsed >= float(args["quit"]):
		print("FIM  portão=", next_cp, "/", info.checkpoints.size(), "  t=", snappedf(t_race, 0.1), "  estado=", state)
		get_tree().quit()

func _next_target() -> Vector3:
	if next_cp < info.checkpoints.size():
		return map.checkpoints[next_cp].pos
	var f: Dictionary = info.finish
	return Vector3(f.p[0], f.p[1], f.p[2])

func _gate_pos(i: int) -> Vector3:
	var d: Dictionary = info.start if i == 0 else (info.checkpoints[i - 1] if i <= info.checkpoints.size() else info.finish)
	return Vector3(d.p[0], d.p[1], d.p[2])

func _measure_gates() -> void:
	for i in info.checkpoints.size() + 1:
		_gate_len.append(_gate_pos(i).distance_to(_gate_pos(i + 1)))

## Progresso na corrida (portões passados + fração até ao próximo), para ordenar os jogadores.
func progress() -> float:
	if state == State.FINISHED:
		return 1000.0
	var d: float = player.global_position.distance_to(_next_target())
	return next_cp + clampf(1.0 - d / maxf(_gate_len[mini(next_cp, _gate_len.size() - 1)], 1.0), 0.0, 0.99)

# ------------------------------------------------------------------ portões e chegada
func _on_checkpoint(i: int) -> void:
	if state != State.RACE or i != next_cp:
		return
	next_cp += 1
	map.highlight(next_cp)
	audio.checkpoint()
	var zone: String = info.sections[mini(i + 1, info.sections.size() - 1)].title
	hud.set_center("", "PORTÃO %d  ·  %s" % [i + 1, hud.fmt_time(t_race)], zone)
	get_tree().create_timer(1.4).timeout.connect(func():
		if state == State.RACE and respawn_timer < 0.0:
			hud.set_center(""))

func _on_finish() -> void:
	if state != State.RACE or next_cp < info.checkpoints.size():
		return
	state = State.FINISHED
	player.running = false
	audio.finish()
	print("CHEGOU em ", hud.fmt_time(t_race))
	if mp:
		Net.send_finished(t_race)
		return
	var record := best <= 0.0 or t_race < best
	var counts := not (args.has("cp") or args.has("at") or args.has("autoplay"))   # testes não contam para o recorde
	if record and counts:
		best = t_race
		_save_best()
	hud.set_center("CHEGADA!", ("NOVO RECORDE!  " if record else "") + hud.fmt_time(t_race), "Pausa → RECOMEÇAR para correr de novo")

# ------------------------------------------------------------------ PvP
func _mp_update(dt: float) -> void:
	_send_t -= dt
	if _send_t <= 0.0:
		_send_t = 0.05
		var q: Quaternion = player.model.quaternion
		Net.send_state(PackedFloat32Array([player.global_position.x, player.global_position.y, player.global_position.z,
			player.heading, q.x, q.y, q.z, q.w, player.speed(), progress(), results.get(Net.my_id(), 0.0), 1.0 if player.drifting else 0.0]))
	# posição na corrida
	var rows := [[Net.my_id(), progress(), results.get(Net.my_id(), 0.0)]]
	for id in remotes:
		rows.append([id, remotes[id].progress, results.get(id, 0.0)])
	rows.sort_custom(func(a, b):
		if a[2] > 0.0 and b[2] > 0.0:
			return a[2] < b[2]
		if a[2] > 0.0 or b[2] > 0.0:
			return a[2] > 0.0
		return a[1] > b[1])
	var dots := []
	for id in remotes:
		var rp: Vector3 = remotes[id].global_position
		dots.append([Vector2(rp.x, rp.z), Net.color_of(id), String(Net.players.get(id, {"name": "?"}).name)])
	hud.remote_dots = dots
	var table := []
	for r in rows:
		var pd: Dictionary = Net.players.get(r[0], {"name": "?"})
		table.append([pd.name, Net.color_of(r[0]), r[0] == Net.my_id(), r[2]])
	hud.set_standings(table)

var _seen_peers := {}
func _on_peer_state(id: int, s: PackedFloat32Array) -> void:
	if remotes.has(id):
		remotes[id].push_state(s)
		if args.has("log") and not _seen_peers.has(id):
			_seen_peers[id] = true
			print("PvP: a receber o veículo de ", Net.players[id].name, " em ", Vector3(s[0], s[1], s[2]))

func _on_peer_finished(id: int, time: float) -> void:
	results[id] = time
	var place := 0
	for t in results.values():
		if t <= time:
			place += 1
	if id == Net.my_id():
		hud.set_center("CHEGADA!", "%dº lugar  ·  %s" % [place, hud.fmt_time(time)], "")
	else:
		audio.checkpoint()
	if results.size() >= Net.players.size():
		hud.show_results(multiplayer.is_server())

# ------------------------------------------------------------------ pausa, quedas e choques
func _on_pause_action(action: String) -> void:
	match action:
		"portao":
			if state == State.RACE or state == State.FREE:
				player.running = false
				respawn(not explore)
		"recomecar":
			if mp:
				if multiplayer.is_server():
					Net.rematch()
			else:
				get_tree().paused = false
				get_tree().reload_current_scene()
		"menu":
			if mp:
				Net.leave()
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_fall() -> void:
	if state != State.RACE and state != State.FREE:
		return
	if args.has("log"):
		print("CAIU em ", player.global_position)
	cam.shake()
	audio.crash()
	Input.vibrate_handheld(250)
	hud.set_center("CAIU!", "De volta ao caminho...")
	respawn_timer = 1.2

## Guarda onde o veículo esteve bem assente no chão (para renascer perto, depois de cair).
func _track_safe(dt: float) -> void:
	_safe_t -= dt
	if _safe_t > 0.0:
		return
	_safe_t = 0.5
	var p: Vector3 = player.global_position
	if player.running and player.on_ground and not player.on_water and p.y > float(info.fall_y) + 20.0:
		_safe.append([p, player.heading])
		if _safe.size() > 12:
			_safe.pop_front()

## Renasce no caminho mais perto de onde se esteve há uns 3 segundos (ou no último portão).
func respawn(at_gate := false) -> void:
	var pos: Vector3
	var dir: Vector2
	if not at_gate and not _safe.is_empty():
		var s: Array = _safe[maxi(0, _safe.size() - 7)]
		var sp: Array = map.nearest_spawn(s[0])
		if not sp.is_empty() and sp[0].distance_to(s[0]) < 300.0:
			pos = sp[0]
			dir = sp[1]
		else:
			pos = s[0]
			dir = Vector2(-sin(s[1]), -cos(s[1]))
	else:
		var g: Dictionary = info.start if next_cp == 0 or explore else info.checkpoints[next_cp - 1]
		pos = Vector3(g.p[0], 0.0, g.p[2])
		pos.y = terrain.height_at(pos.x, pos.z)
		dir = Vector2(g.dir[0], g.dir[1])
	_safe.clear()
	player.place(pos, dir, 30.0)
	player.running = true
	respawn_timer = -1.0
	cam.snap()
	audio.start_run()
	hud.set_center("")

## Exploração: viajar para o caminho mais perto do sítio tocado no mapa.
func _travel(w: Vector2) -> void:
	if not explore:
		return
	var sp: Array = map.nearest_spawn(Vector3(w.x, 0.0, w.y), true)
	if sp.is_empty():
		return
	_safe.clear()
	player.place(sp[0], sp[1], 0.0)
	player.running = true
	respawn_timer = -1.0
	terrain.update_now()
	cam.snap()
	_zone = -1
	if args.has("log"):
		print("VIAJOU para ", sp[0])

func _on_land(strength: float) -> void:
	audio.land(strength)
	cam.kick(clampf(strength / 30.0, 0.2, 1.0))
	if strength > 14.0:
		Input.vibrate_handheld(int(clampf(strength * 2.0, 20.0, 80.0)))

func _on_scrape(strength: float) -> void:
	if args.has("log") and strength > 40.0:
		print("batida %.0f em %s" % [strength, player.global_position])
	audio.scrape(strength)
	if strength > 45.0:
		audio.bump(strength)
		cam.shake(0.35)
	cam.kick(minf(1.0, strength / 40.0))
	Input.vibrate_handheld(int(clampf(strength * 1.5, 10.0, 120.0)))

func _on_boost(amount: float) -> void:
	audio.boost()
	cam.kick(clampf(amount / 12.0, 0.3, 1.0))
	fx.boost_flash()

## Piloto automático preso durante 4 s (só nos testes): avança 240 m pelo caminho e continua,
## para a volta chegar ao fim e o registo mostrar todos os sítios difíceis.
var _stuck_t := 0.0
var _stuck_p := Vector3.ZERO
func _check_stuck(dt: float) -> void:
	if not player.autopilot or not player.running:
		return
	_stuck_t += dt
	if _stuck_t > 4.0:
		if player.global_position.distance_to(_stuck_p) < 15.0:
			print("PRESO em ", player.global_position)
			var r: Array = player.route
			var i := mini(player._route_i + 30, r.size() - 2)
			var a: Array = r[i]
			var b: Array = r[i + 1]
			player.place(Vector3(a[0], a[1], a[2]), Vector2(b[0] - a[0], b[2] - a[2]).normalized(), 30.0)
			cam.snap()
		_stuck_t = 0.0
		_stuck_p = player.global_position

func _adapt_quality(dt: float) -> void:
	if args.has("autoplay"):
		return
	_fps_acc += 1.0 / maxf(dt, 0.0001)
	_fps_n += 1
	if _fps_n < 180:
		return
	var avg := _fps_acc / _fps_n
	_fps_acc = 0.0
	_fps_n = 0
	if avg < 45.0 and _quality == 2:
		_quality = 1
		fx.blur_enabled = false
	elif avg < 40.0 and _quality == 1:
		_quality = 0
		sun.shadow_enabled = false

func _load_best() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return float(cfg.get_value(SAVE_KEY, "best", 0.0))
	return 0.0

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_KEY, "best", best)
	cfg.save(SAVE_PATH)
