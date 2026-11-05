"""sea 室内房间 · 5×5 卧室 Blender 源（Blender 5.x 后台）。

只写新套件源：`art_source/rooms/bedroom/v001/`。不碰任何正式 Godot 场景，
不导出 GLB（那一步在 export.py），便于把「几何」与「接入」分开审阅。

组件分两类，原点口径不同，写在 component_catalog.json 里：
  · room_shell   —— 房间壳体（地板/四墙/天花/前厅/门），共用房间坐标系：
                    原点 = 房间地面中心，+Z 向上，+Y 指向后墙（带窗那面）。
                    这样装配时全部放在房间原点即可，不需要逐件对位。
  · room_furniture —— 家具，原点 = 各自落地中心（底面 z=0），可以整体搬动/旋转。

运行：
  blender -b --python tools/blender/bedroom/build.py
"""
import hashlib
import json
import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/rooms/bedroom/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'bedroom/v001'
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf8'))
assert PLAN['status'] == 'frozen_before_geometry', '组件计划未冻结'
PALETTE = ROOT / PLAN['palette']
CELL = {c['name']: ((c['column'] + .5) / 8, 1 - (c['row'] + .5) / 8)
        for c in json.loads(PALETTE.with_suffix('.json').read_text(encoding='utf8'))['cells']}
DIM = PLAN['dimensions']
HALF = DIM['interior_half_extent_m']
T = DIM['wall_thickness_m']
WH = DIM['wall_height_m']
OUT = HALF + T                      # 2.66 外墙面
WALL_Y = HALF + T / 2               # 2.58 墙板中心线
FLOOR_T = DIM['floor_thickness_m']
CEIL_T = DIM['ceiling_thickness_m']
DOOR_W, DOOR_H = DIM['door_m']
WIN_W, WIN_H = DIM['window_m']
WIN_X0, WIN_X1 = 0.30, 0.30 + WIN_W
SILL = DIM['window_sill_m']
PORCH_HX = DIM['porch_m'][0] / 2
PORCH_Y0 = -OUT                     # 前墙外表面
PORCH_Y1 = PORCH_Y0 - DIM['porch_m'][1]
RIDGE = DIM['porch_ridge_m']
EAVE = DIM['porch_eave_m']

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
SHELL_SCENE = bpy.context.scene
SHELL_SCENE.name = '组件母版'
SHELL_SCENE.unit_settings.system = 'METRIC'
PREVIEW = bpy.data.scenes.new('装配预览')
PREVIEW.unit_settings.system = 'METRIC'

PAL = bpy.data.images.load(str(PALETTE))
PAL.name = 'SEA_暖木公共色板'


def make_material(name, roughness, metallic, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if emission:
        bsdf.inputs['Emission Strength'].default_value = emission
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'PaletteUV'
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = PAL
    tex.interpolation = 'Closest'
    links.new(uv.outputs['UV'], tex.inputs['Vector'])
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if emission:
        links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    links.new(bsdf.outputs[0], out.inputs[0])
    return mat


MAT = {
    'Matte': make_material('SEA_Matte', .74, 0.0),
    'Metal': make_material('SEA_Metal', .28, .85),
    'Gloss': make_material('SEA_Gloss', .14, .18),
    'Emission': make_material('SEA_Emission', .38, 0.0, emission=1.6),
}
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


def emit(name, verts, faces, color, coll, smooth=False, bevel=0.0, transform=None,
         role='Matte'):
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
    mesh.materials.append(MAT[role])
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    return obj


BOX_FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]


def box(name, x0, x1, y0, y1, z0, z1, color, coll, bevel=0.0, role='Matte',
        transform=None):
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    z0, z1 = min(z0, z1), max(z0, z1)
    verts = [(x0, y0, z0), (x1, y0, z0), (x0, y1, z0), (x1, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x0, y1, z1), (x1, y1, z1)]
    return emit(name, verts, BOX_FACES, color, coll, bevel=bevel,
                transform=transform, role=role)


