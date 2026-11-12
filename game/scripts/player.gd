extends CharacterBody3D
## First-person controller with ADS reflex alignment, field medkits [H], and audio replay [Q].

var game
var active = false
var camera: Camera3D
var weapon_root: Node3D
var pitch = 0.0
var yaw = 0.0
var recoil = 0.0
var ammo = 8
var medkits = 1
var reload_left = 0.0
var cooldown = 0.0
var footstep_clock = 0.0
var held_keys = {}
var aiming = false
var weapon_view
const RELOAD_SECONDS = 1.45

const MOVEMENT_KEYS = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT, KEY_SHIFT, KEY_SPACE]

func clear_movement_input():
	held_keys.clear()
	aiming = false
	velocity = Vector3.ZERO
	if is_instance_valid(camera):
		camera.fov = 75

func _input(event):
	if not active:
		return
	if event is InputEventKey:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code in MOVEMENT_KEYS:
			if event.pressed:
				held_keys[code] = true
			else:
				held_keys.erase(code)
			get_viewport().set_input_as_handled()

func key_down(code: int) -> bool:
	return held_keys.has(code)

func _ready():
	collision_layer = 8
	collision_mask = 1 | 4
	var collider = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.65
	collider.shape = capsule
	collider.position.y = 0.85
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.58
	camera.fov = 75
	camera.near = 0.06
	add_child(camera)
	camera.current = true
	weapon_root = Node3D.new()
	camera.add_child(weapon_root)
	weapon_view = game.attach_weapon(weapon_root)
	get_window().focus_exited.connect(clear_movement_input)

func _unhandled_input(event):
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens = 0.0017 if aiming else 0.0023
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, -1.35, 1.35)
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			shoot()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			aiming = true
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		aiming = false
	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_R:
			reload()
		elif code == KEY_E:
			game.interact()
		elif code == KEY_Q:
			game.replay_question_audio()
		elif code == KEY_H:
			use_medkit()

func use_medkit():
	if not active or game.paused or medkits <= 0:
		return
	if not is_instance_valid(game.combat) or not game.combat.in_field():
		game._notice("当前无需使用医疗包。")
		return
	if game.combat.health >= game.combat.MAX_HEALTH and game.combat.shield >= game.rules.max_shield():
		game._notice("生命与护盾已满！")
		return
	medkits -= 1
	game.combat.heal(45, 25)
	game.play_sfx("heal_shield", -10)
	game._notice("已使用应急医疗包 · 生命+45 护盾+25（剩余 %d 个）" % medkits, game.MINT)

func _physics_process(delta):
	if game.paused:
		velocity = Vector3.ZERO
		return
	cooldown = maxf(0, cooldown - delta)
	var recoil_recover = 16.0 if "red_dot" in game.rules.profile.owned else 13.0
	recoil = lerpf(recoil, 0, delta * recoil_recover)
	if reload_left > 0:
		reload_left -= delta
		if reload_left <= 0:
			ammo = game.rules.magazine()
	rotation.y = yaw
	var recoil_pitch = 0.022 if "red_dot" in game.rules.profile.owned else 0.034
	camera.rotation.x = pitch + recoil * recoil_pitch
	var target_fov = (48.0 if "red_dot" in game.rules.profile.owned else 58.0) if aiming else 75.0
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * 13, 1))
	var progress = clampf(reload_left / RELOAD_SECONDS, 0, 1)
	# Align reflex reticle dot (y = 0.234) straight with camera optical axis when aiming
	var target_pose = Vector3(0.0, -0.234, -0.46) if aiming else Vector3(0.21, -0.245, -0.58)
	target_pose.y -= sin(progress * PI) * 0.17
	target_pose.z += recoil * 0.055
	weapon_root.position = weapon_root.position.lerp(target_pose, minf(delta * 15, 1))
	if is_instance_valid(weapon_view):
		weapon_view.animate(delta, progress, Vector2(velocity.x, velocity.z).length(), aiming)
	if not active or game.paused:
		velocity = Vector3.ZERO
		return
	var direction = Vector2(
		float(key_down(KEY_D) or key_down(KEY_RIGHT)) - float(key_down(KEY_A) or key_down(KEY_LEFT)),
		float(key_down(KEY_S) or key_down(KEY_DOWN)) - float(key_down(KEY_W) or key_down(KEY_UP))
	).normalized()
	var speed = 6.1 if key_down(KEY_SHIFT) else 4.25
	if aiming:
		speed *= 0.78
	if "scout" in game.rules.profile.owned:
		speed *= 1.12
	var move_direction = basis * Vector3(direction.x, 0, direction.y)
	velocity.x = lerpf(velocity.x, move_direction.x * speed, minf(delta * 12, 1))
	velocity.z = lerpf(velocity.z, move_direction.z * speed, minf(delta * 12, 1))
	if not is_on_floor():
		velocity.y -= 20 * delta
	elif key_down(KEY_SPACE):
		velocity.y = 6.2
		game.play_sound("jump_a", -22)
	move_and_slide()
	position.x = clampf(position.x, game.Layout.MIN_X + 1.5, game.Layout.MAX_X - 1.5)
	position.z = clampf(position.z, game.Layout.MIN_Z + 1.5, game.Layout.MAX_Z - 1.5)
	if position.y < -5:
		position = Vector3(0, 2, 7)
	footstep_clock -= delta
	if is_on_floor() and direction.length() > 0.1:
		weapon_root.position.y += sin(Time.get_ticks_msec() * 0.009) * (0.004 if aiming else 0.010)
		if footstep_clock <= 0:
			game.play_sound("land", -26)
			footstep_clock = 0.33 if speed > 5 else 0.46

func reload():
	if reload_left <= 0 and ammo < game.rules.magazine():
		reload_left = RELOAD_SECONDS
		game.play_sound("weapon_change", -14)

func shoot():
	if not active or game.paused:
		return
	if cooldown > 0 or reload_left > 0:
		return
	if ammo <= 0:
		reload()
		return
	ammo -= 1
	cooldown = 0.21
	recoil = 1.0
	if is_instance_valid(weapon_view):
		weapon_view.shot()
	game.play_sound("blaster_repeater", -16)
	game.fire(camera)
