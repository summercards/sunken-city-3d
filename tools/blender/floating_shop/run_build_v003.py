import bpy
from pathlib import Path
with bpy.context.temp_override(window=bpy.context.window_manager.windows[0]):
 exec(compile(Path('D:/projects/sea/tools/blender/floating_shop/build_v003.py').read_text(encoding='utf-8'),'build_v003.py','exec'))
