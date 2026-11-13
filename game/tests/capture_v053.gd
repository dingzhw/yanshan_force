extends SceneTree
## Captures 7 real GPU-rendered 1280x720 screenshots of v0.5.3 features for pixel-level QA inspection.

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
	var eye = from_pos + Vector3(0, 1.58, 0)
	var d = look_target - eye
	game.player.yaw = atan2(-d.x, -d.z)
	game.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())

func run():
	seed(20261115)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(6)

	game.rules.profile.coins = 1280
	game.rules.profile.xp = 420
	game.rules.profile.points = 3
	game.rules.profile.owned = ["magazine", "magazine2", "scope_2x", "suppressor", "compensator", "angled_grip", "tactical_rig", "tactical_belt", "forest_skin", "shield_core"]
	game.rules.profile.equipped = {"optic": "scope_2x", "muzzle": "suppressor", "grip": "angled_grip"}
	game.rules.profile.warehouse = [
		{"title": "加密战术主板", "value": 95, "rarity": 3},
		{"title": "精密电台晶体", "value": 160, "rarity": 4}
	]
	game.rules.profile.collection = ["烟山统领黄金核心", "量子词典原型机", "烟山古铜虎符"]
	for i in 28:
		game.rules.profile.mastery[game.words[i].id] = {"seen": 3, "correct": 3, "wrong": 0, "spelled": 1}

	# 1. Gunsmith 2.0 3x5 Menu UI
	game._refresh_menu("烟山基地 v0.5.3 · 武器改装与战术出击")
	await wait_render(6)
	game._capture("v053-menu-gunsmith.png")

	# 2. Modded YS-04 Carbine (scope_2x + suppressor + angled_grip + forest_skin) + tactical pickups & updated HUD
	game.start_action(true)
	game.rules.add_loot("加密战术主板", 95, 3)
	aim_player_at(game.Layout.on_ground(Vector3(6.2, 0, 14.2)) + Vector3(0, 0.15, 0), game.Layout.on_ground(Vector3(6.9, 0, 10.6)) + Vector3(0, 0.35, 0))
	game._update_interaction()
	await wait_render(12)
	game._capture("v053-rifle-modded.png")

	# 3. 2x Tactical Scope ADS Sight Picture at Outpost Zone 1
	game.rules.score = 195
	game.rules.correct = 13
	game.rules.answered = 14
	game.rules.streak = 3
	var center1 = game.combat.zone_center(1)
	aim_player_at(center1 + Vector3(0.4, 0.12, 6.2), center1 + Vector3(0.0, 1.55, -2.5))
	game.player.aiming = true
	await wait_render(24)
	game._capture("v053-rifle-ads.png")
	game.player.aiming = false
	await wait_render(8)

	# 4. Held Tactical Knife [2] Idle View
	game.player.select_weapon(1)
	aim_player_at(game.Layout.on_ground(Vector3(-2.0, 0, -18.0)) + Vector3(0, 0.15, 0), game.Layout.on_ground(Vector3(-4.0, 0, -28.0)) + Vector3(0, 1.5, 0))
	await wait_render(14)
	game._capture("v053-knife-idle.png")

	# 5. Held Tactical Knife Mid-Slash View (hold right at peak sweep sin=1.0 for frame capture)
	game.player.weapon_view.trigger_knife_slash(0)
	game.player.weapon_view.slash_left = game.player.weapon_view.slash_duration * 0.50
	game.player.weapon_view.animate(0.0, 0.0, 0.0, false)
	await RenderingServer.frame_post_draw
	game._capture("v053-knife-slash.png")

	# 6. External Close-Up Inspection of Hand.R Gripping Tactical Knife
	game.player.weapon_view.slash_left = 0.0
	await wait_render(10)
	game.hud.hide()
	var knife_cam := Camera3D.new()
	knife_cam.fov = 38.0
	knife_cam.near = 0.02
	game.player.weapon_view.add_child(knife_cam)
	var k_target: Vector3 = game.player.weapon_view.knife_root.global_position
	knife_cam.global_position = k_target + (game.player.weapon_view.global_basis.x * -0.22) + (game.player.weapon_view.global_basis.y * 0.14) + (game.player.weapon_view.global_basis.z * -0.22)
	knife_cam.look_at(k_target, Vector3.UP)
	knife_cam.current = true
	await wait_render(4)
	game._capture("v053-knife-grip-closeup.png")
	game.player.camera.current = true
	knife_cam.queue_free()
	game.hud.show()

	# 7. Zone-B Heavy Boss「铁甲词尊 · 烟山统领」+ Exposed Core + Smoke/EMP + Danger Ring
	game.player.select_weapon(0)
	var center2 = game.combat.zone_center(2)
	aim_player_at(center2 + Vector3(0.0, 0.15, 6.8), center2 + Vector3(0.0, 1.72, -1.6))
	await wait_render(6)
	var boss = game.combat.boss_unit
	if is_instance_valid(boss):
		boss.position = game.Layout.on_ground(center2 + Vector3(0.0, 0, -1.6))
		boss.look_at(Vector3(game.player.position.x, boss.position.y, game.player.position.z), Vector3.UP)
		boss.rotate_y(PI)
		boss.hp = 260
		boss.expose_boss_core(4.0)
	game.combat.deploy_smoke_emp(center2 + Vector3(-2.8, 0, 0.6))
	game.combat.spawn_danger_ring(center2 + Vector3(1.8, 0, 1.8), 3.1, 24)
	game._sync_question()
	await wait_render(8)
	game._capture("v053-boss-smoke-combat.png")

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("PASS capture_v053 completed all 7 screenshots")
	quit(0)
