extends Node3D
## Yanshan Force v0.9.1 — "曼德尔砖破译攻坚站" (MandelBrick Capture & 3-Round Cipher Decryption Event)
## Exclusive dynamic field event on Ahsarah Fortress (Normal & Confidential Operations):
##   1) Capture glowing MandelBrick from Administrative Fortress Courtyard Vault Pedestal
##   2) Escort brick to active G.T.I. Decryption Station (alternating Brakkesh Bazaar / Cement Plant Yard)
##   3) Insert brick -> triggers 2 Word-Shield Interceptor Ambush Waves + 3-Round Grade-5A English Spelling Cipher
##   4) Complete decryption -> +90/+120 bonus score, physical MandelBrick Reward Crate (3 calibrated pyramid rolls),
##      achievement "曼德尔破译者" & 3D weapon charm "迷你曼德尔砖"!

const AhsarahLayout = preload("res://scripts/ahsarah_layout.gd")
const TacticalProps = preload("res://scripts/tactical_props.gd")
const FORTRESS_GLB := "res://assets/slice/v091_ahsarah_fortress.glb"
const AHSARAH_LOOT_GLB := "res://assets/slice/v090_ahsarah_collectibles.glb"

var game
var state: String = "inactive"  # "inactive" | "available" | "carrying" | "decoding" | "completed"
var busy: bool = false
var run_counter: int = 0
var active_site_index: int = 0
var active_site: Dictionary = {}
var decode_round: int = 0       # 1..3 during decoding
var cipher_words: Array = []    # 3 distinct Grade 5A words for the 3 decryption rounds
var wrong_attempts_round: int = 0
var wave_1_spawned: bool = false
var wave_2_spawned: bool = false
var pulse_clock: float = 0.0

var event_root: Node3D = null
var pickup_node: Node3D = null
var pickup_brick_vis: Node3D = null
var pickup_beam: MeshInstance3D = null
var pickup_label: Label3D = null
var decode_node: Node3D = null
var decode_brick_vis: Node3D = null
var decode_beam: MeshInstance3D = null
var decode_light: OmniLight3D = null
var decode_label: Label3D = null
var reward_crate_node: Node3D = null

var scene_templates: Dictionary = {}
var mesh_cache: Dictionary = {}
var rng := RandomNumberGenerator.new()

# Cipher Modal UI
var overlay: Control
var modal_title: Label
var modal_round_lbl: Label
var progress_fill: ColorRect
var chinese_lbl: Label
var cloze_lbl: Label
var hint_lbl: Label
var status_lbl: Label
var answer_input: LineEdit
var speak_btn: Button
var submit_btn: Button
var close_btn: Button

func setup(g):
	game = g
	rng.randomize()
	_build_ui()

func _exit_tree():
	for k in scene_templates:
		var n = scene_templates[k]
		if is_instance_valid(n):
			n.free()
	scene_templates.clear()
	mesh_cache.clear()

func _extract_mesh(path: String, node_name: String) -> Mesh:
	var key := path + "::" + node_name
	if mesh_cache.has(key):
		return mesh_cache[key]
	if not scene_templates.has(path):
		var packed = load(path)
		if packed == null:
			return null
		scene_templates[path] = packed.instantiate()
	var tpl: Node = scene_templates[path]
	var found := tpl.find_child(node_name, true, false)
	var out_mesh: Mesh = null
	if found is MeshInstance3D:
		out_mesh = found.mesh
	elif found != null:
		for ch in found.find_children("*", "MeshInstance3D", true, false):
			out_mesh = (ch as MeshInstance3D).mesh
			break
	mesh_cache[key] = out_mesh
	return out_mesh

func _make_brick_visual() -> Node3D:
	var holder := Node3D.new()
	var bm: Mesh = _extract_mesh(AHSARAH_LOOT_GLB, "mandel_brick")
	if bm != null:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.scale = Vector3.ONE * 1.45
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	else:
		var mi2 := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.46, 0.46, 0.46)
		mi2.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("3ce8ff")
		mat.emission_enabled = true
		mat.emission = Color("22d6ff")
		mat.emission_energy_multiplier = 2.0
		mi2.material_override = mat
		holder.add_child(mi2)
	return holder

