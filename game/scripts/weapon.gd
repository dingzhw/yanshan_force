extends Node3D
## Tactical YS-04 Carbine & Held Combat Knife viewmodel (v0.8.2):
## - Rigid gun_pivot locking rifle, optics, muzzle, grips, bolt, muzzle flash & dangling 3D charm together (zero reload optic drift!)
## - Upgraded anodized gunmetal / matte carbon polymer PBR materials, reciprocating bolt carrier, brass shell ejection, star muzzle flash
## - Physically damped 2-axis swinging 3D Achievement Weapon Charm mounted beneath the forward rail!

const Achievements = preload("res://scripts/achievements.gd")

var game
var gun_pivot: Node3D
var rifle: Node3D
var rifle_meshes: Array[MeshInstance3D] = []
var attachments_root: Node3D
var att_nodes := {}
var optic_root: Node3D
var optic_housing: Node3D
var reticle_dot: MeshInstance3D
var support_grip: Node3D
var bolt_carrier: MeshInstance3D
var bolt_base_pos := Vector3(0.015, 0.162, -0.025)

# Physically swinging 3D Achievement Weapon Charm
var charm_anchor: Node3D
var charm_pendulum: Node3D
var charm_visual_root: Node3D
var equipped_charm_id := ""
var charm_angle := Vector2.ZERO
var charm_vel := Vector2.ZERO
var prev_world_yaw := 0.0
var prev_yaw_ready := false

# Brass shell casings pool
var shell_casings: Array = []
var shell_mat: StandardMaterial3D

# Skinned first-person arms nodes & knife attachment
var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_mesh: MeshInstance3D
var right_arm_rig: Node3D
var left_hand_pivot: Node3D
var left_sleeve: MeshInstance3D
var knife_mount: BoneAttachment3D
var knife_root: Node3D
var slash_arc: MeshInstance3D
var slash_arc_mat: ShaderMaterial

var flash: Node3D
var light: OmniLight3D
var magazine: Node3D
var shot_left := 0.0
var bolt_kick := 0.0
var recoil_z := 0.0
var recoil_rot_x := 0.0
var slash_left := 0.0
var slash_duration := 0.34
var slash_combo := 0
var slam_left := 0.0
const SLAM_DURATION := 0.50
var weapon_slot := 0  # 0 = YS-04 Carbine, 1 = Tactical Knife
var elapsed := 0.0
var aim_blend := 0.0

var left_hand_bone := -1
var right_index_bones: Array[int] = []
var pose_cache := {}

func _ready():
	var has_skin = "forest_skin" in game.rules.profile.owned

	# v0.8.2 V81-9: Unified rigid gun_pivot (scale 1,1,1) so rifle, optics, attachments, muzzle flash, bolt & charm
	# ALL rotate as ONE solid firearm during reload, recoil & ADS — zero optic detachment!
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	add_child(gun_pivot)

	rifle = game._model(gun_pivot, "res://assets/slice/rifle.glb", Vector3.ZERO, 0.22, 0)
	magazine = rifle.find_child("YS04_magazine", true, false)
	var has_mag2 = "magazine2" in game.rules.profile.owned
	var has_mag1 = "magazine" in game.rules.profile.owned
	if is_instance_valid(magazine):
		if has_mag2:
			magazine.scale = Vector3(1.18, 1.42, 1.15)
		elif has_mag1:
			magazine.scale.y = 1.25

	rifle_meshes.clear()
	for m in rifle.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh != null:
			for s_idx in mi.mesh.get_surface_count():
				var base_m: Material = mi.mesh.surface_get_material(s_idx)
				if base_m is BaseMaterial3D:
					var dup := (base_m as BaseMaterial3D).duplicate() as BaseMaterial3D
					var fmt_s: int = int(mi.mesh.surface_get_format(s_idx))
					if (fmt_s & Mesh.ARRAY_FORMAT_COLOR) != 0:
						dup.vertex_color_use_as_albedo = true
					var mname := String(base_m.resource_name)
					if "HandguardStock" in mname or "Magazine" in mname or "Grip" in mname:
						dup.metallic = 0.08
						dup.roughness = 0.72
						dup.metallic_specular = 0.22
						if has_skin and ("HandguardStock" in mname or "Magazine" in mname):
							dup.albedo_color = Color("376c55")
					else:
						# Machined anodized gunmetal steel receiver, barrel & Picatinny rail
						dup.metallic = 0.74
						dup.roughness = 0.30
						dup.metallic_specular = 0.55
					mi.set_surface_override_material(s_idx, dup)
		rifle_meshes.append(mi)

	# Low-profile M-LOK polymer rail cover under forend (also carries forest_skin tint!)
	support_grip = Node3D.new()
	support_grip.position = Vector3(0.0, 0.136, -0.145)
	rifle.add_child(support_grip)
	var mlok_panel := MeshInstance3D.new()
	var mlok_box := BoxMesh.new()
	mlok_box.size = Vector3(0.030, 0.006, 0.095)
	mlok_panel.mesh = mlok_box
	var mlok_mat := StandardMaterial3D.new()
	mlok_mat.albedo_color = Color("376c55") if has_skin else Color("2b3538")
	mlok_mat.roughness = 0.72
	mlok_mat.metallic = 0.08
	mlok_mat.metallic_specular = 0.18
	mlok_panel.material_override = mlok_mat
	mlok_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	support_grip.add_child(mlok_panel)
	rifle_meshes.append(mlok_panel)

	# Reciprocating brushed-steel bolt carrier visible in the right ejection port!
	bolt_carrier = MeshInstance3D.new()
	var bolt_box := BoxMesh.new()
	bolt_box.size = Vector3(0.008, 0.016, 0.046)
	bolt_carrier.mesh = bolt_box
	bolt_carrier.position = bolt_base_pos
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.albedo_color = Color("a8b2b8")
	bolt_mat.metallic = 0.90
	bolt_mat.roughness = 0.24
	bolt_carrier.material_override = bolt_mat
	bolt_carrier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun_pivot.add_child(bolt_carrier)
	rifle_meshes.append(bolt_carrier)

	# Polished 5.56mm brass casing material
	shell_mat = StandardMaterial3D.new()
	shell_mat.albedo_color = Color("d8b252")
	shell_mat.metallic = 0.92
	shell_mat.roughness = 0.22

	_build_reflex_optic()
	_build_attachments()
	_build_charm_mount()
	_setup_skinned_arms(has_skin)
	_setup_knife_attachment()
	_build_slash_arc()
	_build_muzzle_flash()

	refresh_loadout()
	set_weapon_slot(0)

