extends SceneTree

var game
var failures = 0
var checks = 0

func _initialize():
	call_deferred("run")

func key(code: int,pressed: bool,physical = true):
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code if physical else 0
	event.pressed = pressed
	Input.parse_input_event(event)

func verify(condition: bool,message: String):
	checks += 1
	if not condition:
		failures += 1
	print("PASS " if condition else "FAIL ",message)

func travel(code: int,physical = true,sprint = false) -> Vector3:
	game.player.clear_movement_input()
	game.player.position = Vector3(0,0.2,4.5)
	game.player.yaw = 0
	for i in 20:
		await physics_frame
	var start = game.player.position
	if sprint:
		key(KEY_SHIFT,true)
	key(code,true,physical)
	for i in 60:
		await physics_frame
	var moved = game.player.position - start
	key(code,false,physical)
	key(KEY_SHIFT,false)
	print("MOVEMENT ",code," physical=",physical," sprint=",sprint," displacement=",moved," floor=",game.player.is_on_floor()," mouse_mode=",Input.mouse_mode)
	return moved

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	for i in 45:
		await physics_frame
	verify(game.player.is_on_floor(),"spawn lands on terrain")
	var forward = await travel(KEY_W)
	verify(forward.z < -3.0 and absf(forward.x)<0.1,"W advances and does not stick in ground")
	var back = await travel(KEY_S)
	verify(back.z > 3.0 and absf(back.x)<0.1,"S moves backwards")
	var left = await travel(KEY_A)
	verify(left.x < -3.0 and absf(left.z)<0.1,"A strafes left")
	var right = await travel(KEY_D)
	verify(right.x > 3.0 and absf(right.z)<0.1,"D strafes right")
	var logical = await travel(KEY_W,false)
	verify(logical.z < -3.0,"logical-only key events also move")
	var arrow = await travel(KEY_UP)
	verify(arrow.z < -3.0,"arrow keys move as an alternative")
	var sprint = await travel(KEY_W,true,true)
	verify(sprint.length() > forward.length()*1.3,"Shift sprint increases actual displacement")
	game.player.clear_movement_input()
	for i in 12:
		await physics_frame
	var jump_start = game.player.position.y
	key(KEY_SPACE,true)
	for i in 8:
		await physics_frame
	key(KEY_SPACE,false)
	verify(game.player.position.y > jump_start+0.4,"Space jumps above terrain")
	for i in 60:
		await physics_frame
	verify(game.player.is_on_floor(),"jump lands normally")
	key(KEY_W,true)
	await physics_frame
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	var paused_at = game.player.position
	for i in 10:
		await physics_frame
	verify(game.player.position.distance_to(paused_at)<0.01,"pause stops movement")
	key(KEY_W,false)
	game._input(escape)
	verify(game.player.held_keys.is_empty(),"resume clears held input")
	game.player.clear_movement_input()
	game.player.position = Vector3(25,game.terrain_height(25,25)+1,25)
	for i in 60:
		await physics_frame
	verify(game.player.is_on_floor(),"terrain slopes support the player")
	key(KEY_W,true)
	var slope_start = game.player.position
	for i in 60:
		await physics_frame
	key(KEY_W,false)
	verify(game.player.position.distance_to(slope_start)>2.0,"player can walk on a hillside")
	game.player.clear_movement_input()
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("MOVEMENT_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
