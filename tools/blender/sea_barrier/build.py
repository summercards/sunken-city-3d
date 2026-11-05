"""sea 家园外围残楼围挡 · 白盒建模（Blender 4.5 后台）。

只写新套件源，不动任何正式 Godot 场景。每个 20 米组件单独成 Collection、
单独存独立包；围合摆位全部来自 component_plan.json，脚本不自己算坐标。

运行：
  blender -b --python tools/blender/sea_barrier/build.py
"""
import hashlib
import json
import math
import os
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/sea_barrier/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'sea_barrier/v001'
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf8'))
assert PLAN['status'] == 'frozen_before_geometry', '组件计划未冻结'
PALETTE = ROOT / PLAN['palette']
CELLS = json.loads(PALETTE.with_suffix('.json').read_text(encoding='utf8'))['cells']
CELL = {c['name']: ((c['column'] + .5) / 8, 1 - (c['row'] + .5) / 8) for c in CELLS}

WALL_COLORS = ['plaster', 'stone', 'gray', 'lightgray', 'cloud', 'snow', 'white', 'sage_gray']
RUBBLE_COLORS = ['stone', 'gray', 'slate', 'lightgray']
TRUNK_COLORS = ['bark', 'wood_dark', 'darkwood']
LEAF_COLORS = ['forest', 'deepgreen', 'moss', 'fern', 'jade', 'sage']

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
ASSEMBLY = bpy.context.scene
ASSEMBLY.name = '家园外围残楼围挡_完整围合'
ASSEMBLY.unit_settings.system = 'METRIC'
MASTER = bpy.data.scenes.new('组件母版_独立编辑')
MASTER.unit_settings.system = 'METRIC'

PAL = bpy.data.images.load(str(PALETTE))
PAL.name = 'SEA_暖木公共色板'
MAT = bpy.data.materials.new('SEA_Matte')
MAT.use_nodes = True
_nodes = MAT.node_tree.nodes
_links = MAT.node_tree.links
_nodes.clear()
_out = _nodes.new('ShaderNodeOutputMaterial')
_bsdf = _nodes.new('ShaderNodeBsdfPrincipled')
_bsdf.inputs['Roughness'].default_value = .86
_bsdf.inputs['Metallic'].default_value = 0.0
_uv = _nodes.new('ShaderNodeUVMap')
_uv.uv_map = 'PaletteUV'
_tex = _nodes.new('ShaderNodeTexImage')
_tex.image = PAL
_tex.interpolation = 'Closest'
_links.new(_uv.outputs['UV'], _tex.inputs['Vector'])
_links.new(_tex.outputs['Color'], _bsdf.inputs['Base Color'])
_links.new(_bsdf.outputs[0], _out.inputs[0])
W.mkdir(parents=True, exist_ok=True)


def palette_uv(mesh, color):
    uv = mesh.uv_layers.new(name='PaletteUV')
    uv.active_render = True
    cx, cy = CELL[color]
    for poly in mesh.polygons:
        count = len(poly.loop_indices)
        for k, li in enumerate(poly.loop_indices):
            angle = math.tau * k / count
            uv.data[li].uv = (cx + .02 * math.cos(angle), cy + .02 * math.sin(angle))


def emit(name, verts, faces, color, coll, smooth=False, bevel=0.0, transform=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel:
        edges = [e for e in bm.edges if e.is_manifold]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2,
                            affect='EDGES', profile=.5, clamp_overlap=True)
    if smooth:
        for f in bm.faces:
            f.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    if transform is not None:
        mesh.transform(transform)
    palette_uv(mesh, color)
    mesh.materials.append(MAT)
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    return obj


BOX_FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]


def box(name, x0, x1, y0, y1, z0, z1, color, coll, bevel=0.0, yaw=0.0, pivot=(0, 0)):
    if x1 < x0:
        x0, x1 = x1, x0
    if z1 < z0:
        z0, z1 = z1, z0
    verts = [(x0, y0, z0), (x1, y0, z0), (x0, y1, z0), (x1, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x0, y1, z1), (x1, y1, z1)]
    xf = None
    if yaw:
        xf = (Matrix.Translation((pivot[0], pivot[1], 0))
              @ Matrix.Rotation(yaw, 4, 'Z')
              @ Matrix.Translation((-pivot[0], -pivot[1], 0)))
    return emit(name, verts, BOX_FACES, color, coll, bevel=bevel, transform=xf)


