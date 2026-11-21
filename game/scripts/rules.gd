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
const NORMAL_EXTRACT_ACCURACY = 0.60
const CONFIDENTIAL_EXTRACT_ACCURACY = 0.80
const CONFIDENTIAL_VALUE_MULT = 1.35
const CONFIDENTIAL_CRATE_BONUS = 0.12

const SAFE_BOX_SLOTS = 2
const MAX_DISPLAY_STAND = 4
const MAX_RARITY = 7
const PROFILE_SCHEMA_VERSION = 3

const DEFAULT_SETTINGS = {
	"strict_daily_review": true,
	"auto_speak_on_switch": true,
	"reduce_screen_shake": false,
	"sfx_volume": 1.0,
	"voice_volume": 1.0,
	"mouse_sensitivity": 1.0
}

const CULTURAL_NOTES = {
	"越窑秘色青瓷盏": {
		"fiction": "相传由诚庄先民自古窑旧埠请回，曾供奉于烟霞古洞石案之上。",
		"fact": "唐代越窑「秘色瓷」以浙江上林湖窑系为代表，釉色青碧莹润如玉。1987 年陕西法门寺唐代地宫出土的 13 件秘色瓷与物账碑首次印证了这一名品（参考：陕西历史博物馆 / 浙江省博物馆藏品研究资料）。"
	},
	"诚庄先民双龙玉璧": {
		"fiction": "烟山族谱传说此璧曾用于秋收祈丰，后为雾隐帮觊觎而秘藏深林。",
		"fact": "玉璧是中国古代重要礼器，江南太湖流域自良渚文化起便有精良治玉传统，常见璧、琮等形制（参考：良渚博物院 / 南京博物院公开馆藏说明）。"
	},
	"烟霞岩画残拓": {
		"fiction": "拓印自烟霞古洞原生石壁《烟山耕读》阴刻，记录诚庄先民采茶耕读往事。",
		"fact": "传拓（墨拓）是用宣纸贴覆金石碑刻并扑墨显字的传统文献复制技艺，2006 年以来多地碑刻传拓技艺列入各级非物质文化遗产名录。"
	},
	"端溪雕云古砚": {
		"fiction": "诚庄私塾先生留下的镇案老砚，常与竹简古诗碑刻相伴。",
		"fact": "端砚产自广东肇庆端溪，始于唐代，以石质致密、发墨细腻不损毫著称，位列中国四大名砚之首（参考：故宫博物院文房四宝器物志）。"
	},
	"海兽葡萄错银铜镜": {
		"fiction": "古道商队遗落烟山溪畔的传家古镜，被巡护队收入秘藏。",
		"fact": "海兽葡萄镜盛行于盛唐，纹饰融合瑞兽与西域葡萄蔓叶，见证丝绸之路中西工艺交流（参考：中国国家博物馆唐代铜镜展陈资料）。"
	},
	"宜兴朱泥水平壶": {
		"fiction": "诚庄春茶上市时山村茶坊待客所用的传世紫砂水平小壶。",
		"fact": "江苏宜兴丁蜀镇紫砂陶始兴于明代中叶，朱泥小壶因胎质细密、透气聚香而擅泡工夫茶（参考：宜兴陶瓷博物馆公开资料）。"
	},
	"望稻亭鎏金香炉": {
		"fiction": "昔年乡贤登东岭望稻亭观秋熟时所设雅器，与望稻亭信标并称东岭双景。",
		"fact": "博山炉造型兴于汉代，炉盖镂空叠嶂如海中仙山，焚香时轻烟自峰隙袅袅而出（参考：河北博物院满城汉墓错金博山炉展陈资料）。"
	},
	"烟山先民竹简": {
		"fiction": "藏于烟霞古洞寒潭茶灶旁石室的古旧墨书简册，记述「烟山」得名由来。",
		"fact": "竹简是纸张普及前中国主要的书写载体，以韦编或丝绳编联成册，湖南里耶、湖北睡虎地等地出土简牍为研究古代基层生活提供了珍贵一手文献。"
	}
}

const RARITY_NAMES = {
	1: "常规",
	2: "精良",
	3: "稀有",
	4: "史诗",
	5: "珍品·小金",
	6: "传说·大金",
	7: "旷世·大红"
}

