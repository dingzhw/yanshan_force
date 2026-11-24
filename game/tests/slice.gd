extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func verify(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func frames(n: int):
	for i in n: await physics_frame
func node_for(id: String):
	for n in game.exploration.nodes:
		if n.get_meta("explore_id") == id: return n
	return null
func enter(id: String):
	var node = node_for(id)
	game.player.clear_movement_input()
	game.player.position = node.position + Vector3(0, 0.1, 2)
	await frames(3)
	game.interact()
func ray(a: Vector3, b: Vector3):
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1, [game.player.get_rid()]))

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action(true, "normal")
	await frames(3)
	verify(game.VERSION == "0.9.7" and game.words.size() == 175 and game.crate_nodes.size() == 6, "v0.9.7 slice uses 175-entry word pack and 6 Yanshan blind-box vault crates")
	var tac_counts := {"ammo_crate": 0, "smoke_emp": 0, "energy_drink": 0}
	var active_ammo_norm := 0
	var supply_count := 0
	for p in game.pickup_nodes:
		var t_id := str(p.get_meta("tactical_item", ""))
		if tac_counts.has(t_id):
			tac_counts[t_id] += 1
			if t_id == "ammo_crate" and p.visible:
				active_ammo_norm += 1
		else:
			supply_count += 1
	verify(supply_count == 11 and tac_counts["ammo_crate"] >= 9 and active_ammo_norm <= 6 and tac_counts["smoke_emp"] >= 4 and tac_counts["energy_drink"] >= 3, "v0.8.2_dev2 D2-2: places 11 supply caches and limits active Normal ground ammo crates to <= 6")
	verify(game.exploration.nodes.size() == 14, "v0.9.0 spawns 4 classic exploration + 4 field intel + recon radio + airdrop beacon + 3 Yanxia heritage + Dimensional Rift Wall")
	for raw in [game.Layout.SPAWN, game.Layout.POEM, game.Layout.MATH, game.Layout.STATIONS[1].at, game.Layout.STATIONS[2].at, game.Layout.PASS_OUTPOST, game.exit_position, Vector3(-48, 0, -100)]:
		var at = game.Layout.on_ground(raw)
		var hit = ray(at + Vector3.UP * 5, at - Vector3.UP * 2)
		verify(not hit.is_empty(), "continuous terrain collider beneath " + str(raw))
	var batches = game.landscape.find_children("*", "MultiMeshInstance3D", true, false)
	verify(batches.size() >= 2, "bamboo stems and leaves are instanced instead of thousands of draw nodes")

	var old_id = game.question.id
	await enter("clue")
	verify(game.exploration.busy and game.paused and game.exploration.states.clue, "E opens a reachable English exploration clue and freezes the run")
	var time = game.time_left
	var ammo = game.player.ammo
	game.player.shoot()
	await frames(20)
	verify(is_equal_approx(game.time_left, time) and game.player.ammo == ammo, "reading does not consume timer or permit shooting")
	game.exploration.close()

	await enter("english")
	verify(game.exploration.busy and game.exploration.is_spelling_challenge("english") and game.exploration.spell_box.visible and game.rules.bag.size() == 0, "v0.8.6: following next to opens live random English spelling verification for sealed roadside supply")
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("english"))
	verify(game.exploration.states.english and game.exploration.swap_button.visible and game.rules.bag.size() == 0, "v0.8.6: spelling random roadside word unlocks calibrated probabilistic supply confirmation button")
	game.exploration.open_reward_container()
	game.loot_container_ui.take_item_to_bag(0)
	verify(game.exploration.states.english and game.exploration.states.english_claimed and game.rules.bag.size() == 1 and not node_for("english").visible, "confirming next to supply collects item and removes its collider")
	var bag = game.rules.bag.size()
	game.exploration.open(node_for("english"))
	verify(game.rules.bag.size() == bag, "English discovery cannot be claimed twice")
	game.exploration.close()

	await enter("poem")
	verify(game.exploration.busy, "stone tablet is reachable from its branch")
	var poem_ans = game.exploration.answer_button_index("poem")
	game.exploration.buttons[poem_ans].pressed.emit()
	verify(game.exploration.states.poem and game.exploration.swap_button.visible and game.rules.bag.size() == bag, "v0.8.4: correct poem answer unlocks reward confirmation button without auto-stuffing")
	game.exploration.open_reward_container()
	game.loot_container_ui.take_item_to_bag(0)
	verify(game.exploration.states.poem and game.exploration.states.poem_claimed and game.rules.bag.size() == bag + 1, "confirming poem reward collects item and marks stone compartment claimed")
	game.exploration.choose(poem_ans)
	verify(game.rules.bag.size() == bag + 1, "repeated solved-puzzle click cannot duplicate loot")
	verify(game.question.id == old_id and game.rules.score == 18 and game.rules.answered == 0, "optional learning keeps the pending combat question untouched while awarding exploration bonus")

	# v0.8.6: Wrong spelling on Field Intel locks that node out for the rest of the run (no retry brute-force!)
	var ic_lock_node: Node3D = node_for("intel_cleft")
	game.exploration.open(ic_lock_node)
	verify(game.exploration.is_spelling_challenge("intel_cleft") and game.exploration.spell_box.visible, "v0.8.6: field intel node uses live random English spelling challenge")
	game.exploration.submit_spelling("__definitely_wrong_spelling__")
	verify(game.exploration.is_locked_out("intel_cleft") and game.exploration.spell_submit_btn.disabled and not game.exploration.states.intel_cleft, "v0.8.6: wrong spelling on field intel immediately locks node for the run and disables retry")
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("intel_cleft"))
	verify(not game.exploration.states.intel_cleft, "v0.8.6: typing correct spelling after lock-out cannot bypass single-attempt rule")
	game.exploration.close()

	while game.rules.bag.size() < game.rules.capacity():
		game.rules.add_loot("filled", 1, 1)
	var gate_at = game.exploration.gate.global_position + Vector3(1.4, 1.1, 0)
	verify(not ray(gate_at + Vector3(0, 0, 3), gate_at - Vector3(0, 0, 3)).is_empty(), "closed shortcut gate blocks a real world ray")
	# v0.8.1 FB-6 / v0.8.5: Flanking timber stockade wings block walking/rays across the entire valley pass!
	var mg_c: Vector3 = game.Layout.MATH_GATE_CENTER
	var wing_w: Vector3 = game.Layout.on_ground(Vector3(mg_c.x - 5.5, 0, mg_c.z)) + Vector3(0, 1.1, 0)
	var wing_e: Vector3 = game.Layout.on_ground(Vector3(mg_c.x + 5.5, 0, mg_c.z)) + Vector3(0, 1.1, 0)
	verify(not ray(wing_w + Vector3(0, 0, 3), wing_w - Vector3(0, 0, 3)).is_empty() and not ray(wing_e + Vector3(0, 0, 3), wing_e - Vector3(0, 0, 3)).is_empty(), "v0.8.1 FB-6: fortified timber stockade wings physically seal both flanks of the shortcut pass")
	# v0.8.1 FB-1: Elevated Wangdao Pavilion scenic overlook deck stands > 9.0m with solid floor beneath it!
	var wd_pos: Vector3 = game.landscape.wangdao_deck_pos
	var wd_hit: Dictionary = ray(wd_pos + Vector3(0, 2.0, 0), wd_pos - Vector3(0, 1.5, 0))
	verify(wd_pos.y >= 9.0 and not wd_hit.is_empty() and absf(wd_hit.position.y - wd_pos.y) < 0.25, "v0.8.1 FB-1: elevated Wangdao Pavilion scenic overlook deck stands above 9.0m with solid balcony floor")
	await enter("math")
	var math_ans = game.exploration.answer_button_index("math")
	game.exploration.buttons[math_ans].pressed.emit()
	verify(game.exploration.states.math and not game.exploration.states.math_claimed, "full bag preserves the solved math reward for later")
	await frames(2)
	verify(ray(gate_at + Vector3(0, 0, 3), gate_at - Vector3(0, 0, 3)).is_empty(), "solved math puzzle opens the gate's collision")
	game.exploration.close()
	await enter("math")
	verify(not game.exploration.states.math_claimed and game.loot_container_ui.busy and game.loot_container_ui.pending_items.size() == 1, "v0.8.4: revisiting solved math node with unclaimed reward opens LootContainerUI directly")
	game.loot_container_ui.discard_bag_slot(game.rules.bag.size() - 1)
	game.loot_container_ui.take_item_to_bag(0)
	verify(game.exploration.states.math_claimed and game.rules.bag.size() == game.rules.capacity() and not game.loot_container_ui.busy, "v0.8.4: discarding 1 slot in LootContainerUI & confirming claims the pending math reward")
	game.exploration.open_reward_container()
	verify(game.rules.bag.size() == game.rules.capacity(), "repeated reward claim cannot duplicate an item")
	verify(game.exploration.completed() == 3, "all three optional discoveries complete independently")

	# Test CipherTerminal multi-stage progression (Tier 1: word+phrase, Tier 3: word+phrase+sentence)
	game.rules.bag.pop_back()
	game.rules.bag.pop_back()
	for i in 12:
		game.rules.open_question()
		game.rules.answer(true)
	game.player.position = game.crate_nodes[0].position + Vector3(0, 0.1, 1.4)
	await frames(3)
	game.interact()
	verify(game.cipher_terminal.busy and game.paused and game.cipher_terminal.stage_count() == 2, "interacting with Tier-1 crate opens 2-stage word+phrase terminal")
	game.cipher_terminal.submit_text("__wrong1__")
	verify(not game.cipher_terminal.unlocked and game.cipher_terminal.attempts == 1, "first typo keeps stage locked and prompts retry")
	game.cipher_terminal.submit_text("__wrong2__")
	verify(not game.cipher_terminal.unlocked and game.cipher_terminal.mask_label.text.contains(game.cipher_terminal.target_word.english.replace("’", "'")), "second typo reveals guided spelling without soft-locking")
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	verify(not game.cipher_terminal.unlocked and game.cipher_terminal.stage_index == 1 and str(game.cipher_terminal.target_word.get("kind", "")) == "phrase", "stage 1 word pass transitions to stage 2 textbook phrase")
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	verify(game.cipher_terminal.unlocked and game.rules.crates.size() == 1 and game.loot_container_ui.busy and game.loot_container_ui.pending_items.size() == 2, "v0.8.4: completing stage 2 phrase unlocks Tier-1 crate and hands off 2 items to LootContainerUI")
	game.loot_container_ui.take_all_for_qa()
	verify(not game.cipher_terminal.busy and not game.loot_container_ui.busy and not game.paused, "taking all crate loot closes LootContainerUI and resumes field play")

	# Test Tier-3 Legendary Gold Airdrop Pod (3 stages: word -> phrase -> sentence + contraction equivalence + full-bag selective pickup)
	verify(game.cipher_terminal._is_match("it is your turn", {"english": "It’s your turn."}) and game.cipher_terminal._is_match("it's your turn", {"english": "It’s your turn."}), "sentence matcher accepts contractions, expanded forms, and omitted punctuation")
	game.player.position = game.crate_nodes[2].position + Vector3(0, 0.1, 1.6)
	await frames(3)
	game.interact()
	verify(game.cipher_terminal.busy and game.cipher_terminal.stage_count() == 3, "Tier-3 gold airdrop pod requires 3-stage word+phrase+sentence unlock")
	verify(str(game.cipher_terminal.stages[2].get("kind", "")) == "sentence", "Tier-3 final stage challenges a full Grade 5A sentence")
	game.cipher_terminal.solve_all_for_qa()
	verify(game.cipher_terminal.unlocked and game.rules.crates.size() == 2 and game.loot_container_ui.busy and game.loot_container_ui.pending_items.size() == 3, "v0.8.4: solving all 3 stages unlocks Tier-3 pod and shows all 3 high-tier items in LootContainerUI even on full bag")
	verify(game.crate_nodes[2].get_meta("lid_node").rotation.x < -0.4, "Tier-3 pod opens its armored lid on unlock")
	game.loot_container_ui.discard_bag_slot(game.rules.bag.size() - 1)
	game.loot_container_ui.take_item_to_bag(0)
	game.loot_container_ui.close()

	game.player.ammo = 1
	game.player.reload()
	await frames(8)
	await enter("poem")
	var reload = game.player.reload_left
	await frames(30)
	verify(is_equal_approx(game.player.reload_left, reload), "puzzle reading freezes an in-progress reload")
	game.exploration.close()
	await frames(95)
	verify(game.player.ammo == game.rules.magazine(), "closing the puzzle resumes and finishes the same reload")

	while game.rules.score < game.Rules.EXTRACTION_SCORE:
		game.rules.open_question()
		game.rules.answer(true)
	game.rules.outposts_cleared = game.Rules.REQUIRED_OUTPOSTS
	game.rules.boss_defeated = true
	game.player.position = game.exit_position
	await frames(3)
	game.interact()
	verify(game.rules.phase == "extracting", "B extraction starts once 260-point threshold is met")
	await frames(320)
	verify(game.rules.phase == "result" and game.rules.profile.warehouse.size() > 0, "five-second extraction banks the backpack")
	var saved_count = game.rules.profile.warehouse.size()
	game._end_run(true)
	verify(game.rules.profile.warehouse.size() == saved_count, "repeated extraction settlement cannot duplicate discovery loot")

	game.start_action(false)
	verify(game.exploration.completed() == 0 and not game.exploration.states.clue and node_for("english").visible, "a new run resets route discoveries and restores collectible collision")
	verify(is_instance_valid(game.player.weapon_view) and game.player.weapon_view.get_parent() == game.player.weapon_root, "new deployment binds the new animated rifle instance")
	verify(is_instance_valid(game.player.weapon_view.magazine) and is_instance_valid(game.player.weapon_view.optic_root), "rifle has animated magazine and reflex optic")
	verify(is_instance_valid(game.player.weapon_view.right_arm_rig) and is_instance_valid(game.player.weapon_view.left_hand_pivot) and is_instance_valid(game.player.weapon_view.left_sleeve), "rifle view includes first-person tactical sleeves and gloved hands")
	verify(game.player.weapon_view.arms_skeleton is Skeleton3D and game.player.weapon_view.arms_skeleton.get_bone_count() == 39 and game.player.weapon_view.pose_cache.size() >= 8, "v0.5.3 first-person arms use 39-bone CC0 sculpted skeleton with 8 pose actions (incl. knife idle & dual slash)")
	verify(game.player.weapon_view.knife_mount is BoneAttachment3D and is_instance_valid(game.player.weapon_view.knife_root), "v0.5.3 tactical knife is attached to hand.R BoneAttachment3D")
	game.player.select_weapon(1)
	await frames(6)
	verify(game.player.weapon_slot == 1 and game.player.weapon_view.knife_root.visible and not game.player.weapon_view.rifle_meshes[0].visible, "switching to slot 2 reveals held knife and stows rifle")
	game.player.select_weapon(0)
	await frames(4)
	verify(is_instance_valid(game.player.weapon_view.arms_mesh) and game.player.weapon_view.arms_mesh.mesh.get_surface_count() >= 8, "v0.5.3 sculpted arms carry multi-surface PBR sleeve, glove, skin, nail, and watch materials")
	verify(is_equal_approx(game.crate_nodes[2].get_meta("lid_node").rotation.x, 0.0), "new deployment resets vault crate lids back to closed position")
	game.player.ammo = 1
	game.player.reload()
	await frames(40)
	verify(game.player.weapon_view.magazine.position.y < -0.06 and game.player.weapon_view.left_hand_pivot.position.y < 0.08, "reload physically withdraws magazine with left support hand following")
	game._end_run(false)
	game.rules.profile.owned.append("magazine")
	game.start_action(false)
	verify(game.player.ammo == 14 and game.player.weapon_view.magazine.scale.y > 1.2, "magazine upgrade changes both capacity and visible magazine size")
	verify(game.exploration.secrets_completed() == 0 and not game.exploration.radar_scan_active, "new deployment resets v0.5.4 field intel & radar scan state")

	# v0.5.4 Field Intel, Minimap Radar Reveal, Recon Radio & Airdrop Beacon checks
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN)
	await frames(4)
	verify(not game.minimap._is_discovered(game.crate_nodes[4]) and not game.minimap._is_discovered(game.crate_nodes[2]), "hidden parkour & cave vaults start masked on minimap beyond 14m")
	var pre_score := int(game.rules.score)
	var ic_node: Node3D = node_for.call("intel_container")
	game.exploration.open(ic_node)
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("intel_container"))
	game.exploration.close()
	await frames(2)
	verify(game.exploration.is_secret_revealed("parkour_containers") and game.minimap._is_discovered(game.crate_nodes[4]), "intel_container random English spelling reveals West Cargo Vault on minimap")
	verify(game.rules.score >= pre_score + 20 and not game.minimap._is_discovered(game.crate_nodes[2]), "single intel note only reveals its own secret and awards +20 score")

	game.rules.combat_mode = true
	game.player.reserve_ammo = 15
	var pre_gren := int(game.player.grenades)
	var pre_bag: int = game.rules.bag.size()
	var radio_node: Node3D = node_for.call("recon_radio")
	game.exploration.open(radio_node)
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("recon_radio"))
	game.exploration.open_reward_container()
	if game.loot_container_ui.busy:
		game.loot_container_ui.take_all_for_qa()
	else:
		game.exploration.close()
	verify(game.exploration.radar_scan_active and game.minimap._is_discovered(game.crate_nodes[2]) and game.minimap._is_discovered(game.crate_nodes[1]), "East Recon Radio triggers global minimap radar reveal")
	verify(game.player.grenades == pre_gren + 1 and game.player.reserve_ammo >= 15 + 8, "v0.8.2_dev2 D2-2: Recon Radio grants +1 smoke/EMP and +8 calibrated reserve ammo")
	var pre_ammo2 := int(game.player.reserve_ammo)
	var ab_node: Node3D = node_for.call("airdrop_beacon")
	game.exploration.open(ab_node)
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("airdrop_beacon"))
	game.exploration.open_reward_container()
	if game.loot_container_ui.busy:
		game.loot_container_ui.take_all_for_qa()
	else:
		game.exploration.close()
	var ab_loot: Dictionary = game.rules.bag[game.rules.bag.size() - 1]
	verify(game.player.reserve_ammo > pre_ammo2 and game.rules.bag.size() >= pre_bag + 2 and int(ab_loot.get("rarity", 0)) >= 1 and int(ab_loot.get("rarity", 0)) <= 7, "v0.8.6: North Airdrop Beacon grants calibrated +10 ammo and probabilistic pyramid loot in Normal mode")
	for iid in ["intel_cleft", "intel_cave", "intel_roof"]:
		var inod: Node3D = node_for.call(iid)
		game.exploration.open(inod)
		game.exploration.submit_spelling(game.exploration.expected_spelling_word(iid))
		game.exploration.close()
	verify(game.exploration.secrets_completed() == 6 and game.exploration.completed() == 0, "6 intel/radio/beacon secrets track independently from 3 classic explorations")
	game.rules.combat_mode = false

	# Real CharacterBody3D physics walk+jump verification across all 3 v0.5.4 parkour routes + Cave Grotto
	var sim_key := func(code: Key, pressed: bool):
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
	var hop_step := func(target: Vector3, jump_needed: bool, step_name: String) -> bool:
		sim_key.call(KEY_W, false)
		sim_key.call(KEY_SPACE, false)
		var jumped := false
		for f in range(130):
			var p: Vector3 = game.player.position
			var d := Vector2(target.x - p.x, target.z - p.z)
			var horiz := d.length()
			if horiz > 0.05:
				game.player.yaw = atan2(-d.x, -d.y)
			if horiz <= 0.34:
				sim_key.call(KEY_W, false)
				sim_key.call(KEY_SPACE, false)
				if game.player.is_on_floor():
					return absf(game.player.position.y - target.y) <= 0.42
			else:
				sim_key.call(KEY_W, true)
				if jump_needed and not jumped and game.player.is_on_floor() and f >= 2:
					sim_key.call(KEY_SPACE, true)
					jumped = true
				elif f >= 10:
					sim_key.call(KEY_SPACE, false)
			await physics_frame
		sim_key.call(KEY_W, false)
		sim_key.call(KEY_SPACE, false)
		print("PARKOUR_STEP_TIMEOUT ", step_name, " at ", game.player.position, " expected ", target)
		return false

	# Route A: West Cargo Containers
	var cy: Vector3 = game.Layout.on_ground(game.Layout.PARKOUR_CONTAINERS)
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.position = cy + Vector3(3.6, 0.05, 4.7)
	await frames(6)
	for st in [
		[cy + Vector3(3.6, 0.56, 3.0), true, "A1"],
		[cy + Vector3(1.85, 1.14, 3.0), true, "A2"],
		[cy + Vector3(1.65, 1.70, 1.35), true, "A3_lower_container"],
		[cy + Vector3(-1.45, 1.70, 1.05), false, "A3_walk_west"],
		[cy + Vector3(-2.55, 2.28, -0.35), true, "A4_catwalk"],
		[cy + Vector3(-1.55, 2.86, -1.35), true, "A5_upper_container"],
		[cy + Vector3(-0.75, 2.86, -1.35), false, "A5_crate_reach"]
	]:
		verify(await hop_step.call(st[0], st[1], st[2]), "Route A parkour step reachable by real jump/walk: " + st[2])
	verify(game.player.position.distance_to(game.crate_nodes[4].position) < 3.0 and game._can_interact(game.crate_nodes[4]), "Route A summit crate_nodes[4] is reachable and interactable")

	# Route B: Bamboo Shelter Scaffolding Stairs -> Roof Vault
	var bs_base: float = game.Layout.min_ground_height(game.Layout.SHELTER_BAMBOO.x, game.Layout.SHELTER_BAMBOO.z, 2.4) - 0.08
	var bs_orig := Vector3(game.Layout.SHELTER_BAMBOO.x, bs_base, game.Layout.SHELTER_BAMBOO.z)
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.position = game.Layout.on_ground(Vector3(bs_orig.x + 3.85, 0.0, bs_orig.z + 3.2)) + Vector3(0, 0.05, 0)
	await frames(6)
	for st in [
		[bs_orig + Vector3(3.85, 0.62, 1.55), true, "B1"],
		[bs_orig + Vector3(3.85, 1.20, -0.10), true, "B2"],
		[bs_orig + Vector3(3.85, 1.78, -1.75), true, "B3_balcony"],
		[bs_orig + Vector3(2.45, 2.36, -2.75), true, "B4"],
		[bs_orig + Vector3(0.65, 2.94, -2.75), true, "B5"],
		[bs_orig + Vector3(0.35, 3.485, -1.10), true, "B6_roof"],
		[bs_orig + Vector3(-0.35, 3.485, 0.05), false, "B6_crate_reach"]
	]:
		verify(await hop_step.call(st[0], st[1], st[2]), "Route B shelter roof parkour reachable: " + st[2])
	verify(game.player.position.distance_to(game.crate_nodes[1].position) < 3.0 and game._can_interact(game.crate_nodes[1]), "Route B roof crate_nodes[1] is reachable and interactable")

	# Route C: Watchtower Spiral Climb -> Summit Vault
	var wt: Vector3 = game.landscape.watchtower_pos
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.position = wt + Vector3(0.0, 0.05, 3.5)
	await frames(6)
	for st in [
		[wt + Vector3(0.0, 0.56, 2.05), true, "C0"],
		[wt + Vector3(0.45, 1.06, 0.25), true, "C_deck1"],
		[wt + Vector3(2.05, 1.62, 0.25), true, "C1"],
		[wt + Vector3(2.05, 2.24, -1.45), true, "C2"],
		[wt + Vector3(0.35, 2.87, -2.05), true, "C3"],
		[wt + Vector3(-0.45, 3.50, -0.25), true, "C_deck2"],
		[wt + Vector3(-2.05, 4.08, -0.25), true, "C4"],
		[wt + Vector3(-2.05, 4.70, 1.45), true, "C5"],
		[wt + Vector3(-0.35, 5.32, 2.05), true, "C6"],
		[wt + Vector3(-0.15, 5.92, 0.55), true, "C_summit"]
	]:
		verify(await hop_step.call(st[0], st[1], st[2]), "Route C watchtower spiral parkour reachable: " + st[2])
	verify(game.player.position.distance_to(game.crate_nodes[3].position) < 3.0 and game._can_interact(game.crate_nodes[3]), "Route C summit crate_nodes[3] is reachable and interactable")

	# Cave Grotto accessibility & interaction check
	game.player.velocity = Vector3.ZERO
	game.player.position = game.crate_nodes[2].position + Vector3(0, 0.02, 1.6)
	await frames(10)
	verify(game.player.is_on_floor() and game._can_interact(game.crate_nodes[2]), "Cave Grotto Tier-3 airdrop pod is accessible on flat cave floor")

	# v0.5.5 Mountain Stream, Walkable Footbridges, Living Wildlife, Interactive Flora & Panorama Fence
	var stream_node: Node3D = game.landscape.get_node_or_null("MountainStreamWater")
	var valley_node: Node3D = game.landscape.get_node_or_null("OuterRiceValley")
	var horizon_node: Node3D = game.landscape.get_node_or_null("HorizonMountainsSkirt")
	verify(is_instance_valid(stream_node) and is_instance_valid(valley_node) and is_instance_valid(horizon_node) and stream_node.visible and valley_node.visible and horizon_node.visible, "v0.5.5 stream water, 3D outer rice terraces & horizon skirt exist and render")

	var wy_prev: float = game.Layout.stream_water_y(float(game.Layout.STREAM_Z_MIN))
	var downhill_ok := true
	for zi in range(int(game.Layout.STREAM_Z_MIN) + 6, int(game.Layout.FENCE_MAX_Z) + 1, 6):
		var wy_cur: float = game.Layout.stream_water_y(float(zi))
		if wy_cur >= wy_prev:
			downhill_ok = false
		wy_prev = wy_cur
	verify(downhill_ok, "mountain stream elevation flows strictly downhill from North spring to South")

	for bz in game.Layout.STREAM_BRIDGES:
		var bcx: float = game.Layout.stream_center_x(float(bz))
		var half_span: float = 8.4 if is_equal_approx(float(bz), float(game.Layout.MULTI_ARCH_BRIDGE_Z)) else 5.8
		game.player.clear_movement_input()
		game.player.velocity = Vector3.ZERO
		game.player.position = game.Layout.on_ground(Vector3(bcx - half_span, 0.0, float(bz))) + Vector3(0, 0.12, 0)
		await frames(6)
		var walked := false
		sim_key.call(KEY_SPACE, false)
		for step in 320:
			var p: Vector3 = game.player.position
			var d := Vector2((bcx + half_span) - p.x, float(bz) - p.z)
			if d.length() <= 0.72 and game.player.is_on_floor():
				walked = true
				break
			game.player.yaw = atan2(-d.x, -d.y)
			sim_key.call(KEY_W, true)
			await frames(1)
		sim_key.call(KEY_W, false)
		verify(walked and game.player.position.y > game.Layout.stream_water_y(float(bz)) - 0.05, "stream bridge at z=" + str(bz) + " is smoothly walkable across water")

	verify(is_instance_valid(game.wildlife) and game.wildlife.animals.size() >= 90 and game.wildlife.flora_nodes.size() == 12 and game.wildlife.sky_egrets.size() >= 10, "v0.8.6 spawns 96 habitat critters across 12 species + 10 flapping sky egrets + 12 interactive flora nodes")
	var kinds := {}
	var first_by_kind := {}
	var rigged_ok := true
	for a in game.wildlife.animals:
		kinds[a.kind] = int(kinds.get(a.kind, 0)) + 1
		if not first_by_kind.has(a.kind):
			first_by_kind[a.kind] = a
		var skel: Node = (a.visual as Node).find_child("Skeleton3D", true, false) if a.visual != null else null
		if skel == null:
			skel = (a.visual as Node).find_children("*", "Skeleton3D", true, false)[0] if (a.visual != null and not (a.visual as Node).find_children("*", "Skeleton3D", true, false).is_empty()) else null
		if skel == null or a.anim == null:
			rigged_ok = false
			print("MISSING_RIG kind=", a.kind)
	var eg0: Dictionary = game.wildlife.sky_egrets[0]
	var eg_skels: Array = (eg0.vis as Node).find_children("*", "Skeleton3D", true, false) if eg0.vis != null else []
	verify(rigged_ok and not eg_skels.is_empty() and eg0.anim != null and (eg0.anim as AnimationPlayer).is_playing(), "all 12 wildlife species + sky egrets use real Skeleton3D + AnimationPlayer rigs")
	verify(
		int(kinds.get("rabbit", 0)) >= 11 and int(kinds.get("squirrel", 0)) >= 9 and int(kinds.get("boar", 0)) >= 6 and int(kinds.get("fox", 0)) >= 6
		and int(kinds.get("bird", 0)) >= 11 and int(kinds.get("fish", 0)) >= 8 and int(kinds.get("crab", 0)) >= 6 and int(kinds.get("shrimp", 0)) >= 7
		and int(kinds.get("deer", 0)) >= 8 and int(kinds.get("pheasant", 0)) >= 8 and int(kinds.get("turtle", 0)) >= 6 and int(kinds.get("butterfly", 0)) >= 10,
		"all 12 Jiangnan wildlife species (including deer/pheasant/turtle/butterfly) meet v0.8.6 target counts"
	)

	game.wildlife.reset()
	var all_squirrels_have_tree := true
	for sq_chk in game.wildlife.animals:
		if sq_chk.kind == "squirrel" and game.wildlife._find_nearest_tree_trunk(sq_chk.pos, 22.0).is_empty():
			all_squirrels_have_tree = false
	verify(game.landscape.tree_trunks.size() >= 36 and all_squirrels_have_tree, "slice_world registers >=36 inside-fence tree trunks and every squirrel has a climbable tree within 22m")
	var squirrel: Dictionary = first_by_kind["squirrel"]
	var near_trunk: Vector3 = game.landscape.tree_trunks[0]
	squirrel.pos = Vector3(near_trunk.x + 1.8, game.terrain_height(near_trunk.x + 1.8, near_trunk.z + 1.2), near_trunk.z + 1.2)
	squirrel.root.position = squirrel.pos
	game.player.velocity = Vector3.ZERO
	game.player.position = squirrel.pos + Vector3(0.0, 0.0, 2.8)
	game.wildlife.update(0.05)
	verify(squirrel.state in ["climb_approach", "climb_up"], "approaching squirrel triggers tree-climbing scramble toward nearest trunk")
	for tick in 24:
		game.wildlife.update(0.08)
	verify(
		squirrel.state in ["climb_up", "perched_tree"] and squirrel.pos.y > float(near_trunk.y) + 2.0,
		"startled squirrel climbs >2.0m vertically up tree trunk bark"
	)

	# Test bush-ambush wild boar startle + counter-charge gore attack (-15 HP in combat mode)
	var boar0: Dictionary = first_by_kind["boar"]
	verify(boar0.state == "ambush", "wild boar starts nestled in hillside bush ambush thicket")
	game.player.position = boar0.pos + Vector3(0.0, 0.0, 4.5)
	game.wildlife.update(0.05)
	verify(boar0.state in ["flee", "charge"] and game.wildlife.discovered_species.has("boar"), "approaching bush thicket startles wild boar into hillside gallop or charge")

	game.combat.stage = game.combat.Stage.FIELD
	game.combat.health = 100
	game.combat.shield = 30
	var p_stand: Vector3 = game.Layout.on_ground(Vector3(36.0, 0.0, 6.0))
	game.player.position = p_stand
	boar0.pos = game.Layout.on_ground(Vector3(36.0, 0.0, 2.8))
	boar0.root.position = boar0.pos
	boar0.charge_cd = 0.0
	game.wildlife.trigger_boar_charge(boar0)
	verify(boar0.state == "charge", "trigger_boar_charge enters active counter-charge state")
	for c_tick in 18:
		game.wildlife.update(0.05)
		if game.combat.health < 100:
			break
	verify(game.combat.health == 85 and roundi(game.combat.shield) == 25, "wild boar counter-charge gore impact deals 15 HP damage + 5 shield loss")
	game.combat.stage = game.combat.Stage.OFF

	var bird0: Dictionary = first_by_kind["bird"]
	var perch_y: float = bird0.pos.y
	game.player.position = Vector3(bird0.pos.x, game.terrain_height(bird0.pos.x, bird0.pos.z), bird0.pos.z + 3.0)
	game.wildlife.update(0.05)
	for tick in 12:
		game.wildlife.update(0.1)
	verify(bird0.state == "fly" and bird0.pos.y > perch_y + 1.2, "startled mountain bird flaps and climbs dynamically into the sky")

	# v0.6.1.2 Real bullet raycast hit tests on both airborne flying birds AND high-altitude sky egrets!
	var sky_cam := Camera3D.new()
	game.add_child(sky_cam)
	bird0.pos = Vector3(0.0, 18.0, 0.0)
	bird0.root.position = bird0.pos
	sky_cam.global_position = Vector3(0.0, 14.0, 14.0)
	await frames(2)
	sky_cam.look_at((bird0.area as Area3D).global_position)
	game.fire(sky_cam)
	verify(bird0.state == "downed" and bird0.area.collision_layer == 0, "real bullet raycast hits and downs airborne flying mountain bird")

	var sky_egret0: Dictionary = game.wildlife.sky_egrets[0]
	(sky_egret0.node as Node3D).global_position = Vector3(0.0, 32.0, -18.0)
	sky_cam.global_position = Vector3(0.0, 12.0, 18.0)
	await frames(2)
	sky_cam.look_at((sky_egret0.area as Area3D).global_position)
	game.fire(sky_cam)
	verify(sky_egret0.state == "downed" and sky_egret0.area.collision_layer == 0, "real long-range bullet raycast hits and downs high-altitude sky egret")
	for eg_tick in 16:
		game.wildlife.update(0.1)
	verify(sky_egret0.state == "hidden" and not (sky_egret0.node as Node3D).visible, "downed sky egret spirals and dissolves cleanly before 15s respawn")
	sky_cam.queue_free()

	var rabbit0: Dictionary = first_by_kind["rabbit"]
	verify(game.wildlife.hit_bullet(rabbit0.area) and rabbit0.state == "downed", "bullet hit downs wildlife critter cleanly")
	for wait_v in 22:
		game.wildlife.update(0.1)
	verify(rabbit0.state == "hidden" and not rabbit0.root.visible, "downed animal dissolves and vanishes after ~1.85s")

	# Knife slash strike on river crab
	var crab0: Dictionary = first_by_kind["crab"]
	var crab_cam := Camera3D.new()
	game.add_child(crab_cam)
	crab_cam.position = crab0.pos + Vector3(0.0, 0.55, 1.45)
	crab_cam.look_at(crab0.pos + Vector3(0.0, 0.22, 0.0))
	verify(game.wildlife.melee_strike(crab_cam) and crab0.state == "downed", "tactical knife melee strike downs nearby river crab")
	crab_cam.queue_free()

	var flora0: Node3D = game.wildlife.flora_nodes[0]
	var pre_flora_score: int = game.rules.score
	verify(game.wildlife.interact_flora(flora0) and game.rules.score == pre_flora_score + 5, "first [E] botanical flora study teaches English and awards +5 score")
	game.wildlife.interact_flora(flora0)
	verify(game.rules.score == pre_flora_score + 5, "re-inspecting flora reviews English without duplicating score")

	# Perimeter fence physics wall & open panoramic vista check
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.position = game.Layout.on_ground(Vector3(6.0, 0.0, game.Layout.FENCE_MAX_Z - 1.6)) + Vector3(0, 0.15, 0)
	game.player.yaw = PI  # face straight South toward outer fence & valley
	await frames(4)
	for push_step in 45:
		sim_key.call(KEY_W, true)
		await frames(1)
	sim_key.call(KEY_W, false)
	var fence_wall_hit: Dictionary = ray(Vector3(6.0, game.terrain_height(6.0, game.Layout.FENCE_MAX_Z - 1.0) + 0.55, game.Layout.FENCE_MAX_Z - 2.0), Vector3(6.0, game.terrain_height(6.0, game.Layout.FENCE_MAX_Z - 1.0) + 0.55, game.Layout.FENCE_MAX_Z + 2.0))
	verify(not fence_wall_hit.is_empty() and game.player.position.z < game.Layout.FENCE_MAX_Z - 0.1, "South mountain timber fence stops player physically at perimeter boundary")

	# v0.5.6 Atmospheric vista lighting cohesion checks
	var world_envs: Array = game.landscape.find_children("*", "WorldEnvironment", true, false)
	var env_ok := false
	if not world_envs.is_empty() and (world_envs[0] as WorldEnvironment).environment != null:
		var env_cfg: Environment = (world_envs[0] as WorldEnvironment).environment
		env_ok = (env_cfg.tonemap_mode == Environment.TONE_MAPPER_FILMIC or env_cfg.tonemap_mode == Environment.TONE_MAPPER_AGX) and env_cfg.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and env_cfg.fog_enabled
	verify(env_ok, "v0.5.6 landscape configures Filmic tonemapping, sky ambient lighting, and atmospheric horizon fog")
	var vmesh: MeshInstance3D = valley_node as MeshInstance3D
	verify(vmesh != null and vmesh.mesh != null and vmesh.mesh.get_surface_count() > 0, "OuterRiceValley renders unified terraced paddies and 3D outer foothills")

	# v0.6.0 Jiangnan Rural Hill Heritage landmark & traversability verification
	var arch_bridge: Node = game.landscape.find_child("StoneArchBridge", true, false)
	var boundary_stele: Node = game.landscape.find_child("BoundaryStele", true, false)
	var wangdao_pav: Node = game.landscape.find_child("WangdaoPavilion", true, false)
	var camphor_shrine: Node = game.landscape.find_child("CamphorShrine", true, false)
	var wayside_shrine: Node = game.landscape.find_child("WaysideShrine", true, false)
	var flagstones: MultiMeshInstance3D = game.landscape.find_child("BluestoneFlagstones", true, false) as MultiMeshInstance3D
	verify(arch_bridge != null and boundary_stele != null and wangdao_pav != null and camphor_shrine != null and wayside_shrine != null, "v0.6.0 spawns StoneArchBridge, BoundaryStele, WangdaoPavilion, CamphorShrine, and WaysideShrine")
	verify(flagstones == null, "v0.8.2 V81-2: legacy overlapping 3D BluestoneFlagstones trail slabs removed in favor of crisp ground bluestone shader")
	var poem_node = node_for("poem")
	var poem_pav = poem_node.find_child("poem_stele_pavilion", true, false) if poem_node != null else null
	var obelisk = poem_node.find_child("statue_obelisk", true, false) if poem_node != null else null
	verify(poem_pav != null and obelisk == null, "v0.6.0 replaces Western obelisk with Jiangnan poem_stele_pavilion")
	# v0.8.1 FB-1 / v0.8.5: Walk purely with KEY_W up the +2.75m Grand Bluestone Staircase onto WangdaoPavilion overlook deck!
	var pav_at: Vector3 = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION)
	var wd_dx := float(game.Layout.WANGDAO_PAVILION.x) - 33.5
	var wd_dz := float(game.Layout.WANGDAO_PAVILION.z) - 20.8
	var start_xz: Vector3 = game.Layout.on_ground(Vector3(27.4 + wd_dx, 0.0, 17.1 + wd_dz)) + Vector3(0.0, 0.12, 0.0)
	var target_xz: Vector3 = Vector3(33.2 + wd_dx, pav_at.y + 2.75, 22.1 + wd_dz)
	var walk_dir := Vector2(target_xz.x - start_xz.x, target_xz.z - start_xz.z)
	game.player.clear_movement_input()
	game.player.position = start_xz
	game.player.velocity = Vector3.ZERO
	game.player.yaw = atan2(-walk_dir.x, -walk_dir.y)
	await frames(8)
	game.player.held_keys[KEY_W] = true
	for _f in 240:
		var rem_d := Vector2(target_xz.x - game.player.position.x, target_xz.z - game.player.position.z)
		if rem_d.length() <= 0.30:
			break
		game.player.yaw = atan2(-rem_d.x, -rem_d.y)
		await physics_frame
	game.player.clear_movement_input()
	await frames(6)
	verify(Vector2(game.player.position.x - target_xz.x, game.player.position.z - target_xz.z).length() < 0.75 and game.player.is_on_floor() and game.player.position.y >= pav_at.y + 2.65, "v0.8.1 FB-1: player walks cleanly up Grand Bluestone Staircase onto elevated WangdaoPavilion overlook deck (y=%.2f)" % game.player.position.y)

	# v0.6.1 Concave Pebble Creek, Watertight Valley Collar, Submerged Pilings, Botanical Flora & HUD non-overlap checks
	var bed_node := game.landscape.get_node_or_null("StreamChannelBed") as MeshInstance3D
	verify(bed_node != null and bed_node.mesh != null and bed_node.mesh.get_surface_count() > 0, "v0.6.1 renders StreamChannelBed wet-pebble recessed channel")
	var concave_ok := true
	for tz in [24.0, -14.0, -90.0]:
		var tcx: float = game.Layout.stream_center_x(tz)
		var twy: float = game.Layout.stream_water_y(tz)
		var tbed: float = game.terrain_height(tcx, tz)
		var tbank_l: float = game.terrain_height(tcx - 2.6, tz)
		var tbank_r: float = game.terrain_height(tcx + 2.6, tz)
		if (twy - tbed) < 0.45 or (tbank_l - twy) < 0.32 or (tbank_r - twy) < 0.32:
			concave_ok = false
	verify(concave_ok, "creek sits in a true concave channel (~0.52m below water, >=0.34m below both bank lips)")
	var stream_aabb: AABB = (stream_node as MeshInstance3D).get_aabb()
	verify(stream_aabb.end.z > 180.0, "MountainStreamWater flows continuously past South fence (z=40) into distant village paddies (z>180)")
	var seam_max_err := 0.0
	var max_z_f := float(game.Layout.MAX_Z)
	for sx_i in range(int(game.Layout.MIN_X), int(game.Layout.MAX_X) + 1, 5):
		seam_max_err = maxf(seam_max_err, absf(game.landscape._outer_valley_y(float(sx_i), max_z_f) - game.landscape._ground_vis_y(float(sx_i), max_z_f)))
	verify(seam_max_err < 0.002, "OuterRiceValley South collar matches ContinuousGround z=MAX_Z with zero seam gap")
	var fmax_z_f := float(game.Layout.FENCE_MAX_Z)
	var scx_fmax := float(game.Layout.stream_center_x(fmax_z_f))
	var piling_prof: Vector2 = game.landscape._fence_post_profile(scx_fmax - 0.90, fmax_z_f)
	verify(piling_prof.x < game.Layout.stream_water_y(fmax_z_f) - 0.85, "South fence creek pilings plunge deep into streambed beneath water")
	for batch_id in ["MountainCamphorTrees", "MountainWillowTrees", "MountainMapleTrees", "MosoBambooCulms", "MosoBambooClumps", "VillageWillows", "VillageCamphors", "HillsideGrassTufts", "HillsideAzaleaBushes"]:
		var bnode := game.landscape.get_node_or_null(batch_id) as MultiMeshInstance3D
		verify(bnode != null and bnode.multimesh != null and bnode.multimesh.instance_count > 0, "v0.6.1 MultiMesh batch active: " + batch_id)
	verify(game.mission_label.position.y + game.mission_label.size.y <= game.guide_label.position.y, "Zone 1 top-left HUD mission_label and guide_label do not overlap")

	# v0.6.2 Lost Bamboo-Stone Labyrinth ("迷踪竹石阵") & Yanxia Ancient Cavern ("烟霞古洞") verification
	var maze_node := game.landscape.get_node_or_null("BambooStoneMaze") as Node3D
	var cave_node := game.landscape.get_node_or_null("YanxiaAncientCave") as Node3D
	verify(maze_node != null and cave_node != null, "v0.6.2 spawns BambooStoneMaze and YanxiaAncientCave")
	verify(maze_node.get_node_or_null("BambooMazeSouthGate") != null and maze_node.get_node_or_null("KarstCrouchArch") != null and maze_node.get_node_or_null("CliffMoyaStele") != null and maze_node.get_node_or_null("StoneSundialPedestal") != null, "v0.6.2 maze includes South Gate, KarstCrouchArch, CliffMoyaStele, and StoneSundialPedestal")
	verify(game.crate_nodes.size() >= 6 and str(game.crate_nodes[5].get_meta("title")) == "烟霞古洞秘藏石匣", "v0.6.2 places Tier-3 Yanxia Cavern vault crate at crate_nodes[5]")

	# 1) KarstCrouchArch rigidly translated by (CAVE_DX, CAVE_DZ): blocks standing, passes [C] crouched
	var cdx := float(game.Layout.CAVE_DX)
	var cdz := float(game.Layout.CAVE_DZ)
	var cave_fy := float(game.Layout.CAVE_FLOOR_Y) + 0.026
	game.player.clear_movement_input()
	game.player.reset_stance()
	game.player.position = Vector3(-41.60 + cdx, float(game.terrain_height(-41.60 + cdx, -44.15 + cdz)) + 0.05, -44.15 + cdz)
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0.0
	await frames(6)
	game.player.held_keys[KEY_W] = true
	for _f in 48:
		await physics_frame
	game.player.clear_movement_input()
	await frames(3)
	var stand_blocked_z: float = game.player.position.z
	verify(stand_blocked_z > -45.25 + cdz, "KarstCrouchArch 1.25m lintel blocks standing player (z=%.2f)" % stand_blocked_z)

	sim_key.call(KEY_C, true)
	await frames(2)
	sim_key.call(KEY_C, false)
	await frames(4)
	verify(game.player.stance == 1, "pressing [C] switches player to crouched stance in front of karst arch")
	game.player.yaw = 0.0
	game.player.held_keys[KEY_W] = true
	for _f in 75:
		if game.player.position.z < -46.55 + cdz:
			break
		await physics_frame
	game.player.clear_movement_input()
	await frames(4)
	verify(game.player.position.z < -46.30 + cdz and game.player.is_on_floor(), "crouched player crawls cleanly underneath KarstCrouchArch (z=%.2f)" % game.player.position.z)
	sim_key.call(KEY_C, true)
	await frames(2)
	sim_key.call(KEY_C, false)
	await frames(4)

	# 2) Real walk-in traversal from Cavern Forecourt through South Cliff Portal into YanxiaAncientCave
	game.player.clear_movement_input()
	game.player.position = Vector3(-41.60 + cdx, cave_fy + 0.03, -56.20 + cdz)
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0.0
	await frames(6)
	game.player.held_keys[KEY_W] = true
	for _f in 125:
		if game.player.position.z < -63.80 + cdz:
			break
		await physics_frame
	game.player.clear_movement_input()
	await frames(6)
	verify(game.player.position.z < -62.50 + cdz and game.player.is_on_floor() and absf(game.player.position.y - cave_fy) < 0.18, "player walks seamlessly through Yanxia Cave portal onto wet limestone floor (pos=%s)" % str(game.player.position))
	game.player.position = Vector3(-40.25 + cdx, cave_fy, -65.25 + cdz)
	await frames(4)
	verify(game._can_interact(game.crate_nodes[5]), "Yanxia Cavern Tier-3 vault crate has unobstructed interaction line-of-sight inside Inner Sanctum")

	# 3) All 3 Heritage discoveries ("竹石清音", "耕读图", "寒潭茶灶与古竹简") + minimap reveal + HP/Shield heal + Legendary Bamboo Slips
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN)
	game.exploration.revealed_secrets.clear()
	game.exploration.radar_scan_active = false
	await frames(3)
	verify(not game.minimap._is_discovered(game.crate_nodes[5]), "Yanxia Cavern vault starts masked on minimap before discovering cliff inscription")
	var moya_ev: Node3D = node_for.call("cliff_inscription")
	game.exploration.open(moya_ev)
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("cliff_inscription"))
	game.exploration.close()
	verify(game.exploration.is_secret_revealed("yanxia_cave") and game.minimap._is_discovered(game.crate_nodes[5]), "Moya cliff inscription random spelling reveals Yanxia Cavern secret on minimap")

	game.start_action(true, "normal")
	await frames(4)
	# Verify all 10 exploration spelling nodes draw distinct random 175-pack words per run!
	var seen_spell_words := {}
	for sid in game.exploration.SPELL_CHALLENGE_IDS:
		var ew: String = game.exploration.expected_spelling_word(sid)
		if ew != "":
			seen_spell_words[ew.to_lower()] = true
	verify(seen_spell_words.size() == game.exploration.SPELL_CHALLENGE_IDS.size(), "v0.8.6: all 10 exploration/heritage/intel spelling nodes draw 10 distinct random live words per run")
	game.combat.health = 60
	game.combat.shield = 5.0
	game.rules.bag.clear()
	for hid in ["cave_mural", "cave_hearth"]:
		var hev: Node3D = node_for.call(hid)
		game.exploration.open(hev)
		game.exploration.submit_spelling(game.exploration.expected_spelling_word(hid))
		game.exploration.open_reward_container()
		if game.loot_container_ui.busy:
			game.loot_container_ui.take_all_for_qa()
		else:
			game.exploration.close()
	# Also solve cliff_inscription on this fresh Normal run so heritage_completed() == 3!
	var moya_ev2: Node3D = node_for.call("cliff_inscription")
	game.exploration.open(moya_ev2)
	game.exploration.submit_spelling(game.exploration.expected_spelling_word("cliff_inscription"))
	game.exploration.close()
	verify(game.exploration.heritage_completed() == 3, "all 3 v0.6.2 Yanxia heritage discoveries solve via random English spelling and track in heritage_completed() == 3")
	verify(game.combat.health == 80 and game.combat.shield >= 19.5, "cave_hearth spring tea restores +20 HP and +15 Shield")
	verify(game.rules.bag.size() == 2, "v0.8.6: Yanxia rock petroglyph & hearth roll calibrated probabilistic pyramid loot instead of guaranteed fixed T4/T5")

	# 4) v0.8.0 World Looting (14 ultra-hidden nooks, zero open-road Gold/Red, blind-box crates, clean wildlife tags), [B] Backpack+SafeBox, [I] 3D Turntable, Warehouse Vault & Compendium
	var active_loose := 0
	var open_high_loose := 0
	for lnode in game.world_loot.loose_nodes:
		if lnode.visible and lnode.has_meta("loot_item"):
			active_loose += 1
			if int(lnode.get_meta("loot_item").get("rarity", 1)) >= 5:
				open_high_loose += 1
	var overcharged_cnt := 0
	for pnode in game.pickup_nodes:
		if pnode.has_meta("overcharged"):
			overcharged_cnt += 1
	verify(active_loose == 7 and open_high_loose == 0 and game.world_loot.nest_nodes.size() == 20 and overcharged_cnt == 2 and game.world_loot.overcharged_halos.is_empty(), "v0.8.6 spawns 7 modest open-road relics (0 Gold/Red), 20 ultra-hidden nooks, and 2 spoiler-free blind-box caches")
	var spoiler_crates := 0
	for cnode in game.crate_nodes:
		for cl in cnode.find_children("*", "Label3D", true, false):
			var ct := str((cl as Label3D).text)
			if "大金" in ct or "大红" in ct or "史诗" in ct:
				spoiler_crates += 1
	verify(spoiler_crates == 0, "v0.8.0 blind-box vault crates carry zero rarity-spoiler text on 3D tags")
	# v0.8.0 #14: Wildlife & flora overhead tags hidden by default for clean scenic landscape
	game.wildlife.reset()
	var visible_eco_labels := 0
	for wa in game.wildlife.animals:
		if wa.label.visible:
			visible_eco_labels += 1
	for wf in game.wildlife.flora_nodes:
		if (wf.get_meta("label_node") as Label3D).visible:
			visible_eco_labels += 1
	verify(visible_eco_labels == 0, "v0.8.0 hides all permanent wildlife and flora overhead labels by default for clean mountain scenery")

	# v0.8.4: Open-world 3D single loose relic opens confirmation panel (leave in place OR pick up!)
	var tent_loose: Node3D = game.world_loot.loose_nodes[0]
	var pre_loose_bag: int = game.rules.bag.size()
	game.player.position = tent_loose.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	verify(game.loot_container_ui.busy and game.loot_container_ui.active_kind == "loose" and game.rules.bag.size() == pre_loose_bag and tent_loose.visible, "v0.8.4: pressing [F] on single ground loose relic opens confirmation pickup panel instead of auto-stuffing")
	game.loot_container_ui.close()
	verify(not game.loot_container_ui.busy and tent_loose.visible and game.rules.bag.size() == pre_loose_bag, "v0.8.4: leaving single loose relic panel preserves the 3D relic on pedestal")
	game.interact()
	game.loot_container_ui.take_item_to_bag(0)
	verify(game.rules.bag.size() == pre_loose_bag + 1 and not tent_loose.visible and game.loot_ui.toast_panel.visible, "v0.8.4: confirming single loose relic collects item, hides relic & triggers HUD toast")

	# Search a tactile Bird Nest ('掏鸟窝') via quick-search progress bar -> opens LootContainerUI!
	var nest0: Node3D = game.world_loot.nest_nodes[0]
	var pre_nest_bag: int = game.rules.bag.size()
	game.player.position = nest0.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	verify(game.loot_ui.active_search_node == nest0 and game.loot_ui.search_panel.visible, "interacting with Bird Nest starts tactile magnifying-glass quick-search bar")
	game.loot_ui.complete_active_search_for_qa()
	verify(game.loot_container_ui.busy and game.loot_container_ui.active_kind == "nest" and nest0.visible, "v0.8.4: completing Bird Nest search opens selective confirmation pickup panel")
	game.loot_container_ui.take_item_to_bag(0)
	verify(game.rules.bag.size() == pre_nest_bag + 1 and not nest0.visible, "confirming Bird Nest pickup collects surprise loot and hides empty nest")

	# Spawn & inspect an Enemy Squad Wave Drop Pouch via LootContainerUI (selective leave + revisit!)
	var pouch_pos: Vector3 = game.Layout.on_ground(Vector3(-6.0, 0.0, -12.0))
	var pouch: Node3D = game.world_loot.spawn_squad_drop(pouch_pos, "林间古道营地", true, false)
	var pre_pouch_bag: int = game.rules.bag.size()
	game.player.position = pouch.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	verify(game.loot_container_ui.busy and game.loot_container_ui.active_kind == "squad_drop" and game.loot_container_ui.pending_items.size() >= 1, "v0.8.4: interacting with enemy wave drop pouch opens zero-typing selective LootContainerUI")
	game.loot_container_ui.take_all_for_qa()
	verify(game.rules.bag.size() > pre_pouch_bag and not pouch.visible, "claiming flawless enemy wave drop pouch transfers multi-slot battle loot into bag")

	# Test [B] Tactical Backpack modal & [I] 3D Relic Turntable Showcase + Camp Compendium
	game.loot_ui.toggle_backpack()
	verify(game.loot_ui.busy_bag and game.paused and game.loot_ui.bag_grid.get_child_count() == game.rules.capacity(), "[B] opens Tactical Backpack grid matching player capacity")
	game.loot_ui.toggle_backpack()
	verify(not game.loot_ui.busy_bag and not game.paused, "pressing [B] again closes Tactical Backpack and resumes field play")

	game.loot_ui.inspect_best_in_bag()
	verify(game.loot_ui.busy_inspect and game.loot_ui.inspect_turntable.get_child_count() >= 3, "[I] opens 3D Relic Turntable Showcase with procedural 3D sculpture on spinning pedestal")
	game.loot_ui.close_inspect()
	verify(not game.loot_ui.busy_inspect and not game.paused, "closing 3D Relic Turntable resumes field play")

	game._end_run(false)
	game.compendium_button.pressed.emit()
	verify(game.loot_ui.busy_compendium and game.loot_ui.comp_grid.get_child_count() >= 31, "Camp Compendium button opens bilingual Yanshan Curios & Mythic Red gallery with all 31 catalog cards")
	game.loot_ui.close_compendium()

	# v0.6.4 Qinglü Art, Multi-Surface Weapons, Sculpted Props & Locked-Shoulder CQB Knife Verification
	game.start_action(false)
	await frames(6)
	var wv64 = game.player.weapon_view
	verify(wv64.pose_cache.size() >= 10 and wv64.rifle_meshes[0].mesh.get_surface_count() >= 5, "v0.6.4 loads 10 CQB/rifle poses and 5-surface Qinglu-tactical YS-04 carbine")
	game.player.select_weapon(1)
	game.player.weapon_root.position = Vector3(0.0, -0.145, -0.35)
	var skel64: Skeleton3D = wv64.arms_skeleton
	var up_r_idx: int = skel64.find_bone("upperarm.R")
	var up_l_idx: int = skel64.find_bone("upperarm.L")
	var shoulder_always_behind_cam := true
	for combo_i in [0, 1]:
		for phase_u in [0.0, 0.18, 0.36, 0.50, 0.78]:
			wv64.slash_combo = combo_i
			wv64.slash_left = wv64.slash_duration * (1.0 - phase_u) if phase_u > 0.0 else 0.0
			wv64.animate(0.0, 0.0, 0.0, false)
			var sr_world: Vector3 = skel64.global_transform * skel64.get_bone_global_pose(up_r_idx).origin
			var sl_world: Vector3 = skel64.global_transform * skel64.get_bone_global_pose(up_l_idx).origin
			var sr_cam: Vector3 = game.player.camera.to_local(sr_world)
			var sl_cam: Vector3 = game.player.camera.to_local(sl_world)
			if sr_cam.z <= 0.01 or sl_cam.z <= 0.01:
				shoulder_always_behind_cam = false
	verify(shoulder_always_behind_cam, "v0.6.4 locks both left and right shoulder joints strictly behind Camera3D lens across all knife idle/windup/slash frames")

	var camphor_tree_mesh: Mesh = game.landscape._extract_mesh("res://assets/slice/v061_nature_wildlife.glb", "tree_camphor")
	var has_qinglu_shader := false
	if camphor_tree_mesh != null:
		for si in camphor_tree_mesh.get_surface_count():
			if camphor_tree_mesh.surface_get_material(si) is ShaderMaterial and (int(camphor_tree_mesh.surface_get_format(si)) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				has_qinglu_shader = true
	verify(has_qinglu_shader and game.world_loot.drop_case_mesh != null, "v0.6.4 binds Qinglu volumetric ShaderMaterial with baked COLOR_0 on trees and sculpted v064_world_props meshes")

	# v0.8.2 Scene Polish, Reload Optic Lock, Cave Perimeter Seal, Achievements & 3D Physical Weapon Charms (V81-1..11)
	# V81-4: Cave Mural heritage spelling popup has zero overlap between story body and spelling input bar
	var mural_nd = node_for("cave_mural")
	if mural_nd != null:
		game.exploration.open(mural_nd)
		await frames(2)
		var body_bottom: float = game.exploration.body.position.y + game.exploration.body.size.y
		var spell_top: float = game.exploration.spell_box.position.y
		verify(game.exploration.spell_box.visible and spell_top >= body_bottom + 4.0, "v0.8.6: Yanxia Cave mural body text clears spelling input bar with zero overlap (gap=%.1fpx)" % (spell_top - body_bottom))
		game.exploration.close()
	# V81-6 / v0.8.5: Exterior Yanxia Cave West/East walls & Maze row-6 corners block raycast penetration cleanly
	var sp82: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var ray_y := float(game.Layout.CAVE_FLOOR_Y) + 1.5
	var cave_w_ray := PhysicsRayQueryParameters3D.create(Vector3(-50.0 + cdx, ray_y, -61.0 + cdz), Vector3(-43.0 + cdx, ray_y, -61.0 + cdz), 1)
	var cave_e_ray := PhysicsRayQueryParameters3D.create(Vector3(-33.0 + cdx, ray_y, -61.0 + cdz), Vector3(-40.0 + cdx, ray_y, -61.0 + cdz), 1)
	var seam_w_ray := PhysicsRayQueryParameters3D.create(Vector3(-47.5 + cdx, ray_y, -56.2 + cdz), Vector3(-47.5 + cdx, ray_y, -60.5 + cdz), 1)
	var seam_e_ray := PhysicsRayQueryParameters3D.create(Vector3(-35.7 + cdx, ray_y, -56.2 + cdz), Vector3(-35.7 + cdx, ray_y, -60.5 + cdz), 1)
	var cave_sealed: bool = (not sp82.intersect_ray(cave_w_ray).is_empty()) and (not sp82.intersect_ray(cave_e_ray).is_empty()) and (not sp82.intersect_ray(seam_w_ray).is_empty()) and (not sp82.intersect_ray(seam_e_ray).is_empty())
	verify(cave_sealed, "v0.8.5: Yanxia Ancient Cave exterior rock cliffs and Maze row-6 corner seams are watertight solid in West Bamboo Ravine")
	# V81-7: Zero spoiler label "迷踪竹石阵 · 东侧幽径" in maze
	var has_secret_spoiler := false
	for lbl3 in game.landscape.find_children("*", "Label3D", true, false):
		if (lbl3 as Label3D).text.contains("东侧幽径"):
			has_secret_spoiler = true
	verify(not has_secret_spoiler, "v0.8.2 V81-7: secret Bamboo Maze east entrance has zero spoiler floating text")
	# V81-9: Mid-reload optic stays rigidly locked to rifle inside gun_pivot (0.000m drift!)
	game.player.select_weapon(0)
	wv64.animate(0.016, 0.0, 0.0, false)
	var optic_rel_idle: Vector3 = wv64.rifle.to_local(wv64.optic_root.global_position)
	wv64.animate(0.016, 0.50, 0.0, false)
	var optic_rel_reload: Vector3 = wv64.rifle.to_local(wv64.optic_root.global_position)
	verify(optic_rel_idle.distance_to(optic_rel_reload) < 0.001 and wv64.optic_root.get_parent() == wv64.gun_pivot, "v0.8.2 V81-9: optic stays rigidly locked to rifle rail during reload animation (zero drift)")
	# v0.8.5: Relocated rear upper-receiver charm directly below optic left flank (z >= +0.075 -> clear of BOTH front & rear hands!)
	game.achievements.record_wildlife_kill("boar")
	for _sqk in 10:
		game.achievements.record_wildlife_kill("squirrel")
	var ach_unlocked_ok: bool = game.achievements.is_unlocked("boar_1") and game.achievements.is_unlocked("sq_10") and game.achievements.is_charm_unlocked("charm_roast")
	game.achievements.equip_charm("charm_roast")
	var charm_under_optic_clear: bool = (wv64.charm_anchor.position.x + wv64.charm_pendulum.position.x) <= -0.036 and wv64.charm_anchor.position.z >= 0.075 and wv64.charm_visual_root.scale.x >= 1.10
	verify(ach_unlocked_ok and wv64.equipped_charm_id == "charm_roast" and wv64.charm_anchor.visible and wv64.charm_visual_root.get_child_count() >= 2 and charm_under_optic_clear, "v0.8.5: weapon charm mounts on rear upper receiver below optic left flank (z>=0.075) clear of both hands")
	# v0.8.5 Great Yanshan 3x Map Expansion, Camp Spacing (>=60m), Isolated Cave (>=60m) & New Blender 4.5 Landmarks
	var playable_w: float = float(game.Layout.FENCE_MAX_X) - float(game.Layout.FENCE_MIN_X)
	var playable_d: float = float(game.Layout.FENCE_MAX_Z) - float(game.Layout.FENCE_MIN_Z)
	verify(playable_w >= 179.0 and playable_d >= 239.0 and playable_w * playable_d >= 43000.0, "v0.8.5: Great Yanshan playable area expanded 3x to 180m x 240m (%.0f m2)" % (playable_w * playable_d))
	var min_camp_gap := 9999.0
	for ci in game.Layout.COMBAT_ZONES.size():
		for cj in range(ci + 1, game.Layout.COMBAT_ZONES.size()):
			var pa: Vector3 = game.Layout.COMBAT_ZONES[ci].at
			var pb: Vector3 = game.Layout.COMBAT_ZONES[cj].at
			min_camp_gap = minf(min_camp_gap, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	var min_cave_gap := 9999.0
	for camp_z in game.Layout.COMBAT_ZONES:
		var cp: Vector3 = camp_z.at
		min_cave_gap = minf(min_cave_gap, Vector2(cp.x - game.Layout.YANXIA_CAVE_CENTER.x, cp.z - game.Layout.YANXIA_CAVE_CENTER.z).length())
	verify(min_camp_gap >= 60.0 and min_cave_gap >= 60.0, "v0.8.5: all 6 Fogveil camps spaced >=60m apart (min=%.1fm) and Yanxia Cave isolated >=60m (min=%.1fm)" % [min_camp_gap, min_cave_gap])
	var cloud_arena: Node = game.landscape.get_node_or_null("CloudTopMartialArena")
	var multi_bridge: Node = game.landscape.get_node_or_null("TripleArchStoneBridge")
	var tea_pav: Node = game.landscape.get_node_or_null("TeaHillPavilion")
	var cliff_stele: Node = game.landscape.get_node_or_null("YanshanCliffStele")
	var arena_pillars: int = cloud_arena.find_children("ArenaDragonPillar_*", "Node3D", false, false).size() if cloud_arena != null else 0
	var arena_flat_ok := absf(float(game.terrain_height(game.Layout.CLOUD_ARENA_CENTER.x, game.Layout.CLOUD_ARENA_CENTER.z)) - float(game.Layout.CLOUD_ARENA_Y)) < 0.08
	verify(cloud_arena != null and arena_pillars == 8 and arena_flat_ok and multi_bridge != null and tea_pav != null and cliff_stele != null, "v0.8.5: spawns 38m flat CloudTopMartialArena (8 dragon pillars), TripleArchStoneBridge, TeaHillPavilion & YanshanCliffStele")
	# v0.8.6: Multi-layer cloud-wreathed distant mountains, fixed outward Wangdao signboard & handcrafted Jiangnan architecture/scenery
	var peaks_3d: Node = game.landscape.get_node_or_null("DistantPeaksRing3D")
	var cloud_outer: Node = game.landscape.get_node_or_null("MistyCloudSeaOuter")
	var cloud_inner: Node = game.landscape.get_node_or_null("MistyCloudSeaInner")
	var wangdao_sign: Node3D = game.landscape.find_child("WangdaoSignpost", true, false) as Node3D
	var sign_fwd: Vector3 = wangdao_sign.global_transform.basis.z if wangdao_sign != null else Vector3.ZERO
	var tower_nd: Node = game.find_child("JiangnanWatchtower", true, false)
	var tower_vis: Node = tower_nd.get_node_or_null("WatchtowerVisual") if tower_nd != null else null
	var arch_forest: Node = game.landscape.get_node_or_null("TrailArchGate_Forest")
	var arch_cloud: Node = game.landscape.get_node_or_null("TrailArchGate_CloudArena")
	var count_batch := func(batch_prefix: String) -> int:
		var total := 0
		for ch in game.landscape.get_children():
			if ch.name == batch_prefix or ch.name.begins_with(batch_prefix + "_"):
				if ch is MultiMeshInstance3D and (ch as MultiMeshInstance3D).multimesh != null:
					total += (ch as MultiMeshInstance3D).multimesh.instance_count
		return total
	var lantern_cnt: int = count_batch.call("JiangnanStoneLanterns")
	var hedge_cnt: int = count_batch.call("JiangnanTeaHedges")
	var boulder_cnt: int = count_batch.call("MossyBoulderClusters")
	var bench_cnt: int = count_batch.call("ScenicStoneBenches")
	verify(
		peaks_3d != null and cloud_outer != null and cloud_inner != null,
		"v0.8.6: spawns 3D DistantPeaksRing3D and dual counter-drifting MistyCloudSea cloud belts"
	)
	verify(
		wangdao_sign != null and sign_fwd.x < -0.45 and sign_fwd.z < -0.45,
		"v0.8.6: Wangdao Pavilion signboard faces outward NW toward approaching trail (fwd=%s)" % str(sign_fwd)
	)
	var wangdao_built: Node = wangdao_pav.find_child("wangdao_pavilion_complete", true, false) if wangdao_pav != null else null
	verify(
		tower_vis != null and wangdao_built != null and arch_forest != null and arch_cloud != null
		and lantern_cnt >= 16 and hedge_cnt >= 20 and boulder_cnt >= 20 and bench_cnt >= 6,
		"v0.8.6: mounts unified WangdaoPavilion, JiangnanWatchtower, 2 mountain arch gates, stone lanterns(%d), tea hedges(%d), mossy boulders(%d) & scenic benches(%d)" % [lantern_cnt, hedge_cnt, boulder_cnt, bench_cnt]
	)
	game._end_run(false)
	game.loot_ui.open_compendium("achievements")
	verify(game.loot_ui.busy_compendium and game.loot_ui.comp_grid.get_child_count() == game.achievements.CATALOG.size(), "v0.8.2 V81-10/11: Compendium exposes Achievements & Weapon Charms Hall with all 24 achievement cards")
	game.loot_ui.close_compendium()

	# 7) v0.8.2_dev1 C1/C6: Editable Prologue Scene E2E, Comfort Settings & Dual-Layer Cultural Specimen Card!
	var pro_packed = load("res://scenes/prologue_chapter.tscn")
	verify(pro_packed is PackedScene and is_instance_valid(game.prologue), "v0.8.2_dev1 C1: editable prologue_chapter.tscn loads cleanly and mounts Prologue controller")
	game.rules.profile["prologue_completed"] = false
	var coins_before_pro: int = int(game.rules.profile.coins)
	game.start_prologue_chapter(true)
	await frames(4)
	verify(game.rules.prologue_mode and game.prologue.active and game.prologue.busy and game.prologue.stage == "skirmish", "v0.8.2_dev1 C1: Prologue opens Camp Guide briefing modal cleanly")
	game.prologue.close_modal()
	# Wrong scout hit gives friendly hint (no wipe), then clearing all 3 scouts advances to Wangdao Beacon clue!
	var wrong_sc_idx: int = (game.prologue.active_scout_idx + 1) % game.prologue.scouts.size()
	game.prologue.hit_bullet(game.prologue.scouts[wrong_sc_idx].area)
	verify(game.prologue.scouts_cleared == 0 and game.prologue.stage == "skirmish", "v0.8.2_dev1 C1: wrong prologue scout hit gives friendly feedback without wiping player")
	for _ps in 3:
		var t_idx: int = game.prologue.active_scout_idx
		game.prologue.hit_bullet(game.prologue.scouts[t_idx].area)
	verify(game.prologue.scouts_cleared == 3 and game.prologue.stage == "beacon_clue", "v0.8.2_dev1 C1: clearing 3 East Ridge scouts unlocks Wangdao Beacon investigation")
	# Wangdao Beacon bilingual clue: gentle retry on wrong choice -> records non-first-try honestly -> solve -> Yanxia Cave cliffhanger!
	game.prologue.open_beacon_clue()
	game.prologue.modal_choice_btns[1].pressed.emit()
	verify(not game.prologue.clue_solved and game.prologue.modal_choice_btns[1].disabled, "v0.8.2_dev1 C1: wrong prologue clue choice grants hint and allows gentle retry (no hard lock)")
	game.prologue.modal_choice_btns[0].pressed.emit()
	verify(game.prologue.clue_solved and not game.prologue.clue_first_try_correct and game.prologue.stage == "return_camp" and game.prologue.modal_body.text.contains("器物考据"), "v0.8.2_dev1 C1/C6: solving Wangdao clue shows dual-layer celadon lore, Yanxia Cave lead & advances to camp hand-in")
	game.prologue.close_modal()
	# Task Log [J] re-read check
	game.prologue.open_task_log()
	verify(game.prologue.busy and game.prologue.modal_body.text.contains("烟霞古洞"), "v0.8.2_dev1 C1: Prologue Task Log allows re-reading dialogue and clues anytime")
	game.prologue.close_modal()
	# Return to Camp NPC to hand in beacon & trigger settlement
	game.prologue.open_npc_dialogue()
	verify(bool(game.rules.profile.get("prologue_completed", false)) and int(game.rules.profile.coins) >= coins_before_pro + 120 and game.menu_summary.text.contains("烟霞古洞"), "v0.8.2_dev1 C1: Camp NPC hand-in completes Prologue, awards starter coins & sets up Yanxia Cave hook")

	# Comfort & Accessibility Settings (reduce_screen_shake, audio sliders, sensitivity)
	game.rules.set_setting("reduce_screen_shake", true)
	game.rules.set_setting("sfx_volume", 0.5)
	game.rules.set_setting("voice_volume", 0.85)
	game.rules.set_setting("mouse_sensitivity", 1.55)
	game._sync_settings_ui()
	game.player.screen_shake = 0.0
	game.player.add_screen_shake(0.95)
	verify(is_equal_approx(game.player.screen_shake, 0.0) and game.setting_shake_cb.button_pressed and is_equal_approx(game.setting_sens_slider.value, 1.55), "v0.8.2_dev1 C6: reduce_screen_shake zeroes camera shake and comfort settings sync cleanly to UI")
	game.rules.set_setting("reduce_screen_shake", false)

	# Dual-layer Cultural Specimen Card in 3D Compendium Inspector
	game.loot_ui.open_inspect_item(game.Rules.LOOT_TABLE[7][0]) # 越窑秘色青瓷盏
	verify(game.loot_ui.inspect_lore_label.text.contains("【烟山物语（游戏设定）】") and game.loot_ui.inspect_lore_label.text.contains("【器物考据（历史资料）】"), "v0.8.2_dev1 C6: 3D Relic Inspector separates in-game fiction from verifiable historical museum notes")
	game.loot_ui.close_inspect()

	# 8) v0.8.2_dev2 D2-4 & D2-6: Forest Outpost Board Terrain Clearance, Cave Warden Hunt Lock & Normal/Conf Cave Reward Balance!
	var all_boards_clear := true
	for st_node in game.stations:
		for bi in st_node.boards.size():
			var bd: Node3D = st_node.boards[bi]
			var b_pos: Vector3 = bd.global_position
			var b_right: Vector3 = bd.global_transform.basis.x
			var b_fwd: Vector3 = bd.global_transform.basis.z
			var b_bottom_y := b_pos.y - 0.80
			var max_local_y := -999.0
			for sx in [-1.62, 0.0, 1.62]:
				for sz in [-0.14, 0.14]:
					var wp: Vector3 = b_pos + b_right * sx + b_fwd * sz
					max_local_y = maxf(max_local_y, float(game.terrain_height(wp.x, wp.z)))
			if b_bottom_y < max_local_y + 0.50:
				all_boards_clear = false
				print("BOARD_CLIP ", st_node.station_id, " idx=", bi, " bottom=", b_bottom_y, " terrain=", max_local_y)
	verify(all_boards_clear, "v0.8.2_dev2 D2-6: all 12 word target boards across all 3 stations sit strictly above hillside terrain with zero clipping")

	# Cave Warden hunt blocks cave_hearth interaction; cave_hearth tests random English spelling & rolls calibrated probabilistic drop!
	game.start_action(true, "normal")
	await frames(2)
	var hearth_nd = node_for("cave_hearth")
	game.cave_warden.state = "hunt"
	game.exploration.open(hearth_nd)
	verify(not game.exploration.busy, "v0.8.6: Cave Warden active hunt blocks casual interaction with cave_hearth")
	game.cave_warden.state = "patrol"
	game.exploration.open(hearth_nd)
	var hearth_w1: String = game.exploration.expected_spelling_word("cave_hearth")
	game.exploration.submit_spelling(hearth_w1)
	game.exploration.open_reward_container()
	game.loot_container_ui.take_all_for_qa()
	var norm_cave_item: Dictionary = game.rules.bag[game.rules.bag.size() - 1]
	verify(hearth_w1 != "" and int(norm_cave_item.get("rarity", 0)) >= 1 and int(norm_cave_item.get("rarity", 0)) <= 7, "v0.8.6: Normal cave_hearth tests random English word (%s) and rolls probabilistic pyramid drop" % hearth_w1)
	# Statistical check over 300 Normal exploration_deep rolls: White/Green/Blue must form >=65% majority & Gold+ <=10% (NO guaranteed Purple/Gold!)
	var low_cnt := 0
	var high_cnt := 0
	for _er in 300:
		var rr: int = game.rules.roll_calibrated_rarity(false, "exploration_deep", true)
		if rr <= 3:
			low_cnt += 1
		elif rr >= 5:
			high_cnt += 1
	verify(low_cnt >= 200 and high_cnt <= 30, "v0.8.6: 300 Normal exploration_deep rolls follow calibrated pyramid (White-Blue=%d/300, Gold+=%d/300)" % [low_cnt, high_cnt])

	game._end_run(false)
	game.start_action(true, "confidential")
	await frames(2)
	var active_ammo_conf := 0
	for p2 in game.pickup_nodes:
		if str(p2.get_meta("tactical_item", "")) == "ammo_crate" and p2.visible:
			active_ammo_conf += 1
	verify(active_ammo_conf <= 4 and game.cave_warden.hp == 360, "v0.8.6: Confidential mode limits ground ammo crates to <= 4 and uses mechanical Cave Warden (360 HP)")
	game.exploration.open(hearth_nd)
	var hearth_w2: String = game.exploration.expected_spelling_word("cave_hearth")
	game.exploration.submit_spelling(hearth_w2)
	game.exploration.open_reward_container()
	game.loot_container_ui.take_all_for_qa()
	var conf_cave_item: Dictionary = game.rules.bag[game.rules.bag.size() - 1]
	verify(hearth_w2 != "" and int(conf_cave_item.get("rarity", 0)) >= 1 and int(conf_cave_item.get("rarity", 0)) <= 7, "v0.8.6: Confidential cave_hearth tests live random English word (%s) and rolls calibrated Confidential pyramid drop" % hearth_w2)
	game._end_run(false)

	# 9) v0.8.3 R1/R3: Ranger '少羽' Profile, Camp Liaison NPC Bounty ('烟山名望') & Character Codex Tab ('人物小记')
	game.start_action(true, "normal")
	await frames(3)
	verify(is_instance_valid(game.rangers) and game.rangers.camp_npc_node.visible and not game.rangers.active_bounty.is_empty(), "v0.8.3 R3: Camp Liaison NPC '陈向导' stands in camp and assigns a random Reputation bounty in Combat")
	game.player.position = game.rangers.camp_npc_node.position + Vector3(0.0, 0.1, 1.8)
	await frames(2)
	game.interact()
	verify(game.rangers.busy and game.paused and game.rangers.is_card_unlocked("chen_guide"), "v0.8.3 R3: interacting [F] with Camp Liaison opens Ranger/Bounty modal and unlocks '陈向导' character card")
	var first_b_id: String = str(game.rangers.active_bounty.id)
	game.rangers._reroll_bounty()
	verify(str(game.rangers.active_bounty.id) != first_b_id and game.rangers.bounty_rerolled, "v0.8.3 R3: Camp Liaison supports one-time random bounty reroll per run")
	game.rangers.close_npc_modal()
	var rep_before: int = game.rangers.reputation()
	var coins_before_b: int = int(game.rules.profile.coins)
	var b_ev: String = str(game.rangers.active_bounty.event)
	var b_tgt: int = int(game.rangers.active_bounty.target)
	game.rangers.record_bounty_progress(b_ev, b_tgt, true)
	verify(game.rangers.bounty_done and game.rangers.reputation() > rep_before and int(game.rules.profile.coins) > coins_before_b, "v0.8.3 R3: completing Camp Liaison bounty awards Yanshan Reputation ('烟山名望') and coins")
	game.rangers.unlock_card("vanguard_boss", false)
	game.rangers.unlock_card("cave_warden", false)
	game._end_run(false)
	game.loot_ui.open_compendium("characters")
	verify(game.loot_ui.busy_compendium and game.loot_ui.comp_grid.get_child_count() == game.rangers.CHARACTER_CARDS.size(), "v0.8.3 R3: Compendium exposes '👤 人物小记' tab listing all 8 Ranger & enemy character cards")
	game.loot_ui.close_compendium()

	# 10) v0.9.7 Yanshan Solid Scenery Colliders, Sculpted Chen Guide Rig & Animated Mistbound Skeletal Troops
	var y_sc_body := game.landscape.find_child("YanshanSceneryColliders", true, false) as StaticBody3D
	verify(is_instance_valid(y_sc_body) and y_sc_body.is_in_group("solid_props") and y_sc_body.get_child_count() >= 200, "v0.9.7: YanshanSceneryColliders provides solid physics collision for all tea hedges, mossy boulders, lanterns, benches, fallen logs & shrubs (%d shapes)" % (y_sc_body.get_child_count() if is_instance_valid(y_sc_body) else 0))
	var chen_rig: Node = game.rangers.camp_npc_node.find_child("ChenGuideRig", true, false)
	var chen_col: Node = game.rangers.camp_npc_node.find_child("ChenGuideCollider", true, false)
	verify(chen_rig != null and chen_col != null, "v0.9.7: Camp Liaison Chen Guide loads sculpted animated npc_chen_guide.glb with solid collider")
	game.start_action(true, "normal")
	await frames(3)
	var skel_bots := 0
	for zid in game.combat.troops.keys():
		for bot in game.combat.troops[zid]:
			if is_instance_valid(bot) and bot.find_child("MistboundSkeletalRig", true, false) != null:
				skel_bots += 1
	verify(skel_bots >= 6, "v0.9.7: Yanshan Mistbound Assault & Sniper soldiers use sculpted animated skeletal rigs (%d active)" % skel_bots)
	game._end_run(false)

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SLICE_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