func _make_beacon_beam(col: Color, h: float = 26.0) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.42
	cm.height = h
	beam.mesh = cm
	beam.position.y = h * 0.5
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(col.r, col.g, col.b, 0.24)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.emission_enabled = true
	bmat.emission = col
	bmat.emission_energy_multiplier = 1.8
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return beam

func _clear_world_nodes():
	if is_instance_valid(event_root):
		event_root.queue_free()
		event_root = null
	pickup_node = null
	pickup_brick_vis = null
	pickup_beam = null
	pickup_label = null
	decode_node = null
	decode_brick_vis = null
	decode_beam = null
	decode_light = null
	decode_label = null
	reward_crate_node = null

func reset_for_run():
	close_modal()
	_clear_world_nodes()
	state = "inactive"
	decode_round = 0
	cipher_words.clear()
	wrong_attempts_round = 0
	wave_1_spawned = false
	wave_2_spawned = false
	pulse_clock = 0.0
	if not is_instance_valid(game):
		return
	if not game.is_ahsarah_map() or not game.rules.combat_mode:
		game.cached_interactables.clear()
		return
	# Activate MandelBrick Capture & Decryption Event on Ahsarah Combat Operations!
	state = "available"
	active_site_index = run_counter % AhsarahLayout.MANDEL_DECODE_SITES.size()
	run_counter += 1
	active_site = AhsarahLayout.MANDEL_DECODE_SITES[active_site_index]
	_spawn_event_props()
	game.cached_interactables.clear()

func _spawn_event_props():
	event_root = Node3D.new()
	event_root.name = "MandelEventRoot"
	add_child(event_root)

	# 1) Administrative Fortress Courtyard Vault Capture Pedestal
	var p_pos := AhsarahLayout.on_ground(AhsarahLayout.MANDEL_PICKUP_POS)
	pickup_node = Node3D.new()
	pickup_node.name = "MandelPickupPedestal"
	pickup_node.position = p_pos
	pickup_node.set_meta("mandel_role", "pickup")
	pickup_node.set_meta("title", "曼德尔加密砖 · 夺取点")
	event_root.add_child(pickup_node)

	var ped_mesh: Mesh = _extract_mesh(FORTRESS_GLB, "mandel_brick_pedestal")
	if ped_mesh != null:
		var pmi := MeshInstance3D.new()
		pmi.mesh = ped_mesh
		pickup_node.add_child(pmi)
	var ped_body := StaticBody3D.new()
	var ped_col := CollisionShape3D.new()
	var ped_shp := CylinderShape3D.new()
	ped_shp.radius = 0.72
	ped_shp.height = 1.32
	ped_col.shape = ped_shp
	ped_col.position.y = 0.66
	ped_body.add_child(ped_col)
	pickup_node.add_child(ped_body)

	pickup_brick_vis = _make_brick_visual()
	pickup_brick_vis.position = Vector3(0.0, 1.66, 0.0)
	pickup_node.add_child(pickup_brick_vis)

	pickup_beam = _make_beacon_beam(Color("42ecff"), 24.0)
	pickup_node.add_child(pickup_beam)

	var pl := OmniLight3D.new()
	pl.light_color = Color("42ecff")
	pl.light_energy = 2.4
	pl.omni_range = 9.0
	pl.position = Vector3(0.0, 1.8, 0.0)
	pickup_node.add_child(pl)

	pickup_label = game._label3d(pickup_node, "◆ 曼德尔加密砖 · [F] 夺取护送", Vector3(0.0, 2.55, 0.0), 34, Color("56f2ff"))
	pickup_label.pixel_size = 0.0068
	pickup_label.visibility_range_end = 95.0

	# 2) Active G.T.I. MandelBrick Decryption Station
	var d_pos := AhsarahLayout.on_ground(active_site.at)
	decode_node = Node3D.new()
	decode_node.name = "MandelDecodeStation"
	decode_node.position = d_pos
	decode_node.rotation_degrees.y = float(active_site.get("yaw", 0.0))
	decode_node.set_meta("mandel_role", "decode")
	decode_node.set_meta("title", str(active_site.title))
	event_root.add_child(decode_node)

	var st_mesh: Mesh = _extract_mesh(FORTRESS_GLB, "mandel_decode_station")
	if st_mesh != null:
		var smi := MeshInstance3D.new()
		smi.mesh = st_mesh
		decode_node.add_child(smi)
	var st_body := StaticBody3D.new()
	var st_col := CollisionShape3D.new()
	var st_shp := CylinderShape3D.new()
	st_shp.radius = 1.68
	st_shp.height = 3.2
	st_col.shape = st_shp
	st_col.position.y = 1.6
	st_body.add_child(st_col)
	decode_node.add_child(st_body)

	decode_brick_vis = _make_brick_visual()
	decode_brick_vis.position = Vector3(0.0, 1.88, 0.0)
	decode_brick_vis.visible = false
	decode_node.add_child(decode_brick_vis)

	decode_beam = _make_beacon_beam(Color("ffd15c"), 28.0)
	decode_beam.visible = false
	decode_node.add_child(decode_beam)

	decode_light = OmniLight3D.new()
	decode_light.light_color = Color("42ecff")
	decode_light.light_energy = 2.2
	decode_light.omni_range = 11.0
	decode_light.position = Vector3(0.0, 2.3, 0.4)
	decode_node.add_child(decode_light)

	decode_label = game._label3d(decode_node, "📡 %s · 待插入曼德尔砖" % str(active_site.title), Vector3(0.0, 3.65, 0.0), 34, Color("ffe28a"))
	decode_label.pixel_size = 0.0072
	decode_label.visibility_range_end = 135.0

