extends Node3D
## Yanxia Ancient Cave Acoustic Guardian Boss ("古洞循音石卫" · v0.8.5 No-Stun Stealth-Guard Redesign).
## Blind karst guardian strictly leashed to Yanxia Ancient Cave in the isolated west bamboo ravine:
## - Articulated Blender 4.5 hierarchy: warden_body, head_crest, arm_left_pivot, arm_right_pivot (thick青石臂盾)
## - Compact 0.30m chest energy core hitbox (0.18m glowing cyan crystal)
## - ZERO stun on core hit or damage accumulation!
## - Core hit -> IMMEDIATELY snaps both stone arm-shields crossed across chest core (guard_arms=true) AND
##   immediately unleashes a sonic wave retaliation attack toward the player!
## - 1.5s Stealth Disengage Loop: if the player enters stealth silence ([C] crouch / [Z] prone / still without firing)
##   for 1.5 seconds, Cave Warden abandons search (state="patrol") and lowers/opens both arms again, creating
##   the next core-shot window!
## - [G] Smoke helps break sound tracking quickly (NO stun); Shaoyu [V] Slam briefly jolts arms open for 1.0s (NO stun).

const HIT_LAYER := 32  # Dedicated bit 5 for Cave Warden hitboxes (isolated from player/world masks)
const HEAR_RADIUS := 15.0
const TERRITORY_RADIUS := 13.5
const MAX_HP_NORMAL := 280
const MAX_HP_CONFIDENTIAL := 440
const CORE_HIT_RADIUS := 0.30
const CORE_VISUAL_RADIUS := 0.18
const STEALTH_DISENGAGE_SECONDS := 1.5

const PATROL_OFFSETS := [
	Vector3(0.0, 0.0, 7.60),
	Vector3(0.0, 0.0, 4.20),
	Vector3(1.30, 0.0, 1.80),
	Vector3(0.0, 0.0, 5.00),
]

var game
var rng := RandomNumberGenerator.new()
var root_node: Node3D
var model_node: Node3D
var body_mesh: Node3D
var arm_left_pivot: Node3D
var arm_right_pivot: Node3D
var head_crest: Node3D
var core_crystal: MeshInstance3D
var core_crystal_mat: StandardMaterial3D
var hp_bar_root: Node3D
var hp_fill: MeshInstance3D
var hp_fill_mat: StandardMaterial3D
var body_area: Area3D
var core_area: Area3D
var guard_area: Area3D
var status_label: Label3D
var sonar_rings: Array = []

var state := "patrol"  # "patrol" | "investigate" | "hunt" | "defeated" (ZERO stunned state!)
var max_hp := MAX_HP_NORMAL
var hp := MAX_HP_NORMAL
var hit_flash_left := 0.0
var deflect_flash_left := 0.0
var guard_arms := false
var guard_left := 0.0
var arms_forced_open_left := 0.0
var stealth_quiet_timer := 0.0
var sonic_retaliation_count := 0
var noise_meter := 0.0
var investigate_pos := Vector3.ZERO
var sonar_cd := 0.0
var attack_cd := 0.0
var patrol_idx := 0
var elapsed := 0.0
var hud_ping_cd := 0.0

func _cave_center() -> Vector3:
	if is_instance_valid(game) and game.Layout != null:
		return game.Layout.YANXIA_CAVE_CENTER
	return Vector3(-72.0, 0.0, -100.0)

func _cave_floor_y() -> float:
	if is_instance_valid(game) and game.Layout != null:
		return float(game.Layout.CAVE_FLOOR_Y) + 0.03
	return 8.63

func territory_center() -> Vector3:
	var c := _cave_center()
	return Vector3(c.x, _cave_floor_y(), c.z + 2.5)

func cave_min_x() -> float:
	return _cave_center().x - 3.2

func cave_max_x() -> float:
	return _cave_center().x + 3.2

func cave_min_z() -> float:
	return _cave_center().z - 3.8

func cave_max_z() -> float:
	return _cave_center().z + 10.8

