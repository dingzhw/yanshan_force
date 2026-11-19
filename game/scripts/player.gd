extends CharacterBody3D
## First-person controller with tactical stances ([C] Crouch / [Z,Ctrl] Prone), hybrid [Q/E] cover lean,
## dual weapons ([1] YS-04 / [2] Tactical Knife / [V] Quick Melee), [F] interact, [X] audio replay, and consumables.

const STANCE_STAND := 0
const STANCE_CROUCH := 1
const STANCE_PRONE := 2
const LEAN_HOLD_THRESHOLD := 0.22
const LEAN_MAX_OFFSET := 0.36
const LEAN_MAX_ROLL := 0.22
const RELOAD_SECONDS := 1.45

const MOVEMENT_KEYS = [
	KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT,
	KEY_SHIFT, KEY_SPACE, KEY_Q, KEY_E
]

var game
var active = false
var camera: Camera3D
var collider: CollisionShape3D
var capsule: CapsuleShape3D
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

# Tactical stance & cover lean state
var stance: int = STANCE_STAND
var current_eye_y: float = 1.58
var lean_dir: int = 0          # -1 = left (Q), 0 = center, +1 = right (E)
var lean_blend: float = 0.0    # smoothed [-1.0, +1.0]
var effective_lean: float = 0.0
var lean_hold_time := {KEY_Q: 0.0, KEY_E: 0.0}
var lean_activated_on_press := {KEY_Q: false, KEY_E: false}
var knockback_vel := Vector3.ZERO

func clear_movement_input():
	held_keys.clear()
	aiming = false
	lean_dir = 0
	lean_blend = 0.0
	effective_lean = 0.0
	lean_hold_time[KEY_Q] = 0.0
	lean_hold_time[KEY_E] = 0.0
	lean_activated_on_press[KEY_Q] = false
	lean_activated_on_press[KEY_E] = false
	knockback_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	if is_instance_valid(camera):
		camera.fov = 75
		camera.rotation.z = 0.0
		camera.position.x = 0.0

func reset_stance():
	stance = STANCE_STAND
	current_eye_y = 1.58
	lean_dir = 0
	lean_blend = 0.0
	effective_lean = 0.0
	if is_instance_valid(capsule) and is_instance_valid(collider):
		capsule.height = 1.65
		collider.position.y = 0.85
	if is_instance_valid(camera):
		camera.position = Vector3(0.0, 1.58, 0.0)
		camera.rotation.z = 0.0

func _input(event):
	if not active:
		return
	if event is InputEventKey:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code in MOVEMENT_KEYS:
			if event.pressed:
				if not event.echo and (code == KEY_Q or code == KEY_E):
					_on_lean_key_pressed(code)
				held_keys[code] = true
			else:
				held_keys.erase(code)
				if code == KEY_Q or code == KEY_E:
					_on_lean_key_released(code)
			get_viewport().set_input_as_handled()

func _on_lean_key_pressed(code: int):
	if game.paused:
		return
	var side := -1 if code == KEY_Q else 1
	lean_hold_time[code] = 0.0
	if lean_dir == side:
		lean_dir = 0
		lean_activated_on_press[code] = false
	else:
		lean_dir = side
		lean_activated_on_press[code] = true

func _on_lean_key_released(code: int):
	var side := -1 if code == KEY_Q else 1
	var held_t := float(lean_hold_time.get(code, 0.0))
	if bool(lean_activated_on_press.get(code, false)) and held_t >= LEAN_HOLD_THRESHOLD and lean_dir == side:
		lean_dir = 0
	lean_hold_time[code] = 0.0
	lean_activated_on_press[code] = false

func key_down(code: int) -> bool:
	return held_keys.has(code)

