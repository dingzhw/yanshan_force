extends Node3D
## 6-Camp × 3-Wave × 5-Soldier Tactical Word Combat Manager (v0.6.1.2)
## - Standby camps patrol at spawn and NEVER auto-chase from afar until player pulls aggro.
## - Active wave (5 bots) pursues player; dead bots NEVER respawn mid-wave.
## - Headshot on correct soldier = 1-shot kill; Word Shield/Torso on correct soldier = 2-shot kill.
## - Hitting a wrong soldier deals 0 damage and stacks +25% enemy attack power for the current wave (up to 2.00x).
## - Clearing all 5 bots spawns the next wave in standby at camp origin (up to 3 waves -> permanent camp clear).

const Soldier = preload("res://scripts/word_soldier.gd")
enum Stage { OFF, FIELD }

const MAX_HEALTH = 100
const SQUAD_SIZE = 5
const CAMP_COVER_COUNT = 6
const NORMAL_MIN_SQUAD = 3
const NORMAL_MAX_SQUAD = 4
const CONF_MIN_SQUAD = 3
const CONF_MAX_SQUAD = 6
const NORMAL_PURSUIT_RADIUS = 44.0
const WAVES_PER_CAMP = 3
const WAVE_REINFORCE_DELAY = 15.0
const WAVE_TRUCE_GRACE = 15.0
const SUPPRESS_HIT_SCALE = 0.40
const WRONG_DAMAGE_STEP = 0.25
const MAX_WRONG_STACKS = 4
const STILL_HIT_CHANCE = 0.78
const FAST_HIT_CHANCE = 0.26
const MAX_EVASION_SPEED = 6.1
const AIRBORNE_HIT_SCALE = 0.55

var game
var stage = Stage.OFF
var field_hits: int = 0
var field_answers: int = 0
var rage_left: float = 0.0
var wave_wrong_stacks: int = 0
var wrong_attempts_on_current: int = 0
var prompt_choice_count := 0
var first_choice_recorded := false
var health: int = MAX_HEALTH
var shield: float = 30.0
var shield_delay: float = 0.0
var zone: int = -1
var attack_lock: float = 0.0
var suppress_lock: float = 0.0
var moving_suppression_shots: int = 0
var miss_left: float = 0.0
var shot_rng := RandomNumberGenerator.new()
var arena: Node3D
var camp_covers = {}
var camp_outer_anchors = {}
var wave_squad_size = {}
var troops = {}
var wave_words = {}
var boss_unit = null
var waves_done = {}
var waves_target = {}
var zone_cleared = {}
var zone_engaged = {}
var zone_respawn_grace = {}
var zone_reinforce_left = {}
var smoke_zones = []
var danger_rings = []
var active_attacker = null
var active_attacker_idle: float = 0.0
var last_attacker_option: int = -1
var wave_had_wrong_shot: bool = false
var last_kill_pos: Vector3 = Vector3.ZERO

func begin():
	stop()
	stage = Stage.FIELD
	field_hits = 0
	field_answers = 0
	rage_left = 0.0
	wave_wrong_stacks = 0
	wrong_attempts_on_current = 0
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	health = MAX_HEALTH
	shield = float(game.rules.max_shield())
	shield_delay = 0.0
	attack_lock = 0.0
	suppress_lock = 0.0
	moving_suppression_shots = 0
	miss_left = 0.0
	boss_unit = null
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	smoke_zones.clear()
	danger_rings.clear()
	shot_rng.randomize()
	_deploy()

func stop():
	stage = Stage.OFF
	zone = -1
	rage_left = 0.0
	wave_wrong_stacks = 0
	wrong_attempts_on_current = 0
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	boss_unit = null
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	smoke_zones.clear()
	danger_rings.clear()
	camp_covers.clear()
	camp_outer_anchors.clear()
	wave_squad_size.clear()
	troops.clear()
	wave_words.clear()
	waves_done.clear()
	waves_target.clear()
	zone_cleared.clear()
	zone_engaged.clear()
	zone_respawn_grace.clear()
	zone_reinforce_left.clear()
	if is_instance_valid(arena):
		arena.hide()
		for body in arena.find_children("*", "CollisionObject3D", true, false):
			body.collision_layer = 0
		arena.queue_free()
		arena = null
	for s_idx in game.stations.size():
		game.stations[s_idx].enable_boards(true)

func in_warmup() -> bool:
	return false

func in_field() -> bool:
	return stage == Stage.FIELD

func is_zone_engaged(z_idx: int) -> bool:
	return zone == z_idx and bool(zone_engaged.get(z_idx, false))

func living_soldiers(z_idx: int) -> Array:
	var alive := []
	for s in troops.get(z_idx, []):
		if is_instance_valid(s) and not s.defeated:
			alive.append(s)
	return alive

func player_in_smoke() -> bool:
	if not is_instance_valid(game.player):
		return false
	for sz in smoke_zones:
		if game.player.position.distance_to(sz.pos) <= float(sz.radius):
			return true
	return false

func heal(hp_gain: int, shield_gain: int):
	health = mini(MAX_HEALTH, health + hp_gain)
	shield = minf(float(game.rules.max_shield()), shield + float(shield_gain))

func zone_info(z_idx: int) -> Dictionary:
	return game.Layout.COMBAT_ZONES[z_idx]

func zone_center(z_idx: int) -> Vector3:
	return game.Layout.on_ground(zone_info(z_idx).at)

func zone_aggro(z_idx: int) -> float:
	return float(zone_info(z_idx).aggro)

func zone_pursuit(z_idx: int) -> float:
	if is_single_attacker_mode():
		return minf(NORMAL_PURSUIT_RADIUS, float(zone_info(z_idx).pursuit))
	return float(zone_info(z_idx).pursuit)

func damage_multiplier() -> float:
	return 1.0 + float(clampi(wave_wrong_stacks, 0, MAX_WRONG_STACKS)) * WRONG_DAMAGE_STEP

func damage_per_shot(soldier = null) -> int:
	var base := 11
	if is_instance_valid(soldier) and soldier.has_method("base_shot_damage"):
		base = soldier.base_shot_damage()
	return maxi(2, roundi(float(base) * damage_multiplier()))

func is_single_attacker_mode() -> bool:
	return not game.rules.is_confidential()

func hit_chance() -> float:
	var motion: Vector3 = game.player.get_real_velocity()
	var speed := Vector2(motion.x, motion.z).length()
	var chance := lerpf(STILL_HIT_CHANCE, FAST_HIT_CHANCE, clampf(speed / MAX_EVASION_SPEED, 0.0, 1.0))
	if not game.player.is_on_floor():
		chance *= AIRBORNE_HIT_SCALE
	if is_instance_valid(game.player) and game.player.has_method("evasion_profile_multiplier"):
		chance *= float(game.player.evasion_profile_multiplier())
	if is_single_attacker_mode():
		chance *= game.Rules.NORMAL_HIT_SCALE
	return chance

