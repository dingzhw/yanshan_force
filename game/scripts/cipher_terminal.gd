extends Node
## Tiered English Cipher Terminal:
## - Regular Supply Boxes: 1-stage single core English word spelling
## - Tier 1 Outpost Crate: 2-stage combo (Core Word -> Textbook Phrase)
## - Tier 2 Epic Vault:    2-stage combo (Textbook Phrase -> Grade 5A Short Sentence)
## - Tier 3 Gold Airdrop:  3-stage protocol (Advanced Word -> Textbook Phrase -> Full Grade 5A Sentence)

const SENTENCE_BANK = [
	{"id": "s_u1_1", "unit": 1, "textbook_page": 17, "kind": "sentence", "english": "It's your turn.", "chinese": "轮到你了。"},
	{"id": "s_u1_2", "unit": 1, "textbook_page": 8, "kind": "sentence", "english": "Listen carefully in class.", "chinese": "在课堂上仔细听讲。"},
	{"id": "s_u1_3", "unit": 1, "textbook_page": 11, "kind": "sentence", "english": "Wait a minute.", "chinese": "等一会儿。"},
	{"id": "s_u2_1", "unit": 2, "textbook_page": 23, "kind": "sentence", "english": "Well done!", "chinese": "干得好！"},
	{"id": "s_u2_2", "unit": 2, "textbook_page": 26, "kind": "sentence", "english": "Never give up.", "chinese": "永不放弃。"},
	{"id": "s_u2_3", "unit": 2, "textbook_page": 28, "kind": "sentence", "english": "We study hard.", "chinese": "我们努力学习。"},
	{"id": "s_u3_1", "unit": 3, "textbook_page": 35, "kind": "sentence", "english": "I don't think so.", "chinese": "我不这么认为。"},
	{"id": "s_u3_2", "unit": 3, "textbook_page": 38, "kind": "sentence", "english": "Look at the gift over there.", "chinese": "看那里的礼物。"},
	{"id": "s_u4_1", "unit": 4, "textbook_page": 49, "kind": "sentence", "english": "Keep to the right.", "chinese": "靠右边走。"},
	{"id": "s_u4_2", "unit": 4, "textbook_page": 50, "kind": "sentence", "english": "Please walk slowly.", "chinese": "请慢点走。"},
	{"id": "s_u4_3", "unit": 4, "textbook_page": 44, "kind": "sentence", "english": "We should warm up.", "chinese": "我们应该先热身。"},
	{"id": "s_u5_1", "unit": 5, "textbook_page": 59, "kind": "sentence", "english": "I often play the piano.", "chinese": "我经常弹钢琴。"},
	{"id": "s_u5_2", "unit": 5, "textbook_page": 61, "kind": "sentence", "english": "Let's have a picnic.", "chinese": "我们去野餐吧。"},
	{"id": "s_u6_1", "unit": 6, "textbook_page": 79, "kind": "sentence", "english": "Please do your homework.", "chinese": "请做你的家庭作业。"},
	{"id": "s_u7_1", "unit": 7, "textbook_page": 85, "kind": "sentence", "english": "How about this sweater?", "chinese": "这件毛衣怎么样？"},
	{"id": "s_u8_1", "unit": 8, "textbook_page": 99, "kind": "sentence", "english": "We have a good time.", "chinese": "我们过得很愉快。"}
]

var game
var busy = false
var mode = "crate" # "supply" or "crate"
var active_crate: Node3D
var stages: Array = []
var stage_index = 0
var target_word: Dictionary = {}
var attempts = 0
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
	swap_button = game._button(overlay, "替换背包最低值物资", Rect2(636, 372, 340, 46), _swap_lowest)
	swap_button.hide()

	status_label = game._text(overlay, "", Vector2(242, 428), Vector2(796, 52), 17, game.GOLD)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	loot_container = HBoxContainer.new()
	loot_container.position = Vector2(242, 488)
	loot_container.size = Vector2(796, 86)
	loot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	loot_container.add_theme_constant_override("separation", 16)
	overlay.add_child(loot_container)

	game._text(overlay, "破译期间暂停敌袭与计时 · 常规箱考单词，高级/空投大金箱考词组与整句（忽略句末标点）", Vector2(242, 598), Vector2(610, 30), 13, Color("8fb2a4"))
	close_button = game._button(overlay, "关闭返回 [Esc]", Rect2(868, 590, 174, 38), close)
	overlay.hide()