func _ready():
	collision_layer = 8
	collision_mask = 1 | 4
	collider = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
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
		elif code == KEY_F:
			game.interact()
		elif code == KEY_X:
			game.replay_question_audio()
		elif code == KEY_C:
			toggle_crouch()
		elif code == KEY_Z or code == KEY_CTRL:
			toggle_prone()
		elif code == KEY_H:
			use_medkit()
		elif code == KEY_G:
			throw_smoke_emp()
		elif code == KEY_T:
			use_stim()
		elif code == KEY_B and is_instance_valid(game.loot_ui):
			game.loot_ui.toggle_backpack()
		elif code == KEY_I and is_instance_valid(game.loot_ui):
			game.loot_ui.inspect_best_in_bag()

func toggle_crouch():
	if not active or game.paused:
		return
	if stance == STANCE_CROUCH:
		set_stance(STANCE_STAND)
	else:
		set_stance(STANCE_CROUCH)

func toggle_prone():
	if not active or game.paused:
		return
	if stance == STANCE_PRONE:
		set_stance(STANCE_STAND)
	else:
		set_stance(STANCE_PRONE)

func can_stand_to(target_stance: int) -> bool:
	if target_stance >= stance:
		return true  # Lowering stance never requires overhead room
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var req_top := 1.72 if target_stance == STANCE_STAND else 1.16
	var space := get_world_3d().direct_space_state
	for off: Vector3 in [Vector3.ZERO, Vector3(0.20, 0, 0), Vector3(-0.20, 0, 0), Vector3(0, 0, 0.20), Vector3(0, 0, -0.20)]:
		var from_p: Vector3 = global_position + off + Vector3(0, 0.36, 0)
		var to_p: Vector3 = global_position + off + Vector3(0, req_top, 0)
		var q := PhysicsRayQueryParameters3D.create(from_p, to_p, 1 | 4, [get_rid()])
		if not space.intersect_ray(q).is_empty():
			return false
	return true

func set_stance(target_stance: int, silent: bool = false) -> bool:
	var clamped := clampi(target_stance, STANCE_STAND, STANCE_PRONE)
	if clamped == stance:
		return true
	if not can_stand_to(clamped):
		if clamped == STANCE_STAND and stance == STANCE_PRONE and can_stand_to(STANCE_CROUCH):
			clamped = STANCE_CROUCH
		else:
			if not silent:
				game._notice("上方空间受限，无法起身！", Color("ffd27d"))
			return false
	stance = clamped
	if not silent:
		game.play_sound("land", -28)
	return true

func stance_label() -> String:
	var s_txt := "站立"
	if stance == STANCE_CROUCH:
		s_txt = "蹲伏"
	elif stance == STANCE_PRONE:
		s_txt = "卧倒"
	if lean_dir < 0:
		s_txt += "·左探"
	elif lean_dir > 0:
		s_txt += "·右探"
	return s_txt

func get_aim_target_position() -> Vector3:
	if is_instance_valid(camera) and camera.is_inside_tree():
		return camera.global_position - Vector3(0.0, 0.08, 0.0)
	return global_position + Vector3(0.0, current_eye_y - 0.08, 0.0)

func evasion_profile_multiplier() -> float:
	var mult := 1.0
	if stance == STANCE_CROUCH:
		mult *= 0.78
	elif stance == STANCE_PRONE:
		mult *= 0.56
	if absf(effective_lean) > 0.25:
		mult *= 0.80
	return mult

func apply_knockback(impulse: Vector3):
	knockback_vel += Vector3(impulse.x, 0.0, impulse.z)
	if impulse.y > 0.0 and is_on_floor():
		velocity.y = maxf(velocity.y, impulse.y)

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

