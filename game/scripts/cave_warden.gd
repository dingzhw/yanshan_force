extends Node3D
## Yanxia Ancient Cave Acoustic Guardian Boss ("古洞循音石卫" · v0.8.6 Tactical Acoustic Predator).
## Blind karst guardian strictly leashed to Yanxia Ancient Cave in the isolated west bamboo ravine:
## - Articulated Blender 4.5 hierarchy: warden_body, head_crest, arm_left_pivot, arm_right_pivot (thick青石臂盾)
## - Compact 0.30m chest energy core hitbox (0.18m glowing cyan crystal)
## - ZERO stun on core hit! Core hit snaps X-brace dual-arm guard + locks firing point via Ballistic Triangulation!
## - Anti-Crouch-Snipe Mandatory Reposition: after shooting, camping within relocate_dist (2.8m Normal / 4.0m Conf;
##   2.2m suppressed) freezes the 1.5s stealth timer AND triggers a 22m Focused Sonic Lance straight down the firing line!
## - 4 Acoustic Moves: 360° Sonic Pulse, 22m Focused Sonic Lance, Cavern Quake Stalactite Rings, and
##   Confidential-Exclusive Active Echolocation Sweep (evaded ONLY by [Z] prone / [G] smoke / rock cover!) + Enraged Resonance (<45% HP).

const HIT_LAYER := 32  # Dedicated bit 5 for Cave Warden hitboxes (isolated from player/world masks)
const HEAR_RADIUS := 15.0
const BALLISTIC_RANGE := 22.0
const TERRITORY_RADIUS := 15.0
const MAX_HP_NORMAL := 280
const MAX_HP_CONFIDENTIAL := 360
const CORE_HIT_RADIUS := 0.30
const CORE_VISUAL_RADIUS := 0.18
const STEALTH_DISENGAGE_SECONDS := 1.5
const RELOCATE_DIST_NORMAL := 2.8
const RELOCATE_DIST_CONFIDENTIAL := 4.0
const RELOCATE_DIST_SUPPRESSED := 2.2

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
var lance_beam_node: MeshInstance3D
var lance_beam_mat: StandardMaterial3D
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
var sonic_lance_count := 0
var quake_slam_count := 0
var echo_sweep_count := 0
var echo_detected_count := 0
var echo_evaded_count := 0
var enraged_resonance := false
var last_shot_pos := Vector3.ZERO
var shot_origin_active := false
var last_shot_suppressed := false
var lance_state := "idle"  # "idle" | "charging" | "flash"
var lance_timer := 0.0
var lance_cd := 0.0
var lance_origin := Vector3.ZERO
var lance_dir := Vector3.FORWARD
var quake_cd := 6.0
var echo_sweep_cd := 5.5
var echo_charging := false
var echo_charge_left := 0.0
var noise_meter := 0.0
var investigate_pos := Vector3.ZERO
var sonar_cd := 0.0
var attack_cd := 0.0
var patrol_idx := 0
var elapsed := 0.0
var hud_ping_cd := 0.0
var map_enabled := true

func set_map_enabled(on: bool):
	map_enabled = on
	if is_instance_valid(root_node):
		root_node.visible = on and is_mode_active() and state != "defeated"
	if not on:
		if is_instance_valid(body_area):
			body_area.collision_layer = 0
		if is_instance_valid(core_area):
			core_area.collision_layer = 0
		if is_instance_valid(guard_area):
			guard_area.collision_layer = 0

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

	# 3D Focused Anti-Sniper Sonic Lance Telegraph & Fire Beam
	lance_beam_node = MeshInstance3D.new()
	var lb_mesh := BoxMesh.new()
	lb_mesh.size = Vector3(0.24, 0.24, 1.0)
	lance_beam_node.mesh = lb_mesh
	lance_beam_mat = StandardMaterial3D.new()
	lance_beam_mat.albedo_color = Color(0.28, 0.92, 1.0, 0.72)
	lance_beam_mat.emission_enabled = true
	lance_beam_mat.emission = Color("54f0ff")
	lance_beam_mat.emission_energy_multiplier = 2.6
	lance_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lance_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lance_beam_node.material_override = lance_beam_mat
	lance_beam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lance_beam_node.hide()
	add_child(lance_beam_node)

