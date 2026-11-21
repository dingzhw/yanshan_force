extends Node3D
## Optional cross-subject & v0.5.4 field intel / radio / airdrop discoveries.
## Reading freezes timer & combat, randomizes questions per run, and shuffles option buttons.

const TacticalProps = preload("res://scripts/tactical_props.gd")
const INTEL_IDS = ["intel_container", "intel_cleft", "intel_cave", "intel_roof"]
const SECRET_EVENT_IDS = ["intel_container", "intel_cleft", "intel_cave", "intel_roof", "recon_radio", "airdrop_beacon"]
const HERITAGE_IDS = ["cliff_inscription", "cave_mural", "cave_hearth"]

var game
var nodes = []
var node_labels = {}
var states = {}
var failed = {}
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
var gate_plaque: Label3D
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
	_mark("cliff_inscription", Vector3(-36.45, 0, -50.0), "摩崖石刻《竹石清音》", Color("e8b878"))
	_mark("cave_mural", Vector3(-44.05, 0, -61.15), "先民岩凿壁画《烟山耕读》", Color("8de8c0"))
	_mark("cave_hearth", Vector3(-41.05, 0, -66.35), "寒潭茶灶与古竹简", Color("ffd15c"))
	_build_shortcut_stockade()
	_ui()
	reset()

