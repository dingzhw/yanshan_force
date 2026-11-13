"""Publish local entry points only after release, CRC and packaged-tour checks."""
from pathlib import Path
import hashlib,json,zipfile,re,math
ROOT=Path(__file__).resolve().parents[1]
BASE=json.loads((ROOT/'docs/backups/20261107-pre-v040/baseline.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def guard(rel):
    p=ROOT/rel
    if sha(p)!=BASE[str(Path(rel))]:raise RuntimeError('Concurrent change; preserving '+rel)
def text_preserving(rel,text):
    p=ROOT/rel;raw=p.read_bytes();style='\r\n' if b'\r\n' in raw else '\n'
    data=text.replace('\r\n','\n').replace('\n',style).encode('utf-8')
    if raw.startswith(b'\xef\xbb\xbf'):data=b'\xef\xbb\xbf'+data
    p.write_bytes(data)

def main():
    tests=json.loads((ROOT/'docs/v040-checks/run-smoke.json').read_text(encoding='utf-8'))
    assert all(t.get('exit_code')==0 and not t['failures'] for t in tests)
    check_count=sum(t['passes'] for t in tests);assert check_count==182
    packaged=json.loads((ROOT/'docs/v040-checks/run-packaged-tour.json').read_text(encoding='utf-8'))[0]
    assert packaged['exit_code']==0 and not packaged['failures'] and packaged['report']['route_and_extraction_passed']
    report=packaged['report'];assert report['optional_discoveries']==3 and report['score']==100 and report['opened_crates']>=1 and report['profile_saved'] is False
    release_path=ROOT/'docs/release-0.4.0.json';release=json.loads(release_path.read_text(encoding='utf-8'))
    for file in release['files']:assert sha(ROOT/file['path'])==file['sha256']
    old=json.loads((ROOT/'docs/release-0.3.1.json').read_text(encoding='utf-8'))
    for file in old['files']:assert sha(ROOT/file['path'])==file['sha256']
    archive=ROOT/'playtest/烟山基地试玩_v0.4.0_Windows.zip'
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        required=['YanshanBase.exe','YanshanBase.pck','开始试玩.cmd','低负载启动.cmd','性能巡检.cmd','试玩说明.txt','licenses/Slice-CC0-sources.txt']
        assert all(name in z.namelist() for name in required)
        for name in z.namelist():assert z.read(name)==(ROOT/'playtest/windows-v0.4.0'/name).read_bytes()
    with zipfile.ZipFile(ROOT/release['source_checkpoint']) as z:
        assert z.testzip() is None
        for name in z.namelist():assert z.read(name)==(ROOT/name).read_bytes()
    pck=(ROOT/'playtest/windows-v0.4.0/YanshanBase.pck').read_bytes()
    payloads={}
    for name in ['data/wordpacks/jiangsu-5a-2026.json','data/exploration/grade5a.json']:
        source=ROOT/'game'/name;offset=pck.find(source.read_bytes());assert offset>=0
        payloads[name]={'sha256':sha(source),'exact_payload_offset':offset}
    assert payloads['data/wordpacks/jiangsu-5a-2026.json']['sha256']==BASE[str(Path('game/data/wordpacks/jiangsu-5a-2026.json'))]
    for rel in ['开始烟山试玩.cmd','性能巡检.cmd','README.txt','docs/runtime-local.json','docs/project-scope.json']:guard(rel)
    for rel in ['开始烟山试玩.cmd','性能巡检.cmd']:
        p=ROOT/rel;data=p.read_bytes().replace(b'windows-v0.3.1',b'windows-v0.4.0')
        if rel=='性能巡检.cmd':data=data.replace(b'--qa --hardware-check',b'--qa --hardware-check --low-quality')
        p.write_bytes(data)
    low=ROOT/'低负载启动.cmd'
    with low.open('xb') as f:f.write(b'@echo off\r\nstart "" "%~dp0playtest\\windows-v0.4.0\\YanshanBase.exe" -- --low-quality\r\n')
    runtime=json.loads((ROOT/'docs/runtime-local.json').read_text(encoding='utf-8'))
    runtime['playtest_executable']=str(ROOT/'playtest/windows-v0.4.0/YanshanBase.exe')
    text_preserving('docs/runtime-local.json',json.dumps(runtime,ensure_ascii=False,indent=2)+'\n')
    scope=json.loads((ROOT/'docs/project-scope.json').read_text(encoding='utf-8'))
    scope['recorded_date']='2026-11-07';scope['stage']='v0.4.0 A到B山林探索精修试玩；Vega 8待实测'
    scope['playtest']='playtest/windows-v0.4.0/YanshanBase.exe'
    scope['challenge_points']=['A · 山脚营地','林间前哨','B · 竹林补给点']
    scope['gameplay']['exploration']={'english':'next to 寻找路牌旁补给','math':'五上图形平移；打开近道木门','poem':'五上山居秋暝石刻','optional':True,'reading_pauses_run':True,'full_bag_reward_swap':True}
    scope['gameplay']['word_combat']['zones']=['林间前哨','B · 竹林补给点']
    scope['gameplay']['word_combat']['active_shooters_per_group']=2
    scope['slice']={'target_minutes':[5,8],'human_duration_validated':False,'route':'A山脚营地—林间前哨—B竹林补给点','art':'半写实江南山林方向；免费开放许可素材优先','quality_toggle':'F6 / --low-quality'}
    text_preserving('docs/project-scope.json',json.dumps(scope,ensure_ascii=False,indent=2)+'\n')
    readme=(ROOT/'docs/v0.4.0-试玩说明.txt').read_text(encoding='utf-8-sig')
    readme+='\n本机项目入口\n双击本目录“开始烟山试玩.cmd”启动新版；Vega 8优先用“低负载启动.cmd”。\n发给孩子电脑：只需复制playtest/烟山基地试玩_v0.4.0_Windows.zip并完整解压。\n旧版：playtest/windows-v0.3.1；原ZIP保留。\n\n开发与恢复\n源码与素材：game；原始素材与许可：third_party、downloads、game/licenses。\nGodot 4.7.2 Compatibility；沿用现有运行时与Blender，没有新增全局依赖。\n构建缓存位于本机Temp，路径见docs/runtime-local.json；game目录没有.godot缓存。\n本轮开始前完整备份：docs/backups/20261107-pre-v040。\n新版代码检查点：docs/checkpoints/source-0.4.0.zip。\n新版完整game目录快照：docs/checkpoints/source-0.4.0-full.zip。\n验收详情：docs/final-verification-v0.4.0.json、docs/v0.4.0-交付与验收.txt。\n'
    text_preserving('README.txt',readme)
    snapshot=ROOT/'docs/checkpoints/source-0.4.0-full.zip'
    game_files=[p for p in sorted((ROOT/'game').rglob('*')) if p.is_file() and '.godot' not in p.parts]
    with zipfile.ZipFile(snapshot,'x',zipfile.ZIP_DEFLATED) as z:
        for p in game_files:z.write(p,p.relative_to(ROOT))
    with zipfile.ZipFile(snapshot) as z:
        assert z.testzip() is None
        for p in game_files:assert z.read(str(p.relative_to(ROOT)).replace('\\','/'))==p.read_bytes()
    assert not (ROOT/'game/.godot').exists()
    for file in old['files']:assert sha(ROOT/file['path'])==file['sha256']
    verification={'version':'0.4.0','date':'2026-11-07','checks_passed':check_count,'checks':tests,'windows_package_crc':'passed','package_matches_release_directory':True,'source_checkpoint_matches':True,'full_game_snapshot':{'path':str(snapshot.relative_to(ROOT)),'files':len(game_files),'sha256':sha(snapshot)},'exact_pck_json_payloads':payloads,'old_v031_release_hashes_unchanged':True,'launchers_updated':True,'normal_save_path_unchanged':True,'automated_runs_used_qa_mode':True,'packaged_complete_tour':report,'native_window_observed':True,'sky_keyboard_injection_counted':False,'sky_note':'Input protection reported concurrent user input twice; attempts stopped. Actual movement input-event and capsule tests passed.','target_vega8_tested':False,'human_5_to_8_minute_pacing_tested':False,'unconfirmed_extra_probe':'External --script resource probe emitted no observable result and was not counted; exact PCK JSON payload matching and complete packaged tour passed.'}
    output=ROOT/'docs/final-verification-v0.4.0.json';output.write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')
    release.update(verification=str(output.relative_to(ROOT)),full_source_snapshot=str(snapshot.relative_to(ROOT)),old_v031_preserved=True)
    release_path.write_text(json.dumps(release,ensure_ascii=False,indent=2),encoding='utf-8')
    text=f'''烟山基地v0.4.0交付与验收\n\n已交付Windows独立运行目录及ZIP；无需安装开发工具。\n入口：开始烟山试玩.cmd；Vega 8建议低负载启动.cmd。\n\n已实现：约100米A到B山路、PBR地面与扫描苔石/箱体、轻量植被、实体碰撞、步枪与弹匣动作、三个可选学习探索、开箱/搜撤/出售/升级与旧存档沿用。\n\n验证：{check_count}项玩法、输入、移动、物理、战斗、经济、学习及GPU地面检查通过。\n独立EXE自动完成识词100分、探索3/3、开箱和3秒撤离；不保存QA进度。\n成品1280×720低负载巡检开发机：{report['gpu']}。\n平均{report['average_fps']:.1f} FPS；P95 {report['p95_frame_ms']:.1f} ms；最大单帧{report['max_frame_ms']:.1f} ms。\n这是自由练习路线的可复现自动巡检；词兵实战另通过34项检查。\n自动巡检用时{report['duration_seconds']:.1f}秒，快速输入答案，不作为孩子游玩时长。\n\n尚待实测：目标 Vega 8 核显电脑的实际帧率、键鼠手感，以及孩子是否适合5–8分钟节奏。\nWindows窗口实际渲染已观察；Sky两次按键注入被输入保护拒绝，已停止，未计为键盘验收。\n182项中的移动与按键检查使用Godot真实输入事件和角色物理运动；完整巡检实际走过主路和学习支路。\n\n原v0.3.1 EXE/PCK/ZIP哈希均未变化。\n修改前完整备份：docs/backups/20261107-pre-v040。\n新版本代码与完整game目录快照：docs/checkpoints/source-0.4.0.zip、source-0.4.0-full.zip。\nZIP CRC、源码一致性、独立包与目录内容一致性均通过。\n新PCK已找到与源文件完全一致的175条词包和探索题库字节内容。\n完整记录：docs/final-verification-v0.4.0.json。\n'''
    (ROOT/'docs/v0.4.0-交付与验收.txt').write_text(text,encoding='utf-8-sig')
    with (ROOT/'docs/slice-v040-work-log.txt').open('a',encoding='utf-8') as f:f.write('Delivered v0.4.0. Final 182 regression checks passed; independent Windows EXE completed 100-point/3-discovery/crate/extraction tour. ZIP CRC, exact PCK JSON payloads, all release-file hashes, old v0.3.1 hashes and full game snapshot checked. Launchers and scope updated. Vega8 and human pacing remain pending. Native Sky keyboard attempts were blocked by input protection and not counted.\n')
    print(json.dumps({'version':'0.4.0','checks':check_count,'packaged_full_tour':True,'zip_crc':'passed','old_release_preserved':True,'full_snapshot_files':len(game_files),'target_vega8_tested':False},ensure_ascii=False))

if __name__=='__main__':main()
