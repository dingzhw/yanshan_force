extends RefCounted

const EXTRACTION_SCORE = 260
const EXTRACTION_SECONDS = 5.0
const BASE_ANSWER_SCORE = 15
const STREAK_BONUS_SCORE = 5
const OUTPOST_CLEAR_SCORE = 30
const BOSS_DEFEAT_SCORE = 60
const SUPPLY_PERFECT_SCORE = 10
const CIPHER_PERFECT_SCORE = 25

const RARITY_NAMES = {
	1: "普通",
	2: "精良",
	3: "稀有",
	4: "史诗",
	5: "传说·大金"
}

const RARITY_COLORS = {
	1: Color("cad4cf"),
	2: Color("74e3a3"),
	3: Color("66beff"),
	4: Color("cf8aff"),
	5: Color("ffd15c")
}

const LOOT_TABLE = {
	1: [
		{"title": "旧巡护电池", "value": 28, "rarity": 1},
		{"title": "压缩干粮", "value": 30, "rarity": 1},
		{"title": "信号铜线", "value": 32, "rarity": 1}
	],
	2: [
		{"title": "林间指北针", "value": 48, "rarity": 2},
		{"title": "防水战术手电", "value": 54, "rarity": 2},
		{"title": "巡护员徽章", "value": 58, "rarity": 2}
	],
	3: [
		{"title": "加密无线电台", "value": 82, "rarity": 3},
		{"title": "光学测距模块", "value": 90, "rarity": 3},
		{"title": "古树琥珀标本", "value": 96, "rarity": 3}
	],
	4: [
		{"title": "无人机核心芯片", "value": 145, "rarity": 4},
		{"title": "竹海古玉残片", "value": 155, "rarity": 4},
		{"title": "军用黑匣子", "value": 165, "rarity": 4}
	],
	5: [
		{"title": "烟山古铜虎符", "value": 260, "rarity": 5},
		{"title": "特级金质勋章", "value": 290, "rarity": 5},
		{"title": "量子词典原型机", "value": 320, "rarity": 5},
		{"title": "烟山统领黄金核心", "value": 380, "rarity": 5}
	]
}

const ITEMS = {
	"red_dot": {"cost": 110, "slot": "optic", "title": "全息精准瞄具 · 开镜高倍稳瞄"},
	"scope_2x": {"cost": 220, "slot": "optic", "title": "2倍战术棱镜镜 · 远距清晰稳瞄"},
	"suppressor": {"cost": 240, "slot": "muzzle", "title": "钛合金消音器 · 低噪潜行不惊动远敌"},
	"compensator": {"cost": 190, "slot": "muzzle", "title": "双室制退器 · 后坐力-35%更稳定"},
	"angled_grip": {"cost": 175, "slot": "grip", "title": "战术直角握把 · 开镜提速45%+稳枪"},
	"magazine": {"cost": 140, "slot": "mag", "title": "扩容弹匣 I · 8→14发"},
	"magazine2": {"cost": 260, "slot": "mag", "title": "战术弹鼓 II · 14→20发"},
	"shield_core": {"cost": 200, "slot": "armor", "title": "纳米护盾核心 · 护盾30→60"},
	"backpack": {"cost": 180, "slot": "pack", "title": "野外战术背包 · 8→14格"},
	"medkit_pack": {"cost": 160, "slot": "med", "title": "急救扩容包 · 医疗包1→3"},
	"tactical_rig": {"cost": 210, "slot": "rig", "title": "模块化携行弹挂 · 开局备弹+2弹匣"},
	"tactical_belt": {"cost": 165, "slot": "belt", "title": "特战腰带 · 开局+1烟雾EMP +1能量饮"},
	"forest_skin": {"cost": 120, "slot": "skin", "title": "竹影迷彩涂装 · 翡翠定制枪身"},
	"scout": {"cost": 240, "slot": "boots", "title": "山林侦察靴 · 移速+12%"},
	"reward_point": {"cost": 350, "slot": "reward", "title": "奖励积分券 · 家长线下兑现"}
}

const GUNSMITH_ORDER = [
	"red_dot", "scope_2x",
	"suppressor", "compensator",
	"angled_grip", "tactical_rig",
	"tactical_belt", "magazine",
	"magazine2", "shield_core",
	"backpack", "medkit_pack",
	"forest_skin", "scout",
	"reward_point"
]

