extends SceneTree
## v0.9.6 Visual Verification Capture Suite (1280x720 GL Compatibility):
## 1. v096_01_login_yanshan_hd.png       — Gunmetal Command UI + Yanshan HD 3D Relief Map + 3D Beacons
## 2. v096_02_login_ahsarah_hd.png       — Gunmetal Command UI + Ahsarah HD Desert Map + Zero Dam 3D Beacons
## 3. v096_03_login_story_hd.png         — Gunmetal Command UI + Story Mode HD Vista + 3D Beacons
## 4. v096_04_lore_hub_fresh_locked.png  — Fresh Save Lore Codex Page 1: Shaoyu UNLOCKED + 4 Rangers LOCKED "?"
## 5. v096_05_lore_detail_locked_q.png   — Fresh Save Lore Codex Page 2: Locked Operative big "?" + Unlock Guide
## 6. v096_06_lore_hub_mixed_ahsarah.png — Mid-Campaign Lore Codex Page 1 (Ahsarah): Guard+Saeed UNLOCKED, Reis LOCKED "?"
## 7. v096_07_lore_detail_unlocked.png   — Mid-Campaign Lore Codex Page 2 (Shaoyu): Full Portrait + 4 Chapters!

const OUT_DIR := "res://../docs/media"

func _snap(name: String):
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = ProjectSettings.globalize_path(OUT_DIR).path_join(name)
	var err := img.save_png(path)
	print("CAPTURE_V096 ", name, " err=", err, " size=", img.get_width(), "x", img.get_height())

func _initialize():
	call_deferred("_run")

func _run():
	var main = load("res://main.tscn").instantiate()
	main.qa_mode = true
	root.add_child(main)
	for _i in 14:
		await process_frame

	# 1. Yanshan HD 3D War Map + 3D Beacons + Gunmetal Command UI
	main._select_nav_theater("yanshan")
	await _snap("v096_01_login_yanshan_hd.png")

	# 2. Ahsarah HD 3D Desert Map (unlock preview to inspect LIVE state)
	main.rules.unlock_map("ahsarah")
	main._select_nav_theater("ahsarah")
	await _snap("v096_02_login_ahsarah_hd.png")

	# 3. Story Mode HD Vista + 3D Beacons
	main._select_nav_theater("story")
	await _snap("v096_03_login_story_hd.png")

	# 4. Fresh-save Lore Codex Page 1 (Rangers: ONLY Shaoyu unlocked; 4 teammates show "?" mystery portrait!)
	main._select_nav_theater("yanshan")
	main.rules.profile.unlocked_maps = ["yanshan"]
	main.rules.profile.runs = 0
	main.rules.profile.extractions = 0
	main.rules.profile.reputation = 0
	main.rules.profile.lore_stats = {}
	main.rules.profile.lore_scenes = []
	main.rules.profile.achievements = []
	main.lore_codex.open("rangers")
	await _snap("v096_04_lore_hub_fresh_locked.png")

	# 5. Fresh-save Lore Codex Page 2 (Click locked Ranger 'tingfeng': big "?" silhouette + unlock guide!)
	main.lore_codex.open_character("tingfeng")
	await _snap("v096_05_lore_detail_locked_q.png")

	# 6. Mid-campaign Ahsarah faction Page 1 (Guard + Saeed UNLOCKED, Reis still LOCKED "?" side-by-side!)
	main.rules.unlock_map("ahsarah")
	main.rules.inc_lore_stat("ahsarah_runs", 2)
	main.rules.inc_lore_stat("camps_cleared_ahsarah", 2)
	main.rules.inc_lore_stat("saeed_defeats", 1)
	main.lore_codex.open("ahsarah")
	await _snap("v096_06_lore_hub_mixed_ahsarah.png")

	# 7. Unlocked Shaoyu Dedicated Dossier Page 2 (Gunmetal frame + portrait + progressive unlock bars!)
	main.rules.inc_lore_stat("shaoyu_runs", 2)
	main.rules.inc_lore_stat("shaoyu_skill_uses", 3)
	main.rules.mark_lore_scene("yanshan_base")
	main.rules.mark_lore_scene("prologue")
	main.rules.profile.extractions = 2
	main.rules.profile.reputation = 180
	main.rules.profile.achievements = ["first_extract", "streak_5"]
	main.lore_codex.open_character("shaoyu")
	await _snap("v096_07_lore_detail_unlocked.png")

	print("ALL 7 v0.9.6 VISUAL CAPTURES DONE")
	quit(0)