func interactable_nodes() -> Array:
	var out: Array = []
	if state == "inactive":
		return out
	if is_instance_valid(pickup_node) and state == "available":
		out.append(pickup_node)
	if is_instance_valid(decode_node) and state in ["available", "carrying", "decoding"]:
		out.append(decode_node)
	if is_instance_valid(reward_crate_node) and reward_crate_node.visible:
		out.append(reward_crate_node)
	return out

func active_target_pos() -> Vector3:
	if state == "available" and is_instance_valid(pickup_node):
		return pickup_node.global_position
	if state in ["carrying", "decoding"] and is_instance_valid(decode_node):
		return decode_node.global_position
	return Vector3.ZERO

func status_hud_line() -> String:
	if state == "inactive":
		return ""
	if state == "available":
		return "◆ 曼德尔砖待夺取（行政堡垒庭院）"
	if state == "carrying":
		var dist := roundi(game.player.position.distance_to(decode_node.global_position)) if (is_instance_valid(game.player) and is_instance_valid(decode_node)) else 0
		return "◆ 已携带曼德尔砖 → %s (%dm)" % [str(active_site.get("title", "破译站")), dist]
	if state == "decoding":
		return "⚡ 曼德尔砖破译中（第 %d/3 轮）· 靠近站台按 [F]" % clampi(decode_round, 1, 3)
	if state == "completed":
		return "★ 曼德尔砖破译完成！"
	return ""

func prompt_for(node: Node3D) -> String:
	if not is_instance_valid(node) or not node.has_meta("mandel_role"):
		return ""
	var role := str(node.get_meta("mandel_role"))
	if role == "pickup":
		return "[F] 夺取【曼德尔加密砖】→ 护送至%s破译！" % str(active_site.get("title", "破译站"))
	if role == "decode":
		if state == "carrying":
			return "[F] 插入【曼德尔加密砖】启动破译（将引来拦截敌军！）"
		if state == "decoding":
			return "[F] 打开【曼德尔砖破译终端】（第 %d/3 轮英文破译）" % clampi(decode_round, 1, 3)
		return "🔒 %s · 请先前往行政堡垒庭院夺取曼德尔砖" % str(active_site.get("title", "破译站"))
	if role == "reward_crate":
		var rem: Array = node.get_meta("pending_items", [])
		if rem.is_empty():
			return "曼德尔砖破译秘藏 · 已搜空"
		return "[F] 搜刮【曼德尔砖破译秘藏】（剩余 %d 件）" % rem.size()
	return ""

