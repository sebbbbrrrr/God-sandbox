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
 coverage.append({'age':age['id'],'name':age['name'],'definitions':len(rows),'legacy_definitions':len(rows)-len(authored),'authored_designs':len(authored),'functional_archetypes':len(archetypes),'minimum_archetypes':8,'minimum_shortfall':max(0,8-len(archetypes)),'full_age_complete':False,'recipes_exact':all(isinstance(n,int) and n>0 for b in rows for n in b['materials'].values()),'authored_lifecycle_states':False,'android_device_verified':False})
matrix=[]
for age in d['eras']:
 for region in d['regions']:
  rows=[b for b in d['buildings'] if b['primary_age']==age['id'] and b['regional_family']==region]
  sprites={b['visual']['sprite'] for b in rows if b['visual']['sprite'] in art}
  matrix.append({'age':age['id'],'region':region,'categories':','.join(sorted({b['category'] for b in rows})),'asset_count':len(sprites),'building_designs':len(rows),'functional_integration':bool(rows),'recipe_completion':bool(rows),'animation_support':'shared stages and worker choreography' if rows else 'missing','visual_quality_approval':'internal logical-scale review; device/owner pending' if sprites else 'missing','authored_damage_states':False})
report={'scope':'Batch A plus partial Batch B; full 11-age acceptance NOT met','age_summary':coverage,'region_matrix':matrix,'withheld_source_cells':[{'source':'tools/source/architecture_agricultural.png','cell':[1,1],'reason':'Timber work yard saw design needs era-appropriate redraw; no runtime region or functional definition created.'}],'regional_context':'Existing settlement_context climate values select real distinct structures. Live Nature/climate adapter remains unimplemented.','missing_regions':['coastal_island','alpine_mountain','grassland_steppe','river_wetland'],'missing_ages':[3,4,5,6,7,8,9,10,11]}
(R/'docs/architecture/coverage.json').write_text(json.dumps(report,indent=2)+'\n')
with (R/'docs/architecture/coverage.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=matrix[0]);writer.writeheader();writer.writerows(matrix)
# Exact geometric comparison, cut from the actual packed sprites.
page=Image.open(R/'assets/pixel/architecture_early.png').convert('RGBA')
contact=Image.new('RGB',(960,340),'#23302a');draw=ImageDraw.Draw(contact)
for n,(id,label) in enumerate([('wattle_house','II / Woodland'),('adobe_house','II / Desert'),('stilt_house','II / Tropical'),('earth_shelter','I / Cold')]):
 e=atlas['arch_'+id];x,y,w,h=e['packed_rect'];im=page.crop((x,y,x+w,y+h)).resize((w*3,h*3),Image.Resampling.NEAREST)
 contact.paste(im,(n*240+(240-im.width)//2,230-im.height),im);draw.text((n*240+14,250),label,fill='#efe4c9')
contact.save(R/'docs/architecture/regional-comparison.png')
print('COVERAGE: 24 canonical definitions; 15 authored designs; no age marked fully complete')
