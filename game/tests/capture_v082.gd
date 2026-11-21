extends SceneTree
## v0.8.2 Real 1280x720 Visual Verification Suite (8 high-value shots covering all 15 v0.8.2 features & fixes).

var game

func _initialize():
	call_deferred("run")

func frames(n: int):
	for _i in n:
		await process_frame
		await physics_frame

func run():
	var out_dir := OS.get_environment("DRZ_SCREENSHOT_DIR")
	if out_dir == "":
		out_dir = "user://v082_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await frames(8)
	game.rules.profile.review_due.clear()
	game.rules.profile.owned.append_array(["scope_2x", "suppressor", "angled_grip", "forest_skin"])
	game.rules.equip_attachment("optic", "scope_2x")
	game.rules.equip_attachment("muzzle", "suppressor")
	game.rules.equip_attachment("grip", "angled_grip")
	game.achievements.record_wildlife_kill("boar")
	for _sq in 10:
		game.achievements.record_wildlife_kill("squirrel")
	game.achievements.equip_charm("charm_roast")

	# 1) Wangdao Overlook terrace seam (V81-1 zero Z-fighting) + panoramic golden rice paddies & solid horizon mountains (V81-8)
	game.start_action(false)
	await frames(6)
	game.achievements.banner_panel.hide()
	game.achievements.banner_queue.clear()
	game.achievements.banner_active = {}
	var pav_y := float(game.terrain_height(35.2, 22.4)) + 2.75
	game.player.position = Vector3(33.9, pav_y + 0.08, 25.25)
	game.player.yaw = -2.75
	game.player.pitch = -0.35
	await frames(6)
	game._capture("v082_wangdao_clean.png")

	# 2) Solid opaque 4-layer Jiangnan horizon mountains from south ridge (V81-8 zero ghost mountains!)
	game.player.position = game.Layout.on_ground(Vector3(-8.0, 0.0, 21.0)) + Vector3(0.0, 0.12, 0.0)
	game.player.yaw = PI
	game.player.pitch = 0.06
	await frames(6)
	game._capture("v082_slope_clean_horizon.png")

	# 3) Yanxia Ancient Cave looking UP at the real open Karst Skylight hole into real blue sky (V81-5)
	game.player.position = Vector3(-40.8, 6.55, -66.1)
	game.player.yaw = 0.65
	game.player.pitch = 0.72
	await frames(6)
	game._capture("v082_cave_skylight.png")

	# 4) Yanxia Cave Mural modal with zero text/button overlap (V81-4)
	var mural_node = null
	for n in game.exploration.nodes:
		if n.get_meta("explore_id", "") == "cave_mural":
			mural_node = n
			break
	if mural_node != null:
		game.exploration.open(mural_node)
		await frames(4)
		game._capture("v082_cave_mural_ui.png")
		game.exploration.close()
		await frames(4)

	# 5) Mid-reload YS-04 carbine: 2x scope rigidly locked to rail (V81-9) + dangling 3D charm + Achievement unlock banner (V81-10)
	game.player.position = game.Layout.on_ground(Vector3(-4.0, 0.0, -4.0)) + Vector3(0.0, 0.12, 0.0)
	game.player.yaw = 0.0
	game.player.pitch = -0.05
	game.rules.profile["equipped_charm"] = "charm_fox_bell"
	game.player.select_weapon(0)
	game.player.weapon_view.refresh_loadout()
	game.player.ammo = 4
	game.player.reload()
	game.player.reload_left = game.player.RELOAD_SECONDS * 0.52
	var unlocked_ach: Array = game.rules.profile.get("achievements", [])
	unlocked_ach.erase("fox_1")
	game.achievements.banner_queue.clear()
	game.achievements.banner_active = {}
	game.achievements.record_wildlife_kill("fox")
	game.achievements.banner_elapsed = 0.65
	game.achievements.update(0.016)
	await frames(4)
	game._capture("v082_rifle_reload_charm.png")
	game.player.reload_left = 0.0

	# 6) Yanxia Cave Acoustic Warden ("古洞循音石卫") emitting sleek cyan 3D sonar ring (#2 + V81-6/7)
	game.achievements.banner_panel.hide()
	game.achievements.banner_queue.clear()
	game.achievements.banner_active = {}
	game.cave_warden.reset()
	game.cave_warden.root_node.position = game.Layout.on_ground(Vector3(-41.60, 0.0, -61.8))
	game.cave_warden.root_node.rotation.y = 0.0
	game.cave_warden.state = "investigate"
	game.cave_warden.noise_meter = 52.0
	game.cave_warden._sync_label()
	game.cave_warden.spawn_sonar_ring(game.cave_warden.root_node.position, Color("54f0ff"), 8.5)
	game.cave_warden._update_sonar_rings(0.24)
	game.player.position = game.Layout.on_ground(Vector3(-41.60, 0.0, -55.4)) + Vector3(0.0, 0.12, 0.0)
	game.player.yaw = 0.0
	game.player.pitch = -0.02
	await frames(4)
	game._capture("v082_cave_warden.png")

	# 7) Confidential Operation Skyfall Giant 5-Shield Overlord ("雾隐机关王·玄铁词尊") (#12 + #13)
	game.start_action(true, "confidential")
	await frames(6)
	var c2: Vector3 = game.combat.zone_center(2)
	game.combat.engage_camp(2)
	var boss = game.combat.boss_unit
	if is_instance_valid(boss):
		boss.force_land_skyfall()
		for s in game.combat.troops[2]:
			s.set_physics_process(false)
			if s != boss:
				s.position = c2 + Vector3(12.0, 0.0, -10.0)
		boss.position = game.Layout.on_ground(c2 + Vector3(0.0, 0.0, -3.5))
		boss.rotation = Vector3.ZERO
	game.player.position = game.Layout.on_ground(c2 + Vector3(0.0, 0.0, 8.8)) + Vector3(0.0, 0.12, 0.0)
	game.player.yaw = 0.0
	game.player.pitch = 0.05
	await frames(6)
	game._capture("v082_skyfall_overlord.png")

	# 8) Simplified "🏆 烟山奇珍图鉴" -> "🎖 成就与挂件" tab + Camp Mandatory Review Menu check (V81-10/11/12)
	game._end_run(false)
	await frames(4)
	game.loot_ui.open_compendium("achievements")
	await frames(5)
	game._capture("v082_achievement_hall.png")
	game.loot_ui.close_compendium()

	game.queue_free()
	await process_frame
	print("CAPTURE_V082_DONE")
	quit(0)
