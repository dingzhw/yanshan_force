extends Node3D
## Optional cross-subject & v0.5.4 field intel / radio / airdrop discoveries.
## Reading freezes timer & combat, randomizes questions per run, and shuffles option buttons.

const TacticalProps = preload("res://scripts/tactical_props.gd")
const INTEL_IDS = ["intel_container", "intel_cleft", "intel_cave", "intel_roof"]
const SECRET_EVENT_IDS = ["intel_container", "intel_cleft", "intel_cave", "intel_roof", "recon_radio", "airdrop_beacon"]

var game
var nodes = []
var states = {}
var data = {}
var current_items = {}
var current_options = {}
var current_answer_index = {}
var revealed_secrets = {}
var radar_scan_active = false
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
	_mark("intel_container", game.Layout.PARKOUR_CONTAINERS + Vector3(5.6, 0, 2.5), "战地线报 #1 · 西岭货柜", Color("6ce3b8"))
	_mark("intel_cleft", Vector3(-19.5, 0, -50.2), "战地线报 #2 · 双岩秘藏", Color("6ce3b8"))
	_mark("intel_cave", game.Layout.MATH + Vector3(-2.6, 0, -1.8), "战地线报 #3 · 石窟密电", Color("ffd15c"))
	_mark("intel_roof", game.Layout.SHELTER_BAMBOO + Vector3(1.6, 0, 3.8), "战地线报 #4 · 棚顶与高塔", Color("cf8aff"))
	_mark("recon_radio", game.Layout.RECON_RADIO, "东岭侦察电台 · 抢修扫图", Color("56e8ff"))
	_mark("airdrop_beacon", game.Layout.AIRDROP_BEACON, "北脊空投信标 · 呼叫补给", Color("ffd15c"))
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
		var loaded_pavilion := false
		var jn_path := "res://assets/slice/v060_jiangnan_assets.glb"
		if ResourceLoader.exists(jn_path):
			if not game.scene_cache.has(jn_path):
				game.scene_cache[jn_path] = load(jn_path)
			var inst: Node3D = game.scene_cache[jn_path].instantiate()
			var sub := inst.find_child("poem_stele_pavilion", true, false)
			if is_instance_valid(sub):
				if sub.get_parent():
					sub.get_parent().remove_child(sub)
				sub.owner = null
				sub.position = Vector3.ZERO
				node.add_child(sub)
				inst.queue_free()
				loaded_pavilion = true
			else:
				inst.queue_free()
		if not loaded_pavilion:
			var fallback_mat = StandardMaterial3D.new()
			fallback_mat.albedo_color = Color("868b7e")
			fallback_mat.roughness = 0.90
			var stele_fb = game._model(node, "res://assets/slice/rock_3.glb", Vector3.ZERO, 1.5, 0, "convex")
			for m in stele_fb.find_children("*", "MeshInstance3D", true, false):
				m.material_override = fallback_mat
		# Solid colliders for pavilion stone base (step-clear of z=+2.0 interact spot), stele tablet & 4 pillars
		var base_shp := BoxShape3D.new()
		base_shp.size = Vector3(3.00, 0.28, 2.70)
		game.Props.shape_body(node, base_shp, Vector3(0, 0.14, 0))
		var tablet_shp := BoxShape3D.new()
		tablet_shp.size = Vector3(1.18, 2.25, 0.72)
		game.Props.shape_body(node, tablet_shp, Vector3(0, 1.12, 0))
		for sx in [-1.08, 1.08]:
			for sz in [-0.96, 0.96]:
				var col_shp := CylinderShape3D.new()
				col_shp.radius = 0.11
				col_shp.height = 2.30
				game.Props.shape_body(node, col_shp, Vector3(sx, 1.15, sz))
	elif id == "english":
		game._model(node, "res://assets/slice/crate.glb", Vector3.ZERO, 0.52, 0, "convex")
	elif id in INTEL_IDS:
		var board = TacticalProps.attach_parkour_asset(node, game, "prop_intel_board", Vector3.ZERO, 0.25, Vector3.ONE * 1.1)
		if board == null:
			game._mesh_box(node, Vector3(0, 0.72, 0), Vector3(0.9, 1.3, 0.14), color, true)
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(0.95, 1.35, 0.30)
		game.Props.shape_body(node, col_shape, Vector3(0, 0.68, 0))
	elif id == "recon_radio":
		var radio = TacticalProps.attach_parkour_asset(node, game, "prop_recon_radio", Vector3.ZERO, -0.35, Vector3.ONE * 1.15)
		if radio == null:
			game._mesh_box(node, Vector3(0, 0.65, 0), Vector3(0.9, 1.2, 0.7), Color("3c545b"), true)
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(0.95, 1.30, 0.75)
		game.Props.shape_body(node, col_shape, Vector3(0, 0.65, 0))
		var pulse := OmniLight3D.new()
		pulse.position = Vector3(0, 1.45, 0)
		pulse.light_color = Color("56e8ff")
		pulse.light_energy = 1.0
		pulse.omni_range = 4.6
		node.add_child(pulse)
	elif id == "airdrop_beacon":
		var beacon = TacticalProps.attach_parkour_asset(node, game, "prop_airdrop_beacon", Vector3.ZERO, 0.2, Vector3.ONE * 1.15)
		if beacon == null:
			game._mesh_box(node, Vector3(0, 0.85, 0), Vector3(1.1, 1.6, 1.1), Color("ffd15c"), true)
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(1.15, 1.55, 1.15)
		game.Props.shape_body(node, col_shape, Vector3(0, 0.78, 0))
		var glow := OmniLight3D.new()
		glow.position = Vector3(0, 1.75, 0)
		glow.light_color = Color("ffd15c")
		glow.light_energy = 1.25
		glow.omni_range = 5.4
		node.add_child(glow)
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
	if id == "poem":
		prompt.position = Vector3(0, 2.66, 1.56)
		prompt.pixel_size = 0.0040
		prompt.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		prompt.text = "烟山诗碑亭 · 按 [E] 研读"
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
	game._panel(overlay, Rect2(240, 68, 800, 586), Color("162822"), Color(0.48, 0.78, 0.62, 0.45))
	title = game._text(overlay, "", Vector2(275, 88), Vector2(730, 42), 28, game.MINT)
	body = game._text(overlay, "", Vector2(275, 142), Vector2(730, 128), 22)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in 3:
		buttons.append(game._button(overlay, "", Rect2(275, 286 + i * 48, 730, 42), choose.bind(i)))
	explanation = game._text(overlay, "", Vector2(275, 434), Vector2(730, 96), 18, game.GOLD)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source = game._text(overlay, "", Vector2(275, 536), Vector2(730, 44), 13, Color("a7b8a2"))
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._button(overlay, "返回山路  [Esc]", Rect2(790, 594, 215, 37), close)
	swap_button = game._button(overlay, "替换最低值物资", Rect2(550, 594, 220, 37), replace_reward)
	swap_button.hide()
	game._text(overlay, "阅读与思考期间暂停计时和敌方攻击", Vector2(275, 598), Vector2(300, 30), 14, game.MINT)
	overlay.hide()

