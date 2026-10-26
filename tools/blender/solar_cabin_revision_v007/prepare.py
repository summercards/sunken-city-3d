"""Prepare a protected revision from the user's saved Blender edits."""
import json, shutil, hashlib, os
from pathlib import Path
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v007'
D=R/'art_source/scenes/sunny_bloom_retreat/v007'
OLD=D.parent/'v006'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
protected={str(p.relative_to(R)):sha(p) for p in [OLD/'sunny_bloom_retreat.blend',R/'art_source/shared/palettes/sea_cozy_8x8_512.png',R/'art_source/scenes/bloom_lower_building/v001/bloom_lower_building.blend']}
write(W/'protected_sources.json',protected)
paths=list((R/'godot/assets/models/facilities/solar_cabin').rglob('*'))+list((R/'godot/assets/materials/solar_cabin').rglob('*'))+[R/'godot/src/world/sunny_bloom_visual.gd',R/'godot/shaders/sunny_palette.gdshader',R/'assets/registry/ledgers/scenes.json',R/'assets/registry/runtime_resource_inventory.json']
for p in paths:
 if p.is_file():
  dst=W/'before'/p.relative_to(R);dst.parent.mkdir(parents=True,exist_ok=True)
  if not dst.exists():shutil.copy2(p,dst)
plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'))
plan.update(version='v007',source_policy='Use the user-edited saved v006, preserve every existing transform and realized mesh. New palette is scoped to solar cabin and its submerged base.',palette='art_source/shared/palettes/sea_cabin_muted_8x8_512.png')
for base,suffix,color in [('platform_board','coral','coral'),('platform_board','ochre','ochre'),('dock_board','sand','honey'),('dock_board','shade','wood')]:
 e=next(x for x in plan['components'] if x['key']==base).copy();e.update(key=base+'_'+suffix,asset_id=e['asset_id']+'-'+suffix.upper(),name=e['name']+'-'+suffix,variant_of=base,palette_color=color);plan['components'].append(e)
assert len(plan['components'])<=50
write(D/'component_plan.json',plan)
# Variant palette preserves the original file and all unrelated consumers.
p=json.loads((R/'art_source/shared/palettes/sea_cozy_8x8_512.json').read_text())
colors={'cream':'#E0DAB6','sand':'#DDD4AF','white':'#D7D8BA','mint_white':'#CACEB0','cloud':'#D2D1B6','snow':'#DDDDBF','honey':'#DDC991','wood_light':'#D2BC85','wood':'#C4AD79','wood_mid':'#B59D6A','wood_edge':'#E0D0A4'}
for c in p['cells']:
 if c['name'] in colors:c['hex']=colors[c['name']]
p.update(version='v007',scope='solar_cabin and submerged base',derived_from='sea_cozy_8x8_512.png',note='Muted timber and warm ivory sampled by visual reference; coral/red/orange remain original swatches.')
write(R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.json',p)
print('PREPARED',len(plan['components']),protected)

