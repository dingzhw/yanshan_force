extends RefCounted

const LearningStore = preload("res://scripts/learning_store.gd")
const SrsScheduler = preload("res://scripts/srs_scheduler.gd")

const EXTRACTION_SCORE = 260
const EXTRACTION_SECONDS = 5.0
const BASE_ANSWER_SCORE = 15
const STREAK_BONUS_SCORE = 5
const NEMESIS_BONUS_SCORE = 10
const OUTPOST_CLEAR_SCORE = 30
const BOSS_DEFEAT_SCORE = 60
const SUPPLY_PERFECT_SCORE = 10
const CIPHER_PERFECT_SCORE = 25
const NORMAL_HIT_SCALE = 0.50
const CONFIDENTIAL_VALUE_MULT = 1.35
const CONFIDENTIAL_CRATE_BONUS = 0.12

const RARITY_NAMES = {
	1: "普通",
	2: "精良",
	3: "稀有",
	4: "史诗",
	5: "传说·大金",
	6: "旷世·大红"
}

const RARITY_COLORS = {
	1: Color("cad4cf"),
	2: Color("6be39b"),
	3: Color("5cb8ff"),
	4: Color("cf82ff"),
	5: Color("ffd15c"),
	6: Color("ff4757")
}

const CONDITION_TIERS = [
	{"name": "战损", "mult": 0.90, "weight": 0.16},
	{"name": "标准", "mult": 1.00, "weight": 0.48},
	{"name": "崭新", "mult": 1.16, "weight": 0.25},
	{"name": "极品孤本", "mult": 1.34, "weight": 0.11}
]

