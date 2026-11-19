extends RefCounted

const SENTENCE_PATH := "res://data/learning/jiangsu-5a-sentences.json"
const INDEPENDENT := "independent"
const HINTED := "hinted"
const COPIED := "copied_scaffold"
const INCORRECT := "incorrect"

var profile: Dictionary

func _init(save_profile: Dictionary):
	profile = save_profile

static func load_sentences() -> Array:
	var bank = JSON.parse_string(FileAccess.get_file_as_string(SENTENCE_PATH))
	if bank is Dictionary and bank.get("schema_version") == 1 and bank.get("entries") is Array:
		return bank.entries
	push_error("Sentence bank missing or invalid: " + SENTENCE_PATH)
	return []

func _entry(id: String) -> Dictionary:
	var data = profile.mastery.get(id)
	return data if data is Dictionary else {}

func record_recognition(id: String, is_correct: bool, choice_count: int, used_help: bool):
	if id.is_empty():
		return
	var entry := _entry(id)
	entry["seen"] = int(entry.get("seen", 0)) + 1
	entry["last_choice_count"] = choice_count
	if not is_correct:
		entry["wrong"] = int(entry.get("wrong", 0)) + 1
		entry["last_outcome"] = INCORRECT
		profile.review_due[id] = INCORRECT
	elif choice_count >= 2 and not used_help:
		_credit(entry)
		entry["last_outcome"] = INDEPENDENT
	else:
		entry["last_outcome"] = HINTED if used_help else "one_choice"
		if used_help:
			profile.review_due[id] = HINTED
	profile.mastery[id] = entry

func record_spelling(id: String, outcome: String, is_retest := false):
	if id.is_empty():
		return
	var entry := _entry(id)
	entry["seen"] = int(entry.get("seen", 0)) + 1
	entry["last_outcome"] = outcome
	if outcome == INDEPENDENT:
		entry["spelled"] = int(entry.get("spelled", 0)) + 1
		_credit(entry)
		if is_retest:
			profile.review_due.erase(id)
	else:
		entry[outcome] = int(entry.get(outcome, 0)) + 1
		if outcome == INCORRECT:
			entry["wrong"] = int(entry.get("wrong", 0)) + 1
		profile.review_due[id] = outcome
	profile.mastery[id] = entry

func _credit(entry: Dictionary):
	entry["correct"] = int(entry.get("correct", 0)) + 1
	# The legacy counter included last-enemy guesses and supported spelling.
	entry["independent_correct"] = int(entry.get("independent_correct", 0)) + 1

func mastered_count(entries: Array) -> int:
	var count := 0
	var counted := {}
	for term in entries:
		var id := str(term.id)
		if counted.has(id):
			continue
		counted[id] = true
		if int(_entry(id).get("independent_correct", 0)) >= 2:
			count += 1
	return count

func pending(entries: Array, unit: int, include_extra: bool) -> Array:
	var by_id := {}
	for term in entries:
		if unit > 0 and int(term.unit) != unit:
			continue
		if not include_extra and (not term.get("core", true) or term.get("proper_name", false)):
			continue
		by_id[str(term.id)] = term
	var result := []
	for id in profile.review_due:
		if by_id.has(id):
			result.append(by_id[id])
	return result
