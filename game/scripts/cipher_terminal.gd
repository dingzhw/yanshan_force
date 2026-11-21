extends Node
## v0.6.3 Tiered English Cipher & Magnifying-Glass Loot Reveal Terminal:
## - Regular Supply Boxes: 1-stage word spelling (+ Overcharged golden box bonus & 6-tier miracle jackpot!)
## - Tier 1/2/3 Vaults: 2–3 stage English combo with visible Perfect-Crack Luck Multiplier & Tier 6 '旷世·大红'
## - Squad Drop Pouches: Instant unlocking into escalating Magnifying-Glass Slot-by-Slot Inspection!

const LootUI = preload("res://scripts/loot_ui.gd")
const LearningStore = preload("res://scripts/learning_store.gd")
const SrsScheduler = preload("res://scripts/srs_scheduler.gd")

var game
var busy = false
var mode = "crate" # "supply" or "crate"
var active_crate: Node3D
var stages: Array = []
var stage_index = 0
var target_word: Dictionary = {}
var attempts = 0
var spelling_help_used := false
var retest_revealed_ids: Dictionary = {}
var retest_requeued_ids: Dictionary = {}
var all_stages_perfect = true
var unlocked = false
var perfect_crack = false
var displayed_loot: Array = []
var pending_loot: Array = []

var overlay: Control
var title_label: Label
var meta_label: Label
var stage_label: Label
var prompt_label: Label
var mask_label: Label
var input_box: LineEdit
var status_label: Label
var footer_hint: Label
var submit_button: Button
var speak_button: Button
var hint_button: Button
var close_button: Button
var swap_button: Button
var loot_container: HBoxContainer
var reveal_slots: Array = []
var reveal_cursor: int = 0
var reveal_timer: float = 0.0
var reveal_duration: float = 0.3
var reveal_tick_acc: float = 0.0
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

	game._panel(overlay, Rect2(200, 62, 880, 596), Color(0.052, 0.106, 0.132, 0.98), Color(0.45, 0.82, 0.68, 0.58))
	title_label = game._text(overlay, "战术密码箱 · 英语破译终端", Vector2(242, 84), Vector2(680, 38), 27, game.MINT)
	meta_label = game._text(overlay, "", Vector2(242, 124), Vector2(796, 24), 14, Color("9ec4b5"))

	stage_label = game._text(overlay, "", Vector2(242, 154), Vector2(796, 28), 16, Color("ffd166"))
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	prompt_label = game._text(overlay, "", Vector2(242, 188), Vector2(796, 62), 27, game.CREAM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	mask_label = game._text(overlay, "", Vector2(242, 254), Vector2(796, 44), 22, game.GOLD)
	mask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	input_box = LineEdit.new()
	input_box.position = Vector2(304, 308)
	input_box.size = Vector2(506, 52)
	input_box.placeholder_text = "输入准确的英文内容，按 Enter 验证…"
	input_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_box.keep_editing_on_text_submit = true
	input_box.add_theme_font_size_override("font_size", 22)
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

	speak_button = game._button(overlay, "🔊 发音 [Tab]", Rect2(822, 308, 154, 52), _speak_hint)
	submit_button = game._button(overlay, "验证破译 [Enter]", Rect2(304, 372, 316, 46), submit, true)
	hint_button = game._button(overlay, "查看字母提示", Rect2(636, 372, 340, 46), _show_spelling_hint)
	hint_button.hide()
	swap_button = game._button(overlay, "替换背包最低值物资", Rect2(636, 372, 340, 46), _swap_lowest)
	swap_button.hide()

	status_label = game._text(overlay, "", Vector2(242, 422), Vector2(796, 44), 16, game.GOLD)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	loot_container = HBoxContainer.new()
	loot_container.position = Vector2(218, 470)
	loot_container.size = Vector2(844, 114)
	loot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	loot_container.add_theme_constant_override("separation", 12)
	overlay.add_child(loot_container)

	footer_hint = game._text(overlay, "开箱后可按 Space 跳过物资搜索。", Vector2(232, 598), Vector2(628, 30), 12, Color("8fb2a4"))
	close_button = game._button(overlay, "关闭返回 [Esc]", Rect2(868, 590, 174, 38), close)
	overlay.hide()

func _input(event):
	if not busy or mode == "retest":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_TAB:
			_speak_hint()
			get_viewport().set_input_as_handled()
		elif code == KEY_SPACE and unlocked and reveal_cursor < reveal_slots.size():
			reveal_all_immediately()
			get_viewport().set_input_as_handled()

func reset():
	busy = false
	unlocked = false
	active_crate = null
	stages.clear()
	stage_index = 0
	displayed_loot.clear()
	pending_loot.clear()
	for node in game.crate_nodes + game.pickup_nodes:
		if is_instance_valid(node) and node.has_meta("unclaimed_loot"):
			node.remove_meta("unclaimed_loot")
	if is_instance_valid(overlay):
		overlay.hide()

func stage_count() -> int:
	return stages.size()

func _selected_unit() -> int:
	return game.unit_picker.selected if is_instance_valid(game.unit_picker) else 0

func _pick_word_entry(prefer_longer: bool) -> Dictionary:
	var source_pool: Array = game.pool if not game.pool.is_empty() else game.words
	var candidates := []
	for w in source_pool:
		var en: String = str(w.get("english", "")).strip_edges()
		if w.get("kind", "word") != "word" or w.get("proper_name", false):
			continue
		if "..." in en or " " in en or en.length() < 3 or en.length() > 14:
			continue
		if prefer_longer and en.length() < 5:
			continue
		candidates.append(w)
	if candidates.is_empty():
		for w in game.words:
			var en2: String = str(w.get("english", "")).strip_edges()
			if w.get("kind", "word") == "word" and not (" " in en2) and not ("..." in en2) and not w.get("proper_name", false):
				candidates.append(w)
	var best: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var best_score := -1.0
	for i in mini(6, candidates.size()):
		var c: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		var s: float = game.rules.word_priority(str(c.get("id", ""))) + rng.randf() * 0.6
		if s > best_score:
			best_score = s
			best = c
	var entry := best.duplicate(true)
	entry["challenge_tag"] = "进阶词汇锁" if prefer_longer else "核心单词锁"
	return entry

func _pick_phrase_entry() -> Dictionary:
	var sel_u := _selected_unit()
	var candidates := []
	for pass_idx in 2:
		for w in game.words:
			var en: String = str(w.get("english", "")).strip_edges()
			if w.get("kind", "") != "phrase" or w.get("proper_name", false):
				continue
			if "..." in en or "one’s" in en or "one's" in en:
				continue
			if pass_idx == 0 and sel_u > 0 and int(w.get("unit", 0)) != sel_u:
				continue
			candidates.append(w)
		if not candidates.is_empty():
			break
	var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)
	picked["challenge_tag"] = "重点词组锁"
	return picked

