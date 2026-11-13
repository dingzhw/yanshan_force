extends RefCounted
## Realistic procedural PBR materials & multi-part military/expedition 3D props (replaces cartoon flat meshes).

static var _tex_cache := {}
static var _mat_cache := {}

static func _hash01(x: int, y: int, seed_val: int) -> float:
	var n := (x * 374761393 + y * 668265263 + seed_val * 1442695041) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0

static func canvas_texture() -> ImageTexture:
	if _tex_cache.has("canvas"):
		return _tex_cache["canvas"]
	var w := 128
	var h := 128
	var img := Image.create(w, h, true, Image.FORMAT_RGB8)
	for y in h:
		var rain_stain := smoothstep(0.72, 1.0, float(y) / float(h)) * 0.16
		for x in w:
			var warp := 0.035 if (x % 4 < 2) else -0.035
			var weft := 0.030 if (y % 4 < 2) else -0.030
			var grain := (_hash01(x, y, 17) - 0.5) * 0.06
			var seam := -0.10 if (x % 32 == 0 or x % 32 == 1) else (0.05 if x % 32 == 2 else 0.0)
			var stitch := 0.12 if (x % 32 == 3 and y % 6 < 3) else 0.0
			var shade := clampf(1.0 + warp + weft + grain + seam + stitch - rain_stain, 0.62, 1.22)
			img.set_pixel(x, y, Color(0.34 * shade, 0.38 * shade, 0.28 * shade))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["canvas"] = tex
	return tex

