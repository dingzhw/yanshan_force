extends RefCounted
## Yanshan Force v0.8.5 — "大烟山" 3x Playable Area Expansion (180m x 240m = 43,200 m²)
## 6 Fogveil camps spaced 62-176m apart, isolated West Bamboo Ravine for Yanxia Cave (>=64m from all camps),
## 5 creek bridges (including central Triple-Arch Bluestone Bridge), and North Cloud-Top 38m Martial Arena!

const MIN_X = -100.0
const MAX_X = 100.0
const MIN_Z = -210.0
const MAX_Z = 50.0
const GRID_WIDTH := 201   # -100..+100 inclusive
const GRID_DEPTH := 261   # -210..+50 inclusive

const FENCE_MIN_X = -90.0
const FENCE_MAX_X = 90.0
const FENCE_MIN_Z = -200.0
const FENCE_MAX_Z = 40.0

const STREAM_Z_MIN = -196.0
const STREAM_Z_MAX = 50.0
const STREAM_BRIDGES = [16.0, -28.0, -74.0, -124.0, -164.0]
const MULTI_ARCH_BRIDGE_Z = -28.0
const STONE_ARCH_BRIDGE_Z = -164.0
const STREAM_POINTS = [
	[-206.0, 32.0],
	[-180.0, 34.5],
	[-164.0, 34.0],
	[-145.0, 31.0],
	[-124.0, 29.5],
	[-98.0, 28.0],
	[-74.0, 27.5],
	[-50.0, 25.5],
	[-28.0, 25.0],
	[-6.0, 24.0],
	[16.0, 25.0],
	[32.0, 25.5],
	[40.0, 26.0],
	[50.0, 27.2]
]

const SPAWN = Vector3(0.0, 0.0, 14.0)
const STATIONS = [
	{"id": "camp", "title": "A · 山脚营地", "at": SPAWN},
	{"id": "forest", "title": "林间前哨", "at": Vector3(-16.0, 0.0, -60.0)},
	{"id": "rocks", "title": "B · 云顶竹林演武坛", "at": Vector3(16.0, 0.0, -158.0)}
]

const CLOUD_ARENA_CENTER = Vector3(8.0, 0.0, -180.0)
const CLOUD_ARENA_RADIUS = 19.0   # 38m diameter open bluestone plaza
const CLOUD_ARENA_Y = 12.20

const PASS_OUTPOST = Vector3(8.0, 0.0, -118.0)
const WEST_CAMP = Vector3(-62.0, 0.0, -16.0)
const EAST_CAMP = Vector3(64.0, 0.0, -68.0)
const NW_CAMP = Vector3(-54.0, 0.0, -162.0)

const COMBAT_ZONES = [
	{"id": "forest", "title": "雾隐帮·林间古道营", "at": Vector3(-16.0, 0.0, -60.0), "waves": 3, "squad": 5, "aggro": 15.8, "pursuit": 88.0, "boss": false},
	{"id": "pass", "title": "雾隐帮·山道拦截营", "at": PASS_OUTPOST, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 88.0, "boss": false},
	{"id": "bamboo", "title": "雾隐帮·B区云顶竹林总坛", "at": CLOUD_ARENA_CENTER, "waves": 3, "squad": 5, "aggro": 16.5, "pursuit": 94.0, "boss": true},
	{"id": "west_ridge", "title": "雾隐帮·西岭山坡营", "at": WEST_CAMP, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 88.0, "boss": false},
	{"id": "east_ridge", "title": "雾隐帮·东坡茶岭营", "at": EAST_CAMP, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 88.0, "boss": false},
	{"id": "nw_plateau", "title": "雾隐帮·西北高地营", "at": NW_CAMP, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 88.0, "boss": false}
]

