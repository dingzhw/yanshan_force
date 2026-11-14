extends Node3D

const Rules = preload("res://scripts/rules.gd")
const Player = preload("res://scripts/player.gd")
const MapWidget = preload("res://scripts/minimap.gd")
const Props = preload("res://scripts/props.gd")
const Layout = preload("res://scripts/layout.gd")
const Challenge = preload("res://scripts/challenge.gd")
const Combat = preload("res://scripts/combat.gd")
const PerformanceTour = preload("res://scripts/performance_tour.gd")
const CipherTerminal = preload("res://scripts/cipher_terminal.gd")
const VERSION = "0.6.1"
const SliceWorld = preload("res://scripts/slice_world.gd")
const WeaponView = preload("res://scripts/weapon.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Wildlife = preload("res://scripts/wildlife.gd")

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
var sfx_cache = {}
var tts_voice_id = ""
var listening_mode = false
var distractor_rng := RandomNumberGenerator.new()

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
var bag_slots_box: HFlowContainer
var bag_signature = ""
var ammo_label: Label
var interaction_panel: Panel
var interaction_label: Label
var feedback_label: Label
var feedback_panel: Panel
var feedback_left = 0.0
var closest_interaction
var screen_flash: ColorRect
var crosshair_label: Label
var hitmarker_label: Label
var hitmarker_left = 0.0
var threat_banner: Panel
var threat_label: Label
var hp_bar_fill: ColorRect
var shield_bar_fill: ColorRect
var extract_pulse_clock = 0.0

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
var wildlife
var cipher_terminal
var landscape
var minimap

func _ready():
	qa_mode = "--qa" in OS.get_cmdline_user_args() or "--hardware-check" in OS.get_cmdline_user_args()
	distractor_rng.randomize()
	var variable_font = FontVariation.new()
	variable_font.base_font = load("res://assets/font/NotoSansSC.ttf")
	variable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	font = variable_font
	_init_tts()
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
	wildlife = Wildlife.new()
	add_child(wildlife)
	wildlife.setup(self)
	cipher_terminal = CipherTerminal.new()
	add_child(cipher_terminal)
	cipher_terminal.setup(self)
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
		_capture("preview-v05.png")
	if qa_mode and "--preview-combat" in OS.get_cmdline_user_args():
		seed(42030)
		start_action(true)
		await get_tree().physics_frame
		player.position = Layout.on_ground(Layout.COMBAT_ZONES[0].at) + Vector3(0, 0.1, 3.0)
		await get_tree().create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		_capture("preview-combat.png")
	if "--auto-quit" in OS.get_cmdline_user_args():
		await get_tree().create_timer(3).timeout
		get_tree().quit()

func _init_tts():
	if qa_mode or DisplayServer.get_name() == "headless":
		return
	var voices = DisplayServer.tts_get_voices_for_language("en")
	if voices.size() > 0:
		tts_voice_id = voices[0]

func speak_english(text: String):
	if qa_mode or DisplayServer.get_name() == "headless" or tts_voice_id == "" or text.strip_edges() == "":
		return
	var clean = text.replace("...", " ").replace("’", "'").strip_edges()
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(clean, tts_voice_id, 85, 1.0, 0.96)

func replay_question_audio():
	if question.is_empty():
		return
	if tts_voice_id != "":
		speak_english(question.english)
		_notice("🔊 正在朗读英文发音", MINT)
	else:
		_notice("提示：当前环境未检测到系统英文语音包", GOLD)

func _load_words():
	for file in DirAccess.get_files_at("res://data/wordpacks"):
		if file.ends_with(".json"):
			var pack = JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/" + file))
			if pack is Dictionary and pack.get("schema_version", 0) == 1:
				words.append_array(pack.get("entries", []))
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
		for key in ["coins", "xp", "points", "extractions"]:
			rules.profile[key] = maxi(0, int(data.get(key, 0)))
		var normalized_wh = []
		for item in rules.profile.warehouse:
			if item is Dictionary:
				normalized_wh.append({
					"title": str(item.get("title", "物资")),
					"value": maxi(1, int(item.get("value", 20))),
					"rarity": clampi(int(item.get("rarity", 1)), 1, 5)
				})
		rules.profile.warehouse = normalized_wh
	rules.ensure_equipped()

func _save():
	if qa_mode and profile_path_override == "":
		return
	var file = FileAccess.open(_save_path() + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(rules.profile, "\t"))
		file.close()
		DirAccess.rename_absolute(_save_path() + ".tmp", _save_path())

func terrain_height(x: float, z: float) -> float:
	return Layout.height(x, z)

func _material(color: Color, unshaded = false) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
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
	label.outline_modulate = Color("142421")
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
			var bound = _bounds(child, xf)
			if bound.size.length() > 0:
				result = bound if result.size.length() == 0 else result.merge(bound)
	return result

func _model(parent: Node3D, path: String, at: Vector3, height: float, angle = 0.0, physics = ""):
	if not scene_cache.has(path):
		scene_cache[path] = load(path)
	var instance = scene_cache[path].instantiate()
	var bound = _bounds(instance)
	var scale_factor = height / maxf(bound.size.y, 0.01)
	var pivot = Node3D.new()
	parent.add_child(pivot)
	pivot.position = at
	pivot.rotation.y = angle
	pivot.add_child(instance)
	instance.scale *= scale_factor
	instance.position -= Vector3(bound.get_center().x, bound.position.y, bound.get_center().z) * scale_factor
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if physics != "":
		Props.mesh_collision(pivot, physics)
	return pivot

func _build_world():
	landscape = SliceWorld.new()
	add_child(landscape)
	landscape.setup(self)

func _build_tower(at: Vector3) -> Node3D:
	var tower = Node3D.new()
	tower.position = at
	add_child(tower)
	var steel_mat = StandardMaterial3D.new()
	steel_mat.albedo_color = Color("526058")
	steel_mat.albedo_texture = load("res://assets/slice/tree_bark.jpg")
	steel_mat.metallic = 0.35
	steel_mat.roughness = 0.62
	for x in [-0.9, 0.9]:
		for z in [-0.9, 0.9]:
			var leg = _mesh_box(tower, Vector3(x, 3.5, z), Vector3(0.16, 7.0, 0.16), Color("636d61"), true)
			leg.material_override = steel_mat
	for y in [1.0, 3.44, 5.86]:
		var deck = _mesh_box(tower, Vector3(0, y, 0), Vector3(2.1, 0.12, 2.1), Color("4a5a4e"), true)
		deck.material_override = steel_mat
	# Exterior spiraling parkour jump catwalk up to Deck 1 (1.06), Deck 2 (3.50) & Summit (5.92), all dy <= 0.63m with ample headroom
	var steps := [
		[Vector3(0.0, 0.56, 2.05), Vector2(1.60, 1.45)],
		[Vector3(2.05, 1.62, 0.25), Vector2(1.45, 1.55)],
		[Vector3(2.05, 2.24, -1.45), Vector2(1.45, 1.45)],
		[Vector3(0.35, 2.87, -2.05), Vector2(1.55, 1.45)],
		[Vector3(-2.05, 4.08, -0.25), Vector2(1.45, 1.55)],
		[Vector3(-2.05, 4.70, 1.45), Vector2(1.45, 1.45)],
		[Vector3(-0.35, 5.32, 2.05), Vector2(1.60, 1.45)]
	]
	for st_info in steps:
		var top: Vector3 = st_info[0]
		var sz: Vector2 = st_info[1]
		var plat = _mesh_box(tower, Vector3(top.x, top.y - 0.07, top.z), Vector3(sz.x, 0.14, sz.y), Color("806c50"), true)
		plat.material_override = steel_mat
		var trim = _mesh_box(tower, Vector3(top.x, top.y - 0.04, top.z), Vector3(sz.x * 0.94, 0.03, sz.y * 0.94), Color("8de8c0"))
		trim.material_override.roughness = 0.55
		var bracket = _mesh_box(tower, Vector3(top.x * 0.52, top.y - 0.34, top.z * 0.52), Vector3(0.14, 0.56, 0.14), Color("3c4740"))
		bracket.material_override = steel_mat
	_mesh_box(tower, Vector3(-0.78, 7.7, -0.78), Vector3(0.13, 2.6, 0.13), Color("d0c6a5"))
	_mesh_box(tower, Vector3(-0.78, 7.9, -0.78), Vector3(1.4, 0.08, 0.08), Color("d0c6a5"))
	_label3d(tower, "烟山观察哨 · 登顶寻宝", Vector3(0, 7.2, 0), 43, GOLD)
	return tower

func _crate_accent(tier: int) -> Color:
	if tier >= 3:
		return Color("ffd15c")
	if tier == 2:
		return Color("cf8aff")
	return GOLD

func _make_crate(title: String, tier: int, at: Vector3) -> Node3D:
	var crate = Node3D.new()
	crate.position = at
	crate.set_meta("title", title)
	crate.set_meta("tier", tier)
	add_child(crate)
	var req = rules.crate_requirements(tier)
	var lock_desc = "单词+词组双关锁"
	var header = title
	if tier == 2:
		header = "【史诗/大金】" + title
		lock_desc = "词组+短句双关锁"
	elif tier >= 3:
		header = "【传说大金】" + title
		lock_desc = "词汇+词组+整句三重破译"
	var tag = "%s\n%d题 · %d%%正确率 · %s" % [header, req.minimum, roundi(req.accuracy * 100), lock_desc]
	var lbl = _label3d(crate, tag, Vector3(0, 1.75, 0), 30, _crate_accent(tier))
	lbl.pixel_size = 0.0056
	crate_nodes.append(crate)
	return crate

func attach_weapon(parent: Node3D):
	var view = WeaponView.new()
	view.game = self
	parent.add_child(view)
	return view

func play_sound(id: String, volume = -16):
	if DisplayServer.get_name() == "headless":
		return
	var path = "res://assets/fps/sounds/" + id + ".ogg"
	if not ResourceLoader.exists(path):
		return
	if not sound_cache.has(id):
		sound_cache[id] = load(path)
	var sound = AudioStreamPlayer.new()
	sound.stream = sound_cache[id]
	sound.volume_db = volume
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func play_sfx(id: String, volume = -13):
	if DisplayServer.get_name() == "headless":
		return
	var path = "res://assets/sfx/" + id + ".wav"
	if not ResourceLoader.exists(path):
		return
	if not sfx_cache.has(id):
		sfx_cache[id] = load(path)
	var sound = AudioStreamPlayer.new()
	sound.stream = sfx_cache[id]
	sound.volume_db = volume
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func _exit_tree():
	if DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

func _panel(parent: Control, rect: Rect2, color = Color(0.042, 0.095, 0.118, 0.86), border = Color(0.45, 0.78, 0.65, 0.34)):
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _text(parent: Control, text: String, at: Vector2, size: Vector2, font_size = 20, color = CREAM):
	var label = Label.new()
	label.text = text
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Control, text: String, rect: Rect2, callback: Callable, accent = false):
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 16)
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("85d8b1") if accent else Color("22383e")
		if style_name == "hover":
			style.bg_color = style.bg_color.lightened(0.12)
		if style_name == "disabled":
			style.bg_color = Color("19272d")
		style.border_color = Color(0.52, 0.85, 0.72, 0.35 if style_name != "disabled" else 0.12)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(style_name, style)
	button.add_theme_color_override("font_color", INK if accent else CREAM)
	button.add_theme_color_override("font_hover_color", INK if accent else CREAM)
	button.add_theme_color_override("font_disabled_color", Color("6f8680"))
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

	# ZONE 1: Top-Left Compact Mission & Telemetry Card
	_panel(hud, Rect2(18, 16, 372, 166))
	_text(hud, "YANSHAN · 烟山战术终端", Vector2(32, 22), Vector2(246, 22), 14, MINT)
	fps_label = _text(hud, "", Vector2(298, 22), Vector2(78, 22), 13, Color("9ecfc0"))
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_label = _text(hud, "", Vector2(32, 46), Vector2(346, 24), 16, CREAM)
	mission_label = _text(hud, "", Vector2(32, 74), Vector2(346, 46), 13, GOLD)
	mission_label.clip_text = true
	guide_label = _text(hud, "", Vector2(32, 128), Vector2(346, 42), 12, Color("a9c7ba"))
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.clip_text = true

	# ZONE 2: Top-Center Sleek Word Prompt Card
	_panel(hud, Rect2(398, 16, 514, 102), Color(0.038, 0.095, 0.118, 0.88), Color(0.55, 0.90, 0.74, 0.55))
	question_label = _text(hud, "", Vector2(412, 20), Vector2(486, 48), 25, CREAM)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label = _text(hud, "", Vector2(412, 72), Vector2(486, 38), 13, MINT)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Threat Warning Banner (only shown when actively locked on)
	threat_banner = _panel(hud, Rect2(455, 124, 400, 30), Color(0.38, 0.09, 0.09, 0.90), Color("ff6b6b"))
	threat_label = _text(threat_banner, "⚠ 敌方火力锁定 · 冲刺跑跳或隐蔽掩体！", Vector2(10, 4), Vector2(370, 22), 14, Color("ffd6d6"))
	threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	threat_banner.hide()

	# ZONE 3: Top-Right Radar Minimap
	_panel(hud, Rect2(1092, 16, 170, 196))
	_text(hud, "N  ·  烟山战术雷达", Vector2(1108, 22), Vector2(142, 20), 13, MINT)
	var map = MapWidget.new()
	map.game = self
	map.position = Vector2(1094, 44)
	map.size = Vector2(166, 166)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(map)
	minimap = map

	# ZONE 4A: Bottom-Left Vitals (Shield/HP Bars) + Rarity Loot Slots
	combat_panel = _panel(hud, Rect2(18, 542, 344, 160))
	combat_label = _text(combat_panel, "", Vector2(14, 8), Vector2(316, 22), 14, CREAM)

	var shield_bg = ColorRect.new()
	shield_bg.position = Vector2(14, 33)
	shield_bg.size = Vector2(316, 8)
	shield_bg.color = Color(0.10, 0.20, 0.24, 0.9)
	shield_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_panel.add_child(shield_bg)
	shield_bar_fill = ColorRect.new()
	shield_bar_fill.position = Vector2(14, 33)
	shield_bar_fill.size = Vector2(316, 8)
	shield_bar_fill.color = Color("56d8ff")
	shield_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_panel.add_child(shield_bar_fill)

	var hp_bg = ColorRect.new()
	hp_bg.position = Vector2(14, 45)
	hp_bg.size = Vector2(316, 10)
	hp_bg.color = Color(0.16, 0.12, 0.12, 0.9)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_panel.add_child(hp_bg)
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.position = Vector2(14, 45)
	hp_bar_fill.size = Vector2(316, 10)
	hp_bar_fill.color = Color("6ae3a8")
	hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_panel.add_child(hp_bar_fill)

	bag_label = _text(combat_panel, "", Vector2(14, 62), Vector2(316, 22), 14, GOLD)
	bag_slots_box = HFlowContainer.new()
	bag_slots_box.position = Vector2(14, 86)
	bag_slots_box.size = Vector2(316, 66)
	bag_slots_box.add_theme_constant_override("h_separation", 5)
	bag_slots_box.add_theme_constant_override("v_separation", 4)
	bag_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_panel.add_child(bag_slots_box)

	# ZONE 4B: Bottom-Right Weapon, Reserve Ammo & Tactical Consumables Card
	_panel(hud, Rect2(954, 566, 308, 136))
	ammo_label = _text(hud, "", Vector2(968, 574), Vector2(282, 122), 14, CREAM)

	# Center Prompts & Tactical Reticles
	feedback_panel = _panel(hud, Rect2(370, 520, 540, 64), Color(0.04, 0.11, 0.12, 0.92), Color(0.55, 0.88, 0.72, 0.5))
	feedback_panel.hide()
	feedback_label = _text(hud, "", Vector2(384, 526), Vector2(512, 52), 19, MINT)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	interaction_panel = _panel(hud, Rect2(384, 594, 524, 38), Color(0.04, 0.09, 0.11, 0.82))
	interaction_label = _text(hud, "", Vector2(394, 596), Vector2(504, 34), 16, GOLD)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	crosshair_label = _text(hud, "+", Vector2(622, 338), Vector2(36, 42), 26, Color(0.92, 0.98, 0.94, 0.85))
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	hitmarker_label = _text(hud, "×", Vector2(616, 332), Vector2(48, 48), 34, MINT)
	hitmarker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hitmarker_label.hide()

	_text(hud, "[WASD]移动  [1/2/滚轮]切枪切刀  [V]快刀  [R]换弹  [H]医疗  [G]烟雾EMP  [T]能量  [E]交互", Vector2(368, 682), Vector2(578, 22), 11, Color("a9c2b5")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	screen_flash = ColorRect.new()
	screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_flash.color = Color(0.4, 1, 0.7, 0)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen_flash)

	# CAMP / PAUSE MENU
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.03, 0.065, 0.08, 0.62)
	menu.add_child(veil)
	_panel(menu, Rect2(86, 56, 1108, 608), Color(0.038, 0.082, 0.102, 0.97), Color(0.46, 0.80, 0.66, 0.42))

	menu_title = _text(menu, "烟山基地", Vector2(120, 80), Vector2(470, 60), 42, MINT)
	_text(menu, "英语战术搜撤行动  ·  VERSION " + VERSION, Vector2(122, 142), Vector2(460, 28), 17, GOLD)
	_button(menu, "退出", Rect2(1098, 84, 68, 36), func(): get_tree().quit())
	abandon_button = _button(menu, "放弃本局", Rect2(956, 84, 130, 36), func(): _end_run(false))
	abandon_button.hide()

	menu_summary = _text(menu, "", Vector2(122, 186), Vector2(460, 126), 16)
	menu_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review_button = _button(menu, "查看本局错词本（含页码）", Rect2(122, 316, 456, 30), _show_review)
	review_button.hide()

	unit_picker = OptionButton.new()
	unit_picker.position = Vector2(122, 358)
	unit_picker.size = Vector2(290, 40)
	unit_picker.add_item("全部单元 · 175 条词汇")
	for i in range(1, 9):
		unit_picker.add_item("Unit " + str(i))
	menu.add_child(unit_picker)

	include_extra = CheckBox.new()
	include_extra.text = "含拓展词与专名"
	include_extra.position = Vector2(422, 360)
	include_extra.button_pressed = true
	include_extra.add_theme_font_size_override("font_size", 15)
	menu.add_child(include_extra)

	start_button = _button(menu, "部署战术行动  →", Rect2(122, 418, 274, 54), func(): start_action(rules.combat_mode if rules.phase in ["active", "extracting"] else true), true)
	practice_button = _button(menu, "自由靶场练习", Rect2(408, 418, 170, 54), func(): start_action(false))

	_text(menu, "【v0.6.1 江南山林水系与生灵精修简报】\n• 下凹鹅卵石河床与水岸芦苇：清澈山溪穿过木桩直汇诚庄垂柳稻田\n• 江南乡土林木焕新：香樟、垂柳、乌桕枫香与有节毛竹林重塑山村质感\n• 八类鲜活山野生灵：灌木惊起小野猪、山坡赤狐、枝头白鹭、锦鲤山蟹与清溪河虾", Vector2(122, 490), Vector2(465, 145), 14, Color("b4ccbe"))

	# Right Column: Progress, Warehouse & 3-Column 15-Item Gunsmith Armory
	menu_finance = _text(menu, "", Vector2(616, 134), Vector2(548, 72), 17, GOLD)
	_text(menu, "枪 匠 改 装 台 与 战 备 仓 库", Vector2(616, 214), Vector2(380, 28), 20, MINT)
	sell_button = _button(menu, "出售仓库物资", Rect2(616, 248, 548, 38), _sell, true)

	for idx in Rules.GUNSMITH_ORDER.size():
		var id: String = Rules.GUNSMITH_ORDER[idx]
		var col = idx % 3
		var row = int(idx / 3)
		var rect = Rect2(616 + col * 186, 294 + row * 50, 176, 42)
		shop_buttons[id] = _button(menu, "", rect, _buy.bind(id))
		shop_buttons[id].add_theme_font_size_override("font_size", 13)

	menu_status = _text(menu, "五上词库 175 条 · 离线标准英文读音 · 点击已购配件可换装/卸下", Vector2(616, 594), Vector2(548, 48), 14, Color("a9c4b6"))
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Review Overlay
	review_overlay = Control.new()
	review_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(review_overlay)
	var shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.04, 0.04, 0.92)
	review_overlay.add_child(shade)
	_panel(review_overlay, Rect2(190, 80, 900, 560))
	_text(review_overlay, "本局错词复盘 · 点击单词可听标准发音", Vector2(220, 103), Vector2(680, 44), 27, MINT)
	_button(review_overlay, "返回营地", Rect2(942, 105, 112, 40), func(): review_overlay.hide())
	review_text = RichTextLabel.new()
	review_text.position = Vector2(220, 170)
	review_text.size = Vector2(830, 430)
	review_text.add_theme_font_size_override("normal_font_size", 22)
	review_text.bbcode_enabled = true
	review_text.meta_clicked.connect(func(meta): speak_english(str(meta)))
	review_overlay.add_child(review_text)
	review_overlay.hide()
	hud.hide()

