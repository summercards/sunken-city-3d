"""Derive a 5 by 2.5 metre berth using the construction kit's palette."""
import hashlib
import os
from math import pi
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/scenes/ocean_building_kit/v002/building_kit.blend"
SUNNY = ROOT / "art_source/scenes/sunny_bloom_retreat/v008/components"
BOLLARD = SUNNY / "bollard/bollard.blend"
FENDER = SUNNY / "hanging_tire/hanging_tire.blend"
PACKAGE = ROOT / "art_source/scenes/ocean_building_kit/v004/workshop_dock"
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "workshop_dock"
OUTPUT = ROOT / "godot/assets/models/building_kit/workshop_dock/v004/workshop_dock.glb"


def copy_fixtures(scene, path, names, offsets, family, scale, rotation, material=None):
    with bpy.data.libraries.load(str(path)) as (library, imported):
        assert all(name in library.objects for name in names)
        imported.objects = list(names)
    for index, offset in enumerate(offsets, 1):
        for original, part in zip(imported.objects, names.values(), strict=True):
            obj = original.copy()
            obj.data = original.data.copy()
            obj.parent = None
            obj.matrix_world = Matrix.Translation(Vector(offset)) @ rotation @ Matrix.Scale(scale, 4)
            obj.name = f"{family}{index:02d}_{part}"
            if material is not None:
                obj.data.materials[0] = material
            scene.collection.objects.link(obj)
    return imported.objects[0].data.materials[0]


def main():
    source_hashes = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in (SOURCE, BOLLARD, FENDER)}
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    originals = list(bpy.data.collections["制作_5×5米木平台"].objects)
    scene = bpy.data.scenes.new("Workshop dock")
    bpy.context.window.scene = scene
    boards = (originals[0], originals[2], originals[5])
    joists = originals[6:]
    rotation = Matrix.Rotation(pi / 2, 4, "Z")
    for index, original in enumerate((*boards, *joists)):
        obj = original.copy()
        obj.data = original.data.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.transform(rotation @ original.matrix_basis)
        if index < len(boards):
            low = min(v.co.y for v in obj.data.vertices)
            high = max(v.co.y for v in obj.data.vertices)
            offsets = (-1.25 - low, -(low + high) / 2, 1.25 - high)
            obj.data.transform(Matrix.Translation(Vector((0, offsets[index], 0))))
            assert abs(high - low - original.dimensions.x) < 0.001
            obj.name = f"Plank_{index + 1}"
        else:
            obj.data.transform(Matrix.Diagonal(Vector((1.0, 0.5, 1.0, 1.0))))
            obj.name = f"Joist_{index - len(boards) + 1}"
        scene.collection.objects.link(obj)
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    points = [obj.matrix_world @ v.co for obj in scene.objects for v in obj.data.vertices]
    for axis, span in enumerate((5.0, 2.5, 0.5)):
        actual = max(p[axis] for p in points) - min(p[axis] for p in points)
        assert abs(actual - span) < 0.001, (axis, actual)
    sunny_material = copy_fixtures(scene, BOLLARD, {"bollard_mesh": "Post"},
        [(x, -0.75, 0) for x in (-1.99, 1.99)], "Bollard", 1.725, Matrix.Identity(4))
    sunny_material.name = "SEA_SunnyMatte"
    copy_fixtures(scene, FENDER, {
        "饱满橡胶轮胎": "Tire", "胎侧环纹": "SidewallA",
        "胎侧环纹.001": "SidewallB", "轮胎悬挂绳": "Rope",
    }, [(x, -1.195, -1.16) for x in (-1.92, -0.64, 0.64, 1.92)],
        "Fender", 1.15, Matrix.Rotation(pi, 4, "Z"), sunny_material)
    for obj in scene.objects:
        if obj.name.endswith("_Rope"):
            # The sprung end ties down to this lower deck, with the loop on the tire untouched.
            for vertex in obj.data.vertices:
                inside = min(1.0, max(0.0, (-vertex.co.y - 0.10) / 0.39))
                vertex.co.z -= 0.45 * inside * inside
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    for folder in (PACKAGE, WORK, OUTPUT.parent):
        folder.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(PACKAGE / "workshop_dock.blend"), compress=True)
    derived = WORK / "workshop_dock_export.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(derived), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(derived))
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_yup=True,
        export_image_format="NONE", export_animations=False, export_cameras=False, export_lights=False)
    assert all(hashlib.sha256(path.read_bytes()).hexdigest() == sha for path, sha in source_hashes.items())


if __name__ == "__main__":
    main()