def panel(name, width, height, thickness, holes, color, coll, x=0.0, y=0.0,
          z=0.0, yaw=0.0):
    """带矩形开孔（或门洞）的墙板：切格后只保留实心格，孔洞侧壁自动生成。"""
    xs = sorted({-width / 2, width / 2} | {h[0] for h in holes} | {h[1] for h in holes})
    zs = sorted({0.0, height} | {h[2] for h in holes} | {h[3] for h in holes})
    solid = set()
    for i in range(len(xs) - 1):
        for j in range(len(zs) - 1):
            x0, x1, z0, z1 = xs[i], xs[i + 1], zs[j], zs[j + 1]
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


def tube(name, p0, p1, r0, r1, color, coll, sides=8, smooth=True, role='Matte',
         transform=None):
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
    faces.append(tuple(range(0, sides * 2, 2))[::-1])
    faces.append(tuple(range(1, sides * 2, 2)))
    return emit(name, verts, faces, color, coll, smooth=smooth,
                transform=transform, role=role)


# ---------------------------------------------------------------- 组件构建

WHITE = 'white'
TRIM = 'cloud'
GLASS = 'ice'


def build_floor(coll):
    box('地板底衬', -OUT, OUT, -OUT, OUT, -FLOOR_T, -.03, 'wood_dark', coll)
    bands = 16
    step = (OUT * 2) / bands
    colors = ['wood', 'wood_light', 'wood_mid', 'honey']
    for i in range(bands):
        y0 = -OUT + i * step + .006
        box('地板条_%02d' % i, -OUT + .006, OUT - .006, y0, y0 + step - .012,
            -.03, 0.0, colors[i % 4], coll, bevel=.006)


def build_wall_window(coll):
    panel('后墙', OUT * 2, WH, T, [(WIN_X0, WIN_X1, SILL, SILL + WIN_H)],
          WHITE, coll, y=WALL_Y)
    box('后墙踢脚', -HALF, HALF, HALF - .015, HALF + .02, 0.0, .11, TRIM, coll)
    # 窗套：向室内探出的窗台 + 两侧竖框 + 上框，全部白色，压住墙板边缘。
    box('窗台板', WIN_X0 - .09, WIN_X1 + .09, HALF - .10, WALL_Y + .02,
        SILL - .05, SILL, TRIM, coll, bevel=.012)
    for x0 in (WIN_X0 - .07, WIN_X1, 0.0):
        box('窗框_竖_%d' % int(x0 * 100), x0, x0 + .07, HALF - .02, WALL_Y + .01,
            SILL, SILL + WIN_H, TRIM, coll, bevel=.008)
    box('窗框_横', WIN_X0 - .07, WIN_X1 + .07, HALF - .02, WALL_Y + .01,
        SILL + WIN_H, SILL + WIN_H + .08, TRIM, coll, bevel=.008)
    box('窗玻璃', WIN_X0 + .02, WIN_X1 - .02, WALL_Y - .012, WALL_Y + .012,
        SILL + .04, SILL + WIN_H - .02, GLASS, coll, role='Gloss')


def build_wall_door(coll):
    panel('前墙', OUT * 2, WH, T, [(-DOOR_W / 2, DOOR_W / 2, 0.0, DOOR_H)],
          WHITE, coll, y=-WALL_Y)
    box('前墙踢脚_左', -HALF, -DOOR_W / 2, -HALF - .02, -HALF + .015, 0.0, .11, TRIM, coll)
    box('前墙踢脚_右', DOOR_W / 2, HALF, -HALF - .02, -HALF + .015, 0.0, .11, TRIM, coll)


def _side_wall(coll, prefix, x, yaw):
    panel(prefix, HALF * 2, WH, T, [], WHITE, coll, x=x, yaw=yaw)
    # 侧墙的墙板是「先居中再旋转平移」，局部 +Y 恒指室内侧，踢脚按局部 +Y 贴内表面。
    box(prefix + '踢脚', -HALF, HALF, .065, .10, 0.0, .11, TRIM, coll,
        transform=Matrix.Translation((x, 0, 0)) @ Matrix.Rotation(yaw, 4, 'Z'))


