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
	print("PASS " if ok else "FAIL ", description)

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
	for candidate in range(1, 1025):
		probe.seed = candidate
		var roll = probe.randf()
		if roll > low and roll < high:
			return candidate
	assert(false, "No deterministic shot roll in the expected interval")
	return 0

func run():
	seed(42030)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	aim = Camera3D.new()
	game.add_child(aim)
	await frames(2)

	# Immediate field deployment into 3 outposts with 3 distinct enemy archetypes
	game.start_button.pressed.emit()
	verify(game.combat.in_field() and game.combat.troops.size() == 3, "combat mode immediately deploys 3 tactical outposts without forced 35s wait")
	verify(game.combat.health == 100 and game.combat.shield == 30 and not game.stations[1].boards[0].visible, "player starts with 100 HP + 30 Shield and field static boards disabled")

	var seen_archetypes = {}
	for z_idx in game.combat.troops:
		for s in game.combat.troops[z_idx]:
			seen_archetypes[s.archetype] = true
	verify(seen_archetypes.size() == 4 and is_instance_valid(game.combat.boss_unit), "all 4 enemy archetypes (Assault Bot, Scout Drone, Sniper Guard, Boss Warden) spawn across outposts")
	verify(not game.player.has_infinite_ammo() and game.player.reserve_ammo == game.rules.starter_reserve_ammo(), "combat starts with finite reserve ammo while practice keeps infinite")

	# Camp Station 0 remains usable for optional warm-up, WITHOUT farming combat extraction score!
	game.interact()
	verify(game.active_station == 0 and game.stations[0].boards[0].visible, "camp station remains available for optional warm-up")
	var camp_score_before: int = game.rules.score
	game.resolve_answer(game.answer_index, false)
	verify(game.rules.score == camp_score_before, "camp Station 0 warm-up awards 0 combat score in field runs")
	game._leave_station()

	var patrol = game.combat.troops[0][0]
	var patrol_start: Vector3 = patrol.position
	await frames(65)
	verify(patrol.position.distance_to(patrol_start) > 0.55 and patrol.action == Soldier.Action.PATROL, "outpost squad patrols real terrain before aggro")

	# Expanded aggro check: approaching 20m from Zone 0 already triggers combat (aggro = 23m)
	var center0: Vector3 = game.combat.zone_center(0)
	game.player.position = center0 + Vector3(0, 0.1, 19.5)
	await frames(5)
	verify(game.combat.zone == 0 and patrol.word_label.text != "", "expanded 23m aggro radius engages player at medium range")

	var all_words_fit = true
	for entry in game.words:
		game._fit_word(patrol.word_label, entry.english, 118)
		var label = patrol.word_label
		var size = game.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.width, label.font_size)
		if size.y > 118 or size.x > label.width:
			all_words_fit = false
	verify(all_words_fit, "all 175 textbook entries fit the holographic shield")

	# Advance, warn, fire (absorbed by Shield first!), and retreat to cover
	game.player.position = center0 + Vector3(0, 0.08, 1.5)
	game.combat.shot_rng.seed = seed_for_roll(0.0, 0.1)
	await frames(4)
	var saw_warning = false
	var fired = false
	var init_shield: float = game.combat.shield
	var first_attacker
	for i in 320:
		await physics_frame
		for soldier in game.combat.troops[0]:
			if soldier.action == Soldier.Action.AIM:
				saw_warning = true
				first_attacker = soldier
		if game.combat.shield < init_shield or game.combat.health < 100:
			fired = true
			break
	verify(saw_warning and fired and game.combat.shield < init_shield and game.combat.health == 100, "enemy shot warns, fires, and is absorbed by rechargeable shield first")

	var sheltered = false
	if is_instance_valid(first_attacker):
		for i in 180:
			await physics_frame
			if first_attacker.action == Soldier.Action.COVER and first_attacker.position.distance_to(first_attacker.cover_goal) < 0.75 and not game.combat.clear_shot(first_attacker.position):
				sheltered = true
				break
	verify(sheltered, "attacker retreats behind solid cover after firing")
	if is_instance_valid(first_attacker):
		var cover_sh = game.combat.shield
		var rng_state: int = game.combat.shot_rng.state
		game.combat.strike(first_attacker)
		verify(is_equal_approx(game.combat.shield, cover_sh) and game.combat.shot_rng.state == rng_state, "solid cover cancels enemy shot before rolling accuracy")

	# Medkit [H] healing test
	game.combat.health = 50
	game.combat.shield = 5
	var kits_before = game.player.medkits
	game.player.use_medkit()
	verify(game.player.medkits == kits_before - 1 and game.combat.health == 95 and roundi(game.combat.shield) == 30, "field medkit restores +45 HP and +25 shield")

	# Wrong & Correct holographic shield raycast tests
	var before_wrong: int = game.combat.damage_per_shot()
	var wrong = game.combat.troops[0][(game.answer_index + 1) % 4]
	wrong.position = center0 + Vector3(0, 0.08, -3)
	await frames(2)
	var eye: Vector3 = game.player.camera.global_position
	shoot(eye, wrong.shield_area.global_position + wrong.shield_area.global_basis.x * 0.72)
	verify(game.combat.field_answers == 1 and game.combat.rage_left > 6.8 and game.combat.damage_per_shot() > before_wrong, "hitting wrong shield triggers rage and raises enemy damage")
	var wrong_damage: int = game.combat.damage_per_shot()

	game._next_question()
	var correct = game.combat.troops[0][game.answer_index]
	if correct != wrong:
		wrong.position = wrong.home
	correct.position = center0 + Vector3(0, 0.08, -3)
	await frames(2)
	shoot(game.player.camera.global_position, correct.shield_area.global_position)
	verify(game.rules.score == game.Rules.BASE_ANSWER_SCORE and correct.defeated and correct.shield_area.collision_layer == 0, "correct shot awards 15 points and shatters target shield")
	verify(game.combat.rage_left == 0 and game.combat.damage_per_shot() < wrong_damage, "correct answer breaks rage and lowers field damage")
	var score_after_one: int = game.rules.score
	shoot(game.player.camera.global_position, correct.shield_area.global_position)
	verify(game.rules.score == score_after_one, "shooting a downed bot cannot score again")

	# Dual weapon + Knife backstab ammo drop + Smoke/EMP + Stim tests in Zone 1
	game._next_question()
	var center1: Vector3 = game.combat.zone_center(1)
	game.player.position = center1 + Vector3(0, 0.08, 2.0)
	await frames(5)
	verify(game.combat.zone == 1, "mid-route pass outpost activates Zone 1")
	var sniper = null
	for s in game.combat.troops[1]:
		if s.archetype == Soldier.Archetype.SNIPER_GUARD:
			sniper = s
			break
	var saw_laser = false
	if is_instance_valid(sniper):
		sniper.position = center1 + Vector3(0, 0.08, -5.0)
		for i in 220:
			await physics_frame
			if sniper.action == Soldier.Action.AIM and sniper.laser_beam.visible:
				saw_laser = true
				break
	verify(saw_laser, "heavy sniper guard projects visible red laser beam while locking on")

	# Throw Smoke/EMP grenade [G]: stuns Zone 1 squad and conceals player from Sniper clear_shot
	var gren_before: int = game.player.grenades
	game.player.camera.global_position = game.player.position + Vector3(0, 1.58, 0)
	game.player.camera.look_at(center1 + Vector3(0, 0.2, -3.0))
	game.player.throw_smoke_emp()
	await frames(2)
	verify(game.player.grenades == gren_before - 1 and game.combat.smoke_zones.size() >= 1 and is_instance_valid(sniper) and sniper.stun_left > 1.0, "smoke/EMP grenade consumes 1 charge, deploys smoke cloud, and stuns squad")
	game.combat.deploy_smoke_emp(game.player.position)
	verify(game.combat.player_in_smoke() and is_instance_valid(sniper) and not game.combat.clear_shot(sniper.position), "standing inside smoke cloud blocks sniper clear_shot")

	# Test Adrenaline Stim [T]
	game.combat.health = 70
	var stim_before: int = game.player.stims
	game.player.use_stim()
	verify(game.player.stims == stim_before - 1 and game.player.stim_left > 5.0 and game.combat.health > 70, "adrenaline stim triggers sprint+regen buff")

	# Knife backstab execution on a stunned Zone-1 unit recovers +magazine() reserve ammo!
	var knife_victim = game.combat.troops[1][3]
	knife_victim.stun(3.0)
	knife_victim.rotation.y = 0.0
	game.player.position = knife_victim.position - knife_victim.global_transform.basis.z * 1.4
	game.player.ammo = 4
	var res_before: int = game.player.reserve_ammo
	aim.global_position = game.player.position + Vector3(0, 1.58, 0)
	aim.look_at(knife_victim.global_position + Vector3(0, 1.15, 0))
	game.melee_strike(aim)
	verify(knife_victim.defeated and game.player.reserve_ammo == res_before + game.rules.magazine(), "knife backstab executes enemy and recovers +1 magazine reserve ammo")

	# Clear Zone 1 remaining waves so outposts_cleared becomes 1
	game.player.position = center1 + Vector3(0, 0.08, 1.5)
	game.combat.health = 100
	game.combat.shield = 30
	await frames(2)
	if not game.rules.question_open:
		game._next_question()
	for i in 1000:
		await physics_frame
		if game.combat.zone_cleared.get(1, false) or game.rules.phase != "active":
			break
		if not game.rules.question_open:
			continue
		var t1 = game.combat.troops[1][game.answer_index]
		if t1.defeated:
			game._next_question()
			continue
		if i % 20 == 19:
			t1.position = center1 + Vector3(-2.5 + float(game.answer_index) * 1.7, 0.08, -3.2)
		var from1: Vector3 = game.player.camera.global_position
		var at1: Vector3 = t1.shield_area.global_position
		var r1 := PhysicsRayQueryParameters3D.create(from1, at1, 7, [game.player.get_rid()])
		r1.collide_with_areas = true
		var hit1 = game.get_world_3d().direct_space_state.intersect_ray(r1)
		if hit1 and (hit1.collider == t1 or hit1.collider == t1.shield_area):
			game.player.ammo = game.rules.magazine()
			shoot(from1, at1)
	verify(game.rules.outposts_cleared >= 1, "Zone 1 clears cleanly via combat hits")

	# Anti-Bypass Check: 260+ score + 1 outpost cleared WITHOUT Boss defeated MUST still block extraction!
	game.rules.score = 270
	verify(not game.rules.can_extract(), "260+ score + 1 outpost still blocks combat extraction while Zone-B Boss lives")

	# Clear Zone 2 (B · 竹林重兵阵地) + Defeat Boss Warden「铁甲词尊」
	game.rules.score = 220
	var center2: Vector3 = game.combat.zone_center(2)
	game.player.position = center2 + Vector3(0, 0.08, 1.5)
	game.combat.health = 100
	game.combat.shield = 30
	await frames(5)
	verify(game.combat.zone == 2, "bamboo stronghold activates Zone 2")
	var boss = game.combat.boss_unit
	var saw_core_crit := false
	for i in 1200:
		await physics_frame
		if game.rules.boss_defeated or game.rules.phase != "active":
			break
		if is_instance_valid(boss) and not boss.defeated and boss.exposed_left > 0 and not saw_core_crit and is_instance_valid(boss.core_area):
			boss.position = center2 + Vector3(0.0, 0.08, -3.2)
			boss.look_at(Vector3(game.player.position.x, boss.position.y, game.player.position.z), Vector3.UP)
			boss.rotate_y(PI)
			await physics_frame
			var hp_before: int = boss.hp
			var c_from: Vector3 = game.player.camera.global_position
			var c_at: Vector3 = boss.core_area.global_position
			var r_core := PhysicsRayQueryParameters3D.create(c_from, c_at, 7, [game.player.get_rid()])
			r_core.collide_with_areas = true
			var hit_core = game.get_world_3d().direct_space_state.intersect_ray(r_core)
			if hit_core and hit_core.collider == boss.core_area:
				game.player.ammo = game.rules.magazine()
				shoot(c_from, c_at)
				saw_core_crit = boss.hp == hp_before - 42
		if not game.rules.question_open:
			continue
		var target = game.combat.troops[2][game.answer_index]
		if target.defeated:
			game._next_question()
			continue
		if i % 20 == 19:
			target.position = center2 + Vector3(-2.5 + float(game.answer_index) * 1.7, 0.08, -3.4)
		var from2: Vector3 = game.player.camera.global_position
		var at2: Vector3 = target.shield_area.global_position
		var r2 := PhysicsRayQueryParameters3D.create(from2, at2, 7, [game.player.get_rid()])
		r2.collide_with_areas = true
		var hit2 = game.get_world_3d().direct_space_state.intersect_ray(r2)
		if hit2 and (hit2.collider == target or hit2.collider == target.shield_area):
			game.player.ammo = game.rules.magazine()
			shoot(from2, at2)
	verify(saw_core_crit, "shattering a shield in Zone 2 exposes Boss reactor core for 42 crit bullet damage")
	verify(game.rules.boss_defeated and game.rules.outposts_cleared >= 2 and game.rules.score >= game.Rules.EXTRACTION_SCORE and game.rules.can_extract(), "clearing 2 outposts + defeating Zone-B Boss + 260 pts unlocks combat extraction")
	await frames(100)
	verify(is_instance_valid(game.combat.troops[2][0]) and game.combat.troops[2][0] != boss and not game.combat.troops[2][0].defeated and game.rules.boss_defeated, "defeated Boss does not respawn while remnant slot 0 continues")

	game.rules.add_loot("前哨战利品", 82, 3)
	game.player.position = game.exit_position
	await frames(2)
	game.interact()
	verify(game.rules.phase == "extracting", "combat extraction begins at B beacon")
	game.extraction_left = 0.02
	await frames(5)
	verify(game.rules.phase == "result" and game.rules.profile.warehouse.size() > 0 and not game.combat.in_field(), "extraction banks loot and clears combat")

	# Evasion & Lethal Defeat Checks
	game.start_button.pressed.emit()
	await frames(4)
	game.player.position = center0 + Vector3(0, 0.08, 1.5)
	await frames(5)
	var threat = game.combat.troops[0][0]
	for soldier in game.combat.troops[0]:
		soldier.set_physics_process(false)
	threat.position = center0 + Vector3(0, 0.08, -3)
	await frames(20)
	game.combat.shield = 0
	game.combat.shield_delay = 30.0

	var stationary: float = game.combat.hit_chance()
	var same_roll := seed_for_roll(0.50, 0.70)
	var before: int = game.combat.health
	game.combat.shot_rng.seed = same_roll
	game.combat.strike(threat)
	verify(absf(stationary - 0.78) < 0.02 and game.combat.health == before - game.combat.damage_per_shot(threat), "stationary player takes full hit at 78% base accuracy")

	key(KEY_A, true)
	await frames(28)
	var moving: float = game.combat.hit_chance()
	before = game.combat.health
	game.combat.shot_rng.seed = same_roll
	game.combat.strike(threat)
	verify(moving < 0.45 and game.combat.health == before and game.combat.miss_left > 0, "same roll misses when player strafes")

	key(KEY_SHIFT, true)
	await frames(22)
	var sprinting: float = game.combat.hit_chance()
	var jump_roll := seed_for_roll(0.18, 0.23)
	before = game.combat.health
	game.combat.shot_rng.seed = jump_roll
	game.combat.strike(threat)
	verify(absf(sprinting - 0.26) < 0.03 and game.combat.health == before - game.combat.damage_per_shot(threat), "sprinting lowers enemy hit chance to 26%")

	key(KEY_SPACE, true)
	await frames(8)
	var sprint_jump: float = game.combat.hit_chance()
	before = game.combat.health
	game.combat.shot_rng.seed = jump_roll
	game.combat.strike(threat)
	verify(not game.player.is_on_floor() and sprint_jump < 0.16 and game.combat.health == before and game.combat.miss_left > 0, "same roll misses during sprint-jump")

	key(KEY_SPACE, false)
	key(KEY_SHIFT, false)
	key(KEY_A, false)
	game.player.clear_movement_input()
	game.player.position = center0 + Vector3(0, 0.08, 1.5)
	await frames(15)
	game.combat.shield = 0
	game.combat.health = 1
	game.rules.add_loot("未撤离", 50, 2)
	game.combat.shot_rng.seed = seed_for_roll(0.0, 0.1)
	game.combat.strike(threat)
	verify(game.rules.phase == "result" and game.rules.bag.is_empty() and game.menu_title.text.contains("耗尽"), "lethal attack ends run and drops unextracted loot")

	game.practice_button.pressed.emit()
	game.interact()
	verify(game.combat.stage == Battle.Stage.OFF and game.stations[1].boards[0].visible and game.active_station == 0, "free practice starts with stationary boards enabled")

	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("COMBAT_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
