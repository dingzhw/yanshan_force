extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var checked=0;var floating=0;var maximum=-INF
	for prop in get_nodes_in_group("solid_props"):
		if prop.get_parent()!=game.landscape or prop.get_meta("physics_profile","")!="convex":continue
		var points=[];var bottom=INF;var top=-INF
		for mesh in prop.find_children("*","MeshInstance3D",true,false):
			for vertex in mesh.mesh.get_faces():
				var p=mesh.global_transform*vertex;points.append(p);bottom=minf(bottom,p.y);top=maxf(top,p.y)
		var clearance=INF
		for p in points:
			if p.y<bottom+(top-bottom)*0.10:clearance=minf(clearance,p.y-game.terrain_height(p.x,p.z))
		maximum=maxf(maximum,clearance);checked+=1
		if clearance>0.12:
			floating+=1;print("FLOATING_PROP ",prop.position," clearance=",clearance)
	print("PROP_CONTACT checked=",checked," floating=",floating," max_clearance=",maximum)
	game.queue_free();await process_frame;quit(1 if floating else 0)
