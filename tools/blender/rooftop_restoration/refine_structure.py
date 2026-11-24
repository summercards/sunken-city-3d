"""Revise the installed ranch's two-storey frame in a new Blender source."""
import hashlib
import json
import math
import os
from pathlib import Path
import random
import sys

import bpy
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from geometry import Model

OLD = ROOT / "art_source/scenes/ocean_rooftop_farm/v010"
SOURCE = OLD.parent / "v011"
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration/v011"
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
MAIN = SOURCE / "ocean_rooftop_farm_v011.blend"
VARIANTS = ("facade_bay", "facade_bay_chipped", "facade_bay_open", "facade_bay_cracked")
KEYS = (*VARIANTS, "corner_pier", "edge_beam", "beam_corner", "base_slab")
REPLACED = {"facade_bay", "corner_pier", "edge_beam", "base_slab"}
PITCH = 4.28
X_EDGE, Y_EDGE = 17.12, 6.42


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def masonry(model, x0, x1, rows, z0, y, tones, variant):
    recessed = ({(2,1)}, {(1,0),(1,1)}, {(0,3),(2,2)}, {(1,2)})[variant]
    for row, heights in enumerate(rows):
        z = z0 + row * .385 + .18
        cursor = x0
        for index, fraction in enumerate(heights):
            width = fraction * (x1-x0)
            depth = .108 if (row,index) in recessed else (.245, .278, .257, .265)[(row+index*3+variant) % 4]
            stone = model.box("Staggered solid ashlar", (cursor + width*.5, y - depth*.5, z),
                              (width-.014, depth, .362), "slate" if (row,index) in recessed
                              else tones[(row*2+index+variant) % len(tones)],
                              bevel=.047, rho=.026, kind="masonry")
            stone["bond_course"] = row
            cursor += width


def bay(model, variant):
    # The brickwork fits in front of a backing wall. Deep side returns connect it to the inset sash.
    masonry(model, -1.87, 1.87, ((.27,.24,.25,.24), (.15,.32,.29,.24), (.25,.28,.32,.15)),
            .147, -.064, ("stone", "gray", "silver", "stone", "sage_gray"), variant)
    model.box("Backing behind the masonry courses", (0, .097, .671), (3.724, .30, 1.25), "gray", bevel=.041)
    for side in (-1, 1):
        x = side * 1.70
        model.box("Deep tapered masonry jamb", (x,-.025,2.31), (.334,.54,2.39), "stone", bevel=.039)
        model.box("Square projecting sill", (side * .81,-.163,1.34), (1.58,.50,.142), "silver",
                  bevel=.032, kind="opening")
    model.box("Central dressed stone jamb", (0,.075,2.38), (.105,.48,2.12), "sage_gray", bevel=.022)
    model.box("Recessed interior shadow", (0,.232,2.37), (3.28,.062,2.15), "slate", bevel=.018)
    for i, x in enumerate((-.81,.81)):
        model.box("Inset lower sash rail", (x,-.019,1.49), (1.52,.096,.095), "steel",
                  bevel=.014, kind="opening")
        model.box("Inset upper sash rail", (x,-.016,3.37), (1.52,.10,.093), "steel",
                  bevel=.014, kind="opening")
        for side in (-1,1):
            model.box("Inset vertical sash rail", (x+side*.722,-.016,2.43), (.085,.10,1.76), "steel",
                      bevel=.014, kind="opening")
        panes = (
            (((-.668,1.55),(.668,1.55),(.668,1.77),(.30,1.81),(.12,2.48),(-.11,2.25),(-.33,1.91),(-.668,2.10)),),
            (((-.667,3.315),(.667,3.315),(.667,2.64),(.26,2.95),(.05,2.47),(-.21,2.62),(-.667,2.29)),),
            (),
            (((-.662,1.55),(.667,1.55),(.667,3.315),(.18,3.315),(.042,2.88),(.19,2.48),(-.22,2.09),(-.411,1.8),(-.662,1.73)),
             ((-.665,1.85),(-.451,1.88),(-.26,2.18),(.073,2.50),(-.06,2.90),(.078,3.315),(-.665,3.315))),
            (((-.668,1.55),(-.10,1.55),(-.36,1.75),(-.52,2.34),(-.668,2.48)),
             ((.26,3.315),(.668,3.315),(.668,2.91),(.48,3.07))),
        )
        profile = ((0,3),(1,4),(2,0),(4,2))[variant][i]
        for j, outline in enumerate(panes[profile]):
            model.panel("Fractured glass with exposed thickness", [(x+u,.035,z) for u,z in outline],
                        .029, ("deepblue","ocean","blue")[(variant+i+j)%3], role="Gloss", bevel=.009)
    model.box("Beveled continuous window lintel", (0,-.034,3.56), (3.72,.59,.28), "silver", bevel=.044)
    model.box("Recessed upper masonry panel", (0,.07,4.002), (3.72,.36,.604), "gray", bevel=.040)
    for u, z, w, h in (
        ((1.54,3.93,.39,.22),), ((-1.37,3.97,.57,.30),(.59,3.97,.31,.16)),
        ((.26,4.02,.42,.15),), (),
    )[variant]:
        model.panel("Irregular recess shadow at damaged render",
                    [(u+w*dx,-.119,z+h*dz) for dx,dz in ((-.5,-.15),(-.32,-.49),(.39,-.30),(.5,.14),(.11,.33),(-.26,.48))],
                    .021, "slate", bevel=.008)


