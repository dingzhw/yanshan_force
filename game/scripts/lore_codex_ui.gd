extends Node
## Standalone Multi-Faction Character Lore Codex UI ('角色小传' — v0.9.6).
## - Unidentified / Locked Characters display a sleek tactical '?' silhouette portrait (locked_mystery.png)
##   and classified nameplate ('???') until their Chapter I unlock milestone is achieved!
## - Once unlocked, the character's full high-res 3D portrait is revealed on both Page 1 (Faction Hub)
##   and Page 2 (Dedicated Character Dossier: Left Portrait + Right 4-Stage Progressive Chronicles).
## - Styled with sharp modern gunmetal / mechanical tactical military UI chrome.

const PORTRAIT_DIR := "res://assets/portraits/"
const LOCKED_PORTRAIT_PATH := "res://assets/portraits/locked_mystery.png"

const FACTIONS := [
	{
		"id": "rangers",
		"code": "FAC-01",
		"name": "烟山游侠小队",
		"short": "烟山游侠",
		"en": "YANSHAN RANGERS",
		"color": Color("3ef0b4"),
		"bg": Color(0.04, 0.095, 0.090, 0.96),
		"desc": "扎根诚庄山麓与江南竹海的少年巡护游侠们。通过持续派遣游侠出击、施展专属技能、解锁成就与深入不同战区场景，逐步解锁全部游侠形象与成长密档。",
		"unlock_rule": "推进方式：派遣少羽出战、施展 [V] 天生神力、解锁成就、探访序章/烟山/古洞/阿萨拉多处场景、积攒烟山名望。",
		"members": ["shaoyu", "chen_guide", "tingfeng", "qinghe", "zhuying"],
	},
	{
		"id": "mistbound",
		"code": "FAC-02",
		"name": "雾隐帮与古洞秘境",
		"short": "雾隐帮",
		"en": "MISTBOUND SYNDICATE & CAVE",
		"color": Color("ff5c5c"),
		"bg": Color(0.11, 0.045, 0.052, 0.96),
		"desc": "借江南山雾潜入烟山的神秘武装帮派，以及沉眠于烟霞古洞千年的听声石卫。清剿山林营地、击败铁面词卫、玄铁词尊与古洞石卫，即可揭露敌首真容并层层解封密档。",
		"unlock_rule": "推进方式：肃清烟山雾隐营地、无错破译密电箱、击败铁面词卫/玄铁词尊/古洞石卫、搜集江南遗珍。",
		"members": ["mistbound_soldier", "vanguard_boss", "skyfall_overlord", "cave_warden"],
	},
	{
		"id": "ahsarah",
		"code": "FAC-03",
		"name": "阿萨拉卫队",
		"short": "阿萨拉卫队",
		"en": "AHSARAH GUARD",
		"color": Color("ffa938"),
		"bg": Color(0.12, 0.080, 0.040, 0.96),
		"desc": "2035 年盘踞北非零号大坝与巴克什沙丘的本土部族游击武装，由孤狼猎手「赤枭·赛伊德」与旧贵族军阀「雷斯」各据险要。踏入阿萨拉堡垒并逐一击败强敌即可揭晓其真实形象与档案。",
		"unlock_rule": "推进方式：解锁并进军阿萨拉堡垒、清剿沙漠哨所、击败赤枭·赛伊德与军阀·雷斯、带出阿萨拉珍宝。",
		"members": ["ahsarah_guard", "saeed_fiery_owl", "reis_warlord"],
	},
	{
		"id": "haavk",
		"code": "FAC-04",
		"name": "哈夫克集团（HAAVK）",
		"short": "哈夫克集团",
		"en": "HAAVK CORPORATION",
		"color": Color("3ce2ff"),
		"bg": Color(0.04, 0.085, 0.130, 0.96),
		"desc": "修建零号大坝与巴别通讯塔的跨国科技财团，派出全白高能装甲特勤守卫东区变电站，并暗中推行「曼德尔加密砖」量子语言计划。突袭变电站、破译加密砖与精进词库即可解密绝密文件。",
		"unlock_rule": "推进方式：进军阿萨拉、突袭东区变电站、成功破译曼德尔加密砖、稳步提升英语词汇掌握量。",
		"members": ["haavk_trooper", "mandel_protocol"],
	},
]

