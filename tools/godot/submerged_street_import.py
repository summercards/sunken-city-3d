"""Import submerged_street v001 into Godot: palette materials, per-building prefabs, main.tscn placement.

Design rules this script follows (all learned from this project's own failures):
  * 颜色必须是预制体里序列化的 surface_material_override —— 不靠 @tool 脚本运行期上色，
    否则编辑器里重新实例化就会退回 GLB 的灰底（2026-10-29 六栋变白就是这么来的）。
  * 每个 surface 的材质角色按**导入后网格自带的 glTF 材质名**决定，不按手写顺序猜；
    GLB 重新导出改变 primitive 顺序时，这里会和 verify 一起报错，而不是悄悄换色。
  * 摆放由 main.tscn 拥有；源里的实例清单只是参考排布，本脚本只做一次整体偏移，
    不改建筑物之间的相对关系（测试会核对相对关系）。
  * 纯观赏：Blockers mode=none、无碰撞、无交互、无岸线。

Run: python -X utf8 tools/godot/submerged_street_import.py
"""
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'art_source/scenes/submerged_street/v001'
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
GLB_ROOT = ROOT / 'godot/assets/models/scenery/submerged_street'
PREFAB_DIR = ROOT / 'godot/scenes/decorations/underwater/street/buildings'
MAT_DIR = ROOT / 'godot/assets/materials/submerged_street'
MAIN = ROOT / 'godot/scenes/main.tscn'
PALETTE = 'res://assets/textures/shared/sea_cabin_muted_8x8_512.png'
GROUP = 'UnderwaterStreet'
# 街面整体偏移。约束有四条，全部量过：
#   1) 不压 Zone2 横滨站（x -40.4..-19.6, z -27.5..-8.5）与 Zone1 家园（x -25.6..15.3）；
#   2) 不压现有六栋水下景观（x >= -21.5）；
#   3) 全部落在相机 pan_bounds（x/z -77..77）内 —— 否则玩家永远摇不到那一片；
#   4) 十栋整体西移 + 南移，落在阳光房西南的开阔水域。
# 47.4 米宽的街区塞不进"西侧剩余 32 米"，所以主位移给到 Z。
OFFSET_X = -9.0
OFFSET_Z = 45.0
# 高度怎么定：**按屋顶对齐水面**，不是按地面齐平。
# 现有六栋水下景观就是这么摆的（包围盒顶面 -1.1 到 -3.7，底面 -18.7 到 -30.1）——
# 每栋顶部贴在水面下方，底座随自身高度落到不同深度，看上去才是一片「沉在水下的楼」。
# 如果反过来让十栋底面齐平（y=-28.2），除了 28.8 米的高层，其余 3.6–16.5 米的楼顶面都在
# 水下 11–21 米，隔着十几米深的水根本看不见 —— 本轮真实渲染里只剩一栋，就是这么暴露的。
# 所以：屋顶落点固定，底板高度 = 屋顶落点 - 该栋实测高度。
WATER_Y = 1.12          # main.tscn 水面标高（实测）
TOP_CLEARANCE = 1.45    # 屋顶落在水面下方这么多：与现有六栋同一带，且满足 0.25 米净空
TOP_Y = WATER_Y - TOP_CLEARANCE
ROLES = ('matte', 'metal', 'gloss')
ROLE_MATERIAL = {
    'matte': 'res://assets/materials/submerged_street/matte.tres',
    'metal': 'res://assets/materials/submerged_street/metal.tres',
    'gloss': 'res://assets/materials/submerged_street/gloss.tres',
}


def glb_roles(path: Path):
    """导入后每个 surface 的材质角色：按 glTF material 名读，不靠顺序假设。"""
    data = path.read_bytes()
    jlen = int.from_bytes(data[12:16], 'little')
    gl = json.loads(data[20:20 + jlen])
    roots = gl['scenes'][gl.get('scene', 0)]['nodes']
    mesh_nodes = [gl['nodes'][i].get('name', '') for i in roots]
    names = [m.get('name', '') for m in gl.get('materials', [])]
    roles = []
    for mesh in gl['meshes']:
        for prim in mesh['primitives']:
            name = names[prim['material']] if 'material' in prim else ''
            role = name.replace('SEA_', '').strip().lower()
            assert role in ROLES, '%s: unexpected material role %r' % (path.name, name)
            roles.append(role)
    assert len(mesh_nodes) == 1, '%s: expected one scene root, got %r' % (path.name, mesh_nodes)
    return roles, mesh_nodes[0]


