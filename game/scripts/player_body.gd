extends Node3D
## Full-Skeleton Skinned 3D Hero Controller for '游侠·少羽' (v0.9.4).
## - Loads Blender 4.5 rigged & retargeted asset res://assets/slice/player_shaoyu.glb (55 bones, 24 animations)
## - Godot 4.7.2 AnimationTree (Upper/Lower body bone-filtered blending: 8-dir locomotion, crouch, prone crawl, jump + combat)
## - AimSpineModifier (SkeletonModifier3D) layering smooth aim pitch & Q/E cover lean BEFORE IK & scarf physics
## - TwoBoneIK3D locking Left Arm (UpperArm.L -> LowerArm.L -> Hand.L) cleanly onto YS-04 forward handguard
## - SpringBoneSimulator3D simulating real-time flowing wind physics on Shaoyu's 4-bone cinnabar-red scarf tail
## - BoneAttachment3D (Weapon_R / Weapon_Back) syncing live YS-04 skins/attachments & back-holstering on Knife / [V] Slam
## - In 1P: hides head, gear, upper torso, scarf & backpack while keeping real skinned lower legs & boots visible!

const HERO_GLB := "res://assets/slice/player_shaoyu.glb"
const RIFLE_GLB := "res://assets/slice/rifle.glb"
const KNIFE_GLB := "res://assets/slice/tactical_knife.glb"
const RIFLE_WORLD_SCALE := 0.78

const UPPER_BODY_BONES := [
	"Abdomen", "Torso", "Chest", "Neck", "Head",
	"Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
	"Index2.L", "Index3.L", "Index4.L", "Middle2.L", "Middle3.L", "Middle4.L",
	"Ring2.L", "Ring3.L", "Ring4.L", "Pinky2.L", "Pinky3.L", "Pinky4.L",
	"Thumb2.L", "Thumb3.L",
	"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
	"Index2.R", "Index3.R", "Index4.R", "Middle2.R", "Middle3.R", "Middle4.R",
	"Ring2.R", "Ring3.R", "Ring4.R", "Pinky2.R", "Pinky3.R", "Pinky4.R",
	"Thumb2.R", "Thumb3.R",
	"Weapon_R", "Weapon_Back",
]

const LOOPING_ANIMS := [
	"Idle_Stance", "Walk_Fwd", "Jog_Fwd", "Sprint_Fwd",
	"Walk_Back", "Strafe_Left", "Strafe_Right",
	"Crouch_Idle", "Crouch_Walk", "Prone_Idle", "Prone_Crawl",
	"Jump_001", "Jump_Loop",
	"Rifle_LowReady", "Rifle_Aim", "Rifle_Crouch_Aim", "Knife_Idle",
]


class AimSpineModifier extends SkeletonModifier3D:
	var aim_pitch: float = 0.0
	var lean_roll: float = 0.0
	var recoil_pitch: float = 0.0
	var active_in_pose: bool = true
	var spine_indices: Array[int] = []
	var spine_pitch_weights: Array[float] = [0.10, 0.22, 0.34, 0.14, 0.20]
	var spine_lean_weights: Array[float] = [0.22, 0.32, 0.36, 0.05, 0.05]

	func bind_bones(skel: Skeleton3D) -> void:
		spine_indices.clear()
		for bname in ["Abdomen", "Torso", "Chest", "Neck", "Head"]:
			spine_indices.append(skel.find_bone(bname))

	func _process_modification() -> void:
		if not active_in_pose:
			return
		var skel := get_skeleton()
		if skel == null or spine_indices.is_empty():
			return
		var total_pitch := clampf(aim_pitch * 0.72 + recoil_pitch * 0.14, -0.62, 0.62)
		var total_lean := clampf(lean_roll * 0.38, -0.42, 0.42)
		if absf(total_pitch) < 0.002 and absf(total_lean) < 0.002:
			return
		for i in spine_indices.size():
			var bidx := spine_indices[i]
			if bidx < 0:
				continue
			var cur_q := skel.get_bone_pose_rotation(bidx)
			# In Shaoyu's hero space (+Z forward, +Y up), local spine tilt:
			# Positive X pitches forward/down, negative X tilts up; Z rolls left/right cover lean.
			var dp := -total_pitch * spine_pitch_weights[i]
			var dl := total_lean * spine_lean_weights[i]
			var delta_q := Quaternion.from_euler(Vector3(dp, 0.0, dl))
			skel.set_bone_pose_rotation(bidx, (cur_q * delta_q).normalized())


