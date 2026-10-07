extends Node
## PvP local (autoload "Net"): um telemóvel CRIA a corrida e os outros ENTRAM, na mesma rede Wi-Fi
## (ou ligados ao hotspot de um deles). Descoberta automática: quem procura envia "RACESTARS?"
## por broadcast e para todos os endereços da sua rede /24; quem criou responde com o nome.
## Durante a corrida cada telemóvel manda o estado do seu veículo ~20 vezes por segundo.

signal players_changed
signal hosts_changed
signal status_changed(text: String)
signal countdown_started
signal peer_state(id: int, state: PackedFloat32Array)
signal peer_finished(id: int, time: float)
signal everyone_back_to_menu

const PORT := 47777
const DISC_PORT := 47778
const MAX_PLAYERS := 4
const COLORS := [Color("#ff7a2e"), Color("#3fa8ff"), Color("#5fe06a"), Color("#c46bff")]

var online := false
var mode := "corrida"             # "explorar" (mundo livre) ou "corrida" (circuito de A a B)
var players := {}                 # id -> {"name": String, "color": int, "ready": bool}
var my_name := "Jogador"
var hosts := {}                   # ip -> {"name": String, "count": int, "seen": float}
var _disc: PacketPeerUDP          # anfitrião: responde a quem procura
var _probe: PacketPeerUDP         # cliente: procura anfitriões
var _probe_timer := 0.0
var _clock := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _status("Não foi possível ligar."); leave(); everyone_back_to_menu.emit())
	multiplayer.server_disconnected.connect(func(): _status("O anfitrião saiu."); leave(); everyone_back_to_menu.emit())

func my_id() -> int:
	return multiplayer.get_unique_id() if online else 1

func color_of(id: int) -> Color:
	return COLORS[int(players.get(id, {}).get("color", 0)) % COLORS.size()]

func sorted_ids() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids

func _status(t: String) -> void:
	status_changed.emit(t)

# ------------------------------------------------------------------ criar / entrar / sair
func host_game() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		_status("Não foi possível criar o jogo (porta ocupada?).")
		return false
	multiplayer.multiplayer_peer = peer
	online = true
	players = {1: {"name": my_name, "color": 0, "ready": false}}
	_disc = PacketPeerUDP.new()
	if _disc.bind(DISC_PORT) != OK:
		_disc = null
	players_changed.emit()
	_status("Jogo criado. À espera de jogadores...")
	return true

func join_game(ip: String) -> bool:
	leave_keep_probe()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		_status("Endereço inválido.")
		return false
	multiplayer.multiplayer_peer = peer
	online = true
	_status("A ligar a %s..." % ip)
	return true

func leave_keep_probe() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	online = false
	players = {}
	if _disc:
		_disc.close()
		_disc = null

func leave() -> void:
	leave_keep_probe()
	stop_search()

# ------------------------------------------------------------------ descoberta na rede local
func start_search() -> void:
	stop_search()
	hosts = {}
	_probe = PacketPeerUDP.new()
	_probe.set_broadcast_enabled(true)
	_probe.bind(0)
	_probe_timer = 0.0

func stop_search() -> void:
	if _probe:
		_probe.close()
		_probe = null

## Endereços IPv4 desta máquina na rede local.
static func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out

func _process(dt: float) -> void:
	_clock += dt
	if _disc:   # anfitrião responde a quem procura
		while _disc.get_available_packet_count() > 0:
			var pkt := _disc.get_packet().get_string_from_utf8()
			if pkt == "RACESTARS?":
				_disc.set_dest_address(_disc.get_packet_ip(), _disc.get_packet_port())
				_disc.put_packet(("RACESTARS!%s|%d" % [my_name, players.size()]).to_utf8_buffer())
	if _probe:
		_probe_timer -= dt
		if _probe_timer <= 0.0:
			_probe_timer = 1.5
			var msg := "RACESTARS?".to_utf8_buffer()
			_probe.set_dest_address("255.255.255.255", DISC_PORT)
			_probe.put_packet(msg)
			for ip in local_ips():   # também um a um na rede /24 (alguns telemóveis bloqueiam broadcast)
				var base := String(ip).substr(0, String(ip).rfind(".") + 1)
				for k in range(1, 255):
					_probe.set_dest_address(base + str(k), DISC_PORT)
					_probe.put_packet(msg)
		var changed := false
		while _probe.get_available_packet_count() > 0:
			var pkt := _probe.get_packet().get_string_from_utf8()
			var ip := _probe.get_packet_ip()
			if pkt.begins_with("RACESTARS!"):
				var parts := pkt.substr(10).split("|")
				hosts[ip] = {"name": parts[0], "count": int(parts[1]) if parts.size() > 1 else 1, "seen": _clock}
				changed = true
		for ip in hosts.keys():
			if _clock - hosts[ip].seen > 6.0:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()

# ------------------------------------------------------------------ sala de espera
func _on_peer_connected(_id: int) -> void:
	pass

func _on_connected() -> void:
	_status("Ligado! À espera que o anfitrião comece.")
	stop_search()
	_register.rpc_id(1, my_name)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	players_changed.emit()
	if multiplayer.is_server():
		_sync_players.rpc(players)

@rpc("any_peer", "reliable")
func _register(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var used := []
	for p in players.values():
		used.append(p.color)
	var c := 0
	while c in used:
		c += 1
	players[id] = {"name": pname if pname != "" else "Jogador %d" % (players.size() + 1), "color": c, "ready": false}
	_sync_players.rpc(players)
	players_changed.emit()

@rpc("authority", "reliable")
func _sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()

## Anfitrião: todos vão para o mundo, no modo escolhido.
func start_race(m: String = "") -> void:
	if multiplayer.is_server():
		for id in players:
			players[id].ready = false
		_go_race.rpc(m if m != "" else mode)

@rpc("authority", "reliable", "call_local")
func _go_race(m: String) -> void:
	mode = m
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## Cada um avisa quando a corrida carregou; o anfitrião começa a contagem quando todos estão prontos.
func report_loaded() -> void:
	if not online:
		return
	_loaded.rpc_id(1)

@rpc("any_peer", "reliable", "call_local")
func _loaded() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id].ready = true
	for p in players.values():
		if not p.ready:
			return
	_countdown.rpc()

@rpc("authority", "reliable", "call_local")
func _countdown() -> void:
	countdown_started.emit()

# ------------------------------------------------------------------ durante a corrida
func send_state(s: PackedFloat32Array) -> void:
	if online and multiplayer.multiplayer_peer and players.size() > 1:
		_state.rpc(s)

@rpc("any_peer", "unreliable_ordered")
func _state(s: PackedFloat32Array) -> void:
	peer_state.emit(multiplayer.get_remote_sender_id(), s)

func send_finished(time: float) -> void:
	if online:
		_finished.rpc(time)

@rpc("any_peer", "reliable", "call_local")
func _finished(time: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = my_id()
	peer_finished.emit(id, time)

## Anfitrião: nova corrida com os mesmos jogadores.
func rematch() -> void:
	start_race(mode)