func _mark_zone_cleared(z_idx: int):
	if zone_cleared.get(z_idx, false):
		return
	zone_cleared[z_idx] = true
	zone_engaged[z_idx] = false
	if zone == z_idx:
		zone = -1
	wave_wrong_stacks = 0
	game.rules.outposts_cleared += 1
	game.rules.score += game.Rules.OUTPOST_CLEAR_SCORE
	game.player.medkits += 1
	game.player.add_reserve_ammo(game.rules.magazine())
	game.play_sfx("loot_epic", -11)
	game._sync_question()
	game._notice("★ 已彻底肃清【%s】全部 3 波守军！+%d 积分 · 医疗包+1 备弹+%d（已攻克 %d/%d 营地，撤离需2处）" % [
		zone_info(z_idx).title, game.Rules.OUTPOST_CLEAR_SCORE, game.rules.magazine(),
		game.rules.outposts_cleared, game.Layout.COMBAT_ZONES.size()
	], game.MINT)

func _roll_wave_squad_size(_z_idx: int, _wave_idx: int) -> int:
	if game.rules.is_confidential():
		return shot_rng.randi_range(CONF_MIN_SQUAD, CONF_MAX_SQUAD)
	return shot_rng.randi_range(NORMAL_MIN_SQUAD, NORMAL_MAX_SQUAD)

func _squad_archetypes(z_idx: int, wave_idx: int, count: int = 4) -> Array:
	var template: Array
	if z_idx == 0:
		template = [Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE]
	elif z_idx == 1:
		template = [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.ASSAULT_BOT]
	elif z_idx == 2:
		if wave_idx == 0 and not game.rules.boss_defeated:
			template = [Soldier.Archetype.BOSS_WARDEN, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT]
		else:
			template = [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE]
	elif z_idx == 3:
		template = [Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT]
	elif z_idx == 4:
		template = [Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SNIPER_GUARD]
	else:
		template = [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT]
	var out: Array = []
	for i in count:
		out.append(template[i % template.size()])
	return out

func _build_tactical_cover(at: Vector3, index: int, low_front: bool):
	var base_y: float = game.Layout.min_ground_height(at.x, at.z, 0.9) - 0.12
	var uphill_y: float = maxf(at.y, maxf(game.Layout.height(at.x - 1.0, at.z - 1.2), game.Layout.height(at.x + 1.0, at.z - 1.2)))
	# Castellated stepped Jiangnan parapet ('高低错落垛口战术矮垣'):
	# - Center solid merlon (~1.84m, 1.04m wide) blocks shots during full shelter;
	# - Left/right low firing wings (~0.72m) shield legs while keeping 100% of the chest English Word Shield unobstructed!
	var merlon_h: float = maxf(1.84, (uphill_y - base_y) + 1.80)
	if low_front:
		merlon_h = maxf(1.0, at.y - base_y + 0.78)
	var wing_h: float = maxf(0.72, (at.y - base_y) + 0.68)
	var root = Node3D.new()
	root.position = Vector3(at.x, base_y, at.z)
	arena.add_child(root)

	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color("dedad0") if index % 2 == 0 else Color("d4d0c5")
	wall_mat.albedo_texture = load("res://assets/slice/ink_jiangnan/plaster_albedo.jpg")
	wall_mat.normal_enabled = true
	wall_mat.normal_texture = load("res://assets/slice/ink_jiangnan/plaster_normal.jpg")
	wall_mat.normal_scale = 0.60
	wall_mat.roughness = 0.90
	wall_mat.metallic_specular = 0.05

	var center_merlon = game._mesh_box(root, Vector3(0, merlon_h * 0.5, 0), Vector3(1.04, merlon_h, 0.88), Color.WHITE, true)
	center_merlon.material_override = wall_mat
	var low_wings = game._mesh_box(root, Vector3(0, wing_h * 0.5, 0), Vector3(2.08, wing_h, 0.82), Color.WHITE, true)
	low_wings.material_override = wall_mat

	var plinth_mat = StandardMaterial3D.new()
	plinth_mat.albedo_color = Color("9aa3a6")
	plinth_mat.albedo_texture = load("res://assets/slice/ink_jiangnan/bluestone_albedo.jpg")
	plinth_mat.roughness = 0.86
	var plinth = game._mesh_box(root, Vector3(0, 0.22, 0), Vector3(2.14, 0.44, 0.90), Color.WHITE)
	plinth.material_override = plinth_mat

	var cap_mat = StandardMaterial3D.new()
	cap_mat.albedo_color = Color("6e7d8a")
	cap_mat.albedo_texture = load("res://assets/slice/ink_jiangnan/tile_albedo.jpg")
	cap_mat.normal_enabled = true
	cap_mat.normal_texture = load("res://assets/slice/ink_jiangnan/tile_normal.jpg")
	cap_mat.roughness = 0.55
	cap_mat.metallic_specular = 0.15
	var center_cap = game._mesh_box(root, Vector3(0, merlon_h + 0.04, 0), Vector3(1.14, 0.11, 0.98), Color.WHITE)
	center_cap.material_override = cap_mat
	for sx in [-0.78, 0.78]:
		var wing_cap = game._mesh_box(root, Vector3(sx, wing_h + 0.035, 0), Vector3(0.56, 0.08, 0.90), Color.WHITE)
		wing_cap.material_override = cap_mat
	var stripe = game._mesh_box(root, Vector3(0, merlon_h - 0.12, 0), Vector3(1.07, 0.06, 0.91), Color("52463a"))
	stripe.material_override.roughness = 0.82

func _pick_seed_word() -> Dictionary:
	if game.question_queue.is_empty():
		game.question_queue = game._build_weighted_queue()
	if game.rules.answered > 0 and game.rules.answered % 6 == 0 and not game.wrong_words.is_empty():
		return game.wrong_words.pick_random()
	return game.question_queue.pop_back()

func _build_wave_words(count: int) -> Array:
	var seed_word := _pick_seed_word()
	var words_list: Array = game._pick_smart_distractors(seed_word, count)
	while words_list.size() < count:
		var extra: Dictionary = game.words[shot_rng.randi_range(0, game.words.size() - 1)]
		var dup := false
		for w in words_list:
			if str(w.english).to_lower() == str(extra.english).to_lower():
				dup = true
				break
		if not dup:
			words_list.append(extra)
	words_list.shuffle()
	return words_list

func _spawn_camp_wave(z_idx: int):
	if troops.has(z_idx):
		for old_s in troops[z_idx]:
			if is_instance_valid(old_s):
				old_s.collision_layer = 0
				old_s.queue_free()
	var wave_idx := int(waves_done.get(z_idx, 0))
	var sq_count := _roll_wave_squad_size(z_idx, wave_idx)
	wave_squad_size[z_idx] = sq_count
	var archetypes := _squad_archetypes(z_idx, wave_idx, sq_count)
	var words_n := _build_wave_words(sq_count)
	wave_words[z_idx] = words_n
	var covers: Array = camp_covers[z_idx]
	# Spread squad evenly across the 6 wide-spaced camp cover slots (leaving unoccupied covers + clear lanes!)
	var cover_order := [1, 4, 2, 3, 0, 5]
	var soldiers := []
	for i in sq_count:
		var c_slot: int = int(cover_order[i % cover_order.size()]) % covers.size()
		var soldier = Soldier.new()
		arena.add_child(soldier)
		soldier.setup(self, z_idx, i, covers[c_slot], archetypes[i])
		soldier.claimed_cover_idx = c_slot
		soldier.assigned_word = words_n[i]
		soldier.show_word("", false)
		soldiers.append(soldier)
		if archetypes[i] == Soldier.Archetype.BOSS_WARDEN:
			boss_unit = soldier
	troops[z_idx] = soldiers
	zone_engaged[z_idx] = false

