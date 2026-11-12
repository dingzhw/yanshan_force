extends Node
## High-value password crate terminal: type the exact English word to unlock & reveal rare loot.

var game
var busy = false
var active_crate: Node3D
var target_word: Dictionary = {}
var attempts = 0
var unlocked = false
var perfect_crack = false
var pending_loot: Array = []

var overlay: Control
var title_label: Label
var prompt_label: Label
var mask_label: Label
var meta_label: Label
var input_box: LineEdit
var status_label: Label
var submit_button: Button
var speak_button: Button
var close_button: Button
var swap_button: Button
var loot_container: HBoxContainer
var rng := RandomNumberGenerator.new()

func setup(g):
	game = g
	rng.randomize()
	_build_ui()

func _build_ui():
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(overlay)

	var veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.055, 0.90)
	overlay.add_child(veil)

	game._panel(overlay, Rect2(220, 74, 840, 572), Color(0.055, 0.11, 0.135, 0.98), Color(0.45, 0.82, 0.68, 0.55))
	title_label = game._text(overlay, "战术密码箱 · 拼写破译", Vector2(260, 98), Vector2(620, 40), 28, game.MINT)
	meta_label = game._text(overlay, "", Vector2(260, 140), Vector2(740, 26), 15, Color("9ec4b5"))

	prompt_label = game._text(overlay, "", Vector2(260, 178), Vector2(760, 68), 28, game.CREAM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	mask_label = game._text(overlay, "", Vector2(260, 250), Vector2(760, 44), 24, game.GOLD)
	mask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	input_box = LineEdit.new()
	input_box.position = Vector2(340, 308)
	input_box.size = Vector2(440, 52)
	input_box.placeholder_text = "在此输入准确的英文单词 / 短语，按 Enter 解锁…"
	input_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_box.add_theme_font_size_override("font_size", 23)
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color("0d1c22")
	input_style.border_color = game.MINT
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(6)
	input_style.content_margin_left = 14
	input_style.content_margin_right = 14
	input_box.add_theme_stylebox_override("normal", input_style)
	input_box.add_theme_stylebox_override("focus", input_style)
	input_box.text_submitted.connect(func(_t): submit())
	input_box.text_changed.connect(func(_t): game.play_sfx("cipher_key", -20))
	overlay.add_child(input_box)

	speak_button = game._button(overlay, "🔊 发音提示", Rect2(794, 308, 150, 52), _speak_hint)
	submit_button = game._button(overlay, "破译开箱 [Enter]", Rect2(340, 374, 290, 46), submit, true)
	swap_button = game._button(overlay, "替换背包最低值物资", Rect2(646, 374, 298, 46), _swap_lowest)
	swap_button.hide()

	status_label = game._text(overlay, "", Vector2(260, 432), Vector2(760, 54), 18, game.GOLD)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	loot_container = HBoxContainer.new()
	loot_container.position = Vector2(260, 492)
	loot_container.size = Vector2(760, 86)
	loot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	loot_container.add_theme_constant_override("separation", 16)
	overlay.add_child(loot_container)

	game._text(overlay, "破译期间暂停敌方攻击与倒计时 · 前2次准确拼出享「完美破译」爆率加成", Vector2(260, 594), Vector2(540, 30), 14, Color("8fb2a4"))
	close_button = game._button(overlay, "关闭返回 [Esc]", Rect2(830, 588, 185, 38), close)
	overlay.hide()

func reset():
	busy = false
	unlocked = false
	active_crate = null
	pending_loot.clear()
	if is_instance_valid(overlay):
		overlay.hide()

func _pick_spelling_word() -> Dictionary:
	var source_pool: Array = game.pool if not game.pool.is_empty() else game.words
	var candidates = []
	for w in source_pool:
		var en: String = w.english.strip_edges()
		if "..." in en or en.length() > 16 or w.get("proper_name", false):
			continue
		candidates.append(w)
	if candidates.is_empty():
		candidates = source_pool
	# Prefer words with higher mastery priority (unseen or previously missed)
	var best = candidates[rng.randi_range(0, candidates.size() - 1)]
	var best_score = -1.0
	for i in mini(6, candidates.size()):
		var c = candidates[rng.randi_range(0, candidates.size() - 1)]
		var s = game.rules.word_priority(c.id) + rng.randf() * 0.6
		if s > best_score:
			best_score = s
			best = c
	return best

func _build_mask(english: String, tier: int, reveal_all: bool = false) -> String:
	var clean = english.replace("’", "'").strip_edges()
	if reveal_all:
		return "正确拼写：  " + clean
	var out = []
	var n = clean.length()
	for i in n:
		var ch = clean[i]
		if ch == " " or ch == "-" or ch == "'":
			out.append("  " if ch == " " else ch)
		elif tier <= 1 and (i == 0 or i == n - 1):
			out.append(ch)
		elif tier == 2 and i == 0:
			out.append(ch)
		else:
			out.append("_")
	return "拼写结构： " + " ".join(out) + "   （共 %d 字符）" % n

func open_for_crate(crate_node: Node3D):
	var crate_title: String = crate_node.get_meta("title")
	var tier: int = int(crate_node.get_meta("tier"))
	if crate_title in game.rules.crates:
		game._notice(crate_title + " 已破译搜刮完毕。")
		return
	if not game.rules.crate_ready(tier):
		var req = game.rules.crate_requirements(tier)
		game._notice("需至少答 %d 题且正确率达 %d%% 才能连接此密码箱！" % [req.minimum, roundi(req.accuracy * 100)])
		game.play_sfx("hit_wrong", -14)
		return
	if game.rules.bag.size() >= game.rules.capacity():
		game._notice("随身背包已满（%d/%d格），请先撤离入库！" % [game.rules.bag.size(), game.rules.capacity()])
		game.play_sfx("hit_wrong", -14)
		return

	active_crate = crate_node
	target_word = _pick_spelling_word()
	attempts = 0
	unlocked = false
	perfect_crack = false
	pending_loot.clear()
	_clear_loot_cards()

	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var tier_tag = ["普通密码箱", "高级金库箱", "特级空投密码箱"][clampi(tier - 1, 0, 2)]
	title_label.text = "%s · 单词拼写破译" % crate_title
	meta_label.text = "%s  |  Unit %d · 课本第 %d 页  |  输入对应英文即可开箱摸金" % [tier_tag, int(target_word.get("unit", 1)), int(target_word.get("textbook_page", 1))]
	prompt_label.text = "中文释义：【 %s 】" % target_word.chinese
	mask_label.text = _build_mask(target_word.english, tier, false)
	status_label.text = "请在上方输入框键入准确的英文拼写，按 Enter 键解锁。"
	status_label.add_theme_color_override("font_color", game.GOLD)

	input_box.editable = true
	input_box.text = ""
	submit_button.disabled = false
	submit_button.text = "破译开箱 [Enter]"
	swap_button.hide()
	overlay.show()
	input_box.grab_focus()

func _speak_hint():
	if not target_word.is_empty():
		game.speak_english(target_word.english)

func _normalize(s: String) -> String:
	var clean = s.replace("’", "'").strip_edges().to_lower()
	while "  " in clean:
		clean = clean.replace("  ", " ")
	return clean

func submit_text(typed: String):
	input_box.text = typed
	submit()

func submit():
	if not busy or unlocked or not is_instance_valid(active_crate):
		return
	var expected = _normalize(target_word.english)
	var actual = _normalize(input_box.text)
	if actual == "":
		status_label.text = "输入不能为空，请拼写对应的英文单词！"
		return
	attempts += 1
	if actual == expected:
		unlocked = true
		perfect_crack = attempts <= 2
		input_box.editable = false
		submit_button.disabled = true
		var crate_title: String = active_crate.get_meta("title")
		var tier: int = int(active_crate.get_meta("tier"))
		var awarded = game.rules.open_crate(crate_title, tier, perfect_crack)
		if perfect_crack:
			game.rules.record_word_spelled(target_word.id)
		active_crate.get_child(active_crate.get_child_count() - 1).modulate = game.MINT
		if active_crate.has_meta("lid_node") and is_instance_valid(active_crate.get_meta("lid_node")):
			active_crate.get_meta("lid_node").rotation.x = -0.85
		game.speak_english(target_word.english)
		var has_epic = false
		for item in awarded:
			if int(item.get("rarity", 1)) >= 4:
				has_epic = true
		game.play_sfx("loot_epic" if has_epic else "cipher_unlock", -10)
		_render_loot_cards(awarded)
		if perfect_crack:
			status_label.text = "★ 完美破译！ +%d 分 · 拼写准确：%s — 已开启高爆率战利品！" % [game.Rules.CIPHER_PERFECT_SCORE, target_word.english]
			status_label.add_theme_color_override("font_color", game.MINT)
		else:
			status_label.text = "密码箱已开启！记住拼写：%s（%s）" % [target_word.english, target_word.chinese]
			status_label.add_theme_color_override("font_color", game.GOLD)
		close_button.text = "收下物资 [Esc]"
	else:
		game.play_sfx("hit_wrong", -12)
		var matched = 0
		for i in mini(actual.length(), expected.length()):
			if actual[i] == expected[i]:
				matched += 1
			else:
				break
		if attempts == 1:
			status_label.text = "拼写有误（前 %d 个字符正确）。可点右侧「🔊 发音提示」再试一次！" % matched
			status_label.add_theme_color_override("font_color", Color("f5b971"))
			input_box.select_all()
			input_box.grab_focus()
		else:
			mask_label.text = _build_mask(target_word.english, 1, true)
			game.speak_english(target_word.english)
			status_label.text = "已显示正确拼写，请对照上方正确单词完整输入一遍即可开箱！"
			status_label.add_theme_color_override("font_color", Color("ff9e7d"))
			if target_word not in game.wrong_words:
				game.wrong_words.append(target_word)
			game.rules.record_word_result(target_word.id, false)
			input_box.select_all()
			input_box.grab_focus()

func _clear_loot_cards():
	for child in loot_container.get_children():
		child.queue_free()

func _render_loot_cards(items: Array):
	_clear_loot_cards()
	for item in items:
		var r: int = int(item.get("rarity", 1))
		var r_color: Color = game.Rules.RARITY_COLORS[r]
		var r_name: String = game.Rules.RARITY_NAMES[r]
		var card = Panel.new()
		card.custom_minimum_size = Vector2(228, 78)
		var st = StyleBoxFlat.new()
		st.bg_color = Color(r_color.r * 0.16, r_color.g * 0.16, r_color.b * 0.18, 0.95)
		st.border_color = r_color
		st.set_border_width_all(2)
		st.set_corner_radius_all(7)
		card.add_theme_stylebox_override("panel", st)
		loot_container.add_child(card)
		var tag = game._text(card, "【%s】" % r_name, Vector2(10, 8), Vector2(208, 22), 14, r_color)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var name_lbl = game._text(card, item.title, Vector2(8, 30), Vector2(212, 24), 17, game.CREAM)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var val_lbl = game._text(card, "估值 %d 币" % int(item.value), Vector2(8, 53), Vector2(212, 20), 13, game.GOLD)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _swap_lowest():
	pass

func close():
	if not busy:
		return
	busy = false
	overlay.hide()
	close_button.text = "关闭返回 [Esc]"
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(game.exploration):
		game.exploration.grace = maxf(game.exploration.grace, 2.5)
