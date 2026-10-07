extends Control
## Menu inicial: EXPLORAR o mundo ou correr o CIRCUITO de A a B, sozinho ou com outro telemóvel
## na mesma rede Wi-Fi (um cria o jogo, o outro entra).
## Argumentos de teste: --host [--players=2] [--mode=explorar]  |  --join=IP  |  qualquer outro
## (--autoplay, --at, --mode=...) vai direto para o jogo sozinho.

var font_title: Font = preload("res://assets/fonts/RussoOne.woff2")
var font_body: FontVariation
var main_box: VBoxContainer
var lobby_box: VBoxContainer
var join_box: VBoxContainer
var name_edit: LineEdit
var ip_edit: LineEdit
var lobby_list: Label
var lobby_info: Label
var start_btn: Button
var explore_btn: Button
var hosts_box: VBoxContainer
var status_lbl: Label
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var i := s.find("=")
		args[s.substr(0, i) if i >= 0 else s] = s.substr(i + 1) if i >= 0 else true
	font_body = FontVariation.new()
	font_body.base_font = preload("res://assets/fonts/Nunito.woff2")
	font_body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	_build()
	Net.players_changed.connect(_refresh_lobby)
	Net.hosts_changed.connect(_refresh_hosts)
	Net.status_changed.connect(func(t): status_lbl.text = t)
	Net.everyone_back_to_menu.connect(func(): _show(main_box))
	if args.has("mode"):
		Net.mode = String(args["mode"])
	if Net.online:      # voltou de uma corrida PvP: fica na sala de espera
		_show(lobby_box)
		_refresh_lobby()
	# atalhos de teste
	if args.has("host"):
		Net.my_name = String(args.get("name", "Anfitrião"))
		_on_host()
	elif args.has("join"):
		Net.my_name = String(args.get("name", "Convidado"))
		_show(join_box)
		Net.join_game(String(args["join"]))
	elif not args.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _process(_dt: float) -> void:
	# teste: o anfitrião começa sozinho quando chegam os jogadores pedidos
	if args.has("host") and Net.online and multiplayer.is_server() and lobby_box.visible:
		if Net.players.size() >= int(args.get("players", 2)):
			args.erase("host")
			Net.start_race(Net.mode)

# ------------------------------------------------------------------ interface
func _label(text: String, size: int, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f if f else font_body)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color("#2a1a10"))
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _button(text: String, cb: Callable, accent := Color("#ffb347")) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_title)
	b.add_theme_font_size_override("font_size", 34)
	b.custom_minimum_size = Vector2(520, 84)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.07, 0.04, 0.78) if st != "pressed" else Color(accent, 0.55)
		sb.border_color = accent
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(22)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color("#fff1d6"))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(cb)
	return b

func _edit(placeholder: String, text: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_override("font", font_body)
	e.add_theme_font_size_override("font_size", 32)
	e.custom_minimum_size = Vector2(520, 70)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.9)
	sb.set_corner_radius_all(16)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_color_override("font_color", Color("#2a1a10"))
	return e

