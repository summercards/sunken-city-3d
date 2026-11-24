"""Export revised solar cabin components and bake the Blender assembly tracks."""

import hashlib
import json
import os
from pathlib import Path
import struct

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "art_source/scenes/sunny_bloom_retreat/v008"
SOURCE = SOURCE_DIR / "sunny_bloom_retreat.blend"
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "sunroom_runtime_1_6"
OPTIMIZED = WORK / "solar_cabin_runtime_1_6.blend"
OUTPUT = ROOT / "godot/assets/models/facilities/solar_cabin/v1_6"
WRAPPERS = ROOT / "godot/scenes/components/solar_cabin/v1_6"
LEGACY_RUNTIME = OUTPUT.parent / "instances.json"
FIT = Matrix.Translation(Vector((5.128, 1.368, .704))) @ Matrix.Scale(1.15, 4)
AXIS = Matrix.Rotation(-1.5707963267948966, 4, "X")
ASSEMBLY = "阳光房 | 组件从上方落装"
MODULES = {
    "rear_building": "后部方形建筑",
    "solar_room": "前部倾斜太阳能房",
    "front_platform": "前方可行动平台-酒红",
    "bridge": "栈桥-暖木",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def resource(path):
    return "res://" + path.relative_to(ROOT / "godot").as_posix()


def glb_name(key):
    return "parapet_open_v2.glb" if key == "parapet" else f"{key}.glb"


def transform(obj):
    return FIT @ AXIS @ obj.matrix_world @ AXIS.inverted()


def infer_module(obj, key):
    if "龙骨" in obj.name:
        return "bridge"
    if key in {"deck_rail", "float_shell"}:
        return "front_platform"
    if key == "eave_bracket":
        return "solar_room"
    if key == "parapet" or "端柱" in obj.name or key in {"wall_skirt", "service_box"}:
        return "rear_building"
    raise ValueError(f"Missing module for {obj.name}")


def build_layout(scene, assembly, catalog, plan):
    old_source = json.loads((SOURCE_DIR / "component_instances.json").read_text())["instances"]
    old_runtime = json.loads(LEGACY_RUNTIME.read_text())
    legacy_objects = {row["name"]: (i, row) for i, row in enumerate(old_source)}
    motion = {o["静态实例"]: o for o in assembly.objects if "静态实例" in o}
    revised = {row["key"] for row in plan["reworked_masters"]}
    revised.update(row["key"] for row in plan["source_local_masters"])
    new_components = {row["collection"]: row["key"] for row in plan["source_local_masters"]}
    by_collection = {row["collection"]: row for row in catalog}
    exports = {}
    instances = []
    for obj in scene.objects:
        col = obj.instance_collection
        if col is None:
            continue
        if col.name in new_components:
            key = new_components[col.name]
            asset_id, category = plan["asset_id"], "structure"
        else:
            row = by_collection[col.name]
            key, asset_id, category = (row[k] for k in ("key", "asset_id", "category"))
        index, old = legacy_objects.get(obj.name, (None, None))
        serial = f"{index:03}" if index is not None else f"new_{len(instances):03}"
        module = old["module"] if old is not None else infer_module(obj, key)
        row = dict(component=key, asset_id=asset_id, category=category, module=module,
                   instance_id=f"solar_cabin/{serial}", transform=[list(m) for m in transform(obj)][:3])
        if key in revised:
            exports[key] = col
            row["component_scene"] = resource(WRAPPERS / f"{key}.tscn")
        if key == "umbrella":
            row["wind_animation"] = True
        o = motion[obj.name]
        start, end = o["落装"]
        if key != "cooler":
            row["drop"] = [start, end]
        instances.append(row)
    tracks = [(row, motion[obj.name]) for row, obj in
              zip(instances, [o for o in scene.objects if o.instance_collection], strict=True)
              if "drop" in row]
    bpy.context.window.scene = assembly
    for frame in range(1, 226):
        assembly.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for row, obj in tracks:
            start, end = row["drop"]
            if frame == 1:
                row["rise"] = []
            if start <= frame <= end:
                height = transform(obj.evaluated_get(depsgraph)).translation.y - row["transform"][1][3]
                row["rise"].append(round(max(0, height), 6))
    for row, _ in tracks:
        assert row["rise"][0] > 4 and row["rise"][-1] < .0001, row["instance_id"]
    plants = [dict(row, instance_id=row.get("instance_id", f"solar_cabin/{i:03}"))
              for i, row in enumerate(old_runtime["instances"]) if row["category"] == "flora"]
    return instances + plants, exports


def prepare_export_scene(exports):
    scene = bpy.data.scenes.new("Solar Cabin 1.6 optimized output")
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 121
    bpy.context.window.scene = scene
    for key, source in exports.items():
        collection = bpy.data.collections.new("Output_" + key)
        scene.collection.children.link(collection)
        still = []
        deform = []
        walking = []
        for ob in source.objects:
            if ob.type != "MESH":
                continue
            if key == "parapet" and ob.name == "夹层玻璃":
                continue
            obj = ob.copy()
            obj.data = ob.data.copy()
            obj.parent = None
            obj.matrix_world = ob.matrix_basis.copy()
            collection.objects.link(obj)
            if key == "terrace" and ob.name.startswith("露台木板"):
                walking.append(obj)
            elif obj.data.shape_keys:
                deform.append(obj)
            else:
                still.append(obj)
        for group, suffix in ((still, "static"), (deform, "fabric"), (walking, "walk_surface")):
            if not group:
                continue
            bpy.ops.object.select_all(action="DESELECT")
            for obj in group:
                obj.select_set(True)
            active = group[0]
            bpy.context.view_layer.objects.active = active
            if len(group) > 1:
                bpy.ops.object.join()
            active.name = f"{key}_{suffix}"
            active.data.name = active.name
            if active.data.shape_keys:
                keys = active.data.shape_keys
                keys.animation_data.action.name = "wind"
                keys.key_blocks[1].name = "gust"
                keys.key_blocks[2].name = "return"
    for other in tuple(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED), compress=True)


