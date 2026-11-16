extends Node
## v0.6.3 True Extraction Looting UI:
## - Crisp procedural vector item icons across all 32 items & 6 rarity tiers (White -> Crimson Mythic Red '旷世·大红')
## - HUD Tactile Quick-Search bar (for Bird Nests / Rock Crevices) & '出大红/出大金' Jackpot Toast Banner
## - [B] Tactical Backpack Grid & Loot Appraisal / Discard Manager
## - [I] Rotating 3D Relic Showcase Inspector + Camp Bilingual Treasure Compendium ('烟山双语奇珍图鉴')

class LootIconCanvas extends Control:
	var icon_kind: String = "core"
	var accent: Color = Color("ffd15c")

	func _draw():
		var w: float = size.x
		var h: float = size.y
		var c: Vector2 = Vector2(w * 0.5, h * 0.5)
		var r: float = minf(w, h) * 0.38
		var soft_bg: Color = Color(accent.r, accent.g, accent.b, 0.16)
		var bright: Color = accent.lightened(0.28)
		var dark: Color = accent.darkened(0.38)
		draw_circle(c, r * 1.12, soft_bg)

		match icon_kind:
			"celadon":
				# Lotus-petal Secret Celadon Bowl ('越窑秘色青瓷盏')
				var bowl := PackedVector2Array([
					c + Vector2(-r * 0.95, -r * 0.18),
					c + Vector2(r * 0.95, -r * 0.18),
					c + Vector2(r * 0.62, r * 0.52),
					c + Vector2(-r * 0.62, r * 0.52)
				])
				draw_colored_polygon(bowl, Color("7ed6be"))
				draw_arc(c + Vector2(0, -r * 0.18), r * 0.95, 0.0, PI, 18, bright, 2.2, true)
				draw_rect(Rect2(c.x - r * 0.36, c.y + r * 0.52, r * 0.72, r * 0.20), Color("58b39b"))
				draw_circle(c + Vector2(0, -r * 0.55), r * 0.16, bright)
			"ganoderma":
				# Millennium Purple-Crimson Ganoderma ('烟山千年紫芝王')
				draw_line(c + Vector2(-r * 0.08, r * 0.82), c + Vector2(r * 0.08, -r * 0.05), Color("b85d43"), 4.2, true)
				draw_circle(c + Vector2(-r * 0.18, -r * 0.18), r * 0.58, accent)
				draw_circle(c + Vector2(r * 0.28, -r * 0.06), r * 0.46, bright)
				draw_arc(c + Vector2(-r * 0.16, -r * 0.18), r * 0.44, PI * 1.08, PI * 1.92, 14, Color("ffd88a"), 2.0, true)
			"seal":
				# Heart of Yanshan Crimson-Gold Dragon Seal ('烟山之心·赤金龙印')
				draw_rect(Rect2(c.x - r * 0.72, c.y - r * 0.02, r * 1.44, r * 0.78), Color("ffd15c"))
				draw_rect(Rect2(c.x - r * 0.72, c.y - r * 0.02, r * 1.44, r * 0.78), bright, false, 2.0)
				var gem := PackedVector2Array([
					c + Vector2(0, -r * 0.88),
					c + Vector2(r * 0.48, -r * 0.32),
					c + Vector2(0, r * 0.14),
					c + Vector2(-r * 0.48, -r * 0.32)
				])
				draw_colored_polygon(gem, Color("ff3b4e"))
				draw_polyline(PackedVector2Array([gem[0], gem[1], gem[2], gem[3], gem[0]]), Color("fff0d4"), 1.8, true)
			"radar_heart":
				# Quantum Phased-Array Radar Core ('相控阵超算雷达心')
				var hex := PackedVector2Array()
				for i in 6:
					var a: float = float(i) * TAU / 6.0 - PI * 0.5
					hex.append(c + Vector2(cos(a), sin(a)) * r * 0.92)
				draw_colored_polygon(hex, dark)
				for i in 6:
					draw_line(hex[i], hex[(i + 1) % 6], bright, 2.0, true)
				draw_circle(c, r * 0.42, Color("ff4757"))
				draw_arc(c, r * 0.64, 0, TAU, 20, Color("ffd15c"), 1.6, true)
			"jade":
				# Carved Bi-Disc ('双龙玉璧 / 竹海古玉')
				draw_circle(c, r * 0.86, accent.lerp(Color("9ff0d4"), 0.45))
				draw_circle(c, r * 0.32, Color(0.06, 0.11, 0.13, 0.96))
				draw_arc(c, r * 0.60, 0.4, 2.5, 12, bright, 1.8, true)
				draw_arc(c, r * 0.60, 3.5, 5.6, 12, bright, 1.8, true)
			"slips":
				# Bound Ancient Bamboo Slips ('烟山先民竹简')
				for i in 5:
					var bx: float = c.x - r * 0.72 + float(i) * r * 0.32
					draw_rect(Rect2(bx, c.y - r * 0.76, r * 0.22, r * 1.52), Color("d9b46e"))
				draw_line(c + Vector2(-r * 0.80, -r * 0.38), c + Vector2(r * 0.80, -r * 0.38), Color("7a4928"), 2.2)
				draw_line(c + Vector2(-r * 0.80, r * 0.38), c + Vector2(r * 0.80, r * 0.38), Color("7a4928"), 2.2)
			"tally":
				# Bronze Tiger Tally ('烟山古铜虎符')
				var body := PackedVector2Array([
					c + Vector2(-r * 0.88, r * 0.28),
					c + Vector2(-r * 0.62, -r * 0.38),
					c + Vector2(r * 0.35, -r * 0.26),
					c + Vector2(r * 0.88, -r * 0.52),
					c + Vector2(r * 0.82, r * 0.34)
				])
				draw_colored_polygon(body, Color("d8a648"))
				draw_line(c + Vector2(-r * 0.42, -r * 0.05), c + Vector2(r * 0.42, -r * 0.05), bright, 2.0)
			"core", "quantum":
				draw_circle(c, r * 0.78, dark)
				draw_arc(c, r * 0.78, 0, TAU, 24, bright, 2.4, true)
				var dia := PackedVector2Array([
					c + Vector2(0, -r * 0.56), c + Vector2(r * 0.56, 0),
					c + Vector2(0, r * 0.56), c + Vector2(-r * 0.56, 0)
				])
				draw_colored_polygon(dia, accent)
			"medal", "badge":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.38, -r * 0.84), c + Vector2(r * 0.38, -r * 0.84),
					c + Vector2(r * 0.18, -r * 0.12), c + Vector2(-r * 0.18, -r * 0.12)
				]), Color("4d88cf"))
				draw_circle(c + Vector2(0, r * 0.22), r * 0.54, accent)
				draw_circle(c + Vector2(0, r * 0.22), r * 0.32, bright)
			"rubbing":
				draw_rect(Rect2(c.x - r * 0.66, c.y - r * 0.76, r * 1.32, r * 1.52), Color("4f5954"))
				draw_rect(Rect2(c.x - r * 0.50, c.y - r * 0.58, r * 1.00, r * 1.16), Color("d5d0c1"), false, 1.8)
				draw_line(c + Vector2(-r * 0.32, -r * 0.25), c + Vector2(r * 0.32, -r * 0.25), bright, 2.0)
				draw_line(c + Vector2(-r * 0.32, r * 0.08), c + Vector2(r * 0.22, r * 0.08), bright, 2.0)
			"kettle":
				draw_circle(c + Vector2(0, r * 0.14), r * 0.58, accent)
				draw_arc(c + Vector2(0, -r * 0.24), r * 0.44, PI, TAU, 14, bright, 2.4, true)
				draw_line(c + Vector2(r * 0.46, r * 0.05), c + Vector2(r * 0.86, -r * 0.26), bright, 3.0)
			"chip", "blackbox":
				draw_rect(Rect2(c.x - r * 0.62, c.y - r * 0.56, r * 1.24, r * 1.12), accent)
				draw_rect(Rect2(c.x - r * 0.38, c.y - r * 0.32, r * 0.76, r * 0.64), dark)
				for k in [-0.36, 0.0, 0.36]:
					draw_line(c + Vector2(r * k, -r * 0.82), c + Vector2(r * k, -r * 0.56), bright, 2.0)
					draw_line(c + Vector2(r * k, r * 0.56), c + Vector2(r * k, r * 0.82), bright, 2.0)
			"radio":
				draw_rect(Rect2(c.x - r * 0.46, c.y - r * 0.32, r * 0.92, r * 1.08), accent)
				draw_line(c + Vector2(r * 0.24, -r * 0.32), c + Vector2(r * 0.24, -r * 0.88), bright, 2.6)
				draw_circle(c + Vector2(0, r * 0.26), r * 0.22, dark)
			"compass":
				draw_circle(c, r * 0.76, dark)
				draw_arc(c, r * 0.76, 0, TAU, 22, accent, 2.2, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.58), c + Vector2(r * 0.18, 0), c + Vector2(-r * 0.18, 0)]), Color("ff5c66"))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.58), c + Vector2(r * 0.18, 0), c + Vector2(-r * 0.18, 0)]), Color("dce8e2"))
			"amber", "gem", "rock":
				var poly := PackedVector2Array([
					c + Vector2(-r * 0.22, -r * 0.80), c + Vector2(r * 0.58, -r * 0.42),
					c + Vector2(r * 0.72, r * 0.36), c + Vector2(-r * 0.12, r * 0.78),
					c + Vector2(-r * 0.74, r * 0.18)
				])
				draw_colored_polygon(poly, accent)
				draw_circle(c + Vector2(r * 0.08, -r * 0.12), r * 0.20, bright)
			"fan":
				draw_arc(c + Vector2(0, r * 0.48), r * 0.96, PI * 1.15, PI * 1.85, 18, accent, r * 0.56, true)
				for a_deg in [-32.0, -16.0, 0.0, 16.0, 32.0]:
					var rad: float = deg_to_rad(a_deg - 90.0)
					draw_line(c + Vector2(0, r * 0.48), c + Vector2(0, r * 0.48) + Vector2(cos(rad), sin(rad)) * r * 1.05, bright, 1.5)
			_:
				draw_rect(Rect2(c.x - r * 0.62, c.y - r * 0.48, r * 1.24, r * 0.96), accent)
				draw_rect(Rect2(c.x - r * 0.62, c.y - r * 0.48, r * 1.24, r * 0.96), bright, false, 1.8)
				draw_circle(c, r * 0.22, bright)


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

