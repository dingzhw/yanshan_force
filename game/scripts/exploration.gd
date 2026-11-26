extends Node3D
## Optional cross-subject & v0.5.4 field intel / radio / airdrop discoveries.
## Reading freezes timer & combat, randomizes questions per run, and shuffles option buttons.

const TacticalProps = preload("res://scripts/tactical_props.gd")
const INTEL_IDS = ["intel_container", "intel_cleft", "intel_cave", "intel_roof"]
const SECRET_EVENT_IDS = ["intel_container", "intel_cleft", "intel_cave", "intel_roof", "recon_radio", "airdrop_beacon"]
const HERITAGE_IDS = ["cliff_inscription", "cave_mural", "cave_hearth"]
const AHSARAH_EXPLORE_IDS = ["ahsarah_oasis", "ahsarah_cement", "ahsarah_bazaar", "ahsarah_substation", "ahsarah_fortress", "ahsarah_dam"]
const SPELL_CHALLENGE_IDS = [
	"english", "intel_container", "intel_cleft", "intel_cave", "intel_roof",
	"recon_radio", "airdrop_beacon", "cliff_inscription", "cave_mural", "cave_hearth",
	"dimensional_rift",
	"ahsarah_oasis", "ahsarah_cement", "ahsarah_bazaar", "ahsarah_substation", "ahsarah_fortress", "ahsarah_dam"
]
const DEEP_REWARD_IDS = ["cave_hearth", "cave_mural", "airdrop_beacon", "ahsarah_fortress", "ahsarah_dam"]

const AHSARAH_LORE_SPECS := {
	"ahsarah_oasis": {
		"title": "绿洲前哨 · G.T.I. 跨界频段简报",
		"lore": "【2035 · 阿萨拉战区简报】穿过烟霞古洞次元石壁的游侠，欢迎抵达北非干旱古国阿萨拉！跨国巨企哈夫克集团借修建「零号大坝」垄断水源，与本土武装「阿萨拉卫队」爆发激战。G.T.I. 委托你破译前沿词盾并安全撤离！",
		"reward_score": 25,
		"reward_title": "前哨补给物资"
	},
	"ahsarah_cement": {
		"title": "水泥厂 · 哈夫克征水密令",
		"lore": "【西侧水泥厂档案】零号大坝动工当年，哈夫克工程队将上游河谷强行淹没。大坝守将「赤枭·赛伊德」的家乡村庄与父亲便毁于那场清场，从此这名荒漠猎人之子立誓向所有外来掠夺者复仇。",
		"reward_score": 30,
		"reward_title": "水泥厂工业物资"
	},
	"ahsarah_bazaar": {
		"title": "巴克什拱廊 · 老猎人手记",
		"lore": "【巴克什砂岩集市手记】泛黄日记写着赛伊德最常挂在嘴边的猎人信条：「父亲教导我，好的猎人懂得尊重猎物……但你们，不配！」阿萨拉卫队士兵则总在掩体后高喊着「来！咱俩练练！」扑向来犯之敌。",
		"reward_score": 30,
		"reward_title": "巴克什商队物资"
	},
	"ahsarah_substation": {
		"title": "变电站 · 曼德尔加密砖日志",
		"lore": "【哈夫克集团（HAAVK）机密日志】东区变电站正为大坝与巴别通讯塔输送高压算力，用于测试极具价值的「曼德尔加密砖（MandelBrick）」——全息青蓝立方体内部封存着最高等级加密档案。",
		"reward_score": 35,
		"reward_title": "变电站科技物资"
	},
	"ahsarah_fortress": {
		"title": "行政堡垒 · 赤枭与非洲之心档案",
		"lore": "【阿萨拉行政堡垒绝密】传闻中北非最璀璨的旷世大红「非洲之心」曾短暂现身行政堡垒金库！普通行动中「赤枭·赛伊德」亲率卫队驻守此地，擅长翻滚位移与燃烧弹封路，切忌原地硬刚。",
		"reward_score": 40,
		"reward_title": "堡垒金库秘藏"
	},
	"ahsarah_dam": {
		"title": "大坝观景台 · 军阀留声机残页",
		"lore": "【机密行动 · 军阀雷斯档案】出身阿萨拉旧贵族的军阀「雷斯」最爱在炮火连天中摇响古董黄铜留声机，边听古典交响乐边率重甲霰弹卫队碾压对手：「没有交响乐的战场，简直粗俗不堪！」",
		"reward_score": 45,
		"reward_title": "大坝特勤秘藏"
	}
}

