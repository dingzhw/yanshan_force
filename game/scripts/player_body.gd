extends Node3D
## Articulated 3D full-body hero controller for '游侠·少羽' (v0.9.3).
## - Loads Blender 4.5 asset res://assets/slice/player_shaoyu.glb
## - In 1P: hides head, arms, backpack & world weapon while keeping torso/legs/boots genuinely visible when looking down!
## - In 3P: shows complete character + real equipped YS-04 carbine (synced skins/attachments) or tactical knife + back holster!
## - Smooth procedural animations: idle, 8-dir walk/sprint, jump, crouch, prone crawl, Q/E cover lean, recoil, reload, knife slash & [V] slam!

const HERO_GLB := "res://assets/slice/player_shaoyu.glb"

var game
var hero_root: Node3D
var hips_pivot: Node3D
var torso_pivot: Node3D
var torso_mesh: Node3D
var head_pivot: Node3D
var arm_l_pivot: Node3D
var forearm_l_pivot: Node3D
var arm_r_pivot: Node3D
var forearm_r_pivot: Node3D
var leg_l_pivot: Node3D
var shin_l_pivot: Node3D
var leg_r_pivot: Node3D
var shin_r_pivot: Node3D
var backpack_mesh: Node3D
var weapon_hand_mount: Node3D
var weapon_back_mount: Node3D

var world_rifle_root: Node3D
var world_knife_root: Node3D
var world_muzzle_flash: MeshInstance3D

var is_first_person: bool = true
var stride_phase: float = 0.0
var breath_clock: float = 0.0
var cur_weapon_slot: int = -1
var flash_left: float = 0.0
var slam_anim_left: float = 0.0
var slash_anim_left: float = 0.0
var slash_anim_combo: int = 0

var base_hips_y: float = 0.92
var current_hips_y: float = 0.92
var current_hips_pitch: float = 0.0

func setup(owner_game):
	game = owner_game
	_build_hero()
	refresh_weapon_visuals()
	set_first_person(true)

