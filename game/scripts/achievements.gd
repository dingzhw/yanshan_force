extends Node
## Yanshan Force Achievement & Weapon Charm Badge System (v0.8.2 V81-10).
## Tracks lifetime wildlife & combat milestones, queues gilded top-center unlock banners,
## and rewards equippable 3D dangling weapon charms mounted underneath the YS-04 carbine!

const CHARMS := {
	"charm_acorn": {"name": "鎏金松果挂牌", "color": Color("d9a441"), "accent": Color("7d4f22"), "shape": "acorn", "desc": "松鼠系列成就奖励：精工黄铜松果吊坠。"},
	"charm_acorn_gold": {"name": "纯金松鼠王冠章", "color": Color("ffd74a"), "accent": Color("ff7b29"), "shape": "crown", "desc": "高阶松鼠成就奖励：24K 鎏金王冠松果勋章。"},
	"charm_roast": {"name": "烤肉金猪牌", "color": Color("e07b39"), "accent": Color("ffd86b"), "shape": "roast", "desc": "野猪首杀成就奖励：滋滋冒油的烤肉金猪挂件！"},
	"charm_boar_tusk": {"name": "玄金獠牙勋章", "color": Color("f0e2c4"), "accent": Color("5a3b24"), "shape": "tusk", "desc": "铁鬃猎手成就奖励：双弯白牙镶金战术坠。"},
	"charm_fox_bell": {"name": "赤狐铜铃", "color": Color("e85d3a"), "accent": Color("ffd26a"), "shape": "bell", "desc": "赤狐系列成就奖励：古铜微光小铃铛。"},
	"charm_koi": {"name": "青花锦鲤玉坠", "color": Color("4ce3d0"), "accent": Color("ff6e4a"), "shape": "koi", "desc": "溪谷水产成就奖励：江南碧玉雕花锦鲤佩。"},
	"charm_feather": {"name": "白鹭银羽徽", "color": Color("e6f2f8"), "accent": Color("6ce3c6"), "shape": "feather", "desc": "飞鸟系列成就奖励：鎏银振翅白鹭羽饰。"},
	"charm_shield_tag": {"name": "战术词盾狗牌", "color": Color("5ad9a8"), "accent": Color("1c332c"), "shape": "tag", "desc": "雾隐帮词兵成就奖励：刻字钛合金战术铭牌。"},
	"charm_word_blade": {"name": "百词斩金刃章", "color": Color("ffd15c"), "accent": Color("46e8b8"), "shape": "blade", "desc": "百词斩/连对成就奖励：微型双刃金剑挂件。"},
	"charm_crosshair": {"name": "黄金准星靶环", "color": Color("ff5c5c"), "accent": Color("ffd15c"), "shape": "crosshair", "desc": "百步穿词成就奖励：光学十字分划黄金环。"},
	"charm_sonar": {"name": "幽蓝声纹晶核", "color": Color("58e8ff"), "accent": Color("194866"), "shape": "sonar", "desc": "古洞循音石卫成就奖励：脉动幽蓝声波矿晶。"},
	"charm_iron_crown": {"name": "玄铁龙纹战徽", "color": Color("ffae3b"), "accent": Color("2a262c"), "shape": "iron_crown", "desc": "机密天降玄铁词尊成就奖励：暗金玄铁霸主徽章。"},
	"charm_mythic_star": {"name": "赤金大红星章", "color": Color("ff3b4e"), "accent": Color("ffd966"), "shape": "star", "desc": "旷世大红带出成就奖励：赤金五芒星荣耀坠。"},
}

