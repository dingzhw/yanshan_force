extends SceneTree
var game
func _initialize():call_deferred("run")
func capture(name: String):
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	game._capture(name)
func position_at(at: Vector3,yaw: float,pitch: float):
	game.player.position=game.Layout.on_ground(at)+Vector3.UP*0.1
	game.player.yaw=yaw;game.player.pitch=pitch
	for i in 20:await physics_frame
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await capture("v040-menu.png")
	game.start_action();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await position_at(Vector3(0,0,4.5),0,-0.08)
	await capture("v040-camp.png")
	await position_at(Vector3(-7,0,-18),0.4,-0.03)
	await capture("v040-path.png")
	game.player.aiming=true
	for i in 20:await physics_frame
	await capture("v040-aim.png")
	game.player.aiming=false
	await position_at(game.Layout.POEM+Vector3(0,0,2),0,-0.05)
	game.interact()
	await capture("v040-poem.png")
	game.exploration.choose(0)
	await capture("v040-poem-solved.png")
	game.exploration.close()
	await position_at(Vector3(-7,0,-54),-0.3,0.02)
	await capture("v040-bamboo.png")
	game._end_run(false)
	game.start_action(true);game.interact();game.combat.range_left=0.01
	await process_frame;await process_frame
	await position_at(game.Layout.STATIONS[1].at+Vector3(0,0,2),0,-0.03)
	await create_timer(1.4).timeout
	await capture("v040-word-soldiers.png")
	game.queue_free();await process_frame
	print("SLICE_VISUAL_COMPLETE");quit()
