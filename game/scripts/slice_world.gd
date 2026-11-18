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
var tree_trunks: Array[Vector3] = []
var tree_trunk_radii: Array[float] = []
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
	s.sky_top_color = Color("588496")
	s.sky_horizon_color = Color("c5d4c8")
	s.ground_bottom_color = Color("3c4f44")
	s.ground_horizon_color = Color("aec0b4")
	s.sun_angle_max = 30.0
	s.sun_curve = 0.13
	sky.sky_material = s
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.76
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.02
	e.tonemap_white = 1.42
	e.fog_enabled = true
	e.fog_density = 0.0028
	e.fog_light_color = Color("b6cabf")
	e.fog_sky_affect = 0.18
	env.environment = e
	add_child(env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47, -38, 0)
	sun.light_color = Color("faefd8")
	sun.light_energy = 0.94
	low_quality = "--low-quality" in OS.get_cmdline_user_args()
	sun.shadow_enabled = not low_quality
	sun.directional_shadow_max_distance = 42
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.05
	add_child(sun)

func set_low_quality(value: bool):
	low_quality = value
	for child in get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = not low_quality

func _ground_vis_y(x: float, z: float) -> float:
	var h := float(game.terrain_height(x, z))
	var sd := float(game.Layout.stream_distance(x, z))
	if sd < 2.22 and z >= game.Layout.STREAM_Z_MIN - 1.2:
		h -= 0.055 * (1.0 - smoothstep(1.48, 2.22, sd))
	if x > -46.2 and x < -37.0 and z > -70.1 and z < -57.6:
		var wx := 1.0 - smoothstep(3.6, 4.5, absf(x + 41.6))
		var wz := (1.0 - smoothstep(-58.3, -57.6, z)) * (1.0 - smoothstep(-69.2, -70.1, z))
		h -= 0.50 * wx * wz
	return h

func _ground():
	var verts = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	for z in range(-120, 36):
		for x in range(-60, 60):
			var p = [
				Vector3(x, _ground_vis_y(x, z), z),
				Vector3(x, _ground_vis_y(x, z + 1), z + 1),
				Vector3(x + 1, _ground_vis_y(x + 1, z), z),
				Vector3(x + 1, _ground_vis_y(x + 1, z + 1), z + 1)
			]
			for tri in [[0, 2, 1], [2, 3, 1]]:
				var normal = (p[tri[2]] - p[tri[0]]).cross(p[tri[1]] - p[tri[0]]).normalized()
				for i in tri:
					verts.append(p[i])
					normals.append(normal)
					uvs.append(Vector2(p[i].x, p[i].z) * 0.28)
					var r_t := clampf(game.Layout.road_distance(p[i].x, p[i].z) / 4.5, 0, 1)
					var s_t := clampf(game.Layout.stream_distance(p[i].x, p[i].z) / 3.6, 0, 1)
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
 float stream_bank=1.0-smoothstep(0.45,0.98,COLOR.g);
 float patch=0.5+0.5*sin(pos.x*0.24+sin(pos.z*0.19)*2.1);
 float micro_band=smoothstep(0.32,0.68,patch);
 vec3 greenery=mix(vec3(0.21,0.34,0.23),vec3(0.37,0.46,0.27),micro_band);
 vec3 bed=mix(tex*vec3(0.54,0.49,0.39),tex*greenery*1.44,edge);
 vec3 wet_stone=tex*vec3(0.30,0.36,0.32);
 ALBEDO=mix(bed,wet_stone,stream_bank*0.78);
 NORMAL_MAP=texture(soil_normal,UV).rgb; NORMAL_MAP_DEPTH=0.46; ROUGHNESS=mix(0.96,0.68,stream_bank); SPECULAR=0.03;
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("soil", load("res://assets/slice/ground_color.jpg"))
	mat.set_shader_parameter("soil_normal", load("res://assets/slice/ground_normal.jpg"))
	ground.material_override = mat
	add_child(ground)

	var shape = HeightMapShape3D.new()
	shape.map_width = 121
	shape.map_depth = 157
	var heights = PackedFloat32Array()
	for z in range(-120, 37):
		for x in range(-60, 61):
			heights.append(game.terrain_height(x, z))
	shape.map_data = heights
	game.Props.shape_body(self, shape, Vector3(0, 0, -42)).name = "GroundCollision"

var extracted_mesh_cache: Dictionary = {}
var qinglu_foliage_shader: Shader = null
var qinglu_foliage_cache: Dictionary = {}

