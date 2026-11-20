"""街机屋的 Blender 后处理。以 -- 后的 package / render / animation / verify 选择操作。"""

import argparse
from collections import Counter
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[3]
SUITE = "rooftop_arcade"
VERSION = "v001"
FOLDER = ROOT / "art_source/scenes" / SUITE / VERSION
SOURCE = FOLDER / f"{SUITE}.blend"
PLAN = FOLDER / "component_plan.json"
PALETTE = ROOT / "art_source/shared/palettes/sea_rooftop_arcade_8x8_512.png"
EXPORT = FOLDER / "export" / VERSION
OPTIMIZED = EXPORT / f"{SUITE}_optimized_{VERSION}.blend"
PREFIX = "SEA-SCENE-RAC-"
MASTER, STATIC, INTERIOR, ANIMATION = (
    "街机屋_组件母版", "街机屋_参考装配", "街机屋_室内剖视", "街机屋_组装动画",
)
VIEWS = {STATIC: ("Hero", "Front", "Right", "Back"), INTERIOR: ("Shop", "Loft", "Plan", "Dollhouse", "Utility")}
STAGES = (1, 42, 86, 126, 166, 205, 241)
AIRDROP_STAGES = (1, 65, 113, 161, 209, 260, 345)
SPRING_STAGES = (1, 46, 78, 110, 142, 178, 222)
MATRIX_TOL = 1e-4
ORIGIN_TOL = 1e-4


def work_dir():
    return Path(os.environ.get("SEA_WORK_ROOT") or ROOT.parent / "sea-work").expanduser().resolve() / f"{SUITE}_{VERSION}"


def log(message):
    print(f"[rooftop_arcade] {message}", flush=True)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def file_record(path):
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": sha256(path), "bytes": path.stat().st_size}


def matrix_matches(a, b):
    return all(abs(x - y) <= MATRIX_TOL for ar, br in zip(a, b) for x, y in zip(ar, br))


def vec(value):
    return [float(x) for x in value]


def collection_tree(parent):
    for child in parent.children:
        yield child
        yield from collection_tree(child)


def normalize_key(value):
    return str(value).lower().replace("-", "_")


def key_for_collection(collection):
    key = normalize_key(collection.get("asset_key", collection.name[len(PREFIX):]))
    require(re.fullmatch(r"[a-z0-9]+(?:_[a-z0-9]+)*", key), f"无效组件键：{collection.name} / {key}")
    return key


@contextmanager
def active_scene(scene):
    window = bpy.context.window
    previous = window.scene if window is not None else None
    if window is not None:
        window.scene = scene
    try:
        with bpy.context.temp_override(scene=scene, view_layer=scene.view_layers[0]):
            bpy.context.view_layer.update()
            yield
    finally:
        if window is not None:
            window.scene = previous


def image_path(image, blend_path):
    raw = image.filepath
    if raw.startswith("//"):
        return (blend_path.parent / raw[2:]).resolve()
    path = Path(raw).expanduser()
    if path.is_absolute():
        return path.resolve()
    base = ROOT if path.parts and path.parts[0] == "art_source" else blend_path.parent
    return (base / path).resolve()


def palette_images(objects, blend_path, errors, relative_required=False):
    images = set()
    materials = {slot.material for obj in objects for slot in obj.material_slots if slot.material}
    for material in sorted(materials, key=lambda item: item.name):
        nodes = material.node_tree.nodes if material.use_nodes and material.node_tree else ()
        found = False
        for node in nodes:
            if node.type != "TEX_IMAGE" or node.image is None:
                continue
            image = node.image
            if image_path(image, blend_path) != PALETTE.resolve():
                errors.append(f"{material.name} 引用了非共享色板图片：{image.filepath}")
                continue
            found = True
            images.add(image)
            if image.source != "FILE" or image.packed_file or len(image.packed_files):
                errors.append(f"{image.name} 必须是未打包的外部图片")
            if relative_required and not image.filepath.startswith("//"):
                errors.append(f"{blend_path.name} 的色板不是 Blender 相对路径：{image.filepath}")
        if not found:
            errors.append(f"{material.name} 未引用共享色板")
    if not images:
        errors.append(f"{blend_path.name} 未找到共享色板图片引用")
    return images


@contextmanager
def output_palette_paths(images, destination):
    # 已按目标 .blend 计算路径，写出时禁止 Blender 再重映射。
    relative = "//" + Path(os.path.relpath(PALETTE, destination.parent)).as_posix()
    previous = [(image, image.filepath) for image in images]
    try:
        for image, _ in previous:
            image.filepath_raw = relative
        yield
    finally:
        for image, path in previous:
            image.filepath_raw = path


def mesh_signature(digest, obj):
    mesh = obj.data
    digest.update((obj.name + "\0").encode("utf-8"))
    digest.update(struct.pack("<III", len(mesh.vertices), len(mesh.polygons), len(mesh.loops)))
    for vertex in mesh.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
    for polygon in mesh.polygons:
        digest.update(struct.pack("<II?", polygon.loop_total, polygon.material_index, polygon.use_smooth))
    for loop in mesh.loops:
        digest.update(struct.pack("<I", loop.vertex_index))
    for layer in mesh.uv_layers:
        digest.update((layer.name + "\0").encode("utf-8"))
        for uv in layer.uv:
            digest.update(struct.pack("<2f", *uv.vector))


def topology(mesh):
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        result = {
            "wire_edges": sum(edge.is_wire for edge in bm.edges),
            "boundary_edges": sum(edge.is_boundary for edge in bm.edges),
            "non_manifold_edges": sum(not edge.is_manifold and not edge.is_boundary and not edge.is_wire for edge in bm.edges),
            "non_manifold_vertices": sum(not vertex.is_manifold for vertex in bm.verts),
            "loose_vertices": sum(not vertex.link_edges for vertex in bm.verts),
            "inconsistent_winding_edges": sum(edge.is_manifold and not edge.is_contiguous for edge in bm.edges),
        }
        result["closed_manifold_meshes"] = int(bool(bm.faces) and not any(result.values()))
        return result
    finally:
        bm.free()


