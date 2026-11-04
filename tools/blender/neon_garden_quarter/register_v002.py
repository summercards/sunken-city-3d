"""Promote reviewed NGQ sources, retaining previous versions and the existing atlas."""
import hashlib,importlib.util,json,os
from pathlib import Path

root=Path(__file__).resolve().parents[3]
version=os.environ.get('NGQ_VERSION','v002')
assert version in ['v002','v003']
source=root/'art_source/scenes/neon_garden_quarter'/version
work=Path(os.environ.get('SEA_WORK_ROOT',root.parent/'sea-work'))/'neon_garden_quarter'/version
doc=f'docs/development/2026-11-05_neon_garden_quarter_{version}.md'

def read(path):return json.loads(path.read_text(encoding='utf8'))
def write(path,data):
    payload=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf8')
    if path.exists() and path.read_bytes()==payload:return
    temporary=path.with_name(path.name+'.ngq.tmp')
    temporary.write_bytes(payload)
    temporary.replace(path)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

plan=read(source/'component_plan.json')
catalog=read(source/'component_catalog.json')['components']
audit=read(work/'source_verification.json')
structure=read(work/'structure_verification.json')
skill=read(work/'skill_verification.json')
visual=read(work/'visual_review.json')
assert all(report['passed'] for report in [audit,structure,skill,visual])
assert sha(source/'neon_garden_quarter.blend')==audit['source_sha256']==structure['source_sha256']==visual['source_sha256']
assert all(sha(root/item['source'])==item['source_sha256'] for item in catalog)

index=read(root/'assets/registry/ledger_index.json');route=index['domains']['scenes']
ledger=root/route['ledger'];ledger_snapshot=ledger.read_bytes();book=json.loads(ledger_snapshot)
key=route['asset_key'];old={row['asset_id']:row for row in book[key]}
policy_spec=importlib.util.spec_from_file_location('water_policy',root/'tools/apply_water_layer.py')
policy=importlib.util.module_from_spec(policy_spec);policy_spec.loader.exec_module(policy)
evidence=[doc,str(work/'source_verification.json'),str(work/'structure_verification.json'),str(work/'skill_verification.json'),str(work/'visual_review.json')]
stage='source_verified_runtime_integration_pending'
runtime_by_key={}
if version=='v003':
    stage='runtime_component_verified_provenance_pending'
    runtime_report=read(work/'runtime_review.json');assert runtime_report['passed']
    evidence.append(runtime_report['verification_report'])
    export_path=source/'export/v003/export_manifest.json';export=read(export_path)
    runtime_by_key={entry['key']:entry for entry in export['components']}
    assert set(runtime_by_key)=={entry['key'] for entry in catalog}
    for entry in runtime_by_key.values():
        assert sha(root/entry['glb'])==entry['glb_sha256']
        assert sha(root/entry['optimized_source'])==entry['optimized_sha256']
stats={entry['key']:entry for entry in audit['components']}

def versioned(row):
    asset_id=row['asset_id'];prev=old.get(asset_id)
    layer,role=policy.classify(asset_id)
    row.update(domain='scenes',suite=plan['suite'],scope='scene_local',version=version,stage=stage,
               building_class=policy.classify_building(asset_id),water_layer=layer,water_layer_role=role,
               license='pending_user_supplied_reference',consumer_features=['SEA-ASSET'],verification=evidence,
               runtime_path=None,collision='runtime_pending',navigation='runtime_pending')
    if prev:
        history=list(prev.get('previous_sources',[]))
        if prev['source']!=row['source']:
            assert sha(root/prev['source'])==prev['source_sha256'],asset_id+' previous source drift'
            history.append({k:prev[k] for k in ['source','source_sha256','manifest','version']})
        row['previous_sources']=history
    return row

updates={}
for item in catalog:
    asset_id=item['asset_id'];metric=stats[item['key']]
    fields=['asset_id','name','category','source','source_sha256','manifest','bounds_size_m','geometry_fingerprint','material_roles','palette','origin','front_axis','loaded_branch']
    row=versioned({field:item[field] for field in fields})
    assert row['building_class']==item['building_class']
    row.update(triangles=metric['triangles'],polygons=metric['polygons'],maintenance_status='source_verified')
    if runtime_by_key:
        runtime=runtime_by_key[item['key']]
        row.update(runtime_path=runtime['glb'],runtime_sha256=runtime['glb_sha256'],prefab=runtime['prefab'],runtime_triangles=runtime['triangles_after'],optimized_source=runtime['optimized_source'],optimized_sha256=runtime['optimized_sha256'],collision='facility_owned',navigation='facility_owned')
    updates[asset_id]=row
