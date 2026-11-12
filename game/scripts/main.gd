extends Node3D

const Rules = preload("res://scripts/rules.gd")
const Player = preload("res://scripts/player.gd")
const MapWidget = preload("res://scripts/minimap.gd")
const Props = preload("res://scripts/props.gd")
const Layout = preload("res://scripts/layout.gd")
const Challenge = preload("res://scripts/challenge.gd")
const Combat = preload("res://scripts/combat.gd")
const PerformanceTour = preload("res://scripts/performance_tour.gd")
const VERSION = "0.4.0"
const SliceWorld = preload("res://scripts/slice_world.gd")
const WeaponView = preload("res://scripts/weapon.gd")
const Exploration = preload("res://scripts/exploration.gd")
const INK = Color("101f29")
const MINT = Color("8de8c0")
const CREAM = Color("f1f2df")
const GOLD = Color("f4ca84")
var rules = Rules.new()
var font: Font
var player
var words = []
var pool = []
var question_queue = []
var question = {}
var choices = []
var answer_index = -1
var stations = []
var active_station = -1
var targets = []
var target_materials = []
var crate_nodes = []
var pickup_nodes = []
var exit_position = Layout.on_ground(Layout.EXIT)
var time_left = 480.0
var extraction_left = 0.0
var next_question_left = 0.0
var wrong_words = []
var paused = true
var scene_cache = {}
var sound_cache = {}
var ui: Control
var hud: Control
var menu: Control
var menu_title: Label
var menu_summary: Label
var menu_finance: Label
var menu_status: Label
var start_button: Button
var sell_button: Button
var shop_buttons = {}
var unit_picker: OptionButton
var include_extra: CheckBox
var question_label: Label
var unit_label: Label
var stat_label: Label
var mission_label: Label
var bag_label: Label
var ammo_label: Label
var interaction_label: Label
var feedback_label: Label
var feedback_panel: Panel
var feedback_left = 0.0
var closest_interaction
var screen_flash: ColorRect
var qa_mode = false
var screenshot_path = ""
var profile_path_override = ""
var guide_label: Label
var fps_label: Label
var review_overlay: Control
var review_text: RichTextLabel
var review_button: Button
var tutorial_moved = false
var render_age = 0.0
var abandon_button: Button
var practice_button: Button
var combat: Node3D
var combat_panel: Panel
var combat_label: Label
var exploration
var landscape

func _ready():
	qa_mode = "--qa" in OS.get_cmdline_user_args() or "--hardware-check" in OS.get_cmdline_user_args()
	var variable_font = FontVariation.new()
	variable_font.base_font = load("res://assets/font/NotoSansSC.ttf")
	variable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
	font = variable_font
	_load_words()
	_load_profile()
	_build_world()
	player = Player.new()
	player.game = self
	add_child(player)
	player.position = Vector3(0, 0.15, 4.5)
	combat = Combat.new()
	combat.game = self
	add_child(combat)
	_build_ui()
	exploration = Exploration.new()
	add_child(exploration)
	exploration.setup(self)
	_refresh_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--hardware-check" in OS.get_cmdline_user_args():
		var tour = PerformanceTour.new()
		tour.game = self
		add_child(tour)
		tour.call_deferred("run")
		return
	if "--preview" in OS.get_cmdline_user_args():
		start_action()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_capture("preview-v02.png")
	if qa_mode and "--preview-combat" in OS.get_cmdline_user_args():
		seed(42030)
		start_action(true)
		await get_tree().physics_frame
		interact()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_capture("preview-range.png")
		combat.range_left = 0.01
		await get_tree().process_frame
		await get_tree().process_frame
		player.position = stations[1].position+Vector3(0,0.1,2)
		await get_tree().create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		_capture("preview-combat.png")
	if "--auto-quit" in OS.get_cmdline_user_args():
		await get_tree().create_timer(3).timeout
		get_tree().quit()

func _load_words():
	for file in DirAccess.get_files_at("res://data/wordpacks"):
		if file.ends_with(".json"):
			var pack = JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/" + file))
			if pack is Dictionary and pack.get("schema_version",0) == 1:
				words.append_array(pack.get("entries",[]))
	assert(words.size() >= 4, "词库至少需要四个词条")

func _save_path() -> String:
	if profile_path_override != "":
		return profile_path_override
	return "user://qa-profile.json" if qa_mode else "user://profile-v01.json"

