extends RefCounted

const SrsScheduler = preload("res://scripts/srs_scheduler.gd")
const SENTENCE_PATH := "res://data/learning/jiangsu-5a-sentences.json"
const INDEPENDENT := "independent"
const PRACTICED := "practiced_completion"
const HINTED := "hinted"
const COPIED := "copied_scaffold"
const INCORRECT := "incorrect"
const REVEAL_COOLDOWN_SECONDS := 300

var profile: Dictionary
var run_independent := 0
var run_assisted := 0
var run_incorrect := 0

func _init(save_profile: Dictionary):
	profile = save_profile

func reset_run_stats():
	run_independent = 0
	run_assisted = 0
	run_incorrect = 0

static func load_sentences() -> Array:
	var bank = JSON.parse_string(FileAccess.get_file_as_string(SENTENCE_PATH))
	if bank is Dictionary and bank.get("schema_version") == 1 and bank.get("entries") is Array:
		return bank.entries
	push_error("Sentence bank missing or invalid: " + SENTENCE_PATH)
	return []

static func format_cloze(sentence_text: String, span: String) -> String:
	if sentence_text.is_empty() or span.is_empty():
		return sentence_text
	var idx := sentence_text.findn(span)
	if idx < 0:
		return sentence_text
	return sentence_text.substr(0, idx) + "____" + sentence_text.substr(idx + span.length())

static func build_cloze_index(sentences: Array) -> Dictionary:
	var index := {}
	for sent in sentences:
		if not (sent is Dictionary):
			continue
		var en := str(sent.get("english", ""))
		var zh := str(sent.get("chinese", ""))
		var page := int(sent.get("textbook_page", 0))
		var unit := int(sent.get("unit", 0))
		var source_kind := str(sent.get("source_kind", ""))
		for target in sent.get("cloze_targets", []):
			if not (target is Dictionary):
				continue
			var wid := str(target.get("word_id", ""))
			var span := str(target.get("span", ""))
			if wid.is_empty() or span.is_empty() or index.has(wid):
				continue
			if en.findn(span) < 0:
				continue
			index[wid] = {
				"sentence_id": str(sent.get("id", "")),
				"english": en,
				"chinese": zh,
				"cloze_text": format_cloze(en, span),
				"span": span,
				"textbook_page": page,
				"unit": unit,
				"source_kind": source_kind
			}
	return index

func _entry(id: String) -> Dictionary:
	var data = profile.mastery.get(id)
	return data if data is Dictionary else {}

func _bump_scene_stat(scene: String, modality: String, bucket: String):
	if not profile.has("learning_stats") or not (profile["learning_stats"] is Dictionary):
		profile["learning_stats"] = {}
	var stats: Dictionary = profile["learning_stats"]
	var key := scene if scene != "" else "combat_word"
	if not stats.has(key) or not (stats[key] is Dictionary):
		stats[key] = {"total": 0, "independent": 0, "assisted": 0, "incorrect": 0, "one_choice": 0}
	var rec: Dictionary = stats[key]
	rec["total"] = int(rec.get("total", 0)) + 1
	rec[bucket] = int(rec.get(bucket, 0)) + 1
	if modality != "":
		var mkey := "mod_" + modality
		if not stats.has(mkey) or not (stats[mkey] is Dictionary):
			stats[mkey] = {"total": 0, "independent": 0, "assisted": 0, "incorrect": 0, "one_choice": 0}
		var mrec: Dictionary = stats[mkey]
		mrec["total"] = int(mrec.get("total", 0)) + 1
		mrec[bucket] = int(mrec.get(bucket, 0)) + 1

func mark_answer_revealed(id: String, now_ts := -1):
	if id.is_empty():
		return
	var entry := _entry(id)
	entry["last_revealed_ts"] = SrsScheduler.resolve_now(now_ts)
	profile.mastery[id] = entry

func was_recently_revealed(id: String, now_ts := -1) -> bool:
	if id.is_empty():
		return false
	var entry := _entry(id)
	var rev_ts := int(entry.get("last_revealed_ts", 0))
	if rev_ts <= 0:
		return false
	var now := SrsScheduler.resolve_now(now_ts)
	return now >= rev_ts and (now - rev_ts) < REVEAL_COOLDOWN_SECONDS

func is_due(id: String, now_ts := -1) -> bool:
	return SrsScheduler.is_due(profile, id, now_ts)

func is_nemesis(id: String, now_ts := -1) -> bool:
	return SrsScheduler.is_due(profile, id, now_ts)

