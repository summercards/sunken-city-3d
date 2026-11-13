"""修 sea 场景源的 UV 层、材质角色命名与输出集合，不改色格分配与几何。

用法：
  blender --background "<源>.blend" --python repair_palette_uv_source.py -- \
      --output "<另存>.blend" [--glb out.glb] [--asset-name <english_key>] \
      [--donor-blend <补UV的源>.blend --donor-object <对象名>]

只做四件事：补/清 PaletteUV 层、把材质归一为 SEA 四角色、重建 01/02/90 集合骨架、清废弃材质。
"""

import argparse
import sys
from pathlib import Path

import bpy

PALETTE_UV = "PaletteUV"
ROLE_MATTE = "SEA_Matte"
ROLE_METAL = "SEA_Metal"
ROLE_GLOSS = "SEA_Gloss"
ROLE_EMISSION = "SEA_Emission"

# 历史散料材质名 → SEA 角色。sea 不接受按颜色命名的材质球。
ROLE_ALIASES = {
    "mat_matte": ROLE_MATTE,
    "mat_matte_teal": ROLE_MATTE,
    "mat_plaster": ROLE_MATTE,
    "mat_timber": ROLE_MATTE,
    "mat_metal": ROLE_METAL,
    "mat_metal_brushed": ROLE_METAL,
    "mat_glass": ROLE_GLOSS,
    "mat_gloss": ROLE_GLOSS,
    "mat_emissive": ROLE_EMISSION,
    "mat_emissive_ui": ROLE_EMISSION,
}
ROLE_KEYWORDS = (
    ("自发光", ROLE_EMISSION), ("发光", ROLE_EMISSION), ("emissive", ROLE_EMISSION), ("led", ROLE_EMISSION),
    ("清漆", ROLE_GLOSS), ("玻璃", ROLE_GLOSS), ("glass", ROLE_GLOSS), ("gloss", ROLE_GLOSS),
    ("金属", ROLE_METAL), ("metal", ROLE_METAL),
    ("哑光", ROLE_MATTE), ("墙面", ROLE_MATTE), ("墙漆", ROLE_MATTE), ("木", ROLE_MATTE), ("matte", ROLE_MATTE),
)


def args():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--glb", type=Path)
    parser.add_argument("--asset-name", help="英文 asset_key，用于命名 主体/发光 对象")
    parser.add_argument("--asset-id", help="AssetID；给出时会创建/复用同名组件集合（sea 约定）")
    parser.add_argument("--collection", action="append", default=[],
                        help="导出这些集合（可重复）；缺省导出 SEA- 开头的组件集合")
    parser.add_argument("--donor-blend", type=Path)
    parser.add_argument("--donor-object")
    return parser.parse_args(values)


def restore_missing_palette_uv(donor_blend, donor_object_name):
    missing = [o for scene in bpy.data.scenes for o in scene.objects
               if o.type == "MESH" and PALETTE_UV not in o.data.uv_layers]
    if not missing:
        return
    if len(missing) != 1 or not donor_blend or not donor_object_name:
        raise RuntimeError("缺 PaletteUV 时要求只有一个目标对象，并显式给出 donor")
    with bpy.data.libraries.load(str(donor_blend), link=False) as (source, target):
        if donor_object_name not in source.objects:
            raise RuntimeError(f"donor 对象不存在: {donor_object_name}")
        target.objects = [donor_object_name]
    donor = target.objects[0]
    target_obj = missing[0]
    donor_layer = donor.data.uv_layers.get(PALETTE_UV)
    if donor_layer is None or len(donor.data.loops) != len(target_obj.data.loops):
        raise RuntimeError(f"donor loop 数不匹配: {len(donor.data.loops)} != {len(target_obj.data.loops)}")
    layer = target_obj.data.uv_layers.new(name=PALETTE_UV)
    for index in range(len(layer.data)):
        layer.data[index].uv = donor_layer.data[index].uv
    bpy.data.objects.remove(donor, do_unlink=True)


def standardize_uv_layers():
    # 网格数据块可能被多个对象共享：先逐数据块处理，再设活动层，
    # 因为删旧层会重置 Blender 的 active_render 标记。
    meshes = {obj.data for scene in bpy.data.scenes for obj in scene.objects if obj.type == "MESH"}
    for mesh in meshes:
        palette = mesh.uv_layers.get(PALETTE_UV)
        if palette is None:
            raise RuntimeError(f"{mesh.name} 没有 PaletteUV")
        for layer in list(mesh.uv_layers):
            if layer != palette:
                mesh.uv_layers.remove(layer)
    for mesh in meshes:
        palette = mesh.uv_layers[PALETTE_UV]
        mesh.uv_layers.active = palette
        palette.active_render = True
        mesh.update()
    for material in bpy.data.materials:
        tree = getattr(material, "node_tree", None)
        if tree is None:
            continue
        for node in tree.nodes:
            if node.type == "UVMAP":
                node.uv_map = PALETTE_UV
            elif node.type == "TEX_IMAGE":
                node.interpolation = "Closest"


