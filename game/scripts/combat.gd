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
# v0.8.1 #3/#4/#8 & v0.8.3 ADS-gated sniping: 3x aggro (~46-48m) ADS-only preview with LOS + audio debounce
const SNIPER_AGGRO_MULT = 3.0
const SNIPER_PREVIEW_RANGE = 48.0
const PREVIEW_SPEAK_DEBOUNCE = 1.2
const PROMPT_TIMEOUT_NORMAL = 10.0
const PROMPT_TIMEOUT_CONFIDENTIAL = 7.0
const WRONG_REVEAL_SECONDS = 1.4
const RAGE_WRONG_TRIGGER = 3
const RAGE_HUNT_DURATION = 12.0
const RAGE_NORMAL_DAMAGE_MULT = 2.0
const RAGE_CONFIDENTIAL_DAMAGE_MULT = 4.0
const RAGE_PURSUIT_RADIUS = 145.0

var game
var stage = Stage.OFF
var field_hits: int = 0
var field_answers: int = 0
var rage_left: float = 0.0
var wave_wrong_stacks: int = 0
var wrong_attempts_on_current: int = 0
var prompt_choice_count := 0
var first_choice_recorded := false
var first_choice_independent := false
var nemesis_cursor := 0
var zone_prompt_option: Dictionary = {}
var preview_zone: int = -1
var last_preview_speak_zone: int = -1
var last_preview_speak_word: String = ""
var preview_speak_cd: float = 0.0
var prompt_timer_left: float = 0.0
var prompt_timer_max: float = PROMPT_TIMEOUT_NORMAL
var prompt_reveal_left: float = 0.0
var prompt_reveal_zone: int = -1
var prompt_locked_after_wrong: bool = false
var consecutive_wrong_hits: int = 0
var rage_hunt_left: float = 0.0
var rage_hunt_zone: int = -1
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
var boss_barrage_cd: float = 4.5
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
	first_choice_recorded = false
	first_choice_independent = false
	nemesis_cursor = 0
	zone_prompt_option.clear()
	preview_zone = -1
	last_preview_speak_zone = -1
	last_preview_speak_word = ""
	preview_speak_cd = 0.0
	prompt_timer_left = 0.0
	prompt_timer_max = prompt_timeout_limit()
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_locked_after_wrong = false
	consecutive_wrong_hits = 0
	rage_hunt_left = 0.0
	rage_hunt_zone = -1
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
	boss_barrage_cd = 4.5
	shot_rng.randomize()
	_deploy()

func stop():
	stage = Stage.OFF
	zone = -1
	rage_left = 0.0
	wave_wrong_stacks = 0
	wrong_attempts_on_current = 0
	first_choice_recorded = false
	first_choice_independent = false
	nemesis_cursor = 0
	zone_prompt_option.clear()
	preview_zone = -1
	last_preview_speak_zone = -1
	last_preview_speak_word = ""
	preview_speak_cd = 0.0
	prompt_timer_left = 0.0
	prompt_timer_max = prompt_timeout_limit()
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_locked_after_wrong = false
	consecutive_wrong_hits = 0
	rage_hunt_left = 0.0
	rage_hunt_zone = -1
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	boss_unit = null
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	smoke_zones.clear()
	danger_rings.clear()
	boss_barrage_cd = 4.5
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

func zone_sniper_range(z_idx: int) -> float:
	return zone_aggro(z_idx) * SNIPER_AGGRO_MULT

func is_rage_hunting(z_idx: int) -> bool:
	return rage_hunt_left > 0.0 and z_idx == rage_hunt_zone

func prompt_timeout_limit() -> float:
	return PROMPT_TIMEOUT_CONFIDENTIAL if game.rules.is_confidential() else PROMPT_TIMEOUT_NORMAL

func zone_pursuit(z_idx: int) -> float:
	if is_rage_hunting(z_idx):
		return RAGE_PURSUIT_RADIUS
	if is_single_attacker_mode():
		return minf(NORMAL_PURSUIT_RADIUS, float(zone_info(z_idx).pursuit))
	return float(zone_info(z_idx).pursuit)

