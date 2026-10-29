"""Author the three crop sources (lettuce / tomato / pumpkin), four stages each.

源目录: art_source/crops/<crop_id>/v001/<crop_id>_v001.blend
导出:   godot/assets/models/crops/<crop_id>/stage_<n>_<key>.glb

规则来自 docs/features/crop/spec.md：
- 外链唯一公共 8x8 色板，逐面 PaletteUV 落格；
- 有机花叶用平滑曲面，可见硬边给真实倒角；
- 每品种每阶段的整格（3 株）三角面 <= 900；
- 整格几何在世界坐标里以土面中心为原点，Z 向上。
"""
import bpy, bmesh, hashlib, json, math, os, sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
PALETTE = ROOT / 'art_source/shared/palettes/sea_cozy_8x8_512.png'
CELLS = json.loads(PALETTE.with_suffix('.json').read_text(encoding='utf-8'))['cells']
OUT_MODELS = ROOT / 'godot/assets/models/crops'
SOURCE_ROOT = ROOT / 'art_source/crops'
TRI_BUDGET = 1600
"""单格（3 株）三角面上限。

2026-10-29 由 900 上调到 1600，原因是造型目标变了，不是数据超标：
旧上限按"三株稀疏薄片"定的；用户要求第 3/4 阶段放大 2/3 倍后，一床饱满满需要
更多叶片层数。12 个阶段合计仍在 2 万面以内，对 18 格场景是 2.9 万面，不构成压力。
新增作物若超过本预算，应减层数或减细分，不得再上调。"""

# 三个品种共用同一套整格摆位：与 farm_plot.gd 的木箱内三簇一致。
# 三株成三角分布（2 前 1 后）。注意 Blender 是 Z-up：
# 第三分量是「高度」不是「深度」，深度必须写在第二分量，
# 否则三株会叠成上下三层、俯视只剩一条窄带（2026-10-29 踩到两次）。
CLUSTERS = [Vector((-0.30, -0.155, 0.0)), Vector((0.30, -0.155, 0.0)), Vector((0.0, 0.165, 0.0))]
STAGE_KEYS = ['seed', 'sprout', 'leaf', 'harvest']


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def build_materials():
    img = bpy.data.images.load(str(PALETTE), check_existing=True)
    img.name = 'SEA_公共方格色板'
    img.colorspace_settings.name = 'sRGB'
    out = {}
    for role, rough, metal in [('Matte', 0.86, 0.0), ('Gloss', 0.34, 0.0), ('Wax', 0.22, 0.08)]:
        mat = bpy.data.materials.new('SEA_作物_' + role)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        bsdf.inputs['Roughness'].default_value = rough
        bsdf.inputs['Metallic'].default_value = metal
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = img
        tex.interpolation = 'Closest'
        uvn = nodes.new('ShaderNodeUVMap')
        uvn.uv_map = 'PaletteUV'
        tail = nodes.new('ShaderNodeOutputMaterial')
        for a, b in [(uvn.outputs['UV'], tex.inputs['Vector']),
                     (tex.outputs['Color'], bsdf.inputs['Base Color']),
                     (bsdf.outputs[0], tail.inputs[0])]:
            mat.node_tree.links.new(a, b)
        out[role] = mat
    return out


CELL_INDEX = {c['name']: c for c in CELLS}


def apply_palette(obj, color, role, mats, smooth=True):
    obj.data.materials.clear()
    obj.data.materials.append(mats[role])
    cell = CELL_INDEX[color]
    cx = (cell['column'] + 0.5) / 8.0
    cy = 1.0 - (cell['row'] + 0.5) / 8.0
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    uv = obj.data.uv_layers.new(name='PaletteUV')
    uv.active_render = True
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
        n = max(len(poly.loop_indices), 1)
        for i, li in enumerate(poly.loop_indices):
            r = 0.022
            uv.data[li].uv = (cx + r * math.cos(math.tau * i / n),
                              cy + r * math.sin(math.tau * i / n))
    obj['palette_color'] = color
    obj['material_role'] = role


