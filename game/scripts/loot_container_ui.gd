extends Node
## v0.8.4 Universal Selective Loot Confirmation & Container Inspection Panel ("全物资确认拾取面板").
## Unified dual-column modal used by ALL field loot sources:
## - Password Crates (Tier 1/2/3), Field Supply Boxes, Enemy Squad/Boss/Warden Drop Pouches
## - 14 Hidden Bird Nests & Karst Crevices, 10 Ground/Pedestal Single Loose Relics, & Exploration Reward Stashes
## Left Column: Container items (2D studio icon, rarity bar, bilingual name, appraisal, [拾取] & [存安全箱])
## Right Column: Live Tactical Backpack (with one-click [丢弃腾位]) & 2-Slot Encrypted Safe Box
## Bottom Bar: [只拾取蓝品及以上] / [全部拾取] / [离开（剩余留箱）] — unclaimed items persist in world containers!

const LootUI = preload("res://scripts/loot_ui.gd")

var game
var busy: bool = false
var active_node: Node3D = null
var active_kind: String = ""  # "crate" | "supply" | "squad_drop" | "nest" | "loose" | "exploration"
var active_title: String = ""
var active_subtitle: String = ""
var active_explore_id: String = ""
var pending_items: Array = []
var revealed_flags: Array = []
var taken_this_session: Array = []

# Magnifying-glass slot-by-slot reveal state (for crates, supply boxes & fresh drop pouches)
var reveal_cursor: int = 0
var reveal_timer: float = 0.0
var reveal_duration: float = 0.30
var reveal_tick_acc: float = 0.0
var reveal_bars: Dictionary = {}  # slot_idx -> {"bar": ColorRect, "max_w": float}

# UI references
var overlay: Control
var header_title: Label
var header_sub: Label
var left_header: Label
var left_vbox: VBoxContainer
var safe_header: Label
var safe_row: HBoxContainer
var bag_header: Label
var bag_vbox: VBoxContainer
var status_label: Label
var take_blue_btn: Button
var take_all_btn: Button
var leave_btn: Button
var top_close_btn: Button

func setup(g):
	game = g
	_build_ui()

func _build_ui():
	overlay = Control.new()
	overlay.name = "LootContainerOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.055, 0.90)
	overlay.add_child(veil)

	# Outer tactical frame (1160 x 652 centered in 1280 x 720)
	game._panel(overlay, Rect2(60, 34, 1160, 652), Color(0.042, 0.088, 0.110, 0.98), Color(0.48, 0.84, 0.70, 0.62))

	header_title = game._text(overlay, "📦 物资确认拾取面板", Vector2(86, 46), Vector2(880, 32), 22, game.MINT)
	header_title.clip_text = true
	header_sub = game._text(overlay, "左侧查看并选择要带走的物资，右侧可随时整理背包或存入加密安全箱；未拿走的物资保留原处！", Vector2(86, 78), Vector2(920, 20), 13, Color("9ec4b5"))
	header_sub.clip_text = true
	top_close_btn = game._button(overlay, "离开（剩余留箱）[Esc]", Rect2(1018, 48, 178, 38), close)
	top_close_btn.add_theme_font_size_override("font_size", 13)

	# LEFT COLUMN: Current Container Loot List
	game._panel(overlay, Rect2(84, 106, 536, 488), Color(0.032, 0.068, 0.086, 0.94), Color(0.42, 0.76, 0.64, 0.42))
	left_header = game._text(overlay, "🔍 当前容器物资清单", Vector2(98, 114), Vector2(508, 24), 15, game.GOLD)
	left_header.clip_text = true

	var left_scroll := ScrollContainer.new()
	left_scroll.position = Vector2(94, 144)
	left_scroll.size = Vector2(516, 440)
	overlay.add_child(left_scroll)

	left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 10)
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_vbox)

	# RIGHT COLUMN: Safe Box (Top) + Tactical Backpack (Bottom)
	game._panel(overlay, Rect2(634, 106, 562, 134), Color(0.082, 0.082, 0.038, 0.95), Color("f6c34e"))
	safe_header = game._text(overlay, "🔒 加密安全箱（0 / 2 格 · 阵亡不掉落）", Vector2(648, 112), Vector2(534, 22), 14, Color("ffd46e"))
	safe_header.clip_text = true
	safe_row = HBoxContainer.new()
	safe_row.position = Vector2(648, 140)
	safe_row.size = Vector2(534, 88)
	safe_row.add_theme_constant_override("separation", 10)
	overlay.add_child(safe_row)

	game._panel(overlay, Rect2(634, 248, 562, 346), Color(0.032, 0.068, 0.086, 0.94), Color(0.42, 0.76, 0.64, 0.42))
	bag_header = game._text(overlay, "🎒 我的战术背包（0 / 8 格 · 0 币）", Vector2(648, 256), Vector2(534, 24), 15, game.MINT)
	bag_header.clip_text = true

	var right_scroll := ScrollContainer.new()
	right_scroll.position = Vector2(646, 286)
	right_scroll.size = Vector2(538, 298)
	overlay.add_child(right_scroll)

	bag_vbox = VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 6)
	bag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(bag_vbox)

	# BOTTOM STATUS & QUICK ACTION BAR
	status_label = game._text(overlay, "提示：点击【拾取】收入背包，点击【存安全箱】锁定珍宝；按 [Space] 可跳过放大镜鉴定。", Vector2(86, 602), Vector2(1110, 22), 13, Color("a9d8c5"))
	status_label.clip_text = true

	take_blue_btn = game._button(overlay, "◆ 只拾取蓝品及以上", Rect2(84, 630, 220, 42), func(): take_blue_and_above())
	game._style_tactical_button(take_blue_btn, Color("1a3c58"), Color("5cb8ff"), Color("e4f4ff"))

	take_all_btn = game._button(overlay, "✓ 全部拾取", Rect2(318, 630, 174, 42), func(): take_all(), true)

	leave_btn = game._button(overlay, "离开（剩余留箱）[Esc]", Rect2(968, 630, 228, 42), close)

	overlay.hide()

