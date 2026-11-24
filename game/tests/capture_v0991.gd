extends SceneTree
## v0.9.9.1 Visual Audit Capture Suite (1280x720 GL Compatibility):
## 01. Sunny front 3/4 close-up of Judy Hopps on Yanshan camp meadow (Idle alert stance, eyes/badge/ears/uniform!)
## 02. Dynamic mid-air bunny hop (Walk hop apex — ears swept back, knees tucked joyfully above Yanshan grass!)
## 03. 3rd-person protagonist Shaoyu standing beside hopping Judy Hopps on Yanshan lawn (scale & lighting harmony!)

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V0991 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

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
	main.player.set_third_person(false, true)
	for _i in 12:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 46.0
	cam.near = 0.10
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true

	# Freeze wildlife AI during photo shoot and pick Rabbit #0 on open sunny meadow
	main.wildlife.frozen_for_capture = true
	main.paused = true
	main.hud.hide()
	var rb: Dictionary = main.wildlife.animals[0]
	var spot := Vector3(15.5, float(main.Layout.fast_height(15.5, 25.5)), 25.5)
	rb.pos = spot
	rb.root.position = spot
	# Face +Z/+X (towards camera & sunlight in south-east!) -> local -Z faces +Z when rotation.y = PI
	rb.root.rotation = Vector3(0.0, PI - 0.25, 0.0)
	rb.visual.position = Vector3.ZERO
	rb.visual.rotation = Vector3.ZERO
	var anim: AnimationPlayer = rb.anim
	var judy_fwd := Vector3(-sin(PI - 0.25), 0.0, -cos(PI - 0.25)).normalized()
	var judy_right := Vector3(judy_fwd.z, 0.0, -judy_fwd.x).normalized()

	# Shot 01: Front 3/4 Close-up in Idle stance on sunny Yanshan camp meadow
	if is_instance_valid(anim) and anim.has_animation("Idle"):
		anim.play("Idle")
		anim.seek(0.45, true)
		anim.pause()
	_aim(cam, spot + judy_fwd * 1.48 + judy_right * 0.34 + Vector3(0.0, 0.66, 0.0), spot + Vector3(0.0, 0.54, 0.0))
	await _snap("v0991_01_judy_meadow_closeup.png")

	# Shot 02: Dynamic mid-air bunny hop (Walk apex frame 9/24 = 0.375s!) from front-side angle
	rb.root.rotation = Vector3(0.0, PI * 0.68, 0.0)
	var jf2 := Vector3(-sin(PI * 0.68), 0.0, -cos(PI * 0.68)).normalized()
	var jr2 := Vector3(jf2.z, 0.0, -jf2.x).normalized()
	if is_instance_valid(anim) and anim.has_animation("Walk"):
		anim.play("Walk")
		anim.seek(9.0 / 24.0, true)
		anim.pause()
	_aim(cam, spot + jf2 * 1.15 + jr2 * 1.68 + Vector3(0.0, 0.72, 0.0), spot + Vector3(0.0, 0.56, 0.0))
	await _snap("v0991_02_judy_hopping_action.png")

	# Shot 03: Scale comparison — 3rd-person protagonist Shaoyu beside hopping Judy Hopps on sunny Yanshan lawn!
	main.player.set_third_person(true, true)
	var p_spot := Vector3(13.8, float(main.Layout.fast_height(13.8, 25.5)), 25.5)
	main.player.global_position = p_spot
	main.player.rotation = Vector3(0.0, PI - 0.15, 0.0)
	rb.root.rotation = Vector3(0.0, PI - 0.25, 0.0)
	if is_instance_valid(anim) and anim.has_animation("Run"):
		anim.play("Run")
		anim.seek(0.0, true)
		anim.pause()
	# Also bring a second Judy rabbit nearby in Idle pose for lively meadow scene!
	if main.wildlife.animals.size() > 1:
		var rb2: Dictionary = main.wildlife.animals[1]
		var s2 := Vector3(16.7, float(main.Layout.fast_height(16.7, 24.4)), 24.4)
		rb2.pos = s2
		rb2.root.position = s2
		rb2.root.rotation = Vector3(0.0, PI + 0.32, 0.0)
		rb2.visual.position = Vector3.ZERO
		rb2.visual.rotation = Vector3.ZERO
		if is_instance_valid(rb2.anim) and rb2.anim.has_animation("Idle"):
			rb2.anim.play("Idle")
			rb2.anim.seek(0.2, true)
			rb2.anim.pause()
	_aim(cam, Vector3(15.2, p_spot.y + 1.32, 29.4), Vector3(15.0, p_spot.y + 0.72, 25.2))
	await _snap("v0991_03_judy_camp_scale_compare.png")

	main.queue_free()
	await process_frame
	quit(0)