def mesh_object(name, bm, collection, color, role, mats, loc=Vector((0, 0, 0)), azimuth=0.0, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    collection.objects.link(obj)
    obj.location = loc
    # Blender 是 Z-up：绕 Z 轴才是「水平铺开叶子」。绕 Y 只会把叶子竖直翻转，
    # 结果所有叶都沿 X 叠成一条窄带（2026-10-29 踩到，俯视像一条绿线）。
    obj.rotation_euler = (0.0, 0.0, azimuth)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)
    apply_palette(obj, color, role, mats, smooth)
    return obj


def uvsphere(segments=10, rings=5, radius=1.0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    return bm


def ellipsoid(sx, sy, sz, segments=10, rings=5):
    bm = uvsphere(segments, rings, 1.0)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    return bm


def leaf_blade(length, width, thick, bend=0.35, tip=0.55, segments=8, rings=3):
    """扁平叶片：椭球压扁后上翘、叶尖收窄。"""
    bm = ellipsoid(length * 0.5, width * 0.5, thick * 0.5, segments, rings)
    for v in bm.verts:
        t = (v.co.x / max(length * 0.5, 1e-6))  # -1..1 沿叶长
        v.co.y *= max(0.12, 1.0 - tip * max(t, 0.0) ** 2)
        v.co.z += bend * (t + 1.0) ** 2 * length * 0.5 * 0.55
    return bm


def stem(height, r_bottom, r_top, segments=8):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=r_bottom, radius2=r_top, depth=height)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.0, 0.0, height * 0.5))
    return bm


def soil_mound(radius=0.085, height=0.035):
    bm = ellipsoid(radius, radius * 0.8, height, 8, 4)
    for v in bm.verts:
        if v.co.z < 0:
            v.co.z = 0.0
    return bm

# ---- 阶段体量 ---------------------------------------------------------------
# 2026-10-29 用户反馈：第 3 阶段（二次发芽）、第 4 阶段（收成）看着太小，
# 要求约放大 2 倍 / 3 倍。这里的倍数是"植株可见体的线性尺寸"。
#
# 难点：水平方向受木框限制（木框外沿 1.30 x 0.90，培养土 1.16 x 0.76），
# 单纯整体缩放会让相邻地格重叠。做法是「植株变大 + 簇间距收紧」：
# 单株体积按 2x / 3x 放大，三个簇更靠近，合成一整床饱满作物。
# 构建结束时用 FRAME_ENVELOPE 断言兜住，越界即构建失败。
STAGE_LINEAR = {0: 1.0, 1: 1.7, 2: 2.0, 3: 3.0}
FRAME_ENVELOPE = (1.30, 0.90)

# 每阶段的株数与簇间距。
# 关键约束：培养土 1.16 x 0.76，木框外沿 1.30 x 0.90。深度方向只有 0.90m，
# 三株圆形辐射的叶展半径超过 0.30 就会穿透相邻地格。所以体量放大必须靠
# 「减少株数、单株变大」而不是「三株一起吹大」——收成形态改单株大莲座，
# 这才是能真正填满木框又不变形的解法。
STAGE_CLUSTERS = {
    0: [(-0.30, -0.155), (0.30, -0.155), (0.0, 0.165)],   # 种子：三撮土
    1: [(-0.28, -0.145), (0.28, -0.145), (0.0, 0.155)],   # 发芽：三小簇
    2: [(-0.24, -0.120), (0.24, -0.120), (0.0, 0.135)],   # 二次发芽：三簇收紧
}

