extends SceneTree
## Captures 6 real GPU-rendered 1280x720 screenshots of v0.5.1 for visual QA inspection.

var game

func _initialize():
	call_deferred("run")

func wait_render(frames = 4):
	for i in frames:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw

func aim_player_at(from_pos: Vector3, look_target: Vector3):
	game.player.position = from_pos
	var eye = from_pos + Vector3(0, 1.62, 0)
	var d = look_target - eye
	game.player.yaw = atan2(-d.x, -d.z)
	game.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())

func run():
	seed(20261113)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(6)

	game.rules.profile.coins = 560
	game.rules.profile.xp = 290
	game.rules.profile.points = 2
	game.rules.profile.owned = ["magazine", "red_dot"]
	game.rules.profile.collection = ["量子词典原型机", "烟山古铜虎符"]
	for i in 22:
		game.rules.profile.mastery[game.words[i].id] = {"seen": 3, "correct": 3, "wrong": 0, "spelled": 1}

	# 1. Camp A: Realistic Command Tent + Fuel Drums + Armory Workbench + Keypad Supply Box + First-Person Tactical Arms
	game.start_action(true)
	game.rules.add_loot("战术医疗电芯", 42, 2)
	game.rules.add_loot("加密无线电台", 82, 3)
	aim_player_at(game.Layout.on_ground(Vector3(4.8, 0, 5.6)) + Vector3(0, 0.15, 0), game.Layout.on_ground(Vector3(9.4, 0, 10.0)) + Vector3(0, 1.15, 0))
	game._update_interaction()
	await wait_render(10)
	game._capture("v051-camp-tent-arms.png")

	# 2. Mid-Reload Pose: Left gloved hand gripping & pulling YS04_magazine
	game.player.ammo = 3
	game.player.reload()
	await wait_render(30)
	game._capture("v051-reload.png")
	while game.player.reload_left > 0:
		await physics_frame
		await process_frame

	# 3. ADS Sight Picture at Outpost Zone 1 (verifying zero sightline obstruction + upgraded metallic Scout Drone)
	game.rules.score = 210
	game.rules.correct = 14
	game.rules.answered = 15
	game.rules.streak = 4
	var center1 = game.combat.zone_center(1)
	aim_player_at(center1 + Vector3(0.5, 0.12, 6.4), center1 + Vector3(0.0, 1.55, -1.5))
	game.player.aiming = true
	await wait_render(24)
	game._capture("v051-arms-ads.png")
	game.player.aiming = false
	await wait_render(8)

	# 4. Tier-3 Gold Airdrop Vault Pod in the field with 3-stage interaction prompt
	var pod = game.crate_nodes[2]
	aim_player_at(pod.position + Vector3(0.85, 0.12, 2.55), pod.position + Vector3(0, 1.15, 0))
	game._update_interaction()
	await wait_render(8)
	game._capture("v051-airdrop-pod.png")

	# 5. Tier-3 Multi-Stage Cipher Terminal on Stage 3 (Full Grade 5A Sentence Challenge)
	game.cipher_terminal.open_for_crate(pod)
	await wait_render(3)
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	await wait_render(2)
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	await wait_render(4)
	game._capture("v051-cipher-sentence.png")

	# 6. Unlocked Tier-3 Loot Cards + Full-Bag Lowest-Item Swap UI
	while game.rules.bag.size() < game.rules.capacity():
		game.rules.add_loot("野战压缩口粮", 20, 1)
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	await wait_render(4)
	game._capture("v051-cipher-loot.png")
	game.cipher_terminal.close()

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("PASS capture_v051 completed all 6 screenshots")
	quit(0)
