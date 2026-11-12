extends Node3D
## Optional cross-subject discoveries (English spatial clue, Grade 5A Math & Classical Poetry).
## Reading freezes timer & combat, randomizes questions per run, and shuffles option buttons.

var game
var nodes = []
var states = {}
var data = {}
var current_items = {}
var current_options = {}
var current_answer_index = {}
var busy = false
var active_id = ""
var overlay: Control
var title: Label
var body: Label
var explanation: Label
var source: Label
var buttons = []
var swap_button: Button
var gate: Node3D
var grace = 0.0
var began = 0.0
var rng := RandomNumberGenerator.new()

func setup(g):
	game = g
	rng.randomize()
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	_mark("clue", game.Layout.CLUE, "巡护员的纸条", Color("d1c79b"))
	_mark("english", game.Layout.CLUE_LOOT, "路牌旁的封存补给", Color("7c8b5b"))
	_mark("poem", game.Layout.POEM, "山路古诗石碑", Color("777b68"))
	_mark("math", game.Layout.MATH, "巡护站 · 近道机关", Color("5d6a50"))
	var center = game.Layout.on_ground(Vector3(10, 0, -62))
	gate = Node3D.new()
	gate.position = center + Vector3(-1.4, 0, 0)
	add_child(gate)
	for x in [-1.5, 1.5]:
		game._mesh_box(self, center + Vector3(x, 0.95, 0), Vector3(0.20, 1.9, 0.20), Color("5b4933"), true)
	game._mesh_box(gate, Vector3(1.4, 1.15, 0), Vector3(2.8, 0.20, 0.16), Color("7b6344"), true)
	game._mesh_box(gate, Vector3(1.4, 0.58, 0), Vector3(2.8, 0.16, 0.16), Color("7b6344"), true)
	_ui()
	reset()

func _mark(id: String, at: Vector3, label: String, color: Color):
	var node = Node3D.new()
	node.position = game.Layout.on_ground(at)
	node.set_meta("explore_id", id)
	node.set_meta("prompt", label)
	add_child(node)
	if id == "poem":
		var stele_mat = StandardMaterial3D.new()
		stele_mat.albedo_color = Color("868b7e")
		stele_mat.albedo_texture = load("res://assets/slice/ground_color.jpg")
		stele_mat.normal_enabled = true
		stele_mat.normal_texture = load("res://assets/slice/ground_normal.jpg")
		stele_mat.uv1_scale = Vector3(1.5, 2.5, 1.5)
		stele_mat.roughness = 0.90
		var stele_node: Node3D
		if ResourceLoader.exists("res://assets/nature/statue_obelisk.glb"):
			stele_node = game._model(node, "res://assets/nature/statue_obelisk.glb", Vector3.ZERO, 2.2, 0, "convex")
		else:
			stele_node = game._model(node, "res://assets/slice/rock_3.glb", Vector3.ZERO, 1.5, 0, "convex")
		for m in stele_node.find_children("*", "MeshInstance3D", true, false):
			m.material_override = stele_mat
		var carving = game._label3d(node, "古诗石刻\n按 E 研读", Vector3(0, 1.25, 0.55), 29, Color("f3eed2"))
		carving.pixel_size = 0.0045
		carving.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	elif id == "english":
		game._model(node, "res://assets/slice/crate.glb", Vector3.ZERO, 0.52, 0, "convex")
	else:
		var timber_mat = StandardMaterial3D.new()
		timber_mat.albedo_color = Color("7b684e")
		timber_mat.albedo_texture = load("res://assets/slice/tree_bark.jpg")
		timber_mat.uv1_scale = Vector3(1, 2.5, 1)
		timber_mat.roughness = 0.86
		var post = game._mesh_box(node, Vector3(0, 0.62, 0), Vector3(0.13, 1.28, 0.13), Color.WHITE, true)
		post.material_override = timber_mat
		var board_back = game._mesh_box(node, Vector3(0, 1.05, 0.06), Vector3(1.05, 0.66, 0.08), color, true)
		board_back.material_override = timber_mat
		game._mesh_box(node, Vector3(0, 1.05, 0.11), Vector3(0.88, 0.50, 0.015), Color("dfd9b8"))
		var text = game._label3d(node, "巡护记录\nnext to" if id == "clue" else "近道机关\nE 解锁木门", Vector3(0, 1.05, 0.13), 26, Color("223428"))
		text.pixel_size = 0.0038
		text.outline_size = 0
		text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var prompt = game._label3d(node, label + " · [E]", Vector3(0, 2.15, 0), 28, game.GOLD)
	prompt.visibility_range_end = 15
	nodes.append(node)

func _ui():
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(overlay)
	var veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.03, 0.055, 0.035, 0.91)
	overlay.add_child(veil)
	game._panel(overlay, Rect2(240, 86, 800, 550), Color("162822"), Color(0.48, 0.78, 0.62, 0.45))
	title = game._text(overlay, "", Vector2(275, 110), Vector2(690, 42), 29, game.MINT)
	body = game._text(overlay, "", Vector2(275, 172), Vector2(730, 145), 24)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in 3:
		buttons.append(game._button(overlay, "", Rect2(275 + i * 244, 337, 230, 54), choose.bind(i)))
	explanation = game._text(overlay, "", Vector2(275, 414), Vector2(730, 100), 19, game.GOLD)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source = game._text(overlay, "", Vector2(275, 521), Vector2(710, 51), 13, Color("a7b8a2"))
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._button(overlay, "返回山路  [Esc]", Rect2(790, 578, 215, 37), close)
	swap_button = game._button(overlay, "替换最低值物资", Rect2(550, 578, 220, 37), replace_reward)
	swap_button.hide()
	game._text(overlay, "阅读与思考期间暂停计时和敌方攻击", Vector2(275, 582), Vector2(300, 30), 14, game.MINT)
	overlay.hide()

