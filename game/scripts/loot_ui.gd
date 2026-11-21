extends Node
## v0.8.0 Museum-Grade Extraction Looting & Vault Showcase UI:
## - 64 unique Blender 4.5 Cycles studio-rendered 256x256 RGBA item icons (7-tier rarity T1..T7)
## - 64 unique sculpted multi-material PBR 3D collectibles from assets/slice/v072_collectibles.glb
## - HUD Tactile Quick-Search bar & '出大红/出大金/出小金' Jackpot Toast Banner
## - [B] Tactical Backpack + 2-Slot Encrypted Safe Box ('加密安全箱 · 阵亡不掉落')
## - Camp & Settlement Warehouse Vault Manager (Single-Sell, Lock/Unlock, Sell Junk, 4-Slot 3D Display Stand)
## - [I] Interactive 360° Mouse-Drag & Zoom 3D Relic Showcase Inspector + 64-Item Bilingual Compendium

const COLLECTIBLE_GLB := "res://assets/slice/v072_collectibles.glb"
const ICON_DIR := "res://assets/icons/loot/"

const TITLE_TO_ART_ID := {
	# T1 · 常规 (14)
	"旧巡护电池": "battery",
	"压缩干粮": "ration",
	"信号铜线": "wire",
	"诚庄春茶饼": "tea",
	"青竹编织哨": "bamboo",
	"粗陶米碗": "rice_bowl",
	"烟山野生核桃": "walnut",
	"老式木算盘": "abacus",
	"铁皮铅笔盒": "pencil_tin",
	"老竹尺": "bamboo_ruler",
	"干桂花香包": "osmanthus_pack",
	"旧黄铜钥匙串": "key_ring",
	"军绿旧水壶": "canteen",
	"尼龙登山绳": "rope_coil",
	# T2 · 精良 (12)
	"林间指北针": "compass",
	"防水战术手电": "torch",
	"巡护员徽章": "badge",
	"烟山手工折扇": "fan",
	"溪石萤光矿": "gem",
	"朱漆首饰匣": "lacquer_box",
	"青花品茗杯": "blue_teacup",
	"工兵折叠铲": "folding_shovel",
	"信号发烟罐": "smoke_can",
	"湖笔书写套组": "brush_set",
	"铜制电报发报键": "morse_key",
	"烟山草药标本匣": "herb_case",
	# T3 · 稀有 (11)
	"加密无线电台": "radio",
	"光学测距模块": "rangefinder",
	"古树琥珀标本": "amber",
	"军规夜视镜片": "nvg_lens",
	"太湖透漏赏石": "rock",
	"军用双筒望远镜": "binoculars",
	"雕花黄铜墨盒": "ink_box",
	"松烟鎏金古墨锭": "inkstick",
	"江南苏绣锦囊": "silk_pouch",
	"便携气象测风仪": "anemometer",
	"机械铜壳怀表": "pocket_watch",
	# T4 · 史诗 (10)
	"无人机核心芯片": "chip",
	"竹海古玉残片": "jade_piece",
	"军用黑匣子": "blackbox",
	"烟霞岩画残拓": "rubbing",
	"古樟祈福银锁": "silver_lock",
	"先民青铜茶铫": "kettle",
	"鎏金点翠银簪": "hairpin",
	"青瓷蟾蜍水注": "water_dropper",
	"微光瞄具光学核": "optic_core",
	"端溪雕云古砚": "inkstone",
	# T5 · 珍品·小金 (6)
	"海兽葡萄错银铜镜": "bronze_mirror",
	"战备量子加密硬盘": "crypto_drive",
	"宜兴朱泥水平壶": "zisha_teapot",
	"翡翠节节高玉佩": "jade_pendant",
	"复古黄铜旁轴相机": "vintage_camera",
	"御窑青花缠枝盏": "imperial_bowl",
	# T6 · 传说·大金 (6)
	"烟山古铜虎符": "tally",
	"特级金质勋章": "medal",
	"量子词典原型机": "quantum",
	"烟山先民竹简": "slips",
	"烟山统领黄金核心": "core",
	"望稻亭鎏金香炉": "censer",
	# T7 · 旷世·大红 (5)
	"越窑秘色青瓷盏": "celadon",
	"烟山千年紫芝王": "ganoderma",
	"诚庄先民双龙玉璧": "jade_bi",
	"相控阵超算雷达心": "radar_heart",
	"烟山之心·赤金龙印": "seal"
}

const LEGACY_ICON_ALIAS := {
	"lens": "rangefinder",
	"jade": "jade_bi"
}

static var _mesh_cache: Dictionary = {}
static var _glb_loaded: bool = false
static var _icon_cache: Dictionary = {}


static func all_collectible_art_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in TITLE_TO_ART_ID.values():
		out.append(str(k))
	return out


static func resolve_art_id(item_or_kind) -> String:
	if item_or_kind is Dictionary:
		var title := str(item_or_kind.get("title", ""))
		if TITLE_TO_ART_ID.has(title):
			return str(TITLE_TO_ART_ID[title])
		var raw := str(item_or_kind.get("icon", "core"))
		return str(LEGACY_ICON_ALIAS.get(raw, raw))
	var s := str(item_or_kind)
	if TITLE_TO_ART_ID.has(s):
		return str(TITLE_TO_ART_ID[s])
	return str(LEGACY_ICON_ALIAS.get(s, s))


static func load_collectible_icon(item_or_kind) -> Texture2D:
	var art_id := resolve_art_id(item_or_kind)
	if _icon_cache.has(art_id):
		return _icon_cache[art_id]
	var path := ICON_DIR + art_id + ".png"
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			_icon_cache[art_id] = tex
			return tex
	return null


static func _collect_meshes_recursive(node: Node):
	if node is MeshInstance3D and node.mesh != null:
		var nm := str(node.name)
		if nm.begins_with("loot_"):
			var art_id := nm.substr(5)
			_mesh_cache[art_id] = node.mesh
	for ch in node.get_children():
		_collect_meshes_recursive(ch)


static func _ensure_collectible_meshes():
	if _glb_loaded:
		return
	_glb_loaded = true
	if not ResourceLoader.exists(COLLECTIBLE_GLB):
		return
	var packed = load(COLLECTIBLE_GLB)
	if packed is PackedScene:
		var inst: Node = packed.instantiate()
		_collect_meshes_recursive(inst)
		inst.free()


static func get_collectible_mesh(item_or_kind) -> Mesh:
	_ensure_collectible_meshes()
	var art_id := resolve_art_id(item_or_kind)
	if _mesh_cache.has(art_id):
		return _mesh_cache[art_id]
	if _mesh_cache.has("core"):
		return _mesh_cache["core"]
	return null


var game
var busy_bag: bool = false
var busy_inspect: bool = false
var busy_compendium: bool = false
var busy_warehouse: bool = false
var inspect_return_to: String = ""

# Top-center Jackpot Toast Banner
var toast_panel: Panel
var toast_icon_holder: Control
var toast_header: Label
var toast_name: Label
var toast_sub: Label
var toast_left: float = 0.0
var toast_rarity: int = 1

# Center Tactile Quick-Search Bar (Hidden Nooks & Bird Nests)
var search_panel: Panel
var search_label: Label
var search_bar_fill: ColorRect
var active_search_node: Node3D = null
var search_elapsed: float = 0.0
var search_duration: float = 0.92

# [B] Tactical Backpack + 2-Slot Encrypted Safe Box Modal
var bag_overlay: Control
var bag_header_label: Label
var safe_box_header_label: Label
var safe_box_row: HBoxContainer
var bag_grid: GridContainer
var bag_status_label: Label

# Camp & Settlement Warehouse Vault Modal ('烟山战利品收藏库')
var wh_overlay: Control
var wh_stats_label: Label
var wh_status_label: Label
var wh_grid: GridContainer
var wh_sell_junk_btn: Button
var wh_filter_mode: String = "all" # "all" | "high" | "locked" | "junk"
var wh_filter_buttons: Dictionary = {}

