"""Stage individually importable house assets outside the Godot project."""
import hashlib
import json
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[3]
VERSION = "v010"
SOURCE = ROOT / "art_source/scenes/ocean_rooftop_farm" / VERSION
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent/"sea-work"))/"rooftop_restoration"/VERSION
EXPORT = WORK/"export"
CANDIDATE = WORK/"godot_candidate"
MODEL = Path("assets/models/facilities/rooftop_ranch/house")/VERSION
COMPONENT = Path("scenes/components/facilities/rooftop_ranch/house")/VERSION

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value)

def vec(values):
    return "Vector3(" + ", ".join(f"{v:.7g}" for v in values) + ")"

layout = json.loads((EXPORT/"runtime_layout.json").read_text())
plan = json.loads((SOURCE/"component_plan.json").read_text())
asset_ids = {row["key"]: row["asset_id"] for row in plan["components"]}
wrappers = []
for key, info in layout["components"].items():
    model = MODEL/f"{key}.glb"
    destination = CANDIDATE/model
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(EXPORT/f"{key}.glb", destination)
    res_model = f"res://{model.as_posix()}"
    digest = hashlib.md5(res_model.encode()).hexdigest()
    cache = f"res://.godot/imported/{key}.glb-{digest}.scn"
    write(CANDIDATE/(str(model)+".import"), f'''[remap]

importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"

[deps]

source_file="{res_model}"
dest_files=["{cache}"]

[params]

meshes/generate_lods=false
meshes/create_shadow_meshes=true
animation/import=false
gltf/embedded_image_handling=0
import_script/path="res://tools/rooftop_ranch_palette_import.gd"
_subresources={{}}
''')
    shapes = info["collision"]
    lines = ['[gd_scene format=3]',
             f'[ext_resource type="PackedScene" path="{res_model}" id="model"]']
    for index, box in enumerate(shapes):
        lines += [f'[sub_resource type="BoxShape3D" id="box{index}"]', f'size = {vec(box["size"])}']
    lines += ['[node name="Piece" type="Node3D"]', f'metadata/asset_id = "{asset_ids[key]}"',
              '[node name="Visual" parent="." instance=ExtResource("model")]']
    if shapes:
        lines += ['[node name="Solid" type="StaticBody3D" parent="."]',
                  'collision_layer = 8192', 'collision_mask = 0']
    for index, box in enumerate(shapes):
        lines += [f'[node name="Segment{index}" type="CollisionShape3D" parent="Solid"]',
                  f'position = {vec(box["center"])}', f'shape = SubResource("box{index}")']
    wrapper = COMPONENT/f"{key}.tscn"
    write(CANDIDATE/wrapper,"\n\n".join(lines)+"\n")
    info.update({"model": "godot/"+model.as_posix(), "prefab": "godot/"+wrapper.as_posix()})
    wrappers.append((key,wrapper))

lines = ['[gd_scene format=3]',
         '[ext_resource type="Script" path="res://src/facilities/rooftop_house_repair.gd" id="repair"]',
         '[ext_resource type="Script" path="res://src/facilities/rooftop_house_repair_prompt.gd" id="prompt"]',
         '[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blockers"]']
lines += [f'[ext_resource type="PackedScene" path="res://{path.as_posix()}" id="{key}"]'
          for key,path in wrappers]
lines += ['[node name="RooftopHouse" type="Node3D"]', 'script = ExtResource("repair")',
          'metadata/asset_id = "SEA-SCENE-ORF7-ASSEMBLY"', 'metadata/building_class = "above_water"',
          '[node name="Blockers" type="Node3D" parent="."]', 'script = ExtResource("blockers")',
          'mode = "none"', 'blocks_water = false',
          '[node name="BuildingAnimation" type="AnimationPlayer" parent="."]',
          '[node name="RepairPrompt" type="Node3D" parent="."]', 'position = Vector3(2, 0.02, 3.85)',
          'script = ExtResource("prompt")', 'id = "rooftop_ranch_house_repair"',
          'label = "屋顶小屋"', 'verb = "修复"', 'focus_anchor = "node"', 'focus_radius = 1.55', 'auto_radius = false']
for index, part in enumerate(layout["placements"]):
    part["node"] = f"Part{index:02d}"
    _,pos,quaternion,scale,visible = part["states"][0]
    lines += [f'[node name="{part["node"]}" parent="." instance=ExtResource("{part["key"]}")]',
              f'position = {vec(pos)}', f'quaternion = Quaternion({", ".join(map(str,quaternion))})',
              f'scale = {vec(scale)}', f'visible = {str(visible).lower()}',
              f'metadata/placement = {json.dumps(part["name"],ensure_ascii=False)}',
              f'metadata/component_key = "{part["key"]}"']
    if not visible and layout["components"][part["key"]]["collision"]:
        lines += [f'[node name="Solid" parent="{part["node"]}" index="1"]','collision_layer = 0']
        # Imported child override is serialized so opening the scene uses the damaged collision.
        lines += [f'[editable path="{part["node"]}"]']
# Godot requires editable declarations after all scene nodes.
editable = [line for line in lines if line.startswith("[editable ")]
lines = [line for line in lines if not line.startswith("[editable ")] + editable
write(CANDIDATE/COMPONENT/"rooftop_house.tscn","\n\n".join(lines)+"\n")
write(CANDIDATE/COMPONENT/"repair_layout.json",json.dumps(layout,ensure_ascii=False,separators=(",",":"))+"\n")
print(f"{len(wrappers)} wrappers and {len(layout['placements'])} independently editable house placements")