func _get_qinglu_foliage_material(tex: Texture2D, mat_key: String, has_vcol: bool) -> ShaderMaterial:
	var cache_id := mat_key + "::" + (str(tex.get_rid().get_id()) if tex != null else "notex") + ("::vc" if has_vcol else "::novc")
	if qinglu_foliage_cache.has(cache_id):
		return qinglu_foliage_cache[cache_id]
	if qinglu_foliage_shader == null:
		qinglu_foliage_shader = Shader.new()
		qinglu_foliage_shader.code = """shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut = 0.40;
uniform float sway_amp = 0.045;
uniform float use_baked_ao = 1.0;
uniform float warm_autumn = 0.0;

varying vec3 v_world_nrm;
varying vec3 v_vcol;
varying float v_instance_var;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_vcol = mix(vec3(0.78, clamp(VERTEX.y / 5.5, 0.0, 1.0), 0.5), COLOR.rgb, use_baked_ao);
	vec3 origin_w = MODEL_MATRIX[3].xyz;
	v_instance_var = fract(sin(dot(origin_w.xz, vec2(12.9898, 78.233))) * 43758.5453);

	// Gentle mountain breeze sway weighted toward outer/upper bough tips
	float flex = clamp(v_vcol.g * 0.72 + (1.0 - UV.y) * 0.28, 0.0, 1.0);
	float phase = TIME * 1.55 + origin_w.x * 0.37 + origin_w.z * 0.29 + VERTEX.y * 0.35;
	VERTEX.x += sin(phase) * sway_amp * flex;
	VERTEX.z += cos(phase * 0.85) * sway_amp * 0.65 * flex;
}

void fragment() {
	vec4 tex = texture(leaf_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;

	// Lock view-space normal to the smooth outward canopy normal (never flip on backfaces -> zero harsh X-card seams!)
	NORMAL = normalize((VIEW_MATRIX * vec4(v_world_nrm, 0.0)).xyz);

	// 3D Volumetric Qinglü core-to-crown gradient: Deep Qingdai Ink-Jade interior -> Sunlit Tea-Gold exterior!
	float core_ao = clamp(v_vcol.r, 0.20, 1.0);
	float crown_h = clamp(v_vcol.g, 0.0, 1.0);
	float vol_t = smoothstep(0.22, 0.94, core_ao * 0.74 + crown_h * 0.26);

	vec3 shadow_tint = mix(vec3(0.42, 0.60, 0.62), vec3(0.56, 0.50, 0.52), warm_autumn);
	vec3 crown_tint = mix(vec3(1.12, 1.10, 0.94), vec3(1.16, 1.04, 0.90), warm_autumn);
	// Subtle per-tree & per-bouquet organic shift so neighboring trees never merge into one flat mass
	vec3 var_tint = mix(vec3(0.93, 1.03, 1.02), vec3(1.06, 0.99, 0.92), clamp(v_instance_var * 0.65 + v_vcol.b * 0.35, 0.0, 1.0));

	ALBEDO = tex.rgb * mix(shadow_tint, crown_tint, vol_t) * var_tint;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float half_nl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = clamp(half_nl * (0.46 + 0.68 * v_vcol.r), 0.0, 1.0);
	// Soft 2-step Qinglü painterly cel-band (clean sunlit crowns vs cool mineral-jade shade, zero plastic shine!)
	float cel = mix(smoothstep(0.30, 0.56, lit) * 0.56 + smoothstep(0.58, 0.86, lit) * 0.44, lit, 0.32);
	vec3 cool_shade = vec3(0.14, 0.24, 0.26);
	vec3 warm_sun = (LIGHT_COLOR / 3.14159) * vec3(1.02, 0.98, 0.84);
	// Translucent spring-leaf rim glow when looking toward the sun
	float back_rim = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0) * smoothstep(0.52, 1.0, v_vcol.r) * 0.26;
	DIFFUSE_LIGHT += (mix(cool_shade, warm_sun, cel) + vec3(0.24, 0.28, 0.14) * back_rim) * ATTENUATION;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = qinglu_foliage_shader
	if tex != null:
		sm.set_shader_parameter("leaf_tex", tex)
	var is_willow := "Willow" in mat_key
	var is_maple := "Maple" in mat_key
	var is_azalea := "Azalea" in mat_key
	sm.set_shader_parameter("alpha_cut", 0.36 if is_willow else 0.40)
	sm.set_shader_parameter("sway_amp", 0.075 if is_willow else (0.022 if is_azalea else 0.045))
	sm.set_shader_parameter("use_baked_ao", 1.0 if has_vcol else 0.0)
	sm.set_shader_parameter("warm_autumn", 0.65 if is_maple else 0.0)
	qinglu_foliage_cache[cache_id] = sm
	return sm

func _polish_mesh_materials(src_mesh: Mesh) -> Mesh:
	if src_mesh == null:
		return null
	var mesh: Mesh = src_mesh.duplicate()
	for s in mesh.get_surface_count():
		var fmt: int = int(mesh.surface_get_format(s))
		var has_vcol: bool = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0
		var mat: Material = mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			var smat := mat as StandardMaterial3D
			var mname := String(smat.resource_name)
			if smat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and smat.albedo_texture != null:
				mesh.surface_set_material(s, _get_qinglu_foliage_material(smat.albedo_texture, mname, has_vcol))
				continue
		var bmat: BaseMaterial3D = null
		if mat is BaseMaterial3D:
			bmat = mat.duplicate() as BaseMaterial3D
		elif has_vcol:
			bmat = StandardMaterial3D.new()
			bmat.roughness = 0.88
		if bmat != null:
			if has_vcol:
				bmat.vertex_color_use_as_albedo = true
			if bmat.metallic < 0.35:
				bmat.metallic = 0.0
				bmat.metallic_specular = 0.05
				bmat.roughness = maxf(bmat.roughness, 0.78)
			if bmat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				bmat.alpha_scissor_threshold = 0.40
				bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
				bmat.roughness = 0.92
			mesh.surface_set_material(s, bmat)
	return mesh

func _polish_node_materials(node: Node3D):
	if node == null:
		return
	var targets: Array = []
	if node is MeshInstance3D:
		targets.append(node)
	targets.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for t in targets:
		var mi := t as MeshInstance3D
		if mi and mi.mesh:
			mi.mesh = _polish_mesh_materials(mi.mesh)

func _extract_mesh(glb_path: String, sub_name: String = "") -> Mesh:
	var cache_key := glb_path + "::" + sub_name
	if extracted_mesh_cache.has(cache_key):
		return extracted_mesh_cache[cache_key]
	if not ResourceLoader.exists(glb_path):
		return null
	if not game.scene_cache.has(glb_path):
		game.scene_cache[glb_path] = load(glb_path)
	var inst: Node3D = game.scene_cache[glb_path].instantiate()
	var target: Node = inst.find_child(sub_name, true, false) if sub_name != "" else null
	if target != null and not (target is MeshInstance3D):
		var sub_meshes := target.find_children("*", "MeshInstance3D", true, false)
		target = sub_meshes[0] if not sub_meshes.is_empty() else null
	if not (target is MeshInstance3D):
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		target = meshes[0] if not meshes.is_empty() else null
	var extracted: Mesh = _polish_mesh_materials(target.mesh) if (target is MeshInstance3D) else null
	inst.queue_free()
	extracted_mesh_cache[cache_key] = extracted
	return extracted

func _batch(mesh: Mesh, mat: Material, transforms: Array, shadows: bool):
	if mesh == null or transforms.is_empty():
		return
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

func _batch_direct(mesh: Mesh, transforms: Array, shadows: bool = false, batch_name: String = "", vis_end: float = 0.0):
	if mesh == null or transforms.is_empty():
		return
	var chunk_size := 36.0
	var use_chunks: bool = transforms.size() > 24 and batch_name != "BluestoneFlagstones"
	if not use_chunks:
		var node := MultiMeshInstance3D.new()
		if batch_name != "":
			node.name = batch_name
		var avg := Vector3.ZERO
		for xf in transforms:
			avg += (xf as Transform3D).origin
		avg /= float(transforms.size())
		node.position = avg
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			var xf_i := transforms[i] as Transform3D
			mm.set_instance_transform(i, Transform3D(xf_i.basis, xf_i.origin - avg))
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			node.visibility_range_end = vis_end + 14.0
		add_child(node)
		return

	# Spatial sector chunking (36m x 36m) unlocks real GPU frustum culling + accurate per-sector visibility_range_end!
	var buckets: Dictionary = {}
	for xf in transforms:
		var t := xf as Transform3D
		var key := Vector2i(int(floorf(t.origin.x / chunk_size)), int(floorf(t.origin.z / chunk_size)))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(t)

	var chunk_idx := 0
	for key in buckets:
		var list: Array = buckets[key]
		var center := Vector3.ZERO
		for t in list:
			center += (t as Transform3D).origin
		center /= float(list.size())

		var cnode := MultiMeshInstance3D.new()
		if batch_name != "":
			cnode.name = batch_name if chunk_idx == 0 else ("%s_Chunk%d" % [batch_name, chunk_idx])
		cnode.position = center
		var cmm := MultiMesh.new()
		cmm.transform_format = MultiMesh.TRANSFORM_3D
		cmm.mesh = mesh
		cmm.instance_count = list.size()
		for i in list.size():
			var lt := list[i] as Transform3D
			cmm.set_instance_transform(i, Transform3D(lt.basis, lt.origin - center))
		cnode.multimesh = cmm
		cnode.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			cnode.visibility_range_end = vis_end + 18.0
		add_child(cnode)
		chunk_idx += 1

func _is_vista_corridor(x: float, z: float) -> bool:
	# Keep scenic sightlines unobstructed at South Camp Fence Overlook, Creek Outflow, Wangdao Pavilion & East Terrace
	if x > -10.5 and x < 5.0 and z > 18.0 and z < 35.0:
		return true
	if x > 14.2 and x < 21.8 and z > 19.0 and z < 42.0:
		return true
	if x > 27.0 and x < 42.5 and z > 17.5 and z < 36.0:
		return true
	if x > 42.5 and x < 60.0 and z > -27.5 and z < -15.5:
		return true
	return false

func _surface_height_any(x: float, z: float) -> float:
	if x >= -60.0 and x <= 60.0 and z >= -120.0 and z <= 36.0:
		return float(game.terrain_height(x, z))
	return _outer_valley_y(x, z)

func _min_surface_height_any(x: float, z: float, radius: float) -> float:
	var low := _surface_height_any(x, z)
	for d in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius), Vector2(radius * 0.7, radius * 0.7), Vector2(-radius * 0.7, -radius * 0.7)]:
		low = minf(low, _surface_height_any(x + d.x, z + d.y))
	return low

func _vegetation():
	for i in 6:
		var path = "res://assets/slice/rock_%d.glb" % i
		if ResourceLoader.exists(path):
			rock_paths.append(path)

	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var culm_mesh := _extract_mesh(v061_path, "bamboo_culm_single")
	var clump_mesh := _extract_mesh(v061_path, "bamboo_clump")
	var culm_tx: Array = []
	var clump_tx: Array = []

	# Authentic segmented Moso bamboo groves & fence-side bamboo pockets
	for i in 155:
		var x := rng.randf_range(-50.5, 50.5)
		var z := rng.randf_range(-109.0, 21.5)
		if game.Layout.clear_for_route(x, z, 0.65) or _is_vista_corridor(x, z):
			continue
		if i % 5 == 0 and not game.Layout.clear_for_route(x, z, 2.2):
			var cy := _surface_height_any(x, z) - 0.04
			var csc := rng.randf_range(0.84, 1.16)
			clump_tx.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * csc), Vector3(x, cy, z)))
			if game.Layout.road_distance(x, z) < 18.0:
				var cshape := CylinderShape3D.new()
				cshape.radius = 0.58 * csc
				cshape.height = 6.2 * csc
				var cbody = game.Props.shape_body(self, cshape, Vector3(x, cy + 3.1 * csc, z))
				cbody.add_to_group("solid_props")
		else:
			for j in 2:
				var bx := x + float(j) * 0.75 + rng.randf_range(-0.22, 0.22)
				var bz := z + float(j) * 0.52 + rng.randf_range(-0.22, 0.22)
				if game.Layout.clear_for_route(bx, bz, 0.45) or _is_vista_corridor(bx, bz):
					continue
				var by := _surface_height_any(bx, bz) - 0.03
				var bsc := rng.randf_range(0.82, 1.24)
				var basis := Basis(Vector3.UP, rng.randf_range(0, TAU))
				basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.045, 0.045)).scaled(Vector3(bsc * 0.96, bsc, bsc * 0.96))
				culm_tx.append(Transform3D(basis, Vector3(bx, by, bz)))
				if game.Layout.road_distance(bx, bz) < 15.0:
					var shape := CylinderShape3D.new()
					shape.radius = 0.13
					shape.height = 6.8 * bsc
					var body = game.Props.shape_body(self, shape, Vector3(bx, by + 3.4 * bsc, bz))
					body.add_to_group("solid_props")

	# Disable directional shadow-map rasterization on alpha-scissored bamboo foliage (~290k tris saved per shadow split!)
	_batch_direct(culm_mesh, culm_tx, false, "MosoBambooCulms", 112.0)
	_batch_direct(clump_mesh, clump_tx, false, "MosoBambooClumps", 105.0)
	_trees()

	for i in 34:
		var x := rng.randf_range(-48.5, 48.5)
		var z := rng.randf_range(-107.0, 21.5)
		if not game.Layout.clear_for_route(x, z, 1.6) and not _is_vista_corridor(x, z):
			rock(Vector3(x, 0, z), rng.randf_range(1.0, 3.3), i)
	for info in [[Vector3(-22, 0, -18), 2.1], [Vector3(-46.5, 0, -21.0), 2.8], [Vector3(5, 0, -34), 2.9], [Vector3(-9.5, 0, -71), 3.4], [Vector3(24, 0, -91), 4.2]]:
		rock(info[0], info[1], int(absf(info[0].z)))
	_backdrop()

func _trees():
	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var camphor_mesh := _extract_mesh(v061_path, "tree_camphor")
	var willow_mesh := _extract_mesh(v061_path, "tree_willow")
	var maple_mesh := _extract_mesh(v061_path, "tree_maple_tallow")

	var camphor_tx: Array = []
	var willow_tx: Array = []
	var maple_tx: Array = []

	# 1) Graceful Weeping Willows ("垂柳") lining the mountain creek & framing the South fence creek outflow
	var creek_willow_specs := [
		[-99.0, -4.1], [-85.0, 4.3], [-70.5, -4.0], [-56.0, 4.2],
		[-38.0, -4.2], [-30.0, 4.5], [-17.5, -4.3], [-8.5, 4.2],
		[1.5, -4.0], [13.2, 4.3], [19.8, -4.3], [24.2, 4.8],
		[29.5, -5.0], [33.5, 5.2]
	]
	for idx in creek_willow_specs.size():
		var wz: float = creek_willow_specs[idx][0]
		var woff: float = creek_willow_specs[idx][1]
		var wx := _outer_stream_x(wz) + woff
		if (game.Layout.road_distance(wx, wz) < 4.2 or _is_near_bridge(wz, 3.8)) and wz <= 25.0:
			continue
		var wy := _surface_height_any(wx, wz) - 0.08
		var wsc := 0.96 + float(idx % 4) * 0.10
		var wyaw := float(idx) * 1.85
		willow_tx.append(Transform3D(Basis(Vector3.UP, wyaw).scaled(Vector3.ONE * wsc), Vector3(wx, wy, wz)))
		if wz >= game.Layout.FENCE_MIN_Z and wz <= game.Layout.FENCE_MAX_Z and absf(wx) <= 51.5:
			var tshape := CylinderShape3D.new()
			tshape.radius = 0.28 * wsc
			tshape.height = 4.2 * wsc
			game.Props.shape_body(self, tshape, Vector3(wx, wy + 2.1 * wsc, wz))
			tree_trunks.append(Vector3(wx, wy + 0.08, wz))
			tree_trunk_radii.append(0.28 * wsc)

	# 2) Key landmark & trailside Southern Broadleaf Trees (Camphor "香樟" & Maple/Tallow "枫香/乌桕")
	var curated_trees := [
		Vector3(-17, 0, -4), Vector3(24, 0, -8), Vector3(-29, 0, -19), Vector3(24, 0, -18),
		Vector3(-37, 0, -30), Vector3(24, 0, -42), Vector3(-32, 0, -53), Vector3(28, 0, -63),
		Vector3(-25, 0, -76), Vector3(33, 0, -91), Vector3(-7, 0, -107), Vector3(32, 0, -3),
		Vector3(-44, 0, 18), Vector3(-31, 0, 21), Vector3(45, 0, 12), Vector3(46, 0, -6),
		Vector3(45, 0, -38), Vector3(44, 0, -58), Vector3(45, 0, -79), Vector3(42, 0, -102),
		Vector3(-45, 0, 4), Vector3(-46, 0, -16), Vector3(-46, 0, -44), Vector3(-45, 0, -68),
		Vector3(-44, 0, -88), Vector3(-42, 0, -106), Vector3(-19, 0, -108), Vector3(11, 0, -108),
		Vector3(-21.5, 0, -2.5), Vector3(-34.8, 0, -18.5), Vector3(35.0, 0, -41.0), Vector3(36.8, 0, -62.5),
		Vector3(-32.5, 0, -76.5), Vector3(38.5, 0, -14.0), Vector3(-38.0, 0, -60.0), Vector3(39.0, 0, -96.0),
		Vector3(-42.0, 0, -2.0), Vector3(-48.0, 0, -32.0), Vector3(-47.0, 0, -56.0), Vector3(-47.5, 0, -96.0),
		Vector3(-17.5, 0, -99.5), Vector3(-20.5, 0, -72.0), Vector3(47.5, 0, -48.5), Vector3(48.0, 0, -68.0),
		Vector3(47.5, 0, -90.0), Vector3(38.0, 0, -4.0), Vector3(-26.0, 0, 14.0), Vector3(-39.5, 0, 12.0), Vector3(39.5, 0, 4.0),
		Vector3(34.5, 0, -49.0), Vector3(35.5, 0, -56.0),
		Vector3(-51.2, 0, -42.0), Vector3(-51.2, 0, -54.0), Vector3(-51.2, 0, -66.0),
		Vector3(-31.6, 0, -58.5), Vector3(-31.2, 0, -49.5), Vector3(-43.5, 0, -27.2)
	]
	# Also scatter natural fence-side & outer-collar woodland trees so hills have zero empty dead zones
	for k in 34:
		var sx := rng.randf_range(-56.5, 56.5)
		var sz := rng.randf_range(-116.0, 24.5)
		if absf(sx) < 33.0 and sz > -98.0 and sz < 14.0:
			continue
		curated_trees.append(Vector3(sx, 0.0, sz))

	for idx in curated_trees.size():
		var raw: Vector3 = curated_trees[idx]
		if _is_vista_corridor(raw.x, raw.z):
			continue
		if raw.x >= -52.0 and raw.x <= 52.0 and raw.z >= -112.0 and raw.z <= 26.0:
			if game.Layout.clear_for_route(raw.x, raw.z, 1.8):
				continue
		elif game.Layout.stream_distance(raw.x, raw.z) < 4.2:
			continue
		var ty := _surface_height_any(raw.x, raw.z) - 0.10
		var tsc := rng.randf_range(0.90, 1.28)
		var tyaw := float(idx) * 2.07 + rng.randf_range(-0.25, 0.25)
		var xform := Transform3D(Basis(Vector3.UP, tyaw).scaled(Vector3.ONE * tsc), Vector3(raw.x, ty, raw.z))
		if idx % 5 == 1 or idx % 5 == 3:
			maple_tx.append(xform)
		else:
			camphor_tx.append(xform)
		if raw.x >= -51.5 and raw.x <= 51.5 and raw.z >= -111.5 and raw.z <= 25.5:
			var shape := CylinderShape3D.new()
			shape.radius = 0.30 * tsc
			shape.height = 4.6 * tsc
			game.Props.shape_body(self, shape, Vector3(raw.x, ty + 2.3 * tsc, raw.z))
			tree_trunks.append(Vector3(raw.x, ty + 0.10, raw.z))
			tree_trunk_radii.append(0.30 * tsc)
	var shrine_p: Vector3 = game.Layout.on_ground(game.Layout.CAMPHOR_SHRINE)
	tree_trunks.append(shrine_p)
	tree_trunk_radii.append(0.58)

	# Disable alpha-scissored leaf shadow thrashing and ground trees with a single 1-draw-call soft canopy shade disc MultiMesh!
	_batch_direct(camphor_mesh, camphor_tx, false, "MountainCamphorTrees", 145.0)
	_batch_direct(willow_mesh, willow_tx, false, "MountainWillowTrees", 145.0)
	_batch_direct(maple_mesh, maple_tx, false, "MountainMapleTrees", 145.0)
	_build_canopy_shade_discs()

func _build_canopy_shade_discs():
	if tree_trunks.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(4.8, 4.8)
	quad.orientation = PlaneMesh.FACE_Y
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled;
void fragment(){
 vec2 d = UV * 2.0 - 1.0;
 float r = length(d);
 float soft = 1.0 - smoothstep(0.22, 0.96, r);
 ALBEDO = vec3(0.05, 0.08, 0.05);
 ALPHA = soft * 0.30;
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	var shade_tx: Array = []
	for i in tree_trunks.size():
		var tp: Vector3 = tree_trunks[i]
		var tr := float(tree_trunk_radii[i]) if i < tree_trunk_radii.size() else 0.30
		var sc := clampf(tr * 3.4, 0.85, 1.55)
		var gy := _surface_height_any(tp.x, tp.z) + 0.045
		var hx0 := _surface_height_any(tp.x - 0.8, tp.z)
		var hx1 := _surface_height_any(tp.x + 0.8, tp.z)
		var hz0 := _surface_height_any(tp.x, tp.z - 0.8)
		var hz1 := _surface_height_any(tp.x, tp.z + 0.8)
		var up_n := Vector3(hx0 - hx1, 1.6, hz0 - hz1).normalized()
		var right_v := Vector3.RIGHT.slide(up_n).normalized()
		var fwd_v := right_v.cross(up_n).normalized()
		shade_tx.append(Transform3D(Basis(right_v * sc, up_n, fwd_v * sc), Vector3(tp.x + 0.35, gy, tp.z + 0.35)))
	_batch(quad, smat, shade_tx, false)

func _hill_height(x: float, z: float) -> float:
	return 5.0 + 15.0 * exp(-pow((x + 65.0) / 43.0, 2.0) - pow((z + 175.0) / 45.0, 2.0)) + 22.0 * exp(-pow((x - 45.0) / 58.0, 2.0) - pow((z + 205.0) / 60.0, 2.0)) + 5.0 * sin(x * 0.025 + z * 0.018)

func _outer_stream_x(z: float) -> float:
	if z <= 36.0:
		return float(game.Layout.stream_center_x(z))
	var dz := z - 36.0
	return 19.6 + (1.0 - exp(-dz * 0.06)) * sin(dz * 0.052) * 8.5

func _outer_stream_width_scale(z: float) -> float:
	if z <= 36.0:
		return 1.0
	return 1.0 + 0.65 * smoothstep(36.0, 145.0, z)

func _outer_foothill_weight(x: float, z: float) -> float:
	var center_dist := Vector2(x, z + 44.0).length()
	var south_plain := exp(-pow((x - 16.0) / 68.0, 2.0)) * smoothstep(70.0, 195.0, z)
	return smoothstep(162.0, 265.0, center_dist) * (1.0 - 0.65 * south_plain)

func _outer_valley_y(x: float, z: float) -> float:
	var ix := clampf(x, -60.0, 60.0)
	var iz := clampf(z, -120.0, 36.0)
	var dx := maxf(0.0, maxf(-60.0 - x, x - 60.0))
	var dz := maxf(0.0, maxf(-120.0 - z, z - 36.0))
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.001:
		return _ground_vis_y(ix, iz)
	var edge_land := float(game.Layout.land_edge_height(ix, iz))
	var north_w := smoothstep(-114.0, -146.0, z) * (1.0 - smoothstep(56.0, 98.0, absf(x)))
	var north_h := _hill_height(x, z)
	# Broad terraced lowland rice paddies surrounding East, West & South hillsides
	var raw_terrace := -11.4 + 1.6 * sin(x * 0.024 + z * 0.016) + 0.9 * cos(z * 0.028)
	var quantized := floorf((raw_terrace + 13.0) / 2.2) * 2.2 - 13.0
	var valley_floor := lerpf(raw_terrace, quantized, 0.56)
	var down_t := smoothstep(0.0, 30.0, d)
	var rural_y := lerpf(edge_land, valley_floor, down_t)
	rural_y = lerpf(rural_y, north_h, north_w * smoothstep(6.0, 38.0, d))
	var center_dist := Vector2(x, z + 44.0).length()
	var foothill_w := _outer_foothill_weight(x, z)
	var foothill_h := 6.0 + 18.0 * smoothstep(170.0, 280.0, center_dist) + 8.5 * sin(x * 0.027 - z * 0.021) + 5.5 * cos(x * 0.016 + z * 0.031)
	var land_y := lerpf(rural_y, foothill_h, foothill_w)
	# Continuous recessed riverbed & bank lips extending seamlessly South from z = 36.0 into the rural rice valley
	if z >= 36.0 and z <= 172.0:
		var sx := _outer_stream_x(z)
		var w_sc := _outer_stream_width_scale(z)
		var local_off := (x - sx) / w_sc
		if absf(local_off) < 5.2:
			var equiv_x := 19.6 + local_off
			var delta_36 := _ground_vis_y(equiv_x, 36.0) - float(game.Layout.land_edge_height(equiv_x, 36.0))
			var chan_fade := 1.0 - smoothstep(145.0, 172.0, z)
			land_y += delta_36 * chan_fade
	return land_y

func _stream_water_y_any(z: float) -> float:
	if z <= 36.0:
		return float(game.Layout.stream_water_y(z))
	var sx := _outer_stream_x(z)
	return _outer_valley_y(sx, z) + lerpf(0.575, 0.18, smoothstep(36.0, 155.0, z))

func _outer_valley_normal(x: float, z: float) -> Vector3:
	var dx := maxf(0.0, maxf(-60.0 - x, x - 60.0))
	var dz := maxf(0.0, maxf(-120.0 - z, z - 36.0))
	var eps := 1.0 if (dx < 24.0 and dz < 48.0) else 4.0
	return Vector3(
		_outer_valley_y(x - eps, z) - _outer_valley_y(x + eps, z),
		2.0 * eps,
		_outer_valley_y(x, z - eps) - _outer_valley_y(x, z + eps)
	).normalized()

func _valley_raw_vert(x: float, z: float) -> Array:
	var y := _outer_valley_y(x, z)
	var n := _outer_valley_normal(x, z)
	var dx := maxf(0.0, maxf(-60.0 - x, x - 60.0))
	var dz := maxf(0.0, maxf(-120.0 - z, z - 36.0))
	var d := sqrt(dx * dx + dz * dz)
	var fh := _outer_foothill_weight(x, z)
	var paddy_w := smoothstep(22.0, 42.0, d) * (1.0 - smoothstep(-6.5, -2.0, y))
	var slope_flat := smoothstep(0.86, 0.96, n.y)
	return [Vector3(x, y, z), n, Vector2(x, z) * 0.015, Color(paddy_w * slope_flat, clampf(d / 220.0, 0.0, 1.0), fh)]

func _valley_stitched_vert(ix: int, iz: int, outer_box: Array, coarse_step: int) -> Array:
	# Snap fine-ring outer-perimeter vertices linearly onto coarse_step endpoints so zero T-junction cracks can ever form
	if coarse_step > 1:
		var ox0: int = outer_box[0]
		var ox1: int = outer_box[1]
		var oz0: int = outer_box[2]
		var oz1: int = outer_box[3]
		if (ix == ox0 or ix == ox1) and iz >= oz0 and iz <= oz1:
			var rem_z := posmod(iz - oz0, coarse_step)
			if rem_z != 0:
				var z_a := float(iz - rem_z)
				var z_b := float(iz - rem_z + coarse_step)
				var tz := float(rem_z) / float(coarse_step)
				var va := _valley_raw_vert(float(ix), z_a)
				var vb := _valley_raw_vert(float(ix), z_b)
				return [(va[0] as Vector3).lerp(vb[0] as Vector3, tz), ((va[1] as Vector3).lerp(vb[1] as Vector3, tz)).normalized(), (va[2] as Vector2).lerp(vb[2] as Vector2, tz), (va[3] as Color).lerp(vb[3] as Color, tz)]
		if (iz == oz0 or iz == oz1) and ix >= ox0 and ix <= ox1:
			var rem_x := posmod(ix - ox0, coarse_step)
			if rem_x != 0:
				var x_a := float(ix - rem_x)
				var x_b := float(ix - rem_x + coarse_step)
				var tx := float(rem_x) / float(coarse_step)
				var va := _valley_raw_vert(x_a, float(iz))
				var vb := _valley_raw_vert(x_b, float(iz))
				return [(va[0] as Vector3).lerp(vb[0] as Vector3, tx), ((va[1] as Vector3).lerp(vb[1] as Vector3, tx)).normalized(), (va[2] as Vector2).lerp(vb[2] as Vector2, tx), (va[3] as Color).lerp(vb[3] as Color, tx)]
	return _valley_raw_vert(float(ix), float(iz))

func _append_valley_ring(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, inner_box: Array, outer_box: Array, step: int, next_step: int):
	var ix0: int = inner_box[0]
	var ix1: int = inner_box[1]
	var iz0: int = inner_box[2]
	var iz1: int = inner_box[3]
	for z in range(int(outer_box[2]), int(outer_box[3]), step):
		for x in range(int(outer_box[0]), int(outer_box[1]), step):
			if x >= ix0 and x < ix1 and z >= iz0 and z < iz1:
				continue
			var v0 := _valley_stitched_vert(x, z, outer_box, next_step)
			var v1 := _valley_stitched_vert(x, z + step, outer_box, next_step)
			var v2 := _valley_stitched_vert(x + step, z, outer_box, next_step)
			var v3 := _valley_stitched_vert(x + step, z + step, outer_box, next_step)
			var cell := [v0, v1, v2, v3]
			for k in [0, 2, 1, 2, 3, 1]:
				var vd: Array = cell[k]
				vertices.append(vd[0])
				normals.append(vd[1])
				uvs.append(vd[2])
				colors.append(vd[3])

func _backdrop():
	# 1) Watertight 3-ring terraced rural rice-paddy valley seamlessly stitched to ContinuousGround [-60..60] x [-120..36]
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	var box0 := [-60, 60, -120, 36]
	var box1 := [-64, 64, -124, 44]
	var box2 := [-96, 96, -152, 88]
	var box3 := [-288, 288, -336, 248]
	_append_valley_ring(vertices, normals, uvs, colors, box0, box1, 1, 2)
	_append_valley_ring(vertices, normals, uvs, colors, box1, box2, 2, 8)
	_append_valley_ring(vertices, normals, uvs, colors, box2, box3, 8, 1)

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
 vec3 slope_col = mix(near_grass, far_hill_col, smoothstep(10.0, 56.0, edge_d));

 vec3 p_tex = texture(paddy_tex, UV).rgb;
 float macro_dapple = 0.88 + 0.14 * sin(wpos.x * 0.022 + wpos.z * 0.018);
 vec3 paddy_col = p_tex * macro_dapple * 0.62;

 float paddy_t = clamp(COLOR.r, 0.0, 1.0) * (1.0 - foothill_f * 0.96);
 ALBEDO = mix(slope_col, paddy_col, paddy_t);
 NORMAL_MAP = texture(soil_normal, soil_uv).rgb;
 NORMAL_MAP_DEPTH = mix(0.50, 0.12, smoothstep(10.0, 75.0, edge_d));
 ROUGHNESS = mix(0.95, 0.90, paddy_t);
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

	# 2) Rural Jiangnan cottages sheltered by authentic Weeping Willows, Camphors, Southern Maples & Bamboo Groves (zero Christmas pines!)
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
		_batch_direct(house_mesh, house_tx, false, "VillageFarmhouses", 220.0)

	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var v_willow := _extract_mesh(v061_path, "tree_willow")
	var v_camphor := _extract_mesh(v061_path, "tree_camphor")
	var v_maple := _extract_mesh(v061_path, "tree_maple_tallow")
	var v_bamboo := _extract_mesh(v061_path, "bamboo_clump")

	var v_willow_tx: Array = []
	var v_camphor_tx: Array = []
	var v_maple_tx: Array = []
	var v_bamboo_tx: Array = []

	# Weeping willows ("垂柳") lining the valley irrigation river from the mountain foot right through the village paddies
	for r_idx in 18:
		var rz := 40.0 + float(r_idx) * 6.8
		var r_side := -1.0 if r_idx % 2 == 0 else 1.0
		var rx := _outer_stream_x(rz) + r_side * (4.8 + float(r_idx % 3) * 1.2)
		var ry := _outer_valley_y(rx, rz) - 0.12
		var rsc := 1.08 + float(r_idx % 4) * 0.12
		v_willow_tx.append(Transform3D(Basis(Vector3.UP, float(r_idx) * 1.63).scaled(Vector3.ONE * rsc), Vector3(rx, ry, rz)))

	# Authentic Jiangnan village groves beside white-wall black-tile cottages: front-yard willows & camphors + backyard bamboo
	for j in village_spots.size():
		var hp: Vector3 = village_spots[j]
		for t_i in 3:
			var ang := float(j * 3 + t_i) * 2.09 + 0.35
			var rad := 6.6 + float(t_i) * 3.8
			var tx_p := hp.x + cos(ang) * rad
			var tz_p := hp.z + sin(ang) * rad
			if absf(tx_p - _outer_stream_x(tz_p)) < 3.8 and tz_p > 35.0:
				tx_p += 5.2
			var ty_p := _outer_valley_y(tx_p, tz_p) - 0.12
			var ts := 1.02 + float((j + t_i) % 4) * 0.12
			var xform := Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * ts), Vector3(tx_p, ty_p, tz_p))
			if t_i == 0:
				v_willow_tx.append(xform)
			elif t_i == 1:
				if j % 3 == 0:
					v_maple_tx.append(xform)
				else:
					v_camphor_tx.append(xform)
			else:
				v_bamboo_tx.append(xform)

	# Outer foothill broadleaf stands (lightweight silhouettes at 140m+ horizon)
	for k in 28:
		var angle := float(k) * 0.89
		var rad := 142.0 + float(k % 6) * 14.0
		var vx := sin(angle) * rad
		var vz := -44.0 + cos(angle) * (rad * 1.12)
		if vz < -118.0 and absf(vx) < 70.0:
			continue
		var vy := _outer_valley_y(vx, vz) - 0.16
		var ts := 1.18 + float(k % 4) * 0.16
		var xform := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * ts), Vector3(vx, vy, vz))
		if k % 3 == 0:
			v_maple_tx.append(xform)
		else:
			v_camphor_tx.append(xform)

	_batch_direct(v_willow, v_willow_tx, false, "VillageWillows", 215.0)
	_batch_direct(v_camphor, v_camphor_tx, false, "VillageCamphors", 215.0)
	_batch_direct(v_maple, v_maple_tx, false, "VillageMaples", 215.0)
	_batch_direct(v_bamboo, v_bamboo_tx, false, "VillageBamboo", 185.0)

	# 3) 360-degree distant misty mountain range panorama cylinder harmonizing with sun azimuth & valley mist
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

func rock(at: Vector3, height: float, index: int):
	var path = "res://assets/nature/rock_largeA.glb" if rock_paths.is_empty() else rock_paths[index % rock_paths.size()]
	var grounded_y := _min_surface_height_any(at.x, at.z, height * 0.72) - (0.38 + height * 0.09)
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
	label.visibility_range_end = 34.0

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
	l.visibility_range_end = 38.0
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
	# v0.6.2 Lost Bamboo-Stone Labyrinth ("迷踪竹石阵") & Yanxia Ancient Cavern ("烟霞古洞")
	_build_bamboo_maze_and_yanxia_cave()
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
		[Vector3(-12, 0, -17), "林间古道营地 ↑\n西岭山坡营地 ←"],
		[Vector3(-20, 0, -28), "← 诗碑亭 · 迷踪竹石阵\n林间营地 →"],
		[Vector3(-32.8, 0, -33.2), "↙ 迷踪竹石阵 · 烟霞古洞\n摩崖石刻 · 先民岩画 · 寒潭"],
		[Vector3(22.4, 0, -21.5), "东坡茶岭营地 ↗\n东上望稻亭 ↘"],
		[Vector3(-14, 0, -53), "西北高地营 ↖\n山道拦截营 ↑"],
		[Vector3(14, 0, -72), "B · 撤离信标\n260分·2营·统领"]
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
	var crate_yanxia = game._make_crate("烟霞古洞秘藏石匣", 3, Vector3(-39.05, 6.526, -65.45))
	crate_yanxia.set_meta("secret_key", "yanxia_cave")
	for crate in game.crate_nodes:
		TacticalProps.build_tiered_vault_crate(game, crate, int(crate.get_meta("tier")))
	crate_yanxia.scale = Vector3.ONE * 0.78
	for lbl_c in crate_yanxia.find_children("*", "Label3D", true, false):
		var cl := lbl_c as Label3D
		if cl:
			cl.pixel_size = 0.0023
			cl.position.y = 1.24
			cl.visibility_range_end = 7.4

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
		{"at": game.Layout.SE_BAMBOO_CACHE, "ground": true, "secret_key": "se_bamboo_cache"},
		{"at": Vector3(-46.80, 0, -47.45), "ground": true, "secret_key": "yanxia_cave"}
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
		var sup_hint := "深藏物资箱 · 单词解锁 [F]" if spot.secret_key != "" else "常规物资箱 · 单词解锁 [F]"
		var sup_lbl = game._label3d(pickup, sup_hint, Vector3(0, 0.96, 0), 26, Color("8ef0c8") if spot.secret_key != "" else game.GOLD)
		sup_lbl.visibility_range_end = 22.0
		game.pickup_nodes.append(pickup)

	# Tactical Field Ammo Crates & Consumable Pouches (tactical_pickups.glb)
	var field_tactical = [
		{"at": Vector3(8.8, 0, 8.2), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "5.56 军用弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-5.5, 0, -21.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "5.56 军用弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-28.5, 0, -11.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "西岭营旁弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(31.8, 0, -28.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "东坡营旁弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-24.8, 0, -78.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "西北高地弹药箱", "col": Color("ffd15c"), "secret_key": ""},
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
	var tag = "[F] %s" % parent.get_meta("title", "战术补给")
	var tac_lbl = game._label3d(parent, tag, Vector3(0, 0.72, 0), 22, glow_col)
	tac_lbl.visibility_range_end = 20.0

func _is_near_bridge(z: float, margin: float = 3.4) -> bool:
	for bz in game.Layout.STREAM_BRIDGES:
		if absf(z - float(bz)) < margin:
			return true
	return false

func _stream():
	# 1) Carved concave wet-pebble streambed & mossy cobble banks (z = -111.5 .. +58.0, opaque for zero alpha-sort conflict)
	var bed_verts := PackedVector3Array()
	var bed_normals := PackedVector3Array()
	var bed_uvs := PackedVector2Array()
	var bed_colors := PackedColorArray()
	var bed_rows := []
	var bz_cur := -111.5
	while bz_cur <= 58.01:
		var zc := minf(bz_cur, 58.0)
		var cx := _outer_stream_x(zc)
		var wy := _stream_water_y_any(zc)
		var w_sc := _outer_stream_width_scale(zc)
		var end_fade := maxf(1.0 - smoothstep(-111.5, -109.2, zc), smoothstep(50.5, 58.0, zc))
		var row := []
		for u_i in range(-7, 8):
			var norm_off := float(u_i) * 0.34  # -2.38 .. +2.38m
			var off := norm_off * w_sc
			var px := cx + off
			var base_h := float(game.terrain_height(px, zc)) if zc <= 36.0 else (_outer_valley_y(px, zc) + 0.055 * (1.0 - smoothstep(1.48, 2.22, absf(norm_off))))
			var lip_taper := lerpf(0.014, -0.058, smoothstep(1.86, 2.38, absf(norm_off)))
			var py := base_h + lip_taper
			var wet := 1.0 - smoothstep(wy - 0.02, wy + 0.30, py)
			var grass_blend := maxf(smoothstep(1.74, 2.28, absf(norm_off)), end_fade)
			var r_t := clampf(float(game.Layout.road_distance(px, zc)) / 4.5, 0.0, 1.0) if zc <= 36.0 else 1.0
			var s_t := clampf(absf(off) / 3.6, 0.0, 1.0)
			row.append([Vector3(px, py, zc), Vector2(px * 0.56, zc * 0.56), Color(wet, grass_blend, r_t, s_t)])
		bed_rows.append(row)
		bz_cur += 0.75

	for r_i in bed_rows.size() - 1:
		var r0: Array = bed_rows[r_i]
		var r1: Array = bed_rows[r_i + 1]
		for c_i in r0.size() - 1:
			var a0: Array = r0[c_i]
			var a1: Array = r0[c_i + 1]
			var b0: Array = r1[c_i]
			var b1: Array = r1[c_i + 1]
			var qv: Array[Vector3] = [a0[0] as Vector3, a1[0] as Vector3, b0[0] as Vector3, b1[0] as Vector3]
			var qu: Array[Vector2] = [a0[1] as Vector2, a1[1] as Vector2, b0[1] as Vector2, b1[1] as Vector2]
			var qc: Array[Color] = [a0[2] as Color, a1[2] as Color, b0[2] as Color, b1[2] as Color]
			var nrm: Vector3 = (qv[1] - qv[0]).cross(qv[2] - qv[0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for k in [0, 1, 2, 1, 3, 2]:
				bed_verts.append(qv[k])
				bed_normals.append(nrm)
				bed_uvs.append(qu[k])
				bed_colors.append(qc[k])

	var bed_arr := []
	bed_arr.resize(Mesh.ARRAY_MAX)
	bed_arr[Mesh.ARRAY_VERTEX] = bed_verts
	bed_arr[Mesh.ARRAY_NORMAL] = bed_normals
	bed_arr[Mesh.ARRAY_TEX_UV] = bed_uvs
	bed_arr[Mesh.ARRAY_COLOR] = bed_colors
	var bed_mesh := ArrayMesh.new()
	bed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bed_arr)
	var bed_inst := MeshInstance3D.new()
	bed_inst.name = "StreamChannelBed"
	bed_inst.mesh = bed_mesh
	var bed_shader := Shader.new()
	bed_shader.code = """shader_type spatial;
