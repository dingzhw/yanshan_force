extends SceneTree
## v0.8.5 Visual Capture Suite (1280x720):
## 1. v085_charm_under_optic_hip.png   — Relocated charm under left flank of optic in hip-fire (ZERO front/rear hand clip!)
## 2. v085_charm_under_optic_ads.png   — Relocated charm under left flank of optic in ADS (ZERO sightline / hand clip!)
## 3. v085_warden_guard_sonic.png      — Cave Warden after core hit: NO stun, immediate X-brace guard + sonic retaliation + stealth HUD!
## 4. v085_cloud_arena_pillars.png     — North Summit 38m flat Cloud-Top Bluestone Martial Arena & 8 dragon-carved pillars!
## 5. v085_triple_bridge_teapav.png    — Central Triple-Arch Bluestone Bridge + East Tea-Hill Rest Pavilion + 3x Minimap with tags!
## 6. v085_wangdao_expanded_vista.png  — Elevated Wangdao Overlook terrace panoramic view across 3x expanded Great Yanshan!

var game

func _initialize():
	call_deferred("run")

func frames(count: int):
	for _i in count:
		await process_frame
		await physics_frame

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await frames(6)

	# 1 & 2) Relocated rear upper-receiver weapon charm directly below left flank of red-dot optic (hip-fire & ADS)
	game.rules.profile.owned = ["red_dot", "forest_skin", "backpack"]
	game.rules.ensure_equipped()
	game.achievements.record_stat("fox", 1, true)
	game.achievements.banner_queue.clear()
	game.achievements.banner_active = {}
	game.achievements.banner_panel.hide()
	game.achievements.equip_charm("charm_fox_bell")
	game.start_action(true, "normal")
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	game.player.select_weapon(0)
	game.player.position = game.Layout.on_ground(game.Layout.SPAWN + Vector3(0.0, 0.0, -4.0)) + Vector3(0.0, 0.14, 0.0)
	game.player.yaw = -0.35
	game.player.pitch = -0.04
	game.player.aiming = false
	await frames(10)
	game._capture("v085_charm_under_optic_hip.png")

	game.player.aiming = true
	await frames(16)
	game._capture("v085_charm_under_optic_ads.png")
	game.player.aiming = false
	await frames(8)
	game.player.ammo = 2
	game.player.reload()
	await frames(22)
	game._capture("v085_charm_reload_check.png")
	game.player.reload_left = 0.0
	await frames(6)

	# 3) Cave Warden inside isolated West Bamboo Ravine Yanxia Cave: core hit -> immediate guard + sonic ring + stealth prompt!
	var cw = game.cave_warden
	cw.reset()
	var c_cen: Vector3 = game.Layout.YANXIA_CAVE_CENTER
	var c_fy: float = float(game.Layout.CAVE_FLOOR_Y) + 0.03
	cw.root_node.position = Vector3(c_cen.x, c_fy, c_cen.z + 1.8)
	cw.root_node.rotation = Vector3.ZERO
	game.player.position = Vector3(c_cen.x + 0.25, c_fy + 0.05, c_cen.z + 6.8)
	game.player.velocity = Vector3.ZERO
	game.player.set_stance(game.player.STANCE_CROUCH, true)
	var cw_look: Vector3 = cw.root_node.global_position + Vector3(0.0, 1.55, 0.0)
	var d_cw: Vector3 = cw_look - game.player.camera.global_position
	game.player.yaw = atan2(-d_cw.x, -d_cw.z)
	game.player.pitch = atan2(d_cw.y, Vector2(d_cw.x, d_cw.z).length())
	await frames(6)
	cw.hit_bullet(cw.core_area)
	cw.snap_articulation_for_pose()
	await frames(4)
	game._capture("v085_warden_guard_sonic.png")

	# 4) North Summit 38m Cloud-Top Bluestone Martial Arena ("云顶青石演武坛") with 8 dragon pillars & open sky
	game.player.reset_stance()
	var ac: Vector3 = game.Layout.CLOUD_ARENA_CENTER
	var arena_view: Vector3 = game.Layout.on_ground(Vector3(ac.x, 0.0, ac.z + 24.0)) + Vector3(0.0, 0.2, 0.0)
	game.player.position = arena_view
	game.player.yaw = 0.0
	game.player.pitch = 0.04
	await frames(10)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await frames(2)
	game._capture("v085_cloud_arena_pillars.png")

	# 5) Central Triple-Arch Bluestone Bridge + East Tea-Hill Rest Pavilion + 3x Minimap with landmark labels!
	var b1x: float = game.Layout.stream_center_x(float(game.Layout.MULTI_ARCH_BRIDGE_Z))
	var bridge_view: Vector3 = game.Layout.on_ground(Vector3(b1x - 13.5, 0.0, float(game.Layout.MULTI_ARCH_BRIDGE_Z) + 7.2)) + Vector3(0.0, 0.2, 0.0)
	game.player.position = bridge_view
	var look_tea := Vector2(game.Layout.EAST_OVERLOOK.x - bridge_view.x, game.Layout.EAST_OVERLOOK.z - bridge_view.z)
	game.player.yaw = atan2(-look_tea.x, -look_tea.y)
	game.player.pitch = -0.02
	await frames(10)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await frames(2)
	game._capture("v085_triple_bridge_teapav.png")

	# 6) Wangdao Overlook Terrace panoramic vista across 3x expanded Great Yanshan & Chengzhuang terraced paddies
	var wd_pos: Vector3 = game.landscape.wangdao_deck_pos + Vector3(0.0, 0.12, -0.35)
	game.player.position = wd_pos
	game.player.yaw = PI + 0.18
	game.player.pitch = -0.14
	await frames(10)
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	await frames(2)
	game._capture("v085_wangdao_expanded_vista.png")

	game._end_run(false)
	game.queue_free()
	await process_frame
	print("CAPTURE_V085_DONE")
	quit(0)