# [I] Interactive 360° 3D Relic Showcase Inspector
var inspect_overlay: Control
var inspect_title: Label
var inspect_en_label: Label
var inspect_meta_label: Label
var inspect_lore_label: Label
var inspect_icon_holder: Control
var inspect_vp_frame: Panel
var inspect_vp: SubViewport
var inspect_cam: Camera3D
var inspect_rim_light: OmniLight3D
var inspect_turntable: Node3D
var inspect_spin_btn: Button
var inspect_item_data: Dictionary = {}
var inspect_auto_spin: bool = true
var inspect_dragging: bool = false
var inspect_yaw: float = 0.35
var inspect_pitch: float = 0.24
var inspect_cam_dist: float = 1.62

# Camp Bilingual Treasure Compendium & Achievements/Charms Hall ('烟山奇珍图鉴')
var comp_overlay: Control
var comp_stats_label: Label
var comp_grid: GridContainer
var comp_tab := "relics"
var comp_tab_relics_btn: Button
var comp_tab_ach_btn: Button


func setup(g):
	game = g
	_build_toast_and_search_hud()
	_build_backpack_modal()
	_build_warehouse_modal()
	_build_inspect_modal()
	_build_compendium_modal()


static func create_icon(item_or_kind, col: Color, sz: Vector2, locked_silhouette: bool = false) -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = sz
	frame.size = sz
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.06, 0.08, 0.88) if locked_silhouette else Color(col.r * 0.14 + 0.03, col.g * 0.14 + 0.04, col.b * 0.16 + 0.05, 0.94)
	st.border_color = Color(0.28, 0.40, 0.38, 0.40) if locked_silhouette else Color(col.r, col.g, col.b, 0.72)
	st.set_border_width_all(1 if sz.x < 60.0 else 2)
	st.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", st)

	var tex := load_collectible_icon(item_or_kind)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(2, 2)
		tr.size = Vector2(maxf(8.0, sz.x - 4.0), maxf(8.0, sz.y - 4.0))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked_silhouette:
			tr.modulate = Color(0.10, 0.16, 0.19, 0.82)
		frame.add_child(tr)
		if locked_silhouette:
			var q := Label.new()
			q.text = "?"
			q.position = Vector2.ZERO
			q.size = sz
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.add_theme_font_size_override("font_size", int(clampf(sz.y * 0.44, 14.0, 32.0)))
			q.add_theme_color_override("font_color", Color(0.58, 0.76, 0.72, 0.75))
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(q)
	return frame


func any_modal_open() -> bool:
	return busy_bag or busy_inspect or busy_compendium or busy_warehouse


func close_all_modals():
	if busy_inspect:
		inspect_return_to = ""
		close_inspect()
	if busy_bag:
		close_backpack()
	if busy_warehouse:
		close_warehouse()
	if busy_compendium:
		close_compendium()


func reset_run():
	toast_left = 0.0
	if is_instance_valid(toast_panel):
		toast_panel.hide()
	cancel_quick_search()
	close_all_modals()


func _build_toast_and_search_hud():
	# 1) High-value Loot Jackpot Toast (below top question box, completely clear of crosshair)
	toast_panel = game._panel(game.hud, Rect2(376, 148, 528, 76), Color(0.05, 0.09, 0.11, 0.95), Color("ffd15c"))
	toast_panel.hide()
	toast_icon_holder = Control.new()
	toast_icon_holder.position = Vector2(12, 10)
	toast_icon_holder.size = Vector2(56, 56)
	toast_panel.add_child(toast_icon_holder)

	toast_header = game._text(toast_panel, "", Vector2(78, 6), Vector2(436, 22), 14, Color("ffd15c"))
	toast_name = game._text(toast_panel, "", Vector2(78, 28), Vector2(436, 24), 18, game.CREAM)
	toast_sub = game._text(toast_panel, "", Vector2(78, 52), Vector2(436, 18), 12, Color("b8d6c8"))

	# 2) Tactile Magnifying-Glass Quick-Search Bar (for Bird Nests & Crevices)
	search_panel = game._panel(game.hud, Rect2(430, 544, 420, 42), Color(0.04, 0.10, 0.12, 0.94), game.MINT)
	search_panel.hide()
	search_label = game._text(search_panel, "🔍 正在摸索秘藏...", Vector2(14, 4), Vector2(392, 20), 14, game.GOLD)
	search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(18, 28)
	bar_bg.size = Vector2(384, 7)
	bar_bg.color = Color(1, 1, 1, 0.12)
	search_panel.add_child(bar_bg)
	search_bar_fill = ColorRect.new()
	search_bar_fill.position = Vector2(18, 28)
	search_bar_fill.size = Vector2(0, 7)
	search_bar_fill.color = game.MINT
	search_panel.add_child(search_bar_fill)


func trigger_loot_toast(item: Dictionary, source_tag: String = "搜刮获得"):
	var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
	toast_rarity = r
	var r_col: Color = game.Rules.RARITY_COLORS[r]
	var r_name: String = game.Rules.RARITY_NAMES[r]
	var cond: String = str(item.get("cond", "标准"))
	var cond_tag: String = (" · ✦" + cond) if cond in ["极品孤本", "崭新"] else (" · " + cond if cond != "标准" else "")

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.18, 0.04, 0.06, 0.96) if r == 7 else (Color(0.15, 0.10, 0.03, 0.95) if r >= 5 else Color(0.05, 0.10, 0.13, 0.94))
	st.border_color = r_col
	st.set_border_width_all(3 if r >= 5 else 2)
	st.set_corner_radius_all(8)
	toast_panel.add_theme_stylebox_override("panel", st)

	for ch in toast_icon_holder.get_children():
		ch.queue_free()
	toast_icon_holder.add_child(create_icon(item, r_col, Vector2(56, 56)))

	if r == 7:
		toast_header.text = "🔥 出大红了！！【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.screen_flash.color = Color(1.0, 0.26, 0.32, 0.24)
		game.play_sfx("loot_mythic_red", -7)
	elif r == 6:
		toast_header.text = "✦ 摸出大金！【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.screen_flash.color = Color(1.0, 0.72, 0.22, 0.18)
		game.play_sfx("loot_epic", -8)
	elif r == 5:
		toast_header.text = "◆ 摸出小金珍品！【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.screen_flash.color = Color(0.98, 0.84, 0.36, 0.14)
		game.play_sfx("loot_epic", -11)
	elif r == 4:
		toast_header.text = "★ 搜出史诗奇珍【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.play_sfx("loot_reveal_rare", -10)
	elif r == 3:
		toast_header.text = "◆ 发现稀有物资【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.play_sfx("loot_reveal_rare", -12)
	else:
		toast_header.text = "已收入【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.play_sfx("loot_reveal_common", -12)

	toast_header.add_theme_color_override("font_color", r_col)
	toast_name.text = "%s  ·  %s" % [str(item.get("title", "物资")), str(item.get("en", "Item"))]
	toast_sub.text = "鉴定估值 +%d 币（占格 %s）  |  按 [B] 存入安全箱 · [I] 3D检视宝物" % [
		int(item.get("value", 0)), str(item.get("grid", "1×1"))
	]
	toast_left = 4.8 if r >= 6 else (4.0 if r == 5 else (3.4 if r >= 3 else 2.4))
	toast_panel.show()


func start_quick_search(node: Node3D, duration: float = 0.90):
	if not is_instance_valid(node):
		return
	active_search_node = node
	search_elapsed = 0.0
	search_duration = maxf(0.15, duration)
	var title: String = str(node.get_meta("title", "隐秘鸟窝"))
	search_label.text = "🔍 正在摸索【%s】...  期待出大红！" % title
	search_bar_fill.size.x = 0.0
	search_panel.show()
	game.play_sfx("loot_scan_tick", -11)


func cancel_quick_search():
	active_search_node = null
	search_elapsed = 0.0
	if is_instance_valid(search_panel):
		search_panel.hide()


func complete_active_search_for_qa():
	if is_instance_valid(active_search_node):
		var target := active_search_node
		cancel_quick_search()
		if is_instance_valid(game.world_loot):
			game.world_loot.finish_nest_search(target)