func _deploy():
	game._leave_station()
	game.next_question_left = 0.0
	arena = Node3D.new()
	add_child(arena)
	for s_idx in game.stations.size():
		game.stations[s_idx].enable_boards(s_idx == 0)

	# 6 wide-spaced staggered tactical cover offsets (~3.3m open lanes so front covers never occlude rear covers!)
	var cover_offsets := [
		Vector2(-8.0, -5.8),
		Vector2(-4.8, -7.4),
		Vector2(-1.6, -6.2),
		Vector2(1.6, -7.5),
		Vector2(4.8, -6.3),
		Vector2(8.0, -5.9),
	]
	for z_idx in game.Layout.COMBAT_ZONES.size():
		var info = zone_info(z_idx)
		var center := zone_center(z_idx)
		waves_done[z_idx] = 0
		waves_target[z_idx] = int(info.get("waves", WAVES_PER_CAMP))
		zone_cleared[z_idx] = false
		zone_engaged[z_idx] = false
		zone_respawn_grace[z_idx] = 0.0
		zone_reinforce_left[z_idx] = 0.0
		var covers := []
		for i in CAMP_COVER_COUNT:
			var off2: Vector2 = cover_offsets[i]
			var barrier: Vector3 = game.Layout.on_ground(center + Vector3(off2.x, 0.0, off2.y))
			_build_tactical_cover(barrier, i, z_idx == 0 and i > 0 and i < CAMP_COVER_COUNT - 1)
			covers.append(barrier)
		camp_covers[z_idx] = covers
		# Collect nearby natural tree trunks (12m..30m from camp) as out-of-camp small-pursuit cover anchors!
		var outer_pts := []
		if is_instance_valid(game.landscape) and "tree_trunks" in game.landscape:
			for tp in game.landscape.tree_trunks:
				var d_camp := Vector2(tp.x - center.x, tp.z - center.z).length()
				if d_camp >= 11.5 and d_camp <= 29.5:
					outer_pts.append(game.Layout.on_ground(tp))
					if outer_pts.size() >= 8:
						break
		camp_outer_anchors[z_idx] = outer_pts
		_spawn_camp_wave(z_idx)

	game.player.ammo = game.rules.magazine()
	game.player.reserve_ammo = game.rules.starter_reserve_ammo()
	game.player.reload_left = 0.0
	game._next_question()

func _select_next_wave_prompt(z_idx: int) -> bool:
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		return false
	var candidates := alive
	if z_idx == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated and boss_unit.exposed_left > 0.0 and alive.size() > 1:
		var non_boss := []
		for s in alive:
			if s != boss_unit:
				non_boss.append(s)
		if not non_boss.is_empty():
			candidates = non_boss
	var chosen = candidates[shot_rng.randi_range(0, candidates.size() - 1)]
	game.choices = wave_words[z_idx]
	game.answer_index = chosen.option
	game.question = chosen.assigned_word
	wrong_attempts_on_current = 0
	prompt_choice_count = candidates.size()
	first_choice_recorded = false
	game.question_help_used = false
	game.listening_mode = (game.tts_voice_id != "" and game.rules.answered >= 4 and game.rules.answered % 5 == 0)
	game.rules.open_question()
	game.next_question_left = 0.0
	show_question()
	if game.listening_mode and not game.paused:
		game.speak_english(game.question.english)
	return true

func spawn_pending_wave_now(z_idx: int):
	if float(zone_reinforce_left.get(z_idx, 0.0)) > 0.0 and not zone_cleared.get(z_idx, false):
		zone_reinforce_left[z_idx] = 0.0
		_spawn_camp_wave(z_idx)
		zone_respawn_grace[z_idx] = WAVE_TRUCE_GRACE

func engage_camp(z_idx: int):
	if z_idx < 0 or z_idx >= game.Layout.COMBAT_ZONES.size() or zone_cleared.get(z_idx, false):
		return
	if float(zone_reinforce_left.get(z_idx, 0.0)) > 0.0:
		spawn_pending_wave_now(z_idx)
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		return
	if zone >= 0 and zone != z_idx:
		disengage_active_camp(false)
	zone = z_idx
	zone_engaged[z_idx] = true
	zone_respawn_grace[z_idx] = 0.0
	wave_wrong_stacks = 0
	rage_left = 0.0
	wrong_attempts_on_current = 0
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	attack_lock = 0.25 if game.rules.is_confidential() else 0.55
	game._leave_station()
	game.next_question_left = 0.0
	for s in alive:
		if s.action == Soldier.Action.PATROL:
			s.begin_tactical_engagement()
	if is_single_attacker_mode():
		active_attacker = _pick_next_attacker(z_idx)
	_select_next_wave_prompt(z_idx)
	var z_title: String = zone_info(z_idx).title
	var w_cur: int = int(waves_done.get(z_idx, 0)) + 1
	var w_max: int = int(waves_target.get(z_idx, WAVES_PER_CAMP))
	var pace_tag: String = "机密机动包抄" if game.rules.is_confidential() else "普通谨慎掩体战"
	if z_idx == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
		game._notice("⚠ 惊动【%s】（第 %d/%d 波 · %d兵 · %s）：铁甲词尊登场！爆头1枪或词盾2枪破防！" % [z_title, w_cur, w_max, alive.size(), pace_tag], Color("ffd15c"))
		game.play_sfx("boss_phase", -11)
	else:
		game._notice("⚔ 触发【%s】第 %d/%d 波交火（%d兵 · %s）！词兵依托掩体周旋，抓闪身时机打头1枪/词盾2枪！" % [z_title, w_cur, w_max, alive.size(), pace_tag], game.GOLD)

func disengage_active_camp(announce: bool = true):
	if zone < 0:
		return
	var old_z := zone
	zone_engaged[old_z] = false
	zone = -1
	wave_wrong_stacks = 0
	rage_left = 0.0
	wrong_attempts_on_current = 0
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	for s in troops.get(old_z, []):
		if is_instance_valid(s) and not s.defeated:
			s.action = Soldier.Action.PATROL
			s.laser_beam.hide()
			s.show_word("", false)
	game._sync_question()
	if announce:
		game._notice("已脱离【%s】追击范围，剩余词兵返回出生地待命。" % zone_info(old_z).title, game.GOLD)

func _camp_pull_distance(z_idx: int) -> float:
	var p: Vector3 = game.player.position
	var c: Vector3 = zone_center(z_idx)
	var best := Vector2(p.x - c.x, p.z - c.z).length() + absf(p.y - c.y) * 0.22
	for s in troops.get(z_idx, []):
		if is_instance_valid(s) and not s.defeated:
			var sd := Vector2(p.x - s.position.x, p.z - s.position.z).length() + absf(p.y - s.position.y) * 0.22
			best = minf(best, sd + 2.2)
	return best