const EXIT = Vector3(46.0, 0.0, -148.0)
const ROUTE = [
	SPAWN,
	Vector3(-8.0, 0.0, -14.0),
	Vector3(-24.0, 0.0, -34.0),
	Vector3(-16.0, 0.0, -60.0),
	Vector3(-8.0, 0.0, -88.0),
	PASS_OUTPOST,
	Vector3(16.0, 0.0, -158.0),
	Vector3(24.0, 0.0, -164.0),
	Vector3(44.0, 0.0, -164.0),
	EXIT
]

const POEM = Vector3(-42.0, 0.0, -46.0)
const MATH = Vector3(4.0, 0.0, -96.0)
const MATH_GATE_CENTER = Vector3(14.5, 0.0, -104.0)
const CLUE = Vector3(6.5, 0.0, -16.0)
const CLUE_LOOT = Vector3(14.5, 0.0, -24.0)
const PARKOUR_CONTAINERS = Vector3(-34.0, 0.0, -10.0)
const CLEFT_CACHE = Vector3(-44.0, 0.0, -86.0)
const CAVE_GROTTO = Vector3(-36.0, 0.0, -124.0)
const EAST_OVERLOOK = Vector3(48.0, 0.0, -28.0)     # Hosts v0.8.5 Tea-Hill Rest Pavilion
const WANGDAO_PAVILION = Vector3(56.0, 0.0, 26.0)   # SE elevated overlook plateau
const CAMPHOR_SHRINE = Vector3(16.5, 0.0, -15.5)
const SE_BAMBOO_CACHE = Vector3(64.0, 0.0, -128.0)
const RECON_RADIO = Vector3(54.0, 0.0, -96.0)
const AIRDROP_BEACON = Vector3(58.0, 0.0, -176.0)
const WATCHTOWER = Vector3(-56.0, 0.0, -184.0)
const SHELTER_BAMBOO = Vector3(24.0, 0.0, -156.0)
const CLIFF_STELE_AT = Vector3(-28.0, 0.0, -138.0)  # v0.8.5 Mountain Inscribed Stele

# Rigidly translated Bamboo-Stone Maze & Yanxia Ancient Cave in isolated West Bamboo Ravine
# Rigid delta from legacy (-41.60, -64.00) -> (-72.00, -100.00): dx = -30.40, dz = -36.00
const CAVE_DX = -30.40
const CAVE_DZ = -36.00
const CAVE_FLOOR_Y = 10.60
const BAMBOO_MAZE_GATE = Vector3(-72.0, 0.0, -72.5)
const BAMBOO_MAZE_EAST = Vector3(-65.5, 0.0, -80.0)
const BAMBOO_MAZE_SUNDIAL = Vector3(-77.2, 0.0, -83.0)
const BAMBOO_MAZE_MOYA = Vector3(-66.8, 0.0, -86.0)
const YANXIA_CAVE_MOUTH = Vector3(-72.0, 0.0, -93.5)
const YANXIA_CAVE_CENTER = Vector3(-72.0, 0.0, -100.0)
const YANXIA_CAVE_SANCTUM = Vector3(-71.25, 0.0, -102.55)