func _update_inspect_camera():
	if not is_instance_valid(inspect_cam):
		return
	var target := Vector3(0.0, 0.04, 0.0)
	var cp := target + Vector3(
		inspect_cam_dist * cos(inspect_pitch) * sin(inspect_yaw),
		inspect_cam_dist * sin(inspect_pitch),
		inspect_cam_dist * cos(inspect_pitch) * cos(inspect_yaw)
	)
	inspect_cam.look_at_from_position(cp, target, Vector3.UP)


func _input(event):
	if not busy_inspect or not is_instance_valid(inspect_vp_frame):
		return
	var vp_rect := Rect2(inspect_vp_frame.global_position, inspect_vp_frame.size)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and vp_rect.has_point(mb.position):
				inspect_dragging = true
				get_viewport().set_input_as_handled()
			elif not mb.pressed and inspect_dragging:
				inspect_dragging = false
				get_viewport().set_input_as_handled()
		elif mb.pressed and vp_rect.has_point(mb.position):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				inspect_cam_dist = clampf(inspect_cam_dist - 0.12, 0.92, 2.25)
				_update_inspect_camera()
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				inspect_cam_dist = clampf(inspect_cam_dist + 0.12, 0.92, 2.25)
				_update_inspect_camera()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and inspect_dragging:
		var mm := event as InputEventMouseMotion
		inspect_yaw -= mm.relative.x * 0.011
		inspect_pitch = clampf(inspect_pitch + mm.relative.y * 0.009, -0.35, 1.08)
		_update_inspect_camera()
		get_viewport().set_input_as_handled()


func _process(delta: float):
	if toast_left > 0.0 and not game.paused:
		toast_left = maxf(0.0, toast_left - delta)
		if toast_rarity >= 5 and is_instance_valid(toast_panel):
			var pulse: float = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.012)
			toast_header.modulate = Color(1.0, pulse + 0.22, pulse, 1.0) if toast_rarity == 7 else Color(1.0, 0.95, pulse, 1.0)
		if toast_left <= 0.0 and is_instance_valid(toast_panel):
			toast_header.modulate = Color.WHITE
			toast_panel.hide()

	if is_instance_valid(active_search_node) and not game.paused:
		if not active_search_node.visible or game.player.position.distance_to(active_search_node.global_position) > 3.9:
			cancel_quick_search()
			game._notice("距离过远，已中断搜索。", Color("f5b971"))
		else:
			var prev_step: int = int(search_elapsed / 0.24)
			search_elapsed += delta
			var cur_step: int = int(search_elapsed / 0.24)
			if cur_step > prev_step and search_elapsed < search_duration:
				game.play_sfx("loot_scan_tick", -14)
			var ratio: float = clampf(search_elapsed / search_duration, 0.0, 1.0)
			search_bar_fill.size.x = 384.0 * ratio
			if ratio >= 1.0:
				var finished_node := active_search_node
				cancel_quick_search()
				if is_instance_valid(game.world_loot):
					game.world_loot.finish_nest_search(finished_node)

	if busy_inspect and is_instance_valid(inspect_turntable):
		if inspect_auto_spin and not inspect_dragging:
			inspect_yaw += delta * 0.72
			_update_inspect_camera()
		inspect_turntable.position.y = sin(Time.get_ticks_msec() * 0.0028) * 0.018


# ---------------------------------------------------------------------------
# [B] TACTICAL BACKPACK + 2-SLOT ENCRYPTED SAFE BOX ('加密安全箱')
# ---------------------------------------------------------------------------
func _build_backpack_modal():
	bag_overlay = Control.new()
	bag_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(bag_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.055, 0.90)
	bag_overlay.add_child(veil)

	game._panel(bag_overlay, Rect2(96, 36, 1088, 648), Color(0.045, 0.095, 0.118, 0.98), Color(0.46, 0.82, 0.68, 0.55))
	bag_header_label = game._text(bag_overlay, "随身摸金背包 · 战利品鉴定与安全箱整理", Vector2(130, 56), Vector2(830, 32), 21, game.MINT)
	bag_header_label.clip_text = true
	game._button(bag_overlay, "关闭背包 [B/Esc]", Rect2(990, 54, 158, 36), close_backpack)

	# 2-Slot Encrypted Safe Box Section (阵亡/超时也能带回营地!)
	game._panel(bag_overlay, Rect2(130, 98, 1018, 122), Color(0.08, 0.085, 0.04, 0.95), Color("f6c34e"))
	safe_box_header_label = game._text(bag_overlay, "🔒 加密安全箱（0 / 2 格 · 阵亡或超时仍可安全带回营地收藏库！）", Vector2(146, 104), Vector2(980, 22), 14, Color("ffd46e"))
	safe_box_row = HBoxContainer.new()
	safe_box_row.position = Vector2(146, 130)
	safe_box_row.size = Vector2(986, 82)
	safe_box_row.add_theme_constant_override("separation", 16)
	bag_overlay.add_child(safe_box_row)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(130, 232)
	scroll.size = Vector2(1018, 392)
	bag_overlay.add_child(scroll)

	bag_grid = GridContainer.new()
	bag_grid.columns = 4
	bag_grid.add_theme_constant_override("h_separation", 12)
	bag_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(bag_grid)

	bag_status_label = game._text(bag_overlay, "摸到大红/大金立刻点「存安全箱」锁死保底！点击「3D检视」可 360° 细看藏品纹理与雕工。", Vector2(130, 636), Vector2(1018, 28), 14, Color("9ec4b5"))
	bag_overlay.hide()


func toggle_backpack():
	if busy_bag:
		close_backpack()
	elif game.rules.phase in ["active", "extracting"] and not game.paused:
		open_backpack()


func open_backpack():
	close_all_modals()
	busy_bag = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_backpack_ui()
	bag_overlay.show()


