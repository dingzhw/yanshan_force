extends CharacterBody3D
## Tactical Word Bot / Patrol Drone with 3 archetypes, holographic word shield, laser lock, and shatter FX.

enum Action { PATROL, ADVANCE, AIM, COVER }
enum Archetype { ASSAULT_BOT, SCOUT_DRONE, SNIPER_GUARD }

const HIT_LAYER = 4

var combat
var zone: int
var option: int
var archetype: int = Archetype.ASSAULT_BOT
var home: Vector3
var cover: Vector3
var side: float
var patrol: Array[Vector3] = []
var patrol_index = 0
var action = Action.PATROL
var defeated = false

var visual_root: Node3D
var shield_area: Area3D
var word_label: Label3D
var tag_label: Label3D
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

func attack_range() -> float:
	if archetype == Archetype.SNIPER_GUARD:
		return 28.0
	if archetype == Archetype.SCOUT_DRONE:
		return 21.5
	return 19.5

func move_speed() -> float:
	if archetype == Archetype.SCOUT_DRONE:
		return 4.1
	if archetype == Archetype.SNIPER_GUARD:
		return 2.15
	return 2.95

func base_shot_damage() -> int:
	if archetype == Archetype.SNIPER_GUARD:
		return 17
	if archetype == Archetype.SCOUT_DRONE:
		return 8
	return 11

func fire_interval() -> float:
	if archetype == Archetype.SCOUT_DRONE:
		return 2.35
	if archetype == Archetype.SNIPER_GUARD:
		return 3.75
	return 2.95

func aim_windup() -> float:
	if archetype == Archetype.SNIPER_GUARD:
		return 1.08
	if archetype == Archetype.SCOUT_DRONE:
		return 0.68
	return 0.80

func setup(controller, zone_index: int, index: int, barrier: Vector3, bot_type: int = Archetype.ASSAULT_BOT):
	combat = controller
	zone = zone_index
	option = index
	archetype = bot_type
	cover = barrier
	side = -1.0 if index % 2 == 0 else 1.0
	home = combat.game.Layout.on_ground(cover + Vector3(side * 1.45, 0, -1.65))
	position = home + Vector3.UP * 0.06
	patrol = [
		home,
		combat.game.Layout.on_ground(cover + Vector3(side * 1.90, 0, 0.55)),
		combat.game.Layout.on_ground(cover + Vector3(side * 1.65, 0, -2.65))
	]
	patrol_index = 1
	hover_clock = index * 1.3
	cooldown = 0.55 + index * 0.32
	collision_layer = HIT_LAYER
	collision_mask = 1 | HIT_LAYER | 8
	floor_snap_length = 0.38
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.44
	capsule.height = 1.98
	var hitbox = CollisionShape3D.new()
	hitbox.position.y = 1.0
	hitbox.shape = capsule
	add_child(hitbox)
	_build_model()

func _metal_mat(color: Color, metallic = 0.52, rough = 0.45) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m

func _build_model():
	var game = combat.game
	visual_root = Node3D.new()
	add_child(visual_root)

	if archetype == Archetype.SCOUT_DRONE:
		_build_drone_chassis(game)
	elif archetype == Archetype.SNIPER_GUARD:
		_build_sniper_chassis(game)
	else:
		_build_assault_chassis(game)

	# Holographic Framed Electronic Word Shield
	shield_area = Area3D.new()
	var shield_y = 1.44 if archetype == Archetype.SNIPER_GUARD else (1.38 if archetype == Archetype.SCOUT_DRONE else 1.32)
	shield_area.position = Vector3(0, shield_y, 0.48)
	shield_area.collision_layer = HIT_LAYER
	shield_area.collision_mask = 0
	shield_area.monitoring = false
	shield_area.monitorable = false
	add_child(shield_area)

	var badge_shape = BoxShape3D.new()
	badge_shape.size = Vector3(2.04, 0.76, 0.16)
	var badge_hitbox = CollisionShape3D.new()
	badge_hitbox.shape = badge_shape
	shield_area.add_child(badge_hitbox)

	var border_col = Color("ff9b54") if archetype == Archetype.SCOUT_DRONE else (Color("ff5d6c") if archetype == Archetype.SNIPER_GUARD else Color("5ce0b8"))
	var outer_bezel = game._mesh_box(shield_area, Vector3(0, 0, -0.015), Vector3(2.04, 0.76, 0.06), border_col)
	frame_material = outer_bezel.material_override
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var screen_box = game._mesh_box(shield_area, Vector3(0, -0.02, 0.02), Vector3(1.92, 0.62, 0.05), Color("edf2e6"))
	shield_material = screen_box.material_override
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var role_text = ["突击护盾兵", "迅捷侦察机", "重装狙击卫"][archetype]
	tag_label = game._label3d(shield_area, "%s · %s" % [char(65 + option), role_text], Vector3(0, 0.22, 0.055), 19, Color("143832"))
	tag_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag_label.pixel_size = 0.0044
	tag_label.outline_size = 0

	word_label = game._label3d(shield_area, "", Vector3(0, -0.05, 0.058), 60, Color("102620"))
	word_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	word_label.pixel_size = 0.0052
	word_label.width = 345
	word_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	word_label.outline_size = 0

	# Sniper / Aim Laser Sight Beam
	laser_beam = MeshInstance3D.new()
	var beam_box = BoxMesh.new()
	beam_box.size = Vector3(0.025, 0.025, 1.0)
	laser_beam.mesh = beam_box
	var laser_mat = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.85) if archetype == Archetype.SNIPER_GUARD else Color(1.0, 0.65, 0.22, 0.65)
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_beam.material_override = laser_mat
	laser_beam.hide()
	add_child(laser_beam)