func _load_profile():
	if (qa_mode and profile_path_override == "") or not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if data is Dictionary:
		for key in rules.profile:
			if data.has(key) and typeof(data[key]) == typeof(rules.profile[key]):
				rules.profile[key] = data[key]
		# JSON numbers are floats; persistent integer balances are normalized.
		for key in ["coins","xp","points","extractions"]:
			rules.profile[key] = maxi(0,int(data.get(key,0)))

func _save():
	if qa_mode and profile_path_override == "":
		return
	var file = FileAccess.open(_save_path() + ".tmp",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(rules.profile,"\t"))
		file.close()
		DirAccess.rename_absolute(_save_path()+".tmp",_save_path())

func terrain_height(x: float, z: float) -> float:
	return Layout.height(x,z)

func _material(color: Color, unshaded = false) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _mesh_box(parent: Node3D, at: Vector3, dimensions: Vector3, color: Color, collidable = false):
	var node = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = dimensions
	node.mesh = shape
	node.material_override = _material(color)
	node.position = at
	parent.add_child(node)
	if collidable:
		var body = StaticBody3D.new()
		parent.add_child(body)
		body.position = at
		var collision = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = dimensions
		collision.shape = box
		body.add_child(collision)
	return node

func _label3d(parent: Node3D, text: String, at: Vector3, size = 60, color = CREAM):
	var label = Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = 0.008
	label.position = at
	label.modulate = color
	label.outline_size = 9
	label.outline_modulate = Color("182b27")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	parent.add_child(label)
	return label

func _bounds(node: Node3D, transform_so_far = Transform3D.IDENTITY) -> AABB:
	var xf = transform_so_far * node.transform
	var result = AABB()
	if node is MeshInstance3D:
		result = xf * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var bound = _bounds(child,xf)
			if bound.size.length() > 0:
				result = bound if result.size.length() == 0 else result.merge(bound)
	return result

func _model(parent: Node3D, path: String, at: Vector3, height: float, angle = 0.0, physics = ""):
	if not scene_cache.has(path):
		scene_cache[path] = load(path)
	var instance = scene_cache[path].instantiate()
	var bound = _bounds(instance)
	var scale_factor = height / maxf(bound.size.y,0.01)
	var pivot = Node3D.new()
	parent.add_child(pivot)
	pivot.position = at
	pivot.rotation.y = angle
	pivot.add_child(instance)
	instance.scale *= scale_factor
	instance.position -= Vector3(bound.get_center().x,bound.position.y,bound.get_center().z)*scale_factor
	for mesh in instance.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if physics != "":
		Props.mesh_collision(pivot, physics)
	return pivot

func _build_world():
	landscape = SliceWorld.new()
	add_child(landscape)
	landscape.setup(self)

func _build_tower(at: Vector3):
	var tower = Node3D.new()
	tower.position = at
	add_child(tower)
	for x in [-0.9,0.9]:
		for z in [-0.9,0.9]:
			_mesh_box(tower,Vector3(x,3.4,z),Vector3(0.16,6.8,0.16),Color("636d61"),true)
	for y in [1.0,3.3,5.8]:
		_mesh_box(tower,Vector3(0,y,0),Vector3(2.1,0.1,2.1),Color("4a5a4e"),true)
	_mesh_box(tower,Vector3(0,7.7,0),Vector3(0.13,2.6,0.13),Color("d0c6a5"))
	_mesh_box(tower,Vector3(0,7.9,0),Vector3(2.4,0.08,0.08),Color("d0c6a5"))
	_label3d(tower,"烟山观察哨",Vector3(0,6.5,0),43,GOLD)

func _make_crate(title: String,tier: int,at: Vector3):
	var crate = Node3D.new()
	crate.position = at
	crate.set_meta("title",title)
	crate.set_meta("tier",tier)
	add_child(crate)
	_model(crate,"res://assets/survival/chest.glb",Vector3.ZERO,0.85,0,"convex")
	_label3d(crate,title+"\n"+("5题 · 70%正确率" if tier==1 else "10题 · 85%正确率"),Vector3(0,1.7,0),39,GOLD)
	crate_nodes.append(crate)

func attach_weapon(parent: Node3D):
	var view = WeaponView.new()
	view.game = self
	parent.add_child(view)
	return view

func play_sound(id: String, volume = -16):
	if DisplayServer.get_name() == "headless":
		return
	var path = "res://assets/fps/sounds/"+id+".ogg"
	if not sound_cache.has(id):
		sound_cache[id] = load(path)
	var sound = AudioStreamPlayer.new()
	sound.stream = sound_cache[id]
	sound.volume_db = volume
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func _exit_tree():
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

func _panel(parent: Control,rect: Rect2,color = Color(0.045,0.09,0.12,0.91),border = Color(0.45,0.72,0.60,0.3)):
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	return panel

