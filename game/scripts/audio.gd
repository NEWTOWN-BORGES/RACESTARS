extends Node
## Som: motor (tom sobe com a velocidade), vento, música, passagem rente, batida e largada.
## Dentro dos túneis entra um eco (reverb) no barramento de efeitos.

var engine: AudioStreamPlayer
var wind: AudioStreamPlayer
var music: AudioStreamPlayer
var sfx: AudioStreamPlayer
var whoosh_stream: AudioStream = preload("res://assets/audio/whoosh.wav")
var crash_stream: AudioStream = preload("res://assets/audio/crash.wav")
var start_stream: AudioStream = preload("res://assets/audio/start.wav")
var reverb: AudioEffectReverb
var fx_bus := 0
var _reverb_wet := 0.0

func _ready() -> void:
	fx_bus = AudioServer.bus_count
	AudioServer.add_bus(fx_bus)
	AudioServer.set_bus_name(fx_bus, "Efeitos")
	AudioServer.set_bus_send(fx_bus, "Master")
	reverb = AudioEffectReverb.new()
	reverb.room_size = 0.75
	reverb.damping = 0.3
	reverb.wet = 0.0
	reverb.dry = 1.0
	AudioServer.add_bus_effect(fx_bus, reverb)
	engine = _player(_loop(preload("res://assets/audio/engine_loop.wav")), -12.0, "Efeitos")
	wind = _player(_loop(preload("res://assets/audio/wind_loop.wav")), -40.0, "Efeitos")
	music = _player(_loop(preload("res://assets/audio/music_loop.wav")), -9.0, "Master")
	sfx = _player(null, -4.0, "Efeitos")
	sfx.max_polyphony = 4
	music.play()

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

func start_run() -> void:
	_play(start_stream, 1.0, -6.0)
	engine.play()
	wind.play()

func crash() -> void:
	engine.stop()
	_play(crash_stream, 1.0, 0.0)

func near_miss(frac: float) -> void:
	_play(whoosh_stream, randf_range(0.9, 1.15) + frac * 0.3, -2.0)

func _play(s: AudioStream, pitch: float, db: float) -> void:
	sfx.stream = s
	sfx.pitch_scale = pitch
	sfx.volume_db = db
	sfx.play()

func update(running: bool, frac: float, in_tunnel: bool, dt: float) -> void:
	if running:
		engine.pitch_scale = 0.75 + frac * 1.0
		engine.volume_db = lerpf(-14.0, -7.0, frac)
		wind.volume_db = lerpf(-26.0, -6.0, frac) + (3.0 if in_tunnel else 0.0)
		wind.pitch_scale = 0.9 + frac * 0.5
	else:
		wind.volume_db = move_toward(wind.volume_db, -60.0, dt * 30.0)
	_reverb_wet = move_toward(_reverb_wet, 0.35 if in_tunnel else 0.0, dt * 1.5)
	reverb.wet = _reverb_wet
