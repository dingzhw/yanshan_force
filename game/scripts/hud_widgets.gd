extends Control
## Delta Force-inspired ultra-clean vector tactical HUD icons (v0.9.3).
## Draws crisp resolution-independent icons without cluttering the screen with verbose text:
## - StanceSilhouette: standing / crouching / prone operator silhouette + Q/E lean arrow + 1P/3P badge
## - TacticalSlotIcon: 44x44 translucent icon tiles for [H] Medkit, [G] Smoke/EMP, [T] Stim, [V] Shaoyu Skill (with cooldown sweep)
## - WeaponGlyph: sleek rifle vs knife silhouette glyph next to the big ammo counter

class StanceSilhouette extends Control:
	var stance: int = 0
	var lean_dir: int = 0
	var third_person: bool = false

	func set_state(s: int, l: int, tp: bool):
		if stance == s and lean_dir == l and third_person == tp:
			return
		stance = s
		lean_dir = l
		third_person = tp
		queue_redraw()

	func _draw():
		var w := size.x
		var h := size.y
		var bg := Color(0.05, 0.11, 0.13, 0.62)
		var border := Color(0.55, 0.90, 0.74, 0.42) if not third_person else Color(1.0, 0.84, 0.38, 0.68)
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.2)

		var col := Color("dff7ee")
		var cx := w * 0.5 + float(lean_dir) * 4.0
		if stance == 0:
			# Standing operator silhouette
			draw_circle(Vector2(cx, 11.0), 4.2, col)
			draw_line(Vector2(cx, 16.0), Vector2(cx, 31.0), col, 4.0)
			draw_line(Vector2(cx - 6.0, 20.0), Vector2(cx + 7.0, 22.0), col, 2.4)
			draw_line(Vector2(cx - 2.0, 30.0), Vector2(cx - 5.5, 43.0), col, 3.0)
			draw_line(Vector2(cx + 2.0, 30.0), Vector2(cx + 5.5, 43.0), col, 3.0)
		elif stance == 1:
			# Crouching silhouette
			draw_circle(Vector2(cx, 19.0), 4.0, Color("ffd86b"))
			draw_line(Vector2(cx, 24.0), Vector2(cx - 2.0, 33.0), Color("ffd86b"), 3.8)
			draw_line(Vector2(cx - 2.0, 33.0), Vector2(cx + 6.0, 36.0), Color("ffd86b"), 2.8)
			draw_line(Vector2(cx + 6.0, 36.0), Vector2(cx + 5.0, 44.0), Color("ffd86b"), 2.8)
			draw_line(Vector2(cx - 2.0, 33.0), Vector2(cx - 6.0, 44.0), Color("ffd86b"), 2.8)
		else:
			# Prone horizontal silhouette
			draw_circle(Vector2(cx + 11.0, 33.0), 3.6, Color("5ce8ff"))
			draw_line(Vector2(cx - 13.0, 37.0), Vector2(cx + 7.0, 35.0), Color("5ce8ff"), 4.2)
			draw_line(Vector2(cx + 6.0, 36.0), Vector2(cx + 15.0, 38.0), Color("5ce8ff"), 2.2)

		if lean_dir != 0:
			var ax := cx + float(lean_dir) * 14.0
			draw_circle(Vector2(ax, 12.0), 2.5, Color("ffd15c"))