func _ground_pos(xz: Vector3) -> Vector3:
	var c := _cave_center()
	if xz.z <= c.z + 5.8 and xz.x >= cave_min_x() and xz.x <= cave_max_x():
		return Vector3(xz.x, _cave_floor_y(), xz.z)
	return Vector3(xz.x, float(game.terrain_height(xz.x, xz.z)), xz.z)

func _clamp_to_cave(xz: Vector3) -> Vector3:
	return Vector3(clampf(xz.x, cave_min_x(), cave_max_x()), 0.0, clampf(xz.z, cave_min_z(), cave_max_z()))

func is_mode_active() -> bool:
	return map_enabled and is_instance_valid(game) and game.rules.combat_mode and not game.rules.prologue_mode

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
	sonic_lance_count = 0
	quake_slam_count = 0
	echo_sweep_count = 0
	echo_detected_count = 0
	echo_evaded_count = 0
	enraged_resonance = false
	last_shot_pos = Vector3.ZERO
	shot_origin_active = false
	last_shot_suppressed = false
	lance_state = "idle"
	lance_timer = 0.0
	lance_cd = 0.0
	quake_cd = 5.8
	echo_sweep_cd = 5.5
	echo_charging = false
	echo_charge_left = 0.0
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
	if is_instance_valid(lance_beam_node):
		lance_beam_node.hide()
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

func required_relocate_distance() -> float:
	if last_shot_suppressed:
		return RELOCATE_DIST_SUPPRESSED
	if is_instance_valid(game) and game.rules.is_confidential():
		return RELOCATE_DIST_CONFIDENTIAL
	return RELOCATE_DIST_NORMAL