const BOSS_BLUEPRINTS = ["scope_2x", "suppressor", "compensator", "angled_grip", "tactical_rig", "tactical_belt"]

var phase = "camp"
var combat_mode = false
var score = 0
var correct = 0
var answered = 0
var streak = 0
var best_streak = 0
var shots = 0
var outposts_cleared = 0
var perfect_ciphers = 0
var boss_defeated = false
var question_open = false
var bag = []
var crates = []
var supplies_opened = []
var loot_rng := RandomNumberGenerator.new()

var profile = {
	"coins": 0,
	"xp": 0,
	"points": 0,
	"warehouse": [],
	"owned": [],
	"equipped": {"optic": "", "muzzle": "", "grip": ""},
	"extractions": 0,
	"mastery": {},
	"collection": []
}

func _init():
	loot_rng.randomize()

func accuracy() -> float:
	return float(correct) / float(answered) if answered > 0 else 0.0

func capacity() -> int:
	return 14 if "backpack" in profile.owned else 8

func magazine() -> int:
	if "magazine2" in profile.owned:
		return 20
	return 14 if "magazine" in profile.owned else 8

func max_shield() -> int:
	return 60 if "shield_core" in profile.owned else 30

func starter_medkits() -> int:
	return 3 if "medkit_pack" in profile.owned else 1

func starter_reserve_ammo() -> int:
	if not combat_mode:
		return -1
	var mags = 4 if "tactical_rig" in profile.owned else 2
	return mags * magazine()

func starter_grenades() -> int:
	return 2 if "tactical_belt" in profile.owned else 1

func starter_stims() -> int:
	return 2 if "tactical_belt" in profile.owned else 1

func ensure_equipped():
	if not profile.has("equipped") or not (profile.equipped is Dictionary):
		profile["equipped"] = {"optic": "", "muzzle": "", "grip": ""}
	var eq: Dictionary = profile["equipped"]
	for slot in ["optic", "muzzle", "grip"]:
		var val = str(eq.get(slot, ""))
		if val != "" and not (val in profile.owned):
			eq[slot] = ""
	# Backward compatibility: legacy saves owning red_dot auto-equip it unless scope_2x is equipped
	if str(eq.get("optic", "")) == "":
		if "scope_2x" in profile.owned:
			eq["optic"] = "scope_2x"
		elif "red_dot" in profile.owned:
			eq["optic"] = "red_dot"

func active_optic() -> String:
	ensure_equipped()
	return str(profile["equipped"].get("optic", ""))

func active_muzzle() -> String:
	ensure_equipped()
	return str(profile["equipped"].get("muzzle", ""))

func active_grip() -> String:
	ensure_equipped()
	return str(profile["equipped"].get("grip", ""))

func equip_attachment(slot: String, id: String) -> bool:
	if phase in ["active", "extracting"]:
		return false
	ensure_equipped()
	if id == "":
		profile["equipped"][slot] = ""
		return true
	if not (id in profile.owned) or not ITEMS.has(id) or ITEMS[id].get("slot", "") != slot:
		return false
	profile["equipped"][slot] = "" if str(profile["equipped"].get(slot, "")) == id else id
	return true

func unlock_blueprint(id: String) -> bool:
	if not ITEMS.has(id) or id == "reward_point" or id in profile.owned:
		return false
	profile.owned.append(id)
	var slot = str(ITEMS[id].get("slot", ""))
	if slot in ["optic", "muzzle", "grip"]:
		ensure_equipped()
		profile["equipped"][slot] = id
	return true

func level() -> int:
	return 1 + int(profile.xp / 120)

func start_run(as_combat = false):
	phase = "active"
	combat_mode = as_combat
	score = 0
	correct = 0
	answered = 0
	streak = 0
	best_streak = 0
	shots = 0
	outposts_cleared = 0
	perfect_ciphers = 0
	boss_defeated = false
	bag = []
	crates = []
	supplies_opened = []
	question_open = false

func open_question():
	question_open = phase == "active"