func _show_review():
	var lines = []
	for word in wrong_words:
		lines.append("[url=%s][color=#8de8c0]🔊 %s[/color][/url]  —  %s\n[color=#a9c4b6]Unit %d · 课本第 %d 页[/color]\n" % [word.english, word.english, word.chinese, word.unit, word.textbook_page])
	review_text.text = "\n".join(lines) if not lines.is_empty() else "本局还没有错词，表现非常棒！"
	review_text.scroll_to_line(0)
	review_overlay.show()

func _warehouse_total_value() -> int:
	var sum = 0
	for item in rules.profile.warehouse:
		sum += int(item.get("value", 0))
	return sum

func _refresh_menu(result = ""):
	var mastered = rules.mastered_count()
	var collected = rules.profile.collection.size()
	menu_finance.text = "Lv.%d（%d/120 XP） · 货币 %d 币 · 家长奖励券 %d 张\n词表熟练掌握：%d / %d 词   |   史诗/大金藏品图鉴：%d / 7 件" % [
		rules.level(), rules.profile.xp % 120, rules.profile.coins, rules.profile.points,
		mastered, words.size(), collected
	]
	menu_title.text = result if result != "" else "烟山基地"
	if result == "":
		menu_summary.text = "山脚营地出发：有限备弹+匕首近战，突破林间/山道前哨！\n常规箱单词解锁，高阶空投箱词组+整句破译。\n满 260 分 + 攻克至少 2 处前哨 + 击败 B 区首领夺密钥即可撤离！"

	var wh_count = rules.profile.warehouse.size()
	var wh_val = _warehouse_total_value()
	sell_button.text = "一键出售仓库物资（%d 件 · 合计 %d 币）" % [wh_count, wh_val]
	sell_button.disabled = wh_count == 0 or rules.phase in ["active", "extracting"]

	var eq_optic: String = rules.active_optic()
	var eq_muzzle: String = rules.active_muzzle()
	var eq_grip: String = rules.active_grip()
	var in_run: bool = rules.phase in ["active", "extracting"]

	for id in shop_buttons:
		var item = Rules.ITEMS[id]
		var slot = str(item.get("slot", ""))
		var is_mod: bool = slot in ["optic", "muzzle", "grip"]
		var owned = id in rules.profile.owned
		var equipped_now: bool = is_mod and ((slot == "optic" and eq_optic == id) or (slot == "muzzle" and eq_muzzle == id) or (slot == "grip" and eq_grip == id))
		var prereq_missing = (id == "magazine2" and not ("magazine" in rules.profile.owned))
		var suffix = ""
		if id == "reward_point":
			suffix = "%d币兑" % item.cost
		elif equipped_now:
			suffix = "已装配"
		elif owned and is_mod:
			suffix = "点换装"
		elif owned:
			suffix = "已装备"
		elif prereq_missing:
			suffix = "先扩容I"
		else:
			suffix = "%d币" % item.cost
		shop_buttons[id].text = "%s\n%s" % [item.title.split(" · ")[0], suffix]
		shop_buttons[id].tooltip_text = item.title
		var can_click: bool = false
		if id == "reward_point":
			can_click = not in_run and rules.profile.coins >= item.cost
		elif owned and is_mod:
			can_click = not in_run
		else:
			can_click = not in_run and not owned and not prereq_missing and rules.profile.coins >= item.cost
		shop_buttons[id].disabled = not can_click

	start_button.text = "继续行动  →" if in_run else "部署战术行动  →"
	practice_button.visible = not in_run
	abandon_button.visible = in_run
	unit_picker.disabled = in_run
	include_extra.disabled = unit_picker.disabled

