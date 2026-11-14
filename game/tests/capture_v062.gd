extends SceneTree
## Captures GPU-rendered 1280x720 screenshots & Standard-Quality (real-time shadows ON) FPS benchmark for v0.6.2:
## 1) Main menu v0.6.2 briefing (Lost Bamboo-Stone Labyrinth & Yanxia Ancient Cavern);
## 2) Approaching the mossy bluestone South Gate ("迷踪竹石阵") along the flagstone trail;
## 3) Crouching [C] before the perforated Taihu karst arch shortcut ("奇石矮拱") & stone wayfinder lantern;
## 4) East Cliff Alcove Moya carving ("竹石清音");
## 5) Cavern Forecourt looking up at the craggy karst bluff & vermilion-engraved portal ("烟霞古洞");
## 6) Outer Gallery recessed Tang/Song blue-green mineral cave mural ("《烟山先民耕读图》") & stalactites;
## 7) Inner Sanctum overhead Skylight Mist Beam ("一线天光"), Sunken Jade Spring Pool, Ancestral Stone Tea Hearth, Celadon Tea Set & Ancient Bamboo Slips;
## 8) Interactive Yanshan Heritage reading card ("先民矿物壁画《耕读图》").

var game
var frame_samples_ms: Array[float] = []
var sampling_active := false

func _initialize():
	run()

func _process(delta: float) -> bool:
	if sampling_active and delta > 0.0:
		frame_samples_ms.append(delta * 1000.0)
	return false

func wait_render(frames: int = 8):
	await process_frame
	for _i in frames:
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw

func aim_player_exact(foot_pos: Vector3, look_target: Vector3, stance_mode: int = 0):
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.reset_stance()
	if stance_mode != 0:
		game.player.set_stance(stance_mode, true)
	game.player.current_eye_y = 1.04 if stance_mode == 1 else 1.58
	game.player.camera.position.y = game.player.current_eye_y
	game.player.position = foot_pos
	var eye_pos: Vector3 = foot_pos + Vector3(0.0, float(game.player.current_eye_y), 0.0)
	var d: Vector3 = look_target - eye_pos
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.25, 1.25)

func ground_foot(x: float, z: float, extra_y: float = 0.06) -> Vector3:
	return Vector3(x, float(game.terrain_height(x, z)) + extra_y, z)

