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
var hp: int = 90
var max_shield_layers: int = 2
var shield_layers: int = 2
var stun_left: float = 0.0
var exposed_left: float = 0.0
var wrong_flash_left: float = 0.0
var boss_phase: int = 3
var boss_ring_cd: float = 4.2
var shield_intact: bool = true

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
		return 20
	if archetype == Archetype.SNIPER_GUARD:
		return 16
	if archetype == Archetype.SCOUT_DRONE:
		return 8
	return 10

func fire_interval() -> float:
	if archetype == Archetype.BOSS_WARDEN:
		return 2.45
	if archetype == Archetype.SCOUT_DRONE:
		return 2.55
	if archetype == Archetype.SNIPER_GUARD:
		return 3.80
	return 3.05

func aim_windup() -> float:
	if archetype == Archetype.BOSS_WARDEN:
		return 0.80
	if archetype == Archetype.SNIPER_GUARD:
		return 1.08
	if archetype == Archetype.SCOUT_DRONE:
		return 0.72
	return 0.82

func _base_max_hp() -> int:
	if archetype == Archetype.BOSS_WARDEN:
		return 450
	if archetype == Archetype.SCOUT_DRONE:
		return 70
	if archetype == Archetype.SNIPER_GUARD:
		return 90
	return 90

func setup(controller, zone_index: int, index: int, barrier: Vector3, bot_type: int = Archetype.ASSAULT_BOT):
	combat = controller
	zone = zone_index
	option = index
	archetype = bot_type
	max_hp = _base_max_hp()
	hp = max_hp
	max_shield_layers = 2
	shield_layers = max_shield_layers
	boss_phase = 3
	stun_left = 0.0
	exposed_left = 0.0
	wrong_flash_left = 0.0
	shield_intact = true
	defeated = false
	action = Action.PATROL
	cover = barrier
	side = -1.0 if index % 2 == 0 else 1.0
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
	collision_layer = HIT_LAYER
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
	var head_y := 2.30 if archetype == Archetype.BOSS_WARDEN else (1.88 if archetype == Archetype.SNIPER_GUARD else (1.88 if archetype == Archetype.SCOUT_DRONE else 1.78))
	head_area.position = Vector3(0, head_y, 0.14)
	add_child(head_area)
	var hshape = SphereShape3D.new()
	hshape.radius = 0.40 if archetype == Archetype.BOSS_WARDEN else 0.34
	var hcol = CollisionShape3D.new()
	hcol.shape = hshape
	head_area.add_child(hcol)

	# 2. Overhead Compact 3D Health / Shield-Layer Bar
	hp_bar_root = Node3D.new()
	hp_bar_root.position = Vector3(0, 2.82 if archetype == Archetype.BOSS_WARDEN else 2.26, 0)
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
	bg.visibility_range_end = 42.0
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
	hp_fill.visibility_range_end = 42.0
	hp_bar_root.add_child(hp_fill)

	# 3. Chest-Mounted Holographic Electronic Word Shield (2 Shots to Break & Kill on Correct Soldier)
	shield_area = Area3D.new()
	shield_area.set_meta("hit_zone", "shield")
	var shield_y := 1.56 if archetype == Archetype.BOSS_WARDEN else (1.22 if archetype == Archetype.SNIPER_GUARD else (1.20 if archetype == Archetype.SCOUT_DRONE else 1.16))
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

	var role_text = ["突击护盾兵", "迅捷侦察机", "重装狙击卫", "★ 烟山统领"][archetype]
	base_tag_text = "%s · %s" % [char(65 + (option % 8)), role_text]
	tag_label = game._label3d(shield_area, base_tag_text, Vector3(0, 0.22 if archetype == Archetype.BOSS_WARDEN else 0.20, 0.055), 18, Color("143832"))
	tag_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag_label.pixel_size = 0.0044
	tag_label.outline_size = 0
	tag_label.visibility_range_end = 45.0

	word_label = game._label3d(shield_area, "", Vector3(0, -0.05, 0.058), 58, Color("102620"))
	word_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	word_label.pixel_size = 0.0050
	word_label.width = 345
	word_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	word_label.outline_size = 0
	word_label.visibility_range_end = 48.0

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
	var obsidian_mat = _ceramic_plate_mat(Color("222c30"), false)
	var gold_mat = _bronze_trim_mat(Color("d6a648"))
	var armor_mat = _ceramic_plate_mat(Color("2f4b44"), true)

	_oct_drum(visual_root, Vector3(0, 1.48, 0), 0.60, 0.48, 1.02, obsidian_mat, 8)
	_oct_drum(visual_root, Vector3(0, 0.94, 0), 0.42, 0.36, 0.38, armor_mat, 8)

	# Exposed glowing reactor chest core (crit weakpoint when shield/phase shattered)
	var core_box = game._mesh_box(visual_root, Vector3(0, 1.52, 0.38), Vector3(0.42, 0.42, 0.14), Color("ff9d3b"))
	core_material = core_box.material_override
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_area = Area3D.new()
	core_area.set_meta("hit_zone", "core")
	core_area.position = Vector3(0, 1.50, 0.46)
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
		if stun_left > 0:
			hp_fill_mat.albedo_color = Color("56e8ff")
		elif archetype == Archetype.BOSS_WARDEN:
			hp_fill_mat.albedo_color = Color("ff5c5c") if exposed_left > 0 else Color("ffb84d")
		else:
			hp_fill_mat.albedo_color = Color("5fe3a8") if shield_layers >= 2 else Color("ff9f4a")

