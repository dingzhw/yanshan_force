extends Control
## Grand 3D Tactical Relief War-Table & 3D Volumetric Landmark Beacons (v0.9.6).
## Renders bespoke Ultra-HD stylized aerial topographic maps (1600x900) mounted onto a
## gently sculpted 3D tactical relief war-table inside an isolated SubViewport (own_world_3d = true),
## crowned with custom-sculpted 3D metallic/holographic rotating landmark beacons,
## parabolic 3D data-link arcs, and an animated holographic radar scan sweep.
## Automatically disables SubViewport rendering whenever hidden during combat -> ZERO in-match FPS cost!

signal landmark_selected(landmark_id: String, meta: Dictionary)

const MAP_TEXTURES := {
	"yanshan": "res://assets/warmap/map_yanshan_hd.png",
	"ahsarah": "res://assets/warmap/map_ahsarah_hd.png",
	"story": "res://assets/warmap/map_story_hd.png",
}

const TABLE_W := 24.0
const TABLE_D := 13.5  # Exact 16:9 aspect ratio matching 1600x900 HD relief textures

# Landmark coordinates use normalized map UV (u: 0=left..1=right, v: 0=top..1=bottom)
# calibrated directly to the architectural landmarks on each HD map!
const LANDMARKS := {
	"yanshan": [
		{
			"id": "yanshan_base",
			"code": "SEC-01A",
			"title": "烟山基地",
			"badge": "烟山基地",
			"subtitle": "已开放 · 江南山地搜撤核心战区",
			"uv": Vector2(0.48, 0.27),
			"icon_3d": "base_diamond",
			"open": true,
			"map_id": "yanshan",
			"accent": Color("3ef0b4"),
			"desc": "烟山北麓高地前哨，串联东岭望稻亭、古石拱桥、竹海总坛与烟霞古洞。15 分钟普通行动 / 20 分钟机密行动，肃清 3 座营地并击败首领即可携宝撤离！",
		},
		{
			"id": "jingtang_school",
			"code": "SEC-01B",
			"title": "鲸塘中心小学",
			"badge": "鲸塘中心小学（暂未开放）",
			"subtitle": "暂未开放 · 后续版本规划中",
			"uv": Vector2(0.27, 0.70),
			"icon_3d": "school_crest",
			"open": false,
			"map_id": "yanshan",
			"accent": Color("7cc8dc"),
			"desc": "【暂未开放 · 规划中】位于烟山西麓山脚的乡土校园与操场。未来版本将开放校园情景英语互动与课堂词汇支线探索，敬请期待！",
		},
		{
			"id": "chengzhuang_port",
			"code": "SEC-01C",
			"title": "诚庄村河港",
			"badge": "诚庄村河港（暂未开放）",
			"subtitle": "暂未开放 · 后续版本规划中",
			"uv": Vector2(0.77, 0.54),
			"icon_3d": "port_anchor",
			"open": false,
			"map_id": "yanshan",
			"accent": Color("6ad4c4"),
			"desc": "【暂未开放 · 规划中】粉墙黛瓦的诚庄水乡码头与古石桥河港。未来版本将拓展水陆双线潜行与货栈奇珍搜撤玩法，敬请期待！",
		},
	],
	"ahsarah": [
		{
			"id": "ahsarah_fortress",
			"code": "SEC-02A",
			"title": "阿萨拉堡垒",
			"badge": "阿萨拉堡垒",
			"subtitle": "零号大坝 · 沙漠堡垒搜撤战区",
			"uv": Vector2(0.71, 0.24),
			"icon_3d": "fortress_bastion",
			"open": true,
			"map_id": "ahsarah",
			"accent": Color("ffb238"),
			"desc": "扼守北非峡谷咽喉的零号大坝与雷达行政堡垒！融汇水泥厂、巴克什集市与哈夫克变电站：普通迎战「赤枭·赛伊德」，机密直面「军阀·雷斯」，夺取非洲之心与曼德尔砖！",
		},
		{
			"id": "brakkesh_oldtown",
			"code": "SEC-02B",
			"title": "巴克什古城外围",
			"badge": "巴克什古城外围（暂未开放）",
			"subtitle": "暂未开放 · 后续荒漠拓展规划",
			"uv": Vector2(0.26, 0.69),
			"icon_3d": "desert_dome",
			"open": false,
			"map_id": "ahsarah",
			"accent": Color("d2ae76"),
			"desc": "【暂未开放 · 规划中】绿洲环抱的阿萨拉古城外围巷战区，拟于后续版本拓展多层屋顶立体对抗与遗迹密室，敬请期待！",
		},
		{
			"id": "space_city",
			"code": "SEC-02C",
			"title": "哈夫克航天禁区",
			"badge": "哈夫克航天禁区（暂未开放）",
			"subtitle": "暂未开放 · 后续高阶拓展规划",
			"uv": Vector2(0.83, 0.62),
			"icon_3d": "orbital_spire",
			"open": false,
			"map_id": "ahsarah",
			"accent": Color("58d8f6"),
			"desc": "【暂未开放 · 规划中】沙漠东南高原上的哈夫克秘密发射台与科研高塔，拟于后续版本作为终极高难英语特战禁区登场！",
		},
	],
	"story": [
		{
			"id": "story_ch1",
			"code": "STORY-01",
			"title": "第一章 · 烟山初行",
			"badge": "第一章：烟山初行（序章）",
			"subtitle": "已开放 · 5–8 分钟沉浸式教学剧情",
			"uv": Vector2(0.46, 0.25),
			"icon_3d": "story_star",
			"open": true,
			"map_id": "yanshan",
			"accent": Color("ffd76a"),
			"desc": "跟随陈向导深入烟山谷地，查明东岭望稻亭失联信标背后的英文密电线索，完成你的首次游侠实战演练！",
		},
		{
			"id": "story_ch2",
			"code": "STORY-02",
			"title": "第二章 · 古洞秘闻",
			"badge": "第二章：烟霞古洞深处（筹备中）",
			"subtitle": "筹备中 · 后续剧情章节",
			"uv": Vector2(0.20, 0.47),
			"icon_3d": "cave_crystal",
			"open": false,
			"map_id": "yanshan",
			"accent": Color("82c8bc"),
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

var map_textures: Dictionary = {}
var theater_roots: Dictionary = {}  # theater_id -> Node3D
var scan_beams: Dictionary = {}     # theater_id -> MeshInstance3D
var beacon_anims: Array = []        # [{emblem, outer_ring, inner_ring, pulse_ring, theater, id, base_y, accent}]

var pins_layer: Control
var pin_buttons: Dictionary = {}    # landmark_id -> {holder, btn, rail, dot, world_pos, data, effective_open}
var theater_header_lbl: Label
var theater_code_lbl: Label
var theater_sub_lbl: Label
var header_rail: ColorRect
var live_coord_lbl: Label

var current_theater: String = "yanshan"
var selected_landmark_id: String = "yanshan_base"
var anim_clock: float = 0.0
var cam_focus_offset: Vector3 = Vector3.ZERO
var target_focus_offset: Vector3 = Vector3.ZERO
var mouse_parallax: Vector2 = Vector2.ZERO


func setup(g, rect: Rect2):
	game = g
	position = rect.position
	size = rect.size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS

	_load_hd_textures()
	_build_viewport()
	_build_all_theaters()
	_build_overlay_chrome()
	set_theater("yanshan", true)


func _load_hd_textures():
	for tid in MAP_TEXTURES:
		var path: String = MAP_TEXTURES[tid]
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				map_textures[tid] = tex


func _mat(col: Color, rough: float = 0.45, met: float = 0.55, unshaded: bool = false, emit_col: Color = Color(0, 0, 0, 0), emit_e: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = rough
	m.metallic = met
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit_col
		m.emission_energy_multiplier = emit_e
	return m


func _uv_to_world(uv: Vector2, theater: String) -> Vector3:
	var x := (uv.x - 0.5) * TABLE_W
	var z := (uv.y - 0.5) * TABLE_D
	var y := _relief_height(uv.x, uv.y, theater)
	return Vector3(x, y, z)


func _relief_height(u: float, v: float, theater: String) -> float:
	# Subtle genuine 3D topographic relief under the HD terrain artwork so lighting & beacons feel tactile!
	var h := 0.08 * sin(u * PI) * sin(v * PI)
	if theater == "yanshan":
		# Gentle summit swell under Yanshan Base hill & north ridges
		var d_hill := Vector2((u - 0.46) * 1.4, (v - 0.28) * 1.6).length()
		h += 0.62 * exp(-(d_hill * d_hill) / 0.085)
		var d_nw := Vector2(u - 0.14, v - 0.14).length()
		h += 0.48 * exp(-(d_nw * d_nw) / 0.07)
		var d_ne := Vector2(u - 0.88, v - 0.14).length()
		h += 0.46 * exp(-(d_ne * d_ne) / 0.07)
	elif theater == "ahsarah":
		# Twin canyon mesa plateaus & fortress cliff flanking Zero Dam!
		var d_fort := Vector2((u - 0.72) * 1.3, (v - 0.26) * 1.5).length()
		h += 0.65 * exp(-(d_fort * d_fort) / 0.09)
		var d_west := Vector2((u - 0.24) * 1.3, (v - 0.24) * 1.5).length()
		h += 0.55 * exp(-(d_west * d_west) / 0.08)
		var d_mesa := Vector2((u - 0.82) * 1.4, (v - 0.68) * 1.6).length()
		h += 0.36 * exp(-(d_mesa * d_mesa) / 0.065)
	else:
		var d_peak := Vector2((u - 0.46) * 1.5, (v - 0.22) * 1.5).length()
		h += 0.50 * exp(-(d_peak * d_peak) / 0.08)
	return h


func _build_viewport():
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.own_world_3d = true
	sub_viewport.size = Vector2i(maxi(320, int(size.x)), maxi(240, int(size.y)))
	sub_viewport.msaa_3d = Viewport.MSAA_4X
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("070c11")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cde4ee")
	env.ambient_light_energy = 0.82
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	world_env = WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun_light.light_color = Color("fff5e4")
	sun_light.light_energy = 1.15
	sun_light.shadow_enabled = false
	sub_viewport.add_child(sun_light)

	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-35.0, -140.0, 0.0)
	fill_light.light_color = Color("5ec8e8")
	fill_light.light_energy = 0.58
	fill_light.shadow_enabled = false
	sub_viewport.add_child(fill_light)

	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.2
	camera.far = 140.0
	sub_viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 15.8, 11.4), Vector3(0.0, 0.0, 0.95), Vector3.UP)


func _build_relief_map_mesh(theater: String) -> MeshInstance3D:
	var seg_x := 48
	var seg_z := 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pts: Array = []
	var uvs: Array = []
	pts.resize((seg_z + 1) * (seg_x + 1))
	uvs.resize((seg_z + 1) * (seg_x + 1))

	for iz in range(seg_z + 1):
		var v := float(iz) / float(seg_z)
		var z := (v - 0.5) * TABLE_D
		for ix in range(seg_x + 1):
			var u := float(ix) / float(seg_x)
			var x := (u - 0.5) * TABLE_W
			var h := _relief_height(u, v, theater)
			var idx := iz * (seg_x + 1) + ix
			pts[idx] = Vector3(x, h, z)
			uvs[idx] = Vector2(u, v)

	for iz in range(seg_z):
		for ix in range(seg_x):
			var i00 := iz * (seg_x + 1) + ix
			var i10 := i00 + 1
			var i01 := i00 + (seg_x + 1)
			var i11 := i01 + 1
			for tri in [[i00, i10, i11], [i00, i11, i01]]:
				for vi in tri:
					st.set_uv(uvs[vi])
					st.add_vertex(pts[vi])

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HDMapRelief_" + theater
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	if map_textures.has(theater):
		mat.albedo_texture = map_textures[theater]
		mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	else:
		mat.albedo_color = Color("284844")
	mat.roughness = 0.72
	mat.metallic = 0.04
	# Keep HD colors ultra-vibrant & crisp under war-table lighting with gentle self-illumination!
	if map_textures.has(theater):
		mat.emission_enabled = true
		mat.emission_texture = map_textures[theater]
		mat.emission_energy_multiplier = 0.36
	mi.material_override = mat
	return mi


func _add_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, segs: int = 12, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_torus(parent: Node3D, pos: Vector3, inner_r: float, outer_r: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO, rings: int = 28) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = rings
	tm.ring_segments = 10
	mi.mesh = tm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_table_chassis(root: Node3D, accent: Color) -> MeshInstance3D:
	# Heavy brushed gunmetal tactical war-table deck & beveled metallic rails framing the HD map
	var m_deck := _mat(Color("0d141b"), 0.52, 0.72)
	var m_steel := _mat(Color("22303a"), 0.34, 0.85)
	var m_glow := _mat(accent, 0.20, 0.35, true, accent, 1.55)
	var m_grid := _mat(accent, 0.3, 0.1, true, accent, 0.65, 0.18)

	# Dark sub-deck beneath the relief map
	_add_box(root, Vector3(0, -0.34, 0), Vector3(TABLE_W + 2.8, 0.56, TABLE_D + 2.8), m_deck)
	# Brushed gunmetal top perimeter rail framing the 16:9 HD relief map
	var hw := TABLE_W * 0.5 + 0.24
	var hd := TABLE_D * 0.5 + 0.24
	_add_box(root, Vector3(0, 0.02, -hd), Vector3(TABLE_W + 0.96, 0.24, 0.44), m_steel)
	_add_box(root, Vector3(0, 0.02, hd), Vector3(TABLE_W + 0.96, 0.24, 0.44), m_steel)
	_add_box(root, Vector3(-hw, 0.02, 0), Vector3(0.44, 0.24, TABLE_D + 0.96), m_steel)
	_add_box(root, Vector3(hw, 0.02, 0), Vector3(0.44, 0.24, TABLE_D + 0.96), m_steel)

	# Glowing tactical edge strip inset along the gunmetal rim
	_add_box(root, Vector3(0, 0.145, -hd + 0.16), Vector3(TABLE_W + 0.18, 0.04, 0.06), m_glow)
	_add_box(root, Vector3(0, 0.145, hd - 0.16), Vector3(TABLE_W + 0.18, 0.04, 0.06), m_glow)
	_add_box(root, Vector3(-hw + 0.16, 0.145, 0), Vector3(0.06, 0.04, TABLE_D + 0.18), m_glow)
	_add_box(root, Vector3(hw - 0.16, 0.145, 0), Vector3(0.06, 0.04, TABLE_D + 0.18), m_glow)

	# Subtle holographic tactical sector grid lines hovering just above the terrain relief
	for gx in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_add_box(root, Vector3(gx, 0.12, 0), Vector3(0.022, 0.008, TABLE_D - 0.2), m_grid)
	for gz in [-4.5, -1.5, 1.5, 4.5]:
		_add_box(root, Vector3(0, 0.12, gz), Vector3(TABLE_W - 0.2, 0.008, 0.022), m_grid)

	# Animated holographic radar scan beam gliding smoothly north -> south across the map!
	var beam := _add_box(root, Vector3(0, 0.56, 0), Vector3(TABLE_W - 0.3, 0.028, 0.22), _mat(accent, 0.1, 0.1, true, accent, 1.65, 0.42))
	beam.name = "RadarScanBeam"
	return beam


func _build_3d_landmark_beacon(root: Node3D, theater: String, lm: Dictionary):
	var lid := str(lm["id"])
	var uv: Vector2 = lm["uv"]
	var base_pos := _uv_to_world(uv, theater)
	var is_open := bool(lm["open"])
	var acc: Color = lm["accent"]
	var icon_kind := str(lm.get("icon_3d", "base_diamond"))

	var holder := Node3D.new()
	holder.name = "Beacon3D_" + lid
	holder.position = base_pos
	root.add_child(holder)

	var m_gunmetal := _mat(Color("526c7e"), 0.26, 0.34, false, Color("263e4d"), 0.32)
	var m_chrome := _mat(Color("e2f1fa"), 0.16, 0.42, false, Color("b8dcf0"), 0.38)
	var m_acc_metal := _mat(acc.lightened(0.18), 0.18, 0.28, false, acc, 1.15 if is_open else 0.72)
	var m_acc_glow := _mat(acc.lightened(0.25), 0.12, 0.18, true, acc, 1.95 if is_open else 1.10)
	var m_beam := _mat(acc, 0.1, 0.0, true, acc, 1.15 if is_open else 0.70, 0.22 if is_open else 0.14)
	var m_ring_glow := _mat(acc.lightened(0.12), 0.14, 0.22, true, acc, 1.65 if is_open else 0.92, 0.92 if is_open else 0.74)

	# 1. Sleek Octagonal Mechanical Pedestal Anchor seated flush into the 3D relief terrain
	var pad_r := 0.56 if is_open else 0.45
	_add_cyl(holder, Vector3(0, 0.05, 0), pad_r * 0.88, pad_r, 0.13, m_gunmetal, 8)
	_add_cyl(holder, Vector3(0, 0.12, 0), pad_r * 0.62, pad_r * 0.72, 0.05, m_chrome, 8)
	_add_torus(holder, Vector3(0, 0.15, 0), pad_r * 0.86, pad_r * 0.98, m_ring_glow)

	# 4 Mechanical Corner Targeting Chevrons around base pad
	for ci in range(4):
		var ang := deg_to_rad(45.0 + float(ci) * 90.0)
		var cp := Vector3(cos(ang) * (pad_r + 0.22), 0.11, sin(ang) * (pad_r + 0.22))
		_add_box(holder, cp, Vector3(0.20, 0.05, 0.06), m_acc_glow, Vector3(0, -rad_to_deg(ang), 0))

	# Expanding Radar Pulse Ring
	var pulse_ring := _add_torus(holder, Vector3(0, 0.16, 0), pad_r * 1.00, pad_r * 1.08, _mat(acc, 0.1, 0.1, true, acc, 1.4, 0.50))

	# Vertical Translucent Holographic Light Column
	var col_h := 2.05 if is_open else 1.55
	_add_cyl(holder, Vector3(0, col_h * 0.5 + 0.12, 0), 0.03, 0.20 if is_open else 0.14, col_h, m_beam, 12)

	# 2. Floating Sculpted 3D Emblem Assembly (rotates smoothly above the pedestal!)
	var emblem := Node3D.new()
	emblem.name = "SculptedEmblem_" + lid
	var emb_y := 1.24 if is_open else 1.04
	emblem.position = Vector3(0, emb_y, 0)
	emblem.scale = Vector3.ONE * 0.84
	holder.add_child(emblem)

	var outer_ring: Node3D = null
	var inner_ring: Node3D = null

	match icon_kind:
		"base_diamond":
			# 【烟山基地】: Sculpted 3D Emerald Tactical Command Diamond + Winged Armor Shield + Dual Gyro Rings!
			_add_cyl(emblem, Vector3(0, 0.36, 0), 0.02, 0.44, 0.72, m_acc_metal, 4, Vector3(0, 45, 0))
			_add_cyl(emblem, Vector3(0, -0.36, 0), 0.44, 0.02, 0.72, m_acc_metal, 4, Vector3(0, 45, 0))
			# Metallic gunmetal equatorial belt + twin angled wings
			_add_cyl(emblem, Vector3(0, 0.0, 0), 0.52, 0.52, 0.12, m_gunmetal, 4, Vector3(0, 45, 0))
			_add_box(emblem, Vector3(-0.56, 0.08, 0), Vector3(0.38, 0.12, 0.16), m_chrome, Vector3(0, 0, 26))
			_add_box(emblem, Vector3(0.56, 0.08, 0), Vector3(0.38, 0.12, 0.16), m_chrome, Vector3(0, 0, -26))
			# Apex laser spire
			_add_cyl(emblem, Vector3(0, 0.88, 0), 0.02, 0.05, 0.44, m_acc_glow, 6)
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.82, 0.90, m_ring_glow, Vector3(24, 0, 14))
			inner_ring = _add_torus(emblem, Vector3.ZERO, 0.62, 0.68, m_chrome, Vector3(-28, 30, -18))

		"fortress_bastion":
			# 【阿萨拉堡垒】: 3D Armored Hexagonal Bastion Core + Battlement Fins + Dual Amber Gyro Rings!
			_add_cyl(emblem, Vector3(0, 0.0, 0), 0.46, 0.54, 0.58, m_gunmetal, 6)
			_add_cyl(emblem, Vector3(0, 0.38, 0), 0.24, 0.44, 0.24, m_acc_metal, 6)
			_add_cyl(emblem, Vector3(0, -0.44, 0), 0.44, 0.04, 0.46, m_acc_metal, 6)
			# 3 Armored radial fortress buttresses
			for fi in range(3):
				var fa := float(fi) * 120.0
				var rad := deg_to_rad(fa)
				_add_box(emblem, Vector3(cos(rad) * 0.50, 0.08, sin(rad) * 0.50), Vector3(0.28, 0.46, 0.14), m_chrome, Vector3(0, -fa, 0))
			# Glowing amber command core crystal crowning the bastion
			_add_cyl(emblem, Vector3(0, 0.68, 0), 0.02, 0.22, 0.42, m_acc_glow, 6)
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.86, 0.94, m_ring_glow, Vector3(22, 10, -16))
			inner_ring = _add_torus(emblem, Vector3.ZERO, 0.64, 0.70, m_chrome, Vector3(-26, -24, 18))

		"story_star":
			# 【剧情模式序章】: 3D Golden Tactical Compass Star Prism + Halo Ring!
			_add_cyl(emblem, Vector3(0, 0.34, 0), 0.02, 0.38, 0.68, m_acc_metal, 4)
			_add_cyl(emblem, Vector3(0, -0.34, 0), 0.38, 0.02, 0.68, m_acc_metal, 4)
			_add_box(emblem, Vector3.ZERO, Vector3(1.18, 0.14, 0.14), m_acc_glow, Vector3(45, 0, 0))
			_add_box(emblem, Vector3.ZERO, Vector3(0.14, 0.14, 1.18), m_acc_glow, Vector3(0, 0, 45))
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.76, 0.84, m_ring_glow, Vector3(28, 0, 0))
			inner_ring = _add_torus(emblem, Vector3.ZERO, 0.56, 0.61, m_chrome, Vector3(-28, 45, 0))

		"school_crest":
			# 【鲸塘中心小学】: Sculpted 3D Classical School Pediment & Pillars Crest + Metallic Lock Halo!
			_add_box(emblem, Vector3(0, -0.22, 0), Vector3(0.84, 0.12, 0.30), m_gunmetal)
			for cx in [-0.28, 0.0, 0.28]:
				_add_cyl(emblem, Vector3(cx, 0.04, 0), 0.06, 0.065, 0.42, m_chrome, 8)
			# Sculpted triangular gable roof
			_add_box(emblem, Vector3(-0.22, 0.34, 0), Vector3(0.54, 0.10, 0.34), m_acc_metal, Vector3(0, 0, 26))
			_add_box(emblem, Vector3(0.22, 0.34, 0), Vector3(0.54, 0.10, 0.34), m_acc_metal, Vector3(0, 0, -26))
			_add_cyl(emblem, Vector3(0, 0.56, 0), 0.03, 0.03, 0.26, m_acc_glow, 6)
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.68, 0.74, m_ring_glow, Vector3(90, 0, 0))
			_add_mini_3d_lock(emblem, Vector3(0, -0.52, 0), m_gunmetal, m_chrome, m_acc_glow)

		"port_anchor":
			# 【诚庄村河港】: Sculpted 3D Naval Anchor Emblem + Metallic Lock Halo!
			_add_cyl(emblem, Vector3(0, 0.04, 0), 0.065, 0.075, 0.76, m_chrome, 8)
			_add_box(emblem, Vector3(0, 0.22, 0), Vector3(0.56, 0.09, 0.09), m_acc_metal)
			# Curved anchor arms (flukes)
			_add_box(emblem, Vector3(-0.22, -0.24, 0), Vector3(0.42, 0.09, 0.10), m_acc_metal, Vector3(0, 0, -34))
			_add_box(emblem, Vector3(0.22, -0.24, 0), Vector3(0.42, 0.09, 0.10), m_acc_metal, Vector3(0, 0, 34))
			_add_torus(emblem, Vector3(0, 0.46, 0), 0.10, 0.15, m_acc_glow, Vector3(90, 0, 0), 16)
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.68, 0.74, m_ring_glow, Vector3(90, 0, 0))
			_add_mini_3d_lock(emblem, Vector3(0, -0.52, 0), m_gunmetal, m_chrome, m_acc_glow)

		"desert_dome":
			# 【巴克什古城外围】: Sculpted 3D Sandstone Citadel Dome & Spire + Metallic Lock Halo!
			_add_cyl(emblem, Vector3(0, -0.16, 0), 0.42, 0.46, 0.30, m_gunmetal, 8)
			var dome := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.36
			sm.height = 0.56
			dome.mesh = sm
			dome.position = Vector3(0, 0.12, 0)
			dome.material_override = m_acc_metal
			emblem.add_child(dome)
			_add_cyl(emblem, Vector3(0, 0.46, 0), 0.02, 0.05, 0.32, m_acc_glow, 6)
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.68, 0.74, m_ring_glow, Vector3(90, 0, 0))
			_add_mini_3d_lock(emblem, Vector3(0, -0.50, 0), m_gunmetal, m_chrome, m_acc_glow)

		"orbital_spire":
			# 【哈夫克航天禁区】: Sculpted 3D Orbital Rocket + Delta Fins + Tilted Ring!
			_add_cyl(emblem, Vector3(0, 0.06, 0), 0.12, 0.16, 0.72, m_chrome, 10)
			_add_cyl(emblem, Vector3(0, 0.54, 0), 0.01, 0.12, 0.28, m_acc_glow, 10)
			for fi in range(3):
				var fa := float(fi) * 120.0
				var rad := deg_to_rad(fa)
				_add_box(emblem, Vector3(cos(rad) * 0.20, -0.18, sin(rad) * 0.20), Vector3(0.24, 0.26, 0.05), m_acc_metal, Vector3(0, -fa, -18))
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.68, 0.74, m_ring_glow, Vector3(32, 0, 22))
			_add_mini_3d_lock(emblem, Vector3(0, -0.50, 0), m_gunmetal, m_chrome, m_acc_glow)

		_:
			# Default / Cave Crystal
			_add_cyl(emblem, Vector3(0, 0.26, 0), 0.02, 0.32, 0.52, m_acc_metal, 6)
			_add_cyl(emblem, Vector3(0, -0.26, 0), 0.32, 0.02, 0.52, m_acc_metal, 6)
			outer_ring = _add_torus(emblem, Vector3.ZERO, 0.64, 0.70, m_ring_glow, Vector3(24, 0, -24))
			_add_mini_3d_lock(emblem, Vector3(0, -0.50, 0), m_gunmetal, m_chrome, m_acc_glow)

	beacon_anims.append({
		"theater": theater,
		"id": lid,
		"emblem": emblem,
		"outer_ring": outer_ring,
		"inner_ring": inner_ring,
		"pulse_ring": pulse_ring,
		"base_y": emb_y,
		"is_open": is_open,
		"phase": float(beacon_anims.size()) * 1.1,
	})


