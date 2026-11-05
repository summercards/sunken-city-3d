"""Register only this original vegetation kit; retain unrelated hash drift."""
import json,hashlib,sys,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=R.parent/'sea-work/vegetation_implementation_20261105'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p,v):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report_path=Path(sys.argv[1]).resolve();runtime=read(report_path)
for name in ['vegetation-contract','visual-vegetation','rooftop-ranch']:
 assert runtime['results'][name]['passed'],name
source=read(W/'source_report.json');assert source['passed']
index_path=R/'assets/registry/ledger_index.json';index_before=index_path.read_bytes();index=read(index_path)
route='assets/registry/ledgers/vegetation.json'
index['domains']['vegetation']={'ledger':route,'asset_key':'assets'}
other_ids={row['asset_id'] for domain,r in index['domains'].items() if domain!='vegetation' for row in read(R/r['ledger'])[r['asset_key']]}
rows=[];audit=[]
for s in source['assets']:
 k=s['key'];aid=s['asset_id'];assert aid not in other_ids
 for file_field,hash_field in [('source','source_sha256'),('optimized_source','optimized_sha256'),('glb','glb_sha256')]:assert sha(R/s[file_field])==s[hash_field]
 b=(R/s['glb']).read_bytes();d=json.loads(b[20:20+struct.unpack_from('<I',b,12)[0]])
 assert not d.get('images') and not d.get('textures')
 primitive=d['meshes'][0]['primitives'][0];assert {'POSITION','NORMAL','TEXCOORD_0','COLOR_0'}<=set(primitive['attributes'])
 triangles=d['accessors'][primitive['indices']]['count']//3;assert triangles==s['after']['triangles']
 prefab=f'godot/scenes/components/vegetation/{k}.tscn'
 manifest=f'art_source/vegetation/v001/components/{k}/asset_manifest.json'
 consumers=['solar_cabin','rooftop_ranch'] if k not in ['mound_spread','pink_flower','turf_pad'] else ['rooftop_ranch'] if k=='mound_spread' else ['solar_cabin']
 row=dict(asset_id=aid,name=s['label'],domain='vegetation',suite='shared_vegetation',version='v001',scope='shared',category=s['profile'],source=s['source'],source_sha256=s['source_sha256'],optimized_source=s['optimized_source'],optimized_sha256=s['optimized_sha256'],manifest=manifest,glb=s['glb'],glb_sha256=s['glb_sha256'],runtime_path=prefab,runtime_sha256=sha(R/prefab),prefab=prefab,stage='runtime_and_visual_verified',license='original_procedural_geometry',reference_provenance='user_video_origin_unverified; aesthetic reference only, no copied mesh/texture',palette='art_source/shared/palettes/sea_cabin_timber_8x8_512.png',wind_contract=1,profile=f'godot/assets/materials/vegetation/{s["profile"]}.tres',triangles=triangles,bounds_blender=s['after']['bounds_blender'],consumers=consumers,consumer_features=['SEA-AMBIENT','SEA-ASSET'],collision=False,water_layer='surface',water_layer_role='none',verification=dict(source='passed',import='passed',visual='passed',performance='measured_on_RTX_4060_Ti_not_universal_60fps',evidence=[str(report_path),str(W/'source_report.json'),'docs/development/2026-11-05_vegetation_implementation.md']))
 rows.append(row);write(R/manifest,dict(row,asset_ledger=route+'#'+aid,production_report='production_report.json',origin='bottom_center',uv0='PaletteUV',color0='linear WindData RGBA; root-bend, detail, phase, AO',lod='Godot imported mesh LOD plus patch density LOD; no duplicate asset geometry'))
 audit.append(dict(asset_id=aid,glb_attributes=list(primitive['attributes']),triangles=triangles,embedded_images=0))
write(R/route,dict(schema_version=1,domain='vegetation',owner_feature='SEA-ASSET',note='One row per reusable asset; layouts reference catalog keys mapped to these AssetIDs. Source/reference/visual/performance status separated.',assets=rows))
assert index_path.read_bytes()==index_before,'Concurrent route edit'
write(index_path,index)
source_index=read(R/'assets/registry/current_source_index.json')
source_index['sources']=[{key:row[key] for key in ['asset_id','source','source_sha256','manifest']} for route_row in index['domains'].values() for row in read(R/route_row['ledger'])[route_row['asset_key']]]
write(R/'assets/registry/current_source_index.json',source_index)

# Only new files and reviewed runtime consumer files. Never refresh unrelated sources.
inventory_path=R/index['runtime_inventory'];before=inventory_path.read_bytes();inv=read(inventory_path)
paths=set()
for base in ['godot/assets/models/vegetation','godot/assets/materials/vegetation','godot/scenes/components/vegetation','godot/shaders/vegetation','godot/data/vegetation']:
 paths.update(p.relative_to(R).as_posix() for p in (R/base).rglob('*') if p.is_file() and p.suffix in ['.glb','.tscn','.tres','.json','.gdshader','.gdshaderinc'])
reviewed={'godot/scenes/facilities/rooftop_ranch.tscn','godot/scenes/facilities/solar_cabin_surface.tscn','godot/scenes/main.tscn','godot/assets/materials/shader_param_contract.json'}
changed=[]
for row in inv['resources']:
 if row['path'] in paths|reviewed:
  p=R/row['path'];old=row['sha256'];row.update(bytes=p.stat().st_size,sha256=sha(p));changed.append(dict(path=row['path'],previous_sha256=old,sha256=row['sha256']))
existing={r['path'] for r in inv['resources']}
owners={r['runtime_path']:r['asset_id'] for r in rows}|{r['glb']:r['asset_id'] for r in rows}
for p in sorted(paths-existing):
 inv['resources'].append(dict(path=p,bytes=(R/p).stat().st_size,sha256=sha(R/p),asset_id=owners.get(p,'SEA-AMBIENT-shared-vegetation'),status='vegetation_runtime_verified'))
inv['resources'].sort(key=lambda x:x['path']);assert inventory_path.read_bytes()==before,'Concurrent inventory edit';write(inventory_path,inv)
write(W/'registration_report.json',dict(passed=True,asset_count=len(rows),gltf_audit=audit,updated_existing_runtime_hashes=changed,unrelated_hashes_preserved=True))
print('Vegetation: registered 8 independent assets; unrelated drift preserved.')