def inspect_component(collection, errors, with_topology):
    key = key_for_collection(collection)
    objects = sorted(collection.objects, key=lambda item: item.name)
    if not objects or collection.children:
        errors.append(f"{collection.name} 必须直接包含网格且不得包含子集合")
    if collection.instance_offset.length > ORIGIN_TOL:
        errors.append(f"{collection.name} 的 instance_offset 不为零")
    identity = Matrix.Identity(4)
    lows, highs = [float("inf")] * 3, [-float("inf")] * 3
    counts = Counter()
    materials = set()
    digest = hashlib.sha256()
    for obj in objects:
        if obj.type != "MESH":
            errors.append(f"{collection.name} 包含非网格对象 {obj.name}")
            continue
        if obj.parent is not None or not matrix_matches(obj.matrix_basis, identity) or not matrix_matches(obj.matrix_world, identity):
            errors.append(f"{obj.name} 的母版变换不为恒等或具有父对象")
        if any(mod.type == "BEVEL" for mod in obj.modifiers):
            errors.append(f"{obj.name} 仍有未应用的 BEVEL 修改器")
        counts["weighted_normal_modifier_meshes"] += int(any(mod.type == "WEIGHTED_NORMAL" for mod in obj.modifiers))
        mesh = obj.data
        counts["custom_normal_meshes"] += int(mesh.has_custom_normals)
        if not mesh.polygons:
            errors.append(f"{obj.name} 没有网格面")
            continue
        uv = mesh.uv_layers.active
        if uv is None or uv.name != "PaletteUV" or not uv.active_render:
            errors.append(f"{obj.name} 的 PaletteUV 未同时设为活动及渲染 UV")
        for vertex in mesh.vertices:
            for axis, value in enumerate(vertex.co):
                lows[axis] = min(lows[axis], value)
                highs[axis] = max(highs[axis], value)
        mesh.calc_loop_triangles()
        counts.update(objects=1, vertices=len(mesh.vertices), polygons=len(mesh.polygons), triangles=len(mesh.loop_triangles))
        materials.update(slot.material.name for slot in obj.material_slots if slot.material)
        if not any(slot.material for slot in obj.material_slots):
            errors.append(f"{obj.name} 没有材质")
        mesh_signature(digest, obj)
        if with_topology:
            counts.update(topology(mesh))
    bounds = None
    if counts["objects"]:
        bounds = {"min_m": lows, "max_m": highs, "size_m": [hi - lo for lo, hi in zip(lows, highs)]}
        if abs(lows[2]) > ORIGIN_TOL:
            errors.append(f"{collection.name} 的最小本地 Z 为 {lows[2]:.6f} m，预期 0 m")
    return {"asset_key": key, "asset_id": collection.name, "collection": collection.name,
            "bounds": bounds, "geometry_sha256": digest.hexdigest(), "materials": sorted(materials), **counts}


def index_instances(scene, components, errors):
    result = {}
    for obj in scene.objects:
        collection = obj.instance_collection
        if collection is None and obj.instance_type != "COLLECTION":
            if obj.type == "EMPTY" and ("asset_key" in obj or "instance_index" in obj):
                errors.append(f"{scene.name}/{obj.name} 有实例属性但未链接集合")
            continue
        if obj.type != "EMPTY" or obj.instance_type != "COLLECTION" or collection is None:
            errors.append(f"{scene.name}/{obj.name} 不是有效的 EMPTY 集合实例")
            continue
        raw_key, index, phase = (obj.get(name) for name in ("asset_key", "instance_index", "phase"))
        if not isinstance(raw_key, str) or type(index) is not int or not isinstance(phase, (str, int, float)):
            errors.append(f"{scene.name}/{obj.name} 的 asset_key、instance_index 或 phase 缺失或类型错误")
            continue
        key = normalize_key(raw_key)
        if key not in components or collection != components[key]:
            errors.append(f"{scene.name}/{obj.name} 的 asset_key 与所实例化的母版集合不一致")
            continue
        identity = (key, index)
        if identity in result:
            errors.append(f"{scene.name} 重复实例键：{identity}")
        else:
            result[identity] = obj
    return result


def active_curves(obj):
    ad = obj.animation_data
    if ad is None or ad.action is None:
        return ()
    action, slot = ad.action, ad.action_slot
    curves = []
    # Blender 5 的 Action 以 slot 隔离同一 Action 内不同对象的曲线。
    if slot is not None:
        for layer in action.layers:
            for strip in layer.strips:
                if strip.type == "KEYFRAME":
                    bag = strip.channelbag(slot)
                    if bag is not None:
                        curves.extend(bag.fcurves)
    if not curves and not action.layers:
        curves = getattr(action, "fcurves", ())
    return curves


def keyed_frames(obj):
    paths = {"location", "rotation_euler", "rotation_quaternion", "rotation_axis_angle", "scale", "hide_render", "hide_viewport"}
    frames = {}
    for curve in active_curves(obj):
        if curve.data_path in paths and curve.keyframe_points:
            frames.setdefault(curve.data_path, set()).update(float(p.co.x) for p in curve.keyframe_points)
    return {path: sorted(values) for path, values in sorted(frames.items())}