func _build_muzzle_flash():
	flash = Node3D.new()
	flash.name = "MuzzleFlashRig"
	flash.position = Vector3(0, 0.158, -0.37)
	gun_pivot.add_child(flash)

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.96, 0.78, 0.96)
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var fin_mat := StandardMaterial3D.new()
	fin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fin_mat.albedo_color = Color(1.0, 0.76, 0.34, 0.88)
	fin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.018
	sph.height = 0.088
	core.mesh = sph
	core.rotation.x = PI * 0.5
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(core)

	for rot_z in [0.0, PI * 0.333, PI * 0.666]:
		var fin := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(0.095, 0.012, 0.032)
		fin.mesh = q
		fin.rotation.z = rot_z
		fin.position = Vector3(0.0, 0.0, -0.018)
		fin.material_override = fin_mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.add_child(fin)
	flash.hide()

	light = OmniLight3D.new()
	light.position = flash.position
	light.omni_range = 3.8
	light.light_color = Color("ffd28a")
	light.light_energy = 0.0
	gun_pivot.add_child(light)

func _build_attachments():
	attachments_root = Node3D.new()
	attachments_root.name = "AttachmentsRoot"
	gun_pivot.add_child(attachments_root)
	var path := "res://assets/slice/rifle_attachments.glb"
	if not ResourceLoader.exists(path):
		return
	if not game.scene_cache.has(path):
		game.scene_cache[path] = load(path)
	var inst: Node3D = game.scene_cache[path].instantiate()
	attachments_root.add_child(inst)
	for key in ["att_scope_2x", "att_suppressor", "att_compensator", "att_angled_grip"]:
		var node = inst.find_child(key, true, false)
		if is_instance_valid(node):
			for mi in ([node] + node.find_children("*", "MeshInstance3D", true, false)):
				if mi is MeshInstance3D:
					var mesh_i := mi as MeshInstance3D
					mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if mesh_i.mesh != null:
						for s_idx in mesh_i.mesh.get_surface_count():
							var smat: Material = mesh_i.mesh.surface_get_material(s_idx)
							if smat != null and smat.resource_name.begins_with("Mat_OpticGlass"):
								var glass_ov := StandardMaterial3D.new()
								glass_ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
								glass_ov.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
								glass_ov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
								glass_ov.albedo_color = Color(0.10, 0.34, 0.30, 0.05)
								mesh_i.set_surface_override_material(s_idx, glass_ov)
							elif smat is BaseMaterial3D:
								var mdup := (smat as BaseMaterial3D).duplicate() as BaseMaterial3D
								mdup.metallic = maxf(mdup.metallic, 0.65)
								mdup.roughness = minf(mdup.roughness, 0.34)
								mesh_i.set_surface_override_material(s_idx, mdup)
			node.hide()
			att_nodes[key] = node

func _build_charm_mount():
	# v0.8.4 Left-flank exterior Picatinny side-rail outrigger lug & sling ring:
	# Mounted on the camera-facing left side of the upper receiver (clear of the left hand & optic sightline)
	# so all 13 achievement charms dangle prominently in hip-fire, combat, sprint, reload & ADS!
	charm_anchor = Node3D.new()
	charm_anchor.name = "WeaponCharmAnchor"
	charm_anchor.position = Vector3(-0.030, 0.184, -0.068)
	gun_pivot.add_child(charm_anchor)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("323b40")
	ring_mat.metallic = 0.88
	ring_mat.roughness = 0.24

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color("d4ad5a")
	brass_mat.metallic = 0.90
	brass_mat.roughness = 0.22

	# Rail clamp block bolted to receiver left flank + outward cantilever arm
	var clamp_blk := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.010, 0.014, 0.026)
	clamp_blk.mesh = cb
	clamp_blk.position = Vector3(-0.003, 0.0, 0.0)
	clamp_blk.material_override = ring_mat
	clamp_blk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	charm_anchor.add_child(clamp_blk)

	var outrigger := MeshInstance3D.new()
	var ob := BoxMesh.new()
	ob.size = Vector3(0.024, 0.007, 0.010)
	outrigger.mesh = ob
	outrigger.position = Vector3(-0.016, -0.001, 0.0)
	outrigger.material_override = brass_mat
	outrigger.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	charm_anchor.add_child(outrigger)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.0052
	torus.outer_radius = 0.0084
	torus.rings = 14
	torus.ring_segments = 8
	ring.mesh = torus
	ring.position = Vector3(-0.028, -0.006, 0.0)
	ring.rotation.x = PI * 0.5
	ring.material_override = brass_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	charm_anchor.add_child(ring)

	charm_pendulum = Node3D.new()
	charm_pendulum.name = "WeaponCharmPendulum"
	charm_pendulum.position = Vector3(-0.028, -0.010, 0.0)
	charm_anchor.add_child(charm_pendulum)

	charm_visual_root = Node3D.new()
	charm_visual_root.name = "WeaponCharmVisual"
	charm_visual_root.scale = Vector3.ONE * 1.45
	charm_pendulum.add_child(charm_visual_root)
	charm_anchor.hide()