func _box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(v)
	return v

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = preload("res://assets/ui/menu_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.04, 0.02, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var title := _label("RACESTARS", 120, font_title)
	title.add_theme_color_override("font_color", Color("#ffd36e"))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-500, 30)
	title.size = Vector2(1000, 150)
	add_child(title)
	status_lbl = _label("", 26)
	status_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_lbl.position = Vector2(-600, -70)
	status_lbl.size = Vector2(1200, 60)
	add_child(status_lbl)
	# principal
	main_box = _box()
	name_edit = _edit("O teu nome", "Jogador")
	name_edit.text_changed.connect(func(t): Net.my_name = t)
	main_box.add_child(name_edit)
	main_box.add_child(_button("EXPLORAR O MUNDO", _on_solo.bind("explorar"), Color("#5fe06a")))
	main_box.add_child(_button("CIRCUITO DE A ATÉ B", _on_solo.bind("corrida")))
	main_box.add_child(_button("JOGAR A DOIS: CRIAR", _on_host, Color("#7ff6ff")))
	main_box.add_child(_button("JOGAR A DOIS: ENTRAR", _on_join_screen, Color("#7ff6ff")))
	# sala de espera (anfitrião e convidados)
	lobby_box = _box()
	lobby_info = _label("", 28)
	lobby_info.custom_minimum_size = Vector2(900, 0)
	lobby_box.add_child(lobby_info)
	lobby_list = _label("", 36, font_title)
	lobby_box.add_child(lobby_list)
	explore_btn = _button("EXPLORAR JUNTOS", func(): Net.start_race("explorar"), Color("#5fe06a"))
	lobby_box.add_child(explore_btn)
	start_btn = _button("CORRIDA DE A ATÉ B", func(): Net.start_race("corrida"))
	lobby_box.add_child(start_btn)
	lobby_box.add_child(_button("SAIR", _on_leave, Color("#ff6a5a")))
	# procurar corridas
	join_box = _box()
	join_box.add_child(_label("Jogos encontrados no mesmo Wi-Fi:", 28))
	hosts_box = VBoxContainer.new()
	hosts_box.add_theme_constant_override("separation", 10)
	join_box.add_child(hosts_box)
	join_box.add_child(_label("ou escreve o endereço do anfitrião:", 24))
	ip_edit = _edit("192.168.1.10", "")
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	join_box.add_child(ip_edit)
	join_box.add_child(_button("ENTRAR", func(): _join(ip_edit.text.strip_edges()), Color("#5fe06a")))
	join_box.add_child(_button("VOLTAR", _on_leave, Color("#ff6a5a")))
	_show(main_box)

func _show(box: Control) -> void:
	for b in [main_box, lobby_box, join_box]:
		b.visible = b == box

# ------------------------------------------------------------------ ações
func _on_solo(m: String) -> void:
	Net.leave()
	Net.mode = m
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_host() -> void:
	if Net.host_game():
		_show(lobby_box)
		_refresh_lobby()

func _on_join_screen() -> void:
	Net.start_search()
	_show(join_box)
	_refresh_hosts()
	status_lbl.text = "A procurar jogos... (os dois telemóveis têm de estar no mesmo Wi-Fi)"

func _join(ip: String) -> void:
	if ip.is_valid_ip_address():
		if Net.join_game(ip):
			_show(lobby_box)
			_refresh_lobby()
	else:
		status_lbl.text = "Endereço inválido."

func _on_leave() -> void:
	Net.leave()
	_show(main_box)
	status_lbl.text = ""

func _refresh_hosts() -> void:
	for c in hosts_box.get_children():
		c.queue_free()
	if Net.hosts.is_empty():
		hosts_box.add_child(_label("(nenhuma ainda)", 26))
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		hosts_box.add_child(_button("%s  ·  %d jog." % [h.name, h.count], _join.bind(ip), Color("#5fe06a")))

func _refresh_lobby() -> void:
	if not lobby_box.visible:
		return
	var host := Net.online and multiplayer.multiplayer_peer != null and multiplayer.is_server()
	var lines := []
	for id in Net.sorted_ids():
		var p: Dictionary = Net.players[id]
		lines.append(("● %s" % p.name) + ("  (anfitrião)" if id == 1 else ""))
	lobby_list.text = "\n".join(lines) if not lines.is_empty() else "..."
	if host:
		var ips := Net.local_ips()
		lobby_info.text = "Jogo criado! No outro telemóvel (no mesmo Wi-Fi) escolhe JOGAR A DOIS: ENTRAR.\nEndereço deste telemóvel: %s" % (", ".join(ips) if not ips.is_empty() else "?")
		var ready := Net.players.size() >= 2
		for b in [explore_btn, start_btn]:
			b.visible = true
			b.disabled = not ready
		explore_btn.text = "EXPLORAR JUNTOS" if ready else "À ESPERA DE JOGADORES..."
		start_btn.visible = ready
	else:
		lobby_info.text = "Na sala de espera. O anfitrião escolhe: explorar juntos ou corrida."
		explore_btn.visible = false
		start_btn.visible = false
