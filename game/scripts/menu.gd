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
var races_box: VBoxContainer
var event_btn: Button
var name_edit: LineEdit
var ip_edit: LineEdit
var lobby_list: Label
var lobby_info: Label
var start_btn: Button
var explore_btn: Button
var hosts_box: VBoxContainer
var status_lbl: Label
var loading_lbl: Label
var args := {}
# corridas: a grande (A até B, por todas as zonas) e as curtas geradas em map.json
var events: Array = [{"id": "grande", "name": "Grande Corrida", "type": "sprint", "laps": 1, "length": 119000.0}]

func _ready() -> void:
	preload("res://scripts/controls.gd").setup()
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
	Net.loading.connect(_show_loading)
	if args.has("mode"):
		Net.mode = String(args["mode"])
	if args.has("event"):
		Net.event = String(args["event"])
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
	elif args.has("menushot"):   # teste: fotografa o menu e sai (--races: o submenu das corridas)
		if args.has("races"):
			_show(races_box)
		get_tree().create_timer(1.5).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(String(args["menushot"]))
			get_tree().quit())
	elif not args.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not loading_lbl.visible:
		if races_box.visible:
			_show(main_box)
		elif join_box.visible or lobby_box.visible:
			_on_leave()
		get_viewport().set_input_as_handled()

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
	b.custom_minimum_size = Vector2(520, 76)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.07, 0.04, 0.78) if st != "pressed" else Color(accent, 0.55)
		sb.border_color = accent
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(22)
		if st == "focus":
			sb.border_color = Color.WHITE
			sb.bg_color = Color(0.3, 0.22, 0.09, 0.95)
			sb.set_border_width_all(6)
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
	e.custom_minimum_size = Vector2(520, 64)
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
	v.offset_top += 70     # abaixo do título
	v.offset_bottom += 70
	add_child(v)
	return v

