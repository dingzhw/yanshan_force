extends Node3D
## Multi-archetype tactical outpost combat manager with rechargeable shield, 3 zones, and outpost capture waves.

const Soldier = preload("res://scripts/word_soldier.gd")
enum Stage { OFF, FIELD }

const MAX_HEALTH = 100
const RAGE_SECONDS = 7.0
const SHIELD_REGEN_DELAY = 4.5
const SHIELD_REGEN_RATE = 11.0
const STILL_HIT_CHANCE = 0.78
const FAST_HIT_CHANCE = 0.26
const MAX_EVASION_SPEED = 6.1
const AIRBORNE_HIT_SCALE = 0.55

var game
var stage = Stage.OFF
var field_hits = 0
var field_answers = 0
var rage_left = 0.0
var health = MAX_HEALTH
var shield = 30
var shield_delay = 0.0
var zone = -1
var attack_lock = 0.0
var miss_left = 0.0
var shot_rng := RandomNumberGenerator.new()
var arena: Node3D
var troops = {}
var waves_done = {}
var waves_target = {}
var zone_cleared = {}

func begin():
	stop()
	stage = Stage.FIELD
	field_hits = 0
	field_answers = 0
	rage_left = 0.0
	health = MAX_HEALTH
	shield = game.rules.max_shield()
	shield_delay = 0.0
	attack_lock = 0.0
	miss_left = 0.0
	shot_rng.randomize()
	_deploy()

func stop():
	stage = Stage.OFF
	zone = -1
	troops.clear()
	waves_done.clear()
	waves_target.clear()
	zone_cleared.clear()
	if is_instance_valid(arena):
		arena.hide()
		for body in arena.find_children("*", "CollisionObject3D", true, false):
			body.collision_layer = 0
		arena.queue_free()
		arena = null
	for station in game.stations:
		station.enable_boards(true)

func in_warmup() -> bool:
	return false

func in_field() -> bool:
	return stage == Stage.FIELD

func heal(hp_gain: int, shield_gain: int):
	health = mini(MAX_HEALTH, health + hp_gain)
	shield = mini(game.rules.max_shield(), shield + shield_gain)

func zone_info(z_idx: int) -> Dictionary:
	return game.Layout.COMBAT_ZONES[z_idx]

func zone_center(z_idx: int) -> Vector3:
	return game.Layout.on_ground(zone_info(z_idx).at)

func zone_aggro(z_idx: int) -> float:
	return float(zone_info(z_idx).aggro)

func zone_pursuit(z_idx: int) -> float:
	return float(zone_info(z_idx).pursuit)

func record_field(correct: bool):
	field_answers += 1
	if correct:
		field_hits += 1
		rage_left = 0.0
		if zone >= 0 and not zone_cleared.get(zone, false):
			waves_done[zone] = int(waves_done.get(zone, 0)) + 1
			if waves_done[zone] >= waves_target[zone]:
				zone_cleared[zone] = true
				game.rules.outposts_cleared += 1
				game.rules.score += game.Rules.OUTPOST_CLEAR_SCORE
				game.player.medkits += 1
				game.play_sfx("loot_epic", -11)
				game._notice("★ 已攻克【%s】！ +%d 积分 · 奖励应急医疗包+1（已清剿 %d 处前哨）" % [zone_info(zone).title, game.Rules.OUTPOST_CLEAR_SCORE, game.rules.outposts_cleared], game.MINT)
	else:
		rage_left = RAGE_SECONDS

func damage_multiplier() -> float:
	var field_scale := 1.0
	if field_answers > 0:
		field_scale = lerpf(1.22, 0.78, float(field_hits) / field_answers)
	var rage := 1.75 if rage_left > 0 else 1.0
	var cleared_relief := 0.72 if (zone >= 0 and zone_cleared.get(zone, false)) else 1.0
	return clampf(field_scale * rage * cleared_relief, 0.45, 2.4)

func damage_per_shot(soldier = null) -> int:
	var base := 11
	if is_instance_valid(soldier) and soldier.has_method("base_shot_damage"):
		base = soldier.base_shot_damage()
	return maxi(2, roundi(float(base) * damage_multiplier()))

func hit_chance() -> float:
	var motion: Vector3 = game.player.get_real_velocity()
	var speed := Vector2(motion.x, motion.z).length()
	var chance := lerpf(STILL_HIT_CHANCE, FAST_HIT_CHANCE, clampf(speed / MAX_EVASION_SPEED, 0.0, 1.0))
	if not game.player.is_on_floor():
		chance *= AIRBORNE_HIT_SCALE
	return chance

