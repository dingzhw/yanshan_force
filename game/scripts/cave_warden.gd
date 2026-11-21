extends Node3D
## Yanxia Ancient Cave Acoustic Guardian Boss ("古洞循音石卫" · v0.8.3 Rebalanced).
## Blind karst guardian strictly guarding Yanxia Ancient Cave & immediate forecourt:
## - Detects nearby cave movement & gunshot noise within 15.0m (NEVER pulls from outer camps!)
## - Strictly leashed inside Yanxia Cave corridor (x=-44.8..-38.4, z=-67.8..-53.2; exits hunt immediately once player leaves cave)
## - Fair, beatable combat loop: 280 HP (Normal) / 440 HP (Confidential), protruding glowing cyan chest core (55/85 crit dmg),
##   armor hits deal 20/16 dmg with hit-flinch & 3D HP bar, every 80 dmg triggers a 1.4s Stagger window,
##   and [G] Smoke/EMP (5.5s) or Shaoyu [V] '天生神力' (2.5s) expose its core for massive burst damage!

const HIT_LAYER := 32  # Dedicated bit 5 for Cave Warden hitboxes (isolated from player/world masks)
const TERRITORY_CENTER := Vector3(-41.60, 6.55, -61.50)
const HEAR_RADIUS := 15.0
const TERRITORY_RADIUS := 13.5
const CAVE_MIN_X := -44.8
const CAVE_MAX_X := -38.4
const CAVE_MIN_Z := -67.8
const CAVE_MAX_Z := -53.2
const MAX_HP_NORMAL := 280
const MAX_HP_CONFIDENTIAL := 440
const STAGGER_THRESHOLD := 80

var game
var root_node: Node3D
var model_node: Node3D
var core_crystal: MeshInstance3D
var core_crystal_mat: StandardMaterial3D
var hp_bar_root: Node3D
var hp_fill: MeshInstance3D
var hp_fill_mat: StandardMaterial3D
var body_area: Area3D
var core_area: Area3D
var status_label: Label3D
var sonar_rings: Array = []

var state := "patrol"  # "patrol" | "investigate" | "hunt" | "stunned" | "defeated"
var max_hp := MAX_HP_NORMAL
var hp := MAX_HP_NORMAL
var stagger_accum := 0
var hit_flash_left := 0.0
var noise_meter := 0.0
var investigate_pos := TERRITORY_CENTER
var sonar_cd := 0.0
var attack_cd := 0.0
var stun_left := 0.0
var calm_timer := 0.0
var patrol_idx := 0
var elapsed := 0.0
var hud_ping_cd := 0.0

const PATROL_PTS := [
	Vector3(-41.60, 0.0, -56.40),
	Vector3(-41.60, 0.0, -59.80),
	Vector3(-40.30, 0.0, -62.20),
	Vector3(-41.60, 0.0, -59.00),
]

func setup(g):
	game = g
	_build_warden()
	reset()

