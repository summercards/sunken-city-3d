import bpy,glob,os
for p in glob.glob('D:/projects/sea/art_source/scenes/water_building_003/v002/component_packages/foundation/*.blend'):
 with bpy.data.libraries.load(p,) as (src,dst): print('SRC',src.collections[:20],src.scenes[:10],src.objects[:5])
