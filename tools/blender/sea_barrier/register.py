"""登记 sea 家园外围残楼围挡（v001）的源级资产行。

本轮只做到 Blender 白盒源：不导出 GLB、不改任何正式 TSCN、不登记 runtime 资源。
因此 stage 一律 source_verified_runtime_pending，船阻挡与岸线仍是「几何前提成立、
运行未接」。只写本套件自己的行，不动其他资产的哈希。

用法：python3 tools/blender/sea_barrier/register.py
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/sea_barrier/v001'
INDEX = json.loads((ROOT / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
ROUTE = INDEX['domains']['scenes']
BOOK_PATH = ROOT / ROUTE['ledger']

PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
CATALOG = json.loads((D / 'component_catalog.json').read_text(encoding='utf-8'))['components']
VERIFY = json.loads((Path(__import__('os').environ.get(
    'SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'sea_barrier/v001/source_verification.json'
    ).read_text(encoding='utf-8'))
assert VERIFY['failures'] == 0, '源级验收未通过，不允许登记'
assert len(CATALOG) == len(PLAN['components']), '目录与计划不一致'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


records = []
plan_by_key = {c['key']: c for c in PLAN['components']}
for item in CATALOG:
    key = item['key']
    plan = plan_by_key[key]
    source = D / 'component_packages' / key / f'{key}.blend'
    assert source.is_file(), source
    manifest_path = source.parent / 'asset_manifest.json'
    aid = item['asset_id']
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
        'origin': 'waterline_center',
        'origin_note': '构件半沉，原点取水线中心；底部在水下约 2.8 米。',
        'front_axis': '-Y',
        'bounds_size_m': item['bounds_size_m'],
        'mesh_objects': item['mesh_objects'],
        'triangles': item['triangles'],
        'triangle_budget': plan['triangle_budget'],
        'material_roles': ['SEA_Matte'],
        'palette': PLAN['palette'],
        'palette_uv': 'sole UV layer PaletteUV / per-face inset island / 8px safe margin',
        # 指纹由 build.py 在建模时算出并写进目录；这里只做搬运，不重算，
        # 免得「登记脚本自己算一个」和「成品几何」各说各话。
        'geometry_fingerprint': item['geometry_fingerprint'],
        'scope': 'scene_local',
        'placement_count': len(plan['placements']),
        'collision': 'facility_projection_pending',
        'blocking_intent': 'boat_blocking_required_at_runtime',
        'stage': 'source_verified_runtime_pending',
        'runtime_integrated': False,
        'license': 'user_authored_whitebox_no_external_reference',
        'verification': VERIFY['checks'],
        'verification_failures': VERIFY['failures'],
        'note': '白盒阶段：只有体量、倾斜、开口与窗洞，未做倒角细则与贴图细节。',
    }
    save(manifest_path, manifest)
    records.append({
        'asset_id': aid,
        'name': item['name'],
        'category': 'barrier_whitebox/' + item['kind'],
        'source': manifest['source'],
        'source_sha256': manifest['source_sha256'],
        'manifest': manifest_path.relative_to(ROOT).as_posix(),
        'bounds_size_m': item['bounds_size_m'],
        'geometry_fingerprint': manifest['geometry_fingerprint'],
        'material_roles': ['SEA_Matte'],
        'palette': PLAN['palette'],
        'origin': 'waterline_center',
        'front_axis': '-Y',
        'loaded_branch': '.agents/skills/sea-scene-component-authoring/references/above-water.md',
        'domain': 'scenes',
        'suite': 'sea_barrier',
        'scope': 'scene_local',
        'version': 'v001',
        'stage': 'source_verified_runtime_pending',
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'part',
        'license': manifest['license'],
        'consumer_features': ['SEA-ASSET'],
        'verification': [
            'docs/development/2026-11-05_sea_barrier_whitebox.md',
        ],
        'triangles': item['triangles'],
        'mesh_objects': item['mesh_objects'],
        'maintenance_status': 'source_verified_runtime_pending',
        'note': '围挡白盒组件；船阻挡按几何派生，运行接入与专项验证 pending。',
    })

book = json.loads(BOOK_PATH.read_text(encoding='utf-8'))
own = {r['asset_id'] for r in records}
book[ROUTE['asset_key']] = [a for a in book[ROUTE['asset_key']] if a['asset_id'] not in own] + records
save(BOOK_PATH, book)

# 运行资源哈希：GLB / 包装 / 材质 / 脚本 / 总装。只登记本套件自己的文件，
# 不碰别人正在改的哈希 —— 刷新全表会把未知改动一起接受。
def norm_sha(path):
    data = Path(path).read_bytes()
    return hashlib.sha256(data.replace(b'\r\n', b'\n')).hexdigest()

runtime_rows = []
for glb in sorted((ROOT / 'godot/assets/models/barrier').glob('*/*.glb')):
    runtime_rows.append({'path': glb.relative_to(ROOT).as_posix(), 'bytes': glb.stat().st_size,
                         'sha256': norm_sha(glb), 'asset_id': None,
                         'status': 'runtime_component_verified',
                         'note': 'SEA-ASSET-R47 sea_barrier whitebox GLB'})
for rel in ['godot/assets/materials/barrier/matte.tres',
            'godot/scenes/world/sea_barrier.tscn',
            'godot/src/world/sea_barrier.gd',
            'godot/src/world/sea_barrier_component.gd',
            'godot/tests/test_sea_barrier.gd',
            'godot/tools/capture_sea_barrier.gd']:
    path = ROOT / rel
    runtime_rows.append({'path': rel, 'bytes': path.stat().st_size, 'sha256': norm_sha(path),
                         'asset_id': None, 'status': 'runtime_resource_verified',
                         'note': 'SEA-ASSET-R47 sea_barrier contract'})
for wrapper in sorted((ROOT / 'godot/scenes/components/barrier').glob('*.tscn')):
    runtime_rows.append({'path': wrapper.relative_to(ROOT).as_posix(),
                         'bytes': wrapper.stat().st_size, 'sha256': norm_sha(wrapper),
                         'asset_id': None, 'status': 'runtime_component_verified',
                         'note': 'SEA-ASSET-R47 sea_barrier wrapper'})
inventory_path = ROOT / INDEX['runtime_inventory']
inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
fresh = {row['path']: row for row in runtime_rows}
inventory['resources'] = ([fresh.pop(r['path'], r) for r in inventory['resources']]
                          + list(fresh.values()))
save(inventory_path, inventory)

sources = []
for domain, route in INDEX['domains'].items():
    for row in json.loads((ROOT / route['ledger']).read_text(encoding='utf-8'))[route['asset_key']]:
        sources.append({k: row[k] for k in ['asset_id', 'source', 'source_sha256', 'manifest']})
index_path = ROOT / 'assets/registry/current_source_index.json'
data = json.loads(index_path.read_text(encoding='utf-8'))
data['sources'] = sources
save(index_path, data)
print('REGISTERED', len(records), 'source rows;', len(runtime_rows), 'runtime rows')