# [I] Rotating 3D Relic Showcase Inspector
var inspect_overlay: Control
var inspect_title: Label
var inspect_en_label: Label
var inspect_meta_label: Label
var inspect_lore_label: Label
var inspect_icon_holder: Control
var inspect_vp: SubViewport
var inspect_turntable: Node3D
var inspect_item_data: Dictionary = {}

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

static func create_icon(icon_kind: String, col: Color, sz: Vector2) -> Control:
	var ic := LootIconCanvas.new()
	ic.icon_kind = icon_kind
	ic.accent = col
	ic.custom_minimum_size = sz
	ic.size = sz
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic

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
	toast_icon_holder.add_child(create_icon(str(item.get("icon", "core")), r_col, Vector2(56, 56)))

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
		inspect_turntable.rotation.y += delta * 1.15
		inspect_turntable.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.04

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

	bag_status_label = game._text(bag_overlay, "点击任意宝物卡片可听标准英文发音；高价值大金/大红可点「3D检视」，低值杂物可点「丢弃」腾出格子。", Vector2(146, 602), Vector2(988, 32), 14, Color("9ec4b5"))
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
		card.custom_minimum_size = Vector2(232, 134)
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

			card.add_child(create_icon(str(item.get("icon", "core")), r_col, Vector2(46, 46)))
			card.get_child(card.get_child_count() - 1).position = Vector2(10, 12)

			var r_badge: String = "【%s · %s】" % [game.Rules.RARITY_NAMES[r], str(item.get("cond", "标准"))]
			game._text(card, r_badge, Vector2(60, 8), Vector2(164, 20), 12, r_col)
			var t_lbl: Label = game._text(card, str(item.get("title", "物资")), Vector2(60, 28), Vector2(164, 22), 15, game.CREAM)
			t_lbl.clip_text = true
			var e_lbl: Label = game._text(card, "🔊 " + str(item.get("en", "Supply")), Vector2(60, 50), Vector2(162, 18), 11, Color("9adbc0"))
			e_lbl.clip_text = true
			e_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			game._text(card, "估值 %d 币 · %s" % [int(item.get("value", 0)), str(item.get("grid", "1×1"))], Vector2(12, 72), Vector2(208, 20), 13, game.GOLD)

			var btn_speak: Button = game._button(card, "读音", Rect2(10, 96, 62, 28), func(): game.speak_english(str(item.get("en", ""))))
			btn_speak.add_theme_font_size_override("font_size", 12)
			var btn_insp: Button = game._button(card, "3D检视", Rect2(78, 96, 74, 28), func():
				close_backpack()
				open_inspect_item(item)
			)
			btn_insp.add_theme_font_size_override("font_size", 12)
			var btn_drop: Button = game._button(card, "丢弃", Rect2(158, 96, 64, 28), _discard_slot.bind(slot_i))
			btn_drop.add_theme_font_size_override("font_size", 12)
		else:
			st.bg_color = Color(0.03, 0.06, 0.08, 0.65)
			st.border_color = Color(0.35, 0.55, 0.48, 0.25)
			st.set_border_width_all(1)
			card.add_theme_stylebox_override("panel", st)
			var empty_l: Label = game._text(card, "空闲槽位 #%d\n探索物资箱/鸟窝/桌面搜刮" % (slot_i + 1), Vector2(14, 44), Vector2(204, 48), 13, Color("6c8d80"))
			empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag_grid.add_child(card)