func update(delta: float):
	if not in_field():
		return
	rage_left = maxf(0, rage_left - delta)
	attack_lock = maxf(0, attack_lock - delta)
	miss_left = maxf(0, miss_left - delta)
	if shield_delay > 0:
		shield_delay = maxf(0, shield_delay - delta)
	elif shield < game.rules.max_shield():
		shield = minf(float(game.rules.max_shield()), float(shield) + SHIELD_REGEN_RATE * delta)

	var next_zone := -1
	var nearest := INF
	for index in game.Layout.COMBAT_ZONES.size():
		var center := zone_center(index)
		var distance: float = game.player.position.distance_to(center)
		var radius := zone_pursuit(index) if index == zone else zone_aggro(index)
		if distance < radius and distance < nearest:
			next_zone = index
			nearest = distance
	if next_zone != zone:
		if zone >= 0 and troops.has(zone):
			for soldier in troops[zone]:
				soldier.show_word("", false)
		zone = next_zone
		if zone >= 0:
			game._leave_station()
			game._sync_question()
			var z_title = zone_info(zone).title
			var prog = "已占领（余波巡逻）" if zone_cleared.get(zone, false) else ("压制进度 %d/%d" % [waves_done.get(zone, 0), waves_target.get(zone, 4)])
			game._notice("进入交战区：%s（%s）· 注意无人机包抄与狙击红线！" % [z_title, prog], game.GOLD)
		else:
			game._sync_question()

func _squad_archetypes(z_idx: int) -> Array:
	if z_idx == 0:
		return [Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE]
	if z_idx == 1:
		return [Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT]
	return [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SNIPER_GUARD]

func _build_tactical_cover(at: Vector3, index: int):
	# Solid textured cover barricade (blocks bullets & capsules on layer 1)
	var base_y = game.Layout.min_ground_height(at.x, at.z, 0.9) - 0.08
	var root = Node3D.new()
	root.position = Vector3(at.x, base_y, at.z)
	arena.add_child(root)
	var crate_mat = StandardMaterial3D.new()
	crate_mat.albedo_color = Color("4c5646") if index % 2 == 0 else Color("594e3f")
	crate_mat.albedo_texture = load("res://assets/slice/tree_bark.jpg")
	crate_mat.roughness = 0.88
	var main_block = game._mesh_box(root, Vector3(0, 0.98, 0), Vector3(1.52, 2.02, 0.90), Color.WHITE, true)
	main_block.material_override = crate_mat
	var cap_mat = StandardMaterial3D.new()
	cap_mat.albedo_color = Color("2d3638")
	cap_mat.metallic = 0.45
	cap_mat.roughness = 0.50
	var top_trim = game._mesh_box(root, Vector3(0, 2.01, 0), Vector3(1.58, 0.12, 0.96), Color.WHITE)
	top_trim.material_override = cap_mat
	var stripe = game._mesh_box(root, Vector3(0, 1.48, 0), Vector3(1.55, 0.10, 0.92), Color("c49a45"))
	stripe.material_override.roughness = 0.7

func _deploy():
	game._leave_station()
	game.next_question_left = 0
	arena = Node3D.new()
	add_child(arena)
	# Keep Camp Station 0 open for optional warm-up, disable field static boards 1 & 2
	for s_idx in game.stations.size():
		game.stations[s_idx].enable_boards(s_idx == 0)

	for z_idx in game.Layout.COMBAT_ZONES.size():
		var info = zone_info(z_idx)
		var center := zone_center(z_idx)
		waves_done[z_idx] = 0
		waves_target[z_idx] = int(info.waves)
		zone_cleared[z_idx] = false
		var archetypes = _squad_archetypes(z_idx)
		var soldiers = []
		for i in 4:
			var side := -1.0 if i % 2 == 0 else 1.0
			var barrier: Vector3 = game.Layout.on_ground(center + Vector3(-5.7 + i * 3.8 - side * 1.1, 0, -7.8 - (i % 2) * 1.3))
			_build_tactical_cover(barrier, i)
			var soldier = Soldier.new()
			arena.add_child(soldier)
			soldier.setup(self, z_idx, i, barrier, archetypes[i])
			soldiers.append(soldier)
		troops[z_idx] = soldiers
	game.player.ammo = game.rules.magazine()
	game.player.reload_left = 0.0
	game._next_question()