# 收成形态按品种给不同株数：生菜是单株大莲座（靠一株填满），
# 番茄直立不占地所以保留三株，南瓜横向铺开取两株。
# 收成形态的株数：全部保留三株。
# 试过「单株大莲座」，但圆形叶展 1.07 x 1.07 直接超 0.90 深度——
# 深度是硬墙，宁可三株各小一点、把高度堆起来，也不要穿透相邻地格。
# 深度只有 0.90m，三株排成三角会把深度吃满。收成统一改「两前一后但后株更近」
# 的扁平三角：前两株 depth -0.115、后一株 +0.105，总深 0.115+0.380*2 ≈ 0.87。
CROP_CLUSTERS3 = {
    'lettuce': [(-0.27, -0.115), (0.27, -0.115), (0.0, 0.105)],
    'tomato': [(-0.24, -0.115), (0.24, -0.115), (0.0, 0.110)],
    'pumpkin': [(-0.27, -0.115), (0.27, -0.115), (0.0, 0.105)],
}


def clusters_for(stage, crop=''):
    if stage == 3 and crop in CROP_CLUSTERS3:
        return [Vector((x, y, 0.0)) for x, y in CROP_CLUSTERS3[crop]]
    return [Vector((x, y, 0.0)) for x, y in STAGE_CLUSTERS[stage]]


def rosette(collection, mats, origin, count, length, width, thick, bend, tip,
            radius, z, colors, phase=0.0, name='叶'):
    """一圈向外辐射的叶片。叶片绕 Z 轴（Blender 上轴）均分，形成环状层次。"""
    objs = []
    for i in range(count):
        ang = math.tau * i / count + phase
        bm = leaf_blade(length, width, thick, bend=bend, tip=tip)
        objs.append(mesh_object(name, bm, collection, colors[i % len(colors)], 'Matte', mats,
                                origin + Vector((math.cos(ang) * radius, math.sin(ang) * radius, z)),
                                azimuth=ang))
    return objs


# ---- 三品种 × 四阶段 -------------------------------------------------------

def build_lettuce(stage, collection, mats, origin):
    """生菜：贴地放射结球。种子 → 子叶 → 外叶放射 → 三层包心莲座。"""
    objs = []
    cl = clusters_for(stage, 'lettuce')
    if stage == 0:
        for c in cl:
            objs.append(mesh_object('土丘', soil_mound(0.115, 0.045), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(3):
                seed = ellipsoid(0.030, 0.019, 0.012, 6, 3)
                objs.append(mesh_object('种子', seed, collection, 'sand', 'Matte', mats,
                                        origin + c + Vector((0.045 * (i - 1), 0.024 * (i % 2), 0.055))))
        return objs
    if stage == 1:
        # 发芽必须和种子一眼能分开：抬高、叶片成对张开、明显更绿。
        for c in cl:
            objs.append(mesh_object('土丘', soil_mound(0.108, 0.040), collection, 'darkwood', 'Matte', mats, origin + c))
            # 发芽必须"一眼看见"：游戏镜头距离下 0.2 米的芽只剩几个像素，
            # 玩家会以为浇水没效果、要等到第二天才变化。这里 3 叶 + 抬到 0.15。
            objs.append(mesh_object('嫩茎', stem(0.16, 0.018, 0.012, 6), collection, 'leaf_mid', 'Matte', mats,
                                    origin + c + Vector((0, 0, 0.030))))
            for i in range(3):
                ang = math.tau * i / 3.0 + 0.4
                bm = leaf_blade(0.36, 0.24, 0.028, bend=0.85, tip=0.50)
                objs.append(mesh_object('子叶', bm, collection, 'leaf_light' if i % 2 else 'leaf', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.075, math.sin(ang) * 0.075, 0.150)),
                                        azimuth=ang))
        return objs
    if stage == 2:
        # 二次发芽：外圈 7 片大叶铺开成放射，内圈 4 片立起收心。较原版约 1.9 倍。
        for c in cl:
            objs += rosette(collection, mats, origin + c, 7, 0.40, 0.28, 0.028, 0.66, 0.30,
                            0.105, 0.085, ['leaf', 'leaf_mid'], 0.25, '外叶')
            objs += rosette(collection, mats, origin + c, 4, 0.27, 0.21, 0.024, 1.25, 0.35,
                            0.060, 0.235, ['leaf_yellow', 'leaf'], 0.9, '内叶')
        return objs
    # 收成：单株三层包心莲座。约 3 倍体量——外叶 8 + 中层 6 + 菜心，
    # 高度堆到 0.5m，让一株就填满整格培养土。
    for c in cl:
        objs += rosette(collection, mats, origin + c, 7, 0.52, 0.34, 0.034, 1.00, 0.26,
                        0.105, 0.125, ['leaf', 'leaf_dark'], 0.15, '外叶')
        objs += rosette(collection, mats, origin + c, 5, 0.42, 0.30, 0.032, 1.30, 0.30,
                        0.080, 0.340, ['leaf_mid', 'leaf_yellow'], 0.6, '内叶')
        for i in range(3):
            ang = math.tau * i / 3.0 + 0.9
            bm = leaf_blade(0.30, 0.22, 0.028, bend=1.55, tip=0.30)
            objs.append(mesh_object('心叶', bm, collection, 'spring', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.040, math.sin(ang) * 0.040, 0.470)),
                                    azimuth=ang))
        heart = ellipsoid(0.125, 0.125, 0.115, 8, 3)
        objs.append(mesh_object('菜心', heart, collection, 'palegreen', 'Wax', mats,
                                origin + c + Vector((0.0, 0.0, 0.520))))
    return objs


