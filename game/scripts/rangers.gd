extends Node3D
## Extensible Ranger ('游侠') Roster, Active [V] Skill System, Camp Liaison Bounties ('烟山名望') & Character Codex (v0.8.3).
## - Default Ranger: '少羽' (Shaoyu) — Active [V] Skill '天生神力' (Innate Might):
##   Heavy ground-slam punch knocking nearby word soldiers flat for 1.5s (30.0s cooldown),
##   staggering Bosses & Yanxia Cave Acoustic Warden cleanly.
## - Designed as an extensible multi-ranger foundation for v0.9.0 reputation-based recruitment.

const SHAOYU_SKILL_RADIUS := 7.8
const SHAOYU_KNOCKDOWN_SECONDS := 1.5
const SHAOYU_COOLDOWN_SECONDS := 30.0

const RANGERS := {
	"shaoyu": {
		"id": "shaoyu",
		"name": "少羽",
		"title": "破阵游侠",
		"en": "Shaoyu · Vanguard Ranger",
		"skill_name": "天生神力",
		"skill_key": "V",
		"skill_cooldown": SHAOYU_COOLDOWN_SECONDS,
		"skill_radius": SHAOYU_SKILL_RADIUS,
		"skill_duration": SHAOYU_KNOCKDOWN_SECONDS,
		"skill_desc": "按 [V] 朝地面挥出重拳，以震地冲击波将周围 7.8m 内的词兵短暂震倒在地 1.5 秒（对首领与古洞石卫触发硬直打断），冷却 30 秒。",
		"passive_desc": "山野韧骨：烟山首位常驻游侠，兼具稳健枪法与近身解围能力。",
		"reputation_req": 0,
		"available": true,
		"accent": Color("ffd15c"),
	},
	"tingfeng": {
		"id": "tingfeng",
		"name": "林听风",
		"title": "听风斥候",
		"en": "Lin Tingfeng · Recon Ranger",
		"skill_name": "听风鹰眼",
		"skill_key": "V",
		"skill_cooldown": 28.0,
		"skill_radius": 45.0,
		"skill_duration": 6.0,
		"skill_desc": "【v0.9.0 预告】短时高亮远处营地与弱点词盾，显著提升远距狙词稳瞄能力。",
		"passive_desc": "山风耳目：擅长远距开镜侦察与听音索敌。",
		"reputation_req": 300,
		"available": false,
		"accent": Color("5ce8ff"),
	},
	"qinghe": {
		"id": "qinghe",
		"name": "苏青禾",
		"title": "悬壶游侠",
		"en": "Su Qinghe · Field Medic",
		"skill_name": "青囊脉冲",
		"skill_key": "V",
		"skill_cooldown": 35.0,
		"skill_radius": 6.0,
		"skill_duration": 5.0,
		"skill_desc": "【v0.9.0 预告】瞬发战术护盾急救波，瞬间回复生命护盾并加速换弹。",
		"passive_desc": "本草通识：采摘奇植与使用医疗包享有额外增益。",
		"reputation_req": 600,
		"available": false,
		"accent": Color("6be39b"),
	},
	"zhuying": {
		"id": "zhuying",
		"name": "竹影",
		"title": "踏雾潜行",
		"en": "Zhuying · Stealth Ranger",
		"skill_name": "竹影轻身",
		"skill_key": "V",
		"skill_cooldown": 32.0,
		"skill_radius": 0.0,
		"skill_duration": 5.0,
		"skill_desc": "【v0.9.0 预告】短时步履无声且提升移速，专为深入烟霞古洞潜行避开循音石卫而设。",
		"passive_desc": "林下潜踪：大幅降低行走与开镜发出的声纹噪声。",
		"reputation_req": 900,
		"available": false,
		"accent": Color("cf82ff"),
	},
}

const RANGER_ORDER := ["shaoyu", "tingfeng", "qinghe", "zhuying"]

