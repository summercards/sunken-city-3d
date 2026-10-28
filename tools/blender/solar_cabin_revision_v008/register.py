"""Advance only the reviewed cabin assets and known runtime outputs."""
import json,hashlib,os
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v008';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v008'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
protected=read(W/'protected_sources.json');assert all(sha(R/p)==h for p,h in protected.items())
checks={}
for name in ['20261028-103359-thin-planks-dayparts-3b8259','20261028-103938-dayparts-delivery-66895e','20261028-103658-thin-deck-integration-2986ba','20261028-103730-thin-deck-all-routes-ee9ebe','20261028-104445-thin-plank-final-pivots-5fd6a0']:
 report=read(R.parent/'sea-work/verification'/name/'report.json')
 for k,v in report['results'].items():
  if v['passed']:checks[k]=v
assert all(k in checks for k in ['daylight','visual-cabin-dayparts','visual-solar-cabin','solar-components','surface','minimum-loop','sleep-cycle','visual-plot-shipping'])
route=read(R/'assets/registry/ledger_index.json')['domains']['scenes'];bp=R/route['ledger'];book=read(bp);rows=book[route['asset_key']];lookup={e['asset_id']:e for e in rows};export=read(D/'export/v001/export_manifest.json');cat={e['key']:e for e in read(D/'catalog.json')['components']}
common=dict(version='v008',runtime_version='1.5',stage='runtime_integrated_verified',runtime_verified=True,optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],export_manifest=(D/'export/v001/export_manifest.json').relative_to(R).as_posix(),palette='art_source/shared/palettes/sea_cabin_timber_8x8_512.png')
def put(aid,source,manifest,**kwargs):
 source=Path(source);source=source if source.is_absolute() else R/source;manifest=Path(manifest);manifest=manifest if manifest.is_absolute() else R/manifest
 row=lookup.get(aid)
 if row is None:
  row=dict(asset_id=aid,domain='scenes',license='pending_user_reference_rights_review',scope='scene_local',consumer_features=['SEA-ASSET','SEA-WORLD'],geometry_fingerprint=None);rows.append(row);lookup[aid]=row
 else:
  actual=sha(R/row['source'])
  if actual!=row['source_sha256']:
   owned=read(W/'owned_generated_before_final.json')
   assert owned.get(row['source'])==row['source_sha256'] and '/sunny_bloom_retreat/v008/' in row['source'],'Unexpected source drift '+aid
   assert read(W/'source_verification.json')['passed']
  if row['source']!=source.relative_to(R).as_posix():row.setdefault('previous_sources',[]).append({k:row[k] for k in ['source','source_sha256','manifest','version']})
 row.update(common,source=source.relative_to(R).as_posix(),source_sha256=sha(source),manifest=manifest.relative_to(R).as_posix(),**kwargs)
 write(manifest,dict(row,asset_ledger=route['ledger']+'#'+aid));return row
for e in export['components']:
 c=cat[e['key']];p=R/c['component_source'];e.update(prefab=f'godot/scenes/components/solar_cabin/{e["key"]}.tscn',source_version='v008',runtime_verified=True,triangles_before=sum(o['triangles_before'] for o in e['optimization']),triangles_after=e['exported_triangles'])
 assert sha(R/e['glb'])==e['glb_sha256']
 put(e['asset_id'],p,p.parent/'asset_manifest.json',name=e['name'],category=e['category'],asset_key=e['key'],runtime_path=e['glb'],prefab=e['prefab'],geometry_fingerprint=c['geometry_fingerprint'])
put('SEA-SCENE-SBR-ASSEMBLY',D/'sunny_bloom_retreat.blend',D/'asset_manifest.json',name='太阳能木屋-海上区域',runtime_path='godot/assets/models/facilities/solar_cabin/instances.json',prefab='godot/scenes/facilities/solar_cabin_surface.tscn')
put('SEA-SCENE-SBR-OPTIMIZED',R/export['optimized_source'],D/'export/v001/optimized_asset_manifest.json',name='太阳能木屋-独立优化源',runtime_path=None,prefab=None)
for key in ['rear_building','solar_room','front_platform','bridge']:
 p=D/'modules'/key/(key+'.blend');put('SEA-SCENE-SBR-MODULE-'+key.upper().replace('_','-'),p,p.parent/'asset_manifest.json')