var game
var hero_root: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var aim_spine_mod: AimSpineModifier
var left_arm_ik: TwoBoneIK3D
var scarf_spring: SpringBoneSimulator3D

var weapon_r_attach: BoneAttachment3D
var weapon_back_attach: BoneAttachment3D
var foregrip_ik_target: Marker3D
var left_elbow_pole: Marker3D

# Mesh groups for clean 1P / 3P visibility separation
var upper_meshes: Array[MeshInstance3D] = []
var lower_meshes: Array[MeshInstance3D] = []

# Backward-compatible references queried by existing test suites
var hips_pivot: Node3D
var head_pivot: Node3D
var leg_l_pivot: Node3D

var world_rifle_root: Node3D
var world_knife_root: Node3D
var world_muzzle_flash: MeshInstance3D

var is_first_person: bool = true
var cur_weapon_slot: int = -1
var cur_rifle_holstered: bool = false
var flash_left: float = 0.0
var fire_anim_left: float = 0.0
var slam_anim_left: float = 0.0
var slash_anim_left: float = 0.0
var slash_anim_combo: int = 0
var was_on_floor: bool = true
var cur_lower_state: String = ""
var cur_upper_state: String = ""
var cur_upper_weight: float = 1.0
var cur_slam_weight: float = 0.0
var cur_ik_weight: float = 0.0
var breath_clock: float = 0.0


func setup(owner_game):
	game = owner_game
	_build_hero()
	refresh_weapon_visuals()
	set_first_person(true)


func _resolve_anim(candidates: Array[String]) -> String:
	if not is_instance_valid(anim_player):
		return ""
	for c in candidates:
		if anim_player.has_animation(c):
			return c
	var lst := anim_player.get_animation_list()
	return lst[0] if not lst.is_empty() else ""


