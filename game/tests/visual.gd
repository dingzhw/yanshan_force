extends SceneTree
var game

func _initialize():
	call_deferred("run")

func capture(filename: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	game._capture(filename)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await capture("01-营地与升级.png")
	game.start_action()
	await physics_frame
	game.interact()
	game.player.active = false
	game.player.yaw = 0
	game.player.pitch = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame
	await capture("02-烟山射击区.png")
	var previous_choices = game.choices.duplicate()
	for i in 4:
		var names = ["sometimes","Chinese New Year’s Day","Christmas Eve","I don’t think so."]
		for word in game.words:
			if word.english==names[i]: game.choices[i] = word
	game._sync_question()
	game.question_label.text = "单词与长词组排版检查"
	await capture("06-长单词与词组.png")
	game.choices = previous_choices
	game._sync_question()
	for index in [1,2]:
		game.player.position = game.stations[index].position+Vector3(0,0.1,1)
		await physics_frame
		game.interact()
		await capture("区域-%d.png" % index)
	game.player.position = Vector3(0,0.1,4.5)
	await physics_frame
	game.interact()
	for i in 10:
		game._next_question()
		game.resolve_answer(game.answer_index)
	game.rules.open_crate("林间补给箱",1)
	game.player.position = game.exit_position
	game.interact()
	game._end_run(true)
	await capture("03-成功撤离与物资.png")
	game._sell()
	game._buy("magazine")
	await capture("04-出售与升级.png")
	game.wrong_words = game.words.duplicate()
	game._show_review()
	await capture("05-全部错词.png")
	print("VISUAL_SEQUENCE_COMPLETE")
	game.queue_free()
	await process_frame
	await create_timer(0.4).timeout
	quit()
