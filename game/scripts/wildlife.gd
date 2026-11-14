extends Node3D
## Living Yanshan Mountain ecosystem (8 community/Blender species: rabbits, squirrels, bush-ambush wild boars,
## red foxes, tree-perching birds & creek egrets, brook koi, creek crabs, and freshwater river shrimp)
## plus 8 interactive English botanical study specimens.

var game
var animals: Array = []
var sky_egrets: Array = []
var flora_nodes: Array = []
var discovered_species: Dictionary = {}
var collected_flora: Dictionary = {}
var hit_fx: Array = []
var flee_sfx_cooldown := 0.0
var rng := RandomNumberGenerator.new()

const HIT_LAYER := 16  # Dedicated bit 4 (isolated from player mask 1|4 and enemy mask 7)
const TOTAL_SPECIES := 8

const FLORA_SPOTS := [
	{"id": "flora_camp_orchid", "pos": Vector3(13.5, 0, 5.2), "kind": "orchid", "en": "Wild Orchid", "zh": "溪畔幽兰", "tts": "wild orchid", "sentence": "Wild orchids grow beside the clear mountain stream.", "heal": 6},
	{"id": "flora_bridge_lily", "pos": Vector3(15.2, 0, -21.5), "kind": "lily", "en": "Water Lily", "zh": "石桥睡莲", "tts": "water lily", "sentence": "Green water lilies float quietly near the stone bridge.", "heal": 5},
	{"id": "flora_forest_mushroom", "pos": Vector3(-19.5, 0, -31.5), "kind": "mushroom", "en": "Red Mushroom", "zh": "红伞山菌", "tts": "red mushroom", "sentence": "Bright red mushrooms grow under tall shady camphor trees.", "heal": 5},
	{"id": "flora_west_lavender", "pos": Vector3(-24.8, 0, -14.2), "kind": "purple_flower", "en": "Mountain Lavender", "zh": "山坡紫花", "tts": "purple flower", "sentence": "Purple flowers bloom beside the green cargo crates.", "heal": 5},
	{"id": "flora_overlook_berry", "pos": Vector3(23.8, 0, -26.5), "kind": "berry_fern", "en": "Mountain Berry", "zh": "朱果奇草", "tts": "mountain berry", "sentence": "Curious fern berries shine orange on the east ridge.", "heal": 8},
	{"id": "flora_cave_orchid", "pos": Vector3(-21.2, 0, -65.0), "kind": "orchid", "en": "Cave Orchid", "zh": "石窟夜光兰", "tts": "cave orchid", "sentence": "A glowing purple orchid blooms in front of the rock cave.", "heal": 8},
	{"id": "flora_radio_goldflower", "pos": Vector3(24.5, 0, -49.5), "kind": "yellow_flower", "en": "Golden Marigold", "zh": "金盏野花", "tts": "yellow flower", "sentence": "Yellow flowers wave near the East Recon Radio.", "heal": 5},
	{"id": "flora_bamboo_fern", "pos": Vector3(20.6, 0, -83.5), "kind": "berry_fern", "en": "Bamboo Herb", "zh": "竹海灵草", "tts": "green herb", "sentence": "Fresh green herbs hide beside the cool east stream.", "heal": 8}
]

const HABITAT_ANIMALS := [
	# 1. Little Rabbits (8 — meadows, creek lawns & East/West/South fence slopes)
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(9.6, 0, 12.8)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-11.0, 0, -6.5)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-22.5, 0, -24.5)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(24.5, 0, -34.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(13.5, 0, -70.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-18.5, 0, -90.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-43.5, 0, 16.5)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(44.0, 0, -14.0)},

	# 2. Red Squirrels (7 — woodland trunks, bamboo groves & perimeter slopes)
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-15.5, 0, -5.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-27.5, 0, -19.5)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(22.5, 0, -41.5)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(28.0, 0, -62.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-30.0, 0, -94.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(43.5, 0, 9.5)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-44.0, 0, -56.0)},

	# 3. Bush-Ambush Wild Boars (5 — hidden in flowering azalea thickets on East/West slopes; burst out when approached!)
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(-38.5, 0, 11.5)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(39.5, 0, 2.5)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(-40.0, 0, -40.5)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(38.5, 0, -68.5)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(-37.5, 0, -82.0)},

	# 4. Agile Red Foxes (5 — patrolling fence-side grassy slopes & bamboo edges)
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-20.0, 0, 20.5)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(44.5, 0, -28.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-44.5, 0, -22.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(43.5, 0, -88.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-16.0, 0, -106.0)},

	# 5. Tree-Perching Songbirds & Creek Egrets (9 — perched on fence posts, tree branches & wading by creek)
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(-3.25, 0, 25.8), "perch_h": 1.28},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(22.75, 0, 25.8), "perch_h": 1.28},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(-16.6, 0, -4.0), "perch_h": 3.25},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(11.0, 0, -16.5), "perch_h": 3.45},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(46.0, 0, -19.5), "perch_h": 2.85},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(-36.5, 0, -30.0), "perch_h": 3.15},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(20.1, 0, 16.5), "perch_h": 0.04},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(15.0, 0, -16.5), "perch_h": 0.04},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(20.2, 0, -58.5), "perch_h": 0.04},

	# 6. Brook Koi / Carp (7 — swimming in clear recessed pebble creek pools)
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": 21.5, "lane": -0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": 12.5, "lane": 0.40},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": 1.5, "lane": -0.38},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -15.0, "lane": 0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -33.0, "lane": -0.40},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -56.0, "lane": 0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -84.0, "lane": -0.35},

	# 7. Creek Rock Crabs (5 — scuttling along wet pebble shorelines)
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": 18.2, "bank_side": -1.48},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": 9.2, "bank_side": 1.50},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -20.5, "bank_side": 1.52},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -43.5, "bank_side": -1.48},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -76.0, "bank_side": 1.50},

	# 8. Freshwater Jade River Shrimp (6 — hovering over pebbles & tail-flipping backward when startled!)
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": 20.0, "lane": 0.45},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": 14.2, "lane": -0.48},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -8.5, "lane": 0.42},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -29.5, "lane": -0.44},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -51.0, "lane": 0.46},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -89.0, "lane": -0.42}
]

