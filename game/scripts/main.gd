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
const LootUI = preload("res://scripts/loot_ui.gd")
const LootContainerUI = preload("res://scripts/loot_container_ui.gd")
const WorldLoot = preload("res://scripts/world_loot.gd")
const LearningStore = preload("res://scripts/learning_store.gd")
const SrsScheduler = preload("res://scripts/srs_scheduler.gd")
const Achievements = preload("res://scripts/achievements.gd")
const Rangers = preload("res://scripts/rangers.gd")
const PrologueScene = preload("res://scenes/prologue_chapter.tscn")
const VERSION = "0.8.4"
const SliceWorld = preload("res://scripts/slice_world.gd")
const WeaponView = preload("res://scripts/weapon.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Wildlife = preload("res://scripts/wildlife.gd")
const CaveWarden = preload("res://scripts/cave_warden.gd")

const INK = Color("101f29")
const MINT = Color("8de8c0")
const CREAM = Color("f1f2df")
const GOLD = Color("f4ca84")

var rules = Rules.new()
var font: Font
var player
var words = []
var sentences: Array = []
var cloze_index: Dictionary = {}
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
var cached_interactables = []
var exit_position = Layout.on_ground(Layout.EXIT)
var time_left = 480.0
var extraction_left = 0.0
var next_question_left = 0.0
var wrong_words = []
var paused = true
var scene_cache = {}
var sound_cache = {}
var sfx_cache = {}
var voice_manifest: Dictionary = {}
var voice_cache: Dictionary = {}
var voice_player: AudioStreamPlayer = null
var last_voice_backend: String = ""
var last_voice_key: String = ""
var tts_voice_id = ""
var listening_mode = false
var question_help_used := false
var run_started_ms := -1
var profile_read_failed := false
var last_save_error := ""
var last_backup_path := ""
var _unknown_profile_fields: Dictionary = {}
var force_save_fail_for_test := false
var distractor_rng := RandomNumberGenerator.new()

var ui: Control
var hud: Control
var menu: Control
var menu_title: Label
var menu_summary: Label
var menu_finance: Label
var menu_status: Label
var start_button: Button
var confidential_button: Button
var prologue_button: Button
var settings_button: Button
var settings_panel: Control
var setting_strict_cb: CheckBox
var setting_autospeak_cb: CheckBox
var setting_shake_cb: CheckBox
var setting_sfx_slider: HSlider
var setting_sfx_lbl: Label
var setting_voice_slider: HSlider
var setting_voice_lbl: Label
var setting_sens_slider: HSlider
var setting_sens_lbl: Label
var terminal_title_label: Label
var sell_button: Button
var armory_panel: Control
var armory_progress: Label
var retest_button: Button
var shop_buttons = {}
var unit_picker: OptionButton
var include_extra: CheckBox
var question_panel: Panel
var word_switch_flash: float = 0.0
var ammo_respawn_timers: Dictionary = {}
var question_label: Label
var cloze_label: Label
var unit_label: Label
var prompt_timer_bg: ColorRect
var prompt_timer_fill: ColorRect
var station_prompt_timer_left: float = 0.0
var station_prompt_timer_max: float = 10.0
var stat_label: Label
var mission_label: Label
var bag_label: Label
var bag_slots_box: HFlowContainer
var bag_signature = ""
var ammo_label: Label
var skill_panel: Panel
var skill_label: Label
var skill_bar_fill: ColorRect
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
var warehouse_button: Button
var compendium_button: Button
var camp_display_stand: Node3D
var camp_display_slots: Array = []
var camp_display_clock: float = 0.0
var combat: Node3D
var combat_panel: Panel
var combat_label: Label
var exploration
var wildlife
var cipher_terminal
var achievements
var rangers
var cave_warden
var prologue
var loot_ui
var loot_container_ui
var world_loot
var landscape
var minimap
var startup_ms := {}
var startup_menu_frame_ms := 0

func _ready():
	var startup_begin := Time.get_ticks_msec()
	startup_ms["boot_to_ready"] = startup_begin
	var step_begin := startup_begin
	qa_mode = "--qa" in OS.get_cmdline_user_args() or "--hardware-check" in OS.get_cmdline_user_args()
	get_tree().auto_accept_quit = false
	distractor_rng.randomize()
	var variable_font = FontVariation.new()
	variable_font.base_font = load("res://assets/font/NotoSansSC.ttf")
	variable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	font = variable_font
	_init_voice_pack()
	_init_tts()
	_load_words()
	sentences = LearningStore.load_sentences()
	cloze_index = LearningStore.build_cloze_index(sentences)
	_load_profile()
	startup_ms["font_voice_profile"] = Time.get_ticks_msec() - step_begin
	step_begin = Time.get_ticks_msec()
	_build_world()
	startup_ms["world_total"] = Time.get_ticks_msec() - step_begin
	step_begin = Time.get_ticks_msec()
	player = Player.new()
	player.game = self
	add_child(player)
	player.position = Vector3(0, 0.15, 4.5)
	combat = Combat.new()
	combat.game = self
	add_child(combat)
	_build_ui()
	startup_ms["player_ui"] = Time.get_ticks_msec() - step_begin
	step_begin = Time.get_ticks_msec()
	exploration = Exploration.new()
	add_child(exploration)
	exploration.setup(self)
	wildlife = Wildlife.new()
	add_child(wildlife)
	wildlife.setup(self)
	cave_warden = CaveWarden.new()
	add_child(cave_warden)
	cave_warden.setup(self)
	startup_ms["exploration_wildlife"] = Time.get_ticks_msec() - step_begin
	step_begin = Time.get_ticks_msec()
	world_loot = WorldLoot.new()
	add_child(world_loot)
	world_loot.setup(self)
	cipher_terminal = CipherTerminal.new()
	add_child(cipher_terminal)
	cipher_terminal.setup(self)
	loot_ui = LootUI.new()
	add_child(loot_ui)
	loot_ui.setup(self)
	loot_container_ui = LootContainerUI.new()
	add_child(loot_container_ui)
	loot_container_ui.setup(self)
	achievements = Achievements.new()
	add_child(achievements)
	achievements.setup(self)
	prologue = PrologueScene.instantiate()
	add_child(prologue)
	prologue.setup(self)
	rangers = Rangers.new()
	add_child(rangers)
	rangers.setup(self)
	_build_camp_display_stand()
	refresh_camp_display_stand()
	_sync_settings_ui()
	_refresh_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	startup_ms["loot_and_menu"] = Time.get_ticks_msec() - step_begin
	startup_ms["ready_total"] = Time.get_ticks_msec() - startup_begin
	var args := OS.get_cmdline_user_args()
	if "--startup-check" in args or "--hardware-check" in args:
		await get_tree().process_frame
		startup_ms["first_process_frame"] = Time.get_ticks_msec()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		startup_menu_frame_ms = Time.get_ticks_msec()
		startup_ms["playable_ready_ms"] = startup_menu_frame_ms
		print("STARTUP_REPORT ", JSON.stringify({
			"version": VERSION, "renderer": RenderingServer.get_current_rendering_method(),
			"menu_frame_ms": startup_menu_frame_ms, "playable_ready_ms": startup_menu_frame_ms,
			"stages_ms": startup_ms,
			"tts_setting_enabled": bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)),
			"tts_voice_ready": tts_voice_id != "",
			"voice_pack_count": voice_manifest.size(),
			"voice_sample_playable": load_voice_stream("Dragon Boat Festival") != null
		}))
		if "--startup-check" in args:
			get_tree().quit()
			return
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

static func normalize_voice_key(text: String) -> String:
	var s := text.replace("...", " ").replace("…", " ").replace("’", "'").replace("‘", "'")
	s = s.replace("\t", " ").replace("\n", " ").replace("\r", " ")
	var parts: PackedStringArray = s.strip_edges().split(" ", false)
	return " ".join(parts).to_lower()

func _init_voice_pack():
	voice_manifest.clear()
	var path := "res://data/learning/voice_manifest.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("entries") is Dictionary:
			voice_manifest = parsed.entries
	if not is_instance_valid(voice_player):
		voice_player = AudioStreamPlayer.new()
		voice_player.volume_db = -1.5
		add_child(voice_player)

func _init_tts():
	if qa_mode or DisplayServer.get_name() == "headless":
		return
	var voices = DisplayServer.tts_get_voices_for_language("en")
	if voices.size() > 0:
		tts_voice_id = voices[0]

func has_english_voice(text: String = "") -> bool:
	if text.strip_edges() != "":
		var key := normalize_voice_key(text)
		if voice_manifest.has(key):
			var fname := str(voice_manifest[key].get("file", ""))
			if fname != "" and ResourceLoader.exists("res://assets/voice/" + fname):
				return true
		return tts_voice_id != ""
	return not voice_manifest.is_empty() or tts_voice_id != ""

func load_voice_stream(text: String) -> AudioStream:
	var key := normalize_voice_key(text)
	if key == "" or not voice_manifest.has(key):
		return null
	if voice_cache.has(key):
		return voice_cache[key]
	var fname := str(voice_manifest[key].get("file", ""))
	if fname == "":
		return null
	var path := "res://assets/voice/" + fname
	if not ResourceLoader.exists(path):
		return null
	var stream = load(path)
	if stream is AudioStream:
		voice_cache[key] = stream
		return stream
	return null

func speak_english(text: String) -> bool:
	var key := normalize_voice_key(text)
	last_voice_key = key
	if key == "":
		last_voice_backend = "none"
		return false
	var voice_gain: float = float(rules.setting("voice_volume", 1.0))
	var stream := load_voice_stream(text)
	if stream != null:
		last_voice_backend = "ogg"
		if qa_mode or DisplayServer.get_name() == "headless" or voice_gain <= 0.005:
			return true
		DisplayServer.tts_stop()
		if not is_instance_valid(voice_player):
			voice_player = AudioStreamPlayer.new()
			add_child(voice_player)
		voice_player.volume_db = -1.5 + linear_to_db(voice_gain)
		voice_player.stop()
		voice_player.stream = stream
		voice_player.play()
		return true
	if qa_mode or DisplayServer.get_name() == "headless":
		last_voice_backend = "tts" if tts_voice_id != "" else "none"
		return tts_voice_id != ""
	if voice_gain <= 0.005:
		last_voice_backend = "tts" if tts_voice_id != "" else "none"
		return true
	if tts_voice_id == "":
		_init_tts()
	if tts_voice_id == "":
		last_voice_backend = "none"
		return false
	if is_instance_valid(voice_player):
		voice_player.stop()
	var clean := text.replace("...", " ").replace("…", " ").replace("’", "'").replace("‘", "'").strip_edges()
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(clean, tts_voice_id, clampi(roundi(90.0 * voice_gain), 0, 100), 1.0, 0.96)
	last_voice_backend = "tts"
	return true

func replay_question_audio():
	if question.is_empty():
		return
	var en_text := str(question.get("english", ""))
	if has_english_voice(en_text):
		if not listening_mode:
			question_help_used = true
		if speak_english(en_text):
			_notice("🔊 正在朗读英文发音", MINT)
			return
	_notice("提示：当前环境未检测到可用英文语音（离线语音与系统语音均未命中）", GOLD)

func _load_words():
	for file in DirAccess.get_files_at("res://data/wordpacks"):
		if file.ends_with(".json"):
			var pack = JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/" + file))
			if pack is Dictionary and pack.get("schema_version", 0) == 1:
				words.append_array(pack.get("entries", []))
	assert(words.size() >= 4, "词库至少需要四个词条")