func _build_hero():
	if not ResourceLoader.exists(HERO_GLB):
		push_warning("player_shaoyu.glb missing!")
		return
	var packed = load(HERO_GLB)
	if packed == null or not (packed is PackedScene):
		return
	hero_root = packed.instantiate()
	hero_root.name = "HeroModel"
	# Quaternius/glTF rig faces +Z locally; rotate 180 deg so Shaoyu faces player forward (-Z)!
	hero_root.rotation.y = PI
	add_child(hero_root)

	skeleton = hero_root.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = hero_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	hips_pivot = skeleton

	upper_meshes.clear()
	lower_meshes.clear()
	for mi in hero_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null:
			continue
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := m.name
		if n == "Shaoyu_LowerLegs" or n == "Shaoyu_LowerBoots":
			lower_meshes.append(m)
			if n == "Shaoyu_LowerLegs":
				leg_l_pivot = m
		else:
			upper_meshes.append(m)
			if n == "Shaoyu_Head":
				head_pivot = m

	if not is_instance_valid(skeleton) or not is_instance_valid(anim_player):
		push_warning("player_shaoyu.glb missing Skeleton3D or AnimationPlayer!")
		return

	# Ensure loop modes are set explicitly on all looping vs one-shot clips
	for aname in anim_player.get_animation_list():
		var anim := anim_player.get_animation(aname)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR if (aname in LOOPING_ANIMS) else Animation.LOOP_NONE

	# 1. Weapon BoneAttachments (Weapon_R for hands, Weapon_Back for sleek diagonal backpack holster)
	weapon_r_attach = BoneAttachment3D.new()
	weapon_r_attach.name = "WeaponRAttach"
	weapon_r_attach.bone_name = "Weapon_R"
	skeleton.add_child(weapon_r_attach)

	weapon_back_attach = BoneAttachment3D.new()
	weapon_back_attach.name = "WeaponBackAttach"
	weapon_back_attach.bone_name = "Weapon_Back"
	skeleton.add_child(weapon_back_attach)

	# 2. Left-Elbow Pole Marker for natural anatomical elbow tuck during TwoBoneIK3D
	left_elbow_pole = Marker3D.new()
	left_elbow_pole.name = "LeftElbowPole"
	# In hero_root local space (+Z forward, +X left, +Y up): outward-left and downward!
	left_elbow_pole.position = Vector3(0.42, 0.92, 0.14)
	hero_root.add_child(left_elbow_pole)

	# 3. Build Godot 4.7.2 AnimationTree (Upper/Lower Body Bone-Filtered Blend Tree)
	_build_animation_tree()

	# 4. SkeletonModifier3D stack (strict execution order on Skeleton3D!):
	#    (a) AimSpineModifier -> additive aim pitch & Q/E cover lean
	aim_spine_mod = AimSpineModifier.new()
	aim_spine_mod.name = "AimSpineModifier"
	skeleton.add_child(aim_spine_mod)
	aim_spine_mod.bind_bones(skeleton)

	#    (b) TwoBoneIK3D -> locks Left Arm strictly onto YS-04 forward handguard during blended movement/recoil
	left_arm_ik = TwoBoneIK3D.new()
	left_arm_ik.name = "LeftArmRifleIK"
	left_arm_ik.setting_count = 1
	left_arm_ik.set_root_bone_name(0, "UpperArm.L")
	left_arm_ik.set_middle_bone_name(0, "LowerArm.L")
	left_arm_ik.set_end_bone_name(0, "Hand.L")
	left_arm_ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Y)
	left_arm_ik.influence = 0.0
	skeleton.add_child(left_arm_ik)

	#    (c) SpringBoneSimulator3D -> real-time flowing wind physics on 4-bone cinnabar-red ranger scarf!
	if skeleton.find_bone("Scarf_01") >= 0 and skeleton.find_bone("Scarf_04") >= 0:
		scarf_spring = SpringBoneSimulator3D.new()
		scarf_spring.name = "ScarfSpringPhysics"
		scarf_spring.setting_count = 1
		scarf_spring.set_root_bone_name(0, "Scarf_01")
		scarf_spring.set_end_bone_name(0, "Scarf_04")
		scarf_spring.set_stiffness(0, 0.72)
		scarf_spring.set_drag(0, 0.34)
		scarf_spring.set_gravity(0, 0.42)
		scarf_spring.set_gravity_direction(0, Vector3(0.18, -0.78, -0.60).normalized())
		scarf_spring.set_radius(0, 0.035)
		skeleton.add_child(scarf_spring)


func _add_anim_node(tree: AnimationNodeBlendTree, node_name: String, candidates: Array[String], speed: float = 1.0) -> String:
	var aname := _resolve_anim(candidates)
	var anode := AnimationNodeAnimation.new()
	anode.animation = aname
	if absf(speed - 1.0) > 0.01:
		var ts := AnimationNodeTimeScale.new()
		var inner := node_name + "_clip"
		tree.add_node(inner, anode)
		tree.add_node(node_name, ts)
		tree.connect_node(node_name, 0, inner)
		return node_name
	tree.add_node(node_name, anode)
	return node_name