def inspect_vertical_motion(scene, animated, source_matrices, errors):
    """Check channels, entry bounds and motion samples without mutating the scene."""
    mode = scene.get('assembly_motion')
    if mode not in ('vertical_setdown_v2', 'offscreen_airdrop_v3', 'spring_drop_v4'):
        return None
    spring = mode == 'spring_drop_v4'
    air = mode != 'vertical_setdown_v2'
    tol = MATRIX_TOL
    bad = []
    first, last = scene.frame_start, scene.frame_end
    cam = scene.camera
    if cam is None or cam.data.type != 'ORTHO' or cam.animation_data or cam.data.animation_data:
        bad.append('camera must be fixed orthographic')
    minimum_margin = float('inf')
    min_crossing_frames = float('inf')
    if air and cam is not None:
        view_inverse = cam.rotation_euler.to_matrix().transposed()
        view_top = max(v.y for v in cam.data.view_frame(scene=scene))
        z_projection = (view_inverse @ Vector((0,0,1))).y
    for identity, obj in sorted(animated.items()):
        curves = {(curve.data_path, curve.array_index): curve for curve in active_curves(obj)}
        expected = {('location', 2)} if air else {('location', 2), ('hide_render', 0), ('hide_viewport', 0)}
        if set(curves) != expected or len(active_curves(obj)) != len(expected) or obj.parent or obj.constraints:
            bad.append(f'{identity}: unexpected animated channels or transform parent'); continue
        if identity not in source_matrices:
            bad.append(f'{identity}: missing static matrix'); continue
        state = obj.matrix_basis.copy()
        state.translation.z = source_matrices[identity].translation.z
        if not matrix_matches(state, source_matrices[identity]):
            bad.append(f'{identity}: static X/Y, orientation or scale differs'); continue
        start, land, height = (obj.get(p) for p in ('assembly_enter','assembly_landed','assembly_drop_m'))
        limit = 20.0 if air else .50
        if not isinstance(start,int) or not isinstance(land,int) or not first < start < land < last or not isinstance(height,(int,float)) or not .15 <= height <= limit:
            bad.append(f'{identity}: invalid entrance timing or travel'); continue
        base = source_matrices[identity].translation.z
        zcurve = curves[('location', 2)]
        if air:
            if cam is None or obj.hide_render or obj.hide_viewport or obj.animation_data.drivers or obj.animation_data.nla_tracks:
                bad.append(f'{identity}: hidden or additional animation'); continue
            impact = obj.get('assembly_impact') if spring else land
            if spring:
                apex, second_impact, second_apex, lift = (obj.get(f'assembly_{k}') for k in ('bounce_apex','second_impact','second_apex','bounce_m'))
                times = [start,impact,apex,second_impact,second_apex,land]
                if any(not isinstance(t,(float,int)) for t in times) or any(b <= a for a,b in zip(times,times[1:])) or not isinstance(lift,(float,int)) or not .06 <= lift <= .15:
                    bad.append(f'{identity}: invalid impact or rebound parameters'); continue
                heights = [height,0,lift,0,lift*.19,0]
            else:
                times, heights = [start, land], [height, 0]
            points = list(zcurve.keyframe_points)
            if len(points) != len(times) or [round(p.co.x, 5) for p in points] != times or any(p.interpolation != 'BEZIER' for p in points[:-1]) or zcurve.extrapolation != 'CONSTANT' or len(zcurve.modifiers):
                bad.append(f'{identity}: noncontinuous or unexpected trajectory'); continue
            if any(abs(zcurve.evaluate(t)-base-h)>tol for t,h in zip(times,heights)):
                bad.append(f'{identity}: missed contact or rebound apex'); continue
            if spring:
                valid_legs = True
                for t0,t1,h0,h1 in zip(times,times[1:],heights,heights[1:]):
                    for i in range(1,32):
                        u = i/32
                        weight = u*u if h1 < h0 else 2*u-u*u
                        actual = zcurve.evaluate(t0+(t1-t0)*u)-base
                        if abs(actual-(h0+(h1-h0)*weight))>tol or actual < -tol:
                            valid_legs = False
                if not valid_legs:
                    bad.append(f'{identity}: acceleration or damping curve deviates'); continue
            matrix = source_matrices[identity]
            projected = [(view_inverse @ (matrix @ (mesh.matrix_basis @ Vector(corner)) - cam.location)).y
                         for mesh in obj.instance_collection.all_objects if mesh.type == 'MESH' for corner in mesh.bound_box]
            low, high = min(projected), max(projected)
            margin = low + (zcurve.evaluate(first)-base)*z_projection - view_top
            minimum_margin = min(minimum_margin, margin)
            if margin < .15 or high >= view_top:
                bad.append(f'{identity}: invalid bounds at offscreen start or final placement'); continue
            # A fractional crossing demonstrates continuous entry even for thin bricks.
            crossing = sum(low + (zcurve.evaluate(t/24)-base)*z_projection < view_top < high + (zcurve.evaluate(t/24)-base)*z_projection
                           for t in range(start*24, impact*24+1)) / 24
            min_crossing_frames = min(min_crossing_frames, crossing)
            if crossing <= 0:
                bad.append(f'{identity}: no continuous top-edge crossing'); continue
        previous = base + height
        for frame in range(first, last+1):
            z = zcurve.evaluate(frame)
            still_falling = not spring or frame <= impact
            if (still_falling and z > previous + tol) or z < base - tol or (frame <= start and abs(z-base-height) > tol) or (frame >= land and abs(z-base) > tol):
                bad.append(f'{identity}: invalid Z at {frame}'); break
            if not air and any(bool(curves[(channel,0)].evaluate(frame) > .5) != (frame < start) for channel in ('hide_render','hide_viewport')):
                bad.append(f'{identity}: invalid visibility at {frame}'); break
            previous = z
    errors.extend('竖直装配：'+reason for reason in bad)
    return {'mode':mode, 'fixed_orthographic_camera':not bool(cam is None or cam.animation_data or cam.data.animation_data),
            'instances':len(animated), 'frame_samples':len(animated)*(last-first+1), 'errors':len(bad),
            **({'no_visibility_tracks':not bad, 'minimum_offscreen_margin_m':round(minimum_margin,4) if minimum_margin != float('inf') else None,
                'minimum_top_edge_crossing_frames':round(min_crossing_frames,4) if min_crossing_frames != float('inf') else None} if air else {})}


