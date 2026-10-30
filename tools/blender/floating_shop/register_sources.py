"""Register only this source kit through the scenes route; preserve other baselines."""
import json, hashlib, os
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/floating_shop/v001';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
qa=json.loads((W/'verification.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];source=D/'floating_shop.blend'
assert qa['passed'] and qa['standalone_packages_reopened']==39 and len(qa['views'])==10
assert qa['source_sha256']==sha(source)
index=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=index['domains']['scenes'];lp=R/route['ledger'];book=json.loads(lp.read_text(encoding='utf-8'));old={x['asset_id']:x for x in book[route['asset_key']]}
prefix='SEA-SCENE-FSH-';assembly=prefix+'ASSEMBLY';records=[]
for e in cat:
 p=R/e['component_source'];mp=p.parent/'asset_manifest.json';manifest=json.loads(mp.read_text(encoding='utf-8'))
 assert sha(p)==e['source_sha256']==manifest['source_sha256']
 records.append({'asset_id':e['asset_id'],'name':e['name'],'domain':'scenes','stage':'source_verified_runtime_pending','source':e['component_source'],'source_sha256':e['source_sha256'],'manifest':mp.relative_to(R).as_posix(),'version':'v001','runtime_path':None,'prefab':None,'license':'pending_user_reference_rights_review','geometry_fingerprint':e['geometry_fingerprint'],'consumer_features':['SEA-ASSET'],'category':e['category'],'source_group':e['source_group'],'facility_id':assembly,'placement_layer':'above_water','scope':'scene_local','note':'海上悬浮商铺独立组件；公共PaletteUV，母版及独立包重开验证完成；正式Godot接入pending。'})
am={'schema':'sea.scene.assembly_manifest','asset_id':assembly,'name':'海上悬浮商铺','version':'v001','source':source.relative_to(R).as_posix(),'source_sha256':sha(source),'asset_ledger':route['ledger']+'#'+assembly,'category':'building/structure','placement_layer':'above_water','runtime_status':'pending','license':'pending_user_reference_rights_review','reference':'reference.png','reference_sha256':sha(D/'reference.png'),'palette_asset_id':'SEA-PALETTE-COZY-64','component_catalog':'catalog.json','component_instances':'component_instances.json','metrics':qa['metrics'],'visual_review':{'status':'source_views_reviewed_user_art_acceptance_pending','views':qa['views'],'limits':['公共色板下保持sea风格，非参考图逐像素复刻','总宽包含1.2m外环廊及轮胎；12m指店体直径','屋面细节密度与锈蚀层次仍可继续美术深化']}}
save(D/'asset_manifest.json',am)
records.append({'asset_id':assembly,'name':am['name'],'domain':'scenes','stage':'source_verified_runtime_pending','source':am['source'],'source_sha256':am['source_sha256'],'manifest':(D/'asset_manifest.json').relative_to(R).as_posix(),'version':'v001','runtime_path':None,'prefab':None,'license':am['license'],'geometry_fingerprint':None,'consumer_features':['SEA-ASSET'],'category':'building/structure','facility_id':assembly,'placement_layer':'above_water','scope':'scene_local','note':'按七视角参考制作；39母版组件、250实例、10张真实渲染。建筑与植物分离；仅Blender源级完成，Godot、碰撞、导航、性能和商业授权pending。'})
for domain,routing in index['domains'].items():
 for row in json.loads((R/routing['ledger']).read_text(encoding='utf-8'))[routing['asset_key']]:
  if row['asset_id'].startswith(prefix):
   desired=next((x for x in records if x['asset_id']==row['asset_id']),None);assert domain=='scenes' and desired and row['source']==desired['source'],'AssetID collision'
ids={x['asset_id'] for x in records};book[route['asset_key']]=[x for x in book[route['asset_key']] if x['asset_id'] not in ids]+records
assert all(next(x for x in book[route['asset_key']] if x['asset_id']==k)==v for k,v in old.items() if not k.startswith(prefix))
save(lp,book)
sip=R/'assets/registry/current_source_index.json';si=json.loads(sip.read_text(encoding='utf-8'));before={x['asset_id']:x for x in si['sources']};rows=[]
for routing in index['domains'].values():
 for e in json.loads((R/routing['ledger']).read_text(encoding='utf-8'))[routing['asset_key']]:rows.append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
assert all(before.get(x['asset_id']) in (None,x) for x in rows if not x['asset_id'].startswith(prefix))
si['sources']=rows;save(sip,si)
qa['exit_codes']['registration']=0;save(W/'verification.json',qa)
save(R/'docs/development/2026-10-30_floating_shop_verification.json',qa)
print(json.dumps({'registered':len(records),'category':'building/structure','ledger':route['ledger'],'preserved_unrelated_records':True},ensure_ascii=False))