func _pick_sentence_entry(prefer_short: bool) -> Dictionary:
	var sel_u := _selected_unit()
	var candidates: Array = game.sentences.filter(func(s): return sel_u <= 0 or int(s.unit) == sel_u)
	if candidates.is_empty():
		candidates = game.sentences
	var by_length := candidates.filter(func(s):
		var word_count := str(s.english).split(" ", false).size()
		return word_count <= 4 if prefer_short else word_count >= 4
	)
	if not by_length.is_empty():
		candidates = by_length
	var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)
	picked["challenge_tag"] = "教材短句锁" if prefer_short else "整句声纹锁"
	return picked

func _build_mask(entry: Dictionary, reveal_all: bool = false) -> String:
	var clean := str(entry.english).replace("’", "'").strip_edges()
	if reveal_all:
		return "正确拼写：  " + clean
	var kind := str(entry.get("kind", "word"))
	if kind == "word" and not (" " in clean):
		var chars := []
		var n := clean.length()
		for i in n:
			var ch := clean[i]
			if ch == "-" or ch == "'":
				chars.append(ch)
			elif i == 0 or (i == n - 1 and n >= 4):
				chars.append(ch)
			else:
				chars.append("_")
		return "单词结构： " + " ".join(chars) + "   （共 %d 字母）" % n
	# Multi-word phrase or full sentence: show word frames & leading hints clearly
	var words_arr := clean.split(" ", false)
	var masked_words := []
	for w_idx in words_arr.size():
		var tok := words_arr[w_idx]
		var punct := ""
		if tok.ends_with(".") or tok.ends_with("!") or tok.ends_with("?"):
			punct = tok.right(1)
			tok = tok.left(tok.length() - 1)
		var letters := []
		for i in tok.length():
			var c := tok[i]
			if c == "'" or c == "-":
				letters.append(c)
			elif i == 0:
				letters.append(c)
			else:
				letters.append("_")
		masked_words.append("".join(letters) + punct)
	var type_label := "词组" if kind == "phrase" else "句子"
	return "%s结构： %s   （共 %d 词，标点可省）" % [type_label, "   ".join(masked_words), words_arr.size()]

func _enter_modal():
	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hint_button.hide()
	speak_button.show()
	overlay.show()

func _focus_input_box():
	if not is_instance_valid(input_box) or not input_box.editable:
		return
	input_box.grab_focus()
	input_box.set_caret_column(input_box.text.length())
	input_box.call_deferred("grab_focus")
	input_box.call_deferred("set_caret_column", input_box.text.length())

