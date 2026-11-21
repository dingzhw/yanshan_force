extends SceneTree

var game

func _initialize():
	call_deferred("run")

func _wait_render(frames_n: int = 5):
	for i in frames_n:
		await physics_frame
	for j in 3:
		await process_frame
	await RenderingServer.frame_post_draw

func _aim_player_at(from_pos: Vector3, target_pos: Vector3):
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.position = from_pos
	var eye := from_pos + Vector3(0.0, 1.58, 0.0)
	var d := target_pos - eye
	game.player.yaw = atan2(-d.x, -d.z)
	game.player.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.15, 1.15)
	game.player.rotation.y = game.player.yaw
	game.player.camera.rotation.x = game.player.pitch

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await _wait_render(5)

	# 1) FB-4 Clean Camp A vista (no legacy 4 idle placeholder target boards!)
	game.start_action(false)
	await _wait_render(4)
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	_aim_player_at(game.Layout.on_ground(Vector3(0.0, 0.0, 4.5)) + Vector3(0, 0.05, 0), Vector3(0.0, 1.8, -12.0))
	await _wait_render(5)
	game._capture("03-camp-clean-no-idle-signs-v081.png")

	# 2) FB-1 Elevated East Ridge Wangdao Pavilion Scenic Overlook Vista (looking south-southwest over terraced paddies & cottages!)
	var wd_balc: Vector3 = game.landscape.wangdao_deck_pos
	_aim_player_at(wd_balc + Vector3(0.0, 0.05, -0.35), Vector3(14.0, -7.5, 92.0))
	game.hud.hide()
	await _wait_render(6)
	game._capture("01-wangdao-overlook-vista-v081.png")

	# 3) FB-2 & FB-3 Close-up of Crisp Carved Bluestone Flagstones + Mountain Granite Rock along trail
	# Trail boulder at (-22, 0, -18) and main bluestone trail near (-18, 0, -27) / Wangdao stone stairs (29.8, 19.0)
	var rock_trail_from: Vector3 = game.Layout.on_ground(Vector3(-18.6, 0.0, -20.8)) + Vector3(0, 0.05, 0)
	var rock_trail_look: Vector3 = game.Layout.on_ground(Vector3(-21.6, 0.0, -18.2)) + Vector3(0, 0.65, 0)
	_aim_player_at(rock_trail_from, rock_trail_look)
	await _wait_render(6)
	game._capture("02-rock-and-flagstone-closeup-v081.png")

	# 4) FB-6 Valley-Spanning Fortified Math Shortcut Timber Stockade + Central Lockable Wooden Gate
	var gate_look: Vector3 = game.Layout.on_ground(Vector3(10.0, 0.0, -62.0)) + Vector3(0.0, 1.45, 0.0)
	var gate_from: Vector3 = game.Layout.on_ground(Vector3(8.5, 0.0, -52.5)) + Vector3(0.0, 0.10, 0.0)
	_aim_player_at(gate_from, gate_look)
	await _wait_render(6)
	game._capture("04-math-stockade-fence-gate-v081.png")

	# 5) #3 & #4 Distant Word Sniping HUD Preview (aiming at Camp 0 from ~25m away with unobstructed line of sight!)
	game.hud.show()
	game.start_action(true, "normal")
	await _wait_render(5)
	var c0: Vector3 = game.combat.zone_center(0)
	var s0 = game.combat.troops[0][0]
	var snipe_from: Vector3 = game.Layout.on_ground(c0 + Vector3(-2.8, 0.0, 22.0)) + Vector3(0.0, 0.08, 0.0)
	_aim_player_at(snipe_from, s0.shield_area.global_position)
	game.player.aiming = true
	await _wait_render(6)
	game._capture("05-sniper-distant-camp-hud-v081.png")

	# 6) #8 Confidential 3-Wrong Rage Hunt (4.0x Crimson Banner!)
	game.player.aiming = false
	game.start_action(true, "confidential")
	await _wait_render(4)
	_aim_player_at(game.Layout.on_ground(c0 + Vector3(0.0, 0.0, 14.0)) + Vector3(0, 0.08, 0), c0 + Vector3(0, 1.5, -5.0))
	await _wait_render(4)
	for rw in 3:
		var cw_opt: int = (int(game.combat.zone_prompt_option.get(0, 0)) + 1) % game.combat.troops[0].size()
		var cw_s = game.combat.troops[0][cw_opt]
		game.combat.hit_bullet(cw_s.shield_area, "", cw_s.shield_area.global_position)
		if rw < 2:
			game.combat.update(1.55)
	await _wait_render(5)
	game._capture("06-rage-hunt-hud-v081.png")

	# 7) FB-5 Single-Attempt Field Intel Lock Overlay (showing wrong-answer lock + correct answer + disabled retry buttons)
	var ic_node: Node3D = null
	for n in game.exploration.nodes:
		if n.get_meta("explore_id") == "intel_container":
			ic_node = n
			break
	if ic_node != null:
		game.exploration.open(ic_node)
		var ans_i: int = game.exploration.answer_button_index("intel_container")
		game.exploration.buttons[(ans_i + 1) % 3].pressed.emit()
		await _wait_render(4)
		game._capture("07-intel-single-attempt-lock-v081.png")
		game.exploration.close()

	game.queue_free()
	await process_frame
	print("CAPTURE_V081_DONE")
	quit(0)
