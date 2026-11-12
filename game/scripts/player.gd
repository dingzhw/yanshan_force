extends CharacterBody3D
# Movement and camera handling adapted from Kenney Starter Kit FPS (MIT).

var game
var active = false
var camera: Camera3D
var weapon_root: Node3D
var pitch = 0.0
var yaw = 0.0
var recoil = 0.0
var ammo = 8
var reload_left = 0.0
var cooldown = 0.0
var footstep_clock = 0.0
var held_keys = {}
var aiming = false
var weapon_view
const RELOAD_SECONDS = 1.5

const MOVEMENT_KEYS = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT, KEY_SHIFT, KEY_SPACE]

func clear_movement_input():
	held_keys.clear()
	aiming = false
	velocity = Vector3.ZERO
	camera.fov = 75

func _input(event):
	# Track key events before GUI focus can consume them. Logical codes cover
	# keyboards/input methods that do not provide a physical key code.
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
	camera.near = 0.08
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
		yaw -= event.relative.x * 0.0023
		pitch = clampf(pitch - event.relative.y * 0.0023, -1.35, 1.35)
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			shoot()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			aiming = true
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		aiming = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R or event.keycode == KEY_R:
			reload()
		elif event.physical_keycode == KEY_E or event.keycode == KEY_E:
			game.interact()

func _physics_process(delta):
	if game.paused:
		velocity = Vector3.ZERO
		return
	cooldown = maxf(0, cooldown - delta)
	recoil = lerpf(recoil, 0, delta * 13)
	if reload_left > 0:
		reload_left -= delta
		if reload_left <= 0:
			ammo = game.rules.magazine()
	rotation.y = yaw
	camera.rotation.x = pitch + recoil * 0.035
	camera.fov = lerpf(camera.fov,58.0 if aiming else 75.0,minf(delta*12,1))
	var progress = clampf(reload_left/RELOAD_SECONDS,0,1)
	var target_pose = Vector3(0.0,-0.215,-0.72) if aiming else Vector3(0.24,-0.30,-0.73)
	target_pose.y -= sin(progress*PI)*0.18
	target_pose.z += recoil*0.07
	weapon_root.position = weapon_root.position.lerp(target_pose,minf(delta*14,1))
	if is_instance_valid(weapon_view): weapon_view.animate(delta,progress,Vector2(velocity.x,velocity.z).length(),aiming)
	if not active or game.paused:
		velocity = Vector3.ZERO
		return
	var direction = Vector2(float(key_down(KEY_D) or key_down(KEY_RIGHT)) - float(key_down(KEY_A) or key_down(KEY_LEFT)), float(key_down(KEY_S) or key_down(KEY_DOWN)) - float(key_down(KEY_W) or key_down(KEY_UP))).normalized()
	var speed = 6.0 if key_down(KEY_SHIFT) else 4.2
	if "scout" in game.rules.profile.owned:
		speed *= 1.10
	var move_direction = basis * Vector3(direction.x, 0, direction.y)
	velocity.x = lerpf(velocity.x, move_direction.x * speed, minf(delta*12,1))
	velocity.z = lerpf(velocity.z, move_direction.z * speed, minf(delta*12,1))
	if not is_on_floor():
		velocity.y -= 20 * delta
	elif key_down(KEY_SPACE):
		velocity.y = 6.0
	move_and_slide()
	position.x = clampf(position.x, game.Layout.MIN_X+1.5,game.Layout.MAX_X-1.5)
	position.z = clampf(position.z, game.Layout.MIN_Z+1.5,game.Layout.MAX_Z-1.5)
	if position.y < -5:
		position = Vector3(0, 2, 7)
	footstep_clock -= delta
	if is_on_floor() and direction.length() > 0.1:
		weapon_root.position.y += sin(Time.get_ticks_msec()*0.009)*0.012
		if footstep_clock <= 0:
			game.play_sound("land", -26)
			footstep_clock = 0.34 if speed > 5 else 0.48

func reload():
	if reload_left <= 0 and ammo < game.rules.magazine():
		reload_left = RELOAD_SECONDS
		game.play_sound("weapon_change", -14)

func shoot():
	if not active or game.paused: return
	if cooldown > 0 or reload_left > 0:
		return
	if ammo <= 0:
		reload()
		return
	ammo -= 1
	cooldown = 0.24
	recoil = 1.0
	if is_instance_valid(weapon_view): weapon_view.shot()
	game.play_sound("blaster", -18)
	game.fire(camera)
