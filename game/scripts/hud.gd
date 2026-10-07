extends CanvasLayer
## Interface: cronómetro, portões, recorde, velocidade, minimapa (3 km à volta do veículo),
## seta para o próximo portão, nome da zona, contagem 3-2-1, mensagens, pausa,
## ecrã do MAPA (mundo inteiro; na exploração toca-se para viajar) e resultados do PvP.

signal camera_pressed
signal pause_action(action: String)   # "portao", "recomecar", "menu"
signal travel_requested(world: Vector2)

const MINI_SPAN := 3000.0              # metros mostrados no minimapa

var font_title: Font = preload("res://assets/fonts/RussoOne.woff2")
var font_body: Font
var root: Control
var time_label: Label
var cp_label: Label
var best_label: Label
var speed_label: Label
var center_label: Label
var sub_label: Label
var hint_label: Label
var zone_label: Label
var arrow: Control
var minimap: Control
var minimap_tex: Texture2D = preload("res://assets/map/minimap.png")
var map_size := 24576.0
var player_pos := Vector2.ZERO
var player_heading := 0.0
var next_cp := Vector2.ZERO
var has_target := true
var arrow_angle := 0.0
var show_arrow := false
var player: Node            # para acender os botões de toque quando premidos
var pads: Control
var multiplayer_mode := false
var explore := false
var pause_panel: Control
var results_panel: Control
var results_label: Label
var standings_label: RichTextLabel
var remote_dots: Array = []   # [[Vector2 posição, Color, nome]] dos outros jogadores
var zones: Array = []         # [{name, c}] para o mapa grande
var gates: Array = []         # [Vector2] portões do circuito (mapa grande)
var next_gate := 0
var map_panel: Control
var map_view: Control
var map_hint: Label
var _zone_t := 0.0

func _ready() -> void:
	var fv := FontVariation.new()
	fv.base_font = preload("res://assets/fonts/Nunito.woff2")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	font_body = fv
	process_mode = Node.PROCESS_MODE_ALWAYS   # o menu de pausa e o mapa funcionam com o jogo parado
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	time_label = _label(font_title, 54, 0.0, 1.0, 0.0, HORIZONTAL_ALIGNMENT_CENTER, 10)
	cp_label = _label(font_title, 28, 0.0, 1.0, 0.0, HORIZONTAL_ALIGNMENT_LEFT, 22)
	best_label = _label(font_body, 22, 0.0, 1.0, 0.0, HORIZONTAL_ALIGNMENT_RIGHT, 24)
	speed_label = _label(font_title, 44, 0.0, 1.0, 1.0, HORIZONTAL_ALIGNMENT_RIGHT, 232)
	center_label = _label(font_title, 110, 0.0, 1.0, 0.5, HORIZONTAL_ALIGNMENT_CENTER, -90)
	sub_label = _label(font_body, 30, 0.0, 1.0, 0.5, HORIZONTAL_ALIGNMENT_CENTER, 40)
	hint_label = _label(font_body, 22, 0.0, 1.0, 0.5, HORIZONTAL_ALIGNMENT_CENTER, 92)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	zone_label = _label(font_title, 58, 0.0, 1.0, 0.0, HORIZONTAL_ALIGNMENT_CENTER, 182)
	zone_label.add_theme_color_override("font_color", Color("#ffd36e"))
	zone_label.modulate.a = 0.0
	# seta para o próximo portão
	arrow = Control.new()
	arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	arrow.position = Vector2(-40, 92)
	arrow.size = Vector2(80, 80)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(_draw_arrow)
	root.add_child(arrow)
	# botões de toque desenhados (só desenho: o toque é lido pelo veículo)
	pads = Control.new()
	pads.set_anchors_preset(Control.PRESET_FULL_RECT)
	pads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pads.draw.connect(_draw_pads)
	root.add_child(pads)
	# minimapa
	minimap = Control.new()
	minimap.position = Vector2(22, 72)
	minimap.size = Vector2(220, 220)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)
	# botões
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.position = Vector2(-390, 62)
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)
	bar.add_child(_button("CÂMARA", func(): camera_pressed.emit()))
	bar.add_child(_button("MAPA", func(): open_map()))
	bar.add_child(_button("II", func(): _toggle_pause()))
	# classificação (PvP)
	standings_label = RichTextLabel.new()
	standings_label.bbcode_enabled = true
	standings_label.fit_content = true
	standings_label.scroll_active = false
	standings_label.anchor_left = 1.0
	standings_label.anchor_right = 1.0
	standings_label.position = Vector2(-330, 136)
	standings_label.size = Vector2(310, 200)
	standings_label.add_theme_font_override("normal_font", font_title)
	standings_label.add_theme_font_size_override("normal_font_size", 26)
	standings_label.add_theme_constant_override("outline_size", 6)
	standings_label.add_theme_color_override("font_outline_color", Color("#2a1a10"))
	standings_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(standings_label)
	# pausa
	pause_panel = _panel()
	var pv: VBoxContainer = pause_panel.get_child(0)
	pv.add_child(_big_button("CONTINUAR", func():
		pause_panel.visible = false
		_update_pause()))
	pv.add_child(_big_button("VOLTAR AO PORTÃO", _pause_and.bind("portao")))
	pv.add_child(_big_button("RECOMEÇAR", _pause_and.bind("recomecar")))
	pv.add_child(_big_button("MENU", _pause_and.bind("menu")))
	# resultados (PvP)
	results_panel = _panel()
	var rv: VBoxContainer = results_panel.get_child(0)
	results_label = Label.new()
	_style(results_label, font_title, 34)
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(results_label)
	rv.add_child(_big_button("NOVA CORRIDA", func(): pause_action.emit("recomecar")))
	rv.add_child(_big_button("MENU", func(): pause_action.emit("menu")))
	# mapa grande
	map_panel = ColorRect.new()
	(map_panel as ColorRect).color = Color(0.05, 0.03, 0.02, 0.82)
	map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.visible = false
	root.add_child(map_panel)
	map_view = Control.new()
	map_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map_view.draw.connect(_draw_big_map)
	map_view.gui_input.connect(_on_map_input)
	map_panel.add_child(map_view)
	map_hint = Label.new()
	_style(map_hint, font_body, 26)
	map_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	map_hint.offset_top = -56
	map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_panel.add_child(map_hint)
	var close := _big_button("FECHAR", func():
		map_panel.visible = false
		_update_pause())
	close.custom_minimum_size = Vector2(220, 70)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.position = Vector2(-250, 24)
	map_panel.add_child(close)

