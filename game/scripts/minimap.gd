extends Control
## Tactical radar minimap showing route, 3 outposts, 3 enemy archetypes, password crates, and extraction beacon.

var game

func _process(_delta):
	queue_redraw()

func point(v: Vector3) -> Vector2:
	return Vector2(83, 83) + Vector2(v.x, v.z + 44) * 0.88

func _draw():
	draw_circle(Vector2(83, 83), 78, Color(0.05, 0.14, 0.13, 0.94))
	for r in [28, 54, 78]:
		draw_arc(Vector2(83, 83), r, 0, TAU, 64, Color(0.38, 0.72, 0.60, 0.22), 1.0, true)
	draw_line(Vector2(5, 83), Vector2(161, 83), Color(0.4, 0.7, 0.6, 0.14))
	draw_line(Vector2(83, 5), Vector2(83, 161), Color(0.4, 0.7, 0.6, 0.14))
	if not is_instance_valid(game.player):
		return

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
						if soldier.archetype == 1:
							dot_col = Color("ffd166") # Scout Drone
						elif soldier.archetype == 2:
							dot_col = Color("ff4d6d") # Sniper Guard
						draw_circle(point(soldier.position), 2.4, dot_col)
	else:
		for station in game.Layout.STATIONS:
			draw_circle(point(station.at), 3.8, Color("86c5eb"))

	for sup in game.pickup_nodes:
		if sup.visible:
			draw_circle(point(sup.position), 2.1, Color("66d9ef"))

	for chest in game.crate_nodes:
		var opened = chest.get_meta("title") in game.rules.crates
		var tier = int(chest.get_meta("tier"))
		var c = Color("5f7d73") if opened else (Color("ffd15c") if tier == 3 else (Color("cf8aff") if tier == 2 else Color("74e3a3")))
		draw_rect(Rect2(point(chest.position) - Vector2(3, 3), Vector2(6, 6)), c)

	var exit_point = point(game.exit_position)
	var ready = game.rules.can_extract()
	draw_circle(exit_point, 5.2, Color("76e5bc") if ready else Color("d8b26e"), false, 2.0)

	var p = point(game.player.position)
	var f = Vector2(-sin(game.player.yaw), -cos(game.player.yaw))
	draw_colored_polygon(PackedVector2Array([p + f * 7.2, p + f.rotated(2.45) * 5.0, p + f.rotated(-2.45) * 5.0]), Color("f4fff8"))
