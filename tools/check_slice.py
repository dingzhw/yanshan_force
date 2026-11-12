"""Run Godot integration checks with QA profiles; retain explicit failures/logs."""
from pathlib import Path
import subprocess,json,argparse,re,sys,os
ROOT=Path(__file__).resolve().parents[1]
runtime=json.loads((ROOT/'docs/runtime-local.json').read_text(encoding='utf-8'))
p=argparse.ArgumentParser();p.add_argument('tests',nargs='+');p.add_argument('--stage',action='store_true');args=p.parse_args()
if args.stage:
    subprocess.run([runtime['python_used'],str(ROOT/'tools/build_playtest.py')],check=True)
    imported=subprocess.run([runtime['console_executable'],'--headless','--path',runtime['game_working_copy'],'--editor','--import','--quit'],capture_output=True,encoding='utf-8',errors='replace',timeout=120)
    (ROOT/'docs/v040-import.log').write_text(imported.stdout+'\n'+imported.stderr,encoding='utf-8')
    print('IMPORT_EXIT',imported.returncode,flush=True)
    if imported.returncode or 'SCRIPT ERROR:' in imported.stderr:raise RuntimeError('Godot import failed; inspect v040-import.log')
out=ROOT/'docs'/'v040-checks';out.mkdir(exist_ok=True)
results=[]
for name in args.tests:
    command=[runtime['console_executable']]+([] if name in ['slice_visual','terrain_render'] else ['--headless'])+['--path',runtime['game_working_copy'],'--script',f'res://tests/{name}.gd','--','--qa']
    if name=='hardware-tour':command=[runtime['console_executable'],'--path',runtime['game_working_copy'],'--','--qa','--hardware-check','--auto-quit','--low-quality']
    if name=='packaged-tour':command=[str(ROOT/'playtest/windows-v0.4.0/YanshanBase.exe'),'--log-file',str(out/'packaged-engine.log'),'--','--qa','--hardware-check','--auto-quit','--low-quality']
    env=os.environ.copy()
    screenshots=ROOT/'docs'/'screenshots'/'v040';screenshots.mkdir(exist_ok=True)
    env['DRZ_SCREENSHOT_DIR']=str(screenshots)
    diagnostics=ROOT/'docs/diagnostics/v040';diagnostics.mkdir(exist_ok=True)
    env['DRZ_DIAGNOSTICS_DIR']=str(diagnostics)
    try:
        r=subprocess.run(command,capture_output=True,encoding='utf-8',errors='replace',timeout=150,env=env,creationflags=subprocess.CREATE_NO_WINDOW)
        text=r.stdout+'\n'+r.stderr
        if name=='packaged-tour' and 'PERFORMANCE_REPORT ' not in text and (out/'packaged-engine.log').exists():text+='\n'+(out/'packaged-engine.log').read_text(encoding='utf-8',errors='replace')
        (out/(name+'.log')).write_text(text,encoding='utf-8')
        failures=[line for line in text.splitlines() if re.search(r'^FAIL |SCRIPT ERROR:|Parse Error:|^ERROR:|Assertion failed',line)]
        entry={'test':name,'exit_code':r.returncode,'passes':len(re.findall(r'^PASS ',text,re.M)),'failures':failures,'summary':[line for line in text.splitlines() if 'CHECKS' in line or 'LIVE_ROUND' in line]}
        if name in ['hardware-tour','packaged-tour']:
            report=re.search(r'^PERFORMANCE_REPORT (\{.*\})$',text,re.M)
            entry['report']=json.loads(report.group(1)) if report else None
            if not entry['report'] or not entry['report'].get('route_and_extraction_passed'):
                entry['failures'].append('Complete performance-tour result missing or not passed')
    except subprocess.TimeoutExpired as e:
        text=(e.stdout or b'').decode('utf-8',errors='replace') if isinstance(e.stdout,bytes) else str(e.stdout)
        (out/(name+'.log')).write_text(text,encoding='utf-8');entry={'test':name,'error':'timeout','tail':text[-2400:]}
    print(json.dumps(entry,ensure_ascii=False),flush=True);results.append(entry)
    if entry.get('exit_code',1)!=0 or entry.get('failures'):break
(out/('run-'+args.tests[0]+'.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(0 if all(r.get('exit_code',1)==0 and not r.get('failures') for r in results) else 1)
