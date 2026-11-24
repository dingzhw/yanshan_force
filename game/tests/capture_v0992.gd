extends SceneTree
## v0.9.9.2 Visual Audit Capture Suite (1280x720 GL Compatibility):
## 01. Protagonist Shaoyu v2 sunny front 3/4 portrait in Yanshan Base (3P Rifle_LowReady with YS-04 rifle!)
## 02. Protagonist Shaoyu v2 tactical Rifle_Aim + Prone check (verifying rifle grip, amber goggles & zero leg twist!)
## 03. Realistic Woodland Stag close-up in Yanshan sunlit glade (Idle regal stance + antlers + photoreal fur!)
## 04. Epic Yanshan meadow trio: Shaoyu v2 + Realistic Stag (mid-stride/leap!) + Judy Hopps hopping together!

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V0992 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

func _aim(cam: Camera3D, from: Vector3, to: Vector3):
	cam.global_position = from
	cam.look_at(to, Vector3.UP)

func _initialize():
	call_deferred("_run")

func _run():
	var main = load("res://main.tscn").instantiate()
	main.qa_mode = true
	root.add_child(main)
	for _i in 14:
		await process_frame

	main.switch_map("yanshan")
	main.start_action(true, "normal")
	main.player.set_third_person(true, true)
	for _i in 12:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 46.0
	cam.near = 0.10
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true

	main.wildlife.frozen_for_capture = true
	main.paused = false
	main.hud.hide()

	# Place Shaoyu v2 on open sunny camp meadow facing south-east sunlight (+Z / +X)
	var sp := Vector3(14.6, float(main.Layout.fast_height(14.6, 25.4)), 25.4)
	main.player.global_position = sp
	main.player.yaw = PI - 0.25
	main.player.rotation = Vector3(0.0, PI - 0.25, 0.0)
	main.player.stance = 0
	for _i in 12:
		await physics_frame
	var fwd := Vector3(-sin(PI - 0.25), 0.0, -cos(PI - 0.25)).normalized()
	var rgt := Vector3(fwd.z, 0.0, -fwd.x).normalized()

	# Shot 01: Protagonist Shaoyu v2 front 3/4 in Rifle_LowReady (YS-04 rifle calibrated in both hands!)
	_aim(cam, sp + fwd * 2.30 + rgt * 0.68 + Vector3(0.0, 1.24, 0.0), sp + Vector3(0.0, 1.04, 0.0))
	await _snap("v0992_01_shaoyu_v2_front_3p.png")

	# Shot 02: Protagonist Shaoyu v2 Prone_Idle side 3/4 on flat camp lawn (verifying zero twisted legs + clean grass clearance!)
	var sp_flat := Vector3(14.2, float(main.Layout.fast_height(14.2, 23.6)), 23.6)
	main.player.global_position = sp_flat
	main.player.yaw = PI * 0.5
	main.player.stance = 2
	for _i in 22:
		await physics_frame
	_aim(cam, sp_flat + Vector3(0.45, 0.78, 2.25), sp_flat + Vector3(0.0, 0.28, 0.0))
	await _snap("v0992_02_shaoyu_v2_prone_3p.png")

	# Restore Shaoyu v2 to standing Rifle_LowReady on sunny meadow
	main.player.global_position = sp
	main.player.yaw = PI - 0.25
	main.player.stance = 0
	for _i in 14:
		await physics_frame
	main.paused = true

	# Find first deer & first rabbit
	var deer_a: Dictionary = {}
	var rab_a: Dictionary = {}
	for a in main.wildlife.animals:
		if str(a.kind) == "deer" and deer_a.is_empty():
			deer_a = a
		elif str(a.kind) == "rabbit" and rab_a.is_empty():
			rab_a = a

	# Shot 03: Realistic Woodland Stag sunny close-up (Idle regal stance!)
	var d_spot := Vector3(16.8, float(main.Layout.fast_height(16.8, 24.0)), 24.0)
	if not deer_a.is_empty():
		deer_a.pos = d_spot
		deer_a.root.position = d_spot
		deer_a.root.rotation = Vector3(0.0, PI * 0.62, 0.0)
		deer_a.visual.position = Vector3.ZERO
		deer_a.visual.rotation = Vector3.ZERO
		if is_instance_valid(deer_a.anim) and deer_a.anim.has_animation("Idle"):
			deer_a.anim.play("Idle")
			deer_a.anim.seek(0.6, true)
			deer_a.anim.pause()
	var df := Vector3(-sin(PI * 0.62), 0.0, -cos(PI * 0.62)).normalized()
	var dr := Vector3(df.z, 0.0, -df.x).normalized()
	_aim(cam, d_spot + df * 1.75 + dr * 2.15 + Vector3(0.0, 1.06, 0.0), d_spot + Vector3(0.0, 0.82, 0.0))
	await _snap("v0992_03_realistic_deer_closeup.png")

	# Shot 04: Epic Yanshan meadow trio — Shaoyu v2 + Realistic Stag (mid-stride Walk!) + Judy Hopps (mid-hop!)
	if not deer_a.is_empty():
		deer_a.root.rotation = Vector3(0.0, PI * 0.72, 0.0)
		if is_instance_valid(deer_a.anim) and deer_a.anim.has_animation("Walk"):
			deer_a.anim.play("Walk")
			deer_a.anim.seek(0.0, true)
			deer_a.anim.pause()
	if not rab_a.is_empty():
		var r_spot := Vector3(15.7, float(main.Layout.fast_height(15.7, 25.8)), 25.8)
		rab_a.pos = r_spot
		rab_a.root.position = r_spot
		rab_a.root.rotation = Vector3(0.0, PI - 0.18, 0.0)
		rab_a.visual.position = Vector3.ZERO
		rab_a.visual.rotation = Vector3.ZERO
		if is_instance_valid(rab_a.anim) and rab_a.anim.has_animation("Walk"):
			rab_a.anim.play("Walk")
			rab_a.anim.seek(9.0 / 24.0, true)
			rab_a.anim.pause()
	_aim(cam, Vector3(15.9, sp.y + 1.48, 29.8), Vector3(15.7, sp.y + 0.86, 24.8))
	await _snap("v0992_04_shaoyu_deer_judy_meadow.png")

	main.queue_free()
	await process_frame
	quit(0)