const CHARACTER_CARDS := [
	{
		"id": "shaoyu",
		"name": "游侠 · 少羽",
		"role": "默认出战主角 · 破阵游侠",
		"faction": "烟山游侠小队",
		"icon": "⚡",
		"color": Color("ffd15c"),
		"bio": "生长于诚庄山麓的少年游侠，力大沉稳，熟稔烟山竹径与溪谷。面对雾隐帮步步紧逼，少羽背起 YS-04 卡宾枪踏入山林，一边破译英文密电、搜集散落遗珍，一边护守家乡安宁。",
		"tactical": "专属 [V] 技能「天生神力」：重拳砸地将周围 7.8m 词兵震倒 1.5 秒（30s CD），被近身包抄或连错狂暴时是绝佳解围反击利器。",
		"unlock_hint": "初始默认解锁",
	},
	{
		"id": "chen_guide",
		"name": "陈向导 · 营地联络员",
		"role": "烟山巡护联络官 · 委托发布者",
		"faction": "烟山游侠小队",
		"icon": "🧭",
		"color": Color("8de8c0"),
		"bio": "常年驻守烟山山脚营地的老巡护员，对东岭望稻亭、石拱古桥与先民石窟了如指掌。负责统筹每日烟山巡护委托、签发「烟山名望」，并在序章引导新游侠熟悉实战。",
		"tactical": "每局出击前可在营地帐篷旁按 [F] 找陈向导查看或更换今日随机委托，完成后即时获得烟山名望与行动币。",
		"unlock_hint": "与营地联络员「陈向导」对话或完成序章解锁",
	},
	{
		"id": "mistbound_syndicate",
		"name": "雾隐帮 · 词盾巡逻编队",
		"role": "盘踞烟山 6 处营地的敌对帮派",
		"faction": "雾隐帮",
		"icon": "⚔",
		"color": Color("ff9d7d"),
		"bio": "借江南山雾潜入烟山的神秘帮派，下辖突击兵、高速侦察蜂与红激光狙击卫三类词兵，身佩以英语密令驱动的全息护盾，妄图窃取诚庄先民遗珍。",
		"tactical": "按顶部中文或自动英文读音命中对应词兵：瞄头 1 枪秒、词盾 2 枪破；少羽近身按 [V] 可震倒整队创造稳瞄爆头窗口。",
		"unlock_hint": "在正式战斗中肃清任意 1 座雾隐帮营地解锁",
	},
	{
		"id": "vanguard_boss",
		"name": "铁面词卫 · 雾隐先锋",
		"role": "普通行动 B 区竹林总坛统领",
		"faction": "雾隐帮",
		"icon": "🛡",
		"color": Color("ff8066"),
		"bio": "雾隐帮镇守 B 区竹林总坛的重甲先锋，铁面覆额、持重型火力压制山脊，掌握着 B 点撤离信标的加密密钥。",
		"tactical": "拥有 720 HP 与周期性 5.5 秒重炮红圈轰炸（半血双圈）。击碎词盾暴露胸口红核暴击输出，可用 [G] 烟雾 EMP 或 [V] 天生神力打断其瞄准。",
		"unlock_hint": "在普通行动中击败「雾隐先锋·铁面词卫」解锁",
	},
	{
		"id": "skyfall_overlord",
		"name": "玄铁词尊 · 雾隐机关王",
		"role": "机密行动天降巨型五盾首领",
		"faction": "雾隐帮",
		"icon": "👑",
		"color": Color("ff5c66"),
		"bio": "雾隐帮秘造的 4 米高玄铁鎏金重型机关统领，仅在机密行动惊动 B 区总坛时伴随震地轰鸣从天而降，全身覆盖五面连锁词盾阵列。",
		"tactical": "匕首无法劈开其玄铁重甲！必须严格按顶部 1→5 顺序以步枪逐一击破 5 块词盾，打错顺序会立刻怒吼回满 500 HP 并重洗词序。",
		"unlock_hint": "在机密行动中击败「雾隐机关王·玄铁词尊」解锁",
	},
	{
		"id": "cave_warden",
		"name": "古洞循音石卫",
		"role": "烟霞古洞千年喀斯特听声守卫",
		"faction": "烟山秘境",
		"icon": "🔊",
		"color": Color("56e8ff"),
		"bio": "沉眠于烟霞古洞一线天石窟的古老机关石卫，双目已盲却能凭借幽蓝声纹肋骨捕捉洞内每一丝脚步与枪响，世代守护先民耕读岩画与寒潭茶灶。",
		"tactical": "仅在烟霞古洞范围内巡逻追击（撤出洞口即脱战）。击中其 0.30m 胸前蓝核不会使其晕厥，反而会触发立刻双臂护核并释放声波反击！此时迅速按 [C]/[Z] 进入潜行静默 1.5 秒，石卫便会放弃搜索并再度放开双臂；可用 [G] 烟雾助消声脱搜，或用少羽 [V] 天生神力短暂震开双臂 1.0 秒抢打核心。",
		"unlock_hint": "在正式战斗中击败「古洞循音石卫」解锁",
	},
	{
		"id": "tingfeng",
		"name": "林听风 · 听风斥候",
		"role": "后续可招募游侠（v0.9.0 预告）",
		"faction": "烟山游侠小队",
		"icon": "🦅",
		"color": Color("5ce8ff"),
		"bio": "常年在东岭望稻亭观风测候的青年斥候，双耳极灵，能凭百米外林间风声分辨敌营方位。待烟山名望达到 300 后将在 v0.9.0 开放招募切角。",
		"tactical": "预告 [V] 技能「听风鹰眼」：短时高亮远处营地与词兵弱点，强化远距开镜狙词手感。",
		"unlock_hint": "累计「烟山名望」达 300 预告解锁（v0.9.0 开放出战）",
	},
	{
		"id": "qinghe",
		"name": "苏青禾 · 悬壶游侠",
		"role": "后续可招募游侠（v0.9.0 预告）",
		"faction": "烟山游侠小队",
		"icon": "🌿",
		"color": Color("6be39b"),
		"bio": "出身江南草药世家的女游侠，熟识烟山八大奇植与山泉茶理，随身携带自制战术急救装置。待烟山名望达到 600 后将在 v0.9.0 开放招募切角。",
		"tactical": "预告 [V] 技能「青囊脉冲」：瞬发护盾急救波，回复生命护盾并瞬间完成装填。",
		"unlock_hint": "累计「烟山名望」达 600 预告解锁（v0.9.0 开放出战）",
	},
]

