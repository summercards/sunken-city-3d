"""把点状/塌陷的 PaletteUV 批量扩成每个色格内、有面积的 UV 小岛。

用法：
  blender --background "<套件>.blend" --python expand_palette_uv_islands.py -- \
      --output "<另存路径>.blend" [--grid 8] [--glb out.glb] [--palette <色板>.png]

sea 默认 8×8 格；换色板尺寸时改 --grid 与 --safe-margin。
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

MIN_AREA = 1.0e-7
DEFAULT_GRID = 8
TARGET_CELL_RATIO = 0.5     # 小岛跨度占格边长的一半
MIN_SPAN_CELL_RATIO = 0.115  # 小岛最短边下限，保证有面积且不贴边


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--grid", type=int, default=DEFAULT_GRID)
    parser.add_argument("--glb", type=Path)
    parser.add_argument("--palette", type=Path,
                        help="把唯一公共色板重新外链后再保存/导出；sea 不打包图片")
    parser.add_argument("--collection", action="append", default=[],
                        help="只导出这些集合（可重复）；缺省导出 SEA- 开头的组件集合")
    return parser.parse_args(values)


def projection_axes(normal: Vector) -> tuple[int, int]:
    dominant = max(range(3), key=lambda index: abs(normal[index]))
    return ((1, 2), (0, 2), (0, 1))[dominant]


def polygon_area(points: list[Vector]) -> float:
    return abs(sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    )) * 0.5


def expand_mesh(mesh: bpy.types.Mesh, grid: int) -> int:
    layer = mesh.uv_layers.get("PaletteUV")
    if layer is None:
        raise RuntimeError(f"{mesh.name} 缺少 PaletteUV")
    cell = 1.0 / grid
    target_span = cell * TARGET_CELL_RATIO
    min_span = cell * MIN_SPAN_CELL_RATIO
    changed = 0
    for polygon in mesh.polygons:
        loop_indices = list(polygon.loop_indices)
        if len(loop_indices) < 3:
            continue
        old_uvs = [layer.data[index].uv for index in loop_indices]
        average_u = sum(uv.x for uv in old_uvs) / len(old_uvs)
        average_v = sum(uv.y for uv in old_uvs) / len(old_uvs)
        column = min(grid - 1, max(0, math.floor(max(0.0, min(0.999999, average_u)) * grid)))
        row = min(grid - 1, max(0, math.floor(max(0.0, min(0.999999, average_v)) * grid)))
        cell_center = Vector(((column + 0.5) * cell, (row + 0.5) * cell))

        axis_u, axis_v = projection_axes(polygon.normal)
        projected = [
            Vector((mesh.vertices[mesh.loops[index].vertex_index].co[axis_u],
                    mesh.vertices[mesh.loops[index].vertex_index].co[axis_v]))
            for index in loop_indices
        ]
        minimum = Vector((min(point.x for point in projected), min(point.y for point in projected)))
        maximum = Vector((max(point.x for point in projected), max(point.y for point in projected)))
        source_center = (minimum + maximum) * 0.5
        source_span = maximum - minimum
        largest_span = max(source_span.x, source_span.y)

        if largest_span <= 1.0e-12:
            projected = [
                Vector((math.cos(2.0 * math.pi * index / len(loop_indices)),
                        math.sin(2.0 * math.pi * index / len(loop_indices))))
                for index in range(len(loop_indices))
            ]
            source_center = Vector((0.0, 0.0))
            largest_span = 2.0

        scale = target_span / largest_span
        island = [(point - source_center) * scale for point in projected]
        span_u = max(point.x for point in island) - min(point.x for point in island)
        span_v = max(point.y for point in island) - min(point.y for point in island)
        stretch_u = max(1.0, min_span / max(span_u, 1.0e-12))
        stretch_v = max(1.0, min_span / max(span_v, 1.0e-12))
        island = [Vector((point.x * stretch_u, point.y * stretch_v)) for point in island]
        if polygon_area(island) < MIN_AREA:
            radius = target_span * 0.5
            island = [
                Vector((math.cos(2.0 * math.pi * index / len(loop_indices)) * radius,
                        math.sin(2.0 * math.pi * index / len(loop_indices)) * radius))
                for index in range(len(loop_indices))
            ]

        for loop_index, point in zip(loop_indices, island):
            layer.data[loop_index].uv = cell_center + point
            changed += 1

    mesh.uv_layers.active = layer
    layer.active_render = True
    mesh.update()
    return changed


SHOWCASE_HINTS = ("展示支持", "不导出")


def is_showcase_collection(name: str) -> bool:
    s = name.strip()
    return any(hint in s for hint in SHOWCASE_HINTS) or (s.startswith("90") and not s[2:3].isdigit())


def export_targets(explicit):
    """sea 的组件集合以 AssetID（SEA- 前缀）命名；也可显式点名集合。"""
    collections = [c for name in explicit for c in [bpy.data.collections.get(name)] if c]
    if not collections:
        collections = [c for c in bpy.data.collections
                       if c.name.startswith("SEA-") and not is_showcase_collection(c.name)]
    objects = {o for c in collections for o in c.all_objects if o.type == "MESH"}
    if not objects:
        # 回落：母版场景内除展示支持外的全部网格
        scene = next((s for s in bpy.data.scenes if "组件母版" in s.name), bpy.context.scene)
        showcase = {o for c in bpy.data.collections if is_showcase_collection(c.name) for o in c.all_objects}
        objects = {o for o in scene.objects if o.type == "MESH" and o not in showcase}
    if not objects:
        raise RuntimeError("找不到可导出的 sea 组件网格；请用 --collection 指定集合")
    return objects


def activate_scene_for(objects):
    """组件集合常挂在组件母版场景下；导出前把活动场景切过去，否则 select_set 报不在视图层。"""
    first = next(iter(objects))
    for scene in bpy.data.scenes:
        if first.name in scene.objects:
            window = getattr(bpy.context, "window", None)
            if window is not None and window.scene != scene:
                window.scene = scene
            return scene
    return None


def export_glb(path: Path, explicit_collections=()) -> None:
    objects = export_targets(explicit_collections)
    activate_scene_for(objects)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objects))
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_image_format="NONE",  # sea 色板不外嵌
    )


def is_palette_image(image: bpy.types.Image) -> bool:
    if image.source != "FILE":
        return False
    name = image.name.lower()
    return "色盘" in image.name or name.startswith("sea_") or "palette" in name


def relink_palette(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(path)
    for image in bpy.data.images:
        if not is_palette_image(image):
            continue
        image.filepath = str(path)
        image.reload()
        if image.packed_file is not None:
            image.unpack(method="REMOVE")


def main() -> None:
    options = parse_args()
    if options.grid < 2:
        raise SystemExit("--grid 至少为 2")
    # Blender 保存后会以新 .blend 位置为基准解析相对路径，故输入输出先绝对化
    options.output = options.output.expanduser().resolve()
    if options.glb:
        options.glb = options.glb.expanduser().resolve()
    if options.palette:
        options.palette = options.palette.expanduser().resolve()
    # 批处理原位更新时不在正式验收目录旁生成 .blend1；历史版本由资产目录统一归档。
    bpy.context.preferences.filepaths.save_version = 0
    meshes = {obj.data for scene in bpy.data.scenes for obj in scene.objects if obj.type == "MESH"}
    changed = sum(expand_mesh(mesh, options.grid) for mesh in meshes)
    if options.palette:
        relink_palette(options.palette)
    for material in bpy.data.materials:
        tree = getattr(material, "node_tree", None)
        if tree is None:
            continue
        for node in tree.nodes:
            if node.type == "UVMAP":
                node.uv_map = "PaletteUV"
            elif node.type == "TEX_IMAGE":
                node.interpolation = "Closest"
    options.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    if options.glb:
        export_glb(options.glb, options.collection)
    print("EXPANDED_PALETTE_UV_LOOPS", changed, "GRID", options.grid)


if __name__ == "__main__":
    main()