func _discard_slot(idx: int):
	var removed: Dictionary = game.rules.discard_bag_item(idx)
	if not removed.is_empty():
		game.play_sfx("loot_reveal_common", -13)
		bag_status_label.text = "已丢弃【%s（%d币）】，腾出 1 格随身背包空间。" % [str(removed.get("title", "")), int(removed.get("value", 0))]
		_refresh_backpack_ui()

# ---------------------------------------------------------------------------
# [I] ROTATING 3D RELIC INSPECT SHOWCASE
# ---------------------------------------------------------------------------
func _build_inspect_modal():
	inspect_overlay = Control.new()
	inspect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(inspect_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.035, 0.045, 0.92)
	inspect_overlay.add_child(veil)

	game._panel(inspect_overlay, Rect2(210, 74, 860, 572), Color(0.045, 0.085, 0.108, 0.98), Color("ffd15c"))
	inspect_title = game._text(inspect_overlay, "宝物 3D 检视台", Vector2(248, 96), Vector2(600, 38), 28, Color("ffd15c"))
	game._button(inspect_overlay, "收起返回 [I/Esc]", Rect2(886, 94, 152, 38), close_inspect)

	# Dedicated 3D SubViewport Relic Turntable!
	var vp_frame: Panel = game._panel(inspect_overlay, Rect2(248, 150, 360, 360), Color(0.025, 0.05, 0.065, 1.0), Color(0.55, 0.82, 0.70, 0.35))
	var vpc := SubViewportContainer.new()
	vpc.position = Vector2(6, 6)
	vpc.size = Vector2(348, 348)
	vpc.stretch = true
	vp_frame.add_child(vpc)

	inspect_vp = SubViewport.new()
	inspect_vp.size = Vector2i(348, 348)
	inspect_vp.own_world_3d = true
	inspect_vp.transparent_bg = true
	inspect_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vpc.add_child(inspect_vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.42, 1.65)
	cam.look_at_from_position(Vector3(0.0, 0.42, 1.65), Vector3(0.0, 0.04, 0.0), Vector3.UP)
	cam.fov = 42.0
	inspect_vp.add_child(cam)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38, 32, 0)
	key_light.light_energy = 1.45
	inspect_vp.add_child(key_light)

	var rim_light := OmniLight3D.new()
	rim_light.position = Vector3(-1.2, 0.8, -1.0)
	rim_light.light_color = Color("ffd166")
	rim_light.light_energy = 1.6
	rim_light.omni_range = 5.0
	inspect_vp.add_child(rim_light)

	inspect_turntable = Node3D.new()
	inspect_vp.add_child(inspect_turntable)

	# Right-side Appraisal & Bilingual Lore Card
	inspect_icon_holder = Control.new()
	inspect_icon_holder.position = Vector2(636, 156)
	inspect_icon_holder.size = Vector2(76, 76)
	inspect_overlay.add_child(inspect_icon_holder)

	inspect_en_label = game._text(inspect_overlay, "", Vector2(724, 162), Vector2(314, 34), 22, game.MINT)
	inspect_meta_label = game._text(inspect_overlay, "", Vector2(724, 198), Vector2(314, 52), 15, game.GOLD)
	inspect_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	inspect_lore_label = game._text(inspect_overlay, "", Vector2(636, 268), Vector2(400, 165), 17, game.CREAM)
	inspect_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	game._button(inspect_overlay, "🔊 朗读宝物英文名称", Rect2(636, 456, 230, 46), func():
		if not inspect_item_data.is_empty():
			game.speak_english(str(inspect_item_data.get("en", "")))
	, true)

	game._text(inspect_overlay, "3D 展台自动旋转展示宝物结构 · 带出撤离信标即可永久点亮营地【烟山奇珍图鉴】！", Vector2(248, 530), Vector2(790, 26), 14, Color("9ec4b5"))
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
	inspect_icon_holder.add_child(create_icon(str(item.get("icon", "core")), r_col, Vector2(76, 76)))

	_populate_3d_turntable(str(item.get("icon", "core")), r, r_col)
	game.speak_english(str(item.get("en", "")))
	game.play_sfx("loot_mythic_red" if r == 6 else ("loot_epic" if r >= 4 else "loot_reveal_rare"), -10)
	inspect_overlay.show()

