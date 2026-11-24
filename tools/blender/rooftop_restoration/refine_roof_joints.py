"""Revise the split paving and greenhouse base without moving their anchors."""
import hashlib
import json
import os
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).parent))
from geometry import Model
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
OLD = ROOT / "art_source/scenes/ocean_rooftop_farm/v011"
SOURCE = OLD.with_name("v012")
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
KEYS = ("deck_tile_c", "greenhouse_base")
ENTRY_PLANTS = {"Planter.006", "Greens.008", "Greens.009"}
ENTRY_OFFSET = (-1.28, -.20)


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paving(model):
    # Two broad courses and one narrow patch row. The outer footprint follows
    # the existing grid and each stone remains a closed, separately editable mesh.
    courses = (
        (-1.1365, -.338, (-1.0715, .181, 1.0715), ("stone", "cloud")),
        (-.338, .633, (-1.0715, -.368, .724, 1.0715), ("silver", "stone", "sand")),
        (.633, 1.1365, (-1.0715, -.114, 1.0715), ("cloud", "stone")),
    )
    for row, (y0, y1, cuts, tones) in enumerate(courses):
        for column, (x0, x1) in enumerate(zip(cuts, cuts[1:])):
            x0 += .009 if column else 0
            x1 -= .009 if column < len(cuts)-2 else 0
            low = y0 + (.009 if row else 0)
            high = y1 - (.009 if row < len(courses)-1 else 0)
            model.box(f"Staggered paving stone {row+1}.{column+1}",
                      ((x0+x1)/2, (low+high)/2, .1), (x1-x0, high-low, .20),
                      tones[column], bevel=.043, rho=.013, kind="horizontal_cover")


def replace_vertices(obj, transform):
    for v in obj.data.vertices:
        v.co = transform(*v.co)
    obj.data.update()


def greenhouse(model):
    existing = list(model.collection.objects)
    for obj in existing:
        if obj.name.startswith(("Blue side sill", "Blue standing seam panel",
                                "Teal end sill", "Rear kickboard")):
            # Retain the frame height and mounting points. The lower skin is
            # replaced by masonry; the original upper sheet ends at the stone cap.
            replace_vertices(obj, lambda x,y,z: (x, y, .24 + z*(1-.24/.84)))

    for side, cuts in (
        (-1, (-3.28, -2.62, -1.53, -.41, .08, 1.31, 2.04, 3.22)),
        (1, (-3.28, -2.41, -1.94, -.72, .46, 1.03, 2.47, 3.22)),
    ):
        for i, (y0,y1) in enumerate(zip(cuts,cuts[1:])):
            depth = (.275,.339,.255,.315)[i%4]
            swatch = ("stone","gray","sage_gray","silver","sand")[(i + (side+1)*2)%5]
            height = (.226,.217,.228,.216)[(i + (side+1))%4]
            model.box("Rough stone side plinth", (side*(2.64+(.035 if i%3==1 else 0)),(y0+y1)/2,height/2),
                      (depth,y1-y0-.016,height), swatch, bevel=.034, rho=.026, kind="masonry")

    ends = (
        (-3.183, ((-2.45,-1.92,-.81),(.81,1.44,2.45))),
        (3.27, ((-2.45,-1.33,-.51,.62,1.18,2.45),)),
    )
    for end, strips in ends:
        for cuts in strips:
            for i, (x0,x1) in enumerate(zip(cuts,cuts[1:])):
                depth = (.272,.323,.285)[(i + (end>0))%3]
                model.box("Stepped stone end plinth",
                          ((x0+x1)/2,end+(.018 if i%2==0 else -.012),.114),
                          (x1-x0-.018,depth,.228), ("gray","stone","silver")[i%3],
                          bevel=.032, rho=.021, kind="masonry")
    model.box("Low dressed threshold stone", (0,-3.37,.029), (1.53,.418,.058), "silver",
              bevel=.021, rho=.024, kind="horizontal_cover")