func _sell():
	var value = rules.sell_all()
	if value > 0:
		play_sfx("cipher_unlock", -12)
	_save()
	_refresh_menu()
	menu_status.text = "物资已全部结算出售，获得 %d 枚游戏货币！" % value

func _buy(id: String):
	var item = Rules.ITEMS.get(id, {})
	var slot = str(item.get("slot", ""))
	if id != "reward_point" and id in rules.profile.owned and slot in ["optic", "muzzle", "grip"]:
		if rules.equip_attachment(slot, id):
			play_sfx("weapon_change", -12)
			_save()
			_refresh_menu()
			var now_eq: bool = rules.profile["equipped"].get(slot, "") == id
			menu_status.text = ("已装配配件：" if now_eq else "已卸下配件：") + item.title
		return
	if rules.purchase(id):
		play_sfx("loot_epic" if id == "reward_point" else "cipher_unlock", -11)
		_save()
		_refresh_menu()
		menu_status.text = "已解锁装备：" + item.title
		if id == "reward_point":
			menu_status.text += "（线下奖励可与爸爸妈妈核对兑现！）"

func _build_weighted_queue() -> Array:
	var deck = []
	for w in pool:
		deck.append(w)
		if rules.word_priority(w.id) >= 2.8:
			deck.append(w)
	deck.shuffle()
	return deck

