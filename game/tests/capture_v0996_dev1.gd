extends SceneTree
## v0.9.9.6_dev1 Dual-Backend Visual Audit Capture Suite (1280x720 — Forward+ & GL Compatibility):
## Captures ALL 6 upgraded PBR skeletal characters IN-ENGINE + 1:1 Lore Codex portrait hubs!

const MainScene = preload("res://main.tscn")

func wait_frames(n: int = 8):
	for _i in n:
		await process_frame
		await physics_frame

func grab(out_dir: String, fname: String):
	await wait_frames(10)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		var path := out_dir.path_join(fname)
		var err := img.save_png(path)
		print("CAPTURED ", path, " ok=", (err == OK), " size=", img.get_size())

func _find_bot_with_rig(game, rig_name: String):
	for zid in game.combat.troops.keys():
		for bot in game.combat.troops[zid]:
			if is_instance_valid(bot) and bot.find_child(rig_name, true, false) != null:
				return bot
	return null

func _frame_bot(cam: Camera3D, bot: Node3D, dist: float, cam_h: float, look_h: float, side_off: float = 0.25):
	# Freeze bot gently facing sun-lit front-3/4 toward camera so every armor plate, visor, face & prop reads crisply!
	var bp: Vector3 = bot.global_position
	var fwd: Vector3 = bot.global_transform.basis.z.normalized()
	var right: Vector3 = bot.global_transform.basis.x.normalized()
	cam.current = true
	cam.global_position = bp + fwd * dist + right * side_off + Vector3(0.0, cam_h, 0.0)
	cam.look_at(bp + Vector3(0.0, look_h, 0.0), Vector3.UP)

func _initialize():
	call_deferred("_run")

func _run():
	var out_dir := OS.get_environment("TEMP").path_join("v0996_dev1_shots")
	var tag := ""
	var uargs := OS.get_cmdline_user_args()
	for idx in uargs.size():
		if uargs[idx] == "--out-dir" and idx + 1 < uargs.size():
			out_dir = uargs[idx + 1]
		elif uargs[idx] == "--backend-tag" and idx + 1 < uargs.size():
			tag = uargs[idx + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var pfx := (tag + "_") if tag != "" else ""

	var game = MainScene.instantiate()
	game.qa_mode = true
	game.profile_path_override = "user://qa-v0996-dev1-cap.json"
	if FileAccess.file_exists(game.profile_path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile_path_override))
	root.add_child(game)
	await wait_frames(12)

	var cam := Camera3D.new()
	cam.fov = 46.0
	game.add_child(cam)

	# 1) Yanshan Normal Mode -> Vanguard Boss ('铁面词卫 · 雾隐先锋')
	game.start_action(true, "normal")
	await wait_frames(18)
	game.paused = true
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.hide()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.hide()
	var vb = _find_bot_with_rig(game, "VanguardBossRig")
	if is_instance_valid(vb):
		vb.rotation.y = deg_to_rad(25.0)
		if is_instance_valid(vb.shield_area):
			vb.shield_area.hide()
		_frame_bot(cam, vb, 3.65, 1.56, 1.38, 0.52)
		await grab(out_dir, pfx + "01_yanshan_vanguard_boss.png")

	# 2) Yanshan Confidential Mode -> Skyfall Overlord ('玄铁词尊 · 雾隐机关王')
	game.paused = false
	game.start_action(true, "confidential")
	await wait_frames(12)
	var ov = _find_bot_with_rig(game, "SkyfallOverlordRig")
	if is_instance_valid(ov):
		ov.force_land_skyfall()
		await wait_frames(8)
		game.paused = true
		ov.rotation.y = deg_to_rad(20.0)
		for sd in ov.multi_shields:
			if is_instance_valid(sd.area):
				sd.area.hide()
		_frame_bot(cam, ov, 5.45, 2.28, 2.05, 0.72)
		await grab(out_dir, pfx + "02_yanshan_skyfall_overlord.png")

	# 3-5) Ahsarah Fortress Normal Mode -> Ahsarah Guard, HAAVK Trooper, Captain Saeed!
	game.paused = false
	game.rules.unlock_map("ahsarah")
	game.switch_map("ahsarah")
	await wait_frames(8)
	game.start_action(true, "normal")
	await wait_frames(20)
	game.paused = true
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.hide()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.hide()

	var ag = _find_bot_with_rig(game, "AhsarahGuardRig")
	if is_instance_valid(ag):
		ag.rotation.y = deg_to_rad(18.0)
		if is_instance_valid(ag.shield_area):
			ag.shield_area.hide()
		_frame_bot(cam, ag, 2.65, 1.24, 1.06, 0.36)
		await grab(out_dir, pfx + "03_ahsarah_guard.png")

	var hk = _find_bot_with_rig(game, "HaavkTrooperRig")
	if is_instance_valid(hk):
		hk.rotation.y = deg_to_rad(18.0)
		if is_instance_valid(hk.shield_area):
			hk.shield_area.hide()
		_frame_bot(cam, hk, 2.75, 1.26, 1.08, 0.36)
		await grab(out_dir, pfx + "04_ahsarah_haavk_trooper.png")

	var saeed = _find_bot_with_rig(game, "CaptainSaeedRig")
	if is_instance_valid(saeed):
		saeed.rotation.y = deg_to_rad(18.0)
		if is_instance_valid(saeed.shield_area):
			saeed.shield_area.hide()
		_frame_bot(cam, saeed, 3.25, 1.48, 1.28, 0.44)
		await grab(out_dir, pfx + "05_ahsarah_boss_saeed.png")

	# 6) Ahsarah Fortress Confidential Mode -> Warlord Reis ('阿萨拉军阀·雷斯')
	game.paused = false
	game.start_action(true, "confidential")
	await wait_frames(12)
	var reis = _find_bot_with_rig(game, "WarlordReisRig")
	if is_instance_valid(reis):
		reis.force_land_skyfall()
		await wait_frames(8)
		game.paused = true
		reis.rotation.y = deg_to_rad(18.0)
		for sd in reis.multi_shields:
			if is_instance_valid(sd.area):
				sd.area.hide()
		_frame_bot(cam, reis, 4.45, 2.02, 1.78, 0.56)
		await grab(out_dir, pfx + "06_ahsarah_boss_reis.png")

	# 7-8) Lore Codex Hubs showing 1:1 Studio-Matched Official Portraits!
	game.paused = false
	game._end_run(false)
	await wait_frames(6)
	game.rules.unlock_map("ahsarah")
	game.rules.inc_lore_stat("camps_cleared_yanshan", 2)
	game.rules.inc_lore_stat("ironface_defeats", 1)
	game.rules.inc_lore_stat("overlord_defeats", 1)
	game.rules.inc_lore_stat("warden_defeats", 1)
	game.rules.inc_lore_stat("saeed_defeats", 1)
	game.rules.inc_lore_stat("reis_defeats", 1)
	game.lore_codex.open("ahsarah")
	await grab(out_dir, pfx + "07_codex_ahsarah_hub.png")
	game.lore_codex.open("mistbound")
	await grab(out_dir, pfx + "08_codex_mistbound_hub.png")

	game.queue_free()
	await process_frame
	print("CAPTURE_V0996_DEV1_DONE")
	quit(0)
