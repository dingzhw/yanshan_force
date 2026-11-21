extends Node3D
## Yanxia Ancient Cave Acoustic Guardian Boss ("古洞循音石卫" · v0.8.4 Articulated Dual-Arm Guard).
## Blind karst guardian strictly guarding Yanxia Ancient Cave & immediate forecourt:
## - Articulated Blender 4.5 hierarchy: warden_body, head_crest, arm_left_pivot, arm_right_pivot (with thick青石臂盾)
## - Tightened 0.30m chest energy core hitbox (shrunk from 0.56m for rewarding marksmanship!)
## - Hit -> Dual-Arm Guard (guard_arms=true, 2.4-3.2s): arms snap crossed across chest, frontal shots deflect off
##   stone arm-shields (warden_shield_deflect.wav, 10/8 chip dmg) with tactical HUD guidance.
## - Active Pursuit / Stagger / [G] Smoke EMP / Shaoyu [V] Slam -> Arms fling wide open exposing the 0.30m cyan core
##   for high-value crit bursts (55/45 active, 85/70 stunned)!
## - Strictly leashed inside Yanxia Cave corridor (x=-44.8..-38.4, z=-67.8..-53.2; exits hunt immediately outside cave).

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
const CORE_HIT_RADIUS := 0.30
const CORE_VISUAL_RADIUS := 0.18

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

var state := "patrol"  # "patrol" | "investigate" | "hunt" | "stunned" | "defeated"
var max_hp := MAX_HP_NORMAL
var hp := MAX_HP_NORMAL
var stagger_accum := 0
var hit_flash_left := 0.0
var deflect_flash_left := 0.0
var guard_arms := false
var guard_left := 0.0
var pursuit_open_left := 0.0
var pursuit_hits_taken := 0
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

	# Compact 0.30m glowing cyan sonar chest core weakpoint (shrunk from 0.56m in v0.8.4!)
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
	if xz.z <= -58.2 and xz.x >= CAVE_MIN_X and xz.x <= CAVE_MAX_X:
		return Vector3(xz.x, 6.53, xz.z)
	return Vector3(xz.x, float(game.terrain_height(xz.x, xz.z)), xz.z)

func _clamp_to_cave(xz: Vector3) -> Vector3:
	return Vector3(clampf(xz.x, CAVE_MIN_X, CAVE_MAX_X), 0.0, clampf(xz.z, CAVE_MIN_Z, CAVE_MAX_Z))

func is_mode_active() -> bool:
	return is_instance_valid(game) and game.rules.combat_mode and not game.rules.prologue_mode

func max_hp_for_mode() -> int:
	return MAX_HP_CONFIDENTIAL if (is_instance_valid(game) and game.rules.is_confidential()) else MAX_HP_NORMAL

func set_guard_arms(enabled: bool, duration: float = 2.8):
	guard_arms = enabled and is_alive() and state != "stunned"
	guard_left = duration if guard_arms else 0.0
	if is_instance_valid(guard_area):
		guard_area.collision_layer = HIT_LAYER if guard_arms else 0
	_sync_label()

func apply_stun(duration: float):
	if not is_alive():
		return
	state = "stunned"
	stun_left = maxf(stun_left, duration)
	pursuit_open_left = 0.0
	pursuit_hits_taken = 0
	set_guard_arms(false, 0.0)
	_sync_label()

func reset():
	state = "patrol"
	max_hp = max_hp_for_mode()
	hp = max_hp
	stagger_accum = 0
	hit_flash_left = 0.0
	deflect_flash_left = 0.0
	guard_arms = false
	guard_left = 0.0
	pursuit_open_left = 0.0
	pursuit_hits_taken = 0
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
			if state == "stunned":
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
	if state == "stunned":
		status_label.text = "💫 古洞循音石卫 · 失衡破防 %.1fs（集火蓝核暴击！） HP %d/%d" % [maxf(0.0, stun_left), hp, max_hp]
		status_label.modulate = Color("ffd86b")
	elif guard_arms:
		status_label.text = "🛡 古洞循音石卫 · 双臂护核！拉扯诱其追击  HP %d/%d" % [hp, max_hp]
		status_label.modulate = Color("ffd166")
	elif state == "hunt":
		status_label.text = "⚠ 古洞循音石卫 · 追击露核！（打胸口蓝核暴击！） HP %d/%d" % [hp, max_hp]
		status_label.modulate = Color("ff5c5c")
	elif state == "investigate":
		status_label.text = "🌀 古洞循音石卫 · 声波搜寻 (%d%%)  HP %d/%d" % [pct, hp, max_hp]
		status_label.modulate = Color("ffd15c")
	else:
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
			if not guard_arms:
				pursuit_open_left = 3.2
				pursuit_hits_taken = 0
			game.play_sfx("warden_sonar", -7)
			spawn_sonar_ring(root_node.position, Color("ff5c5c"), 11.5)
			if is_instance_valid(game.player):
				game.player.add_screen_shake(0.28)
			game._notice("⚠ 古洞循音石卫惊醒追击！等其张臂追击时狙击 0.30m 蓝核，或用 [G]烟雾 / [V]天生神力 震晕破核！", Color("ff6b6b"))
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
		noise_meter = 10.0
		apply_stun(5.5)
		game._notice("✦ 烟雾 EMP 震开石卫双臂并致盲 5.5 秒！趁现在集火胸前蓝核（每枪 85 暴击伤害）！", Color("7ceeff"))

