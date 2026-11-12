"""Render local discussion artifacts with installed Chrome; no dependencies added."""
from pathlib import Path
import subprocess
import tempfile
import json
import sys

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'qa'
OUT.mkdir(exist_ok=True)
CHROME=Path(r'C:\Program Files\Google\Chrome\Application\chrome.exe')
profile=Path(tempfile.mkdtemp(prefix='yanshan-planning-chrome-'))
cases=[('map-preview.html','map.png',1000,1040),('01-画面参考与美术方向.html','art-preview.png',1400,1900),('02-烟山基地地图草图.html','map-document.png',1400,2400),('03-武器与环境素材候选.html','assets-preview.png',1500,5300)]
if '--map-only' in sys.argv:
    cases=[c for c in cases if c[0] in ('map-preview.html','02-烟山基地地图草图.html')]
results=[]
for source,target,w,h in cases:
    out=ROOT/target if target=='map.png' else OUT/target
    args=[str(CHROME),'--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--hide-scrollbars',f'--user-data-dir={profile}',f'--screenshot={out}',f'--window-size={w},{h}','--virtual-time-budget=1500',(ROOT/source).as_uri()]
    try:
        r=subprocess.run(args,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=35,creationflags=subprocess.CREATE_NO_WINDOW)
        (OUT/(target+'.log')).write_text(r.stderr,encoding='utf-8')
        results.append(dict(document=source,exit_code=r.returncode,screenshot_exists=out.is_file(),bytes=out.stat().st_size if out.is_file() else 0))
    except subprocess.TimeoutExpired:
        results.append(dict(document=source,error='Chrome timeout',screenshot_exists=out.is_file()))
    print(json.dumps(results[-1],ensure_ascii=False),flush=True)
    if results[-1].get('exit_code') != 0:
        break
(OUT/('render-map-update.json' if '--map-only' in sys.argv else 'render-record.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
assert all(r.get('exit_code')==0 and r['screenshot_exists'] for r in results), results
