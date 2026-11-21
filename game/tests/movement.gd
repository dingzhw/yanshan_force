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
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN) + Vector3(0, 0.2, 0)
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
	game.player.position = Vector3(42, game.terrain_height(42, 22) + 1.0, 22)
	for i in 60:
		await physics_frame
	verify(game.player.is_on_floor(),"terrain slopes support the player")
	key(KEY_W,true)
	var slope_start = game.player.position
	for i in 60:
		await physics_frame
	key(KEY_W,false)
	verify(game.player.position.distance_to(slope_start)>2.0,"player can walk on a hillside")

	# v0.6.1.1 Tactical Stances ([C] Crouch, [Z] Prone, Overhead Roof Clearance) & Hybrid [Q/E] Cover Lean + [F] Interact
	game.player.clear_movement_input()
	game.player.reset_stance()
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN) + Vector3(0, 0.2, 0)
	game.player.yaw = 0.0
	for i in 20:
		await physics_frame

	key(KEY_C, true)
	key(KEY_C, false)
	for i in 25:
		await physics_frame
	verify(game.player.stance == 1 and absf(game.player.camera.position.y - 1.04) < 0.06, "[C] crouch lowers eye height to ~1.04m")
	var crouch_start = game.player.position
	key(KEY_W, true)
	for i in 60:
		await physics_frame
	key(KEY_W, false)
	var crouch_dist = (game.player.position - crouch_start).length()
	verify(crouch_dist > 1.2 and crouch_dist < forward.length() * 0.74, "crouch movement is controlled and slower than standing")

	key(KEY_Z, true)
	key(KEY_Z, false)
	for i in 28:
		await physics_frame
	verify(game.player.stance == 2 and absf(game.player.camera.position.y - 0.46) < 0.06, "[Z] prone lowers eye height to ~0.46m")
	var prone_start = game.player.position
	key(KEY_W, true)
	for i in 60:
		await physics_frame
	key(KEY_W, false)
	var prone_dist = (game.player.position - prone_start).length()
	verify(prone_dist > 0.6 and prone_dist < crouch_dist * 0.68, "prone crawl is slower than crouch walk")

	# Low ceiling overhead check: cannot stand up directly under a 1.32m roof
	var low_roof := StaticBody3D.new()
	low_roof.collision_layer = 1
	var roof_cs := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(2.2, 0.24, 2.2)
	roof_cs.shape = roof_box
	low_roof.add_child(roof_cs)
	low_roof.position = game.player.position + Vector3(0.0, 1.34, 0.0)
	game.add_child(low_roof)
	await physics_frame
	await physics_frame
	key(KEY_Z, true)
	key(KEY_Z, false)
	await physics_frame
	verify(game.player.stance == 1, "standing from prone under 1.34m low roof safely stops at crouch instead of clipping")
	key(KEY_C, true)
	key(KEY_C, false)
	await physics_frame
	verify(game.player.stance == 1, "crouched player cannot stand through low overhead obstacle")
	low_roof.queue_free()
	await physics_frame
	await physics_frame
	key(KEY_C, true)
	key(KEY_C, false)
	for i in 22:
		await physics_frame
	verify(game.player.stance == 0 and absf(game.player.camera.position.y - 1.58) < 0.06, "removing overhead obstacle allows [C] to stand back up")

	# Hybrid [E] tap-to-toggle (< 0.22s) & [Q] hold-to-peek (>= 0.22s) + side wall anti-clip
	key(KEY_E, true)
	for i in 4:
		await physics_frame
	key(KEY_E, false)
	for i in 20:
		await physics_frame
	verify(game.player.lean_dir == 1 and game.player.camera.position.x > 0.28 and game.player.camera.rotation.z < -0.15, "short [E] tap toggles right cover lean ON")
	key(KEY_E, true)
	await physics_frame
	key(KEY_E, false)
	for i in 20:
		await physics_frame
	verify(game.player.lean_dir == 0 and absf(game.player.camera.position.x) < 0.04, "second [E] tap resets cover lean to center")

	key(KEY_Q, true)
	for i in 22:
		await physics_frame
	verify(game.player.lean_dir == -1 and game.player.camera.position.x < -0.28, "holding [Q] >= 0.22s leans camera left")
	key(KEY_Q, false)
	for i in 20:
		await physics_frame
	verify(game.player.lean_dir == 0 and absf(game.player.camera.position.x) < 0.04, "releasing held [Q] automatically returns from peek")

	# Side-wall anti-clip clamp during lean
	var side_wall := StaticBody3D.new()
	side_wall.collision_layer = 1
	var sw_cs := CollisionShape3D.new()
	var sw_box := BoxShape3D.new()
	sw_box.size = Vector3(0.2, 2.2, 2.0)
	sw_cs.shape = sw_box
	side_wall.add_child(sw_cs)
	side_wall.position = game.player.position + Vector3(0.42, 1.1, 0.0)
	game.add_child(side_wall)
	await physics_frame
	await physics_frame
	key(KEY_E, true)
	for i in 18:
		await physics_frame
	verify(game.player.camera.position.x < 0.14, "leaning into nearby right wall clamps camera offset to prevent clipping")
	key(KEY_E, false)
	side_wall.queue_free()
	await physics_frame

	# [F] Interact remap check
	game.player.clear_movement_input()
	game.player.reset_stance()
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN) + Vector3(0, 0.2, 0)
	game.player.yaw = 0.0
	for i in 10:
		await physics_frame
	key(KEY_F, true)
	key(KEY_F, false)
	await physics_frame
	verify(game.active_station == 0, "[F] triggers world interaction cleanly")
	game._leave_station()

	game.player.clear_movement_input()
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("MOVEMENT_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
