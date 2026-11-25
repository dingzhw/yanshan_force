extends SceneTree
## v0.9.9.5_dev2 Visual Audit Capture Suite (1280x720 — Forward+ & GL Compatibility):
##   01_camp_chen_guide_closeup.png   — Normal Camp Liaison Chen Guide front bust closeup
##   02_camp_chen_guide_fullbody.png  — Normal Camp full-body scale & stance check beside Shaoyu
##   03_prologue_chen_guide.png       — Prologue Chapter Chen Guide unified appearance check
##   04_codex_chen_guide_portrait.png — Lore Codex Chen Guide card with 1:1 matching portrait

const MainScene = preload("res://main.tscn")

func wait_frames(n: int = 8):
	for _i in n:
		await process_frame
		await physics_frame

func grab(out_dir: String, fname: String):
	await wait_frames(8)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		var path := out_dir.path_join(fname)
		var err := img.save_png(path)
		print("CAPTURED ", path, " ok=", (err == OK), " size=", img.get_size())

func _initialize():
	call_deferred("_run")

func _run():
	var out_dir := OS.get_environment("TEMP").path_join("v0995_dev2_shots")
	var tag := ""
	var uargs := OS.get_cmdline_user_args()
	for idx in uargs.size():
		if uargs[idx] == "--out-dir" and idx + 1 < uargs.size():
			out_dir = uargs[idx + 1]
		elif uargs[idx] == "--backend-tag" and idx + 1 < uargs.size():
			tag = uargs[idx + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var pfx := (tag + "_") if tag != "" else ""

	var game = MainScene.instantiate()
	game.qa_mode = true
	game.profile_path_override = "user://qa-v0995-dev2-cap.json"
	if FileAccess.file_exists(game.profile_path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile_path_override))
	root.add_child(game)
	await wait_frames(12)

	var cam := Camera3D.new()
	cam.fov = 46.0
	game.add_child(cam)

	# 1) Normal Camp Liaison Chen Guide closeup (wait 24 frames so Forward+ finishes compiling alpha-mask hair shader!)
	game.start_action(true, "normal")
	await wait_frames(24)
	var npc: Node3D = game.rangers.camp_npc_node
	var npc_pos: Vector3 = npc.global_position
	var npc_fwd: Vector3 = npc.global_transform.basis.z.normalized()
	var npc_right: Vector3 = npc.global_transform.basis.x.normalized()
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.hide()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.hide()
	cam.current = true
	cam.fov = 42.0
	cam.global_position = npc_pos + npc_fwd * 1.48 + npc_right * 0.14 + Vector3(0.0, 1.56, 0.0)
	cam.look_at(npc_pos + Vector3(0.0, 1.46, 0.0), Vector3.UP)
	await grab(out_dir, pfx + "01_camp_chen_guide_closeup.png")

	# 2) Normal Camp full-body view with protagonist Shaoyu standing beside Chen Guide!
	if is_instance_valid(game.player.player_body):
		game.player.set_third_person(true, true)
		game.player.player_body.show()
	game.player.position = npc_pos + npc_right * 1.15 + npc_fwd * 0.10
	game.player.yaw = npc.rotation.y
	game.player.velocity = Vector3.ZERO
	await wait_frames(8)
	cam.current = true
	cam.fov = 48.0
	cam.global_position = npc_pos + npc_fwd * 3.15 + npc_right * 0.55 + Vector3(0.0, 1.24, 0.0)
	cam.look_at(npc_pos + npc_right * 0.50 + Vector3(0.0, 1.02, 0.0), Vector3.UP)
	await grab(out_dir, pfx + "02_camp_chen_guide_fullbody.png")

	# 3) Prologue Chapter Chen Guide unified check
	game._end_run(false)
	await wait_frames(4)
	game.start_prologue_chapter(false)
	await wait_frames(10)
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.hide()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.hide()
	var pnpc: Node3D = game.prologue.npc_node
	var ppos: Vector3 = pnpc.global_position
	var pfwd: Vector3 = pnpc.global_transform.basis.z.normalized()
	var pright: Vector3 = pnpc.global_transform.basis.x.normalized()
	cam.current = true
	cam.fov = 46.0
	cam.global_position = ppos + pfwd * 2.15 + pright * 0.18 + Vector3(0.0, 1.40, 0.0)
	cam.look_at(ppos + Vector3(0.0, 1.28, 0.0), Vector3.UP)
	await grab(out_dir, pfx + "03_prologue_chen_guide.png")

	# 4) Lore Codex Chen Guide card showing 1:1 matching new official portrait & updated dossier!
	game._end_run(false)
	await wait_frames(4)
	game.rules.profile["prologue_completed"] = true
	game.rules.inc_lore_stat("bounties", 1)
	game.lore_codex.open("rangers")
	await wait_frames(4)
	game.lore_codex.open_character("chen_guide")
	await grab(out_dir, pfx + "04_codex_chen_guide_portrait.png")

	game.queue_free()
	await process_frame
	print("CAPTURE_V0995_DEV2_DONE")
	quit(0)