func _add_mini_3d_lock(parent: Node3D, pos: Vector3, m_body: Material, m_shackle: Material, m_keyhole: Material):
	# Crisp miniature 3D brushed-steel padlock indicating locked/upcoming sectors
	var lg := Node3D.new()
	lg.position = pos
	parent.add_child(lg)
	_add_box(lg, Vector3(0, -0.04, 0), Vector3(0.28, 0.22, 0.12), m_body)
	_add_box(lg, Vector3(0, -0.04, 0.065), Vector3(0.06, 0.10, 0.02), m_keyhole)
	_add_torus(lg, Vector3(0, 0.09, 0), 0.06, 0.095, m_shackle, Vector3(90, 0, 0), 14)


func _build_tactical_arc(root: Node3D, p_a: Vector3, p_b: Vector3, col: Color):
	# 3D parabolic glowing dotted tactical link trajectory arcing cleanly above the relief map
	var mat := _mat(col, 0.2, 0.1, true, col, 1.35, 0.72)
	var steps := 14
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := p_a.lerp(p_b, t)
		p.y += sin(t * PI) * 1.45 + 0.16
		var next_t := minf(1.0, float(i + 1) / float(steps))
		var np := p_a.lerp(p_b, next_t)
		np.y += sin(next_t * PI) * 1.45 + 0.16
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.055, 0.045, p.distance_to(np) * 0.56)
		seg.mesh = bm
		seg.material_override = mat
		root.add_child(seg)
		seg.look_at_from_position(p, np, Vector3.UP)