func start_action(as_combat = false):
	if rules.phase not in ["active", "extracting"]:
		review_button.hide()
		review_overlay.hide()
		tutorial_moved = false
		_leave_station()
		rules.start_run(as_combat)
		exploration.reset()
		if is_instance_valid(wildlife):
			wildlife.reset()
		if is_instance_valid(cipher_terminal):
			cipher_terminal.reset()
		player.medkits = rules.starter_medkits()
		player.grenades = rules.starter_grenades()
		player.stims = rules.starter_stims()
		player.stim_left = 0.0
		player.weapon_slot = 0
		time_left = 480.0
		next_question_left = 0.0
		wrong_words = []
		bag_signature = "__dirty__"
		pool = []
		for word in words:
			if unit_picker.selected > 0 and word.unit != unit_picker.selected:
				continue
			if not include_extra.button_pressed and (not word.core or word.proper_name):
				continue
			pool.append(word)
		if pool.size() < 4:
			pool = words.duplicate()
		question_queue = _build_weighted_queue()
		player.position = Layout.on_ground(Layout.SPAWN) + Vector3.UP * 0.15
		player.yaw = 0.0
		player.pitch = 0.0
		player.ammo = rules.magazine()
		player.reserve_ammo = rules.starter_reserve_ammo()
		player.reload_left = 0.0
		player.cooldown = 0.0
		player.knife_cooldown = 0.0
		player.recoil = 0.0
		for node in pickup_nodes:
			Props.set_enabled(node, true)
		for node in crate_nodes:
			var tier = int(node.get_meta("tier"))
			node.get_child(node.get_child_count() - 1).modulate = _crate_accent(tier)
			if node.has_meta("lid_node") and is_instance_valid(node.get_meta("lid_node")):
				node.get_meta("lid_node").rotation.x = 0.0
		for child in player.weapon_root.get_children():
			child.queue_free()
		player.weapon_view = attach_weapon(player.weapon_root)
		if as_combat:
			combat.begin()
		else:
			combat.stop()
			_next_question()
	paused = false
	get_viewport().gui_release_focus()
	player.clear_movement_input()
	player.active = true
	player.camera.fov = 75
	menu.hide()
	hud.show()
	combat_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _pick_smart_distractors(target: Dictionary) -> Array:
	var target_en: String = target.english.strip_edges()
	var target_is_phrase: bool = target.get("kind", "word") == "phrase" or (" " in target_en)
	var target_proper: bool = bool(target.get("proper_name", false))
	var target_first: String = target_en.substr(0, 1).to_lower()
	var target_len: int = target_en.length()
	var target_unit: int = int(target.get("unit", 0))

	var scored = []
	var source = pool if pool.size() >= 4 else words
	for candidate in source:
		if candidate.english.to_lower() == target_en.to_lower() or candidate.chinese == target.chinese:
			continue
		var cand_en: String = candidate.english.strip_edges()
		var cand_is_phrase: bool = candidate.get("kind", "word") == "phrase" or (" " in cand_en)
		var s := distractor_rng.randf() * 1.15
		if cand_is_phrase == target_is_phrase:
			s += 4.2
		if bool(candidate.get("proper_name", false)) == target_proper:
			s += 3.0
		if int(candidate.get("unit", -1)) == target_unit:
			s += 1.4
		if cand_en.substr(0, 1).to_lower() == target_first:
			s += 1.2
		s += maxf(0.0, 2.0 - absf(float(cand_en.length() - target_len)) * 0.25)
		scored.append({"word": candidate, "score": s})

	scored.sort_custom(func(a, b): return a.score > b.score)
	var picked = [target]
	for entry in scored:
		var cand = entry.word
		var dup = false
		for c in picked:
			if cand.english.to_lower() == c.english.to_lower() or cand.chinese == c.chinese:
				dup = true
				break
		if not dup:
			picked.append(cand)
		if picked.size() == 4:
			break
	return picked

