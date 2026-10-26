import json,shutil,re
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v007/export/v001';G=R/'godot'
report=json.loads((D/'export_manifest.json').read_text())
for e in report['components']:
 p=G/f'scenes/components/solar_cabin/{e["key"]}.tscn'
 if not p.exists():
  p.write_text(f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{e['glb'].removeprefix('godot/')}" id="visual"]
[node name="{e['name']}" type="Node3D"]
script = ExtResource("bind")
metadata/asset_id = "{e['asset_id']}"
[node name="Visual" parent="." instance=ExtResource("visual")]
''',encoding='utf-8')
 e['prefab']=p.relative_to(R).as_posix()
 # Imported component paths and existing UIDs remain stable.
 imp=R/(e['glb']+'.import')
 if imp.exists():
  text=imp.read_text(encoding='utf-8');text=text.replace('meshes/generate_lods=true','meshes/generate_lods=false').replace('gltf/embedded_image_handling=1','gltf/embedded_image_handling=0');imp.write_text(text,encoding='utf-8')
(D/'export_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(G/'assets/models/facilities/solar_cabin/revision_metrics.json').write_text(json.dumps({'expanded_triangles_after':report['expanded_triangles_after']}))
shutil.copy2(R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.png',G/'assets/textures/shared/sea_cabin_muted_8x8_512.png')
for p in (G/'assets/materials/solar_cabin').glob('*.tres'):
 s=p.read_text(encoding='utf-8').replace('sea_cozy_8x8_512.png','sea_cabin_muted_8x8_512.png');p.write_text(s,encoding='utf-8')
for name in ['test_solar_components.gd','test_solar_cabin_asset.gd']:
 p=G/'tests'/name;s=p.read_text(encoding='utf-8').replace('sea_cozy_8x8_512.png','sea_cabin_muted_8x8_512.png').replace('component_ids.size()==45,"45 active','component_ids.size()==49,"49 active')
 s=s.replace('if key in ["platform_board","dock_board"]:', 'if key.begins_with("platform_board") or key.begins_with("dock_board"):')
 p.write_text(s,encoding='utf-8')
print('Integrated 49 components; retained all hand-edited facility and zone scenes.')
