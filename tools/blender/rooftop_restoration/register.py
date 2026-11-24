import hashlib
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from apply_water_layer import building_views, classify, classify_building


VERSION = next((v for v in ("v014", "v013", "v012") if v in sys.argv), "v011" if "structure-v011" in sys.argv else "v010")
SCOPED = VERSION != "v010"
SOURCE = ROOT / "art_source/scenes/ocean_rooftop_farm" / VERSION
EVIDENCE = "docs/development/" + {
    "v010": "2026-11-23_rooftop_ranch_full.md",
    "v011": "2026-11-24_rooftop_ranch_structure.md",
    "v012": "2026-11-24_rooftop_ranch_roof_joints.md",
    "v013": "2026-11-24_rooftop_ranch_wild_growth.md",
    "v014": "2026-11-24_rooftop_ranch_submerged.md",
}[VERSION]
REGISTRY = ROOT / "assets/registry"
ASSEMBLY = Path("godot/scenes/facilities/rooftop_ranch.tscn")
RUNTIME = Path("godot/scenes/components/facilities/rooftop_ranch/v010")
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration"
WORK /= VERSION if SCOPED else "full-v010"


def write(path, value):
    old = path.read_bytes() if path.exists() else b""
    new = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if b"\r\n" in old:
        new = new.replace("\n", "\r\n")
    if new.encode() != old:
        path.write_bytes(new.encode())


def read(path):
    return json.loads(path.read_text())


routes = read(REGISTRY / "ledger_index.json")["domains"]
route = routes["scenes"]
ledger_path = ROOT / route["ledger"]
book = read(ledger_path)
rows = book[route["asset_key"]]
manifests = [SOURCE / "asset_manifest.json", *sorted(SOURCE.glob("component_packages/*/asset_manifest.json"))]
entries = []
if VERSION == "v013":
    verified = read(WORK / "growth_audit.json")
    layout = {"source_sha256": read(manifests[0])["source_sha256"]}
    assert len(manifests) == 1 and verified["regions"] == 8
else:
    layout = read(WORK / "installed_assets.json")
    assert layout["version"] == SOURCE.name
if SCOPED and VERSION != "v013":
    verified = read(WORK / "structure_audit.json")
    assert verified["placements"] == len(layout["placements"]) + verified["retained_placement_records"]
    assert set(verified["new_package_faces"]) == set(layout["components"])
    assert len(verified["clips"]) == 9 and len(manifests) == len(layout["components"]) + 1
elif not SCOPED:
    verified = read(SOURCE / "source_verification.json")
    assert verified["frames_checked"] == 300 and verified["component_count"] == len(manifests) - 1
    assert len(layout["components"]) == 46 and len(layout["placements"]) == 390
for path in manifests:
    meta = read(path)
    aid = meta["asset_id"]
    key = meta.get("key","rooftop_restoration")
    source_sha = hashlib.sha256((ROOT / meta["source"]).read_bytes()).hexdigest()
    assert source_sha == meta["source_sha256"], aid
    water_layer, water_role = classify(aid)
    building_class = classify_building(aid)
    assert building_class == meta["building_class"], aid
    category, label = {
        "structure":("structure","建筑结构"),"facility":("furnishing","固定设施"),
        "vegetation":("flora","植物"),"assembly":("building_assembly","建筑总成"),
    }[meta.get("category","assembly")]
    entry = {
        "asset_id":aid,"asset_key":key,"domain":"scenes",
        "name":meta.get("name","海上屋顶牧场 · 破损与重建"),
        "category":category,"category_label":label,
        "stage":"runtime_integrated_verified","version":SOURCE.name,"source":meta["source"],
        "source_sha256":source_sha,"manifest":path.relative_to(ROOT).as_posix(),
        "building_class":building_class,"water_layer":water_layer,"water_layer_role":water_role,
        "front_axis":"-Y","license":"original_meshes; commercial reference usage pending",
        "consumer_features":["SEA-ASSET","SEA-WORLD"],
        "verification":EVIDENCE,
    }
    if category == "building_assembly":
        entry["clips"] = {
            key: {**clip, "duration_seconds": round((clip["frames"][1] - clip["frames"][0] + 1) / meta["fps"], 3)}
            for key, clip in meta["clips"].items()
        }
        entry["fps"] = meta["fps"]
        entry["main_duration_seconds"] = 10.0
        entry["footprint_m"] = [34.72,13.82] if SCOPED else [34.4,13.8]
        entry["origin"] = "building_local"
        entry["collision_responsibility"] = "Independent component solids, marine hulls and state-dependent walk surfaces."
        assert layout["source_sha256"] == source_sha
        entry["prefab"] = ASSEMBLY.as_posix()
        entry["runtime_verification"] = "full_assembly_verified"
        entry["construction_animation"] = {"clip":"construction","duration_seconds":3.567,
                                           "trigger":"八个区域修复完毕后的屋顶搭建交互"}
        if SCOPED:
            entry.update(component_count=50, instance_count=verified["placements"], base_version=meta["base_version"])
        if VERSION in ("v012", "v013", "v014"):
            entry["construction_animation"]["shared_tracks"] = "godot/src/building/construction_animation.gd"
        if VERSION in ("v013", "v014"):
            entry["wild_growth"] = meta["wild_growth"]
        if VERSION == "v013":
            assert meta["wild_growth"]["count"] == verified["growth"]
        if VERSION == "v014":
            assert verified["submerged_levels"] == verified["unique_damage_patterns"] == 7
            assert layout["submerged_instances"] == meta["submerged_instances"]
            entry.update(component_count=50 + len(layout["components"]) - 1,
                         submerged_levels=7, submerged_instances=layout["submerged_instances"])
        meta.pop("installed_subassembly", None)
        meta.update(prefab=entry["prefab"], runtime_status="full_assembly_verified", runtime_verification=EVIDENCE)
    else:
        entry["origin"] = meta.get("origin", "bottom_center")
        component = layout["components"][key]
        entry["triangles"] = component["after"] if SCOPED else verified["triangles_per_master"][key]
        digest = hashlib.sha256((ROOT / component["model"]).read_bytes()).hexdigest()
        assert digest == component["glb_sha256"], key
        entry.update(runtime_path=component["model"], runtime_sha256=digest, prefab=component["prefab"])
        roles = []
        if component["solid"]:
            roles.append("wrapper_local_actor_solids")
        if component["hull"]:
            roles.append("wrapper_local_hull_solids")
        entry["collision_responsibility"] = " + ".join(roles) or "visual_only"
        meta.update(runtime_path=entry["runtime_path"], prefab=entry["prefab"])
    meta["asset_ledger"] = route["ledger"] + "#" + aid
    meta["version"] = SOURCE.name
    entries.append((entry,path,meta))