func _next_question():
	if question_queue.is_empty():
		question_queue = _build_weighted_queue()
	question = question_queue.pop_back()
	if rules.answered > 0 and rules.answered % 6 == 0 and wrong_words.size() > 0:
		question = wrong_words.pick_random()
	choices = _pick_smart_distractors(question)
	choices.shuffle()
	answer_index = 0
	for i in choices.size():
		if choices[i].id == question.id:
			answer_index = i
	listening_mode = (tts_voice_id != "" and rules.answered >= 4 and rules.answered % 5 == 0)
	rules.open_question()
	_sync_question()
	if listening_mode and not paused:
		speak_english(question.english)

func _sync_question():
	if combat.in_field() and combat.zone >= 0:
		combat.show_question()
		return
	if active_station < 0:
		if combat.in_field():
			combat.show_question()
		else:
			question_label.text = "靠近绿色终端，按 [E] 启动识词靶场"
			unit_label.text = "A 山脚营地 → 林间前哨 → B 竹林撤离点  |  自由探索与识词"
		return
	for i in choices.size():
		_fit_word(targets[i], choices[i].english)
		target_materials[i].albedo_color = Color("182e30")
	if listening_mode and rules.question_open:
		question_label.text = "🔊 听音辨词挑战 · 按 [Q] 重播读音"
	else:
		question_label.text = question.chinese
	unit_label.text = "%s · Unit %d · 第 %d 页  |  [Q] 听标准发音" % [stations[active_station].title, question.unit, question.textbook_page]
	if not rules.question_open:
		target_materials[answer_index].albedo_color = Color("3b8a62")
		unit_label.text = "已结算 · 下一题即将出现"

func _fit_word(label: Label3D, word: String, height_limit = 138):
	label.text = word.replace("’", "'")
	label.font_size = 64
	var parts = label.text.split(" ")
	while label.font_size > 28:
		var fits = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.width, label.font_size).y <= height_limit
		for part in parts:
			if font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x > label.width - 55:
				fits = false
				break
		if fits:
			break
		label.font_size -= 2

func _activate_station(index: int):
	if combat.in_field() and (combat.zone >= 0 or index != 0):
		return
	if index < 0 or index >= stations.size() or player.position.distance_to(_interaction_position(stations[index])) > 3.2 or not _can_interact(stations[index]):
		return
	if active_station >= 0:
		stations[active_station].clear()
	active_station = index
	targets = stations[index].targets
	target_materials = stations[index].materials
	_sync_question()
	_notice(stations[index].title + " · 看中文射击对应英文靶牌（按 Q 可听发音）", MINT)

func _leave_station():
	if active_station >= 0:
		stations[active_station].clear()
	active_station = -1
	targets = []
	target_materials = []
	_sync_question()

func _interaction_position(node: Node3D) -> Vector3:
	return node.global_position + (Vector3(2, 0, 2) if node.has_meta("station_id") else Vector3.ZERO)

func _can_interact(node: Node3D) -> bool:
	var endpoint = _interaction_position(node) + Vector3(0, 0.6, 0)
	var query = PhysicsRayQueryParameters3D.create(player.camera.global_position, endpoint, 3, [player.get_rid()])
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == node or node.is_ancestor_of(hit.collider)

func show_hitmarker(is_crit: bool = false):
	hitmarker_left = 0.22
	hitmarker_label.text = "✦" if is_crit else "×"
	hitmarker_label.add_theme_color_override("font_color", GOLD if is_crit else MINT)
	hitmarker_label.show()

func melee_strike(camera: Camera3D):
	if rules.phase != "active" or paused:
		return
	var shooting_field = combat.in_field() and (combat.zone >= 0 or active_station < 0)
	if shooting_field:
		combat.melee_strike(camera)
		if is_instance_valid(wildlife):
			wildlife.melee_strike(camera)
		return
	if active_station >= 0 and player.position.distance_to(stations[active_station].position) <= 15:
		var from = camera.global_position
		var to = from - camera.global_basis.z * 4.2
		var query = PhysicsRayQueryParameters3D.create(from, to, 3, [player.get_rid()])
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		if result and result.collider.get_meta("station_id", "") == stations[active_station].station_id and result.collider.has_meta("answer_index"):
			play_sfx("knife_hit", -10)
			resolve_answer(int(result.collider.get_meta("answer_index")))
			return
	if is_instance_valid(wildlife):
		wildlife.melee_strike(camera)

func deploy_smoke_emp(camera: Camera3D):
	if rules.phase != "active" or paused:
		return
	var from := camera.global_position
	var dir := (-camera.global_basis.z).normalized()
	var target := from + dir * 6.5
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 14.0, 1, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.position
	if combat.in_field():
		combat.deploy_smoke_emp(target)
	else:
		play_sfx("smoke_emp", -10)
		_notice("已投掷训练烟雾/EMP 手雷（实战中可瘫痪敌方并遮蔽狙击激光）", Color("7ceeff"))

