extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	game.player.set_physics_process(false)
	game.player.active = false
	game.player.position = Vector3(0,2,4.5)
	await physics_frame
	var space = game.get_world_3d().direct_space_state
	print("GROUND_RAY ",space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,4,4.5),Vector3(0,-4,4.5),1)))
	for i in 100:
		await physics_frame
		game.player.velocity = Vector3(0,-5,0)
		game.player.move_and_slide()
	print("GROUND_LAND position=",game.player.position," floor=",game.player.is_on_floor()," collisions=",game.player.get_slide_collision_count())
	for i in game.player.get_slide_collision_count():
		var c = game.player.get_slide_collision(i)
		print("GROUND_COLLISION normal=",c.get_normal()," travel=",c.get_travel()," collider=",c.get_collider())
	var start = game.player.position
	for i in 60:
		await physics_frame
		game.player.velocity = Vector3(0,-1,-4)
		game.player.move_and_slide()
	print("GROUND_MANUAL_MOVE ",game.player.position-start," floor=",game.player.is_on_floor())
	game.queue_free()
	await process_frame
	quit()
