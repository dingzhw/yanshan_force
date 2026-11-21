extends Control
## Tactical radar minimap for v0.8.5 Great Yanshan (180m x 240m):
## Shows route, winding creek + 5 bridges, 6 spaced camps, 38m Cloud-Top Arena, Yanxia Cave,
## enemy archetypes, crates, extraction beacon & crisp Chinese landmark short labels!

var game
var redraw_accum := 0.0

func _process(delta):
	if is_instance_valid(game) and game.paused:
		return
	redraw_accum += delta
	if redraw_accum >= 0.05:
		redraw_accum = 0.0
		queue_redraw()

func point(v: Vector3) -> Vector2:
	# Maps X in [-90..90], Z in [-200..40] (center (0, -80)) cleanly into radius-76 circular radar!
	return Vector2(83.0, 83.0) + Vector2(v.x, v.z + 80.0) * 0.56

func _is_discovered(node: Node3D) -> bool:
	if not node.has_meta("secret_key"):
		return true
	var sk := str(node.get_meta("secret_key"))
	if sk == "":
		return true
	if is_instance_valid(game.exploration) and game.exploration.is_secret_revealed(sk):
		return true
	return game.player.position.distance_to(node.position) < 16.0

func _draw_tag(pos: Vector2, text: String, col: Color):
	if is_instance_valid(game) and game.font != null:
		draw_string(game.font, pos + Vector2(-5.0, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.03, 0.08, 0.08, 0.90))
		draw_string(game.font, pos + Vector2(-6.0, 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

func _draw():
	draw_circle(Vector2(83, 83), 78, Color(0.05, 0.14, 0.13, 0.94))
	for r in [26, 52, 78]:
		draw_arc(Vector2(83, 83), r, 0, TAU, 48, Color(0.38, 0.72, 0.60, 0.22), 1.0, true)
	draw_line(Vector2(5, 83), Vector2(161, 83), Color(0.4, 0.7, 0.6, 0.14))
	draw_line(Vector2(83, 5), Vector2(83, 161), Color(0.4, 0.7, 0.6, 0.14))
	if not is_instance_valid(game.player):
		return

	# Winding mountain creek & 5 crossings across the 240m north-south span
	for i in range(-194, 42, 8):
		var z0 := float(i)
		var z1 := minf(42.0, z0 + 8.0)
		draw_line(
			point(Vector3(game.Layout.stream_center_x(z0), 0, z0)),
			point(Vector3(game.Layout.stream_center_x(z1), 0, z1)),
			Color("4da8e2"), 1.8, true
		)
	for bz in game.Layout.STREAM_BRIDGES:
		var cx: float = game.Layout.stream_center_x(float(bz))
		draw_line(
			point(Vector3(cx - 3.6, 0, float(bz))),
			point(Vector3(cx + 3.6, 0, float(bz))),
			Color("cba26c"), 2.8, true
		)

	for i in game.Layout.ROUTE.size() - 1:
		draw_line(point(game.Layout.ROUTE[i]), point(game.Layout.ROUTE[i + 1]), Color("8e9869"), 2.2, true)
	for branch in game.Layout.BRANCHES:
		for i in branch.size() - 1:
			draw_line(point(branch[i]), point(branch[i + 1]), Color("6c8061"), 1.0, true)

	for at in [game.Layout.POEM, game.Layout.MATH, game.Layout.CLUE]:
		draw_circle(point(at), 2.5, Color("e0c991"), false, 1.2)

	# North Summit 38m Cloud-Top Bluestone Martial Arena ring
	var arena_p := point(game.Layout.CLOUD_ARENA_CENTER)
	draw_arc(arena_p, float(game.Layout.CLOUD_ARENA_RADIUS) * 0.56, 0, TAU, 28, Color("ffd86b", 0.62), 1.6, true)

	# Bamboo-Stone Labyrinth footprint & Yanxia Ancient Cavern vault marker in West Ravine
	var cdx := float(game.Layout.CAVE_DX)
	var cdz := float(game.Layout.CAVE_DZ)
	var maze_tl := point(Vector3(-48.1 + cdx, 0, -57.5 + cdz))
	draw_rect(Rect2(maze_tl, Vector2(13.0, 21.0) * 0.56), Color(0.56, 0.82, 0.68, 0.38), false, 1.0)
	var cave_p := point(game.Layout.YANXIA_CAVE_CENTER)
	draw_arc(cave_p, 4.2, PI, TAU, 14, Color(0.68, 0.92, 0.84, 0.72), 1.5, true)

	if is_instance_valid(game.combat) and game.combat.in_field():
		for z_idx in game.Layout.COMBAT_ZONES.size():
			var z_pos = point(game.Layout.COMBAT_ZONES[z_idx].at)
			var cleared: bool = game.combat.zone_cleared.get(z_idx, false)
			var engaged: bool = game.combat.is_zone_engaged(z_idx)
			var ring_col := Color("6ae3a8") if cleared else (Color("ff6347") if engaged else Color(0.95, 0.72, 0.36, 0.55))
			draw_arc(z_pos, 7.6, 0, TAU, 22, ring_col, 1.6 if engaged else 1.1, true)
			if game.combat.troops.has(z_idx):
				for soldier in game.combat.troops[z_idx]:
					if is_instance_valid(soldier) and not soldier.defeated:
						var dot_col = Color("f59b56")
						var r = 1.9
						if soldier.archetype == 1:
							dot_col = Color("ffd166")
						elif soldier.archetype == 2:
							dot_col = Color("ff4d6d")
						elif soldier.archetype == 3:
							dot_col = Color("ffda44")
							r = 3.6
						draw_circle(point(soldier.position), r, dot_col)
						if soldier.archetype == 3:
							draw_arc(point(soldier.position), 5.2, 0, TAU, 16, Color("ff5c5c"), 1.2)
	else:
		for station in game.Layout.STATIONS:
			draw_circle(point(station.at), 3.4, Color("86c5eb"))

	if is_instance_valid(game.exploration):
		for enode in game.exploration.nodes:
			var eid := str(enode.get_meta("explore_id", ""))
			var done := bool(game.exploration.states.get(eid, false))
			var ep := point(enode.position)
			if eid == "recon_radio":
				draw_circle(ep, 2.8, Color("5f7d73") if done else Color("56e8ff"))
			elif eid == "airdrop_beacon":
				draw_circle(ep, 3.0, Color("5f7d73") if done else Color("ffd15c"))
			elif eid.begins_with("intel_"):
				draw_rect(Rect2(ep - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), Color("5f7d73") if done else Color("8ef0c8"))
			elif eid in ["cliff_inscription", "cave_mural", "cave_hearth"]:
				var hc := Color("5f7d73") if done else Color("f0c878")
				draw_colored_polygon(PackedVector2Array([ep + Vector2(0, -2.6), ep + Vector2(2.6, 0), ep + Vector2(0, 2.6), ep + Vector2(-2.6, 0)]), hc)

	for sup in game.pickup_nodes:
		if sup.visible and _is_discovered(sup):
			if sup.has_meta("tactical_item"):
				var tk = str(sup.get_meta("tactical_item"))
				var tc = Color("f5c542") if tk == "ammo_crate" else (Color("56e8ff") if tk == "smoke_emp" else Color("6ae3a8"))
				draw_circle(point(sup.position), 1.6, tc)
			else:
				if sup.has_meta("overcharged"):
					draw_circle(point(sup.position), 2.2, Color("ffd15c"))
					draw_arc(point(sup.position), 3.2, 0, TAU, 12, Color("ff8c42"), 1.0)
				else:
					draw_circle(point(sup.position), 1.8, Color("66d9ef"))

	if is_instance_valid(game.world_loot):
		for raw_d in game.world_loot.drop_nodes:
			var dnode: Node3D = raw_d
			if is_instance_valid(dnode) and dnode.visible:
				var dp: Vector2 = point(dnode.position)
				draw_colored_polygon(PackedVector2Array([
					dp + Vector2(0, -2.8), dp + Vector2(2.8, 0),
					dp + Vector2(0, 2.8), dp + Vector2(-2.8, 0)
				]), Color("ffd15c"))

	for chest in game.crate_nodes:
		var opened = chest.get_meta("title") in game.rules.crates
		if not opened and not _is_discovered(chest):
			continue
		var tier = int(chest.get_meta("tier"))
		var c = Color("5f7d73") if opened else (Color("ffd15c") if tier == 3 else (Color("cf8aff") if tier == 2 else Color("74e3a3")))
		var cp = point(chest.position)
		draw_rect(Rect2(cp - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), c)
		if not opened and chest.has_meta("secret_key"):
			draw_rect(Rect2(cp - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), c, false, 1.0)

	var exit_point = point(game.exit_position)
	var ready = game.rules.can_extract()
	draw_circle(exit_point, 4.6, Color("76e5bc") if ready else Color("d8b26e"), false, 1.8)

	# v0.8.5 Crisp Chinese landmark short labels on radar
	_draw_tag(point(game.Layout.SPAWN) + Vector2(0.0, 10.0), "营", Color("a8f0d0"))
	_draw_tag(point(game.Layout.WANGDAO_PAVILION) + Vector2(2.0, -4.0), "望", Color("f4d48c"))
	_draw_tag(point(game.Layout.EAST_OVERLOOK) + Vector2(4.0, 0.0), "亭", Color("c8e8d8"))
	_draw_tag(cave_p + Vector2(-4.0, -6.0), "洞", Color("7ceeff"))
	_draw_tag(arena_p + Vector2(0.0, -8.0), "坛", Color("ffd86b"))
	_draw_tag(exit_point + Vector2(7.0, 2.0), "撤", Color("76e5bc") if ready else Color("f0cf86"))

	var p = point(game.player.position)
	var f = Vector2(-sin(game.player.yaw), -cos(game.player.yaw))
	draw_colored_polygon(PackedVector2Array([p + f * 6.8, p + f.rotated(2.45) * 4.6, p + f.rotated(-2.45) * 4.6]), Color("f4fff8"))
