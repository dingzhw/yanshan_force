extends Node3D
## Yanshan Force v0.9.0 — "阿萨拉堡垒" (Ahsarah Fortress) 3D Sunlit Desert World Builder
## Fuses Brakkesh warm North African sandstone kasbah arches & desert oasis palms with
## Zero Dam monumental concrete hydro wall, twin Babel radar towers, west cement silos & east Haavk substation!

const AhsarahLayout = preload("res://scripts/ahsarah_layout.gd")
const TacticalProps = preload("res://scripts/tactical_props.gd")

const ARCH_GLB := "res://assets/slice/v090_ahsarah_architecture.glb"
const HORIZON_TEX := "res://assets/slice/horizon_ahsarah.png"
const SAND_TEX := "res://assets/slice/ahsarah_sand_albedo.jpg"
const SANDSTONE_TEX := "res://assets/slice/ahsarah_sandstone_albedo.jpg"
const CONCRETE_TEX := "res://assets/slice/ahsarah_concrete_albedo.jpg"
const ROAD_TEX := "res://assets/slice/ahsarah_road_albedo.jpg"

var game
var rng = RandomNumberGenerator.new()
var sun_light: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var low_quality: bool = false
var scene_templates: Dictionary = {}
var mesh_cache: Dictionary = {}
var prop_roots: Dictionary = {}
var wangdao_deck_pos := Vector3.ZERO   # Compatibility attribute with SliceWorld

func setup(main_game):
	game = main_game
	rng.seed = 2035090
	_atmosphere()
	_desert_horizon()
	_terrain()
	_oasis_pool()
	_hero_landmarks()
	_sandstone_perimeter_and_covers()
	_desert_flora_and_boulders()
	_stations_and_targets()
	_tactical_crates_and_pickups()
	_extraction_helipad()

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

func _place_arch(parent: Node3D, node_name: String, pos: Vector3, yaw_deg: float = 0.0, sc: float = 1.0, shadow: bool = true) -> MeshInstance3D:
	var m: Mesh = _extract_mesh(ARCH_GLB, node_name)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	mi.scale = Vector3.ONE * sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _add_solid_box(parent: Node3D, center: Vector3, dims: Vector3, yaw_deg: float = 0.0):
	var body := StaticBody3D.new()
	body.position = center
	body.rotation_degrees.y = yaw_deg
	body.add_to_group("solid_props")
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = dims
	col.shape = shp
	body.add_child(col)
	return body

func _atmosphere():
	# Crisp sunlit North African clear desert sky — warm sand-gold horizon blending cleanly into cobalt azure zenith!
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3c8ed6")
	sky_mat.sky_horizon_color = Color("f2d5a4")
	sky_mat.sky_curve = 0.24
	sky_mat.ground_bottom_color = Color("b8834d")
	sky_mat.ground_horizon_color = Color("e8c48e")
	sky_mat.ground_curve = 0.14
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.14
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color("f2cfa0")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.84
	env.tonemap_white = 2.8
	env.fog_enabled = true
	env.fog_light_color = Color("dcb884")
	env.fog_light_energy = 0.58
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.14
	env.glow_enabled = false
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.light_color = Color("ffe6bc")
	sun_light.light_energy = 0.96
	sun_light.rotation_degrees = Vector3(-38.0, -34.0, 0.0)
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 140.0
	sun_light.shadow_bias = 0.05
	sun_light.shadow_normal_bias = 1.5
	add_child(sun_light)

func set_low_quality(low: bool):
	low_quality = low
	apply_quality_preset(not low)

func apply_quality_preset(high: bool):
	if is_instance_valid(sun_light):
		sun_light.shadow_enabled = high
		sun_light.directional_shadow_max_distance = 135.0 if high else 0.0
	if is_instance_valid(world_env) and world_env.environment != null:
		world_env.environment.glow_enabled = high