func _rebuild_charm_mesh(charm_id: String):
	equipped_charm_id = charm_id
	if not is_instance_valid(charm_visual_root):
		return
	for ch in charm_visual_root.get_children():
		ch.queue_free()
	if charm_id == "" or not Achievements.CHARMS.has(charm_id):
		if is_instance_valid(charm_anchor):
			charm_anchor.hide()
		return
	var spec: Dictionary = Achievements.CHARMS[charm_id]
	var is_glowing: bool = str(spec.shape) in ["sonar", "star", "crosshair"]
	var main_mat := StandardMaterial3D.new()
	main_mat.albedo_color = spec.color
	main_mat.metallic = 0.80
	main_mat.roughness = 0.22
	main_mat.metallic_specular = 0.65
	main_mat.emission_enabled = true
	main_mat.emission = spec.color
	main_mat.emission_energy_multiplier = 0.55 if is_glowing else 0.26
	var acc_mat := StandardMaterial3D.new()
	acc_mat.albedo_color = spec.accent
	acc_mat.metallic = 0.72
	acc_mat.roughness = 0.26
	acc_mat.emission_enabled = true
	acc_mat.emission = spec.color if is_glowing else spec.accent
	acc_mat.emission_energy_multiplier = 1.05 if is_glowing else 0.20

	# Delicate hanging chain link connecting ring to charm body
	var link := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.0016
	lc.bottom_radius = 0.0016
	lc.height = 0.015
	link.mesh = lc
	link.position = Vector3(0.0, -0.0075, 0.0)
	link.material_override = acc_mat
	link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	charm_visual_root.add_child(link)

	var shape := str(spec.shape)
	var body := Node3D.new()
	body.position = Vector3(0.0, -0.026, 0.0)
	# Gently cant charm face toward the first-person camera on the left flank!
	body.rotation.y = 0.28
	charm_visual_root.add_child(body)

	match shape:
		"acorn", "crown":
			var nut := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.011
			sp.height = 0.025
			nut.mesh = sp
			nut.material_override = main_mat
			nut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(nut)
			var cap := MeshInstance3D.new()
			var cp := CylinderMesh.new()
			cp.top_radius = 0.013
			cp.bottom_radius = 0.011
			cp.height = 0.009
			cap.mesh = cp
			cap.position = Vector3(0, 0.009, 0)
			cap.material_override = acc_mat
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(cap)
		"roast", "tusk":
			var medallion := MeshInstance3D.new()
			var mc := CylinderMesh.new()
			mc.top_radius = 0.014
			mc.bottom_radius = 0.014
			mc.height = 0.005
			medallion.mesh = mc
			medallion.rotation.z = PI * 0.5
			medallion.material_override = main_mat
			medallion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(medallion)
			for side in [-1.0, 1.0]:
				var rib := MeshInstance3D.new()
				var rb := BoxMesh.new()
				rb.size = Vector3(0.007, 0.018, 0.004)
				rib.mesh = rb
				rib.position = Vector3(0.0, 0.0, side * 0.008)
				rib.rotation.x = side * 0.35
				rib.material_override = acc_mat
				rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				body.add_child(rib)
		"bell":
			var bell := MeshInstance3D.new()
			var bc := SphereMesh.new()
			bc.radius = 0.012
			bc.height = 0.024
			bell.mesh = bc
			bell.material_override = main_mat
			bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(bell)
			var band := MeshInstance3D.new()
			var bt := TorusMesh.new()
			bt.inner_radius = 0.010
			bt.outer_radius = 0.0135
			band.mesh = bt
			band.material_override = acc_mat
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(band)
		"koi", "feather", "blade":
			var fin := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(0.004, 0.032, 0.012)
			fin.mesh = fb
			fin.material_override = main_mat
			fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(fin)
			var guard := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(0.007, 0.005, 0.020)
			guard.mesh = gb
			guard.position = Vector3(0.0, 0.010, 0.0)
			guard.material_override = acc_mat
			guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(guard)
		"crosshair", "sonar":
			var ring_m := MeshInstance3D.new()
			var rt := TorusMesh.new()
			rt.inner_radius = 0.009
			rt.outer_radius = 0.014
			ring_m.mesh = rt
			ring_m.rotation.z = PI * 0.5
			ring_m.material_override = main_mat
			ring_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(ring_m)
			var core_m := MeshInstance3D.new()
			var cs := SphereMesh.new()
			cs.radius = 0.006
			cs.height = 0.012
			core_m.mesh = cs
			core_m.material_override = acc_mat
			core_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(core_m)
		_:
			# Tactical dogtag / iron crown / mythic star
			var plate := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.004, 0.026, 0.018)
			plate.mesh = pb
			plate.material_override = main_mat
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(plate)
			var emblem := MeshInstance3D.new()
			var eb := BoxMesh.new()
			eb.size = Vector3(0.006, 0.012, 0.012)
			emblem.mesh = eb
			emblem.rotation.x = PI * 0.25
			emblem.material_override = acc_mat
			emblem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(emblem)

	if is_instance_valid(charm_anchor):
		charm_anchor.visible = weapon_slot == 0

