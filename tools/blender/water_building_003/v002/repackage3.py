exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
# Save actual standalone .blend files, one temporary scene per component.
orig=bpy.context.window.scene
for k,c in cols.items():
    aid=by[k]['asset_id']; old=c.name; c.name=aid
    ts=bpy.data.scenes.new('ComponentPackage_'+k)
    ts.collection.children.link(c)
    bpy.context.window.scene=ts
    p=D/'component_packages'/k; p.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(p/(k+'.blend')),copy=True)
    ts.collection.children.unlink(c)
    bpy.data.scenes.remove(ts)
    c.name=old
bpy.context.window.scene=orig
print('standalone packages saved',len(cols))
