extends RefCounted
## Transparent 5-stage Leitner spaced-repetition scheduler for primary-school vocabulary.
## Intervals (days): Stage 0 = due now, Stage 1 = 1d, Stage 2 = 3d, Stage 3 = 7d, Stage 4 = 15d.

const DAY_SECONDS := 86400
const STAGE_INTERVAL_DAYS := [0, 1, 3, 7, 15]
const MAX_STAGE := 4
const OUTCOME_INDEPENDENT := "independent"
const OUTCOME_PRACTICED := "practiced_completion"
const OUTCOME_HINTED := "hinted"
const OUTCOME_COPIED := "copied_scaffold"
const OUTCOME_INCORRECT := "incorrect"

static func now_unix() -> int:
	return int(Time.get_unix_time_from_system())

static func resolve_now(now_ts: int) -> int:
	return now_ts if now_ts >= 0 else now_unix()

static func stage_label(stage: int) -> String:
	var labels := ["待巩固", "1天间隔", "3天间隔", "7天间隔", "15天稳固"]
	return labels[clampi(stage, 0, labels.size() - 1)]

static func interval_seconds(stage: int) -> int:
	return int(STAGE_INTERVAL_DAYS[clampi(stage, 0, MAX_STAGE)]) * DAY_SECONDS

static func apply_outcome(entry: Dictionary, outcome: String, is_retest := false, now_ts := -1) -> Dictionary:
	var now := resolve_now(now_ts)
	var stage := clampi(int(entry.get("srs_stage", 0)), 0, MAX_STAGE)
	var streak := maxi(0, int(entry.get("independent_streak", 0)))
	var due_ts := int(entry.get("next_due_ts", 0))

	if outcome == OUTCOME_INDEPENDENT:
		streak += 1
		if stage == 0:
			stage = 1
			due_ts = now + interval_seconds(stage)
		elif is_retest or (due_ts > 0 and now >= due_ts):
			stage = mini(MAX_STAGE, stage + 1)
			due_ts = now + interval_seconds(stage)
		elif due_ts <= 0:
			due_ts = now + interval_seconds(stage)
	elif outcome == OUTCOME_PRACTICED:
		# Completed after seeing the answer in review: clears immediate lock without inflating independent mastery or advancing SRS to tomorrow.
		streak = 0
		stage = 0
		due_ts = 0
	elif outcome == OUTCOME_HINTED:
		streak = 0
		stage = maxi(0, stage - 1)
		due_ts = now
	else:
		# Incorrect or copied_scaffold resets interval to immediate review.
		streak = 0
		stage = 0
		due_ts = now

	entry["srs_stage"] = stage
	entry["independent_streak"] = streak
	entry["last_reviewed_ts"] = now
	entry["next_due_ts"] = due_ts
	return entry

static func is_time_overdue(profile: Dictionary, id: String, now_ts := -1) -> bool:
	var mastery = profile.get("mastery")
	if not (mastery is Dictionary) or not mastery.has(id):
		return false
	var entry = mastery[id]
	if not (entry is Dictionary):
		return false
	var stage := int(entry.get("srs_stage", 0))
	var due_ts := int(entry.get("next_due_ts", 0))
	return stage > 0 and due_ts > 0 and resolve_now(now_ts) >= due_ts

static func is_due(profile: Dictionary, id: String, now_ts := -1) -> bool:
	var review_due = profile.get("review_due")
	if review_due is Dictionary and review_due.has(id):
		return true
	return is_time_overdue(profile, id, now_ts)

static func due_entries(profile: Dictionary, entries: Array, unit: int, include_extra: bool, now_ts := -1) -> Array:
	var now := resolve_now(now_ts)
	var mistakes := []
	var overdue := []
	var seen_ids := {}
	var review_due = profile.get("review_due", {})
	var mastery = profile.get("mastery", {})
	for term in entries:
		var id := str(term.get("id", ""))
		if id.is_empty() or seen_ids.has(id):
			continue
		if unit > 0 and int(term.get("unit", 0)) != unit:
			continue
		if not include_extra and (not term.get("core", true) or term.get("proper_name", false)):
			continue
		seen_ids[id] = true
		if review_due is Dictionary and review_due.has(id):
			mistakes.append(term)
		elif is_time_overdue(profile, id, now):
			var due_ts := int(mastery[id].get("next_due_ts", 0)) if mastery is Dictionary and mastery.has(id) and mastery[id] is Dictionary else 0
			overdue.append({"term": term, "due_ts": due_ts})
	overdue.sort_custom(func(a, b): return int(a.due_ts) < int(b.due_ts))
	var result := []
	result.append_array(mistakes)
	for item in overdue:
		result.append(item.term)
	return result

static func build_session_queue(profile: Dictionary, pool: Array, now_ts := -1) -> Array:
	var now := resolve_now(now_ts)
	var due_bucket := []
	var fresh_bucket := []
	var solid_bucket := []
	var mastery = profile.get("mastery", {})
	for term in pool:
		var id := str(term.get("id", ""))
		if is_due(profile, id, now):
			due_bucket.append(term)
		elif not (mastery is Dictionary) or not mastery.has(id) or int(mastery[id].get("srs_stage", 0)) < 2:
			fresh_bucket.append(term)
		else:
			solid_bucket.append(term)
	due_bucket.shuffle()
	fresh_bucket.shuffle()
	solid_bucket.shuffle()
	# Caller consumes with pop_back(), so highest-priority due words sit at the tail.
	var deck := []
	deck.append_array(solid_bucket)
	deck.append_array(fresh_bucket)
	if not due_bucket.is_empty():
		var repeats := mini(due_bucket.size(), 6)
		for i in repeats:
			deck.append(due_bucket[i])
		deck.append_array(due_bucket)
	return deck
