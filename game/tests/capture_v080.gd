extends SceneTree

var game

func _initialize():
	call_deferred("run")

func _wait_render(frames_n: int = 4):
	for i in frames_n:
		await process_frame
	await RenderingServer.frame_post_draw

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await _wait_render(4)

	# Seed a rich realistic v0.8.0 player profile with T7 Red, T6 Big Gold, T5 Small Gold, and T1-T4 items
	game.rules.profile.coins = 680
	game.rules.profile.red_extracted = 2
	game.rules.profile.gold_extracted = 3
	game.rules.profile.small_gold_extracted = 4
	game.rules.profile.best_haul = 2480
	game.rules.profile.best_item_title = "烟山之心·赤金龙印"
	game.rules.profile.best_item_value = 1280
	game.rules.profile.collection = [
		"烟山之心·赤金龙印", "越窑秘色青瓷盏", "诚庄先民双龙玉璧",
		"量子词典原型机", "烟山古铜虎符", "望稻亭鎏金香炉",
		"海兽葡萄错银铜镜", "战备量子加密硬盘", "宜兴朱泥水平壶",
		"翡翠节节高玉佩", "复古黄铜旁轴相机", "御窑青花缠枝盏",
		"端溪雕云古砚", "青瓷蟾蜍水注"
	]
	game.rules.profile.warehouse = [
		game.rules._enrich_loot_dict({"title": "烟山之心·赤金龙印", "value": 1280, "rarity": 7, "cond": "极品孤本", "locked": true}),
		game.rules._enrich_loot_dict({"title": "越窑秘色青瓷盏", "value": 740, "rarity": 7, "cond": "崭新", "locked": true}),
		game.rules._enrich_loot_dict({"title": "望稻亭鎏金香炉", "value": 520, "rarity": 6, "cond": "标准", "locked": true}),
		game.rules._enrich_loot_dict({"title": "宜兴朱泥水平壶", "value": 284, "rarity": 5, "cond": "崭新", "locked": true}),
		game.rules._enrich_loot_dict({"title": "复古黄铜旁轴相机", "value": 276, "rarity": 5, "cond": "标准", "locked": true}),
		game.rules._enrich_loot_dict({"title": "翡翠节节高玉佩", "value": 262, "rarity": 5, "cond": "标准", "locked": false}),
		game.rules._enrich_loot_dict({"title": "端溪雕云古砚", "value": 198, "rarity": 4, "cond": "标准", "locked": false}),
		game.rules._enrich_loot_dict({"title": "机械铜壳怀表", "value": 124, "rarity": 3, "cond": "崭新", "locked": false}),
		game.rules._enrich_loot_dict({"title": "老式木算盘", "value": 28, "rarity": 1, "cond": "标准", "locked": false})
	]
	game.rules.profile.display_stand = [
		"烟山之心·赤金龙印",
		"宜兴朱泥水平壶",
		"复古黄铜旁轴相机",
		"翡翠节节高玉佩"
	]
	game.refresh_camp_display_stand()
	game._refresh_menu()
	await _wait_render(3)
	game._capture("06-camp-menu-v080.png")

	# 1) Camp Warehouse Vault Modal (single-sell, lock protection, sell-junk, 3D display stand tags)
	game.loot_ui.open_warehouse()
	await _wait_render(4)
	game._capture("01-warehouse-vault-v080.png")
	game.loot_ui.close_warehouse()

	# 2) 64-Item 7-Tier Compendium (showing T7 Red, T6 Big Gold, and brand-new T5 Small Gold!)
	game.loot_ui.open_compendium()
	await _wait_render(4)
	game._capture("05-compendium-64-v080.png")
	game.loot_ui.close_compendium()

	# 3) Camp 4-Slot 3D Display Stand Close-up in sunlit camp courtyard!
	game.start_action(false)
	await _wait_render(3)
	game.wildlife.frozen_for_capture = true
	var stand_pos: Vector3 = game.camp_display_stand.global_position
	var stand_fwd: Vector3 = game.camp_display_stand.global_transform.basis.z
	game.player.position = stand_pos + stand_fwd * 3.15 + Vector3(0, 0.05, 0)
	var look_dir: Vector3 = (stand_pos + Vector3(0, 1.15, 0)) - (game.player.position + Vector3(0, 1.55, 0))
	game.player.yaw = atan2(-look_dir.x, -look_dir.z)
	game.player.pitch = clampf(atan2(look_dir.y, Vector2(look_dir.x, look_dir.z).length()), -0.45, 0.45)
	game.player.rotation.y = game.player.yaw
	game.player.camera.rotation.x = game.player.pitch
	game.hud.hide()
	await _wait_render(5)
	game._capture("03-camp-display-stand-v080.png")
	game.hud.show()

	# 4) Clean Scenic Stream & Meadow View (zero permanent floating wildlife/flora labels & zero open-road sky beams!)
	game.wildlife.reset()
	game.wildlife.frozen_for_capture = true
	var creek_p := Vector3(13.2, 0.0, 7.6)
	game.player.position = game.Layout.on_ground(creek_p) + Vector3(0, 0.12, 0)
	game.player.yaw = -0.78
	game.player.pitch = -0.14
	game.player.rotation.y = game.player.yaw
	game.player.camera.rotation.x = game.player.pitch
	await _wait_render(5)
	game._capture("04-scenic-clean-wildlife-v080.png")

	# 5) [B] Tactical Backpack + 2-Slot Encrypted Safe Box ('加密安全箱')
	game.rules.safe_box = [
		game.rules._enrich_loot_dict({"title": "烟山之心·赤金龙印", "value": 1280, "rarity": 7, "cond": "极品孤本"}),
		game.rules._enrich_loot_dict({"title": "宜兴朱泥水平壶", "value": 284, "rarity": 5, "cond": "崭新"})
	]
	game.rules.bag = [
		game.rules._enrich_loot_dict({"title": "海兽葡萄错银铜镜", "value": 225, "rarity": 5, "cond": "标准"}),
		game.rules._enrich_loot_dict({"title": "战备量子加密硬盘", "value": 248, "rarity": 5, "cond": "崭新"}),
		game.rules._enrich_loot_dict({"title": "御窑青花缠枝盏", "value": 292, "rarity": 5, "cond": "标准"}),
		game.rules._enrich_loot_dict({"title": "端溪雕云古砚", "value": 195, "rarity": 4, "cond": "标准"}),
		game.rules._enrich_loot_dict({"title": "机械铜壳怀表", "value": 122, "rarity": 3, "cond": "标准"}),
		game.rules._enrich_loot_dict({"title": "老式木算盘", "value": 28, "rarity": 1, "cond": "标准"})
	]
	game.loot_ui.open_backpack()
	await _wait_render(4)
	game._capture("02-backpack-safebox-v080.png")
	game.loot_ui.close_backpack()

	print("CAPTURE_V080_DONE")
	game.queue_free()
	await process_frame
	quit(0)