func _desert_horizon():
	# 1) True 3D sculpted distant desert mesa ring (r=238m) rising cleanly above canyon skyline
	var mesa_ring := _place_arch(self, "desert_mesa_ring", Vector3(0.0, 4.0, -70.0), 0.0, 1.0, false)
	if mesa_ring != null:
		mesa_ring.name = "DesertMesaRing3D"
		if mesa_ring.mesh != null and mesa_ring.mesh.get_surface_count() > 0:
			var mmat := StandardMaterial3D.new()
			mmat.vertex_color_use_as_albedo = true
			mmat.albedo_color = Color("d8a878")
			mmat.roughness = 0.94
			mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesa_ring.material_override = mmat

	# 2) Seamless 360-degree sunlit desert mesa & Saharan dune panoramic backdrop cylinder (r=268m)
	var htex: Texture2D = load(HORIZON_TEX)
	if htex == null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 268.0
	cyl.bottom_radius = 268.0
	cyl.height = 132.0
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var hmat := StandardMaterial3D.new()
	hmat.albedo_texture = htex
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.cull_mode = BaseMaterial3D.CULL_FRONT
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.disable_fog = true
	var backdrop := MeshInstance3D.new()
	backdrop.name = "DesertHorizonPanorama"
	backdrop.mesh = cyl
	backdrop.material_override = hmat
	backdrop.position = Vector3(0.0, 56.0, -70.0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)

func _terrain():
	var step := 2.0
	var cols := int((AhsarahLayout.MAX_X - AhsarahLayout.MIN_X) / step) + 1
	var rows := int((AhsarahLayout.MAX_Z - AhsarahLayout.MIN_Z) / step) + 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var grid_v: Array = []
	var grid_c: Array = []
	grid_v.resize(rows * cols)
	grid_c.resize(rows * cols)

	for rz in rows:
		var z := AhsarahLayout.MIN_Z + float(rz) * step
		for cx in cols:
			var x := AhsarahLayout.MIN_X + float(cx) * step
			var y := AhsarahLayout.height(x, z)
			var idx := rz * cols + cx
			grid_v[idx] = Vector3(x, y, z)
			# Vertex-color blending: rich golden-ochre desert sand + darker gravel road + oasis greenery + warm sandstone courtyard
			var col := Color("c69d66")
			var rd := AhsarahLayout.road_distance(x, z, 6.0)
			if rd < 4.5:
				var rt := 1.0 - smoothstep(2.0, 4.5, rd)
				col = col.lerp(Color("9c8260"), rt * 0.78)
			# Lush palm-oasis moist earth & grass ring around south pool (-16, 12)
			var od := Vector2((x - AhsarahLayout.OASIS_POOL.x) / 14.0, (z - AhsarahLayout.OASIS_POOL.z) / 11.0).length()
			if od < 1.35:
				var ot := 1.0 - smoothstep(0.65, 1.35, od)
				col = col.lerp(Color("6c8848"), ot * 0.85)
			# Warm limestone/concrete courtyard tone around Admin Fortress & Helipad
			var fd := Vector2(x - AhsarahLayout.ADMIN_FORTRESS.x, z - AhsarahLayout.ADMIN_FORTRESS.z).length()
			if fd < 24.0:
				var ft := 1.0 - smoothstep(16.0, 24.0, fd)
				col = col.lerp(Color("b6a68c"), ft * 0.70)
			# Deep terracotta canyon rim walls near edges
			var edge_w := smoothstep(54.0, 84.0, absf(x))
			if edge_w > 0.01:
				col = col.lerp(Color("a46238"), edge_w * 0.82)
			grid_c[idx] = col

	for rz in rows - 1:
		for cx in cols - 1:
			var i00 := rz * cols + cx
			var i10 := i00 + 1
			var i01 := i00 + cols
			var i11 := i01 + 1
			var v00: Vector3 = grid_v[i00]
			var v10: Vector3 = grid_v[i10]
			var v01: Vector3 = grid_v[i01]
			var v11: Vector3 = grid_v[i11]
			var uv00 := Vector2(v00.x * 0.08, v00.z * 0.08)
			var uv10 := Vector2(v10.x * 0.08, v10.z * 0.08)
			var uv01 := Vector2(v01.x * 0.08, v01.z * 0.08)
			var uv11 := Vector2(v11.x * 0.08, v11.z * 0.08)
			for tri in [[i00, v00, uv00], [i10, v10, uv10], [i11, v11, uv11], [i00, v00, uv00], [i11, v11, uv11], [i01, v01, uv01]]:
				st.set_color(grid_c[tri[0]])
				st.set_uv(tri[2])
				st.add_vertex(tri[1])

	st.generate_normals()
	var t_mesh := st.commit()
	var t_mat := StandardMaterial3D.new()
	t_mat.albedo_texture = load(SAND_TEX)
	t_mat.vertex_color_use_as_albedo = true
	t_mat.roughness = 0.92
	t_mat.metallic = 0.0

	var t_mi := MeshInstance3D.new()
	t_mi.name = "AhsarahDesertTerrain"
	t_mi.mesh = t_mesh
	t_mi.material_override = t_mat
	t_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(t_mi)

	# Full analytical trimesh collision for rock-solid player/enemy grounding & zero terrain clipping
	var body := StaticBody3D.new()
	body.name = "AhsarahTerrainBody"
	add_child(body)
	var col := CollisionShape3D.new()
	col.shape = t_mesh.create_trimesh_shape()
	body.add_child(col)