const BRANCHES = [
	# West Poem Pavilion & West Ridge Camp link
	[Vector3(-24.0, 0.0, -34.0), POEM, Vector3(-50.0, 0.0, -30.0), WEST_CAMP],
	# West Bamboo-Stone Labyrinth ("迷踪竹石阵") & Yanxia Cavern footpaths (well outside all camp aggro rings)
	[POEM, Vector3(-56.0, 0.0, -56.0), Vector3(-72.0, 0.0, -65.0), BAMBOO_MAZE_GATE],
	[Vector3(-48.0, 0.0, -66.0), Vector3(-61.0, 0.0, -80.0), BAMBOO_MAZE_EAST],
	# Math Shortcut Gate Pass -> Upper-Pass Bridge -> Extraction Helipad
	[Vector3(-8.0, 0.0, -88.0), MATH, MATH_GATE_CENTER, Vector3(20.0, 0.0, -124.0), Vector3(38.0, 0.0, -124.0), EXIT],
	# Central Triple-Arch Bluestone Bridge (z = -28.0) -> East Tea Pavilion & South Ridge to Wangdao Pavilion
	[Vector3(-8.0, 0.0, -14.0), CLUE, CLUE_LOOT, Vector3(16.0, 0.0, -28.0), Vector3(34.0, 0.0, -28.0), EAST_OVERLOOK, Vector3(50.0, 0.0, -4.0), Vector3(51.0, 0.0, 14.0), WANGDAO_PAVILION],
	# South Camp Wooden Bridge (z = 16.0) -> Gentle East Hillside Trail to Wangdao Pavilion & North Link
	[SPAWN, Vector3(17.5, 0.0, 16.0), Vector3(33.0, 0.0, 16.0), Vector3(44.5, 0.0, 20.5), WANGDAO_PAVILION],
	[Vector3(33.0, 0.0, 16.0), Vector3(44.0, 0.0, 2.0), Vector3(50.0, 0.0, -4.0)],
	# Mid-Creek Wooden Bridge (z = -74.0) -> East Tea-Hill Camp & Recon Radio
	[Vector3(-16.0, 0.0, -60.0), Vector3(8.0, 0.0, -70.0), Vector3(19.5, 0.0, -74.0), Vector3(36.0, 0.0, -74.0), EAST_CAMP],
	[EAST_OVERLOOK, Vector3(56.0, 0.0, -48.0), EAST_CAMP, RECON_RADIO, SE_BAMBOO_CACHE, Vector3(38.0, 0.0, -124.0)],
	# North Cloud-Pass Stone Bridge (z = -164.0) -> North Airdrop Beacon & Cloud-Top Martial Arena South Avenue
	[Vector3(44.0, 0.0, -164.0), AIRDROP_BEACON],
	[Vector3(16.0, 0.0, -158.0), Vector3(8.0, 0.0, -161.0), CLOUD_ARENA_CENTER],
	# West Pass -> Cliff Stele -> NW Highland Camp -> Watchtower
	[PASS_OUTPOST, Vector3(-16.0, 0.0, -128.0), CLIFF_STELE_AT, NW_CAMP, WATCHTOWER]
]

static var grid_height_cache = {}
static var stream_water_heights: Array = []
static var fast_height_grid: PackedFloat32Array = PackedFloat32Array()

static func base_height(x: float, z: float) -> float:
	if z > 4.0 and z <= 42.0 and absf(x) < 20.0:
		return 0.0
	if z > 42.0 and absf(x) < 20.0:
		return -smoothstep(42.0, 50.0, z) * 0.85
	var climb := smoothstep(-4.0, 192.0, -z) * 11.5
	var shoulders := smoothstep(18.0, 74.0, absf(x)) * 5.2
	# Gently elevated SE scenic knoll beneath Wangdao Pavilion for sweeping golden rice-terrace vistas
	var wd_knoll := 2.65 * exp(-pow((x - WANGDAO_PAVILION.x) / 21.0, 2.0) - pow((z - WANGDAO_PAVILION.z) / 19.0, 2.0)) * smoothstep(32.0, 44.0, x)
	var undul := (sin(x * 0.085 + z * 0.036) * 1.65 + sin(z * 0.092) * 0.80) * smoothstep(4.0, 32.0, -z)
	return climb + shoulders + wd_knoll + undul

static func stream_center_x(z: float) -> float:
	if z <= STREAM_POINTS[0][0]:
		return STREAM_POINTS[0][1]
	var left := 0
	var right := STREAM_POINTS.size() - 1
	if z >= STREAM_POINTS[right][0]:
		return STREAM_POINTS[right][1]
	while right - left > 1:
		var mid := (left + right) / 2
		if z <= STREAM_POINTS[mid][0]:
			right = mid
		else:
			left = mid
	var z0 := float(STREAM_POINTS[left][0])
	var z1 := float(STREAM_POINTS[right][0])
	var t := clampf((z - z0) / (z1 - z0), 0.0, 1.0)
	var blend := t * t * (3.0 - 2.0 * t)
	return lerpf(STREAM_POINTS[left][1], STREAM_POINTS[right][1], blend)

