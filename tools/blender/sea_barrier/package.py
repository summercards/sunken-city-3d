"""生成 Godot 侧包装：18 个组件 PackedScene + 总装场景，并接到 main.tscn。

不重写任何现有文件：main.tscn 只在 `World/SeaStructures` 下插入一个实例节点和
一条 ext_resource，其余内容逐字节保留。

用法：python3 tools/blender/sea_barrier/package.py
"""
import hashlib
import json
import math
import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/sea_barrier/v001'
GD = ROOT / 'godot'
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf8'))
EXPORT = json.loads((D / 'export/v001/export_manifest.json').read_text(encoding='utf8'))
CATALOG = json.loads((D / 'component_catalog.json').read_text(encoding='utf8'))['components']
BY_KEY = {c['key']: c for c in CATALOG}
EXPORT_BY_KEY = {r['key']: r for r in EXPORT['components']}

HALF = PLAN['ring']['inner_half_extent_m']
DEPTH = PLAN['dimensions']['depth_m']
CORNER_ARM = PLAN['dimensions']['corner_arm_m']

WRAPPER_DIR = 'scenes/components/barrier'
ASSEMBLY = 'scenes/world/sea_barrier.tscn'
ROOT_NAME = 'SeaBarrier'


def fmt(value):
    text = f'{value:.6f}'.rstrip('0').rstrip('.')
    return text if text not in ('-0', '') else '0'


def manual_rects(comp):
    """阻挡矩形，组件本地 XZ。

    直线段：标称矩形（宽度 × 进深），相邻段首尾相接、无缝。
    转角件：只有两条腿。L 形两腿各是 10×10 的方块，转到四个角都对；
    再加一条「对角补块」就会在 NW/SE 两个角指错方向、压进可活动范围。
    """
    width = comp['width_m']
    if comp['kind'] != 'corner_ruin':
        return [(-width / 2, -DEPTH / 2, width, DEPTH)]
    # 转角件原点在围合内角；本地 +z 是圈内方向（Blender -Y），北腿占 x∈[-W,0]/z∈[-W,0]
    return [
        (-CORNER_ARM, -CORNER_ARM, CORNER_ARM, CORNER_ARM),   # 沿 x 的那条腿
        (0, 0, CORNER_ARM, CORNER_ARM),                        # 沿 z 的那条腿
    ]


def rect_literal(values):
    return 'Rect2(' + ', '.join(fmt(v) for v in values) + ')'


def wrapper_text(comp, export):
    key = comp['key']
    rects = ', '.join(rect_literal(r) for r in manual_rects(comp))
    return f'''[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" path="res://assets/models/barrier/{key}/{key}.glb" id="model"]
[ext_resource type="Script" path="res://src/world/sea_barrier_component.gd" id="contract"]
[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]

[node name="{key}" instance=ExtResource("model")]
script = ExtResource("contract")
asset_id = "{comp['asset_id']}"
instance_id = "sea_barrier/{key}"
facility_id = "sea_barrier"
component_kind = "building"
subcategory = "{comp['kind']}"
water_layer = "surface"
water_layer_role = "part"
movable = false
metadata/asset_id = "{comp['asset_id']}"
metadata/asset_version = "v001"
metadata/component_key = "{key}"
metadata/building_class = "above_water"
metadata/blocker_mode = "manual"

[node name="Blockers" type="Node3D" parent="."]
script = ExtResource("blocker")
mode = "manual"
blocks_water = true
cell = 0.5
manual_rects = [{rects}]
'''


def transform_literal(place):
    """plan 的 (x, y) 平面 → Godot (x, 0, -y)；Blender 绕 Z 的角 = Godot 绕 Y 的角。"""
    px, py = place['position']
    theta = math.radians(place['yaw_deg'])
    c, s = math.cos(theta), math.sin(theta)
    # Godot 绕 Y 旋转：x' = x·cos + z·sin, z' = -x·sin + z·cos
    values = [c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c, px, 0.0, -py]
    return 'Transform3D(' + ', '.join(fmt(v) for v in values) + ')'


