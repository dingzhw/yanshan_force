extends SceneTree
## Captures 5 real GPU-rendered 1280x720 screenshots of v0.5.0 for visual QA inspection.

var game

func _initialize():
	call_deferred("run")

func wait_render(frames = 4):
	for i in frames:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw

func run():
	seed(20261112)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(6)

	# 1. Camp Menu with 9-item shop & mastery/collection progress
	game.rules.profile.coins = 520
	game.rules.profile.xp = 275
	game.rules.profile.points = 2
	game.rules.profile.owned = ["magazine", "red_dot"]
	game.rules.profile.collection = ["量子词典原型机", "烟山古铜虎符"]
	game.rules.profile.warehouse = [
		{"title": "量子词典原型机", "value": 320, "rarity": 5},
		{"title": "无人机核心芯片", "value": 145, "rarity": 4}
	]
	for i in 18:
		game.rules.profile.mastery[game.words[i].id] = {"seen": 3, "correct": 3, "wrong": 0, "spelled": 1}
	game._refresh_menu()
	await wait_render(4)
	game._capture("v050-menu.png")

	# 2. Combat HUD + 3 Enemy Archetypes (Assault Bot, Scout Drone, Sniper Guard) + Rarity Loot Pills
	game.start_action(true)
	game.rules.add_loot("加密无线电台", 82, 3)
	game.rules.add_loot("无人机核心芯片", 145, 4)
	game.rules.add_loot("量子词典原型机", 320, 5)
	game.rules.score = 195
	game.rules.correct = 13
	game.rules.answered = 14
	game.rules.streak = 4
	var center1 = game.combat.zone_center(1)
	game.player.position = center1 + Vector3(0.4, 0.12, 6.2)
	game.player.yaw = 0.04
	game.player.pitch = -0.05
	await wait_render(18)
	game._capture("v050-combat.png")

	# 3. Tactical Reflex Optic ADS View (checking zero green cylinder arms & aligned red/cyan dot)
	game.player.aiming = true
	for i in 24:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	game._capture("v050-aim.png")
	game.player.aiming = false

	# 4. Grounded Boulders, Textured Timber Shelter & Bamboo Stronghold
	game.player.position = game.Layout.on_ground(Vector3(14.5, 0, -79.5)) + Vector3(0, 0.12, 0)
	game.player.yaw = 0.22
	game.player.pitch = -0.06
	await wait_render(12)
	game._capture("v050-bamboo.png")

	# 5. Password Crate Spelling Terminal + Unlocked Rarity Loot Cards
	game.cipher_terminal.open_for_crate(game.crate_nodes[2])
	await wait_render(3)
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	await wait_render(4)
	game._capture("v050-cipher.png")
	game.cipher_terminal.close()

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit(0)