const BOUNTY_POOL := [
	{"id": "slam_2_enemies", "title": "天生神力破阵", "desc": "本局按 [V] 发动「天生神力」累计震倒至少 2 名词兵", "event": "slam_enemies", "target": 2, "rep": 30, "coins": 40},
	{"id": "clear_camp_1", "title": "清剿雾隐前哨", "desc": "本局彻底肃清任意 1 座雾隐帮战斗营地（3 波）", "event": "camp_cleared", "target": 1, "rep": 35, "coins": 45},
	{"id": "crack_2_boxes", "title": "战地密电破译", "desc": "本局通过英文拼写成功开启 2 个物资箱或密码箱", "event": "box_cracked", "target": 2, "rep": 30, "coins": 40},
	{"id": "streak_5", "title": "连珠妙语五连击", "desc": "本局实战中达成连续答对 5 题", "event": "best_streak", "target": 5, "rep": 35, "coins": 50},
	{"id": "defeat_boss", "title": "斩首竹林统领", "desc": "本局击败 B 区竹林总坛首领（铁面词卫或玄铁词尊）", "event": "boss_defeated", "target": 1, "rep": 50, "coins": 70},
	{"id": "defeat_warden", "title": "静步破音石卫", "desc": "本局击败烟霞古洞「古洞循音石卫」", "event": "warden_defeated", "target": 1, "rep": 55, "coins": 80},
]

var game
var rng := RandomNumberGenerator.new()
var skill_cooldown_left: float = 0.0
var slam_uses_run: int = 0
var knocked_down_run: int = 0
var shockwaves: Array = []

# Camp Liaison NPC ('陈向导') for Formal Combat & Practice Camp (hidden during Prologue)
var camp_npc_node: Node3D
var active_bounty: Dictionary = {}
var bounty_progress: int = 0
var bounty_done: bool = false
var bounty_rerolled: bool = false

