extends RefCounted

const MIN_X = -60.0
const MAX_X = 60.0
const MIN_Z = -120.0
const MAX_Z = 36.0
const FENCE_MIN_X = -52.0
const FENCE_MAX_X = 52.0
const FENCE_MIN_Z = -112.0
const FENCE_MAX_Z = 26.0
const STREAM_Z_MIN = -111.0
const STREAM_Z_MAX = 36.0
const STREAM_BRIDGES = [7.0, -24.0, -46.5, -73.5]
const STREAM_POINTS = [
	[-116.0, 15.6],
	[-101.0, 16.5],
	[-88.0, 24.2],
	[-76.0, 24.6],
	[-62.0, 21.2],
	[-46.5, 18.5],
	[-24.0, 16.5],
	[7.0, 18.6],
	[26.0, 17.6],
	[31.0, 18.3],
	[36.0, 19.6]
]
const SPAWN = Vector3(0, 0, 4.5)
const STATIONS = [
	{"id": "camp", "title": "A · 山脚营地", "at": SPAWN},
	{"id": "forest", "title": "林间前哨", "at": Vector3(-12, 0, -42)},
	{"id": "rocks", "title": "B · 竹林补给点", "at": Vector3(8, 0, -86)}
]
const PASS_OUTPOST = Vector3(-1, 0, -65)
const WEST_CAMP = Vector3(-34.0, 0, -18.0)
const EAST_CAMP = Vector3(37.5, 0, -34.0)
const NW_CAMP = Vector3(-31.0, 0, -85.0)
const COMBAT_ZONES = [
	{"id": "forest", "title": "林间古道营地", "at": Vector3(-12.0, 0, -42.0), "waves": 3, "squad": 5, "aggro": 15.8, "pursuit": 86.0, "boss": false},
	{"id": "pass", "title": "山道拦截营地", "at": PASS_OUTPOST, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 86.0, "boss": false},
	{"id": "bamboo", "title": "B区竹林统领营", "at": Vector3(6.5, 0, -90.0), "waves": 3, "squad": 5, "aggro": 15.8, "pursuit": 86.0, "boss": true},
	{"id": "west_ridge", "title": "西岭山坡营地", "at": WEST_CAMP, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 86.0, "boss": false},
	{"id": "east_ridge", "title": "东坡茶岭营地", "at": EAST_CAMP, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 86.0, "boss": false},
	{"id": "nw_plateau", "title": "西北高地营地", "at": NW_CAMP, "waves": 3, "squad": 5, "aggro": 15.2, "pursuit": 86.0, "boss": false}
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
const WANGDAO_PAVILION = Vector3(33.5, 0, 20.8)
const CAMPHOR_SHRINE = Vector3(10.6, 0, -16.8)
const SE_BAMBOO_CACHE = Vector3(29.5, 0, -86.5)
const RECON_RADIO = Vector3(27.5, 0, -46.5)
const AIRDROP_BEACON = Vector3(23.5, 0, -101.0)
const WATCHTOWER = Vector3(-34.0, 0, -102.0)
const SHELTER_BAMBOO = Vector3(14.0, 0, -88.0)
const BRANCHES = [
	[Vector3(-18, 0, -27), POEM],
	[Vector3(-7, 0, -54), MATH, Vector3(12, 0, -62), EXIT],
	# Central Stone Arch Bridge (z = -24.0) -> East Overlook & South Ridge to Wangdao Pavilion
	[Vector3(-7, 0, -15), CLUE, CLUE_LOOT, Vector3(11.0, 0, -24.0), Vector3(22.2, 0, -24.0), EAST_OVERLOOK, Vector3(28.5, 0, -8.0), Vector3(31.5, 0, 8.0), WANGDAO_PAVILION],
	# South Camp Wooden Bridge (z = 7.0) -> Gentle East Hillside Trail to Wangdao Pavilion & North Link
	[SPAWN, Vector3(13.2, 0, 7.0), Vector3(23.8, 0, 7.0), Vector3(28.0, 0, 13.5), WANGDAO_PAVILION],
	[Vector3(23.8, 0, 7.0), Vector3(28.5, 0, -8.0)],
	# Upstream Wooden Bridge (z = -46.5) -> Gentle Walkable Climb to East Recon Radio & North Loop
	[Vector3(-7, 0, -54), Vector3(5.5, 0, -49.0), Vector3(13.2, 0, -46.5), Vector3(23.4, 0, -46.5), RECON_RADIO],
	[EAST_OVERLOOK, Vector3(27.0, 0, -35.5), RECON_RADIO, Vector3(28.2, 0, -60.0), Vector3(30.2, 0, -73.5), SE_BAMBOO_CACHE],
	# Northern Creek Wooden Bridge (z = -73.5, cx ≈ 24.3) -> East Bamboo Cache & Airdrop Beacon
	[EXIT, Vector3(18.6, 0, -73.5), Vector3(30.2, 0, -73.5), Vector3(26.5, 0, -94.0), AIRDROP_BEACON]
]
static var grid_height_cache = {}
static var stream_water_heights: Array = []
static var fast_height_grid: PackedFloat32Array = PackedFloat32Array()

static func base_height(x: float, z: float) -> float:
	if z > 0.0 and z <= 28.0 and absf(x) < 18.0:
		return 0.0
	if z > 28.0 and absf(x) < 18.0:
		return -smoothstep(28.0, 36.0, z) * 0.85
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
	if z < STREAM_Z_MIN - 1.5 or z > STREAM_Z_MAX + 1.0:
		return INF
	return absf(x - stream_center_x(z))

static func _land_height(x: float, z: float) -> float:
	var key = Vector2(x, z)
	var result = base_height(x, z)
	for station in STATIONS:
		var at = station.at
		var blend = 1.0 - smoothstep(10.0, 15.0, Vector2(x - at.x, z - at.z).length())
		result = lerpf(result, base_height(at.x, at.z), blend)
	for at in [EXIT, POEM, MATH, CLUE, CLUE_LOOT, PASS_OUTPOST, WEST_CAMP, EAST_CAMP, NW_CAMP, PARKOUR_CONTAINERS, CAVE_GROTTO, EAST_OVERLOOK, RECON_RADIO, SE_BAMBOO_CACHE, AIRDROP_BEACON, WATCHTOWER, SHELTER_BAMBOO, WANGDAO_PAVILION, CAMPHOR_SHRINE, Vector3(10.75, 0, -21.55)]:
		var blend = 1.0 - smoothstep(4.5, 11.0, Vector2(x - at.x, z - at.z).length())
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
	var road_t := 1.0 - smoothstep(2.8, 7.6, nearest)
	result = lerpf(result, bed, road_t)
	var pav_pad := 1.0 - smoothstep(5.4, 10.5, Vector2(x - WANGDAO_PAVILION.x, z - WANGDAO_PAVILION.z).length())
	result = lerpf(result, anchor_height(WANGDAO_PAVILION), pav_pad)
	for bz in STREAM_BRIDGES:
		var bcx := stream_center_x(float(bz))
		if absf(x - bcx) < 16.5 and absf(z - float(bz)) < 8.5:
			var wh := base_height(bcx - 5.2, float(bz))
			var eh := base_height(bcx + 5.2, float(bz))
			var saddle := lerpf(wh, eh, 0.38)
			var wx := 1.0 - smoothstep(5.0, 16.5, absf(x - bcx))
			var wz := 1.0 - smoothstep(2.6, 8.5, absf(z - float(bz)))
			result = lerpf(result, saddle, wx * wz)
	return result

static func land_edge_height(x: float, z: float) -> float:
	return _land_height(x, z)

static func _ensure_stream_profile():
	if not stream_water_heights.is_empty():
		return
	var z_start := -120
	var count := 157  # -120 .. +36 inclusive
	stream_water_heights.resize(count)
	var prev := 999.0
	for i in count:
		var z := float(z_start + i)
		var cx := stream_center_x(z)
		var low_bank := minf(_land_height(cx - 3.6, z), _land_height(cx + 3.6, z))
		var avg_bank := (_land_height(cx - 3.6, z) + _land_height(cx + 3.6, z)) * 0.5
		var bank_ref := lerpf(low_bank, avg_bank, 0.35) - 0.36
		var wy := bank_ref if i == 0 else minf(prev - 0.017, bank_ref)
		stream_water_heights[i] = wy
		prev = wy

static func stream_water_y(z: float) -> float:
	_ensure_stream_profile()
	var fidx := clampf(z + 120.0, 0.0, float(stream_water_heights.size() - 2))
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
		var bridge_clear := smoothstep(1.3, 2.6, min_bz)
		# Natural raised earthen/stone creek bank lip (+0.38m above water on both sides)
		var lip_target := maxf(result, wy + 0.38)
		var lip_w := smoothstep(1.65, 2.60, sd) * (1.0 - smoothstep(3.35, 5.10, sd)) * head_fade * bridge_clear
		result = lerpf(result, lip_target, lip_w)
		# True recessed U-shaped streambed channel (water at wy sits ~0.38m below bank lips, bed at wy - 0.52m)
		if sd < 2.65:
			var bank_top := maxf(result, wy + 0.36 * bridge_clear)
			var wall_t := smoothstep(1.05, 2.60, sd)
			var carved := lerpf(wy - 0.52, bank_top, wall_t)
			result = lerpf(result, minf(result, carved), head_fade)
	if integer_point:
		grid_height_cache[key] = result
	return result

static func anchor_height(at: Vector3) -> float:
	if at == POEM:
		return 5.0
	if at == WANGDAO_PAVILION:
		return 4.35
	if at == EAST_OVERLOOK:
		return 3.95
	if at == RECON_RADIO:
		return 5.55
	if at == SE_BAMBOO_CACHE:
		return 7.35
	if at == Vector3(23.8, 0, 7.0):
		return 0.72
	if at == Vector3(22.2, 0, -24.0):
		return 3.10
	if at == Vector3(23.4, 0, -46.5):
		return 4.55
	if at == Vector3(30.2, 0, -73.5):
		return 6.35
	return base_height(at.x, at.z)

static func _ensure_fast_grid():
	if not fast_height_grid.is_empty():
		return
	# 121 (x: -60..60) x 157 (z: -120..36) = 18997 pre-baked floats matching HeightMapShape3D!
	fast_height_grid.resize(121 * 157)
	var idx := 0
	for zi in range(-120, 37):
		var zf := float(zi)
		for xi in range(-60, 61):
			fast_height_grid[idx] = height(float(xi), zf)
			idx += 1

static func fast_height(x: float, z: float) -> float:
	_ensure_fast_grid()
	var fx := clampf(x + 60.0, 0.0, 119.999)
	var fz := clampf(z + 120.0, 0.0, 155.999)
	var ix := int(floorf(fx))
	var iz := int(floorf(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var row0 := iz * 121 + ix
	var row1 := row0 + 121
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

static func road_distance(x: float, z: float) -> float:
	var result = path_distance(x, z, ROUTE)
	for branch in BRANCHES:
		result = minf(result, path_distance(x, z, branch))
	return result

static func clear_for_route(x: float, z: float, padding = 0.0) -> bool:
	if road_distance(x, z) < 4.5 + padding:
		return true
	if stream_distance(x, z) < 3.1 + padding:
		return true
	if Vector2(x - EXIT.x, z - EXIT.z).length() < 8 + padding:
		return true
	for station in STATIONS:
		if Vector2(x - station.at.x, z - station.at.z).length() < 14 + padding:
			return true
	for camp_at in [PASS_OUTPOST, WEST_CAMP, EAST_CAMP, NW_CAMP, Vector3(6.5, 0, -90.0)]:
		if Vector2(x - camp_at.x, z - camp_at.z).length() < 10.5 + padding:
			return true
	for at in [POEM, MATH, CLUE, CLUE_LOOT]:
		if Vector2(x - at.x, z - at.z).length() < 5 + padding:
			return true
	for at in [PARKOUR_CONTAINERS, CAVE_GROTTO, WATCHTOWER, SHELTER_BAMBOO]:
		if Vector2(x - at.x, z - at.z).length() < 7.5 + padding:
			return true
	for at in [CLEFT_CACHE, EAST_OVERLOOK, SE_BAMBOO_CACHE, RECON_RADIO, AIRDROP_BEACON, WANGDAO_PAVILION, CAMPHOR_SHRINE]:
		if Vector2(x - at.x, z - at.z).length() < 5.0 + padding:
			return true
	return false
