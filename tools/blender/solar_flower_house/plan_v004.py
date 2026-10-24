"""Write the frozen component plan for solar_flower_house v004.

Plan first: this file only records intent, budget and the reference hash. It must be
written and frozen before any geometry exists. Run with plain python3.
"""
import hashlib, json
from pathlib import Path

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/solar_flower_house/v004'
REF = D / 'reference.png'
PALETTE = R / 'art_source/shared/palettes/sea_cozy_8x8_512.png'

# (slug, name, category, family, variant_axis, variant_value, variant_reason)
SPEC = [
    ('base_slab', '房屋基座平台', 'building', 'platform', None, None, None),
    ('stilt', '深木桩柱', 'building', 'platform', None, None, None),
    ('stage_base', '门廊台基', 'building', 'platform', None, None, None),
    ('wall_ground', '一层墙壳', 'building', 'wall', None, None, None),
    ('wall_upper', '二层墙壳', 'building', 'wall', None, None, None),
    ('floor_slab', '二层楼板', 'building', 'slab', None, None, None),
    ('roof_terrace', '屋顶露台板', 'building', 'slab', None, None, None),
    ('column_short', '门廊短柱', 'building', 'column', 'height', '1.50m', '门廊前后柱高不同以承接倾斜屋面'),
    ('column_tall', '门廊高柱', 'building', 'column', 'height', '2.00m', '门廊前后柱高不同以承接倾斜屋面'),
    ('parapet', '白框女儿墙单元', 'building', 'railing', 'infill', 'panel', '屋顶需实心板挡风，二层露台需通透栏杆'),
    ('railing_open', '通透细栏杆单元', 'building', 'railing', 'infill', 'open', '屋顶需实心板挡风，二层露台需通透栏杆'),
    ('parapet_post', '女儿墙端柱', 'building', 'railing_end', None, None, None),
    ('handrail_wire', '细钢丝扶手', 'building', 'hardware', None, None, None),
    ('roof_slab', '门廊坡屋面', 'building', 'roof', None, None, None),
    ('roof_room', '屋顶小屋', 'building', 'roof_room', None, None, None),
    ('hip_roof', '小屋四坡顶', 'building', 'roof_room', None, None, None),
    ('window_cross', '青色十字格窗', 'building', 'opening', 'type', 'cross', '同族窗型按格栅区分宽窗与百叶窗'),
    ('window_louver', '青色百叶窗', 'building', 'opening', 'type', 'louver', '同族窗型按格栅区分宽窗与百叶窗'),
    ('vent_panel', '深紫通风面板', 'building', 'fixture', None, None, None),
    ('cabinet', '橙红百叶柜', 'building', 'fixture', None, None, None),
    ('solar_panel', '太阳能板阵', 'building', 'solar', None, None, None),
    ('panel_board', '板上木垫板', 'building', 'solar', None, None, None),
    ('awning', '黄白尖旗遮阳棚', 'building', 'awning', None, None, None),
    ('porch_plank', '橙色门廊板', 'building', 'decking', None, None, None),
    ('porch_step', '门廊台阶', 'building', 'decking', None, None, None),
    ('clamp_block', '深木卡块', 'building', 'decking', None, None, None),
    ('tire', '蓝色轮胎护舷', 'building', 'fender', None, None, None),
    ('pier_plank', '浅木栈桥板', 'building', 'pier', None, None, None),
    ('pier_rim', '白色栈桥包边', 'building', 'pier', None, None, None),
    ('dock_post', '橄榄木桩白帽', 'building', 'pier', None, None, None),
    ('crate_grid', '深木格箱', 'building', 'container', None, None, None),
    ('crate_lattice', '木格栅箱', 'building', 'container', None, None, None),
    ('barrel', '深蓝圆桶', 'building', 'container', None, None, None),
    ('planter_square', '木花箱', 'building', 'planter', None, None, None),
    ('planter_cream', '米色花箱', 'building', 'planter', None, None, None),
    ('planter_round', '陶土圆盆', 'building', 'planter', None, None, None),
    ('bench', '白框橙板长凳', 'building', 'seat', None, None, None),
    ('boat', '黄色小渔船', 'building', 'boat', None, None, None),
    ('outboard', '淡紫船外机', 'building', 'boat', None, None, None),
    ('oar', '木船桨', 'building', 'boat', None, None, None),
    ('fisherman', '草帽渔夫', 'building', 'figure', None, None, None),
    ('figure_white', '白瓷小人', 'building', 'figure', None, None, None),
    ('buoy_float', '粉青浮球', 'building', 'float', None, None, None),
    ('leaf_cluster', '阔叶绿植簇', 'flora', 'leaf', None, None, None),
    ('vine', '垂枝藤', 'flora', 'vine', None, None, None),
    ('cosmos', '粉色波斯菊', 'flora', 'bloom', 'species', 'pink', '同族花按花色区分粉白黄三色'),
    ('daisy', '白色雏菊', 'flora', 'bloom', 'species', 'white', '同族花按花色区分粉白黄三色'),
    ('goldflower', '黄色花苞', 'flora', 'bloom', 'species', 'yellow', '同族花按花色区分粉白黄三色'),
]

