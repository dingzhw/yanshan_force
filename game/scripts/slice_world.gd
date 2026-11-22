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
	low_quality = "--low-quality" in OS.get_cmdline_user_args()
	for part in [
		_init_structure_materials, _lighting, _ground, _stream, _vegetation,
		_flora_meadows, _camp, _landmarks, _boundary
	]:
		var began := Time.get_ticks_msec()
		part.call()
		game.startup_ms[str(part.get_method()).trim_prefix("_")] = Time.get_ticks_msec() - began
	set_low_quality(low_quality)

var world_env_ref: Environment = null
var fog_volumes: Array[Node3D] = []
var ink_post_quad: MeshInstance3D = null
var drizzle_particles: CPUParticles3D = null
var ink_arch_mat_cache: Dictionary = {}

func _init_structure_materials():
	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	var tile_tex = load("res://assets/slice/ink_jiangnan/tile_albedo.jpg")
	var tile_nrm = load("res://assets/slice/ink_jiangnan/tile_normal.jpg")
	wood_post_mat = StandardMaterial3D.new()
	wood_post_mat.albedo_color = Color("463f38")
	wood_post_mat.albedo_texture = bark_tex
	wood_post_mat.uv1_scale = Vector3(1, 3, 1)
	wood_post_mat.roughness = 0.90
	wood_post_mat.metallic_specular = 0.05

	wood_plank_mat = StandardMaterial3D.new()
	wood_plank_mat.albedo_color = Color("524a41")
	wood_plank_mat.albedo_texture = bark_tex
	wood_plank_mat.uv1_scale = Vector3(2, 1, 1)
	wood_plank_mat.roughness = 0.88
	wood_plank_mat.metallic_specular = 0.05

	roof_slate_mat = StandardMaterial3D.new()
	roof_slate_mat.albedo_color = Color("2b3033")
	roof_slate_mat.albedo_texture = tile_tex
	roof_slate_mat.normal_enabled = true
	roof_slate_mat.normal_texture = tile_nrm
	roof_slate_mat.normal_scale = 0.75
	roof_slate_mat.uv1_scale = Vector3(2.4, 2.4, 1)
	roof_slate_mat.metallic = 0.04
	roof_slate_mat.metallic_specular = 0.16
	roof_slate_mat.roughness = 0.52

func _is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func _lighting():
	var env = WorldEnvironment.new()
	var e = Environment.new()
	world_env_ref = e
	var sky = Sky.new()
	# Taiping-Village ('太平村·江南云海梯田山境') Custom Painterly Sky & Towering Golden Cumulus Cloud Sea!
	var sky_sh := Shader.new()
	sky_sh.code = """shader_type sky;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm_cloud(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.06 + vec2(11.3, 7.7);
		a *= 0.50;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_d = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.42, 0.62, 0.66));
	float y = clamp(dir.y, 0.0, 1.0);
	float sun_dot = max(dot(dir, sun_d), 0.0);

	// 1) Deep vibrant Taiping Village cobalt-cerulean sky visible right down to low FPS elevation angles!
	vec3 zenith_col = vec3(0.025, 0.175, 0.445);
	vec3 mid_sky = vec3(0.095, 0.345, 0.635);
	vec3 low_sky = vec3(0.24, 0.52, 0.76);
	vec3 horiz_cool = vec3(0.74, 0.85, 0.92);
	vec3 horiz_warm = vec3(1.02, 0.88, 0.68);
	vec3 horiz_col = mix(horiz_cool, horiz_warm, pow(sun_dot, 1.5) * 0.82 + 0.15);

	vec3 sky_col = mix(horiz_col, low_sky, smoothstep(0.0, 0.065, y));
	sky_col = mix(sky_col, mid_sky, smoothstep(0.05, 0.18, y));
	sky_col = mix(sky_col, zenith_col, smoothstep(0.16, 0.48, y));
	// Warm golden solar aureole
	sky_col += vec3(1.0, 0.84, 0.55) * pow(sun_dot, 9.0) * 0.30;
	sky_col += vec3(1.0, 0.95, 0.82) * smoothstep(0.9985, 0.9997, dot(dir, sun_d)) * 1.4;

	if (dir.y > -0.02) {
		// 2) Crisp cauliflower-sculpted towering cumulus clouds ('晴空暖金立体云朵', leaving 55%+ open blue sky!)
		vec2 dome_uv = dir.xz / max(0.18, dir.y + 0.14);
		vec2 drift = vec2(TIME * 0.0035, TIME * 0.0018);
		float n_macro = fbm_cloud(dome_uv * 0.85 + drift);
		float n_billow = abs(vnoise(dome_uv * 2.6 - drift * 1.3) * 2.0 - 1.0);
		float n_detail = fbm_cloud(dome_uv * 4.8 + vec2(3.7, 8.2));
		float cauliflower = n_macro * 0.66 + (1.0 - n_billow) * 0.22 + n_detail * 0.12;
		float band = (1.0 - smoothstep(0.28, 0.62, y)) * smoothstep(0.00, 0.06, dir.y);
		float cloud_field = cauliflower + band * 0.08;
		float density = smoothstep(0.56, 0.66, cloud_field) * smoothstep(-0.005, 0.045, dir.y);

		// Crisp directional sunlit golden-ivory crown vs cool sky-blue shadow belly
		vec2 sun_step = sun_d.xz * 0.14;
		float n_sun = fbm_cloud((dome_uv + sun_step) * 0.85 + drift) * 0.68 + fbm_cloud((dome_uv + sun_step) * 4.8 + vec2(3.7, 8.2)) * 0.32;
		float self_lit = clamp(0.54 + (cauliflower - n_sun) * 3.2 + y * 0.24 + sun_dot * 0.26, 0.0, 1.0);

		vec3 cloud_shadow = vec3(0.44, 0.62, 0.80);
		vec3 cloud_mid = vec3(0.88, 0.92, 0.96);
		vec3 cloud_sunlit = mix(vec3(1.00, 0.97, 0.91), vec3(1.08, 0.92, 0.72), 0.55 + 0.45 * sun_dot);
		vec3 cloud_col = mix(cloud_shadow, cloud_mid, smoothstep(0.18, 0.54, self_lit));
		cloud_col = mix(cloud_col, cloud_sunlit, smoothstep(0.50, 0.86, self_lit));

		sky_col = mix(sky_col, cloud_col, density * (1.0 - smoothstep(0.52, 0.78, y)));
	} else {
		sky_col = mix(horiz_col, vec3(0.28, 0.42, 0.26), smoothstep(0.0, 0.45, -dir.y));
	}
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		COLOR = pow(max(sky_col, vec3(0.0)), vec3(0.74));
	#else
		COLOR = sky_col;
	#endif
}
"""
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_sh
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.72
	e.ambient_light_energy = 0.52
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		e.ambient_light_energy = 0.66
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.04
	e.tonemap_white = 1.38

	# Crystal-clear mountain air (0..72m 100% vibrant clarity) + distant valley sea-of-clouds aerial perspective!
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color("d8e8f3")
	e.fog_sun_scatter = 0.26
	e.fog_depth_begin = 72.0
	e.fog_depth_end = 385.0
	e.fog_depth_curve = 1.45
	e.fog_aerial_perspective = 0.38
	e.fog_sky_affect = 0.0
	e.fog_height_density = 0.0

	var use_modern_fx := _is_forward_plus() and not low_quality
	e.ssao_enabled = use_modern_fx
	e.ssao_radius = 1.10
	e.ssao_intensity = 1.05
	e.ssao_power = 1.25
	e.volumetric_fog_enabled = use_modern_fx
	e.volumetric_fog_density = 0.0005
	e.volumetric_fog_albedo = Color("eaf2f8")
	e.volumetric_fog_emission = Color("dce8f2")
	e.volumetric_fog_emission_energy = 0.06
	e.volumetric_fog_length = 125.0
	env.environment = e
	add_child(env)

	# Warm golden-ivory morning sunlight ('云开日出暖金阳') contrasting with cool cerulean sky shadows!
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -42, 0)
	sun.light_color = Color("ffecc4")
	sun.light_energy = 1.34
	sun.shadow_enabled = not low_quality
	sun.shadow_blur = 1.45
	sun.directional_shadow_max_distance = 52
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.05
	add_child(sun)

	_setup_valley_fog_volumes(use_modern_fx)
	_setup_ink_contour_and_drizzle(not low_quality)

func _setup_valley_fog_volumes(active_now: bool):
	fog_volumes.clear()
	if not _is_forward_plus():
		return
	var fog_sh := Shader.new()
	fog_sh.code = """shader_type fog;
void fog() {
	vec3 p = WORLD_POSITION * vec3(0.042, 0.24, 0.042) + vec3(TIME * 0.028, 0.0, TIME * 0.018);
	float n1 = sin(p.x * 2.1 + cos(p.z * 1.8) * 1.4);
	float n2 = cos(p.z * 3.3 - sin(p.x * 2.7) * 1.2);
	float wisp = smoothstep(-0.12, 0.72, 0.5 * n1 + 0.5 * n2);
	float edge_fade = 1.0 - smoothstep(0.46, 1.0, length(UVW * 2.0 - 1.0));
	DENSITY = 0.028 * wisp * edge_fade;
	ALBEDO = vec3(0.94, 0.96, 0.98);
	EMISSION = vec3(0.90, 0.93, 0.96) * 0.20;
}
"""
	var fmat := ShaderMaterial.new()
	fmat.shader = fog_sh
	# Billowing Taiping-style valley sea-of-clouds framing the sunlit village & paddies along mountain flanks!
	var mist_spots := [
		[Vector3(-64.0, -3.5, 76.0), Vector3(68.0, 10.5, 62.0)],
		[Vector3(72.0, -3.5, 82.0), Vector3(68.0, 10.5, 62.0)],
		[Vector3(8.0, -2.5, 162.0), Vector3(175.0, 12.0, 58.0)],
		[Vector3(96.0, -4.0, -14.0), Vector3(58.0, 9.5, 88.0)],
		[Vector3(-96.0, -4.0, -10.0), Vector3(58.0, 9.5, 88.0)],
	]
	for sp in mist_spots:
		var fv := FogVolume.new()
		fv.position = sp[0]
		fv.size = sp[1]
		fv.material = fmat
		fv.visible = active_now
		add_child(fv)
		fog_volumes.append(fv)

