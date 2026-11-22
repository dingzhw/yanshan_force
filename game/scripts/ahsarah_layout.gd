extends RefCounted
## Yanshan Force v0.9.0 — "阿萨拉堡垒" (Ahsarah Fortress) Desert Canyon & Zero Dam Tactical Map (160m x 200m)
## Fuses Delta Force's iconic Zero Dam (colossal north concrete dam + west cement silos + east substation)
## with Brakkesh's sunlit North African sandstone kasbah arches & south palm oasis!
## Mirrors Layout's API surface 1:1 so combat, minimap, player, exploration & world_loot switch maps cleanly.

const MAP_ID = "ahsarah"
const MAP_TITLE = "阿萨拉堡垒"

const MIN_X = -90.0
const MAX_X = 90.0
const MIN_Z = -180.0
const MAX_Z = 40.0
const GRID_WIDTH := 181   # -90..+90 inclusive
const GRID_DEPTH := 221   # -180..+40 inclusive

const FENCE_MIN_X = -75.0
const FENCE_MAX_X = 75.0
const FENCE_MIN_Z = -148.0
const FENCE_MAX_Z = 25.0

# Compatibility stubs for stream APIs (Ahsarah is arid desert with a small south oasis pool, no creek)
const STREAM_Z_MIN = 9999.0
const STREAM_Z_MAX = -9999.0
const STREAM_BRIDGES = []
const STREAM_POINTS = []

const SPAWN = Vector3(0.0, 0.0, 14.0)
const OASIS_POOL = Vector3(-16.0, 0.0, 12.0)

const CEMENT_PLANT = Vector3(-46.0, 0.0, -48.0)
const BAZAAR_ARCH = Vector3(38.0, 0.0, -36.0)
const SUBSTATION = Vector3(46.0, 0.0, -88.0)
const WEST_BARRACKS = Vector3(-44.0, 0.0, -108.0)
const ADMIN_FORTRESS = Vector3(0.0, 0.0, -124.0)
const FORTRESS_GATE = Vector3(0.0, 0.0, -102.0)
const ZERO_DAM_CENTER = Vector3(0.0, 0.0, -158.0)
const RADAR_TOWER_WEST = Vector3(-34.0, 0.0, -148.0)
const RADAR_TOWER_EAST = Vector3(34.0, 0.0, -148.0)
const EXIT = Vector3(52.0, 0.0, -138.0)

# Arena alias matching Layout's boss arena constants
const CLOUD_ARENA_CENTER = ADMIN_FORTRESS
const CLOUD_ARENA_RADIUS = 18.0
const CLOUD_ARENA_Y = 5.40

const STATIONS = [
	{"id": "oasis", "title": "A · 绿洲前哨", "at": SPAWN},
	{"id": "wadi", "title": "中部荒漠哨卡", "at": Vector3(-4.0, 0.0, -56.0)},
	{"id": "fortress", "title": "B · 阿萨拉行政堡垒", "at": Vector3(0.0, 0.0, -114.0)}
]

# 5 carefully spaced Ahsarah combat zones (z_idx == 2 is the flagship Administrative Fortress Boss zone!)
const COMBAT_ZONES = [
	{"id": "cement", "title": "阿萨拉卫队 · 西侧水泥厂", "at": CEMENT_PLANT, "waves": 3, "squad": 5, "aggro": 15.8, "pursuit": 86.0, "boss": false, "faction": "ahsarah"},
	{"id": "bazaar", "title": "阿萨拉卫队 · 巴克什集市", "at": BAZAAR_ARCH, "waves": 3, "squad": 5, "aggro": 15.6, "pursuit": 86.0, "boss": false, "faction": "ahsarah"},
	{"id": "admin_fortress", "title": "阿萨拉行政堡垒 · 核心中枢", "at": ADMIN_FORTRESS, "waves": 3, "squad": 5, "aggro": 17.5, "pursuit": 94.0, "boss": true, "faction": "ahsarah"},
	{"id": "substation", "title": "哈夫克集团 · 东区变电站", "at": SUBSTATION, "waves": 3, "squad": 5, "aggro": 16.0, "pursuit": 88.0, "boss": false, "faction": "haavk"},
	{"id": "west_bastion", "title": "阿萨拉卫队 · 大坝西翼哨所", "at": WEST_BARRACKS, "waves": 3, "squad": 5, "aggro": 15.8, "pursuit": 86.0, "boss": false, "faction": "ahsarah"}
]

# Exploration & lore node anchors (6 Ahsarah story terminals)
const INTEL_OASIS = Vector3(8.5, 0.0, 9.5)
const INTEL_CEMENT = Vector3(-34.5, 0.0, -40.0)
const INTEL_BAZAAR = Vector3(31.5, 0.0, -26.5)
const INTEL_SUBSTATION = Vector3(37.5, 0.0, -82.0)
const INTEL_FORTRESS = Vector3(-13.0, 0.0, -112.0)
const INTEL_DAM_VIEW = Vector3(22.0, 0.0, -138.0)