func _text(parent: Control,text: String,at: Vector2,size: Vector2,font_size = 20,color = CREAM):
	var label = Label.new()
	label.text = text
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Control,text: String,rect: Rect2,callback: Callable,accent = false):
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size",18)
	for style_name in ["normal","hover","pressed","disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("85d8b1") if accent else Color("243a40")
		if style_name == "hover":
			style.bg_color = style.bg_color.lightened(0.12)
		if style_name == "disabled":
			style.bg_color = Color("203037")
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(style_name,style)
	button.add_theme_color_override("font_color",INK if accent else CREAM)
	button.add_theme_color_override("font_hover_color",INK if accent else CREAM)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Theme.new()
	ui.theme.default_font = font
	canvas.add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	_panel(hud,Rect2(22,18,1236,54))
	_text(hud,"YANSHAN  /  烟山基地",Vector2(40,28),Vector2(310,32),22,MINT)
	stat_label = _text(hud,"",Vector2(355,29),Vector2(890,32),20)
	fps_label = _text(hud,"",Vector2(1162,33),Vector2(87,24),14,MINT)
	_panel(hud,Rect2(22,92,246,174))
	_text(hud,"本 局 任 务",Vector2(40,106),Vector2(210,30),17,GOLD)
	mission_label = _text(hud,"",Vector2(40,143),Vector2(215,115),17)
	_panel(hud,Rect2(22,280,246,190))
	guide_label = _text(hud,"",Vector2(40,294),Vector2(215,167),16)
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel(hud,Rect2(296,92,688,112))
	question_label = _text(hud,"",Vector2(318,104),Vector2(644,65),30)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label = _text(hud,"",Vector2(320,172),Vector2(640,24),14,MINT)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel(hud,Rect2(1088,92,170,209))
	_text(hud,"N  /  A → B 山路",Vector2(1104,100),Vector2(148,25),13,MINT)
	var map = MapWidget.new()
	map.game = self
	map.position = Vector2(1090,126)
	map.size = Vector2(166,166)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(map)
	combat_panel = _panel(hud,Rect2(1013,313,245,123))
	combat_label = _text(combat_panel,"",Vector2(15,12),Vector2(215,98),16)
	combat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_panel.hide()
	_panel(hud,Rect2(22,494,246,166))
	_text(hud,"随 身 背 包",Vector2(40,506),Vector2(210,25),15,GOLD)
	bag_label = _text(hud,"",Vector2(40,537),Vector2(215,118),16)
	_panel(hud,Rect2(1030,572,228,103))
	ammo_label = _text(hud,"",Vector2(1048,582),Vector2(202,86),20)
	_panel(hud,Rect2(326,592,630,44))
	interaction_label = _text(hud,"",Vector2(334,592),Vector2(614,44),19,GOLD)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_panel = _panel(hud,Rect2(280,477,720,80))
	feedback_panel.hide()
	feedback_label = _text(hud,"",Vector2(295,482),Vector2(690,70),22,MINT)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var crosshair = _text(hud,"+",Vector2(622,338),Vector2(36,42),29)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(hud,"WASD 移动   Shift 奔跑   空格 跳跃   左键 射击   右键 瞄准   R 换弹   E 交互   Esc 暂停",Vector2(285,681),Vector2(735,25),13,Color("cfdfd0"))
	screen_flash = ColorRect.new()
	screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_flash.color = Color(0.4,1,0.7,0)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen_flash)
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.035,0.07,0.085,0.54)
	menu.add_child(veil)
	_panel(menu,Rect2(98,70,1084,575),Color(0.04,0.085,0.105,0.96))
	menu_title = _text(menu,"烟山基地",Vector2(130,98),Vector2(590,68),44,MINT)
	_text(menu,"英语搜撤行动  /  PLAYTEST "+VERSION,Vector2(132,165),Vector2(530,34),19,GOLD)
	_button(menu,"退出",Rect2(1085,102,65,36),func(): get_tree().quit())
	abandon_button = _button(menu,"放弃本局",Rect2(939,102,130,36),func(): _end_run(false))
	abandon_button.hide()
	menu_summary = _text(menu,"",Vector2(132,215),Vector2(465,115),17)
	menu_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review_button = _button(menu,"查看本局全部错词",Rect2(132,323,460,26),_show_review)
	review_button.hide()
	unit_picker = OptionButton.new()
	unit_picker.position = Vector2(132,352)
	unit_picker.size = Vector2(306,42)
	unit_picker.add_item("全部单元 · 175 条词汇")
	for i in range(1,9):
		unit_picker.add_item("Unit "+str(i))
	menu.add_child(unit_picker)
	include_extra = CheckBox.new()
	include_extra.text = "含拓展词与专名"
	include_extra.position = Vector2(132,400)
	include_extra.button_pressed = true
	include_extra.add_theme_font_size_override("font_size",17)
	menu.add_child(include_extra)
	start_button = _button(menu,"部署词兵行动  →",Rect2(132,454,270,54),start_action.bind(true),true)
	practice_button = _button(menu,"自由练习",Rect2(414,454,178,54),start_action)
	_text(menu,"建议游玩 5–8 分钟 · A营地 → B竹林\n35秒热身，沿路探索、识词与搜集。\n100分撤离 · 数学/古诗机关可选",Vector2(132,528),Vector2(480,89),16,Color("b6cbbd"))
	menu_finance = _text(menu,"",Vector2(650,112),Vector2(420,76),19,GOLD)
	_text(menu,"仓 库 与 补 给",Vector2(650,217),Vector2(420,28),22,MINT)
	sell_button = _button(menu,"出售仓库物资",Rect2(650,262,500,40),_sell)
	var y = 316
	for id in ["magazine","backpack","forest_skin","scout","reward_point"]:
		shop_buttons[id] = _button(menu,"",Rect2(650,y,500,40),_buy.bind(id))
		y += 48
	menu_status = _text(menu,"书后词表 175 条 · 单人离线 · 进度自动保存",Vector2(650,570),Vector2(510,55),14,Color("b6cbbd"))
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review_overlay = Control.new()
	review_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(review_overlay)
	var shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02,0.04,0.04,0.92)
	review_overlay.add_child(shade)
	_panel(review_overlay,Rect2(190,80,900,560))
	_text(review_overlay,"本局错词 · 再记一遍",Vector2(220,103),Vector2(700,44),28,MINT)
	_button(review_overlay,"返回",Rect2(947,105,105,40),func(): review_overlay.hide())
	review_text = RichTextLabel.new()
	review_text.position = Vector2(220,170)
	review_text.size = Vector2(830,430)
	review_text.add_theme_font_size_override("normal_font_size",23)
	review_text.bbcode_enabled = false
	review_overlay.add_child(review_text)
	review_overlay.hide()
	hud.hide()

