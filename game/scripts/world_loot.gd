extends Node3D
## v0.6.3 Dynamic Match Looting Layer:
## 1. Loose World Loot Spawns ('露天刷货点') — randomized each match with visible 3D relics & rarity aura rings
## 2. Tactile Bird Nests & Karst Crevices ('掏鸟窝 / 探石缝') — 0.9s magnifying-glass search with miracle '出大红' odds
## 3. Overcharged Supply Caches ('高能异动箱') — random field boxes supercharged with golden beacons each run
## 4. Squad Wave Drop Pouches ('词兵战术战利品包') — dropped on wave clear, upgraded by flawless English accuracy

const LootUI = preload("res://scripts/loot_ui.gd")

const LOOSE_SPOTS = [
	{"id": "loose_camp_tent", "title": "营地帐篷行军案", "at": Vector3(-5.2, 0.0, 3.8), "y_off": 0.44, "pedestal": true, "high": false},
	{"id": "loose_shrine", "title": "土地石龛青石案", "at": Vector3(7.4, 0.0, -16.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_wangdao", "title": "望稻亭观景石几", "at": Vector3(35.8, 0.0, 23.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_poem", "title": "诗碑亭石栏旁", "at": Vector3(-23.2, 0.0, -30.5), "y_off": 0.44, "pedestal": true, "high": false},
	{"id": "loose_forest", "title": "古道掩体补给台", "at": Vector3(-8.4, 0.0, -35.8), "y_off": 0.44, "pedestal": true, "high": false},
	{"id": "loose_radio", "title": "东岭电台检修台", "at": Vector3(22.8, 0.0, -43.5), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_maze", "title": "竹石阵秘境石台", "at": Vector3(-46.6, 0.0, -52.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_cave", "title": "烟霞古洞东壁石案", "at": Vector3(-38.8, 0.0, -61.2), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_shelter", "title": "竹林木棚工具台", "at": Vector3(10.2, 0.0, -81.8), "y_off": 0.44, "pedestal": true, "high": true},
	{"id": "loose_airdrop", "title": "北脊信标物资垫", "at": Vector3(18.6, 0.0, -97.8), "y_off": 0.44, "pedestal": true, "high": true}
]

const NEST_SPOTS = [
	# Original 6 + 8 new ultra-hidden bush, azalea, bridge-corner, reed, maze & shadow stashes (14 total!)
	{"id": "nest_south_willow", "title": "溪畔垂柳树丫鸟窝", "at": Vector3(8.6, 0.0, 3.6), "kind": "nest"},
	{"id": "nest_camphor", "title": "百年古樟背根秘洞", "at": Vector3(11.8, 0.0, -17.9), "kind": "nest"},
	{"id": "nest_azalea", "title": "西岭映山红花丛藏点", "at": Vector3(-20.4, 0.0, -22.2), "kind": "nest"},
	{"id": "nest_arch_bridge", "title": "青石拱桥南墩桥角", "at": Vector3(19.6, 0.0, -21.8), "kind": "crevice"},
	{"id": "nest_karst_cleft", "title": "竹石阵太湖石秘缝", "at": Vector3(-45.2, 0.0, -41.2), "kind": "crevice"},
	{"id": "nest_se_bamboo", "title": "东南竹海翠竹深窝", "at": Vector3(28.0, 0.0, -81.8), "kind": "nest"},
	{"id": "nest_south_bridge_corner", "title": "南溪木桥东墩芦苇角", "at": Vector3(21.4, 0.0, 5.4), "kind": "nest"},
	{"id": "nest_paddy_bank", "title": "望稻梯田草埂暗窝", "at": Vector3(29.8, 0.0, 17.6), "kind": "nest"},
	{"id": "nest_poem_steps", "title": "诗碑亭石阶灌木缝", "at": Vector3(-30.4, 0.0, -27.2), "kind": "crevice"},
	{"id": "nest_west_thicket", "title": "西岭红花坡矮灌丛", "at": Vector3(-33.6, 0.0, -14.8), "kind": "nest"},
	{"id": "nest_mid_bridge_reeds", "title": "中溪桥头鹅卵石暗缝", "at": Vector3(15.6, 0.0, -48.2), "kind": "crevice"},
	{"id": "nest_maze_deadend", "title": "竹石迷阵西壁石隙", "at": Vector3(-48.4, 0.0, -50.6), "kind": "crevice"},
	{"id": "nest_cave_shadow", "title": "烟霞古洞寒潭石影", "at": Vector3(-43.6, 0.0, -61.8), "kind": "crevice"},
	{"id": "nest_north_bridge_bamboo", "title": "北溪桥畔竹根暗囊", "at": Vector3(26.8, 0.0, -71.8), "kind": "nest"}
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

	# 1) Roll randomized Loose World Spawns (7 active in Normal/Practice, 8 in Confidential!)
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
		if node.has_meta("loot_item"):
			node.remove_meta("loot_item")
		if chosen.has(i):
			var item: Dictionary = game.rules.roll_world_loose_item(bool(node.get_meta("high_tier", false)))
			node.set_meta("loot_item", item)
			_populate_loose_visual(holder, item)
			node.visible = true
		else:
			node.visible = false

	# 2) Reset all 6 Bird Nests & Crevices (each rolls fresh when searched!)
	for raw_n in nest_nodes:
		var nnode: Node3D = raw_n
		if nnode.has_meta("searched"):
			nnode.remove_meta("searched")
		if nnode.has_meta("unclaimed_item"):
			nnode.remove_meta("unclaimed_item")
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

func prompt_for(node: Node3D) -> String:
	var kind: String = str(node.get_meta("world_loot_kind", ""))
	if kind == "loose":
		var item: Dictionary = node.get_meta("loot_item", {})
		var r: int = clampi(int(item.get("rarity", 1)), 1, 7)
		var r_name: String = game.Rules.RARITY_NAMES[r]
		var spot_title: String = str(node.get_meta("title", "桌面物资"))
		if game.rules.bag.size() >= game.rules.capacity():
			return "[F] 背包已满·置换拾取【%s】%s（%s）" % [r_name, str(item.get("title", "物资")), spot_title]
		return "[F] 直接摸取【%s】%s · %s" % [r_name, str(item.get("title", "物资")), str(item.get("en", ""))]
	elif kind == "nest":
		var n_title: String = str(node.get_meta("title", "隐蔽秘藏"))
		if node.has_meta("unclaimed_item"):
			var u_it: Dictionary = node.get_meta("unclaimed_item")
			var ur: int = clampi(int(u_it.get("rarity", 1)), 1, 7)
			return "[F] 置换领取【%s】%s" % [game.Rules.RARITY_NAMES[ur], str(u_it.get("title", ""))]
		return "[F] 🔍 隐秘翻找 · %s" % n_title
	elif kind == "squad_drop":
		var d_title: String = str(node.get_meta("title", "词兵战术掉落包"))
		return "[F] 🔍 搜索%s（免拼写鉴定战利品）" % d_title
	return "[F] 搜刮物资"

func interact(node: Node3D):
	var kind: String = str(node.get_meta("world_loot_kind", ""))
	if kind == "loose":
		_pickup_loose(node)
	elif kind == "nest":
		if node.has_meta("unclaimed_item"):
			_claim_or_swap_single(node, node.get_meta("unclaimed_item"), str(node.get_meta("title", "隐秘鸟窝")), true)
		elif not node.has_meta("searched"):
			game.loot_ui.start_quick_search(node, 0.88)
	elif kind == "squad_drop":
		game.cipher_terminal.open_for_drop_pouch(node)

func _pickup_loose(node: Node3D):
	if not node.has_meta("loot_item"):
		return
	var item: Dictionary = node.get_meta("loot_item")
	var spot_title: String = str(node.get_meta("title", "露天搜刮"))
	_claim_or_swap_single(node, item, spot_title, false)

func finish_nest_search(node: Node3D):
	if not is_instance_valid(node) or node.has_meta("searched"):
		return
	node.set_meta("searched", true)
	var glint: Node3D = node.get_node_or_null("Glint")
	if is_instance_valid(glint):
		glint.visible = false
	var item: Dictionary = game.rules.roll_bird_nest_item()
	var n_title: String = str(node.get_meta("title", "树丫鸟窝"))
	_claim_or_swap_single(node, item, n_title, true)

func _claim_or_swap_single(node: Node3D, item: Dictionary, source_tag: String, is_nest: bool):
	if game.rules.add_loot_item(item):
		game.speak_english(str(item.get("en", "")))
		game.loot_ui.trigger_loot_toast(item, source_tag)
		if is_nest:
			if node.has_meta("unclaimed_item"):
				node.remove_meta("unclaimed_item")
			node.visible = false
		else:
			node.remove_meta("loot_item")
			node.visible = false
		game.cached_interactables.clear()
		return

	# Bag is full -> if new item is worth more than lowest bag item, swap immediately; otherwise store unclaimed!
	var low_idx: int = game.rules.lowest_bag_index()
	if low_idx >= 0 and int(item.get("value", 0)) > int(game.rules.bag[low_idx].get("value", 0)):
		var removed: Dictionary = game.rules.swap_lowest_loot(item)
		game.speak_english(str(item.get("en", "")))
		game.loot_ui.trigger_loot_toast(item, "%s·置换【%s】" % [source_tag, str(removed.get("title", ""))])
		if is_nest and node.has_meta("unclaimed_item"):
			node.remove_meta("unclaimed_item")
		node.visible = false
		game.cached_interactables.clear()
	else:
		if is_nest:
			node.set_meta("unclaimed_item", item)
		game._notice("背包已满！按 [B] 整理丢弃低值杂物后再拾取【%s（%d币）】" % [str(item.get("title", "")), int(item.get("value", 0))], Color("ffd166"))

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