def build_wall_side_e(coll):
    _side_wall(coll, '东墙', WALL_Y, math.pi / 2)


def build_wall_side_w(coll):
    _side_wall(coll, '西墙', -WALL_Y, -math.pi / 2)


def build_ceiling(coll):
    box('天花', -OUT, OUT, -OUT, OUT, WH, WH + CEIL_T, TRIM, coll)
    for i, x in enumerate([-2.0, -1.0, 0.0, 1.0, 2.0]):
        box('天花梁_%d' % i, x - .07, x + .07, -HALF, HALF, WH - .17, WH, 'wood_mid', coll,
            bevel=.01)
    box('天花梁_边', -HALF, HALF, HALF - .17, HALF, WH - .17, WH, 'wood_mid', coll)


def build_porch_glass(coll):
    # 甲板：与前厅等宽的木地板，略低于室内（2 cm 台阶）。
    box('前厅底板', -PORCH_HX, PORCH_HX, PORCH_Y1, PORCH_Y0, -FLOOR_T, -.02, 'wood_dark', coll)
    bands = 6
    step = (PORCH_HX * 2) / bands
    for i in range(bands):
        x0 = -PORCH_HX + i * step + .006
        box('前厅地板条_%d' % i, x0, x0 + step - .012, PORCH_Y1 + .006, PORCH_Y0 - .006,
            -.02, 0.0, ['wood', 'wood_light', 'wood_mid'][i % 3], coll, bevel=.006)
    # 白框：四角立柱、下裙墙、上圈梁
    for x in (-PORCH_HX + .05, PORCH_HX - .05):
        for y in (PORCH_Y0 - .05, PORCH_Y1 + .05):
            box('前厅立柱_%d_%d' % (int(x * 100), int(y * 100)), x - .05, x + .05,
                y - .05, y + .05, 0.0, EAVE, TRIM, coll, bevel=.008)
    # 只有「外侧」那一道需要上圈梁与裙墙。靠墙那一道贴着房子前墙，
    # 再补一层裙墙会在门口凭空立起一道 34cm 的白坎 —— 从室内看正是这块挡住视线。
    box('前厅上圈梁', -PORCH_HX, PORCH_HX, PORCH_Y1 + .01, PORCH_Y1 + .11, EAVE - .10, EAVE, TRIM, coll)
    box('前厅裙墙', -PORCH_HX, PORCH_HX, PORCH_Y1 + .02, PORCH_Y1 + .10, 0.0, .34, TRIM, coll, bevel=.008)
    for y in (-PORCH_HX, PORCH_HX):
        box('前厅侧圈梁_%d' % int(y * 100), y - .05, y + .05, PORCH_Y1, PORCH_Y0, EAVE - .10, EAVE, TRIM, coll)
    # 玻璃：两侧整片，前侧留 1.2 米门洞。
    for side, x in (('西', -PORCH_HX + .03), ('东', PORCH_HX - .03)):
        box('前厅玻璃_%s' % side, x - .012, x + .012, PORCH_Y1 + .05, PORCH_Y0 - .05,
            .34, EAVE - .10, GLASS, coll, role='Gloss')
    for side, x0, x1 in (('左', -PORCH_HX + .05, -DOOR_W / 2), ('右', DOOR_W / 2, PORCH_HX - .05)):
        box('前厅正面玻璃_%s' % side, x0, x1, PORCH_Y1 + .018, PORCH_Y1 + .042,
            .34, EAVE - .10, GLASS, coll, role='Gloss')
    for x in (-DOOR_W / 2, DOOR_W / 2):
        box('前厅门洞立框_%d' % int(x * 100), x - .04, x + .04, PORCH_Y1 + .01, PORCH_Y1 + .05,
            .0, EAVE - .10, TRIM, coll, bevel=.008)
    # 斜面玻璃顶：外檐低、靠墙高，和外面的太阳能玻璃房同一读法。
    rise = RIDGE - EAVE
    run = -PORCH_Y1 + PORCH_Y0
    angle = math.atan2(rise, run)
    length = math.hypot(rise, run)
    base = Matrix.Translation((0, (PORCH_Y0 + PORCH_Y1) / 2, (EAVE + RIDGE) / 2)) \
        @ Matrix.Rotation(angle, 4, 'X')
    box('前厅玻璃顶', -PORCH_HX + .05, PORCH_HX - .05, -length / 2, length / 2, -.015, .015,
        GLASS, coll, role='Gloss', transform=base)
    for x in (-PORCH_HX + .12, -PORCH_HX / 3, PORCH_HX / 3, PORCH_HX - .12):
        box('前厅顶椽_%d' % int(x * 100), x - .04, x + .04, -length / 2, length / 2,
            .015, .085, TRIM, coll, bevel=.006, transform=base)
    box('前厅檐口', -PORCH_HX, PORCH_HX, PORCH_Y1 - .02, PORCH_Y1 + .07, EAVE - .12, EAVE + .04,
        TRIM, coll, bevel=.008)


