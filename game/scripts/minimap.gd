extends Control
## Tactical radar minimap showing route, 3 outposts, 3 enemy archetypes, password crates, and extraction beacon.

var game

func _process(_delta):
	queue_redraw()

func point(v: Vector3) -> Vector2:
	return Vector2(83, 83) + Vector2(v.x, v.z + 44) * 0.88

func _is_discovered(node: Node3D) -> bool:
	if not node.has_meta("secret_key"):
		return true
	var sk := str(node.get_meta("secret_key"))
	if sk == "":
		return true
	if is_instance_valid(game.exploration) and game.exploration.is_secret_revealed(sk):
		return true
	return game.player.position.distance_to(node.position) < 14.0

func _draw():
	draw_circle(Vector2(83, 83), 78, Color(0.05, 0.14, 0.13, 0.94))
	for r in [28, 54, 78]:
		draw_arc(Vector2(83, 83), r, 0, TAU, 64, Color(0.38, 0.72, 0.60, 0.22), 1.0, true)
	draw_line(Vector2(5, 83), Vector2(161, 83), Color(0.4, 0.7, 0.6, 0.14))
	draw_line(Vector2(83, 5), Vector2(83, 161), Color(0.4, 0.7, 0.6, 0.14))
	if not is_instance_valid(game.player):
		return

	for i in range(-110, 26, 4):
		var z0 := float(i)
		var z1 := minf(26.0, z0 + 4.0)
		draw_line(
			point(Vector3(game.Layout.stream_center_x(z0), 0, z0)),
			point(Vector3(game.Layout.stream_center_x(z1), 0, z1)),
			Color("4da8e2"), 2.2, true
		)
	for bz in game.Layout.STREAM_BRIDGES:
		var cx: float = game.Layout.stream_center_x(float(bz))
		draw_line(
			point(Vector3(cx - 2.6, 0, float(bz))),
			point(Vector3(cx + 2.6, 0, float(bz))),
			Color("cba26c"), 3.2, true
		)

	for i in game.Layout.ROUTE.size() - 1:
		draw_line(point(game.Layout.ROUTE[i]), point(game.Layout.ROUTE[i + 1]), Color("8e9869"), 2.8, true)
	for branch in game.Layout.BRANCHES:
		for i in branch.size() - 1:
			draw_line(point(branch[i]), point(branch[i + 1]), Color("6c8061"), 1.2, true)

	for at in [game.Layout.POEM, game.Layout.MATH, game.Layout.CLUE]:
		draw_circle(point(at), 3.0, Color("e0c991"), false, 1.4)

	if is_instance_valid(game.combat) and game.combat.in_field():
		for z_idx in game.Layout.COMBAT_ZONES.size():
			var z_pos = point(game.Layout.COMBAT_ZONES[z_idx].at)
			var cleared = game.combat.zone_cleared.get(z_idx, false)
			draw_arc(z_pos, 11.0, 0, TAU, 32, Color("6ae3a8") if cleared else Color(0.95, 0.45, 0.32, 0.42), 1.3, true)
			if game.combat.troops.has(z_idx):
				for soldier in game.combat.troops[z_idx]:
					if not soldier.defeated:
						var dot_col = Color("f59b56")
						var r = 2.4
						if soldier.archetype == 1:
							dot_col = Color("ffd166") # Scout Drone
						elif soldier.archetype == 2:
							dot_col = Color("ff4d6d") # Sniper Guard
						elif soldier.archetype == 3:
							dot_col = Color("ffda44") # Boss Warden
							r = 4.2
						draw_circle(point(soldier.position), r, dot_col)
						if soldier.archetype == 3:
							draw_arc(point(soldier.position), 6.0, 0, TAU, 16, Color("ff5c5c"), 1.3)
	else:
		for station in game.Layout.STATIONS:
			draw_circle(point(station.at), 3.8, Color("86c5eb"))

	if is_instance_valid(game.exploration):
		for enode in game.exploration.nodes:
			var eid := str(enode.get_meta("explore_id", ""))
			var done := bool(game.exploration.states.get(eid, false))
			var ep := point(enode.position)
			if eid == "recon_radio":
				draw_circle(ep, 3.2, Color("5f7d73") if done else Color("56e8ff"))
			elif eid == "airdrop_beacon":
				draw_circle(ep, 3.4, Color("5f7d73") if done else Color("ffd15c"))
			elif eid.begins_with("intel_"):
				draw_rect(Rect2(ep - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color("5f7d73") if done else Color("8ef0c8"))

	for sup in game.pickup_nodes:
		if sup.visible and _is_discovered(sup):
			if sup.has_meta("tactical_item"):
				var tk = str(sup.get_meta("tactical_item"))
				var tc = Color("f5c542") if tk == "ammo_crate" else (Color("56e8ff") if tk == "smoke_emp" else Color("6ae3a8"))
				draw_circle(point(sup.position), 1.9, tc)
			else:
				draw_circle(point(sup.position), 2.1, Color("66d9ef"))

	for chest in game.crate_nodes:
		var opened = chest.get_meta("title") in game.rules.crates
		if not opened and not _is_discovered(chest):
			continue
		var tier = int(chest.get_meta("tier"))
		var c = Color("5f7d73") if opened else (Color("ffd15c") if tier == 3 else (Color("cf8aff") if tier == 2 else Color("74e3a3")))
		var cp = point(chest.position)
		draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), c)
		if not opened and chest.has_meta("secret_key"):
			draw_rect(Rect2(cp - Vector2(4.5, 4.5), Vector2(9, 9)), c, false, 1.0)

	var exit_point = point(game.exit_position)
	var ready = game.rules.can_extract()
	draw_circle(exit_point, 5.2, Color("76e5bc") if ready else Color("d8b26e"), false, 2.0)

	var p = point(game.player.position)
	var f = Vector2(-sin(game.player.yaw), -cos(game.player.yaw))
	draw_colored_polygon(PackedVector2Array([p + f * 7.2, p + f.rotated(2.45) * 5.0, p + f.rotated(-2.45) * 5.0]), Color("f4fff8"))
