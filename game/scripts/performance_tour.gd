extends Node
## Optional, visible QA tour. Uses real render timings and never saves a profile.
var game
var samples = []
var route_ok = true
var sampling = false
var blocked_at = ""
var last_sample_us := 0

func _process(_delta):
	if sampling:
		var now := Time.get_ticks_usec()
		samples.append((now - last_sample_us) / 1000.0)
		last_sample_us = now

func start_sampling():
	samples.clear()
	last_sample_us = Time.get_ticks_usec()
	sampling = true

func stop_sampling() -> Dictionary:
	sampling = false
	var total := 0.0
	for ms in samples:
		total += ms
	samples.sort()
	var p95 := float(samples[ceili(samples.size() * 0.95) - 1]) if not samples.is_empty() else 0.0
	return {
		"render_frames": samples.size(),
		"average_fps": 1000.0 * samples.size() / total if total > 0.0 else 0.0,
		"p95_frame_ms": p95,
		"max_frame_ms": samples[-1] if not samples.is_empty() else 0.0,
		"p95_meets_30fps_budget": p95 > 0.0 and p95 <= 1000.0 / 30.0
	}

func sample_combat(zone_index: int) -> Dictionary:
	if game.rules.phase in ["active", "extracting"]:
		game._end_run(false)
	game.start_action(true, "normal")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var center: Vector3 = game.combat.zone_center(zone_index)
	var stand: Vector3 = game.Layout.on_ground(center + Vector3(0.6, 0, 4.8))
	game.player.position = stand + Vector3.UP * 0.08
	game.player.yaw = 0.0
	game.player.pitch = -0.025
	await get_tree().physics_frame
	game.combat.engage_camp(zone_index)
	var squad_size: int = game.combat.living_soldiers(zone_index).size()
	await get_tree().create_timer(1.5).timeout
	start_sampling()
	var until := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < until and game.rules.phase == "active" and game.combat.zone == zone_index:
		await get_tree().process_frame
	var result := stop_sampling()
	result["zone"] = String(game.combat.zone_info(zone_index).id)
	result["squad_size"] = squad_size
	result["sample_completed"] = game.combat.zone == zone_index and Time.get_ticks_msec() >= until
	game._end_run(false)
	return result

func travel(goal: Vector3) -> bool:
	var began = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 18000:
		var offset = Vector2(goal.x - game.player.position.x, goal.z - game.player.position.z)
		if offset.length() < 0.65:
			game.player.clear_movement_input()
			return true
		game.player.yaw = atan2(-offset.x, -offset.y)
		game.player.held_keys[KEY_W] = true
		game.player.held_keys[KEY_SHIFT] = true
		await get_tree().physics_frame
	game.player.clear_movement_input()
	blocked_at = str(goal)
	print("TOUR_BLOCKED goal=", goal, " actual=", game.player.position)
	for i in game.player.get_slide_collision_count():
		var contact = game.player.get_slide_collision(i)
		print("TOUR_COLLIDER ", contact.get_collider().get_path(), " at ", contact.get_collider().global_position)
	return false

func challenge(index: int, count: int):
	if not await travel(game.Layout.on_ground(game.Layout.STATIONS[index].at + Vector3(0.8, 0, 0.8))):
		route_ok = false
		return
	game._activate_station(index)
	if game.active_station != index:
		route_ok = false
		blocked_at = "terminal-" + str(index)
		return
	game.player.clear_movement_input()
	game.player.yaw = 0
	game.player.pitch = 0
	for i in count:
		while not game.rules.question_open:
			await get_tree().process_frame
		if game.player.ammo <= 0 and game.player.reload_left <= 0:
			game.player.reload()
		while game.player.reload_left > 0 or game.player.cooldown > 0 or game.player.ammo <= 0:
			await get_tree().physics_frame
		game.player.recoil = 0.0
		var target = game.stations[index].boards[game.answer_index]
		var direction = target.global_position - game.player.camera.global_position
		game.player.yaw = atan2(-direction.x, -direction.z)
		game.player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		await get_tree().physics_frame
		await get_tree().physics_frame
		var previous = game.rules.score
		game.player.shoot()
		if game.rules.score < previous + game.Rules.BASE_ANSWER_SCORE:
			route_ok = false
			blocked_at = "shot-" + str(index)
			return
		await get_tree().create_timer(0.25).timeout
		if game.player.ammo == 0:
			game.player.reload()

func discovery(id: String) -> bool:
	var node
	for candidate in game.exploration.nodes:
		if candidate.get_meta("explore_id") == id:
			node = candidate
	if not is_instance_valid(node):
		return false
	if not await travel(node.position + Vector3(0, 0, 2)):
		return false
	game.interact()
	if id == "english":
		return game.exploration.states.english
	if not game.exploration.busy:
		return false
	if id != "clue":
		var ans_idx = game.exploration.answer_button_index(id)
		game.exploration.buttons[ans_idx].pressed.emit()
	await get_tree().process_frame
	game.exploration.close()
	return game.exploration.states[id]

func supply_stop() -> bool:
	var sup = game.pickup_nodes[0]
	if not await travel(sup.position + Vector3(0.5, 0, 0.8)):
		return false
	await get_tree().physics_frame
	game.interact()
	if not game.cipher_terminal.busy:
		return false
	game.cipher_terminal.solve_all_for_qa()
	await get_tree().process_frame
	game.cipher_terminal.close()
	return not sup.visible