func _show_review():
	var lines = []
	for word in wrong_words:
		lines.append("%s  —  %s\nUnit %d · 课本第 %d 页\n" % [word.english,word.chinese,word.unit,word.textbook_page])
	review_text.text = "\n".join(lines) if not lines.is_empty() else "本局还没有错词。"
	review_text.scroll_to_line(0)
	review_overlay.show()

func _refresh_menu(result = ""):
	menu_finance.text = "Lv.%d  ·  %d / 100 经验\n货币 %d   |   奖励积分 %d" % [rules.level(),rules.profile.xp%100,rules.profile.coins,rules.profile.points]
	menu_title.text = result if result != "" else "烟山基地"
	if result == "":
		menu_summary.text = "山脚出发，沿竹林小路前往B补给点。\n找纸条、解石刻和机关，带回物资。\n答对+10分，100分撤离；机关可选。"
	sell_button.text = "出售仓库物资（%d 件）" % rules.profile.warehouse.size()
	sell_button.disabled = rules.profile.warehouse.is_empty() or rules.phase in ["active","extracting"]
	for id in shop_buttons:
		var item = Rules.ITEMS[id]
		var owned = id in rules.profile.owned
		shop_buttons[id].text = item.title+"    "+("已拥有" if owned else str(item.cost)+" 币")
		shop_buttons[id].disabled = owned or rules.profile.coins < item.cost or rules.phase in ["active","extracting"]
	start_button.text = "继续行动  →" if rules.phase in ["active","extracting"] else "部署词兵行动  →"
	practice_button.visible = rules.phase not in ["active","extracting"]
	abandon_button.visible = rules.phase in ["active","extracting"]
	unit_picker.disabled = rules.phase in ["active","extracting"]
	include_extra.disabled = unit_picker.disabled

func _sell():
	var value = rules.sell_all()
	_save()
	_refresh_menu()
	menu_status.text = "物资已出售，获得 %d 枚游戏货币。" % value

func _buy(id: String):
	if rules.purchase(id):
		_save()
		_refresh_menu()
		menu_status.text = "已兑换："+Rules.ITEMS[id].title
		if id == "reward_point":
			menu_status.text += "。现实奖励兑换规则由家长约定。"

