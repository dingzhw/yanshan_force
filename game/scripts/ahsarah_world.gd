extends Node3D
## Yanshan Force v0.9.0 — "阿萨拉堡垒" (Ahsarah Fortress) 3D Sunlit Desert World Builder
## Fuses Brakkesh warm North African sandstone kasbah arches & desert oasis palms with
## Zero Dam monumental concrete hydro wall, twin Babel radar towers, west cement silos & east Haavk substation!

const AhsarahLayout = preload("res://scripts/ahsarah_layout.gd")
const TacticalProps = preload("res://scripts/tactical_props.gd")

const ARCH_GLB := "res://assets/slice/v090_ahsarah_architecture.glb"
const FORTRESS_GLB := "res://assets/slice/v091_ahsarah_fortress.glb"
const PICKUPS_GLB := "res://assets/slice/v092_tactical_pickups.glb"
const DESERT_NATURE_GLB := "res://assets/slice/v097_desert_nature.glb"
const PBR_V097_DIR := "res://assets/pbr_v097/"
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
	return _place_from_glb(parent, ARCH_GLB, node_name, pos, yaw_deg, sc, shadow)

func _place_fortress(parent: Node3D, node_name: String, pos: Vector3, yaw_deg: float = 0.0, sc: float = 1.0, shadow: bool = true) -> MeshInstance3D:
	return _place_from_glb(parent, FORTRESS_GLB, node_name, pos, yaw_deg, sc, shadow)

func _place_from_glb(parent: Node3D, glb_path: String, node_name: String, pos: Vector3, yaw_deg: float = 0.0, sc: float = 1.0, shadow: bool = true) -> MeshInstance3D:
	var m: Mesh = _extract_mesh(glb_path, node_name)
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

func _add_solid_box(parent: Node3D, center: Vector3, dims: Vector3, yaw_deg: float = 0.0) -> StaticBody3D:
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

func _add_solid_cylinder(parent: Node3D, center: Vector3, radius: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.add_to_group("solid_props")
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = radius
	shp.height = height
	col.shape = shp
	body.add_child(col)
	return body

func _make_mesh_solid(mi: MeshInstance3D) -> StaticBody3D:
	## v0.9.2 Exact trimesh physics collision matching 100% of every visual face — ZERO hollow/walk-through models!
	if mi == null or mi.mesh == null:
		return null
	mi.create_trimesh_collision()
	for ch in mi.get_children():
		if ch is StaticBody3D:
			ch.add_to_group("solid_props")
			return ch as StaticBody3D
	return null

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
	# 1) True 3D sculpted distant desert mesa ring (r=238m) rising seamlessly out of the outer desert dune skirt
	var mesa_ring := _place_arch(self, "desert_mesa_ring", Vector3(0.0, 2.5, -70.0), 0.0, 1.0, false)
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
	backdrop.position = Vector3(0.0, 44.0, -70.0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)

func _terrain():
	# v0.9.2: High-resolution 1.0m analytical desert terrain grid (exact 1:1 match with AhsarahLayout.fast_height_grid -> ZERO terrain clipping!)
	var step := 1.0
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
			# v0.9.7 Splat weights encoded in vertex color channels:
			#   R = compacted gravel road | G = oasis meadow grass | B = fortress sandstone courtyard | A = wet oasis shoreline
			var rd := AhsarahLayout.road_distance(x, z, 6.0)
			var w_road := (1.0 - smoothstep(1.9, 4.8, rd)) if rd < 4.8 else 0.0
			var od := Vector2((x - AhsarahLayout.OASIS_POOL.x) / 13.8, (z - AhsarahLayout.OASIS_POOL.z) / 10.5).length()
			var w_oasis := (1.0 - smoothstep(0.66, 1.38, od)) if od < 1.38 else 0.0
			var shore_d := Vector2((x - AhsarahLayout.OASIS_POOL.x) / 7.4, (z - AhsarahLayout.OASIS_POOL.z) / 5.4).length()
			var w_wet := (1.0 - smoothstep(0.70, 1.26, shore_d)) if shore_d < 1.26 else 0.0
			var fd := Vector2(x - AhsarahLayout.ADMIN_FORTRESS.x, z - AhsarahLayout.ADMIN_FORTRESS.z).length()
			var w_court := (1.0 - smoothstep(16.5, 25.0, fd)) if fd < 25.0 else 0.0
			grid_c[idx] = Color(w_road, w_oasis, w_court, w_wet)

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
			var uv00 := Vector2(v00.x * 0.14, v00.z * 0.14)
			var uv10 := Vector2(v10.x * 0.14, v10.z * 0.14)
			var uv01 := Vector2(v01.x * 0.14, v01.z * 0.14)
			var uv11 := Vector2(v11.x * 0.14, v11.z * 0.14)
			for tri in [[i00, v00, uv00], [i10, v10, uv10], [i11, v11, uv11], [i00, v00, uv00], [i11, v11, uv11], [i01, v01, uv01]]:
				st.set_color(grid_c[tri[0]])
				st.set_uv(tri[2])
				st.add_vertex(tri[1])

	st.generate_normals()
	st.generate_tangents()
	var t_mesh := st.commit()
	var t_mat := _create_desert_terrain_shader_material()

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

	# Seamless extended Outer Desert Dune Skirt stitching directly onto the 4 terrain edges out to r=290m!
	_build_outer_desert_skirt(t_mat)

func _create_desert_terrain_shader_material() -> ShaderMaterial:
	# v0.9.7 Multi-Layer CC0 PBR Desert Shader (8 samplers: GL Compatibility + Forward+ safe!)
	# Combines dual-scale anti-tiling wind-rippled coast sand, wadi gravel roads, triplanar stratified canyon cliffs,
	# weathered fortress sandstone plazas, oasis greenery & sunlit quartz micro-sparkle!
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D sand_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_rgh : filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cliff_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cliff_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_diff : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 1) Dual-scale anti-tiling wind-rippled Saharan sand (near crisp ripples + macro rotated dune sweep)
	vec2 uv_near = v_wpos.xz * 0.24;
	mat2 rot28 = mat2(vec2(0.883, -0.469), vec2(0.469, 0.883));
	vec2 uv_macro = (rot28 * v_wpos.xz) * 0.068 + vec2(0.31, 0.17);
	vec3 s_near = texture(sand_diff, uv_near).rgb;
	vec3 s_macro = texture(sand_diff, uv_macro).rgb;
	vec3 sand_col = mix(s_near, s_macro, 0.44) * vec3(1.10, 0.94, 0.72);
	vec3 sand_n = normalize(mix(texture(sand_nrm, uv_near).rgb, texture(sand_nrm, uv_macro).rgb, 0.36));
	float sand_r = mix(texture(sand_rgh, uv_near).r, texture(sand_rgh, uv_macro).r, 0.40);

	// 2) Sun-baked wadi gravel & convoy tracks (COLOR.r)
	vec2 uv_grav = v_wpos.xz * 0.28;
	vec3 grav_col = texture(gravel_diff, uv_grav).rgb * vec3(1.02, 0.92, 0.78);
	vec3 grav_n = texture(gravel_nrm, uv_grav).rgb;
	// Subtle arid gravel patches even off-road based on large organic wave
	float dry_patch = smoothstep(0.56, 0.84, 0.5 + 0.5 * sin(v_wpos.x * 0.065 + cos(v_wpos.z * 0.058) * 1.9));
	float w_road = clamp(COLOR.r * 0.92 + dry_patch * 0.28, 0.0, 1.0);

	vec3 col = mix(sand_col, grav_col, w_road);
	vec3 nrm = mix(sand_n, grav_n, w_road);
	float rgh = mix(clamp(sand_r, 0.68, 0.94), 0.88, w_road);

	// 3) Administrative Fortress weathered limestone courtyard (COLOR.b)
	vec2 uv_st = v_wpos.xz * 0.34;
	vec3 court_col = texture(stone_diff, uv_st).rgb * vec3(1.06, 0.98, 0.86);
	float w_court = smoothstep(0.06, 0.82, COLOR.b);
	col = mix(col, court_col, w_court * 0.84);
	nrm = mix(nrm, grav_n, w_court * 0.50);
	rgh = mix(rgh, 0.82, w_court);

	// 4) South Oasis moist meadow & dark wet sand shoreline (COLOR.g / COLOR.a)
	float w_oasis = smoothstep(0.04, 0.88, COLOR.g);
	float w_wet = smoothstep(0.05, 0.85, COLOR.a);
	vec3 oasis_grass = mix(vec3(0.28, 0.42, 0.19), vec3(0.42, 0.52, 0.24), clamp(dot(grav_col, vec3(0.333)) * 1.4, 0.0, 1.0));
	col = mix(col, oasis_grass, w_oasis * 0.78);
	col = mix(col, sand_col * vec3(0.54, 0.47, 0.38), w_wet * 0.85);
	rgh = mix(rgh, 0.34, w_wet * 0.82);

	// 5) World-space Triplanar Stratified Desert Cliff Rock auto-blended on steep canyon slopes & rims!
	vec3 tri_b = pow(abs(v_wnrm), vec3(4.0));
	tri_b /= max(tri_b.x + tri_b.y + tri_b.z, 0.0001);
	vec2 cx = v_wpos.zy * 0.14;
	vec2 cy = v_wpos.xz * 0.14;
	vec2 cz = v_wpos.xy * 0.14;
	vec3 cliff_c = (texture(cliff_diff, cx).rgb * tri_b.x + texture(cliff_diff, cy).rgb * tri_b.y + texture(cliff_diff, cz).rgb * tri_b.z) * vec3(1.16, 0.86, 0.64);
	vec3 cliff_n = texture(cliff_nrm, cx).rgb * tri_b.x + texture(cliff_nrm, cy).rgb * tri_b.y + texture(cliff_nrm, cz).rgb * tri_b.z;

	float slope_rock = smoothstep(0.935, 0.76, v_wnrm.y);
	float rim_rock = smoothstep(55.0, 82.0, abs(v_wpos.x)) * (1.0 - smoothstep(92.0, 125.0, abs(v_wpos.x)));
	float w_cliff = clamp(max(slope_rock * 0.92, rim_rock * 0.72), 0.0, 0.92) * (1.0 - w_oasis * 0.85);
	col = mix(col, cliff_c, w_cliff);
	nrm = mix(nrm, cliff_n, w_cliff);
	rgh = mix(rgh, 0.91, w_cliff);

	// Subtle desert dune macro shadow modulation for cinematic scale
	float macro_shade = 0.93 + 0.14 * sin(v_wpos.x * 0.042 + v_wpos.z * 0.031);
	ALBEDO = col * macro_shade;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = mix(1.05, 1.35, max(w_cliff, w_road * 0.5));
	ROUGHNESS = clamp(rgh, 0.30, 0.96);
	METALLIC = 0.0;
	SPECULAR = mix(0.24, 0.08, w_cliff);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("sand_diff", load(PBR_V097_DIR + "coast_sand_01_diff.jpg"))
	sm.set_shader_parameter("sand_nrm", load(PBR_V097_DIR + "coast_sand_01_nor_gl.jpg"))
	sm.set_shader_parameter("sand_rgh", load(PBR_V097_DIR + "coast_sand_01_rough.jpg"))
	sm.set_shader_parameter("gravel_diff", load(PBR_V097_DIR + "gravelly_sand_diff.jpg"))
	sm.set_shader_parameter("gravel_nrm", load(PBR_V097_DIR + "gravelly_sand_nor_gl.jpg"))
	sm.set_shader_parameter("cliff_diff", load(PBR_V097_DIR + "cliff_side_diff.jpg"))
	sm.set_shader_parameter("cliff_nrm", load(PBR_V097_DIR + "cliff_side_nor_gl.jpg"))
	sm.set_shader_parameter("stone_diff", load(PBR_V097_DIR + "old_sandstone_02_diff.jpg"))
	return sm

