extends SceneTree

func _initialize():
	var before := GDScript.new()
	before.source_code = FileAccess.get_file_as_string(OS.get_environment("YS_BASELINE_LAYOUT"))
	if before.reload() != OK:
		quit(2)
		return
	var after = load("res://scripts/layout.gd")
	var max_height := 0.0
	var max_road := 0.0
	var max_stream := 0.0
	var points := 0
	for z in range(-120, 37):
		max_stream = maxf(max_stream, absf(after.stream_center_x(z + 0.55) - before.stream_center_x(z + 0.55)))
		for x in range(-60, 61):
			max_height = maxf(max_height, absf(after.height(x, z) - before.height(x, z)))
			max_road = maxf(max_road, absf(after.road_distance(x, z, 4.5) - minf(4.5, before.road_distance(x, z))))
			points += 1
			if posmod(x * 2 + z, 5) == 0:
				max_height = maxf(max_height, absf(after.height(x + 0.55, z - 0.55) - before.height(x + 0.55, z - 0.55)))
				points += 1
	print("LAYOUT_PARITY ", JSON.stringify({"points": points, "height_m": max_height, "road_m": max_road, "stream_center_m": max_stream}))
	quit(0 if maxf(max_height, maxf(max_road, max_stream)) <= 0.000002 else 1)
