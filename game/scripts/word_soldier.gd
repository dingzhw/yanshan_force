extends CharacterBody3D
## Tactical Word Bot / Heavy Boss with 4 archetypes, 1-shot Headshot weakpoint, 2-shot Word Shield, zero-damage wrong-shot deflection, and true camp-standby -> pursuit AI.

enum Action { PATROL, ADVANCE, AIM, COVER }
enum Archetype { ASSAULT_BOT, SCOUT_DRONE, SNIPER_GUARD, BOSS_WARDEN }

const HIT_LAYER = 4
const TacticalProps = preload("res://scripts/tactical_props.gd")

var combat
var zone: int
var option: int
var archetype: int = Archetype.ASSAULT_BOT
var assigned_word: Dictionary = {}
var home: Vector3
var cover: Vector3
var side: float
var patrol: Array[Vector3] = []
var patrol_index = 0
var action = Action.PATROL
var defeated = false

var max_hp: int = 90
var melee_hits_taken: int = 0
var hp: int = 90
var max_shield_layers: int = 2
var shield_layers: int = 2
var stun_left: float = 0.0
var knockdown_left: float = 0.0
var knockdown_vel: Vector3 = Vector3.ZERO
var exposed_left: float = 0.0
var wrong_flash_left: float = 0.0
var boss_phase: int = 3
var boss_ring_cd: float = 4.2
var shield_intact: bool = true

# v0.8.6 Normal Mode Boss ("雾隐先锋·铁面词卫") — 3-Phase Word-Shield Matrix + Tactical Action Moves
var boss_core_pulse_shots: int = 0       # Capped 1-shot crit pulse after shield break (NO 4.5s infinite spray!)
var vanguard_shields_root: Node3D = null
var vanguard_shields: Array = []         # 3 dicts: {slot, part, base_pos, area, word_label, tag_label, frame_mat, screen_mat, active, word}
var vanguard_correct_slot: int = -1
var vanguard_active_count: int = 0       # 0 = Phase 1 single shield; 2 = Phase 2 Twin Shoulder; 3 = Phase 3 Triple Matrix
var vanguard_move_state: String = "idle" # "idle" | "charge_windup" | "charging" | "wave_windup"
var vanguard_move_timer: float = 0.0
var vanguard_move_cd: float = 6.2
var vanguard_charge_target: Vector3 = Vector3.ZERO
var vanguard_drones_spawned: bool = false

const VANGUARD_SHIELD_SPECS := [
	{"part": "左肩词盾", "pos": Vector3(-1.54, 1.92, 0.58)},
	{"part": "右肩词盾", "pos": Vector3(1.54, 1.92, 0.58)},
	{"part": "玄顶词盾", "pos": Vector3(0.00, 2.72, 0.56)},
]

# v0.8.6 Flagship Confidential Skyfall Overlord ("雾隐机关王·玄铁词尊") — Articulated Rig + 2-Round Orbiting Shields + Ultimate「天地万象」
var is_skyfall_overlord: bool = false
var multi_shields: Array = []          # 5 dicts: {slot, part, base_pos, area, word_label, tag_label, frame_mat, screen_mat, broken, word}
var overlord_seq_words: Array = []     # Active round words in strict required break order (5 in R1, 3 in R2)
var overlord_seq_slots: Array = []     # Active slot indices for current round
var overlord_seq_step: int = 0
var overlord_round: int = 1            # 1 (500 HP, 5 shields; last 3 orbit!) | 2 (300 HP, 3 fast-orbiting shields + 10s timer)
var overlord_orbit_active: bool = false
var overlord_orbit_angle: float = 0.0
var overlord_r2_timer: float = 0.0
var overlord_ultimate_count: int = 0
var overlord_ultimate_state: String = "none" # "none" | "descending" | "holding" | "lifting" | "recovery"
var overlord_ultimate_timer: float = 0.0
var overlord_recovery_left: float = 0.0
var mirror_mountain_node: Node3D = null
var skyfall_beam_node: Node3D = null
var skyfall_state: String = "landed"   # "idle" | "dropping" | "landed"
var skyfall_y_offset: float = 0.0
var skyfall_vel: float = 0.0
var overlord_shields_root: Node3D
var ov_arm_l: Node3D = null
var ov_arm_r: Node3D = null
var ov_head: Node3D = null
var ov_halo: Node3D = null
var ov_move_cd: float = 3.2
var ov_move_state: String = "idle"     # "idle" | "flash_dash" | "whirlwind" | "sword_wave" | "dharma_barrage"
var ov_move_timer: float = 0.0
var ov_move_cycle: int = 0
var ov_dash_target: Vector3 = Vector3.ZERO
var ov_slash_fired: bool = false

const OVERLORD_R2_DURATION := 10.0
const OVERLORD_RECOVERY_DURATION := 4.5
const OVERLORD_TRIGGER_RADIUS := 22.0

const OVERLORD_SHIELD_SPECS := [
	{"part": "左肩甲", "pos": Vector3(-2.15, 3.12, 0.92)},
	{"part": "右肩甲", "pos": Vector3(2.15, 3.12, 0.92)},
	{"part": "左臂盾", "pos": Vector3(-2.35, 1.72, 1.05)},
	{"part": "右臂盾", "pos": Vector3(2.35, 1.72, 1.05)},
	{"part": "胸核盾", "pos": Vector3(0.00, 2.38, 1.24)},
]

var visual_root: Node3D
var shield_area: Area3D
var head_area: Area3D
var core_area: Area3D
var core_material: StandardMaterial3D
var hp_bar_root: Node3D
var hp_fill: MeshInstance3D
var hp_fill_mat: StandardMaterial3D
var word_label: Label3D
var tag_label: Label3D
var base_tag_text: String = ""
var base_border_col: Color = Color("5ce0b8")
var is_nemesis_bounty: bool = false
var shield_material: StandardMaterial3D
var frame_material: StandardMaterial3D
var visor: StandardMaterial3D
var laser_beam: MeshInstance3D
var legs: Array[Node3D] = []
var defeat_tween: Tween

var stride = 0.0
var hover_clock = 0.0
var cooldown = 0.0
var aim_left = 0.0
var cover_left = 0.0
var cover_goal: Vector3
var claimed_cover_idx: int = -1
var is_bounding_to_cover: bool = false
var bound_goal: Vector3 = Vector3.ZERO
var peek_goal: Vector3 = Vector3.ZERO
var cover_reposition_cd: float = 0.0
var suppress_cd: float = 0.0
var occluded_prompt_time: float = 0.0
var peek_phase: float = 0.0

func attack_range() -> float:
	if archetype == Archetype.BOSS_WARDEN:
		return 30.0
	if archetype == Archetype.SNIPER_GUARD:
		return 28.0
	if archetype == Archetype.SCOUT_DRONE:
		return 21.5
	return 19.5

func move_speed() -> float:
	if archetype == Archetype.BOSS_WARDEN:
		return 2.75
	if archetype == Archetype.SCOUT_DRONE:
		return 4.25
	if archetype == Archetype.SNIPER_GUARD:
		return 2.45
	return 3.20

func base_shot_damage() -> int:
	if archetype == Archetype.BOSS_WARDEN:
		return 24
	if archetype == Archetype.SNIPER_GUARD:
		return 16
	if archetype == Archetype.SCOUT_DRONE:
		return 8
	return 10

func fire_interval() -> float:
	if archetype == Archetype.BOSS_WARDEN:
		return 2.15
	if archetype == Archetype.SCOUT_DRONE:
		return 2.55
	if archetype == Archetype.SNIPER_GUARD:
		return 3.80
	return 3.05

func aim_windup() -> float:
	if archetype == Archetype.BOSS_WARDEN:
		return 0.72
	if archetype == Archetype.SNIPER_GUARD:
		return 1.08
	if archetype == Archetype.SCOUT_DRONE:
		return 0.72
	return 0.82

func _base_max_hp() -> int:
	if archetype == Archetype.BOSS_WARDEN:
		return 500 if is_skyfall_overlord else 600
	if archetype == Archetype.SCOUT_DRONE:
		return 70
	if archetype == Archetype.SNIPER_GUARD:
		return 90
	return 90

func setup(controller, zone_index: int, index: int, barrier: Vector3, bot_type: int = Archetype.ASSAULT_BOT, skyfall_mode: bool = false):
	combat = controller
	zone = zone_index
	option = index
	archetype = bot_type
	is_skyfall_overlord = (bot_type == Archetype.BOSS_WARDEN and skyfall_mode)
	skyfall_state = "idle" if is_skyfall_overlord else "landed"
	skyfall_y_offset = 0.0
	skyfall_vel = 0.0
	overlord_round = 1
	overlord_orbit_active = false
	overlord_orbit_angle = 0.0
	overlord_r2_timer = 0.0
	overlord_ultimate_count = 0
	overlord_ultimate_state = "none"
	overlord_ultimate_timer = 0.0
	overlord_recovery_left = 0.0
	ov_move_state = "idle"
	ov_move_cd = 2.8
	ov_move_timer = 0.0
	ov_move_cycle = 0
	boss_core_pulse_shots = 0
	vanguard_correct_slot = -1
	vanguard_active_count = 0
	vanguard_move_state = "idle"
	vanguard_move_timer = 0.0
	vanguard_move_cd = 5.8
	vanguard_charge_target = Vector3.ZERO
	vanguard_drones_spawned = false
	max_hp = _base_max_hp()
	hp = max_hp
	melee_hits_taken = 0
	max_shield_layers = 2
	shield_layers = max_shield_layers
	boss_phase = 3
	stun_left = 0.0
	knockdown_left = 0.0
	knockdown_vel = Vector3.ZERO
	exposed_left = 0.0
	wrong_flash_left = 0.0
	shield_intact = true
	defeated = false
	action = Action.PATROL
	cover = barrier
	side = -1.0 if index % 2 == 0 else 1.0
	if is_skyfall_overlord:
		home = combat.game.Layout.on_ground(combat.game.Layout.CLOUD_ARENA_CENTER)
	else:
		home = combat.game.Layout.on_ground(cover + Vector3(side * 1.35, 0, -1.65))
	position = home + Vector3.UP * 0.06
	patrol = [
		home,
		combat.game.Layout.on_ground(cover + Vector3(side * 1.85, 0, 0.55)),
		combat.game.Layout.on_ground(cover + Vector3(side * 1.55, 0, -2.55))
	]
	patrol_index = 1
	hover_clock = index * 1.3
	peek_phase = index * 1.15
	cooldown = 0.65 + index * 0.30
	is_bounding_to_cover = false
	cover_reposition_cd = 0.0
	suppress_cd = 0.0
	occluded_prompt_time = 0.0
	peek_goal = home
	collision_layer = 0 if is_skyfall_overlord else HIT_LAYER
	collision_mask = 1 | HIT_LAYER | 8
	floor_snap_length = 0.38
	var is_boss := archetype == Archetype.BOSS_WARDEN
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.46 if is_boss else 0.35
	# Keep body capsule strictly below the head weakpoint sphere so headshots never hit torso first!
	capsule.height = 1.86 if is_boss else 1.42
	var hitbox = CollisionShape3D.new()
	hitbox.position.y = 0.94 if is_boss else 0.72
	hitbox.shape = capsule
	add_child(hitbox)
	_build_model()
	if is_skyfall_overlord:
		visible = false
		if is_instance_valid(head_area):
			head_area.collision_layer = 0
		if is_instance_valid(core_area):
			core_area.collision_layer = 0

func _metal_mat(color: Color, metallic = 0.22, rough = 0.72) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = minf(metallic, 0.32)
	m.roughness = maxf(rough, 0.66)
	m.metallic_specular = 0.12
	return m