func start_action(as_combat = false):
	if rules.phase not in ["active","extracting"]:
		review_button.hide()
		review_overlay.hide()
		tutorial_moved = false
		_leave_station()
		rules.start_run()
		exploration.reset()
		if as_combat: combat.begin()
		else: combat.stop()
		time_left = 480
		next_question_left = 0
		wrong_words = []
		pool = []
		for word in words:
			if unit_picker.selected > 0 and word.unit != unit_picker.selected:
				continue
			if not include_extra.button_pressed and (not word.core or word.proper_name):
				continue
			pool.append(word)
		if pool.size() < 4:
			pool = words.duplicate()
		question_queue = pool.duplicate()
		question_queue.shuffle()
		player.position = Layout.on_ground(Layout.SPAWN)+Vector3.UP*0.15
		player.yaw = 0
		player.pitch = 0
		player.ammo = rules.magazine()
		player.reload_left = 0
		player.cooldown = 0
		player.recoil = 0
		for node in pickup_nodes:
			Props.set_enabled(node,true)
		for node in crate_nodes:
			node.get_child(node.get_child_count()-1).modulate = GOLD
		for child in player.weapon_root.get_children():
			child.queue_free()
		player.weapon_view = attach_weapon(player.weapon_root)
		_next_question()
	paused = false
	get_viewport().gui_release_focus()
	player.clear_movement_input()
	player.active = true
	player.camera.fov = 75
	menu.hide()
	hud.show()
	combat_panel.visible = combat.stage!=Combat.Stage.OFF
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _next_question():
	if question_queue.is_empty():
		question_queue = pool.duplicate()
		question_queue.shuffle()
	question = question_queue.pop_back()
	# Revisit a missed entry periodically, after other questions have intervened.
	if rules.answered > 0 and rules.answered%6 == 0 and wrong_words.size() > 0:
		question = wrong_words.pick_random()
	choices = [question]
	var distractors = pool.duplicate()
	distractors.shuffle()
	for candidate in distractors:
		var duplicate = false
		for chosen in choices:
			if candidate.english.to_lower() == chosen.english.to_lower() or candidate.chinese == chosen.chinese:
				duplicate = true
		if not duplicate:
			choices.append(candidate)
		if choices.size() == 4:
			break
	choices.shuffle()
	for i in choices.size():
		if choices[i].id == question.id:
			answer_index = i
	rules.open_question()
	_sync_question()

func _sync_question():
	if combat.in_field():
		combat.show_question()
		return
	if active_station < 0:
		question_label.text = "靠近绿色终端，按 E 开始挑战"
		unit_label.text = "A山脚营地 → 林间前哨 → B竹林补给点"
		if combat.in_warmup():
			question_label.text = "在营地终端旁按 E 开始限时热身"
			unit_label.text = "热身成绩决定后续词兵的基础伤害"
		return
	for i in choices.size():
		_fit_word(targets[i],choices[i].english)
		target_materials[i].albedo_color = Color("182e30")
	question_label.text = question.chinese
	unit_label.text = "%s · Unit %d · 课本第 %d 页" % [stations[active_station].title,question.unit,question.textbook_page]
	if not rules.question_open:
		target_materials[answer_index].albedo_color = Color("3b8a62")
		unit_label.text = "已结算 · 下一题即将出现"

func _fit_word(label: Label3D,word: String,height_limit = 138):
	label.text = word.replace("’","'")
	label.font_size = 64
	var parts = label.text.split(" ")
	while label.font_size>28:
		var fits = font.get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,label.width,label.font_size).y<=height_limit
		for part in parts:
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x>label.width-55:
				fits = false
				break
		if fits: break
		label.font_size -= 2

func _activate_station(index: int):
	if combat.in_field() or (combat.in_warmup() and index!=0):
		return
	if index < 0 or index >= stations.size() or player.position.distance_to(_interaction_position(stations[index]))>3.2 or not _can_interact(stations[index]):
		return
	if active_station >= 0: stations[active_station].clear()
	active_station = index
	targets = stations[index].targets
	target_materials = stations[index].materials
	combat.start_range()
	_sync_question()
	_notice(stations[index].title+" · 看中文，射击对应英文。",MINT)

func _leave_station():
	if active_station >= 0: stations[active_station].clear()
	active_station = -1
	targets = []
	target_materials = []
	_sync_question()

func _interaction_position(node: Node3D) -> Vector3:
	return node.global_position + (Vector3(2,0,2) if node.has_meta("station_id") else Vector3.ZERO)