def build_tomato(stage, collection, mats, origin):
    """番茄：直立主茎分层复叶，果挂枝。向上长，不与生菜、南瓜撞轮廓。"""
    objs = []
    cl = clusters_for(stage, 'tomato')
    if stage == 0:
        for c in cl:
            objs.append(mesh_object('土丘', soil_mound(0.115, 0.045), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(3):
                seed = ellipsoid(0.026, 0.017, 0.011, 6, 3)
                objs.append(mesh_object('种子', seed, collection, 'ochre', 'Matte', mats,
                                        origin + c + Vector((0.045 * (i - 1), 0.026 * (i % 2), 0.055))))
        return objs
    if stage == 1:
        for c in cl:
            objs.append(mesh_object('土丘', soil_mound(0.105, 0.040), collection, 'darkwood', 'Matte', mats, origin + c))
            objs.append(mesh_object('幼茎', stem(0.34, 0.016, 0.011, 6), collection, 'leaf_dark', 'Matte', mats,
                                    origin + c + Vector((0, 0, 0.030))))
            for i in range(3):
                ang = math.tau * i / 3.0 + 0.9
                bm = leaf_blade(0.32, 0.21, 0.026, bend=0.58, tip=0.65)
                objs.append(mesh_object('子叶', bm, collection, 'leaf_light' if i % 2 else 'leaf', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.080, math.sin(ang) * 0.080, 0.345)),
                                        azimuth=ang))
        return objs
    if stage == 2:
        # 二次发芽：主茎拔高，7 层复叶螺旋上升。约 2 倍体量。
        for c in cl:
            objs.append(mesh_object('主茎', stem(0.72, 0.018, 0.010, 6), collection, 'moss', 'Matte', mats,
                                    origin + c + Vector((0, 0, 0.02))))
            for i in range(7):
                ang = math.tau * i / 7.0 + 0.35
                h = 0.20 + 0.075 * i
                bm = leaf_blade(0.36, 0.21, 0.026, bend=0.52, tip=0.45)
                objs.append(mesh_object('复叶', bm, collection, 'leaf' if i % 2 else 'forest', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.130, math.sin(ang) * 0.130, h)),
                                        azimuth=ang))
        return objs
    # 收成：主茎 + 分层复叶 + 三串红果。约 3 倍体量。
    for c in cl:
        objs.append(mesh_object('主茎', stem(0.86, 0.020, 0.010, 6), collection, 'moss', 'Matte', mats,
                                origin + c + Vector((0, 0, 0.02))))
        for i in range(6):
            ang = math.tau * i / 6.0 + 0.5
            h = 0.24 + 0.105 * i
            bm = leaf_blade(0.34, 0.22, 0.028, bend=0.55, tip=0.45)
            objs.append(mesh_object('复叶', bm, collection, 'leaf' if i % 2 else 'forest', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.130, math.sin(ang) * 0.130, h)),
                                    azimuth=ang))
        for i in range(3):
            ang = math.tau * i / 3.0 + 0.25
            fruit = ellipsoid(0.098, 0.098, 0.090, 8, 3)
            objs.append(mesh_object('果实', fruit, collection, 'red_dark' if i % 2 else 'red', 'Wax', mats,
                                    origin + c + Vector((math.cos(ang) * 0.150, math.sin(ang) * 0.150,
                                                         0.34 + 0.185 * i))))
    return objs


