import json,re
from pathlib import Path
R=Path(__file__).resolve().parents[3]
s=(R/'tools/blender/solar_cabin_revision_v007/integrate.py').read_text(encoding='utf-8').replace('v007','v008').replace('sea_cabin_muted_8x8_512.png','sea_cabin_timber_8x8_512.png')
# Previous revision's palette is the search target; timber palette is the replacement.
s=s.replace(".replace('sea_cozy_8x8_512.png','sea_cabin_timber_8x8_512.png')", ".replace('sea_cabin_muted_8x8_512.png','sea_cabin_timber_8x8_512.png')")
s=s.replace(".replace('sea_cozy_8x8_512.png','sea_cabin_timber_8x8_512.png')", ".replace('sea_cabin_muted_8x8_512.png','sea_cabin_timber_8x8_512.png')")
exec(compile(s,__file__,'exec'))
G=R/'godot';p=G/'scenes/facilities/solar_cabin.tscn';s=p.read_text(encoding='utf-8');s=s.replace('1, 0, -0.3, 0)','1, 0, -0.77, 0)');p.write_text(s,encoding='utf-8')
p=G/'scenes/zones/zone1_home_harbor.tscn';s=p.read_text(encoding='utf-8').replace('1.85','1.38').replace('span_max = 2.15','span_max = 1.68').replace('0, -1.03, 3.65225','0, -0.26, 3.65225');p.write_text(s,encoding='utf-8')
p=G/'assets/data/zones.json';data=json.loads(p.read_text(encoding='utf-8'))
for zone in data:
 if zone['id']!='zone1':continue
 for landing in zone['landings']:
  if landing['id']=='main':
   for key in ['dockEdge','landStand']:landing[key][1]=1.38
 for walk in zone['walk']:
  if walk['id']=='zone1_home_dock':walk.update(y=1.38,span=[1.0,1.68])
p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Runtime assertions use the actual thinner deck while keeping the old art-local top datum.
p=G/'tests/test_solar_cabin_asset.gd';s=p.read_text(encoding='utf-8').replace('absf(deck_top-1.85)','absf(deck_top-1.38)').replace('walkable deck top lowered to 1.85','thin walkable deck top is 1.38m');p.write_text(s,encoding='utf-8')
print('Thin deck: underside 1.16 / top 1.38; all current authored facility offsets retained.')