func setup(g):
	game = g
	rng.seed = 20261115
	_spawn_wildlife()
	_spawn_sky_egrets()
	_spawn_flora_spots()
	reset()

func _polish_critter_materials(node: Node3D):
	if node == null:
		return
	var targets: Array = []
	if node is MeshInstance3D:
		targets.append(node)
	targets.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for t in targets:
		var mi := t as MeshInstance3D
		if mi and mi.mesh:
			var dup_mesh: Mesh = mi.mesh.duplicate()
			for s in dup_mesh.get_surface_count():
				var fmt: int = int(dup_mesh.surface_get_format(s))
				var has_vcol: bool = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0
				var mat: Material = dup_mesh.surface_get_material(s)
				var bmat: BaseMaterial3D = null
				if mat is BaseMaterial3D:
					bmat = mat.duplicate() as BaseMaterial3D
				elif has_vcol:
					bmat = StandardMaterial3D.new()
					bmat.roughness = 0.86
				if bmat != null:
					if has_vcol:
						bmat.vertex_color_use_as_albedo = true
					bmat.metallic = 0.0
					bmat.metallic_specular = 0.12
					dup_mesh.surface_set_material(s, bmat)
			mi.mesh = dup_mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 74.0

func _instantiate_bundle_mesh(glb_path: String, mesh_name: String) -> Node3D:
	if ResourceLoader.exists(glb_path):
		if not game.scene_cache.has(glb_path):
			game.scene_cache[glb_path] = load(glb_path)
		var inst: Node3D = game.scene_cache[glb_path].instantiate()
		var sub = inst.find_child(mesh_name, true, false)
		if is_instance_valid(sub):
			if sub.get_parent():
				sub.get_parent().remove_child(sub)
			sub.owner = null
			sub.position = Vector3.ZERO
			_polish_critter_materials(sub)
			inst.queue_free()
			return sub
		inst.queue_free()
	return null

func _instantiate_animal_mesh(mesh_name: String) -> Node3D:
	var n := _instantiate_bundle_mesh("res://assets/slice/v061_nature_wildlife.glb", mesh_name)
	if n != null:
		return n
	return _instantiate_bundle_mesh("res://assets/slice/v055_eco_assets.glb", mesh_name)

func _instantiate_eco_mesh(mesh_name: String) -> Node3D:
	return _instantiate_bundle_mesh("res://assets/slice/v055_eco_assets.glb", mesh_name)

func _species_scale(kind: String, mesh_name: String) -> float:
	match kind:
		"rabbit": return 1.08
		"squirrel": return 0.96
		"boar": return 1.14
		"fox": return 1.12
		"bird": return 1.18 if mesh_name == "animal_egret" else 0.98
		"fish": return 1.05
		"crab": return 0.94
		"shrimp": return 0.80
	return 1.0

