extends Control
## Grand 3D Interactive Strategic War Map ('作战沙盘' — v0.9.5).
## Renders a live miniature 3D terrain diorama inside an isolated SubViewport (own_world_3d = true)
## occupying the right 4/5 of the Login Screen (1012x720):
## - Theater 1 ('yanshan'): Lush Jiangnan mountains, terraced paddies, winding Chengzhuang River:
##     * Upper-Center Hill -> 【烟山基地】 (playable)
##     * Bottom-Left Campus -> 【鲸塘中心小学（暂未开放）】 (mini 3D school + oval track)
##     * Mid-Right Riverbend -> 【诚庄村河港（暂未开放）】 (mini Jiangnan white-wall village + arch bridge + wharf)
## - Theater 2 ('ahsarah'): Golden North African desert dunes, canyon gorge, dam reservoir & oasis:
##     * North-Central Gorge -> 【阿萨拉堡垒】 (mini Zero Dam + sandstone fortress + twin Babel towers)
##     * Southwest Oasis -> 【巴克什古城外围（暂未开放）】 (mini mudbrick domes + palms)
##     * Southeast Mesa -> 【哈夫克航天禁区（暂未开放）】 (mini futuristic gantry + radar dishes)
## - Theater 3 ('story'): Golden-hour scenic flyover of Yanshan Valley for Story Mode chapters.
## Automatically disables SubViewport rendering whenever hidden during combat -> ZERO in-match FPS cost!

signal landmark_selected(landmark_id: String, meta: Dictionary)

const LANDMARKS := {
	"yanshan": [
		{
			"id": "yanshan_base",
			"title": "烟山基地",
			"badge": "🏔 烟山基地",
			"subtitle": "已开放 · 江南山地搜撤核心战区",
			"pos": Vector3(0.4, 5.25, -4.8),
			"open": true,
			"map_id": "yanshan",
			"accent": Color("58f0b8"),
			"desc": "烟山北麓高地前哨，串联东岭望稻亭、古石拱桥、竹海总坛与烟霞古洞。15 分钟普通行动 / 20 分钟机密行动，肃清 3 座营地并击败首领即可携宝撤离！",
		},
		{
			"id": "jingtang_school",
			"title": "鲸塘中心小学",
			"badge": "🏫 鲸塘中心小学（暂未开放）",
			"subtitle": "暂未开放 · 后续版本规划中",
			"pos": Vector3(-7.6, 2.20, 4.4),
			"open": false,
			"map_id": "yanshan",
			"accent": Color("9eb4c0"),
			"desc": "【暂未开放 · 规划中】位于烟山西麓山脚的乡土校园与操场。未来版本将开放校园情景英语互动与课堂词汇支线探索，敬请期待！",
		},
		{
			"id": "chengzhuang_port",
			"title": "诚庄村河港",
			"badge": "🏘 诚庄村河港（暂未开放）",
			"subtitle": "暂未开放 · 后续版本规划中",
			"pos": Vector3(8.2, 2.05, 0.2),
			"open": false,
			"map_id": "yanshan",
			"accent": Color("9eb4c0"),
			"desc": "【暂未开放 · 规划中】粉墙黛瓦的诚庄水乡码头与古石桥河港。未来版本将拓展水陆双线潜行与货栈奇珍搜撤玩法，敬请期待！",
		},
	],
	"ahsarah": [
		{
			"id": "ahsarah_fortress",
			"title": "阿萨拉堡垒",
			"badge": "🏰 阿萨拉堡垒",
			"subtitle": "零号大坝 · 沙漠堡垒搜撤战区",
			"pos": Vector3(-0.2, 4.70, -4.3),
			"open": true,
			"map_id": "ahsarah",
			"accent": Color("ffb84d"),
			"desc": "扼守北非峡谷咽喉的零号大坝与行政堡垒！融汇水泥厂、巴克什砂岩集市与哈夫克变电站：普通迎战「赤枭·赛伊德」，机密直面「军阀·雷斯」，寻觅非洲之心与曼德尔加密砖！",
		},
		{
			"id": "brakkesh_oldtown",
			"title": "巴克什古城外围",
			"badge": "🕌 巴克什古城外围（暂未开放）",
			"subtitle": "暂未开放 · 后续荒漠拓展规划",
			"pos": Vector3(-7.5, 2.25, 4.3),
			"open": false,
			"map_id": "ahsarah",
			"accent": Color("b8a88c"),
			"desc": "【暂未开放 · 规划中】绿洲环抱的阿萨拉古城外围巷战区，拟于后续版本拓展多层屋顶立体对抗与遗迹密室，敬请期待！",
		},
		{
			"id": "space_city",
			"title": "哈夫克航天禁区",
			"badge": "🛰 哈夫克航天禁区（暂未开放）",
			"subtitle": "暂未开放 · 后续高阶拓展规划",
			"pos": Vector3(8.0, 3.30, 1.6),
			"open": false,
			"map_id": "ahsarah",
			"accent": Color("7cc8e0"),
			"desc": "【暂未开放 · 规划中】沙漠东南高原上的哈夫克秘密发射台与科研高塔，拟于后续版本作为终极高难英语特战禁区登场！",
		},
	],
	"story": [
		{
			"id": "story_ch1",
			"title": "第一章 · 烟山初行",
			"badge": "✨ 第一章：烟山初行（单人序章）",
			"subtitle": "已开放 · 5–8 分钟沉浸式教学剧情",
			"pos": Vector3(0.4, 5.10, -4.8),
			"open": true,
			"map_id": "yanshan",
			"accent": Color("ffd76a"),
			"desc": "跟随陈向导深入烟山谷地，查明东岭望稻亭失联信标背后的英文密电线索，完成你的首次游侠实战演练！",
		},
		{
			"id": "story_ch2",
			"title": "第二章 · 古洞秘闻",
			"badge": "📜 第二章：烟霞古洞深处（敬请期待）",
			"subtitle": "筹备中 · 后续剧情章节",
			"pos": Vector3(6.8, 2.75, -0.8),
			"open": false,
			"map_id": "yanshan",
			"accent": Color("9eb4c0"),
			"desc": "【剧情筹备中】深入烟霞古洞寒潭石室，揭开雾隐帮词盾核心与阿萨拉零号大坝之间的跨国谜团。",
		},
	],
}