def inspect_assembly(scenes, components, catalog, errors):
    static_scene, anim_scene = scenes[STATIC], scenes[ANIMATION]
    static = index_instances(static_scene, components, errors)
    animated = index_instances(anim_scene, components, errors)
    if not static:
        errors.append("参考装配没有有效实例")
    if static.keys() != animated.keys():
        errors.append(f"装配与动画的实例键不一致：仅静态 {sorted(static.keys() - animated.keys())}；仅动画 {sorted(animated.keys() - static.keys())}")
    source_matrices, rows = {}, []
    component_by_key = {entry["asset_key"]: entry for entry in catalog}
    with active_scene(static_scene):
        graph = bpy.context.evaluated_depsgraph_get()
        for identity, obj in sorted(static.items()):
            key, index = identity
            evaluated = obj.evaluated_get(graph)
            matrix = evaluated.matrix_world.copy()
            source_matrices[identity] = matrix
            position, rotation, scale = matrix.decompose()
            if obj.animation_data and (obj.animation_data.action or obj.animation_data.drivers or obj.animation_data.nla_tracks):
                errors.append(f"静态装配实例 {obj.name} 带有动画数据")
            if evaluated.hide_render or evaluated.hide_viewport:
                errors.append(f"静态装配实例 {obj.name} 被隐藏")
            rows.append({"name": obj.name, "asset_key": key, "asset_id": component_by_key[key]["asset_id"],
                         "instance_index": index, "phase": obj["phase"], "position_m": vec(position),
                         "rotation_euler_xyz": vec(rotation.to_euler("XYZ")), "rotation_quaternion_wxyz": vec(rotation),
                         "scale": vec(scale), "matrix_world": [vec(row) for row in matrix]})
    matched = sorted(static.keys() & animated.keys())
    keyed = 0
    for identity, obj in sorted(animated.items()):
        if keyed_frames(obj):
            keyed += 1
        else:
            errors.append(f"动画实例 {obj.name} 不含变换或可见性关键帧")
        if identity in static and any(static[identity][prop] != obj[prop] for prop in ("asset_key", "instance_index", "phase")):
            errors.append(f"实例 {identity} 的静态和动画自定义属性不同")
    stages = {'offscreen_airdrop_v3': AIRDROP_STAGES, 'spring_drop_v4': SPRING_STAGES}.get(anim_scene.get('assembly_motion'), STAGES)
    if (anim_scene.frame_start, anim_scene.frame_end) != (stages[0], stages[-1]):
        errors.append(f"动画场景帧范围应为 {stages[0]}–{stages[-1]}")
    stage_counts, final_mismatches = [], []
    previous_frame = anim_scene.frame_current
    with active_scene(anim_scene):
        try:
            for frame in stages:
                anim_scene.frame_set(frame)
                graph = bpy.context.evaluated_depsgraph_get()
                landed_by_phase = Counter()
                for identity in matched:
                    obj = animated[identity]
                    evaluated = obj.evaluated_get(graph)
                    landed = not (evaluated.hide_render or evaluated.hide_viewport) and matrix_matches(evaluated.matrix_world, source_matrices[identity])
                    if landed:
                        landed_by_phase[str(obj["phase"])] += 1
                    elif frame == stages[-1]:
                        final_mismatches.append({"asset_key": identity[0], "instance_index": identity[1], "name": obj.name})
                stage_counts.append({"frame": frame, "landed": sum(landed_by_phase.values()), "by_phase": dict(sorted(landed_by_phase.items()))})
        finally:
            anim_scene.frame_set(previous_frame)
    if any(a["landed"] >= b["landed"] for a, b in zip(stage_counts, stage_counts[1:])):
        errors.append(f"阶段到位数量未严格递增：{[(row['frame'], row['landed']) for row in stage_counts]}")
    if stage_counts[-1]["landed"] != len(static) or final_mismatches:
        errors.append(f"第 {stages[-1]} 帧未完整匹配静态：到位 {stage_counts[-1]['landed']}/{len(static)}")
    return rows, {
        "static_instance_count": len(static), "animation_instance_count": len(animated), "keyed_instance_count": keyed,
        "source_fps": anim_scene.render.fps / anim_scene.render.fps_base, "landed_counts": stage_counts,
        "landed_definition": "实例可见（对象可见性标志）且求值后的世界矩阵与静态实例相符；不代表碰撞或支撑接触验证。",
        "matrix_tolerance": MATRIX_TOL, "final_mismatches": final_mismatches,
        **({'vertical_motion': inspect_vertical_motion(anim_scene, animated, source_matrices, errors)} if anim_scene.get('assembly_motion') else {}),
        "expanded_polygons": sum(component_by_key[key].get("polygons", 0) for key, _ in static),
        "expanded_triangles": sum(component_by_key[key].get("triangles", 0) for key, _ in static),
    }