const HERITAGE_LORE_VARIANTS := {
	"cave_hearth": [
		"穹顶「一线天光」斜映碧色寒潭，青石圆桌上展陈先民手书竹简《烟山煮茗记》：「汲寒潭甘泉，燃枯竹微火，山中岁月静，一卷书声清。」",
		"寒潭畔青石茶灶余温犹存，竹简《诚庄农谚》载：「春采云雾茶，夏听翠竹风，秋收万顷稻，冬藏一洞温。」",
		"石案青瓷茶盏旁置有先民手抄《洞中夜读录》：「山外烟霞重，洞里松灯明；勤读知远方，字字见真情。」"
	],
	"cave_mural": [
		"西壁青灰岩体阴刻《烟山耕读岩画》（背篓采茶、驱牛扶犁、洞中挑灯），东壁《烟霞古洞志》载：「昔诚庄先民辟山畴，见暮霭竹烟常绕石壁，遂名此山曰烟山。」",
		"石壁之上铁錾斧痕历经风雨犹自清晰：画卷描绘江南先民晨涉碧溪采新茶、暮归岩洞燃松火授书的温润图景，烟山文脉由此代代相承。"
	],
	"cliff_inscription": [
		"竹石奇阵摩崖朱砂镌刻：「瘦石穿云立，翠篁引风吟。曲径通幽洞，清泉洗凡心。」——循翠竹幽径或矮石拱 [C] 蹲行即可通往千年古迹烟霞古洞。",
		"绝壁苔痕间刻有诚庄先贤题记：「入竹阵莫急，听溪声辨向；低首过石门，别有洞天藏。」——北端石门后即烟霞古洞入口。"
	]
}

var game
var nodes = []
var node_labels = {}
var states = {}
var failed = {}
var data = {}
var current_items = {}
var current_options = {}
var current_answer_index = {}
var current_spell_words = {}
var current_lore_snippets = {}
var rolled_rewards = {}
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
var spell_box: Control
var spell_input: LineEdit
var spell_submit_btn: Button
var spell_speak_btn: Button
var swap_button: Button
var gate: Node3D
var gate_plaque: Label3D
var stockade_root: Node3D
var grace = 0.0
var began = 0.0
var rng := RandomNumberGenerator.new()

func setup(g):
	game = g
	rng.randomize()
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	_ui()
	rebuild_for_map()

func rebuild_for_map():
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	node_labels.clear()
	if is_instance_valid(gate):
		gate.queue_free()
		gate = null
	if is_instance_valid(stockade_root):
		stockade_root.queue_free()
		stockade_root = null
	gate_plaque = null

	if game.is_ahsarah_map():
		var al = game.active_layout
		_mark("ahsarah_oasis", al.INTEL_OASIS, "绿洲前哨 · G.T.I. 跨界简报", Color("56e8ff"))
		_mark("ahsarah_cement", al.INTEL_CEMENT, "水泥厂 · 哈夫克征水密令", Color("ffd15c"))
		_mark("ahsarah_bazaar", al.INTEL_BAZAAR, "巴克什拱廊 · 老猎人手记", Color("f0a868"))
		_mark("ahsarah_substation", al.INTEL_SUBSTATION, "变电站 · 曼德尔加密砖日志", Color("3ae8ff"))
		_mark("ahsarah_fortress", al.INTEL_FORTRESS, "行政堡垒 · 赤枭与非洲之心档案", Color("ff7868"))
		_mark("ahsarah_dam", al.INTEL_DAM_VIEW, "大坝观景台 · 军阀留声机残页", Color("f6c34e"))
	else:
		_mark("clue", game.Layout.CLUE, "巡护员的纸条", Color("d1c79b"))
		_mark("english", game.Layout.CLUE_LOOT, "路牌旁的封存补给", Color("7c8b5b"))
		_mark("poem", game.Layout.POEM, "山路古诗石碑", Color("777b68"))
		_mark("math", game.Layout.MATH, "巡护站 · 近道机关", Color("5d6a50"))
		_mark("intel_container", game.Layout.PARKOUR_CONTAINERS + Vector3(5.6, 0, 2.5), "战地线报 #1 · 西岭货柜", Color("6ce3b8"))
		_mark("intel_cleft", game.Layout.CLEFT_CACHE + Vector3(12.0, 0, 2.0), "战地线报 #2 · 双岩秘藏", Color("6ce3b8"))
		_mark("intel_cave", game.Layout.MATH + Vector3(-2.6, 0, -1.8), "战地线报 #3 · 石窟密电", Color("ffd15c"))
		_mark("intel_roof", game.Layout.SHELTER_BAMBOO + Vector3(1.6, 0, 3.8), "战地线报 #4 · 棚顶与高塔", Color("cf8aff"))
		_mark("recon_radio", game.Layout.RECON_RADIO, "东岭侦察电台 · 抢修扫图", Color("56e8ff"))
		_mark("airdrop_beacon", game.Layout.AIRDROP_BEACON, "北脊空投信标 · 呼叫补给", Color("ffd15c"))
		var cave_c: Vector3 = game.Layout.YANXIA_CAVE_CENTER
		_mark("cliff_inscription", game.Layout.BAMBOO_MAZE_MOYA + Vector3(-0.05, 0, 0.0), "摩崖石刻《竹石清音》", Color("e8b878"))
		# v0.9.9.6_dev2 Grand Mountain Cavern placements: Mid-Gallery Mural (flush with Cave_Mural_Slab), Grand Hall Tea Hearth, Deep '一线天' Rift Wall!
		_mark("cave_mural", Vector3(cave_c.x - 6.25, 0, cave_c.z - 8.22), "先民岩凿壁画《烟山耕读》", Color("8de8c0"))
		_mark("cave_hearth", Vector3(cave_c.x - 5.65, 0, cave_c.z - 27.30), "寒潭茶灶与古竹简", Color("ffd15c"))
		_mark("dimensional_rift", Vector3(cave_c.x - 3.50, 0, cave_c.z - 33.40), "次元石壁 · 跨界裂隙", Color("5ef5e8"))
		_build_shortcut_stockade()
	reset()

