"""Pack the commissioned source sheet into exact, nearest-sampled game assets.
Usage: python tools/build_pixel_assets.py SOURCE_SHEET.png
The source is image-generated; masks/transitions are deterministic pixel geometry.
Pillow is an authoring dependency only. Runtime needs only the PNG atlases/JSON.
"""
from pathlib import Path
import json, sys, random
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/pixel'
OUT.mkdir(parents=True,exist_ok=True)
src=Image.open(sys.argv[1]).convert('RGBA')
terrain=Image.new('RGBA',(512,512)); objects=Image.new('RGBA',(512,512)); masks=Image.new('RGBA',(512,512))
manifest={}; counters={'terrain':0,'objects':0,'transitions':0}
def pack(name,im,kind):
    size=64 if kind=='objects' else 32
    slot=counters[kind]; counters[kind]+=1
    x=(slot%(512//size))*size; y=(slot//(512//size))*size
    target={'terrain':terrain,'objects':objects,'transitions':masks}[kind]
    target.paste(im,(x,y))
    manifest[name]={'atlas':kind,'rect':[x,y,im.width,im.height]}
def cell(col,row):
    return src.crop((round(col*src.width/8),round(row*src.height/8),round((col+1)*src.width/8),round((row+1)*src.height/8)))
def tile(col,row):
    im=cell(col,row).resize((32,32),Image.Resampling.NEAREST)
    im.putalpha(255)
    return im
terrain_sources={'meadow':[(i,4) for i in range(4)],'forest':[(4,4),(5,4),(6,5),(7,5)],
'dirt':[(6,4)]*4,'ash':[(2,5)]*4,'earth':[(7,4)],'water':[(0,5)]*4,'shallow':[(1,5)]*4,
'rock':[(3,5)]*4,'mountain':[(4,5)]*4,'sand':[(5,5)]*4}
# Tile edge colour variation is bounded; texture pattern still contains fine detail.
for family,coords in terrain_sources.items():
    for i,(col,row) in enumerate(coords):
        im=tile(col,row)
        if len(set(coords))==1 and i:
            from PIL import ImageChops
            im=ImageChops.offset(im,i*7,i*11)
        if family in ('meadow','forest'):
            tint=Image.new('RGBA',(32,32),'#70954d' if family=='meadow' else '#4e7045')
            im=Image.blend(im,tint,0.50)
        if family in ('water','shallow','sand'):
            tint=Image.new('RGBA',(32,32),{'water':'#287f97','shallow':'#57aaad','sand':'#c6b57d'}[family])
            im=Image.blend(im,tint,0.78 if family!='sand' else 0.42)
        pack(f'{family}_{i}',im,'terrain')
object_names=[
['pine_0','pine_1','pine_2','pine_3','pine_4','bush','flower_bush','stump'],
['rock_small','rock_medium','rock_tall','log','grass','flowers_white','flowers_gold','moss_rock'],
['hut','cottage','workshop','town_hall','bridge_wood_h','bridge_wood_v','bridge_stone_h','bridge_stone_v'],
['fence_h','fence_v','well','barrels','woodpile','sign','citizen_gold','citizen_rose'],
['cliff_0','cliff_1','cliff_2','cliff_3','cliff_4','cliff_5','cliff_6','cliff_7'],
['fire','blessing','ripple','reeds','grass_2','fern','ledge','cliff_corner']]
for names,row in zip(object_names,[0,1,2,3,6,7]):
    for col,name in enumerate(names):
        im=cell(col,row)
        # Binary pixel alpha prevents coloured near-transparent generation fringes.
        alpha=im.getchannel('A').point(lambda a:255 if a>=160 else 0)
        im.putalpha(alpha)
        box=alpha.getbbox()
        if box: im=im.crop(box)
        if name.startswith('pine'): limit=(36,58)
        elif name.startswith('citizen'): limit=(10,17)
        elif name in ('hut','cottage','workshop','town_hall'): limit=(50,49) if name!='town_hall' else (60,60)
        elif name.startswith('cliff'): limit=(32,24)
        elif name.startswith('bridge'): limit=(32,32)
        else: limit=(25,23)
        factor=min(limit[0]/im.width,limit[1]/im.height)
        im=im.resize((max(1,round(im.width*factor)),max(1,round(im.height*factor))),Image.Resampling.NEAREST)
        pack(name,im,'objects')
# 4-bit N,E,S,W overlays. Their jitter is invariant along opposite tile borders.
# Graded opaque pixel coverage, not texture filtering, creates soft natural edges.
for family,source in [('meadow','meadow_0'),('forest','forest_0'),('dirt','dirt_0'),('ash','ash_0'),('earth','earth_0'),('rock','rock_0'),('shore','sand_0'),('shallow','shallow_0')]:
    entry=manifest[source]; x,y,w,h=entry['rect']; base=terrain.crop((x,y,x+w,y+h))
    for mask in range(1,16):
        im=Image.new('RGBA',(32,32))
        for py in range(32):
            for px in range(32):
                distances=[py,31-px,31-py,px]
                strength=max([11-distances[d]+((px*17+py*11)%5)-2 for d in range(4) if mask&(1<<d)])
                if strength>0 and ((px*31+py*19)%8)<strength:
                    im.putpixel((px,py),base.getpixel((px,py)))
        if family=='shore':
            d=ImageDraw.Draw(im)
            for axis,bit in [('n',1),('e',2),('s',4),('w',8)]:
                if not mask&bit: continue
                for p in range(32):
                    offset=2+((p//4)%2)
                    q={'n':(p,offset),'s':(p,31-offset),'e':(31-offset,p),'w':(offset,p)}[axis]
                    im.putpixel(q,(207,231,199,255))
        pack(f'{family}_edge_{mask}',im,'transitions')
# Concave shore corner sprites cover diagonally adjoining land.
for corner,(cx,cy) in enumerate([(0,0),(31,0),(31,31),(0,31)]):
    im=Image.new('RGBA',(32,32)); d=ImageDraw.Draw(im)
    for y in range(32):
        for x in range(32):
            dist=(x-cx)**2+(y-cy)**2
            if dist<42: im.putpixel((x,y),(181,190,118,255))
            elif dist<58: im.putpixel((x,y),(173,219,199,255))
    pack(f'shore_corner_{corner}',im,'transitions')
# Rounded land corners cut back the square silhouette against water.
base_entry=manifest['water_0'];x,y,w,h=base_entry['rect'];ocean=terrain.crop((x,y,x+w,y+h))
for mask in range(1,16):
    im=Image.new('RGBA',(32,32))
    for corner,(cx,cy,bits) in enumerate([(0,0,9),(31,0,3),(31,31,6),(0,31,12)]):
        if mask&bits!=bits: continue
        for yy in range(12):
            for xx in range(12):
                # Outside a quarter-circle centred towards the tile interior.
                dist=(11-xx)**2+(11-yy)**2
                px=xx if cx==0 else 31-xx; py=yy if cy==0 else 31-yy
                if dist>125: im.putpixel((px,py),ocean.getpixel((px,py)))
                elif dist>105: im.putpixel((px,py),(188,216,176,255))
    pack(f'coast_cut_{mask}',im,'transitions')
for name in ['path_h','path_v','path_cross']:
    entry=manifest['dirt_0'];x,y,w,h=entry['rect'];earth=terrain.crop((x,y,x+w,y+h))
    im=Image.new('RGBA',(32,32))
    for y in range(32):
        for x in range(32):
            jitter=(x*11+y*19)%3
            if (name!='path_v' and abs(y-16)<4+jitter) or (name!='path_h' and abs(x-16)<4+jitter):
                im.putpixel((x,y),earth.getpixel((x,y)))
    pack(name,im,'transitions')
# Inner/outer rock joins share the face material and use exact pixel silhouettes.
entry=manifest['cliff_0'];x,y,w,h=entry['rect'];face=objects.crop((x,y,x+w,y+h)).resize((32,24),Image.Resampling.NEAREST)
for name in ['cliff_inner','cliff_outer']:
    im=face.copy()
    for y in range(24):
        for x in range(32):
            if (name=='cliff_inner' and x<20 and y>7) or (name=='cliff_outer' and x>25-y//4):
                im.putpixel((x,y),(0,0,0,0))
    pack(name,im,'objects')
# Tight pixel contact shadows and directional face strips are reusable overlays.
for name,colour in [('contact_shadow',(26,47,43,125)),('cliff_east',(34,48,48,100))]:
    im=Image.new('RGBA',(32,32)); d=ImageDraw.Draw(im)
    if name=='contact_shadow': d.rectangle((0,0,31,3),fill=colour)
    else: d.rectangle((27,0,31,31),fill=colour)
    pack(name,im,'transitions')
for name,im in [('terrain',terrain),('objects',objects),('transitions',masks)]: im.save(OUT/f'{name}.png',optimize=True)
combined=Image.new('RGBA',(1024,1024))
for kind,im,offset in [('terrain',terrain,(0,0)),('objects',objects,(512,0)),('transitions',masks,(0,512))]:
    combined.paste(im,offset)
    for entry in manifest.values():
        if entry['atlas']==kind:
            x,y,w,h=entry['rect'];entry['packed_rect']=[x+offset[0],y+offset[1],w,h]
combined.save(OUT/'sprite_atlas.png',optimize=True)
(OUT/'atlas.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Packed {len(manifest)} named assets into one runtime atlas plus three authoring atlases')