func interact(node: Node3D) -> bool:
	if not is_instance_valid(node) or not node.has_meta("mandel_role"):
		return false
	var role := str(node.get_meta("mandel_role"))
	if role == "pickup":
		return pickup_brick()
	if role == "decode":
		if state == "carrying":
			return insert_brick()
		if state == "decoding":
			return open_cipher_modal()
		game.play_sfx("warning_lock", -12)
		game._notice("🔒 请先前往【行政堡垒庭院】夺取发光的曼德尔加密砖，再护送至此破译！", Color("ffd15c"))
		return true
	if role == "reward_crate":
		var rem: Array = node.get_meta("pending_items", [])
		if rem.is_empty():
			game._notice("曼德尔砖破译秘藏箱已搜空！", game.MINT)
			return true
		game.loot_container_ui.open_container(
			node, "crate", "曼德尔砖破译秘藏", rem,
			"破译成功奖励 · 严格金字塔掉率（含阿萨拉高阶珍品加权）", false
		)
		return true
	return false

func pickup_brick() -> bool:
	if state != "available":
		return false
	state = "carrying"
	if is_instance_valid(pickup_brick_vis):
		pickup_brick_vis.visible = false
	if is_instance_valid(pickup_beam):
		pickup_beam.visible = false
	if is_instance_valid(pickup_label):
		pickup_label.text = "✓ 曼德尔砖已夺取"
		pickup_label.modulate = Color("8ef0c8")
	if is_instance_valid(decode_beam):
		decode_beam.visible = true
	if is_instance_valid(decode_label):
		decode_label.text = "📡 %s · [F] 插入曼德尔砖！" % str(active_site.get("title", "破译站"))
		decode_label.modulate = Color("56f2ff")
	game.cached_interactables.clear()
	game.play_sfx("cipher_unlock", -9)
	game.screen_flash.color = Color(0.22, 0.88, 1.0, 0.14)
	game._notice("✦ 已夺取【曼德尔加密砖】！护送至【%s】按 [F] 插入破译（全图雷达已标出青色菱标）！" % str(active_site.get("title", "破译站")), Color("56f2ff"))
	return true

func _pick_three_cipher_words() -> Array:
	var source: Array = game.pool if game.pool.size() >= 6 else game.words
	var candidates: Array = []
	for w in source:
		var en_s := str(w.get("english", "")).strip_edges()
		if en_s.length() >= 3 and en_s.length() <= 14 and not (" " in en_s) and not ("'" in en_s) and not ("-" in en_s):
			candidates.append(w)
	if candidates.size() < 3:
		candidates = source.duplicate()
	candidates.shuffle()
	var picked: Array = []
	for c in candidates:
		var dup := false
		for p in picked:
			if str(p.get("english", "")).to_lower() == str(c.get("english", "")).to_lower():
				dup = true
				break
		if not dup:
			picked.append(c)
		if picked.size() >= 3:
			break
	return picked

func insert_brick() -> bool:
	if state != "carrying":
		return false
	state = "decoding"
	decode_round = 1
	wrong_attempts_round = 0
	cipher_words = _pick_three_cipher_words()
	if is_instance_valid(decode_brick_vis):
		decode_brick_vis.visible = true
	if is_instance_valid(decode_beam):
		decode_beam.visible = true
	if is_instance_valid(decode_label):
		decode_label.text = "⚡ %s · [F] 启动 3 轮英文破译！" % str(active_site.get("title", "破译站"))
		decode_label.modulate = Color("ffd86b")
	game.cached_interactables.clear()
	game.play_sfx("warning_lock", -7)
	game.screen_flash.color = Color(0.26, 0.90, 1.0, 0.18)
	if not wave_1_spawned and is_instance_valid(game.combat) and is_instance_valid(decode_node):
		wave_1_spawned = true
		game.combat.spawn_mandel_interceptors(decode_node.global_position, 1)
	game._notice("⚡ 曼德尔砖已接入【%s】！第 1 波阿萨拉拦截小队已逼近——靠近破译站按 [F] 进行 3 轮英文破译（破译界面自动暂停保护）！" % str(active_site.get("title", "破译站")), Color("ffd86b"))
	return true

func expected_cipher_word() -> String:
	if state != "decoding" or decode_round < 1 or decode_round > cipher_words.size():
		return ""
	return str(cipher_words[decode_round - 1].get("english", ""))

