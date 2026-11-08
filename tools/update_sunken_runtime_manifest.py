"""把 v006 封闭版的面数与哈希同步进运行时清单。

只改这 20 个建筑组件自己的 triangles / glb_sha256 / source_sha256 / asset_version，
其余记录、实例清单、地形契约一律原样保留。
"""
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / 'godot/assets/models/scenery/sunken_city/runtime_manifest.json'
REPORT = REPO / 'art_source/scenes/sunken_city/v006/seal_report.json'


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    report = json.loads(REPORT.read_text(encoding='utf-8'))
    sealed = {r['key']: r for r in report['components']}
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))

    changed = []
    for comp in manifest['components']:
        key = comp['key']
        rep = sealed.get(key)
        if rep is None:
            continue
        glb = REPO / rep['runtime_path']
        before = comp.get('triangles')
        comp['triangles'] = rep['triangles']
        comp['glb_sha256'] = sha(glb)
        comp['source_sha256'] = rep['sealed_sha256']
        comp['asset_version'] = 'v006'
        comp['sealed_interior'] = True
        comp['interior_policy'] = 'watertight_shell_no_enterable_space'
        comp['prefab_sha256'] = sha(REPO / 'godot/scenes/components/scenery/sunken_city' / (key + '.tscn'))
        changed.append((key, before, rep['triangles']))

    manifest['sealed_interior'] = True
    manifest['sealed_interior_note'] = (
        '2026-11-08 用户要求楼房封闭：v005 的 20 栋建筑组件补封盖后另存 v006，'
        '网格水密、玩家无法进入楼体。实例变换、材质与包围盒不变。')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('manifest updated', len(changed), 'components')
    for k, a, b in changed:
        print(f'  {k:22s} {a} -> {b}')


main()
