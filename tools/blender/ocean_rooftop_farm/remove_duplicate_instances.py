"""Remove exact duplicate collection instances left by an interrupted R2 rerun."""
import bpy, json
from collections import Counter
from pathlib import Path

D = Path(r'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v001')
W = D.parents[3].parent / 'sea-work/ocean_rooftop_farm/v001'
source = D / 'ocean_rooftop_farm.blend'
W.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(source))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_duplicate_cleanup.blend'), copy=True, compress=True)
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
layout_path = D/'component_instances.json'
data = json.loads(layout_path.read_text(encoding='utf-8'))
seen = set()
remove = []
kept = []
for item in data['instances']:
    signature = (item['key'], tuple(round(v, 5) for v in item['position']), tuple(round(v, 5) for v in item['rotation_euler_xyz']), tuple(round(v, 5) for v in item['scale']))
    if signature in seen:
        remove.append(item['name'])
    else:
        seen.add(signature)
        kept.append(item)
for name in remove:
    obj = bpy.data.objects.get(name)
    if obj is not None:
        bpy.data.objects.remove(obj, do_unlink=True)
data['instances'] = kept
layout_path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
counts = Counter(item['key'] for item in kept)
cat_path = D/'component_catalog.json'
cat = json.loads(cat_path.read_text(encoding='utf-8'))
for entry in cat['components']:
    entry['instances'] = counts[entry['key']]
cat_path.write_text(json.dumps(cat, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
print(json.dumps({'removed':remove, 'remaining_instances':len(kept), 'backup':str(W/'before_duplicate_cleanup.blend')}, ensure_ascii=False))