# Modal UI for Ranger & Camp Liaison Bounty Board
var busy: bool = false
var modal_overlay: Control
var modal_title: Label
var modal_ranger_body: Label
var modal_bounty_body: Label
var modal_reroll_btn: Button
var modal_status: Label

func setup(g):
	game = g
	rng.randomize()
	_build_camp_npc()
	_build_modal_ui()
	reset_for_run(false, false)

func _build_camp_npc():
	camp_npc_node = Node3D.new()
	camp_npc_node.name = "CampBountyGuideNPC"
	var at: Vector3 = game.Layout.on_ground(game.Layout.SPAWN + Vector3(3.6, 0.0, -2.3))
	camp_npc_node.position = at
	camp_npc_node.rotation.y = -0.78
	camp_npc_node.set_meta("camp_bounty_npc", true)
	add_child(camp_npc_node)

	# Stylized Jiangnan ranger liaison silhouette standing neatly beside Camp Command Tent
	var coat_mat := StandardMaterial3D.new()
	coat_mat.albedo_color = Color("2b5a4d")
	coat_mat.roughness = 0.72
	var scarf_mat := StandardMaterial3D.new()
	scarf_mat.albedo_color = Color("d8a948")
	scarf_mat.roughness = 0.55
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color("e8c4a2")
	skin_mat.roughness = 0.62
	var boot_mat := StandardMaterial3D.new()
	boot_mat.albedo_color = Color("2b2623")
	boot_mat.roughness = 0.85

	for lx in [-0.14, 0.14]:
		var leg: MeshInstance3D = game._mesh_box(camp_npc_node, Vector3(lx, 0.42, 0), Vector3(0.18, 0.84, 0.20), Color("2b2623"), false)
		leg.material_override = boot_mat
	var torso: MeshInstance3D = game._mesh_box(camp_npc_node, Vector3(0, 1.14, 0), Vector3(0.50, 0.64, 0.28), Color("2b5a4d"), false)
	torso.material_override = coat_mat
	var scarf: MeshInstance3D = game._mesh_box(camp_npc_node, Vector3(0, 1.44, 0.02), Vector3(0.54, 0.12, 0.32), Color("d8a948"), false)
	scarf.material_override = scarf_mat
	var head: MeshInstance3D = game._mesh_box(camp_npc_node, Vector3(0, 1.66, 0), Vector3(0.30, 0.30, 0.30), Color("e8c4a2"), false)
	head.material_override = skin_mat
	var brim: MeshInstance3D = game._mesh_box(camp_npc_node, Vector3(0, 1.82, 0.03), Vector3(0.52, 0.05, 0.48), Color("28473c"), false)
	brim.material_override = coat_mat

	var beacon := MeshInstance3D.new()
	var b_cyl := CylinderMesh.new()
	b_cyl.top_radius = 0.46
	b_cyl.bottom_radius = 0.48
	b_cyl.height = 0.05
	beacon.mesh = b_cyl
	beacon.position.y = 0.03
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("ffd15c")
	bmat.emission_enabled = true
	bmat.emission = Color("ffd15c")
	bmat.emission_energy_multiplier = 0.65
	beacon.material_override = bmat
	camp_npc_node.add_child(beacon)

	var lbl: Label3D = game._label3d(camp_npc_node, "陈向导 · 烟山委托与游侠档案\n[F] 查看名望委托", Vector3(0, 2.26, 0), 26, Color("ffd87a"))
	lbl.pixel_size = 0.0052
	lbl.visibility_range_end = 18.0