func _input(event):
	if not busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_TAB:
			_speak_hint()
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
	var candidates := []
	for pass_idx in 2:
		for s in SENTENCE_BANK:
			var word_cnt := str(s.english).split(" ", false).size()
			if prefer_short and word_cnt > 4 and pass_idx == 0:
				continue
			if not prefer_short and word_cnt < 4 and pass_idx == 0:
				continue
			if pass_idx == 0 and sel_u > 0 and int(s.unit) != sel_u:
				continue
			candidates.append(s)
		if not candidates.is_empty():
			break
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
	overlay.show()

func _refresh_stage_ui():
	target_word = stages[stage_index]
	attempts = 0
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
	mask_label.text = _build_mask(target_word, false)

	var unit_str := "Unit %d · 课本第 %d 页" % [int(target_word.get("unit", 1)), int(target_word.get("textbook_page", 1))]
	if mode == "supply":
		meta_label.text = "常规野外物资箱  |  %s  |  准确输入 1 个英文单词即可开箱领取物资" % unit_str
	else:
		var tier := int(active_crate.get_meta("tier"))
		var tier_desc: String = [
			"前哨补给箱（单词+词组 2连破 · 稀有/史诗）",
			"精密金库箱（词组+短句 2连破 · 高爆史诗/大金）",
			"特级大金空投箱（词汇+词组+整句 3重破译 · 高爆传说大金！）"
		][clampi(tier - 1, 0, 2)]
		meta_label.text = "%s  |  %s" % [tier_desc, unit_str]

	input_box.editable = true
	input_box.text = ""
	submit_button.disabled = false
	submit_button.text = ("验证下一关 [Enter]" if stage_index + 1 < total else "破译开箱 [Enter]")
	close_button.text = "关闭返回 [Esc]"
	input_box.grab_focus()

func open_for_supply(pickup_node: Node3D):
	if not is_instance_valid(pickup_node) or not pickup_node.visible:
		return
	mode = "supply"
	active_crate = pickup_node
	_clear_loot_cards()
	swap_button.hide()

	# If previously unlocked while bag was full, reopen directly to claim/swap
	if pickup_node.has_meta("unclaimed_loot"):
		var saved: Array = pickup_node.get_meta("unclaimed_loot")
		if not saved.is_empty():
			stages = [_pick_word_entry(false)]
			stage_index = 0
			target_word = stages[0]
			unlocked = true
			displayed_loot = saved.duplicate(true)
			pending_loot = saved.duplicate(true)
			_enter_modal()
			title_label.text = "%s · 待领取物资" % str(pickup_node.get_meta("title", "常规物资箱"))
			stage_label.text = "✓ 单词锁已破译 · 请整理背包领取"
			prompt_label.text = "箱内物资尚未放入背包"
			mask_label.text = ""
			input_box.editable = false
			submit_button.disabled = true
			_render_loot_cards(displayed_loot)
			_try_claim_pending()
			return

	stages = [_pick_word_entry(false)]
	stage_index = 0
	all_stages_perfect = true
	unlocked = false
	perfect_crack = false
	displayed_loot.clear()
	pending_loot.clear()

	_enter_modal()
	title_label.text = "%s · 单词拼写解锁" % str(pickup_node.get_meta("title", "常规物资箱"))
	_refresh_stage_ui()
	status_label.text = "常规物资箱需输入对应的英文单词解锁（按 Tab 可听标准读音）。"
	status_label.add_theme_color_override("font_color", game.GOLD)

