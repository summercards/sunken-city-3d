"""Use the prop validator's explicit UI-light naming for the emissive bulb."""
import bpy, json, hashlib
from pathlib import Path

D = Path(r'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v001')
W = D.parents[3].parent/'sea-work/ocean_rooftop_farm/v001'
source = D/'ocean_rooftop_farm.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_emissive_rename.blend'), copy=True, compress=True)
col = bpy.data.collections['SEA-SCENE-ORF-LAMP-POST']
obj = next(o for o in col.objects if o.type == 'MESH' and any(m and m.name == 'SEA_Emission' for m in o.data.materials))
obj.name = '暖灯_UI灯光'
bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
print(json.dumps({'renamed_emissive_object':obj.name, 'geometry_changed':False, 'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}, ensure_ascii=False))
