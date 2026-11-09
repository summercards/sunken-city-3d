import bpy, traceback
from pathlib import Path
log=Path('D:/projects/sea-work/bld_20261109_a/v002/debug_trace.txt')
bpy.ops.wm.open_mainfile(filepath='D:/projects/sea/art_source/scenes/bld_20261109_a/v001/bld_20261109_a.blend', load_ui=False)
try:
    code=Path('D:/projects/sea/tools/blender/bld_20261109_a/v002/iterate_v002.py').read_text(encoding='utf-8')
    exec(compile(code,'iterate_v002.py','exec'),globals(),globals())
except Exception:
    log.write_text(traceback.format_exc()+'\nFILE='+str(bpy.data.filepath)+'\nSCENE='+bpy.context.scene.name,encoding='utf-8')
    raise