func _setup_knife_attachment():
	if not is_instance_valid(arms_skeleton):
		return
	var r_hand_idx := arms_skeleton.find_bone("hand.R")
	if r_hand_idx < 0:
		return
	knife_mount = BoneAttachment3D.new()
	knife_mount.name = "RightHandKnifeMount"
	knife_mount.bone_name = "hand.R"
	arms_skeleton.add_child(knife_mount)
	var path := "res://assets/slice/tactical_knife.glb"
	if ResourceLoader.exists(path):
		if not game.scene_cache.has(path):
			game.scene_cache[path] = load(path)
		knife_root = game.scene_cache[path].instantiate()
		knife_mount.add_child(knife_root)
		for m in knife_root.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 1.5
			if mi.mesh != null:
				for s_idx in mi.mesh.get_surface_count():
					var km: Material = mi.mesh.surface_get_material(s_idx)
					if km is BaseMaterial3D:
						var kdup := (km as BaseMaterial3D).duplicate() as BaseMaterial3D
						if (int(mi.mesh.surface_get_format(s_idx)) & Mesh.ARRAY_FORMAT_COLOR) != 0:
							kdup.vertex_color_use_as_albedo = true
						kdup.metallic_specular = 0.28
						mi.set_surface_override_material(s_idx, kdup)
		knife_root.hide()

func refresh_loadout():
	var optic_id: String = game.rules.active_optic()
	var muzzle_id: String = game.rules.active_muzzle()
	var grip_id: String = game.rules.active_grip()

	if att_nodes.has("att_scope_2x"):
		att_nodes["att_scope_2x"].visible = optic_id == "scope_2x"
	if att_nodes.has("att_suppressor"):
		att_nodes["att_suppressor"].visible = muzzle_id == "suppressor"
	if att_nodes.has("att_compensator"):
		att_nodes["att_compensator"].visible = muzzle_id == "compensator"
	if att_nodes.has("att_angled_grip"):
		att_nodes["att_angled_grip"].visible = grip_id == "angled_grip"

	if is_instance_valid(optic_housing):
		optic_housing.visible = optic_id != "scope_2x"
	if is_instance_valid(reticle_dot):
		var col := Color("4effc4") if optic_id == "scope_2x" else (Color("5cffd6") if optic_id == "red_dot" else Color("ff5964"))
		reticle_dot.material_override = game._material(col, true)
	if is_instance_valid(flash):
		if muzzle_id == "suppressor":
			flash.position = Vector3(0, 0.158, -0.505)
			flash.scale = Vector3(0.32, 0.38, 0.32)
		elif muzzle_id == "compensator":
			flash.position = Vector3(0, 0.158, -0.415)
			flash.scale = Vector3(0.72, 0.72, 0.72)
		else:
			flash.position = Vector3(0, 0.158, -0.37)
			flash.scale = Vector3.ONE
		if is_instance_valid(light):
			light.position = flash.position

	var desired_charm := str(game.rules.profile.get("equipped_charm", ""))
	if desired_charm != equipped_charm_id:
		_rebuild_charm_mesh(desired_charm)
	if is_instance_valid(charm_anchor):
		charm_anchor.visible = weapon_slot == 0 and equipped_charm_id != ""

func set_weapon_slot(slot: int):
	weapon_slot = clampi(slot, 0, 1)
	var is_rifle := weapon_slot == 0
	for mi in rifle_meshes:
		if is_instance_valid(mi):
			mi.visible = is_rifle
	if is_instance_valid(optic_root):
		optic_root.visible = is_rifle
	if is_instance_valid(attachments_root):
		attachments_root.visible = is_rifle
	if is_instance_valid(charm_anchor):
		charm_anchor.visible = is_rifle and equipped_charm_id != ""
	if is_instance_valid(knife_root):
		knife_root.visible = not is_rifle
	if is_instance_valid(slash_arc) and is_rifle:
		slash_arc.hide()
	if not is_rifle:
		shot_left = 0.0
		if is_instance_valid(flash):
			flash.hide()
		if is_instance_valid(light):
			light.light_energy = 0.0
	_apply_arm_pose(aim_blend if is_rifle else 0.0, 0.0, 0.0)

func trigger_knife_slash(combo_idx: int = 0):
	slash_combo = combo_idx % 2
	slash_left = slash_duration

func trigger_ground_slam():
	slam_left = SLAM_DURATION
	charm_vel.y += 14.0
	charm_vel.x += 4.5

