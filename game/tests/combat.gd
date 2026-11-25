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
	game.rules.profile.review_due.clear()
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

	# 2. v0.8.3 ADS-Gated Sniper Preview (3x camp aggro ~46-48m): standby soldiers show English shields at spawn (<=98m),
	# do NOT auto-chase from afar, stay SILENT without right-click ADS, ignore camps beyond 3x aggro, and lock+speak ONLY on ADS!
	var center0: Vector3 = game.combat.zone_center(0)
	game.player.position = game.Layout.on_ground(center0 + Vector3(0, 0, 24.5)) + Vector3(0, 0.12, 0)
	game.player.aiming = false
	await frames(65)
	var patrol = game.combat.troops[0][0]
	verify(
		game.combat.zone == -1 and not game.combat.is_zone_engaged(0) and patrol.action == Soldier.Action.PATROL and patrol.shield_area.visible and patrol.word_label.text != "" and patrol.word_label.visibility_range_end >= 90.0,
		"v0.8.1 #3: standby camp squad patrols at spawn, does NOT auto-chase from 24.5m, and visibly displays long-range word shields"
	)
	# (a) Looking directly at Camp 0 from 24.5m WITHOUT ADS -> MUST NOT preview HUD or auto-speak!
	var d_patrol: Vector3 = patrol.shield_area.global_position - game.player.camera.global_position
	game.player.yaw = atan2(-d_patrol.x, -d_patrol.z)
	game.player.pitch = atan2(d_patrol.y, Vector2(d_patrol.x, d_patrol.z).length())
	game.last_voice_key = ""
	await frames(6)
	verify(
		game.combat.preview_zone == -1 and game.last_voice_key == "" and not game.unit_label.text.contains("开镜狙词") and not game.prompt_timer_fill.visible,
		"v0.8.3 ADS-gated sniping: looking at Camp 0 from 24.5m WITHOUT ADS stays silent and hides sniper prompt"
	)
	# (b) Even WITH ADS, aiming from beyond 3x aggro (56m > 47.4m) MUST NOT trigger sniper preview or audio!
	game.player.position = game.Layout.on_ground(center0 + Vector3(0, 0, 56.0)) + Vector3(0, 0.12, 0)
	game.player.aiming = true
	await frames(2)
	var d_far: Vector3 = patrol.shield_area.global_position - game.player.camera.global_position
	game.player.yaw = atan2(-d_far.x, -d_far.z)
	game.player.pitch = atan2(d_far.y, Vector2(d_far.x, d_far.z).length())
	game.last_voice_key = ""
	await frames(6)
	verify(
		game.combat.preview_zone == -1 and game.last_voice_key == "",
		"v0.8.3 ADS-gated sniping: ADS beyond 3x camp aggro (56m > 47.4m) never previews or auto-speaks"
	)
	# (c) Right-click ADS directly at Camp 0 from 24.5m (within 3x aggro & clear LOS) -> locks HUD & speaks target English word!
	game.player.aiming = false
	game.player.position = game.Layout.on_ground(center0 + Vector3(0, 0, 24.5)) + Vector3(0, 0.12, 0)
	await frames(2)
	d_patrol = patrol.shield_area.global_position - game.player.camera.global_position
	game.player.yaw = atan2(-d_patrol.x, -d_patrol.z)
	game.player.pitch = atan2(d_patrol.y, Vector2(d_patrol.x, d_patrol.z).length())
	await frames(2)
	game.rules.set_setting("auto_speak_on_switch", true)
	game.last_voice_key = ""
	game.player.aiming = true
	await frames(6)
	verify(
		game.combat.preview_zone == 0 and game.unit_label.text.contains("开镜狙词") and game.question_label.text == str(game.question.get("chinese", "")) and game.prompt_timer_fill.visible and game.last_voice_key != "" and game.question_help_used,
		"v0.8.3 / v0.9.9.4 ADS-gated sniping: right-click ADS within 3x aggro previews target Chinese prompt, countdown bar, and (when opt-in auto-speak is enabled) speaks English with assisted_audio flag"
	)
	# (d) Releasing ADS clears distant preview immediately; rapid re-ADS within 1.2s debounce does not spam audio!
	game.player.aiming = false
	await frames(4)
	verify(
		game.combat.preview_zone == -1 and not game.prompt_timer_fill.visible,
		"v0.8.3 ADS-gated sniping: releasing ADS immediately clears distant sniper preview"
	)
	game.last_voice_key = ""
	game.player.aiming = true
	await frames(4)
	verify(
		game.combat.preview_zone == 0 and game.last_voice_key == "",
		"v0.8.3 ADS-gated sniping: rapid re-ADS on same camp within 1.2s debounce does not spam duplicate audio"
	)
	game.player.aiming = false
	game.rules.set_setting("auto_speak_on_switch", false)
	await frames(4)

	# Stepping into Camp 0's spawn aggro radius (~15.8m) WITHOUT ADS pulls aggro without leaking pre-answer English audio!
	game.last_voice_key = ""
	game.player.position = game.Layout.on_ground(center0 + Vector3(0, 0, 13.5)) + Vector3(0, 0.08, 0)
	game.player.velocity = Vector3.ZERO
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
		game.combat.zone == 0 and game.combat.is_zone_engaged(0) and game.last_voice_key == "" and not game.question_help_used and wave0_words.size() == squad0_n and claimed_slots.size() == squad0_n and patrol.word_label.text != "" and game.question.english == prompted_soldier.assigned_word.english,
		"v0.9.9.4: entering camp aggro radius engages 3-4 bot wave without pre-answer English spoiler and assigns distinct words & cover slots"
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
	game.player.position = game.Layout.on_ground(center0 + Vector3(0, 0, 1.5)) + Vector3(0, 0.06, 0)
	game.player.velocity = Vector3.ZERO
	game.player.clear_movement_input()
	game.player.reset_stance()
	await frames(14)
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
	game.player.position = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION + Vector3(-2.0, 0.0, 2.0)) + Vector3(0, 0.15, 0)
	game.combat.health = 50
	game.combat.shield = 5
	await frames(240)
	verify(game.combat.zone == -1 and game.combat.health == 50 and roundi(game.combat.shield) == 5, "leaving Normal 44m pursuit perimeter disengages camp and does NOT passively auto-regenerate HP or shield")
	var kits_before = game.player.medkits
	game.player.use_medkit()
	verify(game.player.medkits == kits_before - 1 and game.combat.health == 95 and roundi(game.combat.shield) == 30, "field medkit restores +45 HP and +25 shield")

	# 5. Re-engage Camp 0 & test v0.8.1 #4 Strict Wrong-Answer Rotation + #8 3-Wrong Rage Hunt (2.0x Normal) + 1-Shot Headshot vs 2-Shot Shield
	game.player.position = center0 + Vector3(0, 0.08, 2.2)
	await frames(6)
	verify(game.combat.zone == 0 and is_equal_approx(game.combat.damage_multiplier(), 1.0), "returning to Camp 0 re-engages wave at 1.00x base enemy attack")

	var wave0_init_alive: int = game.combat.living_soldiers(0).size()
	var wrong = game.combat.troops[0][(game.answer_index + 1) % wave0_init_alive]
	for s_pause in game.combat.troops[0]:
		s_pause.set_physics_process(false)
		s_pause.position = center0 + Vector3(6.5, 0.08, -6.5)
	wrong.position = center0 + Vector3(0, 0.08, -2.6)
	wrong.rotation = Vector3.ZERO
	await frames(2)
	var base_wrong_dmg: int = game.combat.damage_per_shot(wrong)
	var prompt_before_wrong: String = str(game.question.get("english", ""))
	shoot(game.player.camera.global_position, wrong.shield_area.global_position)
	verify(
		not wrong.defeated and wrong.hp == wrong.max_hp and wrong.shield_layers == 2 and game.combat.wave_wrong_stacks == 1 and game.combat.consecutive_wrong_hits == 1 and is_equal_approx(game.combat.damage_multiplier(), 1.25) and game.combat.damage_per_shot(wrong) > base_wrong_dmg and game.combat.prompt_locked_after_wrong and game.combat.prompt_reveal_left > 1.0,
		"v0.8.1 #4: hitting wrong soldier deals ZERO damage, locks old answer for 1.4s reveal, and stacks +25% enemy attack (1.25x)"
	)
	# Attempting to shoot the just-revealed correct soldier during 1.4s lock MUST NOT score or kill!
	var locked_right = game.combat.troops[0][game.answer_index]
	locked_right.position = center0 + Vector3(2.4, 0.08, -2.6)
	locked_right.rotation = Vector3.ZERO
	await frames(2)
	var pre_lock_score: int = game.rules.score
	shoot(game.player.camera.global_position, locked_right.head_area.global_position)
	verify(not locked_right.defeated and game.rules.score == pre_lock_score, "v0.8.1 #4: shooting revealed answer during 1.4s lock cannot cheat score or kill")
	# Advance past 1.4s reveal -> MUST switch to a brand-new English word!
	game.combat.update(1.55)
	verify(not game.combat.prompt_locked_after_wrong and str(game.question.get("english", "")) != prompt_before_wrong, "v0.8.1 #4: after 1.4s reveal, combat automatically rotates to a brand-new word")

	# Two more consecutive wrong hits (total 3) trigger Normal Rage Hunt (12s, 2.0x damage, 145m pursuit)!
	for s_park in game.combat.troops[0]:
		s_park.position = center0 + Vector3(6.5, 0.08, -6.5)
	wrong = game.combat.troops[0][(game.answer_index + 1) % wave0_init_alive]
	wrong.position = center0 + Vector3(0, 0.08, -2.6)
	wrong.rotation = Vector3.ZERO
	await frames(2)
	shoot(game.player.camera.global_position, wrong.head_area.global_position)
	verify(not wrong.defeated and game.combat.consecutive_wrong_hits == 2 and is_equal_approx(game.combat.damage_multiplier(), 1.50), "2nd consecutive wrong hit deals ZERO damage and raises counter to 2/3")
	game.combat.update(1.55)
	for s_park2 in game.combat.troops[0]:
		s_park2.position = center0 + Vector3(6.5, 0.08, -6.5)
	wrong = game.combat.troops[0][(game.answer_index + 1) % wave0_init_alive]
	wrong.position = center0 + Vector3(0, 0.08, -2.6)
	wrong.rotation = Vector3.ZERO
	await frames(2)
	shoot(game.player.camera.global_position, wrong.shield_area.global_position)
	verify(
		game.combat.is_rage_hunting(0) and game.combat.rage_hunt_left > 10.0 and is_equal_approx(game.combat.damage_multiplier(), 2.0) and game.combat.zone_pursuit(0) >= 140.0,
		"v0.8.1 #8: 3 consecutive wrong hits trigger Normal Rage Hunt (12s, 2.0x damage, 145m pursuit)"
	)
	# Clear reveal lock & verify unanswered 10s timeout rotates cleanly in Normal mode
	game.combat.update(1.55)
	var pre_to_word: String = str(game.question.get("english", ""))
	verify(is_equal_approx(game.combat.prompt_timer_max, 10.0), "v0.8.1 #4: Normal mode prompt countdown is 10.0s")
	game.combat.prompt_timer_left = 0.05
	game.combat.update(0.10)
	verify(str(game.question.get("english", "")) != pre_to_word, "v0.8.1 #4: Normal combat prompt auto-rotates on 10s timeout")
	# Reset rage timer and park all soldiers back at home for clean headshot/shield checks below
	game.combat.rage_hunt_left = 0.0
	game.combat.rage_hunt_zone = -1
	for s_park3 in game.combat.troops[0]:
		s_park3.position = s_park3.home

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
	for s_rel in game.combat.troops[0]:
		if s_rel != correct_sh and s_rel.action != s_rel.Action.ADVANCE:
			game.combat.on_soldier_attack_finished(s_rel)
			s_rel.action = s_rel.Action.ADVANCE
	game.combat.suppress_lock = 0.0
	correct_sh.stun_left = 0.0
	correct_sh.cooldown = 1.5
	correct_sh.suppress_cd = 0.02
	if not correct_sh.is_bounding_to_cover or Vector2(correct_sh.position.x - correct_sh.bound_goal.x, correct_sh.position.z - correct_sh.bound_goal.z).length() < 3.0:
		correct_sh.bound_goal = game.Layout.on_ground(center0 + Vector3(5.6, 0.0, -3.2))
		correct_sh.is_bounding_to_cover = true
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
	var kite_pos: Vector3 = game.Layout.on_ground(center0 + Vector3(12.0, 0.0, 18.0)) + Vector3(0, 0.12, 0)
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
	game.rules.profile.review_due.clear()
	game.rules.profile.mastery.clear()
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
	verify(is_equal_approx(game.combat.prompt_timer_max, 7.0), "v0.8.1 #4: Confidential mode prompt countdown tightens to 7.0s")

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

	# v0.8.2_dev2 D2-1: Confidential knife requires 10 slashes (not 1-hit kill!) and recovers +4 emergency reserve ammo!
	game.combat.health = 100
	game.combat.shield = 60
	game.combat.prompt_locked_after_wrong = false
	game.combat.prompt_timer_left = 7.0
	var knife_victim = game.combat.troops[1][game.answer_index]
	for s_k in game.combat.troops[1]:
		s_k.set_physics_process(false)
		if s_k != knife_victim:
			s_k.position = game.Layout.on_ground(center1 + Vector3(8.5, 0.0, -8.5))
	knife_victim.stun(3.0)
	knife_victim.position = game.Layout.on_ground(center1 + Vector3(0.0, 0.0, -2.0))
	knife_victim.rotation = Vector3.ZERO
	game.player.position = game.Layout.on_ground(knife_victim.position + Vector3(0.0, 0.0, -1.4)) + Vector3(0.0, 0.06, 0.0)
	game.player.ammo = 4
	game.player.reserve_ammo = 10
	var res_before: int = game.player.reserve_ammo
	aim.global_position = game.player.position + Vector3(0, 1.58, 0)
	aim.look_at(knife_victim.global_position + Vector3(0, 1.15, 0))
	game.melee_strike(aim)
	var survived_first_slash: bool = (not knife_victim.defeated) and knife_victim.melee_hits_taken == 1
	for _ks in 9:
		if knife_victim.defeated:
			break
		game.player.position = game.Layout.on_ground(knife_victim.position + Vector3(0.0, 0.0, -1.4)) + Vector3(0.0, 0.06, 0.0)
		aim.global_position = game.player.position + Vector3(0, 1.58, 0)
		aim.look_at(knife_victim.global_position + Vector3(0, 1.15, 0))
		game.melee_strike(aim)
	verify(survived_first_slash and knife_victim.defeated and knife_victim.melee_hits_taken == 10 and game.player.reserve_ammo == res_before + 4, "v0.8.2_dev2 D2-1: Confidential knife takes 10 hits (no 1-hit cheese) and recovers +4 reserve ammo on kill")

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

	# v0.8.2 #12 & #13: Confidential Zone 2 spawns giant Skyfall 5-Shield Overlord ("雾隐机关王·玄铁词尊")
	verify(
		boss.is_skyfall_overlord and boss.multi_shields.size() == 5 and boss.hp == 500 and game.Layout.COMBAT_ZONES[2].title.contains("雾隐帮"),
		"v0.8.2 #12/#13: Confidential Zone 2 spawns Mistbound Syndicate Skyfall 5-Shield Overlord (500 HP)"
	)
	boss.force_land_skyfall()
	verify(game.player.screen_shake > 0.5, "v0.8.2 #12: Skyfall Overlord landing triggers seismic full-screen camera shake")
	await frames(2)

	# Step 1: Break 1st sequential shield -> HP drops 500 -> 400 and step advances 0 -> 1
	var first_slot: int = boss.expected_overlord_slot()
	shoot(game.player.camera.global_position, boss.multi_shields[first_slot].area.global_position)
	await frames(2)
	verify(boss.overlord_seq_step == 1 and boss.hp == 400 and boss.multi_shields[first_slot].broken, "v0.8.2 #12: shooting correct 1st Overlord shield shatters it (-100 HP, step 1/5)")

	# Step 2: Shoot WRONG out-of-order shield -> FULL RESET to 500 HP, step 0/5 & reshuffle all 5 shields!
	var wrong_slot: int = boss.overlord_seq_slots[3]
	shoot(game.player.camera.global_position, boss.multi_shields[wrong_slot].area.global_position)
	await frames(2)
	var all_five_intact := true
	for sd_chk in boss.multi_shields:
		if bool(sd_chk.broken):
			all_five_intact = false
	verify(boss.overlord_seq_step == 0 and boss.hp == 500 and all_five_intact, "v0.8.2 #12: shooting out-of-order shield resets Overlord HP to 500/500 and restores/reshuffles all 5 shields")

	# Step 3: Break all 5 Round-1 shields in strict 1->5 order -> transitions cleanly to Round 2 (3 fast-orbiting golden shields), then break all 3 Round-2 shields -> Overlord defeated + overlord_1 unlocked!
	for _os in 5:
		var req_s: int = boss.expected_overlord_slot()
		var sp1: Vector3 = boss.multi_shields[req_s].area.global_position
		var od1: Vector3 = Vector3(sp1.x - boss.global_position.x, 0.0, sp1.z - boss.global_position.z)
		od1 = od1.normalized() if od1.length() > 0.1 else Vector3.BACK
		shoot(sp1 + od1 * 3.2, sp1)
		await frames(1)
	verify(not boss.defeated and boss.overlord_round == 2 and boss.hp == 300 and boss.overlord_orbit_active, "v0.8.6: clearing Round-1 5 shields advances Skyfall Overlord to Round 2 (300 HP, 3 orbiting shields)")
	for _os2 in 3:
		var req_s2: int = boss.expected_overlord_slot()
		var sp2: Vector3 = boss.multi_shields[req_s2].area.global_position
		var od2: Vector3 = Vector3(sp2.x - boss.global_position.x, 0.0, sp2.z - boss.global_position.z)
		od2 = od2.normalized() if od2.length() > 0.1 else Vector3.BACK
		shoot(sp2 + od2 * 3.2, sp2)
		await frames(1)
	verify(boss.defeated and game.rules.boss_defeated and game.achievements.is_unlocked("overlord_1"), "v0.8.6: breaking Round-1 (5 shields) + Round-2 (3 orbiting shields) defeats Skyfall Overlord and unlocks overlord_1 achievement")

	# Finish Wave 1 remaining guards, then verify Wave 2 spawns WITHOUT Boss, then clear Waves 2 & 3!
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
	while game.rules.score < game.rules.extraction_score_required():
		game.rules.open_question()
		game.rules.answer(true)
	if game.rules.outposts_cleared < game.Rules.REQUIRED_OUTPOSTS:
		game.rules.outposts_cleared = game.Rules.REQUIRED_OUTPOSTS
	verify(
		game.rules.boss_defeated and boss_core_val == 621 and game.combat.zone_cleared.get(2, false) and game.rules.outposts_cleared >= game.Rules.REQUIRED_OUTPOSTS and game.rules.score >= game.rules.extraction_score_required() and game.rules.can_extract(),
		"clearing 3 camps + defeating Zone-B Boss (621 Confidential T6 core) + >=520 pts unlocks Confidential extraction"
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
	game.rules.profile.review_due.clear()
	game.rules.profile.mastery.clear()
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
	verify(game.combat.stage == Battle.Stage.OFF and game.stations[0].boards[0].visible and not game.stations[1].boards[0].visible and game.active_station == 0, "free practice shows active station boards while keeping inactive stations hidden")

	# Confidential 4.0x distant Rage Hunt check (#8): 3 consecutive wrong snipes from 52m away triggers 4.0x Rage Hunt!
	game.start_action(true, "confidential")
	await frames(4)
	game.player.position = game.Layout.on_ground(center0 + Vector3(0.0, 0.0, 52.0)) + Vector3(0.0, 0.12, 0.0)
	await frames(4)
	for s_c in game.combat.troops[0]:
		s_c.set_physics_process(false)
	for rw in 3:
		var cw_opt: int = (int(game.combat.zone_prompt_option.get(0, 0)) + 1) % game.combat.troops[0].size()
		var cw_s = game.combat.troops[0][cw_opt]
		game.combat.hit_bullet(cw_s.shield_area, "", cw_s.shield_area.global_position)
		if rw < 2:
			game.combat.update(1.55)
	verify(
		game.combat.is_rage_hunting(0) and game.combat.zone == 0 and is_equal_approx(game.combat.damage_multiplier(), 4.0),
		"v0.8.1 #8: 3 wrong distant sniper hits in Confidential Operation trigger 4.0x Rage Hunt & force-engage camp from 52m"
	)
	game._end_run(false)

	# 10. v0.7.0 Nemesis Bounty deterministic wave injection, bounty kill reward & all-camp readability promotion!
	var nemesis_id := "js5a2026-061" # warm up (has textbook Cloze sentence 'We should ____.')
	game.rules.profile.review_due.clear()
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

	# 11. v0.8.6 Normal Mode Boss 3-Phase Multi-Shield Tactical Duel + Anti-Crouch-Snipe Cave Warden (Normal & Confidential)!
	var norm_boss = game.combat.boss_unit
	verify(is_instance_valid(norm_boss) and not norm_boss.is_skyfall_overlord and norm_boss.hp == 600 and norm_boss.vanguard_shields.size() == 3, "v0.8.6: Normal Mode Boss '雾隐先锋·铁面词卫' spawns with 600 HP and 3-slot Vanguard Word-Shield Matrix")
	# Engage Zone 2 in Normal mode and verify Boss mortar barrage spawns a red danger ring + v0.9.9.4 honest audio-assist separation!
	game.rules.set_setting("auto_speak_on_switch", false)
	game.last_voice_key = ""
	game.combat.engage_camp(2)
	var switched_en: String = str(game.question.get("english", ""))
	verify(
		game.last_voice_key == "" and not game.question_help_used and game.word_switch_flash > 0.0,
		"v0.9.9.4: default combat word switch flashes visually without leaking pre-answer English audio or help penalty"
	)
	game.rules.set_setting("auto_speak_on_switch", true)
	var auto_spoke_z2: bool = game.trigger_question_audio(true)
	verify(
		auto_spoke_z2 and game.last_voice_key == game.normalize_voice_key(switched_en) and game.question_help_used and game.question_audio_assisted,
		"v0.9.9.4: opt-in auto_speak_on_switch speaks English on switch AND honestly flags assisted_audio help"
	)
	game.rules.set_setting("auto_speak_on_switch", false)
	game.clear_question_help()
	var pre_rings: int = game.combat.danger_rings.size()
	game.combat.boss_barrage_cd = 0.02
	game.combat.update(0.05)
	verify(game.combat.danger_rings.size() > pre_rings, "v0.8.6: Normal Boss fires periodic red danger-ring mortar barrages")
	# v0.8.6 Normal Boss Phase 1 -> Capped 1-shot Core Pulse -> Phase 2 Twin Shoulder Shields -> Phase 3 Triple Matrix + Energy Wave!
	for z2_n in game.combat.troops[2]:
		z2_n.set_physics_process(false)
	game.combat.zone_prompt_option[2] = norm_boss.option
	game.answer_index = norm_boss.option
	game.question = norm_boss.assigned_word
	game.combat.prompt_locked_after_wrong = false
	var pre_p1_hp: int = norm_boss.hp
	game.combat.hit_bullet(norm_boss.head_area, "", Vector3.ZERO)
	verify(norm_boss.hp == pre_p1_hp - 150 and norm_boss.boss_core_pulse_shots == 1, "v0.8.6: Phase 1 Normal Boss headshot deals -150 HP and opens strictly 1-shot Bonus Core Pulse")
	# First core shot deals -45 & closes pulse; second core shot CANNOT spam core!
	var hp_before_core1: int = norm_boss.hp
	game.combat.hit_bullet(norm_boss.core_area, "", Vector3.ZERO)
	verify(norm_boss.hp == hp_before_core1 - 45 and norm_boss.boss_core_pulse_shots == 0, "v0.8.6: single Bonus Core Pulse shot deals -45 HP and immediately closes core")
	# Force HP across Phase 2 (<=400) -> deploys Twin Shoulder Word Shields + Scout Drones!
	game.combat.zone_prompt_option[2] = norm_boss.option
	game.answer_index = norm_boss.option
	game.question = norm_boss.assigned_word
	game.combat.hit_bullet(norm_boss.head_area, "", Vector3.ZERO)
	verify(norm_boss.boss_phase == 2 and norm_boss.vanguard_multi_active() and norm_boss.vanguard_active_count == 2 and norm_boss.vanguard_drones_spawned, "v0.8.6: Normal Boss <=66% HP shifts to Phase 2 Twin Shoulder Word Shields + deploys Scout Drones")
	# Shooting torso/armor during Phase 2 multi-shield deflects for 0 dmg!
	var hp_p2_arm: int = norm_boss.hp
	game.combat.zone_prompt_option[2] = norm_boss.option
	game.answer_index = norm_boss.option
	game.question = norm_boss.expected_vanguard_word()
	game.combat.hit_bullet(norm_boss.head_area, "", Vector3.ZERO)
	verify(norm_boss.hp == hp_p2_arm, "v0.8.6: Normal Boss Phase 2/3 deflects non-shield shots (0 dmg) forcing true English shield choice")
	# Shooting WRONG Vanguard decoy shield deals 0 dmg & refreshes word pair!
	var wrong_v_slot: int = (norm_boss.expected_vanguard_slot() + 1) % 2
	game.combat.hit_bullet(norm_boss.vanguard_shields[wrong_v_slot].area, "", Vector3.ZERO)
	verify(norm_boss.hp == hp_p2_arm, "v0.8.6: hitting wrong Vanguard decoy shield deals 0 dmg and refreshes word pair")
	# Shooting CORRECT Vanguard shield deals damage & pushes into Phase 3 Triple Matrix (<=200 HP) + Energy Wave!
	var pre_waves: int = game.combat.sword_waves.size()
	var ok_v_slot: int = norm_boss.expected_vanguard_slot()
	game.combat.hit_bullet(norm_boss.vanguard_shields[ok_v_slot].area, "", Vector3.ZERO)
	verify(norm_boss.boss_phase == 1 and norm_boss.vanguard_active_count == 3 and game.combat.sword_waves.size() > pre_waves, "v0.8.6: Normal Boss <=33% HP enters Phase 3 Triple Word-Shield Matrix and launches horizontal Energy Wave")
	# Restore Normal melee target & verify 5-hit melee + wrong-melee counter-bash cleanly!
	game.combat.prompt_locked_after_wrong = false
	var norm_melee_s = null
	var wrong_melee_s = null
	for ns in game.combat.troops[2]:
		if is_instance_valid(ns) and not ns.defeated and ns.archetype != Soldier.Archetype.BOSS_WARDEN:
			if norm_melee_s == null:
				norm_melee_s = ns
			elif wrong_melee_s == null:
				wrong_melee_s = ns
	if norm_melee_s != null:
		game.combat.zone_prompt_option[2] = norm_melee_s.option
		game.answer_index = norm_melee_s.option
		game.question = norm_melee_s.assigned_word
		norm_melee_s.set_physics_process(false)
		game.player.reserve_ammo = 10
		game.combat.health = 100
		game.combat.shield = 30
		var norm_survived_4 := true
		var hp_bar_before_m: float = norm_melee_s.hp_fill.scale.x
		verify(norm_melee_s.shield_area.position.y >= 2.35 and is_instance_valid(norm_melee_s.chest_core_root), "v0.9.8: regular word soldiers mount compact overhead holographic word tag (y=%.2f) + embedded chest word core" % norm_melee_s.shield_area.position.y)
		for hit_i in 4:
			game.player.position = norm_melee_s.position - norm_melee_s.global_transform.basis.z * 1.35
			aim.global_position = game.player.position + Vector3(0, 1.58, 0)
			aim.look_at(norm_melee_s.global_position + Vector3(0, 1.15, 0))
			game.melee_strike(aim)
			if norm_melee_s.defeated:
				norm_survived_4 = false
		var hp_bar_after_4: float = norm_melee_s.hp_fill.scale.x
		var hp_lbl_vis_4: bool = is_instance_valid(norm_melee_s.hp_text_label) and norm_melee_s.hp_text_label.visible
		game.player.position = norm_melee_s.position - norm_melee_s.global_transform.basis.z * 1.35
		aim.global_position = game.player.position + Vector3(0, 1.58, 0)
		aim.look_at(norm_melee_s.global_position + Vector3(0, 1.15, 0))
		game.melee_strike(aim)
		verify(norm_survived_4 and hp_bar_after_4 < hp_bar_before_m - 0.35 and hp_lbl_vis_4 and norm_melee_s.defeated and norm_melee_s.melee_hits_taken == 5 and game.player.reserve_ammo == 16, "v0.9.8: Normal knife slashes visibly shrink 3D HP bar per hit (%.2f->%.2f) & execute on 5th hit (+6 reserve ammo)" % [hp_bar_before_m, hp_bar_after_4])
	if wrong_melee_s != null and not wrong_melee_s.defeated:
		wrong_melee_s.set_physics_process(false)
		game.combat.prompt_locked_after_wrong = false
		game.combat.health = 100
		game.combat.shield = 30
		if wrong_melee_s.option == game.answer_index:
			game.answer_index = norm_boss.option
		game.player.position = wrong_melee_s.position - wrong_melee_s.global_transform.basis.z * 1.35
		aim.global_position = game.player.position + Vector3(0, 1.58, 0)
		aim.look_at(wrong_melee_s.global_position + Vector3(0, 1.15, 0))
		game.melee_strike(aim)
		verify(game.combat.shield < 30.0 or game.combat.health < 100, "v0.8.2_dev2 D2-1: wrong melee slash triggers immediate close-quarters enemy counter-bash")
	game.combat.disengage_active_camp(false)

	var cw = game.cave_warden
	cw.reset()
	var cw_core_shp: SphereShape3D = (cw.core_area.get_child(0) as CollisionShape3D).shape as SphereShape3D
	var cw_articulated: bool = is_instance_valid(cw.body_mesh) and is_instance_valid(cw.arm_left_pivot) and is_instance_valid(cw.arm_right_pivot) and is_instance_valid(cw.head_crest)
	verify(is_instance_valid(cw) and cw.is_alive() and cw.state == "patrol" and cw.hp == 280 and cw_articulated and is_equal_approx(cw_core_shp.radius, 0.30), "v0.8.6: Cave Warden loads articulated 4-part Blender rig with compact 0.30m chest core & 280 Normal HP")
	# Outer camp gunfire (> 22m away) MUST NOT alert Cave Warden!
	cw.on_gunshot(cw.root_node.position + Vector3(24.0, 0, 18.0), false)
	verify(cw.state == "patrol" and cw.noise_meter == 0.0 and not cw.shot_origin_active, "v0.8.6: outer camp combat beyond 22m never pulls Cave Warden out of isolated Yanxia Cave ravine")
	cw.register_noise(cw.root_node.position + Vector3(0, 0, 6.0), 4.0)
	verify(cw.state == "patrol", "v0.8.6: quiet stealth keeps Cave Warden unalerted")
	cw.on_gunshot(cw.root_node.position + Vector3(0, 0, 4.0), false)
	cw.on_gunshot(cw.root_node.position + Vector3(0, 0, 4.0), false)
	verify(cw.state == "hunt" and cw.noise_meter >= 75.0, "v0.8.6: loud gunshots inside Yanxia Cave trigger Cave Warden hunt lock")
	# Leaving Yanxia Cave far away immediately cancels hunt & Warden never leaves cave corridor!
	game.player.position = game.Layout.on_ground(game.Layout.COMBAT_ZONES[0].at) + Vector3(0, 0.2, 0)
	cw.update(0.1)
	verify(cw.state == "patrol" and cw.root_node.position.x >= cw.cave_min_x() and cw.root_node.position.x <= cw.cave_max_x() and cw.root_node.position.z >= cw.cave_min_z() and cw.root_node.position.z <= cw.cave_max_z(), "v0.8.6: leaving Yanxia Cave immediately drops hunt and strictly confines Warden inside cave")
	# v0.8.6 Anti-Crouch-Snipe Redesign: core hit NEVER stuns, locks firing spot, raises X-guard, AND fires Focused Anti-Sniper Sonic Lance!
	cw.reset()
	var c_cen: Vector3 = game.Layout.YANXIA_CAVE_CENTER
	var c_fy: float = float(game.Layout.CAVE_FLOOR_Y) + 0.03
	cw.root_node.position = Vector3(c_cen.x, c_fy, c_cen.z + 2.2)
	cw.root_node.rotation = Vector3.ZERO
	game.player.position = Vector3(c_cen.x, c_fy, c_cen.z + 9.2) # 7.0m crouch-snipe range (>5.5m)
	game.player.velocity = Vector3.ZERO
	game.player.stance = game.player.STANCE_CROUCH
	game.combat.health = 100
	game.combat.shield = 30
	await frames(2)
	var hp_pre_core: int = cw.hp
	cw.hit_bullet(cw.core_area)
	cw.snap_articulation_for_pose()
	verify(cw.hp == hp_pre_core - 60 and cw.state == "hunt" and cw.state != "stunned" and cw.guard_arms and cw.shot_origin_active and cw.lance_state == "charging" and cw.arm_left_pivot.rotation.y > 0.5 and cw.arm_right_pivot.rotation.y < -0.5, "v0.8.6: long-range crouch-snipe on Cave Warden core NEVER stuns — raises X-guard, locks firing spot & charges Focused Sonic Lance")
	# Staying camped in crouch at the exact firing spot FREEZES stealth disengage at 0.0 AND eats the Focused Sonic Lance!
	for _camp_t in 12:
		cw.update(0.10)
	verify(cw.stealth_quiet_timer == 0.0 and cw.guard_arms and cw.sonic_lance_count >= 1 and (game.combat.shield < 30.0 or game.combat.health < 100), "v0.8.6: stationary crouch-sniping at firing spot freezes stealth disengage and gets punished by Focused Sonic Lance")
	# Real 3D frontal raycast while guarding hits guard_area FIRST for 10 chip dmg!
	await frames(2)
	var hp_pre_guard_ray: int = cw.hp
	var sp_cw: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var cw_ray_from: Vector3 = cw.root_node.global_position + Vector3(0.0, 1.56, 3.6)
	var cw_ray_to: Vector3 = cw.root_node.global_position + Vector3(0.0, 1.56, -0.5)
	var cw_q := PhysicsRayQueryParameters3D.create(cw_ray_from, cw_ray_to, cw.HIT_LAYER)
	cw_q.collide_with_areas = true
	var cw_hit_guard := sp_cw.intersect_ray(cw_q)
	var guard_blocked_ok: bool = (not cw_hit_guard.is_empty()) and (cw_hit_guard.collider == cw.guard_area)
	if not cw_hit_guard.is_empty():
		cw.hit_bullet(cw_hit_guard.collider)
	verify(guard_blocked_ok and cw.hp == hp_pre_guard_ray - 10 and cw.deflect_flash_left > 0.05, "v0.8.6: frontal 3D raycast aimed at chest core while guarding hits arm-shield guard_area for 10 chip dmg")
	# Now stealth-relocate >= 3.2m laterally away from last_shot_pos -> clears shot lock & 1.5s silence cleanly drops hunt & lowers arms!
	game.player.position = cw.last_shot_pos + Vector3(3.3, 0.0, 0.0)
	game.player.stance = game.player.STANCE_CROUCH
	game.player.velocity = Vector3.ZERO
	cw.lance_state = "idle"
	cw.update(0.80)
	verify(not cw.shot_origin_active and cw.guard_arms and cw.state == "hunt", "v0.8.6: relocating >2.8m clears shot lock; before 1.5s completes Warden still guards")
	cw.update(0.80)
	cw.snap_articulation_for_pose()
	await frames(2)
	var cw_q2 := PhysicsRayQueryParameters3D.create(cw.root_node.global_position + Vector3(0.0, 1.56, 3.6), cw.root_node.global_position + Vector3(0.0, 1.56, -0.5), cw.HIT_LAYER)
	cw_q2.collide_with_areas = true
	var hp_pre_open_ray: int = cw.hp
	var cw_hit_open := sp_cw.intersect_ray(cw_q2)
	var open_hit_core: bool = (not cw_hit_open.is_empty()) and (cw_hit_open.collider == cw.core_area)
	if not cw_hit_open.is_empty():
		cw.hit_bullet(cw_hit_open.collider)
	verify(open_hit_core and cw.hp == hp_pre_open_ray - 60 and cw.guard_arms and cw.state != "stunned", "v0.8.6: relocating >2.8m + 1.5s silence lowers arms -> next core raycast hits for 60 dmg and re-triggers guard")
	# [G] Smoke breaks shot lock & accelerates silent disengage (NO stun!)
	cw.state = "hunt"
	cw.set_guard_arms(true, 4.0)
	cw.shot_origin_active = true
	cw.stealth_quiet_timer = 0.0
	cw.on_smoke_emp(cw.root_node.position + Vector3(0, 0, 2.0))
	verify(cw.state != "stunned" and not cw.shot_origin_active and cw.stealth_quiet_timer >= 1.2, "v0.8.6: [G] smoke clears ballistic lock and accelerates silent disengage without stunning Warden")
	cw.update(0.35)
	verify(cw.state == "patrol" and not cw.guard_arms, "v0.8.6: brief silence after [G] smoke drops Warden search and opens arms cleanly")
	var pre_cw_score: int = game.rules.score
	var pre_drops_cnt: int = game.world_loot.drop_nodes.size()
	for _cwh in 6:
		if not cw.is_alive():
			break
		cw.set_guard_arms(false, 0.0)
		cw.hit_bullet(cw.core_area)
	verify(not cw.is_alive() and game.rules.score >= pre_cw_score + 80 and game.achievements.is_unlocked("warden_1") and game.achievements.is_charm_unlocked("charm_sonar") and game.world_loot.drop_nodes.size() == pre_drops_cnt + 1, "v0.8.6: core-strike stealth loop defeats Cave Warden cleanly, grants +80 pts/warden_1/charm_sonar & spawns physical relic drop pouch")
	# v0.8.6 Confidential Cave Warden Mechanical Differentiation: 360 HP, Active Echolocation Sweep (caught crouched / evaded prone!) & Enraged Resonance (<45% HP)!
	game._end_run(false)
	game.start_action(true, "confidential")
	await frames(3)
	cw.reset()
	cw.root_node.position = Vector3(c_cen.x, c_fy, c_cen.z + 2.2)
	cw.root_node.rotation = Vector3.ZERO
	game.player.position = Vector3(c_cen.x, c_fy, c_cen.z + 8.5)
	game.player.velocity = Vector3.ZERO
	game.player.stance = game.player.STANCE_CROUCH
	cw.state = "hunt"
	cw.echo_sweep_cd = 0.0
	cw.lance_state = "idle"
	cw.quake_cd = 9.0
	cw.update(0.05)
	verify(cw.hp == 360 and cw.echo_charging, "v0.8.6 Confidential Cave Warden uses mechanical Active Echolocation Sweep (360 HP, not HP sponge)")
	cw.update(1.25)
	verify(cw.echo_detected_count >= 1 and cw.shot_origin_active and cw.lance_state == "charging", "v0.8.6 Confidential Active Echolocation detects open crouched player & chains Sonic Lance")
	# Prone [Z] evades Active Echolocation 100%!
	game.player.stance = game.player.STANCE_PRONE
	cw.lance_state = "idle"
	cw.echo_sweep_cd = 0.0
	cw.update(0.05)
	cw.update(1.25)
	verify(cw.echo_evaded_count >= 1, "v0.8.6 Confidential Active Echolocation is cleanly evaded by [Z] Prone posture")
	# Dropping <=45% HP triggers Confidential-Exclusive Enraged Resonance!
	cw.hp = 170
	cw.set_guard_arms(false, 0.0)
	cw.hit_bullet(cw.core_area)
	verify(cw.enraged_resonance, "v0.8.6 Confidential Cave Warden enters Enraged Resonance below 45% HP")

	# 12. v0.8.2_dev1 C2 & C4: Camp Warm-Up zero-contamination, Overlord accurate candidate/help count & Practice Range Cave Warden dormancy!
	game._end_run(false)
	game.start_action(true, "normal")
	await frames(4)
	game.interact()
	await frames(2)
	game.resolve_answer(game.answer_index, false)
	var cw_stats: Dictionary = game.rules.profile.get("learning_stats", {}).get("camp_warmup", {})
	verify(
		game.rules.score == 0 and game.rules.answered == 0 and game.rules.correct == 0 and int(cw_stats.get("total", 0)) >= 1,
		"v0.8.2_dev1 C4: Camp Station 0 warm-up during Combat leaves combat score/answered/accuracy untouched while logging camp_warmup channel"
	)
	# v0.8.6 Flagship Confidential Overlord ("雾隐机关王·玄铁词尊"):
	# Zero ADS early-drop, <=22m Cloud Arena proximity skyfall, 5-part articulated rig, R1 (500 HP, 5 shields -> last 3 orbit),
	# R2 (300 HP, 3 fast-orbiting golden shields, 10s countdown), Ultimate「天地万象」Mirror Yanshan crush (Shield->0, HP->10, 4.5s breather -> rearm),
	# plus accurate 1-of-1 candidate logging (one_choice)!
	game.start_action(true, "confidential")
	await frames(4)
	var ov_boss = game.combat.boss_unit
	verify(
		is_instance_valid(ov_boss) and ov_boss.is_skyfall_overlord and ov_boss.skyfall_state == "idle"
		and not ov_boss.visible and ov_boss.collision_layer == 0
		and is_instance_valid(ov_boss.ov_arm_l) and is_instance_valid(ov_boss.ov_arm_r)
		and is_instance_valid(ov_boss.ov_head) and is_instance_valid(ov_boss.ov_halo),
		"v0.8.6: Confidential Overlord spawns hidden in clouds with 5-part articulated rig (arms/head/dharma halo)"
	)
	# Aiming with ADS from ~44m away (clear of other camps) MUST NOT drop or engage Overlord!
	var arena_c: Vector3 = game.Layout.CLOUD_ARENA_CENTER
	game.player.position = game.Layout.on_ground(arena_c + Vector3(36.0, 0.0, 26.0)) + Vector3(0.0, 0.14, 0.0)
	game.player.aiming = true
	var d_ov_far: Vector3 = (ov_boss.global_position + Vector3(0, 2.0, 0)) - game.player.camera.global_position
	game.player.yaw = atan2(-d_ov_far.x, -d_ov_far.z)
	game.player.pitch = atan2(d_ov_far.y, Vector2(d_ov_far.x, d_ov_far.z).length())
	await frames(6)
	verify(game.combat._detect_aimed_camp() != 2 and ov_boss.skyfall_state == "idle" and not ov_boss.visible, "v0.8.6: distant ADS aiming NEVER triggers early Overlord skyfall")
	game.player.aiming = false
	# Stepping within <=22m of Cloud-Top Arena triggers proximity skyfall!
	game.player.position = game.Layout.on_ground(arena_c + Vector3(0.0, 0.0, 14.0)) + Vector3(0.0, 0.14, 0.0)
	await frames(4)
	verify(ov_boss.skyfall_state in ["dropping", "landed"] and ov_boss.visible, "v0.8.6: entering <=22m Cloud-Top Arena triggers Overlord skyfall arrival")
	ov_boss.force_land_skyfall()
	ov_boss.position = game.Layout.on_ground(arena_c + Vector3(0.0, 0.0, -2.5))
	game.player.position = game.Layout.on_ground(arena_c + Vector3(0.0, 0.0, 7.2)) + Vector3(0.0, 0.12, 0.0)
	await frames(2)
	verify(ov_boss.overlord_round == 1 and ov_boss.hp == 500 and not ov_boss.overlord_orbit_active, "v0.8.6: Overlord lands in Round 1 (500 HP, 5 word shields)")
	# Break Round 1 shields 1..5 in exact order; after 2 hits remaining 3 orbit; 5th logs one_choice & enters Round 2!
	var last_shield_word_id := ""
	var prev_last_ind := 0
	var r1_orbit_started := false
	for step_i in 5:
		var exp_w: Dictionary = ov_boss.expected_overlord_word()
		var exp_slot: int = ov_boss.expected_overlord_slot()
		if step_i == 4:
			last_shield_word_id = str(exp_w.get("id", ""))
			prev_last_ind = int(game.rules.profile.mastery.get(last_shield_word_id, {}).get("independent_correct", 0))
		var sp_r1: Vector3 = ov_boss.multi_shields[exp_slot].area.global_position
		var od_r1: Vector3 = Vector3(sp_r1.x - ov_boss.global_position.x, 0.0, sp_r1.z - ov_boss.global_position.z)
		od_r1 = od_r1.normalized() if od_r1.length() > 0.1 else Vector3.BACK
		shoot(sp_r1 + od_r1 * 3.2, sp_r1)
		await frames(1)
		if step_i == 1 and ov_boss.overlord_orbit_active:
			r1_orbit_started = true
	var last_entry: Dictionary = game.rules.profile.mastery.get(last_shield_word_id, {})
	verify(
		int(last_entry.get("last_choice_count", 0)) == 1 and str(last_entry.get("last_outcome", "")) == "one_choice" and int(last_entry.get("independent_correct", 0)) == prev_last_ind,
		"v0.8.2_dev1 C4: Overlord final 1-of-1 shield logs choice_count=1 (one_choice) without inflating independent_correct"
	)
	verify(
		r1_orbit_started and not ov_boss.defeated and ov_boss.overlord_round == 2 and ov_boss.hp == 300
		and ov_boss.overlord_orbit_active and ov_boss.overlord_seq_words.size() == 3 and ov_boss.overlord_r2_timer > 8.0,
		"v0.8.6: breaking R1 shields activates orbiting after 2 hits and transitions cleanly to Round 2 (300 HP, 3 fast-orbiting golden shields, 10s countdown)"
	)
	# Let Round 2 countdown expire -> Ultimate「天地万象」Inverted Mirror Yanshan Mountain descends, crushes Shield->0 & HP->10 (non-lethal!), then 4.5s breather & re-arms R2!
	game.combat.health = 100
	game.combat.shield = 60.0
	ov_boss.overlord_r2_timer = 0.05
	await frames(6)
	verify(
		ov_boss.overlord_ultimate_state == "descending" and is_instance_valid(ov_boss.mirror_mountain_node) and ov_boss.overlord_ultimate_count == 1,
		"v0.8.6: Round 2 timeout triggers Ultimate「天地万象」and spawns descending Inverted Mirror Yanshan Mountain"
	)
	# Fast-forward ultimate impact crush -> verify Shield==0 & HP==10 (non-lethal!)
	ov_boss.overlord_ultimate_timer = 0.02
	await frames(4)
	verify(
		ov_boss.overlord_ultimate_state == "holding" and game.combat.health == 10 and is_equal_approx(game.combat.shield, 0.0) and game.rules.phase == "active",
		"v0.8.6: Ultimate「天地万象」impact strips Shield->0 and crushes HP->10 without killing player"
	)
	# Fast-forward holding -> lifting -> 4.5s healing breather -> re-arm Round 2
	ov_boss.overlord_ultimate_timer = 0.02
	await frames(4)
	ov_boss.overlord_ultimate_timer = 0.02
	await frames(4)
	verify(ov_boss.overlord_ultimate_state == "recovery" and ov_boss.overlord_recovery_left > 3.5, "v0.8.6: Ultimate lifts cleanly into 4.5s healing breather window")
	ov_boss.overlord_ultimate_timer = 0.02
	await frames(4)
	verify(ov_boss.overlord_ultimate_state == "none" and ov_boss.overlord_round == 2 and ov_boss.overlord_r2_timer > 8.5, "v0.8.6: after 4.5s breather, Overlord re-arms Round 2 orbiting shields cleanly")
	# Break all 3 Round-2 orbiting shields in sequence from clear outward sightline to defeat Overlord!
	game.combat.health = 100
	for r2_i in 3:
		var r2_slot: int = ov_boss.expected_overlord_slot()
		var sh_pos: Vector3 = ov_boss.multi_shields[r2_slot].area.global_position
		var out_dir: Vector3 = Vector3(sh_pos.x - ov_boss.global_position.x, 0.0, sh_pos.z - ov_boss.global_position.z)
		out_dir = out_dir.normalized() if out_dir.length() > 0.1 else Vector3.BACK
		shoot(sh_pos + out_dir * 3.2, sh_pos)
		await frames(1)
	verify(ov_boss.defeated and game.rules.boss_defeated, "v0.8.6: breaking all 3 Round-2 orbiting golden shields defeats Overlord cleanly")
	# Practice Range keeps Cave Warden dormant and non-interactive:
	game.start_action(false)
	await frames(2)
	verify(not game.cave_warden.is_mode_active() and not game.cave_warden.root_node.visible and game.cave_warden.core_area.collision_layer == 0, "v0.8.2_dev1 C2: Cave Warden stays dormant and hidden in pure Practice Range")

	# 13. v0.8.3 R2: Default Ranger '少羽' [V] Active Skill '天生神力' (1.5s Knockdown, 30s Cooldown, Boss/Warden Stagger & Viewmodel Slam)
	game.start_action(true, "normal")
	await frames(4)
	verify(is_instance_valid(game.rangers) and game.rangers.active_ranger_id() == "shaoyu" and game.rangers.can_use_skill(), "v0.8.3 R2: default Ranger '少羽' starts active with [V] '天生神力' skill ready")
	game.combat.engage_camp(0)
	var slam_targets := []
	for s_sl in game.combat.troops[0]:
		if is_instance_valid(s_sl) and not s_sl.defeated:
			s_sl.position = game.Layout.on_ground(game.player.position + Vector3(2.2 + float(slam_targets.size()) * 1.4, 0.0, -3.2))
			slam_targets.append(s_sl)
			if slam_targets.size() >= 2:
				break
	await frames(2)
	var slam_ok: bool = game.player.use_ranger_skill()
	await frames(10)
	var both_knocked: bool = slam_targets.size() >= 2 and slam_targets[0].knockdown_left > 1.0 and slam_targets[1].knockdown_left > 1.0 and slam_targets[0].visual_root.rotation.x < -0.5
	verify(slam_ok and both_knocked and game.rangers.skill_cooldown_left > 28.0 and game.player.weapon_view.slam_left > 0.0, "v0.8.3 R2: [V] '天生神力' knocks nearby word soldiers flat for 1.5s, plays viewmodel slam & starts 30s cooldown")
	verify(not game.player.use_ranger_skill(), "v0.8.3 R2: [V] skill cannot be spammed while 30s cooldown is active")
	# Wait out remaining 1.5s knockdown and confirm clean recovery
	for _kf in 110:
		await physics_frame
		if slam_targets[0].knockdown_left <= 0.0:
			break
	verify(slam_targets[0].knockdown_left <= 0.001 and absf(slam_targets[0].visual_root.rotation.x) < 0.05, "v0.8.3 R2: knocked-down word soldiers stand back up cleanly after 1.5s")
	# Verify [V] skill briefly jolts Cave Warden arm-shields open for 1.0s WITHOUT stunning!
	game.rangers.skill_cooldown_left = 0.0
	game.cave_warden.reset()
	game.cave_warden.state = "hunt"
	game.cave_warden.set_guard_arms(true, 4.0)
	game.player.position = game.cave_warden.root_node.position + Vector3(0.0, 0.1, 4.0)
	await frames(2)
	game.player.use_ranger_skill()
	verify(game.cave_warden.state != "stunned" and not game.cave_warden.guard_arms and game.cave_warden.arms_forced_open_left >= 0.85, "v0.8.5: [V] '天生神力' briefly jolts Cave Warden arm-shields open for 1.0s without stunning")

	# v0.9.8 Cave Warden Portrait-Faithful Sculpted Rig + 6-Point Curved Patrol + Blind Bull-Rush Wall-Slam + Acoustic Decoy + Knife Melee!
	game.cave_warden.reset()
	var cw98 = game.cave_warden
	verify(
		cw98.using_v098_model and is_instance_valid(cw98.leg_left_pivot) and is_instance_valid(cw98.leg_right_pivot) and cw98.PATROL_OFFSETS.size() >= 6,
		"v0.9.8: Cave Warden mounts portrait-faithful v098_cave_warden.glb with articulated legs & 6-point curved cavern circuit"
	)
	# Acoustic Bullet Decoy Baiting draws patrol Warden toward rock impact point!
	var decoy_pt: Vector3 = Vector3(cw98._cave_center().x + 2.4, cw98._cave_floor_y(), cw98._cave_center().z + 1.2)
	game.player.position = Vector3(cw98._cave_center().x - 2.6, cw98._cave_floor_y(), cw98._cave_center().z + 8.5)
	var decoy_ok: bool = cw98.on_bullet_impact_sound(decoy_pt)
	verify(decoy_ok and cw98.decoy_lure_count >= 1 and cw98.state == "investigate", "v0.9.8: shooting distant cave rock wall triggers Acoustic Decoy Baiting drawing blind Warden to investigate")
	# Blind Bull-Rush Charge + Wall-Slam Core Expose (dodge sideways -> Warden slams cave rock wall -> 2.6s open core!)
	cw98.reset()
	cw98.root_node.position = Vector3(cw98._cave_center().x + 1.4, cw98._cave_floor_y(), cw98._cave_center().z + 2.0)
	game.player.position = Vector3(cw98._cave_center().x - 2.4, cw98._cave_floor_y(), cw98._cave_center().z + 6.5)
	cw98.state = "hunt"
	cw98.start_blind_rush(cw98.root_node.position + Vector3(4.0, 0.0, 0.0))
	for _rf in 18:
		cw98.update(0.10)
		if cw98.wall_slam_count >= 1:
			break
	verify(cw98.rush_count >= 1 and cw98.wall_slam_count >= 1 and cw98.arms_forced_open_left >= 2.0 and not cw98.guard_arms, "v0.9.8: dodging Blind Bull-Rush slams Warden into cave wall and forces twin stone shields open for 2.6s")
	# Knife melee slash against Cave Warden deducts HP visibly!
	var cw_hp_pre_m: int = cw98.hp
	var cw_mcam := Camera3D.new()
	game.add_child(cw_mcam)
	game.player.position = cw98.root_node.position + Vector3(0.0, 0.0, 2.2)
	cw_mcam.global_position = game.player.position + Vector3(0.0, 1.56, 0.0)
	cw_mcam.look_at(cw98.root_node.global_position + Vector3(0.0, 1.56, 0.0))
	var cw_knife_ok: bool = cw98.melee_strike(cw_mcam)
	cw_mcam.queue_free()
	verify(cw_knife_ok and cw98.hp < cw_hp_pre_m, "v0.9.8: Tactical Knife slash hits Cave Warden and visibly deducts HP (%d->%d)" % [cw_hp_pre_m, cw98.hp])
	game._end_run(false)

	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("COMBAT_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