const DOSSIERS := {
	# ===================== 烟山游侠小队 (5) =====================
	"shaoyu": {
		"id": "shaoyu",
		"faction": "rangers",
		"name": "游侠 · 少羽",
		"hidden_title": "代号：破阵少年",
		"en": "SHAOYU · VANGUARD RANGER",
		"role": "破阵游侠 · 默认出战主角",
		"quote": "「风过烟山竹梢时，每一道英语密电我都听得一清二楚！」",
		"tactical": "专属 [V] 技能「天生神力」：重拳震地冲击波将周围 7.8m 词兵震倒 1.5 秒（30s CD），对首领与古洞石卫触发硬直打断。",
		"chapters": [
			{
				"title": "档案 I · 竹林少年与赤红围巾",
				"cond": {"type": "always"},
				"text": "少羽生于诚庄山麓的竹编匠人家中，自小翻越东岭茶坡、听着鸟鸣与私塾晨读长大。脖颈间那条朱红长围巾，是离家执行首次巡山任务前外婆亲手织就的护身信物；每当山风卷起红巾，乡亲们就知道烟山最靠谱的小游侠又出发了。",
			},
			{
				"title": "档案 II · 实战砺锋：天生神力",
				"cond": {"type": "lore_stat", "key": "shaoyu_runs", "target": 2, "label": "派遣少羽出击累计 2 局"},
				"text": "初入实战时，雾隐帮企图借密集词兵近身包抄逼退这名年轻游侠。危机关头，少羽凭借常年挑柴劈竹炼出的惊人臂力猛击青石地面，硬生生震翻整队词盾巡逻兵——这一记「天生神力」从此成为烟山营地人人称道的破阵绝技。",
			},
			{
				"title": "档案 III · 勋章淬炼与双线历练",
				"cond": {"type": "combo", "parts": [
					{"type": "achievements", "target": 3, "label": "解锁至少 3 项烟山成就"},
					{"type": "scenes_count", "target": 2, "label": "探访至少 2 处不同战区/场景"},
				], "label": "解锁 3 项成就且探访 2 处不同场景"},
				"text": "随着战功勋章一枚枚挂上 YS-04 卡宾枪侧轨，少羽的脚步不再局限于山脚营地。从迷雾缭绕的烟霞古洞一线天，到万里之外风沙呼啸的零号大坝，这副琥珀防风护目镜见证了他从青涩守林少年蜕变为独当一面的双语特战游侠。",
			},
			{
				"title": "档案 IV · 烟山之誓（终极密档）",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "shaoyu_skill_uses", "target": 5, "label": "累计施展 [V] 天生神力 5 次"},
					{"type": "extractions", "target": 3, "label": "累计成功撤离 3 局"},
				], "label": "累计使用 [V] 技能 5 次并成功撤离 3 局"},
				"text": "少羽的背包夹层里藏着一本翻得卷边的手写英文单词本，扉页用炭笔写着一行小字：『守得住家乡山水，也看得懂更大世界』。无论面对玄铁词尊还是远赴阿萨拉沙漠，他始终坚信：真正的锋芒不止在枪口，更在清醒的头脑与永不退缩的担当。",
			},
		],
	},
	"chen_guide": {
		"id": "chen_guide",
		"faction": "rangers",
		"name": "陈向导 · 营地联络官",
		"hidden_title": "待解锁 · 营地老联络官",
		"en": "GUIDE CHEN · CAMP LIAISON",
		"role": "资深山林巡护员 · 委托发布者",
		"quote": "「出门前记得清点弹药与单词本——老陈在山脚帐篷煮好茶等你回来。」",
		"tactical": "驻守营地指挥帐篷旁：按 [F] 接取/刷新今日烟山名望委托，并在序章亲自指导新游侠完成首次搜撤演练。",
		"chapters": [
			{
				"title": "档案 I · 三十年烟山活地图",
				"cond": {"type": "any", "parts": [
					{"type": "scene", "scene": "prologue", "label": "完成序章或与陈向导对话"},
					{"type": "lore_stat", "key": "shaoyu_runs", "target": 1, "label": "派遣少羽出击 1 局"},
				], "label": "完成序章、与陈向导对话或出击任意 1 局"},
				"text": "陈向导在烟山巡护了整整三十年，山中哪条溪谷雨后涨水、哪块青石板下藏着先民古碑，他闭着眼睛都能画出来。胸前那副磕掉漆的军绿双筒望远镜，陪他走过了半生风霜。",
			},
			{
				"title": "档案 II · 诚庄初行引路人",
				"cond": {"type": "scene", "scene": "prologue", "label": "完成剧情模式《烟山初行·序章》或与陈向导完成联络"},
				"text": "雾隐帮悄然渗入烟山那年，正是陈向导最先截获了伪装成英文气象码的无线电信号。他连夜在山脚空地搭起前哨指挥帐，将少羽等年轻游侠组织起来，一字一句教他们如何把英语听读化作破盾利器。",
			},
			{
				"title": "档案 III · 名望簿上的秘密",
				"cond": {"type": "bounties", "target": 1, "label": "完成任意 1 项陈向导营地委托"},
				"text": "外人只道陈向导手里的名望登记簿记录着奖赏与行动币，却很少有人知道，每当游侠带回一件散落山野的诚庄古瓷或竹简，老陈都会悄悄拍照编目，盼着风波平息那天全部还给村里的乡土陈列馆。",
			},
			{
				"title": "档案 IV · 远方的老战友",
				"cond": {"type": "reputation", "target": 150, "label": "累计获得 150 点「烟山名望」"},
				"text": "深夜独坐帐前时，老陈偶尔会调到一个加密短波频道——那里传来阿萨拉沙漠的风沙杂音。原来他年轻时曾参与过海外水利科考，零号大坝动工前的原始水文图纸，至今仍有一份副本压在他的茶罐底下。",
			},
		],
	},
	"tingfeng": {
		"id": "tingfeng",
		"faction": "rangers",
		"name": "林听风 · 听风斥候",
		"hidden_title": "待解锁 · 东岭观风斥候",
		"en": "LIN TINGFENG · RECON RANGER",
		"role": "远距侦察游侠 · 望稻亭观风手",
		"quote": "「竹叶响动偏西三寸——两百米外有侦察蜂压低高度摸过来了。」",
		"tactical": "【预告技能】听风鹰眼：短时高亮远距营地与弱点词盾，提升开镜稳瞄与听音辨位精度。",
		"chapters": [
			{
				"title": "档案 I · 望稻亭上的观风客",
				"cond": {"type": "any", "parts": [
					{"type": "lore_stat", "key": "camps_cleared_yanshan", "target": 1, "label": "肃清烟山营地 1 座"},
					{"type": "reputation", "target": 50, "label": "烟山名望达 50 点"},
				], "label": "在烟山肃清 1 座营地或名望达 50 点"},
				"text": "高束墨发、身披青碧轻甲风衣的青年斥候，常年驻守东岭望稻亭制高点。他极少高声交谈，却能凭山风掠过竹林的频率分辨出百米外巡逻队的脚步轻重。",
			},
			{
				"title": "档案 II · 声学单筒镜的来历",
				"cond": {"type": "lore_stat", "key": "camps_cleared_yanshan", "target": 3, "label": "在烟山行动中累计肃清 3 座雾隐营地"},
				"text": "林听风手中那具银灰光学测距镜并非制式军品，而是他用废旧气象测风仪与望远镜亲手拼装的宝贝。烟山每一座雾隐营地的布防草图，大半都出自他黎明前的静默测绘。",
			},
			{
				"title": "档案 III · 严苛的校准习惯",
				"cond": {"type": "achievements", "target": 5, "label": "累计解锁 5 项成就"},
				"text": "少羽爱冲阵、听风爱算风。两人联手清剿东岭哨所时曾打赌谁的命中率更高，结果听风在八十米外连续十枪精准击碎移动词盾，只留下一句『别急着扣扳机，先听清重音节』。",
			},
			{
				"title": "档案 IV · 风起名望时",
				"cond": {"type": "reputation", "target": 300, "label": "累计「烟山名望」达 300 点"},
				"text": "当烟山名望突破三百大关，林听风终于在营地名册上签下了自己的代号。他向陈向导承诺，待下阶段战线向诚庄河港与外围延伸时，他愿作为游侠小队第二名常驻出战干员亲自压阵。",
			},
		],
	},
	"qinghe": {
		"id": "qinghe",
		"faction": "rangers",
		"name": "苏青禾 · 悬壶游侠",
		"hidden_title": "待解锁 · 战地青囊医者",
		"en": "SU QINGHE · FIELD MEDIC",
		"role": "战地医疗游侠 · 本草通识者",
		"quote": "「护盾碎了别硬扛！深呼吸，喝口山泉草药饮就能再战三回合。」",
		"tactical": "【预告技能】青囊脉冲：瞬发纳米护盾急救波，回复护盾生命并大幅加速战术换弹。",
		"chapters": [
			{
				"title": "档案 I · 茶田畔的青囊少女",
				"cond": {"type": "any", "parts": [
					{"type": "extractions", "target": 1, "label": "成功撤离 1 局"},
					{"type": "collection", "target": 2, "label": "收藏 2 件高阶遗珍"},
				], "label": "累计成功撤离 1 局或收藏 2 件高阶遗珍"},
				"text": "出身江南中医世家的苏青禾，发髻总系着一缕翠绿竹丝带。白绿相间的轻便医疗战服上嵌着发光纳米急救匣，在漫山梯田间既像采茶姑娘，又是伤员眼中最安心的微光。",
			},
			{
				"title": "档案 II · 能量饮的神秘配方",
				"cond": {"type": "collection", "target": 4, "label": "在奇珍图鉴中累计收藏 4 件高阶遗珍"},
				"text": "营地里人人爱用的战术能量饮，其实经过了苏青禾的私房改良——她在电解质里添了几滴烟山明前茶露与薄荷草精，既提神又解乏，连一向挑剔的林听风都悄悄多塞了两罐进背囊。",
			},
			{
				"title": "档案 III · 逆风救场手记",
				"cond": {"type": "extractions", "target": 4, "label": "累计成功撤离 4 局"},
				"text": "她的随身笔记本一半画着烟山八大奇植手绘图谱，另一半写满英文医学与急救词根。她说，多记住一个英文词，危急时就能更快读懂敌方缴获仪器的操作面板，救回更多同伴。",
			},
			{
				"title": "档案 IV · 青囊出山约",
				"cond": {"type": "reputation", "target": 600, "label": "累计「烟山名望」达 600 点"},
				"text": "眼看战事已蔓延至荒漠古堡，苏青禾连夜升级了「青囊脉冲」便携发生器，专门针对沙漠高温与燃烧弹灼伤调校了冷却喷雾，随时准备奔赴最危险的前线。",
			},
		],
	},
	"zhuying": {
		"id": "zhuying",
		"faction": "rangers",
		"name": "竹影 · 踏雾潜行者",
		"hidden_title": "待解锁 · 深林潜行暗影",
		"en": "ZHUYING · STEALTH RANGER",
		"role": "深林潜行游侠 · 古洞探路人",
		"quote": "「听声石卫不怕火炮，只怕连心跳都能藏进竹风里的人。」",
		"tactical": "【预告技能】竹影轻身：短时步履完全无声且大幅提升潜行移速，专克烟霞古洞循音石卫。",
		"chapters": [
			{
				"title": "档案 I · 雾中无声的墨绿斗篷",
				"cond": {"type": "any", "parts": [
					{"type": "scene", "scene": "yanshan_cave", "label": "深入烟霞古洞"},
					{"type": "lore_stat", "key": "warden_defeats", "target": 1, "label": "击败古洞循音石卫 1 次"},
					{"type": "reputation", "target": 150, "label": "烟山名望达 150 点"},
				], "label": "探访烟霞古洞、击败古洞石卫或名望达 150 点"},
				"text": "深绿连帽斗篷、半遮面的战术面罩与泛着幽紫微光的单眼微光目镜——没人见过竹影真正出声大笑的模样，只知道每当竹海起雾，她总能比任何人更早摸清敌巢虚实。",
			},
			{
				"title": "档案 II · 静步穿过一线天",
				"cond": {"type": "lore_stat", "key": "warden_defeats", "target": 1, "label": "击败烟霞古洞「古洞循音石卫」1 次"},
				"text": "古洞循音石卫曾令无数贸然闯入的探险者仓皇退走。竹影耗时七夜在寒潭岩壁旁静坐听音，终于测出石卫放弃搜寻的 1.5 秒静默窗口，并将其刻在洞口青石上留给后来者。",
			},
			{
				"title": "档案 III · 消音器的艺术",
				"cond": {"type": "lore_stat", "key": "perfect_ciphers_total", "target": 3, "label": "累计无错破译 3 个密码物资箱"},
				"text": "相比正面强攻，竹影更痴迷于「一枪不发拿走高阶密码箱」的优雅战术。她亲自为营地军械库校验了钛合金消音器的气流折板，使游侠在偷袭狙击卫时几乎不留回音。",
			},
			{
				"title": "档案 IV · 暗夜守望",
				"cond": {"type": "reputation", "target": 900, "label": "累计「烟山名望」达 900 点"},
				"text": "很少有人知道，竹影曾短暂卧底于雾隐帮外围情报站，并在玄铁词尊尚未完全苏醒前偷出核心加密协议交给陈向导。那道微光目镜后的沉静眼神，始终护着整片烟山夜空。",
			},
		],
	},

	# ===================== 雾隐帮与秘境 (4) =====================
	"mistbound_soldier": {
		"id": "mistbound_soldier",
		"faction": "mistbound",
		"name": "雾隐帮 · 词盾巡逻编队",
		"hidden_title": "待解锁 · 雾隐武装编队",
		"en": "MISTBOUND TROOPER SQUAD",
		"role": "烟山常规武装 · 突击/侦察/狙击三栖编队",
		"quote": "「别让他们抢走烟山的宝贝！布词盾阵！」",
		"tactical": "按顶部英文/中文提示锁敌：爆头一枪清，词盾两枪破；遇包围时用 [V] 天生神力震倒整队！",
		"chapters": [
			{
				"title": "档案 I · 突入江南的神秘黑影",
				"cond": {"type": "lore_stat", "key": "camps_cleared_yanshan", "target": 1, "label": "在烟山行动中肃清 1 座雾隐帮营地"},
				"text": "身着暗青复合甲、面罩泛着幽蓝冷光的雾隐帮巡逻兵，趁着梅雨山雾潜入诚庄外围。他们迅速在古桥、竹林与山坡筑起沙袋哨所，四处挖掘诚庄先民遗留的青瓷与古玉。",
			},
			{
				"title": "档案 II · 全息词盾的运行破绽",
				"cond": {"type": "lore_stat", "key": "camps_cleared_yanshan", "target": 2, "label": "在烟山行动中累计肃清 2 座雾隐营地"},
				"text": "经游侠缴获残片分析，雾隐帮手腕上的全息能量盾由英文高频密令维持稳定。只要精准辨别出目标词条并击中对应士兵，能量共振便会瞬间瓦解护盾；反之打错词条则会诱发其过载狂暴。",
			},
			{
				"title": "档案 III · 三兵种协同阵型",
				"cond": {"type": "lore_stat", "key": "camps_cleared_yanshan", "target": 4, "label": "在烟山行动中累计肃清 4 座雾隐营地"},
				"text": "随着交火深入，雾隐帮开始派出突击兵正面压迫、轻甲侦察蜂高速绕侧、红激光狙击卫高点锁头。一旦发现红线瞄准，立刻利用竹林掩体或 [Q]/[E] 侧身探头反狙是唯一正解。",
			},
			{
				"title": "档案 IV · 雇主迷云",
				"cond": {"type": "lore_stat", "key": "perfect_ciphers_total", "target": 5, "label": "累计无错破译 5 个密码箱"},
				"text": "从营地电台破译出的账本碎片显示，雾隐帮的词盾芯片并非土法制造，其底层接口编号竟与阿萨拉东区变电站的哈夫克测试批次完全吻合——江南山雾之下，藏着跨越半个地球的隐秘交易。",
			},
		],
	},
	"vanguard_boss": {
		"id": "vanguard_boss",
		"faction": "mistbound",
		"name": "铁面词卫 · 雾隐先锋",
		"hidden_title": "待解锁 · B 区重甲首领",
		"en": "IRONFACE VANGUARD",
		"role": "普通行动 · B 区竹林总坛首领",
		"quote": "「想过竹林总坛？先接下我这轮红圈重炮再说！」",
		"tactical": "720 HP 与周期性红圈重炮轰炸（半血双圈）；破词盾后集中猛打胸口赤红能量核！",
		"chapters": [
			{
				"title": "档案 I · 铁角假面下的猛兽",
				"cond": {"type": "lore_stat", "key": "ironface_defeats", "target": 1, "label": "在烟山普通行动中击败「铁面词卫」1 次"},
				"text": "镇守烟山 B 区竹林总坛的重装指挥官，头戴双角铁面、胸嵌赤红高能反应炉，单手便可端起多管旋转重机枪压制整条山脊，令普通巡护队员闻风丧胆。",
			},
			{
				"title": "档案 II · 红圈迫击火力网",
				"cond": {"type": "lore_stat", "key": "ironface_defeats", "target": 2, "label": "累计击败「铁面词卫」2 次"},
				"text": "铁面词卫在交火中最擅以 5.5 秒倒计时的红圈重炮封锁掩体，半血之后更是双圈齐落。唯有在预警圈亮起刹那果断疾跑换位、击碎其词盾暴露胸口红核，方能以弱胜强。",
			},
			{
				"title": "档案 III · 蓝图保管者",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "ironface_defeats", "target": 2, "label": "累计击败铁面词卫 2 次"},
					{"type": "lore_stat", "key": "perfect_ciphers_total", "target": 3, "label": "无错破译 3 个密码箱"},
				], "label": "击败铁面词卫 2 次且无错破译 3 个密码箱"},
				"text": "他贴身锁着雾隐帮最精良的枪械改装蓝图。每次击败铁面词卫，游侠不仅能夺下 B 区撤离加密密钥，更能顺手截获 2 倍棱镜镜、消音器或战术握把的制造图纸。",
			},
			{
				"title": "档案 IV · 傲慢的先锋末路",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "ironface_defeats", "target": 3, "label": "累计击败铁面词卫 3 次"},
					{"type": "achievements", "target": 4, "label": "累计解锁 4 项成就"},
				], "label": "累计击败铁面词卫 3 次并解锁 4 项成就"},
				"text": "据被俘雾隐小头目交代，铁面词卫原是黑市重火教官，最看不起只会背书的学生兵。直到被少年游侠少羽一次次用精准听词与天生神力掀翻在地，他才在撤离通讯里咬牙写下『启动天降玄铁预案』。",
			},
		],
	},
	"skyfall_overlord": {
		"id": "skyfall_overlord",
		"faction": "mistbound",
		"name": "玄铁词尊 · 雾隐机关王",
		"hidden_title": "待解锁 · 机密天降巨像",
		"en": "SKYFALL OVERLORD",
		"role": "机密行动 · 天降巨型五盾首领",
		"quote": "「凡铁岂能撼我玄甲！按序破阵，否则一切归零！」",
		"tactical": "匕首无效！必须严格按顶部 1→5 顺序用步枪击破 5 面连锁词盾，打错立刻怒吼回满 500 HP 并重洗顺序。",
		"chapters": [
			{
				"title": "档案 I · 云端坠落的鎏金巨像",
				"cond": {"type": "lore_stat", "key": "overlord_defeats", "target": 1, "label": "在烟山机密行动中击败「玄铁词尊」1 次"},
				"text": "高达四米的黑曜鎏金外骨骼机关巨像，背后悬浮着发光金色齿轮光轮与五面连锁能量词盾。唯有在极度危险的【机密行动】惊动 B 区总坛时，它才会撕裂云雾轰然空降。",
			},
			{
				"title": "档案 II · 五重词序铁律",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "overlord_defeats", "target": 1, "label": "击败玄铁词尊 1 次"},
					{"type": "extractions", "target": 3, "label": "累计成功撤离 3 局"},
				], "label": "击败玄铁词尊 1 次并成功撤离 3 局"},
				"text": "玄铁词尊周身五面金盾构成自修复逻辑闭环：唯有严格依循 1 至 5 的英文词汇顺序逐一击穿，才能让其金色齿轮陷入瘫痪。哪怕错开一枪，整套防御矩阵都会瞬间咆哮回能。",
			},
			{
				"title": "档案 III · 通往阿萨拉的钥匙",
				"cond": {"type": "map_ahsarah", "label": "成功解锁第二战区「阿萨拉堡垒」"},
				"text": "在玄铁词尊轰然倒地后掉落的残破导航核心里，陈向导与林听风首次破译出了一组北纬 30 度荒漠峡谷的加密坐标——指向千里之外风沙漫天的「零号大坝 · 阿萨拉堡垒」。",
			},
			{
				"title": "档案 IV · 雾隐幕后的钢铁意志",
				"cond": {"type": "lore_stat", "key": "overlord_defeats", "target": 2, "label": "累计击败「玄铁词尊」2 次"},
				"text": "拆解其残骸后发现，玄铁词尊的胸腔里并无真人驾驶舱，只有一块刻满英文语法校验环的高能主控板。它究竟是雾隐帮倾尽全力的终极杀器，还是某股海外势力在烟山投放的试作兵器？答案正藏在阿萨拉。",
			},
		],
	},
	"cave_warden": {
		"id": "cave_warden",
		"faction": "mistbound",
		"name": "古洞循音石卫",
		"hidden_title": "待解锁 · 古洞千年石卫",
		"en": "YANXIA ACOUSTIC WARDEN",
		"role": "烟霞古洞 · 千年喀斯特听声守卫",
		"quote": "「嗡——（石壁低频回响，任何急促足音都将唤醒千年石盾）」",
		"tactical": "击中胸口蓝核后会双臂护核反击！立即按 [C]/[Z] 静步潜行 1.5s 令其脱搜露核，或按 [V] 短暂震开双臂抢输出。",
		"chapters": [
			{
				"title": "档案 I · 一线天深处的沉眠巨石",
				"cond": {"type": "any", "parts": [
					{"type": "scene", "scene": "yanshan_cave", "label": "深入烟霞古洞遭遇石卫"},
					{"type": "lore_stat", "key": "warden_defeats", "target": 1, "label": "击败古洞循音石卫 1 次"},
				], "label": "深入烟霞古洞遭遇或击败「古洞循音石卫」"},
				"text": "矗立于烟霞古洞寒潭石室之间的古老机关石卫，浑身镌刻先民青蓝符纹，双目虽已风化失明，胸腔中那枚幽蓝声纹晶核却历经千年依旧熠熠跳动。",
			},
			{
				"title": "档案 II · 听声辨位与静默之道",
				"cond": {"type": "lore_stat", "key": "warden_defeats", "target": 1, "label": "击败「古洞循音石卫」1 次"},
				"text": "古洞内回声激荡，奔跑与枪响都会瞬间引来石卫举盾逼近。只有懂得放慢呼吸、蹲伏潜行的智勇游侠，才能在石卫闭合双臂的间隙悄然隐去身形，等待蓝核再度敞开。",
			},
			{
				"title": "档案 III · 破阵而出的古洞宝藏",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "warden_defeats", "target": 1, "label": "击败石卫 1 次"},
					{"type": "collection", "target": 4, "label": "收集 4 件高阶奇珍"},
				], "label": "击败石卫 1 次并收集 4 件高阶奇珍"},
				"text": "石卫并不效忠于雾隐帮——它纯粹忠实于千年前诚庄先民设下的守护契约，只将《烟山耕读》岩画与寒潭茶灶旁珍藏的秘色青瓷、先民竹简交付给兼具沉着与智慧的试炼通过者。",
			},
			{
				"title": "档案 IV · 千年声纹共鸣",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "warden_defeats", "target": 2, "label": "累计击败古洞循音石卫 2 次"},
					{"type": "collection", "target": 6, "label": "奇珍图鉴收集至少 6 件高阶奇珍"},
				], "label": "累计击败石卫 2 次并收集 6 件高阶奇珍"},
				"text": "当古洞石卫第二次颔首熄灭蓝光时，寒潭水面竟隐约映出一段古老碑铭：『喧嚣者迷途，静听者明心』。原来这座石窟既是先民避祸藏珍之所，更是一座专为磨砺少年定力而建的千年听音试炼堂。",
			},
		],
	},

	# ===================== 阿萨拉卫队 (3) =====================
	"ahsarah_guard": {
		"id": "ahsarah_guard",
		"faction": "ahsarah",
		"name": "阿萨拉卫队 · 荒漠游击兵",
		"hidden_title": "待解锁 · 荒漠红巾卫兵",
		"en": "AHSARAH GUARD SOLDIER",
		"role": "沙漠本土武装 · 水泥厂与巴克什哨所守军",
		"quote": "「来！咱俩练练！敢闯阿萨拉的地盘，别想活着把水带走！」",
		"tactical": "依托砂岩拱门、集装箱与沙袋掩体推进，交火时常伴随狂放战吼；善用高点卡视角破盾爆头。",
		"chapters": [
			{
				"title": "档案 I · 红白头巾下的荒漠骄傲",
				"cond": {"type": "map_ahsarah", "label": "解锁第二战区「阿萨拉堡垒」"},
				"text": "身着沙色作战服、颈绕经典红白格头巾的本土游击战士，世代生息在阿萨拉河谷。零号大坝截断下游水源后，无数失地青年拿起卡宾枪编入阿萨拉卫队，誓要夺回故土。",
			},
			{
				"title": "档案 II · 初抵零号大坝沙场",
				"cond": {"type": "lore_stat", "key": "ahsarah_runs", "target": 1, "label": "进入阿萨拉堡垒执行 1 次行动"},
				"text": "从湿润青翠的江南山林骤然踏入烈日灼眼的阿萨拉峡谷，风沙与热浪扑面而来。卫队士兵盘踞在水泥厂料仓、巴克什拱门集市与大坝哨塔之间，只要听见脚步声便会兴奋地喊着『咱俩练练』冲锋而来。",
			},
			{
				"title": "档案 III · 沙丘伏击战术拆解",
				"cond": {"type": "lore_stat", "key": "camps_cleared_ahsarah", "target": 2, "label": "在阿萨拉堡垒累计肃清 2 座营地"},
				"text": "与烟山雾隐帮依靠山雾隐蔽不同，阿萨拉卫队精于利用高低错落的沙丘与砖石巷道交叉火力压制。战斗中切忌停在开阔沙地硬拼，借油罐车与土墙 [Q]/[E] 闪身点射才是上策。",
			},
			{
				"title": "档案 IV · 烽烟背后的故乡歌谣",
				"cond": {"type": "lore_stat", "key": "ahsarah_runs", "target": 3, "label": "出击阿萨拉堡垒累计 3 局"},
				"text": "在一座被清剿的集市哨所篝火旁，少羽拾到半张焦黄的英文课本与手绘水源地图。许多阿萨拉卫兵本是沙漠里的修路工与商贩，他们拼命守着残破堡垒，只为等绿洲溪流再次流过巴克什的拱门。",
			},
		],
	},
	"saeed_fiery_owl": {
		"id": "saeed_fiery_owl",
		"faction": "ahsarah",
		"name": "赤枭 · 赛伊德",
		"hidden_title": "待解锁 · 行政堡垒孤狼首领",
		"en": "CAPTAIN SAEED · FIERY OWL",
		"role": "阿萨拉堡垒 · 普通行动行政堡垒首领",
		"quote": "「父亲教导我，好的猎人懂得尊重猎物……但你，不配！」",
		"tactical": "招牌战术翻滚位移 + 高温燃烧弹封路 + 复合战术弩齐射！见火焰预警圈立刻疾跑拉距离，破盾猛击红核！",
		"chapters": [
			{
				"title": "档案 I · 猩红兜帽与孤狼之名",
				"cond": {"type": "lore_stat", "key": "saeed_defeats", "target": 1, "label": "在阿萨拉堡垒击败「赤枭·赛伊德」1 次"},
				"text": "身披赤红荒漠斗篷、胸悬青铜飞枭徽章、背负精钢复合弩与重机枪的传奇指挥官——代号「赤枭」。他在零号大坝行政堡垒一带神出鬼没，任何孤身潜入的外来干员都难逃他的锐目。",
			},
			{
				"title": "档案 II · 荒漠猎手与零号大坝旧怨",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "saeed_defeats", "target": 1, "label": "击败赛伊德 1 次"},
					{"type": "lore_stat", "key": "camps_cleared_ahsarah", "target": 2, "label": "肃清阿萨拉营地 2 座"},
				], "label": "击败赛伊德 1 次且肃清阿萨拉营地 2 座"},
				"text": "赛伊德本是阿萨拉河谷最出色的年轻猎手，自幼随父亲在峭壁间追猎山羚。直到哈夫克集团强行征地修建零号大坝并害死阻拦施工的父亲，这头温柔的荒漠猎鹰才彻底化作焚尽敌营的「赤枭」。",
			},
			{
				"title": "档案 III · 翻滚烈焰破局实录",
				"cond": {"type": "lore_stat", "key": "saeed_defeats", "target": 2, "label": "累计击败「赤枭·赛伊德」2 次"},
				"text": "正面交锋中，赛伊德总在枪林弹雨里敏捷侧滚规避弹道，同时掷出燃烧瓶点燃地面封锁走位，口中冷笑着『我看到你了，小耗子！』。唯有预判其翻滚落点、稳听英语词令一举破盾，方能令这名孤狼俯首。",
			},
			{
				"title": "档案 IV · 猎人的敬意",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "saeed_defeats", "target": 2, "label": "累计击败赤枭·赛伊德 2 次"},
					{"type": "has_any_item", "items": ["赤枭青铜猎徽", "阿萨拉王室金杯", "非洲之心"], "label": "带出阿萨拉高阶珍宝（猎徽/金杯/非洲之心）"},
				], "label": "击败赛伊德 2 次并带出阿萨拉高阶珍宝"},
				"text": "二度败在少羽枪下后，赛伊德靠在砂岩柱边摘下黑面巾，罕见地将一枚「赤枭青铜猎徽」抛了过来。他淡淡说出一句：『你和哈夫克那群冷血雇佣兵不同——下次再见，我不会再留手。』",
			},
		],
	},
	"reis_warlord": {
		"id": "reis_warlord",
		"faction": "ahsarah",
		"name": "阿萨拉军阀 · 雷斯",
		"hidden_title": "待解锁 · 阿萨拉机密军阀",
		"en": "WARLORD REIS",
		"role": "阿萨拉堡垒 · 机密行动行政堡垒统领",
		"quote": "「把留声机开大声点！没有交响乐的战场，简直粗俗不堪！」",
		"tactical": "【机密专属两轮制首领】第一轮须严格按 1→5 破五面重词盾；第二轮携三面旋转金盾 + 霰弹冲锋，破阵即掉高阶珍宝！",
		"chapters": [
			{
				"title": "档案 I · 墨镜、鎏金袍与铜喇叭留声机",
				"cond": {"type": "lore_stat", "key": "reis_defeats", "target": 1, "label": "在阿萨拉【机密行动】击败「军阀·雷斯」1 次"},
				"text": "一身金线刺绣藏青战甲、墨镜遮目、肩扛古董黄铜大喇叭留声机——阿萨拉最具戏剧张力的重装军阀雷斯，总爱在硝烟弥漫的堡垒广场放起激昂交响乐，优雅而狂傲地指挥战斗。",
			},
			{
				"title": "档案 II · 马尔卡兹旧贵族的野心",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "reis_defeats", "target": 1, "label": "击败雷斯 1 次"},
					{"type": "lore_stat", "key": "ahsarah_runs", "target": 2, "label": "出击阿萨拉 2 局"},
				], "label": "击败雷斯 1 次且出击阿萨拉 2 局"},
				"text": "雷斯出身阿萨拉旧王室军官世家，战乱爆发后凭铁腕收编精锐重甲卫队自立山头。在他眼中，哈夫克集团是毫无审美的暴发户，而赛伊德则过于偏执——唯有自己才配坐镇行政堡垒金库之巅。",
			},
			{
				"title": "档案 III · 交响乐章终结之战",
				"cond": {"type": "lore_stat", "key": "reis_defeats", "target": 2, "label": "累计击败「军阀·雷斯」2 次"},
				"text": "当留声机奏响最高潮乐章，雷斯先以五面顺序词盾测试闯入者的英文功底，随即释放三面公转金盾端起 S12K 重霰弹咆哮冲锋。扛住音浪冲击并击碎金盾的那一刻，连雷斯都忍不住击掌赞叹。",
			},
			{
				"title": "档案 IV · 非洲之心的终极秘密",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "reis_defeats", "target": 2, "label": "累计击败军阀·雷斯 2 次"},
					{"type": "has_any_item", "items": ["军阀古董留声机", "非洲之心", "曼德尔加密砖"], "label": "带出军阀古董留声机 / 非洲之心 / 曼德尔加密砖"},
				], "label": "累计击败雷斯 2 次并带出其珍藏大金/大红"},
				"text": "在雷斯留声机底座的暗格里，藏着一份泛黄的皇家宝石鉴定书。原来传说中的旷世红钻「非洲之心」正是当年王室为换取荒漠净水工程而筹措的最后抵押，如今静静躺在行政堡垒深处的密匣中等待真正的破局者。",
			},
		],
	},

	# ===================== 哈夫克集团 (2) =====================
	"haavk_trooper": {
		"id": "haavk_trooper",
		"faction": "haavk",
		"name": "哈夫克精锐特勤",
		"hidden_title": "待解锁 · 哈夫克装甲特勤",
		"en": "HAAVK ELITE OPERATIVE",
		"role": "跨国科技私军 · 东区变电站高阶守卫",
		"quote": "「HAAVK 协议生效——清除未经授权的信号侵入者，保护曼德尔资产。」",
		"tactical": "驻守阿萨拉东区变电站重地，火力精准、装备青蓝战术面罩；善用 [G] 烟雾 EMP 干扰其光学锁定！",
		"chapters": [
			{
				"title": "档案 I · 纯白复合甲与青蓝面罩",
				"cond": {"type": "map_ahsarah", "label": "解锁第二战区「阿萨拉堡垒」"},
				"text": "2035 年，跨国科技巨擘哈夫克集团（HAAVK）以援建零号大坝与巴别通讯塔为名进驻阿萨拉，同时派遣装备全白复合装甲与全息瞄准面罩的私军特勤全面接管能源枢纽。",
			},
			{
				"title": "档案 II · 东区变电站高压防线",
				"cond": {"type": "lore_stat", "key": "ahsarah_runs", "target": 1, "label": "进入阿萨拉堡垒执行 1 次行动"},
				"text": "与阿萨拉卫队的粗犷游击不同，哈夫克特勤严守标准化战术阵列，驻扎在高压电网密布的东区变电站。他们几乎从不流露多余情绪，所有指令均通过冷冰冰的加密无线电实时下达。",
			},
			{
				"title": "档案 III · 突袭高压变电站",
				"cond": {"type": "lore_stat", "key": "substation_cleared", "target": 1, "label": "在阿萨拉堡垒清剿「东区变电站」1 次"},
				"text": "攻入东区变电站后，少羽发现哈夫克并非单纯发电——超负荷运转的变压器组正将庞大电流持续输往巴别通讯塔顶，为一项代号「曼德尔协议」的高密度语言量子加密阵列供能。",
			},
			{
				"title": "档案 IV · 烟山与巴别塔的隐秘连线",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "substation_cleared", "target": 2, "label": "累计清剿东区变电站 2 次"},
					{"type": "mastered_words", "target": 25, "label": "累计掌握至少 25 个英语单词"},
				], "label": "清剿东区变电站 2 次并累计掌握 25 词"},
				"text": "变电站终端的残存日志彻底揭开了跨战区谜团：烟山雾隐帮使用的全息词盾与玄铁词尊，正是哈夫克外包给东方黑市做野外压力测试的原型模块——而少羽一路过关斩将，已将他们的实验日志彻底改写。",
			},
		],
	},
	"mandel_protocol": {
		"id": "mandel_protocol",
		"faction": "haavk",
		"name": "曼德尔加密砖 · 量子档案",
		"hidden_title": "待解锁 · 绝密量子装置",
		"en": "MANDELBRICK QUANTUM ARCHIVE",
		"role": "哈夫克绝密高能装置 · 全图事件核心",
		"quote": "「检测到曼德尔加密砖激活——45 秒内以无提示独立拼写完成同步破译！」",
		"tactical": "在阿萨拉堡垒触发曼德尔加密砖事件后，顶住敌军反扑并独立完成多轮英文破译即可赢取高阶大金/大红珍宝！",
		"chapters": [
			{
				"title": "档案 I · 青金辉光下的几何魔方",
				"cond": {"type": "any", "parts": [
					{"type": "lore_stat", "key": "mandel_decodes", "target": 1, "label": "破译曼德尔加密砖 1 次"},
					{"type": "lore_stat", "key": "perfect_ciphers_total", "target": 2, "label": "无错破译密码箱 2 个"},
				], "label": "破译曼德尔加密砖 1 次或累计无错破译 2 个密码箱"},
				"text": "通体由鎏金几何框架与青蓝全息棱面构筑的量子加密存储模块——「曼德尔加密砖」。它是哈夫克集团在阿萨拉倾注最高预算研发的机密核心，任何一枚现身战区都会引来各方疯抢。",
			},
			{
				"title": "档案 II · 独立记忆才是唯一密钥",
				"cond": {"type": "lore_stat", "key": "perfect_ciphers_total", "target": 4, "label": "累计无错破译 4 个战场密码箱"},
				"text": "曼德尔加密砖的防火墙极其刁钻：普通暴力破解只会导致自毁锁死，唯有人类操作者在干扰倒计时中凭借扎实的英语听读与独立拼写，连续通过高频语义校验，才能将其温和解锁。",
			},
			{
				"title": "档案 III · 极限同步破译战",
				"cond": {"type": "lore_stat", "key": "mandel_decodes", "target": 1, "label": "在阿萨拉堡垒成功破译 1 次曼德尔加密砖"},
				"text": "破译倒计时启动瞬间，全堡垒的警报红灯骤然响起，阿萨拉卫队与哈夫克特勤同时向发射台蜂拥而至。能在枪声与倒计时压迫下冷静拼出最后一个字母的游侠，才配捧走这座闪耀青光的量子奇迹。",
			},
			{
				"title": "档案 IV · 星辰大海的下一站",
				"cond": {"type": "combo", "parts": [
					{"type": "lore_stat", "key": "mandel_decodes", "target": 2, "label": "累计破译 2 次曼德尔加密砖"},
					{"type": "mastered_words", "target": 40, "label": "累计掌握至少 40 个英语单词"},
				], "label": "破译曼德尔加密砖 2 次并累计掌握 40 词"},
				"text": "随着第二枚曼德尔加密砖完成深度解码，全息投影在营地沙盘上缓缓展开了更宏大的远景：江南诚庄河港、鲸塘旧校舍、巴克什古城深处以及哈夫克航天禁区……属于少年游侠与单词搜撤的全新篇章，才刚刚拉开序幕。",
			},
		],
	},
}