func set_mode(is_explore: bool) -> void:
	explore = is_explore
	time_label.visible = not explore
	cp_label.visible = not explore
	best_label.visible = not explore
	var portao: Button = pause_panel.get_child(0).get_child(1)
	portao.text = "VOLTAR AO CAMINHO" if explore else "VOLTAR AO PORTÃO"
	var rec: Button = pause_panel.get_child(0).get_child(2)
	rec.visible = not explore

func _panel() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.03, 0.02, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.visible = false
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.add_child(v)
	root.add_child(bg)
	return bg

func _big_button(text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	b.custom_minimum_size = Vector2(440, 76)
	b.add_theme_font_size_override("font_size", 30)
	return b

func _pause_and(action: String) -> void:
	pause_panel.visible = false
	_update_pause()
	pause_action.emit(action)

## Sozinho, o jogo pára enquanto a pausa ou o mapa estão abertos (no PvP o mundo continua).
func _update_pause() -> void:
	get_tree().paused = not multiplayer_mode and (pause_panel.visible or map_panel.visible)

func _toggle_pause() -> void:
	pause_panel.visible = not pause_panel.visible
	var rec: Button = pause_panel.get_child(0).get_child(2)
	rec.visible = not explore and (not multiplayer_mode or multiplayer.is_server())
	rec.text = "NOVA CORRIDA (TODOS)" if multiplayer_mode else "RECOMEÇAR"
	_update_pause()

func open_map() -> void:
	pause_panel.visible = false
	map_panel.visible = true
	var s := root.size
	var side := minf(s.y - 90.0, s.x - 300.0)
	map_view.position = Vector2((s.x - side) * 0.5, 20.0)
	map_view.size = Vector2(side, side)
	map_hint.text = "Toca num sítio do mapa para ir para lá" if explore else "Circuito: segue os portões até à META"
	map_view.queue_redraw()
	_update_pause()

## Classificação ao vivo no PvP: [[nome, cor, sou_eu, tempo_de_chegada]] por ordem.
func set_standings(rows: Array) -> void:
	var lines := []
	for i in rows.size():
		var r: Array = rows[i]
		var t: String = ("  " + fmt_time(r[3])) if r[3] > 0.0 else ""
		var nm: String = ("[u]%s[/u]" % r[0]) if r[2] else r[0]
		if explore:
			lines.append("[right][color=#%s]● %s[/color][/right]" % [r[1].to_html(false), nm])
		else:
			lines.append("[right][color=#%s]%dº %s%s[/color][/right]" % [r[1].to_html(false), i + 1, nm, t])
	standings_label.text = "\n".join(lines)
	results_label.text = "RESULTADOS\n\n" + "\n".join(rows.map(func(r): return "%s   %s" % [r[0], fmt_time(r[3]) if r[3] > 0.0 else "--"]))

func show_results(is_host: bool) -> void:
	results_panel.visible = true
	results_panel.get_child(0).get_child(1).visible = is_host

func show_zone(text: String) -> void:
	zone_label.text = text.to_upper()
	_zone_t = 3.5

func _process(dt: float) -> void:
	if _zone_t > 0.0:
		_zone_t -= dt
		zone_label.modulate.a = clampf(_zone_t / 0.8, 0.0, 1.0) * clampf((3.5 - _zone_t) / 0.4, 0.0, 1.0)
	if map_panel.visible:
		map_view.queue_redraw()

func _style(l: Label, f: Font, size: int) -> void:
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color("#2a1a10"))
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))

