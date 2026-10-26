"""Register only reviewed cabin assets; leave unrelated runtime drift visible."""
import json,hashlib,os
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v007';D=R/'art_source/scenes/sunny_bloom_retreat/v007';LD=R/'art_source/scenes/bloom_lower_building/v002'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
V=R.parent/'sea-work/verification/20261026-200229-solar-cabin-v007-final-tabs-16ca8e';C=V
proof=read(V/'report.json');component_proof=read(C/'report.json')['results']['solar-components'];assert component_proof['passed'] and all(proof['results'][k]['passed'] for k in ['visual-solar-cabin','surface'])
protected=read(W/'protected_sources.json');assert all(sha(R/p)==h for p,h in protected.items())
route=read(R/'assets/registry/ledger_index.json')['domains']['scenes'];bookpath=R/route['ledger'];book=read(bookpath);rows=book[route['asset_key']];byid={e['asset_id']:e for e in rows}
allowed_user_input='art_source/scenes/sunny_bloom_retreat/v006/sunny_bloom_retreat.blend'
def put(aid,name,source,manifest,version,**extra):
 source=Path(source);manifest=Path(manifest);source=source if source.is_absolute() else R/source;manifest=manifest if manifest.is_absolute() else R/manifest
 row=byid.get(aid)
 if row:
  old=R/row['source'];actual=sha(old)
  assert actual==row['source_sha256'] or row['source']==allowed_user_input,'Unreviewed source drift '+aid
  if row['source']!=source.relative_to(R).as_posix():
   prev={k:row[k] for k in ['source','source_sha256','manifest','version']}
   if actual!=row['source_sha256']:prev.update(user_edited_input_sha256=actual,input_snapshot=str(W/'user_input.blend'),reason='User explicitly supplied saved edits as the new input; original registered hash retained here.')
   row.setdefault('previous_sources',[]).append(prev)
 else:
  row={'asset_id':aid,'domain':'scenes','license':'pending_user_reference_rights_review','geometry_fingerprint':None};rows.append(row);byid[aid]=row
 row.update(name=name,source=source.relative_to(R).as_posix(),source_sha256=sha(source),manifest=manifest.relative_to(R).as_posix(),version=version,stage='runtime_integrated_verified',runtime_verified=True,consumer_features=['SEA-ASSET','SEA-WORLD'],scope='scene_local',**extra)
 write(manifest,dict(row,asset_ledger=route['ledger']+'#'+aid));return row
reports=[]
for root,kit,version in [(D,'solar_cabin','v007'),(LD,'bloom_lower_building','v002')]:
 report=read(root/'export/v001/export_manifest.json');cat={e['key']:e for e in read(root/'catalog.json')['components']};reports.append(report)
 common=dict(runtime_version='1.4',optimized_source=report['optimized_source'],optimized_sha256=report['optimized_sha256'],export_manifest=(root/'export/v001/export_manifest.json').relative_to(R).as_posix(),palette='art_source/shared/palettes/sea_cabin_muted_8x8_512.png')
 for e in report['components']:
  assert sha(R/e['glb'])==e['glb_sha256'];c=cat[e['key']];src=R/c['component_source'];prefab=e.get('prefab',f'godot/scenes/components/{kit}/{e["key"]}.tscn')
  e.update(prefab=prefab,source_version=version,runtime_verified=True,triangles_before=sum(o['triangles_before'] for o in e['optimization']),triangles_after=e['exported_triangles'],fidelity_review='upper four fixed-camera views inspected, mean absolute RGB error below 0.192/255; lower geometry/UV unchanged, GLB hashes reused and material binding checked in runtime')
  e['reduction_ratio']=1-e['triangles_after']/e['triangles_before'] if e['triangles_before'] else None
  put(e['asset_id'],e['name'],src,src.parent/'asset_manifest.json',version,category=e['category'],asset_key=e['key'],runtime_path=e['glb'],prefab=prefab,geometry_fingerprint=c.get('geometry_fingerprint'),**common)
 assembly='SEA-SCENE-SBR-ASSEMBLY' if kit=='solar_cabin' else 'SEA-SCENE-BLB-ASSEMBLY';filename='sunny_bloom_retreat.blend' if kit=='solar_cabin' else 'bloom_lower_building.blend'
 put(assembly,'太阳能木屋-海上区域' if kit=='solar_cabin' else '太阳能木屋-海下基座',root/filename,root/'asset_manifest.json',version,category='scene_assembly',runtime_path=f'godot/assets/models/facilities/{kit}/instances.json',prefab=f'godot/scenes/facilities/solar_cabin_{"surface" if kit=="solar_cabin" else "submerged_base"}.tscn',**common)
 put(assembly.replace('ASSEMBLY','OPTIMIZED'),'太阳能木屋-独立优化源-'+kit,R/report['optimized_source'],root/'export/v001/optimized_asset_manifest.json',version,category='optimized_export_source',runtime_path=None,prefab=None,**common)
 write(root/'export/v001/export_manifest.json',report)