func _build_modal_ui():
	modal_overlay = Control.new()
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(modal_overlay)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.045, 0.055, 0.90)
	modal_overlay.add_child(veil)

	game._panel(modal_overlay, Rect2(190, 82, 900, 556), Color(0.04, 0.09, 0.112, 0.98), Color("ffd15c"))
	modal_title = game._text(modal_overlay, "🧭 陈向导 · 游侠小队与烟山名望委托", Vector2(224, 102), Vector2(680, 38), 25, Color("ffd15c"))
	game._button(modal_overlay, "返回行动 [Esc]", Rect2(918, 102, 140, 38), close_npc_modal)

	game._panel(modal_overlay, Rect2(224, 152, 832, 178), Color(0.06, 0.12, 0.14, 0.95), Color("8de8c0"))
	modal_ranger_body = game._text(modal_overlay, "", Vector2(242, 164), Vector2(796, 156), 15, game.CREAM)
	modal_ranger_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	game._panel(modal_overlay, Rect2(224, 344, 832, 186), Color(0.09, 0.085, 0.045, 0.95), Color("ffd15c"))
	modal_bounty_body = game._text(modal_overlay, "", Vector2(242, 356), Vector2(796, 122), 16, Color("fff0c8"))
	modal_bounty_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	modal_reroll_btn = game._button(modal_overlay, "更换本局委托（限 1 次）", Rect2(242, 480, 236, 36), _reroll_bounty)
	modal_status = game._text(modal_overlay, "", Vector2(224, 544), Vector2(832, 74), 14, Color("9ec8b9"))
	modal_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_overlay.hide()

func active_ranger_id() -> String:
	game.rules.ensure_ranger_profile()
	var rid := str(game.rules.profile.get("active_ranger", "shaoyu"))
	return rid if RANGERS.has(rid) else "shaoyu"

func active_ranger() -> Dictionary:
	return RANGERS[active_ranger_id()]

func reputation() -> int:
	game.rules.ensure_ranger_profile()
	return int(game.rules.profile.get("reputation", 0))

func reputation_rank() -> String:
	var r := reputation()
	if r >= 900:
		return "烟山宗师"
	if r >= 600:
		return "烟山名宿"
	if r >= 300:
		return "青竹侠客"
	if r >= 100:
		return "巡岭游侠"
	return "初入烟山"

func is_card_unlocked(card_id: String) -> bool:
	game.rules.ensure_ranger_profile()
	if card_id == "shaoyu":
		return true
	if card_id == "tingfeng" and reputation() >= 300:
		return true
	if card_id == "qinghe" and reputation() >= 600:
		return true
	return card_id in game.rules.profile.character_cards

func unlocked_card_count() -> int:
	var n := 0
	for c in CHARACTER_CARDS:
		if is_card_unlocked(str(c.id)):
			n += 1
	return n

func unlock_card(card_id: String, announce: bool = true) -> bool:
	game.rules.ensure_ranger_profile()
	var valid := false
	var card_name := card_id
	for c in CHARACTER_CARDS:
		if str(c.id) == card_id:
			valid = true
			card_name = str(c.name)
			break
	if not valid:
		return false
	if card_id in game.rules.profile.character_cards:
		return false
	game.rules.profile.character_cards.append(card_id)
	if announce and is_instance_valid(game):
		game._notice("📖 解锁人物小记：【%s】！可在「图鉴 → 人物小记」查阅" % card_name, Color("ffd87a"))
	return true

func reset_for_run(is_combat: bool, is_prologue: bool):
	skill_cooldown_left = 0.0
	slam_uses_run = 0
	knocked_down_run = 0
	bounty_progress = 0
	bounty_done = false
	bounty_rerolled = false
	for sw in shockwaves:
		if is_instance_valid(sw.node):
			sw.node.queue_free()
	shockwaves.clear()
	if is_instance_valid(camp_npc_node):
		camp_npc_node.visible = not is_prologue
	if is_combat and not is_prologue:
		active_bounty = BOUNTY_POOL[rng.randi_range(0, BOUNTY_POOL.size() - 1)].duplicate(true)
	else:
		active_bounty = {}
	if busy:
		close_npc_modal()

func _reroll_bounty():
	if not busy or bounty_done or bounty_rerolled or active_bounty.is_empty():
		return
	bounty_rerolled = true
	var cur_id := str(active_bounty.get("id", ""))
	var candidates: Array = []
	for b in BOUNTY_POOL:
		if str(b.id) != cur_id:
			candidates.append(b)
	if not candidates.is_empty():
		active_bounty = candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)
		bounty_progress = 0
	game.play_sfx("cipher_unlock", -13)
	_refresh_modal_text()

