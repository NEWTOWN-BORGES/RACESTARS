extends RefCounted
const VEHICLE := preload("res://materials/metal/vehicle.tres")

static func apply_vehicle(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var original = node.mesh.surface_get_material(i)
			if original is StandardMaterial3D and not original.emission_enabled:
				node.set_surface_override_material(i, VEHICLE)
	for child in node.get_children():
		apply_vehicle(child)