const LOOT_TABLE = {
	1: [
		{"title": "旧巡护电池", "en": "Old Battery", "value": 28, "rarity": 1, "grid": "1×1", "icon": "battery", "lore": "巡山手电与无线电常用的标准锂电池。"},
		{"title": "压缩干粮", "en": "Field Ration", "value": 30, "rarity": 1, "grid": "1×1", "icon": "ration", "lore": "真空密封的高热量麦香压缩饼干。"},
		{"title": "信号铜线", "en": "Copper Wire", "value": 32, "rarity": 1, "grid": "1×1", "icon": "wire", "lore": "抢修山岭侦察电台所需的纯铜导线。"},
		{"title": "诚庄春茶饼", "en": "Spring Tea Cake", "value": 34, "rarity": 1, "grid": "1×1", "icon": "tea", "lore": "诚庄村民采摘烟山明前嫩芽压制的小茶饼，清香回甘。"},
		{"title": "青竹编织哨", "en": "Bamboo Whistle", "value": 36, "rarity": 1, "grid": "1×1", "icon": "bamboo", "lore": "江南山里孩子用苦竹削成的清脆竹哨。"}
	],
	2: [
		{"title": "林间指北针", "en": "Forest Compass", "value": 48, "rarity": 2, "grid": "1×1", "icon": "compass", "lore": "夜光表盘金属指北针，在竹石迷阵中辨位极准。"},
		{"title": "防水战术手电", "en": "Tactical Flashlight", "value": 54, "rarity": 2, "grid": "1×1", "icon": "torch", "lore": "探索烟霞古洞幽暗石室的高流明铝合金手电。"},
		{"title": "巡护员徽章", "en": "Ranger Badge", "value": 58, "rarity": 2, "grid": "1×1", "icon": "badge", "lore": "镌有香樟叶与山溪纹样的烟山护林纪念章。"},
		{"title": "烟山手工折扇", "en": "Bamboo Folding Fan", "value": 62, "rarity": 2, "grid": "1×1", "icon": "fan", "lore": "取烟山老毛竹做扇骨、题有山水小楷的江南折扇。"},
		{"title": "溪石萤光矿", "en": "Stream Fluorite", "value": 66, "rarity": 2, "grid": "1×1", "icon": "gem", "lore": "鹅卵石山溪冲刷出的淡青色天然萤石原矿。"}
	],
	3: [
		{"title": "加密无线电台", "en": "Encrypted Radio", "value": 82, "rarity": 3, "grid": "1×2", "icon": "radio", "lore": "双频抗干扰战术步话机，可截获词兵调动信号。"},
		{"title": "光学测距模块", "en": "Laser Rangefinder", "value": 90, "rarity": 3, "grid": "1×2", "icon": "rangefinder", "lore": "高精度红外测距仪，精密镜片完好无损。"},
		{"title": "古树琥珀标本", "en": "Ancient Amber", "value": 96, "rarity": 3, "grid": "1×1", "icon": "amber", "lore": "凝结着远古松针与小虫的金透树脂琥珀。"},
		{"title": "军规夜视镜片", "en": "Night Vision Lens", "value": 106, "rarity": 3, "grid": "1×2", "icon": "nvg_lens", "lore": "镀有翠绿增透膜的微光夜视仪核心光学组件。"},
		{"title": "太湖透漏赏石", "en": "Taihu Scholar Rock", "value": 115, "rarity": 3, "grid": "1×2", "icon": "rock", "lore": "迷踪竹石阵中历经山泉溶蚀、瘦皱漏透的案头奇石。"}
	],
	4: [
		{"title": "无人机核心芯片", "en": "Drone AI Chip", "value": 145, "rarity": 4, "grid": "1×1", "icon": "chip", "lore": "迅捷侦察机搭载的高算力飞控与词库阵列芯片。"},
		{"title": "竹海古玉残片", "en": "Ancient Jade Piece", "value": 155, "rarity": 4, "grid": "1×1", "icon": "jade_piece", "lore": "竹林深处出土的温润青白玉璜残件，沁色古朴。"},
		{"title": "军用黑匣子", "en": "Flight Black Box", "value": 165, "rarity": 4, "grid": "1×2", "icon": "blackbox", "lore": "防爆橙红涂装战术记录仪，存有珍贵加密航迹。"},
		{"title": "烟霞岩画残拓", "en": "Petroglyph Rubbing", "value": 175, "rarity": 4, "grid": "1×2", "icon": "rubbing", "lore": "拓印自烟霞古洞原生石壁《烟山耕读》的宣纸墨拓。"},
		{"title": "古樟祈福银锁", "en": "Silver Blessing Lock", "value": 188, "rarity": 4, "grid": "1×1", "icon": "silver_lock", "lore": "百年古樟石龛旁流传的江南錾花长命银锁。"},
		{"title": "先民青铜茶铫", "en": "Bronze Tea Kettle", "value": 198, "rarity": 4, "grid": "2×2", "icon": "kettle", "lore": "古洞寒潭畔先民汲泉煮茗所用的绿锈小青铜壶。"}
	],
	5: [
		{"title": "烟山古铜虎符", "en": "Bronze Tiger Tally", "value": 260, "rarity": 5, "grid": "1×2", "icon": "tally", "lore": "错金铭文古铜兵符，印证烟山古道昔日戍守历史。"},
		{"title": "特级金质勋章", "en": "Supreme Gold Medal", "value": 290, "rarity": 5, "grid": "1×1", "icon": "medal", "lore": "表彰卓越战术识词先锋的纯金浮雕荣誉勋章。"},
		{"title": "量子词典原型机", "en": "Quantum Dictionary", "value": 320, "rarity": 5, "grid": "2×2", "icon": "quantum", "lore": "搭载全息声纹解码核心的实验级双语终端原型机。"},
		{"title": "烟山先民竹简", "en": "Ancient Bamboo Slips", "value": 340, "rarity": 5, "grid": "2×2", "icon": "slips", "lore": "烟霞古洞石案遗留的千年墨书竹简，记载诚庄耕读往事。"},
		{"title": "烟山统领黄金核心", "en": "Warden Golden Core", "value": 380, "rarity": 5, "grid": "2×2", "icon": "core", "lore": "铁甲词尊胸腔卸载的高纯度聚变黄金能源核心。"},
		{"title": "望稻亭鎏金香炉", "en": "Gilded Incense Burner", "value": 415, "rarity": 5, "grid": "2×2", "icon": "censer", "lore": "镂空博山云纹鎏金铜炉，昔年文人登亭望稻时焚香雅器。"}
	],
	6: [
		{"title": "越窑秘色青瓷盏", "en": "Secret Celadon Bowl", "value": 640, "rarity": 6, "grid": "2×2", "icon": "celadon", "lore": "【旷世·大红】如冰似玉、千峰翠色的唐宋越窑秘色贡瓷孤品！"},
		{"title": "烟山千年紫芝王", "en": "Millennium Ganoderma", "value": 720, "rarity": 6, "grid": "2×2", "icon": "ganoderma", "lore": "【旷世·大红】生于烟山绝壁云雾深处、紫气莹润的千年灵芝王！"},
		{"title": "诚庄先民双龙玉璧", "en": "Twin-Dragon Jade Disc", "value": 790, "rarity": 6, "grid": "2×2", "icon": "jade_bi", "lore": "【旷世·大红】精雕江南水云双龙纹的羊脂白玉礼璧，价值连城！"},
		{"title": "相控阵超算雷达心", "en": "Quantum Radar Core", "value": 880, "rarity": 6, "grid": "2×3", "icon": "radar_heart", "lore": "【旷世·大红】统御全山防空与电讯阵列最高权限的超算红核！"},
		{"title": "烟山之心·赤金龙印", "en": "Heart of Yanshan", "value": 980, "rarity": 6, "grid": "2×2", "icon": "seal", "lore": "【旷世·大红】赤金镶嵌红宝的镇山宝印——摸金行动最高荣耀象征！"}
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
var operation_tier: String = "normal"
var score = 0
var correct = 0
var answered = 0
var streak = 0
var best_streak = 0
var shots = 0
var outposts_cleared = 0
var perfect_ciphers = 0
var nemesis_cleared = 0
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
	"review_due": {},
	"last_run": {},
	"collection": [],
	"red_extracted": 0,
	"gold_extracted": 0,
	"best_haul": 0,
	"best_item_title": "",
	"best_item_value": 0
}

var learning := LearningStore.new(profile)

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

func is_confidential() -> bool:
	return combat_mode and operation_tier == "confidential"

func mode_label() -> String:
	if not combat_mode:
		return "自由靶场"
	return "机密行动" if operation_tier == "confidential" else "普通行动"

func migrate_legacy_items():
	if profile.has("collection") and profile.collection is Array:
		for i in profile.collection.size():
			if str(profile.collection[i]) == "烟霞丹青残拓":
				profile.collection[i] = "烟霞岩画残拓"
	if profile.has("warehouse") and profile.warehouse is Array:
		for item in profile.warehouse:
			if item is Dictionary and str(item.get("title", "")) == "烟霞丹青残拓":
				item["title"] = "烟霞岩画残拓"
	for int_key in ["red_extracted", "gold_extracted", "best_haul", "best_item_value"]:
		profile[int_key] = maxi(0, int(profile.get(int_key, 0)))
	profile["best_item_title"] = str(profile.get("best_item_title", ""))

static func catalog_meta(title: String) -> Dictionary:
	for r in LOOT_TABLE:
		for entry in LOOT_TABLE[r]:
			if str(entry.title) == title:
				return entry
	return {}

static func total_collectible_count() -> int:
	return LOOT_TABLE[4].size() + LOOT_TABLE[5].size() + LOOT_TABLE[6].size()

func start_run(as_combat = false, tier: String = "normal"):
	phase = "active"
	combat_mode = as_combat
	operation_tier = "confidential" if (as_combat and tier == "confidential") else "normal"
	score = 0
	correct = 0
	answered = 0
	streak = 0
	best_streak = 0
	shots = 0
	outposts_cleared = 0
	perfect_ciphers = 0
	nemesis_cleared = 0
	boss_defeated = false
	bag = []
	crates = []
	supplies_opened = []
	question_open = false

func open_question():
	question_open = phase == "active"

func answer(is_correct: bool, word_id: String = "", choice_count := 4, used_help := false) -> bool:
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
		learning.record_recognition(word_id, is_correct, choice_count, used_help)
	return true

func word_priority(word_id: String) -> float:
	if SrsScheduler.is_due(profile, word_id):
		return 4.2
	if not profile.mastery.has(word_id):
		return 2.2
	var m = profile.mastery[word_id]
	if not (m is Dictionary):
		return 2.0
	var c = int(m.get("independent_correct", m.get("correct", 0)))
	var w = int(m.get("wrong", 0))
	var stage = int(m.get("srs_stage", 0))
	if w > 0 and c <= w + 1:
		return 3.5 + float(w - c) * 0.5
	if stage >= 3 or (c >= 3 and w == 0):
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

func _enrich_loot_dict(raw: Dictionary) -> Dictionary:
	var title := str(raw.get("title", "物资"))
	var meta := catalog_meta(title)
	var r := clampi(int(raw.get("rarity", meta.get("rarity", 1))), 1, 6)
	var en_s := str(raw.get("en", ""))
	if en_s == "":
		en_s = str(meta.get("en", "Supply Item"))
	var grid_s := str(raw.get("grid", ""))
	if grid_s == "":
		grid_s = str(meta.get("grid", "2×2" if r >= 5 else ("1×2" if r >= 3 else "1×1")))
	var icon_s := str(raw.get("icon", ""))
	if icon_s == "":
		icon_s = str(meta.get("icon", "core" if r >= 5 else ("chip" if r >= 3 else "ration")))
	var cond_s := str(raw.get("cond", ""))
	if cond_s == "":
		cond_s = "标准"
	var lore_s := str(raw.get("lore", ""))
	if lore_s == "":
		lore_s = str(meta.get("lore", "烟山行动搜刮物资。"))
	return {
		"title": title,
		"en": en_s,
		"value": maxi(1, int(raw.get("value", meta.get("value", 25)))),
		"rarity": r,
		"grid": grid_s,
		"icon": icon_s,
		"cond": cond_s,
		"lore": lore_s
	}

func add_loot(title: String, value: int, rarity: int = 1, extra: Dictionary = {}) -> bool:
	if phase != "active" or bag.size() >= capacity():
		return false
	var merged := extra.duplicate()
	merged["title"] = title
	merged["value"] = value
	merged["rarity"] = clampi(rarity, 1, 6)
	bag.append(_enrich_loot_dict(merged))
	return true

func add_loot_item(item: Dictionary) -> bool:
	if phase != "active" or bag.size() >= capacity():
		return false
	bag.append(_enrich_loot_dict(item))
	return true

func discard_bag_item(index: int) -> Dictionary:
	if phase != "active" or index < 0 or index >= bag.size():
		return {}
	var removed: Dictionary = bag[index]
	bag.remove_at(index)
	return removed

func _roll_condition() -> Dictionary:
	var p := loot_rng.randf()
	var acc := 0.0
	for c in CONDITION_TIERS:
		acc += float(c.weight)
		if p <= acc:
			return c
	return CONDITION_TIERS[1]

func roll_item_by_rarity(rarity: int) -> Dictionary:
	var clamped := clampi(rarity, 1, 6)
	var list: Array = LOOT_TABLE[clamped]
	var item: Dictionary = list[loot_rng.randi_range(0, list.size() - 1)].duplicate()
	var cond := _roll_condition()
	var jitter := loot_rng.randf_range(0.97, 1.04)
	var val := roundi(float(item["value"]) * float(cond["mult"]) * jitter)
	if is_confidential():
		val = roundi(float(val) * CONFIDENTIAL_VALUE_MULT)
	item["value"] = maxi(1, val)
	item["cond"] = str(cond["name"])
	return _enrich_loot_dict(item)

func roll_field_pickup(perfect_spell: bool = true, overcharged: bool = false) -> Dictionary:
	var roll := loot_rng.randf()
	if is_confidential():
		roll = maxf(0.0, roll - 0.035)
	var r := 1
	if overcharged:
		# Golden Overcharged Supply Cache: guaranteed Uncommon+, real shot at Gold & Mythic Red!
		if perfect_spell:
			if roll < 0.045: r = 6
			elif roll < 0.165: r = 5
			elif roll < 0.420: r = 4
			elif roll < 0.780: r = 3
			else: r = 2
		else:
			if roll < 0.015: r = 6
			elif roll < 0.060: r = 5
			elif roll < 0.220: r = 4
			elif roll < 0.560: r = 3
			else: r = 2
	else:
		# Even humble field wooden boxes have true Delta-Force miracle jackpot potential!
		if perfect_spell:
			if roll < 0.012: r = 6
			elif roll < 0.045: r = 5
			elif roll < 0.145: r = 4
			elif roll < 0.390: r = 3
			elif roll < 0.760: r = 2
			else: r = 1
		else:
			if roll < 0.003: r = 5
			elif roll < 0.035: r = 4
			elif roll < 0.160: r = 3
			elif roll < 0.480: r = 2
			else: r = 1
	return roll_item_by_rarity(r)

func roll_world_loose_item(high_tier_spot: bool = false) -> Dictionary:
	var roll := loot_rng.randf()
	if is_confidential():
		roll = maxf(0.0, roll - 0.04)
	var r := 1
	if high_tier_spot:
		if roll < 0.042: r = 6
		elif roll < 0.155: r = 5
		elif roll < 0.390: r = 4
		elif roll < 0.720: r = 3
		else: r = 2
	else:
		if roll < 0.016: r = 6
		elif roll < 0.062: r = 5
		elif roll < 0.185: r = 4
		elif roll < 0.440: r = 3
		elif roll < 0.780: r = 2
		else: r = 1
	return roll_item_by_rarity(r)

func roll_bird_nest_item() -> Dictionary:
	## Iconic '掏鸟窝/探石缝' tactile lottery: humble twigs/fluorite or miracle '鸟窝出大红'!
	var roll := loot_rng.randf()
	if is_confidential():
		roll = maxf(0.0, roll - 0.045)
	var r := 1
	if roll < 0.032: r = 6
	elif roll < 0.095: r = 5
	elif roll < 0.240: r = 4
	elif roll < 0.520: r = 3
	elif roll < 0.820: r = 2
	else: r = 1
	return roll_item_by_rarity(r)

func roll_squad_drop_items(flawless_wave: bool, is_boss_camp: bool = false) -> Array:
	var count := 2 if (flawless_wave or is_boss_camp) else (2 if loot_rng.randf() < 0.45 else 1)
	var out := []
	for i in count:
		var roll := loot_rng.randf()
		if is_confidential():
			roll = maxf(0.0, roll - 0.05)
		if is_boss_camp:
			roll = maxf(0.0, roll - 0.08)
		var r := 2
		if flawless_wave and i == 0:
			if roll < 0.055: r = 6
			elif roll < 0.210: r = 5
			elif roll < 0.540: r = 4
			else: r = 3
		else:
			if roll < 0.020: r = 6
			elif roll < 0.085: r = 5
			elif roll < 0.260: r = 4
			elif roll < 0.600: r = 3
			else: r = 2
		out.append(roll_item_by_rarity(r))
	return out

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
	bag[idx] = _enrich_loot_dict(item)
	return removed

func roll_crate_rarity(tier: int, perfect_spell: bool) -> int:
	var roll := loot_rng.randf()
	if is_confidential():
		roll = maxf(0.0, roll - CONFIDENTIAL_CRATE_BONUS * 0.65)
	if tier <= 1:
		if perfect_spell:
			if roll < 0.032: return 6
			if roll < 0.145: return 5
			if roll < 0.420: return 4
			if roll < 0.800: return 3
			return 2
		else:
			if roll < 0.030: return 5
			if roll < 0.180: return 4
			if roll < 0.600: return 3
			return 2
	elif tier == 2:
		if perfect_spell:
			if roll < 0.075: return 6
			if roll < 0.300: return 5
			if roll < 0.680: return 4
			return 3
		else:
			if roll < 0.020: return 6
			if roll < 0.105: return 5
			if roll < 0.360: return 4
			if roll < 0.780: return 3
			return 2
	else:
		if perfect_spell:
			if roll < 0.155: return 6
			if roll < 0.520: return 5
			if roll < 0.880: return 4
			return 3
		else:
			if roll < 0.045: return 6
			if roll < 0.220: return 5
			if roll < 0.600: return 4
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
		if add_loot_item(item):
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
		if not add_loot_item(item):
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

func _record_extracted_item(item: Dictionary):
	var r := int(item.get("rarity", 1))
	var val := int(item.get("value", 0))
	if r >= 4 and not (item.title in profile.collection):
		profile.collection.append(item.title)
	if r >= 6:
		profile["red_extracted"] = int(profile.get("red_extracted", 0)) + 1
	elif r == 5:
		profile["gold_extracted"] = int(profile.get("gold_extracted", 0)) + 1
	if val > int(profile.get("best_item_value", 0)):
		profile["best_item_value"] = val
		profile["best_item_title"] = str(item.get("title", ""))

func finish_extraction() -> bool:
	if phase != "extracting":
		return false
	if combat_mode and outposts_cleared >= 2 and bag.size() < capacity():
		var bonus_r := 6 if (boss_defeated and loot_rng.randf() < (0.28 if is_confidential() else 0.14)) else (5 if boss_defeated else (4 if loot_rng.randf() < 0.65 else 5))
		var bonus_item := roll_item_by_rarity(bonus_r)
		bag.append(bonus_item)
	var run_haul := bag_value()
	if run_haul > int(profile.get("best_haul", 0)):
		profile["best_haul"] = run_haul
	for item in bag:
		_record_extracted_item(item)
	profile.warehouse.append_array(bag.duplicate(true))
	var gained_xp: int = int(correct) * 6 + int(outposts_cleared) * 25 + int(perfect_ciphers) * 15 + (60 if boss_defeated else 0) + 60
	if is_confidential():
		gained_xp = roundi(float(gained_xp) * CONFIDENTIAL_VALUE_MULT)
	profile.xp += gained_xp
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
