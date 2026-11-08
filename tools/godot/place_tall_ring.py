"""沿矩形四边直线摆放回字型高楼，只新增不删除。

设计（2026-11-08 用户要求「不要环形，沿着边缘直着摆」）
- 两层方框，不是圆环：外框半宽 112 m，内框半宽 72 m，沟宽 40 m。
- 每条边上的楼严格共线（X 或 Z 完全相同），朝向为轴对齐的四向之一（0/90/180/270），
  一律朝框内。不加抖动 —— 「直着」就是直着。
- 靠四条边、留四个直角，形成回字型的两个「口」。
- 楼基取最近地面组件顶面：地面块 24 m 见方，外框边缘离块心最远 12.6 m、
  内框最远 17.0 m，均落在块内，所以每栋都踩在真实街面上。
- 高度按「高峰—低—中—低」节奏轮换，沿直线看是错落的锯齿天际线。
- 不删任何原有实例：位置归用户，重叠处由他手工取舍。

用法：python3 tools/godot/place_tall_ring.py [--dry-run]
"""
import argparse
import json
import math
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LAYOUT = REPO / 'godot/scenes/underwater/sunroom_region/sunken_city_layout.tscn'

OUTER_HALF = 112.0
OUTER_PER_SIDE = 7      # 间距 = 224/6 = 37.3 m
INNER_HALF = 72.0
INNER_PER_SIDE = 5      # 间距 = 144/4 = 36.0 m
SCALE = 2.0
WATER_LOCAL_Y = 51.12 - 43.487442

GROUND_KEYS = {'street_intact', 'street_split', 'junction', 'canal_segment',
               'plaza_tile', 'terrain_ramp'}
GROUND_HALF_DIAGONAL = 24.0 * math.sqrt(2.0) / 2.0 + 0.5

# 每边一排的固定顺序：高峰 → 低 → 中 → 低 → 高峰……锯齿天际线；
# 顺序同时照顾平面尺寸，相邻两栋在行内不互相插入（2× 后宽 28–43 m，间距 36–37 m）。
OUTER_ROW = ['slender_tower', 'terrace_residence', 'tram_tenement', 'rounded_corner',
             'terraced_tower', 'cutaway_tenement', 'balcony_tenement']
# 内框整体退一档，比外框低，从沟底看是内低外高两层楼墙；同样避开宽楼相邻。
INNER_ROW = ['half_tower', 'frame_construction', 'roof_garden_shell',
             'canal_shell', 'canal_housing']