func is_camping_shot_origin(player_pos: Vector3) -> bool:
	if not shot_origin_active:
		return false
	if is_instance_valid(game.combat) and game.combat.player_in_smoke():
		return false
	var d_shot := Vector2(player_pos.x - last_shot_pos.x, player_pos.z - last_shot_pos.z).length()
	return d_shot < required_relocate_distance()

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
	var camping_now := is_instance_valid(game.player) and is_camping_shot_origin(game.player.position)
	var rage_tag := "【狂鸣】" if enraged_resonance else ""
	if arms_forced_open_left > 0.0:
		status_label.text = "⚡ 古洞循音石卫%s · 双臂震开 %.1fs（速射蓝核！） HP %d/%d" % [rage_tag, arms_forced_open_left, hp, max_hp]
		status_label.modulate = Color("ffd86b")
	elif echo_charging:
		status_label.text = "📡 古洞循音石卫%s · 主动声呐扫描 %.1fs！速 [Z] 匍匐/进烟！ HP %d/%d" % [rage_tag, echo_charge_left, hp, max_hp]
		status_label.modulate = Color("ff8a4c")
	elif lance_state == "charging":
		status_label.text = "☄ 古洞循音石卫%s · 锁定开火点蓄力【穿石声波束】！横向闪避！ HP %d/%d" % [rage_tag, hp, max_hp]
		status_label.modulate = Color("ff5c5c")
	elif guard_arms:
		if camping_now:
			status_label.text = "🎯 石卫已锁定开火点！潜行转移 >%.1fm 或投 [G] 烟雾脱搜！ HP %d/%d" % [required_relocate_distance(), hp, max_hp]
			status_label.modulate = Color("ff7a52")
		elif stealth_quiet_timer > 0.08:
			var remain_quiet := maxf(0.0, STEALTH_DISENGAGE_SECONDS - stealth_quiet_timer)
			status_label.text = "🛡 古洞循音石卫%s · 护核搜寻中（静默 %.1fs 后放手） HP %d/%d" % [rage_tag, remain_quiet, hp, max_hp]
			status_label.modulate = Color("ffd166")
		else:
			status_label.text = "🛡 古洞循音石卫%s · 双臂护核！潜行移位并静默 1.5s 脱搜 HP %d/%d" % [rage_tag, hp, max_hp]
			status_label.modulate = Color("ffd166")
	elif state == "hunt":
		status_label.text = "⚠ 古洞循音石卫%s · 追击露核！（打胸口蓝核！） HP %d/%d" % [rage_tag, hp, max_hp]
		status_label.modulate = Color("ff5c5c")
	elif state == "investigate":
		status_label.text = "🌀 古洞循音石卫%s · 声波搜寻 (%d%%) HP %d/%d" % [rage_tag, pct, hp, max_hp]
		status_label.modulate = Color("ffd15c")
	else:
		status_label.text = "古洞循音石卫%s · 听声巡逻（蓝核已暴露） HP %d/%d" % [rage_tag, hp, max_hp]
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
			game.play_cn_voice("cave_03", dist, true)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 11.5)
			if is_instance_valid(game.player):
				game.player.add_screen_shake(0.28)
			game._notice("⚠ 古洞循音石卫循声惊醒！按 [C]/[Z] 潜行静默 1.5 秒脱搜！", Color("ff6b6b"))
	elif noise_meter >= 30.0 and state == "patrol":
		state = "investigate"
		game.play_sfx("warden_sonar", -11)
		game.play_cn_voice("cave_02", dist, false)
		spawn_sonar_ring(root_node.position, Color("54f0ff"), 10.0)
		game._notice("🌀 古洞循音石卫听到了动静！潜行静默待其放开双臂再狙蓝核！", Color("7ceeff"))
	elif immediate_ping and sonar_cd <= 0.0:
		sonar_cd = 1.6
		game.play_sfx("warden_sonar", -12)
		spawn_sonar_ring(root_node.position, Color("ff8052") if state == "hunt" else Color("54f0ff"), 10.5)
	_sync_label()

func on_gunshot(origin: Vector3, suppressed: bool):
	if not is_alive():
		return
	var dist := root_node.position.distance_to(origin)
	if dist <= BALLISTIC_RANGE:
		last_shot_pos = origin
		shot_origin_active = true
		last_shot_suppressed = suppressed
		investigate_pos = _ground_pos(_clamp_to_cave(origin))
	register_noise(origin, 28.0 if suppressed else 68.0, true)

func on_smoke_emp(origin: Vector3):
	## v0.8.6: Smoke breaks ballistic tracking + acoustic lock cleanly (NO long stun!).
	if not is_alive():
		return
	if root_node.position.distance_to(origin) <= 16.0:
		noise_meter = 0.0
		shot_origin_active = false
		echo_charging = false
		echo_charge_left = 0.0
		if lance_state == "charging":
			lance_state = "idle"
			if is_instance_valid(lance_beam_node):
				lance_beam_node.hide()
		stealth_quiet_timer = maxf(stealth_quiet_timer, STEALTH_DISENGAGE_SECONDS - 0.25)
		game._notice("✦ 烟雾屏蔽声源与弹道锁定！保持潜行静默片刻，石卫便会放弃搜索并放开双臂！", Color("7ceeff"))
		_sync_label()