func _input(event):
	if not busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_SPACE and _has_unrevealed_slots():
			reveal_all_immediately()
			get_viewport().set_input_as_handled()

func reset():
	busy = false
	active_node = null
	active_kind = ""
	active_title = ""
	active_subtitle = ""
	active_explore_id = ""
	pending_items.clear()
	revealed_flags.clear()
	taken_this_session.clear()
	reveal_bars.clear()
	reveal_cursor = 0
	reveal_timer = 0.0
	if is_instance_valid(game):
		var all_nodes: Array = []
		all_nodes.append_array(game.crate_nodes)
		all_nodes.append_array(game.pickup_nodes)
		if is_instance_valid(game.exploration):
			all_nodes.append_array(game.exploration.nodes)
		for nd in all_nodes:
			if is_instance_valid(nd):
				for mk in ["pending_items", "opened_remaining", "scanned", "unclaimed_loot"]:
					if nd.has_meta(mk):
						nd.remove_meta(mk)
	if is_instance_valid(overlay):
		overlay.hide()

func _has_unrevealed_slots() -> bool:
	for f in revealed_flags:
		if not bool(f):
			return true
	return false

func _scan_duration_for(rarity: int) -> float:
	if rarity >= 7:
		return 1.15
	if rarity == 6:
		return 0.88
	if rarity == 5:
		return 0.68
	if rarity == 4:
		return 0.48
	if rarity == 3:
		return 0.36
	return 0.22

func open_container(node: Node3D, kind: String, title: String, items: Array, subtitle: String = "", animate_scan: bool = false, explore_id: String = ""):
	if items.is_empty():
		return
	if is_instance_valid(game.loot_ui) and game.loot_ui.any_modal_open():
		game.loot_ui.close_all_modals()
	active_node = node
	active_kind = kind
	active_title = title
	active_subtitle = subtitle
	active_explore_id = explore_id
	taken_this_session.clear()

	pending_items.clear()
	for raw in items:
		if raw is Dictionary:
			pending_items.append(game.rules._enrich_loot_dict(raw))

	if pending_items.is_empty():
		return

	# Sort fresh multi-item containers highest valuation first for crisp scanning excitement
	var already_scanned: bool = is_instance_valid(node) and bool(node.get_meta("scanned", false))
	if not already_scanned and pending_items.size() > 1:
		pending_items.sort_custom(func(a, b): return int(a.get("value", 0)) > int(b.get("value", 0)))

	var do_scan: bool = animate_scan and not already_scanned and not game.qa_mode
	revealed_flags.clear()
	for _i in pending_items.size():
		revealed_flags.append(not do_scan)

	reveal_cursor = 0 if do_scan else pending_items.size()
	reveal_timer = 0.0
	reveal_tick_acc = 0.0
	if do_scan:
		reveal_duration = _scan_duration_for(int(pending_items[0].get("rarity", 1)))

	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if is_instance_valid(node):
		node.set_meta("pending_items", pending_items.duplicate(true))
		if kind != "loose":
			node.set_meta("opened_remaining", true)

	if kind == "loose":
		status_label.text = "查看这件散落物资后，可点【拾取】入包、【存安全箱】，或点【离开】将其留在原地。"
	elif do_scan:
		status_label.text = "🔍 放大镜正在逐格鉴定容器物资（按 [Space] 或点击卡片可立即揭晓全部）！"
	else:
		status_label.text = "请勾选要带走的物资；背包满时可在右侧点【丢弃腾位】或直接点【存安全箱】！"
	status_label.add_theme_color_override("font_color", Color("a9d8c5"))

	_refresh_all()
	overlay.show()

func _refresh_all():
	_refresh_headers()
	_refresh_left_container()
	_refresh_right_inventory()
	_refresh_bottom_buttons()