def inspect_source(plan, blend_path, with_topology=True, relative_required=False):
    errors = []
    scenes = {scene.name: scene for scene in bpy.data.scenes}
    missing = sorted({MASTER, STATIC, INTERIOR, ANIMATION} - scenes.keys())
    unexpected = sorted(scenes.keys() - {MASTER, STATIC, INTERIOR, ANIMATION})
    if missing or unexpected:
        errors.append(f"场景命名不符：缺少 {missing}；额外 {unexpected}")
    master = scenes.get(MASTER)
    components, catalog = {}, []
    if master is not None:
        membership = Counter()
        with active_scene(master):
            for collection in sorted(set(collection_tree(master.collection)), key=lambda item: item.name):
                if not collection.name.startswith(PREFIX):
                    if collection.objects:
                        errors.append(f"母版分组 {collection.name} 不应直接包含对象")
                    continue
                key = key_for_collection(collection)
                if key in components:
                    errors.append(f"重复组件键：{key}")
                    continue
                components[key] = collection
                membership.update(collection.objects)
                catalog.append(inspect_component(collection, errors, with_topology))
            for obj in master.objects:
                if membership[obj] != 1 or obj.name in master.collection.objects:
                    errors.append(f"母版对象 {obj.name} 必须且只能直接属于一个组件集合")
        detached = sorted(c.name for c in bpy.data.collections if c.name.startswith(PREFIX) and c not in components.values())
        if detached:
            errors.append(f"发现未登记到组件母版的组件集合：{detached}")
    planned = {key: group for group, keys in plan["components"].items() for key in keys}
    if planned.keys() != components.keys():
        errors.append(f"组件与计划不符：缺少 {sorted(planned.keys() - components.keys())}；额外 {sorted(components.keys() - planned.keys())}")
    images = palette_images((obj for c in components.values() for obj in c.objects if obj.type == "MESH"),
                            blend_path, errors, relative_required)
    for scene_name, names in VIEWS.items():
        if scene_name in scenes:
            for name in names:
                camera = scenes[scene_name].objects.get(name)
                if camera is None or camera.type != "CAMERA":
                    errors.append(f"{scene_name} 缺少相机 {name}")
    if ANIMATION in scenes and scenes[ANIMATION].camera is None:
        errors.append(f"{ANIMATION} 缺少活动相机")
    instances, assembly = (inspect_assembly(scenes, components, catalog, errors)
                           if STATIC in scenes and ANIMATION in scenes else ([], {}))
    expected_fps = plan.get("animation", {}).get("fps")
    if assembly and expected_fps is not None and abs(assembly["source_fps"] - expected_fps) > 1e-4:
        errors.append(f"动画帧率与计划不符：{assembly['source_fps']:g}，预期 {expected_fps:g}")
    instance_counts = Counter(row["asset_key"] for row in instances)
    for entry in catalog:
        key = entry["asset_key"]
        entry.update(family=planned.get(key), instance_count=instance_counts[key], origin="bottom_center", front_axis="-Y")
    stats = {field: sum(entry.get(field, 0) for entry in catalog) for field in (
        "objects", "polygons", "triangles", "closed_manifold_meshes", "boundary_edges", "wire_edges",
        "non_manifold_edges", "non_manifold_vertices", "loose_vertices", "inconsistent_winding_edges",
        "weighted_normal_modifier_meshes", "custom_normal_meshes",
    ) if with_topology or field in ("objects", "polygons", "triangles")}
    return {"errors": errors, "scenes": sorted(scenes), "catalog": catalog, "instances": instances,
            "assembly": assembly, "master_mesh_stats": stats}, components, images


def inspect_glb(path):
    with path.open("rb") as stream:
        header = stream.read(12)
        require(len(header) == 12, f"{path.name} 的 GLB 文件头截断")
        magic, version, length = struct.unpack("<4sII", header)
        require(magic == b"glTF" and version == 2 and length == path.stat().st_size, f"{path.name} 的 GLB 文件头不合法")
        document, binary = None, False
        while stream.tell() < length:
            header = stream.read(8)
            require(len(header) == 8, f"{path.name} 的 GLB 块头截断")
            size, kind = struct.unpack("<I4s", header)
            require(size % 4 == 0 and stream.tell() + size <= length, f"{path.name} 的 GLB 块长度不合法")
            if document is None:
                require(kind == b"JSON" and size > 0, f"{path.name} 的首个 GLB 块必须是 JSON")
                document = json.loads(stream.read(size))
            else:
                require(kind != b"JSON" and not (kind == b"BIN\x00" and binary), f"{path.name} 有重复的标准 GLB 块")
                binary = binary or kind == b"BIN\x00"
                stream.seek(size, os.SEEK_CUR)
    require(isinstance(document, dict) and binary, f"{path.name} 缺少 GLB JSON 或 BIN 块")
    require(not document.get("images"), f"{path.name} 不应包含任何图片引用")
    require(not set(document.get("extensionsUsed", ())) & {"KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_mesh_quantization", "MSFT_lod"},
            f"{path.name} 不应包含网格压缩、量化或 LOD 扩展")
    meshes, accessors = document.get("meshes", []), document.get("accessors", [])
    primitives = [primitive for mesh in meshes for primitive in mesh.get("primitives", [])]
    require(primitives, f"{path.name} 没有 glTF 网格图元")
    for primitive in primitives:
        attributes = primitive.get("attributes", {})
        uv_index, pos_index = attributes.get("TEXCOORD_0"), attributes.get("POSITION")
        require(all(type(index) is int and 0 <= index < len(accessors) for index in (uv_index, pos_index)),
                f"{path.name} 的图元缺少有效的 TEXCOORD_0 或 POSITION")
        uv, position = accessors[uv_index], accessors[pos_index]
        require(uv.get("type") == "VEC2" and uv.get("count", 0) > 0 and uv["count"] == position.get("count"),
                f"{path.name} 的 TEXCOORD_0 数据与顶点不匹配")
    return {"mesh_count": len(meshes), "primitive_count": len(primitives), "texcoord_0_primitive_count": len(primitives), "image_count": 0}