func _build_warden():
	root_node = Node3D.new()
	root_node.name = "CaveWardenBoss"
	add_child(root_node)

	var path := "res://assets/slice/v082_bosses.glb"
	if ResourceLoader.exists(path):
		if not game.scene_cache.has(path):
			game.scene_cache[path] = load(path)
		var inst: Node3D = game.scene_cache[path].instantiate()
		var target = inst.find_child("cave_warden", true, false)
		if target is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = (target as MeshInstance3D).mesh
			mi.name = "CaveWardenMesh"
			model_node = mi
			root_node.add_child(mi)
		inst.queue_free()
	if model_node == null:
		model_node = game._mesh_box(root_node, Vector3(0, 1.35, 0), Vector3(1.2, 2.5, 0.8), Color("284852"))

	# Body hitbox (layer 32) shifted slightly behind protruding chest core so frontal chest shots ALWAYS crit core!
	body_area = Area3D.new()
	body_area.collision_layer = HIT_LAYER
	body_area.collision_mask = 0
	body_area.set_meta("cave_warden_part", "body")
	var b_col := CollisionShape3D.new()
	var b_shp := BoxShape3D.new()
	b_shp.size = Vector3(1.55, 2.48, 0.88)
	b_col.shape = b_shp
	b_col.position = Vector3(0.0, 1.30, -0.06)
	body_area.add_child(b_col)
	root_node.add_child(body_area)

	# Protruding glowing cyan sonar chest core weakpoint (clearly visible & easy to read/hit!)
	core_area = Area3D.new()
	core_area.collision_layer = HIT_LAYER
	core_area.collision_mask = 0
	core_area.set_meta("cave_warden_part", "core")
	var c_col := CollisionShape3D.new()
	var c_shp := SphereShape3D.new()
	c_shp.radius = 0.56
	c_col.shape = c_shp
	c_col.position = Vector3(0.0, 1.56, 0.56)
	core_area.add_child(c_col)
	root_node.add_child(core_area)

	core_crystal = MeshInstance3D.new()
	var c_mesh := SphereMesh.new()
	c_mesh.radius = 0.28
	c_mesh.height = 0.56
	c_mesh.radial_segments = 12
	c_mesh.rings = 8
	core_crystal.mesh = c_mesh
	core_crystal.position = Vector3(0.0, 1.56, 0.44)
	core_crystal_mat = StandardMaterial3D.new()
	core_crystal_mat.albedo_color = Color("5ef2ff")
	core_crystal_mat.emission_enabled = true
	core_crystal_mat.emission = Color("3ce6ff")
	core_crystal_mat.emission_energy_multiplier = 2.0
	core_crystal_mat.roughness = 0.18
	core_crystal.material_override = core_crystal_mat
	root_node.add_child(core_crystal)

	# Clear 3D floating HP bar right above shoulders so every bullet drop is unmistakably visible!
	hp_bar_root = Node3D.new()
	hp_bar_root.position = Vector3(0.0, 2.74, 0.0)
	root_node.add_child(hp_bar_root)
	var bg_bar: MeshInstance3D = game._mesh_box(hp_bar_root, Vector3(0.0, 0.0, -0.01), Vector3(1.64, 0.16, 0.04), Color("101b22"), false)
	(bg_bar.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_fill = game._mesh_box(hp_bar_root, Vector3(0.0, 0.0, 0.02), Vector3(1.56, 0.10, 0.04), Color("56e8ff"), false)
	hp_fill_mat = hp_fill.material_override as StandardMaterial3D
	hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	status_label = game._label3d(root_node, "古洞循音石卫 · 听声巡逻", Vector3(0.0, 3.04, 0.0), 26, Color("6cf2ff"))
	status_label.pixel_size = 0.0052
	status_label.visibility_range_end = 26.0

func _ground_pos(xz: Vector3) -> Vector3:
	if xz.z <= -58.2 and xz.x >= CAVE_MIN_X and xz.x <= CAVE_MAX_X:
		return Vector3(xz.x, 6.53, xz.z)
	return Vector3(xz.x, float(game.terrain_height(xz.x, xz.z)), xz.z)

func _clamp_to_cave(xz: Vector3) -> Vector3:
	return Vector3(clampf(xz.x, CAVE_MIN_X, CAVE_MAX_X), 0.0, clampf(xz.z, CAVE_MIN_Z, CAVE_MAX_Z))

func is_mode_active() -> bool:
	return is_instance_valid(game) and game.rules.combat_mode and not game.rules.prologue_mode

func max_hp_for_mode() -> int:
	return MAX_HP_CONFIDENTIAL if (is_instance_valid(game) and game.rules.is_confidential()) else MAX_HP_NORMAL

func reset():
	state = "patrol"
	max_hp = max_hp_for_mode()
	hp = max_hp
	stagger_accum = 0
	hit_flash_left = 0.0
	noise_meter = 0.0
	sonar_cd = 1.5
	attack_cd = 0.0
	stun_left = 0.0
	calm_timer = 0.0
	patrol_idx = 0
	hud_ping_cd = 0.0
	investigate_pos = _ground_pos(PATROL_PTS[0])
	var on := is_mode_active()
	if is_instance_valid(root_node):
		root_node.position = _ground_pos(PATROL_PTS[0])
		root_node.rotation = Vector3.ZERO
		root_node.visible = on
	if is_instance_valid(model_node):
		model_node.position = Vector3.ZERO
		model_node.rotation = Vector3.ZERO
	if is_instance_valid(body_area):
		body_area.collision_layer = HIT_LAYER if on else 0
	if is_instance_valid(core_area):
		core_area.collision_layer = HIT_LAYER if on else 0
	for r in sonar_rings:
		if is_instance_valid(r.node):
			r.node.queue_free()
	sonar_rings.clear()
	_sync_label()

func is_alive() -> bool:
	return is_mode_active() and state != "defeated"

func _sync_label():
	if is_instance_valid(hp_bar_root):
		hp_bar_root.visible = (state != "defeated" and is_mode_active())
	if is_instance_valid(hp_fill):
		var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
		hp_fill.scale.x = maxf(0.02, ratio)
		hp_fill.position.x = -1.56 * 0.5 * (1.0 - ratio)
		if is_instance_valid(hp_fill_mat):
			if state == "stunned":
				hp_fill_mat.albedo_color = Color("ffd86b")
			elif ratio <= 0.35:
				hp_fill_mat.albedo_color = Color("ff5c5c")
			elif ratio <= 0.65:
				hp_fill_mat.albedo_color = Color("ffb84d")
			else:
				hp_fill_mat.albedo_color = Color("56e8ff")
	if not is_instance_valid(status_label):
		return
	if state == "defeated":
		status_label.visible = false
		return
	status_label.visible = true
	var pct := clampi(roundi(noise_meter), 0, 100)
	match state:
		"hunt":
			status_label.text = "⚠ 古洞循音石卫 · 循声追击！  HP %d/%d" % [hp, max_hp]
			status_label.modulate = Color("ff5c5c")
		"investigate":
			status_label.text = "🌀 古洞循音石卫 · 声波搜寻 (%d%%)  HP %d/%d" % [pct, hp, max_hp]
			status_label.modulate = Color("ffd15c")
		"stunned":
			status_label.text = "💫 古洞循音石卫 · 失衡致盲 %.1fs（打蓝核暴击！） HP %d/%d" % [maxf(0.0, stun_left), hp, max_hp]
			status_label.modulate = Color("ffd86b")
		_:
			status_label.text = "古洞循音石卫 · 听声巡逻  HP %d/%d" % [hp, max_hp]
			status_label.modulate = Color("6cf2ff")

func spawn_sonar_ring(origin: Vector3, col: Color = Color("54f0ff"), max_r: float = 10.5):
	if DisplayServer.get_name() == "headless":
		return
	var ring := MeshInstance3D.new()
	var tmesh := TorusMesh.new()
	tmesh.inner_radius = 0.955
	tmesh.outer_radius = 1.0
	tmesh.rings = 32
	tmesh.ring_segments = 8
	ring.mesh = tmesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.62)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = origin + Vector3(0.0, 0.42, 0.0)
	ring.scale = Vector3(0.45, 0.16, 0.45)
	add_child(ring)
	sonar_rings.append({"node": ring, "mat": mat, "age": 0.0, "dur": 1.15, "max_r": max_r})

