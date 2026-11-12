extends RefCounted

const MIN_X = -56.0
const MAX_X = 56.0
const MIN_Z = -116.0
const MAX_Z = 28.0
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
const BRANCHES = [[Vector3(-18, 0, -27), POEM], [Vector3(-7, 0, -54), MATH, Vector3(12, 0, -62), EXIT], [Vector3(-7, 0, -15), CLUE, CLUE_LOOT]]
static var grid_height_cache = {}

static func base_height(x: float, z: float) -> float:
	if z > 0 and absf(x) < 18:
		return 0.0
	var climb = smoothstep(-3.0, 105.0, -z) * 8.0
	var shoulders = smoothstep(11.0, 36.0, absf(x)) * 5.0
	return climb + shoulders + (sin(x * 0.12 + z * 0.045) * 1.8 + sin(z * 0.13) * 0.8) * smoothstep(5, 27, -z)

static func height(x: float, z: float) -> float:
	var key = Vector2(x, z)
	var integer_point = x == floorf(x) and z == floorf(z)
	if integer_point and grid_height_cache.has(key):
		return grid_height_cache[key]
	var result = base_height(x, z)
	for station in STATIONS:
		var at = station.at
		var blend = 1.0 - smoothstep(10.0, 15.0, Vector2(x - at.x, z - at.z).length())
		result = lerpf(result, base_height(at.x, at.z), blend)
	for at in [EXIT, POEM, MATH, CLUE, CLUE_LOOT, PASS_OUTPOST]:
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
	result = lerpf(result, bed, 1.0 - smoothstep(2.3, 5.2, nearest))
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
	return false