uniform sampler2D pebbles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D pebbles_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D pebbles_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
void vertex(){
 wpos = VERTEX;
}
void fragment(){
 float wet = clamp(COLOR.r, 0.0, 1.0);
 float grass_t = clamp(COLOR.g, 0.0, 1.0);
 vec3 p_col = texture(pebbles, UV).rgb;
 float p_rough = texture(pebbles_rough, UV).r;
 float moss_n = 0.5 + 0.5 * sin(wpos.x * 2.3 + cos(wpos.z * 1.9) * 2.1);
 vec3 dry_cobble = mix(p_col * vec3(0.68, 0.68, 0.62), p_col * vec3(0.40, 0.50, 0.32), moss_n * 0.52 * (1.0 - wet));
 vec3 wet_pebble = p_col * vec3(0.42, 0.46, 0.40);
 vec3 channel_col = mix(dry_cobble, wet_pebble, wet);

 vec2 soil_uv = wpos.xz * 0.28;
 vec3 s_tex = texture(soil, soil_uv).rgb;
 float edge = smoothstep(0.36, 0.94, COLOR.b);
 float stream_bank = 1.0 - smoothstep(0.45, 0.98, COLOR.a);
 float patch_n = 0.5 + 0.5 * sin(wpos.x * 0.27 + sin(wpos.z * 0.21) * 2.0);
 vec3 greenery = mix(vec3(0.28, 0.35, 0.19), vec3(0.42, 0.44, 0.27), patch_n);
 vec3 bed_soil = mix(s_tex * vec3(0.56, 0.50, 0.37), s_tex * greenery * 1.42, edge);
 vec3 wet_stone = s_tex * vec3(0.32, 0.36, 0.30);
 vec3 grass_col = mix(bed_soil, wet_stone, stream_bank * 0.78);
 float bank_rough = mix(0.94, 0.62, stream_bank);

 ALBEDO = mix(channel_col, grass_col, grass_t);
 NORMAL_MAP = mix(texture(pebbles_normal, UV).rgb, texture(soil_normal, soil_uv).rgb, grass_t);
 NORMAL_MAP_DEPTH = mix(0.88, 0.52, grass_t);
 ROUGHNESS = mix(mix(clamp(p_rough * 0.92, 0.55, 0.92), 0.22, wet), bank_rough, grass_t);
 SPECULAR = mix(mix(0.16, 0.52, wet), 0.5, grass_t);
}
"""
	var bed_mat := ShaderMaterial.new()
	bed_mat.shader = bed_shader
	bed_mat.set_shader_parameter("pebbles", load("res://assets/slice/river_pebbles_color.jpg"))
	bed_mat.set_shader_parameter("pebbles_normal", load("res://assets/slice/river_pebbles_normal.jpg"))
	bed_mat.set_shader_parameter("pebbles_rough", load("res://assets/slice/river_pebbles_rough.jpg"))
	bed_mat.set_shader_parameter("soil", load("res://assets/slice/ground_color.jpg"))
	bed_mat.set_shader_parameter("soil_normal", load("res://assets/slice/ground_normal.jpg"))
	bed_inst.material_override = bed_mat
	bed_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed_inst)

	# 2) Continuous clear mountain brook flowing from North Spring (z=-111) right underneath South Fence (z=26) into the village paddies (z=166)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var rows := []
	var z_cur := float(game.Layout.STREAM_Z_MIN)
	while z_cur <= 166.01:
		var zc := minf(z_cur, 166.0)
		var cx := _outer_stream_x(zc)
		var wy := _stream_water_y_any(zc)
		var w_sc := _outer_stream_width_scale(zc)
		var hw := 1.92 * w_sc * smoothstep(-112.0, -108.5, zc)
		hw = maxf(hw, 0.58)
		var tail_fade := 1.0 - smoothstep(150.0, 166.0, zc)
		var v_coord := (zc + 112.0) * 0.22
		var r_pts := []
		for s_i in 5:
			var frac := -1.0 + float(s_i) * 0.5  # -1.0, -0.5, 0.0, +0.5, +1.0
			var edge_amt := absf(frac)
			r_pts.append([Vector3(cx + frac * hw, wy, zc), Vector2(0.5 + frac * 0.5, v_coord), Color(edge_amt, tail_fade, 0.0)])
		rows.append(r_pts)
		z_cur += 1.0 if zc < 48.0 else 3.5

	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for seg in 4:
			var a0: Array = r0[seg]
			var a1: Array = r0[seg + 1]
			var b0: Array = r1[seg]
			var b1: Array = r1[seg + 1]
			var quad_v := [a0[0] as Vector3, a1[0] as Vector3, b0[0] as Vector3, b1[0] as Vector3]
			var quad_u := [a0[1] as Vector2, a1[1] as Vector2, b0[1] as Vector2, b1[1] as Vector2]
			var quad_c := [a0[2] as Color, a1[2] as Color, b0[2] as Color, b1[2] as Color]
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
render_mode blend_mix, cull_disabled;
varying float edge_t;
varying float tail_a;
varying vec3 wpos;
void vertex(){
 edge_t = COLOR.r;
 tail_a = COLOR.g;
 wpos = VERTEX;
 float rip = sin(TIME * 2.4 + VERTEX.z * 1.7 + sin(VERTEX.x * 2.3) * 1.4) * 0.011;
 VERTEX.y += rip * (1.0 - edge_t * 0.75);
}
void fragment(){
 float w1 = sin(UV.y * 9.5 - TIME * 2.6 + sin(UV.x * 7.2 + TIME * 0.9) * 1.15);
 float w2 = cos(UV.y * 15.3 - TIME * 3.4 - cos(wpos.x * 2.9 - TIME * 1.1) * 1.25);
 float ripple = 0.5 + 0.28 * w1 + 0.22 * w2;
 float glint = smoothstep(0.76, 0.98, ripple) * (1.0 - edge_t * 0.55);
 float bank_foam = smoothstep(0.76, 0.95, edge_t + 0.06 * w1) * (1.0 - smoothstep(0.95, 1.0, edge_t));
 vec3 deep_jade = vec3(0.09, 0.22, 0.20);
 vec3 shallow_olive = vec3(0.16, 0.30, 0.25);
 vec3 col = mix(deep_jade, shallow_olive, clamp(edge_t * 0.72 + ripple * 0.28, 0.0, 1.0));
 col = mix(col, vec3(0.78, 0.86, 0.82), max(bank_foam * 0.55, glint * 0.32));
 ALBEDO = col;
 NORMAL = normalize(vec3((w1 - w2) * 0.07, 1.0, (w1 + w2) * 0.07));
 ROUGHNESS = 0.12;
 SPECULAR = 0.68;
 float shore_alpha = mix(0.62, 0.06, smoothstep(0.68, 0.99, edge_t));
 ALPHA = shore_alpha * tail_a;
}
"""
	var wmat := ShaderMaterial.new()
	wmat.shader = wshader
	water.material_override = wmat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# 3) Northern spring headwater boulders
	rock(Vector3(game.Layout.stream_center_x(-111.0), 0, -112.0), 2.4, 2)
	rock(Vector3(game.Layout.stream_center_x(-110.5) - 2.3, 0, -110.5), 1.8, 0)
	rock(Vector3(game.Layout.stream_center_x(-110.5) + 2.3, 0, -110.5), 1.9, 1)

	# 4) 3 walkable creek crossings: South & North mountain wooden footbridges + Central v0.6.0 Stone Arch Bridge
	for bz in game.Layout.STREAM_BRIDGES:
		if is_equal_approx(float(bz), -24.0):
			_build_stone_arch_bridge(float(bz))
		else:
			_build_footbridge(float(bz))

	# 5) Dense MultiMesh shoreline cobbles, reeds & cattails lining both recessed creek banks
	var cobble_meshes: Array = []
	var cobble_txs: Array = [[], [], []]
	for m_i in 3:
		cobble_meshes.append(_extract_mesh("res://assets/slice/rock_%d.glb" % m_i))
	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var reed_mesh := _extract_mesh(v061_path, "prop_reed_clump")
	var cattail_mesh := _extract_mesh(v061_path, "prop_cattail_clump")
	var reed_tx: Array = []
	var cattail_tx: Array = []

	var bank_rng := RandomNumberGenerator.new()
	bank_rng.seed = 20260611
	var sz_cur := -108.5
	var bank_idx := 0
	while sz_cur <= 44.0:
		if not _is_near_bridge(sz_cur, 3.6):
			var cx_b := _outer_stream_x(sz_cur)
			var w_sc := _outer_stream_width_scale(sz_cur)
			for side_s in [-1.0, 1.0]:
				var side_f := float(side_s)
				var cob_off := side_f * (1.32 + bank_rng.randf_range(0.0, 0.48)) * w_sc
				var cob_x := cx_b + cob_off
				var cob_z := sz_cur + bank_rng.randf_range(-0.40, 0.40)
				var hx0 := _surface_height_any(cob_x - 0.5, cob_z)
				var hx1 := _surface_height_any(cob_x + 0.5, cob_z)
				var hz0 := _surface_height_any(cob_x, cob_z - 0.5)
				var hz1 := _surface_height_any(cob_x, cob_z + 0.5)
				if absf(hx1 - hx0) > 0.52 or absf(hz1 - hz0) > 0.52:
					bank_idx += 1
					continue
				var surf_up := Vector3(hx0 - hx1, 1.0, hz0 - hz1).normalized()
				var cyaw := bank_rng.randf_range(0.0, TAU)
				var c_right := Vector3(cos(cyaw), 0.0, -sin(cyaw))
				var c_fwd := surf_up.cross(c_right).normalized()
				c_right = c_fwd.cross(surf_up).normalized()
				var cob_y := _surface_height_any(cob_x, cob_z) - 0.09
				var cob_sc := bank_rng.randf_range(0.16, 0.36)
				var cob_basis := Basis(c_right, surf_up, c_fwd).scaled(Vector3(cob_sc * 1.15, cob_sc * 0.72, cob_sc))
				cobble_txs[bank_idx % 3].append(Transform3D(cob_basis, Vector3(cob_x, cob_y, cob_z)))
				if bank_idx % 3 == 0:
					var reed_off := side_f * (1.68 + bank_rng.randf_range(0.04, 0.46)) * w_sc
					var rx := cx_b + reed_off
					var rz := sz_cur + bank_rng.randf_range(-0.50, 0.50)
					var rhx := absf(_surface_height_any(rx + 0.45, rz) - _surface_height_any(rx - 0.45, rz))
					if rhx <= 0.48:
						var ry := _surface_height_any(rx, rz) - 0.06
						var rsc := bank_rng.randf_range(0.76, 1.16)
						var r_xf := Transform3D(Basis(Vector3.UP, bank_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rsc), Vector3(rx, ry, rz))
						if bank_idx % 6 == 0:
							cattail_tx.append(r_xf)
						else:
							reed_tx.append(r_xf)
				bank_idx += 1
		sz_cur += 2.15

	for m_i in 3:
		_batch_direct(cobble_meshes[m_i], cobble_txs[m_i], false, "StreamBankCobbles_%d" % m_i, 58.0)
	_batch_direct(reed_mesh, reed_tx, false, "StreamBankReeds", 84.0)
	_batch_direct(cattail_mesh, cattail_tx, false, "StreamBankCattails", 84.0)

	# 6) Batched creek emerald lotus pads & pink blooms sitting cleanly flush on calm creek pools
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.24
	pad_mesh.bottom_radius = 0.21
	pad_mesh.height = 0.020
	pad_mesh.radial_segments = 14
	var bloom_mesh := SphereMesh.new()
	bloom_mesh.radius = 0.070
	bloom_mesh.height = 0.10
	bloom_mesh.radial_segments = 10
	var pad_tx: Array = []
	var bloom_tx: Array = []
	for k_idx in 16:
		var lz := -96.0 + float(k_idx) * 7.4
		if _is_near_bridge(lz, 3.2):
			continue
		var cx := _outer_stream_x(lz)
		var wy := _stream_water_y_any(lz) + 0.010
		var off := (-0.65 if k_idx % 2 == 0 else 0.62) + sin(float(k_idx) * 1.7) * 0.18
		var ps := 0.82 + float(k_idx % 3) * 0.16
		pad_tx.append(Transform3D(Basis(Vector3.UP, float(k_idx) * 1.1).scaled(Vector3(ps, 1.0, ps)), Vector3(cx + off, wy, lz)))
		if k_idx % 2 == 0:
			bloom_tx.append(Transform3D(Basis.IDENTITY, Vector3(cx + off, wy + 0.042, lz)))
	_batch(pad_mesh, game._material(Color("3b7d45")), pad_tx, false)
	_batch(bloom_mesh, game._material(Color("f0a4c2")), bloom_tx, false)

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
			var pier: Node3D = game._mesh_box(root, Vector3(sx, -0.82, sz), Vector3(0.16, 1.56, 0.16), Color.WHITE, true)
			pier.material_override = wood_post_mat

	# Sloped approach ramps with rotated pivot (mesh + StaticBody3D together) flush at deck y=0 and ground x=cx+-5.4
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var run := 3.0
		var outer_x := cx + side_f * (2.4 + run)
		var outer_h := float(game.terrain_height(outer_x, z_center))
		var drop := maxf(0.12, deck_y - (outer_h - 0.06))
		var ramp_len := sqrt(run * run + drop * drop) + 0.18
		var ramp_pivot := Node3D.new()
		ramp_pivot.position = Vector3(side_f * (2.4 + run * 0.5), -drop * 0.5, 0.0)
		ramp_pivot.rotation.z = -side_f * atan2(drop, run)
		root.add_child(ramp_pivot)
		var ramp: Node3D = game._mesh_box(ramp_pivot, Vector3(0, -0.07, 0), Vector3(ramp_len, 0.14, 2.22), Color.WHITE, true)
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
			_polish_node_materials(sub)
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
			[Vector3(3.5, 0, -18.0), Vector3(7.4, 0, -21.2), Vector3(10.8, 0, -24.0)],
			[Vector3(22.2, 0, -24.0), Vector3(26.5, 0, -24.0), Vector3(28.5, 0, -8.0), Vector3(31.5, 0, 8.0), Vector3(33.2, 0, 17.8)],
			[Vector3(5.5, 0, 6.2), Vector3(13.0, 0, 7.0)],
			[Vector3(23.8, 0, 7.0), Vector3(28.0, 0, 13.5), Vector3(32.2, 0, 19.6)],
			[Vector3(5.5, 0, -49.0), Vector3(13.0, 0, -46.5)],
			[Vector3(23.6, 0, -46.5), Vector3(27.2, 0, -46.5), Vector3(27.0, 0, -35.5), Vector3(26.5, 0, -25.2)],
			[Vector3(-18.2, 0, -27.2), Vector3(-23.0, 0, -27.6), Vector3(-28.0, 0, -26.5)],
			[Vector3(-28.0, 0, -29.0), Vector3(-33.5, 0, -33.2), Vector3(-41.6, 0, -32.2), Vector3(-41.6, 0, -36.5)],
			[Vector3(-25.0, 0, -31.5), Vector3(-33.2, 0, -44.0), Vector3(-35.2, 0, -44.0)],
			[Vector3(-41.6, 0, -36.6), Vector3(-41.6, 0, -38.1)],
			[Vector3(-41.6, 0, -54.4), Vector3(-41.6, 0, -57.4)]
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

