"""冻结 sea 家园外围残楼围挡的组件计划（先计划后几何）。

计划里同时算出围合摆位，并断言四边 150 米被严丝合缝铺满；建模脚本只消费这里的结果，
不自己再推一遍坐标，避免计划与成品漂移。
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SUITE = ROOT / 'art_source/scenes/sea_barrier/v001'
PALETTE = ROOT / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'

HALF = 120.0         # 可活动范围 240 x 240，边界在 +-120
# 2026-11-05 三次口径：150 → 90 → 240。最后一次按用户红框截图反推：
# 红框 854x698 px，用「围挡 110 米外接」与「霓虹花园 x=156」两点校准得 0.33 米/px，
# 红框约 282 米宽、右界落在 x≈+150（霓虹花园恰好在框外），故取 240 米见方。
CORNER_ARM = 10.0    # 转角件沿每边各占 10 米（L 形两条腿）
DEPTH = 10.0         # 围挡进深，全部落在边界外侧
MODULE_W = 20.0
SIDES = ['north', 'east', 'south', 'west']
# 每边 11 个 20 米件 = 220 米，加两端转角腿 20 米正好 240，不需要收口件。
MODULE_COUNT = 11
KIND_CYCLE = ['house_pair', 'forest_band', 'single_house']
# 四条边的起点错开，绕一圈不会看到四段一样的排列。
KIND_OFFSET = {'north': 0, 'east': 1, 'south': 2, 'west': 1}
SIDE_CN = {'north': '北', 'east': '东', 'south': '南', 'west': '西'}
KIND_CN = {'house_pair': '双塌房', 'single_house': '斜塌楼', 'forest_band': '半沉林带',
           'filler': '收口残墙', 'corner_ruin': '转角残楼'}
YAW = {'north': 0.0, 'east': -90.0, 'south': 180.0, 'west': 90.0}

COMPONENTS = []


def add(key, name, family, width, kind, seed, placements):
    COMPONENTS.append({
        'key': key,
        'name': name,
        'asset_id': f'SEA-SCENE-SBW-{len(COMPONENTS) + 1:03d}',
        'category': 'architecture',
        'family': family,
        'building_class': 'above_water',
        'origin': 'waterline_center',
        'front_axis': '-Y',
        'triangle_budget': 18000 if kind == 'corner_ruin' else 12000,
        'collection': f'SBW_{len(COMPONENTS) + 1:02d}_{name}',
        'scope': 'scene_local',
        'kind': kind,
        'width_m': width,
        'depth_m': DEPTH,
        'seed': seed,
        'placements': placements,
    })


# 1. 转角件：两条母版，各管一对对角。四个角如果共用一条母版，转 90 度后形状完全一样，
#    站在圈内一眼就能看出是复制粘贴；拆成两条只是换随机种子，成本为零。
add('corner_ruin_a', '转角残楼A（L形20米）', 'corner_ruin', CORNER_ARM, 'corner_ruin', 20261105, [
    {'position': [HALF, HALF], 'yaw_deg': 0.0},
    {'position': [-HALF, -HALF], 'yaw_deg': 180.0},
])
add('corner_ruin_b', '转角残楼B（L形20米）', 'corner_ruin', CORNER_ARM, 'corner_ruin', 20270713, [
    {'position': [-HALF, HALF], 'yaw_deg': 90.0},
    {'position': [HALF, -HALF], 'yaw_deg': 270.0},
])

# 2. 直段：每边 3 个 20 米件 + 1 个 10 米收口件，10 + 60 + 10 + 10 = 90 米。
#    240 米每边 = 转角腿 10 + 11×20 米件 + 转角腿 10，整除，不需要收口件。
for side in SIDES:
    lo_edge, hi_edge = -HALF + CORNER_ARM, HALF - CORNER_ARM
    cursor = lo_edge
    pieces = []
    for _ in range(MODULE_COUNT):
        pieces.append((cursor, cursor + MODULE_W))
        cursor += MODULE_W
    assert abs(cursor - hi_edge) < 1e-9, f'{side}: 直段没有铺到转角'
    offset = KIND_OFFSET[side]
    kinds = [KIND_CYCLE[(offset + i) % len(KIND_CYCLE)] for i in range(MODULE_COUNT)]
    for index, ((piece_lo, piece_hi), kind) in enumerate(zip(pieces, kinds), start=1):
        width = round(piece_hi - piece_lo, 3)
        mid = (piece_lo + piece_hi) / 2
        if side == 'north':
            pos = [mid, HALF + DEPTH / 2]
        elif side == 'south':
            pos = [mid, -(HALF + DEPTH / 2)]
        elif side == 'east':
            pos = [HALF + DEPTH / 2, mid]
        else:
            pos = [-(HALF + DEPTH / 2), mid]
        add(f'{side}_{index:02d}',
            f'{SIDE_CN[side]}{index:02d}·{KIND_CN[kind]}（{width:g}米）',
            kind, width, kind, 20261105 + len(COMPONENTS) * 37,
            [{'position': pos, 'yaw_deg': YAW[side]}])

# 3. 铺满断言：每边 = 转角腿 10 + 直段合计 220 + 转角腿 10 = 240。
for side in SIDES:
    covered = sum(c['width_m'] for c in COMPONENTS
                  if c['kind'] != 'corner_ruin'
                  and c['placements'][0]['yaw_deg'] == YAW[side])
    assert abs(covered - (2 * HALF - 2 * CORNER_ARM)) < 1e-6, (side, covered)

instances = [{'component': comp['key'], 'position': place['position'],
              'yaw_deg': place['yaw_deg'], 'scale': 1.0}
             for comp in COMPONENTS for place in comp['placements']]

plan = {
    'schema': 'sea.component_plan',
    'suite': 'sea_barrier',
    'version': 'v001',
    'feature_id': 'SEA-ASSET',
    'requirement': 'SEA-ASSET-R47',
    'status': 'frozen_before_geometry',
    'building_class': 'above_water',
    'branch': '.agents/skills/sea-scene-component-authoring/references/above-water.md',
    'reference': None,
    'reference_note': '用户口述：白盒残楼围挡，破坏房屋+倾斜+树林；范围 150 改成 90，'
                      '当天再按红框截图改为 240x240',
    'palette': 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png',
    'palette_sha256': hashlib.sha256(PALETTE.read_bytes()).hexdigest(),
    'dimensions': {
        'module_width_m': MODULE_W,
        'depth_m': DEPTH,
        'corner_arm_m': CORNER_ARM,
        'waterline_local_z': 0.0,
        'submerged_base_local_z': -2.8,
        'house_storey_m': 3.0,
        'wall_thickness_m': 0.3,
        'window_m': [1.0, 1.2],
    },
    'ring': {
        'shape': 'square',
        'center': [0.0, 0.0],
        'inner_half_extent_m': HALF,
        'side_length_m': 2 * HALF,
        'placement': 'inner_face_on_boundary_outward',
        'instances': len(instances),
        'coverage_assert': '转角腿 10 + 11*20 + 转角腿 10 = 240 per side',
    },
    'exceptions': [
        '白盒阶段：只做体量、倾斜、开口与窗洞，开孔边缘为直角，倒角只落在体块外轮廓。',
        '同族超过 3 件：用户明确要求「每 20 米一个独立组件、不许合并」，按显式例外登记；'
        '套件总数 29 件仍在 50 件上限内。',
        '原点取水线中心而非底部中心：构件半沉，底部在水下 2.8 米，用水线做原点才不随水深漂移。',
        '植被随各组件走，尚未抽成跨套件共享母版。',
    ],
    'components': COMPONENTS,
    'instances': instances,
}
SUITE.mkdir(parents=True, exist_ok=True)
(SUITE / 'component_plan.json').write_text(
    json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print('PLAN', len(COMPONENTS), 'components', len(instances), 'instances')
for side in SIDES:
    straight = sum(c['width_m'] for c in COMPONENTS
                   if c['kind'] != 'corner_ruin'
                   and c['placements'][0]['yaw_deg'] == YAW[side])
    legs = sum(c['width_m'] for c in COMPONENTS if c['kind'] == 'corner_ruin')
    # 每条边两头各压着一条 10 米的转角腿，所以 130 直段 + 20 转角 = 150
    print(' ', side, '直段', straight, '+ 转角腿 2x10 =',
          straight + legs)