func _refresh_headers():
	var rem := pending_items.size()
	var total_v := 0
	for it in pending_items:
		total_v += int(it.get("value", 0))
	if active_kind == "loose":
		header_title.text = "📦 %s · 散落物资确认拾取" % active_title
		top_close_btn.text = "离开（留原地）[Esc]"
		leave_btn.text = "离开（留原地）[Esc]"
	else:
		header_title.text = "📦 %s · 选择性物资搜刮（剩余 %d 件）" % [active_title, rem]
		top_close_btn.text = ("完成返回 [Esc]" if rem == 0 else "离开（剩余留箱）[Esc]")
		leave_btn.text = ("完成返回 [Esc]" if rem == 0 else "离开（剩余留箱）[Esc]")

	if active_subtitle != "":
		header_sub.text = active_subtitle
	elif active_kind == "loose":
		header_sub.text = "自由决定是否收入背包或直接锁入安全箱；不想要可直接离开，物品将留在原地。"
	else:
		header_sub.text = "左侧逐件点击【拾取】/【存安全箱】，右侧可整理背包腾位；未选走的物资留在原容器可随时复开！"

	if _has_unrevealed_slots():
		left_header.text = "🔍 放大镜鉴定中（共 %d 件 · 按 [Space] 跳过）" % rem
	else:
		left_header.text = "🔍 当前容器物资清单（剩余 %d 件 · 估值 %d 币）" % [rem, total_v]

func _refresh_left_container():
	reveal_bars.clear()
	for ch in left_vbox.get_children():
		ch.queue_free()

	if pending_items.is_empty():
		var done_card := Panel.new()
		done_card.custom_minimum_size = Vector2(496, 136)
		var dst := StyleBoxFlat.new()
		dst.bg_color = Color(0.045, 0.115, 0.105, 0.92)
		dst.border_color = game.MINT
		dst.set_border_width_all(2)
		dst.set_corner_radius_all(8)
		done_card.add_theme_stylebox_override("panel", dst)
		var dl: Label = game._text(done_card, "✓ 本容器物资已全部搜刮完毕！\n点击下方「完成返回」或按 [Esc] 继续烟山行动。", Vector2(18, 40), Vector2(460, 56), 16, game.MINT)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left_vbox.add_child(done_card)
		return

	var bag_full: bool = game.rules.bag.size() >= game.rules.capacity()
	var safe_full: bool = game.rules.safe_box.size() >= game.rules.safe_box_slots()

	for idx in pending_items.size():
		var item: Dictionary = pending_items[idx]
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		var r_col: Color = game.Rules.RARITY_COLORS[r]
		var r_name: String = game.Rules.RARITY_NAMES[r]
		var grid_tag: String = str(item.get("grid", "1×1"))
		var cond_str: String = str(item.get("cond", "标准"))
		var revealed: bool = idx < revealed_flags.size() and bool(revealed_flags[idx])

		var card := Panel.new()
		card.custom_minimum_size = Vector2(496, 118)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(8)

		if not revealed:
			var scanning_now: bool = (idx == reveal_cursor)
			st.bg_color = Color(0.08, 0.10, 0.12, 0.96) if scanning_now else Color(0.04, 0.07, 0.09, 0.92)
			st.border_color = game.MINT if scanning_now else Color(0.35, 0.56, 0.50, 0.42)
			st.set_border_width_all(2 if scanning_now else 1)
			card.add_theme_stylebox_override("panel", st)

			var m_title: Label = game._text(card, "🔍 未知物资槽 #%d · [%s]" % [idx + 1, grid_tag], Vector2(18, 22), Vector2(460, 26), 17, Color("c4e6d8"))
			m_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

			var hint_txt: String = "等待放大镜鉴定..."
			var hint_col: Color = Color("7fa498")
			var fill_col: Color = game.MINT
			if scanning_now:
				if r >= 7:
					hint_txt = "⚠ 侦测到旷世奇珍超高能波形！！"
					hint_col = Color("ff6b7a")
					fill_col = Color("ff4757")
				elif r == 6:
					hint_txt = "✦ 发现传说大金高价值信号！"
					hint_col = Color("ff9f38")
					fill_col = Color("ff9f38")
				elif r == 5:
					hint_txt = "◆ 捕捉到温润珍品小金光芒！"
					hint_col = Color("f6c34e")
					fill_col = Color("f6c34e")
				else:
					hint_txt = "🔍 放大镜鉴定中（点击卡片或按 Space 跳过）..."
					hint_col = Color("9ef0d2")
			var sub_l: Label = game._text(card, hint_txt, Vector2(18, 52), Vector2(460, 22), 13, hint_col)
			sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

			var bar_bg := ColorRect.new()
			bar_bg.position = Vector2(36, 86)
			bar_bg.size = Vector2(424, 9)
			bar_bg.color = Color(1, 1, 1, 0.12)
			bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(bar_bg)

			var bar_fill := ColorRect.new()
			bar_fill.position = Vector2(36, 86)
			bar_fill.size = Vector2(0, 9)
			bar_fill.color = fill_col
			bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(bar_fill)
			reveal_bars[idx] = {"bar": bar_fill, "max_w": 424.0}

			var skip_btn := Button.new()
			skip_btn.flat = true
			skip_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			skip_btn.pressed.connect(reveal_all_immediately)
			card.add_child(skip_btn)
		else:
			st.bg_color = Color(0.20, 0.045, 0.07, 0.97) if r == 7 else Color(r_col.r * 0.16 + 0.03, r_col.g * 0.15 + 0.04, r_col.b * 0.18 + 0.05, 0.96)
			st.border_color = r_col
			st.set_border_width_all(3 if r >= 5 else 2)
			card.add_theme_stylebox_override("panel", st)

			# Left vertical rarity color stripe
			var stripe := ColorRect.new()
			stripe.position = Vector2(6, 10)
			stripe.size = Vector2(6, 98)
			stripe.color = r_col
			stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(stripe)

			var ic := LootUI.create_icon(item, r_col, Vector2(68, 68))
			ic.position = Vector2(18, 25)
			card.add_child(ic)

			var badge_prefix := "🔥 " if r == 7 else ("✦ " if r == 6 else ("◆ " if r == 5 else ""))
			var b_lbl: Label = game._text(card, "%s【%s · %s】" % [badge_prefix, r_name, cond_str], Vector2(96, 10), Vector2(252, 20), 12, r_col)
			b_lbl.clip_text = true
			var t_lbl: Label = game._text(card, str(item.get("title", "物资")), Vector2(96, 32), Vector2(252, 26), 17, game.CREAM)
			t_lbl.clip_text = true
			var e_lbl: Label = game._text(card, "🔊 %s · [%s]" % [str(item.get("en", "Supply")), grid_tag], Vector2(96, 60), Vector2(252, 20), 12, Color("9adbc0"))
			e_lbl.clip_text = true
			e_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var v_lbl: Label = game._text(card, "鉴定估值  %d 币" % int(item.get("value", 0)), Vector2(96, 84), Vector2(252, 22), 15, Color("ff6b7a") if r == 7 else game.GOLD)
			v_lbl.clip_text = true

			var btn_pick: Button = game._button(card, "背包已满" if bag_full else "拾取入包", Rect2(356, 16, 128, 38), func(): take_item_to_bag(idx), not bag_full)
			btn_pick.add_theme_font_size_override("font_size", 14)
			btn_pick.disabled = bag_full

			var btn_safe: Button = game._button(card, "安全箱满" if safe_full else "🔒 存安全箱", Rect2(356, 64, 128, 38), func(): take_item_to_safe_box(idx))
			btn_safe.add_theme_font_size_override("font_size", 13)
			if not safe_full:
				game._style_tactical_button(btn_safe, Color("4b3b14"), Color("f6c34e"), Color("fff2c4"))
			btn_safe.disabled = safe_full

		left_vbox.add_child(card)