func fire(camera: Camera3D):
	if rules.phase != "active" or paused:
		return
	rules.shots += 1
	var shooting_field = combat.in_field() and (combat.zone >= 0 or active_station < 0)
	var from = camera.global_position
	var to = from - camera.global_basis.z * 85
	var query = PhysicsRayQueryParameters3D.create(from, to, 7 if shooting_field else 3, [player.get_rid()])
	query.collide_with_areas = shooting_field
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if is_instance_valid(wildlife):
		wildlife.on_gunshot_near(player.position, rules.active_muzzle() == "suppressor")
		var wq = PhysicsRayQueryParameters3D.create(from, to, 1 | Wildlife.HIT_LAYER, [player.get_rid()])
		wq.collide_with_areas = true
		var whit = get_world_3d().direct_space_state.intersect_ray(wq)
		if whit and whit.collider is Area3D:
			if result.is_empty() or from.distance_to(whit.position) <= from.distance_to(result.position) + 0.05:
				if wildlife.hit_bullet(whit.collider):
					return
	if not shooting_field and (active_station < 0 or player.position.distance_to(stations[active_station].position) > 15):
		return
	if shooting_field:
		if result:
			combat.hit_bullet(result.collider, rules.active_muzzle(), result.position)
		return
	if result and active_station >= 0 and result.collider.get_meta("station_id", "") == stations[active_station].station_id and result.collider.has_meta("answer_index"):
		resolve_answer(int(result.collider.get_meta("answer_index")))

func resolve_answer(index: int, mobile = false):
	if (not mobile and active_station < 0) or index < 0 or index >= choices.size():
		return
	var correct = index == answer_index
	var prev_score = rules.score
	if not rules.answer(correct, str(question.get("id", ""))):
		return
	# Block Camp Station 0 farming during real field combat runs!
	var camp_warmup_in_combat: bool = (not mobile and combat.in_field())
	if camp_warmup_in_combat:
		rules.score = prev_score
	var gained = rules.score - prev_score

	hitmarker_left = 0.20
	hitmarker_label.text = "×" if correct else "✕"
	hitmarker_label.add_theme_color_override("font_color", MINT if correct else Color("ff6b6b"))
	hitmarker_label.show()
	play_sfx("hit_correct" if correct else "hit_wrong", -11)
	speak_english(question.english)

	if mobile:
		combat.record_field(correct)
		combat.hit_feedback(index, correct)
	elif correct:
		target_materials[index].albedo_color = Color("3b8a62")
	else:
		target_materials[index].albedo_color = Color("8d4b47")
		target_materials[answer_index].albedo_color = Color("3b8a62")

	if camp_warmup_in_combat:
		_notice("营地热身：%s（%s）· 实战撤离积分与清哨需击杀前哨敌军" % [question.english, question.chinese], GOLD)
	elif correct:
		var streak_tag = (" · 🔥%d连击!" % rules.streak) if rules.streak >= 3 else ""
		if not (mobile and combat.zone >= 0 and combat.waves_done.get(combat.zone, 0) == combat.waves_target.get(combat.zone, -1)):
			_notice("命中正确！ +%d 分%s · %s（%s）" % [gained, streak_tag, question.english, question.chinese], MINT)
		if rules.correct % 3 == 0:
			var chip_rarity = 3 if rules.streak >= 4 else 2
			rules.add_loot("战术知识芯片", 46 + maxi(0, rules.level() - 1) * 4, chip_rarity)
	else:
		var warning = "\n⚠ 敌方狂暴强化 7 秒 · 当前伤害 ×%.2f" % combat.damage_multiplier() if mobile else ""
		_notice("正确答案：%s  —  %s%s" % [question.english, question.chinese, warning], Color("f5b995"))
		if question not in wrong_words:
			wrong_words.append(question)

	screen_flash.color = Color(0.3, 1, 0.65, 0.08) if correct else Color(1, 0.35, 0.2, 0.09)
	next_question_left = 1.45 if correct else 2.45
	unit_label.text = "已结算 · 下一题即将出现"

func _notice(text: String, color = GOLD):
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_left = 3.4

func _refresh_bag_pills():
	var sig_parts = [str(rules.capacity())]
	for item in rules.bag:
		sig_parts.append("%s:%d:%d" % [item.title, int(item.value), int(item.get("rarity", 1))])
	var sig = "|".join(sig_parts)
	if sig == bag_signature:
		return
	bag_signature = sig
	for child in bag_slots_box.get_children():
		child.queue_free()
	if rules.bag.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "沿路搜刮物资与密码箱（支持拼写开大金）"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color("89a89b"))
		bag_slots_box.add_child(empty_lbl)
		return
	for item in rules.bag:
		var r = clampi(int(item.get("rarity", 1)), 1, 5)
		var col: Color = Rules.RARITY_COLORS[r]
		var pill = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(col.r * 0.17, col.g * 0.17, col.b * 0.19, 0.92)
		st.border_color = col
		st.set_border_width_all(1)
		st.set_corner_radius_all(4)
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		pill.add_theme_stylebox_override("panel", st)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl = Label.new()
		lbl.text = item.title
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", col)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(lbl)
		bag_slots_box.add_child(pill)

func _process(delta):
	render_age += delta
	if not is_instance_valid(player) or not is_instance_valid(stat_label):
		return
	if paused:
		return
	exploration.update(delta)
	if is_instance_valid(wildlife):
		wildlife.update(delta)
	combat.update(delta)
	if active_station >= 0 and player.position.distance_to(stations[active_station].position) > 15:
		_leave_station()
	if rules.phase in ["active", "extracting"]:
		time_left -= delta
		if time_left <= 0:
			_end_run(false)
			return
	if rules.phase == "active" and next_question_left > 0:
		next_question_left -= delta
		if next_question_left <= 0:
			_next_question()
	if rules.phase == "extracting":
		if player.position.distance_to(exit_position) > 4.0:
			rules.phase = "active"
			_next_question()
			_notice("已离开撤离信标范围，读条中断！")
		else:
			extract_pulse_clock -= delta
			if extract_pulse_clock <= 0:
				extract_pulse_clock = 1.0
				play_sfx("extract_pulse", -14)
			extraction_left -= delta
			if extraction_left <= 0:
				_end_run(true)
				return

	feedback_left = maxf(0, feedback_left - delta)
	feedback_label.visible = feedback_left > 0
	feedback_panel.visible = feedback_label.visible
	screen_flash.color.a = maxf(0, screen_flash.color.a - delta * 0.22)

	if hitmarker_left > 0:
		hitmarker_left = maxf(0, hitmarker_left - delta)
		if hitmarker_left <= 0:
			hitmarker_label.hide()

	crosshair_label.text = "◆" if player.weapon_slot == 1 else "+"
	crosshair_label.visible = not (player.aiming and player.weapon_slot == 0)

	var streak_str = ("  🔥×%d" % rules.streak) if rules.streak >= 3 else ""
	stat_label.text = "积分 %03d/%d  |  正确率 %d%%  |  %02d:%02d%s" % [
		rules.score, Rules.EXTRACTION_SCORE, roundi(rules.accuracy() * 100), int(time_left) / 60, int(time_left) % 60, streak_str
	]
	fps_label.text = "%d FPS" % Engine.get_frames_per_second() if render_age > 1.5 else "预热中"

	var outpost_part = ("前哨 %d/2 · 密钥 %d/1" % [rules.outposts_cleared, 1 if rules.boss_defeated else 0]) if rules.combat_mode else "自由靶场"
	var extract_part = "信标已就绪" if rules.can_extract() else _extraction_blocker_short()
	var eco_part = wildlife.status_badge() if is_instance_valid(wildlife) else "生灵 0/8 · 奇植 0/8"
	mission_label.text = "%s  ·  箱 %d/%d  ·  撤离：%s\n%s  ·  %s" % [
		outpost_part, rules.crates.size(), crate_nodes.size(), extract_part, exploration.status_text(), eco_part
	]
	_update_guide()
	_update_combat_hud()

	bag_label.text = "随身背包 %d / %d 格  ·  估值 %d 币" % [rules.bag.size(), rules.capacity(), rules.bag_value()]
	_refresh_bag_pills()

	var mods := []
	if rules.active_optic() == "scope_2x":
		mods.append("2倍棱镜")
	elif rules.active_optic() == "red_dot":
		mods.append("全息瞄具")
	else:
		mods.append("反射机械")
	if rules.active_muzzle() == "suppressor":
		mods.append("消音器")
	elif rules.active_muzzle() == "compensator":
		mods.append("制退器")
	if rules.active_grip() == "angled_grip":
		mods.append("直角握把")
	var optic_tag = " · ".join(mods)
	var active_tag = "[2] 战术匕首 (高移速+近战必回弹)" if player.weapon_slot == 1 else "[1] YS-04 卡宾枪  |  [2] 匕首"
	var reserve_str = "∞" if player.has_infinite_ammo() else str(maxi(0, player.reserve_ammo))
	var ammo_line = "近战状态  ·  [左键/V] 斩击（背后处决/回弹）" if player.weapon_slot == 1 else (
		"换弹装填中…" if player.reload_left > 0 else "弹药 %02d / 备弹 %s   [R]换弹" % [player.ammo, reserve_str]
	)
	var stim_suffix = ("  ⚡%.0fs" % player.stim_left) if player.stim_left > 0 else ""
	ammo_label.text = "%s\n%s\n%s\n[H]医疗×%d  [G]烟雾×%d  [T]能量×%d%s" % [
		active_tag, ammo_line, optic_tag, player.medkits, player.grenades, player.stims, stim_suffix
	]
	_update_interaction()

