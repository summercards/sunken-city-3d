import bpy, os
from pathlib import Path
W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop'
sc=bpy.context.scene;sc.render.resolution_percentage=65;sc.cycles.samples=24;sc.render.filepath=str(W/'preview.png')
bpy.ops.render.render(write_still=True)
print(sc.render.filepath)
