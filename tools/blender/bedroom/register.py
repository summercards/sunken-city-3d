"""登记 sea 室内房间 bedroom/v001 的 13 个组件源与运行资源。

只写本套件的行：`assets/registry/ledgers/scenes.json` 的 SEA-SCENE-BDR-001..013、
各自的 `asset_manifest.json`、`assets/registry/current_source_index.json` 与
`assets/registry/runtime_resource_inventory.json`。不动其它资产的哈希。

用法：python3 tools/blender/bedroom/register.py
"""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/rooms/bedroom/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'bedroom/v001'
INDEX = json.loads((ROOT / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
ROUTE = INDEX['domains']['scenes']
BOOK_PATH = ROOT / ROUTE['ledger']

PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
CATALOG = json.loads((D / 'component_catalog.json').read_text(encoding='utf-8'))['components']
EXPORT = json.loads((D / 'export/v001/export_index.json').read_text(encoding='utf-8'))
VERIFY = json.loads((W / 'source_verification.json').read_text(encoding='utf-8'))
assert VERIFY['failures'] == 0, '源级验收未通过，不允许登记'
assert len(CATALOG) == len(PLAN['components']) == 13, '目录与计划不一致'

GLB = {c['key']: c for c in EXPORT['components']}
# 家具在房间里的初版摆放（房间局部坐标，+Z 朝玻璃前厅）。
LAYOUT = {
    'bed': [(-1.86, 0.0, 1.425), 0.0],
    'nightstand': [(-0.95, 0.0, 2.29), 0.0],
    'table_lamp': [(-0.95, 0.50, 2.29), 0.0],
    'rug': [(0.45, 0.0, -0.35), 0.0],
    'shelf': [(2.24, 0.0, 0.15), 90.0],
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, data):
    # 显式 newline='\n'：Path.write_text 在 Windows 上会把 LF 翻成 CRLF，
    # 而仓库里的账本/清单是 LF。翻一次就是「整文件都改了」，审阅时看不出真正的改动。
    with path.open('w', encoding='utf-8', newline='\n') as handle:
        handle.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


records = []
for item in CATALOG:
    key = item['key']
    source = D / 'component_packages' / key / f'{key}.blend'
    assert source.is_file(), source
    manifest_path = source.parent / 'asset_manifest.json'
    aid = item['asset_id']
    glb = GLB[key]
    movable = key == 'bed'
    manifest = {
        'key': key,
        'name': item['name'],
        'asset_id': aid,
        'domain': 'scenes',
        'asset_ledger': ROUTE['ledger'] + '#' + aid,
        'category': item['category'],
        'family': item['family'],
        'building_class': 'above_water',
        'version': 'v001',
        'source': source.relative_to(ROOT).as_posix(),
        'source_sha256': sha(source),
        'collection': item['collection'],
        'origin': item['origin'],
        'origin_note': '房间壳体共用房间坐标系（原点＝室内地面中心，+Z/Blender -Y 朝前厅）；'
                       '家具各自以落地中心为原点，便于整体搬动与旋转。',
        'front_axis': '-Y(Blender) -> +Z(Godot)',
        'bounds_size_m': item['bounds_size_m'],
        'mesh_objects': item['mesh_objects'],
        'triangles': item['triangles'],
        'triangle_budget': item['triangle_budget'],
        'material_roles': item['material_roles'],
        'palette': PLAN['palette'],
        'palette_uv': 'sole UV layer PaletteUV / per-face inset island / 8px safe margin',
        'geometry_fingerprint': item['geometry_fingerprint'],
        'scope': 'room_local',
        'placement_count': 1,
        'collision': 'godot_tscn_owned',
        'blocking_intent': 'actor_blocking_for_furniture_walls_are_collision_free',
        'runtime_glb': glb['glb'],
        'runtime_glb_sha256': glb['glb_sha256'],
        'runtime_component': f'godot/scenes/components/room/{key}.tscn',
        'movable': movable,
        'stage': 'source_and_runtime_verified',
        'runtime_integrated': True,
        'license': 'user_authored_whitebox_no_external_reference',
        'verification': VERIFY['checks'],
        'verification_failures': VERIFY['failures'],
        'note': '室内房间组件；色盘 UV + 三材质角色，无内嵌贴图。灯光/行走面/碰撞归正式 TSCN。',
    }
    save(manifest_path, manifest)
    records.append({
        'asset_id': aid,
        'name': item['name'],
        'category': 'room/' + item['family'],
        'source': manifest['source'],
        'source_sha256': manifest['source_sha256'],
        'manifest': manifest_path.relative_to(ROOT).as_posix(),
        'runtime_path': glb['glb'],
        'runtime_sha256': glb['glb_sha256'],
        'prefab': manifest['runtime_component'],
        'bounds_size_m': item['bounds_size_m'],
        'geometry_fingerprint': item['geometry_fingerprint'],
        'material_roles': item['material_roles'],
        'palette': PLAN['palette'],
        'origin': item['origin'],
        'front_axis': manifest['front_axis'],
        'domain': 'scenes',
        'suite': 'bedroom',
        'scope': 'room_local',
        'version': 'v001',
        'stage': 'source_and_runtime_verified',
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'part',
        'license': manifest['license'],
        'consumer_features': ['SEA-ROOM', 'SEA-ASSET'],
        'movable': movable,
        'room_layout': LAYOUT.get(key),
        'verification': [
            'docs/development/2026-11-05_bedroom_room.md',
        ],
        'triangles': item['triangles'],
        'mesh_objects': item['mesh_objects'],
        'maintenance_status': 'runtime_integrated_verified',
        'note': '室内房间组件（5×5 卧室 + 玻璃前厅 + 可搬运的床）。',
    })

book = json.loads(BOOK_PATH.read_text(encoding='utf-8'))
own = {r['asset_id'] for r in records}
book[ROUTE['asset_key']] = [a for a in book[ROUTE['asset_key']]
                            if a['asset_id'] not in own] + records
save(BOOK_PATH, book)

# 源索引：检查脚本要求它**逐域按账本顺序**整表一致，所以这里直接按
# ledger_index 的域顺序从各分账本重建，而不是往末尾追加 —— 追加会把新行放到
# 其它域（ui/crops/audio）后面，表虽然内容不错、顺序对不上，检查照样失败。
source_index_path = ROOT / 'assets/registry/current_source_index.json'
keys = ['asset_id', 'source', 'source_sha256', 'manifest']
rebuilt = []
for domain, route in INDEX['domains'].items():
    domain_book = json.loads((ROOT / route['ledger']).read_text(encoding='utf-8'))
    for asset in domain_book[route['asset_key']]:
        rebuilt.append({k: asset[k] for k in keys})
save(source_index_path, {'sources': rebuilt})

# 运行资源清单：GLB / 组件 TSCN / 房间 TSCN / 脚本 / 着色器都要有哈希。
inventory_path = ROOT / 'assets/registry/runtime_resource_inventory.json'
inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
by_path = {e['path']: e for e in inventory['resources']}
runtime_rows = []
for item in CATALOG:
    key = item['key']
    runtime_rows.append((GLB[key]['glb'], item['asset_id']))
    runtime_rows.append((f'godot/scenes/components/room/{key}.tscn', item['asset_id']))
runtime_rows.append(('godot/scenes/rooms/bedroom.tscn', 'SEA-SCENE-BDR-000'))
runtime_rows.append(('godot/scenes/main.tscn', None))
# SEA-ROOM 的代码与它改到的既有文件。清单只收「运行时会加载的东西」，
# 测试脚本不收（它们不进导出包）。
# 室内玻璃材质与它的着色器：窗与前厅直接挂在上面，属于运行时会加载的东西。
for path in ['godot/assets/materials/room/room_glass.tres',
             'godot/assets/materials/room/room_porch_glass.tres',
             'godot/src/room/room_cutaway.gd',
             'godot/src/camera/actions/orbit_action.gd',
             'godot/src/camera/actions/zoom_action.gd',
             'godot/shaders/sunny_palette_gloss.gdshader',
             'godot/src/world/sunny_palette_binding.gd',
             'godot/scenes/components/room/wall_window.tscn',
             'godot/scenes/components/room/porch_glass.tscn',
             'godot/src/room/room_controller.gd']:
    runtime_rows.append((path, None))
for path in ['godot/src/room/room_service.gd', 'godot/src/room/room_scene.gd',
             'godot/src/room/room_controller.gd', 'godot/src/room/room_bed.gd',
             'godot/src/room/room_door.gd', 'godot/src/room/room_cutaway.gd',
             'godot/src/bootstrap/main.gd', 'godot/src/ui/hud.gd',
             'godot/src/ui/launcher_icon.gd', 'godot/src/ui/sleep_curtain.gd',
             'godot/src/camera/orbit_camera.gd', 'godot/src/save/save_schema.gd',
             'godot/src/save/save_game.gd', 'godot/src/core/play_scope.gd',
             'godot/scenes/zones/zone1_home_harbor.tscn']:
    runtime_rows.append((path, None))
runtime_rows.append(('godot/assets/textures/shared/sea_cabin_timber_8x8_512.png',
                     'SEA-PALETTE-CABIN-TIMBER-64'))
for path in ['godot/shaders/sunny_palette.gdshader', 'godot/shaders/terrain_placeholder.gdshader']:
    if (ROOT / path).is_file():
        runtime_rows.append((path, None))
for path, aid in runtime_rows:
    full = ROOT / path
    if not full.is_file():
        continue
    row = by_path.get(path)
    if row is None:
        row = {'path': path, 'asset_id': aid}
        inventory['resources'].append(row)
        by_path[path] = row
    digest = sha(full)
    if row.get('sha256') and row['sha256'] != digest:
        row['previous_sha256'] = row['sha256']
    row.update(sha256=digest, bytes=full.stat().st_size,
               note='SEA-ROOM bedroom v001 runtime')
save(inventory_path, inventory)

print(f'Registered {len(records)} bedroom components; '
      f'{len(runtime_rows)} runtime rows checked.')
