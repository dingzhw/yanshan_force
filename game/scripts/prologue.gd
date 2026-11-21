extends Node3D
## Standalone Single-Player Prologue Chapter ("烟山初行：望稻亭失联信标" · v0.8.2_dev1)
## Mounted via editable Godot scene `res://scenes/prologue_chapter.tscn`.
## Designed for 10+ first-time players to independently launch, follow diegetic Jiangnan landmarks,
## engage a short 3-word scout encounter, decode an audio/text English clue at Wangdao Pavilion,
## recover the silenced beacon (pointing to Yanxia Ancient Cave), and hand it in at Camp.

const HIT_LAYER := 64  # Dedicated bit 6 for Prologue Scout targets
const BRIEFING_CLUE_EN := "Cross the bridge and climb the stone steps to the pavilion."
const BEACON_CLUE_EN := "Look beside the green celadon cup. The signal points north to the misty cave."

var game
var active: bool = false
var stage: String = "inactive"  # "briefing" | "skirmish" | "beacon_clue" | "return_camp" | "completed"
var busy: bool = false

var npc_node: Node3D
var npc_label: Label3D
var npc_beacon_ring: MeshInstance3D
var beacon_node: Node3D
var beacon_label: Label3D
var beacon_pulse_mesh: MeshInstance3D
var wayfinder_nodes: Array = []

var scouts: Array = []          # Array of Dictionaries: {node, area, word, label, frame_mat, defeated}
var active_scout_idx: int = -1
var scouts_cleared: int = 0
var scout_wrong_attempts: int = 0

var clue_attempts: int = 0
var clue_first_try_correct: bool = false
var clue_solved: bool = false
var started_ms: int = -1
var pulse_clock: float = 0.0

# Dialogue / Clue / Task Log UI
var modal_overlay: Control
var modal_title: Label
var modal_body: Label
var modal_clue_btn: Button
var modal_choice_btns: Array = []
var modal_feedback: Label
var modal_close_btn: Button
var current_modal_kind: String = ""

func setup(g):
	game = g
	_build_world_props()
	_build_modal_ui()
	set_active(false)

func _marker_ground(marker_name: String, fallback: Vector3) -> Vector3:
	var m := get_node_or_null(marker_name) as Node3D
	var xz := m.position if m != null else fallback
	return Vector3(xz.x, float(game.terrain_height(xz.x, xz.z)), xz.z)

