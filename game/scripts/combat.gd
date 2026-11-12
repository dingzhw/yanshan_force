extends Node3D

const Soldier = preload("res://scripts/word_soldier.gd")
enum Stage { OFF, READY, RANGE, FIELD }
const RANGE_SECONDS = 35.0
const BASE_DAMAGE = 6
const MAX_HEALTH = 100
const RAGE_SECONDS = 7.0
const STILL_HIT_CHANCE = 0.75
const FAST_HIT_CHANCE = 0.25
const MAX_EVASION_SPEED = 6.0
const AIRBORNE_HIT_SCALE = 0.55

var game
var stage = Stage.OFF
var range_left = 0.0
var range_hits = 0
var range_answers = 0
var field_hits = 0
var field_answers = 0
var range_scale = 1.0
var rage_left = 0.0
var health = MAX_HEALTH
var zone = -1
var attack_lock = 0.0
var miss_left = 0.0
var shot_rng := RandomNumberGenerator.new()
var arena: Node3D
var troops = {}

func begin():
	stop()
	stage = Stage.READY
	range_left = RANGE_SECONDS
	range_hits = 0
	range_answers = 0
	field_hits = 0
	field_answers = 0
	range_scale = 1.0
	rage_left = 0.0
	health = MAX_HEALTH
	attack_lock = 0.0
	miss_left = 0.0
	shot_rng.randomize()

func stop():
	stage = Stage.OFF
	zone = -1
	troops.clear()
	if is_instance_valid(arena):
		arena.hide()
		for body in arena.find_children("*","CollisionObject3D",true,false):
			body.collision_layer = 0
		arena.queue_free()
		arena = null
	for station in game.stations:
		station.enable_boards(true)

func in_warmup() -> bool:
	return stage==Stage.READY or stage==Stage.RANGE

func in_field() -> bool:
	return stage==Stage.FIELD

func start_range():
	if stage==Stage.READY:
		stage = Stage.RANGE

func record_range(correct: bool):
	range_answers += 1
	if correct: range_hits += 1

func record_field(correct: bool):
	field_answers += 1
	if correct:
		field_hits += 1
		rage_left = 0.0
	else:
		rage_left = RAGE_SECONDS

static func warmup_multiplier(hits: int, attempts: int) -> float:
	if attempts==0: return 1.0
	return clampf(1.0+0.6*(1.0-float(hits)/attempts)-mini(hits,10)*0.065,0.45,1.60)

func damage_multiplier() -> float:
	var field_scale := 1.0
	if field_answers>0:
		field_scale = lerpf(1.2,0.72,float(field_hits)/field_answers)
	var rage := 2.0 if rage_left>0 else 1.0
	return clampf(range_scale*field_scale*rage,0.35,2.5)

func damage_per_shot() -> int:
	return maxi(1,roundi(BASE_DAMAGE*damage_multiplier()))

func hit_chance() -> float:
	# Real motion accounts for the capsule stopping against solid objects.
	var motion: Vector3 = game.player.get_real_velocity()
	var speed := Vector2(motion.x,motion.z).length()
	var chance := lerpf(STILL_HIT_CHANCE,FAST_HIT_CHANCE,clampf(speed/MAX_EVASION_SPEED,0.0,1.0))
	if not game.player.is_on_floor():
		chance *= AIRBORNE_HIT_SCALE
	return chance

func update(delta: float):
	if stage==Stage.RANGE:
		range_left = maxf(0,range_left-delta)
		if range_left==0:
			_deploy()
	if not in_field():
		return
	rage_left = maxf(0,rage_left-delta)
	attack_lock = maxf(0,attack_lock-delta)
	miss_left = maxf(0,miss_left-delta)
	var next_zone := -1
	var nearest := 14.0
	for index in range(1,game.stations.size()):
		var distance: float = game.player.position.distance_to(game.stations[index].position)
		var radius := 19.0 if index==zone else 14.0
		if distance<radius and (next_zone<0 or distance<nearest):
			next_zone = index
			nearest = distance
	if next_zone!=zone:
		if zone>=0:
			for soldier in troops[zone]:
				soldier.show_word("",false)
		zone = next_zone
		game._sync_question()
		if zone>=0:
			game._notice(game.stations[zone].title+" · 看清胸牌，用掩体挡住火力",game.MINT)