func _build_drone_chassis(game):
	legs.clear()
	var hull_mat = _metal_mat(Color("2d3840"), 0.68, 0.34)
	var accent_mat = _metal_mat(Color("8a5d2e"), 0.72, 0.32)
	var fuselage = game._mesh_box(visual_root, Vector3(0, 1.72, 0), Vector3(0.54, 0.28, 0.58), Color.WHITE)
	fuselage.material_override = hull_mat
	var canopy = game._mesh_box(visual_root, Vector3(0, 1.88, -0.02), Vector3(0.38, 0.12, 0.40), Color.WHITE)
	canopy.material_override = accent_mat
	var wing_mat = _metal_mat(Color("1e262c"), 0.65, 0.38)
	for x in [-0.58, 0.58]:
		var arm = game._mesh_box(visual_root, Vector3(x * 0.56, 1.78, 0), Vector3(0.46, 0.06, 0.12), Color.WHITE)
		arm.material_override = wing_mat
		var ring = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.18
		torus.outer_radius = 0.24
		ring.mesh = torus
		ring.position = Vector3(x, 1.80, 0)
		ring.material_override = wing_mat
		visual_root.add_child(ring)
		var thruster = game._mesh_box(visual_root, Vector3(x, 1.77, 0), Vector3(0.18, 0.02, 0.18), Color("6cf0d0"))
		thruster.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor = game._mesh_box(visual_root, Vector3(0, 1.74, 0.30), Vector3(0.38, 0.10, 0.05), Color("ffb35c")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _build_assault_chassis(game):
	var armor_mat = _metal_mat(Color("455954") if zone == 0 else Color("3f5261"), 0.48, 0.46)
	var dark_mat = _metal_mat(Color("222b2e"), 0.60, 0.40)
	var chest = game._mesh_box(visual_root, Vector3(0, 1.15, 0), Vector3(0.68, 0.68, 0.42), Color.WHITE)
	chest.material_override = armor_mat
	var head = game._mesh_box(visual_root, Vector3(0, 1.66, 0.02), Vector3(0.46, 0.32, 0.42), Color.WHITE)
	head.material_override = dark_mat
	var crest = game._mesh_box(visual_root, Vector3(0, 1.85, 0), Vector3(0.54, 0.12, 0.48), Color.WHITE)
	crest.material_override = armor_mat
	visor = game._mesh_box(visual_root, Vector3(0, 1.67, 0.24), Vector3(0.38, 0.10, 0.04), Color("7ef0c8")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.46, 0.46]:
		var pauldron = game._mesh_box(visual_root, Vector3(x, 1.34, 0.02), Vector3(0.24, 0.26, 0.36), Color.WHITE)
		pauldron.material_override = armor_mat
		var forearm = game._mesh_box(visual_root, Vector3(x, 1.02, 0.22), Vector3(0.16, 0.22, 0.36), Color.WHITE)
		forearm.material_override = dark_mat
	for x in [-0.21, 0.21]:
		var leg = Node3D.new()
		leg.position = Vector3(x, 0.78, 0)
		visual_root.add_child(leg)
		var thigh = game._mesh_box(leg, Vector3(0, -0.30, 0), Vector3(0.22, 0.56, 0.26), Color.WHITE)
		thigh.material_override = dark_mat
		var boot = game._mesh_box(leg, Vector3(0, -0.66, 0.07), Vector3(0.25, 0.18, 0.38), Color.WHITE)
		boot.material_override = armor_mat
		legs.append(leg)

func _build_sniper_chassis(game):
	var heavy_mat = _metal_mat(Color("3b332b"), 0.58, 0.38)
	var trim_mat = _metal_mat(Color("8c6d3f"), 0.72, 0.32)
	var dark_mat = _metal_mat(Color("1d2126"), 0.62, 0.42)
	var torso = game._mesh_box(visual_root, Vector3(0, 1.24, 0), Vector3(0.82, 0.78, 0.50), Color.WHITE)
	torso.material_override = heavy_mat
	var helm = game._mesh_box(visual_root, Vector3(0, 1.80, 0.02), Vector3(0.52, 0.36, 0.46), Color.WHITE)
	helm.material_override = dark_mat
	# Twin shoulder rail pylons
	for x in [-0.54, 0.54]:
		var pad = game._mesh_box(visual_root, Vector3(x, 1.48, 0), Vector3(0.28, 0.34, 0.44), Color.WHITE)
		pad.material_override = trim_mat
		var rail = game._mesh_box(visual_root, Vector3(x * 0.85, 1.92, 0.14), Vector3(0.10, 0.14, 0.62), Color.WHITE)
		rail.material_override = dark_mat
	visor = game._mesh_box(visual_root, Vector3(0, 1.80, 0.26), Vector3(0.42, 0.11, 0.05), Color("ff5c6c")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.25, 0.25]:
		var leg = Node3D.new()
		leg.position = Vector3(x, 0.82, 0)
		visual_root.add_child(leg)
		var thigh = game._mesh_box(leg, Vector3(0, -0.34, 0), Vector3(0.26, 0.62, 0.30), Color.WHITE)
		thigh.material_override = dark_mat
		var boot = game._mesh_box(leg, Vector3(0, -0.72, 0.08), Vector3(0.30, 0.20, 0.44), Color.WHITE)
		boot.material_override = trim_mat
		legs.append(leg)

func show_word(word: String, new_question: bool):
	if defeat_tween and defeat_tween.is_valid():
		defeat_tween.kill()
	visual_root.rotation = Vector3.ZERO
	visual_root.position = Vector3.ZERO
	visual_root.scale = Vector3.ONE
	shield_area.show()
	laser_beam.hide()
	if defeated and new_question:
		var player_at: Vector3 = combat.game.player.position
		var spawn := home
		if player_at.distance_to(home) < 2.6:
			for point in patrol:
				if point.distance_to(player_at) > spawn.distance_to(player_at):
					spawn = point
		if player_at.distance_to(spawn) < 1.5:
			spawn = combat.game.Layout.on_ground(cover + Vector3(-side * 1.5, 0, -2.4))
		position = spawn + Vector3.UP * 0.06
		velocity = Vector3.ZERO
		defeated = false
		show()
		collision_layer = HIT_LAYER
		shield_area.collision_layer = HIT_LAYER
		action = Action.ADVANCE
		cooldown = 1.05
	if new_question:
		shield_material.albedo_color = Color("edf2e6")
	combat.game._fit_word(word_label, word, 114)

func neutralize():
	defeated = true
	collision_layer = 0
	shield_area.collision_layer = 0
	velocity = Vector3.ZERO
	action = Action.PATROL
	laser_beam.hide()
	shield_area.hide()
	_spawn_shatter_fx()
	if defeat_tween and defeat_tween.is_valid():
		defeat_tween.kill()
	defeat_tween = create_tween()
	defeat_tween.set_parallel(true)
	defeat_tween.tween_property(visual_root, "rotation:x", -0.95, 0.28)
	defeat_tween.tween_property(visual_root, "position:y", -0.45, 0.28)
	defeat_tween.tween_property(visual_root, "scale", Vector3(0.82, 0.82, 0.82), 0.28)
	defeat_tween.chain().tween_callback(func():
		if defeated:
			hide()
	)

func _spawn_shatter_fx():
	if not is_instance_valid(combat) or not is_instance_valid(combat.arena):
		return
	var game = combat.game
	var origin = shield_area.global_position
	for i in 6:
		var shard = game._mesh_box(combat.arena, origin, Vector3(0.22, 0.14, 0.04), Color("7af5cc"))
		shard.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var angle = TAU * float(i) / 6.0 + 0.3
		var target_pos = origin + Vector3(cos(angle) * 1.15, 0.45 + sin(angle) * 0.55, sin(angle) * 0.65)
		var tw = shard.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "global_position", target_pos, 0.34)
		tw.tween_property(shard, "rotation", Vector3(angle * 2.0, angle, angle * 1.5), 0.34)
		tw.tween_property(shard, "scale", Vector3(0.05, 0.05, 0.05), 0.34)
		tw.chain().tween_callback(shard.queue_free)
	var pop = game._label3d(combat.arena, "+%d" % game.Rules.BASE_ANSWER_SCORE, origin + Vector3(0, 0.45, 0), 46, game.MINT)
	var ptw = pop.create_tween()
	ptw.tween_property(pop, "position:y", origin.y + 1.45, 0.55)
	ptw.tween_callback(pop.queue_free)