func _update_sonar_rings(delta: float):
	for i in range(sonar_rings.size() - 1, -1, -1):
		var sr: Dictionary = sonar_rings[i]
		sr.age += delta
		var nd: MeshInstance3D = sr.node
		if sr.age >= sr.dur or not is_instance_valid(nd):
			if is_instance_valid(nd):
				nd.queue_free()
			sonar_rings.remove_at(i)
			continue
		var u: float = sr.age / sr.dur
		var rad := lerpf(0.45, float(sr.max_r), 1.0 - pow(1.0 - u, 2.2))
		nd.scale = Vector3(rad, 0.16, rad)
		(sr.mat as StandardMaterial3D).albedo_color.a = (1.0 - u) * 0.58

func _player_inside_cave_territory(pos: Vector3) -> bool:
	return Vector2(pos.x - TERRITORY_CENTER.x, pos.z - TERRITORY_CENTER.z).length() <= TERRITORY_RADIUS and pos.z <= -51.5

func register_noise(source_pos: Vector3, intensity: float, immediate_ping: bool = false):
	if not is_alive() or state == "stunned":
		return
	var dist := root_node.position.distance_to(source_pos)
	if dist > HEAR_RADIUS:
		return
	var atten := clampf(1.0 - dist / HEAR_RADIUS, 0.0, 1.0)
	var gained := intensity * (0.30 + 0.70 * atten)
	if gained <= 0.01:
		return
	noise_meter = minf(100.0, noise_meter + gained)
	investigate_pos = _ground_pos(_clamp_to_cave(source_pos))
	calm_timer = 0.0
	if noise_meter >= 75.0:
		if state != "hunt":
			state = "hunt"
			game.play_sfx("warden_sonar", -7)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 11.5)
			if is_instance_valid(game.player):
				game.player.add_screen_shake(0.28)
			game._notice("⚠ 古洞循音石卫惊醒追击！瞄准胸前发光蓝核高额暴击，或用 [G]烟雾 / [V]天生神力 震晕它（撤出洞口即脱战）！", Color("ff6b6b"))
	elif noise_meter >= 30.0 and state == "patrol":
		state = "investigate"
		game.play_sfx("warden_sonar", -11)
		spawn_sonar_ring(root_node.position, Color("54f0ff"), 10.0)
		game._notice("🌀 古洞循音石卫听到了动静！按 [C] 蹲行或 [Z] 匍匐静默，或瞄准胸前蓝核先手开火！", Color("7ceeff"))
	elif immediate_ping and sonar_cd <= 0.0:
		sonar_cd = 1.6
		game.play_sfx("warden_sonar", -12)
		spawn_sonar_ring(root_node.position, Color("ff8052") if state == "hunt" else Color("54f0ff"), 10.5)
	_sync_label()