static var _portrait_cache: Dictionary = {}

var game
var busy: bool = false
var view_mode: String = "hub"  # "hub" | "detail"
var active_faction_id: String = "rangers"
var active_char_id: String = "shaoyu"
var return_to_compendium: bool = false

var overlay: Control
var header_title: Label
var header_progress: Label
var back_btn: Button
var close_btn: Button
var prev_char_btn: Button
var next_char_btn: Button

# Page 1 (Faction Hub) containers
var hub_root: Control
var faction_tabs_row: HBoxContainer
var faction_tab_btns: Dictionary = {}
var faction_banner_panel: Panel
var faction_banner_title: Label
var faction_banner_desc: Label
var faction_banner_rule: Label
var hub_cards_scroll: ScrollContainer
var hub_cards_grid: GridContainer

# Page 2 (Dedicated Character Dossier) containers
var detail_root: Control
var detail_portrait_frame: Panel
var detail_portrait_tex: TextureRect
var detail_name_lbl: Label
var detail_en_lbl: Label
var detail_role_lbl: Label
var detail_quote_lbl: Label
var detail_tactical_lbl: Label
var detail_progress_lbl: Label
var detail_progress_fill: ColorRect
var detail_chapters_scroll: ScrollContainer
var detail_chapters_vbox: VBoxContainer