func update(delta: float):
	if not in_field():
		return
	attack_lock = maxf(0.0, attack_lock - delta)
	suppress_lock = maxf(0.0, suppress_lock - delta)
	miss_left = maxf(0.0, miss_left - delta)

	for z_i in zone_respawn_grace.keys():
		var g_left := float(zone_respawn_grace[z_i])
		if g_left > 0.0:
			var prev_g := int(ceilf(g_left))
			# Keep full truce countdown while player loots/reloads near camp; only reset once player has fully left (> aggro + 10m)
			if _camp_pull_distance(int(z_i)) > zone_aggro(int(z_i)) + 10.0:
				zone_respawn_grace[z_i] = 0.0
				if zone < 0:
					show_question()
			else:
				var next_g := maxf(0.0, g_left - delta)
				zone_respawn_grace[z_i] = next_g
				if zone < 0 and int(ceilf(next_g)) != prev_g:
					show_question()

	for z_i in zone_reinforce_left.keys():
		var r_left := float(zone_reinforce_left[z_i])
		if r_left > 0.0 and not zone_cleared.get(int(z_i), false):
			var prev_sec := int(ceilf(r_left))
			r_left = maxf(0.0, r_left - delta)
			zone_reinforce_left[z_i] = r_left
			if r_left <= 0.0:
				_spawn_camp_wave(int(z_i))
				zone_respawn_grace[int(z_i)] = WAVE_TRUCE_GRACE
				game._sync_question()
				var zi := int(z_i)
				var w_next := int(waves_done.get(zi, 0)) + 1
				var w_tot := int(waves_target.get(zi, WAVES_PER_CAMP))
				if _camp_pull_distance(zi) <= zone_aggro(zi) + 8.0:
					game._notice("⚑【%s】第 %d/%d 波增援已在掩体就位（15秒休整内不主动开火，搜完物资可离开或开枪迎战）！" % [
						zone_info(zi).title, w_next, w_tot
					], game.GOLD)
			elif zone < 0 and int(ceilf(r_left)) != prev_sec:
				show_question()

	for i in range(smoke_zones.size() - 1, -1, -1):
		var sz = smoke_zones[i]
		sz.left -= delta
		if sz.left <= 0:
			if is_instance_valid(sz.node):
				sz.node.queue_free()
			smoke_zones.remove_at(i)
		elif sz.left < 1.8 and is_instance_valid(sz.node):
			sz.node.scale = Vector3.ONE * clampf(sz.left / 1.8, 0.15, 1.0)

	for i in range(danger_rings.size() - 1, -1, -1):
		var dr = danger_rings[i]
		dr.left -= delta
		if is_instance_valid(dr.inner):
			var frac := 1.0 - clampf(dr.left / float(dr.duration), 0.0, 1.0)
			dr.inner.scale = Vector3(frac, 1.0, frac)
		if dr.left <= 0:
			if is_instance_valid(game.player) and game.player.position.distance_to(dr.pos) <= float(dr.radius):
				apply_player_damage(int(dr.damage))
			else:
				game._notice("★ 成功闪避首领重炮轰炸！", game.MINT)
			if is_instance_valid(dr.node):
				dr.node.queue_free()
			danger_rings.remove_at(i)

	if is_instance_valid(game.exploration) and game.exploration.safe():
		if zone >= 0:
			disengage_active_camp(false)
		return

	if zone >= 0 and is_zone_engaged(zone):
		if living_soldiers(zone).is_empty():
			_complete_current_wave(zone)
			return
		if is_single_attacker_mode():
			if not is_instance_valid(active_attacker) or active_attacker.defeated or active_attacker.zone != zone or active_attacker.stun_left > 0.0:
				active_attacker = null
				active_attacker_idle = 0.0
			if active_attacker == null:
				if attack_lock <= 0.0:
					active_attacker = _pick_next_attacker(zone)
					active_attacker_idle = 0.0
			elif active_attacker.action == Soldier.Action.AIM:
				active_attacker_idle = 0.0
			else:
				active_attacker_idle += delta
				if active_attacker_idle > 2.2:
					last_attacker_option = active_attacker.option
					active_attacker = _pick_next_attacker(zone)
					active_attacker_idle = 0.0
		var c := zone_center(zone)
		var d_home := Vector2(game.player.position.x - c.x, game.player.position.z - c.z).length()
		if d_home > zone_pursuit(zone):
			disengage_active_camp(true)
		return

	# Standby aggro detection: player must walk into an un-cleared camp's spawn area to pull aggro!
	var pull_idx := -1
	var nearest := INF
	for z_idx in game.Layout.COMBAT_ZONES.size():
		if zone_cleared.get(z_idx, false):
			continue
		if float(zone_reinforce_left.get(z_idx, 0.0)) > 0.0:
			continue
		if float(zone_respawn_grace.get(z_idx, 0.0)) > 0.0:
			continue
		if living_soldiers(z_idx).is_empty():
			continue
		var d := _camp_pull_distance(z_idx)
		if d <= zone_aggro(z_idx) and d < nearest:
			nearest = d
			pull_idx = z_idx
	if pull_idx >= 0:
		engage_camp(pull_idx)

func show_question():
	var fighting := zone >= 0 and is_zone_engaged(zone)
	for station in game.stations:
		station.terminal_label.visible = not fighting
	if not fighting:
		if game.active_station == 0:
			return
		var rest_hint := "清完追兵后留足休整间隔再刷下波  |  "
		if is_instance_valid(game.player):
			for z_i in game.Layout.COMBAT_ZONES.size():
				if zone_cleared.get(z_i, false):
					continue
				var r_l := float(zone_reinforce_left.get(z_i, 0.0))
				var g_l := float(zone_respawn_grace.get(z_i, 0.0))
				if (r_l > 0.0 or g_l > 0.0) and _camp_pull_distance(z_i) <= zone_aggro(z_i) + 8.0:
					if r_l > 0.0:
						rest_hint = "⏳【%s】下波增援 %.0f 秒后抵达（安心搜刮战利品）  |  " % [zone_info(z_i).title, ceilf(r_l)]
					else:
						rest_hint = "🕊【%s】增援休整 %.0f 秒不主动追击（可离开或开枪迎战）  |  " % [zone_info(z_i).title, ceilf(g_l)]
					break
		game.question_label.text = "前往敌军营地触发波次仇恨（每营 3 波）"
		game.unit_label.text = "%s已攻克 %d/6 营（需≥2） · 统领密钥 %d/1" % [
			rest_hint, game.rules.outposts_cleared, 1 if game.rules.boss_defeated else 0
		]
		return

	var words_5: Array = wave_words.get(zone, [])
	var alive_count := 0
	for slot_i in troops[zone].size():
		var soldier = troops[zone][slot_i]
		if not is_instance_valid(soldier) or soldier.defeated:
			continue
		alive_count += 1
		var w_text := str(soldier.assigned_word.get("english", "")) if not soldier.assigned_word.is_empty() else (str(words_5[slot_i].english) if slot_i < words_5.size() else "")
		soldier.show_word(w_text, false)

	if game.listening_mode and game.rules.question_open:
		game.question_label.text = "🔊 电台截获英文语音 · 按 [X] 重播读音"
	else:
		game.question_label.text = str(game.question.get("chinese", ""))

	var z_title: String = zone_info(zone).title
	var w_cur: int = int(waves_done.get(zone, 0)) + 1
	var w_max: int = int(waves_target.get(zone, WAVES_PER_CAMP))
	var mode_tag := "机密机动" if game.rules.is_confidential() else "普通谨慎"
	var atk_tag := (" | ⚠敌攻×%.2f" % damage_multiplier()) if wave_wrong_stacks > 0 else ""
	var boss_suffix := ""
	if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
		boss_suffix = " | ★统领 %d/450%s" % [boss_unit.hp, " (红核暴露!)" if boss_unit.exposed_left > 0 else ""]
	var wave_total: int = int(wave_squad_size.get(zone, troops[zone].size()))
	game.unit_label.text = "%s · %s · 第 %d/%d 波 · 守军 %d/%d%s%s  |  [X]读音" % [
		z_title, mode_tag, w_cur, w_max, alive_count, wave_total, atk_tag, boss_suffix
	]

