extends Node3D
## Multi-archetype tactical outpost combat manager with armor-shatter word shields, physical HP/weakpoints, Smoke/EMP tactical zones, and Zone-B Armored Boss.

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
var boss_unit = null
var waves_done = {}
var waves_target = {}
var zone_cleared = {}
var smoke_zones = []
var danger_rings = []

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
	boss_unit = null
	smoke_zones.clear()
	danger_rings.clear()
	shot_rng.randomize()
	_deploy()

func stop():
	stage = Stage.OFF
	zone = -1
	boss_unit = null
	smoke_zones.clear()
	danger_rings.clear()
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
	for s_idx in game.stations.size():
		game.stations[s_idx].enable_boards(true)

func in_warmup() -> bool:
	return false

func in_field() -> bool:
	return stage == Stage.FIELD

func player_in_smoke() -> bool:
	if not is_instance_valid(game.player):
		return false
	for sz in smoke_zones:
		if game.player.position.distance_to(sz.pos) <= float(sz.radius):
			return true
	return false

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
			var boss_blocking: bool = zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated
			if waves_done[zone] >= waves_target[zone] and not boss_blocking:
				_mark_zone_cleared(zone)
	else:
		rage_left = RAGE_SECONDS

func _mark_zone_cleared(z_idx: int):
	if zone_cleared.get(z_idx, false):
		return
	zone_cleared[z_idx] = true
	game.rules.outposts_cleared += 1
	game.rules.score += game.Rules.OUTPOST_CLEAR_SCORE
	game.player.medkits += 1
	game.player.add_reserve_ammo(game.rules.magazine())
	game.play_sfx("loot_epic", -11)
	game._notice("★ 已攻克【%s】！ +%d 积分 · 医疗包+1 备弹+%d（前哨 %d/2）" % [
		zone_info(z_idx).title, game.Rules.OUTPOST_CLEAR_SCORE, game.rules.magazine(), game.rules.outposts_cleared
	], game.MINT)

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

	# Update Smoke/EMP tactical zones
	for i in range(smoke_zones.size() - 1, -1, -1):
		var sz = smoke_zones[i]
		sz.left -= delta
		if sz.left <= 0:
			if is_instance_valid(sz.node):
				sz.node.queue_free()
			smoke_zones.remove_at(i)
		elif sz.left < 1.8 and is_instance_valid(sz.node):
			sz.node.scale = Vector3.ONE * clampf(sz.left / 1.8, 0.15, 1.0)

	# Update Boss telegraphed crimson Danger Rings
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
			if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
				game._notice("⚠ 进入【B区首领高地】：铁甲词尊现身！破除词盾开启胸口核心弱点！", Color("ffd15c"))
				game.play_sfx("boss_phase", -11)
			else:
				game._notice("进入交战区：%s（%s）· 注意无人机包抄与狙击红线！" % [z_title, prog], game.GOLD)
		else:
			game._sync_question()

func _squad_archetypes(z_idx: int) -> Array:
	if z_idx == 0:
		return [Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT, Soldier.Archetype.SCOUT_DRONE]
	if z_idx == 1:
		return [Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT]
	return [Soldier.Archetype.BOSS_WARDEN, Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.SCOUT_DRONE, Soldier.Archetype.ASSAULT_BOT]

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
			if archetypes[i] == Soldier.Archetype.BOSS_WARDEN:
				boss_unit = soldier
		troops[z_idx] = soldiers
	game.player.ammo = game.rules.magazine()
	game.player.reserve_ammo = game.rules.starter_reserve_ammo()
	game.player.reload_left = 0.0
	game._next_question()

func show_question():
	if zone < 0:
		if game.active_station == 0:
			return
		game.question_label.text = "沿山路破哨 · 击败B区首领并搜刮补给"
		game.unit_label.text = "撤离要求：积分 %d · 攻克 %d/2 前哨 · 首领密钥 %d/1" % [
			game.Rules.EXTRACTION_SCORE, game.rules.outposts_cleared, 1 if game.rules.boss_defeated else 0
		]
		return
	if zone == 2 and game.rules.boss_defeated and game.rules.question_open and is_instance_valid(boss_unit) and troops[2][0] == boss_unit:
		var remnant = Soldier.new()
		arena.add_child(remnant)
		remnant.setup(self, 2, 0, boss_unit.cover, Soldier.Archetype.ASSAULT_BOT)
		troops[2][0] = remnant
	for slot_i in troops[zone].size():
		var soldier = troops[zone][slot_i]
		if slot_i >= 4:
			soldier.show_word("", false)
		else:
			soldier.show_word(game.choices[soldier.option].english, game.rules.question_open)
	if game.listening_mode and game.rules.question_open:
		game.question_label.text = "🔊 电台截获英文语音 · 按 [Q] 重播读音"
	else:
		game.question_label.text = game.question.chinese
	var z_title = zone_info(zone).title
	var boss_suffix := (" | ★统领 %d/450" % boss_unit.hp) if (zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated) else ""
	var wave_str = "已占领" if zone_cleared.get(zone, false) else ("波次 %d/%d" % [waves_done.get(zone, 0), waves_target.get(zone, 4)])
	game.unit_label.text = "%s（%s）%s  |  [Q] 读音" % [z_title, wave_str, boss_suffix]
	if not game.rules.question_open:
		game.unit_label.text = "目标护盾已击破 · 可趁硬直射击核心或迎击下波…"