func _spawn_wildlife():
	for idx in HABITAT_ANIMALS.size():
		var spec: Dictionary = HABITAT_ANIMALS[idx]
		var kind := str(spec.kind)
		var mesh_name := str(spec.get("mesh", "animal_" + kind))
		var root := Node3D.new()
		root.name = "Critter_%s_%d" % [kind, idx]
		add_child(root)

		var visual := _instantiate_animal_mesh(mesh_name)
		if visual == null:
			visual = MeshInstance3D.new()
			var cap := BoxMesh.new()
			cap.size = Vector3(0.28, 0.24, 0.34)
			visual.mesh = cap
		var sc := _species_scale(kind, mesh_name)
		visual.scale = Vector3.ONE * sc
		root.add_child(visual)

		var area := Area3D.new()
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("critter_index", idx)
		var shp := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.62 if kind in ["boar", "fox"] else 0.48
		shp.shape = sph
		shp.position.y = 0.0 if kind in ["fish", "shrimp"] else 0.28
		area.add_child(shp)
		root.add_child(area)

		var tag_y := 0.54 if kind in ["fish", "shrimp", "crab"] else (0.94 if kind == "boar" else 0.76)
		var lbl: Label3D = game._label3d(root, "%s · %s" % [spec.en, spec.zh], Vector3(0, tag_y, 0), 20, Color("f2f7d4"))
		lbl.visibility_range_end = 10.5

		var home := _initial_pos(spec)
		var init_state := "ambush" if kind == "boar" else "idle"
		var entry := {
			"idx": idx,
			"kind": kind,
			"mesh_name": mesh_name,
			"en": str(spec.en),
			"zh": str(spec.zh),
			"tts": str(spec.tts),
			"root": root,
			"visual": visual,
			"area": area,
			"label": lbl,
			"home": home,
			"perch_h": float(spec.get("perch_h", 0.0)),
			"stream_z": float(spec.get("stream_z", 0.0)),
			"lane": float(spec.get("lane", 0.0)),
			"bank_side": float(spec.get("bank_side", -1.5)),
			"pos": home,
			"dir": Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(),
			"state": init_state,  # idle, ambush, flee, fly, downed, hidden
			"timer": 0.0,
			"phase": rng.randf_range(0.0, TAU),
			"wander_cd": rng.randf_range(0.8, 3.2),
			"visual_scale": sc,
			"fly_alt": 0.0
		}
		animals.append(entry)

func _spawn_sky_egrets():
	# Ambient flock of 5 white Jiangnan egrets soaring peacefully over the creek & southern rice valley
	var orbit_specs := [
		{"center": Vector3(18.0, 15.5, 18.0), "rx": 18.0, "rz": 14.0, "spd": 0.34, "phase": 0.0},
		{"center": Vector3(20.5, 17.2, 22.0), "rx": 20.0, "rz": 15.5, "spd": 0.34, "phase": 0.55},
		{"center": Vector3(16.0, 18.8, 42.0), "rx": 26.0, "rz": 19.0, "spd": 0.28, "phase": 1.85},
		{"center": Vector3(-12.0, 19.5, -18.0), "rx": 24.0, "rz": 18.0, "spd": 0.30, "phase": 3.10},
		{"center": Vector3(14.0, 22.0, -56.0), "rx": 22.0, "rz": 17.0, "spd": 0.31, "phase": 4.45}
	]
	for i in orbit_specs.size():
		var sp: Dictionary = orbit_specs[i]
		var holder := Node3D.new()
		holder.name = "SkyEgret_%d" % i
		add_child(holder)
		var vis := _instantiate_animal_mesh("animal_egret")
		if vis != null:
			vis.scale = Vector3.ONE * 1.42
			if vis is MeshInstance3D:
				(vis as MeshInstance3D).visibility_range_end = 0.0
			for ch in vis.find_children("*", "MeshInstance3D", true, false):
				(ch as MeshInstance3D).visibility_range_end = 0.0
			holder.add_child(vis)
		sky_egrets.append({
			"node": holder,
			"vis": vis,
			"center": sp.center,
			"rx": float(sp.rx),
			"rz": float(sp.rz),
			"spd": float(sp.spd),
			"angle": float(sp.phase)
		})

func _initial_pos(spec: Dictionary) -> Vector3:
	var kind := str(spec.kind)
	if kind == "fish":
		var z := float(spec.stream_z)
		var cx := float(game.Layout.stream_center_x(z)) + float(spec.lane)
		return Vector3(cx, float(game.Layout.stream_water_y(z)) - 0.16, z)
	if kind == "shrimp":
		var z := float(spec.stream_z)
		var cx := float(game.Layout.stream_center_x(z)) + float(spec.lane)
		return Vector3(cx, float(game.Layout.stream_water_y(z)) - 0.26, z)
	if kind == "crab":
		var z := float(spec.stream_z)
		var cx := float(game.Layout.stream_center_x(z)) + float(spec.bank_side)
		return Vector3(cx, float(game.terrain_height(cx, z)) + 0.03, z)
	var h: Vector3 = spec.home
	var base_y := float(game.terrain_height(h.x, h.z))
	if kind == "bird":
		return Vector3(h.x, base_y + float(spec.get("perch_h", 0.0)), h.z)
	return Vector3(h.x, base_y, h.z)

func _spawn_flora_spots():
	for spot in FLORA_SPOTS:
		var root := Node3D.new()
		var p: Vector3 = game.Layout.on_ground(spot.pos)
		if str(spot.kind) == "lily":
			var z := float(spot.pos.z)
			p = Vector3(float(game.Layout.stream_center_x(z)) - 0.85, float(game.Layout.stream_water_y(z)) + 0.02, z)
		root.position = p
		root.set_meta("flora_id", spot.id)
		root.set_meta("en", spot.en)
		root.set_meta("zh", spot.zh)
		root.set_meta("tts", spot.tts)
		root.set_meta("sentence", spot.sentence)
		root.set_meta("heal", int(spot.heal))
		add_child(root)

		var visual := _place_flora_visual(root, str(spot.kind))
		root.set_meta("visual_node", visual)

		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.36
		tm.outer_radius = 0.44
		tm.rings = 16
		tm.ring_segments = 6
		ring.mesh = tm
		ring.position.y = 0.03
		ring.material_override = game._material(Color("9df0b8"), true)
		root.add_child(ring)
		root.set_meta("ring_node", ring)

		var lbl: Label3D = game._label3d(root, "%s · %s [E]" % [spot.en, spot.zh], Vector3(0, 0.88, 0), 18, Color("d4ffdc"))
		lbl.visibility_range_end = 13.0
		root.set_meta("label_node", lbl)
		flora_nodes.append(root)