# Compatibility landmark stubs so shared scripts never error if accessed
const POEM = INTEL_CEMENT
const MATH = INTEL_BAZAAR
const MATH_GATE_CENTER = Vector3(999.0, 0.0, 999.0)
const CLUE = INTEL_OASIS
const CLUE_LOOT = INTEL_SUBSTATION
const WANGDAO_PAVILION = EXIT
const EAST_OVERLOOK = BAZAAR_ARCH
const YANXIA_CAVE_CENTER = Vector3(999.0, 0.0, 999.0)
const YANXIA_CAVE_MOUTH = Vector3(999.0, 0.0, 999.0)
const YANXIA_CAVE_SANCTUM = Vector3(999.0, 0.0, 999.0)
const CAVE_DX = 0.0
const CAVE_DZ = 0.0
const CAVE_FLOOR_Y = 0.0

const ROUTE = [
	SPAWN,
	Vector3(0.0, 0.0, -14.0),
	Vector3(-4.0, 0.0, -56.0),
	Vector3(0.0, 0.0, -86.0),
	FORTRESS_GATE,
	ADMIN_FORTRESS,
	Vector3(24.0, 0.0, -132.0),
	EXIT
]

const BRANCHES = [
	# West Cement Plant tactical loop (Zero Dam west corridor)
	[Vector3(0.0, 0.0, -14.0), Vector3(-24.0, 0.0, -26.0), CEMENT_PLANT, Vector3(-46.0, 0.0, -78.0), WEST_BARRACKS, Vector3(-22.0, 0.0, -122.0), ADMIN_FORTRESS],
	# East Brakkesh Bazaar -> Haavk Substation -> Helipad extraction road
	[Vector3(0.0, 0.0, -14.0), Vector3(22.0, 0.0, -22.0), BAZAAR_ARCH, Vector3(44.0, 0.0, -62.0), SUBSTATION, Vector3(48.0, 0.0, -114.0), EXIT],
	# Mid-canyon cross link between Cement Plant and Bazaar
	[CEMENT_PLANT, Vector3(-4.0, 0.0, -56.0), BAZAAR_ARCH],
	# South Oasis trail (sweeps cleanly south-west around the recessed oasis spring pool!)
	[SPAWN, Vector3(-6.0, 0.0, 20.0), Vector3(-28.0, 0.0, 14.0), Vector3(-28.0, 0.0, -8.0), Vector3(-24.0, 0.0, -26.0)]
]

# Explicit flat architectural grading pads [pos, inner_flat_radius, outer_blend_radius]
# Ensures EVERY pavilion, silo, substation bay, barracks, radar tower & camp outpost sits dead-level with zero floating edges!
const BUILDING_PADS = [
	[Vector3(44.0, 0.0, -28.0), 8.2, 14.5],    # Brakkesh main arched bazaar pavilion
	[Vector3(36.0, 0.0, -46.0), 8.0, 14.0],    # Brakkesh south bazaar pavilion
	[Vector3(-52.0, 0.0, -104.0), 8.2, 14.5],  # West barracks pavilion
	[Vector3(-54.0, 0.0, -44.0), 9.5, 16.0],   # Cement plant silo #1
	[Vector3(-52.0, 0.0, -64.0), 9.0, 15.5],   # Cement plant silo #2
	[Vector3(52.0, 0.0, -84.0), 7.2, 13.0],    # Haavk substation bay #1
	[Vector3(52.0, 0.0, -96.0), 7.2, 13.0],    # Haavk substation bay #2
	[RADAR_TOWER_WEST, 7.5, 13.5],             # West Babel radar tower
	[RADAR_TOWER_EAST, 7.5, 13.5],             # East Babel radar tower
]

const LAND_ANCHORS = [
	SPAWN, CEMENT_PLANT, BAZAAR_ARCH, SUBSTATION, WEST_BARRACKS,
	FORTRESS_GATE, EXIT, RADAR_TOWER_WEST, RADAR_TOWER_EAST,
	INTEL_OASIS, INTEL_CEMENT, INTEL_BAZAAR, INTEL_SUBSTATION, INTEL_FORTRESS, INTEL_DAM_VIEW
]

const ROAD_BLEND_RADIUS := 7.5
const ROAD_CELL_SIZE := 10.0

class RoadSegment:
	var start: Vector2
	var direction: Vector2
	var length_squared: float
	var start_height: float
	var end_height: float

static var road_segments: Array[RoadSegment] = []
static var road_cells: Dictionary = {}
static var grid_height_cache = {}
static var fast_height_grid: PackedFloat32Array = PackedFloat32Array()