static func load_portrait(char_id: String) -> Texture2D:
	if _portrait_cache.has(char_id):
		return _portrait_cache[char_id]
	var path := PORTRAIT_DIR + char_id + ".png"
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			_portrait_cache[char_id] = tex
			return tex
	return null


static func load_locked_portrait() -> Texture2D:
	if _portrait_cache.has("__locked__"):
		return _portrait_cache["__locked__"]
	if ResourceLoader.exists(LOCKED_PORTRAIT_PATH):
		var tex = load(LOCKED_PORTRAIT_PATH)
		if tex is Texture2D:
			_portrait_cache["__locked__"] = tex
			return tex
	return null


static func all_dossier_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in FACTIONS:
		for cid in f["members"]:
			out.append(str(cid))
	return out


func setup(g):
	game = g
	_build_ui()
	overlay.hide()


func _faction_by_id(fid: String) -> Dictionary:
	for f in FACTIONS:
		if str(f["id"]) == fid:
			return f
	return FACTIONS[0]


func _evaluate_condition(cond: Dictionary) -> Dictionary:
	var ctype := str(cond.get("type", "always"))
	var ls: Dictionary = game.rules.ensure_lore_stats()
	var prof: Dictionary = game.rules.profile
	if ctype == "always":
		return {"unlocked": true, "cur": 1, "target": 1, "label": "初始档案已解封"}
	if ctype == "lore_stat":
		var key := str(cond.get("key", ""))
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := int(ls.get(key, 0))
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "extractions":
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := maxi(int(prof.get("extractions", 0)), int(ls.get("shaoyu_extractions", 0)))
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "achievements":
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := (prof.get("achievements", []) as Array).size()
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "reputation":
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := int(prof.get("reputation", 0))
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "bounties":
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := int(prof.get("bounties_completed", 0))
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "collection":
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := (prof.get("collection", []) as Array).size()
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "mastered_words":
		var target := maxi(1, int(cond.get("target", 1)))
		var cur := int(game.rules.learning.mastered_count(game.words))
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "map_ahsarah":
		var ok: bool = game.rules.is_map_unlocked("ahsarah")
		return {"unlocked": ok, "cur": 1 if ok else 0, "target": 1, "label": str(cond.get("label", "解锁阿萨拉堡垒"))}
	if ctype == "scene":
		var sc := str(cond.get("scene", ""))
		var visited: Array = ls.get("scenes_visited", [])
		var ok := (sc in visited)
		if sc == "prologue":
			ok = ok or bool(prof.get("prologue_completed", false)) or ("chen_guide" in prof.get("character_cards", []))
		return {"unlocked": ok, "cur": 1 if ok else 0, "target": 1, "label": str(cond.get("label", ""))}
	if ctype == "scenes_count":
		var target := maxi(1, int(cond.get("target", 1)))
		var visited: Array = ls.get("scenes_visited", [])
		var cur := visited.size()
		return {"unlocked": cur >= target, "cur": mini(cur, target), "target": target, "label": str(cond.get("label", ""))}
	if ctype == "has_any_item":
		var items: Array = cond.get("items", [])
		var col: Array = prof.get("collection", [])
		var ok := false
		for title in items:
			if str(title) in col:
				ok = true
				break
		if not ok:
			for it in prof.get("warehouse", []):
				if it is Dictionary and str(it.get("title", "")) in items:
					ok = true
					break
		return {"unlocked": ok, "cur": 1 if ok else 0, "target": 1, "label": str(cond.get("label", ""))}
	if ctype == "any":
		var parts: Array = cond.get("parts", [])
		var best_ratio := -1.0
		var best_cur := 0
		var best_target := 1
		var any_ok := false
		for p in parts:
			var res := _evaluate_condition(p)
			if bool(res.unlocked):
				any_ok = true
				best_cur = int(res.target)
				best_target = int(res.target)
				break
			var ratio := float(res.cur) / float(maxi(1, int(res.target)))
			if ratio > best_ratio:
				best_ratio = ratio
				best_cur = int(res.cur)
				best_target = int(res.target)
		return {
			"unlocked": any_ok,
			"cur": best_target if any_ok else best_cur,
			"target": best_target,
			"label": str(cond.get("label", "")),
		}
	if ctype == "combo":
		var parts: Array = cond.get("parts", [])
		var done_cnt := 0
		var sub_labels: PackedStringArray = []
		for p in parts:
			var res := _evaluate_condition(p)
			if bool(res.unlocked):
				done_cnt += 1
			sub_labels.append("%s（%d/%d）" % [str(res.label), int(res.cur), int(res.target)])
		return {
			"unlocked": done_cnt >= parts.size(),
			"cur": done_cnt,
			"target": maxi(1, parts.size()),
			"label": str(cond.get("label", "")) + "  [" + "；".join(sub_labels) + "]",
		}
	return {"unlocked": false, "cur": 0, "target": 1, "label": ""}