func open_npc_modal():
	if busy or not is_instance_valid(modal_overlay):
		return
	unlock_card("chen_guide", false)
	busy = true
	game.paused = true
	game.player.active = false
	game.player.clear_movement_input()
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_modal_text()
	modal_overlay.show()

func close_npc_modal():
	if not busy:
		return
	busy = false
	modal_overlay.hide()
	game.paused = false
	game.player.active = true
	game.player.clear_movement_input()
	game.hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_modal_text():
	var r: Dictionary = active_ranger()
	modal_ranger_body.text = (
		"当前出战游侠：【%s · %s】  |  烟山名望：%d（%s）  |  已完成委托：%d\n" +
		"主动技能 [%s] %s（冷却 %.0f 秒 · 半径 %.1fm）：%s\n" +
		"被动特质：%s\n" +
		"后续招募预告（v0.9.0）：林听风（名望 300）· 苏青禾（名望 600）· 竹影（名望 900）"
	) % [
		str(r.name), str(r.title), reputation(), reputation_rank(), int(game.rules.profile.get("bounties_completed", 0)),
		str(r.skill_key), str(r.skill_name), float(r.skill_cooldown), float(r.skill_radius), str(r.skill_desc),
		str(r.passive_desc)
	]
	if active_bounty.is_empty():
		modal_bounty_body.text = "当前为自由靶场练习模式：可随时按 [V] 演练少羽「天生神力」重拳震地！\n进入「普通行动」或「机密行动」后，陈向导将为你派发每日烟山名望委托。"
		modal_reroll_btn.hide()
	else:
		var tgt := int(active_bounty.get("target", 1))
		var st_str := "✓ 已完成并入账！" if bounty_done else ("进行中（%d / %d）" % [mini(bounty_progress, tgt), tgt])
		modal_bounty_body.text = (
			"本局烟山随机委托：【%s】 — %s\n" +
			"任务目标：%s\n" +
			"完成奖励：+%d 烟山名望  ·  +%d 行动币"
		) % [
			str(active_bounty.title), st_str, str(active_bounty.desc),
			int(active_bounty.rep), int(active_bounty.coins)
		]
		modal_reroll_btn.visible = not bounty_done
		modal_reroll_btn.disabled = bounty_rerolled
		modal_reroll_btn.text = "本局已更换过委托" if bounty_rerolled else "更换本局委托（限 1 次）"
	modal_status.text = "提示：击败雾隐帮营地、铁面词卫、玄铁词尊或古洞循音石卫，均会在营地「图鉴 → 人物小记」解锁专属角色卡！"

func record_bounty_progress(event_key: String, amount: int = 1, set_max: bool = false):
	if not game.rules.combat_mode or game.rules.prologue_mode:
		return
	if active_bounty.is_empty() or bounty_done:
		return
	if str(active_bounty.get("event", "")) != event_key:
		return
	if set_max:
		bounty_progress = maxi(bounty_progress, amount)
	else:
		bounty_progress += amount
	var tgt := int(active_bounty.get("target", 1))
	if bounty_progress >= tgt:
		bounty_done = true
		var rep_gain := int(active_bounty.get("rep", 30))
		var coin_gain := int(active_bounty.get("coins", 40))
		game.rules.ensure_ranger_profile()
		game.rules.profile["reputation"] = int(game.rules.profile.get("reputation", 0)) + rep_gain
		game.rules.profile["bounties_completed"] = int(game.rules.profile.get("bounties_completed", 0)) + 1
		game.rules.profile.coins += coin_gain
		game.play_sfx("achievement_unlock", -8)
		game._notice("★ 完成陈向导委托【%s】！+%d 烟山名望 · +%d 行动币（当前名望 %d）" % [
			str(active_bounty.title), rep_gain, coin_gain, reputation()
		], Color("ffd86b"))

