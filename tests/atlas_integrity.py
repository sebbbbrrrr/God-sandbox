"""Authoring checks; no engine or renderer substitutes. Run after the packer."""
from pathlib import Path
import ast,hashlib,json,subprocess,sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'assets/pixel'
meta=json.loads((folder/'atlas.json').read_text())
pages=[Image.open(folder/name).convert('RGBA') for name in json.loads((folder/'pages.json').read_text())]
assert len(meta)==358
assert len(pages)==2, 'Architecture occupies its own bounded atlas page'
rects=[];fingerprints=set()
for name,entry in meta.items():
    page=entry['page'];x,y,w,h=entry['packed_rect']
    assert 0<=page<len(pages) and w>0 and h>0
    assert x>=0 and y>=0 and x+w<=pages[page].width and y+h<=pages[page].height,name
    for other_page,a,b,c,d,other in rects:
        assert page!=other_page or x+w<=a or a+c<=x or y+h<=b or b+d<=y,(name,other)
    rects.append((page,x,y,w,h,name))
    im=pages[page].crop((x,y,x+w,y+h))
    # Single-sided coast cuts intentionally contain no pixels: only corners
    # with both adjacent ocean bits need to cut back the land silhouette.
    empty_cut=name.startswith('coast_cut_') and int(name.rsplit('_',1)[1]) in [1,2,4,5,8,10]
    assert im.getchannel('A').getbbox() or empty_cut,name
    if entry.get('category') in ['vegetation','landscape','building','settlement_prop']:
        digest=hashlib.sha256(im.tobytes()).hexdigest()
        assert digest==entry['sha256'] and digest not in fingerprints,name
        fingerprints.add(digest)
        assert set(im.getchannel('A').tobytes())<={0,255},name
        assert (ROOT/entry['source']).is_file(),name
assert len(fingerprints)==64
architecture_hashes=set()
for name,e in meta.items():
    if e.get('category')!='architecture': continue
    assert e['sha256'] not in architecture_hashes,name
    architecture_hashes.add(e['sha256'])
    x,y,w,h=e['packed_rect']; im=pages[e['page']].crop((x,y,x+w,y+h))
    assert set(im.getchannel('A').tobytes())<={0,255}
    assert hashlib.sha256(im.tobytes()).hexdigest()==e['sha256']
    assert (ROOT/e['source']).is_file()
    assert w<=64 and h<=64

assert len(architecture_hashes)==28
# Exercise overflow page boundaries without manufacturing duplicate artwork.
tree=ast.parse((ROOT/'tools/expand_pixel_assets.py').read_text())
function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='runtime_slot')
scope={};exec(compile(ast.Module(body=[function],type_ignores=[]),'<atlas slot>','exec'),scope)
slots=[scope['runtime_slot'](i) for i in range(1024)]
assert len(set(slots))==1024
assert slots[63]==(0,960,960) and slots[64]==(1,0,0) and slots[320]==(2,0,0)
assert all(0<=x<=960 and 0<=y<=960 for page,x,y in slots)
# A second full build must produce byte-identical atlases and metadata.
paths=[folder/name for name in ['sprite_atlas.png','terrain.png','objects.png','transitions.png','expansion.png','atlas.json','pages.json','README.md','architecture_early.png']]
before=[hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
subprocess.run([sys.executable,str(ROOT/'tools/expand_pixel_assets.py')],check=True)
subprocess.run([sys.executable,str(ROOT/'tools/pack_architecture.py')],check=True)
assert before==[hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
print('ATLAS_INTEGRITY_PASSED: 358 nonoverlapping regions; 64 original cutouts + 28 architectural sprites; deterministic rebuild')