func _ceramic_plate_mat(color: Color, emerald_weave: bool = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = TacticalProps.ripstop_texture(emerald_weave)
	m.uv1_scale = Vector3(2.2, 2.2, 1.0)
	m.metallic = 0.12
	m.roughness = 0.78
	m.metallic_specular = 0.08
	return m

func _bronze_trim_mat(color: Color = Color("c29a4b")) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.76
	m.roughness = 0.34
	m.metallic_specular = 0.28
	return m

func _oct_drum(parent: Node3D, at: Vector3, top_r: float, bot_r: float, h: float, mat: Material, segs: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = h
	cyl.radial_segments = segs
	mi.mesh = cyl
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _build_model():
	var game = combat.game
	visual_root = Node3D.new()
	add_child(visual_root)

	if archetype == Archetype.BOSS_WARDEN:
		_build_boss_chassis(game)
	elif archetype == Archetype.SCOUT_DRONE:
		_build_drone_chassis(game)
	elif archetype == Archetype.SNIPER_GUARD:
		_build_sniper_chassis(game)
	else:
		_build_assault_chassis(game)

	# 1. Head / Optical Core Weakpoint Area (1-Shot Instant Kill on Correct Soldier!)
	# Positioned cleanly ABOVE the chest word shield so players can reliably aim for headshots!
	head_area = Area3D.new()
	head_area.set_meta("hit_zone", "head")
	head_area.collision_layer = HIT_LAYER
	head_area.collision_mask = 0
	head_area.monitoring = false
	head_area.monitorable = false
	var head_y := (3.42 if is_skyfall_overlord else 2.30) if archetype == Archetype.BOSS_WARDEN else (1.88 if archetype == Archetype.SNIPER_GUARD else (1.88 if archetype == Archetype.SCOUT_DRONE else 1.78))
	head_area.position = Vector3(0, head_y, 0.14)
	add_child(head_area)
	var hshape = SphereShape3D.new()
	hshape.radius = (0.52 if is_skyfall_overlord else 0.40) if archetype == Archetype.BOSS_WARDEN else 0.34
	var hcol = CollisionShape3D.new()
	hcol.shape = hshape
	head_area.add_child(hcol)

	# 2. Overhead Compact 3D Health / Shield-Layer Bar
	hp_bar_root = Node3D.new()
	hp_bar_root.position = Vector3(0, (4.55 if is_skyfall_overlord else 3.46) if archetype == Archetype.BOSS_WARDEN else 2.26, 0)
	add_child(hp_bar_root)
	var bg = MeshInstance3D.new()
	var bg_quad = QuadMesh.new()
	bg_quad.size = Vector2(1.45 if archetype == Archetype.BOSS_WARDEN else 0.92, 0.14 if archetype == Archetype.BOSS_WARDEN else 0.09)
	bg.mesh = bg_quad
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.08, 0.11, 0.12, 0.86)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bg_mat
	bg.visibility_range_end = 85.0
	hp_bar_root.add_child(bg)

	hp_fill = MeshInstance3D.new()
	var fill_quad = QuadMesh.new()
	fill_quad.size = Vector2(1.37 if archetype == Archetype.BOSS_WARDEN else 0.86, 0.09 if archetype == Archetype.BOSS_WARDEN else 0.055)
	hp_fill.mesh = fill_quad
	hp_fill.position.z = 0.01
	hp_fill_mat = StandardMaterial3D.new()
	hp_fill_mat.albedo_color = Color("ffb84d") if archetype == Archetype.BOSS_WARDEN else Color("5fe3a8")
	hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hp_fill.material_override = hp_fill_mat
	hp_fill.visibility_range_end = 85.0
	hp_bar_root.add_child(hp_fill)

	# 3. Chest-Mounted Holographic Electronic Word Shield (2 Shots to Break & Kill on Correct Soldier)
	shield_area = Area3D.new()
	shield_area.set_meta("hit_zone", "shield")
	var shield_y := 1.70 if archetype == Archetype.BOSS_WARDEN else (1.40 if archetype == Archetype.SNIPER_GUARD else (1.38 if archetype == Archetype.SCOUT_DRONE else 1.34))
	shield_area.position = Vector3(0, shield_y, 0.66 if archetype == Archetype.BOSS_WARDEN else 0.46)
	shield_area.collision_layer = 0
	shield_area.collision_mask = 0
	shield_area.monitoring = false
	shield_area.monitorable = false
	shield_area.hide()
	add_child(shield_area)

	var bw := 2.24 if archetype == Archetype.BOSS_WARDEN else 2.00
	var bh := 0.78 if archetype == Archetype.BOSS_WARDEN else 0.70
	var badge_shape = BoxShape3D.new()
	badge_shape.size = Vector3(bw, bh, 0.16)
	var badge_hitbox = CollisionShape3D.new()
	badge_hitbox.shape = badge_shape
	shield_area.add_child(badge_hitbox)

	base_border_col = Color("ffd15c") if archetype == Archetype.BOSS_WARDEN else (Color("ff9b54") if archetype == Archetype.SCOUT_DRONE else (Color("ff5d6c") if archetype == Archetype.SNIPER_GUARD else Color("5ce0b8")))
	var outer_bezel = game._mesh_box(shield_area, Vector3(0, 0, -0.015), Vector3(bw, bh, 0.055), base_border_col)
	frame_material = outer_bezel.material_override
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Antique-bronze Jiangnan corner brackets framing the tactical word screen
	var corner_mat := _bronze_trim_mat()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var brk = game._mesh_box(shield_area, Vector3(sx * (bw * 0.5 - 0.06), sy * (bh * 0.5 - 0.045), 0.022), Vector3(0.16, 0.12, 0.045), Color.WHITE)
			brk.material_override = corner_mat

	var screen_box = game._mesh_box(shield_area, Vector3(0, -0.02, 0.02), Vector3(bw - 0.12, bh - 0.12, 0.05), Color("edf2e6"))
	shield_material = screen_box.material_override
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var role_text = ["雾隐突击兵", "雾隐侦察蜂", "雾隐狙击卫", "★ 雾隐机关王·玄铁词尊" if is_skyfall_overlord else "★ 雾隐先锋·铁面词卫"][archetype]
	base_tag_text = "%s · %s" % [char(65 + (option % 8)), role_text]
	tag_label = game._label3d(shield_area, base_tag_text, Vector3(0, 0.22 if archetype == Archetype.BOSS_WARDEN else 0.20, 0.055), 18, Color("143832"))
	tag_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag_label.pixel_size = 0.0044
	tag_label.outline_size = 0
	tag_label.visibility_range_end = 85.0

	word_label = game._label3d(shield_area, "", Vector3(0, -0.05, 0.058), 58, Color("102620"))
	word_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	word_label.pixel_size = 0.0052
	word_label.width = 345
	word_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	word_label.outline_size = 2
	word_label.outline_modulate = Color("f6f9f2")
	word_label.visibility_range_end = 98.0

	# Sniper / Aim Laser Sight Beam
	laser_beam = MeshInstance3D.new()
	var beam_box = BoxMesh.new()
	beam_box.size = Vector3(0.030 if archetype == Archetype.BOSS_WARDEN else 0.025, 0.030 if archetype == Archetype.BOSS_WARDEN else 0.025, 1.0)
	laser_beam.mesh = beam_box
	var laser_mat = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(1.0, 0.22, 0.18, 0.88) if archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN] else Color(1.0, 0.65, 0.22, 0.65)
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_beam.material_override = laser_mat
	laser_beam.hide()
	add_child(laser_beam)
	if is_skyfall_overlord:
		_build_overlord_multi_shields(game)
	elif archetype == Archetype.BOSS_WARDEN:
		_build_vanguard_shields(game)
	_refresh_hp_bar()