func _setup_skinned_arms(has_skin: bool):
	var path := "res://assets/slice/fp_arms.glb"
	if not game.scene_cache.has(path):
		game.scene_cache[path] = load(path)
	arms_root = game.scene_cache[path].instantiate()
	rifle.add_child(arms_root)

	var skels = arms_root.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		arms_skeleton = skels[0] as Skeleton3D
		left_hand_bone = arms_skeleton.find_bone("hand.L")
		right_index_bones.clear()
		for bname in ["index_01.R", "index_02.R", "index_03.R"]:
			var bi := arms_skeleton.find_bone(bname)
			if bi >= 0:
				right_index_bones.append(bi)

	var meshes = arms_root.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.5
		if arms_mesh == null:
			arms_mesh = mi

	if is_instance_valid(arms_mesh) and arms_mesh.mesh != null and has_skin:
		for surf_idx in arms_mesh.mesh.get_surface_count():
			var base_mat: Material = arms_mesh.mesh.surface_get_material(surf_idx)
			if base_mat is BaseMaterial3D:
				var bm := base_mat as BaseMaterial3D
				var mname: String = bm.resource_name
				if mname.begins_with("Mat_Sleeve"):
					var dup := bm.duplicate() as BaseMaterial3D
					dup.albedo_texture = load("res://assets/slice/arm_sleeve_forest.jpg")
					arms_mesh.set_surface_override_material(surf_idx, dup)

	pose_cache.clear()
	var anim_players = arms_root.find_children("*", "AnimationPlayer", true, false)
	if anim_players.size() > 0 and is_instance_valid(arms_skeleton):
		var ap := anim_players[0] as AnimationPlayer
		ap.stop()
		for anim_name in ap.get_animation_list():
			var anim := ap.get_animation(anim_name)
			if anim == null:
				continue
			var bone_map := {}
			for t in anim.get_track_count():
				var tpath := anim.track_get_path(t)
				if tpath.get_subname_count() == 0:
					continue
				var bname := String(tpath.get_concatenated_subnames())
				var bidx := arms_skeleton.find_bone(bname)
				if bidx < 0:
					continue
				if not bone_map.has(bidx):
					bone_map[bidx] = {
						"pos": arms_skeleton.get_bone_rest(bidx).origin,
						"rot": arms_skeleton.get_bone_rest(bidx).basis.get_rotation_quaternion(),
					}
				var ttype := anim.track_get_type(t)
				if ttype == Animation.TYPE_POSITION_3D:
					bone_map[bidx]["pos"] = anim.position_track_interpolate(t, 0.0)
				elif ttype == Animation.TYPE_ROTATION_3D:
					bone_map[bidx]["rot"] = anim.rotation_track_interpolate(t, 0.0)
			pose_cache[String(anim_name)] = bone_map

	right_arm_rig = arms_root
	left_sleeve = arms_mesh
	left_hand_pivot = Node3D.new()
	add_child(left_hand_pivot)
	_apply_arm_pose(0.0, 0.0, 0.0)

