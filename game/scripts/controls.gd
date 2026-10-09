extends RefCounted
## Godot/SDL normaliza DualShock 4 e DualSense (USB/Bluetooth) para estes botões.
## device=-1 aceita também comandos ligados depois de abrir o jogo.
static func setup() -> void:
	var keys := {"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D],
		"brake": [KEY_DOWN, KEY_S, KEY_SPACE], "recover": [KEY_R],
		"camera_cycle": [KEY_C], "pause_game": [KEY_ESCAPE], "nitro": [KEY_SHIFT], "camera_center": [KEY_V]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			_bind(action, event)
			# Teclas lógicas também chegam por teclados virtuais/acessibilidade.
			if key in [KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_ESCAPE]:
				var logical := InputEventKey.new()
				logical.keycode = key
				_bind(action, logical)
	_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis("nitro", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_button("nitro", JOY_BUTTON_A) # X durante a corrida
	_button("camera_center", JOY_BUTTON_RIGHT_STICK)
	for action in ["look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_button("steer_left", JOY_BUTTON_DPAD_LEFT)
	_button("steer_right", JOY_BUTTON_DPAD_RIGHT)
	_button("brake", JOY_BUTTON_X) # Quadrado
	_button("recover", JOY_BUTTON_Y) # Triângulo
	_button("camera_cycle", JOY_BUTTON_B) # Círculo
	_button("pause_game", JOY_BUTTON_START) # Options
	# Navegação nativa dos Control: X confirma, Círculo volta.
	_button("ui_accept", JOY_BUTTON_A)
	_button("ui_cancel", JOY_BUTTON_B)
	for item in [["ui_left", JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0],
		["ui_right", JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
		["ui_up", JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0],
		["ui_down", JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0]]:
		_button(item[0], item[1])
		_axis(item[0], item[2], item[3])

static func _bind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

static func _button(action: StringName, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	_bind(action, event)

static func _axis(action: StringName, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = value
	_bind(action, event)

static func focus_first(parent: Node) -> bool:
	if parent == null or (parent is CanvasItem and not parent.is_visible_in_tree()):
		return false
	if parent is Button and not parent.disabled and parent.focus_mode != Control.FOCUS_NONE:
		parent.grab_focus()
		return true
	for child in parent.get_children():
		if focus_first(child):
			return true
	return false

static func hint() -> String:
	if not Input.get_connected_joypads().is_empty():
		return "Analógico / direcional: virar · L2 / Quadrado: travar · Triângulo: recuperar · R2 / X: nitro · analógico direito: câmera"
	if OS.has_feature("mobile"):
		return "Esquerda do ecrã: virar · direita: TRAVÃO DE MÃO (travar + virar = derrapar)"
	return "← → / A D: virar · ↓ / Espaço: travar · Shift: nitro · R: recuperar · C: câmera · Esc: pausa · Aceleração automática"

static func nitro_touch_rect(size: Vector2) -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 90.0, size.y - 96.0), Vector2(180, 72))
