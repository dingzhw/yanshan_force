extends SceneTree
## v0.8.6 Visual Capture Suite (9 crisp 1280x720 shots):
## 1. v086_01_misty_mountains_wangdao.png   — Cloud-wreathed Qinglu distant mountains, 3D peaks ring & drifting cloud-sea belts from Wangdao overlook
## 2. v086_02_wangdao_sign_and_scenery.png  — Fixed outward-facing Wangdao Pavilion signboard (NW trail view) + Wangdao timber trim & stone lanterns
## 3. v086_03_jiangnan_watchtower.png       — Handcrafted Jiangnan flying-eave Watchtower + spiralling parkour catwalk + misty mountains
## 4. v086_04_tea_pavilion_and_arch.png     — Upgraded East Tea-Hill Pavilion + terraced tea hedges + stone bench + stone lanterns
## 5. v086_05_wildlife_expansion.png        — All 4 new skeletal-animated wildlife species (Sika Deer, Golden Pheasant, Pond Turtle, Butterfly)
## 6. v086_06_display_stand_8slot.png       — Camp 2-tier 8-slot 3D Display Stand showcasing 8 brand-new v0.8.6 museum collectibles
## 7. v086_07_gilded_rifle_and_arch.png     — First-person Gilded Jade-Gold YS-04 Rifle + under-optic charm looking through Mountain Arch Gate
## 8. v086_08_overlord_orbit_shields.png    — Articulated 5-part Confidential Boss '玄铁词尊' + spinning Dharma halo + Round-2 orbiting golden shields
## 9. v086_09_ultimate_mirror_yanshan.png   — Ultimate「天地万象」with giant Inverted Mirror Yanshan Mountain descending over Cloud-Top Arena!

var game

func _initialize():
	call_deferred("run")

func frames(count: int):
	for _i in count:
		await process_frame
		await physics_frame

func look_from_to(cam_origin: Vector3, target: Vector3):
	game.player.velocity = Vector3.ZERO
	game.player.position = cam_origin
	await frames(2)
	var d: Vector3 = target - game.player.camera.global_position
	game.player.yaw = atan2(-d.x, -d.z)
	game.player.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
	await frames(6)

