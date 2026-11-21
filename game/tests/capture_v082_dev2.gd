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

	# 1) D2-5: Settings drawer showing new "切换新词时立即自动朗读英文读音" checkbox
	game.settings_panel.show()
	game._sync_settings_ui()
	await frames(4)
	game._capture("v082dev2_settings_autospeak.png")
	game.settings_panel.hide()

	# 2) D2-6: Station 1 ("林间前哨") all 4 word boards A/B/C/D standing 100% clear of the western hillside!
	game.start_action(false)
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	var st1 = game.stations[1]
	game.player.position = st1.global_position + Vector3(2.0, 0.14, 2.0)
	await frames(3)
	game._activate_station(1)
	# Stand slightly south-east facing all 4 boards clearly (especially Board D on the far left!)
	game.player.position = game.Layout.on_ground(st1.global_position + Vector3(1.2, 0.0, 6.4)) + Vector3(0, 0.14, 0)
	var look_mid: Vector3 = st1.targets[1].global_position.lerp(st1.targets[0].global_position, 0.35)
	var d_st: Vector3 = look_mid - game.player.camera.global_position
	game.player.yaw = atan2(-d_st.x, -d_st.z)
	game.player.pitch = atan2(d_st.y, Vector2(d_st.x, d_st.z).length())
	await frames(6)
	game._capture("v082dev2_forest_boards_clear.png")

	# 3) D2-1/D2-2/D2-5: Normal Combat B-Zone Boss (720 HP + red mortar ring barrage + golden word-switch flash + scarce ammo HUD)
	game._end_run(false)
	game.start_action(true, "normal")
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	var c2: Vector3 = game.combat.zone_center(2)
	game.player.position = game.Layout.on_ground(c2 + Vector3(0.0, 0.0, 8.8)) + Vector3(0, 0.14, 0)
	game.combat.engage_camp(2)
	var boss = game.combat.boss_unit
	if is_instance_valid(boss):
		boss.set_physics_process(false)
		boss.position = game.Layout.on_ground(c2 + Vector3(0.0, 0.0, -0.8))
		boss.rotation.y = 0.0
		game.combat.spawn_danger_ring(c2 + Vector3(0.6, 0.0, 3.6), 3.4, 28)
		game.flash_word_switch_banner()
		var d_b: Vector3 = (boss.global_position + Vector3(0, 1.5, 0)) - game.player.camera.global_position
		game.player.yaw = atan2(-d_b.x, -d_b.z)
		game.player.pitch = atan2(d_b.y, Vector2(d_b.x, d_b.z).length())
	await frames(6)
	game._capture("v082dev2_boss_barrage_ammo.png")

	# 4) D2-3: Retest continuous input modal showing active cursor & clean prompt
	game._end_run(false)
	game.rules.profile.review_due.clear()
	game.rules.profile.review_due[str(game.words[0].id)] = "incorrect"
	game.rules.profile.review_due[str(game.words[1].id)] = "incorrect"
	game._open_retest()
	await frames(4)
	game._capture("v082dev2_retest_input.png")
	game.cipher_terminal.close()

	game.queue_free()
	await process_frame
	print("CAPTURE_V082_DEV2_DONE")
	quit(0)
