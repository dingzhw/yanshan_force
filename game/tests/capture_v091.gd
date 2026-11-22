extends SceneTree
## v0.9.1 Visual Showcase & Grounding Audit Capture Suite (8 crisp 1280x720 GL Compatibility renders)

func frames(n: int):
	for _i in n:
		await process_frame

func snap(out_dir: String, fname: String):
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var full := out_dir.path_join(fname)
	var err := img.save_png(full)
	print("CAPTURE_V091 ", fname, " err=", err, " size=", img.get_width(), "x", img.get_height())

func aim_player_at(game, from_pos: Vector3, target_pos: Vector3, stand_y_exact: bool = false):
	var p = game.player
	if stand_y_exact:
		p.position = from_pos
	else:
		p.position = Vector3(from_pos.x, game.active_layout.height(from_pos.x, from_pos.z) + 0.08, from_pos.z)
	p.velocity = Vector3.ZERO
	var eye: Vector3 = p.position + Vector3(0.0, 1.56, 0.0)
	var delta := target_pos - eye
	var horiz := Vector2(delta.x, delta.z).length()
	p.yaw = atan2(-delta.x, -delta.z)
	p.pitch = clampf(atan2(delta.y, maxf(0.01, horiz)), -1.1, 1.1)
	p.rotation.y = p.yaw
	p.camera.rotation.x = p.pitch

func _initialize():
	call_deferred("run")

func run():
	var out_dir := ProjectSettings.globalize_path("res://../docs/media")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var game = load("res://main.tscn").instantiate()
	game.profile_path_override = "user://capture_v091_profile.json"
	root.add_child(game)
	await frames(6)

	# Unlock Ahsarah & all 3 new Ahsarah charms for visual inspection
	game.rules.unlock_map("ahsarah")
	for cid in ["charm_mini_mandel", "charm_fiery_owl", "charm_heart_africa"]:
		if not (cid in game.rules.profile.unlocked_charms):
			game.rules.profile.unlocked_charms.append(cid)
	game.switch_map("ahsarah")
	await frames(6)

	game.start_action(true, "normal")
	await frames(6)
	game.wildlife.frozen_for_capture = true
	game.achievements.equip_charm("charm_mini_mandel")
	await frames(4)

	# 1. Walkable 2nd-floor Administrative Fortress Balcony overlooking Boss Courtyard, Saeed, MandelBrick & West Wing!
	aim_player_at(game, Vector3(20.6, game.active_layout.CLOUD_ARENA_Y + 3.74, -124.0), Vector3(-4.0, game.active_layout.CLOUD_ARENA_Y + 1.6, -126.5), true)
	await snap(out_dir, "v091_01_fortress_2f_balcony.png")

	# 2. Zero Dam 68m Underground Floodway / Spillway Shortcut Tunnel interior looking toward central cyan vault alcove & East portal
	aim_player_at(game, Vector3(-16.5, game.active_layout.CLOUD_ARENA_Y + 0.06, -141.5), Vector3(12.0, game.active_layout.CLOUD_ARENA_Y + 1.55, -142.2), true)
	await snap(out_dir, "v091_02_dam_spillway_tunnel.png")

	# 3. Brakkesh Grand Dome Bathhouse (44, -28) sunlit 3/4 view showing ribbed dome, twin cupolas, teal tile frieze & grounded steps
	var bh_y: float = game.active_layout.height(44.0, -28.0)
	aim_player_at(game, Vector3(29.5, 0.0, -15.5), Vector3(44.0, bh_y + 3.8, -28.0), false)
	await snap(out_dir, "v091_03_brakkesh_grand_bathhouse.png")

	# 4. Cement Plant Climbable +4.2m Elevated Steel Sniper Catwalk & stair tower
	var cw_y: float = game.active_layout.height(-42.0, -54.0)
	aim_player_at(game, Vector3(-25.5, 0.0, -45.5), Vector3(-42.0, cw_y + 3.0, -54.5), false)
	await snap(out_dir, "v091_04_cement_elevated_catwalk.png")

	# 5. Live MandelBrick Decryption Station (position player right at station FIRST, then insert -> live Wave-1 word-shield interceptors!)
	var d_pos: Vector3 = game.mandel_event.decode_node.global_position
	aim_player_at(game, d_pos + Vector3(-5.8, 0.0, 5.2), d_pos + Vector3(0.0, 1.85, 0.0), false)
	game.mandel_event.pickup_brick()
	game.mandel_event.insert_brick()
	await frames(8)
	await snap(out_dir, "v091_05_mandel_decode_station.png")

	# 6. G.T.I. MandelBrick 3-Round English Cipher Decryption Terminal Modal
	game.mandel_event.open_cipher_modal()
	await snap(out_dir, "v091_06_mandel_cipher_modal.png")
	game.mandel_event.close_modal()
	await frames(4)

	# 7. Desert Wildlife Ecology Showcase on sunlit South Oasis sandy meadow (100% clear of camp display stand!)
	var cam_from := Vector3(-11.0, 0.0, 23.0)
	var cy0: float = game.active_layout.height(-15.5, 19.5)
	for da in game.wildlife.desert_animals:
		if da.kind == "camel" and da.idx == 8:
			da.pos = Vector3(-16.2, game.active_layout.height(-16.2, 18.8), 18.8)
			da.root.position = da.pos
			da.root.rotation.y = 0.72
			da.label.visible = true
		elif da.kind == "fennec" and da.idx == 0:
			da.pos = Vector3(-13.2, game.active_layout.height(-13.2, 18.4), 18.4)
			da.root.position = da.pos
			da.root.rotation.y = 2.45
			da.label.visible = true
		elif da.kind == "scarab" and da.idx == 12:
			da.pos = Vector3(-12.2, game.active_layout.height(-12.2, 20.4), 20.4)
			da.root.position = da.pos
			da.root.rotation.y = 1.65
			da.label.visible = true
	if not game.wildlife.desert_falcons.is_empty():
		var df0: Dictionary = game.wildlife.desert_falcons[0]
		(df0.node as Node3D).position = Vector3(-16.5, cy0 + 5.2, 13.8)
		(df0.node as Node3D).rotation.y = 0.75
		(df0.label as Label3D).visible = true
	aim_player_at(game, cam_from, Vector3(-14.6, cy0 + 1.45, 18.2), false)
	await snap(out_dir, "v091_07_desert_wildlife_oasis.png")

	# 8. First-Person 3D Weapon Charm Showcase ("非洲之心微钻" charm_heart_africa cleanly mounted under optic rail, zero hand clipping!)
	game.achievements.equip_charm("charm_heart_africa")
	await frames(4)
	aim_player_at(game, Vector3(0.0, 0.0, -78.0), Vector3(0.0, 12.0, -148.0), false)
	await snap(out_dir, "v091_08_ahsarah_weapon_charm.png")

	game.queue_free()
	await frames(2)
	print("CAPTURE_V091_DONE=8")
	quit(0)