func _label(f: Font, size: int, al: float, ar: float, av: float, align: int, offset: float) -> Label:
	var l := Label.new()
	_style(l, f, size)
	l.horizontal_alignment = align
	l.anchor_left = al
	l.anchor_right = ar
	l.anchor_top = av
	l.anchor_bottom = av
	l.offset_left = 28
	l.offset_right = -28
	if av == 0.0:
		l.offset_top = offset
		l.offset_bottom = offset + size * 1.4
	elif av == 1.0:
		l.offset_top = -offset - size * 1.4
		l.offset_bottom = -offset
	else:
		l.offset_top = offset
		l.offset_bottom = offset + size * 1.4
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_title)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(110 if text.length() > 2 else 70, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.06, 0.04, 0.55)
	sb.border_color = Color(1, 0.85, 0.55, 0.8)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color("#ffe3a8"))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

static func fmt_time(t: float) -> String:
	if t <= 0.0 or t > 35999.0:
		return "--:--,--"
	var h := int(t / 3600.0)
	var m := int(t / 60.0) % 60
	var s := int(t) % 60
	var c := int((t - floor(t)) * 100.0)
	if h > 0:
		return "%d:%02d:%02d,%02d" % [h, m, s, c]
	return "%02d:%02d,%02d" % [m, s, c]

func set_race(time: float, best: float, cp: int, cp_total: int, kmh: float) -> void:
	time_label.text = fmt_time(time) if time > 0.0 else "00:00,00"
	best_label.text = "RECORDE  " + fmt_time(best)
	cp_label.text = "PORTÃO %d/%d" % [mini(cp + 1, cp_total), cp_total] if cp < cp_total else "RUMO À META!"
	speed_label.text = "%d km/h" % int(kmh)
	next_gate = cp

func set_center(text: String, sub := "", hint := "") -> void:
	center_label.text = text
	sub_label.text = sub
	hint_label.text = hint

func set_nav(ppos: Vector3, heading: float, target: Vector3, target_on := true) -> void:
	player_pos = Vector2(ppos.x, ppos.z)
	player_heading = heading
	next_cp = Vector2(target.x, target.z)
	has_target = target_on
	var to := next_cp - player_pos
	var want := atan2(-to.x, -to.y)
	arrow_angle = wrapf(want - heading, -PI, PI)
	show_arrow = has_target and absf(arrow_angle) > 0.45
	arrow.queue_redraw()
	minimap.queue_redraw()
	pads.queue_redraw()

func _pad(c: Vector2, r: float, on: bool, text: String, col: Color) -> void:
	pads.draw_circle(c, r, Color(col, 0.42 if on else 0.16))
	pads.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.85 if on else 0.45), 4.0, true)
	if text == "<" or text == ">":   # seta desenhada (não depende da fonte ter o símbolo)
		var d := -1.0 if text == "<" else 1.0
		var tri := PackedVector2Array([c + Vector2(30 * d, 0), c + Vector2(-18 * d, -28), c + Vector2(-18 * d, 28)])
		pads.draw_colored_polygon(tri, Color(1, 1, 1, 0.95 if on else 0.7))
		return
	var fs := 24
	var w := font_title.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	pads.draw_string_outline(font_title, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.1, 0.05, 0.02, 0.8))
	pads.draw_string(font_title, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95 if on else 0.7))

func _draw_pads() -> void:
	var s := pads.size
	var l: bool = player != null and player.input_left
	var r: bool = player != null and player.input_right
	var b: bool = player != null and player.braking and player.running
	_pad(Vector2(s.x * 0.09, s.y - 110), 72.0, l, "<", Color("#7ff6ff"))
	_pad(Vector2(s.x * 0.27, s.y - 110), 72.0, r, ">", Color("#7ff6ff"))
	_pad(Vector2(s.x - 150, s.y - 125), 92.0, b, "TRAVÃO", Color("#ff5a3c"))