static func stream_distance(x: float, z: float) -> float:
	if z < STREAM_Z_MIN - 1.5 or z > STREAM_Z_MAX + 1.0:
		return INF
	return absf(x - stream_center_x(z))

const LAND_ANCHORS = [
	EXIT, POEM, MATH, MATH_GATE_CENTER, CLUE, CLUE_LOOT, PASS_OUTPOST, WEST_CAMP, EAST_CAMP, NW_CAMP,
	PARKOUR_CONTAINERS, CAVE_GROTTO, EAST_OVERLOOK, RECON_RADIO, SE_BAMBOO_CACHE,
	AIRDROP_BEACON, WATCHTOWER, SHELTER_BAMBOO, WANGDAO_PAVILION, CAMPHOR_SHRINE,
	CLIFF_STELE_AT, Vector3(17.0, 0.0, -25.0)
]
const ROAD_BLEND_RADIUS := 8.0
const ROAD_CELL_SIZE := 10.0

class RoadSegment:
	var start: Vector2
	var direction: Vector2
	var length_squared: float
	var start_height: float
	var end_height: float

static var road_segments: Array[RoadSegment] = []
static var road_cells: Dictionary = {}

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

static func _land_height(x: float, z: float) -> float:
	_prepare_road_segments()
	var key := Vector2(x, z)
	var result := base_height(x, z)
	for station in STATIONS:
		var at: Vector3 = station.at
		var distance := Vector2(x - at.x, z - at.z).length()
		if distance < 15.0:
			result = lerpf(result, base_height(at.x, at.z), 1.0 - smoothstep(10.0, 15.0, distance))
	for at in LAND_ANCHORS:
		var distance := Vector2(x - at.x, z - at.z).length()
		if distance < 11.5:
			result = lerpf(result, anchor_height(at), 1.0 - smoothstep(4.8, 11.5, distance))
	var nearest := ROAD_BLEND_RADIUS
	var bed := result
	var cell := Vector2i(floori(x / ROAD_CELL_SIZE), floori(z / ROAD_CELL_SIZE))
	for segment: RoadSegment in road_cells.get(cell, []):
		var t := clampf((key - segment.start).dot(segment.direction) / segment.length_squared, 0, 1)
		var distance := key.distance_to(segment.start + segment.direction * t)
		if distance < nearest:
			nearest = distance
			bed = lerpf(segment.start_height, segment.end_height, t)
	var pav_pad := 1.0 - smoothstep(5.0, 13.5, Vector2(x - WANGDAO_PAVILION.x, z - WANGDAO_PAVILION.z).length())
	result = lerpf(result, anchor_height(WANGDAO_PAVILION), pav_pad)
	var road_t := 1.0 - smoothstep(2.9, ROAD_BLEND_RADIUS, nearest)
	result = lerpf(result, bed, road_t)
	# North Summit 38m-diameter Cloud-Top Bluestone Martial Arena ("云顶青石演武坛")
	var arena_d := Vector2(x - CLOUD_ARENA_CENTER.x, z - CLOUD_ARENA_CENTER.z).length()
	if arena_d < CLOUD_ARENA_RADIUS + 8.0:
		var arena_w := 1.0 - smoothstep(CLOUD_ARENA_RADIUS - 0.5, CLOUD_ARENA_RADIUS + 8.0, arena_d)
		result = lerpf(result, CLOUD_ARENA_Y, arena_w)
	# Smoothly graded terrace for isolated West Ravine «迷踪竹石阵» (9.95m -> 10.60m) & flat 10.60m floor across «烟霞古洞»
	if x > (-51.8 + CAVE_DX) and x < (-31.6 + CAVE_DX) and z > (-74.5 + CAVE_DZ) and z < (-32.0 + CAVE_DZ):
		var maze_wx := 1.0 - smoothstep(7.0, 9.7, absf(x - (-41.7 + CAVE_DX)))
		var maze_wz := 1.0 - smoothstep(17.15, 20.8, absf(z - (-53.35 + CAVE_DZ)))
		var terrace_y := lerpf(CAVE_FLOOR_Y - 0.65, CAVE_FLOOR_Y, smoothstep(36.5 - CAVE_DZ, 55.8 - CAVE_DZ, -z))
		result = lerpf(result, terrace_y, maze_wx * maze_wz)
	for bz in STREAM_BRIDGES:
		if absf(z - float(bz)) >= 9.0:
			continue
		var bcx := stream_center_x(float(bz))
		if absf(x - bcx) < 17.5:
			var wh := base_height(bcx - 6.0, float(bz))
			var eh := base_height(bcx + 6.0, float(bz))
			var saddle := lerpf(wh, eh, 0.40)
			var wx := 1.0 - smoothstep(5.5, 17.5, absf(x - bcx))
			var wz := 1.0 - smoothstep(2.8, 9.0, absf(z - float(bz)))
			result = lerpf(result, saddle, wx * wz)
	return result

