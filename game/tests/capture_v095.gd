extends SceneTree

const OUT_DIR := "res://../docs/media"

func _initialize():
	call_deferred("_run")

func _save_shot(name: String):
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V095 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

func _run():
	var main = load("res://main.tscn").instantiate()
	main.qa_mode = true
	root.add_child(main)
	for _i in 12:
		await process_frame

	# 1. Login Screen — 烟山行动 3D War Map (Left 1/5 Rail + Right 4/5 3D Jiangnan Map)
	main._select_nav_theater("yanshan")
	await _save_shot("v095_01_login_yanshan_3dmap.png")

	# 2. Login Screen — 阿萨拉行动 3D Desert Map (Zero Dam + Fortress + Oasis + Space Base)
	main.rules.unlock_map("ahsarah")
	main._select_nav_theater("ahsarah")
	await _save_shot("v095_02_login_ahsarah_3dmap.png")

	# 3. Login Screen — 剧情模式 (Golden-hour Yanshan Story Diorama)
	main._select_nav_theater("story")
	await _save_shot("v095_03_login_story_mode.png")

	# Seed realistic mid-campaign lore stats so locked + unlocked chapters & progress bars shine!
	main.rules.inc_lore_stat("shaoyu_runs", 2)
	main.rules.inc_lore_stat("shaoyu_skill_uses", 3)
	main.rules.mark_lore_scene("yanshan_base")
	main.rules.mark_lore_scene("prologue")
	main.rules.profile.extractions = 2
	main.rules.profile.reputation = 180
	main.rules.profile.achievements = ["first_extract", "streak_5"]
	main.rules.inc_lore_stat("ahsarah_runs", 1)
	main.rules.inc_lore_stat("saeed_defeats", 1)

	# 4. Standalone Lore Codex — Page 1: Multi-Faction Hub (Rangers tab)
	main.lore_codex.open("rangers")
	await _save_shot("v095_04_lore_codex_hub.png")

	# 5. Standalone Lore Codex — Page 2: Shaoyu Dedicated Dossier (Left Portrait + Right 4-Stage Lore)
	main.lore_codex.open_character("shaoyu")
	await _save_shot("v095_05_lore_codex_shaoyu.png")

	# 6. Standalone Lore Codex — Page 2: Warlord Reis Dedicated Dossier (Ahsarah faction)
	main.lore_codex.open_character("reis_warlord")
	await _save_shot("v095_06_lore_codex_reis.png")

	main.lore_codex.close()

	# 7. In-Engine Godot 3D Close-Up of Refined Shaoyu (Sculpted Face, Eyes through Amber Goggles, Hair, Scarf, 2H Rifle)
	main.switch_map("yanshan")
	main.start_action(false, "normal")
	main.player.set_third_person(true, true)
	main.player.position = main.active_layout.on_ground(Vector3(0.0, 0.0, 2.0)) + Vector3.UP * 0.05
	main.player.yaw = 0.0
	main.player.pitch = 0.0
	main.player.aiming = true
	for _i in 18:
		await physics_frame
		await process_frame
	main.hud.hide()
	var face_cam := Camera3D.new()
	face_cam.fov = 34.0
	main.add_child(face_cam)
	var ppos: Vector3 = main.player.global_position
	face_cam.position = ppos + Vector3(0.38, 1.56, -1.08)
	face_cam.look_at(ppos + Vector3(0.0, 1.46, 0.0), Vector3.UP)
	face_cam.current = true
	await _save_shot("v095_07_shaoyu_face_closeup.png")
	face_cam.current = false
	face_cam.queue_free()

	# 8. In-Engine Godot 3D Ahsarah Desert Zero-Twist Prone Pose
	main.switch_map("ahsarah")
	main.start_action(true, "normal")
	main.player.set_third_person(true, true)
	var sand_spot: Vector3 = main.active_layout.on_ground(Vector3(12.0, 0.0, 8.0)) + Vector3.UP * 0.05
	main.player.position = sand_spot
	main.player.yaw = 0.25
	main.player.pitch = 0.0
	main.player.stance = 2
	for _i in 24:
		await physics_frame
		await process_frame
	main.feedback_left = 0.0
	main.feedback_panel.hide()
	if is_instance_valid(main.achievements) and is_instance_valid(main.achievements.banner_root):
		main.achievements.banner_root.hide()
	main.hud.show()
	var prone_cam := Camera3D.new()
	prone_cam.fov = 44.0
	main.add_child(prone_cam)
	var pp2: Vector3 = main.player.global_position
	prone_cam.position = pp2 + Vector3(1.55, 0.95, 2.15)
	prone_cam.look_at(pp2 + Vector3(0.0, 0.28, -0.15), Vector3.UP)
	prone_cam.current = true
	await _save_shot("v095_08_shaoyu_prone_desert.png")
	prone_cam.current = false
	prone_cam.queue_free()

	# 9. In-Engine Godot 1P Look-Down (Clean Cargo Pants, Kneepads & Combat Boots, zero floating waist dome!)
	main.player.stance = 0
	main.player.set_third_person(false, true)
	main.player.camera.current = true
	main.player.pitch = deg_to_rad(-76.0)
	for _i in 20:
		await physics_frame
		await process_frame
	main.feedback_left = 0.0
	main.feedback_panel.hide()
	if is_instance_valid(main.achievements) and is_instance_valid(main.achievements.banner_root):
		main.achievements.banner_root.hide()
	await _save_shot("v095_09_shaoyu_1p_lookdown.png")

	print("CAPTURE_V095_ALL_DONE")
	quit(0)
