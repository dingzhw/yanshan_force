extends SceneTree
## v0.9.9.5_dev1 Visual Audit Capture Suite (1280x720 — supports both Forward+ & GL Compatibility):
## Captures 9 key views proving:
##   01_mountain_exterior_aerial.png   — Forested mountain massif completely hiding the 41m cavern
##   02_bamboo_forecourt_mouth.png     — Bamboo forecourt opening into mountain cliff cave mouth ('洞口')
##   03_cave_throat_to_gallery.png     — Narrow entrance throat curving & widening into Skylight Mid-Gallery
##   04_mid_gallery_mural_flora.png    — Mid-Gallery Skylight sunbeam, West Mural & glowing cave wall flora
##   05_grand_hall_warden_patrol.png   — Vast 23.6m Grand Cavern Hall + 2.86m Minecraft-Warden patrolling + glow flora
##   06_warden_v2_xguard.png           — Close-up of 65-bone Minecraft-Warden in X-Guard arm-shield pose
##   07_warden_v2_exposed_roar.png     — Close-up of Minecraft-Warden roaring with arms wide open & blazing soul-heart
##   08_deep_yixiantian_rift.png       — Deepest '一线天' vertical fissure sunbeam + Dimensional Rift Wall + Jade Pool
##   09_codex_warden_portrait.png      — Lore Codex Cave Warden card showing 1:1 matching new official portrait

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
	var out_dir := OS.get_environment("TEMP").path_join("v0995_dev1_shots")
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
	game.profile_path_override = "user://qa-v0995-dev1-cap.json"
	if FileAccess.file_exists(game.profile_path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile_path_override))
	root.add_child(game)
	await wait_frames(12)

	var cam := Camera3D.new()
	cam.fov = 58.0
	game.add_child(cam)

	game.start_action(true, "normal")
	await wait_frames(8)
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.hide()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.hide()

	var cave_c: Vector3 = game.Layout.YANXIA_CAVE_CENTER
	var hall_c: Vector3 = game.Layout.YANXIA_CAVE_HALL
	var fy: float = float(game.Layout.CAVE_FLOOR_Y) + 0.026

	# Keep player parked peacefully inside cavern hall during interior shots
	game.player.position = Vector3(hall_c.x, fy, hall_c.z + 9.0)
	game.player.velocity = Vector3.ZERO
	game.player.stance = game.player.STANCE_CROUCH

	# Shot 01: Exterior mountain massif aerial 3/4 view proving entire 41m cavern is hidden inside mountain!
	cam.current = true
	cam.fov = 54.0
	cam.global_position = Vector3(cave_c.x + 34.0, fy + 26.0, cave_c.z + 24.0)
	cam.look_at(Vector3(cave_c.x - 4.0, fy + 10.5, cave_c.z - 18.0), Vector3.UP)
	await grab(out_dir, pfx + "01_mountain_exterior_aerial.png")

	# Shot 02: Ground view from Bamboo-Stone Maze forecourt looking straight at mountain cliff cave mouth ('洞口') & plaque!
	cam.fov = 66.0
	cam.global_position = Vector3(cave_c.x + 0.05, fy + 1.85, cave_c.z + 10.6)
	cam.look_at(Vector3(cave_c.x, fy + 2.75, cave_c.z + 6.5), Vector3.UP)
	await grab(out_dir, pfx + "02_bamboo_forecourt_mouth.png")

	# Shot 03: Inside narrow entrance throat looking north-west into expanding Skylight Mid-Gallery!
	cam.fov = 66.0
	cam.global_position = Vector3(cave_c.x - 0.15, fy + 1.85, cave_c.z + 4.4)
	cam.look_at(Vector3(cave_c.x - 2.6, fy + 2.8, cave_c.z - 12.0), Vector3.UP)
	await grab(out_dir, pfx + "03_cave_throat_to_gallery.png")

	# Shot 04: Mid-Gallery showcasing Skylight sunbeam, West Wall Mural ('烟山耕读') & glowing wall flora!
	cam.fov = 66.0
	cam.global_position = Vector3(cave_c.x + 1.1, fy + 2.35, cave_c.z - 5.2)
	cam.look_at(Vector3(cave_c.x - 6.8, fy + 2.55, cave_c.z - 11.4), Vector3.UP)
	await grab(out_dir, pfx + "04_mid_gallery_mural_flora.png")

	# Shot 05: Vast 23.6m Grand Cavern Hall — Minecraft-Warden patrolling amidst pillars, glow flora & '一线天'!
	var cw = game.cave_warden
	cw.reset()
	var cw_stage := Vector3(hall_c.x + 0.5, fy, hall_c.z + 1.0)
	cw.root_node.position = cw_stage
	cw.root_node.rotation = Vector3(0.0, 0.28, 0.0)
	cw.state = "patrol"
	cw.snap_articulation_for_pose()
	cam.fov = 68.0
	cam.global_position = Vector3(hall_c.x + 1.8, fy + 3.2, hall_c.z + 10.6)
	cam.look_at(Vector3(hall_c.x - 1.2, fy + 2.4, hall_c.z - 4.0), Vector3.UP)
	await grab(out_dir, pfx + "05_grand_hall_warden_patrol.png")

	# Shot 06: Close-up of 65-bone Minecraft-Warden in X-Guard defensive pose!
	cw.root_node.position = cw_stage
	cw.root_node.rotation = Vector3(0.0, 0.24, 0.0)
	cw.state = "hunt"
	cw.stealth_quiet_timer = 0.0
	cw.set_guard_arms(true, 6.0)
	cw.snap_articulation_for_pose()
	cam.fov = 50.0
	cam.global_position = cw_stage + Vector3(1.15, 1.82, 4.45)
	cam.look_at(cw_stage + Vector3(0.0, 1.56, 0.0), Vector3.UP)
	await grab(out_dir, pfx + "06_warden_v2_xguard.png")

	# Shot 07: Close-up of Minecraft-Warden roaring with arms flung wide open & blazing soul-heart!
	cw.root_node.position = cw_stage
	cw.root_node.rotation = Vector3(0.0, 0.20, 0.0)
	cw.state = "patrol"
	cw.force_open_arms(4.0)
	cw.snap_articulation_for_pose()
	await grab(out_dir, pfx + "07_warden_v2_exposed_roar.png")

	# Shot 08: Deepest '一线天' vertical fissure sunbeam + Dimensional Rift Wall + Jade Spring Pool!
	cw.root_node.position = Vector3(hall_c.x + 6.5, fy, hall_c.z + 4.5)
	cam.fov = 66.0
	cam.global_position = Vector3(hall_c.x - 1.8, fy + 2.6, hall_c.z - 1.5)
	cam.look_at(Vector3(hall_c.x - 0.8, fy + 2.8, hall_c.z - 11.2), Vector3.UP)
	await grab(out_dir, pfx + "08_deep_yixiantian_rift.png")

	# Shot 09: Lore Codex Cave Warden detail showing 1:1 matching new official portrait!
	game._end_run(false)
	await wait_frames(4)
	game.rules.inc_lore_stat("warden_defeats", 1)
	game.lore_codex.open("mistbound")
	await wait_frames(4)
	game.lore_codex.open_character("cave_warden")
	await grab(out_dir, pfx + "09_codex_warden_portrait.png")

	game.queue_free()
	await process_frame
	print("CAPTURE_V0995_DEV1_DONE")
	quit(0)