func _build_shortcut_stockade():
	## v0.8.1 FB-6: Valley-spanning fortified timber palisade wall (x = 1.6..19.6 at z = -62)
	## anchored to the west pass ridge & east creek embankment, with central lockable wooden gate at x = 10!
	stockade_root = Node3D.new()
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

	var mg: Vector3 = game.Layout.MATH_GATE_CENTER
	var center: Vector3 = game.Layout.on_ground(mg)
	var fence_z: float = mg.z

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

	# Solid impenetrable palisade wings spanning entire pass from west slope to east creek bank!
	var west_anchor := center.x - 10.5
	var east_anchor := float(game.Layout.stream_center_x(fence_z)) - 2.2
	var wings := [
		[west_anchor, center.x - 1.55],
		[center.x + 1.55, east_anchor]
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
		game.landscape.rock(Vector3(west_anchor - 0.45, 0.0, fence_z - 0.15), 2.85, 1)
		game.landscape.rock(Vector3(east_anchor + 0.45, 0.0, fence_z + 0.10), 2.95, 3)

func _mark(id: String, at: Vector3, label: String, color: Color):
	var node = Node3D.new()
	if id in ["dimensional_rift", "cave_mural", "cave_hearth"]:
		node.position = Vector3(at.x, float(game.Layout.CAVE_FLOOR_Y) + 0.026, at.z)
	else:
		node.position = game.active_layout.on_ground(at)
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
	elif id in HERITAGE_IDS or id == "dimensional_rift":
		var h_ring := MeshInstance3D.new()
		var h_torus := TorusMesh.new()
		h_torus.inner_radius = 0.36 if id == "dimensional_rift" else 0.30
		h_torus.outer_radius = 0.46 if id == "dimensional_rift" else 0.38
		h_torus.rings = 18
		h_torus.ring_segments = 6
		h_ring.mesh = h_torus
		h_ring.position = Vector3(0.0, 0.05, 0.0)
		h_ring.material_override = game._material(color, true)
		node.add_child(h_ring)
	elif id in AHSARAH_EXPLORE_IDS:
		# Sleek sunlit desert tactical intel field terminal
		game._mesh_box(node, Vector3(0, 0.45, 0), Vector3(0.62, 0.90, 0.48), Color("4e565e"), true)
		var scr: MeshInstance3D = game._mesh_box(node, Vector3(0, 1.08, 0), Vector3(0.76, 0.46, 0.14), Color("16262e"), false)
		scr.rotation_degrees.x = -18.0
		var glow_scr: MeshInstance3D = game._mesh_box(node, Vector3(0, 1.09, 0.075), Vector3(0.64, 0.34, 0.02), color, false)
		glow_scr.rotation_degrees.x = -18.0
		glow_scr.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
		prompt.position = Vector3(-0.35, 3.35, 0.0)
		prompt.pixel_size = 0.0038
		prompt.text = "先民岩凿壁画《烟山耕读》 · [F]"
	elif id == "cave_hearth":
		prompt.position = Vector3(0.0, 1.68, -0.82)
		prompt.pixel_size = 0.0038
		prompt.text = "寒潭茶灶与先民竹简 · [F]"
	elif id == "dimensional_rift":
		prompt.position = Vector3(0.0, 0.88, 0.25)
		prompt.pixel_size = 0.0032
		prompt.text = "按 [F] 查探次元石壁"
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
	# v0.8.2 V81-4: Taller adaptive panel (840x646) + dynamic layout in _reflow_ui() so long heritage mural
	# stories NEVER collide with option buttons, explanation, or source line!
	game._panel(overlay, Rect2(220, 36, 840, 648), Color("162822"), Color(0.48, 0.78, 0.62, 0.45))
	title = game._text(overlay, "", Vector2(256, 54), Vector2(768, 38), 26, game.MINT)
	body = game._text(overlay, "", Vector2(256, 102), Vector2(768, 192), 19)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.clip_text = true
	for i in 3:
		buttons.append(game._button(overlay, "", Rect2(256, 308 + i * 48, 768, 42), choose.bind(i)))

	# v0.8.6 Live Random English Word Spelling Bar (used by Heritage / Intel / Radio / Airdrop / English nodes)
	spell_box = Control.new()
	spell_box.position = Vector2(256, 326)
	spell_box.size = Vector2(768, 96)
	overlay.add_child(spell_box)
	spell_input = LineEdit.new()
	spell_input.position = Vector2(0, 0)
	spell_input.size = Vector2(496, 46)
	spell_input.placeholder_text = "输入完整英文单词（按 Enter 或点右侧提交）"
	spell_input.add_theme_font_size_override("font_size", 20)
	spell_input.add_theme_color_override("font_color", Color("f4f8ef"))
	spell_input.add_theme_color_override("font_placeholder_color", Color("7ea897"))
	var sb_norm := StyleBoxFlat.new()
	sb_norm.bg_color = Color("0e1e19")
	sb_norm.border_color = Color("62c8a0")
	sb_norm.set_border_width_all(2)
	sb_norm.set_corner_radius_all(8)
	sb_norm.content_margin_left = 14
	sb_norm.content_margin_right = 14
	var sb_focus := sb_norm.duplicate()
	sb_focus.border_color = Color("ffd15c")
	spell_input.add_theme_stylebox_override("normal", sb_norm)
	spell_input.add_theme_stylebox_override("focus", sb_focus)
	spell_input.text_submitted.connect(submit_spelling)
	spell_box.add_child(spell_input)
	spell_submit_btn = game._button(spell_box, "✓ 提交拼写", Rect2(508, 0, 134, 46), func(): submit_spelling(spell_input.text), true)
	spell_speak_btn = game._button(spell_box, "🔊 听读音", Rect2(650, 0, 118, 46), _speak_active_spell_word, false)
	spell_box.hide()

	explanation = game._text(overlay, "", Vector2(256, 460), Vector2(768, 110), 15, game.GOLD)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.clip_text = true
	source = game._text(overlay, "", Vector2(256, 578), Vector2(768, 34), 13, Color("a7b8a2"))
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._button(overlay, "返回山路  [Esc]", Rect2(808, 624, 216, 38), close)
	swap_button = game._button(overlay, "📦 确认拾取奖励物资", Rect2(548, 624, 244, 38), open_reward_container, true)
	swap_button.hide()
	game._text(overlay, "阅读与思考期间暂停计时和敌方攻击", Vector2(256, 630), Vector2(300, 28), 14, game.MINT)
	overlay.hide()

func _reflow_ui(mode: String):
	var txt_len := body.text.length()
	var fsize := 17 if txt_len > 155 else (19 if txt_len > 95 else 21)
	body.add_theme_font_size_override("font_size", fsize)
	var measured_h := 120.0
	if is_instance_valid(game) and game.font != null:
		measured_h = game.font.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, 768.0, fsize).y + 16.0
	else:
		measured_h = ceilf(float(txt_len) / 34.0) * float(fsize + 9) + 18.0
	var max_body_h := 268.0 if mode == "spell" else 232.0
	var body_h := clampf(measured_h, 88.0, max_body_h)
	body.position = Vector2(256, 100)
	body.size = Vector2(768, body_h)
	var btn_top := 100.0 + body_h + 14.0
	if mode == "mc":
		spell_box.hide()
		for i in 3:
			buttons[i].position = Vector2(256, btn_top + float(i) * 46.0)
			buttons[i].size = Vector2(768, 40)
		var exp_top := btn_top + 3.0 * 46.0 + 10.0
		explanation.position = Vector2(256, exp_top)
		explanation.size = Vector2(768, maxf(54.0, 574.0 - exp_top))
	elif mode == "spell":
		for i in 3:
			buttons[i].hide()
		spell_box.position = Vector2(256, btn_top)
		spell_box.show()
		var exp_top_s := btn_top + 58.0
		explanation.position = Vector2(256, exp_top_s)
		explanation.size = Vector2(768, maxf(64.0, 574.0 - exp_top_s))
	else:
		spell_box.hide()
		for i in 3:
			buttons[i].hide()
		explanation.position = Vector2(256, btn_top + 12.0)
		explanation.size = Vector2(768, maxf(96.0, 574.0 - btn_top - 12.0))

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

