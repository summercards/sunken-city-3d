"""Register this kit only after saved main and standalone sources pass QA."""
from pathlib import Path
import json,hashlib,os
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/tropical_flower_house/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'tropical_flower_house'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
qa=json.loads((W/'source_verification.json').read_text());assert qa['passed']
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes']
bp=R/route['ledger'];book=json.loads(bp.read_text());old={a['asset_id']:a for a in book[route['asset_key']]}
cat=json.loads((D/'component_catalog.json').read_text())['components'];new=[]
for c in cat:
 p=R/c['component_blend'];assert sha(p)==c['source_sha256']
 new.append({'asset_id':c['component_id'],'name':c['name'],'domain':'scenes','stage':'source_verified_runtime_pending','source':c['component_blend'],'source_sha256':sha(p),'manifest':str((p.parent/'asset_manifest.json').relative_to(R)),'version':'v001','runtime_path':None,'prefab':None,'license':'pending_user_reference_rights_review','geometry_fingerprint':c['geometry_fingerprint'],'consumer_features':['SEA-ASSET'],'category':c['category'],'scope':'scene_local','note':'参考附件制作的热带花屋，38组件；建筑与花草分离，低分段厚曲面与真实倒角；源级通过，Godot接入pending。'})
p=D/'tropical_flower_house.blend';aid='SEA-SCENE-TFH-ASSEMBLY'
manifest={'asset_id':aid,'name':'饱满卡通热带花屋','source':str(p.relative_to(R)),'source_sha256':sha(p),'asset_ledger':route['ledger']+'#'+aid,'version':'v001','category':'scene_assembly','runtime_status':'pending','license':'pending_user_reference_rights_review','component_catalog':'component_catalog.json','component_instances':'component_instances.json','reference':'reference.png','component_count':len(cat),'instance_count':qa['metrics']['instances'],'separate_categories':['building','flora'],'palette_asset_id':'SEA-PALETTE-COZY-64','metrics':qa['metrics']}
save(D/'asset_manifest.json',manifest)
new.append({'asset_id':aid,'name':manifest['name'],'domain':'scenes','stage':'source_verified_runtime_pending','source':manifest['source'],'source_sha256':manifest['source_sha256'],'manifest':str((D/'asset_manifest.json').relative_to(R)),'version':'v001','runtime_path':None,'prefab':None,'license':manifest['license'],'geometry_fingerprint':None,'consumer_features':['SEA-ASSET'],'category':'scene_assembly','scope':'scene_local','note':'本次附件参考的新套件，保留所有已有套件。源级通过，未接入Godot。'})
for a in new:
 if a['asset_id'] in old:assert old[a['asset_id']]['source']==a['source'],'AssetID collision'
ids={a['asset_id'] for a in new};book[route['asset_key']]=[a for a in book[route['asset_key']] if a['asset_id'] not in ids]+new
save(bp,book)
index=json.loads((R/'assets/registry/ledger_index.json').read_text());sources=[]
for domain,rt in index['domains'].items():
 for a in json.loads((R/rt['ledger']).read_text())[rt['asset_key']]:sources.append({k:a[k] for k in ['asset_id','source','source_sha256','manifest']})
ip=R/'assets/registry/current_source_index.json';value=json.loads(ip.read_text());value['sources']=sources;save(ip,value)
print('Registered',len(new),'kit records; preserved unrelated records and shared palette.')
