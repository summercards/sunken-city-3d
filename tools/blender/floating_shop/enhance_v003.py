"""Restore v002's retail detail onto the v003 rectangular shell.

Scope (user 2026-10-31): only displays, advertising signs, glazing and interior
decorative lights. Deck, roof, wall module pitch, columns, awnings and railings
are untouched.

Run: blender -b <v003 blend> --python tools/blender/floating_shop/enhance_v003.py
"""
import bpy
import bmesh
import hashlib
import json
import math
import os
import shutil
from pathlib import Path
from mathutils import Matrix, Vector

R = Path('D:/projects/sea')
D = R / 'art_source/scenes/floating_shop/v003'
W = Path(os.environ.get('SEA_WORK_ROOT', 'D:/projects/sea-work')) / 'floating_shop/v003'
W.mkdir(parents=True, exist_ok=True)
CL = json.loads((R / '.agents/skills/sea-scene-component-authoring/references/building_scale.json')
                .read_text(encoding='utf-8'))['measurements']['ground_clear_height']
DECK_Z = 2.514
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()

if not (W / 'v003_before_retail.blend').exists():
    shutil.copy2(D / 'floating_shop.blend', W / 'v003_before_retail.blend')
    print('BACKUP v003_before_retail.blend')

# ---------------------------------------------------------------- component plan
NEW = [
    ('shop_window', '直线玻璃橱窗单元', 'window', 'building/structure', 'structure'),
    ('sign_gifts', 'GIFTS礼盒招牌', 'sign', 'building/structure', 'structure'),
    ('sign_drinks', 'COLD DRINKS饮料招牌', 'sign', 'building/structure', 'structure'),
    ('shop_lamp', '店内吊灯', 'lamp', 'building/structure', 'structure'),
    ('shop_string', '橱窗内侧串灯', 'lamp', 'building/structure', 'structure'),
    ('postcard_rack', '双面明信片旋转架', 'furniture', 'building/structure', 'structure'),
    ('mailbox', '红色邮筒', 'furniture', 'building/structure', 'structure'),
    ('ice_box', '白色ICE冷藏箱', 'furniture', 'building/structure', 'structure'),
    ('vending', '黄色投币售货机', 'furniture', 'building/structure', 'structure'),
    ('shelf', '店内三层陈列架', 'furniture', 'building/structure', 'structure'),
    ('bottle', '彩色饮料瓶组', 'goods', 'building/structure', 'structure'),
    ('gift', '礼品盒与玩偶陈列组', 'goods', 'building/structure', 'structure'),
]
plan_path = D / 'component_plan.json'
plan = json.loads(plan_path.read_text(encoding='utf-8'))
have = {c['key'] for c in plan['components']}
for key, name, family, category, group in NEW:
    if key in have:
        continue
    plan['components'].append({
        'key': key, 'asset_id': 'SEA-SCENE-FSH-' + key.upper().replace('_', '-'),
        'name': name, 'family': family, 'category': category, 'source_group': group,
        'scope': 'scene_local', 'origin': 'bottom_center', 'front_axis': '-Y',
        'allowed_rotation': 'full Euler XYZ', 'triangle_budget': None,
    })
plan['revision_note'] = ('v003 retail pass: rectangular shell unchanged; reopening glazing, '
                         'advertising signs, exterior displays and interior decorative lights to '
                         'the v002 art direction (user 2026-10-31).')
plan['dimension_contract']['window_count'] = 4
plan['dimension_contract']['window_band_m'] = [0.56, 4.30]
plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

# ---------------------------------------------------------------- shared helpers
code = (R / 'tools/blender/floating_shop/build.py').read_text(encoding='utf-8')
exec(code[code.index('def finish('):code.index('def build_deck(')])

sc = bpy.data.scenes['海上悬浮商铺_v003']
if bpy.context.window_manager.windows:
    bpy.context.window_manager.windows[0].scene = sc
