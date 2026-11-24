extends SceneTree
## v0.9.8 Visual Audit Capture Suite (1280x720 GL Compatibility):
## 01. Chen Guide front close-up (portrait-faithful salt-and-pepper hair, sculpted face/eyes, golden scarf, binoculars, NO weird hat!)
## 02. Yanshan Mistbound combat close-up (NEW compact overhead translucent word tag + embedded glowing chest word core, ZERO body occlusion!)
## 03. Yanshan mid-range (~22m) word tag readability verification
## 04. Knife melee per-hit HP deduction (visibly shortened amber HP bar + HP 54/90 + rising -18 damage popup!)
## 05. Cave Warden portrait-faithful hero front 3/4 inside Yanxia Ancient Cave (carved sandstone face, cyan eyes/runes, diamond core, twin forearm tower shields!)
## 06. Cave Warden X-brace dual forearm tower-shield guard pose over chest diamond core
## 07. Cave Warden Blind Bull-Rush Charge telegraph lane + Wall-Slam exposed core
## 08. Ahsarah Desert combat with NEW compact overhead translucent word tags + embedded chest core

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V098 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

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

	# Start in Yanshan Normal Combat
	main.switch_map("yanshan")
	main.start_action(true, "normal")
	main.player.set_third_person(false, true)
	for _i in 14:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.near = 0.10
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true

	# ------------------------------------------------------------------
	# Shot 01: Front Close-Up of Rebuilt Portrait-Faithful Chen Guide!
	# ------------------------------------------------------------------
	main.paused = true
	main.hud.hide()
	var chen: Node3D = main.rangers.camp_npc_node
	var chen_p: Vector3 = chen.global_position
	var chen_fwd: Vector3 = (chen.global_transform.basis.z).normalized()
	var chen_right: Vector3 = (chen.global_transform.basis.x).normalized()
	_aim(cam, chen_p + chen_fwd * 1.55 + chen_right * 0.22 + Vector3(0.0, 1.52, 0.0), chen_p + Vector3(0.0, 1.44, 0.0))
	await _snap("v098_01_chen_guide_front.png")

	# ------------------------------------------------------------------
	# Shot 02: Yanshan Combat Close-Up — Compact Overhead Word Tag + Embedded Chest Core (ZERO body occlusion!)
	# ------------------------------------------------------------------
	main.paused = false
	main.combat.engage_camp(0)
	for _i in 6:
		await process_frame
	var squad0: Array = main.combat.troops.get(0, [])
	var camp0_c: Vector3 = main.active_layout.on_ground(main.combat.zone_center(0))
	var focus_s = null
	var idx_place := 0
	for s in squad0:
		if is_instance_valid(s) and not s.defeated:
			var px := camp0_c.x + (-1.75 + float(idx_place) * 1.85)
			var pz := camp0_c.z - 1.5 + float(idx_place % 2) * 0.65
			s.position = main.active_layout.on_ground(Vector3(px, 0.0, pz)) + Vector3(0.0, 0.04, 0.0)
			s.rotation.y = 0.0
			if focus_s == null:
				focus_s = s
			idx_place += 1
	main.player.position = main.active_layout.on_ground(camp0_c + Vector3(0.0, 0.0, 5.2))
	for _i in 6:
		await process_frame
	main.paused = true
	cam.fov = 58.0
	_aim(cam, camp0_c + Vector3(0.0, 2.05, 5.15), camp0_c + Vector3(0.0, 1.48, -1.2))
	await _snap("v098_02_word_shield_closeup.png")

	# ------------------------------------------------------------------
	# Shot 03: Mid-Range (~17m) Unobstructed Readability Check of Compact Overhead Word Tags!
	# ------------------------------------------------------------------
	_aim(cam, camp0_c + Vector3(-2.6, 3.8, 16.5), camp0_c + Vector3(0.0, 1.85, -1.2))
	await _snap("v098_03_word_shield_midrange.png")

	# ------------------------------------------------------------------
	# Shot 04: Knife Melee Per-Hit Visible HP Deduction (2 Slashes -> HP 54/90 + Amber Bar + Rising "-18"!)
	# ------------------------------------------------------------------
	main.paused = false
	var target_s = null
	for s in squad0:
		if is_instance_valid(s) and not s.defeated and s.option == main.answer_index:
			target_s = s
			break
	if target_s == null:
		target_s = focus_s
	if target_s != null:
		target_s.position = main.active_layout.on_ground(camp0_c + Vector3(0.0, 0.0, 0.5)) + Vector3(0.0, 0.04, 0.0)
		target_s.rotation.y = 0.0
		main.player.position = main.active_layout.on_ground(camp0_c + Vector3(0.0, 0.0, 2.7))
		main.player.select_weapon(1)
		var slash_cam := Camera3D.new()
		main.add_child(slash_cam)
		slash_cam.global_position = main.player.position + Vector3(0.0, 1.56, 0.0)
		slash_cam.look_at(target_s.global_position + Vector3(0.0, 1.25, 0.0))
		main.combat.melee_strike(slash_cam)
		await process_frame
		main.combat.melee_strike(slash_cam)
		slash_cam.queue_free()
		for _i in 3:
			await process_frame
		main.paused = true
		main.hud.show()
		cam.fov = 56.0
		_aim(cam, target_s.global_position + Vector3(0.45, 1.85, 3.85), target_s.global_position + Vector3(0.0, 1.65, 0.0))
		await _snap("v098_04_knife_hp_deduction.png")
		main.hud.hide()

	# ------------------------------------------------------------------
	# Shot 05, 06, 07: Rebuilt Portrait-Faithful Cave Warden Inside Yanxia Cave!
	# ------------------------------------------------------------------
	main.paused = false
	main.combat.disengage_active_camp(false)
	var cw = main.cave_warden
	cw.reset()
	var c_cen: Vector3 = main.Layout.YANXIA_CAVE_CENTER
	var c_fy: float = float(main.Layout.CAVE_FLOOR_Y) + 0.03
	cw.root_node.position = Vector3(c_cen.x, c_fy, c_cen.z + 2.4)
	cw.root_node.rotation = Vector3.ZERO
	cw.set_guard_arms(false, 0.0)
	cw.patrol_listen_left = 0.0
	cw.snap_articulation_for_pose()
	# Add a gentle gallery rim light so sculpted sandstone facets & cyan runes read crisply in the cavern!
	var fill := OmniLight3D.new()
	fill.light_color = Color("d8ecff")
	fill.light_energy = 2.4
	fill.omni_range = 16.0
	fill.position = cw.root_node.position + Vector3(2.0, 2.8, 4.2)
	main.add_child(fill)

	# Shot 05: Heroic Front 3/4 Portrait-Faithful Pose!
	main.paused = true
	cam.fov = 54.0
	_aim(cam, cw.root_node.position + Vector3(1.15, 1.92, 4.15), cw.root_node.position + Vector3(0.0, 1.48, 0.0))
	await _snap("v098_05_cave_warden_portrait_front.png")

	# Shot 06: Twin Massive Carved-Stone Forearm Tower Shields Crossed in X-Brace Guard!
	cw.set_guard_arms(true, 5.0)
	cw.snap_articulation_for_pose()
	_aim(cam, cw.root_node.position + Vector3(-0.75, 1.85, 3.85), cw.root_node.position + Vector3(0.0, 1.48, 0.0))
	await _snap("v098_06_cave_warden_xguard.png")

	# Shot 07: NEW Blind Bull-Rush Charge Telegraph Corridor (camera cleanly inside cave!)
	cw.set_guard_arms(false, 0.0)
	cw.root_node.position = Vector3(c_cen.x, c_fy, c_cen.z + 0.4)
	cw.start_blind_rush(cw.root_node.position + Vector3(0.0, 0.0, 6.8))
	cw.snap_articulation_for_pose()
	_aim(cam, cw.root_node.position + Vector3(2.15, 2.25, 4.95), cw.root_node.position + Vector3(0.0, 1.10, 2.2))
	await _snap("v098_07_cave_warden_rush_telegraph.png")
	fill.queue_free()

	# ------------------------------------------------------------------
	# Shot 08: Ahsarah Desert Guards & Haavk Troopers with NEW Compact Overhead Word Tags!
	# ------------------------------------------------------------------
	main.paused = false
	main._end_run(false)
	main.rules.unlock_map("ahsarah")
	main.switch_map("ahsarah")
	main.start_action(true, "normal")
	for _i in 16:
		await process_frame
	main.combat.engage_camp(0)
	for _i in 6:
		await process_frame
	var a_c0: Vector3 = main.active_layout.on_ground(main.combat.zone_center(0))
	var sq_a: Array = main.combat.troops.get(0, [])
	var ia := 0
	for s in sq_a:
		if is_instance_valid(s) and not s.defeated:
			s.position = main.active_layout.on_ground(Vector3(a_c0.x - 2.1 + float(ia) * 1.9, 0.0, a_c0.z - 1.2 + float(ia % 2) * 0.5)) + Vector3(0.0, 0.04, 0.0)
			s.rotation.y = 0.0
			ia += 1
	main.player.position = main.active_layout.on_ground(a_c0 + Vector3(0.0, 0.0, 5.4))
	for _i in 6:
		await process_frame
	main.paused = true
	cam.fov = 58.0
	_aim(cam, a_c0 + Vector3(0.0, 2.1, 5.6), a_c0 + Vector3(0.0, 1.48, -1.0))
	await _snap("v098_08_ahsarah_overhead_shields.png")

	main.queue_free()
	await process_frame
	print("V098_CAPTURE_COMPLETE")
	quit(0)