func on_gunshot(origin: Vector3, suppressed: bool):
	if not is_alive():
		return
	register_noise(origin, 22.0 if suppressed else 64.0, true)

func on_smoke_emp(origin: Vector3):
	if not is_alive():
		return
	if root_node.position.distance_to(origin) <= 13.5:
		state = "stunned"
		stun_left = 5.5
		noise_meter = 10.0
		game._notice("✦ 烟雾 EMP 致盲古洞循音石卫 5.5 秒！趁现在集火胸前蓝核（每枪 85 暴击伤害）！", Color("7ceeff"))
		_sync_label()

func _deliver_sonic_retaliation(is_close_slam: bool = false):
	if not is_alive() or state == "stunned" or not is_instance_valid(game.player):
		return
	if is_instance_valid(game.combat) and game.combat.player_in_smoke():
		return
	var is_conf: bool = game.rules.is_confidential()
	attack_cd = (2.10 if is_conf else 2.60) if not is_close_slam else (2.25 if is_conf else 2.75)
	spawn_sonar_ring(root_node.position, Color("ff3b30"), 11.0 if is_conf else 9.5)
	game.play_sfx("warden_sonar", -6)
	game.player.add_screen_shake(0.42 if is_close_slam else 0.30)
	var push_dir: Vector3 = game.player.position - root_node.position
	push_dir.y = 0.0
	if push_dir.length() > 0.05:
		game.player.apply_knockback(push_dir.normalized() * (6.8 if is_close_slam else 4.6) + Vector3(0, 1.8, 0))
	var dmg: int = (34 if is_conf else 24) if is_close_slam else (24 if is_conf else 16)
	if is_instance_valid(game.combat) and game.rules.combat_mode:
		game.combat.apply_player_damage(dmg)
	game._notice("💥 古洞循音石卫释放%s（-%d 伤害）！打胸前蓝核可将其打进失衡硬直，或按 [G]/[V] 震晕！" % [
		"重锤震地" if is_close_slam else "声波冲击", dmg
	], Color("ff7a6b"))

func hit_bullet(collider) -> bool:
	if not is_alive() or not (collider is Object):
		return false
	if not collider.has_meta("cave_warden_part"):
		return false
	var part := str(collider.get_meta("cave_warden_part"))
	var is_conf: bool = game.rules.is_confidential()
	var dmg := 0
	var is_crit := (part == "core")
	if is_crit:
		if state == "stunned":
			dmg = 70 if is_conf else 85
		else:
			dmg = 45 if is_conf else 55
	else:
		dmg = 16 if is_conf else 20
	hp = maxi(0, hp - dmg)
	stagger_accum += dmg
	hit_flash_left = 0.16
	game.show_hitmarker(is_crit)
	game.play_sfx("hit_correct" if is_crit else "knife_hit", -9)

	var triggered_stagger := false
	if hp > 0 and state != "stunned" and stagger_accum >= STAGGER_THRESHOLD:
		stagger_accum = 0
		state = "stunned"
		stun_left = 1.4
		triggered_stagger = true
		spawn_sonar_ring(root_node.position, Color("ffd86b"), 8.5)
		game.play_sfx("boss_phase", -11)

	if not triggered_stagger and state != "stunned":
		register_noise(game.player.position, 68.0, true)

	if hp <= 0:
		_on_defeated()
	else:
		_sync_label()
		if triggered_stagger:
			game._notice("⚡ 击破石卫平衡！古洞循音石卫陷入失衡硬直 1.4 秒（剩余 %d/%d HP · 趁机速射蓝核！）" % [hp, max_hp], Color("ffd86b"))
		elif is_crit:
			game._notice("✦ 暴击石卫发光蓝核 -%d HP！（剩余 %d/%d HP）" % [dmg, hp, max_hp], Color("7ceeff"))
		else:
			game._notice("💥 命中石卫岩甲 -%d HP（剩余 %d/%d HP · 瞄准胸前发光蓝核可触发 3 倍暴击！）" % [dmg, hp, max_hp], Color("ffe08c"))
	return true

