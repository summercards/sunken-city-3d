"""Build a house-only export duplicate, then reopen it to emit individual GLBs."""
import hashlib
import json
import os
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[3]
VERSION = next((v for v in ("v011","v012","v014") if v in sys.argv), "v011" if "structure-v011" in sys.argv else "v010")
SCOPED = VERSION != "v010"
SOURCE = ROOT / "art_source/scenes/ocean_rooftop_farm" / VERSION
FULL = "full-ranch" in sys.argv
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent/"sea-work"))/"rooftop_restoration"
OUT = WORK / ("full-v010" if FULL and not SCOPED else VERSION) / "export"
MAIN_PATH = SOURCE/f"ocean_rooftop_farm_{VERSION}.blend"
DERIVED = OUT/("rooftop_ranch_optimized.blend" if FULL else "rooftop_house_optimized.blend")
SELECTED = {"house_shell","house_corner_patch","house_roof","house_eaves","house_eaves_damage",
            "house_damage","house_pipe","house_pipe_damage","roof_ladder","roof_ladder_damage",
            "entry_assembly","doghouse","rubble","bench","planter","flowers","greens",
            "wall_stone_warm","wall_stone_sand","wall_stone_cool"}
WALL_PREFIXES = ("Deep west return wall","Recessed east return wall","Back wall","Deep grey plaster bay",
                 "Sill masonry","Rebuilt plaster pier","Corner return at recessed entry")
SWAP = Matrix(((1,0,0),(0,0,1),(0,-1,0)))
ANCHOR = Vector((0,0,0) if FULL else (-11.27,2.94,10.56))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pose(obj):
    q = (SWAP @ obj.rotation_euler.to_matrix() @ SWAP.inverted()).to_quaternion()
    return [[round(v,6) for v in SWAP@(obj.location-ANCHOR)],
            [round(v,7) for v in (q.x,q.y,q.z,q.w)],
            [round(v,6) for v in (obj.scale.x,obj.scale.z,obj.scale.y)],not obj.hide_render]


def house_instance(entry):
    if entry["key"] not in SELECTED:
        return False
    if entry["key"] == "rubble":
        return entry["area"] == "house"
    if entry["key"] in {"bench","planter","flowers","greens"}:
        point=entry["after"][0]
        return -16.4<point[0]<-6.9 and -4.6<point[1]<.1 or point[2]>13.7 and point[0]<-8
    return True


def collision_box(obj):
    points=[SWAP @ (obj.matrix_world @ vertex.co) for vertex in obj.data.vertices]
    low,high=([func(v[i] for v in points) for i in range(3)] for func in (min,max))
    return {"name":obj.name,"center":[round((a+b)/2,6) for a,b in zip(low,high)],
            "size":[round(b-a,6) for a,b in zip(low,high)]}