var game
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var camera: Camera3D
var world_env: WorldEnvironment
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D

var yanshan_root: Node3D
var ahsarah_root: Node3D
var beacon_rings: Array = []
var cloud_nodes: Array = []

var pins_layer: Control
var pin_buttons: Dictionary = {}  # landmark_id -> {panel, btn, dot, world_pos, data}
var theater_header_lbl: Label
var theater_sub_lbl: Label

var current_theater: String = "yanshan"  # "story" | "yanshan" | "ahsarah"
var selected_landmark_id: String = "yanshan_base"
var anim_clock: float = 0.0
var cam_focus_offset: Vector3 = Vector3.ZERO
var target_focus_offset: Vector3 = Vector3.ZERO


func setup(g, rect: Rect2):
	game = g
	position = rect.position
	size = rect.size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS

	_build_viewport()
	_build_yanshan_diorama()
	_build_ahsarah_diorama()
	_build_overlay_chrome()
	set_theater("yanshan", true)


func _mat(col: Color, rough: float = 0.85, met: float = 0.0, unshaded: bool = false, emit_col: Color = Color(0, 0, 0, 0), emit_e: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = met
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit_col
		m.emission_energy_multiplier = emit_e
	return m


func _build_viewport():
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.own_world_3d = true
	sub_viewport.size = Vector2i(maxi(320, int(size.x)), maxi(240, int(size.y)))
	sub_viewport.msaa_3d = Viewport.MSAA_2X
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("285870")
	sky_mat.sky_horizon_color = Color("8cc4b8")
	sky_mat.ground_bottom_color = Color("1f3834")
	sky_mat.ground_horizon_color = Color("6b9c8e")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9cd4c8")
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_light_color = Color("8fc0b8")
	env.fog_density = 0.0085
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	world_env = WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-31.0, 48.0, 0.0)
	sun_light.light_color = Color("fff0d2")
	sun_light.light_energy = 1.55
	sun_light.shadow_enabled = false
	sub_viewport.add_child(sun_light)

	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-28.0, -145.0, 0.0)
	fill_light.light_color = Color("7bc8e2")
	fill_light.light_energy = 0.42
	fill_light.shadow_enabled = false
	sub_viewport.add_child(fill_light)

	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.2
	camera.far = 160.0
	sub_viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 16.5, 22.8), Vector3(0.0, 0.6, 0.8), Vector3.UP)