func _refresh_right_inventory():
	for ch in safe_row.get_children():
		ch.queue_free()
	for ch in bag_vbox.get_children():
		ch.queue_free()

	var cap: int = game.rules.capacity()
	var s_slots: int = game.rules.safe_box_slots()
	var bag_val: int = game.rules.bag_value()
	var safe_val: int = game.rules.safe_box_value()
	var bag_full: bool = game.rules.bag.size() >= cap
	var safe_full: bool = game.rules.safe_box.size() >= s_slots

	safe_header.text = "🔒 加密安全箱（%d / %d 格 · 保底 %d 币 · 阵亡不掉落）" % [
		game.rules.safe_box.size(), s_slots, safe_val
	]
	bag_header.text = "🎒 我的战术背包（%d / %d 格 · 估值 %d 币%s）" % [
		game.rules.bag.size(), cap, bag_val,
		" · 机密×1.35" if game.rules.is_confidential() else ""
	]

	# Render Encrypted Safe Box slots (2 base, or 3 with safebox_upgrade)
	var scard_w: float = 172.0 if s_slots >= 3 else 262.0
	for s_idx in s_slots:
		var scard := Panel.new()
		scard.custom_minimum_size = Vector2(scard_w, 86)
		var sst := StyleBoxFlat.new()
		sst.set_corner_radius_all(7)
		if s_idx < game.rules.safe_box.size():
			var sit: Dictionary = game.rules.safe_box[s_idx]
			var sr: int = clampi(int(sit.get("rarity", 1)), 1, 7)
			var sr_col: Color = game.Rules.RARITY_COLORS[sr]
			sst.bg_color = Color(sr_col.r * 0.18 + 0.04, sr_col.g * 0.15 + 0.03, sr_col.b * 0.14 + 0.02, 0.96)
			sst.border_color = sr_col
			sst.set_border_width_all(2)
			scard.add_theme_stylebox_override("panel", sst)

			var ic_sz: float = 40.0 if s_slots >= 3 else 52.0
			var sic := LootUI.create_icon(sit, sr_col, Vector2(ic_sz, ic_sz))
			sic.position = Vector2(6 if s_slots >= 3 else 8, 8 if s_slots >= 3 else 17)
			scard.add_child(sic)

			var tx: float = 52.0 if s_slots >= 3 else 66.0
			var tw: float = 114.0 if s_slots >= 3 else 124.0
			var st_lbl: Label = game._text(scard, str(sit.get("title", "珍宝")), Vector2(tx, 8), Vector2(tw, 20), 12 if s_slots >= 3 else 13, sr_col)
			st_lbl.clip_text = true
			var sv_lbl: Label = game._text(scard, "%d币" % int(sit.get("value", 0)) if s_slots >= 3 else "%s · %d币" % [game.Rules.RARITY_NAMES[sr], int(sit.get("value", 0))], Vector2(tx, 30), Vector2(tw, 18), 11, game.GOLD)
			sv_lbl.clip_text = true
			if s_slots < 3:
				game._text(scard, "🔒 阵亡保底", Vector2(66, 56), Vector2(120, 18), 11, Color("9ee2c2"))

			var b_rect: Rect2 = Rect2(6, 54, scard_w - 12.0, 26) if s_slots >= 3 else Rect2(196, 14, 58, 58)
			var b_out: Button = game._button(scard, "移回背包" if s_slots >= 3 else "移回\n背包", b_rect, func(): move_safe_to_bag(s_idx))
			b_out.add_theme_font_size_override("font_size", 11)
			b_out.disabled = bag_full
		else:
			sst.bg_color = Color(0.05, 0.075, 0.06, 0.72)
			sst.border_color = Color(0.95, 0.78, 0.35, 0.36)
			sst.set_border_width_all(1)
			scard.add_theme_stylebox_override("panel", sst)
			var semp: Label = game._text(scard, "🔒 安全格 #%d\n空闲" % (s_idx + 1) if s_slots >= 3 else "🔒 安全格 #%d（空闲）\n左侧点「存安全箱」直存" % (s_idx + 1), Vector2(6, 22), Vector2(scard_w - 12.0, 42), 11 if s_slots >= 3 else 12, Color("cbbd88"))
			semp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		safe_row.add_child(scard)

	# Render current Tactical Backpack items (sorted display keeping real bag index for accurate discard/move!)
	if game.rules.bag.is_empty():
		var emp_card := Panel.new()
		emp_card.custom_minimum_size = Vector2(516, 84)
		var est := StyleBoxFlat.new()
		est.bg_color = Color(0.03, 0.06, 0.08, 0.65)
		est.border_color = Color(0.35, 0.55, 0.48, 0.25)
		est.set_border_width_all(1)
		est.set_corner_radius_all(7)
		emp_card.add_theme_stylebox_override("panel", est)
		var el: Label = game._text(emp_card, "随身背包暂无物资（剩余 %d 格空位）\n点击左侧【拾取入包】或下方【全部拾取】收入囊中" % cap, Vector2(14, 20), Vector2(488, 44), 13, Color("7b9e90"))
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag_vbox.add_child(emp_card)
		return

	for b_idx in game.rules.bag.size():
		var bit: Dictionary = game.rules.bag[b_idx]
		var br: int = clampi(int(bit.get("rarity", 1)), 1, 7)
		var br_col: Color = game.Rules.RARITY_COLORS[br]

		var row := Panel.new()
		row.custom_minimum_size = Vector2(518, 56)
		var rst := StyleBoxFlat.new()
		rst.bg_color = Color(br_col.r * 0.14 + 0.02, br_col.g * 0.14 + 0.03, br_col.b * 0.16 + 0.04, 0.94)
		rst.border_color = Color(br_col.r, br_col.g, br_col.b, 0.72)
		rst.set_border_width_all(2 if br >= 5 else 1)
		rst.set_corner_radius_all(6)
		row.add_theme_stylebox_override("panel", rst)

		var bic := LootUI.create_icon(bit, br_col, Vector2(42, 42))
		bic.position = Vector2(8, 7)
		row.add_child(bic)

		var bt: Label = game._text(row, "【%s】 %s" % [game.Rules.RARITY_NAMES[br], str(bit.get("title", "物资"))], Vector2(58, 6), Vector2(276, 22), 14, br_col)
		bt.clip_text = true
		var bs: Label = game._text(row, "%s · 估值 %d 币" % [str(bit.get("en", "")), int(bit.get("value", 0))], Vector2(58, 30), Vector2(276, 18), 11, game.GOLD)
		bs.clip_text = true

		var b_safe: Button = game._button(row, "存安全箱", Rect2(340, 12, 82, 32), func(): move_bag_to_safe(b_idx))
		b_safe.add_theme_font_size_override("font_size", 11)
		b_safe.disabled = safe_full

		var b_drop: Button = game._button(row, "丢弃腾位", Rect2(428, 12, 82, 32), func(): discard_bag_slot(b_idx))
		b_drop.add_theme_font_size_override("font_size", 11)
		game._style_tactical_button(b_drop, Color("4d2024"), Color("ff7a7a"), Color("ffe2e2"))

		bag_vbox.add_child(row)

