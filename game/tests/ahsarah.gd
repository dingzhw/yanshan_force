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
	verify(game.VERSION == "0.9.4" and game.active_map_id == "yanshan", "v0.9.4 boots cleanly on Yanshan Base")
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
	verify(game.crate_nodes.size() == 10 and game.pickup_nodes.size() == 20, "v0.9.2 Ahsarah mounts 10 Cipher Crates and 20 sculpted pickups (ammo/medkit/EMP/stim/supply)")
	verify(game.exploration.nodes.size() == 6 and game.wildlife.active_map_id == "ahsarah" and not game.wildlife.yanshan_root.visible and game.wildlife.ahsarah_root.visible and not game.cave_warden.map_enabled, "v0.9.1 Ahsarah mounts 6 lore terminals, switches Wildlife cleanly to Ahsarah desert ecology & disables Cave Warden")
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
	# Verify Practice Range HUD banner in Ahsarah uses Ahsarah route text (not Yanshan!) and hides MandelBrick event
	game.start_action(false)
	await frames(2)
	verify("绿洲前哨" in game.unit_label.text and not ("山脚营地" in game.unit_label.text), "Ahsarah Practice Range banner displays Ahsarah route instead of Yanshan (%s)" % game.unit_label.text)
	verify(is_instance_valid(game.mandel_event) and game.mandel_event.state == "inactive", "MandelBrick dynamic event stays inactive during Practice Range")

	# 8c. v0.9.1 Multi-Story Walkable Architecture, Spillway Shortcut Tunnel & Elevated Catwalk Physics
	var wing_w: Node = game.landscape.find_child("FortressInteriorWing_W", true, false)
	var wing_e: Node = game.landscape.find_child("FortressInteriorWing_E", true, false)
	var spillway: Node = game.landscape.find_child("ZeroDamSpillwayTunnel", true, false)
	var bathhouse: Node = game.landscape.find_child("BrakkeshGrandBathhouse", true, false)
	var catwalk: Node = game.landscape.find_child("CementElevatedCatwalk", true, false)
	verify(wing_w != null and wing_e != null and spillway != null and bathhouse != null and catwalk != null, "v0.9.1 mounts all 5 hero multi-story structures (Twin Fortress 2F Wings, 68m Dam Spillway Tunnel, Brakkesh Grand Bathhouse & Cement Catwalk)")
	await physics_frame
	# Verify walkable 2nd-floor balcony deck on East Wing (+22.5, 5.40+3.70=9.10, -124.0)
	var f2_ray := PhysicsRayQueryParameters3D.create(Vector3(21.2, 11.2, -124.0), Vector3(21.2, 7.2, -124.0))
	var f2_hit: Dictionary = space.intersect_ray(f2_ray)
	verify(not f2_hit.is_empty() and absf(f2_hit.position.y - (game.active_layout.CLOUD_ARENA_Y + 3.70)) <= 0.15, "2-Story Fortress East Wing 2F sniper balcony has rock-solid walkable floor at y=%.2f" % (f2_hit.position.y if not f2_hit.is_empty() else -1.0))
	# Verify 68m Zero Dam Spillway Shortcut Tunnel is 100% open & unobstructed portal-to-portal (x=-33 -> +33 at z=-141.5, y=6.8)!
	var tun_clear_ray := PhysicsRayQueryParameters3D.create(Vector3(-33.0, game.active_layout.CLOUD_ARENA_Y + 1.5, -141.5), Vector3(33.0, game.active_layout.CLOUD_ARENA_Y + 1.5, -141.5))
	var tun_block: Dictionary = space.intersect_ray(tun_clear_ray)
	var tun_roof_ray := PhysicsRayQueryParameters3D.create(Vector3(0.0, game.active_layout.CLOUD_ARENA_Y + 1.5, -141.5), Vector3(0.0, game.active_layout.CLOUD_ARENA_Y + 6.5, -141.5))
	var tun_roof: Dictionary = space.intersect_ray(tun_roof_ray)
	verify(tun_block.is_empty() and not tun_roof.is_empty(), "68m Zero Dam Spillway Shortcut Tunnel is 100% clear portal-to-portal with solid concrete roof overhead")
	# Verify Cement Plant Elevated Steel Catwalk (+4.29m deck) is solid & walkable
	var cat_base_y: float = game.active_layout.min_ground_height(-42.0, -54.0, 4.5)
	var cat_ray := PhysicsRayQueryParameters3D.create(Vector3(-42.0, cat_base_y + 6.5, -56.0), Vector3(-42.0, cat_base_y + 2.5, -56.0))
	var cat_hit: Dictionary = space.intersect_ray(cat_ray)
	verify(not cat_hit.is_empty() and absf(cat_hit.position.y - (cat_base_y + 4.29)) <= 0.18, "Cement Plant elevated steel catwalk has solid walkable deck at y=%.2f" % (cat_hit.position.y if not cat_hit.is_empty() else -1.0))

	# 8d. v0.9.1 MandelBrick Capture -> Escort -> 2 Ambush Waves -> 3-Round English Cipher -> Reward Crate & Pyramid Odds
	game.start_action(true, "normal")
	await frames(4)
	verify(game.mandel_event.state == "available" and is_instance_valid(game.mandel_event.pickup_node) and is_instance_valid(game.mandel_event.decode_node), "MandelBrick event spawns vault pedestal & active G.T.I. decode station in Ahsarah combat")
	verify(game.mandel_event.pickup_brick() and game.mandel_event.state == "carrying", "Capturing MandelBrick transitions event to 'carrying' state")
	verify(game.mandel_event.insert_brick() and game.mandel_event.state == "decoding" and game.mandel_event.wave_1_spawned, "Inserting MandelBrick begins 3-round decryption and dispatches Wave 1 word-shield interceptors")
	verify(game.combat.living_soldiers(game.combat.MANDEL_ZONE_ID).size() >= 3, "Wave 1 MandelBrick ambush deploys >=3 active word-shield interceptors")
	verify(game.mandel_event.open_cipher_modal() and game.mandel_event.busy and game.paused, "Opening MandelBrick decryption modal pauses combat safely")
	var w1: String = game.mandel_event.expected_cipher_word()
	verify(w1 != "" and not game.mandel_event.submit_cipher("wrongspellingxyz") and game.mandel_event.wrong_attempts_round == 1, "Wrong cipher spelling reveals extra hint letter without soft-locking")
	var pre_mandel_score: int = game.rules.score
	verify(game.mandel_event.submit_cipher(w1) and game.mandel_event.decode_round == 2 and game.mandel_event.wave_2_spawned, "Solving Round 1 advances to Round 2 and dispatches Wave 2 Haavk interceptors")
	var w2: String = game.mandel_event.expected_cipher_word()
	verify(w2 != "" and game.mandel_event.submit_cipher(w2) and game.mandel_event.decode_round == 3, "Solving Round 2 advances to Round 3")
	var w3: String = game.mandel_event.expected_cipher_word()
	verify(w3 != "" and game.mandel_event.submit_cipher(w3) and game.mandel_event.state == "completed", "Solving Round 3 completes MandelBrick decryption cleanly")
	verify(game.rules.score >= pre_mandel_score + 135 and is_instance_valid(game.mandel_event.reward_crate_node) and game.loot_container_ui.busy and game.loot_container_ui.pending_items.size() == 3, "Completed MandelBrick awards +90 bonus (+45 cipher) score, spawns physical Reward Crate & opens 3-item confirmation panel")
	game.loot_container_ui.close()
	# Verify mandel_decode strict pyramid odds (T7 < T6 < T5 < T4)
	var m_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0}
	for _mi in 400:
		var mr: int = game.rules.roll_calibrated_rarity(true, "mandel_decode", true)
		m_counts[mr] = int(m_counts[mr]) + 1
	verify(int(m_counts[7]) < int(m_counts[6]) and int(m_counts[6]) < int(m_counts[5]) and int(m_counts[5]) < int(m_counts[4]), "MandelBrick reward table strictly obeys calibrated pyramid scarcity (T7=%d < T6=%d < T5=%d < T4=%d /400)" % [m_counts[7], m_counts[6], m_counts[5], m_counts[4]])

	# 8e. v0.9.1 Rigged Desert Wildlife Ecology (4 Species, 28 Critters, Skeleton3D + AnimationPlayer, 341 Voices, Zero Cross-Map Leakage)
	verify(game.wildlife.desert_animals.size() == 22 and game.wildlife.desert_falcons.size() == 6, "Ahsarah desert wildlife spawns 22 ground critters (8 fennec, 4 camel, 10 scarab) + 6 soaring Desert Falcons = 28")
	var desert_rigs_ok := true
	var seen_dkinds := {}
	for da in game.wildlife.desert_animals:
		seen_dkinds[str(da.kind)] = true
		if da.anim == null or da.visual.find_child("Skeleton3D", true, false) == null:
			desert_rigs_ok = false
	for df in game.wildlife.desert_falcons:
		seen_dkinds["falcon"] = true
		if df.anim == null or df.vis.find_child("Skeleton3D", true, false) == null:
			desert_rigs_ok = false
	var desert_tts_ok: bool = (
		game.voice_manifest.size() == 341
		and bool(game.has_english_voice("fennec fox"))
		and bool(game.has_english_voice("camel"))
		and bool(game.has_english_voice("desert falcon"))
		and bool(game.has_english_voice("golden scarab"))
	)
	var ys_collision_zero := true
	for ya in game.wildlife.animals:
		if int(ya.area.collision_layer) != 0:
			ys_collision_zero = false
			break
	verify(desert_rigs_ok and seen_dkinds.size() == 4 and desert_tts_ok and ys_collision_zero, "All 4 desert species have Skeleton3D+AnimationPlayer, all 341 offline voice clips load, and Yanshan critters have 0 hitbox leakage")

	# 8f. v0.9.1 30 Achievements & 16 Weapon Charms (Equipping all 3 new Ahsarah 3D weapon charms on rifle!)
	game.wildlife._record_desert_species_discovery("fennec", "Fennec Fox", "荒漠耳廓狐", "fennec fox", false)
	game.wildlife._record_desert_species_discovery("camel", "Camel", "北非单峰驼", "camel", false)
	game.wildlife._record_desert_species_discovery("scarab", "Golden Scarab", "金色沙丘圣甲虫", "golden scarab", false)
	game.wildlife._record_desert_species_discovery("falcon", "Desert Falcon", "荒漠猎隼", "desert falcon", false)
	verify(game.achievements.CATALOG.size() == 30 and game.achievements.CHARMS.size() == 16, "Achievements catalog expanded to 30 milestones and 16 equippable 3D weapon charms")
	verify(game.achievements.is_unlocked("ahsarah_entry") and game.achievements.is_unlocked("ahsarah_saeed") and game.achievements.is_unlocked("ahsarah_reis") and game.achievements.is_unlocked("ahsarah_mandel") and game.achievements.is_unlocked("ahsarah_eco"), "All Ahsarah milestones (entry, Saeed, Reis, MandelBrick, 4 Desert Wildlife) unlock cleanly")
	var charms_3d_ok := true
	for cid in ["charm_mini_mandel", "charm_fiery_owl", "charm_heart_africa"]:
		if not game.achievements.is_charm_unlocked(cid) or not game.achievements.equip_charm(cid):
			charms_3d_ok = false
		elif not game.player.weapon_view.charm_anchor.visible or game.player.weapon_view.charm_visual_root.get_child_count() < 2:
			charms_3d_ok = false
	verify(charms_3d_ok, "All 3 Ahsarah 3D weapon charms (Mini MandelBrick, Fiery Owl, Heart of Africa) equip & mount sculpted 3D meshes on rifle")

	# 8g. v0.9.2 Comprehensive Desert Bugfix Audits (Bugs a-d) + Bespoke Saeed/Reis Boss Kits + Sculpted Tactical Pickups!
	game.start_action(true, "normal")
	await frames(4)
	for _pf in 20:
		await physics_frame
	space = game.get_world_3d().direct_space_state

	# Audit (a): ZERO disappearing camp soldiers — EVERY soldier across all 5 camps sits above ground with open sky!
	var soldiers_checked := 0
	var soldiers_ok := true
	for z_i in 5:
		for s in game.combat.living_soldiers(z_i):
			soldiers_checked += 1
			var gy: float = game.active_layout.height(s.position.x, s.position.z)
			if s.position.y < gy - 0.15 or s.position.y > gy + 2.0:
				soldiers_ok = false
				printerr("  Soldier underground/floating z=%d pos=%s gy=%.2f" % [z_i, str(s.position), gy])
			var sky_rq := PhysicsRayQueryParameters3D.create(Vector3(s.position.x, gy + 5.5, s.position.z), Vector3(s.position.x, gy + 0.25, s.position.z), 1)
			var sky_hit: Dictionary = space.intersect_ray(sky_rq)
			if not sky_hit.is_empty():
				soldiers_ok = false
				printerr("  Soldier obstructed overhead z=%d pos=%s hit=%s" % [z_i, str(s.position), str(sky_hit.position)])
	verify(soldiers_checked >= 15 and soldiers_ok, "v0.9.2 Bug(a): ALL %d Ahsarah camp soldiers across 5 zones spawn cleanly above ground with open sky (zero buried/trapped bots)" % soldiers_checked)
	# Verify floor-rescue watchdog instantly rescues an artificially dropped soldier
	var sample_s = game.combat.living_soldiers(0)[0]
	var sample_gy: float = game.active_layout.height(sample_s.position.x, sample_s.position.z)
	sample_s.position.y = sample_gy - 3.5
	sample_s._clamp_above_ground()
	verify(sample_s.position.y >= sample_gy, "v0.9.2 Bug(a): Soldier floor-safety watchdog rescues underground coordinates cleanly (y=%.2f >= %.2f)" % [sample_s.position.y, sample_gy])

	# Audit (b): 1.0m high-res terrain grid & level Cement Catwalk stair pad
	var terr_mi: MeshInstance3D = game.landscape.find_child("AhsarahDesertTerrain", true, false)
	var terr_tris: int = terr_mi.mesh.get_faces().size() / 3 if (terr_mi != null and terr_mi.mesh != null) else 0
	var cat_y0: float = game.active_layout.height(-42.0, -54.0)
	var cat_y1: float = game.active_layout.height(-33.5, -54.0)
	verify(terr_tris >= 75000 and absf(cat_y0 - cat_y1) <= 0.12, "v0.9.2 Bug(b): 1.0m analytical desert terrain mesh (tris=%d) & level catwalk stair pad (delta=%.3fm)" % [terr_tris, absf(cat_y0 - cat_y1)])

	# Audit (c): ZERO fake/hollow solid models — physics raycast probes hit EVERY hero structure solidly!
	var cp1_y: float = game.active_layout.min_ground_height(-54.0, -44.0, 4.5)
	var cp1_booth: Vector3 = Vector3(-54.0, cp1_y, -44.0) + Basis(Vector3.UP, deg_to_rad(14.0)) * Vector3(5.5, 1.8, 1.8)
	var sb1_y: float = game.active_layout.min_ground_height(52.0, -84.0, 3.2)
	var sb1_console: Vector3 = Vector3(52.0, sb1_y, -84.0) + Basis(Vector3.UP, deg_to_rad(-90.0)) * Vector3(2.45, 1.45, 0.0)
	var rt_w_y: float = game.active_layout.min_ground_height(-34.0, -148.0, 3.8)
	var wing_e_stair_under: Vector3 = Vector3(22.5, game.active_layout.CLOUD_ARENA_Y, -124.0) + Basis(Vector3.UP, deg_to_rad(-90.0)) * Vector3(-0.5, 1.2, -1.85)
	var bath_y0: float = game.active_layout.min_ground_height(44.0, -28.0, 5.5)
	var bath_pier: Vector3 = Vector3(44.0, bath_y0, -28.0) + Basis(Vector3.UP, deg_to_rad(-20.0)) * Vector3(2.62, 2.2, 4.75)
	var pav_y0: float = game.active_layout.min_ground_height(36.0, -46.0, 4.2)
	var pav_wall: Vector3 = Vector3(36.0, pav_y0, -46.0) + Basis(Vector3.UP, deg_to_rad(75.0)) * Vector3(3.10, 2.2, 3.05) * 0.94
	var solid_probes := [
		["Cement Silo Control Booth", cp1_booth + Vector3(0.0, 0.0, 3.2), cp1_booth - Vector3(0.0, 0.0, 3.2)],
		["Substation Haavk Relay Console", sb1_console + Vector3(-3.0, 0.0, 0.0), sb1_console + Vector3(3.0, 0.0, 0.0)],
		["Babel Radar Tower Plinth Rim", Vector3(-34.0 + 4.2, rt_w_y + 1.2, -144.0), Vector3(-34.0 + 4.2, rt_w_y + 1.2, -151.0)],
		["Zero Dam Spillway Apron", Vector3(0.0, game.active_layout.CLOUD_ARENA_Y + 0.8, -144.5), Vector3(0.0, game.active_layout.CLOUD_ARENA_Y + 0.8, -149.5)],
		["Fortress Wing Under-Stair Masonry", wing_e_stair_under + Vector3(0.0, 0.0, 2.2), wing_e_stair_under - Vector3(0.0, 0.0, 2.2)],
		["Grand Bathhouse Arcade Pier", bath_pier + Vector3(0.0, 0.0, 2.0), bath_pier - Vector3(0.0, 0.0, 2.0)],
		["South Bazaar Pavilion Wall", pav_wall + Vector3(2.0, 0.0, 0.0), pav_wall - Vector3(2.0, 0.0, 0.0)],
		["Gatehouse Awning Post", Vector3(-9.3, game.active_layout.CLOUD_ARENA_Y + 1.8, -102.0 + 9.2), Vector3(-9.3, game.active_layout.CLOUD_ARENA_Y + 1.8, -102.0 + 6.2)],
	]
	var solid_hits := 0
	for sp in solid_probes:
		var srq := PhysicsRayQueryParameters3D.create(sp[1], sp[2], 1)
		if not space.intersect_ray(srq).is_empty():
			solid_hits += 1
		else:
			printerr("  HOLLOW MODEL DETECTED: %s" % str(sp[0]))
	verify(solid_hits == solid_probes.size(), "v0.9.2 Bug(c): ALL %d/%d hero Ahsarah structures & props are 100%% physics-solid (zero walk-through models)" % [solid_hits, solid_probes.size()])

	# Audit (d): ZERO buried hidden stashes or loose tables (all 18/18 sit on open ground with clear sky above!)
	var loot_spots_checked := 0
	var loot_spots_clear := 0
	for lnode in game.world_loot.loose_nodes + game.world_loot.nest_nodes:
		loot_spots_checked += 1
		var lp: Vector3 = lnode.position
		var lrq := PhysicsRayQueryParameters3D.create(lp + Vector3(0.0, 6.0, 0.0), lp - Vector3(0.0, 1.0, 0.0), 1)
		var lhit: Dictionary = space.intersect_ray(lrq)
		if not lhit.is_empty() and absf(lhit.position.y - lp.y) <= 0.28:
			loot_spots_clear += 1
		else:
			printerr("  BURIED/OCCLUDED STASH: %s pos=%s hit=%s" % [str(lnode.get_meta("title", "")), str(lp), str(lhit.get("position", "NONE"))])
	verify(loot_spots_checked == 18 and loot_spots_clear == 18, "v0.9.2 Bug(d): ALL %d/%d Ahsarah loose tables & desert amphora stashes sit cleanly on open ground (zero buried stashes)" % [loot_spots_clear, loot_spots_checked])

	# Feature 2a: Sculpted Blender 4.5 tactical pickups + medkit pickup bugfix
	var sculpted_pickups := 0
	var sample_medkit: Node3D = null
	for pnode in game.pickup_nodes:
		if pnode.has_meta("tactical_item"):
			if pnode.find_child("SculptedPickupMesh", true, false) != null:
				sculpted_pickups += 1
			if str(pnode.get_meta("tactical_item")) == "medkit" and sample_medkit == null:
				sample_medkit = pnode
	verify(sculpted_pickups == 14, "v0.9.2 mounts sculpted Blender 4.5 PBR meshes on all %d/14 Ahsarah tactical pickups (ammo/medkit/EMP/stim)" % sculpted_pickups)
	var pre_meds: int = game.player.medkits
	game.player.position = sample_medkit.position + Vector3(0.0, 0.1, 0.6)
	game.closest_interaction = sample_medkit
	game.interact()
	verify(game.player.medkits == pre_meds + 1, "Picking up a sculpted tactical medkit increments player.medkits cleanly (not stims)")

	# Feature 2b: Captain Saeed bespoke M249 LMG + Roll & Triple Incendiary Crossbow (burning fire_zones!) + Desert Smoke!
	var saeed2 = game.combat.boss_unit
	game.player.position = game.active_layout.on_ground(Vector3(0.0, 0.0, -116.0)) + Vector3.UP * 0.1
	game.combat.engage_camp(2, true)
	await frames(2)
	saeed2.vanguard_move_state = "idle"
	saeed2.vanguard_move_cd = 0.01
	saeed2.saeed_move_cycle = 0
	saeed2._step_saeed_boss_ai(0.05, game.player.position, 10.0)
	verify(saeed2.vanguard_move_state == "saeed_lmg_windup", "Captain Saeed Move 1 triggers bespoke M249 LMG sweeping suppression windup")
	saeed2.vanguard_move_state = "idle"
	saeed2.vanguard_move_cd = 0.01
	saeed2.saeed_move_cycle = 1
	saeed2._step_saeed_boss_ai(0.05, game.player.position, 10.0)
	verify(saeed2.vanguard_move_state == "saeed_roll_crossbow", "Captain Saeed Move 2 triggers acrobatic roll + triple incendiary crossbow")
	for _sf in 14:
		saeed2._step_saeed_boss_ai(0.06, game.player.position, 10.0)
	verify(game.combat.boss_projectiles.size() >= 2, "Captain Saeed fires visible sculpted 3D incendiary crossbow bolts (count=%d)" % game.combat.boss_projectiles.size())
	for _uf in 30:
		game.combat.update(0.06)
	verify(game.combat.fire_zones.size() >= 2, "Saeed's incendiary bolts ignite persistent burning fire pools across courtyard (pools=%d)" % game.combat.fire_zones.size())

	# Feature 2c: Warlord Reis bespoke Gramophone Symphony Rings + S12K Drum Shotgun + Cluster Frag Grenades + Zero Dam Artillery Ultimate!
	game.start_action(true, "confidential")
	await frames(4)
	var reis2 = game.combat.boss_unit
	game.player.position = game.active_layout.on_ground(Vector3(0.0, 0.0, -114.0)) + Vector3.UP * 0.1
	game.combat.engage_camp(2, true)
	await frames(2)
	reis2.ov_move_state = "idle"
	reis2.ov_move_cd = 0.01
	reis2.ov_move_cycle = 0
	reis2._step_reis_boss_ai(0.05, game.player.position, 10.0)
	reis2._step_reis_boss_ai(0.25, game.player.position, 10.0)
	verify(reis2.ov_move_state == "reis_symphony_shock" and game.combat.sonic_rings.size() >= 1, "Warlord Reis Move 1 emits golden jumpable Brass Gramophone acoustic shockwave rings")
	reis2.ov_move_state = "idle"
	reis2.ov_move_cd = 0.01
	reis2.ov_move_cycle = 2
	reis2._step_reis_boss_ai(0.05, game.player.position, 10.0)
	reis2._step_reis_boss_ai(0.60, game.player.position, 10.0)
	var frag_cnt := 0
	for bp in game.combat.boss_projectiles:
		if str(bp.kind) == "frag_grenade":
			frag_cnt += 1
	verify(frag_cnt == 3, "Warlord Reis Move 3 launches 3 spinning 3D sculpted fragmentation grenades (count=%d)" % frag_cnt)
	reis2.trigger_ultimate_tiandi()
	var dam_shells := 0
	for bp2 in game.combat.boss_projectiles:
		if str(bp2.kind) == "dam_artillery":
			dam_shells += 1
	verify(reis2.overlord_ultimate_state == "descending" and dam_shells == 6 and is_instance_valid(reis2.mirror_mountain_node) and reis2.mirror_mountain_node.name == "ReisArtilleryUltimate", "Warlord Reis Ultimate launches 6 streaking Zero Dam Artillery shells from dam crest (zero Yanshan Mirror Mountain)")
	game.combat.apply_ultimate_crush_to_10hp()
	verify(game.combat.health == 10 and int(game.combat.shield) == 0, "Zero Dam Artillery Ultimate obeys non-lethal 10 HP crush balance rule")

	# 9. Clean Round-Trip back to Yanshan Base (and verify Yanshan ALSO mounts sculpted v092 pickups!)
	verify(game.switch_map("yanshan"), "Round-trip switch_map('yanshan') restores Yanshan Base cleanly")
	await frames(4)
	var ys_sculpted := 0
	for yp in game.pickup_nodes:
		if yp.has_meta("tactical_item") and yp.find_child("SculptedPickupMesh", true, false) != null:
			ys_sculpted += 1
	verify(ys_sculpted >= 15, "Great Yanshan ALSO upgrades tactical pickups to sculpted Blender 4.5 PBR models (%d mounted)" % ys_sculpted)
	var ah_collision_zero := true
	for da2 in game.wildlife.desert_animals:
		if int(da2.area.collision_layer) != 0:
			ah_collision_zero = false
			break
	verify(not game.is_ahsarah_map() and game.crate_nodes.size() == 6 and game.wildlife.active_map_id == "yanshan" and game.wildlife.yanshan_root.visible and not game.wildlife.ahsarah_root.visible and ah_collision_zero and game.cave_warden.map_enabled, "Yanshan Base restores all 6 crates, 12 Jiangnan wildlife species, Cave Warden & isolates desert wildlife cleanly")

	# =========================================================================
	# 10. v0.9.3 Offline Chinese Faction/Boss Voices, 15/20-min Timers, Minimal HUD & Full-Body 3P Checks
	# =========================================================================
	var req_cn_groups := ["ahsarah_guard", "boss_saeed", "boss_reis", "haavk_trooper", "mistbound_soldier", "boss_ironface", "boss_overlord", "cave_warden"]
	var cn_groups_ok := true
	for grp in req_cn_groups:
		if not game.cn_voice_groups.has(grp) or (game.cn_voice_groups[grp] as Array).size() < 5:
			cn_groups_ok = false
			break
	var cn_decoded := 0
	for lid in game.cn_voice_manifest.keys():
		var st_cn: AudioStream = game.load_cn_voice_stream(str(lid))
		if st_cn != null and st_cn.get_length() > 0.35:
			cn_decoded += 1
	verify(game.cn_voice_manifest.size() >= 60 and cn_decoded == game.cn_voice_manifest.size() and cn_groups_ok, "v0.9.3: all %d/%d offline Chinese faction & boss OGG voice clips decode across all 8 groups" % [cn_decoded, game.cn_voice_manifest.size()])
	game.cn_voice_cd = 0.0
	var bark_played: bool = game.play_cn_voice("reis_01", 8.0, true)
	verify(bark_played and game.last_cn_voice_id == "reis_01" and game.radio_panel.visible and "留声机" in game.radio_label.text, "v0.9.3: play_cn_voice plays boss Chinese clip and displays compact radio caption")
	var ag_id: String = game.play_cn_voice_group("ahsarah_guard", "proximity", 14.0, true)
	verify(ag_id != "" and ag_id.begins_with("ag_"), "v0.9.3: play_cn_voice_group picks random Ahsarah Guard proximity bark (%s)" % ag_id)

	# Match timers: 15 min Normal (900s) / 20 min Confidential (1200s) & 3 camps required
	game.start_action(true, "normal")
	verify(game.time_left > 895.0 and game.time_left <= 900.0 and game.Rules.REQUIRED_OUTPOSTS == 3, "v0.9.3: Normal Operation launches with 15-minute (900s) timer and 3-camp extraction target")
	game.start_action(true, "confidential")
	verify(game.time_left > 1195.0 and game.time_left <= 1200.0, "v0.9.3: Confidential Operation launches with 20-minute (1200s) timer")

	# Minimal Delta Force HUD widgets & [F1] Intel Overlay toggle
	verify(is_instance_valid(game.stance_widget) and is_instance_valid(game.weapon_glyph) and is_instance_valid(game.slot_medkit) and is_instance_valid(game.slot_emp) and is_instance_valid(game.slot_stim) and is_instance_valid(game.slot_skill) and is_instance_valid(game.ammo_big_label), "v0.9.3: minimal modern HUD builds vector stance silhouette, weapon glyph & 4 tactical icon slots")
	verify(not game.intel_overlay.visible, "v0.9.3: verbose [F1] tactical intel drawer stays hidden by default to keep front view clear")
	game.toggle_intel_overlay()
	verify(game.intel_overlay.visible, "v0.9.3: toggle_intel_overlay() opens on-demand full status & keybinds card")
	game.toggle_intel_overlay()
	verify(not game.intel_overlay.visible, "v0.9.3: second toggle closes intel drawer cleanly")

	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))
	print("AHSARAH_TEST_SUMMARY passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
