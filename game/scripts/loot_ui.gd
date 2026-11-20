extends Node
## v0.7.2 Museum-Grade Extraction Looting UI:
## - 32 unique Blender 4.5 Cycles studio-rendered 256x256 RGBA item icons (1:1 matching 3D models)
## - 32 unique sculpted multi-material PBR 3D collectibles from assets/slice/v072_collectibles.glb
## - HUD Tactile Quick-Search bar & '出大红/出大金' Jackpot Toast Banner
## - [B] Tactical Backpack Grid & Loot Appraisal / Discard Manager
## - [I] Interactive 360° Mouse-Drag & Zoom 3D Relic Showcase Inspector + Camp Bilingual Treasure Compendium

const COLLECTIBLE_GLB := "res://assets/slice/v072_collectibles.glb"
const ICON_DIR := "res://assets/icons/loot/"

const TITLE_TO_ART_ID := {
	"旧巡护电池": "battery",
	"压缩干粮": "ration",
	"信号铜线": "wire",
	"诚庄春茶饼": "tea",
	"青竹编织哨": "bamboo",
	"林间指北针": "compass",
	"防水战术手电": "torch",
	"巡护员徽章": "badge",
	"烟山手工折扇": "fan",
	"溪石萤光矿": "gem",
	"加密无线电台": "radio",
	"光学测距模块": "rangefinder",
	"古树琥珀标本": "amber",
	"军规夜视镜片": "nvg_lens",
	"太湖透漏赏石": "rock",
	"无人机核心芯片": "chip",
	"竹海古玉残片": "jade_piece",
	"军用黑匣子": "blackbox",
	"烟霞岩画残拓": "rubbing",
	"古樟祈福银锁": "silver_lock",
	"先民青铜茶铫": "kettle",
	"烟山古铜虎符": "tally",
	"特级金质勋章": "medal",
	"量子词典原型机": "quantum",
	"烟山先民竹简": "slips",
	"烟山统领黄金核心": "core",
	"望稻亭鎏金香炉": "censer",
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

# Top-center Jackpot Toast Banner
var toast_panel: Panel
var toast_icon_holder: Control
var toast_header: Label
var toast_name: Label
var toast_sub: Label
var toast_left: float = 0.0
var toast_rarity: int = 1

# Center Tactile Quick-Search Bar (Bird Nests & Rock Crevices)
var search_panel: Panel
var search_label: Label
var search_bar_fill: ColorRect
var active_search_node: Node3D = null
var search_elapsed: float = 0.0
var search_duration: float = 0.92

# [B] Tactical Backpack Modal
var bag_overlay: Control
var bag_header_label: Label
var bag_grid: GridContainer
var bag_status_label: Label

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

# Camp Bilingual Treasure Compendium ('烟山奇珍图鉴')
var comp_overlay: Control
var comp_stats_label: Label
var comp_grid: GridContainer


func setup(g):
	game = g
	_build_toast_and_search_hud()
	_build_backpack_modal()
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
	return busy_bag or busy_inspect or busy_compendium


func close_all_modals():
	if busy_inspect:
		close_inspect()
	if busy_bag:
		close_backpack()
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
	var r: int = clampi(int(item.get("rarity", 1)), 1, 6)
	toast_rarity = r
	var r_col: Color = game.Rules.RARITY_COLORS[r]
	var r_name: String = game.Rules.RARITY_NAMES[r]
	var cond: String = str(item.get("cond", "标准"))
	var cond_tag: String = (" · ✦" + cond) if cond in ["极品孤本", "崭新"] else (" · " + cond if cond != "标准" else "")

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.18, 0.04, 0.06, 0.96) if r == 6 else (Color(0.14, 0.11, 0.04, 0.95) if r == 5 else Color(0.05, 0.10, 0.13, 0.94))
	st.border_color = r_col
	st.set_border_width_all(3 if r >= 5 else 2)
	st.set_corner_radius_all(8)
	toast_panel.add_theme_stylebox_override("panel", st)

	for ch in toast_icon_holder.get_children():
		ch.queue_free()
	toast_icon_holder.add_child(create_icon(item, r_col, Vector2(56, 56)))

	if r == 6:
		toast_header.text = "🔥 出大红了！！【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.screen_flash.color = Color(1.0, 0.26, 0.32, 0.24)
		game.play_sfx("loot_mythic_red", -7)
	elif r == 5:
		toast_header.text = "✦ 摸出大金！【%s%s】 · %s" % [r_name, cond_tag, source_tag]
		game.screen_flash.color = Color(1.0, 0.82, 0.30, 0.18)
		game.play_sfx("loot_epic", -9)
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
	toast_sub.text = "鉴定估值 +%d 币（占格 %s）  |  按 [I] 3D检视宝物 · [B] 整理背包" % [
		int(item.get("value", 0)), str(item.get("grid", "1×1"))
	]
	toast_left = 4.8 if r >= 5 else (3.6 if r >= 3 else 2.4)
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
			toast_header.modulate = Color(1.0, pulse + 0.22, pulse, 1.0) if toast_rarity == 6 else Color(1.0, 0.95, pulse, 1.0)
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
# [B] TACTICAL BACKPACK & APPRAISAL OVERLAY
# ---------------------------------------------------------------------------
func _build_backpack_modal():
	bag_overlay = Control.new()
	bag_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(bag_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.055, 0.90)
	bag_overlay.add_child(veil)

	game._panel(bag_overlay, Rect2(110, 56, 1060, 608), Color(0.045, 0.095, 0.118, 0.98), Color(0.46, 0.82, 0.68, 0.55))
	bag_header_label = game._text(bag_overlay, "随身摸金背包 · 战利品鉴定与整理", Vector2(146, 80), Vector2(820, 34), 22, game.MINT)
	bag_header_label.clip_text = true
	game._button(bag_overlay, "关闭背包 [B/Esc]", Rect2(980, 76, 156, 38), close_backpack)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(146, 130)
	scroll.size = Vector2(988, 456)
	bag_overlay.add_child(scroll)

	bag_grid = GridContainer.new()
	bag_grid.columns = 4
	bag_grid.add_theme_constant_override("h_separation", 14)
	bag_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(bag_grid)

	bag_status_label = game._text(bag_overlay, "点击「读音」听美式自然发音；点击「3D检视」可鼠标拖拽 360° 细看藏品纹理与雕工！", Vector2(146, 602), Vector2(988, 32), 14, Color("9ec4b5"))
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
	for ch in bag_grid.get_children():
		ch.queue_free()
	var cap: int = game.rules.capacity()
	var total_val: int = game.rules.bag_value()
	bag_header_label.text = "随身摸金背包（%d / %d 格） · 当前总估值 %d 币%s" % [
		game.rules.bag.size(), cap, total_val,
		"（机密估值×1.35已生效）" if game.rules.is_confidential() else ""
	]

	for slot_i in cap:
		var card := Panel.new()
		card.custom_minimum_size = Vector2(232, 138)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(8)
		if slot_i < game.rules.bag.size():
			var item: Dictionary = game.rules.bag[slot_i]
			var r: int = clampi(int(item.get("rarity", 1)), 1, 6)
			var r_col: Color = game.Rules.RARITY_COLORS[r]
			st.bg_color = Color(r_col.r * 0.16, r_col.g * 0.15, r_col.b * 0.18, 0.96)
			st.border_color = r_col
			st.set_border_width_all(3 if r >= 5 else 2)
			card.add_theme_stylebox_override("panel", st)

			var ic := create_icon(item, r_col, Vector2(54, 54))
			ic.position = Vector2(10, 10)
			card.add_child(ic)

			var r_badge: String = "【%s · %s】" % [game.Rules.RARITY_NAMES[r], str(item.get("cond", "标准"))]
			game._text(card, r_badge, Vector2(70, 8), Vector2(154, 20), 12, r_col)
			var t_lbl: Label = game._text(card, str(item.get("title", "物资")), Vector2(70, 28), Vector2(154, 22), 15, game.CREAM)
			t_lbl.clip_text = true
			var e_lbl: Label = game._text(card, "🔊 " + str(item.get("en", "Supply")), Vector2(70, 50), Vector2(152, 18), 11, Color("9adbc0"))
			e_lbl.clip_text = true
			e_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			game._text(card, "估值 %d 币 · %s" % [int(item.get("value", 0)), str(item.get("grid", "1×1"))], Vector2(12, 74), Vector2(208, 20), 13, game.GOLD)

			var btn_speak: Button = game._button(card, "读音", Rect2(10, 100, 62, 28), func(): game.speak_english(str(item.get("en", ""))))
			btn_speak.add_theme_font_size_override("font_size", 12)
			var btn_insp: Button = game._button(card, "3D检视", Rect2(78, 100, 74, 28), func():
				close_backpack()
				open_inspect_item(item)
			)
			btn_insp.add_theme_font_size_override("font_size", 12)
			var btn_drop: Button = game._button(card, "丢弃", Rect2(158, 100, 64, 28), _discard_slot.bind(slot_i))
			btn_drop.add_theme_font_size_override("font_size", 12)
		else:
			st.bg_color = Color(0.03, 0.06, 0.08, 0.65)
			st.border_color = Color(0.35, 0.55, 0.48, 0.25)
			st.set_border_width_all(1)
			card.add_theme_stylebox_override("panel", st)
			var empty_l: Label = game._text(card, "空闲槽位 #%d\n探索物资箱/鸟窝/桌面搜刮" % (slot_i + 1), Vector2(14, 46), Vector2(204, 48), 13, Color("6c8d80"))
			empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag_grid.add_child(card)