def pier(model):
    model.box("Pinned stone column foot", (0,0,.17), (.50,.50,.34), "gray", bevel=.075)
    model.box("Tapered half metre column shaft", (0,0,2.116), (.50,.50,3.532), "stone", bevel=.095)
    model.box("Beveled bearing capital", (0,0,4.106), (.50,.50,.428), "plaster", bevel=.092)


def beam(model):
    model.box("Continuous cast beam", (0,0,.28), (4.268,.64,.56), "stone", bevel=.045, rho=.010)
    model.box("Rebated lower beam fascia", (0,-.345,.181), (4.242,.046,.163),
              "sage_gray", bevel=.017, rho=.015)


def corner_beam(model):
    model.box("Corner beam bearing block", (0,0,.28), (.64,.64,.56),
              "stone", bevel=.045, rho=.017)


def slab(model):
    model.box("Reinforced 200 mm slab", (0,0,.10), (34.72,13.82,.20), "slate",
              bevel=.044, rho=.010, kind="horizontal_cover")


def main():
    assert Path(bpy.data.filepath).resolve() == OLD / "ocean_rooftop_farm_v010.blend"
    WORK.mkdir(parents=True, exist_ok=True)
    if not (WORK / "before_mcp.blend").exists():
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK / "before_mcp.blend"), copy=True, compress=True)
    original = read(OLD / "component_plan.json")
    plan = {**original, "version": "v011", "parent_version": "v010", "design_clause": "SEA-ASSET-R91",
            "scoped_revision": {"keys": list(KEYS), "structural_pitch_m": PITCH,
                                "reference_sha256": {
                                    "frame": "a2540bdc8f61f662af5de5477a6b92b99f6dc81a9fcf021be369370aa4799c00",
                                    "damage": "8cb92bad33bcb8f459b54625491935f2babaa1a03762b0b269a5ed79740b51d4",
                                },
                                "roof_level_retained": True}}
    plan["components"] = [dict(row) for row in original["components"]]
    by_key = {row["key"]:row for row in plan["components"]}
    for key,label in zip(VARIANTS[1:],("掉角和斜裂窗跨","空窗和缺砖窗跨","残存角片窗跨")):
        plan["components"].append(dict(by_key["facade_bay"], key=key, name=label,
                                       asset_id="SEA-SCENE-ORF7-"+key.upper().replace("_","-")))
    plan["components"].append(dict(by_key["edge_beam"], key="beam_corner", name="转角梁承托块",
                                   asset_id="SEA-SCENE-ORF7-BEAM-CORNER", component_family="beam_joint"))
    assert len(plan["components"]) == 50
    for row in plan["components"]:
        if row["key"] in KEYS:
            row["source_revision"] = "v011"
    write(SOURCE / "component_plan.json", plan)
    layout = read(OLD / "component_instances.json")
    old_main = bpy.context.scene
    property_group = next(group for group in old_main.collection.children if group.name.startswith("01 "))
    shared = bpy.data.collections["COMMON | static modules"]
    materials = {role: bpy.data.materials["SEA_" + role] for role in ("Matte", "Metal", "Gloss", "Emission")}
    swatches = {c["name"]:(c["column"],c["row"]) for c in read(PALETTE.with_suffix(".json"))["cells"]}
    builders = {key: (lambda model, variant=i: bay(model, variant)) for i,key in enumerate(VARIANTS)}
    builders.update(corner_pier=pier, edge_beam=beam, beam_corner=corner_beam, base_slab=slab)
    offsets = {}
    for key in KEYS:
        coll = bpy.data.collections.get("MASTER | " + key) or bpy.data.collections.new("MASTER | " + key)
        for obj in list(coll.objects):
            mesh = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        model = Model(coll, materials, swatches)
        builders[key](model)
        vertices = [v.co for obj in coll.objects for v in obj.data.vertices]
        low = Vector(tuple(min(v[i] for v in vertices) for i in range(3)))
        high = Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
        origin = Vector(((low.x+high.x)*.5,(low.y+high.y)*.5,low.z))
        offsets[key] = origin
        for obj in coll.objects:
            for vertex in obj.data.vertices:
                vertex.co -= origin
            obj.data.update()
        package_dir = SOURCE / "component_packages" / key
        package_dir.mkdir(parents=True, exist_ok=True)
        prior_key = "facade_bay" if key in VARIANTS else "edge_beam" if key=="beam_corner" else key
        meta = read(OLD / "component_packages" / prior_key / "asset_manifest.json")
        sc = bpy.data.scenes.new("Asset | " + key)
        sc.collection.children.link(coll)
        sc.unit_settings.system = "METRIC"
        sc["AssetID"] = meta["asset_id"]
        sc["origin"], sc["front_axis"] = "bottom_center", "-Y"
        package = package_dir / (key+".blend")
        bpy.data.libraries.write(str(package), {sc}, path_remap="RELATIVE_ALL", fake_user=True, compress=True)
        bpy.data.scenes.remove(sc)
        for name in ("runtime_path", "prefab"):
            meta.pop(name, None)
        entry = next(row for row in plan["components"] if row["key"] == key)
        meta.update(**entry, source=package.relative_to(ROOT).as_posix(), source_sha256=sha(package),
                    version="v011", bounds_m=list(high-low), authoring_origin_before_recenter=list(origin),
                    materials=sorted({obj.active_material.name for obj in coll.objects}),
                    form_style="SF-B", form=model.form, collection=coll.name)
        write(package_dir / "asset_manifest.json", meta)

    old_instances = layout["instances"]
    layout["instances"] = [item for item in old_instances if item["key"] not in REPLACED]
    for row in old_instances:
        if row["key"] in REPLACED:
            bpy.data.objects.remove(old_main.objects[row["name"]], do_unlink=True)
    asset_ids = {row["key"]:row["asset_id"] for row in plan["components"]}

    def add(key, name, point, yaw=0, scale_x=1.0, scale_z=1.0):
        rotation = Euler((0,0,math.radians(yaw)))
        scale = (scale_x,1.0,scale_z)
        origin = offsets[key]
        loc = Vector(point) + rotation.to_matrix() @ Vector((origin.x*scale_x,origin.y,origin.z*scale_z))
        obj = bpy.data.objects.new(name, None)
        property_group.objects.link(obj)
        shared.objects.link(obj)
        obj.instance_type = "COLLECTION"
        obj.instance_collection = bpy.data.collections["MASTER | " + key]
        obj.location, obj.rotation_euler, obj.scale = loc, rotation, scale
        obj.empty_display_size = .17
        obj["asset_key"], obj["area"], obj["placement_id"] = key,"static",obj.name
        pose = [list(loc),list(rotation),list(scale),True]
        layout["instances"].append(dict(name=obj.name,key=key,asset_id=asset_ids[key],area=None,
                                        before=pose,after=pose,keys=[]))

    rng = random.Random(462)
    previous_floor = []
    for level, floor in enumerate((0.0, 5.10),1):
        beam_z = floor + 4.532
        beam_height = .56 if level == 1 else .36
        root_z = floor+.20+.008
        add("base_slab", f"Frame L{level} slab", (0,0,floor))
        columns = [(i*PITCH,y) for y in (-Y_EDGE,Y_EDGE) for i in range(-4,5)]
        columns.extend((x,y) for x in (-X_EDGE,X_EDGE) for y in (-2.14,2.14))
        scale_z = (beam_z-.012-root_z)/4.32
        for index, (x,y) in enumerate(columns):
            add("corner_pier", f"Frame L{level} column {index+1:02d}", (x,y,root_z),scale_z=scale_z)
        runs = [(f"F{i+1:02d}", ((i-3.5)*PITCH,-Y_EDGE),0) for i in range(8)]
        runs += [(f"B{i+1:02d}",((i-3.5)*PITCH,Y_EDGE),180) for i in range(8)]
        runs += [(f"W{i+1:02d}",(-X_EDGE,(i-1)*PITCH),-90) for i in range(3)]
        runs += [(f"E{i+1:02d}",(X_EDGE,(i-1)*PITCH),90) for i in range(3)]
        current_floor = []
        for index,(label, (x,y), yaw) in enumerate(runs):
            blocked = set(current_floor[-1:])
            if previous_floor:
                blocked.add(previous_floor[index])
            choices = [key for key in VARIANTS if key not in blocked]
            variant = rng.choices(choices, weights=[1 if key in current_floor[-3:] else 4 for key in choices])[0]
            current_floor.append(variant)
            add(variant, f"Frame L{level} bay {label}", (x,y,root_z),yaw)
            # The end beam meets a bearing block on the corner column with a 12 mm joint.
            axis = Euler((0,0,math.radians(yaw))).to_matrix() @ Vector((1,0,0))
            center = Vector((x,y,beam_z))
            for sign in (-1,1):
                end = center + sign * axis * PITCH*.5
                if abs(abs(end.x)-X_EDGE)<.0001 and abs(abs(end.y)-Y_EDGE)<.0001:
                    center -= sign * axis * .16
                    add("edge_beam", f"Frame L{level} beam {label}", center,yaw,
                        scale_x=3.948/4.268,scale_z=beam_height/.56)
                    break
            else:
                add("edge_beam", f"Frame L{level} beam {label}", center,yaw,scale_z=beam_height/.56)
        for x in (-X_EDGE,X_EDGE):
            for y in (-Y_EDGE,Y_EDGE):
                add("beam_corner", f"Frame L{level} beam corner {x:+.2f} {y:+.2f}",
                    (x,y,beam_z),scale_z=beam_height/.56)
        previous_floor = current_floor

    # The raised west terrace retains its existing tile tops. Its visible
    # perimeter gets a shallow fascia set below the rail feet.
    for y, yaw in ((-6.60,0),(6.60,180)):
        for index in range(3):
            x = -15.11 + 3.625 * index
            add("edge_beam", f"Raised terrace fascia {yaw} {index}", (x,y,10.006),yaw,
                scale_x=3.613/4.268,scale_z=.462/.56)
    for index in range(3):
        y = (index-1)*4.28 - (index-1)*.03
        add("edge_beam", f"Raised terrace fascia west {index}",(-16.90,y,10.006),-90,
            scale_x=(4.208 if index!=1 else 4.268)/4.268,scale_z=.462/.56)

    layout.update(version="v011", base_version="v010")
    write(SOURCE/"component_instances.json", layout)
    for image in bpy.data.images:
        if image.source == "FILE":
            image.filepath = str(PALETTE)
    old_main["structural_revision"] = "v011"
    old_main.frame_set(300)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(MAIN), compress=True, relative_remap=True)
    meta = read(OLD/"asset_manifest.json")
    meta["components"] = [row["key"] for row in plan["components"]]
    meta.update(version="v011", source=MAIN.relative_to(ROOT).as_posix(), source_sha256=sha(MAIN),
                instances=len(layout["instances"]), runtime_status="pending", base_version="v010")
    write(SOURCE/"asset_manifest.json", meta)
    print(f"Saved {MAIN.name}, {len(layout['instances'])} placements")


main()
