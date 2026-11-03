"""Register only reviewed low-shoulder r7 sources, preserving other domains."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASELINE=ROOT.parent/'sea-work/avatar-shoulder-r7-baseline'
REVIEWED_R7=ROOT.parent/'sea-work/verification/20261103-105940-avatar-shoulder-r7-final-render-e76504/project/src/avatar/avatar_morphology.gd'
DELIVERY='docs/development/2026-11-03_avatar_low_shoulders.md'

def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value):(ROOT/path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def hash_at(path):
 data=Path(path).read_bytes()
 if Path(path).suffix in ['.gd','.json','.md','.gdshader','.py']:data=data.replace(b'\r\n',b'\n')
 return hashlib.sha256(data).hexdigest()
def digest(path):return hash_at(ROOT/path)
def guard(path,recorded):
 allowed={digest(path)}
 if (BASELINE/path).exists():allowed.add(hash_at(BASELINE/path))
 if path=='godot/src/avatar/avatar_morphology.gd' and REVIEWED_R7.exists():allowed.add(hash_at(REVIEWED_R7))
 if recorded not in allowed:raise SystemExit('Unreviewed shoulder predecessor: '+path)

index=read('assets/registry/ledger_index.json');route=index['domains']['characters']
book=read(route['ledger']);inventory=read(index['runtime_inventory'])
changes={
 'SEA-CHAR-AVATAR-001':('v006',['godot/src/avatar/avatar_visual.gd','godot/src/player/character.gd','art_source/characters/avatar/v006/shoulder_contract.json','art_source/characters/avatar/v006/shoulder_reference.png']),
 'SEA-CHAR-RIG-001':('v005',['godot/src/player/character.gd']),
 'SEA-CHAR-SHAPE-001':('v004',['godot/src/avatar/avatar_morphology.gd','art_source/characters/avatar/v006/shoulder_contract.json']),
}
pending=[]
for aid,(version,paths) in changes.items():
 row=next(r for r in book[route['asset_key']] if r['asset_id']==aid)
 guard(row['source'],row['source_sha256']);manifest=read(row['manifest'])
 for entry in manifest['authored_files']:
  if entry['path'] in paths:guard(entry['path'],entry['sha256'])
 pending.append((aid,row,manifest,version,paths))
reviewed={p for _,paths in changes.values() for p in paths}
for row in inventory['resources']:
 if row['path'] in reviewed:guard(row['path'],row['sha256'])

for aid,row,manifest,version,paths in pending:
 if row['source_sha256']!=digest(row['source']):row['previous_source_sha256']=row['source_sha256']
 row.update(source_sha256=digest(row['source']),version=version,verification=DELIVERY,
  note='r7 按用户最新红线内收/降低肩口，平顺颈胸、袖口与腋下；标准胖体肩根间距0.28937m、高0.74125m，骨架静止绑定和存档格式保持；本轮实际网格/渲染/动作验证。')
 manifest.update(version=version,verification=DELIVERY,shoulder_contract='art_source/characters/avatar/v006/shoulder_contract.json')
 for path in paths:
  item=next((e for e in manifest['authored_files'] if e['path']==path),None)
  if item is None:manifest['authored_files'].append(dict(path=path,sha256=digest(path)))
  else:item['sha256']=digest(path)
 write(row['manifest'],manifest)
write(route['ledger'],book)
for row in inventory['resources']:
 if row['path'] not in reviewed:continue
 if row['sha256']!=digest(row['path']):row['previous_sha256']=row['sha256']
 row.update(sha256=digest(row['path']),bytes=(ROOT/row['path']).stat().st_size)
 marker='2026-11-03 SEA-AVATAR-R25'
 if marker not in row.get('note',''):row['note']=row.get('note','')+' '+marker+'：最新低肩内收与上胸修顺，按已审阅前身定点登记。'
write(index['runtime_inventory'],inventory)
projection=read('assets/registry/current_source_index.json')
projection['sources']=[{k:r[k] for k in ['asset_id','source','source_sha256','manifest']} for entry in index['domains'].values() for r in read(entry['ledger'])[entry['asset_key']]]
write('assets/registry/current_source_index.json',projection)
print('Registered avatar/rig/shape shoulder revisions only; other source hashes unchanged.')
