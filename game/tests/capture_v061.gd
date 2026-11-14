extends SceneTree
## Captures 8 GPU-rendered 1280x720 screenshots verifying every v0.6.1 visual fix:
## 1) Menu briefing; 2) South fence creek outflow, submerged pilings, watertight valley & village willows;
## 3) True concave pebble creek channel & banks; 4) Ancient Camphor & Wayside Shrine;
## 5) Segmented Moso bamboo & broadleaf trees; 6) East fence slope (zero floating rocks + boar/fox/bird/azaleas);
## 7) Creek pool koi, crab & river shrimp; 8) Active combat HUD non-overlap check.

var game

func _initialize():
	run()

func wait_render(frames = 8):
	await process_frame
	for i in frames:
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw

func aim_player_at(from_xz: Vector3, look_target: Vector3, y_offset: float = 0.12):
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

	# 1. Main menu with v0.6.1 briefing
	game._refresh_menu("烟山基地 v0.6.1 · 江南山林水系与生灵精修")
	await wait_render(4)
	game._capture("v061-menu-briefing.png")

	game.start_action(false)
	await wait_render(8)

	# 2. South Fence Creek Outflow & Village Willows (exact user bug #1 & #4 angle!)
	aim_player_at(Vector3(14.1, 0.0, 22.8), Vector3(18.2, -1.8, 36.0), 0.12)
	await wait_render(8)
	game._capture("v061-south-fence-creek-outflow.png")

	# 3. True Concave Pebble Creek Channel, Stone/Reed Banks & Wading Egret (exact user bug #3 angle!)
	var c_x: float = game.Layout.stream_center_x(16.0)
	var c_wy: float = game.Layout.stream_water_y(16.0)
	aim_player_at(Vector3(c_x - 2.9, 0.0, 19.6), Vector3(c_x + 0.2, c_wy + 0.15, 9.5), 0.12)
	await wait_render(8)
	game._capture("v061-concave-pebble-creek.png")

	# 4. Rebuilt Botanical Ancient Camphor & Wayside Shrine (exact user bug #2 angle!)
	var cs_at: Vector3 = game.Layout.on_ground(game.Layout.CAMPHOR_SHRINE)
	aim_player_at(cs_at + Vector3(-4.2, 0.0, 7.8), cs_at + Vector3(0.8, 2.5, 0.2), 0.15)
	await wait_render(8)
	game._capture("v061-camphor-shrine-botanical.png")

	# 5. Segmented Moso Bamboo Grove & Broadleaf Camphor / Maple Trees
	aim_player_at(Vector3(17.5, 0.0, -79.5), Vector3(24.5, game.terrain_height(24.5, -88.0) + 3.2, -88.5), 0.15)
	await wait_render(8)
	game._capture("v061-bamboo-maple-canopy.png")

	# 6. East Fence Slope: Zero Floating Boulders + Lush Grass/Azaleas + Charging Wild Boar & Red Fox (exact user bug #5 & #6 angle!)
	for a in game.wildlife.animals:
		if a.kind == "boar" and Vector2(a.home.x - 39.5, a.home.z - 2.5).length() < 2.0:
			a.state = "flee"
			a.label.visible = true
			a.pos = Vector3(40.0, game.terrain_height(40.0, 5.4), 5.4)
			a.root.position = a.pos
			a.root.rotation.y = deg_to_rad(-28.0)
			a.visual.position.y = 0.04
		elif a.kind == "fox" and a.home.x > 35.0 and a.home.z > -35.0:
			a.pos = Vector3(42.4, game.terrain_height(42.4, 3.8), 3.8)
			a.root.position = a.pos
			a.root.rotation.y = deg_to_rad(-42.0)
	aim_player_at(Vector3(38.2, 0.0, 9.2), Vector3(43.0, game.terrain_height(43.0, 1.0) + 0.5, 0.5), 0.15)
	await wait_render(8)
	game._capture("v061-east-fence-slope-boar-fox.png")

	# 7. Close-up Clear Creek Pool with Brook Koi, Creek Crab & Freshwater River Shrimp
	var p_cx: float = game.Layout.stream_center_x(19.2)
	var p_wy: float = game.Layout.stream_water_y(19.2)
	aim_player_at(Vector3(p_cx - 2.35, 0.0, 21.8), Vector3(p_cx + 0.15, p_wy - 0.18, 18.8), 0.08)
	await wait_render(8)
	game._capture("v061-creek-aquatic-shrimp-koi.png")

	# 8. Active Combat Mode HUD & Forest Outpost View (verifies crisp non-overlapping Zone 1 HUD!)
	game._end_run(false)
	game.start_action(true)
	await wait_render(6)
	aim_player_at(Vector3(-8.5, 0.0, -33.5), Vector3(-12.0, game.terrain_height(-12.0, -42.0) + 1.8, -42.0), 0.15)
	await wait_render(8)
	game._capture("v061-combat-hud-clean.png")

	game.queue_free()
	await process_frame
	print("PASS capture_v061 completed all 8 screenshots")
	quit(0)
