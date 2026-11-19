extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func verify(ok: bool, text: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", text)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	await physics_frame
	game.interact()
	verify(game.active_station == 0, "learning begins at camp terminal")
	var missed_id = game.question.id
	game.resolve_answer((game.answer_index + 1) % 4)
	verify(game.wrong_words.size() == 1 and game.feedback_label.text.contains(game.question.english), "wrong shot presents the correct English answer")
	verify(game.rules.profile.mastery.has(missed_id) and int(game.rules.profile.mastery[missed_id].wrong) == 1, "mastery profile records wrong attempts per word")
	for i in 5:
		game._next_question()
		game.resolve_answer(game.answer_index)
	game._next_question()
	verify(game.question.id == game.wrong_words[0].id, "missed word revisits after six answered questions")

	# Smart distractor validation: phrases pull phrase distractors rather than obvious single words
	var phrase_entry = null
	for w in game.words:
		if " " in w.english and not w.proper_name:
			phrase_entry = w
			break
	var picked = game._pick_smart_distractors(phrase_entry)
	var phrase_count = 0
	for item in picked:
		if " " in item.english or item.get("kind", "") == "phrase":
			phrase_count += 1
	verify(picked.size() == 4 and phrase_count >= 3, "smart distractors match multi-word phrases with phrase distractors")

	var fit = true
	var whole_words_fit = true
	for word in game.words:
		game.choices = [word, word, word, word]
		game._sync_question()
		var label = game.targets[0]
		if game.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, 355, label.font_size).y > 146:
			fit = false
			print("OVERFLOW ", word.english)
		for part in label.text.split(" "):
			if game.font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x > 300:
				whole_words_fit = false
	verify(fit, "all 175 entries and long phrases fit their word boards")
	verify(whole_words_fit, "all 175 entries keep individual words within a single line")
	game.wrong_words = game.words.duplicate()
	game._end_run(false)
	game._show_review()
	verify(game.review_overlay.visible and game.review_text.text.contains(game.words[0].english) and game.review_text.text.contains(game.words[-1].english), "scrollable review contains every missed entry")
	verify(game.review_button.visible, "result exposes the full review button")
	game.start_action()
	verify(game.wrong_words.is_empty() and not game.review_overlay.visible and not game.review_button.visible, "new run resets only this run's review")

	# Settle a failed action through its normal exit and reload only the data.
	game.profile_path_override = "user://qa-v067-learning.json"
	game.rules.add_loot("unbanked", 10, 1)
	await physics_frame
	game.interact()
	var failed_term: Dictionary = game.question
	game.resolve_answer((game.answer_index + 1) % game.choices.size())
	game._end_run(false, "QA failed action")
	var restored = load("res://scripts/main.gd").new()
	restored.profile_path_override = game.profile_path_override
	restored._load_profile()
	verify(restored.rules.profile.review_due.has(failed_term.id) and restored.rules.profile.mastery.has(failed_term.id), "failed action persists the question and its retest queue across restart")
	verify(game.rules.bag.is_empty() and restored.rules.profile.warehouse.is_empty(), "failed action does not bank loot")
	verify(restored.rules.profile.last_run.has("wall_clock_seconds") and not restored.rules.profile.last_run.extracted, "failed settlement saves real elapsed time")
	restored.free()

	var sentence: Dictionary = game.sentences[0]
	var learning = game.rules.learning
	var word_count: int = learning.mastered_count(game.words)
	learning.record_spelling(sentence.id, "independent")
	learning.record_spelling(sentence.id, "independent")
	verify(game.words.size() == 175 and game.sentences.size() == 16 and learning.mastered_count(game.words) == word_count and learning.mastered_count(game.sentences) == 1, "separate stable IDs keep sentence mastery out of the 175 words")
	verify(game.rules.profile.mastery[sentence.id].seen == 2, "independent spellings advance seen as well as correct")

	var low_signal_term: Dictionary = game.words[-1]
	learning.record_recognition(low_signal_term.id, true, 1, false)
	verify(game.rules.profile.mastery[low_signal_term.id].last_choice_count == 1 and not game.rules.profile.mastery[low_signal_term.id].has("independent_correct"), "single-option hit carries no independent mastery credit")

	var cipher = game.cipher_terminal
	cipher.open_retest([failed_term])
	verify(cipher.busy and not cipher.hint_button.visible and not cipher.speak_button.visible and cipher.mask_label.text.is_empty(), "retest starts without spelling or pronunciation hints")
	cipher.submit_text(str(failed_term.english))
	verify(not game.rules.profile.review_due.has(failed_term.id) and cipher.unlocked, "first correct retest clears that pending item")
	cipher.close()
	var persisted = JSON.parse_string(FileAccess.get_file_as_string(game.profile_path_override))
	verify(not persisted.review_due.has(failed_term.id), "retest outcome survives reloading the file")

	game.start_action(false)
	cipher.open_for_supply(game.pickup_nodes[0])
	var helped_id: String = cipher.target_word.id
	var prior: int = int(game.rules.profile.mastery.get(helped_id, {}).get("independent_correct", 0))
	cipher.hint_button.pressed.emit()
	cipher.submit_text(str(cipher.target_word.english))
	verify(cipher.unlocked and not cipher.perfect_crack and game.rules.profile.mastery[helped_id].last_outcome == "hinted", "a hint still allows looting without independent credit or perfect bonus")
	verify(int(game.rules.profile.mastery[helped_id].get("independent_correct", 0)) == prior and game.rules.profile.review_due.has(helped_id), "hinted spelling remains queued for independent retest")
	cipher.close()
	cipher.open_for_supply(game.pickup_nodes[1])
	var copied_id: String = cipher.target_word.id
	var copied_prior: int = int(game.rules.profile.mastery.get(copied_id, {}).get("independent_correct", 0))
	cipher.submit_text("__wrong__")
	cipher.submit_text("__wrong_again__")
	cipher.submit_text(str(cipher.target_word.english))
	verify(cipher.unlocked and not cipher.perfect_crack and game.rules.profile.mastery[copied_id].last_outcome == "copied_scaffold", "copying the revealed answer can still open the supply box")
	verify(int(game.rules.profile.mastery[copied_id].get("independent_correct", 0)) == copied_prior and game.rules.profile.review_due.has(copied_id), "copying the answer is distinct from spelling mastery")
	cipher.close()
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LEARNING_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
