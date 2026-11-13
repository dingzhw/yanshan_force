extends Node3D
## Tactical YS-04 Carbine & Held Combat Knife viewmodel with Blender CC0 arms (fp_arms.glb) and Gunsmith 2.0 attachments.

var game
var rifle: Node3D
var rifle_meshes: Array[MeshInstance3D] = []
var attachments_root: Node3D
var att_nodes := {}
var optic_root: Node3D
var optic_housing: Node3D
var reticle_dot: MeshInstance3D
var support_grip: Node3D

# Skinned first-person arms nodes & knife attachment
var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_mesh: MeshInstance3D
var right_arm_rig: Node3D
var left_hand_pivot: Node3D
var left_sleeve: MeshInstance3D
var knife_mount: BoneAttachment3D
var knife_root: Node3D

var flash: MeshInstance3D
var light: OmniLight3D
var magazine: Node3D
var shot_left := 0.0
var slash_left := 0.0
var slash_duration := 0.34
var slash_combo := 0
var weapon_slot := 0  # 0 = YS-04 Carbine, 1 = Tactical Knife
var elapsed := 0.0
var aim_blend := 0.0

var left_hand_bone := -1
var right_index_bones: Array[int] = []
var pose_cache := {}

func _ready():
	var has_skin = "forest_skin" in game.rules.profile.owned

	rifle = game._model(self, "res://assets/slice/rifle.glb", Vector3.ZERO, 0.22, 0)
	magazine = rifle.find_child("YS04_magazine", true, false)
	var has_mag2 = "magazine2" in game.rules.profile.owned
	var has_mag1 = "magazine" in game.rules.profile.owned
	if is_instance_valid(magazine):
		if has_mag2:
			magazine.scale = Vector3(1.18, 1.42, 1.15)
		elif has_mag1:
			magazine.scale.y = 1.25

	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("376c55") if has_skin else Color("2b3136")
	body_mat.metallic = 0.62 if has_skin else 0.55
	body_mat.roughness = 0.38 if has_skin else 0.44

	var mag_mat = StandardMaterial3D.new()
	mag_mat.albedo_color = Color("234538") if has_skin else Color("3b423c")
	mag_mat.metallic = 0.35
	mag_mat.roughness = 0.62

	rifle_meshes.clear()
	for m in rifle.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_instance_valid(magazine) and (mi == magazine or magazine.is_ancestor_of(mi)):
			mi.material_override = mag_mat
		else:
			mi.material_override = body_mat
		rifle_meshes.append(mi)

	# Low-profile M-LOK rail cover marker under forend
	support_grip = Node3D.new()
	support_grip.position = Vector3(0.0, 0.136, -0.145)
	rifle.add_child(support_grip)

	_build_reflex_optic()
	_build_attachments()
	_setup_skinned_arms(has_skin)
	_setup_knife_attachment()

	# Muzzle flash aligned with YS-04 barrel centerline (y = 0.158)
	flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.026
	sphere.height = 0.12
	flash.mesh = sphere
	flash.rotation.x = PI / 2
	flash.position = Vector3(0, 0.158, -0.37)
	flash.material_override = game._material(Color("ffe29a"), true)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.hide()
	add_child(flash)

	light = OmniLight3D.new()
	light.position = flash.position
	light.omni_range = 3.2
	light.light_color = Color("ffd699")
	light.light_energy = 0.0
	add_child(light)

	refresh_loadout()
	set_weapon_slot(0)

func _build_attachments():
	attachments_root = Node3D.new()
	add_child(attachments_root)
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
								glass_ov.albedo_color = Color(0.10, 0.32, 0.28, 0.04)
								mesh_i.set_surface_override_material(s_idx, glass_ov)
			node.hide()
			att_nodes[key] = node

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
			flash.scale = Vector3(0.45, 0.55, 0.45)
		elif muzzle_id == "compensator":
			flash.position = Vector3(0, 0.158, -0.415)
			flash.scale = Vector3(0.75, 0.78, 0.75)
		else:
			flash.position = Vector3(0, 0.158, -0.37)
			flash.scale = Vector3.ONE
		if is_instance_valid(light):
			light.position = flash.position

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
	if is_instance_valid(knife_root):
		knife_root.visible = not is_rifle
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

	# Cache bone pose tracks from Blender NLA animations for fast, zero-alloc frame blending
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

	# Compatibility markers for external inspection & tests
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
			var w := sin(t * PI)
			var s_name := "pose_knife_slash_a" if slash_combo == 0 else "pose_knife_slash_b"
			var k_slash: Dictionary = pose_cache.get(s_name, k_idle)
			final_map = _blend_bone_maps(k_idle, k_slash, w)
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
		left_hand_pivot.position = rifle.transform * (arms_skeleton.transform * hand_in_skel)

func _build_reflex_optic():
	optic_root = Node3D.new()
	optic_root.position = Vector3(0.0, 0.212, 0.03)
	add_child(optic_root)
	optic_housing = Node3D.new()
	optic_root.add_child(optic_housing)

	var upgraded = "red_dot" in game.rules.profile.owned
	var frame_color = Color("233833") if upgraded else Color("1e2428")
	var frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = frame_color
	frame_mat.metallic = 0.65
	frame_mat.roughness = 0.35

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
	glass_mat.albedo_color = Color(0.35, 0.88, 0.82, 0.11)
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

func shot():
	shot_left = 0.065

func animate(delta: float, reload_progress: float, moving: float, aimed: bool):
	elapsed += delta
	shot_left = maxf(0, shot_left - delta)
	slash_left = maxf(0, slash_left - delta)
	var firing := shot_left > 0 and weapon_slot == 0
	flash.visible = firing
	var muzzle_id: String = game.rules.active_muzzle()
	light.light_energy = (0.55 if muzzle_id == "suppressor" else 1.6) if firing else 0.0
	aim_blend = move_toward(aim_blend, 1.0 if (aimed and weapon_slot == 0) else 0.0, delta * 10.0)

	if weapon_slot == 0:
		var dip = sin(reload_progress * PI)
		rifle.rotation.z = dip * -0.26
		optic_root.rotation.z = rifle.rotation.z
		if is_instance_valid(attachments_root):
			attachments_root.rotation.z = rifle.rotation.z
		if is_instance_valid(magazine):
			magazine.position = Vector3(0, -dip * 0.16, dip * 0.07)
			magazine.rotation.x = -dip * 0.14
		var fire_w := clampf(shot_left / 0.065, 0.0, 1.0)
		_apply_arm_pose(aim_blend, dip, fire_w)
		position.x = sin(elapsed * 7.5) * moving * (0.0006 if aimed else 0.0035)
		position.y = absf(sin(elapsed * 7.5)) * moving * (0.0005 if aimed else 0.0025)
		position.z = 0.0
		rotation = rotation.lerp(Vector3.ZERO, minf(delta * 18.0, 1.0))
	else:
		rifle.rotation.z = 0.0
		_apply_arm_pose(0.0, 0.0, 0.0)
		var slash_t := sin(clampf(1.0 - (slash_left / slash_duration), 0.0, 1.0) * PI) if slash_left > 0.0 else 0.0
		var dir_sign := -1.0 if slash_combo == 0 else 1.0
		position.x = sin(elapsed * 8.5) * moving * 0.0045 + dir_sign * slash_t * 0.14
		position.y = absf(sin(elapsed * 8.5)) * moving * 0.0035 + slash_t * (0.045 if slash_combo == 0 else -0.025)
		position.z = -slash_t * 0.12
		rotation = Vector3(-slash_t * 0.18, dir_sign * slash_t * 0.16, -dir_sign * slash_t * 0.36)