assembly_id=plan['assembly_asset_id']
assembly=versioned(dict(asset_id=assembly_id,name='霓虹花园街区·水上建筑群结构修订',category='building_assembly',source=audit['source'],source_sha256=audit['source_sha256'],manifest=(source/'asset_manifest.json').relative_to(root).as_posix(),component_count=len(catalog),instance_count=audit['assembly']['visible_instances'],polygons=audit['assembly']['polygons'],triangles=audit['assembly']['triangles'],palette=plan['palette'],poster_asset_id=plan['texture_asset_id'],material_roles=['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']))
updates[assembly_id]=assembly
if runtime_by_key:
    zone=next(entry for entry in read(root/'godot/assets/data/zones.json') if entry['id']=='neon_garden_quarter')
    assembly.update(runtime_path=export['runtime_assembly'],runtime_sha256=sha(root/export['runtime_assembly']),export_manifest=export_path.relative_to(root).as_posix(),world_anchor=zone['origin'],collision='boat_blockers_from_foundation',navigation='open_water_route_verified',landing='street_landing_verified')
previous_catalog=read(source.parent/'v001/component_catalog.json')['components']
retired={item['asset_id'] for item in previous_catalog if item['key'] in plan['retired_components']}
for asset_id in retired:
    previous=old[asset_id];assert sha(root/previous['source'])==previous['source_sha256']
    updates[asset_id]=dict(previous,maintenance_status='historical_source_retained',removed_from_assembly_version='v002')
assert len(catalog)==50 and len(retired)==3 and plan['texture_asset_id'] not in updates
assert sha(root/old[plan['texture_asset_id']]['source'])==audit['poster_sha256']
for domain,entry in index['domains'].items():
    if domain=='scenes':continue
    assert not set(updates)&{row['asset_id'] for row in read(root/entry['ledger'])[entry['asset_key']]}
for asset_id in set(updates)&old.keys():assert old[asset_id].get('suite')==plan['suite']

pending=['upper floors and roof gameplay access','reference commercial rights'] if runtime_by_key else ['runtime integration','collision','navigation','landing','reference commercial rights']
write(source/'asset_manifest.json',dict(assembly,asset_ledger=route['ledger']+'#'+assembly_id,component_plan='component_plan.json',catalog='component_catalog.json',instances='component_instances.json',sign_mounts='mounting_manifest.json',revision_contract=plan['revision_contract'],branch=plan['branch'],reference_sha256=plan['reference_sha256'],poster_exception=plan['material_exception'],source_bounds=audit['assembly'],pending=pending))
book[key]=[updates.get(row['asset_id'],row) for row in book[key]]+[row for asset_id,row in updates.items() if asset_id not in old]
assert ledger.read_bytes()==ledger_snapshot,'Concurrent scene ledger edit. Read and run again.'
write(ledger,book)
source_index=root/'assets/registry/current_source_index.json';derived=read(source_index)
derived['sources']=[{field:row[field] for field in ['asset_id','source','source_sha256','manifest']} for entry in index['domains'].values() for row in read(root/entry['ledger'])[entry['asset_key']]]
write(source_index,derived)
for name,value in policy.building_views(book[key],route['ledger']).items():write(root/route['building_views'][name],value)
if runtime_by_key:
    inventory_path=root/index['runtime_inventory'];inventory=read(inventory_path)
    runtime_paths={assembly['runtime_path']:assembly_id,'godot/src/world/neon_garden_quarter.gd':assembly_id,'godot/tools/neon_garden_quarter_import.gd':assembly_id,'godot/assets/textures/facilities/neon_garden_quarter/poster_atlas.png':plan['texture_asset_id']}
    for entry in runtime_by_key.values():
        for path in [entry['glb'],entry['glb']+'.import',entry['prefab']]:runtime_paths[path]=entry['asset_id']
    atlas_path='godot/assets/textures/facilities/neon_garden_quarter/poster_atlas.png'
    assert sha(root/atlas_path)==audit['poster_sha256']
    runtime_paths[atlas_path+'.import']=plan['texture_asset_id']
    inventory['resources']=[row for row in inventory['resources'] if row['path'] not in runtime_paths]
    inventory['resources'] += [dict(path=path,bytes=(root/path).stat().st_size,sha256=sha(root/path),asset_id=asset_id,status=stage) for path,asset_id in runtime_paths.items()]
    inventory['resources'].sort(key=lambda row:row['path'])
    write(inventory_path,inventory)
write(work/'registration_report.json',{'passed':True,'version':version,'active_rows':51,'historical_component_rows':len(retired),'shared_atlas_rows':1,'source_sha256':audit['source_sha256'],'changed_asset_ids':sorted(updates)})
print(f'NGQ {version}: 51 current rows, 3 retired historical components, 1 existing atlas')
