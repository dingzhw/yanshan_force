extends SceneTree
## Captures 6 GPU-rendered 1280x720 screenshots verifying v0.5.6 cohesive distant vista lighting,
## Filmic sky/ambient shading, 3D outer foothills, hamlet pines, and foreground stream/ecology harmony.

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

	# 1. Main menu with v0.5.6 distant lighting & ecology briefing
	game._refresh_menu("烟山基地 v0.5.6 · 远景光影与大气雾效调优")
	await wait_render(4)
	game._capture("v056-menu-briefing.png")

	game.start_action(false)
	await wait_render(6)

	# 2. South Mountain Timber Fence -> cohesive rice paddies, nested hamlets, 3D foothills & mist peaks
	aim_player_at(Vector3(2.2, 0.0, 23.6), Vector3(14.0, -7.5, 82.0), 0.15)
	await wait_render(8)
	game._capture("v056-fence-paddies-vista.png")

	# 3. East Ridge Overlook Fence -> terraced green fields, pine clusters & layered horizon haze
	aim_player_at(Vector3(50.2, 0.0, -24.0), Vector3(96.0, -8.5, -16.0), 0.20)
	await wait_render(8)
	game._capture("v056-west-overlook-terrace.png")

	# 4. Northwest Overlook Fence -> West/NW hillside crest looking out over misty outer foothills
	aim_player_at(Vector3(-49.0, 0.0, -46.0), Vector3(-118.0, -4.0, -28.0), 0.20)
	await wait_render(8)
	game._capture("v056-high-ridge-panorama.png")

	# 5. Foreground Stream + Footbridge + River Crab under unified Filmic sky lighting
	var b_z := 7.0
	var b_cx: float = game.Layout.stream_center_x(b_z)
	var b_wy: float = game.Layout.stream_water_y(b_z)
	aim_player_at(Vector3(b_cx - 6.2, 0.0, 11.4), Vector3(b_cx - 0.3, b_wy + 0.35, 6.8), 0.20)
	await wait_render(8)
	game._capture("v056-stream-bridge-fish-crab.png")

	# 6. Camp Rabbit & Bamboo Ridges harmony check
	game.wildlife.reset()
	game.feedback_left = 0.0
	var rabbit_pos: Vector3 = game.wildlife.animals[0].pos
	game.player.camera.fov = 34.0
	aim_player_at(rabbit_pos + Vector3(5.6, 0.0, 5.9), rabbit_pos + Vector3(0.0, 0.26, 0.0), 0.12)
	await wait_render(6)
	game._capture("v056-rabbit-squirrel-flora.png")
	game.player.camera.fov = 75.0

	game.queue_free()
	await process_frame
	print("PASS capture_v056 completed all 6 screenshots")
	quit(0)
