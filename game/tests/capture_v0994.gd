extends SceneTree
## v0.9.9.4 Visual Audit Capture Suite (1280x720 — supports both Forward+ & GL Compatibility via --backend-tag):
## 01. Isolated Fresh Save Main Menu -> opens directly on Story Mode with one-click Prologue button
## 02. Prologue Camp Guide NPC -> unified formal npc_chen_guide.glb (zero primitive sphere/cone dummy)
## 03. Prologue 3 East Ridge Scouts -> unified formal v097_mistbound_assault.glb + compact overhead holographic tags
## 04. Normal Operation Camp Guide NPC -> same formal Chen Guide for side-by-side verification
## 05. Shaoyu v2 Front/3-4 Close-up (captured in BOTH Forward+ & GL Compatibility backends!)
## 06. Shaoyu v2 Real 3P Over-the-Shoulder Back View (captured in BOTH Forward+ & GL Compatibility backends!)

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V0994 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height(), " method=", RenderingServer.get_current_rendering_method())

func _aim(cam: Camera3D, from: Vector3, to: Vector3):
	cam.global_position = from
	cam.look_at(to, Vector3.UP)

func _initialize():
	call_deferred("_run")

func _run():
	var args := OS.get_cmdline_user_args()
	var method := str(RenderingServer.get_current_rendering_method())
	var tag := "gl" if "gl" in method else "fp"
	var shaoyu_only := ("--shaoyu-only" in args)

	var main = load("res://main.tscn").instantiate()
	main.qa_mode = true
	main.profile_path_override = "user://qa-v0994-clean-fresh.json"
	if FileAccess.file_exists(main.profile_path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(main.profile_path_override))
	root.add_child(main)
	for _i in 18:
		await process_frame

	if not shaoyu_only:
		# Shot 01: Isolated clean fresh save main menu (opens directly on Story Mode with one-click Prologue button!)
		await _snap("v0994_01_fresh_save_menu.png")

		# Shot 02: Actual Prologue Camp Guide NPC (unified formal npc_chen_guide.glb!)
		main.start_prologue_chapter(false)
		for _i in 12:
			await process_frame
		main.wildlife.frozen_for_capture = true
		main.hud.hide()
		var pcam := Camera3D.new()
		pcam.fov = 44.0
		pcam.near = 0.08
		pcam.far = 900.0
		main.add_child(pcam)
		pcam.current = true
		var npc_pos: Vector3 = main.prologue.npc_node.global_position
		var npc_fwd: Vector3 = main.prologue.npc_node.global_basis.z.normalized()
		var npc_rgt: Vector3 = main.prologue.npc_node.global_basis.x.normalized()
		_aim(pcam, npc_pos + npc_fwd * 2.25 + npc_rgt * 0.48 + Vector3(0.0, 1.38, 0.0), npc_pos + Vector3(0.0, 1.24, 0.0))
		await _snap("v0994_02_prologue_chen_guide.png")

		# Shot 03: Actual Prologue 3 Mistbound Scouts on East Ridge (unified formal rigs + compact overhead holographic tags!)
		var s0: Vector3 = main.prologue.scouts[0].node.global_position
		var s1: Vector3 = main.prologue.scouts[1].node.global_position
		var s2: Vector3 = main.prologue.scouts[2].node.global_position
		var mid_s: Vector3 = (s0 + s1 + s2) / 3.0
		main.player.global_position = Vector3(mid_s.x - 5.6, float(main.Layout.fast_height(mid_s.x - 5.6, mid_s.z + 6.8)), mid_s.z + 6.8)
		for _i in 12:
			await process_frame
		_aim(pcam, mid_s + Vector3(-5.8, 2.25, 7.2), mid_s + Vector3(0.0, 1.50, 0.0))
		await _snap("v0994_03_prologue_scouts.png")

		# Shot 04: Normal Operation Camp Liaison Chen Guide (same formal person across Prologue & Normal!)
		main.prologue.set_active(false)
		main.start_action(true, "normal")
		for _i in 12:
			await process_frame
		main.wildlife.frozen_for_capture = true
		main.hud.hide()
		pcam.current = true
		var cpos: Vector3 = main.rangers.camp_npc_node.global_position
		var cfwd: Vector3 = main.rangers.camp_npc_node.global_basis.z.normalized()
		var crgt: Vector3 = main.rangers.camp_npc_node.global_basis.x.normalized()
		_aim(pcam, cpos + cfwd * 2.25 + crgt * 0.48 + Vector3(0.0, 1.38, 0.0), cpos + Vector3(0.0, 1.24, 0.0))
		await _snap("v0994_04_normal_chen_guide.png")
		pcam.queue_free()
	else:
		main.switch_map("yanshan")
		main.start_action(true, "normal")
		for _i in 12:
			await process_frame
		main.wildlife.frozen_for_capture = true
		main.hud.hide()

	# Shot 05 & 06: Shaoyu v2 Dual-Backend Verification (Front/3-4 Portrait + Real Default 3P Over-the-Shoulder Back View!)
	var sp := Vector3(14.6, float(main.Layout.fast_height(14.6, 25.4)), 25.4)
	main.player.global_position = sp
	main.player.yaw = PI - 0.25
	main.player.rotation = Vector3(0.0, PI - 0.25, 0.0)
	main.player.stance = 0
	main.player.select_weapon(0)
	main.player.aiming = false
	main.player.set_third_person(true, true)
	main.player.pitch = -0.06
	for _i in 22:
		await physics_frame

	# Real player 3P over-the-shoulder camera (checks hair back, collar, scarf, gloves & backpack!)
	main.player.camera.current = true
	await _snap("v0994_06_shaoyu_ots_%s.png" % tag)

	# Close front/three-quarter inspection shot (exact same angle across Forward+ & GL Compatibility!)
	var sc_cam := Camera3D.new()
	sc_cam.fov = 42.0
	sc_cam.near = 0.08
	sc_cam.far = 900.0
	main.add_child(sc_cam)
	sc_cam.current = true
	var fwd := Vector3(-sin(PI - 0.25), 0.0, -cos(PI - 0.25)).normalized()
	var rgt := Vector3(fwd.z, 0.0, -fwd.x).normalized()
	_aim(sc_cam, sp + fwd * 1.85 + rgt * 0.72 + Vector3(0.0, 1.38, 0.0), sp + Vector3(0.0, 1.18, 0.0))
	await _snap("v0994_05_shaoyu_front_%s.png" % tag)

	main.queue_free()
	await process_frame
	quit(0)
