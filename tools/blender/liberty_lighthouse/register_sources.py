"""Register only the QA-passed Liberty Lighthouse kit; preserve unrelated records."""
from pathlib import Path
import hashlib
import json

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/liberty_lighthouse/v001'
W = R / 'sea-work/liberty_lighthouse'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


qa = json.loads((W / 'verification.json').read_text(encoding='utf-8'))
assert qa['passed'] and qa['source_only']
source = D / 'liberty_lighthouse.blend'
assert qa['source_sha256'] == sha(source), 'Saved assembly changed after verification'
route = json.loads((R / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))['domains']['scenes']
ledger_path = R / route['ledger']
book = json.loads(ledger_path.read_text(encoding='utf-8'))
existing = {a['asset_id']: a for a in book[route['asset_key']]}
catalog = json.loads((D / 'catalog.json').read_text(encoding='utf-8'))['components']
records = []
for component in catalog:
    package = R / component['component_source']
    manifest_path = package.parent / 'asset_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    assert sha(package) == component['source_sha256'] == manifest['source_sha256']
    records.append({
        'asset_id': component['asset_id'],
        'name': component['name'],
        'domain': 'scenes',
        'stage': 'source_verified_runtime_pending',
        'source': component['component_source'],
        'source_sha256': component['source_sha256'],
        'manifest': manifest_path.relative_to(R).as_posix(),
        'version': 'v001',
        'runtime_path': None,
        'prefab': None,
        'license': 'pending_user_reference_rights_review',
        'geometry_fingerprint': component['geometry_fingerprint'],
        'consumer_features': ['SEA-ASSET'],
        'category': component['category'],
        'scope': 'scene_local',
        'note': '巨手灯塔场景组件；母版与独立包重开、逐面 PaletteUV 及关键尺寸通过；Godot 接入、碰撞/导航、商业授权及用户最终美术验收 pending。'
    })
assembly_id = 'SEA-SCENE-LHL-ASSEMBLY'
assembly_manifest = {
    'schema': 'sea.scene.assembly_manifest',
    'asset_id': assembly_id,
    'name': '巨手托举纪念品灯塔',
    'source': source.relative_to(R).as_posix(),
    'source_sha256': qa['source_sha256'],
    'asset_ledger': route['ledger'] + '#' + assembly_id,
    'version': 'v001',
    'category': 'scene_assembly',
    'runtime_status': 'pending',
    'license': 'pending_user_reference_rights_review',
    'component_catalog': 'catalog.json',
    'component_instances': 'component_instances.json',
    'reference': 'reference.png',
    'reference_sha256': qa['reference_sha256'],
    'component_count': len(catalog),
    'instance_count': qa['metrics']['instances'],
    'palette_asset_id': 'SEA-PALETTE-COZY-64',
    'metrics': qa['metrics'],
    'visual_review': {
        'status': 'source_views_reviewed_user_art_acceptance_pending',
        'views': qa['views'],
        'refinements_pending': ['巨手解剖轮廓与握持姿态', '雨棚环绕与招牌空间关系', '窗洞/服务窗真实开洞', '锈蚀层次与灯室透镜可见性']
    }
}
save(D / 'asset_manifest.json', assembly_manifest)
records.append({
    'asset_id': assembly_id,
    'name': assembly_manifest['name'],
    'domain': 'scenes',
    'stage': 'source_verified_runtime_pending',
    'source': assembly_manifest['source'],
    'source_sha256': assembly_manifest['source_sha256'],
    'manifest': (D / 'asset_manifest.json').relative_to(R).as_posix(),
    'version': 'v001',
    'runtime_path': None,
    'prefab': None,
    'license': assembly_manifest['license'],
    'geometry_fingerprint': None,
    'consumer_features': ['SEA-ASSET'],
    'category': 'scene_assembly',
    'scope': 'scene_local',
    'note': '30组件/55实例的独立Blender场景套件；源级检查及四视图目视复核完成，未接入Godot，不替换现有阳光房或其他正式场景。'
})
for record in records:
    if record['asset_id'] in existing:
        assert Path(existing[record['asset_id']]['source']).as_posix() == record['source'], 'AssetID collision: ' + record['asset_id']
ids = {a['asset_id'] for a in records}
book[route['asset_key']] = [a for a in book[route['asset_key']] if a['asset_id'] not in ids] + records
save(ledger_path, book)
index = json.loads((R / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
sources = []
for domain, routing in index['domains'].items():
    for asset in json.loads((R / routing['ledger']).read_text(encoding='utf-8'))[routing['asset_key']]:
        sources.append({key: asset[key] for key in ['asset_id', 'source', 'source_sha256', 'manifest']})
source_index_path = R / 'assets/registry/current_source_index.json'
source_index = json.loads(source_index_path.read_text(encoding='utf-8'))
old_sources = {row['asset_id']: row for row in source_index['sources']}
for row in sources:
    previous = old_sources.get(row['asset_id'])
    if previous is not None and not row['asset_id'].startswith('SEA-SCENE-LHL-'):
        assert previous == row, 'Unrelated source index changed: ' + row['asset_id']
source_index['sources'] = sources
save(source_index_path, source_index)
print(json.dumps({'registered_components': len(catalog), 'registered_assemblies': 1, 'ledger': route['ledger'], 'preserved_unrelated_hashes': True}, ensure_ascii=False))
