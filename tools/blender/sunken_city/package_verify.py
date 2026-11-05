"""仅供独立 Blender 后台进程：打包 sunken_city 所选版本并逐包重开验证。

执行前须由作者另行保存最终母版；本脚本不读取 working.blend，不连接 MCP。
运行方式：blender --background --factory-startup --disable-autoexec
          --python-exit-code 1 --python tools/blender/sunken_city/package_verify.py
SEA_SUNKEN_VERSION 选择 v001（默认）、v002、v003 或 v004，独立包与报告按版本隔离。
SEA_WORK_ROOT 可改工程外工作根目录，默认 <工程同级>/sea-work。
"""

import argparse
from array import array
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import traceback
import uuid

import bpy
from mathutils import Vector


R = Path(__file__).resolve().parents[3]
VERSION = os.environ.get("SEA_SUNKEN_VERSION", "v001")
if VERSION not in {"v001", "v002", "v003", "v004"}:
    raise ValueError("SEA_SUNKEN_VERSION 只支持 v001、v002、v003 或 v004")
D = R / "art_source/scenes/sunken_city" / VERSION
MAIN = D / f"sunken_city_{VERSION}.blend"
CATALOG = D / "component_catalog.json"
PACKAGES = D / "component_packages"
PAL = R / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
W = Path(os.environ.get("SEA_WORK_ROOT", R.parent / "sea-work")).expanduser().resolve() / "sunken_city" / VERSION
ROLES = {"SEA_Matte", "SEA_Metal", "SEA_Gloss"}
EXPECTED_COUNT = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))['component_budget']['planned']
EPS = 1.0e-5
MIN_UV_AREA = 1.0e-7
OUTPUT = "02_游戏输出_独立组件"
DISPLAY = "90_展示环境_不属于组件"


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def dump(path, value):
    """同目录原子替换，避免半截 JSON；只在实际执行阶段调用。"""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        temp.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def identity(matrix):
    return all(math.isfinite(matrix[i][j]) and abs(matrix[i][j] - int(i == j)) <= EPS
               for i in range(4) for j in range(4))


def audit_grid8(obj):
    """保持安装版审计的返回契约，仅将色格改为 8×8、8px 内缩。"""
    layers = obj.data.uv_layers
    layer = layers.get("PaletteUV")
    result = {
        "object": obj.name,
        "polygon_count": len(obj.data.polygons),
        "valid_island_polygon_count": 0,
        "missing_palette_uv": layer is None,
        "active_uv": layers.active.name if layers.active else "",
        "active_render_uv": next((uv.name for uv in layers if uv.active_render), ""),
        "extra_uv_layers": [uv.name for uv in layers if uv.name != "PaletteUV"],
        "bad_polygon_examples": [],
    }
    if layer is None:
        return result
    for face in obj.data.polygons:
        points = [layer.data[index].uv for index in face.loop_indices]
        valid = len(points) >= 3 and all(math.isfinite(p.x) and math.isfinite(p.y) for p in points)
        if valid:
            cells = {(math.floor(p.x * 8), math.floor(p.y * 8)) for p in points}
            valid = len(cells) == 1 and all(0 <= c < 8 and 0 <= r < 8 for c, r in cells)
            if valid:
                c, r = next(iter(cells))
                # 512 / 8 = 64px；每侧留 8px，即全图 UV 的 8/512。
                valid = all(c / 8 + 8 / 512 <= p.x <= (c + 1) / 8 - 8 / 512
                            and r / 8 + 8 / 512 <= p.y <= (r + 1) / 8 - 8 / 512 for p in points)
            area = abs(sum(p.x * points[(i + 1) % len(points)].y
                           - points[(i + 1) % len(points)].x * p.y
                           for i, p in enumerate(points))) * 0.5
            valid = valid and area > MIN_UV_AREA
        if valid:
            result["valid_island_polygon_count"] += 1
        elif len(result["bad_polygon_examples"]) < 8:
            result["bad_polygon_examples"].append(face.index)
    return result