def assembly_text():
    order = [c['key'] for c in PLAN['components']]
    resources = []
    for index, key in enumerate(order):
        resources.append(f'[ext_resource type="PackedScene" path="res://{WRAPPER_DIR}/{key}.tscn" '
                         f'id="c{index}"]')
    index_of = {key: i for i, key in enumerate(order)}
    nodes = []
    seen = {}
    for item in PLAN['instances']:
        key = item['component']
        seen[key] = seen.get(key, 0) + 1
        node_name = f'{key}_{seen[key]:02d}'
        nodes.append(f'[node name="{node_name}" parent="Visual" instance=ExtResource("c{index_of[key]}")]\n'
                     f'transform = {transform_literal(item)}')
    return f'''[gd_scene load_steps={len(resources) + 2} format=3]

[ext_resource type="Script" path="res://src/world/sea_barrier.gd" id="barrier"]
''' + '\n'.join(resources) + f'''

[node name="{ROOT_NAME}" type="Node3D"]
script = ExtResource("barrier")
asset_id = "SEA-SCENE-SBW-ASSEMBLY"
role = "barrier"
metadata/asset_id = "SEA-SCENE-SBW-ASSEMBLY"
metadata/asset_version = "v001"
metadata/building_class = "above_water"
metadata/segments = {len(PLAN['components'])}

[node name="Visual" type="Node3D" parent="."]

''' + '\n\n'.join(nodes) + '\n'


def patch_main(assembly_rel):
    path = GD / 'scenes/main.tscn'
    text = path.read_text(encoding='utf-8')
    if 'scenes/world/sea_barrier.tscn' in text:
        return 'already'
    anchor = '[node name="neon_garden_quarter" parent="World/SeaStructures"'
    line_start = text.index(anchor)
    line_end = text.index('\n', line_start)
    insert_at = line_end + 1
    ext = ('[ext_resource type="PackedScene" path="res://%s" id="36_barrier"]\n' % assembly_rel)
    # ext_resource 必须插在第一条 [node 之前
    first_node = text.index('[node ')
    text = text[:first_node] + ext + text[first_node:]
    # unique_id 取一个当前未使用的值
    used = {int(x) for x in re.findall(r'unique_id=(\d+)', text)}
    unique = 917300001
    while unique in used:
        unique += 1
    node = (f'[node name="sea_barrier" parent="World/SeaStructures" unique_id={unique} '
            f'instance=ExtResource("36_barrier")]\n')
    anchor2 = '[node name="neon_garden_quarter" parent="World/SeaStructures"'
    line_start = text.index(anchor2)
    line_end = text.index('\n', line_start)
    # 插在 neon_garden 那两行之后（节点行 + transform 行）
    transform_end = text.index('\n', line_end + 1) + 1
    text = text[:transform_end] + node + text[transform_end:]
    path.write_text(text, encoding='utf-8')
    return 'inserted'


MANIFEST = D / 'package_manifest.json'
FORCE = '--force' in sys.argv


def content_sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def write_generated(path, text, recorded):
    """写生成物，但先确认磁盘上的内容仍然等于上次生成的内容。

    这个工程被「整文件重写覆盖手改」坑过两次（2026-11-03 / 11-04 账本）。
    围挡的总装和包装都是生成物，但用户完全可能在编辑器里挪了一段围栏 ——
    无条件重写会把那些改动静默吃掉。所以：磁盘内容一旦和上次生成的哈希不一致，
    就当作「有人手改过」，停下来要求显式 --force，而不是覆盖。
    """
    rel = path.relative_to(ROOT).as_posix()
    new_sha = content_sha(text)
    if path.exists():
        current_sha = content_sha(path.read_text(encoding='utf-8'))
        expected = recorded.get(rel)
        if current_sha != new_sha and current_sha != expected and not FORCE:
            raise SystemExit(
                f'拒绝覆盖手改过的文件：{rel}\n'
                f'  上次生成 {expected or "(无记录)"}\n'
                f'  磁盘当前 {current_sha}\n'
                f'  本次生成 {new_sha}\n'
                '确认要丢弃手改就加 --force；保留手改就改 plan.py 或直接编辑生成脚本。')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')
    return new_sha


previous = json.loads(MANIFEST.read_text(encoding='utf-8')) if MANIFEST.exists() else {}
generated = dict(previous.get('files', {}))

created = []
for comp in PLAN['components']:
    key = comp['key']
    export = EXPORT_BY_KEY[key]
    target = GD / WRAPPER_DIR / f'{key}.tscn'
    generated[target.relative_to(ROOT).as_posix()] = write_generated(
        target, wrapper_text(comp, export), generated)
    created.append(target)

assembly = GD / ASSEMBLY
generated[assembly.relative_to(ROOT).as_posix()] = write_generated(
    assembly, assembly_text(), generated)
status = patch_main(ASSEMBLY)

MANIFEST.write_text(json.dumps({
    'suite': 'sea_barrier', 'version': 'v001',
    'note': '生成物哈希。磁盘内容与之不符 = 有人手改过，package.py 会拒绝覆盖。',
    'files': generated}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('PACKAGED', len(created), 'wrappers +', ASSEMBLY, '| main.tscn:', status)
