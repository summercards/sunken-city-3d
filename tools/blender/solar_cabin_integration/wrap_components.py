# -*- coding: utf-8 -*-
from pathlib import Path
import json
R=Path(__file__).resolve().parents[3];G=R/'godot';D=R/'art_source/scenes/sunny_bloom_retreat/v003/export/v001';report=json.loads((D/'export_manifest.json').read_text())
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
write(G/'src/world/sunny_palette_binding.gd','''@tool
extends Node3D
const MATERIALS = {
 "Matte": preload("res://assets/materials/solar_cabin/sunny_matte.tres"),
 "Metal": preload("res://assets/materials/solar_cabin/sunny_metal.tres"),
 "Gloss": preload("res://assets/materials/solar_cabin/sunny_gloss.tres"),
 "Emission": preload("res://assets/materials/solar_cabin/sunny_emission.tres")}
func _ready() -> void:
 bind(self)
func bind(node: Node) -> void:
 if node is MeshInstance3D:
  for surface in node.mesh.get_surface_count():
   var m: Material=node.mesh.surface_get_material(surface)
   var role: String="Matte"
   if m!=null:
    for name in MATERIALS:
     if name in m.resource_name:role=name
   node.set_surface_override_material(surface,MATERIALS[role])
 for c in node.get_children():bind(c)
''')
for e in report['components']:
 p=G/f'scenes/components/solar_cabin/{e["key"]}.tscn'
 write(p,f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{e['glb'].removeprefix('godot/')}" id="visual"]
[node name="{e['key']}" type="Node3D"]
script = ExtResource("bind")
metadata/asset_id = "{e['asset_id']}"
[node name="Visual" parent="." instance=ExtResource("visual")]
''');e['prefab']=str(p.relative_to(R))
for e in report['legacy']:
 if e['key']=='salvage_station':e['prefab']='godot/scenes/facilities/salvage_station.tscn';continue
 p=G/f'scenes/components/solar_cabin/{e["key"]}.tscn'
 write(p,f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://src/world/legacy_facility_materials.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{e['glb'].removeprefix('godot/')}" id="visual"]
[node name="{e['key']}" type="Node3D"]
script = ExtResource("bind")
[node name="Visual" parent="." instance=ExtResource("visual")]
''');e['prefab']=str(p.relative_to(R))
base=G/'scenes/facilities/solar_cabin_submerged_base.tscn';s=base.read_text()
for e in report['legacy']:
 if e['key']=='salvage_station':continue
 s=s.replace('res://'+e['glb'].removeprefix('godot/'),'res://'+e['prefab'].removeprefix('godot/'))
base.write_text(s)
p=G/'src/world/sunny_bloom_visual.gd';s=p.read_text();s=s.replace('"res://assets/models/facilities/solar_cabin/components/%s/%s.glb" % [key,key]','"res://scenes/components/solar_cabin/%s.tscn" % key');p.write_text(s)
write(G/'scenes/facilities/solar_cabin.tscn','''[gd_scene load_steps=3 format=3]
[ext_resource type="PackedScene" path="res://scenes/facilities/solar_cabin_surface.tscn" id="surface"]
[ext_resource type="PackedScene" path="res://scenes/facilities/solar_cabin_submerged_base.tscn" id="base"]
[node name="太阳能木屋" type="Node3D"]
metadata/asset_id = "SEA-REF-FACILITY-SOLAR-CABIN"
[node name="太阳能木屋-海上区域" parent="." instance=ExtResource("surface")]
[node name="太阳能木屋-海下基座" parent="." instance=ExtResource("base")]
''')
zone=G/'scenes/zones/zone1_home_harbor.tscn';s=zone.read_text();s=s.replace('path="res://scenes/facilities/solar_cabin_surface.tscn" id="sunny_surface"','path="res://scenes/facilities/solar_cabin.tscn" id="sunny_surface"');s=s.replace('[ext_resource type="PackedScene" path="res://scenes/facilities/solar_cabin_submerged_base.tscn" id="home_base"]\n','');s=s.replace('[node name="太阳能木屋-海上区域" parent="Models" instance=ExtResource("sunny_surface")]','[node name="太阳能木屋" parent="Models" instance=ExtResource("sunny_surface")]');s=s.replace('[node name="太阳能木屋-海下基座" parent="Models" instance=ExtResource("home_base")]\n','')
import re
s=re.sub(r'load_steps=\d+','load_steps='+str(len(re.findall(r'^\[ext_resource|^\[sub_resource',s,flags=re.M))+1),s,count=1);zone.write_text(s)
(D/'export_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('49 source component prefabs and 4 base prefabs registered in export manifest')