def write_component(collection, entry, images):
    key = entry["asset_key"]
    blend, glb = FOLDER / "components" / f"{key}.blend", EXPORT / f"{key}.glb"
    scene = bpy.data.scenes.new(f"街机屋_组件_{key}")
    scene.unit_settings.system = "METRIC"
    scene["asset_key"] = key
    scene["asset_id"] = collection.name
    scene.collection.children.link(collection)
    try:
        with active_scene(scene):
            with output_palette_paths(images, blend):
                bpy.data.libraries.write(str(blend), {scene}, path_remap="NONE", fake_user=True, compress=True)
            options = bpy.ops.export_scene.gltf.get_rna_type().properties
            settings = {"filepath": str(glb), "export_format": "GLB", "use_active_scene": True,
                        "export_texcoords": True, "export_normals": True, "export_image_format": "NONE",
                        "export_materials": "EXPORT", "export_animations": False, "export_yup": True,
                        "export_apply": True, "export_cameras": False, "export_lights": False}
            if "export_draco_mesh_compression_enable" in options:
                settings["export_draco_mesh_compression_enable"] = False
            require(bpy.ops.export_scene.gltf(**settings) == {"FINISHED"}, f"{glb.name} 导出失败")
    finally:
        bpy.data.scenes.remove(scene)
    entry.update(component_blend=file_record(blend), staging_glb={**file_record(glb), **inspect_glb(glb)})


def write_optimized(images):
    # 只清理无用户的本地叶数据块，保留所有场景、集合、动作及网格内容。
    removed = {}
    for kind in ("meshes", "curves", "cameras", "lights", "materials", "images"):
        blocks = getattr(bpy.data, kind)
        unused = [block for block in blocks if not block.users and not block.use_fake_user and block.library is None]
        for block in unused:
            blocks.remove(block)
        removed[kind] = len(unused)
    with output_palette_paths(images, OPTIMIZED):
        result = bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED), compress=True, copy=True, relative_remap=False)
        require(result == {"FINISHED"}, "优化副本保存失败")
    return {**file_record(OPTIMIZED), "unused_local_datablocks_removed": removed,
            "geometry_policy": "原网格不修改；仅清理零用户的本地叶数据块并压缩写盘。", "visual_comparison": "pending"}


def checks_pass(errors):
    require(not errors, f"验收发现 {len(errors)} 项错误：" + "；".join(errors[:8]))


def package(plan):
    out = work_dir()
    source = file_record(SOURCE)
    report, components, images = inspect_source(plan, SOURCE)
    write_json(out / "package_report.json", {"passed": False, "source": source, **report})
    checks_pass(report["errors"])
    catalog, instances = report["catalog"], report["instances"]
    (FOLDER / "components").mkdir(exist_ok=True)
    EXPORT.mkdir(parents=True, exist_ok=True)
    try:
        for number, entry in enumerate(catalog, 1):
            log(f"打包 {number}/{len(catalog)}：{entry['asset_key']}")
            write_component(components[entry["asset_key"]], entry, images)
        optimized = write_optimized(images)
        require(sha256(SOURCE) == source["sha256"], "母版文件 SHA-256 在打包期间发生变化")
    except Exception as exc:
        report["errors"].append(str(exc))
        write_json(out / "package_report.json", {"passed": False, "source": source, **report})
        raise
    palette = file_record(PALETTE)
    base = {"schema_version": 1, "suite": SUITE, "version": VERSION, "source": source, "source_sha256": source["sha256"]}
    catalog_path, instances_path = FOLDER / "catalog.json", FOLDER / "component_instances.json"
    write_json(catalog_path, {**base, "palette": palette, "components": catalog})
    write_json(instances_path, {**base, "scene": STATIC, "animation_scene": ANIMATION, "units": "meters",
                                 "coordinate_mapping": "(x,y,z)->(x,z,-y)", "instances": instances, "assembly": report["assembly"]})
    manifest = {**base, "display_name": plan.get("display_name"), "feature_id": plan.get("feature_id"),
                "source_stage": plan.get("source_stage"), "runtime_integration": "pending",
                "reference_license": plan.get("reference_license", "pending"), "references": plan.get("references", []),
                "palette": palette, "plan": file_record(PLAN), "catalog": file_record(catalog_path),
                "component_instances": file_record(instances_path), "scenes": report["scenes"],
                "components": catalog, "component_count": len(catalog), "assembly": report["assembly"],
                "master_mesh_stats": report["master_mesh_stats"], "optimized_blend": optimized,
                "contact_dimensions": contact_dimensions(plan),
                "staging_glb_policy": {"texcoord_0": "required on all primitives", "images": "none", "runtime_palette_binding": "pending"},
                "visual_acceptance": "pending", "saved_package_reopen": "run verify"}
    write_json(FOLDER / "asset_manifest.json", manifest)
    write_json(out / "package_report.json", {"passed": True, "source_unchanged": True, **manifest})
    log(f"打包完成：{len(catalog)} 个独立组件，{len(instances)} 个静态实例")


def refresh_motion(plan):
    """Refresh the assembly derivatives only; keep every part package untouched."""
    manifest_path = FOLDER / 'asset_manifest.json'
    catalog_path = FOLDER / 'catalog.json'
    pose_path = FOLDER / 'component_instances.json'
    manifest, catalog, poses = (read_json(p) for p in (manifest_path,catalog_path,pose_path))
    source = file_record(SOURCE)
    report, _, images = inspect_source(plan, SOURCE)
    checks_pass(report['errors'])
    require(report['assembly'].get('vertical_motion', {}).get('errors') == 0, '竖直装配自检失败')
    require(report['instances'] == poses['instances'], '静态摆位意外变动')
    require(report['master_mesh_stats'] == manifest['master_mesh_stats'], '母版网格统计意外变动')
    previous = {c['asset_id']: c for c in manifest['components']}
    require(set(previous) == {c['asset_id'] for c in report['catalog']}, '组件集合意外变动')
    for component in report['catalog']:
        saved = previous[component['asset_id']]
        require(all(saved.get(k) == v for k,v in component.items()), f'组件母版意外变化：{component["asset_id"]}')
        for label in ('component_blend','staging_glb'):
            part = saved[label]
            require(file_record(ROOT / part['path'])['sha256'] == part['sha256'], f'组件包意外变化：{part["path"]}')
    optimized = write_optimized(images)
    for item in (manifest,catalog,poses):
        item.update(source=source,source_sha256=source['sha256'])
    poses['assembly'] = manifest['assembly'] = report['assembly']
    write_json(catalog_path,catalog)
    write_json(pose_path,poses)
    manifest.update(plan=file_record(PLAN), catalog=file_record(catalog_path), component_instances=file_record(pose_path), optimized_blend=optimized, scenes=report['scenes'], motion_revision=plan['animation']['revision'])
    write_json(manifest_path,manifest)
    log(f'竖直组装修订已更新：{len(previous)} 个独立组件及静态 GLB 原哈希不变')


