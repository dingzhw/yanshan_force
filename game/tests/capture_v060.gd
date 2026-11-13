extends SceneTree
## Captures 6 GPU-rendered 1280x720 screenshots verifying v0.6.0 Jiangnan rural hill landmarks:
## Wangdao Pavilion, Stone Arch Bridge & Boundary Stele, Poem Stele Pavilion, Ancient Camphor & Shrine.

var game

func _initialize():
	run()

func wait_render(frames = 6):
	await process_frame
	for i in frames:
		await process_frame
		await physics_frame

func aim_player_at(from_xz: Vector3, look_target: Vector3, y_offset: float = 0.05):
	var ground_pos: Vector3 = game.Layout.on_ground(Vector3(from_xz.x, 0.0, from_xz.z)) + Vector3(0.0, y_offset, 0.0)
	game.player.velocity = Vector3.ZERO
	game.player.position = ground_pos
	var d: Vector3 = look_target - (ground_pos + Vector3(0.0, 1.48, 0.0))
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.1, 1.1)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(8)

	# 1. Main menu with v0.6.0 Jiangnan heritage briefing
	game._refresh_menu("烟山基地 v0.6.0 · 古今交织：江南地标重塑")
	await wait_render(4)
	game._capture("v060-menu-briefing.png")

	game.start_action(false)
	await wait_render(6)

	# 2. Central Single-Arch Bluestone Bridge, Stream & Engraved Trail Boundary Stele
	var b_cx: float = game.Layout.stream_center_x(-24.0)
	var b_wy: float = game.Layout.stream_water_y(-24.0)
	aim_player_at(Vector3(b_cx - 8.2, 0.0, -18.2), Vector3(b_cx - 0.8, b_wy + 1.0, -23.6), 0.15)
	await wait_render(8)
	game._capture("v060-stone-arch-bridge.png")

	# 3. Ancient Camphor Tree & Candle-lit Wayside Earth-God Shrine + Bluestone Trail
	var cs_at: Vector3 = game.Layout.on_ground(game.Layout.CAMPHOR_SHRINE)
	aim_player_at(cs_at + Vector3(-3.8, 0.0, 7.6), cs_at + Vector3(1.1, 2.0, 0.6), 0.15)
	await wait_render(8)
	game._capture("v060-camphor-shrine-trail.png")

	# 4. Wangdao Pavilion ("望稻亭") Flying-Eave Architecture & Gilded Plaque
	var pav_at: Vector3 = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION)
	var pav_node := game.landscape.find_child("WangdaoPavilion", true, false) as Node3D
	var pbasis: Basis = pav_node.transform.basis if pav_node else Basis.IDENTITY
	aim_player_at(pav_at + pbasis * Vector3(-6.8, 0.0, 2.8), pav_at + Vector3(0.0, 2.1, 0.0), 0.15)
	await wait_render(8)
	game._capture("v060-wangdao-pavilion-vista.png")

	# 5. Inside Wangdao Pavilion Looking Out Across Overlook Rail at the Southern Terraced Paddies & Hamlets
	var inside_pos: Vector3 = pav_at + pbasis * Vector3(1.12, 0.32, 0.18)
	game.player.velocity = Vector3.ZERO
	game.player.position = inside_pos
	var look_out := pav_at + pbasis * Vector3(58.0, -15.5, 4.0)
	var d_east: Vector3 = look_out - (inside_pos + Vector3(0.0, 1.48, 0.0))
	game.player.yaw = atan2(-d_east.x, -d_east.z)
	game.player.pitch = clampf(atan2(d_east.y, maxf(0.05, Vector2(d_east.x, d_east.z).length())), -1.1, 1.1)
	await wait_render(8)
	game._capture("v060-wangdao-overlook-paddies.png")

	# 6. Carved Bluestone Poem Stele Pavilion ("烟山诗碑亭") on West Forest Trail
	var poem_at: Vector3 = game.Layout.on_ground(game.Layout.POEM)
	aim_player_at(poem_at + Vector3(-0.9, 0.0, 4.3), poem_at + Vector3(0.0, 1.55, 0.0), 0.12)
	await wait_render(8)
	game._capture("v060-poem-stele-pavilion.png")

	game.queue_free()
	await process_frame
	print("PASS capture_v060 completed all 6 screenshots")
	quit(0)
