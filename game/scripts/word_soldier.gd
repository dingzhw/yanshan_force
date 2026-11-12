extends CharacterBody3D

enum Action { PATROL, ADVANCE, AIM, COVER }
const HIT_LAYER = 4
const ATTACK_RANGE = 11.0

var combat
var zone: int
var option: int
var home: Vector3
var cover: Vector3
var side: float
var patrol: Array[Vector3] = []
var patrol_index = 0
var action = Action.PATROL
var defeated = false
var shield_area: Area3D
var word_label: Label3D
var shield_material: StandardMaterial3D
var visor: StandardMaterial3D
var legs: Array[Node3D] = []
var stride = 0.0
var cooldown = 0.0
var aim_left = 0.0
var cover_left = 0.0
var cover_goal: Vector3

func setup(controller, zone_index: int, index: int, barrier: Vector3):
	combat = controller
	zone = zone_index
	option = index
	cover = barrier
	side = -1.0 if index % 2 == 0 else 1.0
	home = combat.game.Layout.on_ground(cover + Vector3(side*1.15,0,-1.7))
	position = home + Vector3.UP*0.06
	patrol = [
		home,
		combat.game.Layout.on_ground(cover + Vector3(side*1.3,0,0.05)),
		combat.game.Layout.on_ground(cover + Vector3(side*1.2,0,-2.5))
	]
	patrol_index = 1
	cooldown = 0.6 + index*0.4
	collision_layer = HIT_LAYER
	collision_mask = 1 | HIT_LAYER | 8
	floor_snap_length = 0.35
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.95
	var hitbox = CollisionShape3D.new()
	hitbox.position.y = 0.99
	hitbox.shape = capsule
	add_child(hitbox)
	_build_model()

func _build_model():
	var game = combat.game
	var armor = Color("706f59") if zone == 1 else Color("596d72")
	var dark = Color("303a39")
	game._mesh_box(self,Vector3(0,1.12,0),Vector3(0.73,0.73,0.44),armor)
	game._mesh_box(self,Vector3(0,1.62,0.01),Vector3(0.54,0.36,0.48),dark)
	game._mesh_box(self,Vector3(0,1.82,0),Vector3(0.66,0.21,0.58),armor)
	visor = game._mesh_box(self,Vector3(0,1.65,0.257),Vector3(0.40,0.12,0.035),Color("94e6c5")).material_override
	visor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.49,0.49]:
		game._mesh_box(self,Vector3(x,1.12,0.10),Vector3(0.22,0.47,0.30),armor)
		game._mesh_box(self,Vector3(x,0.97,0.32),Vector3(0.20,0.19,0.33),dark)
	for x in [-0.22,0.22]:
		var leg = Node3D.new()
		leg.position = Vector3(x,0.77,0)
		add_child(leg)
		game._mesh_box(leg,Vector3(0,-0.32,0),Vector3(0.26,0.58,0.29),dark)
		game._mesh_box(leg,Vector3(0,-0.68,0.09),Vector3(0.28,0.17,0.43),armor)
		legs.append(leg)
	shield_area = Area3D.new()
	shield_area.position = Vector3(0,1.31,0.44)
	shield_area.collision_layer = HIT_LAYER
	shield_area.collision_mask = 0
	shield_area.monitoring = false
	shield_area.monitorable = false
	add_child(shield_area)
	var badge_shape = BoxShape3D.new()
	badge_shape.size = Vector3(1.84,0.68,0.15)
	var badge_hitbox = CollisionShape3D.new()
	badge_hitbox.shape = badge_shape
	shield_area.add_child(badge_hitbox)
	shield_material = game._mesh_box(shield_area,Vector3.ZERO,badge_shape.size,Color("e4e8d4")).material_override
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	word_label = game._label3d(shield_area,"",Vector3(0,-0.012,0.089),60,Color("193124"))
	word_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	word_label.pixel_size = 0.0052
	word_label.width = 335
	word_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	word_label.outline_size = 0

func show_word(word: String, new_question: bool):
	if defeated and new_question:
		# Keep reinforcements clear of a player standing in their original lane.
		var player_at: Vector3 = combat.game.player.position
		var spawn := home
		if player_at.distance_to(home) < 2.4:
			for point in patrol:
				if point.distance_to(player_at)>spawn.distance_to(player_at):
					spawn = point
		if player_at.distance_to(spawn) < 1.4:
			spawn = combat.game.Layout.on_ground(cover + Vector3(-side*1.4,0,-2.3))
		position = spawn + Vector3.UP*0.06
		velocity = Vector3.ZERO
		defeated = false
		show()
		collision_layer = HIT_LAYER
		shield_area.collision_layer = HIT_LAYER
		action = Action.ADVANCE
		cooldown = 1.3
	if new_question:
		shield_material.albedo_color = Color("e4e8d4")
	combat.game._fit_word(word_label,word,118)