func stun(seconds: float):
	if defeated:
		return
	stun_left = maxf(stun_left, seconds)
	action = Action.PATROL
	laser_beam.hide()
	_refresh_hp_bar()

func expose_boss_core(seconds: float):
	if archetype != Archetype.BOSS_WARDEN or defeated:
		return
	exposed_left = maxf(exposed_left, seconds)
	shield_intact = false
	if is_instance_valid(shield_area):
		shield_area.hide()
		shield_area.collision_layer = 0
	if is_instance_valid(core_material):
		core_material.albedo_color = Color("ff3b3b")
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

func apply_damage(amount: int, from_english_shield: bool = false, is_crit: bool = false) -> bool:
	if defeated:
		return false
	if amount <= 0:
		on_wrong_hit_flash()
		return false
	hp = maxi(0, hp - amount)
	if archetype != Archetype.BOSS_WARDEN and hp <= 0:
		shield_layers = 0
	if from_english_shield and archetype == Archetype.BOSS_WARDEN:
		shield_layers = max_shield_layers
		if is_instance_valid(tag_label):
			tag_label.text = base_tag_text
			tag_label.modulate = Color("143832")
		if is_instance_valid(frame_material):
			frame_material.albedo_color = base_border_col
		expose_boss_core(4.5)
		stun(1.25)
		var next_phase := 3 if hp > 300 else (2 if hp > 150 else 1)
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

func show_word(word: String, _new_question: bool):
	# NEVER revive a defeated soldier mid-wave! Dead units stay eliminated until the whole wave is cleared.
	if defeated:
		return
	var has_word := word != ""
	if has_word and (archetype != Archetype.BOSS_WARDEN or exposed_left <= 0):
		shield_area.show()
		shield_area.collision_layer = HIT_LAYER
		shield_intact = true
		combat.game._fit_word(word_label, word, 110)
		if shield_layers >= max_shield_layers and wrong_flash_left <= 0:
			shield_material.albedo_color = Color("edf2e6")
			frame_material.albedo_color = base_border_col
			tag_label.text = base_tag_text
			tag_label.modulate = Color("143832")
	else:
		shield_area.hide()
		shield_area.collision_layer = 0
	_refresh_hp_bar()

func neutralize():
	if defeated:
		return
	defeated = true
	shield_layers = 0
	collision_layer = 0
	shield_area.collision_layer = 0
	if is_instance_valid(head_area):
		head_area.collision_layer = 0
	if is_instance_valid(core_area):
		core_area.collision_layer = 0
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

func _spawn_shatter_fx():
	if not is_instance_valid(combat) or not is_instance_valid(combat.arena):
		return
	var game = combat.game
	var origin = shield_area.global_position
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
				shield_material.albedo_color = Color("edf2e6") if shield_layers >= max_shield_layers else Color("fff0b3")
			if is_instance_valid(frame_material):
				frame_material.albedo_color = base_border_col if shield_layers >= max_shield_layers else Color("ff8c3b")

	var player_at: Vector3 = game.player.position
	var toward_player := player_at - position
	toward_player.y = 0
	var distance := toward_player.length()
	var engaged: bool = (combat.zone == zone and combat.is_zone_engaged(zone))

	# Performance optimization: Distant un-aggroed camp garrisons sleep peacefully at their posts!
	if not engaged and distance > 36.0:
		laser_beam.hide()
		velocity = Vector3.ZERO
		return

	hover_clock += delta
	if archetype == Archetype.SCOUT_DRONE:
		visual_root.position.y = sin(hover_clock * 4.4) * 0.10

	if exposed_left > 0:
		exposed_left = maxf(0, exposed_left - delta)
		if exposed_left <= 0:
			shield_intact = true
			if is_instance_valid(core_material):
				core_material.albedo_color = Color("ff9d3b")
			if engaged and not assigned_word.is_empty():
				show_word(str(assigned_word.get("english", "")), false)
			_refresh_hp_bar()

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

	cooldown = maxf(0, cooldown - delta)
	cover_reposition_cd = maxf(0.0, cover_reposition_cd - delta)
	suppress_cd = maxf(0.0, suppress_cd - delta)
	peek_phase += delta
	var goal := position
	var speed := move_speed()

	if archetype == Archetype.BOSS_WARDEN and engaged:
		boss_ring_cd = maxf(0, boss_ring_cd - delta)
		if boss_ring_cd <= 0 and distance < attack_range() and not combat.player_in_smoke() and combat.is_designated_attacker(self):
			boss_ring_cd = (7.8 if combat.is_single_attacker_mode() else 6.2) if boss_phase >= 2 else (6.0 if combat.is_single_attacker_mode() else 4.6)
			combat.spawn_danger_ring(player_at, 3.4, 18 if combat.is_single_attacker_mode() else 24)

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

		var can_engage_now: bool = combat.is_designated_attacker(self)
		var heavy_ready_aim: bool = (archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN]) and shield_layers >= max_shield_layers and distance >= 5.5
		if can_engage_now and (not is_bounding_to_cover or heavy_ready_aim) and distance < attack_range() and cooldown <= 0 and combat.clear_shot(position) and combat.reserve_attack(self):
			is_bounding_to_cover = false
			visual_root.rotation.x = 0.0
			action = Action.AIM
			aim_left = aim_windup()
			if archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN]:
				game.play_sfx("warning_lock", -13)
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
	else:
		visor.albedo_color = Color("ff4f4f") if archetype in [Archetype.SNIPER_GUARD, Archetype.BOSS_WARDEN] else Color("7ef0c8")

	if engaged and distance > 0.05:
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
