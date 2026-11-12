extends SceneTree
var game
var checks = 0
var failures = 0

func _initialize():
	call_deferred("run")

func verify(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)

func key(code: int, down: bool):
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func walk(start: Vector3, yaw: float, frames: int, jump = false) -> Vector3:
	game.player.clear_movement_input()
	game.player.position = start
	game.player.yaw = yaw
	for i in 20: await physics_frame
	key(KEY_W,true)
	if jump: key(KEY_SPACE,true)
	for i in frames:
		await physics_frame
		if i == 7: key(KEY_SPACE,false)
	key(KEY_W,false)
	key(KEY_SPACE,false)
	var result = game.player.position
	game.player.clear_movement_input()
	return result

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,3,[game.player.get_rid()]))

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	await physics_frame
	game.interact()
	for fixture in [["nature/rock_largeA",3.0,"convex"],["nature/tree_oak",6.0,"tree"],["survival/barrel",1.0,"convex"],["survival/box-large",1.0,"convex"]]:
		var prop = game._model(game,"res://assets/"+fixture[0]+".glb",Vector3(0,0,12),fixture[1],0,fixture[2])
		await physics_frame
		var position = await walk(Vector3(0,0.2,16),0,90)
		print("BLOCK ",fixture[0]," ",position)
		verify(position.z>12.3,fixture[0]+" blocks an actual walking capsule")
		var hit = ray(Vector3(0,0.6,16),Vector3(0,0.6,8))
		verify(not hit.is_empty(),fixture[0]+" blocks the bullet ray")
		prop.queue_free()
		await physics_frame
	var tent = game._model(game,"res://assets/survival/tent-canvas.glb",Vector3(0,0,12),3.5,0,"trimesh")
	await physics_frame
	var inside = await walk(Vector3(0,0.2,16),0,50)
	print("TENT_ENTRANCE ",inside)
	verify(inside.z<13 and inside.z>10,"tent entrance admits the player")
	var outside = await walk(inside,PI,50)
	verify(outside.z>15,"player can leave through the tent entrance")
	var side = await walk(Vector3(5,0.2,12),PI/2,80)
	verify(side.x>0.3,"tent canvas side blocks the player")
	tent.queue_free()
	await physics_frame
	var low = game._model(game,"res://assets/nature/rock_largeA.glb",Vector3(0,0,12),0.55,0,"convex")
	await physics_frame
	var landed = await walk(Vector3(0,0.1,13.6),0,23,true)
	for i in 45: await physics_frame
	verify(game.player.is_on_floor() and game.player.position.y>0.15,"jump lands on the low rock")
	low.queue_free()
	await physics_frame
	var rock = game._model(game,"res://assets/nature/rock_largeA.glb",Vector3.ZERO,1.5,0,"convex")
	await physics_frame
	var around = await walk(Vector3(5.5,0.1,4),0,100)
	verify(around.z< -2,"player can walk around a solid rock")
	rock.queue_free()
	await physics_frame
	var pickup = game.pickup_nodes[0]
	game.Props.set_enabled(pickup,false)
	await physics_frame
	var hit = ray(pickup.position+Vector3(0,0.25,2),pickup.position+Vector3(0,0.25,-2))
	verify(hit.is_empty(),"collected pickup removes its blocking collider")
	game.Props.set_enabled(pickup,true)
	await physics_frame
	verify(not ray(pickup.position+Vector3(0,0.25,2),pickup.position+Vector3(0,0.25,-2)).is_empty(),"new run restores pickup collider")
	var tower=game.Layout.on_ground(Vector3(-34,0,-102))
	verify(not ray(tower+Vector3(-0.9,0.5,3),tower+Vector3(-0.9,0.5,-2)).is_empty(),"observation tower pillars block bullets")
	var board = game.targets[0].get_parent()
	verify((board.collision_layer & 1)!=0,"word board also blocks player layer")
	var stopped = await walk(Vector3(board.global_position.x,0.1,board.global_position.z+3),0,90)
	verify(stopped.z>board.global_position.z+0.3,"word board blocks actual walking")
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("PHYSICS_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
