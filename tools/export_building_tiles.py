"""Publish contact sheets using actual God Sandbox atlas regions."""
import json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
out=root/"docs"/"media"
out.mkdir(parents=True,exist_ok=True)
atlas=json.loads((root/"assets/pixel/atlas.json").read_text())
pages=json.loads((root/"assets/pixel/pages.json").read_text())
tex=[Image.open(root/"assets/pixel"/p).convert("RGBA") for p in pages]
kinds=["hut","cottage","stone_house","workshop","storage","farmhouse","barn","market","watchtower","town_hall"]
original={"hut","cottage","workshop","town_hall"}
buildings=[]
for kind in kinds:
    for key in ([kind] if kind in original else [])+[kind+"_a",kind+"_b"]:
        r=atlas[key]
        buildings.append((key,r["packed_rect"],tex[r.get("page",0)]))
assert len(buildings)==23
m=json.loads((root/"data/visuals/physical_sprite_manifest.json").read_text())
physical=Image.open(root/"assets/pixel/physical_atlas.png").convert("RGBA")
stages=[(k,v["rect"],physical) for k,v in m["sprites"].items() if v["category"]=="construction"]
assert len(stages)==60
def font(n):
    try:return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",n)
    except OSError:return ImageFont.load_default()
def sheet(entries,name,title,columns,cellwidth,cellheight):
    gap=12
    header=96
    rows=math.ceil(len(entries)/columns)
    W=(cellwidth+gap)*columns+gap
    H=header+(cellheight+gap)*rows+gap+36
    im=Image.new("RGB",(W,H),(24,38,35))
    d=ImageDraw.Draw(im)
    d.text((20,16),title,font=font(26),fill=(240,230,210))
    d.text((20,55),f"{len(entries)} ORIGINAL ATLAS REGIONS | EXACT CROPS | NEAREST-NEIGHBOUR UPSCALE",font=font(12),fill=(175,190,171))
    for i,(key,rect,source) in enumerate(entries):
        col=i%columns;row=i//columns
        x=gap+(cellwidth+gap)*col;y=header+gap+(cellheight+gap)*row
        d.rounded_rectangle((x,y,x+cellwidth,y+cellheight),radius=8,fill=(47,65,60),outline=(103,129,107),width=2)
        rx,ry,rw,rh=map(int,rect)
        part=source.crop((rx,ry,rx+rw,ry+rh))
        available=cellheight-49
        scale=max(1,min(6,int(min((cellwidth-18)/rw,(available-12)/rh))))
        part=part.resize((rw*scale,rh*scale),Image.Resampling.NEAREST)
        cx=x+(cellwidth-part.width)//2;cy=y+(available-part.height)//2+8
        im.paste(part,(cx,cy),part)
        label=key.replace("_"," ").title()
        d.text((x+11,y+cellheight-38),label,font=font(15 if columns==4 else 12),fill=(237,223,198))
        d.text((x+11,y+cellheight-19),key,font=font(10),fill=(165,191,172))
    d.text((20,H-28),"Actual assets, not concept art. Some designs are decorative until built by simulation.",font=font(12),fill=(173,191,170))
    path=out/name
    im.save(path,optimize=True)
    print(f"CREATED {path} {W}x{H}")
sheet(buildings,"god_sandbox_buildings_23.png","GOD SANDBOX | FINISHED BUILDINGS",4,244,216)
sheet(stages,"god_sandbox_construction_tiles_60.png","GOD SANDBOX | CONSTRUCTION TILES",6,180,164)
