from pathlib import Path
import json,re
R=Path(__file__).resolve().parents[3];G=R/'godot';D=R/'art_source/scenes/sunny_bloom_retreat/v005/export/v001';W=R.parent/'sea-work/solar_cabin_revision_v005';report=json.loads((D/'export_manifest.json').read_text())
def js(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
for e in report['components']:
 p=G/f'scenes/components/solar_cabin/{e["key"]}.tscn';p.write_text(f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{e['glb'].removeprefix('godot/')}" id="visual"]
[node name="{e['name']}" type="Node3D"]
script = ExtResource("bind")
metadata/asset_id = "{e['asset_id']}"
[node name="Visual" parent="." instance=ExtResource("visual")]
''');e['prefab']=str(p.relative_to(R))
# Keep the existing author-owned zone and adjust only the bridge contracts.
zones=json.loads((W/'before/godot/assets/data/zones.json').read_text());z=next(x for x in zones if x['id']=='zone1');land=next(x for x in z['landings'] if x['id']=='main');delta=1.38*1.15
for key in ['boatPark','dockEdge','landStand']:land[key][2]+=delta
walk=next(x for x in z['walk'] if x['id']=='zone1_home_dock');walk['rects'][-1][3]+=delta
js(G/'assets/data/zones.json',zones)
p=G/'scenes/zones/zone1_home_harbor.tscn';s=(W/'before/godot/scenes/zones/zone1_home_harbor.tscn').read_text();a=s.index('[node name="Walk_zone1_home_dock"');b=s.index('[node name="Walk_zone1_salvage"');block=s[a:b];rs=walk['rects'];text='rects = ['+', '.join('Rect2('+', '.join(f'{v:.6f}' for v in [r[0],r[2],r[1]-r[0],r[3]-r[2]])+')' for r in rs)+']';block=re.sub(r'^rects = .*$',text,block,flags=re.M);s=s[:a]+block+s[b:]
def v3(v):return 'Vector3('+', '.join(f'{x:.6f}' for x in v)+')'
a=s.index('[node name="Landing_main"');b=s.index('[node name="Landing_salvage"');block=s[a:b];block=re.sub(r'(\[node name="Landing_main"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3(land['landStand']),block);s=s[:a]+block+s[b:];p.write_text(s)
shore=json.loads((W/'before/godot/assets/baked/shore.json').read_text());shapes=[x for x in shore['shapes'] if x.get('asset_id')=='SEA-SCENE-SBR-ASSEMBLY'];bridge=shapes[-1];bridge['hz']+=delta/2;bridge['z']+=delta/2;js(G/'assets/baked/shore.json',shore)
js(D/'export_manifest.json',report);js(G/'assets/models/facilities/solar_cabin/revision_metrics.json',{'expanded_triangles_after':report['expanded_triangles_after']});js(W/'integration.json',{'version':'1.2','source_revision':'v005','bridge_extension_godot_m':delta,'landings':land,'walk_rects':walk['rects'],'sunroom_right_shift_godot_m':1.4375,'deck_thickness_godot_m':.69})
p=G/'tests/test_solar_cabin_asset.gd';s=p.read_text().replace('component_ids.size()==46,"46 active','component_ids.size()==47,"47 active');p.write_text(s)
print('Updated 47 wrappers, 1.587m extended bridge landing/walk/shore; other placement unchanged')