func _build_hero():
	if not ResourceLoader.exists(HERO_GLB):
		push_warning("player_shaoyu.glb missing!")
		return
	var packed = load(HERO_GLB)
	if packed == null or not (packed is PackedScene):
		return
	hero_root = packed.instantiate()
	hero_root.name = "HeroModel"
	add_child(hero_root)

	hips_pivot = hero_root.find_child("hips_pivot", true, false) as Node3D
	torso_pivot = hero_root.find_child("torso_pivot", true, false) as Node3D
	torso_mesh = hero_root.find_child("torso_mesh", true, false) as Node3D
	head_pivot = hero_root.find_child("head_pivot", true, false) as Node3D
	arm_l_pivot = hero_root.find_child("arm_l_pivot", true, false) as Node3D
	forearm_l_pivot = hero_root.find_child("forearm_l_pivot", true, false) as Node3D
	arm_r_pivot = hero_root.find_child("arm_r_pivot", true, false) as Node3D
	forearm_r_pivot = hero_root.find_child("forearm_r_pivot", true, false) as Node3D
	leg_l_pivot = hero_root.find_child("leg_l_pivot", true, false) as Node3D
	shin_l_pivot = hero_root.find_child("shin_l_pivot", true, false) as Node3D
	leg_r_pivot = hero_root.find_child("leg_r_pivot", true, false) as Node3D
	shin_r_pivot = hero_root.find_child("shin_r_pivot", true, false) as Node3D
	backpack_mesh = hero_root.find_child("backpack_mesh", true, false) as Node3D
	weapon_hand_mount = hero_root.find_child("weapon_hand_mount", true, false) as Node3D
	weapon_back_mount = hero_root.find_child("weapon_back_mount", true, false) as Node3D

	if is_instance_valid(hips_pivot):
		base_hips_y = hips_pivot.position.y
		current_hips_y = base_hips_y

	for mi in hero_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m != null:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func refresh_weapon_visuals():
	if not is_instance_valid(weapon_hand_mount) or not is_instance_valid(weapon_back_mount):
		return
	if is_instance_valid(world_rifle_root):
		world_rifle_root.queue_free()
		world_rifle_root = null
	if is_instance_valid(world_knife_root):
		world_knife_root.queue_free()
		world_knife_root = null

	# World-scale YS-04 Carbine mounted on hand or back holster
	world_rifle_root = Node3D.new()
	world_rifle_root.name = "WorldRifleRoot"
	weapon_hand_mount.add_child(world_rifle_root)

	if is_instance_valid(game) and ResourceLoader.exists("res://assets/slice/rifle.glb"):
		var rifle_inst: Node3D = game._model(world_rifle_root, "res://assets/slice/rifle.glb", Vector3(0.0, -0.02, -0.14), 0.23, 0.0)
		var has_gilded: bool = "gilded_skin" in game.rules.profile.owned
		var has_skin: bool = has_gilded or ("forest_skin" in game.rules.profile.owned)
		for m in rifle_inst.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s_idx in mi.mesh.get_surface_count():
				var base_m: Material = mi.mesh.surface_get_material(s_idx)
				if base_m is BaseMaterial3D:
					var dup := (base_m as BaseMaterial3D).duplicate() as BaseMaterial3D
					var mname := String(base_m.resource_name)
					if "HandguardStock" in mname or "Magazine" in mname or "Grip" in mname:
						if has_gilded and ("HandguardStock" in mname or "Magazine" in mname):
							dup.albedo_color = Color("1f6f58")
						elif has_skin and ("HandguardStock" in mname or "Magazine" in mname):
							dup.albedo_color = Color("376c55")
					elif has_gilded:
						dup.albedo_color = Color("d8aa4c")
						dup.metallic = 0.88
						dup.roughness = 0.24
					mi.set_surface_override_material(s_idx, dup)
		# Compact suppressor visual if equipped
		if game.rules.active_muzzle() == "suppressor":
			var sup := MeshInstance3D.new()
			var scyl := CylinderMesh.new()
			scyl.top_radius = 0.018
			scyl.bottom_radius = 0.018
			scyl.height = 0.16
			sup.mesh = scyl
			sup.rotation.x = PI * 0.5
			sup.position = Vector3(0.0, 0.095, -0.52)
			var smat := StandardMaterial3D.new()
			smat.albedo_color = Color("252c32")
			smat.metallic = 0.65
			smat.roughness = 0.36
			sup.material_override = smat
			world_rifle_root.add_child(sup)
		# World muzzle flash puff for 3P shooting
		world_muzzle_flash = MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.075
		fm.height = 0.15
		world_muzzle_flash.mesh = fm
		world_muzzle_flash.position = Vector3(0.0, 0.10, -0.56)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color("ffe48a")
		fmat.emission_enabled = true
		fmat.emission = Color("ffba42")
		fmat.emission_energy_multiplier = 4.2
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		world_muzzle_flash.material_override = fmat
		world_muzzle_flash.visible = false
		world_rifle_root.add_child(world_muzzle_flash)

	# World-scale Tactical Knife
	world_knife_root = Node3D.new()
	world_knife_root.name = "WorldKnifeRoot"
	weapon_hand_mount.add_child(world_knife_root)
	var handle := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.022, 0.028, 0.115)
	handle.mesh = hbox
	handle.position = Vector3(0.0, 0.0, -0.02)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color("284c40")
	hmat.roughness = 0.72
	handle.material_override = hmat
	world_knife_root.add_child(handle)

	var blade := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.008, 0.032, 0.21)
	blade.mesh = bbox
	blade.position = Vector3(0.0, 0.004, -0.18)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("d8eef2")
	bmat.metallic = 0.88
	bmat.roughness = 0.20
	blade.material_override = bmat
	world_knife_root.add_child(blade)

	cur_weapon_slot = -1
	_sync_weapon_mount(0)
	_apply_visibility()

