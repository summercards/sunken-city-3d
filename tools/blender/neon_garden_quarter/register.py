"""Register only NGQ rows after source + skill gates. Preserve unrelated stored hashes."""
import hashlib,json,os,sys,importlib.util,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter/v001'
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
P=read(D/'component_plan.json');C=read(D/'component_catalog.json')['components'];V=read(W/'source_verification.json');K=read(W/'skill_verification.json');VIS=read(W/'visual_review.json')
assert V['passed'] and K['passed'] and VIS['passed'],'all source gates must pass'
assert sha(D/'neon_garden_quarter.blend')==V['source_sha256']
assert all(sha(R/c['source'])==c['source_sha256'] for c in C)
assert sha(R/P['palette'])==P['palette_sha256']==V['palette_sha256']
I=read(R/'assets/registry/ledger_index.json');route=I['domains']['scenes'];bookpath=R/route['ledger'];before=bookpath.read_bytes();book=json.loads(before)
spec=importlib.util.spec_from_file_location('water_policy',R/'tools/apply_water_layer.py');policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)
stage='source_verified_runtime_integration_pending';evidence=['docs/development/2026-11-04_neon_garden_quarter.md',str(W/'source_verification.json'),str(W/'skill_verification.json'),str(W/'visual_review.json')]
stats={x['key']:x for x in V['components']};new=[]
for c in C:
 aid=c['asset_id'];layer,role=policy.classify(aid);cl=policy.classify_building(aid);assert cl==c['building_class']
 classification=dict(category='building' if c['category']=='architecture' else 'upgrade_attachment',subcategory='structure' if c['category']=='architecture' else ('plants' if c['category']=='plants' else 'decoration'))
 new.append(dict(asset_id=aid,name=c['name'],domain='scenes',suite=P['suite'],scope='scene_local',category=c['category'],classification=classification,building_class=cl,water_layer=layer,water_layer_role=role,source=c['source'],source_sha256=c['source_sha256'],manifest=c['manifest'],version='v001',stage=stage,license='pending_user_supplied_reference',consumer_features=['SEA-ASSET'],material_roles=c['material_roles'],palette=P['palette'],origin='bottom_center',front_axis='-Y',bounds_size_m=c['bounds_size_m'],geometry_fingerprint=c['geometry_fingerprint'],polygons=stats[c['key']]['polygons'],triangles=stats[c['key']]['triangles'],verification=evidence,collision='runtime_pending',navigation='runtime_pending',runtime_path=None,loaded_branch=c['loaded_branch']))
atlas_source=(D/'textures/poster_atlas.png').relative_to(R).as_posix();atlas_manifest=D/'textures/asset_manifest.json'
atlas=dict(asset_id=P['texture_asset_id'],name='霓虹花园街区-image2八幅广告图集',domain='scenes',suite=P['suite'],category='signage_texture',scope='scene_local',building_class=None,water_layer='none',water_layer_role='none',source=atlas_source,source_sha256=sha(R/atlas_source),manifest=atlas_manifest.relative_to(R).as_posix(),version='v001',stage='source_verified_runtime_integration_pending',license='pending_user_supplied_reference',generator='gpt-image-2',image_size=[2048,2048],atlas_layout=dict(columns=4,rows=2),reference_sha256=P['reference_sha256'],prompt=(D/'textures/image2_prompt.txt').relative_to(R).as_posix(),verification=evidence)
dump(atlas_manifest,dict(atlas,asset_ledger=route['ledger']+'#'+atlas['asset_id'],usage='Only printed surfaces; explicit PosterUV and PosterMask, main palette remains external.'))
master=dict(asset_id=P['assembly_asset_id'],name='霓虹花园街区-完整水上建筑群',domain='scenes',suite=P['suite'],scope='scene_local',category='building_assembly',classification=dict(category='building',subcategory='structure'),building_class='above_water',water_layer='surface',water_layer_role='entity',source=V['source'],source_sha256=V['source_sha256'],manifest=(D/'asset_manifest.json').relative_to(R).as_posix(),version='v001',stage=stage,license='pending_user_supplied_reference',consumer_features=['SEA-ASSET'],component_count=len(C),instance_count=V['assembly']['visible_instances'],polygons=V['assembly']['polygons'],triangles=V['assembly']['triangles'],palette=P['palette'],material_roles=['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],verification=evidence,collision='runtime_pending',navigation='runtime_pending',runtime_path=None)
dump(D/'asset_manifest.json',dict(master,asset_ledger=route['ledger']+'#'+master['asset_id'],component_plan='component_plan.json',catalog='component_catalog.json',instances='component_instances.json',branch=P['branch'],poster_exception=P['material_exception'],source_bounds=V['assembly'],reference_sha256=P['reference_sha256'],spatial_intent=dict(central_street_clear_strip=dict(x=[-2.5,2.5],y=[-10,9.2],surface_z=.3),deck_top_z=.3,landing_intent=[0,-10.8,.3],boat_approach_intent=[0,-14,0],status='Blender source layout only; real capsule, landing, blocking and gameplay unverified'),completion=dict(back_and_side_facades=True,roof_services=True,plants_separate=True,no_water=True,no_human_or_animal_meshes=True),pending=['Godot integration','runtime capsule and boat clearance','collision/navigation/shoreline','performance optimization','reference commercial rights','user final art acceptance']))
new+=[master,atlas];ids={x['asset_id'] for x in new};assert len(ids)==48
for domain,rt in I['domains'].items():
 for row in read(R/rt['ledger'])[rt['asset_key']]:
  assert row['asset_id'] not in ids or row.get('suite')==P['suite'],'duplicate ID owned by another suite'
old_rows={x['asset_id']:x for x in book[route['asset_key']] if x['asset_id'] not in ids}
book[route['asset_key']]=[x for x in book[route['asset_key']] if x['asset_id'] not in ids]+new
assert all(old_rows[k]==next(x for x in book[route['asset_key']] if x['asset_id']==k) for k in old_rows)
backup=W/'registry_before_registration';backup.mkdir(exist_ok=True)
if not(backup/'scenes.json').exists():(backup/'scenes.json').write_bytes(before)
assert bookpath.read_bytes()==before,'concurrent scenes ledger edit; rerun from current rows'
dump(bookpath,book)
# Derived index uses every stored source hash verbatim. Never refresh unrelated hashes.
idxpath=R/'assets/registry/current_source_index.json';srcidx=read(idxpath);sources=[]
for domain,rt in I['domains'].items():
 sources.extend({k:a[k] for k in ['asset_id','source','source_sha256','manifest']} for a in read(R/rt['ledger'])[rt['asset_key']])
srcidx['sources']=sources;dump(idxpath,srcidx)
for name,view in policy.building_views(book[route['asset_key']],route['ledger']).items():dump(R/route['building_views'][name],view)
dump(W/'registration_report.json',dict(passed=True,registered_rows=len(new),component_rows=len(C),assembly_rows=1,texture_rows=1,unrelated_rows_preserved=len(old_rows),asset_ids=sorted(ids),source_sha256=V['source_sha256']))
print('NGQ_REGISTERED',len(new),'rows; unrelated source hashes preserved')