func _discard_slot(idx: int):
	var removed: Dictionary = game.rules.discard_bag_item(idx)
	if not removed.is_empty():
		game.play_sfx("loot_reveal_common", -13)
		bag_status_label.text = "已丢弃【%s（%d币）】，腾出 1 格随身背包空间。" % [str(removed.get("title", "")), int(removed.get("value", 0))]
		_refresh_backpack_ui()


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

	inspect_lore_label = game._text(inspect_overlay, "", Vector2(638, 250), Vector2(412, 188), 17, game.CREAM)
	inspect_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	game._button(inspect_overlay, "🔊 朗读宝物英文名称", Rect2(638, 460, 240, 46), func():
		if not inspect_item_data.is_empty():
			game.speak_english(str(inspect_item_data.get("en", "")))
	, true)

	game._text(inspect_overlay, "带出撤离信标即可永久点亮营地【烟山奇珍图鉴】，随时回味 32 件独立建模奇珍！", Vector2(238, 608), Vector2(810, 26), 14, Color("9ec4b5"))
	inspect_overlay.hide()


func inspect_best_in_bag():
	if game.rules.phase not in ["active", "extracting"]:
		return
	if busy_inspect:
		close_inspect()
		return
	if game.rules.bag.is_empty():
		game._notice("随身背包暂无战利品，快去搜刮物资箱、桌面或鸟窝吧！", game.GOLD)
		return
	var best: Dictionary = game.rules.bag[0]
	for it in game.rules.bag:
		if int(it.get("rarity", 1)) > int(best.get("rarity", 1)) or (int(it.get("rarity", 1)) == int(best.get("rarity", 1)) and int(it.get("value", 0)) > int(best.get("value", 0))):
			best = it
	open_inspect_item(best)