func damage_multiplier() -> float:
	if rage_hunt_left > 0.0:
		return RAGE_CONFIDENTIAL_DAMAGE_MULT if game.rules.is_confidential() else RAGE_NORMAL_DAMAGE_MULT
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
	zone_prompt_option.erase(z_idx)
	if preview_zone == z_idx:
		preview_zone = -1
	if rage_hunt_zone == z_idx:
		rage_hunt_left = 0.0
		rage_hunt_zone = -1
	prompt_timer_left = 0.0
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_locked_after_wrong = false
	if zone == z_idx:
		zone = -1
	wave_wrong_stacks = 0
	game.rules.outposts_cleared += 1
	game.rules.score += game.Rules.OUTPOST_CLEAR_SCORE
	game.player.medkits += 1
	var clear_ammo := 6 if game.rules.is_confidential() else 8
	game.player.add_reserve_ammo(clear_ammo)
	game.play_sfx("loot_epic", -11)
	if is_instance_valid(game.rangers):
		game.rangers.unlock_card("mistbound_syndicate", false)
		game.rangers.record_bounty_progress("camp_cleared", 1)
	game._sync_question()
	game._notice("★ 已彻底肃清【%s】全部 3 波守军！+%d 积分 · 医疗包+1 备弹+%d（已攻克 %d/%d 营地，撤离需2处）" % [
		zone_info(z_idx).title, game.Rules.OUTPOST_CLEAR_SCORE, clear_ammo,
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
	plinth_mat.albedo_color = Color("b2bcb8")
	plinth_mat.albedo_texture = load("res://assets/slice/ink_jiangnan/flagstone_albedo.png")
	plinth_mat.normal_enabled = true
	plinth_mat.normal_texture = load("res://assets/slice/ink_jiangnan/flagstone_normal.png")
	plinth_mat.roughness = 0.80
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
	var due_pool: Array = game.rules.learning.pending(game.pool, 0, true)
	if not due_pool.is_empty():
		var picked: Dictionary = due_pool[nemesis_cursor % due_pool.size()]
		nemesis_cursor += 1
		return picked
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
		var skyfall_boss: bool = (archetypes[i] == Soldier.Archetype.BOSS_WARDEN and game.rules.is_confidential())
		soldier.setup(self, z_idx, i, covers[c_slot], archetypes[i], skyfall_boss)
		soldier.claimed_cover_idx = c_slot
		soldier.assigned_word = words_n[i]
		soldier.set_nemesis_bounty(game.rules.learning.is_nemesis(str(words_n[i].get("id", ""))))
		# v0.8.1 #3: Word shields are clearly shown from spawn so players can scout & snipe from afar!
		if skyfall_boss:
			soldier.configure_overlord_sequence(_build_wave_words(5))
		else:
			soldier.show_word(str(words_n[i].get("english", "")), false)
		soldiers.append(soldier)
		if archetypes[i] == Soldier.Archetype.BOSS_WARDEN:
			boss_unit = soldier
	troops[z_idx] = soldiers
	zone_engaged[z_idx] = false
	_pick_zone_prompt_option(z_idx, -1)

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
			_build_tactical_cover(barrier, i, i > 0 and i < CAMP_COVER_COUNT - 1)
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

func _pick_zone_prompt_option(z_idx: int, avoid_option: int = -1) -> int:
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		zone_prompt_option.erase(z_idx)
		return -1
	var candidates := alive
	if z_idx == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated and boss_unit.exposed_left > 0.0 and alive.size() > 1:
		var non_boss := []
		for s in alive:
			if s != boss_unit:
				non_boss.append(s)
		if not non_boss.is_empty():
			candidates = non_boss
	if avoid_option >= 0 and candidates.size() >= 2:
		var alt := []
		for s in candidates:
			if s.option != avoid_option:
				alt.append(s)
		if not alt.is_empty():
			candidates = alt
	var nemesis_candidates := []
	if candidates.size() >= 2:
		for s in candidates:
			if s.is_nemesis_bounty:
				nemesis_candidates.append(s)
	var chosen = nemesis_candidates[shot_rng.randi_range(0, nemesis_candidates.size() - 1)] if not nemesis_candidates.is_empty() else candidates[shot_rng.randi_range(0, candidates.size() - 1)]
	zone_prompt_option[z_idx] = chosen.option
	return chosen.option

func _get_zone_prompt_soldier(z_idx: int):
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		return null
	var want_opt := int(zone_prompt_option.get(z_idx, -1))
	for s in alive:
		if s.option == want_opt:
			if z_idx == 2 and s == boss_unit and boss_unit.exposed_left > 0.0 and alive.size() > 1:
				break
			return s
	var picked_opt := _pick_zone_prompt_option(z_idx, -1)
	for s in alive:
		if s.option == picked_opt:
			return s
	return alive[0]

func _reroll_soldier_word(z_idx: int, soldier):
	if not is_instance_valid(soldier) or soldier.defeated:
		return
	var old_en := str(soldier.assigned_word.get("english", "")).to_lower()
	var fresh := _pick_seed_word()
	for _try in 12:
		var f_en := str(fresh.get("english", "")).to_lower()
		var clash := (f_en == old_en)
		if not clash:
			for other in living_soldiers(z_idx):
				if other != soldier and str(other.assigned_word.get("english", "")).to_lower() == f_en:
					clash = true
					break
		if not clash:
			break
		fresh = _pick_seed_word()
	if wave_words.has(z_idx) and soldier.option < wave_words[z_idx].size():
		wave_words[z_idx][soldier.option] = fresh
	soldier.assigned_word = fresh
	soldier.set_nemesis_bounty(game.rules.learning.is_nemesis(str(fresh.get("id", ""))))
	soldier.show_word(str(fresh.get("english", "")), false)

func _sync_active_prompt_from_zone(z_idx: int, reset_timer: bool = false) -> bool:
	var chosen = _get_zone_prompt_soldier(z_idx)
	if not is_instance_valid(chosen):
		return false
	var alive := living_soldiers(z_idx)
	game.choices = wave_words.get(z_idx, [])
	game.answer_index = chosen.option
	game.question = chosen.assigned_word
	prompt_choice_count = alive.size()
	if reset_timer:
		prompt_timer_max = prompt_timeout_limit()
		prompt_timer_left = prompt_timer_max
		wrong_attempts_on_current = 0
		first_choice_recorded = false
		first_choice_independent = false
		game.question_help_used = false
		prompt_locked_after_wrong = false
		game.rules.open_question()
	return true

func _select_next_wave_prompt(z_idx: int, avoid_option: int = -1, preserve_existing: bool = false) -> bool:
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		return false
	var chosen = _get_zone_prompt_soldier(z_idx) if preserve_existing else null
	if not is_instance_valid(chosen):
		_pick_zone_prompt_option(z_idx, avoid_option)
		chosen = _get_zone_prompt_soldier(z_idx)
	if not is_instance_valid(chosen):
		return false
	game.choices = wave_words[z_idx]
	game.answer_index = chosen.option
	game.question = chosen.assigned_word
	wrong_attempts_on_current = 0
	prompt_choice_count = alive.size()
	first_choice_recorded = false
	first_choice_independent = false
	prompt_locked_after_wrong = false
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_timer_max = prompt_timeout_limit()
	prompt_timer_left = prompt_timer_max
	game.question_help_used = false
	game.listening_mode = (game.has_english_voice(str(game.question.get("english", ""))) and game.rules.answered >= 4 and game.rules.answered % 5 == 0)
	game.rules.open_question()
	game.next_question_left = 0.0
	show_question()
	if game.has_method("flash_word_switch_banner"):
		game.flash_word_switch_banner()
	var auto_speak: bool = bool(game.rules.setting("auto_speak_on_switch", true))
	var should_speak_zone: bool = (zone == z_idx and is_zone_engaged(z_idx)) or (preview_zone == z_idx and is_instance_valid(game.player) and game.player.aiming)
	if should_speak_zone and (game.listening_mode or auto_speak) and not game.paused:
		game.speak_english(str(game.question.get("english", "")))
	return true

func _rotate_prompt_after_wrong(z_idx: int):
	## v0.8.1 #4: After brief 1.4s correct-answer reveal, swap old soldier's word & switch to a brand-new question!
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_locked_after_wrong = false
	if z_idx < 0 or zone_cleared.get(z_idx, false):
		return
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		return
	var old_opt := int(zone_prompt_option.get(z_idx, -1))
	for s in alive:
		if s.option == old_opt:
			_reroll_soldier_word(z_idx, s)
			break
	_select_next_wave_prompt(z_idx, old_opt, false)

func _rotate_prompt_on_timeout(z_idx: int):
	## v0.8.1 #4: Auto-rotate unanswered question cleanly after 10s (Normal) / 7s (Confidential).
	if z_idx < 0 or zone_cleared.get(z_idx, false):
		return
	var alive := living_soldiers(z_idx)
	if alive.is_empty():
		return
	var old_opt := int(zone_prompt_option.get(z_idx, -1))
	if alive.size() == 1:
		_reroll_soldier_word(z_idx, alive[0])
	_select_next_wave_prompt(z_idx, old_opt, false)
	game._notice("⏱ 题目超时自动轮换新词 · 瞄准新目标词兵！", Color("9cd6f0"))

func _has_sniper_los(from: Vector3, target_pt: Vector3) -> bool:
	var seg := target_pt - from
	var dist := seg.length()
	if dist <= 1.2:
		return true
	var rq := PhysicsRayQueryParameters3D.create(from, target_pt - seg.normalized() * 0.45, 1, [game.player.get_rid()])
	rq.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(rq).is_empty()

func _detect_aimed_camp() -> int:
	## v0.8.3 ADS-gated sniping: ONLY when right-click aiming (rifle) within 3x camp aggro (~46-48m) & unobstructed LOS!
	if not in_field() or not is_instance_valid(game.player) or not is_instance_valid(game.player.camera):
		return -1
	if not game.player.aiming or game.player.weapon_slot != 0:
		return -1
	var cam: Camera3D = game.player.camera
	var from := cam.global_position
	var fwd := (-cam.global_basis.z).normalized()
	# 1) Direct crosshair hit on any living soldier within that camp's 3x-aggro sniper range (layer 1 auto-occludes terrain/walls)
	var rq := PhysicsRayQueryParameters3D.create(from, from + fwd * SNIPER_PREVIEW_RANGE, 1 | Soldier.HIT_LAYER, [game.player.get_rid()])
	rq.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	if not hit.is_empty():
		var direct_s = _resolve_soldier_node(hit.collider)
		if direct_s is Soldier and not direct_s.defeated and not zone_cleared.get(direct_s.zone, false) and float(zone_reinforce_left.get(direct_s.zone, 0.0)) <= 0.0:
			var max_r: float = zone_sniper_range(direct_s.zone)
			if from.distance_to(hit.position) <= max_r:
				return direct_s.zone
	# 2) Tight ADS angular cone (~15 deg) with terrain/obstacle LOS check within each camp's 3x-aggro sniper range
	var best_z := -1
	var best_dot: float = 0.965
	for z_idx in game.Layout.COMBAT_ZONES.size():
		if zone_cleared.get(z_idx, false) or float(zone_reinforce_left.get(z_idx, 0.0)) > 0.0:
			continue
		var alive := living_soldiers(z_idx)
		if alive.is_empty():
			continue
		var max_r: float = zone_sniper_range(z_idx)
		var z_dot := -1.0
		var center_pt := zone_center(z_idx) + Vector3.UP * 2.2
		var d_c := from.distance_to(center_pt)
		if d_c <= max_r and d_c > 1.0:
			var dot_c := fwd.dot((center_pt - from).normalized())
			if dot_c > best_dot and _has_sniper_los(from, center_pt):
				z_dot = maxf(z_dot, dot_c)
		for s in alive:
			var sp: Vector3 = s.global_position + Vector3.UP * 1.72
			var d_s := from.distance_to(sp)
			if d_s <= max_r and d_s > 1.0:
				var dot_s := fwd.dot((sp - from).normalized())
				if dot_s > best_dot and _has_sniper_los(from, sp):
					z_dot = maxf(z_dot, dot_s)
		if z_dot > best_dot:
			best_dot = z_dot
			best_z = z_idx
	return best_z

func spawn_pending_wave_now(z_idx: int):
	if float(zone_reinforce_left.get(z_idx, 0.0)) > 0.0 and not zone_cleared.get(z_idx, false):
		zone_reinforce_left[z_idx] = 0.0
		_spawn_camp_wave(z_idx)
		zone_respawn_grace[z_idx] = WAVE_TRUCE_GRACE

func engage_camp(z_idx: int, preserve_prompt: bool = false):
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
	preview_zone = -1
	zone_engaged[z_idx] = true
	zone_respawn_grace[z_idx] = 0.0
	if not is_rage_hunting(z_idx):
		wave_wrong_stacks = 0
		rage_left = 0.0
	wrong_attempts_on_current = 0
	first_choice_recorded = false
	first_choice_independent = false
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	boss_barrage_cd = 3.8 if game.rules.is_confidential() else 4.5
	attack_lock = 0.25 if game.rules.is_confidential() else 0.55
	game._leave_station()
	game.next_question_left = 0.0
	for s in alive:
		if s.action == Soldier.Action.PATROL:
			s.begin_tactical_engagement()
	if is_single_attacker_mode():
		active_attacker = _pick_next_attacker(z_idx)
	_select_next_wave_prompt(z_idx, -1, preserve_prompt)
	var z_title: String = zone_info(z_idx).title
	var w_cur: int = int(waves_done.get(z_idx, 0)) + 1
	var w_max: int = int(waves_target.get(z_idx, WAVES_PER_CAMP))
	var pace_tag: String = "机密机动包抄" if game.rules.is_confidential() else "普通谨慎掩体战"
	if not is_rage_hunting(z_idx):
		if z_idx == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
			if boss_unit.is_skyfall_overlord:
				if boss_unit.skyfall_state == "idle":
					boss_unit.trigger_skyfall()
				game._notice("⚡ 天降震地！【雾隐机关王·玄铁词尊】轰然降临 %s！请严格按 1→5 顺序击破全身 5 块词盾（打错顺序满血洗牌）！" % z_title, Color("ffd15c"))
			else:
				game._notice("⚠ 惊动雾隐帮【%s】（第 %d/%d 波 · %d兵 · %s）：雾隐先锋·铁面词卫登场！爆头1枪或词盾2枪破防！" % [z_title, w_cur, w_max, alive.size(), pace_tag], Color("ffd15c"))
				game.play_sfx("boss_phase", -11)
		else:
			game._notice("⚔ 触发雾隐帮【%s】第 %d/%d 波交火（%d兵 · %s）！词兵依托掩体周旋，抓闪身时机打头1枪/词盾2枪！" % [z_title, w_cur, w_max, alive.size(), pace_tag], game.GOLD)

func disengage_active_camp(announce: bool = true):
	if zone < 0:
		return
	var old_z := zone
	zone_engaged[old_z] = false
	zone = -1
	wave_wrong_stacks = 0
	rage_left = 0.0
	prompt_timer_left = 0.0
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_locked_after_wrong = false
	wrong_attempts_on_current = 0
	first_choice_recorded = false
	first_choice_independent = false
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	for s in troops.get(old_z, []):
		if is_instance_valid(s) and not s.defeated:
			s.action = Soldier.Action.PATROL
			s.laser_beam.hide()
			# v0.8.1 #3: Keep English word shields visible even when returning to standby so distant sniping stays clear!
			s.show_word(str(s.assigned_word.get("english", "")), false)
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
	preview_speak_cd = maxf(0.0, preview_speak_cd - delta)

	# v0.8.1 #8: Rage Hunt countdown
	if rage_hunt_left > 0.0:
		rage_hunt_left = maxf(0.0, rage_hunt_left - delta)
		if rage_hunt_left <= 0.0:
			rage_hunt_zone = -1
			show_question()

	# v0.8.1 #4: Wrong-hit brief correct-answer reveal -> force switch to fresh new word
	if prompt_reveal_left > 0.0 and not (is_instance_valid(game.exploration) and game.exploration.safe()):
		prompt_reveal_left = maxf(0.0, prompt_reveal_left - delta)
		if prompt_reveal_left <= 0.0:
			_rotate_prompt_after_wrong(prompt_reveal_zone)

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
		# v0.8.2_dev2 D2-2: Periodic Boss Mortar Barrage (red danger rings) so B-Zone Boss is genuinely threatening!
		if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated and not boss_unit.is_skyfall_overlord and boss_unit.stun_left <= 0.0 and not player_in_smoke():
			boss_barrage_cd -= delta
			if boss_barrage_cd <= 0.0:
				boss_barrage_cd = 4.2 if game.rules.is_confidential() else 5.5
				var b_dmg := 38 if game.rules.is_confidential() else 28
				if is_instance_valid(game.player):
					spawn_danger_ring(game.player.position, 3.4, b_dmg)
					if boss_unit.boss_phase <= 2:
						var pvel: Vector3 = game.player.get_real_velocity()
						var lead := Vector3(pvel.x, 0.0, pvel.z)
						var offset := lead.normalized() * 3.8 if lead.length() > 0.6 else Vector3(3.6, 0.0, 0.0)
						spawn_danger_ring(game.player.position + offset, 3.0, maxi(20, b_dmg - 4))
		# v0.8.1 #4: Unanswered combat question countdown (Normal 10s / Confidential 7s)
		if prompt_reveal_left <= 0.0 and game.rules.question_open:
			prompt_timer_left = maxf(0.0, prompt_timer_left - delta)
			if prompt_timer_left <= 0.0:
				_rotate_prompt_on_timeout(zone)
		if is_single_attacker_mode() and not is_rage_hunting(zone):
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
		engage_camp(pull_idx, true)
		return

	# v0.8.3 ADS-gated sniper aim detection — ONLY when right-click aiming at an un-cleared camp within 3x aggro (~46-48m) & clear LOS!
	var aimed: int = preview_zone if (prompt_reveal_left > 0.0 and preview_zone >= 0) else _detect_aimed_camp()
	if aimed != preview_zone:
		preview_zone = aimed
		if preview_zone >= 0 and prompt_reveal_left <= 0.0:
			_sync_active_prompt_from_zone(preview_zone, true)
			if game.has_method("flash_word_switch_banner"):
				game.flash_word_switch_banner()
			var cur_en := str(game.question.get("english", ""))
			var allow_speak := preview_speak_cd <= 0.0 or preview_zone != last_preview_speak_zone or cur_en != last_preview_speak_word
			if allow_speak and bool(game.rules.setting("auto_speak_on_switch", true)) and not game.paused and cur_en != "":
				game.speak_english(cur_en)
				last_preview_speak_zone = preview_zone
				last_preview_speak_word = cur_en
				preview_speak_cd = PREVIEW_SPEAK_DEBOUNCE
		elif preview_zone < 0:
			prompt_timer_left = 0.0
		show_question()
	elif preview_zone >= 0 and prompt_reveal_left <= 0.0:
		if zone_cleared.get(preview_zone, false) or living_soldiers(preview_zone).is_empty():
			preview_zone = -1
			prompt_timer_left = 0.0
			show_question()
		elif prompt_timer_left > 0.0 and game.rules.question_open:
			prompt_timer_left = maxf(0.0, prompt_timer_left - delta)
			if prompt_timer_left <= 0.0:
				_rotate_prompt_on_timeout(preview_zone)

func show_question():
	var fighting := zone >= 0 and is_zone_engaged(zone)
	for station in game.stations:
		station.terminal_label.visible = not fighting
	if not fighting:
		if game.active_station == 0:
			return
		# v0.8.3 ADS-Gated Sniper Preview HUD when right-click aiming at an un-cleared camp within 3x aggro!
		if preview_zone >= 0 and not zone_cleared.get(preview_zone, false) and not living_soldiers(preview_zone).is_empty():
			if prompt_reveal_left <= 0.0:
				_sync_active_prompt_from_zone(preview_zone, false)
			var p_dist := roundi(game.player.position.distance_to(zone_center(preview_zone)))
			var p_alive := living_soldiers(preview_zone).size()
			var p_title: String = zone_info(preview_zone).title
			var p_wcur: int = int(waves_done.get(preview_zone, 0)) + 1
			var p_wmax: int = int(waves_target.get(preview_zone, WAVES_PER_CAMP))
			if prompt_reveal_left > 0.0:
				game.question_label.text = "正解：%s — %s" % [str(game.question.get("english", "")), str(game.question.get("chinese", ""))]
			else:
				game.question_label.text = str(game.question.get("chinese", ""))
			if is_instance_valid(game.cloze_label):
				var p_cl: Dictionary = game.cloze_for_word(str(game.question.get("id", "")))
				game.cloze_label.text = ("教材语境：%s  (p.%d)" % [p_cl.cloze_text, int(p_cl.textbook_page)]) if not p_cl.is_empty() else ""
			game.unit_label.text = "🎯 开镜狙词【%s】(%dm) · 第%d/%d波 · 守军%d | [X]读音" % [
				p_title, p_dist, p_wcur, p_wmax, p_alive
			]
			return
		var rest_hint := "右键开镜瞄准45m内敌营即可狙词  |  "
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
		game.question_label.text = "右键开镜瞄准敌营狙词，或靠近触发波次交火"
		if is_instance_valid(game.cloze_label):
			game.cloze_label.text = ""
		game.unit_label.text = "%s已攻克 %d/6 营（需≥2） · 统领密钥 %d/1" % [
			rest_hint, game.rules.outposts_cleared, 1 if game.rules.boss_defeated else 0
		]
		return

	var words_5: Array = wave_words.get(zone, [])
	var alive_count := 0
	var active_is_nemesis := false
	for slot_i in troops[zone].size():
		var soldier = troops[zone][slot_i]
		if not is_instance_valid(soldier) or soldier.defeated:
			continue
		alive_count += 1
		if soldier.option == game.answer_index and soldier.is_nemesis_bounty:
			active_is_nemesis = true
		var w_text := str(soldier.assigned_word.get("english", "")) if not soldier.assigned_word.is_empty() else (str(words_5[slot_i].english) if slot_i < words_5.size() else "")
		soldier.show_word(w_text, false)

	var overlord_active: bool = (zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated and boss_unit.is_skyfall_overlord)
	if overlord_active and prompt_reveal_left <= 0.0:
		var exp_w: Dictionary = boss_unit.expected_overlord_word()
		if not exp_w.is_empty():
			game.question = exp_w
			game.question_label.text = "【第 %d/5 盾】%s" % [boss_unit.overlord_seq_step + 1, str(exp_w.get("chinese", ""))]
			if is_instance_valid(game.cloze_label):
				var seq_parts: Array = []
				for si in boss_unit.overlord_seq_words.size():
					var raw_zh := str(boss_unit.overlord_seq_words[si].get("chinese", ""))
					var short_zh := raw_zh.split("；")[0].split(";")[0].split("，")[0].split(",")[0].strip_edges()
					if short_zh.length() > 4:
						short_zh = short_zh.substr(0, 4)
					if si < boss_unit.overlord_seq_step:
						seq_parts.append("✓%s" % short_zh)
					elif si == boss_unit.overlord_seq_step:
						seq_parts.append("▶%s" % short_zh)
					else:
						seq_parts.append("%d.%s" % [si + 1, short_zh])
				game.cloze_label.text = "顺序：" + " → ".join(seq_parts)
	elif prompt_reveal_left > 0.0:
		game.question_label.text = "正解：%s — %s" % [str(game.question.get("english", "")), str(game.question.get("chinese", ""))]
		if is_instance_valid(game.cloze_label):
			var rev_cl: Dictionary = game.cloze_for_word(str(game.question.get("id", "")))
			game.cloze_label.text = ("例句：%s  (p.%d)" % [rev_cl.english, int(rev_cl.textbook_page)]) if not rev_cl.is_empty() else "即将切换全新单词…"
	elif game.listening_mode and game.rules.question_open:
		game.question_label.text = "🔊 雾隐电台截获英文语音 · 按 [X] 重播读音"
		if is_instance_valid(game.cloze_label):
			game.cloze_label.text = "★ 宿敌复习词 · 独立击破额外 +10分 / +4盾" if active_is_nemesis else ""
	else:
		game.question_label.text = str(game.question.get("chinese", ""))
		if is_instance_valid(game.cloze_label):
			var cloze: Dictionary = game.cloze_for_word(str(game.question.get("id", "")))
			if not cloze.is_empty():
				var tag := "★ 宿敌语境：" if active_is_nemesis else "教材语境："
				game.cloze_label.text = "%s%s  (p.%d)" % [tag, cloze.cloze_text, int(cloze.textbook_page)]
			elif active_is_nemesis:
				game.cloze_label.text = "★ 宿敌复习词 · 独立击破额外 +10分 / +4盾"
			else:
				game.cloze_label.text = ""

	var z_title: String = zone_info(zone).title
	var w_cur: int = int(waves_done.get(zone, 0)) + 1
	var w_max: int = int(waves_target.get(zone, WAVES_PER_CAMP))
	var mode_tag := "机密机动" if game.rules.is_confidential() else "普通谨慎"
	var atk_tag := (" | 🔥狂暴×%.1f" % damage_multiplier()) if rage_hunt_left > 0.0 else ((" | ⚠敌攻×%.2f" % damage_multiplier()) if wave_wrong_stacks > 0 else "")
	var boss_suffix := ""
	if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
		if boss_unit.is_skyfall_overlord:
			boss_suffix = " | ★词尊 %d/500 (%d/5)" % [boss_unit.hp, boss_unit.overlord_seq_step]
		else:
			boss_suffix = " | ★先锋 %d/%d%s" % [boss_unit.hp, boss_unit.max_hp, " (红核!)" if boss_unit.exposed_left > 0 else ""]
	var wave_total: int = int(wave_squad_size.get(zone, troops[zone].size()))
	if overlord_active:
		game.unit_label.text = "雾隐总坛 · ★玄铁词尊 %d/500 · 顺序盾 %d/5 | [X]读音" % [boss_unit.hp, boss_unit.overlord_seq_step]
	elif boss_suffix != "":
		game.unit_label.text = "%s · 第%d/%d波 · 守%d/%d%s%s | [X]读音" % [
			z_title.replace("雾隐帮·", ""), w_cur, w_max, alive_count, wave_total, atk_tag, boss_suffix
		]
	else:
		game.unit_label.text = "%s · %s · 第%d/%d波 · 守军%d/%d%s | [X]读音" % [
			z_title, mode_tag, w_cur, w_max, alive_count, wave_total, atk_tag
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
	first_choice_independent = is_correct and prompt_choice_count >= 2 and not game.question_help_used
	game.rules.learning.record_recognition(str(game.question.id), is_correct, prompt_choice_count, game.question_help_used, -1, "combat_word", "listening" if game.listening_mode else "recognition")
	if (not is_correct or game.question_help_used) and game.question not in game.wrong_words:
		game.wrong_words.append(game.question)

func _apply_wrong_target_penalty(soldier):
	# v0.8.1 #4/#8: Wrong soldier takes ZERO HP/shield damage, reveals correct answer + voice + example for 1.4s
	# then forces a brand-new question; 3 consecutive wrong hits trigger 12s Rage Hunt (2.0x Normal / 4.0x Confidential)!
	soldier.on_wrong_hit_flash()
	wave_had_wrong_shot = true
	wave_wrong_stacks = mini(MAX_WRONG_STACKS, wave_wrong_stacks + 1)
	consecutive_wrong_hits += 1
	rage_left = 7.0
	wrong_attempts_on_current += 1
	field_answers += 1
	game.rules.answered += 1
	game.rules.streak = 0
	_record_first_choice(false)

	var target_z: int = soldier.zone
	var correct_en := str(game.question.get("english", ""))
	var correct_zh := str(game.question.get("chinese", ""))
	var cloze_d: Dictionary = game.cloze_for_word(str(game.question.get("id", "")))
	var example_line := ("\n例句：%s (p.%d)" % [cloze_d.english, int(cloze_d.textbook_page)]) if not cloze_d.is_empty() else ""

	# Lock old question & trigger 1.4s reveal before rotating to a brand-new word
	prompt_locked_after_wrong = true
	prompt_reveal_left = WRONG_REVEAL_SECONDS
	prompt_reveal_zone = target_z
	prompt_timer_left = 0.0

	game.hitmarker_left = 0.24
	game.hitmarker_label.text = "✕"
	game.hitmarker_label.add_theme_color_override("font_color", Color("ff6b6b"))
	game.hitmarker_label.show()
	game.play_sfx("hit_wrong", -10)
	game.speak_english(correct_en)

	var triggered_rage := false
	if consecutive_wrong_hits >= RAGE_WRONG_TRIGGER:
		triggered_rage = true
		consecutive_wrong_hits = 0
		rage_hunt_left = RAGE_HUNT_DURATION
		rage_hunt_zone = target_z
		if zone != target_z:
			engage_camp(target_z, true)
			# Re-apply reveal lock after engage_camp initialized the zone
			prompt_locked_after_wrong = true
			prompt_reveal_left = WRONG_REVEAL_SECONDS
			prompt_reveal_zone = target_z
			prompt_timer_left = 0.0
		for s_enrage in living_soldiers(target_z):
			s_enrage.begin_tactical_engagement(true)
		game.play_sfx("warning_lock", -6)
		game.screen_flash.color = Color(1.0, 0.16, 0.12, 0.24)
		var rage_title := "机密狂暴围剿" if game.rules.is_confidential() else "狂暴围剿"
		game._notice("🔥 连错3次触发【%s】%.0f秒 · 敌营全员强袭（敌伤×%.1f）\n正解：%s（%s）" % [
			rage_title, RAGE_HUNT_DURATION, damage_multiplier(), correct_en, correct_zh
		], Color("ff5c66"))
	else:
		game.screen_flash.color = Color(1.0, 0.32, 0.18, 0.11)
		game._notice("✕ 打错词兵（连错 %d/%d）！正解：%s（%s）· 即将换新题%s" % [
			consecutive_wrong_hits, RAGE_WRONG_TRIGGER, correct_en, correct_zh, example_line
		], Color("ff9d7d"))
	if not triggered_rage and zone < 0:
		preview_zone = target_z
	show_question()

func _score_wave_correct(soldier, is_crit: bool, prefix: String, grant_bullet_ammo: bool = true):
	if is_instance_valid(soldier):
		last_kill_pos = soldier.global_position
	consecutive_wrong_hits = 0
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
		var kill_ammo := 1 if game.rules.is_confidential() else 2
		game.player.add_reserve_ammo(kill_ammo)

	game.show_hitmarker(is_crit)
	game.play_sfx("hit_correct", -10)
	game.speak_english(str(w_entry.get("english", "")))
	game.screen_flash.color = Color(0.3, 1.0, 0.65, 0.08)
	if is_instance_valid(game.achievements):
		game.achievements.record_stat("best_streak", game.rules.streak, true)
	if is_instance_valid(game.rangers):
		game.rangers.record_bounty_progress("best_streak", game.rules.streak, true)
		if is_instance_valid(soldier) and soldier.defeated:
			game.achievements.record_stat("soldiers_defeated", 1)
			if is_instance_valid(game.player) and game.player.position.distance_to(soldier.position) >= 35.0:
				game.achievements.record_stat("sniper_kills", 1)

	var nemesis_tag := ""
	if is_instance_valid(soldier) and soldier.is_nemesis_bounty and first_choice_independent:
		game.rules.nemesis_cleared += 1
		game.rules.score += game.Rules.NEMESIS_BONUS_SCORE
		gained += game.Rules.NEMESIS_BONUS_SCORE
		heal(0, 4)
		nemesis_tag = " · ★宿敌攻克(+%d分/+4盾)" % game.Rules.NEMESIS_BONUS_SCORE
	var streak_tag := (" · 🔥%d连击" % game.rules.streak) if game.rules.streak >= 3 else ""
	if game.rules.streak >= 3:
		heal(0, 6)
		streak_tag += "(+6盾)"
	if game.rules.correct % 3 == 0:
		var chip_rarity := 3 if game.rules.streak >= 4 else 2
		game.rules.add_loot("战术知识芯片", 46 + maxi(0, game.rules.level() - 1) * 4, chip_rarity)
	var cloze_note := ""
	var cl: Dictionary = game.cloze_for_word(str(w_entry.get("id", "")))
	if not cl.is_empty():
		cloze_note = "\n教材例句：%s (p.%d)" % [cl.english, int(cl.textbook_page)]
	game._notice("%s！+%d 分%s%s · %s（%s）%s" % [
		prefix, gained, nemesis_tag, streak_tag, str(w_entry.get("english", "")), str(w_entry.get("chinese", "")), cloze_note
	], Color("ffd15c") if nemesis_tag != "" else game.MINT)

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
	boss.set_nemesis_bounty(game.rules.learning.is_nemesis(str(fresh.get("id", ""))))
	boss.shield_layers = boss.max_shield_layers
	_select_next_wave_prompt(2)

func _complete_current_wave(z_idx: int):
	var flawless_wave: bool = not wave_had_wrong_shot
	var drop_origin: Vector3 = last_kill_pos if last_kill_pos != Vector3.ZERO else zone_center(z_idx)
	wave_wrong_stacks = 0
	rage_left = 0.0
	wrong_attempts_on_current = 0
	first_choice_recorded = false
	first_choice_independent = false
	wave_had_wrong_shot = false
	last_kill_pos = Vector3.ZERO
	active_attacker = null
	active_attacker_idle = 0.0
	last_attacker_option = -1
	zone_engaged[z_idx] = false
	zone_prompt_option.erase(z_idx)
	if preview_zone == z_idx:
		preview_zone = -1
	if rage_hunt_zone == z_idx:
		rage_hunt_left = 0.0
		rage_hunt_zone = -1
	prompt_timer_left = 0.0
	prompt_reveal_left = 0.0
	prompt_reveal_zone = -1
	prompt_locked_after_wrong = false
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
	game.player.add_reserve_ammo(3 if game.rules.is_confidential() else 4)
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
	var target_z: int = soldier.zone
	if zone < 0 or not is_zone_engaged(zone):
		# v0.8.1 #3: Support both close-range engagement & distant precision word sniping (preserving previewed prompt!)
		var d_camp := Vector2(game.player.position.x - zone_center(target_z).x, game.player.position.z - zone_center(target_z).z).length()
		if d_camp <= zone_pursuit(target_z):
			engage_camp(target_z, true)
		else:
			preview_zone = target_z
			if prompt_reveal_left <= 0.0:
				_sync_active_prompt_from_zone(target_z, not game.rules.question_open)
	elif target_z != zone:
		game._notice("⚠ 请先肃清当前追击你的【%s】词兵编队！" % zone_info(zone).title, game.GOLD)
		return true

	if muzzle_id != "suppressor":
		for other in living_soldiers(target_z):
			if other.action == Soldier.Action.PATROL:
				other.begin_tactical_engagement()

	# v0.8.2 #12: Confidential Operation Skyfall Giant 5-Shield Overlord ("雾隐机关王·玄铁词尊")
	# Must break all 5 body-mounted English word shields in STRICT 1->5 sequence; ANY wrong shield resets HP to 500/500 & reshuffles!
	if soldier.is_skyfall_overlord:
		if soldier.skyfall_state != "landed":
			soldier.force_land_skyfall()
		var hit_zone_str := str(collider.get_meta("hit_zone", "")) if (collider is Object) else ""
		if hit_zone_str != "multi_shield":
			game.show_hitmarker(false)
			game.play_sfx("dry_fire", -10)
			game._notice("🛡 雾隐机关王玄铁装甲反弹！请严格按 1→5 顺序射击其全身 5 块英文词盾！", Color("ffd15c"))
			show_question()
			return true
		var slot_idx := int(collider.get_meta("shield_slot", -1))
		var exp_slot: int = soldier.expected_overlord_slot()
		var exp_word: Dictionary = soldier.expected_overlord_word()
		var rem_choices: int = maxi(1, soldier.remaining_overlord_shields())
		var used_audio_help: bool = game.question_help_used
		if slot_idx == exp_slot:
			consecutive_wrong_hits = 0
			field_answers += 1
			field_hits += 1
			if not game.rules.question_open:
				game.rules.open_question()
			game.rules.answer(true)
			game.rules.score += 5
			game.rules.learning.record_recognition(str(exp_word.get("id", "")), true, rem_choices, used_audio_help, -1, "boss_overlord", "listening" if game.listening_mode else "recognition")
			game.question_help_used = false
			game.show_hitmarker(true)
			game.play_sfx("hit_correct", -9)
			game.speak_english(str(exp_word.get("english", "")))
			game.player.add_reserve_ammo(2)
			if is_instance_valid(game.achievements):
				game.achievements.record_stat("best_streak", game.rules.streak, true)
			var overlord_dead: bool = soldier.break_overlord_shield(slot_idx)
			if overlord_dead:
				if is_instance_valid(game.achievements):
					game.achievements.record_stat("soldiers_defeated", 1)
					game.achievements.record_stat("skyfall_boss_defeated", 1)
				_on_boss_defeated(soldier)
				_advance_wave_after_kill(target_z)
			else:
				var nxt: Dictionary = soldier.expected_overlord_word()
				prompt_timer_left = prompt_timer_max
				game._notice("⚡ 顺序破盾 (%d/5) 命中 %s！下一块词盾目标：【%s】" % [
					soldier.overlord_seq_step, str(exp_word.get("english", "")), str(nxt.get("chinese", ""))
				], Color("ffd15c"))
				show_question()
				if game.has_method("flash_word_switch_banner"):
					game.flash_word_switch_banner()
				if (game.listening_mode or bool(game.rules.setting("auto_speak_on_switch", true))) and not game.paused and not nxt.is_empty():
					game.speak_english(str(nxt.get("english", "")))
		else:
			# Wrong sequence -> Roar + Earthquake shake + FULL HP reset (500/500) + Reshuffle all 5 shields!
			consecutive_wrong_hits += 1
			field_answers += 1
			game.rules.answered += 1
			game.rules.streak = 0
			if not exp_word.is_empty():
				game.rules.learning.record_recognition(str(exp_word.get("id", "")), false, rem_choices, used_audio_help, -1, "boss_overlord", "listening" if game.listening_mode else "recognition")
				if exp_word not in game.wrong_words:
					game.wrong_words.append(exp_word)
			game.question_help_used = false
			game.show_hitmarker(false)
			game.play_sfx("boss_phase", -7)
			game.play_sfx("hit_wrong", -10)
			if not exp_word.is_empty():
				game.speak_english(str(exp_word.get("english", "")))
			soldier.reset_overlord_sequence(_build_wave_words(5))
			game.screen_flash.color = Color(1.0, 0.22, 0.14, 0.24)
			game._notice("⚠ 破防顺序错误（应击 %s）！雾隐机关王怒吼震地——血量已回满 500/500 且 5 块词盾重新洗牌！" % str(exp_word.get("english", "")), Color("ff5c66"))
			show_question()
		return true

	# Bonus weakpoint: Exposed Boss Reactor Core takes 38 crit damage while glowing!
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN and collider == soldier.core_area and soldier.exposed_left > 0.0:
		game.show_hitmarker(true)
		game.play_sfx("hit_correct", -11)
		var core_killed: bool = soldier.apply_damage(38, false, true)
		if core_killed:
			_on_boss_defeated(soldier)
			_advance_wave_after_kill(target_z)
		else:
			game._notice("★ 命中首领暴露红核！暴击 -38 HP（剩余 %d/%d HP）" % [soldier.hp, soldier.max_hp], Color("ffd15c"))
			show_question()
		return true

	# v0.8.1 #4: During the 1.4s correct-answer reveal after a wrong hit, lock prompt resolution (no score cheat & no accidental burst double-penalty)!
	if prompt_locked_after_wrong:
		game._notice("本题答案已公布，正在切换新题，请等待新词出现！", Color("ffd27d"))
		return true

	# Wrong soldier hit -> 0 damage + reveal correct answer + force switch + count toward 3-wrong Rage Hunt!
	if soldier.option != game.answer_index:
		_apply_wrong_target_penalty(soldier)
		return true

	_record_first_choice(true)
	# Correct soldier hit -> 1-shot Headshot OR 2-shot Word Shield/Torso!
	var is_head: bool = (collider == soldier.head_area) or (collider is Object and str(collider.get_meta("hit_zone", "")) == "head")
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		if is_head:
			var b_dead: bool = soldier.apply_damage(150, true, true)
			_score_wave_correct(soldier, true, "🎯 首领核心爆头破防")
			if b_dead:
				_on_boss_defeated(soldier)
				_advance_wave_after_kill(target_z)
			else:
				_rotate_boss_word_and_prompt(soldier)
		elif soldier.shield_layers > 1 and soldier.exposed_left <= 0.0:
			soldier.crack_shield_once()
			prompt_timer_left = prompt_timer_max
			game.show_hitmarker(false)
			game.play_sfx("hit_correct", -13)
			game._notice("⚡ 统领词盾裂开 (1/2)！再补 1 枪击碎护盾暴露红核（打头部可1枪破盾）！", Color("ffe082"))
			show_question()
		else:
			var b_dead2: bool = soldier.apply_damage(125, true, false)
			_score_wave_correct(soldier, false, "✦ 统领重甲词盾击碎")
			if b_dead2:
				_on_boss_defeated(soldier)
				_advance_wave_after_kill(target_z)
			else:
				_rotate_boss_word_and_prompt(soldier)
		return true

	# Normal pursuing word soldier (Assault / Drone / Sniper)
	if is_head:
		soldier.apply_damage(999, true, true)
		_score_wave_correct(soldier, true, "🎯 精准爆头一击必杀")
		_apply_boss_guard_shockwave()
		_advance_wave_after_kill(target_z)
	elif soldier.shield_layers > 1:
		soldier.crack_shield_once()
		prompt_timer_left = prompt_timer_max
		game.show_hitmarker(false)
		game.play_sfx("hit_correct", -13)
		game._notice("⚡ 命中正确词盾 (1/2)！单词未消散，再补 1 枪击毙（瞄准头部可 1 枪秒杀）！", Color("ffe082"))
		show_question()
	else:
		soldier.apply_damage(999, true, false)
		_score_wave_correct(soldier, false, "✦ 二段破盾击毙")
		_apply_boss_guard_shockwave()
		_advance_wave_after_kill(target_z)
	return true

func _apply_boss_guard_shockwave():
	if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated and not boss_unit.is_skyfall_overlord:
		var b_killed: bool = boss_unit.apply_damage(35, true, false)
		if b_killed:
			_on_boss_defeated(boss_unit)

func _apply_melee_knockback(soldier, speed: float = 3.2):
	if not is_instance_valid(game.player) or not is_instance_valid(soldier):
		return
	var away: Vector3 = game.player.position - soldier.position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	game.player.apply_knockback(away.normalized() * speed)

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

	# v0.8.2_dev2 D2-1: Skyfall Overlord heavy iron armor bounces melee completely!
	if best_soldier.is_skyfall_overlord:
		game.play_sfx("dry_fire", -9)
		game.show_hitmarker(false)
		_apply_melee_knockback(best_soldier, 4.6)
		apply_player_damage(24 if game.rules.is_confidential() else 16)
		game._notice("🛡 玄铁词尊装甲反弹匕首并震退反击！请用步枪按 1→5 顺序射击全身词盾！", Color("ff8080"))
		return true

	if best_soldier.archetype == Soldier.Archetype.BOSS_WARDEN and best_soldier.exposed_left > 0.0 and best_soldier.option != game.answer_index:
		game.play_sfx("knife_hit", -8)
		game.show_hitmarker(true)
		var b_kill: bool = best_soldier.apply_damage(35, false, true)
		_apply_melee_knockback(best_soldier, 3.8)
		apply_player_damage(20)
		if b_kill:
			_on_boss_defeated(best_soldier)
			_advance_wave_after_kill(zone)
		else:
			game._notice("🗡 斩击首领红核 -35 HP（剩余 %d/%d HP）· 遭到铁面重击反噬 -20！" % [best_soldier.hp, best_soldier.max_hp], Color("ffd15c"))
		return true

	if best_soldier.option != game.answer_index:
		game.play_sfx("knife_hit", -10)
		var bash_dmg := 28 if game.rules.is_confidential() else 16
		_apply_melee_knockback(best_soldier, 3.6)
		apply_player_damage(bash_dmg)
		_apply_wrong_target_penalty(best_soldier)
		game._notice("✕ 挥刀砍错词兵！遭到近身反击 -%d 伤害（正解：%s）" % [bash_dmg, str(game.question.get("english", ""))], Color("ff6b6b"))
		return true

	if prompt_locked_after_wrong:
		game._notice("本题答案已公布，正在切换新题！", Color("ffd27d"))
		return true

	game.play_sfx("knife_hit", -8)
	if best_soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		var boss_melee_dmg := 28 if game.rules.is_confidential() else 42
		var b_dead: bool = best_soldier.apply_damage(boss_melee_dmg, false, false)
		_apply_melee_knockback(best_soldier, 4.2)
		apply_player_damage(24 if game.rules.is_confidential() else 18)
		if b_dead:
			_record_first_choice(true)
			var b_ammo := 4 if game.rules.is_confidential() else 6
			game.player.add_reserve_ammo(b_ammo)
			_score_wave_correct(best_soldier, true, "🗡 匕首补刀击破首领（备弹+%d）" % b_ammo, false)
			_on_boss_defeated(best_soldier)
			_advance_wave_after_kill(zone)
		else:
			game.show_hitmarker(false)
			game._notice("🗡 匕首削甲 -%d HP（首领剩余 %d/%d HP）· 遭到首领重拳反击！建议拉远用枪破词盾！" % [boss_melee_dmg, best_soldier.hp, best_soldier.max_hp], Color("ffd15c"))
		return true

	# v0.8.2_dev2 D2-1: Tactical knife requires 5 hits (Normal) / 10 hits (Confidential) on regular word soldiers
	# with close-quarters counter-retaliation so melee is strictly an emergency ammo-recovery backup!
	var hits_needed: int = game.rules.melee_hits_to_kill()
	best_soldier.melee_hits_taken += 1
	var slash_dmg: int = maxi(1, int(ceilf(float(best_soldier.max_hp) / float(hits_needed))))
	var killed_by_melee: bool = (best_soldier.melee_hits_taken >= hits_needed) or (best_soldier.hp - slash_dmg <= 0)
	if killed_by_melee:
		_record_first_choice(true)
		var melee_ammo := 4 if game.rules.is_confidential() else 6
		game.player.add_reserve_ammo(melee_ammo)
		best_soldier.apply_damage(999, true, true)
		_score_wave_correct(best_soldier, true, "🗡 匕首连斩处决 (%d/%d刀 · 备弹+%d)" % [best_soldier.melee_hits_taken, hits_needed, melee_ammo], false)
		_apply_boss_guard_shockwave()
		_advance_wave_after_kill(zone)
	else:
		best_soldier.hp = maxi(1, best_soldier.hp - slash_dmg)
		best_soldier._refresh_hp_bar()
		best_soldier.begin_tactical_engagement()
		prompt_timer_left = maxf(prompt_timer_left, 4.0)
		game.show_hitmarker(false)
		var counter_tag := ""
		if best_soldier.melee_hits_taken % 2 == 0:
			var c_dmg := 18 if game.rules.is_confidential() else 10
			_apply_melee_knockback(best_soldier, 2.4)
			apply_player_damage(c_dmg)
			counter_tag = " · 敌兵贴身反击 -%d" % c_dmg
		game._notice("🗡 匕首劈砍命中 (%d/%d 刀 · 剩余 %d/%d HP)%s · 用枪打头可 1 枪秒杀！" % [
			best_soldier.melee_hits_taken, hits_needed, best_soldier.hp, best_soldier.max_hp, counter_tag
		], Color("ffe082"))
	return true

func record_field(_correct: bool):
	pass

func hit_feedback(_index: int, _correct: bool):
	pass

func on_boss_phase_shift(_boss, next_phase: int):
	game.play_sfx("boss_phase", -9)
	game._notice("★ 雾隐先锋·铁面词卫 进入第 %d 阶段！胸口红核暴露，小心重炮轰炸红圈！" % (4 - next_phase), Color("ffd15c"))
	if is_instance_valid(game.player):
		spawn_danger_ring(game.player.position, 3.4, 24)

func _on_boss_defeated(boss):
	if game.rules.boss_defeated:
		return
	game.rules.boss_defeated = true
	game.rules.score += game.Rules.BOSS_DEFEAT_SCORE
	game.player.add_reserve_ammo(8 if game.rules.is_confidential() else 10)
	var core_val := roundi(460.0 * (game.Rules.CONFIDENTIAL_VALUE_MULT if game.rules.is_confidential() else 1.0))
	var core_item := {"title": "烟山统领黄金核心", "value": core_val, "rarity": 6}
	if not game.rules.add_loot(core_item.title, core_item.value, core_item.rarity):
		game.rules.swap_lowest_loot(core_item)
	var extra_red_msg := ""
	if is_instance_valid(boss) and boss.is_skyfall_overlord:
		# Confidential Skyfall Overlord bonus drop: extra T6 Big Gold / T7 Mythic Red treasure!
		var bonus_r := 7 if randf() < 0.35 else 6
		var bonus_item: Dictionary = game.rules.roll_item_by_rarity(bonus_r)
		if game.rules.add_loot_item(bonus_item):
			extra_red_msg = " + 机密首领秘宝【%s】%s" % [game.Rules.RARITY_NAMES[bonus_r], bonus_item.title]
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
	if is_instance_valid(game.rangers):
		var is_ov: bool = is_instance_valid(boss) and boss.is_skyfall_overlord
		game.rangers.unlock_card("skyfall_overlord" if is_ov else "vanguard_boss", false)
		game.rangers.record_bounty_progress("boss_defeated", 1)
	var boss_name := "雾隐机关王·玄铁词尊" if (is_instance_valid(boss) and boss.is_skyfall_overlord) else "雾隐先锋·铁面词卫"
	game._notice("🏆 击败【%s】！夺得 B区撤离密钥 + 黄金核心(%d)%s%s！" % [boss_name, core_val, extra_red_msg, bp_msg], Color("ffd15c"))

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
	if rage_hunt_left > 0.0:
		attack_lock = 0.52
		return true
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
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		chance = clampf(chance * 1.55 + 0.14, 0.28, 0.88)
	elif soldier.archetype == Soldier.Archetype.SNIPER_GUARD:
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