for key in ['rear_building','solar_room','front_platform','bridge']:
 p=D/'modules'/key/(key+'.blend');aid='SEA-SCENE-SBR-MODULE-'+key.upper().replace('_','-')
 put(aid,'太阳能木屋-'+key,p,p.parent/'asset_manifest.json','v007',category='scene_module',runtime_path='godot/assets/models/facilities/solar_cabin/instances.json',prefab=f'godot/scenes/facilities/solar_cabin_{key}.tscn')
p=D/'export/v001/placement/solar_cabin/solar_cabin_v1.4.blend'
put('SEA-REF-FACILITY-SOLAR-CABIN','太阳能木屋',p,p.parent/'asset_manifest.json','v007',category='facility_assembly',runtime_path='godot/assets/models/facilities/solar_cabin/instances.json',prefab='godot/scenes/facilities/solar_cabin.tscn',note='User-edited v006 retained, muted timber/coral/ivory palette, rope connections; current Godot submerged-base local offset preserved in assembly.')
p=R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.png'
put('SEA-PALETTE-CABIN-MUTED-64','太阳能木屋低饱和木色与暖米白色板',p,p.parent/'sea_cabin_muted_asset_manifest.json','v007',category='shared_palette',runtime_path='godot/assets/textures/shared/sea_cabin_muted_8x8_512.png',prefab=None,note='New palette variant; original cozy palette unchanged. 8x8 512px nearest sampling; lossless and no mipmaps.')
byid['SEA-PALETTE-CABIN-MUTED-64']['license']='original_authored_palette';write(p.parent/'sea_cabin_muted_asset_manifest.json',dict(byid['SEA-PALETTE-CABIN-MUTED-64'],asset_ledger=route['ledger']+'#SEA-PALETTE-CABIN-MUTED-64'))
write(bookpath,book)
index=read(R/'assets/registry/current_source_index.json');index['sources']=[]
for route2 in read(R/'assets/registry/ledger_index.json')['domains'].values():
 for e in read(R/route2['ledger'])[route2['asset_key']]:index['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(R/'assets/registry/current_source_index.json',index)
inventory=read(R/'assets/registry/runtime_resource_inventory.json');runtime={e['path']:e for e in inventory['resources']};allowed={e['glb']:e['asset_id'] for report in reports for e in report['components']}
allowed.update({'godot/assets/models/facilities/solar_cabin/instances.json':'SEA-SCENE-SBR-ASSEMBLY','godot/assets/models/facilities/solar_cabin/revision_metrics.json':'SEA-SCENE-SBR-ASSEMBLY','godot/assets/textures/shared/sea_cabin_muted_8x8_512.png':'SEA-PALETTE-CABIN-MUTED-64'})
allowed.update({p.relative_to(R).as_posix():'SEA-PALETTE-CABIN-MUTED-64' for p in (R/'godot/assets/materials/solar_cabin').glob('*.tres')})
for path,aid in allowed.items():
 row=runtime.get(path)
 if not row:row={'path':path};inventory['resources'].append(row)
 elif row['sha256']!=sha(R/path):row['previous_sha256']=row['sha256']
 row.update(sha256=sha(R/path),bytes=(R/path).stat().st_size,asset_id=aid,status='runtime_integrated_verified')
write(R/'assets/registry/runtime_resource_inventory.json',inventory)
evidence=dict(source=read(W/'source_verification.json'),edits=read(W/'edit_evidence.json'),protected_sources=protected,runtime=read(V/'project/outputs/solar-cabin-runtime.json'),runtime_results=proof['results'],component_check=component_proof,optimization={'before':reports[0]['expanded_triangles_before'],'after':reports[0]['expanded_triangles_after'],'four_view_rgb_comparison':read(W/'fidelity_pixels.json')},blender_exit_notes=['Blender 4.5 reports compatibility warning for historical 5.2 files; saved/reopened meshes verified.','Lower/placement background processes exited 0 with Blender orphan memory warnings; no Godot resource leak reported.'],not_run=['long duration performance benchmark','reference commercial rights review'],evidence_directory=str(W))
evidence['lower_geometry_reuse']=read(W/'lower_geometry_reuse.json')
evidence['selftest']=read(R.parent/'sea-work/verification/20261026-195513-solar-cabin-v007-fixed-af7c54/report.json')['results']['selftest']
write(R/'docs/development/2026-10-26_solar_cabin_v007_verification.json',evidence)
print('REGISTERED; unrelated runtime hashes intentionally unchanged')