func _refresh_stage_ui():
	target_word = stages[stage_index]
	attempts = 0
	spelling_help_used = false
	var total := stages.size()
	var dots := []
	for i in total:
		dots.append("✓" if i < stage_index else ("●" if i == stage_index else "○"))
	var tag := str(target_word.get("challenge_tag", "英语解锁"))
	if total == 1:
		stage_label.text = "🔓 单关验证 · 【%s】" % tag
	else:
		stage_label.text = "🔐 多重加密进度：%s   第 %d / %d 关 · 【%s】" % ["  ".join(dots), stage_index + 1, total, tag]

	var kind := str(target_word.get("kind", "word"))
	var prefix := "中文句意" if kind == "sentence" else ("词组释义" if kind == "phrase" else "单词释义")
	prompt_label.text = "%s：【 %s 】" % [prefix, target_word.chinese]
	if mode != "retest":
		var cloze: Dictionary = game.cloze_for_word(str(target_word.get("id", "")))
		if not cloze.is_empty():
			prompt_label.text += "\n语境填空：%s" % cloze.cloze_text
	mask_label.text = ""

	var unit_str := "Unit %d · 课本第 %d 页" % [int(target_word.get("unit", 1)), int(target_word.get("textbook_page", 1))]
	match str(target_word.get("source_kind", "")):
		"textbook_verbatim": unit_str += " · 课文原句"
		"phrase_extension": unit_str += " · 教材词组拓展"
	if mode == "retest":
		stage_label.text = "复测 %d / %d" % [stage_index + 1, total]
		meta_label.text = unit_str
	elif mode == "supply":
		meta_label.text = "野外加密物资盲盒（一次拼对触发幸运加成，一切品质皆有可能！）  |  %s" % unit_str
	else:
		var tier := int(active_crate.get_meta("tier"))
		var tier_desc: String = [
			"前哨密码箱（单词+词组 2连破 · 未知盲盒开箱鉴定）",
			"精密密码箱（词组+短句 2连破 · 未知盲盒多格鉴定）",
			"深藏加密箱（词汇+词组+整句 3重破译 · 未知盲盒多格鉴定）"
		][clampi(tier - 1, 0, 2)]
		meta_label.text = "%s  |  %s" % [tier_desc, unit_str]

	input_box.editable = true
	input_box.text = ""
	speak_button.visible = mode != "retest"
	hint_button.visible = mode != "retest"
	submit_button.disabled = false
	submit_button.text = ("验证下一关 [Enter]" if stage_index + 1 < total else "破译开箱 [Enter]")
	if mode == "retest":
		submit_button.text = "提交复测 [Enter]"
	if is_instance_valid(footer_hint):
		footer_hint.text = "提示：直接连续打字并按 Enter 自动切换下一复测词条（无需重新点击输入框）。" if mode == "retest" else "开箱后可按 Space 跳过物资搜索。"
	close_button.text = "关闭返回 [Esc]"
	_focus_input_box()

func open_retest(entries: Array):
	if busy or entries.is_empty():
		return
	mode = "retest"
	stages = entries.duplicate()
	stage_index = 0
	retest_revealed_ids.clear()
	retest_requeued_ids.clear()
	active_crate = null
	unlocked = false
	busy = true
	_clear_loot_cards()
	swap_button.hide()
	overlay.show()
	title_label.text = "单词与句型复测"
	status_label.text = "根据中文独立写出英文。答错后先学习正解，稍后换序练习（看答案后输入仅计练习完成，不虚计独立答对）。"
	status_label.add_theme_color_override("font_color", game.CREAM)
	_refresh_stage_ui()

func open_for_supply(pickup_node: Node3D):
	if not is_instance_valid(pickup_node) or not pickup_node.visible:
		return
	# v0.8.4: Previously unlocked supply box with leftover items opens LootContainerUI directly (no re-spelling!)
	if pickup_node.has_meta("pending_items"):
		var saved_p: Array = pickup_node.get_meta("pending_items")
		if not saved_p.is_empty() and is_instance_valid(game.loot_container_ui):
			game.loot_container_ui.open_container(
				pickup_node, "supply", str(pickup_node.get_meta("title", "野外物资箱")),
				saved_p, "已解锁物资箱 · 自由选择拾取入包、存安全箱或留在箱内", false
			)
			return
	mode = "supply"
	active_crate = pickup_node
	_clear_loot_cards()
	swap_button.hide()

	stages = [_pick_word_entry(false)]
	stage_index = 0
	all_stages_perfect = true
	unlocked = false
	perfect_crack = false
	displayed_loot.clear()
	pending_loot.clear()

	_enter_modal()
	title_label.text = "%s · 单词拼写解锁" % str(pickup_node.get_meta("title", "野外物资箱"))
	_refresh_stage_ui()
	status_label.text = "输入英文单词解锁并进入【确认拾取面板】（一次拼对触发幸运加成，按 Tab 听读音）！"
	status_label.add_theme_color_override("font_color", game.GOLD)

