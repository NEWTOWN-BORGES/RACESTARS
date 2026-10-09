extends Node3D
## Circuito suspenso: geometria, portões e saltos vêm da mesma rota determinística.
## Apenas acrescenta estruturas; não escreve no mapa, no terreno ou na física do carro.

const CENTER := Vector3(9500.0, 440.0, 1000.0)
const HALF_WIDTH := 42.0
const RAMP_LENGTH := 100.0
const GAP_LENGTH := 36.0
const RAMP_RISE := 14.054
const STEP := 20.0
var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _faces := PackedVector3Array()
var _cube: BoxMesh
var _unit_faces := PackedVector3Array()

static func _jumps() -> Array:
	return [
		{"origin": CENTER + Vector3(-500, 0, -640), "dir": Vector3.RIGHT, "ramp_start": 240.0},
		{"origin": CENTER + Vector3(760, 0, -420), "dir": Vector3.BACK, "ramp_start": 220.0},
	]

static func _line(points: Array, a: Vector3, b: Vector3, ramp_start := -1.0) -> void:
	var length := a.distance_to(b)
	var samples: Array[float] = []
	for i in range(1, ceili(length / STEP) + 1):
		samples.append(minf(float(i) * STEP, length))
	if ramp_start >= 0.0:
		for s in [ramp_start, ramp_start + RAMP_LENGTH, ramp_start + RAMP_LENGTH + GAP_LENGTH]:
			if not samples.has(s):
				samples.append(s)
	samples.sort()
	for s in samples:
		var p := a.lerp(b, s / length)
		if ramp_start >= 0.0:
			if s >= ramp_start and s <= ramp_start + RAMP_LENGTH:
				p.y += (s - ramp_start) / RAMP_LENGTH * RAMP_RISE
			elif s > ramp_start + RAMP_LENGTH and s < ramp_start + RAMP_LENGTH + GAP_LENGTH:
				p.y += RAMP_RISE * (1.0 - (s - ramp_start - RAMP_LENGTH) / GAP_LENGTH)
		points.append(p)

static func _arc(points: Array, c: Vector3, radius: float, begin: float, end: float) -> void:
	var count := ceili(absf(end - begin) * radius / STEP)
	for i in range(1, count + 1):
		var a := lerpf(begin, end, float(i) / count)
		points.append(c + Vector3(cos(a) * radius, 0, sin(a) * radius))

static func _path() -> Array:
	var p: Array = [CENTER + Vector3(-500, 0, -640)]
	_line(p, p.back(), CENTER + Vector3(540, 0, -640), 240.0)
	_arc(p, CENTER + Vector3(540, 0, -420), 220, -PI / 2, 0)
	_line(p, p.back(), CENTER + Vector3(760, 0, 420), 220.0)
	_arc(p, CENTER + Vector3(540, 0, 420), 220, 0, PI / 2)
	_line(p, p.back(), CENTER + Vector3(-540, 0, 640))
	_arc(p, CENTER + Vector3(-540, 0, 480), 160, PI / 2, PI * 1.5)
	_line(p, p.back(), CENTER + Vector3(300, 0, 320))
	_arc(p, CENTER + Vector3(300, 0, 160), 160, PI / 2, -PI / 2)
	_line(p, p.back(), CENTER + Vector3(-500, 0, 0))
	_arc(p, CENTER + Vector3(-500, 0, -220), 220, PI / 2, PI)
	_line(p, p.back(), CENTER + Vector3(-720, 0, -420))
	_arc(p, CENTER + Vector3(-500, 0, -420), 220, PI, PI * 1.5)
	p[p.size() - 1] = p[0]
	return p