func _blend_bone_maps(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w <= 0.0001 or b.is_empty():
		return a
	if w >= 0.9999 or a.is_empty():
		return b
	var out := {}
	for bidx in a.keys():
		var pa: Dictionary = a[bidx]
		if b.has(bidx):
			var pb: Dictionary = b[bidx]
			out[bidx] = {
				"pos": (pa["pos"] as Vector3).lerp(pb["pos"] as Vector3, w),
				"rot": (pa["rot"] as Quaternion).slerp(pb["rot"] as Quaternion, w),
			}
		else:
			out[bidx] = pa
	return out

func _apply_arm_pose(ads_w: float, dip: float, fire_w: float):
	if not is_instance_valid(arms_skeleton) or not pose_cache.has("pose_hip"):
		return
	var final_map: Dictionary
	if weapon_slot == 1 and pose_cache.has("pose_knife_idle"):
		var k_idle: Dictionary = pose_cache["pose_knife_idle"]
		final_map = k_idle
		if slash_left > 0.001:
			var t := clampf(1.0 - (slash_left / slash_duration), 0.0, 1.0)
			var w_name := "pose_knife_windup_a" if slash_combo == 0 else "pose_knife_windup_b"
			var s_name := "pose_knife_slash_a" if slash_combo == 0 else "pose_knife_slash_b"
			var k_wind: Dictionary = pose_cache.get(w_name, k_idle)
			var k_slash: Dictionary = pose_cache.get(s_name, k_idle)
			if t < 0.18:
				final_map = _blend_bone_maps(k_idle, k_wind, smoothstep(0.0, 0.18, t))
			elif t < 0.52:
				var u := clampf((t - 0.18) / 0.34, 0.0, 1.0)
				var snap := 1.0 - pow(1.0 - u, 2.6)
				final_map = _blend_bone_maps(k_wind, k_slash, snap)
			else:
				final_map = _blend_bone_maps(k_slash, k_idle, smoothstep(0.52, 1.0, t))
	else:
		var hip_map: Dictionary = pose_cache["pose_hip"]
		var ads_map: Dictionary = pose_cache.get("pose_ads", hip_map)
		var base_map := _blend_bone_maps(hip_map, ads_map, ads_w)

		final_map = base_map
		if dip > 0.002 and pose_cache.has("pose_reload_reach") and pose_cache.has("pose_reload_pull"):
			var reach_map: Dictionary = pose_cache["pose_reload_reach"]
			var pull_map: Dictionary = pose_cache["pose_reload_pull"]
			if dip < 0.28:
				final_map = _blend_bone_maps(base_map, reach_map, smoothstep(0.0, 0.28, dip))
			else:
				final_map = _blend_bone_maps(reach_map, pull_map, smoothstep(0.28, 1.0, dip))

	for bidx in final_map.keys():
		var entry: Dictionary = final_map[bidx]
		arms_skeleton.set_bone_pose_position(bidx, entry["pos"])
		arms_skeleton.set_bone_pose_rotation(bidx, entry["rot"])

	if weapon_slot == 0 and fire_w > 0.001 and pose_cache.has("pose_fire"):
		var fire_map: Dictionary = pose_cache["pose_fire"]
		for bidx in right_index_bones:
			if final_map.has(bidx) and fire_map.has(bidx):
				var r0: Quaternion = final_map[bidx]["rot"]
				var r1: Quaternion = fire_map[bidx]["rot"]
				arms_skeleton.set_bone_pose_rotation(bidx, r0.slerp(r1, fire_w))

	if left_hand_bone >= 0 and is_instance_valid(left_hand_pivot):
		var hand_in_skel := arms_skeleton.get_bone_global_pose(left_hand_bone).origin
		left_hand_pivot.position = gun_pivot.transform * (rifle.transform * (arms_skeleton.transform * hand_in_skel))

func _build_reflex_optic():
	# Parented directly under gun_pivot -> rigidly locked to Picatinny rail during reload & recoil!
	optic_root = Node3D.new()
	optic_root.name = "ReflexOpticRoot"
	optic_root.position = Vector3(0.0, 0.212, 0.03)
	gun_pivot.add_child(optic_root)
	optic_housing = Node3D.new()
	optic_root.add_child(optic_housing)

	var upgraded = "red_dot" in game.rules.profile.owned
	var frame_color = Color("233833") if upgraded else Color("1d2328")
	var frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = frame_color
	frame_mat.metallic = 0.78
	frame_mat.roughness = 0.28

	var base = game._mesh_box(optic_housing, Vector3(0, 0.0, 0), Vector3(0.036, 0.012, 0.075), frame_color)
	base.material_override = frame_mat
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side_x in [-0.019, 0.019]:
		var wall = game._mesh_box(optic_housing, Vector3(side_x, 0.022, 0), Vector3(0.004, 0.034, 0.056), frame_color)
		wall.material_override = frame_mat
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top_hood = game._mesh_box(optic_housing, Vector3(0, 0.039, 0), Vector3(0.042, 0.004, 0.056), frame_color)
	top_hood.material_override = frame_mat
	top_hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var glass = MeshInstance3D.new()
	var quad = BoxMesh.new()
	quad.size = Vector3(0.034, 0.030, 0.002)
	glass.mesh = quad
	glass.position = Vector3(0, 0.022, -0.01)
	var glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.28, 0.86, 0.80, 0.10)
	glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.material_override = glass_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	optic_housing.add_child(glass)

	reticle_dot = MeshInstance3D.new()
	var dot_mesh = SphereMesh.new()
	dot_mesh.radius = 0.0024 if upgraded else 0.0030
	dot_mesh.height = dot_mesh.radius * 2.0
	reticle_dot.mesh = dot_mesh
	reticle_dot.position = Vector3(0, 0.022, -0.011)
	reticle_dot.material_override = game._material(Color("5cffd6") if upgraded else Color("ff5964"), true)
	reticle_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	optic_root.add_child(reticle_dot)

func _build_slash_arc():
	slash_arc = MeshInstance3D.new()
	slash_arc.position = Vector3.ZERO
	var segs := 24
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var p0 := Vector3(0.28, 0.27, -0.15)
	var p1 := Vector3(-0.01, 0.15, -0.31)
	var p2 := Vector3(-0.35, -0.02, -0.16)
	var cam_eye := Vector3(0.0, 0.145, 0.35)
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var omt := 1.0 - u
		var p_out := omt * omt * p0 + 2.0 * omt * u * p1 + u * u * p2
		var tang := (2.0 * omt * (p1 - p0) + 2.0 * u * (p2 - p1)).normalized()
		var view_ray := (p_out - cam_eye).normalized()
		var inward := tang.cross(view_ray).normalized()
		var w_rib := 0.086 * pow(sin(u * PI), 0.82) + 0.006
		var p_in := p_out + inward * w_rib + Vector3(0.0, -0.01, 0.032) * sin(u * PI)
		verts.append(p_in)
		verts.append(p_out)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if i < segs:
			var b := i * 2
			indices.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	slash_arc.mesh = am
	slash_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float sweep_head = 0.0;
