"""Fetch only Windows x64 entries from the official multi-platform template ZIP.

HTTP byte ranges avoid downloading 1.28 GB of unrelated platform templates.
Each extracted entry is verified against its ZIP CRC and recorded with SHA-256.
"""
from pathlib import Path
import hashlib
import json
import os
import struct
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parents[1]
_LOCAL_ROOT = Path(os.environ.get("DRZ_RUNTIME") or (Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData/Local")) / "Temp/drz-english-shooter-20261103"))
ENGINE = _LOCAL_ROOT / "godot-4.7.2"
URL = "https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
TOTAL = 1281349702


def get_range(start, end):
    request = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(request,timeout=90) as response:
        if response.status != 206 or not response.headers.get('Content-Range','').startswith(f'bytes {start}-{end}/'):
            raise RuntimeError("Official server did not honor requested byte range.")
        data = response.read(end-start+2)
    if len(data) != end-start+1:
        raise RuntimeError("Incomplete HTTP range.")
    return data


def main():
    tail = get_range(TOTAL-65536,TOTAL-1)
    offset = tail.rfind(b'PK\x05\x06')
    if offset < 0:
        raise RuntimeError('ZIP end record not found')
    eocd = struct.unpack_from('<4s4H2LH',tail,offset)
    cd_size, cd_offset = eocd[5],eocd[6]
    central = get_range(cd_offset,cd_offset+cd_size-1)
    selected = []
    pos = 0
    while pos < len(central):
        fields = struct.unpack_from('<4s6H3L5H2L',central,pos)
        if fields[0] != b'PK\x01\x02':
            raise RuntimeError('Bad ZIP directory record')
        name_len,extra_len,comment_len = fields[10:13]
        name = central[pos+46:pos+46+name_len].decode('utf-8')
        if name in ('templates/windows_release_x86_64.exe','templates/windows_debug_x86_64.exe','templates/version.txt'):
            selected.append((name,fields))
        pos += 46+name_len+extra_len+comment_len
    assert len(selected)==3, [row[0] for row in selected]
    destination = ENGINE/'editor_data/export_templates/4.7.2.stable'
    destination.mkdir(parents=True,exist_ok=True)
    report = []
    for name,fields in selected:
        target = destination/Path(name).name
        method,crc,compressed,uncompressed,local_offset = fields[4],fields[7],fields[8],fields[9],fields[16]
        if target.exists():
            content = target.read_bytes()
        else:
            header = get_range(local_offset,local_offset+29)
            local = struct.unpack('<4s5H3L2H',header)
            assert local[0] == b'PK\x03\x04'
            start = local_offset+30+local[9]+local[10]
            encoded = get_range(start,start+compressed-1)
            content = zlib.decompress(encoded,-15) if method==8 else encoded
            assert len(content)==uncompressed and zlib.crc32(content)&0xffffffff==crc
            target.write_bytes(content)
        assert len(content)==uncompressed and zlib.crc32(content)&0xffffffff==crc
        report.append({'entry':name,'compressed_bytes':compressed,'bytes':len(content),'crc32':f'{crc:08x}','sha256':hashlib.sha256(content).hexdigest(),'destination':str(target)})
        print('VERIFIED',name,len(content),flush=True)
    result = {'source':URL,'method':'HTTP range extraction of official ZIP entries','full_archive_downloaded':False,'full_archive_sha256_verified':False,'entry_crc_verified':True,'entries':report}
    output = ROOT/'docs/windows-export-templates.json'
    if output.exists():
        previous=json.loads(output.read_text(encoding='utf-8'))
        assert previous==result
    else:
        output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