func _patrol_pt(idx: int) -> Vector3:
	var c := _cave_center()
	var off: Vector3 = PATROL_OFFSETS[idx % PATROL_OFFSETS.size()]
	return Vector3(c.x + off.x, 0.0, c.z + off.z)

func setup(g):
	game = g
	rng.randomize()
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
		if is_instance_valid(target) and target is Node3D:
			if target.get_parent() != null:
				target.get_parent().remove_child(target)
			target.owner = null
			target.name = "CaveWardenRig"
			target.position = Vector3.ZERO
			target.rotation = Vector3.ZERO
			model_node = target
			root_node.add_child(target)
			body_mesh = target.find_child("warden_body", true, false) as Node3D
			arm_left_pivot = target.find_child("arm_left_pivot", true, false) as Node3D
			arm_right_pivot = target.find_child("arm_right_pivot", true, false) as Node3D
			head_crest = target.find_child("head_crest", true, false) as Node3D
		inst.queue_free()
	if model_node == null:
		model_node = game._mesh_box(root_node, Vector3(0, 1.35, 0), Vector3(1.2, 2.5, 0.8), Color("284852"))

	# Body hitbox (layer 32) sitting behind core so accurate chest shots hit core (or guard_area when guarding)
	body_area = Area3D.new()
	body_area.collision_layer = HIT_LAYER
	body_area.collision_mask = 0
	body_area.set_meta("cave_warden_part", "body")
	var b_col := CollisionShape3D.new()
	var b_shp := BoxShape3D.new()
	b_shp.size = Vector3(1.52, 2.48, 0.82)
	b_col.shape = b_shp
	b_col.position = Vector3(0.0, 1.30, -0.08)
	body_area.add_child(b_col)
	root_node.add_child(body_area)

	# Compact 0.30m glowing cyan sonar chest core weakpoint
	core_area = Area3D.new()
	core_area.collision_layer = HIT_LAYER
	core_area.collision_mask = 0
	core_area.set_meta("cave_warden_part", "core")
	var c_col := CollisionShape3D.new()
	var c_shp := SphereShape3D.new()
	c_shp.radius = CORE_HIT_RADIUS
	c_col.shape = c_shp
	c_col.position = Vector3(0.0, 1.56, 0.38)
	core_area.add_child(c_col)
	root_node.add_child(core_area)

	# Forward Arm-Shield Guard hitbox (enabled ONLY while guard_arms == true; intercepts frontal shots over chest core!)
	guard_area = Area3D.new()
	guard_area.collision_layer = 0
	guard_area.collision_mask = 0
	guard_area.set_meta("cave_warden_part", "guard")
	var g_col := CollisionShape3D.new()
	var g_shp := BoxShape3D.new()
	g_shp.size = Vector3(1.18, 0.94, 0.36)
	g_col.shape = g_shp
	g_col.position = Vector3(0.0, 1.54, 0.62)
	guard_area.add_child(g_col)
	root_node.add_child(guard_area)

	core_crystal = MeshInstance3D.new()
	var c_mesh := SphereMesh.new()
	c_mesh.radius = CORE_VISUAL_RADIUS
	c_mesh.height = CORE_VISUAL_RADIUS * 2.0
	c_mesh.radial_segments = 14
	c_mesh.rings = 10
	core_crystal.mesh = c_mesh
	core_crystal.position = Vector3(0.0, 1.56, 0.34)
	core_crystal_mat = StandardMaterial3D.new()
	core_crystal_mat.albedo_color = Color("5ef2ff")
	core_crystal_mat.emission_enabled = true
	core_crystal_mat.emission = Color("3ce6ff")
	core_crystal_mat.emission_energy_multiplier = 2.0
	core_crystal_mat.roughness = 0.16
	core_crystal.material_override = core_crystal_mat
	root_node.add_child(core_crystal)

	# Clear 3D floating HP bar right above shoulders
	hp_bar_root = Node3D.new()
	hp_bar_root.position = Vector3(0.0, 2.78, 0.0)
	root_node.add_child(hp_bar_root)
	var bg_bar: MeshInstance3D = game._mesh_box(hp_bar_root, Vector3(0.0, 0.0, -0.01), Vector3(1.64, 0.16, 0.04), Color("101b22"), false)
	(bg_bar.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_fill = game._mesh_box(hp_bar_root, Vector3(0.0, 0.0, 0.02), Vector3(1.56, 0.10, 0.04), Color("56e8ff"), false)
	hp_fill_mat = hp_fill.material_override as StandardMaterial3D
	hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	status_label = game._label3d(root_node, "古洞循音石卫 · 听声巡逻", Vector3(0.0, 3.08, 0.0), 26, Color("6cf2ff"))
	status_label.pixel_size = 0.0052
	status_label.visibility_range_end = 26.0

func _ground_pos(xz: Vector3) -> Vector3:
	var c := _cave_center()
	if xz.z <= c.z + 5.8 and xz.x >= cave_min_x() and xz.x <= cave_max_x():
		return Vector3(xz.x, _cave_floor_y(), xz.z)
	return Vector3(xz.x, float(game.terrain_height(xz.x, xz.z)), xz.z)

func _clamp_to_cave(xz: Vector3) -> Vector3:
	return Vector3(clampf(xz.x, cave_min_x(), cave_max_x()), 0.0, clampf(xz.z, cave_min_z(), cave_max_z()))

func is_mode_active() -> bool:
	return is_instance_valid(game) and game.rules.combat_mode and not game.rules.prologue_mode

func max_hp_for_mode() -> int:
	return MAX_HP_CONFIDENTIAL if (is_instance_valid(game) and game.rules.is_confidential()) else MAX_HP_NORMAL

func set_guard_arms(enabled: bool, duration: float = 4.2):
	guard_arms = enabled and is_alive() and arms_forced_open_left <= 0.0
	guard_left = duration if guard_arms else 0.0
	if is_instance_valid(guard_area):
		guard_area.collision_layer = HIT_LAYER if guard_arms else 0
	_sync_label()

func force_open_arms(duration: float = 1.0):
	## v0.8.5: Shaoyu [V] Slam briefly jolts arm-shields apart for 1.0s WITHOUT stunning the Warden!
	if not is_alive():
		return
	arms_forced_open_left = maxf(arms_forced_open_left, duration)
	set_guard_arms(false, 0.0)
	spawn_sonar_ring(root_node.position, Color("ffd86b"), 8.0)
	game._notice("⚡ 少羽震开石卫双臂 %.1f 秒！趁空档速射 0.30m 胸口蓝核！" % duration, Color("ffd86b"))
	_sync_label()

func reset():
	state = "patrol"
	max_hp = max_hp_for_mode()
	hp = max_hp
	hit_flash_left = 0.0
	deflect_flash_left = 0.0
	guard_arms = false
	guard_left = 0.0
	arms_forced_open_left = 0.0
	stealth_quiet_timer = 0.0
	sonic_retaliation_count = 0
	noise_meter = 0.0
	sonar_cd = 1.5
	attack_cd = 0.0
	patrol_idx = 0
	hud_ping_cd = 0.0
	investigate_pos = _ground_pos(_patrol_pt(0))
	var on := is_mode_active()
	if is_instance_valid(root_node):
		root_node.position = _ground_pos(_patrol_pt(0))
		root_node.rotation = Vector3.ZERO
		root_node.visible = on
	if is_instance_valid(model_node):
		model_node.position = Vector3.ZERO
		model_node.rotation = Vector3.ZERO
	if is_instance_valid(arm_left_pivot):
		arm_left_pivot.rotation = Vector3.ZERO
	if is_instance_valid(arm_right_pivot):
		arm_right_pivot.rotation = Vector3.ZERO
	if is_instance_valid(head_crest):
		head_crest.rotation = Vector3.ZERO
	if is_instance_valid(body_area):
		body_area.collision_layer = HIT_LAYER if on else 0
	if is_instance_valid(core_area):
		core_area.collision_layer = HIT_LAYER if on else 0
	if is_instance_valid(guard_area):
		guard_area.collision_layer = 0
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
			if arms_forced_open_left > 0.0:
				hp_fill_mat.albedo_color = Color("ffd86b")
			elif guard_arms:
				hp_fill_mat.albedo_color = Color("9ab8c2")
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
	if arms_forced_open_left > 0.0:
		status_label.text = "⚡ 古洞循音石卫 · 双臂震开 %.1fs（速射蓝核！） HP %d/%d" % [arms_forced_open_left, hp, max_hp]
		status_label.modulate = Color("ffd86b")
	elif guard_arms:
		var remain_quiet := maxf(0.0, STEALTH_DISENGAGE_SECONDS - stealth_quiet_timer)
		if stealth_quiet_timer > 0.08:
			status_label.text = "🛡 古洞循音石卫 · 护核搜寻中（静默 %.1fs 后放手） HP %d/%d" % [remain_quiet, hp, max_hp]
		else:
			status_label.text = "🛡 古洞循音石卫 · 双臂护核！按 [C]/[Z] 潜行静默 1.5s 脱搜  HP %d/%d" % [hp, max_hp]
		status_label.modulate = Color("ffd166")
	elif state == "hunt":
		status_label.text = "⚠ 古洞循音石卫 · 追击露核！（打胸口蓝核！） HP %d/%d" % [hp, max_hp]
		status_label.modulate = Color("ff5c5c")
	elif state == "investigate":
		status_label.text = "🌀 古洞循音石卫 · 声波搜寻 (%d%%)  HP %d/%d" % [pct, hp, max_hp]
		status_label.modulate = Color("ffd15c")
	else:
		status_label.text = "古洞循音石卫 · 听声巡逻（蓝核已暴露） HP %d/%d" % [hp, max_hp]
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
	var tc := territory_center()
	return Vector2(pos.x - tc.x, pos.z - tc.z).length() <= TERRITORY_RADIUS and pos.z <= _cave_center().z + 12.5

func register_noise(source_pos: Vector3, intensity: float, immediate_ping: bool = false):
	if not is_alive():
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
	stealth_quiet_timer = 0.0
	if noise_meter >= 75.0:
		if state != "hunt":
			state = "hunt"
			game.play_sfx("warden_sonar", -7)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 11.5)
			if is_instance_valid(game.player):
				game.player.add_screen_shake(0.28)
			game._notice("⚠ 古洞循音石卫循声惊醒！按 [C]/[Z] 潜行静默 1.5 秒可令其放弃搜索并放开双臂！", Color("ff6b6b"))
	elif noise_meter >= 30.0 and state == "patrol":
		state = "investigate"
		game.play_sfx("warden_sonar", -11)
		spawn_sonar_ring(root_node.position, Color("54f0ff"), 10.0)
		game._notice("🌀 古洞循音石卫听到了动静！按 [C] 蹲伏或 [Z] 匍匐潜行静默，待其放开双臂再狙蓝核！", Color("7ceeff"))
	elif immediate_ping and sonar_cd <= 0.0:
		sonar_cd = 1.6
		game.play_sfx("warden_sonar", -12)
		spawn_sonar_ring(root_node.position, Color("ff8052") if state == "hunt" else Color("54f0ff"), 10.5)
	_sync_label()