def write_material(name: str, resource: str, metallic: float, roughness: float, clearcoat: float, note: str):
    body = '\n'.join([
        '[gd_resource type="StandardMaterial3D" format=3]',
        '',
        '[ext_resource type="Texture2D" path="%s" id="palette"]' % PALETTE,
        '',
        '[resource]',
        'resource_name = "%s"' % resource,
        'albedo_texture = ExtResource("palette")',
        # 0 = Nearest：色板是 8x8 纯色格，任何插值都会串色。
        'texture_filter = 0',
        'metallic = %.2f' % metallic,
        'roughness = %.2f' % roughness,
    ])
    if clearcoat > 0:
        body += '\nclearcoat_enabled = true\nclearcoat = %.2f' % clearcoat
    body += '\n'  # 每个 .tres 以换行结尾
    path = MAT_DIR / (name + '.tres')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding='utf-8')
    return path


def building_height(key: str) -> float:
    """从 catalog 读该栋真实包络高度（不是计划里的名义尺寸）。"""
    catalog = json.loads((D / 'catalog.json').read_text(encoding='utf-8'))['components']
    row = next(r for r in catalog if r['key'] == key)
    return row['bounds_max'][2] - row['bounds_min'][2]


def main():
    # ---------- 1. 三档材质角色（与源里 SEA_Matte / SEA_Metal / SEA_Gloss 对应）
    mats = {
        'matte': write_material('matte', 'SEA_Matte_SubmergedStreet', 0.0, 0.74, 0.0, 'muted palette'),
        'metal': write_material('metal', 'SEA_Metal_SubmergedStreet', 0.86, 0.27, 0.0, 'muted palette'),
        'gloss': write_material('gloss', 'SEA_Gloss_SubmergedStreet', 0.18, 0.12, 0.62, 'muted palette'),
    }

    # ---------- 2. 逐栋预制体
    PREFAB_DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for item in PLAN['components']:
        key = item['key']
        glb = GLB_ROOT / key / (key + '.glb')
        assert glb.is_file(), 'missing GLB: ' + str(glb)
        roles, mesh_node = glb_roles(glb)
        lines = ['[gd_scene format=3]', '',
                 '[ext_resource type="Script" path="res://src/world/submerged_street_building.gd" id="contract"]',
                 '[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]',
                 '[ext_resource type="PackedScene" path="res://%s" id="model"]'
                 % glb.relative_to(ROOT / 'godot').as_posix()]
        used = sorted(set(roles), key=ROLES.index)
        for role in used:
            lines.append('[ext_resource type="Material" path="%s" id="%s"]' % (ROLE_MATERIAL[role], role))
        lines += ['', '[node name="%s" type="Node3D"]' % item['name'],
                  'script = ExtResource("contract")',
                  'asset_id = "%s"' % item['asset_id'],
                  'component_kind = "decoration"',
                  'subcategory = "underwater_buildings"',
                  'movable = false',
                  'metadata/asset_id = "%s"' % item['asset_id'],
                  'metadata/triangle_budget = %d' % item['triangle_budget'],
                  'metadata/source_suite = "submerged_street"',
                  'water_layer = "submerged"',
                  'water_layer_role = "entity"',
                  '[node name="Visual" parent="." instance=ExtResource("model")]',
                  # 覆盖必须落在真正的 MeshInstance3D 上：写成「可编辑子节点」再由它持有
                  # surface_material_override。直接写在 Visual（Node3D）上时，单 surface 的旧楼
                  # 恰好能被引擎的占位重映射救回来，但 2~3 个 surface 就整组失效 —— 本轮实测过。
                  '[node name="%s" parent="Visual" index="0"]' % mesh_node]
        for index, role in enumerate(roles):
            lines.append('surface_material_override/%d = ExtResource("%s")' % (index, role))
        lines += ['[node name="Blockers" type="Node3D" parent="."]',
                  'script = ExtResource("blocker")',
                  'mode = "none"',
                  'blocks_water = false', '']
        path = PREFAB_DIR / (key + '.tscn')
        path.write_bytes('\n'.join(lines).encode('utf-8'))
        rows.append(dict(key=key, name=item['name'], asset_id=item['asset_id'],
                         height=building_height(key),
                         prefab=path.relative_to(ROOT).as_posix(),
                         mesh_node=mesh_node,
                         prefab_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                         runtime_path=glb.relative_to(ROOT).as_posix(),
                         roles=roles, triangle_budget=item['triangle_budget'],
                         placement=item['placement_godot'], rotation_y_degrees=item['rotation_y_degrees']))

    # ---------- 3. main.tscn：按「块」替换整组，不碰其他节点
    # 不用正则跨块删除：上一版非贪婪删除只吃掉了组头，留下 10 个没有父级的孤儿，
    # Godot 实例化时逐个报 "parent has vanished"。这里按节点块整体过滤。
    text = MAIN.read_text(encoding='utf-8')
    kept = []
    drop = False
    for line in text.split('\n'):
        if line.startswith('['):
            header = line.startswith('[node ')
            ours = header and ('name="%s"' % GROUP in line or 'parent="World/%s"' % GROUP in line)
            drop = ours or (line.startswith('[ext_resource') and 'street_' in line and 'id="street_' in line)
        if not drop:
            kept.append(line)
    lines = kept

    last_ext = max(i for i, line in enumerate(lines) if line.startswith('[ext_resource'))
    new_ext = ['[ext_resource type="PackedScene" path="res://%s" id="street_%s"]'
               % (row['prefab'].split('/', 1)[1], row['key']) for row in rows]
    lines[last_ext + 1:last_ext + 1] = new_ext

    def f(value: float) -> str:
        return '0' if abs(value) < 5e-7 else ('%.6f' % value)

    anchor = next(i for i, line in enumerate(lines) if line.startswith('[node name="SeaStructures"'))
    unique = 1920000001
    block = ['[node name="%s" type="Node3D" parent="World" unique_id=%d]' % (GROUP, unique),
             'metadata/owner = "main.tscn 独占摆位；art_source 的实例清单只作参考"',
             'metadata/source_suite = "submerged_street"']
    unique += 1
    for row in rows:
        x = row['placement'][0] + OFFSET_X
        z = row['placement'][2] + OFFSET_Z
        y = round(TOP_Y - row['height'], 3)
        c, s = math.cos(math.radians(float(row['rotation_y_degrees']))), math.sin(math.radians(float(row['rotation_y_degrees'])))
        # Transform3D 序列化顺序＝basis 三列再 origin；绕 Y 旋转的三列是 (c,0,-s) / (0,1,0) / (s,0,c)
        block += ['[node name="%s" parent="World/%s" unique_id=%d instance=ExtResource("street_%s")]'
                  % (row['key'], GROUP, unique, row['key']),
                  'transform = Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, %s, %s)'
                  % (f(c), f(-s), f(s), f(c), f(x), f(y), f(z)),
                  'instance_id = "home_street/%s"' % row['key']]
        unique += 1
    lines[anchor:anchor] = block
    MAIN.write_text('\n'.join(lines), encoding='utf-8')

    manifest = dict(
        schema='sea.godot_import', kit='submerged_street', version='v001',
        owner_scene='godot/scenes/main.tscn#World/' + GROUP,
        group=GROUP,
        group_offset={'x': OFFSET_X, 'z': OFFSET_Z},
        top_alignment={'water_y': WATER_Y, 'target_roof_y': TOP_Y,
                       'rule': '每栋屋顶落在水面下方 1.45 米；底板高度 = 屋顶落点 - 该栋实测高度'},
        reason=('十栋整体西移 9 米、南移 45 米，避开 Zone2 横滨站与 Zone1 家园、避开现有六栋水下景观。'
                '高度按屋顶对齐水面：每栋屋脊落在水面 y=1.12 下方 1.45 米，底板随高度下沉，'
                '与现有六栋同一带（它们的顶面在 -1.1 到 -3.7）。'),
        materials={role: path.relative_to(ROOT).as_posix() for role, path in mats.items()},
        palette=PALETTE,
        components=rows,
    )
    out = D / 'godot_import.json'
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('IMPORT_PLAN', len(rows), 'prefabs ->', PREFAB_DIR.relative_to(ROOT))
    for row in rows:
        print('  %-24s %-38s roles=%s' % (row['key'], row['prefab'].split('/')[-1], ','.join(row['roles'])))


if __name__ == '__main__':
    main()
