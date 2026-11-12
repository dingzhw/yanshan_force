extends Node3D
var station_id = ""
var title = ""
var targets = []
var materials = []
var boards = []
var terminal_label: Label3D

func setup(game, data: Dictionary):
	station_id = data.id
	title = data.title
	position = game.Layout.on_ground(data.at)
	set_meta("station_id",station_id)
	var rel_ground = game.Layout.min_ground_height(position.x + 2.0, position.z + 2.0, 0.55) - position.y
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("2b4842")
	body_mat.metallic = 0.45
	body_mat.roughness = 0.52
	var pedestal = game._mesh_box(self, Vector3(2, rel_ground + 0.50, 2), Vector3(0.76, 1.55, 0.58), Color("2b4842"), true)
	pedestal.material_override = body_mat
	var screen = game._mesh_box(self, Vector3(2, rel_ground + 0.92, 2.30), Vector3(0.58, 0.42, 0.04), Color("67e0b4"))
	screen.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terminal_label = game._label3d(self, title + "\n[E] 单词挑战", Vector3(2, rel_ground + 1.88, 2), 30, game.MINT)
	for i in 4:
		var board = StaticBody3D.new()
		board.collision_layer = 3
		board.collision_mask = 0
		board.set_meta("answer_index",i)
		board.set_meta("station_id",station_id)
		board.position = Vector3(-5.7+i*3.8,1.9,-10)
		if station_id=="camp":board.position=Vector3(-1.7+i*3.8,1.9,-13)
		else:
			board.position=Vector3(-10,1.9,-5.7+i*3.8)
			board.rotation.y=PI/2
		add_child(board)
		boards.append(board)
		var mesh = game._mesh_box(board,Vector3.ZERO,Vector3(3.25,1.6,0.24),Color("182e30"))
		mesh.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		materials.append(mesh.material_override)
		game._mesh_box(board,Vector3(0,-1.3,0),Vector3(0.12,1.4,0.16),Color("4e6557"),true)
		var shape = BoxShape3D.new()
		shape.size = Vector3(3.25,1.6,0.3)
		var collision = CollisionShape3D.new()
		collision.shape = shape
		board.add_child(collision)
		var label = game._label3d(board,"",Vector3(0,-0.10,0.17),64)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = 355
		label.pixel_size = 0.0085
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		targets.append(label)
		var letter = game._label3d(board,char(65+i),Vector3(0,0.66,0.18),28,game.MINT)
		letter.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	clear()

func enable_boards(enabled: bool):
	for board in boards:
		board.visible = enabled
		board.collision_layer = 3 if enabled else 0
		for post in board.find_children("*","StaticBody3D",true,false):
			post.collision_layer = 1 if enabled else 0
	terminal_label.text = title+("\n[E] 单词挑战" if enabled else "\n词兵行动")

func clear():
	for i in 4:
		targets[i].text = ["前往终端","按 E 开始","单词挑战","探索烟山"][i]
		targets[i].font_size = 48
		materials[i].albedo_color = Color("182e30")