func on_gunshot(origin: Vector3, suppressed: bool):
	if not is_alive():
		return
	register_noise(origin, 28.0 if suppressed else 68.0, true)

func on_smoke_emp(origin: Vector3):
	## v0.8.5: Smoke provides acoustic masking & accelerates silent disengage (NO long stun!).
	if not is_alive():
		return
	if root_node.position.distance_to(origin) <= 13.5:
		noise_meter = 0.0
		stealth_quiet_timer = maxf(stealth_quiet_timer, STEALTH_DISENGAGE_SECONDS - 0.25)
		game._notice("✦ 烟雾屏蔽声源！保持潜行静默片刻，石卫便会放弃搜索并放开双臂！", Color("7ceeff"))
		_sync_label()

func _deliver_sonic_retaliation(is_close_slam: bool = false, keep_guard: bool = true):
	if not is_alive() or not is_instance_valid(game.player):
		return
	if is_instance_valid(game.combat) and game.combat.player_in_smoke():
		return
	if not keep_guard and guard_arms:
		set_guard_arms(false, 0.0)
	sonic_retaliation_count += 1
	var is_conf: bool = game.rules.is_confidential()
	attack_cd = (2.15 if is_conf else 2.65) if not is_close_slam else (2.30 if is_conf else 2.80)
	spawn_sonar_ring(root_node.position, Color("ff3b30"), 11.5 if is_conf else 10.0)
	game.play_sfx("warden_sonar", -6)
	game.player.add_screen_shake(0.38 if is_close_slam else 0.26)
	var push_dir: Vector3 = game.player.position - root_node.position
	push_dir.y = 0.0
	if push_dir.length() > 0.05:
		game.player.apply_knockback(push_dir.normalized() * (6.2 if is_close_slam else 4.2) + Vector3(0, 1.5, 0))
	var dmg: int = (32 if is_conf else 22) if is_close_slam else (22 if is_conf else 16)
	if is_instance_valid(game.combat) and game.rules.combat_mode:
		game.combat.apply_player_damage(dmg)
	game._notice("💥 古洞循音石卫释放%s（-%d 伤害）！快按 [C]/[Z] 潜行静默 1.5 秒等其放弃搜索放开双臂！" % [
		"重锤震地" if is_close_slam else "声波反击", dmg
	], Color("ff7a6b"))