def geometry_fingerprint(mesh):
    """对原始 float32 顶点及有序拓扑做稳定小端摘要，不依赖对象名。"""
    digest = hashlib.sha256(b"sea.geometry.float32-topology.v1\0")
    fields = [(mesh.vertices, "co", "f", 3), (mesh.edges, "vertices", "i", 2),
              (mesh.loops, "vertex_index", "i", 1), (mesh.polygons, "loop_start", "i", 1),
              (mesh.polygons, "loop_total", "i", 1)]
    for data, prop, code, width in fields:
        values = array(code, [0]) * (len(data) * width)
        data.foreach_get(prop, values)
        if sys.byteorder != "little":
            values.byteswap()
        digest.update(json.dumps([prop, len(data), width]).encode("ascii"))
        digest.update(values.tobytes())
    return digest.hexdigest()


def audit_component(entry, standalone=False):
    result = {"key": entry["key"], "checks": {}, "errors": []}

    def check(name, passed, actual=None, expected=None):
        passed = bool(passed)
        result["checks"][name] = {"passed": passed, "actual": actual, "expected": expected}
        if not passed:
            result["errors"].append(name)

    col = bpy.data.collections.get(entry["collection"])
    check("collection_exists", col is not None, entry["collection"])
    if col is None:
        result["passed"] = False
        return result
    objects = list(col.all_objects)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    root = bpy.data.objects.get(entry["root_object"])
    check("one_root_one_mesh", len(objects) == 2 and len(meshes) == 1
          and root in objects and root.type == "EMPTY", [(o.name, o.type) for o in objects], "ROOT EMPTY + MESH")
    check("no_nested_component_collections", not col.children, list(col.children.keys()), [])
    check("collection_offset_zero", all(math.isfinite(v) and abs(v) <= EPS for v in col.instance_offset), list(col.instance_offset), [0, 0, 0])
    check("collection_visible", not col.hide_viewport and not col.hide_render,
          {"hide_viewport": col.hide_viewport, "hide_render": col.hide_render})
    if entry.get("objects") is not None:
        check("catalog_object_names", sorted(o.name for o in objects) == sorted(entry["objects"]), sorted(o.name for o in objects), sorted(entry["objects"]))
    for obj in objects:
        prefix = obj.name + "/"
        check(prefix + "identity", all(identity(m) for m in (obj.matrix_basis, obj.matrix_local, obj.matrix_world, obj.matrix_parent_inverse)),
              {"basis": [list(r) for r in obj.matrix_basis], "parent_inverse": [list(r) for r in obj.matrix_parent_inverse]})
        check(prefix + "unique_collection_owner", list(obj.users_collection) == [col], [c.name for c in obj.users_collection], [col.name])
        check(prefix + "no_instance_or_library", obj.instance_type == "NONE" and obj.library is None)
        check(prefix + "static_geometry", not obj.constraints and not obj.modifiers and obj.animation_data is None)
        check(prefix + "visible", not obj.hide_viewport and not obj.hide_render and not obj.hide_get())
    if root in objects:
        check("root_unparented", root.parent is None, root.parent.name if root.parent else None)
    if len(meshes) == 1:
        obj = meshes[0]
        mesh = obj.data
        check("mesh_parent_is_root", obj.parent == root and obj.parent_type == "OBJECT", obj.parent.name if obj.parent else None, entry["root_object"])
        check("mesh_nonempty", len(mesh.vertices) > 0 and len(mesh.polygons) > 0, {"vertices": len(mesh.vertices), "polygons": len(mesh.polygons)})
        check("mesh_no_shape_keys_or_linked_data", mesh.shape_keys is None and mesh.library is None and mesh.animation_data is None)
        finite = all(math.isfinite(v) for vertex in mesh.vertices for v in vertex.co)
        check("finite_vertices", finite)
        if mesh.vertices and finite:
            low = [min(v.co[i] for v in mesh.vertices) for i in range(3)]
            high = [max(v.co[i] for v in mesh.vertices) for i in range(3)]
            anchor = [(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, low[2]]
            check("bottom_center_origin", all(abs(v) <= EPS for v in anchor), anchor, [0, 0, 0])
            result.update(bounds_min=low, bounds_max=high, bounds_size_m=[b - a for a, b in zip(low, high)])
        uv = audit_grid8(obj)
        result["uv_audit"] = uv
        check("unique_active_render_palette_uv", len(mesh.uv_layers) == 1 and uv["active_uv"] == "PaletteUV" and uv["active_render_uv"] == "PaletteUV", list(mesh.uv_layers.keys()), ["PaletteUV"])
        check("every_face_area_gt_1e_minus7_single_grid8_safe8px", not uv["missing_palette_uv"] and uv["valid_island_polygon_count"] == len(mesh.polygons),
              {"valid": uv["valid_island_polygon_count"], "total": len(mesh.polygons), "bad_examples": uv["bad_polygon_examples"]})
        slots = list(mesh.materials)
        check("no_empty_duplicate_or_nonrole_slots", bool(slots) and all(m is not None and m.name in ROLES for m in slots)
              and len({m.name for m in slots if m}) == len(slots), [m.name if m else None for m in slots], sorted(ROLES))
        bad_indices = [f.index for f in mesh.polygons if f.material_index >= len(slots) or slots[f.material_index] is None]
        check("valid_face_material_indices", not bad_indices, bad_indices[:8])
        used_roles = sorted({slots[f.material_index].name for f in mesh.polygons if f.material_index < len(slots) and slots[f.material_index]})
        check("catalog_face_material_roles", used_roles == sorted(entry["material_roles"]), used_roles, sorted(entry["material_roles"]))
        result["material_roles"] = used_roles
        image_ids = set()
        material_errors = []
        for mat in {m for m in slots if m}:
            if not mat.use_nodes or not mat.node_tree:
                material_errors.append(mat.name + ": 缺少节点树")
                continue
            image_nodes = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"]
            if not image_nodes:
                material_errors.append(mat.name + ": 缺少色盘图像节点")
            for node in mat.node_tree.nodes:
                if node.type in {"EMISSION", "GROUP"}:
                    material_errors.append(mat.name + ": 不接受发光节点或未展开的节点组")
                if node.type == "BSDF_PRINCIPLED":
                    strength = node.inputs.get("Emission Strength")
                    color = node.inputs.get("Emission Color") or node.inputs.get("Emission")
                    if ((strength and strength.is_linked) or (color and color.is_linked)
                            or (color and max(color.default_value[:3]) > 0
                                and (strength is None or strength.default_value > 0))):
                        material_errors.append(mat.name + ": 存在发光或动态发光输入")
                if node.type == "UVMAP" and node.uv_map != "PaletteUV":
                    material_errors.append(mat.name + ": 错误 UV 节点")
            for node in image_nodes:
                image = node.image
                vector = node.inputs.get("Vector")
                explicit_uv = vector is not None and len(vector.links) == 1 and vector.links[0].from_node.type == "UVMAP" and vector.links[0].from_node.uv_map == "PaletteUV"
                if node.interpolation != "Closest" or not explicit_uv:
                    material_errors.append(mat.name + ": 非 Closest 或未由 PaletteUV 直接驱动")
                if image is None:
                    material_errors.append(mat.name + ": 图像为空")
                    continue
                image_ids.add(image.as_pointer())
                path = Path(bpy.path.abspath(image.filepath, library=image.library)).resolve()
                if image.source != "FILE" or path != PAL.resolve() or not path.is_file() or image.packed_file or len(image.packed_files):
                    material_errors.append(mat.name + ": 色盘必须外链唯一共享 PNG，不得打包")
                if tuple(image.size) != (512, 512):
                    material_errors.append(mat.name + ": 色盘不是 512×512")
                if standalone and (image.filepath.startswith("//") or not Path(image.filepath).is_absolute()):
                    material_errors.append(mat.name + ": 独立包色盘不是绝对路径")
        check("single_palette_image_datablock", len(image_ids) == 1, len(image_ids), 1)
        check("palette_nodes_and_no_emission", not material_errors, material_errors)
        result["geometry_fingerprint"] = geometry_fingerprint(mesh)
        mesh.calc_loop_triangles()
        result.update(mesh_object=obj.name, vertices=len(mesh.vertices), polygons=len(mesh.polygons), triangles=len(mesh.loop_triangles))
    if standalone:
        scene = bpy.context.scene
        output = bpy.data.collections.get(OUTPUT)
        display = bpy.data.collections.get(DISPLAY)
        check("one_default_scene", len(bpy.data.scenes) == 1, len(bpy.data.scenes), 1)
        check("output_wrapper", output is not None and list(output.children) == [col]
              and not output.objects and set(scene.collection.children) == {output, display})
        check("preview_outside_component", display is not None and set(o.type for o in display.objects) == {"CAMERA", "LIGHT"}
              and len(display.objects) == 2 and not display.children and scene.camera in list(display.objects))
        check("no_extra_objects", display is not None and set(bpy.data.objects) == set(objects) | set(display.objects)
              and set(scene.objects) == set(bpy.data.objects))
        check("no_extra_collections", set(bpy.data.collections.keys()) == {OUTPUT, DISPLAY, col.name}, list(bpy.data.collections.keys()))
        check("no_linked_blend_dependencies", not bpy.data.libraries, list(bpy.data.libraries.keys()))
        materials = list(bpy.data.materials)
        check("file_materials_unique_shared_roles", len(materials) <= 3 and all(m.name in ROLES for m in materials), [m.name for m in materials])
        file_images = [image for image in bpy.data.images if image.source == "FILE"]
        check("file_has_only_shared_palette", len(file_images) == 1 and len(image_ids) == 1
              and file_images[0].as_pointer() in image_ids if len(meshes) == 1 else False,
              [image.filepath for image in file_images])
    result["passed"] = not result["errors"]
    return result


def append_package(entry, target):
    # 防止在活跃 GUI/MCP 会话中误调用清场；后台检查还在入口执行一次。
    if not bpy.app.background:
        raise RuntimeError("禁止在 GUI/MCP 会话内执行打包")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.data.use_autopack = False
    # 空默认场景若残留启动材质，只清理 append 之前的无用户数据。
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)
    with bpy.data.libraries.load(str(MAIN), link=False) as (source, destination):
        if entry["collection"] not in source.collections:
            raise RuntimeError("最终母版缺少集合：" + entry["collection"])
        destination.collections = [entry["collection"]]
    col = destination.collections[0]
    if col is None:
        raise RuntimeError("集合载入失败")
    scene = bpy.context.scene
    scene.name = entry.get("name", entry["key"]) + "_独立包"
    scene.unit_settings.system = "METRIC"
    output = bpy.data.collections.new(OUTPUT)
    scene.collection.children.link(output)
    output.children.link(col)
    # 只规范化已正确引用的共享图片；不修复错图、不解包、不改 UV/几何/材质。
    for image in bpy.data.images:
        if image.source == "FILE":
            actual = Path(bpy.path.abspath(image.filepath, start=str(MAIN.parent), library=image.library)).resolve()
            if actual != PAL.resolve() or image.packed_file or len(image.packed_files):
                raise RuntimeError("源组件色盘引用错误或已内嵌：" + image.name)
            image.filepath = str(PAL.resolve())
    bpy.context.view_layer.update()
    audit = audit_component(entry)
    if not audit["passed"]:
        return audit, False
    display = bpy.data.collections.new(DISPLAY)
    scene.collection.children.link(display)
    target_point = Vector((0, 0, audit["bounds_size_m"][2] / 2))
    radius = max(Vector(audit["bounds_size_m"]).length / 2, 0.1)
    camera_data = bpy.data.cameras.new("展示相机")
    camera = bpy.data.objects.new("展示相机", camera_data)
    display.objects.link(camera)
    camera.location = target_point + Vector((1, -1.5, 1)).normalized() * radius * 4
    camera.rotation_euler = (target_point - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = radius * 2.5
    camera_data.clip_start = 0.01
    camera_data.clip_end = max(100, radius * 10)
    scene.camera = camera
    light_data = bpy.data.lights.new("展示日光", "SUN")
    light_data.energy = 2
    light_data.angle = math.radians(15)
    light = bpy.data.objects.new("展示日光", light_data)
    display.objects.link(light)
    light.rotation_euler = (0.45, -0.55, -0.4)
    world = bpy.data.worlds.new("展示环境")
    world.use_nodes = True
    next(node for node in world.node_tree.nodes if node.type == 'BACKGROUND').inputs[0].default_value = (0.35, 0.4, 0.45, 1)
    scene.world = world
    scene.render.resolution_x = scene.render.resolution_y = 1024
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.shading.type = "MATERIAL"
                space.region_3d.view_location = target_point
                space.region_3d.view_distance = radius * 3
    target.parent.mkdir(parents=True, exist_ok=True)
    status = bpy.ops.wm.save_as_mainfile(filepath=str(target), compress=False, relative_remap=False)
    if "FINISHED" not in status or not target.is_file() or target.stat().st_size == 0:
        raise RuntimeError("独立包未成功保存：" + str(target))
    return audit, True


def find_validator():
    candidates = [Path.home() / ".workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py",
                  Path.home() / ".agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py"]
    return next((path for path in candidates if path.is_file()), None), candidates


def skill_worker(args):
    # 子进程只调用安装版 main，除 UV 审计外不替换任何函数或检查。
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("sunken_city_installed_prop_validator", args.validator)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.audit_palette_uv = audit_grid8
    sys.argv = [str(args.validator), "--", "--max-materials", "3", "--shared-palette", str(PAL.resolve()), "--json", str(args.report)]
    module.main()


def run_generic(validator, entry, target, run_id):
    directory = W / "skill_reports" / run_id
    directory.mkdir(parents=True, exist_ok=True)
    report = directory / (entry["key"] + ".json")
    log = directory / (entry["key"] + ".log")
    command = [bpy.app.binary_path, "--background", "--factory-startup", "--disable-autoexec", str(target),
               "--python-exit-code", "1", "--python", str(Path(__file__).resolve()), "--",
               "--skill-worker", "--validator", str(validator), "--report", str(report)]
    row = {"key": entry["key"], "stage": "generic_validator", "status": "running", "passed": False,
           "exit_code": None, "command": command, "report": str(report), "log": str(log), "checks": {}, "errors": []}
    before = sha(target)
    try:
        with log.open("w", encoding="utf-8") as stream:
            process = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=False)
        row["exit_code"] = process.returncode
        if report.is_file():
            data = json.loads(report.read_text(encoding="utf-8"))
            row["checks"] = data.get("checks", {})
            row["reported_passed"] = data.get("passed")
            row["reported_blend"] = data.get("blend")
            report_valid = (isinstance(row["checks"], dict) and bool(row["checks"])
                            and all(value is True for value in row["checks"].values())
                            and data.get("passed") is True and not data.get("errors") and not data.get("failures")
                            and ("status" not in data or data["status"] == "passed")
                            and ("exit_code" not in data or type(data["exit_code"]) is int and data["exit_code"] == 0)
                            and Path(data.get("blend", "")).resolve() == target.resolve()
                            and data.get("output_mesh_count") == 1)
            if not report_valid:
                row["errors"].append("通用验证报告失败、不完整或不属于当前包")
        else:
            row["errors"].append("子进程没有生成本次通用验证报告")
        if process.returncode != 0:
            row["errors"].append("通用验证进程返回非零")
    except Exception:
        row["errors"].append(traceback.format_exc())
    row["package_sha256_before"] = before
    row["package_sha256_after"] = sha(target)
    if row["package_sha256_after"] != before:
        row["errors"].append("通用验证期间独立包哈希改变")
    row["passed"] = not row["errors"]
    row["status"] = "passed" if row["passed"] else "failed"
    return row