const RARITY_COLORS = {
	1: Color("d2dbd6"),
	2: Color("6be39b"),
	3: Color("5cb8ff"),
	4: Color("cf82ff"),
	5: Color("f6c34e"),
	6: Color("ff9f38"),
	7: Color("ff4757")
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
		{"title": "青竹编织哨", "en": "Bamboo Whistle", "value": 36, "rarity": 1, "grid": "1×1", "icon": "bamboo", "lore": "江南山里孩子用苦竹削成的清脆竹哨。"},
		{"title": "粗陶米碗", "en": "Clay Rice Bowl", "value": 22, "rarity": 1, "grid": "1×1", "icon": "rice_bowl", "lore": "江南山村手绘蓝纹粗陶碗，配着一双原木竹筷。"},
		{"title": "烟山野生核桃", "en": "Mountain Walnut", "value": 24, "rarity": 1, "grid": "1×1", "icon": "walnut", "lore": "林间秋风吹落的饱满山核桃，香脆补体力。"},
		{"title": "老式木算盘", "en": "Wooden Abacus", "value": 26, "rarity": 1, "grid": "1×2", "icon": "abacus", "lore": "供销社旧柜台留下的老紫木七珠算盘，珠粒圆润。"},
		{"title": "铁皮铅笔盒", "en": "Tin Pencil Case", "value": 27, "rarity": 1, "grid": "1×2", "icon": "pencil_tin", "lore": "印有山水线条的怀旧绿漆铁皮文具盒。"},
		{"title": "老竹尺", "en": "Bamboo Ruler", "value": 29, "rarity": 1, "grid": "1×1", "icon": "bamboo_ruler", "lore": "烟山老裁缝与木匠常用的刻度毛竹直尺。"},
		{"title": "干桂花香包", "en": "Osmanthus Sachet", "value": 31, "rarity": 1, "grid": "1×1", "icon": "osmanthus_pack", "lore": "装满金秋干桂花的明黄束口小香囊，幽香扑鼻。"},
		{"title": "旧黄铜钥匙串", "en": "Brass Key Ring", "value": 33, "rarity": 1, "grid": "1×1", "icon": "key_ring", "lore": "系在铜环上的三把老仓库黄铜钥匙，敲击清脆。"},
		{"title": "军绿旧水壶", "en": "Field Canteen", "value": 35, "rarity": 1, "grid": "1×2", "icon": "canteen", "lore": "装满清甜山泉水的帆布背带铝制野外水壶。"},
		{"title": "尼龙登山绳", "en": "Climbing Rope", "value": 37, "rarity": 1, "grid": "1×2", "icon": "rope_coil", "lore": "配有金属快挂扣的橙色高强度山崖攀登绳索。"}
	],
	2: [
		{"title": "林间指北针", "en": "Forest Compass", "value": 48, "rarity": 2, "grid": "1×1", "icon": "compass", "lore": "夜光表盘金属指北针，在竹石迷阵中辨位极准。"},
		{"title": "防水战术手电", "en": "Tactical Flashlight", "value": 54, "rarity": 2, "grid": "1×1", "icon": "torch", "lore": "探索烟霞古洞幽暗石室的高流明铝合金手电。"},
		{"title": "巡护员徽章", "en": "Ranger Badge", "value": 58, "rarity": 2, "grid": "1×1", "icon": "badge", "lore": "镌有香樟叶与山溪纹样的烟山护林纪念章。"},
		{"title": "烟山手工折扇", "en": "Bamboo Folding Fan", "value": 62, "rarity": 2, "grid": "1×1", "icon": "fan", "lore": "取烟山老毛竹做扇骨、题有山水小楷的江南折扇。"},
		{"title": "溪石萤光矿", "en": "Stream Fluorite", "value": 66, "rarity": 2, "grid": "1×1", "icon": "gem", "lore": "鹅卵石山溪冲刷出的淡青色天然萤石原矿。"},
		{"title": "朱漆首饰匣", "en": "Red Lacquer Box", "value": 46, "rarity": 2, "grid": "1×2", "icon": "lacquer_box", "lore": "镶着黄铜包角与蝶形暗扣的江南朱红漆木匣。"},
		{"title": "青花品茗杯", "en": "Blue Porcelain Cup", "value": 50, "rarity": 2, "grid": "1×1", "icon": "blue_teacup", "lore": "配花梨木杯托的手绘缠枝青花细瓷品茗杯。"},
		{"title": "工兵折叠铲", "en": "Folding Shovel", "value": 55, "rarity": 2, "grid": "1×2", "icon": "folding_shovel", "lore": "可快速锁紧折叠的锰钢战术工兵铲，掘土破障两用。"},
		{"title": "信号发烟罐", "en": "Signal Smoke Can", "value": 59, "rarity": 2, "grid": "1×1", "icon": "smoke_can", "lore": "用于标定撤离信标与掩护转移的战术拉环烟雾罐。"},
		{"title": "湖笔书写套组", "en": "Calligraphy Brush", "value": 63, "rarity": 2, "grid": "1×2", "icon": "brush_set", "lore": "青瓷五峰笔山配兼毫湖笔，书房案头清雅文具。"},
		{"title": "铜制电报发报键", "en": "Telegraph Key", "value": 68, "rarity": 2, "grid": "1×2", "icon": "morse_key", "lore": "底座厚重的经典黄铜摩斯电码发报手键，回弹清脆。"},
		{"title": "烟山草药标本匣", "en": "Herb Specimen Box", "value": 72, "rarity": 2, "grid": "1×2", "icon": "herb_case", "lore": "封存珍稀烟山蕨类压花与英文拉丁注记的木框标本。"}
	],
	3: [
		{"title": "加密无线电台", "en": "Encrypted Radio", "value": 82, "rarity": 3, "grid": "1×2", "icon": "radio", "lore": "双频抗干扰战术步话机，可截获词兵调动信号。"},
		{"title": "光学测距模块", "en": "Laser Rangefinder", "value": 90, "rarity": 3, "grid": "1×2", "icon": "rangefinder", "lore": "高精度红外测距仪，精密镜片完好无损。"},
		{"title": "古树琥珀标本", "en": "Ancient Amber", "value": 96, "rarity": 3, "grid": "1×1", "icon": "amber", "lore": "凝结着远古松针与小虫的金透树脂琥珀。"},
		{"title": "军规夜视镜片", "en": "Night Vision Lens", "value": 106, "rarity": 3, "grid": "1×2", "icon": "nvg_lens", "lore": "镀有翠绿增透膜的微光夜视仪核心光学组件。"},
		{"title": "太湖透漏赏石", "en": "Taihu Scholar Rock", "value": 115, "rarity": 3, "grid": "1×2", "icon": "rock", "lore": "迷踪竹石阵中历经山泉溶蚀、瘦皱漏透的案头奇石。"},
		{"title": "军用双筒望远镜", "en": "Field Binoculars", "value": 86, "rarity": 3, "grid": "1×2", "icon": "binoculars", "lore": "覆有防滑胶皮与绿膜物镜的侦察兵高倍望远镜。"},
		{"title": "雕花黄铜墨盒", "en": "Carved Ink Box", "value": 94, "rarity": 3, "grid": "1×1", "icon": "ink_box", "lore": "翻盖浮雕祥云的精工老铜墨盒，墨丝依然润泽。"},
		{"title": "松烟鎏金古墨锭", "en": "Pine Soot Inkstick", "value": 102, "rarity": 3, "grid": "1×1", "icon": "inkstick", "lore": "描金松烟八角徽墨，置于花梨小座上，历久弥香。"},
		{"title": "江南苏绣锦囊", "en": "Suzhou Silk Pouch", "value": 108, "rarity": 3, "grid": "1×1", "icon": "silk_pouch", "lore": "以金线翠缎精绣云水菱纹并缀翡翠珠的江南锦囊。"},
		{"title": "便携气象测风仪", "en": "Wind Meter", "value": 114, "rarity": 3, "grid": "1×2", "icon": "anemometer", "lore": "带三杯风速转子的山地侦察气象测风终端。"},
		{"title": "机械铜壳怀表", "en": "Brass Pocket Watch", "value": 122, "rarity": 3, "grid": "1×1", "icon": "pocket_watch", "lore": "翻盖罗马字面机械铜怀表，齿轮滴答走时精准。"}
	],
	4: [
		{"title": "无人机核心芯片", "en": "Drone AI Chip", "value": 145, "rarity": 4, "grid": "1×1", "icon": "chip", "lore": "迅捷侦察机搭载的高算力飞控与词库阵列芯片。"},
		{"title": "竹海古玉残片", "en": "Ancient Jade Piece", "value": 155, "rarity": 4, "grid": "1×1", "icon": "jade_piece", "lore": "竹林深处出土的温润青白玉璜残件，沁色古朴。"},
		{"title": "军用黑匣子", "en": "Flight Black Box", "value": 165, "rarity": 4, "grid": "1×2", "icon": "blackbox", "lore": "防爆橙红涂装战术记录仪，存有珍贵加密航迹。"},
		{"title": "烟霞岩画残拓", "en": "Petroglyph Rubbing", "value": 175, "rarity": 4, "grid": "1×2", "icon": "rubbing", "lore": "拓印自烟霞古洞原生石壁《烟山耕读》的宣纸墨拓。"},
		{"title": "古樟祈福银锁", "en": "Silver Blessing Lock", "value": 188, "rarity": 4, "grid": "1×1", "icon": "silver_lock", "lore": "百年古樟石龛旁流传的江南錾花长命银锁。"},
		{"title": "先民青铜茶铫", "en": "Bronze Tea Kettle", "value": 198, "rarity": 4, "grid": "2×2", "icon": "kettle", "lore": "古洞寒潭畔先民汲泉煮茗所用的绿锈小青铜壶。"},
		{"title": "鎏金点翠银簪", "en": "Gilded Hairpin", "value": 150, "rarity": 4, "grid": "1×2", "icon": "hairpin", "lore": "点翠云凤镶珠鎏金老银簪，工艺清雅绝伦。"},
		{"title": "青瓷蟾蜍水注", "en": "Celadon Water Dropper", "value": 162, "rarity": 4, "grid": "1×2", "icon": "water_dropper", "lore": "越窑系青绿冰裂釉造型水注，文人研墨清供雅玩。"},
		{"title": "微光瞄具光学核", "en": "Thermal Optic Core", "value": 180, "rarity": 4, "grid": "1×2", "icon": "optic_core", "lore": "锗晶体琥珀镀膜热成像光学棱镜核心组件。"},
		{"title": "端溪雕云古砚", "en": "Duanxi Inkstone", "value": 192, "rarity": 4, "grid": "2×2", "icon": "inkstone", "lore": "紫润细腻、带红木嵌盒的端溪老坑雕云文房名砚。"}
	],
	5: [
		{"title": "海兽葡萄错银铜镜", "en": "Silver Inlaid Mirror", "value": 215, "rarity": 5, "grid": "2×2", "icon": "bronze_mirror", "lore": "【珍品·小金】唐代瑞兽葡萄纹错银青铜古镜，红木托架保存完好。"},
		{"title": "战备量子加密硬盘", "en": "Encrypted Hard Drive", "value": 230, "rarity": 5, "grid": "1×2", "icon": "crypto_drive", "lore": "【珍品·小金】AES-512 钛金装甲防爆移动硬盘，藏有烟山密电档案。"},
		{"title": "宜兴朱泥水平壶", "en": "Zisha Clay Teapot", "value": 245, "rarity": 5, "grid": "2×2", "icon": "zisha_teapot", "lore": "【珍品·小金】名家手抟原矿朱泥水平紫砂壶，包浆温润如玉。"},
		{"title": "翡翠节节高玉佩", "en": "Jade Bamboo Pendant", "value": 255, "rarity": 5, "grid": "1×2", "icon": "jade_pendant", "lore": "【珍品·小金】冰种阳绿雕刻竹节平安玉佩，寓意学业步步高升。"},
		{"title": "复古黄铜旁轴相机", "en": "Vintage Film Camera", "value": 270, "rarity": 5, "grid": "2×2", "icon": "vintage_camera", "lore": "【珍品·小金】精工露铜经典机械旁轴胶片机，记录昔日烟山风貌。"},
		{"title": "御窑青花缠枝盏", "en": "Imperial Blue Bowl", "value": 285, "rarity": 5, "grid": "2×2", "icon": "imperial_bowl", "lore": "【珍品·小金】描金口沿高足御窑青花缠枝莲纹盏，发色浓艳明丽。"}
	],
	6: [
		{"title": "烟山古铜虎符", "en": "Bronze Tiger Tally", "value": 340, "rarity": 6, "grid": "1×2", "icon": "tally", "lore": "【传说·大金】错金铭文古铜兵符，印证烟山古道昔日戍守历史。"},
		{"title": "特级金质勋章", "en": "Supreme Gold Medal", "value": 365, "rarity": 6, "grid": "1×1", "icon": "medal", "lore": "【传说·大金】表彰卓越战术识词先锋的纯金浮雕荣誉勋章。"},
		{"title": "量子词典原型机", "en": "Quantum Dictionary", "value": 395, "rarity": 6, "grid": "2×2", "icon": "quantum", "lore": "【传说·大金】搭载全息声纹解码核心的实验级双语终端原型机。"},
		{"title": "烟山先民竹简", "en": "Ancient Bamboo Slips", "value": 420, "rarity": 6, "grid": "2×2", "icon": "slips", "lore": "【传说·大金】烟霞古洞石案遗留的千年墨书竹简，记载诚庄耕读往事。"},
		{"title": "烟山统领黄金核心", "en": "Warden Golden Core", "value": 460, "rarity": 6, "grid": "2×2", "icon": "core", "lore": "【传说·大金】雾隐帮统领（玄铁词尊 / 铁面词卫）胸腔卸载的高纯度聚变黄金能源核心。"},
		{"title": "望稻亭鎏金香炉", "en": "Gilded Incense Burner", "value": 495, "rarity": 6, "grid": "2×2", "icon": "censer", "lore": "【传说·大金】镂空博山云纹鎏金铜炉，昔年文人登亭望稻时焚香雅器。"}
	],
	7: [
		{"title": "越窑秘色青瓷盏", "en": "Secret Celadon Bowl", "value": 680, "rarity": 7, "grid": "2×2", "icon": "celadon", "lore": "【旷世·大红】如冰似玉、千峰翠色的唐宋越窑秘色贡瓷孤品！"},
		{"title": "烟山千年紫芝王", "en": "Millennium Ganoderma", "value": 760, "rarity": 7, "grid": "2×2", "icon": "ganoderma", "lore": "【旷世·大红】生于烟山绝壁云雾深处、紫气莹润的千年灵芝王！"},
		{"title": "诚庄先民双龙玉璧", "en": "Twin-Dragon Jade Disc", "value": 840, "rarity": 7, "grid": "2×2", "icon": "jade_bi", "lore": "【旷世·大红】精雕江南水云双龙纹的羊脂白玉礼璧，价值连城！"},
		{"title": "相控阵超算雷达心", "en": "Quantum Radar Core", "value": 920, "rarity": 7, "grid": "2×3", "icon": "radar_heart", "lore": "【旷世·大红】统御全山防空与电讯阵列最高权限的超算红核！"},
		{"title": "烟山之心·赤金龙印", "en": "Heart of Yanshan", "value": 1050, "rarity": 7, "grid": "2×2", "icon": "seal", "lore": "【旷世·大红】赤金镶嵌红宝的镇山宝印——摸金行动最高荣耀象征！"}
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
var prologue_mode = false
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
var safe_box = []
var last_saved_safe_box_count = 0
var crates = []
var supplies_opened = []
var loot_rng := RandomNumberGenerator.new()

var profile = {
	"schema_version": PROFILE_SCHEMA_VERSION,
	"saved_by_version": "0.8.3",
	"coins": 0,
	"xp": 0,
	"points": 0,
	"reputation": 0,
	"active_ranger": "shaoyu",
	"unlocked_rangers": ["shaoyu"],
	"character_cards": ["shaoyu"],
	"bounties_completed": 0,
	"warehouse": [],
	"display_stand": [],
	"owned": [],
	"equipped": {"optic": "", "muzzle": "", "grip": ""},
	"extractions": 0,
	"prologue_completed": false,
	"prologue_best_seconds": 0,
	"mastery": {},
	"review_due": {},
	"learning_stats": {},
	"settings": DEFAULT_SETTINGS.duplicate(true),
	"last_run": {},
	"stats": {},
	"achievements": [],
	"unlocked_charms": [],
	"equipped_charm": "",
	"collection": [],
	"red_extracted": 0,
	"gold_extracted": 0,
	"small_gold_extracted": 0,
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
	var has_rig: bool = "tactical_rig" in profile.owned
	if is_confidential():
		return 18 if has_rig else 12
	return 24 if has_rig else 16

func max_reserve_ammo() -> int:
	if not combat_mode:
		return -1
	var has_rig: bool = "tactical_rig" in profile.owned
	if is_confidential():
		return 48 if has_rig else 36
	return 60 if has_rig else 48

func ground_ammo_gain() -> int:
	return 6 if is_confidential() else 8

func ammo_crate_respawn_seconds() -> float:
	return 150.0 if is_confidential() else 90.0

func melee_hits_to_kill() -> int:
	return 10 if is_confidential() else 5

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

func ensure_ranger_profile():
	if not profile.has("reputation"):
		profile["reputation"] = 0
	profile["reputation"] = maxi(0, int(profile.get("reputation", 0)))
	if not profile.has("bounties_completed"):
		profile["bounties_completed"] = 0
	profile["bounties_completed"] = maxi(0, int(profile.get("bounties_completed", 0)))
	if not profile.has("unlocked_rangers") or not (profile.unlocked_rangers is Array):
		profile["unlocked_rangers"] = ["shaoyu"]
	if not ("shaoyu" in profile.unlocked_rangers):
		profile.unlocked_rangers.insert(0, "shaoyu")
	var ar := str(profile.get("active_ranger", "shaoyu"))
	if ar == "" or not (ar in profile.unlocked_rangers):
		profile["active_ranger"] = "shaoyu"
	if not profile.has("character_cards") or not (profile.character_cards is Array):
		profile["character_cards"] = ["shaoyu"]
	if not ("shaoyu" in profile.character_cards):
		profile.character_cards.insert(0, "shaoyu")

func ensure_settings() -> Dictionary:
	if not profile.has("settings") or not (profile["settings"] is Dictionary):
		profile["settings"] = DEFAULT_SETTINGS.duplicate(true)
	var st: Dictionary = profile["settings"]
	for k in DEFAULT_SETTINGS:
		if not st.has(k):
			st[k] = DEFAULT_SETTINGS[k]
	st["strict_daily_review"] = bool(st.get("strict_daily_review", true))
	st["auto_speak_on_switch"] = bool(st.get("auto_speak_on_switch", true))
	st["reduce_screen_shake"] = bool(st.get("reduce_screen_shake", false))
	st["sfx_volume"] = clampf(float(st.get("sfx_volume", 1.0)), 0.0, 1.0)
	st["voice_volume"] = clampf(float(st.get("voice_volume", 1.0)), 0.0, 1.0)
	st["mouse_sensitivity"] = clampf(float(st.get("mouse_sensitivity", 1.0)), 0.4, 2.2)
	return st

func setting(key: String, fallback = null):
	var st := ensure_settings()
	return st.get(key, DEFAULT_SETTINGS.get(key, fallback))

func set_setting(key: String, value):
	var st := ensure_settings()
	st[key] = value
	ensure_settings()

func level() -> int:
	return 1 + int(profile.xp / 120)

func is_confidential() -> bool:
	return combat_mode and operation_tier == "confidential"

func can_loot() -> bool:
	# v0.8.1 #15: Practice Range ('自由靶场') & Prologue have no field loot boxes
	return combat_mode and not prologue_mode

func required_extract_accuracy() -> float:
	if not combat_mode:
		return 0.0
	return CONFIDENTIAL_EXTRACT_ACCURACY if is_confidential() else NORMAL_EXTRACT_ACCURACY

func accuracy_gate_met() -> bool:
	if not combat_mode:
		return true
	return answered > 0 and accuracy() >= required_extract_accuracy() - 0.0001

func mode_label() -> String:
	if prologue_mode:
		return "烟山初行·序章"
	if not combat_mode:
		return "自由靶场"
	return "机密行动" if operation_tier == "confidential" else "普通行动"

func migrate_legacy_items():
	var legacy_schema: bool = int(profile.get("schema_version", 1)) < 2
	if profile.has("collection") and profile.collection is Array:
		for i in profile.collection.size():
			if str(profile.collection[i]) == "烟霞丹青残拓":
				profile.collection[i] = "烟霞岩画残拓"
	if profile.has("warehouse") and profile.warehouse is Array:
		for item in profile.warehouse:
			if item is Dictionary:
				if str(item.get("title", "")) == "烟霞丹青残拓":
					item["title"] = "烟霞岩画残拓"
				var meta := catalog_meta(str(item.get("title", "")))
				if legacy_schema and not meta.is_empty():
					item["rarity"] = int(meta.rarity)
				else:
					item["rarity"] = clampi(int(item.get("rarity", meta.get("rarity", 1))), 1, MAX_RARITY)
				if not item.has("locked"):
					item["locked"] = int(item.get("rarity", 1)) >= 6
	for int_key in ["red_extracted", "gold_extracted", "small_gold_extracted", "best_haul", "best_item_value", "prologue_best_seconds"]:
		profile[int_key] = maxi(0, int(profile.get(int_key, 0)))
	profile["prologue_completed"] = bool(profile.get("prologue_completed", false))
	profile["best_item_title"] = str(profile.get("best_item_title", ""))
	if not profile.has("display_stand") or not (profile.display_stand is Array):
		profile["display_stand"] = []
	var cleaned_stand: Array = []
	for t in profile.display_stand:
		var ts := str(t)
		if ts != "" and not (ts in cleaned_stand) and not catalog_meta(ts).is_empty():
			cleaned_stand.append(ts)
			if cleaned_stand.size() >= MAX_DISPLAY_STAND:
				break
	profile["display_stand"] = cleaned_stand
	if not profile.has("learning_stats") or not (profile["learning_stats"] is Dictionary):
		profile["learning_stats"] = {}
	ensure_settings()
	ensure_ranger_profile()
	profile["schema_version"] = PROFILE_SCHEMA_VERSION

static func catalog_meta(title: String) -> Dictionary:
	for r in LOOT_TABLE:
		for entry in LOOT_TABLE[r]:
			if str(entry.title) == title:
				return entry
	return {}

static func total_collectible_count() -> int:
	return LOOT_TABLE[4].size() + LOOT_TABLE[5].size() + LOOT_TABLE[6].size() + LOOT_TABLE[7].size()

static func total_catalog_count() -> int:
	var n := 0
	for r in LOOT_TABLE:
		n += LOOT_TABLE[r].size()
	return n

func start_run(as_combat = false, tier: String = "normal"):
	phase = "active"
	prologue_mode = (tier == "prologue")
	combat_mode = as_combat and not prologue_mode
	operation_tier = "prologue" if prologue_mode else ("confidential" if (combat_mode and tier == "confidential") else "normal")
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
	safe_box = []
	last_saved_safe_box_count = 0
	crates = []
	supplies_opened = []
	question_open = false
	learning.reset_run_stats()

func open_question():
	question_open = phase == "active"

func answer(is_correct: bool, word_id: String = "", choice_count := 4, used_help := false, scene := "combat_word", modality := "recognition") -> bool:
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
		learning.record_recognition(word_id, is_correct, choice_count, used_help, -1, scene, modality)
	return true

func word_priority(word_id: String) -> float:
	if SrsScheduler.is_due(profile, word_id):
		return 4.2
	if not profile.mastery.has(word_id):
		return 2.2
	var m = profile.mastery[word_id]
	if not (m is Dictionary):
		return 2.0
	if str(m.get("last_outcome", "")) == LearningStore.PRACTICED and int(m.get("srs_stage", 0)) == 0:
		return 2.9
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
	var r := clampi(int(raw.get("rarity", meta.get("rarity", 1))), 1, MAX_RARITY)
	var en_s := str(raw.get("en", ""))
	if en_s == "":
		en_s = str(meta.get("en", "Supply Item"))
	var grid_s := str(raw.get("grid", ""))
	if grid_s == "":
		grid_s = str(meta.get("grid", "2×2" if r >= 5 else ("1×2" if r >= 3 else "1×1")))
	var icon_s := str(raw.get("icon", ""))
	if icon_s == "":
		icon_s = str(meta.get("icon", "core" if r >= 6 else ("bronze_mirror" if r == 5 else ("chip" if r >= 3 else "ration"))))
	var cond_s := str(raw.get("cond", ""))
	if cond_s == "":
		cond_s = "标准"
	var lore_s := str(raw.get("lore", ""))
	if lore_s == "":
		lore_s = str(meta.get("lore", "烟山行动搜刮物资。"))
	var out := {
		"title": title,
		"en": en_s,
		"value": maxi(1, int(raw.get("value", meta.get("value", 25)))),
		"rarity": r,
		"grid": grid_s,
		"icon": icon_s,
		"cond": cond_s,
		"lore": lore_s
	}
	if raw.has("locked"):
		out["locked"] = bool(raw.get("locked", false))
	return out

func add_loot(title: String, value: int, rarity: int = 1, extra: Dictionary = {}) -> bool:
	if phase != "active" or not can_loot() or bag.size() >= capacity():
		return false
	var merged := extra.duplicate()
	merged["title"] = title
	merged["value"] = value
	merged["rarity"] = clampi(rarity, 1, MAX_RARITY)
	bag.append(_enrich_loot_dict(merged))
	return true

func add_loot_item(item: Dictionary) -> bool:
	if phase != "active" or not can_loot() or bag.size() >= capacity():
		return false
	bag.append(_enrich_loot_dict(item))
	return true

func discard_bag_item(index: int) -> Dictionary:
	if phase != "active" or index < 0 or index >= bag.size():
		return {}
	var removed: Dictionary = bag[index]
	bag.remove_at(index)
	return removed

func move_bag_to_safe_box(bag_index: int) -> bool:
	if phase not in ["active", "extracting"]:
		return false
	if bag_index < 0 or bag_index >= bag.size() or safe_box.size() >= SAFE_BOX_SLOTS:
		return false
	var item: Dictionary = bag[bag_index]
	bag.remove_at(bag_index)
	safe_box.append(item)
	return true

func move_safe_box_to_bag(safe_index: int) -> bool:
	if phase not in ["active", "extracting"]:
		return false
	if safe_index < 0 or safe_index >= safe_box.size() or bag.size() >= capacity():
		return false
	var item: Dictionary = safe_box[safe_index]
	safe_box.remove_at(safe_index)
	bag.append(item)
	return true

func safe_box_value() -> int:
	var result := 0
	for item in safe_box:
		result += int(item.get("value", 0))
	return result

func total_carried_value() -> int:
	return bag_value() + safe_box_value()

func _roll_condition() -> Dictionary:
	var p := loot_rng.randf()
	var acc := 0.0
	for c in CONDITION_TIERS:
		acc += float(c.weight)
		if p <= acc:
			return c
	return CONDITION_TIERS[1]

func _roll_from_weights(weights_7_to_1: Array) -> int:
	var p := loot_rng.randf()
	var acc := 0.0
	for i in weights_7_to_1.size():
		acc += float(weights_7_to_1[i])
		if p <= acc:
			return MAX_RARITY - i
	return 1

func roll_calibrated_rarity(mode_confidential: bool, context: String = "standard", perfect: bool = true) -> int:
	## v0.8.0 strictly calibrated 7-tier drop curves [T7 Red, T6 Big Gold, T5 Small Gold, T4 Purple, T3 Blue, T2 Green, T1 White]:
	## - Confidential standard: 2.0% Red / 5.0% Big Gold / 8.0% Small Gold / 14% Purple / 21% Blue / 24% Green / 26% White
	## - Normal standard: clearly lower Big Gold/Red so Confidential Risk-Reward truly shines
	## - Open-road loose spawns: strictly capped at T1-T4 (Confidential) / T1-T3 (Normal) — ZERO open-road Big Gold/Red!
	if context == "loose_open":
		if mode_confidential:
			return _roll_from_weights([0.000, 0.000, 0.000, 0.140, 0.260, 0.300, 0.300])
		return _roll_from_weights([0.000, 0.000, 0.000, 0.000, 0.220, 0.360, 0.420])
	if context == "hidden_nook":
		if mode_confidential:
			return _roll_from_weights([0.025, 0.055, 0.090, 0.150, 0.210, 0.230, 0.240])
		return _roll_from_weights([0.004, 0.014, 0.045, 0.127, 0.220, 0.270, 0.320])
	if context == "crate_t1":
		if mode_confidential:
			return _roll_from_weights([0.015, 0.045, 0.080, 0.150, 0.220, 0.240, 0.250] if perfect else [0.008, 0.028, 0.064, 0.140, 0.230, 0.260, 0.270])
		return _roll_from_weights([0.000, 0.008, 0.040, 0.132, 0.230, 0.280, 0.310] if perfect else [0.000, 0.004, 0.026, 0.100, 0.220, 0.300, 0.350])
	if context == "crate_t2":
		if mode_confidential:
			return _roll_from_weights([0.025, 0.060, 0.100, 0.175, 0.220, 0.220, 0.200] if perfect else [0.012, 0.036, 0.072, 0.150, 0.230, 0.250, 0.250])
		return _roll_from_weights([0.003, 0.016, 0.055, 0.156, 0.240, 0.260, 0.270] if perfect else [0.000, 0.008, 0.034, 0.118, 0.230, 0.290, 0.320])
	if context == "crate_t3":
		if mode_confidential:
			return _roll_from_weights([0.040, 0.085, 0.125, 0.200, 0.230, 0.190, 0.130] if perfect else [0.020, 0.050, 0.090, 0.170, 0.230, 0.230, 0.210])
		return _roll_from_weights([0.008, 0.028, 0.075, 0.189, 0.240, 0.240, 0.220] if perfect else [0.002, 0.012, 0.046, 0.140, 0.240, 0.270, 0.290])
	if context == "squad_drop":
		if mode_confidential:
			return _roll_from_weights([0.022, 0.053, 0.085, 0.150, 0.210, 0.235, 0.245] if perfect else [0.014, 0.040, 0.076, 0.140, 0.220, 0.250, 0.260])
		return _roll_from_weights([0.002, 0.012, 0.045, 0.131, 0.230, 0.270, 0.310] if perfect else [0.000, 0.006, 0.030, 0.114, 0.220, 0.290, 0.340])
	# Default / standard supply blind-box
	if mode_confidential:
		return _roll_from_weights([0.020, 0.050, 0.080, 0.140, 0.210, 0.240, 0.260] if perfect else [0.010, 0.032, 0.068, 0.130, 0.220, 0.260, 0.280])
	return _roll_from_weights([0.000, 0.008, 0.035, 0.117, 0.220, 0.280, 0.340] if perfect else [0.000, 0.003, 0.022, 0.095, 0.210, 0.300, 0.370])

func roll_item_by_rarity(rarity: int) -> Dictionary:
	var clamped := clampi(rarity, 1, MAX_RARITY)
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
	# v0.8.0 Blind-Box Supply Case: no visual spoiler; secret lucky caches gently bump odds without guaranteeing red
	var ctx := "hidden_nook" if overcharged else "standard"
	var r := roll_calibrated_rarity(is_confidential(), ctx, perfect_spell)
	return roll_item_by_rarity(r)

func roll_world_loose_item(_high_tier_spot: bool = false) -> Dictionary:
	# v0.8.0 #10: Open-road table loot strictly never rolls Big Gold (T6) or Mythic Red (T7)!
	var r := roll_calibrated_rarity(is_confidential(), "loose_open", true)
	return roll_item_by_rarity(r)

func roll_bird_nest_item() -> Dictionary:
	## Iconic '掏鸟窝 / 摸草丛 / 探桥角石缝' ultra-hidden stash lottery!
	var r := roll_calibrated_rarity(is_confidential(), "hidden_nook", true)
	return roll_item_by_rarity(r)

func roll_squad_drop_items(flawless_wave: bool, is_boss_camp: bool = false) -> Array:
	var count := 2 if (flawless_wave or is_boss_camp) else (2 if loot_rng.randf() < 0.45 else 1)
	var out := []
	for i in count:
		var r := roll_calibrated_rarity(is_confidential(), "crate_t2" if (is_boss_camp and i == 0) else "squad_drop", flawless_wave or is_boss_camp)
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
	var ctx := "crate_t1" if tier <= 1 else ("crate_t2" if tier == 2 else "crate_t3")
	return roll_calibrated_rarity(is_confidential(), ctx, perfect_spell)

func open_crate(crate_id: String, tier: int, perfect_spell: bool = false) -> Array:
	var awarded = []
	if not can_loot() or crate_id in crates or not crate_ready(tier) or bag.size() >= capacity():
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
	if not can_loot() or crate_id in crates or not crate_ready(tier):
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
	if combat_mode and (outposts_cleared < 2 or not boss_defeated or not accuracy_gate_met()):
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
	if r >= 7:
		profile["red_extracted"] = int(profile.get("red_extracted", 0)) + 1
	elif r == 6:
		profile["gold_extracted"] = int(profile.get("gold_extracted", 0)) + 1
	elif r == 5:
		profile["small_gold_extracted"] = int(profile.get("small_gold_extracted", 0)) + 1
	if val > int(profile.get("best_item_value", 0)):
		profile["best_item_value"] = val
		profile["best_item_title"] = str(item.get("title", ""))

func _bank_items_to_warehouse(items: Array):
	for raw_it in items:
		var banked: Dictionary = _enrich_loot_dict(raw_it)
		var r: int = int(banked.get("rarity", 1))
		if not banked.has("locked"):
			banked["locked"] = (r >= 6)
		_record_extracted_item(banked)
		profile.warehouse.append(banked)

func finish_extraction() -> bool:
	if phase != "extracting":
		return false
	if combat_mode and outposts_cleared >= 2 and bag.size() < capacity():
		var bonus_r := 4
		if is_confidential():
			var p_c := loot_rng.randf()
			bonus_r = 7 if (boss_defeated and p_c < 0.06) else (6 if p_c < 0.38 else 5)
		else:
			var p_n := loot_rng.randf()
			bonus_r = 6 if (boss_defeated and p_n < 0.06) else (5 if p_n < 0.40 else 4)
		var bonus_item := roll_item_by_rarity(bonus_r)
		bag.append(bonus_item)
	var run_haul := total_carried_value()
	if run_haul > int(profile.get("best_haul", 0)):
		profile["best_haul"] = run_haul
	var all_brought: Array = bag.duplicate(true)
	all_brought.append_array(safe_box.duplicate(true))
	last_saved_safe_box_count = safe_box.size()
	_bank_items_to_warehouse(all_brought)
	var gained_xp: int = int(correct) * 6 + int(outposts_cleared) * 25 + int(perfect_ciphers) * 15 + (60 if boss_defeated else 0) + 60
	if is_confidential():
		gained_xp = roundi(float(gained_xp) * CONFIDENTIAL_VALUE_MULT)
	profile.xp += gained_xp
	profile.extractions += 1
	bag.clear()
	safe_box.clear()
	phase = "result"
	return true

func abandon():
	# v0.8.0: Regular bag is lost on failed run / retreat, but Encrypted Safe Box (2 slots) ALWAYS survives!
	last_saved_safe_box_count = safe_box.size()
	if not safe_box.is_empty():
		_bank_items_to_warehouse(safe_box.duplicate(true))
		safe_box.clear()
	bag.clear()
	question_open = false
	phase = "result"

func is_on_display_stand(title: String) -> bool:
	if not profile.has("display_stand") or not (profile.display_stand is Array):
		return false
	return title in profile.display_stand

func toggle_display_stand(title: String) -> Dictionary:
	if phase in ["active", "extracting"]:
		return {"ok": false, "reason": "in_run"}
	if not profile.has("display_stand") or not (profile.display_stand is Array):
		profile["display_stand"] = []
	var stand: Array = profile.display_stand
	if title in stand:
		stand.erase(title)
		return {"ok": true, "pinned": false}
	if stand.size() >= MAX_DISPLAY_STAND:
		return {"ok": false, "reason": "full"}
	stand.append(title)
	# Auto-lock at least one matching copy in warehouse so displayed treasure is safe!
	for it in profile.warehouse:
		if it is Dictionary and str(it.get("title", "")) == title:
			it["locked"] = true
			break
	return {"ok": true, "pinned": true}

func toggle_warehouse_lock(idx: int) -> bool:
	if phase in ["active", "extracting"] or idx < 0 or idx >= profile.warehouse.size():
		return false
	var item: Dictionary = profile.warehouse[idx]
	var next_locked: bool = not bool(item.get("locked", false))
	item["locked"] = next_locked
	return next_locked

func sell_warehouse_item(idx: int) -> int:
	if phase in ["active", "extracting"] or idx < 0 or idx >= profile.warehouse.size():
		return 0
	var item: Dictionary = profile.warehouse[idx]
	if bool(item.get("locked", false)):
		return 0
	var val: int = int(item.get("value", 0))
	var sold_title: String = str(item.get("title", ""))
	profile.coins += val
	profile.warehouse.remove_at(idx)
	# If last copy of a displayed item was unlocked & sold, also remove from display stand
	var still_owned := false
	for rem in profile.warehouse:
		if rem is Dictionary and str(rem.get("title", "")) == sold_title:
			still_owned = true
			break
	if not still_owned and is_on_display_stand(sold_title):
		profile.display_stand.erase(sold_title)
	return val

func sell_unlocked_junk(max_rarity: int = 3) -> Dictionary:
	if phase in ["active", "extracting"]:
		return {"count": 0, "coins": 0}
	var kept := []
	var sold_count := 0
	var sold_coins := 0
	for item in profile.warehouse:
		var is_locked := bool(item.get("locked", false))
		var r := int(item.get("rarity", 1))
		if not is_locked and r <= max_rarity:
			sold_count += 1
			sold_coins += int(item.get("value", 0))
		else:
			kept.append(item)
	profile.warehouse = kept
	profile.coins += sold_coins
	return {"count": sold_count, "coins": sold_coins}

func unlocked_warehouse_value() -> int:
	var sum := 0
	for item in profile.warehouse:
		if not bool(item.get("locked", false)):
			sum += int(item.get("value", 0))
	return sum

func unlocked_warehouse_count() -> int:
	var n := 0
	for item in profile.warehouse:
		if not bool(item.get("locked", false)):
			n += 1
	return n

func locked_warehouse_count() -> int:
	var n := 0
	for item in profile.warehouse:
		if bool(item.get("locked", false)):
			n += 1
	return n

func sell_all() -> int:
	# Sells all UNLOCKED items in warehouse; locked treasures stay safely preserved!
	if phase in ["active", "extracting"]:
		return 0
	var total := 0
	var kept := []
	for item in profile.warehouse:
		if bool(item.get("locked", false)):
			kept.append(item)
		else:
			total += int(item.get("value", 0))
	profile.coins += total
	profile.warehouse = kept
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