func record_recognition(id: String, is_correct: bool, choice_count: int, used_help: bool, now_ts := -1, scene := "combat_word", modality := "recognition"):
	if id.is_empty():
		return
	var entry := _entry(id)
	entry["seen"] = int(entry.get("seen", 0)) + 1
	entry["encounters"] = int(entry.get("encounters", 0)) + 1
	entry["last_choice_count"] = choice_count
	entry["last_scene"] = scene
	if not is_correct:
		entry["wrong"] = int(entry.get("wrong", 0)) + 1
		entry["last_outcome"] = INCORRECT
		profile.review_due[id] = INCORRECT
		SrsScheduler.apply_outcome(entry, INCORRECT, false, now_ts)
		run_incorrect += 1
		_bump_scene_stat(scene, modality, "incorrect")
	elif choice_count >= 2 and not used_help:
		_credit(entry)
		entry["last_outcome"] = INDEPENDENT
		entry.erase("last_revealed_ts")
		SrsScheduler.apply_outcome(entry, INDEPENDENT, false, now_ts)
		profile.review_due.erase(id)
		run_independent += 1
		_bump_scene_stat(scene, modality, "independent")
	else:
		entry["last_outcome"] = HINTED if used_help else "one_choice"
		run_assisted += 1
		_bump_scene_stat(scene, modality, "assisted" if used_help else "one_choice")
		if used_help:
			entry["assisted"] = int(entry.get("assisted", 0)) + 1
			profile.review_due[id] = HINTED
			SrsScheduler.apply_outcome(entry, HINTED, false, now_ts)
	profile.mastery[id] = entry

func record_story_clue(id: String, is_correct: bool, first_try: bool, scene := "prologue_clue"):
	## v0.9.9.4: Story comprehension clues (with on-screen English/Chinese context) are tracked strictly as
	## 'story_clue' telemetry and NEVER pollute independent listening/recognition mastery or the SRS review pool!
	if id.is_empty():
		return
	var bucket := "incorrect"
	if is_correct:
		bucket = "independent" if first_try else "assisted"
	_bump_scene_stat(scene if scene != "" else "prologue_clue", "story_clue", bucket)
	if profile.has("review_due") and profile["review_due"] is Dictionary and profile["review_due"].has(id):
		profile["review_due"].erase(id)

func record_spelling(id: String, outcome: String, is_retest := false, now_ts := -1, count_encounter := true, scene := ""):
	if id.is_empty():
		return
	var entry := _entry(id)
	var eff_scene := scene if scene != "" else ("retest_spell" if is_retest else "crate_spell")
	entry["seen"] = int(entry.get("seen", 0)) + 1
	if count_encounter:
		entry["encounters"] = int(entry.get("encounters", 0)) + 1
	entry["last_outcome"] = outcome
	entry["last_scene"] = eff_scene
	if outcome == INDEPENDENT:
		entry["spelled"] = int(entry.get("spelled", 0)) + 1
		entry.erase("last_revealed_ts")
		_credit(entry)
		SrsScheduler.apply_outcome(entry, INDEPENDENT, is_retest, now_ts)
		profile.review_due.erase(id)
		run_independent += 1
		_bump_scene_stat(eff_scene, "spelling", "independent")
	elif outcome == PRACTICED:
		# Practiced completion after answer was shown: does NOT credit independent_correct or advance SRS!
		entry["spelled"] = int(entry.get("spelled", 0)) + 1
		entry["practiced"] = int(entry.get("practiced", 0)) + 1
		SrsScheduler.apply_outcome(entry, PRACTICED, is_retest, now_ts)
		profile.review_due.erase(id)
		run_assisted += 1
		_bump_scene_stat(eff_scene, "spelling", "assisted")
	else:
		entry[outcome] = int(entry.get(outcome, 0)) + 1
		if outcome == INCORRECT:
			entry["wrong"] = int(entry.get("wrong", 0)) + 1
			run_incorrect += 1
			_bump_scene_stat(eff_scene, "spelling", "incorrect")
		else:
			run_assisted += 1
			_bump_scene_stat(eff_scene, "spelling", "assisted")
		profile.review_due[id] = outcome
		SrsScheduler.apply_outcome(entry, outcome, is_retest, now_ts)
	profile.mastery[id] = entry

func _credit(entry: Dictionary):
	entry["correct"] = int(entry.get("correct", 0)) + 1
	entry["independent_correct"] = int(entry.get("independent_correct", 0)) + 1

func is_mastered(id: String) -> bool:
	var e := _entry(id)
	if e.is_empty():
		return false
	var ind := int(e.get("independent_correct", 0))
	var wrong := int(e.get("wrong", 0))
	var stage := int(e.get("srs_stage", 0))
	return (ind >= 2 and ind > wrong) or stage >= 2

func mastered_count(entries: Array) -> int:
	var count := 0
	var counted := {}
	for term in entries:
		var id := str(term.id)
		if counted.has(id):
			continue
		counted[id] = true
		if is_mastered(id):
			count += 1
	return count

func pending(entries: Array, unit: int, include_extra: bool, now_ts := -1) -> Array:
	return SrsScheduler.due_entries(profile, entries, unit, include_extra, now_ts)