ROT = [0, 90, 180, 270]
PREFIX = {
    'base_slab': 'BASE-SLAB', 'stilt': 'STILT', 'stage_base': 'STAGE-BASE',
    'wall_ground': 'WALL-GROUND', 'wall_upper': 'WALL-UPPER', 'floor_slab': 'FLOOR-SLAB',
    'roof_terrace': 'ROOF-TERRACE', 'column_short': 'COLUMN-SHORT',
    'column_tall': 'COLUMN-TALL', 'parapet': 'PARAPET', 'railing_open': 'RAILING-OPEN', 'parapet_post': 'PARAPET-POST',
    'handrail_wire': 'HANDRAIL-WIRE', 'roof_slab': 'ROOF-SLAB', 'roof_room': 'ROOF-ROOM',
    'hip_roof': 'HIP-ROOF', 'window_cross': 'WINDOW-CROSS', 'window_louver': 'WINDOW-LOUVER',
    'vent_panel': 'VENT-PANEL', 'cabinet': 'CABINET', 'solar_panel': 'SOLAR-PANEL',
    'panel_board': 'PANEL-BOARD', 'awning': 'AWNING', 'porch_plank': 'PORCH-PLANK',
    'porch_step': 'PORCH-STEP', 'clamp_block': 'CLAMP-BLOCK', 'tire': 'TIRE',
    'pier_plank': 'PIER-PLANK', 'pier_rim': 'PIER-RIM', 'dock_post': 'DOCK-POST',
    'crate_grid': 'CRATE-GRID', 'crate_lattice': 'CRATE-LATTICE', 'barrel': 'BARREL',
    'planter_square': 'PLANTER-SQUARE', 'planter_cream': 'PLANTER-CREAM',
    'planter_round': 'PLANTER-ROUND', 'bench': 'BENCH', 'boat': 'BOAT',
    'outboard': 'OUTBOARD', 'oar': 'OAR', 'fisherman': 'FISHERMAN',
    'figure_white': 'FIGURE-WHITE', 'buoy_float': 'BUOY-FLOAT',
    'leaf_cluster': 'LEAF-CLUSTER', 'vine': 'VINE', 'cosmos': 'COSMOS',
    'daisy': 'DAISY', 'goldflower': 'GOLDFLOWER',
}

components = []
for slug, name, cat, fam, axis, val, why in SPEC:
    components.append({
        'component_id': 'SEA-SCENE-SOLAR-' + PREFIX[slug],
        'slug': slug, 'name': name, 'category': cat, 'component_family': fam,
        'scope': 'scene_local', 'variant_axis': axis, 'variant_value': val,
        'variant_reason': why, 'front_axis': '-Y', 'allowed_rotations_z_deg': ROT,
    })

assert len(components) <= 50, len(components)
families = {}
for c in components:
    families.setdefault(c['component_family'], []).append(c)
for fam, items in families.items():
    assert len(items) <= 3 or (
        len(items) <= 5 and all(i['variant_axis'] and i['variant_reason'] for i in items)
    ), (fam, len(items))

plan = {
    'schema': 'sea.scene.component_plan',
    'version': 'v004',
    'status': 'frozen_before_geometry',
    'frozen_date': '2026-10-24',
    'feature_id': 'SEA-ASSET',
    'reference': 'reference.png',
    'reference_sha256': hashlib.sha256(REF.read_bytes()).hexdigest(),
    'reference_license': 'pending_user_reference_rights_review',
    'reference_view': 'isometric diorama, orthographic 35.26 deg elevation, front-left azimuth, white backdrop',
    'dimensions_assumption': {
        'base_platform_m': [5.65, 6.00],
        'deck_top_z_m': 0.95,
        'pier_top_z_m': 0.60,
        'water_drop_m': 1.60,
        'house_block_m': [5.00, 5.60, 4.40],
        'roof_room_m': [2.50, 2.00, 1.50],
        'pavilion_m': [2.80, 2.30, 0.95],
        'roof_pitch_deg': 10.5,
        'note': '参考图无标尺与透视标定；以上为独立美术源米制假设，只服务轮廓与镜头还原，不改变游戏碰撞或正式建筑尺寸。',
    },
    'component_budget': {'limit': 50, 'planned': len(components), 'remaining': 50 - len(components)},
    'palette': {
        'path': 'art_source/shared/palettes/sea_cozy_8x8_512.png',
        'sha256': hashlib.sha256(PALETTE.read_bytes()).hexdigest(),
        'uv_layer': 'PaletteUV',
        'roles': ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission'],
        'policy': '复用既有公共方格色板，只重映射逐面 PaletteUV；不修改共享 PNG，不为单个颜色新增材质。',
    },
    'revision_note': '依用户 2026-10-24 附件新建 v004：双层白墙小屋＋太阳能门廊＋双列栈桥＋黄色渔船的等距模型。v001-v003 与公共色板保持不变，本版不复用旧版几何。制模中把栏杆族拆成实心女儿墙与通透栏杆两个变体，并按屋面退台重排露台进深。',
    'base_version': None,
    'base_source_sha256': None,
    'structural_decisions': {
        'railing_family': '屋檐与二层露台分别需要实心板与通透栏杆，用 infill 变体轴拆两件，不共用同一几何。',
        'level2_terrace': '二层体后退 1.37 米形成连续露台，前排花箱贴栏杆内侧摆，花苞抬高到叶堆之上。',
        'pier_tiling': '栈桥按 1.5 米物理模数铺板与包边，实例只做整组位移与 90° 旋转，不非等比拉伸。',
        'composition': '门廊台面前移，使橙色台面与尖旗遮阳棚在等距视角下探出坡屋面。',
    },
    'acceptance_focus': '高还原轮廓与配色：三角面预算不作为本版约束，优先还原结构、比例与花叶密度。',
    'components': components,
}
D.mkdir(parents=True, exist_ok=True)
(D / 'component_plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n')
print('PLAN_FROZEN', len(components), 'components', len(families), 'families')
print('reference_sha256', plan['reference_sha256'])