func close_backpack():
	if not busy_bag:
		return
	busy_bag = false
	bag_overlay.hide()
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_backpack_ui():
	for ch in safe_box_row.get_children():
		ch.queue_free()
	for ch in bag_grid.get_children():
		ch.queue_free()
	var cap: int = game.rules.capacity()
	var bag_val: int = game.rules.bag_value()
	var safe_val: int = game.rules.safe_box_value()
	bag_header_label.text = "随身摸金背包（%d/%d 格 · %d币） + 安全箱（%d/%d · %d币）%s" % [
		game.rules.bag.size(), cap, bag_val,
		game.rules.safe_box.size(), game.Rules.SAFE_BOX_SLOTS, safe_val,
		" · 机密×1.35" if game.rules.is_confidential() else ""
	]
	safe_box_header_label.text = "🔒 加密安全箱（%d / %d 格 · 保底估值 %d 币 · 即使行动失败也能安全入库！）" % [
		game.rules.safe_box.size(), game.Rules.SAFE_BOX_SLOTS, safe_val
	]

	# Render 2 Encrypted Safe Box slots
	for s_idx in game.Rules.SAFE_BOX_SLOTS:
		var scard := Panel.new()
		scard.custom_minimum_size = Vector2(484, 80)
		var sst := StyleBoxFlat.new()
		sst.set_corner_radius_all(8)
		if s_idx < game.rules.safe_box.size():
			var s_item: Dictionary = game.rules.safe_box[s_idx]
			var sr: int = clampi(int(s_item.get("rarity", 1)), 1, 7)
			var sr_col: Color = game.Rules.RARITY_COLORS[sr]
			sst.bg_color = Color(sr_col.r * 0.18 + 0.04, sr_col.g * 0.15 + 0.03, sr_col.b * 0.14 + 0.02, 0.96)
			sst.border_color = sr_col
			sst.set_border_width_all(2)
			scard.add_theme_stylebox_override("panel", sst)

			var sic := create_icon(s_item, sr_col, Vector2(58, 58))
			sic.position = Vector2(10, 11)
			scard.add_child(sic)

			var sb_lbl: Label = game._text(scard, "🔒【%s】 %s" % [game.Rules.RARITY_NAMES[sr], str(s_item.get("title", "宝物"))], Vector2(76, 8), Vector2(248, 22), 14, sr_col)
			sb_lbl.clip_text = true
			var se_lbl: Label = game._text(scard, "%s · 保底估值 %d 币" % [str(s_item.get("en", "")), int(s_item.get("value", 0))], Vector2(76, 32), Vector2(248, 20), 12, game.GOLD)
			se_lbl.clip_text = true
			game._text(scard, "已加密锁定 · 行动失败也不掉落", Vector2(76, 54), Vector2(248, 18), 11, Color("9ee2c2"))

			var b_insp_s: Button = game._button(scard, "3D检视", Rect2(332, 12, 68, 56), func():
				inspect_return_to = "backpack"
				close_backpack()
				open_inspect_item(s_item)
			)
			b_insp_s.add_theme_font_size_override("font_size", 12)
			var b_take: Button = game._button(scard, "取回\n背包", Rect2(406, 12, 68, 56), _move_safe_to_bag.bind(s_idx))
			b_take.add_theme_font_size_override("font_size", 12)
			b_take.disabled = game.rules.bag.size() >= cap
		else:
			sst.bg_color = Color(0.05, 0.075, 0.06, 0.72)
			sst.border_color = Color(0.95, 0.78, 0.35, 0.36)
			sst.set_border_width_all(1)
			scard.add_theme_stylebox_override("panel", sst)
			var sempty: Label = game._text(scard, "🔒 安全箱槽位 #%d（空闲）\n在下方背包中点击「存安全箱」即可将珍宝存入此格" % (s_idx + 1), Vector2(18, 18), Vector2(448, 44), 13, Color("cbbd88"))
			sempty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		safe_box_row.add_child(scard)

	var safe_full: bool = game.rules.safe_box.size() >= game.Rules.SAFE_BOX_SLOTS
	for slot_i in cap:
		var card := Panel.new()
		card.custom_minimum_size = Vector2(242, 146)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(8)
		if slot_i < game.rules.bag.size():
			var item: Dictionary = game.rules.bag[slot_i]
			var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
			var r_col: Color = game.Rules.RARITY_COLORS[r]
			st.bg_color = Color(r_col.r * 0.16, r_col.g * 0.15, r_col.b * 0.18, 0.96)
			st.border_color = r_col
			st.set_border_width_all(3 if r >= 5 else 2)
			card.add_theme_stylebox_override("panel", st)

			var ic := create_icon(item, r_col, Vector2(54, 54))
			ic.position = Vector2(10, 10)
			card.add_child(ic)

			var r_badge: String = "【%s · %s】" % [game.Rules.RARITY_NAMES[r], str(item.get("cond", "标准"))]
			game._text(card, r_badge, Vector2(70, 8), Vector2(164, 20), 11, r_col)
			var t_lbl: Label = game._text(card, str(item.get("title", "物资")), Vector2(70, 28), Vector2(164, 22), 15, game.CREAM)
			t_lbl.clip_text = true
			var e_lbl: Label = game._text(card, "🔊 " + str(item.get("en", "Supply")), Vector2(70, 50), Vector2(162, 18), 11, Color("9adbc0"))
			e_lbl.clip_text = true
			e_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			game._text(card, "估值 %d 币 · %s" % [int(item.get("value", 0)), str(item.get("grid", "1×1"))], Vector2(12, 74), Vector2(218, 20), 13, game.GOLD)

			var btn_safe: Button = game._button(card, "存安全箱", Rect2(10, 102, 72, 32), _move_bag_to_safe.bind(slot_i), not safe_full)
			btn_safe.add_theme_font_size_override("font_size", 11)
			btn_safe.disabled = safe_full
			var btn_insp: Button = game._button(card, "3D检视", Rect2(86, 102, 56, 32), func():
				inspect_return_to = "backpack"
				close_backpack()
				open_inspect_item(item)
			)
			btn_insp.add_theme_font_size_override("font_size", 11)
			var btn_speak: Button = game._button(card, "读音", Rect2(146, 102, 42, 32), func(): game.speak_english(str(item.get("en", ""))))
			btn_speak.add_theme_font_size_override("font_size", 11)
			var btn_drop: Button = game._button(card, "丢弃", Rect2(192, 102, 42, 32), _discard_slot.bind(slot_i))
			btn_drop.add_theme_font_size_override("font_size", 11)
		else:
			st.bg_color = Color(0.03, 0.06, 0.08, 0.65)
			st.border_color = Color(0.35, 0.55, 0.48, 0.25)
			st.set_border_width_all(1)
			card.add_theme_stylebox_override("panel", st)
			var empty_l: Label = game._text(card, "空闲槽位 #%d\n探索物资箱/隐蔽角落搜刮" % (slot_i + 1), Vector2(14, 50), Vector2(214, 48), 13, Color("6c8d80"))
			empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag_grid.add_child(card)


func _move_bag_to_safe(idx: int):
	if idx < 0 or idx >= game.rules.bag.size():
		return
	var title_s: String = str(game.rules.bag[idx].get("title", "宝物"))
	if game.rules.move_bag_to_safe_box(idx):
		game.play_sfx("cipher_unlock", -11)
		bag_status_label.text = "🔒 已将【%s】存入加密安全箱！本局即便失败也可安全带回营地仓库。" % title_s
		_refresh_backpack_ui()


func _move_safe_to_bag(idx: int):
	if idx < 0 or idx >= game.rules.safe_box.size():
		return
	var title_s: String = str(game.rules.safe_box[idx].get("title", "宝物"))
	if game.rules.move_safe_box_to_bag(idx):
		game.play_sfx("loot_reveal_common", -12)
		bag_status_label.text = "已将【%s】从安全箱取回随身背包。" % title_s
		_refresh_backpack_ui()


func _discard_slot(idx: int):
	var removed: Dictionary = game.rules.discard_bag_item(idx)
	if not removed.is_empty():
		game.play_sfx("loot_reveal_common", -13)
		bag_status_label.text = "已丢弃【%s（%d币）】，腾出 1 格随身背包空间。" % [str(removed.get("title", "")), int(removed.get("value", 0))]
		_refresh_backpack_ui()


# ---------------------------------------------------------------------------
# CAMP & SETTLEMENT WAREHOUSE VAULT ('烟山战利品收藏库 · v0.8.0')
# ---------------------------------------------------------------------------
func _build_warehouse_modal():
	wh_overlay = Control.new()
	wh_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(wh_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.05, 0.94)
	wh_overlay.add_child(veil)

	game._panel(wh_overlay, Rect2(74, 38, 1132, 644), Color(0.04, 0.086, 0.108, 0.98), Color("f6c34e"))
	game._text(wh_overlay, "📦 烟山战利品收藏库 · 单件出售 / 🔒锁存珍藏 / 营地3D展台", Vector2(106, 54), Vector2(740, 34), 24, Color("ffd46e"))
	wh_sell_junk_btn = game._button(wh_overlay, "一键售杂物(白/绿/蓝)", Rect2(842, 54, 194, 36), _warehouse_sell_junk, true)
	wh_sell_junk_btn.add_theme_font_size_override("font_size", 14)
	game._button(wh_overlay, "返回营地 [Esc]", Rect2(1046, 54, 130, 36), close_warehouse)

	wh_stats_label = game._text(wh_overlay, "", Vector2(106, 94), Vector2(1070, 24), 14, game.MINT)

	# Filter tabs
	var filters := [
		["all", "全部库存"],
		["high", "金红重宝 (小金/大金/大红)"],
		["locked", "🔒 已锁存珍藏"],
		["junk", "常规杂物 (白/绿/蓝)"]
	]
	var fx := 106.0
	for pair in filters:
		var fkey: String = pair[0]
		var flbl: String = pair[1]
		var w_btn: float = 198.0 if fkey == "high" else (162.0 if fkey == "junk" else 134.0)
		var fb: Button = game._button(wh_overlay, flbl, Rect2(fx, 124, w_btn, 32), func():
			wh_filter_mode = fkey
			_refresh_warehouse_ui()
		)
		fb.add_theme_font_size_override("font_size", 13)
		wh_filter_buttons[fkey] = fb
		fx += w_btn + 10.0

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(106, 166)
	scroll.size = Vector2(1070, 466)
	wh_overlay.add_child(scroll)

	wh_grid = GridContainer.new()
	wh_grid.columns = 3
	wh_grid.add_theme_constant_override("h_separation", 14)
	wh_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(wh_grid)

	wh_status_label = game._text(wh_overlay, "提示：大金与大红带出后自动 🔒 锁存防误卖；最多挑选 4 件珍宝摆上营地 3D 奇珍展台！", Vector2(106, 642), Vector2(1070, 26), 14, Color("9ec4b5"))
	wh_overlay.hide()


