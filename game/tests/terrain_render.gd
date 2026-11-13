extends SceneTree
## Real GPU regression: geometry must render from the playable side of the floor.
var game
var checks = 0
var failures = 0
var ground: MeshInstance3D

func _initialize(): call_deferred("run")

func verify(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)

func rendered():
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	ground = game.landscape.get_node("ContinuousGround")
	assert(ground != null)
	var arrays = ground.mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var front_up = true
	var normals_up = true
	for i in range(0,vertices.size(),3):
		if (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).y>=0: front_up = false
		if normals[i].y<=0: normals_up = false
	verify(front_up,"all floor triangles face the player side")
	verify(normals_up,"terrain lighting normals face upward")
	var viewport = SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01,0.02,0.03)
	world.environment = environment
	viewport.add_child(world)
	var mesh = MeshInstance3D.new()
	mesh.mesh = ground.mesh
	var geometry_material=StandardMaterial3D.new()
	geometry_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override=geometry_material
	viewport.add_child(mesh)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	viewport.add_child(camera)
	for at in [Vector3(0,0,4.5),Vector3(-25,0,-8),Vector3(23,0,-24),game.exit_position,Vector3(25,0,25),Vector3(-42,0,-36)]:
		var surface = game.Layout.on_ground(at)
		camera.position = surface+Vector3(0,12,0)
		camera.look_at(surface,Vector3.FORWARD)
		await rendered()
		var pixels = viewport.get_texture().get_image()
		var filled = 0
		for y in range(24,233,26):
			for x in range(24,233,26):
				var color = pixels.get_pixel(x,y)
				if color.g>0.15 and color.r>0.15: filled += 1
		print("FLOOR_COVERAGE ",at," ",filled,"/81")
		verify(filled==81,"GPU draws a continuous floor at "+str(at))
	viewport.queue_free()
	game.start_action()
	game.player.active = false
	game.ui.hide()
	game.player.weapon_root.hide()
	for index in 3:
		game.player.position = game.stations[index].position+Vector3(0,0.1,1)
		game.player.pitch = -1.1
		game.player.yaw = 0
		ground.show()
		await physics_frame
		await rendered()
		var visible = game.get_viewport().get_texture().get_image()
		game._capture("floor-%d.png" % index)
		ground.hide()
		await rendered()
		var hidden = game.get_viewport().get_texture().get_image()
		var changed = 0
		for y in range(400,641,30):
			for x in range(340,941,75):
				var a = visible.get_pixel(x,y)
				var b = hidden.get_pixel(x,y)
				if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>0.03: changed += 1
		print("FIRST_PERSON_FLOOR ",index," ",changed,"/81")
		verify(changed>=73,"actual first-person floor is visible in zone "+str(index))
	ground.show()
	game.queue_free()
	await process_frame
	await create_timer(0.4).timeout
	print("TERRAIN_RENDER_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