func _extraction_blocker_short() -> String:
	if rules.score < Rules.EXTRACTION_SCORE:
		return "差%d分" % (Rules.EXTRACTION_SCORE - rules.score)
	if rules.combat_mode and not rules.boss_defeated:
		return "需败B区首领"
	if rules.combat_mode and rules.outposts_cleared < 2:
		return "需攻克%d/2哨" % rules.outposts_cleared
	return "待就绪"

func _crate_progress(tier: int) -> String:
	var req = rules.crate_requirements(tier)
	var pct = roundi(req.accuracy * 100)
	if rules.crate_ready(tier):
		return "可拼写破译"
	if rules.answered < req.minimum:
		return "需答 %d 题/%d%%" % [req.minimum, pct]
	return "正确率需 %d%%" % pct

func _update_guide():
	if player.position.distance_to(Vector3(0, 0, 4.5)) > 1.2:
		tutorial_moved = true
	if rules.can_extract():
		guide_label.text = "★ 撤离条件已全达标！前往B点绿色信标按 [E] 坚守5秒"
	elif combat.in_field() and combat.zone == 2 and is_instance_valid(combat.boss_unit) and not combat.boss_unit.defeated:
		guide_label.text = "首领战：破词盾露核心，[G]烟雾可致盲躲红圈"
	elif combat.in_field() and combat.zone >= 0:
		guide_label.text = "射对词盾破防 · 无弹按 [2/V] 匕首近战回弹"
	elif combat.in_field():
		guide_label.text = "突破前哨并击败 B 区首领（营地靶场不计分）"
	elif not tutorial_moved and active_station < 0:
		guide_label.text = "按 [E] 开启身旁营地终端，或沿山路探索"
	else:
		guide_label.text = "看中文射英文 · 答对+%d分 · 3连击额外+%d分" % [Rules.BASE_ANSWER_SCORE, Rules.STREAK_BONUS_SCORE]

func _update_combat_hud():
	if combat.in_field():
		var max_sh = maxf(1.0, float(rules.max_shield()))
		shield_bar_fill.size.x = 316.0 * clampf(float(combat.shield) / max_sh, 0.0, 1.0)
		hp_bar_fill.size.x = 316.0 * clampf(float(combat.health) / float(Combat.MAX_HEALTH), 0.0, 1.0)
		hp_bar_fill.color = Color("6ae3a8") if combat.health > 55 else (Color("f4ca64") if combat.health > 28 else Color("ff5c66"))
		var threats = combat.active_threat_count()
		threat_banner.visible = threats > 0
		var state_tag = "烟雾隐蔽!" if combat.player_in_smoke() else ("闪避成功!" if combat.miss_left > 0 else ("狂暴 ×%.2f" % combat.damage_multiplier() if combat.rage_left > 0 else ("受瞄准 ×%d" % threats if threats > 0 else "护盾自动充能")))
		combat_label.text = "生命 %d/100  ·  护盾 %d/%d  ·  %s" % [combat.health, roundi(combat.shield), rules.max_shield(), state_tag]
	else:
		threat_banner.hide()
		shield_bar_fill.size.x = 316.0
		hp_bar_fill.size.x = 316.0
		hp_bar_fill.color = Color("6ae3a8")
		combat_label.text = "自由靶场模式  ·  无限备弹 · 护盾生命满值"

func _extraction_blocker_text() -> String:
	var missing := []
	if rules.score < Rules.EXTRACTION_SCORE:
		missing.append("还差 %d 积分（%d/%d）" % [Rules.EXTRACTION_SCORE - rules.score, rules.score, Rules.EXTRACTION_SCORE])
	if rules.combat_mode and rules.outposts_cleared < 2:
		missing.append("需攻克至少 2 处前哨（%d/2）" % rules.outposts_cleared)
	if rules.combat_mode and not rules.boss_defeated:
		missing.append("需击败 B 区首领夺取密钥")
	return " · ".join(missing)

