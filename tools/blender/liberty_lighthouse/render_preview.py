import bpy
from pathlib import Path
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';W=R/'sea-work/liberty_lighthouse';W.mkdir(exist_ok=True)
sc=bpy.data.scenes['巨手灯塔_制作与装配_v001'];bpy.context.window.scene=sc;sc.render.resolution_x=1000;sc.render.resolution_y=1400;sc.cycles.samples=40;sc.render.filepath=str(W/'beauty.png');bpy.ops.render.render(write_still=True)
print('RENDERED',sc.render.filepath)
