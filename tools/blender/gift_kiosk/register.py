"""Register only this reviewed delivery; do not refresh unrelated drifting hashes."""
import argparse,hashlib,json,os,struct,sys,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/gift_kiosk/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
sys.path.insert(0,str(R/'tools'));import apply_water_layer as layers
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write_json(p,value):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def fingerprint(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);base=20+n+8;h=hashlib.sha256()
 for mesh in g['meshes']:
  for primitive in mesh['primitives']:
   for a in [primitive['attributes']['POSITION'],primitive['indices']]:
    accessor=g['accessors'][a];view=g['bufferViews'][accessor['bufferView']];at=base+view.get('byteOffset',0);h.update(raw[at:at+view['byteLength']])
 return h.hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);p.add_argument('--write',action='store_true');a=p.parse_args()
 signed=json.loads(a.report.read_text(encoding='utf-8'))
 for test in ['gift-kiosk','visual-gift-kiosk']:assert signed['results'][test]['passed'],test+' must pass before runtime promotion'
 source_report=json.loads((W/'source_verification.json').read_text());assert source_report['passed']
 assert json.loads((W/'export_audit.json').read_text())['passed'],'Independent GLB vs bpy audit must pass'
 opt=json.loads((D/'export/v001/optimization_manifest.json').read_text(encoding='utf-8'));assert opt['fidelity']['passed']
 for protected,expected in opt['protected_sources'].items():assert sha(Path(protected))==expected,protected+' protected source drift'
 plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];layout=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
 routes=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=routes['domains']['scenes'];book_path=R/route['ledger'];book=json.loads(book_path.read_text(encoding='utf-8'));assets=book[route['asset_key']];byid={e['asset_id']:e for e in assets}
 all_ids=[]
 for domain,routing in routes['domains'].items():
  all_ids += [e['asset_id'] for e in json.loads((R/routing['ledger']).read_text(encoding='utf-8'))[routing['asset_key']]]
 assert len(all_ids)==len(set(all_ids))
 new=[];runtime_files={};summaries={}
 for e in catalog:
  o=next(o for o in opt['components'] if o['asset_id']==e['asset_id']);prefab=f'godot/scenes/components/facilities/gift_kiosk/{e["key"]}.tscn';layer,role=layers.classify(e['asset_id'])
  assert sha(R/o['glb'])==o['glb_sha256'],e['asset_id']+' GLB drift since export/audit'
  manifest=dict(e,asset_ledger=route['ledger']+'#'+e['asset_id'],runtime_path=o['glb'],runtime_sha256=sha(R/o['glb']),prefab=prefab,prefab_sha256=sha(R/prefab),optimized_source=opt['optimized_source'],optimized_sha256=opt['optimized_sha256'],optimization_manifest='art_source/scenes/gift_kiosk/v001/export/v001/optimization_manifest.json',triangles_before=o['triangles_before'],triangles_after=o['triangles_after'],geometry_fingerprint=fingerprint(R/o['glb']))
  mp=R/e['component_source'];manifest_path=mp.parent/'asset_manifest.json'
  row={k:manifest[k] for k in ['asset_id','name','source_sha256','runtime_path','runtime_sha256','prefab','prefab_sha256','optimized_source','optimized_sha256','optimization_manifest','geometry_fingerprint']}
  row.update(domain='scenes',source=e['component_source'],manifest=manifest_path.relative_to(R).as_posix(),version='v001',runtime_version='v001',suite='gift_kiosk',scope='scene_local',origin='bottom_center',front_axis='-Y(Blender) -> +Z(Godot)',bounds_size_m=e['bounds_size'],triangles=o['triangles_after'],material_roles=e['material_roles'],palette=plan['palette'],building_class=layers.classify_building(e['asset_id']),water_layer=layer,water_layer_role=role,stage='source_runtime_verified_provenance_pending',maintenance_status='runtime_integrated_verified',license='pending_user_reference_commercial_rights_review',user_art_acceptance='pending',consumer_features=['SEA-ASSET','SEA-WORLD'],collision=False,interactive=False,verification=[str(a.report.resolve()),'docs/development/2026-11-07_gift_kiosk.md'])
  row['category']='building/structure' if row['building_class'] is not None else ('upgrade_attachment/plants' if e['group']=='plant' else 'furniture/fixed_accessory')
  if row['building_class']=='underwater':row.update(blocks_actor=False,blocks_water=False,walkable=False,has_landing=False,shoreline_source=False,note='Shallow reference flotation equipment only; no underwater architectural base or gameplay space. Explicitly excluded from deck collision/blocking/shore derivation.')
  if e['key'] in ['awning_blue','awning_white']:row['shared_geometry_family']='gks_awning_strip_palette_uv_variants'
  new.append(row);summaries[e['key']]=row
  if a.write:write_json(manifest_path,manifest)
  for path in [o['glb'],o['glb']+'.import',prefab]:runtime_files[path]=(e['asset_id'],'runtime_integrated_verified_provenance_pending')
 assembly_id='SEA-SCENE-GKS-ASSEMBLY';source=D/'gift_kiosk.blend';prefab='godot/scenes/facilities/floating_shop.tscn'
 assert sha(source)==source_report['source_sha256']==opt['source_sha256_after']
 assembly={'asset_id':assembly_id,'name':'海上礼品商亭','domain':'scenes','source':source.relative_to(R).as_posix(),'source_sha256':sha(source),'manifest':'art_source/scenes/gift_kiosk/v001/asset_manifest.json','asset_ledger':route['ledger']+'#'+assembly_id,'version':'v001','prefab':prefab,'prefab_sha256':sha(R/prefab),'runtime_path':prefab,'runtime_sha256':sha(R/prefab),'optimized_source':opt['optimized_source'],'optimized_sha256':opt['optimized_sha256'],'optimization_manifest':'art_source/scenes/gift_kiosk/v001/export/v001/optimization_manifest.json','geometry_fingerprint':sha(D/'component_instances.json'),'palette':plan['palette'],'category':'building/shop','classification':{'category':'building','subcategory':'shop','level':'商店'},'building_class':'above_water','water_layer':'amphibious','water_layer_role':'entity','facility_id':assembly_id,'scope':'scene_local','stage':'source_runtime_verified_provenance_pending','maintenance_status':'runtime_integrated_verified','zone_id':'sea_supply','interactive':True,'collision':{'walkable_deck':True,'water_blocker':'deck_component_geometry_only','underwater_excluded':True},'underwater_architectural_base':False,'motion':{'axis':'world_Y','amplitude_m':.12,'secondary_amplitude_m':.025,'period_s':6.8,'actor_carry_owner':'ActorController'},'components':[e['asset_id'] for e in catalog],'component_count':47,'instance_count':len(layout),'triangles':sum(summaries[e['key']]['triangles'] for e in layout),'placement_owner':'main.tscn','runtime_instances':['World/SeaStructures/floating_shop'],'reference_license':'pending_user_reference_commercial_rights_review','license':'pending_user_reference_commercial_rights_review','user_art_acceptance':'pending','consumer_features':['SEA-ASSET','SEA-WORLD','SEA-MOVE','SEA-NAV'],'verification':[str(a.report.resolve()),'docs/development/2026-11-07_gift_kiosk.md']}
 new.append(assembly)
 old=byid['SEA-SCENE-FSH-ASSEMBLY'];old_hash=old['source_sha256'];assert sha(R/old['source'])==old_hash
 old.update(name='旧海上驿站（原浮店模型）',prefab='godot/scenes/facilities/floating_rest_stop.tscn',prefab_sha256=sha(R/'godot/scenes/facilities/floating_rest_stop.tscn'),runtime_instances=['World/SeaStructures/floating_rest_stop'],interactive=False,zone_id=None,classification={'category':'building','subcategory':'rest_stop','level':'旧驿站景观'},collision={'walkable_deck':False,'water_blocker':'existing_geometry_only_at_user_placement'},runtime_role_revision='2026-11-07: retired shop; exact user transform and old GLB/source preserved; no second sea_supply identity, landing or shop interaction',maintenance_status='retired_shop_visual_preserved_user_transform')
 old['note']+=' 2026-11-07 当前角色：旧海上驿站景观，海上商店身份由SEA-SCENE-GKS-ASSEMBLY接替。原用户缩放/下沉变换及旧源、GLB不改；旧50米坐标只属历史参考。' if '2026-11-07 当前角色' not in old['note'] else ''
 for row in new:
  if row['asset_id'] in byid:assets[assets.index(byid[row['asset_id']])]=row
  else:assets.append(row)
 assert len({e['asset_id'] for e in assets})==len(assets)
 runtime_files[prefab]=(assembly_id,'runtime_integrated_verified_provenance_pending')
 runtime_files['godot/scenes/facilities/floating_rest_stop.tscn']=('SEA-SCENE-FSH-ASSEMBLY','retired_shop_visual_preserved_user_transform')
 runtime_files['godot/assets/models/facilities/gift_kiosk/runtime_manifest.json']=(assembly_id,'runtime_contract_verified')
 for pth in (R/'godot/assets/materials/gift_kiosk').glob('*.tres'):runtime_files[pth.relative_to(R).as_posix()]=(assembly_id,'runtime_integrated_verified_provenance_pending')
 # Explicit reviewed whitelist. Known baseline drift in water.tres,
 # bootstrap/main.gd and the unrelated fish source is deliberately left alone.
 reviewed=['godot/scenes/main.tscn','godot/assets/data/zones.json','godot/src/facilities/floating_shop_zone.gd','godot/src/facilities/supply_counter.gd','godot/src/player/actor_controller.gd','godot/src/player/character_motor.gd','godot/src/navigation/ground_space.gd','godot/src/world/zones.gd','godot/tools/gift_kiosk_import.gd','godot/tools/capture_gift_kiosk.gd','godot/tests/test_gift_kiosk.gd','godot/tests/test_water_layer.gd']
 for pth in reviewed:runtime_files[pth]=(assembly_id,'reviewed_gift_kiosk_runtime_change')
 for pth in reviewed:
  if not pth.endswith('.gd'):continue
  uid=R/(pth+'.uid');staged_uid=Path(signed['run_dir'])/'project'/(pth.removeprefix('godot/')+'.uid')
  if not uid.exists() and staged_uid.exists() and a.write:shutil.copy2(staged_uid,uid)
  if uid.exists():runtime_files[uid.relative_to(R).as_posix()]=(assembly_id,'stable_script_uid')
 inv_path=R/routes['runtime_inventory'];inv=json.loads(inv_path.read_text(encoding='utf-8'));resources={e['path']:e for e in inv['resources']}
 for pth,(aid,status) in runtime_files.items():
  path=R/pth;assert path.is_file(),pth
  row=resources.get(pth,{'path':pth,'asset_id':aid});row.update(sha256=sha(path),bytes=path.stat().st_size,status=status)
  if pth.startswith(('godot/scenes/facilities/floating_shop','godot/assets/models/facilities/gift_kiosk','godot/assets/materials/gift_kiosk','godot/scenes/components/facilities/gift_kiosk')):row['asset_id']=aid
  resources[pth]=row
 inv['resources']=[resources[k] for k in sorted(resources)]
 if a.write:
  generated=list((R/'godot/scenes/components/facilities/gift_kiosk').glob('*.tscn'))+list((R/'godot/assets/materials/gift_kiosk').glob('*.tres'))+[R/'godot/scenes/facilities/floating_shop.tscn',R/'godot/scenes/facilities/floating_rest_stop.tscn']
  for path in generated:
   snapshot=Path(signed['run_dir'])/'project'/path.relative_to(R/'godot')
   assert snapshot.is_file() and sha(snapshot)==sha(path),str(path)+' differs from final verified scene snapshot'
  write_json(D/'runtime_assembly_receipt.json',{'schema':'sea.authored_scene_generation_guard','note':'Block regeneration after any user Godot edit; build an external candidate and review per-file changes.','generated_files':{p.relative_to(R).as_posix():sha(p) for p in generated}})
  write_json(D/'asset_manifest.json',assembly);write_json(book_path,book)
  for name,view in layers.building_views(assets,route['ledger']).items():write_json(R/route['building_views'][name],view)
  sources=[]
  for domain,routing in routes['domains'].items():
   current=book if domain=='scenes' else json.loads((R/routing['ledger']).read_text(encoding='utf-8'))
   sources += [{k:e[k] for k in ['asset_id','source','source_sha256','manifest']} for e in current[routing['asset_key']]]
  index=R/'assets/registry/current_source_index.json';saved=json.loads(index.read_text(encoding='utf-8'));saved['sources']=sources;write_json(index,saved);write_json(inv_path,inv)
  write_json(W/'registration.json',{'new_assets':len(new),'reviewed_runtime_files':len(runtime_files),'source_hashes_preserved':True,'signed_report':str(a.report.resolve()),'unrelated_baseline_drift_preserved':['SEA-DECO-ANIMAL-FISH-SCHOOL','godot/assets/materials/water.tres','godot/src/bootstrap/main.gd']})
 print(json.dumps({'write':a.write,'new_assets':len(new),'reviewed_runtime_files':len(runtime_files),'assembly_triangles':assembly['triangles']}))
if __name__=='__main__':main()