# ---------------------------------------------------------------------------
# Procedural Sculpted 3D Relief Terrain Mesh Generator (Vertex-Colored!)
# ---------------------------------------------------------------------------
func _build_terrain_mesh(half_w: float, half_d: float, seg_x: int, seg_z: int, height_fn: Callable, color_fn: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	var cols: Array = []
	pts.resize((seg_z + 1) * (seg_x + 1))
	cols.resize((seg_z + 1) * (seg_x + 1))
	for iz in range(seg_z + 1):
		var tz := float(iz) / float(seg_z)
		var z := lerpf(-half_d, half_d, tz)
		for ix in range(seg_x + 1):
			var tx := float(ix) / float(seg_x)
			var x := lerpf(-half_w, half_w, tx)
			var h: float = float(height_fn.call(x, z))
			var idx := iz * (seg_x + 1) + ix
			pts[idx] = Vector3(x, h, z)
			cols[idx] = color_fn.call(x, z, h)

	for iz in range(seg_z):
		for ix in range(seg_x):
			var i00 := iz * (seg_x + 1) + ix
			var i10 := i00 + 1
			var i01 := i00 + (seg_x + 1)
			var i11 := i01 + 1
			for tri in [[i00, i10, i11], [i00, i11, i01]]:
				for vi in tri:
					st.set_color(cols[vi])
					st.add_vertex(pts[vi])

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.88
	mat.metallic = 0.02
	mi.material_override = mat
	return mi


func _add_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_beacon_ring(parent: Node3D, pos: Vector3, col: Color, radius: float = 1.15):
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.82
	tm.outer_radius = radius
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.position = pos
	ring.material_override = _mat(col, 0.2, 0.1, true, col, 1.4)
	parent.add_child(ring)
	beacon_rings.append({"node": ring, "base_y": pos.y})

	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.04
	bm.bottom_radius = 0.16
	bm.height = 2.6
	beam.mesh = bm
	beam.position = pos + Vector3(0, 1.3, 0)
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(col.r, col.g, col.b, 0.36)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.emission_enabled = true
	bmat.emission = col
	bmat.emission_energy_multiplier = 1.1
	beam.material_override = bmat
	parent.add_child(beam)


# ---------------------------------------------------------------------------
# DIORAMA 1: 烟山行动 (Jiangnan Mountain Relief + Base + School + River Port)
# ---------------------------------------------------------------------------
func _yanshan_river_z(x: float) -> float:
	# Winding river sweeping from top-right through mid-right Chengzhuang Port to bottom-right
	return 0.6 + sin(x * 0.24 - 0.6) * 1.9 + (x - 6.0) * 0.12


func _yanshan_height(x: float, z: float) -> float:
	# Main Yanshan Mountain peak at upper-center (0.4, -4.8)
	var d_main := Vector2(x - 0.4, z + 4.8).length()
	var h_main := 3.55 * exp(-(d_main * d_main) / 14.5)
	# Secondary twin mist ridges along northern horizon
	var d_nw := Vector2(x + 9.2, z + 7.2).length()
	var h_nw := 4.1 * exp(-(d_nw * d_nw) / 24.0)
	var d_ne := Vector2(x - 10.6, z + 7.6).length()
	var h_ne := 4.4 * exp(-(d_ne * d_ne) / 26.0)
	var d_mid_e := Vector2(x - 6.6, z + 2.2).length()
	var h_me := 1.75 * exp(-(d_mid_e * d_mid_e) / 11.0)
	# Gentle rolling Jiangnan foothills
	var roll := 0.35 * sin(x * 0.32) * cos(z * 0.28) + 0.20 * cos((x + z) * 0.22)
	var h := 0.62 + h_main + h_nw + h_ne + h_me + roll
	# Flatten Jingtang School flatland (bottom-left: -8.4, +5.1)
	var d_sch := Vector2(x + 8.4, z - 5.1).length()
	if d_sch < 4.5:
		h = lerpf(0.66, h, smoothstep(2.2, 4.5, d_sch))
	# Carve Chengzhuang River channel flowing past mid-right (9.0, 0.4)
	var rz := _yanshan_river_z(x)
	var d_riv := absf(z - rz)
	if x > -3.5 and d_riv < 2.2:
		var carve := 1.0 - smoothstep(0.65, 2.2, d_riv)
		h = lerpf(h, 0.14, carve * 0.92)
	# Broad harbor basin right beside Chengzhuang Port (x ~ 8.8..12.8, z ~ 1.4..4.2)
	var d_bay := Vector2((x - 10.4) * 0.72, z - 2.3).length()
	if d_bay < 3.0:
		h = lerpf(0.12, h, smoothstep(1.3, 3.0, d_bay))
	return maxf(0.10, h)


func _yanshan_color(x: float, z: float, h: float) -> Color:
	if h < 0.34:
		return Color("297d88")  # Shallow river bed / turquoise banks
	if h < 0.72:
		# Terraced Jiangnan golden-green rice paddies near valley floor!
		var stripe := 0.5 + 0.5 * sin(x * 1.4 + z * 1.2)
		return Color("528b52").lerp(Color("8ea856"), stripe * 0.45)
	if h < 1.85:
		return Color("2d6d4c").lerp(Color("458a58"), clampf((h - 0.72) / 1.13, 0.0, 1.0))
	if h < 3.10:
		return Color("265a44").lerp(Color("48705e"), clampf((h - 1.85) / 1.25, 0.0, 1.0))
	return Color("5e796e").lerp(Color("92a89e"), clampf((h - 3.10) / 1.5, 0.0, 1.0))


func _build_yanshan_diorama():
	yanshan_root = Node3D.new()
	yanshan_root.name = "YanshanDiorama"
	sub_viewport.add_child(yanshan_root)

	# 1. Sculpted Jiangnan Mountain Relief
	var terrain := _build_terrain_mesh(17.5, 13.5, 58, 44, _yanshan_height, _yanshan_color)
	yanshan_root.add_child(terrain)

	# 2. Translucent Sparkling River & Bay Water Plane
	var water := MeshInstance3D.new()
	var wplane := PlaneMesh.new()
	wplane.size = Vector2(34.5, 26.5)
	water.mesh = wplane
	water.position = Vector3(0.0, 0.36, 0.0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.16, 0.56, 0.64, 0.84)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.16
	wmat.metallic = 0.18
	water.material_override = wmat
	yanshan_root.add_child(water)

	# 3. Stylized Pine & Bamboo Groves scattered organically across hills
	var m_tree_dk := _mat(Color("1d543c"), 0.86)
	var m_tree_lt := _mat(Color("2f764b"), 0.84)
	var m_trunk := _mat(Color("5b4332"), 0.90)
	var tree_spots := [
		Vector2(-3.2, -5.6), Vector2(-1.8, -6.2), Vector2(2.6, -5.5), Vector2(4.2, -4.4),
		Vector2(-4.8, -3.2), Vector2(-6.5, -2.5), Vector2(-3.8, -1.4), Vector2(-1.2, -1.8),
		Vector2(3.6, -2.2), Vector2(5.4, -3.0), Vector2(6.8, -4.8), Vector2(-7.8, -4.8),
		Vector2(-10.5, -1.6), Vector2(-4.2, 2.2), Vector2(-2.2, 3.8), Vector2(2.8, 3.4),
		Vector2(5.2, 4.8), Vector2(-1.6, 6.2), Vector2(3.8, -6.8), Vector2(-5.4, -6.8),
	]
	for idx in tree_spots.size():
		var tp: Vector2 = tree_spots[idx]
		var th := _yanshan_height(tp.x, tp.y)
		if th < 0.55:
			continue
		var s := 0.85 + float(idx % 3) * 0.22
		_add_cyl(yanshan_root, Vector3(tp.x, th + 0.18 * s, tp.y), 0.06 * s, 0.08 * s, 0.36 * s, m_trunk, 6)
		_add_cyl(yanshan_root, Vector3(tp.x, th + 0.62 * s, tp.y), 0.04, 0.44 * s, 0.78 * s, m_tree_dk if idx % 2 == 0 else m_tree_lt, 7)

	# 4. LANDMARK 1 (Upper-Center Hill): 【烟山基地】 — Watchtower, Dongling Red Pavilion, Camp Tents & Beacon!
	var m_wall := _mat(Color("e8e4d8"), 0.78)
	var m_roof := _mat(Color("2b3842"), 0.68)
	var m_red := _mat(Color("c43c32"), 0.60)
	var m_tent := _mat(Color("3a6e54"), 0.82)
	var m_pad := _mat(Color("3d484c"), 0.72)
	var base_p := Vector3(0.4, _yanshan_height(0.4, -4.8), -4.8)
	var base_grp := Node3D.new()
	base_grp.position = base_p
	yanshan_root.add_child(base_grp)
	# Flat summit stone terrace
	_add_cyl(base_grp, Vector3(0, -0.08, 0), 1.65, 1.95, 0.28, m_pad, 14)
	# Iconic Dongling Pavilion (red pillars + upturned dark tile pagoda roof!)
	_add_box(base_grp, Vector3(-0.48, 0.38, -0.22), Vector3(0.72, 0.54, 0.72), m_red)
	_add_cyl(base_grp, Vector3(-0.48, 0.84, -0.22), 0.10, 0.74, 0.46, m_roof, 4)
	# Tactical Radio Watchtower & Command Tent
	_add_box(base_grp, Vector3(0.58, 0.56, 0.18), Vector3(0.42, 0.92, 0.42), m_wall)
	_add_box(base_grp, Vector3(0.58, 1.08, 0.18), Vector3(0.56, 0.14, 0.56), m_roof)
	_add_cyl(base_grp, Vector3(0.58, 1.48, 0.18), 0.03, 0.04, 0.74, _mat(Color("a4c0c4"), 0.4, 0.6), 6)
	_add_box(base_grp, Vector3(-0.18, 0.24, 0.72), Vector3(0.76, 0.34, 0.48), m_tent, 0.25)
	_add_beacon_ring(yanshan_root, base_p + Vector3(0, 0.14, 0), Color("58f0b8"), 1.52)

	# 5. LANDMARK 2 (Bottom-Left): 【鲸塘中心小学（暂未开放）】 — Teaching Building, Flagpole & Red Oval Track!
	var sch_p := Vector3(-7.6, _yanshan_height(-7.6, 4.4), 4.4)
	var sch_grp := Node3D.new()
	sch_grp.position = sch_p
	yanshan_root.add_child(sch_grp)
	var m_sch_wall := _mat(Color("ede6d4"), 0.74)
	var m_sch_roof := _mat(Color("b64b3a"), 0.68)
	var m_track := _mat(Color("b85642"), 0.86)
	var m_pitch := _mat(Color("489a56"), 0.88)
	# Courtyard concrete apron
	_add_box(sch_grp, Vector3(0, 0.04, 0), Vector3(4.2, 0.08, 2.8), _mat(Color("aeb5b0"), 0.84))
	# Main U-shaped Chinese Primary School Teaching Building
	_add_box(sch_grp, Vector3(-0.75, 0.42, -0.58), Vector3(2.2, 0.72, 0.68), m_sch_wall)
	_add_box(sch_grp, Vector3(-0.75, 0.84, -0.58), Vector3(2.36, 0.16, 0.80), m_sch_roof)
	_add_box(sch_grp, Vector3(-1.55, 0.34, 0.18), Vector3(0.62, 0.56, 1.05), m_sch_wall)
	_add_box(sch_grp, Vector3(-1.55, 0.68, 0.18), Vector3(0.72, 0.14, 1.15), m_sch_roof)
	# Flagpole + tiny crimson flag in front courtyard
	_add_cyl(sch_grp, Vector3(-0.55, 0.68, 0.35), 0.025, 0.03, 1.25, _mat(Color("cfd8dc"), 0.3, 0.7), 6)
	_add_box(sch_grp, Vector3(-0.36, 1.18, 0.35), Vector3(0.36, 0.22, 0.04), m_red)
	# Miniature Red-Clay Oval Sports Track + Green Soccer Field
	_add_box(sch_grp, Vector3(0.95, 0.10, 0.25), Vector3(1.75, 0.06, 1.85), m_track)
	_add_box(sch_grp, Vector3(0.95, 0.14, 0.25), Vector3(1.22, 0.05, 1.32), m_pitch)

	# 6. LANDMARK 3 (Mid-Right Riverbend): 【诚庄村河港（暂未开放）】 — Jiangnan White-Wall Cottages, Stone Arch Bridge & Wharf!
	var port_p := Vector3(8.2, maxf(0.46, _yanshan_height(8.2, 0.2)), 0.2)
	var port_grp := Node3D.new()
	port_grp.position = port_p
	yanshan_root.add_child(port_grp)
	var m_wood := _mat(Color("7b5638"), 0.84)
	var m_stone := _mat(Color("9ea5a0"), 0.82)
	var m_boat := _mat(Color("5c3d28"), 0.78)
	# Cluster of 5 Jiangnan white-wall black-tile cottages
	for c_spec in [
		[Vector3(-0.95, 0.28, -0.75), Vector3(0.92, 0.54, 0.66), 0.12],
		[Vector3(0.15, 0.32, -0.92), Vector3(1.06, 0.62, 0.68), -0.08],
		[Vector3(1.18, 0.26, -0.42), Vector3(0.84, 0.48, 0.62), 0.22],
		[Vector3(-0.55, 0.24, 0.15), Vector3(0.86, 0.46, 0.58), -0.15],
		[Vector3(0.55, 0.26, 0.05), Vector3(0.90, 0.50, 0.60), 0.06],
	]:
		var cp: Vector3 = c_spec[0]
		var cs: Vector3 = c_spec[1]
		var cr: float = c_spec[2]
		_add_box(port_grp, cp, cs, m_wall, cr)
		_add_box(port_grp, cp + Vector3(0, cs.y * 0.5 + 0.08, 0), Vector3(cs.x + 0.14, 0.16, cs.z + 0.14), m_roof, cr)
	# Wooden River Wharf Pier extending into Chengzhuang River Harbor
	_add_box(port_grp, Vector3(0.15, 0.02, 1.25), Vector3(0.76, 0.14, 1.55), m_wood)
	_add_box(port_grp, Vector3(0.15, 0.04, 1.85), Vector3(1.65, 0.14, 0.54), m_wood)
	# Stone Arch Bridge spanning the creek
	_add_box(port_grp, Vector3(-1.85, 0.12, 1.15), Vector3(1.55, 0.26, 0.46), m_stone, -0.22)
	# Two tiny moored wooden riverboats on water
	_add_box(port_grp, Vector3(1.15, -0.06, 1.65), Vector3(0.32, 0.14, 0.84), m_boat, 0.35)
	_add_box(port_grp, Vector3(-0.85, -0.06, 1.82), Vector3(0.28, 0.12, 0.74), m_boat, -0.25)

	# Subtle dotted tactical supply roads connecting Yanshan Base <-> Jingtang School <-> Chengzhuang Port!
	var m_road := _mat(Color("d8c89c"), 0.88)
	for seg_pair in [[Vector2(0.4, -3.2), Vector2(-6.2, 3.6)], [Vector2(1.4, -3.4), Vector2(6.8, -0.2)], [Vector2(-5.4, 4.0), Vector2(6.4, 0.8)]]:
		var a: Vector2 = seg_pair[0]
		var b: Vector2 = seg_pair[1]
		for si in range(1, 9):
			var t := float(si) / 9.0
			var p2 := a.lerp(b, t) + Vector2(sin(t * PI) * 0.6, cos(t * PI) * 0.35)
			var ph := _yanshan_height(p2.x, p2.y)
			if ph > 0.38:
				_add_box(yanshan_root, Vector3(p2.x, ph + 0.05, p2.y), Vector3(0.46, 0.08, 0.28), m_road, (b - a).angle())

	# 7. Drifting Soft Jiangnan Mist Clouds
	var m_cloud := StandardMaterial3D.new()
	m_cloud.albedo_color = Color(0.95, 0.98, 0.96, 0.52)
	m_cloud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_cloud.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for ci in range(4):
		var cl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.6 + float(ci % 2) * 0.55
		sm.height = 0.55
		cl.mesh = sm
		cl.position = Vector3(-9.5 + ci * 6.4, 5.2 + float(ci % 2) * 0.7, -5.8 + float(ci % 3) * 2.2)
		cl.scale = Vector3(1.8, 0.45, 0.95)
		cl.material_override = m_cloud
		yanshan_root.add_child(cl)
		cloud_nodes.append({"node": cl, "base_x": cl.position.x, "speed": 0.28 + ci * 0.06})


# ---------------------------------------------------------------------------
# DIORAMA 2: 阿萨拉行动 (North African Desert Dunes + Zero Dam Fortress + Oasis)
# ---------------------------------------------------------------------------
func _ahsarah_height(x: float, z: float) -> float:
	# Dramatic north canyon mesas framing Zero Dam gorge (-0.4, -4.3)
	var d_mesa_w := Vector2((x + 6.2) * 0.78, z + 5.2).length()
	var h_mw := 3.85 * exp(-(d_mesa_w * d_mesa_w) / 18.0)
	var d_mesa_e := Vector2((x - 6.8) * 0.78, z + 5.0).length()
	var h_me := 3.95 * exp(-(d_mesa_e * d_mesa_e) / 20.0)
	# Southeast high mesa plateau for HAAVK Space City
	var d_se := Vector2(x - 8.8, z - 1.9).length()
	var h_se := 1.75 * exp(-(d_se * d_se) / 14.0)
	# Sweeping wind-carved sand dune ripples across south desert
	var dunes := 0.42 * sin(x * 0.36 + z * 0.22) + 0.24 * cos(x * 0.20 - z * 0.40)
	var h := 0.85 + h_mw + h_me + h_se + dunes
	# Carve central North-South canyon gorge through Zero Dam (x ~ -0.4)
	var gorge_x := -0.4 + sin(z * 0.28) * 1.15
	var d_gorge := absf(x - gorge_x)
	if d_gorge < 2.6:
		var carve := 1.0 - smoothstep(0.95, 2.6, d_gorge)
		var floor_h := 0.26 if z < -4.2 else 0.42
		h = lerpf(h, floor_h, carve * 0.90)
	# Southwest oasis basin around Brakkesh (-8.2, 4.9)
	var d_oa := Vector2(x + 8.2, z - 4.9).length()
	if d_oa < 3.6:
		h = lerpf(0.68, h, smoothstep(1.8, 3.6, d_oa))
	return maxf(0.18, h)


func _ahsarah_color(x: float, z: float, h: float) -> Color:
	# Oasis palm greenery in southwest
	if Vector2(x + 8.2, z - 4.9).length() < 2.8 and h < 0.92:
		return Color("568448")
	if h < 0.40 and z < -3.6:
		return Color("2a7a88")  # Dam reservoir water bed
	if h < 0.78:
		return Color("b8905a")  # Dry wadi canyon floor
	if h < 1.95:
		var band := 0.5 + 0.5 * sin(x * 0.65 + z * 0.45)
		return Color("d6aa68").lerp(Color("c68e4c"), band * 0.55)  # Golden Sahara dunes
	return Color("a86640").lerp(Color("874b32"), clampf((h - 1.95) / 2.2, 0.0, 1.0))  # Terracotta canyon cliffs


func _build_ahsarah_diorama():
	ahsarah_root = Node3D.new()
	ahsarah_root.name = "AhsarahDiorama"
	sub_viewport.add_child(ahsarah_root)

	# 1. Sculpted Desert Dunes & Red-Rock Canyon Relief
	var terrain := _build_terrain_mesh(17.5, 13.5, 58, 44, _ahsarah_height, _ahsarah_color)
	ahsarah_root.add_child(terrain)

	# 2. Sparkling Turquoise Dam Reservoir behind Zero Dam (north of z=-4.5)
	var res_water := MeshInstance3D.new()
	var rplane := PlaneMesh.new()
	rplane.size = Vector2(9.2, 7.6)
	res_water.mesh = rplane
	res_water.position = Vector3(-0.4, 1.12, -8.3)
	var rwmat := StandardMaterial3D.new()
	rwmat.albedo_color = Color(0.14, 0.62, 0.72, 0.88)
	rwmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rwmat.roughness = 0.14
	rwmat.metallic = 0.22
	res_water.material_override = rwmat
	ahsarah_root.add_child(res_water)

	# 3. LANDMARK 1 (North-Central Gorge): 【阿萨拉堡垒】 — Zero Dam Wall + Sandstone Fortress + Twin Babel Towers!
	var m_concrete := _mat(Color("b8b2a2"), 0.76)
	var m_sandstone := _mat(Color("cfa36e"), 0.80)
	var m_sand_dark := _mat(Color("9a6e42"), 0.84)
	var m_haavk_w := _mat(Color("dce6ea"), 0.45, 0.22)
	var m_cyan := _mat(Color("3ae8ff"), 0.2, 0.1, true, Color("3ae8ff"), 1.6)

	var fort_grp := Node3D.new()
	fort_grp.position = Vector3(-0.4, 0.0, -4.3)
	ahsarah_root.add_child(fort_grp)
	# Monumental Zero Dam Concrete Wall spanning the canyon gorge!
	_add_box(fort_grp, Vector3(0.0, 1.25, -0.35), Vector3(5.6, 2.15, 0.82), m_concrete)
	_add_box(fort_grp, Vector3(0.0, 2.38, -0.35), Vector3(5.8, 0.18, 1.04), _mat(Color("787a78"), 0.72))
	# Spillway chutes on dam face
	for sx in [-1.4, -0.45, 0.45, 1.4]:
		_add_box(fort_grp, Vector3(sx, 1.15, 0.12), Vector3(0.32, 1.75, 0.22), _mat(Color("6c7678"), 0.66))
	# Administrative Sandstone Fortress on east abutment
	_add_box(fort_grp, Vector3(2.45, 1.75, 0.85), Vector3(2.15, 1.18, 1.55), m_sandstone)
	_add_box(fort_grp, Vector3(2.45, 2.42, 0.85), Vector3(2.28, 0.18, 1.68), m_sand_dark)
	# Twin HAAVK Babel Comms Towers rising dramatically above the fortress!
	_add_cyl(fort_grp, Vector3(1.65, 2.85, 0.45), 0.16, 0.24, 2.35, m_haavk_w, 8)
	_add_cyl(fort_grp, Vector3(1.65, 4.10, 0.45), 0.04, 0.06, 0.65, m_cyan, 6)
	_add_cyl(fort_grp, Vector3(3.15, 2.65, 0.62), 0.14, 0.20, 1.85, m_haavk_w, 8)
	# West Cement Plant twin silos
	for cx in [-2.65, -2.10]:
		_add_cyl(fort_grp, Vector3(cx, 1.85, 1.25), 0.26, 0.26, 1.15, m_concrete, 10)
	_add_beacon_ring(ahsarah_root, Vector3(-0.4, 2.52, -4.3), Color("ffb84d"), 1.65)

	# 4. LANDMARK 2 (Southwest Oasis): 【巴克什古城外围（暂未开放）】 — Mudbrick Domes, Minaret & Oasis Palms
	var brk_p := Vector3(-7.5, _ahsarah_height(-7.5, 4.3), 4.3)
	var brk_grp := Node3D.new()
	brk_grp.position = brk_p
	ahsarah_root.add_child(brk_grp)
	for b_spec in [
		[Vector3(-0.85, 0.34, -0.45), Vector3(1.15, 0.68, 0.95)],
		[Vector3(0.45, 0.28, -0.65), Vector3(0.95, 0.56, 0.85)],
		[Vector3(-0.25, 0.26, 0.65), Vector3(1.25, 0.52, 0.78)],
	]:
		_add_box(brk_grp, b_spec[0], b_spec[1], m_sandstone)
	var dome := MeshInstance3D.new()
	var dsm := SphereMesh.new()
	dsm.radius = 0.44
	dsm.height = 0.66
	dome.mesh = dsm
	dome.position = Vector3(-0.85, 0.72, -0.45)
	dome.material_override = _mat(Color("dfbe74"), 0.52, 0.22)
	brk_grp.add_child(dome)
	_add_cyl(brk_grp, Vector3(0.75, 0.78, -0.65), 0.12, 0.16, 1.48, m_sand_dark, 8)
	# Oasis turquoise pond & 3 stylized desert palm trees
	_add_cyl(brk_grp, Vector3(1.25, 0.04, 0.65), 0.82, 0.88, 0.08, rwmat, 14)
	var m_palm := _mat(Color("3f7c3b"), 0.82)
	for pp in [Vector2(1.85, 0.25), Vector2(0.75, 1.25), Vector2(1.55, 1.20)]:
		_add_cyl(brk_grp, Vector3(pp.x, 0.36, pp.y), 0.04, 0.06, 0.72, _mat(Color("6e5034"), 0.88), 6)
		_add_cyl(brk_grp, Vector3(pp.x, 0.72, pp.y), 0.36, 0.08, 0.22, m_palm, 7)

	# 5. LANDMARK 3 (Southeast Mesa): 【哈夫克航天禁区（暂未开放）】 — Futuristic Launch Spire & Radar Dishes
	var spc_p := Vector3(8.0, _ahsarah_height(8.0, 1.6), 1.6)
	var spc_grp := Node3D.new()
	spc_grp.position = spc_p
	ahsarah_root.add_child(spc_grp)
	_add_box(spc_grp, Vector3(0, 0.10, 0), Vector3(3.2, 0.20, 2.4), _mat(Color("66747e"), 0.62))
	_add_box(spc_grp, Vector3(-0.75, 0.56, -0.25), Vector3(1.15, 0.76, 0.95), m_haavk_w)
	# Launch Gantry + sleek rocket spire
	_add_box(spc_grp, Vector3(0.75, 1.25, -0.10), Vector3(0.32, 2.25, 0.32), _mat(Color("8898a2"), 0.45, 0.4))
	_add_cyl(spc_grp, Vector3(0.32, 1.12, -0.10), 0.06, 0.16, 1.95, m_haavk_w, 10)
	_add_cyl(spc_grp, Vector3(-0.75, 1.08, 0.55), 0.34, 0.08, 0.24, m_haavk_w, 10)
	_add_cyl(spc_grp, Vector3(0.75, 2.45, -0.10), 0.06, 0.06, 0.22, m_cyan, 8)

	# Desert tactical convoy tracks connecting Zero Dam <-> Brakkesh Oasis <-> Space Base!
	var m_droad := _mat(Color("8a6a44"), 0.90)
	for seg_pair in [[Vector2(-0.4, -2.5), Vector2(-6.4, 3.6)], [Vector2(1.2, -2.6), Vector2(6.6, 1.2)]]:
		var a: Vector2 = seg_pair[0]
		var b: Vector2 = seg_pair[1]
		for si in range(1, 9):
			var t := float(si) / 9.0
			var p2 := a.lerp(b, t)
			var ph := _ahsarah_height(p2.x, p2.y)
			_add_box(ahsarah_root, Vector3(p2.x, ph + 0.05, p2.y), Vector3(0.48, 0.08, 0.28), m_droad, (b - a).angle())

	ahsarah_root.hide()


# ---------------------------------------------------------------------------
# 2D Floating Projected Tactical Pins & Theater Header Chrome
# ---------------------------------------------------------------------------
func _build_overlay_chrome():
	# Soft top vignette bar over the 3D map for crisp header readability
	var top_bar := ColorRect.new()
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(size.x, 78)
	top_bar.color = Color(0.025, 0.052, 0.068, 0.72)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	theater_header_lbl = game._text(self, "🏔 烟山行动 · 江南山地三维作战沙盘", Vector2(26, 12), Vector2(720, 32), 22, Color("f6fffa"))
	theater_sub_lbl = game._text(self, "点击沙盘上的据点图标查看情报并部署出击", Vector2(28, 46), Vector2(780, 22), 13, Color("9ce8cf"))

	pins_layer = Control.new()
	pins_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pins_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(pins_layer)


func _rebuild_pins():
	for ch in pins_layer.get_children():
		pins_layer.remove_child(ch)
		ch.queue_free()
	pin_buttons.clear()

	var list: Array = LANDMARKS.get(current_theater, [])
	var ah_unlocked: bool = game.rules.is_map_unlocked("ahsarah")
	for lm in list:
		var lid := str(lm["id"])
		var is_open := bool(lm["open"])
		var effective_open := is_open
		var badge_txt := str(lm["badge"])
		if lid == "ahsarah_fortress" and not ah_unlocked:
			effective_open = false
			badge_txt = "🔒 阿萨拉堡垒（古洞解锁）"

		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		var pill_w := 168 if effective_open else 234
		holder.size = Vector2(pill_w, 52)
		pins_layer.add_child(holder)

		var btn := Button.new()
		btn.position = Vector2(0, 0)
		btn.size = Vector2(pill_w, 36)
		btn.text = badge_txt
		btn.add_theme_font_size_override("font_size", 14 if effective_open else 12)
		btn.pressed.connect(func():
			select_landmark(lid)
		)
		holder.add_child(btn)

		# Small pointer stem dot beneath the floating pin pill
		var stem := ColorRect.new()
		stem.position = Vector2(pill_w * 0.5 - 2.0, 36)
		stem.size = Vector2(4, 14)
		stem.color = (lm["accent"] as Color) if effective_open else Color("7c8f98")
		stem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(stem)

		pin_buttons[lid] = {
			"holder": holder,
			"btn": btn,
			"stem": stem,
			"world_pos": lm["pos"],
			"data": lm,
			"effective_open": effective_open,
		}
	_style_pins()
	_update_pin_positions()


func _style_pins():
	for lid in pin_buttons:
		var entry: Dictionary = pin_buttons[lid]
		var btn: Button = entry["btn"]
		var lm: Dictionary = entry["data"]
		var is_sel: bool = (str(lid) == selected_landmark_id)
		var eff_open := bool(entry["effective_open"])
		var acc: Color = lm["accent"]
		if is_sel:
			game._style_tactical_button(
				btn,
				acc.darkened(0.58) if eff_open else Color("2a343c"),
				acc if eff_open else Color("c8d4dc"),
				Color("fffcf0")
			)
		elif eff_open:
			game._style_tactical_button(btn, Color(0.055, 0.14, 0.13, 0.92), acc, Color("e8fff6"))
		else:
			game._style_tactical_button(btn, Color(0.08, 0.10, 0.12, 0.86), Color("566872"), Color("b2c2ca"))


func set_theater(theater: String, emit_signal_now: bool = true):
	if not (theater in ["story", "yanshan", "ahsarah"]):
		theater = "yanshan"
	current_theater = theater
	var is_desert := (theater == "ahsarah")
	if is_instance_valid(yanshan_root):
		yanshan_root.visible = not is_desert
	if is_instance_valid(ahsarah_root):
		ahsarah_root.visible = is_desert

	# Retune miniature diorama atmosphere & lighting per theater!
	if is_instance_valid(world_env) and world_env.environment != null:
		var env := world_env.environment
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		if is_desert:
			sm.sky_top_color = Color("3c6e96")
			sm.sky_horizon_color = Color("e8c488")
			sm.ground_bottom_color = Color("765232")
			sm.ground_horizon_color = Color("d8aa6e")
			env.ambient_light_color = Color("f0cca0")
			env.fog_light_color = Color("e2c08a")
			env.fog_density = 0.0075
			sun_light.light_color = Color("ffe6ba")
			sun_light.light_energy = 1.65
			theater_header_lbl.text = "🏜 阿萨拉行动 · 零号大坝与荒漠三维战区沙盘"
			theater_sub_lbl.text = "2035 北非荒漠战区 · 点击据点【阿萨拉堡垒】部署行动，其余地点规划筹建中"
		elif theater == "story":
			sm.sky_top_color = Color("3c5e7c")
			sm.sky_horizon_color = Color("e0bc86")
			sm.ground_bottom_color = Color("223834")
			sm.ground_horizon_color = Color("8aa88e")
			env.ambient_light_color = Color("d8d6b2")
			env.fog_light_color = Color("c8bc9c")
			env.fog_density = 0.009
			sun_light.light_color = Color("ffd89c")
			sun_light.light_energy = 1.50
			theater_header_lbl.text = "📖 剧情模式 · 烟山初行沉浸式任务总览"
			theater_sub_lbl.text = "推荐首次游玩的少年游侠由此启程 · 5–8 分钟完整体验听词、侦察、交锋与撤离"
		else:
			sm.sky_top_color = Color("285870")
			sm.sky_horizon_color = Color("8cc4b8")
			sm.ground_bottom_color = Color("1f3834")
			sm.ground_horizon_color = Color("6b9c8e")
			env.ambient_light_color = Color("9cd4c8")
			env.fog_light_color = Color("8fc0b8")
			env.fog_density = 0.0085
			sun_light.light_color = Color("fff0d2")
			sun_light.light_energy = 1.45
			theater_header_lbl.text = "🏔 烟山行动 · 江南山地三维作战沙盘"
			theater_sub_lbl.text = "中上【烟山基地】已开放出击 · 左下【鲸塘中心小学】与右中【诚庄村河港】待后续版本开放"

	var list: Array = LANDMARKS.get(theater, [])
	if not list.is_empty():
		selected_landmark_id = str(list[0]["id"])
		target_focus_offset = Vector3.ZERO
	_rebuild_pins()
	if emit_signal_now and not list.is_empty():
		landmark_selected.emit(selected_landmark_id, list[0])


func select_landmark(landmark_id: String):
	var list: Array = LANDMARKS.get(current_theater, [])
	for lm in list:
		if str(lm["id"]) == landmark_id:
			selected_landmark_id = landmark_id
			var p: Vector3 = lm["pos"]
			target_focus_offset = Vector3(p.x * 0.22, 0.0, p.z * 0.18)
			_style_pins()
			landmark_selected.emit(landmark_id, lm)
			return


func refresh_unlock_states():
	_rebuild_pins()


func set_rendering_active(active: bool):
	if is_instance_valid(sub_viewport):
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


func _update_pin_positions():
	if not is_instance_valid(camera):
		return
	for lid in pin_buttons:
		var entry: Dictionary = pin_buttons[lid]
		var wp: Vector3 = entry["world_pos"]
		var holder: Control = entry["holder"]
		if camera.is_position_behind(wp):
			holder.hide()
			continue
		holder.show()
		var sp := camera.unproject_position(wp)
		# Clamp cleanly inside visible 3D map region (above bottom deployment drawer y < 495!)
		var px := clampf(sp.x - holder.size.x * 0.5, 16.0, size.x - holder.size.x - 16.0)
		var py := clampf(sp.y - holder.size.y, 82.0, 456.0)
		holder.position = Vector2(px, py)


func _process(delta: float):
	var active := visible and is_visible_in_tree()
	set_rendering_active(active)
	if not active or not is_instance_valid(camera):
		return
	anim_clock += delta
	cam_focus_offset = cam_focus_offset.lerp(target_focus_offset, minf(delta * 4.5, 1.0))

	# Gentle cinematic breathing orbit over the 3D miniature strategic relief map!
	var sway_x := sin(anim_clock * 0.34) * 0.95
	var sway_y := cos(anim_clock * 0.26) * 0.28
	var base_cam := Vector3(0.0, 16.5, 22.8)
	var base_look := Vector3(0.0, 0.5, 0.6)
	if current_theater == "story":
		base_cam = Vector3(-4.5, 11.8, 17.5)
		base_look = Vector3(0.4, 1.8, -3.2)
	elif current_theater == "ahsarah":
		base_cam = Vector3(0.2, 16.2, 22.4)
		base_look = Vector3(-0.2, 0.8, 0.5)

	camera.position = base_cam + Vector3(sway_x, sway_y, 0.0) + cam_focus_offset * 0.75
	camera.look_at(base_look + cam_focus_offset, Vector3.UP)

	# Pulse active deployment beacon rings & drift Jiangnan clouds
	for b in beacon_rings:
		var n: Node3D = b["node"]
		if is_instance_valid(n):
			var p := 1.0 + sin(anim_clock * 2.8) * 0.12
			n.scale = Vector3(p, 1.0, p)
			n.rotation.y = anim_clock * 0.6
	for cl in cloud_nodes:
		var cn: Node3D = cl["node"]
		if is_instance_valid(cn):
			cn.position.x = fmod(float(cl["base_x"]) + anim_clock * float(cl["speed"]) + 18.0, 36.0) - 18.0

	_update_pin_positions()
