extends Node
## Som: turbinas (tom sobe com a velocidade), vento, música, contagem, portões,
## chegada, raspões e batidas. Dentro da gruta e sob o teto do desfiladeiro entra eco.

var engine: AudioStreamPlayer
var wind: AudioStreamPlayer
var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var _voice := 0
var reverb: AudioEffectReverb
var fx_bus := 0
var _reverb_wet := 0.0
var _scrape_cd := 0.0
var S := {}

func _ready() -> void:
	fx_bus = AudioServer.get_bus_index("Efeitos")
	if fx_bus < 0:   # só cria uma vez (a cena é recarregada ao recomeçar)
		fx_bus = AudioServer.bus_count
		AudioServer.add_bus(fx_bus)
		AudioServer.set_bus_name(fx_bus, "Efeitos")
		AudioServer.set_bus_send(fx_bus, "Master")
		var r := AudioEffectReverb.new()
		r.room_size = 0.8
		r.damping = 0.3
		r.dry = 1.0
		AudioServer.add_bus_effect(fx_bus, r)
	reverb = AudioServer.get_bus_effect(fx_bus, 0)
	reverb.wet = 0.0
	for n in ["whoosh", "crash", "start", "beep", "go", "checkpoint", "finish", "scrape", "land"]:
		S[n] = load("res://assets/audio/%s.wav" % n)
	engine = _player(_loop(preload("res://assets/audio/engine_loop.wav")), -14.0, "Efeitos")
	wind = _player(_loop(preload("res://assets/audio/wind_loop.wav")), -40.0, "Efeitos")
	music = _player(_loop(preload("res://assets/audio/music_loop.wav")), -12.0, "Master")
	for i in 5:
		voices.append(_player(null, 0.0, "Efeitos"))
	music.play()
	engine.pitch_scale = 0.6
	engine.volume_db = -20.0
	engine.play()

func _loop(s: AudioStream) -> AudioStream:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s

func _player(stream: AudioStream, db: float, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = bus
	add_child(p)
	return p

func _play(name: String, pitch := 1.0, db := 0.0) -> void:
	var p := voices[_voice]
	_voice = (_voice + 1) % voices.size()
	p.stream = S[name]
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()

func beep(go: bool) -> void:
	_play("go" if go else "beep", 1.0, -3.0)

func start_run() -> void:
	if not engine.playing:
		engine.play()
	if not wind.playing:
		wind.play()

func checkpoint() -> void:
	_play("checkpoint", 1.0, -2.0)

func finish() -> void:
	_play("finish", 1.0, 0.0)

func crash() -> void:
	engine.stop()
	_play("crash", 1.0, 0.0)

func scrape(strength: float) -> void:
	if _scrape_cd > 0.0:
		return
	_scrape_cd = 0.18
	_play("scrape", randf_range(0.85, 1.15), lerpf(-10.0, 0.0, clampf(strength / 40.0, 0.0, 1.0)))

func land(strength: float) -> void:
	_play("land", randf_range(0.9, 1.1), lerpf(-10.0, 0.0, clampf(strength / 30.0, 0.0, 1.0)))

func near_miss(frac: float) -> void:
	_play("whoosh", randf_range(0.9, 1.15) + frac * 0.3, -2.0)

func update(running: bool, frac: float, in_tunnel: bool, dt: float) -> void:
	_scrape_cd -= dt
	if running:
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.7 + frac * 1.15, 1.0 - exp(-dt * 6.0))
		engine.volume_db = lerpf(-13.0, -6.0, frac) + (2.0 if in_tunnel else 0.0)
		wind.volume_db = lerpf(-28.0, -8.0, frac)
		wind.pitch_scale = 0.9 + frac * 0.5
	else:
		engine.pitch_scale = move_toward(engine.pitch_scale, 0.6, dt * 0.5)
		wind.volume_db = move_toward(wind.volume_db, -60.0, dt * 30.0)
	_reverb_wet = move_toward(_reverb_wet, 0.4 if in_tunnel else 0.0, dt * 1.5)
	reverb.wet = _reverb_wet
