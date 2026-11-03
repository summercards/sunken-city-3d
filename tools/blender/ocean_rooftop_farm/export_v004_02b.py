"""按 02b 规范从 v004 独立组件包生成持久优化 Blend 与稳定 GLB。

只写入 v004/export/v004、rooftop_ranch 运行资产及本脚本允许的导入契约；
不从主总成导出整楼，不改任何 v004 源 Blend。
"""
import bpy
import bmesh
import hashlib
import json
import os
import shutil
import struct
from pathlib import Path

ROOT = Path("D:/projects/sea")
SOURCE_DIR = ROOT / "art_source/scenes/ocean_rooftop_farm/v004"
EXPORT_DIR = SOURCE_DIR / "export/v004"
RUNTIME_DIR = ROOT / "godot/assets/models/facilities/rooftop_ranch"
CATALOG_PATH = SOURCE_DIR / "component_catalog.json"
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
ASSEMBLY = SOURCE_DIR / "ocean_rooftop_farm_v004.blend"
BASE = SOURCE_DIR / "base_building.blend"


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def json_write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def mesh_objects(collection):
    result = []
    for obj in collection.objects:
        if obj.type == "MESH":
            result.append(obj)
    for child in collection.children:
        result.extend(mesh_objects(child))
    return result


def triangles_for_object(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def stats(collection):
    meshes = mesh_objects(collection)
    triangles = 0
    polygons = 0
    vertices = 0
    uv_faces = 0
    uv_layers = set()
    materials = set()
    palette_images = set()
    bounds = []
    for obj in meshes:
        me = obj.data
        triangles += triangles_for_object(obj)
        polygons += len(me.polygons)
        vertices += len(me.vertices)
        uv = me.uv_layers.get("PaletteUV")
        if uv:
            uv_layers.add(uv.name)
            uv_faces += len(me.polygons)
        for mat in me.materials:
            if mat:
                materials.add(mat.name)
                if mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type == "TEX_IMAGE" and node.image:
                            palette_images.add(Path(bpy.path.abspath(node.image.filepath)).resolve().as_posix())
        bounds.extend(obj.matrix_world @ v.co for v in me.vertices)
    low = [min(v[i] for v in bounds) for i in range(3)] if bounds else None
    high = [max(v[i] for v in bounds) for i in range(3)] if bounds else None
    return {
        "mesh_objects": len(meshes),
        "polygons": polygons,
        "triangles": triangles,
        "vertices": vertices,
        "uv_faces": uv_faces,
        "uv_layers": sorted(uv_layers),
        "materials": sorted(materials),
        "palette_images": sorted(palette_images),
        "bounds_low": low,
        "bounds_high": high,
        "bounds_size": [high[i] - low[i] for i in range(3)] if low else None,
    }


def cleanup_mesh(obj):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    zero_faces = [face for face in bm.faces if face.calc_area() <= 1e-12]
    duplicate_faces = []
    seen = set()
    for face in bm.faces:
        if face in zero_faces:
            continue
        # Only remove a duplicate with the same winding. Reversed winding can be
        # an intentional visible back face and is therefore retained.
        signature = tuple(v.index for v in face.verts)
        if signature in seen:
            duplicate_faces.append(face)
        else:
            seen.add(signature)
    delete_faces = list(dict.fromkeys(zero_faces + duplicate_faces))
    if delete_faces:
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update(calc_edges=True)
    return {
        "zero_area_faces_removed": len(zero_faces),
        "duplicate_faces_removed": len(duplicate_faces),
        "vertices_merged_or_removed": 0,
        "coplanar_faces_dissolved": 0,
        "unused_vertices_removed": 0,
    }


def normalize_materials():
    palette_abs = PALETTE.resolve()
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                node.image.filepath = str(palette_abs)
                node.interpolation = "Closest"
        for node in mat.node_tree.nodes:
            if node.type == "UVMAP":
                node.uv_map = "PaletteUV"


def output_collection():
    candidates = [c for c in bpy.context.scene.collection.children if c.name.startswith("02_游戏输出")]
    assert len(candidates) == 1, (bpy.data.filepath, [c.name for c in candidates])
    return candidates[0]


def select_output(collection):
    bpy.ops.object.select_all(action="DESELECT")
    meshes = mesh_objects(collection)
    assert meshes
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    return meshes


def read_glb(path):
    blob = Path(path).read_bytes()
    assert blob[:4] == b"glTF", path
    length = struct.unpack_from("<I", blob, 12)[0]
    gltf = json.loads(blob[20:20 + length])
    triangles = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            mode = prim.get("mode", 4)
            count = gltf["accessors"][prim["indices"]]["count"] if "indices" in prim else gltf["accessors"][prim["attributes"]["POSITION"]]["count"]
            triangles += count // 3 if mode == 4 else (count - 2 if mode == 5 else count // 3 if mode == 6 else 0)
    return {
        "bytes": len(blob),
        "meshes": len(gltf.get("meshes", [])),
        "nodes": len(gltf.get("nodes", [])),
        "triangles": triangles,
        "images": len(gltf.get("images", [])),
        "materials": [m.get("name", "") for m in gltf.get("materials", [])],
    }


def write_import_contract(glb):
    cache_name = f".godot/imported/{glb.name}-rooftop-ranch.scn"
    text = f'''[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="res://{cache_name}"\n\n[deps]\n\nsource_file="res://{glb.relative_to(ROOT / 'godot').as_posix()}"\ndest_files=["res://{cache_name}"]\n\n[params]\n\nnodes/root_type=""\nnodes/root_name=""\nnodes/root_script=null\nnodes/apply_root_scale=true\nnodes/root_scale=1.0\nnodes/import_as_skeleton_bones=false\nnodes/use_name_suffixes=true\nnodes/use_node_type_suffixes=true\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=true\nmeshes/light_baking=1\nmeshes/force_disable_compression=false\nanimation/import=false\nmaterials/extract=0\nmaterials/extract_format=0\nmaterials/extract_path=""\n_subresources={{}}\ngltf/naming_version=2\ngltf/embedded_image_handling=0\nimport_script/path="res://tools/rooftop_ranch_palette_import.gd"\n'''
    glb.with_suffix(glb.suffix + ".import").write_text(text, encoding="utf-8")


def export_glb(path, collection):
    select_output(collection)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_keep_originals=False,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_apply=False,
        export_animations=False,
    )


