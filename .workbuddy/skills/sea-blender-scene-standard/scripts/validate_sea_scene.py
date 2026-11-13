"""sea 场景源级验收：PaletteUV / 色板外链 / SEA 材质角色 / 集合结构 / 三角面统计。

面向 sea 真实源结构：
  · 场景 `<套件>_组件母版`：组件集合以 AssetID 命名（`SEA-SCENE-XXX-YYY`），网格在此。
  · 场景 `<套件>_参考装配`：组件集合实例 + `展示支持_不导出`（相机/灯光）。
  · 展示支持集合永远不参与几何验收。

用法：
  blender --background "<套件>.blend" --python validate_sea_scene.py -- \
      [--palette-grid 8] [--max-materials 4] [--safe-margin 0.015625] \
      [--shared-palette art_source/shared/palettes/sea_cozy_8x8_512.png] \
      [--scene <装配场景名>] [--allow-extra-uv] [--json report.json]

退出码 0 = 全部通过，1 = 有必须项失败。报告总是打到 stdout。
"""

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

import bpy

PALETTE_UV = "PaletteUV"
FORBIDDEN_EXTRA_UV = {"UVMap", "UVMap.001", "UV贴图"}
ASSET_PREFIX = "SEA-"
MASTER_SCENE_HINT = "组件母版"
SEA_ROLES = ("SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission")
EMISSIVE_KEYS = ("sea_emission", "自发光", "发光", "emissive", "glow")
# 自发光对象命名词表：sea 习惯用语义名（吊灯/灯笼），因此「灯」也算合格
EMISSIVE_OBJECT_NAME_KEYS = ("发光", "灯", "emission", "emissive", "glow", "led")
# 512px 色板留 8px 安全边 = 8 / 512
DEFAULT_SAFE_MARGIN = 8.0 / 512.0
MIN_UV_AREA = 1.0e-7
EPS = 1.0e-5


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--palette-grid", type=int, default=None,
                   help="色板格数；缺省时从色板同名 .json 的 grid 读取，再不行用 8")
    p.add_argument("--max-materials", type=int, default=4, help="材质角色上限；sea 为 4")
    p.add_argument("--safe-margin", type=float, default=DEFAULT_SAFE_MARGIN,
                   help="格内安全边（UV 单位）；默认 8/512")
    p.add_argument("--shared-palette", type=Path, help="要求色板图片节点都外链到该文件且未打包")
    p.add_argument("--scene", help="统计三角面的场景名；默认当前场景，缺省回落到面数最多的场景")
    p.add_argument("--all-meshes", action="store_true", help="校验场景内全部网格（调试用）")
    p.add_argument("--allow-extra-uv", action="store_true")
    p.add_argument("--json", type=Path)
    return p.parse_args(argv)


# ---------- 集合与对象归类 ----------

def is_showcase(name):
    """展示支持集合：sea 里出现过 `90 展示支持_不导出`、`90_...`、`展示支持`。"""
    s = name.strip()
    if "展示支持" in s or "不导出" in s:
        return True
    if s.startswith("90") and not s[2:3].isdigit():
        return True
    return False


def node_tree_of(material):
    """Blender 5.x 材质恒为节点材质；避开已弃用的 material.use_nodes。"""
    return getattr(material, "node_tree", None)


def master_collections():
    """AssetID 命名的组件集合；排除展示支持。"""
    return sorted(
        (c for c in bpy.data.collections if c.name.startswith(ASSET_PREFIX) and not is_showcase(c.name)),
        key=lambda c: c.name,
    )