func _build_all_theaters():
	var theme_accents := {
		"yanshan": Color("3ef0b4"),
		"ahsarah": Color("ffb238"),
		"story": Color("ffd76a"),
	}
	for tid in ["yanshan", "ahsarah", "story"]:
		var root := Node3D.new()
		root.name = "WarTable_" + tid
		sub_viewport.add_child(root)
		theater_roots[tid] = root

		var acc: Color = theme_accents[tid]
		var beam := _build_table_chassis(root, acc)
		scan_beams[tid] = beam
		root.add_child(_build_relief_map_mesh(tid))

		var lms: Array = LANDMARKS.get(tid, [])
		var hub_pos := Vector3.ZERO
		for i in range(lms.size()):
			var lm: Dictionary = lms[i]
			_build_3d_landmark_beacon(root, tid, lm)
			var wp := _uv_to_world(lm["uv"], tid)
			if i == 0:
				hub_pos = wp
			else:
				_build_tactical_arc(root, hub_pos, wp, acc)
		root.visible = (tid == "yanshan")


# ---------------------------------------------------------------------------
# 2D Mechanical Gunmetal Overlay Chrome & Projected Callout Tags
# ---------------------------------------------------------------------------
func _build_overlay_chrome():
	# Sharp mechanical top HUD telemetry bar (gunmetal carbon + glowing left accent rail)
	var top_bar := Panel.new()
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(size.x, 66)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tb_st := StyleBoxFlat.new()
	tb_st.bg_color = Color(0.032, 0.048, 0.064, 0.86)
	tb_st.border_width_bottom = 1
	tb_st.border_color = Color("28424f")
	top_bar.add_theme_stylebox_override("panel", tb_st)
	add_child(top_bar)

	header_rail = ColorRect.new()
	header_rail.position = Vector2(18, 12)
	header_rail.size = Vector2(4, 42)
	header_rail.color = Color("3ef0b4")
	header_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(header_rail)

	theater_code_lbl = game._text(top_bar, "SAT-LINK // SEC-01 · 实时三维战区沙盘", Vector2(32, 8), Vector2(480, 16), 11, Color("6ceac0"))
	theater_header_lbl = game._text(top_bar, "烟山行动 · 江南山地三维作战沙盘", Vector2(32, 24), Vector2(560, 26), 19, Color("f4fffa"))
	theater_sub_lbl = game._text(top_bar, "点击立体据点标志切换目标并部署出击", Vector2(32, 47), Vector2(680, 16), 11, Color("8fb2bd"))

	live_coord_lbl = game._text(top_bar, "GRID 31.24°N 119.48°E // HD-RELIEF ACTIVE", Vector2(size.x - 364, 12), Vector2(346, 20), 11, Color("6f98a6"))
	live_coord_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var badge_3d: Label = game._text(top_bar, "◈ 3D VOLUMETRIC BEACONS ONLINE", Vector2(size.x - 364, 34), Vector2(346, 18), 11, Color("48ddb0"))
	badge_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	pins_layer = Control.new()
	pins_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pins_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(pins_layer)