func find_explore_node(eid: String) -> Node3D:
	for n in game.exploration.nodes:
		var nd := n as Node3D
		if nd != null and str(nd.get_meta("explore_id", "")) == eid:
			return nd
	return null

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(10)

	game.landscape.set_low_quality(false)
	await wait_render(6)

	# 1. Main menu with v0.6.2 briefing
	game._refresh_menu("烟山基地 v0.6.2 · 迷踪竹石阵与烟霞古洞")
	await wait_render(6)
	game._capture("01-menu-v062.png")

	# Start Combat Mode in Standard Quality (real-time shadows ON) & run live GPU benchmark across v0.6.2 landmarks + valley!
	game.start_action(true)
	game.landscape.set_low_quality(false)
	await wait_render(18)

	var bench_views := [
		{"name": "south_valley_vista", "foot": ground_foot(6.5, 14.5, 0.12), "look": Vector3(16.5, 1.5, 38.0)},
		{"name": "bamboo_maze_south_gate", "foot": ground_foot(-40.8, -32.4, 0.10), "look": Vector3(-41.6, 8.0, -38.0)},
		{"name": "yanxia_cave_portal", "foot": Vector3(-41.6, 6.54, -53.6), "look": Vector3(-41.6, 8.9, -58.5)},
		{"name": "yanxia_inner_sanctum", "foot": Vector3(-41.35, 6.526, -63.15), "look": Vector3(-41.85, 7.65, -67.15)}
	]
	frame_samples_ms.clear()
	var per_view := {}
	for bv in bench_views:
		var foot_v: Vector3 = bv["foot"]
		var look_v: Vector3 = bv["look"]
		var vname: String = str(bv["name"])
		aim_player_exact(foot_v, look_v, 0)
		for _w in 18:
			await process_frame
		var local_ms: Array[float] = []
		sampling_active = true
		var start_idx := frame_samples_ms.size()
		for _s in 75:
			await process_frame
		sampling_active = false
		for k in range(start_idx, frame_samples_ms.size()):
			local_ms.append(frame_samples_ms[k])
		var sum_local := 0.0
		for v in local_ms:
			sum_local += v
		per_view[vname] = snappedf(1000.0 * float(local_ms.size()) / maxf(0.001, sum_local), 0.1)

	var total_ms := 0.0
	for m in frame_samples_ms:
		total_ms += m
	var sorted_ms: Array[float] = frame_samples_ms.duplicate()
	sorted_ms.sort()
	var avg_fps: float = 1000.0 * float(sorted_ms.size()) / maxf(0.001, total_ms)
	var p95_ms: float = sorted_ms[int(float(sorted_ms.size() - 1) * 0.95)] if not sorted_ms.is_empty() else 0.0
	print("STANDARD_FPS_BENCHMARK ", JSON.stringify({
		"gpu": RenderingServer.get_video_adapter_name(),
		"low_quality": game.landscape.low_quality,
		"frames": sorted_ms.size(),
		"average_fps": snappedf(avg_fps, 0.1),
		"p95_frame_ms": snappedf(p95_ms, 0.2),
		"per_view_fps": per_view
	}))

	# Clean run in Combat Mode for crisp, well-lit v0.6.2 screenshots (after FPS warmup > 1.5s so FPS counter shows live FPS!)
	game._end_run(false)
	game.start_action(true)
	game.landscape.set_low_quality(false)
	game.wildlife.frozen_for_capture = true
	await create_timer(1.65).timeout
	await wait_render(10)

	# 2. Bamboo-Stone Labyrinth South Bluestone Archway ("迷 踪 竹 石 阵") & Flagstone Approach
	aim_player_exact(ground_foot(-41.55, -32.35, 0.05), Vector3(-41.60, float(game.terrain_height(-41.60, -36.50)) + 1.88, -36.60), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("02-bamboo-maze-south-gate.png")

	# 3. Crouching [C] before the Perforated Taihu Karst Arch Shortcut ("奇石矮拱") & Glowing Stone Lantern
	aim_player_exact(ground_foot(-41.55, -43.25, 0.04), Vector3(-41.55, float(game.terrain_height(-41.60, -45.50)) + 1.05, -45.55), 1)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("03-karst-crouch-arch-lantern.png")

	# 4. East Cliff Moya Carving Alcove ("竹 石 清 音") with [F] Heritage Prompt
	aim_player_exact(ground_foot(-37.75, -50.08, 0.04), Vector3(-35.42, float(game.terrain_height(-35.38, -50.00)) + 1.55, -50.00), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("04-moya-cliff-inscription.png")

	# 5. Yanxia Ancient Cavern South Cliff Portal ("烟 霞 古 洞") from the Bamboo-Framed Forecourt
	aim_player_exact(Vector3(-41.60, 6.52, -53.45), Vector3(-41.60, 8.85, -57.85), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("05-yanxia-cave-portal.png")

	# 6. Outer Gallery Recessed Blue-Green Mineral Cave Mural ("《烟山先民耕读图》") & Ceiling Stalactites
	aim_player_exact(Vector3(-41.05, 6.526, -60.85), Vector3(-44.72, 8.16, -61.15), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("06-cave-ancient-mineral-mural.png")

	# 7. Inner Sanctum: Overhead Skylight Mist Beam ("一线天光"), Sunken Jade Spring Pool, Ancestral Stone Tea Hearth & Ancient Bamboo Slips
	aim_player_exact(Vector3(-42.02, 6.526, -64.10), Vector3(-41.52, 7.56, -67.35), 0)
	await create_timer(1.08).timeout
	await wait_render(8)
	game._capture("07-inner-sanctum-jade-pool-hearth.png")

	# 8. Interactive Yanshan Heritage Reading Card ("烟霞古洞 · 先民青绿矿物壁画《耕读图》")
	var mural_ev := find_explore_node("cave_mural")
	if mural_ev != null:
		aim_player_exact(Vector3(-43.25, 6.526, -61.15), Vector3(-44.72, 8.15, -61.15), 0)
		await wait_render(4)
		game.exploration.open(mural_ev)
		await wait_render(6)
		game._capture("08-heritage-reading-overlay.png")
		game.exploration.close()

	game.queue_free()
	await process_frame
	quit(0)