func _draw_arrow() -> void:
	if not show_arrow:
		return
	var c := Vector2(40, 40)
	var a := -arrow_angle
	var pts := PackedVector2Array([Vector2(0, -34), Vector2(22, 18), Vector2(0, 6), Vector2(-22, 18)])
	for i in pts.size():
		pts[i] = c + pts[i].rotated(a)
	arrow.draw_colored_polygon(pts, Color("#7ff6ff"))
	arrow.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#0b2a33"), 4.0)

func _player_marker(ci: CanvasItem, pp: Vector2, sz: float) -> void:
	var fwd := Vector2(-sin(player_heading), -cos(player_heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([pp + fwd * sz * 1.6, pp - fwd * sz + side * sz, pp - fwd * sz - side * sz])
	ci.draw_colored_polygon(tri, Color("#ff4f4f"))
	ci.draw_polyline(tri + PackedVector2Array([tri[0]]), Color.WHITE, 2.0)

## Minimapa: janela de MINI_SPAN metros à volta do veículo (norte para cima).
func _draw_minimap() -> void:
	var r := Rect2(Vector2.ZERO, minimap.size)
	minimap.draw_rect(r, Color(0.1, 0.06, 0.04, 0.6))
	var tex_size := minimap_tex.get_size()
	var px_per_m := tex_size.x / map_size
	var center_px := (player_pos / map_size + Vector2(0.5, 0.5)) * tex_size
	var span_px := MINI_SPAN * px_per_m
	var src := Rect2(center_px - Vector2(span_px, span_px) * 0.5, Vector2(span_px, span_px))
	minimap.draw_texture_rect_region(minimap_tex, r, src, Color(1, 1, 1, 0.92))
	var scale := minimap.size.x / MINI_SPAN
	var mid := minimap.size * 0.5
	var to_mini := func(w: Vector2) -> Vector2: return mid + (w - player_pos) * scale
	if has_target:
		var q: Vector2 = to_mini.call(next_cp)
		var clamped := Vector2(clampf(q.x, 8, minimap.size.x - 8), clampf(q.y, 8, minimap.size.y - 8))
		minimap.draw_circle(clamped, 7.0 if clamped == q else 5.0, Color("#7ff6ff"))
		minimap.draw_arc(clamped, 7.0, 0.0, TAU, 16, Color("#0b2a33"), 2.0)
	for d in remote_dots:
		var q: Vector2 = to_mini.call(d[0])
		q = Vector2(clampf(q.x, 6, minimap.size.x - 6), clampf(q.y, 6, minimap.size.y - 6))
		minimap.draw_circle(q, 6.0, d[1])
		minimap.draw_arc(q, 6.0, 0.0, TAU, 16, Color.WHITE, 1.5)
	_player_marker(minimap, mid, 7.0)
	minimap.draw_rect(r, Color(1, 0.85, 0.55, 0.7), false, 3.0)

func _world_to_big(w: Vector2) -> Vector2:
	return (w / map_size + Vector2(0.5, 0.5)) * map_view.size

func _draw_big_map() -> void:
	var r := Rect2(Vector2.ZERO, map_view.size)
	map_view.draw_texture_rect(minimap_tex, r, false)
	map_view.draw_rect(r, Color(1, 0.85, 0.55, 0.8), false, 3.0)
	var fs := clampi(int(map_view.size.x / 52.0), 12, 22)
	for z in zones:
		var p := _world_to_big(Vector2(z.c[0], z.c[1]))
		var w := font_title.get_string_size(z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		map_view.draw_string_outline(font_title, p + Vector2(-w * 0.5, -map_view.size.y * 0.09), z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.1, 0.05, 0.02, 0.9))
		map_view.draw_string(font_title, p + Vector2(-w * 0.5, -map_view.size.y * 0.09), z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff1d6"))
	if not explore:
		for i in gates.size():
			if i >= next_gate:
				map_view.draw_circle(_world_to_big(gates[i]), 7.0 if i == next_gate else 4.0, Color("#7ff6ff") if i == next_gate else Color(1, 1, 1, 0.8))
	for d in remote_dots:
		var q := _world_to_big(d[0])
		map_view.draw_circle(q, 9.0, d[1])
		map_view.draw_arc(q, 9.0, 0.0, TAU, 16, Color.WHITE, 2.0)
		if d.size() > 2:
			map_view.draw_string_outline(font_body, q + Vector2(12, 6), d[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0.1, 0.05, 0.02, 0.9))
			map_view.draw_string(font_body, q + Vector2(12, 6), d[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, d[1].lightened(0.3))
	_player_marker(map_view, _world_to_big(player_pos), 10.0)

func _on_map_input(e: InputEvent) -> void:
	if not explore:
		return
	var pressed: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if pressed:
		var w: Vector2 = (e.position / map_view.size - Vector2(0.5, 0.5)) * map_size
		map_panel.visible = false
		_update_pause()
		travel_requested.emit(w)