func _style_pin_button(btn: Button, bg: Color, border: Color, font_col: Color, left_bar: Color, is_sel: bool):
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = bg if st_name == "normal" else (bg.lightened(0.14) if st_name == "hover" else bg.darkened(0.06))
		st.border_color = border
		st.border_width_top = 1
		st.border_width_bottom = 1
		st.border_width_right = 1
		st.border_width_left = 4 if is_sel else 3
		# Sharp chamfered tactical corners!
		st.corner_radius_top_left = 2
		st.corner_radius_top_right = 3
		st.corner_radius_bottom_left = 2
		st.corner_radius_bottom_right = 3
		st.content_margin_left = 10
		st.content_margin_right = 10
		if st_name != "disabled":
			st.border_color = left_bar if is_sel else border
		btn.add_theme_stylebox_override(st_name, st)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", Color("ffffff"))
	btn.add_theme_color_override("font_pressed_color", font_col)


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
		var code_tag := str(lm.get("code", "SEC"))
		var badge_txt := str(lm["badge"])
		if lid == "ahsarah_fortress" and not ah_unlocked:
			effective_open = false
			badge_txt = "🔒 阿萨拉堡垒（古洞解锁）"
		elif effective_open:
			badge_txt = "◈ %s · %s" % [code_tag, badge_txt]
		else:
			badge_txt = "▪ %s" % badge_txt

		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		var pill_w := 206 if effective_open else 224
		holder.size = Vector2(pill_w, 46)
		pins_layer.add_child(holder)

		var btn := Button.new()
		btn.position = Vector2(0, 0)
		btn.size = Vector2(pill_w, 32)
		btn.text = badge_txt
		btn.add_theme_font_size_override("font_size", 13 if effective_open else 12)
		btn.pressed.connect(func():
			select_landmark(lid)
		)
		holder.add_child(btn)

		var acc: Color = lm["accent"]
		var rail := ColorRect.new()
		rail.position = Vector2(0, 0)
		rail.size = Vector2(4, 32)
		rail.color = acc if effective_open else Color("5c727e")
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rail)

		# Sleek tactical drop-line pointer anchoring the callout tag cleanly above the 3D sculpted beacon!
		var stem := ColorRect.new()
		stem.position = Vector2(pill_w * 0.5 - 1.0, 32)
		stem.size = Vector2(2, 12)
		stem.color = Color(acc.r, acc.g, acc.b, 0.85) if effective_open else Color("667c88")
		stem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(stem)

		var dot := ColorRect.new()
		dot.position = Vector2(pill_w * 0.5 - 3.0, 42)
		dot.size = Vector2(6, 4)
		dot.color = acc if effective_open else Color("8fa6b2")
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(dot)

		# Anchor label projection cleanly ABOVE the 3D sculpted emblem so the 3D icon below is 100% unobstructed!
		var base_wp := _uv_to_world(lm["uv"], current_theater)
		var label_wp := base_wp + Vector3(0.0, 2.78 if is_open else 2.28, 0.0)

		pin_buttons[lid] = {
			"holder": holder,
			"btn": btn,
			"rail": rail,
			"stem": stem,
			"world_pos": label_wp,
			"base_pos": base_wp,
			"data": lm,
			"effective_open": effective_open,
		}
	_style_pins()
	_update_pin_positions()


