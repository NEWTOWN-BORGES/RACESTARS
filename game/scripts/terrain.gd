extends Node3D
## Terreno do mapa (4 x 4 km) a partir de assets/map/height.bin.
## Desenho em pedaços de 256 m com níveis de detalhe (mais perto = mais triângulos),
## colisão com um único HeightMapShape3D (leve para o celular).

const CHUNK_CELLS := 64
const LOD_STEPS := [1, 2, 4, 8]
const LOD_DIST := [420.0, 900.0, 1600.0]
const VIEW_DIST := 2600.0
const SKIRT := 25.0

var res := 1025
var cell := 4.0
var half := 2048.0
var heights: PackedFloat32Array
var chunks_n := 16
var chunk_nodes := {}      # Vector2i -> MeshInstance3D
var chunk_lod := {}        # Vector2i -> lod atual
var mesh_cache := {}       # Vector3i(cx, cz, lod) -> ArrayMesh
var material: ShaderMaterial
var _timer := 0.0
var focus: Node3D

func setup(info: Dictionary) -> void:
	res = int(info.res)
	cell = float(info.cell)
	half = float(info.size) * 0.5
	chunks_n = (res - 1) / CHUNK_CELLS
	heights = FileAccess.get_file_as_bytes("res://assets/map/height.bin").to_float32_array()
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/terrain.gdshader")
	_make_collision()
	for cz in chunks_n:
		for cx in chunks_n:
			var mi := MeshInstance3D.new()
			mi.material_override = material
			mi.position = Vector3(-half + cx * CHUNK_CELLS * cell, 0.0, -half + cz * CHUNK_CELLS * cell)
			add_child(mi)
			chunk_nodes[Vector2i(cx, cz)] = mi
			chunk_lod[Vector2i(cx, cz)] = -1

func _make_collision() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = res
	hm.map_depth = res
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / cell
	hm.map_data = scaled
	cs.shape = hm
	cs.scale = Vector3(cell, cell, cell)
	body.add_child(cs)
	body.set_meta("terrain", true)
	# paredes invisíveis um pouco antes das montanhas da borda
	var edge := half - 90.0
	for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var wall := CollisionShape3D.new()
		var wb := WorldBoundaryShape3D.new()
		wb.plane = Plane(-n, -edge)
		wall.shape = wb
		body.add_child(wall)
	add_child(body)

func h(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, res - 1)
	iz = clampi(iz, 0, res - 1)
	return heights[iz * res + ix]

## Altura do terreno num ponto qualquer (interpolada).
func height_at(x: float, z: float) -> float:
	var fx := (x + half) / cell
	var fz := (z + half) / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var u := fx - ix
	var v := fz - iz
	return lerpf(lerpf(h(ix, iz), h(ix + 1, iz), u), lerpf(h(ix, iz + 1), h(ix + 1, iz + 1), u), v)

func update_now() -> void:
	_update_lods(true)

func _process(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.2
		_update_lods(false)

func _update_lods(all_now: bool) -> void:
	if focus == null:
		return
	var p := focus.global_position
	var built := 0
	var span := CHUNK_CELLS * cell
	for key in chunk_nodes:
		var mi: MeshInstance3D = chunk_nodes[key]
		var center := mi.position + Vector3(span * 0.5, 0.0, span * 0.5)
		var d := Vector2(center.x - p.x, center.z - p.z).length() - span * 0.5
		if d > VIEW_DIST:
			mi.visible = false
			continue
		mi.visible = true
		var lod := 3
		for i in LOD_DIST.size():
			if d < LOD_DIST[i]:
				lod = i
				break
		if lod == chunk_lod[key]:
			continue
		var ck := Vector3i(key.x, key.y, lod)
		if not mesh_cache.has(ck):
			if not all_now and built >= 3:
				continue
			mesh_cache[ck] = _build_chunk(key.x, key.y, LOD_STEPS[lod])
			built += 1
		mi.mesh = mesh_cache[ck]
		chunk_lod[key] = lod

func _build_chunk(cx: int, cz: int, step: int) -> ArrayMesh:
	var n := CHUNK_CELLS / step + 1
	var ox := cx * CHUNK_CELLS
	var oz := cz * CHUNK_CELLS
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var ix := ox + i * step
			var iz := oz + j * step
			var y := h(ix, iz)
			verts[j * n + i] = Vector3(i * step * cell, y, j * step * cell)
			var dx := h(ix + step, iz) - h(ix - step, iz)
			var dz := h(ix, iz + step) - h(ix, iz - step)
			norms[j * n + i] = Vector3(-dx, 2.0 * step * cell, -dz).normalized()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# saia: borda que desce para esconder frestas entre níveis de detalhe
	var edge: Array[int] = []
	for i in n:
		edge.append(i)
	for j in range(1, n):
		edge.append(j * n + n - 1)
	for i in range(n - 2, -1, -1):
		edge.append((n - 1) * n + i)
	for j in range(n - 2, 0, -1):
		edge.append(j * n)
	edge.append(0)
	var base := verts.size()
	for k in edge.size():
		var v := verts[edge[k]]
		verts.append(Vector3(v.x, v.y - SKIRT, v.z))
		norms.append(norms[edge[k]])
	for k in edge.size() - 1:
		var a2 := edge[k]
		var b2 := edge[k + 1]
		var c2 := base + k
		var d2 := base + k + 1
		idx.append_array([a2, c2, b2, b2, c2, d2, a2, b2, c2, b2, d2, c2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