func _refresh_bottom_buttons():
	var has_items := not pending_items.is_empty()
	var blue_count := 0
	for it in pending_items:
		if int(it.get("rarity", 1)) >= 3:
			blue_count += 1
	var bag_full: bool = game.rules.bag.size() >= game.rules.capacity()

	take_blue_btn.disabled = (not has_items) or bag_full or (blue_count == 0 and not _has_unrevealed_slots())
	take_blue_btn.text = "◆ 只拾取蓝品及以上" if _has_unrevealed_slots() else ("◆ 只拾取蓝品及以上（%d）" % blue_count)
	take_all_btn.disabled = (not has_items) or bag_full
	take_all_btn.text = "✓ 全部拾取（%d）" % pending_items.size() if has_items else "✓ 已全部拾取"

func _reveal_single_slot(idx: int, with_audio: bool):
	if idx < 0 or idx >= revealed_flags.size() or bool(revealed_flags[idx]):
		return
	revealed_flags[idx] = true
	if with_audio and idx < pending_items.size():
		var item: Dictionary = pending_items[idx]
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		if r == 7:
			game.play_sfx("loot_mythic_red", -7)
			status_label.text = "🔥 奇迹出大红！！开出【旷世·大红】%s（%d币）—— 建议立即点【存安全箱】锁定！" % [str(item.title), int(item.value)]
			status_label.add_theme_color_override("font_color", Color("ff6b7a"))
			game.speak_english(str(item.get("en", "")))
		elif r == 6:
			game.play_sfx("loot_epic", -8)
			status_label.text = "✦ 金光耀眼！摸出【传说·大金】%s（%d币）！" % [str(item.title), int(item.value)]
			status_label.add_theme_color_override("font_color", Color("ff9f38"))
		elif r == 5:
			game.play_sfx("loot_epic", -11)
			status_label.text = "◆ 珍品闪耀！摸出【珍品·小金】%s（%d币）！" % [str(item.title), int(item.value)]
			status_label.add_theme_color_override("font_color", Color("f6c34e"))
		elif r >= 3:
			game.play_sfx("loot_reveal_rare", -11)
		else:
			game.play_sfx("loot_reveal_common", -12)