func _build_animation_tree():
	anim_tree = AnimationTree.new()
	anim_tree.name = "HeroAnimTree"
	hero_root.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var root_bt := AnimationNodeBlendTree.new()
	anim_tree.tree_root = root_bt

	# Lower-Body Locomotion Transition (15 crisp states with smooth 0.16s crossfade!)
	var lower_tr := AnimationNodeTransition.new()
	lower_tr.xfade_time = 0.16
	lower_tr.allow_transition_to_self = false
	var lower_specs := [
		["rifle_idle", ["Rifle_LowReady", "Idle_Stance"]],
		["rifle_aim_idle", ["Rifle_Aim", "Rifle_LowReady"]],
		["walk_fwd", ["Walk_Fwd"]],
		["jog_fwd", ["Jog_Fwd", "Walk_Fwd"]],
		["sprint_fwd", ["Sprint_Fwd", "Jog_Fwd"]],
		["walk_back", ["Walk_Back", "Walk_Fwd"]],
		["strafe_l", ["Strafe_Left", "Walk_Fwd"]],
		["strafe_r", ["Strafe_Right", "Walk_Fwd"]],
		["crouch_idle", ["Rifle_Crouch_Aim", "Crouch_Idle"]],
		["crouch_walk", ["Crouch_Walk", "Crouch_Idle"]],
		["prone_idle", ["Prone_Idle", "Prone_Crawl"]],
		["prone_crawl", ["Prone_Crawl", "Prone_Idle"]],
		["jump_start", ["Jump_Start_001", "Jump_Start", "Jump_001"]],
		["jump_loop", ["Jump_001", "Jump_Loop"]],
		["knife_idle", ["Knife_Idle", "Idle_Stance"]],
	]
	lower_tr.input_count = lower_specs.size()
	root_bt.add_node("LowerLocomotion", lower_tr)
	for i in lower_specs.size():
		var sname: String = lower_specs[i][0]
		var cands: Array[String] = []
		for s in lower_specs[i][1]:
			cands.append(String(s))
		lower_tr.set_input_name(i, sname)
		var nid := "L_" + sname
		_add_anim_node(root_bt, nid, cands)
		root_bt.connect_node("LowerLocomotion", i, nid)

	# Upper-Body Combat Transition (7 tactical weapon states with crisp 0.11s crossfade!)
	var upper_tr := AnimationNodeTransition.new()
	upper_tr.xfade_time = 0.11
	upper_tr.allow_transition_to_self = true
	var upper_specs := [
		["low_ready", ["Rifle_LowReady"]],
		["aim", ["Rifle_Aim"]],
		["fire", ["Rifle_Fire", "Rifle_Aim"]],
		["reload", ["Rifle_Reload", "Rifle_LowReady"]],
		["knife_idle", ["Knife_Idle"]],
		["knife_slash_1", ["Knife_Slash_1"]],
		["knife_slash_2", ["Knife_Slash_2", "Knife_Slash_1"]],
	]
	upper_tr.input_count = upper_specs.size()
	root_bt.add_node("UpperCombat", upper_tr)
	for i in upper_specs.size():
		var sname: String = upper_specs[i][0]
		var cands: Array[String] = []
		for s in upper_specs[i][1]:
			cands.append(String(s))
		upper_tr.set_input_name(i, sname)
		var nid := "U_" + sname
		_add_anim_node(root_bt, nid, cands)
		root_bt.connect_node("UpperCombat", i, nid)

	# Bone-Filtered Blend2: layers UpperCombat strictly onto Abdomen -> Head -> Arms -> Fingers -> Weapon sockets!
	var upper_blend := AnimationNodeBlend2.new()
	upper_blend.filter_enabled = true
	var skel_rel := String(hero_root.get_path_to(skeleton))
	for bname in UPPER_BODY_BONES:
		if skeleton.find_bone(bname) >= 0:
			upper_blend.set_filter_path(NodePath(skel_rel + ":" + bname), true)
	root_bt.add_node("UpperBlend", upper_blend)
	root_bt.connect_node("UpperBlend", 0, "LowerLocomotion")
	root_bt.connect_node("UpperBlend", 1, "UpperCombat")

	# Full-Body Heroic [V] Ground-Slam One-Shot Override (always starts cleanly from frame 0!)
	var slam_clip := AnimationNodeAnimation.new()
	slam_clip.animation = _resolve_anim(["Shaoyu_GroundSlam", "Knife_Slash_1"])
	root_bt.add_node("SlamClip", slam_clip)

	var full_oneshot := AnimationNodeOneShot.new()
	full_oneshot.fadein_time = 0.08
	full_oneshot.fadeout_time = 0.14
	root_bt.add_node("FullBodySlam", full_oneshot)
	root_bt.connect_node("FullBodySlam", 0, "UpperBlend")
	root_bt.connect_node("FullBodySlam", 1, "SlamClip")
	root_bt.connect_node("output", 0, "FullBodySlam")

	anim_tree.active = true
	anim_tree.set("parameters/LowerLocomotion/transition_request", "rifle_idle")
	anim_tree.set("parameters/UpperCombat/transition_request", "low_ready")
	anim_tree.set("parameters/UpperBlend/blend_amount", 1.0)
	cur_lower_state = "rifle_idle"
	cur_upper_state = "low_ready"


