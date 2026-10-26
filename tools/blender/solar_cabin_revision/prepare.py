from pathlib import Path
import json,shutil,hashlib
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v004';W=R.parent/'sea-work/solar_cabin_revision_v004';B=W/'before';W.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
paths=[R/'godot/scenes/facilities',R/'godot/scenes/components/solar_cabin',R/'godot/assets/models/facilities/solar_cabin',R/'godot/assets/materials/solar_cabin',R/'godot/scenes/zones/zone1_home_harbor.tscn',R/'godot/assets/data/zones.json',R/'godot/assets/data/build_sites.json',R/'godot/assets/data/gather_spots.json',R/'godot/assets/baked/shore.json',R/'godot/src/world/sunny_bloom_visual.gd',R/'godot/shaders/sunny_palette.gdshader',R/'godot/shaders/sunny_palette_gloss.gdshader',R/'assets/registry',R/'godot/tests/test_solar_cabin_asset.gd',R/'godot/tests/test_solar_components.gd']
assert not (B/'manifest.json').exists(),'Do not overwrite before snapshot'
records=[]
for path in paths:
 for p in sorted(path.rglob('*')) if path.is_dir() else [path]:
  if not p.is_file():continue
  dest=B/p.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest);assert sha(p)==sha(dest);records.append({'path':str(p.relative_to(R)),'sha256':sha(p)})
(B/'manifest.json').write_text(json.dumps(records,indent=2))
D.mkdir(parents=True,exist_ok=True)
p=json.loads((R/'art_source/scenes/sunny_bloom_retreat/v003/component_plan.json').read_text());p['version']='v004';p['status']='frozen_before_geometry';p['revision_note']='用户七项修订：全区1.5倍，移除灰承台和藤蔓/裂叶植物，后部水泥、灰封顶、宽窗、扩大前房，空平台与桥分开且异色。';p['source_policy']='Only derive current sunny_bloom_retreat/v003. Preserve v003 and 0.1 backups.'
p['layout_revision']={'assembly_scale_over_v003':1.5,'scale_pivot_blender':[0,0,.68],'roof_room_scale_xy':[1.12,1.42],'roof_room_hinge_blender':[1.02,-.40],'front_platform_clear':True,'platform_color':'wine red via berry palette swatch + material hue/value correction','bridge_color':'wood_light','runtime_deck_y':2.15,'parts':['rear_building','solar_room','front_platform','bridge']}
p['references']=[]
for name in ['df680c7f-c482-45f6-8b04-78e2ed2a34cb','01dc6530-7896-40bd-9b57-9513af0f0503','f74329d6-e57b-421f-a3fe-734dd1b95fef','c3fd2402-3d06-4b6e-b2da-ef38a86b7941','b498a8e8-bc03-428b-8207-c5615db36304','43ee737f-414f-43e8-a612-d2fec8b81693']:
 src=Path('/var/folders/m6/jk1g96896k79k8kzh51m4hvc0000gn/T')/f'codex-clipboard-{name}.png';out=D/f'reference_{len(p["references"])+1}.png';shutil.copy2(src,out);p['references'].append({'path':str(out.relative_to(R)),'sha256':sha(out)})
p['reference']=p['references'][0]['path'];p['reference_sha256']=p['references'][0]['sha256']
removed={'foundation','pier','deck_tile','vine','palm','sofa','table','stool','umbrella','cooler','vase','bottle','mat','bollard'}
p['components']=[c for c in p['components'] if c['key'] not in removed]
for key,name in [('platform_board','前方平台-酒红横向整板'),('concrete_slab','后部建筑-水泥地坪')]:
 p['components'].append(dict(key=key,name=name,asset_id='SEA-SCENE-SBR-'+key.upper().replace('_','-'),category='structure',family=key,origin='bottom_center',front_axis='-Y',triangle_budget=500))
for c in p['components']:
 if c['key']=='dock_board':c['name']='栈桥-暖木横向整板'
 if c['key']=='narrow_window':c['name']='后部建筑-加宽前窗'
p['component_limit']=50;p['scene_triangle_limit']=None
(D/'component_plan.json').write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
(W/'protected_sources.json').write_text(json.dumps({str(x.relative_to(R)):sha(x) for x in [R/'art_source/scenes/sunny_bloom_retreat/v003/sunny_bloom_retreat.blend',R/'art_source/shared/palettes/sea_cozy_8x8_512.png']},indent=2))
print('Snapshot',len(records),'files; frozen plan',len(p['components']),'components')
