"""One-time NEW scenery initialization; final placement belongs to TSCN."""
import json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/submerged_neighborhood/v001'
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
E=json.loads((D/'export_manifest.json').read_text(encoding='utf-8'))
assert E['protected_sources_unchanged']
out=R/'godot/scenes/decorations/underwater/neighborhood.tscn'
assert not out.exists(),'Edit formal TSCN in place; never regenerate'
lines=['[gd_scene format=3]']
for e in E['components']:
    k=e['key'];prefab='godot/scenes/decorations/underwater/buildings/'+k+'.tscn'
    write(R/prefab,'[gd_scene format=3]\n'
        '[ext_resource type="Script" path="res://src/world/submerged_building.gd" id="contract"]\n'
        '[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]\n'
        f'[ext_resource type="PackedScene" path="res://{e["runtime_path"].removeprefix("godot/")}" id="model"]\n'
        f'[node name="{e["name"]}" type="Node3D"]\nscript = ExtResource("contract")\n'
        f'asset_id = "{e["asset_id"]}"\ncomponent_kind = "decoration"\nsubcategory = "underwater_buildings"\nmovable = false\n'
        f'metadata/asset_id = "{e["asset_id"]}"\nmetadata/triangle_budget = 1000\n'
        '[node name="Visual" parent="." instance=ExtResource("model")]\n'
        '[node name="Blockers" type="Node3D" parent="."]\nscript = ExtResource("blocker")\nmode = "none"\nblocks_water = false\n')
    # Import settings are part of the reproducible contract (no embedded images).
    rel=e['runtime_path'].removeprefix('godot/');digest=hashlib.md5(('res://'+rel).encode()).hexdigest()
    cache=f'res://.godot/imported/{k}.glb-{digest}.scn'
    write(R/(e['runtime_path']+'.import'),f'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n\n[deps]\nsource_file="res://{rel}"\ndest_files=["{cache}"]\n\n[params]\nnodes/root_scale=1.0\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=false\nmeshes/force_disable_compression=true\nanimation/import=false\ngltf/embedded_image_handling=0\n')
    lines.append(f'[ext_resource type="PackedScene" path="res://{prefab.removeprefix("godot/")}" id="{k}"]')
lines+=['[node name="水下景观街区" type="Node3D"]','metadata/placement_owner = "formal Godot TSCN"']
for e in E['components']:
    k=e['key'];pos=e['placement_godot']
    # Fit beside the preserved existing sunroom base, with open water channels.
    if k=='terraced_tower':pos=[17.6,-21.5,-10.8]
    if k=='rounded_tower':pos=[-10.4,-20.4,2.0]
    if k=='slender_tower':pos=[-1.2,-16.2,-9.2]
    if k=='rear_slab':pos=[-11.2,-23.0,-11.0]
    if k=='stepped_lowrise':pos=[0.2,-12.0,24.0]
    if k=='flat_annex':pos=[-7.3,-14.6,15.8]
    lines += [f'[node name="{k}" parent="." instance=ExtResource("{k}")]',
        'position = Vector3('+', '.join(str(x) for x in pos)+')',f'instance_id = "home_submerged/{k}"']
write(out,'\n\n'.join(lines)+'\n')
print('INITIALIZED',len(E['components']),'independent scenery scenes')
