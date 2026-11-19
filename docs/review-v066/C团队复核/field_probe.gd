extends SceneTree

var game
var result = {}

func _initialize():
	call_deferred("run")

func sample(label):
	await create_timer(1.5).timeout
	var gaps: Array[float] = []
	var start_us := Time.get_ticks_usec()
	var last := start_us
	while last - start_us < 5000000:
		await process_frame
		var now := Time.get_ticks_usec()
		gaps.append((now - last) / 1000.0)
		last = now
	gaps.sort()
	return {"scene": label, "frames": gaps.size(), "seconds": (last-start_us)/1e6, "fps": gaps.size()*1e6/(last-start_us), "p95_ms": gaps[ceili(gaps.size()*0.95)-1], "max_ms": gaps[-1], "phase": game.rules.phase, "zone": game.combat.zone, "low": game.landscape.low_quality, "scale": root.scaling_3d_scale}

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var build_start := Time.get_ticks_msec()
	game = load("res://main.tscn").instantiate()
	game.profile_path_override = OS.get_environment("YS_C_TEST_PROFILE")
	if game.profile_path_override == "":
		quit(2)
		return
	root.add_child(game)
	var build_time := Time.get_ticks_msec() - build_start
	await process_frame
	result = {"version": game.VERSION, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "viewport": str(root.get_visible_rect().size), "voice": game.tts_voice_id != "", "qa": game.qa_mode, "segments": []}
	result["scene_build_ms"] = build_time
	result.segments.append(await sample("menu"))
	var enter_start := Time.get_ticks_msec()
	game.start_action(true, "normal")
	result["normal_setup_ms"] = Time.get_ticks_msec() - enter_start
	var center: Vector3 = game.combat.zone_center(0)
	var pos := center + Vector3(0.6, 0, 4.8)
	pos.y = game.terrain_height(pos.x, pos.z) + 0.08
	game.player.position = pos
	game.player.yaw = 0.0
	game.player.pitch = -0.025
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.combat.engage_camp(0)
	result["squad"] = game.combat.troops[0].size()
	result.segments.append(await sample("normal_first_camp"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(game.profile_path_override + ".png")
	if not game.landscape.low_quality:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F6
		key.pressed = true
		game._input(key)
		result.segments.append(await sample("same_camp_F6"))
	print("C_AUDIT ", JSON.stringify(result))
	game.queue_free()
	await process_frame
	quit()