func _sync_weapon_mount(slot: int):
	if cur_weapon_slot == slot:
		return
	cur_weapon_slot = slot
	if not is_instance_valid(world_rifle_root) or not is_instance_valid(world_knife_root):
		return
	if slot == 0:
		if world_rifle_root.get_parent() != weapon_hand_mount:
			world_rifle_root.get_parent().remove_child(world_rifle_root)
			weapon_hand_mount.add_child(world_rifle_root)
		world_rifle_root.position = Vector3(0.0, 0.02, -0.05)
		world_rifle_root.rotation = Vector3(-1.38, 0.0, 0.0)
		world_rifle_root.scale = Vector3.ONE
		world_knife_root.visible = false
	else:
		if world_rifle_root.get_parent() != weapon_back_mount:
			world_rifle_root.get_parent().remove_child(world_rifle_root)
			weapon_back_mount.add_child(world_rifle_root)
		world_rifle_root.position = Vector3(0.0, -0.08, 0.02)
		world_rifle_root.rotation = Vector3(0.0, PI * 0.5, 0.0)
		world_rifle_root.scale = Vector3.ONE * 0.94
		world_knife_root.visible = not is_first_person
		world_knife_root.position = Vector3(0.0, -0.01, -0.02)
		world_knife_root.rotation = Vector3(-1.45, 0.0, 0.0)
	_apply_visibility()

func _apply_visibility():
	if not is_instance_valid(hero_root):
		return
	var show_upper: bool = not is_first_person
	if is_instance_valid(torso_mesh):
		torso_mesh.visible = show_upper
	if is_instance_valid(head_pivot):
		head_pivot.visible = show_upper
	if is_instance_valid(arm_l_pivot):
		arm_l_pivot.visible = show_upper
	if is_instance_valid(arm_r_pivot):
		arm_r_pivot.visible = show_upper
	if is_instance_valid(backpack_mesh):
		backpack_mesh.visible = show_upper
	if is_instance_valid(weapon_back_mount):
		weapon_back_mount.visible = show_upper
	if is_instance_valid(world_rifle_root):
		world_rifle_root.visible = show_upper
	if is_instance_valid(world_knife_root):
		world_knife_root.visible = show_upper and (cur_weapon_slot == 1)

func set_first_person(fp: bool):
	is_first_person = fp
	_apply_visibility()

func trigger_shot():
	flash_left = 0.055

func trigger_knife_slash(combo: int):
	slash_anim_left = 0.34
	slash_anim_combo = combo

func trigger_ground_slam():
	slam_anim_left = 0.52

