"""Register reviewed r6 revisions against the captured r5 predecessor only."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASELINE=ROOT.parent/'sea-work/avatar-shape-r6-baseline-20261103'
DELIVERY='docs/development/2026-11-03_avatar_shape_and_mouth.md'

def read(path): return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value): (ROOT/path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def hash_at(path):
    data=Path(path).read_bytes()
    if Path(path).suffix in ['.gd','.gdshader','.json','.py','.md']: data=data.replace(b'\r\n',b'\n')
    return hashlib.sha256(data).hexdigest()
def digest(path): return hash_at(ROOT/path)
def guard(path,previous):
    allowed={digest(path)}
    if (BASELINE/path).exists(): allowed.add(hash_at(BASELINE/path))
    if previous not in allowed: raise SystemExit('Unreviewed r5 predecessor: '+path)

index=read('assets/registry/ledger_index.json')
updates={
 'SEA-CHAR-AVATAR-001':('characters','v005',['godot/src/avatar/avatar_visual.gd','godot/src/player/character.gd','godot/assets/data/avatar_catalog.json','art_source/characters/avatar/v005/shape_contract.json']),
 'SEA-CHAR-RIG-001':('characters','v004',['godot/src/avatar/avatar_limb_skinning.gd','godot/src/player/character.gd']),
 'SEA-CHAR-RECEIVE-001':('characters','v006',['godot/src/player/animation/item_receive.gd']),
 'SEA-CHAR-FACE-001':('characters','v003',['godot/src/avatar/avatar_face.gd']),
 'SEA-CHAR-SHAPE-001':('characters','v003',['godot/src/avatar/avatar_morphology.gd']),
 'SEA-CHAR-EXPRESSION-001':('characters','v002',['godot/src/avatar/avatar_expression.gd']),
 'SEA-UI-AVATAR-001':('ui','v004',['godot/src/avatar/avatar_editor.gd','godot/src/onboarding/arrival_camera.gd']),
}
books={d:read(index['domains'][d]['ledger']) for d in ['characters','ui']}
planned=[]
for aid,(domain,version,paths) in updates.items():
 row=next(r for r in books[domain]['assets'] if r['asset_id']==aid)
 guard(row['source'],row['source_sha256']); manifest=read(row['manifest'])
 for entry in manifest['authored_files']:
  if entry['path'] in paths: guard(entry['path'],entry['sha256'])
 planned.append((aid,row,manifest,version,paths))
inventory=read(index['runtime_inventory'])
changed={p for _,_,ps in updates.values() for p in ps}
for row in inventory['resources']:
 if row['path'] in changed: guard(row['path'],row['sha256'])

for aid,row,manifest,version,paths in planned:
 if row['source_sha256']!=digest(row['source']): row['previous_source_sha256']=row['source_sha256']
 row.update(source_sha256=digest(row['source']),version=version,verification=DELIVERY,
  note='r6 按用户最新红线：饱满A形躯干/低胯短腿、独立头横宽和臂粗、16嘴型贴图、下移帽子；原档案兼容，当前专项和真实渲染见交付。')
 manifest.update(version=version,verification=DELIVERY)
 for path in paths:
  entry=next((e for e in manifest['authored_files'] if e['path']==path),None)
  if entry is None: manifest['authored_files'].append(dict(path=path,sha256=digest(path)))
  else: entry['sha256']=digest(path)
 if aid=='SEA-CHAR-FACE-001': manifest['mouth_asset_id']='SEA-CHAR-MOUTH-001'
 write(row['manifest'],manifest)

aid='SEA-CHAR-MOUTH-001';source='godot/assets/textures/avatar/graphic_mouths.png'
manifest='assets/registry/manifests/sea-char-mouth-001.json'
paths=[source,'godot/shaders/avatar_mouth.gdshader','tools/prepare_avatar_mouth_atlas.py','art_source/characters/avatar/v005/graphic_mouth_source.png','art_source/characters/avatar/v005/graphic_mouth_manifest.json']
row=dict(asset_id=aid,name='旅人16款图形嘴型贴图',domain='characters',stage='runtime_component_verified',source=source,source_sha256=digest(source),manifest=manifest,version='v001',runtime_path=source,
 license='original_generated_artwork_and_project_authored_atlas_shader',consumer_features=['SEA-AVATAR'],verification=DELIVERY,
 note='原4嘴型ID保留，16款大块图形嘴型；透明曲面贴片，情绪切帧与开合，不复制参考游戏像素。')
existing=next((r for r in books['characters']['assets'] if r['asset_id']==aid),None)
if existing is not None and (existing['source']!=source or existing['source_sha256']!=digest(source)): raise SystemExit('Duplicate or unreviewed mouth asset ID')
if existing is None: books['characters']['assets'].append(row)
else: existing.update(row)
write(manifest,dict(asset_id=aid,asset_ledger=index['domains']['characters']['ledger']+'#'+aid,version='v001',source=source,runtime_path=source,
 authored_files=[dict(path=p,sha256=digest(p)) for p in paths],verification=DELIVERY,tiles=16,layout='4x4; 256px tiles; 1024x1024 RGBA',
 source_type='original generated mouth sheet; largest-alpha-component extraction, transparent padding, shader animation',consumer='AvatarFace + AvatarExpression'))
for domain,book in books.items(): write(index['domains'][domain]['ledger'],book)
owners={p:aid for aid,(_,_,ps) in updates.items() for p in ps if p.startswith('godot/')}
for path in paths:
 if path.startswith('godot/'): owners[path]='SEA-CHAR-MOUTH-001'
for path,owner in owners.items():
 entry=next((r for r in inventory['resources'] if r['path']==path),None)
 if entry is None: inventory['resources'].append(dict(path=path,bytes=(ROOT/path).stat().st_size,sha256=digest(path),asset_id=owner,status='runtime_component_verified'))
 else:
  if entry['sha256']!=digest(path): entry['previous_sha256']=entry['sha256']
  entry.update(bytes=(ROOT/path).stat().st_size,sha256=digest(path))
  marker='2026-11-03 SEA-AVATAR-R22–R24'
  if marker not in entry.get('note',''): entry['note']=entry.get('note','')+' '+marker+'：本轮轮廓/嘴型/帽位修订，精确审阅前身后登记。'
write(index['runtime_inventory'],inventory)
projection=read('assets/registry/current_source_index.json')
projection['sources']=[{k:r[k] for k in ['asset_id','source','source_sha256','manifest']} for route in index['domains'].values() for r in read(route['ledger'])[route['asset_key']]]
write('assets/registry/current_source_index.json',projection)
content=read(index['content_index'])
for table in content['tables']:
 if table['path']=='godot/assets/data/avatar_catalog.json': table['ids']=[s['id'] for s in read(table['path'])['slots']]
write(index['content_index'],content)
print('Registered r6 shape, head/arm controls, mouth atlas and hat placement only.')
