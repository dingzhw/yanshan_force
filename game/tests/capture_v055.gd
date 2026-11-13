extends SceneTree
## Captures 6 real GPU-rendered 1280x720 screenshots showcasing v0.5.5 living Yanshan ecology:
## mountain stream & footbridges, brook fish & river crabs, rabbits/squirrels, exotic flora [E],
## and 360-degree mountain timber guardrail + distant rice paddies, farmhouses & mountain ridges.

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

	# 1. Main menu with v0.5.5 ecology & panoramic vista briefing
	game._refresh_menu("烟山基地 v0.5.5 · 山间溪流生态与全景稻田视野")
	await wait_render(4)
	game._capture("v055-menu-briefing.png")

	# Enter active scenic deployment
	game.start_action(false)
	await wait_render(6)

	# 2. Mountain Stream + South Footbridge (z=7.0) + River Crab + Water Lilies
	var b_z := 7.0
	var b_cx: float = game.Layout.stream_center_x(b_z)
	var b_wy: float = game.Layout.stream_water_y(b_z)
	aim_player_at(Vector3(b_cx - 6.2, 0.0, 11.4), Vector3(b_cx - 0.3, b_wy + 0.35, 6.8), 0.20)
	await wait_render(8)
	game._capture("v055-stream-bridge-fish-crab.png")

	# 3. Forest Rabbit + Wildflower Meadow (telephoto framing from sunny east-south grass away from crates)
	game.wildlife.reset()
	game.feedback_left = 0.0
	var rabbit_pos: Vector3 = game.wildlife.animals[0].pos
	game.player.camera.fov = 34.0
	aim_player_at(rabbit_pos + Vector3(5.6, 0.0, 5.9), rabbit_pos + Vector3(0.0, 0.26, 0.0), 0.12)
	await wait_render(6)
	game._capture("v055-rabbit-squirrel-flora.png")
	game.player.camera.fov = 75.0

	# 4. South Mountain Timber Guardrail Fence -> 3D Terraced Rice Paddies, Cottages & Horizon Ridges
	aim_player_at(Vector3(2.2, 0.0, 23.6), Vector3(14.0, -7.5, 82.0), 0.15)
	await wait_render(8)
	game._capture("v055-fence-paddies-vista.png")

	# 5. East Ridge Overlook Fence -> Golden/Green Valley Terraces, Cottages & Mountain Skirt
	aim_player_at(Vector3(50.2, 0.0, -24.0), Vector3(96.0, -8.5, -16.0), 0.20)
	await wait_render(8)
	game._capture("v055-west-overlook-terrace.png")

	# 6. Exotic Flora [E] Botanical Study + HUD Eco Progress & Stream Minimap
	var orchid_pos := Vector3(13.5, 0.0, 5.2)
	aim_player_at(orchid_pos + Vector3(-1.3, 0.0, -1.9), game.Layout.on_ground(orchid_pos) + Vector3(0.1, 0.35, 0.1), 0.05)
	await wait_render(5)
	game._update_interaction()
	game.interact()
	await wait_render(6)
	game._capture("v055-flora-english-scan.png")

	game.queue_free()
	await process_frame
	print("PASS capture_v055 completed all 6 screenshots")
	quit(0)