func reveal_all_immediately():
	var changed := false
	for i in revealed_flags.size():
		if not bool(revealed_flags[i]):
			revealed_flags[i] = true
			changed = true
	reveal_cursor = revealed_flags.size()
	if is_instance_valid(active_node):
		active_node.set_meta("scanned", true)
	if changed and busy:
		_refresh_all()

func _play_item_take_sfx(r: int, to_safe: bool):
	if r == 7:
		game.play_sfx("loot_mythic_red", -7)
	elif to_safe:
		game.play_sfx("cipher_unlock", -10)
	elif r >= 5:
		game.play_sfx("loot_epic", -9)
	elif r >= 3:
		game.play_sfx("loot_reveal_rare", -11)
	else:
		game.play_sfx("loot_reveal_common", -12)

func take_item_to_bag(idx: int) -> bool:
	if not busy or idx < 0 or idx >= pending_items.size():
		return false
	reveal_all_immediately()
	var item: Dictionary = pending_items[idx]
	if not game.rules.add_loot_item(item):
		game.play_sfx("hit_wrong", -13)
		status_label.text = "背包已满（%d/%d）！请在右侧点【丢弃腾位】，或直接点【🔒 存安全箱】！" % [game.rules.bag.size(), game.rules.capacity()]
		status_label.add_theme_color_override("font_color", Color("ffd166"))
		return false
	pending_items.remove_at(idx)
	if idx < revealed_flags.size():
		revealed_flags.remove_at(idx)
	taken_this_session.append(item)
	var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
	_play_item_take_sfx(r, false)
	game.speak_english(str(item.get("en", "")))
	_sync_world_container_state()
	if pending_items.is_empty():
		close()
		return true
	status_label.text = "✓ 已拾取【%s】%s（%d币）入包！剩余 %d 件可继续勾选。" % [game.Rules.RARITY_NAMES[r], str(item.title), int(item.value), pending_items.size()]
	status_label.add_theme_color_override("font_color", game.MINT)
	_refresh_all()
	return true