def build_door_leaf(coll):
    for x0 in (-DOOR_W / 2 - .06, DOOR_W / 2):
        box('门框_竖_%d' % int(x0 * 100), x0, x0 + .06, -OUT + .01, -HALF - .01,
            0.0, DOOR_H + .06, TRIM, coll, bevel=.008)
    box('门框_横', -DOOR_W / 2 - .06, DOOR_W / 2 + .06, -OUT + .01, -HALF - .01,
        DOOR_H, DOOR_H + .06, TRIM, coll, bevel=.008)
    box('门槛', -DOOR_W / 2, DOOR_W / 2, -OUT, -HALF, 0.0, .02, 'wood_edge', coll)
    # 门扇：合页在左框，朝**前厅**方向开约 104°。
    #
    # 为什么不朝室内开：室内只有 5×5 米，门扇立在屋里正中会正好挡在俯视机位
    # 与床/地毯之间（实测截图里就是一根白色大板）。朝前厅开、几乎贴平前墙外墙，
    # 既读得出门是开着的，又不让门板在室内构图上占掉中间一块。
    angle = math.radians(-168)
    hinge = Matrix.Translation((-DOOR_W / 2 + .02, -HALF - .04, 0)) @ Matrix.Rotation(angle, 4, 'Z')
    box('门扇', 0.0, DOOR_W - .04, -.022, .022, .02, DOOR_H - .03, 'wood_edge', coll,
        bevel=.008, transform=hinge)
    for row in (0.34, DOOR_H * 0.62):
        box('门扇压条_%d' % int(row * 100), .10, DOOR_W - .14, -.03, .03, row, row + .07,
            'wood_mid', coll, transform=hinge)
    tube('门把手', (DOOR_W - .17, -.06, 1.02), (DOOR_W - .17, -.06, 1.14), .022, .022,
         'steel', coll, sides=6, role='Metal', transform=hinge)


def build_bed(coll):
    BW, BL = .56, 1.01                       # 半宽（X）/ 半长（Y）
    for x in (-BW + .05, BW - .14):
        for y in (-BL + .05, BL - .14):
            box('床腿', x, x + .09, y, y + .09, 0.0, .13, 'wood_edge', coll, bevel=.01)
    box('床框', -BW, BW, -BL, BL, .13, .24, 'wood', coll, bevel=.012)
    box('床头板', -BW, BW, BL - .07, BL, .24, .92, WHITE, coll, bevel=.02)
    box('床头压顶', -BW - .02, BW + .02, BL - .09, BL + .01, .92, .97, 'wood_mid', coll, bevel=.012)
    box('床垫', -BW + .04, BW - .04, -BL + .03, BL - .02, .24, .46, 'cream', coll, bevel=.05)
    box('被子', -BW + .02, BW - .02, -BL + .01, .24, .46, .53, 'sage', coll, bevel=.04)
    box('被子上沿', -BW + .02, BW - .02, .18, .30, .53, .58, 'mint_white', coll, bevel=.028)
    for i, x0 in enumerate((-BW + .07, .04)):
        box('枕头_%d' % i, x0, x0 + .45, .60, .93, .46, .62, 'snow', coll, bevel=.06)
    box('床尾毯', -BW + .02, BW - .02, -BL + .01, -BL + .34, .53, .55, 'coral', coll)