static func _array(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

static func _is_gap(p: Vector3) -> bool:
	for jump in _jumps():
		var delta: Vector3 = p - jump.origin
		var d: Vector3 = jump.dir
		var along := delta.dot(d)
		var side := delta - d * along
		if Vector2(side.x, side.z).length() < HALF_WIDTH + 1.0 and along > jump.ramp_start + RAMP_LENGTH + 0.01 and along < jump.ramp_start + RAMP_LENGTH + GAP_LENGTH - 0.01:
			return true
	return false

static func _bypass_open(p: Vector3) -> bool:
	for jump in _jumps():
		var delta: Vector3 = p - jump.origin
		var d: Vector3 = jump.dir
		var along := delta.dot(d)
		var side := delta - d * along
		if Vector2(side.x, side.z).length() < 2.0:
			var s: float = jump.ramp_start
			if (along >= s - 150.0 and along <= s - 35.0) or (along >= s + 345.0 and along <= s + 475.0):
				return true
	return false

static func event_data() -> Dictionary:
	var points := _path()
	var route: Array = []
	var gates: Array = []
	var length := 0.0
	var since_gate := 0.0
	for i in points.size():
		var p: Vector3 = points[i]
		route.append(_array(p))
		if i == 0:
			continue
		var segment: float = p.distance_to(points[i - 1])
		length += segment
		since_gate += segment
		if since_gate > 440.0 and i < points.size() - 14 and not _is_gap(p) and p.y < CENTER.y + 1.0:
			var d: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[i - 1]).normalized()
			gates.append({"p": _array(p), "dir": [d.x, d.z], "w": 128.0, "name": "TITÃ %02d" % (gates.size() + 1)})
			since_gate = 0.0
	var start := {"p": _array(points[0]), "dir": [1.0, 0.0]}
	gates.append({"p": start.p.duplicate(), "dir": start.dir.duplicate(), "w": 128.0, "name": "CIDADELA TITÃ"})
	var jumps: Array = []
	for j in _jumps():
		var lip: Vector3 = j.origin + j.dir * (j.ramp_start + RAMP_LENGTH) + Vector3.UP * RAMP_RISE
		var landing: Vector3 = j.origin + j.dir * (j.ramp_start + RAMP_LENGTH + GAP_LENGTH)
		var side := Vector3(j.dir.z, 0, -j.dir.x)
		jumps.append({"ramp_start": _array(j.origin + j.dir * j.ramp_start), "takeoff": _array(lip), "landing": _array(landing), "gap_center": _array((lip + landing) * 0.5), "dir": [j.dir.x, j.dir.z], "gap_length": GAP_LENGTH, "ramp_degrees": 8.0, "landing_length": 240.0, "bypass": _array(landing + side * 100.0), "bypass_width": 32.0})
	return {"id": "titan", "name": "Cidadela Titã", "type": "circuit", "laps": 2, "length": length, "route": route, "start": start, "gates": gates, "finish": {}, "half_w": HALF_WIDTH, "jumps": jumps, "hairpin_radius": 160.0, "photo_spots": [{"p": [8400, 1150, -300], "look_at": [9500, 650, 1000]}, {"p": [9050, 465, 360], "look_at": [9600, 480, 360]}, {"p": [9950, 570, 1460], "look_at": [9500, 880, 1160]}]}

func setup(_terrain: Node) -> void:
	name = "TitanCircuit"
	_cube = BoxMesh.new()
	_cube.size = Vector3.ONE
	_unit_faces = _cube.get_faces()
	_make_material("deck", Color("344757"), 0.30)
	_make_material("structure", Color("87979e"), 0.55)
	_make_material("dark", Color("17232e"), 0.50)
	_make_material("orange", Color("ed8938"), 0.30)
	_make_material("cyan", Color("63e9ef"), 0.15, true)
	_make_material("white", Color("e2efec"), 0.20)
	var route := _path()
	for i in route.size() - 1:
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		if _is_gap((a + b) * 0.5):
			continue
		_road(a, b, HALF_WIDTH * 2.0, true, i)
	for j in _jumps():
		_bypass(j)
	_architecture()
	_flush()
	var body := StaticBody3D.new()
	body.name = "TitanDeckAndBarriers"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	set_meta("jumps", event_data().jumps)
	set_meta("deck_height", CENTER.y)
	print("Titã: %d segmentos, %d triângulos de colisão, %d lotes visuais" % [route.size() - 1, _faces.size() / 3, _batches.size()])

func _make_material(key: String, color: Color, metallic: float, glow := false) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.58
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.6
	_materials[key] = mat
	_batches[key] = []

func _box(key: String, pos: Vector3, size: Vector3, basis := Basis.IDENTITY, solid := false) -> void:
	var xf := Transform3D(basis * Basis.from_scale(size), pos)
	_batches[key].append(xf)
	if solid:
		for v in _unit_faces:
			_faces.append(xf * v)

func _beam(key: String, a: Vector3, b: Vector3, width: float, height: float, solid := false, overlap := 0.6) -> void:
	var forward := (b - a).normalized()
	var side := Vector3(forward.z, 0, -forward.x).normalized()
	var up := forward.cross(side).normalized()
	var basis := Basis(side, up, forward)
	_box(key, (a + b) * 0.5, Vector3(width, height, a.distance_to(b) + overlap), basis, solid)

func _road(a: Vector3, b: Vector3, width: float, rails: bool, index: int) -> void:
	var f := (b - a).normalized()
	var side := Vector3(f.z, 0, -f.x).normalized()
	var up := f.cross(side).normalized()
	var overlap := 7.0 if absf(f.x) > 0.001 and absf(f.z) > 0.001 and absf(f.y) < 0.001 else 0.6
	_beam("deck", a - up * 5.0, b - up * 5.0, width, 10.0, true, overlap)
	for sign_value in [-1.0, 1.0]:
		var edge: Vector3 = side * sign_value * (width * 0.5 - 1.0)
		_beam("cyan", a + edge + up * 0.18, b + edge + up * 0.18, 1.4, 0.25)
		if rails and not (sign_value > 0.0 and _bypass_open((a + b) * 0.5)):
			_beam("orange" if index % 6 == 0 else "structure", a + edge + up * 2.3, b + edge + up * 2.3, 2.4, 4.6, true, overlap)
			_beam("dark", a + edge - up * 12.0, b + edge - up * 12.0, 6.0, 12.0)
	if index % 3 == 0:
		_beam("white", a + up * 0.18, a.lerp(b, 0.45) + up * 0.18, 0.9, 0.22)

