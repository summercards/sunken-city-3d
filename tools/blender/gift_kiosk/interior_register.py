"""Register only this validated interior; never refresh unrelated content hashes."""
import argparse,hashlib,json,os,sys,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/gift_kiosk_interior/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001'
sys.path.insert(0,str(R/'tools'));import apply_water_layer as layers
p=argparse.ArgumentParser();p.add_argument('--report',required=True,type=Path);a=p.parse_args();run=a.report.parent;report=json.loads(a.report.read_text(encoding='utf-8'))
required=['gift-kiosk-interior','visual-gift-kiosk-interior','gift-kiosk','roof-reveal'];assert all(report['results'][k]['passed'] for k in required),'Scoped runtime checks must all pass'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(path,data):
 payload=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()
 if path.exists():
  with path.open('r+b') as f:f.write(payload);f.truncate()
 else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(payload)
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));source=json.loads((W/'source_verification.json').read_text());opt=json.loads((D/'export/v001/optimization_manifest.json').read_text(encoding='utf-8'))
assert source['passed'] and source['packages_reopened']==11 and opt['fidelity']['passed']
assert json.loads((W/'export_audit.json').read_text())['passed']
for path,expected in opt['protected_sources'].items():assert sha(Path(path))==expected,path
for path,expected in json.loads((W/'scope_before.json').read_text(encoding='utf-8'))['protected_files'].items():
 if path.startswith('art_source/') or path.endswith('.glb'):assert sha(R/path)==expected,path
index=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=index['domains']['scenes'];book_path=R/route['ledger'];book=json.loads(book_path.read_text(encoding='utf-8'));assets=book[route['asset_key']];byid={e['asset_id']:e for e in assets}
runtime_path=R/index['runtime_inventory'];runtime=json.loads(runtime_path.read_text(encoding='utf-8'));resources={e['path']:e for e in runtime['resources']}
new_ids=[];owned=[]
def glb_fingerprint(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);base=28+n;h=hashlib.sha256()
 for mesh in g['meshes']:
  for primitive in mesh['primitives']:
   for attr in ['POSITION','TEXCOORD_0']:
    acc=g['accessors'][primitive['attributes'][attr]];v=g['bufferViews'][acc['bufferView']];at=base+v.get('byteOffset',0);h.update(raw[at:at+v['byteLength']])
 return h.hexdigest()
for e in cat:
 row=next(v for v in opt['components'] if v['asset_id']==e['asset_id']);glb=R/row['glb'];assert sha(glb)==row['glb_sha256'];assert sha(R/e['component_source'])==row['source_sha256_after']
 prefab=f"godot/scenes/components/facilities/gift_kiosk_interior/{e['key']}.tscn"
 entry={'asset_id':e['asset_id'],'name':e['name'],'domain':'scenes','source':e['component_source'],'source_sha256':sha(R/e['component_source']),'manifest':str((R/e['component_source']).parent.relative_to(R)/'asset_manifest.json').replace('\\','/'),'version':'v001','runtime_path':row['glb'],'runtime_sha256':sha(glb),'prefab':prefab,'prefab_sha256':sha(R/prefab),'optimized_source':opt['optimized_source'],'optimized_sha256':opt['optimized_sha256'],'optimization_manifest':(D/'export/v001/optimization_manifest.json').relative_to(R).as_posix(),'geometry_fingerprint':glb_fingerprint(glb),'classification':{'category':'scene_component','subcategory':e['family']},'building_class':layers.classify_building(e['asset_id']),'water_layer':layers.classify(e['asset_id'])[0],'water_layer_role':layers.classify(e['asset_id'])[1],'facility_id':'SEA-SCENE-GKS-ASSEMBLY','scope':'scene_local','stage':'source_runtime_verified_provenance_pending','maintenance_status':'runtime_integrated_verified','triangles':row['triangles_after'],'bounds_size':e['bounds_size'],'palette':plan['palette'],'consumer_features':['SEA-ASSET','SEA-WORLD'],'license':plan['reference_license'],'user_art_acceptance':'pending','verification':[str(a.report),'docs/development/2026-11-07_gift_kiosk_interior.md']}
 entry.update(origin='bottom_center',front_axis='Godot +Z',source_collection=e['collection'],material_roles=e['material_roles'],reference=plan['reference'],reference_sha256=plan['reference_sha256'],asset_ledger=route['ledger']+'#'+e['asset_id'])
 assert e['asset_id'] not in byid,'New interior was already registered'
 assets.append(entry);byid[e['asset_id']]=entry;new_ids.append(e['asset_id']);write(R/entry['manifest'],entry)
 owned.extend([R/prefab,glb,glb.with_suffix('.glb.import')])
