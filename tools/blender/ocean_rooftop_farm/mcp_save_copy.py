import bpy, json
from pathlib import Path
p = Path('D:/projects/sea/sea-work/ocean_rooftop_farm/rebuild_r3_prechange.blend')
p.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(p), copy=True)
print(json.dumps({'saved_copy': str(p), 'current': bpy.data.filepath, 'objects': len(bpy.data.objects)}, ensure_ascii=False))