func is_character_unlocked(char_id: String) -> bool:
	if not DOSSIERS.has(char_id):
		return false
	var chs: Array = DOSSIERS[char_id]["chapters"]
	if chs.is_empty():
		return false
	return bool(_evaluate_condition(chs[0]["cond"]).unlocked)


func unlocked_characters_count() -> int:
	var n := 0
	for cid in DOSSIERS:
		if is_character_unlocked(str(cid)):
			n += 1
	return n


func unlocked_chapters_for(char_id: String) -> int:
	if not DOSSIERS.has(char_id):
		return 0
	var n := 0
	for ch in DOSSIERS[char_id]["chapters"]:
		if bool(_evaluate_condition(ch["cond"]).unlocked):
			n += 1
	return n


func total_chapter_counts() -> Dictionary:
	var unlocked := 0
	var total := 0
	for cid in DOSSIERS:
		var chs: Array = DOSSIERS[cid]["chapters"]
		total += chs.size()
		unlocked += unlocked_chapters_for(cid)
	return {"unlocked": unlocked, "total": total, "chars_unlocked": unlocked_characters_count(), "chars_total": DOSSIERS.size()}


func faction_chapter_counts(fid: String) -> Dictionary:
	var f := _faction_by_id(fid)
	var unlocked := 0
	var total := 0
	var c_unl := 0
	for cid in f["members"]:
		if DOSSIERS.has(cid):
			if is_character_unlocked(str(cid)):
				c_unl += 1
			total += (DOSSIERS[cid]["chapters"] as Array).size()
			unlocked += unlocked_chapters_for(cid)
	return {"unlocked": unlocked, "total": total, "chars_unlocked": c_unl, "chars_total": (f["members"] as Array).size()}


