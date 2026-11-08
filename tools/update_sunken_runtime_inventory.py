"""只刷新本轮真正改动的运行时资源哈希，并登记新增文件。

不做批量刷新：并行会话改过的其它文件继续显示 drift（AGENTS 第 9 条：
授权未核验时明确 pending，不通过批量更新哈希隐藏未知变更）。
"""
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
INV = REPO / 'assets/registry/runtime_resource_inventory.json'
STATUS = 'runtime_verified_sealed_interior_20261108'


def sha(p):
    data = Path(p).read_bytes()
    return hashlib.sha256(data).hexdigest(), len(data)


def main():
    sealed = [c['key'] for c in json.loads(
        (REPO / 'art_source/scenes/sunken_city/v006/seal_report.json').read_text(encoding='utf-8'))['components']]

    touched = set()
    for slug in sealed:
        touched.add('godot/assets/models/scenery/sunken_city/%s/%s.glb' % (slug, slug))
        touched.add('godot/assets/models/scenery/sunken_city/%s/%s.glb.import' % (slug, slug))
        touched.add('godot/scenes/components/scenery/sunken_city/%s.tscn' % slug)
        touched.add('godot/assets/models/scenery/sunken_city_tall/%s/%s.glb' % (slug, slug))
        touched.add('godot/scenes/components/scenery/sunken_city_tall/%s.tscn' % slug)
    # 版本标记统一升到 v006，50 个包装场景都改过，一并刷新。
    for w in sorted((REPO / 'godot/scenes/components/scenery/sunken_city').glob('*.tscn')):
        touched.add(str(w.relative_to(REPO)).replace('\\', '/'))
    touched |= {
        'godot/scenes/underwater/sunroom_region/sunken_city_layout.tscn',
        'godot/scenes/world/sunken_city.tscn',
        'godot/src/diving/sunroom_region.gd',
        'godot/tests/test_sunken_city.gd',
        'godot/tests/test_sunroom_underwater_region.gd',
        'godot/assets/models/scenery/sunken_city/runtime_manifest.json',
    }

    inv = json.loads(INV.read_text(encoding='utf-8'))
    by_path = {r['path']: r for r in inv['resources']}
    updated, added, missing = 0, 0, []

    for rel in sorted(touched):
        p = REPO / rel
        if not p.is_file():
            missing.append(rel)
            continue
        digest, size = sha(p)
        rec = by_path.get(rel)
        if rec is None:
            entry = {'path': rel, 'asset_id': None, 'sha256': digest, 'bytes': size,
                     'status': STATUS,
                     'audit_note': '2026-11-08 水下建筑封闭与回字型高楼环：本轮新增或改写的运行时资源。'}
            if 'sunken_city_tall' in rel:
                slug = rel.split('/')[-2] if rel.endswith('.glb') else rel.split('/')[-1][:-5]
                entry['asset_id'] = 'SEA-SCENE-SCITY-TALL-' + slug.upper().replace('_', '-')
            inv['resources'].append(entry)
            by_path[rel] = entry
            added += 1
        elif rec.get('sha256') != digest or rec.get('bytes') != size:
            rec['sha256'] = digest
            rec['bytes'] = size
            rec['status'] = STATUS
            rec['audit_note'] = '2026-11-08 水下建筑封闭（v006 封闭版 / v008 高楼版）后的实测哈希。'
            updated += 1

    inv['note'] = (inv.get('note', '') + ' 2026-11-08 仅刷新封闭相关的运行时资源；'
                   '其它并行改动的 drift 保留不掩盖。').strip()
    INV.write_text(json.dumps(inv, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('updated', updated, 'added', added, 'missing', missing)


main()
