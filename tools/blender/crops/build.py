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
TRI_BUDGET = 900

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


# ---- 三品种 × 四阶段 -------------------------------------------------------

def build_lettuce(stage, collection, mats, origin):
    """生菜：贴地放射结球。种子→子叶→外叶放射→包心莲座。

    造型要点（2026-10-29 真机渲染复盘）：
    - 叶片必须向上拱起（bend 足够大），否则俯视只剩几条细线，整棵读作三颗小球；
    - 收成形态分三层：外叶（深）→ 内叶（中）→ 菜心（浅黄绿），靠层次读体积，不靠一颗大球。
    """
    objs = []
    if stage == 0:
        for c in CLUSTERS:
            objs.append(mesh_object('土丘', soil_mound(0.10, 0.038), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(3):
                seed = ellipsoid(0.024, 0.015, 0.010, 6, 3)
                objs.append(mesh_object('种子', seed, collection, 'sand', 'Matte', mats,
                                        origin + c + Vector((0.036 * (i - 1), 0.020 * (i % 2), 0.050))))
        return objs
    if stage == 1:
        for c in CLUSTERS:
            objs.append(mesh_object('土丘', soil_mound(0.095, 0.032), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(2):
                ang = math.tau * i / 2.0 + 0.4
                bm = leaf_blade(0.15, 0.105, 0.014, bend=0.85, tip=0.7)
                objs.append(mesh_object('子叶', bm, collection, 'leaf_light', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.035, math.sin(ang) * 0.035, 0.042)),
                                        azimuth=ang))
        return objs
    if stage == 2:
        for c in CLUSTERS:
            # 外圈 6 片大叶向外拱起，内圈 3 片略小而直立，形成放射层次。
            for i in range(6):
                ang = math.tau * i / 6.0 + 0.25
                bm = leaf_blade(0.26, 0.175, 0.016, bend=0.72, tip=0.45)
                objs.append(mesh_object('外叶', bm, collection, 'leaf' if i % 2 else 'leaf_mid', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.055, math.sin(ang) * 0.055, 0.062)),
                                        azimuth=ang))
            for i in range(3):
                ang = math.tau * i / 3.0 + 0.9
                bm = leaf_blade(0.15, 0.115, 0.014, bend=0.95, tip=0.55)
                objs.append(mesh_object('内叶', bm, collection, 'leaf_yellow', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.030, math.sin(ang) * 0.030, 0.105)),
                                        azimuth=ang))
        return objs
    # harvest：外叶包成莲座 + 中层收紧 + 浅黄菜心
    # 5 外 + 3 内 + 菜心 = 900 面预算内最饱满的组合（6+4 会到 1104）。
    for c in CLUSTERS:
        for i in range(5):
            ang = math.tau * i / 5.0 + 0.15
            bm = leaf_blade(0.30, 0.205, 0.018, bend=1.05, tip=0.30)
            objs.append(mesh_object('外叶', bm, collection, 'leaf' if i % 2 else 'leaf_dark', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.060, math.sin(ang) * 0.060, 0.070)),
                                    azimuth=ang))
        for i in range(3):
            ang = math.tau * i / 3.0 + 0.6
            bm = leaf_blade(0.19, 0.145, 0.016, bend=1.35, tip=0.35)
            objs.append(mesh_object('内叶', bm, collection, 'leaf_mid' if i % 2 else 'leaf_yellow', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.040, math.sin(ang) * 0.040, 0.150)),
                                    azimuth=ang))
        heart = ellipsoid(0.080, 0.080, 0.075, 8, 3)
        objs.append(mesh_object('菜心', heart, collection, 'spring', 'Wax', mats,
                                origin + c + Vector((0.0, 0.0, 0.185))))
    return objs


def build_tomato(stage, collection, mats, origin):
    """番茄：直立主茎分层复叶，果挂枝。"""
    objs = []
    if stage == 0:
        for c in CLUSTERS:
            objs.append(mesh_object('土丘', soil_mound(0.10, 0.038), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(3):
                seed = ellipsoid(0.021, 0.013, 0.009, 6, 3)
                objs.append(mesh_object('种子', seed, collection, 'ochre', 'Matte', mats,
                                        origin + c + Vector((0.036 * (i - 1), 0.022 * (i % 2), 0.050))))
        return objs
    if stage == 1:
        for c in CLUSTERS:
            objs.append(mesh_object('土丘', soil_mound(0.09, 0.032), collection, 'darkwood', 'Matte', mats, origin + c))
            objs.append(mesh_object('幼茎', stem(0.14, 0.010, 0.007), collection, 'leaf_dark', 'Matte', mats,
                                    origin + c + Vector((0, 0, 0.028))))
            for i in range(2):
                ang = math.tau * i / 2.0 + 0.9
                bm = leaf_blade(0.13, 0.085, 0.012, bend=0.6, tip=0.75)
                objs.append(mesh_object('子叶', bm, collection, 'leaf_light', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.045, math.sin(ang) * 0.045, 0.165)),
                                        azimuth=ang))
        return objs
    if stage == 2:
        for c in CLUSTERS:
            objs.append(mesh_object('主茎', stem(0.46, 0.014, 0.008, 6), collection, 'moss', 'Matte', mats,
                                    origin + c + Vector((0, 0, 0.02))))
            for i in range(7):
                ang = math.tau * i / 7.0 + 0.35
                h = 0.13 + 0.048 * i
                bm = leaf_blade(0.20, 0.115, 0.014, bend=0.55, tip=0.5)
                objs.append(mesh_object('复叶', bm, collection, 'leaf' if i % 2 else 'forest', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.075, math.sin(ang) * 0.075, h)),
                                        azimuth=ang))
        return objs
    # harvest：茎 + 5 层叶 + 三颗红果（6 层叶加三果会到 924，超 900 预算）
    for c in CLUSTERS:
        objs.append(mesh_object('主茎', stem(0.52, 0.015, 0.008, 6), collection, 'moss', 'Matte', mats,
                                origin + c + Vector((0, 0, 0.02))))
        for i in range(5):
            ang = math.tau * i / 5.0 + 0.5
            h = 0.15 + 0.070 * i
            bm = leaf_blade(0.20, 0.115, 0.014, bend=0.60, tip=0.5)
            objs.append(mesh_object('复叶', bm, collection, 'leaf' if i % 2 else 'forest', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.080, math.sin(ang) * 0.080, h)),
                                    azimuth=ang))
        for i in range(3):
            ang = math.tau * i / 3.0 + 0.2
            fruit = ellipsoid(0.072, 0.072, 0.066, 8, 3)
            objs.append(mesh_object('果实', fruit, collection, 'red_dark' if i % 2 else 'red', 'Wax', mats,
                                    origin + c + Vector((math.cos(ang) * 0.090, math.sin(ang) * 0.090,
                                                         0.235 + 0.062 * i))))
    return objs