func open_for_drop_pouch(drop_node: Node3D):
	if not is_instance_valid(drop_node) or not drop_node.visible:
		return
	var pouch_title: String = str(drop_node.get_meta("title", "词兵战术掉落包"))
	var flawless: bool = bool(drop_node.get_meta("flawless", false))
	var items_arr: Array = []
	if drop_node.has_meta("pending_items"):
		items_arr = drop_node.get_meta("pending_items").duplicate(true)
	elif drop_node.has_meta("unclaimed_loot"):
		items_arr = drop_node.get_meta("unclaimed_loot").duplicate(true)
	else:
		items_arr = drop_node.get_meta("drop_items", []).duplicate(true)
	if items_arr.is_empty():
		drop_node.visible = false
		game.cached_interactables.clear()
		return
	var already_scanned: bool = bool(drop_node.get_meta("scanned", false))
	var sub_txt := ("★ 零失误精准歼敌 · 掉落品质已升阶！请自由选择拾取或存安全箱。" if flawless else "✓ 战斗缴获黑匣挂包（免拼写）· 请自由选择拾取或留箱。")
	if is_instance_valid(game.loot_container_ui):
		game.loot_container_ui.open_container(drop_node, "squad_drop", pouch_title, items_arr, sub_txt, not already_scanned)

func open_for_crate(crate_node: Node3D):
	var crate_title: String = crate_node.get_meta("title")
	var tier: int = int(crate_node.get_meta("tier"))

	# v0.8.4: Previously unlocked password crate with remaining items opens LootContainerUI directly!
	if crate_node.has_meta("pending_items"):
		var saved_c: Array = crate_node.get_meta("pending_items")
		if not saved_c.is_empty() and is_instance_valid(game.loot_container_ui):
			game.loot_container_ui.open_container(
				crate_node, "crate", crate_title, saved_c,
				"密码箱已解锁 · 自由勾选剩余高价值战利品，右侧可整理背包腾位", false
			)
			return

	if crate_title in game.rules.crates:
		game._notice(crate_title + " 已破译并搜空。")
		return
	if not game.rules.crate_ready(tier):
		var req = game.rules.crate_requirements(tier)
		game._notice("需至少答 %d 题且正确率达 %d%% 才能连接此密码箱！" % [req.minimum, roundi(req.accuracy * 100)])
		game.play_sfx("hit_wrong", -14)
		return

	mode = "crate"
	active_crate = crate_node
	if tier <= 1:
		stages = [_pick_word_entry(false), _pick_phrase_entry()]
	elif tier == 2:
		stages = [_pick_phrase_entry(), _pick_sentence_entry(true)]
	else:
		stages = [_pick_word_entry(true), _pick_phrase_entry(), _pick_sentence_entry(false)]

	stage_index = 0
	all_stages_perfect = true
	unlocked = false
	perfect_crack = false
	displayed_loot.clear()
	pending_loot.clear()
	_clear_loot_cards()
	swap_button.hide()

	_enter_modal()
	title_label.text = "%s · 阶梯式英语破译" % crate_title
	_refresh_stage_ui()
	status_label.text = "完成全部 %d 关英语验证即打开【确认拾取面板】（完美破译大幅提升大金/大红概率）！" % stages.size()
	status_label.add_theme_color_override("font_color", game.GOLD)

func _speak_hint():
	if busy and not unlocked and mode != "retest" and not target_word.is_empty() and game.has_english_voice(str(target_word.english)):
		spelling_help_used = true
		game.speak_english(str(target_word.english))

func _show_spelling_hint():
	if busy and not unlocked and mode != "retest":
		spelling_help_used = true
		mask_label.text = _build_mask(target_word, false)
		input_box.grab_focus()

func _canonical(s: String) -> String:
	var t := s.replace("’", "'").replace("‘", "'").to_lower().strip_edges()
	for ch in [".", "!", "?", ",", ";", ":"]:
		t = t.replace(ch, " ")
	t = t.replace("-", " ")
	# Normalize common textbook contractions & BrE/AmE variants so valid forms always pass
	var pairs := [
		["it's", "it is"],
		["don't", "do not"],
		["let's", "let us"],
		["can't", "cannot"],
		["what's", "what is"],
		["i'm", "i am"],
		["favourite", "favorite"],
		["neighbour", "neighbor"]
	]
	for p in pairs:
		t = t.replace(p[0], p[1])
	while "  " in t:
		t = t.replace("  ", " ")
	return t.strip_edges()

func _is_match(typed: String, entry: Dictionary) -> bool:
	var actual := _canonical(typed)
	if actual == "":
		return false
	if actual == _canonical(str(entry.english)):
		return true
	for alias in entry.get("aliases", []):
		if actual == _canonical(str(alias)):
			return true
	return false

func submit_text(typed: String):
	input_box.text = typed
	submit()

func solve_all_for_qa():
	var guard := 0
	while busy and not unlocked and guard < 8:
		guard += 1
		submit_text(str(target_word.english))
	reveal_all_immediately()

func _try_claim_pending():
	var still_unclaimed := []
	for item in pending_loot:
		if not game.rules.add_loot_item(item):
			still_unclaimed.append(item)
	pending_loot = still_unclaimed

	if mode in ["supply", "drop_pouch"]:
		if pending_loot.is_empty():
			if is_instance_valid(active_crate):
				if active_crate.has_meta("unclaimed_loot"):
					active_crate.remove_meta("unclaimed_loot")
				if mode == "supply":
					game.Props.set_enabled(active_crate, false)
				else:
					active_crate.visible = false
					game.cached_interactables.clear()
			swap_button.hide()
		else:
			if is_instance_valid(active_crate):
				active_crate.set_meta("unclaimed_loot", pending_loot.duplicate(true))
			_update_swap_button()
	else:
		if pending_loot.is_empty():
			if is_instance_valid(active_crate) and active_crate.has_meta("unclaimed_loot"):
				active_crate.remove_meta("unclaimed_loot")
			swap_button.hide()
		else:
			if is_instance_valid(active_crate):
				active_crate.set_meta("unclaimed_loot", pending_loot.duplicate(true))
			_update_swap_button()