func _setup_ink_contour_and_drizzle(enable_drizzle: bool):
	# Zero-backbuffer-copy 3D Painterly Silhouette Contour ('远淡近浓青黛飞白轻勾线', ZERO slope banding!)
	ink_post_quad = MeshInstance3D.new()
	ink_post_quad.name = "InkContourAndPaperOverlay"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	ink_post_quad.mesh = qm
	ink_post_quad.extra_cull_margin = 16384.0
	ink_post_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var psh := Shader.new()
	psh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D paper_tex : source_color, filter_linear, repeat_enable;

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		d = d * 2.0 - 1.0;
	#endif
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= max(0.00001, view.w);
	return -view.z;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.0 / max(VIEWPORT_SIZE, vec2(1280.0, 720.0));
	float dc = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float dl = linear_depth(SCREEN_UV - vec2(px.x * 1.25, 0.0), INV_PROJECTION_MATRIX);
	float dr = linear_depth(SCREEN_UV + vec2(px.x * 1.25, 0.0), INV_PROJECTION_MATRIX);
	float du = linear_depth(SCREEN_UV - vec2(0.0, px.y * 1.25), INV_PROJECTION_MATRIX);
	float dd = linear_depth(SCREEN_UV + vec2(0.0, px.y * 1.25), INV_PROJECTION_MATRIX);

	float silhouette_jump = max(max(dl - dc, dr - dc), max(du - dc, dd - dc));
	float thresh = max(0.44, dc * 0.088);
	float edge = smoothstep(thresh, thresh * 2.2, silhouette_jump);

	float near_guard = smoothstep(1.05, 1.65, dc);
	float mist_fade = 1.0 - smoothstep(18.0, 38.0, dc);
	float paper = texture(paper_tex, SCREEN_UV * vec2(3.0, 1.7)).r;
	float dry_brush = smoothstep(0.68, 0.98, paper);
	float ink_line = edge * near_guard * mist_fade * mix(0.14, 0.26, dry_brush);

	float paper_grain = clamp((0.92 - paper) * 0.08, 0.0, 0.012);

	ALBEDO = vec3(0.11, 0.20, 0.24);
	ALPHA = clamp(ink_line + paper_grain, 0.0, 0.28);
}
"""
	var pmat := ShaderMaterial.new()
	pmat.shader = psh
	pmat.render_priority = -4
	pmat.set_shader_parameter("paper_tex", load("res://assets/slice/ink_jiangnan/xuan_paper_grain.jpg"))
	ink_post_quad.material_override = pmat
	add_child(ink_post_quad)

	# Delicate sunlit mountain breeze motes ('山间晴岚暖金微尘') floating gently in morning sunbeams!
	drizzle_particles = CPUParticles3D.new()
	drizzle_particles.name = "JiangnanMistyDrizzle"
	drizzle_particles.position = Vector3(8.0, 6.5, -14.0)
	drizzle_particles.amount = 110
	drizzle_particles.lifetime = 4.5
	drizzle_particles.preprocess = 2.5
	drizzle_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drizzle_particles.emission_box_extents = Vector3(32.0, 5.0, 32.0)
	drizzle_particles.direction = Vector3(0.65, 0.25, 0.45).normalized()
	drizzle_particles.spread = 35.0
	drizzle_particles.gravity = Vector3(0.0, 0.04, 0.0)
	drizzle_particles.initial_velocity_min = 0.35
	drizzle_particles.initial_velocity_max = 0.85
	var mote_quad := QuadMesh.new()
	mote_quad.size = Vector2(0.038, 0.038)
	var rmat := StandardMaterial3D.new()
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	rmat.albedo_color = Color(1.0, 0.95, 0.82, 0.28)
	mote_quad.material = rmat
	drizzle_particles.mesh = mote_quad
	drizzle_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drizzle_particles.emitting = enable_drizzle
	drizzle_particles.visible = enable_drizzle
	add_child(drizzle_particles)

func set_low_quality(value: bool):
	low_quality = value
	for child in get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = not low_quality
	var use_modern_fx := _is_forward_plus() and not low_quality
	if world_env_ref != null:
		world_env_ref.ssao_enabled = use_modern_fx
		world_env_ref.volumetric_fog_enabled = use_modern_fx
	for fv in fog_volumes:
		if is_instance_valid(fv):
			fv.visible = use_modern_fx
	if is_instance_valid(drizzle_particles):
		drizzle_particles.visible = not low_quality
		drizzle_particles.emitting = not low_quality
	if get_viewport() != null:
		get_viewport().scaling_3d_scale = 0.90 if low_quality else 1.0
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

func _ground_vis_y(x: float, z: float) -> float:
	var h := float(game.terrain_height(x, z))
	var sd := float(game.Layout.stream_distance(x, z))
	if sd < 2.22 and z >= game.Layout.STREAM_Z_MIN - 1.2:
		h -= 0.055 * (1.0 - smoothstep(1.48, 2.22, sd))
	var cx_c := float(game.Layout.YANXIA_CAVE_CENTER.x)
	var cz_c := float(game.Layout.YANXIA_CAVE_CENTER.z)
	if x > cx_c - 4.6 and x < cx_c + 4.6 and z > cz_c - 6.1 and z < cz_c + 6.4:
		var wx := 1.0 - smoothstep(3.6, 4.5, absf(x - cx_c))
		var wz := (1.0 - smoothstep(cz_c + 5.7, cz_c + 6.4, z)) * (1.0 - smoothstep(cz_c - 5.2, cz_c - 6.1, z))
		h -= 0.50 * wx * wz
	return h

func _smooth_vis_normal(x: float, z: float) -> Vector3:
	var eps := 0.55
	var hx0 := _ground_vis_y(x - eps, z)
	var hx1 := _ground_vis_y(x + eps, z)
	var hz0 := _ground_vis_y(x, z - eps)
	var hz1 := _ground_vis_y(x, z + eps)
	return Vector3(hx0 - hx1, 2.0 * eps, hz0 - hz1).normalized()

func _ground():
	# v0.8.5: 1-pass O(N) terrain bake over 201x261 grid [-100..100] x [-210..50] (3x playable area!)
	var min_xi := int(game.Layout.MIN_X)
	var max_xi := int(game.Layout.MAX_X)
	var min_zi := int(game.Layout.MIN_Z)
	var max_zi := int(game.Layout.MAX_Z)
	var WIDTH := int(game.Layout.GRID_WIDTH)
	var DEPTH := int(game.Layout.GRID_DEPTH)
	var total := WIDTH * DEPTH

	var heights := PackedFloat32Array()
	heights.resize(total)
	var vis_y := PackedFloat32Array()
	vis_y.resize(total)
	var verts := PackedVector3Array()
	verts.resize(total)
	var normals := PackedVector3Array()
	normals.resize(total)
	var uvs := PackedVector2Array()
	uvs.resize(total)
	var colors := PackedColorArray()
	colors.resize(total)

	var cx_c := float(game.Layout.YANXIA_CAVE_CENTER.x)
	var cz_c := float(game.Layout.YANXIA_CAVE_CENTER.z)
	var arena_c: Vector3 = game.Layout.CLOUD_ARENA_CENTER
	var arena_r := float(game.Layout.CLOUD_ARENA_RADIUS)
	var s_zmin := float(game.Layout.STREAM_Z_MIN)

	var idx := 0
	for zi in range(min_zi, max_zi + 1):
		var z := float(zi)
		for xi in range(min_xi, max_xi + 1):
			var x := float(xi)
			var h := float(game.terrain_height(x, z))
			heights[idx] = h
			var vh := h
			var sd := float(game.Layout.stream_distance(x, z))
			if sd < 2.22 and z >= s_zmin - 1.2:
				vh -= 0.055 * (1.0 - smoothstep(1.48, 2.22, sd))
			if x > cx_c - 4.6 and x < cx_c + 4.6 and z > cz_c - 6.1 and z < cz_c + 6.4:
				var wx := 1.0 - smoothstep(3.6, 4.5, absf(x - cx_c))
				var wz := (1.0 - smoothstep(cz_c + 5.7, cz_c + 6.4, z)) * (1.0 - smoothstep(cz_c - 5.2, cz_c - 6.1, z))
				vh -= 0.50 * wx * wz
			vis_y[idx] = vh
			verts[idx] = Vector3(x, vh, z)
			uvs[idx] = Vector2(x, z) * 0.24
			var road := clampf(game.Layout.road_distance(x, z, 4.6) / 4.6, 0.0, 1.0)
			# Paint the 38m Cloud-Top Martial Arena plaza floor with crisp carved Jiangnan bluestone!
			var ad := Vector2(x - arena_c.x, z - arena_c.z).length()
			if ad < arena_r + 1.5:
				road = minf(road, smoothstep(arena_r - 1.2, arena_r + 1.5, ad))
			var stream := clampf(sd / 3.8, 0.0, 1.0)
			colors[idx] = Color(road, stream, 0.0)
			idx += 1

	# Fast central-difference vertex normals directly from precomputed vis_y array (saves 4x redundant terrain lookups!)
	for rz in DEPTH:
		var z0 := maxi(0, rz - 1)
		var z1 := mini(DEPTH - 1, rz + 1)
		var dz_span := float(z1 - z0)
		var row_off := rz * WIDTH
		for rx in WIDTH:
			var x0 := maxi(0, rx - 1)
			var x1 := mini(WIDTH - 1, rx + 1)
			var dx_span := float(x1 - x0)
			var hx0 := vis_y[row_off + x0]
			var hx1 := vis_y[row_off + x1]
			var hz0 := vis_y[z0 * WIDTH + rx]
			var hz1 := vis_y[z1 * WIDTH + rx]
			normals[row_off + rx] = Vector3((hx0 - hx1) / dx_span, 1.0, (hz0 - hz1) / dz_span).normalized()

	var indices := PackedInt32Array()
	indices.resize((WIDTH - 1) * (DEPTH - 1) * 6)
	var ii := 0
	for z in DEPTH - 1:
		for x in WIDTH - 1:
			var top := z * WIDTH + x
			var bottom := top + WIDTH
			indices[ii] = top
			indices[ii + 1] = top + 1
			indices[ii + 2] = bottom
			indices[ii + 3] = top + 1
			indices[ii + 4] = bottom + 1
			indices[ii + 5] = bottom
			ii += 6
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground = MeshInstance3D.new()
	ground.name = "ContinuousGround"
	ground.mesh = mesh
	var shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_cobble : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D trail_stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D trail_stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 pos;
void vertex(){pos=VERTEX;}
void fragment(){
 // Multi-scale UV blend eliminates 2002-style tiled grass repetition!
 vec3 tex_near = texture(soil, UV).rgb;
 vec3 tex_macro = texture(soil, UV * 0.23 + vec2(0.37, 0.19)).rgb;
 float lum = dot(mix(tex_near, tex_macro, 0.55), vec3(0.299, 0.587, 0.114));
 float tex_tone = mix(0.84, 1.14, clamp(lum * 1.45, 0.0, 1.0));

 float road_edge = smoothstep(0.28, 0.90, COLOR.r);
 float stream_bank = 1.0 - smoothstep(0.32, 0.98, COLOR.g);

 // Warm sunlit golden-olive spring meadow & cool emerald shaded patches (Taiping Village hillside harmony!)
 float wash1 = 0.5 + 0.5 * sin(pos.x * 0.13 + sin(pos.z * 0.11) * 2.2);
 float wash2 = 0.5 + 0.5 * cos(pos.z * 0.27 - cos(pos.x * 0.23) * 1.7);
 float ink_wash = smoothstep(0.25, 0.78, wash1 * 0.65 + wash2 * 0.35);

 vec3 damp_moss = mix(vec3(0.11, 0.25, 0.14), vec3(0.26, 0.39, 0.13), ink_wash);
 // v0.8.1 FB-3: Crisp carved Jiangnan bluestone path bedding along mountain trails instead of muddy blur
 vec2 flag_uv = pos.xz * 0.52;
 vec3 stone_albedo = texture(trail_stone, flag_uv).rgb;
 vec3 stone_nrm = texture(trail_stone_nrm, flag_uv).rgb;
 float trail_core = 1.0 - smoothstep(0.18, 0.68, COLOR.r);
 vec3 trail_earth = mix(vec3(0.34, 0.31, 0.25) * tex_tone, stone_albedo * vec3(0.96, 0.98, 0.95), trail_core * 0.86);
 vec3 slope_col = mix(trail_earth, damp_moss * tex_tone, road_edge);

 // Natural CC0 mud-and-cobble feathering along creek banks
 vec2 bank_uv = pos.xz * 0.42;
 vec3 mc_rgb = texture(mud_cobble, bank_uv).rgb;
 float mc_lum = dot(mc_rgb, vec3(0.299, 0.587, 0.114));
 vec3 wet_bank = vec3(0.24, 0.26, 0.23) * mix(0.76, 1.24, mc_lum);

 ALBEDO = mix(slope_col, wet_bank, stream_bank * 0.88);
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
  ALBEDO = pow(ALBEDO, vec3(0.88));
 #endif
 vec3 base_nrm = mix(stone_nrm, texture(soil_normal, UV * 0.65).rgb, smoothstep(0.24, 0.72, COLOR.r));
 NORMAL_MAP = mix(base_nrm, texture(mud_normal, bank_uv).rgb, stream_bank);
 NORMAL_MAP_DEPTH = mix(mix(0.88, 0.24, road_edge), 0.62, stream_bank);
 ROUGHNESS = mix(mix(0.62, 0.95, road_edge), 0.56, stream_bank);
 SPECULAR = mix(0.16, 0.04, road_edge);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("soil", load("res://assets/slice/ground_color.jpg"))
	mat.set_shader_parameter("soil_normal", load("res://assets/slice/ground_normal.jpg"))
	mat.set_shader_parameter("mud_cobble", load("res://assets/slice/ink_jiangnan/mud_cobble_albedo.jpg"))
	mat.set_shader_parameter("mud_normal", load("res://assets/slice/ink_jiangnan/mud_cobble_normal.jpg"))
	mat.set_shader_parameter("trail_stone", load("res://assets/slice/ink_jiangnan/flagstone_albedo.png"))
	mat.set_shader_parameter("trail_stone_nrm", load("res://assets/slice/ink_jiangnan/flagstone_normal.png"))
	ground.material_override = mat
	add_child(ground)

	var shape = HeightMapShape3D.new()
	shape.map_width = WIDTH
	shape.map_depth = DEPTH
	shape.map_data = heights
	var center_x := (float(min_xi) + float(max_xi)) * 0.5
	var center_z := (float(min_zi) + float(max_zi)) * 0.5
	game.Props.shape_body(self, shape, Vector3(center_x, 0.0, center_z)).name = "GroundCollision"

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
uniform float alpha_cut = 0.38;
uniform float sway_amp = 0.042;
uniform float use_baked_ao = 1.0;
uniform float warm_autumn = 0.0;
uniform float camera_dab = 0.0;

varying vec3 v_world_nrm;
varying vec3 v_vcol;
varying float v_instance_var;

void vertex() {
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_vcol = mix(vec3(0.75, clamp(VERTEX.y / 5.5, 0.0, 1.0), 0.45), COLOR.rgb, use_baked_ao);
	vec3 origin_w = MODEL_MATRIX[3].xyz;
	v_instance_var = fract(sin(dot(origin_w.xz, vec2(12.9898, 78.233))) * 43758.5453);

	// Camera-facing painterly sumi-e dab expansion (zero X-card paper edges from ANY view angle!)
	if (camera_dab > 0.5) {
		float dab_sz = 1.20 + COLOR.b * 2.20;
		float rot_ang = (COLOR.a - 0.5) * 1.60 + (v_instance_var - 0.5) * 0.45;
		vec2 q = vec2(UV.x - 0.5, 0.5 - UV.y) * dab_sz;
		float cr = cos(rot_ang);
		float sr = sin(rot_ang);
		vec2 qr = vec2(q.x * cr - q.y * sr, q.x * sr + q.y * cr);
		vec3 w_right = INV_VIEW_MATRIX[0].xyz;
		vec3 w_up = INV_VIEW_MATRIX[1].xyz;
		mat3 world_to_local = transpose(mat3(
			normalize(MODEL_MATRIX[0].xyz),
			normalize(MODEL_MATRIX[1].xyz),
			normalize(MODEL_MATRIX[2].xyz)
		));
		VERTEX += world_to_local * (w_right * qr.x + w_up * qr.y);
	}

	float flex = clamp(v_vcol.g * 0.72 + (1.0 - UV.y) * 0.28, 0.0, 1.0);
	float phase = TIME * 1.35 + origin_w.x * 0.37 + origin_w.z * 0.29 + VERTEX.y * 0.32;
	VERTEX.x += sin(phase) * sway_amp * flex;
	VERTEX.z += cos(phase * 0.85) * sway_amp * 0.65 * flex;
}

void fragment() {
	vec4 tex = texture(leaf_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;

	// Lock normal to smooth 3D spherical canopy normal
	NORMAL = normalize((VIEW_MATRIX * vec4(v_world_nrm, 0.0)).xyz);

	// Taiping Village Cool-to-Warm Hue Shift: cool cerulean-teal sky shadow -> warm golden-sprout sunlit crown!
	float core_ao = clamp(v_vcol.r, 0.24, 1.0);
	float crown_h = clamp(v_vcol.g, 0.0, 1.0);
	float vol_t = smoothstep(0.18, 0.94, core_ao * 0.70 + crown_h * 0.30);

	vec3 shadow_tint = mix(vec3(0.56, 0.78, 0.82), vec3(0.72, 0.70, 0.68), warm_autumn);
	vec3 crown_tint = mix(vec3(1.06, 1.10, 0.86), vec3(1.12, 1.02, 0.88), warm_autumn);
	vec3 var_tint = mix(vec3(0.94, 0.99, 0.96), vec3(1.06, 1.02, 0.90), v_instance_var);

	ALBEDO = tex.rgb * mix(shadow_tint, crown_tint, vol_t) * var_tint;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	// Painterly Half-Lambert + golden morning sun-rim translucency on outer canopy!
	float half_nl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = clamp(half_nl * (0.40 + 0.68 * v_vcol.r), 0.0, 1.0);
	float ink_step = mix(smoothstep(0.24, 0.66, lit), lit, 0.48);
	float back_rim = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0) * clamp(v_vcol.g, 0.15, 1.0) * 0.26;
	DIFFUSE_LIGHT += (LIGHT_COLOR / 3.14159) * (0.30 + 0.86 * ink_step + back_rim) * ATTENUATION;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = qinglu_foliage_shader
	if tex != null:
		sm.set_shader_parameter("leaf_tex", tex)
	var is_willow := "Willow" in mat_key
	var is_maple := "Maple" in mat_key
	var is_azalea := "Azalea" in mat_key
	var is_dab := "SumiDab" in mat_key
	sm.set_shader_parameter("alpha_cut", 0.34 if is_willow else (0.38 if is_dab else 0.40))
	sm.set_shader_parameter("sway_amp", 0.085 if is_willow else (0.022 if is_azalea else 0.040))
	sm.set_shader_parameter("use_baked_ao", 1.0 if has_vcol else 0.0)
	sm.set_shader_parameter("warm_autumn", 0.70 if is_maple else 0.0)
	sm.set_shader_parameter("camera_dab", 1.0 if is_dab else 0.0)
	qinglu_foliage_cache[cache_id] = sm
	return sm

func _get_ink_arch_material(kind: String) -> Material:
	if ink_arch_mat_cache.has(kind):
		return ink_arch_mat_cache[kind]
	var mat: Material = null
	if kind == "plaster":
		# Authentic Hui/Jiangnan '粉墙': weathered whitewashed lime plaster + automatic eave rain-drip ink streaks & plinth moss!
		var sh := Shader.new()
		sh.code = """shader_type spatial;
uniform sampler2D plaster_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D weathered_tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 p_col = texture(plaster_tex, UV * 1.15).rgb;
	vec3 w_col = texture(weathered_tex, UV * 0.75 + vec2(0.23, 0.41)).rgb;
	float w_lum = dot(w_col, vec3(0.299, 0.587, 0.114));
	vec3 base_wall = mix(vec3(0.86, 0.85, 0.81), vec3(0.94, 0.92, 0.88), clamp(p_col.r, 0.0, 1.0));

	// Subtle eave rain-wash streaks & spring moss plinth
	float streak_freq = sin(wpos.x * 19.0 + sin(wpos.z * 17.0) * 1.8) * 0.5 + 0.5;
	float streak_fine = sin(wpos.x * 43.0 - wpos.z * 37.0) * 0.5 + 0.5;
	float streak_mask = smoothstep(0.35, 0.88, streak_freq * 0.65 + streak_fine * 0.35);
	float top_drip = smoothstep(0.55, 0.96, COLOR.r) * streak_mask * 0.36;
	float age_patch = smoothstep(0.58, 0.26, w_lum) * 0.24;
	float base_moss = (1.0 - smoothstep(0.04, 0.26, COLOR.r)) * (0.40 + 0.40 * streak_freq);

	vec3 col = mix(base_wall, vec3(0.42, 0.46, 0.47), clamp(top_drip + age_patch, 0.0, 0.52));
	col = mix(col, vec3(0.26, 0.38, 0.26), clamp(base_moss, 0.0, 0.62));

	ALBEDO = col;
	NORMAL_MAP = texture(plaster_nrm, UV * 1.15).rgb;
	NORMAL_MAP_DEPTH = 0.65;
	ROUGHNESS = 0.92;
	SPECULAR = 0.04;
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("plaster_tex", load("res://assets/slice/ink_jiangnan/plaster_albedo.jpg"))
		sm.set_shader_parameter("plaster_nrm", load("res://assets/slice/ink_jiangnan/plaster_normal.jpg"))
		sm.set_shader_parameter("weathered_tex", load("res://assets/slice/ink_jiangnan/plaster_weathered_albedo.jpg"))
		mat = sm
	elif kind == "tile":
		# Authentic Jiangnan '青黛小青瓦' slate-blue roof tiles catching clear cerulean sky
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color("2d3842")
		sm.albedo_texture = load("res://assets/slice/ink_jiangnan/tile_albedo.jpg")
		sm.normal_enabled = true
		sm.normal_texture = load("res://assets/slice/ink_jiangnan/tile_normal.jpg")
		sm.normal_scale = 0.85
		sm.uv1_scale = Vector3(1.8, 1.8, 1.0)
		sm.roughness = 0.52
		sm.metallic = 0.04
		sm.metallic_specular = 0.18
		mat = sm
	elif kind == "bluestone":
		# v0.8.1 FB-3: Crisp high-res 1024x1024 hand-laid Jiangnan bluestone flagstones with world-space triplanar detail
		var sh := Shader.new()
		sh.code = """shader_type spatial;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_rgh : filter_linear_mipmap, repeat_enable;
varying vec3 w_nrm;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 blend = pow(abs(w_nrm), vec3(5.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec2 uv_x = wpos.zy * 0.56;
	vec2 uv_y = wpos.xz * 0.56;
	vec2 uv_z = wpos.xy * 0.56;
	vec3 st = texture(stone_tex, uv_x).rgb * blend.x + texture(stone_tex, uv_y).rgb * blend.y + texture(stone_tex, uv_z).rgb * blend.z;
	vec3 nm = texture(stone_nrm, uv_x).rgb * blend.x + texture(stone_nrm, uv_y).rgb * blend.y + texture(stone_nrm, uv_z).rgb * blend.z;
	float rgh = texture(stone_rgh, uv_x).r * blend.x + texture(stone_rgh, uv_y).r * blend.y + texture(stone_rgh, uv_z).r * blend.z;
	float micro = dot(texture(stone_tex, uv_y * 2.6 + vec2(0.17, 0.43)).rgb, vec3(0.333));
	vec3 col = st * mix(0.92, 1.14, clamp(micro * 1.45, 0.0, 1.0));
	ALBEDO = col;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.05;
	ROUGHNESS = clamp(rgh, 0.38, 0.94);
	SPECULAR = mix(0.10, 0.26, smoothstep(0.55, 0.95, w_nrm.y));
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("stone_tex", load("res://assets/slice/ink_jiangnan/flagstone_albedo.png"))
		sm.set_shader_parameter("stone_nrm", load("res://assets/slice/ink_jiangnan/flagstone_normal.png"))
		sm.set_shader_parameter("stone_rgh", load("res://assets/slice/ink_jiangnan/flagstone_rough.png"))
		mat = sm
	elif kind == "rock":
		# v0.8.1 FB-2: Razor-sharp world-space triplanar Jiangnan mountain granite / karst rock (zero stretched blurry UVs!)
		var sh := Shader.new()
		sh.code = """shader_type spatial;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_rgh : filter_linear_mipmap, repeat_enable;