uniform float opacity = 0.0;
void fragment() {
	float wake = smoothstep(sweep_head - 0.68, sweep_head, UV.x) * (1.0 - smoothstep(sweep_head, sweep_head + 0.045, UV.x));
	float outer_rim = pow(UV.y, 1.15);
	float edge_gleam = smoothstep(0.76, 1.0, UV.y);
	float tip_flash = smoothstep(sweep_head - 0.28, sweep_head, UV.x);
	vec3 ink_jade = vec3(0.14, 0.58, 0.52);
	vec3 celadon = vec3(0.48, 0.96, 0.82);
	vec3 gold = vec3(1.00, 0.93, 0.60);
	vec3 col = mix(ink_jade, celadon, outer_rim);
	col = mix(col, gold, clamp(edge_gleam * 0.65 + outer_rim * tip_flash * 0.82, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = wake * (0.18 + 0.78 * outer_rim) * opacity;
}
"""
	slash_arc_mat = ShaderMaterial.new()
	slash_arc_mat.shader = sh
	am.surface_set_material(0, slash_arc_mat)
	slash_arc.hide()
	add_child(slash_arc)

func _eject_brass_shell():
	if DisplayServer.get_name() == "headless":
		return
	var casing := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0032
	cm.bottom_radius = 0.0038
	cm.height = 0.019
	cm.radial_segments = 6
	casing.mesh = cm
	casing.material_override = shell_mat
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	casing.position = Vector3(0.026, 0.168, -0.025)
	casing.rotation = Vector3(0.3, 0.2, 1.2)
	add_child(casing)
	shell_casings.append({
		"node": casing,
		"vel": Vector3(randf_range(0.62, 0.96), randf_range(0.42, 0.72), randf_range(0.16, 0.36)),
		"spin": Vector3(randf_range(16.0, 26.0), randf_range(-18.0, 18.0), randf_range(18.0, 32.0)),
		"left": 0.44,
	})

func shot():
	shot_left = 0.055
	bolt_kick = 1.0
	var comp_mult := 0.68 if game.rules.active_muzzle() == "compensator" else 1.0
	recoil_z = minf(0.042, recoil_z + 0.026 * comp_mult)
	recoil_rot_x = minf(0.11, recoil_rot_x + 0.052 * comp_mult)
	charm_vel.x += randf_range(-3.2, 3.2)
	charm_vel.y += 8.8 * comp_mult
	if is_instance_valid(flash):
		flash.rotation.z = randf_range(0.0, TAU)
	_eject_brass_shell()

func _update_shells(delta: float):
	for i in range(shell_casings.size() - 1, -1, -1):
		var sc: Dictionary = shell_casings[i]
		sc.left -= delta
		var nd: MeshInstance3D = sc.node
		if sc.left <= 0.0 or not is_instance_valid(nd):
			if is_instance_valid(nd):
				nd.queue_free()
			shell_casings.remove_at(i)
			continue
		sc.vel.y -= 4.8 * delta
		nd.position += sc.vel * delta
		nd.rotation += sc.spin * delta

func _update_charm_physics(delta: float, moving: float, reload_dip: float):
	if not is_instance_valid(charm_pendulum) or not is_instance_valid(charm_anchor) or not charm_anchor.visible:
		return
	var cur_yaw := global_rotation.y if is_inside_tree() else 0.0
	var yaw_vel := 0.0
	if prev_yaw_ready and delta > 0.0001:
		yaw_vel = clampf(wrapf(cur_yaw - prev_world_yaw, -PI, PI) / delta, -12.0, 12.0)
	prev_world_yaw = cur_yaw
	prev_yaw_ready = true

	# Spring-damper 2-axis pendulum responding to turning inertia, footstep bob, recoil & reload roll!
	# Clamp inward Z-swing (+0.16 max) so exterior left-side charm NEVER clips into receiver body!
	var stiffness := 34.0
	var damping := 5.8
	var target_x := clampf(-0.08 - reload_dip * 0.36 + yaw_vel * 0.060, -0.78, 0.14)
	var target_y := clampf(sin(elapsed * 7.5) * moving * 0.045, -0.35, 0.35)
	charm_vel.x += ((target_x - charm_angle.x) * stiffness - charm_vel.x * damping) * delta
	charm_vel.y += ((target_y - charm_angle.y) * stiffness - charm_vel.y * damping) * delta
	charm_angle.x = clampf(charm_angle.x + charm_vel.x * delta, -0.88, 0.16)
	charm_angle.y = clampf(charm_angle.y + charm_vel.y * delta, -0.74, 0.74)
	charm_pendulum.rotation = Vector3(charm_angle.y, 0.0, charm_angle.x)

func animate(delta: float, reload_progress: float, moving: float, aimed: bool):
	elapsed += delta
	shot_left = maxf(0, shot_left - delta)
	bolt_kick = maxf(0.0, bolt_kick - delta * 14.0)
	recoil_z = lerpf(recoil_z, 0.0, minf(delta * 20.0, 1.0))
	recoil_rot_x = lerpf(recoil_rot_x, 0.0, minf(delta * 18.0, 1.0))
	slash_left = maxf(0, slash_left - delta)
	slam_left = maxf(0.0, slam_left - delta)
	_update_shells(delta)

	var firing := shot_left > 0 and weapon_slot == 0
	if is_instance_valid(flash):
		flash.visible = firing
	var muzzle_id: String = game.rules.active_muzzle()
	if is_instance_valid(light):
		light.light_energy = (0.45 if muzzle_id == "suppressor" else 1.85) if firing else 0.0
	aim_blend = move_toward(aim_blend, 1.0 if (aimed and weapon_slot == 0) else 0.0, delta * 10.0)

	if weapon_slot == 0:
		# reload_progress runs 1.0 -> 0.0 over RELOAD_SECONDS; u runs 0.0 -> 1.0 forward in time!
		var reloading := reload_progress > 0.001
		var u := (1.0 - reload_progress) if reloading else 0.0
		var dip := sin(reload_progress * PI)
		var bolt_slap := 0.0
		if reloading and u > 0.74:
			bolt_slap = sin(clampf((u - 0.74) / 0.24, 0.0, 1.0) * PI)

		# Rotate ENTIRE gun_pivot rigidly (rifle + optics + attachments + flash + charm move as 1 solid unit!)
		gun_pivot.rotation = Vector3(recoil_rot_x + dip * 0.075 - bolt_slap * 0.035, dip * 0.045, dip * -0.25)
		gun_pivot.position = Vector3(0.0, -bolt_slap * 0.006, recoil_z)

		# Reciprocating bolt carrier kicks backward on shot & cycles cleanly on final bolt-release phase!
		if is_instance_valid(bolt_carrier):
			var b_travel := maxf(bolt_kick, bolt_slap) * 0.038
			bolt_carrier.position = bolt_base_pos + Vector3(0.0, 0.0, b_travel)

		# Realistic 3-phase magazine detach / swap / crisp seat
		if is_instance_valid(magazine):
			var mag_out := 0.0
			if reloading:
				if u < 0.30:
					mag_out = smoothstep(0.0, 0.30, u)
				elif u < 0.56:
					mag_out = 1.0
				elif u < 0.74:
					mag_out = 1.0 - smoothstep(0.56, 0.74, u)
				else:
					mag_out = 0.0
			magazine.position = Vector3(0.0, -mag_out * 0.17, mag_out * 0.065)
			magazine.rotation.x = -mag_out * 0.15

		var fire_w := clampf(shot_left / 0.055, 0.0, 1.0)
		_apply_arm_pose(aim_blend, dip, fire_w)
		_update_charm_physics(delta, moving, dip)

		# Subtle organic breathing sway + movement figure-8 bob (damped when ADS)
		var breath_x := sin(elapsed * 1.45) * (0.00035 if aimed else 0.0011)
		var breath_y := cos(elapsed * 2.15) * (0.00035 if aimed else 0.0012)
		position.x = sin(elapsed * 7.5) * moving * (0.0006 if aimed else 0.0036) + breath_x
		position.y = absf(sin(elapsed * 7.5)) * moving * (0.0005 if aimed else 0.0026) + breath_y
		position.z = 0.0
		rotation = rotation.lerp(Vector3.ZERO, minf(delta * 18.0, 1.0))
	else:
		gun_pivot.rotation = Vector3.ZERO
		gun_pivot.position = Vector3.ZERO
		_apply_arm_pose(0.0, 0.0, 0.0)
		var raw_t := clampf(1.0 - (slash_left / slash_duration), 0.0, 1.0) if slash_left > 0.0 else 0.0
		var cleave_env := sin(clampf((raw_t - 0.12) / 0.56, 0.0, 1.0) * PI) if slash_left > 0.0 else 0.0
		var dir_sign := -1.0 if slash_combo == 0 else 1.0
		position.x = sin(elapsed * 8.2) * moving * 0.0040 + dir_sign * cleave_env * 0.016
		position.y = absf(sin(elapsed * 8.2)) * moving * 0.0032 - cleave_env * 0.008
		position.z = -cleave_env * 0.015
		rotation = Vector3(-cleave_env * 0.032, dir_sign * cleave_env * 0.048, -dir_sign * cleave_env * 0.036)

		if is_instance_valid(slash_arc):
			if slash_left > 0.0 and raw_t >= 0.14 and raw_t <= 0.64:
				var arc_u := clampf((raw_t - 0.14) / 0.38, 0.0, 1.04)
				var arc_alpha := sin(clampf((raw_t - 0.14) / 0.50, 0.0, 1.0) * PI)
				slash_arc.scale.x = 1.0 if slash_combo == 0 else -1.0
				slash_arc.rotation.z = 0.0
				slash_arc_mat.set_shader_parameter("sweep_head", arc_u)
				slash_arc_mat.set_shader_parameter("opacity", arc_alpha * 0.92)
				slash_arc.show()
			else:
				slash_arc.hide()

	if slam_left > 0.0:
		# Compact downward seismic punch impulse keeping shoulder joints strictly behind camera lens!
		var st := clampf(1.0 - (slam_left / SLAM_DURATION), 0.0, 1.0)
		var slam_y := 0.0
		var slam_z := 0.0
		var slam_rx := 0.0
		var slam_rz := 0.0
		if st < 0.22:
			var u1 := smoothstep(0.0, 0.22, st)
			slam_y = 0.028 * u1
			slam_z = 0.018 * u1
			slam_rx = 0.11 * u1
			slam_rz = 0.08 * u1
		elif st < 0.54:
			var u2 := clampf((st - 0.22) / 0.32, 0.0, 1.0)
			var punch := 1.0 - pow(1.0 - u2, 2.5)
			slam_y = lerpf(0.028, -0.072, punch)
			slam_z = lerpf(0.018, 0.032, punch)
			slam_rx = lerpf(0.11, -0.22, punch)
			slam_rz = lerpf(0.08, -0.09, punch)
		else:
			var u3 := smoothstep(0.54, 1.0, st)
			slam_y = lerpf(-0.072, 0.0, u3)
			slam_z = lerpf(0.032, 0.0, u3)
			slam_rx = lerpf(-0.22, 0.0, u3)
			slam_rz = lerpf(-0.09, 0.0, u3)
		position += Vector3(0.0, slam_y, slam_z)
		rotation += Vector3(slam_rx, 0.0, slam_rz)