func _oasis_pool():
	# Shimmering sunlit emerald desert oasis spring at (-16, -0.18, 12)
	var pool := MeshInstance3D.new()
	pool.name = "OasisSpringPool"
	var pm := CylinderMesh.new()
	pm.top_radius = 8.4
	pm.bottom_radius = 7.2
	pm.height = 0.14
	pm.radial_segments = 24
	pool.mesh = pm
	pool.scale = Vector3(1.0, 1.0, 0.72)
	pool.position = Vector3(AhsarahLayout.OASIS_POOL.x, -0.16, AhsarahLayout.OASIS_POOL.z)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.18, 0.62, 0.58, 0.86)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.12
	wmat.metallic = 0.18
	pool.material_override = wmat
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)

func _hero_landmarks():
	var root := Node3D.new()
	root.name = "AhsarahHeroLandmarks"
	add_child(root)

	# 1) COLOSSAL NORTH ZERO DAM MONOLITH (114m wide x 40m tall framing entire northern skyline!)
	var dam_y := AhsarahLayout.CLOUD_ARENA_Y - 1.2
	_place_arch(root, "zero_dam_wall_monolith", Vector3(0.0, dam_y, -162.0), 0.0, 1.0, true)
	_add_solid_box(root, Vector3(0.0, dam_y + 18.0, -160.0), Vector3(118.0, 40.0, 14.0))
	var dam_lbl: Label3D = game._label3d(root, "零号大坝 · ZERO DAM", Vector3(0.0, dam_y + 30.0, -150.0), 66, Color("ffe5a8"))
	dam_lbl.pixel_size = 0.018
	dam_lbl.visibility_range_end = 220.0

	# 2) TWIN BABEL-INSPIRED CONCRETE RADAR WATCHTOWERS flanking the Dam & Fortress!
	for rt_pos in [AhsarahLayout.RADAR_TOWER_WEST, AhsarahLayout.RADAR_TOWER_EAST]:
		var gp := AhsarahLayout.on_ground(rt_pos)
		_place_arch(root, "babel_radar_tower", gp, 18.0 if rt_pos.x < 0 else -18.0, 1.0, true)
		_add_solid_box(root, gp + Vector3(0.0, 10.0, 0.0), Vector3(7.4, 20.0, 7.4))

	# 3) HERO ADMINISTRATIVE FORTRESS GATEHOUSE (Brakkesh sandstone twin towers + arched walkable passage!)
	var fg := AhsarahLayout.on_ground(AhsarahLayout.FORTRESS_GATE)
	_place_arch(root, "ahsarah_fortress_gatehouse", fg, 0.0, 1.0, true)
	# Solid colliders ONLY on left & right flanking towers (x=-7 & x=+7), keeping central 4.8m arched gateway 100% WALKABLE!
	_add_solid_box(root, fg + Vector3(-7.0, 4.4, 0.0), Vector3(6.4, 8.8, 11.4))
	_add_solid_box(root, fg + Vector3(7.0, 4.4, 0.0), Vector3(6.4, 8.8, 11.4))
	_add_solid_box(root, fg + Vector3(0.0, 6.6, 0.0), Vector3(8.2, 2.4, 10.2))  # Overhead command bridge
	var fg_lbl: Label3D = game._label3d(root, "阿萨拉行政堡垒 · ADMIN FORTRESS", fg + Vector3(0.0, 9.6, 5.8), 44, Color("ffd878"))
	fg_lbl.pixel_size = 0.010
	fg_lbl.visibility_range_end = 120.0

	# 4) WEST CEMENT PLANT INDUSTRIAL SILOS (Zero Dam signature west wing!)
	var cp1 := AhsarahLayout.on_ground(Vector3(-54.0, 0.0, -44.0))
	var cp2 := AhsarahLayout.on_ground(Vector3(-52.0, 0.0, -64.0))
	_place_arch(root, "cement_silo_complex", cp1, 14.0, 1.0, true)
	_add_solid_box(root, cp1 + Vector3(-3.4, 7.2, 0.0), Vector3(5.6, 14.4, 5.6), 14.0)
	_add_solid_box(root, cp1 + Vector3(3.4, 7.2, 0.0), Vector3(5.6, 14.4, 5.6), 14.0)
	_place_arch(root, "cement_silo_complex", cp2, -82.0, 0.88, true)
	_add_solid_box(root, cp2 + Vector3(0.0, 6.4, 0.0), Vector3(6.2, 12.8, 10.6), -82.0)
	var cp_lbl: Label3D = game._label3d(root, "西侧水泥厂 · CEMENT PLANT", cp1 + Vector3(2.0, 16.5, 0.0), 38, Color("f0d8a8"))
	cp_lbl.pixel_size = 0.009
	cp_lbl.visibility_range_end = 95.0

	# 5) EAST BRAKKESH SANDSTONE ARCHED BAZAAR PAVILIONS & WEST BARRACKS PAVILION
	var pav_specs := [
		[Vector3(44.0, 0.0, -28.0), -20.0, 1.0, "巴克什拱门集市"],
		[Vector3(36.0, 0.0, -46.0), 75.0, 0.94, ""],
		[Vector3(-52.0, 0.0, -104.0), 32.0, 1.0, "西翼大坝营房"],
		[Vector3(-19.5, 0.0, -124.0), 90.0, 0.92, ""],  # Admin courtyard West sandstone wing
		[Vector3(19.5, 0.0, -124.0), -90.0, 0.92, ""],  # Admin courtyard East sandstone wing
	]
	for ps in pav_specs:
		var pp := AhsarahLayout.on_ground(ps[0])
		_place_arch(root, "brakkesh_sandstone_pavilion", pp, float(ps[1]), float(ps[2]), true)
		# Corner pier colliders only so players can walk straight through the arched bazaar pavilions!
		var sc: float = float(ps[2])
		var rad := deg_to_rad(float(ps[1]))
		for c_off in [Vector3(-3.3, 2.2, -2.7), Vector3(3.3, 2.2, -2.7), Vector3(-3.3, 2.2, 2.7), Vector3(3.3, 2.2, 2.7)]:
			var rot_o := Vector3(c_off.x * cos(rad) - c_off.z * sin(rad), c_off.y, c_off.x * sin(rad) + c_off.z * cos(rad)) * sc
			_add_solid_box(root, pp + rot_o, Vector3(1.5, 4.4, 1.5) * sc, float(ps[1]))
		if str(ps[3]) != "":
			var pl: Label3D = game._label3d(root, str(ps[3]), pp + Vector3(0.0, 7.6, 0.0), 34, Color("ffe2a8"))
			pl.pixel_size = 0.0085
			pl.visibility_range_end = 85.0

	# 6) EAST HAAVK ELECTRICAL SUBSTATION TRANSFORMER BAYS
	for sb_spec in [[Vector3(52.0, 0.0, -84.0), -90.0], [Vector3(52.0, 0.0, -96.0), -90.0]]:
		var sp := AhsarahLayout.on_ground(sb_spec[0])
		_place_arch(root, "substation_transformer_bay", sp, float(sb_spec[1]), 1.0, true)
		_add_solid_box(root, sp + Vector3(0.0, 1.8, 0.0), Vector3(5.2, 3.6, 7.2), 0.0)
	var sub_lbl: Label3D = game._label3d(root, "哈夫克变电站 · HAAVK SUBSTATION", AhsarahLayout.on_ground(Vector3(50.0, 0.0, -90.0)) + Vector3(0.0, 6.2, 0.0), 36, Color("6ceeff"))
	sub_lbl.pixel_size = 0.009
	sub_lbl.visibility_range_end = 90.0

	# 7) TACTICAL 4x4 DESERT RECON JEEPS (Oasis Camp, Mid-Wadi Road, Helipad Overlook)
	for jp in [[Vector3(7.5, 0.0, 16.5), -142.0], [Vector3(-12.0, 0.0, -48.0), 28.0], [Vector3(44.0, 0.0, -132.0), -64.0]]:
		var jpos := AhsarahLayout.on_ground(jp[0])
		_place_arch(root, "tactical_desert_jeep", jpos, float(jp[1]), 1.0, true)
		_add_solid_box(root, jpos + Vector3(0.0, 0.95, 0.0), Vector3(2.1, 1.9, 4.2), float(jp[1]))

