extends RefCounted

const MIN_X = -56.0
const MAX_X = 56.0
const MIN_Z = -116.0
const MAX_Z = 28.0
const FENCE_MIN_X = -52.0
const FENCE_MAX_X = 52.0
const FENCE_MIN_Z = -112.0
const FENCE_MAX_Z = 26.0
const STREAM_Z_MIN = -111.0
const STREAM_Z_MAX = 26.0
const STREAM_BRIDGES = [7.0, -24.0, -46.5]
const STREAM_POINTS = [
	[-116.0, 15.6],
	[-101.0, 16.5],
	[-88.0, 24.2],
	[-76.0, 24.6],
	[-62.0, 21.2],
	[-46.5, 18.5],
	[-24.0, 16.5],
	[7.0, 18.6],
	[28.0, 17.6]
]
const SPAWN = Vector3(0, 0, 4.5)
const STATIONS = [
	{"id": "camp", "title": "A · 山脚营地", "at": SPAWN},
	{"id": "forest", "title": "林间前哨", "at": Vector3(-12, 0, -42)},
	{"id": "rocks", "title": "B · 竹林补给点", "at": Vector3(8, 0, -86)}
]
const PASS_OUTPOST = Vector3(-1, 0, -65)
const COMBAT_ZONES = [
	{"id": "forest", "title": "林间前哨", "at": Vector3(-12, 0, -42), "waves": 4, "aggro": 23.0, "pursuit": 28.0},
	{"id": "pass", "title": "山道拦截哨", "at": PASS_OUTPOST, "waves": 3, "aggro": 19.0, "pursuit": 24.0},
	{"id": "bamboo", "title": "B · 竹林重兵阵地", "at": Vector3(8, 0, -86), "waves": 5, "aggro": 24.0, "pursuit": 30.0}
]
const EXIT = Vector3(18, 0, -76)
const ROUTE = [SPAWN, Vector3(-7, 0, -15), Vector3(-18, 0, -27), Vector3(-12, 0, -42), Vector3(-7, 0, -54), PASS_OUTPOST, Vector3(8, 0, -86), EXIT]
const POEM = Vector3(-28, 0, -29)
const MATH = Vector3(1, 0, -58)
const CLUE = Vector3(3.5, 0, -18)
const CLUE_LOOT = Vector3(8, 0, -23)
const PARKOUR_CONTAINERS = Vector3(-21.5, 0, -11.5)
const CLEFT_CACHE = Vector3(-29.5, 0, -51.5)
const CAVE_GROTTO = Vector3(-25.5, 0, -68.5)
const EAST_OVERLOOK = Vector3(26.5, 0, -24.0)
const SE_BAMBOO_CACHE = Vector3(29.5, 0, -86.5)
const RECON_RADIO = Vector3(27.5, 0, -46.5)
const AIRDROP_BEACON = Vector3(23.5, 0, -101.0)
const WATCHTOWER = Vector3(-34.0, 0, -102.0)
const SHELTER_BAMBOO = Vector3(14.0, 0, -88.0)
const BRANCHES = [[Vector3(-18, 0, -27), POEM], [Vector3(-7, 0, -54), MATH, Vector3(12, 0, -62), EXIT], [Vector3(-7, 0, -15), CLUE, CLUE_LOOT]]
static var grid_height_cache = {}
static var stream_water_heights: Array = []

static func base_height(x: float, z: float) -> float:
	if z > 0 and absf(x) < 18:
		return 0.0
	var climb = smoothstep(-3.0, 105.0, -z) * 8.0
	var shoulders = smoothstep(11.0, 36.0, absf(x)) * 5.0
	return climb + shoulders + (sin(x * 0.12 + z * 0.045) * 1.8 + sin(z * 0.13) * 0.8) * smoothstep(5, 27, -z)

static func stream_center_x(z: float) -> float:
	if z <= STREAM_POINTS[0][0]:
		return STREAM_POINTS[0][1]
	for i in STREAM_POINTS.size() - 1:
		var z0 := float(STREAM_POINTS[i][0])
		var x0 := float(STREAM_POINTS[i][1])
		var z1 := float(STREAM_POINTS[i + 1][0])
		var x1 := float(STREAM_POINTS[i + 1][1])
		if z <= z1:
			var t := clampf((z - z0) / (z1 - z0), 0.0, 1.0)
			var s := t * t * (3.0 - 2.0 * t)
			return lerpf(x0, x1, s)
	return float(STREAM_POINTS[-1][1])

static func stream_distance(x: float, z: float) -> float:
	if z < STREAM_Z_MIN - 1.5 or z > STREAM_Z_MAX + 2.0:
		return INF
	return absf(x - stream_center_x(z))

