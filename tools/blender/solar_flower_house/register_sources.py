"""Register only the solar flower house sources after the saved-source gate passes.
Existing unrelated asset rows and runtime hashes are never modified.
"""
from pathlib import Path
import json,hashlib,os,sys
R=Path(__file__).resolve().parents[3]
version=sys.argv[sys.argv.index('--version')+1] if '--version' in sys.argv else 'v001'
assert version in ['v001','v002','v003']
D=R/'art_source/scenes/solar_flower_house'/version;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/('solar_flower_house' if version=='v001' else 'solar_flower_house_'+version)
qa=json.loads((W/'source_verification.json').read_text());assert qa['passed'], 'source gate must pass'
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];book_path=R/route['ledger'];book=json.loads(book_path.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
catalog=json.loads((D/'component_catalog.json').read_text())['components'];new=[]
for c in catalog:
 p=R/c['component_blend'];assert sha(p)==c['source_sha256']
 new.append({'asset_id':c['component_id'],'name':c['name'],'domain':'scenes','stage':'source_verified_runtime_pending','source':c['component_blend'],'source_sha256':sha(p),'manifest':str((p.parent/'asset_manifest.json').relative_to(R)),'version':version,'runtime_path':None,'prefab':None,'license':'pending_user_reference_rights_review','geometry_fingerprint':c['geometry_fingerprint'],'consumer_features':['SEA-ASSET'],'category':c['category'],'note':'Blender 独立包及 PaletteUV 验证通过；参考图授权和 Godot 接入仍 pending。'})
for aid,name,p,mp,category in [
 ('SEA-SCENE-SOLAR-FLOWER-HOUSE','太阳能花屋参考装配',D/'solar_flower_house.blend',D/'asset_manifest.json','scene_assembly'),
 ('SEA-PALETTE-COZY-64','sea 清新治愈 64 色公共色板',R/'art_source/shared/palettes/sea_cozy_8x8_512.png',R/'art_source/shared/palettes/asset_manifest.json','shared_palette')]:
 manifest={'asset_id':aid,'name':name,'source':str(p.relative_to(R)),'source_sha256':sha(p),'asset_ledger':route['ledger']+'#'+aid,'version':version,'category':category,'runtime_status':'pending','license':'original_authored_palette' if category=='shared_palette' else 'pending_user_reference_rights_review'}
 if category=='scene_assembly':manifest.update(component_catalog='component_catalog.json',component_instances='component_instances.json',reference=json.loads((D/'component_plan.json').read_text())['reference'],component_count=len(catalog),instance_count=qa['metrics']['instances'],separate_categories=['building','flora'])
 else:manifest.update(grid=[8,8],size_px=[512,512],color_metadata='sea_cozy_8x8_512.json',sampling='Closest',uv_layer='PaletteUV',safe_inset_px=8)
 if category=='shared_palette':manifest['version']='v001'
 save(mp,manifest)
 new.append({'asset_id':aid,'name':name,'domain':'scenes','stage':'source_verified_runtime_pending','source':str(p.relative_to(R)),'source_sha256':sha(p),'manifest':str(mp.relative_to(R)),'version':manifest['version'],'runtime_path':None,'prefab':None,'license':manifest['license'],'geometry_fingerprint':None,'consumer_features':['SEA-ASSET'],'category':category,'note':'源级交付；非正式 Godot 接入。'})
ids={a['asset_id'] for a in new};old={a['asset_id']:a for a in book[route['asset_key']]}
for a in new:
 if a['asset_id'] in old:
  prior=old[a['asset_id']]
  if prior['source']!=a['source']:
   assert version in ['v002','v003'] and any('/solar_flower_house/'+v+'/' in prior['source'] for v in ['v001','v002']) and '/solar_flower_house/'+version+'/' in a['source'], 'AssetID source collision'
   history=list(prior.get('previous_sources',[]));history.append({k:prior[k] for k in ['source','source_sha256','manifest','version']});a['previous_sources']=history
  elif 'previous_sources' in prior:a['previous_sources']=prior['previous_sources']
  if version=='v002' and a['asset_id'].startswith('SEA-SCENE-SOLAR-'):
   a['note']='v002 简约低面数源；整场景展开后三角面 <=3000；建筑与花草分离，Godot 接入 pending。'
  if version=='v003' and a['asset_id'].startswith('SEA-SCENE-SOLAR-'):
   a['note']='依用户要求基于 v001 调整色调和花朵风格，建筑几何锁定；本轮为风格源，不宣称满足3000面；Godot 接入 pending。'
book[route['asset_key']]=[a for a in book[route['asset_key']] if a['asset_id'] not in ids]+new
save(book_path,book)
# Rebuild only the derived source path index from all routed ledgers.
index=json.loads((R/'assets/registry/ledger_index.json').read_text());sources=[]
for domain,rt in index['domains'].items():
 for a in json.loads((R/rt['ledger']).read_text())[rt['asset_key']]:sources.append({k:a[k] for k in ['asset_id','source','source_sha256','manifest']})
p=R/'assets/registry/current_source_index.json';value=json.loads(p.read_text());value['sources']=sources;save(p,value)
print('Registered or updated',len(new),'scene source rows; total',len(book[route['asset_key']]))