func _format_skeleton(word: String, extra_reveals: int = 0) -> String:
	var n := word.length()
	if n <= 2:
		return word.substr(0, 1) + " _"
	var parts: Array = []
	for i in n:
		var ch := word.substr(i, 1)
		if i == 0 or i == n - 1 or i <= extra_reveals:
			parts.append(ch)
		else:
			parts.append("_")
	return " ".join(parts)

func open_cipher_modal() -> bool:
	if state != "decoding" or decode_round < 1 or decode_round > cipher_words.size():
		return false
	if is_instance_valid(game.loot_ui) and game.loot_ui.any_modal_open():
		game.loot_ui.close_all_modals()
	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_modal()
	overlay.show()
	answer_input.grab_focus()
	var w_en := expected_cipher_word()
	if w_en != "" and not game.qa_mode:
		game.speak_english(w_en)
	return true

func close_modal():
	if not busy:
		return
	busy = false
	if is_instance_valid(overlay):
		overlay.hide()
	if is_instance_valid(game) and game.rules.phase in ["active", "extracting"]:
		game.paused = false
		game.player.active = true
		game.hud.show()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_modal():
	if decode_round < 1 or decode_round > cipher_words.size():
		return
	var w: Dictionary = cipher_words[decode_round - 1]
	var en_s := str(w.get("english", ""))
	var zh_s := str(w.get("chinese", ""))
	var pct: float = float(decode_round - 1) / 3.0
	modal_title.text = "⚡ G.T.I. 曼德尔砖量子破译终端 · %s" % str(active_site.get("title", "破译站"))
	modal_round_lbl.text = "破译进度：第 %d / 3 轮   （已解密 %d%%）" % [decode_round, roundi(pct * 100.0)]
	progress_fill.size.x = 676.0 * pct
	chinese_lbl.text = "中文释义：%s   （Unit %d · p.%d）" % [zh_s, int(w.get("unit", 1)), int(w.get("textbook_page", 1))]
	var cl: Dictionary = game.cloze_for_word(str(w.get("id", "")))
	cloze_lbl.text = ("教材语境：%s" % str(cl.cloze_text)) if not cl.is_empty() else "听标准发音并根据字母骨架拼出完整英文单词！"
	hint_lbl.text = "字母骨架提示：  %s   （共 %d 字母）" % [_format_skeleton(en_s, wrong_attempts_round), en_s.length()]
	answer_input.text = ""
	status_lbl.text = "输入英文拼写后按 [Enter] 或点击【写入破译密钥】（破译期间战场已安全暂停）。"
	status_lbl.add_theme_color_override("font_color", Color("8ef0c8"))

func submit_cipher(raw_text: String = "") -> bool:
	if state != "decoding" or decode_round < 1 or decode_round > cipher_words.size():
		return false
	var typed := (raw_text if raw_text != "" else (answer_input.text if is_instance_valid(answer_input) else "")).strip_edges().to_lower()
	var w: Dictionary = cipher_words[decode_round - 1]
	var expected := str(w.get("english", "")).strip_edges().to_lower()
	var wid := str(w.get("id", ""))
	if typed == expected:
		game.rules.answered += 1
		game.rules.correct += 1
		game.rules.streak += 1
		game.rules.best_streak = maxi(game.rules.best_streak, game.rules.streak)
		game.rules.score += 15
		if wid != "":
			var sp_out: String = game.LearningStore.HINTED if wrong_attempts_round > 0 else game.LearningStore.INDEPENDENT
			game.rules.learning.record_spelling(wid, sp_out, false, -1, true, "mandel_decode")
		game.play_sfx("cipher_unlock", -9)
		game.speak_english(str(w.get("english", "")))
		wrong_attempts_round = 0
		if decode_round == 1 and not wave_2_spawned and is_instance_valid(game.combat) and is_instance_valid(decode_node):
			wave_2_spawned = true
			game.combat.spawn_mandel_interceptors(decode_node.global_position, 2)
		if decode_round >= 3:
			_complete_decryption()
			return true
		decode_round += 1
		if is_instance_valid(decode_label):
			decode_label.text = "⚡ %s · [F] 继续破译（第 %d/3 轮）" % [str(active_site.get("title", "破译站")), decode_round]
		if busy:
			_refresh_modal()
			status_lbl.text = "✓ 第 %d/3 轮密钥校验通过！+15分%s" % [
				decode_round - 1,
				" · ⚠ 外部第 2 波哈夫克特勤拦截队已抵达！" if (decode_round == 2) else ""
			]
			status_lbl.add_theme_color_override("font_color", Color("ffd86b"))
		return true
	# Wrong attempt — record SRS, reveal one extra hint letter & play audio (never soft-lock!)
	wrong_attempts_round += 1
	game.rules.answered += 1
	game.rules.streak = 0
	if wid != "":
		game.rules.learning.record_spelling(wid, game.LearningStore.INCORRECT, false, -1, true, "mandel_decode")
	if w not in game.wrong_words:
		game.wrong_words.append(w)
	game.play_sfx("hit_wrong", -10)
	game.speak_english(str(w.get("english", "")))
	if busy:
		hint_lbl.text = "字母骨架提示：  %s   （已解锁更多字母！）" % _format_skeleton(str(w.get("english", "")), wrong_attempts_round)
		status_lbl.text = "✕ 拼写有误，请细听读音并参照字母骨架重试！（输入：%s）" % typed
		status_lbl.add_theme_color_override("font_color", Color("ff8a80"))
		answer_input.select_all()
		answer_input.grab_focus()
	return false

