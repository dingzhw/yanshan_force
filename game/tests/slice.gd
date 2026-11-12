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
	verify(game.VERSION == "0.5.1" and game.words.size() == 175 and game.crate_nodes.size() == 3, "v0.5.1 slice uses 175-entry word pack and 3 tiered vault crates")
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
	verify(is_equal_approx(game.crate_nodes[2].get_meta("lid_node").rotation.x, 0.0), "new deployment resets vault crate lids back to closed position")
	game.player.ammo = 1
	game.player.reload()
	await frames(40)
	verify(game.player.weapon_view.magazine.position.y < -0.06 and game.player.weapon_view.left_hand_pivot.position.y < 0.08, "reload physically withdraws magazine with left support hand following")
	game._end_run(false)
	game.rules.profile.owned.append("magazine")
	game.start_action(false)
	verify(game.player.ammo == 14 and game.player.weapon_view.magazine.scale.y > 1.2, "magazine upgrade changes both capacity and visible magazine size")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SLICE_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
