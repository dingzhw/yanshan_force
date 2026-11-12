extends SceneTree
## Captures 6 real GPU-rendered 1280x720 screenshots of v0.5.2 sculpted tactical arms for visual QA inspection.

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
	seed(20261114)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(6)

	print("ARMS_SKEL_BONES=", game.player.weapon_view.arms_skeleton.get_bone_count() if is_instance_valid(game.player.weapon_view.arms_skeleton) else -1)
	print("ARMS_POSES=", game.player.weapon_view.pose_cache.keys())

	game.rules.profile.coins = 620
	game.rules.profile.xp = 310
	game.rules.profile.points = 2
	game.rules.profile.owned = ["magazine", "red_dot"]
	game.rules.profile.collection = ["量子词典原型机", "烟山古铜虎符"]
	for i in 22:
		game.rules.profile.mastery[game.words[i].id] = {"seen": 3, "correct": 3, "wrong": 0, "spelled": 1}

	# 1. Camp A Hip-Fire: Standard Olive-Drab Ripstop Sleeve + Sculpted Half-Finger Tactical Gloves + Watch
	game.start_action(true)
	game.rules.add_loot("战术医疗电芯", 42, 2)
	game.rules.add_loot("加密无线电台", 82, 3)
	aim_player_at(game.Layout.on_ground(Vector3(6.2, 0, 6.2)) + Vector3(0, 0.15, 0), game.Layout.on_ground(Vector3(9.6, 0, 10.2)) + Vector3(0, 1.35, 0))
	game._update_interaction()
	await wait_render(12)
	game._capture("v052-hip-fire.png")

	# 2. Mid-Reload Pose: Sculpted Left Hand Gripping & Pulling YS04_magazine
	game.player.ammo = 3
	game.player.reload()
	await wait_render(34)
	game._capture("v052-reload-mag.png")
	while game.player.reload_left > 0:
		await physics_frame
		await process_frame

	# 3. ADS Sight Picture at Outpost Zone 1 (verifying thumb-forward grip & 0% sightline obstruction)
	game.rules.score = 210
	game.rules.correct = 14
	game.rules.answered = 15
	game.rules.streak = 4
	var center1 = game.combat.zone_center(1)
	aim_player_at(center1 + Vector3(0.5, 0.12, 6.4), center1 + Vector3(0.0, 1.55, -1.5))
	game.player.aiming = true
	await wait_render(24)
	game._capture("v052-ads-sight.png")
	game.player.aiming = false
	await wait_render(8)

	# 4. Forest Camo Skin ("forest_skin") Deployment: Woodland Camo Sleeves + Anodized Carbine
	game._end_run(false)
	game.rules.profile.owned.append("forest_skin")
	game.start_action(true)
	aim_player_at(game.Layout.on_ground(Vector3(-4.5, 0, -8.0)) + Vector3(0, 0.15, 0), game.Layout.on_ground(Vector3(-12.0, 0, -18.0)) + Vector3(0, 1.5, 0))
	await wait_render(12)
	game._capture("v052-forest-skin.png")

	# 5 & 6. External Close-Up Inspection Camera of Both Sculpted Hands Wrapping YS-04
	game.hud.hide()
	var inspect_cam := Camera3D.new()
	inspect_cam.fov = 42.0
	inspect_cam.near = 0.03
	game.player.weapon_view.add_child(inspect_cam)

	# Left-front 3/4 view showing both hands, pistol grip trigger finger, forend C-clamp & telemetry watch
	inspect_cam.position = Vector3(-0.32, 0.24, -0.02)
	inspect_cam.look_at(game.player.weapon_view.to_global(Vector3(0.0, 0.11, -0.02)), Vector3.UP)
	inspect_cam.current = true
	await wait_render(4)
	game._capture("v052-inspect-left.png")

	# Right-side 3/4 view showing right hand palm/knuckle armor, trigger finger on trigger, and curled forend fingers
	inspect_cam.position = Vector3(0.32, 0.20, 0.04)
	inspect_cam.look_at(game.player.weapon_view.to_global(Vector3(0.0, 0.10, 0.02)), Vector3.UP)
	await wait_render(4)
	game._capture("v052-inspect-right.png")

	game.player.camera.current = true
	inspect_cam.queue_free()
	game.hud.show()

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("PASS capture_v052 completed all 6 screenshots")
	quit(0)