func _build_outer_desert_skirt(t_mat: Material):
	var center_z := -70.0
	var half_x := 90.0
	var half_z := 110.0
	var segs_per_side := 32
	var perimeter: Array[Vector2] = []
	# Trace clockwise perimeter along exact terrain box edge: North (-180) -> East (+90) -> South (+40) -> West (-90)
	for i in segs_per_side:
		var f := float(i) / float(segs_per_side)
		perimeter.append(Vector2(lerpf(-half_x, half_x, f), -180.0))
	for i in segs_per_side:
		var f := float(i) / float(segs_per_side)
		perimeter.append(Vector2(half_x, lerpf(-180.0, 40.0, f)))
	for i in segs_per_side:
		var f := float(i) / float(segs_per_side)
		perimeter.append(Vector2(lerpf(half_x, -half_x, f), 40.0))
	for i in segs_per_side:
		var f := float(i) / float(segs_per_side)
		perimeter.append(Vector2(-half_x, lerpf(40.0, -180.0, f)))

	var n_pts := perimeter.size()
	var rings_fracs := [0.0, 0.14, 0.34, 0.62, 1.0]
	var ring_verts: Array = []
	var ring_cols: Array = []
	var outer_r := 288.0

	for rf in rings_fracs:
		var rv: Array[Vector3] = []
		var rc: Array[Color] = []
		for p in perimeter:
			var edge_y := AhsarahLayout.height(p.x, p.y)
			var dir := Vector2(p.x, p.y - center_z).normalized()
			var edge_pos := Vector2(p.x, p.y)
			var outer_pos := Vector2(0.0, center_z) + dir * outer_r
			var wp := edge_pos.lerp(outer_pos, rf)
			var wy: float
			if rf <= 0.001:
				wy = edge_y
			else:
				var rolling := 5.5 + 7.5 * sin(wp.x * 0.022 + wp.y * 0.019) + 4.2 * cos(wp.x * 0.036 - wp.y * 0.028)
				var far_lift := smoothstep(0.35, 1.0, rf) * 10.5
				wy = lerpf(edge_y, rolling + far_lift, smoothstep(0.0, 0.55, rf))
			rv.append(Vector3(wp.x, wy, wp.y))
			# v0.9.7 Skirt uses pure splat-weight 0 (wind-rippled dunes + automatic triplanar cliff slope!)
			rc.append(Color(0.0, 0.0, 0.0, 0.0))
		ring_verts.append(rv)
		ring_cols.append(rc)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in rings_fracs.size() - 1:
		var r0: Array[Vector3] = ring_verts[ri]
		var r1: Array[Vector3] = ring_verts[ri + 1]
		var c0: Array[Color] = ring_cols[ri]
		var c1: Array[Color] = ring_cols[ri + 1]
		for i in n_pts:
			var j := (i + 1) % n_pts
			var v00 := r0[i]; var v10 := r0[j]; var v01 := r1[i]; var v11 := r1[j]
			var u00 := Vector2(v00.x * 0.06, v00.z * 0.06)
			var u10 := Vector2(v10.x * 0.06, v10.z * 0.06)
			var u01 := Vector2(v01.x * 0.06, v01.z * 0.06)
			var u11 := Vector2(v11.x * 0.06, v11.z * 0.06)
			for tri in [[c0[i], v00, u00], [c1[i], v01, u01], [c1[j], v11, u11], [c0[i], v00, u00], [c1[j], v11, u11], [c0[j], v10, u10]]:
				st.set_color(tri[0])
				st.set_uv(tri[2])
				st.add_vertex(tri[1])
	st.generate_normals()
	st.generate_tangents()
	var skirt := MeshInstance3D.new()
	skirt.name = "AhsarahOuterDesertSkirt"
	skirt.mesh = st.commit()
	skirt.material_override = t_mat
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)

func _oasis_pool():
	# TRUE recessed sunlit emerald desert oasis spring sitting strictly INSIDE the -1.10m carved sand basin!
	# Water plane at y=-0.34m intersects INTO the sloping wet-sand shore 360° around (ZERO floating disc edge!).
	var pool := MeshInstance3D.new()
	pool.name = "OasisSpringPool"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16.0, 11.6)
	pm.subdivide_width = 20
	pm.subdivide_depth = 16
	pool.mesh = pm
	pool.position = Vector3(AhsarahLayout.OASIS_POOL.x, -0.34, AhsarahLayout.OASIS_POOL.z)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
void vertex() {
	float t = TIME * 1.45;
	float w = sin(VERTEX.x * 1.4 + t) * 0.018 + cos(VERTEX.z * 1.7 - t * 1.15) * 0.015;
	VERTEX.y += w;
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float ripple = sin(r * 18.0 - TIME * 2.4) * 0.5 + 0.5;
	float wave2 = sin(UV.x * 26.0 + TIME * 1.8) * cos(UV.y * 22.0 - TIME * 1.3) * 0.5 + 0.5;
	vec3 deep_col = vec3(0.08, 0.44, 0.46);
	vec3 shallow_col = vec3(0.24, 0.68, 0.60);
	vec3 foam_col = vec3(0.76, 0.90, 0.86);
	float depth_mix = smoothstep(0.18, 0.92, r);
	vec3 col = mix(deep_col, shallow_col, depth_mix);
	col = mix(col, foam_col, smoothstep(0.76, 0.98, ripple * 0.55 + wave2 * 0.45) * 0.24);
	ALBEDO = col;
	ROUGHNESS = 0.14;
	METALLIC = 0.12;
	ALPHA = mix(0.88, 0.52, smoothstep(0.68, 1.0, r));
}
"""
	var wmat := ShaderMaterial.new()
	wmat.shader = shader
	pool.material_override = wmat
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)

	# Carved weathered spring rock head & reeds feeding water into the recessed north shoreline
	var spring_pos := Vector3(AhsarahLayout.OASIS_POOL.x, -0.04, AhsarahLayout.OASIS_POOL.z - 5.1)
	var spring_mi := _place_arch(self, "oasis_spring_head", spring_pos, 0.0, 1.0, true)
	_make_mesh_solid(spring_mi)

	# Natural shoreline rim boulders partially embedded along the wet sand bank for grounded transition!
	var rim_rocks := [
		[-6.8, -2.6, 22.0, 0.44], [-7.4, 1.8, 108.0, 0.48], [-4.8, 4.9, 195.0, 0.42],
		[4.6, 4.6, 310.0, 0.46], [7.2, 1.4, 45.0, 0.44], [6.6, -2.8, 154.0, 0.46],
		[3.2, -4.9, 260.0, 0.40], [-3.4, -4.8, 82.0, 0.42],
	]
	for rr in rim_rocks:
		var rp := Vector3(AhsarahLayout.OASIS_POOL.x + float(rr[0]), 0.0, AhsarahLayout.OASIS_POOL.z + float(rr[1]))
		var ry := AhsarahLayout.height(rp.x, rp.z)
		var sc: float = float(rr[3])
		var rock_mi := _place_arch(self, "desert_boulder_a", Vector3(rp.x, ry - 0.16, rp.z), float(rr[2]), sc, true)
		_make_mesh_solid(rock_mi)

func _hero_landmarks():
	var root := Node3D.new()
	root.name = "AhsarahHeroLandmarks"
	add_child(root)

	# 1) COLOSSAL NORTH ZERO DAM MONOLITH (114m concrete wall + flanking photogrammetry desert canyon cliff abutments!)
	var dam_y := AhsarahLayout.CLOUD_ARENA_Y - 1.2
	var dam_mi := _place_arch(root, "zero_dam_wall_monolith", Vector3(0.0, dam_y, -158.0), 0.0, 1.0, true)
	_make_mesh_solid(dam_mi)
	# v0.9.7 Photogrammetry cliff abutments sealing Zero Dam cleanly into both canyon rock walls!
	# Both cliffs face SOUTH (+14 deg West, -16 deg East) so ZERO 1-sided photogrammetry backfaces show!
	for cliff_spec in [[Vector3(-64.0, dam_y - 3.2, -158.5), 14.0, 1.14], [Vector3(64.0, dam_y - 3.2, -158.5), -16.0, 1.14]]:
		var cl_mi := _place_arch(root, "desert_cliff_abutment", cliff_spec[0], float(cliff_spec[1]), float(cliff_spec[2]), true)
		_make_mesh_solid(cl_mi)
	# Solid cliff wing blockers locking both dam flanks into canyon walls (strictly north of z=-150m, clear of NE Helipad!)
	_add_solid_box(root, Vector3(-72.0, dam_y + 14.0, -158.0), Vector3(34.0, 34.0, 16.0))
	_add_solid_box(root, Vector3(72.0, dam_y + 14.0, -158.0), Vector3(34.0, 34.0, 16.0))
	var dam_lbl: Label3D = game._label3d(root, "零号大坝 · ZERO DAM", Vector3(0.0, dam_y + 30.0, -146.0), 66, Color("ffe5a8"))
	dam_lbl.pixel_size = 0.018
	dam_lbl.visibility_range_end = 220.0

	# 2) TWIN BABEL-INSPIRED CONCRETE RADAR WATCHTOWERS flanking the Dam & Fortress!
	for rt_pos in [AhsarahLayout.RADAR_TOWER_WEST, AhsarahLayout.RADAR_TOWER_EAST]:
		var ry := AhsarahLayout.min_ground_height(rt_pos.x, rt_pos.z, 3.8)
		var gp := Vector3(rt_pos.x, ry, rt_pos.z)
		var rt_mi := _place_arch(root, "babel_radar_tower", gp, 18.0 if rt_pos.x < 0 else -18.0, 1.0, true)
		_make_mesh_solid(rt_mi)

	# 3) HERO ADMINISTRATIVE FORTRESS GATEHOUSE (Brakkesh sandstone twin towers + arched walkable passage!)
	var fg := AhsarahLayout.on_ground(AhsarahLayout.FORTRESS_GATE)
	_place_arch(root, "ahsarah_fortress_gatehouse", fg, 0.0, 1.0, true)
	# Solid colliders on left & right flanking towers, outer concrete buttresses, front/rear arch cheeks & awning posts!
	_add_solid_box(root, fg + Vector3(-7.0, 4.4, 0.0), Vector3(6.4, 8.8, 11.5))
	_add_solid_box(root, fg + Vector3(7.0, 4.4, 0.0), Vector3(6.4, 8.8, 11.5))
	for sgn_g in [-1.0, 1.0]:
		for gz in [-5.25, 5.25]:
			_add_solid_box(root, fg + Vector3(sgn_g * 9.55, 2.0, gz), Vector3(1.45, 4.2, 1.48))
		for az in [-4.4, 4.4]:
			_add_solid_box(root, fg + Vector3(sgn_g * 3.25, 3.8, az), Vector3(1.75, 6.2, 1.65))
	# Front-left shade awning posts + stone plinth collars
	for ax in [-9.3, -4.7]:
		_add_solid_cylinder(root, fg + Vector3(ax, 1.85, 7.7), 0.22, 3.8)
	_add_solid_box(root, fg + Vector3(0.0, 6.6, 0.0), Vector3(8.4, 2.5, 10.4))  # Overhead command bridge
	# Walkable gatehouse tunnel floor (y=0..0.70m) + smooth front & rear step ramps so players ascend cleanly!
	_add_solid_box(root, fg + Vector3(0.0, 0.35, 0.0), Vector3(6.8, 0.70, 14.4))
	for r_sgn in [-1.0, 1.0]:
		var ramp_b := _add_solid_box(root, fg + Vector3(0.0, 0.25, r_sgn * 8.1), Vector3(6.5, 0.28, 2.4), 0.0)
		ramp_b.rotation_degrees.x = r_sgn * 17.0
	var fg_lbl: Label3D = game._label3d(root, "阿萨拉行政堡垒 · ADMIN FORTRESS", fg + Vector3(0.0, 9.6, 5.8), 44, Color("ffd878"))
	fg_lbl.pixel_size = 0.010
	fg_lbl.visibility_range_end = 120.0

	# 4) WEST CEMENT PLANT INDUSTRIAL SILOS (Zero Dam signature west wing — 100% trimesh solid silos + control booth + apron!)
	var cp1 := Vector3(-54.0, AhsarahLayout.min_ground_height(-54.0, -44.0, 4.5), -44.0)
	var cp2 := Vector3(-52.0, AhsarahLayout.min_ground_height(-52.0, -64.0, 4.5), -64.0)
	var cp1_mi := _place_arch(root, "cement_silo_complex", cp1, 14.0, 1.0, true)
	_make_mesh_solid(cp1_mi)
	var cp2_mi := _place_arch(root, "cement_silo_complex", cp2, -82.0, 0.88, true)
	_make_mesh_solid(cp2_mi)
	var cp_lbl: Label3D = game._label3d(root, "西侧水泥厂 · CEMENT PLANT", cp1 + Vector3(2.0, 16.5, 0.0), 38, Color("f0d8a8"))
	cp_lbl.pixel_size = 0.009
	cp_lbl.visibility_range_end = 95.0

	# 5) v0.9.1 ICONIC WALKABLE MULTI-STORY ARCHITECTURE:
	# 5a) TWIN 2-STORY WALKABLE ADMINISTRATIVE FORTRESS WINGS (East & West flanking Boss Courtyard!)
	_build_fortress_interior_wing(root, Vector3(AhsarahLayout.FORTRESS_WEST_WING.x, AhsarahLayout.CLOUD_ARENA_Y, AhsarahLayout.FORTRESS_WEST_WING.z), 90.0, "西翼二层狙击廊")
	_build_fortress_interior_wing(root, Vector3(AhsarahLayout.FORTRESS_EAST_WING.x, AhsarahLayout.CLOUD_ARENA_Y, AhsarahLayout.FORTRESS_EAST_WING.z), -90.0, "东翼二层指挥廊")

	# 5b) ZERO DAM 68m UNDERGROUND FLOODWAY / SPILLWAY SHORTCUT TUNNEL (links West Bastion -> East Helipad!)
	_build_dam_spillway_tunnel(root, Vector3(AhsarahLayout.SPILLWAY_TUNNEL_CENTER.x, AhsarahLayout.CLOUD_ARENA_Y, AhsarahLayout.SPILLWAY_TUNNEL_CENTER.z))

	# 5c) BRAKKESH GRAND DOME BATHHOUSE centerpiece at East Bazaar (44, -28)
	_build_brakkesh_grand_bathhouse(root, AhsarahLayout.GRAND_BATHHOUSE, -20.0)

	# 5d) CEMENT PLANT CLIMBABLE +4.2m ELEVATED STEEL SNIPER CATWALK (-42, -54)
	_build_cement_elevated_catwalk(root, AhsarahLayout.CEMENT_CATWALK, 90.0)

	# 5e) SOUTH BAZAAR & WEST BARRACKS SANDSTONE ARCHED PAVILIONS (100% solid walls, roof, amphorae & awning posts!)
	var pav_specs := [
		[Vector3(36.0, 0.0, -46.0), 75.0, 0.94, ""],
		[Vector3(-52.0, 0.0, -104.0), 32.0, 1.0, "西翼大坝营房"],
	]
	for ps in pav_specs:
		var p_in: Vector3 = ps[0]
		var py := AhsarahLayout.min_ground_height(p_in.x, p_in.z, 4.2)
		var pp := Vector3(p_in.x, py, p_in.z)
		_place_arch(root, "brakkesh_sandstone_pavilion", pp, float(ps[1]), float(ps[2]), true)
		var sc: float = float(ps[2])
		var yaw_deg: float = float(ps[1])
		var rot_b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
		# Full solid front/rear arch flanking walls (leaving center 4.4m arch open!)
		for fz in [-3.05, 3.05]:
			for fx in [-3.10, 3.10]:
				_add_solid_box(root, pp + (rot_b * Vector3(fx, 2.50, fz)) * sc, Vector3(1.88, 3.90, 0.78) * sc, yaw_deg)
		# Full solid left/right arch flanking walls (leaving center 3.2m side arches open!)
		for sx in [-3.66, 3.66]:
			for sz in [-2.35, 2.35]:
				_add_solid_box(root, pp + (rot_b * Vector3(sx, 2.50, sz)) * sc, Vector3(0.78, 3.90, 1.56) * sc, yaw_deg)
		# Roof slab & dome blocker
		_add_solid_box(root, pp + (rot_b * Vector3(0.0, 4.58, 0.0)) * sc, Vector3(8.5, 0.55, 6.9) * sc, yaw_deg)
		# Walkable raised sandstone floor (top at y=0.60*sc) + smooth entry ramps on front/back
		_add_solid_box(root, pp + Vector3(0.0, 0.30 * sc, 0.0), Vector3(8.6, 0.60, 7.1) * sc, yaw_deg)
		var front_ramp := _add_solid_box(root, pp + (rot_b * Vector3(0.0, 0.22, 4.25)) * sc, Vector3(4.0, 0.24, 1.9) * sc, yaw_deg)
		front_ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(18.0))
		var back_ramp := _add_solid_box(root, pp + (rot_b * Vector3(0.0, 0.22, -4.15)) * sc, Vector3(4.2, 0.24, 1.7) * sc, yaw_deg)
		back_ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18.0))
		# Solid front awning posts & terracotta amphorae colliders
		for p_off in [Vector3(-2.4, 1.6, 5.42), Vector3(2.4, 1.6, 5.42)]:
			_add_solid_cylinder(root, pp + (rot_b * p_off) * sc, 0.20 * sc, 3.4 * sc)
		for jar_off in [Vector3(-3.0, 0.45, 3.95), Vector3(-2.35, 0.38, 4.25), Vector3(3.0, 0.42, 4.0)]:
			_add_solid_cylinder(root, pp + (rot_b * jar_off) * sc, 0.34 * sc, 0.92 * sc)
		if str(ps[3]) != "":
			var pl: Label3D = game._label3d(root, str(ps[3]), pp + Vector3(0.0, 7.6, 0.0), 34, Color("ffe2a8"))
			pl.pixel_size = 0.0085
			pl.visibility_range_end = 85.0

	# 6) EAST HAAVK ELECTRICAL SUBSTATION TRANSFORMER BAYS (100% trimesh solid pad + transformer + relay console!)
	for sb_spec in [[Vector3(52.0, 0.0, -84.0), -90.0], [Vector3(52.0, 0.0, -96.0), -90.0]]:
		var s_in: Vector3 = sb_spec[0]
		var sp := Vector3(s_in.x, AhsarahLayout.min_ground_height(s_in.x, s_in.z, 3.2), s_in.z)
		var sb_mi := _place_arch(root, "substation_transformer_bay", sp, float(sb_spec[1]), 1.0, true)
		_make_mesh_solid(sb_mi)
	var sub_lbl: Label3D = game._label3d(root, "哈夫克变电站 · HAAVK SUBSTATION", AhsarahLayout.on_ground(Vector3(50.0, 0.0, -90.0)) + Vector3(0.0, 6.2, 0.0), 36, Color("6ceeff"))
	sub_lbl.pixel_size = 0.009
	sub_lbl.visibility_range_end = 90.0

	# 7) TACTICAL 4x4 DESERT RECON JEEPS (100% trimesh solid body, seated dead-level on dedicated flat pads!)
	for jp in [[Vector3(7.5, 0.0, 16.5), -142.0], [Vector3(-12.0, 0.0, -48.0), 28.0], [Vector3(44.0, 0.0, -132.0), -64.0]]:
		var j_in: Vector3 = jp[0]
		var jpos := Vector3(j_in.x, AhsarahLayout.height(j_in.x, j_in.z) - 0.02, j_in.z)
		var j_mi := _place_arch(root, "tactical_desert_jeep", jpos, float(jp[1]), 1.0, true)
		_make_mesh_solid(j_mi)

func _add_local_box(parent: Node3D, origin: Vector3, rot_b: Basis, yaw_deg: float, local_center: Vector3, dims: Vector3) -> StaticBody3D:
	return _add_solid_box(parent, origin + rot_b * local_center, dims, yaw_deg)

func _build_fortress_interior_wing(parent: Node3D, pos: Vector3, yaw_deg: float, label_text: String):
	var mi := _place_fortress(parent, "fortress_interior_wing", pos, yaw_deg, 1.0, true)
	if mi != null:
		mi.name = "FortressInteriorWing_%s" % ("W" if pos.x < 0.0 else "E")
	var rot_b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	# Ground-floor foundation floor flush at y=0
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(0.0, -0.45, 0.0), Vector3(17.4, 0.90, 7.8))
	# Ground-floor front colonnade pillars (leaving 3 wide 3.4m walkable arches open at x=-5, 0, +5!)
	for px in [-7.65, -2.5, 2.5, 7.65]:
		_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(px, 1.75, 3.15), Vector3(1.50, 3.50, 0.85))
	# Rear fortified wall segments (leaving central 2.8m rear tactical doorway open!)
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-5.05, 1.85, -3.15), Vector3(6.9, 3.70, 0.78))
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(5.05, 1.85, -3.15), Vector3(6.9, 3.70, 0.78))
	# Side doorway jambs (leaving central 3.4m side archway open!)
	for sx in [-8.15, 8.15]:
		_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(sx, 1.75, -2.40), Vector3(0.82, 3.50, 1.45))
		_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(sx, 1.75, 2.40), Vector3(0.82, 3.50, 1.45))
	# Solid interior smooth sloped staircase ramp rising from x=-6.2 (y=0.0) -> x=+0.4 (y=3.70) at z=-1.85!
	var stair_angle := atan2(3.70, 6.6)
	var stair_body := _add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-2.9, 1.69, -1.85), Vector3(7.65, 0.28, 1.96))
	stair_body.rotate_object_local(Vector3(0.0, 0.0, 1.0), stair_angle)
	# v0.9.2: Solid masonry under-staircase fill so players NEVER walk inside the stone stairs!
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-4.1, 0.36, -1.85), Vector3(1.8, 0.72, 1.92))
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-2.3, 0.88, -1.85), Vector3(1.9, 1.76, 1.92))
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-0.45, 1.52, -1.85), Vector3(1.85, 3.04, 1.92))
	# Stair inner railing curb to prevent falling sideways off stairs
	var rail_body := _add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-2.9, 2.50, -0.88), Vector3(7.4, 0.90, 0.14))
	rail_body.rotate_object_local(Vector3(0.0, 0.0, 1.0), stair_angle)
	# 2nd-floor walkable deck slabs (top y = +3.70m) with exact stairwell cutout at x∈[-6.4..+0.4], z∈[-2.85..-0.85]!
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(0.0, 3.55, 1.35), Vector3(17.2, 0.30, 4.40))
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(4.45, 3.55, -2.12), Vector3(8.2, 0.30, 2.55))
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(-7.4, 3.55, -2.12), Vector3(2.2, 0.30, 2.55))
	# 2nd-floor front sniper chest-high parapet (top y=4.71m -> clear line of fire over rail into Boss Courtyard!)
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(0.0, 4.18, 3.32), Vector3(16.8, 1.06, 0.44))
	for px in [-8.1, -3.1, 3.1, 8.1]:
		_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(px, 5.10, 3.28), Vector3(1.05, 2.85, 0.56))
	# 2nd-floor rear & side safety parapets + overhead shade roof
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(0.0, 4.30, -3.25), Vector3(16.8, 1.24, 0.48))
	for sx in [-8.25, 8.25]:
		_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(sx, 4.30, 0.0), Vector3(0.48, 1.24, 6.7))
	_add_local_box(parent, pos, rot_b, yaw_deg, Vector3(0.0, 6.45, 1.65), Vector3(17.0, 0.28, 3.8))
	# Warm interior corridor amber lantern glow
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffbe66")
	lamp.light_energy = 1.8
	lamp.omni_range = 12.0
	lamp.position = pos + rot_b * Vector3(0.0, 3.0, 0.8)
	parent.add_child(lamp)
	var lbl: Label3D = game._label3d(parent, label_text + " · 可登二层", pos + rot_b * Vector3(0.0, 7.6, 3.2), 30, Color("ffd884"))
	lbl.pixel_size = 0.008
	lbl.visibility_range_end = 75.0

func _build_dam_spillway_tunnel(parent: Node3D, pos: Vector3):
	var mi := _place_fortress(parent, "dam_spillway_tunnel", pos, 0.0, 1.0, true)
	if mi != null:
		mi.name = "ZeroDamSpillwayTunnel"
	# Solid concrete floor (top y=pos.y+0.02)
	_add_solid_box(parent, pos + Vector3(0.0, -0.44, 0.0), Vector3(70.0, 0.92, 6.4))
	_add_solid_box(parent, pos + Vector3(0.0, -0.44, -4.1), Vector3(6.8, 0.92, 3.0))
	# Solid south tunnel wall
	_add_solid_box(parent, pos + Vector3(0.0, 2.0, 2.75), Vector3(68.0, 4.0, 0.90))
	# Split north tunnel wall leaving central 6m maintenance vault alcove open (x∈[-3..+3])
	_add_solid_box(parent, pos + Vector3(-18.5, 2.0, -2.75), Vector3(31.0, 4.0, 0.90))
	_add_solid_box(parent, pos + Vector3(18.5, 2.0, -2.75), Vector3(31.0, 4.0, 0.90))
	# Central north maintenance vault alcove back & side walls + roof
	_add_solid_box(parent, pos + Vector3(0.0, 2.0, -5.45), Vector3(6.8, 4.0, 0.80))
	_add_solid_box(parent, pos + Vector3(-3.1, 2.0, -4.1), Vector3(0.70, 4.0, 2.6))
	_add_solid_box(parent, pos + Vector3(3.1, 2.0, -4.1), Vector3(0.70, 4.0, 2.6))
	_add_solid_box(parent, pos + Vector3(0.0, 4.05, -4.1), Vector3(6.8, 0.65, 3.0))
	# Main reinforced concrete tunnel roof (walkable overhead + blocks rain/falling)
	_add_solid_box(parent, pos + Vector3(0.0, 4.18, 0.0), Vector3(69.0, 0.85, 6.6))
	# Portal headwall side buttresses (leaving 4.6m clear portal entry open!)
	for sgn in [-1.0, 1.0]:
		var px: float = float(sgn) * 34.0
		_add_solid_box(parent, pos + Vector3(px, 4.75, 0.0), Vector3(1.6, 1.6, 7.6))
		for wz in [-3.25, 3.25]:
			_add_solid_box(parent, pos + Vector3(px, 2.4, wz), Vector3(1.8, 5.2, 1.25))
	# Atmospheric amber industrial work lights along the 68m floodway + cyan vault alcove glow!
	for lx in [-26.0, -13.0, 0.0, 13.0, 26.0]:
		var tl := OmniLight3D.new()
		tl.light_color = Color("ffbe62")
		tl.light_energy = 2.4
		tl.omni_range = 16.0
		tl.position = pos + Vector3(lx, 3.15, 0.0)
		parent.add_child(tl)
	var vault_light := OmniLight3D.new()
	vault_light.light_color = Color("4ae8ff")
	vault_light.light_energy = 2.6
	vault_light.omni_range = 11.0
	vault_light.position = pos + Vector3(0.0, 3.1, -4.3)
	parent.add_child(vault_light)
	var wl: Label3D = game._label3d(parent, "零号大坝泄洪暗道 · 西入口", pos + Vector3(-35.2, 5.9, 0.0), 34, Color("ffd166"))
	wl.pixel_size = 0.0085
	wl.visibility_range_end = 90.0
	var el: Label3D = game._label3d(parent, "零号大坝泄洪暗道 → 停机坪撤离点", pos + Vector3(35.2, 5.9, 0.0), 34, Color("8ef5c8"))
	el.pixel_size = 0.0085
	el.visibility_range_end = 90.0

func _build_brakkesh_grand_bathhouse(parent: Node3D, at_xz: Vector3, yaw_deg: float):
	var py := AhsarahLayout.min_ground_height(at_xz.x, at_xz.z, 5.5)
	var pp := Vector3(at_xz.x, py, at_xz.z)
	var mi := _place_fortress(parent, "brakkesh_grand_bathhouse", pp, yaw_deg, 1.0, true)
	if mi != null:
		mi.name = "BrakkeshGrandBathhouse"
	var rot_b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	# Walkable raised stone floor terrace (top at y=+0.55m) + smooth front stair ramp
	_add_local_box(parent, pp, rot_b, yaw_deg, Vector3(0.0, 0.275, 0.0), Vector3(13.4, 0.55, 10.8))
	var f_ramp := _add_local_box(parent, pp, rot_b, yaw_deg, Vector3(0.0, 0.20, 5.95), Vector3(5.4, 0.24, 1.85))
	f_ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(17.5))
	var b_ramp := _add_local_box(parent, pp, rot_b, yaw_deg, Vector3(0.0, 0.20, -5.95), Vector3(4.6, 0.24, 1.85))
	b_ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(-17.5))
	# Outer corner & colonnade wall piers matching exact arch widths (ZERO walk-through masonry!)
	for cz in [-4.75, 4.75]:
		for px in [-5.95, 5.95]:
			_add_local_box(parent, pp, rot_b, yaw_deg, Vector3(px, 2.70, cz), Vector3(1.25, 4.30, 0.88))
		for px in [-2.62, 2.62]:
			_add_local_box(parent, pp, rot_b, yaw_deg, Vector3(px, 2.70, cz), Vector3(1.48, 4.30, 0.88))
	for cx in [-6.05, 6.05]:
		_add_local_box(parent, pp, rot_b, yaw_deg, Vector3(cx, 2.70, 0.0), Vector3(0.88, 4.30, 1.68))
		for sz in [-4.32, 4.32]:
			_add_local_box(parent, pp, rot_b, yaw_deg, Vector3(cx, 2.70, sz), Vector3(0.88, 4.30, 1.56))
	# Roof deck & dome silhouette blocker
	_add_local_box(parent, pp, rot_b, yaw_deg, Vector3(0.0, 5.05, 0.0), Vector3(13.2, 0.45, 10.6))
	# Central octagonal fountain solid cylinder collider
	_add_solid_cylinder(parent, pp + Vector3(0.0, 1.25, 0.0), 1.75, 2.2)
	var bl: Label3D = game._label3d(parent, "巴克什穹顶浴场 · GRAND BATHHOUSE", pp + Vector3(0.0, 10.4, 0.0), 38, Color("ffe2a8"))
	bl.pixel_size = 0.009
	bl.visibility_range_end = 105.0

func _build_cement_elevated_catwalk(parent: Node3D, at_xz: Vector3, yaw_deg: float):
	var cy := AhsarahLayout.min_ground_height(at_xz.x, at_xz.z, 4.5)
	var cp := Vector3(at_xz.x, cy, at_xz.z)
	var mi := _place_fortress(parent, "cement_elevated_catwalk", cp, yaw_deg, 1.0, true)
	if mi != null:
		mi.name = "CementElevatedCatwalk"
	var rot_b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	# Support column piers (keeps open tactical lanes underneath!)
	for px in [-5.6, -1.8, 1.8, 5.6]:
		for pz in [-1.35, 1.35]:
			_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(px, 2.10, pz), Vector3(0.42, 4.20, 0.42))
	# Walkable elevated steel walkway deck (top y = +4.29m)
	_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(0.0, 4.18, 0.0), Vector3(12.4, 0.22, 3.2))
	# Waist-high industrial guardrails around top deck (leaving stair entry open at x∈[-1.8..+0.4], z=+1.52!)
	_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(0.0, 4.78, -1.52), Vector3(12.2, 1.05, 0.16))
	_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(-3.9, 4.78, 1.52), Vector3(4.2, 1.05, 0.16))
	_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(3.2, 4.78, 1.52), Vector3(5.8, 1.05, 0.16))
	for sx in [-6.05, 6.05]:
		_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(sx, 4.78, 0.0), Vector3(0.16, 1.05, 3.1))
	# Climbable sloped steel stair flight rising smoothly from z=+8.8 (y=0.0) -> z=+1.55 (y=4.20) at x=-0.7!
	var stair_ang := atan2(4.20, 7.25)
	var stair_ramp := _add_local_box(parent, cp, rot_b, yaw_deg, Vector3(-0.7, 1.94, 5.175), Vector3(2.08, 0.28, 8.48))
	stair_ramp.rotate_object_local(Vector3.RIGHT, stair_ang)
	for h_sgn in [-1.0, 1.0]:
		var s_rail := _add_local_box(parent, cp, rot_b, yaw_deg, Vector3(-0.7 + h_sgn * 1.04, 2.65, 5.175), Vector3(0.14, 1.12, 8.35))
		s_rail.rotate_object_local(Vector3.RIGHT, stair_ang)
	_add_local_box(parent, cp, rot_b, yaw_deg, Vector3(-0.7, -0.35, 8.95), Vector3(2.4, 0.85, 1.15))
	var cl: Label3D = game._label3d(parent, "水泥厂高架钢桥 · 可登高狙击", cp + Vector3(0.0, 6.1, 0.0), 30, Color("ffd884"))
	cl.pixel_size = 0.008
	cl.visibility_range_end = 85.0

func _sandstone_perimeter_and_covers():
	var cov := Node3D.new()
	cov.name = "AhsarahCoversAndWalls"
	add_child(cov)

	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_texture = load(PBR_V097_DIR + "old_sandstone_02_diff.jpg")
	sand_mat.normal_enabled = true
	sand_mat.normal_texture = load(PBR_V097_DIR + "old_sandstone_02_nor_gl.jpg")
	sand_mat.normal_scale = 1.05
	sand_mat.roughness_texture = load(PBR_V097_DIR + "old_sandstone_02_rough.jpg")
	sand_mat.uv1_scale = Vector3(2.8, 1.4, 1.0)
	sand_mat.roughness = 0.88

	var conc_mat := StandardMaterial3D.new()
	conc_mat.albedo_texture = load(PBR_V097_DIR + "plaster_grey_04_diff.jpg")
	conc_mat.normal_enabled = true
	conc_mat.normal_texture = load(PBR_V097_DIR + "plaster_grey_04_nor_gl.jpg")
	conc_mat.normal_scale = 0.92
	conc_mat.roughness_texture = load(PBR_V097_DIR + "plaster_grey_04_rough.jpg")
	conc_mat.uv1_scale = Vector3(2.4, 1.2, 1.0)
	conc_mat.roughness = 0.86

	# Sandstone fortress courtyard perimeter walls framing the Admin Fortress Boss Arena cleanly
	# (Leaves East/West Spillway Tunnel portals at z=-141.5 and central north archway 100% unobstructed!)
	var wall_specs := [
		[Vector3(-18.0, 0.0, -104.0), Vector3(13.0, 3.6, 1.4), 0.0, sand_mat],
		[Vector3(18.0, 0.0, -104.0), Vector3(13.0, 3.6, 1.4), 0.0, sand_mat],
		[Vector3(-14.0, 0.0, -135.5), Vector3(11.0, 3.6, 1.4), 0.0, conc_mat],
		[Vector3(14.0, 0.0, -135.5), Vector3(11.0, 3.6, 1.4), 0.0, conc_mat],
	]
	for ws in wall_specs:
		var w_in: Vector3 = ws[0]
		var wp := Vector3(w_in.x, AhsarahLayout.min_ground_height(w_in.x, w_in.z, 3.5), w_in.z)
		var dims: Vector3 = ws[1]
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(dims.x, dims.y + 1.2, dims.z)
		box.mesh = bm
		box.material_override = ws[3]
		box.position = wp + Vector3(0.0, dims.y * 0.5 - 0.60, 0.0)
		box.rotation_degrees.y = float(ws[2])
		cov.add_child(box)
		_add_solid_box(cov, wp + Vector3(0.0, dims.y * 0.5, 0.0), dims, float(ws[2]))

	# 12 Curved Sandbag Firing Emplacements & 10 Military Ammo Stacks across key sightlines
	var sandbag_spots := [
		[Vector3(-4.5, 0.0, 6.0), 18.0], [Vector3(5.5, 0.0, 5.5), -20.0],
		[Vector3(-28.0, 0.0, -34.0), 32.0], [Vector3(-31.0, 0.0, -62.0), -18.0],
		[Vector3(28.0, 0.0, -28.0), -35.0], [Vector3(34.0, 0.0, -56.0), 15.0],
		[Vector3(36.0, 0.0, -82.0), -40.0], [Vector3(-34.0, 0.0, -102.0), 42.0],
		[Vector3(-10.5, 0.0, -118.0), 25.0], [Vector3(10.5, 0.0, -118.0), -25.0],
		[Vector3(0.0, 0.0, -136.0), 180.0], [Vector3(46.0, 0.0, -142.0), -125.0],
	]
	for sb in sandbag_spots:
		var s_in: Vector3 = sb[0]
		var sp := Vector3(s_in.x, AhsarahLayout.min_ground_height(s_in.x, s_in.z, 1.6), s_in.z)
		var sb_mi := _place_arch(cov, "sandbag_bunker_wall", sp, float(sb[1]), 1.0, true)
		_make_mesh_solid(sb_mi)

	var ammo_spots := [
		[Vector3(-5.8, 0.0, 14.2), 14.0], [Vector3(6.2, 0.0, 12.0), -22.0],
		[Vector3(-41.0, 0.0, -41.0), 8.0], [Vector3(-47.5, 0.0, -37.5), 42.0],
		[Vector3(27.0, 0.0, -42.5), -15.0], [Vector3(36.5, 0.0, -95.0), 26.0],
		[Vector3(-34.5, 0.0, -115.0), -30.0], [Vector3(-13.5, 0.0, -126.0), 12.0],
		[Vector3(13.5, 0.0, -126.0), -18.0], [Vector3(56.0, 0.0, -132.0), 34.0],
	]
	for am in ammo_spots:
		var a_in: Vector3 = am[0]
		var ap := Vector3(a_in.x, maxf(AhsarahLayout.min_ground_height(a_in.x, a_in.z, 0.9), AhsarahLayout.height(a_in.x, a_in.z) - 0.04), a_in.z)
		var am_mi := _place_arch(cov, "military_ammo_stack", ap, float(am[1]), 1.0, true)
		_make_mesh_solid(am_mi)

	# 4 weathered shipping containers in West Cement Plant & North Checkpoint for Zero Dam tactical feel
	var cont_specs := [
		[Vector3(-30.5, 0.0, -42.5), 14.0, Color("9a4c32")],
		[Vector3(-42.0, 0.0, -70.0), -78.0, Color("466170")],
		[Vector3(-22.0, 0.0, -80.0), 22.0, Color("5a6845")],
		[Vector3(24.0, 0.0, -76.0), -18.0, Color("9a4c32")],
	]
	for cs in cont_specs:
		var c_in: Vector3 = cs[0]
		var cpos := Vector3(c_in.x, AhsarahLayout.min_ground_height(c_in.x, c_in.z, 2.5), c_in.z)
		var cbox := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(2.55, 3.15, 6.2)
		cbox.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = cs[2]
		cmat.albedo_texture = load(CONCRETE_TEX)
		cmat.roughness = 0.72
		cmat.metallic = 0.28
		cbox.material_override = cmat
		cbox.position = cpos + Vector3(0.0, 1.05, 0.0)
		cbox.rotation_degrees.y = float(cs[1])
		cov.add_child(cbox)
		_add_solid_box(cov, cpos + Vector3(0.0, 1.32, 0.0), Vector3(2.55, 2.65, 6.2), float(cs[1]))

	# PHYSICAL STACKED DESERT BOULDER HALF-WALL PERIMETER replacing bare invisible air walls!
	# Interlocking 10m sandstone rock-wall berms visually & physically enclose East, West, South & North Dam flanks!
	var perim := Node3D.new()
	perim.name = "AhsarahPerimeterRockWalls"
	cov.add_child(perim)
	# West (X=-76.2) & East (X=+76.2) stacked desert rock walls spanning Z=-150..+26
	for side_x in [-76.2, 76.2]:
		var yaw_base := 90.0 if side_x < 0.0 else -90.0
		var z_cur := -146.0
		var seg_i := 0
		while z_cur <= 24.0:
			var wy := AhsarahLayout.min_ground_height(side_x, z_cur, 3.5)
			var jitter_x := (0.6 if seg_i % 2 == 0 else -0.5) * (1.0 if side_x > 0 else -1.0)
			var sc_w := 1.02 + (0.08 if seg_i % 3 == 0 else 0.0)
			var rw_mi := _place_arch(perim, "desert_perimeter_rockwall", Vector3(side_x + jitter_x, wy - 0.15, z_cur), yaw_base + (5.0 if seg_i % 2 == 0 else -5.0), sc_w, false)
			_make_mesh_solid(rw_mi)
			z_cur += 9.4
			seg_i += 1
	# South perimeter stacked desert rock wall along Z=+26.2 spanning X=-76..+76
	var x_cur := -72.0
	var s_i := 0
	while x_cur <= 72.0:
		var wy := AhsarahLayout.min_ground_height(x_cur, 26.2, 3.5)
		var jitter_z := 0.55 if s_i % 2 == 0 else -0.45
		var sw_mi := _place_arch(perim, "desert_perimeter_rockwall", Vector3(x_cur, wy - 0.15, 26.2 + jitter_z), 180.0 + (4.5 if s_i % 2 == 0 else -4.5), 1.02, false)
		_make_mesh_solid(sw_mi)
		x_cur += 9.4
		s_i += 1
	# North perimeter rock walls bridging East/West edges seamlessly into Zero Dam's flanking canyon cliffs (Z=-148.5)
	for nx in [-70.0, -61.0, -52.0, 52.0, 61.0, 70.0]:
		var wy := AhsarahLayout.min_ground_height(nx, -148.5, 3.5)
		var nw_mi := _place_arch(perim, "desert_perimeter_rockwall", Vector3(nx, wy - 0.15, -148.5), 6.0 if nx < 0 else -6.0, 1.15, false)
		_make_mesh_solid(nw_mi)

	# Smooth-sliding solid colliders aligned right along the INNER boulder face so players never clip into perimeter rocks!
	_add_solid_box(cov, Vector3(-73.6, 8.0, -61.0), Vector3(2.2, 24.0, 178.0))
	_add_solid_box(cov, Vector3(73.6, 8.0, -61.0), Vector3(2.2, 24.0, 178.0))
	_add_solid_box(cov, Vector3(0.0, 8.0, 24.0), Vector3(154.0, 24.0, 2.2))
	_add_solid_box(cov, Vector3(0.0, 8.0, -148.2), Vector3(154.0, 24.0, 2.2))

func _desert_flora_and_boulders():
	var flora := Node3D.new()
	flora.name = "AhsarahDesertFlora"
	add_child(flora)

	# 7 Lush Date-Palm Clusters ringing the South Oasis & desert wadi springs — EVERY trunk has solid physics collision!
	var palm_spots := [
		[Vector3(-10.5, 0.0, 17.5), 15.0, 1.05],
		[Vector3(-23.5, 0.0, 14.5), 110.0, 1.12],
		[Vector3(-21.2, 0.0, 5.2), 225.0, 0.96],
		[Vector3(-9.2, 0.0, 5.8), 305.0, 0.92],
		[Vector3(14.5, 0.0, 14.5), 48.0, 1.0],
		[Vector3(19.5, 0.0, -10.0), 165.0, 0.94],
		[Vector3(-18.5, 0.0, -18.0), 72.0, 0.90],
	]
	# Local trunk offsets matching build_oasis_palm_cluster() in Blender 4.5
	var palm_trunk_offsets := [
		[Vector2(0.0, 0.0), 0.44, 6.2],
		[Vector2(-1.45, 0.85), 0.38, 5.2],
		[Vector2(1.30, -0.75), 0.34, 4.4],
	]
	for ps in palm_spots:
		var p_in: Vector3 = ps[0]
		var py := AhsarahLayout.min_ground_height(p_in.x, p_in.z, 1.5)
		var pp := Vector3(p_in.x, py - 0.08, p_in.z)
		var yaw_deg: float = float(ps[1])
		var sc: float = float(ps[2])
		_place_arch(flora, "oasis_palm_cluster", pp, yaw_deg, sc, true)
		var rad := deg_to_rad(yaw_deg)
		var ca := cos(rad)
		var sa := sin(rad)
		for tr in palm_trunk_offsets:
			var off: Vector2 = tr[0]
			# Godot Y-rotation maps local (x, z) -> (x*cos + z*sin, -x*sin + z*cos)
			var wx := pp.x + (off.x * ca + off.y * sa) * sc
			var wz := pp.z + (-off.x * sa + off.y * ca) * sc
			var tr_h := float(tr[2]) * sc
			_add_solid_cylinder(flora, Vector3(wx, pp.y + tr_h * 0.5, wz), float(tr[1]) * sc, tr_h)

	# 14 Flat-topped Umbrella Desert Acacia Trees — EVERY trunk deeply grounded with solid collision!
	var acacia_spots := [
		Vector3(24.0, 0.0, 8.0), Vector3(-34.0, 0.0, -6.0), Vector3(56.0, 0.0, -18.0),
		Vector3(-62.0, 0.0, -24.0), Vector3(14.0, 0.0, -46.0), Vector3(-22.0, 0.0, -64.0),
		Vector3(62.0, 0.0, -56.0), Vector3(-64.0, 0.0, -82.0), Vector3(22.0, 0.0, -94.0),
		Vector3(-18.0, 0.0, -96.0), Vector3(64.0, 0.0, -116.0), Vector3(-62.0, 0.0, -130.0),
		Vector3(32.0, 0.0, -118.0), Vector3(-42.0, 0.0, -134.0),
	]
	for idx in acacia_spots.size():
		var a_in: Vector3 = acacia_spots[idx]
		var ap := Vector3(a_in.x, AhsarahLayout.min_ground_height(a_in.x, a_in.z, 0.8) - 0.08, a_in.z)
		var sc: float = rng.randf_range(0.85, 1.18)
		_place_arch(flora, "desert_acacia_tree", ap, float(idx) * 53.0, sc, true)
		_add_solid_cylinder(flora, ap + Vector3(0.0, 2.3 * sc, 0.0), 0.44 * sc, 4.6 * sc)

	# Sculpted faceted Saharan sandstone outcrop boulders (Blender 4.5 desert_boulder_a / b)
	# Replaces smooth brick-textured walk-through spheres — EVERY boulder is deeply grounded AND solid!
	var boulders_root := Node3D.new()
	boulders_root.name = "DesertCanyonRocks"
	flora.add_child(boulders_root)
	var placed_boulders := 0
	for i in 52:
		var side := -1.0 if (i % 2 == 0) else 1.0
		var rx := side * rng.randf_range(54.0, 71.0)
		var rz := rng.randf_range(-142.0, 18.0)
		if AhsarahLayout.clear_for_route(rx, rz, 3.6):
			continue
		var sc := rng.randf_range(0.82, 1.48)
		var ry := AhsarahLayout.min_ground_height(rx, rz, 2.4 * sc)
		var is_tall := (i % 3 == 0)
		var b_name := "desert_boulder_b" if is_tall else "desert_boulder_a"
		var byaw := rng.randf_range(0.0, 360.0)
		var b_mi := _place_arch(boulders_root, b_name, Vector3(rx, ry - 0.42 * sc, rz), byaw, sc, true)
		_make_mesh_solid(b_mi)
		placed_boulders += 1

	# v0.9.7 GPU-Instanced Photogrammetry Desert Scrub Bushes & Scatter Stones (1 draw call each!)
	_scatter_desert_nature(flora)

func _scatter_desert_nature(parent: Node3D):
	var scrub_m := _extract_mesh(DESERT_NATURE_GLB, "desert_scrub_bush")
	var stone_m := _extract_mesh(DESERT_NATURE_GLB, "desert_scatter_stone")
	var scrub_tx: Array[Transform3D] = []
	var stone_tx: Array[Transform3D] = []
	var srng := RandomNumberGenerator.new()
	srng.seed = 2035097

	for _i in 220:
		if scrub_tx.size() >= 96:
			break
		var sx := srng.randf_range(-70.0, 70.0)
		var sz := srng.randf_range(-142.0, 22.0)
		if AhsarahLayout.clear_for_route(sx, sz, 2.2):
			continue
		var sy := AhsarahLayout.height(sx, sz) - 0.05
		var sc := srng.randf_range(0.72, 1.35)
		scrub_tx.append(Transform3D(Basis(Vector3.UP, srng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc * srng.randf_range(0.85, 1.15), sc)), Vector3(sx, sy, sz)))

	for _j in 300:
		if stone_tx.size() >= 135:
			break
		var rx := srng.randf_range(-72.0, 72.0)
		var rz := srng.randf_range(-145.0, 23.0)
		if AhsarahLayout.clear_for_route(rx, rz, 1.4):
			continue
		var ry := AhsarahLayout.height(rx, rz) - 0.08
		var sc := srng.randf_range(0.55, 1.38)
		stone_tx.append(Transform3D(Basis(Vector3.UP, srng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc * srng.randf_range(0.70, 1.10), sc)), Vector3(rx, ry, rz)))

	for pair in [["DesertScrubBushes", scrub_m, scrub_tx, 105.0], ["DesertScatterStones", stone_m, stone_tx, 95.0]]:
		var m: Mesh = pair[1]
		var txs: Array = pair[2]
		if m == null or txs.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = str(pair[0])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = txs.size()
		for k in txs.size():
			mm.set_instance_transform(k, txs[k])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = float(pair[3])
		parent.add_child(mmi)

func _stations_and_targets():
	for data in AhsarahLayout.STATIONS:
		var station = game.Challenge.new()
		game.add_child(station)
		station.setup(game, data)
		game.stations.append(station)

func _tactical_crates_and_pickups():
	# 10 High-value Cipher Crates across Zero Dam x Brakkesh landmarks (including 2F Fortress Balcony & Dam Spillway Alcove!)
	var bath_y := AhsarahLayout.min_ground_height(AhsarahLayout.GRAND_BATHHOUSE.x, AhsarahLayout.GRAND_BATHHOUSE.z, 5.5) + 0.55
	var bath_rot := Basis(Vector3.UP, deg_to_rad(-20.0))
	var bath_crate_pos := Vector3(AhsarahLayout.GRAND_BATHHOUSE.x, bath_y, AhsarahLayout.GRAND_BATHHOUSE.z) + bath_rot * Vector3(3.15, 0.0, 0.0)
	var wb_y := AhsarahLayout.min_ground_height(-52.0, -104.0, 4.2) + 0.60
	var crate_specs := [
		["绿洲前哨补给箱", 1, Vector3(-2.5, 0.0, 7.2), false],
		["水泥厂工棚加密箱", 2, Vector3(-43.5, 0.0, -44.0), false],
		["巴克什浴场珍宝箱", 2, bath_crate_pos, true],
		["哈夫克变电站机密箱", 3, Vector3(47.2, 0.0, -90.0), false],
		["西翼哨所军火箱", 2, Vector3(-52.0, wb_y, -104.0), true],
		["阿萨拉行政堡垒 · 西翼金库箱", 3, Vector3(-16.5, 0.0, -124.0), false],
		["阿萨拉行政堡垒 · 核心曼德尔金库", 3, Vector3(0.0, 0.0, -133.5), false],
		["零号大坝高台特勤秘箱", 3, Vector3(38.5, 0.0, -135.5), false],
		["零号大坝泄洪道秘库", 3, Vector3(0.0, AhsarahLayout.CLOUD_ARENA_Y + 0.04, -145.45), true],
		["行政堡垒 · 东翼二层指挥箱", 3, Vector3(21.2, AhsarahLayout.CLOUD_ARENA_Y + 3.70, -124.0), true],
	]
	for cs in crate_specs:
		var cpos_in: Vector3 = cs[2]
		var gp := cpos_in if bool(cs[3]) else Vector3(cpos_in.x, AhsarahLayout.max_ground_height(cpos_in.x, cpos_in.z, 0.65), cpos_in.z)
		var cr: Node3D = game._make_crate(str(cs[0]), int(cs[1]), gp)
		TacticalProps.build_tiered_vault_crate(game, cr, int(cs[1]))

	# Tactical pickups (sculpted v092 ammo crates, medkits, smoke EMP, energy stims) + field supply boxes!
	var cat_y := AhsarahLayout.min_ground_height(AhsarahLayout.CEMENT_CATWALK.x, AhsarahLayout.CEMENT_CATWALK.z, 4.5) + 4.29
	var pickup_specs := [
		["ammo_crate", "军用弹药补给箱", Vector3(3.6, 0.0, 7.6), false],
		["ammo_crate", "水泥厂弹药补给箱", Vector3(-37.0, 0.0, -49.0), false],
		["ammo_crate", "巴克什弹药补给箱", Vector3(30.5, 0.0, -40.5), false],
		["ammo_crate", "变电站弹药补给箱", Vector3(42.0, 0.0, -82.0), false],
		["ammo_crate", "西翼弹药补给箱", Vector3(-36.0, 0.0, -108.0), false],
		["ammo_crate", "行政堡垒弹药补给箱", Vector3(-9.0, 0.0, -112.0), false],
		["ammo_crate", "堡垒二层狙击弹药箱", Vector3(-21.2, AhsarahLayout.CLOUD_ARENA_Y + 3.70, -126.0), true],
		["medkit", "前哨野战急救包", Vector3(2.2, 0.0, 7.9), false],
		["medkit", "沙漠急救医疗包", Vector3(-14.0, 0.0, -34.0), false],
		["medkit", "行政堡垒急救包", Vector3(9.5, 0.0, -112.0), false],
		["smoke_emp", "前哨战术 EMP 雷", Vector3(5.0, 0.0, 7.9), false],
		["smoke_emp", "战术烟雾 EMP 罐", Vector3(26.0, 0.0, -64.0), false],
		["stim", "前哨肾上腺能量饮", Vector3(3.6, 0.0, 8.9), false],
		["stim", "沙漠能量饮", Vector3(-24.0, 0.0, -86.0), false],
		["supply", "荒漠游击补给包", Vector3(-26.0, 0.0, -28.0), false],
		["supply", "集市商队遗留箱", Vector3(28.0, 0.0, -22.0), false],
		["supply", "哈夫克工程工具箱", Vector3(41.0, 0.0, -72.0), false],
		["supply", "大坝巡逻补给箱", Vector3(-28.0, 0.0, -124.0), false],
		["supply", "停机坪应急物资箱", Vector3(44.0, 0.0, -126.0), false],
		["supply", "水泥厂高架狙击补给", Vector3(-42.0, cat_y, -57.2), true],
	]
	for idx_p in pickup_specs.size():
		var ps = pickup_specs[idx_p]
		var kind := str(ps[0])
		var title := str(ps[1])
		var p_in: Vector3 = ps[2]
		var gp: Vector3 = p_in if bool(ps[3]) else Vector3(p_in.x, AhsarahLayout.max_ground_height(p_in.x, p_in.z, 0.55 if kind == "supply" else 0.35), p_in.z)
		var pnode := Node3D.new()
		pnode.position = gp
		pnode.set_meta("title", title)
		add_child(pnode)
		if kind != "supply":
			pnode.set_meta("tactical_item", kind)
			pnode.set_meta("tactical_id", "ah_tac_%d" % idx_p)
			var col := Color("f0c048") if kind == "ammo_crate" else (Color("56e8ff") if kind == "smoke_emp" else (Color("ff6b6b") if kind == "medkit" else Color("6ae3a8")))
			var mesh_name := "pickup_ammo_crate" if kind == "ammo_crate" else ("pickup_smoke_emp" if kind == "smoke_emp" else ("pickup_medkit" if kind == "medkit" else "pickup_energy_stim"))
			var p_sc := 1.20 if kind == "ammo_crate" else (1.30 if kind == "medkit" else 1.55)
			var mi := _place_from_glb(pnode, PICKUPS_GLB, mesh_name, Vector3.ZERO, float(idx_p) * 35.0, p_sc, true)
			if mi == null:
				var bm := BoxMesh.new()
				bm.size = Vector3(0.74, 0.42, 0.54) if kind == "ammo_crate" else Vector3(0.46, 0.32, 0.36)
				mi = MeshInstance3D.new()
				mi.mesh = bm
				mi.position.y = bm.size.y * 0.5
				var mat := StandardMaterial3D.new()
				mat.albedo_color = col
				mat.roughness = 0.46
				mat.metallic = 0.22
				mi.material_override = mat
				pnode.add_child(mi)
			else:
				mi.name = "SculptedPickupMesh"
			# Subtle glowing tactical ring around base for crisp desert visibility
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.36
			tm.outer_radius = 0.43
			tm.rings = 16
			tm.ring_segments = 6
			ring.mesh = tm
			ring.position.y = 0.03
			ring.material_override = game._material(col, true)
			pnode.add_child(ring)
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
	conc_mat.albedo_texture = load(PBR_V097_DIR + "plaster_grey_04_diff.jpg")
	conc_mat.normal_enabled = true
	conc_mat.normal_texture = load(PBR_V097_DIR + "plaster_grey_04_nor_gl.jpg")
	conc_mat.normal_scale = 0.88
	conc_mat.roughness_texture = load(PBR_V097_DIR + "plaster_grey_04_rough.jpg")
	conc_mat.albedo_color = Color("a2a6aa")
	conc_mat.uv1_scale = Vector3(4.0, 4.0, 1.0)
	conc_mat.roughness = 0.84

	# v0.9.7 Solid walkable concrete helipad with 22-deg beveled 360-deg curb ramp (ZERO sinking boots!)
	var pad := MeshInstance3D.new()
	pad.name = "HelipadConcreteDeck"
	var pm := CylinderMesh.new()
	pm.top_radius = 7.4
	pm.bottom_radius = 8.2
	pm.height = 0.34
	pm.radial_segments = 32
	pad.mesh = pm
	pad.position.y = 0.16
	pad.material_override = conc_mat
	pad_root.add_child(pad)
	_make_mesh_solid(pad)

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
