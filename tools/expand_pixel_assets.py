"""Rebuild Phase 1A, then pack original Phase 1B source sheets and pixel-geometry overlays.
Python/Pillow are authoring-only. Extra 64px slots spill into new 1024px pages deterministically.
"""
from pathlib import Path
import subprocess,sys,json,hashlib
from PIL import Image,ImageDraw,ImageStat
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/pixel';SRC=ROOT/'tools/source'
subprocess.run([sys.executable,str(ROOT/'tools/build_pixel_assets.py'),str(SRC/'source_sheet.png')],check=True)
meta=json.loads((OUT/'atlas.json').read_text());pages=[Image.open(OUT/'sprite_atlas.png').convert('RGBA')]
expansion=Image.new('RGBA',(512,512));extra=0
nature=['oak','birch','willow','beech','maple','spruce','cedar','juniper','sapling_leaf','sapling_pine','dead_tree','fallen_tree','berry_shrub','fern_cluster','wildflowers','tall_grass','moss_log','wet_reeds','cattails','leaf_litter','mushrooms','exposed_roots','branches','pebbles','granite_boulder','sandstone_boulder','moss_boulder','mountain_spire','cliff_debris','driftwood','coastal_stones','shells']
buildings=[f'{kind}_{v}' for kind in ['hut','cottage','stone_house','workshop','storage','farmhouse','barn','market','watchtower','town_hall'] for v in ['a','b']]
props=['fence_gate','fence_vertical','garden','crops','well_roof','well_open','handcart','crates','hay','chopping_block','stone_wall_h','stone_wall_v']