func _build_shortcut_stockade():
	## v0.8.1 FB-6: Valley-spanning fortified timber palisade wall (x = 1.6..19.6 at z = -62)
	## anchored to the west pass ridge & east creek embankment, with central lockable wooden gate at x = 10!
	var stockade_root := Node3D.new()
	stockade_root.name = "MathShortcutStockade"
	add_child(stockade_root)

	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color("5e4832")
	log_mat.albedo_texture = bark_tex
	log_mat.uv1_scale = Vector3(1.0, 2.2, 1.0)
	log_mat.roughness = 0.90
	log_mat.metallic_specular = 0.06

	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("765c40")
	rail_mat.albedo_texture = bark_tex
	rail_mat.uv1_scale = Vector3(2.4, 0.8, 1.0)
	rail_mat.roughness = 0.86

	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color("2a3034")
	iron_mat.metallic = 0.62
	iron_mat.roughness = 0.48

	var center: Vector3 = game.Layout.on_ground(Vector3(10.0, 0.0, -62.0))
	var fence_z := -62.0

	# Central heavy gateway posts + overhead timber lintel framing the lockable door (exact gate center at x = 10.0!)
	for gx in [-1.52, 1.52]:
		var gpos := Vector3(center.x + gx, float(game.Layout.height(center.x + gx, fence_z)) + 1.38, fence_z)
		var gpost: MeshInstance3D = game._mesh_box(stockade_root, gpos, Vector3(0.28, 3.05, 0.28), Color.WHITE, true)
		gpost.material_override = log_mat
	var lintel_pos := Vector3(center.x, center.y + 2.72, fence_z)
	var lintel: MeshInstance3D = game._mesh_box(stockade_root, lintel_pos, Vector3(3.45, 0.24, 0.30), Color.WHITE, false)
	lintel.material_override = log_mat

	# Lockable heavy timber double-framed wooden gate (pivot identical to center + (-1.4, 0, 0) for raycast compatibility!)
	gate = Node3D.new()
	gate.name = "MathShortcutGate"
	gate.position = center + Vector3(-1.4, 0.0, 0.0)
	add_child(gate)
	# Solid gate collision leaf (height 2.20m) + wooden plank visuals + diagonal brace & iron hinges
	var gate_leaf_col := BoxShape3D.new()
	gate_leaf_col.size = Vector3(2.82, 2.25, 0.22)
	game.Props.shape_body(gate, gate_leaf_col, Vector3(1.40, 1.12, 0.0))
	for pi in 8:
		var px := 0.18 + float(pi) * 0.35
		var plank: MeshInstance3D = game._mesh_box(gate, Vector3(px, 1.12, 0.0), Vector3(0.31, 2.18, 0.12), Color.WHITE, false)
		plank.material_override = rail_mat
	for bar_y in [0.52, 1.16, 1.80]:
		var bar: MeshInstance3D = game._mesh_box(gate, Vector3(1.40, bar_y, 0.09), Vector3(2.80, 0.18, 0.08), Color.WHITE, false)
		bar.material_override = log_mat
		var bar_b: MeshInstance3D = game._mesh_box(gate, Vector3(1.40, bar_y, -0.09), Vector3(2.80, 0.18, 0.08), Color.WHITE, false)
		bar_b.material_override = log_mat
	var diag_brace: MeshInstance3D = game._mesh_box(gate, Vector3(1.40, 1.16, 0.12), Vector3(2.85, 0.14, 0.06), Color.WHITE, false)
	diag_brace.rotation.z = 0.42
	diag_brace.material_override = log_mat
	for hy in [0.52, 1.80]:
		var strap: MeshInstance3D = game._mesh_box(gate, Vector3(0.34, hy, 0.14), Vector3(0.68, 0.10, 0.04), Color.WHITE, false)
		strap.material_override = iron_mat
	var lock_plate: MeshInstance3D = game._mesh_box(gate, Vector3(2.58, 1.16, 0.14), Vector3(0.24, 0.28, 0.08), Color.WHITE, false)
	lock_plate.material_override = iron_mat

	gate_plaque = game._label3d(stockade_root, "数学近道木门 · 请在西侧巡护站解题解锁", Vector3(center.x, center.y + 3.16, fence_z + 0.18), 26, game.GOLD)
	gate_plaque.pixel_size = 0.0046
	gate_plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	gate_plaque.visibility_range_end = 24.0

	# Solid impenetrable palisade wings spanning entire pass: West [1.6..8.45] & East [11.55..19.4]
	var wings := [
		[1.60, 8.45],
		[11.55, 19.40]
	]
	for wing in wings:
		var x0: float = wing[0]
		var x1: float = wing[1]
		var span := x1 - x0
		var segs := maxi(2, int(ceilf(span / 2.2)))
		for s_i in segs:
			var sx0 := lerpf(x0, x1, float(s_i) / float(segs))
			var sx1 := lerpf(x0, x1, float(s_i + 1) / float(segs))
			var smx := (sx0 + sx1) * 0.5
			var slen := sx1 - sx0
			var gy0 := float(game.Layout.height(sx0, fence_z))
			var gy1 := float(game.Layout.height(sx1, fence_z))
			var gmid := (gy0 + gy1) * 0.5
			var slope_ang := atan2(gy1 - gy0, slen)
			# Solid tall invisible collider (2.85m high, sunk 0.45m below ground so ZERO sneaking under or jumping over!)
			var w_shp := BoxShape3D.new()
			w_shp.size = Vector3(slen + 0.22, 3.25, 0.48)
			game.Props.shape_body(stockade_root, w_shp, Vector3(smx, gmid + 1.25, fence_z)).add_to_group("solid_props")
			# Horizontal cross-beams binding the logs
			for ry in [0.75, 1.95]:
				var rail: MeshInstance3D = game._mesh_box(stockade_root, Vector3(smx, gmid + ry, fence_z + 0.14), Vector3(slen + 0.12, 0.16, 0.11), Color.WHITE, false)
				rail.rotation.z = slope_ang
				rail.material_override = rail_mat
				var rail2: MeshInstance3D = game._mesh_box(stockade_root, Vector3(smx, gmid + ry, fence_z - 0.14), Vector3(slen + 0.12, 0.16, 0.11), Color.WHITE, false)
				rail2.rotation.z = slope_ang
				rail2.material_override = rail_mat
		# Individual sharpened timber palisade stakes following exact terrain elevation
		var stake_count := maxi(4, int(roundf(span / 0.36)))
		for k in stake_count + 1:
			var px := lerpf(x0, x1, float(k) / float(stake_count))
			var py := float(game.Layout.height(px, fence_z))
			var h_var := 2.48 + (0.18 if k % 3 == 0 else (-0.08 if k % 2 == 0 else 0.06))
			var log_mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.085
			cyl.bottom_radius = 0.125
			cyl.height = h_var + 0.45
			cyl.radial_segments = 7
			log_mi.mesh = cyl
			log_mi.position = Vector3(px, py + (h_var - 0.45) * 0.5, fence_z)
			log_mi.material_override = log_mat
			stockade_root.add_child(log_mi)
			var tip_mi := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.012
			cone.bottom_radius = 0.088
			cone.height = 0.28
			cone.radial_segments = 7
			tip_mi.mesh = cone
			tip_mi.position = Vector3(px, py + h_var + 0.12, fence_z)
			tip_mi.material_override = rail_mat
			stockade_root.add_child(tip_mi)

	# Anchor boulders pinning both ends of the stockade into West hillside & East creek bank!
	if is_instance_valid(game.landscape) and game.landscape.has_method("rock"):
		game.landscape.rock(Vector3(1.15, 0.0, fence_z - 0.15), 2.85, 1)
		game.landscape.rock(Vector3(19.75, 0.0, fence_z + 0.10), 2.95, 3)

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
	elif id in HERITAGE_IDS:
		var h_ring := MeshInstance3D.new()
		var h_torus := TorusMesh.new()
		h_torus.inner_radius = 0.30
		h_torus.outer_radius = 0.38
		h_torus.rings = 18
		h_torus.ring_segments = 6
		h_ring.mesh = h_torus
		h_ring.position = Vector3(0.0, 0.05, 0.0)
		h_ring.material_override = game._material(color, true)
		node.add_child(h_ring)
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
		var text = game._label3d(node, "巡护记录\nnext to" if id == "clue" else "近道机关\nF 解锁木门", Vector3(0, 1.05, 0.13), 26, Color("223428"))
		text.pixel_size = 0.0038
		text.outline_size = 0
		text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var prompt = game._label3d(node, label + " · [F]", Vector3(0, 2.15, 0), 28, game.GOLD)
	if id == "poem":
		prompt.position = Vector3(0, 2.66, 1.56)
		prompt.pixel_size = 0.0040
		prompt.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		prompt.text = "烟山诗碑亭 · 按 [F] 研读"
	elif id == "cliff_inscription":
		prompt.position = Vector3(0.82, 2.74, 0.0)
		prompt.pixel_size = 0.0038
		prompt.text = "摩崖石刻《竹石清音》 · [F]"
	elif id == "cave_mural":
		prompt.position = Vector3(-0.55, 2.68, 0.0)
		prompt.pixel_size = 0.0038
		prompt.text = "先民岩凿壁画《烟山耕读》 · [F]"
	elif id == "cave_hearth":
		prompt.position = Vector3(0.0, 1.68, -0.82)
		prompt.pixel_size = 0.0038
		prompt.text = "寒潭茶灶与先民竹简 · [F]"
	prompt.visibility_range_end = 15
	node_labels[id] = {"label": prompt, "base_text": prompt.text, "base_color": game.GOLD}
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
	explanation = game._text(overlay, "", Vector2(275, 430), Vector2(730, 112), 16, game.GOLD)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.clip_text = true
	source = game._text(overlay, "", Vector2(275, 548), Vector2(730, 38), 13, Color("a7b8a2"))
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