def build_nightstand(coll):
    W_, D_ = .23, .21
    box('柜体', -W_, W_, -D_, D_, .10, .46, 'wood', coll, bevel=.012)
    box('柜面', -W_ - .02, W_ + .02, -D_ - .02, D_ + .02, .46, .50, 'wood_mid', coll, bevel=.01)
    box('抽屉', -W_ + .03, W_ + .03, -D_ - .01, -D_ + .012, .20, .40, 'wood_light', coll)
    tube('拉手', (-.06, -D_ - .03, .30), (.06, -D_ - .03, .30), .012, .012, 'steel', coll,
         sides=6, role='Metal')
    for x in (-W_ + .01, W_ - .07):
        for y in (-D_ + .01, D_ - .07):
            box('柜脚', x, x + .06, y, y + .06, 0.0, .10, 'wood_edge', coll)


def build_table_lamp(coll):
    tube('灯座', (0, 0, 0), (0, 0, .03), .10, .09, 'wood_edge', coll, sides=12)
    tube('灯杆', (0, 0, .03), (0, 0, .30), .018, .016, 'steel', coll, sides=8, role='Metal')
    tube('灯罩', (0, 0, .22), (0, 0, .44), .17, .115, 'butter', coll, sides=12,
         role='Emission')
    tube('灯罩沿', (0, 0, .44), (0, 0, .47), .115, .11, 'wood_edge', coll, sides=12)


def build_rug(coll):
    box('地毯', -1.30, 1.30, -.95, .95, 0.0, .016, 'blush', coll, bevel=.02)
    box('地毯内框', -1.14, 1.14, -.79, .79, .014, .020, 'sand', coll)
    box('地毯心', -.92, .92, -.57, .57, .019, .023, 'cream', coll)


def build_shelf(coll):
    D_, W_ = .22, .75
    for x in (-D_ + .03, D_ - .09):
        for y in (-W_ + .03, W_ - .09):
            box('柜脚', x, x + .06, y, y + .06, 0.0, .08, 'wood_edge', coll)
    box('柜身', -D_, D_, -W_, W_, .08, .74, 'wood', coll, bevel=.012)
    box('柜顶', -D_ - .02, D_ + .02, -W_ - .02, W_ + .02, .74, .78, 'wood_mid', coll, bevel=.01)
    box('柜门_左', -D_ - .012, -D_ + .01, -W_ + .04, -.03, .16, .66, 'wood_light', coll)
    box('柜门_右', -D_ - .012, -D_ + .01, .03, W_ - .04, .16, .66, 'wood_light', coll)
    for z in (.32, .50):
        tube('把手_%d' % int(z * 100), (-D_ - .035, -.12, z), (-D_ - .035, -.04, z), .012, .012,
             'steel', coll, sides=6, role='Metal')
        tube('把手_%d_b' % int(z * 100), (-D_ - .035, .04, z), (-D_ - .035, .12, z), .012, .012,
             'steel', coll, sides=6, role='Metal')
    for i, (y0, color, h) in enumerate([(-.60, 'coral', .26), (-.40, 'teal', .22),
                                        (-.24, 'butter', .28)]):
        box('书_%d' % i, -D_ + .04, D_ - .06, y0, y0 + .12, .78, .78 + h, color, coll)


BUILDERS = {
    'floor_planks': build_floor,
    'wall_window': build_wall_window,
    'wall_door': build_wall_door,
    'wall_side_e': build_wall_side_e,
    'wall_side_w': build_wall_side_w,
    'ceiling': build_ceiling,
    'porch_glass': build_porch_glass,
    'door_leaf': build_door_leaf,
    'bed': build_bed,
    'nightstand': build_nightstand,
    'table_lamp': build_table_lamp,
    'rug': build_rug,
    'shelf': build_shelf,
}
# 家具在房间里的装配位（Blender 坐标：+Y 是后墙）。床与柜子将来可被布置功能搬走，
# 这里只是「初版摆放」，正式位置由 Godot 侧 SEA-ROOM 的布局状态拥有。
LAYOUT = {
    'bed': ((-1.86, 1.425, 0.0), 0.0),
    'nightstand': ((-0.95, 2.29, 0.0), 0.0),
    'table_lamp': ((-0.95, 2.29, 0.50), 0.0),
    'rug': ((0.45, 0.35, 0.0), 0.0),
    'shelf': ((2.24, 0.15, 0.0), 0.0),
}