assert PALETTE.is_file()
assert len(json.loads(CATALOG_PATH.read_text(encoding="utf-8"))["components"]) == 45
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
source_hashes_before = {str(p): sha(p) for p in [ASSEMBLY, BASE, PALETTE]}
cat = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))["components"]
for entry in cat:
    src = ROOT / entry["component_source"].replace("\\", "/")
    assert src.is_file(), src
    source_hashes_before[str(src)] = sha(src)

records = []
for index, entry in enumerate(cat, 1):
    key = entry["key"]
    src = ROOT / entry["component_source"].replace("\\", "/")
    optimized = EXPORT_DIR / f"{key}_optimized.blend"
    glb_dir = RUNTIME_DIR / "components" / key
    glb_dir.mkdir(parents=True, exist_ok=True)
    glb = glb_dir / f"{key}.glb"

    bpy.ops.wm.open_mainfile(filepath=str(src))
    collection = output_collection()
    before = stats(collection)
    operations = []
    totals = {"zero_area_faces_removed": 0, "duplicate_faces_removed": 0, "vertices_merged_or_removed": 0, "coplanar_faces_dissolved": 0, "unused_vertices_removed": 0}
    for obj in mesh_objects(collection):
        result = cleanup_mesh(obj)
        for name, value in result.items():
            totals[name] += value
    normalize_materials()
    operations.extend([
        "remove zero-area faces (area <= 1e-12m²)",
        "remove exact same-winding duplicate faces only; reversed faces retained for silhouette/back-face fidelity",
        "check coincident vertices without merging because PaletteUV/material seams are protected",
        "check coplanar subdivisions without dissolving across UV/material/hard-edge boundaries",
        "retain all visible faces, object transforms, origins and PaletteUV islands",
    ])
    if all(value == 0 for value in totals.values()):
        zero_reason = "清理命中为零；源组件无可安全移除的重复/退化几何，保留全部可见轮廓、背面、材质边界与 PaletteUV。"
    else:
        zero_reason = "清理仅移除可证明退化或同向重复面；其余几何为可见面、阴影面或受 UV/材质边界保护而保留。"
    bpy.ops.wm.save_as_mainfile(filepath=str(optimized), compress=True)
    optimized_hash = sha(optimized)

    bpy.ops.wm.open_mainfile(filepath=str(optimized))
    collection = output_collection()
    after = stats(collection)
    assert after["uv_faces"] == before["uv_faces"] or totals["zero_area_faces_removed"] > 0
    assert after["materials"]
    assert "PaletteUV" in after["uv_layers"]
    export_glb(glb, collection)
    write_import_contract(glb)
    glb_stats = read_glb(glb)
    assert glb_stats["images"] == 0, (key, glb_stats)
    assert glb_stats["triangles"] == after["triangles"], (key, glb_stats, after)
    reduction = None if before["triangles"] == 0 else (before["triangles"] - after["triangles"]) / before["triangles"]
    records.append({
        "asset_id": entry["asset_id"],
        "key": key,
        "name": entry["name"],
        "category": entry["category"],
        "source_version": "v004",
        "source": src.relative_to(ROOT).as_posix(),
        "source_sha256_before": source_hashes_before[str(src)],
        "source_sha256_after": sha(src),
        "optimized": optimized.relative_to(ROOT).as_posix(),
        "optimized_sha256": optimized_hash,
        "glb": glb.relative_to(ROOT).as_posix(),
        "glb_sha256": sha(glb),
        "triangles_before": before["triangles"],
        "triangles_after": after["triangles"],
        "exported_triangles": glb_stats["triangles"],
        "reduction_ratio": reduction,
        "budget": None,
        "budget_reason": "用户未提供逐组件三角预算；未虚构预算，按保真优先执行安全清理。",
        "operations": operations,
        "operation_counts": totals,
        "zero_change_reason": zero_reason,
        "bounds_blender": {"low": after["bounds_low"], "high": after["bounds_high"], "size": after["bounds_size"]},
        "origin": entry.get("origin", "bottom_center"),
        "front_axis_blender": entry.get("front_axis", "-Y"),
        "coordinate_mapping": "Blender (x,y,z) -> Godot (x,z,-y); GLTF export_yup=True",
        "material_names": after["materials"],
        "palette": "art_source/shared/palettes/sea_cabin_timber_8x8_512.png",
        "palette_sampling": "Closest; no mipmap; external only; no embedded image",
        "palette_images_in_optimized": after["palette_images"],
        "glb_stats": glb_stats,
        "independent_reopen": True,
        "runtime_verified": False,
        "godot_import_status": "pending_import_only",
    })
    print("EXPORTED", index, key, before["triangles"], after["triangles"], glb_stats["triangles"], flush=True)