func hit_bullet(collider) -> bool:
	if not is_alive() or not (collider is Object):
		return false
	if not collider.has_meta("cave_warden_part"):
		return false
	var part := str(collider.get_meta("cave_warden_part"))
	var is_conf: bool = game.rules.is_confidential()
	var blocked_by_guard: bool = (part == "guard") or (part == "core" and guard_arms)

	var dmg := 0
	var is_crit := false
	if blocked_by_guard:
		dmg = 8 if is_conf else 10
		hp = maxi(0, hp - dmg)
		deflect_flash_left = 0.18
		hit_flash_left = 0.08
		game.show_hitmarker(false)
		game.play_sfx("warden_shield_deflect", -7)
	elif part == "core":
		is_crit = true
		dmg = 50 if is_conf else 60
		hp = maxi(0, hp - dmg)
		hit_flash_left = 0.18
		game.show_hitmarker(true)
		game.play_sfx("hit_correct", -9)
	else:
		dmg = 16 if is_conf else 20
		hp = maxi(0, hp - dmg)
		hit_flash_left = 0.16
		game.show_hitmarker(false)
		game.play_sfx("knife_hit", -9)

	# v0.8.5 Core-Hit Behavior: NEVER stuns!
	# Immediately raises X-brace dual-arm guard to shield chest core AND fires immediate sonic wave retaliation!
	if hp > 0:
		stealth_quiet_timer = 0.0
		state = "hunt"
		noise_meter = 100.0
		if is_instance_valid(game.player):
			investigate_pos = _ground_pos(_clamp_to_cave(game.player.position))
		if is_crit:
			arms_forced_open_left = 0.0
			set_guard_arms(true, 4.6)
			if is_instance_valid(game.player) and root_node.position.distance_to(game.player.position) <= HEAR_RADIUS:
				_deliver_sonic_retaliation(false, true)
		elif not blocked_by_guard:
			if arms_forced_open_left <= 0.0:
				set_guard_arms(true, 3.6)

	if hp <= 0:
		_on_defeated()
	else:
		_sync_label()
		if blocked_by_guard:
			game._notice("🛡 石卫双臂护核！子弹被青石臂盾弹开（-%d 擦伤 · 剩 %d/%d HP），请按 [C]/[Z] 潜行静默 1.5s 等其放手！" % [dmg, hp, max_hp], Color("ffd166"))
		elif is_crit:
			game._notice("✦ 暴击蓝核 -%d HP（剩 %d/%d HP）！石卫立刻护核并声波反击——潜行静默 1.5s 后将再度放开双臂！" % [dmg, hp, max_hp], Color("7ceeff"))
		else:
			game._notice("💥 命中石卫岩甲 -%d HP（剩 %d/%d HP）· 石卫合臂护核，潜行静默 1.5s 待其放手再狙蓝核！" % [dmg, hp, max_hp], Color("ffe08c"))
	return true

