extends CharacterBody3D
## First-person controller with dual weapons ([1] YS-04 / [2] Tactical Knife / [V] Quick Melee), Gunsmith optics, finite ammo, and tactical consumables ([H], [G], [T]).

var game
var active = false
var camera: Camera3D
var weapon_root: Node3D
var pitch = 0.0
var yaw = 0.0
var recoil = 0.0
var ammo = 8
var reserve_ammo = -1
var medkits = 1
var grenades = 1
var stims = 1
var stim_left = 0.0
var reload_left = 0.0
var cooldown = 0.0
var knife_cooldown = 0.0
var quick_melee_left = 0.0
var weapon_slot = 0  # 0 = YS-04 Carbine, 1 = Tactical Knife
var slash_combo = 0
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
		var optic_id: String = game.rules.active_optic()
		var base_sens = 0.0014 if (aiming and optic_id == "scope_2x") else (0.0017 if aiming else 0.0023)
		yaw -= event.relative.x * base_sens
		pitch = clampf(pitch - event.relative.y * base_sens, -1.35, 1.35)
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			shoot()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if weapon_slot == 0:
				aiming = true
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			select_weapon(1 if weapon_slot == 0 else 0)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		aiming = false
	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_R:
			reload()
		elif code == KEY_1:
			select_weapon(0)
		elif code == KEY_2:
			select_weapon(1)
		elif code == KEY_V:
			quick_melee()
		elif code == KEY_E:
			game.interact()
		elif code == KEY_Q:
			game.replay_question_audio()
		elif code == KEY_H:
			use_medkit()
		elif code == KEY_G:
			throw_smoke_emp()
		elif code == KEY_T:
			use_stim()

func has_infinite_ammo() -> bool:
	return not game.rules.combat_mode or reserve_ammo < 0

func add_reserve_ammo(amount: int):
	if amount <= 0 or has_infinite_ammo():
		return
	var cap = game.rules.magazine() * 8
	reserve_ammo = mini(reserve_ammo + amount, cap)

func select_weapon(slot: int):
	var target := clampi(slot, 0, 1)
	if weapon_slot == target:
		return
	weapon_slot = target
	quick_melee_left = 0.0
	if weapon_slot == 1:
		reload_left = 0.0
		aiming = false
	if is_instance_valid(weapon_view):
		weapon_view.set_weapon_slot(weapon_slot)
	game.play_sound("weapon_change", -18)

func quick_melee():
	if not active or game.paused or knife_cooldown > 0:
		return
	var was_rifle: bool = weapon_slot == 0
	if was_rifle:
		weapon_slot = 1
		reload_left = 0.0
		aiming = false
		quick_melee_left = 0.36
		if is_instance_valid(weapon_view):
			weapon_view.set_weapon_slot(1)
	_perform_knife_slash()

func throw_smoke_emp():
	if not active or game.paused:
		return
	if grenades <= 0:
		game._notice("烟雾/EMP 手雷已耗尽！")
		return
	if not is_instance_valid(game.combat):
		return
	grenades -= 1
	game.deploy_smoke_emp(camera)