func _complete_decryption():
	state = "completed"
	close_modal()
	var bonus_score: int = 120 if game.rules.is_confidential() else 90
	game.rules.score += bonus_score
	game.rules.perfect_ciphers += 1
	game.player.add_reserve_ammo(8)
	if is_instance_valid(game.combat) and game.combat.in_field():
		game.combat.heal(10, 15)
	if is_instance_valid(decode_beam):
		decode_beam.visible = false
	if is_instance_valid(decode_light):
		decode_light.light_color = Color("6ae3a8")
	if is_instance_valid(decode_label):
		decode_label.text = "★ %s · 曼德尔砖破译完成！" % str(active_site.get("title", "破译站"))
		decode_label.modulate = Color("8ef5c8")
	game.play_sfx("loot_epic", -6)
	game.screen_flash.color = Color(0.32, 0.96, 0.88, 0.22)

	if is_instance_valid(game.achievements):
		game.achievements.record_stat("mandel_decoded", 1)

	# Spawn physical MandelBrick Reward Crate right beside the station (3 calibrated pyramid rolls!)
	var rewards: Array = game.rules.roll_mandel_reward_items()
	if is_instance_valid(event_root) and is_instance_valid(decode_node):
		var cr_pos := decode_node.global_position + Vector3(2.15, 0.0, 1.35)
		cr_pos.y = AhsarahLayout.height(cr_pos.x, cr_pos.z)
		reward_crate_node = Node3D.new()
		reward_crate_node.name = "MandelRewardCrate"
		reward_crate_node.position = cr_pos
		reward_crate_node.set_meta("mandel_role", "reward_crate")
		reward_crate_node.set_meta("title", "曼德尔砖破译秘藏")
		reward_crate_node.set_meta("pending_items", rewards.duplicate(true))
		event_root.add_child(reward_crate_node)
		TacticalProps.build_tiered_vault_crate(game, reward_crate_node, 3)
		var rl: Label3D = game._label3d(reward_crate_node, "✦ 曼德尔砖破译秘藏 · [F] 搜刮", Vector3(0.0, 1.65, 0.0), 30, Color("56f2ff"))
		rl.pixel_size = 0.0056
		rl.visibility_range_end = 42.0
		game.cached_interactables.clear()

	game._notice("🏆 曼德尔加密砖破译成功！+%d 积分 · 备弹+8 · 护盾+15 · 开启破译秘藏箱！" % bonus_score, Color("56f2ff"))
	if is_instance_valid(game.loot_container_ui) and not rewards.is_empty():
		game.loot_container_ui.open_container(
			reward_crate_node, "crate", "曼德尔砖破译秘藏", rewards,
			"3 轮英文量子破译成功！左侧挑选心仪珍宝带走，未拿走的保留在破译箱内。", true
		)