func _can_interact(node: Node3D) -> bool:
	var endpoint = _interaction_position(node)+Vector3(0,0.6,0)
	var query = PhysicsRayQueryParameters3D.create(player.camera.global_position,endpoint,3,[player.get_rid()])
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == node or node.is_ancestor_of(hit.collider)

func fire(camera: Camera3D):
	if rules.phase != "active" or paused:
		return
	rules.shots += 1
	if not combat.in_field() and (active_station < 0 or player.position.distance_to(stations[active_station].position)>15):
		return
	var from = camera.global_position
	var to = from - camera.global_basis.z*80
	var query = PhysicsRayQueryParameters3D.create(from,to,7 if combat.in_field() else 3,[player.get_rid()])
	query.collide_with_areas = combat.in_field()
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if combat.in_field():
		if result: combat.hit(result.collider)
		return
	if result and active_station >= 0 and result.collider.get_meta("station_id", "") == stations[active_station].station_id and result.collider.has_meta("answer_index"):
		resolve_answer(int(result.collider.get_meta("answer_index")))

func resolve_answer(index: int,mobile = false):
	if (not mobile and active_station<0) or index<0 or index>=choices.size():
		return
	var correct = index == answer_index
	var warmup = combat.stage==Combat.Stage.RANGE
	if warmup:
		if not rules.question_open: return
		rules.question_open = false
		combat.record_range(correct)
	elif not rules.answer(correct):
		return
	if mobile:
		combat.record_field(correct)
		combat.hit_feedback(index,correct)
	elif correct:
		target_materials[index].albedo_color = Color("3b8a62")
	else:
		target_materials[index].albedo_color = Color("8d4b47")
		target_materials[answer_index].albedo_color = Color("3b8a62")
	if correct:
		_notice(("热身答对 · " if warmup else "答对了！ +10 分 · ")+question.english,MINT)
		if not warmup and rules.correct%3 == 0:
			rules.add_loot("知识芯片",20+maxi(0,rules.level()-1)*2)
	else:
		var warning = "\n词兵强化 7 秒 · 当前伤害 ×%.2f" % combat.damage_multiplier() if mobile else ""
		_notice("正确答案："+question.english+"  ·  "+question.chinese+warning,Color("f0be9a"))
		if question not in wrong_words:
			wrong_words.append(question)
	screen_flash.color = Color(0.3,1,0.65,0.07) if correct else Color(1,0.4,0.2,0.07)
	next_question_left = (0.85 if correct else 1.55) if warmup else (1.65 if correct else 2.6)
	unit_label.text = "已结算 · 下一题即将出现"

func _notice(text: String,color = GOLD):
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color",color)
	feedback_left = 3.5

func _process(delta):
	render_age += delta
	if not is_instance_valid(player) or not is_instance_valid(stat_label):
		return
	if paused:
		return
	exploration.update(delta)
	combat.update(delta)
	if active_station >= 0 and player.position.distance_to(stations[active_station].position)>15:
		_leave_station()
	if rules.phase in ["active","extracting"] and not combat.in_warmup():
		time_left -= delta
		if time_left <= 0:
			_end_run(false)
			return
	if rules.phase == "active" and next_question_left > 0:
		next_question_left -= delta
		if next_question_left <= 0:
			_next_question()
	if rules.phase == "extracting":
		if player.position.distance_to(exit_position) > 4:
			rules.phase = "active"
			_next_question()
			_notice("已离开撤离圈，撤离取消。")
		else:
			extraction_left -= delta
			if extraction_left <= 0:
				_end_run(true)
				return
	feedback_left = maxf(0,feedback_left-delta)
	feedback_label.visible = feedback_left > 0
	feedback_panel.visible = feedback_label.visible
	screen_flash.color.a = maxf(0,screen_flash.color.a-delta*0.16)
	stat_label.text = "积分 %03d   |   正确率 %d%%（%d/%d）   |   %02d:%02d   |   Lv.%d" % [rules.score,roundi(rules.accuracy()*100),rules.correct,rules.answered,int(time_left)/60,int(time_left)%60,rules.level()]
	fps_label.text = "%d FPS" % Engine.get_frames_per_second() if render_age>2 else "预热中"
	mission_label.text = "① 单词挑战：答对 +10\n② 普通箱："+_crate_progress(1)+"\n③ 高级箱："+_crate_progress(2)+"\n④ 撤离："+("已解锁" if rules.score>=100 else "还差 %d 分" % (100-rules.score))
	_update_guide()
	if not combat.in_warmup(): guide_label.text += "\n"+exploration.status_text()
	_update_combat_hud()
	var names = []
	for item in rules.bag:
		if not item.title in names:
			names.append(item.title)
	bag_label.text = "%d / %d 格  ·  估值 %d 币\n%s\n\n撤离成功后物资入库" % [rules.bag.size(),rules.capacity(),rules.bag_value(),"、".join(names) if names.size()>0 else "林间有普通补给可拾取"]
	bag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ammo_label.text = "YS-04  /  训练步枪\n"+("换弹中…" if player.reload_left>0 else "%02d / %02d   [R] 换弹" % [player.ammo,rules.magazine()])+"\n"+("林地涂装" if "forest_skin" in rules.profile.owned else "单发 · 精准识词")
	_update_interaction()