func _place_flora_visual(parent: Node3D, kind: String) -> Node3D:
	if kind == "orchid":
		var o := _instantiate_eco_mesh("flora_glow_orchid")
		if o != null:
			o.scale = Vector3.ONE * 1.15
			parent.add_child(o)
			return o
	elif kind == "berry_fern":
		var f := _instantiate_eco_mesh("flora_berry_fern")
		if f != null:
			f.scale = Vector3.ONE * 1.25
			parent.add_child(f)
			return f
	if kind == "lily":
		var holder := Node3D.new()
		var pad := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34
		cm.bottom_radius = 0.30
		cm.height = 0.028
		pad.mesh = cm
		pad.material_override = game._material(Color("3f8c4e"))
		holder.add_child(pad)
		var flower := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.095
		sm.height = 0.14
		flower.mesh = sm
		flower.position.y = 0.06
		flower.material_override = game._material(Color("ffafd2"))
		holder.add_child(flower)
		parent.add_child(holder)
		return holder
	var nature_map := {
		"mushroom": "res://assets/nature/mushroom_redGroup.glb",
		"purple_flower": "res://assets/nature/flower_purpleA.glb",
		"yellow_flower": "res://assets/nature/flower_yellowA.glb"
	}
	var path: String = nature_map.get(kind, "res://assets/nature/flower_redA.glb")
	if ResourceLoader.exists(path):
		return game._model(parent, path, Vector3.ZERO, 0.62 if kind != "lily" else 0.14, rng.randf_range(0, TAU), "none")
	var box: Node3D = game._mesh_box(parent, Vector3(0, 0.25, 0), Vector3(0.35, 0.5, 0.35), Color("7de08b"), false)
	return box

func reset():
	discovered_species.clear()
	collected_flora.clear()
	flee_sfx_cooldown = 0.0
	for fx in hit_fx:
		if is_instance_valid(fx.node):
			fx.node.queue_free()
	hit_fx.clear()
	for a in animals:
		a.state = "ambush" if a.kind == "boar" else "idle"
		a.timer = 0.0
		a.fly_alt = 0.0
		a.pos = _initial_pos(HABITAT_ANIMALS[a.idx])
		a.dir = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		a.root.visible = true
		a.root.position = a.pos
		a.root.rotation = Vector3(0.0, atan2(-a.dir.x, -a.dir.z), 0.0)
		a.visual.rotation = Vector3.ZERO
		a.visual.position = Vector3(0.0, -0.14 if a.state == "ambush" else 0.0, 0.0)
		a.visual.scale = Vector3.ONE * a.visual_scale
		a.label.visible = (a.state != "ambush")
		a.area.collision_layer = HIT_LAYER
	for f in flora_nodes:
		var lbl: Label3D = f.get_meta("label_node")
		lbl.text = "%s · %s [E]" % [f.get_meta("en"), f.get_meta("zh")]
		lbl.modulate = Color.WHITE
		var ring: MeshInstance3D = f.get_meta("ring_node")
		ring.visible = true

func update(delta: float):
	flee_sfx_cooldown = maxf(0.0, flee_sfx_cooldown - delta)
	_update_fx(delta)
	_update_sky_egrets(delta)
	if not is_instance_valid(game.player):
		return
	var ppos: Vector3 = game.player.position
	for a in animals:
		match a.state:
			"hidden":
				a.timer -= delta
				if a.timer <= 0.0:
					a.state = "ambush" if a.kind == "boar" else "idle"
					a.fly_alt = 0.0
					a.pos = _initial_pos(HABITAT_ANIMALS[a.idx])
					a.root.position = a.pos
					a.visual.rotation = Vector3.ZERO
					a.visual.position = Vector3(0.0, -0.14 if a.state == "ambush" else 0.0, 0.0)
					a.visual.scale = Vector3.ONE * a.visual_scale
					a.label.visible = (a.state != "ambush")
					a.area.collision_layer = HIT_LAYER
					a.root.visible = true
			"downed":
				a.timer -= delta
				var fade := clampf(a.timer / 0.65, 0.02, 1.0)
				a.visual.scale = Vector3.ONE * a.visual_scale * fade
				a.visual.rotation.z = lerpf(a.visual.rotation.z, PI * 0.48, minf(delta * 14.0, 1.0))
				if a.timer <= 0.0:
					a.state = "hidden"
					a.timer = 24.0
					a.root.visible = false
					a.area.collision_layer = 0
			"ambush", "idle", "flee", "fly":
				_step_creature(a, delta, ppos)