func _prepare_v062_mesh_materials(src_mesh: Mesh) -> Mesh:
	if src_mesh == null:
		return null
	var mesh: Mesh = src_mesh.duplicate()
	for s in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(s)
		if mat is BaseMaterial3D:
			var bmat := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			var mname := mat.resource_name
			if mname.contains("SkylightBeam") or (not mname.contains("Yanxia") and bmat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and bmat.albedo_color.a < 0.35):
				bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
				bmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				bmat.albedo_color = Color(0.76, 0.93, 0.89, 0.17)
			elif mname.contains("YanxiaMural") or mname.contains("YanxiaChronicle"):
				bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				bmat.roughness = 0.88
				bmat.metallic_specular = 0.18
			elif mname.contains("JadePool") or mname.contains("JadeWater") or bmat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
				bmat.roughness = 0.08
				bmat.metallic_specular = 0.68
			mesh.surface_set_material(s, bmat)
	return mesh

func _instantiate_v062_mesh(mesh_name: String) -> Node3D:
	var path := "res://assets/slice/v062_bamboo_cave.glb"
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
			var targets: Array = []
			if sub is MeshInstance3D:
				targets.append(sub)
			targets.append_array(sub.find_children("*", "MeshInstance3D", true, false))
			for t in targets:
				var mi := t as MeshInstance3D
				if mi and mi.mesh:
					mi.mesh = _prepare_v062_mesh_materials(mi.mesh)
			inst.queue_free()
			return sub
		inst.queue_free()
	return null

