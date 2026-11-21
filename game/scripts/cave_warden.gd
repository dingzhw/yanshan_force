extends Node3D
## Yanxia Ancient Cave Acoustic Guardian Boss ("古洞循音石卫" · v0.8.2 #2).
## Blind karst guardian patrolling Yanxia Ancient Cave:
## - Detects player movement & gunshot noise (Prone [Z] near-silent, Crouch [C] quiet, Walk/Sprint/Gunfire loud)
## - Emits visible 3D cyan sonar rings when investigating sound sources
## - Hunts aggressively within 42m cavern territory when locked, countered by stealth, [G] smoke/EMP, or shooting its glowing sonar core!

const HIT_LAYER := 32  # Dedicated bit 5 for Cave Warden hitboxes (isolated from player/world masks)
const TERRITORY_CENTER := Vector3(-41.60, 6.55, -60.20)
const HEAR_RADIUS := 38.0
const TERRITORY_RADIUS := 42.0
const MAX_HP_NORMAL := 620
const MAX_HP_CONFIDENTIAL := 960

var game
var root_node: Node3D
var model_node: Node3D
var body_area: Area3D
var core_area: Area3D
var status_label: Label3D
var sonar_rings: Array = []

var state := "patrol"  # "patrol" | "investigate" | "hunt" | "stunned" | "defeated"
var max_hp := MAX_HP_NORMAL
var hp := MAX_HP_NORMAL
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

	# Body hitbox (layer 32)
	body_area = Area3D.new()
	body_area.collision_layer = HIT_LAYER
	body_area.collision_mask = 0
	body_area.set_meta("cave_warden_part", "body")
	var b_col := CollisionShape3D.new()
	var b_shp := BoxShape3D.new()
	b_shp.size = Vector3(1.65, 2.55, 1.05)
	b_col.shape = b_shp
	b_col.position = Vector3(0.0, 1.32, 0.0)
	body_area.add_child(b_col)
	root_node.add_child(body_area)

	# Glowing cyan sonar chest core weakpoint (2x crit damage!)
	core_area = Area3D.new()
	core_area.collision_layer = HIT_LAYER
	core_area.collision_mask = 0
	core_area.set_meta("cave_warden_part", "core")
	var c_col := CollisionShape3D.new()
	var c_shp := SphereShape3D.new()
	c_shp.radius = 0.44
	c_col.shape = c_shp
	c_col.position = Vector3(0.0, 1.56, 0.24)
	core_area.add_child(c_col)
	root_node.add_child(core_area)

	status_label = game._label3d(root_node, "古洞循音石卫 · 巡逻中", Vector3(0.0, 3.05, 0.0), 26, Color("6cf2ff"))
	status_label.pixel_size = 0.0052
	status_label.visibility_range_end = 42.0

func _ground_pos(xz: Vector3) -> Vector3:
	if xz.z <= -58.2 and xz.x >= -44.8 and xz.x <= -38.4:
		return Vector3(xz.x, 6.53, xz.z)
	return Vector3(xz.x, float(game.terrain_height(xz.x, xz.z)), xz.z)

func is_mode_active() -> bool:
	return is_instance_valid(game) and game.rules.combat_mode and not game.rules.prologue_mode

func max_hp_for_mode() -> int:
	return MAX_HP_CONFIDENTIAL if (is_instance_valid(game) and game.rules.is_confidential()) else MAX_HP_NORMAL

func reset():
	state = "patrol"
	max_hp = max_hp_for_mode()
	hp = max_hp
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
	if not is_instance_valid(status_label):
		return
	if state == "defeated":
		status_label.visible = false
		return
	status_label.visible = true
	var pct := clampi(roundi(noise_meter), 0, 100)
	match state:
		"hunt":
			status_label.text = "⚠ 古洞循音石卫 · 循声猎杀！  HP %d/%d" % [hp, max_hp]
			status_label.modulate = Color("ff5c5c")
		"investigate":
			status_label.text = "🌀 古洞循音石卫 · 声波搜寻 (%d%%)  HP %d/%d" % [pct, hp, max_hp]
			status_label.modulate = Color("ffd15c")
		"stunned":
			status_label.text = "✦ 古洞循音石卫 · 声纹致盲中(核心易伤)  HP %d/%d" % [hp, max_hp]
			status_label.modulate = Color("9ef5e2")
		_:
			status_label.text = "古洞循音石卫 · 听声巡逻  HP %d/%d" % [hp, max_hp]
			status_label.modulate = Color("6cf2ff")