func _resolve_soldier_node(collider):
	var cur := collider as Node
	while is_instance_valid(cur):
		if cur is Soldier:
			return cur
		cur = cur.get_parent()
	return null

func hit(collider) -> bool:
	return hit_bullet(collider, "", Vector3.ZERO)

func hit_bullet(collider, muzzle_id: String = "", _hit_pos: Vector3 = Vector3.ZERO) -> bool:
	var soldier = _resolve_soldier_node(collider)
	if not (soldier is Soldier) or soldier.zone != zone or soldier.defeated:
		return false
	if muzzle_id != "suppressor":
		for other in troops.get(zone, []):
			if not other.defeated and other.action == Soldier.Action.PATROL:
				other.action = Soldier.Action.ADVANCE
	if collider == soldier.shield_area:
		if game.rules.question_open:
			game.resolve_answer(soldier.option, true)
			return true
		soldier.apply_damage(12, false, false)
		return true
	var hit_zone := str(collider.get_meta("hit_zone", "body")) if collider is Object and collider.has_meta("hit_zone") else "body"
	var dmg := 12
	var is_crit := false
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		if hit_zone == "core" and soldier.exposed_left > 0:
			dmg = 42
			is_crit = true
			game._notice("★ 命中首领暴露核心！暴击 -%d HP" % dmg, Color("ffd15c"))
		elif hit_zone == "head":
			dmg = 16
			is_crit = true
		else:
			dmg = 6
			game._notice("重甲减伤 -%d！打中正确英文词盾破防开启核心！" % dmg)
	else:
		if hit_zone == "head":
			dmg = 28
			is_crit = true
		else:
			dmg = 12
	game.show_hitmarker(is_crit)
	var killed: bool = soldier.apply_damage(dmg, false, is_crit)
	_on_soldier_physical_hit(soldier, killed, "bullet")
	return true

func melee_strike(camera: Camera3D) -> bool:
	if not in_field() or zone < 0 or not troops.has(zone):
		return false
	var cam_pos := camera.global_position
	var cam_fwd := (-camera.global_transform.basis.z).normalized()
	var best_soldier = null
	var best_dist := 3.45
	for s in troops[zone]:
		if s.defeated:
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
	var enemy_fwd: Vector3 = (best_soldier.global_transform.basis.z).normalized()
	var to_player: Vector3 = (game.player.global_position - best_soldier.global_position).normalized()
	var backstab: bool = enemy_fwd.dot(to_player) < -0.15
	var dmg: int = 115 if (backstab and best_soldier.archetype != Soldier.Archetype.BOSS_WARDEN) else (85 if (backstab or best_soldier.stun_left > 0 or best_soldier.exposed_left > 0) else 52)
	game.play_sfx("knife_hit", -8)
	game.show_hitmarker(backstab or best_soldier.stun_left > 0)
	var killed: bool = best_soldier.apply_damage(dmg, false, backstab)
	if killed:
		var mag_gain: int = game.rules.magazine()
		game.player.add_reserve_ammo(mag_gain)
		game.rules.score += 12 if backstab else 8
		game._notice("%s！近战击杀回收 +%d 备弹！" % ["背后致命处决" if backstab else "匕首战术斩杀", mag_gain], game.MINT)
	else:
		game._notice("匕首斩击 -%d HP！" % dmg, Color("ffd27d"))
	_on_soldier_physical_hit(best_soldier, killed, "knife")
	return true

func _on_soldier_physical_hit(soldier, killed: bool, _source: String):
	if not killed:
		return
	if soldier.archetype == Soldier.Archetype.BOSS_WARDEN:
		_on_boss_defeated(soldier)
	else:
		var ammo_drop := 5
		if _source != "knife":
			game.player.add_reserve_ammo(ammo_drop)
			game.rules.score += 8
		var all_down := true
		for s in troops[zone]:
			if not s.defeated:
				all_down = false
				break
		if all_down and not zone_cleared.get(zone, false):
			record_field(true)
			game.next_question_left = 0.75
		elif not all_down and soldier.option == game.answer_index and game.rules.question_open:
			game.rules.question_open = false
			game.next_question_left = 0.55
			show_question()