def master_meshes():
    result = {}
    collections = master_collections()
    if not collections:
        # 回落：母版场景里除展示支持外的全部网格
        scene = next((s for s in bpy.data.scenes if MASTER_SCENE_HINT in s.name), None)
        pool = scene.objects if scene else bpy.context.scene.objects
        showcase = {o for c in bpy.data.collections if is_showcase(c.name) for o in c.all_objects}
        for obj in pool:
            if obj.type == "MESH" and obj not in showcase:
                result[obj.name] = obj
        return result, []
    for coll in collections:
        for obj in coll.all_objects:
            if obj.type == "MESH":
                result.setdefault(obj.name, obj)
    return result, [c.name for c in collections]


def showcase_leaks(meshes):
    """展示/验收集合中的网格不得出现在组件母版里。"""
    showcase = {o.name for c in bpy.data.collections if is_showcase(c.name) for o in c.all_objects}
    return sorted(name for name in meshes if name in showcase)


# ---------- UV ----------

def uv_polygon_area(uvs):
    return abs(sum(
        uvs[i].x * uvs[(i + 1) % len(uvs)].y - uvs[(i + 1) % len(uvs)].x * uvs[i].y
        for i in range(len(uvs))
    )) * 0.5


def cell_index(value, grid):
    return min(grid - 1, max(0, math.floor(max(0.0, min(0.999999, value)) * grid)))


def audit_palette_uv(obj, grid, safe_margin):
    data = obj.data
    layer = data.uv_layers.get(PALETTE_UV)
    report = {
        "object": obj.name,
        "polygon_count": len(data.polygons),
        "valid_island_polygon_count": 0,
        "missing_palette_uv": layer is None,
        "active_uv": data.uv_layers.active.name if data.uv_layers.active else "",
        "active_render_uv": next((u.name for u in data.uv_layers if u.active_render), ""),
        "extra_uv_layers": [u.name for u in data.uv_layers if u.name != PALETTE_UV],
        "bad_polygon_examples": [],
    }
    if layer is None:
        return report
    cell = 1.0 / grid
    for poly in data.polygons:
        uvs = [layer.data[i].uv for i in poly.loop_indices]
        if len(uvs) < 3:
            continue
        columns = {cell_index(uv.x, grid) for uv in uvs}
        rows = {cell_index(uv.y, grid) for uv in uvs}
        same_cell = len(columns) == 1 and len(rows) == 1
        safe = False
        if same_cell:
            col = next(iter(columns))
            row = next(iter(rows))
            safe = all(
                col * cell + safe_margin <= uv.x <= (col + 1) * cell - safe_margin
                and row * cell + safe_margin <= uv.y <= (row + 1) * cell - safe_margin
                for uv in uvs
            )
        if same_cell and safe and uv_polygon_area(uvs) >= MIN_UV_AREA:
            report["valid_island_polygon_count"] += 1
        elif len(report["bad_polygon_examples"]) < 8:
            report["bad_polygon_examples"].append(poly.index)
    return report


# ---------- 材质 ----------

def material_is_emissive(mat):
    if not mat:
        return False
    if any(k in mat.name.lower() for k in EMISSIVE_KEYS):
        return True
    tree = node_tree_of(mat)
    if tree:
        for node in tree.nodes:
            if node.type == "EMISSION":
                return True
            if node.type == "BSDF_PRINCIPLED":
                strength = node.inputs.get("Emission Strength")
                if strength and not strength.is_linked and float(strength.default_value) > 0.05:
                    return True
    return False


def material_role(mat):
    """把材质名归到 SEA 四角色；不在四角色内返回 None。"""
    name = mat.name
    for role in SEA_ROLES:
        if name == role or name.startswith(role + "."):
            return role
    lowered = name.lower()
    if any(k in lowered for k in ("emissive", "glow")) or "自发光" in name or "发光" in name:
        return "SEA_Emission"
    if "glass" in lowered or "gloss" in lowered or "清漆" in name or "玻璃" in name:
        return "SEA_Gloss"
    if "metal" in lowered or "金属" in name:
        return "SEA_Metal"
    if "matte" in lowered or "哑光" in name:
        return "SEA_Matte"
    return None


