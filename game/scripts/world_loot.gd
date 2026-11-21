extends Node3D
## v0.6.3 Dynamic Match Looting Layer:
## 1. Loose World Loot Spawns ('露天刷货点') — randomized each match with visible 3D relics & rarity aura rings
## 2. Tactile Bird Nests & Karst Crevices ('掏鸟窝 / 探石缝') — 0.9s magnifying-glass search with miracle '出大红' odds
## 3. Overcharged Supply Caches ('高能异动箱') — random field boxes supercharged with golden beacons each run
## 4. Squad Wave Drop Pouches ('词兵战术战利品包') — dropped on wave clear, upgraded by flawless English accuracy

const LootUI = preload("res://scripts/loot_ui.gd")

const LOOSE_SPOTS = [
	{"id": "loose_camp_tent", "title": "营地帐篷行军案", "at": Vector3(-5.4, 0.0, 13.2), "y_off": 0.44, "pedestal": true, "high": false},
	{"id": "loose_shrine", "title": "土地石龛青石案", "at": Vector3(13.2, 0.0, -15.0), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_wangdao", "title": "望稻亭观景石几", "at": Vector3(56.2, 0.0, 30.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_poem", "title": "诗碑亭石栏旁", "at": Vector3(-37.0, 0.0, -47.5), "y_off": 0.44, "pedestal": true, "high": false},
	{"id": "loose_forest", "title": "古道掩体补给台", "at": Vector3(-11.5, 0.0, -52.0), "y_off": 0.44, "pedestal": true, "high": false},
	{"id": "loose_radio", "title": "东岭电台检修台", "at": Vector3(49.5, 0.0, -93.0), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_maze", "title": "竹石阵秘境石台", "at": Vector3(-77.0, 0.0, -88.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_cave", "title": "烟霞古洞东壁石案", "at": Vector3(-69.2, 0.0, -97.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_shelter", "title": "竹林木棚工具台", "at": Vector3(20.0, 0.0, -151.0), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_airdrop", "title": "北脊信标物资垫", "at": Vector3(52.5, 0.0, -172.0), "y_off": 0.44, "pedestal": true, "high": true}
]

const NEST_SPOTS = [
	# 14 ultra-hidden bush, azalea, bridge-corner, reed, maze & shadow stashes across Great Yanshan (180x240m)
	{"id": "nest_south_willow", "title": "溪畔垂柳树丫鸟窝", "at": Vector3(13.5, 0.0, 12.8), "kind": "nest"},
	{"id": "nest_camphor", "title": "百年古樟背根秘洞", "at": Vector3(17.8, 0.0, -16.8), "kind": "nest"},
	{"id": "nest_azalea", "title": "西岭映山红花丛藏点", "at": Vector3(-31.0, 0.0, -28.0), "kind": "nest"},
	{"id": "nest_arch_bridge", "title": "三孔青石桥南墩桥角", "at": Vector3(28.5, 0.0, -24.8), "kind": "crevice"},
	{"id": "nest_karst_cleft", "title": "竹石阵太湖石秘缝", "at": Vector3(-75.6, 0.0, -77.2), "kind": "crevice"},
	{"id": "nest_se_bamboo", "title": "东南竹海翠竹深窝", "at": Vector3(61.5, 0.0, -124.0), "kind": "nest"},
	{"id": "nest_south_bridge_corner", "title": "南溪木桥东墩芦苇角", "at": Vector3(29.8, 0.0, 14.0), "kind": "nest"},
	{"id": "nest_paddy_bank", "title": "望稻梯田草埂暗窝", "at": Vector3(48.0, 0.0, 24.0), "kind": "nest"},
	{"id": "nest_poem_steps", "title": "诗碑亭石阶灌木缝", "at": Vector3(-44.8, 0.0, -44.0), "kind": "crevice"},
	{"id": "nest_west_thicket", "title": "西岭红花坡矮灌丛", "at": Vector3(-51.0, 0.0, -19.0), "kind": "nest"},
	{"id": "nest_mid_bridge_reeds", "title": "中溪桥头鹅卵石暗缝", "at": Vector3(24.0, 0.0, -76.5), "kind": "crevice"},
	{"id": "nest_maze_deadend", "title": "竹石迷阵西壁石隙", "at": Vector3(-78.8, 0.0, -86.6), "kind": "crevice"},
	{"id": "nest_cave_shadow", "title": "烟霞古洞寒潭石影", "at": Vector3(-74.0, 0.0, -97.8), "kind": "crevice"},
	{"id": "nest_north_bridge_bamboo", "title": "北溪桥畔竹根暗囊", "at": Vector3(38.2, 0.0, -161.5), "kind": "nest"}
]

var game
var rng := RandomNumberGenerator.new()
var loose_nodes: Array = []
var nest_nodes: Array = []
var drop_nodes: Array = []
var overcharged_halos: Array = []
var drop_case_mesh: Mesh = null
var spin_clock: float = 0.0

func setup(g):
	game = g
	rng.randomize()
	_build_static_anchors()

func interactable_nodes() -> Array:
	return loose_nodes + nest_nodes + drop_nodes

func _build_static_anchors():
	var props_glb := "res://assets/slice/v064_world_props.glb"
	var ped_mesh: Mesh = game.landscape._extract_mesh(props_glb, "prop_stone_pedestal")
	var nest_mesh: Mesh = game.landscape._extract_mesh(props_glb, "prop_bird_nest")
	var crevice_mesh: Mesh = game.landscape._extract_mesh(props_glb, "prop_karst_crevice")
	drop_case_mesh = game.landscape._extract_mesh(props_glb, "prop_squad_drop_case")

	# 1) Sculpted Jiangnan Octagonal Sumidero Stone Pedestals (top y = 0.44m)
	for idx_l in LOOSE_SPOTS.size():
		var spec: Dictionary = LOOSE_SPOTS[idx_l]
		var root := Node3D.new()
		var gp: Vector3 = game.Layout.on_ground(spec.at)
		if spec.id == "loose_wangdao" and is_instance_valid(game.landscape) and game.landscape.wangdao_deck_pos != Vector3.ZERO:
			gp = Vector3(spec.at.x, game.landscape.wangdao_deck_pos.y, spec.at.z)
		root.position = gp
		root.set_meta("world_loot_kind", "loose")
		root.set_meta("spot_id", spec.id)
		root.set_meta("title", spec.title)
		root.set_meta("high_tier", bool(spec.high))
		add_child(root)

		if bool(spec.pedestal) and ped_mesh != null:
			var stump := MeshInstance3D.new()
			stump.mesh = ped_mesh
			stump.rotation.y = float(idx_l) * 0.785
			stump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(stump)

		var holder := Node3D.new()
		holder.name = "RelicHolder"
		holder.position.y = float(spec.y_off)
		root.add_child(holder)
		loose_nodes.append(root)

	# 2) Sculpted Woven-Twig Bird Nests & Perforated Taihu Karst Rock Crevices ('掏鸟窝')
	var glint_mat := StandardMaterial3D.new()
	glint_mat.albedo_color = Color("ffe082")
	glint_mat.emission_enabled = true
	glint_mat.emission = Color("ffd166")
	glint_mat.emission_energy_multiplier = 1.25

	for idx_n in NEST_SPOTS.size():
		var nspec: Dictionary = NEST_SPOTS[idx_n]
		var nroot := Node3D.new()
		nroot.position = game.Layout.on_ground(nspec.at)
		nroot.set_meta("world_loot_kind", "nest")
		nroot.set_meta("nest_id", nspec.id)
		nroot.set_meta("title", nspec.title)
		add_child(nroot)

		var prop_mi := MeshInstance3D.new()
		prop_mi.mesh = nest_mesh if str(nspec.kind) == "nest" else crevice_mesh
		prop_mi.rotation.y = float(idx_n) * 1.15
		prop_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nroot.add_child(prop_mi)

		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.024
		sm.height = 0.048
		spark.mesh = sm
		spark.name = "Glint"
		spark.position = Vector3(0.0, 0.30, 0.0)
		spark.material_override = glint_mat
		spark.visibility_range_end = 5.2
		nroot.add_child(spark)
		nest_nodes.append(nroot)

func reset_for_run():
	# Clear previous enemy drop pouches
	for d in drop_nodes:
		if is_instance_valid(d):
			d.queue_free()
	drop_nodes.clear()

	# Clear previous overcharged halos on supply boxes
	for h in overcharged_halos:
		if is_instance_valid(h):
			h.queue_free()
	overcharged_halos.clear()
	for p in game.pickup_nodes:
		if is_instance_valid(p) and p.has_meta("overcharged"):
			p.remove_meta("overcharged")

	# v0.8.1 #15: Practice Range ('自由靶场') is pure shooting & vocabulary training — hide all world loot!
	if not game.rules.can_loot():
		for node in loose_nodes:
			var holder: Node3D = node.get_node("RelicHolder")
			for ch in holder.get_children():
				ch.queue_free()
			if node.has_meta("loot_item"):
				node.remove_meta("loot_item")
			node.visible = false
		for raw_n in nest_nodes:
			(raw_n as Node3D).visible = false
		game.cached_interactables.clear()
		return

	# 1) Roll randomized Loose World Spawns (7 active in Normal, 8 in Confidential!)
	var indices := []
	for i in loose_nodes.size():
		indices.append(i)
	# Always activate index 0 (Camp Tent Table) so players immediately see open-world 3D loot!
	var rest := indices.slice(1)
	rest.shuffle()
	var active_target: int = 8 if game.rules.is_confidential() else 7
	var chosen := {0: true}
	for idx in rest:
		if chosen.size() >= active_target:
			break
		chosen[idx] = true

	for i in loose_nodes.size():
		var node: Node3D = loose_nodes[i]
		var holder: Node3D = node.get_node("RelicHolder")
		for ch in holder.get_children():
			ch.queue_free()
		for mk in ["loot_item", "pending_items", "opened_remaining", "scanned"]:
			if node.has_meta(mk):
				node.remove_meta(mk)
		if chosen.has(i):
			var item: Dictionary = game.rules.roll_world_loose_item(bool(node.get_meta("high_tier", false)))
			node.set_meta("loot_item", item)
			_populate_loose_visual(holder, item)
			node.visible = true
		else:
			node.visible = false

	# 2) Reset all 14 Bird Nests & Crevices (each rolls fresh when searched!)
	for raw_n in nest_nodes:
		var nnode: Node3D = raw_n
		for mk in ["searched", "unclaimed_item", "pending_items", "opened_remaining", "scanned"]:
			if nnode.has_meta(mk):
				nnode.remove_meta(mk)
		var glint: Node3D = nnode.get_node_or_null("Glint")
		if is_instance_valid(glint):
			glint.visible = true
		nnode.visible = true

	# 3) Secretly tag 2 (Normal) or 3 (Confidential) lucky blind-box supply caches (v0.8.0 #11: ZERO external spoiler halos!)
	var candidate_supplies := []
	for idx in range(2, game.pickup_nodes.size()):
		var pnode: Node3D = game.pickup_nodes[idx]
		if is_instance_valid(pnode) and not pnode.has_meta("tactical_item"):
			candidate_supplies.append(pnode)
	candidate_supplies.shuffle()
	var over_count: int = mini(3 if game.rules.is_confidential() else 2, candidate_supplies.size())
	for k in over_count:
		var snode: Node3D = candidate_supplies[k]
		snode.set_meta("overcharged", true)

	game.cached_interactables.clear()

func _populate_loose_visual(holder: Node3D, item: Dictionary):
	var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
	var r_col: Color = game.Rules.RARITY_COLORS[r]

	# Subtle tabletop rim ring only (v0.8.0 #10: NO sky beams, NO open-road Big Gold/Red spoilers!)
	var aura := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.21
	tm.outer_radius = 0.24
	aura.mesh = tm
	aura.position.y = 0.02
	var amat := StandardMaterial3D.new()
	amat.albedo_color = r_col
	amat.emission_enabled = true
	amat.emission = r_col
	amat.emission_energy_multiplier = 0.48
	aura.material_override = amat
	aura.visibility_range_end = 12.0
	holder.add_child(aura)

	var mesh_3d := LootUI.build_world_loot_mesh(item, r, r_col, 1.15)
	mesh_3d.name = "SpinMesh"
	holder.add_child(mesh_3d)

func spawn_squad_drop(world_pos: Vector3, camp_title: String, flawless_wave: bool, is_boss_camp: bool) -> Node3D:
	var gp: Vector3 = game.Layout.on_ground(world_pos)
	var dnode := Node3D.new()
	dnode.position = gp
	dnode.set_meta("world_loot_kind", "squad_drop")
	var quality_tag: String = "精英战术掉落包" if flawless_wave else "词兵战术掉落包"
	dnode.set_meta("title", "%s · %s" % [camp_title, quality_tag])
	dnode.set_meta("flawless", flawless_wave)
	dnode.set_meta("boss_camp", is_boss_camp)
	var rolled: Array = game.rules.roll_squad_drop_items(flawless_wave, is_boss_camp)
	dnode.set_meta("drop_items", rolled)
	add_child(dnode)

	# Uniform tactical teal-mint beacon strip (v0.8.0 #11: blind-box mystery until opened!)
	var strip_col: Color = Color("7ed6b8")

	var body := MeshInstance3D.new()
	if drop_case_mesh != null:
		body.mesh = drop_case_mesh
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.68, 0.32, 0.46)
		body.mesh = bm
		body.position.y = 0.16
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dnode.add_child(body)

	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.62, 0.035, 0.48)
	strip.mesh = sm
	strip.position.y = 0.285
	var st_mat := StandardMaterial3D.new()
	st_mat.albedo_color = strip_col
	st_mat.emission_enabled = true
	st_mat.emission = strip_col
	st_mat.emission_energy_multiplier = 1.25
	strip.material_override = st_mat
	dnode.add_child(strip)

	drop_nodes.append(dnode)
	game.cached_interactables.clear()
	return dnode