func _resolve_soldier_node(collider):
	var cur := collider as Node
	while is_instance_valid(cur):
		if cur is Soldier:
			return cur
		cur = cur.get_parent()
	return null

func _record_first_choice(is_correct: bool):
	if first_choice_recorded or game.question.is_empty():
		return
	first_choice_recorded = true
	game.rules.learning.record_recognition(str(game.question.id), is_correct, prompt_choice_count, game.question_help_used)
	if (not is_correct or game.question_help_used) and game.question not in game.wrong_words:
		game.wrong_words.append(game.question)

func _apply_wrong_target_penalty(soldier):
	# Wrong word soldier takes ZERO HP and ZERO shield damage, and buffs remaining wave attack power!
	soldier.on_wrong_hit_flash()
	wave_had_wrong_shot = true
	wave_wrong_stacks = mini(MAX_WRONG_STACKS, wave_wrong_stacks + 1)
	rage_left = 7.0
	wrong_attempts_on_current += 1
	field_answers += 1
	game.rules.answered += 1
	game.rules.streak = 0
	_record_first_choice(false)

	game.hitmarker_left = 0.24
	game.hitmarker_label.text = "✕"
	game.hitmarker_label.add_theme_color_override("font_color", Color("ff6b6b"))
	game.hitmarker_label.show()
	game.play_sfx("hit_wrong", -10)
	game.speak_english(str(game.question.get("english", "")))
	game.screen_flash.color = Color(1.0, 0.32, 0.18, 0.11)

	var hint_str := ""
	if wrong_attempts_on_current >= 2:
		var en_word := str(game.question.get("english", "")).strip_edges()
		if en_word.length() > 0:
			hint_str = " · 提示首字母「%s...」" % en_word.substr(0, mini(2, en_word.length()))
	game._notice("✕ 打错词兵（敌方无伤）！本波剩余敌军攻击力 +25%%（当前 ×%.2f）%s" % [damage_multiplier(), hint_str], Color("ff9d7d"))
	show_question()

func _score_wave_correct(soldier, is_crit: bool, prefix: String, grant_bullet_ammo: bool = true):
	if is_instance_valid(soldier):
		last_kill_pos = soldier.global_position
	field_answers += 1
	field_hits += 1
	rage_left = 0.0
	var prev_score: int = game.rules.score
	if not game.rules.question_open:
		game.rules.open_question()
	var w_entry: Dictionary = soldier.assigned_word if not soldier.assigned_word.is_empty() else game.question
	game.rules.answer(true)
	var gained: int = game.rules.score - prev_score
	if grant_bullet_ammo:
		game.player.add_reserve_ammo(5)

	game.show_hitmarker(is_crit)
	game.play_sfx("hit_correct", -10)
	game.speak_english(str(w_entry.get("english", "")))
	game.screen_flash.color = Color(0.3, 1.0, 0.65, 0.08)

	var streak_tag := (" · 🔥%d连击" % game.rules.streak) if game.rules.streak >= 3 else ""
	if game.rules.streak >= 3:
		heal(0, 6)
		streak_tag += "(+6盾)"
	if game.rules.correct % 3 == 0:
		var chip_rarity := 3 if game.rules.streak >= 4 else 2
		game.rules.add_loot("战术知识芯片", 46 + maxi(0, game.rules.level() - 1) * 4, chip_rarity)
	game._notice("%s！+%d 分%s · %s（%s）" % [
		prefix, gained, streak_tag, str(w_entry.get("english", "")), str(w_entry.get("chinese", ""))
	], game.MINT)

func _rotate_boss_word_and_prompt(boss):
	var fresh := _pick_seed_word()
	for _try in 8:
		var clash := false
		for w in wave_words.get(2, []):
			if str(w.english).to_lower() == str(fresh.english).to_lower():
				clash = true
				break
		if not clash:
			break
		fresh = _pick_seed_word()
	if wave_words.has(2) and boss.option < wave_words[2].size():
		wave_words[2][boss.option] = fresh
	boss.assigned_word = fresh
	boss.shield_layers = boss.max_shield_layers
	_select_next_wave_prompt(2)

func _complete_current_wave(z_idx: int):
	var flawless_wave: bool = not wave_had_wrong_shot
	var drop_origin: Vector3 = last_kill_pos if last_kill_pos != Vector3.ZERO else zone_center(z_idx)
	wave_wrong_stacks = 0
	rage_left = 0.0
	wrong_attempts_on_current = 0
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	zone_engaged[z_idx] = false
	if zone == z_idx:
		zone = -1
	if is_instance_valid(game.world_loot):
		game.world_loot.spawn_squad_drop(drop_origin, zone_info(z_idx).title, flawless_wave, z_idx == 2)
	waves_done[z_idx] = int(waves_done.get(z_idx, 0)) + 1
	var done_now: int = waves_done[z_idx]
	var total_w: int = int(waves_target.get(z_idx, WAVES_PER_CAMP))
	if done_now >= total_w:
		_mark_zone_cleared(z_idx)
		return
	# Reward clearing a wave and schedule an 8.5s empty-camp reinforcement interval + 14s arrival truce!
	if troops.has(z_idx):
		for old_s in troops[z_idx]:
			if is_instance_valid(old_s):
				old_s.collision_layer = 0
				old_s.queue_free()
		troops[z_idx] = []
	game.rules.score += 10
	game.player.add_reserve_ammo(6)
	zone_reinforce_left[z_idx] = WAVE_REINFORCE_DELAY
	zone_respawn_grace[z_idx] = WAVE_TRUCE_GRACE
	game._sync_question()
	var drop_tag := "【精英无瑕战利品箱】" if flawless_wave else "【词兵战术掉落包】"
	game._notice("★【%s】第 %d/%d 波已全歼！掉落%s，下波 %.0f 秒后就位且休整免战！" % [
		zone_info(z_idx).title, done_now, total_w, drop_tag, WAVE_REINFORCE_DELAY
	], game.MINT)

func _advance_wave_after_kill(z_idx: int):
	if living_soldiers(z_idx).is_empty():
		_complete_current_wave(z_idx)
	else:
		_select_next_wave_prompt(z_idx)

func hit(collider) -> bool:
	return hit_bullet(collider, "", Vector3.ZERO)