scene='godot/scenes/facilities/gift_kiosk_interior.tscn';assembly={'asset_id':plan['asset_id'],'name':'海上礼品商亭室内陈设','domain':'scenes','source':(D/'gift_kiosk_interior.blend').relative_to(R).as_posix(),'source_sha256':source['source_sha256'],'manifest':(D/'asset_manifest.json').relative_to(R).as_posix(),'version':'v001','runtime_path':scene,'runtime_sha256':sha(R/scene),'prefab':scene,'prefab_sha256':sha(R/scene),'optimized_source':opt['optimized_source'],'optimized_sha256':opt['optimized_sha256'],'optimization_manifest':(D/'export/v001/optimization_manifest.json').relative_to(R).as_posix(),'geometry_fingerprint':hashlib.sha256(''.join(byid[e['asset_id']]['geometry_fingerprint'] for e in cat).encode()).hexdigest(),'classification':{'category':'building','subcategory':'interior_furnishing_extension'},'building_class':'above_water','water_layer':'surface','water_layer_role':'part','facility_id':'SEA-SCENE-GKS-ASSEMBLY','scope':'scene_local','stage':'source_runtime_verified_provenance_pending','maintenance_status':'runtime_integrated_verified','components':new_ids.copy(),'component_count':11,'instance_count':112,'reused_instances':17,'expanded_new_triangles':source['expanded_triangles'],'placement_owner':'godot/scenes/facilities/gift_kiosk_interior.tscn','palette':plan['palette'],'consumer_features':['SEA-ASSET','SEA-WORLD'],'license':plan['reference_license'],'user_art_acceptance':'pending','verification':[str(a.report),'docs/development/2026-11-07_gift_kiosk_interior.md']}
assembly['asset_ledger']=route['ledger']+'#'+plan['asset_id']
assert plan['asset_id'] not in byid;assets.append(assembly);new_ids.append(plan['asset_id']);write(D/'asset_manifest.json',assembly)
parent=byid['SEA-SCENE-GKS-ASSEMBLY'];parent['prefab_sha256']=parent['runtime_sha256']=sha(R/parent['prefab']);parent['interior_extension']={'asset_id':plan['asset_id'],'prefab':scene,'feature_id':'SEA-WORLD-R27','verification':str(a.report)}
parent_manifest_path=R/parent['manifest'];parent_manifest=json.loads(parent_manifest_path.read_text(encoding='utf-8'));parent_manifest['prefab_sha256']=parent_manifest['runtime_sha256']=parent['prefab_sha256'];parent_manifest['interior_extension']=parent['interior_extension'];write(parent_manifest_path,parent_manifest)
owned += [R/scene,R/parent['prefab'],R/'godot/assets/models/facilities/gift_kiosk_interior/runtime_manifest.json']
owned += [R/p for p in ['godot/src/facilities/supply_counter.gd','godot/tests/test_gift_kiosk_interior.gd','godot/tools/capture_gift_kiosk_interior.gd','godot/tests/test_gift_kiosk.gd','godot/tools/capture_gift_kiosk.gd']]
owned += [p.with_suffix(p.suffix+'.uid') for p in owned.copy() if p.suffix=='.gd' and p.with_suffix(p.suffix+'.uid').exists()]
proof=[]
for path in owned:
 name=path.relative_to(R).as_posix();staged=run/'project'/path.relative_to(R/'godot')
 assert staged.exists() and sha(path)==sha(staged),name+' does not match tested snapshot'
 row=resources.get(name)
 if row is None:row={'path':name,'asset_id':plan['asset_id']};runtime['resources'].append(row)
 row.update(sha256=sha(path),bytes=path.stat().st_size,status='reviewed_gift_kiosk_interior_runtime_verified')
 proof.append({'path':name,'sha256':sha(path),'bytes':path.stat().st_size})
runtime['resources'].sort(key=lambda e:e['path']);write(runtime_path,runtime);write(book_path,book)
for name,data in layers.building_views(assets,route['ledger']).items():write(R/route['building_views'][name],data)
sources=[]
for domain,meta in index['domains'].items():
 ledger=book if domain=='scenes' else json.loads((R/meta['ledger']).read_text(encoding='utf-8'))
 sources.extend({k:e[k] for k in ['asset_id','source','source_sha256','manifest']} for e in ledger[meta['asset_key']])
source_index_path=R/'assets/registry/current_source_index.json';source_index=json.loads(source_index_path.read_text(encoding='utf-8'));source_index['sources']=sources;write(source_index_path,source_index)
proof={'feature_ids':['SEA-ASSET-R57','SEA-WORLD-R27'],'report':str(a.report),'passed_checks':required,'official_import_report':'D:/projects/sea-work/verification/20261107-184501-gift-kiosk-interior-first-7784c4/report.json','source_report':str(W/'source_verification.json'),'fidelity_report':str(W/'fidelity.json'),'glb_audit':str(W/'export_audit.json'),'new_asset_ids':new_ids,'runtime_files':proof,'expected_faults':[],'not_run':['low-end device performance','full unrelated feature suite'],'excluded_hash_updates':['Main, water material, concurrent NPC/residence/dive changes and all unknown source drift']}
write(R/'docs/development/2026-11-07_gift_kiosk_interior_verification.json',proof)
print('Registered',len(new_ids),'new assets and',len(proof['runtime_files']),'reviewed runtime files; no unknown hashes refreshed')
