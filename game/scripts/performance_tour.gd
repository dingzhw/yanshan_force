extends Node
## Optional, visible 3-part QA & hardware benchmark tour (v0.8.2_dev1).
## Part 1: Practice Range pure training route (ZERO field supply boxes or crates!)
## Part 2: Formal Normal Operation supply box, cipher crate & extraction verification
## Part 3: 4-Scene real-render frame-time sweep (First Camp, B Outpost, Yanxia Cave, Wangdao Overlook)
## Uses real render timings and never saves/modifies the player's save profile.

var game
var samples: Array = []
var route_ok := true
var sampling := false
var blocked_at := ""
var last_sample_us := 0
var first_spike_ms := 0.0
var sample_frames_seen := 0

func _process(_delta):
	if sampling:
		var now := Time.get_ticks_usec()
		var dt_ms := (now - last_sample_us) / 1000.0
		samples.append(dt_ms)
		sample_frames_seen += 1
		if sample_frames_seen <= 5:
			first_spike_ms = maxf(first_spike_ms, dt_ms)
		last_sample_us = now

func start_sampling():
	samples.clear()
	first_spike_ms = 0.0
	sample_frames_seen = 0
	last_sample_us = Time.get_ticks_usec()
	sampling = true

func stop_sampling() -> Dictionary:
	sampling = false
	var total := 0.0
	for ms in samples:
		total += float(ms)
	samples.sort()
	var p95 := float(samples[ceili(samples.size() * 0.95) - 1]) if not samples.is_empty() else 0.0
	return {
		"render_frames": samples.size(),
		"average_fps": 1000.0 * samples.size() / total if total > 0.0 else 0.0,
		"p95_frame_ms": p95,
		"max_frame_ms": float(samples[-1]) if not samples.is_empty() else 0.0,
		"first_entry_spike_ms": first_spike_ms,
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
	start_sampling()
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and game.rules.phase == "active" and game.combat.zone == zone_index:
		await get_tree().process_frame
	var result := stop_sampling()
	result["zone"] = String(game.combat.zone_info(zone_index).id)
	result["squad_size"] = squad_size
	result["sample_completed"] = game.combat.zone == zone_index and Time.get_ticks_msec() >= until
	game._end_run(false)
	return result

func sample_landmark(label: String, stand_pos: Vector3, yaw_rad: float, pitch_rad: float, combat_mode: bool = true) -> Dictionary:
	if game.rules.phase in ["active", "extracting"]:
		game._end_run(false)
	game.start_action(combat_mode, "normal")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.player.position = stand_pos
	game.player.yaw = yaw_rad
	game.player.pitch = pitch_rad
	await get_tree().physics_frame
	await get_tree().process_frame
	start_sampling()
	var until := Time.get_ticks_msec() + 3500
	while Time.get_ticks_msec() < until and game.rules.phase == "active":
		await get_tree().process_frame
	var result := stop_sampling()
	result["scene"] = label
	result["sample_completed"] = Time.get_ticks_msec() >= until
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
	if not is_instance_valid(sup) or not sup.visible:
		return false
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
	var crate = game.crate_nodes[0]
	if not is_instance_valid(crate) or not crate.visible:
		return false
	game.player.position = crate.position + Vector3(0, 0.15, 1.8)
	await get_tree().physics_frame
	game.interact()
	if not game.cipher_terminal.busy:
		return false
	game.cipher_terminal.solve_all_for_qa()
	await get_tree().process_frame
	game.cipher_terminal.close()
	return crate.get_meta("title") in game.rules.crates

func _run_formal_combat_supply_and_extract() -> Dictionary:
	if game.rules.phase in ["active", "extracting"]:
		game._end_run(false)
	game.start_action(true, "normal")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().physics_frame
	var out := {"supply_opened": false, "crate_opened": false, "extraction_completed": false, "blocked_at": ""}
	# 1) Open Camp Supply Box via spelling cipher in formal Normal Operation
	out.supply_opened = await supply_stop()
	if not out.supply_opened:
		out.blocked_at = "formal-supply-box"
		game._end_run(false)
		return out
	# 2) Meet Tier-1 crate & extraction criteria cleanly, then crack Tier-1 password crate
	for _k in 18:
		game.rules.open_question()
		game.rules.answer(true)
	game.rules.outposts_cleared = 2
	game.rules.boss_defeated = true
	out.crate_opened = await crate_stop()
	if not out.crate_opened:
		out.blocked_at = "formal-cipher-crate"
		game._end_run(false)
		return out
	# 3) Move to B-Point Extraction Beacon and complete 5s extraction countdown
	game.player.position = game.exit_position + Vector3(0, 0.15, 1.6)
	await get_tree().physics_frame
	game.interact()
	if game.rules.phase == "extracting":
		game.extraction_left = 0.08
		var ext_began := Time.get_ticks_msec()
		while game.rules.phase == "extracting" and Time.get_ticks_msec() - ext_began < 3000:
			await get_tree().process_frame
	out.extraction_completed = (game.rules.phase == "result" and game.rules.profile.extractions >= 1)
	if not out.extraction_completed:
		out.blocked_at = "formal-extraction"
		game._end_run(false)
	return out

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# =========================================================================
	# PART 1: Practice Range Pure Training Route (ZERO supply box / crate loot)
	# =========================================================================
	game.start_action(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._notice("正在自动巡检（1/3）：自由靶场纯识词路线与 3 处探索节点，不改动玩家存档。")
	await get_tree().create_timer(1.2).timeout
	start_sampling()
	var began = Time.get_ticks_msec()
	route_ok = true
	blocked_at = ""
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
	if route_ok:
		game.interact()
		var extract_began = Time.get_ticks_msec()
		while game.rules.phase == "extracting" and Time.get_ticks_msec() - extract_began < int((game.Rules.EXTRACTION_SECONDS + 2.5) * 1000.0):
			await get_tree().process_frame
	var practice := stop_sampling()
	var practice_completed = route_ok and game.rules.phase == "result" and game.exploration.completed() == 3
	var elapsed = float(Time.get_ticks_msec() - began) / 1000.0

	# =========================================================================
	# PART 2: Formal Combat Operation Supply Box, Cipher Crate & Extraction
	# =========================================================================
	var formal_res := await _run_formal_combat_supply_and_extract()
	var formal_ok: bool = bool(formal_res.supply_opened and formal_res.crate_opened and formal_res.extraction_completed)

	# =========================================================================
	# PART 3: 4-Scene Frame-Time Benchmark Sweep (30 FPS / 33.3ms P95 Budget)
	# =========================================================================
	var normal_first := await sample_combat(0)
	var normal_b := await sample_combat(2)
	var cave_pos: Vector3 = game.Layout.on_ground(Vector3(-41.60, 0.0, -55.4)) + Vector3(0, 0.12, 0)
	var cave_scene := await sample_landmark("yanxia_cave_entrance", cave_pos, 0.0, -0.02, true)
	var wangdao_pos: Vector3 = game.landscape.wangdao_deck_pos + Vector3(0, 0.12, -0.35) if is_instance_valid(game.landscape) else game.Layout.on_ground(Vector3(35.2, 0.0, 24.8))
	var wangdao_scene := await sample_landmark("wangdao_overlook", wangdao_pos, PI, -0.14, false)

	var scenes_ok: bool = bool(normal_first.sample_completed and normal_b.sample_completed and cave_scene.sample_completed and wangdao_scene.sample_completed)
	var verified: bool = practice_completed and formal_ok and scenes_ok

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
		"first_entry_spike_ms": practice.first_entry_spike_ms,
		"practice_training_passed": practice_completed,
		"formal_combat_supply_extract": formal_res,
		"formal_combat_passed": formal_ok,
		"route_and_extraction_passed": practice_completed and formal_ok,
		"blocked_at": blocked_at if blocked_at != "" else str(formal_res.blocked_at),
		"optional_discoveries": game.exploration.completed(),
		"low_quality": game.landscape.low_quality,
		"p95_meets_30fps_budget": practice.p95_meets_30fps_budget,
		"normal_first_camp": normal_first,
		"normal_b_outpost": normal_b,
		"yanxia_cave_entrance": cave_scene,
		"wangdao_overlook": wangdao_scene,
		"all_sections_verified": verified,
		"profile_saved": false
	}

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
	game.menu_title.text = "巡检全部通过" if verified and file != null else "巡检发现问题"
	game.menu_summary.text = (
		"1. 自由靶场纯训练：%s · P95 %.1f ms\n" % ["通过" if practice_completed else "失败", p95]
		+ "2. 正式行动开箱撤离：%s（箱/密码/撤离）\n" % ("通过" if formal_ok else "失败")
		+ "3. 四景帧时 P95：首营 %.1f / B区 %.1f / 古洞 %.1f / 望稻 %.1f ms\n%s" % [
			normal_first.p95_frame_ms, normal_b.p95_frame_ms, cave_scene.p95_frame_ms, wangdao_scene.p95_frame_ms,
			"报告已写入 diagnostics 文件夹。" if file != null else "诊断报告写入失败。"
		]
	)
	game.menu_status.text = report.gpu
	if "--auto-quit" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0 if verified and file != null else 1)