func take_cover():
	laser_beam.hide()
	var player_at: Vector3 = combat.game.player.position
	var toward_player := player_at - cover
	toward_player.y = 0
	if toward_player.length_squared() < 0.1:
		toward_player = Vector3.BACK
	cover_goal = combat.game.Layout.on_ground(cover - toward_player.normalized() * 1.55)
	action = Action.COVER
	cover_left = 0.72 if archetype == Archetype.SCOUT_DRONE else 0.95

func _update_laser(player_eye: Vector3):
	if action != Action.AIM or defeated:
		laser_beam.hide()
		return
	var from = global_position + Vector3(0, 1.72 if archetype != Archetype.ASSAULT_BOT else 1.62, 0)
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

	hover_clock += delta
	if archetype == Archetype.SCOUT_DRONE:
		visual_root.position.y = sin(hover_clock * 4.4) * 0.11

	var player_at: Vector3 = game.player.position
	var toward_player := player_at - position
	toward_player.y = 0
	var distance := toward_player.length()
	cooldown = maxf(0, cooldown - delta)
	var goal := position
	var speed := move_speed()

	# Up to 3 active shooters (option < 3) engage aggressively in active zone!
	if combat.zone != zone or option >= 3:
		action = Action.PATROL
		speed *= 0.62
		if position.distance_to(patrol[patrol_index]) < 0.55:
			patrol_index = (patrol_index + 1) % patrol.size()
		goal = patrol[patrol_index]
	elif action == Action.COVER:
		goal = cover_goal
		speed *= 1.18
		cover_left -= delta if position.distance_to(cover_goal) < 0.65 else delta * 0.40
		if cover_left <= 0:
			action = Action.ADVANCE
	elif action == Action.AIM:
		aim_left -= delta
		_update_laser(player_at + Vector3.UP * 1.24)
		if aim_left <= 0:
			laser_beam.hide()
			take_cover()
			cooldown = fire_interval() * (0.72 if combat.rage_left > 0 else 1.0)
			combat.strike(self)
	else:
		action = Action.ADVANCE
		laser_beam.hide()
		if distance < attack_range() and cooldown <= 0 and combat.clear_shot(position) and combat.reserve_attack():
			action = Action.AIM
			aim_left = aim_windup()
			if archetype == Archetype.SNIPER_GUARD:
				game.play_sfx("warning_lock", -13)
		elif archetype == Archetype.SNIPER_GUARD and distance < 13.0 and distance > 6.5 and combat.clear_shot(position):
			# Sniper holds medium-long vantage only when line-of-sight is already clear
			goal = position + toward_player.normalized().cross(Vector3.UP) * side * 1.4
		elif distance > (3.8 if archetype == Archetype.SCOUT_DRONE else 5.0):
			goal = player_at + Vector3(-3.8 + option * 2.5, 0, 0)
		else:
			goal = position + toward_player.normalized().cross(Vector3.UP) * side * 1.6
		var zone_center: Vector3 = combat.zone_center(zone)
		var offset: Vector3 = goal - zone_center
		offset.y = 0
		var max_leash: float = combat.zone_pursuit(zone) - 2.0
		if offset.length() > max_leash:
			goal = zone_center + offset.limit_length(max_leash)

	if not combat.in_field():
		return
	if action == Action.AIM:
		visor.albedo_color = Color("ffb347")
	else:
		visor.albedo_color = Color("ff5c6c") if archetype == Archetype.SNIPER_GUARD else Color("7ef0c8")

	if distance > 0.05:
		rotation.y = atan2(toward_player.x, toward_player.z)
	if action == Action.ADVANCE or action == Action.COVER:
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