func spawn_sonar_ring(origin: Vector3, col: Color = Color("54f0ff"), max_r: float = 11.5):
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

func register_noise(source_pos: Vector3, intensity: float, immediate_ping: bool = false):
	if not is_alive() or state == "stunned":
		return
	var dist := root_node.position.distance_to(source_pos)
	if dist > HEAR_RADIUS:
		return
	var atten := clampf(1.0 - dist / HEAR_RADIUS, 0.0, 1.0)
	var gained := intensity * (0.28 + 0.72 * atten)
	if gained <= 0.01:
		return
	noise_meter = minf(100.0, noise_meter + gained)
	investigate_pos = source_pos
	calm_timer = 0.0
	if noise_meter >= 75.0:
		if state != "hunt":
			state = "hunt"
			game.play_sfx("warden_sonar", -7)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 14.5)
			if is_instance_valid(game.player):
				game.player.add_screen_shake(0.32)
			game._notice("⚠ 古洞循音石卫循声锁定！可用 [G] 烟雾致盲、撤出 42m 领地或击破胸前幽蓝晶核！", Color("ff6b6b"))
	elif noise_meter >= 30.0 and state == "patrol":
		state = "investigate"
		game.play_sfx("warden_sonar", -11)
		spawn_sonar_ring(root_node.position, Color("54f0ff"), 11.5)
		game._notice("🌀 古洞循音石卫听到了动静！按 [C] 蹲行或 [Z] 匍匐保持静默可躲过声波探测！", Color("7ceeff"))
	elif immediate_ping and sonar_cd <= 0.0:
		sonar_cd = 1.6
		game.play_sfx("warden_sonar", -12)
		spawn_sonar_ring(root_node.position, Color("ff8052") if state == "hunt" else Color("54f0ff"), 12.0)
	_sync_label()

func on_gunshot(origin: Vector3, suppressed: bool):
	if not is_alive():
		return
	register_noise(origin, 24.0 if suppressed else 68.0, true)

func on_smoke_emp(origin: Vector3):
	if not is_alive():
		return
	if root_node.position.distance_to(origin) <= 13.5:
		state = "stunned"
		stun_left = 5.5
		noise_meter = 10.0
		game._notice("✦ 烟雾 EMP 干扰了古洞循音石卫的听音角冠！致盲 5.5 秒，趁机潜行或集火胸核！", Color("7ceeff"))
		_sync_label()

func _deliver_sonic_retaliation(is_close_slam: bool = false):
	if not is_alive() or state == "stunned" or not is_instance_valid(game.player):
		return
	if is_instance_valid(game.combat) and game.combat.player_in_smoke():
		return
	var is_conf: bool = game.rules.is_confidential()
	attack_cd = (1.05 if is_conf else 1.35) if not is_close_slam else (1.25 if is_conf else 1.55)
	spawn_sonar_ring(root_node.position, Color("ff3b30"), 15.0 if is_conf else 13.0)
	game.play_sfx("warden_sonar", -5)
	game.player.add_screen_shake(0.58 if is_close_slam else 0.44)
	var push_dir: Vector3 = game.player.position - root_node.position
	push_dir.y = 0.0
	if push_dir.length() > 0.05:
		game.player.apply_knockback(push_dir.normalized() * (9.5 if is_close_slam else 6.2) + Vector3(0, 2.6, 0))
	var dmg: int = (52 if is_conf else 34) if is_close_slam else (40 if is_conf else 26)
	if is_instance_valid(game.combat) and game.rules.combat_mode:
		game.combat.apply_player_damage(dmg)
	game._notice("💥 古洞循音石卫释放%s（-%d 伤害）！请蹲趴潜行或投掷 [G] 烟雾致盲后再击破胸核！" % [
		"重锤震地" if is_close_slam else "高能反击声波", dmg
	], Color("ff5c5c"))

func hit_bullet(collider) -> bool:
	if not is_alive() or not (collider is Object):
		return false
	if not collider.has_meta("cave_warden_part"):
		return false
	var part := str(collider.get_meta("cave_warden_part"))
	var is_conf: bool = game.rules.is_confidential()
	var dmg := 0
	if part == "core":
		if state == "stunned":
			dmg = 38 if is_conf else 42
		else:
			dmg = 24 if is_conf else 28
	else:
		dmg = 6 if is_conf else 8
	hp = maxi(0, hp - dmg)
	game.show_hitmarker(part == "core")
	game.play_sfx("hit_correct" if part == "core" else "dry_fire", -10)
	var was_stunned := (state == "stunned")
	register_noise(game.player.position, 88.0, true)
	if hp <= 0:
		_on_defeated()
	else:
		_sync_label()
		if not was_stunned and attack_cd <= 0.0 and is_instance_valid(game.player):
			var dist_p := root_node.position.distance_to(game.player.position)
			if dist_p <= (15.5 if is_conf else 13.5):
				_deliver_sonic_retaliation(dist_p < 4.6)
	return true