func _update_sky_egrets(delta: float):
	for eg in sky_egrets:
		eg.angle += float(eg.spd) * delta
		var ang: float = eg.angle
		var c: Vector3 = eg.center
		var nx := c.x + cos(ang) * float(eg.rx)
		var nz := c.z + sin(ang) * float(eg.rz)
		var ny := c.y + sin(ang * 2.0) * 1.1
		var tx := -sin(ang) * float(eg.rx)
		var tz := cos(ang) * float(eg.rz)
		var n: Node3D = eg.node
		n.position = Vector3(nx, ny, nz)
		n.rotation.y = atan2(-tx, -tz)
		if eg.vis != null:
			(eg.vis as Node3D).rotation.z = 0.22 + sin(ang * 9.0) * 0.14
			(eg.vis as Node3D).position.y = sin(ang * 9.0) * 0.08

func _step_creature(a: Dictionary, delta: float, ppos: Vector3):
	var kind: String = a.kind
	var pos: Vector3 = a.pos
	var dist := Vector2(pos.x - ppos.x, pos.z - ppos.z).length()
	if dist > 54.0 and a.state in ["idle", "ambush"]:
		return

	if kind == "boar" and a.state == "ambush":
		a.phase += delta * 2.5
		a.visual.position.y = -0.14 + sin(a.phase) * 0.015
		if dist < 11.2:
			_trigger_boar_ambush(a, ppos, true)
		return

	var flee_r := 8.4 if kind in ["rabbit", "squirrel", "fox", "bird"] else (6.5 if kind == "boar" else 4.8)
	if dist < flee_r and a.state == "idle":
		_start_flee(a, ppos, true)

	if a.state in ["flee", "fly"]:
		a.timer -= delta
		if a.timer <= 0.0 and dist > 14.0:
			a.state = "idle"
			a.fly_alt = 0.0
			a.wander_cd = rng.randf_range(0.8, 2.4)

	a.phase += delta * (11.5 if a.state in ["flee", "fly"] else 4.2)
	match kind:
		"fish":
			_move_fish(a, delta, ppos)
		"shrimp":
			_move_shrimp(a, delta, ppos)
		"crab":
			_move_crab(a, delta, ppos)
		"bird":
			_move_bird(a, delta, ppos)
		_:
			_move_land_critter(a, delta, ppos)

func _trigger_boar_ambush(a: Dictionary, ppos: Vector3, by_proximity: bool):
	a.state = "flee"
	a.timer = 5.4
	a.label.visible = true
	a.visual.position.y = 0.0
	# Burst obliquely out of the bush thicket across the open hillside!
	var to_p := Vector3(ppos.x - a.pos.x, 0.0, ppos.z - a.pos.z)
	if to_p.length_squared() < 0.01:
		to_p = Vector3(1.0, 0.0, 0.0)
	var tangent := Vector3(-to_p.z, 0.0, to_p.x).normalized()
	if a.idx % 2 == 1:
		tangent = -tangent
	a.dir = (tangent * 0.82 - to_p.normalized() * 0.58).normalized()
	game.play_sfx("boar_charge", -9)
	_spawn_vanish_motes(a.pos + Vector3(0.0, 0.32, 0.0))
	if by_proximity and not discovered_species.has("boar"):
		discovered_species["boar"] = true
		game.speak_english(a.tts)
		game._notice("🐗 灌木丛惊起【%s · %s】！正埋头横冲山坡！" % [a.en, a.zh], Color("ffd48a"))

func _start_flee(a: Dictionary, away_from: Vector3, by_proximity: bool = false):
	if a.kind == "boar" and a.state == "ambush":
		_trigger_boar_ambush(a, away_from, by_proximity)
		return
	a.state = "fly" if a.kind == "bird" else "flee"
	a.timer = 5.2 if a.kind == "bird" else (4.4 if a.kind in ["rabbit", "squirrel", "fox", "boar"] else 2.8)
	var delta_xz := Vector3(a.pos.x - away_from.x, 0.0, a.pos.z - away_from.z)
	if delta_xz.length_squared() < 0.01:
		delta_xz = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	a.dir = delta_xz.normalized()
	if flee_sfx_cooldown <= 0.0:
		flee_sfx_cooldown = 1.35
		game.play_sfx("bird_flap" if a.kind == "bird" else ("boar_charge" if a.kind == "boar" else "animal_flee"), -12)
	if by_proximity and not discovered_species.has(a.kind) and a.pos.distance_to(game.player.position) < 11.5:
		discovered_species[a.kind] = true
		game.speak_english(a.tts)
		game._notice("🌿 发现山野生灵：%s（%s）· 靠近惊动会敏捷逃逸！" % [a.en, a.zh], Color("9ef5b8"))

