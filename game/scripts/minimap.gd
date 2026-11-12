extends Control
var game

func _process(_delta):
	queue_redraw()

func point(v: Vector3) -> Vector2:
	return Vector2(83,83)+Vector2(v.x,v.z+44)*0.88

func _draw():
	draw_circle(Vector2(83,83), 77, Color("102924"))
	for r in [30,55,77]:
		draw_arc(Vector2(83,83),r,0,TAU,64,Color(0.35,0.65,0.56,0.2),1,true)
	draw_line(Vector2(6,83),Vector2(160,83),Color(0.4,0.7,0.6,0.15))
	draw_line(Vector2(83,6),Vector2(83,160),Color(0.4,0.7,0.6,0.15))
	if not is_instance_valid(game.player):
		return
	for i in game.Layout.ROUTE.size()-1:
		draw_line(point(game.Layout.ROUTE[i]),point(game.Layout.ROUTE[i+1]),Color("8e9869"),3,true)
	for branch in game.Layout.BRANCHES:
		for i in branch.size()-1:draw_line(point(branch[i]),point(branch[i+1]),Color("6c8061"),1,true)
	for at in [game.Layout.POEM,game.Layout.MATH,game.Layout.CLUE]:
		draw_circle(point(at),3,Color("e0c991"),false,1.4)
	for station in game.Layout.STATIONS:
		draw_circle(point(station.at),4,Color("94bde0"))
	for chest in game.crate_nodes:
		draw_rect(Rect2(point(chest.position)-Vector2(3,3),Vector2(6,6)),Color("f2c77c"))
	if is_instance_valid(game.combat) and game.combat.in_field() and game.combat.zone>=0:
		for soldier in game.combat.troops[game.combat.zone]:
			if not soldier.defeated:
				draw_circle(point(soldier.position),2.2,Color("f28c64"))
	var exit_point = point(game.exit_position)
	draw_circle(exit_point,5,Color("76e5bc"),false,2)
	var p = point(game.player.position)
	var f = Vector2(-sin(game.player.yaw),-cos(game.player.yaw))
	draw_colored_polygon(PackedVector2Array([p+f*7,p+f.rotated(2.45)*5,p+f.rotated(-2.45)*5]),Color("ecf5e7"))
