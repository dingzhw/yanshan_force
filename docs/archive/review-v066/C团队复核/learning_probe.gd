extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var game = load("res://main.tscn").instantiate()
	var path := OS.get_environment("YS_C_TEST_PROFILE")
	if path == "" or FileAccess.file_exists(path):
		quit(2)
		return
	game.profile_path_override = path
	root.add_child(game)
	await process_frame
	game._save()
	game.start_action(false)
	await physics_frame
	game.interact()
	var word_id: String = game.question.id
	game.resolve_answer((game.answer_index + 1) % 4)
	game._end_run(false)
	var disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	print("C_FAILED_RUN ", JSON.stringify({"in_session": game.rules.profile.mastery.has(word_id), "on_disk": disk.mastery.has(word_id), "visible_review": game.review_button.visible}))
	var sentence = game.cipher_terminal.SENTENCE_BANK[0]
	var count_before: int = game.rules.mastered_count()
	for i in 2:
		game.rules.record_word_spelled(sentence.id)
	var matches = game.words.filter(func(e): return e.id == sentence.id)
	print("C_SENTENCE ", JSON.stringify({"id": sentence.id, "in_pack": not matches.is_empty(), "mastery_delta": game.rules.mastered_count()-count_before, "counter": game.rules.profile.mastery[sentence.id], "pack_size": game.words.size()}))
	game.queue_free()
	await process_frame
	quit()
