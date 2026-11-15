extends SceneTree
## Captures GPU-rendered 1280x720 screenshots & Standard-Quality (real-time shadows ON) FPS benchmark for v0.6.2.1:
## 1) Main menu v0.6.2.1 with Normal Operation ("普通行动 · 常规"), Confidential Operation ("机密行动 · 高危") & Free Range ("自由靶场");
## 2) Normal Operation ("普通行动 · 单兵轮攻"): 1 designated attacker advancing/aiming while 4 word soldiers hold readable non-firing escort arc;
## 3) Confidential Operation ("机密行动 · 估值×1.35"): golden HUD badge & full 5-soldier coordinated assault pressure;
## 4) Yanxia Ancient Cavern West Wall: frameless stone-chiseled ancestral petroglyph ("先民岩凿壁画《烟山耕读》") cut directly into living limestone;
## 5) Yanxia Ancient Cavern East Wall: frameless incised rock chronicle ("石壁题志 ·《烟霞古洞志》").

const Soldier = preload("res://scripts/word_soldier.gd")
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

func aim_player_exact(foot_pos: Vector3, look_target: Vector3, stance_mode: int = 0):
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.reset_stance()
	if stance_mode != 0:
		game.player.set_stance(stance_mode, true)
	game.player.current_eye_y = 1.04 if stance_mode == 1 else 1.58
	game.player.camera.position.y = game.player.current_eye_y
	game.player.position = foot_pos
	var eye_pos: Vector3 = foot_pos + Vector3(0.0, float(game.player.current_eye_y), 0.0)
	var d: Vector3 = look_target - eye_pos
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.25, 1.25)

