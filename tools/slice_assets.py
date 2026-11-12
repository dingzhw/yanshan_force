"""Fetch approved public CC0 assets and record originals; never execute downloads."""
from pathlib import Path
from urllib.request import urlopen, Request
from concurrent.futures import ThreadPoolExecutor
import argparse,json,hashlib,zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'downloads'/'slice-v040'
OUT.mkdir(exist_ok=True)
def fetch(url,path,limit=120_000_000):
    if path.exists(): return path
    with urlopen(Request(url,headers={'User-Agent':'YanshanAssetPreparation/0.4'}),timeout=50) as response:
        data=response.read(limit+1)
    if len(data)>limit: raise RuntimeError('Size cap exceeded: '+url)
    path.write_bytes(data)
    return path

def catalog():
    urls={
      'rock-files':'https://api.polyhaven.com/files/rock_moss_set_01',
      'crate-files':'https://api.polyhaven.com/files/old_military_crate',
      'rock-info':'https://api.polyhaven.com/info/rock_moss_set_01',
      'crate-info':'https://api.polyhaven.com/info/old_military_crate',
      'ground-info':'https://ambientcg.com/api/v2/full_json?id=Ground015',
    }
    with ThreadPoolExecutor(max_workers=3) as pool:
        tasks={name:pool.submit(fetch,url,OUT/(name+'.json'),8_000_000) for name,url in urls.items()}
        for name,task in tasks.items():
            try:
                data=json.loads(task.result().read_text(encoding='utf-8'))
                print(name, json.dumps(data,ensure_ascii=False)[:2600],flush=True)
            except Exception as e: print(name,'ERROR',str(e),flush=True)

def download():
    downloads={
      'smallarms.zip':'https://opengameart.org/sites/default/files/smallarms.zip',
      'Ground015_1K-JPG.zip':'https://ambientcg.com/get?file=Ground015_1K-JPG.zip',
    }
    # Blender source for scanned props plus the low-resolution PBR channels.
    for name in ('rock','crate'):
        meta=json.loads((OUT/(name+'-files.json')).read_text(encoding='utf-8'))
        for typ in ('blend','Diffuse','nor_gl','Rough'):
            if typ not in meta: continue
            resolutions=meta[typ]
            res='1k' if '1k' in resolutions else next(iter(resolutions))
            formats=resolutions[res]
            fmt='blend' if typ=='blend' else ('jpg' if 'jpg' in formats else 'png')
            item=formats[fmt]
            downloads[item['url'].split('/')[-1]]=item['url']
    records=[]
    with ThreadPoolExecutor(max_workers=3) as pool:
        tasks={name:pool.submit(fetch,url,OUT/name) for name,url in downloads.items()}
        for name,task in tasks.items():
            try:
                path=task.result()
                records.append(dict(file=name,url=downloads[name],bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
                print('OK',name,path.stat().st_size,flush=True)
            except Exception as e:
                records.append(dict(file=name,url=downloads[name],error=str(e)))
                print('ERROR',name,str(e),flush=True)
    (OUT/'download-record.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')

def tree():
    for kind in ['info','files']:
        fetch('https://api.polyhaven.com/'+kind+'/pine_tree_01',OUT/('pine-'+kind+'.json'),8_000_000)
    meta=json.loads((OUT/'pine-files.json').read_text(encoding='utf-8'))
    item=meta['blend']['1k']['blend']
    print('PINE_BLEND',item['size'],flush=True)
    if item['size']>100_000_000:
        print('SKIP: source geometry exceeds the 100 MB preparation budget',flush=True)
        return
    urls={item['url'].split('/')[-1]:item['url']}
    for kind in ['Diffuse','nor_gl','Rough','Alpha']:
        if kind in meta:
            fmts=meta[kind]['1k']; f='jpg' if 'jpg' in fmts else ('png' if 'png' in fmts else next(iter(fmts)))
            it=fmts[f];urls[it['url'].split('/')[-1]]=it['url']
    # Keep leaf alpha and other referenced channels, if present, at 1K only.
    for rel,info in item.get('include',{}).items():
        urls.setdefault(info['url'].split('/')[-1],info['url'])
    records=[]
    with ThreadPoolExecutor(max_workers=3) as pool:
        tasks={name:pool.submit(fetch,url,OUT/name,100_000_000) for name,url in urls.items()}
        for name,f in tasks.items():
            try:
                path=f.result();records.append({'file':name,'url':urls[name],'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()});print('PINE_OK',name,path.stat().st_size,flush=True)
            except Exception as e:records.append({'file':name,'error':str(e)});print('PINE_ERROR',name,str(e),flush=True)
    (OUT/'pine-download-record.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')

def foliage():
    meta=json.loads((OUT/'pine-files.json').read_text(encoding='utf-8'))
    records=[]
    for key in ['bark_diff','twig_diff','twig_alpha']:
        formats=meta[key]['1k'];fmt='jpg' if 'jpg' in formats else 'png';item=formats[fmt]
        if item['size']>3_000_000:raise RuntimeError('Foliage texture exceeds size budget')
        path=fetch(item['url'],OUT/item['url'].split('/')[-1],3_000_000)
        records.append(dict(file=path.name,url=item['url'],bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        print('FOLIAGE_OK',path.name,path.stat().st_size,flush=True)
    (OUT/'foliage-download-record.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--download',action='store_true');p.add_argument('--tree',action='store_true');p.add_argument('--foliage',action='store_true');a=p.parse_args()
    foliage() if a.foliage else (tree() if a.tree else (download() if a.download else catalog()))