func open_for_crate(crate_node: Node3D):
	var crate_title: String = crate_node.get_meta("title")
	var tier: int = int(crate_node.get_meta("tier"))

	if crate_node.has_meta("unclaimed_loot"):
		var saved: Array = crate_node.get_meta("unclaimed_loot")
		if not saved.is_empty():
			mode = "crate"
			active_crate = crate_node
			stages = [_pick_word_entry(false)]
			stage_index = 0
			target_word = stages[0]
			unlocked = true
			displayed_loot = saved.duplicate(true)
			pending_loot = saved.duplicate(true)
			_enter_modal()
			title_label.text = "%s · 剩余高价值战利品" % crate_title
			stage_label.text = "✓ 密码箱已解锁 · 可替换背包低价值物资"
			prompt_label.text = "背包空间不足，剩余物资暂存箱内"
			mask_label.text = ""
			input_box.editable = false
			submit_button.disabled = true
			_render_loot_cards(displayed_loot)
			_try_claim_pending()
			return

	if crate_title in game.rules.crates:
		game._notice(crate_title + " 已破译搜刮完毕。")
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
	status_label.text = "完成全部 %d 关英语验证即可开启宝箱（高阶箱含词组与课本句子，按 Tab 听发音）！" % stages.size()
	status_label.add_theme_color_override("font_color", game.GOLD)

func _speak_hint():
	if not target_word.is_empty():
		game.speak_english(str(target_word.english))

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

