extends SceneTree
var failures=0
var checks=0
func verify(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",message)
func _initialize():call_deferred("run")
func run():
	var words=JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/jiangsu-5a-2026.json"))
	verify(words is Dictionary and words.get("entries",[]).size()==175,"standalone PCK contains all 175 textbook records")
	print("PACKAGED_WORDPACK_SHA256 ",FileAccess.get_sha256("res://data/wordpacks/jiangsu-5a-2026.json"))
	var learning=JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	verify(learning is Dictionary and learning.has("math") and learning.has("poem"),"standalone PCK includes the new exploration question data")
	var sentences = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning/jiangsu-5a-sentences.json"))
	var cloze_count := 0
	if sentences is Dictionary and sentences.get("entries") is Array:
		for s in sentences.entries:
			cloze_count += s.get("cloze_targets", []).size()
	verify(sentences is Dictionary and sentences.get("entries", []).size() == 16 and cloze_count >= 15, "standalone PCK includes all 16 sourced sentence entries with 15+ verified Cloze targets")
	verify(ResourceLoader.exists("res://scripts/srs_scheduler.gd") and ResourceLoader.exists("res://scripts/learning_store.gd"), "standalone PCK includes SRS scheduler and learning store modules")
	verify(bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)), "exported project enables audio/general/text_to_speech for OS TTS fallback")
	var voice_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning/voice_manifest.json"))
	var voice_ok: bool = (voice_manifest is Dictionary and voice_manifest.get("entries") is Dictionary and voice_manifest.entries.size() >= 240)
	var missing_ogg: int = 0
	if voice_ok:
		for k in voice_manifest.entries.keys():
			var fname: String = str(voice_manifest.entries[k].get("file", ""))
			if fname == "" or not ResourceLoader.exists("res://assets/voice/" + fname):
				missing_ogg += 1
	verify(voice_ok and missing_ogg == 0, "standalone PCK includes complete offline voice manifest and all OGG clips (%d entries, %d missing)" % [voice_manifest.entries.size() if voice_ok else 0, missing_ogg])
	var sample_voice = load("res://assets/voice/" + str(voice_manifest.entries["dragon boat festival"].get("file", ""))) if (voice_ok and voice_manifest.entries.has("dragon boat festival")) else null
	verify(sample_voice is AudioStream, "standalone PCK decodes sample offline voice OGG as AudioStream")
	var loot_ui_cls = load("res://scripts/loot_ui.gd")
	var art_ids: PackedStringArray = loot_ui_cls.all_collectible_art_ids()
	var missing_col_mesh: int = 0
	var missing_col_icon: int = 0
	for aid in art_ids:
		if loot_ui_cls.get_collectible_mesh(aid) == null:
			missing_col_mesh += 1
		if loot_ui_cls.load_collectible_icon(aid) == null:
			missing_col_icon += 1
	verify(art_ids.size() == 32 and ResourceLoader.exists("res://assets/slice/v072_collectibles.glb") and missing_col_mesh == 0, "standalone PCK contains all 32 sculpted PBR collectible meshes in v072_collectibles.glb")
	verify(art_ids.size() == 32 and missing_col_icon == 0, "standalone PCK contains all 32 studio-rendered collectible 2D icons")
	for name in ["rifle","crate","rock_0","rock_1","rock_2","rock_3","rock_4","rock_5"]:
		verify(ResourceLoader.exists("res://assets/slice/"+name+".glb"),"packaged model "+name)
	for name in ["ground_color","ground_normal","tree_bark","tree_needles","tree_alpha"]:
		verify(ResourceLoader.exists("res://assets/slice/"+name+".jpg"),"packaged texture "+name)
	verify(FileAccess.file_exists("res://licenses/Slice-CC0-sources.txt"),"standalone PCK carries source and license notices")
	verify(not FileAccess.file_exists("res://tests/smoke.gd"),"development tests excluded from distribution")
	print("PACKAGED_RESOURCE_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