p=D/'export/v001/placement/solar_cabin/solar_cabin_v1.5.blend';put('SEA-REF-FACILITY-SOLAR-CABIN',p,p.parent/'asset_manifest.json',name='太阳能木屋',note='v008 thin 0.22m timber decks, reference warm timber color; current authored base overhang and waterline preserved.')
p=R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png';row=put('SEA-PALETTE-CABIN-TIMBER-64',p,p.parent/'sea_cabin_timber_asset_manifest.json',name='太阳能木屋浮板暖木色板',category='shared_palette',runtime_path='godot/assets/textures/shared/sea_cabin_timber_8x8_512.png',prefab=None);row['license']='original_authored_palette';write(R/row['manifest'],dict(row,asset_ledger=route['ledger']+'#'+row['asset_id']))
write(D/'export/v001/export_manifest.json',export);write(bp,book)
ix=read(R/'assets/registry/current_source_index.json');ix['sources']=[]
for domain in read(R/'assets/registry/ledger_index.json')['domains'].values():
 for row in read(R/domain['ledger'])[domain['asset_key']]:ix['sources'].append({k:row[k] for k in ['asset_id','source','source_sha256','manifest']})
write(R/'assets/registry/current_source_index.json',ix)
allowed={e['glb']:e['asset_id'] for e in export['components']}
allowed.update({'godot/assets/models/facilities/solar_cabin/instances.json':'SEA-SCENE-SBR-ASSEMBLY','godot/assets/models/facilities/solar_cabin/revision_metrics.json':'SEA-SCENE-SBR-ASSEMBLY','godot/assets/textures/shared/sea_cabin_timber_8x8_512.png':'SEA-PALETTE-CABIN-TIMBER-64','godot/assets/data/zones.json':None})
allowed.update({p.relative_to(R).as_posix():'SEA-SCENE-SBR-ASSEMBLY' for p in (R/'godot/assets/materials/solar_cabin').glob('*.tres')})
for path in ['godot/shaders/toon.gdshader','godot/shaders/toon_alpha.gdshader','godot/shaders/toon_common.gdshaderinc','godot/shaders/water.gdshader','godot/shaders/water_absorption.gdshader','godot/shaders/sunny_palette.gdshader']:allowed[path]=None
invp=R/'assets/registry/runtime_resource_inventory.json';inv=read(invp);by={e['path']:e for e in inv['resources']}
for path,aid in allowed.items():
 row=by.get(path)
 if row is None:
  if not path.endswith('.png') and path not in {e['glb'] for e in export['components']}:continue
  row={'path':path,'asset_id':aid};inv['resources'].append(row)
 if row.get('sha256') and row['sha256']!=sha(R/path):row['previous_sha256']=row['sha256']
 row.update(sha256=sha(R/path),bytes=(R/path).stat().st_size,note='Reviewed v008 timber/daypart change')
write(invp,inv)
evidence=dict(protected_sources=protected,source=read(W/'source_verification.json'),edits=read(W/'edit_evidence.json'),reference=read(W/'reference_board_measurement.json'),checks=checks,daypart_pixels=read(W/'daypart_pixel_stats.json'),optimization={'before':export['expanded_triangles_before'],'after':export['expanded_triangles_after']},not_run=['long-duration performance','mobile/Compatibility renderer','reference commercial-rights review'],known_initial_failures=['surface requires --full-world for the retired zones; repeated with that explicit scope and passed.'])
write(R/'docs/development/2026-10-28_thin_cabin_and_dayparts_verification.json',evidence)
print('Registered v008, preserving all unrelated asset hashes.')
