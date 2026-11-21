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
		for frame in 1400:
			var offset = Vector2(waypoint.x-game.player.position.x,waypoint.z-game.player.position.z)
			if offset.length()<0.65:
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

	# v0.8.5 All 5 Creek Bridges (including Triple-Arch Bluestone Bridge & North Stone Arch Bridge) -> East Hillside walks without jumping!
	var b0x: float = game.Layout.stream_center_x(16.0)
	var b1x: float = game.Layout.stream_center_x(-28.0)
	var b2x: float = game.Layout.stream_center_x(-74.0)
	var b3x: float = game.Layout.stream_center_x(-124.0)
	var b4x: float = game.Layout.stream_center_x(-164.0)
	var bridge_trails := [
		{
			"name": "South Bridge (z=16.0) -> East Hillside -> Wangdao Approach",
			"start": Vector3(b0x - 6.8, 0.0, 16.0),
			"waypoints": [Vector3(b0x, 0.0, 16.0), Vector3(b0x + 6.8, 0.0, 16.0), Vector3(44.5, 0.0, 20.5)]
		},
		{
			"name": "Central Triple-Arch Bluestone Bridge (z=-28.0) -> East Tea Pavilion Trail",
			"start": Vector3(b1x - 9.2, 0.0, -28.0),
			"waypoints": [Vector3(b1x, 0.0, -28.0), Vector3(b1x + 9.2, 0.0, -28.0), Vector3(42.0, 0.0, -28.0)]
		},
		{
			"name": "Mid-Creek Bridge (z=-74.0) -> East Tea-Hill Slope",
			"start": Vector3(b2x - 6.8, 0.0, -74.0),
			"waypoints": [Vector3(b2x, 0.0, -74.0), Vector3(b2x + 6.8, 0.0, -74.0), Vector3(42.0, 0.0, -74.0)]
		},
		{
			"name": "Upper-Pass Bridge (z=-124.0) -> Extraction Approach",
			"start": Vector3(b3x - 6.8, 0.0, -124.0),
			"waypoints": [Vector3(b3x, 0.0, -124.0), Vector3(b3x + 6.8, 0.0, -124.0), Vector3(41.0, 0.0, -128.0)]
		},
		{
			"name": "North Stone Arch Bridge (z=-164.0) -> North Airdrop Ridge",
			"start": Vector3(b4x - 7.5, 0.0, -164.0),
			"waypoints": [Vector3(b4x, 0.0, -164.0), Vector3(b4x + 7.5, 0.0, -164.0), Vector3(46.0, 0.0, -164.0)]
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
			for _frame in 520:
				var off := Vector2(wp.x - game.player.position.x, wp.z - game.player.position.z)
				if off.length() < 0.78:
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
