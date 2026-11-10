exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())
if not (W/'session_before_wb003.blend').exists():
    bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before_wb003.blend'),copy=True)
print(sc.name, len(by), list(top))
