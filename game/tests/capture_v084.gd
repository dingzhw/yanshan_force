extends SceneTree

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

	# 1) Weapon Charm Left-Side Exterior Display — Hip-Fire & ADS!
	game.rules.profile.owned = ["red_dot", "forest_skin", "backpack"]
	game.rules.ensure_equipped()
	game.achievements.record_stat("soldiers_defeated", 200, true)
	game.achievements.record_stat("fox", 1, true)
	game.achievements.banner_queue.clear()
	game.achievements.banner_active = {}
	game.achievements.banner_panel.hide()
	game.achievements.equip_charm("charm_fox_bell")
	game.start_action(true, "normal")
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	game.player.position = game.Layout.on_ground(Vector3(0.0, 0.0, 5.4)) + Vector3(0, 0.14, 0)
	game.player.yaw = 0.0
	game.player.pitch = -0.04
	await frames(10)
	game._capture("v084_charm_hipfire.png")

	# 1B) ADS with Red Dot optic — verify left-side exterior charm is visible and NEVER blocks center reticle!
	game.player.aiming = true
	await frames(16)
	game._capture("v084_charm_ads.png")
	game.player.aiming = false
	await frames(10)

	# 2) Cave Warden Dual-Arm Guard State (arms crossed protecting shrunk 0.30m core + shield deflect notice!)
	var cw = game.cave_warden
	cw.reset()
	cw.root_node.position = Vector3(-41.60, 6.53, -61.80)
	cw.root_node.rotation.y = 0.0
	game.player.position = Vector3(-41.60, 6.58, -56.40)
	var cw_look: Vector3 = cw.root_node.global_position + Vector3(0.0, 1.55, 0.0)
	var d_cw: Vector3 = cw_look - game.player.camera.global_position
	game.player.yaw = atan2(-d_cw.x, -d_cw.z)
	game.player.pitch = atan2(d_cw.y, Vector2(d_cw.x, d_cw.z).length())
	await frames(3)
	# First hit -> immediately raises X-brace stone arm shields across chest, then deflect frontal shot!
	cw.hit_bullet(cw.body_area)
	cw.snap_articulation_for_pose()
	cw.hit_bullet(cw.guard_area)
	cw.snap_articulation_for_pose()
	await frames(4)
	game._capture("v084_cave_warden_guard.png")

	# 3) Cave Warden Active Pursuit Open-Core State (arms flung wide open exposing compact 0.30m cyan core!)
	cw.state = "hunt"
	cw.noise_meter = 92.0
	cw.stagger_accum = 0
	cw.set_guard_arms(false, 0.0)
	cw.pursuit_open_left = 3.2
	cw.pursuit_hits_taken = 0
	cw.elapsed = 0.0
	cw.snap_articulation_for_pose()
	cw.hit_bullet(cw.core_area)
	cw.snap_articulation_for_pose()
	await frames(4)
	game._capture("v084_cave_warden_exposed.png")

	# 4) Universal Selective Loot Confirmation Panel — Multi-Item Password Crate (Mixed White/Blue/Big Gold + Backpack & Safe Box!)
	game.rules.bag.clear()
	game.rules.safe_box.clear()
	game.rules.add_loot_item(game.rules.roll_item_by_rarity(1))
	game.rules.add_loot_item(game.rules.roll_item_by_rarity(2))
	game.rules.add_loot_item(game.rules.roll_item_by_rarity(4))
	game.rules.add_item_to_safe_box(game.rules.roll_item_by_rarity(7))
	var demo_crate: Node3D = game.crate_nodes[0]
	var crate_items: Array = [
		game.rules.roll_item_by_rarity(6),
		game.rules.roll_item_by_rarity(3),
		game.rules.roll_item_by_rarity(1),
	]
	game.loot_container_ui.open_container(
		demo_crate, "crate", "林间前哨密码箱", crate_items,
		"★ 完美破译全通 +25 分 · 自由选择拾取入包、直存安全箱，或留低品物资在箱内！", false
	)
	await frames(4)
	game._capture("v084_loot_crate_panel.png")
	game.loot_container_ui.close()

	# 5) Universal Selective Loot Confirmation Panel — Single Ground/Pedestal Loose Relic!
	var tent_loose: Node3D = game.world_loot.loose_nodes[0]
	game.player.position = tent_loose.position + Vector3(0, 0.1, 1.2)
	await frames(3)
	game.interact()
	await frames(4)
	game._capture("v084_loot_single_ground.png")
	game.loot_container_ui.close()

	game.queue_free()
	await process_frame
	print("CAPTURE_V084_DONE")
	quit(0)
