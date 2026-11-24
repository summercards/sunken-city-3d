"""Reopen the scoped source and capture matching structural review angles."""
import hashlib
import json
import os
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).parent))
from reopen import audit_collection, audit_palette

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "art_source/scenes/ocean_rooftop_farm"
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration/v011"
VIEWS = {
    "facade": ((-16, -38, 18), (0, -5.1, 6.25), 37),
    "corner": ((27, -22, 13.9), (12.7, -5.1, 6.8), 17),
    "front": ((0, -34, 7), (0, -6.4, 6.7), 36.4),
}


def read(path):
    return json.loads(path.read_text())


def capture(tag):
    scene = bpy.context.scene
    scene.cycles.samples = 10
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1450
    scene.render.resolution_y = 840
    scene.render.resolution_percentage = 100
    camera = scene.camera
    for label, (at, target, size) in VIEWS.items():
        camera.location = at
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = size
        scene.frame_set(300)
        scene.render.filepath = str(WORK / f"{tag}_{label}.png")
        bpy.ops.render.render(write_still=True)
    if tag == "v011":
        at, target, size = VIEWS["corner"]
        camera.location = at
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = size
        scene.frame_set(1)
        scene.render.filepath = str(WORK / "v011_damaged_corner.png")
        bpy.ops.render.render(write_still=True)