const CATALOG := [
	# Squirrel tier (10 / 100 / 1000 / 10000)
	{"id": "sq_10", "cat": "生灵狩猎", "stat": "squirrel", "target": 10, "title": "杀了只老鼠？", "desc": "累计消灭 10 只林间小松鼠", "charm": "charm_acorn", "icon": "🐿"},
	{"id": "sq_100", "cat": "生灵狩猎", "stat": "squirrel", "target": 100, "title": "松果终结者", "desc": "累计消灭 100 只林间小松鼠", "charm": "charm_acorn", "icon": "🌰"},
	{"id": "sq_1000", "cat": "生灵狩猎", "stat": "squirrel", "target": 1000, "title": "竹林松鼠克星", "desc": "累计消灭 1,000 只林间小松鼠", "charm": "charm_acorn_gold", "icon": "👑"},
	{"id": "sq_10000", "cat": "生灵狩猎", "stat": "squirrel", "target": 10000, "title": "烟山松鼠传说", "desc": "累计消灭 10,000 只林间小松鼠", "charm": "charm_acorn_gold", "icon": "🌟"},
	# Wild Boar tier (1 / 10 / 100)
	{"id": "boar_1", "cat": "生灵狩猎", "stat": "boar", "target": 1, "title": "可以吃烤肉了！", "desc": "首次成功消灭 1 头山林小野猪", "charm": "charm_roast", "icon": "🍖"},
	{"id": "boar_10", "cat": "生灵狩猎", "stat": "boar", "target": 10, "title": "山林野味大师", "desc": "累计消灭 10 头山林小野猪", "charm": "charm_roast", "icon": "🔥"},
	{"id": "boar_100", "cat": "生灵狩猎", "stat": "boar", "target": 100, "title": "铁鬃猎手", "desc": "累计消灭 100 头山林小野猪", "charm": "charm_boar_tusk", "icon": "🐗"},
	# Red Fox tier (1 / 10 / 100)
	{"id": "fox_1", "cat": "生灵狩猎", "stat": "fox", "target": 1, "title": "狐假虎威？", "desc": "首次消灭 1 只山坡小赤狐", "charm": "charm_fox_bell", "icon": "🦊"},
	{"id": "fox_10", "cat": "生灵狩猎", "stat": "fox", "target": 10, "title": "赤狐追踪者", "desc": "累计消灭 10 只山坡小赤狐", "charm": "charm_fox_bell", "icon": "🔔"},
	{"id": "fox_100", "cat": "生灵狩猎", "stat": "fox", "target": 100, "title": "烟霞捕影", "desc": "累计消灭 100 只山坡小赤狐", "charm": "charm_fox_bell", "icon": "⚡"},
	# Creek Aquatic tier (fish + shrimp + crab: 10 / 50 / 200)
	{"id": "aqua_10", "cat": "生灵狩猎", "stat": "aquatic", "target": 10, "title": "溪边小渔夫", "desc": "累计消灭 10 只锦鲤、河虾或山蟹", "charm": "charm_koi", "icon": "🐟"},
	{"id": "aqua_50", "cat": "生灵狩猎", "stat": "aquatic", "target": 50, "title": "清蒸还是红烧？", "desc": "累计消灭 50 只锦鲤、河虾或山蟹", "charm": "charm_koi", "icon": "🦀"},
	{"id": "aqua_200", "cat": "生灵狩猎", "stat": "aquatic", "target": 200, "title": "江南水产大亨", "desc": "累计消灭 200 只锦鲤、河虾或山蟹", "charm": "charm_koi", "icon": "💎"},
	# Birds / Sky Egrets (1 / 10)
	{"id": "bird_1", "cat": "生灵狩猎", "stat": "bird", "target": 1, "title": "神箭惊鸿", "desc": "首次击落 1 只溪畔飞鸟或高空白鹭", "charm": "charm_feather", "icon": "🪶"},
	{"id": "bird_10", "cat": "生灵狩猎", "stat": "bird", "target": 10, "title": "穿云落羽", "desc": "累计击落 10 只飞鸟或高空白鹭", "charm": "charm_feather", "icon": "🦅"},
	# Word-Combat & Mistbound Syndicate ("雾隐帮") tier
	{"id": "soldier_10", "cat": "词战荣誉", "stat": "soldiers_defeated", "target": 10, "title": "初露锋芒", "desc": "累计击败 10 名雾隐帮词兵", "charm": "charm_shield_tag", "icon": "🎖"},
	{"id": "soldier_50", "cat": "词战荣誉", "stat": "soldiers_defeated", "target": 50, "title": "雾隐清道夫", "desc": "累计击败 50 名雾隐帮词兵", "charm": "charm_shield_tag", "icon": "🛡"},
	{"id": "soldier_200", "cat": "词战荣誉", "stat": "soldiers_defeated", "target": 200, "title": "百词斩将", "desc": "累计击败 200 名雾隐帮词兵", "charm": "charm_word_blade", "icon": "⚔"},
	{"id": "soldier_1000", "cat": "词战荣誉", "stat": "soldiers_defeated", "target": 1000, "title": "烟山词圣", "desc": "累计击败 1,000 名雾隐帮词兵", "charm": "charm_word_blade", "icon": "🏆"},
	{"id": "sniper_10", "cat": "词战荣誉", "stat": "sniper_kills", "target": 10, "title": "百步穿词", "desc": "在 35m 外远距精准狙击词兵 10 次", "charm": "charm_crosshair", "icon": "🎯"},
	{"id": "streak_15", "cat": "词战荣誉", "stat": "best_streak", "target": 15, "title": "过目不忘", "desc": "单局连续答对 15 道英语词题", "charm": "charm_word_blade", "icon": "🔥"},
	# Boss & Mythic Loot milestones
	{"id": "warden_1", "cat": "首领与摸金", "stat": "cave_warden_defeated", "target": 1, "title": "静步破音", "desc": "在烟霞古洞击败「古洞循音石卫」", "charm": "charm_sonar", "icon": "🌀"},
	{"id": "overlord_1", "cat": "首领与摸金", "stat": "skyfall_boss_defeated", "target": 1, "title": "玄铁克星", "desc": "机密行动按序击败天降「雾隐机关王·玄铁词尊」", "charm": "charm_iron_crown", "icon": "⚡"},
	{"id": "red_1", "cat": "首领与摸金", "stat": "red_extracted", "target": 1, "title": "红运当头", "desc": "成功带出 1 件【旷世·大红】珍品", "charm": "charm_mythic_star", "icon": "✦"},
]

