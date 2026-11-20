"""Register the verified Rooftop Arcade source; never change runtime hashes."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FOLDER = ROOT / 'art_source/scenes/rooftop_arcade/v001'
WORK = Path(os.environ.get('SEA_WORK_ROOT') or ROOT.parent / 'sea-work') / 'rooftop_arcade_v001'
AID = 'SEA-SCENE-RAC'
NAMES = ['挂梯','蓝色街机','黄色街机','蓝色雨棚与侧招','陶红砖','浅红砖','深红砖','砖墙承托','晾衣绳','矮茶桌','浮台铺板','落水管','代币价牌','外楼梯','浮台基座','热水罐','吊灯','条纹床','窗帘','阁楼楼板','相框','阁楼前墙','波纹屋盖','卧室货架','阁楼外壳','系泊件','转角石','CRT 维修桌','梯形蓝窗','外墙表箱','纸箱','店门','底层围护','圆凳','百叶风口','店面框','代币柜台','工具板','木电杆','底层货架','风扇']


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def write(path, data):
    text = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    if path.is_file() and b'\r\n' in path.read_bytes():
        text = text.replace('\n', '\r\n')
    if not path.is_file() or path.read_bytes() != text.encode('utf-8'):
        path.write_bytes(text.encode('utf-8'))


def replace_registry_rows(path, key, rows):
    raw = path.read_bytes().decode('utf-8')
    previous = json.loads(raw)
    old = previous[key]
    if old == rows:
        return
    prefix = 0
    while prefix < min(len(old), len(rows)) and old[prefix] == rows[prefix]:
        prefix += 1
    suffix = 0
    while suffix < min(len(old), len(rows)) - prefix and old[-1-suffix] == rows[-1-suffix]:
        suffix += 1
    assert old and len(rows) - suffix > prefix, 'This registration only inserts or replaces rows.'
    decoder = json.JSONDecoder()
    cursor = raw.index('[', raw.index(json.dumps(key))) + 1
    spans = []
    for expected in old:
        cursor += len(raw[cursor:]) - len(raw[cursor:].lstrip())
        value, end = decoder.raw_decode(raw, cursor)
        assert value == expected
        spans.append((cursor, end))
        cursor = end + 1
    nl = '\r\n' if '\r\n' in raw else '\n'
    sep = ',' + nl + '    '
    payload = sep.join(json.dumps(a, ensure_ascii=False, indent=2).replace('\n', nl + '    ') for a in rows[prefix:len(rows)-suffix])
    if prefix == len(old):
        start = stop = spans[-1][1]
        payload = sep + payload
    elif len(old) - suffix == prefix:
        start = stop = spans[prefix][0]
        payload += sep
    else:
        start, stop = spans[prefix][0], spans[len(old)-suffix-1][1]
    updated = raw[:start] + payload + raw[stop:]
    assert json.loads(updated) == {**previous, key: rows}
    path.write_bytes(updated.encode('utf-8'))


def main():
    plan = read(FOLDER / 'component_plan.json')
    report = read(WORK / 'verification.json')
    palette_check = read(WORK / 'validate.json')
    path = FOLDER / 'asset_manifest.json'
    m = read(path)
    assert report['passed'] and palette_check['passed'] and report['source']['sha256'] == m['source_sha256']
    for name in ('hero','front','right','back','shop','loft','plan','dollhouse','utility'):
        assert (WORK / (name+'.png')).is_file()
    route_table = read(ROOT / 'assets/registry/ledger_index.json')['domains']
    route = route_table['scenes']
    book_path = ROOT / route['ledger']
    books = {k: read(ROOT / r['ledger']) for k, r in route_table.items()}
    prior = [a for k, b in books.items() for a in b[route_table[k]['asset_key']]]
    assert len({a['asset_id'] for a in prior}) == len(prior)
    existing = {a['asset_id']: a for a in prior}
    spec = importlib.util.spec_from_file_location('scene_water', ROOT / 'tools/apply_water_layer.py')
    policy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(policy)
    key = route['asset_key']
    roles = sorted({mat for c in m['components'] for mat in c['materials']})
    assert len(NAMES) == len(m['components']) == 41
    labels = dict(zip(sorted(c['asset_key'] for c in m['components']), NAMES))
    entries = []
    manifests = {}
    for aid, name, category, saved, props, manifest_path in [
        (AID, plan['display_name'], 'building_assembly', m['source'], {'material_roles': roles, 'component_count': 41, 'instance_count': m['assembly']['static_instance_count']}, path),
        *((c['asset_id'], labels[c['asset_key']], 'structure' if c['asset_key'] in plan['components']['architecture'] else 'furnishing', c['component_blend'], {'material_roles': c['materials'], 'bounds': c['bounds'], 'asset_key': c['asset_key']}, FOLDER / 'components' / (c['asset_key']+'.manifest.json')) for c in m['components']),
    ]:
        assert aid not in existing or existing[aid].get('suite') == plan['suite']
        assert digest(ROOT / saved['path']) == saved['sha256']
        layer, role = policy.classify(aid)
        asset = {'asset_id':aid, 'name':name, 'suite':plan['suite'], 'domain':'scenes', 'category':category, 'category_label':{'building_assembly':'建筑总成','structure':'建筑结构','furnishing':'固定设施'}[category], 'scope':'scene_local', 'classification':{'category':'building','subcategory':category}, 'building_class':policy.classify_building(aid), 'water_layer':layer, 'water_layer_role':role, 'version':plan['version'], 'source':saved['path'], 'source_sha256':saved['sha256'], 'manifest':rel(manifest_path), 'palette':plan['palette'], 'palette_sha256':report['palette']['sha256'], 'front_axis':'-Y', 'origin':'bottom_center', 'runtime_path':None, 'prefab':None, 'license_status':'pending', 'consumer_features':['SEA-ASSET'], 'stage':'source_verified_runtime_pending', **props}
        assert asset['building_class'] == 'above_water'
        entries.append(asset)
        manifests[manifest_path] = {**(m if aid==AID else {}), **asset, 'asset_ledger':route['ledger']+'#'+aid, 'visual_acceptance':'user_review_pending', 'saved_package_reopen':'passed', 'source_verification':'palette_uv_and_saved_source_reopen_passed'}
        if aid==AID:
            # The detailed asset manifest uses rich file records; retain both.
            manifests[manifest_path]['source'] = m['source']
            manifests[manifest_path]['palette'] = report['palette']
    target_ids = {a['asset_id'] for a in entries}
    books['scenes'][key] = [a for a in books['scenes'][key] if a['asset_id'] not in target_ids] + entries
    for file, content in manifests.items():
        write(file, content)
    replace_registry_rows(book_path, key, books['scenes'][key])
    index_path = ROOT / 'assets/registry/current_source_index.json'
    projected = [{k:a[k] for k in ('asset_id','source','source_sha256','manifest')} for d,b in books.items() for a in b[route_table[d]['asset_key']]]
    replace_registry_rows(index_path, 'sources', projected)
    for cls, view in policy.building_views(books['scenes'][key],route['ledger']).items():
        replace_registry_rows(ROOT / route['building_views'][cls], 'asset_ids', view['asset_ids'])
    print(f'RAC: {len(entries)} source rows; runtime unchanged')


if __name__ == '__main__':
    main()
