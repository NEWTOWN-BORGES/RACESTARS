extends Node3D
## Mundo infinito, para frente e para os dois lados, montado com as peças modeladas
## no Blender (assets/models/*.glb). Duas camadas:
##   * pedaços pequenos (80 m): obstáculos do dia a dia, avenidas de arcos, decoração;
##   * marcos (320 m): arcos de pedra gigantes, anéis, lâminas e formações enormes,
##     que dão a sensação de mapa vasto e aparecem bem de longe.
## A cada PERIOD metros há uma cordilheira infinita para os lados, furada por túneis
## a cada RIDGE_W metros: lá dentro não dá para ir para os lados.

const CHUNK := 80.0
const LAT_CHUNKS := 4
const AHEAD_CHUNKS := 8
const BEHIND_CHUNKS := 1
const BUILD_PER_FRAME := 2

const LM_CHUNK := 320.0
const LM_LAT := 2
const LM_AHEAD := 3

const PERIOD := 1500.0
const RIDGE_AT := 1240.0
const RIDGE_W := 60.0
const RIDGE_L := 180.0
const START_CLEAR := 160.0

# col: tipo de colisão. "cyl" = cilindro só no tronco/base. r = raio para não sobrepor peças.
const PROPS := {
	"rock_spire_a": {"col": "convex", "r": 7.0},
	"rock_spire_b": {"col": "convex", "r": 5.5},
	"rock_spire_c": {"col": "convex", "r": 8.5},
	"mesa": {"col": "trimesh", "r": 26.0},
	"arch": {"col": "trimesh", "r": 15.0},
	"arch_giant": {"col": "trimesh", "r": 42.0},
	"arch_twin": {"col": "trimesh", "r": 28.0},
	"rock_ring": {"col": "trimesh", "r": 19.0},
	"rock_fin": {"col": "convex", "r": 17.0},
	"butte": {"col": "convex", "r": 62.0},
	"boulder_a": {"col": "convex", "r": 4.0},
	"boulder_b": {"col": "convex", "r": 5.5},
	"pillar": {"col": "convex", "r": 2.6},
	"gate": {"col": "trimesh", "r": 10.0},
	"crystals_cyan": {"col": "cyl", "r": 4.0, "cr": 2.4, "h": 8.0},
	"crystals_mag": {"col": "cyl", "r": 4.0, "cr": 2.4, "h": 8.0},
	"tree_acacia": {"col": "cyl", "r": 4.0, "cr": 0.7, "h": 9.0},
	"tree_acacia_b": {"col": "cyl", "r": 3.5, "cr": 0.6, "h": 7.0},
	"tree_mushroom": {"col": "cyl", "r": 6.0, "cr": 1.2, "h": 13.0},
	"tower_pod": {"col": "convex", "r": 4.5},
	"float_island": {"col": "none", "r": 0.0},
	"grass_tuft": {"col": "none", "r": 0.0},
	"pebbles": {"col": "none", "r": 0.0},
	"ridge_tunnel": {"col": "trimesh", "r": 0.0},
}

# Obstáculos comuns por bioma: 0 = savana de arenito, 1 = vale dos cristais
const BIOMES := [
	{"rock_spire_a": 3.0, "rock_spire_b": 3.0, "rock_spire_c": 1.6, "arch": 2.2, "boulder_a": 2.0,
	 "boulder_b": 1.4, "tree_acacia": 3.0, "tree_acacia_b": 2.0, "tower_pod": 1.2, "pillar": 0.8},
	{"crystals_cyan": 3.0, "crystals_mag": 3.0, "tree_mushroom": 3.0, "gate": 1.4, "pillar": 2.0,
	 "boulder_a": 2.0, "boulder_b": 1.4, "rock_spire_b": 1.5, "arch": 1.4, "tower_pod": 0.8},
]
# Marcos gigantes
const LANDMARKS := {"arch_giant": 3.0, "arch_twin": 2.4, "rock_ring": 2.4, "butte": 1.6, "rock_fin": 2.0, "mesa": 1.2}

var seed_value := 1
var player: Node3D
var props := {}
var chunks := {}
var landmarks := {}
var lm_plans := {}
var ridges := {}
var queue: Array[Vector2i] = []
var ground: MeshInstance3D

func _ready() -> void:
	_load_props()
	_make_ground()