func use_stim():
	if not active or game.paused or stims <= 0:
		return
	stims -= 1
	stim_left = 10.0
	if is_instance_valid(game.combat):
		game.combat.heal(12, 18)
	game.play_sfx("heal_shield", -12)
	game._notice("已注射肾上腺素能量饮 · 移速提升+24%% 并持续回盾（剩余 %d）" % stims, game.MINT)

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
	knife_cooldown = maxf(0, knife_cooldown - delta)
	if quick_melee_left > 0:
		quick_melee_left = maxf(0, quick_melee_left - delta)
		if quick_melee_left <= 0 and weapon_slot == 1:
			weapon_slot = 0
			if is_instance_valid(weapon_view):
				weapon_view.set_weapon_slot(0)
	if stim_left > 0:
		stim_left = maxf(0, stim_left - delta)
		if is_instance_valid(game.combat) and game.combat.in_field() and game.combat.shield < game.rules.max_shield():
			game.combat.shield = minf(float(game.rules.max_shield()), game.combat.shield + 3.5 * delta)

	var optic_id: String = game.rules.active_optic()
	var muzzle_id: String = game.rules.active_muzzle()
	var grip_id: String = game.rules.active_grip()

	var recoil_recover = 16.0 if optic_id in ["red_dot", "scope_2x"] else 13.0
	if grip_id == "angled_grip":
		recoil_recover += 2.5
	recoil = lerpf(recoil, 0, delta * recoil_recover)
	if reload_left > 0 and weapon_slot == 0:
		reload_left -= delta
		if reload_left <= 0:
			if has_infinite_ammo():
				ammo = game.rules.magazine()
			else:
				var need: int = game.rules.magazine() - ammo
				var take: int = mini(need, maxi(0, reserve_ammo))
				ammo += take
				reserve_ammo -= take
	rotation.y = yaw
	var recoil_pitch = 0.021 if optic_id in ["red_dot", "scope_2x"] else 0.034
	if muzzle_id == "compensator":
		recoil_pitch *= 0.65
	camera.rotation.x = pitch + recoil * recoil_pitch

	var ads_active := aiming and weapon_slot == 0
	var target_fov = (36.0 if optic_id == "scope_2x" else (48.0 if optic_id == "red_dot" else 58.0)) if ads_active else 75.0
	var fov_speed = 19.0 if grip_id == "angled_grip" else 13.0
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * fov_speed, 1))
	var progress = clampf(reload_left / RELOAD_SECONDS, 0, 1) if weapon_slot == 0 else 0.0
	# Align optic reticle (y = 0.234) straight with camera optical axis when aiming; keep Knife pose steady forward
	var target_pose = Vector3(0.0, -0.234, -0.46) if ads_active else (Vector3(0.155, -0.182, -0.49) if weapon_slot == 1 else Vector3(0.21, -0.245, -0.58))
	target_pose.y -= sin(progress * PI) * 0.042
	target_pose.x -= sin(progress * PI) * 0.035
	target_pose.z += recoil * 0.055
	var pose_speed := 19.0 if grip_id == "angled_grip" else 15.0
	weapon_root.position = weapon_root.position.lerp(target_pose, minf(delta * pose_speed, 1))
	if is_instance_valid(weapon_view):
		weapon_view.animate(delta, progress, Vector2(velocity.x, velocity.z).length(), ads_active)
	if not active or game.paused:
		velocity = Vector3.ZERO
		return
	var direction = Vector2(
		float(key_down(KEY_D) or key_down(KEY_RIGHT)) - float(key_down(KEY_A) or key_down(KEY_LEFT)),
		float(key_down(KEY_S) or key_down(KEY_DOWN)) - float(key_down(KEY_W) or key_down(KEY_UP))
	).normalized()
	var speed = 6.1 if key_down(KEY_SHIFT) else 4.25
	if weapon_slot == 1:
		speed *= 1.12
	elif ads_active:
		speed *= 0.90 if grip_id == "angled_grip" else 0.78
	if "scout" in game.rules.profile.owned:
		speed *= 1.12
	if stim_left > 0:
		speed *= 1.24
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
		weapon_root.position.y += sin(Time.get_ticks_msec() * 0.009) * (0.004 if ads_active else 0.010)
		if footstep_clock <= 0:
			game.play_sound("land", -26)
			footstep_clock = 0.33 if speed > 5 else 0.46

func reload():
	if weapon_slot != 0:
		return
	if reload_left <= 0 and ammo < game.rules.magazine():
		if not has_infinite_ammo() and reserve_ammo <= 0:
			game.play_sfx("dry_fire", -8)
			game._notice("备弹耗尽！按 [2] 切换战术匕首近战补弹，或搜集 5.56 弹药箱", Color("ffd27d"))
			return
		reload_left = RELOAD_SECONDS
		game.play_sound("weapon_change", -14)

func _perform_knife_slash():
	knife_cooldown = 0.38
	slash_combo += 1
	if is_instance_valid(weapon_view):
		weapon_view.trigger_knife_slash(slash_combo)
	game.play_sfx("knife_slash", -8)
	game.melee_strike(camera)

func shoot():
	if not active or game.paused:
		return
	if weapon_slot == 1:
		if knife_cooldown <= 0:
			_perform_knife_slash()
		return
	if cooldown > 0 or reload_left > 0:
		return
	if ammo <= 0:
		if has_infinite_ammo() or reserve_ammo > 0:
			reload()
		else:
			cooldown = 0.28
			game.play_sfx("dry_fire", -8)
			game._notice("弹匣已空且无备弹！按 [2] 或 [V] 使用战术匕首近战击杀恢复备弹", Color("ffd27d"))
		return
	ammo -= 1
	cooldown = 0.21
	var muzzle_id: String = game.rules.active_muzzle()
	var grip_id: String = game.rules.active_grip()
	recoil = 0.65 if muzzle_id == "compensator" else (0.85 if grip_id == "angled_grip" else 1.0)
	if is_instance_valid(weapon_view):
		weapon_view.shot()
	if muzzle_id == "suppressor":
		game.play_sfx("shot_suppressed", -10)
	else:
		game.play_sound("blaster_repeater", -16)
	game.fire(camera)
