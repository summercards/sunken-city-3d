"""Read-only: report which palette image each v003 blend actually links.

Never saves. Used to settle whether the recorded palette field matches the source.
"""
import json
import sys
from pathlib import Path

import bpy

out = []
for im in bpy.data.images:
    if im.source != 'FILE':
        continue
    path = Path(bpy.path.abspath(im.filepath))
    out.append({
        'image': im.name,
        'filepath': im.filepath,
        'absolute': str(path),
        'exists': path.is_file(),
    })
print('PALETTE_LINKS ' + json.dumps({
    'blend': bpy.data.filepath,
    'images': out,
}, ensure_ascii=False))
sys.exit(0)