func _extract_v062_mesh(mesh_name: String) -> Mesh:
	var path := "res://assets/slice/v062_bamboo_cave.glb"
	var cache_key := path + "::v062::" + mesh_name
	if extracted_mesh_cache.has(cache_key):
		return extracted_mesh_cache[cache_key]
	if not ResourceLoader.exists(path):
		return null
	if not game.scene_cache.has(path):
		game.scene_cache[path] = load(path)
	var inst: Node3D = game.scene_cache[path].instantiate()
	var target: Node = inst.find_child(mesh_name, true, false)
	if target != null and not (target is MeshInstance3D):
		var sub_m := target.find_children("*", "MeshInstance3D", true, false)
		target = sub_m[0] if not sub_m.is_empty() else null
	var out: Mesh = _prepare_v062_mesh_materials((target as MeshInstance3D).mesh) if (target is MeshInstance3D) else null
	inst.queue_free()
	extracted_mesh_cache[cache_key] = out
	return out

func _build_bamboo_maze_and_yanxia_cave():
	# 1) "迷踪竹石阵" — 5x6 Multi-Path Taihu Karst & Moso Bamboo Labyrinth + row-6 Cavern Forecourt
	var maze_root := Node3D.new()
	maze_root.name = "BambooStoneMaze"
	add_child(maze_root)

	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var culm_mesh := _extract_mesh(v061_path, "bamboo_culm_single")
	var clump_mesh := _extract_mesh(v061_path, "bamboo_clump")
	var fern_mesh := _extract_mesh(v061_path, "prop_fern_clump")
	var karst_a_mesh := _extract_v062_mesh("karst_monolith_a")
	var karst_b_mesh := _extract_v062_mesh("karst_monolith_b")

	var karst_a_tx: Array = []
	var karst_b_tx: Array = []
	var maze_culm_tx: Array = []
	var maze_clump_tx: Array = []
	var maze_fern_tx: Array = []
	var m_rng := RandomNumberGenerator.new()
	m_rng.seed = 20260620

	var x0 := -48.10
	var cw := 2.60
	var z0 := -36.50
	var ch := 3.00

	# South Bluestone Archway ("迷 踪 竹 石 阵") at (rl=0, c=2) = (-41.60, y, -36.50)
	var gate_pos := Vector3(-41.60, float(game.terrain_height(-41.60, -36.50)) - 0.04, -36.50)
	var gate_node := Node3D.new()
	gate_node.name = "BambooMazeSouthGate"
	gate_node.position = gate_pos
	maze_root.add_child(gate_node)
	var gate_vis := _instantiate_v062_mesh("bamboo_maze_gate")
	if gate_vis:
		gate_node.add_child(gate_vis)
	for sx in [-1.0, 1.0]:
		var pier_shp := BoxShape3D.new()
		pier_shp.size = Vector3(0.62, 3.20, 0.78)
		game.Props.shape_body(gate_node, pier_shp, Vector3(sx * 1.42, 1.60, 0.0)).add_to_group("solid_props")
	var gate_lintel := BoxShape3D.new()
	gate_lintel.size = Vector3(3.40, 0.80, 0.86)
	game.Props.shape_body(gate_node, gate_lintel, Vector3(0.0, 3.28, 0.0)).add_to_group("solid_props")

	# Central Eroded Karst Crouch Arch ("矮石暗拱 · [C] 蹲伏潜行") at (rl=3, c=2) = (-41.60, y, -45.50)
	var arch_gy := float(game.terrain_height(-41.60, -45.50))
	var arch_node := Node3D.new()
	arch_node.name = "KarstCrouchArch"
	arch_node.position = Vector3(-41.60, arch_gy, -45.50)
	maze_root.add_child(arch_node)
	var arch_vis := _instantiate_v062_mesh("karst_crouch_arch")
	if arch_vis:
		arch_node.add_child(arch_vis)
	for sx in [-1.0, 1.0]:
		var ap_shp := BoxShape3D.new()
		ap_shp.size = Vector3(0.62, 3.20, 0.88)
		game.Props.shape_body(arch_node, ap_shp, Vector3(sx * 1.02, 1.60, 0.0)).add_to_group("solid_props")
	# Bottom strictly at +1.25m (blocks standing 1.675m, passes [C] crouch 1.115m!)
	var arch_top := BoxShape3D.new()
	arch_top.size = Vector3(2.64, 2.06, 0.90)
	game.Props.shape_body(arch_node, arch_top, Vector3(0.0, 2.28, 0.0)).add_to_group("solid_props")
	for sz_lbl in [0.58, -0.58]:
		var a_lbl: Label3D = game._label3d(arch_node, "奇石矮拱 · 按 [C] 蹲伏潜行", Vector3(0.0, 1.62, sz_lbl), 22, Color("a8f0d4"))
		a_lbl.pixel_size = 0.0036
		a_lbl.visibility_range_end = 11.5

	# Maze wall graph: open_h[rl] (rl=0..6, cols 0..4) & open_v[cl] (cl=0..5, rows 0..6)
	var open_h := {
		0: [2],
		1: [0, 3, 4],
		2: [1, 3],
		3: [4],
		4: [0, 1, 3],
		5: [1, 3],
		6: [2]
	}
	var open_v := {
		0: [],
		1: [0, 1, 2, 4, 5, 6],
		2: [0, 1, 2, 3, 5, 6],
		3: [0, 2, 3, 4, 6],
		4: [0, 2, 3, 4, 5, 6],
		5: [2]
	}

	var wall_segments: Array = []
	for rl in 7:
		var hz := z0 - float(rl) * ch
		var oh: Array = open_h.get(rl, [])
		for c in 5:
			if c in oh or (rl == 3 and c == 2):
				continue
			wall_segments.append([x0 + (float(c) + 0.5) * cw, hz, cw, true, false])
	for cl in 6:
		var vx := x0 + float(cl) * cw
		var ov: Array = open_v.get(cl, [])
		for r in 7:
			if r in ov:
				continue
			var is_moya_wall := (cl == 5 and r == 4)
			wall_segments.append([vx, z0 - (float(r) + 0.5) * ch, ch, false, is_moya_wall])

	for seg_idx in wall_segments.size():
		var seg: Array = wall_segments[seg_idx]
		var mx: float = seg[0]
		var mz: float = seg[1]
		var slen: float = seg[2]
		var is_horiz: bool = seg[3]
		var is_moya: bool = seg[4]
		var gy := float(game.terrain_height(mx, mz))

		var w_shp := BoxShape3D.new()
		if is_moya:
			w_shp.size = Vector3(0.56, 3.30, slen + 0.14)
			game.Props.shape_body(maze_root, w_shp, Vector3(mx + 0.05, gy + 1.60, mz)).add_to_group("solid_props")
			for z_flank in [-1.25, 1.25]:
				var zf := float(z_flank)
				var fy := float(game.terrain_height(mx, mz + zf)) - 0.18
				karst_b_tx.append(Transform3D(Basis(Vector3.UP, m_rng.randf_range(-0.3, 0.3)).scaled(Vector3(0.95, 1.08, 0.95)), Vector3(mx + 0.06, fy, mz + zf)))
			continue

		w_shp.size = Vector3(slen + 0.14, 3.30, 0.64) if is_horiz else Vector3(0.64, 3.30, slen + 0.14)
		game.Props.shape_body(maze_root, w_shp, Vector3(mx, gy + 1.60, mz)).add_to_group("solid_props")

		var base_yaw := 0.0 if is_horiz else PI * 0.5
		var dir_v := Vector3(1.0, 0.0, 0.0) if is_horiz else Vector3(0.0, 0.0, 1.0)
		var perp_v := Vector3(0.0, 0.0, 1.0) if is_horiz else Vector3(1.0, 0.0, 0.0)

		# Mix Taihu strange karst monoliths & lush Moso bamboo culms along every closed wall segment
		if seg_idx % 3 != 1:
			var k_off := m_rng.randf_range(-0.38, 0.38)
			var kp := Vector3(mx, 0.0, mz) + dir_v * k_off
			var ky := float(game.terrain_height(kp.x, kp.z)) - 0.18
			var ksc := m_rng.randf_range(0.92, 1.18)
			var kyaw := base_yaw + (PI if m_rng.randf() < 0.5 else 0.0) + m_rng.randf_range(-0.18, 0.18)
			var k_xf := Transform3D(Basis(Vector3.UP, kyaw).scaled(Vector3(ksc * 1.04, ksc, ksc * 0.88)), Vector3(kp.x, ky, kp.z))
			if seg_idx % 2 == 0:
				karst_a_tx.append(k_xf)
			else:
				karst_b_tx.append(k_xf)
			var f_pos := kp + perp_v * (0.26 if seg_idx % 2 == 0 else -0.26)
			maze_fern_tx.append(Transform3D(Basis(Vector3.UP, m_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * 0.92), Vector3(f_pos.x, float(game.terrain_height(f_pos.x, f_pos.z)) - 0.03, f_pos.z)))

		for b_i in [-0.92, 0.0, 0.92]:
			var b_off := float(b_i)
			if seg_idx % 3 != 1 and absf(b_off) < 0.2:
				continue
			var bp: Vector3 = Vector3(mx, 0.0, mz) + dir_v * (b_off + m_rng.randf_range(-0.14, 0.14)) + perp_v * m_rng.randf_range(-0.10, 0.10)
			var by := float(game.terrain_height(bp.x, bp.z)) - 0.04
			var bsc := m_rng.randf_range(0.86, 1.18)
			var b_basis := Basis(Vector3.UP, m_rng.randf_range(0.0, TAU)).rotated(Vector3.RIGHT, m_rng.randf_range(-0.035, 0.035)).scaled(Vector3(bsc * 0.92, bsc, bsc * 0.92))
			maze_culm_tx.append(Transform3D(b_basis, Vector3(bp.x, by, bp.z)))

		if seg_idx % 4 == 1:
			var cp := Vector3(mx, 0.0, mz) + dir_v * m_rng.randf_range(-0.25, 0.25)
			var cy := float(game.terrain_height(cp.x, cp.z)) - 0.05
			maze_clump_tx.append(Transform3D(Basis(Vector3.UP, m_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * 0.72), Vector3(cp.x, cy, cp.z)))

	# East Side Gate framing monoliths & hint at (-35.10, y, -44.00)
	for ez_off in [-1.22, 1.22]:
		var ez := float(ez_off)
		var egy := float(game.terrain_height(-35.10, -44.00 + ez)) - 0.18
		karst_b_tx.append(Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(0.88, 1.04, 0.88)), Vector3(-35.10, egy, -44.00 + ez)))
	var egate_lbl: Label3D = game._label3d(maze_root, "迷踪竹石阵 · 东侧幽径", Vector3(-34.85, float(game.terrain_height(-35.10, -44.00)) + 2.35, -44.00), 22, Color("e8dfc0"))
	egate_lbl.pixel_size = 0.0038
	egate_lbl.visibility_range_end = 15.0

	# West Secret Alcove (0, 3): Ancient Bluestone Sundial Pedestal at (-46.80, y, -46.25)
	var sun_gy := float(game.terrain_height(-46.80, -46.25)) - 0.02
	var sundial := Node3D.new()
	sundial.name = "StoneSundialPedestal"
	sundial.position = Vector3(-46.80, sun_gy, -46.25)
	maze_root.add_child(sundial)
	var sun_vis := _instantiate_v062_mesh("stone_sundial_pedestal")
	if sun_vis:
		sundial.add_child(sun_vis)
	var sun_shp := CylinderShape3D.new()
	sun_shp.radius = 0.44
	sun_shp.height = 1.18
	game.Props.shape_body(sundial, sun_shp, Vector3(0.0, 0.59, 0.0)).add_to_group("solid_props")
	var sun_lbl: Label3D = game._label3d(sundial, "先民青石日晷残座", Vector3(0.0, 1.52, 0.0), 20, Color("e8d8a8"))
	sun_lbl.pixel_size = 0.0034
	sun_lbl.visibility_range_end = 10.5

	# East Cliff Moya Carving Alcove (4, 4): "竹石清音" Cliff Stele at (-35.38, y, -50.00) facing -X West
	var moya_gy := float(game.terrain_height(-35.38, -50.00)) - 0.04
	var moya_node := Node3D.new()
	moya_node.name = "CliffMoyaStele"
	moya_node.position = Vector3(-35.38, moya_gy, -50.00)
	maze_root.add_child(moya_node)
	var moya_vis := _instantiate_v062_mesh("cliff_moya_stele")
	if moya_vis:
		moya_node.add_child(moya_vis)

	# 6 Hexagonal Mossy Jiangnan Stone Lanterns guiding key labyrinth junctions & Cavern Forecourt
	var lantern_pts := [
		Vector2(-40.62, -37.28),
		Vector2(-40.62, -44.72),
		Vector2(-42.55, -46.28),
		Vector2(-37.22, -48.92),
		Vector2(-42.55, -53.80),
		Vector2(-40.05, -56.35)
	]
	for l_idx in lantern_pts.size():
		var lp: Vector2 = lantern_pts[l_idx]
		var lgy := float(game.terrain_height(lp.x, lp.y)) - 0.02
		var l_node := Node3D.new()
		l_node.name = "MazeStoneLantern_%d" % l_idx
		l_node.position = Vector3(lp.x, lgy, lp.y)
		l_node.rotation.y = float(l_idx) * 0.52
		maze_root.add_child(l_node)
		var l_vis := _instantiate_v062_mesh("stone_maze_lantern")
		if l_vis:
			l_node.add_child(l_vis)
		var l_shp := CylinderShape3D.new()
		l_shp.radius = 0.22
		l_shp.height = 1.48
		game.Props.shape_body(l_node, l_shp, Vector3(0.0, 0.74, 0.0)).add_to_group("solid_props")

	# 2) "烟霞古洞" — Walk-in 2-Chamber Limestone Cavern with Ancient Mineral Mural, Chronicle, Skylight Jade Pool & Hearth Relics
	var cave_root := Node3D.new()
	cave_root.name = "YanxiaAncientCave"
	cave_root.position = Vector3(-41.60, 6.50, -64.00)
	add_child(cave_root)

	var cave_vis := _instantiate_v062_mesh("yanxia_cave_complex")
	if cave_vis:
		cave_root.add_child(cave_vis)

	var hearth_vis := _instantiate_v062_mesh("ancestral_hearth_relics")
	if hearth_vis:
		hearth_vis.position = Vector3(0.55, 0.026, -3.35)
		cave_root.add_child(hearth_vis)

	# Analytical cavern physics colliders (walkable wet limestone floor at y_local=+0.026m, 3.24m x 3.25m portal, walls & roof)
	var cave_boxes := [
		[Vector3(0.0, -0.174, 0.25), Vector3(7.60, 0.40, 12.30)],   # Walkable wet limestone floor slab (top = +0.026m = 6.526m world)
		[Vector3(-2.05, 0.70, -2.85), Vector3(2.08, 1.35, 3.08)],   # Sunken Jade Spring Pool rim guard
		[Vector3(-3.40, 2.60, 5.68), Vector3(3.56, 5.60, 1.68)],    # South portal West cliff buttress (leaves x >= -1.62 open)
		[Vector3(3.40, 2.60, 5.68), Vector3(3.56, 5.60, 1.68)],     # South portal East cliff buttress (leaves x <= +1.62 open)
		[Vector3(0.0, 4.50, 5.68), Vector3(3.60, 2.50, 1.68)],      # South portal over-arch brow (bottom = 3.25m)
		[Vector3(-4.35, 2.70, -0.15), Vector3(2.20, 5.80, 12.20)],  # West cavern cliff wall (inner face = -3.25)
		[Vector3(4.35, 2.70, -0.15), Vector3(2.20, 5.80, 12.20)],   # East cavern cliff wall (inner face = +3.25)
		[Vector3(0.0, 2.70, -6.15), Vector3(9.60, 5.80, 2.00)],     # North cavern back wall (inner face = -5.15)
		[Vector3(0.0, 4.95, 0.0), Vector3(9.60, 2.00, 12.40)],      # Vaulted mountain roof cap (bottom = 3.95m)
		[Vector3(-0.33, 0.46, -3.70), Vector3(1.04, 0.88, 0.94)]    # Ancestral stone tea hearth
	]
	for cb in cave_boxes:
		var c_shp := BoxShape3D.new()
		c_shp.size = cb[1]
		game.Props.shape_body(cave_root, c_shp, cb[0]).add_to_group("solid_props")

	var tbl_shp := CylinderShape3D.new()
	tbl_shp.radius = 0.68
	tbl_shp.height = 0.82
	game.Props.shape_body(cave_root, tbl_shp, Vector3(0.93, 0.44, -3.25)).add_to_group("solid_props")

	# Distance-faded shadowless cavern lights (0ms cost beyond 32m; steep raking torchlight grazes chiseled rock walls!)
	var light_specs := [
		[Vector3(-2.32, 3.04, 3.42), Color("ffd094"), 1.06, 5.8],
		[Vector3(2.32, 2.98, 2.30), Color("ffd094"), 1.02, 5.6],
		[Vector3(-1.65, 2.65, -2.85), Color("8ef2df"), 1.38, 6.2],
		[Vector3(0.45, 1.45, -3.30), Color("ffb25e"), 1.22, 5.4]
	]
	for ls in light_specs:
		var ol := OmniLight3D.new()
		ol.position = ls[0]
		ol.light_color = ls[1]
		ol.light_energy = ls[2]
		ol.omni_range = ls[3]
		ol.shadow_enabled = false
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 24.0
		ol.distance_fade_length = 8.0
		cave_root.add_child(ol)

	var chron_lbl: Label3D = game._label3d(cave_root, "石壁题志 ·《烟霞古洞志》", Vector3(2.86, 2.82, 2.85), 20, Color("e8dec2"))
	chron_lbl.pixel_size = 0.0034
	chron_lbl.visibility_range_end = 11.0
	var pool_lbl: Label3D = game._label3d(cave_root, "一线天光 · 洞中寒潭", Vector3(-1.95, 1.52, -2.85), 20, Color("9ef5e2"))
	pool_lbl.pixel_size = 0.0034
	pool_lbl.visibility_range_end = 11.5

	# Natural Moso bamboo & woodland ferns crowning the exterior karst mountain bluff atop Yanxia Cave
	var bluff_bamboo := [
		Vector3(-44.6, 12.15, -60.5), Vector3(-38.5, 12.25, -60.8),
		Vector3(-45.2, 12.10, -65.2), Vector3(-38.8, 12.35, -65.6),
		Vector3(-42.8, 12.20, -69.0), Vector3(-39.6, 12.25, -68.6)
	]
	for bb in bluff_bamboo:
		maze_clump_tx.append(Transform3D(Basis(Vector3.UP, m_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * 0.78), bb))
	for bf_i in 8:
		var bfx := -41.6 + cos(float(bf_i) * 0.78) * 3.4
		var bfz := -64.0 + sin(float(bf_i) * 0.78) * 4.6
		maze_fern_tx.append(Transform3D(Basis(Vector3.UP, float(bf_i) * 1.1).scaled(Vector3.ONE * 1.12), Vector3(bfx, 12.05, bfz)))

	_batch_direct(karst_a_mesh, karst_a_tx, true, "MazeKarstMonolithsA", 96.0)
	_batch_direct(karst_b_mesh, karst_b_tx, true, "MazeKarstMonolithsB", 96.0)
	_batch_direct(culm_mesh, maze_culm_tx, false, "MazeBambooCulms", 98.0)
	_batch_direct(clump_mesh, maze_clump_tx, false, "MazeBambooClumps", 96.0)
	_batch_direct(fern_mesh, maze_fern_tx, false, "MazeKarstFerns", 58.0)