func _deliver_sonic_retaliation(is_close_slam: bool = false):
	if not is_alive() or state == "stunned" or not is_instance_valid(game.player):
		return
	if is_instance_valid(game.combat) and game.combat.player_in_smoke():
		return
	# Preparing a sonic slam forces arms open so aggressive play stays counterable!
	if guard_arms:
		set_guard_arms(false, 0.0)
		pursuit_open_left = maxf(pursuit_open_left, 2.2)
		pursuit_hits_taken = 0
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
	game._notice("💥 古洞循音石卫释放%s（-%d 伤害）！趁其双臂张开瞄准蓝核反打，或按 [G]/[V] 震晕！" % [
		"重锤震地" if is_close_slam else "声波冲击", dmg
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
		stagger_accum += maxi(4, roundi(float(dmg) * 0.5))
		deflect_flash_left = 0.18
		hit_flash_left = 0.08
		game.show_hitmarker(false)
		game.play_sfx("warden_shield_deflect", -7)
	elif part == "core":
		is_crit = true
		dmg = (70 if is_conf else 85) if state == "stunned" else (45 if is_conf else 55)
		hp = maxi(0, hp - dmg)
		stagger_accum += dmg
		hit_flash_left = 0.18
		game.show_hitmarker(true)
		game.play_sfx("hit_correct", -9)
	else:
		dmg = 16 if is_conf else 20
		hp = maxi(0, hp - dmg)
		stagger_accum += dmg
		hit_flash_left = 0.16
		game.show_hitmarker(false)
		game.play_sfx("knife_hit", -9)

	var triggered_stagger := false
	if hp > 0 and state != "stunned" and stagger_accum >= STAGGER_THRESHOLD:
		stagger_accum = 0
		apply_stun(1.4)
		triggered_stagger = true
		spawn_sonar_ring(root_node.position, Color("ffd86b"), 8.5)
		game.play_sfx("boss_phase", -11)

	if hp > 0 and not triggered_stagger and state != "stunned":
		var was_pursuit_open: bool = (state == "hunt" and not guard_arms and pursuit_open_left > 0.0)
		register_noise(game.player.position, 48.0 if blocked_by_guard else 68.0, not blocked_by_guard)
		if not blocked_by_guard:
			if not was_pursuit_open:
				# Hit while patrol/investigate/braced -> IMMEDIATELY snap both stone arm-shields across chest core!
				pursuit_open_left = 0.0
				pursuit_hits_taken = 0
				set_guard_arms(true, rng.randf_range(2.4, 3.2))
			else:
				# Hit while actively chasing with arms open -> allows a crisp 2-shot punish window before snapping arms back up!
				pursuit_hits_taken += 1
				if pursuit_hits_taken >= 2:
					pursuit_open_left = 0.0
					pursuit_hits_taken = 0
					set_guard_arms(true, rng.randf_range(2.4, 3.0))

	if hp <= 0:
		_on_defeated()
	else:
		_sync_label()
		if triggered_stagger:
			game._notice("⚡ 击破石卫平衡！双臂弹开陷入失衡硬直 1.4 秒（剩余 %d/%d HP · 趁机速射胸前蓝核！）" % [hp, max_hp], Color("ffd86b"))
		elif blocked_by_guard:
			game._notice("🛡 石卫双臂护核！子弹被青石臂盾弹开（-%d 擦伤 · 剩 %d/%d HP），拉扯诱其追击再破核！" % [dmg, hp, max_hp], Color("ffd166"))
		elif is_crit:
			var guard_note := " · 石卫立即举臂护核！" if guard_arms else ""
			game._notice("✦ 暴击石卫发光蓝核 -%d HP！（剩余 %d/%d HP%s）" % [dmg, hp, max_hp, guard_note], Color("7ceeff"))
		else:
			var guard_note2 := " · 石卫合臂护核，拉扯诱其追击露核！" if guard_arms else " · 瞄准胸前 0.30m 蓝核可触发高额暴击！"
			game._notice("💥 命中石卫岩甲 -%d HP（剩余 %d/%d HP%s）" % [dmg, hp, max_hp, guard_note2], Color("ffe08c"))
	return true

func _on_defeated():
	state = "defeated"
	noise_meter = 0.0
	guard_arms = false
	guard_left = 0.0
	pursuit_open_left = 0.0
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

	if state == "stunned":
		speed = 14.0
		target_l = Vector3(0.32, 0.48, -0.52)
		target_r = Vector3(0.32, -0.48, 0.52)
		target_h = Vector3(-0.42, sin(elapsed * 8.0) * 0.14, 0.0)
	elif guard_arms:
		speed = 16.0
		var jolt := 0.14 if deflect_flash_left > 0.0 else 0.0
		# Interlocking X-brace: both thick stone arm-shields fold tightly across the chest covering the 0.30m blue core!
		target_l = Vector3(-0.88 + jolt, 0.92, 0.22)
		target_r = Vector3(-0.98 + jolt, -0.92, -0.22)
		target_h = Vector3(0.20, 0.0, 0.0)
	elif state == "hunt":
		speed = 12.0
		var stride := sin(elapsed * 7.2)
		# Active pursuit charge: arms flung WIDE OPEN to sides, exposing chest core completely!
		target_l = Vector3(-0.26 + stride * 0.46, -0.34, -0.46)
		target_r = Vector3(-0.26 - stride * 0.46, 0.34, 0.46)
		target_h = Vector3(-0.10, sin(elapsed * 4.2) * 0.10, 0.0)
	else:
		speed = 8.0
		var sw := sin(elapsed * 2.4)
		target_l = Vector3(sw * 0.16, -0.06, -0.10)
		target_r = Vector3(-sw * 0.16, 0.06, 0.10)
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

	# Pulsing compact 0.30m cyan chest crystal (dimmer while shielded, blazing bright when exposed in chase/stun!)
	if is_instance_valid(core_crystal_mat):
		if hit_flash_left > 0.0 and deflect_flash_left <= 0.0:
			core_crystal_mat.albedo_color = Color("ffffff")
			core_crystal_mat.emission = Color("ffd86b")
			core_crystal_mat.emission_energy_multiplier = 4.2
		elif state == "stunned":
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

	if state == "stunned":
		stun_left -= delta
		if is_instance_valid(model_node):
			model_node.rotation.x = lerpf(model_node.rotation.x, -0.26, minf(delta * 10.0, 1.0))
			model_node.position.z = lerpf(model_node.position.z, -0.14 if hit_flash_left > 0.0 else 0.0, minf(delta * 16.0, 1.0))
		_update_articulation(delta)
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

	# Strictly enforce Yanxia Cave territory leash: exiting the cave IMMEDIATELY breaks hunt & drops guard!
	if (state in ["hunt", "investigate"] or guard_arms) and not player_in_cave:
		if state == "hunt":
			game._notice("✦ 已离开烟霞古洞范围，古洞循音石卫退回洞内巡逻。", game.MINT)
		state = "patrol"
		noise_meter = 0.0
		pursuit_open_left = 0.0
		set_guard_arms(false, 0.0)
		_sync_label()

	# Guard timer countdown: kiting further away inside cave accelerates guard drop into an open-core pursuit charge!
	if guard_arms:
		var kite_mult := 1.55 if (player_in_cave and dist_p > 4.6) else 1.0
		guard_left = maxf(0.0, guard_left - delta * kite_mult)
		if guard_left <= 0.0:
			set_guard_arms(false, 0.0)
			if player_in_cave and state in ["hunt", "investigate"]:
				state = "hunt"
				noise_meter = maxf(noise_meter, 82.0)
				pursuit_open_left = 3.2
				pursuit_hits_taken = 0
				spawn_sonar_ring(root_node.position, Color("ff5c5c"), 10.5)
				game.play_sfx("warden_sonar", -9)
				game._notice("⚠ 石卫张开双臂大步追击！胸口 0.30m 蓝核已暴露，立刻反击暴击！", Color("7ceeff"))
				_sync_label()
	elif pursuit_open_left > 0.0:
		pursuit_open_left = maxf(0.0, pursuit_open_left - delta)

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
		# Slower braced shuffle while guarding; fast aggressive stride with arms flung open when chasing!
		move_speed = (1.35 if is_conf_m else 1.15) if guard_arms else (4.55 if is_conf_m else 3.85)
		if sonar_cd <= 0.0:
			sonar_cd = 2.4
			game.play_sfx("warden_sonar", -9)
			spawn_sonar_ring(root_node.position, Color("ffd166") if guard_arms else Color("ff5c5c"), 11.0)
		var blast_range := 11.0 if is_conf_m else 9.5
		if player_in_cave and dist_p <= blast_range and attack_cd <= 0.0 and game.rules.combat_mode and not guard_arms:
			_deliver_sonic_retaliation(dist_p < 3.8)
	elif state == "investigate":
		move_target = _ground_pos(_clamp_to_cave(investigate_pos))
		move_speed = 1.20 if guard_arms else 2.55
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
	if state == "hunt" or guard_arms:
		var face_p := Vector2(ppos.x - root_node.position.x, ppos.z - root_node.position.z)
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