def build_pumpkin(stage, collection, mats, origin):
    """南瓜：沿土面匍匐藤蔓，果压在地面。"""
    objs = []
    if stage == 0:
        for c in CLUSTERS:
            objs.append(mesh_object('土丘', soil_mound(0.10, 0.038), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(3):
                seed = ellipsoid(0.026, 0.017, 0.010, 6, 3)
                objs.append(mesh_object('种子', seed, collection, 'cream', 'Matte', mats,
                                        origin + c + Vector((0.040 * (i - 1), 0.024 * (i % 2), 0.050))))
        return objs
    if stage == 1:
        for c in CLUSTERS:
            objs.append(mesh_object('土丘', soil_mound(0.095, 0.034), collection, 'darkwood', 'Matte', mats, origin + c))
            for i in range(2):
                ang = math.tau * i / 2.0 + 0.2
                bm = leaf_blade(0.14, 0.125, 0.012, bend=0.30, tip=0.15)
                objs.append(mesh_object('子叶', bm, collection, 'leaf_light', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.050, math.sin(ang) * 0.050, 0.040)),
                                        azimuth=ang))
        return objs
    if stage == 2:
        for c in CLUSTERS:
            for i in range(2):
                ang = 0.4 + i * 1.9
                bm = ellipsoid(0.16, 0.020, 0.014, 8, 3)
                objs.append(mesh_object('藤', bm, collection, 'moss', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.070, math.sin(ang) * 0.070, 0.036)),
                                        azimuth=ang))
            for i in range(5):
                ang = math.tau * i / 5.0 + 0.7
                bm = leaf_blade(0.20, 0.185, 0.015, bend=0.35, tip=0.18)
                objs.append(mesh_object('大叶', bm, collection, 'leaf' if i % 2 else 'leaf_mid', 'Matte', mats,
                                        origin + c + Vector((math.cos(ang) * 0.095, math.sin(ang) * 0.095, 0.046)),
                                        azimuth=ang))
        return objs
    # harvest：藤 + 大叶 + 一颗带沟槽的南瓜
    for c in CLUSTERS:
        for i in range(2):
            ang = 0.4 + i * 1.9
            bm = ellipsoid(0.17, 0.021, 0.014, 8, 3)
            objs.append(mesh_object('藤', bm, collection, 'moss', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.070, math.sin(ang) * 0.070, 0.036)),
                                    azimuth=ang))
        for i in range(4):
            ang = math.tau * i / 4.0 + 1.1
            bm = leaf_blade(0.19, 0.175, 0.015, bend=0.40, tip=0.18)
            objs.append(mesh_object('大叶', bm, collection, 'leaf' if i % 2 else 'forest', 'Matte', mats,
                                    origin + c + Vector((math.cos(ang) * 0.100, math.sin(ang) * 0.100, 0.048)),
                                    azimuth=ang))
        bm = ellipsoid(0.150, 0.150, 0.108, 10, 5)
        for v in bm.verts:
            ang = math.atan2(v.co.y, v.co.x)
            groove = 1.0 - 0.10 * (0.5 + 0.5 * math.cos(ang * 8.0))
            v.co.x *= groove
            v.co.y *= groove
        objs.append(mesh_object('南瓜', bm, collection, 'ochre', 'Wax', mats,
                                origin + c + Vector((0.145, 0.035, 0.104))))
        bm = stem(0.062, 0.013, 0.020, 6)
        objs.append(mesh_object('瓜蒂', bm, collection, 'forest', 'Matte', mats,
                                origin + c + Vector((0.145, 0.035, 0.205))))
    return objs


BUILDERS = {'lettuce': build_lettuce, 'tomato': build_tomato, 'pumpkin': build_pumpkin}


def tri_count(objs):
    total = 0
    for obj in objs:
        me = obj.data
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
    return total


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
            entry['stages'][STAGE_KEYS[stage]] = {'objects': len(objs), 'triangles': tris}
            if tris > TRI_BUDGET:
                failures.append('%s stage %d: %d triangles > %d' % (crop_id, stage, tris, TRI_BUDGET))
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
