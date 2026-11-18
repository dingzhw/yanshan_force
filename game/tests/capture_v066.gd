extends SceneTree
## v0.6.6 GPU Screenshot & Tactical Cover AI Verification ('智战烟山 · 谨慎掩体战术AI + 随机兵力 + 30秒休整')

const Soldier = preload("res://scripts/word_soldier.gd")
var game

func _initialize():
	run()

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

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(2026066)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(12)

	# Shot 01: Menu v0.6.6
	game._capture("01-menu-v066.png")

	# Start Normal Operation (3-4 cautious cover-seeking soldiers)
	game.start_action(true, "normal")
	await wait_render(14)
	game.wildlife.frozen_for_capture = true

	# Shot 02: Normal Operation — 3-4 soldiers holding behind 7 castellated Hui parapets & side-peeking shields!
	var c0: Vector3 = game.combat.zone_center(0)
	aim_player_exact(ground_foot(c0.x + 0.6, c0.z + 4.8, 0.08), c0 + Vector3(0.0, 1.25, -6.5))
	game.player.weapon_root.position = Vector3(0.21, -0.245, -0.58)
	game.combat.engage_camp(0)
	for _t in 75:
		await physics_frame
	game.combat.health = 100
	game.combat.shield = game.rules.max_shield()
	await wait_render(6)
	game._capture("02-normal-cautious-cover-combat.png")

	# Shot 03: Shield-Cracked Soldier Bounding Between Covers + Firing Moving Suppression Tracer!
	var target_s = game.combat.troops[0][game.answer_index]
	target_s.crack_shield_once()
	target_s.stun_left = 0.0
	for _t2 in 14:
		await physics_frame
	game.combat.suppress_lock = 0.0
	game.combat.try_moving_suppression(target_s)
	game.combat.health = 100
	game.combat.shield = game.rules.max_shield()
	await wait_render(2)
	game._capture("03-cracked-shield-bounding-fire.png")

	# Shot 04: Wiped Wave -> 15s Empty Camp Countdown + 15s Truce (= 30s Breathing Window) + Loot Drop!
	game.combat.last_kill_pos = c0 + Vector3(-0.4, 0.0, -1.6)
	for s0 in game.combat.troops[0]:
		if is_instance_valid(s0):
			s0.defeated = true
	game.combat._complete_current_wave(0)
	aim_player_exact(ground_foot(c0.x + 0.8, c0.z + 5.2, 0.08), c0 + Vector3(0.0, 0.95, -3.5))
	await wait_render(8)
	game._capture("04-thirty-sec-rest-window.png")

	# Shot 05: Confidential Operation — Larger Random Squad (up to 6) Bounding Overwatch!
	game.confidential_button.pressed.emit()
	await wait_render(10)
	game.combat.shot_rng.seed = 9
	# Ensure a juicy 5-6 bot Confidential squad at Camp 1 for showcase
	var c1: Vector3 = game.combat.zone_center(1)
	aim_player_exact(ground_foot(c1.x - 3.4, c1.z + 6.8, 0.08), c1 + Vector3(0.4, 1.35, -6.5))
	game.player.weapon_root.position = Vector3(0.21, -0.245, -0.58)
	game.combat.engage_camp(1)
	for _t3 in 55:
		await physics_frame
	if not game.combat.troops[1].is_empty():
		game.combat.suppress_lock = 0.0
		game.combat.try_moving_suppression(game.combat.troops[1][0])
	game.combat.health = 100
	game.combat.shield = game.rules.max_shield()
	await wait_render(2)
	game._capture("05-confidential-bounding-overwatch.png")

	game.queue_free()
	await process_frame
	quit(0)
