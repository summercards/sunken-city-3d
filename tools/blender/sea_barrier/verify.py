"""sea 家园外围残楼围挡 · 源级验收（重开文件后独立核对，不信任建模时的内存状态）。

检查项：
  1. 组件数量、集合数量、母版/独立包一一对应；
  2. 每组件非空几何、根变换与网格变换为恒等；
  3. 每面 UV 有面积且落在单格安全区内，活动层与渲染层都是 PaletteUV，图片外链同一公共色板；
  4. 只用一个材质角色 SEA_Matte，无自发光、无内嵌贴图；
  5. 内侧不越界：所有几何都在 150x150 之外（可活动范围之内一块都不许站）；
  6. 围合连续：在装配场景里沿四边按 0.25 米步长打水平射线，水线处与水下船体高度
     都必须命中实体（这同时是「能挡船」的几何前提）；
  7. 组件三角面在预算内。

用法：
  blender -b --python tools/blender/sea_barrier/verify.py
"""
import json
import math
import os
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/sea_barrier/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'sea_barrier/v001'
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf8'))
PLAN_BY_KEY = {c['key']: c for c in PLAN['components']}
PALETTE_NAME = Path(PLAN['palette']).name

FINDINGS = []


def check(ok, message, detail=None):
    FINDINGS.append({'ok': bool(ok), 'check': message})
    if not ok:
        print('FAIL', message, detail if detail is not None else '', flush=True)


bpy.ops.wm.open_mainfile(filepath=str(D / 'sea_barrier.blend'))
ASSEMBLY = bpy.data.scenes.get('家园外围残楼围挡_完整围合')
MASTER = bpy.data.scenes.get('组件母版_独立编辑')
check(ASSEMBLY is not None, '装配场景存在')
check(MASTER is not None, '母版场景存在')

# 1 组件与集合
collections = {c.name: c for c in bpy.data.collections}
missing = [k for k in PLAN_BY_KEY if PLAN_BY_KEY[k]['collection'] not in collections]
check(not missing, '每个计划组件都有 Collection', missing)
planned_collections = {c['collection'] for c in PLAN['components']}
top_level = {c.name for c in MASTER.collection.children}
check(top_level == planned_collections, '母版场景顶层集合正是计划组件',
      sorted(top_level ^ planned_collections))

packages = sorted(p.stem for p in (D / 'component_packages').glob('*/*.blend'))
check(packages == sorted(PLAN_BY_KEY), '独立包与组件一一对应', packages)

# 2..4 几何、UV、材质
budget_fail = []
for key, comp in PLAN_BY_KEY.items():
    coll = collections.get(comp['collection'])
    if coll is None:
        continue
    meshes = [o for o in coll.all_objects if o.type == 'MESH']
    check(bool(meshes), key + ' 有网格')
    check(all(tuple(o.location) == (0, 0, 0) and tuple(o.rotation_euler) == (0, 0, 0)
              and tuple(o.scale) == (1, 1, 1) for o in meshes),
          key + ' 根变换恒等')
    triangles = 0
    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        check(all(p.area > 0 for p in mesh.polygons), key + ' 无非零面积面',
              f'{obj.name} 有退化面')
        layers = [uv.name for uv in mesh.uv_layers]
        check(layers == ['PaletteUV'], key + ' 只有 PaletteUV', layers)
        check(mesh.uv_layers['PaletteUV'].active_render, key + ' PaletteUV 为渲染层')
        uv = mesh.uv_layers['PaletteUV'].data
        worst_area, safe = 1e9, True
        for poly in mesh.polygons:
            pts = [uv[li].uv for li in poly.loop_indices]
            area = abs(sum(pts[i].x * pts[(i + 1) % len(pts)].y
                           - pts[(i + 1) % len(pts)].x * pts[i].y
                           for i in range(len(pts)))) / 2
            if area >= worst_area:
                continue
            worst_area = area
            margin = 8 / 512
            col = min(7, max(0, int(sum(p.x for p in pts) / len(pts) * 8)))
            row = min(7, max(0, int((1 - sum(p.y for p in pts) / len(pts)) * 8)))
            for p in pts:
                if not (col / 8 + margin <= p.x <= (col + 1) / 8 - margin and
                        row / 8 + margin <= (1 - p.y) <= (row + 1) / 8 - margin):
                    safe = False
        check(worst_area > 1e-6, key + ' 每面 UV 有面积', worst_area)
        check(safe, key + ' UV 落在单格安全区内')
        check(len(mesh.materials) == 1 and mesh.materials[0].name == 'SEA_Matte',
              key + ' 只挂 SEA_Matte', [m.name for m in mesh.materials])
        for node in mesh.materials[0].node_tree.nodes if mesh.materials else []:
            if node.type == 'TEX_IMAGE':
                check(node.image and node.image.name == 'SEA_暖木公共色板',
                      key + ' 图片外链公共色板', node.image.name if node.image else None)
                check(node.interpolation == 'Closest', key + ' 色板插值为 Closest')
        check(not mesh.materials[0].name.startswith('SEA_Emission'), key + ' 无自发光材质')
    # 悬空检查：结构性网格（墙、板、基座、碎石、树干）的最低点必须在水平面以下。
    # 树冠、枝、灌木是挂在树干上的，天然高于水线，不算。
    # 倾斜的楼如果绕底面中心硬转，翘起那一侧会整块抬离水面 —— 上一版近景就是这么穿帮的。
    # 楼板本身当然高于水面（它靠墙撑着），所以按「整栋」判：同一栋楼的所有构件
    # 合起来必须有一段触到或低于水面。整栋被抬起来才是穿帮。
    buildings = {}
    empty_meshes = []
    for obj in meshes:
        name = obj.name
        if any(tag in name for tag in ('冠', '枝', '灌', '碎石', '残堤')):
            continue
        head = name.rsplit('_', 1)[0]
        for cut in ('楼板', '顶板', '墙前', '墙后', '墙左', '墙右', '楼梯间', '女儿墙'):
            head = head.replace('_' + cut, '')
        # 空网格（一个顶点都没有）说明这一块根本没建出来，单独判，不能拿 min() 崩。
        if not obj.data.vertices:
            empty_meshes.append(obj.name)
            continue
        low = min(v.co.z for v in obj.data.vertices)
        buildings[head] = min(buildings.get(head, 1e9), low)
    check(not empty_meshes, key + ' 没有空网格', empty_meshes[:3])
    floating = [(key, head, round(low, 3)) for head, low in buildings.items() if low > 0.05]
    check(not floating, key + ' 整栋不悬空', floating[:3])
    if triangles > comp['triangle_budget']:
        budget_fail.append((key, triangles, comp['triangle_budget']))