pal = R / json.loads(plan_path.read_text(encoding='utf-8'))['palette']
colors = {x['name']: x for x in json.loads(pal.with_suffix('.json').read_text())['cells']}
roles = {n: bpy.data.materials[n] for n in ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission']}
for im in bpy.data.images:
    if im.source == 'FILE' and ('sea_cozy' in im.filepath or 'sea_cabin_timber' in im.filepath):
        im.filepath = str(pal)
        im.reload()
# Glazing has to read as glazing: the v003 pass had flattened Gloss to opaque.
bs = next(n for n in roles['SEA_Gloss'].node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bs.inputs['Alpha'].default_value = .16
bs.inputs['Transmission Weight'].default_value = .70
roles['SEA_Gloss'].surface_render_method = 'DITHERED'
roles['SEA_Gloss'].use_transparency_overlap = False

catalog = json.loads((D / 'catalog.json').read_text(encoding='utf-8'))['components']
layout = json.loads((D / 'component_instances.json').read_text(encoding='utf-8'))['instances']


def drop_key(key):
    """Remove a component collection and every instance that uses it."""
    cname = 'SEA-SCENE-FSH-' + key.upper().replace('_', '-')
    for o in list(sc.objects):
        if o.instance_collection is not None and o.instance_collection.name == cname:
            bpy.data.objects.remove(o, do_unlink=True)
    col = bpy.data.collections.get(cname)
    if col is not None:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(col)
    global layout, catalog
    layout = [i for i in layout if i['key'] != key]
    catalog = [e for e in catalog if e['key'] != key]


def put(key, p, a=0.0, s=(1, 1, 1)):
    n = key + '_' + str(sum(1 for x in layout if x['key'] == key) + 1).zfill(3)
    o = bpy.data.objects.new(n, None)
    o.instance_type = 'COLLECTION'
    o.instance_collection = components[key]
    o.location = p
    o.rotation_euler = (0, 0, a)
    o.scale = s
    (plants_col if key in ('foliage', 'flowers') else building_col).objects.link(o)
    layout.append({'name': n, 'key': key,
                   'asset_id': 'SEA-SCENE-FSH-' + key.upper().replace('_', '-'),
                   'position': list(p), 'rotation_euler_xyz': list(o.rotation_euler),
                   'scale': list(s)})
    return o


building_col = bpy.data.collections['FSH_建筑与固定设施']
plants_col = bpy.data.collections['FSH_植物附件']

# ---------------------------------------------------------------- new components
def shop_window():
    """2.0 m module, same footprint as a wall panel, so it drops straight in."""
    w = .99
    cube('橱窗上部奶油墙板', (0, 0, (4.30 + CL) / 2), (w * 2, .19, CL - 4.30), 'cream', bevel=.035)
    for z in [4.30 + .13, 4.30 + .30]:
        cube('橱窗上墙横缝', (0, -.103, z), (w * 2 - .04, .015, .017), 'stone', bevel=.003)
    cube('橱窗下部青绿窗裙', (0, 0, .28), (w * 2, .20, .56), 'sage_gray', 'SEA_Metal', .025)
    cube('橱窗内凹玻璃', (0, .035, (0.56 + 4.30) / 2), (w * 2 - .16, .035, 4.30 - .56), 'ice', 'SEA_Gloss', 0)
    for x in [-w, w]:
        cube('橱窗竖向青绿边框', (x, -.02, (0.46 + 4.36) / 2), (.10, .23, 4.36 - .46), 'sage_gray', 'SEA_Metal', .02)
    cube('橱窗中央竖梃', (0, -.02, (0.56 + 4.30) / 2), (.055, .20, 4.30 - .56), 'sage_gray', 'SEA_Metal', .012)
    for z in [.51, 4.35]:
        cube('橱窗横向青绿横档', (0, -.02, z), (w * 2, .23, .11), 'sage_gray', 'SEA_Metal', .02)
    cube('橱窗外挑窗台', (0, -.115, .49), (w * 2 + .06, .20, .07), 'cream', 'SEA_Metal', .02)
    for x in [-.62, .62]:
        cube('橱窗分格竖线', (x, .06, (0.56 + 4.30) / 2), (.022, .02, 4.30 - .56), 'sage_gray', 'SEA_Metal', .004)


def sign_board(body, size, icon):
    """Straight hanging fascia: cream panel, gold trim, geometric lettering."""
    cube('招牌米黄面板', (0, 0, .52), (3.02, .14, 1.02), 'butter', bevel=.032)
    for z in [.04, .99]:
        cube('招牌金色细框', (0, -.078, z), (3.0, .045, .05), 'ochre', 'SEA_Metal', .009)
    for x in [-1.48, 1.48]:
        cube('招牌竖边', (x, -.076, .52), (.05, .055, 1.04), 'ochre', 'SEA_Metal', .009)
    text('招牌文字_' + body, body, (-.42, -.086, .50), size, 'deepblue')
    if icon == 'gift':
        cube('招牌红色礼盒', (1.16, -.090, .38), (.38, .05, .40), 'red_dark', bevel=.022)
        cube('招牌礼盒盖', (1.16, -.094, .60), (.43, .06, .08), 'red', bevel=.014)
        cube('招牌礼盒金缎带', (1.16, -.100, .38), (.075, .02, .42), 'gold', bevel=.005)
        for x in [1.075, 1.245]:
            sphere('招牌礼盒蝴蝶结', (x, -.094, .67), (.095, .045, .07), 'red_dark', seg=16, rings=10)
    else:
        cube('招牌红饮料杯', (1.15, -.090, .36), (.26, .05, .40), 'red', bevel=.032)
        cube('招牌杯蓝盖', (1.15, -.094, .56), (.30, .06, .07), 'aqua', bevel=.014)
        rod('招牌吸管', (1.18, -.098, .57), (1.24, -.098, .76), .016, 'cream')


def shop_lamp():
    # `part()` re-centres every component so its lowest vertex sits at z=0.
    # Author the pendant bottom-up from the shade, then place the instance at the
    # world height where the shade should hang.
    rod('吊灯垂杆', (0, 0, 1.02), (0, 0, .40), .020, 'gray')
    cyl('吊灯黄铜灯座', (0, 0, .36), .072, .09, 'ochre', 'SEA_Metal', verts=20, bevel=.014)
    cyl('吊灯奶油灯罩', (0, 0, .20), .33, .21, 'cream', 'SEA_Emission', r2=.215, verts=32, bevel=.02)
    sphere('吊灯暖光灯泡', (0, 0, .055), (.115, .115, .12), 'butter', 'SEA_Emission', 22, 12)


def shop_string():
    """A slack strand of little bulbs just inside the glazing."""
    pts = []
    for i in range(25):
        t = i / 24.0
        x = -4.3 + 8.6 * t
        z = .34 - .20 * math.sin(math.pi * t)
        pts.append((x, 0, z))
    tube('串灯电线', pts, .012, 'slate', 'SEA_Metal')
    for i in range(13):
        t = i / 12.0
        x = -4.15 + 8.3 * t
        z = .34 - .20 * math.sin(math.pi * t) - .06
        sphere('串灯发光小球', (x, 0, z), (.048, .048, .056), 'butter', 'SEA_Emission', 14, 10)


def postcards():
    cyl('展架底座', (0, 0, .04), .32, .08, 'wood_light', verts=32)
    rod('展架转轴', (0, 0, .07), (0, 0, 1.78), .045, 'gray')
    for a in [0, math.pi / 2, math.pi, 3 * math.pi / 2]:
        for x in [-.15, .15]:
            for k in range(4):
                p = Matrix.Rotation(a, 4, 'Z') @ Vector((x, -.26, .45 + k * .30))
                cube('明信片白色卡套', p, (.25, .04, .28), 'snow', bevel=.009, rot=(0, 0, a))
                p2 = Matrix.Rotation(a, 4, 'Z') @ Vector((x, -.286, .45 + k * .30))
                cube('明信片彩色画面', p2, (.19, .013, .20), ['sky', 'coral', 'honey', 'seafoam'][k], bevel=.005, rot=(0, 0, a))
                p3 = Matrix.Rotation(a, 4, 'Z') @ Vector((x, -.298, .43 + k * .30))
                sphere('明信片图形', p3, (.06, .01, .05), ['white', 'leaf_mid', 'blue', 'ochre'][k], seg=12, rings=8)
    cyl('展架顶帽', (0, 0, 1.8), .16, .08, 'wood_light', verts=24)


def mailbox():
    cube('红邮筒主体', (0, 0, .61), (.49, .40, 1.16), 'red_dark', 'SEA_Metal', .08)
    cube('邮筒顶盖', (0, 0, 1.19), (.55, .44, .12), 'red', 'SEA_Metal', .055)
    cube('投信口黑缝', (0, -.207, 1.02), (.34, .025, .055), 'rubber', bevel=.01)
    cube('投信口雨檐', (0, -.23, 1.08), (.39, .09, .045), 'red', 'SEA_Metal', .012)
    cube('邮筒取件门', (0, -.212, .47), (.36, .025, .51), 'red', 'SEA_Metal', .025)
    text('POST小字', 'POST', (0, -.236, .78), .105, 'cream')
    sphere('邮筒门锁', (.12, -.24, .51), (.025, .015, .025), 'gold', 'SEA_Metal', 12, 8)


def icebox():
    cube('ICE白色保温箱', (0, 0, .61), (1, .70, 1.16), 'snow', 'SEA_Metal', .09)
    cube('ICE上翻盖', (0, 0, 1.18), (1.04, .74, .13), 'cream', 'SEA_Metal', .045)
    cube('ICE下部分隔缝', (0, -.358, .45), (.94, .012, .018), 'lightgray', bevel=.003)
    text('ICE蓝色字', 'ICE', (0, -.374, .85), .34, 'ocean')
    for x in [-.37, .37]:
        cube('冷柜盖扣', (x, -.39, 1.13), (.06, .045, .09), 'steel', 'SEA_Metal', .015)
    for x in [-.37, .37]:
        for y in [-.24, .24]:
            cyl('冷柜脚', (x, y, .035), .04, .07, 'slate', verts=12)


def vending():
    cube('黄色售货机身', (0, 0, .54), (.43, .38, 1.08), 'gold', 'SEA_Metal', .065)
    cube('售货装置上盖', (0, 0, 1.07), (.46, .4, .1), 'ochre', 'SEA_Metal', .04)
    cube('售货装置投币口', (.08, -.202, .84), (.13, .03, .035), 'slate', bevel=.008)
    cube('售货装置取货口', (0, -.205, .31), (.24, .025, .15), 'wood_mid', bevel=.025)
    cyl('售货机按钮', (-.10, -.218, .70), .047, .027, 'red_dark', rot=(math.pi / 2, 0, 0), verts=20)
    sphere('柜顶绿色小饮料', (0, 0, 1.22), (.095, .095, .16), 'leaf_mid', seg=20, rings=12)


def bottles():
    for i, c in enumerate(['red_dark', 'gold', 'leaf_mid', 'aqua', 'coral']):
        x = -.44 + i * .22
        cyl('饮料瓶身', (x, 0, .17), .075, .28, c, 'SEA_Matte', verts=20, bevel=.025)
        sphere('饮料瓶肩', (x, 0, .3), (.074, .074, .065), c, seg=20, rings=12)
        cyl('饮料瓶颈', (x, 0, .37), .032, .1, c, 'SEA_Matte', verts=16)
        cyl('饮料瓶盖', (x, 0, .43), .038, .035, 'cream', 'SEA_Metal', verts=16, bevel=.008)
        cyl('饮料白标签', (x, 0, .17), .077, .09, 'cream', 'SEA_Matte', verts=20, bevel=0)


def gifts():
    for i, c in enumerate(['coral', 'seafoam', 'honey']):
        x = -.43 + i * .42
        cube('礼品小盒', (x, 0, .17), (.30, .29, .31), c, bevel=.045)
        cube('礼品盒奶白缎带', (x, -.152, .17), (.06, .015, .32), 'cream', bevel=.008)
    sphere('黄色鸭玩偶身', (.12, 0, .48), (.15, .13, .14), 'gold', seg=20, rings=12)
    sphere('黄色鸭玩偶头', (.12, -.015, .65), (.10, .095, .105), 'gold', seg=20, rings=12)
    sphere('鸭橙色嘴', (.12, -.105, .63), (.07, .07, .035), 'ochre', seg=16, rings=8)
    for x in [.08, .16]:
        sphere('鸭小黑眼', (x, -.096, .68), (.012, .012, .012), 'rubber', seg=12, rings=8)


def cargo_crate():
    """Same crate as before, but the lid leaves the Gloss slot.

    Gloss is the glazing role now. A crate lid sharing it would turn
    see-through the moment the shop windows became transparent.
    """
    cube('矩形防水货箱', (0, 0, .38), (.95, .72, .76), 'seafoam', 'SEA_Metal', .07)
    cube('货箱奶白箱盖', (0, 0, .78), (1, .77, .10), 'cream', 'SEA_Metal', .045)
    for x in [-.31, .31]:
        cube('货箱金属箍', (x, -.368, .39), (.08, .025, .7), 'silver', 'SEA_Metal', .012)
    cube('箱盖扣', (0, -.405, .72), (.13, .05, .13), 'slate', 'SEA_Metal', .015)


for key, fn in [('cargo_crate', cargo_crate), ('shop_window', shop_window), ('shop_lamp', shop_lamp), ('shop_string', shop_string),
                ('postcard_rack', postcards), ('mailbox', mailbox), ('ice_box', icebox),
                ('vending', vending), ('bottle', bottles), ('gift', gifts),
                ('sign_gifts', lambda: sign_board('GIFTS', .40, 'gift')),
                ('sign_drinks', lambda: sign_board('COLD DRINKS', .27, 'drink'))]:
    drop_key(key)
    part(key, fn)
shelf_key = 'shelf'
drop_key(shelf_key)
part(shelf_key, lambda: [cube('陈列架层板', (0, 0, z), (1.9, .48, .10), 'wood_light', bevel=.025)
                         for z in [.08, .77, 1.46]] +
     [cube('陈列架侧撑', (x, 0, .76), (.08, .48, 1.55), 'wood_mid', bevel=.02) for x in [-.92, .92]])

# ---------------------------------------------------------------- layout changes
# Front wall: keep the two end panels, glaze the middle four bays.
for nm in ['wall_panel_002', 'wall_panel_003', 'wall_panel_004', 'wall_panel_005']:
    o = sc.objects.get(nm)
    if o is not None:
        bpy.data.objects.remove(o, do_unlink=True)
layout = [i for i in layout if i['name'] not in
          ('wall_panel_002', 'wall_panel_003', 'wall_panel_004', 'wall_panel_005')]
for x in [-3, -1, 1, 3]:
    put('shop_window', (x, -4.5, DECK_Z))

# Advertising: two more fascias flanking the SEA SUPPLY plate already on the wall.
# Same fascia band as the SEA SUPPLY plate (5.55 + DZ = 7.38). Anything lower
# sits behind the awning; the flanks of the 12 m wall are 3.2 m wide, cleared by
# the 2.8 m centre plate.
put('sign_gifts', (-4.42, -5.25, 7.38))
put('sign_drinks', (4.42, -5.25, 7.38))

# Exterior displays, clear of the 3.2 m railing opening at x -1.6..1.6.
put('postcard_rack', (-5.35, -5.85, DECK_Z))
put('mailbox', (-3.85, -5.30, DECK_Z))
put('vending', (2.75, -4.95, DECK_Z))
put('ice_box', (5.05, -5.65, DECK_Z))

# Rebuilt components lose their instances; re-place the crates where they stood.
put('cargo_crate', (7.1, 3, DECK_Z))
put('cargo_crate', (8.3, 3.3, DECK_Z), .08)
put('cargo_crate', (7.1, 3, 3.40))

# Interior: shelving behind the glass, goods on the shelves.
for x in [-3.1, -1.05, 1.05, 3.1]:
    put('shelf', (x, -3.95, DECK_Z))
for x in [-3.1, -1.05, 1.05, 3.1]:
    put('gift', (x, -3.90, DECK_Z + .82))
    put('bottle', (x, -3.92, DECK_Z + 1.51))

# Interior decorative light: pendants plus a strand just inside the glazing.
# Hangers sit inside the glazed band (world 3.07..6.81); the bulb of each
# pendant lands near 5.2 m so it reads from the deck through the glass.
for x in [-3.3, -1.1, 1.1, 3.3]:
    put('shop_lamp', (x, -4.16, 5.16))
put('shop_string', (0, -4.40, 4.62))

# ---------------------------------------------------------------- bookkeeping
for e in catalog:
    e['instances'] = sum(1 for x in layout if x['key'] == e['key'])
    e['version'] = 'v003'
    e['component_source'] = f"art_source/scenes/floating_shop/v003/component_packages/{e['key']}/{e['key']}.blend"
    if e['key'] == 'wall_panel':
        e['name'] = '奶油色封闭横缝墙板'
(D / 'catalog.json').write_text(json.dumps({'schema': 'sea.scene.component_catalog',
                                            'components': catalog}, ensure_ascii=False, indent=2) + '\n',
                                encoding='utf-8')
(D / 'component_instances.json').write_text(json.dumps({'schema': 'sea.scene.instances', 'up_axis': 'Z',
                                                        'front_axis': '-Y', 'godot_mapping': '(x,y,z)->(x,z,-y)',
                                                        'instances': layout}, ensure_ascii=False, indent=2) + '\n',
                                            encoding='utf-8')
for im in bpy.data.images:
    if im.source == 'FILE' and ('sea_cozy' in im.filepath or 'sea_cabin_timber' in im.filepath):
        im.filepath = bpy.path.relpath(str(pal), start=str(D))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'floating_shop.blend'), compress=True)
print('RETAIL_PASS ' + json.dumps({'components': len(catalog), 'instances': len(layout),
                                   'windows': sum(1 for x in layout if x['key'] == 'shop_window'),
                                   'new': [k for k, *_ in NEW]}, ensure_ascii=False))