func refresh_weapon_visuals():
	if not is_instance_valid(weapon_r_attach) or not is_instance_valid(weapon_back_attach):
		return
	if is_instance_valid(world_rifle_root):
		world_rifle_root.queue_free()
		world_rifle_root = null
	if is_instance_valid(world_knife_root):
		world_knife_root.queue_free()
		world_knife_root = null

	# 1. World-scale YS-04 Carbine mounted cleanly on Weapon_R (zero origin shift -> exact Blender IK alignment!)
	world_rifle_root = Node3D.new()
	world_rifle_root.name = "WorldRifleRoot"
	weapon_r_attach.add_child(world_rifle_root)

	if ResourceLoader.exists(RIFLE_GLB):
		var packed_r = load(RIFLE_GLB)
		if packed_r is PackedScene:
			var rifle_inst: Node3D = packed_r.instantiate()
			rifle_inst.name = "YS04Mesh"
			rifle_inst.scale = Vector3.ONE * RIFLE_WORLD_SCALE
			world_rifle_root.add_child(rifle_inst)

			var has_gilded: bool = is_instance_valid(game) and ("gilded_skin" in game.rules.profile.owned)
			var has_skin: bool = has_gilded or (is_instance_valid(game) and ("forest_skin" in game.rules.profile.owned))
			var mag_node := rifle_inst.find_child("YS04_magazine", true, false) as Node3D
			if is_instance_valid(mag_node) and is_instance_valid(game):
				if "magazine2" in game.rules.profile.owned:
					mag_node.scale = Vector3(1.15, 1.35, 1.12)
				elif "magazine" in game.rules.profile.owned:
					mag_node.scale.y = 1.22

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

			# Synced Suppressor visual
			if is_instance_valid(game) and game.rules.active_muzzle() == "suppressor":
				var sup := MeshInstance3D.new()
				var scyl := CylinderMesh.new()
				scyl.top_radius = 0.015
				scyl.bottom_radius = 0.015
				scyl.height = 0.14
				sup.mesh = scyl
				sup.rotation.x = PI * 0.5
				sup.position = Vector3(0.0, 0.048, -0.40)
				var smat := StandardMaterial3D.new()
				smat.albedo_color = Color("252c32")
				smat.metallic = 0.65
				smat.roughness = 0.36
				sup.material_override = smat
				world_rifle_root.add_child(sup)

			# Synced compact Optic sight on top rail
			var optic_id: String = game.rules.active_optic() if is_instance_valid(game) else ""
			if optic_id == "red_dot" or optic_id == "scope_2x":
				var op := MeshInstance3D.new()
				var ocyl := CylinderMesh.new()
				ocyl.top_radius = 0.016 if optic_id == "scope_2x" else 0.014
				ocyl.bottom_radius = 0.016 if optic_id == "scope_2x" else 0.014
				ocyl.height = 0.135 if optic_id == "scope_2x" else 0.068
				op.mesh = ocyl
				op.rotation.x = PI * 0.5
				op.position = Vector3(0.0, 0.105, -0.025)
				var omat := StandardMaterial3D.new()
				omat.albedo_color = Color("1f252b")
				omat.metallic = 0.72
				omat.roughness = 0.32
				op.material_override = omat
				world_rifle_root.add_child(op)

			# World muzzle flash puff for 3P gunfire
			world_muzzle_flash = MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.068
			fm.height = 0.136
			world_muzzle_flash.mesh = fm
			world_muzzle_flash.position = Vector3(0.0, 0.048, -0.41)
			var fmat := StandardMaterial3D.new()
			fmat.albedo_color = Color("ffe48a")
			fmat.emission_enabled = true
			fmat.emission = Color("ffba42")
			fmat.emission_energy_multiplier = 4.2
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			world_muzzle_flash.material_override = fmat
			world_muzzle_flash.visible = false
			world_rifle_root.add_child(world_muzzle_flash)

	# Precision Left-Hand Foregrip IK Target on the YS-04 forward handguard!
	foregrip_ik_target = Marker3D.new()
	foregrip_ik_target.name = "ForegripIKTarget"
	foregrip_ik_target.position = Vector3(-0.020, -0.022, -0.115)
	world_rifle_root.add_child(foregrip_ik_target)

	if is_instance_valid(left_arm_ik) and is_instance_valid(left_elbow_pole):
		left_arm_ik.set_target_node(0, left_arm_ik.get_path_to(foregrip_ik_target))
		left_arm_ik.set_pole_node(0, left_arm_ik.get_path_to(left_elbow_pole))

	# 2. World-scale Sculpted Tactical Combat Knife (uses real tactical_knife.glb!)
	world_knife_root = Node3D.new()
	world_knife_root.name = "WorldKnifeRoot"
	weapon_r_attach.add_child(world_knife_root)
	if ResourceLoader.exists(KNIFE_GLB):
		var kp = load(KNIFE_GLB)
		if kp is PackedScene:
			var ki: Node3D = kp.instantiate()
			ki.scale = Vector3.ONE * 0.92
			ki.position = Vector3(0.0, 0.0, -0.04)
			for m in ki.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				if mi != null:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world_knife_root.add_child(ki)
	else:
		var blade := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(0.010, 0.028, 0.24)
		blade.mesh = bbox
		blade.position = Vector3(0.0, 0.0, -0.14)
		world_knife_root.add_child(blade)

	cur_weapon_slot = -1
	cur_rifle_holstered = false
	_sync_weapon_mount(0, false)
	_apply_visibility()