def contact_dimensions(plan):
    return {"status": "descriptive_only", "planned_dimensions": plan.get("dimensions", {}),
            "planned_thickness_m": plan.get("thickness_m", {}),
            "not_verified": ["承重与支撑接触", "角色净空", "碰撞及穿插", "Godot 接入"]}


def verify_deliverables(plan, source, report, required):
    errors = report["errors"]
    catalog = report["catalog"]
    manifest_path = FOLDER / "asset_manifest.json"
    paths = [FOLDER / "catalog.json", FOLDER / "component_instances.json", OPTIMIZED]
    paths.extend(path for entry in catalog for path in (
        FOLDER / "components" / f"{entry['asset_key']}.blend", EXPORT / f"{entry['asset_key']}.glb"))
    if not manifest_path.is_file() and not required and not any(path.exists() for path in paths):
        return {"status": "not_present", "inspected_packages": []}
    manifest = read_json(manifest_path) if manifest_path.is_file() else {}
    if not manifest:
        errors.append("缺少有效的 asset_manifest.json，无法核对交付哈希")
    elif manifest.get("source_sha256") != source["sha256"] or manifest.get("source") != source:
        errors.append("asset_manifest.json 的源文件 SHA-256 不匹配")
    manifest_entries = {entry["asset_key"]: entry for entry in manifest.get("components", [])}
    if set(manifest_entries) != {entry["asset_key"] for entry in catalog}:
        errors.append("组件源集合与 manifest 记录不一致")

    def check_file(path, record):
        if not path.is_file():
            errors.append(f"缺少交付文件：{path.relative_to(ROOT)}")
            return False
        actual = file_record(path)
        if any(record.get(key) != value for key, value in actual.items()):
            errors.append(f"路径、大小或 SHA-256 不匹配：{actual['path']}")
        return True

    check_file(PALETTE, manifest.get("palette", {}))
    check_file(PLAN, manifest.get("plan", {}))
    for filename, key in (("catalog.json", "catalog"), ("component_instances.json", "component_instances")):
        path = FOLDER / filename
        if check_file(path, manifest.get(key, {})):
            saved = read_json(path)
            if saved.get("source_sha256") != source["sha256"] or saved.get("source") != source:
                errors.append(f"{filename} 的源文件 SHA-256 不匹配")
            if key == "component_instances" and saved.get("instances") != report["instances"]:
                errors.append("component_instances.json 与源装配不一致")
            if key == "catalog" and saved.get("components") != manifest.get("components"):
                errors.append("catalog.json 与 manifest 的组件条目不一致")
    reopened = []
    optimized_reopened = False
    try:
        for number, entry in enumerate(catalog, 1):
            key = entry["asset_key"]
            blend, glb = FOLDER / "components" / f"{key}.blend", EXPORT / f"{key}.glb"
            recorded = manifest_entries.get(key, {})
            if check_file(glb, recorded.get("staging_glb", {})):
                try:
                    glb_stats = inspect_glb(glb)
                    if any(recorded.get("staging_glb", {}).get(k) != v for k, v in glb_stats.items()):
                        errors.append(f"{glb.name} 的 GLB 统计与 manifest 不符")
                except (RuntimeError, ValueError, TypeError) as exc:
                    errors.append(f"{glb.name}：{exc}")
            if not check_file(blend, recorded.get("component_blend", {})):
                continue
            log(f"重开独立包 {number}/{len(catalog)}：{key}")
            try:
                require(bpy.ops.wm.open_mainfile(filepath=str(blend), load_ui=False) == {"FINISHED"}, f"{blend.name} 无法打开")
                error_start = len(errors)
                require(len(bpy.data.scenes) == 1, f"{blend.name} 不包含唯一的独立场景")
                scene = bpy.data.scenes[0]
                collection = scene.collection.children.get(entry["asset_id"])
                require(collection is not None, f"{blend.name} 缺少预期组件集合")
                if len(scene.collection.children) != 1 or scene.collection.objects:
                    errors.append(f"{blend.name} 混入了非组件对象或集合")
                with active_scene(scene):
                    saved = inspect_component(collection, errors, with_topology=False)
                    palette_images((obj for obj in collection.objects if obj.type == "MESH"), blend, errors, relative_required=True)
                for attr in ("geometry_sha256", "bounds", "triangles", "materials", "custom_normal_meshes", "weighted_normal_modifier_meshes"):
                    if saved.get(attr) != entry.get(attr):
                        errors.append(f"{blend.name} 与源组件的 {attr} 不一致")
                reopened.append({"asset_key": key, "passed": error_start == len(errors)})
            except RuntimeError as exc:
                errors.append(f"{blend.name}：{exc}")
                reopened.append({"asset_key": key, "passed": False})
        if check_file(OPTIMIZED, manifest.get("optimized_blend", {})):
            log("重开优化副本")
            require(bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED), load_ui=False) == {"FINISHED"}, "优化副本无法打开")
            optimized_reopened = True
            optimized, _, _ = inspect_source(plan, OPTIMIZED, with_topology=False, relative_required=True)
            errors.extend(f"优化副本：{message}" for message in optimized["errors"])
            for field in ("instances", "assembly"):
                if optimized[field] != report[field]:
                    errors.append(f"优化副本的 {field} 与源文件不一致")
            fields = ("asset_key", "geometry_sha256", "bounds", "materials", "triangles", "custom_normal_meshes", "weighted_normal_modifier_meshes")
            if [[row.get(field) for field in fields] for row in optimized["catalog"]] != [[row.get(field) for field in fields] for row in catalog]:
                errors.append("优化副本的组件网格、UV 或统计与源文件不一致")
    finally:
        if Path(bpy.data.filepath).resolve() != SOURCE:
            require(bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False) == {"FINISHED"}, "无法恢复打开母版")
    return {"status": "inspected", "inspected_packages": reopened, "optimized_reopened": optimized_reopened}


