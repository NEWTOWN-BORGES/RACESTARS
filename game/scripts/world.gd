extends Node3D
## Mundo infinito: gera pedaços (chunks) de 80x80 m ao redor do jogador, para frente
## e para os dois lados, com as peças modeladas no Blender (assets/models/*.glb).
## A cada PERIOD metros aparece uma cordilheira infinita para os lados, furada por
## túneis a cada RIDGE_W metros: lá dentro não dá para ir para os lados.

const CHUNK := 80.0
const LAT_CHUNKS := 4          # pedaços carregados para cada lado
const AHEAD_CHUNKS := 7        # pedaços carregados à frente
const BEHIND_CHUNKS := 1
const BUILD_PER_FRAME := 2

const PERIOD := 1500.0         # a cada 1500 m vem uma cordilheira
const RIDGE_AT := 1240.0       # onde fica a boca dos túneis dentro do período
const RIDGE_W := 60.0          # largura de cada módulo de cordilheira (um túnel por módulo)
const RIDGE_L := 180.0         # comprimento do túnel
const START_CLEAR := 160.0     # largada sem obstáculos

# Tipo de colisão de cada peça. "cyl" = cilindro só no tronco (dá para passar sob a copa).
const PROPS := {
	"rock_spire_a": {"col": "convex", "r": 7.0},
	"rock_spire_b": {"col": "convex", "r": 5.5},
	"rock_spire_c": {"col": "convex", "r": 8.5},
	"mesa": {"col": "trimesh", "r": 26.0},
	"arch": {"col": "trimesh", "r": 15.0},
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

# Pesos de sorteio por bioma: 0 = savana de arenito, 1 = vale dos cristais
const BIOMES := [
	{"rock_spire_a": 3.0, "rock_spire_b": 3.0, "rock_spire_c": 2.0, "mesa": 0.5, "arch": 0.9,
	 "boulder_a": 2.0, "boulder_b": 1.5, "tree_acacia": 3.0, "tree_acacia_b": 2.0, "tower_pod": 1.4, "pillar": 0.8},
	{"crystals_cyan": 3.0, "crystals_mag": 3.0, "tree_mushroom": 3.0, "gate": 1.0, "pillar": 2.0,
	 "boulder_a": 2.0, "boulder_b": 1.5, "rock_spire_b": 1.5, "tower_pod": 0.8, "arch": 0.6},
]

var seed_value := 1
var player: Node3D
var props := {}
var chunks := {}
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
		var mi := _find_mesh(inst)
		var mesh: Mesh = mi.mesh
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
			sm.roughness = 1.0
			sm.metallic = 0.0
			sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			sm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			if name == "grass_tuft":
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED

func _make_ground() -> void:
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
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

## Distância até a boca dos próximos túneis (ou -1 se estiver longe).
func ridge_ahead(pos: Vector3) -> float:
	var d := -pos.z
	var l := fposmod(d, PERIOD)
	if l < RIDGE_AT:
		return RIDGE_AT - l
	return -1.0

## Centro X do túnel mais próximo (para o piloto automático).
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
	var pcx := floori(p.x / CHUNK)
	var pcz := floori(p.z / CHUNK)
	var wanted := {}
	for dz in range(-AHEAD_CHUNKS, BEHIND_CHUNKS + 1):
		for dx in range(-LAT_CHUNKS, LAT_CHUNKS + 1):
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

# ------------------------------------------------------------------ pedaços do mapa
func _build_chunk(k: Vector2i) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, k.x, k.y])
	var x0 := k.x * CHUNK
	var z0 := k.y * CHUNK
	var body := StaticBody3D.new()
	node.add_child(body)
	var d_mid := -(z0 + CHUNK * 0.5)
	var difficulty := clampf(d_mid / 5000.0, 0.0, 1.0)
	var count := int(lerpf(6.0, 14.0, difficulty)) + rng.randi_range(-1, 2)
	var placed: Array = []
	for i in count:
		var pos := Vector2(x0 + rng.randf() * CHUNK, z0 + rng.randf() * CHUNK)
		var d := -pos.y
		if is_clear_zone(d):
			continue
		var name := _pick(rng, BIOMES[biome_at(d)])
		var s := rng.randf_range(0.8, 1.25)
		var r: float = props[name].r * s
		var ok := true
		for q in placed:
			if pos.distance_to(q[0]) < r + q[1] + 6.0:
				ok = false
				break
		if not ok:
			continue
		placed.append([pos, r])
		var yaw := rng.randf() * TAU
		if name == "arch" or name == "gate":
			yaw = rng.randf_range(-0.3, 0.3)
		_add_prop(node, body, name, Vector3(pos.x, 0.0, pos.y), yaw, s)
	_decorate(node, rng, x0, z0)
	if rng.randf() < 0.08:
		var fi := MeshInstance3D.new()
		fi.mesh = props["float_island"].mesh
		var s2 := rng.randf_range(0.6, 1.5)
		fi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s2),
			Vector3(x0 + rng.randf() * CHUNK, rng.randf_range(95.0, 170.0), z0 + rng.randf() * CHUNK))
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(fi)
	return node

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

func _add_prop(node: Node3D, body: StaticBody3D, name: String, pos: Vector3, yaw: float, s: float) -> void:
	var P: Dictionary = props[name]
	var mi := MeshInstance3D.new()
	mi.mesh = P.mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)
	node.add_child(mi)
	if P.shape:
		var cs := CollisionShape3D.new()
		cs.shape = P.shape
		var t := mi.transform
		if P.col == "cyl":
			t = t * Transform3D(Basis(), Vector3(0.0, P.h * 0.5, 0.0))
		cs.transform = t
		body.add_child(cs)

func _decorate(node: Node3D, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	for spec in [["grass_tuft", 160, 0.8, 1.8], ["pebbles", 26, 0.6, 1.4]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = props[spec[0]].mesh
		var xs: Array[Transform3D] = []
		for i in spec[1]:
			var x := x0 + rng.randf() * CHUNK
			var z := z0 + rng.randf() * CHUNK
			var l := fposmod(-z, PERIOD)
			if l > RIDGE_AT - 2.0 and l < RIDGE_AT + RIDGE_L + 2.0:
				continue
			var s := rng.randf_range(spec[2], spec[3])
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0.0, z)))
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)

# ------------------------------------------------------------------ cordilheiras com túneis
func _update_ridges(p: Vector3) -> void:
	var d := -p.z
	var k0 := int(floor(d / PERIOD))
	for k: int in [k0, k0 + 1]:
		var front: float = k * PERIOD + RIDGE_AT
		var ahead: float = front - d
		if ahead > 650.0 or ahead < -(RIDGE_L + 200.0):
			continue
		var ic := int(round(p.x / RIDGE_W))
		var span := 10 if ahead > 0.0 else 2
		for i in range(ic - span, ic + span + 1):
			var key := Vector2i(k, i)
			if not ridges.has(key):
				ridges[key] = _build_ridge(key, i * RIDGE_W, -front)
	for key in ridges.keys():
		var front2: float = key.x * PERIOD + RIDGE_AT
		if d - front2 > RIDGE_L + 250.0 or absf(key.y * RIDGE_W - p.x) > RIDGE_W * 14.0:
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
	while zz < RIDGE_L - 30.0:
		_add_prop(node, body, "crystals_cyan" if side > 0.0 else "crystals_mag", Vector3(side * 1.8, 0.12, -zz), rng.randf() * TAU, 0.45)
		side = -side
		zz += rng.randf_range(50.0, 70.0)
	return node
