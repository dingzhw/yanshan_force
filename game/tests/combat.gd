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
	game.player.ammo = game.rules.magazine()
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

	# 1. Immediate field deployment into 6 camps × 3 waves × 5 soldiers in standby (Normal Operation default)
	game.start_button.pressed.emit()
	verify(
		game.rules.operation_tier == "normal" and not game.rules.is_confidential() and game.terminal_title_label.text.contains("普通行动"),
		"start_button launches Normal Operation mode with single-attacker HUD tag"
	)
	var all_five_standby := true
	for z_i in game.Layout.COMBAT_ZONES.size():
		if game.combat.living_soldiers(z_i).size() != Battle.SQUAD_SIZE or int(game.combat.waves_target.get(z_i, 0)) != Battle.WAVES_PER_CAMP or game.combat.is_zone_engaged(z_i):
			all_five_standby = false
	verify(
		game.combat.in_field() and game.combat.troops.size() == 6 and all_five_standby,
		"v0.6.1.2 combat deploys 6 mountain camps × 3 waves × 5 soldiers in standby at spawn"
	)
	verify(game.combat.health == 100 and game.combat.shield == 30 and not game.stations[1].boards[0].visible, "player starts with 100 HP + 30 Shield and field static boards disabled")

	var seen_archetypes = {}
	for z_idx in game.combat.troops:
		for s in game.combat.troops[z_idx]:
			seen_archetypes[s.archetype] = true
	verify(seen_archetypes.size() == 4 and is_instance_valid(game.combat.boss_unit), "all 4 enemy archetypes (Assault Bot, Scout Drone, Sniper Guard, Boss Warden) spawn across camps")
	verify(not game.player.has_infinite_ammo() and game.player.reserve_ammo == game.rules.starter_reserve_ammo(), "combat starts with finite reserve ammo while practice keeps infinite")

	# Camp Station 0 remains usable for optional warm-up, WITHOUT farming combat extraction score!
	game.interact()
	verify(game.active_station == 0 and game.stations[0].boards[0].visible, "camp station remains available for optional warm-up")
	var camp_score_before: int = game.rules.score
	game.resolve_answer(game.answer_index, false)
	verify(game.rules.score == camp_score_before, "camp Station 0 warm-up awards 0 combat score in field runs")
	game._leave_station()

	# 2. Standby patrol & non-aggro from afar (> aggro radius) vs spawn-area aggro pull
	var center0: Vector3 = game.combat.zone_center(0)
	game.player.position = center0 + Vector3(0, 0.1, 24.5)
	await frames(65)
	var patrol = game.combat.troops[0][0]
	verify(
		game.combat.zone == -1 and not game.combat.is_zone_engaged(0) and patrol.action == Soldier.Action.PATROL and not patrol.shield_area.visible,
		"standby camp squad patrols at spawn and does NOT auto-chase from 24.5m away"
	)

	# Stepping into Camp 0's spawn aggro radius (~15.5m) pulls aggro on all 5 wave soldiers!
	game.player.position = center0 + Vector3(0, 0.1, 13.5)
	await frames(6)
	var wave0_words := {}
	for s0_check in game.combat.troops[0]:
		wave0_words[str(s0_check.assigned_word.get("english", "")).to_lower()] = true
	var prompted_soldier = game.combat.troops[0][game.answer_index]
	verify(
		game.combat.zone == 0 and game.combat.is_zone_engaged(0) and wave0_words.size() == 5 and patrol.word_label.text != "" and game.question.english == prompted_soldier.assigned_word.english,
		"entering camp aggro radius engages 5-bot wave with 5 distinct words and prompts a living soldier's Chinese meaning"
	)

	var all_words_fit = true
	for entry in game.words:
		game._fit_word(patrol.word_label, entry.english, 110)
		var label = patrol.word_label
		var size = game.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.width, label.font_size)
		if size.y > 110 or size.x > label.width:
			all_words_fit = false
	game.combat.show_question()
	verify(all_words_fit, "all 175 textbook entries fit the holographic word shield")

	# 3. Normal Mode: 0.50x accuracy, single-attacker round-robin token + 4-bot non-firing escort, shield absorb & cover retreat
	game.player.position = center0 + Vector3(0, 0.08, 1.5)
	game.player.clear_movement_input()
	game.player.reset_stance()
	await frames(8)
	var normal_stationary_hit: float = game.combat.hit_chance()
	verify(absf(normal_stationary_hit - 0.39) < 0.025, "Normal Operation halves stationary enemy hit probability from 78%% to ~39%% (got %.2f)" % normal_stationary_hit)
	game.combat.shot_rng.seed = seed_for_roll(0.0, 0.1)
	var saw_warning = false
	var fired = false
	var max_sim_aim := 0
	var saw_four_escort := false
	var init_shield: float = game.combat.shield
	var first_attacker
	for i in 340:
		await physics_frame
		var aim_now := 0
		var escort_now := 0
		for soldier in game.combat.troops[0]:
			if soldier.action == Soldier.Action.AIM:
				aim_now += 1
				if first_attacker == null:
					saw_warning = true
					first_attacker = soldier
			elif not soldier.defeated and soldier.action == Soldier.Action.ADVANCE:
				escort_now += 1
		max_sim_aim = maxi(max_sim_aim, aim_now)
		if aim_now == 1 and escort_now == 4:
			saw_four_escort = true
		if game.combat.shield < init_shield or game.combat.health < 100:
			fired = true
			break
	verify(saw_warning and fired and game.combat.shield < init_shield and game.combat.health == 100, "enemy shot warns, fires, and is absorbed by shield first")
	verify(
		max_sim_aim == 1 and saw_four_escort and game.combat.active_attacker != first_attacker,
		"Normal Operation keeps strictly 1 active attacker while 4 bots escort without firing, then rotates token round-robin"
	)

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

	# 4. High-slope rear lock retention + Leash disengage (>86m) + Hardcore Zero Out-of-Combat Regen + Medkit [H]
	var rear_slope_pos: Vector3 = game.Layout.on_ground(center0 + Vector3(-2.5, 0.0, -9.2)) + Vector3(0.0, 0.12, 0.0)
	game.player.position = rear_slope_pos
	await frames(45)
	var rear_engaged := 0
	for s0 in game.combat.troops[0]:
		if not s0.defeated and s0.action != Soldier.Action.PATROL:
			rear_engaged += 1
	verify(game.combat.zone == 0 and rear_engaged >= 3, "climbing onto elevated slope behind Zone 0 retains enemy lock and squad pursuit")

	# Move >86m away from Zone 0 (to SE valley corner far from all camps) to trigger leash disengage
	game.player.position = game.Layout.on_ground(Vector3(48.0, 0.0, 22.0)) + Vector3(0, 0.15, 0)
	game.combat.health = 50
	game.combat.shield = 5
	await frames(240)
	verify(game.combat.zone == -1 and game.combat.health == 50 and roundi(game.combat.shield) == 5, "leaving pursuit leash disengages camp and does NOT passively auto-regenerate HP or shield")
	var kits_before = game.player.medkits
	game.player.use_medkit()
	verify(game.player.medkits == kits_before - 1 and game.combat.health == 95 and roundi(game.combat.shield) == 30, "field medkit restores +45 HP and +25 shield")

	# 5. Re-engage Camp 0 & test Wrong Hit (0 Damage + +25% Wave Attack Stack) vs 1-Shot Headshot vs 2-Shot Word Shield
	game.player.position = center0 + Vector3(0, 0.08, 2.2)
	await frames(6)
	verify(game.combat.zone == 0 and is_equal_approx(game.combat.damage_multiplier(), 1.0), "returning to Camp 0 re-engages wave at 1.00x base enemy attack")

	var wrong = game.combat.troops[0][(game.answer_index + 1) % Battle.SQUAD_SIZE]
	for s_pause in game.combat.troops[0]:
		s_pause.set_physics_process(false)
	wrong.position = center0 + Vector3(0, 0.08, -2.6)
	wrong.rotation = Vector3.ZERO
	await frames(2)
	var base_wrong_dmg: int = game.combat.damage_per_shot(wrong)
	var prompt_before_wrong: String = str(game.question.get("english", ""))
	shoot(game.player.camera.global_position, wrong.shield_area.global_position)
	verify(
		not wrong.defeated and wrong.hp == wrong.max_hp and wrong.shield_layers == 2 and game.combat.wave_wrong_stacks == 1 and is_equal_approx(game.combat.damage_multiplier(), 1.25) and game.combat.damage_per_shot(wrong) > base_wrong_dmg and str(game.question.get("english", "")) == prompt_before_wrong,
		"hitting wrong soldier deals ZERO HP/shield damage, keeps prompt open, and stacks +25% enemy attack (1.25x)"
	)
	shoot(game.player.camera.global_position, wrong.head_area.global_position)
	verify(
		not wrong.defeated and wrong.hp == wrong.max_hp and wrong.shield_layers == 2 and game.combat.wave_wrong_stacks == 2 and is_equal_approx(game.combat.damage_multiplier(), 1.50),
		"hitting wrong soldier's head also deals ZERO damage and stacks enemy attack to 1.50x"
	)
	wrong.position = wrong.home

	# Headshot on CORRECT soldier = 1-shot instant kill & NO mid-wave respawn!
	var correct_hs = game.combat.troops[0][game.answer_index]
	correct_hs.position = center0 + Vector3(0, 0.08, -2.6)
	correct_hs.rotation = Vector3.ZERO
	await frames(2)
	var score_before_hs: int = game.rules.score
	shoot(game.player.camera.global_position, correct_hs.head_area.global_position)
	verify(
		correct_hs.defeated and correct_hs.head_area.collision_layer == 0 and game.rules.score >= score_before_hs + game.Rules.BASE_ANSWER_SCORE and game.combat.living_soldiers(0).size() == 4,
		"headshot on correct word soldier kills in 1 shot and shrinks pursuing wave to 4/5"
	)
	var score_after_hs: int = game.rules.score
	shoot(game.player.camera.global_position, correct_hs.head_area.global_position)
	verify(game.rules.score == score_after_hs, "shooting a downed bot cannot score again")

	for s_res in game.combat.troops[0]:
		if not s_res.defeated:
			s_res.set_physics_process(true)
	await frames(105)
	verify(
		correct_hs.defeated and game.combat.living_soldiers(0).size() == 4 and not game.combat.troops[0][game.answer_index].defeated,
		"eliminated soldier NEVER respawns mid-wave and Chinese prompt rotates to a remaining living soldier"
	)

	# Word Shield hit on CORRECT soldier = 2-shot kill (1st cracks 1/2, 2nd shatters & kills)!
	for s_pause2 in game.combat.troops[0]:
		s_pause2.set_physics_process(false)
	var correct_sh = game.combat.troops[0][game.answer_index]
	var sh_slot: int = correct_sh.option
	correct_sh.position = center0 + Vector3(0, 0.08, -2.6)
	correct_sh.rotation = Vector3.ZERO
	await frames(2)
	shoot(game.player.camera.global_position, correct_sh.shield_area.global_position)
	verify(
		not correct_sh.defeated and correct_sh.shield_layers == 1 and game.answer_index == sh_slot and correct_sh.shield_area.visible,
		"1st shot on correct word shield cracks shield (1/2) without killing and keeps English word visible"
	)
	shoot(game.player.camera.global_position, correct_sh.shield_area.global_position)
	verify(
		correct_sh.defeated and game.combat.living_soldiers(0).size() == 3 and not game.combat.troops[0][game.answer_index].defeated,
		"2nd shot on cracked word shield shatters & kills soldier (wave 3/5) and advances Chinese prompt"
	)
	for s_res2 in game.combat.troops[0]:
		if not s_res2.defeated:
			s_res2.set_physics_process(true)

	# 6. Kite >aggro away (21.6m from Camp 0) & finish remaining 3 soldiers -> Wave 2 spawns at Camp 0 in STANDBY!
	var kite_pos: Vector3 = game.Layout.on_ground(Vector3(0.0, 0.0, -24.0)) + Vector3(0, 0.12, 0)
	game.player.position = kite_pos
	await frames(12)
	verify(game.combat.zone == 0 and game.combat.is_zone_engaged(0), "active wave continues pursuing player outside spawn aggro radius")

	for kill_step in 3:
		var rem_target = game.combat.troops[0][game.answer_index]
		rem_target.set_physics_process(false)
		rem_target.position = kite_pos + Vector3(0, 0.0, -2.6)
		rem_target.rotation = Vector3.ZERO
		await frames(2)
		shoot(game.player.camera.global_position, rem_target.head_area.global_position)

	verify(
		int(game.combat.waves_done.get(0, 0)) == 1 and game.combat.wave_wrong_stacks == 0 and is_equal_approx(game.combat.damage_multiplier(), 1.0) and game.combat.zone == -1 and not game.combat.is_zone_engaged(0) and game.combat.living_soldiers(0).is_empty() and float(game.combat.zone_reinforce_left.get(0, 0.0)) > 7.5,
		"wiping all 5 pursuing bots resets wrong-shot buff and starts an 8.5s empty-camp reinforcement interval (zero instant respawn)"
	)
	# Stand right inside Camp 0 (2.0m from center!) while reinforcement timer finishes -> Wave 2 arrives in PATROL and respects 14s truce!
	game.player.position = center0 + Vector3(0, 0.08, 2.0)
	await frames(60)
	verify(
		game.combat.living_soldiers(0).is_empty() and float(game.combat.zone_reinforce_left.get(0, 0.0)) > 5.5 and game.combat.zone == -1,
		"standing right inside cleared wave camp during 8.5s interval keeps camp empty for calm looting"
	)
	game.combat.update(8.0)
	await frames(2)
	var spawned_at_home: bool = (game.combat.living_soldiers(0).size() == 5)
	for w2_s in game.combat.troops[0]:
		if Vector2(w2_s.position.x - center0.x, w2_s.position.z - center0.z).length() > 13.5 or w2_s.action != Soldier.Action.PATROL:
			spawned_at_home = false
	await frames(90)
	verify(
		spawned_at_home and float(game.combat.zone_respawn_grace.get(0, 0.0)) > 10.0 and game.combat.zone == -1 and not game.combat.is_zone_engaged(0),
		"after 8.5s interval, Wave 2 arrives at Camp 0 in PATROL standby and grants 14s truce without chasing a nearby looting player"
	)

	# 7. Confidential Operation ("机密行动"): 1.35x valuation, multi-attacker Sniper laser, Smoke/EMP [G], Stim [T], Knife & 3-wave clear
	game.rules.loot_rng.seed = 777
	var norm_leg_loot: Dictionary = game.rules.roll_item_by_rarity(5)
	game.confidential_button.pressed.emit()
	await frames(4)
	game.rules.loot_rng.seed = 777
	var conf_leg_loot: Dictionary = game.rules.roll_item_by_rarity(5)
	verify(
		game.rules.operation_tier == "confidential" and game.rules.is_confidential() and game.terminal_title_label.text.contains("机密行动") and int(conf_leg_loot.get("value", 0)) == roundi(float(norm_leg_loot.get("value", 0)) * 1.35),
		"confidential_button launches Confidential Operation with exact 1.35x loot valuation multiplier"
	)
	var center1: Vector3 = game.combat.zone_center(1)
	game.player.position = center1 + Vector3(0, 0.08, 2.0)
	await frames(6)
	verify(game.combat.zone == 1 and game.combat.is_zone_engaged(1), "entering Camp 1 aggro radius activates Zone 1 Wave 1/3")

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

	var gren_before: int = game.player.grenades
	game.player.camera.global_position = game.player.position + Vector3(0, 1.58, 0)
	game.player.camera.look_at(center1 + Vector3(0, 0.2, -3.0))
	game.player.throw_smoke_emp()
	await frames(2)
	verify(game.player.grenades == gren_before - 1 and game.combat.smoke_zones.size() >= 1 and is_instance_valid(sniper) and sniper.stun_left > 1.0, "smoke/EMP grenade consumes 1 charge, deploys smoke cloud, and stuns squad")
	game.combat.deploy_smoke_emp(game.player.position)
	verify(game.combat.player_in_smoke() and is_instance_valid(sniper) and not game.combat.clear_shot(sniper.position), "standing inside smoke cloud blocks sniper clear_shot")

	game.combat.health = 70
	var stim_before: int = game.player.stims
	game.player.use_stim()
	verify(game.player.stims == stim_before - 1 and game.player.stim_left > 5.0 and game.combat.health > 70, "adrenaline stim triggers sprint+regen buff")

	# Knife execution on the CORRECT Zone-1 soldier executes in 1 hit and recovers +magazine() reserve ammo!
	var knife_victim = game.combat.troops[1][game.answer_index]
	knife_victim.stun(3.0)
	knife_victim.rotation.y = 0.0
	game.player.position = knife_victim.position - knife_victim.global_transform.basis.z * 1.4
	game.player.ammo = 4
	var res_before: int = game.player.reserve_ammo
	aim.global_position = game.player.position + Vector3(0, 1.58, 0)
	aim.look_at(knife_victim.global_position + Vector3(0, 1.15, 0))
	game.melee_strike(aim)
	verify(knife_victim.defeated and game.player.reserve_ammo == res_before + game.rules.magazine(), "knife strike on correct word soldier executes in 1 hit and recovers +1 magazine reserve ammo")

	# Clear all 3 waves of Zone 1 permanently!
	game.player.position = center1 + Vector3(0, 0.08, 1.8)
	game.combat.health = 100
	game.combat.shield = 30
	await frames(2)
	for z1_guard in 40:
		if game.combat.zone_cleared.get(1, false):
			break
		if not game.combat.is_zone_engaged(1):
			game.combat.engage_camp(1)
		var t1 = game.combat.troops[1][game.answer_index]
		if not is_instance_valid(t1) or t1.defeated:
			await frames(2)
			continue
		t1.set_physics_process(false)
		t1.position = center1 + Vector3(0, 0.08, -2.5)
		t1.rotation = Vector3.ZERO
		await frames(2)
		shoot(game.player.camera.global_position, t1.head_area.global_position)
	verify(
		game.combat.zone_cleared.get(1, false) and int(game.combat.waves_done.get(1, 0)) == 3 and game.rules.outposts_cleared == 1,
		"clearing all 3 waves permanently captures Zone 1 camp"
	)

	# Anti-Bypass Check: 260+ score + 1 camp cleared WITHOUT Boss defeated MUST still block extraction!
	game.rules.score = 270
	verify(not game.rules.can_extract(), "260+ score + 1 camp cleared still blocks combat extraction while Zone-B Boss lives")

	# 8. Zone 2 (B区竹林统领营): Boss Warden reactor core 42-crit, non-respawn of Boss in Waves 2-3, and full extraction
	var center2: Vector3 = game.combat.zone_center(2)
	game.player.position = center2 + Vector3(0, 0.08, 2.0)
	game.combat.health = 100
	game.combat.shield = 30
	await frames(6)
	verify(game.combat.zone == 2 and game.combat.is_zone_engaged(2), "bamboo stronghold activates Zone 2 Wave 1/3 with Boss Warden")

	var boss = game.combat.boss_unit
	for z2_pause in game.combat.troops[2]:
		z2_pause.set_physics_process(false)
	boss.position = center2 + Vector3(0, 0.08, -2.8)
	boss.rotation = Vector3.ZERO
	await frames(2)

	# Force prompt onto Boss or crack Boss via headshot when prompted, OR trigger Boss phase exposure via guard kills / Boss hit!
	game.answer_index = boss.option
	game.question = boss.assigned_word
	game.combat.show_question()
	await frames(2)
	# Test 2-shot shield crack on Boss -> exposes reactor core -> shoot reactor core for -42 crit!
	shoot(game.player.camera.global_position, boss.shield_area.global_position)
	verify(boss.shield_layers == 1 and boss.exposed_left <= 0.0, "1st shot on Boss word shield cracks shield (1/2)")
	shoot(game.player.camera.global_position, boss.shield_area.global_position)
	await frames(2)
	verify(boss.exposed_left > 0.0 and is_instance_valid(boss.core_area) and boss.core_area.collision_layer != 0, "2nd shot shatters Boss shield and exposes glowing chest reactor core")

	var hp_before_core: int = boss.hp
	shoot(game.player.camera.global_position, boss.core_area.global_position)
	var saw_core_crit: bool = (boss.hp == hp_before_core - 42)
	verify(saw_core_crit, "shooting exposed Boss reactor core deals 42 critical damage")

	# Finish Wave 1 (defeating Boss + 4 guards), then verify Wave 2 spawns WITHOUT Boss, then clear Waves 2 & 3!
	var checked_wave2_no_boss := false
	for z2_step in 60:
		if game.combat.zone_cleared.get(2, false):
			break
		if not game.combat.is_zone_engaged(2):
			if int(game.combat.waves_done.get(2, 0)) == 1 and not checked_wave2_no_boss:
				checked_wave2_no_boss = true
				game.combat.spawn_pending_wave_now(2)
				var has_second_boss := false
				for s_w2 in game.combat.troops[2]:
					if s_w2.archetype == Soldier.Archetype.BOSS_WARDEN:
						has_second_boss = true
				verify(game.rules.boss_defeated and not has_second_boss and game.combat.living_soldiers(2).size() == 5, "defeated Boss never respawns in Wave 2 while 5 remnant guards spawn at camp")
			game.combat.engage_camp(2)
		var t2 = game.combat.troops[2][game.answer_index]
		if not is_instance_valid(t2) or t2.defeated:
			await frames(2)
			continue
		t2.set_physics_process(false)
		t2.position = center2 + Vector3(0, 0.08, -2.6)
		t2.rotation = Vector3.ZERO
		await frames(2)
		shoot(game.player.camera.global_position, t2.head_area.global_position)

	var boss_core_val := 0
	for b_entry in game.rules.bag:
		if str(b_entry.get("title", "")).contains("统领黄金核心"):
			boss_core_val = int(b_entry.get("value", 0))
	verify(
		game.rules.boss_defeated and boss_core_val == 513 and game.combat.zone_cleared.get(2, false) and game.rules.outposts_cleared >= 2 and game.rules.score >= game.Rules.EXTRACTION_SCORE and game.rules.can_extract(),
		"clearing 2 camps (3 waves each) + defeating Zone-B Boss (513 Confidential core) + >=260 pts unlocks extraction"
	)

	game.rules.add_loot("前哨战利品", 82, 3)
	game.player.position = game.exit_position
	await frames(2)
	game.interact()
	verify(game.rules.phase == "extracting", "combat extraction begins at B beacon")
	game.extraction_left = 0.02
	await frames(5)
	verify(game.rules.phase == "result" and game.rules.profile.warehouse.size() > 0 and not game.combat.in_field(), "extraction banks loot and clears combat")

	# 9. Confidential Stance Evasion, Full 78%/26% Accuracy & Lethal Defeat Checks
	game.confidential_button.pressed.emit()
	await frames(4)
	game.player.position = center0 + Vector3(0, 0.08, 1.5)
	await frames(6)
	var threat = game.combat.troops[0][0]
	for soldier in game.combat.troops[0]:
		soldier.set_physics_process(false)
	threat.position = center0 + Vector3(0, 0.08, -3)
	await frames(20)
	game.combat.shield = 0
	game.combat.shield_delay = 30.0

	var stationary: float = game.combat.hit_chance()
	game.player.set_stance(1, true)
	await frames(16)
	var crouched_hit: float = game.combat.hit_chance()
	game.player.set_stance(2, true)
	await frames(16)
	var prone_hit: float = game.combat.hit_chance()
	verify(crouched_hit < stationary * 0.84 and prone_hit < crouched_hit * 0.80, "crouching and going prone progressively lower enemy hit probability")
	game.player.reset_stance()
	await frames(8)
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
