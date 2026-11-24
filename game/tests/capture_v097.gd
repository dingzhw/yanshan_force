extends SceneTree
## v0.9.7 Comprehensive Visual Audit Capture Suite (1280x720 GL Compatibility):
## 01. Desert Spawn, Wind-Rippled PBR Sand, Palm Oasis, Acacia & Sculpted Chen Guide
## 02. Desert Cement Plant PBR Silos, Catwalk & Shifted Container #1 (Zero Clipping)
## 03. Desert Brakkesh Grand Bathhouse & Photogrammetry Boulders/Scrub
## 04. Desert Zero Dam Concrete Monolith + Photogrammetry Canyon Cliff Abutments
## 05. Desert Helipad Solid Beveled Concrete + Grounded Crates & Level Recon Jeep
## 06. Yanshan Overview (Seamless 360 Horizon, Mossy-Rock Terrain, Sculpted Chen Guide & Refined Display Stand)
## 07. Yanshan Close-Up: Leafy Terraced Tea Hedges + Photogrammetry Mossy Boulders + Grounded Fallen Logs
## 08. Yanshan Stream & Stone Arch Bridge (Softened Mossy Cobble Banks)
## 09. Yanshan Combat Close-Up: Sculpted Skeletal-Animated Mistbound Assault & Sniper + Shaoyu 3P
## 10. Lore Codex Rangers Page on Veteran Save (extractions=22, rep=0, bounties=0): ONLY Shaoyu unlocked!

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V097 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

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

	# Start in Yanshan first for Shots 06-09 (cleanest initial world state!)
	main.switch_map("yanshan")
	main.start_action(true, "normal")
	main.player.set_third_person(true, true)
	for _i in 16:
		await process_frame
	main.paused = true
	main.hud.hide()

	var sc_body := main.landscape.find_child("YanshanSceneryColliders", true, false) as StaticBody3D
	var sc_shapes := sc_body.get_child_count() if is_instance_valid(sc_body) else 0
	print("AUDIT_YANSHAN_SCENERY_COLLIDERS shapes=", sc_shapes)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.12
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true

	# Shot 06: Yanshan Overview — Seamless skyline + Sculpted Chen Guide + Refined Rosewood Display Stand!
	var sp_y: Vector3 = main.active_layout.on_ground(main.active_layout.SPAWN)
	_aim(cam, sp_y + Vector3(-1.2, 2.35, 5.2), sp_y + Vector3(0.4, 1.55, -18.0))
	await _snap("v097_06_yanshan_overview_camp.png")

	# Shot 07: Close-up of NEW botanical leafy Tea Hedges + Photogrammetry Mossy Boulders!
	# Find an actual Tea Hedge & Mossy Boulder pair from MultiMeshInstance3D!
	var tea_mmi := main.landscape.find_child("JiangnanTeaHedges", true, false) as MultiMeshInstance3D
	var bld_mmi := main.landscape.find_child("MossyBoulderClusters", true, false) as MultiMeshInstance3D
	var focus_pt: Vector3 = main.active_layout.on_ground(Vector3(52.0, 0.0, -10.0))
	if is_instance_valid(tea_mmi) and tea_mmi.multimesh != null and tea_mmi.multimesh.instance_count > 0:
		# Pick a tea hedge closest to a mossy boulder so both fill the frame!
		var best_dist := INF
		var best_tp: Vector3 = tea_mmi.to_global(tea_mmi.multimesh.get_instance_transform(0).origin)
		var best_mid: Vector3 = best_tp
		for ti in tea_mmi.multimesh.instance_count:
			var tp: Vector3 = tea_mmi.to_global(tea_mmi.multimesh.get_instance_transform(ti).origin)
			if is_instance_valid(bld_mmi) and bld_mmi.multimesh != null:
				for bi in bld_mmi.multimesh.instance_count:
					var bp: Vector3 = bld_mmi.to_global(bld_mmi.multimesh.get_instance_transform(bi).origin)
					var d := tp.distance_to(bp)
					if d < best_dist:
						best_dist = d
						best_tp = tp
						best_mid = 0.5 * (tp + bp)
		focus_pt = best_mid if best_dist < 14.0 else best_tp
		print("AUDIT_TEA_BOULDER_PAIR dist=", snappedf(best_dist, 0.1), " focus=", focus_pt)
	_aim(cam, focus_pt + Vector3(-5.2, 2.35, 5.6), focus_pt + Vector3(0.0, 0.65, 0.0))
	await _snap("v097_07_yanshan_tea_boulders_logs.png")

	# Shot 08: Yanshan Stream & Stone Arch Bridge (softened natural mossy cobble banks!)
	var br_z := float(main.active_layout.STREAM_BRIDGES[0]) if not main.active_layout.STREAM_BRIDGES.is_empty() else -24.0
	var br_x := float(main.active_layout.stream_center_x(br_z))
	var br_y := float(main.active_layout.stream_water_y(br_z))
	_aim(cam, Vector3(br_x - 7.8, br_y + 3.2, br_z + 11.5), Vector3(br_x + 0.5, br_y + 0.4, br_z - 1.5))
	await _snap("v097_08_yanshan_stream_bridge.png")

	# Shot 09: Yanshan Combat Patrol Close-Up — Sculpted Animated Mistbound Assault & Sniper Troopers!
	# Keep player outside aggro range so standby patrol squad displays full sculpted armor/eave-visor helmets/rifles cleanly!
	var z0_pos: Vector3 = main.active_layout.on_ground(main.active_layout.COMBAT_ZONES[0].at)
	main.paused = false
	for _k in 18:
		await process_frame
	main.paused = true
	var enemy_focus := z0_pos + Vector3(0.0, 1.05, 0.0)
	var first_e_pos := Vector3.ZERO
	var rig_cnt := 0
	var total_bots := 0
	for zid in main.combat.troops.keys():
		for s in main.combat.troops[zid]:
			if is_instance_valid(s) and not s.defeated:
				total_bots += 1
				if s.find_child("MistboundSkeletalRig", true, false) != null:
					rig_cnt += 1
					if zid == 0 and first_e_pos == Vector3.ZERO:
						first_e_pos = s.global_position
	print("AUDIT_MISTBOUND_RIGS active_skeletal_soldiers=", rig_cnt, " total=", total_bots)
	if first_e_pos != Vector3.ZERO:
		enemy_focus = first_e_pos + Vector3(0.0, 1.02, 0.0)
	# Frame from 3/4 flank angle so full sculpted Mistbound eave-visor helmet, bronze armor, rifle & clean word shield all read!
	_aim(cam, enemy_focus + Vector3(-2.35, 0.38, 1.45), enemy_focus + Vector3(0.10, 0.06, 0.15))
	await _snap("v097_09_yanshan_mistbound_combat.png")

	# Switch to Ahsarah Desert Fortress for Shots 01-05!
	cam.queue_free()
	main.rules.unlock_map("ahsarah")
	main.switch_map("ahsarah")
	main.start_action(true, "normal")
	main.player.set_third_person(true, true)
	for _i in 18:
		await process_frame
	main.paused = true
	main.hud.hide()

	var heli_pad: Node = main.landscape.find_child("HelipadConcreteDeck", true, false)
	var heli_has_col := (heli_pad != null and heli_pad.find_child("*", true, false) != null)
	print("AUDIT_DESERT_HELIPAD_SOLID=", heli_has_col)

	cam = Camera3D.new()
	cam.fov = 64.0
	cam.near = 0.12
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true

	# Shot 01: Desert Spawn, Wind-Rippled PBR Sand, Palm Oasis (no glowing dates!), Acacia & Sculpted Chen Guide!
	var dsp: Vector3 = main.active_layout.on_ground(main.active_layout.SPAWN)
	_aim(cam, dsp + Vector3(5.8, 2.55, 7.6), Vector3(-5.0, dsp.y + 1.1, 7.5))
	await _snap("v097_01_desert_spawn_oasis.png")

	# Shot 02: Cement Plant PBR Silos, Elevated Catwalk & Shifted Container #1 (ZERO clipping!)
	var cm_p: Vector3 = main.active_layout.on_ground(Vector3(-39.0, 0.0, -50.0))
	_aim(cam, cm_p + Vector3(18.0, 7.5, 16.5), cm_p + Vector3(-5.0, 3.2, -3.0))
	await _snap("v097_02_desert_cement_plant.png")

	# Shot 03: Brakkesh Grand Dome Bathhouse PBR Sandstone + Photogrammetry Boulders & Desert Scrub!
	var bz_p: Vector3 = main.active_layout.on_ground(main.active_layout.GRAND_BATHHOUSE)
	_aim(cam, bz_p + Vector3(-16.5, 4.4, 15.0), bz_p + Vector3(1.0, 2.8, -1.0))
	await _snap("v097_03_desert_bazaar_bathhouse.png")

	# Shot 04: Zero Dam Monumental Concrete + Flanking Photogrammetry Canyon Cliff Abutments!
	var dm_p: Vector3 = main.active_layout.on_ground(main.active_layout.ADMIN_FORTRESS)
	_aim(cam, dm_p + Vector3(0.0, 15.0, 21.0), Vector3(0.0, dm_p.y + 8.0, -155.0))
	await _snap("v097_04_desert_zero_dam_cliffs.png")

	# Shot 05: Helipad Solid Beveled Concrete + Grounded Crates (38.5,-135.5 / 44,-126) & Level Recon Jeep!
	var hp_p: Vector3 = main.active_layout.on_ground(main.active_layout.EXIT)
	_aim(cam, Vector3(31.5, hp_p.y + 4.8, -118.5), Vector3(47.0, hp_p.y + 0.5, -135.0))
	await _snap("v097_05_desert_helipad_crates.png")

	# Shot 10: Lore Codex Rangers Page on Veteran-Style Save (extractions=22, reputation=0, bounties=0, prologue=false)
	# Proves STRICT gating: ONLY Shaoyu unlocked; Chen/Tingfeng/Qinghe/Zhuying ALL show locked "?"!
	cam.queue_free()
	main._end_run(false, "验收")
	for _i in 8:
		await process_frame
	main.rules.profile.extractions = 22
	main.rules.profile.runs = 30
	main.rules.profile.reputation = 0
	main.rules.profile.bounties_completed = 0
	main.rules.profile.prologue_completed = false
	main.rules.profile.lore_stats = {"shaoyu_runs": 22, "camps_cleared": 40, "warden_defeats": 5}
	main.rules.profile.lore_scenes = ["yanshan_base"]
	main.rules.profile.character_cards = ["shaoyu"]
	main.lore_codex.open("rangers")
	var unlocked_rangers: Array[String] = []
	for cid in ["shaoyu", "chen_guide", "tingfeng", "qinghe", "zhuying"]:
		if main.lore_codex.is_character_unlocked(cid):
			unlocked_rangers.append(cid)
	print("AUDIT_RANGERS_STRICT_UNLOCKED=", unlocked_rangers)
	await _snap("v097_10_rangers_strict_locked.png")

	print("ALL 10 v0.9.7 VISUAL CAPTURES DONE")
	quit(0)
