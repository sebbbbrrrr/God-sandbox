#!/usr/bin/env python3
"""Render a labelled contact sheet of the exact packed God Sandbox era sprites."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
root=Path(__file__).resolve().parents[1]
atlas=Image.open(root/"assets/pixel/sprite_atlas_1.png").convert("RGBA")
index=json.loads((root/"assets/pixel/atlas.json").read_text())
roles=[
["lean_to","hide_tent","branch_hut","stone_shelter","hearth_circle","tool_area","drying_rack","communal_canopy"],
["wattle_house","longhouse","granary","mud_store","farmstead","tool_area","pottery_kiln","meeting_lodge"],
["mudbrick_house","courtyard_house","granary","bronze_foundry","market_court","temple_shrine","tool_area","civic_hall"],
["stone_villa","courtyard_house","tiled_workshop","colonnade","market_forum","barracks","tool_area","bathhouse"],
["half_timber_house","stone_cottage","guildhall","watermill","market_square","fortified_tower","tool_area","granary"]]
names=["I - EARLY STONE AGE","II - AGRICULTURAL","III - BRONZE AGE","IV - IRON / CLASSICAL","V - MEDIEVAL"]
def font(size):
    try:return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",size)
    except OSError:return ImageFont.load_default()
cell_w,cell_h,gap=286,168,12
W=5*(cell_w+gap)+gap
H=124+8*(cell_h+gap)+45
sheet=Image.new("RGB",(W,H),(27,39,37))
draw=ImageDraw.Draw(sheet)
draw.text((20,17),"GOD SANDBOX | CIVILISATION ARCHITECTURE",font=font(28),fill=(239,230,207))
draw.text((20,59),"80 actual 64x64 game regions | 5 ages | 8 archetypes per age | 2 variants per type",font=font(15),fill=(175,194,173))
for age in range(1,6):
    x=gap+(age-1)*(cell_w+gap)
    draw.rounded_rectangle((x,94,x+cell_w,124),radius=5,fill=(61,87,69))
    draw.text((x+9,100),names[age-1],font=font(14),fill=(242,234,212))
    for row,kind in enumerate(roles[age-1]):
        y=132+row*(cell_h+gap)
        draw.rounded_rectangle((x,y,x+cell_w,y+cell_h),radius=8,
                               fill=(48,64,59),outline=(92,119,96),width=2)
        for j,var in enumerate(["a","b"]):
            key=f"era{age}_{kind}_{var}"
            sx,sy,sw,sh=index[key]["packed_rect"]
            img=atlas.crop((sx,sy,sx+sw,sy+sh)).resize((128,128),Image.Resampling.NEAREST)
            sheet.paste(img,(x+13+j*141,y+5),img)
        label=kind.replace("_"," ").title()
        draw.text((x+12,y+139),label,font=font(14),fill=(241,224,195))
out=root/"docs"/"media"
out.mkdir(parents=True,exist_ok=True)
path=out/"god_sandbox_architecture_ages_i_v.png"
sheet.save(path,optimize=True)
print(f"PREVIEW {path} {W}x{H}")