def parse_layout(text):
    ext = {i: p.rsplit('/', 1)[-1].replace('.tscn', '')
           for p, i in re.findall(r'\[ext_resource type="PackedScene" path="res://([^"]+)" id="(c\d+)"\]', text)}
    inst = []
    for b in re.split(r'\n(?=\[node )', text):
        m = re.search(r'\[node name="([^"]+)" parent="([^"]*)"[^\]]*instance=ExtResource\("(c\d+)"\)\]', b)
        if not m:
            continue
        tm = re.search(r'transform = Transform3D\(([^)]*)\)', b)
        v = [float(x) for x in tm.group(1).split(',')] if tm else [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        inst.append({'name': m.group(1), 'ext': m.group(3), 'key': ext.get(m.group(3), '?'),
                     'transform': v, 'block': b})
    return ext, inst


def ground_at(inst, x, z):
    best = None
    for r in inst:
        if r['key'] not in GROUND_KEYS:
            continue
        d = math.hypot(r['transform'][9] - x, r['transform'][11] - z)
        if best is None or d < best[0]:
            best = (d, r['transform'][10])
    return best if best else (0.0, -66.7)


def basis(angle_deg, scale):
    """Godot Transform3D 的 basis 摊平写法；局部 +Z 朝 angle 方向。"""
    a = math.radians(angle_deg)
    c, s = math.cos(a) * scale, math.sin(a) * scale
    return [c, 0.0, -s, 0.0, scale, 0.0, s, 0.0, c]


def fmt(v):
    out = []
    for x in v:
        if abs(x) < 1e-9:
            out.append('0')
        elif abs(x - round(x)) < 1e-9:
            out.append(str(int(round(x))))
        else:
            out.append('%.7g' % x)
    return ', '.join(out)


def edge_slots(half, per_side, ring):
    """沿矩形四条边生成槽位。角落只记一次，朝向取先遇到的那条边。"""
    count = per_side - 1
    step = 2.0 * half / count
    coords = [-half + step * i for i in range(count + 1)]
    slots = []
    seen = set()
    # (轴, 固定值, 朝框内的旋转角)：局部 +Z 指向框内
    sides = [('z', +half, 180.0, 'z+'), ('z', -half, 0.0, 'z-'),
             ('x', +half, -90.0, 'x+'), ('x', -half, 90.0, 'x-')]
    for axis, fixed, rot, side in sides:
        for index_in_side, c in enumerate(coords):
            x, z = (fixed, c) if axis == 'x' else (c, fixed)
            key = (round(x, 3), round(z, 3))
            if key in seen:
                continue
            seen.add(key)
            slots.append({'ring': ring, 'axis': axis, 'x': x, 'z': z, 'rot': rot,
                          'side': side, 'slot': index_in_side})
    return slots


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    text = LAYOUT.read_text(encoding='utf-8')
    # 重跑时先把上一版 tall_ 节点与对应 ext_resource 摘掉，保证结果幂等
    blocks = re.split(r'(?=^\[node )', text, flags=re.M)
    kept = [b for b in blocks
            if not re.match(r'\[node name="tall_', b)]
    text = ''.join(kept)
    text = re.sub(r'^\[ext_resource type="PackedScene" path="res://scenes/components/scenery/sunken_city_tall/[^\n]*\n',
                  '', text, flags=re.M)

    ext, inst = parse_layout(text)

    catalog = json.loads((REPO / 'art_source/scenes/sunken_city/v003/component_catalog.json')
                         .read_text(encoding='utf-8'))['components']
    heights = {c['slug']: c['bounds_size_m'][2] for c in catalog if c['category'] == 'architecture'}

    slots = (edge_slots(OUTER_HALF, OUTER_PER_SIDE, 'outer')
             + edge_slots(INNER_HALF, INNER_PER_SIDE, 'inner'))

    # 每条边沿用同一套行内顺序，但整体轮转一位，四条边的窗洞/楼型不会完全重复
    for s in slots:
        row = OUTER_ROW if s['ring'] == 'outer' else INNER_ROW
        shift = ['z+', 'z-', 'x+', 'x-'].index(s['side'])
        s['key'] = row[(s['slot'] + shift) % len(row)]
        dist, y = ground_at(inst, s['x'], s['z'])
        s['ground_distance'] = dist
        s['ground_ok'] = dist <= GROUND_HALF_DIAGONAL
        s['y'] = y

    new_ext, used, add_ext = {}, set(ext.keys()), []
    n = 0
    for s in slots:
        if s['key'] in new_ext:
            continue
        while ('t%d' % n) in used:
            n += 1
        rid = 't%d' % n
        used.add(rid)
        new_ext[s['key']] = rid
        add_ext.append('[ext_resource type="PackedScene" path="res://scenes/components/scenery/sunken_city_tall/%s.tscn" id="%s"]'
                       % (s['key'], rid))

    nodes = []
    for i, s in enumerate(slots):
        name = 'tall_%s_%02d_%s' % (s['ring'], i, s['key'])
        tf = basis(s['rot'], SCALE) + [s['x'], s['y'], s['z']]
        nodes.append(
            '\n[node name="%s" parent="." instance=ExtResource("%s")]\n'
            'transform = Transform3D(%s)\n'
            'metadata/instance_id = "%s"\n'
            'metadata/urban_role = "canyon_wall_%s"\n'
            'metadata/ring_axis = "edge_%s"\n'
            'metadata/placement_authority = "reference_edge_pending_user_adjust"\n'
            'metadata/source_component_height_m = %.4f\n'
            'metadata/reference_scale = %s\n'
            % (name, new_ext[s['key']], fmt(tf), name, s['ring'], s['axis'],
               heights[s['key']], SCALE))

    marker = text.index('\n\n[node ')
    head, rest = text[:marker], text[marker:]
    new_body = head + '\n' + '\n'.join(add_ext) + rest + ''.join(nodes)

    rows = []
    for i, s in enumerate(slots):
        top = s['y'] + heights[s['key']] * SCALE
        rows.append({'name': 'tall_%s_%02d_%s' % (s['ring'], i, s['key']),
                     'component': s['key'], 'ring': s['ring'], 'edge_axis': s['axis'],
                     'side': s['side'], 'slot': s['slot'],
                     'x': round(s['x'], 3), 'y': round(s['y'], 3), 'z': round(s['z'], 3),
                     'rot_deg': s['rot'], 'height_m': round(heights[s['key']] * SCALE, 2),
                     'top_y': round(top, 2),
                     'above_water_m': round(top - WATER_LOCAL_Y, 2),
                     'ground_distance_m': round(s['ground_distance'], 2),
                     'ground_ok': s['ground_ok']})
    report = {'layout': 'rectangle_edges', 'scale': SCALE,
              'outer_half_m': OUTER_HALF,
              'outer_step_m': round(2.0 * OUTER_HALF / (OUTER_PER_SIDE - 1), 3),
              'inner_half_m': INNER_HALF,
              'inner_step_m': round(2.0 * INNER_HALF / (INNER_PER_SIDE - 1), 3),
              'canyon_width_m': OUTER_HALF - INNER_HALF,
              'added': len(slots), 'removed_existing': 0,
              'water_level_local_y': round(WATER_LOCAL_Y, 4),
              'placements': rows}

    out = REPO.parent / 'sea-work/sunken_seal_20261108/ring_plan.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    if not args.dry_run:
        LAYOUT.write_text(new_body, encoding='utf-8')
        print('LAYOUT_WRITTEN', LAYOUT)

    off = [r for r in rows if not r['ground_ok']]
    print('added %d (outer %d / inner %d); ground_ok %d/%d' % (
        len(rows), sum(1 for r in rows if r['ring'] == 'outer'),
        sum(1 for r in rows if r['ring'] == 'inner'),
        sum(1 for r in rows if r['ground_ok']), len(rows)))
    print('above water: %+.1f .. %+.1f' % (min(r['above_water_m'] for r in rows),
                                           max(r['above_water_m'] for r in rows)))
    if off:
        print('WARN 离地面块过远:', [r['name'] for r in off])


main()