func _crate_progress(tier: int) -> String:
	var minimum = 5 if tier == 1 else 10
	var percent = 70 if tier == 1 else 85
	if rules.crate_ready(tier): return "可开启"
	if rules.answered < minimum: return "还差 %d 题/%d%%" % [minimum-rules.answered,percent]
	return "正确率需 %d%%" % percent

func _update_guide():
	if combat.in_warmup():
		guide_label.text = "35 秒热身\n按 E 启动营地靶场。\n命中越多、正确率越高，\n后续词兵的火力越弱。"
		return
	if combat.in_field() and rules.score<100:
		guide_label.text = "词兵行动\n看中文，射击对应胸牌。\n冲刺和跳跃更容易躲枪。\n橙色预警时也可找掩体。"
		return
	if player.position.distance_to(Vector3(0,0,4.5))>1.0: tutorial_moved = true
	if rules.score>=100:
		guide_label.text = "撤离已解锁\n沿小地图绿色圆圈前进。\n进入圈内按 E，停留3秒。\n物资带回后可出售升级。"
	elif not tutorial_moved and rules.answered==0 and active_station<0:
		guide_label.text = "第1步 · 熟悉操作\nWASD 或方向键移动。\n鼠标转向，空格跳跃。\n身旁绿色终端按 E 开始。"
	elif active_station<0:
		guide_label.text = "寻找单词挑战\n小地图蓝点是挑战区域。\n靠近绿色终端，按 E。\n离开后未答题会保留。"
	elif rules.answered==0:
		guide_label.text = "看中文，认英文\n鼠标瞄准前方英文靶牌。\n左键射击，R 换弹。\n第一次击中选项后结算。"
	else:
		guide_label.text = "边学边搜物资\n答对 +10分，打错显示答案。\n正确率：答对数 ÷ 作答数。\n沿山路找箱子，按 E 开启。"

func _update_combat_hud():
	if combat.in_warmup():
		var timing = "等候开始" if combat.stage==Combat.Stage.READY else "%02d 秒" % ceili(combat.range_left)
		combat_label.text = "热身 · "+timing+"\n答对 %d / %d\n预估基础伤害 ×%.2f" % [combat.range_hits,combat.range_answers,Combat.warmup_multiplier(combat.range_hits,combat.range_answers)]
	elif combat.in_field():
		var status = "火力强化 · %.0f 秒" % ceilf(combat.rage_left) if combat.rage_left>0 else "答对可压低敌方火力"
		if combat.miss_left>0:
			status = "敌方打偏了"
		if combat.zone>=0:
			for soldier in combat.troops[combat.zone]:
				if not soldier.defeated and soldier.action==Combat.Soldier.Action.AIM:
					status = "瞄准中 · 跑跳或找掩体"
					break
		combat_label.text = "体力 %d / 100\n无遮挡命中 %d%%\n敌伤 %d/发 · ×%.2f\n%s" % [combat.health,roundi(combat.hit_chance()*100),combat.damage_per_shot(),combat.damage_multiplier(),status]