def prepare():
    scene=bpy.context.scene
    instances=json.loads((SOURCE/"component_instances.json").read_text())["instances"]
    if SCOPED:
        scoped = set(json.loads((SOURCE/"component_plan.json").read_text())["scoped_revision"]["keys"])
        placements = [item for item in instances if item["key"] in scoped]
        sampled_frames = range(1,301) if VERSION == "v012" else [1]
    else:
        placements=[item for item in instances if FULL or house_instance(item)]
        sampled_frames=range(1,301) if FULL else sorted({1,191,300} | set(range(111,146)) | set(range(215,297)))
    states={p["name"]:[] for p in placements}
    for frame in sampled_frames:
        scene.frame_set(frame)
        for p in placements:
            obj=scene.objects[p["name"]]
            value=pose(obj)
            if not states[obj.name] or states[obj.name][-1][1:]!=value:
                states[obj.name].append([frame,*value])
    used=sorted({p["key"] for p in placements})
    deck=bpy.data.scenes.new("House component export")
    info={}
    for key in used:
        source=bpy.data.collections["MASTER | "+key]
        deck.collection.children.link(source)
        info[key]={"collision":[collision_box(obj) for obj in source.objects
                                 if is_collision_piece(key,obj.name)]}
    bpy.context.window.scene=deck
    for old in list(bpy.data.scenes):
        if old!=deck:
            bpy.data.scenes.remove(old)
    for key in used:
        source=bpy.data.collections["MASTER | "+key]
        bpy.context.view_layer.update()
        depsgraph=bpy.context.evaluated_depsgraph_get()
        before=after=0
        for obj in source.objects:
            evaluated=obj.evaluated_get(depsgraph)
            mesh=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=depsgraph)
            mesh.calc_loop_triangles()
            before+=len(mesh.loop_triangles)
            temp=bmesh.new()
            temp.from_mesh(mesh)
            bmesh.ops.triangulate(temp,faces=list(temp.faces))
            bmesh.ops.dissolve_degenerate(temp,dist=.000001,edges=list(temp.edges))
            temp.to_mesh(mesh)
            temp.free()
            mesh.calc_loop_triangles()
            after+=len(mesh.loop_triangles)
            obj.modifiers.clear()
            obj.data=mesh
        info[key].update({"before":before,"after":after,"mesh_objects":len(source.objects)})
    for material in bpy.data.materials:
        material.use_nodes=False
    for image in list(bpy.data.images):
        bpy.data.images.remove(image,do_unlink=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED),compress=True)
    manifest={"version":VERSION,"source":MAIN_PATH.relative_to(ROOT).as_posix(),"source_sha256":sha(MAIN_PATH),
              "optimized_sha256":sha(DERIVED),"components":info,
              "placements":[{"name":p["name"],"key":p["key"],"area":p["area"] or "static",
                             "states":states[p["name"]]}
                            for p in placements]}
    if FULL:
        manifest["clips"] = json.loads((SOURCE/"asset_manifest.json").read_text())["clips"]
    (OUT/"runtime_layout.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")


def export():
    manifest=json.loads((OUT/"runtime_layout.json").read_text())
    bpy.ops.wm.open_mainfile(filepath=str(DERIVED))
    for key, info in manifest["components"].items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in bpy.data.collections["MASTER | "+key].objects:
            obj.select_set(True)
        path=OUT/f"{key}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,
                                 export_yup=True,export_animations=False,export_cameras=False,
                                 export_lights=False,export_texcoords=True,export_apply=False)
        data=path.read_bytes()
        payload=json.loads(data[20:20+int.from_bytes(data[12:16],"little")])
        assert not payload.get("images") and not payload.get("textures"),key
        assert len(payload["meshes"])==info["mesh_objects"],key
        assert all("TEXCOORD_0" in primitive["attributes"] for mesh in payload["meshes"]
                   for primitive in mesh["primitives"]),key
        info["glb_sha256"]=sha(path)
    (OUT/"runtime_layout.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    print(f"Exported {len(manifest['components'])} independent GLBs and {len(manifest['placements'])} placements")


def is_collision_piece(key, name):
    if (name.startswith(WALL_PREFIXES)
        or key=="entry_assembly" and name.startswith("Recessed vertical door")
        or key=="doghouse" and name.startswith("Kennel back")):
        return True
    if not FULL:
        return False
    return name.startswith({
        "greenhouse_base": ("Blue side sill", "Teal end sill", "Tall central greenhouse door", "Rear kickboard",
                            "Rough stone side plinth", "Stepped stone end plinth"),
        "greenhouse_debris": ("Twisted blue wall remnant",),
        "tower_support": ("Splayed timber stanchion", "Timber X bracing", "Side diagonal support"),
        "tower_debris": ("Broken braced upright",),
        "tower_tank": ("Blue-green painted steel tank", "Rounded lower lip"),
        "barrels": ("Rounded rain barrel",),
        "patio_table": ("Round honey wood table top", "Round stool seat"),
        "windmill": ("Windmill splayed tripod",),
        "rail_pier": ("Parapet pier",),
        "planter": ("Wide tapered planter",),
        "bench": ("Seat plank",),
        "trellis": ("Storage crate",),
        "clothesline": ("Post footing",),
    }.get(key, ()))


OUT.mkdir(parents=True,exist_ok=True)
if "prepare" in sys.argv:
    prepare()
else:
    export()