func _style_pins():
	for lid in pin_buttons:
		var entry: Dictionary = pin_buttons[lid]
		var btn: Button = entry["btn"]
		var rail: ColorRect = entry["rail"]
		var lm: Dictionary = entry["data"]
		var is_sel: bool = (str(lid) == selected_landmark_id)
		var eff_open := bool(entry["effective_open"])
		var acc: Color = lm["accent"]
		rail.color = acc if (eff_open or is_sel) else Color("586e7a")
		if is_sel:
			_style_pin_button(
				btn,
				Color(0.06, 0.13, 0.15, 0.96) if eff_open else Color(0.11, 0.15, 0.19, 0.95),
				acc if eff_open else Color("a8c4d2"),
				Color("ffffff"),
				acc if eff_open else Color("a8c4d2"),
				true
			)
		elif eff_open:
			_style_pin_button(btn, Color(0.04, 0.08, 0.10, 0.90), Color(acc.r, acc.g, acc.b, 0.72), Color("e6fff7"), acc, false)
		else:
			_style_pin_button(btn, Color(0.05, 0.07, 0.09, 0.86), Color("3c505c"), Color("adc0ca"), Color("586e7a"), false)


func set_theater(theater: String, emit_signal_now: bool = true):
	if not (theater in ["story", "yanshan", "ahsarah"]):
		theater = "yanshan"
	current_theater = theater
	for tid in theater_roots:
		var root: Node3D = theater_roots[tid]
		if is_instance_valid(root):
			root.visible = (str(tid) == theater)

	if theater == "ahsarah":
		header_rail.color = Color("ffb238")
		theater_code_lbl.text = "SAT-LINK // SEC-02 · 2035 北非荒漠战区沙盘"
		theater_code_lbl.add_theme_color_override("font_color", Color("ffc462"))
		theater_header_lbl.text = "阿萨拉行动 · 零号大坝与荒漠三维战区"
		theater_sub_lbl.text = "点击立体据点标志【阿萨拉堡垒】部署行动 · 古城外围与航天禁区规划筹建中"
		live_coord_lbl.text = "GRID 27.42°N 14.18°E // ZERO DAM SECTOR"
		if is_instance_valid(sun_light):
			sun_light.light_color = Color("ffebd0")
			fill_light.light_color = Color("ffaa52")
	elif theater == "story":
		header_rail.color = Color("ffd76a")
		theater_code_lbl.text = "SAT-LINK // SEC-00 · 单人沉浸式叙事任务"
		theater_code_lbl.add_theme_color_override("font_color", Color("ffe084"))
		theater_header_lbl.text = "剧情模式 · 烟山初行沉浸式任务总览"
		theater_sub_lbl.text = "推荐首次游玩的少年游侠由此启程 · 5–8 分钟完整体验听词、侦察、交锋与撤离"
		live_coord_lbl.text = "GRID 31.26°N 119.51°E // PROLOGUE BRIEF"
		if is_instance_valid(sun_light):
			sun_light.light_color = Color("ffe6bc")
			fill_light.light_color = Color("80d6c2")
	else:
		header_rail.color = Color("3ef0b4")
		theater_code_lbl.text = "SAT-LINK // SEC-01 · 江南山地三维作战沙盘"
		theater_code_lbl.add_theme_color_override("font_color", Color("5ef5c0"))
		theater_header_lbl.text = "烟山行动 · 江南山地立体战区沙盘"
		theater_sub_lbl.text = "中上【烟山基地】已开放出击 · 左下【鲸塘中心小学】与右中【诚庄村河港】待后续开放"
		live_coord_lbl.text = "GRID 31.24°N 119.48°E // YANSHAN VALLEY"
		if is_instance_valid(sun_light):
			sun_light.light_color = Color("fff6e6")
			fill_light.light_color = Color("5ec8e8")

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
			var wp := _uv_to_world(lm["uv"], current_theater)
			target_focus_offset = Vector3(wp.x * 0.14, 0.0, wp.z * 0.12)
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
		# Clamp cleanly inside visible map zone (below 66px top bar and above 548px deploy console!)
		var px := clampf(sp.x - holder.size.x * 0.5, 14.0, size.x - holder.size.x - 14.0)
		var py := clampf(sp.y - holder.size.y, 72.0, 498.0)
		holder.position = Vector2(px, py)