func _on_defeated():
	state = "defeated"
	noise_meter = 0.0
	body_area.collision_layer = 0
	core_area.collision_layer = 0
	spawn_sonar_ring(root_node.position, Color("7af5cc"), 13.0)
	game.play_sfx("boss_phase", -9)
	if is_instance_valid(game.player):
		game.player.add_screen_shake(0.38)
	if is_instance_valid(root_node):
		root_node.hide()
	game.rules.score += 80
	var loot_msg := ""
	if game.rules.can_loot():
		var is_conf: bool = game.rules.operation_tier == "confidential"
		var rarity := (7 if randf() < 0.28 else 6) if is_conf else (6 if randf() < 0.25 else 5)
		var item: Dictionary = game.rules.roll_item_by_rarity(rarity)
		if game.rules.add_loot_item(item):
			loot_msg = " · 掉落【%s】%s（%d币）" % [game.Rules.RARITY_NAMES[rarity], item.title, int(item.value)]
		else:
			loot_msg = " · 背包已满，已折算 +120 行动币"
			game.rules.profile.coins += 120
	if is_instance_valid(game.achievements):
		game.achievements.record_stat("cave_warden_defeated", 1)
	if is_instance_valid(game.rangers):
		game.rangers.unlock_card("cave_warden", false)
		game.rangers.record_bounty_progress("warden_defeated", 1)
	game._notice("★ 成功击败【古洞循音石卫】！+80 积分%s" % loot_msg, game.GOLD)
	_sync_label()