func take_item_to_safe_box(idx: int) -> bool:
	if not busy or idx < 0 or idx >= pending_items.size():
		return false
	reveal_all_immediately()
	var item: Dictionary = pending_items[idx]
	if not game.rules.add_item_to_safe_box(item):
		game.play_sfx("hit_wrong", -13)
		status_label.text = "加密安全箱已满（%d/%d）！请先在右侧安全箱点【移回背包】腾位。" % [game.rules.safe_box.size(), game.rules.safe_box_slots()]
		status_label.add_theme_color_override("font_color", Color("ffd166"))
		return false
	pending_items.remove_at(idx)
	if idx < revealed_flags.size():
		revealed_flags.remove_at(idx)
	taken_this_session.append(item)
	var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
	_play_item_take_sfx(r, true)
	game.speak_english(str(item.get("en", "")))
	_sync_world_container_state()
	if pending_items.is_empty():
		close()
		return true
	status_label.text = "🔒 已将【%s】%s（%d币）直存加密安全箱！阵亡也不掉落！" % [game.Rules.RARITY_NAMES[r], str(item.title), int(item.value)]
	status_label.add_theme_color_override("font_color", Color("ffd46e"))
	_refresh_all()
	return true

func take_blue_and_above() -> int:
	if not busy or pending_items.is_empty():
		return 0
	reveal_all_immediately()
	var taken_cnt := 0
	var best_r := 1
	var kept: Array = []
	var kept_flags: Array = []
	for i in pending_items.size():
		var item: Dictionary = pending_items[i]
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		if r >= 3 and game.rules.add_loot_item(item):
			taken_cnt += 1
			best_r = maxi(best_r, r)
			taken_this_session.append(item)
		else:
			kept.append(item)
			kept_flags.append(true)
	pending_items = kept
	revealed_flags = kept_flags
	_sync_world_container_state()
	if taken_cnt > 0:
		_play_item_take_sfx(best_r, false)
		game.speak_english(str(taken_this_session[-1].get("en", "")))
	if pending_items.is_empty():
		close()
		return taken_cnt
	if taken_cnt == 0:
		game.play_sfx("hit_wrong", -13)
		status_label.text = "当前容器暂无可装入背包的蓝品及以上物资（或背包已满）。"
		status_label.add_theme_color_override("font_color", Color("ffd166"))
	else:
		status_label.text = "◆ 已一键拾取 %d 件蓝品及以上物资！其余 %d 件低品或满包物资留在容器内。" % [taken_cnt, pending_items.size()]
		status_label.add_theme_color_override("font_color", Color("7ceeff"))
	_refresh_all()
	return taken_cnt

func take_all() -> int:
	if not busy or pending_items.is_empty():
		return 0
	reveal_all_immediately()
	var taken_cnt := 0
	var best_r := 1
	var kept: Array = []
	var kept_flags: Array = []
	for i in pending_items.size():
		var item: Dictionary = pending_items[i]
		if game.rules.add_loot_item(item):
			taken_cnt += 1
			best_r = maxi(best_r, clampi(int(item.get("rarity", 1)), 1, 7))
			taken_this_session.append(item)
		else:
			kept.append(item)
			kept_flags.append(true)
	pending_items = kept
	revealed_flags = kept_flags
	_sync_world_container_state()
	if taken_cnt > 0:
		_play_item_take_sfx(best_r, false)
		game.speak_english(str(taken_this_session[-1].get("en", "")))
	if pending_items.is_empty():
		close()
		return taken_cnt
	game.play_sfx("hit_wrong", -13)
	status_label.text = "已拾取 %d 件，随身背包已满（剩余 %d 件留箱）！可点右侧【丢弃腾位】或点【🔒 存安全箱】。" % [taken_cnt, pending_items.size()]
	status_label.add_theme_color_override("font_color", Color("ffd166"))
	_refresh_all()
	return taken_cnt

func take_all_for_qa() -> int:
	var n := take_all()
	if busy:
		close()
	return n

func discard_bag_slot(bag_idx: int) -> Dictionary:
	if not busy:
		return {}
	var removed: Dictionary = game.rules.discard_bag_item(bag_idx)
	if not removed.is_empty():
		game.play_sfx("loot_reveal_common", -13)
		status_label.text = "已丢弃【%s（%d币）】，腾出 1 格随身背包空间！" % [str(removed.get("title", "")), int(removed.get("value", 0))]
		status_label.add_theme_color_override("font_color", Color("ffd166"))
		_refresh_all()
	return removed

func move_bag_to_safe(bag_idx: int) -> bool:
	if not busy or bag_idx < 0 or bag_idx >= game.rules.bag.size():
		return false
	var t_name := str(game.rules.bag[bag_idx].get("title", "珍宝"))
	if game.rules.move_bag_to_safe_box(bag_idx):
		game.play_sfx("cipher_unlock", -11)
		status_label.text = "🔒 已将背包中的【%s】移入加密安全箱，腾出 1 格背包空间！" % t_name
		status_label.add_theme_color_override("font_color", Color("ffd46e"))
		_refresh_all()
		return true
	return false

