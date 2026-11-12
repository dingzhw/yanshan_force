extends RefCounted

const ITEMS = {
	"magazine": {"cost":120,"title":"扩容弹匣 · 8→14发"},
	"backpack": {"cost":160,"title":"野外背包 · 8→12格"},
	"forest_skin": {"cost":90,"title":"林地枪械涂装 · 绿色外观"},
	"scout": {"cost":240,"title":"山林侦察员 · 移速+10%"},
	"reward_point": {"cost":300,"title":"奖励积分券 · 家长线下兑现"}
}
var phase = "camp"
var score = 0
var correct = 0
var answered = 0
var shots = 0
var question_open = false
var bag = []
var crates = []
var profile = {"coins":0,"xp":0,"points":0,"warehouse":[],"owned":[],"extractions":0}

func accuracy() -> float:
	return float(correct) / float(answered) if answered > 0 else 0.0

func capacity() -> int:
	return 12 if "backpack" in profile.owned else 8

func magazine() -> int:
	return 14 if "magazine" in profile.owned else 8

func level() -> int:
	return 1 + int(profile.xp / 100)

func start_run():
	phase = "active"
	score = 0
	correct = 0
	answered = 0
	shots = 0
	bag = []
	crates = []
	question_open = false

func open_question():
	question_open = phase == "active"

func answer(is_correct: bool) -> bool:
	if phase != "active" or not question_open:
		return false
	question_open = false
	answered += 1
	if is_correct:
		correct += 1
		score += 10
	return true

func crate_ready(tier: int) -> bool:
	return phase == "active" and answered >= (5 if tier == 1 else 10) and accuracy() >= (0.70 if tier == 1 else 0.85)

func add_loot(title: String, value: int) -> bool:
	if phase != "active" or bag.size() >= capacity():
		return false
	bag.append({"title":title,"value":value})
	return true

func open_crate(crate_id: String, tier: int) -> bool:
	if crate_id in crates or not crate_ready(tier) or bag.size() >= capacity():
		return false
	var count = mini(2 if tier == 1 else 3, capacity() - bag.size())
	for i in count:
		add_loot("野外补给" if tier == 1 else "精密组件", 35 if tier == 1 else 70)
	crates.append(crate_id)
	return true

func request_extraction() -> bool:
	if phase != "active" or score < 100:
		return false
	phase = "extracting"
	question_open = false
	return true

func finish_extraction() -> bool:
	if phase != "extracting":
		return false
	profile.warehouse.append_array(bag.duplicate(true))
	profile.xp += correct * 5 + 50
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
	if id != "reward_point" and id in profile.owned:
		return false
	if profile.coins < ITEMS[id].cost:
		return false
	profile.coins -= ITEMS[id].cost
	if id == "reward_point":
		profile.points += 1
	else:
		profile.owned.append(id)
	return true

func bag_value() -> int:
	var result = 0
	for item in bag:
		result += int(item.value)
	return result