func _on_defeated():
	state = "defeated"
	noise_meter = 0.0
	body_area.collision_layer = 0
	core_area.collision_layer = 0
	spawn_sonar_ring(root_node.position, Color("7af5cc"), 16.0)
	game.play_sfx("boss_phase", -9)
	if is_instance_valid(game.player):
		game.player.add_screen_shake(0.45)
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

	if state == "stunned":
		stun_left -= delta
		if stun_left <= 0.0:
			state = "patrol"
			_sync_label()
		return

	var ppos: Vector3 = game.player.position
	var dist_p := root_node.position.distance_to(ppos)
	var dist_home_p := TERRITORY_CENTER.distance_to(ppos)

	# Continuous footstep noise sensing based on player stance & horizontal speed!
	var hspeed := Vector2(game.player.velocity.x, game.player.velocity.z).length()
	if dist_p <= HEAR_RADIUS and hspeed > 0.35:
		var stance: int = game.player.stance
		var rate := 0.6 if stance == game.player.STANCE_PRONE else (2.8 if stance == game.player.STANCE_CROUCH else (36.0 if hspeed > 5.0 else 16.0))
		register_noise(ppos, rate * delta, false)
	elif dist_p < 3.6 and game.player.stance != game.player.STANCE_PRONE:
		# Brushing right against the guardian while standing/crouching alerts it
		register_noise(ppos, 26.0 * delta, false)
	else:
		# Quiet / stealthy player drains alert meter!
		var drain := 16.0 if state == "patrol" else (11.5 if state == "investigate" else 5.5)
		noise_meter = maxf(0.0, noise_meter - drain * delta)
		calm_timer += delta
		if state == "investigate" and (noise_meter <= 8.0 or calm_timer >= 5.2):
			state = "patrol"
			_sync_label()

	# Enforce 42m cavern territory leash
	if state == "hunt" and dist_home_p > TERRITORY_RADIUS:
		state = "patrol"
		noise_meter = 15.0
		game._notice("✦ 已撤离烟霞古洞 42m 领地，古洞循音石卫放弃追击。", game.MINT)
		_sync_label()

	# Movement & attacks
	var move_target := root_node.position
	var move_speed := 1.85
	if state == "hunt":
		move_target = ppos
		var is_conf_m: bool = game.rules.is_confidential()
		move_speed = 5.65 if is_conf_m else 4.75
		if sonar_cd <= 0.0:
			sonar_cd = 2.1
			game.play_sfx("warden_sonar", -9)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 14.0)
		var blast_range := 15.0 if is_conf_m else 13.0
		if dist_p <= blast_range and attack_cd <= 0.0 and game.rules.combat_mode:
			_deliver_sonic_retaliation(dist_p < 4.6)
	elif state == "investigate":
		move_target = investigate_pos
		move_speed = 2.85
		if sonar_cd <= 0.0:
			sonar_cd = 2.4
			game.play_sfx("warden_sonar", -12)
			spawn_sonar_ring(root_node.position, Color("54f0ff"), 11.0)
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
		var next_xz := Vector3(root_node.position.x + step.x, 0.0, root_node.position.z + step.y)
		# Keep guardian inside 42m territory
		if Vector2(next_xz.x - TERRITORY_CENTER.x, next_xz.z - TERRITORY_CENTER.z).length() <= TERRITORY_RADIUS - 1.5:
			root_node.position = _ground_pos(next_xz)
		var desired_yaw := atan2(flat_delta.x, flat_delta.y)
		root_node.rotation.y = lerp_angle(root_node.rotation.y, desired_yaw, minf(delta * 5.5, 1.0))

	# Subtle heavy stalker sway
	if is_instance_valid(model_node):
		model_node.position.y = absf(sin(elapsed * (5.2 if state == "hunt" else 2.2))) * 0.06
	if hud_ping_cd <= 0.0 and dist_p <= 34.0:
		hud_ping_cd = 0.25
		_sync_label()