func spawn_custom_drop(world_pos: Vector3, title: String, items: Array, high_glow: bool = true) -> Node3D:
	var gp: Vector3 = world_pos
	if gp.y <= 0.05:
		gp = game.Layout.on_ground(world_pos)
	var dnode := Node3D.new()
	dnode.position = gp
	dnode.set_meta("world_loot_kind", "squad_drop")
	dnode.set_meta("title", title)
	dnode.set_meta("flawless", high_glow)
	dnode.set_meta("boss_camp", high_glow)
	dnode.set_meta("drop_items", items.duplicate(true))
	add_child(dnode)

	var strip_col: Color = Color("ffd46e") if high_glow else Color("7ed6b8")
	var body := MeshInstance3D.new()
	if drop_case_mesh != null:
		body.mesh = drop_case_mesh
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.68, 0.32, 0.46)
		body.mesh = bm
		body.position.y = 0.16
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dnode.add_child(body)

	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.62, 0.035, 0.48)
	strip.mesh = sm
	strip.position.y = 0.285
	var st_mat := StandardMaterial3D.new()
	st_mat.albedo_color = strip_col
	st_mat.emission_enabled = true
	st_mat.emission = strip_col
	st_mat.emission_energy_multiplier = 1.45 if high_glow else 1.25
	strip.material_override = st_mat
	dnode.add_child(strip)

	drop_nodes.append(dnode)
	game.cached_interactables.clear()
	return dnode