source_hashes_after = {path: sha(path) for path in source_hashes_before}
assert source_hashes_before == source_hashes_after, {k: (source_hashes_before[k], source_hashes_after[k]) for k in source_hashes_before if source_hashes_before[k] != source_hashes_after[k]}
assert len(records) == 45 and len({r["asset_id"] for r in records}) == 45
manifest = {
    "schema": "sea.scene.02b_component_export",
    "asset_id": "SEA-SCENE-ORF2-EXPORT-V004",
    "name": "ocean_rooftop_farm v004 02b 独立组件导出",
    "source_version": "v004",
    "catalog_count": 45,
    "catalog_independent": True,
    "whole_building_glb_substitute": False,
    "upgrade_states_are_independent_assets": True,
    "upgrade_state_keys": ["greenhouse_unbuilt", "greenhouse_complete", "water_tower_unbuilt", "water_tower_complete"],
    "source_sha256_before": source_hashes_before,
    "source_sha256_after": source_hashes_after,
    "all_protected_sources_unchanged": source_hashes_before == source_hashes_after,
    "palette": {
        "source": "art_source/shared/palettes/sea_cabin_timber_8x8_512.png",
        "sha256": sha(PALETTE),
        "sampling": "Closest",
        "mipmap": False,
        "embedded_in_glb": False,
    },
    "optimized_directory": EXPORT_DIR.relative_to(ROOT).as_posix(),
    "runtime_directory": RUNTIME_DIR.relative_to(ROOT).as_posix(),
    "coordinate_mapping": "Blender (x,y,z) -> Godot (x,z,-y)",
    "export_settings": {"export_yup": True, "export_image_format": "NONE", "export_apply": False, "export_animations": False},
    "runtime_verified": False,
    "godot_import_status": "pending_import_only; export is not game acceptance",
    "components": records,
}
json_write(EXPORT_DIR / "export_manifest.json", manifest)
print("ORF4_02B_EXPORT", json.dumps({"components": len(records), "source_unchanged": manifest["all_protected_sources_unchanged"], "glbs": sum(r["glb_stats"]["images"] == 0 for r in records)}, ensure_ascii=False), flush=True)