func move_safe_to_bag(safe_idx: int) -> bool:
	if not busy or safe_idx < 0 or safe_idx >= game.rules.safe_box.size():
		return false
	var t_name := str(game.rules.safe_box[safe_idx].get("title", "珍宝"))
	if game.rules.move_safe_box_to_bag(safe_idx):
		game.play_sfx("loot_reveal_common", -12)
		status_label.text = "已将【%s】从安全箱移回背包，腾出 1 格加密安全箱！" % t_name
		status_label.add_theme_color_override("font_color", game.MINT)
		_refresh_all()
		return true
	return false

func _sync_world_container_state():
	if not is_instance_valid(active_node):
		return
	if pending_items.is_empty():
		for mk in ["pending_items", "opened_remaining", "unclaimed_loot"]:
			if active_node.has_meta(mk):
				active_node.remove_meta(mk)
		match active_kind:
			"supply":
				game.Props.set_enabled(active_node, false)
			"crate":
				if active_node.get_child_count() > 0:
					var lbl = active_node.get_child(active_node.get_child_count() - 1)
					if lbl is Label3D:
						lbl.modulate = game.MINT
			"squad_drop":
				active_node.visible = false
				game.cached_interactables.clear()
			"nest":
				var glint: Node3D = active_node.get_node_or_null("Glint")
				if is_instance_valid(glint):
					glint.visible = false
				active_node.visible = false
				game.cached_interactables.clear()
			"loose":
				if active_node.has_meta("loot_item"):
					active_node.remove_meta("loot_item")
				active_node.visible = false
				game.cached_interactables.clear()
			"exploration":
				if active_explore_id == "english":
					game.exploration.states["english"] = true
					game.exploration.states["english_claimed"] = true
					game.Props.set_enabled(active_node, false)
				elif active_explore_id != "":
					game.exploration.states[active_explore_id + "_claimed"] = true
	else:
		active_node.set_meta("pending_items", pending_items.duplicate(true))
		active_node.set_meta("scanned", true)
		if active_kind != "loose":
			active_node.set_meta("opened_remaining", true)
		else:
			active_node.set_meta("loot_item", pending_items[0])
		if active_kind == "nest":
			var glint2: Node3D = active_node.get_node_or_null("Glint")
			if is_instance_valid(glint2):
				glint2.visible = true
		active_node.visible = true

func _process(delta: float):
	if not busy or not _has_unrevealed_slots():
		return
	while reveal_cursor < revealed_flags.size() and bool(revealed_flags[reveal_cursor]):
		reveal_cursor += 1
	if reveal_cursor >= revealed_flags.size():
		return
	reveal_timer += delta
	reveal_tick_acc += delta
	if reveal_tick_acc >= 0.18:
		reveal_tick_acc = 0.0
		game.play_sfx("loot_scan_tick", -15)
	var ratio: float = clampf(reveal_timer / maxf(0.1, reveal_duration), 0.0, 1.0)
	if reveal_bars.has(reveal_cursor):
		var b_info: Dictionary = reveal_bars[reveal_cursor]
		var bar: ColorRect = b_info.bar
		if is_instance_valid(bar):
			bar.size.x = float(b_info.max_w) * ratio
	if ratio >= 1.0:
		_reveal_single_slot(reveal_cursor, true)
		reveal_cursor += 1
		reveal_timer = 0.0
		reveal_tick_acc = 0.0
		if reveal_cursor < pending_items.size():
			reveal_duration = _scan_duration_for(int(pending_items[reveal_cursor].get("rarity", 1)))
		elif is_instance_valid(active_node):
			active_node.set_meta("scanned", true)
		_refresh_all()

func close():
	if not busy:
		return
	reveal_all_immediately()
	_sync_world_container_state()
	var left_cnt := pending_items.size()
	var title_copy := active_title
	var kind_copy := active_kind
	var best_taken: Dictionary = {}
	for it in taken_this_session:
		if best_taken.is_empty() or int(it.get("rarity", 1)) > int(best_taken.get("rarity", 1)) or (int(it.get("rarity", 1)) == int(best_taken.get("rarity", 1)) and int(it.get("value", 0)) > int(best_taken.get("value", 0))):
			best_taken = it

	busy = false
	overlay.hide()
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(game.exploration):
		game.exploration.grace = maxf(game.exploration.grace, 2.5)
	if not best_taken.is_empty() and is_instance_valid(game.loot_ui):
		game.loot_ui.trigger_loot_toast(best_taken, title_copy)
	if left_cnt > 0:
		if kind_copy == "loose":
			game._notice("📦 已将【%s】留在原地，随时可返回按 [F] 拾取。" % str(pending_items[0].get("title", title_copy)), Color("ffd166"))
		else:
			game._notice("📦 【%s】内仍余 %d 件物资保留原处，随时可回来补拿！" % [title_copy, left_cnt], Color("ffd166"))