func close_inspect():
	if not busy_inspect:
		return
	busy_inspect = false
	inspect_overlay.hide()
	if game.rules.phase in ["active", "extracting"]:
		game.paused = false
		game.player.active = true
		game.player.clear_movement_input()
		game.hud.show()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _populate_3d_turntable(icon_kind: String, rarity: int, r_col: Color):
	for ch in inspect_turntable.get_children():
		ch.queue_free()
	inspect_turntable.rotation = Vector3.ZERO

	# Glowing display pedestal disc
	var ped_mat := StandardMaterial3D.new()
	ped_mat.albedo_color = Color("1b2a30")
	ped_mat.metallic = 0.45
	ped_mat.roughness = 0.35
	var ped := MeshInstance3D.new()
	var ped_cyl := CylinderMesh.new()
	ped_cyl.top_radius = 0.52
	ped_cyl.bottom_radius = 0.58
	ped_cyl.height = 0.08
	ped.mesh = ped_cyl
	ped.position = Vector3(0, -0.34, 0)
	ped.material_override = ped_mat
	inspect_turntable.add_child(ped)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = r_col
	ring_mat.emission_enabled = true
	ring_mat.emission = r_col
	ring_mat.emission_energy_multiplier = 1.6 if rarity >= 5 else 0.9
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.47
	torus.outer_radius = 0.52
	ring.mesh = torus
	ring.position = Vector3(0, -0.30, 0)
	ring.material_override = ring_mat
	inspect_turntable.add_child(ring)

	var relic_mesh := build_world_loot_mesh(icon_kind, rarity, r_col, 2.15)
	relic_mesh.position = Vector3(0, -0.22, 0)
	inspect_turntable.add_child(relic_mesh)