func _place_lance_beam(origin_pt: Vector3, dir_v: Vector3, length_m: float, col: Color, width_m: float):
	if not is_instance_valid(lance_beam_node):
		return
	var d := dir_v.normalized()
	if d.length_squared() < 0.001:
		d = Vector3.FORWARD
	lance_beam_node.show()
	lance_beam_node.global_position = origin_pt + d * (length_m * 0.5)
	lance_beam_node.scale = Vector3(width_m / 0.24, width_m / 0.24, length_m)
	var up_ax := Vector3.RIGHT if absf(d.y) > 0.96 else Vector3.UP
	lance_beam_node.look_at(origin_pt + d * length_m, up_ax)
	if is_instance_valid(lance_beam_mat):
		lance_beam_mat.albedo_color = col
		lance_beam_mat.emission = Color(col.r, col.g, col.b)

func start_sonic_lance(target_pos: Vector3):
	## Move 2 · 22m Focused Anti-Sniper Sonic Lance ("穿石声波束"): telegraphed beam punishing stationary crouch-sniping!
	if not is_alive() or lance_state != "idle":
		return
	var is_conf: bool = game.rules.is_confidential()
	lance_origin = root_node.global_position + Vector3(0.0, 1.62, 0.0)
	var aim_pt := target_pos + Vector3(0.0, 0.95, 0.0)
	var delta_v := aim_pt - lance_origin
	if delta_v.length_squared() < 0.04:
		delta_v = Vector3.BACK
	lance_dir = delta_v.normalized()
	lance_state = "charging"
	lance_timer = 0.66 if is_conf else 0.92
	lance_cd = (3.4 if enraged_resonance else 4.2) if is_conf else 4.8
	_place_lance_beam(lance_origin, lance_dir, BALLISTIC_RANGE, Color(0.32, 0.92, 1.0, 0.62), 0.16)
	game.play_sfx("warning_lock", -9)
	game.play_cn_voice("cave_04", root_node.position.distance_to(target_pos), true)
	game._notice("☄ 石卫蓄力【穿石声波束】！快横向潜行移位躲开光束！", Color("ff8066"))
	_sync_label()

func _fire_sonic_lance():
	if not is_alive():
		return
	var is_conf: bool = game.rules.is_confidential()
	sonic_lance_count += 1
	lance_state = "flash"
	lance_timer = 0.24
	_place_lance_beam(lance_origin, lance_dir, BALLISTIC_RANGE, Color(1.0, 0.36, 0.22, 0.92), 0.52)
	game.play_sfx("warden_sonar", -5)
	spawn_sonar_ring(root_node.position, Color("ff5c42"), 12.0)
	if is_instance_valid(game.player) and game.rules.combat_mode:
		var in_smk: bool = is_instance_valid(game.combat) and game.combat.player_in_smoke()
		var p_center: Vector3 = game.player.position + Vector3(0.0, 0.95, 0.0)
		var rel: Vector3 = p_center - lance_origin
		var along: float = rel.dot(lance_dir)
		if not in_smk and along >= 0.0 and along <= BALLISTIC_RANGE:
			var perp := (rel - lance_dir * along).length()
			if perp <= 1.40:
				var dmg := 28 if is_conf else 20
				game.player.add_screen_shake(0.45)
				game.player.apply_knockback(Vector3(lance_dir.x, 0.0, lance_dir.z).normalized() * 5.6 + Vector3(0.0, 1.3, 0.0))
				if is_instance_valid(game.combat):
					game.combat.apply_player_damage(dmg)
				game._notice("💥 留在原位被【穿石声波束】贯穿（-%d 伤害）！开枪后务必潜行横向换位！" % dmg, Color("ff5c5c"))
			else:
				game._notice("✦ 成功横向移位闪避【穿石声波束】！", game.MINT)