static func ripstop_texture(emerald: bool) -> ImageTexture:
	var key := "ripstop_em" if emerald else "ripstop_std"
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 96
	var h := 96
	var img := Image.create(w, h, true, Image.FORMAT_RGB8)
	var base := Color("28473a") if emerald else Color("313d37")
	var accent := Color("1e352b") if emerald else Color("252e2a")
	for y in h:
		for x in w:
			var grid := 0.055 if (x % 6 == 0 or y % 6 == 0) else 0.0
			var patch_val := sin(float(x) * 0.11 + float(y) * 0.07) + cos(float(x - y) * 0.09)
			var c := base.lerp(accent, 0.45 if patch_val > 0.35 else 0.0)
			var n := (_hash01(x, y, 41) - 0.5) * 0.045
			var seam := -0.12 if (x == 47 or x == 48) else 0.0
			var mul := clampf(1.0 + grid + n + seam, 0.72, 1.18)
			img.set_pixel(x, y, Color(c.r * mul, c.g * mul, c.b * mul))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func steel_case_texture(kind: String) -> ImageTexture:
	var key := "case_" + kind
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 128
	var h := 128
	var img := Image.create(w, h, true, Image.FORMAT_RGB8)
	var base := Color("2b3338")
	var rib_tint := Color("20262b")
	var stripe_col := Color("d4a238")
	if kind == "epic":
		base = Color("262334")
		rib_tint = Color("1b1926")
		stripe_col = Color("b674f8")
	elif kind == "supply":
		base = Color("364234")
		rib_tint = Color("283226")
		stripe_col = Color("7bcfa9")
	for y in h:
		var band := (y >= 92 and y <= 106)
		for x in w:
			var c := base
			if y % 16 < 3:
				c = rib_tint
			var brush := (_hash01(x / 3, y, 89) - 0.5) * 0.05
			c = Color(clampf(c.r + brush, 0, 1), clampf(c.g + brush, 0, 1), clampf(c.b + brush, 0, 1))
			if band and ((x + y) / 10) % 2 == 0:
				c = c.lerp(stripe_col, 0.78)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func canvas_material() -> StandardMaterial3D:
	if not _mat_cache.has("canvas"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = canvas_texture()
		m.uv1_scale = Vector3(3.0, 2.5, 1.0)
		m.roughness = 0.93
		m.metallic = 0.02
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache["canvas"] = m
	return _mat_cache["canvas"]

static func dark_steel_material() -> StandardMaterial3D:
	if not _mat_cache.has("dark_steel"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("252c2f")
		m.metallic = 0.68
		m.roughness = 0.42
		_mat_cache["dark_steel"] = m
	return _mat_cache["dark_steel"]

static func brushed_metal_material(hex_col: String, met := 0.62, rough := 0.38) -> StandardMaterial3D:
	var key := "metal_" + hex_col
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex_col)
		m.metallic = met
		m.roughness = rough
		_mat_cache[key] = m
	return _mat_cache[key]

static func build_command_tent(parent: Node3D, game, at: Vector3, yaw_angle: float) -> Node3D:
	## Walkable weathered olive-canvas command tent with steel frame, timber duckboards, camp lantern & map table.
	var root := Node3D.new()
	var ground_y: float = game.Layout.min_ground_height(at.x, at.z, 2.5) - 0.04
	root.position = Vector3(at.x, ground_y, at.z)
	root.rotation.y = yaw_angle
	root.set_meta("kind", "tent")
	parent.add_child(root)

	var c_mat := canvas_material()
	var s_mat := dark_steel_material()
	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("7b674c")
	wood_mat.albedo_texture = bark_tex
	wood_mat.uv1_scale = Vector3(2, 1, 1)
	wood_mat.roughness = 0.86

	# Timber duckboard floor slats
	for i in 7:
		var z_off := -2.0 + float(i) * 0.66
		var slat = game._mesh_box(root, Vector3(0, 0.04, z_off), Vector3(3.4, 0.05, 0.48), Color.WHITE)
		slat.material_override = wood_mat

	# Steel tubular A-frame poles (front, center, rear) + ridgepole
	for z_p in [-2.35, 0.0, 2.35]:
		for side in [-1.0, 1.0]:
			var upright = game._mesh_box(root, Vector3(side * 1.92, 0.72, z_p), Vector3(0.08, 1.48, 0.08), Color.WHITE)
			upright.material_override = s_mat
			var rafter = game._mesh_box(root, Vector3(side * 0.98, 2.08, z_p), Vector3(2.22, 0.07, 0.07), Color.WHITE)
			rafter.rotation.z = -side * 0.58
			rafter.material_override = s_mat
	var ridge = game._mesh_box(root, Vector3(0, 2.72, 0), Vector3(0.09, 0.09, 4.95), Color.WHITE)
	ridge.material_override = s_mat

	# Sloped heavy canvas roof panels + side skirt walls (collidable so side walls block capsule & bullets)
	for side in [-1.0, 1.0]:
		var wall = game._mesh_box(root, Vector3(side * 1.90, 0.74, 0), Vector3(0.10, 1.48, 4.78), Color.WHITE, true)
		wall.material_override = c_mat
		var slope = game._mesh_box(root, Vector3(side * 1.02, 2.08, 0), Vector3(2.26, 0.08, 4.92), Color.WHITE, true)
		slope.rotation.z = -side * 0.58
		slope.material_override = c_mat
		# Exterior tension guy ropes & steel ground pegs
		for z_peg in [-1.8, 0.0, 1.8]:
			var rope = game._mesh_box(root, Vector3(side * 2.28, 0.68, z_peg), Vector3(0.95, 0.02, 0.02), Color("595343"))
			rope.rotation.z = -side * 0.85
			var peg = game._mesh_box(root, Vector3(side * 2.62, 0.14, z_peg), Vector3(0.05, 0.32, 0.05), Color.WHITE)
			peg.rotation.z = side * 0.32
			peg.material_override = s_mat

	# Rear closed canvas wall (+Z local = back; -Z local = walkable front entrance facing camp)
	var rear_lower = game._mesh_box(root, Vector3(0, 0.74, 2.34), Vector3(3.76, 1.48, 0.10), Color.WHITE, true)
	rear_lower.material_override = c_mat
	var rear_gable = game._mesh_box(root, Vector3(0, 1.92, 2.34), Vector3(2.10, 0.96, 0.08), Color.WHITE, true)
	rear_gable.material_override = c_mat

	# Rolled-up front entrance flaps (-Z local) leaving a clear 2.3m wide walkable doorway
	for side in [-1.0, 1.0]:
		var flap = game._mesh_box(root, Vector3(side * 1.52, 0.92, -2.36), Vector3(0.72, 1.78, 0.10), Color.WHITE, true)
		flap.material_override = c_mat
		var roll := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.11
		cyl.bottom_radius = 0.11
		cyl.height = 1.75
		roll.mesh = cyl
		roll.position = Vector3(side * 1.16, 0.92, -2.41)
		roll.material_override = c_mat
		root.add_child(roll)
	var header_valance = game._mesh_box(root, Vector3(0, 1.96, -2.36), Vector3(2.26, 0.30, 0.08), Color.WHITE)
	header_valance.material_override = c_mat

	# Interior tactical briefing table + glowing field map & warm camp lantern
	var desk = game._mesh_box(root, Vector3(0, 0.78, 1.35), Vector3(1.85, 0.08, 0.82), Color.WHITE, true)
	desk.material_override = wood_mat
	for lx in [-0.78, 0.78]:
		var dleg = game._mesh_box(root, Vector3(lx, 0.38, 1.35), Vector3(0.09, 0.76, 0.66), Color.WHITE)
		dleg.material_override = s_mat
	var map_sheet = game._mesh_box(root, Vector3(-0.18, 0.83, 1.35), Vector3(0.92, 0.015, 0.56), Color("d5d8c2"))
	map_sheet.material_override.roughness = 0.9
	var laptop = game._mesh_box(root, Vector3(0.54, 0.92, 1.28), Vector3(0.36, 0.22, 0.03), Color("5fe0b4"))
	laptop.rotation.x = -0.25
	laptop.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var lamp_bulb = game._mesh_box(root, Vector3(0, 2.48, 0.15), Vector3(0.16, 0.12, 0.16), Color("ffe39e"))
	lamp_bulb.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var camp_light := OmniLight3D.new()
	camp_light.position = Vector3(0, 2.25, 0.15)
	camp_light.light_color = Color("ffdca2")
	camp_light.light_energy = 0.85
	camp_light.omni_range = 5.5
	root.add_child(camp_light)

	var sign_lbl = game._label3d(root, "烟山前线指挥帐篷", Vector3(0, 1.96, -2.42), 24, Color("f0e8c6"))
	sign_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_lbl.rotation.y = PI
	return root

static func build_fuel_drum(parent: Node3D, game, at: Vector3, olive := true) -> Node3D:
	var root := Node3D.new()
	var gy: float = game.Layout.min_ground_height(at.x, at.z, 0.35) - 0.02
	root.position = Vector3(at.x, gy, at.z)
	parent.add_child(root)

	var drum_mat := StandardMaterial3D.new()
	drum_mat.albedo_texture = steel_case_texture("supply" if olive else "std")
	drum_mat.albedo_color = Color("7b8c74") if olive else Color("8a7c68")
	drum_mat.metallic = 0.55
	drum_mat.roughness = 0.52

	var body_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.30
	cyl.bottom_radius = 0.30
	cyl.height = 0.92
	cyl.radial_segments = 16
	body_mesh.mesh = cyl
	body_mesh.position = Vector3(0, 0.46, 0)
	body_mesh.material_override = drum_mat
	root.add_child(body_mesh)

	for ry in [0.04, 0.32, 0.62, 0.90]:
		var hoop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.292
		torus.outer_radius = 0.316
		torus.rings = 16
		torus.ring_segments = 8
		hoop.mesh = torus
		hoop.position = Vector3(0, ry, 0)
		hoop.material_override = dark_steel_material()
		root.add_child(hoop)

	var shape := CylinderShape3D.new()
	shape.radius = 0.31
	shape.height = 0.94
	game.Props.shape_body(root, shape, Vector3(0, 0.47, 0))
	return root

static func build_armory_workbench(parent: Node3D, game, at: Vector3, yaw_angle: float) -> Node3D:
	var root := Node3D.new()
	var gy: float = game.Layout.min_ground_height(at.x, at.z, 0.8) - 0.02
	root.position = Vector3(at.x, gy, at.z)
	root.rotation.y = yaw_angle
	parent.add_child(root)

	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("846d50")
	wood_mat.albedo_texture = bark_tex
	wood_mat.uv1_scale = Vector3(2, 1, 1)
	wood_mat.roughness = 0.82
	var s_mat := dark_steel_material()

	var top = game._mesh_box(root, Vector3(0, 0.86, 0), Vector3(1.95, 0.08, 0.78), Color.WHITE, true)
	top.material_override = wood_mat
	var shelf = game._mesh_box(root, Vector3(0, 0.24, 0), Vector3(1.82, 0.05, 0.66), Color.WHITE)
	shelf.material_override = s_mat
	for lx in [-0.88, 0.88]:
		for lz in [-0.32, 0.32]:
			var leg = game._mesh_box(root, Vector3(lx, 0.43, lz), Vector3(0.07, 0.86, 0.07), Color.WHITE, true)
			leg.material_override = s_mat
	var pegboard = game._mesh_box(root, Vector3(0, 1.32, 0.35), Vector3(1.88, 0.82, 0.05), Color.WHITE, true)
	pegboard.material_override = s_mat
	if ResourceLoader.exists("res://assets/slice/crate.glb"):
		game._model(root, "res://assets/slice/crate.glb", Vector3(-0.42, 0.90, -0.02), 0.30, 0.12)
	var radio = game._mesh_box(root, Vector3(0.52, 1.01, 0.02), Vector3(0.42, 0.22, 0.28), Color.WHITE)
	radio.material_override = brushed_metal_material("38463e", 0.55, 0.45)
	var dial = game._mesh_box(root, Vector3(0.52, 1.03, -0.13), Vector3(0.26, 0.10, 0.02), Color("74f0c2"))
	dial.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return root

static func build_supply_box(game, pickup: Node3D):
	## Realistic military field supply box with PBR crate + corner brackets + cyan single-word keypad lock.
	if ResourceLoader.exists("res://assets/slice/crate.glb"):
		game._model(pickup, "res://assets/slice/crate.glb", Vector3.ZERO, 0.46, 0)
	else:
		var fallback = game._mesh_box(pickup, Vector3(0, 0.23, 0), Vector3(0.80, 0.46, 0.50), Color.WHITE)
		var fb_mat := StandardMaterial3D.new()
		fb_mat.albedo_texture = steel_case_texture("supply")
		fallback.material_override = fb_mat

	var s_mat := dark_steel_material()
	for sx in [-0.26, 0.26]:
		var strap = game._mesh_box(pickup, Vector3(sx, 0.24, 0), Vector3(0.045, 0.48, 0.50), Color.WHITE)
		strap.material_override = s_mat

	# Top electronic single-word lock module
	var pad_base = game._mesh_box(pickup, Vector3(0, 0.48, 0.04), Vector3(0.28, 0.05, 0.18), Color.WHITE)
	pad_base.material_override = s_mat
	var pad_screen = game._mesh_box(pickup, Vector3(0, 0.51, 0.04), Vector3(0.20, 0.015, 0.11), Color("6be6c4"))
	pad_screen.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Solid blocking collider toggled cleanly via Props.set_enabled(pickup, bool)
	var box := BoxShape3D.new()
	box.size = Vector3(0.84, 0.52, 0.54)
	game.Props.shape_body(pickup, box, Vector3(0, 0.26, 0))

static func build_tiered_vault_crate(game, crate: Node3D, tier: int):
	## Visually distinct Tier 1 (Outpost Crate), Tier 2 (Armored Epic Vault), Tier 3 (Gold Legendary Airdrop Pod).
	for child in crate.get_children():
		if not (child is Label3D):
			game.Props.set_enabled(child, false)
			child.queue_free()

	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	var pallet_mat := StandardMaterial3D.new()
	pallet_mat.albedo_color = Color("6e5c44")
	pallet_mat.albedo_texture = bark_tex
	pallet_mat.roughness = 0.88
	var s_mat := dark_steel_material()

	if tier <= 1:
		# Tier 1: Military crate on timber pallet + dual steel lock bars + mint keypad
		var plinth1 = game._mesh_box(crate, Vector3(0, -0.10, 0), Vector3(1.14, 0.22, 0.76), Color.WHITE)
		plinth1.material_override = pallet_mat
		for px in [-0.42, 0.0, 0.42]:
			var runner = game._mesh_box(crate, Vector3(px, 0.04, 0), Vector3(0.12, 0.08, 0.78), Color.WHITE)
			runner.material_override = pallet_mat
		var deck = game._mesh_box(crate, Vector3(0, 0.09, 0), Vector3(1.18, 0.04, 0.80), Color.WHITE)
		deck.material_override = pallet_mat
		if ResourceLoader.exists("res://assets/slice/crate.glb"):
			game._model(crate, "res://assets/slice/crate.glb", Vector3(0, 0.11, 0), 0.66, 0)
		for sx in [-0.34, 0.34]:
			var bar = game._mesh_box(crate, Vector3(sx, 0.45, 0), Vector3(0.05, 0.68, 0.68), Color.WHITE)
			bar.material_override = s_mat
		var lock_led = game._mesh_box(crate, Vector3(0, 0.79, 0.22), Vector3(0.34, 0.06, 0.14), Color("74e3a3"))
		lock_led.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.20, 0.82, 0.82)
		game.Props.shape_body(crate, shape, Vector3(0, 0.41, 0))
	elif tier == 2:
		# Tier 2: Heavy Pelican-style armored gunmetal & violet holographic vault case
		var case_mat := StandardMaterial3D.new()
		case_mat.albedo_texture = steel_case_texture("epic")
		case_mat.metallic = 0.62
		case_mat.roughness = 0.38
		var trim_mat := brushed_metal_material("3d3852", 0.72, 0.32)

		var base_skid = game._mesh_box(crate, Vector3(0, -0.04, 0), Vector3(1.36, 0.32, 0.88), Color.WHITE)
		base_skid.material_override = s_mat
		var hull = game._mesh_box(crate, Vector3(0, 0.44, 0), Vector3(1.28, 0.64, 0.80), Color.WHITE)
		hull.material_override = case_mat
		var lid = game._mesh_box(crate, Vector3(0, 0.80, 0), Vector3(1.34, 0.14, 0.86), Color.WHITE)
		lid.material_override = trim_mat
		crate.set_meta("lid_node", lid)
		for lx in [-0.42, 0.0, 0.42]:
			var latch = game._mesh_box(crate, Vector3(lx, 0.68, 0.42), Vector3(0.10, 0.18, 0.05), Color.WHITE)
			latch.material_override = brushed_metal_material("9ba4b0", 0.82, 0.28)
		var seal = game._mesh_box(crate, Vector3(0, 0.74, 0.43), Vector3(1.16, 0.045, 0.03), Color("cf8aff"))
		seal.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var holo = game._mesh_box(crate, Vector3(0, 0.90, 0.16), Vector3(0.46, 0.06, 0.24), Color("cf8aff"))
		holo.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var shape2 := BoxShape3D.new()
		shape2.size = Vector3(1.36, 0.92, 0.88)
		game.Props.shape_body(crate, shape2, Vector3(0, 0.46, 0))
	else:
		# Tier 3: Legendary Gold-Trimmed Heavy Airdrop Vault Pod (with beacon light & shock skids)
		var pod_mat := StandardMaterial3D.new()
		pod_mat.albedo_texture = steel_case_texture("std")
		pod_mat.metallic = 0.68
		pod_mat.roughness = 0.34
		var gold_armor := brushed_metal_material("c89b3c", 0.82, 0.26)

		var under_plinth = game._mesh_box(crate, Vector3(0, -0.08, 0), Vector3(1.44, 0.28, 0.92), Color.WHITE)
		under_plinth.material_override = s_mat
		for sz in [-0.44, 0.44]:
			var skid = game._mesh_box(crate, Vector3(0, 0.02, sz), Vector3(1.54, 0.24, 0.16), Color.WHITE)
			skid.material_override = s_mat
		var core_hull = game._mesh_box(crate, Vector3(0, 0.54, 0), Vector3(1.40, 0.82, 0.96), Color.WHITE)
		core_hull.material_override = pod_mat
		for cx in [-0.68, 0.68]:
			for cz in [-0.46, 0.46]:
				var bumper = game._mesh_box(crate, Vector3(cx, 0.56, cz), Vector3(0.14, 0.88, 0.14), Color.WHITE)
				bumper.material_override = gold_armor
		var top_cap = game._mesh_box(crate, Vector3(0, 1.00, 0), Vector3(1.46, 0.14, 1.02), Color.WHITE)
		top_cap.material_override = gold_armor
		crate.set_meta("lid_node", top_cap)
		for z_face in [-0.49, 0.49]:
			var band = game._mesh_box(crate, Vector3(0, 0.78, z_face), Vector3(1.24, 0.06, 0.03), Color("ffd15c"))
			band.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var beacon = game._mesh_box(crate, Vector3(0, 1.14, 0), Vector3(0.28, 0.14, 0.28), Color("ffd86b"))
		beacon.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var pod_light := OmniLight3D.new()
		pod_light.position = Vector3(0, 1.32, 0)
		pod_light.light_color = Color("ffd369")
		pod_light.light_energy = 0.95
		pod_light.omni_range = 4.6
		crate.add_child(pod_light)
		var shape3 := BoxShape3D.new()
		shape3.size = Vector3(1.50, 1.14, 1.04)
		game.Props.shape_body(crate, shape3, Vector3(0, 0.57, 0))

	# Keep 3D floating tag at the end of children list & raised above pod height
	for child in crate.get_children():
		if child is Label3D:
			child.position.y = 1.98 if tier >= 3 else (1.76 if tier == 2 else 1.66)
			crate.move_child(child, crate.get_child_count() - 1)
			break

