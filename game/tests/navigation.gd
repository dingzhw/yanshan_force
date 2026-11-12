extends SceneTree
var game
var failures = 0
var checks = 0

func _initialize(): call_deferred("run")

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	for i in 30: await physics_frame
	for waypoint in game.Layout.ROUTE.slice(1):
		var reached = false
		for frame in 900:
			var offset = Vector2(waypoint.x-game.player.position.x,waypoint.z-game.player.position.z)
			if offset.length()<0.6:
				reached = true
				break
			game.player.yaw = atan2(-offset.x,-offset.y)
			game.player.held_keys[KEY_W] = true
			await physics_frame
		game.player.clear_movement_input()
		checks += 1
		if not reached: failures += 1
		print("PASS " if reached else "FAIL ","route waypoint ",waypoint," actual=",game.player.position)
		if not reached:
			for i in game.player.get_slide_collision_count():
				var collision = game.player.get_slide_collision(i)
				var collider = collision.get_collider()
				print("OBSTRUCTION ",collider.get_path()," at=",collider.global_position," parent=",collider.get_parent().global_position," normal=",collision.get_normal())
			break
	checks += 1
	var arrived = Vector2(game.player.position.x-game.exit_position.x,game.player.position.z-game.exit_position.z).length()<1.0
	if not arrived: failures += 1
	print("PASS " if arrived else "FAIL ","complete walking route reaches extraction")
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("NAVIGATION_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