def main():
    assert Path(bpy.data.filepath).resolve().parent == OLD
    plan = read(OLD/"component_plan.json")
    plan.update(version="v012", parent_version="v011", design_clause="SEA-ASSET-R92",
                scoped_revision={
                    "keys": list(KEYS),
                    "reference_sha256": "ac9847ffd68c41459718bd23eb9cf927d4f6c5485172b3d330b977ae1b4ce77d",
                    "paving_cells": 15,
                    "contact": {"relation":"clearance", "stone_course_joints_m": [.016,.018],
                                "tile_top_z_local_m": .20},
                })
    for row in plan["components"]:
        if row["key"] in KEYS:
            row["source_revision"] = "v012"
    write(SOURCE/"component_plan.json", plan)
    root = bpy.context.scene
    materials = {role:bpy.data.materials["SEA_"+role] for role in ("Matte","Metal","Gloss","Emission")}
    swatches = {c["name"]:(c["column"],c["row"]) for c in read(PALETTE.with_suffix(".json"))["cells"]}
    for image in bpy.data.images:
        if image.source == "FILE":
            image.filepath = str(PALETTE)
    for key, builder in zip(KEYS,(paving, greenhouse)):
        coll = bpy.data.collections["MASTER | " + key]
        if key == "deck_tile_c":
            for obj in list(coll.objects):
                mesh = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)
                if not mesh.users:
                    bpy.data.meshes.remove(mesh)
        model = Model(coll, materials, swatches)
        builder(model)
        # Keep the established animation origin. The stonework is confined to
        # the same base datum and asymmetric end pieces project in real space.
        sc = bpy.data.scenes.new("Asset | " + key)
        sc.collection.children.link(coll)
        sc.unit_settings.system = "METRIC"
        prior = read(OLD.parent/"v010/component_packages"/key/"asset_manifest.json")
        sc["AssetID"] = prior["asset_id"]
        sc["origin"], sc["front_axis"] = "bottom_center", "-Y"
        folder = SOURCE/"component_packages"/key
        folder.mkdir(parents=True, exist_ok=True)
        package = folder/(key+".blend")
        bpy.data.libraries.write(str(package), {sc}, path_remap="RELATIVE_ALL", fake_user=True, compress=True)
        bpy.data.scenes.remove(sc)
        vertices = [v.co for obj in coll.objects for v in obj.data.vertices]
        bounds = [max(p[i] for p in vertices)-min(p[i] for p in vertices) for i in range(3)]
        for field in ("runtime_path","prefab"):
            prior.pop(field, None)
        prior.update(version="v012", source=package.relative_to(ROOT).as_posix(), source_sha256=sha(package),
                     bounds_m=bounds, form=model.form, form_style="SF-B",
                     materials=sorted({obj.active_material.name for obj in coll.objects}))
        write(folder/"asset_manifest.json", prior)
    layout = read(OLD/"component_instances.json")
    offset = Vector((*ENTRY_OFFSET, 0))
    for entry in layout["instances"]:
        if entry["name"] not in ENTRY_PLANTS:
            continue
        for placement in (entry["before"],entry["after"],*(key[1] for key in entry["keys"])):
            for i, delta in enumerate(ENTRY_OFFSET):
                placement[0][i] += delta
        obj = root.objects[entry["name"]]
        shortlist = next(scene for scene in bpy.data.scenes if scene.get("independent_area") == "construction")
        related = [candidate for candidate in shortlist.objects
                   if candidate.instance_collection == obj.instance_collection and candidate.animation_data
                   and (candidate.location.xy - obj.location.xy).length < .0002]
        assert len(related) == 1, (obj.name, related)
        for instance in (obj,*related):
            animation = instance.animation_data
            curves = animation.action.layers[0].strips[0].channelbag(animation.action_slot).fcurves
            for curve in curves:
                if curve.data_path == "location" and curve.array_index < 2:
                    delta = offset[curve.array_index]
                    for key in curve.keyframe_points:
                        key.co.y += delta
                        key.handle_left.y += delta
                        key.handle_right.y += delta
                    curve.update()
        for scene in bpy.data.scenes:
            if scene == root or scene == shortlist:
                scene.frame_set(scene.frame_current)
    layout.update(version="v012", base_version="v011")
    write(SOURCE/"component_instances.json", layout)
    root.frame_set(1)
    root["roof_joint_revision"] = "v012"
    main_path = SOURCE/"ocean_rooftop_farm_v012.blend"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(main_path), compress=True, relative_remap=True)
    meta = read(OLD/"asset_manifest.json")
    meta.update(version="v012", base_version="v011", source=main_path.relative_to(ROOT).as_posix(),
                source_sha256=sha(main_path), runtime_status="pending")
    write(SOURCE/"asset_manifest.json", meta)


main()
