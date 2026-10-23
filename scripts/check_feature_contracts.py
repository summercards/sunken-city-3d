#!/usr/bin/env python3
"""Validate master -> independent feature spec/ledger -> implementation/evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
STATUS = {'planned': '规划中', 'partial': '部分实现', 'implemented': '已实现待完整验收',
          'verified': '已验收', 'blocked': '受阻'}


def ledger_meta(text):
    match = re.search(r'```json\n(.*?)\n```', text, re.S)
    if not match:
        raise ValueError('ledger has no JSON registration header')
    return json.loads(match.group(1))


def parse_master(text):
    block = text.split('<!-- FEATURE_CONTROL_BEGIN -->')[1].split('<!-- FEATURE_CONTROL_END -->')[0]
    rows = []
    for line in block.splitlines():
        if not re.match(r'\| <a id=', line):
            continue
        cells = [x.strip() for x in line.strip('|').split('|')]
        if len(cells) != 7:
            raise ValueError('invalid master feature row: ' + line)
        fid = re.search(r'</a>(SEA-[A-Z0-9-]+)', cells[0]).group(1)
        paths = [re.search(r'\]\(([^)]+)\)', cells[i]).group(1) for i in [4, 5]]
        rows.append({'feature_id': fid, 'name': cells[1], 'group': cells[2],
                     'dependencies': re.findall(r'SEA-[A-Z0-9-]+', cells[3]),
                     'spec': paths[0], 'ledger': paths[1], 'summary': cells[6], 'line': line})
    return rows


def graph_errors(rows):
    errors = []
    ids = [r['feature_id'] for r in rows]
    if len(ids) != len(set(ids)):
        errors.append('duplicate FeatureID')
    graph = {r['feature_id']: r['dependencies'] for r in rows}
    for fid, deps in graph.items():
        for dep in deps:
            if dep not in graph:
                errors.append(fid + ': unknown dependency ' + dep)
    visiting, done = set(), set()
    def walk(fid):
        if fid in visiting:
            errors.append('dependency cycle at ' + fid)
            return
        if fid in done or fid not in graph:
            return
        visiting.add(fid)
        for dep in graph[fid]: walk(dep)
        visiting.remove(fid)
        done.add(fid)
    for fid in graph: walk(fid)
    return errors


def check(sync=False):
    issues = []
    def require(ok, message):
        if not ok: issues.append(message)
    master_path = ROOT / 'GDD_V1.0.md'
    master = master_path.read_text()
    rows = parse_master(master)
    require(bool(rows), 'master has no features')
    issues.extend(graph_errors(rows))
    specs, ledgers = set(), set()
    projected = []
    verify_source = (ROOT / 'scripts/run_verification.py').read_text()
    for row in rows:
        fid = row['feature_id']
        specs.add(row['spec']); ledgers.add(row['ledger'])
        for key in ['spec', 'ledger']:
            require((ROOT / row[key]).is_file(), fid + ': missing ' + key)
        if not all((ROOT / row[k]).is_file() for k in ['spec', 'ledger']): continue
        spec = (ROOT / row['spec']).read_text()
        ledger = (ROOT / row['ledger']).read_text()
        try: meta = ledger_meta(ledger)
        except (ValueError, json.JSONDecodeError) as exc:
            issues.append(fid + ': ' + str(exc)); continue
        require(meta.get('feature_id') == fid, fid + ': ledger identity mismatch')
        require(meta.get('status') in STATUS, fid + ': invalid status')
        require(bool(meta.get('owner')), fid + ': no owner')
        backlink = 'GDD_V1.0.md#' + fid.lower()
        require(backlink in spec and backlink in ledger, fid + ': missing master backlink')
        requirements = set(re.findall(r'\| (' + re.escape(fid) + r'-R\d+) \|', spec))
        covered = set(re.findall(r'\| (' + re.escape(fid) + r'-R\d+) \|', ledger))
        require(bool(requirements) and requirements == covered, fid + ': missing or extra requirement ledger rows')
        for path in meta.get('code_paths', []):
            require((ROOT / path).exists(), fid + ': missing implementation ' + path)
        for test in meta.get('verification', []):
            require(test == 'structure' or "'" + test + "':" in verify_source, fid + ': unknown verification ' + test)
        expected = STATUS.get(meta.get('status'), '?')
        if row['summary'] != expected:
            if sync:
                parts = row['line'].rsplit('|', 2)
                master = master.replace(row['line'], parts[0] + '| ' + expected + ' |')
            else: issues.append(fid + ': master status differs from ledger; use --sync')
        projected.append({k: v for k, v in row.items() if k not in ['line', 'summary']} | meta)
    require(len(specs) == len(rows) and len(ledgers) == len(rows), 'features share a spec or ledger')
    actual_specs = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'docs/features').glob('*/spec.md')}
    actual_ledgers = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'docs/features').glob('*/ledger.md')}
    require(specs == actual_specs and ledgers == actual_ledgers, 'orphan/missing feature files')
    # Link existence on the current control surface, excluding archived originals.
    doc_paths = [master_path, ROOT / 'README.md', ROOT / 'docs/README.md']
    doc_paths += [ROOT / x for x in specs | ledgers]
    for p in doc_paths:
        for target in re.findall(r'\]\(([^)]+)\)', p.read_text()):
            if target.startswith(('https:', 'http:', '#', 'mailto:')): continue
            filepart = target.split('#')[0]
            if filepart: require((p.parent / filepart).exists(), str(p.relative_to(ROOT)) + ': broken link ' + target)
    # Production rule modules must stay usable without singleton or scene access.
    for name in ['farming/farm.gd', 'orders/orders.gd']:
        path = ROOT / 'godot/src' / name
        code = '\n'.join(l for l in path.read_text().splitlines() if not l.lstrip().startswith('#'))
        require(not re.search(r'\b(?:Economy|GameState|Zones)\.|get_parent\(|get_node\(', code), name + ': forbidden global/scene dependency')
    migration = json.loads((ROOT / 'docs/development/2026-10-23_path_migration.json').read_text())
    for old, new in migration['paths'].items():
        require(not (ROOT / old).exists() and (ROOT / new).exists(), 'path migration incomplete: ' + old)
    # Resource references (literal full paths; dynamic format strings are checked by runtime suites).
    for p in list((ROOT / 'godot/src').rglob('*.gd')) + list((ROOT / 'godot/scenes').rglob('*.tscn')) + [ROOT / 'godot/project.godot']:
        for ref in re.findall(r'["\'](?:\*)?res://([^"\']+)["\']', p.read_text()):
            if '%' in ref or '{' in ref or ref.endswith('/'): continue
            if ref.startswith('outputs/'): continue
            require((ROOT / 'godot' / ref).exists(), str(p.relative_to(ROOT)) + ': missing resource ' + ref)
    index = json.loads((ROOT / 'assets/registry/ledger_index.json').read_text())
    asset_ids, source_rows = set(), []
    for domain, route in index['domains'].items():
        book = json.loads((ROOT / route['ledger']).read_text())
        for asset in book[route['asset_key']]:
            aid = asset['asset_id']
            require(aid not in asset_ids, 'duplicate AssetID ' + aid); asset_ids.add(aid)
            require(asset['domain'] == domain, aid + ': wrong domain')
            source = ROOT / asset['source']
            require(source.is_file(), aid + ': missing source')
            if source.is_file(): require(hashlib.sha256(source.read_bytes()).hexdigest() == asset['source_sha256'], aid + ': source hash drift')
            manifest = json.loads((ROOT / asset['manifest']).read_text())
            require(manifest['asset_ledger'] == route['ledger'] + '#' + aid, aid + ': manifest ledger link')
            source_rows.append({k:asset[k] for k in ['asset_id','source','source_sha256','manifest']})
    saved_sources = json.loads((ROOT / 'assets/registry/current_source_index.json').read_text())['sources']
    require(source_rows == saved_sources, 'source index differs from asset ledger')
    runtime = json.loads((ROOT / index['runtime_inventory']).read_text())['resources']
    for resource in runtime:
        p = ROOT / resource['path']
        require(p.is_file(), 'missing runtime resource ' + resource['path'])
        if p.is_file(): require(hashlib.sha256(p.read_bytes()).hexdigest() == resource['sha256'], 'runtime hash drift: ' + resource['path'])
    for table in json.loads((ROOT / index['content_index']).read_text())['tables']:
        data = json.loads((ROOT / table['path']).read_text())
        values = data[table['collection_key']] if table['collection_key'] else data
        ids = [str(x['id']) for x in values if 'id' in x]
        require(ids == table['ids'] and len(ids) == len(set(ids)), 'content ID drift/duplicate ' + table['path'])
        require(table['owner'] in {r['feature_id'] for r in rows}, 'unknown content owner')
    target = ROOT / 'docs/generated/feature_index.json'
    value = {'generated_from': 'GDD_V1.0.md + individual feature ledgers; DO NOT EDIT', 'features': projected}
    if not issues and sync:
        master_path.write_text(master)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    elif not sync:
        require(target.exists() and json.loads(target.read_text()) == value, 'derived feature index stale; use --sync')
    for issue in issues: print('FAIL:', issue)
    print(f"{'FAIL' if issues else 'PASS'}: {len(rows)} features, {len(asset_ids)} source assets, {len(runtime)} runtime resource hashes; {len(issues)} issues")
    return 1 if issues else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sync', action='store_true')
    args = parser.parse_args()
    sys.exit(check(args.sync))
