extends Node3D
## Desgaste perto dos monumentos, numa malha única sem colisão nem texturas externas.
func setup(map: Node3D) -> void:
	var sites: Array = []
	for child in map.get_children():
		if child.has_meta("landmarks"):
			sites = child.get_meta("landmarks")
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 72409
	for site in sites:
		for patch in 5:
			var center: Vector3 = site.position + Vector3(rng.randf_range(-65, 65), 0, rng.randf_range(-65, 65))
			var ground: float = map.terrain.height_at(center.x, center.z)
			if ground < 1.5 or map.in_cave(Vector3(center.x, ground + 1.0, center.z)):
				continue
			var radius := rng.randf_range(4.0, 9.0)
			var first := vertices.size()
			for z in 5:
				for x in 5:
					var uv := Vector2(x, z) / 4.0
					var p := center + Vector3((uv.x - 0.5) * radius * 2, 0, (uv.y - 0.5) * radius * 2)
					p.y = map.terrain.height_at(p.x, p.z) + 0.08
					vertices.append(p)
					uvs.append(uv)
			for z in 4:
				for x in 4:
					var a := first + z * 5 + x
					indices.append_array(PackedInt32Array([a, a+1, a+5, a+1, a+6, a+5]))
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "GroundMarks"
	instance.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/surface_wear.gdshader")
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