static func build_world_loot_mesh(icon_kind: String, rarity: int, r_col: Color, scale_mult: float = 1.0) -> Node3D:
	## Lightweight (<64 tris) 3D relic sculpture used both on open-world tables and in the [I] 3D Turntable!
	var root := Node3D.new()
	root.scale = Vector3.ONE * scale_mult

	var main_mat := StandardMaterial3D.new()
	main_mat.albedo_color = r_col.lightened(0.14)
	main_mat.metallic = 0.65 if rarity >= 5 else 0.25
	main_mat.roughness = 0.24 if rarity >= 4 else 0.48
	if rarity >= 4:
		main_mat.emission_enabled = true
		main_mat.emission = r_col
		main_mat.emission_energy_multiplier = 0.65 if rarity == 6 else (0.42 if rarity == 5 else 0.22)

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color("ffd15c") if rarity == 6 else r_col.darkened(0.28)
	accent_mat.metallic = 0.55
	accent_mat.roughness = 0.32

	match icon_kind:
		"celadon", "kettle":
			var cup := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.20
			cm.bottom_radius = 0.10
			cm.height = 0.20
			cup.mesh = cm
			cup.position.y = 0.11
			var cel_mat := main_mat.duplicate()
			cel_mat.albedo_color = Color("82dec5") if icon_kind == "celadon" else r_col
			cup.material_override = cel_mat
			root.add_child(cup)
		"ganoderma":
			var stem := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.035
			sm.bottom_radius = 0.045
			sm.height = 0.20
			stem.mesh = sm
			stem.position.y = 0.10
			stem.rotation_degrees.z = -12.0
			stem.material_override = accent_mat
			root.add_child(stem)
			var cap := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.18
			sp.height = 0.11
			cap.mesh = sp
			cap.position = Vector3(0.03, 0.20, 0)
			cap.material_override = main_mat
			root.add_child(cap)
		"seal":
			var base := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.13, 0.28)
			base.mesh = bm
			base.position.y = 0.065
			base.material_override = accent_mat
			root.add_child(base)
			var step := MeshInstance3D.new()
			var sbm := BoxMesh.new()
			sbm.size = Vector3(0.20, 0.05, 0.20)
			step.mesh = sbm
			step.position.y = 0.155
			step.material_override = accent_mat
			root.add_child(step)
			var jewel := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.16, 0.17, 0.16)
			jewel.mesh = pm
			jewel.position.y = 0.255
			jewel.rotation_degrees.y = 45.0
			jewel.material_override = main_mat
			root.add_child(jewel)
			var crown_ring := MeshInstance3D.new()
			var crm := TorusMesh.new()
			crm.inner_radius = 0.14
			crm.outer_radius = 0.165
			crown_ring.mesh = crm
			crown_ring.position.y = 0.22
			crown_ring.rotation_degrees = Vector3(18, 0, -18)
			crown_ring.material_override = main_mat
			root.add_child(crown_ring)
		"jade":
			var disc := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.065
			tm.outer_radius = 0.19
			disc.mesh = tm
			disc.position.y = 0.19
			disc.rotation_degrees.x = 78.0
			disc.material_override = main_mat
			root.add_child(disc)
		"slips", "rubbing":
			for i in 4:
				var slat := MeshInstance3D.new()
				var sb := BoxMesh.new()
				sb.size = Vector3(0.055, 0.025, 0.28)
				slat.mesh = sb
				slat.position = Vector3(-0.09 + float(i) * 0.06, 0.04, 0.0)
				slat.material_override = main_mat
				root.add_child(slat)
		"core", "radar_heart", "quantum":
			var orb := MeshInstance3D.new()
			var om := SphereMesh.new()
			om.radius = 0.14
			om.height = 0.28
			orb.mesh = om
			orb.position.y = 0.16
			orb.material_override = main_mat
			root.add_child(orb)
			var halo := MeshInstance3D.new()
			var hm := TorusMesh.new()
			hm.inner_radius = 0.17
			hm.outer_radius = 0.20
			halo.mesh = hm
			halo.position.y = 0.16
			halo.rotation_degrees = Vector3(32, 0, 24)
			halo.material_override = accent_mat
			root.add_child(halo)
		_:
			var box := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.24, 0.12, 0.18)
			box.mesh = b
			box.position.y = 0.06
			box.material_override = main_mat
			root.add_child(box)
	return root

