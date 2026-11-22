extends SceneTree
## v0.9.2 Visual Showcase & Bugfix Audit Capture Suite (8 crisp 1280x720 GL Compatibility renders)
## Captures:
##   v092_01_pickups_closeup.png     — All 4 sculpted Blender 4.5 PBR pickups (ammo, medkit, EMP grenade, stim) + desert loot table
##   v092_02_desert_stash_oasis.png  — Sculpted Ahsarah terracotta amphora desert stash & recessed oasis spring
##   v092_03_saeed_m249_firezones.png — Captain Saeed M249 LMG tracers + glowing burning crossbow fire zones
##   v092_04_reis_symphony_shotgun.png — Warlord Reis Brass Gramophone golden shockwave ring + S12K shotgun cone + frag grenades
##   v092_05_zero_dam_artillery.png  — Zero Dam Artillery Ultimate (beacons + streaking shells from Zero Dam crest!)
##   v092_06_cement_camp_clean.png   — Cement Plant clean open camp with visible soldiers, desert covers & level catwalk
##   v092_07_substation_solid.png    — Haavk Substation open switchyard, solid transformer bays & Haavk troopers
##   v092_08_bazaar_bathhouse.png    — Brakkesh Grand Bathhouse plaza, amphora stash & zero terrain clipping

func frames(n: int):
	for _i in n:
		await process_frame

func _initialize():
	call_deferred("run")

func _look_at_pos(game, eye_pos: Vector3, target_pos: Vector3):
	game.player.position = eye_pos - Vector3(0.0, 1.56, 0.0)
	game.player.velocity = Vector3.ZERO
	var d := target_pos - eye_pos
	var yaw := atan2(-d.x, -d.z)
	var horiz := Vector2(d.x, d.z).length()
	var pitch := clampf(atan2(d.y, maxf(0.01, horiz)), -1.15, 1.15)
	game.player.rotation.y = yaw
	game.player.camera.rotation.x = pitch

func _snap(out_dir: String, fname: String):
	await frames(6)
	var img := root.get_viewport().get_texture().get_image()
	var full := out_dir + "/" + fname
	img.save_png(full)
	print("CAPTURED ", full)

