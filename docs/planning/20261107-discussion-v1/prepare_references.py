"""Download only small, licensed reference previews; never touch game assets."""
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import urlparse
import hashlib
import json
import re
import html
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[2]
REF = ROOT / 'references'
REF.mkdir(exist_ok=True)

SOURCES = [
 ('S01','Mossy Forest','Poly Haven / Greg Zaal','HDRI','https://polyhaven.com/a/mossy_forest','林间色彩与湿石参考；CC0；HDRI不等于可探索的三维森林'),
 ('S02','Bamboo Tunnel','Poly Haven / Dimitrios Savva, Jarod Guest','HDRI','https://polyhaven.com/a/bamboo_tunnel','竹径构图参考；CC0；不可直接替代竹林模型'),
 ('S03','Rock Moss Set 01','Poly Haven / Kless, Gyzen','3D model','https://polyhaven.com/a/rock_moss_set_01','苔石模型候选；需简化网格和碰撞'),
 ('S04','Old Military Crate','Poly Haven','3D model','https://polyhaven.com/a/old_military_crate','旧营地箱体候选；开箱交互仍需制作'),
 ('S05','Ground 015','ambientCG / Lennart Demes','PBR material','https://ambientcg.com/view?id=Ground015','泥土、落枝地面材质；1K/2K版本可选'),
 ('S06','Japanese Sycamore','Poly Haven / Charlotte Baglioni','PBR material','https://polyhaven.com/a/japanese_sycamore','树皮材质候选；不是整棵树模型'),
 ('S07','Third Person Shooter Demo','Godot Engine contributors','Official repository','https://github.com/godotengine/tps-demo','模型、动作、材质和镜头技术参考；Godot 4.x'),
 ('S08','TPS Demo LICENSE','Juan Linietsky, Fernando Miguel Calabró, Godot contributors','License','https://raw.githubusercontent.com/godotengine/tps-demo/master/LICENSE.md','代码MIT；美术CC-BY 3.0；保留作者和修改记录'),
 ('S09','Animated Guns Pack','Quaternius','Asset pack','https://quaternius.com/packs/animatedguns.html','6把动画枪；FBX/OBJ/Blend；CC0；低多边形备选'),
 ('S10','fps arms (rigged only)','para / OpenGameArt','Asset page (search-index evidence)','https://opengameart.org/content/fps-arms-rigged-only','手臂CC0；主要是绑定，附粗略样例动作；不等于完整持枪动画套装'),
 ('S11','Universal Animation Library','Quaternius','Asset pack','https://quaternius.com/packs/universalanimationlibrary.html','人体动作重定向候选；免费部分与付费Source版有区别'),
 ('S12','Poly Haven License','Poly Haven','License','https://polyhaven.com/license','HDRI、材质与模型CC0'),
 ('S13','ambientCG License','ambientCG','License','https://docs.ambientcg.com/license/','素材与预览CC0'),
 ('S14','L49 First-Person LMG','CuiGames','Asset page','https://cuigames.itch.io/l49-first-person-lmg','免费自定义许可；无手臂，约125k三角面、298部件；限制原始文件再分发；不优先采用'),
 ('S15','FPS PS1 Animated Glock','loxyrak','Asset page','https://loxyrak.itch.io/fps-ps1-animated-glock','带手臂和动画；CC0但当前下载门槛1加元；复古风不匹配'),
 ('S16','Standard Material 3D','Godot documentation','Official documentation','https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html','材质通过颜色、法线、粗糙度和金属度等控制外观'),
 ('S17','Renderers','Godot documentation','Official documentation','https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html','Compatibility功能边界与烘焙光照可行性'),
 ('S18','Mesh LOD','Godot documentation','Official documentation','https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html','导入模型LOD与远景优化'),
]
sources = [dict(id=i,title=t,publisher=p,source_type=k,date='n.d.',accessed='2026-11-07',url_or_path=u,claims_supported=c,reliability_notes=('A - primary; 页面正文受robots限制，仅取得搜索索引，需下载前复核' if i=='S10' else 'A - primary; 已核对官方页面；模型文件未导入测试'),use_in_report=('01 / 03' if i not in ('S16','S17','S18') else '01 / 03 技术方案')) for i,t,p,k,u,c in SOURCES]
(ROOT/'source-index.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2),encoding='utf-8')
if not (ROOT/'baseline-hashes.json').exists():
    tracked = [p for p in (PROJECT/'game').rglob('*') if p.is_file() and '.godot' not in p.parts and p.suffix in ('.gd','.tscn','.godot','.json')]
    tracked += list(PROJECT.glob('*.cmd')) + [PROJECT/'docs'/'project-scope.json']
    baseline = {str(p.relative_to(PROJECT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}
    (ROOT/'baseline-hashes.json').write_text(json.dumps(baseline,ensure_ascii=False,indent=2),encoding='utf-8')

ALLOWED = {'polyhaven.com','cdn.polyhaven.com','ambientcg.com','docs.ambientcg.com','raw.githubusercontent.com','quaternius.com'}
def get(url):
    if urlparse(url).hostname not in ALLOWED:
        raise ValueError('Unexpected reference host')
    with urlopen(Request(url,headers={'User-Agent':'Yanshan-planning-reference/1.0'}),timeout=25) as r:
        data=r.read(3_000_001)
        if len(data)>3_000_000: raise ValueError('Reference exceeds 3 MB cap')
        return data

def preview(asset):
    path=REF/(asset+'.jpg')
    if path.exists(): return {'asset':asset,'status':'exists'}
    page=get('https://polyhaven.com/a/'+asset).decode('utf-8')
    match=re.search(r'<meta[^>]*property="og:image"[^>]*content="([^"]+)"',page)
    if not match: match=re.search(r'<meta[^>]*content="([^"]+)"[^>]*property="og:image"',page)
    if not match: raise ValueError('No OG preview: '+asset)
    url=html.unescape(match.group(1))
    data=get(url)
    path.write_bytes(data)
    return {'asset':asset,'url':url,'path':str(path.relative_to(ROOT)),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}

if __name__=='__main__':
    entries=[]
    with ThreadPoolExecutor(max_workers=3) as pool:
        tasks={name:pool.submit(preview,name) for name in ['mossy_forest','bamboo_tunnel','rock_moss_set_01','old_military_crate','japanese_sycamore']}
        for name,task in tasks.items():
            try: entries.append(task.result())
            except Exception as e: entries.append({'asset':name,'error':str(e)})
    try:
        license_data=get('https://raw.githubusercontent.com/godotengine/tps-demo/master/LICENSE.md')
        (REF/'TPS-LICENSE.md').write_bytes(license_data)
        screenshot=get('https://raw.githubusercontent.com/godotengine/tps-demo/master/screenshots/screenshot.webp')
        (REF/'tps-demo.webp').write_bytes(screenshot)
        entries.append({'asset':'tps-demo','url':'https://raw.githubusercontent.com/godotengine/tps-demo/master/screenshots/screenshot.webp','bytes':len(screenshot),'credit':'2018 Juan Linietsky, Fernando Miguel Calabró; CC-BY 3.0; unchanged screenshot'})
    except Exception as e: entries.append({'asset':'tps-demo','error':str(e)})
    (REF/'download-record.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(entries,ensure_ascii=False,indent=2))
