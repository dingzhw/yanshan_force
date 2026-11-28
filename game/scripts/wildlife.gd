extends Node3D
## Living Yanshan Mountain ecosystem with true skeletal animations (Skeleton3D + AnimationPlayer),
## tree-climbing squirrels, counter-charging wild boars (15 HP damage), flapping/gliding egrets & songbirds,
## brook koi, creek crabs, freshwater shrimp, and 8 interactive [F] English botanical specimens.

const AhsarahLayout = preload("res://scripts/ahsarah_layout.gd")

var game
var yanshan_root: Node3D
var ahsarah_root: Node3D
var active_map_id: String = "yanshan"
var animals: Array = []
var sky_egrets: Array = []
var flora_nodes: Array = []
var desert_animals: Array = []
var desert_falcons: Array = []
var _desert_spawned := false
var discovered_species: Dictionary = {}
var discovered_desert_species: Dictionary = {}
var collected_flora: Dictionary = {}
var hit_fx: Array = []
var flee_sfx_cooldown := 0.0
var frozen_for_capture := false
var map_enabled := true
var rng := RandomNumberGenerator.new()

func _ensure_desert_spawned():
	if _desert_spawned:
		return
	_desert_spawned = true
	_spawn_desert_wildlife()
	_spawn_desert_falcons()
	_reset_desert_wildlife_state()

func set_active_map(map_id: String):
	active_map_id = "ahsarah" if map_id == "ahsarah" else "yanshan"
	map_enabled = true
	visible = true
	var is_ys := (active_map_id == "yanshan")
	if not is_ys:
		_ensure_desert_spawned()
	if is_instance_valid(yanshan_root):
		yanshan_root.visible = is_ys
	if is_instance_valid(ahsarah_root):
		ahsarah_root.visible = not is_ys
	for a in animals:
		if is_instance_valid(a.area):
			a.area.collision_layer = HIT_LAYER if (is_ys and not (a.state in ["downed", "hidden"])) else 0
	for eg in sky_egrets:
		if is_instance_valid(eg.area):
			eg.area.collision_layer = HIT_LAYER if (is_ys and not (str(eg.get("state", "fly")) in ["downed", "hidden"])) else 0
	for f in flora_nodes:
		if is_instance_valid(f):
			f.visible = is_ys and not bool(collected_flora.get(str(f.get_meta("flora_id", "")), false))
	for da in desert_animals:
		if is_instance_valid(da.area):
			da.area.collision_layer = HIT_LAYER if ((not is_ys) and not (da.state in ["downed", "hidden"])) else 0
	for df in desert_falcons:
		if is_instance_valid(df.area):
			df.area.collision_layer = HIT_LAYER if ((not is_ys) and not (str(df.get("state", "fly")) in ["downed", "hidden"])) else 0

func set_map_enabled(on: bool):
	set_active_map("yanshan" if on else "ahsarah")
var critter_mat_cache: Dictionary = {}

const HIT_LAYER := 16  # Dedicated bit 4 (isolated from player mask 1|4 and enemy mask 7)
const TOTAL_SPECIES := 12
const TOTAL_DESERT_SPECIES := 4
const BOAR_CHARGE_DAMAGE := 15
const BOAR_CHARGE_CHANCE := 0.48