func _build_drone_chassis(game):
	legs.clear()
	var hull_mat = _ceramic_plate_mat(Color("344d48"), true)
	var accent_mat = _bronze_trim_mat(Color("b88b44"))
	var wing_mat = _metal_mat(Color("1e2928"), 0.24, 0.74)
	_oct_drum(visual_root, Vector3(0, 1.66, 0), 0.30, 0.26, 0.26, hull_mat, 8)
	# Octagonal optical dome + eave-brim cap for crisp 1-shot headshot readability
	_oct_drum(visual_root, Vector3(0, 1.88, 0.05), 0.18, 0.22, 0.24, wing_mat, 8)
	_oct_drum(visual_root, Vector3(0, 2.02, 0.05), 0.06, 0.25, 0.07, accent_mat, 8)
	for x in [-0.58, 0.58]:
		var arm = game._mesh_box(visual_root, Vector3(x * 0.56, 1.72, 0), Vector3(0.46, 0.05, 0.10), Color.WHITE)
		arm.material_override = accent_mat
		var ring = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.17
		torus.outer_radius = 0.23
		ring.mesh = torus
		ring.position = Vector3(x, 1.74, 0)
		ring.material_override = wing_mat
		visual_root.add_child(ring)
		var thruster = _oct_drum(visual_root, Vector3(x, 1.71, 0), 0.13, 0.13, 0.025, game._material(Color("6cf0d0"), true), 8)
		thruster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visor = game._mesh_box(visual_root, Vector3(0, 1.88, 0.26), Vector3(0.30, 0.10, 0.04), Color("ffb35c")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _build_assault_chassis(game):
	var armor_mat = _ceramic_plate_mat(Color("42665c") if zone % 2 == 0 else Color("3c5960"), zone % 2 == 0)
	var dark_mat = _metal_mat(Color("1f2b2b"), 0.20, 0.78)
	var bronze_mat = _bronze_trim_mat()
	# Tapered Qinglü lamellar chest cuirass + waist belt
	_oct_drum(visual_root, Vector3(0, 1.18, 0), 0.36, 0.30, 0.64, armor_mat, 8)
	var belt = game._mesh_box(visual_root, Vector3(0, 0.84, 0), Vector3(0.56, 0.10, 0.38), Color.WHITE)
	belt.material_override = bronze_mat
	# Octagonal tactical helm + Jiangnan sloped eave crest ('斗笠飞檐盔')
	_oct_drum(visual_root, Vector3(0, 1.72, 0.04), 0.21, 0.23, 0.32, dark_mat, 8)
	_oct_drum(visual_root, Vector3(0, 1.92, 0.03), 0.08, 0.32, 0.12, armor_mat, 8)
	var rim = _oct_drum(visual_root, Vector3(0, 1.86, 0.03), 0.33, 0.34, 0.025, bronze_mat, 8)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visor = game._mesh_box(visual_root, Vector3(0, 1.73, 0.25), Vector3(0.34, 0.10, 0.04), Color("7ef0c8")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.46, 0.46]:
		var sgn := signf(x)
		var pauldron = game._mesh_box(visual_root, Vector3(x, 1.36, 0.02), Vector3(0.26, 0.22, 0.36), Color.WHITE)
		pauldron.rotation.z = -sgn * 0.22
		pauldron.material_override = armor_mat
		var p_trim = game._mesh_box(visual_root, Vector3(x * 1.06, 1.26, 0.02), Vector3(0.27, 0.04, 0.38), Color.WHITE)
		p_trim.rotation.z = -sgn * 0.22
		p_trim.material_override = bronze_mat
		_oct_drum(visual_root, Vector3(x, 1.02, 0.18), 0.085, 0.075, 0.34, dark_mat, 6)
	for x in [-0.21, 0.21]:
		var leg = Node3D.new()
		leg.position = Vector3(x, 0.78, 0)
		visual_root.add_child(leg)
		_oct_drum(leg, Vector3(0, -0.30, 0), 0.115, 0.095, 0.54, dark_mat, 6)
		var greave = game._mesh_box(leg, Vector3(0, -0.44, 0.05), Vector3(0.18, 0.26, 0.14), Color.WHITE)
		greave.material_override = armor_mat
		var boot = game._mesh_box(leg, Vector3(0, -0.66, 0.07), Vector3(0.23, 0.16, 0.36), Color.WHITE)
		boot.material_override = dark_mat
		legs.append(leg)

func _build_sniper_chassis(game):
	var heavy_mat = _ceramic_plate_mat(Color("3b3632"), false)
	var trim_mat = _bronze_trim_mat(Color("b68542"))
	var dark_mat = _metal_mat(Color("1c2226"), 0.22, 0.76)
	_oct_drum(visual_root, Vector3(0, 1.24, 0), 0.42, 0.35, 0.74, heavy_mat, 8)
	_oct_drum(visual_root, Vector3(0, 1.84, 0.04), 0.23, 0.25, 0.34, dark_mat, 8)
	_oct_drum(visual_root, Vector3(0, 2.04, 0.04), 0.10, 0.34, 0.12, trim_mat, 8)
	for x in [-0.54, 0.54]:
		var sgn := signf(x)
		var pad = game._mesh_box(visual_root, Vector3(x, 1.48, 0), Vector3(0.30, 0.28, 0.44), Color.WHITE)
		pad.rotation.z = -sgn * 0.20
		pad.material_override = trim_mat
		var rail = game._mesh_box(visual_root, Vector3(x * 0.85, 1.94, 0.14), Vector3(0.09, 0.12, 0.62), Color.WHITE)
		rail.material_override = dark_mat
	visor = game._mesh_box(visual_root, Vector3(0, 1.84, 0.27), Vector3(0.38, 0.11, 0.05), Color("ff5c6c")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.25, 0.25]:
		var leg = Node3D.new()
		leg.position = Vector3(x, 0.82, 0)
		visual_root.add_child(leg)
		_oct_drum(leg, Vector3(0, -0.34, 0), 0.135, 0.11, 0.60, dark_mat, 6)
		var boot = game._mesh_box(leg, Vector3(0, -0.72, 0.08), Vector3(0.28, 0.18, 0.42), Color.WHITE)
		boot.material_override = trim_mat
		legs.append(leg)

func _build_boss_chassis(game):
	if is_skyfall_overlord:
		var path := "res://assets/slice/v082_bosses.glb"
		var loaded_mesh := false
		ov_arm_l = null
		ov_arm_r = null
		ov_head = null
		ov_halo = null
		if ResourceLoader.exists(path):
			if not game.scene_cache.has(path):
				game.scene_cache[path] = load(path)
			var inst: Node3D = game.scene_cache[path].instantiate()
			var tgt = inst.find_child("skyfall_overlord", true, false)
			if tgt is Node3D:
				if tgt.get_parent():
					tgt.get_parent().remove_child(tgt)
				tgt.owner = null
				tgt.name = "SkyfallOverlordRig"
				tgt.position = Vector3.ZERO
				visual_root.add_child(tgt)
				ov_arm_l = tgt.find_child("overlord_arm_l", true, false) as Node3D
				ov_arm_r = tgt.find_child("overlord_arm_r", true, false) as Node3D
				ov_head = tgt.find_child("overlord_head", true, false) as Node3D
				ov_halo = tgt.find_child("overlord_halo_ring", true, false) as Node3D
				loaded_mesh = true
			inst.queue_free()
		# Glowing visor handle for rage/stun color shifts
		var v_box: MeshInstance3D = game._mesh_box(visual_root, Vector3(0, 3.40, 0.42), Vector3(0.56, 0.16, 0.06), Color("ff2838"))
		visor = v_box.material_override
		visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c_box: MeshInstance3D = game._mesh_box(visual_root, Vector3(0, 2.42, 0.62), Vector3(0.50, 0.50, 0.16), Color("ff6c24"))
		core_material = c_box.material_override
		core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_area = Area3D.new()
		core_area.set_meta("hit_zone", "core")
		core_area.position = Vector3(0, 2.42, 0.68)
		core_area.collision_layer = 0
		core_area.collision_mask = 0
		add_child(core_area)
		var ccol_o := CollisionShape3D.new()
		var cshp_o := BoxShape3D.new()
		cshp_o.size = Vector3(0.66, 0.66, 0.36)
		ccol_o.shape = cshp_o
		core_area.add_child(ccol_o)
		if loaded_mesh:
			return
	var obsidian_mat = _ceramic_plate_mat(Color("222c30"), false)
	var gold_mat = _bronze_trim_mat(Color("d6a648"))
	var armor_mat = _ceramic_plate_mat(Color("2f4b44"), true)

	_oct_drum(visual_root, Vector3(0, 1.48, 0), 0.60, 0.48, 1.02, obsidian_mat, 8)
	_oct_drum(visual_root, Vector3(0, 0.94, 0), 0.42, 0.36, 0.38, armor_mat, 8)

	# Exposed glowing reactor chest core (crit weakpoint when shield/phase shattered)
	var core_box = game._mesh_box(visual_root, Vector3(0, 1.52, 0.56), Vector3(0.44, 0.44, 0.14), Color("ff9d3b"))
	core_material = core_box.material_override
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_area = Area3D.new()
	core_area.set_meta("hit_zone", "core")
	core_area.position = Vector3(0, 1.50, 0.60)
	core_area.collision_layer = HIT_LAYER
	core_area.collision_mask = 0
	core_area.monitoring = false
	core_area.monitorable = false
	add_child(core_area)
	var cshape = BoxShape3D.new()
	cshape.size = Vector3(0.56, 0.52, 0.34)
	var ccol = CollisionShape3D.new()
	ccol.shape = cshape
	core_area.add_child(ccol)

	_oct_drum(visual_root, Vector3(0, 2.26, 0.06), 0.30, 0.32, 0.42, obsidian_mat, 8)
	_oct_drum(visual_root, Vector3(0, 2.54, 0.04), 0.14, 0.48, 0.16, gold_mat, 8)
	visor = game._mesh_box(visual_root, Vector3(0, 2.26, 0.36), Vector3(0.48, 0.12, 0.06), Color("ff4f4f")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for x in [-0.76, 0.76]:
		var sgn := signf(x)
		var pauldron = game._mesh_box(visual_root, Vector3(x, 1.80, 0.0), Vector3(0.46, 0.42, 0.62), Color.WHITE)
		pauldron.rotation.z = -sgn * 0.22
		pauldron.material_override = gold_mat
		var launcher = game._mesh_box(visual_root, Vector3(x * 0.92, 2.18, -0.05), Vector3(0.24, 0.26, 0.48), Color.WHITE)
		launcher.material_override = armor_mat
		_oct_drum(visual_root, Vector3(x * 0.95, 1.24, 0.24), 0.13, 0.11, 0.52, obsidian_mat, 8)

	for x in [-0.34, 0.34]:
		var leg = Node3D.new()
		leg.position = Vector3(x, 0.92, 0)
		visual_root.add_child(leg)
		_oct_drum(leg, Vector3(0, -0.38, 0), 0.18, 0.15, 0.70, armor_mat, 8)
		var boot = game._mesh_box(leg, Vector3(0, -0.80, 0.09), Vector3(0.38, 0.22, 0.54), Color.WHITE)
		boot.material_override = gold_mat
		legs.append(leg)

func _refresh_hp_bar():
	if not is_instance_valid(hp_fill):
		return
	var ratio := 1.0
	if archetype == Archetype.BOSS_WARDEN:
		ratio = clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	else:
		ratio = clampf(float(shield_layers) / float(maxi(1, max_shield_layers)), 0.0, 1.0)
	hp_fill.scale.x = maxf(0.02, ratio)
	var full_w := 1.37 if archetype == Archetype.BOSS_WARDEN else 0.86
	hp_fill.position.x = -full_w * 0.5 * (1.0 - ratio)
	if is_instance_valid(hp_fill_mat):
		if knockdown_left > 0.0:
			hp_fill_mat.albedo_color = Color("ffd86b")
		elif stun_left > 0:
			hp_fill_mat.albedo_color = Color("56e8ff")
		elif archetype == Archetype.BOSS_WARDEN:
			hp_fill_mat.albedo_color = Color("ff5c5c") if exposed_left > 0 else Color("ffb84d")
		else:
			hp_fill_mat.albedo_color = Color("5fe3a8") if shield_layers >= 2 else Color("ff9f4a")
	if is_instance_valid(tag_label) and knockdown_left <= 0.0 and base_tag_text != "":
		tag_label.text = base_tag_text
		tag_label.modulate = Color("ffd15c") if is_nemesis_bounty else Color("d8ebe2")

func stun(seconds: float):
	if defeated:
		return
	stun_left = maxf(stun_left, seconds)
	action = Action.PATROL
	laser_beam.hide()
	_refresh_hp_bar()

func expose_boss_core(seconds: float):
	if archetype != Archetype.BOSS_WARDEN or defeated or is_skyfall_overlord:
		return
	# v0.8.6: Capped 1-shot Bonus Core Pulse (NO unlimited free bullet-spam window!)
	exposed_left = maxf(exposed_left, minf(seconds, 2.8))
	boss_core_pulse_shots = 1
	shield_intact = false
	if not vanguard_multi_active() and is_instance_valid(shield_area):
		shield_area.hide()
		shield_area.collision_layer = 0
	if is_instance_valid(core_material):
		core_material.albedo_color = Color("ff3b3b")
	_refresh_hp_bar()

func consume_boss_core_pulse():
	boss_core_pulse_shots = 0
	exposed_left = 0.0
	shield_intact = true
	if is_instance_valid(core_material):
		core_material.albedo_color = Color("ff9d3b")
	if not vanguard_multi_active() and not defeated and not assigned_word.is_empty():
		show_word(str(assigned_word.get("english", "")), false)
	_refresh_hp_bar()

func crack_shield_once():
	if defeated:
		return
	shield_layers = maxi(1, shield_layers - 1)
	if is_instance_valid(shield_material):
		shield_material.albedo_color = Color("fff0b3")
	if is_instance_valid(frame_material):
		frame_material.albedo_color = Color("ff8c3b")
	if is_instance_valid(tag_label):
		tag_label.text = "⚡ 护盾破损 (1/2) · 机动换掩体!"
		tag_label.modulate = Color("8a2d0a")
	stun_left = maxf(stun_left, 0.18)
	_refresh_hp_bar()
	# Wounded soldier immediately bounds to a fresh unoccupied cover while firing suppression shots!
	if archetype != Archetype.BOSS_WARDEN and is_instance_valid(combat) and combat.is_zone_engaged(zone):
		begin_tactical_engagement(true)
		suppress_cd = 0.12

func on_wrong_hit_flash():
	if defeated:
		return
	# Wrong target takes ZERO HP / shield damage! Flash deflection warning and duck briefly if not aiming.
	wrong_flash_left = 0.42
	if is_instance_valid(shield_material):
		shield_material.albedo_color = Color("f4a69e")
	if is_instance_valid(frame_material):
		frame_material.albedo_color = Color("ff3b30")
	if action == Action.ADVANCE and not is_bounding_to_cover and archetype != Archetype.BOSS_WARDEN:
		take_cover()
		cover_left = 0.65

func _active_border_col() -> Color:
	return Color("f5b030") if is_nemesis_bounty else base_border_col

func _active_tag_text() -> String:
	return ("★ 宿敌复习 · " + base_tag_text) if is_nemesis_bounty else base_tag_text

func _active_tag_col() -> Color:
	return Color("8a4200") if is_nemesis_bounty else Color("143832")

func set_nemesis_bounty(active: bool):
	is_nemesis_bounty = active
	if shield_layers >= max_shield_layers and wrong_flash_left <= 0:
		if is_instance_valid(frame_material):
			frame_material.albedo_color = _active_border_col()
		if is_instance_valid(tag_label):
			tag_label.text = _active_tag_text()
			tag_label.modulate = _active_tag_col()

func apply_damage(amount: int, from_english_shield: bool = false, is_crit: bool = false) -> bool:
	if defeated:
		return false
	if amount <= 0:
		on_wrong_hit_flash()
		return false
	hp = maxi(0, hp - amount)
	if archetype != Archetype.BOSS_WARDEN and hp <= 0:
		shield_layers = 0
	if archetype == Archetype.BOSS_WARDEN and not is_skyfall_overlord:
		if from_english_shield:
			shield_layers = max_shield_layers
			if is_instance_valid(tag_label):
				tag_label.text = _active_tag_text()
				tag_label.modulate = _active_tag_col()
			if is_instance_valid(frame_material):
				frame_material.albedo_color = _active_border_col()
			expose_boss_core(2.6)
			stun(0.45)
		else:
			if is_instance_valid(hp_fill_mat):
				hp_fill_mat.albedo_color = Color("ffd86b") if is_crit else Color("ff6b6b")
		var next_phase := 3 if hp > int(max_hp * 0.66) else (2 if hp > int(max_hp * 0.33) else 1)
		if next_phase < boss_phase and hp > 0:
			boss_phase = next_phase
			if combat.has_method("on_boss_phase_shift"):
				combat.on_boss_phase_shift(self, boss_phase)
	else:
		if is_instance_valid(hp_fill_mat):
			hp_fill_mat.albedo_color = Color("ffd86b") if is_crit else Color("ff6b6b")
	_refresh_hp_bar()
	if hp <= 0:
		neutralize()
		return true
	return false

func _build_vanguard_shields(game):
	vanguard_shields.clear()
	vanguard_shields_root = Node3D.new()
	vanguard_shields_root.name = "VanguardMultiShields"
	add_child(vanguard_shields_root)
	var bw := 2.02
	var bh := 0.72
	for idx in VANGUARD_SHIELD_SPECS.size():
		var sp: Dictionary = VANGUARD_SHIELD_SPECS[idx]
		var area := Area3D.new()
		area.name = "VanguardShield_%d" % idx
		area.position = sp.pos
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("hit_zone", "vanguard_shield")
		area.set_meta("vanguard_slot", idx)
		area.hide()
		vanguard_shields_root.add_child(area)

		var bshp := BoxShape3D.new()
		bshp.size = Vector3(bw, bh, 0.22)
		var bcol := CollisionShape3D.new()
		bcol.shape = bshp
		area.add_child(bcol)

		var bezel: MeshInstance3D = game._mesh_box(area, Vector3(0, 0, -0.02), Vector3(bw, bh, 0.055), Color("5ce0b8"))
		var fmat: StandardMaterial3D = bezel.material_override
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var screen: MeshInstance3D = game._mesh_box(area, Vector3(0, -0.02, 0.02), Vector3(bw - 0.14, bh - 0.14, 0.05), Color("edf6ee"))
		var smat: StandardMaterial3D = screen.material_override
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var tlbl: Label3D = game._label3d(area, "铁面·%s" % str(sp.part), Vector3(0, 0.21, 0.058), 17, Color("143832"))
		tlbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		tlbl.pixel_size = 0.0044
		tlbl.outline_size = 0
		tlbl.visibility_range_end = 95.0

		var wlbl: Label3D = game._label3d(area, "", Vector3(0, -0.06, 0.062), 56, Color("102620"))
		wlbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		wlbl.pixel_size = 0.0052
		wlbl.width = 345
		wlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wlbl.outline_size = 2
		wlbl.outline_modulate = Color("f6f9f2")
		wlbl.visibility_range_end = 100.0

		vanguard_shields.append({
			"slot": idx,
			"part": str(sp.part),
			"base_pos": sp.pos,
			"area": area,
			"word_label": wlbl,
			"tag_label": tlbl,
			"frame_mat": fmat,
			"screen_mat": smat,
			"active": false,
			"word": {},
		})

func vanguard_multi_active() -> bool:
	return archetype == Archetype.BOSS_WARDEN and not is_skyfall_overlord and vanguard_active_count >= 2

func configure_vanguard_shields(words_list: Array, active_slots: int = 2):
	## Activates 2 (Phase 2 Twin Shoulder) or 3 (Phase 3 Triple Matrix) distinct word shields on Normal Mode Boss!
	if archetype != Archetype.BOSS_WARDEN or is_skyfall_overlord or vanguard_shields.is_empty():
		return
	var n := clampi(active_slots, 2, 3)
	if words_list.size() < n:
		return
	vanguard_active_count = n
	# Fold single chest shield so multi-shield discrimination is cleanly enforced!
	if is_instance_valid(shield_area):
		shield_area.hide()
		shield_area.collision_layer = 0
	var chosen_correct := randi() % n
	vanguard_correct_slot = chosen_correct
	var col_border := Color("ff9f43") if n >= 3 else Color("5ce0d8")
	var phase_tag := "三盾困阵" if n >= 3 else "双盾择词"
	for idx in vanguard_shields.size():
		var sd: Dictionary = vanguard_shields[idx]
		var area: Area3D = sd.area
		if idx < n:
			sd.active = true
			sd.word = words_list[idx]
			area.position = sd.base_pos
			area.show()
			area.collision_layer = HIT_LAYER
			(sd.frame_mat as StandardMaterial3D).albedo_color = col_border
			(sd.screen_mat as StandardMaterial3D).albedo_color = Color("fff6e4") if n >= 3 else Color("edf6f2")
			(sd.tag_label as Label3D).text = "%s·%s" % [phase_tag, str(sd.part)]
			combat.game._fit_word(sd.word_label, str(sd.word.get("english", "")), 108)
		else:
			sd.active = false
			sd.word = {}
			area.hide()
			area.collision_layer = 0
	assigned_word = vanguard_shields[vanguard_correct_slot].word
	_refresh_hp_bar()

func expected_vanguard_slot() -> int:
	return vanguard_correct_slot if vanguard_multi_active() else -1

func expected_vanguard_word() -> Dictionary:
	if vanguard_multi_active() and vanguard_correct_slot >= 0 and vanguard_correct_slot < vanguard_shields.size():
		return vanguard_shields[vanguard_correct_slot].word
	return assigned_word

func flash_vanguard_wrong(slot_idx: int):
	wrong_flash_left = 0.45
	for sd in vanguard_shields:
		if bool(sd.active):
			(sd.frame_mat as StandardMaterial3D).albedo_color = Color("ff3b30") if int(sd.slot) == slot_idx else Color("ff9f43")

func _step_vanguard_boss_ai(delta: float, player_at: Vector3, distance: float, engaged: bool):
	if archetype != Archetype.BOSS_WARDEN or is_skyfall_overlord or defeated:
		return
	# Gentle floating bob on active Vanguard holographic shields
	if vanguard_multi_active():
		for sd in vanguard_shields:
			if bool(sd.active) and is_instance_valid(sd.area):
				var bp: Vector3 = sd.base_pos
				var bob := sin(hover_clock * 2.8 + float(sd.slot) * 1.9) * 0.05
				(sd.area as Area3D).position = Vector3(bp.x, bp.y + bob, bp.z)
		if wrong_flash_left <= 0.0:
			var ok_col := Color("ff9f43") if vanguard_active_count >= 3 else Color("5ce0d8")
			for sd in vanguard_shields:
				if bool(sd.active):
					(sd.frame_mat as StandardMaterial3D).albedo_color = ok_col
	if not engaged or stun_left > 0.0 or knockdown_left > 0.0 or combat.player_in_smoke():
		return
	# Action Move Set for Normal Mode Boss (Phase 2+: Shield-Charge Slam; Phase 3: Horizontal Energy Wave!)
	if boss_phase >= 3:
		return
	if vanguard_move_state == "idle":
		vanguard_move_cd -= delta
		if vanguard_move_cd <= 0.0 and distance < 26.0:
			if boss_phase == 1 and randf() < 0.52:
				vanguard_move_state = "wave_windup"
				vanguard_move_timer = 0.90
				combat.game.play_sfx("warning_lock", -9)
				combat.game._notice("⚡ 铁面词卫蓄力【震荡冲击波】！横向走位躲开直线波束！", Color("ff9e66"))
			else:
				vanguard_move_state = "charge_windup"
				vanguard_move_timer = 0.95
				var to_p := Vector3(player_at.x - position.x, 0.0, player_at.z - position.z)
				var cdir := to_p.normalized() if to_p.length_squared() > 0.04 else Vector3.FORWARD
				var raw_dst := position + cdir * minf(6.2, maxf(2.4, distance - 2.6))
				var camp_c: Vector3 = combat.zone_center(zone)
				var off_c := Vector2(raw_dst.x - camp_c.x, raw_dst.z - camp_c.z)
				if off_c.length() > 24.0:
					off_c = off_c.normalized() * 24.0
				vanguard_charge_target = combat.game.Layout.on_ground(Vector3(camp_c.x + off_c.x, 0.0, camp_c.z + off_c.y))
				combat.game.play_sfx("boss_phase", -10)
				combat.game._notice("⚡ 铁面词卫蓄力【冲锋震地】！迅速横向闪避冲击点！", Color("ffd15c"))
	elif vanguard_move_state == "charge_windup":
		vanguard_move_timer -= delta
		if is_instance_valid(visor):
			visor.albedo_color = Color("ffd15c")
		visual_root.rotation.x = lerpf(visual_root.rotation.x, -0.18, minf(delta * 8.0, 1.0))
		if vanguard_move_timer <= 0.0:
			vanguard_move_state = "charging"
			vanguard_move_timer = 0.55
			combat.game.play_sfx("boss_slash", -9)
	elif vanguard_move_state == "charging":
		vanguard_move_timer -= delta
		position = position.lerp(vanguard_charge_target, minf(delta * 8.5, 1.0))
		visual_root.rotation.x = -0.26
		if vanguard_move_timer <= 0.0:
			vanguard_move_state = "idle"
			vanguard_move_cd = 6.6 if boss_phase == 1 else 8.2
			visual_root.rotation.x = 0.0
			combat.spawn_danger_ring(position, 4.0, 22)
	elif vanguard_move_state == "wave_windup":
		vanguard_move_timer -= delta
		if is_instance_valid(visor):
			visor.albedo_color = Color("ff7840")
		if vanguard_move_timer <= 0.0:
			vanguard_move_state = "idle"
			vanguard_move_cd = 6.2
			var wdir := Vector3(player_at.x - position.x, 0.0, player_at.z - position.z).normalized()
			if combat.has_method("spawn_sword_wave"):
				combat.spawn_sword_wave(position, wdir, 18)
			combat.game.play_sfx("boss_slash", -8)

func _build_overlord_multi_shields(game):
	multi_shields.clear()
	overlord_shields_root = Node3D.new()
	overlord_shields_root.name = "OverlordMultiShields"
	add_child(overlord_shields_root)
	# Hide legacy single chest shield on giant multi-shield overlord!
	if is_instance_valid(shield_area):
		shield_area.hide()
		shield_area.collision_layer = 0

	var bw := 2.02
	var bh := 0.72
	for idx in OVERLORD_SHIELD_SPECS.size():
		var sp: Dictionary = OVERLORD_SHIELD_SPECS[idx]
		var area := Area3D.new()
		area.name = "OverlordShield_%d" % idx
		area.position = sp.pos
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("hit_zone", "multi_shield")
		area.set_meta("shield_slot", idx)
		overlord_shields_root.add_child(area)

		var bshp := BoxShape3D.new()
		bshp.size = Vector3(bw, bh, 0.24)
		var bcol := CollisionShape3D.new()
		bcol.shape = bshp
		area.add_child(bcol)

		var bezel: MeshInstance3D = game._mesh_box(area, Vector3(0, 0, -0.02), Vector3(bw, bh, 0.06), Color("ffd15c"))
		var fmat: StandardMaterial3D = bezel.material_override
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var screen: MeshInstance3D = game._mesh_box(area, Vector3(0, -0.02, 0.02), Vector3(bw - 0.14, bh - 0.14, 0.05), Color("fff6e0"))
		var smat: StandardMaterial3D = screen.material_override
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var tlbl: Label3D = game._label3d(area, "玄铁·%s" % str(sp.part), Vector3(0, 0.21, 0.06), 17, Color("7a3500"))
		tlbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		tlbl.pixel_size = 0.0044
		tlbl.outline_size = 0
		tlbl.visibility_range_end = 98.0

		var wlbl: Label3D = game._label3d(area, "", Vector3(0, -0.06, 0.064), 56, Color("141a18"))
		wlbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		wlbl.pixel_size = 0.0052
		wlbl.width = 345
		wlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wlbl.outline_size = 2
		wlbl.outline_modulate = Color("fffaf0")
		wlbl.visibility_range_end = 105.0

		multi_shields.append({
			"slot": idx,
			"part": str(sp.part),
			"base_pos": sp.pos,
			"area": area,
			"word_label": wlbl,
			"tag_label": tlbl,
			"frame_mat": fmat,
			"screen_mat": smat,
			"broken": false,
			"word": {},
		})
		# Stay hidden & non-collidable until Overlord actually lands from skyfall!
		area.hide()
		area.collision_layer = 0

func configure_overlord_sequence(five_words: Array):
	if not is_skyfall_overlord or multi_shields.is_empty():
		return
	overlord_round = 1
	overlord_orbit_active = false
	overlord_r2_timer = 0.0
	overlord_seq_words.clear()
	for i in mini(5, five_words.size()):
		overlord_seq_words.append(five_words[i])
	overlord_seq_slots = [0, 1, 2, 3, 4]
	overlord_seq_slots.shuffle()
	overlord_seq_step = 0
	max_hp = 500
	hp = max_hp
	var active_now := (skyfall_state == "landed")
	for step_i in mini(overlord_seq_words.size(), overlord_seq_slots.size()):
		var slot_idx: int = overlord_seq_slots[step_i]
		var sd: Dictionary = multi_shields[slot_idx]
		sd.broken = false
		sd.word = overlord_seq_words[step_i]
		var area: Area3D = sd.area
		area.position = sd.base_pos
		area.rotation = Vector3.ZERO
		area.visible = active_now
		area.collision_layer = HIT_LAYER if active_now else 0
		(sd.frame_mat as StandardMaterial3D).albedo_color = Color("ffd15c")
		(sd.screen_mat as StandardMaterial3D).albedo_color = Color("fff6e0")
		(sd.tag_label as Label3D).text = "一轮·%s" % str(sd.part)
		combat.game._fit_word(sd.word_label, str(sd.word.get("english", "")), 108)
	if not overlord_seq_words.is_empty():
		assigned_word = overlord_seq_words[0]
	_refresh_hp_bar()

func configure_overlord_round_two(three_words: Array):
	if not is_skyfall_overlord or multi_shields.is_empty():
		return
	overlord_round = 2
	overlord_orbit_active = true
	overlord_r2_timer = OVERLORD_R2_DURATION
	overlord_ultimate_state = "none"
	overlord_recovery_left = 0.0
	overlord_seq_words.clear()
	for i in mini(3, three_words.size()):
		overlord_seq_words.append(three_words[i])
	var pool_slots := [0, 1, 2, 3, 4]
	pool_slots.shuffle()
	overlord_seq_slots = pool_slots.slice(0, overlord_seq_words.size())
	overlord_seq_step = 0
	max_hp = 300
	hp = max_hp
	for i in multi_shields.size():
		var sd: Dictionary = multi_shields[i]
		var area: Area3D = sd.area
		if i in overlord_seq_slots:
			var step_i := overlord_seq_slots.find(i)
			sd.broken = false
			sd.word = overlord_seq_words[step_i]
			area.show()
			area.collision_layer = HIT_LAYER
			(sd.frame_mat as StandardMaterial3D).albedo_color = Color("ff9f2e")
			(sd.screen_mat as StandardMaterial3D).albedo_color = Color("fff0c8")
			(sd.tag_label as Label3D).text = "二轮金盾·公转"
			combat.game._fit_word(sd.word_label, str(sd.word.get("english", "")), 108)
		else:
			sd.broken = true
			area.hide()
			area.collision_layer = 0
	if not overlord_seq_words.is_empty():
		assigned_word = overlord_seq_words[0]
	_update_overlord_shield_positions(0.0)
	_refresh_hp_bar()

func _update_overlord_shield_positions(delta: float):
	if not is_skyfall_overlord or not is_instance_valid(overlord_shields_root):
		return
	if overlord_ultimate_state in ["descending", "holding", "lifting", "recovery"]:
		for sd in multi_shields:
			var a_hide: Area3D = sd.area
			if is_instance_valid(a_hide):
				a_hide.hide()
				a_hide.collision_layer = 0
		return
	if not overlord_orbit_active:
		return
	var ang_spd: float = 1.62 if overlord_round >= 2 else 1.12
	overlord_orbit_angle += delta * ang_spd
	var intact_list: Array = []
	for sd in multi_shields:
		if not bool(sd.get("broken", false)):
			intact_list.append(sd)
	var n_intact := intact_list.size()
	if n_intact <= 0:
		return
	var orbit_r: float = 3.55 if overlord_round >= 2 else 3.25
	var ppos: Vector3 = combat.game.player.position if (is_instance_valid(combat) and is_instance_valid(combat.game.player)) else (global_position + Vector3(0, 0, 8))
	for k in n_intact:
		var sd: Dictionary = intact_list[k]
		var area: Area3D = sd.area
		var ang: float = overlord_orbit_angle + TAU * float(k) / float(n_intact)
		var ly: float = 2.45 + sin(ang * 2.0 + float(k)) * 0.34
		var local_p := Vector3(cos(ang) * orbit_r, ly, sin(ang) * orbit_r)
		area.position = area.position.lerp(local_p, minf(delta * 8.0, 1.0)) if delta > 0.0 else local_p
		# Always orient shield face toward player so English word stays crisp & legible while orbiting!
		var to_p := ppos - area.global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.05:
			var world_yaw := atan2(to_p.x, to_p.z)
			area.rotation = Vector3(0.0, world_yaw - global_rotation.y, 0.0)

func expected_overlord_slot() -> int:
	if not is_skyfall_overlord or overlord_seq_step < 0 or overlord_seq_step >= overlord_seq_slots.size():
		return -1
	return int(overlord_seq_slots[overlord_seq_step])

func expected_overlord_word() -> Dictionary:
	if not is_skyfall_overlord or overlord_seq_step < 0 or overlord_seq_step >= overlord_seq_words.size():
		return {}
	return overlord_seq_words[overlord_seq_step]

func remaining_overlord_shields() -> int:
	if not is_skyfall_overlord or multi_shields.is_empty():
		return 0
	var intact := 0
	for sd in multi_shields:
		if not bool(sd.get("broken", false)):
			intact += 1
	return intact

func break_overlord_shield(slot_idx: int) -> Dictionary:
	## Returns {"dead": bool, "entered_round_two": bool, "started_orbit": bool}
	var out := {"dead": false, "entered_round_two": false, "started_orbit": false}
	if not is_skyfall_overlord or defeated or slot_idx < 0 or slot_idx >= multi_shields.size():
		return out
	var sd: Dictionary = multi_shields[slot_idx]
	sd.broken = true
	var area: Area3D = sd.area
	area.hide()
	area.collision_layer = 0
	overlord_seq_step += 1
	var total_round_shields := maxi(1, overlord_seq_words.size())
	var step_hp := 100
	hp = maxi(0, (total_round_shields - overlord_seq_step) * step_hp)
	_spawn_shatter_fx(area.global_position)
	if overlord_round == 1 and overlord_seq_step == 2 and not overlord_orbit_active:
		overlord_orbit_active = true
		out["started_orbit"] = true
		for rem_sd in multi_shields:
			if not bool(rem_sd.broken):
				(rem_sd.tag_label as Label3D).text = "离体公转·词盾"
				(rem_sd.frame_mat as StandardMaterial3D).albedo_color = Color("5ce8ff")
	if overlord_seq_step < overlord_seq_words.size():
		assigned_word = overlord_seq_words[overlord_seq_step]
	_refresh_hp_bar()
	if overlord_seq_step >= overlord_seq_words.size() or hp <= 0:
		if overlord_round == 1:
			# Round 1 complete -> Transition to Round 2 (300 HP, 3 fast-orbiting shields, 10s countdown!)
			out["entered_round_two"] = true
			return out
		else:
			_cleanup_ultimate_nodes()
			neutralize()
			out["dead"] = true
			return out
	return out

func reset_overlord_sequence(new_words: Array):
	if not is_skyfall_overlord or defeated:
		return
	if overlord_round >= 2:
		var keep_timer := maxf(2.5, overlord_r2_timer - 1.5)
		configure_overlord_round_two(new_words)
		overlord_r2_timer = keep_timer
	else:
		configure_overlord_sequence(new_words)
	wrong_flash_left = 0.55
	for sd in multi_shields:
		if not bool(sd.broken):
			(sd.frame_mat as StandardMaterial3D).albedo_color = Color("ff3b30")
	if is_instance_valid(combat) and is_instance_valid(combat.game.player):
		combat.game.player.add_screen_shake(0.62)

func trigger_skyfall():
	if not is_skyfall_overlord or skyfall_state != "idle":
		return
	visible = true
	collision_layer = HIT_LAYER
	if is_instance_valid(head_area):
		head_area.collision_layer = HIT_LAYER
	skyfall_state = "dropping"
	skyfall_y_offset = 32.0
	skyfall_vel = -22.0
	visual_root.position.y = skyfall_y_offset
	if is_instance_valid(overlord_shields_root):
		overlord_shields_root.position.y = skyfall_y_offset
	# Tall crimson-gold thunderbeam pillar telegraphing skyfall descent!
	if is_instance_valid(combat) and is_instance_valid(combat.arena):
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 1.6
		bm.bottom_radius = 2.4
		bm.height = 38.0
		beam.mesh = bm
		beam.position = global_position + Vector3(0.0, 19.0, 0.0)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(1.0, 0.72, 0.22, 0.36)
		bmat.emission_enabled = true
		bmat.emission = Color("ff8c28")
		bmat.emission_energy_multiplier = 2.4
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.material_override = bmat
		combat.arena.add_child(beam)
		skyfall_beam_node = beam
	combat.game.play_sfx("boss_skyfall", -5)

func force_land_skyfall():
	if not is_skyfall_overlord or skyfall_state == "landed":
		return
	if skyfall_state == "idle":
		visible = true
		collision_layer = HIT_LAYER
		if is_instance_valid(head_area):
			head_area.collision_layer = HIT_LAYER
	skyfall_state = "landed"
	skyfall_y_offset = 0.0
	skyfall_vel = 0.0
	visual_root.position.y = 0.0
	if is_instance_valid(overlord_shields_root):
		overlord_shields_root.position.y = 0.0
	if is_instance_valid(skyfall_beam_node):
		skyfall_beam_node.queue_free()
		skyfall_beam_node = null
	# Reveal active Round 1 shields now that Overlord has slammed onto Cloud-Top Arena!
	for sd in multi_shields:
		if not bool(sd.get("broken", false)):
			var a_sh: Area3D = sd.area
			a_sh.show()
			a_sh.collision_layer = HIT_LAYER
	if is_instance_valid(combat):
		if is_instance_valid(combat.game.player):
			combat.game.player.add_screen_shake(1.05)
		combat.spawn_danger_ring(position, 8.5, 0)
		if combat.has_method("on_overlord_skyfall_impact"):
			combat.on_overlord_skyfall_impact(position)

func trigger_ultimate_tiandi():
	## Ultimate「天地万象」: Inverted Mirror Yanshan Mountain descends over Cloud-Top Arena, crushing Shield->0 & HP->10, then grants 4.5s healing recovery!
	if not is_skyfall_overlord or defeated or overlord_ultimate_state != "none":
		return
	overlord_ultimate_count += 1
	overlord_ultimate_state = "descending"
	overlord_ultimate_timer = 1.35
	ov_move_state = "idle"
	laser_beam.hide()
	for sd in multi_shields:
		var a_sh: Area3D = sd.area
		if is_instance_valid(a_sh):
			a_sh.hide()
			a_sh.collision_layer = 0
	if is_instance_valid(combat) and is_instance_valid(combat.arena):
		_cleanup_ultimate_nodes()
		var m_root := Node3D.new()
		m_root.name = "MirrorYanshanUltimate"
		var arena_c: Vector3 = combat.game.Layout.CLOUD_ARENA_CENTER
		var arena_y: float = float(combat.game.Layout.CLOUD_ARENA_Y)
		m_root.position = Vector3(arena_c.x, arena_y + 44.0, arena_c.z)
		combat.arena.add_child(m_root)
		var m_path := "res://assets/slice/v086_mirror_yanshan.glb"
		if ResourceLoader.exists(m_path):
			if not combat.game.scene_cache.has(m_path):
				combat.game.scene_cache[m_path] = load(m_path)
			var minst: Node3D = combat.game.scene_cache[m_path].instantiate()
			m_root.add_child(minst)
		mirror_mountain_node = m_root
		combat.game.play_sfx("boss_ultimate", -4)
		combat.game.screen_flash.color = Color(1.0, 0.56, 0.16, 0.24)
		combat.game._notice("☄ 终极技【天地万象】发动！！倒悬镜像烟山伴金阵压顶合拢！！", Color("ff5252"))

func _cleanup_ultimate_nodes():
	if is_instance_valid(mirror_mountain_node):
		mirror_mountain_node.queue_free()
		mirror_mountain_node = null
	if is_instance_valid(skyfall_beam_node):
		skyfall_beam_node.queue_free()
		skyfall_beam_node = null

func _step_overlord_ai(delta: float, player_at: Vector3, distance: float, engaged: bool):
	# Always spin floating Dharma-Wheel Halo behind Overlord
	if is_instance_valid(ov_halo):
		var h_spd := 9.5 if (overlord_ultimate_state != "none" or ov_move_state == "dharma_barrage") else (4.6 if overlord_round >= 2 else 1.8)
		ov_halo.rotation.z += delta * h_spd
	if is_instance_valid(ov_head):
		ov_head.rotation.y = sin(hover_clock * 1.4) * 0.10

	# 1) Ultimate「天地万象」choreography (descending -> impact crush -> holding -> lifting -> 4.5s healing breather -> rearm R2!)
	if overlord_ultimate_state != "none":
		overlord_ultimate_timer = maxf(0.0, overlord_ultimate_timer - delta)
		var arena_y: float = float(combat.game.Layout.CLOUD_ARENA_Y)
		if is_instance_valid(mirror_mountain_node):
			mirror_mountain_node.rotation.y += delta * 0.72
		if overlord_ultimate_state == "descending":
			if is_instance_valid(ov_arm_l):
				ov_arm_l.rotation.x = lerpf(ov_arm_l.rotation.x, -2.35, minf(delta * 6.0, 1.0))
			if is_instance_valid(ov_arm_r):
				ov_arm_r.rotation.x = lerpf(ov_arm_r.rotation.x, -2.35, minf(delta * 6.0, 1.0))
			if is_instance_valid(mirror_mountain_node):
				var frac := 1.0 - clampf(overlord_ultimate_timer / 1.35, 0.0, 1.0)
				mirror_mountain_node.position.y = lerpf(arena_y + 44.0, arena_y + 5.2, frac * frac)
			if overlord_ultimate_timer <= 0.0:
				overlord_ultimate_state = "holding"
				overlord_ultimate_timer = 0.65
				if is_instance_valid(combat) and combat.has_method("apply_ultimate_crush_to_10hp"):
					combat.apply_ultimate_crush_to_10hp()
		elif overlord_ultimate_state == "holding":
			if is_instance_valid(ov_arm_l):
				ov_arm_l.rotation.x = lerpf(ov_arm_l.rotation.x, 0.55, minf(delta * 10.0, 1.0))
			if is_instance_valid(ov_arm_r):
				ov_arm_r.rotation.x = lerpf(ov_arm_r.rotation.x, 0.55, minf(delta * 10.0, 1.0))
			if overlord_ultimate_timer <= 0.0:
				overlord_ultimate_state = "lifting"
				overlord_ultimate_timer = 0.90
		elif overlord_ultimate_state == "lifting":
			if is_instance_valid(mirror_mountain_node):
				var lift_frac := 1.0 - clampf(overlord_ultimate_timer / 0.90, 0.0, 1.0)
				mirror_mountain_node.position.y = lerpf(arena_y + 5.2, arena_y + 52.0, lift_frac)
			if overlord_ultimate_timer <= 0.0:
				_cleanup_ultimate_nodes()
				overlord_ultimate_state = "recovery"
				overlord_recovery_left = OVERLORD_RECOVERY_DURATION
				overlord_ultimate_timer = OVERLORD_RECOVERY_DURATION
				combat.game._notice("💊 倒悬镜像烟山散去！趁 %.1f 秒喘息窗速按 [H]医疗包 / [T]能量饮 回复状态！" % OVERLORD_RECOVERY_DURATION, Color("7ef5be"))
				combat.show_question()
		elif overlord_ultimate_state == "recovery":
			overlord_recovery_left = overlord_ultimate_timer
			# Overlord kneels tiredly during the 4.5s breather
			visual_root.position.y = lerpf(visual_root.position.y, -0.32, minf(delta * 5.0, 1.0))
			if is_instance_valid(ov_arm_l):
				ov_arm_l.rotation.x = lerpf(ov_arm_l.rotation.x, 0.35, minf(delta * 5.0, 1.0))
			if is_instance_valid(ov_arm_r):
				ov_arm_r.rotation.x = lerpf(ov_arm_r.rotation.x, 0.35, minf(delta * 5.0, 1.0))
			if overlord_ultimate_timer <= 0.0:
				visual_root.position.y = 0.0
				overlord_ultimate_state = "none"
				overlord_recovery_left = 0.0
				if is_instance_valid(combat) and combat.has_method("rearm_overlord_round_two"):
					combat.rearm_overlord_round_two()
		return

	# 2) Round 2 10-second countdown!
	if engaged and overlord_round == 2 and skyfall_state == "landed":
		var prev_sec := int(ceilf(overlord_r2_timer))
		overlord_r2_timer = maxf(0.0, overlord_r2_timer - delta)
		if int(ceilf(overlord_r2_timer)) != prev_sec and is_instance_valid(combat):
			combat.show_question()
		if overlord_r2_timer <= 0.0:
			trigger_ultimate_tiandi()
			return

	# 3) Articulated Action Move Set (Flash-Step Dash, Whirlwind Twin-Blade Cleave, Earth-Splitting Sword Wave, Dharma-Wheel Barrage)
	if not engaged or skyfall_state != "landed" or stun_left > 0.0:
		return
	if ov_move_state == "idle":
		# Relaxed combat ready blade swing
		if is_instance_valid(ov_arm_l):
			ov_arm_l.rotation.x = lerpf(ov_arm_l.rotation.x, sin(hover_clock * 2.2) * 0.16, minf(delta * 6.0, 1.0))
			ov_arm_l.rotation.z = lerpf(ov_arm_l.rotation.z, 0.0, minf(delta * 6.0, 1.0))
		if is_instance_valid(ov_arm_r):
			ov_arm_r.rotation.x = lerpf(ov_arm_r.rotation.x, -sin(hover_clock * 2.2) * 0.16, minf(delta * 6.0, 1.0))
			ov_arm_r.rotation.z = lerpf(ov_arm_r.rotation.z, 0.0, minf(delta * 6.0, 1.0))
		visual_root.rotation.y = lerpf(visual_root.rotation.y, 0.0, minf(delta * 8.0, 1.0))
		ov_move_cd -= delta
		if ov_move_cd <= 0.0 and not combat.player_in_smoke():
			var mv_idx := ov_move_cycle % 4
			ov_move_cycle += 1
			ov_slash_fired = false
			if mv_idx == 0 and distance > 9.5:
				ov_move_state = "flash_dash"
				ov_move_timer = 0.85
				var dir_to := Vector3(player_at.x - position.x, 0.0, player_at.z - position.z).normalized()
				var raw_dst := player_at - dir_to * 6.5
				var arena_c: Vector3 = combat.game.Layout.CLOUD_ARENA_CENTER
				var off_a := Vector2(raw_dst.x - arena_c.x, raw_dst.z - arena_c.z)
				if off_a.length() > 15.5:
					off_a = off_a.normalized() * 15.5
				ov_dash_target = combat.game.Layout.on_ground(Vector3(arena_c.x + off_a.x, 0.0, arena_c.z + off_a.y))
				combat.game.play_sfx("boss_slash", -8)
				combat.game._notice("⚡ 玄铁词尊施展【瞬步逼近】！注意走位拉扯！", Color("ffd15c"))
			elif mv_idx == 1 or (mv_idx == 0 and distance <= 9.5):
				ov_move_state = "whirlwind"
				ov_move_timer = 1.45
				combat.spawn_danger_ring(position, 6.2, 26)
				combat.game.play_sfx("boss_slash", -7)
				combat.game._notice("🌀 玄铁词尊蓄力【旋风双刃斩】！快撤出脚下红圈！", Color("ff8080"))
			elif mv_idx == 2:
				ov_move_state = "sword_wave"
				ov_move_timer = 1.15
				combat.game.play_sfx("warning_lock", -9)
				combat.game._notice("⚔ 玄铁词尊高举双刃准备【裂地剑气】！横向闪避直线轨迹！", Color("ff9e66"))
			else:
				ov_move_state = "dharma_barrage"
				ov_move_timer = 1.20
				combat.spawn_danger_ring(player_at, 3.2, 22)
				combat.spawn_danger_ring(player_at + Vector3(3.6, 0.0, -2.4), 3.1, 22)
				combat.game._notice("🔥 玄铁词尊驱动【浮游法轮弹幕】！迅速闪避红圈！", Color("ff8a6b"))
	else:
		ov_move_timer -= delta
		if ov_move_state == "flash_dash":
			if is_instance_valid(ov_arm_l):
				ov_arm_l.rotation.x = -0.85
			if is_instance_valid(ov_arm_r):
				ov_arm_r.rotation.x = 0.75
			position = position.lerp(ov_dash_target, minf(delta * 7.5, 1.0))
		elif ov_move_state == "whirlwind":
			visual_root.rotation.y += delta * 12.5
			if is_instance_valid(ov_arm_l):
				ov_arm_l.rotation.z = lerpf(ov_arm_l.rotation.z, -1.25, minf(delta * 10.0, 1.0))
			if is_instance_valid(ov_arm_r):
				ov_arm_r.rotation.z = lerpf(ov_arm_r.rotation.z, 1.25, minf(delta * 10.0, 1.0))
		elif ov_move_state == "sword_wave":
			if ov_move_timer > 0.55:
				if is_instance_valid(ov_arm_l):
					ov_arm_l.rotation.x = lerpf(ov_arm_l.rotation.x, -2.25, minf(delta * 8.0, 1.0))
				if is_instance_valid(ov_arm_r):
					ov_arm_r.rotation.x = lerpf(ov_arm_r.rotation.x, -2.25, minf(delta * 8.0, 1.0))
			else:
				if not ov_slash_fired:
					ov_slash_fired = true
					var s_dir := Vector3(player_at.x - position.x, 0.0, player_at.z - position.z).normalized()
					if combat.has_method("spawn_sword_wave"):
						combat.spawn_sword_wave(position, s_dir, 24)
					combat.game.play_sfx("boss_slash", -6)
				if is_instance_valid(ov_arm_l):
					ov_arm_l.rotation.x = lerpf(ov_arm_l.rotation.x, 0.95, minf(delta * 14.0, 1.0))
				if is_instance_valid(ov_arm_r):
					ov_arm_r.rotation.x = lerpf(ov_arm_r.rotation.x, 0.95, minf(delta * 14.0, 1.0))
		elif ov_move_state == "dharma_barrage":
			if is_instance_valid(ov_arm_l):
				ov_arm_l.rotation.z = lerpf(ov_arm_l.rotation.z, -0.95, minf(delta * 7.0, 1.0))
			if is_instance_valid(ov_arm_r):
				ov_arm_r.rotation.z = lerpf(ov_arm_r.rotation.z, 0.95, minf(delta * 7.0, 1.0))
		if ov_move_timer <= 0.0:
			ov_move_state = "idle"
			ov_move_cd = 2.6 if overlord_round >= 2 else 3.5
			visual_root.rotation.y = 0.0

func show_word(word: String, _new_question: bool):
	# NEVER revive a defeated soldier mid-wave! Dead units stay eliminated until the whole wave is cleared.
	if defeated:
		return
	if is_skyfall_overlord or vanguard_multi_active():
		if is_instance_valid(shield_area):
			shield_area.hide()
			shield_area.collision_layer = 0
		_refresh_hp_bar()
		return
	var has_word := word != ""
	if has_word and (archetype != Archetype.BOSS_WARDEN or exposed_left <= 0):
		shield_area.show()
		shield_area.collision_layer = HIT_LAYER
		shield_intact = true
		combat.game._fit_word(word_label, word, 110)
		if shield_layers >= max_shield_layers and wrong_flash_left <= 0:
			shield_material.albedo_color = Color("fff8e3") if is_nemesis_bounty else Color("edf2e6")
			frame_material.albedo_color = _active_border_col()
			tag_label.text = _active_tag_text()
			tag_label.modulate = _active_tag_col()
	else:
		shield_area.hide()
		shield_area.collision_layer = 0
	_refresh_hp_bar()

func neutralize():
	if defeated:
		return
	_cleanup_ultimate_nodes()
	defeated = true
	shield_layers = 0
	collision_layer = 0
	shield_area.collision_layer = 0
	if is_instance_valid(head_area):
		head_area.collision_layer = 0
	if is_instance_valid(core_area):
		core_area.collision_layer = 0
	for sd in multi_shields:
		var m_area: Area3D = sd.area
		if is_instance_valid(m_area):
			m_area.collision_layer = 0
			m_area.hide()
	for vd in vanguard_shields:
		var v_area: Area3D = vd.area
		if is_instance_valid(v_area):
			v_area.collision_layer = 0
			v_area.hide()
	vanguard_active_count = 0
	boss_core_pulse_shots = 0
	velocity = Vector3.ZERO
	action = Action.PATROL
	laser_beam.hide()
	shield_area.hide()
	hp_bar_root.hide()
	_spawn_shatter_fx()
	if defeat_tween and defeat_tween.is_valid():
		defeat_tween.kill()
	defeat_tween = create_tween()
	defeat_tween.set_parallel(true)
	defeat_tween.tween_property(visual_root, "rotation:x", -0.95, 0.26)
	defeat_tween.tween_property(visual_root, "position:y", -0.45, 0.26)
	defeat_tween.tween_property(visual_root, "scale", Vector3(0.82, 0.82, 0.82), 0.26)
	defeat_tween.chain().tween_callback(func():
		if defeated:
			hide()
	)

func _spawn_shatter_fx(custom_origin: Vector3 = Vector3.INF):
	if not is_instance_valid(combat) or not is_instance_valid(combat.arena):
		return
	var game = combat.game
	var origin = custom_origin if custom_origin.is_finite() else shield_area.global_position
	var fx_col := Color("ffd15c") if archetype == Archetype.BOSS_WARDEN else Color("7af5cc")
	var count := 10 if archetype == Archetype.BOSS_WARDEN else 5
	for i in count:
		var shard = game._mesh_box(combat.arena, origin, Vector3(0.24, 0.16, 0.05), fx_col)
		shard.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var angle = TAU * float(i) / float(count) + 0.3
		var target_pos = origin + Vector3(cos(angle) * 1.45, 0.55 + sin(angle) * 0.65, sin(angle) * 0.85)
		var tw = shard.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "global_position", target_pos, 0.35)
		tw.tween_property(shard, "rotation", Vector3(angle * 2.0, angle, angle * 1.5), 0.35)
		tw.tween_property(shard, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
		tw.chain().tween_callback(shard.queue_free)

func begin_tactical_engagement(force_reposition: bool = false):
	if defeated or not is_instance_valid(combat):
		return
	laser_beam.hide()
	var slot: Dictionary = combat.claim_tactical_cover(self, force_reposition)
	cover = slot["anchor"]
	cover_goal = slot["shelter_pos"]
	peek_goal = slot["peek_pos"]
	var use_peek: bool = bool(combat.is_designated_attacker(self)) or (option == int(combat.game.answer_index))
	bound_goal = peek_goal if use_peek else cover_goal.lerp(peek_goal, 0.78)
	is_bounding_to_cover = Vector2(position.x - bound_goal.x, position.z - bound_goal.z).length() > 1.15
	action = Action.ADVANCE
	cover_reposition_cd = (4.8 if combat.is_single_attacker_mode() else 3.4) + float(option % 3) * 0.95
	suppress_cd = 0.24 + float(option % 4) * 0.18

func _refresh_cover_poses(player_at: Vector3):
	var to_p := Vector3(player_at.x - cover.x, 0.0, player_at.z - cover.z)
	if to_p.length_squared() < 0.04:
		to_p = Vector3.BACK
	var dir_p := to_p.normalized()
	var right_v := dir_p.cross(Vector3.UP).normalized()
	cover_goal = combat.game.Layout.on_ground(cover - dir_p * 1.42)
	peek_goal = combat.game.Layout.on_ground(cover + right_v * side * 1.16 - dir_p * 0.78)

func take_cover():
	laser_beam.hide()
	is_bounding_to_cover = false
	visual_root.rotation.x = 0.0
	var player_at: Vector3 = combat.game.player.position
	if is_instance_valid(combat) and combat.has_method("claim_tactical_cover"):
		var slot: Dictionary = combat.claim_tactical_cover(self, false)
		cover = slot["anchor"]
		cover_goal = slot["shelter_pos"]
		peek_goal = slot["peek_pos"]
	else:
		_refresh_cover_poses(player_at)
	action = Action.COVER
	cover_left = 1.15 if combat.is_single_attacker_mode() else (0.78 if archetype == Archetype.SCOUT_DRONE else 0.95)

func _update_laser(player_eye: Vector3):
	if action != Action.AIM or defeated or stun_left > 0:
		laser_beam.hide()
		return
	var from = global_position + Vector3(0, 2.24 if archetype == Archetype.BOSS_WARDEN else (1.80 if archetype != Archetype.ASSAULT_BOT else 1.70), 0)
	var dist = from.distance_to(player_eye)
	if dist < 0.5:
		laser_beam.hide()
		return
	laser_beam.show()
	laser_beam.global_position = (from + player_eye) * 0.5
	laser_beam.scale = Vector3(1, 1, dist)
	var up_axis = Vector3.RIGHT if absf((player_eye - from).normalized().y) > 0.98 else Vector3.UP
	laser_beam.look_at(player_eye, up_axis)

func apply_knockdown(duration: float = 1.5, impulse: Vector3 = Vector3.ZERO):
	if defeated:
		return
	var was_aiming: bool = (action == Action.AIM)
	knockdown_left = maxf(knockdown_left, duration)
	knockdown_vel = Vector3(impulse.x, 0.0, impulse.z)
	aim_left = 0.0
	laser_beam.hide()
	if was_aiming and is_instance_valid(combat) and combat.has_method("on_soldier_attack_finished"):
		combat.on_soldier_attack_finished(self)
	action = Action.ADVANCE
	if is_instance_valid(tag_label):
		tag_label.text = "💫 震倒在地 %.1fs" % knockdown_left
		tag_label.modulate = Color("ffd86b")

func _physics_process(delta: float):
	var game = combat.game
	if defeated or game.paused or not combat.in_field():
		laser_beam.hide()
		return
	if is_instance_valid(game.exploration) and game.exploration.safe():
		velocity = Vector3.ZERO
		laser_beam.hide()
		return

	if wrong_flash_left > 0.0:
		wrong_flash_left = maxf(0.0, wrong_flash_left - delta)
		if wrong_flash_left <= 0.0 and not defeated:
			if is_instance_valid(shield_material):
				var idle_bg := Color("fff8e3") if is_nemesis_bounty else Color("edf2e6")
				shield_material.albedo_color = idle_bg if shield_layers >= max_shield_layers else Color("fff0b3")
			if is_instance_valid(frame_material):
				frame_material.albedo_color = _active_border_col() if shield_layers >= max_shield_layers else Color("ff8c3b")

	var player_at: Vector3 = game.player.position
	var toward_player := player_at - position
	toward_player.y = 0
	var distance := toward_player.length()
	var engaged: bool = (combat.zone == zone and combat.is_zone_engaged(zone))
	var rage_hunting: bool = engaged and combat.is_rage_hunting(zone)

	# Hidden Skyfall Overlord stays completely dormant in the clouds until triggered at <=22m!
	if is_skyfall_overlord and skyfall_state == "idle":
		laser_beam.hide()
		velocity = Vector3.ZERO
		return

	# Performance optimization: Distant un-aggroed camp garrisons sleep peacefully at their posts,
	# while facing the player within 98m so distant snipers can cleanly read their English word shields (#3)!
	if not engaged and distance > 36.0:
		laser_beam.hide()
		velocity = Vector3.ZERO
		if distance <= 98.0 and distance > 0.05:
			rotation.y = atan2(toward_player.x, toward_player.z)
		return

	hover_clock += delta
	if is_skyfall_overlord and skyfall_state == "dropping":
		skyfall_vel -= 96.0 * delta
		skyfall_y_offset += skyfall_vel * delta
		if skyfall_y_offset <= 0.0:
			force_land_skyfall()
		else:
			visual_root.position.y = skyfall_y_offset
			if is_instance_valid(overlord_shields_root):
				overlord_shields_root.position.y = skyfall_y_offset
		return
	if is_skyfall_overlord and wrong_flash_left > 0.0:
		wrong_flash_left = maxf(0.0, wrong_flash_left - delta)
		if wrong_flash_left <= 0.0:
			var col_ok := Color("ff9f2e") if overlord_round >= 2 else (Color("5ce8ff") if overlord_orbit_active else Color("ffd15c"))
			for sd in multi_shields:
				if not bool(sd.broken):
					(sd.frame_mat as StandardMaterial3D).albedo_color = col_ok
	if is_skyfall_overlord:
		_update_overlord_shield_positions(delta)
		_step_overlord_ai(delta, player_at, distance, engaged)
		if overlord_ultimate_state != "none":
			velocity = Vector3.ZERO
			if distance > 0.05:
				rotation.y = atan2(toward_player.x, toward_player.z)
			return
	elif archetype == Archetype.BOSS_WARDEN:
		_step_vanguard_boss_ai(delta, player_at, distance, engaged)
		if vanguard_move_state in ["charge_windup", "charging", "wave_windup"]:
			velocity = Vector3.ZERO
			if distance > 0.05:
				rotation.y = atan2(toward_player.x, toward_player.z)
			return
	if archetype == Archetype.SCOUT_DRONE:
		visual_root.position.y = sin(hover_clock * 4.4) * 0.10

	if exposed_left > 0:
		exposed_left = maxf(0, exposed_left - delta)
		if exposed_left <= 0:
			boss_core_pulse_shots = 0
			shield_intact = true
			if is_instance_valid(core_material):
				core_material.albedo_color = Color("ff9d3b")
			if engaged and not vanguard_multi_active() and not assigned_word.is_empty():
				show_word(str(assigned_word.get("english", "")), false)
			_refresh_hp_bar()

	if knockdown_left > 0.0:
		knockdown_left = maxf(0.0, knockdown_left - delta)
		laser_beam.hide()
		knockdown_vel = knockdown_vel.move_toward(Vector3.ZERO, 9.0 * delta)
		velocity = Vector3(knockdown_vel.x, velocity.y - 20.0 * delta if not is_on_floor() else 0.0, knockdown_vel.z)
		visual_root.rotation.x = lerpf(visual_root.rotation.x, -1.16, minf(delta * 18.0, 1.0))
		visual_root.rotation.z = lerpf(visual_root.rotation.z, 0.14 * side, minf(delta * 14.0, 1.0))
		visual_root.position.y = lerpf(visual_root.position.y, -0.52, minf(delta * 18.0, 1.0))
		if is_instance_valid(tag_label):
			tag_label.text = "💫 震倒 %.1fs" % knockdown_left
			tag_label.modulate = Color("ffd86b")
		move_and_slide()
		if knockdown_left <= 0.0:
			visual_root.rotation.x = 0.0
			visual_root.rotation.z = 0.0
			visual_root.position.y = 0.0
			_refresh_hp_bar()
		return

	if stun_left > 0:
		stun_left = maxf(0, stun_left - delta)
		laser_beam.hide()
		velocity = Vector3(0, velocity.y - 20.0 * delta if not is_on_floor() else 0.0, 0)
		visor.albedo_color = Color("56e8ff")
		visual_root.rotation.z = sin(hover_clock * 28.0) * 0.045
		move_and_slide()
		if stun_left <= 0:
			visual_root.rotation.z = 0.0
			_refresh_hp_bar()
		return
	else:
		visual_root.rotation.z = 0.0

	cooldown = maxf(0, cooldown - delta * (1.35 if rage_hunting else 1.0))
	cover_reposition_cd = maxf(0.0, cover_reposition_cd - delta)
	suppress_cd = maxf(0.0, suppress_cd - delta)
	peek_phase += delta
	var goal := position
	var speed := move_speed() * (1.32 if rage_hunting else 1.0)

	if archetype == Archetype.BOSS_WARDEN and engaged and is_skyfall_overlord:
		# Action moves handled cleanly inside _step_overlord_ai(); suppress legacy passive ring timer
		pass

	if not engaged:
		# Standby Garrison at Camp Origin: patrol quietly around camp, DO NOT chase player until aggroed!
		action = Action.PATROL
		is_bounding_to_cover = false
		visual_root.rotation.x = 0.0
		speed *= 0.58
		if position.distance_to(patrol[patrol_index]) < 0.55:
			patrol_index = (patrol_index + 1) % patrol.size()
		goal = patrol[patrol_index]
	elif action == Action.COVER:
		visual_root.rotation.x = 0.0
		goal = cover_goal
		speed *= 1.18
		cover_left -= delta if position.distance_to(cover_goal) < 0.65 else delta * 0.25
		if cover_left <= 0:
			action = Action.ADVANCE
	elif action == Action.AIM:
		visual_root.rotation.x = 0.0
		if combat.player_in_smoke():
			action = Action.ADVANCE
			laser_beam.hide()
		else:
			aim_left -= delta
			_update_laser(combat.player_aim_point())
			if aim_left <= 0:
				laser_beam.hide()
				take_cover()
				cooldown = fire_interval() * (0.82 if combat.wave_wrong_stacks > 0 else 1.0)
				combat.strike(self, false)
				combat.on_soldier_attack_finished(self)
	else:
		action = Action.ADVANCE
		laser_beam.hide()
		_refresh_cover_poses(player_at)

		# Guarantee the soldier carrying the prompted answer word never stays hidden behind an obstacle >1.2s
		if option == game.answer_index:
			if not combat.clear_shot(position):
				occluded_prompt_time += delta
			else:
				occluded_prompt_time = 0.0
			if occluded_prompt_time > 1.20:
				occluded_prompt_time = 0.0
				if combat.clear_shot(peek_goal):
					bound_goal = peek_goal
					is_bounding_to_cover = true
				else:
					begin_tactical_engagement(true)

		var d_cover_player: float = Vector2(player_at.x - cover.x, player_at.z - cover.z).length()
		var too_close_thresh: float = 6.2 if combat.is_single_attacker_mode() else 4.4
		if not is_bounding_to_cover and cover_reposition_cd <= 0.0:
			if (archetype != Archetype.BOSS_WARDEN and distance < too_close_thresh) or d_cover_player > attack_range() - 1.2 or (not combat.is_single_attacker_mode() and archetype != Archetype.BOSS_WARDEN):
				begin_tactical_engagement(true)

		var can_engage_now: bool = rage_hunting or combat.is_designated_attacker(self)
		var heavy_ready_aim: bool = (archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN]) and shield_layers >= max_shield_layers and distance >= 5.5
		if can_engage_now and (not is_bounding_to_cover or heavy_ready_aim or rage_hunting) and distance < attack_range() and cooldown <= 0 and combat.clear_shot(position) and combat.reserve_attack(self):
			is_bounding_to_cover = false
			visual_root.rotation.x = 0.0
			action = Action.AIM
			aim_left = aim_windup() * (0.78 if rage_hunting else 1.0)
			if archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN]:
				game.play_sfx("warning_lock", -13)
		elif rage_hunting:
			# v0.8.1 #8: 3-Wrong Rage Hunt — entire camp charges relentlessly toward the player (even distant snipers!)
			is_bounding_to_cover = false
			visual_root.rotation.x = -0.10
			var r_dir := (-toward_player.normalized()) if distance > 0.05 else Vector3.FORWARD
			var r_ang := (float(option) - 1.5) * 0.36
			goal = player_at + r_dir.rotated(Vector3.UP, r_ang) * 7.2
			if distance < attack_range() + 14.0 and suppress_cd <= 0.0 and combat.try_moving_suppression(self):
				suppress_cd = 0.85
		elif is_bounding_to_cover:
			# Bounding to Cover + Firing Suppression Shots on the Move!
			goal = bound_goal
			speed *= 1.12
			visual_root.rotation.x = -0.08
			var rem_d := Vector2(position.x - bound_goal.x, position.z - bound_goal.z).length()
			if rem_d > 0.92:
				if suppress_cd <= 0.0 and combat.try_moving_suppression(self):
					suppress_cd = 1.45 if combat.is_single_attacker_mode() else 0.95
			else:
				is_bounding_to_cover = false
				visual_root.rotation.x = 0.0
		else:
			visual_root.rotation.x = 0.0
			if can_engage_now:
				if combat.clear_shot(peek_goal) and d_cover_player < attack_range() - 0.8:
					goal = peek_goal
				else:
					# Cautious small-range flank/pursuit when terrain or range blocks the camp parapet
					var camp_c: Vector3 = combat.zone_center(zone)
					var base_dir := (-toward_player.normalized()) if distance > 0.05 else Vector3.FORWARD
					var stand_off := 8.8 if combat.is_single_attacker_mode() else 5.8
					var desired := player_at + base_dir.rotated(Vector3.UP, side * 0.42) * stand_off
					if combat.is_single_attacker_mode():
						var off_camp := Vector2(desired.x - camp_c.x, desired.z - camp_c.z)
						if off_camp.length() > 31.0:
							off_camp = off_camp.normalized() * 31.0
							desired = Vector3(camp_c.x + off_camp.x, desired.y, camp_c.z + off_camp.y)
					goal = desired
					if Vector2(goal.x - position.x, goal.z - position.z).length() > 1.4 and suppress_cd <= 0.0 and combat.try_moving_suppression(self):
						suppress_cd = 1.55 if combat.is_single_attacker_mode() else 1.05
			else:
				# Cautious Cover-Holding Teammates (Normal Mode): stay behind camp parapets & peek shields over low wings!
				if d_cover_player <= 19.5:
					var peek_w: float = 1.0 if (option == int(combat.game.answer_index) or sin(peek_phase * 1.55) > -0.35) else 0.48
					goal = cover_goal.lerp(peek_goal, peek_w)
					speed *= 0.72
				else:
					# Small-range out-of-camp cautious follow (10.5m..13.5m stand-off, capped within 30m of camp)
					var camp_c2: Vector3 = combat.zone_center(zone)
					var escort_ang: float = (float(option) - 1.5) * 0.42
					var base_dir2 := (-toward_player.normalized()) if distance > 0.05 else Vector3.FORWARD
					var desired2 := player_at + base_dir2.rotated(Vector3.UP, escort_ang) * (10.5 + float(option % 2) * 1.8)
					var off_c2 := Vector2(desired2.x - camp_c2.x, desired2.z - camp_c2.z)
					if off_c2.length() > 30.0:
						off_c2 = off_c2.normalized() * 30.0
						desired2 = Vector3(camp_c2.x + off_c2.x, desired2.y, camp_c2.z + off_c2.y)
					goal = desired2
					speed *= 0.85

	if not combat.in_field():
		return
	if action == Action.AIM:
		visor.albedo_color = Color("ffb347")
	elif rage_hunting:
		visor.albedo_color = Color("ff1e2e")
	else:
		visor.albedo_color = Color("ff4f4f") if archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN] else Color("7ef0c8")

	if (engaged or distance <= 98.0) and distance > 0.05:
		rotation.y = atan2(toward_player.x, toward_player.z)
	elif not engaged:
		var pd := goal - position
		pd.y = 0.0
		if pd.length() > 0.08:
			rotation.y = atan2(pd.x, pd.z)

	if (action == Action.ADVANCE or action == Action.COVER) and Vector2(position.x - cover.x, position.z - cover.z).length() < 5.0:
		goal = _around_barrier(goal)
	_walk(goal, speed, delta)

