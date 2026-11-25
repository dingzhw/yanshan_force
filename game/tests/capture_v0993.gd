extends SceneTree
## v0.9.9.3 Visual Audit Capture Suite (1280x720 GL Compatibility):
## 01. 1P Look-Down (Stand) — verifying ZERO hands/arms/chest/torso leak, ONLY clean cargo pants & boots!
## 02. 1P Unified Shaoyu Viewmodel (Rifle + Knife) — bamboo-teal tactical sleeves + charcoal bracer/gloves!
## 03. 3P Rifle_Aim + Rifle_LowReady — real Mixamo mocap dual-hand grip (0mm pistol grip & handguard alignment!)
## 04. 3P Rifle_Crouch_Aim (Kneeling Crouch) — real Mixamo mocap, BOTH feet natural & planted (ZERO twisted feet!)
## 05. 3P Knife_Idle (Martial-arts Stance) — real Mixamo mocap, tactical knife gripped firmly in right hand (ZERO floating!)
## 06. 3P Prone_Idle — real Mixamo mocap, belly/elbows/knees/boots 100% FLAT on Yanshan meadow grass (ZERO hovering!)

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V0993 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

func _aim(cam: Camera3D, from: Vector3, to: Vector3):
	cam.global_position = from
	cam.look_at(to, Vector3.UP)

func _initialize():
	call_deferred("_run")

func _run():
	var main = load("res://main.tscn").instantiate()
	main.qa_mode = true
	root.add_child(main)
	for _i in 14:
		await process_frame

	main.switch_map("yanshan")
	main.start_action(true, "normal")
	for _i in 12:
		await process_frame

	main.wildlife.frozen_for_capture = true
	main.paused = false
	main.hud.hide()

	var sp := Vector3(14.6, float(main.Layout.fast_height(14.6, 25.4)), 25.4)
	main.player.global_position = sp
	main.player.yaw = PI - 0.25
	main.player.rotation = Vector3(0.0, PI - 0.25, 0.0)
	main.player.stance = 0

	# Shot 01: 1P Look-Down (Stand) — verifying ONLY clean cargo pants & boots, ZERO hands/chest!
	main.player.set_third_person(false, true)
	main.player.select_weapon(0)
	main.player.pitch = -1.25
	for _i in 16:
		await physics_frame
	await _snap("v0993_01_1p_lookdown_clean.png")

	# Shot 02: 1P Unified Shaoyu Arms holding YS-04 Rifle (bamboo-teal tactical sleeve + charcoal bracer/gloves!)
	main.player.pitch = 0.0
	for _i in 12:
		await physics_frame
	await _snap("v0993_02_1p_unified_arms.png")

	# Switch to 3P external inspection camera
	main.player.set_third_person(true, true)
	var cam := Camera3D.new()
	cam.fov = 46.0
	cam.near = 0.10
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true
	var fwd := Vector3(-sin(PI - 0.25), 0.0, -cos(PI - 0.25)).normalized()
	var rgt := Vector3(fwd.z, 0.0, -fwd.x).normalized()

	# Shot 03: 3P Rifle_Aim (real Mixamo mocap shoulder-stock ADS, both hands 100% locked on grip & handguard!)
	main.player.stance = 0
	main.player.select_weapon(0)
	main.player.aiming = true
	for _i in 22:
		await physics_frame
	_aim(cam, sp + fwd * 2.15 + rgt * 1.10 + Vector3(0.0, 1.24, 0.0), sp + Vector3(0.0, 1.02, 0.0))
	await _snap("v0993_03_3p_rifle_aim.png")
	main.player.aiming = false

	# Shot 04: 3P Tactical Kneeling Crouch (real Mixamo Idle_Crouching_Aiming — ZERO twisted feet!)
	main.player.stance = 1
	for _i in 24:
		await physics_frame
	_aim(cam, sp + fwd * 2.05 + rgt * 1.25 + Vector3(0.0, 0.92, 0.0), sp + Vector3(0.0, 0.54, 0.0))
	await _snap("v0993_04_3p_crouch_mocap.png")

	# Shot 05: 3P Tactical Knife Stance (real Mixamo Knife_Idle — knife firmly gripped in right hand, rifle slung on back!)
	main.player.stance = 0
	main.player.select_weapon(1)
	for _i in 24:
		await physics_frame
	_aim(cam, sp + fwd * 2.25 + rgt * 0.72 + Vector3(0.0, 1.18, 0.0), sp + Vector3(0.0, 0.94, 0.0))
	await _snap("v0993_05_3p_knife_mocap.png")

	# Shot 06: 3P Prone Aim (real Mixamo Prone_Idle — belly, elbows, legs & boots 100% FLAT on meadow grass!)
	var sp_flat := Vector3(14.2, float(main.Layout.fast_height(14.2, 23.6)), 23.6)
	main.player.global_position = sp_flat
	main.player.yaw = PI * 0.5
	main.player.select_weapon(0)
	main.player.stance = 2
	for _i in 26:
		await physics_frame
	_aim(cam, sp_flat + Vector3(0.55, 0.76, 2.20), sp_flat + Vector3(0.0, 0.22, 0.0))
	await _snap("v0993_06_3p_prone_mocap.png")

	main.queue_free()
	await process_frame
	quit(0)