func _prepare_puzzle(id: String, pool_key: String):
	var pool: Array = data.get(pool_key, [])
	var picked: Dictionary = data[id] if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]
	current_items[id] = picked
	var indexed = []
	for i in picked.options.size():
		indexed.append({"text": picked.options[i], "is_answer": i == int(picked.answer)})
	indexed.shuffle()
	var opts = []
	var ans = 0
	for i in indexed.size():
		opts.append(indexed[i].text)
		if indexed[i].is_answer:
			ans = i
	current_options[id] = opts
	current_answer_index[id] = ans

func answer_button_index(id: String) -> int:
	return int(current_answer_index.get(id, 0))

func reset():
	states = {"clue": false, "english": false, "math": false, "poem": false, "math_claimed": false, "poem_claimed": false}
	busy = false
	active_id = ""
	grace = 0.0
	began = 0.0
	_prepare_puzzle("math", "math_pool")
	_prepare_puzzle("poem", "poem_pool")
	if is_instance_valid(overlay):
		overlay.hide()
	game.Props.set_enabled(gate, true)
	gate.rotation = Vector3.ZERO
	for n in nodes:
		game.Props.set_enabled(n, true)

func safe() -> bool:
	var cipher_busy = is_instance_valid(game.cipher_terminal) and game.cipher_terminal.busy
	return busy or cipher_busy or grace > 0 or game.player.position.distance_to(game.exit_position) < 4.7

func update(delta: float):
	grace = maxf(0, grace - delta)
	if game.rules.phase in ["active", "extracting"]:
		began += delta

func open(node: Node3D):
	var id: String = node.get_meta("explore_id")
	if id == "english":
		if not states.clue:
			game._notice("补给箱贴着封条！先看附近巡护员纸条上的方位提示。")
			game.play_sfx("hit_wrong", -14)
		elif states.english:
			game._notice("这份方位线索补给已收集。")
		elif game.rules.add_loot("加密无线电台", 82, 3):
			states.english = true
			game.Props.set_enabled(node, false)
			game.play_sfx("cipher_unlock", -11)
			game.speak_english("next to")
			game._notice("读懂 next to（在……旁边）！获得【稀有】加密无线电台（82币）", game.MINT)
		else:
			game._notice("背包已满，补给会留在这里。")
		return
	active_id = id
	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.show()
	explanation.text = ""
	source.text = ""
	swap_button.hide()
	if id == "clue":
		states.clue = true
		title.text = "巡护员留下的方位纸条"
		body.text = "山道补给箱藏在路牌旁边。\n英文方位线索：The supply box is  next to  the signpost.\n读懂方位词，去山路右侧路牌旁找一找！"
		source.text = "词汇来源：江苏五上英语词表 · next to（在……旁边）。已同步播放读音。"
		for i in 3:
			buttons[i].hide()
		explanation.text = "提示：next to = 在……旁边。找到封存箱按 [E] 即可领取稀有物资！"
		game.speak_english("next to")
	else:
		var item = current_items[id]
		var opts = current_options[id]
		title.text = item.title
		body.text = item.question
		source.text = item.source
		for i in 3:
			buttons[i].show()
			buttons[i].text = opts[i]
			buttons[i].disabled = false
		buttons[0].grab_focus()
		if states[id]:
			_reward(id)

func choose(index: int):
	if not busy or active_id not in current_items:
		return
	var item = current_items[active_id]
	var expected_idx = answer_button_index(active_id)
	if index != expected_idx:
		game.play_sfx("hit_wrong", -13)
		explanation.text = "再想一想！" + ("注意看清题目里的图形公式或起点与终点距离。" if active_id == "math" else "回想一下课本古诗的意境与上下句对仗。")
		return
	states[active_id] = true
	game.play_sfx("cipher_unlock", -11)
	if active_id == "math":
		gate.rotation.y = -PI / 2
	_reward(active_id)

func _reward(id: String):
	var key = id + "_claimed"
	var item = current_items[id]
	var rarity = int(item.get("reward_rarity", 3))
	swap_button.hide()
	var suffix = "这处探索奖励已领取。"
	if not states[key]:
		if game.rules.add_loot(item.reward_title, int(item.reward_value), rarity):
			states[key] = true
			suffix = "已获得【%s】%s（估值 %d 币）！" % [game.Rules.RARITY_NAMES[rarity], item.reward_title, int(item.reward_value)]
		else:
			suffix = "背包已满！可点下方「替换最低值物资」换入高价值奖励，或直接返回。"
			swap_button.show()
	explanation.text = item.explanation + "\n" + suffix
	for b in buttons:
		b.disabled = true

func replace_reward():
	if not busy or active_id not in current_items or not states[active_id] or states[active_id + "_claimed"]:
		return
	if game.rules.bag.is_empty():
		return
	var lowest = 0
	for i in range(1, game.rules.bag.size()):
		if int(game.rules.bag[i].value) < int(game.rules.bag[lowest].value):
			lowest = i
	var previous = game.rules.bag[lowest]
	game.rules.bag.remove_at(lowest)
	var item = current_items[active_id]
	var rarity = int(item.get("reward_rarity", 3))
	if game.rules.add_loot(item.reward_title, int(item.reward_value), rarity):
		states[active_id + "_claimed"] = true
		game.play_sfx("cipher_unlock", -12)
	else:
		game.rules.bag.insert(lowest, previous)
	_reward(active_id)

func close():
	if not busy:
		return
	busy = false
	overlay.hide()
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	grace = 3.5

func completed() -> int:
	return int(states.get("english", false)) + int(states.get("math", false)) + int(states.get("poem", false))

func status_text() -> String:
	return "探索 %d/3" % completed()
