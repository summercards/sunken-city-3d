"""Stage the shared vegetation patch and keep the existing repair layout."""
import json

import install_ranch as install

WORK = install.WORK.with_name("v013")
ASSEMBLY = "scenes/facilities/rooftop_ranch.tscn"
LAYOUT = "data/vegetation/layouts/rooftop_ranch_ruin.json"


def main():
    install.CANDIDATE = WORK / "godot_candidate"
    scene = (WORK / "official_v012.tscn").read_text()
    assert 'metadata/asset_version = "v012"' in scene
    rows = json.loads((WORK / "placements.json").read_text())["instances"]
    areas = sorted({row["id"].split("/")[1] for row in rows})
    layout = {"schema_version": 1, "scope": "rooftop_ranch_ruin",
              "chunk_metres": 8.0, "regions": [], "instances": rows}
    install.write(LAYOUT, [json.dumps(layout, ensure_ascii=False, separators=(",", ":"))])
    anchor = '[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blockers"]'
    scene = scene.replace(anchor, anchor + '\n\n[ext_resource type="Script" '
                          'path="res://src/ambient/vegetation/patch.gd" id="ruin_vegetation"]', 1)
    scene = scene.replace('metadata/asset_version = "v012"', 'metadata/asset_version = "v013"', 1)
    sections = scene.strip().split("\n\n")
    i = next(i for i, section in enumerate(sections) if section.startswith("[editable"))
    nodes = [
        '[node name="RuinVegetation" type="Node3D" parent="Models"]\n'
        'script = ExtResource("ruin_vegetation")\n'
        f'layout_path = "res://{LAYOUT}"\nmetadata/visual_only = true',
        '[node name="Regions" type="Node3D" parent="Models/RuinVegetation"]',
    ]
    nodes.extend(f'[node name="{area}" type="Node3D" parent="Models/RuinVegetation/Regions"]'
                 for area in areas)
    sections[i:i] = nodes
    install.write(ASSEMBLY, sections)
    print(f"Staged {len(rows)} vegetation instances across {len(areas)} repair regions")


if __name__ == "__main__":
    main()
