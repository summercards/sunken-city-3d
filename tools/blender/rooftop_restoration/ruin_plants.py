"""Bake workshop plant placements against the damaged roof and attach editable Blender instances."""
import hashlib
import json
import math
import os
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).parent))
from reopen import route_bvh

ROOT = Path(__file__).resolve().parents[3]
OLD = ROOT / "art_source/scenes/ocean_rooftop_farm/v012"
SOURCE = OLD.with_name("v013")
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration/v013"
ASSETS = {
    "grass_soft": ("v003", "SEA-VEG-GRASS-SOFT", .43, .48),
    "mound_soft": ("v003", "SEA-VEG-MOUND-SOFT", 1.55, 1.13),
    "moss_soft": ("v002", "SEA-VEG-MOSS-SOFT", .52, .16),
}
# Irregular concentrations follow debris, the raised terrace, and broken
# edges. Skipping any individual ray keeps the exposed ruin visible.
ISLANDS = {
    "west": [(-15.8,-3.1,1.3,1.2,18),(-14.7,-1.3,1.1,1.0,13),(-8.7,-2.0,1.5,1.8,19),
             (-16.15,2.3,.56,2.15,15)],
    "center": [(-4.8,-1.1,1.4,1.95,25),(-1.2,.4,1.8,1.6,25),(1.15,2.1,1.4,1.75,17),
               (-4.5,4.9,1.85,.8,14),(-2.2,-6.39,2.0,.22,14),(-1.6,-4.45,1.6,.42,13)],
    "east": [(3.2,-1.8,1.35,1.6,30),(5.0,.45,1.25,1.8,23),(5.6,4.9,1.25,.9,17),
             (4.2,-6.4,1.45,.24,12)],
    "greenhouse_floor": [(7.3,1.4,1.28,2.0,23),(9.8,4.7,2.2,1.1,29),(12.35,-.55,1.3,1.35,23)],
    "tower_floor": [(15.5,5.55,.9,.82,23),(15.5,.58,.9,1.3,17)],
    "house": [(-14.7,1.1,.42,1.9,15),(-15.6,3.7,.72,1.65,17),(-13.85,2.8,1.08,.95,18),
              (-12.3,4.9,.86,.56,10),(-9.1,.78,.9,.65,14)],
    "greenhouse": [(9.2,-.63,1.3,1.4,21),(11.3,1.8,1.5,1.4,26),(10.55,3.3,1.35,1.2,17)],
    "tower": [(14.45,3.45,1.1,1.35,20),(16.4,3.65,.66,1.65,19)],
}


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def segment_distance(point, a, b):
    d = b - a
    return (point - (a + d * min(1, max(0, (point-a).dot(d)/d.length_squared)))).length


def collect_rows(scene, layout):
    scene.frame_set(1)
    tree, labels = route_bvh(scene)
    routes = list(layout["walk_routes"].values()) + [[(-14.2,-5.65),(-16.12,-5.65)]]
    lines = [(Vector(a),Vector(b)) for route in routes for a,b in zip(route,route[1:])]
    rng = random.Random(11173)
    rows = []
    positions = {}
    windows = layout["areas"]
    hosts = {item["name"]: item["area"] for item in layout["instances"]}
    down = Vector((0,0,-1))
    allowed = ("Paving ", "Deck Underframe", "Rubble", "Greenhouse Debris", "Tower Debris",
               "Rail Pier", "Frame L2 beam", "Raised terrace fascia", "House Roof", "House Eaves")
    for area, groups in ISLANDS.items():
        for island, (cx,cy,rx,ry,count) in enumerate(groups):
            accepted = 0
            for i in range(count * 5):
                if accepted >= count:
                    break
                theta = rng.random() * math.tau
                r = math.sqrt(rng.random())
                x,y = cx+math.cos(theta)*rx*r, cy+math.sin(theta)*ry*r
                key = rng.choices(list(ASSETS), weights=(70,22,8))[0]
                radius, height = ASSETS[key][2:]
                width = rng.uniform(.62,1.18) if key == "grass_soft" else rng.uniform(.23,.52)
                vertical = rng.uniform(.65,1.23) if key == "grass_soft" else rng.uniform(.23,.48)
                if key == "moss_soft":
                    width, vertical = rng.uniform(.58,1.05),rng.uniform(.55,1.0)
                radius *= width
                yaw = rng.uniform(0,math.tau)
                point = Vector((x,y))
                if min(segment_distance(point,a,b) for a,b in lines) < .43+radius:
                    continue
                if any((point-xy).length < (.24 if key=="mound_soft" else .13) for xy in positions.get(area, [])):
                    continue
                roof = area=="house" and island in (2,3)
                hit,normal,face,_ = tree.ray_cast(Vector((x,y,15.4 if roof else 12.75)),down,5.1 if roof else 3.85)
                if hit is None or normal.z < .46 or not labels[face].startswith(allowed):
                    continue
                if roof != (hit.z > 12.75):
                    continue
                if labels[face].startswith("Rail Pier") or (x>15.04 and y< -3.15):
                    continue
                owner = hosts.get(labels[face]) or area
                start, end = windows[owner]["frames"]
                positions.setdefault(area,[]).append(point)
                rows.append({"id":f"rooftop_ranch/{owner}/{area}_{island:02d}_{i:03d}", "asset":key,
                             "position":[round(hit.x,5), round(hit.z-.024,5), round(-hit.y,5)],
                             "scale":[round(width,5),round(vertical,5),round(width,5)],
                             "yaw":round(yaw,6),"phase":round(rng.random(),5),"variation":round(rng.random(),5),
                             "host":labels[face],"height_m":round(height*vertical,3),
                             "clear_frame":min(start+6,end-2)})
                accepted += 1
    assert len(rows)>225, len(rows)
    return rows