func _update_swap_button():
	if pending_loot.is_empty() or game.rules.bag.is_empty():
		swap_button.hide()
		return
	var low_idx: int = game.rules.lowest_bag_index()
	var low_item: Dictionary = game.rules.bag[low_idx]
	var next_item: Dictionary = pending_loot[0]
	swap_button.text = "替换最低物资（%s %d币 → %d币）" % [low_item.title, int(low_item.value), int(next_item.value)]
	swap_button.show()

func submit():
	if not busy or unlocked or (mode != "retest" and not is_instance_valid(active_crate)):
		return
	var raw_typed := input_box.text.strip_edges()
	if raw_typed == "":
		status_label.text = "输入不能为空，请输入对应的英文内容！"
		_focus_input_box()
		return
	attempts += 1
	if mode == "retest":
		_submit_retest(raw_typed)
		return
	if _is_match(raw_typed, target_word):
		var outcome := LearningStore.INDEPENDENT
		if attempts > 2:
			outcome = LearningStore.COPIED
		elif attempts > 1 or spelling_help_used:
			outcome = LearningStore.HINTED
		all_stages_perfect = all_stages_perfect and outcome == LearningStore.INDEPENDENT
		game.rules.learning.record_spelling(str(target_word.id), outcome, false, -1, attempts == 1)
		if outcome != LearningStore.INDEPENDENT and target_word not in game.wrong_words:
			game.wrong_words.append(target_word)
		game.speak_english(str(target_word.english))

		# Multi-stage advance!
		if stage_index + 1 < stages.size():
			game.play_sfx("hit_correct", -11)
			var passed_en := str(target_word.english)
			stage_index += 1
			_refresh_stage_ui()
			status_label.text = "✓ 第 %d 关通过（%s）！请继续破解第 %d / %d 关！" % [stage_index, passed_en, stage_index + 1, stages.size()]
			status_label.add_theme_color_override("font_color", game.MINT)
			return

		# Final stage cleared -> Unlock container & hand off cleanly to v0.8.4 Selective LootContainerUI!
		unlocked = true
		perfect_crack = all_stages_perfect
		if is_instance_valid(game.rangers):
			game.rangers.record_bounty_progress("box_cracked", 1)
		input_box.editable = false
		submit_button.disabled = true
		hint_button.hide()

		if mode == "supply":
			var sid := str(active_crate.get_meta("supply_id", active_crate.name))
			var is_over: bool = active_crate.has_meta("overcharged")
			if not (sid in game.rules.supplies_opened):
				game.rules.supplies_opened.append(sid)
				if perfect_crack:
					game.rules.score += game.Rules.SUPPLY_PERFECT_SCORE
			var item: Dictionary = game.rules.roll_field_pickup(perfect_crack, is_over)
			displayed_loot = [item]
			pending_loot = [item]
			game.play_sfx("cipher_unlock", -11)
			var sup_title := str(active_crate.get_meta("title", "野外物资箱"))
			var sup_sub := ("★ 完美拼写破译 +%d 分（爆率加成已激活）· 请勾选是否拾取或存安全箱" % game.Rules.SUPPLY_PERFECT_SCORE) if perfect_crack else ("✓ 电子锁已解除（拼写：%s）· 请选择是否拾取或留在箱内" % str(target_word.english))
			_handoff_to_loot_container(active_crate, "supply", sup_title, [item], sup_sub, true)
		else:
			var crate_title: String = active_crate.get_meta("title")
			var tier: int = int(active_crate.get_meta("tier"))
			var bonus_pts: int = game.Rules.CIPHER_PERFECT_SCORE + maxi(0, tier - 1) * 10
			var rolled_items: Array = game.rules.unlock_crate_pending(crate_title, tier, perfect_crack)
			displayed_loot = rolled_items.duplicate(true)
			pending_loot = rolled_items.duplicate(true)

			if active_crate.has_meta("lid_node") and is_instance_valid(active_crate.get_meta("lid_node")):
				active_crate.get_meta("lid_node").rotation.x = -0.55

			game.play_sfx("cipher_unlock", -10)
			var crate_sub := ("★ 完美破译全通 +%d 分（爆率加成已激活）· 放大镜鉴定后自由选择要带走的物资！" % bonus_pts) if perfect_crack else "✓ 密码箱已解锁 · 放大镜鉴定后自由选择要带走的物资，未选物资将留在箱内！"
			_handoff_to_loot_container(active_crate, "crate", crate_title, rolled_items, crate_sub, true)
	else:
		game.play_sfx("hit_wrong", -12)
		var clean_exp := str(target_word.english).replace("’", "'").strip_edges()
		var matched := 0
		for i in mini(raw_typed.length(), clean_exp.length()):
			if raw_typed.to_lower()[i] == clean_exp.to_lower()[i]:
				matched += 1
			else:
				break
		if attempts == 1:
			game.rules.learning.record_spelling(str(target_word.id), LearningStore.INCORRECT, false, -1, true)
			if target_word not in game.wrong_words:
				game.wrong_words.append(target_word)
			status_label.text = "输入有误（前 %d 个字符匹配）。可按 [Tab] 听发音提示再试一次！" % matched
			status_label.add_theme_color_override("font_color", Color("f5b971"))
			input_box.select_all()
			input_box.grab_focus()
		else:
			all_stages_perfect = false
			mask_label.text = _build_mask(target_word, true)
			game.speak_english(str(target_word.english))
			status_label.text = "已展示正确英文参考，请对照上方完整输入一遍即可通过本关！"
			status_label.add_theme_color_override("font_color", Color("ff9e7d"))
			hint_button.hide()
			input_box.select_all()
			input_box.grab_focus()