func cloze_for_word(word_id: String) -> Dictionary:
	return cloze_index.get(word_id, {})

func _save_path() -> String:
	if profile_path_override != "":
		return profile_path_override
	return "user://qa-profile.json" if qa_mode else "user://profile-v070.json"

func _backup_pre_upgrade_profile(_source_path: String, raw_text: String):
	var bak_path: String = (profile_path_override + ".pre-v3.bak") if profile_path_override != "" else "user://profile-backup-pre-v3.json"
	if FileAccess.file_exists(bak_path):
		last_backup_path = bak_path
		return
	var bf := FileAccess.open(bak_path, FileAccess.WRITE)
	if bf != null:
		bf.store_string(raw_text)
		bf.close()
		last_backup_path = bak_path

func _load_profile():
	if qa_mode and profile_path_override == "":
		return
	profile_read_failed = false
	last_save_error = ""
	_unknown_profile_fields.clear()
	var path := _save_path()
	var loaded_from_legacy_file := false
	if not FileAccess.file_exists(path):
		if profile_path_override != "":
			return
		var fallback := ""
		for candidate in ["user://profile-v067.json", "user://profile-v01.json"]:
			if FileAccess.file_exists(candidate):
				fallback = candidate
				break
		if fallback == "":
			return
		path = fallback
		loaded_from_legacy_file = true
	var raw_text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(raw_text)
	if not (data is Dictionary):
		profile_read_failed = true
		last_save_error = "存档损坏或无法解析：" + path
		push_warning("Cannot read save profile: " + path)
		return
	if data is Dictionary:
		var incoming_schema: int = int(data.get("schema_version", 1))
		if loaded_from_legacy_file or incoming_schema < Rules.PROFILE_SCHEMA_VERSION:
			_backup_pre_upgrade_profile(path, raw_text)
		for k in data.keys():
			if not rules.profile.has(k):
				_unknown_profile_fields[k] = data[k]
		for key in rules.profile:
			if data.has(key) and typeof(data[key]) == typeof(rules.profile[key]):
				rules.profile[key] = data[key]
		rules.profile["schema_version"] = incoming_schema
		for key in ["coins", "xp", "points", "runs", "extractions", "red_extracted", "gold_extracted", "small_gold_extracted", "best_haul", "best_item_value", "prologue_best_seconds"]:
			if data.has(key) or rules.profile.has(key):
				rules.profile[key] = maxi(0, int(data.get(key, rules.profile.get(key, 0))))
		var normalized_wh = []
		for item in rules.profile.warehouse:
			if item is Dictionary:
				var raw_d := {
					"title": str(item.get("title", "物资")),
					"en": str(item.get("en", "")),
					"value": maxi(1, int(item.get("value", 20))),
					"rarity": clampi(int(item.get("rarity", 1)), 1, Rules.MAX_RARITY),
					"cond": str(item.get("cond", "标准")),
					"grid": str(item.get("grid", "")),
					"icon": str(item.get("icon", "")),
					"lore": str(item.get("lore", ""))
				}
				if item.has("locked"):
					raw_d["locked"] = bool(item.get("locked", false))
				normalized_wh.append(rules._enrich_loot_dict(raw_d))
		rules.profile.warehouse = normalized_wh
	rules.migrate_legacy_items()
	rules.ensure_equipped()