func is_locked_out(id: String) -> bool:
	return bool(failed.get(id, false))

func reset():
	states = {"clue": false, "english": false, "math": false, "poem": false, "math_claimed": false, "poem_claimed": false}
	failed = {}
	for sid in SECRET_EVENT_IDS:
		states[sid] = false
		states[sid + "_claimed"] = false
	for hid in HERITAGE_IDS:
		states[hid] = false
		states[hid + "_claimed"] = false
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
	var hpools: Dictionary = data.get("heritage_pools", {})
	for hid in HERITAGE_IDS:
		if hpools.has(hid):
			_prepare_item(hid, hpools[hid])
	if is_instance_valid(overlay):
		overlay.hide()
	game.Props.set_enabled(gate, true)
	gate.rotation = Vector3.ZERO
	if is_instance_valid(gate_plaque):
		gate_plaque.visible = true
	for n in nodes:
		game.Props.set_enabled(n, true)
	for lid in node_labels:
		var info: Dictionary = node_labels[lid]
		var lbl: Label3D = info.label
		if is_instance_valid(lbl):
			lbl.text = str(info.base_text)
			lbl.modulate = info.base_color

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
		elif not game.rules.can_loot():
			states.english = true
			game.Props.set_enabled(node, false)
			game.play_sfx("cipher_unlock", -11)
			game.speak_english("next to")
			game._notice("读懂 next to（在……旁边）！自由靶场仅纯练词不入包物资，实战中可领稀有无线电台！", game.MINT)
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
		explanation.text = "提示：next to = 在……旁边。找到封存箱按 [F] 即可领取稀有物资！"
		game.speak_english("next to")
	else:
		var item = current_items[id]
		var opts = current_options[id]
		var expected_idx = answer_button_index(id)
		title.text = item.title
		body.text = item.question
		source.text = item.source
		var locked_now := is_locked_out(id)
		for i in 3:
			buttons[i].show()
			buttons[i].text = opts[i]
			buttons[i].disabled = locked_now
		if not locked_now:
			buttons[0].grab_focus()
		if item.has("tts"):
			game.speak_english(str(item.tts))
		if locked_now:
			explanation.text = "✕ 本局该题已答错锁死（不可重试，下局刷新）。\n正确答案：%s\n解析：%s" % [opts[expected_idx], item.explanation]
		elif states.get(id, false):
			_reward(id)

