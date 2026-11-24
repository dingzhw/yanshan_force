extends SceneTree

var game
var failures = 0
var checks = 0

func _initialize():
	call_deferred("run")

func key(code: int,pressed: bool,physical = true):
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code if physical else 0
	event.pressed = pressed
	Input.parse_input_event(event)

func verify(condition: bool,message: String):
	checks += 1
	if not condition:
		failures += 1
	print("PASS " if condition else "FAIL ",message)

func travel(code: int,physical = true,sprint = false) -> Vector3:
	game.player.clear_movement_input()
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN) + Vector3(0, 0.2, 0)
	game.player.yaw = 0
	for i in 20:
		await physics_frame
	var start = game.player.position
	if sprint:
		key(KEY_SHIFT,true)
	key(code,true,physical)
	for i in 60:
		await physics_frame
	var moved = game.player.position - start
	key(code,false,physical)
	key(KEY_SHIFT,false)
	print("MOVEMENT ",code," physical=",physical," sprint=",sprint," displacement=",moved," floor=",game.player.is_on_floor()," mouse_mode=",Input.mouse_mode)
	return moved

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	for i in 45:
		await physics_frame
	verify(game.player.is_on_floor(),"spawn lands on terrain")
	var forward = await travel(KEY_W)
	verify(forward.z < -3.0 and absf(forward.x)<0.1,"W advances and does not stick in ground")
	var back = await travel(KEY_S)
	verify(back.z > 3.0 and absf(back.x)<0.1,"S moves backwards")
	var left = await travel(KEY_A)
	verify(left.x < -3.0 and absf(left.z)<0.1,"A strafes left")
	var right = await travel(KEY_D)
	verify(right.x > 3.0 and absf(right.z)<0.1,"D strafes right")
	var logical = await travel(KEY_W,false)
	verify(logical.z < -3.0,"logical-only key events also move")
	var arrow = await travel(KEY_UP)
	verify(arrow.z < -3.0,"arrow keys move as an alternative")
	var sprint = await travel(KEY_W,true,true)
	verify(sprint.length() > forward.length()*1.3,"Shift sprint increases actual displacement")
	game.player.clear_movement_input()
	for i in 12:
		await physics_frame
	var jump_start = game.player.position.y
	key(KEY_SPACE,true)
	for i in 8:
		await physics_frame
	key(KEY_SPACE,false)
	verify(game.player.position.y > jump_start+0.4,"Space jumps above terrain")
	for i in 60:
		await physics_frame
	verify(game.player.is_on_floor(),"jump lands normally")
	key(KEY_W,true)
	await physics_frame
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	var paused_at = game.player.position
	for i in 10:
		await physics_frame
	verify(game.player.position.distance_to(paused_at)<0.01,"pause stops movement")
	key(KEY_W,false)
	game._input(escape)
	verify(game.player.held_keys.is_empty(),"resume clears held input")
	game.player.clear_movement_input()
	game.player.position = Vector3(42, game.terrain_height(42, 22) + 1.0, 22)
	for i in 60:
		await physics_frame
	verify(game.player.is_on_floor(),"terrain slopes support the player")
	key(KEY_W,true)
	var slope_start = game.player.position
	for i in 60:
		await physics_frame
	key(KEY_W,false)
	verify(game.player.position.distance_to(slope_start)>2.0,"player can walk on a hillside")

	# v0.6.1.1 Tactical Stances ([C] Crouch, [Z] Prone, Overhead Roof Clearance) & Hybrid [Q/E] Cover Lean + [F] Interact
	game.player.clear_movement_input()
	game.player.reset_stance()
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN) + Vector3(0, 0.2, 0)
	game.player.yaw = 0.0
	for i in 20:
		await physics_frame

	key(KEY_C, true)
	key(KEY_C, false)
	for i in 25:
		await physics_frame
	verify(game.player.stance == 1 and absf(game.player.camera.position.y - 1.04) < 0.06, "[C] crouch lowers eye height to ~1.04m")
	var crouch_start = game.player.position
	key(KEY_W, true)
	for i in 60:
		await physics_frame
	key(KEY_W, false)
	var crouch_dist = (game.player.position - crouch_start).length()
	verify(crouch_dist > 1.2 and crouch_dist < forward.length() * 0.74, "crouch movement is controlled and slower than standing")

	key(KEY_Z, true)
	key(KEY_Z, false)
	for i in 28:
		await physics_frame
	verify(game.player.stance == 2 and absf(game.player.camera.position.y - 0.46) < 0.06, "[Z] prone lowers eye height to ~0.46m")
	var prone_start = game.player.position
	key(KEY_W, true)
	for i in 60:
		await physics_frame
	key(KEY_W, false)
	var prone_dist = (game.player.position - prone_start).length()
	verify(prone_dist > 0.6 and prone_dist < crouch_dist * 0.68, "prone crawl is slower than crouch walk")

	# Low ceiling overhead check: cannot stand up directly under a 1.32m roof
	var low_roof := StaticBody3D.new()
	low_roof.collision_layer = 1
	var roof_cs := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(2.2, 0.24, 2.2)
	roof_cs.shape = roof_box
	low_roof.add_child(roof_cs)
	low_roof.position = game.player.position + Vector3(0.0, 1.34, 0.0)
	game.add_child(low_roof)
	await physics_frame
	await physics_frame
	key(KEY_Z, true)
	key(KEY_Z, false)
	await physics_frame
	verify(game.player.stance == 1, "standing from prone under 1.34m low roof safely stops at crouch instead of clipping")
	key(KEY_C, true)
	key(KEY_C, false)
	await physics_frame
	verify(game.player.stance == 1, "crouched player cannot stand through low overhead obstacle")
	low_roof.queue_free()
	await physics_frame
	await physics_frame
	key(KEY_C, true)
	key(KEY_C, false)
	for i in 22:
		await physics_frame
	verify(game.player.stance == 0 and absf(game.player.camera.position.y - 1.58) < 0.06, "removing overhead obstacle allows [C] to stand back up")

	# Hybrid [E] tap-to-toggle (< 0.22s) & [Q] hold-to-peek (>= 0.22s) + side wall anti-clip
	key(KEY_E, true)
	for i in 4:
		await physics_frame
	key(KEY_E, false)
	for i in 20:
		await physics_frame
	verify(game.player.lean_dir == 1 and game.player.camera.position.x > 0.28 and game.player.camera.rotation.z < -0.15, "short [E] tap toggles right cover lean ON")
	key(KEY_E, true)
	await physics_frame
	key(KEY_E, false)
	for i in 20:
		await physics_frame
	verify(game.player.lean_dir == 0 and absf(game.player.camera.position.x) < 0.04, "second [E] tap resets cover lean to center")

	key(KEY_Q, true)
	for i in 22:
		await physics_frame
	verify(game.player.lean_dir == -1 and game.player.camera.position.x < -0.28, "holding [Q] >= 0.22s leans camera left")
	key(KEY_Q, false)
	for i in 20:
		await physics_frame
	verify(game.player.lean_dir == 0 and absf(game.player.camera.position.x) < 0.04, "releasing held [Q] automatically returns from peek")

	# Side-wall anti-clip clamp during lean
	var side_wall := StaticBody3D.new()
	side_wall.collision_layer = 1
	var sw_cs := CollisionShape3D.new()
	var sw_box := BoxShape3D.new()
	sw_box.size = Vector3(0.2, 2.2, 2.0)
	sw_cs.shape = sw_box
	side_wall.add_child(sw_cs)
	side_wall.position = game.player.position + Vector3(0.42, 1.1, 0.0)
	game.add_child(side_wall)
	await physics_frame
	await physics_frame
	key(KEY_E, true)
	for i in 18:
		await physics_frame
	verify(game.player.camera.position.x < 0.14, "leaning into nearby right wall clamps camera offset to prevent clipping")
	key(KEY_E, false)
	side_wall.queue_free()
	await physics_frame

	# [F] Interact remap check
	game.player.clear_movement_input()
	game.player.reset_stance()
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN) + Vector3(0, 0.2, 0)
	game.player.yaw = 0.0
	for i in 10:
		await physics_frame
	key(KEY_F, true)
	key(KEY_F, false)
	await physics_frame
	verify(game.active_station == 0, "[F] triggers world interaction cleanly")
	game._leave_station()

	# v0.9.3 Full-body hero '少羽' (PlayerBody) & seamless 1P/3P camera switching + anti-wall-clip + optical ADS snap!
	var pb = game.player.player_body
	verify(is_instance_valid(pb) and is_instance_valid(pb.hips_pivot) and is_instance_valid(pb.head_pivot) and is_instance_valid(pb.leg_l_pivot) and is_instance_valid(pb.world_rifle_root), "v0.9.3: PlayerBody loads articulated full-body Shaoyu rig with legs, head & world rifle")
	verify(not game.player.third_person and not pb.head_pivot.visible and pb.leg_l_pivot.visible and game.player.weapon_root.visible, "v0.9.3: 1P default hides head/arms while keeping real legs/boots visible below camera")
	key(KEY_P, true)
	key(KEY_P, false)
	for i in 18:
		await physics_frame
	verify(game.player.third_person and pb.head_pivot.visible and not game.player.weapon_root.visible and game.player.camera.position.z > 1.2, "v0.9.3: [P] switches cleanly to 3P over-the-shoulder view with full body visible")
	var aim_pt_3p: Vector3 = game.player.get_aim_target_position()
	verify(aim_pt_3p.distance_to(game.player.global_position + Vector3(0, 1.44, 0)) < 0.35, "v0.9.3: get_aim_target_position() tracks Shaoyu's real body rather than trailing 3P camera")
	# 3P Anti-wall-clip check
	var back_wall := StaticBody3D.new()
	back_wall.collision_layer = 1
	var bw_cs := CollisionShape3D.new()
	var bw_box := BoxShape3D.new()
	bw_box.size = Vector3(3.0, 3.0, 0.25)
	bw_cs.shape = bw_box
	back_wall.add_child(bw_cs)
	back_wall.position = game.player.position + Vector3(0.3, 1.5, 1.15)
	game.add_child(back_wall)
	for i in 12:
		await physics_frame
	verify(game.player.camera.position.z < 1.10, "v0.9.3: 3P camera boom anti-clip pulls forward cleanly in front of rear wall (z=%.2f)" % game.player.camera.position.z)
	back_wall.queue_free()
	for i in 12:
		await physics_frame
	# 3P ADS smart optical snap when scope_2x is equipped
	game.rules.profile.owned.append("scope_2x")
	game.rules.profile.equipped["optic"] = "scope_2x"
	game.player.aiming = true
	for i in 6:
		await physics_frame
	verify(game.player.effective_fp_view and game.player.weapon_root.visible and not pb.head_pivot.visible, "v0.9.3: 3P right-click ADS with 2x scope seamlessly snaps into 1P optical sight")
	game.player.aiming = false
	for i in 8:
		await physics_frame
	verify(not game.player.effective_fp_view and pb.head_pivot.visible and not game.player.weapon_root.visible, "v0.9.3: releasing ADS smoothly returns to 3P over-the-shoulder view")
	key(KEY_F5, true)
	key(KEY_F5, false)
	for i in 6:
		await physics_frame
	verify(not game.player.third_person and game.player.effective_fp_view, "v0.9.3: [F5] switches smoothly back to 1P mode")

	# v0.9.4 Rigged Skinned Hero '游侠·少羽' (55-bone Skeleton3D, 24 animations, AnimationTree, AimSpineModifier, TwoBoneIK3D, SpringBone Scarf & Auto Back-Holster)
	verify(is_instance_valid(pb.skeleton) and pb.skeleton.get_bone_count() >= 55, "v0.9.4: Shaoyu rig loads full 55-bone Skeleton3D (bones=%d)" % (pb.skeleton.get_bone_count() if is_instance_valid(pb.skeleton) else 0))
	verify(is_instance_valid(pb.anim_player) and pb.anim_player.get_animation_list().size() >= 22, "v0.9.4: AnimationPlayer embeds >=22 real skeletal animation clips (%d loaded)" % (pb.anim_player.get_animation_list().size() if is_instance_valid(pb.anim_player) else 0))
	verify(is_instance_valid(pb.anim_tree) and pb.anim_tree.active, "v0.9.4: AnimationTree upper/lower bone-filtered blend tree is active")
	verify(is_instance_valid(pb.aim_spine_mod) and is_instance_valid(pb.left_arm_ik) and is_instance_valid(pb.scarf_spring), "v0.9.4: AimSpineModifier, TwoBoneIK3D & SpringBoneSimulator3D scarf physics are mounted on Skeleton3D")
	verify(pb.upper_meshes.size() >= 1 and pb.lower_meshes.size() == 2 and pb.lower_meshes[0].visible and pb.lower_meshes[1].visible, "v0.9.9.2: Shaoyu v2 PBR meshes cleanly split upper body vs always-visible 1P lower legs/boots")
	# Switch to 3P and verify live locomotion + combat state transitions & auto back-holster on Knife / [V] Ground-Slam!
	game.player.set_third_person(true, true)
	game.player.select_weapon(1)
	for i in 4:
		await physics_frame
	verify(pb.world_rifle_root.get_parent() == pb.weapon_back_attach and pb.cur_upper_state == "knife_idle", "v0.9.4: selecting Tactical Knife holsters YS-04 diagonally on Weapon_Back and enters knife_idle")
	game.player.select_weapon(0)
	for i in 4:
		await physics_frame
	verify(pb.world_rifle_root.get_parent() == pb.weapon_r_attach and pb.cur_upper_state == "low_ready", "v0.9.4: returning to YS-04 mounts rifle onto calibrated Weapon_R bone socket in low_ready")
	pb.trigger_ground_slam()
	for i in 4:
		await physics_frame
	verify(pb.slam_anim_left > 0.0 and pb.world_rifle_root.get_parent() == pb.weapon_back_attach, "v0.9.4: [V] Shaoyu Ground-Slam temporarily back-holsters rifle so fist slams cleanly without sky-pointing barrel")
	pb.slam_anim_left = 0.0

	# v0.9.9.2 Sculpted PBR Protagonist '游侠·少羽 v2' (72-bone Mixamo+Sockets Skeleton, 24 retargeted anims, 1P/3P split, zero-twist prone!)
	var upper_node: MeshInstance3D = pb.hero_root.find_child("Shaoyu_UpperBody", true, false) as MeshInstance3D
	var legs_node: MeshInstance3D = pb.hero_root.find_child("Shaoyu_LowerLegs", true, false) as MeshInstance3D
	var boots_node: MeshInstance3D = pb.hero_root.find_child("Shaoyu_LowerBoots", true, false) as MeshInstance3D
	var total_v2_verts := 0
	for mi_v2 in [upper_node, legs_node, boots_node]:
		if is_instance_valid(mi_v2) and mi_v2.mesh != null and mi_v2.mesh.get_surface_count() > 0:
			total_v2_verts += mi_v2.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	verify(is_instance_valid(upper_node) and is_instance_valid(legs_node) and is_instance_valid(boots_node) and total_v2_verts >= 10000 and pb.skeleton.get_bone_count() >= 65, "v0.9.9.2: Shaoyu v2 loads sculpted PBR hero (%d verts, %d bones) split cleanly into UpperBody/LowerLegs/LowerBoots" % [total_v2_verts, pb.skeleton.get_bone_count()])
	game.player.stance = 2
	for i in 8:
		await physics_frame
	var ul_idx: int = pb.skeleton.find_bone("UpperLeg.L")
	var ur_idx: int = pb.skeleton.find_bone("UpperLeg.R")
	var fl_idx: int = pb.skeleton.find_bone("Foot.L")
	var fr_idx: int = pb.skeleton.find_bone("Foot.R")
	var feet_sep: float = pb.skeleton.get_bone_global_pose(fl_idx).origin.distance_to(pb.skeleton.get_bone_global_pose(fr_idx).origin)
	verify(pb.cur_lower_state == "prone_idle" and ul_idx >= 0 and ur_idx >= 0 and feet_sep < 0.65, "v0.9.9.2: Prone_Idle aligns Shaoyu v2 legs cleanly behind hips without gimbal twist (feet_sep=%.2fm)" % feet_sep)
	game.player.stance = 0
	game.player.set_third_person(false, true)
	for i in 4:
		await physics_frame
	verify(not upper_node.visible and pb.lower_meshes[0].visible and pb.lower_meshes[1].visible, "v0.9.9.2: 1P hides Shaoyu_UpperBody while keeping sculpted cargo-pant legs & combat boots visible for clean look-down")

	game.player.clear_movement_input()
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("MOVEMENT_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
