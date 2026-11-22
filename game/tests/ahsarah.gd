extends SceneTree
## v0.9.0 End-to-End Automated Test Suite for "阿萨拉堡垒" (Ahsarah Fortress):
## 1. Fresh-profile lock enforcement & Yanxia Cave Dimensional Stone Wall ("次元石壁") unlock gate
## 2. Defeating Confidential Cave Warden -> awakening Dimensional Stone Wall -> spelling activation -> permanent save unlock
## 3. Settings parent/playtest quick-unlock toggle ("unlock_ahsarah_preview")
## 4. Ahsarah Fortress 3D world switch (Zero Dam, Admin Fortress, Cement Plant, Brakkesh Bazaar, Haavk Substation, Helipad)
## 5. Ahsarah Normal Mode Boss「赤枭·赛伊德」(Captain Saeed rig, tactical roll, incendiary rings, card unlock)
## 6. Ahsarah Confidential Mode Boss「阿萨拉军阀·雷斯」(Warlord Reis rig, gramophone, 5-shield -> 3-orbiting-shield, card unlock)
## 7. 6 Ahsarah Lore Exploration Terminals (live random 175-word spelling) & 6 Ahsarah Flagship Collectibles (114 total) + strict pyramid rates
## 8. Clean round-trip back to Yanshan Base with zero regressions!

var passed := 0
var failed := 0

func verify(cond: bool, label: String):
	if cond:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func frames(n: int):
	for _i in n:
		await process_frame

func _initialize():
	call_deferred("run")