def runtime_slot(index):
 # First fill the fourth quadrant; later pages use the entire 16x16 slot grid.
 page=0 if index<64 else 1+(index-64)//256
 slot=index if page==0 else (index-64)%256
 return page,(512 if page==0 else 0)+(slot%8 if page==0 else slot%16)*64,(512 if page==0 else 0)+(slot//8 if page==0 else slot//16)*64

def pack_object(name,im,category,source,cell):
 global extra
 # The unused fourth quadrant of page zero gets the first 64 objects.
 page,x,y=runtime_slot(extra)
 while len(pages)<=page:pages.append(Image.new('RGBA',(1024,1024)))
 pages[page].paste(im,(x,y))
 if extra<64:expansion.paste(im,((extra%8)*64,(extra//8)*64))
 meta[name]={'atlas':'expansion' if page==0 else f'sprite_atlas_{page}','rect':[(extra%8)*64,(extra//8)*64,im.width,im.height] if page==0 else [x,y,im.width,im.height], 'packed_rect':[x,y,im.width,im.height], 'page':page,'category':category,'source':source,'source_cell':cell,'sha256':hashlib.sha256(im.tobytes()).hexdigest()}
 extra+=1

def extract(sheet,index,limit):
 col=index%8;row=index//8
 im=sheet.crop((round(col*sheet.width/8),round(row*sheet.height/4),round((col+1)*sheet.width/8),round((row+1)*sheet.height/4)))
 alpha=im.getchannel('A').point(lambda v:255 if v>=176 else 0);im.putalpha(alpha)
 box=alpha.getbbox()
 if not box:raise ValueError('Empty source cell')
 im=im.crop(box);factor=min(limit[0]/im.width,limit[1]/im.height)
 return im.resize((max(1,round(im.width*factor)),max(1,round(im.height*factor))),Image.Resampling.NEAREST)

sheet=Image.open(SRC/'nature_phase1b.png').convert('RGBA')
for i,name in enumerate(nature):
 limit=(43,58) if i<8 else ((34,47) if i in [8,9,10] else ((42,28) if i==11 else (28,25)))
 if name=='mountain_spire':limit=(34,48)
 pack_object(name,extract(sheet,i,limit),'vegetation' if i<23 else 'landscape','tools/source/nature_phase1b.png',[i%8,i//8])
sheet=Image.open(SRC/'settlement_phase1b.png').convert('RGBA')
for i,name in enumerate(buildings+props):
 limit=(50,49) if i<20 else (28,23)
 if name.startswith('town_hall'):limit=(60,60)
 if name.startswith('watchtower'):limit=(32,62)
 if name.startswith(('farmhouse','barn')):limit=(56,50)
 pack_object(name,extract(sheet,i,limit),'building' if i<20 else 'settlement_prop','tools/source/settlement_phase1b.png',[i%8,i//8])
expansion.save(OUT/'expansion.png',optimize=True)
# Sixteen independently drawn ground materials, no colour-swap variants.
terrain=Image.open(OUT/'terrain.png').convert('RGBA');sheet=Image.open(SRC/'terrain_phase1b.png').convert('RGBA')
names=[f'{f}_{i}' for f in ['meadow','forest','sand'] for i in range(4,8)]+['rock_4','rock_5','ash_4','earth_1']
count=sum(1 for r in meta.values() if r['atlas']=='terrain')
for n,name in enumerate(names):
 c=n%4;r=n//4;im=sheet.crop((round(c*sheet.width/4),round(r*sheet.height/4),round((c+1)*sheet.width/4),round((r+1)*sheet.height/4))).resize((32,32),Image.Resampling.NEAREST);im.putalpha(255)
 # Condition independently drawn materials against the existing ground palette.
 # Bake an irregular material boundary into each tile: no runtime extra draw and
 # no square dark-green/rocky checkerboard between old and new source materials.
 family=name.rsplit('_',1)[0];base_rect=meta[family+'_0']['rect'];base=terrain.crop((base_rect[0],base_rect[1],base_rect[0]+32,base_rect[1]+32))
 means=ImageStat.Stat(im).mean;target=ImageStat.Stat(base).mean
 for py in range(32):
  for px in range(32):
   sample=im.getpixel((px,py));under=base.getpixel((px,py))
   edge=min(px,py,31-px,31-py)
   blend=min(1.0,max(0.0,(edge-1+((px*13+py*7)%5)/3)/7))
   if family in ['meadow','forest']:
    sample=tuple(max(0,min(255,round(sample[k]*target[k]/max(1,means[k])))) for k in range(3))
   im.putpixel((px,py),tuple(round(under[k]*(1-blend)+sample[k]*blend) for k in range(3))+(255,))
 x=(count%16)*32;y=(count//16)*32;count+=1;terrain.paste(im,(x,y));pages[0].paste(im,(x,y))
 meta[name]={'atlas':'terrain','rect':[x,y,32,32],'packed_rect':[x,y,32,32],'page':0,'category':'terrain','source':'tools/source/terrain_phase1b.png','source_cell':[c,r]}
terrain.save(OUT/'terrain.png',optimize=True)
# Authored pixel geometry uses existing materials, preserving the original mask vocabulary.
trans=Image.open(OUT/'transitions.png').convert('RGBA');count=sum(1 for r in meta.values() if r['atlas']=='transitions')
def overlay(name,im):
 global count
 x=(count%16)*32;y=(count//16)*32;count+=1
 if y+32>512:raise ValueError('Transition authoring page exhausted')
 trans.paste(im,(x,y));pages[0].paste(im,(x,y+512));meta[name]={'atlas':'transitions','rect':[x,y,im.width,im.height],'packed_rect':[x,y+512,im.width,im.height],'page':0,'category':'overlay','source':'tools/expand_pixel_assets.py'}
for mask in range(1,16):
 im=Image.new('RGBA',(32,32));d=ImageDraw.Draw(im);d.ellipse((11,11,21,21),fill='#a99564')
 for bit,box in [(1,(11,0,21,17)),(2,(16,11,31,21)),(4,(11,16,21,31)),(8,(0,11,17,21))]:
  if mask&bit:d.rectangle(box,fill='#a99564')
 for y in range(32):
  for x in range(32):
   if im.getpixel((x,y))[3] and (x*13+y*7)%17==0:im.putpixel((x,y),(129,116,83,255))
 overlay(f'path_join_{mask}',im)
for name in ['ground_shadow','cliff_strata','cliff_rim','shore_scatter']:
 im=Image.new('RGBA',(32,32));d=ImageDraw.Draw(im)
 if name=='ground_shadow':d.ellipse((5,20,30,30),fill=(22,37,31,65));d.ellipse((10,23,27,28),fill=(18,32,26,42))
 elif name=='cliff_strata':
  for y in [8,17,26]:d.line([(0,y),(9,y+2),(20,y-1),(31,y+1)],fill=(41,48,46,110),width=1)
 elif name=='cliff_rim':d.line([(0,3),(8,2),(16,4),(23,1),(31,3)],fill=(194,191,139,190),width=1)
 else:
  for x,y in [(3,6),(12,12),(25,4),(5,27),(24,22)]:d.ellipse((x,y,x+2,y+1),fill=(133,142,125,210))
 overlay(name,im)
trans.save(OUT/'transitions.png',optimize=True)
for i,page in enumerate(pages):page.save(OUT/('sprite_atlas.png' if i==0 else f'sprite_atlas_{i}.png'),optimize=True)
for name,entry in meta.items():
 entry.setdefault('page',0)
 entry.setdefault('source','tools/build_pixel_assets.py' if entry['atlas']=='transitions' or name in ['cliff_inner','cliff_outer'] else 'tools/source/source_sheet.png')
(OUT/'atlas.json').write_text(json.dumps(meta,indent=2)+'\n')
(OUT/'pages.json').write_text(json.dumps(['sprite_atlas.png']+[f'sprite_atlas_{i}.png' for i in range(1,len(pages))],indent=2)+'\n')
lines=['# Pixel asset inventory','',f'{len(meta)} regions; {len(pages)} runtime atlas page(s), 1024×1024 RGBA each. All rects are x,y,width,height.','', '| Region | Category | Page | Packed rectangle | Source |','| --- | --- | --- | --- | --- |']
for name,r in meta.items():lines.append(f"| `{name}` | {r.get('category',r['atlas'])} | {r['page']} | {r['packed_rect']} | `{r.get('source','tools/source/source_sheet.png')}` |")
(OUT/'README.md').write_text('\n'.join(lines)+'\n')
print(f'Phase 1B: {len(meta)} distinct named regions on {len(pages)} runtime page(s)')