func _update_interaction():
	if combat.in_warmup():
		interaction_label.text = "[E] 开始热身" if combat.stage==Combat.Stage.READY else "热身倒计时 %d 秒 · 看中文射击" % ceili(combat.range_left)
		return
	closest_interaction = null
	var nearest = 3.2
	for node in pickup_nodes+crate_nodes+stations+exploration.nodes:
		if combat.in_field() and node.has_meta("station_id"):
			continue
		if not node.visible:
			continue
		var distance = player.position.distance_to(_interaction_position(node))
		if distance < nearest and _can_interact(node):
			closest_interaction = node
			nearest = distance
	if rules.phase == "extracting":
		interaction_label.text = "撤离倒计时 %.1f 秒 · 留在绿色圆圈内" % maxf(0,extraction_left)
	elif player.position.distance_to(exit_position)<3.5:
		interaction_label.text = "[E] 开始撤离 · 100 分已达标" if rules.score>=100 else "撤离点未解锁 · 还需 %d 分" % (100-rules.score)
	elif closest_interaction:
		if closest_interaction.has_meta("explore_id"):
			interaction_label.text = "[E] "+closest_interaction.get_meta("prompt")
		elif closest_interaction.has_meta("station_id"):
			interaction_label.text = "[E] 开始/继续 · "+closest_interaction.title
		elif closest_interaction.has_meta("tier"):
			var title = closest_interaction.get_meta("title")
			var tier = closest_interaction.get_meta("tier")
			if title in rules.crates:
				interaction_label.text = title+" · 已收集"
			elif rules.crate_ready(tier):
				interaction_label.text = "[E] 打开 "+title
			else:
				interaction_label.text = title+" · "+_crate_progress(tier)
		else:
			interaction_label.text = "[E] 拾取普通补给 · 估值25币"
	else:
		interaction_label.text = "B点撤离圈  %d m  ·  %s" % [roundi(player.position.distance_to(exit_position)),"已解锁" if rules.score>=100 else "100分解锁"]

func interact():
	if rules.phase != "active" or paused:
		return
	if combat.in_warmup():
		_activate_station(0)
		return
	if player.position.distance_to(exit_position)<3.5:
		if rules.request_extraction():
			extraction_left = 3
		else:
			_notice("累计100分即可撤离，撤离不要求正确率。")
		return
	_update_interaction()
	if not is_instance_valid(closest_interaction):
		return
	if closest_interaction.has_meta("explore_id"):
		exploration.open(closest_interaction)
		return
	if closest_interaction.has_meta("station_id"):
		_activate_station(stations.find(closest_interaction))
		return
	if closest_interaction.has_meta("tier"):
		var title = closest_interaction.get_meta("title")
		if rules.open_crate(title,int(closest_interaction.get_meta("tier"))):
			closest_interaction.get_child(closest_interaction.get_child_count()-1).modulate = MINT
			_notice("补给箱已开启，物资装入背包。",MINT)
		else:
			_notice("请检查答题数、正确率、背包空间或箱子是否已打开。")
	elif rules.add_loot("普通补给",int(closest_interaction.get_meta("value"))):
		Props.set_enabled(closest_interaction,false)
		_notice("已拾取普通补给 · 估值25币",MINT)
	else:
		_notice("背包已满，先带着物资撤离。")

func _end_run(success: bool, title = ""):
	var count = rules.bag.size()
	var value = rules.bag_value()
	if success:
		if not rules.finish_extraction():
			return
		_save()
	else:
		rules.abandon()
	combat.stop()
	paused = true
	player.clear_movement_input()
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show()
	hud.hide()
	_refresh_menu(title if title!="" else ("成功撤离" if success else "行动结束"))
	review_button.visible = not wrong_words.is_empty()
	menu_summary.text = ("带回 %d 件物资，估值 %d 币。\n" % [count,value] if success else "本局物资留在烟山，可重新开始。\n")+"答对 %d / %d 题 · 正确率 %d%%\n" % [rules.correct,rules.answered,roundi(rules.accuracy()*100)]
	menu_summary.text += "探索 %d/3 · 用时 %d分%02d秒\n" % [exploration.completed(),int(exploration.began)/60,int(exploration.began)%60]
	if wrong_words.size() > 0:
		menu_summary.text += "本局有 %d 个错词，点击下方查看。" % wrong_words.size()
	else:
		menu_summary.text += "到右侧出售物资，可以兑换升级配件。"

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if is_instance_valid(exploration) and exploration.busy and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
			exploration.close()
			get_viewport().set_input_as_handled()
			return
		if (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE) and rules.phase in ["active","extracting"]:
			if paused:
				start_action()
			else:
				paused = true
				player.clear_movement_input()
				player.active = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				menu.show()
				hud.hide()
				_refresh_menu("行动暂停")
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F6 or event.keycode == KEY_F6:
			landscape.set_low_quality(not landscape.low_quality)
			var quality_text="画质：低负载 · 实时阴影关闭" if landscape.low_quality else "画质：标准 · 近景实时阴影"
			_notice(quality_text,MINT)
			menu_status.text=quality_text
		elif event.physical_keycode == KEY_F12 or event.keycode == KEY_F12:
			_capture("yanshan-"+str(Time.get_unix_time_from_system())+".png")

func _capture(filename: String):
	var folder = OS.get_environment("DRZ_SCREENSHOT_DIR")
	if folder == "":
		folder = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	screenshot_path = folder.path_join(filename)
	var error = get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("SCREENSHOT ",error," ",screenshot_path)