func prompt_for(node: Node3D) -> String:
	var kind: String = str(node.get_meta("world_loot_kind", ""))
	if kind == "loose":
		var item: Dictionary = node.get_meta("loot_item", {})
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		var r_name: String = game.Rules.RARITY_NAMES[r]
		var spot_title: String = str(node.get_meta("title", "桌面物资"))
		return "[F] 查看拾取【%s】%s · %s（%s）" % [r_name, str(item.get("title", "物资")), str(item.get("en", "")), spot_title]
	elif kind == "nest":
		var n_title: String = str(node.get_meta("title", "隐蔽秘藏"))
		if node.has_meta("pending_items"):
			var rem_n: Array = node.get_meta("pending_items")
			if not rem_n.is_empty():
				return "[F] 搜刮【%s】（已开启·剩余 %d 件）" % [n_title, rem_n.size()]
		return "[F] 🔍 隐秘翻找 · %s" % n_title
	elif kind == "squad_drop":
		var d_title: String = str(node.get_meta("title", "词兵战术掉落包"))
		if node.has_meta("pending_items"):
			var rem_d: Array = node.get_meta("pending_items")
			if not rem_d.is_empty():
				return "[F] 搜刮%s（已开启·剩余 %d 件）" % [d_title, rem_d.size()]
		return "[F] 🔍 搜索%s（免拼写确认拾取）" % d_title
	return "[F] 搜刮物资"

