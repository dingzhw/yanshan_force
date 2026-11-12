extends SceneTree

const Rules = preload("res://scripts/rules.gd")
var checks = 0

func verify(condition: bool, text: String):
	assert(condition, text)
	checks += 1
	print("PASS ", text)

func _initialize():
	call_deferred("run")

func run():
	var r = Rules.new()
	r.start_run(false)
	r.open_question()
	verify(r.answer(true, "u1_hello") and r.score == Rules.BASE_ANSWER_SCORE, "correct answer awards base score (15)")
	verify(not r.answer(true, "u1_hello") and r.score == Rules.BASE_ANSWER_SCORE, "one question cannot score twice")
	verify(not r.crate_ready(1), "one perfect answer does not unlock crate")

	# Streak bonus check: 2nd answer +15 (30), 3rd answer +20 (50)
	r.open_question()
	r.answer(true, "u1_hi")
	r.open_question()
	r.answer(true, "u1_good")
	verify(r.streak == 3 and r.score == 50, "3-answer streak awards +5 bonus points")

	# Low accuracy (< 70%) can still reach 260 in practice mode while crates stay locked
	for i in 16:
		r.open_question()
		r.answer(false)
	for i in 12:
		r.open_question()
		r.answer(true)
	verify(r.score >= Rules.EXTRACTION_SCORE and r.accuracy() < 0.70, "low accuracy can accumulate 260 extraction score")
	verify(not r.crate_ready(1), "low accuracy still locks password crate")
	verify(r.add_loot("test", 35, 2), "field loot accessible")
	verify(r.request_extraction(), "practice mode can begin extraction at 260 points")
	verify(r.finish_extraction(), "extraction banks loot")
	verify(not r.finish_extraction() and r.profile.warehouse.size() == 1, "settlement cannot duplicate loot")
	verify(r.sell_all() == 35 and r.profile.coins == 35, "selling transfers exact value")
	verify(not r.purchase("magazine"), "insufficient funds reject upgrade")
	r.profile.coins = 600
	verify(r.purchase("magazine") and r.magazine() == 14, "magazine upgrade affects gameplay")
	verify(not r.purchase("magazine"), "permanent upgrade cannot be purchased twice")
	verify(r.purchase("reward_point") and r.profile.points == 1, "reward points are recorded")

	r.start_run(false)
	for i in 12:
		r.open_question()
		r.answer(true)
	var items = r.open_crate("rare", 2, true)
	verify(items.size() == 3 and r.bag.size() == 3 and r.perfect_ciphers == 1, "perfect spelling unlocks rare crate with 3 items + bonus score")
	verify(r.open_crate("rare", 2, true).is_empty(), "crate cannot be collected twice")
	r.abandon()
	verify(r.bag.is_empty() and r.profile.coins == 110, "failed run clears only carried loot")

	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	verify(game.words.size() == 175, "textbook pack includes all 175 entries")
	game.start_action(false)
	await physics_frame
	game.interact()
	var camera = Camera3D.new()
	game.add_child(camera)
	camera.position = Vector3(0, 1.7, 7)
	camera.look_at(game.targets[game.answer_index].global_position)
	await physics_frame
	game.fire(camera)
	verify(game.rules.score == Rules.BASE_ANSWER_SCORE, "real 3D raycast resolves the matching word target")
	var previous = game.rules.score
	game.fire(camera)
	verify(game.rules.score == previous, "repeated target hit does not duplicate score")

	# Regular supply box requires typing 1 core English word
	var sup0 = game.pickup_nodes[0]
	game.player.position = sup0.position + Vector3(0, 0, -1.2)
	game._update_interaction()
	game.interact()
	verify(game.cipher_terminal.busy and game.cipher_terminal.mode == "supply" and game.cipher_terminal.stage_count() == 1, "E on regular supply box opens 1-word English unlock terminal")
	var pre_sup_score = game.rules.score
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	game.cipher_terminal.close()
	verify(not sup0.visible and game.rules.bag.size() == 1 and game.rules.score == pre_sup_score + Rules.SUPPLY_PERFECT_SCORE, "typing single English word unlocks supply box and awards +10 score")

	while game.rules.score < Rules.EXTRACTION_SCORE or game.rules.answered < 6:
		game._next_question()
		game.resolve_answer(game.answer_index)
	verify(game.rules.score >= Rules.EXTRACTION_SCORE, "question sequence reaches 260 extraction threshold")

	# Tier 1 crate requires 2 consecutive stages: Core Word -> Textbook Phrase
	game.player.position = game.crate_nodes[0].position + Vector3(0, 0, 1.4)
	game._update_interaction()
	game.interact()
	verify(game.cipher_terminal.busy and game.cipher_terminal.stage_count() == 2, "E interaction on Tier-1 crate opens 2-stage word+phrase cipher terminal")
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	verify(not game.cipher_terminal.unlocked and game.cipher_terminal.stage_index == 1, "passing stage 1 advances to textbook phrase stage 2")
	game.cipher_terminal.submit_text(game.cipher_terminal.target_word.english)
	game.cipher_terminal.close()
	verify(game.rules.crates.size() == 1, "completing word+phrase stages unlocks Tier-1 crate")

	game.player.position = game.exit_position
	game.interact()
	verify(game.rules.phase == "extracting", "nearby extraction interaction starts 5s countdown")
	game._end_run(true)
	verify(game.rules.phase == "result" and game.rules.profile.warehouse.size() > 0, "scene settlement banks carried items")
	verify(game.paused and game.menu.visible, "settlement opens warehouse and shop")

	game.profile_path_override = "user://qa-persistence-check.json"
	game.rules.profile.coins = 321
	game._save()
	var restored = load("res://scripts/main.gd").new()
	restored.profile_path_override = game.profile_path_override
	restored._load_profile()
	verify(restored.rules.profile.coins == 321 and restored.rules.profile.warehouse.size() > 0, "currency and warehouse survive save and reload")
	restored.free()

	game.start_action(false)
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	verify(game.paused and game.menu.visible, "Escape keycode pauses and releases game")
	game._input(escape)
	verify(not game.paused and not game.menu.visible, "Escape resumes paused action")
	game.queue_free()
	await process_frame
	print("PLAYTEST_CHECKS_PASSED=", checks)
	quit()