def panel(name, width, height, thickness, holes, color, coll, steps=None,
          x=0.0, y=0.0, z=0.0, yaw=0.0):
    """带矩形开孔的墙板：网格切分后只保留实心格，四周自动生成洞口侧壁。

    steps: [(x0, x1, top)] —— 用分段高度表达破口/残缺的顶边；不给就是齐平顶。
    """
    steps = steps or [(-width / 2, width / 2, height)]
    xs = sorted({p[0] for p in steps} | {p[1] for p in steps}
                | {h[0] for h in holes} | {h[1] for h in holes})
    zs = sorted({0.0, height} | {p[2] for p in steps}
                | {h[2] for h in holes} | {h[3] for h in holes})
    solid = set()
    for i in range(len(xs) - 1):
        for j in range(len(zs) - 1):
            x0, x1, z0, z1 = xs[i], xs[i + 1], zs[j], zs[j + 1]
            if z0 < -1e-6:
                continue
            if not any(s[0] - 1e-6 <= x0 and x1 <= s[1] + 1e-6 and s[2] >= z1 - 1e-6
                       for s in steps):
                continue
            xm, zm = (x0 + x1) / 2, (z0 + z1) / 2
            if any(h[0] < xm < h[1] and h[2] < zm < h[3] for h in holes):
                continue
            solid.add((i, j))
    half = thickness / 2
    index, verts, faces = {}, [], []

    def vid(px, py, pz):
        key = (round(px, 5), round(py, 5), round(pz, 5))
        if key not in index:
            index[key] = len(verts)
            verts.append((px, py, pz))
        return index[key]

    for (i, j) in solid:
        x0, x1, z0, z1 = xs[i], xs[i + 1], zs[j], zs[j + 1]
        faces.append((vid(x0, -half, z0), vid(x1, -half, z0),
                      vid(x1, -half, z1), vid(x0, -half, z1)))
        faces.append((vid(x0, half, z1), vid(x1, half, z1),
                      vid(x1, half, z0), vid(x0, half, z0)))
        if (i - 1, j) not in solid:
            faces.append((vid(x0, -half, z1), vid(x0, half, z1),
                          vid(x0, half, z0), vid(x0, -half, z0)))
        if (i + 1, j) not in solid:
            faces.append((vid(x1, -half, z0), vid(x1, half, z0),
                          vid(x1, half, z1), vid(x1, -half, z1)))
        if (i, j - 1) not in solid:
            faces.append((vid(x0, -half, z0), vid(x0, half, z0),
                          vid(x1, half, z0), vid(x1, -half, z0)))
        if (i, j + 1) not in solid:
            faces.append((vid(x1, -half, z1), vid(x1, half, z1),
                          vid(x0, half, z1), vid(x0, -half, z1)))
    xf = Matrix.Translation((x, y, z)) @ Matrix.Rotation(yaw, 4, 'Z')
    return emit(name, verts, faces, color, coll, transform=xf)