func _flora_meadows():
	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var grass_f := _extract_mesh(v061_path, "prop_grass_tuft")
	var azalea_f := _extract_mesh(v061_path, "prop_azalea_bush")
	var wfern_f := _extract_mesh(v061_path, "prop_fern_clump")
	var log_f := _extract_mesh(v061_path, "prop_fallen_log")

	var red_f := _extract_mesh("res://assets/nature/flower_redA.glb")
	var yel_f := _extract_mesh("res://assets/nature/flower_yellowA.glb")
	var pur_f := _extract_mesh("res://assets/nature/flower_purpleA.glb")
	var mush_f := _extract_mesh("res://assets/nature/mushroom_redGroup.glb")
	var orchid_f := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "flora_glow_orchid")
	var fern_f := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "flora_berry_fern")

	var grass_tx: Array = []
	var azalea_tx: Array = []
	var wfern_tx: Array = []
	var log_tx: Array = []
	var red_tx: Array = []
	var yel_tx: Array = []
	var pur_tx: Array = []
	var mush_tx: Array = []
	var orchid_tx: Array = []
	var fern_tx: Array = []

	# 1) Dense batched wild grass tufts ("山野草丛") across hillsides, fence-post margins & creek meadows
	for g_i in 920:
		var gx := rng.randf_range(-55.5, 55.5)
		var gz := rng.randf_range(-115.5, 31.0)
		# Bias half of grass tufts toward outer slopes & fence margins so perimeter meadows feel rich and natural
		if g_i % 2 == 0 and absf(gx) < 32.0 and gz > -98.0 and gz < 15.0:
			gx = (1.0 if g_i % 4 == 0 else -1.0) * rng.randf_range(32.0, 55.0)
		if game.Layout.road_distance(gx, gz) < 2.9 or absf(gx - _outer_stream_x(gz)) < 2.25 or game.Layout.is_in_bamboo_cave_zone(gx, gz, 0.35):
			continue
		var gy := _surface_height_any(gx, gz) - 0.02
		var gsc := rng.randf_range(0.95, 1.68)
		grass_tx.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(gsc, gsc * rng.randf_range(0.85, 1.20), gsc)), Vector3(gx, gy, gz)))

	# 2) Flowering Azaleas ("映山红灌木"), Woodland Ferns & Wildflowers across mountain slopes & fence edges
	for i in 360:
		var fx := rng.randf_range(-54.5, 54.5)
		var fz := rng.randf_range(-114.5, 29.0)
		if i % 3 == 0 and absf(fx) < 30.0 and fz > -96.0 and fz < 14.0:
			fx = (1.0 if i % 6 == 0 else -1.0) * rng.randf_range(31.0, 54.0)
		if game.Layout.clear_for_route(fx, fz, 0.7) or absf(fx - _outer_stream_x(fz)) < 2.35:
			continue
		var fy := _surface_height_any(fx, fz)
		var yaw := rng.randf_range(0.0, TAU)
		var r_choice := i % 10
		if r_choice == 0 or r_choice == 1:
			azalea_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.82, 1.32)), Vector3(fx, fy - 0.04, fz)))
		elif r_choice == 2 or r_choice == 3 or r_choice == 4:
			wfern_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.92, 1.52)), Vector3(fx, fy - 0.03, fz)))
		elif r_choice == 5 or r_choice == 6:
			red_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.62, 0.94)), Vector3(fx, fy - 0.02, fz)))
		elif r_choice == 7:
			yel_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.62, 0.94)), Vector3(fx, fy - 0.02, fz)))
		elif r_choice == 8:
			pur_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.64, 0.96)), Vector3(fx, fy - 0.02, fz)))
		else:
			mush_tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.55, 0.86)), Vector3(fx, fy - 0.02, fz)))

	# 3) Wild-Boar Ambush Thickets (dense flowering azalea & fern clusters on slopes where boars nestle)
	var boar_thickets := [
		Vector3(-38.5, 0, 11.5), Vector3(39.5, 0, 2.5), Vector3(-45.5, 0, -26.5),
		Vector3(38.5, 0, -68.5), Vector3(-37.5, 0, -82.0)
	]
	for b_idx in boar_thickets.size():
		var bt: Vector3 = boar_thickets[b_idx]
		for k in 4:
			var ang := float(k) * (TAU / 4.0) + float(b_idx) * 0.6
			var bx := bt.x + cos(ang) * 0.95
			var bz := bt.z + sin(ang) * 0.95
			var by := _surface_height_any(bx, bz) - 0.04
			azalea_tx.append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * (1.08 + float(k % 2) * 0.18)), Vector3(bx, by, bz)))
			var fx2 := bt.x + cos(ang + 0.5) * 1.45
			var fz2 := bt.z + sin(ang + 0.5) * 1.45
			wfern_tx.append(Transform3D(Basis(Vector3.UP, ang * 1.3).scaled(Vector3.ONE * 1.35), Vector3(fx2, _surface_height_any(fx2, fz2) - 0.03, fz2)))

	# 4) Mossy Fallen Logs resting flush on forest & fence-side slopes
	for l_i in 26:
		var lx := rng.randf_range(-49.5, 49.5)
		var lz := rng.randf_range(-108.0, 21.0)
		if l_i % 2 == 0 and absf(lx) < 32.0:
			lx = (1.0 if l_i % 4 == 0 else -1.0) * rng.randf_range(33.0, 49.5)
		if game.Layout.clear_for_route(lx, lz, 2.2) or _is_vista_corridor(lx, lz):
			continue
		var ly := _surface_height_any(lx, lz) - 0.05
		var hx0 := _surface_height_any(lx - 0.8, lz)
		var hx1 := _surface_height_any(lx + 0.8, lz)
		var hz0 := _surface_height_any(lx, lz - 0.8)
		var hz1 := _surface_height_any(lx, lz + 0.8)
		var nrm := Vector3(hx0 - hx1, 1.6, hz0 - hz1).normalized()
		var lyaw := rng.randf_range(0.0, TAU)
		var l_right := Vector3(cos(lyaw), 0.0, -sin(lyaw))
		var l_fwd := nrm.cross(l_right).normalized()
		l_right = l_fwd.cross(nrm).normalized()
		var lsc := rng.randf_range(0.84, 1.24)
		log_tx.append(Transform3D(Basis(l_right, nrm, l_fwd).scaled(Vector3.ONE * lsc), Vector3(lx, ly, lz)))

	# 5) Cluster exotic orchids & berry ferns near creek banks, bridges, overlooks & caves
	var special_spots := [
		Vector3(14.5, 0, 12.0), Vector3(13.8, 0, -18.5), Vector3(22.5, 0, -29.0),
		Vector3(21.2, 0, -43.0), Vector3(23.2, 0, -64.0), Vector3(21.5, 0, -78.0),
		Vector3(21.2, 0, -96.0), Vector3(-22.0, 0, -69.5), Vector3(-27.2, 0, -24.5),
		Vector3(-25.0, 0, -49.0), Vector3(8.5, 0, 14.5), Vector3(28.5, 0, -83.5)
	]
	for idx in special_spots.size():
		var sp: Vector3 = special_spots[idx]
		var sy := _surface_height_any(sp.x, sp.z)
		var tx := Transform3D(Basis(Vector3.UP, float(idx) * 0.95).scaled(Vector3.ONE * 1.15), Vector3(sp.x, sy, sp.z))
		if idx % 2 == 0:
			orchid_tx.append(tx)
		else:
			fern_tx.append(tx)

	_batch_direct(grass_f, grass_tx, false, "HillsideGrassTufts", 54.0)
	_batch_direct(azalea_f, azalea_tx, false, "HillsideAzaleaBushes", 88.0)
	_batch_direct(wfern_f, wfern_tx, false, "HillsideFernClumps", 58.0)
	_batch_direct(log_f, log_tx, false, "HillsideFallenLogs", 84.0)
	_batch_direct(red_f, red_tx, false, "", 56.0)
	_batch_direct(yel_f, yel_tx, false, "", 56.0)
	_batch_direct(pur_f, pur_tx, false, "", 56.0)
	_batch_direct(mush_f, mush_tx, false, "", 52.0)
	_batch_direct(orchid_f, orchid_tx, false, "", 68.0)
	_batch_direct(fern_f, fern_tx, false, "", 68.0)