def normalize_material_roles():
    for material in bpy.data.materials:
        current = material.name
        if current in {ROLE_MATTE, ROLE_METAL, ROLE_GLOSS, ROLE_EMISSION}:
            continue
        target = ROLE_ALIASES.get(current.lower())
        if target is None:
            lowered = current.lower()
            for keyword, role in ROLE_KEYWORDS:
                if keyword in lowered:
                    target = role
                    break
        if target is None:
            continue
        # 目标名已被别的材质占用时保留原名，交给人工判断，不静默改名覆盖
        if bpy.data.materials.get(target) is not None:
            raise RuntimeError(f"材质 {current} 想归一为 {target}，但该名字已被占用")
        material.name = target


SHOWCASE_HINTS = ("展示支持", "不导出")


def is_showcase_collection(name):
    s = name.strip()
    return any(hint in s for hint in SHOWCASE_HINTS) or (s.startswith("90") and not s[2:3].isdigit())


def master_scene():
    return next((s for s in bpy.data.scenes if "组件母版" in s.name),
                bpy.context.scene)


def ensure_asset_collection(asset_name, asset_id):
    """sea 骨架：未归类的网格收进 `<AssetID>` 集合，并保证展示支持集合存在。

    已归属某个 `SEA-` 组件集合的网格不动；全部已归好类时只补展示集合，不做搬迁。
    """
    scene = master_scene()
    target_name = asset_id or f"SEA-SCENE-{asset_name.upper()}"
    ordered = [o for obj in scene.objects if obj.type == "MESH" for o in [obj]]

    def already_classified(obj):
        return any(c.name.startswith("SEA-") for c in obj.users_collection)

    movable = [o for o in ordered if not already_classified(o)
               and not any(is_showcase_collection(c.name) for c in o.users_collection)]

    if movable:
        collection = bpy.data.collections.get(target_name)
        if collection is None:
            collection = bpy.data.collections.new(target_name)
            scene.collection.children.link(collection)
        for index, obj in enumerate(movable):
            for owner in list(obj.users_collection):
                if owner is not collection and not is_showcase_collection(owner.name):
                    owner.objects.unlink(obj)
            if collection not in obj.users_collection:
                collection.objects.link(obj)
            if obj.name.startswith(("Cube", "Object", "Plane", "Mesh", "Circle")):
                suffix = "主体" if index == 0 else f"部件{index:02d}"
                obj.name = f"{asset_name}_{suffix}"
        print(f"MOVED_MESHES {len(movable)} -> {target_name}")
    else:
        print("NO_UNCLASSIFIED_MESH 跳过搬迁（源已按 AssetID 归类）")

    if not any(is_showcase_collection(c.name) for c in bpy.data.collections):
        showcase = bpy.data.collections.new("90 展示支持_不导出")
        scene.collection.children.link(showcase)
        print("CREATED_SHOWCASE_COLLECTION")
    return bpy.data.collections.get(target_name)


def purge_unused_materials():
    used = {m for scene in bpy.data.scenes for o in scene.objects if o.type == "MESH"
            for m in o.data.materials if m}
    for material in list(bpy.data.materials):
        if material not in used:
            bpy.data.materials.remove(material)


def export_targets(explicit):
    collections = [c for name in explicit for c in [bpy.data.collections.get(name)] if c]
    if not collections:
        collections = [c for c in bpy.data.collections
                       if c.name.startswith("SEA-") and not is_showcase_collection(c.name)]
    objects = {o for c in collections for o in c.all_objects if o.type == "MESH"}
    if not objects:
        scene = next((s for s in bpy.data.scenes if "组件母版" in s.name), bpy.context.scene)
        showcase = {o for c in bpy.data.collections if is_showcase_collection(c.name) for o in c.all_objects}
        objects = {o for o in scene.objects if o.type == "MESH" and o not in showcase}
    if not objects:
        raise RuntimeError("找不到可导出的 sea 组件网格；请用 --collection 指定集合")
    return objects


def export_glb(path, explicit_collections=()):
    objects = export_targets(explicit_collections)
    activate_scene_for(objects)

def activate_scene_for(objects):
    """组件集合常挂在组件母版场景下；导出前要把活动场景切过去，否则 select_set 报不在视图层。"""
    first = next(iter(objects))
    for scene in bpy.data.scenes:
        if first.name in scene.objects:
            window = getattr(bpy.context, "window", None)
            if window is not None and window.scene != scene:
                window.scene = scene
            return scene
    return None
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
        export_image_format="NONE",
    )


def main():
    options = args()
    # 保存后相对路径基准会变，输入输出先绝对化
    options.output = options.output.expanduser().resolve()
    if options.glb:
        options.glb = options.glb.expanduser().resolve()
    if options.donor_blend:
        options.donor_blend = options.donor_blend.expanduser().resolve()
    restore_missing_palette_uv(options.donor_blend, options.donor_object)
    standardize_uv_layers()
    normalize_material_roles()
    if options.asset_name or options.asset_id:
        ensure_asset_collection(options.asset_name or "component", options.asset_id)
    purge_unused_materials()
    options.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    if options.glb:
        export_glb(options.glb, options.collection)


main()