def tube(name, p0, p1, r0, r1, color, coll, sides=6, smooth=True):
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    length = axis.length
    if length < 1e-4:
        return None
    axis = axis / length
    helper = Vector((0, 0, 1)) if abs(axis.z) < .9 else Vector((1, 0, 0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    verts, faces = [], []
    for k in range(sides):
        a = math.tau * k / sides
        d = u * math.cos(a) + v * math.sin(a)
        verts.append(tuple(p0 + d * r0))
        verts.append(tuple(p1 + d * r1))
    for k in range(sides):
        a, b = 2 * k, 2 * ((k + 1) % sides)
        faces.append((a, b, b + 1, a + 1))
    return emit(name, verts, faces, color, coll, smooth=smooth)


def blob(name, center, radius, color, coll, squash=1.0, rnd=None):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for vert in mesh.vertices:
        vert.co.z *= squash
        if rnd:
            vert.co += Vector((rnd.uniform(-.08, .08), rnd.uniform(-.08, .08),
                               rnd.uniform(-.08, .08))) * radius
    mesh.transform(Matrix.Translation(center))
    mesh.update()
    palette_uv(mesh, color)
    mesh.materials.append(MAT)
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    return obj


# ---------------------------------------------------------------- 建筑与植物

def window_holes(span, floor_height, count, door=False):
    holes = []
    usable = max(1.2, span - 1.6)
    for k in range(count):
        cx = -usable / 2 + usable * (k + .5) / count
        holes.append((cx - .55, cx + .55, floor_height * 3.0 + .95,
                      floor_height * 3.0 + 2.15))
    if door:
        holes.append((-.95, .95, .08, 2.45))
    return holes


def house(coll, prefix, cx, cy, w, d, floors, base_z, rnd, lean=0.0, yaw=0.0,
          missing=None, heavy_damage=False):
    """白盒残楼：四面墙带窗洞，顶层可塌出缺口，整体可倾斜。"""
    t = .3
    h = floors * 3.0
    body = bpy.data.collections.new(prefix + '_体')
    coll.children.link(body)
    color = rnd.choice(WALL_COLORS)

    front = []
    back = []
    for f in range(floors):
        front += window_holes(w, f, max(2, int(w // 3.4)), door=(f == 0))
        back += window_holes(w, f, 1)
    sides = []
    for f in range(floors):
        sides += window_holes(d, f, max(1, int(d // 4.2)))

    # 顶层缺口深度：墙顶最多削掉 drop 米，顶板同步下沉这么多。
    # 之前墙按 h 的百分比削、板却留在 h，结果板悬空成一个大托盘。
    # 白盒阶段用户要的是「一眼看出被摧毁」，所以墙顶跌幅给足：0.8–2.8 米。
    drop = rnd.uniform(.8, 2.8)

    def broken(width, height, limit=None):
        limit = drop if limit is None else limit
        cuts = sorted(rnd.uniform(-width / 2 + 1.3, width / 2 - 1.3)
                      for _ in range(rnd.randint(1, 3)))
        edges = [-width / 2] + cuts + [width / 2]
        return [(edges[i], edges[i + 1], height - rnd.uniform(0, limit))
                for i in range(len(edges) - 1)]

    if missing != 'front':
        panel(f'{prefix}_墙前', w, h, t, front, color, body,
              steps=broken(w, h) if heavy_damage else None,
              x=cx, y=cy - d / 2 + t / 2, z=base_z)
    # 每面墙都留一处参差破口：只破前墙时，从斜后方看过去整栋楼是齐平的方块，
    # 一眼就看得出「没坏」，围挡就不成立了。破口高度受限，避免把窗洞吃掉。
    if missing != 'back':
        panel(f'{prefix}_墙后', w, h, t, back, color, body,
              steps=broken(w, h), x=cx, y=cy + d / 2 - t / 2, z=base_z)
    for sign, tag in ((-1, '左'), (1, '右')):
        if missing == tag:
            continue
        panel(f'{prefix}_墙{tag}', d, h, t, sides, color, body,
              steps=broken(d, h), x=cx + sign * (w / 2 - t / 2), y=cy,
              z=base_z, yaw=math.pi / 2)

    # 屋顶可用区：塌陷只挖掉一半时，楼梯间只能落在还留着的那半块板上。
    roof_span = (cx - w / 2 + .18, cx + w / 2 - .18)
    for f in range(1, floors + 1):
        # 顶层跟着墙顶一起下沉 drop，否则板会悬在矮墙上方
        top = base_z + f * 3.0 - (drop if f == floors else 0.0)
        inset = .18
        if f == floors and rnd.random() < .3 and floors >= 2:
            # 顶层整块塌落：一块板都不留，只剩矮墙
            roof_span = (cx - w / 2 + inset, cx - w / 2 + inset + .01)
            continue
        if f == floors and rnd.random() < .6:
            cut = cx - w / 2 + inset + (w - 2 * inset) * rnd.uniform(.35, .6)
            keep_left = rnd.random() < .5
            box(f'{prefix}_顶板a', cx - w / 2 + inset, cut, cy - d / 2 + inset,
                cy + d / 2 - inset, top - .24, top, rnd.choice(WALL_COLORS), body, bevel=.04)
            roof_span = (cx - w / 2 + inset, cut)
            if rnd.random() < .65:
                box(f'{prefix}_顶板b', cut + rnd.uniform(.5, 1.6), cx + w / 2 - inset,
                    cy - d / 2 + inset, cy + d / 2 - inset,
                    top - .24 - rnd.uniform(.2, .9), top - .24,
                    rnd.choice(WALL_COLORS), body, bevel=.04)
                if not keep_left:
                    roof_span = (cut + 1.6, cx + w / 2 - inset)
        else:
            box(f'{prefix}_楼板{f}', cx - w / 2 + inset, cx + w / 2 - inset,
                cy - d / 2 + inset, cy + d / 2 - inset, top - .24, top,
                rnd.choice(WALL_COLORS), body, bevel=.04)
            roof_span = (cx - w / 2 + inset, cx + w / 2 - inset)

    if rnd.random() < .45:
        top = base_z + h - drop
        for edge in range(4):
            if rnd.random() < .35:
                continue
            if edge == 0:
                arg = (cx - w / 2, cx + w / 2, cy - d / 2, cy - d / 2 + .24)
            elif edge == 1:
                arg = (cx - w / 2, cx + w / 2, cy + d / 2 - .24, cy + d / 2)
            elif edge == 2:
                arg = (cx - w / 2, cx - w / 2 + .24, cy - d / 2, cy + d / 2)
            else:
                arg = (cx + w / 2 - .24, cx + w / 2, cy - d / 2, cy + d / 2)
            box(f'{prefix}_女儿墙{edge}', *arg, top - .1, top + .45,
                rnd.choice(WALL_COLORS), body, bevel=.05)
    # 楼梯间：底面压进顶板 0.3 米（不许悬空），且横向必须整块落在 roof_span 内。
    lo_span, hi_span = roof_span
    if rnd.random() < .5 and hi_span - lo_span >= 3.0:
        sx = rnd.uniform(lo_span + 1.2, hi_span - 1.2)
        sy = cy + rnd.uniform(-d / 2 + 1.7, d / 2 - 1.7)
        box(f'{prefix}_楼梯间', sx - 1.1, sx + 1.1, sy - 1.1, sy + 1.1,
            base_z + h - drop - .3, base_z + h - drop + rnd.uniform(1.6, 2.4),
            rnd.choice(WALL_COLORS), body, bevel=.05)

    objs = list(body.all_objects)
    if lean:
        axis = Vector((rnd.uniform(-.35, .35), 1.0, 0)).normalized()
        pivot = Vector((cx, cy, base_z))
        mat = (Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(lean), 4, axis)
               @ Matrix.Translation(-pivot))
        for obj in objs:
            obj.data.transform(mat)
        # 倾斜是绕底面中心转的，翘起那一侧的下角会被抬离水面、悬在空中。
        # 按真实最低顶点把整栋再压回去，保证倾斜的楼仍然「坐」在基座上。
        lo, _ = coll_bounds(body)
        if lo.z > base_z - .32:
            for obj in objs:
                obj.data.transform(Matrix.Translation((0, 0, base_z - .32 - lo.z)))
    if yaw:
        mat = (Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(yaw, 4, 'Z')
               @ Matrix.Translation((-cx, -cy, 0)))
        for obj in objs:
            obj.data.transform(mat)
    return body


def tree(coll, prefix, x, y, rnd, kind='sunk', z0=-1.8):
    trunk_c = rnd.choice(TRUNK_COLORS)
    leaf_c = rnd.choice(LEAF_COLORS)
    height = {'sunk': rnd.uniform(3.0, 4.2), 'tall': rnd.uniform(6.0, 8.4),
              'dead': rnd.uniform(4.2, 6.4)}[kind]
    lean = Vector((rnd.uniform(-.5, .5), rnd.uniform(-.5, .5), 1)).normalized()
    top = Vector((x, y, z0)) + lean * height
    r = rnd.uniform(.22, .34)
    tube(f'{prefix}_干', (x, y, z0), top, r, r * .45, trunk_c, coll, sides=6)
    if kind != 'dead':
        for i in range(rnd.randint(2, 3)):
            offset = Vector((rnd.uniform(-1.1, 1.1), rnd.uniform(-1.1, 1.1),
                             rnd.uniform(-.4, .9)))
            radius = rnd.uniform(1.05, 1.7) * (1.0 if kind == 'tall' else .9)
            blob(f'{prefix}_冠{i}', top + offset, radius, leaf_c, coll,
                 squash=rnd.uniform(.7, .95), rnd=rnd)
    else:
        for i in range(3):
            angle = rnd.uniform(0, math.tau)
            tip = top + Vector((math.cos(angle) * rnd.uniform(1.0, 2.0),
                                math.sin(angle) * rnd.uniform(1.0, 2.0),
                                rnd.uniform(-.6, .9)))
            tube(f'{prefix}_枝{i}', Vector(top) - lean * rnd.uniform(.5, 1.2), tip,
                 r * .4, .03, trunk_c, coll, sides=5)


def bush(coll, prefix, x, y, rnd):
    color = rnd.choice(LEAF_COLORS)
    for i in range(rnd.randint(2, 3)):
        blob(f'{prefix}_灌{i}',
             (x + rnd.uniform(-.9, .9), y + rnd.uniform(-.9, .9),
              rnd.uniform(-.3, .35)), rnd.uniform(.7, 1.15), color, coll,
             squash=.62, rnd=rnd)


def rubble(coll, prefix, x0, x1, y0, y1, rnd, count=6):
    for i in range(count):
        cx = rnd.uniform(x0, x1)
        cy = rnd.uniform(y0, y1)
        s = rnd.uniform(.35, 1.0)
        box(f'{prefix}_碎石{i}', cx - s / 2, cx + s / 2, cy - s * .4, cy + s * .4,
            rnd.uniform(-1.6, -.2), s * rnd.uniform(.5, 1.0),
            rnd.choice(RUBBLE_COLORS), coll, bevel=.05,
            yaw=rnd.uniform(0, math.pi), pivot=(cx, cy))


## 水线以下的延续深度（2026-11-05 用户要求「往下延伸 20 米」）。
DEEP_M = 20.0
## 残堤底面标高：水线在 0，这一层是原来水下裙体的底。
BASE_Z = -2.8
FLOOR_H = 3.2
## 转角腿的进深与直线段一致，两腿各 10 米宽。
CORNER_DEPTH = 10.0


def embankment(coll, prefix, width, rnd):
    """水下裙体 + 连续残堤：水线处必须没有缺口，船才会真的被挡住。"""
    # 两端各多铺 1.4 米。转角件的对齐基准是「最内侧顶点」，而残楼/树冠会比残堤
    # 更往外探，于是整段被推开约 1.3 米 —— 残堤若只铺满标称宽度，角点处就漏出
    # 一条 1.3 米的窄缝，船能挤出去。多铺的部分与邻段重叠，视觉上就是连成一片废墟。
    span = width + 2.8
    count = max(2, int(math.ceil(span / 4.6)))
    piece = (span + 0.8) / count
    for i in range(count):
        x0 = -span / 2 - .4 + i * piece
        x1 = x0 + piece + .35
        box(f'{prefix}_残堤{i}', x0, x1, rnd.uniform(-3.4, -2.4),
            rnd.uniform(2.6, 3.6), BASE_Z, rnd.uniform(.55, 1.75),
            rnd.choice(RUBBLE_COLORS), coll, bevel=.06,
            yaw=rnd.uniform(-.05, .05), pivot=((x0 + x1) / 2, .5))


def underwater_structure(coll, prefix, width, depth, rnd):
    """水线以下的建筑延续：外壳 + 楼层残板 + 立柱 + 基脚，往下 20 米。

    为什么要做：残堤只到水下 2.8 米，再往下就是空的。船和相机压低一点、
    或者水面透过去看，整排围挡像浮在一块薄板上。用户要求「下方建筑结构补上」，
    所以这里按真实沉没建筑补：每 3.2 米一层板、板下立柱、底部放宽的基脚。

    轮廓比水上部分内收 0.5 米：视觉上像水下体积逐层收缩，也不会顶到
    水上残楼/树冠的包络之外（那会把整段的对齐基准挤走）。
    """
    top = BASE_Z
    bottom = top - DEEP_M
    legs = int(round(DEEP_M / FLOOR_H))
    half_w = width / 2 - .35
    # 进深必须严格收在残堤的包络里（残堤 y ∈ [-3.4, 3.6]）。多探出一点，整段的
    # 「内侧最凸点」就变成水下基脚，对齐基准被挤走 1 米多，水线处就露出缝。
    y0, y1 = -3.3, 3.5

    # 外壳：前后两道长墙，按层开窗带。墙是主要观感来源 —— 从低角度看，
    # 水下就是这一圈墙在往下延。
    #
    # panel() 的 steps 与 holes 都吃「局部高度」（0 = 墙底），不是世界坐标。
    # 把绝对标高 (-2.8) 当高度传进去，整面墙一格实心都没有、直接空掉。
    for tag, yface in (('前', y0 + .17), ('后', y1 - .17)):
        holes = []
        for level in range(legs):
            local_lo = DEEP_M - (level + 1) * FLOOR_H
            # 每层一条宽窗带：只开零星小洞时，从外面看整面就是一块水泥堤。
            if rnd.random() < .78:
                cx = rnd.uniform(-half_w + 2.0, half_w - 2.0)
                wid = rnd.uniform(1.8, 3.4)
                holes.append((max(-half_w + .3, cx - wid), min(half_w - .3, cx + wid),
                              local_lo + .75, local_lo + FLOOR_H - .75))
            # 再随机加一个通高破口（整层塌空）
            if rnd.random() < .4:
                cx = rnd.uniform(-half_w + 1.0, half_w - 1.0)
                wid = rnd.uniform(.6, 1.4)
                holes.append((max(-half_w, cx - wid), min(half_w, cx + wid),
                              local_lo + .2, local_lo + FLOOR_H - .2))
        steps = []
        seg = 3
        edges = [-half_w + i * (2 * half_w / seg) for i in range(seg + 1)]
        for i in range(seg):
            steps.append((edges[i], edges[i + 1],
                          DEEP_M + (rnd.uniform(-.5, .35) if i else rnd.uniform(-.4, .2))))
        panel(f'{prefix}_水下墙{tag}', 2 * half_w, DEEP_M, .34, holes,
              rnd.choice(RUBBLE_COLORS), coll, steps=steps,
              x=0.0, y=yface, z=bottom)

    # 两端封口墙
    for tag, x in (('左', -half_w + .17), ('右', half_w - .17)):
        box(f'{prefix}_水下端墙{tag}', x - .17, x + .17, y0 + .3, y1 - .3,
            bottom, top - rnd.uniform(0, 1.2), rnd.choice(RUBBLE_COLORS), coll,
            bevel=.04)

    # 楼层残板：每层一块，随机缺一段（塌落）
    for level in range(legs):
        z = top - level * FLOOR_H - .26
        if level == legs - 1:
            continue
        if rnd.random() < .22:
            continue
        cut = rnd.uniform(-half_w + 2.0, half_w - 2.0)
        box(f'{prefix}_水下板{level}a', -half_w + .2, cut, y0 + .2, y1 - .2,
            z - .26, z, rnd.choice(RUBBLE_COLORS), coll, bevel=.04)
        if rnd.random() < .6:
            gap = rnd.uniform(.8, 2.6)
            tail = cut + gap
            # 缺口不能吃掉整块板：留至少 0.6 米残边，且厚度不许退化成零厚面
            if tail < half_w - .8:
                drop = rnd.uniform(.1, .7)
                box(f'{prefix}_水下板{level}b', tail, half_w - .2, y0 + .2, y1 - .2,
                    z - .26 - drop, z - .26, rnd.choice(RUBBLE_COLORS), coll, bevel=.04)

    # 立柱：两排，按层断开（断柱留缺口，不一根通到底）
    for row, cy in (('前', y0 + 1.5), ('后', y1 - 1.5)):
        for i in range(2):
            cx = -half_w + 1.2 + i * (2 * half_w - 2.4)
            level = 0
            while level < legs:
                span = rnd.randint(1, 3)
                z_hi = top - level * FLOOR_H - .26
                z_lo = top - min(legs, level + span) * FLOOR_H
                if rnd.random() < .82:
                    box(f'{prefix}_水下柱{row}{i}_{level}', cx - .22, cx + .22,
                        cy - .22, cy + .22, z_lo, z_hi, rnd.choice(RUBBLE_COLORS),
                        coll, bevel=.03)
                level += span

    # 外侧檐口：每层在墙面外挑出一段残板，从侧下方看就是一层层塌掉的楼板边。
    # 这是「水下是建筑」最直接的读数来源，比窗洞更省面。
    for level in range(1, legs):
        z = top - level * FLOOR_H
        if rnd.random() < .25:
            continue
        for tag, yface, sign in (('前', y0, -1), ('后', y1, 1)):
            seg_lo = rnd.uniform(-half_w + .8, half_w - 3.2)
            seg_hi = seg_lo + rnd.uniform(1.4, 3.6)
            box(f'{prefix}_水下檐{tag}{level}', seg_lo, seg_hi,
                yface + sign * .18, yface - sign * .55, z - .34, z,
                rnd.choice(RUBBLE_COLORS), coll, bevel=.03)

    # 基脚：底部一圈厚承台。只往下加高、不向外扩 —— 一扩就越出残堤包络，
    # 整段的对齐基准会被挤走，水线处就会露出缝。
    box(f'{prefix}_水下基脚', -width / 2 + .1, width / 2 - .1,
        y0, y1, bottom, bottom + .9,
        rnd.choice(RUBBLE_COLORS), coll, bevel=.05)


def build_segment(prefix, coll, width, depth, kind, rnd):
    embankment(coll, prefix, width, rnd)
    underwater_structure(coll, prefix, width, depth, rnd)
    if kind == 'house_pair':
        for i, sign in enumerate((-1, 1)):
            house(coll, f'{prefix}_房{i}', sign * width / 4 + rnd.uniform(-1.1, 1.1),
                  rnd.uniform(.4, 2.2), rnd.uniform(6.2, 8.2), rnd.uniform(5.4, 6.8),
                  rnd.randint(2, 3), rnd.uniform(-2.4, -.4), rnd,
                  lean=rnd.uniform(4, 11) * rnd.choice((-1, 1)),
                  missing=rnd.choice([None, 'front', 'back']),
                  heavy_damage=rnd.random() < .5)
        for i in range(rnd.randint(3, 5)):
            tree(coll, f'{prefix}_树{i}', rnd.uniform(-width / 2 + .8, width / 2 - .8),
                 rnd.uniform(-4.2, 3.6), rnd, kind=rnd.choice(('sunk', 'sunk', 'tall')))
    elif kind == 'single_house':
        house(coll, f'{prefix}_房', rnd.uniform(-1.4, 1.4), rnd.uniform(1.0, 2.6),
              rnd.uniform(8.4, 10.4), rnd.uniform(6.2, 7.8), rnd.randint(2, 4),
              rnd.uniform(-2.6, -.6), rnd,
              lean=rnd.uniform(6, 15) * rnd.choice((-1, 1)),
              missing=rnd.choice([None, None, 'front']), heavy_damage=True)
        for i in range(rnd.randint(3, 6)):
            tree(coll, f'{prefix}_树{i}', rnd.uniform(-width / 2 + .8, width / 2 - .8),
                 rnd.uniform(-4.4, 4.2), rnd, kind=rnd.choice(('sunk', 'tall', 'dead')))
    elif kind == 'forest_band':
        top = rnd.uniform(2.2, 3.6)
        panel(f'{prefix}_残墙', width - .4, top, .32, [], rnd.choice(WALL_COLORS), coll,
              steps=[(-width / 2 + .2, -width / 6, top),
                     (-width / 6, width / 8, top - rnd.uniform(.8, 2.0)),
                     (width / 8, width / 2 - .2, top - rnd.uniform(0, .9))],
              y=rnd.uniform(1.6, 2.8))
        for i in range(rnd.randint(7, 10)):
            tree(coll, f'{prefix}_树{i}', rnd.uniform(-width / 2 + .6, width / 2 - .6),
                 rnd.uniform(-4.4, 3.4), rnd,
                 kind=rnd.choice(('sunk', 'sunk', 'sunk', 'tall', 'dead')))
        for i in range(rnd.randint(2, 4)):
            bush(coll, f'{prefix}_灌{i}', rnd.uniform(-width / 2 + .8, width / 2 - .8),
                 rnd.uniform(-4.2, 2.6), rnd)
    else:  # filler 收口残墙
        top = rnd.uniform(1.8, 3.2)
        panel(f'{prefix}_残墙', width - .2, top, .32, [], rnd.choice(WALL_COLORS), coll,
              steps=[(-width / 2 + .1, -width / 10, top),
                     (-width / 10, width / 6, top - rnd.uniform(.9, 2.2)),
                     (width / 6, width / 2 - .1, max(1.0, top - rnd.uniform(0, 1.6)))],
              y=rnd.uniform(1.5, 2.4))
        for i in range(rnd.randint(2, 3)):
            tree(coll, f'{prefix}_树{i}', rnd.uniform(-width / 2 + .7, width / 2 - .7),
                 rnd.uniform(-4.0, 2.4), rnd, kind=rnd.choice(('sunk', 'dead', 'sunk')))
    rubble(coll, prefix, -width / 2 + .4, width / 2 - .4, -3.4, 1.2, rnd,
           count=rnd.randint(4, 8))


def transform_coll(coll, matrix):
    for obj in coll.all_objects:
        if obj.type == 'MESH':
            obj.data.transform(matrix)


def coll_bounds(coll):
    """直接读网格顶点：bound_box 在 mesh.transform 之后是缓存值，会给出旧包络。"""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in coll.all_objects:
        if obj.type != 'MESH':
            continue
        for vert in obj.data.vertices:
            world = obj.matrix_world @ vert.co
            lo = Vector((min(lo[i], world[i]) for i in range(3)))
            hi = Vector((max(hi[i], world[i]) for i in range(3)))
    return lo, hi


def build_corner(coll, arm, prefix, length, rnd):
    """转角的一条腿：10 米残墙 + 一栋靠外的倾斜小楼 + 少量树。

    腿的包络必须严格落在 [0, length]（内侧压在 x=0 上），所以这里不用
    build_segment —— 那套布局按 20 米宽排房子，会溢出到相邻组件的位置。
    """
    coll.children.link(arm)
    embankment(arm, prefix, length - .6, rnd)
    underwater_structure(arm, prefix, length - .6, CORNER_DEPTH, rnd)
    # 残墙：贴内侧面立起来，破口朝上
    top = rnd.uniform(2.4, 3.8)
    panel(f'{prefix}_残墙', length - .3, top, .34, [], rnd.choice(WALL_COLORS), arm,
          steps=[(-length / 2 + .15, -length / 6, top),
                 (-length / 6, length / 8, top - rnd.uniform(.7, 1.9)),
                 (length / 8, length / 2 - .15, top - rnd.uniform(0, .8))],
          y=.5)
    # 倾斜小楼：摆在腿的外侧，不占内圈
    house(arm, f'{prefix}_楼', rnd.uniform(-length / 2 + 3.0, length / 2 - 3.0),
          rnd.uniform(4.0, 5.4), rnd.uniform(5.0, 6.2), rnd.uniform(4.6, 5.6),
          rnd.randint(2, 3), rnd.uniform(-2.2, -.8), rnd,
          lean=rnd.uniform(7, 17) * rnd.choice((-1, 1)),
          missing=rnd.choice([None, 'front', 'back']), heavy_damage=True)
    for i in range(2):
        tree(arm, f'{prefix}_树{i}', rnd.uniform(-length / 2 + .9, length / 2 - 3.4),
             rnd.uniform(1.4, 3.2), rnd, kind=rnd.choice(('sunk', 'tall', 'dead')))
    rubble(arm, prefix, -length / 2 + .5, length / 2 - .5, .6, 3.2, rnd, count=4)


def build_component(comp):
    coll = bpy.data.collections.new(comp['collection'])
    MASTER.collection.children.link(coll)
    rnd = random.Random(comp['seed'])
    width = comp['width_m']
    if comp['kind'] == 'corner_ruin':
        # L 形：原点取「围合内角」。北腿占 x∈[-W,0] / y∈[0,W]，东腿占 x∈[0,W] / y∈[-W,0]，
        # 两条内侧面正好压在 x=0 与 y=0 上，转角内侧的直角不留缝。
        #
        # 对角那块（x>0 且 y>0）也要有东西：两条腿只覆盖两个方向，斜着看过去圈内
        # 正对着一个通到圈外的水口，围挡就白做了。补的角块仍在可活动范围之外。
        north = bpy.data.collections.new(comp['collection'] + '_北腿')
        build_corner(coll, north, f'{comp["collection"]}_A', width, rnd)
        lo, hi = coll_bounds(north)
        # 北腿：x 压到 [-W,0]，y 从 0 往外
        transform_coll(north, Matrix.Translation((-hi.x, -lo.y, 0)))
        east = bpy.data.collections.new(comp['collection'] + '_东腿')
        build_corner(coll, east, f'{comp["collection"]}_B', width, rnd)
        transform_coll(east, Matrix.Rotation(-math.pi / 2, 4, 'Z'))
        lo, hi = coll_bounds(east)
        # 东腿：x 从 0 往外，y 压到 [-W,0]
        transform_coll(east, Matrix.Translation((-lo.x, -hi.y, 0)))
        # 不再补「对角块」。它是按一个朝向手工摆的装饰块，母版转到另两个对角
        # （NW/SE 需要镜像，不是旋转）时会整个掉进可活动范围里 —— 圈内的空海面上
        # 凭空空降一片废墟。四个角只用两条 10 米腿，缺的外侧小角在围挡外、
        # 从圈内看不到，宁可留空也不放错位的东西。
    else:
        build_segment(comp['collection'], coll, width, comp['depth_m'], comp['kind'], rnd)
        # 内侧最凸点（通常是树冠或碎石）对齐边界，围挡全部落在 90x90 之外
        lo, _ = coll_bounds(coll)
        transform_coll(coll, Matrix.Translation((0, -comp['depth_m'] / 2 - lo.y, 0)))
    return coll


CATALOG = []
for comp in PLAN['components']:
    coll = build_component(comp)
    objs = [o for o in coll.all_objects if o.type == 'MESH']
    tris = 0
    fingerprint = hashlib.sha256()
    for obj in sorted(objs, key=lambda o: o.name):
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
        # 几何指纹：对象名 + 全部顶点坐标。源或摆位一改就对不上，登记脚本据此防漂移。
        fingerprint.update(obj.name.encode('utf-8'))
        for vert in obj.data.vertices:
            fingerprint.update(
                f'{vert.co.x:.5f},{vert.co.y:.5f},{vert.co.z:.5f};'.encode('utf-8'))
    lo, hi = coll_bounds(coll)
    size = [round(hi[i] - lo[i], 4) for i in range(3)]
    CATALOG.append({
        'key': comp['key'], 'name': comp['name'], 'asset_id': comp['asset_id'],
        'collection': comp['collection'], 'category': comp['category'],
        'family': comp['family'], 'kind': comp['kind'],
        'mesh_objects': len(objs), 'triangles': tris,
        'geometry_fingerprint': fingerprint.hexdigest(), 'bounds_size_m': size,
        'bounds_min': [round(v, 4) for v in lo],
        'bounds_max': [round(v, 4) for v in hi],
        'material_roles': ['SEA_Matte'],
    })
    print('BUILD', comp['key'], len(objs), tris, size, flush=True)

# 完整围合：每个摆位一个 Collection Instance，几何仍是各组件自己那一份。
for inst in PLAN['instances']:
    comp = next(c for c in PLAN['components'] if c['key'] == inst['component'])
    obj = bpy.data.objects.new(f'围挡_{comp["key"]}_{inst["yaw_deg"]:.0f}', None)
    obj.instance_type = 'COLLECTION'
    obj.instance_collection = bpy.data.collections[comp['collection']]
    obj.location = (inst['position'][0], inst['position'][1], 0)
    obj.rotation_euler = (0, 0, math.radians(inst['yaw_deg']))
    ASSEMBLY.collection.objects.link(obj)

(D / 'component_catalog.json').write_text(
    json.dumps({'suite': 'sea_barrier', 'version': 'v001', 'components': CATALOG},
               ensure_ascii=False, indent=2) + '\n', encoding='utf8')

for comp in PLAN['components']:
    out = D / 'component_packages' / comp['key']
    out.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(out / f'{comp["key"]}.blend'),
                             {bpy.data.collections[comp['collection']]},
                             fake_user=True, compress=False)

bpy.ops.wm.save_as_mainfile(filepath=str(D / 'sea_barrier.blend'), compress=False)
print('SAVED', D / 'sea_barrier.blend')
print('TOTAL_TRIS', sum(c['triangles'] for c in CATALOG))
