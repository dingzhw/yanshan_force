extends RefCounted
## Static world geometry: layer 1 blocks both the capsule and the shot ray.

static func shape_body(parent: Node3D, shape: Shape3D, at: Vector3) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	body.position = at
	var collider = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body

static func mesh_collision(pivot: Node3D, profile: String):
	var vertices = PackedVector3Array()
	for mesh in pivot.find_children("*", "MeshInstance3D", true, false):
		var xf = pivot.global_transform.affine_inverse() * mesh.global_transform
		if profile == "tree":
			for surface in mesh.mesh.get_surface_count():
				var material = mesh.mesh.surface_get_material(surface)
				if material == null or not "wood" in material.resource_name.to_lower():
					continue
				var arrays = mesh.mesh.surface_get_arrays(surface)
				var points = arrays[Mesh.ARRAY_VERTEX]
				var indices = arrays[Mesh.ARRAY_INDEX]
				for index in indices:
					vertices.append(xf * points[index])
		else:
			for vertex in mesh.mesh.get_faces():
				vertices.append(xf * vertex)
	if vertices.is_empty():
		return
	var bounds = AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	if profile == "tree":
		# Sample the visible lower trunk, avoiding the canopy's wide silhouette.
		var trunk_top = bounds.size.y * 0.30
		var radius = 0.08
		for vertex in vertices:
			if vertex.y < trunk_top:
				radius = maxf(radius, Vector2(vertex.x, vertex.z).length())
		var cylinder = CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = bounds.size.y
		shape_body(pivot, cylinder, Vector3(0, cylinder.height/2, 0))
	elif profile == "convex":
		var hull = ConvexPolygonShape3D.new()
		hull.points = vertices
		shape_body(pivot, hull, Vector3.ZERO)
	else:
		var trimesh = ConcavePolygonShape3D.new()
		trimesh.set_faces(vertices)
		trimesh.backface_collision = true
		shape_body(pivot, trimesh, Vector3.ZERO)
	pivot.set_meta("physics_profile", profile)
	pivot.add_to_group("solid_props")

static func set_enabled(node: Node3D, enabled: bool):
	node.visible = enabled
	for body in node.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 1 if enabled else 0

