"""Read-only inventory of the v002 component collections available for reuse."""
import json
import sys
from pathlib import Path

import bpy

want = ['facade_window', 'entry', 'rear_door', 'rear_wall', 'sign_band', 'sign_gifts',
        'sign_postcards', 'sign_drinks', 'postcard_rack', 'mailbox', 'ice_box',
        'vending', 'shelf', 'bottle', 'gift', 'rail_arc']
out = []
for key in want:
    cname = 'SEA-SCENE-FSH-' + key.upper().replace('_', '-')
    col = bpy.data.collections.get(cname)
    if col is None:
        out.append({'key': key, 'collection': cname, 'missing': True})
        continue
    pts = []
    mats = set()
    faces = 0
    for o in col.objects:
        if o.type != 'MESH':
            continue
        faces += len(o.data.polygons)
        for m in o.data.materials:
            if m:
                mats.add(m.name)
        for v in o.data.vertices:
            pts.append(o.matrix_world @ v.co)
    if not pts:
        out.append({'key': key, 'empty': True})
        continue
    xs = [p.x for p in pts]; ys = [p.y for p in pts]; zs = [p.z for p in pts]
    out.append({
        'key': key,
        'objects': len(col.objects),
        'faces': faces,
        'materials': sorted(mats),
        'min': [round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
        'max': [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)],
        'size': [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
    })
print('REUSE_INVENTORY ' + json.dumps(out, ensure_ascii=False))