func _sync_weapon_mount(slot: int, force_holster: bool):
	if cur_weapon_slot == slot and cur_rifle_holstered == force_holster:
		return
	cur_weapon_slot = slot
	cur_rifle_holstered = force_holster
	if not is_instance_valid(world_rifle_root) or not is_instance_valid(world_knife_root):
		return

	var holster_rifle: bool = force_holster or (slot != 0)
	if not holster_rifle:
		if world_rifle_root.get_parent() != weapon_r_attach:
			world_rifle_root.get_parent().remove_child(world_rifle_root)
			weapon_r_attach.add_child(world_rifle_root)
		# Verified exact matrix alignment with Blender Weapon_R socket (+90 deg X maps rifle -Z -> bone +Y, +Y -> bone +Z!)
		world_rifle_root.position = Vector3.ZERO
		world_rifle_root.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		world_rifle_root.scale = Vector3.ONE
		world_knife_root.visible = false
	else:
		if world_rifle_root.get_parent() != weapon_back_attach:
			world_rifle_root.get_parent().remove_child(world_rifle_root)
			weapon_back_attach.add_child(world_rifle_root)
		# Sleek diagonal holster flush behind Shaoyu's compact mountain daypack!
		world_rifle_root.position = Vector3(0.0, 0.02, -0.04)
		world_rifle_root.rotation = Vector3(PI * 0.5, 0.0, PI * 0.5)
		world_rifle_root.scale = Vector3.ONE * 0.94
		world_knife_root.visible = (not is_first_person) and (slot == 1) and (not force_holster)
		world_knife_root.position = Vector3(0.0, 0.03, 0.0)
		world_knife_root.rotation = Vector3(PI * 0.5, 0.0, 0.0)

	# Keep TwoBoneIK3D target path valid if rifle reparented
	if is_instance_valid(left_arm_ik) and is_instance_valid(foregrip_ik_target):
		left_arm_ik.set_target_node(0, left_arm_ik.get_path_to(foregrip_ik_target))
	_apply_visibility()