def area_by_role(meshes):
    """按材质角色汇总世界面积，用于核对 SKILL §4 的面积节奏。"""
    totals = defaultdict(float)
    for obj in meshes.values():
        material_area = defaultdict(float)
        for poly in obj.data.polygons:
            mat = obj.data.materials[poly.material_index] if poly.material_index < len(obj.data.materials) else None
            material_area[mat.name if mat else "<空槽>"] += poly.area
        for name, area in material_area.items():
            mat = bpy.data.materials.get(name)
            role = material_role(mat) if mat else "<空槽>"
            totals[role or name] += area
    total = sum(totals.values()) or 1.0
    return {role: round(area / total, 4) for role, area in sorted(totals.items(), key=lambda kv: -kv[1])}


def material_audit(meshes, shared_palette, palette_grid, palette_contract):
    used = sorted({m for obj in meshes.values() for m in obj.data.materials if m}, key=lambda m: m.name)
    used_in_file = {
        m for obj in bpy.data.objects if obj.type == "MESH" for m in obj.data.materials if m
    }
    unused = sorted(m.name for m in bpy.data.materials if m not in used_in_file)
    expected = shared_palette.expanduser().resolve() if shared_palette else None

    bad_uv_nodes, missing_uv_nodes, bad_interp = [], [], []
    non_shared, packed, ok_palette = [], [], []
    for mat in used:
        uv_nodes, image_nodes = [], []
        tree = node_tree_of(mat)
        if tree:
            uv_nodes = [n for n in tree.nodes if n.type == "UVMAP"]
            image_nodes = [n for n in tree.nodes if n.type == "TEX_IMAGE"]
        if image_nodes and not uv_nodes:
            missing_uv_nodes.append(mat.name)
        for node in uv_nodes:
            if node.uv_map != PALETTE_UV:
                bad_uv_nodes.append({"material": mat.name, "uv_map": node.uv_map})
        for node in image_nodes:
            if node.interpolation != "Closest":
                bad_interp.append({"material": mat.name, "interpolation": node.interpolation})
            if node.image is None:
                continue
            actual = Path(bpy.path.abspath(node.image.filepath))
            try:
                actual = actual.resolve()
            except OSError:
                pass
            if expected is not None and actual != expected:
                non_shared.append({"material": mat.name, "image": node.image.name, "path": str(actual)})
            elif node.image.packed_file is not None:
                packed.append({"material": mat.name, "image": node.image.name})
            else:
                ok_palette.append({"material": mat.name, "path": str(actual)})

    roles = {mat.name: material_role(mat) for mat in used}
    non_sea = sorted(n for n, r in roles.items() if r is None)
    return {
        "used_materials": [m.name for m in used],
        "material_roles": roles,
        "non_sea_role_materials": non_sea,
        "unused_materials": unused,
        "bad_uv_map_nodes": bad_uv_nodes,
        "missing_uv_map_nodes": missing_uv_nodes,
        "bad_image_interpolation": bad_interp,
        "non_shared_palette_images": non_shared,
        "packed_palette_images": packed,
        "external_palette_images": ok_palette,
        "palette_grid_declared": palette_grid,
        "palette_contract": palette_contract,
        "area_share_by_role": area_by_role(meshes),
    }


# ---------- 结构与尺度 ----------

def transform_audit(meshes):
    """组件根应恒等变换、几何在底部中心。非恒等只报不等，不猜意图。"""
    non_identity = []
    for obj in meshes.values():
        loc, rot, scale = obj.location, obj.rotation_euler, obj.scale
        if (max(abs(v) for v in loc) > EPS
                or max(abs(v) for v in rot) > EPS
                or max(abs(s - 1.0) for s in scale) > EPS):
            non_identity.append({
                "object": obj.name,
                "location": [round(v, 5) for v in loc],
                "rotation": [round(v, 5) for v in rot],
                "scale": [round(v, 5) for v in scale],
            })
    return non_identity


