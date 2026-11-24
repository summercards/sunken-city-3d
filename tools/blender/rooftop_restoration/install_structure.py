"""Update only the structural instances in the hand-maintained ranch scene."""
import json
from pathlib import Path
import re
import sys

import install_ranch as install

ROOT = install.ROOT
WORK = install.WORK.with_name("v011")
SOURCE = install.SOURCE.with_name("v011")
SCENE = Path("scenes/facilities/rooftop_ranch.tscn")
install.EXPORT = WORK / "export"
install.CANDIDATE = WORK / "godot_candidate"


def main():
    baseline = Path(sys.argv[1]).read_text()
    layout = json.loads((install.EXPORT / "runtime_layout.json").read_text())
    plan = json.loads((SOURCE / "component_plan.json").read_text())
    ids = {row["key"]: row["asset_id"] for row in plan["components"]}
    keys = set(layout["components"])
    assert keys == set(plan["scoped_revision"]["keys"])
    sections = baseline.strip().split("\n\n")
    assert 'metadata/asset_version = "v010"' in baseline
    ids_re = "|".join(sorted(keys))
    sections = [section for section in sections if not (
        section.startswith('[ext_resource') and re.search(rf' id="({ids_re})"\]$', section)
        or section.startswith('[node') and re.search(rf'\nmetadata/component_key = "({ids_re})"\n', section)
    )]
    at = next(i for i,section in enumerate(sections) if section.startswith("[sub_resource"))
    for key, info in sorted(layout["components"].items()):
        path = install.install_component(key, info, ids[key], version="v011")
        sections.insert(at, f'[ext_resource type="PackedScene" path="res://{path}" id="{key}"]')
        at += 1
    index = next(i for i,section in enumerate(sections) if section.startswith("[editable"))
    for part in layout["placements"]:
        name, key = part["name"], part["key"]
        _, pos, quaternion, scale, visible = part["states"][0]
        assert visible and len(part["states"]) == 1
        node = re.sub("[^a-zA-Z0-9]+", "_", name.replace("-", "_neg_")).strip("_")
        sections.insert(index, f'[node name="{node}" parent="Models" instance=ExtResource("{key}")]\n'
                        f'position = {install.vector(pos)}\n'
                        f'quaternion = {install.vector(quaternion, "Quaternion")}\n'
                        f'scale = {install.vector(scale)}\nmetadata/component_key = "{key}"\n'
                        f'metadata/placement = {json.dumps(name, ensure_ascii=False)}')
        index += 1
    scene = "\n\n".join(sections).replace('metadata/asset_version = "v010"', 'metadata/asset_version = "v011"')
    retained_count = len(re.findall(r"^metadata/component_key", scene, re.MULTILINE))
    assert retained_count == 302 + len(layout["placements"])
    scene = re.sub(r"metadata/component_instances = \d+", f"metadata/component_instances = {retained_count}", scene)
    scene = scene.replace("metadata/component_catalog = 46", "metadata/component_catalog = 50")
    install.write(SCENE, [scene])
    (WORK / "installed_assets.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
