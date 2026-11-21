"""Slice approved commissioned sheets; never synthesize replacement artwork.
The original atlas pages and metadata regions are preserved byte-for-byte.
Source alpha is thresholded using the existing authoring pipeline's rule.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/pixel'
SHEETS={
 'stone':['branch_shelter','knapping_canopy','logging_canopy','quarry_shade','basket_store','meeting_canopy','charcoal_clamp','earth_shelter'],
 'agricultural':['wattle_house','longhouse','raised_granary','pottery_kiln','weaving_house','timber_yard_review','adobe_house','stilt_house']}
meta=json.loads((OUT/'atlas.json').read_text())
meta={k:v for k,v in meta.items() if v.get('category')!='architecture'}
# Idempotent: replace only this tool's own page and owned keys.
pages=json.loads((OUT/'pages.json').read_text())
page_name='architecture_early.png'
if page_name not in pages: pages.append(page_name)
page_index=pages.index(page_name)
atlas=Image.new('RGBA',(1024,512))
manifest={'version':1,'source_mode':'image_gen reference-guided commissioned sheets','quality_status':'reviewed at logical size; owner/device approval pending','assets':{}}
for era,(sheet,names) in enumerate(SHEETS.items(),1):
 source=ROOT/'tools/source'/('architecture_'+sheet+'.png')
 im=Image.open(source).convert('RGBA')
 for slot,name in enumerate(names):
  if name=='timber_yard_review': continue
  x=slot%4;y=slot//4
  cell=im.crop((x*im.width//4,y*im.height//2,(x+1)*im.width//4,(y+1)*im.height//2))
  # The granary cell's far-right gutter includes 3 isolated pixels from the
  # adjacent kiln; crop only that gutter, beyond the granary's x=355 boundary.
  if name=='raised_granary': cell=cell.crop((0,0,cell.width-18,cell.height))
  cell.putalpha(cell.getchannel('A').point(lambda a:255 if a>=160 else 0))
  bounds=cell.getchannel('A').getbbox()
  assert bounds, name
  cell=cell.crop(bounds)
  # 64 logical pixels = two terrain cells; retain fine single-pixel texture.
  factor=min(64/cell.width,64/cell.height)
  cell=cell.resize((max(1,round(cell.width*factor)),max(1,round(cell.height*factor))),Image.Resampling.NEAREST)
  n=(era-1)*8+slot;pos=(n%8*128,n//8*128)
  atlas.paste(cell,pos)
  key='arch_'+name
  entry={'atlas':'architecture','page':page_index,'packed_rect':[*pos,*cell.size],'rect':[*pos,*cell.size],
   'category':'architecture','source':str(source.relative_to(ROOT)),
   'source_cell':[x,y,4,2],'sha256':hashlib.sha256(cell.tobytes()).hexdigest(),'ground_anchor':[cell.width//2,cell.height],
   'primary_age':era,'quality_approved':name!='timber_yard_review'}
  meta[key]=entry;manifest['assets'][key]=entry
atlas.save(OUT/page_name,optimize=True)
(OUT/'atlas.json').write_text(json.dumps(meta,indent=2)+'\n')
(OUT/'pages.json').write_text(json.dumps(pages,indent=2)+'\n')
(ROOT/'data/architecture/asset_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Contact sheets are exact runtime pixels, displayed at 3x nearest-neighbour.
for era,(sheet,names) in enumerate(SHEETS.items(),1):
 contact=Image.new('RGB',(960,640),'#23302a');d=ImageDraw.Draw(contact)
 d.text((20,12),f'GOD SANDBOX / AGE {era} / RUNTIME SPRITES AT 3X',fill='#e9dfc2')
 for slot,name in enumerate(names):
  if 'arch_'+name not in meta:
   d.text((slot%4*240+12,slot//4*295+258),'WITHHELD: saw/tool review',fill='#e9a885')
   continue
  e=meta['arch_'+name];x,y,w,h=e['packed_rect'];crop=atlas.crop((x,y,x+w,y+h)).resize((w*3,h*3),Image.Resampling.NEAREST)
  cx=slot%4*240;cy=slot//4*295+38
  contact.paste(crop,(cx+(240-crop.width)//2,cy+205-crop.height),crop)
  d.text((cx+12,cy+220),name.replace('_',' '),fill='#e9dfc2')
 contact.save(ROOT/f'docs/architecture/age-{era}-contact.png')
# Original and new sprites shown without any upscaling trickery.
orig=Image.open(OUT/'sprite_atlas.png').convert('RGBA');compare=Image.new('RGB',(960,350),'#23302a');d=ImageDraw.Draw(compare)
for n,(key,label) in enumerate([('hut_a','Original premium reference'),('cottage_a','Original premium reference'),('arch_branch_shelter','New Stone Age'),('arch_wattle_house','New Agricultural Age')]):
 e=meta[key];x,y,w,h=e['packed_rect'];src=atlas if key.startswith('arch_') else orig
 crop=src.crop((x,y,x+w,y+h)).resize((w*3,h*3),Image.Resampling.NEAREST)
 compare.paste(crop,(n*240+(240-crop.width)//2,230-crop.height),crop);d.text((n*240+10,255),label,fill='#e9dfc2');d.text((n*240+10,278),f'{w} x {h} logical pixels',fill='#b9c3b4')
compare.save(ROOT/'docs/architecture/reference-comparison.png')
readme=OUT/'README.md'
s=readme.read_text().split('\n\n## Architecture extension')[0]
readme.write_text(s+'\n\n## Architecture extension\n\n15 new cutouts on a separate 1024x512 page; 345 total regions across two pages. Source sheets, reproducible packer and exact metadata: `tools/pack_architecture.py`, `data/architecture/asset_manifest.json`. One source cell is withheld for tool-design review and is absent from the runtime atlas. Original 330 regions remain unchanged.\n')
print('PACKED 15 distinct runtime sprites; 1 source cell withheld for saw/tool review; original 330 untouched')