varying vec3 w_nrm;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 blend = pow(abs(w_nrm), vec3(4.5));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	// Dual-scale world-space triplanar: macro rock strata (0.34) + crisp close-up crystalline micro-grain (1.28)
	vec2 uv_x = wpos.zy * 0.34;
	vec2 uv_y = wpos.xz * 0.34;
	vec2 uv_z = wpos.xy * 0.34;
	vec3 base_c = texture(rock_tex, uv_x).rgb * blend.x + texture(rock_tex, uv_y).rgb * blend.y + texture(rock_tex, uv_z).rgb * blend.z;
	vec3 micro_c = texture(rock_tex, uv_x * 3.6 + vec2(0.31, 0.17)).rgb * blend.x
		+ texture(rock_tex, uv_y * 3.6 + vec2(0.19, 0.53)).rgb * blend.y
		+ texture(rock_tex, uv_z * 3.6 + vec2(0.41, 0.29)).rgb * blend.z;
	float micro_lum = dot(micro_c, vec3(0.299, 0.587, 0.114));
	vec3 rock_col = base_c * mix(0.84, 1.18, clamp(micro_lum * 1.55, 0.0, 1.0));
	// Gentle spring mountain moss strictly on upward-facing flat shelves (side faces stay sharp granite)
	float top_shelf = smoothstep(0.72, 0.94, w_nrm.y);
	float moss_var = 0.5 + 0.5 * sin(wpos.x * 0.65 + cos(wpos.z * 0.58) * 2.1);
	float moss_mask = top_shelf * smoothstep(0.36, 0.84, moss_var) * 0.52;
	vec3 moss_col = vec3(0.21, 0.33, 0.17) * mix(0.86, 1.16, micro_lum);
	ALBEDO = mix(rock_col, moss_col, moss_mask);
	vec3 n_macro = texture(rock_nrm, uv_x).rgb * blend.x + texture(rock_nrm, uv_y).rgb * blend.y + texture(rock_nrm, uv_z).rgb * blend.z;
	vec3 n_detail = texture(rock_nrm, uv_x * 3.4).rgb * blend.x + texture(rock_nrm, uv_y * 3.4).rgb * blend.y + texture(rock_nrm, uv_z * 3.4).rgb * blend.z;
	NORMAL_MAP = normalize(mix(n_macro, n_detail, 0.36));
	NORMAL_MAP_DEPTH = 1.12;
	float rgh = texture(rock_rgh, uv_x).r * blend.x + texture(rock_rgh, uv_y).r * blend.y + texture(rock_rgh, uv_z).r * blend.z;
	ROUGHNESS = mix(clamp(rgh, 0.58, 0.95), 0.92, moss_mask);
	SPECULAR = mix(0.14, 0.05, moss_mask);
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("rock_tex", load("res://assets/slice/ink_jiangnan/granite_rock_albedo.png"))
		sm.set_shader_parameter("rock_nrm", load("res://assets/slice/ink_jiangnan/granite_rock_normal.png"))
		sm.set_shader_parameter("rock_rgh", load("res://assets/slice/ink_jiangnan/granite_rock_rough.png"))
		mat = sm
	elif kind == "undergrowth":
		# Lush sunlit spring meadow grass tufts, ferns & creek reeds!
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_disabled, specular_disabled;
void fragment() {
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 natural = mix(vec3(lum), COLOR.rgb, 0.52);
	ALBEDO = natural * vec3(0.70, 0.88, 0.52);
	ROUGHNESS = 0.94;
	SPECULAR = 0.0;
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = sh
		mat = sm
	ink_arch_mat_cache[kind] = mat
	return mat

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
			if "UndergrowthVCol" in mname:
				mesh.surface_set_material(s, _get_ink_arch_material("undergrowth"))
				continue
			if ("Plaster" in mname or "WhiteWall" in mname) and smat.albedo_texture == null:
				mesh.surface_set_material(s, _get_ink_arch_material("plaster"))
				continue
			if "Tile" in mname and smat.albedo_texture == null:
				mesh.surface_set_material(s, _get_ink_arch_material("tile"))
				continue
			if ("Bluestone" in mname or "Granite" in mname or "Flagstone" in mname or "ShrineStone" in mname or "StonePlinth" in mname or "BridgeMoss" in mname or "PoemPlinth" in mname or "PoemCarvedStone" in mname) and smat.albedo_texture == null:
				mesh.surface_set_material(s, _get_ink_arch_material("bluestone"))
				continue
		var bmat: BaseMaterial3D = null
		if mat is BaseMaterial3D:
			bmat = mat.duplicate() as BaseMaterial3D
		elif has_vcol:
			bmat = StandardMaterial3D.new()
			bmat.roughness = 0.88
		if bmat != null:
			if has_vcol and bmat.albedo_texture == null:
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
	var chunk_size := 46.0
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
	# Keep scenic sightlines unobstructed at South Camp Fence Overlook, Creek Outflow, Wangdao Pavilion, Tea Pavilion & Cloud Arena
	if x > -14.0 and x < 8.0 and z > 28.0 and z < 52.0:
		return true
	if x > 20.0 and x < 31.0 and z > 28.0 and z < 58.0:
		return true
	var wd: Vector3 = game.Layout.WANGDAO_PAVILION
	if x > wd.x - 16.0 and x < wd.x + 18.0 and z > wd.z - 6.0 and z < wd.z + 30.0:
		return true
	if game.Layout.is_in_cloud_arena(x, z, 3.0):
		return true
	return false

func _surface_height_any(x: float, z: float) -> float:
	if x >= game.Layout.MIN_X and x <= game.Layout.MAX_X and z >= game.Layout.MIN_Z and z <= game.Layout.MAX_Z:
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

	var fmin_x := float(game.Layout.FENCE_MIN_X) + 1.5
	var fmax_x := float(game.Layout.FENCE_MAX_X) - 1.5
	var fmin_z := float(game.Layout.FENCE_MIN_Z) + 2.5
	var fmax_z := float(game.Layout.FENCE_MAX_Z) - 4.0

	# Authentic segmented Moso bamboo groves across the 3x expanded Great Yanshan slopes (Vega 8 friendly density!)
	for i in 260:
		var x := rng.randf_range(fmin_x, fmax_x)
		var z := rng.randf_range(fmin_z, fmax_z)
		if game.Layout.clear_for_route(x, z, 0.75) or _is_vista_corridor(x, z):
			continue
		if i % 5 == 0 and not game.Layout.clear_for_route(x, z, 2.2):
			var cy := _surface_height_any(x, z) - 0.04
			var csc := rng.randf_range(0.86, 1.20)
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
				var bsc := rng.randf_range(0.84, 1.26)
				var basis := Basis(Vector3.UP, rng.randf_range(0, TAU))
				basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.045, 0.045)).scaled(Vector3(bsc * 0.96, bsc, bsc * 0.96))
				culm_tx.append(Transform3D(basis, Vector3(bx, by, bz)))
				if game.Layout.road_distance(bx, bz) < 15.0:
					var shape := CylinderShape3D.new()
					shape.radius = 0.13
					shape.height = 6.8 * bsc
					var body = game.Props.shape_body(self, shape, Vector3(bx, by + 3.4 * bsc, bz))
					body.add_to_group("solid_props")

	_batch_direct(culm_mesh, culm_tx, false, "MosoBambooCulms", 120.0)
	_batch_direct(clump_mesh, clump_tx, false, "MosoBambooClumps", 112.0)
	_trees()

	for i in 48:
		var x := rng.randf_range(fmin_x + 2.0, fmax_x - 2.0)
		var z := rng.randf_range(fmin_z + 2.0, fmax_z - 2.0)
		if not game.Layout.clear_for_route(x, z, 1.8) and not _is_vista_corridor(x, z):
			rock(Vector3(x, 0, z), rng.randf_range(1.1, 3.6), i)
	for info in [
		[Vector3(-34.0, 0, -28.0), 2.4], [Vector3(-78.0, 0, -34.0), 3.1],
		[Vector3(8.0, 0, -54.0), 3.0], [Vector3(-18.0, 0, -112.0), 3.6],
		[Vector3(38.0, 0, -172.0), 4.0], [Vector3(-42.0, 0, -178.0), 3.8]
	]:
		rock(info[0], info[1], int(absf(info[0].z)))
	var backdrop_begin := Time.get_ticks_msec()
	_backdrop()
	game.startup_ms["backdrop"] = Time.get_ticks_msec() - backdrop_begin

func _trees():
	var v061_path := "res://assets/slice/v061_nature_wildlife.glb"
	var camphor_mesh := _extract_mesh(v061_path, "tree_camphor")
	var willow_mesh := _extract_mesh(v061_path, "tree_willow")
	var maple_mesh := _extract_mesh(v061_path, "tree_maple_tallow")

	var camphor_tx: Array = []
	var willow_tx: Array = []
	var maple_tx: Array = []

	# 1) Graceful Weeping Willows ("垂柳") lining the 240m winding mountain creek & South outflow
	var creek_willow_specs := [
		[-188.0, 4.4], [-174.0, -4.3], [-152.0, 4.4], [-136.0, -4.2],
		[-114.0, 4.3], [-96.0, -4.2], [-84.0, 4.4], [-64.0, -4.2],
		[-46.0, 4.4], [-16.0, -4.3], [-4.0, 4.3], [6.5, -4.2],
		[24.5, 4.5], [32.5, -4.6], [38.0, 4.8], [45.0, -5.0]
	]
	for idx in creek_willow_specs.size():
		var wz: float = creek_willow_specs[idx][0]
		var woff: float = creek_willow_specs[idx][1]
		var wx := _outer_stream_x(wz) + woff
		if (game.Layout.road_distance(wx, wz, 4.4) < 4.4 or _is_near_bridge(wz, 4.5)) and wz <= 38.0:
			continue
		if game.Layout.is_in_cloud_arena(wx, wz, 2.0):
			continue
		var wy := _surface_height_any(wx, wz) - 0.08
		var wsc := 0.98 + float(idx % 4) * 0.11
		var wyaw := float(idx) * 1.85
		willow_tx.append(Transform3D(Basis(Vector3.UP, wyaw).scaled(Vector3.ONE * wsc), Vector3(wx, wy, wz)))
		if wz >= game.Layout.FENCE_MIN_Z and wz <= game.Layout.FENCE_MAX_Z and absf(wx) <= float(game.Layout.FENCE_MAX_X) - 1.0:
			var tshape := CylinderShape3D.new()
			tshape.radius = 0.28 * wsc
			tshape.height = 4.2 * wsc
			game.Props.shape_body(self, tshape, Vector3(wx, wy + 2.1 * wsc, wz))
			tree_trunks.append(Vector3(wx, wy + 0.08, wz))
			tree_trunk_radii.append(0.28 * wsc)

	# 2) Curated & perimeter Jiangnan Broadleaf Groves (Camphor "香樟" & Maple/Tallow "枫香/乌桕")
	var curated_trees := [
		Vector3(-24, 0, 2), Vector3(36, 0, -6), Vector3(-44, 0, -28), Vector3(38, 0, -46),
		Vector3(-52, 0, -62), Vector3(44, 0, -84), Vector3(-48, 0, -104), Vector3(46, 0, -112),
		Vector3(-34, 0, -130), Vector3(68, 0, -148), Vector3(-28, 0, -186), Vector3(54, 0, -10),
		Vector3(-74, 0, 26), Vector3(-48, 0, 30), Vector3(76, 0, 16), Vector3(78, 0, -16),
		Vector3(78, 0, -52), Vector3(76, 0, -96), Vector3(78, 0, -142), Vector3(72, 0, -182),
		Vector3(-78, 0, 8), Vector3(-80, 0, -36), Vector3(-84, 0, -76), Vector3(-84, 0, -120),
		Vector3(-78, 0, -158), Vector3(-74, 0, -190), Vector3(-34, 0, -194), Vector3(42, 0, -192),
		Vector3(-32, 0, -4), Vector3(-56, 0, -34), Vector3(56, 0, -52), Vector3(56, 0, -114),
		Vector3(-54, 0, -124), Vector3(66, 0, -22), Vector3(-60, 0, -88), Vector3(68, 0, -162),
		Vector3(-72, 0, -4), Vector3(-82, 0, -54), Vector3(-82, 0, -140), Vector3(-82, 0, -176)
	]
	# Scatter natural outer-collar & mid-slope woodland trees across 180x240m without cluttering combat sightlines
	for k in 86:
		var sx := rng.randf_range(-94.0, 94.0)
		var sz := rng.randf_range(-204.0, 36.0)
		curated_trees.append(Vector3(sx, 0.0, sz))

	var fmin_x := float(game.Layout.FENCE_MIN_X)
	var fmax_x := float(game.Layout.FENCE_MAX_X)
	var fmin_z := float(game.Layout.FENCE_MIN_Z)
	var fmax_z := float(game.Layout.FENCE_MAX_Z)
	for idx in curated_trees.size():
		var raw: Vector3 = curated_trees[idx]
		if _is_vista_corridor(raw.x, raw.z):
			continue
		if raw.x >= fmin_x and raw.x <= fmax_x and raw.z >= fmin_z and raw.z <= fmax_z:
			if game.Layout.clear_for_route(raw.x, raw.z, 2.0):
				continue
		elif game.Layout.stream_distance(raw.x, raw.z) < 4.5:
			continue
		var ty := _surface_height_any(raw.x, raw.z) - 0.10
		var tsc := rng.randf_range(0.92, 1.32)
		var tyaw := float(idx) * 2.07 + rng.randf_range(-0.25, 0.25)
		var xform := Transform3D(Basis(Vector3.UP, tyaw).scaled(Vector3.ONE * tsc), Vector3(raw.x, ty, raw.z))
		if idx % 5 == 1 or idx % 5 == 3:
			maple_tx.append(xform)
		else:
			camphor_tx.append(xform)
		if raw.x >= fmin_x + 0.5 and raw.x <= fmax_x - 0.5 and raw.z >= fmin_z + 0.5 and raw.z <= fmax_z - 0.5:
			var shape := CylinderShape3D.new()
			shape.radius = 0.30 * tsc
			shape.height = 4.6 * tsc
			game.Props.shape_body(self, shape, Vector3(raw.x, ty + 2.3 * tsc, raw.z))
			tree_trunks.append(Vector3(raw.x, ty + 0.10, raw.z))
			tree_trunk_radii.append(0.30 * tsc)
	var shrine_p: Vector3 = game.Layout.on_ground(game.Layout.CAMPHOR_SHRINE)
	tree_trunks.append(shrine_p)
	tree_trunk_radii.append(0.58)

	_batch_direct(camphor_mesh, camphor_tx, false, "MountainCamphorTrees", 165.0)
	_batch_direct(willow_mesh, willow_tx, false, "MountainWillowTrees", 165.0)
	_batch_direct(maple_mesh, maple_tx, false, "MountainMapleTrees", 165.0)
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
	return 8.5 + 18.0 * exp(-pow((x + 88.0) / 56.0, 2.0) - pow((z + 275.0) / 55.0, 2.0)) + 25.0 * exp(-pow((x - 62.0) / 72.0, 2.0) - pow((z + 305.0) / 68.0, 2.0)) + 5.5 * sin(x * 0.022 + z * 0.016)

func _outer_stream_x(z: float) -> float:
	var max_z := float(game.Layout.MAX_Z)
	if z <= max_z:
		return float(game.Layout.stream_center_x(z))
	var dz := z - max_z
	return float(game.Layout.stream_center_x(max_z)) + (1.0 - exp(-dz * 0.055)) * sin(dz * 0.048) * 10.5