static func attach_parkour_asset(parent: Node3D, game, mesh_name: String, at: Vector3, yaw := 0.0, scale_vec := Vector3.ONE) -> Node3D:
	var path := "res://assets/slice/parkour_intel_assets.glb"
	if not ResourceLoader.exists(path):
		return null
	if not game.scene_cache.has(path):
		game.scene_cache[path] = load(path)
	var inst: Node3D = game.scene_cache[path].instantiate()
	var sub = inst.find_child(mesh_name, true, false)
	if not is_instance_valid(sub):
		inst.queue_free()
		return null
	inst.remove_child(sub)
	sub.owner = null
	sub.position = at
	sub.rotation.y = yaw
	sub.scale = scale_vec
	parent.add_child(sub)
	inst.queue_free()
	return sub

static func build_parkour_step(parent: Node3D, game, center_top: Vector3, size_xz: Vector2, deck_h := 0.14, support_drop := 0.6, use_wood := true, accent_stripe := true):
	var bark_tex = load("res://assets/slice/tree_bark.jpg")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("867052") if use_wood else Color("54635c")
	mat.albedo_texture = bark_tex
	mat.uv1_scale = Vector3(2, 1, 1)
	mat.roughness = 0.85 if use_wood else 0.58
	mat.metallic = 0.04 if use_wood else 0.42

	var deck = game._mesh_box(parent, Vector3(center_top.x, center_top.y - deck_h * 0.5, center_top.z), Vector3(size_xz.x, deck_h, size_xz.y), Color.WHITE, true)
	deck.material_override = mat
	if accent_stripe:
		var edge = game._mesh_box(parent, Vector3(center_top.x, center_top.y - deck_h * 0.45, center_top.z + size_xz.y * 0.47), Vector3(size_xz.x * 0.94, 0.04, 0.05), Color("e5c158"))
		edge.material_override.roughness = 0.45
	if support_drop > 0.18:
		var leg_h := support_drop
		for sx in [-size_xz.x * 0.36, size_xz.x * 0.36]:
			for sz in [-size_xz.y * 0.36, size_xz.y * 0.36]:
				var post = game._mesh_box(parent, Vector3(center_top.x + sx, center_top.y - deck_h - leg_h * 0.5, center_top.z + sz), Vector3(0.11, leg_h, 0.11), Color.WHITE, false)
				post.material_override = dark_steel_material() if not use_wood else brushed_metal_material("4b4032", 0.15, 0.85)