func _around_barrier(goal: Vector3) -> Vector3:
	var toward_goal := signf(goal.z - cover.z)
	if absf(goal.z - cover.z) < 0.95 or (position.z - cover.z) * toward_goal >= 0.95 or absf(position.x - cover.x) > 2.0:
		return goal
	var lateral := position.x - cover.x
	var edge := signf(lateral) if absf(lateral) > 0.25 else side
	var edge_x := cover.x + edge * 1.55
	if lateral * edge < 1.28:
		return Vector3(edge_x, position.y, position.z)
	return Vector3(edge_x, position.y, cover.z + toward_goal * 1.32)

func _walk(goal: Vector3, speed: float, delta: float):
	var direction := goal - position
	direction.y = 0
	if direction.length() < 0.24:
		direction = Vector3.ZERO
	else:
		direction = direction.normalized()
		var origin := position + Vector3.UP * 0.65
		for angle in [0.0, side * 0.8, -side * 0.8, side * 1.45, -side * 1.45]:
			var candidate := direction.rotated(Vector3.UP, angle)
			if not combat.blocked(origin, origin + candidate * 0.9):
				direction = candidate
				break
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y = -0.6 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if legs.size() >= 2:
		var gait := Vector2(get_real_velocity().x, get_real_velocity().z).length()
		stride += delta * gait * 4.6
		var swing := sin(stride) * minf(gait * 0.16, 0.42)
		legs[0].rotation.x = swing
		legs[1].rotation.x = -swing
