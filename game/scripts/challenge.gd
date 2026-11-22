extends Node3D
var station_id = ""
var title = ""
var targets = []
var materials = []
var boards = []
var terminal_label: Label3D
var boards_allowed: bool = true

func setup(game, data: Dictionary):
	station_id = data.id
	title = data.title
	position = game.active_layout.on_ground(data.at)
	set_meta("station_id",station_id)
	var rel_ground = game.active_layout.min_ground_height(position.x + 2.0, position.z + 2.0, 0.55) - position.y
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("2b4842")
	body_mat.metallic = 0.45
	body_mat.roughness = 0.52
	var pedestal = game._mesh_box(self, Vector3(2, rel_ground + 0.50, 2), Vector3(0.76, 1.55, 0.58), Color("2b4842"), true)
	pedestal.material_override = body_mat
	var screen = game._mesh_box(self, Vector3(2, rel_ground + 0.92, 2.30), Vector3(0.58, 0.42, 0.04), Color("67e0b4"))
	screen.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terminal_label = game._label3d(self, title + "\n[F] 单词挑战", Vector3(2, rel_ground + 1.88, 2), 30, game.MINT)
	for i in 4:
		var board = StaticBody3D.new()
		board.collision_layer = 3
		board.collision_mask = 0
		board.set_meta("answer_index", i)
		board.set_meta("station_id", station_id)
		var local_pos := Vector3(-5.7 + i * 3.8, 1.9, -10.0)
		var yaw_rot := 0.0
		if station_id == "camp":
			local_pos = Vector3(-1.7 + i * 3.8, 1.9, -13.0)
		elif station_id == "forest":
			# v0.8.2_dev2 D2-6: Shift Forest Outpost board row slightly East off the western hillside so Board D never clips into terrain!
			local_pos = Vector3(-7.4, 1.9, -5.7 + i * 3.8)
			yaw_rot = PI / 2.0
		else:
			local_pos = Vector3(-10.0, 1.9, -5.7 + i * 3.8)
			yaw_rot = PI / 2.0
		# Sample actual terrain across full 3.25m board width + thickness footprint so every corner sits cleanly >= 0.90m above hillside terrain!
		var wx: float = position.x + local_pos.x
		var wz: float = position.z + local_pos.z
		var max_ground_y: float = float(game.terrain_height(wx, wz))
		var min_ground_y: float = max_ground_y
		for s_off in [-1.65, -0.85, 0.0, 0.85, 1.65]:
			for d_off in [-0.30, 0.0, 0.30]:
				var sx: float = wx + (d_off if yaw_rot > 0.5 else s_off)
				var sz: float = wz + (s_off if yaw_rot > 0.5 else d_off)
				var h_pt: float = float(game.terrain_height(sx, sz))
				max_ground_y = maxf(max_ground_y, h_pt)
				min_ground_y = minf(min_ground_y, h_pt)
		var board_rel_y: float = maxf(1.9, (max_ground_y - position.y) + 1.72)
		board.position = Vector3(local_pos.x, board_rel_y, local_pos.z)
		board.rotation.y = yaw_rot
		add_child(board)
		boards.append(board)
		var mesh = game._mesh_box(board, Vector3.ZERO, Vector3(3.25, 1.6, 0.24), Color("182e30"))
		mesh.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		materials.append(mesh.material_override)
		var post_drop: float = maxf(1.4, (board_rel_y - (min_ground_y - position.y)) + 0.35)
		game._mesh_box(board, Vector3(0, -0.75 - post_drop * 0.5, 0), Vector3(0.14, post_drop, 0.16), Color("4e6557"), true)
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

func set_boards_visible(vis: bool):
	var show_now: bool = vis and boards_allowed
	for board in boards:
		board.visible = show_now
		board.collision_layer = 3 if show_now else 0
		for post in board.find_children("*", "StaticBody3D", true, false):
			post.collision_layer = 1 if show_now else 0

func enable_boards(enabled: bool):
	boards_allowed = enabled
	terminal_label.visible = true
	if not enabled:
		set_boards_visible(false)
	terminal_label.text = title + ("\n[F] 单词挑战" if enabled else "\n词兵行动")

func clear():
	# v0.8.1 FB-4: Hide idle target boards instead of displaying legacy placeholder signs ("前往终端/按F开始/单词挑战/探索烟山")
	for i in 4:
		targets[i].text = ""
		targets[i].font_size = 48
		materials[i].albedo_color = Color("182e30")
	set_boards_visible(false)