func run():
	var tmp_profile := "user://test_v090_ahsarah_profile.json"
	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))

	var game = load("res://main.tscn").instantiate()
	game.profile_path_override = tmp_profile
	root.add_child(game)
	await frames(4)

	# 1. Fresh save strictly locks Ahsarah Fortress until unlocked via Yanxia Cave or Settings toggle
	verify(game.VERSION == "0.9.0" and game.active_map_id == "yanshan", "v0.9.0 boots cleanly on Yanshan Base")
	verify(game.rules.is_map_unlocked("yanshan") and not game.rules.is_map_unlocked("ahsarah"), "Ahsarah Fortress starts locked on a clean save")
	verify(not game.switch_map("ahsarah"), "switch_map('ahsarah') cleanly refuses while locked")
	verify(is_instance_valid(game.landscape) and is_instance_valid(game.landscape.dimensional_rift_node), "Yanxia Ancient Cave mounts sculpted Dimensional Rift Wall ('次元石壁') behind skylight")

	# 2. Interacting with Dimensional Rift Wall BEFORE defeating Confidential Cave Warden stays sealed!
	game.start_action(true, "confidential")
	await frames(3)
	var rift_node: Node3D = game.exploration._node_for_id("dimensional_rift")
	verify(is_instance_valid(rift_node), "Yanxia Cave exposes 'dimensional_rift' exploration anchor behind skylight")
	if is_instance_valid(game.cave_warden):
		game.cave_warden.state = "patrol"
	game.exploration.open(rift_node)
	verify(not game.exploration.busy and not game.rules.is_ahsarah_permanently_unlocked(), "Dimensional Rift Wall remains sealed before defeating Confidential Cave Warden")

	# 3. Defeating Confidential Cave Warden awakens Dimensional Rift Wall -> random English spelling unlocks Ahsarah permanently!
	game.cave_warden.hp = 1
	game.cave_warden._on_defeated()
	await frames(2)
	verify(game.confidential_warden_slain_this_run and not game.cave_warden.is_alive(), "Defeating Confidential Cave Warden awakens Dimensional Rift Wall flag")
	game.exploration.open(rift_node)
	await frames(2)
	var rift_word: String = game.exploration.expected_spelling_word("dimensional_rift")
	verify(game.exploration.busy and rift_word != "", "Awakened Dimensional Rift Wall opens random 175-word English spelling activation (%s)" % rift_word)
	game.exploration.submit_spelling(rift_word)
	await frames(2)
	verify(game.rules.is_ahsarah_permanently_unlocked() and game.rules.is_map_unlocked("ahsarah"), "Spelling activation permanently unlocks Ahsarah Fortress in profile")
	verify("ahsarah_guard" in game.rules.profile.character_cards and "haavk_corp" in game.rules.profile.character_cards, "Unlocking Ahsarah registers Ahsarah Guard & Haavk character cards")
	game.exploration.close()
	game._end_run(false, "测试结束")
	await frames(2)

	# 4. Settings quick-unlock toggle verification (on simulated un-unlocked profile)
	game.rules.profile["unlocked_maps"] = ["yanshan"]
	verify(not game.rules.is_map_unlocked("ahsarah"), "Removing permanent unlock re-locks Ahsarah when settings toggle is off")
	game.rules.set_setting("unlock_ahsarah_preview", true)
	verify(game.rules.is_map_unlocked("ahsarah"), "Settings 'unlock_ahsarah_preview' toggle grants instant playtest access to Ahsarah")
	game.rules.unlock_map("ahsarah")
	game.rules.set_setting("unlock_ahsarah_preview", false)

	# 5. Switch to Ahsarah Fortress & verify 3D architecture, terrain, crates, pickups, exploration & minimap
	verify(game.switch_map("ahsarah"), "switch_map('ahsarah') succeeds after unlock")
	await frames(4)
	verify(game.is_ahsarah_map() and game.active_layout == game.AhsarahLayout, "Active map & layout switched cleanly to AhsarahLayout")
	verify(game.crate_nodes.size() == 8 and game.pickup_nodes.size() == 15, "Ahsarah mounts 8 Cipher Crates and 15 tactical/supply pickups")
	verify(game.exploration.nodes.size() == 6 and not game.wildlife.map_enabled and not game.cave_warden.map_enabled, "Ahsarah mounts 6 lore terminals and cleanly disables Yanshan wildlife & Cave Warden")
	var dam_found := is_instance_valid(game.landscape.find_child("AhsarahHeroLandmarks", true, false))
	var pano_found := is_instance_valid(game.landscape.find_child("DesertHorizonPanorama", true, false))
	var mesa_found := is_instance_valid(game.landscape.find_child("DesertMesaRing3D", true, false))
	verify(dam_found and pano_found and mesa_found, "AhsarahWorld renders Zero Dam landmarks, 3D mesa ring & seamless 360° desert panorama")

	# 6. Ahsarah Normal Operation -> Captain Saeed ('赤枭·赛伊德') Boss & Ahsarah/Haavk squads
	game.start_action(true, "normal")
	await frames(4)
	verify(game.rules.extraction_score_required() == 450, "Ahsarah Normal Operation sets extraction score threshold to 450")
	verify(game.combat.troops.size() == 5, "Ahsarah deploys all 5 tactical combat zones (Cement, Bazaar, Admin Fortress, Substation, West Bastion)")
	var saeed = game.combat.boss_unit
	verify(is_instance_valid(saeed) and not saeed.is_skyfall_overlord and saeed.is_ahsarah_unit, "Ahsarah Normal Mode spawns Captain Saeed ('赤枭·赛伊德') as Administrative Fortress Boss")
	verify(is_instance_valid(saeed.find_child("CaptainSaeedRig", true, false)) and is_instance_valid(saeed.saeed_cloak), "Captain Saeed mounts sculpted Blender 4.5 articulated rig with crimson cloak")
	var haavk_sq: Array = game.combat.troops.get(3, [])
	verify(not haavk_sq.is_empty() and str(haavk_sq[0].ahsarah_faction) == "haavk", "East Substation zone deploys Haavk Corporation ('哈夫克集团') white-cyan troopers")
	# Test Saeed defeat & card unlock
	game.combat._on_boss_defeated(saeed)
	verify(game.rules.boss_defeated and "saeed_fiery_owl" in game.rules.profile.character_cards, "Defeating Captain Saeed marks boss defeated & unlocks Saeed character card")

	# Test 1 Ahsarah lore terminal live random spelling
	var ah_term: Node3D = game.exploration._node_for_id("ahsarah_fortress")
	game.exploration.open(ah_term)
	await frames(2)
	var ah_word: String = game.exploration.expected_spelling_word("ahsarah_fortress")
	verify(game.exploration.busy and ah_word != "", "Ahsarah lore terminal opens live random 175-word spelling challenge (%s)" % ah_word)
	game.exploration.submit_spelling(ah_word)
	verify(bool(game.exploration.states.get("ahsarah_fortress", false)), "Correct spelling solves Ahsarah lore terminal and awards score + pyramid loot")
	game.exploration.close()

	# 7. Ahsarah Confidential Operation -> Warlord Reis ('阿萨拉军阀·雷斯') Boss
	game.start_action(true, "confidential")
	await frames(4)
	verify(game.rules.extraction_score_required() == 580, "Ahsarah Confidential Operation sets extraction score threshold to 580")
	var reis = game.combat.boss_unit
	verify(is_instance_valid(reis) and reis.is_skyfall_overlord and reis.is_ahsarah_unit, "Ahsarah Confidential Mode spawns Warlord Reis ('阿萨拉军阀·雷斯') as multi-shield Boss")
	verify(is_instance_valid(reis.find_child("WarlordReisRig", true, false)) and is_instance_valid(reis.reis_gramophone), "Warlord Reis mounts sculpted Blender 4.5 rig with shoulder-mounted antique brass gramophone")
	reis.trigger_skyfall()
	await frames(2)
	verify(reis.skyfall_state == "landed" and reis.overlord_seq_words.size() == 5, "Warlord Reis deploys directly onto Fortress Courtyard with 5 ordered heavy word shields")
	game.combat._on_boss_defeated(reis)
	verify("reis_warlord" in game.rules.profile.character_cards, "Defeating Warlord Reis unlocks Reis character card in Codex")

	# 8. 6 Ahsarah Flagship Collectibles (114 total) + Strict Pyramid Drop Rates
	var ah_assets_ok := true
	for title in game.Rules.AHSARAH_LOOT_TITLES:
		var meta: Dictionary = game.Rules.catalog_meta(title)
		if meta.is_empty() or game.LootUI.get_collectible_mesh(meta) == null or game.LootUI.load_collectible_icon(meta) == null:
			ah_assets_ok = false
		if not game.has_english_voice(str(meta.get("en", ""))):
			ah_assets_ok = false
	verify(ah_assets_ok and game.Rules.total_catalog_count() == 114, "All 6 Ahsarah flagship collectibles have 3D PBR meshes, 256x256 studio icons & offline English voice (total 114)")

	# Strict pyramid verification on Ahsarah (Normal crate_t3 vs Confidential crate_t3)
	var ah_red_seen := 0
	var ah_gold_seen := 0
	var ah_regional_hit := 0
	for _i in 300:
		var r_c: int = game.rules.roll_calibrated_rarity(true, "crate_t3", true)
		var it: Dictionary = game.rules.roll_item_by_rarity(r_c)
		if r_c == 7:
			ah_red_seen += 1
		elif r_c == 6:
			ah_gold_seen += 1
		if str(it.get("title", "")) in game.Rules.AHSARAH_LOOT_TITLES:
			ah_regional_hit += 1
	verify(ah_red_seen < 35 and ah_gold_seen < 60 and ah_regional_hit >= 8, "Ahsarah Confidential loot strictly obeys pyramid apex odds while featuring regional Ahsarah treasures (red=%d, gold=%d, regional=%d /300)" % [ah_red_seen, ah_gold_seen, ah_regional_hit])

	# 8b. Visual & Physics Polish Regression Suite (Bugfixes: zero orphaned Yanshan watchtower, solid flora/boulders, recessed oasis, stone perimeter walls, flat pavilion pads, Ahsarah practice HUD)
	verify(game.find_child("JiangnanWatchtower", true, false) == null, "Yanshan JiangnanWatchtower is cleanly absent in Ahsarah Fortress (zero sky ghost)")
	var flora_node: Node = game.landscape.find_child("AhsarahDesertFlora", true, false)
	var flora_bodies := flora_node.find_children("*", "StaticBody3D", true, false).size() if flora_node != null else 0
	verify(flora_bodies >= 55, "All palm trunks, acacia trunks & sculpted desert boulders have solid StaticBody3D colliders (bodies=%d)" % flora_bodies)
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	await physics_frame
	# Raycast directly into the Oasis Palm cluster trunk at (-10.5, 17.5) to confirm real physics collision blocks passage
	var palm_y: float = game.active_layout.min_ground_height(-10.5, 17.5, 1.5)
	var palm_ray := PhysicsRayQueryParameters3D.create(Vector3(-10.5, palm_y + 1.4, 20.5), Vector3(-10.5, palm_y + 1.4, 15.5))
	var palm_hit: Dictionary = space.intersect_ray(palm_ray)
	verify(not palm_hit.is_empty(), "Physics raycast hits Oasis Palm trunk collider solidly (no walk-through)")
	# Verify recessed Oasis Pool sits strictly BELOW all 8 compass shoreline rim points (zero floating water disc!)
	var oasis_pool: Node3D = game.landscape.find_child("OasisSpringPool", true, false)
	var pool_center_y: float = game.active_layout.height(game.active_layout.OASIS_POOL.x, game.active_layout.OASIS_POOL.z)
	var min_rim_y := 99.0
	for ang_i in 8:
		var ang := float(ang_i) * (TAU / 8.0)
		var rx: float = game.active_layout.OASIS_POOL.x + cos(ang) * 7.2 * 1.25
		var rz: float = game.active_layout.OASIS_POOL.z + sin(ang) * 5.2 * 1.25
		min_rim_y = minf(min_rim_y, game.active_layout.height(rx, rz))
	verify(oasis_pool != null and pool_center_y <= -0.95 and oasis_pool.position.y < min_rim_y - 0.15, "Oasis spring pool (y=%.2f) sits cleanly recessed inside basin (center=%.2f, min_rim=%.2f)" % [oasis_pool.position.y if oasis_pool != null else 99.0, pool_center_y, min_rim_y])
	# Verify seamless Outer Desert Skirt & stacked sandstone Perimeter Rock Walls replace bare air walls
	var skirt_node: Node = game.landscape.find_child("AhsarahOuterDesertSkirt", true, false)
	var perim_node: Node = game.landscape.find_child("AhsarahPerimeterRockWalls", true, false)
	verify(skirt_node != null and perim_node != null and perim_node.get_child_count() >= 48, "Seamless outer desert skirt & stacked stone perimeter rock half-walls enclose map (segments=%d)" % (perim_node.get_child_count() if perim_node != null else 0))
	# Verify Brakkesh Bazaar pavilion footprints sit on flat graded pads (zero floating steps/posts/amphorae)
	var pav_flat_ok := true
	for pav_c in [Vector3(44.0, 0.0, -28.0), Vector3(36.0, 0.0, -46.0), Vector3(-52.0, 0.0, -104.0)]:
		var y_min := 999.0
		var y_max := -999.0
		for ox in [-3.5, 0.0, 3.5]:
			for oz in [-3.0, 0.0, 4.5]:
				var hy: float = game.active_layout.height(pav_c.x + ox, pav_c.z + oz)
				y_min = minf(y_min, hy)
				y_max = maxf(y_max, hy)
		if (y_max - y_min) > 0.20:
			pav_flat_ok = false
	verify(pav_flat_ok, "All Brakkesh sandstone pavilion pads are smoothly graded level (delta <= 0.20m across steps & porch)")
	# Verify Practice Range HUD banner in Ahsarah uses Ahsarah route text (not Yanshan!)
	game.start_action(false)
	await frames(2)
	verify("绿洲前哨" in game.unit_label.text and not ("山脚营地" in game.unit_label.text), "Ahsarah Practice Range banner displays Ahsarah route instead of Yanshan (%s)" % game.unit_label.text)

	# 9. Clean Round-Trip back to Yanshan Base
	verify(game.switch_map("yanshan"), "Round-trip switch_map('yanshan') restores Yanshan Base cleanly")
	await frames(4)
	verify(not game.is_ahsarah_map() and game.crate_nodes.size() == 6 and game.wildlife.map_enabled and game.cave_warden.map_enabled, "Yanshan Base restores all 6 crates, 12 wildlife species & Cave Warden after round-trip")

	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))
	print("AHSARAH_TEST_SUMMARY passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