class TacticalSlotIcon extends Control:
	var kind: String = "medkit"  # medkit | emp | stim | skill
	var key_text: String = "H"
	var count_val: int = 1
	var ready_frac: float = 1.0
	var active_sec: float = 0.0
	var label_font: Font

	func configure(k: String, key_s: String, f: Font):
		kind = k
		key_text = key_s
		label_font = f
		queue_redraw()

	func update_state(cnt: int, frac: float = 1.0, act_s: float = 0.0):
		if count_val == cnt and absf(ready_frac - frac) < 0.015 and absf(active_sec - act_s) < 0.25:
			return
		count_val = cnt
		ready_frac = clampf(frac, 0.0, 1.0)
		active_sec = act_s
		queue_redraw()

	func _draw():
		var w := size.x
		var h := size.y
		var is_skill := (kind == "skill")
		var available := (ready_frac >= 0.999) if is_skill else (count_val > 0)
		var accent := Color("6ae3a8")
		if kind == "medkit":
			accent = Color("ff6b72")
		elif kind == "emp":
			accent = Color("4ceeff")
		elif kind == "stim":
			accent = Color("ffd86b")
		elif kind == "skill":
			accent = Color("ffd15c") if available else Color("56d8ff")

		var bg := Color(0.05, 0.10, 0.12, 0.68 if available else 0.40)
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		if is_skill and ready_frac < 0.999:
			var fill_h := h * ready_frac
			draw_rect(Rect2(0.0, h - fill_h, w, fill_h), Color(0.24, 0.62, 0.78, 0.24), true)
		elif active_sec > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r, accent.g, accent.b, 0.20), true)
		draw_rect(Rect2(Vector2.ZERO, size), accent if available else Color(0.45, 0.56, 0.58, 0.32), false, 1.5 if available else 1.0)

		var ic := accent if available else Color(0.50, 0.58, 0.60, 0.52)
		var cx := w * 0.5
		var cy := h * 0.46
		if kind == "medkit":
			draw_rect(Rect2(cx - 3.0, cy - 9.0, 6.0, 18.0), ic, true)
			draw_rect(Rect2(cx - 9.0, cy - 3.0, 18.0, 6.0), ic, true)
		elif kind == "emp":
			draw_circle(Vector2(cx, cy + 1.0), 7.5, ic)
			draw_circle(Vector2(cx, cy + 1.0), 3.6, bg)
			draw_rect(Rect2(cx - 3.5, cy - 10.5, 7.0, 4.0), ic, true)
		elif kind == "stim":
			var pts := PackedVector2Array([
				Vector2(cx + 2.0, cy - 10.0), Vector2(cx - 5.0, cy + 1.0), Vector2(cx + 0.5, cy + 1.0),
				Vector2(cx - 2.5, cy + 10.0), Vector2(cx + 5.5, cy - 1.0), Vector2(cx, cy - 1.0)
			])
			draw_colored_polygon(pts, ic)
		else:
			# Shaoyu [V] shockwave diamond + double ring
			draw_arc(Vector2(cx, cy), 9.5, 0.0, TAU, 18, ic, 1.6)
			var dpts := PackedVector2Array([
				Vector2(cx, cy - 6.5), Vector2(cx + 6.0, cy), Vector2(cx, cy + 6.5), Vector2(cx - 6.0, cy)
			])
			draw_colored_polygon(dpts, ic)

		if label_font != null:
			draw_string(label_font, Vector2(4.0, 12.0), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("b9d4c8"))
			var badge := ""
			if is_skill:
				badge = "OK" if available else ("%ds" % ceili(active_sec))
			else:
				badge = ("%.0fs" % active_sec) if active_sec > 0.1 else ("×%d" % count_val)
			draw_string(label_font, Vector2(0.0, h - 4.0), badge, HORIZONTAL_ALIGNMENT_RIGHT, w - 4.0, 11, Color("f6fbf8") if available else Color("859894"))

class WeaponGlyph extends Control:
	var is_knife: bool = false

	func set_knife(k: bool):
		if is_knife == k:
			return
		is_knife = k
		queue_redraw()

	func _draw():
		var col := Color("ffd86b") if is_knife else Color("dff7ee")
		if is_knife:
			var pts := PackedVector2Array([
				Vector2(6, 17), Vector2(18, 17), Vector2(20, 12), Vector2(46, 10), Vector2(36, 19), Vector2(18, 19), Vector2(6, 20)
			])
			draw_colored_polygon(pts, col)
		else:
			# Crisp YS-04 carbine silhouette
			draw_rect(Rect2(4, 11, 11, 7), col, true)      # Stock
			draw_rect(Rect2(14, 10, 22, 6), col, true)     # Receiver & handguard
			draw_rect(Rect2(36, 11.5, 13, 3), col, true)   # Barrel
			draw_rect(Rect2(20, 6.5, 9, 3.5), Color("8de8c0"), true) # Optic
			draw_rect(Rect2(23, 16, 4.5, 8), col, true)    # Magazine
			draw_rect(Rect2(15, 16, 4, 6), col, true)      # Grip