func open_inspect_item(item: Dictionary):
	close_all_modals()
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

	var r: int = clampi(int(item.get("rarity", 1)), 1, 6)
	var r_col: Color = game.Rules.RARITY_COLORS[r]
	inspect_title.text = "【%s】%s" % [game.Rules.RARITY_NAMES[r], str(item.get("title", "宝物"))]
	inspect_title.add_theme_color_override("font_color", r_col)
	inspect_en_label.text = str(item.get("en", "Treasure"))
	inspect_meta_label.text = "鉴定成色：%s  |  占格：%s\n当前估值：%d 币" % [
		str(item.get("cond", "标准")), str(item.get("grid", "1×1")), int(item.get("value", 0))
	]
	inspect_lore_label.text = "【烟山风物与战术档案】\n" + str(item.get("lore", ""))

	for ch in inspect_icon_holder.get_children():
		ch.queue_free()
	inspect_icon_holder.add_child(create_icon(item, r_col, Vector2(88, 88)))

	if is_instance_valid(inspect_rim_light):
		inspect_rim_light.light_color = r_col.lightened(0.18)

	_populate_3d_turntable(item, r, r_col)
	game.speak_english(str(item.get("en", "")))
	game.play_sfx("loot_mythic_red" if r == 6 else ("loot_epic" if r >= 4 else "loot_reveal_rare"), -10)
	inspect_overlay.show()