func _normalize_english(raw: String) -> String:
	var parts := raw.strip_edges().to_lower().split(" ", false)
	return " ".join(parts)

func _spelling_mask(english: String) -> String:
	var words_arr := english.strip_edges().split(" ", false)
	var masked := []
	for w in words_arr:
		var s := str(w)
		if s.length() <= 1:
			masked.append(s)
		else:
			var chars := [s.substr(0, 1)]
			for ci in range(1, s.length()):
				var ch := s.substr(ci, 1)
				if ch in ["-", "'", ".", "?"]:
					chars.append(ch)
				else:
					chars.append("_")
			masked.append(" ".join(chars))
	return "   ".join(masked)

func _pick_random_spell_words():
	current_spell_words.clear()
	current_lore_snippets.clear()
	var pool: Array = []
	if is_instance_valid(game) and not game.words.is_empty():
		var due: Array = game.rules.learning.pending(game.words, 0, true) if is_instance_valid(game.rules) else []
		for w in due:
			if str(w.get("english", "")).strip_edges() != "":
				pool.append(w)
		var shuffled_all: Array = game.words.duplicate()
		shuffled_all.shuffle()
		for w in shuffled_all:
			if not (w in pool) and str(w.get("english", "")).strip_edges() != "":
				pool.append(w)
	var used_words := {}
	for sid in SPELL_CHALLENGE_IDS:
		var picked: Dictionary = {}
		# Mix review-due priority (first 16) with full-pack variety while strictly deduplicating by lowercase English word!
		var top_span := mini(pool.size(), 28)
		for _attempt in 24:
			if pool.is_empty():
				break
			var idx := rng.randi_range(0, top_span - 1) if (_attempt < 5 and top_span > 0) else rng.randi_range(0, pool.size() - 1)
			var cand: Dictionary = pool[idx]
			var wkey := str(cand.get("english", "")).strip_edges().to_lower()
			if wkey != "" and not used_words.has(wkey):
				picked = cand
				used_words[wkey] = true
				break
		if picked.is_empty():
			for cand in pool:
				var wkey := str(cand.get("english", "")).strip_edges().to_lower()
				if wkey != "" and not used_words.has(wkey):
					picked = cand
					used_words[wkey] = true
					break
		if picked.is_empty() and not pool.is_empty():
			picked = pool[rng.randi_range(0, pool.size() - 1)]
		current_spell_words[sid] = picked
		if HERITAGE_LORE_VARIANTS.has(sid):
			var lv: Array = HERITAGE_LORE_VARIANTS[sid]
			current_lore_snippets[sid] = str(lv[rng.randi_range(0, lv.size() - 1)])