func _on_defeated():
	state = "defeated"
	noise_meter = 0.0
	guard_arms = false
	guard_left = 0.0
	arms_forced_open_left = 0.0
	stealth_quiet_timer = 0.0
	body_area.collision_layer = 0
	core_area.collision_layer = 0
	guard_area.collision_layer = 0
	spawn_sonar_ring(root_node.position, Color("7af5cc"), 13.0)
	game.play_sfx("boss_phase", -9)
	if is_instance_valid(game.player):
		game.player.add_screen_shake(0.38)
	var drop_pos: Vector3 = _ground_pos(_clamp_to_cave(root_node.position))
	if is_instance_valid(root_node):
		root_node.hide()
	game.rules.score += 80
	var loot_msg := ""
	if game.rules.can_loot():
		var is_conf: bool = game.rules.operation_tier == "confidential"
		var rarity := (7 if randf() < 0.28 else 6) if is_conf else (6 if randf() < 0.25 else 5)
		var items: Array = [game.rules.roll_item_by_rarity(rarity)]
		if is_conf:
			items.append(game.rules.roll_item_by_rarity(4 if randf() < 0.65 else 5))
		if is_instance_valid(game.world_loot) and game.world_loot.has_method("spawn_custom_drop"):
			game.world_loot.spawn_custom_drop(drop_pos, "古洞循音石卫 · 秘宝掉落包", items, true)
			loot_msg = " · 已掉落实体【石卫秘宝包（%d件）】，靠近按 [F] 选择拾取！" % items.size()
		else:
			if game.rules.add_loot_item(items[0]):
				loot_msg = " · 掉落【%s】%s（%d币）" % [game.Rules.RARITY_NAMES[rarity], items[0].title, int(items[0].value)]
	if is_instance_valid(game.achievements):
		game.achievements.record_stat("cave_warden_defeated", 1)
	if is_instance_valid(game.rangers):
		game.rangers.unlock_card("cave_warden", false)
		game.rangers.record_bounty_progress("warden_defeated", 1)
	game._notice("★ 成功击败【古洞循音石卫】！+80 积分%s" % loot_msg, game.GOLD)
	_sync_label()

