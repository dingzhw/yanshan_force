extends SceneTree
var failures = 0
var checks = 0

func verify(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", message)

func _initialize():
	call_deferred("run")

func run():
	var words = JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/jiangsu-5a-2026.json"))
	verify(words is Dictionary and words.get("entries", []).size() == 175, "standalone PCK contains all 175 textbook records")
	print("PACKAGED_WORDPACK_SHA256 ", FileAccess.get_sha256("res://data/wordpacks/jiangsu-5a-2026.json"))
	var learning = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	verify(learning is Dictionary and learning.has("math") and learning.has("poem"), "standalone PCK includes exploration question data")
	var sentences = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning/jiangsu-5a-sentences.json"))
	var cloze_count := 0
	if sentences is Dictionary and sentences.get("entries") is Array:
		for s in sentences.entries:
			cloze_count += s.get("cloze_targets", []).size()
	verify(sentences is Dictionary and sentences.get("entries", []).size() == 16 and cloze_count >= 15, "standalone PCK includes all 16 sourced sentence entries with 15+ verified Cloze targets")
	verify(ResourceLoader.exists("res://scripts/srs_scheduler.gd") and ResourceLoader.exists("res://scripts/learning_store.gd"), "standalone PCK includes SRS scheduler and learning store modules")
	verify(ResourceLoader.exists("res://scenes/prologue_chapter.tscn") and ResourceLoader.exists("res://scripts/prologue.gd"), "standalone PCK includes editable Prologue scene and script")
	var pro_scene = load("res://scenes/prologue_chapter.tscn")
	verify(pro_scene is PackedScene, "standalone PCK loads prologue_chapter.tscn as valid PackedScene")
	verify(bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)), "exported project enables audio/general/text_to_speech for OS TTS fallback")

	# Full 279/279 offline voice OGG existence AND real AudioStream decode verification!
	var voice_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning/voice_manifest.json"))
	var voice_ok: bool = (voice_manifest is Dictionary and voice_manifest.get("entries") is Dictionary and voice_manifest.entries.size() >= 275)
	var missing_ogg: int = 0
	var decode_failed_ogg: int = 0
	var decoded_ogg_count: int = 0
	if voice_ok:
		for k in voice_manifest.entries.keys():
			var fname: String = str(voice_manifest.entries[k].get("file", ""))
			var vpath := "res://assets/voice/" + fname
			if fname == "" or not ResourceLoader.exists(vpath):
				missing_ogg += 1
				continue
			var stream = load(vpath)
			if stream is AudioStream and stream.get_length() > 0.05:
				decoded_ogg_count += 1
			else:
				decode_failed_ogg += 1
	verify(voice_ok and missing_ogg == 0 and decode_failed_ogg == 0, "standalone PCK decodes ALL offline voice OGG streams cleanly (%d/%d decoded, %d missing, %d decode_err)" % [
		decoded_ogg_count, voice_manifest.entries.size() if voice_ok else 0, missing_ogg, decode_failed_ogg
	])

	# Full 34/34 SFX WAV existence AND AudioStream decode verification! (Godot PCK lists *.wav.import remaps)
	var sfx_dir := DirAccess.open("res://assets/sfx")
	var sfx_seen := {}
	var sfx_total := 0
	var sfx_decoded := 0
	if sfx_dir != null:
		for raw_f in sfx_dir.get_files():
			var sf: String = raw_f.trim_suffix(".import")
			if sf.ends_with(".wav") and not sfx_seen.has(sf):
				sfx_seen[sf] = true
				sfx_total += 1
				var st = load("res://assets/sfx/" + sf)
				if st is AudioStream and st.get_length() > 0.01:
					sfx_decoded += 1
	var req_sfx_ok := true
	for sfx_n in ["shot_rifle", "shot_suppressed", "reload_mag_out", "reload_mag_in", "reload_bolt", "shell_clink", "achievement_unlock", "warden_sonar", "warden_shield_deflect", "boss_skyfall", "skill_slam"]:
		if not ResourceLoader.exists("res://assets/sfx/" + sfx_n + ".wav"):
			req_sfx_ok = false
	verify(req_sfx_ok and sfx_total >= 36 and sfx_decoded == sfx_total, "standalone PCK decodes ALL packaged SFX WAV streams cleanly (%d/%d decoded)" % [sfx_decoded, sfx_total])

	var loot_ui_cls = load("res://scripts/loot_ui.gd")
	var art_ids: PackedStringArray = loot_ui_cls.all_collectible_art_ids()
	var missing_col_mesh: int = 0
	var missing_col_icon: int = 0
	for aid in art_ids:
		if loot_ui_cls.get_collectible_mesh(aid) == null:
			missing_col_mesh += 1
		if loot_ui_cls.load_collectible_icon(aid) == null:
			missing_col_icon += 1
	verify(art_ids.size() == 64 and ResourceLoader.exists("res://assets/slice/v072_collectibles.glb") and missing_col_mesh == 0, "standalone PCK contains all 64 sculpted PBR collectible meshes in v072_collectibles.glb")
	verify(art_ids.size() == 64 and missing_col_icon == 0, "standalone PCK contains all 64 studio-rendered collectible 2D icons")
	for name in ["rifle", "crate", "rock_0", "rock_1", "rock_2", "rock_3", "rock_4", "rock_5"]:
		verify(ResourceLoader.exists("res://assets/slice/" + name + ".glb"), "packaged model " + name)
	for name in ["ground_color", "ground_normal", "tree_bark", "tree_needles", "tree_alpha"]:
		verify(ResourceLoader.exists("res://assets/slice/" + name + ".jpg"), "packaged texture " + name)
	verify(ResourceLoader.exists("res://assets/slice/v082_bosses.glb") and ResourceLoader.exists("res://scripts/cave_warden.gd") and ResourceLoader.exists("res://scripts/achievements.gd") and ResourceLoader.exists("res://scripts/rangers.gd") and ResourceLoader.exists("res://scripts/loot_container_ui.gd"), "standalone PCK includes v0.8.4 articulated boss GLB, Cave Warden, Achievements, Rangers & LootContainerUI modules")
	var boss_glb_packed = load("res://assets/slice/v082_bosses.glb")
	var boss_rig_ok := false
	if boss_glb_packed is PackedScene:
		var bi: Node = boss_glb_packed.instantiate()
		boss_rig_ok = (bi.find_child("warden_body", true, false) != null and bi.find_child("arm_left_pivot", true, false) != null and bi.find_child("arm_right_pivot", true, false) != null and bi.find_child("head_crest", true, false) != null and bi.find_child("skyfall_overlord", true, false) != null)
		bi.free()
	verify(boss_rig_ok, "standalone PCK v082_bosses.glb contains articulated Cave Warden parts (warden_body/arm_left_pivot/arm_right_pivot/head_crest) & skyfall_overlord")
	var lm_ok := false
	if ResourceLoader.exists("res://assets/slice/v085_landmarks.glb"):
		var lm_packed = load("res://assets/slice/v085_landmarks.glb")
		if lm_packed is PackedScene:
			var lmi: Node = lm_packed.instantiate()
			lm_ok = (lmi.find_child("bridge_multi_arch", true, false) != null and lmi.find_child("tea_hill_pavilion", true, false) != null and lmi.find_child("cliff_stele", true, false) != null and lmi.find_child("arena_dragon_pillar", true, false) != null and lmi.find_child("arena_altar_rim", true, false) != null)
			lmi.free()
	verify(lm_ok, "standalone PCK v085_landmarks.glb contains all 5 Great Yanshan landmarks (bridge_multi_arch/tea_hill_pavilion/cliff_stele/arena_dragon_pillar/arena_altar_rim)")
	verify(FileAccess.file_exists("res://licenses/Slice-CC0-sources.txt"), "standalone PCK carries source and license notices")
	verify(not FileAccess.file_exists("res://tests/smoke.gd"), "development tests excluded from distribution")
	print("PACKAGED_RESOURCE_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