static func base_height(x: float, z: float) -> float:
	# Smooth flat oasis basin terrace around south spawn & oasis pool (z >= -2..28, x in -32..24)
	var north_climb := smoothstep(-2.0, 136.0, -z) * 5.2
	# Canyon rim shoulders rising smoothly near east/west map margins (and continuing naturally into outer dunes!)
	var canyon_walls := smoothstep(54.0, 88.0, absf(x)) * 8.2
	# Elevated NE Helipad Extraction Overlook shelf (7.0m)
	var heli_pad := 2.0 * exp(-pow((x - EXIT.x) / 17.0, 2.0) - pow((z - EXIT.z) / 16.0, 2.0))
	# Natural desert dune undulations in mid-canyon (zero amplitude in south oasis flat zone!)
	var oasis_flat := 1.0 - smoothstep(14.0, 32.0, Vector2((x + 6.0) / 1.15, z - 12.0).length())
	var dunes := (sin(x * 0.075 + z * 0.042) * 1.15 + cos(z * 0.088 - x * 0.032) * 0.65) * smoothstep(-2.0, 22.0, -z)
	var h := north_climb + canyon_walls + heli_pad + dunes
	return lerpf(h, 0.0, oasis_flat)

static func anchor_height(at: Vector3) -> float:
	if at == ADMIN_FORTRESS or at == FORTRESS_GATE:
		return CLOUD_ARENA_Y
	if at == EXIT:
		return 7.0
	if at == SPAWN:
		return 0.0
	return base_height(at.x, at.z)

static func _prepare_road_segments():
	if not road_segments.is_empty():
		return
	for path in [ROUTE] + BRANCHES:
		for i in path.size() - 1:
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			var segment := RoadSegment.new()
			segment.start = Vector2(a.x, a.z)
			segment.direction = Vector2(b.x, b.z) - segment.start
			segment.length_squared = segment.direction.length_squared()
			if segment.length_squared == 0.0:
				continue
			segment.start_height = anchor_height(a)
			segment.end_height = anchor_height(b)
			road_segments.append(segment)
			var x0 := floori((minf(a.x, b.x) - ROAD_BLEND_RADIUS) / ROAD_CELL_SIZE)
			var x1 := floori((maxf(a.x, b.x) + ROAD_BLEND_RADIUS) / ROAD_CELL_SIZE)
			var z0 := floori((minf(a.z, b.z) - ROAD_BLEND_RADIUS) / ROAD_CELL_SIZE)
			var z1 := floori((maxf(a.z, b.z) + ROAD_BLEND_RADIUS) / ROAD_CELL_SIZE)
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var cell := Vector2i(ix, iz)
					if not road_cells.has(cell):
						road_cells[cell] = []
					road_cells[cell].append(segment)

static func height(x: float, z: float) -> float:
	var key := Vector2(x, z)
	var integer_point := x == floorf(x) and z == floorf(z)
	if integer_point and grid_height_cache.has(key):
		return grid_height_cache[key]
	_prepare_road_segments()
	var result := base_height(x, z)
	for at in LAND_ANCHORS:
		var d := Vector2(x - at.x, z - at.z).length()
		if d < 12.0:
			result = lerpf(result, anchor_height(at), 1.0 - smoothstep(5.2, 12.0, d))
	var nearest := ROAD_BLEND_RADIUS
	var bed := result
	var cell := Vector2i(floori(x / ROAD_CELL_SIZE), floori(z / ROAD_CELL_SIZE))
	for segment: RoadSegment in road_cells.get(cell, []):
		var t := clampf((key - segment.start).dot(segment.direction) / segment.length_squared, 0.0, 1.0)
		var dist := key.distance_to(segment.start + segment.direction * t)
		if dist < nearest:
			nearest = dist
			bed = lerpf(segment.start_height, segment.end_height, t)
	var road_t := 1.0 - smoothstep(2.8, ROAD_BLEND_RADIUS, nearest)
	result = lerpf(result, bed, road_t)
	# Level architectural grading pads for every pavilion, silo, substation & radar tower
	for bp in BUILDING_PADS:
		var bpos: Vector3 = bp[0]
		var r_in: float = float(bp[1])
		var r_out: float = float(bp[2])
		var bd := Vector2(x - bpos.x, z - bpos.z).length()
		if bd < r_out:
			var bw := 1.0 - smoothstep(r_in, r_out, bd)
			result = lerpf(result, base_height(bpos.x, bpos.z), bw)
	# Flat Administrative Fortress Courtyard & Gatehouse Terrace (radius 24m at y=5.40m)
	var fort_d := Vector2(x - ADMIN_FORTRESS.x, z - ADMIN_FORTRESS.z).length()
	if fort_d < 30.0:
		var fw := 1.0 - smoothstep(21.5, 30.0, fort_d)
		result = lerpf(result, CLOUD_ARENA_Y, fw)
	var gate_d := Vector2(x - FORTRESS_GATE.x, z - FORTRESS_GATE.z).length()
	if gate_d < 17.0:
		var gw := 1.0 - smoothstep(11.0, 17.0, gate_d)
		result = lerpf(result, CLOUD_ARENA_Y, gw)
	# Flat Helipad Extraction Plateau (y=7.0m)
	var ex_d := Vector2(x - EXIT.x, z - EXIT.z).length()
	if ex_d < 14.5:
		var ew := 1.0 - smoothstep(8.8, 14.5, ex_d)
		result = lerpf(result, 7.0, ew)
	# TRUE deeply recessed concave South Oasis Spring Pool basin at (-16, 12):
	# Rim stays flat at y=0.0m, concave bank drops cleanly down to y=-1.10m so the water sheet at y=-0.34m
	# intersects INTO the sloping sand shore 360° around with ZERO floating edge!
	var pool_d := Vector2((x - OASIS_POOL.x) / 7.2, (z - OASIS_POOL.z) / 5.2).length()
	if pool_d < 1.38:
		var pw := 1.0 - smoothstep(0.62, 1.38, pool_d)
		result = lerpf(result, -1.10, pw)
	if integer_point:
		grid_height_cache[key] = result
	return result