func is_spelling_challenge(id: String) -> bool:
	return id in SPELL_CHALLENGE_IDS and current_spell_words.has(id) and not (current_spell_words[id] as Dictionary).is_empty()

func expected_spelling_word(id: String) -> String:
	return str((current_spell_words.get(id, {}) as Dictionary).get("english", ""))

func _speak_active_spell_word():
	if active_id != "" and is_spelling_challenge(active_id):
		var en := expected_spelling_word(active_id)
		if en != "":
			game.speak_english(en)

func answer_button_index(id: String) -> int:
	return int(current_answer_index.get(id, 0))

func is_locked_out(id: String) -> bool:
	return bool(failed.get(id, false))

func reset():
	states = {"clue": false, "english": false, "english_claimed": false, "math": false, "poem": false, "math_claimed": false, "poem_claimed": false}
	failed = {}
	rolled_rewards = {}
	for sid in SECRET_EVENT_IDS:
		states[sid] = false
		states[sid + "_claimed"] = false
	for hid in HERITAGE_IDS:
		states[hid] = false
		states[hid + "_claimed"] = false
	states["dimensional_rift"] = false
	for aid in AHSARAH_EXPLORE_IDS:
		states[aid] = false
		states[aid + "_claimed"] = false
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
	current_items["english"] = {
		"title": "路牌旁的封存补给 · 拼写核验",
		"question": "循着巡护员纸条上的方位词 next to（在……旁边），你找到了封存补给箱。",
		"explanation": "核验通过！封条已解开，可自由挑选箱内随机补给物资。",
		"source": "江苏五上英语词表 · 随机单词拼写核验",
		"reward_title": "随机补给物资",
		"reward_value": 50,
		"reward_rarity": 2,
	}
	current_items["dimensional_rift"] = {
		"title": "烟霞古洞 · 次元石壁铭文共鸣",
		"question": "一线天光正后方的古老次元石壁正迸发沙金与青蓝双色裂隙！拼写正确英语口令即可彻底破除封印，永久开启全新沙漠特战战场【阿萨拉堡垒】！",
		"explanation": "✦ 次元石壁已彻底开启！新战场【阿萨拉堡垒】已永久写入存档，下次返回营地即可自由切换出击！",
		"source": "烟霞古洞次元裂隙 · 跨界开启试炼",
		"reward_score": 60,
	}
	for aid in AHSARAH_EXPLORE_IDS:
		var spec: Dictionary = AHSARAH_LORE_SPECS[aid]
		current_items[aid] = {
			"title": str(spec.title),
			"question": str(spec.lore),
			"explanation": "情报破译完成！已记录 2035 阿萨拉战区档案并开启随机战利品补给。",
			"source": "阿萨拉战区档案 · 175词教材随机拼写",
			"reward_score": int(spec.reward_score),
			"reward_title": str(spec.reward_title),
		}
		current_lore_snippets[aid] = str(spec.lore)
	_pick_random_spell_words()
	if is_instance_valid(overlay):
		overlay.hide()
	if is_instance_valid(gate):
		game.Props.set_enabled(gate, true)
		gate.rotation = Vector3.ZERO
	if is_instance_valid(gate_plaque):
		gate_plaque.visible = true
	for n in nodes:
		game.Props.set_enabled(n, true)
		for mk in ["pending_items", "opened_remaining", "scanned"]:
			if n.has_meta(mk):
				n.remove_meta(mk)
	for lid in node_labels:
		var info: Dictionary = node_labels[lid]
		var lbl: Label3D = info.label
		if is_instance_valid(lbl):
			lbl.text = str(info.base_text)
			lbl.modulate = info.base_color

func _node_for_id(id: String) -> Node3D:
	for n in nodes:
		if is_instance_valid(n) and str(n.get_meta("explore_id", "")) == id:
			return n
	return null

func safe() -> bool:
	var cipher_busy = is_instance_valid(game.cipher_terminal) and game.cipher_terminal.busy
	var ranger_busy = is_instance_valid(game.rangers) and game.rangers.busy
	var loot_box_busy = is_instance_valid(game.loot_container_ui) and game.loot_container_ui.busy
	return busy or cipher_busy or ranger_busy or loot_box_busy or grace > 0 or game.player.position.distance_to(game.exit_position) < 4.7

func update(delta: float):
	grace = maxf(0, grace - delta)
	if game.rules.phase in ["active", "extracting"]:
		began += delta