func _trigger_cavern_quake(center_hint: Vector3):
	## Move 3 · Cavern Quake Stalactite Rings (2 rings Normal / 3 rings Confidential)!
	if not is_alive() or not is_instance_valid(game.combat) or not game.rules.combat_mode:
		return
	var is_conf: bool = game.rules.is_confidential()
	quake_slam_count += 1
	quake_cd = (5.6 if not enraged_resonance else 4.6) if is_conf else 7.4
	var ring_cnt := 3 if is_conf else 2
	var dmg := 24 if is_conf else 18
	game.play_sfx("boss_phase", -9)
	spawn_sonar_ring(root_node.position, Color("ff8c42"), 11.5)
	if is_instance_valid(game.player):
		game.player.add_screen_shake(0.32)
	var base_pt := _ground_pos(_clamp_to_cave(center_hint))
	for i in ring_cnt:
		var ang := float(i) * (TAU / float(ring_cnt)) + rng.randf_range(-0.35, 0.35)
		var r_off := 0.0 if i == 0 else 3.15
		var pt := _ground_pos(_clamp_to_cave(base_pt + Vector3(cos(ang) * r_off, 0.0, sin(ang) * r_off)))
		game.combat.spawn_danger_ring(pt, 2.85, dmg)
	game._notice("🪨 古洞循音石卫重锤震洞，洞顶碎岩坠落（%d 道红圈）！迅速走位闪避！" % ring_cnt, Color("ff9f54"))