func interact(node: Node3D):
	var kind: String = str(node.get_meta("world_loot_kind", ""))
	if kind == "loose":
		_pickup_loose(node)
	elif kind == "nest":
		if node.has_meta("pending_items"):
			var saved_n: Array = node.get_meta("pending_items")
			if not saved_n.is_empty() and is_instance_valid(game.loot_container_ui):
				game.loot_container_ui.open_container(
					node, "nest", str(node.get_meta("title", "隐蔽秘藏")),
					saved_n, "已翻找的隐蔽秘藏 · 自由选择拾取、存安全箱或留在原处", false
				)
				return
		if not node.has_meta("searched"):
			game.loot_ui.start_quick_search(node, 0.88)
	elif kind == "squad_drop":
		game.cipher_terminal.open_for_drop_pouch(node)

func _pickup_loose(node: Node3D):
	if not node.has_meta("loot_item"):
		return
	var item: Dictionary = node.get_meta("loot_item")
	var spot_title: String = str(node.get_meta("title", "露天散落物资"))
	if is_instance_valid(game.loot_container_ui):
		game.loot_container_ui.open_container(
			node, "loose", spot_title, [item],
			"地面/石案散落物资确认 · 可选择拾取入包、直存安全箱，或离开留在原地", false
		)

func finish_nest_search(node: Node3D):
	if not is_instance_valid(node) or node.has_meta("searched"):
		return
	node.set_meta("searched", true)
	var item: Dictionary = game.rules.roll_bird_nest_item()
	var n_title: String = str(node.get_meta("title", "树丫鸟窝"))
	node.set_meta("pending_items", [item])
	node.set_meta("opened_remaining", true)
	if is_instance_valid(game.loot_container_ui):
		game.loot_container_ui.open_container(
			node, "nest", n_title, [item],
			"隐蔽秘藏翻找完成！自由选择拾取入包、存安全箱或留在原处", false
		)

func update(delta: float):
	if not is_instance_valid(game.player):
		return
	spin_clock += delta
	var ppos: Vector3 = game.player.position
	for raw_l in loose_nodes:
		var node: Node3D = raw_l
		if not node.visible or ppos.distance_squared_to(node.position) > 1225.0:
			continue
		var holder: Node3D = node.get_node_or_null("RelicHolder")
		if is_instance_valid(holder):
			var spin_m: Node3D = holder.get_node_or_null("SpinMesh")
			if is_instance_valid(spin_m):
				spin_m.rotation.y = spin_clock * 1.1
				spin_m.position.y = sin(spin_clock * 2.6 + node.position.x) * 0.025
