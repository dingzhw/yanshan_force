"""Build three offline discussion documents and a fictional level-design map."""
from pathlib import Path
from html import escape
import json
import math
import hashlib

ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parents[2]
SOURCES=json.loads((ROOT/'source-index.json').read_text(encoding='utf-8'))
if not any(s['id']=='S19' for s in SOURCES):
    SOURCES.append(dict(id='S19',title='Various Small Arms (Assault Rifles, Sniper, Pistol)',publisher='Tabasco / OpenGameArt',source_type='Author asset page (search-index evidence)',date='2010-07-02; public-domain update 2023-12-15',accessed='2026-11-07',url_or_path='https://opengameart.org/node/3609',claims_supported='多种低面数枪械；多数枪栓/套筒有动画；无UV纹理，仅Blender材质；页面列CC0及历史CC-BY 3.0',reliability_notes='A - primary; 正文受robots限制，依据作者页面搜索索引；模型与包内许可需下载前复核',use_in_report='03 枪械候选'))
(ROOT/'source-index.json').write_text(json.dumps(SOURCES,ensure_ascii=False,indent=2),encoding='utf-8')
INDEX={s['id']:s for s in SOURCES}

def cite(*ids):
    return ' '.join(f'<a class="cite" href="{escape(INDEX[i]["url_or_path"])}" target="_blank" rel="noreferrer">[{i}]</a>' for i in ids)

CSS='''
:root{--ink:#26392e;--muted:#5d695e;--paper:#f4f2ea;--line:#cdd2c5;--accent:#526b43;--rust:#9b5a32}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.75 "Microsoft YaHei","Noto Sans SC",sans-serif}main{max-width:1180px;margin:auto;padding:42px 46px 70px}header{border-bottom:2px solid var(--ink);padding-bottom:24px;margin-bottom:30px}.eyebrow{font-size:13px;letter-spacing:2px;color:var(--muted)}h1{font-size:38px;line-height:1.3;letter-spacing:1px;margin:12px 0}h2{font-size:26px;margin:34px 0 14px}h3{font-size:19px;margin:15px 0 6px}p{margin:9px 0 15px}a{color:#395e42;text-underline-offset:3px}.cite{font-size:13px;white-space:nowrap}.lead{max-width:900px;font-size:21px;line-height:1.65}.meta,.caption{font-size:13px;color:var(--muted)}nav{display:flex;gap:22px;flex-wrap:wrap;margin-top:22px;font-size:15px}figure{margin:0}figure img{width:100%;display:block;border-radius:3px;background:#e7e8df}figcaption{font-size:14px;margin-top:8px;color:var(--muted)}.two{display:grid;grid-template-columns:1fr 1fr;gap:28px}.three{display:grid;grid-template-columns:repeat(3,1fr);gap:24px}.rule{border-top:1px solid var(--line);padding-top:18px}.note{border-left:4px solid var(--accent);padding:3px 18px;margin:24px 0;background:#e9ecdf}.status{font-size:13px;color:var(--rust);font-weight:600}.palette{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:22px 0}.swatch{height:62px;margin-bottom:7px}.palette span{font-size:14px}.tablewrap{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:15px;line-height:1.7}th,td{text-align:left;vertical-align:top;border-bottom:1px solid var(--line);padding:13px 12px}th{background:#e6e9df;font-size:14px}td:first-child{font-weight:600}ul,ol{padding-left:24px;margin:10px 0 18px}li{margin:5px 0}.strip{display:flex;gap:12px;align-items:center;flex-wrap:wrap;font-size:14px;margin:15px 0}.key{display:inline-block;width:30px;height:5px;vertical-align:middle;margin-right:6px}.dashed{border-top:4px dashed #795a3a;height:0}.map{width:100%;display:block}.sources{font-size:14px}.sources li{overflow-wrap:anywhere}footer{margin-top:40px;padding-top:20px;border-top:1px solid var(--line);font-size:13px;color:var(--muted)}.mini{font-size:14px}details{margin:16px 0}summary{cursor:pointer;font-weight:600}.badge-demo{display:flex;justify-content:center;align-items:center;min-height:180px;background:#56604a}.wordbadge{background:#e4e8d4;color:#172c24;padding:16px 32px;text-align:center;border:8px solid #343e32;font-size:30px;line-height:1.3}.wordbadge small{display:block;font-size:12px;letter-spacing:2px;margin-bottom:10px}
@media(max-width:760px){main{padding:25px 18px}h1{font-size:29px}.lead{font-size:18px}.two,.three{grid-template-columns:1fr}.palette{grid-template-columns:repeat(3,1fr)}table{min-width:740px}nav{gap:12px}th,td{padding:9px}}
@media print{body{background:white}main{max-width:none;padding:0}nav{display:none}h2,h3{break-after:avoid}figure,tr,.note{break-inside:avoid}a{color:inherit}.tablewrap{overflow:visible}table{min-width:0}footer{break-before:auto}}
'''
NAMES=['01-画面参考与美术方向.html','02-烟山基地地图草图.html','03-武器与环境素材候选.html']