# ---------------------------------------------------------------------------
# CAMP BILINGUAL TREASURE COMPENDIUM ('烟山奇珍图鉴 · v0.6.3')
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

	# Display Tier 6 (Crimson Red) -> Tier 5 (Gold) -> Tier 4 (Epic) -> Tier 3..1 curios
	for r in [6, 5, 4, 3, 2, 1]:
		for entry in game.Rules.LOOT_TABLE[r]:
			var unlocked: bool = (r <= 3) or (str(entry.title) in col_arr)
			var r_col: Color = game.Rules.RARITY_COLORS[r]
			var card := Panel.new()
			card.custom_minimum_size = Vector2(332, 114)
			var st := StyleBoxFlat.new()
			st.bg_color = Color(r_col.r * 0.16, r_col.g * 0.14, r_col.b * 0.17, 0.95) if unlocked else Color(0.03, 0.06, 0.07, 0.80)
			st.border_color = r_col if unlocked else Color(0.32, 0.45, 0.42, 0.35)
			st.set_border_width_all(2 if r >= 5 else 1)
			st.set_corner_radius_all(8)
			card.add_theme_stylebox_override("panel", st)

			var ic := create_icon(str(entry.icon), r_col if unlocked else Color("415450"), Vector2(52, 52))
			ic.position = Vector2(10, 12)
			card.add_child(ic)

			var title_txt: String = str(entry.title) if unlocked else "？？？ · 待搜刮带出"
			var head_lbl: Label = game._text(card, "【%s】 %s" % [game.Rules.RARITY_NAMES[r], title_txt], Vector2(68, 8), Vector2(254, 22), 14, r_col if unlocked else Color("779188"))
			head_lbl.clip_text = true
			var en_txt: String = ("🔊 %s  ·  基准 %d 币" % [str(entry.en), int(entry.value)]) if unlocked else "进山搜刮物资箱/桌面/鸟窝并撤离解锁"
			var ce_lbl: Label = game._text(card, en_txt, Vector2(68, 30), Vector2(254, 20), 11, game.MINT if unlocked else Color("607a72"))
			ce_lbl.clip_text = true
			var clean_lore: String = str(entry.lore).replace("【旷世·大红】", "").replace("【传说·大金】", "").strip_edges()
			var lore_lbl: Label = game._text(card, clean_lore if unlocked else "尚未收录该烟山奇珍实物标本。", Vector2(12, 58), Vector2(234 if unlocked else 306, 46), 11, Color("cfe3d8") if unlocked else Color("587068"))
			lore_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			lore_lbl.clip_text = true

			if unlocked:
				var b_view: Button = game._button(card, "3D检视", Rect2(254, 66, 68, 34), func():
					close_compendium()
					open_inspect_item(entry)
				)
				b_view.add_theme_font_size_override("font_size", 12)
			comp_grid.add_child(card)