func hit_bullet(collider, muzzle_id: String = "", _hit_pos: Vector3 = Vector3.ZERO) -> bool:
	var soldier = _resolve_soldier_node(collider)
	if not (soldier is Soldier) or soldier.defeated or zone_cleared.get(soldier.zone, false):
		return false
	if zone < 0 or not is_zone_engaged(zone):
		engage_camp(soldier.zone)
	elif soldier.zone != zone:
		game._notice("⚠ 请先肃清当前追击你的【%s】词兵编队！" % zone_info(zone).title, game.GOLD)
		return true

	if muzzle_id != "suppressor":
		for other in living_soldiers(zone):
			if other.action == Soldier.Action.PATROL:
				other.begin_tactical_engagement()

	# Bonus weakpoint: Exposed Boss Reactor Core always takes 42 crit damage while glowing!
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN and collider == soldier.core_area and soldier.exposed_left > 0.0:
		game.show_hitmarker(true)
		game.play_sfx("hit_correct", -11)
		var core_killed: bool = soldier.apply_damage(42, false, true)
		if core_killed:
			_on_boss_defeated(soldier)
			_advance_wave_after_kill(zone)
		else:
			game._notice("★ 命中首领暴露红核！暴击 -42 HP（剩余 %d/450 HP）" % soldier.hp, Color("ffd15c"))
			show_question()
		return true

	# Wrong soldier hit -> 0 damage + +25% enemy wave attack power stack!
	if soldier.option != game.answer_index:
		_apply_wrong_target_penalty(soldier)
		return true

	_record_first_choice(true)
	# Correct soldier hit -> 1-shot Headshot OR 2-shot Word Shield/Torso!
	var is_head: bool = (collider == soldier.head_area) or (collider is Object and str(collider.get_meta("hit_zone", "")) == "head")
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		if is_head:
			var b_dead: bool = soldier.apply_damage(165, true, true)
			_score_wave_correct(soldier, true, "🎯 首领核心爆头破防")
			if b_dead:
				_on_boss_defeated(soldier)
				_advance_wave_after_kill(zone)
			else:
				_rotate_boss_word_and_prompt(soldier)
		elif soldier.shield_layers > 1 and soldier.exposed_left <= 0.0:
			soldier.crack_shield_once()
			game.show_hitmarker(false)
			game.play_sfx("hit_correct", -13)
			game._notice("⚡ 统领词盾裂开 (1/2)！再补 1 枪击碎护盾暴露红核（打头部可1枪破盾）！", Color("ffe082"))
			show_question()
		else:
			var b_dead2: bool = soldier.apply_damage(165, true, false)
			_score_wave_correct(soldier, false, "✦ 统领重甲词盾击碎")
			if b_dead2:
				_on_boss_defeated(soldier)
				_advance_wave_after_kill(zone)
			else:
				_rotate_boss_word_and_prompt(soldier)
		return true

	# Normal pursuing word soldier (Assault / Drone / Sniper)
	if is_head:
		soldier.apply_damage(999, true, true)
		_score_wave_correct(soldier, true, "🎯 精准爆头一击必杀")
		_apply_boss_guard_shockwave()
		_advance_wave_after_kill(zone)
	elif soldier.shield_layers > 1:
		soldier.crack_shield_once()
		game.show_hitmarker(false)
		game.play_sfx("hit_correct", -13)
		game._notice("⚡ 命中正确词盾 (1/2)！单词未消散，再补 1 枪击毙（瞄准头部可 1 枪秒杀）！", Color("ffe082"))
		show_question()
	else:
		soldier.apply_damage(999, true, false)
		_score_wave_correct(soldier, false, "✦ 二段破盾击毙")
		_apply_boss_guard_shockwave()
		_advance_wave_after_kill(zone)
	return true

func _apply_boss_guard_shockwave():
	if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
		var b_killed: bool = boss_unit.apply_damage(75, true, false)
		if b_killed:
			_on_boss_defeated(boss_unit)

func melee_strike(camera: Camera3D) -> bool:
	if not in_field():
		return false
	var cam_pos := camera.global_position
	var cam_fwd := (-camera.global_transform.basis.z).normalized()
	var best_soldier = null
	var best_dist := 3.45
	var search_zones: Array = [zone] if (zone >= 0 and is_zone_engaged(zone)) else troops.keys()
	for z_k in search_zones:
		if zone_cleared.get(z_k, false):
			continue
		for s in troops.get(z_k, []):
			if not is_instance_valid(s) or s.defeated:
				continue
			var target_center: Vector3 = s.global_position + Vector3(0, 1.35 if s.archetype == Soldier.Archetype.BOSS_WARDEN else 1.15, 0)
			var delta := target_center - cam_pos
			var d := delta.length()
			if d > 3.45:
				continue
			if cam_fwd.dot(delta.normalized()) < 0.42:
				continue
			if d < best_dist:
				best_dist = d
				best_soldier = s
	if best_soldier == null:
		return false
	if zone < 0 or not is_zone_engaged(zone):
		engage_camp(best_soldier.zone)

	if best_soldier.archetype == Soldier.Archetype.BOSS_WARDEN and best_soldier.exposed_left > 0.0 and best_soldier.option != game.answer_index:
		game.play_sfx("knife_hit", -8)
		game.show_hitmarker(true)
		var b_kill: bool = best_soldier.apply_damage(65, false, true)
		if b_kill:
			_on_boss_defeated(best_soldier)
			_advance_wave_after_kill(zone)
		return true

	if best_soldier.option != game.answer_index:
		game.play_sfx("knife_hit", -10)
		_apply_wrong_target_penalty(best_soldier)
		return true

	_record_first_choice(true)
	var mag_gain: int = game.rules.magazine()
	game.play_sfx("knife_hit", -8)
	game.player.add_reserve_ammo(mag_gain)
	if best_soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		var b_dead: bool = best_soldier.apply_damage(165, true, true)
		_score_wave_correct(best_soldier, true, "🗡 匕首破甲斩击（备弹+%d）" % mag_gain, false)
		if b_dead:
			_on_boss_defeated(best_soldier)
			_advance_wave_after_kill(zone)
		else:
			_rotate_boss_word_and_prompt(best_soldier)
	else:
		best_soldier.apply_damage(999, true, true)
		_score_wave_correct(best_soldier, true, "🗡 匕首致命处决（备弹+%d）" % mag_gain, false)
		_apply_boss_guard_shockwave()
		_advance_wave_after_kill(zone)
	return true

func record_field(_correct: bool):
	pass

func hit_feedback(_index: int, _correct: bool):
	pass

func on_boss_phase_shift(_boss, next_phase: int):
	game.play_sfx("boss_phase", -9)
	game._notice("★ 铁甲词尊 进入第 %d 阶段！胸口红核暴露，小心重炮轰炸红圈！" % (4 - next_phase), Color("ffd15c"))
	if is_instance_valid(game.player):
		spawn_danger_ring(game.player.position, 3.4, 24)

func _on_boss_defeated(_boss):
	if game.rules.boss_defeated:
		return
	game.rules.boss_defeated = true
	game.rules.score += game.Rules.BOSS_DEFEAT_SCORE
	game.player.add_reserve_ammo(game.rules.magazine())
	var core_val := roundi(380.0 * (game.Rules.CONFIDENTIAL_VALUE_MULT if game.rules.is_confidential() else 1.0))
	var core_item := {"title": "烟山统领黄金核心", "value": core_val, "rarity": 5}
	if not game.rules.add_loot(core_item.title, core_item.value, core_item.rarity):
		game.rules.swap_lowest_loot(core_item)
	var bp_unlocked := ""
	for bp in game.Rules.BOSS_BLUEPRINTS:
		if not (bp in game.rules.profile.owned):
			if game.rules.unlock_blueprint(bp):
				bp_unlocked = game.Rules.ITEMS[bp].title.split(" · ")[0]
				if is_instance_valid(game.player.weapon_view):
					game.player.weapon_view.refresh_loadout()
				break
	var bp_msg := (" + 研发图纸【%s】" % bp_unlocked) if bp_unlocked != "" else ""
	game.play_sfx("loot_epic", -7)
	game._notice("🏆 击败【铁甲词尊 · 烟山统领】！夺得 B区撤离密钥 + 黄金核心(%d)%s！" % [core_val, bp_msg], Color("ffd15c"))