func bounty_hud_line() -> String:
	if active_bounty.is_empty():
		return ""
	var tgt := int(active_bounty.get("target", 1))
	if bounty_done:
		return "委托✓ %s" % str(active_bounty.title)
	return "委托：%s (%d/%d)" % [str(active_bounty.title), mini(bounty_progress, tgt), tgt]

func can_use_skill() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(game.player):
		return false
	if game.paused or game.rules.phase not in ["active", "extracting"]:
		return false
	return skill_cooldown_left <= 0.001

func activate_skill() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(game.player):
		return false
	if game.paused or game.rules.phase not in ["active", "extracting"]:
		return false
	var r: Dictionary = active_ranger()
	if skill_cooldown_left > 0.001:
		game.play_sfx("dry_fire", -14)
		game._notice("⏳ %s【%s】冷却中（剩余 %.1f 秒）" % [str(r.name), str(r.skill_name), skill_cooldown_left], Color("ffd27d"))
		return false

	skill_cooldown_left = float(r.skill_cooldown)
	slam_uses_run += 1
	if is_instance_valid(game.player.weapon_view) and game.player.weapon_view.has_method("trigger_ground_slam"):
		game.player.weapon_view.trigger_ground_slam()
	game.play_sfx("skill_slam", -7)
	game.player.add_screen_shake(0.42)
	var origin: Vector3 = game.Layout.on_ground(game.player.position)
	var fwd_flat: Vector3 = -game.player.camera.global_basis.z
	fwd_flat.y = 0.0
	var vfx_origin: Vector3 = game.Layout.on_ground(origin + (fwd_flat.normalized() * 1.45 if fwd_flat.length_squared() > 0.01 else Vector3.ZERO))
	_spawn_ground_slam_vfx(vfx_origin, float(r.skill_radius))

	var knocked := 0
	var staggered_bosses := 0
	var rad := float(r.skill_radius)
	var dur := float(r.skill_duration)

	# 1) Knock down nearby Mistbound word soldiers (1.5s knockdown) & stagger Bosses (1.2s)
	if is_instance_valid(game.combat) and game.combat.in_field():
		for z_key in game.combat.troops.keys():
			if game.combat.zone_cleared.get(z_key, false):
				continue
			for s in game.combat.troops[z_key]:
				if not is_instance_valid(s) or s.defeated:
					continue
				var flat_d := Vector2(s.position.x - origin.x, s.position.z - origin.z).length()
				if flat_d > rad:
					continue
				var away := Vector3(s.position.x - origin.x, 0.0, s.position.z - origin.z)
				if away.length_squared() < 0.04:
					away = -game.player.camera.global_basis.z
					away.y = 0.0
				away = away.normalized()
				if s.archetype == s.Archetype.BOSS_WARDEN:
					s.stun(1.2)
					staggered_bosses += 1
				elif s.has_method("apply_knockdown"):
					s.apply_knockdown(dur, away * 3.8)
					knocked += 1
				else:
					s.stun(dur)
					knocked += 1

	# 2) v0.8.5: Briefly jolt Yanxia Cave Acoustic Warden's arm-shields open for 1.0s (NO stun!) if within shockwave range!
	if is_instance_valid(game.cave_warden) and game.cave_warden.is_alive():
		var cw_pos: Vector3 = game.cave_warden.root_node.position
		var cw_d := Vector2(cw_pos.x - origin.x, cw_pos.z - origin.z).length()
		if cw_d <= rad + 0.8:
			game.cave_warden.force_open_arms(1.0)
			staggered_bosses += 1
		elif cw_d <= 15.0:
			game.cave_warden.register_noise(origin, 42.0, true)

	knocked_down_run += knocked
	if knocked > 0:
		record_bounty_progress("slam_enemies", knocked)
	if is_instance_valid(game.achievements):
		game.achievements.record_stat("skill_slams_used", 1)
		if knocked > 0:
			game.achievements.record_stat("enemies_knocked_down", knocked)

	game.screen_flash.color = Color(1.0, 0.82, 0.36, 0.14)
	if knocked > 0 or staggered_bosses > 0:
		var parts: Array[String] = []
		if knocked > 0:
			parts.append("震倒 %d 名词兵（%.1f秒）" % [knocked, dur])
		if staggered_bosses > 0:
			parts.append("震慑强敌 %d 名" % staggered_bosses)
		game._notice("⚡ 少羽发动【%s】！%s · 冷却 %.0f 秒" % [str(r.skill_name), "、".join(parts), float(r.skill_cooldown)], Color("ffd86b"))
	else:
		game._notice("⚡ 少羽发动【%s】重拳震地！（周围 %.0fm 暂无敌人 · 冷却 %.0f 秒）" % [str(r.skill_name), rad, float(r.skill_cooldown)], Color("ffd86b"))
	return true

