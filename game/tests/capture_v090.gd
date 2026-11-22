extends SceneTree
## v0.9.0 Visual Capture & Hardware Inspection Suite (8 crisp 1280x720 GL Compatibility renders):
## 1. v090_01_yanxia_dimensional_rift.png    — Yanxia Ancient Cave Dimensional Rift Wall ("次元石壁") behind skylight
## 2. v090_02_menu_map_selector.png          — Camp Menu Dual-Theater selector & Settings Quick-Unlock drawer
## 3. v090_03_ahsarah_oasis_dam_vista.png    — South Oasis Spawn vista across palms, jeep & Brakkesh gate to colossal Zero Dam
## 4. v090_04_ahsarah_fortress_saeed.png     — Normal Mode Boss「赤枭·赛伊德」in Administrative Fortress courtyard
## 5. v090_05_ahsarah_confidential_reis.png  — Confidential Mode Boss「阿萨拉军阀·雷斯」with gramophone & 5 word shields
## 6. v090_06_ahsarah_cement_plant.png       — West Zero Dam Cement Silos & Ahsarah Guard squad
## 7. v090_07_ahsarah_bazaar_substation.png  — East Brakkesh Sandstone Arched Bazaar & Haavk white-cyan troopers
## 8. v090_08_ahsarah_collectibles_showcase.png — 3D Display Stand showcasing all 6 Ahsarah flagship collectibles

var game
var out_dir: String = ""

func _initialize():
	call_deferred("run")

func frames(n: int):
	for _i in n:
		await process_frame

func snap(filename: String):
	await frames(5)
	var img: Image = root.get_texture().get_image()
	var full: String = out_dir.path_join(filename)
	var err := img.save_png(full)
	print("CAPTURE ", filename, " err=", err, " size=", img.get_width(), "x", img.get_height())

func look_from(pos: Vector3, target: Vector3, hide_weapon: bool = true):
	var cam: Camera3D = game.player.camera
	game.player.position = pos - Vector3(0.0, 1.65, 0.0)
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	if is_instance_valid(game.player.weapon_root):
		game.player.weapon_root.visible = not hide_weapon

func run():
	out_dir = ProjectSettings.globalize_path("res://../docs/media")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var tmp_profile := "user://capture_v090_profile.json"
	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))

	game = load("res://main.tscn").instantiate()
	game.profile_path_override = tmp_profile
	root.add_child(game)
	await frames(6)

	# 1) Yanxia Ancient Cave Dimensional Rift Wall ("次元石壁") behind skylight
	game.start_action(true, "confidential")
	await frames(4)
	game.on_confidential_cave_warden_defeated()
	if is_instance_valid(game.cave_warden):
		game.cave_warden.set_map_enabled(false)
	var cave_c: Vector3 = game.Layout.YANXIA_CAVE_CENTER
	var fy: float = float(game.Layout.CAVE_FLOOR_Y)
	look_from(Vector3(cave_c.x + 1.0, fy + 1.85, cave_c.z - 0.8), Vector3(cave_c.x - 0.95, fy + 1.55, cave_c.z - 4.92), true)
	await snap("v090_01_yanxia_dimensional_rift.png")

	# 2) Camp Menu Dual-Theater Selector + Settings Quick-Unlock drawer
	game.unlock_ahsarah_map("dimensional_rift")
	game._end_run(false, "预览")
	await frames(3)
	game.switch_map("ahsarah")
	await frames(5)
	game.menu.show()
	game.hud.hide()
	game.settings_panel.show()
	game._sync_settings_ui()
	game._refresh_menu()
	await snap("v090_02_menu_map_selector.png")
	game.settings_panel.hide()

	# 3) South Oasis Spawn Vista -> Palms, Jeep, Sandstone Gatehouse & Colossal Zero Dam!
	game.start_action(true, "normal")
	await frames(5)
	look_from(Vector3(-4.0, 4.6, 23.0), Vector3(0.0, 9.0, -110.0), true)
	await snap("v090_03_ahsarah_oasis_dam_vista.png")

	# 4) Administrative Fortress Courtyard -> Normal Boss「赤枭·赛伊德」(Captain Saeed)
	var saeed = game.combat.boss_unit
	if is_instance_valid(saeed):
		var sp: Vector3 = saeed.global_position
		saeed.look_at(sp + Vector3(0.0, 0.0, 12.0), Vector3.UP)
		saeed.rotation.y += PI
		look_from(sp + Vector3(2.8, 2.35, 8.2), sp + Vector3(0.0, 1.75, 0.0), false)
	await snap("v090_04_ahsarah_fortress_saeed.png")

	# 6) West Zero Dam Cement Silos & Ahsarah Guard squad
	var cp_pos: Vector3 = game.AhsarahLayout.on_ground(game.AhsarahLayout.CEMENT_PLANT)
	look_from(cp_pos + Vector3(20.0, 6.2, 22.0), cp_pos + Vector3(-5.0, 4.8, -2.0), true)
	await snap("v090_06_ahsarah_cement_plant.png")

	# 7) East Brakkesh Sandstone Arched Bazaar & Haavk Substation
	var bz_pos: Vector3 = game.AhsarahLayout.on_ground(game.AhsarahLayout.BAZAAR_ARCH)
	look_from(bz_pos + Vector3(-16.0, 4.8, 18.0), bz_pos + Vector3(6.0, 3.0, -14.0), true)
	await snap("v090_07_ahsarah_bazaar_substation.png")

	# 5) Confidential Mode -> Warlord Reis ('阿萨拉军阀·雷斯') with Gramophone & 5 heavy shields
	game.start_action(true, "confidential")
	await frames(5)
	var reis = game.combat.boss_unit
	if is_instance_valid(reis):
		reis.trigger_skyfall()
		await frames(4)
		var rp: Vector3 = reis.global_position
		look_from(rp + Vector3(-3.2, 2.85, 9.6), rp + Vector3(0.0, 2.15, 0.0), false)
	await snap("v090_05_ahsarah_confidential_reis.png")

	# 8) Camp 3D Display Stand showcasing all 6 brand-new Ahsarah Flagship Collectibles!
	game.rules.profile.owned.append("display_expand")
	game.rules.profile.display_stand = [
		"非洲之心", "曼德尔加密砖", "阿萨拉王室金杯", "军阀古董留声机",
		"赤枭青铜猎徽", "巴克什鎏金油灯"
	]
	game.refresh_camp_display_stand()
	await frames(3)
	var st_p: Vector3 = game.camp_display_stand.global_position
	var st_fwd: Vector3 = game.camp_display_stand.global_transform.basis.z.normalized()
	look_from(st_p + st_fwd * 3.1 + Vector3(0.0, 1.75, 0.0), st_p + Vector3(0.0, 1.32, 0.0), true)
	await snap("v090_08_ahsarah_collectibles_showcase.png")

	if FileAccess.file_exists(tmp_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))
	print("CAPTURE_V090_DONE")
	quit(0)