func ground_foot(x: float, z: float, extra_y: float = 0.06) -> Vector3:
	return Vector3(x, float(game.terrain_height(x, z)) + extra_y, z)

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(10)

	game.landscape.set_low_quality(false)
	await wait_render(6)

	# 1. Main menu with Normal / Confidential / Free Range modes
	game._refresh_menu("烟山基地 v0.6.2.1 · 普通/机密双行动与先民岩画")
	await wait_render(6)
	game._capture("01-menu-v0621.png")

	# Start Normal Operation & run Standard-Quality GPU benchmark!
	game.start_action(true, "normal")
	game.landscape.set_low_quality(false)
	await wait_render(18)

	var bench_views := [
		{"name": "south_valley_vista", "foot": ground_foot(6.5, 14.5, 0.12), "look": Vector3(16.5, 1.5, 38.0)},
		{"name": "bamboo_maze_south_gate", "foot": ground_foot(-40.8, -32.4, 0.10), "look": Vector3(-41.6, 8.0, -38.0)},
		{"name": "yanxia_chiseled_petroglyph", "foot": Vector3(-40.85, 6.526, -60.95), "look": Vector3(-44.90, 8.15, -61.15)},
		{"name": "yanxia_inner_sanctum", "foot": Vector3(-41.35, 6.526, -63.15), "look": Vector3(-41.85, 7.65, -67.15)}
	]
	frame_samples_ms.clear()
	var per_view := {}
	for bv in bench_views:
		var foot_v: Vector3 = bv["foot"]
		var look_v: Vector3 = bv["look"]
		var vname: String = str(bv["name"])
		aim_player_exact(foot_v, look_v, 0)
		for _w in 18:
			await process_frame
		var local_ms: Array[float] = []
		sampling_active = true
		var start_idx := frame_samples_ms.size()
		for _s in 75:
			await process_frame
		sampling_active = false
		for k in range(start_idx, frame_samples_ms.size()):
			local_ms.append(frame_samples_ms[k])
		var sum_local := 0.0
		for v in local_ms:
			sum_local += v
		per_view[vname] = snappedf(1000.0 * float(local_ms.size()) / maxf(0.001, sum_local), 0.1)

	var total_ms := 0.0
	for m in frame_samples_ms:
		total_ms += m
	var sorted_ms: Array[float] = frame_samples_ms.duplicate()
	sorted_ms.sort()
	var avg_fps: float = 1000.0 * float(sorted_ms.size()) / maxf(0.001, total_ms)
	var p95_ms: float = sorted_ms[int(float(sorted_ms.size() - 1) * 0.95)] if not sorted_ms.is_empty() else 0.0
	print("STANDARD_FPS_BENCHMARK ", JSON.stringify({
		"gpu": RenderingServer.get_video_adapter_name(),
		"low_quality": game.landscape.low_quality,
		"frames": sorted_ms.size(),
		"average_fps": snappedf(avg_fps, 0.1),
		"p95_frame_ms": snappedf(p95_ms, 0.2),
		"per_view_fps": per_view
	}))

	# 2. Normal Operation ("普通行动 · 单兵轮攻"): 1 active attacker + 4 readable non-firing escorts!
	game._end_run(false)
	game.start_action(true, "normal")
	game.landscape.set_low_quality(false)
	game.wildlife.frozen_for_capture = true
	await create_timer(1.65).timeout
	var c0: Vector3 = game.combat.zone_center(0)
	var p_norm: Vector3 = ground_foot(c0.x, c0.z + 6.8, 0.06)
	aim_player_exact(p_norm, Vector3(c0.x, p_norm.y + 1.45, c0.z - 1.5), 0)
	game.combat.engage_camp(0)
	# Let squad form natural Normal-mode single-attacker + 4-escort arc, or stage cleanly on ground if mid-transition
	for _f in 95:
		await physics_frame
	for idx in game.combat.troops[0].size():
		var s = game.combat.troops[0][idx]
		s.set_physics_process(false)
		var is_atk: bool = (s == game.combat.active_attacker)
		if is_atk:
			var atk_p := ground_foot(c0.x + 0.15, p_norm.z - 4.55, 0.02)
			s.position = atk_p
			s.action = Soldier.Action.AIM
			s.aim_left = 0.85
			s._update_laser(p_norm + Vector3(-0.35, 1.05, 0.0))
		else:
			var slot_off := float(idx - 2) * 0.40
			var esc_dir := Vector3(sin(slot_off), 0.0, -cos(slot_off))
			var esc_p := ground_foot(p_norm.x + esc_dir.x * 8.2, p_norm.z + esc_dir.z * 8.2, 0.02)
			s.position = esc_p
			s.action = Soldier.Action.ADVANCE
			s.laser_beam.hide()
		var to_pl: Vector3 = p_norm - s.position
		s.rotation.y = atan2(to_pl.x, to_pl.z)
	await wait_render(8)
	game._capture("02-normal-mode-single-attacker-escort.png")

	# 3. Confidential Operation ("机密行动 · 估值×1.35"): high-intensity multi-attacker encirclement!
	game._end_run(false)
	game.start_action(true, "confidential")
	game.landscape.set_low_quality(false)
	game.wildlife.frozen_for_capture = true
	game.rules.add_loot("烟山先民竹简", roundi(340.0 * 1.35), 5)
	game.rules.add_loot("烟霞岩画残拓", roundi(175.0 * 1.35), 4)
	await create_timer(1.65).timeout
	var c1: Vector3 = game.combat.zone_center(1)
	var p_conf: Vector3 = ground_foot(c1.x, c1.z + 6.2, 0.06)
	aim_player_exact(p_conf, Vector3(c1.x, p_conf.y + 1.48, c1.z - 1.0), 0)
	game.combat.engage_camp(1)
	for idx in game.combat.troops[1].size():
		var s = game.combat.troops[1][idx]
		s.set_physics_process(false)
		var ang := float(idx - 2) * 0.34
		var dist := 4.8 + float(idx % 2) * 0.65
		var sp := ground_foot(p_conf.x + sin(ang) * dist, p_conf.z - cos(ang) * dist, 0.02)
		s.position = sp
		var to_pl: Vector3 = p_conf - s.position
		s.rotation.y = atan2(to_pl.x, to_pl.z)
		if idx in [1, 2, 4]:
			s.action = Soldier.Action.AIM
			s.aim_left = 0.75
			s._update_laser(p_conf + Vector3(float(idx - 2) * 0.28 - 0.30, 0.98, 0.25))
		else:
			s.action = Soldier.Action.ADVANCE
	await wait_render(8)
	game._capture("03-confidential-mode-squad-assault.png")

	# 4. Yanxia Ancient Cavern West Wall: Frameless Stone-Chiseled Ancestral Petroglyph ("先民岩凿壁画《烟山耕读》")
	game._end_run(false)
	game.start_action(true, "normal")
	game.landscape.set_low_quality(false)
	game.wildlife.frozen_for_capture = true
	await create_timer(1.65).timeout
	aim_player_exact(Vector3(-40.82, 6.526, -60.90), Vector3(-44.90, 8.18, -61.15), 0)
	await create_timer(0.65).timeout
	await wait_render(8)
	game._capture("04-cave-chiseled-ancestral-petroglyph.png")

	# 5. Yanxia Ancient Cavern East Wall: Frameless Stone-Chiseled Chronicle ("石壁题志 ·《烟霞古洞志》")
	aim_player_exact(Vector3(-41.95, 6.526, -60.95), Vector3(-38.30, 8.12, -61.15), 0)
	await create_timer(0.55).timeout
	await wait_render(8)
	game._capture("05-cave-chiseled-chronicle-east.png")

	game.queue_free()
	await process_frame
	quit(0)
