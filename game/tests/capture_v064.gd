extends SceneTree
## Captures GPU-rendered 1280x720 screenshots & Standard-Quality FPS benchmark for v0.6.4 ('青绿烟山 · 美术、建模与动作重塑'):
## 1) 01-menu-v064.png: Camp menu v0.6.4 with Qinglü aesthetic briefing;
## 2) 02-knife-cqb-dual-hand-idle.png: [2] Dual-Hand Martial CQB Knife Stance (both gloved hands + cord-wrapped Qinglü blade, zero floating stump);
## 3) 03-knife-slash-cleave-blade-arc.png: Mid-slash diagonal cleave with Celadon-Gold crescent blade arc & seamless lower-right sleeve entry;
## 4) 04-ys04-carbine-qinglu-valley-vista.png: 5-surface Qinglü YS-04 Carbine overlooking Weeping Willows, Camphors & Autumn Tallow/Maples;
## 5) 05-qinglu-camphor-shrine-sculpted-props.png: Ancient Camphor + Sculpted Sumidero Stone Pedestal + Woven-Twig Bird Nest;
## 6) 06-qinglu-bamboo-forest-and-maple.png: Calligraphic Moso Bamboo plumes + Cinnabar/Ochre Tallow Maple contrast;
## 7) 07-stylized-qinglu-word-soldiers.png: Stylized Qinglü-Mecha Word Soldiers with sloped eave pauldrons, octagonal helms & bronze shield brackets.

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

	# 1. Camp Menu v0.6.4
	game._refresh_menu("烟山基地 v0.6.4 · 青绿烟山美术与第一人称动作重塑")
	await wait_render(8)
	game._capture("01-menu-v064.png")

	# Start Normal Operation & run Standard-Quality GPU FPS benchmark!
	game.start_action(true, "normal")
	game.landscape.set_low_quality(false)
	await wait_render(18)

	var bench_views := [
		{"name": "qinglu_south_valley_vista", "foot": ground_foot(6.5, 14.5, 0.12), "look": Vector3(16.5, 2.2, 38.0)},
		{"name": "qinglu_camphor_and_maple_slope", "foot": ground_foot(8.5, -9.5, 0.10), "look": Vector3(14.0, 4.2, -22.0)},
		{"name": "bamboo_maze_south_gate", "foot": ground_foot(-40.8, -32.4, 0.10), "look": Vector3(-41.6, 8.0, -38.0)},
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
	var bench_json := JSON.stringify({
		"gpu": RenderingServer.get_video_adapter_name(),
		"low_quality": game.landscape.low_quality,
		"frames": sorted_ms.size(),
		"average_fps": snappedf(avg_fps, 0.1),
		"p95_frame_ms": snappedf(p95_ms, 0.2),
		"per_view_fps": per_view
	})
	print("CAPTURE_V064_BENCH=", bench_json)

	# Reset clean state for crisp visual captures
	game.wildlife.frozen_for_capture = true
	game.combat.health = 100
	game.combat.shield = game.rules.max_shield()
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await create_timer(1.15).timeout

	# 4. Multi-Surface YS-04 Qinglü Carbine overlooking Creek Willows, Rice Valley & Misty Mountains!
	game.player.select_weapon(0)
	aim_player_exact(ground_foot(6.5, 14.8, 0.08), Vector3(17.5, 2.2, 38.0), 0)
	game.player.weapon_root.position = Vector3(0.21, -0.245, -0.58)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("04-ys04-carbine-qinglu-valley-vista.png")

	# 2. [2] Dual-Hand Martial CQB Knife Ready Stance (Both Gloved Hands + Watch + '竹影青锋' Blade!)
	game.player.select_weapon(1)
	aim_player_exact(ground_foot(13.2, -6.2, 0.08), Vector3(17.5, 4.2, -21.0), 0)
	game.player.weapon_root.position = Vector3(0.0, -0.145, -0.35)
	game.player.weapon_view.slash_left = 0.0
	game.player.weapon_view.animate(0.0, 0.0, 0.0, false)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("02-knife-cqb-dual-hand-idle.png")

	# 3. Mid-Slash Diagonal Cleave with Celadon-Gold Crescent Blade Arc (Zero Severed Arm Stump!)
	await create_timer(1.08).timeout
	game.player.set_physics_process(false)
	game.player.weapon_root.position = Vector3(0.0, -0.145, -0.35)
	game.player.weapon_view.trigger_knife_slash(0)
	game.player.weapon_view.slash_left = game.player.weapon_view.slash_duration * 0.56  # raw_t = 0.44 mid-cleave + full crescent ribbon!
	game.player.weapon_view.animate(0.0, 0.0, 0.0, false)
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	game._capture("03-knife-slash-cleave-blade-arc.png")
	game.player.weapon_view.slash_left = 0.0
	game.player.set_physics_process(true)
	game.player.select_weapon(0)
	await wait_render(6)

	# 5. Sculpted Octagonal Sumidero Stone Pedestal + Woven-Twig Bird Nest + Ancient Camphor Canopy!
	game.wildlife.visible = false
	var shrine_ped: Node3D = game.world_loot.loose_nodes[1]
	shrine_ped.position = game.Layout.on_ground(Vector3(9.45, 0.0, -14.0))
	shrine_ped.visible = true
	var celadon_item := {
		"title": "越窑秘色青瓷盏",
		"en": "Yue Secret Celadon Bowl",
		"value": 742,
		"rarity": 6,
		"cond": "崭新",
		"grid": "2×2",
		"icon": "celadon",
		"lore": "九秋风露越窑开，夺得千峰翠色来。"
	}
	shrine_ped.set_meta("loot_item", celadon_item)
	var holder: Node3D = shrine_ped.get_node("RelicHolder")
	for ch in holder.get_children():
		ch.queue_free()
	game.world_loot._populate_loose_visual(holder, celadon_item)
	game.cached_interactables.clear()
	var ped_p: Vector3 = shrine_ped.global_position
	aim_player_exact(ground_foot(9.32, -10.45, 0.06), Vector3(8.62, ped_p.y + 0.44, -13.95), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("05-qinglu-camphor-shrine-sculpted-props.png")
	game.wildlife.visible = true

	# 6. Calligraphic Moso Bamboo Plumes & Autumn Cinnabar/Ochre Tallow Maple Grove!
	aim_player_exact(ground_foot(17.2, -2.8, 0.08), Vector3(24.0, 5.6, -13.2), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("06-qinglu-bamboo-forest-and-maple.png")

	# 7. Stylized Qinglü-Mecha Word Soldiers (Sloped Eave Pauldrons, Octagonal Helms & Bronze Shield Brackets)
	var c0: Vector3 = game.combat.zone_center(0)
	var p_norm: Vector3 = ground_foot(c0.x, c0.z + 6.4, 0.06)
	aim_player_exact(p_norm, Vector3(c0.x, p_norm.y + 1.42, c0.z - 1.2), 0)
	game.combat.engage_camp(0)
	for idx in game.combat.troops[0].size():
		var s = game.combat.troops[0][idx]
		s.set_physics_process(false)
		var is_atk: bool = (idx == 2)
		if is_atk:
			s.position = ground_foot(c0.x + 0.10, p_norm.z - 4.35, 0.02)
			s.action = Soldier.Action.AIM
			s.aim_left = 0.80
			s._update_laser(p_norm + Vector3(-0.32, 1.02, 0.0))
		else:
			var slot_off := float(idx - 2) * 0.42
			var esc_dir := Vector3(sin(slot_off), 0.0, -cos(slot_off))
			s.position = ground_foot(p_norm.x + esc_dir.x * 7.8, p_norm.z + esc_dir.z * 7.8, 0.02)
			s.action = Soldier.Action.ADVANCE
			s.laser_beam.hide()
		var to_pl: Vector3 = p_norm - s.position
		s.rotation.y = atan2(to_pl.x, to_pl.z)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("07-stylized-qinglu-word-soldiers.png")

	game.queue_free()
	await process_frame
	quit(0)
