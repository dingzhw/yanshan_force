extends SceneTree
## v0.9.9.5 Visual Audit Capture Suite (1280x720 — supports both Forward+ & GL Compatibility via --backend-tag):
## Captures:
##   01_chen_guide_closeup.png       — Weathered middle-aged Chen Guide front close-up in Yanshan Camp
##   02_mistbound_troopers.png       — Upgraded woven bamboo-hat ('斗笠') Mistbound Assault + Sniper side-by-side
##   03_cave_warden_patrol.png       — Sculptural Cave Warden in calm sandstone-led patrol (restrained rune glow)
##   04_cave_warden_xguard.png       — Cave Warden X-guard closed shoulder/hip joints
##   05_cave_warden_exposed.png      — Cave Warden wall-slam exposed core blazing gold-cyan glow hierarchy
##   06_multitag_yanshan_front.png   — 4 stacked soldiers with mixed long/short phrases (front view + tethers)
##   07_multitag_yanshan_strafe.png  — Same 4 stacked soldiers from lateral strafe angle
##   08_multitag_ahsarah_desert.png  — 4 soldiers with long phrases against sunlit Ahsarah desert sand dunes
##   09_camp_wangdao_lighting.png    — Camp -> Wangdao over-the-shoulder view (harmonized grass & decluttered labels)
##   10_codex_mistbound_portrait.png — Lore Codex Mistbound Assault detail showing repainted bamboo-hat portrait