func open_warehouse():
	if game.rules.phase in ["active", "extracting"]:
		game._notice("行动进行中请使用 [B] 随身背包，撤离回营后即可管理收藏库！", game.GOLD)
		return
	close_all_modals()
	busy_warehouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_warehouse_ui()
	wh_overlay.show()


func close_warehouse():
	if not busy_warehouse:
		return
	busy_warehouse = false
	wh_overlay.hide()
	game._refresh_menu()


func _warehouse_sell_junk():
	var res: Dictionary = game.rules.sell_unlocked_junk(3)
	if int(res.get("count", 0)) > 0:
		game.play_sfx("cipher_unlock", -11)
		game._save()
		wh_status_label.text = "已出售 %d 件未锁定的白/绿/蓝杂物，获得 +%d 枚货币！（高阶珍宝与锁定藏品完好保留）" % [int(res.count), int(res.coins)]
	else:
		wh_status_label.text = "当前没有可出售的未锁定白/绿/蓝杂物。"
	_refresh_warehouse_ui()
	game._refresh_menu()


func _warehouse_sell_single(wh_idx: int):
	if wh_idx < 0 or wh_idx >= game.rules.profile.warehouse.size():
		return
	var title_s: String = str(game.rules.profile.warehouse[wh_idx].get("title", "物资"))
	var earned: int = game.rules.sell_warehouse_item(wh_idx)
	if earned > 0:
		game.play_sfx("cipher_unlock", -12)
		game._save()
		if game.has_method("refresh_camp_display_stand"):
			game.refresh_camp_display_stand()
		wh_status_label.text = "已单件出售【%s】，获得 +%d 枚货币！（当前货币 %d）" % [title_s, earned, game.rules.profile.coins]
	else:
		wh_status_label.text = "【%s】已锁定珍藏，请先解锁后再出售。" % title_s
	_refresh_warehouse_ui()
	game._refresh_menu()


func _warehouse_toggle_lock(wh_idx: int):
	if wh_idx < 0 or wh_idx >= game.rules.profile.warehouse.size():
		return
	var title_s: String = str(game.rules.profile.warehouse[wh_idx].get("title", "物资"))
	var now_locked: bool = game.rules.toggle_warehouse_lock(wh_idx)
	game.play_sfx("weapon_change", -14)
	game._save()
	wh_status_label.text = ("🔒 已锁存【%s】，防误卖保护已开启。" if now_locked else "🔓 已解锁【%s】，现在可以单件出售。") % title_s
	_refresh_warehouse_ui()
	game._refresh_menu()


func _warehouse_toggle_stand(title: String):
	var res: Dictionary = game.rules.toggle_display_stand(title)
	if bool(res.get("ok", false)):
		game.play_sfx("loot_epic" if bool(res.get("pinned", false)) else "weapon_change", -12)
		game._save()
		if game.has_method("refresh_camp_display_stand"):
			game.refresh_camp_display_stand()
		wh_status_label.text = ("★ 已将【%s】摆上营地 3D 奇珍展台（自动锁存）！" if bool(res.get("pinned", false)) else "已将【%s】从营地 3D 展台撤下。") % title
	elif str(res.get("reason", "")) == "full":
		wh_status_label.text = "营地 3D 展台已满 4 槽！请先撤下 1 件展品后再上架【%s】。" % title
	_refresh_warehouse_ui()
	game._refresh_menu()


func _refresh_warehouse_ui():
	for ch in wh_grid.get_children():
		ch.queue_free()

	for fkey in wh_filter_buttons:
		var fb: Button = wh_filter_buttons[fkey]
		var active_f: bool = (fkey == wh_filter_mode)
		game._style_tactical_button(
			fb,
			Color("3a6e5c") if active_f else Color("1d3036"),
			Color("8de8c0") if active_f else Color(0.42, 0.68, 0.58, 0.35),
			game.CREAM
		)

	var wh: Array = game.rules.profile.warehouse
	var stand_cnt: int = game.rules.profile.get("display_stand", []).size()
	var junk_n := 0
	var junk_val := 0
	for it in wh:
		if not bool(it.get("locked", false)) and int(it.get("rarity", 1)) <= 3:
			junk_n += 1
			junk_val += int(it.get("value", 0))
	wh_sell_junk_btn.text = "一键售杂物 (%d件·+%d币)" % [junk_n, junk_val]
	wh_sell_junk_btn.disabled = (junk_n == 0)
	wh_stats_label.text = "库存总计 %d 件（已锁存 %d 件 · 营地3D展台 %d/%d 槽）  |  未锁可售估值 %d 币  |  当前游戏货币 %d 币" % [
		wh.size(), game.rules.locked_warehouse_count(), stand_cnt, game.Rules.MAX_DISPLAY_STAND,
		game.rules.unlocked_warehouse_value(), game.rules.profile.coins
	]

	# Build sorted display indices (highest rarity & value first!)
	var indices := []
	for i in wh.size():
		var item: Dictionary = wh[i]
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		var locked: bool = bool(item.get("locked", false))
		if wh_filter_mode == "high" and r < 5:
			continue
		if wh_filter_mode == "locked" and not locked:
			continue
		if wh_filter_mode == "junk" and (locked or r > 3):
			continue
		indices.append(i)
	indices.sort_custom(func(a, b):
		var ia: Dictionary = wh[a]
		var ib: Dictionary = wh[b]
		var ra := int(ia.get("rarity", 1))
		var rb := int(ib.get("rarity", 1))
		if ra != rb:
			return ra > rb
		return int(ia.get("value", 0)) > int(ib.get("value", 0))
	)

	if indices.is_empty():
		var empty_card := Panel.new()
		empty_card.custom_minimum_size = Vector2(1040, 120)
		var est := StyleBoxFlat.new()
		est.bg_color = Color(0.03, 0.06, 0.08, 0.72)
		est.border_color = Color(0.4, 0.65, 0.55, 0.25)
		est.set_border_width_all(1)
		est.set_corner_radius_all(8)
		empty_card.add_theme_stylebox_override("panel", est)
		var em_lbl: Label = game._text(empty_card, "当前筛选下暂无战利品。进山搜刮物资并携带撤离（或存入 2 格加密安全箱）即可永久入库！", Vector2(20, 44), Vector2(1000, 32), 16, Color("86ab9d"))
		em_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wh_grid.add_child(empty_card)
		return

	for wh_idx in indices:
		var item: Dictionary = wh[wh_idx]
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		var r_col: Color = game.Rules.RARITY_COLORS[r]
		var locked: bool = bool(item.get("locked", false))
		var title_s: String = str(item.get("title", "物资"))
		var on_stand: bool = game.rules.is_on_display_stand(title_s)

		var card := Panel.new()
		card.custom_minimum_size = Vector2(344, 144)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(r_col.r * 0.16, r_col.g * 0.15, r_col.b * 0.18, 0.96)
		st.border_color = Color("ffd46e") if on_stand else r_col
		st.set_border_width_all(3 if (r >= 6 or on_stand) else 2)
		st.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", st)

		var ic := create_icon(item, r_col, Vector2(62, 62))
		ic.position = Vector2(10, 10)
		card.add_child(ic)

		var badge_prefix: String = ("★展台 " if on_stand else "") + ("🔒 " if locked else "")
		var head_lbl: Label = game._text(card, "%s【%s · %s】" % [badge_prefix, game.Rules.RARITY_NAMES[r], str(item.get("cond", "标准"))], Vector2(80, 8), Vector2(254, 20), 12, Color("ffd46e") if on_stand else r_col)
		head_lbl.clip_text = true
		var t_lbl: Label = game._text(card, title_s, Vector2(80, 28), Vector2(254, 24), 16, game.CREAM)
		t_lbl.clip_text = true
		var e_lbl: Label = game._text(card, "🔊 %s" % str(item.get("en", "Item")), Vector2(80, 52), Vector2(254, 18), 11, Color("9adbc0"))
		e_lbl.clip_text = true
		game._text(card, "单件估值：%d 币 · 占格 %s" % [int(item.get("value", 0)), str(item.get("grid", "1×1"))], Vector2(12, 78), Vector2(320, 20), 13, game.GOLD)

		var btn_sell: Button = game._button(card, "已锁存" if locked else "出售 +%d" % int(item.get("value", 0)), Rect2(10, 104, 94, 30), _warehouse_sell_single.bind(wh_idx), not locked)
		btn_sell.add_theme_font_size_override("font_size", 12)
		btn_sell.disabled = locked
		var btn_lock: Button = game._button(card, "🔓解锁" if locked else "🔒锁存", Rect2(108, 104, 72, 30), _warehouse_toggle_lock.bind(wh_idx))
		btn_lock.add_theme_font_size_override("font_size", 12)
		var btn_stand: Button = game._button(card, "撤展台" if on_stand else "★展台", Rect2(184, 104, 74, 30), _warehouse_toggle_stand.bind(title_s))
		btn_stand.add_theme_font_size_override("font_size", 12)
		var btn_insp: Button = game._button(card, "3D检视", Rect2(262, 104, 72, 30), func():
			inspect_return_to = "warehouse"
			close_warehouse()
			open_inspect_item(item)
		)
		btn_insp.add_theme_font_size_override("font_size", 12)
		wh_grid.add_child(card)