func run():
	var tmp_profile := "user://capture_v092_profile.json"
	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))

	var game = load("res://main.tscn").instantiate()
	game.profile_path_override = tmp_profile
	root.add_child(game)
	await frames(6)

	game.rules.unlock_map("ahsarah")
	game.switch_map("ahsarah")
	await frames(6)
	game.start_action(true, "normal")
	await frames(8)

	# Hide first-person rifle briefly for clean architectural/boss framing when needed, keep HUD crisp!
	var out_dir := ProjectSettings.globalize_path("res://../docs/media")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1. Sculpted Blender 4.5 PBR Pickups Close-up (South Oasis Supply Depot: ammo, medkit, EMP, stim!)
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.visible = false
	var y_o: float = game.AhsarahLayout.height(3.6, 8.0)
	_look_at_pos(game, Vector3(3.6, y_o + 1.95, 10.6), Vector3(3.6, y_o + 0.28, 7.6))
	await _snap(out_dir, "v092_01_pickups_closeup.png")

	# 2. Sculpted Ahsarah Desert Amphora Stash + Recessed Oasis Spring Pool (clear framing!)
	var y_st: float = game.AhsarahLayout.height(-12.5, 18.2)
	_look_at_pos(game, Vector3(-12.2, y_st + 1.55, 20.6), Vector3(-13.2, y_st + 0.30, 16.5))
	await _snap(out_dir, "v092_02_desert_stash_oasis.png")

	# 3. Captain Saeed ('赤枭·赛伊德') M249 LMG Tracers + Persistent Burning Fire Zones!
	var ay: float = game.AhsarahLayout.CLOUD_ARENA_Y
	var saeed = game.combat.boss_unit
	saeed.position = Vector3(0.0, ay + 0.12, -124.0)
	game.player.position = Vector3(0.0, ay + 0.10, -112.0)
	game.combat.engage_camp(2, true)
	await frames(4)
	# Spawn vivid persistent fire zones + mid-air incendiary bolt + M249 tracers for live combat snapshot!
	game.combat.spawn_fire_zone(Vector3(-3.2, ay, -118.2), 2.55, 10.0, 0)
	game.combat.spawn_fire_zone(Vector3(3.4, ay, -117.5), 2.55, 10.0, 0)
	game.combat.spawn_incendiary_bolt(Vector3(0.0, ay + 2.0, -123.5), Vector3(0.4, ay, -116.5), 0)
	for ang_d in [-14.0, -6.0, 2.0, 10.0]:
		var m_from := Vector3(0.3, ay + 1.85, -123.2)
		var m_dir := Vector3(0.0, -0.04, 1.0).rotated(Vector3.UP, deg_to_rad(ang_d)).normalized()
		game.combat.fire_saeed_lmg_tracer(m_from, m_dir, 0)
	_look_at_pos(game, Vector3(0.5, ay + 3.2, -110.5), Vector3(0.0, ay + 1.6, -123.5))
	await _snap(out_dir, "v092_03_saeed_m249_firezones.png")

	# 4. Cement Plant Clean Open Camp (visible soldiers, desert sandstone covers, solid silos & level catwalk!)
	var cy: float = game.AhsarahLayout.height(-39.0, -35.0)
	_look_at_pos(game, Vector3(-24.0, cy + 5.6, -24.0), Vector3(-42.0, cy + 2.2, -40.0))
	await _snap(out_dir, "v092_06_cement_camp_clean.png")

	# 5. Haavk Substation Clean Switchyard (visible Haavk troopers west of solid Transformer Bays!)
	var sy: float = game.AhsarahLayout.height(42.5, -89.0)
	_look_at_pos(game, Vector3(30.5, sy + 4.4, -76.5), Vector3(47.5, sy + 1.8, -90.5))
	await _snap(out_dir, "v092_07_substation_solid.png")

	# 6. Brakkesh Bazaar & Grand Bathhouse (open plaza covers, amphora stash, zero terrain clipping!)
	var by: float = game.AhsarahLayout.height(33.5, -36.5)
	_look_at_pos(game, Vector3(21.5, by + 4.8, -28.0), Vector3(39.0, by + 2.2, -33.0))
	await _snap(out_dir, "v092_08_bazaar_bathhouse.png")

	# 7. Confidential Mode Warlord Reis ('阿萨拉军阀·雷斯') Symphony Shockwave Ring + S12K Shotgun + Frag Grenades!
	game.start_action(true, "confidential")
	await frames(8)
	if is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.visible = false
	var reis = game.combat.boss_unit
	reis.position = Vector3(0.0, ay + 0.12, -124.5)
	game.player.position = Vector3(0.0, ay + 0.10, -110.0)
	game.combat.engage_camp(2, true)
	await frames(4)
	game.combat.spawn_reis_gramophone_wave(reis.position, 22.0, 0)
	for _st in 12:
		game.combat.update(0.025)
	game.combat.spawn_reis_frag_grenade(reis.position + Vector3(-0.8, 2.4, 0.0), Vector3(-3.8, ay, -116.5), 3.4, 0)
	game.combat.spawn_reis_frag_grenade(reis.position + Vector3(-0.8, 2.4, 0.0), Vector3(4.2, ay, -117.0), 3.4, 0)
	game.combat.fire_reis_shotgun_cone(reis.position + Vector3(0.4, 2.1, 0.5), Vector3(0.0, -0.05, 1.0), 7, 0)
	for _st2 in 8:
		game.combat.update(0.02)
	_look_at_pos(game, Vector3(0.0, ay + 3.6, -108.5), Vector3(0.0, ay + 2.2, -124.5))
	await _snap(out_dir, "v092_04_reis_symphony_shotgun.png")

	# 8. Warlord Reis Zero Dam Artillery Ultimate (streaking shells from Zero Dam crest + crimson courtyard laser beacons!)
	reis.trigger_ultimate_tiandi()
	for _ut in 16:
		game.combat.update(0.04)
	_look_at_pos(game, Vector3(0.0, ay + 4.8, -109.8), Vector3(0.0, ay + 11.5, -140.0))
	await _snap(out_dir, "v092_05_zero_dam_artillery.png")

	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))
	print("CAPTURE_V092_DONE")
	quit(0)