func _build_world_props():
	# 1) Camp Liaison NPC ("陈向导 · 烟山联络员") standing warmly beside Camp briefing area
	var npc_pos := _marker_ground("CampGuideAnchor", game.Layout.SPAWN + Vector3(-2.8, 0.0, 0.8))
	npc_node = Node3D.new()
	npc_node.name = "CampGuideNPC"
	npc_node.position = npc_pos
	npc_node.rotation.y = 0.55
	npc_node.set_meta("prologue_interact", "npc")
	add_child(npc_node)

	# Stylized Jiangnan ranger silhouette: boots, teal scout tunic, collar scarf, head, woven bamboo hat, glowing hand lantern
	var coat_mat := StandardMaterial3D.new()
	coat_mat.albedo_color = Color("1f4f52")
	coat_mat.roughness = 0.78
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color("e8c4a2")
	skin_mat.roughness = 0.72
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color("bfa065")
	hat_mat.roughness = 0.85
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color("ffe082")
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color("ffb84d")
	lantern_mat.emission_energy_multiplier = 2.0

	var legs: MeshInstance3D = game._mesh_box(npc_node, Vector3(0, 0.42, 0), Vector3(0.42, 0.84, 0.28), Color("263238"), false)
	legs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torso := MeshInstance3D.new()
	var t_cyl := CylinderMesh.new()
	t_cyl.top_radius = 0.22
	t_cyl.bottom_radius = 0.27
	t_cyl.height = 0.74
	torso.mesh = t_cyl
	torso.position = Vector3(0, 1.14, 0)
	torso.material_override = coat_mat
	npc_node.add_child(torso)

	var scarf: MeshInstance3D = game._mesh_box(npc_node, Vector3(0, 1.48, 0.03), Vector3(0.32, 0.11, 0.30), Color("d96b43"), false)
	scarf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var head := MeshInstance3D.new()
	var h_sph := SphereMesh.new()
	h_sph.radius = 0.17
	h_sph.height = 0.34
	head.mesh = h_sph
	head.position = Vector3(0, 1.66, 0)
	head.material_override = skin_mat
	npc_node.add_child(head)

	var hat := MeshInstance3D.new()
	var hat_cone := CylinderMesh.new()
	hat_cone.top_radius = 0.04
	hat_cone.bottom_radius = 0.44
	hat_cone.height = 0.18
	hat.mesh = hat_cone
	hat.position = Vector3(0, 1.84, 0)
	hat.material_override = hat_mat
	npc_node.add_child(hat)

	var lantern := MeshInstance3D.new()
	var l_box := BoxMesh.new()
	l_box.size = Vector3(0.16, 0.24, 0.16)
	lantern.mesh = l_box
	lantern.position = Vector3(0.34, 1.12, 0.22)
	lantern.material_override = lantern_mat
	npc_node.add_child(lantern)

	# Glowing ground ring around Camp Guide when awaiting briefing or hand-in
	npc_beacon_ring = MeshInstance3D.new()
	var ring_m := TorusMesh.new()
	ring_m.inner_radius = 0.78
	ring_m.outer_radius = 0.90
	npc_beacon_ring.mesh = ring_m
	npc_beacon_ring.position = Vector3(0, 0.06, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color("8de8c0")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("8de8c0")
	npc_beacon_ring.material_override = ring_mat
	npc_node.add_child(npc_beacon_ring)

	npc_label = game._label3d(npc_node, "陈向导 · 烟山联络员 [F]", Vector3(0, 2.24, 0), 34, Color("ffe39c"))
	npc_label.pixel_size = 0.0052
	npc_label.visibility_range_end = 42.0

	# 2) Diegetic warm-gold stone wayfinder lanterns along Camp -> South Bridge -> East Path -> Wangdao Stairs
	var wf_specs := [
		["Wayfinder_SouthBridge", Vector3(25.0, 0.0, 16.0), "南桥渡口 · 过桥赴东岭 ↗"],
		["Wayfinder_EastPath", Vector3(37.5, 0.0, 17.8), "东岭山道 · 前方斥候警戒 ↗"],
		["Wayfinder_WangdaoStairs", Vector3(49.5, 0.0, 22.4), "望稻亭石阶 · 登台查信标 ↗"]
	]
	for spec in wf_specs:
		var wpos := _marker_ground(spec[0], spec[1])
		var wf := Node3D.new()
		wf.name = "Prologue_" + str(spec[0])
		wf.position = wpos
		add_child(wf)
		game._mesh_box(wf, Vector3(0, 0.62, 0), Vector3(0.22, 1.24, 0.22), Color("5b6562"), false)
		var lamp: MeshInstance3D = game._mesh_box(wf, Vector3(0, 1.36, 0), Vector3(0.32, 0.34, 0.32), Color("ffd875"), false)
		var lmat := StandardMaterial3D.new()
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat.albedo_color = Color("ffe08c")
		lamp.material_override = lmat
		var wlbl: Label3D = game._label3d(wf, str(spec[2]), Vector3(0, 1.88, 0), 26, Color("ffe59e"))
		wlbl.pixel_size = 0.0046
		wlbl.visibility_range_end = 36.0
		wayfinder_nodes.append(wf)

	# 3) Wangdao Pavilion Silenced Relay Beacon + Celadon Sample on elevated Wangdao Overlook Terrace!
	var wd_x := float(game.Layout.WANGDAO_PAVILION.x) + 1.7
	var wd_z := float(game.Layout.WANGDAO_PAVILION.z) + 2.8
	var deck_pos := Vector3(wd_x, float(game.terrain_height(game.Layout.WANGDAO_PAVILION.x, game.Layout.WANGDAO_PAVILION.z)) + 2.75, wd_z)
	if is_instance_valid(game.landscape) and game.landscape.wangdao_deck_pos.length() > 1.0:
		deck_pos = Vector3(game.landscape.wangdao_deck_pos.x, game.landscape.wangdao_deck_pos.y - 0.015, game.landscape.wangdao_deck_pos.z - 1.85)
	beacon_node = Node3D.new()
	beacon_node.name = "WangdaoLostBeacon"
	beacon_node.position = deck_pos
	beacon_node.set_meta("prologue_interact", "beacon")
	add_child(beacon_node)
	game._mesh_box(beacon_node, Vector3(0, 0.38, 0), Vector3(0.76, 0.76, 0.56), Color("233b42"), false)
	game._mesh_box(beacon_node, Vector3(0, 0.84, 0), Vector3(0.10, 0.65, 0.10), Color("586a6e"), false)
	beacon_pulse_mesh = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.14
	orb.height = 0.28
	beacon_pulse_mesh.mesh = orb
	beacon_pulse_mesh.position = Vector3(0, 1.24, 0)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color("ffb84d")
	beacon_pulse_mesh.material_override = bmat
	beacon_node.add_child(beacon_pulse_mesh)
	# Miniature celadon cup right next to the silenced beacon
	var celadon_vis: Node3D = game.LootUI.build_world_loot_mesh("celadon", 7, Color("72e0b6"), 0.55)
	celadon_vis.position = Vector3(0.28, 0.76, 0.05)
	beacon_node.add_child(celadon_vis)
	beacon_label = game._label3d(beacon_node, "📡 失联信标匣与青瓷残片 [F]", Vector3(0, 1.66, 0), 30, Color("ffd166"))
	beacon_label.pixel_size = 0.0048
	beacon_label.visibility_range_end = 42.0

func _build_modal_ui():
	modal_overlay = Control.new()
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(modal_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.055, 0.88)
	modal_overlay.add_child(veil)

	game._panel(modal_overlay, Rect2(204, 62, 872, 596), Color(0.046, 0.098, 0.118, 0.98), Color("ffd166"))
	modal_title = game._text(modal_overlay, "烟山初行 · 单人序章", Vector2(242, 84), Vector2(640, 38), 26, game.GOLD)
	modal_clue_btn = game._button(modal_overlay, "🔊 播放英文线索", Rect2(886, 84, 156, 38), _speak_current_clue)
	modal_body = game._text(modal_overlay, "", Vector2(242, 134), Vector2(800, 214), 17, game.CREAM)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	modal_choice_btns.clear()
	for idx in 3:
		var b: Button = game._button(modal_overlay, "", Rect2(242, 358 + idx * 54, 800, 46), _on_choice_pressed.bind(idx))
		b.add_theme_font_size_override("font_size", 16)
		b.hide()
		modal_choice_btns.append(b)

	modal_feedback = game._text(modal_overlay, "", Vector2(242, 528), Vector2(800, 52), 15, game.MINT)
	modal_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	modal_close_btn = game._button(modal_overlay, "继续行动 [Esc]", Rect2(834, 592, 212, 42), close_modal, true)
	modal_overlay.hide()

func set_active(on: bool):
	active = on
	visible = on
	if is_instance_valid(npc_node):
		npc_node.visible = on
	if is_instance_valid(beacon_node):
		beacon_node.visible = on
	for wf in wayfinder_nodes:
		if is_instance_valid(wf):
			wf.visible = on
	if not on:
		stage = "inactive"
		_clear_scouts()
		if is_instance_valid(modal_overlay):
			modal_overlay.hide()
		busy = false

func _clear_scouts():
	for sc in scouts:
		if is_instance_valid(sc.node):
			sc.node.queue_free()
	scouts.clear()
	active_scout_idx = -1

func _pick_prologue_words() -> Array:
	# Choose 3 friendly, distinct, voice-backed single words/phrases from Grade 5A vocabulary
	var preferred_en := ["forest", "bridge", "hill", "river", "mountain", "house", "between", "beside", "behind"]
	var picked := []
	for target_en in preferred_en:
		for w in game.words:
			if str(w.get("english", "")).to_lower() == target_en:
				picked.append(w)
				break
		if picked.size() >= 3:
			break
	for w in game.words:
		if picked.size() >= 3:
			break
		if w not in picked and str(w.get("kind", "word")) == "word":
			picked.append(w)
	return picked

func _spawn_prologue_scouts():
	_clear_scouts()
	var pwords := _pick_prologue_words()
	var anchors := [
		["ScoutAnchor_1", Vector3(25.0, 0.0, 11.8)],
		["ScoutAnchor_2", Vector3(27.8, 0.0, 13.6)],
		["ScoutAnchor_3", Vector3(30.2, 0.0, 15.8)]
	]
	for i in mini(3, pwords.size()):
		var pos := _marker_ground(anchors[i][0], anchors[i][1])
		var root := Node3D.new()
		root.name = "PrologueScout_%d" % i
		root.position = pos
		add_child(root)

		# Compact Mistbound Recon Scout Dummy with elevated readable English word shield
		game._mesh_box(root, Vector3(0, 0.55, 0), Vector3(0.46, 1.10, 0.34), Color("283842"), false)
		game._mesh_box(root, Vector3(0, 1.24, 0), Vector3(0.32, 0.28, 0.30), Color("3c525e"), false)
		var visor: MeshInstance3D = game._mesh_box(root, Vector3(0, 1.26, 0.16), Vector3(0.24, 0.07, 0.04), Color("ffb84d"), false)
		(visor.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var area := Area3D.new()
		area.position = Vector3(0, 1.88, 0)
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("prologue_scout_idx", i)
		root.add_child(area)
		var shp := BoxShape3D.new()
		shp.size = Vector3(1.88, 0.72, 0.24)
		var col := CollisionShape3D.new()
		col.shape = shp
		area.add_child(col)

		var bezel: MeshInstance3D = game._mesh_box(area, Vector3(0, 0, -0.02), Vector3(1.86, 0.70, 0.06), Color("ffd166"), false)
		var fmat: StandardMaterial3D = bezel.material_override
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var board: MeshInstance3D = game._mesh_box(area, Vector3(0, 0, 0.02), Vector3(1.74, 0.58, 0.05), Color("faf7ec"), false)
		(board.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var wlbl: Label3D = game._label3d(area, str(pwords[i].get("english", "")), Vector3(0, -0.02, 0.065), 54, Color("142228"))
		wlbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		wlbl.pixel_size = 0.0054
		wlbl.width = 310
		wlbl.outline_size = 2
		wlbl.outline_modulate = Color("ffffff")
		wlbl.visibility_range_end = 78.0

		scouts.append({
			"idx": i,
			"node": root,
			"area": area,
			"word": pwords[i],
			"label": wlbl,
			"frame_mat": fmat,
			"defeated": false
		})
	active_scout_idx = 0 if not scouts.is_empty() else -1
	_sync_active_scout_question()

func _sync_active_scout_question():
	active_scout_idx = -1
	for i in scouts.size():
		if not scouts[i].defeated:
			active_scout_idx = i
			break
	if active_scout_idx >= 0:
		game.question = scouts[active_scout_idx].word
		game.question_help_used = false
		game.listening_mode = false

func start_prologue(auto_open_briefing: bool = true):
	set_active(true)
	stage = "briefing"
	scouts_cleared = 0
	scout_wrong_attempts = 0
	clue_attempts = 0
	clue_first_try_correct = false
	clue_solved = false
	started_ms = Time.get_ticks_msec()
	_spawn_prologue_scouts()
	if is_instance_valid(npc_label):
		npc_label.text = "陈向导 · 烟山联络员 [F 接任务]"
	if is_instance_valid(beacon_label):
		beacon_label.text = "📡 失联信标匣与青瓷残片 [F 查验]"
	if is_instance_valid(game.player):
		game.player.position = game.Layout.on_ground(Vector3(0.0, 0.0, 6.2)) + Vector3.UP * 0.15
		var to_npc: Vector3 = npc_node.position - game.player.position
		game.player.yaw = atan2(-to_npc.x, -to_npc.z)
		game.player.pitch = -0.02
	if auto_open_briefing:
		open_npc_dialogue()

func open_npc_dialogue():
	if not active:
		return
	if stage == "return_camp":
		complete_prologue()
		return
	current_modal_kind = "briefing"
	_enter_modal()
	modal_title.text = "陈向导 · 烟山初行（望稻亭信标失联）"
	modal_clue_btn.show()
	modal_clue_btn.text = "🔊 听英文路线线索"
	for b in modal_choice_btns:
		b.hide()
	modal_body.text = (
		"「欢迎来到烟山基地！东岭【望稻亭】上的联络信标今晨突然断讯，雾隐帮斥候刚刚潜入了桥东山道。」\n\n"
		+ "英文行动线索（可随时按 [J] 重查或 [X] 重听）：\n"
		+ "  \"" + BRIEFING_CLUE_EN + "\"\n\n"
		+ "你的初行任务：\n"
		+ "  1. 沿暖金路灯过南桥上东岭，用英文识词击破 3 名雾隐斥候词盾；\n"
		+ "  2. 登上望稻亭观景台，按 [F] 查验失联信标与越窑青瓷残片；\n"
		+ "  3. 带回信标匣交给营地陈向导完成交付！"
	)
	modal_feedback.text = "提示：序章备弹无限且节奏温和，按 [WASD] 移动、左键射击英文词牌、[X] 听读音、[J] 随时重查任务。"
	modal_close_btn.text = "接下任务 · 出发 [Esc]"
	if stage == "briefing":
		stage = "skirmish"
		if is_instance_valid(npc_label):
			npc_label.text = "陈向导 · 等待信标带回 [F]"

func open_beacon_clue():
	if not active:
		return
	if stage == "skirmish" and scouts_cleared < scouts.size():
		game._notice("先击破桥东山道的 3 名雾隐斥候词盾（%d/3），再安全查验望稻亭信标！" % scouts_cleared, game.GOLD)
		return
	if clue_solved:
		open_task_log()
		return
	current_modal_kind = "beacon_clue"
	_enter_modal()
	modal_title.text = "望稻亭观景台 · 失联信标与越窑青瓷线索"
	modal_clue_btn.show()
	modal_clue_btn.text = "🔊 重听英文线索"
	modal_body.text = (
		"你在望稻亭木挑台旁找到了闪烁微光的失联信标匣，匣旁静置着一只泛着青碧釉光的瓷盏残片。\n"
		+ "信标存储芯片循环播报着一段英文语音线索：\n\n"
		+ "  \"" + BEACON_CLUE_EN + "\"\n\n"
		+ "请根据上方英文线索判断：信标旁发现的器物，以及异常信号指向的下一处地点分别是？"
	)
	var opts := [
		"A. 一只绿色青瓷盏（green celadon cup），信号指向北方的烟霞古洞（misty cave）",
		"B. 一把红漆纸伞（red umbrella），信号指向南方的山下稻田",
		"C. 一块白色大理石（white stone），信号指向东侧的山顶铁塔"
	]
	for i in 3:
		modal_choice_btns[i].text = opts[i]
		modal_choice_btns[i].disabled = false
		modal_choice_btns[i].show()
	modal_feedback.text = "提示：答错也可重听英文线索继续尝试；系统会单独记录你是否首次独立答对。"
	modal_close_btn.text = "暂缓查验 [Esc]"
	game.speak_english(BEACON_CLUE_EN)

func open_task_log():
	if not active:
		return
	current_modal_kind = "task_log"
	_enter_modal()
	modal_title.text = "📋 任务记录 · 烟山初行（按 [J] 随时打开）"
	modal_clue_btn.show()
	modal_clue_btn.text = "🔊 听当前英文线索"
	for b in modal_choice_btns:
		b.hide()
	var s1 := "✓" if scouts_cleared >= scouts.size() else "▶"
	var s2 := "✓" if clue_solved else ("▶" if scouts_cleared >= scouts.size() else "○")
	var s3 := "✓" if stage == "completed" else ("▶" if stage == "return_camp" else "○")
	var cave_hint := "\n【已截获异常日志】烟霞古洞深处传来未知低频声呐脉冲——将在下一章继续追踪！" if clue_solved else ""
	modal_body.text = (
		"当前任务：望稻亭的信标失联\n\n"
		+ "  %s 步骤 1：沿暖金路灯过南桥上东岭，识词击破 3 名雾隐斥候（%d/%d）\n" % [s1, scouts_cleared, scouts.size()]
		+ "  %s 步骤 2：登上东岭望稻亭，按 [F] 听读英文线索并查验失联信标与越窑青瓷\n" % s2
		+ "  %s 步骤 3：带回失联信标匣返回营地，按 [F] 交付给陈向导完成结算\n\n" % s3
		+ "英文线索备份：\n  \"" + (BEACON_CLUE_EN if clue_solved or scouts_cleared >= scouts.size() else BRIEFING_CLUE_EN) + "\""
		+ cave_hint
	)
	modal_feedback.text = "操作提醒：[WASD] 移动 · 左键射英文词牌 · [F] 交互 · [X] 读音 · [Esc] 暂停或调节舒适设置。"
	modal_close_btn.text = "返回烟山 [Esc]"

func _on_choice_pressed(idx: int):
	if current_modal_kind != "beacon_clue" or clue_solved:
		return
	clue_attempts += 1
	var is_right := (idx == 0)
	if is_right:
		clue_solved = true
		clue_first_try_correct = (clue_attempts == 1)
		game.rules.learning.record_recognition(
			"prologue-wangdao-clue",
			true,
			3,
			not clue_first_try_correct,
			-1,
			"prologue",
			"listening"
		)
		game.play_sfx("cipher_unlock", -10)
		var celadon_note: Dictionary = game.Rules.CULTURAL_NOTES.get("越窑秘色青瓷盏", {})
		modal_body.text = (
			"★ 辨认成功！你已安全收起【望稻亭失联信标匣】！\n\n"
			+ "【烟山物语（游戏设定）】\n"
			+ "信标日志显示：一股低频声波源自北方「烟霞古洞」，正是它截断了东岭通讯——这枚青瓷残片与日志将成为下一章深入古洞的关键线索。\n\n"
			+ "【器物考据（历史资料）】\n"
			+ str(celadon_note.get("fact", "唐代越窑「秘色瓷」釉色青碧莹润，以浙江上林湖窑系最为著名。"))
		)
		for b in modal_choice_btns:
			b.hide()
		modal_feedback.text = "★ 请带着信标匣沿石阶原路返回山脚营地，按 [F] 交付给陈向导完成序章！"
		modal_close_btn.text = "收下信标 · 返营交付 [Esc]"
		stage = "return_camp"
		if is_instance_valid(beacon_label):
			beacon_label.text = "✓ 信标匣已取回 · 请返营交付陈向导"
		if is_instance_valid(npc_label):
			npc_label.text = "★ 陈向导 · 按 [F] 交付失联信标"
	else:
		game.rules.learning.record_recognition("prologue-wangdao-clue", false, 3, false, -1, "prologue", "listening")
		game.play_sfx("hit_wrong", -12)
		modal_choice_btns[idx].disabled = true
		modal_feedback.text = "提示：green celadon cup = 青瓷盏，north to the misty cave = 向北指向烟霞古洞。再听一次线索试试！"
		game.speak_english(BEACON_CLUE_EN)

func _speak_current_clue():
	var txt := BEACON_CLUE_EN if (current_modal_kind == "beacon_clue" or clue_solved or scouts_cleared >= scouts.size()) else BRIEFING_CLUE_EN
	game.speak_english(txt)

func _enter_modal():
	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	modal_overlay.show()

func close_modal():
	if not busy:
		return
	busy = false
	modal_overlay.hide()
	if stage == "completed":
		return
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func hit_bullet(collider: Object) -> bool:
	if not active or stage != "skirmish" or not (collider is Area3D):
		return false
	if not collider.has_meta("prologue_scout_idx"):
		return false
	var idx := int(collider.get_meta("prologue_scout_idx", -1))
	if idx < 0 or idx >= scouts.size() or scouts[idx].defeated:
		return false
	var remaining := 0
	for s in scouts:
		if not s.defeated:
			remaining += 1
	var target_sc: Dictionary = scouts[active_scout_idx] if active_scout_idx >= 0 else scouts[idx]
	var target_word: Dictionary = target_sc.word
	var is_right := (idx == active_scout_idx)
	if is_right:
		scouts[idx].defeated = true
		scouts[idx].area.collision_layer = 0
		scouts[idx].node.hide()
		scouts_cleared += 1
		game.rules.learning.record_recognition(
			str(target_word.get("id", "")),
			true,
			maxi(1, remaining),
			game.question_help_used,
			-1,
			"prologue",
			"recognition"
		)
		game.rules.score += 20
		game.rules.answered += 1
		game.rules.correct += 1
		game.show_hitmarker(true)
		game.play_sfx("hit_correct", -10)
		game.speak_english(str(target_word.get("english", "")))
		_sync_active_scout_question()
		if scouts_cleared >= scouts.size():
			stage = "beacon_clue"
			game.play_sfx("cipher_unlock", -10)
			game._notice("★ 东岭 3 名雾隐斥候已全部肃清！请沿石阶登上望稻亭，按 [F] 查验失联信标！", game.MINT)
		else:
			var next_zh := str(scouts[active_scout_idx].word.get("chinese", ""))
			game._notice("✓ 精准命中 %s！下一个斥候词盾：【%s】（%d/%d）" % [
				str(target_word.get("english", "")), next_zh, scouts_cleared, scouts.size()
			], game.MINT)
	else:
		scout_wrong_attempts += 1
		game.rules.answered += 1
		game.rules.learning.record_recognition(str(target_word.get("id", "")), false, maxi(1, remaining), false, -1, "prologue", "recognition")
		game.show_hitmarker(false)
		game.play_sfx("hit_wrong", -12)
		var shot_en := str(scouts[idx].word.get("english", ""))
		game._notice("那是 %s，我们要找的是【%s】对应的英文牌！按 [X] 可听发音提示。" % [shot_en, str(target_word.get("chinese", ""))], Color("ffd166"))
	return true

func complete_prologue():
	stage = "completed"
	busy = false
	if is_instance_valid(modal_overlay):
		modal_overlay.hide()
	var elapsed_sec := maxi(1, roundi(float(Time.get_ticks_msec() - started_ms) / 1000.0)) if started_ms >= 0 else 1
	var first_clear := not bool(game.rules.profile.get("prologue_completed", false))
	game.rules.profile["prologue_completed"] = true
	var prev_best := int(game.rules.profile.get("prologue_best_seconds", 0))
	if prev_best <= 0 or elapsed_sec < prev_best:
		game.rules.profile["prologue_best_seconds"] = elapsed_sec
	game.rules.profile.coins += 120 if first_clear else 40
	game.rules.profile.xp += 60 if first_clear else 25
	if is_instance_valid(game.rangers):
		game.rangers.unlock_card("chen_guide", false)
	game.rules.phase = "result"
	game.rules.prologue_mode = false
	var saved: bool = game._save()
	game.play_sfx("loot_epic", -9)
	set_active(false)
	game.paused = true
	game.player.clear_movement_input()
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.menu.show()
	game.hud.hide()
	game._refresh_menu("★ 烟山初行 · 序章完成！")
	var ind: int = int(game.rules.learning.run_independent)
	var ast: int = int(game.rules.learning.run_assisted)
	var due_now: int = game._pending_retest().size()
	var reward_str := "+120 战备币 · +60 XP（首通奖励）" if first_clear else "+40 战备币 · +25 XP（重温奖励）"
	var clue_tag := "首次独立辨认 ✓" if clue_first_try_correct else "提示后完成辨认"
	game.menu_summary.text = (
		"【陈向导已接收望稻亭失联信标匣】 %s\n" % reward_str
		+ "实测用时：%d 分 %02d 秒 · 望稻亭线索：%s\n" % [elapsed_sec / 60, elapsed_sec % 60, clue_tag]
		+ "学习证据：本次独立答对 %d · 看提示/练习完成 %d · 下次待练 %d\n" % [ind, ast, due_now]
		+ "下一章伏笔：信标已锁定北方「烟霞古洞」异常声呐脉冲——现可点击「开始普通行动」正式启程！"
	)
	if not saved:
		game.menu_summary.text = "⚠ 存档写入失败，请检查磁盘与权限！\n" + game.menu_summary.text
		game.menu_status.text = "存档写入失败（" + game.last_save_error + "）。"
	else:
		game.menu_status.text = "序章进度已存档！现在可以点击「开始普通行动」体验完整搜打撤。"

func current_objective_text() -> String:
	if not active:
		return ""
	match stage:
		"briefing":
			return "【烟山初行】按 [F] 与营地陈向导接取任务"
		"skirmish":
			if active_scout_idx >= 0 and active_scout_idx < scouts.size():
				var raw_zh := str(scouts[active_scout_idx].word.get("chinese", ""))
				var short_zh := raw_zh.split("；")[0].split(";")[0].split("，")[0].split(",")[0].strip_edges()
				return "【序章 1/3】射中英文词盾：%s" % short_zh
			return "【序章 1/3】过南桥清除 3 名雾隐斥候"
		"beacon_clue":
			return "【序章 2/3】登望稻亭按 [F] 查验失联信标"
		"return_camp":
			return "【序章 3/3】带信标返营按 [F] 交付陈向导"
		_:
			return "烟山初行 · 单人序章"

func current_subhint_text() -> String:
	if not active:
		return ""
	match stage:
		"skirmish":
			return "沿暖金路灯过南桥上东岭 · 备弹无限 · [X] 听读音 · [J] 查任务与英文线索"
		"beacon_clue":
			return "望稻亭位于东岭高台 · 登石阶即可俯瞰稻田并找到发光信标匣 · [J] 查任务"
		"return_camp":
			return "已获取「烟霞古洞」异常日志 · 沿原路回山脚营地找陈向导交付 · [J] 查任务"
		_:
			return "[F] 与陈向导对话 · [J] 打开任务记录"

func interaction_prompt_for(player_pos: Vector3) -> Dictionary:
	if not active:
		return {}
	if is_instance_valid(npc_node) and player_pos.distance_to(npc_node.position) < 3.6:
		var lbl := "[F] 向陈向导交付失联信标（完成序章）" if stage == "return_camp" else "[F] 与陈向导对话 / 重温线索"
		return {"kind": "npc", "prompt": lbl}
	if is_instance_valid(beacon_node) and player_pos.distance_to(beacon_node.position) < 3.8:
		var blbl := "[F] 查验望稻亭失联信标与越窑青瓷线索" if not clue_solved else "[F] 重看望稻亭信标记录"
		return {"kind": "beacon", "prompt": blbl}
	return {}

func try_interact(player_pos: Vector3) -> bool:
	var info := interaction_prompt_for(player_pos)
	if info.is_empty():
		return false
	if info.kind == "npc":
		open_npc_dialogue()
		return true
	if info.kind == "beacon":
		open_beacon_clue()
		return true
	return false

func update(delta: float):
	if not active:
		return
	pulse_clock += delta
	if is_instance_valid(beacon_pulse_mesh):
		var s := 1.0 + sin(pulse_clock * 4.5) * 0.16
		beacon_pulse_mesh.scale = Vector3.ONE * s
	if is_instance_valid(npc_beacon_ring):
		npc_beacon_ring.visible = stage in ["briefing", "return_camp"]
		var rs := 1.0 + sin(pulse_clock * 3.6) * 0.08
		npc_beacon_ring.scale = Vector3(rs, 1.0, rs)
	if is_instance_valid(game.player):
		var p_xz := Vector3(game.player.position.x, 0.0, game.player.position.z)
		for sc in scouts:
			if sc.defeated or not is_instance_valid(sc.node):
				continue
			var n_xz := Vector3(sc.node.position.x, 0.0, sc.node.position.z)
			var d := p_xz - n_xz
			if d.length() > 0.4:
				sc.node.rotation.y = atan2(d.x, d.z)
