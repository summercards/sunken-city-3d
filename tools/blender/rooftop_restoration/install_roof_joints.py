"""Install the two v012 prefabs and transfer the three planter poses."""
import json
from pathlib import Path
import re
import sys

import install_ranch as install

ROOT = install.ROOT
WORK = install.WORK.with_name("v012")
SOURCE = install.SOURCE.with_name("v012")
SCENE = Path("scenes/facilities/rooftop_ranch.tscn")
ANIMATION = install.COMPONENTS / "v010/repair_layout.json"
ENTRY_PLANTS = {"Planter.006", "Greens.008", "Greens.009"}


def main():
    install.EXPORT = WORK / "export"
    install.CANDIDATE = WORK / "godot_candidate"
    baseline = Path(sys.argv[1]).read_text()
    layout = json.loads((install.EXPORT / "runtime_layout.json").read_text())
    plan = json.loads((SOURCE / "component_plan.json").read_text())
    v011 = json.loads((SOURCE.with_name("v011") / "component_instances.json").read_text())
    v012 = json.loads((SOURCE / "component_instances.json").read_text())
    moved = {row["name"]: row for row in v012["instances"] if row["name"] in ENTRY_PLANTS}
    ids = {row["key"]: row["asset_id"] for row in plan["components"]}
    for key, info in layout["components"].items():
        path = install.install_component(key, info, ids[key], version="v012")
        old = f'res://{install.COMPONENTS}/v010/{key}.tscn'
        assert baseline.count(old) == 1
        baseline = baseline.replace(old, f"res://{path}")

    animation = json.loads((ROOT / "godot" / ANIMATION).read_text())
    parts = {row["node"]: row for row in animation["placements"]}
    original = {row["name"]: row for row in v011["instances"] if row["name"] in ENTRY_PLANTS}
    sections = baseline.strip().split("\n\n")
    for index, section in enumerate(sections):
        match = re.search(r'^metadata/placement = "([^"]+)"$', section, re.MULTILINE)
        if match is None or match[1] not in moved:
            continue
        name = match[1]
        node = re.match(r'^\[node name="([^"]+)"', section)[1]
        dx,dy,_ = (new-old for new,old in zip(moved[name]["before"][0],original[name]["before"][0]))
        for state in parts[node]["states"]:
            state[1][0] += dx
            state[1][2] -= dy
        first = install.vector(parts[node]["states"][0][1])
        sections[index] = re.sub(r"^position = Vector3\(.*\)$", f"position = {first}", section, flags=re.MULTILINE)
        del moved[name]
    assert not moved
    animation["version"] = "v012"
    install.write(install.COMPONENTS / "v012/repair_layout.json",
                  [json.dumps(animation, ensure_ascii=False, separators=(",",":"))])
    scene = "\n\n".join(sections).replace('metadata/asset_version = "v011"', 'metadata/asset_version = "v012"')
    install.write(SCENE, [scene])
    (WORK / "installed_assets.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
