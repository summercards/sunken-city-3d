import bpy,json
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath='D:/projects/sea/art_source/scenes/bld_20261109_a/v004_lowpoly/bld_20261109_a_v004_lowpoly.blend',load_ui=False)
try:
 p=bpy.ops.export_scene.gltf.get_rna_type().properties
 out=[]
 for x in p:
  if x.identifier in {'export_materials','export_format','use_selection','use_active_collection','export_texture_dir','export_image_format','export_apply'}:
   out.append({'id':x.identifier,'type':x.type,'enum':[e.identifier for e in x.enum_items] if x.type=='ENUM' else None})
 print(json.dumps(out,ensure_ascii=False))
except Exception as e: print(type(e).__name__,e)