static func land_edge_height(x: float, z: float) -> float:
	return _land_height(x, z)

static func _ensure_stream_profile():
	if not stream_water_heights.is_empty():
		return
	var z_start := int(MIN_Z)
	var count := GRID_DEPTH  # -210 .. +50 inclusive
	stream_water_heights.resize(count)
	var prev := 999.0
	for i in count:
		var z := float(z_start + i)
		var cx := stream_center_x(z)
		var left_bank := _land_height(cx - 3.8, z)
		var right_bank := _land_height(cx + 3.8, z)
		var low_bank := minf(left_bank, right_bank)
		var avg_bank := (left_bank + right_bank) * 0.5
		var bank_ref := lerpf(low_bank, avg_bank, 0.35) - 0.36
		var wy := bank_ref if i == 0 else minf(prev - 0.015, bank_ref)
		stream_water_heights[i] = wy
		prev = wy

static func stream_water_y(z: float) -> float:
	_ensure_stream_profile()
	var fidx := clampf(z - MIN_Z, 0.0, float(stream_water_heights.size() - 2))
	var idx := int(floorf(fidx))
	return lerpf(float(stream_water_heights[idx]), float(stream_water_heights[idx + 1]), fidx - float(idx))

static func height(x: float, z: float) -> float:
	var key = Vector2(x, z)
	var integer_point = x == floorf(x) and z == floorf(z)
	if integer_point and grid_height_cache.has(key):
		return grid_height_cache[key]
	var result = _land_height(x, z)
	var sd := stream_distance(x, z)
	if sd < 5.2 and z >= STREAM_Z_MIN - 1.5 and z <= STREAM_Z_MAX + 0.5:
		var wy := stream_water_y(z)
		var head_fade := smoothstep(STREAM_Z_MIN - 1.5, STREAM_Z_MIN + 1.2, z)
		var min_bz := 99.0
		for bz in STREAM_BRIDGES:
			min_bz = minf(min_bz, absf(z - float(bz)))
		var bridge_clear := smoothstep(1.4, 2.8, min_bz)
		var lip_target := maxf(result, wy + 0.38)
		var lip_w := smoothstep(1.65, 2.60, sd) * (1.0 - smoothstep(3.35, 5.10, sd)) * head_fade * bridge_clear
		result = lerpf(result, lip_target, lip_w)
		if sd < 2.65:
			var bank_top := maxf(result, wy + 0.36 * bridge_clear)
			var wall_t := smoothstep(1.05, 2.60, sd)
			var carved := lerpf(wy - 0.52, bank_top, wall_t)
			result = lerpf(result, minf(result, carved), head_fade)
	if integer_point:
		grid_height_cache[key] = result
	return result