func _gui_input(event):
	if event is InputEventMouseMotion:
		var nx := clampf((event.position.x / maxf(size.x, 1.0)) * 2.0 - 1.0, -1.0, 1.0)
		var ny := clampf((event.position.y / maxf(size.y, 1.0)) * 2.0 - 1.0, -1.0, 1.0)
		mouse_parallax = Vector2(nx, ny)


func _process(delta: float):
	var active := visible and is_visible_in_tree()
	set_rendering_active(active)
	if not active or not is_instance_valid(camera):
		return
	anim_clock += delta
	cam_focus_offset = cam_focus_offset.lerp(target_focus_offset, minf(delta * 4.5, 1.0))

	# Sleek 3D War-Table perspective framing the entire 16:9 HD relief map edge-to-edge with headroom for top 3D beacons!
	var sway_x := sin(anim_clock * 0.36) * 0.42 + mouse_parallax.x * 0.65
	var sway_z := cos(anim_clock * 0.28) * 0.22 + mouse_parallax.y * 0.35
	var base_cam := Vector3(0.0, 16.6, 12.2)
	var base_look := Vector3(0.0, 0.0, 0.62)

	camera.position = base_cam + Vector3(sway_x, 0.0, sway_z) + cam_focus_offset * 0.55
	camera.look_at(base_look + cam_focus_offset * 0.45, Vector3.UP)

	# Animate holographic radar scan beam sweeping north -> south across the active relief table
	if scan_beams.has(current_theater):
		var sb: MeshInstance3D = scan_beams[current_theater]
		if is_instance_valid(sb):
			var scan_t := fmod(anim_clock * 0.22, 1.0)
			sb.position.z = lerpf(-TABLE_D * 0.48, TABLE_D * 0.48, scan_t)

	# Animate all 3D sculpted landmark beacons (smooth levitation, gyro rotation & radar pulse!)
	for b in beacon_anims:
		if str(b["theater"]) != current_theater:
			continue
		var emb: Node3D = b["emblem"]
		var is_sel: bool = (str(b["id"]) == selected_landmark_id)
		var ph: float = float(b["phase"])
		if is_instance_valid(emb):
			emb.position.y = float(b["base_y"]) + sin(anim_clock * 2.2 + ph) * 0.09
			emb.rotation.y = anim_clock * (1.15 if is_sel else 0.72) + ph
			var target_s := 0.94 if is_sel else 0.80
			emb.scale = emb.scale.lerp(Vector3.ONE * target_s, minf(delta * 6.0, 1.0))
		var oring: Node3D = b["outer_ring"]
		if is_instance_valid(oring):
			oring.rotation.y = -anim_clock * 1.45
		var iring: Node3D = b["inner_ring"]
		if is_instance_valid(iring):
			iring.rotation.x = anim_clock * 1.25
		var pring: Node3D = b["pulse_ring"]
		if is_instance_valid(pring):
			var pt := fmod(anim_clock * 0.72 + ph * 0.2, 1.0)
			var ps := 1.0 + pt * 0.85
			pring.scale = Vector3(ps, 1.0, ps)

	_update_pin_positions()