func answer(is_correct: bool, word_id: String = "") -> bool:
	if phase != "active" or not question_open:
		return false
	question_open = false
	answered += 1
	if is_correct:
		correct += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		var bonus = STREAK_BONUS_SCORE if streak >= 3 else 0
		score += BASE_ANSWER_SCORE + bonus
	else:
		streak = 0
	if word_id != "":
		record_word_result(word_id, is_correct)
	return true

func record_word_result(word_id: String, is_correct: bool):
	var entry = profile.mastery.get(word_id, {"seen": 0, "correct": 0, "wrong": 0, "spelled": 0})
	entry["seen"] = int(entry.get("seen", 0)) + 1
	if is_correct:
		entry["correct"] = int(entry.get("correct", 0)) + 1
	else:
		entry["wrong"] = int(entry.get("wrong", 0)) + 1
	profile.mastery[word_id] = entry

func record_word_spelled(word_id: String):
	if word_id == "":
		return
	var entry = profile.mastery.get(word_id, {"seen": 0, "correct": 0, "wrong": 0, "spelled": 0})
	entry["spelled"] = int(entry.get("spelled", 0)) + 1
	entry["correct"] = int(entry.get("correct", 0)) + 1
	profile.mastery[word_id] = entry

func mastered_count() -> int:
	var count = 0
	for word_id in profile.mastery:
		var m = profile.mastery[word_id]
		if m is Dictionary and int(m.get("correct", 0)) >= 2 and int(m.get("correct", 0)) > int(m.get("wrong", 0)):
			count += 1
	return count

func word_priority(word_id: String) -> float:
	if not profile.mastery.has(word_id):
		return 2.2
	var m = profile.mastery[word_id]
	if not (m is Dictionary):
		return 2.0
	var c = int(m.get("correct", 0))
	var w = int(m.get("wrong", 0))
	if w > 0 and c <= w + 1:
		return 3.5 + float(w - c) * 0.5
	if c >= 3 and w == 0:
		return 0.45
	return 1.3

func crate_requirements(tier: int) -> Dictionary:
	if tier <= 1:
		return {"minimum": 5, "accuracy": 0.70, "slots": 2}
	if tier == 2:
		return {"minimum": 9, "accuracy": 0.80, "slots": 3}
	return {"minimum": 12, "accuracy": 0.85, "slots": 3}

func crate_ready(tier: int) -> bool:
	var req = crate_requirements(tier)
	return phase == "active" and answered >= req.minimum and accuracy() >= req.accuracy

func add_loot(title: String, value: int, rarity: int = 1) -> bool:
	if phase != "active" or bag.size() >= capacity():
		return false
	bag.append({"title": title, "value": value, "rarity": clampi(rarity, 1, 5)})
	return true

func roll_item_by_rarity(rarity: int) -> Dictionary:
	var clamped = clampi(rarity, 1, 5)
	var list: Array = LOOT_TABLE[clamped]
	return list[loot_rng.randi_range(0, list.size() - 1)].duplicate()

func roll_field_pickup(perfect_spell: bool = true) -> Dictionary:
	var roll = loot_rng.randf()
	var r = 1
	if perfect_spell:
		r = 3 if roll < 0.12 else (2 if roll < 0.50 else 1)
	else:
		r = 2 if roll < 0.28 else 1
	return roll_item_by_rarity(r)

func lowest_bag_index() -> int:
	if bag.is_empty():
		return -1
	var idx := 0
	for i in range(1, bag.size()):
		if int(bag[i].value) < int(bag[idx].value):
			idx = i
	return idx

func swap_lowest_loot(item: Dictionary) -> Dictionary:
	if phase != "active" or bag.is_empty():
		return {}
	var idx := lowest_bag_index()
	var removed: Dictionary = bag[idx]
	bag[idx] = {
		"title": str(item.get("title", "物资")),
		"value": maxi(1, int(item.get("value", 20))),
		"rarity": clampi(int(item.get("rarity", 1)), 1, 5)
	}
	return removed