# ---------------------------------------------------------------------------
# [I] INTERACTIVE 360° MUSEUM 3D RELIC INSPECT SHOWCASE
# ---------------------------------------------------------------------------
func _build_inspect_modal():
	inspect_overlay = Control.new()
	inspect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(inspect_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.035, 0.045, 0.92)
	inspect_overlay.add_child(veil)

	game._panel(inspect_overlay, Rect2(200, 62, 880, 596), Color(0.045, 0.085, 0.108, 0.98), Color("ffd15c"))
	inspect_title = game._text(inspect_overlay, "宝物 3D 博物检视台", Vector2(238, 82), Vector2(610, 38), 28, Color("ffd15c"))
	game._button(inspect_overlay, "收起返回 [I/Esc]", Rect2(896, 82, 152, 38), close_inspect)

	# Dedicated 3D SubViewport Relic Studio Showcase (mouse-drag 360° orbit + wheel zoom!)
	inspect_vp_frame = game._panel(inspect_overlay, Rect2(238, 134, 376, 376), Color(0.035, 0.068, 0.088, 1.0), Color(0.68, 0.86, 0.76, 0.45))
	var vpc := SubViewportContainer.new()
	vpc.position = Vector2(6, 6)
	vpc.size = Vector2(364, 364)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_vp_frame.add_child(vpc)

	inspect_vp = SubViewport.new()
	inspect_vp.size = Vector2i(364, 364)
	inspect_vp.own_world_3d = true
	inspect_vp.transparent_bg = true
	inspect_vp.msaa_3d = Viewport.MSAA_4X
	inspect_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vpc.add_child(inspect_vp)

	# Studio WorldEnvironment so metals, celadon glaze, jade & bronze gleam naturally!
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.09, 0.11, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8e8f0")
	env.ambient_light_energy = 0.82
	we.environment = env
	inspect_vp.add_child(we)

	inspect_cam = Camera3D.new()
	inspect_cam.fov = 38.0
	inspect_vp.add_child(inspect_cam)
	_update_inspect_camera()

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-34, 32, 0)
	key_light.light_color = Color("fff6e6")
	key_light.light_energy = 1.65
	inspect_vp.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-16, -135, 0)
	fill_light.light_color = Color("bde4ff")
	fill_light.light_energy = 0.78
	inspect_vp.add_child(fill_light)

	inspect_rim_light = OmniLight3D.new()
	inspect_rim_light.position = Vector3(-0.9, 0.85, -1.15)
	inspect_rim_light.light_color = Color("ffd166")
	inspect_rim_light.light_energy = 2.1
	inspect_rim_light.omni_range = 5.5
	inspect_vp.add_child(inspect_rim_light)

	inspect_turntable = Node3D.new()
	inspect_vp.add_child(inspect_turntable)

	# Turntable controls directly under 3D viewport
	inspect_spin_btn = game._button(inspect_overlay, "⏸ 暂停自转", Rect2(238, 520, 140, 34), func():
		inspect_auto_spin = not inspect_auto_spin
		inspect_spin_btn.text = "⏸ 暂停自转" if inspect_auto_spin else "▶ 自动旋转"
	)
	inspect_spin_btn.add_theme_font_size_override("font_size", 13)
	var btn_reset: Button = game._button(inspect_overlay, "↺ 重置视角", Rect2(388, 520, 122, 34), func():
		inspect_yaw = 0.35
		inspect_pitch = 0.24
		inspect_cam_dist = 1.62
		_update_inspect_camera()
	)
	btn_reset.add_theme_font_size_override("font_size", 13)
	game._text(inspect_overlay, "左键拖拽 360° 旋转 · 滚轮缩放", Vector2(238, 560), Vector2(376, 24), 13, Color("8fd6bc"))

	# Right-side Appraisal & Bilingual Lore Card
	inspect_icon_holder = Control.new()
	inspect_icon_holder.position = Vector2(638, 138)
	inspect_icon_holder.size = Vector2(88, 88)
	inspect_overlay.add_child(inspect_icon_holder)

	inspect_en_label = game._text(inspect_overlay, "", Vector2(738, 142), Vector2(316, 34), 22, game.MINT)
	inspect_meta_label = game._text(inspect_overlay, "", Vector2(738, 180), Vector2(316, 54), 15, game.GOLD)
	inspect_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	inspect_lore_label = game._text(inspect_overlay, "", Vector2(638, 242), Vector2(416, 266), 14, game.CREAM)
	inspect_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	game._button(inspect_overlay, "🔊 朗读宝物英文名称", Rect2(638, 520, 248, 46), func():
		if not inspect_item_data.is_empty():
			game.speak_english(str(inspect_item_data.get("en", "")))
	, true)

	game._text(inspect_overlay, "带出撤离信标（或存入 2 格安全箱）即可永久点亮营地【烟山奇珍图鉴】，随时 360° 赏玩独立建模奇珍！", Vector2(238, 608), Vector2(810, 26), 14, Color("9ec4b5"))
	inspect_overlay.hide()


func inspect_best_in_bag():
	if game.rules.phase not in ["active", "extracting"]:
		return
	if busy_inspect:
		close_inspect()
		return
	var combined: Array = game.rules.safe_box + game.rules.bag
	if combined.is_empty():
		game._notice("随身背包与安全箱暂无战利品，快去搜刮物资箱或隐蔽角落吧！", game.GOLD)
		return
	var best: Dictionary = combined[0]
	for it in combined:
		if int(it.get("rarity", 1)) > int(best.get("rarity", 1)) or (int(it.get("rarity", 1)) == int(best.get("rarity", 1)) and int(it.get("value", 0)) > int(best.get("value", 0))):
			best = it
	inspect_return_to = ""
	open_inspect_item(best)


