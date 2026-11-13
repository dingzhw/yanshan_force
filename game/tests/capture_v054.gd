extends SceneTree
## Captures 7 real GPU-rendered 1280x720 screenshots of v0.5.4 parkour routes, hidden cave/caches, intel UI & radar scan.

var game

func _initialize():
	run()

func wait_render(frames = 6):
	await process_frame
	for i in frames:
		await process_frame
		await physics_frame

func aim_player_at(from_pos: Vector3, look_target: Vector3):
	game.player.position = from_pos
	var d: Vector3 = look_target - (from_pos + Vector3(0, 1.48, 0))
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.1, 1.1)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(8)

	# 1. Main menu with v0.5.4 exploration briefing
	game._refresh_menu("烟山基地 v0.5.4 · 立体跳格子与战地寻宝")
	await wait_render(4)
	game._capture("v054-menu-briefing.png")

	# Enter active deployment cleanly (disable combat aggro damage during scenic tour)
	game.start_action(false)
	await wait_render(6)

	# 2. Route A: West Cargo Containers + Step Stones + Field Intel Board #1
	var cy: Vector3 = game.Layout.on_ground(game.Layout.PARKOUR_CONTAINERS)
	aim_player_at(cy + Vector3(8.5, 1.2, 6.8), cy + Vector3(-0.2, 2.0, 0.2))
	await wait_render(8)
	game._capture("v054-container-parkour.png")

	# 3. Route B: Bamboo Shelter 5-Step Exterior Scaffolding & Roof Vault
	var bs: Vector3 = game.Layout.on_ground(game.Layout.SHELTER_BAMBOO)
	aim_player_at(bs + Vector3(8.2, 1.2, 3.8), bs + Vector3(0.4, 2.5, -0.6))
	await wait_render(8)
	game._capture("v054-shelter-stairs-roof.png")

	# 4. Route C: Watchtower Spiral Climb & Summit Lookout Vault
	var wt: Vector3 = game.landscape.watchtower_pos
	aim_player_at(wt + Vector3(-2.6, 5.2, 3.8), wt + Vector3(0.1, 5.5, 0.0))
	await wait_render(8)
	game._capture("v054-watchtower-summit.png")

	# 5. Deep Mossy Cave Grotto with Amber Lantern & Tier-3 Airdrop Vault
	var cg: Vector3 = game.Layout.on_ground(game.Layout.CAVE_GROTTO)
	aim_player_at(cg + Vector3(0.35, 0.1, 3.6), cg + Vector3(-0.2, 0.9, -0.2))
	await wait_render(8)
	game._capture("v054-cave-grotto-airdrop.png")

	# 6. Field Intel UI (preposition riddle overlay)
	var intel_cave_node: Node3D = null
	var recon_node: Node3D = null
	for en in game.exploration.nodes:
		var eid := str(en.get_meta("explore_id", ""))
		if eid == "intel_cave":
			intel_cave_node = en
		elif eid == "recon_radio":
			recon_node = en
	if is_instance_valid(intel_cave_node):
		game.exploration.open(intel_cave_node)
		await wait_render(5)
		game._capture("v054-intel-board-ui.png")
		game.exploration.close()
		await wait_render(3)

	# 7. Recon Radio Activated + Global Radar Scan Revealed on Minimap
	if is_instance_valid(recon_node):
		game.exploration.open(recon_node)
		game.exploration.choose(game.exploration.answer_button_index("recon_radio"))
		game.exploration.close()
		var rp: Vector3 = recon_node.position
		aim_player_at(rp + Vector3(-2.1, 0.25, 2.3), rp + Vector3(0.0, 0.85, 0.0))
		await wait_render(8)
		game._capture("v054-recon-radio-radar.png")

	game.queue_free()
	await process_frame
	print("PASS capture_v054 completed all 7 screenshots")
	quit(0)