func _mech_panel_style(bg: Color, border: Color, left_accent: Color = Color(0, 0, 0, 0), left_w: int = 2) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_width_left = left_w if left_accent.a > 0.01 else 1
	st.border_color = left_accent if left_accent.a > 0.01 else border
	st.set_corner_radius_all(3)
	return st


func _build_ui():
	overlay = Control.new()
	overlay.name = "LoreCodexOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	game.ui.add_child(overlay)

	# Sleek dark gunmetal carbon background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.032, 0.044, 0.056, 0.99)
	overlay.add_child(bg)

	# Mechanical Top Command Bar (62px)
	var topbar := Panel.new()
	topbar.position = Vector2(0, 0)
	topbar.size = Vector2(1280, 62)
	var tb_s := StyleBoxFlat.new()
	tb_s.bg_color = Color(0.048, 0.068, 0.084, 0.99)
	tb_s.border_width_bottom = 2
	tb_s.border_color = Color("2d5260")
	topbar.add_theme_stylebox_override("panel", tb_s)
	overlay.add_child(topbar)

	# Glowing tactical top hairline
	var top_line := ColorRect.new()
	top_line.position = Vector2(0, 0)
	top_line.size = Vector2(1280, 3)
	top_line.color = Color("3ef0b4")
	topbar.add_child(top_line)

	back_btn = game._button(topbar, "◀ 返回阵营列表", Rect2(20, 14, 152, 34), func():
		show_faction_hub(active_faction_id)
	)
	game._style_tactical_button(back_btn, Color("132630"), Color("3ef0b4"), Color("e8fff9"))

	header_title = game._text(topbar, "ARCHIVE // 角色小传 · 全阵营人物档案馆", Vector2(26, 15), Vector2(540, 32), 21, Color("f0faf6"))
	header_progress = game._text(topbar, "", Vector2(552, 19), Vector2(292, 26), 13, Color("66e8c8"))
	header_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	prev_char_btn = game._button(topbar, "◀ 上一位", Rect2(854, 14, 108, 34), func():
		_step_character(-1)
	)
	next_char_btn = game._button(topbar, "下一位 ▶", Rect2(970, 14, 108, 34), func():
		_step_character(1)
	)
	game._style_tactical_button(prev_char_btn, Color("121d26"), Color("3a5866"), Color("dceee8"))
	game._style_tactical_button(next_char_btn, Color("121d26"), Color("3a5866"), Color("dceee8"))

	close_btn = game._button(topbar, "✕ 返回沙盘 [ESC]", Rect2(1098, 14, 158, 34), close)
	game._style_tactical_button(close_btn, Color("2e181b"), Color("d45a5a"), Color("ffe8e4"))

	# =========================================================================
	# PAGE 1: FACTION HUB VIEW (四大阵营切换 + 人物立绘 / 未解锁「？」剪影)
	# =========================================================================
	hub_root = Control.new()
	hub_root.position = Vector2(0, 62)
	hub_root.size = Vector2(1280, 658)
	overlay.add_child(hub_root)

	faction_tabs_row = HBoxContainer.new()
	faction_tabs_row.position = Vector2(34, 16)
	faction_tabs_row.size = Vector2(1212, 48)
	faction_tabs_row.add_theme_constant_override("separation", 12)
	hub_root.add_child(faction_tabs_row)

	for f in FACTIONS:
		var fid := str(f["id"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(290, 46)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(func():
			select_faction(fid)
		)
		faction_tabs_row.add_child(btn)
		faction_tab_btns[fid] = btn

	# Faction intel header bar
	faction_banner_panel = game._panel(hub_root, Rect2(34, 76, 1212, 98), Color(0.048, 0.072, 0.088, 0.96), Color("3ef0b4"))
	faction_banner_title = game._text(faction_banner_panel, "", Vector2(20, 10), Vector2(820, 26), 18, Color("fff4d6"))
	faction_banner_desc = game._text(faction_banner_panel, "", Vector2(20, 38), Vector2(1172, 34), 13, Color("cfe2dc"))
	faction_banner_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	faction_banner_rule = game._text(faction_banner_panel, "", Vector2(20, 72), Vector2(1172, 20), 12, Color("66e8c8"))

	# Character Portrait Gallery Grid
	hub_cards_scroll = ScrollContainer.new()
	hub_cards_scroll.position = Vector2(34, 188)
	hub_cards_scroll.size = Vector2(1212, 454)
	hub_root.add_child(hub_cards_scroll)

	hub_cards_grid = GridContainer.new()
	hub_cards_grid.columns = 5
	hub_cards_grid.add_theme_constant_override("h_separation", 16)
	hub_cards_grid.add_theme_constant_override("v_separation", 14)
	hub_cards_scroll.add_child(hub_cards_grid)

	# =========================================================================
	# PAGE 2: DEDICATED CHARACTER DOSSIER PAGE (左立绘或「？」剪影 · 右 4 段渐进档案)
	# =========================================================================
	detail_root = Control.new()
	detail_root.position = Vector2(0, 62)
	detail_root.size = Vector2(1280, 658)
	overlay.add_child(detail_root)

	detail_portrait_frame = game._panel(detail_root, Rect2(32, 16, 388, 624), Color(0.044, 0.062, 0.078, 0.98), Color("3ef0b4"))

	var pic_holder := Panel.new()
	pic_holder.position = Vector2(14, 14)
	pic_holder.size = Vector2(360, 436)
	pic_holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var ph_s := StyleBoxFlat.new()
	ph_s.bg_color = Color(0.02, 0.028, 0.036, 1.0)
	ph_s.set_corner_radius_all(3)
	ph_s.set_border_width_all(2)
	ph_s.border_color = Color("3a5866")
	pic_holder.add_theme_stylebox_override("panel", ph_s)
	detail_portrait_frame.add_child(pic_holder)

	detail_portrait_tex = TextureRect.new()
	detail_portrait_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic_holder.add_child(detail_portrait_tex)

	# Bottom nameplate ribbon overlaid cleanly inside portrait bottom
	var np_veil := ColorRect.new()
	np_veil.position = Vector2(0, 368)
	np_veil.size = Vector2(360, 68)
	np_veil.color = Color(0.02, 0.032, 0.042, 0.88)
	pic_holder.add_child(np_veil)

	detail_name_lbl = game._text(np_veil, "", Vector2(14, 6), Vector2(332, 30), 21, Color("fff3cf"))
	detail_en_lbl = game._text(np_veil, "", Vector2(14, 38), Vector2(332, 22), 11, Color("6ce8cc"))

	detail_role_lbl = game._text(detail_portrait_frame, "", Vector2(16, 458), Vector2(356, 24), 14, Color("ffd15c"))
	detail_quote_lbl = game._text(detail_portrait_frame, "", Vector2(16, 486), Vector2(356, 56), 13, Color("dcebe6"))
	detail_quote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_tactical_lbl = game._text(detail_portrait_frame, "", Vector2(16, 546), Vector2(356, 68), 12, Color("8cc8b8"))
	detail_tactical_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var right_panel: Panel = game._panel(detail_root, Rect2(436, 16, 812, 624), Color(0.044, 0.062, 0.078, 0.96), Color("2d4b58"))

	detail_progress_lbl = game._text(right_panel, "", Vector2(22, 14), Vector2(520, 28), 16, Color("ffd76a"))
	var pbar_bg := ColorRect.new()
	pbar_bg.position = Vector2(554, 21)
	pbar_bg.size = Vector2(236, 12)
	pbar_bg.color = Color(0.09, 0.13, 0.17, 1.0)
	right_panel.add_child(pbar_bg)
	detail_progress_fill = ColorRect.new()
	detail_progress_fill.position = Vector2(0, 0)
	detail_progress_fill.size = Vector2(0, 12)
	detail_progress_fill.color = Color("3ef0b4")
	pbar_bg.add_child(detail_progress_fill)

	detail_chapters_scroll = ScrollContainer.new()
	detail_chapters_scroll.position = Vector2(18, 52)
	detail_chapters_scroll.size = Vector2(776, 556)
	right_panel.add_child(detail_chapters_scroll)

	detail_chapters_vbox = VBoxContainer.new()
	detail_chapters_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_chapters_vbox.add_theme_constant_override("separation", 12)
	detail_chapters_scroll.add_child(detail_chapters_vbox)


func open(initial_faction: String = "", initial_char: String = "", from_compendium: bool = false):
	if is_instance_valid(game.loot_ui):
		game.loot_ui.close_all_modals()
	if is_instance_valid(game.rangers) and game.rangers.busy:
		game.rangers.close_modal()
	return_to_compendium = from_compendium
	busy = true
	if game.rules.phase in ["active", "extracting"]:
		game.paused = true
		game.player.active = false
		game.player.clear_movement_input()
		game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.show()
	overlay.move_to_front()

	if initial_char != "" and DOSSIERS.has(initial_char):
		open_character(initial_char)
	else:
		var fid := initial_faction if initial_faction != "" else active_faction_id
		show_faction_hub(fid)


func close():
	if not busy:
		return
	busy = false
	overlay.hide()
	var back_comp := return_to_compendium
	return_to_compendium = false
	if back_comp and is_instance_valid(game.loot_ui):
		game.loot_ui.open_compendium("relics")
		return
	if game.rules.phase in ["active", "extracting"]:
		if is_instance_valid(game.menu) and game.menu.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			game.paused = false
			game.player.active = true
			game.player.clear_movement_input()
			game.hud.show()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func select_faction(fid: String):
	active_faction_id = fid
	show_faction_hub(fid)


func show_faction_hub(fid: String = ""):
	if fid != "":
		active_faction_id = fid
	view_mode = "hub"
	hub_root.show()
	detail_root.hide()
	back_btn.hide()
	prev_char_btn.hide()
	next_char_btn.hide()
	header_title.position.x = 26
	header_title.text = "ARCHIVE // 角色小传 · 全阵营人物档案馆"
	var tot := total_chapter_counts()
	header_progress.text = "已解锁人物 %d/%d  |  档案 %d/%d 段" % [int(tot.chars_unlocked), int(tot.chars_total), int(tot.unlocked), int(tot.total)]
	_refresh_hub()


func open_character(char_id: String):
	if not DOSSIERS.has(char_id):
		return
	active_char_id = char_id
	active_faction_id = str(DOSSIERS[char_id]["faction"])
	view_mode = "detail"
	hub_root.hide()
	detail_root.show()
	back_btn.show()
	prev_char_btn.show()
	next_char_btn.show()
	header_title.position.x = 188
	var f := _faction_by_id(active_faction_id)
	var unlocked_char := is_character_unlocked(char_id)
	var disp_name := str(DOSSIERS[char_id]["name"]) if unlocked_char else ("??? · " + str(DOSSIERS[char_id].get("hidden_title", "未解锁人物")))
	header_title.text = "%s // %s" % [str(f["name"]), disp_name]
	var tot := total_chapter_counts()
	header_progress.text = "已解锁 %d/%d 人 · %d/%d 段" % [int(tot.chars_unlocked), int(tot.chars_total), int(tot.unlocked), int(tot.total)]
	_refresh_detail()


func _step_character(dir: int):
	var f := _faction_by_id(active_faction_id)
	var members: Array = f["members"]
	if members.is_empty():
		return
	var idx := members.find(active_char_id)
	if idx < 0:
		idx = 0
	idx = posmod(idx + dir, members.size())
	open_character(str(members[idx]))


func _refresh_hub():
	for f in FACTIONS:
		var fid := str(f["id"])
		var btn: Button = faction_tab_btns[fid]
		var fc := faction_chapter_counts(fid)
		var is_sel := (fid == active_faction_id)
		btn.text = "%s // %s（%d/%d人）" % [str(f["code"]), str(f["short"]), int(fc.chars_unlocked), int(fc.chars_total)]
		var accent: Color = f["color"]
		game._style_tactical_button(
			btn,
			accent.darkened(0.72) if is_sel else Color("0d161e"),
			accent if is_sel else Color("2b4350"),
			Color("ffffff") if is_sel else Color("9db8c0")
		)

	var cur_f := _faction_by_id(active_faction_id)
	var accent: Color = cur_f["color"]
	faction_banner_panel.add_theme_stylebox_override("panel", _mech_panel_style(cur_f["bg"], Color("2b4350"), accent, 5))

	faction_banner_title.text = "%s // %s  ·  %s" % [str(cur_f["code"]), str(cur_f["name"]), str(cur_f["en"])]
	faction_banner_title.add_theme_color_override("font_color", accent.lightened(0.20))
	faction_banner_desc.text = str(cur_f["desc"])
	faction_banner_rule.text = "▸ " + str(cur_f["unlock_rule"])

	for ch in hub_cards_grid.get_children():
		hub_cards_grid.remove_child(ch)
		ch.queue_free()

	var members: Array = cur_f["members"]
	var cols := mini(5, maxi(2, members.size()))
	hub_cards_grid.columns = cols
	# Preserve clean 4:5 portrait proportions across 2/3/4/5-member factions (zero cropped foreheads!)
	var card_w := 228 if cols >= 5 else (254 if cols == 4 else (262 if cols == 3 else 274))
	var card_h := 430
	var total_grid_w := cols * card_w + (cols - 1) * 16
	var pad_x := maxi(0, int((1212 - total_grid_w) * 0.5))
	hub_cards_scroll.position.x = 34 + pad_x
	hub_cards_scroll.size.x = 1212 - pad_x

	for cid_raw in members:
		var cid := str(cid_raw)
		if not DOSSIERS.has(cid):
			continue
		var d: Dictionary = DOSSIERS[cid]
		var unl_char := is_character_unlocked(cid)
		var unl := unlocked_chapters_for(cid)
		var tot_ch := (d["chapters"] as Array).size()

		var card := Panel.new()
		card.custom_minimum_size = Vector2(card_w, card_h)
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.052, 0.074, 0.092, 0.98) if unl_char else Color(0.036, 0.048, 0.060, 0.96)
		cs.border_width_top = 3
		cs.border_width_left = 1
		cs.border_width_right = 1
		cs.border_width_bottom = 1
		cs.border_color = accent if unl_char else Color("2b3c48")
		cs.set_corner_radius_all(3)
		card.add_theme_stylebox_override("panel", cs)

		# Portrait preview (top 274px) — UNLOCKED shows real portrait, LOCKED shows tactical '?' silhouette!
		var pframe := Panel.new()
		pframe.position = Vector2(10, 10)
		pframe.size = Vector2(card_w - 20, 274)
		pframe.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var pfs := StyleBoxFlat.new()
		pfs.bg_color = Color(0.018, 0.025, 0.034, 1.0)
		pfs.set_corner_radius_all(2)
		pframe.add_theme_stylebox_override("panel", pfs)
		card.add_child(pframe)

		var tex_rect := TextureRect.new()
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if unl_char:
			tex_rect.texture = load_portrait(cid)
			tex_rect.modulate = Color(1, 1, 1, 1)
		else:
			tex_rect.texture = load_locked_portrait()
			# Subtle faction tint on the mysterious '?' silhouette!
			tex_rect.modulate = Color(0.82, 0.88, 0.94, 1.0).lerp(accent.lightened(0.20), 0.18)
		pframe.add_child(tex_rect)

		# Status tag on top-right of portrait
		var badge := Panel.new()
		badge.position = Vector2(card_w - 116, 16)
		badge.size = Vector2(98, 22)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.025, 0.045, 0.060, 0.92)
		bs.set_border_width_all(1)
		bs.border_color = accent if unl_char else Color("5c7280")
		bs.set_corner_radius_all(2)
		badge.add_theme_stylebox_override("panel", bs)
		card.add_child(badge)
		var blbl: Label = game._text(badge, ("档案 %d/%d" % [unl, tot_ch]) if unl_char else "LOCKED // ?", Vector2(0, 2), Vector2(98, 18), 11, accent.lightened(0.24) if unl_char else Color("9db2be"))
		blbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var nl_text := str(d["name"]) if unl_char else "??? · 未解锁人物"
		var rl_text := str(d["role"]) if unl_char else str(d.get("hidden_title", "达成档案 I 条件解锁形象"))
		var nl: Label = game._text(card, nl_text, Vector2(12, 292), Vector2(card_w - 24, 24), 16, Color("fff3d4") if unl_char else Color("8ea4b2"))
		nl.clip_text = true
		var rl: Label = game._text(card, rl_text, Vector2(12, 318), Vector2(card_w - 24, 20), 12, Color("9dd4c0") if unl_char else Color("6e8594"))
		rl.clip_text = true

		# 4-stage visual progress dots or unlock hint
		if unl_char:
			var dots := ""
			for i in tot_ch:
				dots += "■ " if i < unl else "□ "
			game._text(card, dots.strip_edges() + ("  全卷解封" if unl >= tot_ch else "  已解锁形象"), Vector2(12, 344), Vector2(card_w - 24, 20), 12, accent.lightened(0.15))
		else:
			var c0_ev := _evaluate_condition((d["chapters"] as Array)[0]["cond"])
			var hint_lbl: Label = game._text(card, "解锁：" + str(c0_ev.label), Vector2(12, 340), Vector2(card_w - 24, 30), 10, Color("d4a862"))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			hint_lbl.clip_text = true
			hint_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

		var open_btn: Button = game._button(card, "进入人物专页 ▶" if unl_char else "查看解锁条件 ▶", Rect2(12, 378, card_w - 24, 36), func():
			open_character(cid)
		)
		game._style_tactical_button(
			open_btn,
			accent.darkened(0.70) if unl_char else Color("141e26"),
			accent if unl_char else Color("4a6270"),
			Color("fff8e6") if unl_char else Color("b4c6d0")
		)
		hub_cards_grid.add_child(card)