static func anchor_height(at: Vector3) -> float:
	if at == CLOUD_ARENA_CENTER:
		return CLOUD_ARENA_Y
	if at == WANGDAO_PAVILION:
		return 6.80
	if at == BAMBOO_MAZE_GATE:
		return CAVE_FLOOR_Y - 0.65
	if at == BAMBOO_MAZE_EAST:
		return CAVE_FLOOR_Y - 0.42
	if at == YANXIA_CAVE_CENTER or at == YANXIA_CAVE_MOUTH or at == YANXIA_CAVE_SANCTUM:
		return CAVE_FLOOR_Y
	return base_height(at.x, at.z)

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
	var low = height(x, z)
	for d in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius), Vector2(radius * 0.7, radius * 0.7), Vector2(-radius * 0.7, -radius * 0.7)]:
		low = minf(low, height(x + d.x, z + d.y))
	return low

static func path_distance(x: float, z: float, points: Array) -> float:
	var point = Vector2(x, z)
	var distance = INF
	for i in points.size() - 1:
		var a = Vector2(points[i].x, points[i].z)
		var b = Vector2(points[i + 1].x, points[i + 1].z)
		var fraction = clampf((point - a).dot(b - a) / (b - a).length_squared(), 0, 1)
		distance = minf(distance, point.distance_to(a + (b - a) * fraction))
	return distance

static func road_distance(x: float, z: float, limit := INF) -> float:
	_prepare_road_segments()
	var point := Vector2(x, z)
	var segments: Array = road_segments
	if limit <= ROAD_BLEND_RADIUS:
		segments = road_cells.get(Vector2i(floori(x / ROAD_CELL_SIZE), floori(z / ROAD_CELL_SIZE)), [])
	var result: float = limit
	for segment: RoadSegment in segments:
		var fraction := clampf((point - segment.start).dot(segment.direction) / segment.length_squared, 0, 1)
		result = minf(result, point.distance_to(segment.start + segment.direction * fraction))
	return result

static func is_in_bamboo_cave_zone(x: float, z: float, padding: float = 0.0) -> bool:
	return (
		x >= (-49.2 + CAVE_DX - padding)
		and x <= (-34.3 + CAVE_DX + padding)
		and z >= (-71.6 + CAVE_DZ - padding)
		and z <= (-35.6 + CAVE_DZ + padding)
	)

static func is_in_cloud_arena(x: float, z: float, padding: float = 0.0) -> bool:
	return Vector2(x - CLOUD_ARENA_CENTER.x, z - CLOUD_ARENA_CENTER.z).length() < (CLOUD_ARENA_RADIUS + 2.5 + padding)

static func clear_for_route(x: float, z: float, padding = 0.0) -> bool:
	var pad := float(padding)
	if is_in_bamboo_cave_zone(x, z, pad):
		return true
	if is_in_cloud_arena(x, z, pad):
		return true
	if road_distance(x, z, 4.6 + pad) < 4.6 + pad:
		return true
	if stream_distance(x, z) < 3.4 + pad:
		return true
	if Vector2(x - EXIT.x, z - EXIT.z).length() < 9.5 + pad:
		return true
	for station in STATIONS:
		if Vector2(x - station.at.x, z - station.at.z).length() < 14.0 + pad:
			return true
	for camp in COMBAT_ZONES:
		var camp_at: Vector3 = camp.at
		if Vector2(x - camp_at.x, z - camp_at.z).length() < 11.5 + pad:
			return true
	for at in [POEM, MATH, MATH_GATE_CENTER, CLUE, CLUE_LOOT, CLIFF_STELE_AT]:
		if Vector2(x - at.x, z - at.z).length() < 5.5 + pad:
			return true
	for at in [PARKOUR_CONTAINERS, CAVE_GROTTO, WATCHTOWER, SHELTER_BAMBOO]:
		if Vector2(x - at.x, z - at.z).length() < 7.8 + pad:
			return true
	for at in [CLEFT_CACHE, EAST_OVERLOOK, SE_BAMBOO_CACHE, RECON_RADIO, AIRDROP_BEACON, WANGDAO_PAVILION, CAMPHOR_SHRINE]:
		if Vector2(x - at.x, z - at.z).length() < 6.0 + pad:
			return true
	return false