func show_question():
	if zone < 0:
		if game.active_station == 0:
			return
		game.question_label.text = "沿山路推进 · 攻克前哨并搜刮密码箱"
		game.unit_label.text = "撤离条件：累计 %d 积分 且 至少攻克 1 处词兵前哨（当前 %d/1）" % [game.Rules.EXTRACTION_SCORE, game.rules.outposts_cleared]
		return
	for soldier in troops[zone]:
		soldier.show_word(game.choices[soldier.option].english, game.rules.question_open)
	if game.listening_mode and game.rules.question_open:
		game.question_label.text = "🔊 电台截获英文语音 · 按 [Q] 重播读音"
	else:
		game.question_label.text = game.question.chinese
	var z_title = zone_info(zone).title
	var wave_str = "已占领" if zone_cleared.get(zone, false) else ("波次 %d/%d" % [waves_done.get(zone, 0), waves_target.get(zone, 4)])
	game.unit_label.text = "%s（%s）· 射击正确英文护盾  |  [Q] 听读音" % [z_title, wave_str]
	if not game.rules.question_open:
		game.unit_label.text = "目标护盾已击破 · 下一波次准备中…"

func hit(collider) -> bool:
	var soldier = collider.get_parent() if collider is Area3D else collider
	if not (soldier is Soldier) or soldier.zone != zone or soldier.defeated or not game.rules.question_open:
		return false
	game.resolve_answer(soldier.option, true)
	return true

func hit_feedback(index: int, correct: bool):
	var soldier = troops[zone][index]
	if correct:
		soldier.neutralize()
	else:
		soldier.shield_material.albedo_color = Color("a63e36")
		soldier.take_cover()

func blocked(from: Vector3, to: Vector3) -> bool:
	var ray = PhysicsRayQueryParameters3D.create(from, to, 1)
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func clear_shot(at: Vector3) -> bool:
	return not blocked(at + Vector3.UP * 1.52, game.player.position + Vector3.UP * 1.26)

func reserve_attack() -> bool:
	if attack_lock > 0:
		return false
	attack_lock = 1.42 if rage_left <= 0 else 0.98
	return true

func active_threat_count() -> int:
	if zone < 0 or not troops.has(zone):
		return 0
	var c = 0
	for s in troops[zone]:
		if not s.defeated and s.action == Soldier.Action.AIM:
			c += 1
	return c

func strike(soldier):
	if not in_field() or game.paused or soldier.defeated or soldier.zone != zone:
		return
	if is_instance_valid(game.exploration) and game.exploration.safe():
		return
	if soldier.position.distance_to(game.player.position) > soldier.attack_range() or not clear_shot(soldier.position):
		return
	var from: Vector3 = soldier.position + Vector3.UP * 1.54
	var to: Vector3 = game.player.position + Vector3.UP * 1.26
	var chance := hit_chance()
	if soldier.archetype == Soldier.Archetype.SNIPER_GUARD:
		chance = clampf(chance + 0.10, 0.20, 0.90)
	var hits_player := shot_rng.randf() < chance
	if not hits_player:
		var sideways := (to - from).cross(Vector3.UP).normalized()
		if sideways.is_zero_approx():
			sideways = Vector3.RIGHT
		var side := -1.0 if shot_rng.randf() < 0.5 else 1.0
		to += sideways * side * shot_rng.randf_range(0.7, 1.4)
		var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
		var impact := get_world_3d().direct_space_state.intersect_ray(ray)
		if not impact.is_empty():
			to = impact.position
	var beam_col = Color("ff5d6c") if soldier.archetype == Soldier.Archetype.SNIPER_GUARD else Color("ffc483")
	var trace = game._mesh_box(arena, (from + to) / 2, Vector3(0.028, 0.028, from.distance_to(to)), beam_col)
	trace.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trace_up := Vector3.RIGHT if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	trace.look_at(to, trace_up)
	trace.create_tween().tween_callback(trace.queue_free).set_delay(0.13)
	game.play_sound("enemy_attack", -19)
	if not hits_player:
		miss_left = 1.2
		return
	miss_left = 0.0
	shield_delay = SHIELD_REGEN_DELAY
	var damage := damage_per_shot(soldier)
	var absorbed := mini(int(shield), damage)
	shield = maxf(0.0, float(shield) - float(absorbed))
	var hp_loss := damage - absorbed
	if hp_loss > 0:
		health = maxi(0, health - hp_loss)
		game.screen_flash.color = Color(0.92, 0.14, 0.09, 0.22)
	else:
		game.screen_flash.color = Color(0.25, 0.78, 1.0, 0.15)
	if health == 0:
		game._end_run(false, "行动失败 · 装甲与生命耗尽")
