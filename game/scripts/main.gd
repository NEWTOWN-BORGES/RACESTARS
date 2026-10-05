extends Node3D
## Controla o jogo: início, corrida, batida e recorde.
##
## Argumentos opcionais (depois de `--` na linha de comando), úteis para testes:
##   --autoplay            piloto automático
##   --seed=N              mundo fixo
##   --start=METROS        começa mais adiante (ex.: perto de uma cordilheira)
##   --shots=2,6,10        tira prints nesses segundos (salva em --shotdir)
##   --shotdir=/caminho    pasta dos prints
##   --quit=SEG            fecha o jogo depois de SEG segundos

enum State { MENU, RUN, CRASH }

const SUN_AZIMUTH := 24.0       # graus à direita da direção da corrida
const SUN_ELEVATION := 24.0     # graus acima do horizonte
const SAVE_PATH := "user://save.cfg"

var state := State.MENU
var best := 0.0
var start_z := 0.0
var crash_time := 0.0
var elapsed := 0.0
var args := {}
var shots: Array = []

@onready var world = $World
@onready var player = $Player
@onready var cam = $Camera
@onready var hud = $HUD
@onready var sun: DirectionalLight3D = $Sun

func _ready() -> void:
	_setup_input()
	args = _parse_args()
	var az := deg_to_rad(SUN_AZIMUTH)
	var el := deg_to_rad(SUN_ELEVATION)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	world.seed_value = int(args.get("seed", randi() % 1000000))
	world.player = player
	player.world = world
	player.autopilot = args.has("autoplay")
	player.debug_ap = args.has("debugap")
	if args.has("start"):
		player.global_position.z = -float(args["start"])
	if args.has("x"):
		player.global_position.x = float(args["x"])
	start_z = 0.0
	world.prewarm()
	cam.player = player
	cam.snap()
	player.crashed.connect(_on_crash)
	best = _load_best()
	hud.show_menu(best)
	if args.has("shots"):
		for s in String(args["shots"]).split(","):
			shots.append(float(s))
	if args.has("autoplay"):
		_start()

func _setup_input() -> void:
	var binds := {"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D]}
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

func _unhandled_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventScreenTouch and e.pressed) or e.is_action_pressed("ui_accept")
	if not tap:
		return
	if state == State.MENU:
		_start()
	elif state == State.CRASH and elapsed - crash_time > 0.8:
		get_tree().reload_current_scene()

func _start() -> void:
	state = State.RUN
	start_z = player.global_position.z
	player.start()
	hud.show_run()

func distance() -> float:
	return maxf(0.0, start_z - player.global_position.z)

func _process(dt: float) -> void:
	elapsed += dt
	if state == State.RUN:
		var p: Vector3 = player.global_position
		hud.update_run(distance(), player.speed * 3.6, best, world.ridge_ahead(p), world.in_tunnel(p))
	sun.global_position = player.global_position
	if not shots.is_empty() and elapsed >= shots[0]:
		var t: float = shots.pop_front()
		var dir: String = args.get("shotdir", OS.get_user_data_dir())
		DirAccess.make_dir_recursive_absolute(dir)
		var path := "%s/shot_%05.1f.png" % [dir, t]
		get_viewport().get_texture().get_image().save_png(path)
		print("PRINT ", path, "  dist=", int(distance()), "  fps=", Engine.get_frames_per_second())
	if args.has("quit") and elapsed >= float(args["quit"]):
		get_tree().quit()

func _on_crash() -> void:
	state = State.CRASH
	crash_time = elapsed
	var d := distance()
	var record := d > best
	if record:
		best = d
		_save_best()
	cam.shake()
	hud.show_crash(d, best, record)
	print("BATEU em ", int(d), " m  (", player.last_hit, ")")

func _load_best() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return float(cfg.get_value("score", "best", 0.0))
	return 0.0

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.save(SAVE_PATH)