def source_list(ids):
    return '<ol class="sources">'+''.join(f'<li><b>{i}</b> · {escape(INDEX[i]["title"])} — {escape(INDEX[i]["publisher"])}。<a href="{escape(INDEX[i]["url_or_path"])}">来源页面</a></li>' for i in ids)+'</ol>'

def document(n,title,lead,body):
    nav=''.join(f'<a href="{name}">{i+1:02d} · {label}</a>' for i,(name,label) in enumerate(zip(NAMES,['画面参考','地图草图','素材候选'])))
    text=f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{escape(title)}｜烟山基地讨论稿</title><style>{CSS}</style></head><body><main><header><div class="eyebrow">YANSHAN BASE / DISCUSSION {n:02d}</div><h1>{title}</h1><p class="lead">{lead}</p><div class="meta">2026.11.07 · 讨论稿 v1 · 半写实的江南山林探险 · 免费与开放许可素材优先</div><nav aria-label="三份讨论稿">{nav}</nav></header>{body}<footer>本稿为拟议方案；本轮仅增加规划材料与参考预览，未修改游戏。素材文件尚未导入验证；Vega 8 目标电脑的性能仍需实测。来源核对日期：2026-11-07。完整索引见同目录 source-index.json。</footer></main></body></html>'''
    (ROOT/NAMES[n-1]).write_text(text,encoding='utf-8')

art=f'''
<p class="status">已确定：画面方向与素材预算。下文的色彩、场景与镜头安排是供讨论的具体建议。</p>
<h2>先统一“像什么”</h2>
<p>想象一个雨后逐渐放晴的江南小山：脚下是有落叶的土路，坡脚长着苔藓，竹林后露出旧营房。地形有高低，树和石头有重量，枪支能看出金属、塑料与织物的差别。整体保持明亮，玩家能看清道路、敌人身上的单词和可探索的物件。</p>
<div class="two">
<figure><img src="references/mossy_forest.jpg" alt="Poly Haven Mossy Forest素材预览，展示林间道路、苔石与树冠光线"><figcaption><b>01 · 主参考：林下湿石与道路层次。</b>借鉴前景石头、中景路径、远景树冠的分层，以及自然光下的绿色变化。图为摄影HDRI素材预览，底部球体为材质测试物；场地并非烟山实景。{cite('S01','S12')}</figcaption></figure>
<figure><img src="references/bamboo_tunnel.jpg" alt="Poly Haven Bamboo Tunnel素材预览，竹竿与枝叶在道路上形成拱廊"><figcaption><b>02 · 结构参考：竹径包围感。</b>借鉴弯曲小径、遮挡与透光。此图竹叶偏干黄；本项目建议采用上图的青绿、灰绿配色，竹子疏密交替。HDRI是环境照片，不是可穿行的竹林模型。{cite('S02')}</figcaption></figure>
</div>
<h2>五种颜色，控制整张地图</h2>
<div class="palette">'''+''.join(f'<div><div class="swatch" style="background:{c}"></div><span>{n}<br>{c}</span></div>' for n,c in [('苔藓与林下','#44533D'),('泥土与旧木','#72664D'),('远山与薄雾','#D5DDCF'),('钢铁与装备','#515659'),('单词识别底色','#E4E8D4')])+f'''</div>
<p>主路比周围林地稍亮；箱子与路牌通过轮廓、位置和少量色彩吸引注意。远处山体用低细节轮廓与普通距离雾表现。首轮建议固定白天，先把一种光照调好。</p>
<div class="two rule"><figure><img src="references/rock_moss_set_01.jpg" alt="六块不同轮廓、带自然风化和苔藓的岩石模型预览"><figcaption><b>03 · 石头有主次。</b>大岩石控制视线和战斗掩体，小石子只用于路边过渡；同一块石头可旋转与适度缩放，避免整片等距摆放。{cite('S03')}</figcaption></figure><figure><img src="references/old_military_crate.jpg" alt="带旧漆与金属搭扣的军用箱模型预览"><figcaption><b>04 · 旧营地有生活痕迹。</b>破旧油漆、木料、搭扣和使用痕迹能支撑探索氛围。箱子旁只摆放与用途有关的少量物件，例如桌子、记录纸和路牌。{cite('S04')}</figcaption></figure></div>
<h2>三个值得停下来看一眼的画面</h2>
<div class="three"><section><h3>山脚看见旧营地</h3><p>入口前景压低一根树枝，土路转弯后才露出营地；远处能看见山顶观察所，给探索一个方向。</p></section><section><h3>竹林中发现岔路</h3><p>主路留出清楚的走廊，支路由一块旧路牌和一束自然光提示。敌人轮廓出现在可辨认的距离内。</p></section><section><h3>溪边抵近石桥</h3><p>先听见水声，再看见苔石和桥。桥头可观察两处掩体，过桥前有选择和准备的空间。</p></section></div>
<h2>单词标识与武器放在同一套风格里</h2>
<div class="two"><section><div class="badge-demo" role="img" aria-label="文字标识排版草图，浅色护板上印着英文take notes"><div class="wordbadge"><small>FIELD TRAINING / 排版草图</small>take notes</div></div><p class="mini">以上只示意英文标识的排版：布质胸牌或盾牌护板保留平整、浅色区域，字体深色，长词组可换行。<i>take notes</i> 已在当前词包中。</p></section><section><h3>枪支先完成一把</h3><p>建议先做紧凑型训练步枪：主体深灰、握把与护木颜色略有区别，加入少量正常磨损。重点完成持枪、射击、换弹与瞄准四类动作，再做弹匣或瞄具升级的外观变化。</p><p>新模型、贴图与动作需要一起选择。只增加金属反光，原来的简化轮廓和动作仍会很明显。</p></section></div>
<h2>画面可以提升，关键工作在素材与场景制作</h2>
<p>Godot支持通过颜色、法线、粗糙度等材质参数表现表面细节，也有较完整的官方射击演示。当前卡通观感主要来自现有模型、统一材质、摆放方式和动作完整度；这是结合当前项目与官方能力作出的判断。{cite('S07','S16')}</p>
<details><summary>展开：引擎技术参考与目标电脑取舍</summary><figure><img src="references/tps-demo.webp" alt="Godot官方第三人称射击演示截图，展示分层材质与灯光"><figcaption>Godot TPS Demo 原始截图，技术参考。© 2018 Juan Linietsky、Fernando Miguel Calabró，<a href="https://creativecommons.org/licenses/by/3.0/">CC-BY 3.0</a>；截图未修改。学习材质、轮廓和明暗关系；本项目仍采用江南山林的画面方向。{cite('S07','S08')}</figcaption></figure><p>沿用Compatibility渲染器先验证：1K/2K材质、限制植被视距、模型LOD、少量实时阴影与可行的烘焙光照。HDRI可用于色调和环境照明参考，林间近处遮挡仍由真实地形与模型组成。具体画质取舍以Vega 8实测为准。{cite('S17','S18')}</p></details>
<div class="note"><b>本稿建议先定：</b>白天雨后山林；自然青绿与土灰；旧营地有年代感；文字护板清楚可读；首轮只精修一个能完整玩过的小区域。</div>
<h2>参考来源</h2>{source_list(['S01','S02','S03','S04','S07','S08','S12','S16','S17','S18'])}
'''
document(1,'画面参考与美术方向','把“半写实的江南山林探险”落实成可比较的参考图、色彩、场景和武器要求。',art)

# Fictional coordinates in metres, +Y is north. No real survey data.
POINTS={'A':(50,35),'B':(85,115),'C':(150,160),'D':(250,190),'E':(200,260),'P':(40,135)}
MAIN=[POINTS['A'],(40,65),(58,88),POINTS['B'],(110,135),POINTS['C'],(190,155),POINTS['D'],(265,225),(235,260),POINTS['E']]
SHORT=[POINTS['B'],(60,150),(65,185),(70,215),(130,245),POINTS['E']]
POETRY=[POINTS['B'],(60,125),POINTS['P']]
STREAM=[(0,190),(50,190),(100,170),POINTS['C'],(200,115),(250,120),(300,95)]
def length(points): return sum(math.dist(a,b) for a,b in zip(points,points[1:]))
def xy(p): return (70+p[0]*2.6,70+(300-p[1])*2.6)
def poly(points): return ' '.join(f'{x:.1f},{y:.1f}' for x,y in map(xy,points))
svg=['''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1040" role="img" aria-labelledby="title desc"><title id="title">烟山基地拟议地图：山脚营地、竹林、溪桥、旧营房、山顶观察所</title><desc id="desc">300米见方的虚构关卡设计图。南部黄色轮廓是第一轮精修范围。主路经过五个地标，数学近道走西侧小桥，古诗宝箱位于西南支路。所有位置和高程为设计草案。</desc><defs><pattern id="forest" width="44" height="46" patternUnits="userSpaceOnUse"><path d="M10 16l5-9 5 9m-5-4v10M32 38l4-8 4 8m-4-4v11" fill="none" stroke="#71816a" stroke-width="1" opacity=".48"/></pattern></defs><rect x="0" y="0" width="1000" height="1040" fill="#f4f2ea"/><rect x="70" y="70" width="780" height="780" fill="#cdd6bf"/><path d="M70 245Q280 215 370 150Q560 30 850 110V70H70Z" fill="#9caa8d"/><path d="M70 390Q240 355 420 250T850 250V110Q600 30 370 150T70 245Z" fill="#b3bea3"/><rect x="70" y="70" width="780" height="780" fill="url(#forest)"/>
<g fill="none" stroke="#89977e" stroke-width="1.2" opacity=".8"><path d="M70 260Q220 240 380 170T850 130"/><path d="M70 300Q240 275 400 195T850 165"/><path d="M70 355Q250 340 420 235T850 220"/><path d="M70 425Q270 390 440 285T850 275"/><path d="M70 495Q300 455 455 345T850 330"/></g>
<g stroke="#eff0e6" stroke-width="1" opacity=".55">''']
for m in range(0,301,50):
    q=70+2.6*m
    svg.append(f'<path d="M{q} 70V850M70 {q}H850"/>')
svg.append('</g>')
svg.append(f'<polyline points="{poly(STREAM)}" fill="none" stroke="#688e91" stroke-width="21" stroke-linejoin="round" stroke-linecap="round"/><polyline points="{poly(STREAM)}" fill="none" stroke="#b1d0cc" stroke-width="11" stroke-linejoin="round"/>')
# Polished slice envelope, 115 by 145 metres.
sx,sy=xy((5,145));svg.append(f'<rect x="{sx}" y="{sy}" width="299" height="364" rx="22" fill="#e7cf83" fill-opacity=".19" stroke="#ac762b" stroke-width="3" stroke-dasharray="10 6"/>')
svg.append(f'<polyline points="{poly(MAIN)}" fill="none" stroke="#a18b66" stroke-width="15" stroke-linejoin="round" stroke-linecap="round"/><polyline points="{poly(MAIN)}" fill="none" stroke="#f4dfaf" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"/>')
svg.append(f'<polyline points="{poly(SHORT)}" fill="none" stroke="#76583b" stroke-width="5" stroke-dasharray="10 7" stroke-linejoin="round"/><polyline points="{poly(POETRY)}" fill="none" stroke="#76583b" stroke-width="4" stroke-dasharray="3 7"/>')
# Bridges at actual stream crossings.
for p in [(150,160),(65,184)]:
    x,y=xy(p);svg.append(f'<g transform="translate({x},{y}) rotate(-25)"><rect x="-24" y="-10" width="48" height="20" fill="#e4d5b5" stroke="#5e5947" stroke-width="2"/><path d="M-20 -6H20M-20 6H20" stroke="#7e735c" stroke-width="2"/></g>')
svg.append('<g font-family="Microsoft YaHei,Noto Sans SC,sans-serif" fill="#26392e" font-size="18">')
for key,(label,dx,dy) in {'A':('山脚营地',25,3),'B':('竹林补给点',28,5),'C':('溪桥',-38,-30),'D':('废弃营房',-120,-30),'E':('山顶观察所',-65,-30),'P':('古诗宝箱',-35,-30)}.items():
    x,y=xy(POINTS[key]);color='#4e6547' if key!='P' else '#8c6542'
    svg.append(f'<circle cx="{x}" cy="{y}" r="18" fill="{color}" stroke="#f4f2ea" stroke-width="3"/><text x="{x}" y="{y+6}" text-anchor="middle" fill="#fff" font-weight="bold">{key}</text><text x="{x+dx}" y="{y+dy}" font-weight="bold">{label}</text>')
for p,label in [((20,270),'设计高地 +30m'),((180,90),'溪谷 +8m'),((10,10),'低地 +0m')]:
    x,y=xy(p);svg.append(f'<text x="{x}" y="{y}" font-size="14" fill="#58664e">{label}</text>')
# Two small fight arenas, simple symbols explicitly explained below.
for p in [(80,93),(228,175)]:
    x,y=xy(p);svg.append(f'<path d="M{x-12} {y-12}l24 24m0-24l-24 24" stroke="#a15b3e" stroke-width="4"/>')
for p,label,dx,dy in [((65,184),'数学近道：旧木桥',-110,-25),((85,115),'数学锁 / 临时撤离',25,32),((200,260),'正式撤离点',25,32),((23,57),'首轮精修范围',-25,0)]:
    x,y=xy(p);svg.append(f'<text x="{x+dx}" y="{y+dy}" font-size="14" fill="#634f30">{label}</text>')
svg.append('<path d="M906 150V90l-10 15m10-15l10 15" fill="none" stroke="#26392e" stroke-width="3"/><text x="906" y="75" text-anchor="middle">北</text><text x="906" y="195" font-size="14" text-anchor="middle">山脊</text><text x="906" y="216" font-size="14" text-anchor="middle">逐渐抬升</text>')
svg.append('<path d="M70 890h130m-130-7v14m130-14v14" stroke="#26392e" stroke-width="3"/><text x="135" y="920" text-anchor="middle" font-size="15">50m</text><text x="850" y="895" text-anchor="end" font-size="14">拟议边界 300m × 300m · 虚构关卡平面图</text><text x="70" y="965" font-size="16">粗实线：主路　　长虚线：数学近道　　点线：古诗支路　　×：战斗区域</text><text x="70" y="995" font-size="15">棕黄色虚框：第一轮精修　　蓝色：溪流　　高程与植被带仅表示设计意图</text></g></svg>')
SVG=''.join(svg)
(ROOT/'map.svg').write_text(SVG,encoding='utf-8')
mapdata=dict(kind='fictional_level_design',units='metres',north='+y',bounds=[0,0,300,300],points=POINTS,main_route=MAIN,shortcut=SHORT,poetry_branch=POETRY,stream=STREAM,main_route_length_m=round(length(MAIN)),first_slice_route_length_m=round(length(MAIN[:4])),shortcut_length_m=round(length(SHORT)),standard_B_to_E_m=round(length(MAIN[3:])))
(ROOT/'map-design.json').write_text(json.dumps(mapdata,ensure_ascii=False,indent=2),encoding='utf-8')

mapbody=f'''
<p class="status">地图结构、距离、时长和敌人数量均为拟议值。烟山名称来自项目设定；本图不是现实烟山测绘图。</p>
{SVG}
<h2>一条主路，两个值得偏离主路的选择</h2>
<p>主路按 A → B → C → D → E 走完：山脚营地、竹林补给区、溪桥、废弃营房、山顶观察所。示意主路单程约 {round(length(MAIN))} 米，建议完整一局先试 12–15 分钟，再根据实际行走、学习和战斗耗时调整现有8分钟时限。</p>
<p>西侧古诗支路提供额外宝箱，沿原路返回；数学锁开启的旧木桥近道从B通往E，可绕开营房战斗区。按草图折线路径，B到E主路约 {round(length(MAIN[3:]))} 米，近道约 {round(length(SHORT))} 米，主要收益是减少战斗暴露。</p>
<div class="tablewrap"><table><thead><tr><th>位置</th><th>玩家在这里做什么</th><th>场景如何帮助理解</th></tr></thead><tbody>
<tr><td>A 山脚营地</td><td>保留限时靶场；熟悉操作、查看本局任务，沿路出发。</td><td>平地、清晰出口；能看见山顶地标。出生点与靶场射线避开摆设。</td></tr>
<tr><td>B 竹林补给点</td><td>接触第一组移动词兵；搜索物资与英文线索；可解数学锁开启西侧近道。</td><td>疏密交替的竹林、弯道和土坎形成可读掩体。数学交互放在脱战后的补给棚里。</td></tr>
<tr><td>C 溪桥</td><td>根据既有词包的方位词寻找路旁补给；观察桥对面的动静。</td><td>水声、桥头石墩和路牌提供方向。主路跨水点保持明确，不安排强制跳跃。</td></tr>
<tr><td>D 废弃营房</td><td>较强词兵战斗区；高收益箱与多入口搜索空间。</td><td>先能观察，再决定正面推进或绕行。墙面、门、箱子都有对应阻挡；文字不会藏在黑暗角落。</td></tr>
<tr><td>E 山顶观察所</td><td>达到100分后撤离；允许复用可持续出题的挑战补足分数。</td><td>沿途看得见观察所轮廓。最后一段路线可辨认，撤离圈留足空间，暂不增加登塔玩法。</td></tr>
</tbody></table></div>
<h2>把学习变成探索中的动作</h2>
<div class="three"><section><h3>英语线索：找到位置</h3><p>纸条出现“next to”，提示物资就在路牌旁边；另一处用“between”提示两块石头之间。两个词组都在现有词包里。中文提示可按键查看，寻找过程保留观察空间。</p></section><section><h3>数学锁：给近道供电</h3><p>例如“每组电池2.5格能量，3组共多少格？”用三个电池槽和数字选项表现。答错允许重试并解释；通过后打开旧木桥入口的门。该题是机制样例，正式题目需对齐小学当前数学教材。</p></section><section><h3>古诗宝箱：补全石刻</h3><p>在安全支路读出上一句，从三块石片里选出下一句，正确后获得额外物资。正式诗句从实际语文教材选取；本稿先确定玩法，不预填未经核对的课文。</p></section></div>
<div class="note">学习机关在交互期间建议暂停附近敌人的索敌与攻击，回答后给短暂离开时间。答错反馈答案和解释，不叠加战斗惩罚。物资箱、近道和错词复习可产生关联；累计100分解锁撤离的规则继续保留。</div>
<h2>第一轮只做黄色虚框内的5–8分钟精修段</h2>
<p>主路从A到B约 {round(length(MAIN[:4]))} 米，范围约115×140米：山脚营地、林间弯道、补给棚与古诗支路。完成一把带动作的枪、一种移动词兵、一个英语找物、一个数学锁、一个古诗宝箱；B处设置本轮临时撤离。能走、能打、能读、能带物资回去，再扩展溪桥与山顶。</p>
<p>首轮先采用单种词兵、最多同时2–3名的试验配置。中文提示期间，每组提供一个正确词兵和可辨认的干扰项；保留可持续出题的挑战点，确保低正确率玩家仍能积累100分。场景与读词节奏稳定后再增加人数。</p>
<h2>摆放时需要逐项检查</h2>
<ul><li>主路建议净宽3–4米；沿路掩体建议先按5–10米间隔试摆，再通过角色实测调整。</li><li>大石头和坡面打断长距离视线；溪桥两侧和营房门口不堆满物件，避免通行卡死。</li><li>文字识别优先在中近距离完成，草叶和枪口火光不要持续挡住胸牌。距离与字号须在720p下实际读词验证。</li><li>先验证撞树、绕石、坡面、射击遮挡和敌人寻路，再填充地面细节。草与小碎石只增加视觉层次。</li></ul>
<h2>当前建议的制作顺序</h2><p>确定这张草图 → 只搭可行走的灰盒验证路线 → 精修A至B并完成一局 → Vega 8验证720p/30帧目标 → 扩到溪桥和营房 → 接通山顶撤离。每轮保留独立可回退版本。</p>
'''
document(2,'烟山基地地图草图','先用一个有路线、有选择、有学习发现的小区域证明体验，再扩成约300×300米的完整山林地图。',mapbody)

assets=[
 ('环境 / 优先','林下地面','Ground 015','S05','CC0；PBR贴图；1K/2K可选','用在土路与落枝地面。与另一块泥土或草地材质混合，打散重复。','无模型、无碰撞；地形坡面、纹理比例与过渡仍需制作。'),
 ('环境 / 优先','苔石与掩体','Rock Moss Set 01','S03','CC0；六块石头的模型与材质','主路边与溪桥使用同一组石头，先试2K材质。','实际面数和LOD需读文件确认；玩家碰撞用简化形体，子弹阻挡须独立验证。'),
 ('环境 / 优先','旧营地箱子','Old Military Crate','S04','CC0；模型与PBR材质','用于高辨识度物资箱；适量做颜色变化。','页面有开/闭展示，尚未确认成品动画；需制作开箱状态、交互与拾取反馈。'),
 ('环境 / 次序2','树皮','Japanese Sycamore','S06','CC0；PBR树皮材质','供近景树干试样，先检验纹理比例与色调。','这是树皮贴图，不包含树冠、树干几何或风动。竹林与阔叶林整树模型仍需单独选型。'),
 ('环境 / 参考','林间环境光','Mossy Forest / Bamboo Tunnel','S01','CC0；HDRI；竹径另见S02','用于参考林下色彩、路径与遮阴关系；可试低分辨率环境照明。','不能替代可探索的三维场景，也不能直接把照片背景当成近处森林。'),
 ('枪械 / 优先试样','训练步枪几何','Various Small Arms','S19','作者页列CC0及历史CC-BY 3.0；Blender模型','建议先从M4/AR-15类轮廓试一把，比较近景轮廓与旧枪的差异。','无UV贴图；只有Blender材质，多数枪栓有动作。需展开UV、重做材质、配手臂和换弹。正文受robots限制，依据作者页搜索索引，下载前复核包内许可。'),
 ('枪械 / 备选','已有动作的低面数枪','Animated Guns Pack','S09','CC0；6把动画枪；FBX / OBJ / Blend','作为导入与机械运动的对照试样。','偏卡通；页面没有承诺配套手臂和完整第一人称动作。材质、持枪和换弹仍需加工。'),
 ('手臂 / 待复核','第一人称手臂','fps arms (rigged only)','S10','作者页列CC0；Blend / FBX；约8千三角面','如果枪体试样合格，再检验绑定与握持范围。','主要提供绑定，仅有粗略样例动画；需要重新匹配握持、换弹。正文受robots限制，当前依据作者页搜索索引。'),
 ('动作 / 次序2','词兵走跑与受击','Universal Animation Library','S11','页面列CC0；免费部分 / 付费Source版有区别','优先核对免费Standard下载中的走、跑、受击、倒地；用于词兵动作试样。','全库120+动作不等于免费包全部包含；选定动作后仍需匹配骨架与融合。不是第一人称枪械换弹套装。'),
 ('技术 / 参考','材质、角色与镜头','Godot TPS Demo','S07','代码MIT；美术CC-BY 3.0，见S08','参考动作组织、镜头与材质层次；可选择性借鉴。','整体是科幻风；现有游戏不宜整套替换。复用美术要署名并记录修改，性能需重新测。'),
]
rows=''.join(f'<tr><td>{a}<br><span class="status">{b}</span></td><td><b>{c}</b><br>{cite(s)}<p class="mini">{d}</p></td><td>{e}</td><td>{f}</td></tr>' for a,b,c,s,d,e,f in assets)
assetbody=f'''
<p class="status">已完成官网或作者页索引核对；本轮仅保存参考预览，没有下载整套模型、安装工具或接入游戏。</p>
<h2>推荐先试的组合</h2>
<p><b>环境：</b>Ground 015地面 + Rock Moss Set 01苔石 + Old Military Crate旧箱体，先把A至B做成统一风格。<b>枪械：</b>优先试Various Small Arms的一把步枪几何，配合独立手臂；Animated Guns Pack作动作导入备选。前者更接近所需轮廓，后者更容易建立动作流程，最终画面都需要加工。{cite('S03','S04','S05','S09','S19')}</p>
<p>目前未确认一套同时满足“免费开放许可、半写实、枪与手臂齐全、完整动作、直接适配本项目”的现成包。最大的缺口是枪械、手臂、动作和材质之间的匹配；其次是符合江南气质、适合核显的竹林和阔叶树整树模型。</p>
<h2>环境、武器与动作候选清单</h2>
<div class="tablewrap"><table><thead><tr><th style="width:14%">用途与次序</th><th style="width:26%">候选 / 来源 / 许可</th><th style="width:27%">建议用法</th><th>还需要做什么</th></tr></thead><tbody>{rows}</tbody></table></div>
<h2>两项看似合适、暂不优先采用的资源</h2>
<div class="two"><section><h3>L49 First-Person LMG</h3><p>免费，有9段枪体动画和内嵌PBR贴图，GLB与Blender源文件齐全。但没有手臂，页面列约125k三角面、298个部件，且采用限制原始文件再分发的自定义许可。作者标注AI辅助制作。对于Vega 8和可持续维护的开放资源路线，当前不优先采用。{cite('S14')}</p></section><section><h3>FPS PS1 Animated Glock</h3><p>带手臂、动画与Blender文件，页面列CC0；目前下载需至少1加元。它的PS1复古风也与此次画面目标不一致。列出它是为了说明“许可开放”与“免费取得”是两回事。{cite('S15')}</p></section></div>
<h2>开源资源省在哪里，仍要投入在哪里</h2>
<div class="three"><section><h3>可以省下</h3><p>岩石扫描、树皮与地面纹理绘制、箱子造型、人体基础动作以及枪械基础几何。</p></section><section><h3>仍需制作</h3><p>地形、道路与场景摆放；统一尺度和色调；模型碰撞；持枪与换弹匹配；英文护板；交互和反馈。</p></section><section><h3>必须实测</h3><p>720p能否读清词牌；枪是否挡字；词兵绕掩体是否卡住；植被、阴影与透明叶片对Vega 8的负担。</p></section></div>
<h2>下一轮资源试样怎么验收</h2>
<ol><li><b>环境小样：</b>一段10–20米土路、两种近景树形、两三块苔石、一个旧箱；观察地面接缝、远近比例、坡脚与碰撞。</li><li><b>枪械小样：</b>只选一把，完成可观察的持枪、射击、换弹与瞄准；先确认手指握持、弹匣位置与枪口方向。</li><li><b>词兵小样：</b>同一个角色完成走、跑、受击与倒地；护板词组完整显示。先在20米内验证读词，再决定距离。</li><li><b>目标电脑：</b>先用720p低画质验证30帧目标，记录帧时间和最低表现；不把开发机的顺畅当成Vega 8验收。</li><li><b>通过后再铺地图：</b>把合格的素材和设置用于A至B，保留来源、许可文本、原始包哈希和修改记录。</li></ol>
<p>上述距离、材质分辨率和试样规模是工作起点。尚未下载或读取模型文件，因此没有把具体帧率、显存占用、导入成功或动作兼容写成已通过。</p>
<h2>许可与下载记录</h2><p>Poly Haven和ambientCG的相关资源采用CC0；官方TPS演示代码与美术许可不同，需分别保留。Quaternius只按这里逐项核对的包页面记录，免费Standard版的内容还需在下载时确认。{cite('S08','S12','S13','S11')}</p>
<p class="mini">本目录references内保存5张Poly Haven官方预览和1张Godot官方演示截图。Poly Haven预览按CC0留存；Godot截图未修改，作者与许可见第一份讨论稿及references/TPS-LICENSE.md。OpenGameArt正文robots限制已列在相应行，未通过其他方式绕过限制。</p>
<details><summary>展开全部候选及技术来源</summary>{source_list([s['id'] for s in SOURCES])}</details>
<div class="note"><b>建议这轮讨论形成的结果：</b>认可画面基调、确认A至B的精修范围，并接受“免费枪械基础模型 + 必要加工”的路线。之后再进行小样导入，实际比较画面、动作与性能。</div>
'''
document(3,'武器与环境素材候选','优先采用来源明确、许可清楚的免费资源，列明每个候选能解决什么，以及仍需制作的部分。',assetbody)

# Map-only HTML makes a deterministic local screenshot possible, without a browser server.
(ROOT/'map-preview.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>烟山基地地图草图</title><style>body{margin:0}svg{display:block;width:1000px;height:1040px}</style>'+SVG+'</html>',encoding='utf-8')
baseline=json.loads((ROOT/'baseline-hashes.json').read_text(encoding='utf-8'))
changed=[name for name,h in baseline.items() if not (PROJECT/name).exists() or hashlib.sha256((PROJECT/name).read_bytes()).hexdigest()!=h]
qa=dict(date='2026-11-07',kind='planning_only',documents=NAMES,baseline_files=len(baseline),changed_game_files=changed,reference_images=len(list((ROOT/'references').glob('*.jpg')))+len(list((ROOT/'references').glob('*.webp'))),map_dimensions_m=[300,300],main_route_m=round(length(MAIN)),first_slice_route_m=round(length(MAIN[:4])),source_count=len(SOURCES),target_hardware_tested=False,asset_import_tested=False)
(ROOT/'verification.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(qa,ensure_ascii=False,indent=2))
assert not changed, changed