func roll_crate_rarity(tier: int, perfect_spell: bool) -> int:
	var roll = loot_rng.randf()
	if tier <= 1:
		if perfect_spell:
			if roll < 0.10: return 5
			if roll < 0.36: return 4
			if roll < 0.78: return 3
			return 2
		else:
			if roll < 0.14: return 3
			if roll < 0.58: return 2
			return 1
	elif tier == 2:
		if perfect_spell:
			if roll < 0.24: return 5
			if roll < 0.64: return 4
			return 3
		else:
			if roll < 0.08: return 5
			if roll < 0.32: return 4
			if roll < 0.75: return 3
			return 2
	else:
		if perfect_spell:
			if roll < 0.42: return 5
			if roll < 0.85: return 4
			return 3
		else:
			if roll < 0.18: return 5
			if roll < 0.55: return 4
			return 3

func open_crate(crate_id: String, tier: int, perfect_spell: bool = false) -> Array:
	var awarded = []
	if crate_id in crates or not crate_ready(tier) or bag.size() >= capacity():
		return awarded
	var req = crate_requirements(tier)
	var count = mini(req.slots, capacity() - bag.size())
	for i in count:
		var rarity = roll_crate_rarity(tier, perfect_spell and i == 0)
		var item = roll_item_by_rarity(rarity)
		if add_loot(item.title, item.value, item.rarity):
			awarded.append(item)
	if perfect_spell:
		perfect_ciphers += 1
		score += CIPHER_PERFECT_SCORE + maxi(0, tier - 1) * 10
	crates.append(crate_id)
	return awarded

func unlock_crate_full(crate_id: String, tier: int, perfect_spell: bool = false) -> Dictionary:
	var all_items := []
	var overflow := []
	if crate_id in crates or not crate_ready(tier):
		return {"items": all_items, "overflow": overflow}
	var req = crate_requirements(tier)
	for i in int(req.slots):
		var rarity = roll_crate_rarity(tier, perfect_spell and i == 0)
		var item = roll_item_by_rarity(rarity)
		all_items.append(item)
		if not add_loot(item.title, item.value, item.rarity):
			overflow.append(item)
	if perfect_spell:
		perfect_ciphers += 1
		score += CIPHER_PERFECT_SCORE + maxi(0, tier - 1) * 10
	crates.append(crate_id)
	return {"items": all_items, "overflow": overflow}

func can_extract() -> bool:
	if phase != "active" or score < EXTRACTION_SCORE:
		return false
	if combat_mode and (outposts_cleared < 2 or not boss_defeated):
		return false
	return true

func request_extraction() -> bool:
	if not can_extract():
		return false
	phase = "extracting"
	question_open = false
	return true

func finish_extraction() -> bool:
	if phase != "extracting":
		return false
	for item in bag:
		if int(item.get("rarity", 1)) >= 4 and not (item.title in profile.collection):
			profile.collection.append(item.title)
	if combat_mode and outposts_cleared >= 2 and bag.size() < capacity():
		var bonus_item = roll_item_by_rarity(5 if boss_defeated else (4 if loot_rng.randf() < 0.65 else 5))
		bag.append(bonus_item)
		if not (bonus_item.title in profile.collection):
			profile.collection.append(bonus_item.title)
	profile.warehouse.append_array(bag.duplicate(true))
	profile.xp += correct * 6 + outposts_cleared * 25 + perfect_ciphers * 15 + (60 if boss_defeated else 0) + 60
	profile.extractions += 1
	bag.clear()
	phase = "result"
	return true

func abandon():
	bag.clear()
	question_open = false
	phase = "result"

func sell_all() -> int:
	if phase in ["active", "extracting"]:
		return 0
	var total = 0
	for item in profile.warehouse:
		total += int(item.value)
	profile.coins += total
	profile.warehouse.clear()
	return total

func purchase(id: String) -> bool:
	if phase in ["active", "extracting"] or not ITEMS.has(id):
		return false
	if id == "magazine2" and not ("magazine" in profile.owned):
		return false
	if id != "reward_point" and id in profile.owned:
		return false
	if profile.coins < ITEMS[id].cost:
		return false
	profile.coins -= ITEMS[id].cost
	if id == "reward_point":
		profile.points += 1
	else:
		profile.owned.append(id)
		var slot = str(ITEMS[id].get("slot", ""))
		if slot in ["optic", "muzzle", "grip"]:
			ensure_equipped()
			profile["equipped"][slot] = id
	return true

func bag_value() -> int:
	var result = 0
	for item in bag:
		result += int(item.value)
	return result