func _move_land_critter(a: Dictionary, delta: float, ppos: Vector3):
	var kind: String = a.kind
	var speed := 1.45
	if a.state == "flee":
		match kind:
			"boar": speed = 9.2
			"fox": speed = 8.6
			"rabbit": speed = 7.4
			_: speed = 6.8
	else:
		match kind:
			"boar": speed = 1.75
			"fox": speed = 2.05
			"rabbit": speed = 1.35
			_: speed = 1.55

	if a.state == "idle":
		a.wander_cd -= delta
		if a.wander_cd <= 0.0:
			a.wander_cd = rng.randf_range(1.6, 4.0)
			var to_home: Vector3 = a.home - a.pos
			to_home.y = 0.0
			if to_home.length() > 8.5:
				a.dir = to_home.normalized()
			else:
				a.dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	elif kind != "boar" or a.timer < 3.4:
		var away := Vector3(a.pos.x - ppos.x, 0.0, a.pos.z - ppos.z)
		if away.length() > 0.2:
			a.dir = a.dir.lerp(away.normalized(), minf(delta * 4.2, 1.0)).normalized()

	var dir3: Vector3 = a.dir
	var cur_pos: Vector3 = a.pos
	var nxt := cur_pos + dir3 * speed * delta
	var min_x := float(game.Layout.FENCE_MIN_X) + 1.8
	var max_x := float(game.Layout.FENCE_MAX_X) - 1.8
	var min_z := float(game.Layout.FENCE_MIN_Z) + 1.8
	var max_z := float(game.Layout.FENCE_MAX_Z) - 1.8
	if nxt.x < min_x or nxt.x > max_x:
		a.dir.x = -a.dir.x
		nxt.x = clampf(nxt.x, min_x, max_x)
	if nxt.z < min_z or nxt.z > max_z:
		a.dir.z = -a.dir.z
		nxt.z = clampf(nxt.z, min_z, max_z)
	# Keep land mammals out of deep creek water
	var sd := float(game.Layout.stream_distance(nxt.x, nxt.z))
	if sd < 2.35:
		var push_x := 1.0 if nxt.x >= float(game.Layout.stream_center_x(nxt.z)) else -1.0
		a.dir.x = push_x * 0.85
		nxt.x = float(game.Layout.stream_center_x(nxt.z)) + push_x * 2.40

	nxt.y = float(game.terrain_height(nxt.x, nxt.z))
	a.pos = nxt
	a.root.position = nxt
	a.root.rotation.y = atan2(-a.dir.x, -a.dir.z)

	if kind == "rabbit":
		var hop := absf(sin(a.phase)) * (0.28 if a.state == "flee" else 0.09)
		a.visual.position.y = hop
		a.visual.rotation.x = sin(a.phase * 2.0) * (0.18 if a.state == "flee" else 0.06)
	elif kind == "fox":
		var bound := absf(sin(a.phase * 0.95)) * (0.26 if a.state == "flee" else 0.05)
		a.visual.position.y = bound
		a.visual.rotation.x = sin(a.phase * 1.9) * (0.16 if a.state == "flee" else 0.04)
	elif kind == "boar":
		var gallop := absf(sin(a.phase * 1.35)) * (0.12 if a.state == "flee" else 0.03)
		a.visual.position.y = gallop
		a.visual.rotation.z = sin(a.phase * 2.1) * (0.09 if a.state == "flee" else 0.03)
	else:
		var scurry := absf(sin(a.phase * 1.4)) * (0.14 if a.state == "flee" else 0.04)
		a.visual.position.y = scurry
		a.visual.rotation.z = sin(a.phase * 1.6) * 0.07

func _move_bird(a: Dictionary, delta: float, ppos: Vector3):
	if a.state != "fly":
		# Perched on tree branch, fence post, or wading in shallow stream: gentle head-turn & wing twitch
		var home_p: Vector3 = a.home
		a.pos = a.pos.lerp(home_p, minf(delta * 2.4, 1.0))
		a.root.position = a.pos
		a.root.rotation.y = sin(a.phase * 0.45 + float(a.idx)) * 0.85
		a.visual.position.y = absf(sin(a.phase * 0.9)) * 0.03
		a.visual.rotation = Vector3(sin(a.phase * 0.7) * 0.06, 0.0, 0.0)
		return

	# Active 3D banked climb & soaring escape arc!
	var away := Vector3(a.pos.x - ppos.x, 0.0, a.pos.z - ppos.z)
	if away.length() > 0.3 and a.timer > 2.4:
		a.dir = a.dir.lerp(away.normalized(), minf(delta * 2.8, 1.0)).normalized()
	else:
		var to_home := Vector3(a.home.x - a.pos.x, 0.0, a.home.z - a.pos.z)
		if to_home.length() > 1.5:
			a.dir = a.dir.lerp(to_home.normalized(), minf(delta * 2.2, 1.0)).normalized()

	var spd := 8.4
	var nxt_xz := Vector2(a.pos.x + a.dir.x * spd * delta, a.pos.z + a.dir.z * spd * delta)
	nxt_xz.x = clampf(nxt_xz.x, float(game.Layout.FENCE_MIN_X) + 2.5, float(game.Layout.FENCE_MAX_X) - 2.5)
	nxt_xz.y = clampf(nxt_xz.y, float(game.Layout.FENCE_MIN_Z) + 2.5, float(game.Layout.FENCE_MAX_Z) - 2.5)
	var target_alt := 6.2 + sin(a.phase * 0.3) * 1.2 if a.timer > 1.4 else float(a.perch_h) + 0.8
	a.fly_alt = lerpf(float(a.fly_alt), target_alt, minf(delta * 2.8, 1.0))
	var gy := float(game.terrain_height(nxt_xz.x, nxt_xz.y))
	a.pos = Vector3(nxt_xz.x, maxf(gy + float(a.perch_h), gy + float(a.fly_alt)), nxt_xz.y)
	a.root.position = a.pos
	a.root.rotation.y = atan2(-a.dir.x, -a.dir.z)
	a.visual.position.y = sin(a.phase * 1.9) * 0.11
	a.visual.rotation = Vector3(-0.14, 0.0, sin(a.phase * 1.9) * 0.24)

