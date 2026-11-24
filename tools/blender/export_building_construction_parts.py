"""Export the ten five-meter recipes from their unmerged Blender collections."""

import hashlib
import json
import os
from pathlib import Path
import struct

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/scenes/ocean_building_kit/v002"
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "building_construction"
OUTPUT = ROOT / "godot/assets/models/building_kit/construction_v003"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, catalog):
    bpy.ops.wm.open_mainfile(filepath=str(source))
    output = bpy.data.scenes.new("Construction parts")
    bpy.context.window.scene = output
    for component in catalog:
        collection = bpy.data.collections.new(component["id"])
        output.collection.children.link(collection)
        raw = bpy.data.collections[component["source_collection"]]
        for index, part in enumerate(raw.objects):
            assert part.type == "MESH" and part.data.uv_layers.active.name == "PaletteUV"
            obj = part.copy()
            obj.data = part.data.copy()
            obj.parent = None
            obj.matrix_world = part.matrix_basis.copy()
            prefix = "part"
            if component["id"] == "stairs_5m":
                prefix = "StairTread" if part.name.startswith("踏步_") else "StairSupport"
            obj.name = f"{prefix}_{index + 1:02d}"
            obj.data.name = obj.name
            collection.objects.link(obj)
        points = [obj.matrix_basis @ vertex.co for obj in collection.objects for vertex in obj.data.vertices]
        for boundary, fn in (("min", min), ("max", max)):
            target = Vector(component["bounds"][boundary])
            actual = Vector([fn(point[i] for point in points) for i in range(3)])
            assert (target - actual).length < .001, (component["id"], target, actual)
    for scene in tuple(bpy.data.scenes):
        if scene != output:
            bpy.data.scenes.remove(scene)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    derived = WORK / "construction_parts.blend"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(derived), compress=True)
    return derived


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = SOURCE / "building_kit.blend"
    source_hash = digest(source)
    catalog = json.loads((SOURCE / "catalog.json").read_text())["components"]
    derived = prepare(source, catalog)
    bpy.ops.wm.open_mainfile(filepath=str(derived))
    components = {}
    for component in catalog:
        key = component["id"]
        bpy.ops.object.select_all(action="DESELECT")
        objects = bpy.data.collections[key].objects
        for obj in objects:
            obj.select_set(True)
        path = OUTPUT / f"{key}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
            export_yup=True, export_image_format="NONE", export_animations=False,
            export_cameras=False, export_lights=False)
        data = path.read_bytes()
        length, _ = struct.unpack_from("<II", data, 12)
        gltf = json.loads(data[20:20 + length])
        assert not gltf.get("images") and not gltf.get("textures"), key
        assert sum("mesh" in node for node in gltf["nodes"]) == len(objects), key
        components[key] = {"asset_id":component["asset_id"],"elements":len(objects),
            "path":str(path.relative_to(ROOT)), "sha256":digest(path)}
    assert digest(source) == source_hash
    manifest = {"version":"v003", "source":str(source.relative_to(ROOT)),
        "source_sha256":source_hash, "optimized_sha256":digest(derived), "components":components}
    (OUTPUT / "export_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
