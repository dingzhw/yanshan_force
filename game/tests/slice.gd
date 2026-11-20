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
	verify(game.VERSION == "0.7.2" and game.words.size() == 175 and game.crate_nodes.size() == 6, "v0.7.2 slice uses 175-entry word pack and 6 tiered vault crates")
	var tac_counts := {"ammo_crate": 0, "smoke_emp": 0, "energy_drink": 0}
	var supply_count := 0
	for p in game.pickup_nodes:
		var t_id := str(p.get_meta("tactical_item", ""))
		if tac_counts.has(t_id):
			tac_counts[t_id] += 1
		else:
			supply_count += 1
	verify(supply_count == 11 and tac_counts["ammo_crate"] >= 9 and tac_counts["smoke_emp"] >= 4 and tac_counts["energy_drink"] >= 3, "v0.6.2 places 11 supply caches plus parkour tactical ammo/smoke/stims")
	verify(game.exploration.nodes.size() == 13, "v0.6.2 spawns 4 classic exploration + 4 field intel + recon radio + airdrop beacon + 3 Yanxia heritage")
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

	verify(is_instance_valid(game.wildlife) and game.wildlife.animals.size() >= 48 and game.wildlife.flora_nodes.size() == 8 and game.wildlife.sky_egrets.size() >= 6, "v0.6.1.1 spawns 52 habitat critters across 8 species + 6 flapping sky egrets + 8 interactive flora nodes")
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
	verify(rigged_ok and not eg_skels.is_empty() and eg0.anim != null and (eg0.anim as AnimationPlayer).is_playing(), "all 8 wildlife species + sky egrets use real Skeleton3D + AnimationPlayer rigs")
	verify(
		int(kinds.get("rabbit", 0)) >= 8 and int(kinds.get("squirrel", 0)) >= 7 and int(kinds.get("boar", 0)) >= 5 and int(kinds.get("fox", 0)) >= 5
		and int(kinds.get("bird", 0)) >= 9 and int(kinds.get("fish", 0)) >= 7 and int(kinds.get("crab", 0)) >= 5 and int(kinds.get("shrimp", 0)) >= 6,
		"all 8 Jiangnan wildlife species (rabbit/squirrel/boar/fox/bird/fish/crab/shrimp) meet target counts"
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

	# v0.6.2 Lost Bamboo-Stone Labyrinth ("迷踪竹石阵") & Yanxia Ancient Cavern ("烟霞古洞") verification
	var maze_node := game.landscape.get_node_or_null("BambooStoneMaze") as Node3D
	var cave_node := game.landscape.get_node_or_null("YanxiaAncientCave") as Node3D
	verify(maze_node != null and cave_node != null, "v0.6.2 spawns BambooStoneMaze and YanxiaAncientCave")
	verify(maze_node.get_node_or_null("BambooMazeSouthGate") != null and maze_node.get_node_or_null("KarstCrouchArch") != null and maze_node.get_node_or_null("CliffMoyaStele") != null and maze_node.get_node_or_null("StoneSundialPedestal") != null, "v0.6.2 maze includes South Gate, KarstCrouchArch, CliffMoyaStele, and StoneSundialPedestal")
	verify(game.crate_nodes.size() >= 6 and str(game.crate_nodes[5].get_meta("title")) == "烟霞古洞秘藏石匣", "v0.6.2 places Tier-3 Yanxia Cavern vault crate at crate_nodes[5]")

	# 1) KarstCrouchArch (-41.60, y, -45.50): physically blocks standing player, passes [C] crouched player
	game.player.clear_movement_input()
	game.player.reset_stance()
	game.player.position = Vector3(-41.60, float(game.terrain_height(-41.60, -44.15)) + 0.05, -44.15)
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0.0
	await frames(6)
	game.player.held_keys[KEY_W] = true
	for _f in 48:
		await physics_frame
	game.player.clear_movement_input()
	await frames(3)
	var stand_blocked_z: float = game.player.position.z
	verify(stand_blocked_z > -45.25, "KarstCrouchArch 1.25m lintel blocks standing player (z=%.2f)" % stand_blocked_z)

	sim_key.call(KEY_C, true)
	await frames(2)
	sim_key.call(KEY_C, false)
	await frames(4)
	verify(game.player.stance == 1, "pressing [C] switches player to crouched stance in front of karst arch")
	game.player.yaw = 0.0
	game.player.held_keys[KEY_W] = true
	for _f in 75:
		if game.player.position.z < -46.55:
			break
		await physics_frame
	game.player.clear_movement_input()
	await frames(4)
	verify(game.player.position.z < -46.30 and game.player.is_on_floor(), "crouched player crawls cleanly underneath KarstCrouchArch (z=%.2f)" % game.player.position.z)
	sim_key.call(KEY_C, true)
	await frames(2)
	sim_key.call(KEY_C, false)
	await frames(4)

	# 2) Real walk-in traversal from Cavern Forecourt through South Cliff Portal into YanxiaAncientCave
	game.player.clear_movement_input()
	game.player.position = Vector3(-41.60, 6.55, -56.20)
	game.player.velocity = Vector3.ZERO
	game.player.yaw = 0.0
	await frames(6)
	game.player.held_keys[KEY_W] = true
	for _f in 125:
		if game.player.position.z < -63.80:
			break
		await physics_frame
	game.player.clear_movement_input()
	await frames(6)
	verify(game.player.position.z < -62.50 and game.player.is_on_floor() and absf(game.player.position.y - 6.526) < 0.16, "player walks seamlessly through Yanxia Cave portal onto wet limestone floor (pos=%s)" % str(game.player.position))
	game.player.position = Vector3(-40.25, 6.526, -65.25)
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
	game.exploration.choose(game.exploration.answer_button_index("cliff_inscription"))
	game.exploration.close()
	verify(game.exploration.is_secret_revealed("yanxia_cave") and game.minimap._is_discovered(game.crate_nodes[5]), "Moya cliff inscription reveals Yanxia Cavern secret on minimap")

	game.combat.health = 60
	game.combat.shield = 5.0
	game.rules.bag.clear()
	for hid in ["cave_mural", "cave_hearth"]:
		var hev: Node3D = node_for.call(hid)
		game.exploration.open(hev)
		game.exploration.choose(game.exploration.answer_button_index(hid))
		game.exploration.close()
	verify(game.exploration.heritage_completed() == 3, "all 3 v0.6.2 Yanxia heritage discoveries solve and track in heritage_completed() == 3")
	verify(game.combat.health == 80 and game.combat.shield >= 19.5, "cave_hearth spring tea restores +20 HP and +15 Shield")
	var bag_titles: Array[String] = []
	for b_item in game.rules.bag:
		bag_titles.append(str(b_item.get("title", "")))
	verify("烟山先民竹简" in bag_titles and "烟霞岩画残拓" in bag_titles, "Yanxia rock petroglyph & hearth award Epic & Legendary heritage collectibles into raid bag")

	# 4) v0.6.3 World Looting ('露天刷货', '掏鸟窝', '高能异动箱', '词兵掉落包'), [B] Backpack, [I] 3D Turntable & Compendium Checks
	var active_loose := 0
	for lnode in game.world_loot.loose_nodes:
		if lnode.visible and lnode.has_meta("loot_item"):
			active_loose += 1
	var overcharged_cnt := 0
	for pnode in game.pickup_nodes:
		if pnode.has_meta("overcharged"):
			overcharged_cnt += 1
	verify(active_loose == 7 and game.world_loot.nest_nodes.size() == 6 and overcharged_cnt == 2, "Normal/Practice run spawns 7 randomized 3D loose relics, 6 bird nests/crevices, and 2 overcharged supply caches")

	# Pickup open-world 3D loose relic at Camp Tent Table (loose_nodes[0] is guaranteed active!)
	var tent_loose: Node3D = game.world_loot.loose_nodes[0]
	var pre_loose_bag: int = game.rules.bag.size()
	game.player.position = tent_loose.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	verify(game.rules.bag.size() == pre_loose_bag + 1 and not tent_loose.visible and game.loot_ui.toast_panel.visible, "pressing [F] on open-world 3D loose relic collects item immediately and triggers HUD toast")

	# Search a tactile Bird Nest ('掏鸟窝') via quick-search progress bar!
	var nest0: Node3D = game.world_loot.nest_nodes[0]
	var pre_nest_bag: int = game.rules.bag.size()
	game.player.position = nest0.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	verify(game.loot_ui.active_search_node == nest0 and game.loot_ui.search_panel.visible, "interacting with Bird Nest starts tactile magnifying-glass quick-search bar")
	game.loot_ui.complete_active_search_for_qa()
	verify(game.rules.bag.size() == pre_nest_bag + 1 and not nest0.visible, "completing Bird Nest search rolls and awards surprise loot item")

	# Spawn & inspect an Enemy Squad Wave Drop Pouch via Magnifying-Glass Terminal!
	var pouch_pos: Vector3 = game.Layout.on_ground(Vector3(-6.0, 0.0, -12.0))
	var pouch: Node3D = game.world_loot.spawn_squad_drop(pouch_pos, "林间古道营地", true, false)
	var pre_pouch_bag: int = game.rules.bag.size()
	game.player.position = pouch.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	verify(game.cipher_terminal.busy and game.cipher_terminal.mode == "drop_pouch" and game.cipher_terminal.unlocked, "interacting with enemy wave drop pouch opens zero-typing magnifying-glass loot terminal")
	verify(game.rules.bag.size() > pre_pouch_bag and not pouch.visible, "claiming flawless enemy wave drop pouch transfers multi-slot battle loot into bag")
	game.cipher_terminal.close()

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
	game._end_run(false)

	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SLICE_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