static func _land_height(x: float, z: float) -> float:
	var key = Vector2(x, z)
	var result = base_height(x, z)
	for station in STATIONS:
		var at = station.at
		var blend = 1.0 - smoothstep(10.0, 15.0, Vector2(x - at.x, z - at.z).length())
		result = lerpf(result, base_height(at.x, at.z), blend)
	for at in [EXIT, POEM, MATH, CLUE, CLUE_LOOT, PASS_OUTPOST, PARKOUR_CONTAINERS, CAVE_GROTTO, RECON_RADIO, AIRDROP_BEACON, WATCHTOWER, SHELTER_BAMBOO]:
		var blend = 1.0 - smoothstep(4.0, 9.0, Vector2(x - at.x, z - at.z).length())
		result = lerpf(result, anchor_height(at), blend)
	var nearest = INF
	var bed = result
	for path in [ROUTE] + BRANCHES:
		for i in path.size() - 1:
			var a = Vector2(path[i].x, path[i].z)
			var b = Vector2(path[i + 1].x, path[i + 1].z)
			var t = clampf((key - a).dot(b - a) / (b - a).length_squared(), 0, 1)
			var distance = key.distance_to(a + (b - a) * t)
			if distance < nearest:
				nearest = distance
				bed = lerpf(anchor_height(path[i]), anchor_height(path[i + 1]), t)
	var road_t := 1.0 - smoothstep(2.3, 5.2, nearest)
	result = lerpf(result, bed, road_t)
	for bz in STREAM_BRIDGES:
		var bcx := stream_center_x(float(bz))
		if absf(x - bcx) < 11.5 and absf(z - float(bz)) < 4.8:
			var wh := base_height(bcx - 5.0, float(bz))
			var eh := base_height(bcx + 5.0, float(bz))
			var saddle := lerpf(wh, eh, 0.35)
			var wx := 1.0 - smoothstep(5.5, 11.5, absf(x - bcx))
			var wz := 1.0 - smoothstep(2.0, 4.8, absf(z - float(bz)))
			result = lerpf(result, saddle, wx * wz)
	return result

static func _ensure_stream_profile():
	if not stream_water_heights.is_empty():
		return
	var z_start := -116
	var count := 145  # -116 .. +28 inclusive
	stream_water_heights.resize(count)
	var prev := 999.0
	for i in count:
		var z := float(z_start + i)
		var cx := stream_center_x(z)
		var bank := (_land_height(cx - 3.4, z) + _land_height(cx + 3.4, z)) * 0.5 - 0.34
		var wy := bank if i == 0 else minf(prev - 0.018, bank)
		stream_water_heights[i] = wy
		prev = wy

static func stream_water_y(z: float) -> float:
	_ensure_stream_profile()
	var fidx := clampf(z + 116.0, 0.0, float(stream_water_heights.size() - 2))
	var idx := int(floorf(fidx))
	return lerpf(float(stream_water_heights[idx]), float(stream_water_heights[idx + 1]), fidx - float(idx))

static func height(x: float, z: float) -> float:
	var key = Vector2(x, z)
	var integer_point = x == floorf(x) and z == floorf(z)
	if integer_point and grid_height_cache.has(key):
		return grid_height_cache[key]
	var result = _land_height(x, z)
	var sd := stream_distance(x, z)
	if sd < 4.5 and z >= STREAM_Z_MIN - 1.5 and z <= STREAM_Z_MAX + 2.0:
		var wy := stream_water_y(z)
		var channel_t := 1.0 - smoothstep(1.35, 4.45, sd)
		var end_fade := smoothstep(STREAM_Z_MIN - 1.5, STREAM_Z_MIN + 1.5, z)
		var bed_target := minf(result, wy - 0.42)
		result = lerpf(result, bed_target, channel_t * end_fade)
	if integer_point:
		grid_height_cache[key] = result
	return result

static func anchor_height(at: Vector3) -> float:
	return 5.0 if at == POEM else base_height(at.x, at.z)

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

static func road_distance(x: float, z: float) -> float:
	var result = path_distance(x, z, ROUTE)
	for branch in BRANCHES:
		result = minf(result, path_distance(x, z, branch))
	return result

static func clear_for_route(x: float, z: float, padding = 0.0) -> bool:
	if road_distance(x, z) < 4.5 + padding:
		return true
	if stream_distance(x, z) < 2.9 + padding:
		return true
	if Vector2(x - EXIT.x, z - EXIT.z).length() < 8 + padding:
		return true
	for station in STATIONS:
		if Vector2(x - station.at.x, z - station.at.z).length() < 14 + padding:
			return true
	if Vector2(x - PASS_OUTPOST.x, z - PASS_OUTPOST.z).length() < 11 + padding:
		return true
	for at in [POEM, MATH, CLUE, CLUE_LOOT]:
		if Vector2(x - at.x, z - at.z).length() < 5 + padding:
			return true
	for at in [PARKOUR_CONTAINERS, CAVE_GROTTO, WATCHTOWER, SHELTER_BAMBOO]:
		if Vector2(x - at.x, z - at.z).length() < 7.5 + padding:
			return true
	for at in [CLEFT_CACHE, EAST_OVERLOOK, SE_BAMBOO_CACHE, RECON_RADIO, AIRDROP_BEACON]:
		if Vector2(x - at.x, z - at.z).length() < 5.0 + padding:
			return true
	return false