func _update_interaction():
	closest_interaction = null
	var nearest = 3.2
	var eco_nodes: Array = wildlife.flora_nodes if is_instance_valid(wildlife) else []
	for node in pickup_nodes + crate_nodes + stations + exploration.nodes + eco_nodes:
		if combat.in_field() and node.has_meta("station_id") and (combat.zone >= 0 or node != stations[0]):
			continue
		if not node.visible:
			continue
		var distance = player.position.distance_to(_interaction_position(node))
		if distance < nearest and _can_interact(node):
			closest_interaction = node
			nearest = distance

	if rules.phase == "extracting":
		interaction_label.text = "★ 撤离信标传输中 %.1f 秒 · 请留在光圈内！" % maxf(0, extraction_left)
	elif player.position.distance_to(exit_position) < 3.6:
		interaction_label.text = "[E] 启动战术撤离（坚守 5 秒）" if rules.can_extract() else ("撤离锁定 · " + _extraction_blocker_text())
	elif closest_interaction:
		if closest_interaction.has_meta("tactical_item"):
			var kind = str(closest_interaction.get_meta("tactical_item"))
			var title = str(closest_interaction.get_meta("title", "战术补给"))
			if kind == "ammo_crate":
				interaction_label.text = "[E] 搜刮 %s（+%d 备弹）" % [title, rules.magazine()]
			elif kind == "smoke_emp":
				interaction_label.text = "[E] 拾取 %s（+1）" % title
			else:
				interaction_label.text = "[E] 拾取 %s（+1）" % title
		elif closest_interaction.has_meta("flora_id"):
			var fid := str(closest_interaction.get_meta("flora_id"))
			var f_verb := "温习植物" if (is_instance_valid(wildlife) and wildlife.collected_flora.has(fid)) else "辨识奇植"
			interaction_label.text = "[E] %s · %s (%s)" % [f_verb, closest_interaction.get_meta("en"), closest_interaction.get_meta("zh")]
		elif closest_interaction.has_meta("explore_id"):
			interaction_label.text = "[E] " + closest_interaction.get_meta("prompt")
		elif closest_interaction.has_meta("station_id"):
			interaction_label.text = "[E] 开启识词靶场 · " + closest_interaction.title
		elif closest_interaction.has_meta("tier"):
			var title = closest_interaction.get_meta("title")
			var tier = int(closest_interaction.get_meta("tier"))
			if closest_interaction.has_meta("unclaimed_loot"):
				interaction_label.text = "[E] 领取/替换战利品 · " + title
			elif title in rules.crates:
				interaction_label.text = title + " · 已破译搜刮"
			elif rules.crate_ready(tier):
				var mode_hint = "三重破译(词+词组+句)" if tier >= 3 else ("词组+短句破译" if tier == 2 else "单词+词组破译")
				interaction_label.text = "[E] %s · %s" % [mode_hint, title]
			else:
				interaction_label.text = title + " · " + _crate_progress(tier)
		else:
			var sup_title = str(closest_interaction.get_meta("title", "常规物资箱"))
			if closest_interaction.has_meta("unclaimed_loot"):
				interaction_label.text = "[E] 领取待替换物资 · " + sup_title
			else:
				interaction_label.text = "[E] 单词拼写开箱 · " + sup_title
	else:
		interaction_label.text = "B点撤离信标 %d m  ·  %s" % [
			roundi(player.position.distance_to(exit_position)),
			"已解锁可撤离" if rules.can_extract() else _extraction_blocker_short()
		]

func interact():
	if rules.phase != "active" or paused:
		return
	if player.position.distance_to(exit_position) < 3.6:
		if rules.request_extraction():
			extraction_left = Rules.EXTRACTION_SECONDS
			extract_pulse_clock = 0.05
			play_sfx("extract_pulse", -12)
			_notice("信标已激活！坚守 %.0f 秒完成撤离入库！" % Rules.EXTRACTION_SECONDS, MINT)
		else:
			play_sfx("hit_wrong", -14)
			_notice("无法撤离：" + _extraction_blocker_text())
		return
	_update_interaction()
	if not is_instance_valid(closest_interaction):
		return
	if closest_interaction.has_meta("tactical_item"):
		var kind = str(closest_interaction.get_meta("tactical_item"))
		var title = str(closest_interaction.get_meta("title", "战术补给"))
		if kind == "ammo_crate":
			if player.has_infinite_ammo():
				_notice("当前自由靶场备弹无限 · " + title, MINT)
			else:
				player.add_reserve_ammo(rules.magazine())
				_notice("已补给 %s · 备弹 +%d（当前 %d）" % [title, rules.magazine(), player.reserve_ammo], GOLD)
		elif kind == "smoke_emp":
			player.grenades += 1
			_notice("拾取 %s · 按 [G] 投掷（当前 %d）" % [title, player.grenades], Color("7ceeff"))
		else:
			player.stims += 1
			_notice("拾取 %s · 按 [T] 使用（当前 %d）" % [title, player.stims], MINT)
		play_sfx("ammo_pickup", -10)
		Props.set_enabled(closest_interaction, false)
		return
	if closest_interaction.has_meta("flora_id"):
		if is_instance_valid(wildlife):
			wildlife.interact_flora(closest_interaction)
		return
	if closest_interaction.has_meta("explore_id"):
		exploration.open(closest_interaction)
		return
	if closest_interaction.has_meta("station_id"):
		_activate_station(stations.find(closest_interaction))
		return
	if closest_interaction.has_meta("tier"):
		cipher_terminal.open_for_crate(closest_interaction)
		return
	cipher_terminal.open_for_supply(closest_interaction)

func _end_run(success: bool, title = ""):
	var pre_wh = rules.profile.warehouse.size()
	var carried_value = rules.bag_value()
	var defeated_boss: bool = rules.boss_defeated
	if success:
		if not rules.finish_extraction():
			return
		play_sfx("loot_epic", -10)
		_save()
	else:
		rules.abandon()
	var banked_count = rules.profile.warehouse.size() - pre_wh
	combat.stop()
	if is_instance_valid(cipher_terminal) and cipher_terminal.busy:
		cipher_terminal.reset()
	paused = true
	player.clear_movement_input()
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show()
	hud.hide()
	_refresh_menu(title if title != "" else ("成功撤离！" if success else "行动结束"))
	review_button.visible = not wrong_words.is_empty()
	var header = ("成功带回 %d 件物资（含清哨%s奖励），随身估值 %d 币！\n" % [banked_count, "+首领" if defeated_boss else "", carried_value]) if success else "本局未撤离物资遗留在烟山，调整装备再战！\n"
	menu_summary.text = header + "识词命中 %d / %d 题（正确率 %d%%） · 最高 %d 连击\n" % [
		rules.correct, rules.answered, roundi(rules.accuracy() * 100), rules.best_streak
	]
	var eco_count: int = wildlife.eco_discoveries_total() if is_instance_valid(wildlife) else 0
	menu_summary.text += "攻克前哨 %d 处 · B区首领 %s · 完美破译 %d 箱 · 探索 %d/3 · 秘藏 %d/6 · 生态 %d/12\n" % [
		rules.outposts_cleared, "已击败" if defeated_boss else "未击败", rules.perfect_ciphers, exploration.completed(), exploration.secrets_completed(), eco_count
	]
	if wrong_words.size() > 0:
		menu_summary.text += "本局记录 %d 个待巩固词汇，点下方按钮复盘。" % wrong_words.size()
	else:
		menu_summary.text += "零错词完成行动！可在右侧出售物资兑换新装备。"

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var is_esc = (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE)
		if is_instance_valid(cipher_terminal) and cipher_terminal.busy and is_esc:
			cipher_terminal.close()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(exploration) and exploration.busy and is_esc:
			exploration.close()
			get_viewport().set_input_as_handled()
			return
		if is_esc and rules.phase in ["active", "extracting"]:
			if paused:
				start_action(rules.combat_mode)
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
			var quality_text = "画质：低负载 · 实时阴影关闭" if landscape.low_quality else "画质：标准 · 近景实时阴影"
			_notice(quality_text, MINT)
			menu_status.text = quality_text
		elif event.physical_keycode == KEY_F12 or event.keycode == KEY_F12:
			_capture("yanshan-" + str(Time.get_unix_time_from_system()) + ".png")

func _capture(filename: String):
	var folder = OS.get_environment("DRZ_SCREENSHOT_DIR")
	if folder == "":
		folder = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	screenshot_path = folder.path_join(filename)
	var error = get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("SCREENSHOT ", error, " ", screenshot_path)