func _update_articulation(delta: float):
	if not is_instance_valid(arm_left_pivot) or not is_instance_valid(arm_right_pivot):
		return
	var target_l := Vector3.ZERO
	var target_r := Vector3.ZERO
	var target_h := Vector3.ZERO
	var speed := 10.0

	if arms_forced_open_left > 0.0:
		speed = 16.0
		target_l = Vector3(0.28, -0.46, -0.52)
		target_r = Vector3(0.28, 0.46, 0.52)
		target_h = Vector3(-0.34, sin(elapsed * 9.0) * 0.14, 0.0)
	elif guard_arms:
		speed = 18.0
		var jolt := 0.14 if deflect_flash_left > 0.0 else 0.0
		# Tight interlocking X-brace shielding the 0.30m blue chest core
		target_l = Vector3(-0.78 + jolt, 1.04, 0.24)
		target_r = Vector3(-0.86 + jolt, -1.04, -0.24)
		target_h = Vector3(0.20, 0.0, 0.0)
	elif state == "hunt":
		speed = 12.0
		var stride := sin(elapsed * 7.2)
		target_l = Vector3(-0.24 + stride * 0.44, -0.34, -0.44)
		target_r = Vector3(-0.24 - stride * 0.44, 0.34, 0.44)
		target_h = Vector3(-0.10, sin(elapsed * 4.2) * 0.10, 0.0)
	else:
		speed = 8.5
		var sw := sin(elapsed * 2.4)
		target_l = Vector3(sw * 0.16, -0.10, -0.14)
		target_r = Vector3(-sw * 0.16, 0.10, 0.14)
		target_h = Vector3(0.04, sin(elapsed * (3.6 if state == "investigate" else 1.5)) * (0.36 if state == "investigate" else 0.18), 0.0)

	var w := minf(delta * speed, 1.0)
	arm_left_pivot.rotation = arm_left_pivot.rotation.lerp(target_l, w)
	arm_right_pivot.rotation = arm_right_pivot.rotation.lerp(target_r, w)
	if is_instance_valid(head_crest):
		head_crest.rotation = head_crest.rotation.lerp(target_h, w)