func _fence_post_profile(px: float, pz: float) -> Vector2:
	# Returns Vector2(bottom_y, top_y): posts stand strictly vertical, plunging deep into creek streambed where crossing water!
	var fmax_z := float(game.Layout.FENCE_MAX_Z)
	var scx := float(game.Layout.stream_center_x(fmax_z))
	var ground_y := _surface_height_any(px, pz)
	if is_equal_approx(pz, fmax_z) and absf(px - scx) < 2.95:
		var west_bank_y := _surface_height_any(scx - 3.05, fmax_z)
		var east_bank_y := _surface_height_any(scx + 3.05, fmax_z)
		var span_t := clampf((px - (scx - 3.05)) / 6.10, 0.0, 1.0)
		var rail_ground_ref := lerpf(west_bank_y, east_bank_y, span_t)
		var bed_bottom := minf(ground_y, _stream_water_y_any(fmax_z) - 0.52) - 0.65
		return Vector2(bed_bottom, rail_ground_ref + 1.24)
	return Vector2(ground_y - 0.58, ground_y + 1.24)

func _append_fence_segment(posts_xz: Array, post_tx: Array, cap_tx: Array, rail_tx: Array, close_loop: bool = false):
	var profiles: Array = []
	for p in posts_xz:
		var v2 := p as Vector2
		profiles.append(_fence_post_profile(v2.x, v2.y))
	var count := posts_xz.size()
	for i in count:
		var xz := posts_xz[i] as Vector2
		var prof := profiles[i] as Vector2
		var h := maxf(0.5, prof.y - prof.x)
		var mid_y := 0.5 * (prof.x + prof.y)
		post_tx.append(Transform3D(Basis(Vector3.UP, float(i) * 0.7).scaled(Vector3(1.0, h, 1.0)), Vector3(xz.x, mid_y, xz.y)))
		cap_tx.append(Transform3D(Basis.IDENTITY, Vector3(xz.x, prof.y + 0.025, xz.y)))

	var fmax_z := float(game.Layout.FENCE_MAX_Z)
	var scx := float(game.Layout.stream_center_x(fmax_z))
	var seg_count := count if close_loop else (count - 1)
	for i in seg_count:
		var j := (i + 1) % count
		var a_xz := posts_xz[i] as Vector2
		var b_xz := posts_xz[j] as Vector2
		var a_top := (profiles[i] as Vector2).y
		var b_top := (profiles[j] as Vector2).y
		var delta := Vector3(b_xz.x - a_xz.x, b_top - a_top, b_xz.y - a_xz.y)
		var horiz := Vector3(delta.x, 0.0, delta.z)
		if horiz.length_squared() < 0.001:
			continue
		var h_dir := horiz.normalized()
		var perp := Vector3(-h_dir.z, 0.0, h_dir.x)
		# Sheared Basis(delta, UP * rail_h, perp * rail_t) joins adjacent vertical posts seamlessly with zero V-gaps!
		var rail_basis := Basis(delta, Vector3.UP * 0.095, perp * 0.066)
		var mid_top := Vector3(0.5 * (a_xz.x + b_xz.x), 0.5 * (a_top + b_top), 0.5 * (a_xz.y + b_xz.y))
		rail_tx.append(Transform3D(rail_basis, mid_top - Vector3(0.0, 0.20, 0.0)))
		rail_tx.append(Transform3D(rail_basis, mid_top - Vector3(0.0, 0.64, 0.0)))
		# Extra lower water-gate rail across the creek span so timber pilings & crossbars frame the flowing brook cleanly
		if is_equal_approx(a_xz.y, fmax_z) and is_equal_approx(b_xz.y, fmax_z) and absf(0.5 * (a_xz.x + b_xz.x) - scx) < 2.6:
			rail_tx.append(Transform3D(rail_basis, mid_top - Vector3(0.0, 1.04, 0.0)))