func _submit_retest(typed: String):
	var is_correct := _is_match(typed, target_word)
	var tid := str(target_word.id)
	var cloze: Dictionary = game.cloze_for_word(tid)
	var example_suffix := (" · 例句：%s" % cloze.english) if not cloze.is_empty() else ""
	var feedback := ""
	if is_correct:
		var was_revealed: bool = retest_revealed_ids.has(tid) or game.rules.learning.was_recently_revealed(tid)
		if was_revealed:
			game.rules.learning.record_spelling(tid, LearningStore.PRACTICED, true, -1, true, "retest_spell")
			feedback = "✓ 练习完成（看答案后拼出，不计入独立答对；下次继续巩固）。"
		else:
			game.rules.learning.record_spelling(tid, LearningStore.INDEPENDENT, true, -1, true, "retest_spell")
			var entry: Dictionary = game.rules.profile.mastery.get(tid, {})
			var stage := int(entry.get("srs_stage", 0))
			feedback = "★ 独立答对！已排入【%s】复习计划。" % SrsScheduler.stage_label(stage)
		game.play_sfx("hit_correct", -11)
	else:
		retest_revealed_ids[tid] = true
		game.rules.learning.mark_answer_revealed(tid)
		game.rules.learning.record_spelling(tid, LearningStore.INCORRECT, true, -1, true, "retest_spell")
		if not retest_requeued_ids.has(tid):
			retest_requeued_ids[tid] = true
			stages.append(target_word)
		feedback = "先学习正解：%s%s · 稍后将换序巩固练习。" % [target_word.english, example_suffix]
		game.play_sfx("hit_wrong", -12)
		game.speak_english(str(target_word.english))
	game._save()
	if stage_index + 1 < stages.size():
		stage_index += 1
		_refresh_stage_ui()
	else:
		unlocked = true
		input_box.editable = false
		submit_button.disabled = true
		var rem_due: int = game._pending_retest().size()
		if rem_due == 0:
			stage_label.text = "今日复习全部完成！"
			feedback += "\n🎉 今日到期复习已清零，所有行动模式现已解锁！"
			game.play_sfx("cipher_unlock", -10)
		else:
			stage_label.text = "本组复测结束（仍余 %d 题）" % rem_due
		game._refresh_progress()
	status_label.text = feedback

func _swap_lowest():
	if not busy or not unlocked or pending_loot.is_empty() or game.rules.bag.is_empty():
		return
	reveal_all_immediately()
	var next_item: Dictionary = pending_loot.pop_front()
	var removed: Dictionary = game.rules.swap_lowest_loot(next_item)
	if not removed.is_empty():
		var r: int = clampi(int(next_item.get("rarity", 1)), 1, 7)
		game.play_sfx("loot_mythic_red" if r == 7 else ("loot_epic" if r >= 5 else "cipher_unlock"), -10)
		status_label.text = "已将【%s（%d币）】替换为【%s】%s（%d币）！" % [
			removed.title, int(removed.value),
			game.Rules.RARITY_NAMES[r], next_item.title, int(next_item.value)
		]
		status_label.add_theme_color_override("font_color", game.Rules.RARITY_COLORS[r])
	_try_claim_pending()

func _clear_loot_cards():
	reveal_slots.clear()
	reveal_cursor = 0
	reveal_timer = 0.0
	for child in loot_container.get_children():
		child.queue_free()

func _scan_duration_for(rarity: int) -> float:
	if rarity >= 7:
		return 1.20
	if rarity == 6:
		return 0.92
	if rarity == 5:
		return 0.72
	if rarity == 4:
		return 0.52
	if rarity == 3:
		return 0.38
	return 0.24