func open(node: Node3D):
	var id: String = node.get_meta("explore_id")
	if id in ["cave_mural", "cave_hearth", "dimensional_rift"] and is_instance_valid(game.cave_warden) and game.cave_warden.is_alive() and game.cave_warden.state == "hunt":
		game.play_sfx("warning_lock", -10)
		game._notice("⚠ 古洞循音石卫正在追击！请先潜行转移甩开、[G]烟雾掩护或将其击败后再探查古迹！", Color("ff8080"))
		return
	if id == "dimensional_rift":
		if game.rules.is_ahsarah_permanently_unlocked():
			game.play_sfx("cipher_unlock", -11)
			game._notice("✦ 次元石壁已永久连通【阿萨拉堡垒】！返回营地主菜单即可随时切换进入新战区！", Color("7cf7ec"))
			return
		var warden_down_conf: bool = bool(game.confidential_warden_slain_this_run) or (game.rules.is_confidential() and is_instance_valid(game.cave_warden) and not game.cave_warden.is_alive())
		if not warden_down_conf:
			game.play_sfx("hit_wrong", -13)
			game._notice("🔒 次元石壁封印中！需在烟山【机密行动】中击败「古洞循音石卫」，方可唤醒一线天光后方的跨界裂隙！", Color("ffd15c"))
			return
	if id == "english" and not states.clue:
		game._notice("补给箱贴着封条！先看附近巡护员纸条上的方位提示。")
		game.play_sfx("hit_wrong", -14)
		return
	# v0.8.4: Revisiting a solved exploration stash with leftover reward items opens LootContainerUI directly!
	if bool(states.get(id, false)) and node.has_meta("pending_items"):
		var rem_exp: Array = node.get_meta("pending_items")
		if not rem_exp.is_empty() and is_instance_valid(game.loot_container_ui):
			var exp_title := str(current_items.get(id, {}).get("title", node.get_meta("prompt", "探索奖励")))
			game.loot_container_ui.open_container(
				node, "exploration", exp_title, rem_exp,
				"已解开的探索秘藏奖励 · 自由选择拾取入包、存安全箱或留在原处", false, id
			)
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
		body.text = "山道补给箱藏在路牌旁边。\n英文方位线索：The supply box is  next to  the signpost.\n读懂方位词，去山路右侧路牌旁找到封存箱，完成随机英语拼写核验即可开启！"
		source.text = "词汇来源：江苏五上英语词表 · next to（在……旁边）。已同步播放读音。"
		explanation.text = "提示：next to = 在……旁边。找到封存箱按 [F] 拼对随机考题即可抽取随机品质补给！"
		_reflow_ui("info")
		game.speak_english("next to")
	elif is_spelling_challenge(id):
		var item: Dictionary = current_items.get(id, {})
		var w: Dictionary = current_spell_words[id]
		var w_en := str(w.get("english", ""))
		var w_zh := str(w.get("chinese", ""))
		var raw_unit = w.get("unit", "")
		var w_unit := ("Unit %d" % int(raw_unit)) if (raw_unit is int or raw_unit is float) else (str(raw_unit) if str(raw_unit) != "" else "五上英语")
		var lore_text := str(current_lore_snippets.get(id, ""))
		if lore_text == "":
			if id == "english":
				lore_text = "循着巡护员纸条上的方位线索 next to（在……旁边），你找到了贴着密码封条的山道补给箱。"
			elif id in INTEL_IDS:
				lore_text = "巡护线报原件加密锁闭——输入对应英文单词即可破译密电，并在战术雷达上标亮隐藏秘藏坐标！"
			elif id == "recon_radio":
				lore_text = "东岭侦察电台待校准频段——拼出对应英文口令即可启动全图雷达扫描并领取战术补给！"
			elif id == "airdrop_beacon":
				lore_text = "北脊卫星空投信标等待身份核验——正确拼写随机英文词即可召唤补给弹药与随机品质战利品！"
			else:
				lore_text = str(item.get("question", "")).split("\n")[0]
		var cl: Dictionary = game.cloze_for_word(str(w.get("id", "")))
		var cloze_line := ("\n教材语境：%s  (p.%d)" % [str(cl.cloze_text), int(cl.textbook_page)]) if not cl.is_empty() else ""
		title.text = str(item.get("title", "烟山探索 · 随机单词拼写考题"))
		body.text = "%s\n\n【本局随机单词考题】请根据中文释义拼写对应英文：\n中文释义：%s   |   拼写轮廓：%s%s" % [
			lore_text, w_zh, _spelling_mask(w_en), cloze_line
		]
		source.text = "随机抽词自 175 词教材总库（%s） · 每局刷新 · 奖励按全局爆率金字塔随机抽取" % w_unit
		var locked_now := is_locked_out(id)
		var solved_now := bool(states.get(id, false))
		spell_input.text = w_en if solved_now else ""
		spell_input.editable = (not locked_now and not solved_now)
		spell_submit_btn.disabled = (locked_now or solved_now)
		_reflow_ui("spell")
		if not locked_now and not solved_now:
			spell_input.grab_focus()
		game.speak_english(w_en)
		if locked_now:
			var ex_line := ("\n例句：%s" % str(cl.english)) if not cl.is_empty() else ""
			explanation.text = "✕ 本局该处拼写考题已答错锁死（不可重试，下局换新词）。\n正确拼写：%s（%s）%s" % [w_en, w_zh, ex_line]
		elif solved_now:
			_reward(id)
	else:
		var item = current_items[id]
		var opts = current_options[id]
		var expected_idx = answer_button_index(id)
		title.text = item.title
		body.text = item.question
		source.text = item.source + " · 奖励按爆率金字塔随机抽取"
		var locked_now := is_locked_out(id)
		for i in 3:
			buttons[i].show()
			buttons[i].text = opts[i]
			buttons[i].disabled = locked_now
		_reflow_ui("mc")
		if not locked_now:
			buttons[0].grab_focus()
		if item.has("tts"):
			game.speak_english(str(item.tts))
		if locked_now:
			explanation.text = "✕ 本局该题已答错锁死（不可重试，下局刷新）。\n正确答案：%s\n解析：%s" % [opts[expected_idx], item.explanation]
		elif states.get(id, false):
			_reward(id)

