extends SceneTree
var game
var failures = 0
var checks = 0

func _initialize(): call_deferred("run")
func verify(ok: bool, text: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",text)

func shoot_at(board: Node3D, from: Vector3):
	var camera = Camera3D.new()
	game.add_child(camera)
	camera.global_position = from
	camera.look_at(board.global_position)
	await physics_frame
	game.fire(camera)
	camera.queue_free()

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	await physics_frame
	verify(game.stations.size()==3 and game.active_station==-1,"three challenge points start inactive")
	game.interact()
	verify(game.active_station==0,"nearby E activates camp terminal")
	var original = game.question.id
	var original_choices = game.choices.duplicate(true)
	game._leave_station()
	verify(game.question.id==original and game.rules.question_open,"leaving preserves unanswered question")
	game.player.position = game.stations[1].position+Vector3(0,0.1,1)
	await physics_frame
	game._mesh_box(game,game.stations[1].position+Vector3(1,1.5,1),Vector3(0.3,3,3),Color.GRAY,true)
	var interaction_wall = game.get_child(game.get_child_count()-1)
	await physics_frame
	game.interact()
	verify(game.active_station!=1,"solid cover prevents E interaction through a wall")
	interaction_wall.queue_free()
	await physics_frame
	game.interact()
	verify(game.active_station==1 and game.question.id==original and game.choices==original_choices,"switching terminal preserves question and options")
	verify(game.stations[0].targets[0].text=="前往终端","previous station clears answer boards")
	var index = game.answer_index
	var active_board = game.stations[1].boards[index]
	var from = game.stations[1].position+Vector3(0,1.7,2)
	await shoot_at(game.stations[0].boards[index],Vector3(0,1.7,7))
	verify(game.rules.score==0 and game.rules.question_open,"shooting an inactive station cannot score")
	var midway = (from+active_board.global_position)/2
	game._mesh_box(game,midway,Vector3(2,3,1),Color.GRAY,true)
	var wall = game.get_child(game.get_child_count()-1)
	await physics_frame
	await shoot_at(active_board,from)
	verify(game.rules.score==0 and game.rules.question_open,"solid cover prevents answering through a wall")
	wall.queue_free()
	await physics_frame
	await shoot_at(active_board,from)
	verify(game.rules.score==10,"active unobstructed target scores")
	await shoot_at(active_board,from)
	verify(game.rules.score==10,"repeated hits never duplicate points")
	game.player.position = game.stations[1].position+Vector3(0,0,20)
	await process_frame
	await process_frame
	verify(game.active_station==-1,"walking away deactivates the target set")
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("CHALLENGE_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
