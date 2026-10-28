import json,hashlib,shutil,os
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v008';OLD=D.parent/'v007';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v008'
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
protected={p.relative_to(R).as_posix():sha(p) for p in [OLD/'sunny_bloom_retreat.blend',R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.png']}
write(W/'protected_sources.json',protected)
targets=[R/'godot/assets/models/facilities/solar_cabin',R/'godot/assets/materials/solar_cabin',R/'godot/scenes/facilities/solar_cabin.tscn',R/'godot/scenes/zones/zone1_home_harbor.tscn',R/'assets/registry/ledgers/scenes.json',R/'assets/registry/runtime_resource_inventory.json',R/'godot/src/rendering/daylight_presets.gd',R/'godot/src/rendering/daylight_rig.gd']
for target in targets:
 for p in target.rglob('*') if target.is_dir() else [target]:
  if p.is_file():
   dst=W/'before'/p.relative_to(R);dst.parent.mkdir(parents=True,exist_ok=True)
   if not dst.exists():shutil.copy2(p,dst)
plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'));plan.update(version='v008',palette='art_source/shared/palettes/sea_cabin_timber_8x8_512.png',source_policy='Derive saved v007; retain all user offsets. Ground plank thickness 0.22m at runtime versus 0.18m reference. Pin top faces in source; lower surface root by 0.47m to keep underside/water/base relationship.')
write(D/'component_plan.json',plan)
data=json.loads((R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.json').read_text(encoding='utf-8'))
colors={'wood_light':'#C49C6E','honey':'#CAA576','wood':'#BB9265','wood_mid':'#AE855B','wood_edge':'#D1AF82'}
for e in data['cells']:
 if e['name'] in colors:e['hex']=colors[e['name']]
data.update(version='v008',scope='solar cabin timber revision',reference_color='#C49C6E',reference_thickness_m=.18,target_ground_thickness_m=.22)
write(R/plan['palette'].replace('.png','.json'),data)
print('PREPARED v008')