func _outer_stream_width_scale(z: float) -> float:
	var max_z := float(game.Layout.MAX_Z)
	if z <= max_z:
		return 1.0
	return 1.0 + 0.70 * smoothstep(max_z, max_z + 125.0, z)

func _outer_foothill_weight(x: float, z: float) -> float:
	var center_dist := Vector2(x, z + 80.0).length()
	var south_plain := exp(-pow((x - 24.0) / 86.0, 2.0)) * smoothstep(105.0, 250.0, z)
	return smoothstep(235.0, 345.0, center_dist) * (1.0 - 0.65 * south_plain)

func _outer_valley_y(x: float, z: float) -> float:
	var min_x := float(game.Layout.MIN_X)
	var max_x := float(game.Layout.MAX_X)
	var min_z := float(game.Layout.MIN_Z)
	var max_z := float(game.Layout.MAX_Z)
	var ix := clampf(x, min_x, max_x)
	var iz := clampf(z, min_z, max_z)
	var dx := maxf(0.0, maxf(min_x - x, x - max_x))
	var dz := maxf(0.0, maxf(min_z - z, z - max_z))
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.001:
		return _ground_vis_y(ix, iz)
	var north_w := smoothstep(min_z + 6.0, min_z - 36.0, z) * (1.0 - smoothstep(82.0, 138.0, absf(x)))
	var north_h := _hill_height(x, z)
	var raw_terrace := -11.4 + 1.6 * sin(x * 0.022 + z * 0.015) + 0.9 * cos(z * 0.024)
	var quantized := floorf((raw_terrace + 13.0) / 2.2) * 2.2 - 13.0
	var valley_floor := lerpf(raw_terrace, quantized, 0.56)
	var down_t := smoothstep(0.0, 36.0, d)
	var rural_y := valley_floor
	if down_t < 1.0:
		rural_y = lerpf(game.Layout.land_edge_height(ix, iz), valley_floor, down_t)
	rural_y = lerpf(rural_y, north_h, north_w * smoothstep(8.0, 44.0, d))
	var center_dist := Vector2(x, z + 80.0).length()
	var foothill_w := _outer_foothill_weight(x, z)
	var foothill_h := 3.0 + 9.0 * smoothstep(245.0, 360.0, center_dist) + 3.5 * sin(x * 0.024 - z * 0.019) + 2.4 * cos(x * 0.015 + z * 0.028)
	var land_y := lerpf(rural_y, foothill_h, foothill_w)
	if z >= max_z and z <= max_z + 150.0:
		var sx := _outer_stream_x(z)
		var w_sc := _outer_stream_width_scale(z)
		var local_off := (x - sx) / w_sc
		if absf(local_off) < 5.2:
			var edge_sx := float(game.Layout.stream_center_x(max_z))
			var equiv_x := edge_sx + local_off
			var delta_edge := _ground_vis_y(equiv_x, max_z) - float(game.Layout.land_edge_height(equiv_x, max_z))
			var chan_fade := 1.0 - smoothstep(max_z + 120.0, max_z + 150.0, z)
			land_y += delta_edge * chan_fade
	return land_y

func _stream_water_y_any(z: float) -> float:
	var max_z := float(game.Layout.MAX_Z)
	if z <= max_z:
		return float(game.Layout.stream_water_y(z))
	var sx := _outer_stream_x(z)
	return _outer_valley_y(sx, z) + lerpf(0.575, 0.18, smoothstep(max_z, max_z + 135.0, z))

func _outer_valley_normal(x: float, z: float) -> Vector3:
	var dx := maxf(0.0, maxf(float(game.Layout.MIN_X) - x, x - float(game.Layout.MAX_X)))
	var dz := maxf(0.0, maxf(float(game.Layout.MIN_Z) - z, z - float(game.Layout.MAX_Z)))
	var eps := 1.0 if (dx < 24.0 and dz < 48.0) else 4.0
	return Vector3(
		_outer_valley_y(x - eps, z) - _outer_valley_y(x + eps, z),
		2.0 * eps,
		_outer_valley_y(x, z - eps) - _outer_valley_y(x, z + eps)
	).normalized()

func _valley_raw_vert(x: float, z: float) -> Array:
	var y := _outer_valley_y(x, z)
	var n := _outer_valley_normal(x, z)
	var dx := maxf(0.0, maxf(float(game.Layout.MIN_X) - x, x - float(game.Layout.MAX_X)))
	var dz := maxf(0.0, maxf(float(game.Layout.MIN_Z) - z, z - float(game.Layout.MAX_Z)))
	var d := sqrt(dx * dx + dz * dz)
	var fh := _outer_foothill_weight(x, z)
	var paddy_w := smoothstep(22.0, 46.0, d) * (1.0 - smoothstep(-6.5, -2.0, y))
	var slope_flat := smoothstep(0.86, 0.96, n.y)
	return [Vector3(x, y, z), n, Vector2(x, z) * 0.015, Color(paddy_w * slope_flat, clampf(d / 260.0, 0.0, 1.0), fh)]

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

func _append_valley_ring(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, inner_box: Array, outer_box: Array, step: int, next_step: int):
	var ix0: int = inner_box[0]
	var ix1: int = inner_box[1]
	var iz0: int = inner_box[2]
	var iz1: int = inner_box[3]
	var ring_vertices := {}
	for z in range(int(outer_box[2]), int(outer_box[3]), step):
		for x in range(int(outer_box[0]), int(outer_box[1]), step):
			if x >= ix0 and x < ix1 and z >= iz0 and z < iz1:
				continue
			var cell := [Vector2i(x, z), Vector2i(x, z + step), Vector2i(x + step, z), Vector2i(x + step, z + step)]
			for corner: Vector2i in cell:
				if ring_vertices.has(corner):
					continue
				var vd := _valley_stitched_vert(corner.x, corner.y, outer_box, next_step)
				ring_vertices[corner] = vertices.size()
				vertices.append(vd[0])
				normals.append(vd[1])
				uvs.append(vd[2])
				colors.append(vd[3])
			for k in [0, 2, 1, 2, 3, 1]:
				indices.append(ring_vertices[cell[k]])

func _backdrop():
	# 1) Watertight 3-ring terraced rural rice-paddy valley seamlessly stitched to ContinuousGround [-100..100] x [-210..50]
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	var indices := PackedInt32Array()
	var box0 := [-100, 100, -210, 50]
	var box1 := [-104, 104, -214, 58]
	var box2 := [-144, 144, -248, 120]
	var box3 := [-360, 360, -440, 320]
	_append_valley_ring(vertices, normals, uvs, colors, indices, box0, box1, 1, 2)
	_append_valley_ring(vertices, normals, uvs, colors, indices, box1, box2, 2, 8)
	_append_valley_ring(vertices, normals, uvs, colors, indices, box2, box3, 8, 1)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
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
 vec2 soil_uv = wpos.xz * 0.24;
 vec3 s_tex = texture(soil, soil_uv).rgb;
 float lum = dot(s_tex, vec3(0.299, 0.587, 0.114));
 float patch_n = 0.5 + 0.5 * sin(wpos.x * 0.13 + sin(wpos.z * 0.11) * 2.2);
 vec3 near_moss = mix(vec3(0.22, 0.34, 0.21), vec3(0.34, 0.46, 0.23), patch_n) * mix(0.84, 1.14, clamp(lum * 1.45, 0.0, 1.0));

 // Taiping Village cloud-wrapped teal-emerald foothills ('青黛叠嶂 · 云海缠腰')
 float crest_lift = clamp((wpos.y + 4.0) / 22.0, 0.0, 1.0);
 vec3 valley_mist = vec3(0.85, 0.90, 0.93);
 vec3 ink_ridge = mix(vec3(0.32, 0.52, 0.56), vec3(0.22, 0.42, 0.44), crest_lift);
 vec3 far_hill_col = mix(valley_mist, ink_ridge, smoothstep(0.05, 0.85, crest_lift));
 vec3 slope_col = mix(near_moss, far_hill_col, smoothstep(14.0, 72.0, edge_d));

 vec3 p_tex = texture(paddy_tex, UV).rgb;
 float macro_dapple = 0.94 + 0.10 * sin(wpos.x * 0.022 + wpos.z * 0.018);
 vec3 paddy_col = p_tex * macro_dapple * 1.02;

 float paddy_t = clamp(COLOR.r, 0.0, 1.0) * (1.0 - foothill_f * 0.96);
 ALBEDO = mix(slope_col, paddy_col, paddy_t);
 NORMAL_MAP = texture(soil_normal, soil_uv).rgb;
 NORMAL_MAP_DEPTH = mix(0.28, 0.06, smoothstep(10.0, 75.0, edge_d));
 ROUGHNESS = mix(0.94, 0.38, paddy_t);
 SPECULAR = mix(0.03, 0.22, paddy_t);
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

	# 2) Rural Jiangnan cottages sheltered by authentic Weeping Willows, Camphors, Southern Maples & Bamboo Groves
	var village_spots := [
		Vector3(-44, 0, 118), Vector3(-28, 0, 126), Vector3(-52, 0, 138), Vector3(-18, 0, 146),
		Vector3(12, 0, 124), Vector3(32, 0, 132), Vector3(48, 0, 118), Vector3(58, 0, 140),
		Vector3(68, 0, 158), Vector3(22, 0, 166), Vector3(-6, 0, 174), Vector3(-34, 0, 178),
		Vector3(136, 0, -96), Vector3(148, 0, -72), Vector3(158, 0, -44), Vector3(144, 0, -16),
		Vector3(164, 0, 12), Vector3(174, 0, 38), Vector3(134, 0, 44),
		Vector3(-136, 0, -78), Vector3(-150, 0, -44), Vector3(-162, 0, -10), Vector3(-144, 0, 34), Vector3(-168, 0, 62)
	]
	var house_mesh := _extract_mesh("res://assets/slice/v055_eco_assets.glb", "horizon_farmhouse")
	if house_mesh != null:
		var house_tx: Array = []
		for j in village_spots.size():
			var hp: Vector3 = village_spots[j]
			hp.y = _outer_valley_y(hp.x, hp.z) - 0.14
			var hyaw := float(j % 4) * (PI * 0.5) + 0.18
			house_tx.append(Transform3D(Basis(Vector3.UP, hyaw).scaled(Vector3.ONE * 1.15), hp))
		_batch_direct(house_mesh, house_tx, false, "VillageFarmhouses", 280.0)

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
		var rz := 54.0 + float(r_idx) * 8.2
		var r_side := -1.0 if r_idx % 2 == 0 else 1.0
		var rx := _outer_stream_x(rz) + r_side * (5.2 + float(r_idx % 3) * 1.3)
		var ry := _outer_valley_y(rx, rz) - 0.12
		var rsc := 1.10 + float(r_idx % 4) * 0.12
		v_willow_tx.append(Transform3D(Basis(Vector3.UP, float(r_idx) * 1.63).scaled(Vector3.ONE * rsc), Vector3(rx, ry, rz)))

	# Authentic Jiangnan village groves beside white-wall black-tile cottages
	for j in village_spots.size():
		var hp: Vector3 = village_spots[j]
		for t_i in 3:
			var ang := float(j * 3 + t_i) * 2.09 + 0.35
			var rad := 6.8 + float(t_i) * 4.0
			var tx_p := hp.x + cos(ang) * rad
			var tz_p := hp.z + sin(ang) * rad
			if absf(tx_p - _outer_stream_x(tz_p)) < 4.2 and tz_p > 48.0:
				tx_p += 5.5
			var ty_p := _outer_valley_y(tx_p, tz_p) - 0.12
			var ts := 1.05 + float((j + t_i) % 4) * 0.12
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

	# Outer foothill broadleaf stands (lightweight silhouettes at 200m+ horizon)
	for k in 28:
		var angle := float(k) * 0.89
		var rad := 205.0 + float(k % 6) * 16.0
		var vx := sin(angle) * rad
		var vz := -80.0 + cos(angle) * (rad * 1.12)
		if vz < -205.0 and absf(vx) < 105.0:
			continue
		var vy := _outer_valley_y(vx, vz) - 0.16
		var ts := 1.24 + float(k % 4) * 0.16
		var xform := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * ts), Vector3(vx, vy, vz))
		if k % 3 == 0:
			v_maple_tx.append(xform)
		else:
			v_camphor_tx.append(xform)

	_batch_direct(v_willow, v_willow_tx, false, "VillageWillows", 265.0)
	_batch_direct(v_camphor, v_camphor_tx, false, "VillageCamphors", 265.0)
	_batch_direct(v_maple, v_maple_tx, false, "VillageMaples", 265.0)
	_batch_direct(v_bamboo, v_bamboo_tx, false, "VillageBamboo", 225.0)

	# 3) v0.8.6 Multi-Layer Cloud-Wreathed Distant Mountain Panorama (AI Qinglü Peaks + 3D Peak Ring + Drifting Cloud-Sea Mist Belts!)
	var make_pano_ring := func(radius: float, y_bottom: float, y_top: float, segs: int = 72) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in segs:
			var a0 := float(i) * TAU / float(segs)
			var a1 := float(i + 1) * TAU / float(segs)
			var u0 := float(i) / float(segs)
			var u1 := float(i + 1) / float(segs)
			var x0 := cos(a0) * radius
			var z0 := sin(a0) * radius
			var x1 := cos(a1) * radius
			var z1 := sin(a1) * radius
			var p_tl := Vector3(x0, y_top, z0)
			var p_tr := Vector3(x1, y_top, z1)
			var p_bl := Vector3(x0, y_bottom, z0)
			var p_br := Vector3(x1, y_bottom, z1)
			var n0 := Vector3(-cos(a0), 0.0, -sin(a0))
			var n1 := Vector3(-cos(a1), 0.0, -sin(a1))
			# Inside-facing triangles with exact UV.y = 0.0 (top) -> 1.0 (bottom) (NO Godot CylinderMesh 0..0.5 cap-atlas crop!)
			st.set_normal(n0); st.set_uv(Vector2(u0, 0.0)); st.add_vertex(p_tl)
			st.set_normal(n0); st.set_uv(Vector2(u0, 1.0)); st.add_vertex(p_bl)
			st.set_normal(n1); st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p_br)
			st.set_normal(n0); st.set_uv(Vector2(u0, 0.0)); st.add_vertex(p_tl)
			st.set_normal(n1); st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p_br)
			st.set_normal(n1); st.set_uv(Vector2(u1, 0.0)); st.add_vertex(p_tr)
		return st.commit()

	if ResourceLoader.exists("res://assets/slice/horizon_mountains.png"):
		var sky_ring := MeshInstance3D.new()
		sky_ring.name = "HorizonMountainsSkirt"
		sky_ring.mesh = make_pano_ring.call(362.0, -34.0, 138.0, 72)
		sky_ring.position = Vector3(0.0, 0.0, -80.0)
		var ring_shader := Shader.new()
		ring_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, fog_disabled;
uniform sampler2D pano : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.42, 0.73, -0.54);
varying vec3 wpos;
void vertex(){
 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
 if (UV.y < 0.03) {
  discard;
 }
 vec2 uv = vec2(UV.x, clamp(UV.y, 0.02, 0.985));
 vec4 t = texture(pano, uv);
 float top_guard = smoothstep(0.03, 0.09, UV.y);
 float a = smoothstep(0.05, 0.28, t.a) * top_guard;
 if (a < 0.02) {
  discard;
 }
 float bottom_mist = smoothstep(0.82, 0.99, UV.y);
 float peak_sun = (1.0 - smoothstep(0.28, 0.70, UV.y)) * max(0.0, dot(normalize(vec3(wpos.x, 0.0, wpos.z + 80.0)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z))));
 vec3 mist_white = vec3(0.84, 0.91, 0.95);
 vec3 ridge_col = t.rgb + vec3(0.05, 0.045, 0.02) * peak_sun;
 ridge_col = mix(ridge_col, mist_white, bottom_mist * 0.56);
 ALBEDO = ridge_col;
 ALPHA = a;
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

	# 3B) 3D Sculpted Mid-Distance Foothill Ridge Ring (stays gracefully below soaring distant Qinglu peaks for true parallax!)
	var peaks_mesh := _extract_mesh("res://assets/slice/v086_architecture.glb", "distant_peaks_ring")
	if peaks_mesh != null:
		var peaks_mi := MeshInstance3D.new()
		peaks_mi.name = "DistantPeaksRing3D"
		peaks_mi.mesh = peaks_mesh
		peaks_mi.position = Vector3(0.0, -7.5, -80.0)
		peaks_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var peak_sh := Shader.new()
		peak_sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