func choose(index: int):
	if not busy or active_id not in current_items:
		return
	if bool(states.get(active_id, false)) or is_locked_out(active_id):
		return
	var item = current_items[active_id]
	var expected_idx = answer_button_index(active_id)
	if index != expected_idx:
		# v0.8.1 FB-5: Single-attempt per run! Wrong answer immediately locks this node for the rest of the run.
		failed[active_id] = true
		for b in buttons:
			b.disabled = true
		game.play_sfx("hit_wrong", -13)
		if item.has("tts"):
			game.speak_english(str(item.tts))
		var ans_txt: String = str(current_options[active_id][expected_idx])
		explanation.text = "✕ 回答错误！本局该线索已锁死（不可重试，下局刷新）。\n正确答案：%s\n解析：%s" % [ans_txt, item.explanation]
		if node_labels.has(active_id):
			var info: Dictionary = node_labels[active_id]
			var lbl: Label3D = info.label
			if is_instance_valid(lbl):
				lbl.text = str(item.title) + " · [本局已锁]"
				lbl.modulate = Color("ff8c7a")
		return
	var first_solve := not bool(states.get(active_id, false))
	states[active_id] = true
	if active_id == "math":
		gate.rotation.y = -PI / 2
		if is_instance_valid(gate_plaque):
			gate_plaque.visible = false
		game.play_sfx("cipher_unlock", -11)
	elif first_solve and active_id in HERITAGE_IDS:
		var h_pts := int(item.get("reward_score", 30))
		game.rules.score += h_pts
		var hrk := str(item.get("reveal_key", ""))
		if hrk != "":
			revealed_secrets[hrk] = true
		if active_id == "cave_hearth" and is_instance_valid(game.combat):
			game.combat.heal(20, 15)
			game.play_sfx("heal_shield", -10)
			game._notice("品饮寒潭山茶 · 生命+20 护盾+15 · 烟山秘史 +%d 分！" % h_pts, game.GOLD)
		else:
			game.play_sfx("cipher_unlock", -10)
			game._notice("品读烟山古迹成功！获得 +%d 撤离积分" % h_pts, game.MINT)
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
		if not game.rules.can_loot():
			states[key] = true
			suffix = "自由靶场模式仅作纯学习练习（不入包物资），实战行动中可领取【%s】%s！" % [game.Rules.RARITY_NAMES[rarity], item.reward_title]
		elif game.rules.add_loot(item.reward_title, int(item.reward_value), rarity):
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

func heritage_completed() -> int:
	var n := 0
	for hid in HERITAGE_IDS:
		if bool(states.get(hid, false)):
			n += 1
	return n

func is_secret_revealed(secret_key: String) -> bool:
	if secret_key == "":
		return true
	return radar_scan_active or bool(revealed_secrets.get(secret_key, false))

func status_text() -> String:
	return "探%d/3·秘%d/6·迹%d/3" % [completed(), secrets_completed(), heritage_completed()]
