#!/usr/bin/env python3
"""Split the existing pole/flower islands for scene-owned placement, without remodeling.

The old GLB joined these islands to unrelated floating timber. Keep vertex attributes,
materials, winding and all other meshes verbatim. Only compact/split its index set.
Run without --apply to audit; --apply keeps a recoverable copy outside the project.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import struct

from restore_salvage_vertex_colors import read_glb, read_vec3

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'godot/assets/models/facilities/legacy_home/salvage_station.glb'
BASE_SHA = '4aaef9b50fca8c6ee889cc5cc34a622e0a5e0e7d890cad9922a96a9e20536e9b'
MARKER = 'sea_pole_group_split_v1'
NAME = 'PoleAndFlowers'
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
BYTES = {5121: 1, 5123: 2, 5125: 4, 5126: 4}


def indices(doc, blob, accessor):
    a = doc['accessors'][accessor]
    v = doc['bufferViews'][a['bufferView']]
    fmt = {5123: 'H', 5125: 'I'}[a['componentType']]
    return struct.unpack_from('<' + str(a['count']) + fmt, blob,
                              v.get('byteOffset', 0) + a.get('byteOffset', 0))


def pole_vertices(doc, blob, primitive):
    points = read_vec3(doc, blob, primitive['attributes']['POSITION'])
    parents = list(range(len(points)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    def union(i, j):
        parents[find(i)] = find(j)

    welded = {}
    for i, point in enumerate(points):
        key = tuple(round(v, 4) for v in point)
        if key in welded:
            union(i, welded[key])
        else:
            welded[key] = i
    triangles = indices(doc, blob, primitive['indices'])
    for i in range(0, len(triangles), 3):
        union(triangles[i], triangles[i + 1])
        union(triangles[i], triangles[i + 2])
    groups = collections.defaultdict(list)
    for i in range(len(points)):
        groups[find(i)].append(i)
    # Reviewed complete connected islands: pole, spool, flowers, vines and insulators.
    # The five floating-timber islands are at z=4.27..6.32 and stay untouched.
    selected = {i for group in groups.values()
                if min(points[j][2] for j in group) > 9.0 for i in group}
    assert len(groups) == 116 and len(selected) == 16894, 'Unexpected mesh layout'
    assert all(len({i in selected for i in triangles[t:t + 3]}) == 1
               for t in range(0, len(triangles), 3)), 'Would cut a triangle'
    return selected, triangles


def append_accessor(doc, blob, payload, template, target):
    blob += b'\0' * (-len(blob) % 4)
    view = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob),
                               'byteLength': len(payload), 'target': target})
    blob += payload
    accessor = len(doc['accessors'])
    doc['accessors'].append(template | {'bufferView': view})
    return accessor


def compact(doc, blob, primitive, triangle_indices):
    used = sorted(set(triangle_indices))
    mapping = {old: new for new, old in enumerate(used)}
    attrs = {}
    for name, original in primitive['attributes'].items():
        acc = doc['accessors'][original]
        view = doc['bufferViews'][acc['bufferView']]
        width = WIDTH[acc['type']] * BYTES[acc['componentType']]
        stride = view.get('byteStride', width)
        start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        payload = b''.join(blob[start + i * stride:start + i * stride + width] for i in used)
        new_acc = {k: v for k, v in acc.items() if k not in ['bufferView', 'byteOffset', 'min', 'max']}
        new_acc['count'] = len(used)
        if name == 'POSITION':
            pts = list(struct.iter_unpack('<3f', payload))
            new_acc['min'] = [min(p[k] for p in pts) for k in range(3)]
            new_acc['max'] = [max(p[k] for p in pts) for k in range(3)]
        attrs[name] = append_accessor(doc, blob, payload, new_acc, 34962)
    payload = struct.pack('<' + str(len(triangle_indices)) + 'H',
                          *(mapping[i] for i in triangle_indices))
    result = primitive | {'attributes': attrs}
    result['indices'] = append_accessor(doc, blob, payload,
                                       {'componentType': 5123, 'count': len(triangle_indices),
                                        'type': 'SCALAR'}, 34963)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    original = TARGET.read_bytes()
    doc, blob, _ = read_glb(TARGET)
    if doc.get('extras', {}).get(MARKER):
        print('Already split; placement belongs to salvage_station.tscn')
        return
    assert hashlib.sha256(original).hexdigest() == BASE_SHA, 'Unreviewed input; do not patch'
    primitive = doc['meshes'][0]['primitives'][3]
    selected, triangles = pole_vertices(doc, blob, primitive)
    move, keep = [], []
    for t in range(0, len(triangles), 3):
        (move if triangles[t] in selected else keep).extend(triangles[t:t + 3])
    print(f'Pole/flowers: {len(selected)} vertices, {len(move) // 3} triangles; '
          f'other timber: {len(keep) // 3} triangles; attributes unchanged')
    if not args.apply:
        return
    work = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')).resolve()
    backup = work / 'backups' / ('salvage_station-' + BASE_SHA[:12] + '.glb')
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists():
        assert backup.read_bytes() == original
    else:
        backup.write_bytes(original)
    doc['meshes'][0]['primitives'][3] = compact(doc, blob, primitive, keep)
    mesh_id = len(doc['meshes'])
    doc['meshes'].append({'name': NAME, 'primitives': [compact(doc, blob, primitive, move)]})
    node_id = len(doc['nodes'])
    doc['nodes'].append({'name': NAME, 'mesh': mesh_id})
    doc['scenes'][doc.get('scene', 0)]['nodes'].append(node_id)
    doc.setdefault('extras', {})[MARKER] = {'base_sha256': BASE_SHA, 'vertices': len(selected),
                                          'triangles': len(move) // 3}
    doc['buffers'][0]['byteLength'] = len(blob)
    js = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    blob += b'\0' * (-len(blob) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js
    out += struct.pack('<II', len(blob), 0x004E4942) + blob
    TARGET.write_bytes(out)
    print(f'Wrote {TARGET.relative_to(ROOT)}; backup {backup}')


if __name__ == '__main__':
    main()