static func build_cargo_container_yard(parent: Node3D, game, center_ground: Vector3) -> Dictionary:
	## Route A: Military ISO cargo container stack parkour (max step dy = 0.58m -> top at y = +2.86m).
	var root := Node3D.new()
	root.position = center_ground
	parent.add_child(root)

	# Step 1: Stepping Stone (top = 0.56m)
	build_parkour_step(root, game, Vector3(3.6, 0.56, 3.0), Vector2(1.65, 1.65), 0.22, 0.65, false, true)
	# Step 2: Wooden Supply Stack (top = 1.14m)
	var plinth = game._mesh_box(root, Vector3(1.85, 0.55, 3.0), Vector3(1.55, 1.14, 1.55), Color("6e5b42"), true)
	plinth.material_override = brushed_metal_material("6e5b42", 0.08, 0.86)
	build_parkour_step(root, game, Vector3(1.85, 1.14, 3.0), Vector2(1.62, 1.62), 0.10, 0.0, true, true)

	# Step 3: Lower Olive Cargo Container (0..1.14m tall at (0, 0, 1.45), size 4.2 x 2.0) -> wait jump from 1.14 to 1.72!
	# Put Lower Container on sturdy concrete/timber cribbing pads (y = 0.56..1.70 -> deck top = 1.70m!)
	var crib_mat := dark_steel_material()
	for cx in [-1.65, 1.65]:
		var crib = game._mesh_box(root, Vector3(cx, 0.26, 1.55), Vector3(0.65, 0.60, 1.85), Color.WHITE, true)
		crib.material_override = crib_mat
	var c1 = attach_parkour_asset(root, game, "prop_cargo_container", Vector3(0.0, 0.56, 1.55), 0.0, Vector3.ONE)
	if c1 == null:
		game._mesh_box(root, Vector3(0.0, 1.13, 1.55), Vector3(4.20, 1.14, 2.00), Color("3c4f3d"), true)
	var col1 := BoxShape3D.new()
	col1.size = Vector3(4.20, 1.14, 2.00)
	game.Props.shape_body(root, col1, Vector3(0.0, 1.13, 1.55))

	# Step 4: Mid Catwalk Platform (top = 2.28m, bridging left end of lower container to upper deck)
	build_parkour_step(root, game, Vector3(-2.55, 2.28, -0.35), Vector2(1.60, 1.70), 0.14, 2.35, true, true)

	# Step 5: Upper Stacked Container on timber/steel trestle (y = 1.72..2.86 -> top deck = 2.86m!)
	for cx in [-1.65, 1.65]:
		var legs = game._mesh_box(root, Vector3(-0.30 + cx, 0.86, -1.35), Vector3(0.62, 1.76, 1.85), Color.WHITE, true)
		legs.material_override = crib_mat
	var c2 = attach_parkour_asset(root, game, "prop_cargo_container", Vector3(-0.30, 1.72, -1.35), 0.0, Vector3.ONE)
	if c2 == null:
		game._mesh_box(root, Vector3(-0.30, 2.29, -1.35), Vector3(4.20, 1.14, 2.00), Color("3c4f3d"), true)
	var col2 := BoxShape3D.new()
	col2.size = Vector3(4.20, 1.14, 2.00)
	game.Props.shape_body(root, col2, Vector3(-0.30, 2.29, -1.35))

	return {
		"mid_deck": center_ground + Vector3(0.35, 1.70, 2.15),
		"top_deck": center_ground + Vector3(-0.20, 2.86, -1.35),
		"ammo_spot": center_ground + Vector3(-1.45, 2.86, -1.35)
	}