# ------------------------------------------------------------------ peças
func _load_props() -> void:
	for name in PROPS:
		var scene: PackedScene = load("res://assets/models/%s.glb" % name)
		var inst := scene.instantiate()
		var mesh: Mesh = _find_mesh(inst).mesh
		_stylize(mesh, name)
		var d: Dictionary = PROPS[name]
		var shape: Shape3D = null
		match d.col:
			"convex": shape = mesh.create_convex_shape(true, true)
			"trimesh": shape = mesh.create_trimesh_shape()
			"cyl":
				var c := CylinderShape3D.new()
				c.radius = d.cr
				c.height = d.h
				shape = c
		props[name] = {"mesh": mesh, "shape": shape, "col": d.col, "r": d.r, "h": d.get("h", 0.0)}
		inst.free()

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null

func _stylize(mesh: Mesh, name: String) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			sm.vertex_color_use_as_albedo = true
			sm.roughness = 1.0
			sm.metallic = 0.0
			sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			sm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			if name == "grass_tuft":
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED

func _make_ground() -> void:
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	ground.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	mat.set_shader_parameter("period", PERIOD)
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

# ------------------------------------------------------------------ zonas
func biome_at(d: float) -> int:
	return int(floor(d / PERIOD)) % 2

func is_clear_zone(d: float) -> bool:
	if d < START_CLEAR:
		return true
	var l := fposmod(d, PERIOD)
	return l > RIDGE_AT - 90.0 and l < RIDGE_AT + RIDGE_L + 40.0

func near_ridge(d: float, margin: float) -> bool:
	var l := fposmod(d, PERIOD)
	return l > RIDGE_AT - margin and l < RIDGE_AT + RIDGE_L + margin

## Distância até a boca dos próximos túneis (ou -1 se já passou).
func ridge_ahead(pos: Vector3) -> float:
	var l := fposmod(-pos.z, PERIOD)
	if l < RIDGE_AT:
		return RIDGE_AT - l
	return -1.0

func nearest_tunnel_x(x: float) -> float:
	return round(x / RIDGE_W) * RIDGE_W

func in_tunnel(pos: Vector3) -> bool:
	var l := fposmod(-pos.z, PERIOD)
	return l >= RIDGE_AT and l <= RIDGE_AT + RIDGE_L

# ------------------------------------------------------------------ atualização
func prewarm() -> void:
	_update(true)

func _process(_dt: float) -> void:
	_update(false)

func _update(all_now: bool) -> void:
	if player == null:
		return
	var p := player.global_position
	ground.global_position = Vector3(snappedf(p.x, 4.0), 0.0, snappedf(p.z, 4.0))
	_update_landmarks(p)
	var pcx := floori(p.x / CHUNK)
	var pcz := floori(p.z / CHUNK)
	var wanted := {}
	for dz in range(-AHEAD_CHUNKS, BEHIND_CHUNKS + 1):
		var lat := LAT_CHUNKS if dz > -5 else LAT_CHUNKS + 1   # mais largo lá na frente (o cone de visão abre)
		for dx in range(-lat, lat + 1):
			var k := Vector2i(pcx + dx, pcz + dz)
			wanted[k] = true
			if not chunks.has(k) and not queue.has(k):
				queue.append(k)
	for k in chunks.keys():
		if not wanted.has(k):
			chunks[k].queue_free()
			chunks.erase(k)
	queue = queue.filter(func(k): return wanted.has(k))
	queue.sort_custom(func(a, b): return _cd(a, pcx, pcz) < _cd(b, pcx, pcz))
	var budget := 100000 if all_now else BUILD_PER_FRAME
	while budget > 0 and not queue.is_empty():
		var k: Vector2i = queue.pop_front()
		chunks[k] = _build_chunk(k)
		budget -= 1
	_update_ridges(p)

func _cd(k: Vector2i, cx: int, cz: int) -> float:
	return absf(k.x - cx) * 1.5 + absf(k.y - cz)