func _sandstone_perimeter_and_covers():
	var cov := Node3D.new()
	cov.name = "AhsarahCoversAndWalls"
	add_child(cov)

	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_texture = load(SANDSTONE_TEX)
	sand_mat.uv1_scale = Vector3(2.5, 1.2, 1.0)
	sand_mat.roughness = 0.88

	var conc_mat := StandardMaterial3D.new()
	conc_mat.albedo_texture = load(CONCRETE_TEX)
	conc_mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	conc_mat.roughness = 0.86

	# Sandstone fortress courtyard perimeter walls framing the Admin Fortress Boss Arena cleanly
	var wall_specs := [
		[Vector3(-18.0, 0.0, -104.0), Vector3(13.0, 3.6, 1.4), 0.0, sand_mat],
		[Vector3(18.0, 0.0, -104.0), Vector3(13.0, 3.6, 1.4), 0.0, sand_mat],
		[Vector3(-24.0, 0.0, -138.0), Vector3(1.4, 3.8, 18.0), 0.0, conc_mat],
		[Vector3(24.0, 0.0, -138.0), Vector3(1.4, 3.8, 12.0), 0.0, conc_mat],
	]
	for ws in wall_specs:
		var wp := AhsarahLayout.on_ground(ws[0])
		var dims: Vector3 = ws[1]
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = dims
		box.mesh = bm
		box.material_override = ws[3]
		box.position = wp + Vector3(0.0, dims.y * 0.5 - 0.15, 0.0)
		box.rotation_degrees.y = float(ws[2])
		cov.add_child(box)
		_add_solid_box(cov, box.position, dims, float(ws[2]))

	# 12 Curved Sandbag Firing Emplacements & 10 Military Ammo Stacks across key sightlines
	var sandbag_spots := [
		[Vector3(-4.5, 0.0, 6.0), 18.0], [Vector3(5.5, 0.0, 5.5), -20.0],
		[Vector3(-28.0, 0.0, -34.0), 32.0], [Vector3(-36.0, 0.0, -56.0), -18.0],
		[Vector3(28.0, 0.0, -28.0), -35.0], [Vector3(34.0, 0.0, -56.0), 15.0],
		[Vector3(36.0, 0.0, -82.0), -40.0], [Vector3(-34.0, 0.0, -102.0), 42.0],
		[Vector3(-10.5, 0.0, -118.0), 25.0], [Vector3(10.5, 0.0, -118.0), -25.0],
		[Vector3(0.0, 0.0, -136.0), 180.0], [Vector3(46.0, 0.0, -142.0), -125.0],
	]
	for sb in sandbag_spots:
		var sp := AhsarahLayout.on_ground(sb[0])
		_place_arch(cov, "sandbag_bunker_wall", sp, float(sb[1]), 1.0, true)
		_add_solid_box(cov, sp + Vector3(0.0, 0.62, 0.0), Vector3(4.2, 1.24, 1.15), float(sb[1]))

	var ammo_spots := [
		[Vector3(-5.8, 0.0, 14.2), 14.0], [Vector3(6.2, 0.0, 12.0), -22.0],
		[Vector3(-41.0, 0.0, -41.0), 8.0], [Vector3(-42.0, 0.0, -58.0), 42.0],
		[Vector3(31.0, 0.0, -35.0), -15.0], [Vector3(40.0, 0.0, -94.0), 26.0],
		[Vector3(-38.0, 0.0, -112.0), -30.0], [Vector3(-13.5, 0.0, -126.0), 12.0],
		[Vector3(13.5, 0.0, -126.0), -18.0], [Vector3(56.0, 0.0, -132.0), 34.0],
	]
	for am in ammo_spots:
		var ap := AhsarahLayout.on_ground(am[0])
		_place_arch(cov, "military_ammo_stack", ap, float(am[1]), 1.0, true)
		_add_solid_box(cov, ap + Vector3(0.0, 0.58, 0.0), Vector3(2.2, 1.16, 1.5), float(am[1]))

	# 4 weathered shipping containers in West Cement Plant & North Checkpoint for Zero Dam tactical feel
	var cont_specs := [
		[Vector3(-36.0, 0.0, -45.0), 12.0, Color("9a4c32")],
		[Vector3(-42.0, 0.0, -70.0), -78.0, Color("466170")],
		[Vector3(-22.0, 0.0, -80.0), 22.0, Color("5a6845")],
		[Vector3(24.0, 0.0, -76.0), -18.0, Color("9a4c32")],
	]
	for cs in cont_specs:
		var cpos := AhsarahLayout.on_ground(cs[0])
		var cbox := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(2.55, 2.65, 6.2)
		cbox.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = cs[2]
		cmat.albedo_texture = load(CONCRETE_TEX)
		cmat.roughness = 0.72
		cmat.metallic = 0.28
		cbox.material_override = cmat
		cbox.position = cpos + Vector3(0.0, 1.30, 0.0)
		cbox.rotation_degrees.y = float(cs[1])
		cov.add_child(cbox)
		_add_solid_box(cov, cbox.position, cm.size, float(cs[1]))

	# Boundary desert rock & military hazard fence posts keeping players inside playable 156x196m canyon
	for fx in [-78.0, 78.0]:
		_add_solid_box(cov, Vector3(fx, 8.0, -70.0), Vector3(2.0, 24.0, 204.0))
	_add_solid_box(cov, Vector3(0.0, 8.0, 28.0), Vector3(160.0, 24.0, 2.0))