func open_inspect_item(item: Dictionary):
	var saved_return := inspect_return_to
	close_all_modals()
	inspect_return_to = saved_return
	inspect_item_data = item.duplicate(true)
	busy_inspect = true
	inspect_dragging = false
	inspect_auto_spin = true
	inspect_yaw = 0.35
	inspect_pitch = 0.24
	inspect_cam_dist = 1.62
	if is_instance_valid(inspect_spin_btn):
		inspect_spin_btn.text = "⏸ 暂停自转"
	_update_inspect_camera()

	if game.rules.phase in ["active", "extracting"]:
		game.paused = true
		game.player.active = false
		game.player.clear_movement_input()
		game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
	var r_col: Color = game.Rules.RARITY_COLORS[r]
	inspect_title.text = "【%s】%s" % [game.Rules.RARITY_NAMES[r], str(item.get("title", "宝物"))]
	inspect_title.add_theme_color_override("font_color", r_col)
	inspect_en_label.text = str(item.get("en", "Treasure"))
	inspect_meta_label.text = "鉴定成色：%s  |  占格：%s\n当前估值：%d 币" % [
		str(item.get("cond", "标准")), str(item.get("grid", "1×1")), int(item.get("value", 0))
	]
	var item_title := str(item.get("title", ""))
	if game.Rules.CULTURAL_NOTES.has(item_title):
		var cnote: Dictionary = game.Rules.CULTURAL_NOTES[item_title]
		inspect_lore_label.text = "【烟山物语（游戏设定）】\n" + str(cnote.fiction) + "\n\n【器物考据（历史资料）】\n" + str(cnote.fact)
	else:
		inspect_lore_label.text = "【烟山风物与战术档案】\n" + str(item.get("lore", ""))

	for ch in inspect_icon_holder.get_children():
		ch.queue_free()
	inspect_icon_holder.add_child(create_icon(item, r_col, Vector2(88, 88)))

	if is_instance_valid(inspect_rim_light):
		inspect_rim_light.light_color = r_col.lightened(0.18)

	_populate_3d_turntable(item, r, r_col)
	game.speak_english(str(item.get("en", "")))
	game.play_sfx("loot_mythic_red" if r == 7 else ("loot_epic" if r >= 5 else "loot_reveal_rare"), -10)
	inspect_overlay.show()


func close_inspect():
	if not busy_inspect:
		return
	busy_inspect = false
	inspect_dragging = false
	inspect_overlay.hide()
	var target_return := inspect_return_to
	inspect_return_to = ""
	if target_return == "warehouse":
		open_warehouse()
		return
	if target_return == "compendium":
		open_compendium()
		return
	if target_return == "backpack" and game.rules.phase in ["active", "extracting"]:
		open_backpack()
		return
	if game.rules.phase in ["active", "extracting"]:
		game.paused = false
		game.player.active = true
		game.player.clear_movement_input()
		game.hud.show()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _populate_3d_turntable(item_or_kind, rarity: int, r_col: Color):
	for ch in inspect_turntable.get_children():
		ch.queue_free()
	inspect_turntable.rotation = Vector3.ZERO

	# Stepped museum zitan & brushed-brass velvet display pedestal
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color("241714")
	base_mat.metallic = 0.22
	base_mat.roughness = 0.34
	var ped := MeshInstance3D.new()
	var ped_cyl := CylinderMesh.new()
	ped_cyl.top_radius = 0.44
	ped_cyl.bottom_radius = 0.50
	ped_cyl.height = 0.068
	ped.mesh = ped_cyl
	ped.position = Vector3(0, -0.34, 0)
	ped.material_override = base_mat
	inspect_turntable.add_child(ped)

	var velvet_mat := StandardMaterial3D.new()
	velvet_mat.albedo_color = Color("261116") if rarity == 7 else (Color("241d0f") if rarity >= 5 else Color("132629"))
	velvet_mat.roughness = 0.88
	var top_pad := MeshInstance3D.new()
	var pad_cyl := CylinderMesh.new()
	pad_cyl.top_radius = 0.39
	pad_cyl.bottom_radius = 0.41
	pad_cyl.height = 0.022
	top_pad.mesh = pad_cyl
	top_pad.position = Vector3(0, -0.296, 0)
	top_pad.material_override = velvet_mat
	inspect_turntable.add_child(top_pad)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = r_col
	ring_mat.metallic = 0.72
	ring_mat.roughness = 0.24
	ring_mat.emission_enabled = true
	ring_mat.emission = r_col
	ring_mat.emission_energy_multiplier = 0.95 if rarity >= 5 else 0.45
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.415
	torus.outer_radius = 0.435
	ring.mesh = torus
	ring.position = Vector3(0, -0.298, 0)
	ring.material_override = ring_mat
	inspect_turntable.add_child(ring)

	var relic_mesh := build_world_loot_mesh(item_or_kind, rarity, r_col, 1.82)
	relic_mesh.position = Vector3(0, -0.280, 0)
	inspect_turntable.add_child(relic_mesh)


static func build_world_loot_mesh(item_or_kind, rarity: int, r_col: Color, scale_mult: float = 1.0) -> Node3D:
	## Sculpted multi-material PBR 3D collectible mesh from assets/slice/v072_collectibles.glb
	## Used on open-world stone pedestals, the Camp 3D Display Stand, and the [I] 360° Showcase!
	var root := Node3D.new()
	root.scale = Vector3.ONE * scale_mult

	var mesh := get_collectible_mesh(item_or_kind)
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		return root

	# Emergency fallback only if GLB unavailable
	var main_mat := StandardMaterial3D.new()
	main_mat.albedo_color = r_col.lightened(0.14)
	main_mat.metallic = 0.55 if rarity >= 5 else 0.25
	main_mat.roughness = 0.30
	var fallback := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.14
	sp.height = 0.28
	fallback.mesh = sp
	fallback.position.y = 0.14
	fallback.material_override = main_mat
	root.add_child(fallback)
	return root


# ---------------------------------------------------------------------------
# CAMP BILINGUAL TREASURE COMPENDIUM ('烟山奇珍图鉴 · 64件 · v0.8.0')
# ---------------------------------------------------------------------------
func _build_compendium_modal():
	comp_overlay = Control.new()
	comp_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(comp_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.05, 0.94)
	comp_overlay.add_child(veil)

	game._panel(comp_overlay, Rect2(86, 48, 1108, 624), Color(0.04, 0.088, 0.108, 0.98), Color("ffd15c"))
	game._text(comp_overlay, "🏆 烟山奇珍图鉴", Vector2(122, 68), Vector2(240, 36), 26, Color("ffd15c"))
	comp_tab_relics_btn = game._button(comp_overlay, "奇珍藏品", Rect2(370, 68, 134, 36), func():
		comp_tab = "relics"
		_refresh_compendium_ui()
	)
	comp_tab_ach_btn = game._button(comp_overlay, "🎖 成就与挂件", Rect2(514, 68, 174, 36), func():
		comp_tab = "achievements"
		_refresh_compendium_ui()
	)
	game._button(comp_overlay, "返回营地", Rect2(1020, 68, 138, 38), close_compendium)

	comp_stats_label = game._text(comp_overlay, "", Vector2(122, 110), Vector2(1036, 26), 14, game.MINT)
	comp_stats_label.clip_text = true

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(122, 144)
	scroll.size = Vector2(1036, 498)
	comp_overlay.add_child(scroll)

	comp_grid = GridContainer.new()
	comp_grid.columns = 3
	comp_grid.add_theme_constant_override("h_separation", 14)
	comp_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(comp_grid)
	comp_overlay.hide()


func open_compendium(initial_tab: String = "relics"):
	close_all_modals()
	comp_tab = initial_tab
	busy_compendium = true
	_refresh_compendium_ui()
	comp_overlay.show()


func close_compendium():
	busy_compendium = false
	comp_overlay.hide()