func update(delta: float):
	if state == "inactive":
		return
	pulse_clock += delta
	if is_instance_valid(pickup_brick_vis) and pickup_brick_vis.visible:
		pickup_brick_vis.rotation.y += delta * 1.45
		pickup_brick_vis.position.y = 1.66 + sin(pulse_clock * 2.8) * 0.10
	if is_instance_valid(decode_brick_vis) and decode_brick_vis.visible:
		var spd := 4.4 if state == "decoding" else 1.2
		decode_brick_vis.rotation.y += delta * spd
		decode_brick_vis.position.y = 1.88 + sin(pulse_clock * 4.5) * 0.07
	if is_instance_valid(decode_light):
		if state == "decoding":
			decode_light.light_energy = 2.4 + sin(pulse_clock * 6.5) * 0.9
		elif state == "carrying":
			decode_light.light_energy = 2.0 + sin(pulse_clock * 3.0) * 0.6

func _build_ui():
	overlay = Control.new()
	overlay.name = "MandelDecodeOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.068, 0.88)
	overlay.add_child(veil)

	game._panel(overlay, Rect2(260, 128, 760, 464), Color(0.036, 0.075, 0.112, 0.98), Color("46e8ff"))

	modal_title = game._text(overlay, "⚡ G.T.I. 曼德尔砖量子破译终端", Vector2(292, 148), Vector2(560, 32), 22, Color("5ef2ff"))
	modal_title.clip_text = true
	close_btn = game._button(overlay, "暂离 [Esc]", Rect2(886, 146, 108, 36), close_modal)

	modal_round_lbl = game._text(overlay, "破译进度：第 1 / 3 轮", Vector2(292, 190), Vector2(680, 24), 15, Color("ffd86b"))
	var pb_bg := ColorRect.new()
	pb_bg.position = Vector2(292, 218)
	pb_bg.size = Vector2(676, 10)
	pb_bg.color = Color(0.08, 0.16, 0.22, 0.95)
	overlay.add_child(pb_bg)
	progress_fill = ColorRect.new()
	progress_fill.position = Vector2(292, 218)
	progress_fill.size = Vector2(0, 10)
	progress_fill.color = Color("42ecff")
	overlay.add_child(progress_fill)

	game._panel(overlay, Rect2(292, 244, 676, 152), Color(0.025, 0.056, 0.086, 0.95), Color(0.32, 0.78, 0.92, 0.50))
	chinese_lbl = game._text(overlay, "中文释义：", Vector2(312, 258), Vector2(636, 30), 22, Color("fff6db"))
	cloze_lbl = game._text(overlay, "教材语境：", Vector2(312, 298), Vector2(636, 44), 15, Color("b4e0f2"))
	cloze_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl = game._text(overlay, "字母骨架提示：", Vector2(312, 352), Vector2(636, 28), 18, Color("ffd86b"))

	answer_input = LineEdit.new()
	answer_input.position = Vector2(292, 414)
	answer_input.size = Vector2(448, 46)
	answer_input.placeholder_text = "在此拼写英文单词（按 Enter 提交）"
	answer_input.add_theme_font_size_override("font_size", 20)
	answer_input.text_submitted.connect(func(txt: String): submit_cipher(txt))
	overlay.add_child(answer_input)

	speak_btn = game._button(overlay, "🔊 听读音", Rect2(754, 414, 102, 46), func():
		var w_en := expected_cipher_word()
		if w_en != "":
			game.speak_english(w_en)
	)
	submit_btn = game._button(overlay, "⚡ 写入密钥", Rect2(868, 414, 100, 46), func(): submit_cipher(), true)

	status_lbl = game._text(overlay, "提示：连续破译 3 轮即可解锁曼德尔砖秘藏！", Vector2(292, 480), Vector2(676, 48), 14, Color("8ef0c8"))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var footer: Label = game._text(overlay, "G.T.I. 战术提示：破译成功可获 +90/+120 撤离积分与 3 格阿萨拉高阶秘藏（严格金字塔概率）！", Vector2(292, 544), Vector2(676, 24), 13, Color("7baac0"))
	footer.clip_text = true
	overlay.hide()