func submit_spelling(raw_text: String):
	if not busy or active_id == "" or not is_spelling_challenge(active_id):
		return
	if bool(states.get(active_id, false)) or is_locked_out(active_id):
		return
	var cleaned := _normalize_english(raw_text)
	if cleaned == "":
		explanation.text = "请先在输入框内拼写完整英文单词，再按 Enter 或点击「✓ 提交拼写」！"
		return
	var w: Dictionary = current_spell_words[active_id]
	var w_id := str(w.get("id", ""))
	var w_en := str(w.get("english", ""))
	var w_zh := str(w.get("chinese", ""))
	var expected := _normalize_english(w_en)
	var item: Dictionary = current_items.get(active_id, {})
	var cl: Dictionary = game.cloze_for_word(w_id)
	var ex_line := ("\n教材例句：%s (p.%d)" % [str(cl.english), int(cl.textbook_page)]) if not cl.is_empty() else ""
	if cleaned != expected:
		failed[active_id] = true
		spell_input.editable = false
		spell_submit_btn.disabled = true
		if is_instance_valid(game.rules):
			game.rules.learning.record_spelling(w_id, game.rules.learning.INCORRECT, false, -1, true, "exploration_" + active_id)
		if not (w in game.wrong_words):
			game.wrong_words.append(w)
		game.play_sfx("hit_wrong", -13)
		game.speak_english(w_en)
		explanation.text = "✕ 拼写有误！本局该处已锁死（不可重试，下局刷新全新词题）。\n正确拼写：%s（%s）%s" % [w_en, w_zh, ex_line]
		if node_labels.has(active_id):
			var info: Dictionary = node_labels[active_id]
			var lbl: Label3D = info.label
			if is_instance_valid(lbl):
				lbl.text = str(item.get("title", active_id)) + " · [本局已锁]"
				lbl.modulate = Color("ff8c7a")
		return
	spell_input.text = w_en
	spell_input.editable = false
	spell_submit_btn.disabled = true
	if is_instance_valid(game.rules):
		game.rules.learning.record_spelling(w_id, game.rules.learning.INDEPENDENT, false, -1, true, "exploration_" + active_id)
	game.speak_english(w_en)
	_complete_solved_node(active_id, "✓ 拼写正确：%s（%s）！%s" % [w_en, w_zh, ex_line])

func choose(index: int):
	if not busy or active_id not in current_items or is_spelling_challenge(active_id):
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
	_complete_solved_node(active_id, "")

func _complete_solved_node(id: String, lead_prefix: String):
	var item: Dictionary = current_items.get(id, {})
	var first_solve := not bool(states.get(id, false))
	states[id] = true
	if id == "math":
		gate.rotation.y = -PI / 2
		if is_instance_valid(gate_plaque):
			gate_plaque.visible = false
		game.play_sfx("cipher_unlock", -11)
	elif first_solve and id == "english":
		game.rules.score += 18
		game.play_sfx("cipher_unlock", -11)
		game._notice("拼写核验通过！已解开路牌旁封存补给（+18 积分）！", game.MINT)
	elif first_solve and id in HERITAGE_IDS:
		var h_pts := int(item.get("reward_score", 30))
		game.rules.score += h_pts
		var hrk := str(item.get("reveal_key", ""))
		if hrk != "":
			revealed_secrets[hrk] = true
		if id == "cave_hearth" and is_instance_valid(game.combat):
			game.combat.heal(20, 15)
			game.play_sfx("heal_shield", -10)
			game._notice("品饮寒潭山茶 · 生命+20 护盾+15 · 烟山秘史 +%d 分！" % h_pts, game.GOLD)
		else:
			game.play_sfx("cipher_unlock", -10)
			game._notice("品读烟山古迹并通过随机单词核验！获得 +%d 撤离积分" % h_pts, game.MINT)
	elif first_solve and id in INTEL_IDS:
		game.rules.score += int(item.get("reward_score", 20))
		var rk := str(item.get("reveal_key", ""))
		if rk != "":
			revealed_secrets[rk] = true
		game.play_sfx("cipher_unlock", -11)
		game._notice("破译战地英文线报！雷达已标记秘宝定位（+%d 分）" % int(item.get("reward_score", 20)), game.MINT)
	elif first_solve and id == "recon_radio":
		radar_scan_active = true
		game.rules.score += 45
		game.player.grenades += 1
		var radio_ammo := 6 if game.rules.is_confidential() else 8
		if not game.player.has_infinite_ammo():
			game.player.add_reserve_ammo(radio_ammo)
		game.play_sfx("radio_scan", -10)
		game._notice("东岭雷达全图扫描已激活！+45分 +1烟雾EMP +%d备弹" % radio_ammo, Color("7ceeff"))
	elif first_solve and id == "dimensional_rift":
		game.rules.score += 60
		game.play_sfx("boss_phase", -8)
		if game.has_method("unlock_ahsarah_map"):
			game.unlock_ahsarah_map("dimensional_rift")
	elif first_solve and id in AHSARAH_EXPLORE_IDS:
		var a_pts := int(item.get("reward_score", 30))
		game.rules.score += a_pts
		game.play_sfx("cipher_unlock", -10)
		game._notice("破译阿萨拉战区档案！获得 +%d 撤离积分，可领取随机品质补给" % a_pts, game.GOLD)
	elif first_solve and id == "airdrop_beacon":
		game.rules.score += 40
		var drop_ammo := 12 if game.rules.is_confidential() else 10
		if not game.player.has_infinite_ammo():
			game.player.add_reserve_ammo(drop_ammo)
		game.play_sfx("airdrop_call", -10)
		game._notice("北脊卫星空投已解锁！+40分 +%d备弹" % drop_ammo, game.GOLD)
	else:
		game.play_sfx("cipher_unlock", -11)
	_reward(id, lead_prefix)