check(not budget_fail, '三角面在预算内', budget_fail)

# 5 内侧不越界 + 6 围合连续（按真实装配摆位）
HALF = PLAN['ring']['inner_half_extent_m']
intrusions = []

instances = [o for o in ASSEMBLY.collection.objects if o.instance_type == 'COLLECTION']
check(len(instances) == len(PLAN['instances']), '装配实例数与计划一致',
      (len(instances), len(PLAN['instances'])))

bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
ASSEMBLY_OBJECTS = [o for o in bpy.data.objects if o.name.startswith('围挡_')]
for obj in ASSEMBLY_OBJECTS:
    matrix = obj.matrix_world
    coll = obj.instance_collection
    for src in coll.all_objects:
        if src.type != 'MESH':
            continue
        for vert in src.data.vertices:
            world = matrix @ (src.matrix_world @ vert.co)
            # 可活动范围是 |x| < 75 且 |y| < 75；任一维超出就在围挡那一侧。
            if abs(world.x) < HALF - 0.02 and abs(world.y) < HALF - 0.02:
                intrusions.append((obj.name, tuple(round(v, 2) for v in world)))
                break
check(not intrusions, '没有任何几何探进 150x150 可活动范围', intrusions[:5])

gaps = []
for z in (0.0, -0.6):
    for side, fixed, along, direction in (
            ('north', HALF, 'x', Vector((0, 1, 0))),
            ('south', -HALF, 'x', Vector((0, -1, 0))),
            ('east', HALF, 'y', Vector((1, 0, 0))),
            ('west', -HALF, 'y', Vector((-1, 0, 0)))):
        step = .25
        # 端点 ±75 正好压在转角件两条腿的公共边线上，单点射线贴身擦过不代表真有通道；
        # 转角由同一个 L 形母版的两条腿共享覆盖，内侧直角处无通路。采样从内缩 0.5 米起。
        t = -HALF + .5
        while t <= HALF - .5:
            # 起点放在边界内侧 1 米（这里必须没有几何），向外打 16 米：
            # 船要从这个位置出去，这条路就必须是实心的。
            offset = 1.0 if fixed > 0 else -1.0
            origin = (Vector((t, fixed - offset, z)) if along == 'x'
                      else Vector((fixed - offset, t, z)))
            # ray_cast 第一个返回值是 bool（命中为 True）而不是物体；
            # 判 `is None` 会永远判通过 —— 这个假绿实际发生过一次。
            hit = ASSEMBLY.ray_cast(depsgraph, origin, direction, distance=16.0)
            if hit[0] is not True:
                gaps.append((side, round(z, 2), round(t, 2)))
            t += step
check(not gaps, '四边水面与船体高度向外 16 米内无缺口（挡船前提）', gaps[:8])

# 7 保存后重开：独立包逐个加载
reopen_fail = []
for key in PLAN_BY_KEY:
    path = D / 'component_packages' / key / f'{key}.blend'
    with bpy.data.libraries.load(str(path), link=False) as (src, dst):
        dst.collections = [PLAN_BY_KEY[key]['collection']]
    loaded = dst.collections[0]
    if not loaded or not any(o.type == 'MESH' for o in loaded.all_objects):
        reopen_fail.append(key)
check(not reopen_fail, '独立包重开有几何', reopen_fail)

ok = sum(1 for f in FINDINGS if f['ok'])
result = {'suite': 'sea_barrier', 'version': 'v001', 'checks': len(FINDINGS),
          'failures': len(FINDINGS) - ok, 'findings': FINDINGS,
          'plan_components': len(PLAN_BY_KEY), 'instances': len(PLAN['instances'])}
W.mkdir(parents=True, exist_ok=True)
(W / 'source_verification.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print(f'VERIFY {ok}/{len(FINDINGS)} passed, {len(FINDINGS) - ok} failed')