func _apply_visibility():
	if not is_instance_valid(hero_root):
		return
	var show_upper: bool = not is_first_person
	for m in upper_meshes:
		if is_instance_valid(m):
			m.visible = show_upper
	for m in lower_meshes:
		if is_instance_valid(m):
			m.visible = true
	if is_instance_valid(world_rifle_root):
		world_rifle_root.visible = show_upper
	if is_instance_valid(world_knife_root):
		world_knife_root.visible = show_upper and (cur_weapon_slot == 1) and (not cur_rifle_holstered)


func set_first_person(fp: bool):
	is_first_person = fp
	_apply_visibility()


func trigger_shot():
	flash_left = 0.055
	fire_anim_left = 0.19
	if is_instance_valid(anim_tree) and cur_weapon_slot == 0 and slam_anim_left <= 0.0:
		anim_tree.set("parameters/UpperCombat/transition_request", "fire")
		cur_upper_state = "fire"


func trigger_knife_slash(combo: int):
	slash_anim_left = 0.38
	slash_anim_combo = combo
	if is_instance_valid(anim_tree) and slam_anim_left <= 0.0:
		var st := "knife_slash_1" if (combo % 2 == 1) else "knife_slash_2"
		anim_tree.set("parameters/UpperCombat/transition_request", st)
		cur_upper_state = st