func _bypass(j: Dictionary) -> void:
	var forward: Vector3 = j.dir
	var side := Vector3(forward.z, 0, -forward.x)
	var origin: Vector3 = j.origin
	var start: float = j.ramp_start
	var points: Array = []
	# Curva suave de 600 m: desvio de emergência mais lento e totalmente contínuo.
	for i in 31:
		var t := float(i) / 30.0
		var lateral := 100.0 * sin(PI * t)
		points.append(origin + forward * (start - 140.0 + t * 600.0) + side * lateral)
	for i in points.size() - 1:
		_road(points[i], points[i + 1], 32.0, false, i)
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		# Só o bordo exterior: entradas e saídas não ficam bloqueadas por barreiras.
		if i > 4 and i < 25:
			_beam("orange", a + side * 15.0 + Vector3.UP * 2.3, b + side * 15.0 + Vector3.UP * 2.3, 2.4, 4.6, true)
	var lip: Vector3 = origin + forward * (start + RAMP_LENGTH) + Vector3.UP * RAMP_RISE
	_beam("orange", lip - side * 40.0 + Vector3.UP * 0.3, lip + side * 40.0 + Vector3.UP * 0.3, 2.0, 0.4)
	for sg in [-1.0, 1.0]:
		_box("orange", origin + forward * (start - 65.0) + side * sg * 54.0 + Vector3.UP * 16.0, Vector3(8, 32, 8))
		_box("cyan", origin + forward * (start - 65.0) + side * sg * 54.0 + Vector3.UP * 33.0, Vector3(11, 3, 11))

func _architecture() -> void:
	# Arco orbital vertical de 740 m: a passagem inferior deixa 110 m livres.
	var ring_center := CENTER + Vector3(0, 480, 160)
	for i in 96:
		var a := TAU * float(i) / 96.0
		var b := TAU * float(i + 1) / 96.0
		var p := ring_center + Vector3(cos(a) * 370.0, sin(a) * 370.0, 0)
		var q := ring_center + Vector3(cos(b) * 370.0, sin(b) * 370.0, 0)
		# Radial/tangent basis also handles the vertical sections without singularities.
		var tangent := (q - p).normalized()
		var radial := Vector3(tangent.y, -tangent.x, 0)
		_box("structure", (p + q) * 0.5, Vector3(26, 38, p.distance_to(q) + 1.0), Basis(radial, Vector3.FORWARD, tangent))
		_box("cyan", (p + q) * 0.5 + Vector3(0, 0, -20), Vector3(5, 2, p.distance_to(q) + 1.0), Basis(radial, Vector3.FORWARD, tangent))
		if i % 8 == 0:
			_box("orange", (p + q) * 0.5, Vector3(37, 48, 11), Basis(radial, Vector3.FORWARD, tangent))
	# Torres segmentadas flutuantes, todas acima do terreno e fora da pista.
	for x in [-860.0, 900.0]:
		for z in [-590.0, -120.0, 390.0, 790.0]:
			var p := CENTER + Vector3(x, 0, z)
			_box("dark", p + Vector3(0, 123, 0), Vector3(38, 286, 38))
			for tier in 7:
				_box("structure", p + Vector3(0, 12 + tier * 42, 0), Vector3(66 - tier * 4, 24, 66 - tier * 4))
				_box("cyan", p + Vector3(0, 25 + tier * 42, 0), Vector3(69 - tier * 4, 2.4, 69 - tier * 4))
			_box("orange", p + Vector3(0, 291, 0), Vector3(52, 18, 52))
	# Pórticos industriais com travessas, vigas diagonais e lajes suspensas.
	for x in [-300.0, 160.0, 600.0]:
		var a := CENTER + Vector3(x, 110, -735)
		var b := CENTER + Vector3(x, 110, 735)
		_beam("structure", a, b, 22, 24)
		_beam("orange", a + Vector3.UP * 20, b + Vector3.UP * 20, 8, 6)
		for z in [-735.0, 735.0]:
			_box("structure", CENTER + Vector3(x, 50, z), Vector3(22, 120, 30))
		for z in [-420.0, -80.0, 300.0]:
			_box("dark", CENTER + Vector3(x, 91, z), Vector3(110, 16, 130))
			_box("cyan", CENTER + Vector3(x, 81, z), Vector3(112, 2, 6))
	# Volumes de base rendent les ouvrages massifs sans piliers jusqu'au sol.
	for z in [-640.0, 640.0]:
		for x in [-250.0, 180.0, 560.0]:
			_box("structure", CENTER + Vector3(x, -20, z), Vector3(135, 26, 72))
			_box("orange", CENTER + Vector3(x, -34, z), Vector3(78, 7, 58))

func _flush() -> void:
	for key in _batches:
		var transforms: Array = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _cube
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mesh := MultiMeshInstance3D.new()
		mesh.name = "Titan_" + key
		mesh.multimesh = mm
		mesh.material_override = _materials[key]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key == "cyan" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mesh)
