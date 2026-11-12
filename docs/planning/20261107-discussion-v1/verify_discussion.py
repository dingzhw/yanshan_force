"""Check local document links, sources, JSON and preserved game files."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote, urlparse
import json
import hashlib
import re

ROOT=Path(__file__).resolve().parent
class Checker(HTMLParser):
    def __init__(self):
        super().__init__(); self.urls=[]; self.images=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='a' and 'href' in a: self.urls.append(a['href'])
        if tag=='img':
            assert a.get('alt'), 'Image missing alt'
            self.images.append(a['src'])

errors=[]
for path in sorted(ROOT.glob('0*.html')):
    c=Checker(); text=path.read_text(encoding='utf-8'); c.feed(text)
    for u in c.urls+c.images:
        if not urlparse(u).scheme and not u.startswith('#'):
            if not (ROOT/unquote(u.split('#')[0])).is_file(): errors.append(f'{path.name}: missing {u}')
    if re.search(r'TODO|TBD|lorem|待补|占位',text,re.I): errors.append(f'{path.name}: placeholder')
    print(path.name, 'images=',len(c.images),'links=',len(c.urls))
for p in ROOT.glob('*.json'): json.loads(p.read_text(encoding='utf-8'))
project=ROOT.parents[2]
base=json.loads((ROOT/'baseline-hashes.json').read_text(encoding='utf-8'))
for name,sha in base.items():
    p=project/name
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha: errors.append('Game changed: '+name)
from PIL import Image
for p in (ROOT/'references').iterdir():
    if p.suffix in ('.jpg','.webp'):
        with Image.open(p) as image: image.verify()
design=json.loads((ROOT/'map-design.json').read_text(encoding='utf-8'))
for p in design['points'].values(): assert all(0<=v<=300 for v in p)
qa=json.loads((ROOT/'verification.json').read_text(encoding='utf-8'))
qa.update(local_links_checked=True,images_decoded=True,json_parsed=True,game_hashes_unchanged=not any('Game changed:' in e for e in errors),errors=errors)
(ROOT/'verification.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2),encoding='utf-8')
print('Errors:',errors)
assert not errors