func _desert_flora_and_boulders():
	var flora := Node3D.new()
	flora.name = "AhsarahDesertFlora"
	add_child(flora)

	# 7 Lush Date-Palm Clusters ringing the South Oasis & desert wadi springs!
	var palm_spots := [
		[Vector3(-10.5, 0.0, 17.5), 15.0, 1.05],
		[Vector3(-23.5, 0.0, 14.5), 110.0, 1.12],
		[Vector3(-20.5, 0.0, 4.5), 225.0, 0.96],
		[Vector3(-9.0, 0.0, 5.8), 305.0, 0.92],
		[Vector3(14.5, 0.0, 14.5), 48.0, 1.0],
		[Vector3(19.5, 0.0, -10.0), 165.0, 0.94],
		[Vector3(-18.5, 0.0, -18.0), 72.0, 0.90],
	]
	for ps in palm_spots:
		var pp := AhsarahLayout.on_ground(ps[0])
		_place_arch(flora, "oasis_palm_cluster", pp - Vector3(0.0, 0.15, 0.0), float(ps[1]), float(ps[2]), true)

	# 14 Flat-topped Umbrella Desert Acacia Trees scattered along ridges & bazaar approaches
	var acacia_spots := [
		Vector3(24.0, 0.0, 8.0), Vector3(-34.0, 0.0, -6.0), Vector3(56.0, 0.0, -18.0),
		Vector3(-62.0, 0.0, -24.0), Vector3(14.0, 0.0, -46.0), Vector3(-22.0, 0.0, -64.0),
		Vector3(62.0, 0.0, -56.0), Vector3(-64.0, 0.0, -82.0), Vector3(22.0, 0.0, -94.0),
		Vector3(-18.0, 0.0, -96.0), Vector3(64.0, 0.0, -116.0), Vector3(-62.0, 0.0, -130.0),
		Vector3(32.0, 0.0, -118.0), Vector3(-28.0, 0.0, -142.0),
	]
	for idx in acacia_spots.size():
		var ap := AhsarahLayout.on_ground(acacia_spots[idx])
		_place_arch(flora, "desert_acacia_tree", ap - Vector3(0.0, 0.12, 0.0), float(idx) * 53.0, rng.randf_range(0.85, 1.18), true)

	# Warm ochre canyon sandstone outcrop boulders framing edges via fast MultiMeshInstance3D!
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 2.6
	rock_mesh.height = 3.2
	rock_mesh.radial_segments = 9
	rock_mesh.rings = 5
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_texture = load(SANDSTONE_TEX)
	rock_mat.albedo_color = Color("d89b62")
	rock_mat.roughness = 0.92
	var rock_xforms: Array[Transform3D] = []
	for i in 48:
		var side := -1.0 if (i % 2 == 0) else 1.0
		var rx := side * rng.randf_range(56.0, 77.0)
		var rz := rng.randf_range(-154.0, 22.0)
		if AhsarahLayout.clear_for_route(rx, rz, 3.0):
			continue
		var ry := AhsarahLayout.height(rx, rz)
		var sc := Vector3(rng.randf_range(0.8, 2.2), rng.randf_range(0.6, 1.9), rng.randf_range(0.8, 2.0))
		rock_xforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(sc), Vector3(rx, ry + sc.y * 0.45, rz)))
	if not rock_xforms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock_mesh
		mm.instance_count = rock_xforms.size()
		for i in rock_xforms.size():
			mm.set_instance_transform(i, rock_xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "DesertCanyonRocks"
		mmi.multimesh = mm
		mmi.material_override = rock_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flora.add_child(mmi)

func _stations_and_targets():
	for data in AhsarahLayout.STATIONS:
		var station = game.Challenge.new()
		game.add_child(station)
		station.setup(game, data)
		game.stations.append(station)

func _tactical_crates_and_pickups():
	# 8 High-value Cipher Crates strategically placed across Zero Dam x Brakkesh landmarks!
	var crate_specs := [
		["绿洲前哨补给箱", 1, Vector3(-2.5, 0.0, 7.2)],
		["水泥厂工棚加密箱", 2, Vector3(-43.5, 0.0, -44.0)],
		["巴克什拱廊珍宝箱", 2, Vector3(44.0, 0.0, -28.0)],
		["哈夫克变电站机密箱", 3, Vector3(48.0, 0.0, -90.0)],
		["西翼哨所军火箱", 2, Vector3(-48.5, 0.0, -104.0)],
		["阿萨拉行政堡垒 · 西翼金库箱", 3, Vector3(-16.5, 0.0, -124.0)],
		["阿萨拉行政堡垒 · 核心曼德尔金库", 3, Vector3(0.0, 0.0, -133.5)],
		["零号大坝高台特勤秘箱", 3, Vector3(36.0, 0.0, -138.0)],
	]
	for cs in crate_specs:
		var gp := AhsarahLayout.on_ground(cs[2])
		var cr: Node3D = game._make_crate(str(cs[0]), int(cs[1]), gp)
		TacticalProps.build_tiered_vault_crate(game, cr, int(cs[1]))

	# Tactical pickups (ammo crates, medkits, smoke EMP, energy stims) + field supply boxes
	var pickup_specs := [
		["ammo_crate", "军用弹药补给箱", Vector3(4.0, 0.0, 8.5)],
		["ammo_crate", "水泥厂弹药补给箱", Vector3(-37.0, 0.0, -49.0)],
		["ammo_crate", "巴克什弹药补给箱", Vector3(34.0, 0.0, -42.0)],
		["ammo_crate", "变电站弹药补给箱", Vector3(42.0, 0.0, -82.0)],
		["ammo_crate", "西翼弹药补给箱", Vector3(-36.0, 0.0, -108.0)],
		["ammo_crate", "行政堡垒弹药补给箱", Vector3(-9.0, 0.0, -112.0)],
		["medkit", "沙漠急救医疗包", Vector3(-14.0, 0.0, -34.0)],
		["medkit", "行政堡垒急救包", Vector3(9.5, 0.0, -112.0)],
		["smoke_emp", "战术烟雾 EMP 罐", Vector3(26.0, 0.0, -64.0)],
		["stim", "沙漠能量饮", Vector3(-24.0, 0.0, -86.0)],
		["supply", "荒漠游击补给包", Vector3(-26.0, 0.0, -28.0)],
		["supply", "集市商队遗留箱", Vector3(28.0, 0.0, -22.0)],
		["supply", "哈夫克工程工具箱", Vector3(41.0, 0.0, -72.0)],
		["supply", "大坝巡逻补给箱", Vector3(-28.0, 0.0, -124.0)],
		["supply", "停机坪应急物资箱", Vector3(44.0, 0.0, -126.0)],
	]
	for idx_p in pickup_specs.size():
		var ps = pickup_specs[idx_p]
		var kind := str(ps[0])
		var title := str(ps[1])
		var gp := AhsarahLayout.on_ground(ps[2])
		var pnode := Node3D.new()
		pnode.position = gp
		pnode.set_meta("title", title)
		add_child(pnode)
		if kind != "supply":
			pnode.set_meta("tactical_item", kind)
			pnode.set_meta("tactical_id", "ah_tac_%d" % idx_p)
			var col := Color("f0c048") if kind == "ammo_crate" else (Color("56e8ff") if kind == "smoke_emp" else (Color("ff6b6b") if kind == "medkit" else Color("6ae3a8")))
			var bm := BoxMesh.new()
			bm.size = Vector3(0.74, 0.42, 0.54) if kind == "ammo_crate" else Vector3(0.46, 0.32, 0.36)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.position.y = bm.size.y * 0.5
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.roughness = 0.46
			mat.metallic = 0.22
			mi.material_override = mat
			pnode.add_child(mi)
			var pl: Label3D = game._label3d(pnode, title + " · [F]", Vector3(0.0, 0.92, 0.0), 22, col)
			pl.pixel_size = 0.0042
			pl.visibility_range_end = 18.0
		else:
			pnode.set_meta("supply_id", "ah_sup_%d" % idx_p)
			TacticalProps.build_supply_box(game, pnode)
			var sl: Label3D = game._label3d(pnode, title + " · 单词解锁 [F]", Vector3(0.0, 0.96, 0.0), 24, game.GOLD)
			sl.visibility_range_end = 22.0
		game.pickup_nodes.append(pnode)

func _extraction_helipad():
	# Elevated NE Concrete Helipad Extraction Zone ('B · 堡垒高台停机坪撤离点')
	var ep := AhsarahLayout.on_ground(AhsarahLayout.EXIT)
	var pad_root := Node3D.new()
	pad_root.name = "AhsarahExtractionHelipad"
	pad_root.position = ep
	add_child(pad_root)

	var conc_mat := StandardMaterial3D.new()
	conc_mat.albedo_texture = load(CONCRETE_TEX)
	conc_mat.albedo_color = Color("969ca0")
	conc_mat.roughness = 0.84

	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 7.4
	pm.bottom_radius = 7.8
	pm.height = 0.36
	pm.radial_segments = 24
	pad.mesh = pm
	pad.position.y = 0.14
	pad.material_override = conc_mat
	pad_root.add_child(pad)

	var ymat := StandardMaterial3D.new()
	ymat.albedo_color = Color("f6c343")
	ymat.emission_enabled = true
	ymat.emission = Color("f6c343")
	ymat.emission_energy_multiplier = 0.65

	# Crisp bold "H" helipad marking on concrete deck
	for hx in [-1.55, 1.55]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.04, 4.4)
		bar.mesh = bm
		bar.position = Vector3(hx, 0.33, 0.0)
		bar.material_override = ymat
		pad_root.add_child(bar)
	var mid := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(3.1, 0.04, 0.55)
	mid.mesh = mm
	mid.position = Vector3(0.0, 0.33, 0.0)
	mid.material_override = ymat
	pad_root.add_child(mid)

	# Glowing extraction beacon pillar visible across the desert canyon
	var beam := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.35
	bcm.bottom_radius = 0.55
	bcm.height = 28.0
	beam.mesh = bcm
	beam.position = Vector3(0.0, 14.0, 0.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.45, 0.92, 0.72, 0.22)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.emission_enabled = true
	bmat.emission = Color("6ae3a8")
	bmat.emission_energy_multiplier = 1.6
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad_root.add_child(beam)

	var ex_lbl: Label3D = game._label3d(pad_root, "B · 阿萨拉停机坪撤离点", Vector3(0.0, 4.6, 0.0), 46, Color("8ef5c8"))
	ex_lbl.pixel_size = 0.010
	ex_lbl.visibility_range_end = 150.0