# v0.9.1 Ahsarah Desert Wildlife Ecology (22 ground critters + 6 soaring Desert Falcons = 28 rigged critters across 4 species!)
const DESERT_ANIMALS := [
	# 1. Fennec Foxes (8 — big-eared agile Saharan desert foxes near oasis, dunes & ruins)
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(12.0, 0, 8.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(-28.0, 0, 6.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(-18.0, 0, -24.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(22.0, 0, -16.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(-20.0, 0, -68.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(26.0, 0, -66.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(-30.0, 0, -96.0)},
	{"kind": "fennec", "en": "Fennec Fox", "zh": "荒漠耳廓狐", "tts": "fennec fox", "home": Vector3(32.0, 0, -112.0)},

	# 2. North African Dromedary Camels (4 — tranquil caravan camels by oasis palms & bazaar square)
	{"kind": "camel", "en": "Camel", "zh": "北非单峰驼", "tts": "camel", "home": Vector3(-13.5, 0, 21.5)},
	{"kind": "camel", "en": "Camel", "zh": "北非单峰驼", "tts": "camel", "home": Vector3(18.5, 0, 12.0)},
	{"kind": "camel", "en": "Camel", "zh": "北非单峰驼", "tts": "camel", "home": Vector3(26.0, 0, -48.0)},
	{"kind": "camel", "en": "Camel", "zh": "北非单峰驼", "tts": "camel", "home": Vector3(-30.0, 0, -22.0)},

	# 3. Golden Dune Scarabs (10 — iridescent golden-turquoise Saharan scarabs scuttling across dunes)
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(6.0, 0, 2.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(-8.0, 0, -12.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(15.0, 0, -32.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(-22.0, 0, -42.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(42.0, 0, -60.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(-38.0, 0, -78.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(20.0, 0, -98.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(-18.0, 0, -110.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(34.0, 0, -126.0)},
	{"kind": "scarab", "en": "Golden Scarab", "zh": "金色沙丘圣甲虫", "tts": "golden scarab", "home": Vector3(-38.0, 0, -128.0)},
]

const DESERT_FALCON_SPECS := [
	{"tts": "desert falcon", "center": Vector3(-8.0, 15.5, 8.0), "rx": 20.0, "rz": 16.0, "spd": 0.36, "phase": 0.2},
	{"tts": "desert falcon", "center": Vector3(34.0, 17.5, -34.0), "rx": 22.0, "rz": 18.0, "spd": 0.34, "phase": 1.4},
	{"tts": "desert falcon", "center": Vector3(-38.0, 19.0, -54.0), "rx": 22.0, "rz": 18.0, "spd": 0.32, "phase": 2.5},
	{"tts": "desert falcon", "center": Vector3(4.0, 18.5, -80.0), "rx": 26.0, "rz": 20.0, "spd": 0.31, "phase": 3.7},
	{"tts": "desert falcon", "center": Vector3(0.0, 22.5, -122.0), "rx": 26.0, "rz": 18.0, "spd": 0.35, "phase": 4.8},
	{"tts": "desert falcon", "center": Vector3(30.0, 24.5, -142.0), "rx": 24.0, "rz": 18.0, "spd": 0.33, "phase": 5.6},
]

const FLORA_SPOTS := [
	{"id": "flora_camp_orchid", "pos": Vector3(17.0, 0, 13.5), "kind": "orchid", "en": "Wild Orchid", "zh": "溪畔幽兰", "tts": "wild orchid", "sentence": "Wild orchids grow beside the clear mountain stream.", "heal": 8},
	{"id": "flora_bridge_lily", "pos": Vector3(21.0, 0, -24.5), "kind": "lily", "en": "Water Lily", "zh": "石桥睡莲", "tts": "water lily", "sentence": "Green water lilies float quietly near the stone bridge.", "heal": 6},
	{"id": "flora_forest_mushroom", "pos": Vector3(-28.0, 0, -48.0), "kind": "mushroom", "en": "Red Mushroom", "zh": "红伞山菌", "tts": "red mushroom", "sentence": "Bright red mushrooms grow under tall shady camphor trees.", "heal": 7},
	{"id": "flora_west_lavender", "pos": Vector3(-39.0, 0, -14.0), "kind": "purple_flower", "en": "Mountain Lavender", "zh": "山坡紫花", "tts": "purple flower", "sentence": "Purple flowers bloom beside the green cargo crates.", "heal": 6},
	{"id": "flora_overlook_berry", "pos": Vector3(44.0, 0, -32.0), "kind": "berry_fern", "en": "Mountain Berry", "zh": "朱果奇草", "tts": "mountain berry", "sentence": "Curious fern berries shine orange on the east ridge.", "heal": 10},
	{"id": "flora_cave_orchid", "pos": Vector3(-31.0, 0, -120.0), "kind": "orchid", "en": "Cave Orchid", "zh": "石窟夜光兰", "tts": "cave orchid", "sentence": "A glowing purple orchid blooms in front of the rock cave.", "heal": 10},
	{"id": "flora_radio_goldflower", "pos": Vector3(48.0, 0, -98.0), "kind": "yellow_flower", "en": "Golden Marigold", "zh": "金盏野花", "tts": "yellow flower", "sentence": "Yellow flowers wave near the East Recon Radio.", "heal": 7},
	{"id": "flora_bamboo_fern", "pos": Vector3(38.0, 0, -142.0), "kind": "berry_fern", "en": "Bamboo Herb", "zh": "竹海灵草", "tts": "green herb", "sentence": "Fresh green herbs hide beside the cool east stream.", "heal": 10},
	{"id": "flora_wangdao_tea", "pos": Vector3(47.5, 0, 14.0), "kind": "berry_fern", "en": "Spring Tea Leaf", "zh": "明前茶芽", "tts": "green tea leaf", "sentence": "Tender green tea leaves glisten in the morning mist.", "heal": 8},
	{"id": "flora_tea_pav_iris", "pos": Vector3(61.0, 0, -40.0), "kind": "purple_flower", "en": "Blue Mountain Iris", "zh": "东岭鸢尾", "tts": "blue iris", "sentence": "Blue iris flowers sway gently beside the tea pavilion.", "heal": 7},
	{"id": "flora_west_ravine_shroom", "pos": Vector3(-58.0, 0, -76.0), "kind": "mushroom", "en": "Forest Mushroom", "zh": "幽谷松菇", "tts": "forest mushroom", "sentence": "Sweet forest mushrooms grow in the cool bamboo ravine.", "heal": 8},
	{"id": "flora_cloud_lotus", "pos": Vector3(14.0, 0, -162.0), "kind": "orchid", "en": "Cloud Orchid", "zh": "云顶幽兰", "tts": "cloud orchid", "sentence": "A rare cloud orchid blooms near the high mountain ridge.", "heal": 10}
]

const HABITAT_ANIMALS := [
	# 1. Little Rabbits (11 — meadows, creek lawns & East/West/South fence slopes)
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(11.0, 0, 24.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-16.0, 0, -4.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-34.0, 0, -38.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(40.0, 0, -52.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(20.0, 0, -112.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-30.0, 0, -152.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-68.0, 0, 24.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(72.0, 0, -18.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(44.0, 0, 6.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(-52.0, 0, -104.0)},
	{"kind": "rabbit", "en": "Little Rabbit", "zh": "小野兔", "tts": "little rabbit", "home": Vector3(54.0, 0, -158.0)},

	# 2. Red Squirrels (9 — foraging near camphor & maple tree trunks; climb straight up trees when startled!)
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-23.0, 0, 2.5)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(17.5, 0, -15.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-43.0, 0, -28.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(38.0, 0, -46.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(45.0, 0, -112.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-34.0, 0, -130.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(75.0, 0, 15.0)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(-46.5, 0, -103.5)},
	{"kind": "squirrel", "en": "Red Squirrel", "zh": "小松鼠", "tts": "squirrel", "home": Vector3(74.5, 0, -95.5)},

	# 3. Bush-Ambush Wild Boars (6 — hidden in azalea thickets; sprint on 4 legs & may counter-charge when chased!)
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(-56.0, 0, 18.0)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(62.0, 0, 4.0)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(-76.0, 0, -44.0)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(68.0, 0, -110.0)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(-62.0, 0, -142.0)},
	{"kind": "boar", "en": "Wild Boar", "zh": "小野猪", "tts": "wild boar", "home": Vector3(56.0, 0, -64.0)},

	# 4. Agile Red Foxes (6 — patrolling fence-side grassy slopes & bamboo edges)
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-32.0, 0, 30.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(72.0, 0, -42.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-74.0, 0, -34.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(74.0, 0, -146.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-28.0, 0, -188.0)},
	{"kind": "fox", "en": "Red Fox", "zh": "小赤狐", "tts": "red fox", "home": Vector3(-48.0, 0, -124.0)},

	# 5. Tree-Perching Songbirds & Creek Egrets (11 — perched on fence posts, tree branches & wading by creek)
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(-3.5, 0, 39.8), "perch_h": 1.28},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(34.0, 0, 39.8), "perch_h": 1.28},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(-24.0, 0, 2.0), "perch_h": 3.25},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(16.5, 0, -15.5), "perch_h": 3.45},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(78.0, 0, -16.0), "perch_h": 2.85},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(-44.0, 0, -28.0), "perch_h": 3.15},
	{"kind": "bird", "mesh": "animal_bird", "en": "Mountain Bird", "zh": "山林飞鸟", "tts": "little bird", "home": Vector3(54.0, 0, -40.0), "perch_h": 2.65},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(27.5, 0, 24.0), "perch_h": 0.04},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(22.2, 0, -14.0), "perch_h": 0.04},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(30.2, 0, -104.0), "perch_h": 0.04},
	{"kind": "bird", "mesh": "animal_egret", "en": "White Egret", "zh": "溪畔白鹭", "tts": "white bird", "home": Vector3(25.5, 0, -166.0), "perch_h": 0.04},

	# 6. Brook Koi / Carp (8 — swimming in clear recessed pebble creek pools)
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": 31.0, "lane": -0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": 8.0, "lane": 0.40},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -16.0, "lane": -0.38},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -48.0, "lane": 0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -92.0, "lane": -0.40},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -138.0, "lane": 0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -178.0, "lane": -0.35},
	{"kind": "fish", "en": "Brook Fish", "zh": "溪流锦鲤", "tts": "small fish", "stream_z": -68.0, "lane": -0.30},

	# 7. Creek Rock Crabs (6 — scuttling sideways with 8 jointed legs along wet pebble shorelines)
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": 28.0, "bank_side": -1.48},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": 4.0, "bank_side": 1.50},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -40.0, "bank_side": 1.52},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -88.0, "bank_side": -1.48},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -146.0, "bank_side": 1.50},
	{"kind": "crab", "en": "River Crab", "zh": "溪石山蟹", "tts": "river crab", "stream_z": -176.0, "bank_side": -1.46},

	# 8. Freshwater Jade River Shrimp (7 — hovering & tail-flipping backward when startled!)
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": 33.0, "lane": 0.45},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": 11.0, "lane": -0.48},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -12.0, "lane": 0.42},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -58.0, "lane": -0.44},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -108.0, "lane": 0.46},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -172.0, "lane": -0.42},
	{"kind": "shrimp", "en": "River Shrimp", "zh": "清溪河虾", "tts": "river shrimp", "stream_z": -32.0, "lane": -0.40},

	# 9. v0.8.6 Graceful Jiangnan Sika Deer (8 — spotted mountain deer grazing in bamboo glades & tea hills)
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(-22.0, 0, 18.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(48.0, 0, -14.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(-54.0, 0, -16.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(60.0, 0, -56.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(-42.0, 0, -96.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(52.0, 0, -128.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(-34.0, 0, -172.0)},
	{"kind": "deer", "en": "Sika Deer", "zh": "梅花鹿", "tts": "sika deer", "home": Vector3(32.0, 0, -184.0)},

	# 10. v0.8.6 Golden Mountain Pheasants (8 — dazzling Jiangnan pheasants strutting & bursting into flight!)
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(36.0, 0, 14.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(-28.0, 0, -12.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(54.0, 0, -28.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(-48.0, 0, -52.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(42.0, 0, -78.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(-26.0, 0, -116.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(64.0, 0, -138.0)},
	{"kind": "pheasant", "en": "Golden Pheasant", "zh": "山雉锦鸡", "tts": "golden pheasant", "home": Vector3(-18.0, 0, -180.0)},

	# 11. v0.8.6 Clear-Brook Pond Turtles (6 — sunning on creek pebbles & swimming into the clear stream!)
	{"kind": "turtle", "en": "Pond Turtle", "zh": "清溪山龟", "tts": "pond turtle", "stream_z": 20.0, "bank_side": -1.35},
	{"kind": "turtle", "en": "Pond Turtle", "zh": "清溪山龟", "tts": "pond turtle", "stream_z": -6.0, "bank_side": 1.38},
	{"kind": "turtle", "en": "Pond Turtle", "zh": "清溪山龟", "tts": "pond turtle", "stream_z": -34.0, "bank_side": -1.40},
	{"kind": "turtle", "en": "Pond Turtle", "zh": "清溪山龟", "tts": "pond turtle", "stream_z": -72.0, "bank_side": 1.36},
	{"kind": "turtle", "en": "Pond Turtle", "zh": "清溪山龟", "tts": "pond turtle", "stream_z": -122.0, "bank_side": -1.38},
	{"kind": "turtle", "en": "Pond Turtle", "zh": "清溪山龟", "tts": "pond turtle", "stream_z": -162.0, "bank_side": 1.38},

	# 12. v0.8.6 Swallowtail Butterflies (10 — iridescent golden-jade butterflies fluttering above blossoms & ridges!)
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(6.0, 0, 16.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(24.0, 0, 12.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(44.0, 0, 22.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(-26.0, 0, -24.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(54.0, 0, -36.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(-38.0, 0, -48.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(32.0, 0, -76.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(-48.0, 0, -108.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(46.0, 0, -134.0)},
	{"kind": "butterfly", "en": "Butterfly", "zh": "山涧彩蝶", "tts": "butterfly", "home": Vector3(-12.0, 0, -162.0)}
]

func setup(g):
	game = g
	rng.seed = 20261115
	yanshan_root = Node3D.new()
	yanshan_root.name = "YanshanWildlifeRoot"
	add_child(yanshan_root)
	ahsarah_root = Node3D.new()
	ahsarah_root.name = "AhsarahWildlifeRoot"
	add_child(ahsarah_root)
	_spawn_wildlife()
	_spawn_sky_egrets()
	_spawn_flora_spots()
	# v0.9.9.6: Defer 28 rigged Ahsarah desert critters until Ahsarah map is actually entered!
	reset()
	set_active_map(game.active_map_id if is_instance_valid(game) else "yanshan")

func _polish_critter_materials(node: Node3D, cache_key: String = ""):
	if node == null:
		return
	var preserve_pbr := cache_key.contains("animal_rabbit") or cache_key.contains("animal_deer")
	var targets: Array = []
	if node is MeshInstance3D:
		targets.append(node)
	targets.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for t in targets:
		var mi := t as MeshInstance3D
		if mi and mi.mesh:
			if not preserve_pbr:
				for s in mi.mesh.get_surface_count():
					var mkey := "%s::%d" % [cache_key if cache_key != "" else str(mi.mesh.get_rid()), s]
					var bmat: BaseMaterial3D = critter_mat_cache.get(mkey, null)
					if bmat == null:
						var fmt: int = int(mi.mesh.surface_get_format(s))
						var has_vcol: bool = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0
						var mat: Material = mi.mesh.surface_get_material(s)
						if mat is BaseMaterial3D:
							bmat = mat.duplicate() as BaseMaterial3D
						elif has_vcol:
							bmat = StandardMaterial3D.new()
							bmat.roughness = 0.84
						if bmat != null:
							if has_vcol:
								bmat.vertex_color_use_as_albedo = true
							bmat.metallic = 0.0
							bmat.metallic_specular = 0.12
							critter_mat_cache[mkey] = bmat
					if bmat != null:
						mi.set_surface_override_material(s, bmat)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 1.6 if preserve_pbr else 1.2
			mi.visibility_range_end = 68.0 if preserve_pbr else 54.0

func _configure_anim_loops(anim: AnimationPlayer):
	if anim == null:
		return
	for lib_name in anim.get_animation_library_list():
		var lib: AnimationLibrary = anim.get_animation_library(lib_name)
		if lib == null:
			continue
		for anim_name in lib.get_animation_list():
			var a_res: Animation = lib.get_animation(anim_name)
			if a_res != null:
				a_res.loop_mode = Animation.LOOP_LINEAR

func _play_critter_anim(anim: AnimationPlayer, candidates: Array, speed_scale: float = 1.0, phase_seed: float = -1.0):
	if anim == null:
		return
	var chosen := ""
	var anim_list := anim.get_animation_list()
	for cand in candidates:
		var c_str := str(cand)
		if c_str in anim_list:
			chosen = c_str
			break
		# Fallback case-insensitive match
		for existing in anim_list:
			if str(existing).to_lower() == c_str.to_lower():
				chosen = str(existing)
				break
		if chosen != "":
			break
	if chosen == "" and anim_list.size() > 0:
		chosen = str(anim_list[0])
	if chosen == "":
		return
	anim.speed_scale = speed_scale
	if anim.current_animation != chosen or not anim.is_playing():
		anim.play(chosen, 0.18)
		if phase_seed >= 0.0:
			var a_res: Animation = anim.get_animation(chosen)
			if a_res != null and a_res.length > 0.05:
				anim.seek(fmod(phase_seed, 1.0) * a_res.length, true)

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
			_polish_critter_materials(sub, glb_path + "::" + mesh_name)
			inst.queue_free()
			return sub
		inst.queue_free()
	return null

func _instantiate_animal_mesh(mesh_name: String) -> Node3D:
	var rig_path := "res://assets/slice/wildlife/%s.glb" % mesh_name
	if ResourceLoader.exists(rig_path):
		if not game.scene_cache.has(rig_path):
			game.scene_cache[rig_path] = load(rig_path)
		var inst: Node3D = game.scene_cache[rig_path].instantiate()
		_polish_critter_materials(inst, rig_path)
		var anim := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_configure_anim_loops(anim)
		return inst
	var n := _instantiate_bundle_mesh("res://assets/slice/v061_nature_wildlife.glb", mesh_name)
	if n != null:
		return n
	return _instantiate_bundle_mesh("res://assets/slice/v055_eco_assets.glb", mesh_name)

func _instantiate_eco_mesh(mesh_name: String) -> Node3D:
	return _instantiate_bundle_mesh("res://assets/slice/v055_eco_assets.glb", mesh_name)

func _species_scale(kind: String, mesh_name: String) -> float:
	match kind:
		"rabbit": return 1.00
		"squirrel": return 0.98
		"boar": return 1.15
		"fox": return 1.12
		"bird": return 1.18 if mesh_name == "animal_egret" else 1.02
		"fish": return 1.05
		"crab": return 0.94
		"shrimp": return 0.80
		"deer": return 1.00
		"pheasant": return 1.06
		"turtle": return 1.02
		"butterfly": return 1.18
		"fennec": return 1.12
		"camel": return 1.05
		"scarab": return 1.28
		"falcon": return 1.38
	return 1.0

func _spawn_wildlife():
	for idx in HABITAT_ANIMALS.size():
		var spec: Dictionary = HABITAT_ANIMALS[idx]
		var kind := str(spec.kind)
		var mesh_name := str(spec.get("mesh", "animal_" + kind))
		var root := Node3D.new()
		root.name = "Critter_%s_%d" % [kind, idx]
		yanshan_root.add_child(root)

		var visual := _instantiate_animal_mesh(mesh_name)
		if visual == null:
			visual = MeshInstance3D.new()
			var cap := BoxMesh.new()
			cap.size = Vector3(0.28, 0.24, 0.34)
			visual.mesh = cap
		var sc := _species_scale(kind, mesh_name)
		visual.scale = Vector3.ONE * sc
		root.add_child(visual)
		var anim := visual.find_child("AnimationPlayer", true, false) as AnimationPlayer

		var area := Area3D.new()
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("critter_index", idx)
		var shp := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.85 if kind == "deer" else (0.78 if kind in ["bird", "pheasant"] else (0.62 if kind in ["boar", "fox"] else (0.56 if kind == "rabbit" else 0.48)))
		shp.shape = sph
		shp.position.y = 0.0 if kind in ["fish", "shrimp", "butterfly"] else (0.68 if kind == "deer" else (0.48 if kind == "rabbit" else 0.28))
		area.add_child(shp)
		root.add_child(area)

		var tag_y := 0.54 if kind in ["fish", "shrimp", "crab", "turtle", "butterfly"] else (1.72 if kind == "deer" else (1.16 if kind == "rabbit" else (0.94 if kind == "boar" else 0.76)))
		var lbl: Label3D = game._label3d(root, "%s · %s" % [spec.en, spec.zh], Vector3(0, tag_y, 0), 20, Color("f2f7d4"))
		lbl.visibility_range_end = 11.5
		lbl.visible = false

		var home := _initial_pos(spec)
		var init_state := "ambush" if kind == "boar" else "idle"
		var phase0 := rng.randf_range(0.0, TAU)
		var entry := {
			"idx": idx,
			"kind": kind,
			"mesh_name": mesh_name,
			"en": str(spec.en),
			"zh": str(spec.zh),
			"tts": str(spec.tts),
			"root": root,
			"visual": visual,
			"anim": anim,
			"area": area,
			"label": lbl,
			"base_label": "%s · %s" % [spec.en, spec.zh],
			"tag_left": 0.0,
			"tag_shown_once": false,
			"home": home,
			"perch_h": float(spec.get("perch_h", 0.0)),
			"stream_z": float(spec.get("stream_z", 0.0)),
			"lane": float(spec.get("lane", 0.0)),
			"bank_side": float(spec.get("bank_side", -1.5)),
			"pos": home,
			"dir": Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(),
			"state": init_state,  # idle, ambush, flee, charge, climb_approach, climb_up, perched_tree, fly, downed, hidden
			"timer": 0.0,
			"phase": phase0,
			"wander_cd": rng.randf_range(0.8, 3.2),
			"visual_scale": sc,
			"fly_alt": 0.0,
			"tree_trunk": Vector3.ZERO,
			"tree_radius": 0.32,
			"climb_h": 0.0,
			"climb_target_h": 3.15,
			"climb_angle": 0.0,
			"charge_cd": 0.0,
			"chase_accum": 0.0
		}
		_play_critter_anim(anim, ["Idle", "Swim"], 1.0, phase0 / TAU)
		animals.append(entry)

func _spawn_sky_egrets():
	# Ambient flock of 10 snowy Jiangnan egrets flapping & gliding gracefully over the creek, ridges & rice valley
	var orbit_specs := [
		{"center": Vector3(24.0, 12.8, 22.0), "rx": 22.0, "rz": 18.0, "spd": 0.34, "phase": 0.0},
		{"center": Vector3(32.0, 14.4, 34.0), "rx": 26.0, "rz": 20.0, "spd": 0.32, "phase": 0.62},
		{"center": Vector3(26.0, 16.2, 56.0), "rx": 32.0, "rz": 24.0, "spd": 0.28, "phase": 1.85},
		{"center": Vector3(-18.0, 17.5, -36.0), "rx": 28.0, "rz": 22.0, "spd": 0.30, "phase": 3.10},
		{"center": Vector3(26.0, 19.5, -88.0), "rx": 28.0, "rz": 22.0, "spd": 0.31, "phase": 4.15},
		{"center": Vector3(16.0, 23.5, -158.0), "rx": 30.0, "rz": 24.0, "spd": 0.29, "phase": 5.20},
		{"center": Vector3(56.0, 16.5, -12.0), "rx": 24.0, "rz": 19.0, "spd": 0.33, "phase": 1.15},
		{"center": Vector3(-52.0, 18.0, -76.0), "rx": 25.0, "rz": 20.0, "spd": 0.29, "phase": 2.45},
		{"center": Vector3(58.0, 20.5, -118.0), "rx": 24.0, "rz": 20.0, "spd": 0.31, "phase": 3.70},
		{"center": Vector3(-24.0, 24.5, -144.0), "rx": 28.0, "rz": 22.0, "spd": 0.27, "phase": 4.85}
	]
	for i in orbit_specs.size():
		var sp: Dictionary = orbit_specs[i]
		var holder := Node3D.new()
		holder.name = "SkyEgret_%d" % i
		yanshan_root.add_child(holder)
		var vis := _instantiate_animal_mesh("animal_egret")
		var anim: AnimationPlayer = null
		if vis != null:
			vis.scale = Vector3.ONE * 1.48
			if vis is MeshInstance3D:
				(vis as MeshInstance3D).visibility_range_end = 145.0
			for ch in vis.find_children("*", "MeshInstance3D", true, false):
				(ch as MeshInstance3D).visibility_range_end = 145.0
			anim = vis.find_child("AnimationPlayer", true, false) as AnimationPlayer
			_play_critter_anim(anim, ["Fly"], 1.32, float(i) * 0.19)
			holder.add_child(vis)

		var area := Area3D.new()
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("sky_egret_index", i)
		var shp := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 1.45
		shp.shape = sph
		shp.position.y = 0.15
		area.add_child(shp)
		holder.add_child(area)

		var lbl: Label3D = game._label3d(holder, "White Egret · 高空白鹭", Vector3(0, 0.98, 0), 26, Color("ffe8a3"))
		lbl.visibility_range_end = 68.0
		lbl.visible = false

		var init_ang := float(sp.phase)
		var c0: Vector3 = sp.center
		holder.position = Vector3(c0.x + cos(init_ang) * float(sp.rx), c0.y + sin(init_ang * 2.0) * 1.15, c0.z + sin(init_ang) * float(sp.rz))
		sky_egrets.append({
			"idx": i,
			"node": holder,
			"vis": vis,
			"anim": anim,
			"area": area,
			"label": lbl,
			"base_scale": 1.48,
			"state": "fly",
			"timer": 0.0,
			"center": sp.center,
			"rx": float(sp.rx),
			"rz": float(sp.rz),
			"spd": float(sp.spd),
			"angle": init_ang,
			"cycle_t": float(i) * 0.95,
			"gliding": false
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
	if kind == "crab" or kind == "turtle":
		var z := float(spec.stream_z)
		var cx := float(game.Layout.stream_center_x(z)) + float(spec.bank_side)
		return Vector3(cx, float(game.terrain_height(cx, z)) + 0.03, z)
	var h: Vector3 = spec.home
	var base_y := float(game.terrain_height(h.x, h.z))
	if kind == "bird":
		return Vector3(h.x, base_y + float(spec.get("perch_h", 0.0)), h.z)
	if kind == "butterfly":
		return Vector3(h.x, base_y + 1.05, h.z)
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
		yanshan_root.add_child(root)

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
		ring.visibility_range_end = 5.5
		root.add_child(ring)
		root.set_meta("ring_node", ring)

		var lbl: Label3D = game._label3d(root, "%s · %s [F]" % [spot.en, spot.zh], Vector3(0, 0.88, 0), 18, Color("d4ffdc"))
		lbl.visibility_range_end = 10.0
		lbl.visible = false
		root.set_meta("label_node", lbl)
		root.set_meta("tag_left", 0.0)
		root.set_meta("tag_shown_once", false)
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

func _desert_initial_pos(spec: Dictionary) -> Vector3:
	var h: Vector3 = spec.home
	return Vector3(h.x, float(AhsarahLayout.height(h.x, h.z)), h.z)

func _spawn_desert_wildlife():
	for idx in DESERT_ANIMALS.size():
		var spec: Dictionary = DESERT_ANIMALS[idx]
		var kind := str(spec.kind)
		var mesh_name := "animal_" + kind
		var root := Node3D.new()
		root.name = "DesertCritter_%s_%d" % [kind, idx]
		ahsarah_root.add_child(root)

		var visual := _instantiate_animal_mesh(mesh_name)
		if visual == null:
			visual = MeshInstance3D.new()
			var cap := BoxMesh.new()
			cap.size = Vector3(0.40, 0.32, 0.48)
			visual.mesh = cap
		var sc := _species_scale(kind, mesh_name)
		visual.scale = Vector3.ONE * sc
		root.add_child(visual)
		var anim := visual.find_child("AnimationPlayer", true, false) as AnimationPlayer

		var area := Area3D.new()
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("desert_critter_index", idx)
		var shp := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 1.15 if kind == "camel" else (0.58 if kind == "fennec" else 0.42)
		shp.shape = sph
		shp.position.y = 1.15 if kind == "camel" else (0.34 if kind == "fennec" else 0.14)
		area.add_child(shp)
		root.add_child(area)

		var tag_y := 2.45 if kind == "camel" else (0.85 if kind == "fennec" else 0.52)
		var lbl: Label3D = game._label3d(root, "%s · %s" % [spec.en, spec.zh], Vector3(0, tag_y, 0), 22, Color("ffe8a6"))
		lbl.visibility_range_end = 16.0
		lbl.visible = false

		var home := _desert_initial_pos(spec)
		var phase0 := rng.randf_range(0.0, TAU)
		var entry := {
			"idx": idx,
			"kind": kind,
			"mesh_name": mesh_name,
			"en": str(spec.en),
			"zh": str(spec.zh),
			"tts": str(spec.tts),
			"root": root,
			"visual": visual,
			"anim": anim,
			"area": area,
			"label": lbl,
			"base_label": "%s · %s" % [spec.en, spec.zh],
			"tag_left": 0.0,
			"tag_shown_once": false,
			"home": home,
			"pos": home,
			"dir": Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(),
			"state": "idle",
			"timer": 0.0,
			"phase": phase0,
			"wander_cd": rng.randf_range(1.2, 3.8),
			"visual_scale": sc
		}
		_play_critter_anim(anim, ["Idle", "Walk"], 1.0, phase0 / TAU)
		desert_animals.append(entry)

func _spawn_desert_falcons():
	for i in DESERT_FALCON_SPECS.size():
		var sp: Dictionary = DESERT_FALCON_SPECS[i]
		var holder := Node3D.new()
		holder.name = "DesertFalcon_%d" % i
		ahsarah_root.add_child(holder)
		var vis := _instantiate_animal_mesh("animal_falcon")
		var anim: AnimationPlayer = null
		if vis != null:
			vis.scale = Vector3.ONE * 1.48
			if vis is MeshInstance3D:
				(vis as MeshInstance3D).visibility_range_end = 165.0
			for ch in vis.find_children("*", "MeshInstance3D", true, false):
				(ch as MeshInstance3D).visibility_range_end = 165.0
			anim = vis.find_child("AnimationPlayer", true, false) as AnimationPlayer
			_play_critter_anim(anim, ["Fly"], 1.38, float(i) * 0.17)
			holder.add_child(vis)

		var area := Area3D.new()
		area.collision_layer = HIT_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("desert_falcon_index", i)
		var shp := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 1.45
		shp.shape = sph
		shp.position.y = 0.15
		area.add_child(shp)
		holder.add_child(area)

		var lbl: Label3D = game._label3d(holder, "Desert Falcon · 荒漠猎隼", Vector3(0, 1.05, 0), 26, Color("ffd984"))
		lbl.visibility_range_end = 78.0
		lbl.visible = false

		var init_ang := float(sp.phase)
		var c0: Vector3 = sp.center
		holder.position = Vector3(c0.x + cos(init_ang) * float(sp.rx), c0.y + sin(init_ang * 2.0) * 1.25, c0.z + sin(init_ang) * float(sp.rz))
		desert_falcons.append({
			"idx": i,
			"node": holder,
			"vis": vis,
			"anim": anim,
			"area": area,
			"label": lbl,
			"base_scale": 1.48,
			"state": "fly",
			"timer": 0.0,
			"center": sp.center,
			"rx": float(sp.rx),
			"rz": float(sp.rz),
			"spd": float(sp.spd),
			"angle": init_ang,
			"cycle_t": float(i) * 0.85,
			"gliding": false
		})

func reset():
	discovered_species.clear()
	discovered_desert_species.clear()
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
		a.climb_h = 0.0
		a.charge_cd = 0.0
		a.chase_accum = 0.0
		a.pos = _initial_pos(HABITAT_ANIMALS[a.idx])
		a.dir = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		a.root.visible = true
		a.root.position = a.pos
		a.root.rotation = Vector3(0.0, atan2(-a.dir.x, -a.dir.z), 0.0)
		a.visual.rotation = Vector3.ZERO
		a.visual.position = Vector3(0.0, -0.14 if a.state == "ambush" else 0.0, 0.0)
		a.visual.scale = Vector3.ONE * a.visual_scale
		a.label.text = a.base_label
		a.label.modulate = Color("f2f7d4")
		a.label.visible = false
		a.tag_left = 0.0
		a.tag_shown_once = false
		a.area.collision_layer = HIT_LAYER
		a.area.scale = Vector3.ONE
		_play_critter_anim(a.anim, ["Fly"] if a.kind == "butterfly" else (["Swim"] if a.kind in ["fish", "shrimp"] else ["Idle"]), 1.0, float(a.idx) * 0.13)
	for eg in sky_egrets:
		eg.state = "fly"
		eg.timer = 0.0
		eg.node.visible = true
		eg.area.collision_layer = HIT_LAYER
		eg.label.visible = false
		if eg.vis != null:
			(eg.vis as Node3D).scale = Vector3.ONE * float(eg.base_scale)
			(eg.vis as Node3D).rotation = Vector3(0.0, 0.0, 0.20)
		_play_critter_anim(eg.anim, ["Fly"], 1.32)
	for f in flora_nodes:
		var lbl: Label3D = f.get_meta("label_node")
		lbl.text = "%s · %s [F]" % [f.get_meta("en"), f.get_meta("zh")]
		lbl.modulate = Color.WHITE
		lbl.visible = false
		f.set_meta("tag_left", 0.0)
		f.set_meta("tag_shown_once", false)
		var ring: MeshInstance3D = f.get_meta("ring_node")
		ring.visible = true
	_reset_desert_wildlife_state()
	set_active_map(active_map_id)

func _reset_desert_wildlife_state():
	for da in desert_animals:
		da.state = "idle"
		da.timer = 0.0
		da.pos = _desert_initial_pos(DESERT_ANIMALS[da.idx])
		da.dir = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		da.root.visible = true
		da.root.position = da.pos
		da.root.rotation = Vector3(0.0, atan2(-da.dir.x, -da.dir.z), 0.0)
		da.visual.rotation = Vector3.ZERO
		da.visual.position = Vector3.ZERO
		da.visual.scale = Vector3.ONE * float(da.visual_scale)
		da.label.text = da.base_label
		da.label.modulate = Color("ffe8a6")
		da.label.visible = false
		da.tag_left = 0.0
		da.tag_shown_once = false
		_play_critter_anim(da.anim, ["Idle", "Walk"], 1.0, float(da.idx) * 0.17)
	for df in desert_falcons:
		df.state = "fly"
		df.timer = 0.0
		df.node.visible = true
		df.label.visible = false
		if df.vis != null:
			(df.vis as Node3D).scale = Vector3.ONE * float(df.base_scale)
			(df.vis as Node3D).rotation = Vector3(0.0, 0.0, 0.22)
		_play_critter_anim(df.anim, ["Fly"], 1.38)

func _flash_animal_tag(a: Dictionary, duration: float = 2.2, force_show: bool = false):
	if not force_show and bool(a.get("tag_shown_once", false)):
		return
	a.tag_shown_once = true
	a.tag_left = maxf(float(a.get("tag_left", 0.0)), duration)
	a.label.visible = true

func update(delta: float):
	if frozen_for_capture or not map_enabled:
		return
	flee_sfx_cooldown = maxf(0.0, flee_sfx_cooldown - delta)
	_update_fx(delta)
	if active_map_id == "ahsarah":
		_update_desert_wildlife(delta)
		return
	_update_sky_egrets(delta)
	if not is_instance_valid(game.player):
		return
	var ppos: Vector3 = game.player.position
	# Flora one-time brief discovery reveal (v0.8.0 #14: clean scenic landscape!)
	for f in flora_nodes:
		var flbl: Label3D = f.get_meta("label_node")
		var ftl: float = float(f.get_meta("tag_left", 0.0))
		if ftl > 0.0:
			ftl = maxf(0.0, ftl - delta)
			f.set_meta("tag_left", ftl)
			if ftl <= 0.0:
				flbl.visible = false
		elif not bool(f.get_meta("tag_shown_once", false)) and ppos.distance_squared_to(f.position) <= 23.0:
			f.set_meta("tag_shown_once", true)
			f.set_meta("tag_left", 2.2)
			flbl.visible = true
	for a in animals:
		a.charge_cd = maxf(0.0, float(a.charge_cd) - delta)
		if float(a.get("tag_left", 0.0)) > 0.0 and a.state != "charge":
			a.tag_left = maxf(0.0, float(a.tag_left) - delta)
			if float(a.tag_left) <= 0.0 and a.state != "downed":
				a.label.visible = false
		match a.state:
			"hidden":
				a.timer -= delta
				if a.timer <= 0.0:
					a.state = "ambush" if a.kind == "boar" else "idle"
					a.fly_alt = 0.0
					a.climb_h = 0.0
					a.pos = _initial_pos(HABITAT_ANIMALS[a.idx])
					a.root.position = a.pos
					a.visual.rotation = Vector3.ZERO
					a.visual.position = Vector3(0.0, -0.14 if a.state == "ambush" else 0.0, 0.0)
					a.visual.scale = Vector3.ONE * a.visual_scale
					a.label.text = a.base_label
					a.label.modulate = Color("f2f7d4")
					a.label.visible = false
					a.tag_left = 0.0
					a.area.collision_layer = HIT_LAYER
					a.root.visible = true
					_play_critter_anim(a.anim, ["Idle"], 1.0)
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
			_:
				_step_creature(a, delta, ppos)

func _update_sky_egrets(delta: float):
	for eg in sky_egrets:
		var st := str(eg.get("state", "fly"))
		if st == "hidden":
			eg.timer = float(eg.timer) - delta
			if float(eg.timer) <= 0.0:
				eg.state = "fly"
				eg.node.visible = true
				eg.area.collision_layer = HIT_LAYER
				eg.label.visible = false
				if eg.vis != null:
					(eg.vis as Node3D).scale = Vector3.ONE * float(eg.base_scale)
					(eg.vis as Node3D).rotation = Vector3(0.0, 0.0, 0.20)
				_play_critter_anim(eg.anim, ["Fly"], 1.32)
			continue
		if st == "downed":
			eg.timer = float(eg.timer) - delta
			var n_down: Node3D = eg.node
			n_down.position.y -= 3.6 * delta
			if eg.vis != null:
				var fade := clampf(float(eg.timer) / 1.15, 0.04, 1.0)
				(eg.vis as Node3D).scale = Vector3.ONE * float(eg.base_scale) * fade
				(eg.vis as Node3D).rotation.z += 5.4 * delta
			if float(eg.timer) <= 0.0:
				eg.state = "hidden"
				eg.timer = 15.0
				n_down.visible = false
				eg.area.collision_layer = 0
			continue

		eg.angle += float(eg.spd) * delta
		eg.cycle_t = fmod(float(eg.cycle_t) + delta, 5.8)
		var want_glide := float(eg.cycle_t) > 3.5
		if want_glide != bool(eg.gliding):
			eg.gliding = want_glide
			_play_critter_anim(eg.anim, ["Glide", "Fly"] if want_glide else ["Fly"], 0.92 if want_glide else 1.35)
		var ang: float = eg.angle
		var c: Vector3 = eg.center
		var nx := c.x + cos(ang) * float(eg.rx)
		var nz := c.z + sin(ang) * float(eg.rz)
		var ny := c.y + sin(ang * 2.0) * 1.15
		var tx := -sin(ang) * float(eg.rx)
		var tz := cos(ang) * float(eg.rz)
		var n: Node3D = eg.node
		n.position = Vector3(nx, ny, nz)
		n.rotation.y = atan2(-tx, -tz)
		if eg.vis != null:
			var flap_lift := 0.0 if want_glide else sin(float(eg.cycle_t) * 11.0) * 0.06
			(eg.vis as Node3D).rotation.z = 0.20 + sin(ang) * 0.08
			(eg.vis as Node3D).position.y = flap_lift

func _step_creature(a: Dictionary, delta: float, ppos: Vector3):
	var kind: String = a.kind
	var pos: Vector3 = a.pos
	var dist := Vector2(pos.x - ppos.x, pos.z - ppos.z).length()
	if dist > 42.0 and a.state in ["idle", "ambush"]:
		if a.anim != null:
			(a.anim as AnimationPlayer).speed_scale = 0.0
		return

	if kind == "boar" and a.state == "ambush":
		a.phase += delta * 2.5
		a.visual.position.y = -0.14 + sin(a.phase) * 0.015
		_play_critter_anim(a.anim, ["Idle"], 0.7)
		if dist < 11.5:
			_trigger_boar_ambush(a, ppos, true)
		return

	if kind == "squirrel" and a.state in ["climb_approach", "climb_up", "perched_tree"]:
		_move_climbing_squirrel(a, delta, ppos, dist)
		return

	if kind == "boar" and a.state == "charge":
		_move_charging_boar(a, delta, ppos, dist)
		return

	var flee_r := 10.5 if kind == "deer" else (8.6 if kind in ["rabbit", "squirrel", "fox", "bird", "pheasant"] else (7.2 if kind == "boar" else (4.2 if kind == "butterfly" else 4.8)))
	if dist < flee_r and a.state == "idle":
		_start_flee(a, ppos, true)
		if a.state in ["climb_approach", "charge"]:
			return

	# Wild boar counter-charge when chased closely by the player!
	if kind == "boar" and a.state == "flee" and float(a.charge_cd) <= 0.0 and dist < 8.8:
		a.chase_accum = float(a.chase_accum) + delta
		if float(a.chase_accum) >= 0.85:
			a.chase_accum = 0.0
			if rng.randf() < BOAR_CHARGE_CHANCE:
				trigger_boar_charge(a)
				return
	else:
		a.chase_accum = maxf(0.0, float(a.chase_accum) - delta * 0.5)

	if a.state in ["flee", "fly"]:
		a.timer -= delta
		if a.timer <= 0.0 and dist > 14.0:
			a.state = "idle"
			a.fly_alt = 0.0
			a.label.text = a.base_label
			a.label.modulate = Color("f2f7d4")
			a.wander_cd = rng.randf_range(0.8, 2.4)

	a.phase += delta * (11.5 if a.state in ["flee", "fly"] else 4.2)
	match kind:
		"fish":
			_move_fish(a, delta, ppos)
		"shrimp":
			_move_shrimp(a, delta, ppos)
		"crab":
			_move_crab(a, delta, ppos)
		"turtle":
			_move_turtle(a, delta, ppos)
		"butterfly":
			_move_butterfly(a, delta, ppos)
		"bird":
			_move_bird(a, delta, ppos)
		"pheasant":
			_move_pheasant(a, delta, ppos)
		_:
			_move_land_critter(a, delta, ppos)

func _find_nearest_tree_trunk(from_pos: Vector3, max_dist: float = 22.0) -> Dictionary:
	if not is_instance_valid(game.landscape) or not ("tree_trunks" in game.landscape):
		return {}
	var trunks: Array = game.landscape.tree_trunks
	var radii: Array = game.landscape.tree_trunk_radii
	var best_d := max_dist
	var best_idx := -1
	for i in trunks.size():
		var tp: Vector3 = trunks[i]
		var d := Vector2(tp.x - from_pos.x, tp.z - from_pos.z).length()
		if d < best_d:
			best_d = d
			best_idx = i
	if best_idx < 0:
		return {}
	return {
		"pos": trunks[best_idx],
		"radius": float(radii[best_idx]) if best_idx < radii.size() else 0.32
	}

func start_squirrel_tree_climb(a: Dictionary) -> bool:
	if a.kind != "squirrel":
		return false
	var tree_info := _find_nearest_tree_trunk(a.pos, 24.0)
	if tree_info.is_empty():
		return false
	a.tree_trunk = tree_info.pos
	a.tree_radius = float(tree_info.radius)
	a.climb_h = 0.08
	a.climb_target_h = rng.randf_range(2.85, 3.55)
	var from_t := Vector2(a.pos.x - a.tree_trunk.x, a.pos.z - a.tree_trunk.z)
	a.climb_angle = atan2(from_t.y, from_t.x) if from_t.length() > 0.05 else 0.0
	a.state = "climb_approach"
	a.timer = 6.5
	return true

func _move_climbing_squirrel(a: Dictionary, delta: float, ppos: Vector3, dist_player: float):
	var tp: Vector3 = a.tree_trunk
	var tr: float = float(a.tree_radius)
	if a.state == "climb_approach":
		var apos: Vector3 = a.pos
		var bark_x := tp.x + cos(float(a.climb_angle)) * (tr + 0.06)
		var bark_z := tp.z + sin(float(a.climb_angle)) * (tr + 0.06)
		var to_bark := Vector3(bark_x - apos.x, 0.0, bark_z - apos.z)
		var rem := to_bark.length()
		if rem <= 0.22:
			a.state = "climb_up"
			a.pos = Vector3(bark_x, float(tp.y) + 0.12, bark_z)
			a.climb_h = 0.12
			return
		var dir := to_bark / rem
		a.dir = dir
		var step := minf(rem, 7.6 * delta)
		var nx: float = apos.x + dir.x * step
		var nz: float = apos.z + dir.z * step
		a.pos = Vector3(nx, float(game.Layout.fast_height(nx, nz)), nz)
		a.root.position = a.pos
		a.root.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
		a.visual.position = Vector3.ZERO
		a.visual.rotation = Vector3.ZERO
		_play_critter_anim(a.anim, ["Run"], 1.85)
		return

	if a.state == "climb_up":
		a.climb_h = float(a.climb_h) + 3.45 * delta
		a.climb_angle = float(a.climb_angle) + 0.55 * delta
		var ang := float(a.climb_angle)
		var out_x := cos(ang)
		var out_z := sin(ang)
		var bx := tp.x + out_x * (tr + 0.05)
		var bz := tp.z + out_z * (tr + 0.05)
		var by := float(tp.y) + float(a.climb_h)
		a.pos = Vector3(bx, by, bz)
		a.root.position = a.pos
		# Face inward toward trunk (-Z -> -out), pitch +86 deg around X so nose points UP (+Y) & paws hug bark!
		a.root.rotation = Vector3(0.0, atan2(out_x, out_z), 0.0)
		a.visual.position = Vector3.ZERO
		a.visual.rotation = Vector3(PI * 0.48, 0.0, 0.0)
		_play_critter_anim(a.anim, ["Climb", "Run"], 2.15)
		if float(a.climb_h) >= float(a.climb_target_h):
			a.state = "perched_tree"
			a.timer = 7.5
		return

	if a.state == "perched_tree":
		a.timer -= delta
		a.phase += delta * 4.0
		var ang := float(a.climb_angle)
		var out_x := cos(ang)
		var out_z := sin(ang)
		a.pos = Vector3(tp.x + out_x * (tr + 0.06), float(tp.y) + float(a.climb_target_h), tp.z + out_z * (tr + 0.06))
		a.root.position = a.pos
		a.root.rotation = Vector3(0.0, atan2(out_x, out_z), 0.0)
		a.visual.position = Vector3.ZERO
		a.visual.rotation = Vector3(PI * 0.46, sin(a.phase * 0.8) * 0.18, 0.0)
		_play_critter_anim(a.anim, ["Idle"], 1.2)
		if a.timer <= 0.0 and dist_player > 15.5:
			var gx := tp.x + out_x * (tr + 0.45)
			var gz := tp.z + out_z * (tr + 0.45)
			a.pos = Vector3(gx, float(game.Layout.fast_height(gx, gz)), gz)
			a.root.position = a.pos
			a.visual.rotation = Vector3.ZERO
			a.state = "idle"
			a.wander_cd = 1.5

func trigger_boar_charge(a: Dictionary):
	if a.kind != "boar" or not is_instance_valid(game.player):
		return
	var ppos: Vector3 = game.player.position
	var to_p := Vector3(ppos.x - a.pos.x, 0.0, ppos.z - a.pos.z)
	if to_p.length_squared() < 0.001:
		to_p = Vector3(0.0, 0.0, -1.0)
	a.dir = to_p.normalized()
	a.state = "charge"
	a.timer = 2.35
	a.charge_cd = 7.5
	a.chase_accum = 0.0
	a.visual.position = Vector3.ZERO
	a.visual.rotation = Vector3.ZERO
	a.label.visible = true
	a.label.text = "⚠ 小野猪冲撞 · %s!" % a.en
	a.label.modulate = Color("ff8e72")
	_play_critter_anim(a.anim, ["Gore", "Run"], 1.95)
	game.play_sfx("boar_charge", -7)
	game._notice("🐗 小野猪被逼急反身冲撞！快向两侧闪避或跳跃！", Color("ff9b73"))

func _move_charging_boar(a: Dictionary, delta: float, ppos: Vector3, _dist_xz: float):
	a.timer -= delta
	var to_p := Vector3(ppos.x - a.pos.x, 0.0, ppos.z - a.pos.z)
	if to_p.length() > 0.25:
		a.dir = a.dir.lerp(to_p.normalized(), minf(delta * 5.2, 1.0)).normalized()
	var charge_spd := 9.8
	var nxt: Vector3 = a.pos + a.dir * charge_spd * delta
	nxt.x = clampf(nxt.x, float(game.Layout.FENCE_MIN_X) + 1.6, float(game.Layout.FENCE_MAX_X) - 1.6)
	nxt.z = clampf(nxt.z, float(game.Layout.FENCE_MIN_Z) + 1.6, float(game.Layout.FENCE_MAX_Z) - 1.6)
	nxt.y = float(game.Layout.fast_height(nxt.x, nxt.z))
	a.pos = nxt
	a.root.position = nxt
	a.root.rotation.y = atan2(-a.dir.x, -a.dir.z)
	a.visual.position = Vector3.ZERO
	a.visual.rotation = Vector3.ZERO
	_play_critter_anim(a.anim, ["Gore", "Run"], 1.95)

	var hit_dxz := Vector2(ppos.x - nxt.x, ppos.z - nxt.z).length()
	var hit_dy := absf(ppos.y - nxt.y)
	if hit_dxz <= 1.38 and hit_dy <= 1.18:
		_resolve_boar_gore_impact(a, ppos)
		return
	if a.timer <= 0.0:
		a.state = "flee"
		a.timer = 3.2
		a.label.text = a.base_label
		a.label.modulate = Color("f2f7d4")
		a.label.visible = false

func _resolve_boar_gore_impact(a: Dictionary, ppos: Vector3):
	var push_dir := Vector3(ppos.x - a.pos.x, 0.0, ppos.z - a.pos.z)
	if push_dir.length_squared() < 0.001:
		push_dir = a.dir
	push_dir = push_dir.normalized()
	if is_instance_valid(game.player) and game.player.has_method("apply_knockback"):
		game.player.apply_knockback(push_dir * 8.2 + Vector3.UP * 2.5)
		game.player.recoil = maxf(float(game.player.recoil), 1.35)
	game.play_sfx("animal_hit", -6)
	if is_instance_valid(game.combat) and game.combat.in_field():
		game.combat.apply_physical_trauma(BOAR_CHARGE_DAMAGE, 5, "行动失败 · 遭山林野猪冲撞重伤")
		game._notice("💥 被【小野猪 · Wild Boar】獠牙撞中！生命 -%d · 请用 [H]医疗包 或 [F]奇植 治疗！" % BOAR_CHARGE_DAMAGE, Color("ff6e6e"))
	else:
		game.screen_flash.color = Color(0.95, 0.18, 0.10, 0.24)
		game._notice("💥 被【小野猪 · Wild Boar】冲撞击退！（实战模式将损失 %d 点生命值）" % BOAR_CHARGE_DAMAGE, Color("ff9b73"))
	# After ramming, boar veers away into flee state
	a.dir = Vector3(-push_dir.z, 0.0, push_dir.x).normalized()
	a.state = "flee"
	a.timer = 3.6
	a.label.text = a.base_label
	a.label.modulate = Color("f2f7d4")
	a.label.visible = false

func _trigger_boar_ambush(a: Dictionary, ppos: Vector3, by_proximity: bool):
	_flash_animal_tag(a, 2.2)
	a.visual.position.y = 0.0
	_spawn_vanish_motes(a.pos + Vector3(0.0, 0.32, 0.0))
	if by_proximity and not discovered_species.has("boar"):
		discovered_species["boar"] = true
		game.speak_english(a.tts)
	var dist := Vector2(a.pos.x - ppos.x, a.pos.z - ppos.z).length()
	if dist < 9.2 and float(a.charge_cd) <= 0.0 and rng.randf() < 0.36:
		trigger_boar_charge(a)
		return
	a.state = "flee"
	a.timer = 5.4
	var to_p := Vector3(ppos.x - a.pos.x, 0.0, ppos.z - a.pos.z)
	if to_p.length_squared() < 0.01:
		to_p = Vector3(1.0, 0.0, 0.0)
	var tangent := Vector3(-to_p.z, 0.0, to_p.x).normalized()
	if a.idx % 2 == 1:
		tangent = -tangent
	a.dir = (tangent * 0.82 - to_p.normalized() * 0.58).normalized()
	_play_critter_anim(a.anim, ["Run"], 1.75)
	game.play_sfx("boar_charge", -9)
	if by_proximity:
		game._notice("🐗 灌木丛惊起【%s · %s】！四蹄飞奔横冲山坡（紧追小心反击）！" % [a.en, a.zh], Color("ffd48a"))

func _start_flee(a: Dictionary, away_from: Vector3, by_proximity: bool = false):
	if a.kind == "boar" and a.state == "ambush":
		_trigger_boar_ambush(a, away_from, by_proximity)
		return
	if flee_sfx_cooldown <= 0.0:
		flee_sfx_cooldown = 1.35
		game.play_sfx("bird_flap" if a.kind in ["bird", "pheasant"] else ("boar_charge" if a.kind == "boar" else "animal_flee"), -12)
	if by_proximity and a.pos.distance_to(game.player.position) < 11.2:
		_flash_animal_tag(a, 2.2)
		if not discovered_species.has(a.kind):
			discovered_species[a.kind] = true
			game.speak_english(a.tts)
			var hint_msg := "惊动后窜上树干躲避！" if a.kind == "squirrel" else ("惊起后振翅低飞跃林！" if a.kind == "pheasant" else ("受惊潜入清溪游水！" if a.kind == "turtle" else ("翩然起舞掠过花丛！" if a.kind == "butterfly" else "靠近惊动会敏捷逃逸！")))
			var can_toast: bool = (not game.rules.prologue_mode) and (game.closest_interaction == null) and not (is_instance_valid(game.threat_banner) and game.threat_banner.visible)
			if can_toast:
				game._notice("🌿 发现山野生灵：%s（%s）· %s" % [a.en, a.zh, hint_msg], Color("9ef5b8"))
	if a.kind == "squirrel" and start_squirrel_tree_climb(a):
		return
	a.state = "fly" if a.kind in ["bird", "pheasant"] else "flee"
	a.timer = 5.4 if a.kind == "bird" else (3.8 if a.kind == "pheasant" else (4.5 if a.kind in ["rabbit", "squirrel", "fox", "boar", "deer"] else 3.0))
	var delta_xz := Vector3(a.pos.x - away_from.x, 0.0, a.pos.z - away_from.z)
	if delta_xz.length_squared() < 0.01:
		delta_xz = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	a.dir = delta_xz.normalized()

func _move_land_critter(a: Dictionary, delta: float, ppos: Vector3):
	var kind: String = a.kind
	var speed := 1.45
	if a.state == "flee":
		match kind:
			"deer": speed = 9.4
			"boar": speed = 9.0
			"fox": speed = 8.6
			"rabbit": speed = 7.4
			_: speed = 6.8
	else:
		match kind:
			"deer": speed = 1.90
			"boar": speed = 1.75
			"fox": speed = 2.05
			"rabbit": speed = 1.55
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

	nxt.y = float(game.Layout.fast_height(nxt.x, nxt.z))
	# Align body pitch naturally with mountain slope gradient!
	var ahead_y := float(game.Layout.fast_height(nxt.x + a.dir.x * 0.45, nxt.z + a.dir.z * 0.45))
	var slope_pitch := clampf(atan2(ahead_y - nxt.y, 0.45), -0.42, 0.42)
	a.pos = nxt
	a.root.position = nxt
	a.root.rotation.y = atan2(-a.dir.x, -a.dir.z)
	a.visual.position = Vector3.ZERO
	var eff_pitch := slope_pitch * 0.18 if kind == "rabbit" else slope_pitch
	a.visual.rotation = Vector3(eff_pitch, 0.0, 0.0)

	if a.state == "flee":
		_play_critter_anim(a.anim, ["Run"], 1.45 if kind == "rabbit" else (1.75 if kind in ["boar", "fox"] else 1.65))
	else:
		_play_critter_anim(a.anim, ["Walk", "Run"], 1.15)

func _move_bird(a: Dictionary, delta: float, ppos: Vector3):
	if a.state != "fly":
		a.area.scale = Vector3.ONE
		var home_p: Vector3 = a.home
		a.pos = a.pos.lerp(home_p, minf(delta * 2.4, 1.0))
		a.root.position = a.pos
		a.root.rotation.y = sin(a.phase * 0.45 + float(a.idx)) * 0.85
		a.visual.position = Vector3.ZERO
		a.visual.rotation = Vector3.ZERO
		_play_critter_anim(a.anim, ["Idle"], 1.0)
		return

	# Active 3D banked climb & flapping flight escape (expanded hitbox while airborne)!
	a.area.scale = Vector3.ONE * 1.55
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
	var gy := float(game.Layout.fast_height(nxt_xz.x, nxt_xz.y))
	a.pos = Vector3(nxt_xz.x, maxf(gy + float(a.perch_h), gy + float(a.fly_alt)), nxt_xz.y)
	a.root.position = a.pos
	a.root.rotation.y = atan2(-a.dir.x, -a.dir.z)
	a.visual.position.y = sin(a.phase * 1.6) * 0.06
	a.visual.rotation = Vector3(0.08, 0.0, sin(a.phase * 0.7) * 0.16)
	_play_critter_anim(a.anim, ["Fly"], 1.55)

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
	a.visual.rotation = Vector3.ZERO
	_play_critter_anim(a.anim, ["Swim fast", "Swim"] if a.state == "flee" else ["Swim"], 1.8 if a.state == "flee" else 1.15)

func _move_shrimp(a: Dictionary, delta: float, ppos: Vector3):
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
	var wy := float(game.Layout.stream_water_y(a.stream_z)) - 0.26 + absf(sin(a.phase * 1.6)) * (0.07 if a.state == "flee" else 0.02)
	var nxt := Vector3(px, wy, a.stream_z)
	a.pos = nxt
	a.root.position = nxt
	if a.state == "flee":
		var toward := Vector3(ppos.x - nxt.x, 0.0, ppos.z - nxt.z)
		if toward.length() > 0.05:
			a.root.rotation.y = atan2(-toward.x, -toward.z)
		_play_critter_anim(a.anim, ["Swim fast", "Swim"], 2.0)
	else:
		a.root.rotation.y = sin(a.phase * 0.3 + float(a.idx)) * 1.4
		_play_critter_anim(a.anim, ["Swim", "Idle"], 1.05)

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
	var nxt := Vector3(px, float(game.Layout.fast_height(px, a.stream_z)) + 0.03, a.stream_z)
	a.pos = nxt
	a.root.position = nxt
	a.root.rotation.y = (PI * 0.5 if float(a.bank_side) > 0.0 else -PI * 0.5) + sin(a.phase) * 0.12
	a.visual.position = Vector3.ZERO
	_play_critter_anim(a.anim, ["Walk Sideways", "Run", "Walk"], 1.95 if a.state == "flee" else 1.15)

func _move_pheasant(a: Dictionary, delta: float, ppos: Vector3):
	if a.state == "fly":
		# Startled pheasant bursts into low skimming glide-flight (2.4m altitude) before settling down!
		var away := Vector3(a.pos.x - ppos.x, 0.0, a.pos.z - ppos.z)
		if away.length() > 0.3 and a.timer > 1.5:
			a.dir = a.dir.lerp(away.normalized(), minf(delta * 3.0, 1.0)).normalized()
		var spd := 8.8
		var nxt_x := clampf(a.pos.x + a.dir.x * spd * delta, float(game.Layout.FENCE_MIN_X) + 2.2, float(game.Layout.FENCE_MAX_X) - 2.2)
		var nxt_z := clampf(a.pos.z + a.dir.z * spd * delta, float(game.Layout.FENCE_MIN_Z) + 2.2, float(game.Layout.FENCE_MAX_Z) - 2.2)
		var target_alt := 2.4 if a.timer > 1.1 else 0.0
		a.fly_alt = lerpf(float(a.fly_alt), target_alt, minf(delta * 3.4, 1.0))
		var gy := float(game.Layout.fast_height(nxt_x, nxt_z))
		a.pos = Vector3(nxt_x, gy + float(a.fly_alt), nxt_z)
		a.root.position = a.pos
		a.root.rotation.y = atan2(-a.dir.x, -a.dir.z)
		a.visual.position.y = sin(a.phase * 1.8) * 0.05
		a.visual.rotation = Vector3(0.06, 0.0, sin(a.phase * 0.9) * 0.14)
		_play_critter_anim(a.anim, ["Fly", "Run"], 1.65)
		return
	_move_land_critter(a, delta, ppos)

func _move_turtle(a: Dictionary, delta: float, ppos: Vector3):
	# Tranquil pond turtle basking near stream bank & sliding into clear water ("Swim") when startled!
	var z_min := float(game.Layout.STREAM_Z_MIN) + 4.0
	var z_max := float(game.Layout.FENCE_MAX_Z) - 2.0
	var in_water: bool = (str(a.state) == "flee")
	var spd := 2.4 if in_water else 0.42
	var z_step := (1.0 if float(a.stream_z) >= ppos.z else -1.0) if in_water else (1.0 if float(a.dir.z) >= 0.0 else -1.0)
	if not in_water:
		a.wander_cd -= delta
		if a.wander_cd <= 0.0:
			a.wander_cd = rng.randf_range(2.2, 4.8)
			a.dir.z = -a.dir.z
	a.stream_z = clampf(float(a.stream_z) + z_step * spd * delta, z_min, z_max)
	var cx := float(game.Layout.stream_center_x(a.stream_z))
	var target_off := (0.28 * signf(float(a.bank_side))) if in_water else float(a.bank_side)
	var prev_pos: Vector3 = a.pos
	var cur_off: float = prev_pos.x - cx
	var nxt_off := lerpf(cur_off, target_off, minf(delta * (3.2 if in_water else 1.4), 1.0))
	var px := cx + nxt_off
	var py := (float(game.Layout.stream_water_y(a.stream_z)) - 0.10) if in_water else (float(game.Layout.fast_height(px, a.stream_z)) + 0.02)
	var nxt := Vector3(px, py, float(a.stream_z))
	var look: Vector3 = nxt - prev_pos
	look.y = 0.0
	a.pos = nxt
	a.root.position = nxt
	if look.length() > 0.002:
		a.root.rotation.y = atan2(-look.x, -look.z)
	a.visual.position = Vector3.ZERO
	a.visual.rotation = Vector3.ZERO
	_play_critter_anim(a.anim, ["Swim", "Walk"] if in_water else ["Walk", "Idle"], 1.55 if in_water else 0.90)

func _move_butterfly(a: Dictionary, delta: float, ppos: Vector3):
	# Iridescent swallowtail dancing smoothly in figure-8s above blossoms & rising higher when approached
	var home_p: Vector3 = a.home
	var prev_p: Vector3 = a.pos
	var t: float = float(a.phase) * 0.42 + float(a.idx) * 1.17
	var flutter_r := 3.6 if str(a.state) == "flee" else 2.2
	var target_x := home_p.x + sin(t) * flutter_r
	var target_z := home_p.z + sin(t * 2.0) * (flutter_r * 0.65)
	if str(a.state) == "flee":
		var away := Vector3(prev_p.x - ppos.x, 0.0, prev_p.z - ppos.z)
		if away.length() > 0.2:
			target_x = prev_p.x + away.normalized().x * 3.8 * delta
			target_z = prev_p.z + away.normalized().z * 3.8 * delta
	target_x = clampf(target_x, float(game.Layout.FENCE_MIN_X) + 2.0, float(game.Layout.FENCE_MAX_X) - 2.0)
	target_z = clampf(target_z, float(game.Layout.FENCE_MIN_Z) + 2.0, float(game.Layout.FENCE_MAX_Z) - 2.0)
	var gy := float(game.Layout.fast_height(target_x, target_z))
	var alt := (2.25 if str(a.state) == "flee" else 1.05) + sin(t * 2.6) * 0.34
	var nxt := Vector3(lerpf(prev_p.x, target_x, minf(delta * 3.5, 1.0)), gy + alt, lerpf(prev_p.z, target_z, minf(delta * 3.5, 1.0)))
	var look: Vector3 = nxt - prev_p
	look.y = 0.0
	a.pos = nxt
	a.root.position = nxt
	if look.length() > 0.002:
		a.root.rotation.y = atan2(-look.x, -look.z)
	a.visual.position.y = sin(a.phase * 2.4) * 0.06
	a.visual.rotation = Vector3(0.12, 0.0, sin(t * 1.8) * 0.22)
	_play_critter_anim(a.anim, ["Fly", "Idle"], 1.85 if a.state == "flee" else 1.35)

func _record_desert_species_discovery(kind: String, en_name: String, zh_name: String, tts_key: String, announce: bool):
	var first_time := not discovered_desert_species.has(kind)
	discovered_desert_species[kind] = true
	if first_time:
		game.speak_english(tts_key)
		if is_instance_valid(game.achievements):
			game.achievements.record_stat("desert_species_found", discovered_desert_species.size(), true)
		if announce:
			var can_toast: bool = (not game.rules.prologue_mode) and (game.closest_interaction == null) and not (is_instance_valid(game.threat_banner) and game.threat_banner.visible)
			if can_toast:
				game._notice("🏜 发现阿萨拉荒漠生灵：%s（%s）· 生态图鉴 %d/%d" % [en_name, zh_name, discovered_desert_species.size(), TOTAL_DESERT_SPECIES], Color("ffd984"))

func _update_desert_wildlife(delta: float):
	# 1) Update 6 soaring Desert Falcons
	for df in desert_falcons:
		var st := str(df.get("state", "fly"))
		if st == "hidden":
			df.timer = float(df.timer) - delta
			if float(df.timer) <= 0.0:
				df.state = "fly"
				df.node.visible = true
				df.area.collision_layer = HIT_LAYER
				df.label.visible = false
				if df.vis != null:
					(df.vis as Node3D).scale = Vector3.ONE * float(df.base_scale)
					(df.vis as Node3D).rotation = Vector3(0.0, 0.0, 0.22)
				_play_critter_anim(df.anim, ["Fly"], 1.38)
			continue
		if st == "downed":
			df.timer = float(df.timer) - delta
			var nd: Node3D = df.node
			nd.position.y -= 3.8 * delta
			if df.vis != null:
				var fade := clampf(float(df.timer) / 1.15, 0.04, 1.0)
				(df.vis as Node3D).scale = Vector3.ONE * float(df.base_scale) * fade
				(df.vis as Node3D).rotation.z += 5.2 * delta
			if float(df.timer) <= 0.0:
				df.state = "hidden"
				df.timer = 16.0
				nd.visible = false
				df.area.collision_layer = 0
			continue
		df.angle += float(df.spd) * delta
		df.cycle_t = fmod(float(df.cycle_t) + delta, 5.2)
		var ang: float = df.angle
		var c: Vector3 = df.center
		var nx := c.x + cos(ang) * float(df.rx)
		var nz := c.z + sin(ang) * float(df.rz)
		var ny := c.y + sin(ang * 2.0) * 1.25
		var tx := -sin(ang) * float(df.rx)
		var tz := cos(ang) * float(df.rz)
		var n: Node3D = df.node
		n.position = Vector3(nx, ny, nz)
		n.rotation.y = atan2(-tx, -tz)
		if df.vis != null:
			(df.vis as Node3D).rotation.z = 0.22 + sin(ang) * 0.10
			(df.vis as Node3D).position.y = sin(float(df.cycle_t) * 10.0) * 0.05
		if is_instance_valid(game.player) and not discovered_desert_species.has("falcon"):
			if Vector2(nx - game.player.position.x, nz - game.player.position.z).length() < 18.0:
				_record_desert_species_discovery("falcon", "Desert Falcon", "荒漠猎隼", "desert falcon", true)

	if not is_instance_valid(game.player):
		return
	var ppos: Vector3 = game.player.position
	for da in desert_animals:
		if float(da.get("tag_left", 0.0)) > 0.0:
			da.tag_left = maxf(0.0, float(da.tag_left) - delta)
			if float(da.tag_left) <= 0.0 and da.state != "downed":
				da.label.visible = false
		match da.state:
			"hidden":
				da.timer -= delta
				if da.timer <= 0.0:
					da.state = "idle"
					da.pos = _desert_initial_pos(DESERT_ANIMALS[da.idx])
					da.root.position = da.pos
					da.visual.rotation = Vector3.ZERO
					da.visual.scale = Vector3.ONE * float(da.visual_scale)
					da.label.visible = false
					da.area.collision_layer = HIT_LAYER
					da.root.visible = true
					_play_critter_anim(da.anim, ["Idle", "Walk"], 1.0)
			"downed":
				da.timer -= delta
				var fade := clampf(float(da.timer) / 0.65, 0.02, 1.0)
				da.visual.scale = Vector3.ONE * float(da.visual_scale) * fade
				da.visual.rotation.z = lerpf(da.visual.rotation.z, PI * 0.48, minf(delta * 14.0, 1.0))
				if da.timer <= 0.0:
					da.state = "hidden"
					da.timer = 22.0
					da.root.visible = false
					da.area.collision_layer = 0
			_:
				_step_desert_critter(da, delta, ppos)

func _step_desert_critter(da: Dictionary, delta: float, ppos: Vector3):
	var kind: String = da.kind
	var pos: Vector3 = da.pos
	var dist := Vector2(pos.x - ppos.x, pos.z - ppos.z).length()
	if dist > 48.0 and da.state == "idle":
		if da.anim != null:
			(da.anim as AnimationPlayer).speed_scale = 0.0
		return
	var discover_r := 11.5 if kind == "camel" else (9.5 if kind == "fennec" else 6.0)
	if dist < discover_r:
		_flash_animal_tag(da, 2.4)
		_record_desert_species_discovery(kind, da.en, da.zh, da.tts, true)
	var flee_r := 8.2 if kind == "fennec" else (4.2 if kind == "scarab" else 5.0)
	if dist < flee_r and da.state == "idle" and kind != "camel":
		da.state = "flee"
		da.timer = 4.2 if kind == "fennec" else 2.8
		var away := Vector3(pos.x - ppos.x, 0.0, pos.z - ppos.z)
		da.dir = away.normalized() if away.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
		if flee_sfx_cooldown <= 0.0:
			flee_sfx_cooldown = 1.4
			game.play_sfx("animal_flee", -13)
	if da.state == "flee":
		da.timer -= delta
		if da.timer <= 0.0 and dist > 13.0:
			da.state = "idle"
			da.wander_cd = rng.randf_range(1.2, 3.0)
	var spd := 1.4
	if da.state == "flee":
		spd = 8.4 if kind == "fennec" else (4.8 if kind == "camel" else 4.2)
	else:
		spd = 1.75 if kind == "fennec" else (1.05 if kind == "camel" else 1.25)
	if da.state == "idle":
		da.wander_cd -= delta
		if da.wander_cd <= 0.0:
			da.wander_cd = rng.randf_range(1.8, 4.4)
			var to_h: Vector3 = da.home - pos
			to_h.y = 0.0
			da.dir = to_h.normalized() if to_h.length() > 7.5 else Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
	else:
		var away2 := Vector3(pos.x - ppos.x, 0.0, pos.z - ppos.z)
		if away2.length() > 0.2:
			da.dir = da.dir.lerp(away2.normalized(), minf(delta * 4.0, 1.0)).normalized()
	var nxt: Vector3 = pos + da.dir * spd * delta
	nxt.x = clampf(nxt.x, float(AhsarahLayout.FENCE_MIN_X) + 3.0, float(AhsarahLayout.FENCE_MAX_X) - 3.0)
	nxt.z = clampf(nxt.z, float(AhsarahLayout.FENCE_MIN_Z) + 4.0, float(AhsarahLayout.FENCE_MAX_Z) - 3.0)
	# Keep desert animals cleanly outside the recessed oasis water pool (-16, 12)
	var pool_v := Vector2(nxt.x - AhsarahLayout.OASIS_POOL.x, nxt.z - AhsarahLayout.OASIS_POOL.z)
	if pool_v.length() < 8.4:
		var push_d := pool_v.normalized() if pool_v.length() > 0.1 else Vector2(1.0, 0.0)
		nxt.x = AhsarahLayout.OASIS_POOL.x + push_d.x * 8.6
		nxt.z = AhsarahLayout.OASIS_POOL.z + push_d.y * 8.6
		da.dir = Vector3(push_d.x, 0.0, push_d.y)
	nxt.y = float(AhsarahLayout.fast_height(nxt.x, nxt.z))
	var ahead_y := float(AhsarahLayout.fast_height(nxt.x + da.dir.x * 0.5, nxt.z + da.dir.z * 0.5))
	var slope_pitch := clampf(atan2(ahead_y - nxt.y, 0.5), -0.35, 0.35)
	da.pos = nxt
	da.root.position = nxt
	da.root.rotation.y = atan2(-da.dir.x, -da.dir.z)
	da.visual.position = Vector3.ZERO
	da.visual.rotation = Vector3(slope_pitch, 0.0, 0.0)
	if da.state == "flee":
		_play_critter_anim(da.anim, ["Run", "Walk"], 1.75)
	else:
		_play_critter_anim(da.anim, ["Walk", "Idle"], 1.10)

func _down_desert_falcon(df: Dictionary):
	if str(df.get("state", "fly")) in ["downed", "hidden"]:
		return
	df.state = "downed"
	df.timer = 1.35
	df.area.collision_layer = 0
	df.label.visible = true
	_record_desert_species_discovery("falcon", "Desert Falcon", "荒漠猎隼", "desert falcon", false)
	game.speak_english("desert falcon")
	game.show_hitmarker(true)
	game.play_sfx("animal_hit", -8)
	game.play_sfx("bird_flap", -10)
	_spawn_vanish_motes((df.node as Node3D).global_position)
	game._notice("✦ 精准击中高空【荒漠猎隼 · Desert Falcon】！金羽化光消散…", Color("ffd984"))
	if is_instance_valid(game.achievements) and game.rules.combat_mode:
		game.achievements.record_wildlife_kill("bird")

func _down_desert_animal(da: Dictionary):
	if da.state in ["downed", "hidden"]:
		return
	da.state = "downed"
	da.timer = 1.65
	da.area.collision_layer = 0
	da.label.text = da.base_label
	da.label.modulate = Color("ffd984")
	da.label.visible = true
	_record_desert_species_discovery(str(da.kind), str(da.en), str(da.zh), str(da.tts), false)
	game.speak_english(str(da.tts))
	game.show_hitmarker(false)
	game.play_sfx("animal_hit", -10)
	_spawn_vanish_motes(da.pos + Vector3(0, 0.32, 0))
	game._notice("✦ 击中荒漠生灵【%s · %s】！正化作沙海微光消失…" % [da.en, da.zh], Color("ffd984"))

func shockwave_knockdown_near(origin: Vector3, radius: float):
	if not map_enabled:
		return
	if active_map_id == "ahsarah":
		for da in desert_animals:
			if da.state in ["downed", "hidden"]:
				continue
			if da.pos.distance_to(origin) <= radius:
				da.state = "flee"
				da.timer = 4.0
				da.dir = Vector3(da.pos.x - origin.x, 0.0, da.pos.z - origin.z).normalized()
		return
	## v0.8.6 Skyfall Overlord landing shockwave startles & bowls over nearby ground wildlife!
	for a in animals:
		if a.state in ["downed", "hidden"]:
			continue
		if a.pos.distance_to(origin) <= radius:
			_start_flee(a, origin, false)
			a.visual.rotation.z = 0.35

func on_gunshot_near(origin: Vector3, suppressed: bool):
	if not map_enabled:
		return
	var alert_r := 7.0 if suppressed else 19.0
	if active_map_id == "ahsarah":
		for da in desert_animals:
			if da.state == "idle" and da.pos.distance_to(origin) <= alert_r:
				da.state = "flee"
				da.timer = 3.8
				var away := Vector3(da.pos.x - origin.x, 0.0, da.pos.z - origin.z)
				da.dir = away.normalized() if away.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
		return
	for a in animals:
		if a.state in ["idle", "ambush"] and a.pos.distance_to(origin) <= alert_r:
			_start_flee(a, origin)

func hit_bullet(collider) -> bool:
	if not map_enabled or not (collider is Object):
		return false
	if active_map_id == "ahsarah":
		if collider.has_meta("desert_falcon_index"):
			var f_idx := int(collider.get_meta("desert_falcon_index"))
			if f_idx >= 0 and f_idx < desert_falcons.size():
				_down_desert_falcon(desert_falcons[f_idx])
				return true
		if collider.has_meta("desert_critter_index"):
			var d_idx := int(collider.get_meta("desert_critter_index"))
			if d_idx >= 0 and d_idx < desert_animals.size():
				_down_desert_animal(desert_animals[d_idx])
				return true
		return false
	if collider.has_meta("sky_egret_index"):
		var s_idx := int(collider.get_meta("sky_egret_index"))
		if s_idx < 0 or s_idx >= sky_egrets.size():
			return false
		_down_sky_egret(sky_egrets[s_idx])
		return true
	if not collider.has_meta("critter_index"):
		return false
	var idx := int(collider.get_meta("critter_index"))
	if idx < 0 or idx >= animals.size():
		return false
	_down_animal(animals[idx])
	return true

func _down_sky_egret(eg: Dictionary):
	if str(eg.get("state", "fly")) in ["downed", "hidden"]:
		return
	eg.state = "downed"
	eg.timer = 1.35
	eg.area.collision_layer = 0
	eg.label.visible = true
	discovered_species["bird"] = true
	game.speak_english("white bird")
	game.show_hitmarker(true)
	game.play_sfx("animal_hit", -8)
	game.play_sfx("bird_flap", -10)
	var hit_at: Vector3 = (eg.node as Node3D).global_position
	for i in 7:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.28
		m.mesh = sm
		m.position = hit_at + Vector3(cos(i * TAU / 7.0) * 0.45, 0.15, sin(i * TAU / 7.0) * 0.45)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("fffdf0")
		mat.emission_enabled = true
		mat.emission = Color("ffe699")
		mat.emission_energy_multiplier = 1.6
		m.material_override = mat
		add_child(m)
		hit_fx.append({"node": m, "vel": Vector3(cos(i * 1.1) * 1.6, 1.3 + float(i % 3) * 0.4, sin(i * 1.1) * 1.6), "left": 1.15})
	game._notice("✦ 精准击中高空【白鹭 · White Egret】！漫天白羽化光消散…", Color("ffe8a3"))
	if is_instance_valid(game.achievements) and game.rules.combat_mode:
		game.achievements.record_wildlife_kill("bird")

func melee_strike(camera: Camera3D) -> bool:
	if not map_enabled:
		return false
	var cam_pos := camera.global_position
	var cam_fwd := (-camera.global_transform.basis.z).normalized()
	if active_map_id == "ahsarah":
		var best_d = null
		var best_dd := 3.6
		for da in desert_animals:
			if da.state in ["downed", "hidden"]:
				continue
			var center_d: Vector3 = da.pos + Vector3(0, 0.45 if da.kind == "camel" else 0.24, 0)
			var delta_d := center_d - cam_pos
			var dd := delta_d.length()
			if dd <= best_dd and cam_fwd.dot(delta_d.normalized()) >= 0.45:
				best_dd = dd
				best_d = da
		if best_d == null:
			return false
		game.play_sfx("knife_hit", -10)
		_down_desert_animal(best_d)
		return true
	var best = null
	var best_dist := 3.4
	for a in animals:
		if not (a.state in ["idle", "ambush", "flee", "charge", "climb_approach", "climb_up", "perched_tree", "fly"]):
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
	if a.state in ["downed", "hidden"]:
		return
	a.state = "downed"
	a.timer = 1.85
	a.area.collision_layer = 0
	a.label.text = a.base_label
	a.label.modulate = Color("ffe09e")
	a.label.visible = true
	discovered_species[a.kind] = true
	game.show_hitmarker(false)
	game.play_sfx("animal_hit", -10)
	_spawn_vanish_motes(a.pos + Vector3(0, 0.28, 0))
	game._notice("✦ 击中【%s · %s】！正化作林间微光消失…" % [a.en, a.zh], Color("ffe09e"))
	if is_instance_valid(game.achievements) and game.rules.combat_mode:
		game.achievements.record_wildlife_kill(str(a.kind))

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
	var heal_amt := int(node.get_meta("heal", 7))
	if is_instance_valid(game.combat) and game.combat.in_field():
		game.combat.heal(heal_amt, 6)
	game.play_sfx("flora_collect", -10)
	var lbl: Label3D = node.get_meta("label_node")
	lbl.text = "✓ %s · %s" % [en, zh]
	lbl.modulate = Color("89f0ad")
	lbl.visible = true
	node.set_meta("tag_left", 2.4)
	node.set_meta("tag_shown_once", true)
	var ring: MeshInstance3D = node.get_meta("ring_node")
	ring.visible = false
	game._notice("🌿 辨识奇植【%s · %s】(+5分 +%d生命 +6护盾) · %s" % [en, zh, heal_amt, sentence], Color("8ff5b5"))
	return true

func eco_discoveries_total() -> int:
	return discovered_species.size() + collected_flora.size()

func status_badge() -> String:
	if active_map_id == "ahsarah":
		return "荒漠生灵 %d/%d · 零号大坝 × 巴克什" % [
			mini(TOTAL_DESERT_SPECIES, discovered_desert_species.size()), TOTAL_DESERT_SPECIES
		]
	return "生灵 %d/%d · 奇植 %d/%d" % [
		mini(TOTAL_SPECIES, discovered_species.size()), TOTAL_SPECIES,
		mini(FLORA_SPOTS.size(), collected_flora.size()), FLORA_SPOTS.size()
	]