func _try_claim_pending():
	var still_unclaimed := []
	for item in pending_loot:
		if not game.rules.add_loot(item.title, int(item.value), int(item.get("rarity", 1))):
			still_unclaimed.append(item)
	pending_loot = still_unclaimed

	if mode == "supply":
		if pending_loot.is_empty():
			if is_instance_valid(active_crate):
				if active_crate.has_meta("unclaimed_loot"):
					active_crate.remove_meta("unclaimed_loot")
				game.Props.set_enabled(active_crate, false)
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
	if not busy or unlocked or not is_instance_valid(active_crate):
		return
	var raw_typed := input_box.text.strip_edges()
	if raw_typed == "":
		status_label.text = "输入不能为空，请输入对应的英文内容！"
		return
	attempts += 1
	if _is_match(raw_typed, target_word):
		if attempts > 2:
			all_stages_perfect = false
		else:
			game.rules.record_word_spelled(str(target_word.get("id", "")))
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

		# Final stage cleared -> Unlock container!
		unlocked = true
		perfect_crack = all_stages_perfect
		input_box.editable = false
		submit_button.disabled = true
		stage_label.text = "★ 全部 %d 关验证通过 · 电子锁已解除！" % stages.size()

		if mode == "supply":
			var sid := str(active_crate.get_meta("supply_id", active_crate.name))
			if not (sid in game.rules.supplies_opened):
				game.rules.supplies_opened.append(sid)
				if perfect_crack:
					game.rules.score += game.Rules.SUPPLY_PERFECT_SCORE
			var item: Dictionary = game.rules.roll_field_pickup(perfect_crack)
			displayed_loot = [item]
			pending_loot = [item]
			_render_loot_cards(displayed_loot)
			_try_claim_pending()
			game.play_sfx("cipher_unlock", -11)
			if pending_loot.is_empty():
				status_label.text = ("★ 单词准确！ +%d 分 · 已收入【%s】%s（%d币）" % [game.Rules.SUPPLY_PERFECT_SCORE, game.Rules.RARITY_NAMES[item.rarity], item.title, item.value]) if perfect_crack else ("物资箱已开启！记住拼写：%s — 已获得 %s" % [target_word.english, item.title])
				status_label.add_theme_color_override("font_color", game.MINT if perfect_crack else game.GOLD)
			else:
				status_label.text = "背包已满！可点上方「替换最低物资」换入 %s（%d币），或按 Esc 返回。" % [item.title, item.value]
				status_label.add_theme_color_override("font_color", Color("ffd166"))
		else:
			var crate_title: String = active_crate.get_meta("title")
			var tier: int = int(active_crate.get_meta("tier"))
			var bonus_pts: int = game.Rules.CIPHER_PERFECT_SCORE + maxi(0, tier - 1) * 10
			var res: Dictionary = game.rules.unlock_crate_full(crate_title, tier, perfect_crack)
			displayed_loot = res.items
			# Sort pending overflow highest-value first so swapping grabs the best loot (e.g. 大金) first!
			pending_loot = res.overflow
			pending_loot.sort_custom(func(a, b): return int(a.value) > int(b.value))

			active_crate.get_child(active_crate.get_child_count() - 1).modulate = game.MINT
			if active_crate.has_meta("lid_node") and is_instance_valid(active_crate.get_meta("lid_node")):
				active_crate.get_meta("lid_node").rotation.x = -0.55

			var has_epic := false
			for it in displayed_loot:
				if int(it.get("rarity", 1)) >= 4:
					has_epic = true
			game.play_sfx("loot_epic" if has_epic else "cipher_unlock", -10)
			_render_loot_cards(displayed_loot)
			_try_claim_pending()

			if not pending_loot.is_empty():
				status_label.text = "★ 密码箱已破译！随身背包已满（剩余 %d 件未装入），可点「替换最低物资」换入高价值大金！" % pending_loot.size()
				status_label.add_theme_color_override("font_color", Color("ffd166"))
			elif perfect_crack:
				status_label.text = "★ 完美破译全通！ +%d 分 — 高爆率战利品已全部收入背包！" % bonus_pts
				status_label.add_theme_color_override("font_color", game.MINT)
			else:
				status_label.text = "密码箱已开启！战利品已收入随身背包。"
				status_label.add_theme_color_override("font_color", game.GOLD)
		close_button.text = "收下返回 [Esc]"
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
			if target_word.has("id") and str(target_word.id).begins_with("js5a") and target_word not in game.wrong_words:
				game.wrong_words.append(target_word)
			if target_word.has("id") and str(target_word.id).begins_with("js5a"):
				game.rules.record_word_result(str(target_word.id), false)
			input_box.select_all()
			input_box.grab_focus()

func _swap_lowest():
	if not busy or not unlocked or pending_loot.is_empty() or game.rules.bag.is_empty():
		return
	var next_item: Dictionary = pending_loot.pop_front()
	var removed: Dictionary = game.rules.swap_lowest_loot(next_item)
	if not removed.is_empty():
		game.play_sfx("cipher_unlock", -11)
		status_label.text = "已将【%s（%d币）】替换为【%s】%s（%d币）！" % [
			removed.title, int(removed.value),
			game.Rules.RARITY_NAMES[int(next_item.get("rarity", 1))], next_item.title, int(next_item.value)
		]
		status_label.add_theme_color_override("font_color", game.MINT)
	_try_claim_pending()

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
		card.custom_minimum_size = Vector2(236, 78)
		var st = StyleBoxFlat.new()
		st.bg_color = Color(r_color.r * 0.16, r_color.g * 0.16, r_color.b * 0.18, 0.95)
		st.border_color = r_color
		st.set_border_width_all(2)
		st.set_corner_radius_all(7)
		card.add_theme_stylebox_override("panel", st)
		loot_container.add_child(card)
		var tag = game._text(card, "【%s】" % r_name, Vector2(10, 8), Vector2(216, 22), 14, r_color)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var name_lbl = game._text(card, item.title, Vector2(8, 30), Vector2(220, 24), 17, game.CREAM)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var val_lbl = game._text(card, "估值 %d 币" % int(item.value), Vector2(8, 53), Vector2(220, 20), 13, game.GOLD)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
