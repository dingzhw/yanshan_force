extends SceneTree
## Captures 8 GPU-rendered 1280x720 screenshots verifying every v0.6.1.1 feature & bugfix:
## 1) Menu v0.6.1.1 briefing; 2) Crouch + [E] right cover lean peek in combat;
## 3) [Z] Prone low grass sightline; 4) Upstream Bridge (z=-46.5) gentle bluestone hillside trail;
## 5) South Bridge (z=7.0) gentle bluestone trail up to Wangdao Pavilion;
## 6) Sky egrets & startled bird flapping wide feathered wings in flight;
## 7) Red squirrel vertically scrambling up a Camphor tree trunk;
## 8) Wild boar mid-stride counter-charge gallop with tusks & warning tag.

var game

func _initialize():
	run()

func wait_render(frames: int = 8):
	await process_frame
	for i in frames:
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw

func aim_player_at(from_xz: Vector3, look_target: Vector3, y_offset: float = 0.12):
	var ground_pos: Vector3 = game.Layout.on_ground(Vector3(from_xz.x, 0.0, from_xz.z)) + Vector3(0.0, y_offset, 0.0)
	game.player.velocity = Vector3.ZERO
	game.player.position = ground_pos
	var eye_h: float = game.player.current_eye_y
	var d: Vector3 = look_target - (ground_pos + Vector3(0.0, eye_h, 0.0))
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.1, 1.1)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(8)

	# 1. Main menu with v0.6.1.1 briefing
	game._refresh_menu("烟山基地 v0.6.1.1 · 战术身法与生灵动作精修")
	await wait_render(4)
	game._capture("01-menu-v0611.png")

	# 2. Combat Mode: Crouch ([C]) + Right Cover Lean ([E]) peeking around cover crate at Zone 0
	game.start_action(true)
	await wait_render(8)
	var z0_center: Vector3 = game.combat.zone_center(0)
	# Place a temporary foreground sandbag/crate cover right in front-left of player so peek around right edge is dramatic & clear!
	var peek_cover := StaticBody3D.new()
	peek_cover.collision_layer = 1
	var pc_mesh := MeshInstance3D.new()
	var pc_box := BoxMesh.new()
	pc_box.size = Vector3(1.15, 1.38, 0.78)
	pc_mesh.mesh = pc_box
	var pc_mat := StandardMaterial3D.new()
	pc_mat.albedo_color = Color("5a6354")
	pc_mat.roughness = 0.85
	pc_mesh.material_override = pc_mat
	var pc_trim := MeshInstance3D.new()
	var pt_box := BoxMesh.new()
	pt_box.size = Vector3(1.18, 0.12, 0.81)
	pc_trim.mesh = pt_box
	pc_trim.position.y = 0.64
	pc_trim.material_override = game._material(Color("c49a45"))
	peek_cover.add_child(pc_mesh)
	peek_cover.add_child(pc_trim)
	var stand_spot: Vector3 = game.Layout.on_ground(z0_center + Vector3(-1.2, 0.0, 6.2))
	peek_cover.position = stand_spot + Vector3(-0.32, 0.69, -1.28)
	game.combat.arena.add_child(peek_cover)

	game.player.reset_stance()
	game.player.set_stance(1, true)
	game.player.lean_dir = 1
	aim_player_at(z0_center + Vector3(-1.2, 0.0, 6.2), z0_center + Vector3(0.6, 1.15, -3.5), 0.08)
	await wait_render(18)
	game._capture("02-cover-lean-crouch-peek.png")
	peek_cover.queue_free()

	# 3. Combat Mode: Prone ([Z]) low-profile sightline through hillside grass
	game.player.lean_dir = 0
	game.player.set_stance(2, true)
	aim_player_at(z0_center + Vector3(1.8, 0.0, 7.6), z0_center + Vector3(0.0, 1.15, -3.5), 0.05)
	await wait_render(20)
	game._capture("03-prone-low-grass-sightline.png")

	# Switch to exploration mode for crisp world & wildlife shots
	game._end_run(false)
	game.start_action(false)
	game.player.reset_stance()
	await wait_render(8)

	# 4. Upstream Bridge (z = -46.5, cx = 18.5) looking across creek bridge up the smooth graded bluestone trail to Recon Radio!
	var ub_cx: float = game.Layout.stream_center_x(-46.5)
	var ub_target := Vector3(27.5, game.terrain_height(27.5, -46.5) + 1.35, -46.5)
	aim_player_at(Vector3(ub_cx - 6.8, 0.0, -46.5), ub_target, 0.12)
	await wait_render(8)
	game._capture("04-upstream-bridge-gentle-trail.png")

	# 5. South Bridge (z = 7.0, cx = 18.6) looking across creek bridge up the gentle bluestone path toward Wangdao Pavilion!
	var sb_cx: float = game.Layout.stream_center_x(7.0)
	var sb_target := Vector3(31.5, game.terrain_height(31.5, 16.5) + 1.85, 16.5)
	aim_player_at(Vector3(sb_cx - 6.6, 0.0, 6.4), sb_target, 0.12)
	await wait_render(8)
	game._capture("05-south-bridge-pavilion-trail.png")

	# 6. Sky Egrets & Startled Bird flapping wide articulated feathered wings in flight!
	var eg_cam_xz := Vector3(13.5, 0.0, 19.5)
	var eg_cam_g: Vector3 = game.Layout.on_ground(eg_cam_xz)
	if game.wildlife.sky_egrets.size() >= 2:
		var eg_a: Dictionary = game.wildlife.sky_egrets[0]
		var eg_b: Dictionary = game.wildlife.sky_egrets[1]
		(eg_a.node as Node3D).position = eg_cam_g + Vector3(1.6, 4.1, -5.8)
		(eg_a.node as Node3D).rotation = Vector3(0.0, deg_to_rad(52.0), 0.0)
		if eg_a.vis != null:
			(eg_a.vis as Node3D).rotation = Vector3(0.08, 0.0, 0.18)
		if eg_a.anim != null:
			var ap_a := eg_a.anim as AnimationPlayer
			ap_a.play("Fly")
			ap_a.seek(0.22, true)
			ap_a.speed_scale = 0.0

		(eg_b.node as Node3D).position = eg_cam_g + Vector3(-1.9, 5.2, -7.8)
		(eg_b.node as Node3D).rotation = Vector3(0.0, deg_to_rad(36.0), 0.0)
		if eg_b.vis != null:
			(eg_b.vis as Node3D).rotation = Vector3(0.05, 0.0, -0.14)
		if eg_b.anim != null:
			var ap_b := eg_b.anim as AnimationPlayer
			ap_b.play("Glide" if ap_b.has_animation("Glide") else "Fly")
			ap_b.seek(0.45, true)
			ap_b.speed_scale = 0.0

	for a in game.wildlife.animals:
		if a.kind == "bird":
			a.state = "fly"
			a.pos = eg_cam_g + Vector3(0.2, 2.7, -4.4)
			a.root.position = a.pos
			a.root.rotation = Vector3(0.0, deg_to_rad(42.0), 0.0)
			a.visual.rotation = Vector3(-0.18, 0.0, 0.10)
			if a.anim != null:
				var ap_bird := a.anim as AnimationPlayer
				ap_bird.play("Fly")
				ap_bird.seek(0.18, true)
				ap_bird.speed_scale = 0.0
			break
	game.wildlife.frozen_for_capture = true
	aim_player_at(eg_cam_xz, eg_cam_g + Vector3(0.3, 4.1, -5.8), 0.12)
	await wait_render(6)
	game._capture("06-sky-egrets-wings-flapping.png")

	# 7. Close-up of a Red Squirrel vertically scrambling up an open hillside Camphor tree trunk!
	var chosen_trunk := Vector3.ZERO
	var chosen_rad := 0.34
	var shrine_xz := Vector2(game.Layout.CAMPHOR_SHRINE.x, game.Layout.CAMPHOR_SHRINE.z)
	for ti in game.landscape.tree_trunks.size():
		var tp: Vector3 = game.landscape.tree_trunks[ti]
		var tr_r: float = float(game.landscape.tree_trunk_radii[ti])
		if Vector2(tp.x, tp.z).distance_to(shrine_xz) < 8.0:
			continue
		if tr_r >= 0.30 and tr_r <= 0.44 and tp.z > -28.0 and tp.z < 12.0 and absf(tp.x) > 14.0 and absf(tp.x) < 36.0:
			chosen_trunk = tp
			chosen_rad = tr_r
			break
	if chosen_trunk == Vector3.ZERO and not game.landscape.tree_trunks.is_empty():
		chosen_trunk = game.landscape.tree_trunks[0]
		chosen_rad = float(game.landscape.tree_trunk_radii[0])

	var posed_sq := false
	for a in game.wildlife.animals:
		if a.kind == "squirrel":
			if posed_sq:
				a.root.visible = false
				continue
			posed_sq = true
			a.tree_trunk = chosen_trunk
			a.tree_radius = chosen_rad
			a.climb_h = 1.48
			a.climb_target_h = 3.2
			# Place squirrel on the sunlit South-West / South-East bark face, completely unobstructed!
			var c_ang := deg_to_rad(55.0)
			a.climb_angle = c_ang
			a.state = "climb_up"
			var out_x := cos(c_ang)
			var out_z := sin(c_ang)
			a.pos = Vector3(chosen_trunk.x + out_x * (chosen_rad + 0.04), chosen_trunk.y + 1.48, chosen_trunk.z + out_z * (chosen_rad + 0.04))
			a.root.position = a.pos
			a.root.rotation = Vector3(0.0, atan2(out_x, out_z), 0.0)
			a.visual.position = Vector3.ZERO
			a.visual.rotation = Vector3(PI * 0.48, 0.0, 0.0)
			a.label.visible = true
			a.label.text = "Red Squirrel · 小松鼠 (攀树躲避)"
			if a.anim != null:
				var ap_sq := a.anim as AnimationPlayer
				ap_sq.play("Climb" if ap_sq.has_animation("Climb") else "Run")
				ap_sq.seek(0.09, true)
				ap_sq.speed_scale = 0.0
			# Stand 2.35m back & slightly angled so we see the squirrel's side/back profile hugging the bark!
			var side_ang := c_ang + deg_to_rad(26.0)
			var cam_from := Vector3(chosen_trunk.x + cos(side_ang) * 2.35, 0.0, chosen_trunk.z + sin(side_ang) * 2.35)
			aim_player_at(cam_from, a.pos + Vector3(0.0, 0.04, 0.0), 0.08)
	await wait_render(6)
	game._capture("07-squirrel-climbing-camphor-trunk.png")
	for a in game.wildlife.animals:
		if a.kind == "squirrel":
			a.root.visible = true

	# 8. Close-up of a Wild Boar mid-gallop counter-charge ("Run" peak stride extension + ivory tusks)!
	var boar_spot_xz := Vector3(36.5, 0.0, 4.8)
	var boar_g: Vector3 = game.Layout.on_ground(boar_spot_xz)
	var player_spot_xz := Vector3(34.7, 0.0, 7.3)
	var player_g: Vector3 = game.Layout.on_ground(player_spot_xz)
	for a in game.wildlife.animals:
		if a.kind == "boar":
			a.state = "charge"
			a.pos = boar_g
			a.root.position = boar_g
			var to_cam := Vector3(player_g.x - boar_g.x, 0.0, player_g.z - boar_g.z).normalized()
			# 3/4 side-front angle (-54 deg) clearly showcases all 4 galloping legs split wide AND front ivory tusks!
			var show_dir := to_cam.rotated(Vector3.UP, deg_to_rad(-54.0))
			a.root.rotation = Vector3(0.0, atan2(-show_dir.x, -show_dir.z), 0.0)
			a.visual.position = Vector3.ZERO
			a.visual.rotation = Vector3.ZERO
			a.label.visible = true
			a.label.text = "⚠ 小野猪冲撞 · Wild Boar!"
			a.label.modulate = Color("ff8e72")
			if a.anim != null:
				var ap_boar := a.anim as AnimationPlayer
				ap_boar.play("Run")
				var r_len: float = ap_boar.get_animation("Run").length if ap_boar.has_animation("Run") else 0.5
				ap_boar.seek(r_len * 0.25, true)
				ap_boar.speed_scale = 0.0
			break
	game.player.set_stance(1, true)
	await wait_render(12)
	aim_player_at(player_spot_xz, boar_g + Vector3(0.0, 0.36, 0.0), 0.06)
	await wait_render(6)
	game._capture("08-boar-gallop-charge-gore.png")

	game.queue_free()
	await process_frame
	print("PASS capture_v0611 completed all 8 screenshots")
	quit(0)