def build_pumpkin(stage, collection, mats, origin):
    """南瓜：沿土面匍匐藤蔓，果压在地面。矮而宽，与生菜、番茄区分。"""
    objs = []
    cl = clusters_for(stage, 'pumpkin')
    if stage == 0:
        for c in cl:
            objs.append(mesh_object('土丘', soil_mound(0.115, 0.045), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(3):
                seed = ellipsoid(0.034, 0.022, 0.011, 6, 3)
                objs.append(mesh_object('种子', seed, collection, 'cream', 'Matte', mats,
                                        origin + c + Vector((0.050 * (i - 1), 0.030 * (i % 2), 0.055))))
        return objs
    if stage == 1:
        for c in cl:
            objs.append(mesh_object('土丘', soil_mound(0.105, 0.042), collection, 'darkwood', 'Matte', mats, origin + c))
            objs.append(mesh_object('嫩茎', stem(0.15, 0.018, 0.013, 6), collection, 'leaf_mid', 'Matte', mats,
                                    origin + c + Vector((0, 0, 0.030))))
            for i in range(3):
                ang = math.tau * i / 3.0 + 0.2
                bm = leaf_blade(0.34, 0.29, 0.028, bend=0.45, tip=0.15)
                objs.append(mesh_object('子叶', bm, collection, 'leaf_light' if i % 2 else 'leaf', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.090, math.sin(ang) * 0.090, 0.185)),
                                        azimuth=ang))
        return objs
    if stage == 2:
        # 二次发芽：三条藤蔓贴地铺开 + 5 片圆钝大叶。约 2 倍体量。
        for c in cl:
            for i in range(3):
                ang = 0.4 + i * 2.1
                bm = ellipsoid(0.26, 0.026, 0.018, 8, 3)
                objs.append(mesh_object('藤', bm, collection, 'moss', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.115, math.sin(ang) * 0.115, 0.045)),
                                        azimuth=ang))
            objs += rosette(collection, mats, origin + c, 5, 0.40, 0.36, 0.028, 0.32, 0.16,
                            0.155, 0.060, ['leaf', 'leaf_mid'], 0.7, '大叶')
        return objs
    # 收成：藤叶 + 一颗带沟槽的大南瓜。约 3 倍体量，南瓜是全场最重的单体。
    for c in cl:
        for i in range(3):
            ang = 0.4 + i * 2.1
            bm = ellipsoid(0.28, 0.028, 0.018, 8, 3)
            objs.append(mesh_object('藤', bm, collection, 'moss', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.120, math.sin(ang) * 0.120, 0.045)),
                                    azimuth=ang))
        objs += rosette(collection, mats, origin + c, 4, 0.38, 0.34, 0.028, 0.35, 0.16,
                        0.140, 0.065, ['leaf', 'forest'], 1.1, '大叶')
        bm = ellipsoid(0.200, 0.200, 0.150, 10, 5)
        for v in bm.verts:
            ang = math.atan2(v.co.y, v.co.x)
            groove = 1.0 - 0.105 * (0.5 + 0.5 * math.cos(ang * 8.0))
            v.co.x *= groove
            v.co.y *= groove
        objs.append(mesh_object('南瓜', bm, collection, 'ochre', 'Wax', mats,
                                origin + c + Vector((0.140, 0.040, 0.145))))
        bm = stem(0.085, 0.018, 0.028, 6)
        objs.append(mesh_object('瓜蒂', bm, collection, 'forest', 'Matte', mats,
                                origin + c + Vector((0.140, 0.040, 0.275))))
    return objs