func _render_loot_cards(items: Array, animate: bool = true):
	_clear_loot_cards()
	for idx in items.size():
		var item: Dictionary = items[idx]
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		var r_color: Color = game.Rules.RARITY_COLORS[r]
		var r_name: String = game.Rules.RARITY_NAMES[r]
		var grid_tag: String = str(item.get("grid", "1×1"))
		var is_big: bool = grid_tag.begins_with("2×")
		var card_w: float = 264.0 if is_big else 224.0

		var card := Panel.new()
		card.custom_minimum_size = Vector2(card_w, 108)
		card.pivot_offset = Vector2(card_w * 0.5, 54.0)
		loot_container.add_child(card)

		# Revealed content layer
		var revealed_root := Control.new()
		revealed_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(revealed_root)

		var ic := LootUI.create_icon(item, r_color, Vector2(48, 48))
		ic.position = Vector2(10, 14)
		revealed_root.add_child(ic)

		var cond_str: String = str(item.get("cond", "标准"))
		var badge_txt: String = "【%s · %s】" % [r_name, cond_str]
		game._text(revealed_root, badge_txt, Vector2(60, 8), Vector2(card_w - 68, 20), 12, r_color)
		var ct_lbl: Label = game._text(revealed_root, str(item.get("title", "物资")), Vector2(60, 29), Vector2(card_w - 68, 24), 16, game.CREAM)
		ct_lbl.clip_text = true
		var ce_lbl: Label = game._text(revealed_root, "%s · [%s]" % [str(item.get("en", "Supply")), grid_tag], Vector2(60, 53), Vector2(card_w - 66, 18), 10, Color("9adbc0"))
		ce_lbl.clip_text = true
		ce_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var val_lbl: Label = game._text(revealed_root, "鉴定估值  %d 币" % int(item.value), Vector2(12, 78), Vector2(card_w - 24, 22), 14, Color("ff6b7a") if r == 7 else game.GOLD)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Unsearched Mystery Magnifying-Glass Cover Layer!
		var cover := Control.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(cover)
		var myst_hint: String = "🔍 大型物件 [%s]" % grid_tag if is_big else "🔍 搜索物资槽 [%s]" % grid_tag
		var m_lbl: Label = game._text(cover, myst_hint, Vector2(8, 24), Vector2(card_w - 16, 26), 15, Color("9ec4b5"))
		m_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sub_m: Label = game._text(cover, "等待放大镜逐格鉴定...", Vector2(8, 52), Vector2(card_w - 16, 20), 12, Color("729689"))
		sub_m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var bar_bg := ColorRect.new()
		bar_bg.position = Vector2(16, 84)
		bar_bg.size = Vector2(card_w - 32, 7)
		bar_bg.color = Color(1, 1, 1, 0.10)
		cover.add_child(bar_bg)
		var bar_fill := ColorRect.new()
		bar_fill.position = Vector2(16, 84)
		bar_fill.size = Vector2(0, 7)
		bar_fill.color = game.MINT
		cover.add_child(bar_fill)

		# Click card anytime to instant-reveal!
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		click_btn.pressed.connect(reveal_all_immediately)
		cover.add_child(click_btn)

		var slot_entry := {
			"card": card,
			"revealed_root": revealed_root,
			"cover": cover,
			"m_lbl": m_lbl,
			"sub_m": sub_m,
			"bar_fill": bar_fill,
			"bar_max": card_w - 32.0,
			"item": item,
			"rarity": r,
			"color": r_color
		}
		reveal_slots.append(slot_entry)
		_apply_card_mystery_style(slot_entry, false)

	if not animate or reveal_slots.is_empty():
		reveal_all_immediately()
	else:
		reveal_cursor = 0
		reveal_timer = 0.0
		reveal_tick_acc = 0.0
		reveal_duration = _scan_duration_for(int(reveal_slots[0].rarity))
		_apply_card_mystery_style(reveal_slots[0], true)

func _apply_card_mystery_style(slot: Dictionary, active_scanning: bool):
	var card: Panel = slot.card
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.09, 0.11, 0.96) if active_scanning else Color(0.04, 0.07, 0.09, 0.92)
	st.border_color = game.MINT if active_scanning else Color(0.35, 0.56, 0.50, 0.45)
	st.set_border_width_all(2 if active_scanning else 1)
	st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	slot.revealed_root.hide()
	slot.cover.show()
	if active_scanning:
		var r: int = int(slot.rarity)
		if r >= 7:
			slot.sub_m.text = "⚠ 侦测到旷世奇珍超高能波形！！"
			slot.sub_m.add_theme_color_override("font_color", Color("ff6b7a"))
			slot.bar_fill.color = Color("ff4757")
		elif r == 6:
			slot.sub_m.text = "✦ 发现传说大金高价值信号！"
			slot.sub_m.add_theme_color_override("font_color", Color("ff9f38"))
			slot.bar_fill.color = Color("ff9f38")
		elif r == 5:
			slot.sub_m.text = "◆ 捕捉到温润珍品小金光芒！"
			slot.sub_m.add_theme_color_override("font_color", Color("f6c34e"))
			slot.bar_fill.color = Color("f6c34e")
		else:
			slot.sub_m.text = "🔍 放大镜鉴定中..."