func crate_stop() -> bool:
	var center: Vector3 = game.stations[1].position
	if not await travel(center + Vector3(0, 0, 4)):
		return false
	var crate = game.crate_nodes[0]
	if not await travel(crate.position + Vector3(0, 0, 2)):
		return false
	game.interact()
	if not game.cipher_terminal.busy:
		return false
	game.cipher_terminal.solve_all_for_qa()
	await get_tree().process_frame
	game.cipher_terminal.close()
	if not (crate.get_meta("title") in game.rules.crates):
		return false
	if not await travel(center + Vector3(0, 0, 4)):
		return false
	return await travel(center)

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.start_action(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._notice("正在自动巡检：走完山路、识词、常规单词箱、阶梯密码箱与撤离，不改动玩家存档。")
	await get_tree().create_timer(1.5).timeout
	start_sampling()
	var began = Time.get_ticks_msec()
	if not await supply_stop():
		route_ok = false
		blocked_at = "camp-supply-box"
	if route_ok:
		await challenge(0, 6)
	for waypoint in game.Layout.ROUTE.slice(1):
		if not route_ok:
			break
		if not await travel(waypoint):
			route_ok = false
			break
		if waypoint == game.Layout.ROUTE[1]:
			if not await discovery("clue") or not await discovery("english"):
				route_ok = false
				blocked_at = "english-discovery"
				break
			if not await travel(waypoint):
				route_ok = false
				break
		if waypoint == game.Layout.ROUTE[2]:
			if not await discovery("poem"):
				route_ok = false
				blocked_at = "poem-discovery"
				break
			if not await travel(waypoint):
				route_ok = false
				break
		if waypoint == game.Layout.ROUTE[4]:
			if not await discovery("math"):
				route_ok = false
				blocked_at = "math-discovery"
				break
			if not await travel(waypoint):
				route_ok = false
				break
		for index in [1, 2]:
			if waypoint.distance_to(game.Layout.STATIONS[index].at) < 0.1:
				await challenge(index, 5)
				if index == 1 and route_ok and not await crate_stop():
					route_ok = false
					blocked_at = "cipher-crate"
	if route_ok:
		game.interact()
		var extract_began = Time.get_ticks_msec()
		while game.rules.phase == "extracting" and Time.get_ticks_msec() - extract_began < int((game.Rules.EXTRACTION_SECONDS + 2.5) * 1000.0):
			await get_tree().process_frame
	var practice := stop_sampling()
	var completed = route_ok and game.rules.phase == "result" and game.rules.profile.extractions == 1 and game.exploration.completed() == 3
	var elapsed = float(Time.get_ticks_msec() - began) / 1000.0
	var p95: float = practice.p95_frame_ms
	var report = {
		"version": game.VERSION,
		"gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(),
		"os": OS.get_name(),
		"viewport": str(get_viewport().get_visible_rect().size),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"scaling_3d_scale": get_viewport().scaling_3d_scale,
		"startup_menu_frame_ms": game.startup_menu_frame_ms,
		"startup_stages_ms": game.startup_ms,
		"vsync_disabled": true,
		"duration_seconds": elapsed,
		"render_frames": practice.render_frames,
		"average_fps": practice.average_fps,
		"p95_frame_ms": p95,
		"max_frame_ms": practice.max_frame_ms,
		"route_and_extraction_passed": completed,
		"blocked_at": blocked_at,
		"score": game.rules.score,
		"optional_discoveries": game.exploration.completed(),
		"opened_crates": game.rules.crates.size(),
		"low_quality": game.landscape.low_quality,
		"p95_meets_30fps_budget": practice.p95_meets_30fps_budget,
		"profile_saved": false
	}
	var normal_first := await sample_combat(0)
	var normal_b := await sample_combat(2)
	report["normal_first_camp"] = normal_first
	report["normal_b_outpost"] = normal_b
	var verified: bool = completed and normal_first.sample_completed and normal_b.sample_completed
	var folder = OS.get_environment("DRZ_DIAGNOSTICS_DIR")
	if folder == "":
		folder = "user://diagnostics"
	var error = DirAccess.make_dir_recursive_absolute(folder)
	var path = folder.path_join("performance-" + str(int(Time.get_unix_time_from_system())) + ".json")
	var file = FileAccess.open(path, FileAccess.WRITE) if error == OK else null
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("PERFORMANCE_REPORT ", JSON.stringify(report))
	print("PERFORMANCE_REPORT_PATH ", ProjectSettings.globalize_path(path))
	if game.rules.phase != "result":
		game._end_run(false)
	game.menu_title.text = "巡检完成" if verified and file != null else "巡检发现问题"
	game.menu_summary.text = "靶场撤离 %s · P95 %.1f ms\n普通首营 %.1f ms · B 区 %.1f ms\n%s" % [
		"通过" if completed else "未通过", p95, normal_first.p95_frame_ms, normal_b.p95_frame_ms,
		"报告已写入 diagnostics 文件夹。" if file != null else "诊断报告写入失败。"
	]
	game.menu_status.text = report.gpu
	if "--auto-quit" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0 if verified and file != null else 1)