func neutralize():
	defeated = true
	hide()
	collision_layer = 0
	shield_area.collision_layer = 0
	velocity = Vector3.ZERO
	action = Action.PATROL

func take_cover():
	var player_at: Vector3 = combat.game.player.position
	var toward_player := player_at-cover
	toward_player.y = 0
	if toward_player.length_squared()<0.1:
		toward_player = Vector3.BACK
	cover_goal = combat.game.Layout.on_ground(cover-toward_player.normalized()*1.5)
	action = Action.COVER
	cover_left = 0.95

func _physics_process(delta: float):
	var game = combat.game
	if defeated or game.paused or not combat.in_field():
		return
	if is_instance_valid(game.exploration) and game.exploration.safe():
		velocity=Vector3.ZERO
		return
	var player_at: Vector3 = game.player.position
	var toward_player := player_at-position
	toward_player.y = 0
	var distance := toward_player.length()
	cooldown = maxf(0,cooldown-delta)
	var goal := position
	var speed := 2.4
	if combat.zone != zone or option>=2:
		action = Action.PATROL
		speed = 1.35
		if position.distance_to(patrol[patrol_index])<0.55:
			patrol_index = (patrol_index+1)%patrol.size()
		goal = patrol[patrol_index]
	elif action == Action.COVER:
		goal = cover_goal
		speed = 3.25
		# A flanking player can make this cover useless. Resume the approach.
		cover_left -= delta if position.distance_to(cover_goal)<0.65 else delta*0.35
		if cover_left<=0:
			action = Action.ADVANCE
	elif action == Action.AIM:
		aim_left -= delta
		if aim_left<=0:
			take_cover()
			cooldown = 4.2
			combat.strike(self)
	else:
		action = Action.ADVANCE
		if distance<ATTACK_RANGE and cooldown<=0 and combat.clear_shot(position) and combat.reserve_attack():
			action = Action.AIM
			aim_left = 0.85
		elif distance>4.5:
			goal = player_at+Vector3(-3.6+option*2.4,0,0)
		else:
			goal = position+toward_player.normalized().cross(Vector3.UP)*side
		# Keep patrols in their own zone when a player retreats.
		var offset: Vector3 = goal-combat.game.stations[zone].position
		offset.y = 0
		if offset.length()>14:
			goal = combat.game.stations[zone].position+offset.limit_length(14)
	if not combat.in_field():
		return
	visor.albedo_color = Color("ffaf62") if action==Action.AIM else Color("8be1bb")
	if distance>0.05:
		rotation.y = atan2(toward_player.x,toward_player.z)
	if action==Action.ADVANCE or action==Action.COVER:
		goal = _around_barrier(goal)
	_walk(goal,speed,delta)

func _around_barrier(goal: Vector3) -> Vector3:
	# Route the whole capsule around the assigned cover's side before
	# crossing its face. A ray from the centre alone misses corner contacts.
	var toward_goal := signf(goal.z-cover.z)
	if absf(goal.z-cover.z)<0.95 or (position.z-cover.z)*toward_goal>=0.95 or absf(position.x-cover.x)>2.0:
		return goal
	var lateral := position.x-cover.x
	var edge := signf(lateral) if absf(lateral)>0.25 else side
	var edge_x := cover.x+edge*1.55
	if lateral*edge<1.28:
		return Vector3(edge_x,position.y,position.z)
	return Vector3(edge_x,position.y,cover.z+toward_goal*1.32)

func _walk(goal: Vector3, speed: float, delta: float):
	var direction := goal-position
	direction.y = 0
	if direction.length()<0.24:
		direction = Vector3.ZERO
	else:
		direction = direction.normalized()
		var origin := position+Vector3.UP*0.65
		# Probe around a barrier while the capsule handles actual collisions.
		for angle in [0.0,side*0.8,-side*0.8,side*1.45,-side*1.45]:
			var candidate := direction.rotated(Vector3.UP,angle)
			if not combat.blocked(origin,origin+candidate*0.9):
				direction = candidate
				break
	velocity.x = direction.x*speed
	velocity.z = direction.z*speed
	velocity.y = -0.6 if is_on_floor() else velocity.y-20.0*delta
	move_and_slide()
	var gait := Vector2(get_real_velocity().x,get_real_velocity().z).length()
	stride += delta*gait*4.4
	var swing := sin(stride)*minf(gait*0.15,0.4)
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing
