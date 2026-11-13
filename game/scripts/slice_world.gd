extends Node3D
## A-to-B landscape with grounded hillside boulders, weathered military command tent, 3-tier vault/airdrop crates & keypad supply cases.

const TacticalProps = preload("res://scripts/tactical_props.gd")

var game
var rng = RandomNumberGenerator.new()
var bark: StandardMaterial3D
var wood_post_mat: StandardMaterial3D
var wood_plank_mat: StandardMaterial3D
var roof_slate_mat: StandardMaterial3D
var leaf: ShaderMaterial
var rock_paths = []
var stalk_transforms = []
var leaf_transforms = []
var low_quality = false

func setup(g):
	game = g
	rng.seed = 20261107
	_init_structure_materials()
	_lighting()
	_ground()
	_stream()
	_vegetation()
	_flora_meadows()
	_camp()
	_landmarks()
	_boundary()

func _init_structure_materials():
	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	wood_post_mat = StandardMaterial3D.new()
	wood_post_mat.albedo_color = Color("7b684e")
	wood_post_mat.albedo_texture = bark_tex
	wood_post_mat.uv1_scale = Vector3(1, 3, 1)
	wood_post_mat.roughness = 0.88

	wood_plank_mat = StandardMaterial3D.new()
	wood_plank_mat.albedo_color = Color("8c7759")
	wood_plank_mat.albedo_texture = bark_tex
	wood_plank_mat.uv1_scale = Vector3(2, 1, 1)
	wood_plank_mat.roughness = 0.84

	roof_slate_mat = StandardMaterial3D.new()
	roof_slate_mat.albedo_color = Color("4a5748")
	roof_slate_mat.albedo_texture = bark_tex
	roof_slate_mat.uv1_scale = Vector3(3, 1, 1)
	roof_slate_mat.metallic = 0.18
	roof_slate_mat.roughness = 0.68

func _lighting():
	var env = WorldEnvironment.new()
	var e = Environment.new()
	var sky = Sky.new()
	var s = ProceduralSkyMaterial.new()
	s.sky_top_color = Color("6b8ea0")
	s.sky_horizon_color = Color("bdcbc0")
	s.ground_bottom_color = Color("445140")
	s.ground_horizon_color = Color("aabaae")
	s.sun_angle_max = 32.0
	s.sun_curve = 0.14
	sky.sky_material = s
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.78
	e.ambient_light_energy = 0.40
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.00
	e.tonemap_white = 1.45
	e.fog_enabled = true
	e.fog_density = 0.0030
	e.fog_light_color = Color("b1c3b7")
	e.fog_sky_affect = 0.18
	env.environment = e
	add_child(env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47, -38, 0)
	sun.light_color = Color("f6eedb")
	sun.light_energy = 0.88
	low_quality = "--low-quality" in OS.get_cmdline_user_args()
	sun.shadow_enabled = not low_quality
	sun.directional_shadow_max_distance = 56
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.05
	add_child(sun)

func set_low_quality(value: bool):
	low_quality = value
	for child in get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = not low_quality

func _ground():
	var verts = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	for z in range(-116, 28):
		for x in range(-56, 56):
			var p = [
				Vector3(x, game.terrain_height(x, z), z),
				Vector3(x, game.terrain_height(x, z + 1), z + 1),
				Vector3(x + 1, game.terrain_height(x + 1, z), z),
				Vector3(x + 1, game.terrain_height(x + 1, z + 1), z + 1)
			]
			for tri in [[0, 2, 1], [2, 3, 1]]:
				var normal = (p[tri[2]] - p[tri[0]]).cross(p[tri[1]] - p[tri[0]]).normalized()
				for i in tri:
					verts.append(p[i])
					normals.append(normal)
					uvs.append(Vector2(p[i].x, p[i].z) * 0.28)
					var r_t := clampf(game.Layout.road_distance(p[i].x, p[i].z) / 4.5, 0, 1)
					var s_t := clampf(game.Layout.stream_distance(p[i].x, p[i].z) / 3.2, 0, 1)
					colors.append(Color(r_t, s_t, 0))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground = MeshInstance3D.new()
	ground.name = "ContinuousGround"
	ground.mesh = mesh
	var shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 pos;
void vertex(){pos=VERTEX;}
void fragment(){
 vec3 tex=texture(soil,UV).rgb;
 float edge=smoothstep(0.36,0.94,COLOR.r);
 float stream_bank=1.0-smoothstep(0.38,0.98,COLOR.g);
 float patch=0.5+0.5*sin(pos.x*0.27+sin(pos.z*0.21)*2.0);
 vec3 greenery=mix(vec3(0.28,0.35,0.19),vec3(0.42,0.44,0.27),patch);
 vec3 bed=mix(tex*vec3(0.56,0.50,0.37),tex*greenery*1.42,edge);
 vec3 wet_stone=tex*vec3(0.34,0.38,0.34);
 ALBEDO=mix(bed,wet_stone,stream_bank*0.82);
 NORMAL_MAP=texture(soil_normal,UV).rgb; NORMAL_MAP_DEPTH=0.52; ROUGHNESS=mix(0.94,0.52,stream_bank);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("soil", load("res://assets/slice/ground_color.jpg"))
	mat.set_shader_parameter("soil_normal", load("res://assets/slice/ground_normal.jpg"))
	ground.material_override = mat
	add_child(ground)

	var shape = HeightMapShape3D.new()
	shape.map_width = 113
	shape.map_depth = 145
	var heights = PackedFloat32Array()
	for z in range(-116, 29):
		for x in range(-56, 57):
			heights.append(game.terrain_height(x, z))
	shape.map_data = heights
	game.Props.shape_body(self, shape, Vector3(0, 0, -44)).name = "GroundCollision"

func bamboo(at: Vector3, height: float):
	var pos = game.Layout.on_ground(at)
	stalk_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, height, 1)), pos + Vector3.UP * height / 2))
	# Only allocate capsule/bullet colliders near walkable paths to keep physics lean
	if game.Layout.road_distance(pos.x, pos.z) < 16.0:
		var shape = CylinderShape3D.new()
		shape.radius = 0.13
		shape.height = height
		var body = game.Props.shape_body(self, shape, pos + Vector3.UP * height / 2)
		body.add_to_group("solid_props")
	for y in [height * 0.48, height * 0.67, height * 0.86]:
		leaf_transforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), pos + Vector3.UP * y))

func _spray_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in 24:
		var angle = rng.randf_range(0, TAU)
		var start = Vector3(sin(angle), 0, cos(angle)) * rng.randf_range(0.1, 0.9)
		var tip = start + Vector3(sin(angle) * 0.85, rng.randf_range(-0.3, 0.35), cos(angle) * 0.85)
		var width = Vector3(cos(angle), 0, -sin(angle)) * 0.09
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv([Vector2(0.5, 0), Vector2(0, 0.45), Vector2(0.5, 1), Vector2(1, 0.45)][i])
			st.add_vertex([start, (start + tip) / 2 - width, tip, (start + tip) / 2 + width][i])
	st.generate_normals()
	return st.commit()

func _batch(mesh: Mesh, mat: Material, transforms: Array, shadows: bool):
	var node = MultiMeshInstance3D.new()
	var instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = transforms.size()
	for i in transforms.size():
		instances.set_instance_transform(i, transforms[i])
	node.multimesh = instances
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _vegetation():
	bark = game._material(Color("5c6842"))
	var shader = Shader.new()
	shader.code = """shader_type spatial; render_mode cull_disabled;
void vertex(){VERTEX.x+=sin(TIME*1.3+NODE_POSITION_WORLD.x*0.7+VERTEX.y)*0.028*UV.y;}
void fragment(){ALBEDO=vec3(0.24,0.34,0.16)*(0.8+UV.y*0.3);ROUGHNESS=0.9;}
"""
	leaf = ShaderMaterial.new()
	leaf.shader = shader
	for i in 6:
		var path = "res://assets/slice/rock_%d.glb" % i
		if ResourceLoader.exists(path):
			rock_paths.append(path)
	for i in 200:
		var x = rng.randf_range(-49, 49)
		var z = rng.randf_range(-106, 17)
		if game.Layout.clear_for_route(x, z, 0.4):
			continue
		for j in 3:
			bamboo(Vector3(x + j * 0.6, 0, z + j * 0.43), rng.randf_range(6, 10))
	var stem = CylinderMesh.new()
	stem.height = 1
	stem.top_radius = 0.10
	stem.bottom_radius = 0.12
	stem.radial_segments = 7
	_grass_skirts()
	_batch(stem, bark, stalk_transforms, true)
	_batch(_spray_mesh(), leaf, leaf_transforms, false)
	_trees()
	for i in 30:
		var x = rng.randf_range(-44, 44)
		var z = rng.randf_range(-104, 18)
		if not game.Layout.clear_for_route(x, z, 1.5):
			rock(Vector3(x, 0, z), rng.randf_range(1.0, 3.5), i)
	for info in [[Vector3(-22, 0, -18), 2.1], [Vector3(-36.5, 0, -36.5), 3.0], [Vector3(5, 0, -34), 2.9], [Vector3(-9.5, 0, -71), 3.4], [Vector3(24, 0, -91), 4.2]]:
		rock(info[0], info[1], int(absf(info[0].z)))
	_backdrop()

func _grass_skirts():
	var spots = [
		Vector3(9, 0, 8), Vector3(-8, 0, 9), Vector3(-13, 0, -12), Vector3(6, 0, -16),
		Vector3(-23, 0, -20), Vector3(-24, 0, -33), Vector3(4, 0, -33), Vector3(-18, 0, -45),
		Vector3(-11, 0, -56), Vector3(4, 0, -60), Vector3(-9, 0, -68), Vector3(15, 0, -84),
		Vector3(22, 0, -89), Vector3(13, 0, -75)
	]
	for i in spots.size():
		var raw = spots[i]
		if game.Layout.clear_for_route(raw.x, raw.z, 0.8):
			continue
		var y = game.Layout.height(raw.x, raw.z) + 0.18
		leaf_transforms.append(Transform3D(Basis(Vector3.UP, float(i) * 1.1).scaled(Vector3(0.75, 0.65, 0.75)), Vector3(raw.x, y, raw.z)))

func _extract_mesh(glb_path: String, sub_name: String = "") -> Mesh:
	if not ResourceLoader.exists(glb_path):
		return null
	if not game.scene_cache.has(glb_path):
		game.scene_cache[glb_path] = load(glb_path)
	var inst: Node3D = game.scene_cache[glb_path].instantiate()
	var target: Node = inst.find_child(sub_name, true, false) if sub_name != "" else null
	if not (target is MeshInstance3D):
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		target = meshes[0] if not meshes.is_empty() else null
	var extracted: Mesh = target.mesh if (target is MeshInstance3D) else null
	inst.queue_free()
	return extracted

func _batch_direct(mesh: Mesh, transforms: Array, shadows: bool = false):
	if mesh == null or transforms.is_empty():
		return
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _hill_height(x: float, z: float) -> float:
	return 5.0 + 15.0 * exp(-pow((x + 65.0) / 43.0, 2.0) - pow((z + 175.0) / 45.0, 2.0)) + 22.0 * exp(-pow((x - 45.0) / 58.0, 2.0) - pow((z + 205.0) / 60.0, 2.0)) + 5.0 * sin(x * 0.025 + z * 0.018)

func _outer_stream_x(z: float) -> float:
	var dz := maxf(0.0, z - 26.0)
	return float(game.Layout.stream_center_x(26.0)) + sin(dz * 0.056) * 8.0

func _outer_foothill_weight(x: float, z: float) -> float:
	var center_dist := Vector2(x, z + 44.0).length()
	var south_plain := exp(-pow((x - 16.0) / 68.0, 2.0)) * smoothstep(70.0, 195.0, z)
	return smoothstep(162.0, 265.0, center_dist) * (1.0 - 0.65 * south_plain)

func _outer_valley_y(x: float, z: float) -> float:
	var ix := clampf(x, -56.0, 56.0)
	var iz := clampf(z, -116.0, 28.0)
	var dx := maxf(0.0, maxf(-56.0 - x, x - 56.0))
	var dz := maxf(0.0, maxf(-116.0 - z, z - 28.0))
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.01:
		return game.terrain_height(ix, iz) - 0.06
	var edge_y: float = game.terrain_height(ix, iz) - 0.06
	var north_w := smoothstep(-110.0, -142.0, z) * (1.0 - smoothstep(52.0, 96.0, absf(x)))
	var north_h := _hill_height(x, z)
	# Broad terraced lowland rice paddies surrounding East, West & South hillsides
	var raw_terrace := -11.4 + 1.6 * sin(x * 0.024 + z * 0.016) + 0.9 * cos(z * 0.028)
	var quantized := floorf((raw_terrace + 13.0) / 2.2) * 2.2 - 13.0
	var valley_floor := lerpf(raw_terrace, quantized, 0.56)
	var down_t := smoothstep(2.0, 28.0, d)
	var rural_y := lerpf(edge_y, valley_floor, down_t)
	rural_y = lerpf(rural_y, north_h, north_w * smoothstep(8.0, 38.0, d))
	var center_dist := Vector2(x, z + 44.0).length()
	var foothill_w := _outer_foothill_weight(x, z)
	var foothill_h := 6.0 + 18.0 * smoothstep(170.0, 280.0, center_dist) + 8.5 * sin(x * 0.027 - z * 0.021) + 5.5 * cos(x * 0.016 + z * 0.031)
	var land_y := lerpf(rural_y, foothill_h, foothill_w)
	# Subtle recessed riverbed channel along Southern irrigation creek (z = 26..165)
	if z >= 25.0 and z <= 170.0:
		var sx := _outer_stream_x(z)
		var sd := absf(x - sx)
		if sd < 6.5:
			var bed_t := (1.0 - smoothstep(1.2, 6.5, sd)) * (1.0 - smoothstep(145.0, 170.0, z))
			land_y -= 0.52 * bed_t
	return land_y

func _outer_valley_normal(x: float, z: float) -> Vector3:
	var eps := 4.0
	return Vector3(
		_outer_valley_y(x - eps, z) - _outer_valley_y(x + eps, z),
		2.0 * eps,
		_outer_valley_y(x, z - eps) - _outer_valley_y(x, z + eps)
	).normalized()

func _backdrop():
	# 1) 360-degree stepped terraced rural rice-paddy valley seamlessly swelling into outer 3D foothills
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	for z in range(-332, 244, 8):
		for x in range(-288, 288, 8):
			if x >= -56 and x < 56 and z >= -116 and z < 28:
				continue
			var pts = [
				Vector3(x, _outer_valley_y(x, z), z),
				Vector3(x, _outer_valley_y(x, z + 8), z + 8),
				Vector3(x + 8, _outer_valley_y(x + 8, z), z),
				Vector3(x + 8, _outer_valley_y(x + 8, z + 8), z + 8)
			]
			var ns = [
				_outer_valley_normal(x, z),
				_outer_valley_normal(x, z + 8),
				_outer_valley_normal(x + 8, z),
				_outer_valley_normal(x + 8, z + 8)
			]
			for i in [0, 2, 1, 2, 3, 1]:
				var p: Vector3 = pts[i]
				var n: Vector3 = ns[i]
				vertices.append(p)
				normals.append(n)
				uvs.append(Vector2(p.x, p.z) * 0.015)
				var dx := maxf(0.0, maxf(-56.0 - p.x, p.x - 56.0))
				var dz := maxf(0.0, maxf(-116.0 - p.z, p.z - 28.0))
				var d := sqrt(dx * dx + dz * dz)
				var fh := _outer_foothill_weight(p.x, p.z)
				var paddy_w := smoothstep(20.0, 40.0, d) * (1.0 - smoothstep(-6.5, -2.0, p.y))
				var slope_flat := smoothstep(0.86, 0.96, n.y)
				colors.append(Color(paddy_w * slope_flat, clampf(d / 220.0, 0.0, 1.0), fh))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var valley = MeshInstance3D.new()
	valley.name = "OuterRiceValley"
	valley.mesh = mesh
	var paddy_shader = Shader.new()
	paddy_shader.code = """shader_type spatial;
uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D paddy_tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
varying float edge_d;
varying float foothill_f;
void vertex(){
 wpos = VERTEX;
 edge_d = COLOR.g * 220.0;
 foothill_f = COLOR.b;
}
void fragment(){
 vec2 soil_uv = wpos.xz * 0.28;
 vec3 s_tex = texture(soil, soil_uv).rgb;
 float patch_n = 0.5 + 0.5 * sin(wpos.x * 0.27 + sin(wpos.z * 0.21) * 2.0);
 vec3 greenery = mix(vec3(0.28, 0.35, 0.19), vec3(0.42, 0.44, 0.27), patch_n);
 vec3 near_grass = s_tex * greenery * 1.42;

 // Natural textured foothill forest canopy matching foreground mountain green reflectance
 vec3 canopy_tex = texture(soil, wpos.xz * 0.048).rgb;
 float forest_n = 0.5 + 0.5 * sin(wpos.x * 0.065 + cos(wpos.z * 0.055) * 2.2);
 float ridge_var = 0.5 + 0.5 * sin(wpos.x * 0.025 - wpos.z * 0.029);
 vec3 lush_hill = mix(vec3(0.14, 0.22, 0.12), vec3(0.24, 0.31, 0.18), forest_n);
 vec3 far_hill_col = mix(s_tex, canopy_tex, 0.62) * lush_hill * mix(1.00, 1.24, ridge_var);
 vec3 slope_col = mix(near_grass, far_hill_col, smoothstep(8.0, 52.0, edge_d));

 vec3 p_tex = texture(paddy_tex, UV).rgb;
 float macro_dapple = 0.88 + 0.14 * sin(wpos.x * 0.022 + wpos.z * 0.018);
 vec3 paddy_col = p_tex * macro_dapple * 0.62;

 float paddy_t = clamp(COLOR.r, 0.0, 1.0) * (1.0 - foothill_f * 0.96);
 ALBEDO = mix(slope_col, paddy_col, paddy_t);
 NORMAL_MAP = texture(soil_normal, soil_uv).rgb;
 NORMAL_MAP_DEPTH = mix(0.50, 0.12, smoothstep(10.0, 75.0, edge_d));
 ROUGHNESS = mix(0.96, 0.90, paddy_t);
 SPECULAR = 0.02;
}
"""
	var pmat = ShaderMaterial.new()
	pmat.shader = paddy_shader
	pmat.set_shader_parameter("soil", load("res://assets/slice/ground_color.jpg"))
	pmat.set_shader_parameter("soil_normal", load("res://assets/slice/ground_normal.jpg"))
	if ResourceLoader.exists("res://assets/slice/rural_paddies_albedo.png"):
		pmat.set_shader_parameter("paddy_tex", load("res://assets/slice/rural_paddies_albedo.png"))
	valley.material_override = pmat
	valley.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(valley)

	# 2) Distant Southern irrigation creek nestled inside its carved riverbed channel
	var ov_verts = PackedVector3Array()
	var ov_uvs = PackedVector2Array()
	var segs := 20
	for i in segs:
		var z0 := 32.0 + float(i) * 6.8
		var z1 := z0 + 6.8
		var cx0 := _outer_stream_x(z0)
		var cx1 := _outer_stream_x(z1)
		var y0 := _outer_valley_y(cx0, z0) + 0.08
		var y1 := _outer_valley_y(cx1, z1) + 0.08
		var hw0 := 1.35 + float(i) * 0.08
		var hw1 := 1.35 + float(i + 1) * 0.08
		var q = [Vector3(cx0 - hw0, y0, z0), Vector3(cx0 + hw0, y0, z0), Vector3(cx1 - hw1, y1, z1), Vector3(cx1 + hw1, y1, z1)]
		var quv = [Vector2(0, float(i)), Vector2(1, float(i)), Vector2(0, float(i + 1)), Vector2(1, float(i + 1))]
		for k in [0, 1, 2, 1, 3, 2]:
			ov_verts.append(q[k])
			ov_uvs.append(quv[k])
	var ov_arr = []
	ov_arr.resize(Mesh.ARRAY_MAX)
	ov_arr[Mesh.ARRAY_VERTEX] = ov_verts
	ov_arr[Mesh.ARRAY_TEX_UV] = ov_uvs
	var ov_mesh = ArrayMesh.new()
	ov_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ov_arr)
	var ov_inst = MeshInstance3D.new()
	ov_inst.mesh = ov_mesh
	var ov_shader = Shader.new()
	ov_shader.code = """shader_type spatial;
render_mode blend_mix, cull_disabled;
void fragment(){
 float edge = abs(UV.x - 0.5) * 2.0;
 float head = smoothstep(0.0, 2.2, UV.y);
 float flow = 0.5 + 0.5 * sin(UV.y * 8.0 - TIME * 2.2);
 ALBEDO = mix(vec3(0.06, 0.16, 0.18), vec3(0.10, 0.25, 0.27), flow);
 ROUGHNESS = 0.88;
 SPECULAR = 0.03;
 ALPHA = head * mix(0.80, 0.0, smoothstep(0.45, 1.0, edge));
}
"""
	var ov_mat = ShaderMaterial.new()
	ov_mat.shader = ov_shader
	ov_inst.material_override = ov_mat
	ov_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ov_inst)

	# 3) Rural Jiangnan cottages grouped in tree-sheltered valley hamlets + warm olive foothill pines (zero metallic foliage)
	var village_spots := [
		Vector3(-34, 0, 82), Vector3(-25, 0, 88), Vector3(-40, 0, 96), Vector3(-18, 0, 102),
		Vector3(8, 0, 86), Vector3(22, 0, 94), Vector3(31, 0, 84), Vector3(39, 0, 99),
		Vector3(48, 0, 114), Vector3(14, 0, 118), Vector3(-6, 0, 124), Vector3(-28, 0, 128),
		Vector3(96, 0, -48), Vector3(106, 0, -38), Vector3(114, 0, -24), Vector3(102, 0, -10),
		Vector3(122, 0, 4), Vector3(134, 0, 18), Vector3(92, 0, 22),
		Vector3(-96, 0, -34), Vector3(-108, 0, -18), Vector3(-116, 0, 4), Vector3(-102, 0, 26), Vector3(-124, 0, 42)
	]
	var house_mesh := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "horizon_farmhouse")
	if house_mesh != null:
		var house_tx: Array = []
		for j in village_spots.size():
			var hp: Vector3 = village_spots[j]
			hp.y = _outer_valley_y(hp.x, hp.z) - 0.14
			var hyaw := float(j % 4) * (PI * 0.5) + 0.18
			house_tx.append(Transform3D(Basis(Vector3.UP, hyaw).scaled(Vector3.ONE * 1.12), hp))
		_batch_direct(house_mesh, house_tx, false)

	var vtree_mesh := _extract_mesh("res://assets/nature/tree_pineRoundD.glb")
	if vtree_mesh != null:
		vtree_mesh = vtree_mesh.duplicate()
		var vleaf_mat: StandardMaterial3D = game._material(Color("354f2d"))
		vleaf_mat.roughness = 0.88
		var vbark_mat: StandardMaterial3D = game._material(Color("4f3e2d"))
		vbark_mat.roughness = 0.92
		vtree_mesh.surface_set_material(0, vleaf_mat)
		if vtree_mesh.get_surface_count() > 1:
			vtree_mesh.surface_set_material(1, vbark_mat)

		var tree_tx: Array = []
		# Anchor cohesive tree groves right beside village hamlets so cottages nestle into foliage
		for j in village_spots.size():
			var hp: Vector3 = village_spots[j]
			for t_i in 2:
				var ang := float(j * 3 + t_i) * 2.15
				var rad := 7.2 + float(t_i) * 4.4
				var tx_p := hp.x + cos(ang) * rad
				var tz_p := hp.z + sin(ang) * rad
				var ty_p := _outer_valley_y(tx_p, tz_p) - 0.15
				var ts := 4.2 + float((j + t_i) % 3) * 0.95
				tree_tx.append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * ts), Vector3(tx_p, ty_p, tz_p)))
		# Add hillside & outer foothill pine stands
		for k in 56:
			var angle := float(k) * 0.73
			var rad := 142.0 + float(k % 7) * 14.0
			var vx := sin(angle) * rad
			var vz := -44.0 + cos(angle) * (rad * 1.12)
			if vz < -118.0 and absf(vx) < 70.0:
				continue
			var vy := _outer_valley_y(vx, vz) - 0.18
			var ts := 5.0 + float(k % 4) * 1.1
			tree_tx.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * ts), Vector3(vx, vy, vz)))
		_batch_direct(vtree_mesh, tree_tx, false)

	# 4) 360-degree distant misty mountain range panorama cylinder harmonizing with sun azimuth & valley mist
	if ResourceLoader.exists("res://assets/slice/horizon_mountains.png"):
		var cyl := CylinderMesh.new()
		cyl.top_radius = 278.0
		cyl.bottom_radius = 278.0
		cyl.height = 112.0
		cyl.radial_segments = 48
		cyl.cap_top = false
		cyl.cap_bottom = false
		var sky_ring := MeshInstance3D.new()
		sky_ring.name = "HorizonMountainsSkirt"
		sky_ring.mesh = cyl
		sky_ring.position = Vector3(0, 22.0, -44.0)
		var ring_shader := Shader.new()
		ring_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform sampler2D pano : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.42, 0.73, -0.54);
varying vec3 wpos;
void vertex(){
 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
 vec2 uv = vec2(UV.x * 2.0, UV.y);
 vec4 t = texture(pano, uv);
 vec3 view_xz = normalize(vec3(wpos.x, 0.0, wpos.z + 44.0));
 vec3 sun_xz = normalize(vec3(sun_dir.x, 0.0, sun_dir.z));
 float sun_align = 0.5 + 0.5 * dot(view_xz, sun_xz);
 vec3 ridge_col = t.rgb * mix(0.86, 1.04, sun_align);
 float bottom_mist = smoothstep(0.66, 0.90, UV.y);
 ridge_col = mix(ridge_col, vec3(0.44, 0.54, 0.47), bottom_mist * 0.55);
 ALBEDO = ridge_col;
 ALPHA = t.a;
}
"""
		var rmat := ShaderMaterial.new()
		rmat.shader = ring_shader
		rmat.set_shader_parameter("pano", load("res://assets/slice/horizon_mountains.png"))
		var sun_node := get_children().filter(func(n): return n is DirectionalLight3D)
		if not sun_node.is_empty():
			rmat.set_shader_parameter("sun_dir", sun_node[0].transform.basis.z.normalized())
		sky_ring.material_override = rmat
		sky_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sky_ring)

func _trees():
	var trunk_material = game._material(Color("9a9681"))
	trunk_material.albedo_texture = load("res://assets/slice/tree_bark.jpg")
	trunk_material.uv1_scale = Vector3(1, 5, 1)
	var shader = Shader.new()
	shader.code = """shader_type spatial; render_mode cull_disabled;
uniform sampler2D needles : source_color,filter_linear_mipmap;
uniform sampler2D mask : filter_linear_mipmap;
void vertex(){VERTEX.x+=sin(TIME+MODEL_MATRIX[3].x+VERTEX.y)*0.035*UV.y;}
void fragment(){ALBEDO=texture(needles,UV).rgb*0.8; ALPHA=texture(mask,UV).r;ALPHA_SCISSOR_THRESHOLD=0.48;ROUGHNESS=0.92;}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("needles", load("res://assets/slice/tree_needles.jpg"))
	mat.set_shader_parameter("mask", load("res://assets/slice/tree_alpha.jpg"))
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners = [Vector3(-1.5, -1.7, 0), Vector3(1.5, -1.7, 0), Vector3(1.5, 1.7, 0), Vector3(-1.5, 1.7, 0)]
	var uv = [Vector2(0, 0.45), Vector2(0.22, 0.45), Vector2(0.22, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_uv(uv[i])
		st.add_vertex(corners[i])
	st.generate_normals()
	var crowns = []
	var trunks = []
	for raw in [Vector3(-17, 0, -4), Vector3(24, 0, -8), Vector3(-29, 0, -19), Vector3(24, 0, -18), Vector3(-37, 0, -30), Vector3(24, 0, -42), Vector3(-32, 0, -53), Vector3(28, 0, -63), Vector3(-25, 0, -76), Vector3(33, 0, -91), Vector3(-7, 0, -107), Vector3(32, 0, -3)]:
		var at = game.Layout.on_ground(raw)
		var h = rng.randf_range(9, 13)
		trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, h, 1)), at + Vector3.UP * h / 2))
		var shape = CylinderShape3D.new()
		shape.radius = 0.28
		shape.height = h
		game.Props.shape_body(self, shape, at + Vector3.UP * h / 2)
		for level in 4:
			var radius = 1.8 - level * 0.36
			for i in 5:
				var angle = TAU * i / 5 + level * 0.7
				var pos = at + Vector3(sin(angle) * radius, h * (0.56 + 0.085 * level), cos(angle) * radius)
				crowns.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(1.3 - level * 0.17, 1.2 - level * 0.14, 1)), pos))
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.height = 1
	cylinder_mesh.bottom_radius = 0.28
	cylinder_mesh.top_radius = 0.09
	cylinder_mesh.radial_segments = 10
	_batch(cylinder_mesh, trunk_material, trunks, true)
	_batch(st.commit(), mat, crowns, true)

func rock(at: Vector3, height: float, index: int):
	var path = "res://assets/nature/rock_largeA.glb" if rock_paths.is_empty() else rock_paths[index % rock_paths.size()]
	var grounded_y = game.Layout.min_ground_height(at.x, at.z, height * 0.72) - (0.36 + height * 0.08)
	return game._model(self, path, Vector3(at.x, grounded_y, at.z), height, rng.randf_range(0, TAU), "convex")

func signpost(at: Vector3, text: String):
	var base_y = game.Layout.min_ground_height(at.x, at.z, 0.35) - 0.05
	var root = Node3D.new()
	root.position = Vector3(at.x, base_y, at.z)
	add_child(root)
	var post = game._mesh_box(root, Vector3(0, 0.98, 0), Vector3(0.15, 2.0, 0.15), Color.WHITE, true)
	post.material_override = wood_post_mat
	var board = game._mesh_box(root, Vector3(0, 1.86, 0), Vector3(2.55, 0.96, 0.14), Color.WHITE, true)
	board.material_override = roof_slate_mat
	var trim = game._mesh_box(root, Vector3(0, 2.36, 0), Vector3(2.68, 0.08, 0.20), Color.WHITE)
	trim.material_override = wood_plank_mat
	var label = game._label3d(root, text, Vector3(0, 1.86, 0.09), 30, Color("f0edd2"))
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.pixel_size = 0.0066

var container_yard: Dictionary = {}
var bamboo_shelter: Dictionary = {}
var watchtower_pos: Vector3 = Vector3.ZERO

func shelter(at: Vector3, title: String, with_parkour := false) -> Dictionary:
	var base_y = game.Layout.min_ground_height(at.x, at.z, 2.4) - 0.08
	var root = Node3D.new()
	root.position = Vector3(at.x, base_y, at.z)
	add_child(root)
	for x in [-2.5, 2.5]:
		for z in [-1.8, 1.8]:
			var p = game._mesh_box(root, Vector3(x, 1.72, z), Vector3(0.20, 3.55, 0.20), Color.WHITE, true)
			p.material_override = wood_post_mat
	for x in [-2.5, 2.5]:
		var beam = game._mesh_box(root, Vector3(x, 3.30, 0), Vector3(0.18, 0.16, 3.85), Color.WHITE)
		beam.material_override = wood_plank_mat
	for z in [-1.5, -0.6, 0.3, 1.2]:
		var plank = game._mesh_box(root, Vector3(0, 3.42, z), Vector3(5.8, 0.13, 0.94), Color.WHITE, true)
		plank.material_override = roof_slate_mat
	var table = game._mesh_box(root, Vector3(0, 1.02, -1.35), Vector3(3.5, 0.12, 0.82), Color.WHITE, true)
	table.material_override = wood_plank_mat
	for x in [-1.5, 1.5]:
		var leg = game._mesh_box(root, Vector3(x, 0.50, -1.35), Vector3(0.16, 1.05, 0.62), Color.WHITE, true)
		leg.material_override = wood_post_mat
	var l = game._label3d(root, title, Vector3(0, 2.68, 1.92), 32, Color("f0e8c4"))
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	if with_parkour:
		# Route B: 5-step timber scaffolding climbing up the East/NE flank onto the solid roof deck (all dy <= 0.58m)
		var stairs := [
			[Vector3(3.85, 0.62, 1.55), Vector2(1.55, 1.55), 0.72],
			[Vector3(3.85, 1.20, -0.10), Vector2(1.55, 1.55), 1.30],
			[Vector3(3.85, 1.78, -1.75), Vector2(1.65, 1.65), 1.88],
			[Vector3(2.45, 2.36, -2.75), Vector2(1.60, 1.55), 2.46],
			[Vector3(0.65, 2.94, -2.75), Vector2(1.65, 1.55), 3.04]
		]
		for st in stairs:
			TacticalProps.build_parkour_step(root, game, st[0], st[1], 0.14, st[2], true, true)
	return {
		"root": root,
		"roof_spot": root.position + Vector3(-1.15, 3.485, 0.05),
		"balcony_spot": root.position + Vector3(3.85, 1.78, -1.75)
	}

func _camp():
	TacticalProps.build_command_tent(self, game, Vector3(10.2, 0, 10.2), 1.02)
	TacticalProps.build_fuel_drum(self, game, Vector3(7.6, 0, 12.6), true)
	TacticalProps.build_fuel_drum(self, game, Vector3(6.9, 0, 13.1), false)
	if ResourceLoader.exists("res://assets/slice/crate.glb"):
		game._model(self, "res://assets/slice/crate.glb", Vector3(8.5, 0, 13.2), 0.56, 0.16, "convex")
		game._model(self, "res://assets/slice/crate.glb", Vector3(8.5, 0.55, 13.2), 0.42, -0.12, "convex")
	TacticalProps.build_armory_workbench(self, game, Vector3(11.6, 0, 6.4), 1.02)
	var low_rock_path = "res://assets/slice/rock_2.glb" if ResourceLoader.exists("res://assets/slice/rock_2.glb") else "res://assets/nature/rock_largeA.glb"
	game._model(self, low_rock_path, Vector3(-6, 0, 10), 0.55, 0, "convex").set_meta("kind", "low_rock")
	watchtower_pos = game.Layout.on_ground(game.Layout.WATCHTOWER)
	game._build_tower(watchtower_pos)
	bamboo_shelter = shelter(game.Layout.SHELTER_BAMBOO, "竹林补给棚", true)
	shelter(Vector3(1, 0, -58), "山路巡护站", false)
	# Route A: West Ridge ISO Cargo Container Parkour Yard
	container_yard = TacticalProps.build_cargo_container_yard(self, game, game.Layout.on_ground(game.Layout.PARKOUR_CONTAINERS))
	# Cave Grotto housing Tier-3 Airdrop Vault
	TacticalProps.build_cave_grotto(self, game, game.Layout.on_ground(game.Layout.CAVE_GROTTO))
	# v0.6.0 Jiangnan Rural Hill Heritage Landmarks & Ancient Bluestone Footpaths
	_build_jiangnan_heritage()
	# Deep Cache landmarks: Twin-Rock Cleft, East Overlook Boulder Alcove, SE Bamboo Crag
	rock(game.Layout.CLEFT_CACHE + Vector3(-2.6, 0, -0.4), 2.8, 1)
	rock(game.Layout.CLEFT_CACHE + Vector3(2.6, 0, -0.2), 2.6, 2)
	rock(game.Layout.EAST_OVERLOOK + Vector3(2.5, 0, -1.6), 2.5, 0)
	rock(game.Layout.SE_BAMBOO_CACHE + Vector3(2.6, 0, -1.4), 2.6, 3)
	for data in game.Layout.STATIONS:
		var station = game.Challenge.new()
		game.add_child(station)
		station.setup(game, data)
		game.stations.append(station)
	for info in [
		[Vector3(-9, 0, 7), "烟山基地\nA · 山脚营地"],
		[Vector3(-12, 0, -17), "林间前哨  ↑\n石刻支路  ←"],
		[Vector3(-20, 0, -28), "← 烟山诗碑亭\n主路前哨  →"],
		[Vector3(22.4, 0, -21.5), "东上望稻亭 ↗\n北探石崖奇岩 ↑"],
		[Vector3(-14, 0, -53), "巡护站近道 →\n山道拦截哨 ↑"],
		[Vector3(14, 0, -72), "B · 撤离信标\n260分·2哨·首领"]
	]:
		signpost(info[0], info[1])

func _landmarks():
	game._make_crate("前哨补给箱", 1, game.Layout.on_ground(Vector3(-6, 0, -39)))
	var crate_roof = game._make_crate("竹林棚顶精密箱", 2, bamboo_shelter.roof_spot)
	crate_roof.set_meta("secret_key", "shelter_and_tower")
	var crate_cave = game._make_crate("山崖秘窟空投箱", 3, game.Layout.on_ground(game.Layout.CAVE_GROTTO))
	crate_cave.set_meta("secret_key", "cave_grotto")
	var crate_tower = game._make_crate("观察哨顶层秘宝", 2, watchtower_pos + Vector3(0.18, 5.92, -0.20))
	crate_tower.set_meta("secret_key", "shelter_and_tower")
	var crate_container = game._make_crate("西岭货柜暗箱", 2, container_yard.top_deck + Vector3(0.45, 0.0, 0.0))
	crate_container.set_meta("secret_key", "parkour_containers")
	for crate in game.crate_nodes:
		TacticalProps.build_tiered_vault_crate(game, crate, int(crate.get_meta("tier")))

	var pad = MeshInstance3D.new()
	var ring = TorusMesh.new()
	ring.inner_radius = 2.9
	ring.outer_radius = 3.08
	ring.rings = 32
	ring.ring_segments = 8
	pad.mesh = ring
	pad.position = game.exit_position + Vector3.UP * 0.1
	pad.material_override = game._material(game.MINT, true)
	add_child(pad)

	var inner_pad = MeshInstance3D.new()
	var inner_ring = TorusMesh.new()
	inner_ring.inner_radius = 1.6
	inner_ring.outer_radius = 1.72
	inner_ring.rings = 24
	inner_ring.ring_segments = 8
	inner_pad.mesh = inner_ring
	inner_pad.position = game.exit_position + Vector3.UP * 0.08
	inner_pad.material_override = game._material(game.GOLD, true)
	add_child(inner_pad)

	game._label3d(self, "B · 战术撤离信标\n260分 · 攻2哨 · 败统领", game.exit_position + Vector3.UP * 2.8, 40, game.MINT)

	var pickup_spots = [
		{"at": Vector3(5.2, 0, 7.2), "ground": true, "secret_key": ""},
		{"at": Vector3(-15, 0, -19), "ground": true, "secret_key": ""},
		{"at": Vector3(-23, 0, -29), "ground": true, "secret_key": ""},
		{"at": Vector3(-4, 0, -57), "ground": true, "secret_key": ""},
		{"at": Vector3(6, 0, -67), "ground": true, "secret_key": ""},
		{"at": Vector3(14.8, 0, -85.0), "ground": true, "secret_key": ""},
		{"at": game.Layout.CLEFT_CACHE, "ground": true, "secret_key": "cleft_cache"},
		{"at": container_yard.mid_deck, "ground": false, "secret_key": "parkour_containers"},
		{"at": game.Layout.EAST_OVERLOOK, "ground": true, "secret_key": "east_overlook"},
		{"at": game.Layout.SE_BAMBOO_CACHE, "ground": true, "secret_key": "se_bamboo_cache"}
	]
	for idx in pickup_spots.size():
		var spot: Dictionary = pickup_spots[idx]
		var pickup = Node3D.new()
		pickup.position = game.Layout.on_ground(spot.at) if spot.ground else spot.at
		pickup.set_meta("value", 45 if spot.secret_key != "" else 30)
		pickup.set_meta("supply_id", "supply_%d" % idx)
		pickup.set_meta("title", "隐秘物资箱 #%d" % (idx + 1) if spot.secret_key != "" else "常规物资箱 #%d" % (idx + 1))
		if spot.secret_key != "":
			pickup.set_meta("secret_key", spot.secret_key)
		game.add_child(pickup)
		TacticalProps.build_supply_box(game, pickup)
		var sup_hint := "深藏物资箱 · 单词解锁 [E]" if spot.secret_key != "" else "常规物资箱 · 单词解锁 [E]"
		game._label3d(pickup, sup_hint, Vector3(0, 0.96, 0), 26, Color("8ef0c8") if spot.secret_key != "" else game.GOLD)
		game.pickup_nodes.append(pickup)

	# Tactical Field Ammo Crates & Consumable Pouches (tactical_pickups.glb)
	var field_tactical = [
		{"at": Vector3(8.8, 0, 8.2), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "5.56 军用弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-5.5, 0, -21.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "5.56 军用弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(2.2, 0, -58.4), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "巡护站备弹箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-9.5, 0, -76.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "前哨弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(13.2, 0, -89.4), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "竹林弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-2.0, 0, -104.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "B区突击弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-17.8, 0, -34.2), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "石刻旁弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(7.4, 0, 10.6), "ground": true, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "烟雾/EMP 手雷", "col": Color("56e8ff"), "secret_key": ""},
		{"at": Vector3(0.4, 0, -58.5), "ground": true, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "烟雾/EMP 手雷", "col": Color("56e8ff"), "secret_key": ""},
		{"at": Vector3(15.2, 0, -88.2), "ground": true, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "烟雾/EMP 手雷", "col": Color("56e8ff"), "secret_key": ""},
		{"at": Vector3(-6.2, 0, -105.0), "ground": true, "kind": "energy_drink", "mesh": "pickup_energy_drink", "title": "肾上腺素能量饮", "col": Color("6ae3a8"), "secret_key": ""},
		{"at": Vector3(-1.4, 0, -57.2), "ground": true, "kind": "energy_drink", "mesh": "pickup_energy_drink", "title": "肾上腺素能量饮", "col": Color("6ae3a8"), "secret_key": ""},
		{"at": Vector3(11.5, 0, -87.4), "ground": true, "kind": "energy_drink", "mesh": "pickup_energy_drink", "title": "肾上腺素能量饮", "col": Color("6ae3a8"), "secret_key": ""},
		{"at": watchtower_pos + Vector3(0.45, 3.50, 0.45), "ground": false, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "观察哨备弹箱", "col": Color("ffd15c"), "secret_key": "shelter_and_tower"},
		{"at": container_yard.top_deck + Vector3(1.55, 0.0, 0.0), "ground": false, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "货柜高台备弹箱", "col": Color("ffd15c"), "secret_key": "parkour_containers"},
		{"at": bamboo_shelter.balcony_spot, "ground": false, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "棚侧烟雾EMP", "col": Color("56e8ff"), "secret_key": "shelter_and_tower"}
	]
	for idx in field_tactical.size():
		var td = field_tactical[idx]
		var node = Node3D.new()
		node.position = game.Layout.on_ground(td.at) if td.ground else td.at
		node.set_meta("tactical_item", td.kind)
		node.set_meta("tactical_id", "tac_%d" % idx)
		node.set_meta("title", td.title)
		if td.secret_key != "":
			node.set_meta("secret_key", td.secret_key)
		game.add_child(node)
		_attach_tactical_mesh(node, td.mesh, td.col)
		game.pickup_nodes.append(node)

func _attach_tactical_mesh(parent: Node3D, mesh_name: String, glow_col: Color):
	var path := "res://assets/slice/tactical_pickups.glb"
	if ResourceLoader.exists(path):
		if not game.scene_cache.has(path):
			game.scene_cache[path] = load(path)
		var inst: Node3D = game.scene_cache[path].instantiate()
		var sub = inst.find_child(mesh_name, true, false)
		if is_instance_valid(sub):
			inst.remove_child(sub)
			sub.owner = null
			sub.position = Vector3.ZERO
			sub.scale = Vector3.ONE * (1.85 if mesh_name != "pickup_ammo_crate" else 1.45)
			parent.add_child(sub)
		inst.queue_free()
	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 0.34
	tm.outer_radius = 0.42
	tm.rings = 16
	tm.ring_segments = 6
	ring.mesh = tm
	ring.position.y = 0.04
	ring.material_override = game._material(glow_col, true)
	parent.add_child(ring)
	var tag = "[E] %s" % parent.get_meta("title", "战术补给")
	game._label3d(parent, tag, Vector3(0, 0.72, 0), 22, glow_col)

func _stream():
	# Continuous animated mountain brook flowing downhill from Northern Spring (z=-111) out beneath South Fence (z=26.5)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var rows := []
	var z_cur := float(game.Layout.STREAM_Z_MIN)
	while z_cur <= float(game.Layout.STREAM_Z_MAX) + 0.51:
		var zc := minf(z_cur, float(game.Layout.STREAM_Z_MAX) + 0.5)
		var cx := float(game.Layout.stream_center_x(zc))
		var wy := float(game.Layout.stream_water_y(zc))
		var hw := 1.75 * smoothstep(-112.0, -108.0, zc)
		hw = maxf(hw, 0.55)
		var v_coord := (zc + 112.0) * 0.18
		rows.append([
			Vector3(cx - hw, wy, zc), Vector2(0.0, v_coord), Color(1.0, 0.0, 0.0),
			Vector3(cx, wy, zc), Vector2(0.5, v_coord), Color(0.0, 0.0, 0.0),
			Vector3(cx + hw, wy, zc), Vector2(1.0, v_coord), Color(1.0, 0.0, 0.0)
		])
		z_cur += 1.5
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for half in 2:
			var a := half * 3
			var b := (half + 1) * 3
			var p0: Vector3 = r0[a]
			var p1: Vector3 = r0[b]
			var p2: Vector3 = r1[a]
			var p3: Vector3 = r1[b]
			var quad_v := [p0, p1, p2, p3]
			var quad_u := [r0[a + 1], r0[b + 1], r1[a + 1], r1[b + 1]]
			var quad_c := [r0[a + 2], r0[b + 2], r1[a + 2], r1[b + 2]]
			for k in [0, 1, 2, 1, 3, 2]:
				verts.append(quad_v[k])
				normals.append(Vector3.UP)
				uvs.append(quad_u[k])
				colors.append(quad_c[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var wmesh := ArrayMesh.new()
	wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water := MeshInstance3D.new()
	water.name = "MountainStreamWater"
	water.mesh = wmesh
	var wshader := Shader.new()
	wshader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
varying float edge_t;
void vertex(){
 edge_t = COLOR.r;
 VERTEX.y += sin(TIME * 2.8 + VERTEX.z * 1.5 + VERTEX.x * 2.1) * 0.015 * (1.0 - edge_t * 0.6);
}
void fragment(){
 float flow = sin(UV.y * 11.0 - TIME * 2.9 + sin(UV.x * 6.5 + TIME * 0.8) * 0.85);
 float sparkle = smoothstep(0.66, 0.96, sin(UV.y * 20.0 - TIME * 4.4 + UV.x * 14.0));
 float foam = smoothstep(0.56, 0.95, edge_t * 0.82 + 0.14 * flow);
 vec3 col = mix(vec3(0.14, 0.45, 0.50), vec3(0.32, 0.68, 0.70), 0.45 + 0.38 * flow);
 col = mix(col, vec3(0.86, 0.96, 0.95), max(foam * 0.65, sparkle * 0.42));
 ALBEDO = col;
 ROUGHNESS = 0.14;
 SPECULAR = 0.78;
 ALPHA = mix(0.78, 0.40, edge_t * 0.85);
}
"""
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# Northern spring headwater boulders
	rock(Vector3(game.Layout.stream_center_x(-111.0), 0, -112.0), 2.4, 2)
	rock(Vector3(game.Layout.stream_center_x(-110.5) - 2.1, 0, -110.5), 1.8, 0)
	rock(Vector3(game.Layout.stream_center_x(-110.5) + 2.1, 0, -110.5), 1.9, 1)

	# 3 walkable creek crossings: South & North mountain wooden footbridges + Central v0.6.0 Stone Arch Bridge
	for bz in game.Layout.STREAM_BRIDGES:
		if is_equal_approx(float(bz), -24.0):
			_build_stone_arch_bridge(float(bz))
		else:
			_build_footbridge(float(bz))

	# Natural mossy river stones & stepping boulders (using textured Poly Haven mossy rocks so scale stays spherical/natural)
	var cx_step := float(game.Layout.stream_center_x(-73.5))
	var wy_step := float(game.Layout.stream_water_y(-73.5))
	for k_i in 3:
		var kx: float = [-1.1, 0.0, 1.1][k_i]
		game._model(self, "res://assets/slice/rock_%d.glb" % (k_i % 3), Vector3(cx_step + kx, wy_step - 0.14, -73.5 + kx * 0.25), 0.36, kx * 0.8, "convex")
	for r_i in 8:
		var rz: float = [-98.0, -82.0, -64.0, -52.0, -34.0, -14.0, 1.0, 14.5][r_i]
		var cx := float(game.Layout.stream_center_x(rz))
		var side := -1.85 if r_i % 2 == 0 else 1.85
		game._model(self, "res://assets/slice/rock_%d.glb" % (r_i % 3), Vector3(cx + side, game.terrain_height(cx + side, rz) - 0.12, rz), 0.44, rz * 0.4, "none")

	# Batched creek emerald lotus pads & pink blooms sitting cleanly flush on water surface
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.26
	pad_mesh.bottom_radius = 0.23
	pad_mesh.height = 0.024
	pad_mesh.radial_segments = 14
	var bloom_mesh := SphereMesh.new()
	bloom_mesh.radius = 0.075
	bloom_mesh.height = 0.11
	bloom_mesh.radial_segments = 10
	var pad_tx: Array = []
	var bloom_tx: Array = []
	for k_idx in 18:
		var lz := -98.0 + float(k_idx) * 6.8
		var cx := float(game.Layout.stream_center_x(lz))
		var wy := float(game.Layout.stream_water_y(lz)) + 0.008
		var off := (-0.42 if k_idx % 2 == 0 else 0.40) + sin(float(k_idx) * 1.7) * 0.16
		var ps := 0.85 + float(k_idx % 3) * 0.18
		pad_tx.append(Transform3D(Basis(Vector3.UP, float(k_idx) * 1.1).scaled(Vector3(ps, 1.0, ps)), Vector3(cx + off, wy, lz)))
		if k_idx % 2 == 0:
			bloom_tx.append(Transform3D(Basis.IDENTITY, Vector3(cx + off, wy + 0.045, lz)))
	_batch(pad_mesh, game._material(Color("3b8248")), pad_tx, false)
	_batch(bloom_mesh, game._material(Color("f4a6c6")), bloom_tx, false)

func _build_footbridge(z_center: float):
	var cx := float(game.Layout.stream_center_x(z_center))
	var wy := float(game.Layout.stream_water_y(z_center))
	var bank_w := float(game.terrain_height(cx - 4.4, z_center))
	var bank_e := float(game.terrain_height(cx + 4.4, z_center))
	var deck_y := maxf(wy + 0.70, maxf(bank_w, bank_e) + 0.22)
	var root := Node3D.new()
	root.name = "StreamBridge_%d" % int(roundi(z_center))
	root.position = Vector3(cx, deck_y, z_center)
	add_child(root)

	# Flat central timber span (4.8m x 2.15m) + low open side handrails
	var deck: Node3D = game._mesh_box(root, Vector3(0, -0.07, 0), Vector3(4.8, 0.14, 2.15), Color.WHITE, true)
	deck.material_override = wood_plank_mat
	for sz in [-0.98, 0.98]:
		var rail: Node3D = game._mesh_box(root, Vector3(0, 0.76, sz), Vector3(4.8, 0.09, 0.09), Color.WHITE, true)
		rail.material_override = wood_plank_mat
		var mid_rail: Node3D = game._mesh_box(root, Vector3(0, 0.38, sz), Vector3(4.8, 0.07, 0.07), Color.WHITE)
		mid_rail.material_override = wood_plank_mat
		for px in [-2.25, 0.0, 2.25]:
			var post: Node3D = game._mesh_box(root, Vector3(px, 0.32, sz), Vector3(0.12, 0.98, 0.12), Color.WHITE, true)
			post.material_override = wood_post_mat
	for sx in [-2.0, 2.0]:
		for sz in [-0.90, 0.90]:
			var pier: Node3D = game._mesh_box(root, Vector3(sx, -0.75, sz), Vector3(0.16, 1.4, 0.16), Color.WHITE, true)
			pier.material_override = wood_post_mat

	# Sloped approach ramps with rotated pivot (mesh + StaticBody3D together) flush at deck y=0
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var outer_x := cx + side_f * 4.4
		var outer_h := float(game.terrain_height(outer_x, z_center))
		var drop := maxf(0.24, deck_y - (outer_h - 0.10))
		var run := clampf(drop * 1.65, 2.0, 2.6)
		var ramp_len := sqrt(run * run + drop * drop) + 0.12
		var ramp_pivot := Node3D.new()
		ramp_pivot.position = Vector3(side_f * (2.4 + run * 0.5), -drop * 0.5, 0.0)
		ramp_pivot.rotation.z = -side_f * atan2(drop, run)
		root.add_child(ramp_pivot)
		var ramp: Node3D = game._mesh_box(ramp_pivot, Vector3(0, -0.07, 0), Vector3(ramp_len, 0.14, 2.15), Color.WHITE, true)
		ramp.material_override = wood_plank_mat

func _instantiate_v060_mesh(mesh_name: String) -> Node3D:
	var path := "res://assets/slice/v060_jiangnan_assets.glb"
	if ResourceLoader.exists(path):
		if not game.scene_cache.has(path):
			game.scene_cache[path] = load(path)
		var inst: Node3D = game.scene_cache[path].instantiate()
		var sub = inst.find_child(mesh_name, true, false)
		if is_instance_valid(sub):
			if sub.get_parent():
				sub.get_parent().remove_child(sub)
			sub.owner = null
			sub.position = Vector3.ZERO
			inst.queue_free()
			return sub
		inst.queue_free()
	return null

static func _arch_deck_y(x: float) -> float:
	var ax := absf(x)
	if ax <= 5.0:
		return 0.24 * (1.0 + cos(PI * ax / 5.0))
	return -0.22 * minf(1.0, (ax - 5.0) / 0.35)

func _build_stone_arch_bridge(z_center: float):
	var cx := float(game.Layout.stream_center_x(z_center))
	var wy := float(game.Layout.stream_water_y(z_center))
	var bank_w := float(game.terrain_height(cx - 5.0, z_center))
	var bank_e := float(game.terrain_height(cx + 5.0, z_center))
	var base_y := maxf(wy + 0.58, maxf(bank_w, bank_e) - 0.02)
	var root := Node3D.new()
	root.name = "StoneArchBridge"
	root.position = Vector3(cx, base_y, z_center)
	add_child(root)

	var visual := _instantiate_v060_mesh("stone_arch_bridge")
	if visual:
		root.add_child(visual)

	# 10 contiguous angled BoxShape3D deck slabs matching the gentle cosine stone arch (max ~8.6 deg)
	var steps := 10
	var span_dx := 10.0 / float(steps)
	for i in steps:
		var x0 := -5.0 + float(i) * span_dx
		var x1 := x0 + span_dx
		var y0 := _arch_deck_y(x0)
		var y1 := _arch_deck_y(x1)
		var xm := 0.5 * (x0 + x1)
		var ym := 0.5 * (y0 + y1)
		var seg_len := sqrt(span_dx * span_dx + (y1 - y0) * (y1 - y0)) + 0.14
		var shp := BoxShape3D.new()
		shp.size = Vector3(seg_len, 0.24, 2.24)
		var body: StaticBody3D = game.Props.shape_body(root, shp, Vector3(xm, ym - 0.12, 0.0))
		body.rotation.z = atan2(y1 - y0, span_dx)

	# Flush stone apron ramps linking both banks up to x=+-4.90 so walking +X needs no jump
	var apron_mat := StandardMaterial3D.new()
	apron_mat.albedo_color = Color("5c625e")
	apron_mat.albedo_texture = load("res://assets/slice/ground_color.jpg")
	apron_mat.roughness = 0.88
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var outer_x := cx + side_f * 6.05
		var outer_local_y := float(game.terrain_height(outer_x, z_center)) - base_y - 0.05
		var drop := maxf(0.05, _arch_deck_y(side_f * 4.90) - outer_local_y)
		var run := 1.25
		var ramp_len := sqrt(run * run + drop * drop) + 0.16
		var pivot := Node3D.new()
		pivot.position = Vector3(side_f * (4.90 + run * 0.5), _arch_deck_y(side_f * 4.90) - drop * 0.5, 0.0)
		pivot.rotation.z = -side_f * atan2(drop, run)
		root.add_child(pivot)
		var slab: Node3D = game._mesh_box(pivot, Vector3(0, -0.07, 0), Vector3(ramp_len, 0.14, 2.26), Color.WHITE, true)
		slab.material_override = apron_mat

	# Carved stone balustrade side colliders keeping bridge width wide (2.1m clear)
	for sz in [-1.18, 1.18]:
		for sx in [-1.0, 1.0]:
			var rail_shp := BoxShape3D.new()
			rail_shp.size = Vector3(4.95, 0.86, 0.24)
			var rail_body: StaticBody3D = game.Props.shape_body(root, rail_shp, Vector3(sx * 2.45, 0.48, sz))
			rail_body.rotation.z = -sx * 0.09

	# West bridgehead engraved Boundary Stele ("烟山古道 / 东望诚庄稻田 / 西入竹石深林")
	var stele_at: Vector3 = game.Layout.on_ground(Vector3(cx - 5.75, 0.0, z_center + 2.45))
	var stele_root := Node3D.new()
	stele_root.name = "BoundaryStele"
	stele_root.position = stele_at
	stele_root.rotation.y = deg_to_rad(-28.0)
	add_child(stele_root)
	var stele_vis := _instantiate_v060_mesh("boundary_stele")
	if stele_vis:
		stele_root.add_child(stele_vis)
	var stele_shp := BoxShape3D.new()
	stele_shp.size = Vector3(0.84, 1.95, 0.42)
	game.Props.shape_body(stele_root, stele_shp, Vector3(0, 0.96, 0))

func _build_jiangnan_heritage():
	# 1) Wangdao Pavilion ("望稻亭") perched on the SE bluff overlooking Southern OuterRiceValley paddies & hamlets
	var pav_at: Vector3 = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION)
	var pav := Node3D.new()
	pav.name = "WangdaoPavilion"
	pav.position = pav_at
	pav.rotation.y = deg_to_rad(-102.0)
	add_child(pav)
	var pav_vis := _instantiate_v060_mesh("wangdao_pavilion")
	if pav_vis:
		pav.add_child(pav_vis)

	# Walkable plinth deck + flush entry step ramps on West (-X) and South (+Z) rising cleanly above y=0.28 before plinth edge
	var floor_shp := BoxShape3D.new()
	floor_shp.size = Vector3(4.45, 0.28, 4.45)
	game.Props.shape_body(pav, floor_shp, Vector3(0, 0.14, 0))
	var step_tilt := 0.245
	var step_w := BoxShape3D.new()
	step_w.size = Vector3(1.56, 0.18, 1.95)
	var sw_body: StaticBody3D = game.Props.shape_body(pav, step_w, Vector3(-2.78, 0.053, 0.0))
	sw_body.rotation.z = step_tilt
	var step_s := BoxShape3D.new()
	step_s.size = Vector3(1.95, 0.18, 1.56)
	var ss_body: StaticBody3D = game.Props.shape_body(pav, step_s, Vector3(0.0, 0.053, 2.78))
	ss_body.rotation.x = step_tilt

	# Columns, table & waist-high overlook balustrade colliders (wide West & South walk-in doorways)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var col_shp := BoxShape3D.new()
			col_shp.size = Vector3(0.28, 2.6, 0.28)
			game.Props.shape_body(pav, col_shp, Vector3(sx * 1.60, 1.50, sz * 1.60))
	var north_bench := BoxShape3D.new()
	north_bench.size = Vector3(3.05, 0.92, 0.44)
	game.Props.shape_body(pav, north_bench, Vector3(0.0, 0.68, -1.58))
	var east_rail := BoxShape3D.new()
	east_rail.size = Vector3(0.20, 0.86, 3.05)
	game.Props.shape_body(pav, east_rail, Vector3(1.58, 0.68, 0.0))
	var table_shp := CylinderShape3D.new()
	table_shp.radius = 0.52
	table_shp.height = 0.88
	game.Props.shape_body(pav, table_shp, Vector3(0.0, 0.66, 0.0))

	# 2) Ancient Camphor Tree + Mossy Earth-God Wayside Shrine ("百年古樟 & 土地石龛") beside trail bend
	var camphor_at: Vector3 = game.Layout.on_ground(game.Layout.CAMPHOR_SHRINE)
	var cs_root := Node3D.new()
	cs_root.name = "CamphorShrine"
	cs_root.position = camphor_at
	add_child(cs_root)

	var camphor_vis := _instantiate_v060_mesh("ancient_camphor")
	if camphor_vis:
		cs_root.add_child(camphor_vis)
	var trunk_shp := CylinderShape3D.new()
	trunk_shp.radius = 0.56
	trunk_shp.height = 3.2
	game.Props.shape_body(cs_root, trunk_shp, Vector3(0.0, 1.6, 0.0))

	var shrine_off := Vector3(2.15, 0.0, 1.55)
	var shrine_ground: float = float(game.terrain_height(camphor_at.x + shrine_off.x, camphor_at.z + shrine_off.z)) - camphor_at.y
	var shrine_node := Node3D.new()
	shrine_node.name = "WaysideShrine"
	shrine_node.position = Vector3(shrine_off.x, shrine_ground, shrine_off.z)
	shrine_node.rotation.y = deg_to_rad(-28.0)
	cs_root.add_child(shrine_node)
	var shrine_vis := _instantiate_v060_mesh("wayside_shrine")
	if shrine_vis:
		shrine_node.add_child(shrine_vis)
	var shrine_shp := BoxShape3D.new()
	shrine_shp.size = Vector3(1.52, 1.92, 1.28)
	game.Props.shape_body(shrine_node, shrine_shp, Vector3(0.0, 0.96, 0.0))
	if not low_quality:
		var candle_glow := OmniLight3D.new()
		candle_glow.position = Vector3(0.0, 0.66, 0.62)
		candle_glow.light_color = Color("ffb862")
		candle_glow.light_energy = 0.95
		candle_glow.omni_range = 3.2
		candle_glow.shadow_enabled = false
		shrine_node.add_child(candle_glow)
	var shrine_lbl: Label3D = game._label3d(shrine_node, "土地石龛 · 百年古樟", Vector3(0.0, 2.18, 0.22), 20, Color("f3ead0"))
	shrine_lbl.pixel_size = 0.0028
	shrine_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shrine_lbl.visibility_range_end = 10.5

	# 3) MultiMesh Bluestone Ancient Footpath Slabs tilted flush to hillside slopes in 1 draw call
	var flag_vis := _instantiate_v060_mesh("bluestone_flagstone")
	var flag_mesh: Mesh = null
	if flag_vis is MeshInstance3D:
		flag_mesh = flag_vis.mesh
	elif flag_vis:
		for child in flag_vis.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi and mi.mesh:
				flag_mesh = mi.mesh
				break
	if flag_vis:
		flag_vis.queue_free()
	if flag_mesh != null:
		var trail_polylines := [
			[Vector3(3.5, 0, -18.0), Vector3(7.4, 0, -21.2), Vector3(11.3, 0, -24.0)],
			[Vector3(21.7, 0, -24.0), Vector3(28.5, 0, -8.0), Vector3(32.5, 0, 8.0), Vector3(34.1, 0, 17.6)],
			[Vector3(22.4, 0, 7.0), Vector3(27.5, 0, 12.8), Vector3(30.4, 0, 19.8)],
			[Vector3(-18.2, 0, -27.2), Vector3(-23.0, 0, -27.6), Vector3(-28.0, 0, -26.5)]
		]
		var xfs: Array[Transform3D] = []
		var rng_t := RandomNumberGenerator.new()
		rng_t.seed = 2026060
		for poly in trail_polylines:
			for i in poly.size() - 1:
				var a: Vector3 = poly[i]
				var b: Vector3 = poly[i + 1]
				var delta := Vector2(b.x - a.x, b.z - a.z)
				var dist := delta.length()
				var steps_f := maxi(1, int(dist / 0.96))
				var base_yaw := atan2(delta.y, delta.x)
				for k in steps_f:
					var t := (float(k) + 0.5) / float(steps_f)
					var zig := rng_t.randf_range(-0.14, 0.14) + (0.09 if k % 2 == 0 else -0.09)
					var px := lerpf(a.x, b.x, t) + zig * sin(base_yaw)
					var pz := lerpf(a.z, b.z, t) - zig * cos(base_yaw)
					var py := float(game.terrain_height(px, pz)) - 0.015
					var hx0 := float(game.terrain_height(px - 0.45, pz))
					var hx1 := float(game.terrain_height(px + 0.45, pz))
					var hz0 := float(game.terrain_height(px, pz - 0.45))
					var hz1 := float(game.terrain_height(px, pz + 0.45))
					var surf_up := Vector3(hx0 - hx1, 0.90, hz0 - hz1).normalized()
					var yaw := -base_yaw + rng_t.randf_range(-0.10, 0.10)
					var right := Vector3(cos(yaw), 0.0, -sin(yaw))
					var fwd := surf_up.cross(right).normalized()
					right = fwd.cross(surf_up).normalized()
					var basis := Basis(right, surf_up, fwd).scaled(Vector3(
						rng_t.randf_range(0.88, 1.08),
						1.0,
						rng_t.randf_range(0.88, 1.06)
					))
					xfs.append(Transform3D(basis, Vector3(px, py, pz)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = flag_mesh
		mm.instance_count = xfs.size()
		for idx in xfs.size():
			mm.set_instance_transform(idx, xfs[idx])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BluestoneFlagstones"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _flora_meadows():
	# 1) MultiMesh wildflower carpets, woodland mushrooms & dense hillside shrubs (7 batched draw calls!)
	var red_f := _extract_mesh("res://assets/nature/flower_redA.glb")
	var yel_f := _extract_mesh("res://assets/nature/flower_yellowA.glb")
	var pur_f := _extract_mesh("res://assets/nature/flower_purpleA.glb")
	var mush_f := _extract_mesh("res://assets/nature/mushroom_redGroup.glb")
	var bush_f := _extract_mesh("res://assets/nature/plant_bushDetailed.glb")
	var orchid_f := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "flora_glow_orchid")
	var fern_f := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "flora_berry_fern")

	var red_tx: Array = []
	var yel_tx: Array = []
	var pur_tx: Array = []
	var mush_tx: Array = []
	var bush_tx: Array = []
	var orchid_tx: Array = []
	var fern_tx: Array = []

	for i in 240:
		var fx := rng.randf_range(-47.5, 47.5)
		var fz := rng.randf_range(-108.0, 22.0)
		if game.Layout.clear_for_route(fx, fz, 0.9) or game.Layout.stream_distance(fx, fz) < 2.25:
			continue
		var fy := float(game.terrain_height(fx, fz))
		var yaw := rng.randf_range(0.0, TAU)
		var r_choice := i % 7
		if r_choice == 0 or r_choice == 1:
			red_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.62, 0.92)), Vector3(fx, fy - 0.02, fz)))
		elif r_choice == 2 or r_choice == 3:
			yel_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.62, 0.92)), Vector3(fx, fy - 0.02, fz)))
		elif r_choice == 4:
			pur_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.64, 0.95)), Vector3(fx, fy - 0.02, fz)))
		elif r_choice == 5:
			mush_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.55, 0.85)), Vector3(fx, fy - 0.02, fz)))
		else:
			bush_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.75, 1.25)), Vector3(fx, fy - 0.04, fz)))

	# Cluster exotic orchids & berry ferns near creek banks, bridges, overlooks & caves
	var special_spots := [
		Vector3(14.5, 0, 12.0), Vector3(13.8, 0, -18.5), Vector3(22.5, 0, -29.0),
		Vector3(21.2, 0, -43.0), Vector3(23.2, 0, -64.0), Vector3(21.5, 0, -78.0),
		Vector3(21.2, 0, -96.0), Vector3(-22.0, 0, -69.5), Vector3(-27.2, 0, -24.5),
		Vector3(-25.0, 0, -49.0), Vector3(8.5, 0, 14.5), Vector3(28.5, 0, -83.5)
	]
	for idx in special_spots.size():
		var sp: Vector3 = special_spots[idx]
		var sy := float(game.terrain_height(sp.x, sp.z))
		var tx := Transform3D(Basis(Vector3.UP, float(idx) * 0.95).scaled(Vector3.ONE * 1.15), Vector3(sp.x, sy, sp.z))
		if idx % 2 == 0:
			orchid_tx.append(tx)
		else:
			fern_tx.append(tx)

	_batch_direct(red_f, red_tx, false)
	_batch_direct(yel_f, yel_tx, false)
	_batch_direct(pur_f, pur_tx, false)
	_batch_direct(mush_f, mush_tx, false)
	_batch_direct(bush_f, bush_tx, false)
	_batch_direct(orchid_f, orchid_tx, false)
	_batch_direct(fern_f, fern_tx, false)

func _fence_bay_transform(p0: Vector3, p1: Vector3) -> Transform3D:
	var tangent := (p1 - p0).normalized()
	var side := tangent.cross(Vector3.UP).normalized()
	var up := side.cross(tangent).normalized()
	return Transform3D(Basis(tangent, up, side), (p0 + p1) * 0.5 - Vector3(0, 0.05, 0))

func _boundary():
	# Replace opaque air-wall void with continuous 360-degree mountain timber guardrails + solid collision perimeter
	var bay_mesh := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "mountain_fence_bay")
	var bay_tx: Array = []

	# North & South rails along Z = FENCE_MIN_Z (-112) & FENCE_MAX_Z (+26), spanning X in [-52 .. +52]
	var scx := float(game.Layout.stream_center_x(game.Layout.FENCE_MAX_Z))
	var scy := float(game.Layout.stream_water_y(game.Layout.FENCE_MAX_Z) + 0.36)
	for x_i in range(-50, 52, 4):
		var bx := float(x_i)
		var pn0 := Vector3(bx - 2.0, float(game.terrain_height(bx - 2.0, game.Layout.FENCE_MIN_Z)), game.Layout.FENCE_MIN_Z)
		var pn1 := Vector3(bx + 2.0, float(game.terrain_height(bx + 2.0, game.Layout.FENCE_MIN_Z)), game.Layout.FENCE_MIN_Z)
		bay_tx.append(_fence_bay_transform(pn0, pn1))

		var ys0 := scy if absf((bx - 2.0) - scx) < 2.3 else float(game.terrain_height(bx - 2.0, game.Layout.FENCE_MAX_Z))
		var ys1 := scy if absf((bx + 2.0) - scx) < 2.3 else float(game.terrain_height(bx + 2.0, game.Layout.FENCE_MAX_Z))
		bay_tx.append(_fence_bay_transform(Vector3(bx + 2.0, ys1, game.Layout.FENCE_MAX_Z), Vector3(bx - 2.0, ys0, game.Layout.FENCE_MAX_Z)))

	# West & East rails along X = FENCE_MIN_X (-52) & FENCE_MAX_X (+52), spanning full Z in [-112 .. +26]
	var z_centers := []
	for z_i in range(-110, 25, 4):
		z_centers.append(float(z_i))
	if z_centers[-1] < 24.0:
		z_centers.append(24.0)
	for bz in z_centers:
		var pw0 := Vector3(game.Layout.FENCE_MIN_X, float(game.terrain_height(game.Layout.FENCE_MIN_X, bz + 2.0)), bz + 2.0)
		var pw1 := Vector3(game.Layout.FENCE_MIN_X, float(game.terrain_height(game.Layout.FENCE_MIN_X, bz - 2.0)), bz - 2.0)
		bay_tx.append(_fence_bay_transform(pw0, pw1))

		var pe0 := Vector3(game.Layout.FENCE_MAX_X, float(game.terrain_height(game.Layout.FENCE_MAX_X, bz - 2.0)), bz - 2.0)
		var pe1 := Vector3(game.Layout.FENCE_MAX_X, float(game.terrain_height(game.Layout.FENCE_MAX_X, bz + 2.0)), bz + 2.0)
		bay_tx.append(_fence_bay_transform(pe0, pe1))

	_batch_direct(bay_mesh, bay_tx, not low_quality)

	# Solid tall perimeter colliders (player cannot climb over, bullets respect border, yet view above 1.28m rails stays wide open!)
	var walls := [
		[Vector3(game.Layout.FENCE_MIN_X, 6.0, -43.0), Vector3(0.45, 22.0, 140.0)],
		[Vector3(game.Layout.FENCE_MAX_X, 6.0, -43.0), Vector3(0.45, 22.0, 140.0)],
		[Vector3(0.0, 8.0, game.Layout.FENCE_MIN_Z), Vector3(106.0, 22.0, 0.45)],
		[Vector3(0.0, 3.0, game.Layout.FENCE_MAX_Z), Vector3(106.0, 18.0, 0.45)]
	]
	for w in walls:
		var shape := BoxShape3D.new()
		shape.size = w[1]
		game.Props.shape_body(self, shape, w[0]).name = "FencePerimeterWall"

	# Subtle low cliff accent boulders well down the outer slope so views stay 100% open above rails
	for rz in [-96.0, -64.0, -34.0, -6.0, 18.0]:
		rock(Vector3(-59.5, 0, rz), rng.randf_range(1.1, 1.5), int(absf(rz)) % 3)
		rock(Vector3(59.5, 0, rz), rng.randf_range(1.1, 1.5), (int(absf(rz)) + 1) % 3)
	signpost(Vector3(-3.2, 0, 23.2), "烟山观景木栏\n山下稻田 · 诚庄村落 ↓")
	signpost(Vector3(46.2, 0, -21.5), "东岭梯田观景台\n金色水田 · 溪流远山 →")