func update(delta: float):
	_update_sonar_rings(delta)
	if not is_alive() or game.paused or not is_instance_valid(game.player):
		return
	elapsed += delta
	sonar_cd = maxf(0.0, sonar_cd - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	hud_ping_cd = maxf(0.0, hud_ping_cd - delta)
	if hit_flash_left > 0.0:
		hit_flash_left = maxf(0.0, hit_flash_left - delta)

	# Visual hit-flinch recoil & pulsing cyan chest crystal
	if is_instance_valid(core_crystal_mat):
		if hit_flash_left > 0.0:
			core_crystal_mat.albedo_color = Color("ffffff")
			core_crystal_mat.emission = Color("ffd86b")
			core_crystal_mat.emission_energy_multiplier = 4.2
		elif state == "stunned":
			core_crystal_mat.albedo_color = Color("ffd86b")
			core_crystal_mat.emission = Color("ffae34")
			core_crystal_mat.emission_energy_multiplier = 3.0 + sin(elapsed * 14.0) * 0.8
		else:
			core_crystal_mat.albedo_color = Color("5ef2ff")
			core_crystal_mat.emission = Color("3ce6ff")
			core_crystal_mat.emission_energy_multiplier = 1.9 + sin(elapsed * 5.0) * 0.4

	if is_instance_valid(hp_bar_root) and is_instance_valid(game.player.camera):
		var cam_p: Vector3 = game.player.camera.global_position
		var to_cam := Vector3(cam_p.x - hp_bar_root.global_position.x, 0.0, cam_p.z - hp_bar_root.global_position.z)
		if to_cam.length_squared() > 0.04:
			hp_bar_root.global_rotation.y = atan2(to_cam.x, to_cam.z)

	if state == "stunned":
		stun_left -= delta
		if is_instance_valid(model_node):
			model_node.rotation.x = lerpf(model_node.rotation.x, -0.34, minf(delta * 10.0, 1.0))
			model_node.position.z = lerpf(model_node.position.z, -0.14 if hit_flash_left > 0.0 else 0.0, minf(delta * 16.0, 1.0))
		_sync_label()
		if stun_left <= 0.0:
			state = "patrol"
			if is_instance_valid(model_node):
				model_node.rotation.x = 0.0
			_sync_label()
		return

	var ppos: Vector3 = game.player.position
	var dist_p := root_node.position.distance_to(ppos)
	var player_in_cave := _player_inside_cave_territory(ppos)

	# Strictly enforce Yanxia Cave territory leash: exiting the cave IMMEDIATELY breaks hunt!
	if state in ["hunt", "investigate"] and not player_in_cave:
		if state == "hunt":
			game._notice("✦ 已离开烟霞古洞范围，古洞循音石卫退回洞内巡逻。", game.MINT)
		state = "patrol"
		noise_meter = 0.0
		_sync_label()

	# Continuous footstep noise sensing strictly inside Yanxia Cave!
	var hspeed := Vector2(game.player.velocity.x, game.player.velocity.z).length()
	if player_in_cave and dist_p <= HEAR_RADIUS and hspeed > 0.35:
		var stance: int = game.player.stance
		var rate := 0.6 if stance == game.player.STANCE_PRONE else (2.8 if stance == game.player.STANCE_CROUCH else (34.0 if hspeed > 5.0 else 15.0))
		register_noise(ppos, rate * delta, false)
	elif player_in_cave and dist_p < 3.4 and game.player.stance != game.player.STANCE_PRONE:
		register_noise(ppos, 24.0 * delta, false)
	else:
		var drain := 18.0 if state == "patrol" else (13.0 if state == "investigate" else 8.0)
		noise_meter = maxf(0.0, noise_meter - drain * delta)
		calm_timer += delta
		if state == "investigate" and (noise_meter <= 8.0 or calm_timer >= 4.5):
			state = "patrol"
			_sync_label()

	# Movement & fair sonic attack rhythm (strictly confined inside Yanxia Cave!)
	var move_target := root_node.position
	var move_speed := 1.65
	if state == "hunt":
		move_target = _ground_pos(_clamp_to_cave(ppos))
		var is_conf_m: bool = game.rules.is_confidential()
		move_speed = 4.55 if is_conf_m else 3.85
		if sonar_cd <= 0.0:
			sonar_cd = 2.4
			game.play_sfx("warden_sonar", -9)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 11.0)
		var blast_range := 11.0 if is_conf_m else 9.5
		if player_in_cave and dist_p <= blast_range and attack_cd <= 0.0 and game.rules.combat_mode:
			_deliver_sonic_retaliation(dist_p < 3.8)
	elif state == "investigate":
		move_target = _ground_pos(_clamp_to_cave(investigate_pos))
		move_speed = 2.55
		if sonar_cd <= 0.0:
			sonar_cd = 2.5
			game.play_sfx("warden_sonar", -12)
			spawn_sonar_ring(root_node.position, Color("54f0ff"), 9.5)
	else:
		var wp := _ground_pos(PATROL_PTS[patrol_idx])
		if Vector2(wp.x - root_node.position.x, wp.z - root_node.position.z).length() < 0.75:
			patrol_idx = (patrol_idx + 1) % PATROL_PTS.size()
			wp = _ground_pos(PATROL_PTS[patrol_idx])
		move_target = wp
		move_speed = 1.65

	var flat_delta := Vector2(move_target.x - root_node.position.x, move_target.z - root_node.position.z)
	var stop_dist := 2.4 if state == "hunt" else 0.45
	if flat_delta.length() > stop_dist:
		var step := flat_delta.normalized() * minf(move_speed * delta, flat_delta.length() - stop_dist)
		var next_xz := _clamp_to_cave(Vector3(root_node.position.x + step.x, 0.0, root_node.position.z + step.y))
		root_node.position = _ground_pos(next_xz)
	if state == "hunt":
		var face_p := Vector2(ppos.x - root_node.position.x, ppos.z - root_node.position.z)
		if face_p.length() > 0.25:
			root_node.rotation.y = lerp_angle(root_node.rotation.y, atan2(face_p.x, face_p.y), minf(delta * 6.5, 1.0))
	elif flat_delta.length() > 0.25:
		root_node.rotation.y = lerp_angle(root_node.rotation.y, atan2(flat_delta.x, flat_delta.y), minf(delta * 5.0, 1.0))

	if is_instance_valid(model_node):
		var flinch_z := -0.16 if hit_flash_left > 0.0 else 0.0
		var flinch_rx := -0.18 if hit_flash_left > 0.0 else 0.0
		model_node.position.y = absf(sin(elapsed * (4.6 if state == "hunt" else 2.2))) * 0.055
		model_node.position.z = lerpf(model_node.position.z, flinch_z, minf(delta * 20.0, 1.0))
		model_node.rotation.x = lerpf(model_node.rotation.x, flinch_rx, minf(delta * 20.0, 1.0))