def load_asset(key):
    version, asset_id, _, _ = ASSETS[key]
    path=ROOT/f"art_source/vegetation/{version}/components/{key}/{key}.blend"
    with bpy.data.libraries.load(str(path), link=False) as (source,dest):
        dest.objects = [key]
    obj = dest.objects[0]
    assert obj is not None and obj.type == "MESH"
    coll = bpy.data.collections.new("WORKSHOP | "+key)
    coll["asset_id"] = asset_id
    coll["source"] = path.relative_to(ROOT).as_posix()
    coll.objects.link(obj)
    for material in obj.data.materials:
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                image_path = ROOT / "art_source/vegetation" / version / Path(node.image.filepath).name
                assert image_path.is_file(), image_path
                node.image.filepath = str(image_path)
    return coll


def instance(coll, parent, row, clear=None):
    name = row["id"].rsplit("/", 1)[-1]
    obj = bpy.data.objects.new(row["asset"]+" "+name,None)
    parent.objects.link(obj)
    obj.instance_type = "COLLECTION"
    obj.instance_collection = coll
    x,z,neg_y = row["position"]
    sx,sz,sy = row["scale"]
    obj.location = (x,-neg_y,z)
    obj.rotation_euler.z = row["yaw"]
    obj.scale = (sx,sy,sz)
    obj.empty_display_size = .09
    obj["host"] = row["host"]
    if clear is not None:
        for frame, hidden in ((1,False),(clear,True)):
            obj.hide_render = obj.hide_viewport = hidden
            obj.keyframe_insert("hide_render",frame=frame)
            obj.keyframe_insert("hide_viewport",frame=frame)


def main():
    assert Path(bpy.data.filepath).resolve().parent == OLD
    layout=read(OLD/"component_instances.json")
    scene=bpy.context.scene
    rows=collect_rows(scene,layout)
    for image in bpy.data.images:
        if image.source == "FILE":
            image.filepath = bpy.path.abspath(image.filepath)
    collections = {key:load_asset(key) for key in ASSETS}
    cover=bpy.data.collections.new("06 | Wild roof growth")
    scene.collection.children.link(cover)
    for area in ISLANDS:
        group=bpy.data.collections.new("Wild growth | "+area)
        cover.children.link(group)
        clip=next(sc for sc in bpy.data.scenes if sc.get("independent_area")==area)
        clip_group=bpy.data.collections.new("Wild growth in clip | "+area)
        clip.collection.children.link(clip_group)
        start=layout["areas"][area]["frames"][0]
        for row in (row for row in rows if f"/{area}/" in row["id"]):
            coll=collections[row["asset"]]
            instance(coll,group,row,row["clear_frame"])
            instance(coll,clip_group,row,row["clear_frame"]-start+5)
        clip.frame_set(1)
    scene.frame_set(1)
    SOURCE.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    path=SOURCE/"ocean_rooftop_farm_v013.blend"
    for image in bpy.data.images:
        if image.source == "FILE":
            assert Path(image.filepath).is_file(), image.filepath
            image.filepath = "//" + os.path.relpath(image.filepath, SOURCE)
    bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True,relative_remap=False)
    plan=read(OLD/"component_plan.json")
    plan.update(version="v013",parent_version="v012",design_clause="SEA-ASSET-R93")
    plan["external_plant_refs"]={key:{"asset_id":coll["asset_id"],"source":coll["source"]}
                                 for key,coll in collections.items()}
    plan["scoped_revision"]={"reference_sha256":"ee2e9f935bd4e50456530773b9ab7401a1d93a8659ba2c6b82a04f1cb4c03809",
                             "placements":len(rows),"regions":list(ISLANDS)}
    write(SOURCE/"component_plan.json",plan)
    layout.update(version="v013",base_version="v012")
    write(SOURCE/"component_instances.json",layout)
    meta=read(OLD/"asset_manifest.json")
    meta.update(version="v013",base_version="v012",source=path.relative_to(ROOT).as_posix(),
                source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), runtime_status="pending",
                wild_growth={"count":len(rows),"sources":plan["external_plant_refs"]})
    write(SOURCE/"asset_manifest.json",meta)
    write(WORK/"placements.json",{"instances":rows})
    print(f"Saved {len(rows)} workshop plant placements in {len(ISLANDS)} repair areas")


main()