func _refresh_detail():
	if not DOSSIERS.has(active_char_id):
		return
	var d: Dictionary = DOSSIERS[active_char_id]
	var f := _faction_by_id(str(d["faction"]))
	var accent: Color = f["color"]
	var unl_char := is_character_unlocked(active_char_id)

	detail_portrait_frame.add_theme_stylebox_override("panel", _mech_panel_style(Color(0.044, 0.062, 0.078, 0.98), Color("2b4350"), accent if unl_char else Color("4c6472"), 4))

	if unl_char:
		detail_portrait_tex.texture = load_portrait(active_char_id)
		detail_portrait_tex.modulate = Color(1, 1, 1, 1)
		detail_name_lbl.text = str(d["name"])
		detail_en_lbl.text = str(d["en"])
		detail_role_lbl.text = "▸ " + str(d["role"])
		detail_role_lbl.add_theme_color_override("font_color", accent.lightened(0.22))
		detail_quote_lbl.text = str(d["quote"])
		detail_tactical_lbl.text = "【战地特征】" + str(d["tactical"])
	else:
		detail_portrait_tex.texture = load_locked_portrait()
		detail_portrait_tex.modulate = Color(0.84, 0.90, 0.96, 1.0).lerp(accent.lightened(0.20), 0.16)
		detail_name_lbl.text = "???（未解锁形象）"
		detail_en_lbl.text = "CLASSIFIED // IDENTITY LOCKED"
		detail_role_lbl.text = "▸ " + str(d.get("hidden_title", "机密人物档案"))
		detail_role_lbl.add_theme_color_override("font_color", Color("d8a85e"))
		detail_quote_lbl.text = "「该人物当前处于加密状态——达成右侧『档案 I』解锁条件后，立即揭晓高清人物立绘与首段生平！」"
		detail_tactical_lbl.text = "【情报提示】" + str(f["unlock_rule"])

	var chs: Array = d["chapters"]
	var unl := unlocked_chapters_for(active_char_id)
	var tot := chs.size()
	detail_progress_lbl.text = ("人物小记解封进度：%d / %d 段" % [unl, tot]) if unl_char else "人物尚未解锁 · 请先完成档案 I 揭晓真容（0 / %d 段）" % tot
	detail_progress_fill.color = accent if unl_char else Color("607886")
	detail_progress_fill.size.x = 236.0 * (float(unl) / float(maxi(1, tot)))

	for ch in detail_chapters_vbox.get_children():
		detail_chapters_vbox.remove_child(ch)
		ch.queue_free()

	for idx in chs.size():
		var chap: Dictionary = chs[idx]
		var ev := _evaluate_condition(chap["cond"])
		var is_open := bool(ev.unlocked)

		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.056, 0.086, 0.106, 0.96) if is_open else Color(0.040, 0.052, 0.064, 0.94)
		cs.border_width_left = 5
		cs.border_width_top = 1
		cs.border_width_right = 1
		cs.border_width_bottom = 1
		cs.border_color = accent if is_open else (Color("d89a44") if idx == 0 else Color("304450"))
		cs.set_corner_radius_all(3)
		cs.content_margin_left = 18
		cs.content_margin_right = 18
		cs.content_margin_top = 14
		cs.content_margin_bottom = 14
		card.add_theme_stylebox_override("panel", cs)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		card.add_child(box)

		var title_row := HBoxContainer.new()
		box.add_child(title_row)

		var tlbl := Label.new()
		tlbl.text = str(chap["title"]) if is_open else (str(chap["title"]) if idx == 0 else "加密卷宗 · 第 %d 段（待解封）" % (idx + 1))
		tlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tlbl.add_theme_font_size_override("font_size", 16)
		tlbl.add_theme_color_override("font_color", Color("ffe79e") if is_open else (Color("f0c478") if idx == 0 else Color("7c92a0")))
		title_row.add_child(tlbl)

		var status_lbl := Label.new()
		status_lbl.text = "✓ 已解封" if is_open else ("🔓 达成解锁人物形象" if idx == 0 else "🔒 未解封")
		status_lbl.add_theme_font_size_override("font_size", 12)
		status_lbl.add_theme_color_override("font_color", Color("66f2be") if is_open else Color("f0a852"))
		title_row.add_child(status_lbl)

		if is_open:
			var body := Label.new()
			body.text = str(chap["text"])
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_font_size_override("font_size", 14)
			body.add_theme_color_override("font_color", Color("e4f1ec"))
			box.add_child(body)
		else:
			var lock_desc := Label.new()
			lock_desc.text = "解锁条件：" + str(ev.label)
			lock_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lock_desc.add_theme_font_size_override("font_size", 13)
			lock_desc.add_theme_color_override("font_color", Color("d8c498"))
			box.add_child(lock_desc)

			var prog_row := HBoxContainer.new()
			prog_row.add_theme_constant_override("separation", 10)
			box.add_child(prog_row)

			var pb_wrap := Control.new()
			pb_wrap.custom_minimum_size = Vector2(420, 12)
			prog_row.add_child(pb_wrap)

			var pb_bg := ColorRect.new()
			pb_bg.position = Vector2(0, 2)
			pb_bg.size = Vector2(420, 9)
			pb_bg.color = Color(0.10, 0.14, 0.18, 1.0)
			pb_wrap.add_child(pb_bg)

			var pb_fill := ColorRect.new()
			pb_fill.position = Vector2(0, 2)
			var ratio := clampf(float(ev.cur) / float(maxi(1, int(ev.target))), 0.0, 1.0)
			pb_fill.size = Vector2(420.0 * ratio, 9)
			pb_fill.color = accent
			pb_wrap.add_child(pb_fill)

			var cnt_lbl := Label.new()
			cnt_lbl.text = "当前进度：%d / %d" % [int(ev.cur), int(ev.target)]
			cnt_lbl.add_theme_font_size_override("font_size", 12)
			cnt_lbl.add_theme_color_override("font_color", Color("96b8c4"))
			prog_row.add_child(cnt_lbl)

		detail_chapters_vbox.add_child(card)