func _save() -> bool:
	if qa_mode and profile_path_override == "":
		return true
	if force_save_fail_for_test:
		last_save_error = "模拟磁盘写入受阻（QA 测试）"
		return false
	if profile_read_failed:
		last_save_error = "原存档读取失败，为防止覆盖已中止写入"
		return false
	var path := _save_path()
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_save_error = "无法创建临时存档：" + temp
		push_warning("Cannot create temporary save: " + temp)
		return false
	rules.profile["schema_version"] = Rules.PROFILE_SCHEMA_VERSION
	rules.profile["saved_by_version"] = VERSION
	var payload: Dictionary = _unknown_profile_fields.duplicate(true)
	for k in rules.profile.keys():
		payload[k] = rules.profile[k]
	file.store_string(JSON.stringify(payload, "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temp, path) != OK:
		last_save_error = "无法替换存档文件：" + path
		push_warning("Cannot replace save profile: " + path)
		return false
	last_save_error = ""
	return true

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(menu):
		_quit_game()

func _quit_game():
	if rules.phase in ["active", "extracting"]:
		_end_run(false, "退出行动")
	get_tree().quit()

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
	var tw_lbl = _label3d(tower, "烟山观察哨 · 登顶寻宝", Vector3(0, 7.2, 0), 43, GOLD)
	tw_lbl.visibility_range_end = 44.0
	return tower

func _crate_accent(_tier: int) -> Color:
	# v0.8.0 #11: uniform blind-box accent so containers never spoil rarity before opening!
	return GOLD

func _make_crate(title: String, tier: int, at: Vector3) -> Node3D:
	var crate = Node3D.new()
	crate.position = at
	crate.set_meta("title", title)
	crate.set_meta("tier", tier)
	add_child(crate)
	var req = rules.crate_requirements(tier)
	var lock_desc = "单词+词组双关锁"
	if tier == 2:
		lock_desc = "词组+短句双关锁"
	elif tier >= 3:
		lock_desc = "词汇+词组+整句三重破译"
	var tag = "%s\n%d题 · %d%%正确率 · %s" % [title, req.minimum, roundi(req.accuracy * 100), lock_desc]
	var lbl = _label3d(crate, tag, Vector3(0, 1.75, 0), 30, _crate_accent(tier))
	lbl.pixel_size = 0.0056
	lbl.visibility_range_end = 28.0
	crate_nodes.append(crate)
	return crate

func _build_camp_display_stand():
	## v0.8.0 Camp Courtyard 4-Slot 3D Showcase Display Stand ('烟山奇珍展台')
	## Positioned on sunny east-center camp lawn facing the player courtyard; renders up to 4 pinned 3D collectibles!
	camp_display_stand = Node3D.new()
	camp_display_stand.name = "CampDisplayStand"
	camp_display_stand.position = Layout.on_ground(Vector3(-6.8, 0.0, 0.8))
	camp_display_stand.rotation.y = 0.62
	add_child(camp_display_stand)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("3a241b")
	wood_mat.roughness = 0.44
	wood_mat.metallic = 0.12

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color("c9a252")
	brass_mat.metallic = 0.78
	brass_mat.roughness = 0.28

	# Grounded rosewood gallery cabinet (collidable so player walks cleanly around it)
	var base: MeshInstance3D = _mesh_box(camp_display_stand, Vector3(0, 0.42, 0), Vector3(3.12, 0.84, 0.78), Color("3a241b"), true)
	base.material_override = wood_mat
	var trim_top: MeshInstance3D = _mesh_box(camp_display_stand, Vector3(0, 0.855, 0), Vector3(3.18, 0.04, 0.84), Color("c9a252"), false)
	trim_top.material_override = brass_mat
	var backboard: MeshInstance3D = _mesh_box(camp_display_stand, Vector3(0, 1.18, -0.34), Vector3(3.10, 0.68, 0.08), Color("281914"), false)
	backboard.material_override = wood_mat
	var crown: MeshInstance3D = _mesh_box(camp_display_stand, Vector3(0, 1.54, -0.34), Vector3(3.18, 0.05, 0.14), Color("c9a252"), false)
	crown.material_override = brass_mat

	var header_lbl: Label3D = _label3d(camp_display_stand, "🏆 烟山奇珍 3D 展台（最多陈列 4 件）", Vector3(0, 1.80, -0.20), 28, Color("ffd46e"))
	header_lbl.pixel_size = 0.0052
	header_lbl.visibility_range_end = 18.0

	camp_display_slots.clear()
	var x_offsets := [-1.08, -0.36, 0.36, 1.08]
	for i in Rules.MAX_DISPLAY_STAND:
		var slot_root := Node3D.new()
		slot_root.position = Vector3(x_offsets[i], 0.88, 0.04)
		camp_display_stand.add_child(slot_root)

		var ped := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.28
		cyl.height = 0.06
		ped.mesh = cyl
		ped.position.y = 0.03
		ped.material_override = wood_mat
		slot_root.add_child(ped)

		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.23
		tm.outer_radius = 0.26
		ring.mesh = tm
		ring.position.y = 0.062
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("5a7d72")
		rmat.metallic = 0.65
		rmat.roughness = 0.28
		ring.material_override = rmat
		slot_root.add_child(ring)

		var mount := Node3D.new()
		mount.name = "RelicMount"
		mount.position.y = 0.075
		slot_root.add_child(mount)

		var plaque: Label3D = _label3d(slot_root, "空展位 #%d" % (i + 1), Vector3(0, -0.18, 0.39), 18, Color("9ebdb0"))
		plaque.pixel_size = 0.0036
		plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		plaque.visibility_range_end = 11.0
		camp_display_slots.append({"root": slot_root, "mount": mount, "ring": ring, "plaque": plaque})

func refresh_camp_display_stand():
	if camp_display_slots.is_empty():
		return
	var stand_titles: Array = rules.profile.get("display_stand", [])
	for i in camp_display_slots.size():
		var slot: Dictionary = camp_display_slots[i]
		var mount: Node3D = slot.mount
		var ring: MeshInstance3D = slot.ring
		var plaque: Label3D = slot.plaque
		for ch in mount.get_children():
			ch.queue_free()
		if i < stand_titles.size():
			var title_s: String = str(stand_titles[i])
			var meta: Dictionary = Rules.catalog_meta(title_s)
			var r: int = clampi(int(meta.get("rarity", 5)), 1, Rules.MAX_RARITY)
			var r_col: Color = Rules.RARITY_COLORS[r]
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = r_col
			rmat.metallic = 0.72
			rmat.roughness = 0.22
			rmat.emission_enabled = true
			rmat.emission = r_col
			rmat.emission_energy_multiplier = 1.25 if r >= 6 else 0.75
			ring.material_override = rmat
			var mesh_3d := LootUI.build_world_loot_mesh(meta if not meta.is_empty() else title_s, r, r_col, 1.38)
			mount.add_child(mesh_3d)
			plaque.text = "%s\n%s" % [title_s, str(meta.get("en", ""))]
			plaque.modulate = r_col
		else:
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = Color("5a7d72")
			dmat.metallic = 0.45
			dmat.roughness = 0.45
			ring.material_override = dmat
			plaque.text = "空展位 #%d\n在仓库点★上展台" % (i + 1)
			plaque.modulate = Color("8aa89c")

func attach_weapon(parent: Node3D):
	var view = WeaponView.new()
	view.game = self
	parent.add_child(view)
	return view

func play_sound(id: String, volume = -16):
	if DisplayServer.get_name() == "headless":
		return
	var gain: float = float(rules.setting("sfx_volume", 1.0))
	if gain <= 0.005:
		return
	var path = "res://assets/fps/sounds/" + id + ".ogg"
	if not ResourceLoader.exists(path):
		return
	if not sound_cache.has(id):
		sound_cache[id] = load(path)
	var sound = AudioStreamPlayer.new()
	sound.stream = sound_cache[id]
	sound.volume_db = volume + linear_to_db(gain)
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func play_sfx(id: String, volume = -13):
	if DisplayServer.get_name() == "headless":
		return
	var gain: float = float(rules.setting("sfx_volume", 1.0))
	if gain <= 0.005:
		return
	var path = "res://assets/sfx/" + id + ".wav"
	if not ResourceLoader.exists(path):
		return
	if not sfx_cache.has(id):
		sfx_cache[id] = load(path)
	var sound = AudioStreamPlayer.new()
	sound.stream = sfx_cache[id]
	sound.volume_db = volume + linear_to_db(gain)
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

func _style_tactical_button(button: Button, bg: Color, border: Color, font_col: Color):
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = bg
		if style_name == "hover":
			style.bg_color = bg.lightened(0.13)
		elif style_name == "pressed":
			style.bg_color = bg.darkened(0.08)
		elif style_name == "disabled":
			style.bg_color = Color("19272d")
		style.border_color = border if style_name != "disabled" else Color(0.52, 0.65, 0.62, 0.14)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(style_name, style)
	button.add_theme_color_override("font_color", font_col)
	button.add_theme_color_override("font_hover_color", font_col)
	button.add_theme_color_override("font_pressed_color", font_col)
	button.add_theme_color_override("font_disabled_color", Color("6f8680"))

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
	terminal_title_label = _text(hud, "YANSHAN · 烟山战术终端", Vector2(32, 22), Vector2(262, 22), 14, MINT)
	fps_label = _text(hud, "", Vector2(298, 22), Vector2(78, 22), 13, Color("9ecfc0"))
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_label = _text(hud, "", Vector2(32, 46), Vector2(346, 24), 16, CREAM)
	mission_label = _text(hud, "", Vector2(32, 74), Vector2(346, 46), 13, GOLD)
	mission_label.clip_text = true
	guide_label = _text(hud, "", Vector2(32, 128), Vector2(346, 42), 12, Color("a9c7ba"))
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.clip_text = true

	# ZONE 2: Top-Center Sleek Word Prompt Card (with optional Textbook Cloze Context line)
	question_panel = _panel(hud, Rect2(398, 16, 514, 116), Color(0.038, 0.095, 0.118, 0.88), Color(0.55, 0.90, 0.74, 0.55))
	question_label = _text(hud, "", Vector2(412, 18), Vector2(486, 46), 25, CREAM)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cloze_label = _text(hud, "", Vector2(412, 65), Vector2(486, 24), 15, Color("ffe08c"))
	cloze_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cloze_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cloze_label.clip_text = true
	unit_label = _text(hud, "", Vector2(412, 91), Vector2(486, 36), 13, MINT)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# v0.8.1 #4: Sleek unanswered-question countdown strip along bottom edge of Word Prompt Card
	prompt_timer_bg = ColorRect.new()
	prompt_timer_bg.position = Vector2(404, 126)
	prompt_timer_bg.size = Vector2(502, 4)
	prompt_timer_bg.color = Color(0.10, 0.20, 0.22, 0.85)
	prompt_timer_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_timer_bg.hide()
	hud.add_child(prompt_timer_bg)
	prompt_timer_fill = ColorRect.new()
	prompt_timer_fill.position = Vector2(404, 126)
	prompt_timer_fill.size = Vector2(502, 4)
	prompt_timer_fill.color = MINT
	prompt_timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_timer_fill.hide()
	hud.add_child(prompt_timer_fill)

	# Threat Warning Banner (only shown when actively locked on)
	threat_banner = _panel(hud, Rect2(455, 138, 400, 30), Color(0.38, 0.09, 0.09, 0.90), Color("ff6b6b"))
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

	# ZONE 4B-TOP: Ranger Active [V] Skill Card ('游侠·少羽 · [V] 天生神力')
	skill_panel = _panel(hud, Rect2(954, 514, 308, 46), Color(0.055, 0.095, 0.112, 0.90), Color("ffd15c"))
	skill_label = _text(skill_panel, "⚡ 少羽 · [V] 天生神力 · 就绪！", Vector2(12, 6), Vector2(284, 22), 14, Color("ffd86b"))
	skill_label.clip_text = true
	var sk_bg := ColorRect.new()
	sk_bg.position = Vector2(12, 31)
	sk_bg.size = Vector2(284, 7)
	sk_bg.color = Color(0.10, 0.18, 0.20, 0.92)
	sk_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_panel.add_child(sk_bg)
	skill_bar_fill = ColorRect.new()
	skill_bar_fill.position = Vector2(12, 31)
	skill_bar_fill.size = Vector2(284, 7)
	skill_bar_fill.color = Color("ffd15c")
	skill_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_panel.add_child(skill_bar_fill)

	# ZONE 4B: Bottom-Right Weapon, Reserve Ammo & Tactical Consumables Card
	_panel(hud, Rect2(954, 566, 308, 136))
	ammo_label = _text(hud, "", Vector2(968, 574), Vector2(282, 122), 14, CREAM)

	# Center Prompts & Tactical Reticles
	feedback_panel = _panel(hud, Rect2(340, 506, 600, 76), Color(0.04, 0.11, 0.12, 0.92), Color(0.55, 0.88, 0.72, 0.5))
	feedback_panel.hide()
	feedback_label = _text(hud, "", Vector2(354, 512), Vector2(572, 64), 17, MINT)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.clip_text = true

	interaction_panel = _panel(hud, Rect2(384, 594, 524, 38), Color(0.04, 0.09, 0.11, 0.82))
	interaction_label = _text(hud, "", Vector2(394, 596), Vector2(504, 34), 16, GOLD)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	crosshair_label = _text(hud, "+", Vector2(622, 338), Vector2(36, 42), 26, Color(0.92, 0.98, 0.94, 0.85))
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	hitmarker_label = _text(hud, "×", Vector2(616, 332), Vector2(48, 48), 34, MINT)
	hitmarker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hitmarker_label.hide()

	_text(hud, "[WASD]移动  [C]蹲 [Z]趴  [Q/E]探头  [V]游侠技能  [F]搜刮/交互  [B]背包  [I]检视  [X]读音  [1/2]枪刀  [H/G/T]道具  [F6]画质", Vector2(286, 682), Vector2(712, 22), 11, Color("a9c2b5")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
	_panel(menu, Rect2(86, 56, 534, 608), Color(0.038, 0.082, 0.102, 0.97), Color(0.46, 0.80, 0.66, 0.42))

	menu_title = _text(menu, "烟山基地", Vector2(120, 76), Vector2(204, 44), 28, MINT)
	menu_title.clip_text = true
	_text(menu, "英语搜撤行动 · v" + VERSION, Vector2(122, 124), Vector2(460, 22), 15, GOLD)
	settings_button = _button(menu, "⚙ 设置", Rect2(328, 86, 72, 36), func():
		armory_panel.hide()
		settings_panel.visible = not settings_panel.visible
		if settings_panel.visible:
			_sync_settings_ui()
	)
	settings_button.add_theme_font_size_override("font_size", 13)
	_button(menu, "退出", Rect2(518, 86, 64, 36), _quit_game)
	abandon_button = _button(menu, "放弃本局", Rect2(406, 86, 104, 36), func(): _end_run(false, "放弃本局"))
	abandon_button.hide()

	menu_summary = _text(menu, "", Vector2(122, 150), Vector2(460, 124), 14)
	menu_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_summary.clip_text = false
	review_button = _button(menu, "查看本局错词与例句（含页码）", Rect2(122, 278, 456, 28), _show_review)
	review_button.hide()

	unit_picker = OptionButton.new()
	unit_picker.position = Vector2(122, 312)
	unit_picker.size = Vector2(290, 36)
	unit_picker.add_item("全部单元 · %d 条词汇" % words.size())
	for i in range(1, 9):
		unit_picker.add_item("Unit " + str(i))
	menu.add_child(unit_picker)

	include_extra = CheckBox.new()
	include_extra.text = "含拓展词与专名"
	include_extra.position = Vector2(422, 314)
	include_extra.button_pressed = true
	include_extra.add_theme_font_size_override("font_size", 15)
	menu.add_child(include_extra)
	unit_picker.item_selected.connect(func(_index): _refresh_progress())
	include_extra.toggled.connect(func(_on): _refresh_progress())

	prologue_button = _button(menu, "✨ 烟山初行 · 单人序章（推荐首玩 · 5–8分钟）", Rect2(122, 356, 456, 42), func():
		try_menu_deploy(false, "prologue")
	)
	_style_tactical_button(prologue_button, Color("1f4f42"), Color("8de8c0"), Color("f4fffa"))

	start_button = _button(menu, "开始普通行动", Rect2(122, 406, 154, 46), func():
		var in_active: bool = rules.phase in ["active", "extracting"]
		try_menu_deploy(rules.combat_mode if in_active else true, rules.operation_tier if in_active else "normal")
	, true)
	confidential_button = _button(menu, "机密行动", Rect2(284, 406, 154, 46), func(): try_menu_deploy(true, "confidential"))
	_style_tactical_button(confidential_button, Color("683c1c"), Color("ffb84d"), Color("fff0cf"))
	practice_button = _button(menu, "自由靶场", Rect2(446, 406, 132, 46), func(): try_menu_deploy(false, "normal"))

	_button(menu, "战备与改装", Rect2(122, 460, 146, 36), func():
		settings_panel.hide()
		armory_panel.visible = not armory_panel.visible
	)
	warehouse_button = _button(menu, "我的仓库", Rect2(276, 460, 148, 36), func():
		if is_instance_valid(loot_ui):
			armory_panel.hide()
			settings_panel.hide()
			loot_ui.open_warehouse()
	)
	_style_tactical_button(warehouse_button, Color("3c341a"), Color("f6c34e"), Color("fff2c4"))
	compendium_button = _button(menu, "奇珍图鉴", Rect2(432, 460, 146, 36), func():
		if is_instance_valid(loot_ui):
			armory_panel.hide()
			settings_panel.hide()
			loot_ui.open_compendium()
	)
	retest_button = _button(menu, "无提示复测", Rect2(122, 504, 456, 36), _open_retest)
	menu_finance = _text(menu, "", Vector2(122, 548), Vector2(460, 50), 14, GOLD)
	menu_status = _text(menu, "", Vector2(122, 602), Vector2(460, 50), 13, Color("a9c4b6"))
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Comfort, Audio, Sensitivity & Strict Review Settings Drawer (Right side of Menu/Pause)
	settings_panel = Control.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(settings_panel)
	_panel(settings_panel, Rect2(634, 56, 560, 608), Color(0.038, 0.082, 0.102, 0.97), Color("8de8c0"))
	_text(settings_panel, "⚙ 舒适、音量与学习设置", Vector2(662, 86), Vector2(390, 36), 24, MINT)
	_button(settings_panel, "收起", Rect2(1104, 86, 64, 36), func(): settings_panel.hide())

	setting_shake_cb = CheckBox.new()
	setting_shake_cb.text = "减震动 / 关闭镜头震动（降低晕动，保留清晰文字与命中提示）"
	setting_shake_cb.position = Vector2(662, 146)
	setting_shake_cb.size = Vector2(506, 36)
	setting_shake_cb.add_theme_font_size_override("font_size", 15)
	setting_shake_cb.toggled.connect(func(on: bool):
		rules.set_setting("reduce_screen_shake", on)
		_save()
	)
	settings_panel.add_child(setting_shake_cb)

	setting_sfx_lbl = _text(settings_panel, "枪械与环境音效音量：100%", Vector2(662, 202), Vector2(500, 26), 15, CREAM)
	setting_sfx_slider = HSlider.new()
	setting_sfx_slider.position = Vector2(662, 232)
	setting_sfx_slider.size = Vector2(500, 26)
	setting_sfx_slider.min_value = 0.0
	setting_sfx_slider.max_value = 1.0
	setting_sfx_slider.step = 0.05
	setting_sfx_slider.value = 1.0
	setting_sfx_slider.value_changed.connect(func(v: float):
		rules.set_setting("sfx_volume", v)
		setting_sfx_lbl.text = "枪械与环境音效音量：%d%%" % roundi(v * 100.0)
		_save()
	)
	settings_panel.add_child(setting_sfx_slider)

	setting_voice_lbl = _text(settings_panel, "英语语音读音音量：100%", Vector2(662, 276), Vector2(336, 26), 15, MINT)
	_button(settings_panel, "🔊 试听英语读音", Rect2(1012, 272, 150, 34), func(): speak_english("Dragon Boat Festival"))
	setting_voice_slider = HSlider.new()
	setting_voice_slider.position = Vector2(662, 310)
	setting_voice_slider.size = Vector2(500, 26)
	setting_voice_slider.min_value = 0.0
	setting_voice_slider.max_value = 1.0
	setting_voice_slider.step = 0.05
	setting_voice_slider.value = 1.0
	setting_voice_slider.value_changed.connect(func(v: float):
		rules.set_setting("voice_volume", v)
		setting_voice_lbl.text = "英语语音读音音量：%d%%" % roundi(v * 100.0)
		_save()
	)
	settings_panel.add_child(setting_voice_slider)

	setting_sens_lbl = _text(settings_panel, "鼠标视角灵敏度：1.00x", Vector2(662, 356), Vector2(500, 26), 15, GOLD)
	setting_sens_slider = HSlider.new()
	setting_sens_slider.position = Vector2(662, 386)
	setting_sens_slider.size = Vector2(500, 26)
	setting_sens_slider.min_value = 0.4
	setting_sens_slider.max_value = 2.2
	setting_sens_slider.step = 0.05
	setting_sens_slider.value = 1.0
	setting_sens_slider.value_changed.connect(func(v: float):
		rules.set_setting("mouse_sensitivity", v)
		setting_sens_lbl.text = "鼠标视角灵敏度：%.2fx" % v
		_save()
	)
	settings_panel.add_child(setting_sens_slider)

	setting_strict_cb = CheckBox.new()
	setting_strict_cb.text = "严格今日到期复习门禁（跨单元全词库必做，切单元不可跳过）"
	setting_strict_cb.position = Vector2(662, 434)
	setting_strict_cb.size = Vector2(506, 34)
	setting_strict_cb.add_theme_font_size_override("font_size", 15)
	setting_strict_cb.toggled.connect(func(on: bool):
		rules.set_setting("strict_daily_review", on)
		_save()
		_refresh_progress()
	)
	settings_panel.add_child(setting_strict_cb)

	setting_autospeak_cb = CheckBox.new()
	setting_autospeak_cb.text = "切换新词时立即自动朗读英文读音（听音索敌，不扣独立答对）"
	setting_autospeak_cb.position = Vector2(662, 474)
	setting_autospeak_cb.size = Vector2(506, 34)
	setting_autospeak_cb.add_theme_font_size_override("font_size", 15)
	setting_autospeak_cb.toggled.connect(func(on: bool):
		rules.set_setting("auto_speak_on_switch", on)
		_save()
	)
	settings_panel.add_child(setting_autospeak_cb)

	var set_note: Label = _text(settings_panel,
		"说明：\n• 局内随时按 [Esc] 即可打开本设置并立即生效。\n• 同一 Windows 账户共用独立存档（升级旧档前自动创建 .pre-v3 备份）。\n• 低配核显可按 [F6] 关闭实时阴影，或使用「低负载启动.cmd」。",
		Vector2(662, 520), Vector2(502, 126), 13, Color("9ec4b5"))
	set_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_panel.hide()

	armory_panel = Control.new()
	armory_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	armory_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(armory_panel)
	_panel(armory_panel, Rect2(634, 56, 560, 608), Color(0.038, 0.082, 0.102, 0.97), Color(0.46, 0.80, 0.66, 0.42))
	_text(armory_panel, "战备仓库与改装", Vector2(662, 134), Vector2(374, 35), 24, MINT)
	armory_progress = _text(armory_panel, "", Vector2(662, 176), Vector2(500, 24), 15, GOLD)
	_button(armory_panel, "收起", Rect2(1104, 86, 64, 36), func(): armory_panel.hide())
	sell_button = _button(armory_panel, "出售仓库物资", Rect2(658, 204, 512, 42), _sell, true)

	for idx in Rules.GUNSMITH_ORDER.size():
		var id: String = Rules.GUNSMITH_ORDER[idx]
		var col = idx % 3
		var row = int(idx / 3)
		var rect = Rect2(658 + col * 172, 262 + row * 57, 164, 46)
		shop_buttons[id] = _button(armory_panel, "", rect, _buy.bind(id))
		shop_buttons[id].add_theme_font_size_override("font_size", 13)
	armory_panel.hide()

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
		var line := "[url=%s][color=#8de8c0]🔊 %s[/color][/url]  —  %s\n[color=#a9c4b6]Unit %d · 课本第 %d 页[/color]" % [word.english, word.english, word.chinese, word.unit, word.textbook_page]
		var cloze := cloze_for_word(str(word.get("id", "")))
		if not cloze.is_empty():
			line += "\n[color=#ffe08c]例句：%s（%s · p.%d）[/color]" % [cloze.english, cloze.chinese, int(cloze.textbook_page)]
		lines.append(line + "\n")
	review_text.text = "\n".join(lines) if not lines.is_empty() else "本局还没有错词，表现非常棒！"
	review_text.scroll_to_line(0)
	review_overlay.show()

func _warehouse_total_value() -> int:
	var sum = 0
	for item in rules.profile.warehouse:
		sum += int(item.get("value", 0))
	return sum

func _sync_settings_ui():
	var st: Dictionary = rules.ensure_settings()
	if is_instance_valid(setting_shake_cb):
		setting_shake_cb.set_pressed_no_signal(bool(st.get("reduce_screen_shake", false)))
	if is_instance_valid(setting_strict_cb):
		setting_strict_cb.set_pressed_no_signal(bool(st.get("strict_daily_review", true)))
	if is_instance_valid(setting_autospeak_cb):
		setting_autospeak_cb.set_pressed_no_signal(bool(st.get("auto_speak_on_switch", true)))
	if is_instance_valid(setting_sfx_slider):
		var sv: float = float(st.get("sfx_volume", 1.0))
		setting_sfx_slider.set_value_no_signal(sv)
		setting_sfx_lbl.text = "枪械与环境音效音量：%d%%" % roundi(sv * 100.0)
	if is_instance_valid(setting_voice_slider):
		var vv: float = float(st.get("voice_volume", 1.0))
		setting_voice_slider.set_value_no_signal(vv)
		setting_voice_lbl.text = "英语语音读音音量：%d%%" % roundi(vv * 100.0)
	if is_instance_valid(setting_sens_slider):
		var ms: float = float(st.get("mouse_sensitivity", 1.0))
		setting_sens_slider.set_value_no_signal(ms)
		setting_sens_lbl.text = "鼠标视角灵敏度：%.2fx" % ms

func _pending_retest() -> Array:
	if bool(rules.setting("strict_daily_review", true)):
		return rules.learning.pending(words + sentences, 0, true)
	return rules.learning.pending(words + sentences, unit_picker.selected, include_extra.button_pressed)

func daily_review_required() -> bool:
	return (rules.phase not in ["active", "extracting"]) and not _pending_retest().is_empty()

func try_menu_deploy(as_combat: bool, op_tier: String = "normal") -> bool:
	var same_active_run: bool = (rules.phase in ["active", "extracting"]) and (bool(rules.combat_mode) == bool(as_combat)) and (rules.operation_tier == op_tier)
	if same_active_run:
		start_action(as_combat, op_tier)
		return true
	if op_tier == "prologue":
		# First-time players can always enter the standalone Prologue directly from a clean save!
		if not bool(rules.profile.get("prologue_completed", false)) or _pending_retest().is_empty():
			start_prologue_chapter(true)
			return true
	if not _pending_retest().is_empty():
		var rem := _pending_retest().size()
		var scope_note := "（全词库严格模式）" if bool(rules.setting("strict_daily_review", true)) else "（当前单元范围）"
		menu_status.text = "🔒 请先完成今日到期复习%s（剩 %d 题），全部通过后自动解锁出击！" % [scope_note, rem]
		play_sfx("warning_lock", -12)
		_open_retest()
		return false
	if op_tier == "prologue":
		start_prologue_chapter(true)
		return true
	start_action(as_combat, op_tier)
	return true

func start_prologue_chapter(auto_briefing: bool = true):
	start_action(false, "prologue")
	if is_instance_valid(prologue):
		prologue.start_prologue(auto_briefing)

func _open_retest():
	if rules.phase not in ["active", "extracting"]:
		var todo := _pending_retest()
		if not todo.is_empty():
			cipher_terminal.open_retest(todo)

func _refresh_progress():
	var pending := _pending_retest().size()
	var in_run: bool = rules.phase in ["active", "extracting"]
	var blocked_by_review: bool = (not in_run) and pending > 0
	var strict_on: bool = bool(rules.setting("strict_daily_review", true))
	if is_instance_valid(prologue_button):
		var done_p: bool = bool(rules.profile.get("prologue_completed", false))
		prologue_button.visible = not in_run
		if done_p:
			prologue_button.text = "🔒 重温序章 · 烟山初行" if blocked_by_review else "✓ 烟山初行 · 重温单人序章（望稻亭失联信标）"
		else:
			prologue_button.text = "✨ 烟山初行 · 单人序章（推荐新玩家首玩 · 5–8分钟）"
	if blocked_by_review:
		retest_button.text = "🔒 必做 · 完成今日到期复习（%s剩 %d 题）" % ["全词库" if strict_on else "本单元", pending]
		_style_tactical_button(retest_button, Color("6c4318"), Color("ffd15c"), Color("fff4d1"))
		start_button.text = "🔒 普通行动"
		confidential_button.text = "🔒 机密行动"
		practice_button.text = "🔒 自由靶场"
	else:
		retest_button.text = "今日到期复测 · 0 题待练（已全部完成）" if pending == 0 else "今日到期复测 · %d 题待练" % pending
		_style_tactical_button(retest_button, Color("173138"), Color("4a7570"), Color("b8d8ce"))
		start_button.text = ("继续%s" % rules.mode_label()) if in_run else "开始普通行动"
		confidential_button.text = "机密行动"
		practice_button.text = "自由靶场"
	retest_button.disabled = pending == 0 or in_run
	var ranger_tag := ""
	if is_instance_valid(rangers):
		var ar: Dictionary = rangers.active_ranger()
		ranger_tag = "游侠·%s · 名望 %d（%s） | " % [str(ar.name), rangers.reputation(), rangers.reputation_rank()]
	menu_finance.text = "掌握词条 %d/%d · 句型 %d/%d · 到期 %d\n%s货币 %d · 奖励券 %d" % [
		rules.learning.mastered_count(words), words.size(), rules.learning.mastered_count(sentences),
		sentences.size(), pending, ranger_tag, rules.profile.coins, rules.profile.points
	]

func _refresh_menu(result = ""):
	_refresh_progress()
	var collected = rules.profile.collection.size()
	var total_collectibles = Rules.total_collectible_count()
	var ach_cnt: int = int(achievements.unlocked_count()) if is_instance_valid(achievements) else 0
	compendium_button.text = "图鉴·成就(%d)" % ach_cnt
	compendium_button.tooltip_text = "高阶奇珍 %d/%d · 成就与枪械挂件" % [collected, total_collectibles]
	var wh_count = rules.profile.warehouse.size()
	if is_instance_valid(warehouse_button):
		warehouse_button.text = "我的仓库 · %d" % wh_count
		warehouse_button.disabled = rules.phase in ["active", "extracting"]
	menu_title.text = result if result != "" else "烟山基地"
	if result == "":
		var done_p: bool = bool(rules.profile.get("prologue_completed", false))
		menu_summary.text = (
			"首次来烟山？推荐先体验上方「烟山初行 · 单人序章」（5–8 分钟）熟悉听词、路线与交锋！\n正式行动中认词、搜盲盒、把珍宝存进安全箱带回营地；按「⚙ 设置」可调减震动与音量。"
			if not done_p else
			"认词、搜盲盒、把大金/大红放进安全箱带回营地！\n可在「我的仓库」单件出售、🔒锁存珍宝或摆上营地 3D 展台；按「⚙ 设置」可调舒适选项。"
		)
		menu_status.text = "学习统计区分「独立答对」与「提示/练习完成」，避免虚高。"
		if profile_read_failed or last_save_error != "":
			menu_summary.text = "⚠ 存档状态提醒：" + (last_save_error if last_save_error != "" else "存档读取异常，已保护原文件不覆盖。") + "\n" + menu_summary.text

	var unlocked_cnt: int = rules.unlocked_warehouse_count()
	var unlocked_val: int = rules.unlocked_warehouse_value()
	var locked_cnt: int = rules.locked_warehouse_count()
	sell_button.text = "出售未锁物资（%d件·%d币 | 已锁%d件）" % [unlocked_cnt, unlocked_val, locked_cnt]
	sell_button.disabled = unlocked_cnt == 0 or rules.phase in ["active", "extracting"]

	var eq_optic: String = rules.active_optic()
	var eq_muzzle: String = rules.active_muzzle()
	var eq_grip: String = rules.active_grip()
	var in_run: bool = rules.phase in ["active", "extracting"]
	armory_progress.text = "等级 %d · %d/120 XP · 带回大红 %d 件" % [
		rules.level(), rules.profile.xp % 120, rules.profile.red_extracted
	]

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

	start_button.text = ("继续%s" % rules.mode_label()) if in_run else ("🔒 普通行动" if daily_review_required() else "开始普通行动")
	start_button.size = Vector2(274 if in_run else 154, 46)
	if is_instance_valid(confidential_button):
		confidential_button.visible = not in_run
	practice_button.visible = not in_run
	if is_instance_valid(prologue_button):
		prologue_button.visible = not in_run
	abandon_button.visible = in_run
	unit_picker.disabled = in_run
	include_extra.disabled = unit_picker.disabled

func _sell():
	var value = rules.sell_all()
	if value > 0:
		play_sfx("cipher_unlock", -12)
	_save()
	refresh_camp_display_stand()
	_refresh_menu()
	var kept_locked: int = rules.locked_warehouse_count()
	menu_status.text = "已出售全部未锁物资，获得 +%d 枚货币！%s" % [value, ("（%d 件🔒锁存珍宝已安全保留）" % kept_locked) if kept_locked > 0 else ""]

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
	return SrsScheduler.build_session_queue(rules.profile, pool)

func _refresh_terminal_title():
	if not is_instance_valid(terminal_title_label):
		return
	if rules.prologue_mode:
		terminal_title_label.text = "YANSHAN · 烟山初行（单人序章）"
		terminal_title_label.add_theme_color_override("font_color", Color("ffd166"))
	elif rules.is_confidential():
		terminal_title_label.text = "YANSHAN · 机密行动 (估值×1.35)"
		terminal_title_label.add_theme_color_override("font_color", Color("ffd15c"))
	elif rules.combat_mode:
		terminal_title_label.text = "YANSHAN · 普通行动 (单兵轮攻)"
		terminal_title_label.add_theme_color_override("font_color", MINT)
	else:
		terminal_title_label.text = "YANSHAN · 自由靶场（纯训练）"
		terminal_title_label.add_theme_color_override("font_color", MINT)

func start_action(as_combat = false, op_tier: String = "normal"):
	var is_prologue_req: bool = (op_tier == "prologue")
	var eff_combat: bool = as_combat and not is_prologue_req
	var same_active_run: bool = (rules.phase in ["active", "extracting"]) and (bool(rules.combat_mode) == eff_combat) and (rules.operation_tier == op_tier)
	if not same_active_run:
		if rules.phase in ["active", "extracting"]:
			_end_run(false, "切换行动")
		run_started_ms = Time.get_ticks_msec()
		review_button.hide()
		review_overlay.hide()
		armory_panel.hide()
		if is_instance_valid(settings_panel):
			settings_panel.hide()
		tutorial_moved = false
		_leave_station()
		rules.start_run(eff_combat, op_tier)
		if is_instance_valid(prologue) and not is_prologue_req:
			prologue.set_active(false)
		exploration.reset()
		if is_instance_valid(wildlife):
			wildlife.reset()
		if is_instance_valid(cave_warden):
			cave_warden.reset()
		if is_instance_valid(cipher_terminal):
			cipher_terminal.reset()
		if is_instance_valid(loot_container_ui):
			loot_container_ui.reset()
		if is_instance_valid(rangers):
			rangers.reset_for_run(eff_combat, is_prologue_req)
		player.medkits = rules.starter_medkits()
		player.grenades = rules.starter_grenades()
		player.stims = rules.starter_stims()
		player.stim_left = 0.0
		player.weapon_slot = 0
		time_left = 480.0
		next_question_left = 0.0
		station_prompt_timer_left = 0.0
		feedback_left = 0.0
		feedback_panel.hide()
		hitmarker_left = 0.0
		hitmarker_label.hide()
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
		player.reset_stance()
		player.yaw = 0.0
		player.pitch = 0.0
		player.ammo = rules.magazine()
		player.reserve_ammo = rules.starter_reserve_ammo()
		player.reload_left = 0.0
		player.cooldown = 0.0
		player.knife_cooldown = 0.0
		player.recoil = 0.0
		ammo_respawn_timers.clear()
		var ammo_crate_idx := 0
		for node in pickup_nodes:
			# v0.8.1 #15 & v0.8.2_dev2 D2-2: Practice/Prologue hide field supply loot boxes;
			# Combat selectively enables scarce ground ammo crates (6 Normal / 4 Confidential, with respawn cooldown).
			var enable_pickup: bool = eff_combat or (not is_prologue_req and node.has_meta("tactical_item"))
			if eff_combat and str(node.get_meta("tactical_item", "")) == "ammo_crate":
				if rules.is_confidential():
					enable_pickup = (ammo_crate_idx % 3 == 0)
				else:
					enable_pickup = (ammo_crate_idx % 2 == 0)
				ammo_crate_idx += 1
			Props.set_enabled(node, enable_pickup)
		if is_instance_valid(loot_ui):
			loot_ui.reset_run()
		if is_instance_valid(world_loot):
			world_loot.reset_for_run()
		for node in crate_nodes:
			Props.set_enabled(node, eff_combat)
			var tier = int(node.get_meta("tier"))
			node.get_child(node.get_child_count() - 1).modulate = _crate_accent(tier)
			if node.has_meta("lid_node") and is_instance_valid(node.get_meta("lid_node")):
				node.get_meta("lid_node").rotation.x = 0.0
		for child in player.weapon_root.get_children():
			child.queue_free()
		player.weapon_view = attach_weapon(player.weapon_root)
		if eff_combat:
			combat.begin()
		else:
			combat.stop()
			if not is_prologue_req:
				_next_question()
	if is_instance_valid(loot_ui):
		loot_ui.close_all_modals()
	paused = false
	get_viewport().gui_release_focus()
	player.clear_movement_input()
	player.active = true
	player.camera.fov = 75
	menu.hide()
	hud.show()
	combat_panel.show()
	_refresh_terminal_title()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _pick_smart_distractors(target: Dictionary, desired_count: int = 4) -> Array:
	var target_en: String = target.english.strip_edges()
	var target_is_phrase: bool = target.get("kind", "word") == "phrase" or (" " in target_en)
	var target_proper: bool = bool(target.get("proper_name", false))
	var target_first: String = target_en.substr(0, 1).to_lower()
	var target_len: int = target_en.length()
	var target_unit: int = int(target.get("unit", 0))

	var scored = []
	var source = pool if pool.size() >= desired_count else words
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
		if picked.size() == desired_count:
			break
	return picked

func flash_word_switch_banner():
	word_switch_flash = 0.48
	if is_instance_valid(question_panel):
		var st = question_panel.get_theme_stylebox("panel")
		if st is StyleBoxFlat:
			st.border_color = Color("ffd86b")
			st.set_border_width_all(2)

func _next_question():
	question_help_used = false
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
	listening_mode = (has_english_voice(str(question.get("english", ""))) and rules.answered >= 4 and rules.answered % 5 == 0)
	rules.open_question()
	next_question_left = 0.0
	station_prompt_timer_max = 10.0
	station_prompt_timer_left = station_prompt_timer_max if active_station >= 0 else 0.0
	_sync_question()
	if active_station >= 0:
		flash_word_switch_banner()
		if (listening_mode or bool(rules.setting("auto_speak_on_switch", true))) and not paused:
			speak_english(str(question.get("english", "")))
	elif listening_mode and not paused and not (combat.in_field() and combat.zone < 0):
		speak_english(str(question.get("english", "")))

func _sync_question():
	if combat.in_field() and combat.zone >= 0:
		combat.show_question()
		return
	if active_station < 0:
		if combat.in_field():
			combat.show_question()
		else:
			question_label.text = "靠近绿色终端，按 [F] 启动识词靶场"
			if is_instance_valid(cloze_label):
				cloze_label.text = ""
			unit_label.text = "A 山脚营地 → 林间前哨 → B 竹林撤离点  |  自由探索与识词"
		return
	for i in choices.size():
		_fit_word(targets[i], choices[i].english)
		target_materials[i].albedo_color = Color("182e30")
	if listening_mode and rules.question_open:
		question_label.text = "🔊 听音辨词挑战 · 按 [X] 重播读音"
		if is_instance_valid(cloze_label):
			cloze_label.text = ""
	else:
		question_label.text = question.chinese
		if is_instance_valid(cloze_label):
			var cloze := cloze_for_word(str(question.get("id", "")))
			cloze_label.text = ("教材语境：%s  (p.%d)" % [cloze.cloze_text, int(cloze.textbook_page)]) if not cloze.is_empty() else ""
	unit_label.text = "%s · Unit %d · 第 %d 页  |  [X] 听标准发音" % [stations[active_station].title, question.unit, question.textbook_page]
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
	stations[index].set_boards_visible(true)
	targets = stations[index].targets
	target_materials = stations[index].materials
	var rolled_fresh := false
	if choices.is_empty() or not rules.question_open:
		_next_question()
		rolled_fresh = true
	station_prompt_timer_max = 10.0
	station_prompt_timer_left = station_prompt_timer_max if rules.question_open else 0.0
	_sync_question()
	if not rolled_fresh and not question.is_empty():
		flash_word_switch_banner()
		if (listening_mode or bool(rules.setting("auto_speak_on_switch", true))) and not paused:
			speak_english(str(question.get("english", "")))
	_notice(stations[index].title + " · 看中文或听读音射击对应英文靶牌（按 X 重听发音）", MINT)

func _leave_station():
	if active_station >= 0:
		stations[active_station].clear()
	active_station = -1
	station_prompt_timer_left = 0.0
	targets = []
	target_materials = []
	_sync_question()

func _interaction_position(node: Node3D) -> Vector3:
	return node.global_position + (Vector3(2, 0, 2) if node.has_meta("station_id") else Vector3.ZERO)

func _can_interact(node: Node3D) -> bool:
	if node.has_meta("world_loot_kind"):
		return true
	var endpoint = _interaction_position(node) + Vector3(0, 0.6, 0)
	var query = PhysicsRayQueryParameters3D.create(player.camera.global_position, endpoint, 3, [player.get_rid()])
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == node or node.is_ancestor_of(hit.collider)

func show_hitmarker(is_crit: bool = false):
	hitmarker_left = 0.22
	hitmarker_label.text = "✦" if is_crit else "×"
	hitmarker_label.add_theme_color_override("font_color", GOLD if is_crit else MINT)
	hitmarker_label.show()

func use_ranger_skill() -> bool:
	if rules.phase not in ["active", "extracting"] or paused:
		return false
	if is_instance_valid(rangers):
		return rangers.activate_skill()
	return false

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
		_notice("已投掷训练烟雾/EMP 手雷（实战中可瘫痪雾隐帮词兵与古洞循音石卫）", Color("7ceeff"))
	if is_instance_valid(cave_warden):
		cave_warden.on_smoke_emp(target)

func fire(camera: Camera3D):
	if rules.phase != "active" or paused:
		return
	rules.shots += 1
	var shooting_field = combat.in_field() and (combat.zone >= 0 or active_station < 0)
	var from = camera.global_position
	var to = from - camera.global_basis.z * 155.0
	var query = PhysicsRayQueryParameters3D.create(from, to, 7 if shooting_field else 3, [player.get_rid()])
	query.collide_with_areas = shooting_field
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if is_instance_valid(prologue) and prologue.active:
		var pq := PhysicsRayQueryParameters3D.create(from, to, 1 | prologue.HIT_LAYER, [player.get_rid()])
		pq.collide_with_areas = true
		var phit := get_world_3d().direct_space_state.intersect_ray(pq)
		if phit and phit.collider is Area3D:
			if result.is_empty() or from.distance_to(phit.position) <= from.distance_to(result.position) + 0.05:
				if prologue.hit_bullet(phit.collider):
					return
	if is_instance_valid(cave_warden) and cave_warden.is_mode_active():
		cave_warden.on_gunshot(player.position, rules.active_muzzle() == "suppressor")
		var cwq := PhysicsRayQueryParameters3D.create(from, to, 1 | CaveWarden.HIT_LAYER, [player.get_rid()])
		cwq.collide_with_areas = true
		var cwhit := get_world_3d().direct_space_state.intersect_ray(cwq)
		if cwhit and cwhit.collider is Area3D:
			if result.is_empty() or from.distance_to(cwhit.position) <= from.distance_to(result.position) + 0.05:
				if cave_warden.hit_bullet(cwhit.collider):
					return
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
	# v0.8.2_dev1: Camp Station 0 warm-up during Combat Operations MUST NOT contaminate combat score, answered/correct, or extraction accuracy!
	var camp_warmup_in_combat: bool = (not mobile and combat.in_field())
	if camp_warmup_in_combat:
		if rules.phase != "active" or not rules.question_open:
			return
		rules.question_open = false
		var wid_w := str(question.get("id", ""))
		if wid_w != "":
			rules.learning.record_recognition(wid_w, correct, choices.size(), question_help_used, -1, "camp_warmup", "listening" if listening_mode else "recognition")
	else:
		var rec_scene := "combat_word" if mobile else "practice_station"
		var rec_mod := "listening" if listening_mode else "recognition"
		if not rules.answer(correct, str(question.get("id", "")), choices.size(), question_help_used, rec_scene, rec_mod):
			return
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
		if is_instance_valid(achievements):
			achievements.record_stat("best_streak", rules.streak, true)
		var streak_tag = (" · 🔥%d连击!" % rules.streak) if rules.streak >= 3 else ""
		if mobile and rules.streak >= 3 and combat.in_field():
			combat.heal(0, 6)
			streak_tag += "(+6盾)"
		if not (mobile and combat.zone >= 0 and combat.waves_done.get(combat.zone, 0) == combat.waves_target.get(combat.zone, -1)):
			_notice("命中正确！ +%d 分%s · %s（%s）" % [gained, streak_tag, question.english, question.chinese], MINT)
		if rules.correct % 3 == 0 and rules.can_loot():
			var chip_rarity = 3 if rules.streak >= 4 else 2
			rules.add_loot("战术知识芯片", 46 + maxi(0, rules.level() - 1) * 4, chip_rarity)
	else:
		var warning = "\n⚠ 敌方狂暴强化 7 秒 · 当前伤害 ×%.2f" % combat.damage_multiplier() if mobile else ""
		var cloze := cloze_for_word(str(question.get("id", "")))
		var example_line := ("\n例句：%s (p.%d)" % [cloze.english, int(cloze.textbook_page)]) if not cloze.is_empty() else ""
		_notice("正确答案：%s  —  %s%s%s" % [question.english, question.chinese, warning, example_line], Color("f5b995"))
		if question not in wrong_words:
			wrong_words.append(question)

	screen_flash.color = Color(0.3, 1, 0.65, 0.08) if correct else Color(1, 0.35, 0.2, 0.09)
	station_prompt_timer_left = 0.0
	next_question_left = 1.15 if correct else 1.40
	unit_label.text = "已结算 · 即将切换新题"

func _notice(text: String, color = GOLD):
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_left = 3.4

func _refresh_bag_pills():
	var sig_parts = [str(rules.capacity()), str(rules.safe_box.size())]
	for item in rules.safe_box:
		sig_parts.append("S:%s:%d:%d" % [item.title, int(item.value), int(item.get("rarity", 1))])
	for item in rules.bag:
		sig_parts.append("%s:%d:%d" % [item.title, int(item.value), int(item.get("rarity", 1))])
	var sig = "|".join(sig_parts)
	if sig == bag_signature:
		return
	bag_signature = sig
	for child in bag_slots_box.get_children():
		child.queue_free()
	if rules.bag.is_empty() and rules.safe_box.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "序章任务：按 [J] 重温对话与英文线索，无物资压力！" if rules.prologue_mode else ("搜刮盲盒物资箱/草丛桥角秘藏（按 [B] 存入安全箱！）" if rules.can_loot() else "自由靶场纯训练：无物资掉落，按 [F] 开靶牌练识词！")
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color("89a89b"))
		bag_slots_box.add_child(empty_lbl)
		return
	var shown_list: Array = []
	for sit in rules.safe_box:
		shown_list.append({"item": sit, "safe": true})
	for bit in rules.bag:
		shown_list.append({"item": bit, "safe": false})
	for wrap in shown_list:
		var item: Dictionary = wrap.item
		var is_safe: bool = wrap.safe
		var r = clampi(int(item.get("rarity", 1)), 1, Rules.MAX_RARITY)
		var col: Color = Rules.RARITY_COLORS[r]
		var pill = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.24, 0.04, 0.07, 0.95) if r == 7 else Color(col.r * 0.17, col.g * 0.17, col.b * 0.19, 0.92)
		st.border_color = Color("ffd46e") if is_safe else col
		st.set_border_width_all(2 if (r >= 5 or is_safe) else 1)
		st.set_corner_radius_all(4)
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		pill.add_theme_stylebox_override("panel", st)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl = Label.new()
		var prefix = ("🔒" if is_safe else "") + ("🔥" if r == 7 else ("✦" if r == 6 else ("◆" if r == 5 else "")))
		lbl.text = prefix + str(item.title)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", col)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(lbl)
		bag_slots_box.add_child(pill)

func _process(delta):
	render_age += delta
	camp_display_clock += delta
	if is_instance_valid(achievements):
		achievements.update(delta)
	if is_instance_valid(rangers):
		rangers.update(delta)
	if is_instance_valid(cave_warden):
		cave_warden.update(delta)
	if is_instance_valid(prologue) and prologue.active:
		prologue.update(delta)
	if not camp_display_slots.is_empty():
		for slot in camp_display_slots:
			var mount: Node3D = slot.mount
			if is_instance_valid(mount) and mount.get_child_count() > 0:
				mount.rotation.y = camp_display_clock * 0.85
	if not is_instance_valid(player) or not is_instance_valid(stat_label):
		return
	if paused:
		return
	exploration.update(delta)
	if is_instance_valid(wildlife):
		wildlife.update(delta)
	if is_instance_valid(world_loot):
		world_loot.update(delta)
	combat.update(delta)
	if active_station >= 0 and player.position.distance_to(stations[active_station].position) > 15:
		_leave_station()
	if rules.phase in ["active", "extracting"] and not rules.prologue_mode:
		time_left -= delta
		if time_left <= 0:
			_end_run(false)
			return
	if rules.phase == "active" and next_question_left > 0 and not (combat.in_field() and combat.zone >= 0):
		next_question_left -= delta
		if next_question_left <= 0:
			_next_question()
	elif rules.phase == "active" and active_station >= 0 and rules.question_open and not (combat.in_field() and combat.zone >= 0) and not (is_instance_valid(exploration) and exploration.safe()):
		station_prompt_timer_left = maxf(0.0, station_prompt_timer_left - delta)
		if station_prompt_timer_left <= 0.0:
			_next_question()
			_notice("⏱ 靶场题目超时自动轮换新词！", Color("9cd6f0"))
	_update_prompt_timer_bar()
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

	if word_switch_flash > 0.0:
		word_switch_flash = maxf(0.0, word_switch_flash - delta)
		if is_instance_valid(question_panel):
			var qst = question_panel.get_theme_stylebox("panel")
			if qst is StyleBoxFlat:
				var f_t := clampf(word_switch_flash / 0.48, 0.0, 1.0)
				qst.border_color = Color(0.55, 0.90, 0.74, 0.55).lerp(Color("ffd86b"), f_t)
				qst.set_border_width_all(2 if f_t > 0.25 else 1)

	if rules.combat_mode and not ammo_respawn_timers.is_empty():
		var ready_crates: Array = []
		for crate_n in ammo_respawn_timers.keys():
			if not is_instance_valid(crate_n):
				ready_crates.append(crate_n)
				continue
			var rem_t: float = float(ammo_respawn_timers[crate_n]) - float(delta)
			if rem_t <= 0.0:
				Props.set_enabled(crate_n, true)
				ready_crates.append(crate_n)
			else:
				ammo_respawn_timers[crate_n] = rem_t
		for done_c in ready_crates:
			ammo_respawn_timers.erase(done_c)

	crosshair_label.text = "◆" if player.weapon_slot == 1 else "+"
	crosshair_label.visible = not (player.aiming and player.weapon_slot == 0)

	var streak_str = ("  🔥×%d" % rules.streak) if rules.streak >= 3 else ""
	fps_label.text = "%d FPS" % Engine.get_frames_per_second() if render_age > 1.5 else "预热中"
	_refresh_terminal_title()
	if rules.prologue_mode and is_instance_valid(prologue) and prologue.active:
		stat_label.text = "烟山初行 · 斥候 %d/%d | 线索 %s" % [prologue.scouts_cleared, prologue.scouts.size(), "已解开" if prologue.clue_solved else "待查验"]
		mission_label.text = "单人序章 · 备弹无限 · [J] 重查任务与英文线索\n[Esc] 可随时调减震动、独立音量与鼠标灵敏度"
		question_label.text = prologue.current_objective_text()
		if is_instance_valid(cloze_label):
			cloze_label.text = ""
		unit_label.text = prologue.current_subhint_text()
	elif rules.combat_mode:
		stat_label.text = "积分 %03d/%d  |  正确率 %d%%  |  %02d:%02d%s" % [
			rules.score, Rules.EXTRACTION_SCORE, roundi(rules.accuracy() * 100), int(time_left) / 60, int(time_left) % 60, streak_str
		]
		var outpost_part = "营地 %d/6(需2) · 密钥 %d/1" % [rules.outposts_cleared, 1 if rules.boss_defeated else 0]
		var extract_part = "信标已就绪" if rules.can_extract() else _extraction_blocker_short()
		var eco_part = wildlife.status_badge() if is_instance_valid(wildlife) else "生灵 0/8 · 奇植 0/8"
		mission_label.text = "%s · 箱 %d/%d · 撤离：%s\n%s · %s" % [
			outpost_part, rules.crates.size(), crate_nodes.size(), extract_part, exploration.status_text(), eco_part
		]
	else:
		# Clean Practice Range HUD: pure word/shooting practice without distracting combat timers or extraction gaps!
		stat_label.text = "已答 %d 题  |  正确率 %d%%  |  积分 %d%s" % [
			rules.answered, roundi(rules.accuracy() * 100), rules.score, streak_str
		]
		var eco_part_p = wildlife.status_badge() if is_instance_valid(wildlife) else "生灵 0/8 · 奇植 0/8"
		mission_label.text = "自由靶场 · 纯识词练枪（无物资 / 无首领 / 无战绩成就）\n%s · %s" % [
			exploration.status_text(), eco_part_p
		]
	_update_guide()
	_update_combat_hud()

	if rules.prologue_mode:
		bag_label.text = "序章行囊 · 专注路线、识词与望稻亭信标调查 [J]"
	elif rules.can_loot():
		bag_label.text = "背包 %d/%d · 🔒安全箱 %d/%d · %d币 [B] [I]" % [rules.bag.size(), rules.capacity(), rules.safe_box.size(), Rules.SAFE_BOX_SLOTS, rules.total_carried_value()]
	else:
		bag_label.text = "自由靶场 · 纯射击识词训练（不可搜集物资）"
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
	var active_tag = "[2] 战术匕首 (高移速 · 应急回弹)" if player.weapon_slot == 1 else "[1] YS-04 卡宾枪  |  [2] 匕首"
	var reserve_str = "∞" if player.has_infinite_ammo() else str(maxi(0, player.reserve_ammo))
	var ammo_line = "近战状态  ·  [左键/中键] 斩击（普通5刀/机密10刀回弹）" if player.weapon_slot == 1 else (
		"换弹装填中…" if player.reload_left > 0 else "弹药 %02d / 备弹 %s   [R]换弹" % [player.ammo, reserve_str]
	)
	var stim_suffix = ("  ⚡%.0fs" % player.stim_left) if player.stim_left > 0 else ""
	ammo_label.text = "%s\n%s\n%s\n[H]医疗×%d  [G]烟雾×%d  [T]能量×%d%s" % [
		active_tag, ammo_line, optic_tag, player.medkits, player.grenades, player.stims, stim_suffix
	]
	_update_ranger_skill_hud()
	_update_interaction()

func _update_ranger_skill_hud():
	if not is_instance_valid(skill_panel) or not is_instance_valid(rangers):
		return
	var ar: Dictionary = rangers.active_ranger()
	var cd_max: float = maxf(1.0, float(ar.skill_cooldown))
	var cd_left: float = float(rangers.skill_cooldown_left)
	var ready_now: bool = cd_left <= 0.001
	var frac: float = 1.0 if ready_now else clampf(1.0 - (cd_left / cd_max), 0.0, 1.0)
	skill_bar_fill.size.x = 284.0 * frac
	var st = skill_panel.get_theme_stylebox("panel")
	if ready_now:
		skill_label.text = "⚡ %s · [%s] %s · 就绪！" % [str(ar.name), str(ar.skill_key), str(ar.skill_name)]
		skill_label.add_theme_color_override("font_color", Color("ffd86b"))
		skill_bar_fill.color = Color("ffd15c")
		if st is StyleBoxFlat:
			st.border_color = Color("ffd15c")
			st.set_border_width_all(2)
	else:
		skill_label.text = "⏳ %s · [%s] %s · 冷却 %.1fs" % [str(ar.name), str(ar.skill_key), str(ar.skill_name), cd_left]
		skill_label.add_theme_color_override("font_color", Color("9cd8e8"))
		skill_bar_fill.color = Color("56d8ff")
		if st is StyleBoxFlat:
			st.border_color = Color(0.38, 0.72, 0.78, 0.55)
			st.set_border_width_all(1)

func _update_prompt_timer_bar():
	if not is_instance_valid(prompt_timer_bg) or not is_instance_valid(prompt_timer_fill):
		return
	var left := 0.0
	var limit := 10.0
	var active_bar := false
	if combat.in_field() and (combat.zone >= 0 or combat.preview_zone >= 0) and combat.prompt_reveal_left <= 0.0 and combat.prompt_timer_left > 0.0:
		left = combat.prompt_timer_left
		limit = maxf(1.0, combat.prompt_timer_max)
		active_bar = true
	elif active_station >= 0 and rules.question_open and station_prompt_timer_left > 0.0 and next_question_left <= 0.0:
		left = station_prompt_timer_left
		limit = maxf(1.0, station_prompt_timer_max)
		active_bar = true
	prompt_timer_bg.visible = active_bar
	prompt_timer_fill.visible = active_bar
	if active_bar:
		var frac := clampf(left / limit, 0.0, 1.0)
		prompt_timer_fill.size.x = 502.0 * frac
		prompt_timer_fill.color = Color("ff5c66") if left <= 2.8 else (GOLD if left <= 5.0 else MINT)

func _extraction_blocker_short() -> String:
	if rules.score < Rules.EXTRACTION_SCORE:
		return "差%d分" % (Rules.EXTRACTION_SCORE - rules.score)
	if rules.combat_mode and not rules.boss_defeated:
		return "需败B区首领"
	if rules.combat_mode and rules.outposts_cleared < 2:
		return "需攻克%d/2哨" % rules.outposts_cleared
	if rules.combat_mode and not rules.accuracy_gate_met():
		return "正确率需≥%d%%" % roundi(rules.required_extract_accuracy() * 100)
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
	if rules.prologue_mode and is_instance_valid(prologue) and prologue.active:
		guide_label.text = "[J] 打开任务记录与英文线索  ·  [X] 听读音  ·  [Esc] 舒适设置"
	elif rules.can_extract():
		guide_label.text = "★ 撤离条件已全达标！前往B点绿色信标按 [F] 坚守5秒"
	elif combat.in_field() and combat.zone == 2 and is_instance_valid(combat.boss_unit) and not combat.boss_unit.defeated:
		guide_label.text = "首领战：破词盾露核心，[G]烟雾可致盲躲红圈"
	elif combat.in_field() and combat.zone >= 0:
		guide_label.text = "正确词兵：爆头1枪秒 / 词盾2枪灭 · [V]天生神力震倒周围词兵"
	elif combat.in_field():
		var b_str: String = rangers.bounty_hud_line() if is_instance_valid(rangers) else ""
		guide_label.text = ("%s · [V]天生神力震地 · 靠近6处敌营开战" % b_str) if b_str != "" else "靠近6处敌营触发波次仇恨 · [V]天生神力震地 · 护盾靠[H/T]恢复"
	elif not tutorial_moved and active_station < 0:
		guide_label.text = "按 [F] 开启身旁营地终端，或沿山路探索"
	else:
		guide_label.text = "看中文射英文 · 答对+%d分 · 3连击额外+%d分" % [Rules.BASE_ANSWER_SCORE, Rules.STREAK_BONUS_SCORE]

func _update_combat_hud():
	if combat.in_field():
		var max_sh = maxf(1.0, float(rules.max_shield()))
		shield_bar_fill.size.x = 316.0 * clampf(float(combat.shield) / max_sh, 0.0, 1.0)
		hp_bar_fill.size.x = 316.0 * clampf(float(combat.health) / float(Combat.MAX_HEALTH), 0.0, 1.0)
		hp_bar_fill.color = Color("6ae3a8") if combat.health > 55 else (Color("f4ca64") if combat.health > 28 else Color("ff5c66"))
		var threats = combat.active_threat_count()
		if combat.rage_hunt_left > 0.0:
			threat_banner.show()
			threat_label.text = "🔥 狂暴围剿 %.1fs · 敌营全员强袭 · 敌伤 ×%.1f！" % [combat.rage_hunt_left, combat.damage_multiplier()]
		elif threats > 0:
			threat_banner.show()
			threat_label.text = "⚠ 敌方火力锁定 · 冲刺跑跳或隐蔽掩体！"
		else:
			threat_banner.hide()
		var stance_txt: String = player.stance_label() if is_instance_valid(player) else "站立"
		var alert_tag = ("🔥狂暴×%.1f" % combat.damage_multiplier()) if combat.rage_hunt_left > 0.0 else ("烟雾隐蔽!" if combat.player_in_smoke() else ("闪避成功!" if combat.miss_left > 0 else ("敌攻×%.2f" % combat.damage_multiplier() if combat.wave_wrong_stacks > 0 else ("受瞄×%d" % threats if threats > 0 else "警戒中"))))
		combat_label.text = "HP %d · 盾 %d/%d · %s · %s" % [combat.health, roundi(combat.shield), rules.max_shield(), stance_txt, alert_tag]
	else:
		threat_banner.hide()
		shield_bar_fill.size.x = 316.0
		hp_bar_fill.size.x = 316.0
		hp_bar_fill.color = Color("6ae3a8")
		var stance_p: String = player.stance_label() if is_instance_valid(player) else "站立"
		combat_label.text = ("烟山初行·单人序章  ·  无限备弹  ·  姿态：" if rules.prologue_mode else "自由靶场模式  ·  无限备弹  ·  姿态：") + stance_p

func _extraction_blocker_text() -> String:
	var missing := []
	if rules.score < Rules.EXTRACTION_SCORE:
		missing.append("还差 %d 积分（%d/%d）" % [Rules.EXTRACTION_SCORE - rules.score, rules.score, Rules.EXTRACTION_SCORE])
	if rules.combat_mode and rules.outposts_cleared < 2:
		missing.append("需攻克至少 2 处前哨（%d/2）" % rules.outposts_cleared)
	if rules.combat_mode and not rules.boss_defeated:
		missing.append("需击败 B 区首领夺取密钥")
	if rules.combat_mode and not rules.accuracy_gate_met():
		missing.append("识词正确率需 ≥ %d%%（当前 %d%%）" % [roundi(rules.required_extract_accuracy() * 100), roundi(rules.accuracy() * 100)])
	return " · ".join(missing)

func _update_interaction():
	closest_interaction = null
	var nearest = 3.2
	if cached_interactables.is_empty():
		var eco_nodes: Array = wildlife.flora_nodes if is_instance_valid(wildlife) else []
		var wl_nodes: Array = world_loot.interactable_nodes() if is_instance_valid(world_loot) else []
		var npc_nodes: Array = [rangers.camp_npc_node] if (is_instance_valid(rangers) and is_instance_valid(rangers.camp_npc_node)) else []
		cached_interactables = pickup_nodes + crate_nodes + stations + exploration.nodes + eco_nodes + wl_nodes + npc_nodes
	for node in cached_interactables:
		if not is_instance_valid(node):
			continue
		if combat.in_field() and node.has_meta("station_id") and (combat.zone >= 0 or node != stations[0]):
			continue
		if not node.visible:
			continue
		var distance = player.position.distance_to(_interaction_position(node))
		if distance < nearest and _can_interact(node):
			closest_interaction = node
			nearest = distance

	if rules.prologue_mode and is_instance_valid(prologue) and prologue.active:
		var p_info: Dictionary = prologue.interaction_prompt_for(player.position)
		if not p_info.is_empty():
			interaction_panel.show()
			interaction_label.text = str(p_info.prompt)
		else:
			interaction_panel.show()
			interaction_label.text = "按 [J] 查看任务进度与英文线索 · 沿暖金路灯行进"
		return
	interaction_panel.show()
	if rules.phase == "extracting":
		interaction_label.text = "★ 撤离信标传输中 %.1f 秒 · 请留在光圈内！" % maxf(0, extraction_left)
	elif player.position.distance_to(exit_position) < 3.6:
		interaction_label.text = "[F] 启动战术撤离（坚守 5 秒）" if rules.can_extract() else ("撤离锁定 · " + _extraction_blocker_text())
	elif closest_interaction:
		if closest_interaction.has_meta("tactical_item"):
			var kind = str(closest_interaction.get_meta("tactical_item"))
			var title = str(closest_interaction.get_meta("title", "战术补给"))
			if kind == "ammo_crate":
				interaction_label.text = "[F] 搜刮 %s（+%d 备弹 · 上限%d）" % [title, rules.ground_ammo_gain(), rules.max_reserve_ammo()]
			elif kind == "smoke_emp":
				interaction_label.text = "[F] 拾取 %s（+1）" % title
			else:
				interaction_label.text = "[F] 拾取 %s（+1）" % title
		elif closest_interaction.has_meta("world_loot_kind") and is_instance_valid(world_loot):
			interaction_label.text = world_loot.prompt_for(closest_interaction)
		elif closest_interaction.has_meta("camp_bounty_npc"):
			interaction_label.text = "[F] 找陈向导查看游侠档案与烟山名望委托"
		elif closest_interaction.has_meta("flora_id"):
			var fid := str(closest_interaction.get_meta("flora_id"))
			var f_verb := "温习植物" if (is_instance_valid(wildlife) and wildlife.collected_flora.has(fid)) else "辨识奇植"
			interaction_label.text = "[F] %s · %s (%s)" % [f_verb, closest_interaction.get_meta("en"), closest_interaction.get_meta("zh")]
		elif closest_interaction.has_meta("explore_id"):
			if closest_interaction.has_meta("pending_items") and not (closest_interaction.get_meta("pending_items") as Array).is_empty():
				var rem_e: Array = closest_interaction.get_meta("pending_items")
				interaction_label.text = "[F] 查看奖励物资（已开启·剩余 %d 件） · %s" % [rem_e.size(), str(closest_interaction.get_meta("prompt"))]
			else:
				interaction_label.text = "[F] " + closest_interaction.get_meta("prompt")
		elif closest_interaction.has_meta("station_id"):
			interaction_label.text = "[F] 开启识词靶场 · " + closest_interaction.title
		elif closest_interaction.has_meta("tier"):
			var title = closest_interaction.get_meta("title")
			var tier = int(closest_interaction.get_meta("tier"))
			if closest_interaction.has_meta("pending_items") and not (closest_interaction.get_meta("pending_items") as Array).is_empty():
				var rem_c: Array = closest_interaction.get_meta("pending_items")
				interaction_label.text = "[F] 搜刮（已开启·剩余 %d 件） · %s" % [rem_c.size(), title]
			elif title in rules.crates:
				interaction_label.text = title + " · 已搜空"
			elif rules.crate_ready(tier):
				var mode_hint = "三重破译(词+词组+句)" if tier >= 3 else ("词组+短句破译" if tier == 2 else "单词+词组破译")
				interaction_label.text = "[F] %s · %s" % [mode_hint, title]
			else:
				interaction_label.text = title + " · " + _crate_progress(tier)
		else:
			var sup_title = str(closest_interaction.get_meta("title", "野外物资箱"))
			if closest_interaction.has_meta("pending_items") and not (closest_interaction.get_meta("pending_items") as Array).is_empty():
				var rem_s: Array = closest_interaction.get_meta("pending_items")
				interaction_label.text = "[F] 搜刮（已开启·剩余 %d 件） · %s" % [rem_s.size(), sup_title]
			else:
				interaction_label.text = "[F] 单词拼写开盲盒 · " + sup_title
	else:
		if rules.combat_mode:
			interaction_label.text = "B点撤离信标 %d m  ·  %s" % [
				roundi(player.position.distance_to(exit_position)),
				"已解锁可撤离" if rules.can_extract() else _extraction_blocker_short()
			]
		elif rules.can_extract():
			interaction_label.text = "靶场积分已达标 · 可前往 B 点信标 (%d m) 结束或按 [Esc] 返回" % roundi(player.position.distance_to(exit_position))
		else:
			interaction_label.text = "靠近绿色终端按 [F] 开靶牌练词 · 按 [Esc] 随时返回营地"

func interact():
	if rules.phase != "active" or paused:
		return
	if rules.prologue_mode and is_instance_valid(prologue) and prologue.active:
		if prologue.try_interact(player.position):
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
				var gain: int = rules.ground_ammo_gain()
				var cd: float = rules.ammo_crate_respawn_seconds()
				player.add_reserve_ammo(gain)
				ammo_respawn_timers[closest_interaction] = cd
				_notice("已补给 %s · 备弹 +%d（当前 %d/%d · %.0f秒后刷新）" % [title, gain, player.reserve_ammo, rules.max_reserve_ammo(), cd], GOLD)
		elif kind == "smoke_emp":
			player.grenades += 1
			_notice("拾取 %s · 按 [G] 投掷（当前 %d）" % [title, player.grenades], Color("7ceeff"))
		else:
			player.stims += 1
			_notice("拾取 %s · 按 [T] 使用（当前 %d）" % [title, player.stims], MINT)
		play_sfx("ammo_pickup", -10)
		Props.set_enabled(closest_interaction, false)
		return
	if closest_interaction.has_meta("camp_bounty_npc"):
		if is_instance_valid(rangers):
			rangers.open_npc_modal()
		return
	if closest_interaction.has_meta("world_loot_kind"):
		if is_instance_valid(world_loot):
			world_loot.interact(closest_interaction)
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
	if rules.phase not in ["active", "extracting"]:
		return
	var pre_wh = rules.profile.warehouse.size()
	var carried_value = rules.total_carried_value()
	var safe_val_before = rules.safe_box_value()
	var defeated_boss: bool = rules.boss_defeated
	if success:
		if not rules.finish_extraction():
			return
		play_sfx("loot_epic", -10)
	else:
		rules.abandon()
	var duration := maxf(0.0, (Time.get_ticks_msec() - run_started_ms) / 1000.0) if run_started_ms >= 0 else 0.0
	run_started_ms = -1
	var due_now := _pending_retest().size()
	rules.profile.last_run = {
		"wall_clock_seconds": duration,
		"mode": rules.mode_label(),
		"extracted": success,
		"nemesis_cleared": rules.nemesis_cleared,
		"due_remaining": due_now
	}
	var saved := _save()
	if is_instance_valid(achievements) and int(rules.profile.get("red_extracted", 0)) > 0:
		achievements.record_stat("red_extracted", int(rules.profile.get("red_extracted", 0)), true)
	var banked_count = rules.profile.warehouse.size() - pre_wh
	var safe_saved_count: int = rules.last_saved_safe_box_count
	if is_instance_valid(prologue) and prologue.active:
		prologue.set_active(false)
	rules.prologue_mode = false
	refresh_camp_display_stand()
	combat.stop()
	if is_instance_valid(cipher_terminal) and cipher_terminal.busy:
		cipher_terminal.reset()
	if is_instance_valid(loot_container_ui) and loot_container_ui.busy:
		loot_container_ui.reset()
	if is_instance_valid(rangers) and rangers.busy:
		rangers.close_npc_modal()
	if is_instance_valid(loot_ui):
		loot_ui.reset_run()
	paused = true
	player.clear_movement_input()
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show()
	hud.hide()
	_refresh_menu(title if title != "" else ("成功撤离！" if success else "行动结束"))
	review_button.visible = not wrong_words.is_empty()
	var mode_badge: String = "【%s%s】" % [rules.mode_label(), "·估值×1.35" if rules.is_confidential() else ""]
	var header := ""
	if success:
		header = "%s 带回 %d 件物资（总估值 %d 币）！可在「我的仓库」单件出售或锁存展陈。\n" % [mode_badge, banked_count, carried_value]
	elif safe_saved_count > 0:
		header = "%s 随身背包遗留烟山，但 🔒 安全箱成功保住 %d 件重宝（%d 币）入库！\n" % [mode_badge, safe_saved_count, safe_val_before]
	else:
		header = "%s 本局已结束，学习记录已整理入档。\n" % mode_badge
	var ind_cnt: int = rules.learning.run_independent
	var ast_cnt: int = rules.learning.run_assisted
	menu_summary.text = header + "挑战战绩 %d/%d（%d%%）· 最高 %d 连击 | 独立答对 %d · 提示/练习 %d · 下次待练 %d\n" % [
		rules.correct, rules.answered, roundi(rules.accuracy() * 100), rules.best_streak, ind_cnt, ast_cnt, due_now
	]
	menu_summary.text += "实际用时 %d 分 %02d 秒 · 宿敌攻克 %d 词 · 营地 %d/6 · 首领%s · 完美开箱 %d" % [
		int(duration) / 60, int(duration) % 60, rules.nemesis_cleared, rules.outposts_cleared, "已败" if defeated_boss else "未败", rules.perfect_ciphers
	]
	if wrong_words.size() > 0:
		menu_status.text = "本局有 %d 条错词或借助提示的题目。" % wrong_words.size()
	else:
		menu_status.text = ""
	if not saved:
		menu_summary.text = "⚠ 警告：存档写入失败（" + (last_save_error if last_save_error != "" else "请检查磁盘/权限") + "），本次进度暂未持久化！\n" + menu_summary.text
		menu_status.text = "本局记录暂未写入存档。请检查存档位置与写入权限。"

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var is_esc = (code == KEY_ESCAPE)
		if is_instance_valid(loot_ui) and loot_ui.any_modal_open():
			if is_esc:
				loot_ui.close_all_modals()
				get_viewport().set_input_as_handled()
				return
			if code == KEY_B and loot_ui.busy_bag:
				loot_ui.close_backpack()
				get_viewport().set_input_as_handled()
				return
			if code == KEY_I and loot_ui.busy_inspect:
				loot_ui.close_inspect()
				get_viewport().set_input_as_handled()
				return
		if is_instance_valid(prologue) and prologue.busy and is_esc:
			prologue.close_modal()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(loot_container_ui) and loot_container_ui.busy and is_esc:
			loot_container_ui.close()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(cipher_terminal) and cipher_terminal.busy and is_esc:
			cipher_terminal.close()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(rangers) and rangers.busy and is_esc:
			rangers.close_npc_modal()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(exploration) and exploration.busy and is_esc:
			exploration.close()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(settings_panel) and settings_panel.visible and is_esc:
			settings_panel.hide()
			get_viewport().set_input_as_handled()
			return
		if is_esc and rules.phase in ["active", "extracting"]:
			if paused:
				start_action(rules.combat_mode, rules.operation_tier)
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
