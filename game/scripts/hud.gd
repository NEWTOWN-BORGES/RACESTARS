extends CanvasLayer
## Interface da corrida: cronómetro, portões, recorde, velocidade, minimapa,
## seta para o próximo portão, contagem 3-2-1, mensagens e tela de chegada.

signal camera_pressed
signal restart_pressed

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
var arrow: Control
var minimap: Control
var minimap_tex: Texture2D = preload("res://assets/map/minimap.png")
var map_size := 4096.0
var player_pos := Vector2.ZERO
var player_heading := 0.0
var next_cp := Vector2.ZERO
var arrow_angle := 0.0
var show_arrow := false
var player: Node            # para acender os botões de toque quando premidos
var pads: Control
var paths_drawn := false

func _ready() -> void:
	var fv := FontVariation.new()
	fv.base_font = preload("res://assets/fonts/Nunito.woff2")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	font_body = fv
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
	minimap.size = Vector2(200, 200)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)
	# botões
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.position = Vector2(-250, 62)
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)
	bar.add_child(_button("CÂMARA", func(): camera_pressed.emit()))
	bar.add_child(_button("↺", func(): restart_pressed.emit()))

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
	if t <= 0.0 or t > 3599.0:
		return "--:--,--"
	var m := int(t / 60.0)
	var s := int(t) % 60
	var c := int((t - floor(t)) * 100.0)
	return "%02d:%02d,%02d" % [m, s, c]

func set_race(time: float, best: float, cp: int, cp_total: int, kmh: float) -> void:
	time_label.text = fmt_time(time) if time > 0.0 else "00:00,00"
	best_label.text = "RECORDE  " + fmt_time(best)
	cp_label.text = "PORTÃO %d/%d" % [mini(cp + 1, cp_total), cp_total] if cp < cp_total else "RUMO À META!"
	speed_label.text = "%d km/h" % int(kmh)

func set_center(text: String, sub := "", hint := "") -> void:
	center_label.text = text
	sub_label.text = sub
	hint_label.text = hint

func set_nav(ppos: Vector3, heading: float, target: Vector3) -> void:
	player_pos = Vector2(ppos.x, ppos.z)
	player_heading = heading
	next_cp = Vector2(target.x, target.z)
	var to := next_cp - player_pos
	var want := atan2(-to.x, -to.y)
	arrow_angle = wrapf(want - heading, -PI, PI)
	show_arrow = absf(arrow_angle) > 0.45
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

func _to_map(p: Vector2) -> Vector2:
	return (p / map_size + Vector2(0.5, 0.5)) * minimap.size

func _draw_minimap() -> void:
	var r := Rect2(Vector2.ZERO, minimap.size)
	minimap.draw_rect(r.grow(4), Color(0.1, 0.06, 0.04, 0.6))
	minimap.draw_texture_rect(minimap_tex, r, false, Color(1, 1, 1, 0.9))
	minimap.draw_circle(_to_map(next_cp), 7.0, Color("#7ff6ff"))
	var pp := _to_map(player_pos)
	var fwd := Vector2(-sin(player_heading), -cos(player_heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([pp + fwd * 11, pp - fwd * 7 + side * 7, pp - fwd * 7 - side * 7])
	minimap.draw_colored_polygon(tri, Color("#ff4f4f"))
	minimap.draw_polyline(tri + PackedVector2Array([tri[0]]), Color.WHITE, 2.0)