func _resolved_reward(id: String, _item: Dictionary) -> Dictionary:
	# v0.8.6: ALL exploration item rewards roll probabilistically against the global calibrated drop pyramid!
	# (Cached per run per node so reopening never re-rolls; zero guaranteed Purple/Gold giveaways!)
	if rolled_rewards.has(id):
		return rolled_rewards[id]
	var ctx := "exploration_deep" if id in DEEP_REWARD_IDS else "exploration_standard"
	var rarity: int = game.rules.roll_calibrated_rarity(game.rules.is_confidential(), ctx, true)
	var rolled: Dictionary = game.rules.roll_item_by_rarity(rarity)
	rolled_rewards[id] = rolled
	return rolled

func _reward(id: String, lead_prefix: String = ""):
	var item: Dictionary = current_items.get(id, {})
	var base_exp := (lead_prefix + "\n" + str(item.get("explanation", ""))) if lead_prefix != "" else str(item.get("explanation", ""))
	if not item.has("reward_title"):
		swap_button.hide()
		var pts := int(item.get("reward_score", 20))
		explanation.text = "%s\n已解锁雷达定位并获得 +%d 撤离积分！" % [base_exp, pts]
		for b in buttons:
			b.disabled = true
		return
	var key = id + "_claimed"
	var rw := _resolved_reward(id, item)
	var rw_title: String = str(rw.title)
	var rw_value: int = int(rw.value)
	var rarity: int = int(rw.rarity)
	swap_button.hide()
	var suffix = "这处探索奖励已领取。"
	if not states.get(key, false):
		if not game.rules.can_loot():
			states[key] = true
			suffix = "自由靶场模式仅作纯学习练习（不入包物资），实战行动中可随机抽取【%s】%s 等物资！" % [game.Rules.RARITY_NAMES[rarity], rw_title]
		else:
			var nd := _node_for_id(id)
			var rw_item: Dictionary = game.rules._enrich_loot_dict(rw)
			if is_instance_valid(nd):
				if not nd.has_meta("pending_items") or (nd.get_meta("pending_items") as Array).is_empty():
					nd.set_meta("pending_items", [rw_item])
					nd.set_meta("opened_remaining", true)
			suffix = "随机抽得【%s】%s（估值 %d 币）！请点下方「📦 确认拾取奖励物资」选择入包、存安全箱或留原处。" % [game.Rules.RARITY_NAMES[rarity], rw_title, rw_value]
			swap_button.text = "📦 确认拾取奖励物资"
			swap_button.show()
	explanation.text = base_exp + "\n" + suffix
	for b in buttons:
		b.disabled = true

func open_reward_container():
	if not busy or active_id not in current_items or not bool(states.get(active_id, false)) or bool(states.get(active_id + "_claimed", false)):
		return
	var eid: String = str(active_id)
	var nd: Node3D = _node_for_id(eid)
	var exp_title: String = str(current_items[eid].get("title", "探索奖励"))
	var items_arr: Array = nd.get_meta("pending_items", []) if is_instance_valid(nd) else []
	if items_arr.is_empty():
		var rw := _resolved_reward(eid, current_items[eid])
		items_arr = [game.rules._enrich_loot_dict(rw)]
		if is_instance_valid(nd):
			nd.set_meta("pending_items", items_arr)
			nd.set_meta("opened_remaining", true)
	busy = false
	overlay.hide()
	if is_instance_valid(game.loot_container_ui):
		game.loot_container_ui.open_container(
			nd, "exploration", exp_title, items_arr,
			"探索秘藏奖励确认 · 可拾取入包、直存安全箱，或留原处稍后再取", false, eid
		)
	else:
		close()

func replace_reward():
	open_reward_container()

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
	if is_instance_valid(game) and game.is_ahsarah_map():
		var ac := 0
		for aid in AHSARAH_EXPLORE_IDS:
			if bool(states.get(aid, false)):
				ac += 1
		return "阿萨拉情报 %d/%d" % [ac, AHSARAH_EXPLORE_IDS.size()]
	return "探%d/3·秘%d/6·迹%d/3" % [completed(), secrets_completed(), heritage_completed()]
