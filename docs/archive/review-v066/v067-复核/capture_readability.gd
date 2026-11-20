extends SceneTree

var game

func _initialize():
	call_deferred("run")

func wait_frame():
	await process_frame
	await RenderingServer.frame_post_draw

func place_camera(at: Vector3, look_at: Vector3):
	var ground: Vector3 = game.Layout.on_ground(at)
	game.player.position = ground + Vector3.UP * 0.08
	game.player.velocity = Vector3.ZERO
	var direction: Vector3 = look_at - (game.player.position + Vector3.UP * 1.58)
	game.player.yaw = atan2(-direction.x, -direction.z)
	game.player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())

func capture(name: String):
	await wait_frame()
	game._capture(name)
	print("READABILITY_FRAME ", JSON.stringify({
		"version": game.VERSION, "renderer": RenderingServer.get_current_rendering_method(),
		"scale": root.scaling_3d_scale, "label_hidden": not game.stations[1].terminal_label.visible,
		"pose": str(game.player.position), "file": name
	}))

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_frame()
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if not compatibility:
		await capture("menu-v067.png")
	seed(2026067)
	game.start_action(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.combat.shot_rng.seed = 42
	game.combat._spawn_camp_wave(0)
	await physics_frame
	var roster: Array = game.combat.troops[0]
	var examples := ["Dragon Boat Festival", "Christmas Eve", "Children's Day", "on one's way back"]
	var wave: Array = game.combat.wave_words[0]
	for i in roster.size():
		var text: String = examples[i]
		for word in game.words:
			if str(word.english).replace("’", "'").to_lower() == text.to_lower():
				roster[i].assigned_word = word
				wave[i] = word
				break
	var center: Vector3 = game.combat.zone_center(0)
	var front := center + Vector3(0.6, 0, 4.8)
	var look_at := center + Vector3(0.0, 1.5, -6.0)
	look_at.y = game.terrain_height(look_at.x, look_at.z) + 1.50
	place_camera(front, look_at)
	game.combat.engage_camp(0)
	await create_timer(1.25).timeout
	if compatibility:
		await capture("first-camp-gl.png")
	else:
		await capture("first-camp-standard.png")
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F6
		event.pressed = true
		game._input(event)
		await create_timer(0.35).timeout
		await capture("first-camp-f6.png")
		place_camera(center + Vector3(-4.0, 0.0, 4.8), look_at)
		await create_timer(0.3).timeout
		await capture("first-camp-flank.png")
	game.queue_free()
	await process_frame
	quit()
