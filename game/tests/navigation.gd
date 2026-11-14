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

	# v0.6.1.1 Bridge-to-East-Hillside gentle slope traversal checks (strictly KEY_W walking, ZERO jumping!)
	var bridge_trails := [
		{
			"name": "South Bridge (z=7.0, cx=18.6) -> East Hillside -> Wangdao Pavilion",
			"start": Vector3(12.4, 0.0, 7.0),
			"waypoints": [Vector3(18.6, 0.0, 7.0), Vector3(24.4, 0.0, 7.0), Vector3(28.0, 0.0, 13.5), Vector3(30.8, 0.0, 18.2)]
		},
		{
			"name": "South Bridge (z=7.0, cx=18.6) -> North-East Ridge Trail",
			"start": Vector3(12.4, 0.0, 7.0),
			"waypoints": [Vector3(18.6, 0.0, 7.0), Vector3(24.4, 0.0, 7.0), Vector3(28.5, 0.0, -8.0)]
		},
		{
			"name": "Mid Stone Arch Bridge (z=-24.0, cx=16.5) -> East Overlook & Ridge",
			"start": Vector3(9.8, 0.0, -24.0),
			"waypoints": [Vector3(16.5, 0.0, -24.0), Vector3(23.0, 0.0, -24.0), Vector3(25.1, 0.0, -25.2), Vector3(27.0, 0.0, -35.5)]
		},
		{
			"name": "Upstream Bridge (z=-46.5, cx=18.5) -> East Recon Radio hillside",
			"start": Vector3(12.2, 0.0, -46.5),
			"waypoints": [Vector3(18.5, 0.0, -46.5), Vector3(24.3, 0.0, -46.5), Vector3(26.0, 0.0, -47.6), Vector3(27.8, 0.0, -56.0)]
		},
		{
			"name": "North Bridge (z=-73.5, cx=24.3) -> SE Bamboo Cache slope",
			"start": Vector3(18.0, 0.0, -76.0),
			"waypoints": [Vector3(18.6, 0.0, -73.5), Vector3(24.3, 0.0, -73.5), Vector3(30.2, 0.0, -73.5), Vector3(28.4, 0.0, -84.2)]
		}
	]
	for trail in bridge_trails:
		game.player.clear_movement_input()
		game.player.reset_stance()
		game.player.velocity = Vector3.ZERO
		game.player.position = game.Layout.on_ground(trail.start) + Vector3(0.0, 0.12, 0.0)
		for _f in 12:
			await physics_frame
		var trail_ok := true
		for wp in trail.waypoints:
			var wp_reached := false
			for _frame in 420:
				var off := Vector2(wp.x - game.player.position.x, wp.z - game.player.position.z)
				if off.length() < 0.72:
					wp_reached = true
					break
				game.player.yaw = atan2(-off.x, -off.y)
				game.player.held_keys[KEY_W] = true
				await physics_frame
			game.player.clear_movement_input()
			if not wp_reached:
				trail_ok = false
				print("BRIDGE_SLOPE_STUCK ", trail.name, " target=", wp, " actual=", game.player.position)
				for ci in game.player.get_slide_collision_count():
					var col: KinematicCollision3D = game.player.get_slide_collision(ci)
					var obj := col.get_collider() as Node3D
					if obj:
						print("  HIT ", obj.get_path(), " pos=", obj.global_position, " nrm=", col.get_normal())
				break
		checks += 1
		if not trail_ok:
			failures += 1
		print("PASS " if trail_ok else "FAIL ", "walk across bridge & climb East hillside without jumping: ", trail.name)

	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("NAVIGATION_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
