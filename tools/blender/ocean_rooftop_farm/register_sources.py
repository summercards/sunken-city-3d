"""Register only the QA-passed ocean rooftop farm; preserve unrelated hashes."""
from pathlib import Path
import hashlib
import json

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

qa = json.loads((W/'verification.json').read_text(encoding='utf-8'))
assert qa['passed'] and qa['source_only']
source = D/'ocean_rooftop_farm.blend'
assert qa['source_sha256'] == sha(source), 'Assembly changed after verification'
route = json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'))['domains']['scenes']
ledger_path = R/route['ledger']
book = json.loads(ledger_path.read_text(encoding='utf-8'))
existing = {a['asset_id']:a for a in book[route['asset_key']]}
catalog = json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
records = []
for component in catalog:
    package = R/component['component_source']
    manifest_path = package.parent/'asset_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    assert sha(package) == component['source_sha256'] == manifest['source_sha256']
    records.append({
        'asset_id':component['asset_id'],
        'name':component['name'],
        'domain':'scenes',
        'stage':'source_verified_runtime_pending',
        'source':component['component_source'],
        'source_sha256':component['source_sha256'],
        'manifest':manifest_path.relative_to(R).as_posix(),
        'version':'v001',
        'runtime_path':None,
        'prefab':None,
        'license':'pending_user_reference_rights_review',
        'geometry_fingerprint':component['geometry_fingerprint'],
        'consumer_features':['SEA-ASSET'],
        'category':component['category'],
        'building_class':'above_water',
        'water_layer':'surface',
        'water_layer_role':'part',
        'scope':'scene_local',
        'note':'八层海上屋顶农场组件；保存重开、独立包、PaletteUV及关键标高通过；空农田、破损地砖与破损建筑细节；Godot/碰撞/导航/商业授权/最终美术验收pending。'
    })
assembly_id = 'SEA-SCENE-ORF-ASSEMBLY'
assembly_manifest = {
    'schema':'sea.scene.assembly_manifest',
    'asset_id':assembly_id,
    'name':'八层海上屋顶农场',
    'source':source.relative_to(R).as_posix(),
    'source_sha256':qa['source_sha256'],
    'asset_ledger':route['ledger']+'#'+assembly_id,
    'version':'v001',
    'category':'scene_assembly',
    'building_class':'above_water',
    'water_layer':'surface',
    'runtime_status':'pending',
    'license':'pending_user_reference_rights_review',
    'component_catalog':'component_catalog.json',
    'component_instances':'component_instances.json',
    'reference':'reference.jpg',
    'reference_sha256':qa['reference_sha256'],
    'component_count':len(catalog),
    'instance_count':qa['metrics']['instances'],
    'palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png',
    'palette_asset_id':'SEA-PALETTE-CABIN-TIMBER-64',
    'metrics':qa['metrics'],
    'excluded':['crops','solar panels','people','animals','ocean/background'],
    'visual_review':{
        'status':'source_views_reviewed_user_art_acceptance_pending',
        'views':qa['views'],
        'refinements_compared':['八层连续立面与屋顶标高','三米大块旧地砖与裂缝/缺角/磨损','墙皮剥落/露筋/破窗/封窗木板/外露管线','空田垄、无作物、无太阳能板']
    }
}
save(D/'asset_manifest.json', assembly_manifest)
records.append({
    'asset_id':assembly_id,
    'name':assembly_manifest['name'],
    'domain':'scenes',
    'stage':'source_verified_runtime_pending',
    'source':assembly_manifest['source'],
    'source_sha256':assembly_manifest['source_sha256'],
    'manifest':(D/'asset_manifest.json').relative_to(R).as_posix(),
    'version':'v001',
    'runtime_path':None,
    'prefab':None,
    'license':assembly_manifest['license'],
    'geometry_fingerprint':None,
    'consumer_features':['SEA-ASSET'],
    'category':'scene_assembly',
    'building_class':'above_water',
    'water_layer':'surface',
    'water_layer_role':'entity',
    'scope':'scene_local',
    'note':f"44组件/{qa['metrics']['instances']}实例、八层楼体的独立Blender场景套件；源级检查及五视图完成；无作物/太阳能板/人物/动物/海洋背景；未接入Godot。"
})
for record in records:
    if record['asset_id'] in existing:
        assert Path(existing[record['asset_id']]['source']).as_posix() == record['source'], 'AssetID collision: '+record['asset_id']
ids = {a['asset_id'] for a in records}
book[route['asset_key']] = [a for a in book[route['asset_key']] if a['asset_id'] not in ids] + records
save(ledger_path, book)
index = json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
sources = []
for domain, routing in index['domains'].items():
    for asset in json.loads((R/routing['ledger']).read_text(encoding='utf-8'))[routing['asset_key']]:
        sources.append({key:asset[key] for key in ['asset_id','source','source_sha256','manifest']})
source_index_path = R/'assets/registry/current_source_index.json'
source_index = json.loads(source_index_path.read_text(encoding='utf-8'))
old_sources = {row['asset_id']:row for row in source_index['sources']}
for row in sources:
    previous = old_sources.get(row['asset_id'])
    if previous is not None and not row['asset_id'].startswith('SEA-SCENE-ORF-'):
        assert previous == row, 'Unrelated source index changed: '+row['asset_id']
source_index['sources'] = sources
save(source_index_path, source_index)
print(json.dumps({'registered_components':len(catalog),'registered_assemblies':1,'ledger':route['ledger'],'preserved_unrelated_hashes':True}, ensure_ascii=False))