func _refresh_compendium_ui():
	for ch in comp_grid.get_children():
		comp_grid.remove_child(ch)
		ch.queue_free()
	if is_instance_valid(comp_tab_relics_btn) and is_instance_valid(comp_tab_ach_btn):
		game._style_tactical_button(
			comp_tab_relics_btn,
			Color("3c341a") if comp_tab == "relics" else Color("17282c"),
			Color("ffd15c") if comp_tab == "relics" else Color("4a6e6a"),
			Color("fff2c4") if comp_tab == "relics" else Color("b8d2c8")
		)
		game._style_tactical_button(
			comp_tab_ach_btn,
			Color("3c341a") if comp_tab == "achievements" else Color("17282c"),
			Color("ffd15c") if comp_tab == "achievements" else Color("4a6e6a"),
			Color("fff2c4") if comp_tab == "achievements" else Color("b8d2c8")
		)
	if comp_tab == "achievements":
		_render_achievements_tab()
		return
	var col_arr: Array = game.rules.profile.collection
	var total_col: int = game.Rules.total_collectible_count()
	var total_all: int = game.Rules.total_catalog_count()
	var best_item_str: String = "暂无纪录"
	if int(game.rules.profile.get("best_item_value", 0)) > 0:
		best_item_str = "%s（%d币）" % [str(game.rules.profile.get("best_item_title", "")), int(game.rules.profile.get("best_item_value", 0))]
	comp_stats_label.text = "全馆 %d 件 · 高阶奇珍 %d/%d  |  大红 %d · 大金 %d · 小金 %d  |  最高单局 %d 币  |  镇馆：%s" % [
		total_all, col_arr.size(), total_col,
		int(game.rules.profile.get("red_extracted", 0)),
		int(game.rules.profile.get("gold_extracted", 0)),
		int(game.rules.profile.get("small_gold_extracted", 0)),
		int(game.rules.profile.get("best_haul", 0)),
		best_item_str
	]

	for r in [7, 6, 5, 4, 3, 2, 1]:
		for entry in game.Rules.LOOT_TABLE[r]:
			var unlocked: bool = (r <= 3) or (str(entry.title) in col_arr)
			var r_col: Color = game.Rules.RARITY_COLORS[r]
			var card := Panel.new()
			card.custom_minimum_size = Vector2(332, 122)
			var st := StyleBoxFlat.new()
			st.bg_color = Color(r_col.r * 0.16, r_col.g * 0.14, r_col.b * 0.17, 0.95) if unlocked else Color(0.03, 0.06, 0.07, 0.80)
			st.border_color = r_col if unlocked else Color(0.32, 0.45, 0.42, 0.35)
			st.set_border_width_all(2 if r >= 5 else 1)
			st.set_corner_radius_all(8)
			card.add_theme_stylebox_override("panel", st)

			var ic := create_icon(entry, r_col, Vector2(60, 60), not unlocked)
			ic.position = Vector2(10, 10)
			card.add_child(ic)

			var title_txt: String = str(entry.title) if unlocked else "？？？ · 待搜刮带出"
			var head_lbl: Label = game._text(card, "【%s】 %s" % [game.Rules.RARITY_NAMES[r], title_txt], Vector2(76, 8), Vector2(246, 22), 14, r_col if unlocked else Color("779188"))
			head_lbl.clip_text = true
			var en_txt: String = ("🔊 %s  ·  基准 %d 币" % [str(entry.en), int(entry.value)]) if unlocked else "进山搜刮盲盒/隐蔽角落并撤离解锁"
			var ce_lbl: Label = game._text(card, en_txt, Vector2(76, 30), Vector2(246, 20), 11, game.MINT if unlocked else Color("607a72"))
			ce_lbl.clip_text = true
			var clean_lore: String = str(entry.lore).replace("【旷世·大红】", "").replace("【传说·大金】", "").replace("【珍品·小金】", "").strip_edges()
			var lore_w: float = 228.0 if unlocked else 306.0
			var lore_lbl: Label = game._text(card, clean_lore if unlocked else "尚未收录该烟山奇珍实物标本。", Vector2(12, 74), Vector2(lore_w, 42), 11, Color("cfe3d8") if unlocked else Color("587068"))
			lore_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			lore_lbl.clip_text = true
			lore_lbl.max_lines_visible = 2
			lore_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lore_lbl.set_deferred("size", Vector2(lore_w, 42))
			lore_lbl.offset_left = 12.0
			lore_lbl.offset_right = 12.0 + lore_w
			lore_lbl.offset_top = 74.0
			lore_lbl.offset_bottom = 116.0

			if unlocked:
				var b_view: Button = game._button(card, "3D检视", Rect2(252, 76, 70, 34), func():
					inspect_return_to = "compendium"
					close_compendium()
					open_inspect_item(entry)
				)
				b_view.add_theme_font_size_override("font_size", 12)
			comp_grid.add_child(card)


func _render_achievements_tab():
	var ach = game.achievements
	if not is_instance_valid(ach):
		comp_stats_label.text = "成就系统初始化中…"
		return
	var eq_id: String = ach.equipped_charm()
	var eq_name: String = str(ach.CHARMS.get(eq_id, {}).get("name", "未挂载")) if eq_id != "" else "未挂载"
	comp_stats_label.text = "已解锁成就 %d/%d  |  已解锁枪械挂件 %d/%d  |  当前枪下挂件：%s（点击已解锁徽章即可挂上步枪！）" % [
		ach.unlocked_count(), ach.total_count(), ach.unlocked_charm_count(), ach.CHARMS.size(), eq_name
	]

	for item in ach.CATALOG:
		var aid := str(item.id)
		var is_done: bool = ach.is_unlocked(aid)
		var cur_v: int = ach.stat_value(str(item.stat))
		var tgt_v: int = maxi(1, int(item.target))
		var ratio: float = clampf(float(cur_v) / float(tgt_v), 0.0, 1.0)
		var cid := str(item.get("charm", ""))
		var charm_spec: Dictionary = ach.CHARMS.get(cid, {})
		var charm_name := str(charm_spec.get("name", ""))
		var is_equipped: bool = cid != "" and eq_id == cid

		var card := Panel.new()
		card.custom_minimum_size = Vector2(332, 126)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.14, 0.12, 0.055, 0.96) if is_done else Color(0.032, 0.062, 0.072, 0.86)
		st.border_color = Color("ffd15c") if is_done else Color(0.32, 0.45, 0.42, 0.42)
		st.set_border_width_all(2 if is_done else 1)
		st.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", st)

		var badge_bg := ColorRect.new()
		badge_bg.position = Vector2(10, 10)
		badge_bg.size = Vector2(46, 46)
		badge_bg.color = Color(0.26, 0.20, 0.07, 0.95) if is_done else Color(0.08, 0.12, 0.14, 0.90)
		card.add_child(badge_bg)
		var icon_l: Label = game._text(card, str(item.get("icon", "🏆")), Vector2(10, 12), Vector2(46, 42), 24, Color("ffd866") if is_done else Color("69827a"))
		icon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var head: Label = game._text(card, "[%s] %s" % [str(item.cat), str(item.title)], Vector2(64, 8), Vector2(258, 22), 14, Color("ffd866") if is_done else Color("b4cdc3"))
		head.clip_text = true
		var desc_l: Label = game._text(card, str(item.desc), Vector2(64, 30), Vector2(258, 20), 11, Color("e6f2e8") if is_done else Color("779188"))
		desc_l.clip_text = true

		# Progress bar
		var pb_bg := ColorRect.new()
		pb_bg.position = Vector2(12, 62)
		pb_bg.size = Vector2(216, 10)
		pb_bg.color = Color(0.06, 0.11, 0.12, 0.95)
		card.add_child(pb_bg)
		var pb_fill := ColorRect.new()
		pb_fill.position = Vector2(12, 62)
		pb_fill.size = Vector2(216.0 * ratio, 10)
		pb_fill.color = Color("ffd15c") if is_done else Color("4ec9a4")
		card.add_child(pb_fill)
		var prog_l: Label = game._text(card, "%d / %d" % [mini(cur_v, tgt_v), tgt_v], Vector2(234, 57), Vector2(88, 18), 11, Color("ffd866") if is_done else Color("89a69d"))
		prog_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		var reward_lbl: Label = game._text(card, "挂件：%s" % (charm_name if charm_name != "" else "荣誉称号"), Vector2(12, 82), Vector2(214, 34), 12, game.MINT if is_done else Color("607a72"))
		reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_lbl.clip_text = true

		if is_done and cid != "":
			var btn_txt := "✓ 已挂载" if is_equipped else "装配挂件"
			var b_eq: Button = game._button(card, btn_txt, Rect2(232, 82, 88, 32), func():
				ach.equip_charm(cid)
				_refresh_compendium_ui()
			)
			b_eq.add_theme_font_size_override("font_size", 12)
			if is_equipped:
				game._style_tactical_button(b_eq, Color("204d3e"), Color("7af5cc"), Color("e8fff5"))
		else:
			var lock_l: Label = game._text(card, "待解锁", Vector2(232, 88), Vector2(88, 22), 12, Color("5a7068"))
			lock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		comp_grid.add_child(card)
