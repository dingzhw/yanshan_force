extends SceneTree
## Capture 720p in-engine screenshots of v0.7.2 Compendium, Backpack, and 3D Relic Showcase Inspector.

var out_dir: String = ""
var game


func _initialize():
	call_deferred("_run")


func _arg_val(flag: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == flag:
			return args[i + 1]
	return fallback


func _snap(filename: String):
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var full := out_dir.path_join(filename)
	img.save_png(full)
	print("CAPTURE_V072 ", filename, " ", RenderingServer.get_current_rendering_method())


func _run():
	out_dir = _arg_val("--out-dir", "docs/v072-review")
	game = load("res://main.tscn").instantiate()
	game.qa_mode = true
	root.add_child(game)
	for _i in 4:
		await process_frame

	# Unlock a realistic showcase mix of Tier 6, Tier 5, and Tier 4 treasures in Compendium!
	game.rules.profile.collection = [
		"越窑秘色青瓷盏", "烟山千年紫芝王", "诚庄先民双龙玉璧", "相控阵超算雷达心", "烟山之心·赤金龙印",
		"烟山古铜虎符", "特级金质勋章", "量子词典原型机", "烟山先民竹简", "望稻亭鎏金香炉",
		"军用黑匣子", "烟霞岩画残拓", "古樟祈福银锁", "先民青铜茶铫"
	]
	game.rules.profile.red_extracted = 5
	game.rules.profile.gold_extracted = 6
	game.rules.profile.best_haul = 2480
	game.rules.profile.best_item_title = "烟山之心·赤金龙印"
	game.rules.profile.best_item_value = 1313

	# 1) Camp Bilingual Treasure Compendium ('烟山奇珍图鉴')
	game.loot_ui.open_compendium()
	await _snap("compendium-v072.png")
	game.loot_ui.close_compendium()

	# 2) Start run & populate [B] Tactical Backpack with mixed T1-T6 treasures
	game.start_action(false)
	for _i in 4:
		await physics_frame
	game.rules.bag.clear()
	var bag_samples := [
		game.Rules.LOOT_TABLE[6][2],  # 双龙玉璧
		game.Rules.LOOT_TABLE[6][4],  # 赤金龙印
		game.Rules.LOOT_TABLE[6][0],  # 越窑秘色青瓷盏
		game.Rules.LOOT_TABLE[5][0],  # 古铜虎符
		game.Rules.LOOT_TABLE[4][2],  # 军用黑匣子
		game.Rules.LOOT_TABLE[4][4],  # 古樟祈福银锁
		game.Rules.LOOT_TABLE[3][0],  # 加密无线电台
		game.Rules.LOOT_TABLE[2][3],  # 烟山手工折扇
	]
	for s in bag_samples:
		var it: Dictionary = s.duplicate(true)
		it["cond"] = "极品孤本" if int(it.rarity) >= 5 else "崭新"
		game.rules.bag.append(it)
	game.loot_ui.open_backpack()
	await _snap("backpack-v072.png")
	game.loot_ui.close_backpack()

	# 3) Interactive [I] 3D Showcase Close-Ups (clean player default framing!)
	var showcase_items := [
		["inspect-jade-bi.png", game.Rules.LOOT_TABLE[6][2], 0.30, 0.20, 1.62],
		["inspect-seal.png", game.Rules.LOOT_TABLE[6][4], 0.42, 0.26, 1.56],
		["inspect-celadon.png", game.Rules.LOOT_TABLE[6][0], 0.35, 0.32, 1.56],
		["inspect-blackbox.png", game.Rules.LOOT_TABLE[4][2], 0.45, 0.24, 1.58],
	]
	for spec in showcase_items:
		var it: Dictionary = spec[1].duplicate(true)
		it["cond"] = "极品孤本" if int(it.rarity) >= 5 else "崭新"
		game.loot_ui.open_inspect_item(it)
		game.loot_ui.inspect_auto_spin = false
		game.loot_ui.inspect_yaw = float(spec[2])
		game.loot_ui.inspect_pitch = float(spec[3])
		game.loot_ui.inspect_cam_dist = float(spec[4])
		game.loot_ui._update_inspect_camera()
		await _snap(str(spec[0]))
		game.loot_ui.close_inspect()

	game.queue_free()
	await process_frame
	quit(0)