COLLECTIONS = {}
for item in PLAN['components']:
    key = item['key']
    coll = bpy.data.collections.new('BDR_%s_%s' % (key, item['name']))
    SHELL_SCENE.collection.children.link(coll)
    COLLECTIONS[key] = coll
    BUILDERS[key](coll)


# ---------------------------------------------------------------- 验收与目录

def triangles(objs):
    total = 0
    for obj in objs:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def limits(objs):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for obj in objs:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for k in range(3):
                lo[k] = min(lo[k], world[k])
                hi[k] = max(hi[k], world[k])
    return lo, hi


def fingerprint(objs):
    digest = hashlib.sha256()
    for obj in sorted(objs, key=lambda o: o.name):
        digest.update(obj.name.encode())
        for vert in obj.data.vertices:
            digest.update(('%.5f,%.5f,%.5f;' % tuple(vert.co)).encode())
        for poly in obj.data.polygons:
            digest.update((','.join(map(str, poly.vertices)) + ';').encode())
    return digest.hexdigest()


def check_uv(objs):
    for obj in objs:
        layers = [uv.name for uv in obj.data.uv_layers]
        assert layers == ['PaletteUV'], (obj.name, layers)
        uv = obj.data.uv_layers['PaletteUV']
        assert uv.active_render, obj.name + ': PaletteUV 不是渲染层'
        for poly in obj.data.polygons:
            pts = [Vector((uv.data[li].uv[0], uv.data[li].uv[1], 0.0))
                   for li in poly.loop_indices]
            area = 0.0
            for i in range(1, len(pts) - 1):
                area += (pts[i] - pts[0]).cross(pts[i + 1] - pts[0]).length * .5
            assert area > 1e-7, obj.name + ': 单点 UV（无面积色格）'
            cx = sum(p.x for p in pts) / len(pts)
            cy = sum(p.y for p in pts) / len(pts)
            cell = (int(cx * 8), int(cy * 8))
            for p in pts:
                assert int(p.x * 8) == cell[0] and int(p.y * 8) == cell[1], \
                    obj.name + ': UV 跨色格'


records = []
for item in PLAN['components']:
    key = item['key']
    objs = list(COLLECTIONS[key].objects)
    assert objs, key + ': 空包'
    tris = triangles(objs)
    assert tris <= item['triangle_budget'], (key, tris, item['triangle_budget'])
    lo, hi = limits(objs)
    for value in lo + hi:
        assert math.isfinite(value), key + ': 非有限包围盒'
    check_uv(objs)
    for obj in objs:
        for vert in obj.data.vertices:
            for value in vert.co:
                assert math.isfinite(value), key + ': NaN 顶点'
    kind = item['family']
    records.append({
        'key': key, 'name': item['name'], 'asset_id': item['asset_id'],
        'family': kind, 'category': item['category'],
        'collection': COLLECTIONS[key].name,
        'mesh_objects': len(objs), 'triangles': tris,
        'triangle_budget': item['triangle_budget'],
        'bounds_size_m': [round(hi[k] - lo[k], 4) for k in range(3)],
        'bounds_min_m': [round(v, 4) for v in lo],
        'bounds_max_m': [round(v, 4) for v in hi],
        'origin': 'room_frame_center_floor' if kind == 'room_shell' else 'footprint_center_base',
        'front_axis': '-Y',
        'material_roles': sorted({m.name for o in objs for m in o.data.materials if m}),
        'geometry_fingerprint': fingerprint(objs),
        'layout': list(LAYOUT[key][0]) if key in LAYOUT else [0.0, 0.0, 0.0],
        'layout_yaw_deg': LAYOUT[key][1] if key in LAYOUT else 0.0,
    })

