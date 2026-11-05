"""Register v002 approved scope, preserving every unrelated source/runtime baseline."""
from pathlib import Path
import json,hashlib,sys,struct
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v002';W=R.parent/'sea-work/vegetation_soft_20261105'
assert not (R/'art_source/vegetation/v003/component_plan.json').exists(), 'v002 is historical; use register_meadow.py.'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p,v):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report_path=Path(sys.argv[1]).resolve();run=read(report_path)
for key in ['vegetation-contract','visual-vegetation','visual-vegetation-performance']:
 assert run['results'][key]['passed'],key
sources=read(W/'source_report.json');texture=read(D/'texture_production.json');assert sources['passed']
rows=[];route='assets/registry/ledgers/vegetation.json'
evidence=[str(report_path),'docs/development/2026-11-05_vegetation_soft_cards.md']
for source in sources['assets']:
 for k,h in [('source','source_sha256'),('optimized_source','optimized_sha256'),('glb','glb_sha256')]:assert sha(R/source[k])==source[h]
 key=source['key'];aid=source['asset_id'];b=(R/source['glb']).read_bytes();d=json.loads(b[20:20+struct.unpack_from('<I',b,12)[0]])
 assert not d.get('images')
 primitive=d['meshes'][0]['primitives'][0];assert {'POSITION','NORMAL','TEXCOORD_0','COLOR_0'}<=set(primitive['attributes'])
 assert d['accessors'][primitive['indices']]['count']//3==source['triangles']
 prefab=f'godot/scenes/components/vegetation/{key}.tscn';manifest=f'art_source/vegetation/v002/components/{key}/asset_manifest.json'
 row=dict(source,asset_id=aid,name='柔软草叶贴片簇' if key=='grass_soft' else '细碎苔藓贴片',domain='vegetation',suite='soft_botanical_cards',version='v002',category='textured_vegetation',scope='shared',manifest=manifest,runtime_path=prefab,runtime_sha256=sha(R/prefab),prefab=prefab,stage='runtime_verified_user_visual_review_pending',license='original_carrier_geometry',dependencies=['SEA-TEX-VEGETATION-SOFT-ATLAS'],consumers=['solar_cabin'],consumer_features=['SEA-AMBIENT','SEA-ASSET'],water_layer='surface',water_layer_role='none',collision=False,wind_contract=2,material=f'godot/assets/materials/vegetation/{key}.tres',uv_exception='User explicitly requested botanical color/alpha UV0 instead of palette cells',verification=dict(source='reopened_and_checked',runtime='passed',visual='native_frames_reviewed',user_art_acceptance='pending',performance='measured_RTX4060Ti_1280x800',evidence=evidence))
 rows.append(row);write(R/manifest,dict(row,asset_ledger=route+'#'+aid))
assert sha(R/texture['source'])==texture['source_sha256'] and sha(R/texture['runtime'])==texture['runtime_sha256']
aid='SEA-TEX-VEGETATION-SOFT-ATLAS';manifest='art_source/vegetation/v002/texture_manifest.json'
row=dict(asset_id=aid,name='Image-2草叶与苔藓RGBA图集',domain='vegetation',suite='soft_botanical_cards',version='v002',category='color_alpha_texture',scope='shared',source=texture['source'],source_sha256=texture['source_sha256'],processed_source='art_source/vegetation/v002/soft_atlas.png',processed_sha256=sha(D/'soft_atlas.png'),manifest=manifest,runtime_path=texture['runtime'],runtime_sha256=texture['runtime_sha256'],stage='runtime_verified_user_visual_review_pending',license='generated_image_output_terms_not_audited',provenance=dict(model='gpt-image-2',skill='sofunny-image',mode='reference_image_edit',reference_sha256=texture['reference_sha256'],prompt='art_source/vegetation/v002/texture_brief.txt',processing='art_source/vegetation/v002/texture_production.json'),consumers=['solar_cabin'],consumer_features=['SEA-AMBIENT','SEA-ASSET'],verification=dict(alpha='RGBA 0..255, internal and edge transparency verified',visual='native_game_frames_reviewed',user_art_acceptance='pending',evidence=evidence))
rows.append(row);write(R/manifest,dict(row,asset_ledger=route+'#'+aid))
index_path=R/'assets/registry/ledger_index.json';before=index_path.read_bytes();index=read(index_path)
other_ids={row['asset_id'] for domain,r in index['domains'].items() if domain!='vegetation' for row in read(R/r['ledger'])[r['asset_key']]}
assert not other_ids.intersection(r['asset_id'] for r in rows)
write(R/route,dict(schema_version=1,domain='vegetation',owner_feature='SEA-ASSET',note='v002 current scope only. v001 solid vegetation rejected, not production assets.',assets=rows))
index['domains']['vegetation']=dict(ledger=route,asset_key='assets');assert index_path.read_bytes()==before;write(index_path,index)
p=R/'assets/registry/current_source_index.json';src=read(p)
src['sources']=[{k:row[k] for k in ['asset_id','source','source_sha256','manifest']} for r in index['domains'].values() for row in read(R/r['ledger'])[r['asset_key']]];write(p,src)
p=R/index['runtime_inventory'];before=p.read_bytes();inventory=read(p)
new_paths=set()
for folder in ['godot/assets/models/vegetation','godot/assets/materials/vegetation','godot/scenes/components/vegetation','godot/assets/textures/vegetation','godot/data/vegetation']:
 new_paths.update(x.relative_to(R).as_posix() for x in (R/folder).rglob('*') if x.is_file() and x.suffix in ['.glb','.tres','.tscn','.png','.json'])
new_paths.update(['godot/shaders/vegetation/soft_cards.gdshader','godot/shaders/vegetation/wind.gdshaderinc'])
owners={r['runtime_path']:r['asset_id'] for r in rows}|{r['glb']:r['asset_id'] for r in rows if 'glb' in r}
saved={r['path']:r for r in inventory['resources']}
changes=[]
for path in sorted(new_paths):
 row=dict(path=path,bytes=(R/path).stat().st_size,sha256=sha(R/path),asset_id=owners.get(path,'SEA-AMBIENT-SOFT-VEGETATION'),status='runtime_verified_visual_review_pending')
 if path in saved:changes.append(dict(path=path,previous_sha256=saved[path]['sha256'],sha256=row['sha256']));saved[path].update(row)
 else:inventory['resources'].append(row)
assert p.read_bytes()==before;inventory['resources'].sort(key=lambda r:r['path']);write(p,inventory)
write(W/'registration_report.json',dict(passed=True,asset_count=3,assets=[r['asset_id'] for r in rows],updated_own_resources=changes,unrelated_hashes_untouched=True))
print('SOFT_ASSETS_REGISTERED: 2 independent plants + 1 shared texture')
