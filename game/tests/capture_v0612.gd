extends SceneTree
## Captures 6 GPU-rendered 1280x720 screenshots & Standard-Quality (real-time shadows ON) FPS benchmark for v0.6.1.2:
## 1) Main menu v0.6.1.2 briefing (6 camps × 3 waves × 5 soldiers, 1-shot headshot / 2-shot word shield, 0-damage wrong-shot +25% buff);
## 2) Standby mountain camp garrison patrolling at spawn (non-aggro from afar) + 6-camp radar minimap + Standard-Quality FPS;
## 3) Active 5-soldier pursuing wave with 1st-shot cracked word shield (1/2) & live Chinese prompt;
## 4) Wrong-soldier deflection (0 HP/shield loss) + +25% wave enemy attack buff (×1.25);
## 5) Shooting a high-altitude flying White Egret in the sky with gold crit hitmarker & feather-light motes;
## 6) South fence & concave willow creek valley vista in Standard Quality (real-time shadows + canopy shade discs) at smooth high FPS.

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
	for i in frames:
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw

func aim_player_at(from_xz: Vector3, look_target: Vector3, y_offset: float = 0.12):
	var ground_pos: Vector3 = game.Layout.on_ground(Vector3(from_xz.x, 0.0, from_xz.z)) + Vector3(0.0, y_offset, 0.0)
	game.player.velocity = Vector3.ZERO
	game.player.position = ground_pos
	var eye_h: float = game.player.current_eye_y
	var d: Vector3 = look_target - (ground_pos + Vector3(0.0, eye_h, 0.0))
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.25, 1.25)

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(10)

	# Ensure Standard Quality (real-time shadows ON, NOT low-quality)
	game.landscape.set_low_quality(false)
	await wait_render(6)

	# 1. Main menu with v0.6.1.2 briefing
	game._refresh_menu("烟山基地 v0.6.1.2 · 词兵波次重塑与高帧率优化")
	await wait_render(6)
	game._capture("01-menu-v0612.png")

	# Start Combat Mode in Standard Quality (shadows ON) & run live multi-viewpoint GPU benchmark!
	game.start_action(true)
	game.landscape.set_low_quality(false)
	await wait_render(16)

	var bench_views := [
		{"name": "south_valley_vista", "from": Vector3(6.5, 0.0, 14.5), "look": Vector3(16.5, 1.5, 38.0)},
		{"name": "camp0_active_5bots", "from": game.combat.zone_center(0) + Vector3(0.0, 0.0, 9.5), "look": game.combat.zone_center(0) + Vector3(0.0, 1.2, -3.5)},
		{"name": "camp2_bamboo_boss", "from": game.combat.zone_center(2) + Vector3(0.0, 0.0, 11.0), "look": game.combat.zone_center(2) + Vector3(0.0, 1.4, -4.0)},
		{"name": "east_tea_ridge_camp4", "from": game.combat.zone_center(4) + Vector3(-9.5, 0.0, 10.5), "look": game.combat.zone_center(4) + Vector3(0.0, 1.2, -2.5)}
	]
	frame_samples_ms.clear()
	var per_view := {}
	for bv in bench_views:
		aim_player_at(bv.from, bv.look, 0.12)
		# Warm up shaders/pipelines at this camera frustum
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
		per_view[bv.name] = snappedf(1000.0 * float(local_ms.size()) / maxf(0.001, sum_local), 0.1)

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

	# Restart clean Combat Mode for crisp, deterministic gameplay screenshots
	game._end_run(false)
	game.start_action(true)
	game.landscape.set_low_quality(false)
	await wait_render(24)

	# 2. Standby Camp Garrison (Camp 0: 林间古道营地) from 18.8m away (> aggro 15.5m) + 6-camp radar minimap
	var c0: Vector3 = game.combat.zone_center(0)
	aim_player_at(c0 + Vector3(-1.4, 0.0, 18.8), c0 + Vector3(0.0, 1.25, -4.2), 0.16)
	await create_timer(1.15).timeout
	await wait_render(8)
	game._capture("02-six-camps-standby-radar.png")

	# 3. Active 5-Soldier Pursuing Wave + 1st-Shot Cracked Word Shield (1/2) on Correct Target
	aim_player_at(c0 + Vector3(0.0, 0.0, 7.6), c0 + Vector3(0.0, 1.22, -1.8), 0.12)
	await wait_render(8)
	if not game.combat.is_zone_engaged(0):
		game.combat.engage_camp(0)
	# Arrange the 5 pursuing soldiers in a clean, unobstructed fan facing the player, with the prompted target centered!
	var ans_slot: int = game.answer_index
	var fan_offsets := [
		Vector3(-4.1, 0.06, -2.5),
		Vector3(-2.05, 0.06, -1.55),
		Vector3(0.0, 0.06, -0.95),
		Vector3(2.05, 0.06, -1.55),
		Vector3(4.1, 0.06, -2.5)
	]
	var other_slots: Array[int] = []
	for si in 5:
		if si != ans_slot:
			other_slots.append(si)
	var ordered_slots: Array[int] = [other_slots[0], other_slots[1], ans_slot, other_slots[2], other_slots[3]]
	for fi in 5:
		var bot = game.combat.troops[0][ordered_slots[fi]]
		bot.set_physics_process(false)
		bot.laser_beam.hide()
		bot.position = game.Layout.on_ground(c0 + fan_offsets[fi]) + Vector3(0, 0.06, 0)
		var to_p: Vector3 = game.player.position - bot.position
		bot.rotation = Vector3(0.0, atan2(to_p.x, to_p.z), 0.0)
	await wait_render(4)
	var center_bot = game.combat.troops[0][ans_slot]
	aim_player_at(c0 + Vector3(0.0, 0.0, 7.2), center_bot.shield_area.global_position, 0.12)
	await wait_render(3)
	# Fire 1 real bullet at the correct soldier's word shield to crack it (1/2)!
	game.player.ammo = game.rules.magazine()
	game.fire(game.player.camera)
	await wait_render(2)
	game._capture("03-five-bot-pursuit-cracked-shield.png")

	# 4. Shooting a WRONG Soldier in the Wave -> 0 Damage + +25% Enemy Attack Power Stack (×1.25)!
	var wrong_bot = game.combat.troops[0][ordered_slots[1]]
	aim_player_at(c0 + Vector3(0.0, 0.0, 7.2), wrong_bot.shield_area.global_position, 0.12)
	await wait_render(3)
	game.player.ammo = game.rules.magazine()
	game.fire(game.player.camera)
	await wait_render(2)
	game._capture("04-wrong-hit-attack-buff.png")

	# 5. Shooting a High-Flying Sky Egret ("White Egret · 高空白鹭") with Real Bullet Raycast!
	game._end_run(false)
	game.start_action(false)
	game.landscape.set_low_quality(false)
	await wait_render(12)
	var sky_stand_xz := Vector3(11.5, 0.0, 18.0)
	var sky_stand_g: Vector3 = game.Layout.on_ground(sky_stand_xz)
	game.wildlife.frozen_for_capture = true
	if game.wildlife.sky_egrets.size() >= 2:
		var eg0: Dictionary = game.wildlife.sky_egrets[0]
		var eg1: Dictionary = game.wildlife.sky_egrets[1]
		(eg0.node as Node3D).position = sky_stand_g + Vector3(0.0, 6.2, -9.2)
		(eg0.node as Node3D).rotation = Vector3(0.0, deg_to_rad(48.0), 0.0)
		if eg0.anim != null:
			var ap0 := eg0.anim as AnimationPlayer
			ap0.play("Fly")
			ap0.seek(0.20, true)
			ap0.speed_scale = 0.0
		(eg1.node as Node3D).position = sky_stand_g + Vector3(-3.4, 7.6, -12.5)
		(eg1.node as Node3D).rotation = Vector3(0.0, deg_to_rad(38.0), 0.0)
		if eg1.anim != null:
			var ap1 := eg1.anim as AnimationPlayer
			ap1.play("Glide" if ap1.has_animation("Glide") else "Fly")
			ap1.seek(0.40, true)
			ap1.speed_scale = 0.0
		await wait_render(4)
		aim_player_at(sky_stand_xz, (eg0.area as Area3D).global_position, 0.12)
		await wait_render(3)
		game.player.ammo = game.rules.magazine()
		game.fire(game.player.camera)
		await wait_render(2)
	game._capture("05-sky-egret-shot-feathers.png")
	game.wildlife.frozen_for_capture = false

	# 6. South Fence & Willow Creek Valley Panorama in Standard Quality (Shadows ON + Canopy Shade Discs + High FPS)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	game.hitmarker_left = 0.0
	game.hitmarker_label.hide()
	aim_player_at(Vector3(15.2, 0.0, 22.0), Vector3(22.0, game.terrain_height(22.0, 48.0) + 1.4, 48.0), 0.18)
	await create_timer(1.15).timeout
	await wait_render(10)
	game._capture("06-valley-vista-standard-fps.png")

	game.queue_free()
	await process_frame
	print("PASS capture_v0612 completed all 6 screenshots and standard FPS benchmark")
	quit(0)