def verify():
    scene = bpy.context.scene
    baseline = read(BASE / "v010/component_instances.json")
    updated = read(BASE / "v011/component_instances.json")
    plan = read(BASE / "v011/component_plan.json")
    changed = set(plan["scoped_revision"]["keys"])
    lock = [r for r in baseline["instances"] if r["key"] not in changed]
    assert lock == [r for r in updated["instances"] if r["key"] not in changed]
    for row in updated["instances"]:
        obj = scene.objects[row["name"]]
        assert obj.instance_collection.name == "MASTER | " + row["key"]
        assert obj["asset_key"] == row["key"]
    audit_palette(whole=True)
    old_scene = scene.name
    clips = {item["independent_area"] for item in bpy.data.scenes if "independent_area" in item}
    assert len(clips) == 9
    through_levels = {}
    for level in (1, 2):
        occupants = [r for r in updated["instances"] if r["name"].startswith(f"Frame L{level} ")]
        bays = [r for r in occupants if r["key"].startswith("facade_bay")]
        columns = [r for r in occupants if r["key"] == "corner_pier"]
        beams = [r for r in occupants if r["key"] in {"edge_beam", "beam_corner"}]
        assert len(bays) == 22 and len(columns) == 22 and len(beams) == 26
        assert len({r["key"] for r in bays}) == 4
        assert all(a["key"] != b["key"] for a,b in zip(bays,bays[1:]))
        through_levels[level] = dict(columns=[r["before"][0][:2] for r in columns],
                                     variation=[r["key"] for r in bays])
    assert through_levels[1]["columns"] == through_levels[2]["columns"]
    assert all(a!=b for a,b in zip(through_levels[1]["variation"],through_levels[2]["variation"]))
    package_faces = {}
    for path in sorted((BASE / "v011/component_packages").glob("*/*.blend")):
        bpy.ops.wm.open_mainfile(filepath=str(path))
        assert len(bpy.data.scenes) == 1
        coll = bpy.context.scene.collection.children[0]
        audit_palette()
        audit_collection(coll)
        meta = read(path.with_name("asset_manifest.json"))
        assert meta["source_sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()
        package_faces[path.stem] = sum(len(obj.data.polygons) for obj in coll.objects)
    assert len(package_faces) == 8
    (WORK / "structure_audit.json").write_text(json.dumps({
        "scene": old_scene, "clips": sorted(clips), "placements": len(updated["instances"]),
        "retained_placement_records": len(lock), "new_package_faces": package_faces,
        "per_floor": through_levels,
    }, indent=2, ensure_ascii=False)+"\n")
    print(f"Verified {len(lock)} retained placements, 8 reopened structural packages and 9 clips")

def review_roof():
    scene = bpy.context.scene
    assert scene.frame_current == 1 and not scene.objects["Greenhouse Debris"].hide_render
    assert scene.objects["Greenhouse Base"].hide_render
    audit_palette(whole=True)
    old = read(BASE / "v011/component_instances.json")["instances"]
    current = read(BASE / "v012/component_instances.json")["instances"]
    moved = {"Planter.006", "Greens.008", "Greens.009"}
    assert [r for r in old if r["name"] not in moved] == [r for r in current if r["name"] not in moved]
    keys = {s["independent_area"] for s in bpy.data.scenes if "independent_area" in s}
    assert len(keys) == 9
    scene.frame_set(300)
    for row in (r for r in current if r["name"] in moved):
        assert (scene.objects[row["name"]].location - Vector(row["after"][0])).length < .0001
    work = WORK.with_name("v012")
    camera = scene.camera
    camera.location = (22,-14,21)
    camera.rotation_euler = (Vector((10, -.9,11.5))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale = 16.4
    scene.cycles.samples = 12
    scene.render.resolution_x, scene.render.resolution_y = 1450, 840
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(work/"blender_roof.png")
    bpy.ops.render.render(write_still=True)
    faces = {}
    for path in sorted((BASE/"v012/component_packages").glob("*/*.blend")):
        bpy.ops.wm.open_mainfile(filepath=str(path))
        audit_palette()
        coll = bpy.context.scene.collection.children[0]
        if path.stem == "deck_tile_c":
            audit_collection(coll)
            assert len(coll.objects)==7
            for obj in coll.objects:
                assert abs(max(v.co.z for v in obj.data.vertices)-.20)<.0001
        else:
            # Greenhouse keeps the original installation anchor and has an
            # asymmetric plinth envelope. Inspect centered copies for the UV audit.
            vertices = [v.co for obj in coll.objects for v in obj.data.vertices]
            midpoint = Vector(tuple((min(v[i] for v in vertices)+max(v[i] for v in vertices))/2
                                    for i in range(2))+(0,))
            for obj in coll.objects:
                for vertex in obj.data.vertices:
                    vertex.co -= midpoint
                obj.data.update()
            audit_collection(coll)
        faces[path.stem] = sum(len(obj.data.polygons) for obj in coll.objects)
    assert faces.keys() == {"deck_tile_c", "greenhouse_base"}
    (work/"structure_audit.json").write_text(json.dumps({
        "placements": len(current), "retained_placement_records": len(current)-16,
        "moved_placements": sorted(moved), "new_package_faces":faces, "clips": sorted(keys),
    },ensure_ascii=False,indent=2)+"\n")


def review_ruin_growth():
    scene = bpy.context.scene
    folder = WORK.with_name("v013")
    plan = read(BASE / "v013/component_plan.json")
    layout = read(BASE / "v013/component_instances.json")
    rows = read(folder / "placements.json")["instances"]
    plants = scene.collection.children["06 | Wild roof growth"]
    assert scene.frame_current == 1
    assert len(plants.all_objects) == len(rows)
    assert all(not obj.hide_render for obj in plants.all_objects)
    for image in bpy.data.images:
        if image.source == "FILE":
            assert Path(bpy.path.abspath(image.filepath)).is_file(), image.filepath
    assert layout["instances"] == read(BASE / "v012/component_instances.json")["instances"]
    hosts = {row["name"]: row["area"] for row in layout["instances"]}
    refs = plan["external_plant_refs"]
    for row in rows:
        _, area, _ = row["id"].split("/")
        assert hosts[row["host"]] in (None, area)
        frame = layout["areas"][area]["frames"][0] + 6
        assert row["clear_frame"] == frame and row["height_m"] < .60
    assert {obj.instance_collection["asset_id"] for obj in plants.all_objects} == {
        ref["asset_id"] for ref in refs.values()}
    camera = scene.camera
    camera.location = (-10,-32,21)
    camera.rotation_euler = (Vector((0,0,10.4))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale = 38
    scene.cycles.samples = 10
    scene.render.resolution_x, scene.render.resolution_y = 1450, 820
    scene.render.resolution_percentage = 100
    for frame, key in ((1,"damaged"),(191,"repaired")):
        scene.frame_set(frame)
        assert all(obj.hide_render == (frame == 191) for obj in plants.all_objects)
        scene.render.filepath = str(folder / f"blender_{key}.png")
        bpy.ops.render.render(write_still=True)
    (folder / "growth_audit.json").write_text(json.dumps({
        "placements":len(layout["instances"]), "growth":len(rows), "regions":len(plants.children),
        "plant_asset_ids":[ref["asset_id"] for ref in refs.values()],
    }, ensure_ascii=False, indent=2)+"\n")


def review_submerged():
    scene = bpy.context.scene
    folder = WORK.with_name("v014")
    source = BASE / "v014"
    layout = read(source/"component_instances.json")
    old = read(BASE/"v013/component_instances.json")
    retained = [row for row in layout["instances"] if "floor" not in row]
    changed = {"Pier Dock", "Access Stairs"}
    assert [r for r in retained if r["name"] not in changed] == [r for r in old["instances"] if r["name"] not in changed]
    lower = scene.collection.children["07 | Submerged seven storeys"]
    assert scene.frame_current == 1 and len(lower.children) == 7
    levels = read(source/"submerged_levels.json")["levels"]
    patterns = set()
    for level, group in zip(levels, lower.children):
        assert abs(level["datum"] + level["floor"]*5.1) < .00001
        assert len(group.objects) == len(level["placements"])
        pattern = frozenset(row["name"].split(" ", 2)[-1] for row in level["placements"]
                            if row["key"].endswith(("broken","open","spalled")))
        assert pattern and pattern not in patterns
        patterns.add(pattern)
        for obj in group.objects:
            assert obj.instance_collection is not None
            for mesh in obj.instance_collection.objects:
                assert all((obj.matrix_world @ v.co).z < .04 for v in mesh.data.vertices)
    for image in bpy.data.images:
        if image.source == "FILE":
            assert Path(bpy.path.abspath(image.filepath)).is_file(), image.filepath
    camera = scene.camera
    camera.location = (32,-54,29)
    camera.rotation_euler = (Vector((0,0,-10.4))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale = 62
    scene.cycles.samples = 12
    scene.render.resolution_x, scene.render.resolution_y = 1350, 1350
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(folder/"blender_nine_storeys.png")
    bpy.ops.render.render(write_still=True)
    faces = {}
    for path in sorted((source/"component_packages").glob("*/*.blend")):
        bpy.ops.wm.open_mainfile(filepath=str(path))
        audit_palette()
        coll = bpy.context.scene.collection.children[0]
        if path.stem == "access_stairs":
            # Audit with bottom-centred geometry while preserving the saved interface.
            points = [v.co for o in coll.objects for v in o.data.vertices]
            low,high = (Vector(tuple(f(v[i] for v in points) for i in range(3))) for f in (min,max))
            origin = Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
            for obj in coll.objects:
                for v in obj.data.vertices:
                    v.co -= origin
                obj.data.update()
        audit_collection(coll)
        faces[path.stem] = sum(len(o.data.polygons) for o in coll.objects)
    assert len(faces) == 10
    (folder/"structure_audit.json").write_text(json.dumps({
        "placements":len(layout["instances"]), "retained_placement_records":len(retained)-1,
        "new_package_faces":faces, "clips":list(layout["areas"]),
        "submerged_levels":len(levels), "unique_damage_patterns":len(patterns),
    },ensure_ascii=False,indent=2)+"\n")


if "submerged" in sys.argv:
    review_submerged()
elif "growth" in sys.argv:
    review_ruin_growth()
elif "roof" in sys.argv:
    review_roof()
elif "verify" in sys.argv:
    verify()
else:
    capture(Path(bpy.data.filepath).stem.rsplit("_",1)[-1])