func trigger_ground_slam():
	slam_anim_left = 0.72
	if is_instance_valid(anim_tree):
		anim_tree.set("parameters/FullBodySlam/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
	if not is_instance_valid(hero_root) or not is_instance_valid(anim_tree):
		return

	breath_clock += delta
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - delta)
	if fire_anim_left > 0.0:
		fire_anim_left = maxf(0.0, fire_anim_left - delta)
	if slash_anim_left > 0.0:
		slash_anim_left = maxf(0.0, slash_anim_left - delta)
	if slam_anim_left > 0.0:
		slam_anim_left = maxf(0.0, slam_anim_left - delta)

	var slamming: bool = slam_anim_left > 0.0
	_sync_weapon_mount(weapon_slot, slamming)

	if is_instance_valid(world_muzzle_flash):
		world_muzzle_flash.visible = (not is_first_person) and flash_left > 0.0 and weapon_slot == 0 and (not slamming)

	# 1P subtle backward offset so looking down shows real skinned thighs, knees & combat boots cleanly!
	var target_body_z: float = 0.0
	var target_body_y: float = 0.0
	if is_first_person:
		target_body_z = 0.22 if stance == 2 else (0.14 if stance == 1 else 0.09)
	elif stance == 2:
		# Subtle prone lift keeps belly, cargo pants & boots gliding cleanly ON TOP of undulating sand dunes!
		target_body_y = 0.08
	hero_root.position.z = lerpf(hero_root.position.z, target_body_z, minf(delta * 14.0, 1.0))
	hero_root.position.y = lerpf(hero_root.position.y, target_body_y, minf(delta * 14.0, 1.0))

	# 1. Select Lower-Body Locomotion Animation State (real 8-dir skeletal clips!)
	var horiz_speed := Vector2(local_vel.x, local_vel.z).length()
	var target_lower := "rifle_idle"
	if not on_floor:
		target_lower = "jump_start" if was_on_floor else "jump_loop"
	elif stance == 2:
		target_lower = "prone_crawl" if horiz_speed > 0.18 else "prone_idle"
	elif stance == 1:
		target_lower = "crouch_walk" if horiz_speed > 0.22 else "crouch_idle"
	else:
		if horiz_speed < 0.25:
			if weapon_slot == 1:
				target_lower = "knife_idle"
			else:
				target_lower = "rifle_aim_idle" if aiming else "rifle_idle"
		else:
			# Determine primary movement direction (local -Z is forward, +Z is back, -X is left, +X is right)
			var abs_x := absf(local_vel.x)
			var abs_z := absf(local_vel.z)
			if abs_x > abs_z * 1.15:
				target_lower = "strafe_l" if local_vel.x < 0.0 else "strafe_r"
			elif local_vel.z > 0.35:
				target_lower = "walk_back"
			elif horiz_speed > 5.05 and not aiming:
				target_lower = "sprint_fwd"
			elif horiz_speed > 2.85:
				target_lower = "jog_fwd"
			else:
				target_lower = "walk_fwd"
	was_on_floor = on_floor

	if target_lower != cur_lower_state:
		anim_tree.set("parameters/LowerLocomotion/transition_request", target_lower)
		cur_lower_state = target_lower

	# 2. Select Upper-Body Tactical Combat State
	var target_upper := "low_ready"
	if weapon_slot == 1:
		if slash_anim_left > 0.0:
			target_upper = "knife_slash_1" if (slash_anim_combo % 2 == 1) else "knife_slash_2"
		else:
			target_upper = "knife_idle"
	else:
		if reload_progress > 0.001:
			target_upper = "reload"
		elif fire_anim_left > 0.0:
			target_upper = "fire"
		elif aiming:
			target_upper = "aim"
		else:
			target_upper = "low_ready"

	if target_upper != cur_upper_state:
		anim_tree.set("parameters/UpperCombat/transition_request", target_upper)
		cur_upper_state = target_upper

	# Upper-body blend weight: 1.0 during combat locomotion, 0.0 during full-body prone crawl / prone idle / airborne jump!
	var want_upper_w := 1.0
	if stance == 2:
		want_upper_w = 0.0  # Prone_Idle and Prone_Crawl already animate the full body cleanly!
	elif stance == 1 and horiz_speed < 0.22 and weapon_slot == 0 and not aiming and reload_progress <= 0.001 and fire_anim_left <= 0.0:
		want_upper_w = 0.0  # Rifle_Crouch_Aim already poses the whole body cohesively!
	elif not on_floor and weapon_slot == 1 and slash_anim_left <= 0.0:
		want_upper_w = 0.35
	cur_upper_weight = lerpf(cur_upper_weight, want_upper_w, minf(delta * 14.0, 1.0))
	anim_tree.set("parameters/UpperBlend/blend_amount", cur_upper_weight)

	# 3. Update AimSpineModifier (additive camera pitch + Q/E lean + recoil kick)
	if is_instance_valid(aim_spine_mod):
		aim_spine_mod.active_in_pose = (not is_first_person) and (not slamming) and (stance != 2)
		aim_spine_mod.aim_pitch = lerpf(aim_spine_mod.aim_pitch, pitch, minf(delta * 14.0, 1.0))
		aim_spine_mod.lean_roll = lerpf(aim_spine_mod.lean_roll, lean_blend, minf(delta * 14.0, 1.0))
		aim_spine_mod.recoil_pitch = lerpf(aim_spine_mod.recoil_pitch, recoil, minf(delta * 22.0, 1.0))

	# 4. Left-Arm TwoBoneIK3D stays armed & ready on Skeleton3D; our Blender 2-bone IK clips (Rifle_LowReady/Aim/Fire/Crouch/Prone)
	#    already co-solve Hand.L, all 15 left fingers, and Weapon_R as ONE zero-lag rigid unit inside UpperBlend!
	#    Keep subtle micro-stabilization off on exact-solved stances so left elbow & fingers stay 100% anatomical!
	if is_instance_valid(left_arm_ik):
		cur_ik_weight = lerpf(cur_ik_weight, 0.0, minf(delta * 16.0, 1.0))
		left_arm_ik.influence = cur_ik_weight

	# 5. Update Dynamic Wind & Inertia on Shaoyu's Cinnabar-Red Scarf (SpringBoneSimulator3D!)
	if is_instance_valid(scarf_spring):
		var breeze := sin(breath_clock * 2.4) * 0.14
		# Hero faces +Z locally; running forward (local_vel.z < 0) blows scarf backward (-Z in hero local -> actually back is -Z in hero_root!)
		var wind := Vector3(0.22 + breeze + local_vel.x * 0.14, 0.05, -0.35 + local_vel.z * 0.24)
		scarf_spring.set_external_force(wind)