func _move_fish(a: Dictionary, delta: float, ppos: Vector3):
	var swim_dir := 1.0 if a.dir.z >= 0.0 else -1.0
	if a.state == "flee":
		swim_dir = 1.0 if a.stream_z >= ppos.z else -1.0
	var speed := 4.6 if a.state == "flee" else 1.25
	var z_min := float(game.Layout.STREAM_Z_MIN) + 2.5
	var z_max := float(game.Layout.FENCE_MAX_Z) - 1.6
	a.stream_z += swim_dir * speed * delta
	if a.stream_z < z_min:
		a.stream_z = z_min
		a.dir.z = 1.0
	elif a.stream_z > z_max:
		a.stream_z = z_max
		a.dir.z = -1.0
	var cx := float(game.Layout.stream_center_x(a.stream_z))
	var target_x := cx + float(a.lane) + sin(a.phase * 0.5) * 0.38
	var wy := float(game.Layout.stream_water_y(a.stream_z)) - 0.16
	var nxt := Vector3(target_x, wy, a.stream_z)
	var prev_pos: Vector3 = a.pos
	var look := nxt - prev_pos
	look.y = 0.0
	a.pos = nxt
	a.root.position = nxt
	if look.length() > 0.002:
		a.root.rotation.y = atan2(-look.x, -look.z)
	a.visual.rotation.y = sin(a.phase * 2.2) * 0.22

func _move_shrimp(a: Dictionary, delta: float, ppos: Vector3):
	# Freshwater river shrimp hover gently over wet pebbles, then tail-flip swiftly backward when startled!
	var z_min := float(game.Layout.STREAM_Z_MIN) + 3.5
	var z_max := float(game.Layout.FENCE_MAX_Z) - 1.8
	var z_vel := sin(a.phase * 0.45) * 0.42
	if a.state == "flee":
		var dart_pulse := 0.35 + 0.65 * absf(sin(a.phase * 1.6))
		var away_sign := 1.0 if a.stream_z >= ppos.z else -1.0
		z_vel = away_sign * 4.8 * dart_pulse
	a.stream_z = clampf(a.stream_z + z_vel * delta, z_min, z_max)
	var cx := float(game.Layout.stream_center_x(a.stream_z))
	var px := cx + float(a.lane) + cos(a.phase * 0.6) * 0.28
	var wy := float(game.Layout.stream_water_y(a.stream_z)) - 0.26 + absf(sin(a.phase * 1.6)) * (0.08 if a.state == "flee" else 0.02)
	var nxt := Vector3(px, wy, a.stream_z)
	a.pos = nxt
	a.root.position = nxt
	# In flee mode, shrimp face TOWARD threat while darting backward!
	if a.state == "flee":
		var toward := Vector3(ppos.x - nxt.x, 0.0, ppos.z - nxt.z)
		if toward.length() > 0.05:
			a.root.rotation.y = atan2(-toward.x, -toward.z)
		a.visual.rotation.x = sin(a.phase * 3.2) * 0.26
	else:
		a.root.rotation.y = sin(a.phase * 0.3 + float(a.idx)) * 1.4
		a.visual.rotation.x = sin(a.phase * 1.2) * 0.06

func _move_crab(a: Dictionary, delta: float, ppos: Vector3):
	var crab_speed := 3.4 if a.state == "flee" else 0.72
	var z_step := (1.0 if (a.stream_z >= ppos.z or a.state == "idle") else -1.0)
	if a.state == "idle":
		a.wander_cd -= delta
		if a.wander_cd <= 0.0:
			a.wander_cd = rng.randf_range(1.4, 3.0)
			a.dir.z = -a.dir.z
		z_step = 1.0 if a.dir.z >= 0.0 else -1.0
	var z_min := float(game.Layout.STREAM_Z_MIN) + 4.0
	var z_max := float(game.Layout.FENCE_MAX_Z) - 2.0
	a.stream_z = clampf(a.stream_z + z_step * crab_speed * delta, z_min, z_max)
	var cx := float(game.Layout.stream_center_x(a.stream_z))
	var px := cx + float(a.bank_side) + sin(a.phase * 0.4) * 0.22
	var nxt := Vector3(px, float(game.terrain_height(px, a.stream_z)) + 0.03, a.stream_z)
	a.pos = nxt
	a.root.position = nxt
	# Crabs scuttle sideways toward water center!
	a.root.rotation.y = (PI * 0.5 if float(a.bank_side) > 0.0 else -PI * 0.5) + sin(a.phase) * 0.15
	a.visual.position.y = absf(sin(a.phase * 1.8)) * 0.025