def verify(plan, required):
    out = work_dir() / "verification.json"
    source = file_record(SOURCE)
    report, _, _ = inspect_source(plan, SOURCE)
    report.update(source=source, palette=file_record(PALETTE), contact_dimensions=contact_dimensions(plan),
                  visual_acceptance="pending", passed=False)
    try:
        report["deliverables"] = verify_deliverables(plan, source, report, required)
        if sha256(SOURCE) != source["sha256"]:
            report["errors"].append("验证期间源文件 SHA-256 发生变化")
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as exc:
        report["errors"].append(str(exc))
    report["passed"] = not report["errors"]
    write_json(out, report)
    checks_pass(report["errors"])
    log(f"验证通过：{out}")


def prepare_render_palette():
    for image in bpy.data.images:
        if image.source == "FILE" and image_path(image, SOURCE) == PALETTE.resolve():
            require(not image.packed_file and not len(image.packed_files), f"{image.name} 不应打包共享色板")
            image.filepath = str(PALETTE)


def set_render_samples(scene, samples):
    if scene.render.engine == "CYCLES":
        scene.cycles.device = "CPU"
        scene.cycles.samples = samples
        scene.cycles.use_denoising = True
    elif scene.render.engine == "BLENDER_EEVEE":
        scene.eevee.taa_render_samples = samples
    else:
        raise RuntimeError(f"{scene.name} 的渲染引擎不受支持：{scene.render.engine}")
    scene.render.image_settings.file_format = "PNG"
    scene.render.use_file_extension = True


def render_views():
    prepare_render_palette()
    out = work_dir()
    for scene_name, views in VIEWS.items():
        scene = bpy.data.scenes[scene_name]
        set_render_samples(scene, 32 if scene.render.engine == "CYCLES" else 40)
        scene.render.resolution_percentage = 100
        with active_scene(scene):
            for name in views:
                camera = scene.objects.get(name)
                require(camera is not None and camera.type == "CAMERA", f"{scene.name} 缺少相机 {name}")
                scene.camera = camera
                scene.render.filepath = str(out / f"{name.lower()}.png")
                log(f"渲染 {scene.name} / {name} → {scene.render.filepath}")
                require(bpy.ops.render.render(write_still=True) == {"FINISHED"}, f"{name} 渲染失败")


def render_animation():
    prepare_render_palette()
    scene = bpy.data.scenes[ANIMATION]
    require(scene.camera is not None and scene.camera.type == "CAMERA", f"{ANIMATION} 缺少活动相机")
    mode = scene.get('assembly_motion')
    variants = {'vertical_setdown_v2':'frames_ordered', 'offscreen_airdrop_v3':'frames_airdrop', 'spring_drop_v4':'frames_spring'}
    ordered = mode in variants
    frames = work_dir() / variants.get(mode, 'frames')
    frames.mkdir(exist_ok=True)
    scene.render.engine = "BLENDER_EEVEE"
    set_render_samples(scene, 16 if ordered else 12)
    scene.render.resolution_x = scene.render.resolution_y = 800 if ordered else 640
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = scene.render.pixel_aspect_y = 1
    scene.frame_step = 1 if ordered else 2
    scene.render.use_overwrite = True
    scene.render.use_placeholder = False
    scene.render.filepath = str(frames / "frame_")
    fps = scene.render.fps / scene.render.fps_base / scene.frame_step
    numbers = range(scene.frame_start, scene.frame_end + 1, scene.frame_step)
    log(f"渲染动画帧 {scene.frame_start}–{scene.frame_end}，步长 {scene.frame_step}，编码帧率 {fps:g}，目录 {frames}")
    with active_scene(scene):
        require(bpy.ops.render.render(animation=True) == {"FINISHED"}, "动画渲染失败")
    missing = [frame for frame in numbers if not (frames / f"frame_{frame:04d}.png").is_file()]
    require(not missing, f"动画 PNG 缺失：{missing}")
    write_json(work_dir() / ("animation_ordered_frames.json" if ordered else "animation_frames.json"), {"glob": frames.name + "/frame_*.png", "source_frames": list(numbers), "encode_fps": fps})
    log(f"动画完成：{len(numbers)} 帧 PNG，供外部 FFmpeg 编码")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("package", "render", "animation", "verify", "refresh-motion"))
    parser.add_argument("--require-packages", action="store_true", help="verify 时要求打包产物已存在")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.command != "verify" and args.require_packages:
        parser.error("--require-packages 仅用于 verify")
    require(bpy.data.filepath and Path(bpy.data.filepath).resolve() == SOURCE, f"请先用 Blender 打开源文件：{SOURCE}")
    require(PALETTE.is_file(), f"共享色板不存在：{PALETTE}")
    work_dir().mkdir(parents=True, exist_ok=True)
    if args.command == "package":
        package(read_json(PLAN))
    elif args.command == "refresh-motion":
        refresh_motion(read_json(PLAN))
    elif args.command == "verify":
        verify(read_json(PLAN), args.require_packages)
    elif args.command == "render":
        render_views()
    else:
        render_animation()


if __name__ == "__main__":
    main()