func _load_events() -> void:
	var f := FileAccess.open("res://assets/map/events.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Array and not d.is_empty():
		events = d
	events.append(preload("res://scripts/titan_circuit.gd").event_data())

func _event_name(id: String) -> String:
	for e in events:
		if e.id == id:
			return String(e.name).to_upper()
	return id.to_upper()

func _event_text(e: Dictionary) -> String:
	var km := float(e.length) / 1000.0
	var info := ""
	if e.type == "circuit":
		info = "%d voltas · %s km" % [int(e.laps), ("%.1f" % km).replace(".", ",")]
	elif e.type == "drag":
		info = "arranque · %d m" % int(e.length)
	else:
		info = "de A até B · %d km" % int(round(km))
	var cfg := ConfigFile.new()
	if cfg.load("user://save.cfg") == OK:
		var b := float(cfg.get_value("race_v6", String(e.id), 0.0))
		if b > 0.0:
			info += " · recorde %s" % _fmt(b)
	return "%s   (%s)" % [String(e.name).to_upper(), info]

static func _fmt(t: float) -> String:
	var h := int(t / 3600.0)
	var m := int(t / 60.0) % 60
	var sec := int(t) % 60
	var c := int((t - floor(t)) * 100.0)
	if h > 0:
		return "%d:%02d:%02d,%02d" % [h, m, sec, c]
	return "%02d:%02d,%02d" % [m, sec, c]

func _build() -> void:
	var quality_script = preload("res://scripts/visual_quality.gd")
	var quality_button := OptionButton.new()
	for label in quality_script.LABELS:
		quality_button.add_item(label)
	quality_button.select(quality_script.NAMES.find(quality_script.selected()))
	quality_button.item_selected.connect(func(index: int): quality_script.save(quality_script.NAMES[index]))
	quality_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quality_button.position = Vector2(-252, 12)
	quality_button.size = Vector2(240, 40)
	quality_button.add_theme_font_size_override("font_size", 18)
	# Inserido depois do fundo para permanecer visível.
	_load_events()
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
	add_child(quality_button)
	# principal
	main_box = _box()
	name_edit = _edit("O teu nome", "Jogador")
	name_edit.text_changed.connect(func(t): Net.my_name = t)
	main_box.add_child(name_edit)
	main_box.add_child(_button("EXPLORAR O MUNDO", _on_solo.bind("explorar"), Color("#5fe06a")))
	main_box.add_child(_button("CORRIDAS", func(): _show(races_box)))
	main_box.add_child(_button("REDE LOCAL: CRIAR", _on_host, Color("#7ff6ff")))
	main_box.add_child(_button("REDE LOCAL: ENTRAR", _on_join_screen, Color("#7ff6ff")))
	# sala de espera (anfitrião e convidados)
	lobby_box = _box()
	lobby_info = _label("", 28)
	lobby_info.custom_minimum_size = Vector2(900, 0)
	lobby_box.add_child(lobby_info)
	lobby_list = _label("", 36, font_title)
	lobby_box.add_child(lobby_list)
	explore_btn = _button("EXPLORAR JUNTOS", func(): Net.start_race("explorar"), Color("#5fe06a"))
	lobby_box.add_child(explore_btn)
	event_btn = _button("", _next_event, Color("#ff8ad8"))
	lobby_box.add_child(event_btn)
	start_btn = _button("COMEÇAR A CORRIDA", func(): Net.start_race("corrida", Net.event))
	lobby_box.add_child(start_btn)
	lobby_box.add_child(_button("SAIR", _on_leave, Color("#ff6a5a")))
	# escolher a corrida (sozinho)
	races_box = _box()
	races_box.add_theme_constant_override("separation", 12)
	for e in events:
		var col := Color("#ffb347")
		if e.type == "circuit":
			col = Color("#ff8ad8")
		elif e.type == "drag":
			col = Color("#7ff6ff")
		var b := _button(_event_text(e), _on_race.bind(String(e.id)), col)
		b.add_theme_font_size_override("font_size", 30)
		b.custom_minimum_size.y = 64
		races_box.add_child(b)
	races_box.add_child(_button("VOLTAR", func(): _show(main_box), Color("#ff6a5a")))
	# procurar corridas
	join_box = _box()
	join_box.add_child(_label("PC e Android · até 4 jogadores no mesmo Wi-Fi", 25))
	hosts_box = VBoxContainer.new()
	hosts_box.add_theme_constant_override("separation", 10)
	join_box.add_child(hosts_box)
	join_box.add_child(_label("ou escreve o endereço do anfitrião:", 24))
	ip_edit = _edit("192.168.1.10", "")
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	join_box.add_child(ip_edit)
	join_box.add_child(_button("ENTRAR", func(): _join(ip_edit.text.strip_edges()), Color("#5fe06a")))
	join_box.add_child(_button("VOLTAR", _on_leave, Color("#ff6a5a")))
	loading_lbl = _label("A CARREGAR O MUNDO...", 64, font_title)
	loading_lbl.add_theme_color_override("font_color", Color("#ffd36e"))
	loading_lbl.set_anchors_preset(Control.PRESET_CENTER)
	loading_lbl.position = Vector2(-600, -60)
	loading_lbl.size = Vector2(1200, 120)
	loading_lbl.visible = false
	add_child(loading_lbl)
	_show(main_box)

func _show_loading() -> void:
	_show(null)
	status_lbl.text = ""
	loading_lbl.visible = true

func _show(box: Control) -> void:
	for b in [main_box, lobby_box, join_box, races_box]:
		b.visible = b == box
	preload("res://scripts/controls.gd").focus_first(box)

# ------------------------------------------------------------------ ações
func _on_solo(m: String) -> void:
	Net.leave()
	Net.mode = m
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_race(id: String) -> void:
	Net.event = id
	_on_solo("corrida")

## Anfitrião: troca a corrida que vão fazer juntos.
func _next_event() -> void:
	var i := 0
	for k in events.size():
		if events[k].id == Net.event:
			i = k
	Net.event = String(events[(i + 1) % events.size()].id)
	_refresh_lobby()

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
	var owner := get_viewport().gui_get_focus_owner()
	var restore := owner != null and hosts_box.is_ancestor_of(owner)
	for c in hosts_box.get_children():
		hosts_box.remove_child(c)
		c.queue_free()
	if Net.hosts.is_empty():
		hosts_box.add_child(_label("(nenhuma ainda)", 26))
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		hosts_box.add_child(_button("%s  ·  %d jog." % [h.name, h.count], _join.bind(ip), Color("#5fe06a")))

	if restore:
		preload("res://scripts/controls.gd").focus_first(join_box)

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
		event_btn.visible = ready
		event_btn.text = "PISTA: %s  ▸" % _event_name(Net.event)
	else:
		lobby_info.text = "Na sala de espera. O anfitrião escolhe: explorar juntos ou corrida."
		explore_btn.visible = false
		start_btn.visible = false
		event_btn.visible = false

	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus.is_visible_in_tree() or (focus is Button and focus.disabled):
		preload("res://scripts/controls.gd").focus_first(lobby_box)