def bevel_audit(meshes):
    """记录每对象倒角：修改器宽度/段数，或已应用后的近距离顶点数。"""
    result = []
    for obj in sorted(meshes.values(), key=lambda o: o.name):
        mods = [
            {"width": round(m.width, 5), "segments": m.segments,
             "limit_method": m.limit_method, "hard": getattr(m, "harden_normals", None)}
            for m in obj.modifiers if m.type == "BEVEL"
        ]
        polys = obj.data.polygons
        all_smooth = bool(len(polys)) and all(f.use_smooth for f in polys)
        result.append({"object": obj.name, "bevel_modifiers": mods,
                       "all_faces_smooth": all_smooth,
                       "polygon_count": len(polys)})
    return result


def triangle_count(scene_name):
    """按可见实例求值后统计三角面：母版只算一次，实例各算一次。"""
    if scene_name:
        scene = bpy.data.scenes.get(scene_name)
        if scene is None:
            raise SystemExit(f"找不到场景: {scene_name}")
    else:
        # 默认取装配场景（非组件母版），否则取对象最多的场景
        scene = next((s for s in bpy.data.scenes if MASTER_SCENE_HINT not in s.name), None) \
            or max(bpy.data.scenes, key=lambda s: len(s.objects))
    depsgraph = scene.view_layers[0].depsgraph
    total, instances, per_object = 0, 0, defaultdict(int)
    for inst in depsgraph.object_instances:
        obj = inst.object
        if obj.type != "MESH":
            continue
        mesh = obj.to_mesh()
        if mesh is None:
            continue
        mesh.calc_loop_triangles()
        tris = len(mesh.loop_triangles)
        total += tris
        instances += 1
        per_object[obj.name] += tris
        obj.to_mesh_clear()
    return {
        "scene": scene.name,
        "mesh_instances": instances,
        "triangles": total,
        "top_objects": sorted(per_object.items(), key=lambda kv: -kv[1])[:10],
    }


def load_palette_contract(shared_palette):
    """读取色板同名 .json：格数与色名/行列。格数以契约为准，不靠命令行记忆。"""
    if not shared_palette:
        return None
    json_path = Path(str(shared_palette)).with_suffix(".json")
    if not json_path.exists():
        return None
    try:
        data = json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    cells = data.get("cells") or []
    return {"file": str(json_path), "grid": data.get("grid"), "row_origin": data.get("row_origin"),
            "cell_count": len(cells), "cells": cells}


def resolve_grid(args, contract):
    """命令行 > 色板契约 > 默认 8。色板契约里格数是权威。"""
    declared = (contract or {}).get("grid")
    if args.palette_grid:
        source = "cli"
        grid = args.palette_grid
    elif declared:
        source = "palette_json"
        grid = int(declared[0]) if isinstance(declared, (list, tuple)) else int(declared)
    else:
        source = "default"
        grid = 8
    if declared and source == "cli":
        declared_grid = declared[0] if isinstance(declared, (list, tuple)) else declared
        if int(declared_grid) != grid:
            print(f"警告：命令行格数 {grid} 与色板契约 {declared_grid} 不一致，以命令行执行但结果需复核",
                  file=sys.stderr)
    return max(2, grid), source


# ---------- 主流程 ----------