func _resolve_echo_sweep():
	## Move 4 (Confidential-Only!) · Active Echolocation Sweep: detects standing/crouched open player; [Z] Prone / [G] Smoke / Rock Cover evades 100%!
	echo_charging = false
	echo_charge_left = 0.0
	echo_sweep_count += 1
	echo_sweep_cd = 5.4 if enraged_resonance else 6.4
	spawn_sonar_ring(root_node.position, Color("ffd15c"), 18.0)
	game.play_sfx("warden_sonar", -6)
	if not is_instance_valid(game.player):
		return
	var ppos: Vector3 = game.player.position
	var d_p := root_node.position.distance_to(ppos)
	var in_smk: bool = is_instance_valid(game.combat) and game.combat.player_in_smoke()
	var is_prone: bool = (game.player.stance == game.player.STANCE_PRONE)
	var rock_occluded := false
	if is_instance_valid(game.combat):
		var eye_h := 0.45 if is_prone else (0.98 if game.player.stance == game.player.STANCE_CROUCH else 1.48)
		rock_occluded = game.combat.blocked(root_node.global_position + Vector3(0.0, 1.85, 0.0), ppos + Vector3(0.0, eye_h, 0.0))
	if d_p <= BALLISTIC_RANGE and not in_smk and not is_prone and not rock_occluded:
		echo_detected_count += 1
		last_shot_pos = ppos
		shot_origin_active = true
		investigate_pos = _ground_pos(_clamp_to_cave(ppos))
		stealth_quiet_timer = 0.0
		noise_meter = 100.0
		state = "hunt"
		game._notice("📡 机密【主动声呐扫描】捕获你的轮廓！未按 [Z] 匍匐贴地——石卫立即锁定并蓄力声波束！", Color("ff5c5c"))
		if lance_state == "idle":
			start_sonic_lance(ppos)
	else:
		echo_evaded_count += 1
		game._notice("✦ 成功以 [Z] 匍匐/烟雾/石柱遮挡规避石卫主动声呐扫描！", Color("7ceeff"))
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
	var dmg: int = (30 if is_conf else 22) if is_close_slam else (22 if is_conf else 16)
	if is_instance_valid(game.combat) and game.rules.combat_mode:
		game.combat.apply_player_damage(dmg)
	game._notice("💥 古洞循音石卫释放%s（-%d 伤害）！快潜行移位 >%.1fm 并静默 1.5s 脱搜！" % [
		"重锤震地" if is_close_slam else "声波反击", dmg, required_relocate_distance()
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

	# v0.8.6 Anti-Crouch-Snipe Core-Hit Behavior: NEVER stuns!
	# Immediately locks firing spot (Ballistic Triangulation), snaps X-brace dual-arm guard,
	# and fires close Sonic Pulse (<=5.5m) OR 22m Focused Anti-Sniper Sonic Lance (>5.5m)!
	if hp > 0:
		stealth_quiet_timer = 0.0
		state = "hunt"
		noise_meter = 100.0
		last_shot_suppressed = (game.rules.active_muzzle() == "suppressor")
		if is_conf and not enraged_resonance and hp <= int(max_hp * 0.45):
			enraged_resonance = true
			spawn_sonar_ring(root_node.position, Color("ff3b30"), 15.0)
			game.play_sfx("boss_phase", -7)
			game._notice("🔥 机密古洞石卫进入【狂鸣共振】！移速提升，核心受击将同时震落洞石并锁定声波束！", Color("ff5252"))
		var d_shooter := 999.0
		if is_instance_valid(game.player):
			last_shot_pos = game.player.position
			shot_origin_active = true
			investigate_pos = _ground_pos(_clamp_to_cave(game.player.position))
			d_shooter = root_node.position.distance_to(game.player.position)
		if is_crit:
			arms_forced_open_left = 0.0
			set_guard_arms(true, 4.6)
			if is_instance_valid(game.player):
				if d_shooter <= 5.5:
					_deliver_sonic_retaliation(false, true)
				elif d_shooter <= BALLISTIC_RANGE:
					if lance_state == "idle":
						start_sonic_lance(game.player.position)
					else:
						_deliver_sonic_retaliation(false, true)
				if enraged_resonance and is_instance_valid(game.combat) and game.rules.combat_mode:
					game.combat.spawn_danger_ring(_ground_pos(_clamp_to_cave(game.player.position)), 3.0, 24)
		elif not blocked_by_guard:
			if arms_forced_open_left <= 0.0:
				set_guard_arms(true, 3.6)
			if is_instance_valid(game.player) and d_shooter > 5.5 and d_shooter <= BALLISTIC_RANGE and lance_state == "idle" and lance_cd <= 0.0:
				start_sonic_lance(game.player.position)

	if hp <= 0:
		_on_defeated()
	else:
		_sync_label()
		if blocked_by_guard:
			game._notice("🛡 石卫双臂护核！子弹被青石臂盾弹开（-%d · 剩 %d/%d HP），潜行转移 >%.1fm 并静默 1.5s 等其放手！" % [dmg, hp, max_hp, required_relocate_distance()], Color("ffd166"))
		elif is_crit:
			game._notice("✦ 暴击蓝核 -%d HP（剩 %d/%d HP）！石卫立刻护核并锁定开火点——速潜行移位 >%.1fm 并静默 1.5s！" % [dmg, hp, max_hp, required_relocate_distance()], Color("7ceeff"))
		else:
			game._notice("💥 命中石卫岩甲 -%d HP（剩 %d/%d HP）· 石卫合臂护核并锁定声源，速潜行换位！" % [dmg, hp, max_hp], Color("ffe08c"))
	return true

func _on_defeated():
	state = "defeated"
	noise_meter = 0.0
	guard_arms = false
	guard_left = 0.0
	arms_forced_open_left = 0.0
	stealth_quiet_timer = 0.0
	shot_origin_active = false
	echo_charging = false
	lance_state = "idle"
	if is_instance_valid(lance_beam_node):
		lance_beam_node.hide()
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
		var is_conf: bool = game.rules.is_confidential()
		var rarity: int = game.rules.roll_calibrated_rarity(is_conf, "warden_drop", true)
		var items: Array = [game.rules.roll_item_by_rarity(rarity)]
		if is_conf:
			var r2: int = game.rules.roll_calibrated_rarity(true, "hidden_nook", true)
			items.append(game.rules.roll_item_by_rarity(r2))
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
	game.rules.inc_lore_stat("warden_defeats", 1)
	game.rules.mark_lore_scene("yanshan_cave")
	if game.rules.is_confidential() and game.has_method("on_confidential_cave_warden_defeated"):
		game.on_confidential_cave_warden_defeated()
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
	lance_cd = maxf(0.0, lance_cd - delta)
	quake_cd = maxf(0.0, quake_cd - delta)
	echo_sweep_cd = maxf(0.0, echo_sweep_cd - delta)
	hud_ping_cd = maxf(0.0, hud_ping_cd - delta)
	if hit_flash_left > 0.0:
		hit_flash_left = maxf(0.0, hit_flash_left - delta)
	if deflect_flash_left > 0.0:
		deflect_flash_left = maxf(0.0, deflect_flash_left - delta)
	if arms_forced_open_left > 0.0:
		arms_forced_open_left = maxf(0.0, arms_forced_open_left - delta)

	# Focused Anti-Sniper Sonic Lance state machine
	if lance_state == "charging":
		lance_timer -= delta
		var pulse_w := 0.14 + absf(sin(elapsed * 24.0)) * 0.12
		_place_lance_beam(lance_origin, lance_dir, BALLISTIC_RANGE, Color(1.0, 0.56, 0.24, 0.78) if lance_timer < 0.28 else Color(0.32, 0.92, 1.0, 0.62), pulse_w)
		if lance_timer <= 0.0:
			_fire_sonic_lance()
	elif lance_state == "flash":
		lance_timer -= delta
		if lance_timer <= 0.0:
			lance_state = "idle"
			if is_instance_valid(lance_beam_node):
				lance_beam_node.hide()
			_sync_label()

	# Confidential-Exclusive Active Echolocation Sweep countdown
	if echo_charging:
		echo_charge_left -= delta
		if echo_charge_left <= 0.0:
			_resolve_echo_sweep()
		else:
			_sync_label()

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
		elif enraged_resonance:
			core_crystal_mat.albedo_color = Color("ff6248")
			core_crystal_mat.emission = Color("ff3b28")
			core_crystal_mat.emission_energy_multiplier = 2.8 + sin(elapsed * 10.0) * 0.7
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
	var is_conf_m: bool = game.rules.is_confidential()
	if state == "patrol" and dist_p <= 21.0 and sonar_cd <= 0.0 and game.cn_voice_cd <= 0.0:
		sonar_cd = 16.0
		game.play_cn_voice_group("cave_warden", "proximity", dist_p, false)

	# Strictly enforce Yanxia Cave territory leash: exiting far beyond cave breaks hunt & drops guard!
	if (state in ["hunt", "investigate"] or guard_arms or shot_origin_active) and not player_in_cave and (dist_p > BALLISTIC_RANGE or not shot_origin_active):
		if state == "hunt":
			game._notice("✦ 已离开烟霞古洞范围，古洞循音石卫退回洞内巡逻。", game.MINT)
		state = "patrol"
		noise_meter = 0.0
		stealth_quiet_timer = 0.0
		shot_origin_active = false
		echo_charging = false
		echo_charge_left = 0.0
		lance_state = "idle"
		if is_instance_valid(lance_beam_node):
			lance_beam_node.hide()
		set_guard_arms(false, 0.0)
		_sync_label()

	# Acoustic sensing vs Anti-Crouch-Snipe Mandatory Reposition + 1.5s Stealth Silence Disengage!
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

	var camping_shot := is_camping_shot_origin(ppos)
	if shot_origin_active and not camping_shot:
		shot_origin_active = false
		if state in ["hunt", "investigate"] or guard_arms:
			game._notice("✦ 已潜行转移脱离弹道锁定点！保持静默 1.5 秒，石卫便会放弃搜索并放开双臂！", Color("7ceeff"))
			_sync_label()

	if player_is_noisy:
		stealth_quiet_timer = 0.0
		var rate := 36.0 if hspeed > 5.0 else 18.0
		register_noise(ppos, rate * delta, false)
	elif camping_shot:
		# Anti-crouch-snipe lock: crouching in place at the exact firing spot NEVER ticks down stealth disengage!
		stealth_quiet_timer = 0.0
		investigate_pos = _ground_pos(_clamp_to_cave(last_shot_pos))
		if dist_p <= BALLISTIC_RANGE and lance_state == "idle" and lance_cd <= 0.0:
			start_sonic_lance(last_shot_pos)
		_sync_label()
	else:
		# Player relocated out of firing nest (or in smoke) AND stays silent -> 1.5s disengage cleanly lowers arms!
		noise_meter = maxf(0.0, noise_meter - 24.0 * delta)
		if state in ["hunt", "investigate"] or guard_arms:
			stealth_quiet_timer += delta
			if stealth_quiet_timer >= STEALTH_DISENGAGE_SECONDS:
				state = "patrol"
				noise_meter = 0.0
				stealth_quiet_timer = 0.0
				shot_origin_active = false
				echo_charging = false
				echo_charge_left = 0.0
				set_guard_arms(false, 0.0)
				game._notice("✦ 潜行移位并静默 1.5 秒生效！古洞循音石卫放弃搜索并放开双臂，趁机瞄准胸口蓝核！", Color("7ceeff"))
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

	# Movement & 4-move acoustic combat rhythm (strictly confined inside Yanxia Cave!)
	var move_target := root_node.position
	var move_speed := 1.65
	var rage_spd_mult := 1.22 if enraged_resonance else 1.0
	if state == "hunt":
		move_target = _ground_pos(_clamp_to_cave(ppos if player_is_noisy else investigate_pos))
		move_speed = ((1.40 if is_conf_m else 1.15) if guard_arms else (4.15 if is_conf_m else 3.55)) * rage_spd_mult
		if sonar_cd <= 0.0:
			sonar_cd = 2.4
			game.play_sfx("warden_sonar", -9)
			spawn_sonar_ring(root_node.position, Color("ffd166") if guard_arms else Color("ff5c5c"), 11.0)
		var blast_range := 10.8 if is_conf_m else 9.5
		if player_in_cave and player_is_noisy and dist_p <= blast_range and attack_cd <= 0.0 and game.rules.combat_mode:
			_deliver_sonic_retaliation(dist_p < 3.8, guard_arms)
		# Move 3: Cavern Quake Stalactite Rings during hunt
		if (player_in_cave or dist_p <= BALLISTIC_RANGE) and not in_smoke and quake_cd <= 0.0 and lance_state == "idle" and game.rules.combat_mode:
			_trigger_cavern_quake(ppos if (player_is_noisy or camping_shot) else investigate_pos)
		# Move 4: Confidential-Only Active Echolocation Sweep!
		if is_conf_m and (player_in_cave or dist_p <= BALLISTIC_RANGE) and not echo_charging and echo_sweep_cd <= 0.0 and lance_state == "idle":
			echo_charging = true
			echo_charge_left = 1.15
			spawn_sonar_ring(root_node.position, Color("ffd15c"), 15.0)
			game.play_sfx("warning_lock", -8)
			game._notice("📡 机密预警：古洞石卫蓄力【主动声呐扫描】（1.15s）！立即按 [Z] 匍匐贴地或躲入 [G] 烟雾！", Color("ffd15c"))
			_sync_label()
	elif state == "investigate":
		move_target = _ground_pos(_clamp_to_cave(investigate_pos))
		move_speed = (1.25 if guard_arms else 2.55) * rage_spd_mult
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
	if flat_delta.length() > stop_dist and lance_state != "charging":
		var step := flat_delta.normalized() * minf(move_speed * delta, flat_delta.length() - stop_dist)
		var next_xz := _clamp_to_cave(Vector3(root_node.position.x + step.x, 0.0, root_node.position.z + step.y))
		root_node.position = _ground_pos(next_xz)
	if state == "hunt" or guard_arms or lance_state == "charging":
		var face_target := last_shot_pos if (camping_shot or lance_state == "charging") else (ppos if player_is_noisy else investigate_pos)
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
