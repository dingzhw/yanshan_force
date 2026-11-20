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
	var normal_standby_ok := true
	for z_i in game.Layout.COMBAT_ZONES.size():
		var sz_n: int = game.combat.living_soldiers(z_i).size()
		var cov_n: int = game.combat.camp_covers.get(z_i, []).size()
		if sz_n < Battle.NORMAL_MIN_SQUAD or sz_n > Battle.NORMAL_MAX_SQUAD or cov_n != Battle.CAMP_COVER_COUNT or int(game.combat.waves_target.get(z_i, 0)) != Battle.WAVES_PER_CAMP or game.combat.is_zone_engaged(z_i):
			normal_standby_ok = false
	verify(
		game.combat.in_field() and game.combat.troops.size() == 6 and normal_standby_ok,
		"v0.6.6 Normal Operation deploys 6 camps × 3 waves × random 3-4 soldiers across 7 castellated cover slots"
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

	# Stepping into Camp 0's spawn aggro radius (~15.8m) pulls aggro on the 3-4 wave soldiers & triggers cover bounding!
	game.player.position = center0 + Vector3(0, 0.1, 13.5)
	await frames(6)
	var squad0_n: int = game.combat.troops[0].size()
	var wave0_words := {}
	var claimed_slots := {}
	for s0_check in game.combat.troops[0]:
		wave0_words[str(s0_check.assigned_word.get("english", "")).to_lower()] = true
		if s0_check.claimed_cover_idx >= 0:
			claimed_slots[s0_check.claimed_cover_idx] = true
	var prompted_soldier = game.combat.troops[0][game.answer_index]
	verify(
		game.combat.zone == 0 and game.combat.is_zone_engaged(0) and wave0_words.size() == squad0_n and claimed_slots.size() == squad0_n and patrol.word_label.text != "" and game.question.english == prompted_soldier.assigned_word.english,
		"entering camp aggro radius engages 3-4 bot wave with distinct words & unique claimed cover slots"
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

	# 3. Normal Mode: 0.50x accuracy, single-attacker token + cautious cover-holding teammates + moving suppression fire
	game.player.position = center0 + Vector3(0, 0.08, 1.5)
	game.player.clear_movement_input()
	game.player.reset_stance()
	await frames(8)
	var normal_stationary_hit: float = game.combat.hit_chance()
	verify(absf(normal_stationary_hit - 0.39) < 0.025, "Normal Operation halves stationary enemy hit probability from 78%% to ~39%% (got %.2f)" % normal_stationary_hit)
	game.combat.shot_rng.seed = seed_for_roll(0.0, 0.08)
	var saw_warning = false
	var fired = false
	var max_sim_aim := 0
	var saw_cover_escort := false
	var min_cautious_dist := 999.0
	var init_shield: float = game.combat.shield
	var first_attacker
	for i in 360:
		await physics_frame
		var aim_now := 0
		var escort_now := 0
		for soldier in game.combat.troops[0]:
			var hd := Vector2(soldier.position.x - game.player.position.x, soldier.position.z - game.player.position.z).length()
			min_cautious_dist = minf(min_cautious_dist, hd)
			if soldier.action == Soldier.Action.AIM:
				aim_now += 1
				if first_attacker == null:
					saw_warning = true
					first_attacker = soldier
			elif not soldier.defeated and soldier.action in [Soldier.Action.ADVANCE, Soldier.Action.COVER]:
				escort_now += 1
		max_sim_aim = maxi(max_sim_aim, aim_now)
		if aim_now == 1 and escort_now == squad0_n - 1:
			saw_cover_escort = true
		if first_attacker != null and first_attacker.action == Soldier.Action.COVER and (game.combat.shield < init_shield or game.combat.health < 100):
			fired = true
			break
	verify(saw_warning and fired and game.combat.shield < init_shield and game.combat.health == 100, "enemy shot warns, fires, and is absorbed by shield first")
	verify(
		max_sim_aim == 1 and saw_cover_escort and min_cautious_dist > 5.0 and game.combat.active_attacker != first_attacker,
		"Normal Operation keeps strictly 1 active attacker while cautious teammates hold camp covers (>5m stand-off, zero face-hug)"
	)

	var returned_to_cover = false
	if is_instance_valid(first_attacker):
		for i in 180:
			await physics_frame
			if first_attacker.action == Soldier.Action.COVER and first_attacker.position.distance_to(first_attacker.cover_goal) < 0.75:
				returned_to_cover = true
				break
	verify(returned_to_cover, "attacker returns to a cover position after firing")
	if is_instance_valid(first_attacker):
		# The first camp has low frontal walls and tall flanks. Sample the latter for full cover.
		var original_position: Vector3 = first_attacker.position
		var flank: Vector3 = game.combat.camp_covers[0][0]
		game.player.position = game.Layout.on_ground(flank + Vector3(0, 0, 5.0))
		first_attacker.position = game.Layout.on_ground(flank - Vector3(0, 0, 1.42))
		var cover_sh = game.combat.shield
		var rng_state: int = game.combat.shot_rng.state
		verify(not game.combat.clear_shot(first_attacker.position), "tall first-camp flank fully blocks line of sight")
		game.combat.strike(first_attacker)
		verify(is_equal_approx(game.combat.shield, cover_sh) and game.combat.shot_rng.state == rng_state, "solid flank cover cancels enemy shot before rolling accuracy")
		first_attacker.position = original_position

	# 4. High-slope rear lock retention + Small-range out-of-camp pursuit (~28m) + Cautious disengage (>44m) + Medkit [H]
	var rear_slope_pos: Vector3 = game.Layout.on_ground(center0 + Vector3(-2.5, 0.0, -9.2)) + Vector3(0.0, 0.12, 0.0)
	game.player.position = rear_slope_pos
	await frames(45)
	var rear_engaged := 0
	for s0 in game.combat.troops[0]:
		if not s0.defeated and s0.action != Soldier.Action.PATROL:
			rear_engaged += 1
	verify(game.combat.zone == 0 and rear_engaged >= 2, "climbing onto elevated slope behind Zone 0 retains enemy lock and squad pursuit")

	# Small-range out-of-camp pursuit (~28m from Camp 0) keeps Normal mode cautiously engaged!
	game.player.position = game.Layout.on_ground(center0 + Vector3(0.0, 0.0, 28.0)) + Vector3(0.0, 0.12, 0.0)
	await frames(30)
	verify(game.combat.zone == 0 and game.combat.is_zone_engaged(0), "Normal Operation maintains small-range out-of-camp pursuit (~28m)")

	# Retreating >44m in Normal mode (e.g. 52m away to SE valley) triggers cautious disengage & zero passive regen
	game.player.position = game.Layout.on_ground(Vector3(48.0, 0.0, 22.0)) + Vector3(0, 0.15, 0)
	game.combat.health = 50
	game.combat.shield = 5
	await frames(240)
	verify(game.combat.zone == -1 and game.combat.health == 50 and roundi(game.combat.shield) == 5, "leaving Normal 44m pursuit perimeter disengages camp and does NOT passively auto-regenerate HP or shield")
	var kits_before = game.player.medkits
	game.player.use_medkit()
	verify(game.player.medkits == kits_before - 1 and game.combat.health == 95 and roundi(game.combat.shield) == 30, "field medkit restores +45 HP and +25 shield")

	# 5. Re-engage Camp 0 & test Wrong Hit vs 1-Shot Headshot vs 2-Shot Cracked-Shield Cover Reposition + Moving Suppression
	game.player.position = center0 + Vector3(0, 0.08, 2.2)
	await frames(6)
	verify(game.combat.zone == 0 and is_equal_approx(game.combat.damage_multiplier(), 1.0), "returning to Camp 0 re-engages wave at 1.00x base enemy attack")

	var wave0_init_alive: int = game.combat.living_soldiers(0).size()
	var wrong = game.combat.troops[0][(game.answer_index + 1) % wave0_init_alive]
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
		correct_hs.defeated and correct_hs.head_area.collision_layer == 0 and game.rules.score >= score_before_hs + game.Rules.BASE_ANSWER_SCORE and game.combat.living_soldiers(0).size() == wave0_init_alive - 1,
		"headshot on correct word soldier kills in 1 shot and shrinks living wave by 1"
	)
	var score_after_hs: int = game.rules.score
	shoot(game.player.camera.global_position, correct_hs.head_area.global_position)
	verify(game.rules.score == score_after_hs, "shooting a downed bot cannot score again")

	for s_res in game.combat.troops[0]:
		if not s_res.defeated:
			s_res.set_physics_process(true)
	await frames(105)
	verify(
		correct_hs.defeated and game.combat.living_soldiers(0).size() == wave0_init_alive - 1 and not game.combat.troops[0][game.answer_index].defeated,
		"eliminated soldier NEVER respawns mid-wave and Chinese prompt rotates to a remaining living soldier"
	)

	# Word Shield hit on CORRECT soldier = 2-shot kill (1st cracks 1/2 & triggers cover reposition + moving suppression fire!)
	for s_pause2 in game.combat.troops[0]:
		s_pause2.set_physics_process(false)
	var correct_sh = game.combat.troops[0][game.answer_index]
	var sh_slot: int = correct_sh.option
	var prev_cov_idx: int = correct_sh.claimed_cover_idx
	correct_sh.position = center0 + Vector3(0, 0.08, -2.6)
	correct_sh.rotation = Vector3.ZERO
	await frames(2)
	shoot(game.player.camera.global_position, correct_sh.shield_area.global_position)
	verify(
		not correct_sh.defeated and correct_sh.shield_layers == 1 and game.answer_index == sh_slot and correct_sh.shield_area.visible and (correct_sh.is_bounding_to_cover or correct_sh.claimed_cover_idx != prev_cov_idx),
		"1st shot on correct word shield cracks shield (1/2) and triggers emergency cover reposition"
	)
	# Let the shield-cracked soldier bound toward its new cover for ~0.7s so it fires moving suppression on the run!
	var supp_before: int = game.combat.moving_suppression_shots
	game.combat.suppress_lock = 0.0
	correct_sh.stun_left = 0.0
	correct_sh.suppress_cd = 0.02
	correct_sh.set_physics_process(true)
	await frames(28)
	correct_sh.set_physics_process(false)
	verify(game.combat.moving_suppression_shots > supp_before, "soldier bounding to cover fires moving suppression shots toward player")

	correct_sh.position = center0 + Vector3(0, 0.08, -2.6)
	correct_sh.rotation = Vector3.ZERO
	await frames(2)
	shoot(game.player.camera.global_position, correct_sh.shield_area.global_position)
	verify(
		correct_sh.defeated and game.combat.living_soldiers(0).size() == wave0_init_alive - 2 and not game.combat.troops[0][game.answer_index].defeated,
		"2nd shot on cracked word shield shatters & kills soldier and advances Chinese prompt"
	)
	for s_res2 in game.combat.troops[0]:
		if not s_res2.defeated:
			s_res2.set_physics_process(true)

	# 6. Kite >aggro away (21.6m from Camp 0) & finish remaining soldiers -> 15s empty camp + 15s truce (= 30s safe window)!
	var kite_pos: Vector3 = game.Layout.on_ground(Vector3(0.0, 0.0, -24.0)) + Vector3(0, 0.12, 0)
	game.player.position = kite_pos
	await frames(12)
	verify(game.combat.zone == 0 and game.combat.is_zone_engaged(0), "active wave continues pursuing player in small-range out-of-camp perimeter (21.6m)")

	for kill_step in 6:
		if game.combat.living_soldiers(0).is_empty():
			break
		var rem_target = game.combat.troops[0][game.answer_index]
		rem_target.set_physics_process(false)
		rem_target.position = kite_pos + Vector3(0, 0.0, -2.6)
		rem_target.rotation = Vector3.ZERO
		await frames(2)
		shoot(game.player.camera.global_position, rem_target.head_area.global_position)

	verify(
		int(game.combat.waves_done.get(0, 0)) == 1 and game.combat.wave_wrong_stacks == 0 and is_equal_approx(game.combat.damage_multiplier(), 1.0) and game.combat.zone == -1 and not game.combat.is_zone_engaged(0) and game.combat.living_soldiers(0).is_empty() and float(game.combat.zone_reinforce_left.get(0, 0.0)) > 14.0,
		"wiping pursuing wave resets wrong-shot buff and starts full 15s empty-camp reinforcement interval"
	)
	# Stand right inside Camp 0 (2.0m from center!) for 10s -> camp MUST still be empty (15s delay > 10s)!
	game.player.position = center0 + Vector3(0, 0.08, 2.0)
	game.combat.update(10.0)
	await frames(4)
	verify(
		game.combat.living_soldiers(0).is_empty() and float(game.combat.zone_reinforce_left.get(0, 0.0)) > 4.2 and game.combat.zone == -1,
		"camp remains 100% empty past 10s so player has plenty of time to loot and walk away"
	)
	# Advance past 15s -> Wave 2 (3-4 bots) arrives in PATROL and grants another 15s truce (30s total safe window)!
	game.combat.update(5.5)
	await frames(2)
	var w2_count: int = game.combat.living_soldiers(0).size()
	var spawned_at_home: bool = (w2_count >= Battle.NORMAL_MIN_SQUAD and w2_count <= Battle.NORMAL_MAX_SQUAD)
	for w2_s in game.combat.troops[0]:
		if Vector2(w2_s.position.x - center0.x, w2_s.position.z - center0.z).length() > 14.5 or w2_s.action != Soldier.Action.PATROL:
			spawned_at_home = false
	await frames(90)
	verify(
		spawned_at_home and float(game.combat.zone_respawn_grace.get(0, 0.0)) > 12.5 and game.combat.zone == -1 and not game.combat.is_zone_engaged(0),
		"after 15s interval, Wave 2 (3-4 bots) arrives at Camp 0 in PATROL and grants 15s truce (30s total breathing window)"
	)

	# 7. Confidential Operation ("机密行动"): random 3-6 squad sizes, 1.35x valuation, Sniper laser, Smoke/EMP, Stim, Knife & 3-wave clear
	game.rules.loot_rng.seed = 777
	var norm_leg_loot: Dictionary = game.rules.roll_item_by_rarity(5)
	game.confidential_button.pressed.emit()
	await frames(4)
	var conf_sizes_ok := true
	for cz_i in game.Layout.COMBAT_ZONES.size():
		var c_sz: int = game.combat.living_soldiers(cz_i).size()
		if c_sz < Battle.CONF_MIN_SQUAD or c_sz > Battle.CONF_MAX_SQUAD:
			conf_sizes_ok = false
	game.rules.loot_rng.seed = 777
	var conf_leg_loot: Dictionary = game.rules.roll_item_by_rarity(5)
	verify(
		conf_sizes_ok and game.rules.operation_tier == "confidential" and game.rules.is_confidential() and game.terminal_title_label.text.contains("机密行动") and int(conf_leg_loot.get("value", 0)) == roundi(float(norm_leg_loot.get("value", 0)) * 1.35),
		"confidential_button launches Confidential Operation with random 3-6 squad sizes and exact 1.35x loot valuation"
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
				var w2_z2_cnt: int = game.combat.living_soldiers(2).size()
				verify(game.rules.boss_defeated and not has_second_boss and w2_z2_cnt >= Battle.CONF_MIN_SQUAD and w2_z2_cnt <= Battle.CONF_MAX_SQUAD, "defeated Boss never respawns in Wave 2 while 3-6 remnant guards spawn at camp")
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

	# 10. v0.7.0 Nemesis Bounty deterministic wave injection, bounty kill reward & all-camp readability promotion!
	var nemesis_id := "js5a2026-061" # warm up (has textbook Cloze sentence 'We should ____.')
	game.rules.profile.review_due[nemesis_id] = "incorrect"
	game.start_action(true, "normal")
	await frames(6)
	var found_nemesis = null
	for s in game.combat.troops[0]:
		if is_instance_valid(s) and str(s.assigned_word.get("id", "")) == nemesis_id:
			found_nemesis = s
			break
	verify(found_nemesis != null and found_nemesis.is_nemesis_bounty, "due mistake word is deterministically injected into Camp 0 wave as golden Nemesis Bounty soldier")
	game.player.position = center0 + Vector3(0, 0.08, 4.0)
	game.combat.engage_camp(0)
	await frames(4)
	verify(str(game.question.get("id", "")) == nemesis_id and game.cloze_label.text.contains("We should ____."), "engaging camp surfaces Nemesis word first with verified textbook Cloze context")
	for s_p in game.combat.troops[0]:
		s_p.set_physics_process(false)
	found_nemesis.position = center0 + Vector3(0, 0.08, -1.8)
	found_nemesis.rotation = Vector3.ZERO
	await frames(2)
	var score_pre_nem: int = game.rules.score
	shoot(game.player.camera.global_position, found_nemesis.head_area.global_position)
	verify(
		found_nemesis.defeated and game.rules.nemesis_cleared == 1 and game.rules.score >= score_pre_nem + game.Rules.BASE_ANSWER_SCORE + game.Rules.NEMESIS_BONUS_SCORE and not game.rules.profile.review_due.has(nemesis_id),
		"independently defeating Nemesis Bounty soldier grants +10 bonus, increments nemesis_cleared & clears review_due"
	)

	# All-6-camp readability generalization check (Camp 2 B-Zone uses elevated shield_y & tall outer flank cover)
	var b_non_boss = null
	for s2 in game.combat.troops[2]:
		if is_instance_valid(s2) and s2.archetype != Soldier.Archetype.BOSS_WARDEN:
			b_non_boss = s2
			break
	var b_flank: Vector3 = game.combat.camp_covers[2][0]
	game.player.position = game.Layout.on_ground(b_flank + Vector3(0, 0, 5.0))
	var b_flank_blocked: bool = not game.combat.clear_shot(game.Layout.on_ground(b_flank - Vector3(0, 0, 1.42)))
	verify(b_non_boss != null and b_non_boss.shield_area.position.y >= 1.33 and b_flank_blocked, "Camp 2 B-Zone shares unified elevated word shields and tall outer flank cover")

	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("COMBAT_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
