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
	game.start_action(false)
	await frames(3)
	verify(game.VERSION == "0.6.1" and game.words.size() == 175 and game.crate_nodes.size() == 5, "v0.6.1 slice uses 175-entry word pack and 5 tiered vault crates")
	var tac_counts := {"ammo_crate": 0, "smoke_emp": 0, "energy_drink": 0}
	var supply_count := 0
	for p in game.pickup_nodes:
		var t_id := str(p.get_meta("tactical_item", ""))
		if tac_counts.has(t_id):
			tac_counts[t_id] += 1
		else:
			supply_count += 1
	verify(supply_count == 10 and tac_counts["ammo_crate"] >= 9 and tac_counts["smoke_emp"] >= 4 and tac_counts["energy_drink"] >= 3, "v0.6.0 places 10 supply caches plus parkour tactical ammo/smoke/stims")
	verify(game.exploration.nodes.size() == 10, "v0.6.0 spawns 4 classic exploration + 4 field intel + recon radio + airdrop beacon")
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
	verify(game.exploration.states.english and game.rules.bag.size() == 1 and not node_for("english").visible, "following next to collects the physical supply and removes its collider")
	var bag = game.rules.bag.size()
	game.exploration.open(node_for("english"))
	verify(game.rules.bag.size() == bag, "English discovery cannot be claimed twice")

	await enter("poem")
	verify(game.exploration.busy, "stone tablet is reachable from its branch")
	var poem_ans = game.exploration.answer_button_index("poem")
	game.exploration.buttons[(poem_ans + 1) % 3].pressed.emit()
	verify(not game.exploration.states.poem and game.rules.bag.size() == bag, "wrong poem answer gives feedback without a reward")
	game.exploration.buttons[poem_ans].pressed.emit()
	verify(game.exploration.states.poem and game.exploration.states.poem_claimed and game.rules.bag.size() == bag + 1, "correct poem answer unlocks and rewards the stone compartment")
	game.exploration.choose(poem_ans)
	verify(game.rules.bag.size() == bag + 1, "repeated solved-puzzle click cannot duplicate loot")
	game.exploration.close()
	verify(game.question.id == old_id and game.rules.score == 0 and game.rules.answered == 0, "optional learning keeps the pending English question and its accuracy untouched")

	while game.rules.bag.size() < game.rules.capacity():
		game.rules.add_loot("filled", 1, 1)
	var gate_at = game.exploration.gate.global_position + Vector3(1.4, 1.1, 0)
	verify(not ray(gate_at + Vector3(0, 0, 3), gate_at - Vector3(0, 0, 3)).is_empty(), "closed shortcut gate blocks a real world ray")
	await enter("math")
	var math_ans = game.exploration.answer_button_index("math")
	game.exploration.buttons[math_ans].pressed.emit()
	verify(game.exploration.states.math and not game.exploration.states.math_claimed, "full bag preserves the solved math reward for later")
	await frames(2)
	verify(ray(gate_at + Vector3(0, 0, 3), gate_at - Vector3(0, 0, 3)).is_empty(), "solved math puzzle opens the gate's collision")
	game.exploration.close()
	await enter("math")
	verify(not game.exploration.states.math_claimed and game.exploration.swap_button.visible, "revisiting a full-bag puzzle keeps its unclaimed reward")
	game.exploration.swap_button.pressed.emit()
	verify(game.exploration.states.math_claimed and game.rules.bag.size() == game.rules.capacity(), "full-bag UI swaps one lowest-value item for the pending reward")
	game.exploration.swap_button.pressed.emit()
	verify(game.rules.bag.size() == game.rules.capacity(), "repeated reward swap cannot duplicate an item")
	game.exploration.close()
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
	verify(game.cipher_terminal.unlocked and game.rules.crates.size() == 1, "completing stage 2 phrase unlocks Tier-1 crate")
	game.cipher_terminal.close()
	verify(not game.cipher_terminal.busy and not game.paused, "closing cipher terminal resumes field play")

	# Test Tier-3 Legendary Gold Airdrop Pod (3 stages: word -> phrase -> sentence + contraction equivalence + full-bag overflow swap)
	verify(game.cipher_terminal._is_match("it is your turn", {"english": "It’s your turn."}) and game.cipher_terminal._is_match("it's your turn", {"english": "It’s your turn."}), "sentence matcher accepts contractions, expanded forms, and omitted punctuation")
	game.player.position = game.crate_nodes[2].position + Vector3(0, 0.1, 1.6)
	await frames(3)
	game.interact()
	verify(game.cipher_terminal.busy and game.cipher_terminal.stage_count() == 3, "Tier-3 gold airdrop pod requires 3-stage word+phrase+sentence unlock")
	verify(str(game.cipher_terminal.stages[2].get("kind", "")) == "sentence", "Tier-3 final stage challenges a full Grade 5A sentence")
	game.cipher_terminal.solve_all_for_qa()
	verify(game.cipher_terminal.unlocked and game.rules.crates.size() == 2 and game.cipher_terminal.displayed_loot.size() == 3, "solving all 3 stages unlocks Tier-3 pod and rolls all 3 high-tier items even on full bag")
	verify(game.cipher_terminal.swap_button.visible and game.crate_nodes[2].get_meta("lid_node").rotation.x < -0.4, "Tier-3 pod opens its armored lid and offers overflow swap for full bag")
	game.cipher_terminal.swap_button.pressed.emit()
	game.cipher_terminal.close()

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
	game.exploration.choose(game.exploration.answer_button_index("intel_container"))
	game.exploration.close()
	await frames(2)
	verify(game.exploration.is_secret_revealed("parkour_containers") and game.minimap._is_discovered(game.crate_nodes[4]), "intel_container English clue reveals West Cargo Vault on minimap")
	verify(game.rules.score >= pre_score + 20 and not game.minimap._is_discovered(game.crate_nodes[2]), "single intel note only reveals its own secret and awards +20 score")

	game.rules.combat_mode = true
	game.player.reserve_ammo = 15
	var pre_gren := int(game.player.grenades)
	var pre_bag: int = game.rules.bag.size()
	var radio_node: Node3D = node_for.call("recon_radio")
	game.exploration.open(radio_node)
	game.exploration.choose(game.exploration.answer_button_index("recon_radio"))
	game.exploration.close()
	verify(game.exploration.radar_scan_active and game.minimap._is_discovered(game.crate_nodes[2]) and game.minimap._is_discovered(game.crate_nodes[1]), "East Recon Radio triggers global minimap radar reveal")
	verify(game.player.grenades == pre_gren + 1 and game.player.reserve_ammo >= 15 + game.rules.magazine(), "Recon Radio grants +1 smoke/EMP and reserve ammo")
	var pre_ammo2 := int(game.player.reserve_ammo)
	var ab_node: Node3D = node_for.call("airdrop_beacon")
	game.exploration.open(ab_node)
	game.exploration.choose(game.exploration.answer_button_index("airdrop_beacon"))
	game.exploration.close()
	verify(game.player.reserve_ammo > pre_ammo2 and game.rules.bag.size() >= pre_bag + 2, "North Airdrop Beacon delivers double mags and Gold/Epic loot")
	for iid in ["intel_cleft", "intel_cave", "intel_roof"]:
		var inod: Node3D = node_for.call(iid)
		game.exploration.open(inod)
		game.exploration.choose(game.exploration.answer_button_index(iid))
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

	var wy_prev: float = game.Layout.stream_water_y(-111.0)
	var downhill_ok := true
	for zi in range(-106, 27, 5):
		var wy_cur: float = game.Layout.stream_water_y(float(zi))
		if wy_cur >= wy_prev:
			downhill_ok = false
		wy_prev = wy_cur
	verify(downhill_ok, "mountain stream elevation flows strictly downhill from North spring to South")

	for bz in game.Layout.STREAM_BRIDGES:
		var bcx: float = game.Layout.stream_center_x(float(bz))
		game.player.clear_movement_input()
		game.player.velocity = Vector3.ZERO
		game.player.position = game.Layout.on_ground(Vector3(bcx - 5.2, 0.0, float(bz))) + Vector3(0, 0.12, 0)
		await frames(6)
		var walked := false
		sim_key.call(KEY_SPACE, false)
		for step in 240:
			var p: Vector3 = game.player.position
			var d := Vector2((bcx + 5.2) - p.x, float(bz) - p.z)
			if d.length() <= 0.65 and game.player.is_on_floor():
				walked = true
				break
			game.player.yaw = atan2(-d.x, -d.y)
			sim_key.call(KEY_W, true)
			await frames(1)
		sim_key.call(KEY_W, false)
		verify(walked and game.player.position.y > game.Layout.stream_water_y(float(bz)) - 0.05, "stream footbridge at z=" + str(bz) + " is smoothly walkable across water")

	verify(is_instance_valid(game.wildlife) and game.wildlife.animals.size() >= 48 and game.wildlife.flora_nodes.size() == 8 and game.wildlife.sky_egrets.size() == 5, "v0.6.1 spawns 52 habitat critters across 8 species + 5 sky egrets + 8 interactive flora nodes")
	var kinds := {}
	var first_by_kind := {}
	for a in game.wildlife.animals:
		kinds[a.kind] = int(kinds.get(a.kind, 0)) + 1
		if not first_by_kind.has(a.kind):
			first_by_kind[a.kind] = a
	verify(
		int(kinds.get("rabbit", 0)) >= 8 and int(kinds.get("squirrel", 0)) >= 7 and int(kinds.get("boar", 0)) >= 5 and int(kinds.get("fox", 0)) >= 5
		and int(kinds.get("bird", 0)) >= 9 and int(kinds.get("fish", 0)) >= 7 and int(kinds.get("crab", 0)) >= 5 and int(kinds.get("shrimp", 0)) >= 6,
		"all 8 Jiangnan wildlife species (rabbit/squirrel/boar/fox/bird/fish/crab/shrimp) meet v0.6.1 target counts"
	)

	game.wildlife.reset()
	var squirrel: Dictionary = first_by_kind["squirrel"]
	game.player.velocity = Vector3.ZERO
	game.player.position = squirrel.pos + Vector3(0.0, 0.0, 2.8)
	game.wildlife.update(0.05)
	verify(squirrel.state == "flee", "approaching squirrel triggers skittish flee state")
	for tick in 20:
		game.wildlife.update(0.1)
	verify(
		squirrel.pos.x >= game.Layout.FENCE_MIN_X and squirrel.pos.x <= game.Layout.FENCE_MAX_X and squirrel.pos.z >= game.Layout.FENCE_MIN_Z and squirrel.pos.z <= game.Layout.FENCE_MAX_Z,
		"fleeing animal stays bounded inside physical timber fence perimeter"
	)

	# Test bush-ambush wild boar charge & perched bird 3D flight
	var boar0: Dictionary = first_by_kind["boar"]
	verify(boar0.state == "ambush", "wild boar starts nestled in hillside bush ambush thicket")
	game.player.position = boar0.pos + Vector3(0.0, 0.0, 4.5)
	game.wildlife.update(0.05)
	verify(boar0.state == "flee" and game.wildlife.discovered_species.has("boar"), "approaching bush thicket startles wild boar into hillside charge")

	var bird0: Dictionary = first_by_kind["bird"]
	var perch_y: float = bird0.pos.y
	game.player.position = Vector3(bird0.pos.x, game.terrain_height(bird0.pos.x, bird0.pos.z), bird0.pos.z + 3.0)
	game.wildlife.update(0.05)
	for tick in 12:
		game.wildlife.update(0.1)
	verify(bird0.state == "fly" and bird0.pos.y > perch_y + 1.2, "startled mountain bird flaps and climbs dynamically into the sky")

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
		env_ok = env_cfg.tonemap_mode == Environment.TONE_MAPPER_FILMIC and env_cfg.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and env_cfg.fog_enabled
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
	verify(flagstones != null and flagstones.multimesh != null and flagstones.multimesh.instance_count >= 25, "v0.6.0 batches historic bluestone flagstones in a single MultiMesh")
	var poem_node = node_for("poem")
	var poem_pav = poem_node.find_child("poem_stele_pavilion", true, false) if poem_node != null else null
	var obelisk = poem_node.find_child("statue_obelisk", true, false) if poem_node != null else null
	verify(poem_pav != null and obelisk == null, "v0.6.0 replaces Western obelisk with Jiangnan poem_stele_pavilion")
	# Walk onto WangdaoPavilion west stairs & inside floor purely with KEY_W (no jumping)
	var pav_at: Vector3 = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION)
	var pav_basis: Basis = (wangdao_pav as Node3D).transform.basis
	var start_xz := pav_at + pav_basis * Vector3(-4.0, 0.05, 0.0)
	var target_xz := pav_at + pav_basis * Vector3(-1.10, 0.28, 0.0)
	var walk_dir := Vector2(target_xz.x - start_xz.x, target_xz.z - start_xz.z)
	game.player.clear_movement_input()
	game.player.position = start_xz
	game.player.velocity = Vector3.ZERO
	game.player.yaw = atan2(-walk_dir.x, -walk_dir.y)
	await frames(8)
	game.player.held_keys[KEY_W] = true
	for _f in 120:
		if Vector2(game.player.position.x - pav_at.x, game.player.position.z - pav_at.z).length() <= 1.25:
			break
		await physics_frame
	game.player.clear_movement_input()
	await frames(6)
	verify(Vector2(game.player.position.x - target_xz.x, game.player.position.z - target_xz.z).length() < 0.75 and game.player.is_on_floor() and game.player.position.y > pav_at.y + 0.14, "player walks cleanly onto WangdaoPavilion terrace without jumping")

	# v0.6.1 Concave Pebble Creek, Watertight Valley Collar, Submerged Pilings, Botanical Flora & HUD non-overlap checks
	var bed_node := game.landscape.get_node_or_null("StreamChannelBed") as MeshInstance3D
	verify(bed_node != null and bed_node.mesh != null and bed_node.mesh.get_surface_count() > 0, "v0.6.1 renders StreamChannelBed wet-pebble recessed channel")
	var concave_ok := true
	for tz in [16.0, -10.0, -60.0]:
		var tcx: float = game.Layout.stream_center_x(tz)
		var twy: float = game.Layout.stream_water_y(tz)
		var tbed: float = game.terrain_height(tcx, tz)
		var tbank_l: float = game.terrain_height(tcx - 2.6, tz)
		var tbank_r: float = game.terrain_height(tcx + 2.6, tz)
		if (twy - tbed) < 0.45 or (tbank_l - twy) < 0.32 or (tbank_r - twy) < 0.32:
			concave_ok = false
	verify(concave_ok, "creek sits in a true concave channel (~0.52m below water, >=0.34m below both bank lips)")
	var stream_aabb: AABB = (stream_node as MeshInstance3D).get_aabb()
	verify(stream_aabb.end.z > 150.0, "MountainStreamWater flows continuously past South fence (z=26) into distant village paddies (z>150)")
	var seam_max_err := 0.0
	for sx_i in range(-60, 61, 4):
		seam_max_err = maxf(seam_max_err, absf(game.landscape._outer_valley_y(float(sx_i), 36.0) - game.landscape._ground_vis_y(float(sx_i), 36.0)))
	verify(seam_max_err < 0.002, "OuterRiceValley South collar matches ContinuousGround z=36 with zero seam gap")
	var piling_prof: Vector2 = game.landscape._fence_post_profile(16.75, 26.0)
	verify(piling_prof.x < game.Layout.stream_water_y(26.0) - 0.85, "South fence creek pilings plunge deep into streambed beneath water")
	for batch_id in ["MountainCamphorTrees", "MountainWillowTrees", "MountainMapleTrees", "MosoBambooCulms", "MosoBambooClumps", "VillageWillows", "VillageCamphors", "HillsideGrassTufts", "HillsideAzaleaBushes"]:
		var bnode := game.landscape.get_node_or_null(batch_id) as MultiMeshInstance3D
		verify(bnode != null and bnode.multimesh != null and bnode.multimesh.instance_count > 0, "v0.6.1 MultiMesh batch active: " + batch_id)
	verify(game.mission_label.position.y + game.mission_label.size.y <= game.guide_label.position.y, "Zone 1 top-left HUD mission_label and guide_label do not overlap")

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SLICE_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
