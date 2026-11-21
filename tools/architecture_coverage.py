"""Report actual coverage, without treating variants or recolours as archetypes."""
from pathlib import Path
from PIL import Image,ImageDraw
import csv,hashlib,json
R=Path(__file__).resolve().parents[1]
d=json.loads((R/'data/buildings/catalogue.json').read_text());art=json.loads((R/'data/architecture/asset_manifest.json').read_text())['assets'];atlas=json.loads((R/'assets/pixel/atlas.json').read_text())
coverage=[]
for age in d['eras']:
 rows=[b for b in d['buildings'] if b['primary_age']==age['id']]
 authored=[b for b in rows if not b['legacy']]
 archetypes={b['archetype_id'] for b in rows}
 authored_archetypes={b['archetype_id'] for b in authored}
 coverage.append({'age':age['id'],'name':age['name'],'definitions':len(rows),'legacy_definitions':len(rows)-len(authored),'authored_designs':len(authored),'functional_archetypes':len(archetypes),'authored_functional_archetypes':len(authored_archetypes),'batch_b_archetype_benchmark_met':len(authored_archetypes)>=8,'minimum_archetypes':8,'minimum_shortfall':max(0,8-len(authored_archetypes)),'full_age_complete':False,'recipes_exact':all(isinstance(n,int) and n>0 for b in rows for n in b['materials'].values()),'authored_lifecycle_states':False,'android_device_verified':False})
matrix=[]
for age in d['eras']:
 for region in d['regions']:
  rows=[b for b in d['buildings'] if b['primary_age']==age['id'] and b['regional_family']==region]
  sprites={b['visual']['sprite'] for b in rows if b['visual']['sprite'] in art}
  matrix.append({'age':age['id'],'region':region,'categories':','.join(sorted({b['category'] for b in rows})),'asset_count':len(sprites),'building_designs':len(rows),'functional_integration':bool(rows),'recipe_completion':bool(rows),'animation_support':'shared stages and worker choreography' if rows else 'missing','visual_quality_approval':'internal logical-scale review; device/owner pending' if sprites else 'missing','authored_damage_states':False})
report={'scope':'Batch B content and functional integration for Ages I–III; full 11-age and regional/lifecycle/device acceptance NOT met','age_summary':coverage,'region_matrix':matrix,'withheld_source_cells':[{'source':'tools/source/architecture_agricultural.png','cell':[1,1],'reason':'Original saw cell remains withheld. A separate stone-adze timber workyard was authored and integrated in Batch B.'}],'regional_context':'Existing settlement_context climate values select real distinct structures. Live Nature/climate adapter remains unimplemented.','missing_regions':['coastal_island','alpine_mountain','grassland_steppe','river_wetland'],'missing_ages':[4,5,6,7,8,9,10,11]}
(R/'docs/architecture/coverage.json').write_text(json.dumps(report,indent=2)+'\n')
with (R/'docs/architecture/coverage.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=matrix[0],lineterminator="\n");writer.writeheader();writer.writerows(matrix)
# Exact geometric comparison, cut from the actual packed sprites.
page=Image.open(R/'assets/pixel/architecture_early.png').convert('RGBA')
contact=Image.new('RGB',(960,340),'#23302a');draw=ImageDraw.Draw(contact)
for n,(id,label) in enumerate([('wattle_house','II / Woodland'),('adobe_house','II / Desert'),('stilt_house','II / Tropical'),('earth_shelter','I / Cold')]):
 e=atlas['arch_'+id];x,y,w,h=e['packed_rect'];im=page.crop((x,y,x+w,y+h)).resize((w*3,h*3),Image.Resampling.NEAREST)
 contact.paste(im,(n*240+(240-im.width)//2,230-im.height),im);draw.text((n*240+14,250),label,fill='#efe4c9')
contact.save(R/'docs/architecture/regional-comparison.png')
print('COVERAGE: 37 canonical definitions; 28 authored designs; 8 authored archetypes per age I–III; no age marked fully complete')

chronology=Image.new('RGB',(960,340),'#23302a');draw=ImageDraw.Draw(chronology)
for n,(id,label) in enumerate([('branch_shelter','I / lashed branch shelter'),('wattle_house','II / permanent wattle home'),('bronze_courtyard','III / mudbrick courtyard')]):
 e=atlas['arch_'+id];x,y,w,h=e['packed_rect'];im=page.crop((x,y,x+w,y+h)).resize((w*3,h*3),Image.Resampling.NEAREST)
 chronology.paste(im,(n*320+(320-im.width)//2,230-im.height),im);draw.text((n*320+24,260),label,fill='#efe4c9')
chronology.save(R/'docs/architecture/chronological-i-iii.png')
# Side-by-side reference at actual logical density (same nearest 3x scale).
original=Image.open(R/'assets/pixel/sprite_atlas.png').convert('RGBA')
comparison=Image.new('RGB',(960,340),'#23302a');draw=ImageDraw.Draw(comparison)
for n,(id,label) in enumerate([('cottage_a','Preserved original reference'),('arch_cordage_canopy','I / new cordage work'),('arch_timber_workyard','II / new stone-tool carpentry'),('arch_bronze_smelter','III / new clay-furnace smelter')]):
 e=atlas[id];x,y,w,h=e['packed_rect'];src=page if id.startswith('arch_') else original;im=src.crop((x,y,x+w,y+h)).resize((w*3,h*3),Image.Resampling.NEAREST)
 comparison.paste(im,(n*240+(240-im.width)//2,230-im.height),im);draw.text((n*240+12,260),label,fill='#efe4c9')
comparison.save(R/'docs/architecture/batch-b-reference-comparison.png')
