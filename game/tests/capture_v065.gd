extends SceneTree
## v0.6.5 GPU Screenshot & Forward+ Dual-Tier Benchmark ('晴云烟山 · 太平村云海梯田美学全图统合 & 波次休整修复')

var game
var frame_samples_ms: Array[float] = []
var sampling_active := false

func _initialize():
	run()

func _process(delta: float) -> bool:
	if sampling_active and delta > 0.0:
		frame_samples_ms.append(delta * 1000.0)
	return false

func wait_render(frames: int = 8):
	await process_frame
	for _i in frames:
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw

func aim_player_exact(foot_pos: Vector3, look_target: Vector3):
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.reset_stance()
	game.player.current_eye_y = 1.58
	game.player.camera.position.y = 1.58
	game.player.position = foot_pos
	var eye_pos: Vector3 = foot_pos + Vector3(0.0, 1.58, 0.0)
	var d: Vector3 = look_target - eye_pos
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.25, 1.25)

func ground_foot(x: float, z: float, extra_y: float = 0.08) -> Vector3:
	return Vector3(x, float(game.terrain_height(x, z)) + extra_y, z)

func measure_tier_fps(is_low: bool) -> Dictionary:
	game.landscape.set_low_quality(is_low)
	await wait_render(15)
	var views := [
		{"name": "creek_shrine_bridge", "foot": ground_foot(13.2, -6.2), "look": Vector3(17.5, 5.2, -21.0)},
		{"name": "south_cloud_valley", "foot": ground_foot(6.5, 14.8), "look": Vector3(17.5, 5.8, 42.0)},
	]
	frame_samples_ms.clear()
	var per_view := {}
	for v in views:
		aim_player_exact(v["foot"], v["look"])
		for _w in 18:
			await process_frame
		sampling_active = true
		var s0 := frame_samples_ms.size()
		for _s in 70:
			await process_frame
		sampling_active = false
		var sum_ms := 0.0
		var cnt := 0
		for k in range(s0, frame_samples_ms.size()):
			sum_ms += frame_samples_ms[k]
			cnt += 1
		per_view[v["name"]] = snappedf(1000.0 * float(cnt) / maxf(0.001, sum_ms), 0.1)
	var total := 0.0
	for m in frame_samples_ms:
		total += m
	return {
		"low_quality": is_low,
		"average_fps": snappedf(1000.0 * float(frame_samples_ms.size()) / maxf(0.001, total), 0.1),
		"per_view_fps": per_view,
	}

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(12)

	# Shot 01: Camp Command Menu v0.6.5
	game._capture("01-menu-v065.png")

	game.start_action(true, "normal")
	await wait_render(16)

	var bench_modern := await measure_tier_fps(false)
	var bench_igpu := await measure_tier_fps(true)
	print("V065_FORWARD_PLUS_BENCH=", JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"modern_high_tier": bench_modern,
		"igpu_balanced_tier": bench_igpu,
	}))

	game.landscape.set_low_quality(false)
	game.wildlife.frozen_for_capture = true
	game.combat.health = 100
	game.combat.shield = game.rules.max_shield()
	game.feedback_left = 0.0
	game.feedback_panel.hide()

	# Shot 02: Dual-Hand Knife + Creek + Hui Plaster Shrine + Arch Bridge + Sunlit Camphor & Cumulus Sky!
	game.player.select_weapon(1)
	aim_player_exact(ground_foot(13.2, -6.2, 0.08), Vector3(17.5, 5.4, -21.0))
	game.player.weapon_root.position = Vector3(0.0, -0.145, -0.35)
	game.player.weapon_view.slash_left = 0.0
	game.player.weapon_view.animate(0.0, 0.0, 0.0, false)
	await create_timer(1.10).timeout
	await wait_render(8)
	game._capture("02-taiping-creek-shrine-knife.png")

	# Shot 03: Sunlit Weeping Willow + Moso Bamboo + Golden-Amber Maple + Towering Cumulus Sky!
	game.player.select_weapon(0)
	aim_player_exact(ground_foot(17.2, -2.8, 0.08), Vector3(24.0, 6.4, -13.2))
	game.player.weapon_root.position = Vector3(0.21, -0.245, -0.58)
	await create_timer(1.10).timeout
	await wait_render(8)
	game._capture("03-taiping-willow-bamboo-sky.png")

	# Shot 04: Close-up Hui '粉墙黛瓦·马头墙' Shrine + Sky-Reflecting Brook + Mountain Blossoms!
	game.hud.hide()
	game.player.weapon_root.hide()
	game.world_loot.visible = false
	var shrine_wpos := Vector3(11.65, float(game.terrain_height(11.65, -14.95)), -14.95)
	aim_player_exact(ground_foot(14.6, -11.4, 0.04), shrine_wpos + Vector3(0.15, 1.45, -1.2))
	await create_timer(1.05).timeout
	await wait_render(8)
	game._capture("04-taiping-hui-shrine-blossoms.png")
	game.world_loot.visible = true
	game.hud.show()
	game.player.weapon_root.show()

	# Shot 05: Taiping Village Grand Vista from Wangdao Overlook — Golden-Green Paddies, Sky-Mirror Plots, Hui Cottages, Cloud Sea & Crags!
	aim_player_exact(ground_foot(30.2, 24.4, 0.08), Vector3(8.0, -7.2, 96.0))
	game.player.weapon_root.position = Vector3(0.21, -0.245, -0.58)
	await create_timer(1.10).timeout
	await wait_render(8)
	game._capture("05-taiping-cloud-sea-paddy-valley.png")

	# Shot 06: Same Vista in [F6] Integrated-GPU Balanced Tier
	game.landscape.set_low_quality(true)
	await create_timer(1.05).timeout
	await wait_render(8)
	game._capture("06-taiping-igpu-balanced-f6.png")
	game.landscape.set_low_quality(false)

	# Shot 07: Cleared Wave 1 at Camp 0 showing Empty Camp + Squad Loot Drop + 8.5s Rest Countdown HUD!
	var c0: Vector3 = game.combat.zone_center(0)
	aim_player_exact(ground_foot(c0.x + 1.2, c0.z + 5.8, 0.08), c0 + Vector3(0.0, 0.9, -2.5))
	game.player.weapon_root.position = Vector3(0.21, -0.245, -0.58)
	game.combat.engage_camp(0)
	game.combat.last_kill_pos = c0 + Vector3(0.0, 0.0, -1.2)
	for s0 in game.combat.troops[0]:
		if is_instance_valid(s0):
			s0.defeated = true
	game.combat._complete_current_wave(0)
	await wait_render(10)
	game._capture("07-camp-wave-rest-interval.png")

	game.queue_free()
	await process_frame
	quit(0)