func _update_stance_and_lean(delta: float):
	if key_down(KEY_Q):
		lean_hold_time[KEY_Q] = float(lean_hold_time.get(KEY_Q, 0.0)) + delta
	if key_down(KEY_E):
		lean_hold_time[KEY_E] = float(lean_hold_time.get(KEY_E, 0.0)) + delta

	# Target capsule height & eye height (capsule bottom stays strictly at +0.025m in all stances!)
	var target_eye := 1.58
	var target_cap_h := 1.65
	if stance == STANCE_CROUCH:
		target_eye = 1.04
		target_cap_h = 1.09
	elif stance == STANCE_PRONE:
		target_eye = 0.46
		target_cap_h = 0.65

	var stance_lerp := minf(delta * 12.0, 1.0)
	current_eye_y = lerpf(current_eye_y, target_eye, stance_lerp)
	if is_instance_valid(capsule) and is_instance_valid(collider):
		capsule.height = lerpf(capsule.height, target_cap_h, stance_lerp)
		collider.position.y = capsule.height * 0.5 + 0.025

	var max_lean_scale := 0.45 if stance == STANCE_PRONE else 1.0
	var desired_lean := float(lean_dir) * max_lean_scale
	lean_blend = lerpf(lean_blend, desired_lean, minf(delta * 13.5, 1.0))

	# Clamp lateral lean offset against side walls/cover so camera never clips inside geometry
	var raw_lat := lean_blend * LEAN_MAX_OFFSET
	var clamped_lat := raw_lat
	if absf(raw_lat) > 0.015 and is_inside_tree() and get_world_3d() != null:
		var side_sign := signf(raw_lat)
		var side_vec := global_transform.basis.x.normalized() * side_sign
		var head_origin := global_position + Vector3(0.0, current_eye_y, 0.0)
		var probe_len := absf(raw_lat) + 0.25
		var rq := PhysicsRayQueryParameters3D.create(head_origin, head_origin + side_vec * probe_len, 1 | 4, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(rq)
		if not hit.is_empty():
			var safe_d := maxf(0.0, head_origin.distance_to(hit.position) - 0.24)
			clamped_lat = side_sign * minf(absf(raw_lat), safe_d)

	effective_lean = clamped_lat / LEAN_MAX_OFFSET
	camera.position.x = clamped_lat
	camera.position.y = current_eye_y - absf(clamped_lat) * 0.13
	camera.rotation.z = -effective_lean * LEAN_MAX_ROLL

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

	var direction = Vector2(
		float(key_down(KEY_D) or key_down(KEY_RIGHT)) - float(key_down(KEY_A) or key_down(KEY_LEFT)),
		float(key_down(KEY_S) or key_down(KEY_DOWN)) - float(key_down(KEY_W) or key_down(KEY_UP))
	).normalized()

	# Sprinting stands the player up (if overhead room allows) and cancels cover lean
	var wants_sprint := active and key_down(KEY_SHIFT) and direction.length() > 0.1 and not aiming
	if wants_sprint:
		lean_dir = 0
		if stance != STANCE_STAND:
			set_stance(STANCE_STAND, true)

	_update_stance_and_lean(delta)

	var recoil_pitch = 0.021 if optic_id in ["red_dot", "scope_2x"] else 0.034
	if muzzle_id == "compensator":
		recoil_pitch *= 0.65
	var max_pitch_down := -0.78 if stance == STANCE_PRONE else -1.35
	pitch = clampf(pitch, max_pitch_down, 1.35)
	camera.rotation.x = pitch + recoil * recoil_pitch

	var ads_active := aiming and weapon_slot == 0
	var target_fov = (36.0 if optic_id == "scope_2x" else (48.0 if optic_id == "red_dot" else 58.0)) if ads_active else 75.0
	var fov_speed = 19.0 if grip_id == "angled_grip" else 13.0
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * fov_speed, 1))
	var progress = clampf(reload_left / RELOAD_SECONDS, 0, 1) if weapon_slot == 0 else 0.0
	# Align optic reticle (y = 0.234) straight with camera optical axis when aiming; keep Knife rig torso-centered so shoulders stay behind lens!
	var target_pose = Vector3(0.0, -0.234, -0.46) if ads_active else (Vector3(0.0, -0.145, -0.35) if weapon_slot == 1 else Vector3(0.21, -0.245, -0.58))
	if not ads_active and weapon_slot == 0 and is_instance_valid(game.combat) and game.combat.zone == 0:
		target_pose.y -= 0.075
	target_pose.y -= sin(progress * PI) * 0.042
	target_pose.x -= sin(progress * PI) * 0.035
	target_pose.z += recoil * 0.055
	var pose_speed := 19.0 if grip_id == "angled_grip" else 15.0
	weapon_root.position = weapon_root.position.lerp(target_pose, minf(delta * pose_speed, 1))
	weapon_root.rotation.z = lerpf(weapon_root.rotation.z, -effective_lean * (0.04 if ads_active else 0.11), minf(delta * 14.0, 1.0))
	if is_instance_valid(weapon_view):
		weapon_view.animate(delta, progress, Vector2(velocity.x, velocity.z).length(), ads_active)
	if not active or game.paused:
		velocity = Vector3.ZERO
		return

	var sprinting := wants_sprint and stance == STANCE_STAND
	var speed = 6.1 if sprinting else 4.25
	if stance == STANCE_CROUCH:
		speed *= 0.62
	elif stance == STANCE_PRONE:
		speed *= 0.34
	if absf(effective_lean) > 0.15:
		speed *= 0.82
	if weapon_slot == 1:
		speed *= 1.12
	elif ads_active:
		speed *= 0.90 if grip_id == "angled_grip" else 0.78
	if "scout" in game.rules.profile.owned:
		speed *= 1.12
	if stim_left > 0:
		speed *= 1.24

	knockback_vel = knockback_vel.lerp(Vector3.ZERO, minf(delta * 8.5, 1.0))
	var move_direction = basis * Vector3(direction.x, 0, direction.y)
	velocity.x = lerpf(velocity.x, move_direction.x * speed, minf(delta * 12, 1)) + knockback_vel.x
	velocity.z = lerpf(velocity.z, move_direction.z * speed, minf(delta * 12, 1)) + knockback_vel.z
	if not is_on_floor():
		velocity.y -= 20 * delta
	elif key_down(KEY_SPACE):
		if stance != STANCE_STAND:
			set_stance(STANCE_STAND)
			held_keys.erase(KEY_SPACE)
		else:
			velocity.y = 6.2
			game.play_sound("jump_a", -22)
	move_and_slide()
	position.x = clampf(position.x, game.Layout.MIN_X + 1.5, game.Layout.MAX_X - 1.5)
	position.z = clampf(position.z, game.Layout.MIN_Z + 1.5, game.Layout.MAX_Z - 1.5)
	if position.y < -5:
		position = Vector3(0, 2, 7)
	footstep_clock -= delta
	if is_on_floor() and direction.length() > 0.1:
		var bob_amp := (0.003 if ads_active else 0.006) if stance != STANCE_STAND else (0.004 if ads_active else 0.010)
		weapon_root.position.y += sin(Time.get_ticks_msec() * 0.009) * bob_amp
		if footstep_clock <= 0:
			var step_vol := -32 if stance == STANCE_PRONE else (-29 if stance == STANCE_CROUCH else -26)
			game.play_sound("land", step_vol)
			footstep_clock = 0.33 if speed > 5 else (0.62 if stance == STANCE_PRONE else 0.46)

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
	var stance_recoil := 0.52 if stance == STANCE_PRONE else (0.74 if stance == STANCE_CROUCH else 1.0)
	recoil = (0.65 if muzzle_id == "compensator" else (0.85 if grip_id == "angled_grip" else 1.0)) * stance_recoil
	if is_instance_valid(weapon_view):
		weapon_view.shot()
	if muzzle_id == "suppressor":
		game.play_sfx("shot_suppressed", -10)
	else:
		game.play_sound("blaster_repeater", -16)
	game.fire(camera)
