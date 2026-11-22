extends SceneTree
## Capture 8 GL Compatibility 1280x720 visual audit screenshots for v0.9.3:
## 1. Minimal Delta Force HUD in 1P Yanshan (clean open front view + English strip + icon HUD)
## 2. 1P looking down at real 3D legs, kneepads & combat boots
## 3. 3P over-the-shoulder full-body hero '少羽' in Yanshan Base
## 4. 3P crouched over-the-shoulder aim in Ahsarah Fortress + Chinese Boss radio caption
## 5. 3P prone horizontal crawl posture in Ahsarah desert
## 6. 3P knife equipped with YS-04 rifle holstered diagonally on back pack
## 7. 3P Shaoyu [V] ground-slam shockwave punch in combat
## 8. On-demand [F1] Tactical Intel & Keybind overlay

func _init():
	call_deferred("_run")

func frames(n: int):
	for _i in n:
		await physics_frame
		await process_frame

func grab(path: String):
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURED ", path)

func _run():
	var media_dir := ProjectSettings.globalize_path("res://../docs/media")
	DirAccess.make_dir_recursive_absolute(media_dir)

	var game = load("res://main.tscn").instantiate()
	game.qa_mode = true
	root.add_child(game)
	await frames(8)
	game.rules.unlock_map("ahsarah")
	game.rules.profile.owned.append("forest_skin")
	game.rules.profile.owned.append("shield_core")
	game.rules.profile.owned.append("tactical_belt")

	# 1. Minimal Delta Force HUD in 1P Yanshan (with active English combat word!)
	game.start_action(true, "normal")
	await frames(6)
	game.player.set_third_person(false, true)
	game.player.position = game.active_layout.on_ground(Vector3(0.0, 0.0, 12.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.0
	game.player.pitch = -0.04
	game.combat.engage_camp(0, false)
	await frames(10)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await grab(media_dir.path_join("v093_01_minimal_hud_1p_yanshan.png"))

	# 2. 1P looking down at real legs, kneepads & leather combat boots!
	game.player.position = game.active_layout.on_ground(Vector3(-2.5, 0.0, 26.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.0
	game.player.pitch = -1.18
	game.combat.disengage_active_camp(false)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	game.radio_left = 0.0
	game.radio_panel.hide()
	await frames(10)
	await grab(media_dir.path_join("v093_02_1p_lookdown_real_legs.png"))

	# 3. 3P over-the-shoulder full-body hero '少羽' standing in sunny Yanshan valley!
	game.player.position = game.active_layout.on_ground(Vector3(4.0, 0.0, 20.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.18
	game.player.pitch = -0.08
	game.player.set_third_person(true, true)
	game.cn_voice_cd = 0.0
	game.play_cn_voice("mb_01", 12.0, true)
	await frames(18)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await grab(media_dir.path_join("v093_03_3p_yanshan_standing.png"))

	# 4. Switch to Ahsarah Fortress: 3P crouched over-the-shoulder aim + Saeed Chinese voice radio caption!
	game.switch_map("ahsarah", true)
	await frames(8)
	game.start_action(true, "normal")
	await frames(8)
	if is_instance_valid(game.achievements) and is_instance_valid(game.achievements.banner_root):
		game.achievements.banner_root.hide()
		game.achievements.banner_queue.clear()
		game.achievements.banner_active.clear()
		game.achievements.banner_elapsed = 0.0
	game.player.set_third_person(true, true)
	game.player.position = game.active_layout.on_ground(Vector3(6.0, 0.0, -48.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.05
	game.player.pitch = -0.05
	game.player.set_stance(game.player.STANCE_CROUCH, true)
	game.player.aiming = true
	game.cn_voice_cd = 0.0
	game.play_cn_voice("saeed_02", 14.0, true)
	await frames(18)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await grab(media_dir.path_join("v093_04_3p_ahsarah_crouch_aim.png"))

	# 5. 3P Prone horizontal crawl posture in Ahsarah Fortress!
	game.player.aiming = false
	game.player.set_stance(game.player.STANCE_PRONE, true)
	game.player.position = game.active_layout.on_ground(Vector3(-8.0, 0.0, -28.0)) + Vector3.UP * 0.12
	game.player.yaw = -0.45
	game.player.pitch = -0.10
	game.radio_left = 0.0
	game.radio_panel.hide()
	await frames(18)
	await grab(media_dir.path_join("v093_05_3p_prone_crawl.png"))

	# 6. 3P Tactical Knife active with YS-04 rifle holstered diagonally on Shaoyu's backpack!
	game.player.set_stance(game.player.STANCE_STAND, true)
	game.player.select_weapon(1)
	game.player.position = game.active_layout.on_ground(Vector3(-2.0, 0.0, -86.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.15
	game.player.pitch = -0.06
	game.cn_voice_cd = 0.0
	game.play_cn_voice("reis_01", 10.0, true)
	await frames(18)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await grab(media_dir.path_join("v093_06_3p_knife_back_holster.png"))

	# 7. 3P Shaoyu [V] '天生神力' ground-slam shockwave punch in Ahsarah!
	game.player.select_weapon(0)
	game.player.position = game.active_layout.on_ground(Vector3(0.0, 0.0, -108.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.0
	game.player.pitch = -0.14
	game.combat.engage_camp(2, false)
	await frames(6)
	game.use_ranger_skill()
	await frames(8)
	await grab(media_dir.path_join("v093_07_3p_shaoyu_v_slam.png"))

	# 8. On-demand [F1] Tactical Intel & Keybind overlay cleanly displayed
	game.toggle_intel_overlay()
	await frames(4)
	await grab(media_dir.path_join("v093_08_f1_intel_overlay.png"))

	print("CAPTURE_V093_DONE")
	quit(0)