func _reveal_single_slot(idx: int, with_audio: bool):
	if idx < 0 or idx >= reveal_slots.size():
		return
	var slot: Dictionary = reveal_slots[idx]
	if not slot.cover.visible:
		return
	var r: int = int(slot.rarity)
	var r_col: Color = slot.color
	var card: Panel = slot.card
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.22, 0.04, 0.07, 0.97) if r == 7 else Color(r_col.r * 0.17, r_col.g * 0.16, r_col.b * 0.19, 0.96)
	st.border_color = r_col
	st.set_border_width_all(3 if r >= 5 else 2)
	st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	slot.cover.hide()
	slot.revealed_root.show()

	if with_audio:
		card.scale = Vector2(1.10, 1.10) if r >= 6 else (Vector2(1.06, 1.06) if r == 5 else Vector2(1.04, 1.04))
		if r == 7:
			game.play_sfx("loot_mythic_red", -7)
			stage_label.text = "🔥 奇迹出大红！！开出【旷世·大红】%s（%d币）！！" % [str(slot.item.title), int(slot.item.value)]
			stage_label.add_theme_color_override("font_color", Color("ff5c6c"))
			game.speak_english(str(slot.item.get("en", "")))
		elif r == 6:
			game.play_sfx("loot_epic", -8)
			stage_label.text = "✦ 金光耀眼！摸出【传说·大金】%s（%d币）！" % [str(slot.item.title), int(slot.item.value)]
			stage_label.add_theme_color_override("font_color", Color("ff9f38"))
		elif r == 5:
			game.play_sfx("loot_epic", -11)
			stage_label.text = "◆ 珍品闪耀！摸出【珍品·小金】%s（%d币）！" % [str(slot.item.title), int(slot.item.value)]
			stage_label.add_theme_color_override("font_color", Color("f6c34e"))
		elif r >= 3:
			game.play_sfx("loot_reveal_rare", -11)
		else:
			game.play_sfx("loot_reveal_common", -12)

func reveal_all_immediately():
	for i in reveal_slots.size():
		_reveal_single_slot(i, false)
	reveal_cursor = reveal_slots.size()

func _process(delta: float):
	if not busy or not unlocked:
		return
	# Smooth card punch-scale settle
	for s in reveal_slots:
		var c: Panel = s.card
		if is_instance_valid(c) and c.scale.x > 1.001:
			c.scale = c.scale.lerp(Vector2.ONE, minf(1.0, delta * 11.0))

	if reveal_cursor >= reveal_slots.size():
		return

	var cur_slot: Dictionary = reveal_slots[reveal_cursor]
	reveal_timer += delta
	reveal_tick_acc += delta
	if reveal_tick_acc >= 0.18:
		reveal_tick_acc = 0.0
		game.play_sfx("loot_scan_tick", -15)

	var ratio: float = clampf(reveal_timer / maxf(0.1, reveal_duration), 0.0, 1.0)
	cur_slot.bar_fill.size.x = float(cur_slot.bar_max) * ratio
	if ratio >= 1.0:
		_reveal_single_slot(reveal_cursor, true)
		reveal_cursor += 1
		reveal_timer = 0.0
		reveal_tick_acc = 0.0
		if reveal_cursor < reveal_slots.size():
			reveal_duration = _scan_duration_for(int(reveal_slots[reveal_cursor].rarity))
			_apply_card_mystery_style(reveal_slots[reveal_cursor], true)

func _handoff_to_loot_container(node: Node3D, kind: String, title: String, items: Array, subtitle: String, animate_scan: bool):
	busy = false
	overlay.hide()
	stage_label.add_theme_color_override("font_color", Color("ffd166"))
	close_button.text = "关闭返回 [Esc]"
	if is_instance_valid(game.loot_container_ui) and not items.is_empty():
		game.loot_container_ui.open_container(node, kind, title, items, subtitle, animate_scan)
	else:
		game.paused = false
		game.player.active = true
		game.hud.show()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func close():
	if not busy:
		return
	if mode == "retest":
		busy = false
		overlay.hide()
		game._refresh_progress()
		return
	reveal_all_immediately()
	# Surface HUD jackpot toast for the best high-rarity item pulled from this container!
	var best_pulled: Dictionary = {}
	for it in displayed_loot:
		if int(it.get("rarity", 1)) >= 4 and (best_pulled.is_empty() or int(it.get("rarity", 1)) > int(best_pulled.get("rarity", 1))):
			best_pulled = it
	busy = false
	overlay.hide()
	stage_label.add_theme_color_override("font_color", Color("ffd166"))
	close_button.text = "关闭返回 [Esc]"
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(game.exploration):
		game.exploration.grace = maxf(game.exploration.grace, 2.5)
	if not best_pulled.is_empty() and is_instance_valid(game.loot_ui):
		game.loot_ui.trigger_loot_toast(best_pulled, "开箱鉴定收获")