func hit_feedback(index: int, correct: bool):
	var soldier = troops[zone][index]
	if correct:
		if zone == 2 and is_instance_valid(boss_unit) and not boss_unit.defeated:
			if soldier == boss_unit:
				boss_unit.apply_damage(180, true, true)
			else:
				soldier.apply_damage(240, true, true)
				boss_unit.apply_damage(150, true, true)
			if boss_unit.defeated:
				_on_boss_defeated(boss_unit)
		else:
			soldier.apply_damage(240, true, true)
			game.player.add_reserve_ammo(4)
	else:
		soldier.apply_damage(0, false, false)

func on_boss_phase_shift(boss, next_phase: int):
	game.play_sfx("boss_phase", -9)
	game._notice("★ 铁甲词尊 进入第 %d 阶段！胸口核心短暂暴露，快集火或再破一盾！" % (4 - next_phase), Color("ffd15c"))
	_spawn_boss_support_drone(boss)

func _spawn_boss_support_drone(boss):
	if not is_instance_valid(arena) or not is_instance_valid(boss):
		return
	var offset := Vector3(-3.5 if shot_rng.randf() < 0.5 else 3.5, 0, -2.5)
	var spot: Vector3 = game.Layout.on_ground(boss.position + offset)
	var drone = Soldier.new()
	arena.add_child(drone)
	var next_opt: int = (troops[2].size()) % 4
	drone.setup(self, 2, next_opt, spot, Soldier.Archetype.SCOUT_DRONE)
	drone.show_word("", false)
	troops[2].append(drone)

func _on_boss_defeated(boss):
	if game.rules.boss_defeated:
		return
	game.rules.boss_defeated = true
	game.rules.score += game.Rules.BOSS_DEFEAT_SCORE
	game.player.add_reserve_ammo(game.rules.magazine())
	_mark_zone_cleared(2)
	var core_item := {"title": "烟山统领黄金核心", "value": 380, "rarity": 5}
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
	game._notice("🏆 击败【铁甲词尊 · 烟山统领】！夺得 B区撤离密钥 + 黄金核心(380)%s · B 点已解锁！" % bp_msg, Color("ffd15c"))

func deploy_smoke_emp(center: Vector3):
	if not is_instance_valid(arena):
		return
	var root = Node3D.new()
	var gpos: Vector3 = game.Layout.on_ground(center)
	root.position = gpos
	arena.add_child(root)
	# EMP expanding cyan ring + billowing translucent tactical smoke clouds
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
	for i in 9:
		var puffs = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 1.65 + float(i % 3) * 0.42
		sm.height = 2.4 + float(i % 2) * 0.45
		sm.radial_segments = 14
		sm.rings = 8
		puffs.mesh = sm
		var ang := TAU * float(i) / 8.0 if i < 8 else 0.0
		var ring_r := 1.65 if i < 8 else 0.0
		puffs.position = Vector3(cos(ang) * ring_r, 1.05 + float(i % 3) * 0.30, sin(ang) * ring_r)
		puffs.scale = Vector3(1.15, 0.78, 1.15)
		puffs.material_override = smoke_mat
		root.add_child(puffs)

	smoke_zones.append({"pos": gpos, "left": 8.0, "radius": 5.5, "node": root})
	var stunned := 0
	for z_list in troops.values():
		for s in z_list:
			if not s.defeated and s.position.distance_to(gpos) <= 9.0:
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

func clear_shot(at: Vector3) -> bool:
	if player_in_smoke():
		return false
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

func apply_player_damage(damage: int):
	shield_delay = SHIELD_REGEN_DELAY
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

func strike(soldier):
	if not in_field() or game.paused or soldier.defeated or soldier.zone != zone or soldier.stun_left > 0:
		return
	if is_instance_valid(game.exploration) and game.exploration.safe():
		return
	if soldier.position.distance_to(game.player.position) > soldier.attack_range() or not clear_shot(soldier.position):
		return
	var from: Vector3 = soldier.position + Vector3.UP * (2.10 if soldier.archetype == Soldier.Archetype.BOSS_WARDEN else 1.54)
	var to: Vector3 = game.player.position + Vector3.UP * 1.26
	var chance := hit_chance()
	if soldier.archetype in [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.BOSS_WARDEN]:
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
	var beam_col = Color("ff5d6c") if soldier.archetype in [Soldier.Archetype.SNIPER_GUARD, Soldier.Archetype.BOSS_WARDEN] else Color("ffc483")
	var trace = game._mesh_box(arena, (from + to) / 2, Vector3(0.032, 0.032, from.distance_to(to)), beam_col)
	trace.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trace_up := Vector3.RIGHT if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	trace.look_at(to, trace_up)
	trace.create_tween().tween_callback(trace.queue_free).set_delay(0.14)
	game.play_sound("enemy_attack", -19)
	if not hits_player:
		miss_left = 1.2
		return
	miss_left = 0.0
	apply_player_damage(damage_per_shot(soldier))
