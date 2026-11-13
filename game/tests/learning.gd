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
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LEARNING_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