# ------------------------------------------------------------------ marcos gigantes
func _lm_plan(key: Vector2i) -> Array:
	## Lista determinística de marcos de um pedaço grande: [[nome, Vector2 pos, yaw, escala], ...]
	if lm_plans.has(key):
		return lm_plans[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, key.x, key.y, 99])
	var plan: Array = []
	var n := rng.randi_range(2, 4)
	for i in n:
		var pos := Vector2((key.x + rng.randf()) * LM_CHUNK, (key.y + rng.randf()) * LM_CHUNK)
		var d := -pos.y
		var name := _pick(rng, LANDMARKS)
		var s := rng.randf_range(0.85, 1.3)
		if d < 320.0 or near_ridge(d, 120.0):
			continue
		var ok := true
		for q in plan:
			if pos.distance_to(q[1]) < (PROPS[name].r * s + PROPS[q[0]].r * q[3]) + 20.0:
				ok = false
		if not ok:
			continue
		var yaw := rng.randf() * TAU
		if name.begins_with("arch") or name == "rock_ring":
			yaw = rng.randf_range(-0.25, 0.25)   # de frente para a corrida: passa-se por dentro
		plan.append([name, pos, yaw, s])
	lm_plans[key] = plan
	return plan

func _update_landmarks(p: Vector3) -> void:
	var cx := floori(p.x / LM_CHUNK)
	var cz := floori(p.z / LM_CHUNK)
	var wanted := {}
	for dz in range(-LM_AHEAD, 1):
		for dx in range(-LM_LAT, LM_LAT + 1):
			var k := Vector2i(cx + dx, cz + dz)
			wanted[k] = true
			if not landmarks.has(k):
				var node := Node3D.new()
				add_child(node)
				var body := StaticBody3D.new()
				node.add_child(body)
				var groups := {}
				for e in _lm_plan(k):
					var pos := Vector3(e[1].x, 0.0, e[1].y)
					_add_body(body, e[0], pos, e[2], e[3])
					groups.get_or_add(e[0], []).append(_xf(pos, e[2], e[3]))
				_add_multimeshes(node, groups, true)
				landmarks[k] = node
	for k in landmarks.keys():
		if not wanted.has(k):
			landmarks[k].queue_free()
			landmarks.erase(k)
	for k in lm_plans.keys():
		if absi(k.x - cx) > LM_LAT + 2 or k.y - cz > 2:
			lm_plans.erase(k)

func _landmarks_near(x0: float, z0: float) -> Array:
	var out: Array = []
	var cx := floori((x0 + CHUNK * 0.5) / LM_CHUNK)
	var cz := floori((z0 + CHUNK * 0.5) / LM_CHUNK)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for e in _lm_plan(Vector2i(cx + dx, cz + dz)):
				out.append([e[1], PROPS[e[0]].r * e[3]])
	return out

# ------------------------------------------------------------------ pedaços do mapa
func _xf(pos: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)

func _add_body(body: StaticBody3D, name: String, pos: Vector3, yaw: float, s: float) -> void:
	var P: Dictionary = props[name]
	if P.shape == null:
		return
	var cs := CollisionShape3D.new()
	cs.shape = P.shape
	var t := _xf(pos, yaw, s)
	if P.col == "cyl":
		t = t * Transform3D(Basis(), Vector3(0.0, P.h * 0.5, 0.0))
	cs.transform = t
	body.add_child(cs)

func _add_multimeshes(node: Node3D, groups: Dictionary, shadows: bool, vis_end := 0.0) -> void:
	## Um MultiMesh por tipo de peça: poucas chamadas de desenho (importante no celular).
	for name in groups:
		var xs: Array = groups[name]
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = props[name].mesh
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
		node.add_child(mmi)

