extends CanvasLayer
## Interface: distância, velocidade, recorde, avisos e telas de início/batida.

var font_title: Font = preload("res://assets/fonts/RussoOne.woff2")
var font_body: Font

var dist_label: Label
var speed_label: Label
var best_label: Label
var warn_label: Label
var panel: VBoxContainer
var title_label: Label
var msg_label: Label
var hint_label: Label

func _ready() -> void:
	var fv := FontVariation.new()
	fv.base_font = preload("res://assets/fonts/Nunito.woff2")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	font_body = fv
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	dist_label = _label(root, font_title, 52, true, HORIZONTAL_ALIGNMENT_CENTER, 14.0)
	best_label = _label(root, font_body, 24, true, HORIZONTAL_ALIGNMENT_RIGHT, 24.0)
	speed_label = _label(root, font_title, 40, false, HORIZONTAL_ALIGNMENT_LEFT, 24.0)
	warn_label = _label(root, font_title, 30, true, HORIZONTAL_ALIGNMENT_CENTER, 86.0)
	warn_label.add_theme_color_override("font_color", Color("#ffe08a"))
	panel = VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 10)
	root.add_child(panel)
	title_label = _plain(panel, font_title, 96)
	msg_label = _plain(panel, font_body, 32)
	hint_label = _plain(panel, font_body, 22)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))

func _style(l: Label, f: Font, size: int) -> void:
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color("#1c1e48"))
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _label(parent: Control, f: Font, size: int, top: bool, align: int, margin: float) -> Label:
	## Faixa da largura da tela (no topo ou embaixo); o alinhamento escolhe o canto.
	var l := Label.new()
	_style(l, f, size)
	l.horizontal_alignment = align
	parent.add_child(l)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 0.0 if top else 1.0
	l.anchor_bottom = 0.0 if top else 1.0
	l.offset_left = 30.0
	l.offset_right = -30.0
	l.offset_top = margin if top else -margin - size * 1.4
	l.offset_bottom = margin + size * 1.4 if top else -margin
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _plain(parent: Control, f: Font, size: int) -> Label:
	var l := Label.new()
	_style(l, f, size)
	parent.add_child(l)
	return l

func _center_panel() -> void:
	panel.reset_size()
	panel.position = (get_viewport().get_visible_rect().size - panel.size) * 0.5

func show_menu(best: float) -> void:
	panel.visible = true
	title_label.text = "RACESTARS"
	msg_label.text = "Toque ou aperte ESPAÇO para correr"
	hint_label.text = "Desvie: ← →  /  A D  ou segure os lados da tela"
	best_label.text = "RECORDE  %d m" % int(best) if best > 0.0 else ""
	dist_label.text = ""
	speed_label.text = ""
	warn_label.text = ""
	_center_panel()

func show_run() -> void:
	panel.visible = false

func update_run(dist: float, kmh: float, best: float, ridge_in: float, in_tunnel: bool) -> void:
	dist_label.text = "%d m" % int(dist)
	speed_label.text = "%d km/h" % int(kmh)
	best_label.text = "RECORDE  %d m" % int(maxf(best, dist))
	if in_tunnel:
		warn_label.text = ""
	elif ridge_in > 0.0 and ridge_in < 600.0:
		warn_label.text = "TÚNEIS À FRENTE  ·  %d m" % int(ridge_in)
	else:
		warn_label.text = ""

func show_crash(dist: float, best: float, record: bool) -> void:
	panel.visible = true
	title_label.text = "BATEU!"
	msg_label.text = ("NOVO RECORDE!  %d m" if record else "%d m") % int(dist)
	hint_label.text = "Toque ou aperte ESPAÇO para correr de novo"
	warn_label.text = ""
	_center_panel()