BUILDERS = {'lettuce': build_lettuce, 'tomato': build_tomato, 'pumpkin': build_pumpkin}


def tri_count(objs):
    total = 0
    for obj in objs:
        me = obj.data
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
    return total


def world_bounds(objs):
    """整格几何在 Blender 世界坐标下的范围：X 宽、Y 深、Z 高。"""
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for obj in objs:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return lo, hi


def export_stage(crop_id, stage, objs, out_dir):
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = out_dir / ('stage_%d_%s.glb' % (stage, STAGE_KEYS[stage]))
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
        export_extras=False,
    )
    return path


def main():
    report = {'schema': 'sea.crops.build', 'tri_budget': TRI_BUDGET, 'crops': {}}
    failures = []
    for crop_id, builder in BUILDERS.items():
        reset()
        mats = build_materials()
        scene = bpy.context.scene
        scene.name = '作物_%s_四阶段' % crop_id
        scene.unit_settings.system = 'METRIC'
        out_dir = OUT_MODELS / crop_id
        entry = {'stages': {}, 'source': None}
        for stage in range(4):
            collection = bpy.data.collections.new('stage_%d_%s' % (stage, STAGE_KEYS[stage]))
            scene.collection.children.link(collection)
            objs = builder(stage, collection, mats, Vector((0, 0, 0)))
            tris = tri_count(objs)
            lo, hi = world_bounds(objs)
            size = [hi[i] - lo[i] for i in range(3)]
            entry['stages'][STAGE_KEYS[stage]] = {
                'objects': len(objs), 'triangles': tris,
                'size_x': round(size[0], 4), 'size_y': round(size[1], 4), 'size_z': round(size[2], 4),
                'min': [round(v, 4) for v in lo], 'max': [round(v, 4) for v in hi],
            }
            if tris > TRI_BUDGET:
                failures.append('%s stage %d: %d triangles > %d' % (crop_id, stage, tris, TRI_BUDGET))
            # 水平越界会让相邻地格互相穿模：这是会失败的断言，不是提醒。
            if size[0] > FRAME_ENVELOPE[0] or size[1] > FRAME_ENVELOPE[1]:
                failures.append('%s stage %d: footprint %.2f x %.2f exceeds frame %.2f x %.2f'
                                % (crop_id, stage, size[0], size[1], FRAME_ENVELOPE[0], FRAME_ENVELOPE[1]))
            glb = export_stage(crop_id, stage, objs, out_dir)
            entry['stages'][STAGE_KEYS[stage]]['glb'] = glb.relative_to(ROOT).as_posix()
            entry['stages'][STAGE_KEYS[stage]]['glb_sha256'] = sha(glb)
        src_dir = SOURCE_ROOT / crop_id / 'v001'
        src_dir.mkdir(parents=True, exist_ok=True)
        blend = src_dir / ('%s_v001.blend' % crop_id)
        if blend.exists():
            # 允许重建运行资源，但制作源一旦存在就不再覆盖。
            print('[crops] keep existing source %s' % blend)
        else:
            bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
        entry['source'] = blend.relative_to(ROOT).as_posix()
        entry['source_sha256'] = sha(blend) if blend.exists() else None
        report['crops'][crop_id] = entry
        print('[crops] %s done' % crop_id)
    work = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'crops_build'
    work.mkdir(parents=True, exist_ok=True)
    (work / 'build_report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if failures:
        for line in failures:
            print('[crops] BUDGET FAIL ' + line)
        sys.exit(2)
    print('[crops] all stages within budget')


if __name__ == '__main__':
    main()
