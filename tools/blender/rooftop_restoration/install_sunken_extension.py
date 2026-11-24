"""Stage the shorter access stair and the seven visual-only lower storeys."""
import json
from pathlib import Path
import re

import install_ranch as install

WORK = install.WORK.with_name("v014")
SOURCE = install.SOURCE.with_name("v014")
ASSEMBLY = Path("scenes/facilities/rooftop_ranch.tscn")
LOWER = install.COMPONENTS / "v014/submerged_levels.tscn"


def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new, 1)


def main():
    install.EXPORT = WORK / "export"
    install.CANDIDATE = WORK / "godot_candidate"
    layout = json.loads((install.EXPORT / "runtime_layout.json").read_text())
    plan = json.loads((SOURCE / "component_plan.json").read_text())
    ids = {row["key"]: row["asset_id"] for row in plan["components"] + plan["submerged_kit"]}
    drop = plan["scoped_revision"]["drop_m"]
    components = {key: install.install_component(key, info, ids[key], version="v014")
                  for key, info in layout["components"].items()}
    stair = components.pop("access_stairs")
    rows = [row for row in layout["placements"] if row["key"] in components]
    sections = ['[gd_scene format=3]']
    sections.extend(f'[ext_resource type="PackedScene" path="res://{path}" id="{key}"]'
                    for key, path in components.items())
    sections.append('[node name="SubmergedLevels" type="Node3D"]\nmetadata/visual_only = true\n'
                    'metadata/building_class = "underwater"\nmetadata/water_layer = "submerged"\n'
                    'metadata/water_layer_role = "part"')
    for floor in range(1,8):
        parent = f"Floor{floor:02d}"
        sections.append(f'[node name="{parent}" type="Node3D" parent="."]')
        for index, row in enumerate(row for row in rows if row["name"].startswith(f"Lower {floor:02d} ")):
            _, pos, rotation, scale, visible = row["states"][0]
            assert visible
            key = row["key"]
            title = re.sub(r"[^a-zA-Z0-9]+", "_", row["name"][9:]).strip("_")
            sections.append(f'[node name="{title}_{index:02d}" parent="{parent}" instance=ExtResource("{key}")]\n'
                            f'position = {install.vector(pos)}\n'
                            f'quaternion = {install.vector(rotation, "Quaternion")}\n'
                            f'scale = {install.vector(scale)}\nmetadata/component_key = "{key}"')
    install.write(LOWER, sections)
    scene = (WORK/"official_v013.tscn").read_text()
    scene = replace_once(scene, f"res://{install.COMPONENTS}/v010/access_stairs.tscn", f"res://{stair}")
    first_res = '[sub_resource type="ConcavePolygonShape3D" id="Floor_Pier_Dock_123"]'
    scene = replace_once(scene, first_res, f'[ext_resource type="PackedScene" path="res://{LOWER}" id="deep"]\n\n'+first_res)
    scene = replace_once(scene, 'metadata/asset_version = "v013"', 'metadata/asset_version = "v014"')
    scene = replace_once(scene, 'metadata/asset_version = "v014"',
                         f'metadata/asset_version = "v014"\nmetadata/lowered_m = {drop}')
    height = install.HEIGHT - drop
    scene = replace_once(scene, 'position = Vector3(0, 52.04, 0)', f'position = Vector3(0, {height:.2f}, 0)')
    old = '[node name="BuildingAnimation" type="AnimationPlayer" parent="."]'
    scene = replace_once(scene, old, f'[node name="SubmergedLevels" parent="." instance=ExtResource("deep")]\n'
                         f'position = Vector3(0, {height:.2f}, 0)\n\n'+old)
    for name in ("RepairPrompts", "NpcStations"):
        pattern = rf'^(\[node name="{name}" .*\])$'
        scene, count = re.subn(pattern, rf'\1\nposition = Vector3(0, -{drop}, 0)', scene, flags=re.MULTILINE)
        assert count == 1
    scene = replace_once(scene, "altitude = 66.9", f"altitude = {66.9-drop:.2f}")
    scene = replace_once(scene, "surface_y = 62.24", f"surface_y = {62.24-drop:.2f}")
    scene = replace_once(scene, "span_max = 63.0", f"span_max = {63.0-drop:.2f}")
    scene = replace_once(scene, "position = Vector3(18.360001, 4.49, 5.88)", f"position = Vector3(18.360001, {4.49+drop:.2f}, 5.88)")
    scene = replace_once(scene, "position = Vector3(18.549999, 5.20871, 2.14)", f"position = Vector3(18.549999, {5.20871+drop:.5f}, 2.14)")
    install.write(ASSEMBLY, [scene.strip()])
    layout["submerged_instances"] = len(rows)
    (WORK/"installed_assets.json").write_text(json.dumps(layout,ensure_ascii=False,indent=2)+"\n")
    print(f"Staged shortened stair and {len(rows)} visual-only submerged placements")


if __name__ == "__main__":
    main()