func deploy_smoke_emp(center: Vector3):
	if not is_instance_valid(arena):
		return
	var root = Node3D.new()
	var gpos: Vector3 = game.Layout.on_ground(center)
	root.position = gpos
	arena.add_child(root)
	var emp_ring = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 6.2
	cyl.bottom_radius = 6.2
	cyl.height = 0.08
	emp_ring.mesh = cyl
	emp_ring.position.y = 0.14
	var rmat = StandardMaterial3D.new()
	rmat.albedo_color = Color(0.25, 0.90, 1.0, 0.65)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emp_ring.material_override = rmat
	root.add_child(emp_ring)
	var tw = emp_ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(emp_ring, "scale", Vector3(1.35, 1.0, 1.35), 0.45)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 0.48)
	tw.chain().tween_callback(emp_ring.queue_free)

	var smoke_mat = StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.72, 0.80, 0.82, 0.28)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for i in 7:
		var puffs = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 1.72 + float(i % 3) * 0.42
		sm.height = 2.4 + float(i % 2) * 0.45
		sm.radial_segments = 12
		sm.rings = 6
		puffs.mesh = sm
		var ang := TAU * float(i) / 6.0 if i < 6 else 0.0
		var ring_r := 1.65 if i < 6 else 0.0
		puffs.position = Vector3(cos(ang) * ring_r, 1.05 + float(i % 3) * 0.30, sin(ang) * ring_r)
		puffs.scale = Vector3(1.15, 0.78, 1.15)
		puffs.material_override = smoke_mat
		root.add_child(puffs)

	smoke_zones.append({"pos": gpos, "left": 8.0, "radius": 5.5, "node": root})
	var stunned := 0
	for z_list in troops.values():
		for s in z_list:
			if is_instance_valid(s) and not s.defeated and s.position.distance_to(gpos) <= 9.0:
				s.stun(3.8)
				stunned += 1
	game.play_sfx("smoke_emp", -9)
	game._notice("投掷烟雾/EMP 手雷！致盲麻痹 %d 名敌军 3.8 秒，烟雾掩护中！" % stunned, Color("7ceeff"))

func spawn_danger_ring(target_pos: Vector3, radius: float = 3.4, dmg_val: int = 24):
	if not is_instance_valid(arena):
		return
	var gpos: Vector3 = game.Layout.on_ground(target_pos)
	var root = Node3D.new()
	root.position = gpos + Vector3(0, 0.12, 0)
	arena.add_child(root)

	var outer = MeshInstance3D.new()
	var om = CylinderMesh.new()
	om.top_radius = radius
	om.bottom_radius = radius
	om.height = 0.08
	outer.mesh = om
	var omat = StandardMaterial3D.new()
	omat.albedo_color = Color(0.95, 0.18, 0.14, 0.32)
	omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer.material_override = omat
	root.add_child(outer)

	var inner = MeshInstance3D.new()
	var im = CylinderMesh.new()
	im.top_radius = radius
	im.bottom_radius = radius
	im.height = 0.10
	inner.mesh = im
	inner.scale = Vector3(0.05, 1.0, 0.05)
	var imat = StandardMaterial3D.new()
	imat.albedo_color = Color(1.0, 0.32, 0.18, 0.56)
	imat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	imat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner.material_override = imat
	root.add_child(inner)

	danger_rings.append({"pos": gpos, "radius": radius, "damage": dmg_val, "duration": 1.45, "left": 1.45, "node": root, "inner": inner})
	game.play_sfx("warning_lock", -10)
	game._notice("⚠ 警告：首领蓄力轰炸红圈锁定！迅速冲刺跑出红圈！", Color("ff8080"))

func blocked(from: Vector3, to: Vector3) -> bool:
	var ray = PhysicsRayQueryParameters3D.create(from, to, 1)
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func player_aim_point() -> Vector3:
	if is_instance_valid(game.player) and game.player.has_method("get_aim_target_position"):
		return game.player.get_aim_target_position()
	return game.player.position + Vector3.UP * 1.26

func clear_shot(at: Vector3) -> bool:
	if player_in_smoke():
		return false
	var target_pt := player_aim_point()
	if not blocked(at + Vector3.UP * 1.40, target_pt):
		return true
	if absf(target_pt.y - (at.y + 1.40)) > 1.85:
		return not blocked(at + Vector3.UP * 1.68, target_pt + Vector3.UP * 0.10)
	return false

func _pick_next_attacker(z_idx: int):
	if not troops.has(z_idx):
		return null
	var list: Array = troops[z_idx]
	var clear_candidate = null
	var fallback_candidate = null
	for step in list.size():
		var idx := (last_attacker_option + 1 + step) % list.size()
		var s = list[idx]
		if not is_instance_valid(s) or s.defeated or s.stun_left > 0.0:
			continue
		if fallback_candidate == null:
			fallback_candidate = s
		var horiz_d := Vector2(s.position.x - game.player.position.x, s.position.z - game.player.position.z).length()
		if horiz_d < s.attack_range() + 1.5 and clear_shot(s.position):
			clear_candidate = s
			break
	return clear_candidate if clear_candidate != null else fallback_candidate

func is_designated_attacker(soldier) -> bool:
	if not is_single_attacker_mode():
		return true
	if not is_instance_valid(soldier) or soldier.defeated or soldier.zone != zone:
		return false
	if not is_instance_valid(active_attacker) or active_attacker.defeated or active_attacker.zone != zone or active_attacker.stun_left > 0.0:
		if attack_lock <= 0.0:
			active_attacker = soldier
			active_attacker_idle = 0.0
	return active_attacker == soldier

func on_soldier_attack_finished(soldier):
	if is_single_attacker_mode() and active_attacker == soldier:
		last_attacker_option = soldier.option
		active_attacker = null
		active_attacker_idle = 0.0
		attack_lock = maxf(attack_lock, 1.55 if wave_wrong_stacks <= 0 else 1.15)

func reserve_attack(soldier = null) -> bool:
	if attack_lock > 0:
		return false
	if is_single_attacker_mode():
		if soldier != null and not is_designated_attacker(soldier):
			return false
		if active_threat_count() >= 1:
			return false
		attack_lock = 1.60 if wave_wrong_stacks <= 0 else 1.20
		return true
	attack_lock = 1.12 if wave_wrong_stacks <= 0 else 0.82
	return true

func active_threat_count() -> int:
	if zone < 0 or not is_zone_engaged(zone) or not troops.has(zone):
		return 0
	var c = 0
	for s in troops[zone]:
		if is_instance_valid(s) and not s.defeated and s.action == Soldier.Action.AIM:
			c += 1
	return c

func apply_player_damage(damage: int):
	shield_delay = 0.0
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

func apply_physical_trauma(hp_damage: int, shield_damage: int = 5, death_reason: String = "行动失败 · 生命耗尽"):
	if not in_field():
		return
	shield_delay = 0.0
	shield = maxf(0.0, float(shield) - float(maxi(0, shield_damage)))
	health = maxi(0, health - maxi(0, hp_damage))
	game.screen_flash.color = Color(0.95, 0.12, 0.08, 0.28)
	if health == 0:
		game._end_run(false, death_reason)

