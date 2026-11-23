extends SceneTree
## Capture 8 GL Compatibility 1280x720 visual audit screenshots for v0.9.4 Rigged Hero '游侠·少羽':
## 1. Front 3/4 close-up portrait (Plan B amber goggles, hair, headset, scarf, jacket, chest rig, 2H rifle low-ready)
## 2. Right-side 3/4 ADS close-up (buttstock seated in shoulder, right hand on pistol grip, left hand TwoBoneIK3D on foregrip)
## 3. 3P Over-the-Shoulder gameplay view in Yanshan Base (sleek daypack, flowing red scarf, athletic fighting stance)
## 4. 3P Dynamic Sprint in Yanshan (real UAL Sprint_Fwd + upper-body rifle layer + SpringBone scarf wind)
## 5. 3P Crouched ADS Aim in Ahsarah Fortress (athletic crouch + shouldered rifle facing Zero Dam)
## 6. 3P Belly-Down Prone Stance in Ahsarah desert (elbows propped, natural legs, zero stiff plank)
## 7. 3P Shaoyu [V] '天生神力' Ground-Slam impact in Ahsarah (YS-04 back-holstered + bronze-knuckle slam)
## 8. 1P Look-Down showing smooth skinned cargo pants, kneepads & trail combat boots

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

func _hide_overlays(game):
	game.feedback_left = 0.0
	if is_instance_valid(game.feedback_panel):
		game.feedback_panel.hide()
	game.radio_left = 0.0
	if is_instance_valid(game.radio_panel):
		game.radio_panel.hide()
	if is_instance_valid(game.achievements) and is_instance_valid(game.achievements.banner_root):
		game.achievements.banner_root.hide()
		game.achievements.banner_queue.clear()
		game.achievements.banner_active.clear()
		game.achievements.banner_elapsed = 0.0

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
	# Use iron sights during 3P ADS visual audit shots so we inspect Shaoyu's 3P shouldered ADS pose directly!
	game.rules.profile.owned.erase("red_dot")
	game.rules.profile.owned.erase("scope_2x")
	game.rules.profile.equipped["optic"] = ""

	game.start_action(true, "normal")
	await frames(8)
	game.player.set_third_person(true, true)
	game.player.position = game.active_layout.on_ground(Vector3(3.5, 0.0, 22.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.35
	game.player.pitch = -0.04
	await frames(22)
	_hide_overlays(game)

	# Auxiliary studio-inspection camera for Front & Side close-ups (so HUD + character read crystal clear!)
	var insp_cam := Camera3D.new()
	insp_cam.fov = 46.0
	root.add_child(insp_cam)

	# 1. Front 3/4 Hero Close-up Portrait (Low-Ready Rifle Stance, Plan B Amber Goggles, Hair, Scarf, MOLLE Rig!)
	var ppos: Vector3 = game.player.global_position
	var pfwd: Vector3 = -game.player.global_basis.z
	var pright: Vector3 = game.player.global_basis.x
	insp_cam.current = true
	insp_cam.global_position = ppos + pfwd * 2.05 + pright * 0.62 + Vector3.UP * 1.24
	insp_cam.look_at(ppos + Vector3.UP * 1.12, Vector3.UP)
	await frames(10)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_01_front_hero_closeup.png"))

	# 2. Right-Side 3/4 ADS Close-up (buttstock seated in right shoulder, right hand on pistol grip, left hand IK on handguard!)
	game.player.aiming = true
	await frames(24)
	insp_cam.global_position = ppos + pfwd * 1.35 + pright * 1.25 + Vector3.UP * 1.28
	insp_cam.look_at(ppos + pfwd * 0.12 + Vector3.UP * 1.18, Vector3.UP)
	await frames(8)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_02_side_rifle_grip_closeup.png"))

	# Restore gameplay camera for authentic 3P over-the-shoulder shots!
	game.player.aiming = false
	game.player.camera.current = true
	await frames(16)

	# 3. Authentic 3P Over-the-Shoulder Gameplay View in Yanshan Base
	game.player.yaw = 0.16
	game.player.pitch = -0.07
	await frames(18)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_03_3p_yanshan_standing.png"))

	# 4. 3P Dynamic Sprint in Yanshan (real UAL Sprint_Fwd legs + rifle upper body + SpringBone scarf wind!)
	game.player.held_keys[KEY_W] = true
	game.player.held_keys[KEY_SHIFT] = true
	await frames(28)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_04_3p_sprint_scarf_motion.png"))
	game.player.held_keys.clear()
	await frames(12)

	# 5. Switch to Ahsarah Fortress: 3P Crouched ADS Aim facing Zero Dam!
	game.switch_map("ahsarah", true)
	await frames(8)
	game.start_action(true, "normal")
	await frames(8)
	game.player.set_third_person(true, true)
	game.player.position = game.active_layout.on_ground(Vector3(6.0, 0.0, -48.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.05
	game.player.pitch = -0.04
	game.player.set_stance(game.player.STANCE_CROUCH, true)
	game.player.aiming = true
	await frames(26)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_05_3p_ahsarah_crouch_aim.png"))

	# 6. 3P Belly-Down Prone Stance in Ahsarah Desert (real elbows-propped shooter posture!)
	game.player.aiming = false
	game.player.set_stance(game.player.STANCE_PRONE, true)
	game.player.position = game.active_layout.on_ground(Vector3(-8.0, 0.0, -28.0)) + Vector3.UP * 0.12
	game.player.yaw = -0.35
	game.player.pitch = -0.08
	await frames(26)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_06_3p_prone_crawl.png"))

	# 7. 3P Shaoyu [V] '天生神力' Ground-Slam Impact in Ahsarah (YS-04 back-holstered + clenched bronze-knuckle punch!)
	game.player.set_stance(game.player.STANCE_STAND, true)
	game.player.position = game.active_layout.on_ground(Vector3(0.0, 0.0, -108.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.0
	game.player.pitch = -0.10
	game.combat.engage_camp(2, false)
	await frames(12)
	game.use_ranger_skill()
	await frames(22)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_07_3p_shaoyu_v_slam.png"))

	# 8. 1P Look-Down showing Shaoyu's smooth skinned cargo pants, kneepads & trail combat boots!
	await frames(28)
	game.player.set_third_person(false, true)
	game.player.set_stance(game.player.STANCE_STAND, true)
	game.player.position = game.active_layout.on_ground(Vector3(-2.0, 0.0, -40.0)) + Vector3.UP * 0.12
	game.player.yaw = 0.0
	game.player.pitch = -1.20
	await frames(14)
	_hide_overlays(game)
	await grab(media_dir.path_join("v094_08_1p_lookdown_skinned_boots.png"))

	insp_cam.queue_free()
	print("CAPTURE_V094_DONE")
	quit(0)
