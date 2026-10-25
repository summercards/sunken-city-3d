"""Register only this freshly authored kit after current saved sources pass verification."""
from pathlib import Path
import json,hashlib,os
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunny_bloom_retreat_v003'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
qa=json.loads((W/'verification.json').read_text());source=D/'sunny_bloom_retreat.blend';assert qa['passed'] and len(qa['views'])>=4 and qa['source_sha256']==sha(source)
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];path=R/route['ledger'];book=json.loads(path.read_text());catalog=json.loads((D/'catalog.json').read_text())['components'];rows=[]
for e in catalog:
 p=R/e['component_source'];assert sha(p)==e['source_sha256'];e['asset_ledger']=route['ledger']+'#'+e['asset_id'];write(p.parent/'asset_manifest.json',e);rows.append(dict(asset_id=e['asset_id'],name=e['name'],domain='scenes',stage='source_verified_runtime_pending',source=e['component_source'],source_sha256=e['source_sha256'],manifest=str((p.parent/'asset_manifest.json').relative_to(R)),version='v003',runtime_path=None,prefab=None,license='pending_user_reference_rights_review',geometry_fingerprint=e['geometry_fingerprint'],consumer_features=['SEA-ASSET'],category=e['category'],scope='scene_local',note='本次附件从零制作的 Sunny Bloom Retreat；建筑、陈设、花草分离；仅源级验收。'))
aid='SEA-SCENE-SBR-ASSEMBLY';manifest=dict(asset_id=aid,name='阳光繁花小屋',version='v003',source=str(source.relative_to(R)),source_sha256=sha(source),component_catalog='catalog.json',component_plan='component_plan.json',component_instances='component_instances.json',palette_asset_id='SEA-PALETTE-COZY-64',stage='source_verified_runtime_pending',runtime_status='pending',license='pending_user_reference_rights_review',reference_sha256=qa['reference_sha256'],metrics=qa['metrics'],source_policy='Fresh original construction from current reference only; no prior kit reused.',verification='docs/development/2026-10-25_sunny_bloom_retreat_v003_verification.json')
manifest['asset_ledger']=route['ledger']+'#'+aid
write(D/'asset_manifest.json',manifest)
rows.append(dict(asset_id=aid,name=manifest['name'],domain='scenes',stage=manifest['stage'],source=manifest['source'],source_sha256=manifest['source_sha256'],manifest=str((D/'asset_manifest.json').relative_to(R)),version='v003',runtime_path=None,prefab=None,license=manifest['license'],geometry_fingerprint=None,consumer_features=['SEA-ASSET'],category='scene_assembly',scope='scene_local',note='本次附件独立从零制作；49组件；Godot接入pending。'))
existing={r['asset_id']:r for r in book[route['asset_key']]}
for r in rows:
 if r['asset_id'] in existing:
  previous=existing[r['asset_id']]
  assert previous['source'].startswith('art_source/scenes/sunny_bloom_retreat/'),'AssetID belongs to another kit'
  assert sha(R/previous['source'])==previous['source_sha256'],'Previous source has unreviewed hash drift'
  r['previous_sources']=list(previous.get('previous_sources',[]))
  if previous['source']!=r['source']:r['previous_sources'].append({k:previous[k] for k in ['source','source_sha256','manifest','version']})
ids={r['asset_id'] for r in rows};book[route['asset_key']]=[r for r in book[route['asset_key']] if r['asset_id'] not in ids]+rows;write(path,book)
# Derive hashes from ledger rows, never recompute unrelated asset hashes.
indexpath=R/'assets/registry/current_source_index.json';index=json.loads(indexpath.read_text());all_sources=[]
for route in json.loads((R/'assets/registry/ledger_index.json').read_text())['domains'].values():
 for row in json.loads((R/route['ledger']).read_text())[route['asset_key']]:all_sources.append({k:row[k] for k in ['asset_id','source','source_sha256','manifest']})
index['sources']=all_sources;write(indexpath,index);print('Registered',len(rows),'records; unrelated hashes preserved.')