static func build_cave_grotto(parent: Node3D, game, center_ground: Vector3):
	## Deep mossy cliff grotto housing the Tier-3 Legendary Airdrop Vault (open along +Z for clean entry).
	var root := Node3D.new()
	root.position = center_ground
	parent.add_child(root)

	var west_path := "res://assets/slice/rock_3.glb"
	var cliff_path := "res://assets/slice/rock_4.glb"
	var step_path := "res://assets/nature/rock_smallFlatA.glb" if ResourceLoader.exists("res://assets/nature/rock_smallFlatA.glb") else "res://assets/slice/rock_1.glb"

	# Left, Right & Back cliff walls framing a spacious mossy cavern (inner chamber >= 4.0m wide, mouth open toward +Z)
	game._model(root, west_path, Vector3(-4.1, -0.35, -0.4), 3.2, 0.4, "convex")
	game._model(root, cliff_path, Vector3(4.1, -0.35, -0.4), 2.4, -0.3, "convex")
	game._model(root, west_path, Vector3(-1.8, -0.35, -3.6), 3.4, 1.1, "convex")
	game._model(root, west_path, Vector3(1.8, -0.35, -3.6), 3.4, -1.0, "convex")
	# Upper overhang stone lintel slab (high above player eye level y >= 2.8m) with mossy rock cap texture
	var lintel_mat := StandardMaterial3D.new()
	lintel_mat.albedo_color = Color("767a68")
	lintel_mat.albedo_texture = load("res://assets/slice/ground_color.jpg")
	lintel_mat.normal_enabled = true
	lintel_mat.normal_texture = load("res://assets/slice/ground_normal.jpg")
	lintel_mat.uv1_scale = Vector3(2.4, 1.8, 2.0)
	lintel_mat.roughness = 0.92
	var cap = game._mesh_box(root, Vector3(0.0, 3.30, -1.65), Vector3(6.8, 0.85, 3.4), Color.WHITE, true)
	cap.rotation.x = 0.08
	cap.material_override = lintel_mat
	game._model(root, cliff_path, Vector3(0.0, 3.05, -1.75), 1.9, 0.15, "none")
	# Side stepping flat trail stones outside the mouth
	game._model(root, step_path, Vector3(3.4, -0.02, 2.2), 0.16, 0.2, "convex")
	game._model(root, step_path, Vector3(2.4, -0.01, 3.4), 0.15, -0.4, "convex")

	# Cave lantern + warm amber point light inside cavern mouth
	attach_parkour_asset(root, game, "prop_cave_lantern", Vector3(-1.75, 0.0, 0.55), 0.3, Vector3.ONE * 1.15)
	var cave_light := OmniLight3D.new()
	cave_light.position = Vector3(-0.6, 1.65, -0.25)
	cave_light.light_color = Color("ffc26e")
	cave_light.light_energy = 1.25
	cave_light.omni_range = 6.8
	root.add_child(cave_light)
