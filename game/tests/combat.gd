extends SceneTree

const Battle = preload("res://scripts/combat.gd")
const Soldier = preload("res://scripts/word_soldier.gd")
var game
var aim: Camera3D
var checks = 0
var failures = 0

func _initialize():
	call_deferred("run")

func verify(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ",description)

func frames(count: int):
	for i in count:
		await physics_frame
	await process_frame

func shoot(from: Vector3, target: Vector3):
	aim.global_position = from
	aim.look_at(target)
	game.fire(aim)

func key(code: int, pressed: bool):
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func seed_for_roll(low: float, high: float) -> int:
	var probe = RandomNumberGenerator.new()
	for candidate in range(1,1025):
		probe.seed = candidate
		var roll = probe.randf()
		if roll>low and roll<high:
			return candidate
	assert(false,"No deterministic shot roll in the expected interval")
	return 0

func run():
	seed(42030)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	aim = Camera3D.new()
	game.add_child(aim)
	await frames(2)
	game.start_button.pressed.emit()
	verify(game.combat.stage==Battle.Stage.READY,"main menu deploys into timed-range preparation")
	verify(game.combat.health==100 and game.combat.troops.is_empty(),"the range starts with full health and no attackers")
	game.interact()
	verify(game.combat.stage==Battle.Stage.RANGE,"E interaction starts the 35-second range")
	var warmup_before: float = game.combat.range_left
	var esc = InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	game._input(esc)
	await frames(12)
	verify(game.paused and is_equal_approx(game.combat.range_left,warmup_before),"pausing freezes the warmup timer")
	game._input(esc)
	await frames(10)
	verify(game.combat.range_left<warmup_before,"resuming continues the same warmup")
	shoot(game.player.camera.global_position,game.targets[game.answer_index].global_position)
	verify(game.combat.range_hits==1 and game.combat.range_answers==1 and game.rules.score==0,"actual range ray records a hit separately from field score")
	shoot(game.player.camera.global_position,game.targets[game.answer_index].global_position)
	verify(game.combat.range_answers==1,"repeated range hit cannot inflate the grade")
	game._next_question()
	shoot(game.player.camera.global_position,game.targets[(game.answer_index+1)%4].global_position)
	verify(game.combat.range_answers==2 and game.wrong_words.size()==1,"wrong range hit affects grade and enters review")
	verify(Battle.warmup_multiplier(8,8)<Battle.warmup_multiplier(4,4) and Battle.warmup_multiplier(4,4)<Battle.warmup_multiplier(4,8) and Battle.warmup_multiplier(0,8)>1.0,"warmup formula rewards hit count and accuracy")
	game.combat.range_left = 0.04
	await frames(6)
	verify(game.combat.in_field() and game.combat.troops.size()==2,"range countdown deploys forest and rock patrols")
	verify(is_equal_approx(game.combat.range_scale,Battle.warmup_multiplier(1,2)) and not game.stations[1].boards[0].visible,"warmup grade carries into combat and stationary boards clear")
	var patrol = game.combat.troops[1][0]
	var patrol_start: Vector3 = patrol.position
	await frames(70)
	verify(patrol.position.distance_to(patrol_start)>0.65 and patrol.is_on_floor() and patrol.action==Soldier.Action.PATROL,"patrol follows a route on the real terrain")
	var center: Vector3 = game.stations[1].position
	game.combat.shot_rng.seed = seed_for_roll(0.0,0.1)
	game.player.position = center+Vector3(0,0.08,1.5)
	await frames(6)
	verify(game.combat.zone==1 and patrol.word_label.text!="","approaching the forest enables its word-bearing enemies")
	var all_words_fit = true
	for entry in game.words:
		game._fit_word(patrol.word_label,entry.english,118)
		var label = patrol.word_label
		var size = game.font.get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,label.width,label.font_size)
		if size.y>118 or size.x>label.width:
			all_words_fit = false
	verify(all_words_fit,"all 175 textbook entries fit the mobile shield")
	game.combat.show_question()
	var saw_warning = false
	var fired = false
	var initial_health: int = game.combat.health
	var first_attacker
	for i in 300:
		await physics_frame
		for soldier in game.combat.troops[1]:
			if soldier.action==Soldier.Action.AIM:
				saw_warning = true
				first_attacker = soldier
		if game.combat.health<initial_health:
			fired = true
			break
	verify(saw_warning and fired and initial_health-game.combat.health==game.combat.damage_per_shot(),"an advancing soldier warns, fires and applies real damage")
	var sheltered = false
	if is_instance_valid(first_attacker):
		for i in 160:
			await physics_frame
			if first_attacker.action==Soldier.Action.COVER and first_attacker.position.distance_to(first_attacker.cover_goal)<0.65 and not game.combat.clear_shot(first_attacker.position):
				sheltered = true
				break
	verify(sheltered,"the attacker reaches real cover after firing")
	if is_instance_valid(first_attacker):
		var cover_health: int = game.combat.health
		var rng_state: int = game.combat.shot_rng.state
		game.combat.strike(first_attacker)
		verify(game.combat.health==cover_health and game.combat.shot_rng.state==rng_state,"solid cover cancels the shot before rolling accuracy")
	else:
		verify(false,"solid cover blocks enemy damage")
	# Use a clear patch of the live arena to test the shield ray independently
	# of the patrol's current pose. Preserve the real CharacterBody and shield.
	var before_wrong: int = game.combat.damage_per_shot()
	var wrong = game.combat.troops[1][(game.answer_index+1)%4]
	wrong.position = center+Vector3(0,0.08,-3)
	await frames(2)
	var eye: Vector3 = game.player.camera.global_position
	shoot(eye,wrong.shield_area.global_position+wrong.shield_area.global_basis.x*0.68)
	verify(game.combat.field_answers==1 and game.combat.rage_left>6.8 and game.combat.damage_per_shot()>before_wrong,"hitting the shield's edge resolves a wrong word and raises damage")
	var wrong_damage: int = game.combat.damage_per_shot()
	game._next_question()
	var correct = game.combat.troops[1][game.answer_index]
	if correct!=wrong:
		wrong.position = wrong.home
	correct.position = center+Vector3(0,0.08,-3)
	await frames(2)
	shoot(game.player.camera.global_position,correct.shield_area.global_position)
	verify(game.rules.score==10 and correct.defeated and correct.shield_area.collision_layer==0,"correct shot awards points and disables the defeated soldier and shield")
	verify(game.combat.rage_left==0 and game.combat.damage_per_shot()<wrong_damage,"correct answer breaks rage and lowers field damage")
	var score: int = game.rules.score
	shoot(game.player.camera.global_position,correct.shield_area.global_position)
	verify(game.rules.score==score,"shooting a downed soldier cannot score again")
	game._next_question()
	verify(not correct.defeated and correct.word_label.text!="","next question brings in a readable reinforcement")
	game.player.position = game.stations[2].position+Vector3(0,0.08,1.5)
	await frames(5)
	verify(game.combat.zone==2 and game.combat.troops[2][0].word_label.text!="","the second patrol activates in the rock zone")
	# Finish the run on live targets using actual rays. Wait for enemies to
	# advance or peek when the correct word is behind their cover.
	var last_hit = {}
	var last_target
	for i in 2200:
		await physics_frame
		if game.rules.score>=100 or game.rules.phase!="active":
			break
		if not game.rules.question_open:
			continue
		var target = game.combat.troops[2][game.answer_index]
		last_target = target
		var from: Vector3 = game.player.camera.global_position
		var at: Vector3 = target.shield_area.global_position
		var ray = PhysicsRayQueryParameters3D.create(from,at,7,[game.player.get_rid()])
		ray.collide_with_areas = true
		var result = game.get_world_3d().direct_space_state.intersect_ray(ray)
		last_hit = result
		if result and (result.collider==target or result.collider==target.shield_area):
			shoot(from,at)
	print("LIVE_ROUND score=",game.rules.score," health=",game.combat.health," phase=",game.rules.phase," time=",game.time_left)
	if game.rules.score<100 and is_instance_valid(last_target):
		print("LAST_TARGET ",last_target.option," at ",last_target.position," cover ",last_target.cover," action ",last_target.action," blocked ",last_hit.get("position")," collider ",last_hit.get("collider"))
	verify(game.rules.score==100 and game.combat.health>0,"live moving targets can be read, hit and cleared through a full extraction score")
	game.rules.add_loot("词兵测试物资",25)
	game.player.position = game.exit_position
	await frames(2)
	game.interact()
	verify(game.rules.phase=="extracting" and game.rules.score==100,"field score unlocks the normal extraction")
	game.extraction_left = 0.02
	await frames(5)
	verify(game.rules.phase=="result" and game.rules.profile.warehouse.size()>0 and not game.combat.in_field(),"extraction banks loot and removes combat")
	game.start_button.pressed.emit()
	game.interact()
	game.combat.range_left = 0.03
	await frames(5)
	game.player.position = center+Vector3(0,0.08,1.5)
	await frames(5)
	var threat = game.combat.troops[1][0]
	for soldier in game.combat.troops[1]:
		soldier.set_physics_process(false)
	threat.position = center+Vector3(0,0.08,-3)
	await frames(20)
	var stationary: float = game.combat.hit_chance()
	var same_roll := seed_for_roll(0.50,0.70)
	var before: int = game.combat.health
	game.combat.shot_rng.seed = same_roll
	game.combat.strike(threat)
	verify(absf(stationary-0.75)<0.01 and game.combat.health==before-game.combat.damage_per_shot(),"a stationary player can be hit at 75 percent accuracy")
	key(KEY_A,true)
	await frames(28)
	var moving: float = game.combat.hit_chance()
	before = game.combat.health
	game.combat.shot_rng.seed = same_roll
	game.combat.strike(threat)
	verify(absf(moving-0.40)<0.02 and game.combat.health==before and game.combat.miss_left>0,"the same roll misses when the player moves at normal speed")
	key(KEY_SHIFT,true)
	await frames(22)
	var sprinting: float = game.combat.hit_chance()
	var jump_roll := seed_for_roll(0.18,0.22)
	before = game.combat.health
	game.combat.shot_rng.seed = jump_roll
	game.combat.strike(threat)
	verify(absf(sprinting-0.25)<0.02 and game.combat.health==before-game.combat.damage_per_shot(),"sprinting reduces the chance to 25 percent")
	key(KEY_SPACE,true)
	await frames(8)
	var sprint_jump: float = game.combat.hit_chance()
	before = game.combat.health
	game.combat.shot_rng.seed = jump_roll
	game.combat.strike(threat)
	verify(not game.player.is_on_floor() and absf(sprint_jump-0.1375)<0.02 and game.combat.health==before and game.combat.miss_left>0,"the same shot misses during a sprint jump")
	key(KEY_SPACE,false)
	key(KEY_SHIFT,false)
	key(KEY_A,false)
	game.player.clear_movement_input()
	game.player.position = center+Vector3(0,0.08,1.5)
	await frames(20)
	key(KEY_SPACE,true)
	await frames(8)
	var jump: float = game.combat.hit_chance()
	key(KEY_SPACE,false)
	verify(not game.player.is_on_floor() and absf(jump-0.4125)<0.02,"jumping in place also makes enemy fire less accurate")
	print("HIT_CHANCES still=",stationary," move=",moving," sprint=",sprinting," jump=",jump," sprint_jump=",sprint_jump)
	game.player.clear_movement_input()
	game.player.position = center+Vector3(0,0.08,2)
	key(KEY_SHIFT,true)
	key(KEY_D,true)
	await frames(42)
	verify(game.combat.hit_chance()>0.73 and game.player.position.x<center.x+1.4,"a held sprint key against a solid terminal does not grant evasion")
	key(KEY_SHIFT,false)
	key(KEY_D,false)
	game.player.clear_movement_input()
	game.player.position = center+Vector3(0,0.08,1.5)
	await frames(15)
	game.combat.health = 1
	game.rules.add_loot("未撤离",50)
	game.combat.shot_rng.seed = seed_for_roll(0.0,0.1)
	game.combat.strike(threat)
	verify(game.rules.phase=="result" and game.rules.bag.is_empty() and game.menu_title.text.contains("体力耗尽"),"lethal attack ends the run and drops unextracted loot")
	game.practice_button.pressed.emit()
	game.interact()
	verify(game.combat.stage==Battle.Stage.OFF and game.stations[1].boards[0].visible and game.active_station==0,"free practice still starts with working stationary boards")
	game.queue_free()
	await process_frame
	await create_timer(0.4).timeout
	print("COMBAT_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