const MainScene = preload("res://main.tscn")
const Soldier = preload("res://scripts/word_soldier.gd")

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
	var out_dir := OS.get_environment("TEMP").path_join("v0995_audit_shots")
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
	game.profile_path_override = "user://qa-v0995-capture.json"
	if FileAccess.file_exists(game.profile_path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.profile_path_override))
	root.add_child(game)
	await wait_frames(12)

	var cam := Camera3D.new()
	cam.fov = 52.0
	game.add_child(cam)

	# 1. Start Normal Combat on Yanshan Base
	game.start_action(true, "normal")
	await wait_frames(8)
	# Hide player 1P viewmodel during studio close-up camera shots so hands never intrude in frame!
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.hide()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.hide()

	# Shot 01: Chen Guide close-up in Yanshan Camp
	var chen_n: Node3D = game.rangers.camp_npc_node
	if is_instance_valid(chen_n):
		var cpos: Vector3 = chen_n.global_position
		var cfwd: Vector3 = chen_n.global_transform.basis.z.normalized()
		cam.current = true
		cam.global_position = cpos + cfwd * 1.65 + Vector3(0.28, 1.46, 0.0)
		cam.look_at(cpos + Vector3(0.0, 1.38, 0.0), Vector3.UP)
		await grab(out_dir, pfx + "01_chen_guide_closeup.png")

	# Shot 02: Mistbound Assault + Sniper side-by-side close-up (showcase woven bamboo hats, visors, rifles & folded uniforms!)
	var assault_s = null
	var sniper_s = null
	for zid in game.combat.troops.keys():
		for s in game.combat.troops[zid]:
			if not is_instance_valid(s) or s.defeated:
				continue
			if s.archetype == Soldier.Archetype.ASSAULT_BOT and assault_s == null:
				assault_s = s
			elif s.archetype == Soldier.Archetype.SNIPER_GUARD and sniper_s == null:
				sniper_s = s
	if assault_s != null and sniper_s != null:
		game.combat.disengage_active_camp(false)
		var stage_c: Vector3 = game.Layout.on_ground(Vector3(16.0, 0.0, 10.0))
		assault_s.set_physics_process(false)
		sniper_s.set_physics_process(false)
		assault_s.position = game.Layout.on_ground(stage_c + Vector3(-0.78, 0.0, 0.0))
		sniper_s.position = game.Layout.on_ground(stage_c + Vector3(0.78, 0.0, 0.0))
		assault_s.rotation = Vector3(0.0, 0.20, 0.0)
		sniper_s.rotation = Vector3(0.0, -0.20, 0.0)
		assault_s.shield_area.hide()
		sniper_s.shield_area.hide()
		assault_s.hp_bar_root.hide()
		sniper_s.hp_bar_root.hide()
		cam.current = true
		cam.global_position = stage_c + Vector3(0.0, 1.46, 3.15)
		cam.look_at(stage_c + Vector3(0.0, 1.24, 0.0), Vector3.UP)
		await grab(out_dir, pfx + "02_mistbound_troopers.png")
		assault_s.hp_bar_root.show()
		sniper_s.hp_bar_root.show()

	# Shots 03, 04, 05: Cave Warden Patrol (calm sandstone), X-Guard (closed joints), Exposed Core (blazing glow!)
	var cw = game.cave_warden
	if is_instance_valid(cw):
		cw.reset()
		var cc: Vector3 = cw._cave_center()
		var cfy: float = cw._cave_floor_y()
		var cw_stage: Vector3 = Vector3(cc.x, cfy, cc.z + 3.2)
		cw.root_node.position = cw_stage
		cw.root_node.rotation = Vector3.ZERO
		# Place player cleanly inside cave so territory leash doesn't override X-guard / Exposed poses!
		game.player.position = Vector3(cc.x, cfy, cc.z + 9.0)
		game.player.velocity = Vector3.ZERO
		game.player.stance = game.player.STANCE_CROUCH
		cw.snap_articulation_for_pose()
		cam.current = true
		cam.global_position = cw_stage + Vector3(0.55, 1.66, 4.35)
		cam.look_at(cw_stage + Vector3(0.0, 1.44, 0.0), Vector3.UP)
		await grab(out_dir, pfx + "03_cave_warden_patrol.png")

		cw.root_node.position = cw_stage
		cw.root_node.rotation = Vector3.ZERO
		cw.state = "hunt"
		cw.stealth_quiet_timer = 0.0
		cw.set_guard_arms(true, 6.0)
		cw.snap_articulation_for_pose()
		await grab(out_dir, pfx + "04_cave_warden_xguard.png")

		cw.root_node.position = cw_stage
		cw.root_node.rotation = Vector3.ZERO
		cw.state = "patrol"
		cw.force_open_arms(3.0)
		cw.snap_articulation_for_pose()
		await grab(out_dir, pfx + "05_cave_warden_exposed.png")

	# Restore player viewmodel & body for gameplay shots 06..09!
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.show()
	if is_instance_valid(game.player.player_body):
		game.player.player_body.show()
	game.player.set_stance(game.player.STANCE_STAND)

	# Shots 06 & 07: 4 Stacked Multi-Target Overhead Word Tags (Front + Lateral Strafe) in Yanshan!
	cam.current = false
	game.player.camera.current = true
	game.player.set_third_person(false, true)
	game.combat.engage_camp(0)
	var z0_troops: Array = game.combat.troops.get(0, [])
	var phrases := ["Mid-Autumn Festival", "Spring Festival", "Christmas Eve", "apple"]
	var anchor0: Vector3 = game.Layout.on_ground(Vector3(0.0, 0.0, -34.0))
	for i in z0_troops.size():
		var ts = z0_troops[i]
		ts.set_physics_process(false)
		ts.position = game.Layout.on_ground(anchor0 + Vector3(float(i) * 0.65 - 0.95, 0.0, -float(i) * 1.45))
		ts.rotation = Vector3.ZERO
		ts.show_word(phrases[i % phrases.size()], false)
	if z0_troops.size() > 0:
		game.answer_index = int(z0_troops[0].option)
	game.player.position = game.Layout.on_ground(anchor0 + Vector3(0.0, 0.0, 11.5)) + Vector3(0.0, 0.06, 0.0)
	game.player.yaw = 0.0
	game.player.pitch = 0.04
	await wait_frames(4)
	game.combat.resolve_overhead_tag_overlaps(0.0)
	await grab(out_dir, pfx + "06_multitag_yanshan_front.png")

	# Strafe right + look back diagonally across stacked squad
	game.player.position = game.Layout.on_ground(anchor0 + Vector3(5.2, 0.0, 9.2)) + Vector3(0.0, 0.06, 0.0)
	var d_st: Vector3 = (anchor0 + Vector3(0.0, 1.8, -1.5)) - game.player.camera.global_position
	game.player.yaw = atan2(-d_st.x, -d_st.z)
	game.player.pitch = atan2(d_st.y, Vector2(d_st.x, d_st.z).length())
	await wait_frames(4)
	game.combat.resolve_overhead_tag_overlaps(0.0)
	await grab(out_dir, pfx + "07_multitag_yanshan_strafe.png")

	# Shot 09: Camp -> Wangdao Pavilion over-the-shoulder (open sunlit meadow outside tent — check grass cohesion & label declutter!)
	game.combat.disengage_active_camp(false)
	game.player.set_stance(game.player.STANCE_STAND)
	game.player.set_third_person(true, true)
	game.player.position = game.Layout.on_ground(Vector3(2.5, 0.0, 14.5)) + Vector3(0.0, 0.06, 0.0)
	var wd_pt: Vector3 = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION) + Vector3(0.0, 3.0, 0.0)
	var d_wd: Vector3 = wd_pt - (game.player.position + Vector3(0.0, 1.6, 0.0))
	game.player.yaw = atan2(-d_wd.x, -d_wd.z)
	game.player.pitch = 0.01
	await grab(out_dir, pfx + "09_camp_wangdao_lighting.png")

	# Shot 08: Ahsarah Desert bright sunlight 4-target long-phrase legibility & anti-overlap!
	game._end_run(false)
	game.rules.unlock_map("ahsarah")
	game.switch_map("ahsarah")
	await wait_frames(6)
	game.start_action(true, "normal")
	await wait_frames(6)
	game.player.set_third_person(false, true)
	game.combat.engage_camp(0)
	var ah_troops: Array = game.combat.troops.get(0, [])
	var ah_anchor: Vector3 = game.active_layout.on_ground(game.combat.zone_center(0))
	for i in ah_troops.size():
		var ts2 = ah_troops[i]
		ts2.set_physics_process(false)
		ts2.position = game.active_layout.on_ground(ah_anchor + Vector3(float(i) * 0.72 - 1.05, 0.0, -float(i) * 1.50))
		ts2.rotation = Vector3.ZERO
		ts2.show_word(phrases[i % phrases.size()], false)
	if ah_troops.size() > 0:
		game.answer_index = int(ah_troops[0].option)
	game.player.position = game.active_layout.on_ground(ah_anchor + Vector3(0.0, 0.0, 11.8)) + Vector3(0.0, 0.08, 0.0)
	game.player.yaw = 0.0
	game.player.pitch = 0.04
	await wait_frames(4)
	game.combat.resolve_overhead_tag_overlaps(0.0)
	await grab(out_dir, pfx + "08_multitag_ahsarah_desert.png")

	# Shot 10: Lore Codex Mistbound Assault Trooper detail showing repainted bamboo-hat portrait!
	game._end_run(false)
	await wait_frames(4)
	game.rules.inc_lore_stat("camps_cleared_yanshan", 1)
	game.lore_codex.open("mistbound")
	await wait_frames(4)
	game.lore_codex.open_character("mistbound_soldier")
	await grab(out_dir, pfx + "10_codex_mistbound_portrait.png")

	game.queue_free()
	await process_frame
	print("CAPTURE_V0995_DONE")
	quit(0)