func close_inspect():
	if not busy_inspect:
		return
	busy_inspect = false
	inspect_dragging = false
	inspect_overlay.hide()
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
	velvet_mat.albedo_color = Color("261116") if rarity == 6 else Color("132629")
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
	## Used both on open-world stone pedestals and in the [I] 360° 3D Turntable Showcase!
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
# CAMP BILINGUAL TREASURE COMPENDIUM ('烟山奇珍图鉴 · v0.7.2')
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
	game._text(comp_overlay, "🏆 烟山奇珍图鉴 · 摸金大红与江南风物双语馆", Vector2(122, 68), Vector2(760, 36), 27, Color("ffd15c"))
	game._button(comp_overlay, "返回营地", Rect2(1020, 68, 138, 38), close_compendium)

	comp_stats_label = game._text(comp_overlay, "", Vector2(122, 108), Vector2(880, 26), 15, game.MINT)

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


func open_compendium():
	busy_compendium = true
	_refresh_compendium_ui()
	comp_overlay.show()


func close_compendium():
	busy_compendium = false
	comp_overlay.hide()


func _refresh_compendium_ui():
	for ch in comp_grid.get_children():
		ch.queue_free()
	var col_arr: Array = game.rules.profile.collection
	var total_col: int = game.Rules.total_collectible_count()
	var best_item_str: String = "暂无纪录"
	if int(game.rules.profile.get("best_item_value", 0)) > 0:
		best_item_str = "%s（%d币）" % [str(game.rules.profile.get("best_item_title", "")), int(game.rules.profile.get("best_item_value", 0))]
	comp_stats_label.text = "已点亮高阶奇珍：%d / %d 件  |  累计带出【旷世·大红】%d 件 · 【传说·大金】%d 件  |  单局最高摸金：%d 币  |  镇馆之宝：%s" % [
		col_arr.size(), total_col,
		int(game.rules.profile.get("red_extracted", 0)),
		int(game.rules.profile.get("gold_extracted", 0)),
		int(game.rules.profile.get("best_haul", 0)),
		best_item_str
	]

	for r in [6, 5, 4, 3, 2, 1]:
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
			var en_txt: String = ("🔊 %s  ·  基准 %d 币" % [str(entry.en), int(entry.value)]) if unlocked else "进山搜刮物资箱/桌面/鸟窝并撤离解锁"
			var ce_lbl: Label = game._text(card, en_txt, Vector2(76, 30), Vector2(246, 20), 11, game.MINT if unlocked else Color("607a72"))
			ce_lbl.clip_text = true
			var clean_lore: String = str(entry.lore).replace("【旷世·大红】", "").replace("【传说·大金】", "").strip_edges()
			var lore_lbl: Label = game._text(card, clean_lore if unlocked else "尚未收录该烟山奇珍实物标本。", Vector2(12, 74), Vector2(234 if unlocked else 306, 44), 11, Color("cfe3d8") if unlocked else Color("587068"))
			lore_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			lore_lbl.size = Vector2(234 if unlocked else 306, 44)
			lore_lbl.max_lines_visible = 2
			lore_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

			if unlocked:
				var b_view: Button = game._button(card, "3D检视", Rect2(254, 76, 68, 34), func():
					close_compendium()
					open_inspect_item(entry)
				)
				b_view.add_theme_font_size_override("font_size", 12)
			comp_grid.add_child(card)