func _boundary():
	# Continuous 360-degree mountain timber perimeter fence with strictly vertical pilings planted into terrain & creek bed
	var ring_pts: Array = []
	var fmin_x := float(game.Layout.FENCE_MIN_X)  # -52.0
	var fmax_x := float(game.Layout.FENCE_MAX_X)  # +52.0
	var fmin_z := float(game.Layout.FENCE_MIN_Z)  # -112.0
	var fmax_z := float(game.Layout.FENCE_MAX_Z)  # +26.0

	# 1) North edge (-52 -> +52 at z = -112): 32 equal bays of 3.25m
	for k in 32:
		ring_pts.append(Vector2(fmin_x + float(k) * 3.25, fmin_z))
	# 2) East edge (-112 -> +26 at x = +52): 44 equal bays of ~3.136m
	for k in 44:
		ring_pts.append(Vector2(fmax_x, lerpf(fmin_z, fmax_z, float(k) / 44.0)))
	# 3) South edge (+52 -> -52 at z = +26), placing dedicated submerged creek pilings at x = 18.45 & 16.75 inside the brook!
	var south_xs := [
		52.0, 48.75, 45.5, 42.25, 39.0, 35.75, 32.5, 29.25, 26.0, 22.75,
		20.20, 18.45, 16.75, 15.00,
		13.0, 9.75, 6.5, 3.25, 0.0, -3.25, -6.5, -9.75, -13.0, -16.25,
		-19.5, -22.75, -26.0, -29.25, -32.5, -35.75, -39.0, -42.25, -45.5, -48.75
	]
	for sx in south_xs:
		ring_pts.append(Vector2(float(sx), fmax_z))
	# 4) West edge (+26 -> -112 at x = -52): 44 equal bays closing seamlessly back to (-52, -112)
	for k in 44:
		ring_pts.append(Vector2(fmin_x, lerpf(fmax_z, fmin_z, float(k) / 44.0)))

	var post_tx: Array = []
	var cap_tx: Array = []
	var rail_tx: Array = []
	_append_fence_segment(ring_pts, post_tx, cap_tx, rail_tx, true)

	var post_cyl := CylinderMesh.new()
	post_cyl.top_radius = 0.088
	post_cyl.bottom_radius = 0.098
	post_cyl.height = 1.0
	post_cyl.radial_segments = 8
	var cap_box := BoxMesh.new()
	cap_box.size = Vector3(0.22, 0.055, 0.22)
	var rail_box := BoxMesh.new()
	rail_box.size = Vector3(1.0, 1.0, 1.0)

	_batch(post_cyl, wood_post_mat, post_tx, false)
	_batch(cap_box, roof_slate_mat, cap_tx, false)
	_batch(rail_box, wood_plank_mat, rail_tx, false)

	# Solid tall perimeter colliders (player cannot climb over, bullets respect border, yet view above 1.24m rails stays wide open!)
	var walls := [
		[Vector3(fmin_x, 6.0, -43.0), Vector3(0.45, 22.0, 140.0)],
		[Vector3(fmax_x, 6.0, -43.0), Vector3(0.45, 22.0, 140.0)],
		[Vector3(0.0, 8.0, fmin_z), Vector3(106.0, 22.0, 0.45)],
		[Vector3(0.0, 3.0, fmax_z), Vector3(106.0, 18.0, 0.45)]
	]
	for w in walls:
		var shape := BoxShape3D.new()
		shape.size = w[1]
		game.Props.shape_body(self, shape, w[0]).name = "FencePerimeterWall"

	signpost(Vector3(-3.2, 0, 23.2), "烟山观景木栏\n山下稻田 · 诚庄村落 ↓")
	signpost(Vector3(46.2, 0, -21.5), "东岭梯田观景台\n金色水田 · 溪流远山 →")
