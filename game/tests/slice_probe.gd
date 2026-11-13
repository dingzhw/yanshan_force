extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.start_action()
	game.player.position=game.Layout.on_ground(game.Layout.ROUTE[2])+Vector3.UP*0.1
	for i in 15:await physics_frame
	var goal=game.Layout.on_ground(game.Layout.POEM+Vector3(0,0,2))
	for frame in 300:
		var offset=Vector2(goal.x-game.player.position.x,goal.z-game.player.position.z)
		if offset.length()<0.5:break
		game.player.yaw=atan2(-offset.x,-offset.y);game.player.held_keys[KEY_W]=true
		await physics_frame
	game.player.clear_movement_input()
	print("PROBE goal=",goal," actual=",game.player.position)
	for i in game.player.get_slide_collision_count():
		var c=game.player.get_slide_collision(i);print("PROBE_COLLIDER ",c.get_collider().get_path()," global=",c.get_collider().global_position," parent=",c.get_collider().get_parent().global_position," normal=",c.get_normal())
	quit()