func _deploy():
	range_scale = warmup_multiplier(range_hits,range_answers)
	game._leave_station()
	game.next_question_left = 0
	stage = Stage.FIELD
	arena = Node3D.new()
	add_child(arena)
	for station in game.stations:
		station.enable_boards(false)
	for index in range(1,game.stations.size()):
		var center: Vector3 = game.stations[index].position
		var soldiers = []
		for i in 4:
			var side := -1.0 if i%2==0 else 1.0
			var barrier: Vector3 = game.Layout.on_ground(center+Vector3(-5.55+i*3.7-side*1.15,0,-8.1-(i%2)*1.1))
			game._mesh_box(arena,barrier+Vector3(0,0.94,0),Vector3(1.44,2.05,0.86),Color("5a5542"),true)
			game._mesh_box(arena,barrier+Vector3(0,1.56,0),Vector3(1.50,0.16,0.91),Color("938056"))
			var soldier = Soldier.new()
			arena.add_child(soldier)
			soldier.setup(self,index,i,barrier)
			soldiers.append(soldier)
		troops[index] = soldiers
	game.player.ammo = game.rules.magazine()
	game.player.reload_left = 0.0
	game._next_question()
	var accuracy := roundi(100.0*range_hits/maxi(range_answers,1))
	game._notice("热身结束 · %d/%d 正确 (%d%%) · 敌方基础伤害 ×%.2f" % [range_hits,range_answers,accuracy,range_scale],game.MINT)

func show_question():
	if zone<0:
		game.question_label.text = "沿山路前往林间前哨与B竹林补给点"
		game.unit_label.text = "热身 %d/%d · 敌方基础伤害 ×%.2f" % [range_hits,range_answers,range_scale]
		return
	for soldier in troops[zone]:
		soldier.show_word(game.choices[soldier.option].english,game.rules.question_open)
	game.question_label.text = game.question.chinese
	game.unit_label.text = "%s · 射击对应英文的词兵" % game.stations[zone].title
	if not game.rules.question_open:
		game.unit_label.text = "本题已结算 · 准备下一题"

func hit(collider) -> bool:
	var soldier = collider.get_parent() if collider is Area3D else collider
	if not soldier is Soldier or soldier.zone!=zone or soldier.defeated or not game.rules.question_open:
		return false
	game.resolve_answer(soldier.option,true)
	return true

func hit_feedback(index: int, correct: bool):
	var soldier = troops[zone][index]
	if correct:
		soldier.neutralize()
	else:
		soldier.shield_material.albedo_color = Color("8a4a39")
		soldier.take_cover()

func blocked(from: Vector3, to: Vector3) -> bool:
	var ray = PhysicsRayQueryParameters3D.create(from,to,1)
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func clear_shot(at: Vector3) -> bool:
	return not blocked(at+Vector3.UP*1.48,game.player.position+Vector3.UP*1.26)

func reserve_attack() -> bool:
	if attack_lock>0: return false
	attack_lock = 2.4
	return true

func strike(soldier):
	if not in_field() or game.paused or soldier.defeated or soldier.zone!=zone:
		return
	if is_instance_valid(game.exploration) and game.exploration.safe():return
	if soldier.position.distance_to(game.player.position)>Soldier.ATTACK_RANGE or not clear_shot(soldier.position):
		return
	var from: Vector3 = soldier.position+Vector3.UP*1.48
	var to: Vector3 = game.player.position+Vector3.UP*1.26
	var hits_player := shot_rng.randf()<hit_chance()
	if not hits_player:
		var sideways := (to-from).cross(Vector3.UP).normalized()
		if sideways.is_zero_approx():
			sideways = Vector3.RIGHT
		var side := -1.0 if shot_rng.randf()<0.5 else 1.0
		to += sideways*side*shot_rng.randf_range(0.7,1.4)
		var ray := PhysicsRayQueryParameters3D.create(from,to,1)
		var impact := get_world_3d().direct_space_state.intersect_ray(ray)
		if not impact.is_empty():
			to = impact.position
	var trace = game._mesh_box(arena,(from+to)/2,Vector3(0.022,0.022,from.distance_to(to)),Color("ffc483"))
	trace.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trace_up := Vector3.RIGHT if absf((to-from).normalized().y)>0.99 else Vector3.UP
	trace.look_at(to,trace_up)
	trace.create_tween().tween_callback(trace.queue_free).set_delay(0.11)
	game.play_sound("blaster",-23)
	if not hits_player:
		miss_left = 1.2
		return
	miss_left = 0.0
	var damage := damage_per_shot()
	health = maxi(0,health-damage)
	game.screen_flash.color = Color(0.9,0.13,0.08,0.19)
	if health==0:
		game._end_run(false,"行动失败 · 体力耗尽")