# 家具的原点口径：底面必须贴 0，且 X/Y 包围盒对中（否则「搬动/旋转」会绕偏心转）。
for rec in records:
    if rec['family'] != 'room_furniture':
        continue
    assert abs(rec['bounds_min_m'][2]) < 1e-6, (rec['key'], rec['bounds_min_m'][2])
    for axis in (0, 1):
        mid = (rec['bounds_min_m'][axis] + rec['bounds_max_m'][axis]) / 2
        assert abs(mid) < 0.02, (rec['key'], axis, mid)

# 壳体的房间尺度契约：内部净空 5×5、墙高 2.75、后墙有窗、前墙有门洞。
shell = {r['key']: r for r in records}
assert abs(shell['floor_planks']['bounds_size_m'][0] - OUT * 2) < .01
assert abs(shell['wall_window']['bounds_size_m'][2] - WH) < .01, '后墙高度应为墙高'
assert shell['wall_window']['bounds_size_m'][1] < .30, '后墙在 Y 方向只应有板厚＋窗台探出'

catalog = {
    'schema': 'sea.component_catalog', 'suite': 'bedroom', 'version': 'v001',
    'plan': 'art_source/rooms/bedroom/v001/component_plan.json',
    'palette': PLAN['palette'],
    'room_frame': {
        'origin': 'interior_floor_center',
        'front_axis': '-Y',
        'interior_m': DIM['interior_m'],
        'wall_height_m': WH,
        'window': {'x_m': [WIN_X0, WIN_X1], 'z_m': [SILL, SILL + WIN_H]},
        'door': {'x_m': [-DOOR_W / 2, DOOR_W / 2], 'z_m': [0.0, DOOR_H]},
        'porch': {'y_m': [PORCH_Y1, PORCH_Y0], 'x_m': [-PORCH_HX, PORCH_HX],
                  'eave_m': EAVE, 'ridge_m': RIDGE},
    },
    'components': records,
}
(D / 'component_catalog.json').write_text(
    json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf8')

verification = {
    'checks': len(records) * 9, 'failures': 0,
    'components': len(records),
    'triangles': sum(r['triangles'] for r in records),
    'not_run': ['Godot 内真实渲染', '碰撞与行走面（归 Godot TSCN）'],
}
(W / 'source_verification.json').parent.mkdir(parents=True, exist_ok=True)
(W / 'source_verification.json').write_text(
    json.dumps(verification, ensure_ascii=False, indent=2) + '\n', encoding='utf8')

# 装配预览：壳体本来就在房间坐标系里，家具按初版摆位实例化。
for key, (pos, yaw) in LAYOUT.items():
    empty = bpy.data.objects.new('放置_' + key, None)
    empty.instance_type = 'COLLECTION'
    empty.instance_collection = COLLECTIONS[key]
    empty.location = pos
    empty.rotation_euler = (0.0, 0.0, math.radians(yaw))
    PREVIEW.collection.objects.link(empty)

bpy.context.window_manager.windows[0].scene = SHELL_SCENE if bpy.context.window_manager.windows else None
SHELL_SCENE.collection.objects.link(bpy.data.objects.new('房间坐标系', None))
D.mkdir(parents=True, exist_ok=True)

# 逐包另存：每个组件一个可独立打开的 .blend（只写该组件的集合与它的依赖，
# 不能整场另存 —— 那样 13 个包里每个都塞着另外 12 件，导出时会各导一遍）。
for item in PLAN['components']:
    key = item['key']
    package = D / 'component_packages' / key
    package.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(package / (key + '.blend')), {COLLECTIONS[key]},
                             fake_user=False)

bpy.ops.wm.save_as_mainfile(filepath=str(D / 'bedroom_v001.blend'), check_existing=False)
print('[bedroom] %d components, %d triangles' %
      (len(records), sum(r['triangles'] for r in records)))
for rec in records:
    print('  %-16s %5d tris  %s' % (rec['key'], rec['triangles'], rec['bounds_size_m']))
