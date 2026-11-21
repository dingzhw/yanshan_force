extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func verify(ok: bool, text: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", text)

func distance_for(owned: Array) -> float:
	game.rules.profile.owned = owned
	game.player.clear_movement_input()
	game.player.position = Vector3(0, 0.1, 4.5)
	game.player.yaw = 0
	for i in 20: await physics_frame
	var start = game.player.position
	game.player.held_keys[KEY_W] = true
	for i in 60: await physics_frame
	game.player.clear_movement_input()
	return start.distance_to(game.player.position)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# v0.8.1 #15: Practice Range ('自由靶场') strictly forbids looting & hides field supply/world loot
	game.start_action(false)
	var hidden_practice_loot: bool = (not game.pickup_nodes[0].visible) and (not game.crate_nodes[0].visible) and (not game.world_loot.loose_nodes[0].visible) and (not game.world_loot.nest_nodes[0].visible)
	verify(not game.rules.can_loot() and not game.rules.add_loot("forbidden", 50, 2) and hidden_practice_loot, "v0.8.1 #15: Practice Range hides all loot containers/world loot and blocks add_loot")

	# Normal Operation supply boxes, full-bag overflow swap & extraction accuracy threshold (#5)
	game.start_action(true, "normal")
	for i in 8:
		game.rules.add_loot("filled", 10, 1)
	var pickup = game.pickup_nodes[0]
	game.player.position = pickup.position + Vector3(0, 0.1, 1.2)
	await physics_frame
	game.interact()
	verify(game.cipher_terminal.busy and game.cipher_terminal.mode == "supply", "supply box opens word-unlock terminal even when bag is full")
	game.cipher_terminal.solve_all_for_qa()
	verify(game.cipher_terminal.unlocked and game.cipher_terminal.swap_button.visible and pickup.visible, "unlocked supply box preserves unclaimed loot and offers swap when bag is full")
	game.cipher_terminal.close()
	verify(game.rules.bag.size() == 8 and pickup.visible, "closing full-bag supply terminal keeps box on field until claimed")
	game.rules.bag.pop_back()
	game.interact()
	verify(game.rules.bag.size() == 8 and not pickup.visible, "reopening with free slot claims saved supply loot without re-spelling")
	game.cipher_terminal.close()
	game.interact()
	verify(game.rules.bag.size() == 8 and not game.cipher_terminal.busy, "collected supply box cannot be reopened or duplicated")

	# Test swapping lowest-value item directly inside CipherTerminal
	var pickup2 = game.pickup_nodes[1]
	game.player.position = pickup2.position + Vector3(0, 0.1, 1.2)
	await physics_frame
	game.interact()
	game.cipher_terminal.solve_all_for_qa()
	verify(game.cipher_terminal.swap_button.visible, "second supply box on full bag exposes lowest-item swap button")
	game.cipher_terminal.swap_button.pressed.emit()
	verify(game.rules.bag.size() == 8 and not pickup2.visible, "swapping lowest item claims supply loot and removes supply box")
	game.cipher_terminal.close()
	game.rules.bag[0] = {"title": "量子词典原型机", "value": 395, "rarity": 6}

	# v0.8.1 #5: Accuracy gate enforcement (Normal >= 60%, Confidential >= 80%)
	# 16 wrong + 15 right => accuracy 48% (< 60%), score = 290 >= 260, camps & boss cleared -> STILL BLOCKED!
	for i in 31:
		game.rules.open_question()
		game.rules.answer(i >= 16)
	game.rules.outposts_cleared = 2
	game.rules.boss_defeated = true
	verify(game.rules.score >= game.Rules.EXTRACTION_SCORE and not game.rules.crate_ready(1) and not game.rules.can_extract(), "v0.8.1 #5: 48%% accuracy blocks Normal extraction (< 60%% threshold) even with 260+ pts & boss cleared")
	# Raise accuracy past 60% (add 10 right => 25/41 = 61.0%) -> Normal extraction unlocks!
	for _ok in 10:
		game.rules.open_question()
		game.rules.answer(true)
	verify(game.rules.accuracy() >= 0.60 and game.rules.can_extract(), "v0.8.1 #5: reaching >=60%% accuracy unlocks Normal Operation extraction")
	game.player.position = game.exit_position
	game.interact()
	game.extraction_left = 0.01
	game._process(0.02)
	var banked = game.rules.profile.warehouse.size()
	verify(game.rules.phase == "result" and banked == 8, "extraction path banks loot once")
	verify("量子词典原型机" in game.rules.profile.collection, "legendary extracted item registers in camp trophy collection")
	game._end_run(true)
	verify(game.rules.profile.warehouse.size() == banked, "repeated settlement does not duplicate warehouse")
	game.rules.toggle_warehouse_lock(0) # Unlock auto-locked T6 Quantum Dictionary so legacy sell_all check sells it
	game._sell()
	var coins = game.rules.profile.coins
	game._sell()
	verify(coins > 0 and game.rules.profile.coins == coins, "warehouse sale transfers value only once")

	game.rules.profile.coins = 3000
	verify(not game.rules.purchase("magazine2"), "tier-2 drum magazine requires tier-1 magazine first")
	for id in ["red_dot", "magazine", "magazine2", "shield_core", "backpack", "medkit_pack", "forest_skin", "scout", "reward_point"]:
		game._buy(id)
	verify(game.rules.capacity() == 14 and game.rules.magazine() == 20 and game.rules.max_shield() == 60 and game.rules.starter_medkits() == 3, "all nine tactical upgrades apply their gameplay bonuses")
	verify(game.rules.profile.points == 1, "reward coupon increments recorded offline points")

	game.profile_path_override = "user://qa-next-stage-economy.json"
	game._save()
	var restored = load("res://scripts/main.gd").new()
	restored.profile_path_override = game.profile_path_override
	restored._load_profile()
	verify(restored.rules.profile.coins == game.rules.profile.coins and restored.rules.profile.owned == game.rules.profile.owned and restored.rules.profile.collection == game.rules.profile.collection, "restart restores currency, upgrades, mastery and collection")
	restored.free()

	game.start_action(false)
	verify(game.player.ammo == 20 and game.rules.capacity() == 14 and game.player.medkits == 3, "next deployment equips purchased upgrades")
	var visible_skin = false
	for mesh in game.player.weapon_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null and mesh.material_override.albedo_color == Color("376c55"):
			visible_skin = true
	verify(visible_skin, "forest skin changes the rendered weapon material")
	var plain = await distance_for([])
	var scout = await distance_for(["scout"])
	verify(scout > plain * 1.09 and scout < plain * 1.15, "scout upgrade increases actual movement by twelve percent")

	game.rules.profile.warehouse = [{"title": "saved", "value": 10, "rarity": 1}]
	var saved_coins = game.rules.profile.coins
	game.start_action(true, "normal")
	game.rules.add_loot("lost", 20, 2)
	game.time_left = 0.01
	game._process(0.02)
	verify(game.rules.bag.is_empty() and game.rules.profile.warehouse.size() == 1 and game.rules.profile.coins == saved_coins, "timeout clears carried loot and preserves previous progress")

	# v0.5.3 Gunsmith 2.0 & starter tactical kit checks
	game.rules.profile.coins = 5000
	for mod_id in ["scope_2x", "suppressor", "compensator", "angled_grip", "tactical_rig", "tactical_belt"]:
		game._buy(mod_id)
	verify(game.rules.active_optic() == "scope_2x" and game.rules.active_muzzle() == "compensator" and game.rules.active_grip() == "angled_grip", "buying Gunsmith 2.0 mods auto-equips each slot cleanly")
	verify(game.rules.equip_attachment("muzzle", "suppressor") and game.rules.active_muzzle() == "suppressor", "gunsmith allows switching equipped muzzle between compensator and suppressor")
	verify(game.rules.equip_attachment("muzzle", "suppressor") and game.rules.active_muzzle() == "", "clicking active attachment unequips it cleanly")
	game.rules.equip_attachment("muzzle", "suppressor")
	game.rules.profile.owned.erase("tactical_belt")
	game.rules.profile.coins = 0
	verify(game.rules.unlock_blueprint("tactical_belt") and ("tactical_belt" in game.rules.profile.owned), "Boss blueprint unlocks tactical_belt even with 0 coins")
	game.start_action(true)
	verify(game.player.reserve_ammo == 4 * game.rules.magazine() and game.player.grenades == 2 and game.player.stims == 2, "tactical_rig + tactical_belt grant 4 reserve mags, 2 smoke/EMP, and 2 stims in combat")
	var wv = game.player.weapon_view
	verify(wv.att_nodes["att_scope_2x"].visible and wv.att_nodes["att_suppressor"].visible and wv.att_nodes["att_angled_grip"].visible and not wv.att_nodes["att_compensator"].visible, "equipped Gunsmith 2.0 attachments render visibly on YS-04 carbine")
	game._end_run(false)

	# v0.8.0 7-Tier Rarity ('珍品·小金' T5, '传说·大金' T6, '旷世·大红' T7), 64 Collectibles, Calibration, Safe Box, Lock & Camp 3D Display Stand
	verify(game.Rules.RARITY_NAMES.has(7) and game.Rules.LOOT_TABLE[7].size() == 5 and game.Rules.LOOT_TABLE[5].size() == 6 and game.Rules.total_collectible_count() == 27 and game.Rules.total_catalog_count() == 64, "v0.8.0 defines 7-tier rarity with Small Gold (6), Big Gold (6), Mythic Red (5), 27 high collectibles and 64 total museum items")
	game.start_action(true, "normal")
	var seen_values := {}
	var mythic_sample: Dictionary = {}
	for sample_i in 30:
		var rolled_red: Dictionary = game.rules.roll_item_by_rarity(7)
		if rolled_red.get("title", "") == "烟山之心·赤金龙印":
			mythic_sample = rolled_red
		seen_values[int(rolled_red.get("value", 0))] = true
	if mythic_sample.is_empty():
		mythic_sample = game.rules.roll_item_by_rarity(7)
	verify(int(mythic_sample.get("rarity", 0)) == 7 and str(mythic_sample.get("en", "")) != "" and seen_values.size() >= 6, "Tier-7 Mythic Red items roll dynamic condition/appraisal valuations and bilingual metadata")

	verify(game.rules.add_loot_item(mythic_sample) and game.rules.add_loot("杂物测试", 18, 1), "add_loot_item inserts enriched Tier-7 item into raid bag")
	var dropped: Dictionary = game.rules.discard_bag_item(1)
	verify(str(dropped.get("title", "")) == "杂物测试" and game.rules.bag.size() == 1, "discard_bag_item removes selected bag slot cleanly")

	while game.rules.score < game.Rules.EXTRACTION_SCORE:
		game.rules.open_question()
		game.rules.answer(true)
	game.rules.outposts_cleared = 2
	game.rules.boss_defeated = true
	var prev_red_cnt := int(game.rules.profile.get("red_extracted", 0))
	game.player.position = game.exit_position
	game.interact()
	game.extraction_left = 0.01
	game._process(0.02)
	verify(int(game.rules.profile.get("red_extracted", 0)) == prev_red_cnt + 1 and (mythic_sample.title in game.rules.profile.collection) and int(game.rules.profile.get("best_item_value", 0)) >= int(mythic_sample.value), "extracting a Tier-7 Crimson Red treasure increments red_extracted, unlocks Compendium, and updates best_item_value")

	# Auto-lock on Big Gold / Mythic Red + single-item sell + sell_unlocked_junk + Camp 3D Display Stand
	var red_wh_idx := -1
	for wi in game.rules.profile.warehouse.size():
		if int(game.rules.profile.warehouse[wi].get("rarity", 0)) == 7:
			red_wh_idx = wi
			break
	verify(red_wh_idx >= 0 and bool(game.rules.profile.warehouse[red_wh_idx].get("locked", false)), "extracted Tier-7 Mythic Red is auto-locked in warehouse against accidental sale")
	verify(game.rules.sell_warehouse_item(red_wh_idx) == 0, "locked warehouse treasure refuses single-item sale")
	game.rules.profile.warehouse.append(game.rules._enrich_loot_dict({"title": "粗陶米碗", "value": 22, "rarity": 1, "locked": false}))
	game.rules.profile.warehouse.append(game.rules._enrich_loot_dict({"title": "端溪雕云古砚", "value": 192, "rarity": 4, "locked": false}))
	var coins_before_junk := int(game.rules.profile.coins)
	var junk_res: Dictionary = game.rules.sell_unlocked_junk(3)
	verify(int(junk_res.count) >= 1 and int(game.rules.profile.coins) == coins_before_junk + int(junk_res.coins), "sell_unlocked_junk sells only unlocked T1-T3 items and credits coins")
	var still_has_epic := false
	for wh_it in game.rules.profile.warehouse:
		if str(wh_it.get("title", "")) == "端溪雕云古砚":
			still_has_epic = true
	verify(still_has_epic, "sell_unlocked_junk preserves unlocked Epic/Gold/Red treasures")
	var epic_idx := -1
	for wi2 in game.rules.profile.warehouse.size():
		if str(game.rules.profile.warehouse[wi2].get("title", "")) == "端溪雕云古砚":
			epic_idx = wi2
			break
	var single_earned: int = game.rules.sell_warehouse_item(epic_idx)
	verify(single_earned == 192, "sell_warehouse_item sells a single unlocked treasure for its exact valuation")
	var pin_res: Dictionary = game.rules.toggle_display_stand(str(mythic_sample.title))
	game.refresh_camp_display_stand()
	var stand_meshes := 0
	for slot in game.camp_display_slots:
		if slot.mount.get_child_count() > 0:
			stand_meshes += 1
	verify(bool(pin_res.ok) and bool(pin_res.pinned) and stand_meshes == 1, "toggle_display_stand pins treasure and renders 3D collectible on Camp Display Stand")

	game.profile_path_override = "user://qa-v080-red-economy.json"
	game._save()
	var restored_v080 = load("res://scripts/main.gd").new()
	restored_v080.profile_path_override = game.profile_path_override
	restored_v080._load_profile()
	var kept_r7 := false
	for wh_it in restored_v080.rules.profile.warehouse:
		if int(wh_it.get("rarity", 0)) == 7 and bool(wh_it.get("locked", false)) and str(wh_it.get("en", "")) != "":
			kept_r7 = true
	verify(kept_r7 and int(restored_v080.rules.profile.get("red_extracted", 0)) == prev_red_cnt + 1 and (str(mythic_sample.title) in restored_v080.rules.profile.display_stand), "save/load preserves Tier-7 rarity==7, lock flag, red_extracted and Camp Display Stand")
	restored_v080.free()

	# Legacy schema_version=1 save auto-migration (old T5->T6, old T6->T7)
	var mig_rules = game.Rules.new()
	mig_rules.profile["schema_version"] = 1
	mig_rules.profile["warehouse"] = [
		{"title": "量子词典原型机", "value": 320, "rarity": 5},
		{"title": "越窑秘色青瓷盏", "value": 640, "rarity": 6}
	]
	mig_rules.migrate_legacy_items()
	verify(int(mig_rules.profile.warehouse[0].rarity) == 6 and int(mig_rules.profile.warehouse[1].rarity) == 7 and bool(mig_rules.profile.warehouse[1].locked), "v0.8.0 migrates legacy schema v1 warehouse items from T5/T6 cleanly to T6/T7 with auto-lock")

	# Confidential Operation 80% accuracy gate check (#5)
	var conf_gate = game.Rules.new()
	conf_gate.start_run(true, "confidential")
	for gi in 10:
		conf_gate.open_question()
		conf_gate.answer(gi >= 3) # 7/10 = 70%
	conf_gate.score = 270
	conf_gate.outposts_cleared = 2
	conf_gate.boss_defeated = true
	verify(not conf_gate.can_extract(), "v0.8.1 #5: 70%% accuracy blocks Confidential extraction (< 80%% threshold)")
	for _ok2 in 5:
		conf_gate.open_question()
		conf_gate.answer(true) # 12/15 = 80%
	verify(conf_gate.can_extract(), "v0.8.1 #5: reaching >=80%% accuracy unlocks Confidential extraction")

	# 2-Slot Encrypted Safe Box survives failed run while regular bag clears
	game.start_action(true, "confidential")
	var sb_wh_before: int = game.rules.profile.warehouse.size()
	game.rules.add_loot_item(game.rules.roll_item_by_rarity(7))
	game.rules.add_loot_item(game.rules.roll_item_by_rarity(5))
	game.rules.add_loot_item(game.rules.roll_item_by_rarity(1))
	verify(game.rules.move_bag_to_safe_box(0) and game.rules.move_bag_to_safe_box(0) and not game.rules.move_bag_to_safe_box(0), "Encrypted Safe Box accepts up to 2 items and rejects a 3rd")
	game._end_run(false, "QA SafeBox Failure Check")
	verify(game.rules.bag.is_empty() and game.rules.safe_box.is_empty() and game.rules.profile.warehouse.size() == sb_wh_before + 2 and game.rules.last_saved_safe_box_count == 2, "failed run clears regular bag while permanently banking both Encrypted Safe Box items")

	# Monte Carlo 2000-roll drop calibration check (#6 Normal vs Confidential, #9 7-tier ascending curve, #10 zero open-road Big Gold/Red)
	var mc_rules = game.Rules.new()
	mc_rules.loot_rng.seed = 20261120
	var c_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0}
	var n_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0}
	for _mc in 2000:
		c_counts[mc_rules.roll_calibrated_rarity(true, "standard", true)] += 1
		n_counts[mc_rules.roll_calibrated_rarity(false, "standard", true)] += 1
	var c_red_pct: float = float(c_counts[7]) / 2000.0
	var c_bg_pct: float = float(c_counts[6]) / 2000.0
	var c_sg_pct: float = float(c_counts[5]) / 2000.0
	var n_red_pct: float = float(n_counts[7]) / 2000.0
	var n_bg_pct: float = float(n_counts[6]) / 2000.0
	verify(c_red_pct >= 0.010 and c_red_pct <= 0.034 and c_bg_pct >= 0.032 and c_bg_pct <= 0.072 and c_sg_pct >= 0.058 and c_sg_pct <= 0.108, "Confidential standard Monte Carlo matches ~2%% Red / ~5%% Big Gold / ~8%% Small Gold (got %.1f%%/%.1f%%/%.1f%%)" % [c_red_pct * 100.0, c_bg_pct * 100.0, c_sg_pct * 100.0])
	verify(c_counts[7] < c_counts[6] and c_counts[6] < c_counts[5] and c_counts[5] < c_counts[4] and c_counts[4] < c_counts[3] and c_counts[3] < c_counts[2], "Confidential rarity counts strictly ascend from Red -> Big Gold -> Small Gold -> Purple -> Blue -> Green")
	verify(n_red_pct < 0.005 and n_bg_pct < c_bg_pct * 0.45, "Normal mode Big Gold & Red odds are clearly lower than Confidential (Normal %.2f%%/%.2f%%)" % [n_red_pct * 100.0, n_bg_pct * 100.0])
	var open_high_violations := 0
	for _ol in 300:
		if mc_rules.roll_calibrated_rarity(true, "loose_open", true) >= 5:
			open_high_violations += 1
		if mc_rules.roll_calibrated_rarity(false, "loose_open", true) >= 4:
			open_high_violations += 1
	verify(open_high_violations == 0, "open-road loose spawns roll ZERO Gold/Red across 600 Normal+Confidential samples")

	# v0.8.0 64 Unique Sculpted PBR Collectibles & Studio Icons Verification
	var seen_art_ids := {}
	var missing_meshes := 0
	var missing_icons := 0
	for r_key in game.Rules.LOOT_TABLE.keys():
		for entry in game.Rules.LOOT_TABLE[r_key]:
			var aid: String = game.LootUI.resolve_art_id(entry)
			seen_art_ids[aid] = true
			if game.LootUI.get_collectible_mesh(entry) == null:
				missing_meshes += 1
			if game.LootUI.load_collectible_icon(entry) == null:
				missing_icons += 1
	verify(seen_art_ids.size() == 64 and missing_meshes == 0 and missing_icons == 0, "v0.8.0 maps all 64 collectibles to unique sculpted 3D meshes and 2D studio icons (%d unique, %d missing mesh, %d missing icon)" % [seen_art_ids.size(), missing_meshes, missing_icons])
	var alias_ok: bool = (
		game.LootUI.resolve_art_id({"title": "光学测距模块", "icon": "lens"}) == "rangefinder"
		and game.LootUI.resolve_art_id({"title": "军规夜视镜片", "icon": "lens"}) == "nvg_lens"
		and game.LootUI.resolve_art_id({"title": "竹海古玉残片", "icon": "jade"}) == "jade_piece"
		and game.LootUI.resolve_art_id({"title": "诚庄先民双龙玉璧", "icon": "jade"}) == "jade_bi"
		and game.LootUI.resolve_art_id({"title": "古樟祈福银锁", "icon": "badge"}) == "silver_lock"
		and game.LootUI.resolve_art_id({"title": "望稻亭鎏金香炉", "icon": "kettle"}) == "censer"
	)
	verify(alias_ok, "v0.8.0 resolves legacy saved item titles cleanly to their distinct sculpted art IDs")
	game.loot_ui.open_inspect_item(game.Rules.LOOT_TABLE[7][2])
	var insp_has_glb: bool = false
	for ch in game.loot_ui.inspect_turntable.find_children("*", "MeshInstance3D", true, false):
		if ch.mesh == game.LootUI.get_collectible_mesh("jade_bi"):
			insp_has_glb = true
	verify(game.loot_ui.busy_inspect and insp_has_glb, "3D Relic Showcase Inspector mounts the sculpted Twin-Dragon Jade Bi mesh cleanly")
	game.loot_ui.close_inspect()

	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("ECONOMY_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
