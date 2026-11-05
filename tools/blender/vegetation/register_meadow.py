"""Advance the shared grass version and add card mounds without accepting unrelated drift."""
from pathlib import Path
import json,hashlib,struct,sys
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v003';W=R.parent/'sea-work/vegetation_meadow_20261105'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p,v):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report=Path(sys.argv[1]).resolve();runtime=read(report)
for name in ['vegetation-contract','visual-vegetation','visual-vegetation-performance','rooftop-ranch','water-layer','minimum-loop']:assert runtime['results'][name]['passed'],name
source=read(W/'source_report.json');texture=read(D/'texture_production.json');assert source['passed']
index=read(R/'assets/registry/ledger_index.json');route=index['domains']['vegetation']['ledger'];book_path=R/route;before=book_path.read_bytes();book=read(book_path);by_id={r['asset_id']:r for r in book['assets']}
evidence=[str(report),'docs/development/2026-11-05_vegetation_meadow.md'];updates={}
for s in source['assets']:
 aid=s['asset_id'];key=s['key']
 for path,hashkey in [('source','source_sha256'),('optimized_source','optimized_sha256'),('glb','glb_sha256')]:assert sha(R/s[path])==s[hashkey]
 b=(R/s['glb']).read_bytes();gl=json.loads(b[20:20+struct.unpack_from('<I',b,12)[0]]);assert not gl.get('images')
 pr=gl['meshes'][0]['primitives'][0];assert {'POSITION','NORMAL','TEXCOORD_0','COLOR_0'}<=set(pr['attributes']);assert gl['accessors'][pr['indices']]['count']//3==s['triangles']
 manifest=f'art_source/vegetation/v003/components/{key}/asset_manifest.json';prefab=f'godot/scenes/components/vegetation/{key}.tscn'
 previous=[]
 if aid in by_id:
  old=by_id[aid];previous=list(old.get('previous_sources',[]))
  if old['version']!='v003':previous.append({k:old[k] for k in ['version','source','source_sha256','optimized_source','optimized_sha256','glb_sha256','manifest']})
 row=dict(s,name='宽叶柔软草簇' if key=='grass_soft' else '层叠面片草堆',domain='vegetation',suite='soft_botanical_cards',scope='shared',category='textured_vegetation',manifest=manifest,prefab=prefab,runtime_path=prefab,runtime_sha256=sha(R/prefab),material=f'godot/assets/materials/vegetation/{key}.tres',dependencies=['SEA-TEX-VEGETATION-MEADOW-ATLAS'],consumers=['solar_cabin','rooftop_ranch'] if key=='grass_soft' else ['rooftop_ranch'],consumer_features=['SEA-AMBIENT','SEA-ASSET'],previous_sources=previous,stage='runtime_verified_user_visual_review_pending',license='original_carrier_geometry',water_layer='surface',water_layer_role='none',collision=False,wind_contract=3,verification=dict(source='reopened_and_verified',runtime='passed',visual='near_default_far_and_motion_reviewed',user_art_acceptance='pending',performance='measured_RTX4060Ti_1280x800',evidence=evidence))
 updates[aid]=row;write(R/manifest,dict(row,asset_ledger=route+'#'+aid))
aid='SEA-TEX-VEGETATION-MEADOW-ATLAS';manifest='art_source/vegetation/v003/texture_manifest.json'
for p,h in [('source','source_sha256'),('processed_source','processed_sha256'),('runtime','runtime_sha256')]:assert sha(R/texture[p])==texture[h]
row=dict(asset_id=aid,name='宽叶草地与草堆Image-2图集',domain='vegetation',version='v003',suite='soft_botanical_cards',scope='shared',category='color_alpha_texture',source=texture['source'],source_sha256=texture['source_sha256'],processed_source=texture['processed_source'],processed_sha256=texture['processed_sha256'],manifest=manifest,runtime_path=texture['runtime'],runtime_sha256=texture['runtime_sha256'],license='generated_image_output_terms_not_audited',stage='runtime_verified_user_visual_review_pending',consumers=['solar_cabin','rooftop_ranch'],consumer_features=['SEA-AMBIENT','SEA-ASSET'],provenance=dict(model='gpt-image-2',prompt='art_source/vegetation/v003/texture_brief.txt',processing='art_source/vegetation/v003/texture_production.json',reference='user video frame plus previous fine atlas for a broader-leaf revision'),verification=dict(alpha='RGBA 0..255, transparent leaf gaps',visual='native_game_frames_reviewed',user_art_acceptance='pending',evidence=evidence))
updates[aid]=row;write(R/manifest,dict(row,asset_ledger=route+'#'+aid))
other={r['asset_id'] for domain,route_row in index['domains'].items() if domain!='vegetation' for r in read(R/route_row['ledger'])[route_row['asset_key']]};assert not other.intersection(updates)
book['assets']=[updates.get(r['asset_id'],r) for r in book['assets']]+[r for aid,r in updates.items() if aid not in by_id];book['note']='v003 broad meadow and rooftop mounds. v002 moss retained; grass history preserved. v001 solid candidates rejected.'
assert book_path.read_bytes()==before;write(book_path,book)
p=R/'assets/registry/current_source_index.json';data=read(p);data['sources']=[{k:r[k] for k in ['asset_id','source','source_sha256','manifest']} for route_row in index['domains'].values() for r in read(R/route_row['ledger'])[route_row['asset_key']]];write(p,data)
p=R/index['runtime_inventory'];before=p.read_bytes();inv=read(p);saved={r['path']:r for r in inv['resources']}
paths=set()
for folder in ['godot/assets/models/vegetation','godot/assets/materials/vegetation','godot/assets/textures/vegetation','godot/scenes/components/vegetation','godot/data/vegetation','godot/shaders/vegetation']:
 paths.update(p.relative_to(R).as_posix() for p in (R/folder).rglob('*') if p.is_file() and p.suffix in ['.glb','.tres','.png','.tscn','.json','.gdshader','.gdshaderinc'])
owners={r['runtime_path']:r['asset_id'] for r in updates.values()}|{r['glb']:r['asset_id'] for r in updates.values() if 'glb' in r};changes=[]
for path in sorted(paths):
 row=dict(path=path,sha256=sha(R/path),bytes=(R/path).stat().st_size,asset_id=owners.get(path,saved.get(path,{}).get('asset_id','SEA-AMBIENT-SOFT-VEGETATION')),status='runtime_verified_visual_review_pending')
 if path in saved:
  if row['sha256']!=saved[path]['sha256']:changes.append(dict(path=path,before=saved[path]['sha256'],after=row['sha256']))
  saved[path].update(row)
 else:inv['resources'].append(row)
assert p.read_bytes()==before;inv['resources'].sort(key=lambda r:r['path']);write(p,inv)
write(W/'registration_report.json',dict(passed=True,updated=list(updates),all_vegetation_assets=len(book['assets']),updated_own_runtime_hashes=changes,unrelated_hashes_preserved=True))
print('MEADOW_REGISTERED: grass v003, new mound and broad atlas; v002 source and moss preserved')