func claim_tactical_cover(soldier, force_new_cover: bool = false) -> Dictionary:
	var z_idx: int = soldier.zone
	var center := zone_center(z_idx)
	var player_pos: Vector3 = game.player.position
	var d_player_camp := Vector2(player_pos.x - center.x, player_pos.z - center.z).length()
	var camp_list: Array = camp_covers.get(z_idx, [])
	var outer_list: Array = camp_outer_anchors.get(z_idx, [])

	var all_anchors: Array = []
	for p in camp_list:
		all_anchors.append({"pos": p, "is_parapet": true})
	# Include roadside natural tree/rock covers when player steps outside camp (>17m) or in Confidential flanking!
	if d_player_camp > 17.0 or game.rules.is_confidential():
		for op in outer_list:
			all_anchors.append({"pos": op, "is_parapet": false})

	if all_anchors.is_empty():
		return {"idx": 0, "anchor": soldier.cover, "shelter_pos": soldier.home, "peek_pos": soldier.home, "is_parapet": true}

	var ideal_min := 11.5 if soldier.archetype in [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.BOSS_WARDEN] else (8.2 if is_single_attacker_mode() else 6.2)
	var ideal_max := 20.5 if soldier.archetype in [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.BOSS_WARDEN] else (17.2 if is_single_attacker_mode() else 14.5)

	var best_idx := 0
	var best_score := -1e9
	for k in all_anchors.size():
		var anc: Vector3 = all_anchors[k]["pos"]
		var is_parapet: bool = all_anchors[k]["is_parapet"]
		var occupied := false
		for other in troops.get(z_idx, []):
			if other != soldier and is_instance_valid(other) and not other.defeated:
				if other.claimed_cover_idx == k or Vector2(other.position.x - anc.x, other.position.z - anc.z).length() < 2.05:
					occupied = true
					break
		if occupied:
			continue

		var d_p := Vector2(player_pos.x - anc.x, player_pos.z - anc.z).length()
		var d_self := Vector2(soldier.position.x - anc.x, soldier.position.z - anc.z).length()
		var d_camp := Vector2(anc.x - center.x, anc.z - center.z).length()

		# Normal mode small-range out-of-camp limit: stay within cautious ~29m camp perimeter!
		if is_single_attacker_mode() and d_camp > 29.5:
			continue

		var score := 0.0
		if d_p >= ideal_min and d_p <= ideal_max:
			score += 24.0
		elif d_p < ideal_min:
			score -= (ideal_min - d_p) * 4.5
		else:
			score -= (d_p - ideal_max) * 1.85

		# Prefer built Hui parapets when player is near camp, and nearby moves (4..11m) over marathon sprints
		if is_parapet and d_player_camp <= 21.5:
			score += 8.5
		score -= d_self * 0.42

		if force_new_cover and (k == soldier.claimed_cover_idx or d_self < 1.85):
			score -= 32.0
		elif not force_new_cover and k == soldier.claimed_cover_idx:
			score += 5.5

		if score > best_score:
			best_score = score
			best_idx = k

	var chosen: Vector3 = all_anchors[best_idx]["pos"]
	var chosen_parapet: bool = all_anchors[best_idx]["is_parapet"]
	var to_p := Vector3(player_pos.x - chosen.x, 0.0, player_pos.z - chosen.z)
	if to_p.length_squared() < 0.04:
		to_p = Vector3.BACK
	var dir_p := to_p.normalized()
	var right_v := dir_p.cross(Vector3.UP).normalized()
	# Shelter behind center solid 1.84m merlon / trunk; Peek laterally over 0.72m low wing so 100% of Word Shield is readable!
	var shelter_p: Vector3 = game.Layout.on_ground(chosen - dir_p * (1.42 if chosen_parapet else 1.15))
	var peek_off: float = 1.16 if chosen_parapet else 1.10
	var peek_p: Vector3 = game.Layout.on_ground(chosen + right_v * soldier.side * peek_off - dir_p * (0.78 if chosen_parapet else 0.45))
	soldier.claimed_cover_idx = best_idx
	soldier.cover = chosen
	return {
		"idx": best_idx,
		"anchor": chosen,
		"shelter_pos": shelter_p,
		"peek_pos": peek_p,
		"is_parapet": chosen_parapet,
	}

func try_moving_suppression(soldier) -> bool:
	if suppress_lock > 0.0 or not in_field() or game.paused or soldier.defeated or soldier.zone != zone or not is_zone_engaged(zone) or soldier.stun_left > 0.0:
		return false
	if player_in_smoke():
		return false
	if is_single_attacker_mode() and active_threat_count() >= 1 and active_attacker != soldier:
		return false
	var horiz_d := Vector2(soldier.position.x - game.player.position.x, soldier.position.z - game.player.position.z).length()
	if horiz_d > soldier.attack_range() + 2.0 or not clear_shot(soldier.position):
		return false
	suppress_lock = 0.92 if is_single_attacker_mode() else 0.48
	moving_suppression_shots += 1
	strike(soldier, true)
	return true

func strike(soldier, is_moving_suppression: bool = false):
	if not in_field() or game.paused or soldier.defeated or soldier.zone != zone or not is_zone_engaged(zone) or soldier.stun_left > 0:
		return
	if is_instance_valid(game.exploration) and game.exploration.safe():
		return
	var horiz_d := Vector2(soldier.position.x - game.player.position.x, soldier.position.z - game.player.position.z).length()
	if horiz_d > soldier.attack_range() + 2.5 or not clear_shot(soldier.position):
		return
	var from: Vector3 = soldier.position + Vector3.UP * (2.10 if soldier.archetype == Soldier.Archetype.BOSS_WARDEN else 1.58)
	var to: Vector3 = player_aim_point()
	var chance := hit_chance()
	if soldier.archetype in [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.BOSS_WARDEN]:
		var bonus := 0.05 if is_single_attacker_mode() else 0.10
		var min_c := 0.10 if is_single_attacker_mode() else 0.20
		chance = clampf(chance + bonus, min_c, 0.90)
	if is_moving_suppression:
		chance *= SUPPRESS_HIT_SCALE
	var hits_player := shot_rng.randf() < chance
	if not hits_player:
		var sideways := (to - from).cross(Vector3.UP).normalized()
		if sideways.is_zero_approx():
			sideways = Vector3.RIGHT
		var side := -1.0 if shot_rng.randf() < 0.5 else 1.0
		var spread := shot_rng.randf_range(0.95, 1.85) if is_moving_suppression else shot_rng.randf_range(0.7, 1.4)
		to += sideways * side * spread + Vector3.UP * (shot_rng.randf_range(-0.22, 0.35) if is_moving_suppression else 0.0)
		var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
		var impact := get_world_3d().direct_space_state.intersect_ray(ray)
		if not impact.is_empty():
			to = impact.position
	var beam_col = Color("ffd970") if is_moving_suppression else (Color("ff5d6c") if soldier.archetype in [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.BOSS_WARDEN] else Color("ffc483"))
	var trace = game._mesh_box(arena, (from + to) / 2, Vector3(0.032, 0.032, from.distance_to(to)), beam_col)
	trace.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trace_up := Vector3.RIGHT if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	trace.look_at(to, trace_up)
	trace.create_tween().tween_callback(trace.queue_free).set_delay(0.14)
	game.play_sound("enemy_attack", -20 if is_moving_suppression else -19)
	if not hits_player:
		miss_left = 1.2
		return
	miss_left = 0.0
	var shot_dmg := maxi(2, roundi(float(damage_per_shot(soldier)) * (0.75 if is_moving_suppression else 1.0)))
	apply_player_damage(shot_dmg)