all_asset_ids = [a["asset_id"] for domain,location in routes.items()
                 for a in (rows if domain=="scenes" else read(ROOT/location["ledger"])[location["asset_key"]])]
incoming = {entry["asset_id"] for entry,_,_ in entries}
assert len(incoming) == len(entries)
assert all(all_asset_ids.count(aid) <= 1 for aid in incoming)
assert not incoming.intersection(aid for aid in all_asset_ids if sum(row["asset_id"] == aid for row in rows) == 0)
lookup = {entry["asset_id"]:entry for entry,_,_ in entries}
book[route["asset_key"]] = [lookup.pop(row["asset_id"],row) for row in rows] + list(lookup.values())
write(ledger_path,book)
for _,path,meta in entries:
    write(path,meta)

source_path = REGISTRY / "current_source_index.json"
source_index = read(source_path)
keys = ("asset_id","source","source_sha256","manifest")
old = [row for row in source_index["sources"] if row["asset_id"] not in incoming]
previous_scene_ids = {row["asset_id"] for row in rows}
insertion = max(i + 1 for i,row in enumerate(old) if row["asset_id"] in previous_scene_ids)
seen = {row["asset_id"]:row for row in old[:insertion]}
seen.update({entry["asset_id"]:{key:entry[key] for key in keys} for entry,_,_ in entries})
source_index["sources"] = [seen[row["asset_id"]] for row in book[route["asset_key"]]] + old[insertion:]
write(source_path,source_index)
for name,view in building_views(book[route["asset_key"]],route["ledger"]).items():
    write(ROOT / route["building_views"][name],view)

runtime_path = REGISTRY / "runtime_resource_inventory.json"
runtime = read(runtime_path)
paths = {row["path"]:row for row in runtime["resources"]}
runtime_assets = {}
for entry,_,_ in entries:
    if "runtime_path" in entry:
        for path in (entry["runtime_path"],entry["runtime_path"]+".import",entry["prefab"]):
            runtime_assets[path] = entry["asset_id"]
runtime_assets["godot/tests/test_rooftop_ranch.gd"] = None
if VERSION == "v012":
    for path in (RUNTIME.with_name("v012")/"repair_layout.json",
                 Path("godot/src/facilities/rooftop_ranch_zone.gd"),
                 Path("godot/src/building/construction_animation.gd")):
        runtime_assets[path.as_posix()] = None
if VERSION == "v013":
    runtime_assets["godot/src/facilities/rooftop_ranch_zone.gd"] = None
    runtime_assets["godot/data/vegetation/layouts/rooftop_ranch_ruin.json"] = "SEA-SCENE-ORF7-ASSEMBLY"
if VERSION == "v014":
    runtime_assets["godot/src/facilities/rooftop_ranch_zone.gd"] = None
    runtime_assets["godot/src/bootstrap/main.gd"] = None
    runtime_assets["tools/apply_water_layer.py"] = None
    runtime_assets[(RUNTIME.with_name("v014")/"submerged_levels.tscn").as_posix()] = "SEA-SCENE-ORF7-ASSEMBLY"
for path in (() if SCOPED else (
    RUNTIME/"repair_layout.json",
    Path("godot/scenes/npc/rooftop_npc_stations.tscn"),
    Path("godot/src/facilities/rooftop_ranch_zone.gd"),
    Path("godot/src/facilities/rooftop_ranch_repair_prompt.gd"),
    Path("godot/assets/data/zones.json"),
    Path("tools/apply_water_layer.py"),
)):
    runtime_assets[path.as_posix()] = None
runtime_assets[ASSEMBLY.as_posix()] = "SEA-SCENE-ORF7-ASSEMBLY"
for path, asset_id in runtime_assets.items():
    data = (ROOT / path).read_bytes()
    row = paths.get(path)
    if row is None:
        row = {"path":path, "asset_id":asset_id}
        runtime["resources"].append(row)
    row.update(sha256=hashlib.sha256(data).hexdigest(),bytes=len(data),asset_id=asset_id,
               status=f"runtime_verified_rooftop_ranch_{VERSION}",runtime_verification=EVIDENCE)
write(runtime_path,runtime)
print(f"Registered {len(entries)} rooftop restoration sources")