func _build_chunk(k: Vector2i) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, k.x, k.y])
	var x0 := k.x * CHUNK
	var z0 := k.y * CHUNK
	var body := StaticBody3D.new()
	node.add_child(body)
	var groups := {}
	var placed: Array = _landmarks_near(x0, z0)
	var d_mid := -(z0 + CHUNK * 0.5)
	var difficulty := clampf(d_mid / 6000.0, 0.0, 1.0)

	# avenida de arcos: vários arcos em fila, para atravessar um atrás do outro
	if not is_clear_zone(d_mid) and not near_ridge(d_mid, 140.0) and rng.randf() < 0.12:
		var ax := x0 + rng.randf_range(15.0, CHUNK - 15.0)
		var ok := true
		for q in placed:
			if Vector2(ax, z0 + CHUNK * 0.5).distance_to(q[0]) < q[1] + 45.0:
				ok = false
		if ok:
			for i in 4:
				var pos := Vector2(ax, z0 + 6.0 + i * 22.0)
				_place(body, groups, "arch", Vector3(pos.x, 0.0, pos.y), rng.randf_range(-0.05, 0.05), 1.05)
				placed.append([pos, 15.0])

	var count := int(lerpf(4.0, 12.0, difficulty)) + rng.randi_range(-1, 2)
	for i in count:
		var pos := Vector2(x0 + rng.randf() * CHUNK, z0 + rng.randf() * CHUNK)
		var d := -pos.y
		var name := _pick(rng, BIOMES[biome_at(d)])
		var s := rng.randf_range(0.8, 1.25)
		var yaw := rng.randf() * TAU
		if is_clear_zone(d):
			continue
		var r: float = props[name].r * s
		var ok := true
		for q in placed:
			if pos.distance_to(q[0]) < r + q[1] + 6.0:
				ok = false
				break
		if not ok:
			continue
		placed.append([pos, r])
		if name == "arch" or name == "gate":
			yaw = rng.randf_range(-0.3, 0.3)
		_place(body, groups, name, Vector3(pos.x, 0.0, pos.y), yaw, s)
	_add_multimeshes(node, groups, true)
	_decorate(node, rng, x0, z0)
	if rng.randf() < 0.08:
		var fi := MeshInstance3D.new()
		fi.mesh = props["float_island"].mesh
		var s2 := rng.randf_range(0.7, 1.6)
		fi.transform = _xf(Vector3(x0 + rng.randf() * CHUNK, rng.randf_range(95.0, 170.0), z0 + rng.randf() * CHUNK), rng.randf() * TAU, s2)
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(fi)
	return node

func _place(body: StaticBody3D, groups: Dictionary, name: String, pos: Vector3, yaw: float, s: float) -> void:
	_add_body(body, name, pos, yaw, s)
	groups.get_or_add(name, []).append(_xf(pos, yaw, s))

func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var r := rng.randf() * total
	for key in weights:
		r -= weights[key]
		if r <= 0.0:
			return key
	return weights.keys()[0]

func _decorate(node: Node3D, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	var groups := {"grass_tuft": [], "pebbles": []}
	for spec in [["grass_tuft", 150, 0.8, 1.8], ["pebbles", 24, 0.6, 1.4]]:
		for i in spec[1]:
			var x := x0 + rng.randf() * CHUNK
			var z := z0 + rng.randf() * CHUNK
			var t := _xf(Vector3(x, 0.0, z), rng.randf() * TAU, rng.randf_range(spec[2], spec[3]))
			if near_ridge(-z, 2.0):
				continue
			groups[spec[0]].append(t)
	_add_multimeshes(node, groups, false, 170.0)

# ------------------------------------------------------------------ cordilheiras com túneis
func _update_ridges(p: Vector3) -> void:
	var d := -p.z
	var k0 := int(floor(d / PERIOD))
	for k: int in [k0, k0 + 1]:
		var front: float = k * PERIOD + RIDGE_AT
		var ahead: float = front - d
		if ahead > 900.0 or ahead < -(RIDGE_L + 200.0):
			continue
		var ic := int(round(p.x / RIDGE_W))
		var span := 12 if ahead > 0.0 else 2
		for i in range(ic - span, ic + span + 1):
			var key := Vector2i(k, i)
			if not ridges.has(key):
				ridges[key] = _build_ridge(key, i * RIDGE_W, -front)
	for key in ridges.keys():
		var front2: float = key.x * PERIOD + RIDGE_AT
		if d - front2 > RIDGE_L + 250.0 or absf(key.y * RIDGE_W - p.x) > RIDGE_W * 16.0:
			ridges[key].queue_free()
			ridges.erase(key)

func _build_ridge(key: Vector2i, x: float, z_front: float) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(x, 0.0, z_front)
	add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = props["ridge_tunnel"].mesh
	node.add_child(mi)
	var body := StaticBody3D.new()
	node.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = props["ridge_tunnel"].shape
	body.add_child(cs)
	# cristais dentro do túnel, alternando de lado: obrigam a desviar lá dentro
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, key.x, key.y, 7])
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var zz := 40.0
	var groups := {}
	while zz < RIDGE_L - 30.0:
		_place(body, groups, "crystals_cyan" if side > 0.0 else "crystals_mag", Vector3(side * 1.8, 0.12, -zz), rng.randf() * TAU, 0.45)
		side = -side
		zz += rng.randf_range(50.0, 70.0)
	_add_multimeshes(node, groups, false)
	return node