def main():
    if not bpy.app.background:
        raise RuntimeError("仅允许独立 headless Blender；禁止从 GUI/MCP 执行")
    if W == R or R in W.parents:
        raise RuntimeError("SEA_WORK_ROOT 必须位于工程外；拒绝写入报告")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "_" + uuid.uuid4().hex[:8]
    validator, candidates = find_validator()
    package_report = {"schema": "sea.sunken_city.package_verification.v1", "run_id": run_id, "suite": "sunken_city",
                      "stage": "preflight", "status": "running", "passed": False, "exit_code": None,
                      "source": str(MAIN), "work_directory": str(W), "blender_version": bpy.app.version_string,
                      "expected_package_count": EXPECTED_COUNT, "checks": {}, "errors": [], "components": [],
                      "catalog_updated": False, "geometry_fingerprint_algorithm": "sea.geometry.float32-topology.v1",
                      "runtime_validation": "not_executed_not_in_scope", "visual_validation": "pending_separate_render_review"}
    skill_report = {"schema": "sea.sunken_city.skill_verification.v1", "run_id": run_id, "suite": "sunken_city",
                    "stage": "validator_discovery", "status": "pending", "passed": False, "exit_code": None,
                    "installed_validator": str(validator) if validator else None,
                    "searched_paths": [str(p) for p in candidates], "checks": {}, "errors": [], "components": [],
                    "uv_adapter": "仅 audit_palette_uv：8×8，8px 安全边，逐面面积严格 >1e-7；其余检查不变"}
    source_before = palette_before = catalog_before = None
    entries = []
    updates = {}
    failure = False

    def persist():
        dump(W / "package_verification.json", package_report)
        dump(W / "skill_verification.json", skill_report)

    def check(name, passed, actual=None):
        package_report["checks"][name] = {"passed": bool(passed), "actual": actual}
        if not passed:
            package_report["errors"].append(name)

    try:
        if validator is None:
            skill_report["errors"].append("未找到真实安装的通用验证器，通用验证 pending，不得视为通过")
        else:
            skill_report["validator_sha256"] = sha(validator)
            skill_report["status"] = "running"
        persist()
        if not MAIN.is_file():
            raise FileNotFoundError("请先保存最终母版，绝不回退读取 working.blend：" + str(MAIN))
        source_before = sha(MAIN)
        palette_before = sha(PAL)
        catalog_before = sha(CATALOG)
        package_report.update(source_sha256_before=source_before, palette_sha256_before=palette_before, catalog_sha256_before=catalog_before)
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        all_entries = catalog["components"]
        entries = [e for e in all_entries if e.get("component_id", "").startswith("SEA-SCENE-SCITY-")]
        check("catalog_suite_count", 0 < len(entries) == EXPECTED_COUNT <= 50, len(entries))
        if VERSION in {"v003", "v004"}:
            plan = json.loads((D / "component_plan.json").read_text(encoding="utf-8"))
            planned = plan["components"]
            check(VERSION + "_current_plan_components", len(entries) == len(planned) == 50
                  and len({e["component_id"] for e in planned}) == 50
                  and len({e["key"] for e in planned}) == 50
                  and {(e["component_id"], e["key"]) for e in entries}
                  == {(e["component_id"], e["key"]) for e in planned})
        for field in ("component_id", "key", "collection", "root_object", "component_blend"):
            values = [e[field] for e in entries]
            check("catalog_unique_" + field, len(values) == len(set(values)), len(set(values)))
        for entry in entries:
            if not re.fullmatch(r"[a-z0-9_]+", entry["key"]):
                raise ValueError("不安全的组件 key")
            expected = PACKAGES / entry["key"] / (entry["key"] + ".blend")
            target = (R / entry["component_blend"]).resolve()
            if target != expected.resolve() or PACKAGES.resolve() not in target.parents:
                raise ValueError("组件路径越出本套件预定目录：" + str(target))
            if (R / entry["palette"]).resolve() != PAL.resolve():
                raise ValueError("catalog 不是本套件指定共享色盘")
            if not entry["material_roles"] or not set(entry["material_roles"]) <= ROLES:
                raise ValueError("catalog 含非法材质角色")
        if package_report["errors"]:
            raise RuntimeError("catalog 预检失败")
        package_report["stage"] = "source_read"
        bpy.ops.wm.open_mainfile(filepath=str(MAIN), load_ui=False, use_scripts=False)
        source_names = set()
        master_collections = {c.name for c in bpy.data.collections if c.name.startswith("SEA-SCENE-SCITY-")}
        check("source_exact_component_collection_set", master_collections == {e["collection"] for e in entries}, sorted(master_collections))
        if package_report["errors"]:
            raise RuntimeError("最终母版与 catalog 组件集合不一致")
        for entry in entries:
            collection = bpy.data.collections.get(entry["collection"])
            if collection is None:
                raise RuntimeError("最终母版缺少集合：" + entry["collection"])
            names = {obj.name for obj in collection.all_objects}
            if source_names & names:
                raise RuntimeError("源组件对象跨包重复归属")
            source_names.update(names)
        check("source_catalog_collections_found", True, len(entries))
        for entry in entries:
            row = {"key": entry["key"], "component_id": entry["component_id"], "stage": "source_audit",
                   "status": "running", "passed": False, "exit_code": None, "errors": []}
            package_report["components"].append(row)
            target = (R / entry["component_blend"]).resolve()
            skill_row = {"key": entry["key"], "stage": "generic_validator", "status": "pending", "passed": False,
                         "exit_code": None, "checks": {}, "errors": []}
            try:
                if sha(MAIN) != source_before or sha(PAL) != palette_before:
                    raise RuntimeError("母版或共享色盘在打包过程中发生变化")
                # 每次从最终磁盘源重新 append；不复用前一个包的任何数据块。
                row["stage"] = "append_and_save"
                appended, saved = append_package(entry, target)
                row["appended_audit"] = appended
                if not saved:
                    row["errors"].extend(appended["errors"])
                    raise RuntimeError("载入的源组件未通过审计，未保存此包")
                row["stage"] = "reopen_package"
                row["package_sha256"] = sha(target)
                row["package_bytes"] = target.stat().st_size
                bpy.ops.wm.open_mainfile(filepath=str(target), load_ui=False, use_scripts=False)
                bpy.context.view_layer.update()
                reopened = audit_component(entry, standalone=True)
                row["reopened_audit"] = reopened
                row["checks"] = {"reopen_audit_passed": reopened["passed"],
                                 "geometry_preserved": appended.get("geometry_fingerprint") == reopened.get("geometry_fingerprint"),
                                 "file_hash_unchanged_on_reopen": sha(target) == row["package_sha256"]}
                row["errors"].extend(name for name, passed in row["checks"].items() if not passed)
                row["stage"] = "generic_validator"
                if validator:
                    skill_row = run_generic(validator, entry, target, run_id)
                else:
                    skill_row["errors"].append("通用验证器缺失，未执行")
                if skill_row["passed"] is not True:
                    row["errors"].append("真实通用验证未通过，不得声明组件 passed")
                if sha(target) != row["package_sha256"]:
                    row["errors"].append("通用验证后包哈希与本轮保存结果不一致")
                manifest = dict(entry)
                manifest.update(schema="sea.component_asset_manifest.v1", asset_id=entry["component_id"],
                                source=MAIN.relative_to(R).as_posix(), source_master_sha256=source_before,
                                source_sha256=row["package_sha256"], geometry_fingerprint=reopened.get("geometry_fingerprint"),
                                bounds_min=reopened.get("bounds_min"), bounds_max=reopened.get("bounds_max"),
                                bounds_size_m=reopened.get("bounds_size_m"), objects=[o.name for o in bpy.data.collections[entry["collection"]].all_objects],
                                material_roles=reopened.get("material_roles"), local_origin=[0, 0, 0], emission=False,
                                animation=False, lights_in_component=False, preview_collection=DISPLAY,
                                palette_absolute=str(PAL.resolve()), palette_sha256=palette_before,
                                package_verification={"run_id": run_id, "passed": not row["errors"], "report": str(W / "package_verification.json")},
                                skill_verification={"status": skill_row["status"], "passed": skill_row["passed"], "report": skill_row.get("report"), "exit_code": skill_row["exit_code"]},
                                source_stage="source_verified_runtime_pending" if not row["errors"] and skill_row["passed"] else "source_verification_pending",
                                runtime_validation="not_executed_not_in_scope", exported=False,
                                asset_ledger='assets/registry/ledgers/scenes.json#' + entry['component_id'])
                row["stage"] = "write_manifest"
                dump(target.parent / "asset_manifest.json", manifest)
                row["manifest"] = str(target.parent / "asset_manifest.json")
                row["passed"] = not row["errors"]
                row["exit_code"] = 0 if row["passed"] else 1
                row["status"] = "passed" if row["passed"] else "failed"
                row["stage"] = "package_verified" if row["passed"] else "package_audit_failed"
                if row["passed"]:
                    updates[entry["component_id"]] = {"source_sha256": row["package_sha256"], "geometry_fingerprint": reopened["geometry_fingerprint"]}
            except Exception:
                row["errors"].append(traceback.format_exc())
                row.update(status="failed", passed=False, exit_code=1)
                if not skill_row["errors"] and skill_row["status"] == "pending":
                    skill_row["errors"].append("包未成功保存并重开，通用验证未执行；不验证旧包冒充本次结果")
            skill_report["components"].append(skill_row)
            persist()
            print("SUNKEN_CITY_PACKAGE", entry["key"], row["status"], "skill=" + skill_row["status"], flush=True)
        package_report["stage"] = "aggregate"
        produced = {str((R / e["component_blend"]).resolve()) for e in entries}
        disk_blends = {str(p.resolve()) for p in PACKAGES.rglob("*.blend")}
        disk_manifests = {str(p.resolve()) for p in PACKAGES.rglob("asset_manifest.json")}
        expected_manifests = {str((Path(p).parent / "asset_manifest.json").resolve()) for p in produced}
        check("exact_disk_package_set", disk_blends == produced, {"expected": len(produced), "actual": len(disk_blends), "extra": sorted(disk_blends - produced), "missing": sorted(produced - disk_blends)})
        check("exact_disk_manifest_set", disk_manifests == expected_manifests, {"actual": len(disk_manifests), "extra": sorted(disk_manifests - expected_manifests), "missing": sorted(expected_manifests - disk_manifests)})
        check("all_packages_reopened_and_passed", len(updates) == EXPECTED_COUNT, len(updates))
        skill_report["checks"] = {"validator_exists": validator is not None,
                                  "every_package_executed": len(skill_report["components"]) == EXPECTED_COUNT and all(r["exit_code"] is not None for r in skill_report["components"]),
                                  "every_package_passed": len(skill_report["components"]) == EXPECTED_COUNT and all(r["passed"] for r in skill_report["components"]),
                                  "validator_hash_unchanged": validator is not None and sha(validator) == skill_report["validator_sha256"]}
        skill_report["passed"] = all(skill_report["checks"].values())
        skill_report["status"] = "passed" if skill_report["passed"] else ("pending" if validator is None else "failed")
        skill_report["stage"] = "aggregate"
        skill_report["exit_code"] = 0 if skill_report["passed"] else 1
        check("all_package_hashes_unchanged_before_commit", len(updates) == EXPECTED_COUNT
              and all(sha(R / e["component_blend"]) == updates[e["component_id"]]["source_sha256"]
                      for e in entries if e["component_id"] in updates))
        check("source_hash_unchanged_before_commit", sha(MAIN) == source_before)
        check("palette_hash_unchanged_before_commit", sha(PAL) == palette_before)
        check("catalog_hash_unchanged_before_commit", sha(CATALOG) == catalog_before)
        if package_report["errors"] or not skill_report["passed"]:
            failure = True
        else:
            package_report["stage"] = "catalog_commit"
            for entry in all_entries:
                if entry.get("component_id") in updates:
                    # 只改本套件这两个字段，不升级已有 source_stage，不刷新其他资产。
                    entry.update(updates[entry["component_id"]])
            dump(CATALOG, catalog)
            package_report["catalog_updated"] = True
            package_report["catalog_sha256_after"] = sha(CATALOG)
    except Exception:
        failure = True
        package_report["errors"].append(traceback.format_exc())
    finally:
        # 失败也保留实际已执行检查、阶段和子进程退出码；绝不以空列表判全绿。
        for name, path, before in (("source", MAIN, source_before), ("palette", PAL, palette_before)):
            if before is not None:
                try:
                    after = sha(path)
                    package_report[name + "_sha256_after"] = after
                    check(name + "_hash_unchanged_final", after == before, {"before": before, "after": after})
                except Exception:
                    failure = True
                    package_report["errors"].append(traceback.format_exc())
        if skill_report["exit_code"] is None:
            skill_report["status"] = "pending" if validator is None else "failed"
            skill_report["exit_code"] = 1
            skill_report["errors"].append("流程在全部通用验证完成前终止")
        failure = failure or bool(package_report["errors"]) or not skill_report["passed"]
        package_report["package_checks_passed"] = (len(updates) == EXPECTED_COUNT and not package_report["errors"])
        package_report["passed"] = not failure and package_report["catalog_updated"]
        package_report["status"] = "passed" if package_report["passed"] else "failed"
        package_report["exit_code"] = 0 if package_report["passed"] else 1
        if package_report["passed"]:
            package_report["stage"] = "complete"
        package_report["finished_at"] = datetime.now(timezone.utc).isoformat()
        package_report["packages_reopened"] = sum("reopened_audit" in r for r in package_report["components"])
        skill_report["source_sha256"] = source_before
        persist()
    print("SUNKEN_CITY_RESULT", package_report["status"], "exit_code=" + str(package_report["exit_code"]), flush=True)
    return package_report["exit_code"]


if __name__ == "__main__":
    if not bpy.app.background:
        raise RuntimeError("禁止在 GUI/MCP 执行；请另起 Blender --background")
    parser = argparse.ArgumentParser(description="sunken_city 独立包及源级验证，仅供后台执行")
    parser.add_argument("--skill-worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--validator", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--report", type=Path, help=argparse.SUPPRESS)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)
    if args.skill_worker:
        if args.validator is None or not args.validator.is_file() or args.report is None:
            raise RuntimeError("通用验证子进程参数无效")
        skill_worker(args)
    else:
        raise SystemExit(main())