def export_glb(key):
    bpy.ops.object.select_all(action="DESELECT")
    collection = bpy.data.collections["Output_" + key]
    for obj in collection.objects:
        obj.select_set(True)
    wind = key == "umbrella"
    path = OUTPUT / glb_name(key)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_image_format="NONE", export_cameras=False, export_lights=False,
        export_yup=True, export_animations=wind, export_frame_range=True,
        export_animation_mode="ACTIVE_ACTIONS",
        export_nla_strips_merged_animation_name="wind",
        export_optimize_animation_size=False, export_morph=wind,
    )
    with path.open("rb") as handle:
        handle.read(12)
        length, _ = struct.unpack("<II", handle.read(8))
        gltf = json.loads(handle.read(length))
    assert not gltf.get("textures") and not gltf.get("images")
    channels = [(clip, channel) for clip in gltf.get("animations", []) for channel in clip["channels"]]
    if wind:
        assert len(channels) == 1 and channels[0][0]["name"] == "wind", channels
        assert channels[0][1]["target"]["path"] == "weights"
    triangles = sum(gltf["accessors"][p["indices"]]["count"] // 3
                    for mesh in gltf["meshes"] for p in mesh["primitives"])
    return dict(glb=str(path.relative_to(ROOT)), sha256=sha(path), triangles=triangles,
                materials=[m["name"] for m in gltf["materials"]])


def wrapper(key, asset_id):
    path = WRAPPERS / f"{key}.tscn"
    path.write_text(
        f'[gd_scene format=3]\n\n'
        f'[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]\n'
        f'[ext_resource type="PackedScene" path="{resource(OUTPUT / glb_name(key))}" id="visual"]\n\n'
        f'[node name="{key}" type="Node3D"]\n'
        f'script = ExtResource("bind")\n'
        f'asset_id = "{asset_id}"\n'
        f'metadata/asset_id = "{asset_id}"\n\n'
        f'[node name="Visual" parent="." instance=ExtResource("visual")]\n',
        encoding="utf-8",
    )
    return str(path.relative_to(ROOT))


def main():
    for directory in (WORK, OUTPUT, WRAPPERS):
        directory.mkdir(parents=True, exist_ok=True)
    original_hash = sha(SOURCE)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    assembly = bpy.data.scenes[ASSEMBLY]
    plan = json.loads((SOURCE_DIR / "structure_revision_20261120.json").read_text())
    catalog = json.loads((SOURCE_DIR / "catalog.json").read_text())["components"]
    instances, exports = build_layout(scene, assembly, catalog, plan)
    prepare_export_scene(exports)
    bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED))
    components = {}
    for key in sorted(exports):
        asset_id = next(row["asset_id"] for row in instances if row["component"] == key)
        components[key] = dict(export_glb(key), prefab=wrapper(key, asset_id), asset_id=asset_id)
    assert sha(SOURCE) == original_hash
    write_json(OUTPUT / "instances.json", dict(
        version="1.6", source_version="v008", anchor_godot=[5.128, 1.368, .704],
        scale=1.15, front_godot=[0, 0, 1], deck_height=2.15,
        animation=dict(name="construction", fps=30, end_frame=225), instances=instances,
    ))
    write_json(OUTPUT / "export_manifest.json", dict(
        version="1.6", source=str(SOURCE.relative_to(ROOT)), source_sha256=original_hash,
        optimized_sha256=sha(OPTIMIZED), components=components,
        drop_tracks=sum("drop" in row for row in instances), wind_seconds=4.0,
        scene_modules=list(MODULES),
    ))


if __name__ == "__main__":
    main()