static func _ensure_fast_grid():
	if not fast_height_grid.is_empty():
		return
	fast_height_grid.resize(GRID_WIDTH * GRID_DEPTH)
	var idx := 0
	for zi in range(int(MIN_Z), int(MAX_Z) + 1):
		var zf := float(zi)
		for xi in range(int(MIN_X), int(MAX_X) + 1):
			fast_height_grid[idx] = height(float(xi), zf)
			idx += 1

static func fast_height(x: float, z: float) -> float:
	_ensure_fast_grid()
	var fx := clampf(x - MIN_X, 0.0, float(GRID_WIDTH - 1) - 0.001)
	var fz := clampf(z - MIN_Z, 0.0, float(GRID_DEPTH - 1) - 0.001)
	var ix := int(floorf(fx))
	var iz := int(floorf(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var row0 := iz * GRID_WIDTH + ix
	var row1 := row0 + GRID_WIDTH
	var h0 := lerpf(fast_height_grid[row0], fast_height_grid[row0 + 1], tx)
	var h1 := lerpf(fast_height_grid[row1], fast_height_grid[row1 + 1], tx)
	return lerpf(h0, h1, tz)

static func on_ground(at: Vector3) -> Vector3:
	return Vector3(at.x, height(at.x, at.z), at.z)

static func min_ground_height(x: float, z: float, radius: float) -> float:
	var low := height(x, z)
	for d in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		low = minf(low, height(x + d.x, z + d.y))
	return low

static func stream_center_x(_z: float) -> float:
	return 9999.0

static func stream_distance(_x: float, _z: float) -> float:
	return INF

static func stream_water_y(_z: float) -> float:
	return -99.0

static func road_distance(x: float, z: float, limit := INF) -> float:
	_prepare_road_segments()
	var point := Vector2(x, z)
	var segments: Array = road_segments
	if limit <= ROAD_BLEND_RADIUS:
		segments = road_cells.get(Vector2i(floori(x / ROAD_CELL_SIZE), floori(z / ROAD_CELL_SIZE)), [])
	var result: float = limit
	for segment: RoadSegment in segments:
		var fraction := clampf((point - segment.start).dot(segment.direction) / segment.length_squared, 0.0, 1.0)
		result = minf(result, point.distance_to(segment.start + segment.direction * fraction))
	return result

static func is_in_bamboo_cave_zone(_x: float, _z: float, _padding: float = 0.0) -> bool:
	return false

static func is_in_cloud_arena(x: float, z: float, padding: float = 0.0) -> bool:
	return Vector2(x - ADMIN_FORTRESS.x, z - ADMIN_FORTRESS.z).length() < (CLOUD_ARENA_RADIUS + 2.5 + padding)

static func clear_for_route(x: float, z: float, padding = 0.0) -> bool:
	var pad := float(padding)
	if is_in_cloud_arena(x, z, pad):
		return true
	if road_distance(x, z, 4.8 + pad) < 4.8 + pad:
		return true
	if Vector2(x - OASIS_POOL.x, z - OASIS_POOL.z).length() < 9.5 + pad:
		return true
	if Vector2(x - EXIT.x, z - EXIT.z).length() < 10.5 + pad:
		return true
	for camp in COMBAT_ZONES:
		var ca: Vector3 = camp.at
		if Vector2(x - ca.x, z - ca.z).length() < 12.0 + pad:
			return true
	for at in LAND_ANCHORS:
		if Vector2(x - at.x, z - at.z).length() < 7.0 + pad:
			return true
	return false