varying float vy;
varying vec3 vnorm;
void vertex(){
 vy = VERTEX.y;
 vnorm = normalize(NORMAL);
}
void fragment(){
 float h = clamp((vy + 14.0) / 48.0, 0.0, 1.0);
 float lit = clamp(dot(vnorm, normalize(vec3(0.45, 0.72, -0.52))) * 0.5 + 0.5, 0.0, 1.0);
 vec3 valley_mist = vec3(0.79, 0.87, 0.89);
 vec3 mid_qing = vec3(0.24, 0.44, 0.45);
 vec3 sun_ochre = vec3(0.42, 0.54, 0.40);
 vec3 ridge_col = mix(mid_qing, sun_ochre, lit * 0.42);
 vec3 col = mix(valley_mist, ridge_col, smoothstep(0.10, 0.58, h));
 ALBEDO = col;
}
"""
		var p_smat := ShaderMaterial.new()
		p_smat.shader = peak_sh
		peaks_mi.material_override = p_smat
		add_child(peaks_mi)

	# 3C) Two Counter-Drifting Ink-Wash Cloud-Sea Mist Belts wrapping gently around the lower mountain waists!
	if ResourceLoader.exists("res://assets/slice/horizon_cloud_ribbon.png"):
		var cloud_tex: Texture2D = load("res://assets/slice/horizon_cloud_ribbon.png")
		var cloud_specs := [
			["MistyCloudSeaOuter", 336.0, -10.0, 48.0, 0.0040, 0.48],
			["MistyCloudSeaInner", 288.0, -14.0, 32.0, -0.0056, 0.36]
		]
		for cs in cloud_specs:
			var c_mi := MeshInstance3D.new()
			c_mi.name = str(cs[0])
			c_mi.mesh = make_pano_ring.call(float(cs[1]), float(cs[2]), float(cs[3]), 64)
			c_mi.position = Vector3(0.0, 0.0, -80.0)
			c_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var c_sh := Shader.new()
			c_sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;
uniform sampler2D cloud_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float drift_speed = 0.0045;
uniform float opacity_scale = 0.44;
void fragment(){
 if (UV.y < 0.04 || UV.y > 0.96) {
  discard;
 }
 vec2 uv = vec2(UV.x * 3.0 + TIME * drift_speed, clamp(UV.y, 0.04, 0.96));
 vec4 c = texture(cloud_tex, uv);
 float v_fade = smoothstep(0.04, 0.30, UV.y) * (1.0 - smoothstep(0.68, 0.96, UV.y));
 ALBEDO = mix(c.rgb, vec3(0.93, 0.97, 0.99), 0.38);
 ALPHA = c.a * v_fade * opacity_scale;
}
"""
			var cmat := ShaderMaterial.new()
			cmat.shader = c_sh
			cmat.set_shader_parameter("cloud_tex", cloud_tex)
			cmat.set_shader_parameter("drift_speed", float(cs[4]))
			cmat.set_shader_parameter("opacity_scale", float(cs[5]))
			c_mi.material_override = cmat
			add_child(c_mi)

func rock(at: Vector3, height: float, index: int):
	var path = "res://assets/nature/rock_largeA.glb" if rock_paths.is_empty() else rock_paths[index % rock_paths.size()]
	var grounded_y := _min_surface_height_any(at.x, at.z, height * 0.72) - (0.38 + height * 0.09)
	var rnode = game._model(self, path, Vector3(at.x, grounded_y, at.z), height, rng.randf_range(0, TAU), "convex")
	var rock_mat := _get_ink_arch_material("rock")
	for mi in rnode.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = rock_mat
	return rnode

func signpost(at: Vector3, text: String, yaw: float = 0.0, y_override: float = NAN, node_name: String = "") -> Node3D:
	var base_y: float = y_override if not is_nan(y_override) else (game.Layout.min_ground_height(at.x, at.z, 0.35) - 0.05)
	var root = Node3D.new()
	if node_name != "":
		root.name = node_name
	root.position = Vector3(at.x, base_y, at.z)
	root.rotation.y = yaw
	add_child(root)
	var frame_vis := _instantiate_v086_mesh("jiangnan_signboard_frame")
	if frame_vis != null:
		root.add_child(frame_vis)
		var post_shp := BoxShape3D.new()
		post_shp.size = Vector3(2.40, 2.35, 0.26)
		game.Props.shape_body(root, post_shp, Vector3(0, 1.18, 0)).add_to_group("solid_props")
	else:
		var post = game._mesh_box(root, Vector3(0, 0.98, 0), Vector3(0.15, 2.0, 0.15), Color.WHITE, true)
		post.material_override = wood_post_mat
		var board = game._mesh_box(root, Vector3(0, 1.86, 0), Vector3(2.55, 0.96, 0.14), Color.WHITE, true)
		board.material_override = roof_slate_mat
		var trim = game._mesh_box(root, Vector3(0, 2.36, 0), Vector3(2.68, 0.08, 0.20), Color.WHITE)
		trim.material_override = wood_plank_mat
	var label = game._label3d(root, text, Vector3(0, 1.86, 0.12), 30, Color("f0edd2"))
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.pixel_size = 0.0066
	label.visibility_range_end = 34.0
	return root

var container_yard: Dictionary = {}
var bamboo_shelter: Dictionary = {}
var watchtower_pos: Vector3 = Vector3.ZERO
var wangdao_deck_pos: Vector3 = Vector3.ZERO

func shelter(at: Vector3, title: String, with_parkour := false) -> Dictionary:
	var base_y = game.Layout.min_ground_height(at.x, at.z, 2.4) - 0.08
	var root = Node3D.new()
	root.position = Vector3(at.x, base_y, at.z)
	add_child(root)
	var sh_vis := _instantiate_v086_mesh("bamboo_shelter_jiangnan")
	if sh_vis != null:
		root.add_child(sh_vis)
		# Keep exact Route B physics colliders for posts, walkable roof deck (top y=3.485m), and interior table!
		for x in [-2.5, 2.5]:
			for z in [-1.8, 1.8]:
				game._add_box_collider(root, Vector3(x, 1.72, z), Vector3(0.20, 3.55, 0.20))
		for z in [-1.5, -0.6, 0.3, 1.2]:
			game._add_box_collider(root, Vector3(0, 3.42, z), Vector3(5.8, 0.13, 0.94))
		game._add_box_collider(root, Vector3(0, 1.02, -1.35), Vector3(3.5, 0.12, 0.82))
		for x in [-1.5, 1.5]:
			game._add_box_collider(root, Vector3(x, 0.50, -1.35), Vector3(0.16, 1.05, 0.62))
	else:
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
	var l = game._label3d(root, title, Vector3(0, 2.68, 2.02), 32, Color("f0e8c4"))
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
	# A · 山脚安全营地 centered around SPAWN (0, 0, 14.0)
	TacticalProps.build_command_tent(self, game, Vector3(10.2, 0, 19.8), 1.02)
	TacticalProps.build_fuel_drum(self, game, Vector3(7.6, 0, 22.2), true)
	TacticalProps.build_fuel_drum(self, game, Vector3(6.9, 0, 22.7), false)
	if ResourceLoader.exists("res://assets/slice/crate.glb"):
		game._model(self, "res://assets/slice/crate.glb", Vector3(8.5, 0, 22.8), 0.56, 0.16, "convex")
		game._model(self, "res://assets/slice/crate.glb", Vector3(8.5, 0.55, 22.8), 0.42, -0.12, "convex")
	TacticalProps.build_armory_workbench(self, game, Vector3(11.6, 0, 16.0), 1.02)
	var low_rock_path = "res://assets/slice/rock_2.glb" if ResourceLoader.exists("res://assets/slice/rock_2.glb") else "res://assets/nature/rock_largeA.glb"
	var low_rock_node = game._model(self, low_rock_path, Vector3(-6.0, 0, 19.5), 0.55, 0, "convex")
	low_rock_node.set_meta("kind", "low_rock")
	var lr_mat := _get_ink_arch_material("rock")
	for mi in low_rock_node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = lr_mat
	watchtower_pos = game.Layout.on_ground(game.Layout.WATCHTOWER)
	game._build_tower(watchtower_pos)
	bamboo_shelter = shelter(game.Layout.SHELTER_BAMBOO, "云顶竹林补给棚", true)
	shelter(game.Layout.MATH, "山路巡护站", false)
	# Route A: West Ridge ISO Cargo Container Parkour Yard
	container_yard = TacticalProps.build_cargo_container_yard(self, game, game.Layout.on_ground(game.Layout.PARKOUR_CONTAINERS))
	# Cave Grotto housing Tier-3 Airdrop Vault
	TacticalProps.build_cave_grotto(self, game, game.Layout.on_ground(game.Layout.CAVE_GROTTO))
	# v0.6.0 Jiangnan Rural Hill Heritage Landmarks & Wangdao Overlook Terrace
	_build_jiangnan_heritage()
	# v0.6.2 Isolated West Ravine Lost Bamboo-Stone Labyrinth ("迷踪竹石阵") & Yanxia Ancient Cavern ("烟霞古洞")
	_build_bamboo_maze_and_yanxia_cave()
	# v0.8.5 New Great Yanshan Landmarks: 38m Cloud-Top Martial Arena, East Tea-Hill Pavilion & Mountain Inscribed Stele
	_build_v085_landmarks()
	# v0.8.6 Jiangnan Micro-Scenery: Stone Lanterns, Mountain Arch Gates, Terraced Tea Hedges, Mossy Boulders & Trail Benches
	_build_v086_scenery()
	# Deep Cache landmarks: Twin-Rock Cleft, East Overlook Boulder Alcove, SE Bamboo Crag
	rock(game.Layout.CLEFT_CACHE + Vector3(-2.6, 0, -0.4), 2.8, 1)
	rock(game.Layout.CLEFT_CACHE + Vector3(2.6, 0, -0.2), 2.6, 2)
	rock(game.Layout.EAST_OVERLOOK + Vector3(5.4, 0, -2.2), 2.6, 0)
	rock(game.Layout.SE_BAMBOO_CACHE + Vector3(2.8, 0, -1.5), 2.8, 3)
	for data in game.Layout.STATIONS:
		var station = game.Challenge.new()
		game.add_child(station)
		station.setup(game, data)
		game.stations.append(station)
	for info in [
		[Vector3(-9.5, 0, 16.5), "大烟山基地\nA · 山脚营地"],
		[Vector3(-7.5, 0, -22.5), "林间古道营地 ↑\n西岭山坡营地 ←"],
		[Vector3(-28.5, 0, -32.5), "← 诗碑亭 · 西岭营\n林间营地 →"],
		[Vector3(-60.5, 0, -64.0), "↙ 迷踪竹石阵 · 烟霞古洞\n摩崖石刻 · 先民岩画 · 寒潭"],
		[Vector3(38.0, 0, -23.5), "东岭茶亭 · 东坡营 ↗\n南上望稻亭 ↘"],
		[Vector3(-12.0, 0, -96.0), "西北高地营 ↖\n山道拦截营 ↑"],
		[Vector3(10.2, 0, -152.0), "↑ B区 · 云顶青石演武坛\n→ 北脊撤离信标"]
	]:
		signpost(info[0], info[1])