func _spawn_ground_slam_vfx(center: Vector3, max_radius: float):
	var root := Node3D.new()
	root.position = center + Vector3(0.0, 0.22, 0.0)
	add_child(root)

	# Outer expanding golden-earth shockwave torus ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.78
	tm.outer_radius = 1.00
	tm.rings = 20
	tm.ring_segments = 12
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.86, 0.28, 0.94)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.78, 0.20)
	rmat.emission_energy_multiplier = 2.0
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	ring.scale = Vector3(0.75, 0.95, 0.75)
	root.add_child(ring)

	# Inner cracked-earth impact disc
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.06
	disc.mesh = cm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.95, 0.70, 0.26, 0.42)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dmat
	disc.scale = Vector3(0.6, 1.0, 0.6)
	root.add_child(disc)

	# 8 radial stone-dust impact bursts rising around the fist crater
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.84, 0.76, 0.58, 0.68)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.roughness = 0.95
	var pebbles: Array = []
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var p := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.24, 0.24)
		p.mesh = bm
		p.material_override = dust_mat
		p.position = Vector3(cos(ang) * 0.75, 0.14, sin(ang) * 0.75)
		p.rotation = Vector3(ang, ang * 0.7, 0.4)
		root.add_child(p)
		pebbles.append({"node": p, "dir": Vector3(cos(ang), 0.0, sin(ang))})

	shockwaves.append({
		"node": root,
		"ring": ring,
		"rmat": rmat,
		"disc": disc,
		"dmat": dmat,
		"dust_mat": dust_mat,
		"pebbles": pebbles,
		"max_r": max_radius,
		"elapsed": 0.0,
		"duration": 0.62,
	})

func update(delta: float):
	if not game.paused and skill_cooldown_left > 0.0:
		skill_cooldown_left = maxf(0.0, skill_cooldown_left - delta)

	for i in range(shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = shockwaves[i]
		sw.elapsed = float(sw.elapsed) + delta
		var t := clampf(float(sw.elapsed) / float(sw.duration), 0.0, 1.0)
		if t >= 1.0:
			if is_instance_valid(sw.node):
				sw.node.queue_free()
			shockwaves.remove_at(i)
			continue
		var ease_out := 1.0 - pow(1.0 - t, 2.8)
		var r_now := lerpf(0.65, float(sw.max_r), ease_out)
		if is_instance_valid(sw.ring):
			sw.ring.scale = Vector3(r_now, maxf(0.18, 0.72 * (1.0 - t)), r_now)
		(sw.rmat as StandardMaterial3D).albedo_color.a = (1.0 - t) * 0.90
		if is_instance_valid(sw.disc):
			sw.disc.scale = Vector3(r_now * 0.96, 1.0, r_now * 0.96)
		(sw.dmat as StandardMaterial3D).albedo_color.a = (1.0 - t) * 0.42
		(sw.dust_mat as StandardMaterial3D).albedo_color.a = (1.0 - t) * 0.68
		for pb in sw.pebbles:
			var nd: MeshInstance3D = pb.node
			var dv: Vector3 = pb.dir
			if is_instance_valid(nd):
				var hop_y := sin(t * PI) * 1.45 + 0.12
				nd.position = dv * lerpf(0.75, float(sw.max_r) * 0.62, ease_out) + Vector3(0.0, hop_y, 0.0)
				nd.rotation += Vector3(4.2, 3.1, 2.6) * delta
				nd.scale = Vector3.ONE * lerpf(1.0, 0.35, t)