def main():
    args = parse_args()
    contract = load_palette_contract(args.shared_palette)
    grid, grid_source = resolve_grid(args, contract)

    meshes, asset_collections = master_meshes()
    if args.all_meshes:
        meshes = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}

    uv_reports = [audit_palette_uv(o, grid, args.safe_margin) for o in meshes.values()]
    mat_report = material_audit(meshes, args.shared_palette, grid, contract)

    mixed, bad_names, body_slots, emissive_slots = [], [], [], []
    for obj in meshes.values():
        flags = {material_is_emissive(m) for m in obj.data.materials if m}
        if len(flags) > 1:
            mixed.append(obj.name)
        is_emissive = True in flags
        if is_emissive and not any(k in obj.name.lower() for k in EMISSIVE_OBJECT_NAME_KEYS):
            bad_names.append(obj.name)
        slot_count = len([m for m in obj.data.materials if m])
        if is_emissive and slot_count > 1:
            emissive_slots.append(obj.name)
        if not is_emissive and slot_count > 3:
            body_slots.append(obj.name)

    missing_uv = [r["object"] for r in uv_reports if r["missing_palette_uv"]]
    bad_faces = [r["object"] for r in uv_reports
                 if r["valid_island_polygon_count"] != r["polygon_count"]]
    bad_active = [r["object"] for r in uv_reports if r["active_uv"] != PALETTE_UV]
    bad_render = [r["object"] for r in uv_reports if r["active_render_uv"] != PALETTE_UV]
    extra_uv = {r["object"]: r["extra_uv_layers"] for r in uv_reports if r["extra_uv_layers"]}
    undeclared = {
        name: layers for name, layers in extra_uv.items()
        if any(layer in FORBIDDEN_EXTRA_UV or layer.startswith("UVMap") for layer in layers)
    }
    leaks = showcase_leaks(meshes)
    non_identity = transform_audit(meshes)
    triangles = triangle_count(args.scene)

    checks = {
        f"palette_uv_on_all_master_meshes": not missing_uv,
        f"palette_uv_single_cell_{grid}x{grid}": not bad_faces,
        "palette_uv_is_active_edit_layer": not bad_active,
        "palette_uv_is_active_render_layer": not bad_render,
        "no_undeclared_extra_uv_layers": args.allow_extra_uv or not undeclared,
        "materials_read_palette_uv": not mat_report["bad_uv_map_nodes"]
        and not mat_report["missing_uv_map_nodes"],
        "palette_images_use_closest": not mat_report["bad_image_interpolation"],
        "palette_images_external_and_unpacked": not mat_report["packed_palette_images"],
        "palette_images_use_single_shared_file": (
            args.shared_palette is None or not mat_report["non_shared_palette_images"]
        ),
        "materials_within_four_sea_roles": (
            len(mat_report["used_materials"]) <= args.max_materials
            and not mat_report["non_sea_role_materials"]
        ),
        "no_unused_materials": not mat_report["unused_materials"],
        "no_showcase_mesh_in_masters": not leaks,
        "emissive_not_mixed_with_body": not mixed,
        "emissive_objects_clearly_named": not bad_names,
        "body_has_at_most_three_material_slots": not body_slots,
        "emissive_has_one_material": not emissive_slots,
    }

    report = {
        "blend": bpy.data.filepath,
        "palette_grid": grid,
        "palette_grid_source": grid_source,
        "safe_margin_uv": args.safe_margin,
        "asset_collections": asset_collections,
        "passed": all(checks.values()),
        "checks": checks,
        "master_mesh_count": len(meshes),
        "polygon_count": sum(r["polygon_count"] for r in uv_reports),
        "valid_island_polygon_count": sum(r["valid_island_polygon_count"] for r in uv_reports),
        "uv_reports": uv_reports,
        "extra_uv_layers": extra_uv,
        "material_audit": mat_report,
        "showcase_leaks": leaks,
        "mixed_emission_objects": mixed,
        "poorly_named_emissive_objects": bad_names,
        "body_material_slot_overruns": body_slots,
        "emissive_material_slot_overruns": emissive_slots,
        "triangles": triangles,
        "warnings": {
            "non_identity_component_transforms": non_identity,
            "bevel": bevel_audit(meshes),
            "note": "非恒等变换与倒角仅作记录：母版应为恒等且底部居中；倒角半径/段数按 SKILL §3.3 人工判定。",
        },
    }
    text = json.dumps(report, ensure_ascii=False, indent=2, default=str)
    print(text)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(text, encoding="utf-8")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
