extends Node3D
## Terreno do mundo (24 x 24 km, células de 8 m) a partir de assets/map/height.zst.
## Para não engasgar no telemóvel nada é construído durante o jogo: há só 5 grelhas planas
## (uma por nível de detalhe) partilhadas por todos os pedaços de 512 m; a altura de cada
## vértice é lida na placa gráfica de uma textura. Trocar o nível de detalhe é só trocar a grelha.
## Colisão: um único HeightMapShape3D com os mesmos dados.

const LOD_STEPS := [1, 2, 4, 8, 16]
const LOD_DIST := [420.0, 1100.0, 2000.0, 3300.0]
const VIEW_DIST := 4800.0
const SKIRT := 30.0

var res := 1537
var cell := 4.0
var half := 3072.0
var chunk_cells := 128
var heights: PackedFloat32Array        # em células (metros / cell)
var chunks: Array = []                 # [{node, min, lod}]
var lod_meshes: Array[ArrayMesh] = []
var material: ShaderMaterial
var biome_texture: ImageTexture
var focus: Node3D
var _timer := 0.0

func setup(info: Dictionary) -> void:
	res = int(info.res)
	cell = float(info.cell)
	half = float(info.size) * 0.5
	chunk_cells = int(info.chunk_cells)
	# alturas: float16 comprimido com zstd -> textura (placa gráfica) e float32 (colisão)
	var raw := FileAccess.get_file_as_bytes("res://assets/map/height.zst").decompress(res * res * 2, FileAccess.COMPRESSION_ZSTD)
	var himg := Image.create_from_data(res, res, false, Image.FORMAT_RH, raw)
	var htex := ImageTexture.create_from_image(himg)
	himg.convert(Image.FORMAT_RF)
	heights = himg.get_data().to_float32_array()
	var bres := int(info.biome_res)
	var braw := FileAccess.get_file_as_bytes("res://assets/map/biome.zst").decompress(bres * bres * 4, FileAccess.COMPRESSION_ZSTD)
	var bimg := Image.create_from_data(bres, bres, false, Image.FORMAT_RGBA8, braw)
	bimg.generate_mipmaps()
	biome_texture = ImageTexture.create_from_image(bimg)
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/terrain.gdshader")
	material.set_shader_parameter("heightmap", htex)
	material.set_shader_parameter("cell", cell)
	material.set_shader_parameter("half_size", half)
	material.set_shader_parameter("res", res)
	material.set_shader_parameter("skirt", SKIRT)
	material.set_shader_parameter("water_y", float(info.water_y))
	apply_biome(material, info)
	# superfícies de água (até 16): centro/meia-largura e rotação, para escurecer o fundo
	var rects := PackedVector4Array()
	var rots := PackedVector4Array()
	for w in info.waters:
		if rects.size() >= 16:
			break
		rects.append(Vector4(w.c[0], w.c[1], w.sx, w.sz))
		rots.append(Vector4(cos(w.yaw), sin(w.yaw), w.y, 0.0))
	while rects.size() < 16:
		rects.append(Vector4(0, 0, -1, -1))
		rots.append(Vector4(1, 0, 0, 0))
	material.set_shader_parameter("water_rects", rects)
	material.set_shader_parameter("water_rots", rots)
	for s in LOD_STEPS:
		lod_meshes.append(_grid_mesh(s))
	var n := (res - 1) / chunk_cells
	var span := chunk_cells * cell
	for cz in n:
		for cx in n:
			var mm: Array = info.chunks[cz * n + cx]
			var mi := MeshInstance3D.new()
			mi.material_override = material
			mi.position = Vector3(-half + cx * span, 0.0, -half + cz * span)
			mi.custom_aabb = AABB(Vector3(0.0, float(mm[0]) - SKIRT - 2.0, 0.0), Vector3(span, float(mm[1]) - float(mm[0]) + SKIRT + 4.0, span))
			mi.mesh = lod_meshes[LOD_STEPS.size() - 1]
			add_child(mi)
			chunks.append({"node": mi, "min": Vector2(mi.position.x, mi.position.z), "lod": -1})
	_make_collision()

## Liga um material que usa rock_common.gdshaderinc ao mapa de biomas.
func apply_biome(mat: ShaderMaterial, info: Dictionary) -> void:
	mat.set_shader_parameter("biome_tex", biome_texture)
	mat.set_shader_parameter("map_size", float(info.size))

func _grid_mesh(step: int) -> ArrayMesh:
	var n := chunk_cells / step + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			verts.append(Vector3(i * step * cell, 0.0, j * step * cell))
			uvs.append(Vector2(step, 0.0))
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
		verts.append(verts[edge[k]])
		uvs.append(Vector2(step, 1.0))
	for k in edge.size() - 1:
		var a2 := edge[k]
		var b2 := edge[k + 1]
		var c2 := base + k
		var d2 := base + k + 1
		idx.append_array([a2, c2, b2, b2, c2, d2, a2, b2, c2, b2, d2, c2])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _make_collision() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = res
	hm.map_depth = res
	hm.map_data = heights          # já vem em células: com a escala uniforme dá metros
	cs.shape = hm
	cs.scale = Vector3(cell, cell, cell)
	body.add_child(cs)
	body.set_meta("terrain", true)
	# paredes invisíveis um pouco antes das montanhas da borda
	var edge := half - 120.0
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
	return heights[iz * res + ix] * cell

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
	_update_lods()

func _process(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.25
		_update_lods()

func _update_lods() -> void:
	if focus == null:
		return
	var p := focus.global_position
	var span := chunk_cells * cell
	for c in chunks:
		var mn: Vector2 = c.min
		var dx := maxf(0.0, maxf(mn.x - p.x, p.x - (mn.x + span)))
		var dz := maxf(0.0, maxf(mn.y - p.z, p.z - (mn.y + span)))
		var d := sqrt(dx * dx + dz * dz)
		var mi: MeshInstance3D = c.node
		mi.visible = d < VIEW_DIST
		var lod := LOD_DIST.size()
		for i in LOD_DIST.size():
			if d < LOD_DIST[i]:
				lod = i
				break
		if lod != c.lod:
			c.lod = lod
			mi.mesh = lod_meshes[lod]
