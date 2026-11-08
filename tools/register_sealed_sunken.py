"""把本轮封闭与大尺寸组件写进场景资产账本。

两件事：
1. 20 个 v005 建筑组件改为 v006（封闭版），运行时路径不变，旧哈希进 previous_sources。
2. 20 个 v003 高楼组件以 v008（封闭版）新增登记，运行时在 sunken_city_tall。

AssetID 规则沿用现有：`SEA-SCENE-SCITY-<SLUG-UPPER>`；新增的用 `SEA-SCENE-SCITY-TALL-<SLUG-UPPER>`。

用法：python3 tools/register_sealed_sunken.py [--dry-run]
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LEDGER = REPO / 'assets/registry/ledgers/scenes.json'


def sha(p):
    data = Path(p).read_bytes()
    return hashlib.sha256(data).hexdigest(), len(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    ledger = json.loads(LEDGER.read_text(encoding='utf-8'))
    assets = ledger['assets']
    by_id = {a['asset_id']: a for a in assets}

    sealed_report = json.loads((REPO / 'art_source/scenes/sunken_city/v006/seal_report.json')
                               .read_text(encoding='utf-8'))
    tall_report = json.loads((REPO / 'art_source/scenes/sunken_city/v008/seal_report.json')
                             .read_text(encoding='utf-8'))
    sealed = {r['key']: r for r in sealed_report['components']}
    tall = {r['key']: r for r in tall_report['components']}

    updated = []
    added = []

    for key, rep in sealed.items():
        asset_id = 'SEA-SCENE-SCITY-' + key.upper().replace('_', '-')
        rec = by_id.get(asset_id)
        if rec is None:
            print('SKIP missing record', key)
            continue
        old = {k: rec.get(k) for k in ('version', 'source', 'source_sha256', 'runtime_path')}
        old_runtime_sha = sha(REPO / rec['runtime_path'])[0] if (REPO / rec['runtime_path']).exists() else None

        rec['version'] = 'v006'
        rec['source'] = rep['sealed_blend'] if 'sealed_blend' in rep else rec['source']
        rec['source_sha256'] = rep['sealed_sha256']
        rec['runtime_path'] = rep['runtime_path']
        rec['runtime_sha256'] = rep['glb_sha256']
        rec['sealed_interior'] = True
        rec['interior_policy'] = 'watertight_shell_no_enterable_space'
        rec['boundary_edges_after'] = rep['boundary_after']
        rec['triangles_sealed'] = rep['triangles']
        rec.setdefault('previous_sources', [])
        rec['previous_sources'].append({
            'version': old['version'], 'source': old['source'],
            'source_sha256': old['source_sha256'],
            'runtime_path': old['runtime_path'], 'runtime_sha256': old_runtime_sha,
            'reason': '2026-11-08 封闭内部空间前的可进入版本',
        })
        rec['note'] = ('2026-11-08 用户要求楼房封闭：破口与窗洞补封盖，网格改为水密，'
                       '玩家无法游进楼体内部；破损轮廓、材质槽与包围盒保持。'
                       '实例位置/缩放/朝向未改。')
        updated.append(asset_id)

    template = next(a for a in assets if a.get('suite') == 'sunken_city'
                    and a.get('category') == 'underwater_scenic_building')

    for key, rep in tall.items():
        asset_id = 'SEA-SCENE-SCITY-TALL-' + key.upper().replace('_', '-')
        if asset_id in by_id:
            print('SKIP existing', asset_id)
            continue
        rec = copy.deepcopy(template)
        rec.update({
            'asset_id': asset_id,
            'name': rep['name'] + '（封闭·大尺寸）',
            'suite': 'sunken_city_tall',
            'version': 'v008',
            'source': rep['sealed_blend'],
            'source_sha256': rep['sealed_sha256'],
            'runtime_path': rep['runtime_path'],
            'runtime_sha256': rep['glb_sha256'],
            'prefab': 'godot/scenes/components/scenery/sunken_city_tall/%s.tscn' % key,
            'stage': 'source_verified_runtime_integrated_pending_visual_review',
            'runtime_integrated': False,
            'runtime_status': 'pending_visual_review',
            'prefab_status': 'pending_visual_review',
            'runtime_validation': 'pending',
            'sealed_interior': True,
            'interior_policy': 'watertight_shell_no_enterable_space',
            'boundary_edges_after': rep['boundary_after'],
            'triangles_sealed': rep['triangles'],
            'source_height_m': rep['bbox'][5] - rep['bbox'][2],
            'reference_scale': 2.0,
            'placement_owner': 'godot/scenes/underwater/sunroom_region/sunken_city_layout.tscn',
            'note': ('2026-11-08 家园海底回字型深沟外圈用高楼组件：取 v003 未限高的原生高层几何，'
                     '封闭内部后单独导出，引用时按 2.0 倍尺度摆放。原始 v003 源与运行资源不动。'),
            'verification': [],
            'previous_sources': [],
        })
        assets.append(rec)
        by_id[asset_id] = rec
        added.append(asset_id)

    print('updated', len(updated), 'added', len(added))
    if not args.dry_run:
        LEDGER.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print('LEDGER_WRITTEN')


main()