func on_gunshot_near(origin: Vector3, suppressed: bool):
	var alert_r := 7.0 if suppressed else 19.0
	for a in animals:
		if a.state in ["idle", "ambush"] and a.pos.distance_to(origin) <= alert_r:
			_start_flee(a, origin)

func hit_bullet(collider) -> bool:
	if not (collider is Object) or not collider.has_meta("critter_index"):
		return false
	var idx := int(collider.get_meta("critter_index"))
	if idx < 0 or idx >= animals.size():
		return false
	_down_animal(animals[idx])
	return true

func melee_strike(camera: Camera3D) -> bool:
	var cam_pos := camera.global_position
	var cam_fwd := (-camera.global_transform.basis.z).normalized()
	var best = null
	var best_dist := 3.4
	for a in animals:
		if not (a.state in ["idle", "ambush", "flee", "fly"]):
			continue
		var center: Vector3 = a.pos + Vector3(0, 0.24, 0)
		var delta := center - cam_pos
		var d := delta.length()
		if d <= best_dist and cam_fwd.dot(delta.normalized()) >= 0.45:
			best_dist = d
			best = a
	if best == null:
		return false
	game.play_sfx("knife_hit", -10)
	_down_animal(best)
	return true

func _down_animal(a: Dictionary):
	if not (a.state in ["idle", "ambush", "flee", "fly"]):
		return
	a.state = "downed"
	a.timer = 1.85
	a.area.collision_layer = 0
	a.label.visible = true
	discovered_species[a.kind] = true
	game.show_hitmarker(false)
	game.play_sfx("animal_hit", -10)
	_spawn_vanish_motes(a.pos + Vector3(0, 0.28, 0))
	game._notice("✦ 击中【%s · %s】！正化作林间微光消失…" % [a.en, a.zh], Color("ffe09e"))

func _spawn_vanish_motes(at: Vector3):
	for i in 5:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		m.mesh = sm
		m.position = at + Vector3(cos(i * TAU / 5.0) * 0.20, 0.05, sin(i * TAU / 5.0) * 0.20)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("d8ffcf")
		mat.emission_enabled = true
		mat.emission = Color("b6ffaa")
		mat.emission_energy_multiplier = 1.4
		m.material_override = mat
		add_child(m)
		hit_fx.append({"node": m, "vel": Vector3(cos(i * 1.3) * 0.45, 0.85 + float(i) * 0.12, sin(i * 1.3) * 0.45), "left": 0.9})

func _update_fx(delta: float):
	for i in range(hit_fx.size() - 1, -1, -1):
		var fx: Dictionary = hit_fx[i]
		fx.left -= delta
		if not is_instance_valid(fx.node) or fx.left <= 0.0:
			if is_instance_valid(fx.node):
				fx.node.queue_free()
			hit_fx.remove_at(i)
		else:
			fx.node.position += fx.vel * delta
			fx.node.scale = Vector3.ONE * clampf(fx.left / 0.9, 0.05, 1.0)

func interact_flora(node: Node3D) -> bool:
	if not is_instance_valid(node) or not node.has_meta("flora_id"):
		return false
	var fid := str(node.get_meta("flora_id"))
	var en := str(node.get_meta("en"))
	var zh := str(node.get_meta("zh"))
	var tts := str(node.get_meta("tts"))
	var sentence := str(node.get_meta("sentence"))
	game.speak_english(tts)
	if collected_flora.has(fid):
		game._notice("📖 温习山野植物：%s（%s）— %s" % [en, zh, sentence], Color("c2ffd4"))
		return true
	collected_flora[fid] = true
	game.rules.score += 5
	var heal_amt := int(node.get_meta("heal", 5))
	if is_instance_valid(game.combat) and game.combat.in_field():
		game.combat.heal(heal_amt, 4)
	game.play_sfx("flora_collect", -10)
	var lbl: Label3D = node.get_meta("label_node")
	lbl.text = "✓ %s · %s" % [en, zh]
	lbl.modulate = Color("89f0ad")
	var ring: MeshInstance3D = node.get_meta("ring_node")
	ring.visible = false
	game._notice("🌿 辨识奇植【%s · %s】(+5分 +%d生命) · %s" % [en, zh, heal_amt, sentence], Color("8ff5b5"))
	return true

func eco_discoveries_total() -> int:
	return discovered_species.size() + collected_flora.size()

func status_badge() -> String:
	return "生灵 %d/%d · 奇植 %d/%d" % [
		mini(TOTAL_SPECIES, discovered_species.size()), TOTAL_SPECIES,
		mini(FLORA_SPOTS.size(), collected_flora.size()), FLORA_SPOTS.size()
	]