func _landmarks():
	game._make_crate("前哨补给箱", 1, game.Layout.on_ground(Vector3(-8.5, 0, -54.0)))
	var crate_roof = game._make_crate("竹林棚顶精密箱", 2, bamboo_shelter.roof_spot)
	crate_roof.set_meta("secret_key", "shelter_and_tower")
	var crate_cave = game._make_crate("山崖秘窟空投箱", 3, game.Layout.on_ground(game.Layout.CAVE_GROTTO))
	crate_cave.set_meta("secret_key", "cave_grotto")
	var crate_tower = game._make_crate("观察哨顶层秘宝", 2, watchtower_pos + Vector3(0.18, 5.92, -0.20))
	crate_tower.set_meta("secret_key", "shelter_and_tower")
	var crate_container = game._make_crate("西岭货柜暗箱", 2, container_yard.top_deck + Vector3(0.45, 0.0, 0.0))
	crate_container.set_meta("secret_key", "parkour_containers")
	var cave_c: Vector3 = game.Layout.YANXIA_CAVE_CENTER
	var crate_yanxia = game._make_crate("烟霞古洞秘藏石匣", 3, Vector3(cave_c.x + 2.55, float(game.Layout.CAVE_FLOOR_Y) + 0.026, cave_c.z - 1.45))
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

	game._label3d(self, "B · 战术撤离信标\n260分 · 攻2哨 · 败统领 · 普通60%/机密80%", game.exit_position + Vector3.UP * 2.8, 36, game.MINT)

	var pickup_spots = [
		{"at": Vector3(5.2, 0, 16.8), "ground": true, "secret_key": ""},
		{"at": Vector3(-16.0, 0, -24.0), "ground": true, "secret_key": ""},
		{"at": Vector3(-34.0, 0, -44.0), "ground": true, "secret_key": ""},
		{"at": Vector3(-3.0, 0, -94.0), "ground": true, "secret_key": ""},
		{"at": Vector3(14.0, 0, -126.0), "ground": true, "secret_key": ""},
		{"at": Vector3(26.5, 0, -158.0), "ground": true, "secret_key": ""},
		{"at": game.Layout.CLEFT_CACHE, "ground": true, "secret_key": "cleft_cache"},
		{"at": container_yard.mid_deck, "ground": false, "secret_key": "parkour_containers"},
		{"at": game.Layout.EAST_OVERLOOK + Vector3(-4.2, 0, 2.2), "ground": true, "secret_key": "east_overlook"},
		{"at": game.Layout.SE_BAMBOO_CACHE, "ground": true, "secret_key": "se_bamboo_cache"},
		{"at": game.Layout.BAMBOO_MAZE_SUNDIAL + Vector3(0.0, 0.0, -0.45), "ground": true, "secret_key": "yanxia_cave"}
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
		{"at": Vector3(8.8, 0, 17.8), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "5.56 军用弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-7.0, 0, -24.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "5.56 军用弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-48.0, 0, -18.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "西岭营旁弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(52.0, 0, -64.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "东坡营旁弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-42.0, 0, -150.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "西北高地弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(6.5, 0, -96.5), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "巡护站备弹箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-4.0, 0, -124.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "山道前哨弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(22.0, 0, -160.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "云顶竹林弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-11.0, 0, -178.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "演武坛西侧弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(-26.0, 0, -52.0), "ground": true, "kind": "ammo_crate", "mesh": "pickup_ammo_crate", "title": "诗碑古道弹药箱", "col": Color("ffd15c"), "secret_key": ""},
		{"at": Vector3(7.4, 0, 20.2), "ground": true, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "烟雾/EMP 手雷", "col": Color("56e8ff"), "secret_key": ""},
		{"at": Vector3(2.0, 0, -96.5), "ground": true, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "烟雾/EMP 手雷", "col": Color("56e8ff"), "secret_key": ""},
		{"at": Vector3(26.0, 0, -162.0), "ground": true, "kind": "smoke_emp", "mesh": "pickup_smoke_emp", "title": "烟雾/EMP 手雷", "col": Color("56e8ff"), "secret_key": ""},
		{"at": Vector3(-12.0, 0, -184.0), "ground": true, "kind": "energy_drink", "mesh": "pickup_energy_drink", "title": "肾上腺素能量饮", "col": Color("6ae3a8"), "secret_key": ""},
		{"at": Vector3(-0.5, 0, -95.0), "ground": true, "kind": "energy_drink", "mesh": "pickup_energy_drink", "title": "肾上腺素能量饮", "col": Color("6ae3a8"), "secret_key": ""},
		{"at": Vector3(21.0, 0, -154.0), "ground": true, "kind": "energy_drink", "mesh": "pickup_energy_drink", "title": "肾上腺素能量饮", "col": Color("6ae3a8"), "secret_key": ""},
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
	# 1) Carved concave wet-pebble streambed & mossy cobble banks across the 240m Great Yanshan creek
	var bed_verts := PackedVector3Array()
	var bed_normals := PackedVector3Array()
	var bed_uvs := PackedVector2Array()
	var bed_colors := PackedColorArray()
	var bed_rows := []
	var s_min := float(game.Layout.STREAM_Z_MIN)
	var s_max := float(game.Layout.MAX_Z)
	var bed_end := s_max + 26.0
	var bz_cur := s_min - 0.5
	while bz_cur <= bed_end + 0.01:
		var zc := minf(bz_cur, bed_end)
		var cx := _outer_stream_x(zc)
		var wy := _stream_water_y_any(zc)
		var w_sc := _outer_stream_width_scale(zc)
		var end_fade := maxf(1.0 - smoothstep(s_min - 0.5, s_min + 2.0, zc), smoothstep(bed_end - 8.0, bed_end, zc))
		var row := []
		for u_i in range(-7, 8):
			var norm_off := float(u_i) * 0.34
			var off := norm_off * w_sc
			var px := cx + off
			var base_h := float(game.terrain_height(px, zc)) if zc <= s_max else (_outer_valley_y(px, zc) + 0.055 * (1.0 - smoothstep(1.48, 2.22, absf(norm_off))))
			var lip_taper := lerpf(0.014, -0.058, smoothstep(1.86, 2.38, absf(norm_off)))
			var py := base_h + lip_taper
			var wet := 1.0 - smoothstep(wy - 0.02, wy + 0.30, py)
			var grass_blend := maxf(smoothstep(1.74, 2.28, absf(norm_off)), end_fade)
			var r_t := clampf(float(game.Layout.road_distance(px, zc, 4.6)) / 4.6, 0.0, 1.0) if zc <= s_max else 1.0
			var s_t := clampf(absf(off) / 3.8, 0.0, 1.0)
			var nrm_v := _smooth_vis_normal(px, zc) if zc <= s_max else _outer_valley_normal(px, zc)
			row.append([Vector3(px, py, zc), Vector2(px * 0.56, zc * 0.56), Color(wet, grass_blend, r_t, s_t), nrm_v])
		bed_rows.append(row)
		bz_cur += 1.0 if zc < s_max else 1.5

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
			var qn: Array[Vector3] = [a0[3] as Vector3, a1[3] as Vector3, b0[3] as Vector3, b1[3] as Vector3]
			for k in [0, 1, 2, 1, 3, 2]:
				bed_verts.append(qv[k])
				bed_normals.append(qn[k])
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
uniform sampler2D mud_cobble : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
void vertex(){
 wpos = VERTEX;
}
void fragment(){
 float wet = clamp(COLOR.r, 0.0, 1.0);
 float grass_t = clamp(COLOR.g, 0.0, 1.0);
 vec3 p_col = texture(pebbles, UV).rgb;
 float p_lum = dot(p_col, vec3(0.299, 0.587, 0.114));
 float p_rough = texture(pebbles_rough, UV).r;
 float moss_n = 0.5 + 0.5 * sin(wpos.x * 2.1 + cos(wpos.z * 1.8) * 2.0);

 vec3 dry_cobble = mix(vec3(0.28, 0.30, 0.29), vec3(0.21, 0.26, 0.22), moss_n * 0.55 * (1.0 - wet)) * mix(0.76, 1.24, p_lum);
 vec3 wet_pebble = vec3(0.18, 0.21, 0.20) * mix(0.75, 1.25, p_lum);
 vec3 channel_col = mix(dry_cobble, wet_pebble, wet);

 vec2 bank_uv = wpos.xz * 0.42;
 vec3 mc = texture(mud_cobble, bank_uv).rgb;
 float mc_lum = dot(mc, vec3(0.299, 0.587, 0.114));
 vec3 wet_bank = vec3(0.22, 0.24, 0.23) * mix(0.75, 1.25, mc_lum);

 ALBEDO = mix(channel_col, wet_bank, grass_t);
 NORMAL_MAP = mix(texture(pebbles_normal, UV).rgb, texture(mud_normal, bank_uv).rgb, grass_t);
 NORMAL_MAP_DEPTH = mix(0.82, 0.62, grass_t);
 ROUGHNESS = mix(mix(clamp(p_rough * 0.88, 0.48, 0.86), 0.24, wet), 0.56, grass_t);
 SPECULAR = mix(0.24, 0.06, grass_t);
}
"""
	var bed_mat := ShaderMaterial.new()
	bed_mat.shader = bed_shader
	bed_mat.set_shader_parameter("pebbles", load("res://assets/slice/river_pebbles_color.jpg"))
	bed_mat.set_shader_parameter("pebbles_normal", load("res://assets/slice/river_pebbles_normal.jpg"))
	bed_mat.set_shader_parameter("pebbles_rough", load("res://assets/slice/river_pebbles_rough.jpg"))
	bed_mat.set_shader_parameter("mud_cobble", load("res://assets/slice/ink_jiangnan/mud_cobble_albedo.jpg"))
	bed_mat.set_shader_parameter("mud_normal", load("res://assets/slice/ink_jiangnan/mud_cobble_normal.jpg"))
	bed_inst.material_override = bed_mat
	bed_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed_inst)

	# 2) Continuous clear mountain brook flowing from North Spring (z=-196) right underneath South Fence (z=40) into the village paddies
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var rows := []
	var water_end := s_max + 150.0
	var z_cur := s_min
	while z_cur <= water_end + 0.01:
		var zc := minf(z_cur, water_end)
		var cx := _outer_stream_x(zc)
		var wy := _stream_water_y_any(zc)
		var w_sc := _outer_stream_width_scale(zc)
		var hw := 1.92 * w_sc * smoothstep(s_min - 1.0, s_min + 2.8, zc)
		hw = maxf(hw, 0.58)
		var tail_fade := 1.0 - smoothstep(water_end - 18.0, water_end, zc)
		var v_coord := (zc - s_min) * 0.22
		var r_pts := []
		for s_i in 5:
			var frac := -1.0 + float(s_i) * 0.5
			var edge_amt := absf(frac)
			r_pts.append([Vector3(cx + frac * hw, wy, zc), Vector2(0.5 + frac * 0.5, v_coord), Color(edge_amt, tail_fade, 0.0)])
		rows.append(r_pts)
		z_cur += 1.25 if zc < s_max + 12.0 else 4.0

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

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float raindrop_rings(vec2 p, float t) {
	float acc = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		vec2 uv_g = p * (1.55 + float(layer) * 0.85) + vec2(float(layer) * 13.7, float(layer) * 7.3);
		vec2 id = floor(uv_g);
		vec2 f = fract(uv_g) - 0.5;
		float h = hash21(id);
		vec2 jit = vec2(fract(h * 17.3) - 0.5, fract(h * 31.7) - 0.5) * 0.42;
		float life = fract(t * 0.68 + h);
		float d = length(f - jit);
		float rad = life * 0.44;
		float ring = exp(-abs(d - rad) * 34.0) * (1.0 - life) * smoothstep(0.02, 0.12, life);
		acc += ring;
	}
	return clamp(acc, 0.0, 1.0);
}

void vertex(){
 edge_t = COLOR.r;
 tail_a = COLOR.g;
 wpos = VERTEX;
 float rip = sin(TIME * 1.8 + VERTEX.z * 1.5 + sin(VERTEX.x * 2.1) * 1.2) * 0.006;
 VERTEX.y += rip * (1.0 - edge_t * 0.75);
}
void fragment(){
 // Gentle current + authentic Jiangnan misty raindrop concentric rings ('雨打溪面同心圆涟漪')
 float w1 = sin(UV.y * 8.0 - TIME * 1.9 + sin(UV.x * 6.5 + TIME * 0.7) * 1.1);
 float w2 = cos(UV.y * 13.5 - TIME * 2.4 - cos(wpos.x * 2.6 - TIME * 0.8) * 1.1);
 float drop_ring = raindrop_rings(wpos.xz, TIME);

 // Fresnel sky-water unity ('水天一色'): dark damp ink-olive straight down -> pale Xuan-paper sky mirror at grazing angles!
 vec3 w_view_up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
 float ndotv = clamp(abs(dot(w_view_up, VIEW)), 0.0, 1.0);
 float fresnel = pow(1.0 - ndotv, 2.35);

 vec3 deep_ink_water = vec3(0.11, 0.25, 0.28);
 vec3 bank_canopy_refl = vec3(0.15, 0.28, 0.24);
 vec3 misty_sky_mirror = vec3(0.50, 0.72, 0.85);

 vec3 base_water = mix(deep_ink_water, bank_canopy_refl, smoothstep(0.35, 0.88, edge_t));
 vec3 col = mix(base_water, misty_sky_mirror, clamp(0.16 + fresnel * 0.46 - edge_t * 0.20, 0.0, 0.65));
 // Sparkling sky-blue & ivory water ripple rings
 col = mix(col, vec3(0.88, 0.93, 0.96), drop_ring * 0.52 * (1.0 - edge_t * 0.50));

 ALBEDO = col;
 NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3((w1 - w2) * 0.035, 1.0, (w1 + w2) * 0.035)), 0.0)).xyz);
 ROUGHNESS = 0.18;
 SPECULAR = 0.26;
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
	rock(Vector3(game.Layout.stream_center_x(s_min), 0, s_min - 1.2), 2.5, 2)
	rock(Vector3(game.Layout.stream_center_x(s_min + 0.5) - 2.4, 0, s_min + 0.5), 1.9, 0)
	rock(Vector3(game.Layout.stream_center_x(s_min + 0.5) + 2.4, 0, s_min + 0.5), 2.0, 1)

	# 4) 5 walkable creek crossings: Central v0.8.5 Triple-Arch Bluestone Bridge, North Stone Arch Bridge & 3 Wooden Footbridges
	for bz in game.Layout.STREAM_BRIDGES:
		if is_equal_approx(float(bz), float(game.Layout.MULTI_ARCH_BRIDGE_Z)):
			_build_multi_arch_bridge(float(bz))
		elif is_equal_approx(float(bz), float(game.Layout.STONE_ARCH_BRIDGE_Z)):
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
	var sz_cur := s_min + 2.5
	var bank_idx := 0
	while sz_cur <= s_max + 12.0:
		if not _is_near_bridge(sz_cur, 4.2):
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
		sz_cur += 2.65

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
	for k_idx in 24:
		var lz := s_min + 12.0 + float(k_idx) * 9.2
		if lz > s_max - 4.0 or _is_near_bridge(lz, 3.8):
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

func _instantiate_v085_mesh(mesh_name: String) -> Node3D:
	var path := "res://assets/slice/v085_landmarks.glb"
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

func _instantiate_v086_mesh(mesh_name: String) -> Node3D:
	var path := "res://assets/slice/v086_architecture.glb"
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

static func _multi_arch_deck_y(x: float) -> float:
	var ax := absf(x)
	if ax <= 7.0:
		return 0.22 * (1.0 + cos(PI * ax / 7.0))
	return -0.24 * minf(1.0, (ax - 7.0) / 0.40)

func _build_multi_arch_bridge(z_center: float):
	## v0.8.5 Blender 4.5 Triple-Arch Carved Jiangnan Bluestone Bridge ("三孔青石拱桥")
	var cx := float(game.Layout.stream_center_x(z_center))
	var wy := float(game.Layout.stream_water_y(z_center))
	var bank_w := float(game.terrain_height(cx - 7.0, z_center))
	var bank_e := float(game.terrain_height(cx + 7.0, z_center))
	var base_y := maxf(wy + 0.62, maxf(bank_w, bank_e) - 0.02)
	var root := Node3D.new()
	root.name = "TripleArchStoneBridge"
	root.position = Vector3(cx, base_y, z_center)
	add_child(root)

	var visual := _instantiate_v085_mesh("bridge_multi_arch")
	if visual:
		root.add_child(visual)

	var steps := 14
	var span_dx := 14.0 / float(steps)
	for i in steps:
		var x0 := -7.0 + float(i) * span_dx
		var x1 := x0 + span_dx
		var y0 := _multi_arch_deck_y(x0)
		var y1 := _multi_arch_deck_y(x1)
		var xm := 0.5 * (x0 + x1)
		var ym := 0.5 * (y0 + y1)
		var seg_len := sqrt(span_dx * span_dx + (y1 - y0) * (y1 - y0)) + 0.14
		var shp := BoxShape3D.new()
		shp.size = Vector3(seg_len, 0.26, 2.55)
		var body: StaticBody3D = game.Props.shape_body(root, shp, Vector3(xm, ym - 0.13, 0.0))
		body.rotation.z = atan2(y1 - y0, span_dx)

	var apron_mat := _get_ink_arch_material("bluestone")
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var outer_x := cx + side_f * 8.45
		var outer_local_y := float(game.terrain_height(outer_x, z_center)) - base_y - 0.05
		var drop := maxf(0.05, _multi_arch_deck_y(side_f * 6.90) - outer_local_y)
		var run := 1.65
		var ramp_len := sqrt(run * run + drop * drop) + 0.18
		var pivot := Node3D.new()
		pivot.position = Vector3(side_f * (6.90 + run * 0.5), _multi_arch_deck_y(side_f * 6.90) - drop * 0.5, 0.0)
		pivot.rotation.z = -side_f * atan2(drop, run)
		root.add_child(pivot)
		var slab: Node3D = game._mesh_box(pivot, Vector3(0, -0.08, 0), Vector3(ramp_len, 0.16, 2.66), Color.WHITE, true)
		slab.material_override = apron_mat

	for sz in [-1.36, 1.36]:
		for sx in [-1.0, 1.0]:
			var rail_shp := BoxShape3D.new()
			rail_shp.size = Vector3(6.95, 0.90, 0.24)
			var rail_body: StaticBody3D = game.Props.shape_body(root, rail_shp, Vector3(sx * 3.45, 0.52, sz))
			rail_body.rotation.z = -sx * 0.065

	# West bridgehead engraved Boundary Stele
	var stele_at: Vector3 = game.Layout.on_ground(Vector3(cx - 8.2, 0.0, z_center + 2.75))
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

func _build_v085_landmarks():
	## v0.8.5 Great Yanshan Landmarks:
	## 1) North Cloud-Top 38m Bluestone Martial Arena ("云顶青石演武坛") with 8 Dragon-Carved Pillars & Curb Rim
	var arena_c: Vector3 = game.Layout.CLOUD_ARENA_CENTER
	var arena_y := float(game.Layout.CLOUD_ARENA_Y)
	var arena_r := float(game.Layout.CLOUD_ARENA_RADIUS)
	var arena_root := Node3D.new()
	arena_root.name = "CloudTopMartialArena"
	arena_root.position = Vector3(arena_c.x, arena_y, arena_c.z)
	add_child(arena_root)

	# Glowing engraved bronze-gold central martial array ring (readies stage for v0.8.6 Skyfall Overlord!)
	var ring_m := TorusMesh.new()
	ring_m.inner_radius = 12.6
	ring_m.outer_radius = 13.0
	ring_m.rings = 48
	ring_m.ring_segments = 6
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring_m
	ring_mi.position = Vector3(0.0, 0.04, 0.0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("d8b25a")
	rmat.metallic = 0.72
	rmat.roughness = 0.34
	rmat.emission_enabled = true
	rmat.emission = Color("c8983e")
	rmat.emission_energy_multiplier = 0.45
	ring_mi.material_override = rmat
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena_root.add_child(ring_mi)

	# 8 Dragon-Carved Bluestone Pillars ringing the 38m plaza perimeter (placed at diagonal/inter-cardinal octants
	# so the South, North, East & West approaches stay 100% open & walkable!)
	for k in 8:
		var ang := (float(k) + 0.5) * (TAU / 8.0)
		var px := cos(ang) * (arena_r - 0.6)
		var pz := sin(ang) * (arena_r - 0.6)
		var p_node := Node3D.new()
		p_node.name = "ArenaDragonPillar_%d" % k
		p_node.position = Vector3(px, -0.06, pz)
		p_node.rotation.y = -ang + PI * 0.5
		arena_root.add_child(p_node)
		var p_vis := _instantiate_v085_mesh("arena_dragon_pillar")
		if p_vis:
			p_node.add_child(p_vis)
		var p_col := CylinderShape3D.new()
		p_col.radius = 0.72
		p_col.height = 5.6
		game.Props.shape_body(p_node, p_col, Vector3(0.0, 2.8, 0.0)).add_to_group("solid_props")

		# Low decorative curb segments on non-gateway arcs (leave wide South/East/West/North entrances open!)
		if k in [0, 2, 4, 6]:
			var ang2 := ang + TAU / 16.0
			var rx := cos(ang2) * (arena_r - 0.3)
			var rz := sin(ang2) * (arena_r - 0.3)
			var r_node := Node3D.new()
			r_node.position = Vector3(rx, -0.06, rz)
			r_node.rotation.y = -ang2 + PI * 0.5
			arena_root.add_child(r_node)
			var r_vis := _instantiate_v085_mesh("arena_altar_rim")
			if r_vis:
				r_node.add_child(r_vis)
			var r_shp := BoxShape3D.new()
			r_shp.size = Vector3(4.80, 0.78, 0.76)
			game.Props.shape_body(r_node, r_shp, Vector3(0.0, 0.36, 0.0)).add_to_group("solid_props")

	var arena_lbl: Label3D = game._label3d(arena_root, "☁ 云顶青石演武坛 · B区总坛", Vector3(0.0, 6.2, -16.5), 34, Color("ffe29c"))
	arena_lbl.pixel_size = 0.0060
	arena_lbl.visibility_range_end = 56.0

	# 2) East Ridge Tea-Hill Rest Pavilion ("东岭茶亭") at EAST_OVERLOOK
	var tea_at: Vector3 = game.Layout.on_ground(game.Layout.EAST_OVERLOOK)
	var tea_root := Node3D.new()
	tea_root.name = "TeaHillPavilion"
	tea_root.position = Vector3(tea_at.x, tea_at.y - 0.04, tea_at.z)
	add_child(tea_root)
	var tea_vis := _instantiate_v086_mesh("tea_pavilion_upgraded")
	if tea_vis == null:
		tea_vis = _instantiate_v085_mesh("tea_hill_pavilion")
	if tea_vis:
		tea_root.add_child(tea_vis)
	var tea_floor := CylinderShape3D.new()
	tea_floor.radius = 2.95
	tea_floor.height = 0.38
	game.Props.shape_body(tea_root, tea_floor, Vector3(0.0, 0.19, 0.0)).add_to_group("solid_props")
	var tea_tbl := CylinderShape3D.new()
	tea_tbl.radius = 0.65
	tea_tbl.height = 0.96
	game.Props.shape_body(tea_root, tea_tbl, Vector3(0.0, 0.52, 0.0)).add_to_group("solid_props")
	for k in 6:
		var ang := float(k) * (PI / 3.0) + PI / 6.0
		var col_s := CylinderShape3D.new()
		col_s.radius = 0.16
		col_s.height = 2.8
		game.Props.shape_body(tea_root, col_s, Vector3(cos(ang) * 2.35, 1.80, sin(ang) * 2.35)).add_to_group("solid_props")
	var tea_lbl: Label3D = game._label3d(tea_root, "东岭茶亭 · 观溪歇脚处", Vector3(0.0, 3.45, 0.0), 24, Color("f3ead0"))
	tea_lbl.pixel_size = 0.0038
	tea_lbl.visibility_range_end = 26.0

	# 3) Yanshan Mountain Inscribed Stele ("烟山摩崖石碑") overlooking the mid-west ridge
	var st_at: Vector3 = game.Layout.on_ground(game.Layout.CLIFF_STELE_AT)
	var st_root := Node3D.new()
	st_root.name = "YanshanCliffStele"
	st_root.position = Vector3(st_at.x, st_at.y - 0.05, st_at.z)
	st_root.rotation.y = deg_to_rad(32.0)
	add_child(st_root)
	var st_vis := _instantiate_v085_mesh("cliff_stele")
	if st_vis:
		st_root.add_child(st_vis)
	var st_shp := BoxShape3D.new()
	st_shp.size = Vector3(2.35, 3.60, 1.15)
	game.Props.shape_body(st_root, st_shp, Vector3(0.0, 1.80, 0.0)).add_to_group("solid_props")
	var st_lbl: Label3D = game._label3d(st_root, "烟山古碑 · 西北高岭界", Vector3(0.0, 4.18, 0.0), 24, Color("f0deb0"))
	st_lbl.pixel_size = 0.0040
	st_lbl.visibility_range_end = 28.0

func _build_v086_scenery():
	## v0.8.6 Jiangnan Mountain-Forest Micro-Scenery Layer:
	## 2 Carved Arch Gates + 18 Glowing Stone Lanterns + 28 Terraced Tea Rows + 26 Mossy Boulder Clusters + 8 Trail Stone Benches
	var arch_glb := "res://assets/slice/v086_architecture.glb"
	if not ResourceLoader.exists(arch_glb):
		return

	# 1) 2 Jiangnan Mountain Trail Archways ("山道牌坊") with 4.2m wide walk-through portal
	var gate_specs := [
		["TrailArchGate_Forest", Vector3(-6.0, 0.0, -18.0), 0.14],
		["TrailArchGate_CloudArena", Vector3(0.0, 0.0, -124.0), 0.0]
	]
	for gs in gate_specs:
		var gp: Vector3 = game.Layout.on_ground(gs[1])
		var g_node := Node3D.new()
		g_node.name = str(gs[0])
		g_node.position = Vector3(gp.x, gp.y - 0.06, gp.z)
		g_node.rotation.y = float(gs[2])
		add_child(g_node)
		var g_vis := _instantiate_v086_mesh("mountain_arch_gate")
		if g_vis != null:
			g_node.add_child(g_vis)
		for sx in [-1.0, 1.0]:
			var p_shp := CylinderShape3D.new()
			p_shp.radius = 0.28
			p_shp.height = 4.2
			game.Props.shape_body(g_node, p_shp, Vector3(sx * 2.25, 2.1, 0.0)).add_to_group("solid_props")

	# 2) 18 Glowing Jiangnan Stone Lanterns ("青石灯笼") lining key junctions, bridges, Wangdao, Tea Pavilion & Cloud Arena
	var wd_dx := float(game.Layout.WANGDAO_PAVILION.x) - 33.5
	var wd_dz := float(game.Layout.WANGDAO_PAVILION.z) - 20.8
	var lantern_coords := [
		Vector2(8.0, 17.6), Vector2(-9.8, 12.6),
		Vector2(26.0 + wd_dx, 15.8 + wd_dz), Vector2(30.4 + wd_dx, 19.2 + wd_dz),
		Vector2(20.5, -20.5), Vector2(32.5, -26.5),
		Vector2(-32.0, -45.5), Vector2(-10.5, -48.0),
		Vector2(52.0, -34.0), Vector2(58.5, -41.5),
		Vector2(18.0, -76.0), Vector2(31.5, -80.0),
		Vector2(44.5, -92.0), Vector2(-18.0, -108.0),
		Vector2(-10.5, -138.0), Vector2(10.5, -138.0),
		Vector2(24.0, -155.0), Vector2(-28.0, -156.0)
	]
	var lantern_mesh := _extract_mesh(arch_glb, "stone_lantern")
	var lantern_tx: Array = []
	for i in lantern_coords.size():
		var lp: Vector2 = lantern_coords[i]
		var ly := float(game.terrain_height(lp.x, lp.y)) - 0.04
		lantern_tx.append(Transform3D(Basis(Vector3.UP, float(i) * 0.65), Vector3(lp.x, ly, lp.y)))
	_batch_direct(lantern_mesh, lantern_tx, false, "JiangnanStoneLanterns", 92.0)

	# 3) Lush Terraced Jiangnan Tea-Bush Hedges ("梯田茶垄") along East Tea Ridge, Wangdao slopes & South-East hillside
	var tea_mesh := _extract_mesh(arch_glb, "tea_terraced_hedge")
	var tea_tx: Array = []
	var tea_zones := [
		[46.0, 74.0, -34.0, 14.0, 12],
		[44.0, 78.0, -82.0, -36.0, 10],
		[-72.0, -34.0, -18.0, 26.0, 8]
	]
	var sc_rng := RandomNumberGenerator.new()
	sc_rng.seed = 20261122
	for tz in tea_zones:
		var target_cnt: int = int(tz[4])
		var placed := 0
		var tries := 0
		while placed < target_cnt and tries < target_cnt * 8:
			tries += 1
			var tx := sc_rng.randf_range(float(tz[0]), float(tz[1]))
			var tz_z := sc_rng.randf_range(float(tz[2]), float(tz[3]))
			if game.Layout.clear_for_route(tx, tz_z, 2.0) or _is_vista_corridor(tx, tz_z):
				continue
			var ty := float(game.terrain_height(tx, tz_z)) - 0.08
			var tyaw := atan2(game.terrain_height(tx + 1.0, tz_z) - game.terrain_height(tx - 1.0, tz_z), 2.0) + PI * 0.5
			var tsc := sc_rng.randf_range(0.88, 1.24)
			tea_tx.append(Transform3D(Basis(Vector3.UP, tyaw + sc_rng.randf_range(-0.25, 0.25)).scaled(Vector3(tsc, tsc * 0.96, tsc)), Vector3(tx, ty, tz_z)))
			placed += 1
	_batch_direct(tea_mesh, tea_tx, false, "JiangnanTeaHedges", 115.0)

	# 4) Sculpted Mossy Mountain Boulder Clusters ("太湖苔石群") enriching hillsides & creek meadows
	var boulder_mesh := _extract_mesh(arch_glb, "mossy_boulder_cluster")
	var boulder_tx: Array = []
	var b_tries := 0
	while boulder_tx.size() < 28 and b_tries < 180:
		b_tries += 1
		var bx := sc_rng.randf_range(float(game.Layout.FENCE_MIN_X) + 4.0, float(game.Layout.FENCE_MAX_X) - 4.0)
		var bz := sc_rng.randf_range(float(game.Layout.FENCE_MIN_Z) + 4.0, float(game.Layout.FENCE_MAX_Z) - 6.0)
		if game.Layout.clear_for_route(bx, bz, 2.6) or _is_vista_corridor(bx, bz):
			continue
		var by := float(game.terrain_height(bx, bz)) - 0.14
		var bsc := sc_rng.randf_range(0.75, 1.32)
		boulder_tx.append(Transform3D(Basis(Vector3.UP, sc_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * bsc), Vector3(bx, by, bz)))
	_batch_direct(boulder_mesh, boulder_tx, false, "MossyBoulderClusters", 110.0)

	# 5) 8 Rustic Bluestone Scenic Resting Benches ("青石游憩凳") beside landmarks & overlooks
	var bench_mesh := _extract_mesh(arch_glb, "trail_stone_bench")
	var bench_specs := [
		[Vector2(-8.2, 16.5), 0.45],
		[Vector2(24.0 + wd_dx, 16.5 + wd_dz), -0.65],
		[Vector2(50.5, -36.5), -1.10],
		[Vector2(-35.5, -45.0), 0.72],
		[Vector2(18.5, -28.0), 1.40],
		[Vector2(20.5, -80.5), 1.55],
		[Vector2(-24.0, -138.0), 0.25],
		[Vector2(28.0, -158.0), -0.80]
	]
	var bench_tx: Array = []
	for bs in bench_specs:
		var bp: Vector2 = bs[0]
		var by := float(game.terrain_height(bp.x, bp.y)) - 0.03
		bench_tx.append(Transform3D(Basis(Vector3.UP, float(bs[1])), Vector3(bp.x, by, bp.y)))
	_batch_direct(bench_mesh, bench_tx, false, "ScenicStoneBenches", 85.0)

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
	# 1) v0.8.6 Rebuilt Unified Jiangnan Double-Eave Wangdao Pavilion & Terrace ("望稻重檐观景亭台")
	# Zero overlapping boxes, zero skewed stair-to-pilaster collisions, seamless integrated South viewing balcony!
	var pav_ground: Vector3 = game.Layout.on_ground(game.Layout.WANGDAO_PAVILION)
	var wd_dx := float(game.Layout.WANGDAO_PAVILION.x) - 33.5
	var wd_dz := float(game.Layout.WANGDAO_PAVILION.z) - 20.8
	var deck_y: float = pav_ground.y + 2.75
	var deck_center := Vector3(35.2 + wd_dx, deck_y, 22.4 + wd_dz)
	wangdao_deck_pos = Vector3(35.2 + wd_dx, deck_y + 0.015, 25.45 + wd_dz)

	var overlook_root := Node3D.new()
	overlook_root.name = "WangdaoOverlookTerrace"
	add_child(overlook_root)
	var stone_mat := _get_ink_arch_material("bluestone")

	# Unified Blender 4.5 Double-Eave Wangdao Pavilion + Bluestone Terrace + Integrated South Viewing Balcony
	var pav := Node3D.new()
	pav.name = "WangdaoPavilion"
	pav.position = deck_center
	pav.rotation.y = 0.0
	overlook_root.add_child(pav)
	var wd_vis := _instantiate_v086_mesh("wangdao_pavilion_complete")
	if wd_vis != null:
		pav.add_child(wd_vis)

	# Crisp engraved gilded plaque text on West (-X, stair approach) & South (+Z, balcony) lintels!
	var pl_w: Label3D = game._label3d(pav, "望  稻  亭", Vector3(-1.86, 2.66, -0.45), 34, Color("24150c"))
	pl_w.rotation.y = -PI * 0.5
	pl_w.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pl_w.pixel_size = 0.0052
	pl_w.outline_size = 3
	pl_w.outline_modulate = Color("f2d586")
	pl_w.visibility_range_end = 42.0
	var pl_s: Label3D = game._label3d(pav, "望  稻  亭", Vector3(0.0, 2.66, 1.41), 34, Color("24150c"))
	pl_s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pl_s.pixel_size = 0.0052
	pl_s.outline_size = 3
	pl_s.outline_modulate = Color("f2d586")
	pl_s.visibility_range_end = 42.0

	# 1:1 Aligned Solid Colliders for Terrace Deck, Platform Base, Balustrades, Columns & Tea Table
	var deck_col_shp := BoxShape3D.new()
	deck_col_shp.size = Vector3(6.48, 5.20, 6.84)
	game.Props.shape_body(pav, deck_col_shp, Vector3(0.0, -2.60, 0.275)).add_to_group("solid_props")
	# Perimeter waist-high railing colliders (leaving West stair portal Z in [-2.65, +1.15] wide open!)
	for r_spec in [
		[Vector3(0.0, 0.45, 3.56), Vector3(6.44, 0.90, 0.22)],
		[Vector3(3.18, 0.45, 0.27), Vector3(0.22, 0.90, 6.68)],
		[Vector3(0.0, 0.45, -3.02), Vector3(6.44, 0.90, 0.22)],
		[Vector3(-3.18, 0.45, 2.36), Vector3(0.22, 0.90, 2.46)],
	]:
		var r_shp := BoxShape3D.new()
		r_shp.size = r_spec[1]
		game.Props.shape_body(pav, r_shp, r_spec[0]).add_to_group("solid_props")
	# 4 Pavilion Column colliders + North bench + Center tea table (pavilion center at z=-0.45)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c_shp := CylinderShape3D.new()
			c_shp.radius = 0.16
			c_shp.height = 2.95
			game.Props.shape_body(pav, c_shp, Vector3(sx * 1.72, 1.55, -0.45 + sz * 1.72)).add_to_group("solid_props")
	var n_bench := BoxShape3D.new()
	n_bench.size = Vector3(3.10, 0.92, 0.46)
	game.Props.shape_body(pav, n_bench, Vector3(0.0, 0.50, -0.45 - 1.62)).add_to_group("solid_props")
	var tbl_shp := CylinderShape3D.new()
	tbl_shp.radius = 0.56
	tbl_shp.height = 0.88
	game.Props.shape_body(pav, tbl_shp, Vector3(0.0, 0.46, -0.45)).add_to_group("solid_props")

	# Clean Flush West-NW Bluestone Staircase landing squarely inside the 3.80m West Terrace Portal (Z in [-2.65, +1.15])!
	var stair_foot := Vector3(27.4 + wd_dx, float(game.terrain_height(27.4 + wd_dx, 17.1 + wd_dz)) - 0.08, 17.1 + wd_dz)
	var stair_top := Vector3(deck_center.x - 3.16, deck_y + 0.01, deck_center.z - 1.08)
	var stair_delta := stair_top - stair_foot
	var stair_horiz := Vector2(stair_delta.x, stair_delta.z).length()
	var stair_len := stair_delta.length()
	var stair_yaw := atan2(stair_delta.x, stair_delta.z)
	var stair_pitch := atan2(stair_delta.y, stair_horiz)
	var stair_mid := (stair_foot + stair_top) * 0.5
	var stair_node := Node3D.new()
	stair_node.name = "WangdaoStoneStairs"
	stair_node.position = stair_mid
	stair_node.rotation.y = stair_yaw
	overlook_root.add_child(stair_node)

	# Smooth walkable stone ramp collider + solid 12-step bluestone stairs & neat stepped cheek walls (ZERO pilaster clipping!)
	var ramp_shp := BoxShape3D.new()
	ramp_shp.size = Vector3(2.44, 0.28, stair_len + 0.55)
	var ramp_body: StaticBody3D = game.Props.shape_body(stair_node, ramp_shp, Vector3(0.0, -0.14, 0.0))
	ramp_body.rotation.x = -stair_pitch
	var step_count := 12
	var step_dark := StandardMaterial3D.new()
	step_dark.albedo_color = Color("565f61")
	step_dark.roughness = 0.86
	for si in step_count:
		var t_s := (float(si) + 0.5) / float(step_count)
		var sz_loc := lerpf(-stair_horiz * 0.5, stair_horiz * 0.5, t_s)
		var sy_top := lerpf(-stair_delta.y * 0.5, stair_delta.y * 0.5, (float(si) + 1.0) / float(step_count))
		var riser_h := maxf(0.42, sy_top + stair_delta.y * 0.5 + 0.85)
		var tread_d := (stair_horiz / float(step_count)) + 0.06
		var step_mi: MeshInstance3D = game._mesh_box(stair_node, Vector3(0.0, sy_top - riser_h * 0.5, sz_loc), Vector3(2.36, riser_h, tread_d), Color.WHITE, false)
		step_mi.material_override = stone_mat
		var nosing: MeshInstance3D = game._mesh_box(stair_node, Vector3(0.0, sy_top - 0.035, sz_loc - tread_d * 0.44), Vector3(2.42, 0.07, 0.12), Color.WHITE, false)
		nosing.material_override = step_dark
	for side_x in [-1.28, 1.28]:
		var cheek: MeshInstance3D = game._mesh_box(stair_node, Vector3(side_x, 0.10, -0.08), Vector3(0.24, 0.62, stair_len - 0.15), Color.WHITE, false)
		cheek.rotation.x = -stair_pitch
		cheek.material_override = step_dark
		# Grounded entry newel post at foot of staircase cheek wall
		var foot_post: MeshInstance3D = game._mesh_box(stair_node, Vector3(side_x, -stair_delta.y * 0.5 + 0.36, -stair_horiz * 0.5 - 0.10), Vector3(0.32, 0.92, 0.32), Color.WHITE, false)
		foot_post.material_override = step_dark
	# Visual bluestone apron seamlessly filling junction under stair top & West terrace edge (ramp_body provides smooth collision!)
	var apron_mi: MeshInstance3D = game._mesh_box(overlook_root, Vector3(deck_center.x - 3.10, deck_y - 0.50, deck_center.z - 1.08), Vector3(0.76, 0.96, 2.72), Color.WHITE, false)
	apron_mi.material_override = stone_mat

	# v0.8.6 Fix: Face NW (-2.28 rad) directly outward toward approaching players outside the staircase!
	signpost(Vector3(24.8 + wd_dx, 0.0, 17.2 + wd_dz), "东岭梯田观景台 · 望稻亭\n登石阶俯瞰梯田与诚庄村落 ↗", -2.28, NAN, "WangdaoSignpost")

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

	# v0.8.2 V81-2: Legacy 3D BluestoneFlagstones trail slabs removed — the seamless 1024x1024
	# world-space bluestone shader already paves every mountain trail cleanly with zero z-clipping slabs.

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
			elif mname.contains("Karst") or mname.contains("Rock") or mname.contains("Cliff") or mname.contains("CaveStone"):
				mesh.surface_set_material(s, _get_ink_arch_material("rock"))
				continue
			elif mname.contains("Bluestone") or mname.contains("Stone") or mname.contains("Plinth"):
				mesh.surface_set_material(s, _get_ink_arch_material("bluestone"))
				continue
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

	var cdx := float(game.Layout.CAVE_DX)
	var cdz := float(game.Layout.CAVE_DZ)
	var cave_y := float(game.Layout.CAVE_FLOOR_Y)
	var x0 := -48.10 + cdx
	var cw := 2.60
	var z0 := -36.50 + cdz
	var ch := 3.00

	# South Bluestone Archway ("迷 踪 竹 石 阵")
	var gate_pos := Vector3(-41.60 + cdx, float(game.terrain_height(-41.60 + cdx, -36.50 + cdz)) - 0.04, -36.50 + cdz)
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

	# Central Eroded Karst Crouch Arch ("矮石暗拱 · [C] 蹲伏潜行")
	var arch_gy := float(game.terrain_height(-41.60 + cdx, -45.50 + cdz))
	var arch_node := Node3D.new()
	arch_node.name = "KarstCrouchArch"
	arch_node.position = Vector3(-41.60 + cdx, arch_gy, -45.50 + cdz)
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

	# East Side Gate framing monoliths
	for ez_off in [-1.22, 1.22]:
		var ez := float(ez_off)
		var egy := float(game.terrain_height(-35.10 + cdx, -44.00 + cdz + ez)) - 0.18
		karst_b_tx.append(Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(0.88, 1.04, 0.88)), Vector3(-35.10 + cdx, egy, -44.00 + cdz + ez)))

	# West Secret Alcove (0, 3): Ancient Bluestone Sundial Pedestal
	var sun_gy := float(game.terrain_height(-46.80 + cdx, -46.25 + cdz)) - 0.02
	var sundial := Node3D.new()
	sundial.name = "StoneSundialPedestal"
	sundial.position = Vector3(-46.80 + cdx, sun_gy, -46.25 + cdz)
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

	# East Cliff Moya Carving Alcove (4, 4): "竹石清音" Cliff Stele
	var moya_gy := float(game.terrain_height(-35.38 + cdx, -50.00 + cdz)) - 0.04
	var moya_node := Node3D.new()
	moya_node.name = "CliffMoyaStele"
	moya_node.position = Vector3(-35.38 + cdx, moya_gy, -50.00 + cdz)
	maze_root.add_child(moya_node)
	var moya_vis := _instantiate_v062_mesh("cliff_moya_stele")
	if moya_vis:
		moya_node.add_child(moya_vis)

	# 6 Hexagonal Mossy Jiangnan Stone Lanterns guiding key labyrinth junctions & Cavern Forecourt
	var lantern_pts := [
		Vector2(-40.62 + cdx, -37.28 + cdz),
		Vector2(-40.62 + cdx, -44.72 + cdz),
		Vector2(-42.55 + cdx, -46.28 + cdz),
		Vector2(-37.22 + cdx, -48.92 + cdz),
		Vector2(-42.55 + cdx, -53.80 + cdz),
		Vector2(-40.05 + cdx, -56.35 + cdz)
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

	# 2) "烟霞古洞" — Walk-in 2-Chamber Limestone Cavern rigidly translated to isolated West Bamboo Ravine!
	var cave_root := Node3D.new()
	cave_root.name = "YanxiaAncientCave"
	cave_root.position = Vector3(-41.60 + cdx, cave_y, -64.00 + cdz)
	add_child(cave_root)

	var cave_vis := _instantiate_v062_mesh("yanxia_cave_complex")
	if cave_vis:
		cave_root.add_child(cave_vis)

	var hearth_vis := _instantiate_v062_mesh("ancestral_hearth_relics")
	if hearth_vis:
		hearth_vis.position = Vector3(0.55, 0.026, -3.35)
		cave_root.add_child(hearth_vis)

	# Analytical cavern physics colliders (v0.8.2 V81-6: watertight exterior rock envelope covering FULL visual karst bluff mass
	# x_local = [-6.85..+6.85], z_local = [-7.35..+6.85], leaving ONLY the intentional central 3.24m x 3.25m South portal open!)
	var cave_boxes := [
		[Vector3(0.0, -0.174, 0.25), Vector3(7.60, 0.40, 12.30)],   # Walkable wet limestone floor slab (top = +0.026m = 6.526m world)
		[Vector3(-2.05, 0.70, -2.85), Vector3(2.08, 1.35, 3.08)],   # Sunken Jade Spring Pool rim guard
		[Vector3(-4.24, 2.75, 5.95), Vector3(5.24, 6.10, 2.25)],    # South portal West cliff buttress (inner edge x=-1.62, outer x=-6.86, z=+4.82..+7.08)
		[Vector3(4.24, 2.75, 5.95), Vector3(5.24, 6.10, 2.25)],     # South portal East cliff buttress (inner edge x=+1.62, outer x=+6.86, z=+4.82..+7.08)
		[Vector3(0.0, 4.60, 5.95), Vector3(3.60, 2.70, 2.25)],      # South portal over-arch brow (bottom = 3.25m)
		[Vector3(-5.05, 2.85, -0.35), Vector3(3.60, 6.20, 14.00)],  # West cavern cliff mass (inner face = -3.25, outer = -6.85 -> zero exterior clip!)
		[Vector3(5.05, 2.85, -0.35), Vector3(3.60, 6.20, 14.00)],   # East cavern cliff mass (inner face = +3.25, outer = +6.85 -> zero exterior clip!)
		[Vector3(0.0, 2.85, -6.25), Vector3(13.80, 6.20, 2.20)],    # North cavern back cliff mass (inner face = -5.15, outer = -7.35)
		[Vector3(0.0, 4.95, 0.0), Vector3(13.60, 2.00, 14.20)],     # Vaulted mountain roof cap (bottom = 3.95m)
		[Vector3(-0.33, 0.46, -3.70), Vector3(1.04, 0.88, 0.94)]    # Ancestral stone tea hearth
	]
	for cb in cave_boxes:
		var c_shp := BoxShape3D.new()
		c_shp.size = cb[1]
		game.Props.shape_body(cave_root, c_shp, cb[0]).add_to_group("solid_props")

	# Seal BambooStoneMaze row-6 forecourt corners rigidly translated by (cdx, cdz)
	for side_sgn in [-1.0, 1.0]:
		var sgn_f := float(side_sgn)
		var seal_x := -41.60 + cdx + sgn_f * 5.65
		var seal_z := -57.65 + cdz
		var seal_gy := float(game.terrain_height(seal_x, seal_z))
		var seal_shp := BoxShape3D.new()
		seal_shp.size = Vector3(2.80, 5.20, 3.20)
		game.Props.shape_body(maze_root, seal_shp, Vector3(seal_x, seal_gy + 2.30, seal_z)).add_to_group("solid_props")
		karst_a_tx.append(Transform3D(Basis(Vector3.UP, sgn_f * 0.42).scaled(Vector3(1.22, 1.34, 1.18)), Vector3(seal_x, seal_gy - 0.25, seal_z + 0.15)))
		karst_b_tx.append(Transform3D(Basis(Vector3.UP, sgn_f * 1.15).scaled(Vector3(1.14, 1.24, 1.12)), Vector3(-41.60 + cdx + sgn_f * 6.45, seal_gy - 0.25, seal_z - 1.15)))

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
	var bluff_dy := cave_y - 6.50
	var bluff_bamboo := [
		Vector3(-44.6 + cdx, 12.15 + bluff_dy, -60.5 + cdz), Vector3(-38.5 + cdx, 12.25 + bluff_dy, -60.8 + cdz),
		Vector3(-45.2 + cdx, 12.10 + bluff_dy, -65.2 + cdz), Vector3(-38.8 + cdx, 12.35 + bluff_dy, -65.6 + cdz),
		Vector3(-42.8 + cdx, 12.20 + bluff_dy, -69.0 + cdz), Vector3(-39.6 + cdx, 12.25 + bluff_dy, -68.6 + cdz)
	]
	for bb in bluff_bamboo:
		maze_clump_tx.append(Transform3D(Basis(Vector3.UP, m_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * 0.78), bb))
	for bf_i in 8:
		var bfx := -41.6 + cdx + cos(float(bf_i) * 0.78) * 3.4
		var bfz := -64.0 + cdz + sin(float(bf_i) * 0.78) * 4.6
		maze_fern_tx.append(Transform3D(Basis(Vector3.UP, float(bf_i) * 1.1).scaled(Vector3.ONE * 1.12), Vector3(bfx, 12.05 + bluff_dy, bfz)))

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

	# 1) Dense batched wild grass tufts ("山野草丛") across the 180x240m Great Yanshan slopes (Vega 8 friendly!)
	var gx_min := float(game.Layout.FENCE_MIN_X) - 2.0
	var gx_max := float(game.Layout.FENCE_MAX_X) + 2.0
	var gz_min := float(game.Layout.FENCE_MIN_Z) - 2.0
	var gz_max := float(game.Layout.FENCE_MAX_Z) + 4.0
	for g_i in 1250:
		var gx := rng.randf_range(gx_min, gx_max)
		var gz := rng.randf_range(gz_min, gz_max)
		if g_i % 2 == 0 and absf(gx) < 52.0 and gz > -176.0 and gz < 26.0:
			gx = (1.0 if g_i % 4 == 0 else -1.0) * rng.randf_range(52.0, gx_max)
		if game.Layout.road_distance(gx, gz, 3.0) < 3.0 or absf(gx - _outer_stream_x(gz)) < 2.35 or game.Layout.is_in_bamboo_cave_zone(gx, gz, 0.4) or game.Layout.is_in_cloud_arena(gx, gz, 0.5):
			continue
		var gy := _surface_height_any(gx, gz) - 0.02
		var gsc := rng.randf_range(0.95, 1.68)
		grass_tx.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(gsc, gsc * rng.randf_range(0.85, 1.20), gsc)), Vector3(gx, gy, gz)))

	# 2) Flowering Azaleas ("映山红灌木"), Woodland Ferns & Wildflowers across mountain slopes & fence edges
	for i in 480:
		var fx := rng.randf_range(gx_min + 1.0, gx_max - 1.0)
		var fz := rng.randf_range(gz_min + 1.0, gz_max - 2.0)
		if i % 3 == 0 and absf(fx) < 48.0 and fz > -170.0 and fz < 24.0:
			fx = (1.0 if i % 6 == 0 else -1.0) * rng.randf_range(48.0, gx_max - 1.0)
		if game.Layout.clear_for_route(fx, fz, 0.7) or absf(fx - _outer_stream_x(fz)) < 2.45:
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

	# 3) Wild-Boar Ambush Thickets
	var boar_thickets := [
		Vector3(-56.0, 0, 18.0), Vector3(62.0, 0, 4.0), Vector3(-76.0, 0, -44.0),
		Vector3(68.0, 0, -110.0), Vector3(-62.0, 0, -142.0)
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
	for l_i in 38:
		var lx := rng.randf_range(gx_min + 4.0, gx_max - 4.0)
		var lz := rng.randf_range(gz_min + 6.0, gz_max - 8.0)
		if l_i % 2 == 0 and absf(lx) < 52.0:
			lx = (1.0 if l_i % 4 == 0 else -1.0) * rng.randf_range(52.0, gx_max - 4.0)
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
		Vector3(21.0, 0, 22.0), Vector3(19.5, 0, -20.0), Vector3(36.0, 0, -34.0),
		Vector3(34.0, 0, -78.0), Vector3(35.0, 0, -118.0), Vector3(36.0, 0, -152.0),
		Vector3(39.0, 0, -172.0), Vector3(-32.0, 0, -126.0), Vector3(-40.0, 0, -40.0),
		Vector3(-42.0, 0, -82.0), Vector3(14.0, 0, 24.0), Vector3(60.0, 0, -122.0)
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
	# Continuous 360-degree mountain timber perimeter fence over 180m x 240m (FENCE_MIN/MAX dynamic!)
	var ring_pts: Array = []
	var fmin_x := float(game.Layout.FENCE_MIN_X)  # -90.0
	var fmax_x := float(game.Layout.FENCE_MAX_X)  # +90.0
	var fmin_z := float(game.Layout.FENCE_MIN_Z)  # -200.0
	var fmax_z := float(game.Layout.FENCE_MAX_Z)  # +40.0
	var span_x := fmax_x - fmin_x
	var span_z := fmax_z - fmin_z

	# 1) North edge (-90 -> +90 at z = -200): 48 bays of 3.75m
	var nbays := 48
	for k in nbays:
		ring_pts.append(Vector2(lerpf(fmin_x, fmax_x, float(k) / float(nbays)), fmin_z))
	# 2) East edge (-200 -> +40 at x = +90): 64 bays of 3.75m
	var ebays := 64
	for k in ebays:
		ring_pts.append(Vector2(fmax_x, lerpf(fmin_z, fmax_z, float(k) / float(ebays))))
	# 3) South edge (+90 -> -90 at z = +40) with dedicated submerged creek pilings framing the outflow brook
	var scx := float(game.Layout.stream_center_x(fmax_z))
	var south_xs: Array[float] = []
	var sx_cur := fmax_x
	while sx_cur > fmin_x + 0.5:
		if absf(sx_cur - scx) > 3.1:
			south_xs.append(sx_cur)
		sx_cur -= 3.75
	for cx_p in [scx + 2.65, scx + 0.90, scx - 0.90, scx - 2.65]:
		south_xs.append(cx_p)
	south_xs.sort()
	south_xs.reverse()
	for sx in south_xs:
		ring_pts.append(Vector2(sx, fmax_z))
	# 4) West edge (+40 -> -200 at x = -90): 64 bays closing seamlessly back to (-90, -200)
	for k in ebays:
		ring_pts.append(Vector2(fmin_x, lerpf(fmax_z, fmin_z, float(k) / float(ebays))))

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

	var mid_z := 0.5 * (fmin_z + fmax_z)
	var mid_x := 0.5 * (fmin_x + fmax_x)
	var walls := [
		[Vector3(fmin_x, 9.0, mid_z), Vector3(0.45, 28.0, span_z + 2.0)],
		[Vector3(fmax_x, 9.0, mid_z), Vector3(0.45, 28.0, span_z + 2.0)],
		[Vector3(mid_x, 12.0, fmin_z), Vector3(span_x + 2.0, 28.0, 0.45)],
		[Vector3(mid_x, 5.0, fmax_z), Vector3(span_x + 2.0, 22.0, 0.45)]
	]
	for w in walls:
		var shape := BoxShape3D.new()
		shape.size = w[1]
		game.Props.shape_body(self, shape, w[0]).name = "FencePerimeterWall"

	signpost(Vector3(-3.5, 0, fmax_z - 3.0), "大烟山观景木栏\n山下稻田 · 诚庄村落 ↓")
	# v0.8.2 V81-3: "东岭梯田观景台" relocated onto WangdaoOverlookTerrace where golden paddies & village are genuinely visible!
