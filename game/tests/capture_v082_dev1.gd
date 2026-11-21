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

	# 1) Main Menu with "烟山初行 · 单人序章" entry + right-side "舒适、音量与学习设置" drawer
	game.rules.profile["prologue_completed"] = false
	game._refresh_menu()
	game.settings_panel.show()
	game._sync_settings_ui()
	await frames(4)
	game._capture("v082dev1_menu_settings.png")
	game.settings_panel.hide()

	# 2) Standalone Prologue: Camp Guide NPC "陈向导" + clean single-objective Prologue HUD
	game.start_prologue_chapter(false)
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	await frames(6)
	game._capture("v082dev1_prologue_npc.png")

	# 3) Standalone Prologue: East Hillside warm wayfinder lanterns & 3 Mistbound Scout word shields
	game.prologue.stage = "skirmish"
	game.player.position = game.Layout.on_ground(Vector3(24.2, 0.0, 6.2)) + Vector3(0, 0.14, 0)
	var look_t: Vector3 = game.prologue.scouts[1].node.position + Vector3(0, 1.3, 0)
	var d_sc: Vector3 = look_t - game.player.camera.global_position
	game.player.yaw = atan2(-d_sc.x, -d_sc.z)
	game.player.pitch = atan2(d_sc.y, Vector2(d_sc.x, d_sc.z).length())
	await frames(6)
	game._capture("v082dev1_prologue_scouts.png")

	# 4) Standalone Prologue: Wangdao Overlook Beacon & Yue-Kiln Celadon dual-layer clue discovery modal
	for _ps in 3:
		var tidx: int = game.prologue.active_scout_idx
		if tidx >= 0:
			game.prologue.hit_bullet(game.prologue.scouts[tidx].area)
	game.player.position = game.landscape.wangdao_deck_pos + Vector3(0, 0.12, -1.2)
	game.prologue.open_beacon_clue()
	game.prologue.modal_choice_btns[0].pressed.emit()
	await frames(4)
	game._capture("v082dev1_prologue_beacon_clue.png")
	game.prologue.close_modal()

	# 5) Clean Practice Range HUD (zero fake 07:59 timer / zero fake 差260分 extraction clutter)
	game.start_action(false)
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	game.player.position = game.landscape.wangdao_deck_pos + Vector3(0.0, 0.12, -0.35)
	game.player.yaw = PI
	game.player.pitch = -0.14
	await frames(6)
	game._capture("v082dev1_clean_practice_hud.png")

	# 6) 3D Relic Showcase Inspector with Dual-Layer Cultural Specimen Card (越窑秘色青瓷盏)
	game._end_run(false)
	await frames(3)
	game.loot_ui.open_inspect_item(game.Rules.LOOT_TABLE[7][0])
	await frames(6)
	game._capture("v082dev1_celadon_dual_card.png")
	game.loot_ui.close_inspect()

	game.queue_free()
	await process_frame
	print("CAPTURE_V082_DEV1_DONE")
	quit(0)