func clear_hud_popups():
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	if is_instance_valid(game.achievements):
		game.achievements.banner_queue.clear()
		game.achievements.banner_active = {}
		game.achievements.banner_panel.hide()

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await frames(6)

	# Grant veteran sinks & charm for showcase shots (gilded_skin + display_expand + fox bell charm)
	game.rules.profile.owned = ["red_dot", "gilded_skin", "backpack", "display_expand", "safebox_upgrade", "ranger_mastery"]
	game.rules.ensure_equipped()
	game.rules.profile.display_stand = [
		"金瓯永固杯", "翠玉白菜", "传国和氏璧玉玺", "烟山天穹全息棱镜",
		"鎏金凤冠", "良渚神徽玉琮", "曾侯乙式编钟", "青绿山水手卷"
	]
	for t_name in game.rules.profile.display_stand:
		if not (t_name in game.rules.profile.collection):
			game.rules.profile.collection.append(t_name)
	game.refresh_camp_display_stand()
	game.achievements.record_stat("fox", 1, true)
	game.achievements.equip_charm("charm_fox_bell")

	game.start_action(true, "normal")
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	game.player.select_weapon(0)
	game.player.aiming = false
	await frames(6)

	# 1) Cloud-wreathed Qinglu distant mountains + 3D peaks ring + drifting cloud-sea belts from Wangdao overlook
	var wd_pos: Vector3 = game.landscape.wangdao_deck_pos + Vector3(0.0, 0.14, -0.35)
	game.player.position = wd_pos
	game.player.yaw = PI + 0.16
	game.player.pitch = -0.05
	await frames(8)
	clear_hud_popups()
	await frames(2)
	game._capture("v086_01_misty_mountains_wangdao.png")

	# 2) Fixed outward-facing Wangdao Pavilion signboard seen directly from NW approaching trail!
	var wd_sign: Node3D = game.landscape.find_child("WangdaoSignpost", true, false) as Node3D
	if wd_sign != null:
		var fwd_s: Vector3 = wd_sign.global_transform.basis.z.normalized()
		var sign_cam: Vector3 = game.Layout.on_ground(wd_sign.global_position + fwd_s * 4.4 + Vector3(-0.3, 0.0, 0.2)) + Vector3(0.0, 0.14, 0.0)
		await look_from_to(sign_cam, wd_sign.global_position + Vector3(0.55, 1.55, 0.40))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_02_wangdao_sign_and_scenery.png")

	# 10) Hero close-up of completely rebuilt unified Wangdao Pavilion (flying eaves, solid terrace, flush corner lanterns, stairs & plaques!)
	var wd_pav: Node3D = game.landscape.find_child("WangdaoPavilion", true, false) as Node3D
	if wd_pav != null:
		var wd_hero_cam: Vector3 = game.Layout.on_ground(Vector3(46.2, 0.0, 34.4)) + Vector3(0.0, 2.2, 0.0)
		await look_from_to(wd_hero_cam, Vector3(57.7, game.landscape.wangdao_deck_pos.y + 1.55, 27.9))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_10_wangdao_pavilion_rebuilt.png")

	# 11) Normal Mode Boss '雾隐先锋·铁面词卫' Phase 3 '三盾困阵' (3 holographic word shields + glowing chest core!)
	var center2: Vector3 = game.combat.zone_center(2)
	game.combat.engage_camp(2)
	var nb = game.combat.boss_unit
	if is_instance_valid(nb) and not nb.is_skyfall_overlord:
		for s2 in game.combat.troops[2]:
			s2.set_physics_process(false)
			if s2 != nb:
				s2.hide()
		nb.position = game.Layout.on_ground(center2 + Vector3(0.0, 0.0, -1.8))
		nb.rotation = Vector3.ZERO
		nb.hp = 180
		nb.boss_phase = 1
		nb.configure_vanguard_shields(game.combat._build_wave_words(3), 3)
		nb.expose_boss_core(2.6)
		game.combat.zone_prompt_option[2] = nb.option
		game.answer_index = nb.option
		game.question = nb.expected_vanguard_word()
		game.combat.show_question()
		await look_from_to(game.Layout.on_ground(center2 + Vector3(0.0, 0.0, 6.2)) + Vector3(0.0, 0.14, 0.0), nb.global_position + Vector3(0.0, 1.95, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_11_normal_boss_three_shields.png")
	game.combat.disengage_active_camp(false)

	# 12) Cave Warden '古洞循音石卫' charging 22m Focused Anti-Sniper Sonic Lance inside Yanxia Cave!
	var cw = game.cave_warden
	if is_instance_valid(cw):
		cw.reset()
		var cc: Vector3 = game.Layout.YANXIA_CAVE_CENTER
		var cfy: float = float(game.Layout.CAVE_FLOOR_Y) + 0.03
		cw.root_node.position = Vector3(cc.x, cfy, cc.z + 1.2)
		cw.root_node.rotation = Vector3.ZERO
		cw.state = "hunt"
		cw.set_guard_arms(true, 4.2)
		cw.snap_articulation_for_pose()
		cw.start_sonic_lance(Vector3(cc.x + 1.1, cfy, cc.z + 8.6))
		await look_from_to(Vector3(cc.x - 1.6, cfy + 0.12, cc.z + 8.8), cw.root_node.position + Vector3(0.0, 1.55, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_12_warden_sonic_lance.png")
		cw.reset()

	# 13) Yanxia Cave '寒潭茶灶与先民竹简' live random 175-pack English word spelling challenge UI!
	for enode in game.exploration.nodes:
		if str(enode.get_meta("explore_id", "")) == "cave_hearth":
			game.exploration.open(enode)
			await frames(4)
			game._capture("v086_13_heritage_random_spelling.png")
			game.exploration.close()
			break

	# 3) Upgraded handcrafted Jiangnan flying-eave Watchtower + parkour catwalk + misty mountains (clear of NW camp!)
	var tw: Node3D = game.get_node_or_null("JiangnanWatchtower") as Node3D
	if tw != null:
		var tw_cam: Vector3 = game.Layout.on_ground(tw.global_position + Vector3(-9.5, 0.0, 9.8)) + Vector3(0.0, 0.15, 0.0)
		await look_from_to(tw_cam, tw.global_position + Vector3(0.0, 4.3, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_03_jiangnan_watchtower.png")

	# 4) Upgraded East Tea-Hill Pavilion + terraced tea hedges + stone bench + lanterns
	var tea_pav: Node3D = game.landscape.get_node_or_null("TeaHillPavilion") as Node3D
	if tea_pav != null:
		var tea_cam: Vector3 = game.Layout.on_ground(tea_pav.global_position + Vector3(-9.2, 0.0, 7.6)) + Vector3(0.0, 0.15, 0.0)
		await look_from_to(tea_cam, tea_pav.global_position + Vector3(0.0, 1.85, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_04_tea_pavilion_and_arch.png")

	# 5) Wildlife expansion showcase: stage 1 Sika Deer, 1 Golden Pheasant, 1 Pond Turtle & 2 Butterflies in sunny creek clearing!
	var stage_base := Vector3(14.5, 0.0, 16.5)
	var by_kind := {}
	for a in game.wildlife.animals:
		if a.kind in ["deer", "pheasant", "turtle", "butterfly"] and not by_kind.has(a.kind):
			by_kind[a.kind] = a
	if by_kind.has("deer"):
		var d_a: Dictionary = by_kind["deer"]
		var dp: Vector3 = game.Layout.on_ground(stage_base + Vector3(-1.30, 0.0, -2.55))
		d_a.root.position = dp
		d_a.root.rotation.y = 2.25
	if by_kind.has("pheasant"):
		var ph_a: Dictionary = by_kind["pheasant"]
		var php: Vector3 = game.Layout.on_ground(stage_base + Vector3(0.35, 0.0, -2.25))
		ph_a.root.position = php
		ph_a.root.rotation.y = -0.82
	if by_kind.has("turtle"):
		var tu_a: Dictionary = by_kind["turtle"]
		var tup: Vector3 = game.Layout.on_ground(stage_base + Vector3(-0.32, 0.0, -1.65))
		tu_a.root.position = tup
		tu_a.root.rotation.y = 0.52
	if by_kind.has("butterfly"):
		var bf_a: Dictionary = by_kind["butterfly"]
		var bfp: Vector3 = game.Layout.on_ground(stage_base + Vector3(-0.18, 0.0, -1.95)) + Vector3(0.0, 0.92, 0.0)
		bf_a.root.position = bfp
		bf_a.root.rotation.y = 0.28
	var wild_cam: Vector3 = game.Layout.on_ground(stage_base + Vector3(0.25, 0.0, 1.65)) + Vector3(0.0, 0.14, 0.0)
	await look_from_to(wild_cam, game.Layout.on_ground(stage_base + Vector3(0.0, 0.0, -2.1)) + Vector3(0.0, 0.72, 0.0))
	clear_hud_popups()
	await frames(2)
	game._capture("v086_05_wildlife_expansion.png")

	# 6) Camp 2-Tier 8-Slot 3D Display Stand showcasing 8 new v0.8.6 museum collectibles!
	var stand: Node3D = game.camp_display_stand
	if is_instance_valid(stand):
		var st_fwd: Vector3 = stand.global_transform.basis.z.normalized()
		var st_cam: Vector3 = game.Layout.on_ground(stand.global_position + st_fwd * 3.15) + Vector3(0.0, 0.12, 0.0)
		await look_from_to(st_cam, stand.global_position + Vector3(0.0, 1.38, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_06_display_stand_8slot.png")

	# 7) Gilded Jade-Gold YS-04 Rifle + under-optic charm looking through Forest Mountain Arch Gate!
	var arch_f: Node3D = game.landscape.get_node_or_null("TrailArchGate_Forest") as Node3D
	if arch_f != null:
		var arch_cam: Vector3 = game.Layout.on_ground(arch_f.global_position + Vector3(1.2, 0.0, 8.8)) + Vector3(0.0, 0.15, 0.0)
		await look_from_to(arch_cam, arch_f.global_position + Vector3(0.0, 2.35, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_07_gilded_rifle_and_arch.png")

	# 8 & 9) Confidential Boss '玄铁词尊' Articulated 5-Part Rig + Round-2 Orbiting Shields + Ultimate「天地万象」Mirror Yanshan!
	game.start_action(true, "confidential")
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	await frames(6)
	var ac: Vector3 = game.Layout.CLOUD_ARENA_CENTER
	game.player.position = game.Layout.on_ground(ac + Vector3(0.0, 0.0, 11.8)) + Vector3(0.0, 0.14, 0.0)
	await frames(4)
	var ov = game.combat.boss_unit
	if is_instance_valid(ov):
		ov.force_land_skyfall()
		ov.position = game.Layout.on_ground(ac + Vector3(0.0, 0.0, -1.5))
		ov.rotation = Vector3.ZERO
		ov.set_physics_process(false)
		# Put Overlord directly into Round 2 (3 fast-orbiting golden shields + 10s countdown!) with dramatic blade pose
		ov.configure_overlord_round_two(game.combat._build_wave_words(3))
		ov.overlord_orbit_angle = 0.45
		ov._update_overlord_shield_positions(0.016)
		if is_instance_valid(ov.ov_arm_l):
			ov.ov_arm_l.rotation = Vector3(-0.65, 0.0, -0.35)
		if is_instance_valid(ov.ov_arm_r):
			ov.ov_arm_r.rotation = Vector3(-0.85, 0.0, 0.35)
		game.combat.show_question()
		await look_from_to(game.Layout.on_ground(ac + Vector3(0.0, 0.0, 10.6)) + Vector3(0.0, 0.14, 0.0), ov.global_position + Vector3(0.0, 2.55, 0.0))
		clear_hud_popups()
		await frames(2)
		game._capture("v086_08_overlord_orbit_shields.png")

		# 9) Trigger Ultimate「天地万象」and position Inverted Mirror Yanshan Mountain mid-descent over Cloud-Top Arena!
		ov.trigger_ultimate_tiandi()
		if is_instance_valid(ov.mirror_mountain_node):
			ov.mirror_mountain_node.position.y = float(game.Layout.CLOUD_ARENA_Y) + 12.2
			ov.mirror_mountain_node.rotation.y = 0.52
		if is_instance_valid(ov.ov_arm_l):
			ov.ov_arm_l.rotation = Vector3(-2.25, 0.0, -0.25)
		if is_instance_valid(ov.ov_arm_r):
			ov.ov_arm_r.rotation = Vector3(-2.25, 0.0, 0.25)
		game.screen_flash.color = Color(1.0, 0.56, 0.16, 0.10)
		await look_from_to(game.Layout.on_ground(ac + Vector3(0.0, 0.0, 17.5)) + Vector3(0.0, 0.14, 0.0), Vector3(ac.x, float(game.Layout.CLOUD_ARENA_Y) + 6.8, ac.z))
		await frames(4)
		game._capture("v086_09_ultimate_mirror_yanshan.png")

	game._end_run(false)
	game.queue_free()
	await process_frame
	print("CAPTURE_V086_DONE")
	quit(0)