var game
var banner_root: Control
var banner_panel: Panel
var banner_badge: Label
var banner_title: Label
var banner_sub: Label
var banner_queue: Array = []
var banner_active: Dictionary = {}
var banner_elapsed := 0.0
const BANNER_DURATION := 3.6

func setup(g):
	game = g
	_ensure_profile_fields()
	_build_banner_ui()

func _ensure_profile_fields():
	if not is_instance_valid(game) or game.rules == null:
		return
	var p: Dictionary = game.rules.profile
	if not (p.get("stats") is Dictionary):
		p["stats"] = {}
	if not (p.get("achievements") is Array):
		p["achievements"] = []
	if not (p.get("unlocked_charms") is Array):
		p["unlocked_charms"] = []
	if not p.has("equipped_charm"):
		p["equipped_charm"] = ""
	# Sync red_extracted from legacy profile field if already extracted earlier
	var legacy_red := int(p.get("red_extracted", 0))
	if legacy_red > int(p.stats.get("red_extracted", 0)):
		p.stats["red_extracted"] = legacy_red

func _build_banner_ui():
	banner_root = Control.new()
	banner_root.name = "AchievementBannerRoot"
	banner_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.ui.add_child(banner_root)

	# Sleek gilded achievement banner centered below the top prompt box (y = 136 -> zero HUD overlap!)
	banner_panel = game._panel(banner_root, Rect2(390, 134, 500, 82), Color(0.08, 0.075, 0.045, 0.96), Color("ffd15c"))
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.072, 0.042, 0.96)
	style.border_color = Color("ffd15c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 10
	banner_panel.add_theme_stylebox_override("panel", style)

	var crest := ColorRect.new()
	crest.position = Vector2(14, 13)
	crest.size = Vector2(56, 56)
	crest.color = Color(0.24, 0.18, 0.07, 0.95)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.add_child(crest)

	banner_badge = game._text(banner_panel, "🏆", Vector2(14, 15), Vector2(56, 52), 30, Color("ffd75c"))
	banner_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var kicker: Label = game._text(banner_panel, "✦  烟山成就解锁  ·  ACHIEVEMENT UNLOCKED  ✦", Vector2(82, 8), Vector2(404, 18), 11, Color("ffd15c"))
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_title = game._text(banner_panel, "", Vector2(82, 26), Vector2(404, 28), 21, Color("fff6d6"))
	banner_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_sub = game._text(banner_panel, "", Vector2(82, 55), Vector2(404, 22), 13, Color("8ef0c8"))
	banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.hide()

func stat_value(key: String) -> int:
	_ensure_profile_fields()
	return int(game.rules.profile.stats.get(key, 0))

func is_unlocked(ach_id: String) -> bool:
	_ensure_profile_fields()
	return ach_id in game.rules.profile.achievements

func is_charm_unlocked(charm_id: String) -> bool:
	_ensure_profile_fields()
	return charm_id in game.rules.profile.unlocked_charms

func equipped_charm() -> String:
	_ensure_profile_fields()
	return str(game.rules.profile.get("equipped_charm", ""))

func equip_charm(charm_id: String) -> bool:
	_ensure_profile_fields()
	if charm_id == "":
		game.rules.profile["equipped_charm"] = ""
	else:
		if not CHARMS.has(charm_id) or not is_charm_unlocked(charm_id):
			return false
		if str(game.rules.profile.get("equipped_charm", "")) == charm_id:
			game.rules.profile["equipped_charm"] = ""
		else:
			game.rules.profile["equipped_charm"] = charm_id
	game._save()
	if is_instance_valid(game.player) and is_instance_valid(game.player.weapon_view):
		game.player.weapon_view.refresh_loadout()
	return true

func record_wildlife_kill(kind: String) -> Array:
	var k := kind.to_lower()
	var newly := []
	if k in ["koi", "fish", "shrimp", "crab"]:
		newly.append_array(record_stat(k, 1))
		newly.append_array(record_stat("aquatic", 1))
	else:
		newly.append_array(record_stat(k, 1))
	return newly

func record_stat(stat_key: String, delta_val: int = 1, max_mode: bool = false) -> Array:
	_ensure_profile_fields()
	var stats: Dictionary = game.rules.profile.stats
	var cur := int(stats.get(stat_key, 0))
	var next_val := maxi(cur, delta_val) if max_mode else (cur + delta_val)
	stats[stat_key] = next_val
	var unlocked_now: Array = []
	for item in CATALOG:
		if str(item.stat) != stat_key:
			continue
		var aid := str(item.id)
		if aid in game.rules.profile.achievements:
			continue
		if next_val >= int(item.target):
			game.rules.profile.achievements.append(aid)
			var cid := str(item.get("charm", ""))
			var first_charm := false
			if cid != "" and CHARMS.has(cid) and not (cid in game.rules.profile.unlocked_charms):
				game.rules.profile.unlocked_charms.append(cid)
				first_charm = true
			unlocked_now.append(item)
			_enqueue_banner(item, first_charm)
	if not unlocked_now.is_empty():
		game._save()
	return unlocked_now

func _enqueue_banner(item: Dictionary, first_charm: bool):
	var cid := str(item.get("charm", ""))
	var cname := str(CHARMS.get(cid, {}).get("name", ""))
	var sub_txt := "%s  ·  解锁挂件【%s】" % [str(item.desc), cname] if (first_charm and cname != "") else (
		"%s  ·  可在图鉴装配【%s】" % [str(item.desc), cname] if cname != "" else str(item.desc)
	)
	banner_queue.append({
		"icon": str(item.get("icon", "🏆")),
		"title": str(item.title),
		"sub": sub_txt,
	})
	if banner_active.is_empty():
		_pop_next_banner()

func _pop_next_banner():
	if banner_queue.is_empty():
		banner_active = {}
		if is_instance_valid(banner_panel):
			banner_panel.hide()
		return
	banner_active = banner_queue.pop_front()
	banner_elapsed = 0.0
	if is_instance_valid(banner_panel):
		banner_badge.text = str(banner_active.icon)
		banner_title.text = str(banner_active.title)
		banner_sub.text = str(banner_active.sub)
		banner_panel.modulate.a = 0.0
		banner_panel.position.y = 104.0
		banner_panel.show()
	if is_instance_valid(game):
		game.play_sfx("achievement_unlock", -9)

func update(delta: float):
	if banner_active.is_empty() or not is_instance_valid(banner_panel):
		return
	banner_elapsed += delta
	if banner_elapsed < 0.28:
		var t := clampf(banner_elapsed / 0.28, 0.0, 1.0)
		var ease_out := 1.0 - pow(1.0 - t, 3.0)
		banner_panel.position.y = lerpf(104.0, 134.0, ease_out)
		banner_panel.modulate.a = ease_out
	elif banner_elapsed > BANNER_DURATION - 0.38:
		var t := clampf((BANNER_DURATION - banner_elapsed) / 0.38, 0.0, 1.0)
		banner_panel.position.y = lerpf(116.0, 134.0, t)
		banner_panel.modulate.a = t
	else:
		banner_panel.position.y = 134.0
		banner_panel.modulate.a = 1.0
	if banner_elapsed >= BANNER_DURATION:
		_pop_next_banner()

func unlocked_count() -> int:
	_ensure_profile_fields()
	return game.rules.profile.achievements.size()

func total_count() -> int:
	return CATALOG.size()

func unlocked_charm_count() -> int:
	_ensure_profile_fields()
	return game.rules.profile.unlocked_charms.size()
