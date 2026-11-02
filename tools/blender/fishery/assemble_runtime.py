"""Initialize new component wrappers and a new editable fishery assembly only."""
import json,math,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/wild_fishery/v001'
if (R/'godot/scenes/facilities/wild_fishery.tscn').exists():
 raise SystemExit('Initialization only: the fishery scene already exists. Preserve its manual layout; use an external generation candidate and review changes individually.')
cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];layout=json.loads((D/'component_instances.json').read_text(encoding='utf-8'));origin=layout['world_origin_godot']
def put(p,text):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8')
for e in cat:
 key=e['key'];glb=R/'godot/assets/models/fishery'/key/(key+'.glb');runtime='res://'+glb.relative_to(R/'godot').as_posix()
 imp=glb.with_suffix('.glb.import')
 text=f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"

[deps]
source_file="{runtime}"

[params]
nodes/root_scale=1.0
nodes/apply_root_scale=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=false
import_script/path="res://tools/fishery_palette_import.gd"
gltf/embedded_image_handling=0
'''
 put(imp,text)
 wrapper=R/'godot/scenes/components/fishery'/(key+'.tscn')
 put(wrapper,f'''[gd_scene format=3]
[ext_resource type="PackedScene" path="{runtime}" id="visual"]
[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]
[node name="{key}" type="Node3D"]
metadata/asset_id = "{e['asset_id']}"
metadata/asset_version = "v001"
metadata/component_key = "{key}"
[node name="Visual" parent="." instance=ExtResource("visual")]
[node name="Blockers" type="Node3D" parent="."]
script = ExtResource("blocker")
mode = "none"
''')
lines=['[gd_scene format=3]','[ext_resource type="Script" path="res://src/aqua/fishery_visual.gd" id="script"]','[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]']
for e in cat:lines.append(f'[ext_resource type="PackedScene" path="res://scenes/components/fishery/{e["key"]}.tscn" id="{e["key"]}"]')
lines+=['[node name="WildFishery" type="Node3D"]','script = ExtResource("script")','visible = false','metadata/asset_id = "SEA-FISHERY-ASSEMBLY"','metadata/asset_version = "v001"','[node name="Blockers" type="Node3D" parent="."]','script = ExtResource("blocker")','mode = "none"']
group_names={'land':'Land','flora':'Flora','water':'Water','fish':'Swimmers'}
for group in group_names.values():lines.append(f'[node name="{group}" type="Node3D" parent="."]')
for item in layout['instances']:
 key=item['key'];p=item['position_godot_world'];pos=[p[k]-origin[k] for k in range(3)];scale=item['scale'];yaw=item['yaw_radians']
 lines.append(f'[node name="{item["instance_id"]}" parent="{group_names[item["group"]]}" instance=ExtResource("{key}")]')
 lines.append('position = Vector3(%s)'%', '.join(f'{v:.9f}' for v in pos))
 if yaw:lines.append(f'rotation = Vector3(0, {yaw:.9f}, 0)')
 if scale!=1:lines.append(f'scale = Vector3({scale}, {scale}, {scale})')
put(R/'godot/scenes/facilities/wild_fishery.tscn','\n'.join(lines)+'\n')
print('ASSEMBLED',len(cat),'component wrappers',len(layout['instances']),'instances; existing scene untouched')
