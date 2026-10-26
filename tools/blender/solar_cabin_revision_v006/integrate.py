from pathlib import Path
import json
R=Path(__file__).resolve().parents[3];G=R/'godot';D=R/'art_source/scenes/sunny_bloom_retreat/v006/export/v001';L=R/'art_source/scenes/bloom_lower_building/v001/export/v001'
def js(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
for directory,kit in [(D,'solar_cabin'),(L,'bloom_lower_building')]:
 report=json.loads((directory/'export_manifest.json').read_text())
 for e in report['components']:
  p=G/f'scenes/components/{kit}/{e["key"]}.tscn';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{e['glb'].removeprefix('godot/')}" id="visual"]
[node name="{e['name']}" type="Node3D"]
script = ExtResource("bind")
metadata/asset_id = "{e['asset_id']}"
[node name="Visual" parent="." instance=ExtResource("visual")]
''');e['prefab']=str(p.relative_to(R))
 js(directory/'export_manifest.json',report)
 js(G/f'assets/models/facilities/{kit}/revision_metrics.json',{'expanded_triangles_after':report['expanded_triangles_after']})
p=G/'src/world/sunny_bloom_visual.gd';s=p.read_text().replace('const DATA = "res://assets/models/facilities/solar_cabin/instances.json"','@export_file("*.json") var instance_data_path: String = "res://assets/models/facilities/solar_cabin/instances.json"\n@export_dir var component_directory: String = "res://scenes/components/solar_cabin"').replace('get_file_as_string(DATA)','get_file_as_string(instance_data_path)').replace('load("res://scenes/components/solar_cabin/%s.tscn" % key)','load(component_directory+"/%s.tscn" % key)');p.write_text(s)
p=G/'scenes/facilities/solar_cabin_submerged_base.tscn';p.write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://src/world/sunny_bloom_visual.gd" id="visual"]
[node name="太阳能木屋-海下基座" type="Node3D"]
script = ExtResource("visual")
instance_data_path = "res://assets/models/facilities/bloom_lower_building/instances.json"
component_directory = "res://scenes/components/bloom_lower_building"
module_key = "submerged_base"
metadata/asset_id = "SEA-SCENE-BLB-ASSEMBLY"
metadata/asset_version = "1.0"
''')
p=G/'tests/test_solar_cabin_asset.gd';s=p.read_text().replace('component_ids.size()==47,"47 active','component_ids.size()==45,"45 active').replace('["foundation","pier","vine","palm","deck_tile"]','["foundation","pier","vine","palm","deck_tile","sail","canopy_hook"]')
a=s.index('\tfor node in descendants(base):');b=s.index('\n\tvar salvage:',a)
s=s[:a]+'''\tvar lower_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/bloom_lower_building/instances.json"))
	var lower_metrics: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/bloom_lower_building/revision_metrics.json"))
	var lower_ids := {};var lower_triangles := 0;var lower_instances := 0;var slabs := 0
	var lower_bounds := AABB();var lower_first := true
	for node in descendants(base):
		check(not node is MeshInstance3D,"no legacy submerged merged mesh remains")
		if not node is MultiMeshInstance3D:continue
		var mm: MultiMesh=node.multimesh;var key: String=node.get_meta("asset_component")
		lower_ids[key]=true;lower_triangles+=triangle_count(mm.mesh)*mm.instance_count;lower_instances+=mm.instance_count
		if key=="floor_slab":slabs=mm.instance_count
		for i in mm.instance_count:
			var box: AABB=mm.get_instance_transform(i)*mm.mesh.get_aabb()
			lower_bounds=box if lower_first else lower_bounds.merge(box);lower_first=false
			check(box.end.y<=1.461,"new base below upper ground deck")
			if key=="roof_slab":check(absf(box.end.y-1.46)<.002,"new base roof meets wood deck underside")
		for si in mm.mesh.get_surface_count():
			var mat: ShaderMaterial=mm.mesh.surface_get_material(si)
			check(mat!=null and mat.get_shader_parameter("palette").resource_path=="res://assets/textures/shared/sea_cozy_8x8_512.png","new base shared palette")
	check(slabs==7,"seven storeys in new submerged base")
	check(lower_instances==lower_data.instances.size(),"new base instance manifest matches")
	check(lower_triangles==int(lower_metrics.expanded_triangles_after),"new base triangle count matches optimized export")
	check(lower_ids.has("facade_bay") and lower_ids.has("blue_column"),"new stepped window bays and structural columns loaded")
''' +s[b:]
s=s.replace('"component_count":component_ids.size(),','"lower_components":lower_ids.size(),"lower_instances":lower_instances,"lower_triangles":lower_triangles,"lower_bounds_min":[lower_bounds.position.x,lower_bounds.position.y,lower_bounds.position.z],"lower_bounds_size":[lower_bounds.size.x,lower_bounds.size.y,lower_bounds.size.z],"component_count":component_ids.size(),')
s=s.replace('await shot("context",','await shot("lower",Vector3(5,-6,1.6),43.0,Vector3(-.7,.18,.8))\n\t\tawait shot("context",');p.write_text(s)
# Standalone loader verifies both component families, preserving all existing checks.
p=G/'tests/test_solar_components.gd';s=p.read_text();s=s.replace('for e in data.instances:keys[e.component]=true','for e in data.instances:keys["solar_cabin/"+e.component]=true\n\tvar lower: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/bloom_lower_building/instances.json"))\n\tfor e in lower.instances:keys["bloom_lower_building/"+e.component]=true').replace('res://scenes/components/solar_cabin/%s.tscn','res://scenes/components/%s.tscn');p.write_text(s)
print('Integrated v006 upper and new seven-storey lower; navigation/landing transforms unchanged.')