func snap_articulation_for_pose():
	_update_articulation(1.0)

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
	if deflect_flash_left > 0.0:
		deflect_flash_left = maxf(0.0, deflect_flash_left - delta)
	if arms_forced_open_left > 0.0:
		arms_forced_open_left = maxf(0.0, arms_forced_open_left - delta)

	# Compact 0.30m cyan chest crystal visual feedback
	if is_instance_valid(core_crystal_mat):
		if hit_flash_left > 0.0 and deflect_flash_left <= 0.0:
			core_crystal_mat.albedo_color = Color("ffffff")
			core_crystal_mat.emission = Color("ffd86b")
			core_crystal_mat.emission_energy_multiplier = 4.2
		elif arms_forced_open_left > 0.0:
			core_crystal_mat.albedo_color = Color("ffd86b")
			core_crystal_mat.emission = Color("ffae34")
			core_crystal_mat.emission_energy_multiplier = 3.2 + sin(elapsed * 14.0) * 0.8
		elif guard_arms:
			core_crystal_mat.albedo_color = Color("36b8cc")
			core_crystal_mat.emission = Color("2894b0")
			core_crystal_mat.emission_energy_multiplier = 1.15
		else:
			core_crystal_mat.albedo_color = Color("5ef2ff")
			core_crystal_mat.emission = Color("3ce6ff")
			core_crystal_mat.emission_energy_multiplier = 2.2 + sin(elapsed * 5.8) * 0.45

	if is_instance_valid(hp_bar_root) and is_instance_valid(game.player.camera):
		var cam_p: Vector3 = game.player.camera.global_position
		var to_cam := Vector3(cam_p.x - hp_bar_root.global_position.x, 0.0, cam_p.z - hp_bar_root.global_position.z)
		if to_cam.length_squared() > 0.04:
			hp_bar_root.global_rotation.y = atan2(to_cam.x, to_cam.z)

	var ppos: Vector3 = game.player.position
	var dist_p := root_node.position.distance_to(ppos)
	var player_in_cave := _player_inside_cave_territory(ppos)

	# Strictly enforce Yanxia Cave territory leash: exiting the cave IMMEDIATELY breaks hunt & drops guard!
	if (state in ["hunt", "investigate"] or guard_arms) and not player_in_cave:
		if state == "hunt":
			game._notice("✦ 已离开烟霞古洞范围，古洞循音石卫退回洞内巡逻。", game.MINT)
		state = "patrol"
		noise_meter = 0.0
		stealth_quiet_timer = 0.0
		set_guard_arms(false, 0.0)
		_sync_label()

	# Acoustic sensing vs 1.5s Stealth Silence Disengage!
	var hspeed := Vector2(game.player.velocity.x, game.player.velocity.z).length()
	var stance: int = game.player.stance
	var in_smoke: bool = is_instance_valid(game.combat) and game.combat.player_in_smoke()
	var player_is_noisy: bool = (
		player_in_cave
		and dist_p <= HEAR_RADIUS
		and not in_smoke
		and stance == game.player.STANCE_STAND
		and hspeed > 0.35
	)

	if player_is_noisy:
		stealth_quiet_timer = 0.0
		var rate := 36.0 if hspeed > 5.0 else 18.0
		register_noise(ppos, rate * delta, false)
	else:
		# Player is crouched ([C]), prone ([Z]), standing still, or masked in smoke -> SILENT!
		noise_meter = maxf(0.0, noise_meter - 24.0 * delta)
		if state in ["hunt", "investigate"] or guard_arms:
			stealth_quiet_timer += delta
			if stealth_quiet_timer >= STEALTH_DISENGAGE_SECONDS:
				state = "patrol"
				noise_meter = 0.0
				stealth_quiet_timer = 0.0
				set_guard_arms(false, 0.0)
				game._notice("✦ 潜行静默 1.5 秒生效！古洞循音石卫放弃搜索并放开双臂，趁机瞄准胸口蓝核！", Color("7ceeff"))
				_sync_label()
			else:
				_sync_label()

	# Guard timer countdown when player keeps making noise (non-stealth kiting still eventually opens arms on pursuit)
	if guard_arms and player_is_noisy:
		var kite_mult := 1.45 if (player_in_cave and dist_p > 4.6) else 0.75
		guard_left = maxf(0.0, guard_left - delta * kite_mult)
		if guard_left <= 0.0:
			set_guard_arms(false, 0.0)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 10.5)
			game.play_sfx("warden_sonar", -9)
			_sync_label()

	# Movement & sonic wave attack rhythm (strictly confined inside Yanxia Cave!)
	var move_target := root_node.position
	var move_speed := 1.65
	if state == "hunt":
		move_target = _ground_pos(_clamp_to_cave(investigate_pos if not player_is_noisy else ppos))
		var is_conf_m: bool = game.rules.is_confidential()
		move_speed = (1.30 if is_conf_m else 1.10) if guard_arms else (4.20 if is_conf_m else 3.60)
		if sonar_cd <= 0.0:
			sonar_cd = 2.4
			game.play_sfx("warden_sonar", -9)
			spawn_sonar_ring(root_node.position, Color("ffd166") if guard_arms else Color("ff5c5c"), 11.0)
		var blast_range := 11.0 if is_conf_m else 9.5
		if player_in_cave and player_is_noisy and dist_p <= blast_range and attack_cd <= 0.0 and game.rules.combat_mode:
			_deliver_sonic_retaliation(dist_p < 3.8, guard_arms)
	elif state == "investigate":
		move_target = _ground_pos(_clamp_to_cave(investigate_pos))
		move_speed = 1.20 if guard_arms else 2.55
		if sonar_cd <= 0.0:
			sonar_cd = 2.5
			game.play_sfx("warden_sonar", -12)
			spawn_sonar_ring(root_node.position, Color("54f0ff"), 9.5)
	else:
		var wp := _ground_pos(_patrol_pt(patrol_idx))
		if Vector2(wp.x - root_node.position.x, wp.z - root_node.position.z).length() < 0.75:
			patrol_idx = (patrol_idx + 1) % PATROL_OFFSETS.size()
			wp = _ground_pos(_patrol_pt(patrol_idx))
		move_target = wp
		move_speed = 1.65

	var flat_delta := Vector2(move_target.x - root_node.position.x, move_target.z - root_node.position.z)
	var stop_dist := 2.4 if state == "hunt" else 0.45
	if flat_delta.length() > stop_dist:
		var step := flat_delta.normalized() * minf(move_speed * delta, flat_delta.length() - stop_dist)
		var next_xz := _clamp_to_cave(Vector3(root_node.position.x + step.x, 0.0, root_node.position.z + step.y))
		root_node.position = _ground_pos(next_xz)
	if state == "hunt" or guard_arms:
		var face_target := ppos if player_is_noisy else investigate_pos
		var face_p := Vector2(face_target.x - root_node.position.x, face_target.z - root_node.position.z)
		if face_p.length() > 0.25:
			root_node.rotation.y = lerp_angle(root_node.rotation.y, atan2(face_p.x, face_p.y), minf(delta * 7.2, 1.0))
	elif flat_delta.length() > 0.25:
		root_node.rotation.y = lerp_angle(root_node.rotation.y, atan2(flat_delta.x, flat_delta.y), minf(delta * 5.0, 1.0))

	if is_instance_valid(model_node):
		var flinch_z := -0.08 if deflect_flash_left > 0.0 else (-0.16 if hit_flash_left > 0.0 else 0.0)
		var flinch_rx := -0.07 if deflect_flash_left > 0.0 else (-0.18 if hit_flash_left > 0.0 else 0.0)
		model_node.position.y = absf(sin(elapsed * (4.8 if (state == "hunt" and not guard_arms) else 2.2))) * (0.025 if guard_arms else 0.055)
		model_node.position.z = lerpf(model_node.position.z, flinch_z, minf(delta * 20.0, 1.0))
		model_node.rotation.x = lerpf(model_node.rotation.x, flinch_rx, minf(delta * 20.0, 1.0))
	_update_articulation(delta)
