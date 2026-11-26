extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func verify(ok: bool, text: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", text)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action()
	await physics_frame
	game.interact()
	verify(game.active_station == 0, "learning begins at camp terminal")
	var missed_id = game.question.id
	game.resolve_answer((game.answer_index + 1) % 4)
	verify(game.wrong_words.size() == 1 and game.feedback_label.text.contains(game.question.english), "wrong shot presents the correct English answer")
	verify(game.rules.profile.mastery.has(missed_id) and int(game.rules.profile.mastery[missed_id].wrong) == 1, "mastery profile records wrong attempts per word")
	for i in 5:
		game._next_question()
		game.resolve_answer(game.answer_index)
	game._next_question()
	verify(game.question.id == game.wrong_words[0].id, "missed word revisits after six answered questions")

	# Smart distractor validation: phrases pull phrase distractors rather than obvious single words
	var phrase_entry = null
	for w in game.words:
		if " " in w.english and not w.proper_name:
			phrase_entry = w
			break
	var picked = game._pick_smart_distractors(phrase_entry)
	var phrase_count = 0
	for item in picked:
		if " " in item.english or item.get("kind", "") == "phrase":
			phrase_count += 1
	verify(picked.size() == 4 and phrase_count >= 3, "smart distractors match multi-word phrases with phrase distractors")

	var fit = true
	var whole_words_fit = true
	for word in game.words:
		game.choices = [word, word, word, word]
		game._sync_question()
		var label = game.targets[0]
		if game.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, 355, label.font_size).y > 146:
			fit = false
			print("OVERFLOW ", word.english)
		for part in label.text.split(" "):
			if game.font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x > 300:
				whole_words_fit = false
	verify(fit, "all 175 entries and long phrases fit their word boards")
	verify(whole_words_fit, "all 175 entries keep individual words within a single line")
	game.wrong_words = game.words.duplicate()
	game._end_run(false)
	game._show_review()
	verify(game.review_overlay.visible and game.review_text.text.contains(game.words[0].english) and game.review_text.text.contains(game.words[-1].english), "scrollable review contains every missed entry")
	verify(game.review_button.visible, "result exposes the full review button")
	game.start_action()
	verify(game.wrong_words.is_empty() and not game.review_overlay.visible and not game.review_button.visible, "new run resets only this run's review")

	# Settle a failed action through its normal exit and reload only the data.
	game.profile_path_override = "user://qa-v067-learning.json"
	game.rules.add_loot("unbanked", 10, 1)
	await physics_frame
	game.interact()
	var failed_term: Dictionary = game.question
	game.resolve_answer((game.answer_index + 1) % game.choices.size())
	game._end_run(false, "QA failed action")
	var restored = load("res://scripts/main.gd").new()
	restored.profile_path_override = game.profile_path_override
	restored._load_profile()
	verify(restored.rules.profile.review_due.has(failed_term.id) and restored.rules.profile.mastery.has(failed_term.id), "failed action persists the question and its retest queue across restart")
	verify(game.rules.bag.is_empty() and restored.rules.profile.warehouse.is_empty(), "failed action does not bank loot")
	verify(restored.rules.profile.last_run.has("wall_clock_seconds") and not restored.rules.profile.last_run.extracted, "failed settlement saves real elapsed time")
	restored.free()

	var sentence: Dictionary = game.sentences[0]
	var learning = game.rules.learning
	var word_count: int = learning.mastered_count(game.words)
	learning.record_spelling(sentence.id, "independent")
	learning.record_spelling(sentence.id, "independent")
	verify(game.words.size() == 175 and game.sentences.size() == 16 and learning.mastered_count(game.words) == word_count and learning.mastered_count(game.sentences) == 1, "separate stable IDs keep sentence mastery out of the 175 words")
	verify(game.rules.profile.mastery[sentence.id].seen == 2, "independent spellings advance seen as well as correct")

	var low_signal_term: Dictionary = game.words[-1]
	game.rules.profile.mastery.erase(low_signal_term.id)
	learning.record_recognition(low_signal_term.id, true, 1, false)
	verify(game.rules.profile.mastery[low_signal_term.id].last_choice_count == 1 and not game.rules.profile.mastery[low_signal_term.id].has("independent_correct"), "single-option hit carries no independent mastery credit")

	var cipher = game.cipher_terminal
	cipher.open_retest([failed_term])
	verify(cipher.busy and not cipher.hint_button.visible and not cipher.speak_button.visible and cipher.mask_label.text.is_empty(), "retest starts without spelling or pronunciation hints")
	cipher.submit_text(str(failed_term.english))
	verify(not game.rules.profile.review_due.has(failed_term.id) and cipher.unlocked, "first correct retest clears that pending item")
	cipher.close()
	var persisted = JSON.parse_string(FileAccess.get_file_as_string(game.profile_path_override))
	verify(not persisted.review_due.has(failed_term.id), "retest outcome survives reloading the file")

	game.start_action(true, "normal")
	cipher.open_for_supply(game.pickup_nodes[0])
	var helped_id: String = cipher.target_word.id
	var prior: int = int(game.rules.profile.mastery.get(helped_id, {}).get("independent_correct", 0))
	cipher.hint_button.pressed.emit()
	cipher.submit_text(str(cipher.target_word.english))
	verify(cipher.unlocked and not cipher.perfect_crack and game.rules.profile.mastery[helped_id].last_outcome == "hinted", "a hint still allows looting without independent credit or perfect bonus")
	verify(int(game.rules.profile.mastery[helped_id].get("independent_correct", 0)) == prior and game.rules.profile.review_due.has(helped_id), "hinted spelling remains queued for independent retest")
	cipher.close()
	if game.loot_container_ui.busy:
		game.loot_container_ui.close()
	cipher.open_for_supply(game.pickup_nodes[1])
	var copied_id: String = cipher.target_word.id
	var copied_prior: int = int(game.rules.profile.mastery.get(copied_id, {}).get("independent_correct", 0))
	cipher.submit_text("__wrong__")
	cipher.submit_text("__wrong_again__")
	cipher.submit_text(str(cipher.target_word.english))
	verify(cipher.unlocked and not cipher.perfect_crack and game.rules.profile.mastery[copied_id].last_outcome == "copied_scaffold", "copying the revealed answer can still open the supply box")
	verify(int(game.rules.profile.mastery[copied_id].get("independent_correct", 0)) == copied_prior and game.rules.profile.review_due.has(copied_id), "copying the answer is distinct from spelling mastery")
	cipher.close()
	if game.loot_container_ui.busy:
		game.loot_container_ui.close()

	# v0.7.0 Stage 1 & 2: Deterministic cross-day SRS progression, anti-false-mastery, encounters vs seen, and verified Cloze targets!
	var Srs = load("res://scripts/srs_scheduler.gd")
	var srs_id := "js5a2026-061" # warm up (Unit 4, p.53)
	var day0 := 1763500000
	game.rules.profile.mastery.erase(srs_id)
	game.rules.profile.review_due.erase(srs_id)
	learning.record_recognition(srs_id, true, 4, false, day0)
	var e0: Dictionary = game.rules.profile.mastery[srs_id]
	verify(int(e0.srs_stage) == 1 and int(e0.next_due_ts) == day0 + Srs.DAY_SECONDS, "first independent hit advances SRS to Stage 1 (+1d)")
	verify(not learning.is_due(srs_id, day0 + 3600) and learning.is_due(srs_id, day0 + Srs.DAY_SECONDS), "SRS item is not due mid-day and becomes due after 1 day")
	learning.record_recognition(srs_id, true, 4, false, day0 + 3600)
	verify(int(game.rules.profile.mastery[srs_id].srs_stage) == 1, "same-session repeat does not artificially inflate SRS stage past 1")
	var day1: int = day0 + Srs.DAY_SECONDS
	learning.record_recognition(srs_id, true, 4, false, day1)
	verify(int(game.rules.profile.mastery[srs_id].srs_stage) == 2 and int(game.rules.profile.mastery[srs_id].next_due_ts) == day1 + 3 * Srs.DAY_SECONDS, "next-day independent recall advances SRS to Stage 2 (+3d)")
	var day4: int = day1 + 3 * Srs.DAY_SECONDS
	learning.record_spelling(srs_id, "independent", true, day4)
	verify(int(game.rules.profile.mastery[srs_id].srs_stage) == 3 and int(game.rules.profile.mastery[srs_id].next_due_ts) == day4 + 7 * Srs.DAY_SECONDS, "3-day independent retest advances SRS to Stage 3 (+7d)")
	var day11: int = day4 + 7 * Srs.DAY_SECONDS
	learning.record_spelling(srs_id, "independent", true, day11)
	verify(int(game.rules.profile.mastery[srs_id].srs_stage) == 4 and int(game.rules.profile.mastery[srs_id].next_due_ts) == day11 + 15 * Srs.DAY_SECONDS, "7-day independent retest advances SRS to Stage 4 (+15d)")
	learning.record_recognition(srs_id, false, 4, false, day11 + 100)
	verify(int(game.rules.profile.mastery[srs_id].srs_stage) == 0 and learning.is_due(srs_id, day11 + 100), "a mistake resets SRS stage to 0 and immediately marks word due")

	# Anti-false-mastery guard: 3 wrongs + 2 same-day independent hits (stage 1) must NOT count as mastered; cross-interval stage 2 DOES!
	var hard_id := "js5a2026-070"
	game.rules.profile.mastery.erase(hard_id)
	game.rules.profile.review_due.erase(hard_id)
	for _w in 3:
		learning.record_recognition(hard_id, false, 4, false, day0)
	learning.record_recognition(hard_id, true, 4, false, day0 + 60)
	learning.record_recognition(hard_id, true, 4, false, day0 + 120)
	verify(not learning.is_mastered(hard_id), "high-wrong word with only same-day hits is NOT falsely marked mastered")
	learning.record_recognition(hard_id, true, 4, false, day0 + Srs.DAY_SECONDS + 120)
	verify(learning.is_mastered(hard_id) and int(game.rules.profile.mastery[hard_id].srs_stage) == 2, "passing across a real 1-day interval earns mastery even after earlier struggles")

	# Per-crate encounter count vs event seen count
	var enc_id := "js5a2026-023"
	game.rules.profile.mastery.erase(enc_id)
	learning.record_spelling(enc_id, "incorrect", false, day0, true)
	learning.record_spelling(enc_id, "hinted", false, day0, false)
	verify(int(game.rules.profile.mastery[enc_id].seen) == 2 and int(game.rules.profile.mastery[enc_id].encounters) == 1, "single crate wrong-then-hinted logs 2 seen events and 1 encounter")

	# Deterministic SRS queue puts due words at the tail (first popped by pop_back)
	var queue_check: Array = Srs.build_session_queue(game.rules.profile, game.words, day11 + 100)
	verify(not queue_check.is_empty() and learning.is_due(str(queue_check[-1].id), day11 + 100), "SRS session queue prioritizes due/mistake words at pop_back tail")

	# Verified Cloze index integrity across all 16 audited sentences & 175-word pack
	var word_ids := {}
	for w in game.words:
		word_ids[str(w.id)] = w
	var cloze_valid := true
	var cloze_total := 0
	for s in game.sentences:
		for t in s.get("cloze_targets", []):
			cloze_total += 1
			var wid := str(t.get("word_id", ""))
			var span := str(t.get("span", ""))
			if not word_ids.has(wid) or str(s.english).findn(span) < 0:
				cloze_valid = false
	var warm_cloze: Dictionary = game.cloze_for_word("js5a2026-061")
	verify(cloze_valid and cloze_total >= 15 and warm_cloze.get("cloze_text", "") == "We should ____.", "all 15+ Cloze targets match valid 175-pack IDs and verbatim textbook spans")

	# Legacy profile non-destructive migration check (v0.6.7 -> v0.7.0 preserves old file bytes!)
	var legacy_path := "user://qa-v067-legacy-src.json"
	var legacy_payload := JSON.stringify({"coins": 88, "xp": 240, "mastery": {"js5a2026-003": {"seen": 3, "correct": 2, "independent_correct": 2, "wrong": 0}}, "review_due": {"js5a2026-040": "incorrect"}}, "\t")
	var lf := FileAccess.open(legacy_path, FileAccess.WRITE)
	lf.store_string(legacy_payload)
	lf.close()
	var legacy_hash_before := FileAccess.get_sha256(legacy_path)
	var migrated = load("res://scripts/main.gd").new()
	migrated.profile_path_override = legacy_path
	migrated._load_profile()
	migrated.profile_path_override = "user://qa-v070-migrated-dst.json"
	var mig_saved: bool = migrated._save()
	var mig_reload = load("res://scripts/main.gd").new()
	mig_reload.profile_path_override = "user://qa-v070-migrated-dst.json"
	mig_reload._load_profile()
	verify(mig_saved and FileAccess.get_sha256(legacy_path) == legacy_hash_before and mig_reload.rules.profile.coins == 88 and mig_reload.rules.profile.review_due.has("js5a2026-040"), "v0.6.7 profile migrates forward cleanly while keeping source file SHA-256 unchanged")
	migrated.free()
	mig_reload.free()

	# v0.7.1 Offline US Neural Voice Pack + Export TTS Fallback Verification
	verify(bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)), "project.godot explicitly enables audio/general/text_to_speech for exported builds")
	var missing_word_voice := 0
	for w in game.words:
		if not game.voice_manifest.has(game.normalize_voice_key(str(w.english))):
			missing_word_voice += 1
	var missing_sent_voice := 0
	for s in game.sentences:
		if not game.voice_manifest.has(game.normalize_voice_key(str(s.english))):
			missing_sent_voice += 1
	var missing_loot_voice := 0
	for r_tier in game.Rules.LOOT_TABLE.keys():
		for item in game.Rules.LOOT_TABLE[r_tier]:
			if not game.voice_manifest.has(game.normalize_voice_key(str(item.get("en", "")))):
				missing_loot_voice += 1
	verify(game.voice_manifest.size() >= 325 and missing_word_voice == 0 and missing_sent_voice == 0 and missing_loot_voice == 0, "v0.8.6 offline voice manifest covers 100%% of 175 words, 16 sentences, and all 108 loot names (%d entries)" % game.voice_manifest.size())
	var prev_tts := str(game.tts_voice_id)
	game.tts_voice_id = ""
	var has_no_os_tts: bool = game.has_english_voice("Dragon Boat Festival") and game.has_english_voice("put ... in order") and game.has_english_voice("Children’s Day")
	var spoke_phrase: bool = game.speak_english("put ... in order")
	var stream_ok: bool = game.load_voice_stream("Dragon Boat Festival") is AudioStream
	verify(has_no_os_tts and spoke_phrase and game.last_voice_backend == "ogg" and stream_ok, "offline OGG voice works cleanly with zero OS English TTS voices installed")
	game.tts_voice_id = prev_tts

	# v0.8.2 V81-12: Mandatory Daily Review Gate before deployment (blocks menu deploy when due words exist, unlocks once cleared!)
	game._end_run(false)
	game.rules.profile.review_due.clear()
	game.rules.profile.mastery.clear()
	var gate_word: Dictionary = game.words[2]
	game.rules.profile.review_due[str(gate_word.id)] = "incorrect"
	game._refresh_progress()
	var blocked_deploy: bool = not game.try_menu_deploy(true, "normal")
	var opened_retest: bool = game.cipher_terminal.busy and game.cipher_terminal.mode == "retest"
	verify(game.daily_review_required() and blocked_deploy and opened_retest and game.rules.phase != "active", "v0.8.2 V81-12: pending daily review blocks menu deployment and opens mandatory retest terminal")
	game.cipher_terminal.submit_text(str(gate_word.english))
	game.cipher_terminal.close()
	var unlocked_deploy: bool = game.try_menu_deploy(true, "normal")
	verify(not game.daily_review_required() and unlocked_deploy and game.rules.phase == "active", "v0.8.2 V81-12: completing all daily review items immediately unlocks menu deployment")
	game._end_run(false)

	# v0.8.2_dev1 C3: Complete 6-case Strict Daily Review Matrix & Anti-Inflation Guard!
	game.rules.set_setting("strict_daily_review", true)
	game.rules.profile.review_due.clear()
	game.rules.profile.mastery.clear()
	var u1_word: Dictionary = game.words[0] # Unit 1 word
	for wc in game.words:
		if int(wc.get("unit", 0)) == 1:
			u1_word = wc
			break
	var u1_id: String = str(u1_word.id)
	game.rules.profile.review_due[u1_id] = "incorrect"
	game.unit_picker.selected = 2 # Switch to Unit 2 + exclude extra!
	game.include_extra.button_pressed = false
	game._refresh_progress()
	var blk_norm: bool = not game.try_menu_deploy(true, "normal")
	game.cipher_terminal.close()
	var blk_conf: bool = not game.try_menu_deploy(true, "confidential")
	game.cipher_terminal.close()
	var blk_prac: bool = not game.try_menu_deploy(false, "normal")
	verify(blk_norm and blk_conf and blk_prac and game.daily_review_required(), "v0.8.2_dev1 C3: strict daily review blocks all 3 modes even after switching to another unit")
	# Wrong answer in retest reveals answer, re-queues word, and voluntary close preserves pending due!
	game.cipher_terminal.submit_text("__totally_wrong__")
	verify(game.rules.profile.review_due.has(u1_id) and game.rules.learning.was_recently_revealed(u1_id), "v0.8.2_dev1 C3: wrong retest answer reveals answer, preserves review_due & marks recently revealed")
	game.cipher_terminal.close()
	verify(game.rules.profile.review_due.has(u1_id) and game.daily_review_required(), "v0.8.2_dev1 C3: voluntary exit from retest keeps unfinished due word locked")
	# Re-entering immediately and typing the just-shown answer records practiced_completion (NOT independent_correct, NOT stage 1!)
	game._open_retest()
	game.cipher_terminal.submit_text(str(u1_word.english))
	game.cipher_terminal.close()
	var m_u1: Dictionary = game.rules.profile.mastery.get(u1_id, {})
	verify(
		str(m_u1.get("last_outcome", "")) == "practiced_completion" and int(m_u1.get("independent_correct", 0)) == 0 and int(m_u1.get("srs_stage", 0)) == 0 and not game.rules.profile.review_due.has(u1_id),
		"v0.8.2_dev1 C3: re-entering after answer reveal logs practiced_completion without inflating independent_correct or tomorrow SRS"
	)
	# Continuing the exact same active run while paused is NOT blocked by newly recorded due words
	game.unit_picker.selected = 0
	game.include_extra.button_pressed = true
	var dep_ok: bool = game.try_menu_deploy(true, "normal")
	game.rules.profile.review_due[u1_id] = "incorrect"
	game.paused = true
	var resume_ok: bool = game.try_menu_deploy(true, "normal")
	verify(dep_ok and resume_ok and game.rules.phase == "active", "v0.8.2_dev1 C3: resuming the same paused active run is never falsely blocked")
	game._end_run(false)

	# v0.8.2_dev1 C7: Save Lifecycle Matrix (Schema v2 -> v3 backup, unknown-field preservation & visible save failure warning!)
	var mig_path := "user://qa-v082dev1-lifecycle.json"
	var bak_path := mig_path + ".pre-v3.bak"
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
	var legacy_v2 := {
		"schema_version": 2,
		"coins": 333,
		"achievements": ["boar_1"],
		"unlocked_charms": ["charm_roast"],
		"equipped_charm": "charm_roast",
		"future_custom_tag": "preserve_me_v9"
	}
	var legacy_file := FileAccess.open(mig_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_v2, "\t"))
	legacy_file.close()
	game.profile_path_override = mig_path
	game._load_profile()
	var backup_created: bool = FileAccess.file_exists(bak_path)
	var saved_v3: bool = game._save()
	var raw_v3 = JSON.parse_string(FileAccess.get_file_as_string(mig_path))
	verify(
		backup_created and saved_v3 and raw_v3 is Dictionary and int(raw_v3.get("schema_version", 0)) == 3 and str(raw_v3.get("future_custom_tag", "")) == "preserve_me_v9" and "boar_1" in raw_v3.get("achievements", []),
		"v0.8.2_dev1 C7: legacy v2->v3 upgrade creates pre-upgrade backup, upgrades schema cleanly & preserves unknown future fields"
	)
	game.start_action(true, "normal")
	game.force_save_fail_for_test = true
	game._end_run(false, "存档故障检测")
	verify(game.menu_summary.text.contains("存档写入失败"), "v0.8.2_dev1 C7: save failure displays prominent warning directly in settlement summary")
	game.force_save_fail_for_test = false

	# v0.8.2_dev2 D2-3: Continuous Retest typing keeps focus & editing active after pressing Enter!
	game.rules.profile.review_due.clear()
	var w_a: Dictionary = game.words[0]
	var w_b: Dictionary = game.words[1]
	game.rules.profile.review_due[str(w_a.id)] = "incorrect"
	game.rules.profile.review_due[str(w_b.id)] = "incorrect"
	game._open_retest()
	await process_frame
	var first_t: String = str(game.cipher_terminal.target_word.english)
	game.cipher_terminal.submit_text(first_t)
	await process_frame
	verify(
		game.cipher_terminal.busy and game.cipher_terminal.stage_index == 1 and game.cipher_terminal.input_box.keep_editing_on_text_submit and game.cipher_terminal.input_box.editable and game.cipher_terminal.input_box.text == "",
		"v0.8.2_dev2 D2-3: retest input keeps editing active and clears cleanly onto next word after Enter"
	)
	game.cipher_terminal.close()

	# v0.9.9.6_dev2: 4-Path Recognition Audio Matrix (Audiovisual Default / Silent Mode / Manual [X] in Silent / Muted) + Migration!
	var test_w: Dictionary = game.words[5]
	var tid: String = str(test_w.id)
	game.rules.profile.mastery.erase(tid)
	game.rules.profile.review_due.erase(tid)
	game.rules.profile.learning_stats.clear()
	game.question = test_w
	game.listening_mode = false

	# Case 1: Opt-out silent reading mode (auto_speak_on_switch = false, voice_volume = 1.0, no [X]) -> silent pre-answer -> pure recognition!
	game.rules.set_setting("auto_speak_on_switch", false)
	game.rules.set_setting("voice_volume", 1.0)
	game.clear_question_help()
	var spoke_c1: bool = game.trigger_question_audio(true)
	learning.record_recognition(tid, true, 4, game.question_help_used, day0, "combat_word", game.recognition_modality())
	var m_c1: Dictionary = game.rules.profile.mastery.get(tid, {})
	verify(
		not spoke_c1 and not game.question_help_used and game.recognition_modality() == "recognition" and int(m_c1.get("independent_correct", 0)) == 1 and int(game.rules.profile.learning_stats.get("mod_recognition", {}).get("independent", 0)) == 1,
		"v0.9.9.6_dev2 Case 1 (silent reading mode): credits independent recognition and advances SRS honestly"
	)

	# Case 2: Default audiovisual mode (auto_speak_on_switch = true, voice_volume = 1.0) -> speaks pre-shot, logs audiovisual & credits independent mastery!
	game.rules.set_setting("auto_speak_on_switch", true)
	game.clear_question_help()
	var spoke_c2: bool = game.trigger_question_audio(true)
	learning.record_recognition(tid, true, 4, game.question_help_used, day0 + 30, "combat_word", game.recognition_modality())
	var m_c2: Dictionary = game.rules.profile.mastery.get(tid, {})
	verify(
		spoke_c2 and not game.question_help_used and game.question_audiovisual_played and game.recognition_modality() == "audiovisual" and int(m_c2.get("independent_correct", 0)) == 2 and not game.rules.profile.review_due.has(tid) and int(game.rules.profile.learning_stats.get("mod_audiovisual", {}).get("independent", 0)) == 1,
		"v0.9.9.6_dev2 Case 2 (default audiovisual auto-speak): speaks pre-shot, logs audiovisual modality, and credits mastery without false review_due debt"
	)

	# Case 3: Manual [X] replay in silent mode (auto_speak_on_switch = false, voice_volume = 1.0) -> speaks AND flags assisted_audio!
	game.rules.set_setting("auto_speak_on_switch", false)
	game.clear_question_help()
	game.replay_question_audio()
	learning.record_recognition(tid, true, 4, game.question_help_used, day0 + 60, "combat_word", game.recognition_modality())
	var m_c3: Dictionary = game.rules.profile.mastery.get(tid, {})
	verify(
		game.question_help_used and game.question_audio_assisted and game.recognition_modality() == "assisted_audio" and int(m_c3.get("independent_correct", 0)) == 2 and int(game.rules.profile.learning_stats.get("mod_assisted_audio", {}).get("assisted", 0)) == 1,
		"v0.9.9.6_dev2 Case 3 (manual [X] replay in silent mode): marks assisted_audio without inflating independent_correct"
	)

	# Case 4: Muted voice (voice_volume = 0.0, even with auto_speak=true AND [X] pressed) -> NO audio heard -> still honest independent recognition!
	game.rules.set_setting("auto_speak_on_switch", true)
	game.rules.set_setting("voice_volume", 0.0)
	game.clear_question_help()
	var spoke_c4: bool = game.trigger_question_audio(true)
	game.replay_question_audio()
	learning.record_recognition(tid, true, 4, game.question_help_used, day0 + Srs.DAY_SECONDS, "combat_word", game.recognition_modality())
	var m_c4: Dictionary = game.rules.profile.mastery.get(tid, {})
	verify(
		not spoke_c4 and not game.question_help_used and not game.question_audio_assisted and game.recognition_modality() == "recognition" and int(m_c4.get("independent_correct", 0)) == 3,
		"v0.9.9.6_dev2 Case 4 (muted voice_volume=0): plays nothing and never falsely penalizes independent recognition"
	)
	game.rules.set_setting("auto_speak_on_switch", true)
	game.rules.set_setting("voice_volume", 1.0)

	# v0.9.9.6_dev2 profile migration: saves previously disabled by v0.9.9.4 restore auto_speak_on_switch->true once & clean stranded prologue-wangdao-clue!
	var v0994_path := "user://qa-v0994-autospeak-restore.json"
	var v0994_file := FileAccess.open(v0994_path, FileAccess.WRITE)
	v0994_file.store_string(JSON.stringify({
		"schema_version": 3,
		"saved_by_version": "0.9.9.6_dev1",
		"v0994_autospeak_migrated": true,
		"prologue_completed": true,
		"runs": 3,
		"settings": {"auto_speak_on_switch": false, "last_nav_tab": "yanshan"},
		"review_due": {"prologue-wangdao-clue": "incorrect", "js5a2026-003": "incorrect"}
	}, "\t"))
	v0994_file.close()
	var m_old = load("res://scripts/main.gd").new()
	m_old.profile_path_override = v0994_path
	m_old._load_profile()
	var old_st: Dictionary = m_old.rules.ensure_settings()
	verify(
		bool(old_st.get("auto_speak_on_switch", false)) and not m_old.rules.profile.review_due.has("prologue-wangdao-clue") and m_old.rules.profile.review_due.has("js5a2026-003"),
		"v0.9.9.6_dev2: v0.9.9.4-v0.9.9.6_dev1 save restores pre-shot auto_speak_on_switch->true once and cleans stranded prologue-wangdao-clue while keeping real vocab due items"
	)
	m_old.free()

	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LEARNING_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
