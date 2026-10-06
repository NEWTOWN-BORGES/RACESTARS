extends Node3D
## Corrida contra o relógio, de A (largada) até B (meta), num mapa de 4 x 4 km.
## Liberdade total para sair da estrada e cortar caminho, mas é preciso passar
## pelos portões em ordem. Bateu forte ou caiu no abismo: volta ao último portão.
##
## Argumentos de teste (depois de `--`):
##   --autoplay  --shots=2,6  --shotdir=/caminho  --quit=SEG  --cp=N (começa no portão N)

enum State { COUNTDOWN, RACE, FINISHED }

const SAVE_PATH := "user://save.cfg"
const SUN_AZIMUTH := 35.0
const SUN_ELEVATION := 42.0

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
	var az := deg_to_rad(SUN_AZIMUTH)
	var el := deg_to_rad(SUN_ELEVATION)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/map.json"))
	terrain.setup(info)
	terrain.focus = player
	map.player = player
	map.setup(info, terrain)
	map.checkpoint_passed.connect(_on_checkpoint)
	map.finish_passed.connect(_on_finish)
	hud.map_size = float(info.size)
	hud.camera_pressed.connect(func(): cam.toggle())
	hud.restart_pressed.connect(func(): get_tree().reload_current_scene())
	player.route = info.route
	player.autopilot = args.has("autoplay")
	player.crashed.connect(_on_crash)
	player.scraped.connect(_on_scrape)
	var st: Dictionary = info.start
	if args.has("cp"):
		next_cp = int(args["cp"])
		var c: Dictionary = info.checkpoints[next_cp - 1]
		player.place(Vector3(c.p[0], c.p[1], c.p[2]), Vector2(c.dir[0], c.dir[1]), 0.0)
	else:
		player.place(Vector3(st.p[0], st.p[1], st.p[2]), Vector2(st.dir[0], st.dir[1]), 0.0)
	if args.has("at"):   # teste: --at=x,z,dx,dz coloca o veículo em qualquer ponto do mapa
		var a := String(args["at"]).split(",")
		var ap := Vector3(float(a[0]), 0.0, float(a[1]))
		ap.y = terrain.height_at(ap.x, ap.z)
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
	map.highlight(next_cp)
	hud.set_center("", "", "Segure os lados da tela para virar  ·  os dois lados = travar")
	if args.has("shots"):
		for s in String(args["shots"]).split(","):
			shots.append(float(s))

func _setup_input() -> void:
	var binds := {"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D], "brake": [KEY_DOWN, KEY_S]}
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
				hud.set_center(str(n), "", "Segure os lados da tela para virar  ·  os dois lados = travar")
				audio.beep(false)
			if t_count <= 0.6 and state == State.COUNTDOWN:
				state = State.RACE
				player.running = true
				hud.set_center("JÁ!")
				audio.beep(true)
				audio.start_run()
		State.RACE:
			t_race += dt
			if t_race > 1.2 and respawn_timer < 0.0 and hud.center_label.text == "JÁ!":
				hud.set_center("")
			if p.y < float(info.fall_y) and player.running:
				player.running = false
				_on_crash()
			if respawn_timer >= 0.0:
				respawn_timer -= dt
				if respawn_timer < 0.0:
					_respawn()
			_adapt_quality(dt)
	var target := _next_target()
	hud.set_nav(p, player.heading, target)
	hud.set_race(t_race, best, next_cp, info.checkpoints.size(), player.speed() * 3.6)
	var cave: bool = map.in_cave(p)
	# dentro da gruta / sob o teto de pedra a luz ambiente cai (fica mais escuro)
	env.ambient_light_energy = move_toward(env.ambient_light_energy, 0.28 if cave else 0.7, dt * 1.2)
	fx.update(player.running, player.speed(), player.speed_fraction(), cave, player.on_ground)
	audio.update(player.running, player.speed_fraction(), cave, dt)
	if not shots.is_empty() and elapsed >= shots[0]:
		var t: float = shots.pop_front()
		var dir: String = args.get("shotdir", OS.get_user_data_dir())
		DirAccess.make_dir_recursive_absolute(dir)
		var path := "%s/shot_%05.1f.png" % [dir, t]
		get_viewport().get_texture().get_image().save_png(path)
		print("PRINT ", path, "  portão=", next_cp, "  t=", snappedf(t_race, 0.1), "  fps=", Engine.get_frames_per_second())
	if args.has("log") and int(elapsed * 2.0) != int((elapsed - dt) * 2.0):
		print("t=%.1f  pos=(%d,%d,%d)  v=%d km/h  chão=%s  portão=%d  estado=%d" % [t_race, p.x, p.y, p.z, player.speed() * 3.6, player.on_ground, next_cp, state])
	if args.has("quit") and elapsed >= float(args["quit"]):
		print("FIM  portão=", next_cp, "/", info.checkpoints.size(), "  t=", snappedf(t_race, 0.1), "  estado=", state)
		get_tree().quit()

func _next_target() -> Vector3:
	if next_cp < info.checkpoints.size():
		return map.checkpoints[next_cp].pos
	var f: Dictionary = info.finish
	return Vector3(f.p[0], f.p[1], f.p[2])

func _on_checkpoint(i: int) -> void:
	if state != State.RACE or i != next_cp:
		return
	next_cp += 1
	map.highlight(next_cp)
	audio.checkpoint()
	hud.set_center("", "PORTÃO %d  ·  %s" % [i + 1, hud.fmt_time(t_race)])
	get_tree().create_timer(1.4).timeout.connect(func():
		if state == State.RACE and respawn_timer < 0.0:
			hud.set_center(""))

func _on_finish() -> void:
	if state != State.RACE or next_cp < info.checkpoints.size():
		return
	state = State.FINISHED
	player.running = false
	var record := best <= 0.0 or t_race < best
	if record:
		best = t_race
		_save_best()
	audio.finish()
	hud.set_center("CHEGADA!", ("NOVO RECORDE!  " if record else "") + hud.fmt_time(t_race), "Toque em ↺ para correr de novo")
	print("CHEGOU em ", hud.fmt_time(t_race))

func _on_crash() -> void:
	if state != State.RACE:
		return
	if args.has("log"):
		print("BATEU em ", player.global_position)
	cam.shake()
	audio.crash()
	Input.vibrate_handheld(250)
	hud.set_center("BATEU!", "Voltando ao último portão...")
	respawn_timer = 1.4

func _respawn() -> void:
	var pos: Vector3
	var dir: Vector2
	if next_cp == 0:
		var st: Dictionary = info.start
		pos = Vector3(st.p[0], st.p[1], st.p[2])
		dir = Vector2(st.dir[0], st.dir[1])
	else:
		var c: Dictionary = info.checkpoints[next_cp - 1]
		pos = Vector3(c.p[0], c.p[1], c.p[2])
		dir = Vector2(c.dir[0], c.dir[1])
	pos.y = terrain.height_at(pos.x, pos.z)
	player.place(pos, dir, 40.0)
	player.running = true
	cam.snap()
	audio.start_run()
	hud.set_center("")

func _on_scrape(strength: float) -> void:
	if args.has("log"):
		print("raspão %.0f em %s" % [strength, player.global_position])
	audio.scrape(strength)
	cam.kick(minf(1.0, strength / 40.0))
	Input.vibrate_handheld(int(clampf(strength, 10.0, 60.0)))

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
		return float(cfg.get_value("race", "best", 0.0))
	return 0.0

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("race", "best", best)
	cfg.save(SAVE_PATH)