func _prepare_puzzle(id: String, pool_key: String):
	var pool: Array = data.get(pool_key, [])
	var picked: Dictionary = data[id] if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]
	_prepare_item(id, picked)

func _prepare_item(id: String, picked: Dictionary):
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
	for sid in SECRET_EVENT_IDS:
		states[sid] = false
		states[sid + "_claimed"] = false
	revealed_secrets = {}
	radar_scan_active = false
	busy = false
	active_id = ""
	grace = 0.0
	began = 0.0
	_prepare_puzzle("math", "math_pool")
	_prepare_puzzle("poem", "poem_pool")
	_prepare_puzzle("recon_radio", "recon_pool")
	_prepare_puzzle("airdrop_beacon", "beacon_pool")
	var ipools: Dictionary = data.get("intel_pools", {})
	for iid in INTEL_IDS:
		if ipools.has(iid):
			_prepare_item(iid, ipools[iid])
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
		if item.has("tts"):
			game.speak_english(str(item.tts))
		if states.get(id, false):
			_reward(id)

func choose(index: int):
	if not busy or active_id not in current_items:
		return
	var item = current_items[active_id]
	var expected_idx = answer_button_index(active_id)
	if index != expected_idx:
		game.play_sfx("hit_wrong", -13)
		if item.has("tts"):
			game.speak_english(str(item.tts))
		if active_id == "math":
			explanation.text = "再想一想！注意看清题目里的图形公式或起点与终点距离。"
		elif active_id == "poem":
			explanation.text = "再想一想！回想一下课本古诗的意境与上下句对仗。"
		else:
			explanation.text = "再读再听一遍英文句！注意空间介词（on top of / between / inside / beside / under / in front of）。"
		return
	var first_solve := not bool(states.get(active_id, false))
	states[active_id] = true
	if active_id == "math":
		gate.rotation.y = -PI / 2
		game.play_sfx("cipher_unlock", -11)
	elif first_solve and active_id in INTEL_IDS:
		game.rules.score += int(item.get("reward_score", 20))
		var rk := str(item.get("reveal_key", ""))
		if rk != "":
			revealed_secrets[rk] = true
		game.play_sfx("cipher_unlock", -11)
		game._notice("破译战地英文线报！雷达已标记秘宝定位（+%d 分）" % int(item.get("reward_score", 20)), game.MINT)
	elif first_solve and active_id == "recon_radio":
		radar_scan_active = true
		game.rules.score += 45
		game.player.grenades += 1
		if not game.player.has_infinite_ammo():
			game.player.add_reserve_ammo(game.rules.magazine())
		game.play_sfx("radio_scan", -10)
		game._notice("东岭雷达全图扫描已激活！+45分 +1烟雾EMP +1备弹匣", Color("7ceeff"))
	elif first_solve and active_id == "airdrop_beacon":
		game.rules.score += 40
		if not game.player.has_infinite_ammo():
			game.player.add_reserve_ammo(game.rules.magazine() * 2)
		game.play_sfx("airdrop_call", -10)
		game._notice("北脊卫星空投已解锁！+40分 +2备弹匣", game.GOLD)
	else:
		game.play_sfx("cipher_unlock", -11)
	_reward(active_id)

func _reward(id: String):
	var item = current_items[id]
	if not item.has("reward_title"):
		swap_button.hide()
		var pts := int(item.get("reward_score", 20))
		explanation.text = "%s\n已解锁雷达定位并获得 +%d 撤离积分！" % [item.explanation, pts]
		for b in buttons:
			b.disabled = true
		return
	var key = id + "_claimed"
	var rarity = int(item.get("reward_rarity", 3))
	swap_button.hide()
	var suffix = "这处探索奖励已领取。"
	if not states.get(key, false):
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

func secrets_completed() -> int:
	var n := 0
	for sid in SECRET_EVENT_IDS:
		if bool(states.get(sid, false)):
			n += 1
	return n

func is_secret_revealed(secret_key: String) -> bool:
	if secret_key == "":
		return true
	return radar_scan_active or bool(revealed_secrets.get(secret_key, false))

func status_text() -> String:
	return "探 %d/3 · 秘 %d/6" % [completed(), secrets_completed()]
