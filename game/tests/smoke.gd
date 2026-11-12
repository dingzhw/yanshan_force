extends SceneTree

const Rules = preload("res://scripts/rules.gd")
var checks = 0

func verify(condition: bool, text: String):
	assert(condition,text)
	checks += 1
	print("PASS ",text)

func _initialize():
	call_deferred("run")

func run():
	var r = Rules.new()
	r.start_run()
	r.open_question()
	verify(r.answer(true) and r.score==10,"correct answer awards ten")
	verify(not r.answer(true) and r.score==10,"one question cannot score twice")
	verify(not r.crate_ready(1),"one perfect answer does not unlock crate")
	for i in 9:
		r.open_question()
		r.answer(false)
	for i in 9:
		r.open_question()
		r.answer(true)
	verify(r.score==100 and r.accuracy()<0.70,"low accuracy can accumulate extraction score")
	verify(not r.crate_ready(1),"low accuracy still locks supply crate")
	verify(r.add_loot("test",35),"ordinary loot accessible")
	verify(r.request_extraction(),"low accuracy can begin extraction")
	verify(r.finish_extraction(),"extraction banks loot")
	verify(not r.finish_extraction() and r.profile.warehouse.size()==1,"settlement cannot duplicate loot")
	verify(r.sell_all()==35 and r.profile.coins==35,"selling transfers exact value")
	verify(not r.purchase("magazine"),"insufficient funds reject upgrade")
	r.profile.coins=500
	verify(r.purchase("magazine") and r.magazine()==14,"magazine upgrade affects gameplay")
	verify(not r.purchase("magazine"),"permanent upgrade cannot be purchased twice")
	verify(r.purchase("reward_point") and r.profile.points==1,"reward points are recorded")
	r.start_run()
	for i in 10:
		r.open_question()
		r.answer(true)
	verify(r.open_crate("rare",2) and r.bag.size()==3,"high accuracy opens rare crate")
	verify(not r.open_crate("rare",2),"crate cannot be collected twice")
	r.abandon()
	verify(r.bag.is_empty() and r.profile.coins==80,"failed run clears only carried loot")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	verify(game.words.size()==175,"textbook pack includes all 175 entries")
	game.start_action()
	await physics_frame
	game.interact()
	var camera = Camera3D.new()
	game.add_child(camera)
	camera.position = Vector3(0,1.7,7)
	camera.look_at(game.targets[game.answer_index].global_position)
	await physics_frame
	game.fire(camera)
	verify(game.rules.score==10,"real 3D raycast resolves the matching word target")
	var previous = game.rules.score
	game.fire(camera)
	verify(game.rules.score==previous,"repeated target hit does not duplicate score")
	for i in 9:
		game._next_question()
		game.resolve_answer(game.answer_index)
	verify(game.rules.score==100,"question sequence reaches extraction threshold")
	game.player.position = game.crate_nodes[0].position+Vector3(0,0,1)
	game._update_interaction()
	game.interact()
	verify(game.rules.crates.size()==1,"nearby E interaction opens eligible crate")
	game.player.position = game.exit_position
	game.interact()
	verify(game.rules.phase=="extracting","nearby extraction interaction starts countdown")
	game._end_run(true)
	verify(game.rules.phase=="result" and game.rules.profile.warehouse.size()>0,"scene settlement banks carried items")
	verify(game.paused and game.menu.visible,"settlement opens warehouse and shop")
	game.profile_path_override = "user://qa-persistence-check.json"
	game.rules.profile.coins = 321
	game._save()
	var restored = load("res://scripts/main.gd").new()
	restored.profile_path_override = game.profile_path_override
	restored._load_profile()
	verify(restored.rules.profile.coins==321 and restored.rules.profile.warehouse.size()>0,"currency and warehouse survive save and reload")
	restored.free()
	game.start_action()
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	verify(game.paused and game.menu.visible,"Escape keycode pauses and releases game")
	game._input(escape)
	verify(not game.paused and not game.menu.visible,"Escape resumes paused action")
	game.queue_free()
	await process_frame
	print("PLAYTEST_CHECKS_PASSED=",checks)
	quit()