func update_pose(
	delta: float,
	local_vel: Vector3,
	on_floor: bool,
	stance: int,
	lean_blend: float,
	pitch: float,
	aiming: bool,
	weapon_slot: int,
	recoil: float,
	reload_progress: float
):
	if not is_instance_valid(hero_root) or not is_instance_valid(hips_pivot):
		return
	_sync_weapon_mount(weapon_slot)
	breath_clock += delta
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - delta)
	if is_instance_valid(world_muzzle_flash):
		world_muzzle_flash.visible = (not is_first_person) and flash_left > 0.0 and weapon_slot == 0
	if slash_anim_left > 0.0:
		slash_anim_left = maxf(0.0, slash_anim_left - delta)
	if slam_anim_left > 0.0:
		slam_anim_left = maxf(0.0, slam_anim_left - delta)

	var horiz_speed: float = Vector2(local_vel.x, local_vel.z).length()
	var move_blend: float = clampf(horiz_speed / 4.2, 0.0, 1.45)
	var forward_sign: float = -1.0 if local_vel.z > 0.6 else 1.0
	if horiz_speed > 0.15 and on_floor:
		stride_phase += delta * clampf(horiz_speed * 2.25, 3.2, 13.5) * forward_sign
	else:
		stride_phase = lerpf(stride_phase, roundf(stride_phase / PI) * PI, minf(delta * 7.0, 1.0))

	# 1P subtle backward offset so looking straight down displays boots & legs cleanly without clipping camera!
	var target_body_z: float = 0.0
	if is_first_person:
		target_body_z = 0.26 if stance == 2 else (0.19 if stance == 1 else 0.16)
	hero_root.position.z = lerpf(hero_root.position.z, target_body_z, minf(delta * 14.0, 1.0))

	# Hips height & prone pitch
	var target_hips_y: float = base_hips_y
	var target_hips_pitch: float = 0.0
	if stance == 1:
		target_hips_y = 0.64
	elif stance == 2:
		target_hips_y = 0.22
		target_hips_pitch = -1.42  # Lies flat face-down toward -Z!

	var bob_y: float = absf(sin(stride_phase)) * 0.045 * minf(move_blend, 1.15) if (on_floor and stance != 2) else 0.0
	current_hips_y = lerpf(current_hips_y, target_hips_y + bob_y, minf(delta * 12.0, 1.0))
	current_hips_pitch = lerpf(current_hips_pitch, target_hips_pitch, minf(delta * 10.0, 1.0))
	hips_pivot.position.y = current_hips_y
	hips_pivot.rotation.x = current_hips_pitch
	hips_pivot.rotation.z = lerpf(hips_pivot.rotation.z, -lean_blend * 0.10, minf(delta * 12.0, 1.0))

	# Legs animation (Right-hand rule: +X swings leg forward -Z, -X bends shin backward +Z!)
	var leg_l_x: float = 0.0
	var leg_r_x: float = 0.0
	var shin_l_x: float = 0.0
	var shin_r_x: float = 0.0
	if stance == 2:
		# Prone belly crawl leg alternating kick
		var crawl_s: float = sin(stride_phase * 0.85) * 0.16 * minf(move_blend, 1.0)
		leg_l_x = -0.08 + crawl_s
		leg_r_x = -0.08 - crawl_s
		shin_l_x = -0.18 - maxf(0.0, crawl_s) * 1.4
		shin_r_x = -0.18 - maxf(0.0, -crawl_s) * 1.4
	elif not on_floor:
		leg_l_x = 0.42
		shin_l_x = -0.68
		leg_r_x = -0.16
		shin_r_x = -0.35
	elif stance == 1:
		# Tactical crouch stride
		var amp_c: float = 0.48 * minf(move_blend, 1.0)
		var sw_c: float = sin(stride_phase)
		leg_l_x = 0.62 + sw_c * amp_c
		leg_r_x = 0.62 - sw_c * amp_c
		shin_l_x = -1.16 - maxf(0.0, -sw_c) * 0.28 * minf(move_blend, 1.0)
		shin_r_x = -1.16 - maxf(0.0, sw_c) * 0.28 * minf(move_blend, 1.0)
	else:
		# Standing / Jog / Sprint stride
		var amp: float = 0.62 * minf(move_blend, 1.25)
		var sw: float = sin(stride_phase)
		leg_l_x = sw * amp
		leg_r_x = -sw * amp
		shin_l_x = -maxf(0.0, -sw) * 0.72 * minf(move_blend, 1.2) - 0.05
		shin_r_x = -maxf(0.0, sw) * 0.72 * minf(move_blend, 1.2) - 0.05

	var l_rate: float = minf(delta * 15.0, 1.0)
	if is_instance_valid(leg_l_pivot):
		leg_l_pivot.rotation.x = lerpf(leg_l_pivot.rotation.x, leg_l_x, l_rate)
	if is_instance_valid(shin_l_pivot):
		shin_l_pivot.rotation.x = lerpf(shin_l_pivot.rotation.x, shin_l_x, l_rate)
	if is_instance_valid(leg_r_pivot):
		leg_r_pivot.rotation.x = lerpf(leg_r_pivot.rotation.x, leg_r_x, l_rate)
	if is_instance_valid(shin_r_pivot):
		shin_r_pivot.rotation.x = lerpf(shin_r_pivot.rotation.x, shin_r_x, l_rate)

	# Upper body animation (torso, head, arms)
	if is_instance_valid(torso_pivot):
		var breath_x: float = sin(breath_clock * 2.1) * 0.014
		var t_pitch: float = -0.18 if stance == 1 else (0.58 if stance == 2 else (-0.06 * minf(move_blend, 1.0)))
		if not is_first_person and stance != 2:
			t_pitch += clampf(pitch * 0.34, -0.35, 0.35)
		if slam_anim_left > 0.0:
			var u_sl: float = clampf(1.0 - slam_anim_left / 0.52, 0.0, 1.0)
			t_pitch += sin(u_sl * PI) * (-0.52)
		torso_pivot.rotation.x = lerpf(torso_pivot.rotation.x, t_pitch + breath_x, l_rate)
		torso_pivot.rotation.z = lerpf(torso_pivot.rotation.z, -lean_blend * 0.34, l_rate)
		torso_pivot.rotation.y = lerpf(torso_pivot.rotation.y, 0.14 if (weapon_slot == 0 and aiming) else 0.06, l_rate)

	if is_instance_valid(head_pivot) and not is_first_person:
		var h_pitch: float = clampf(pitch * 0.62, -0.65, 0.65)
		if stance == 2:
			h_pitch = clampf(0.88 + pitch * 0.45, 0.45, 1.25)
		head_pivot.rotation.x = lerpf(head_pivot.rotation.x, h_pitch, l_rate)

	if not is_first_person and is_instance_valid(arm_r_pivot) and is_instance_valid(arm_l_pivot):
		var ar_x: float = 0.0
		var ar_y: float = 0.0
		var ar_z: float = 0.0
		var fr_x: float = 0.0
		var al_x: float = 0.0
		var al_y: float = 0.0
		var al_z: float = 0.0
		var fl_x: float = 0.0

		if slam_anim_left > 0.0:
			# Shaoyu [V] '天生神力' dramatic overhead raise -> heavy ground slam!
			var u_s: float = clampf(1.0 - slam_anim_left / 0.52, 0.0, 1.0)
			if u_s < 0.34:
				var p1: float = u_s / 0.34
				ar_x = lerpf(0.7, 2.55, p1)
				al_x = lerpf(0.6, 2.10, p1)
				fr_x = 0.35
				fl_x = 0.45
			else:
				var p2: float = clampf((u_s - 0.34) / 0.66, 0.0, 1.0)
				ar_x = lerpf(2.55, 0.25, p2)
				al_x = lerpf(2.10, 0.35, p2)
				fr_x = 0.22
				fl_x = 0.32
		elif weapon_slot == 0:
			# Two-handed YS-04 tactical carbine stance
			var aim_lift: float = 0.22 if aiming else 0.0
			var rec_kick: float = recoil * 0.16
			ar_x = 0.92 + aim_lift + clampf(pitch * 0.55, -0.55, 0.55) + rec_kick
			ar_y = 0.10
			ar_z = -0.06
			fr_x = 0.48 + rec_kick * 0.5
			al_x = 1.02 + aim_lift + clampf(pitch * 0.52, -0.52, 0.52) + rec_kick * 0.7
			al_y = -0.46
			al_z = 0.14
			fl_x = 0.56
			if reload_progress > 0.001:
				var rp: float = sin(reload_progress * PI)
				al_x -= rp * 0.48
				al_y += rp * 0.25
				ar_z -= rp * 0.28
		else:
			# Tactical Knife athletic combat guard + dynamic slash combo
			var sw_k: float = sin(stride_phase) * 0.32 * minf(move_blend, 1.0)
			ar_x = 0.72 - sw_k * 0.4
			fr_x = 0.85
			al_x = 0.45 + sw_k * 0.6
			fl_x = 0.65
			if slash_anim_left > 0.0:
				var u_k: float = clampf(1.0 - slash_anim_left / 0.34, 0.0, 1.0)
				var s_dir: float = -1.0 if (slash_anim_combo % 2 == 0) else 1.0
				ar_x = 1.35 + sin(u_k * PI) * 0.45
				ar_y = lerpf(-0.65 * s_dir, 0.85 * s_dir, u_k)
				fr_x = 0.35

		arm_r_pivot.rotation = arm_r_pivot.rotation.lerp(Vector3(ar_x, ar_y, ar_z), l_rate)
		if is_instance_valid(forearm_r_pivot):
			forearm_r_pivot.rotation.x = lerpf(forearm_r_pivot.rotation.x, fr_x, l_rate)
		arm_l_pivot.rotation = arm_l_pivot.rotation.lerp(Vector3(al_x, al_y, al_z), l_rate)
		if is_instance_valid(forearm_l_pivot):
			forearm_l_pivot.rotation.x = lerpf(forearm_l_pivot.rotation.x, fl_x, l_rate)
