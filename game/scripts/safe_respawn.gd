extends RefCounted
## Valida uma superfície larga e o espaço ocupado pela nave antes de recuperar.
static func candidate(space: PhysicsDirectSpaceState3D, floor_pos: Vector3, direction: Vector2, exclude: Array[RID]) -> Dictionary:
	var dir := direction.normalized()
	if dir.length_squared() < 0.5:
		return {}
	var forward := Vector3(dir.x, 0, dir.y)
	var right := Vector3(-dir.y, 0, dir.x)
	var center := Vector3.ZERO
	var normal := Vector3.UP
	for offset: Vector3 in [Vector3.ZERO, forward * 5.5, -forward * 5.5, right * 3.2, -right * 3.2]:
		var p := floor_pos + offset
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 4.0, 3, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < 0.92:
			return {}
		if offset == Vector3.ZERO:
			center = hit.position
			normal = hit.normal
		elif absf((hit.position - center).dot(normal)) > 0.65:
			return {} # borda, degrau, buraco ou dois andares diferentes
	var hull := BoxShape3D.new()
	hull.size = Vector3(5.8, 1.6, 10.8)
	var volume := PhysicsShapeQueryParameters3D.new()
	volume.shape = hull
	volume.collision_mask = 1
	volume.exclude = exclude
	volume.margin = 0.1
	volume.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), center + Vector3.UP * 3.3)
	if not space.intersect_shape(volume, 1).is_empty():
		return {}
	return {"position": center, "direction": dir}
