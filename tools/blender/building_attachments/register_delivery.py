#!/usr/bin/env python3
"""外挂静态库定点登记；先完整预检，再无覆盖发布，旧账本行按原字节保留。"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
AUDIT = ROOT.parent / "sea-work/building_attachments_release"
LIBRARY = Path("/Users/zyq/Library/Application Support/sea-verification/20261116-052700-attachments-v2-support-r9c-a4e161/build-attachment-library/building_attachments/library/v002")
DEST = ROOT / "godot/scenes/components/facilities/building_attachments/v002"
DERIVED = ROOT / "art_source/scenes/building_attachments/v002/source/derived_manifest.json"
STATES = ("fresh", "damaged", "ruined")
STAGE = "authoring_library_integrated_art_review_pending_not_world_installed"
INDEX = ROOT / "assets/registry/ledger_index.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def logical(value):
    return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())


def load(path):
    return json.loads(path.read_bytes())


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def file_row(path, relative=None):
    data = path.read_bytes()
    return {"path": relative or str(path), "sha256": sha(data), "bytes": len(data)}


def new_file(path, data):
    assert path.parent.is_dir(), path.parent
    with path.open("xb") as stream:
        stream.write(data)


def array_spans(data, key):
    text = data.decode("utf-8")
    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*\[', text)
    assert match, key
    pos = match.end()
    decoder = json.JSONDecoder()
    result = []
    while True:
        while text[pos].isspace() or text[pos] == ',':
            pos += 1
        if text[pos] == ']':
            return text, result, pos
        start = pos
        value, pos = decoder.raw_decode(text, pos)
        result.append((start, pos, value))


def splice(data, key, replacements=None, additions=(), insert_at=None):
    text, spans, end = array_spans(data, key)
    edits = []
    for start, stop, row in spans:
        if replacements and row.get("path") in replacements:
            edits.append((start, stop, json.dumps(replacements[row['path']], ensure_ascii=False)))
    if additions:
        lines = ",\n    ".join(json.dumps(row, ensure_ascii=False) for row in additions)
        if insert_at is None or insert_at == len(spans):
            pos = spans[-1][1] if spans else end
            value = (",\n    " if spans else "\n    ") + lines
        else:
            pos = spans[insert_at][0]
            value = lines + ",\n    "
        edits.append((pos, pos, value))
    for start, stop, value in sorted(edits, reverse=True):
        text = text[:start] + value + text[stop:]
    return text.encode()


def protected_snapshot():
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split('\0')
    paths = {p for p in tracked if p and (p.startswith(("godot/src/", "godot/addons/", "godot/tests/", "scripts/", "docs/")) or p in ("GDD_V1.0.md", "godot/project.godot", "godot/scenes/main.tscn"))}
    for directory in ("godot/src/building_attachments", "godot/data/building_attachments", "art_source/scenes/building_attachments", "godot/addons/scene_assembly"):
        paths.update(str(p.relative_to(ROOT)) for p in (ROOT / directory).rglob('*') if p.is_file())
    paths.update(str(p.relative_to(ROOT)) for p in (ROOT / 'godot/tests').glob('test_building_attachments*.gd'))
    return {p: file_row(ROOT / p, p) for p in sorted(paths) if (ROOT / p).is_file()}


def prepare():
    assert AUDIT.parent.is_dir() and AUDIT.parent.resolve() == AUDIT.parent, "审计父目录未验证"
    assert not AUDIT.exists(), "审计目录已存在，禁止覆盖"
    assert DEST.parents[1].is_dir(), "正式库最近父目录不存在"
    assert not DEST.parent.exists(), "目标外挂目录已存在，拒绝任何覆盖"
    index = load(INDEX)
    route = index['domains']['scenes']
    scene_path = ROOT / route['ledger']
    runtime_path = ROOT / index['runtime_inventory']
    checker = (ROOT / 'scripts/check_feature_contracts.py').read_text()
    source_match = re.search(r"ROOT / '(assets/registry/[^']+)'\)\.read_text\(\)\)\['sources'\]", checker)
    assert source_match, "必须由校验器确认派生来源索引路径"
    source_path = ROOT / source_match.group(1)
    books = [load(ROOT / r['ledger'])[r['asset_key']] for r in index['domains'].values()]
    all_ids = [a['asset_id'] for book in books for a in book]
    assert len(all_ids) == len(set(all_ids)), "既有全库AssetID重复"
    scenes = load(scene_path)[route['asset_key']]
    sources = load(source_path)['sources']
    projected = [{k: a[k] for k in ('asset_id', 'source', 'source_sha256', 'manifest')} for book in books for a in book]
    assert projected == sources, "既有source index已漂移，禁止替其它行同步"
    assert 'furnishing' in {a.get('category') for a in scenes}
    assert '固定细节' in (ROOT / 'assets/registry/SCENE_COMPONENTS.md').read_text()
    assert "('furnishing','02_固定设施')" in (ROOT / 'tools/blender/bld_20261109_a/build.py').read_text()
    original = LIBRARY / 'library_manifest.json'
    library = load(original)
    derived = load(DERIVED)
    catalog_path = ROOT / 'godot/data/building_attachments/catalog_v1.json'
    catalog = load(catalog_path)
    entries = catalog['entries']
    assert len(entries) == len(derived['packages']) == library['type_count'] == 32
    assert len(library['records']) == library['variant_count'] == 96
    assert sha(original.read_bytes()) == derived['native_manifest']['sha256']
    assert library['summary']['totals']['triangles'] == 45376
    assert len(catalog['materials']) == 4
    packages = {p['type_id']: p for p in derived['packages']}
    records = {(p['type_id'], p['condition']): p for p in library['records']}
    assert len(records) == 96
    assert set(packages) == {e['type_id'] for e in entries}
    provenance = []
    source_mismatch = []
    for source in library['source']['files']:
        relative = source['path'].removeprefix('res://')
        snapshot = Path(derived['native_project']) / relative
        row = file_row(snapshot)
        assert row['sha256'] == source['sha256'], snapshot
        current = file_row(ROOT / 'godot' / relative, 'godot/' + relative)
        provenance.append({'snapshot': row, 'library_sha256': source['sha256'], 'current': current})
        if current['sha256'] != row['sha256']:
            source_mismatch.append(relative)
    assert source_mismatch == ['src/building_attachments/store.gd'], source_mismatch
    assert provenance[-2]['current']['sha256'] == '45b5ad000e236da369ea995ccbe789afc05b94206f3c4ae7bc503a25c710afda'
    copies = [file_row(original, 'library_manifest.json')]
    new_assets, source_rows, delivery_records, registration_files = [], [], [], {}
    runtime_additions = []
    for entry in entries:
        type_id = entry['type_id']
        aid = 'SEA-SCENE-BAT-' + type_id.upper().replace('_', '-')
        assert aid not in all_ids
        package = packages[type_id]
        assert package['name'] == entry['name']
        blend = Path(package['blend'])
        assert blend.is_relative_to(ROOT / 'art_source/scenes/building_attachments/v002/components')
        blend_row = file_row(blend, str(blend.relative_to(ROOT)))
        assert blend_row['sha256'] == package['blend_sha256']
        variants = {}
        for state in STATES:
            record = records[(type_id, state)]
            derived_state = next(s for s in package['states'] if s['condition'] == state)
            variant = {'condition': state, 'damage_description': entry['damage'][state], 'mount_anchor': record['mount_anchor'], 'stats': record['stats'], 'material_roles': derived_state['material_roles']}
            assert record['damage_description'] == entry['damage'][state]
            for kind, suffix in (('scene', '.tscn'), ('native_geometry', '.native.json'), ('recipe', '.recipe.json')):
                relative = f'{type_id}/{state}{suffix}'
                source = LIBRARY / relative
                assert record[kind] == 'user://building_attachments/library/v002/' + relative
                row = file_row(source, relative)
                assert row['sha256'] == record['sha256'][kind], relative
                copies.append(row)
                target = DEST / relative
                variant[kind] = {**row, 'path': str(target.relative_to(ROOT)), 'resource_path': 'res://' + str(target.relative_to(ROOT / 'godot'))}
                runtime_additions.append({**file_row(source, str(target.relative_to(ROOT))), 'asset_id': aid, 'owner': 'SEA-ASSET', 'status': STAGE, 'resource_role': {'scene': 'static_packed_scene', 'native_geometry': 'authoring_native_snapshot_data', 'recipe': 'authoring_recipe_data'}[kind], 'condition': state, 'runtime_world_installed': False})
            native = load(LIBRARY / f'{type_id}/{state}.native.json')
            recipe = load(LIBRARY / f'{type_id}/{state}.recipe.json')
            assert recipe['type_id'] == type_id and recipe['condition'] == state
            assert native['provenance'] == catalog['source']
            roles = [m['material_role'] for m in native['meshes']]
            assert roles == derived_state['material_roles']
            triangles = sum(len(m['indices']) // 3 for m in native['meshes'])
            assert triangles == record['stats']['triangles'] == derived_state['triangles']
            text = (LIBRARY / f'{type_id}/{state}.tscn').read_text()
            assert 'type="Script"' not in text and '\nscript =' not in text
            assert not re.search(r'cast_shadow = (?:0|2|3)', text)
            for ref in re.findall(r'path="res://([^"]+)"', text):
                assert (ROOT / 'godot' / ref).is_file(), ref
            layers = re.findall(r'^collision_layer = (\d+)', text, re.M)
            assert all(layer == '256' for layer in layers)
            glb = Path(derived_state['glb'])
            exchange = file_row(glb, str(glb.relative_to(ROOT)))
            assert exchange['sha256'] == derived_state['glb_sha256']
            variant['visual_exchange'] = {**exchange, 'purpose': 'visual_exchange_only_not_runtime'}
            variants[state] = variant
            delivery_records.append({'type_id': type_id, 'name': entry['name'], 'asset_id': aid, **variant})
        registration = DEST / type_id / 'registration_manifest.json'
        registration_value = {'schema': 'sea.building_attachments.registration.v1', 'asset_id': aid, 'asset_ledger': route['ledger'] + '#' + aid, 'source_manifest': str(DERIVED.relative_to(ROOT)), 'source_manifest_sha256': sha(DERIVED.read_bytes()), 'delivery_manifest': str((DEST / 'delivery_manifest.json').relative_to(ROOT)), 'library_manifest_sha256': sha(original.read_bytes()), 'source': blend_row, 'stage': STAGE, 'runtime_world_installed': False}
        registration_files[str(registration.relative_to(DEST))] = registration_value
        asset = {'asset_id': aid, 'name': entry['name'], 'label': entry['name'], 'type_id': type_id, 'domain': 'scenes', 'category': 'furnishing', 'category_label': '固定设施', 'classification': {'category': 'furnishing', 'subcategory': 'building_attachments'}, 'catalog_category': entry['category'], 'stage': STAGE, 'version': 'v002', 'source_version': 'v002', 'source': blend_row['path'], 'source_path': blend_row['path'], 'source_sha256': blend_row['sha256'], 'source_blend': blend_row, 'source_kind': 'derived_native_snapshot', 'source_manifest': str(DERIVED.relative_to(ROOT)), 'source_manifest_sha256': sha(DERIVED.read_bytes()), 'manifest': str(registration.relative_to(ROOT)), 'original_native_sources': provenance, 'catalog': file_row(catalog_path, str(catalog_path.relative_to(ROOT))), 'runtime_path': variants['fresh']['scene']['path'], 'prefab': variants['fresh']['scene']['resource_path'], 'runtime_scene': {s: variants[s]['scene'] for s in STATES}, 'default_condition': 'fresh', 'variants': variants, 'delivery_manifest': str((DEST / 'delivery_manifest.json').relative_to(ROOT)), 'building_class': None, 'water_layer': 'none', 'water_layer_role': 'none', 'usage_profiles': {'available': catalog['usages'], 'building_responsibility': '由挂载consumer决定，不是独立建筑', 'decorative_underwater': {'collision_allowed': False, 'world_derivation': False}}, 'collision': {'optional': True, 'catalog_default': entry['collision_default'], 'layer': 256, 'navigation_obstacle': False, 'dive_auto_registration': False, 'world_space_derivation': False}, 'runtime_world_installed': False, 'production_loading': 'Generator按catalog构建；不自动读取静态库', 'provenance': 'project_original_no_external_mesh', 'external_mesh_reuse': False, 'license': 'pending_provenance_review', 'commercial_legal_review': 'pending', 'art_review': 'pending', 'consumer_features': ['SEA-ASSET', 'SEA-WORLD']}
        new_assets.append(asset)
        source_rows.append({k: asset[k] for k in ('asset_id', 'source', 'source_sha256', 'manifest')})
    assert len(copies) == 289 and len({r['path'] for r in copies}) == 289
    assert {str(p.relative_to(LIBRARY)) for p in LIBRARY.rglob('*') if p.is_file()} == {r['path'] for r in copies}
    code = sorted((ROOT / 'godot/src/building_attachments').glob('*.gd'))
    assert len(code) == 11
    owners = {str(p.relative_to(ROOT)): 'SEA-ASSET' for p in code}
    owners.update({'godot/data/building_attachments/catalog_v1.json': 'SEA-ASSET', 'godot/tools/build_attachment_library.gd': 'SEA-QUALITY', 'scripts/run_verification.py': 'SEA-QUALITY'})
    for name in ('attachment_controller', 'attachment_gallery', 'attachment_panel', 'attachment_surface', 'plugin', 'drop_surface', 'thumbnail'):
        owners[f'godot/addons/scene_assembly/{name}.gd'] = 'SEA-WORLD'
    for name in ('test_building_attachments', 'test_building_attachments_editor', 'test_building_attachments_visual'):
        owners[f'godot/tests/{name}.gd'] = 'SEA-ASSET'
    old_test = 'godot/tests/test_scene_assembly_editor.gd'
    diff = subprocess.check_output(['git', 'diff', '--', old_test], cwd=ROOT).decode()
    assert '_show_attachment_page(false)' in diff, '旧装配测试与本轮关联未确认'
    owners[old_test] = 'SEA-WORLD'
    assert len(owners) == 25
    runtime = load(runtime_path)['resources']
    old_runtime = {r['path']: r for r in runtime}
    assert len(old_runtime) == len(runtime)
    replacements = {}
    for path, owner in owners.items():
        row = dict(old_runtime.get(path, {}))
        row.update(file_row(ROOT / path, path))
        row.update({'asset_id': None, 'owner': owner})
        if path not in old_runtime:
            row['status'] = 'runtime_hash_recorded_20261116'
        row['audit_note'] = row.get('audit_note', '') + ' 本轮仅登记外挂当前字节，未运行Godot；不签世界安装、美术或商业授权。'
        if path in old_runtime:
            replacements[path] = row
        else:
            runtime_additions.append(row)
    before = {str(p.relative_to(ROOT)): p.read_bytes() for p in (scene_path, source_path, runtime_path)}
    outputs = {str(scene_path.relative_to(ROOT)): splice(before[str(scene_path.relative_to(ROOT))], route['asset_key'], additions=new_assets), str(source_path.relative_to(ROOT)): splice(before[str(source_path.relative_to(ROOT))], 'sources', additions=source_rows, insert_at=len(scenes)), str(runtime_path.relative_to(ROOT)): splice(before[str(runtime_path.relative_to(ROOT))], 'resources', replacements=replacements, additions=runtime_additions)}
    targets = sorted(owners) + [r['path'] for r in runtime_additions if r['path'] not in owners]
    assert len(targets) == 313
    delivery = {'schema': 'sea.building_attachments.delivery.v1', 'version': 'v002', 'stage': STAGE, 'paths_relative_to': 'delivery_manifest_directory', 'original_library_manifest': copies[0], 'original_manifest_preserved_byte_for_byte': True, 'original_user_paths_are_historical_not_delivery_paths': True, 'files': copies, 'records': delivery_records, 'frozen_native_sources': provenance, 'current_store_is_not_library_input': True, 'runtime_world_installed': False, 'production_loading': 'Generator按catalog构建，不自动读取本静态库', 'counts': {'types': 32, 'states': 96, 'scene': 96, 'native_geometry': 96, 'recipe': 96, 'triangles': 45376, 'shared_materials': 4}, 'license': 'pending_provenance_review', 'commercial_legal_review': 'pending', 'art_review': 'pending'}
    for record in delivery_records:
        for kind in ('scene', 'native_geometry', 'recipe'):
            record[kind] = {**record[kind], 'path': f"{record['type_id']}/{record['condition']}" + {'scene': '.tscn', 'native_geometry': '.native.json', 'recipe': '.recipe.json'}[kind]}
    pending = ['主线程执行Godot正式导入与静态库独立加载finaltest', '用户美术终审、完整contact/style审查', '商业与来源权益审核pending', '未装配到Main或正式世界', 'tools/apply_water_layer.py未登记SEA-SCENE-BAT家族（本轮无修改权限）', '原derived_manifest保持原字节及historical pending；逐件回链位于独立registration_manifest']
    protected = protected_snapshot()
    AUDIT.mkdir()
    for number, (path, data) in enumerate(before.items()):
        new_file(AUDIT / f'before_{number}.json', data)
        new_file(AUDIT / f'proposed_{number}.json', outputs[path])
    plan = {'schema': 'sea.building_attachments.registration_audit.v1', 'parent_verified': str(AUDIT.parent), 'registry_paths': list(before), 'registry_before': {p: {'sha256': sha(b), 'bytes': len(b)} for p, b in before.items()}, 'copies': copies, 'registration_files': registration_files, 'delivery': delivery, 'targets': targets, 'existing_runtime_targets': sorted(replacements), 'record_ids': [a['asset_id'] for a in new_assets], 'protected': protected, 'counts_before': {'scenes': len(scenes), 'sources': len(sources), 'runtime': len(runtime)}, 'counts_after': {'scenes': len(scenes) + 32, 'sources': len(sources) + 32, 'runtime': len(runtime) + len(runtime_additions)}, 'pending': pending, 'godot_run': False, 'category_basis': {'token': 'furnishing', 'label': '固定设施', 'enum_validator_present': False, 'references': ['assets/registry/SCENE_COMPONENTS.md:5', 'tools/blender/bld_20261109_a/build.py:30']}}
    new_file(AUDIT / 'plan.json', encoded(plan))
    return {'prepared': True, 'counts_before': plan['counts_before'], 'counts_after': plan['counts_after'], 'target_runtime_paths': len(targets), 'audit': str(AUDIT)}


def apply():
    plan = load(AUDIT / 'plan.json')
    assert not (AUDIT / 'audit.json').exists(), '已应用，禁止重复运行'
    assert protected_snapshot() == plan['protected'], '受保护输入在预检后发生变化'
    for path, row in plan['registry_before'].items():
        assert sha((ROOT / path).read_bytes()) == row['sha256'], path
    assert not DEST.parent.exists()
    for row in plan['copies']:
        assert file_row(LIBRARY / row['path'], row['path']) == row
        assert not (DEST / row['path']).exists()
    # 同文件系统临时目录完整组装成功后才发布，预检失败不产生正式目标。
    parent = DEST.parents[1]
    staging = Path(tempfile.mkdtemp(prefix='.building_attachments_release_', dir=AUDIT))
    version = staging / 'v002'
    version.mkdir()
    for row in plan['copies']:
        target = version / row['path']
        if not target.parent.exists():
            assert target.parent.parent == version
            target.parent.mkdir()
        new_file(target, (LIBRARY / row['path']).read_bytes())
        assert file_row(target, row['path']) == row
    for relative, value in plan['registration_files'].items():
        new_file(version / relative, encoded(value))
    new_file(version / 'delivery_manifest.json', encoded(plan['delivery']))
    assert os.stat(AUDIT).st_dev == os.stat(parent).st_dev
    os.rename(staging, DEST.parent)
    for number, relative in enumerate(plan['registry_paths']):
        path = ROOT / relative
        assert sha(path.read_bytes()) == plan['registry_before'][relative]['sha256']
        proposed = (AUDIT / f'proposed_{number}.json').read_bytes()
        # 仅应用预检生成的数组插入及指定path行替换，不重新序列化旧行。
        path.write_bytes(proposed)
    return verify()


def verify():
    plan = load(AUDIT / 'plan.json')
    preservation = {}
    for number, relative in enumerate(plan['registry_paths']):
        key = ('assets', 'sources', 'resources')[number]
        before = (AUDIT / f'before_{number}.json').read_bytes()
        after = (ROOT / relative).read_bytes()
        _, b_spans, _ = array_spans(before, key)
        _, a_spans, _ = array_spans(after, key)
        id_key = 'path' if key == 'resources' else 'asset_id'
        b_rows = {r[id_key]: r for _, _, r in b_spans}
        a_rows = {r[id_key]: r for _, _, r in a_spans}
        selected = set(plan['existing_runtime_targets']) if key == 'resources' else set()
        b_text, a_text = before.decode(), after.decode()
        b_raw = {r[id_key]: b_text[s:e] for s, e, r in b_spans}
        a_raw = {r[id_key]: a_text[s:e] for s, e, r in a_spans}
        unaffected = [p for p in b_rows if p not in selected]
        raw_changed = [p for p in unaffected if b_raw[p] != a_raw.get(p)]
        logical_changed = [p for p in unaffected if b_rows[p] != a_rows.get(p)]
        b_top, a_top = load(AUDIT / f'before_{number}.json'), load(ROOT / relative)
        b_top.pop(key); a_top.pop(key)
        assert b_top == a_top
        assert not raw_changed and not logical_changed
        preservation[relative] = {'old_rows': len(b_rows), 'unaffected_rows': len(unaffected), 'raw_affected_non_target_rows': len(raw_changed), 'logical_affected_non_target_rows': len(logical_changed), 'logical_digest_before': logical([b_rows[p] for p in unaffected]), 'logical_digest_after': logical([a_rows[p] for p in unaffected]), 'raw_digest_before': sha('\n'.join(b_raw[p] for p in unaffected).encode()), 'raw_digest_after': sha('\n'.join(a_raw[p] for p in unaffected).encode()), 'top_level_unchanged': True, 'old_status_changes': sum(b_rows[p].get('status') != a_rows[p].get('status') for p in b_rows)}
    copy_mismatches = [r['path'] for r in plan['copies'] if file_row(DEST / r['path'], r['path']) != r]
    assert not copy_mismatches
    current_protected = protected_snapshot()
    locked_diff = [p for p, row in plan['protected'].items() if current_protected.get(p) != row]
    assert not locked_diff
    index = load(INDEX)
    all_assets = [a for route in index['domains'].values() for a in load(ROOT / route['ledger'])[route['asset_key']]]
    assert len(all_assets) == len({a['asset_id'] for a in all_assets})
    projected = [{k: a[k] for k in ('asset_id', 'source', 'source_sha256', 'manifest')} for a in all_assets]
    assert projected == load(ROOT / plan['registry_paths'][1])['sources']
    resources = load(ROOT / plan['registry_paths'][2])['resources']
    by_path = {r['path']: r for r in resources}
    assert len(resources) == plan['counts_after']['runtime'] == len(by_path)
    assert len(load(ROOT / plan['registry_paths'][0])['assets']) == plan['counts_after']['scenes']
    mismatches = [p for p in plan['targets'] if file_row(ROOT / p, p)['sha256'] != by_path[p]['sha256'] or (ROOT / p).stat().st_size != by_path[p]['bytes']]
    assert not mismatches
    registered = [a for a in all_assets if a['asset_id'] in plan['record_ids']]
    assert len(registered) == 32
    manifest_links = 0
    for asset in registered:
        assert asset['runtime_world_installed'] is False and asset['building_class'] is None
        assert sha((ROOT / asset['source']).read_bytes()) == asset['source_sha256']
        assert load(ROOT / asset['manifest'])['asset_ledger'] == index['domains']['scenes']['ledger'] + '#' + asset['asset_id']
        manifest_links += 1
        for state in STATES:
            assert by_path[asset['runtime_scene'][state]['path']]['asset_id'] == asset['asset_id']
    spec = importlib.util.spec_from_file_location('attachment_water_rules', ROOT / 'tools/apply_water_layer.py')
    rules = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rules)
    unknown = []
    for asset in registered:
        try:
            rules.classify(asset['asset_id'])
        except KeyError:
            unknown.append(asset['asset_id'])
    result = {'passed_scoped_static_checks': True, 'godot_run': False, 'full_contract_check_run': False, 'copy_count': len(plan['copies']), 'copy_hash_mismatch_count': len(copy_mismatches), 'current_core_locked_file_count': len(plan['protected']), 'current_core_locked_diff_count': len(locked_diff), 'new_source_count': 32, 'new_asset_record_count': 32, 'new_runtime_scene_count': 96, 'native_json_count': 96, 'recipe_count': 96, 'registered_runtime_target_count': len(plan['targets']), 'target_runtime_hash_mismatch_count': len(mismatches), 'manifest_backlink_count': manifest_links, 'source_index_matches_all_ledgers': True, 'asset_ids_globally_unique': True, 'counts_before': plan['counts_before'], 'counts_after': plan['counts_after'], 'record_ids': plan['record_ids'], 'runtime_paths': plan['targets'], 'preservation': preservation, 'unknown_water_family_count': len(unknown), 'pending': plan['pending'], 'original_library_manifest': file_row(DEST / 'library_manifest.json'), 'geometry_triangle_sum': sum(r['stats']['triangles'] for r in load(DEST / 'library_manifest.json')['records']), 'delivery_file_count': sum(p.is_file() for p in DEST.rglob('*'))}
    output = AUDIT / 'audit.json'
    if output.exists():
        assert load(output) == result, '既有audit与本次复核结果不一致'
    else:
        new_file(output, encoded(result))
    return {k: v for k, v in result.items() if k not in ('runtime_paths', 'preservation', 'record_ids')}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('prepare', 'apply', 'verify'))
    args = parser.parse_args()
    print(json.dumps({'prepare': prepare, 'apply': apply, 'verify': verify}[args.mode](), ensure_ascii=False, indent=2))
