exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
# Collections were source-only and unlinked from the active scene, so bpy.data.libraries.write skipped them.
# Link each one to a temporary scene during export; this preserves the component as a real openable package.
for k,c in cols.items():
    aid=by[k]['asset_id']; old=c.name; c.name=aid
    ts=bpy.data.scenes.new('PACKAGE_EXPORT_'+k)
    ts.collection.children.link(c)
    p=D/'component_packages'/k; p.mkdir(parents=True,exist_ok=True)
    bpy.data.libraries.write(str(p/(k+'.blend')),{c},path_remap='ABSOLUTE',compress=True)
    ts.collection.children.unlink(c)
    bpy.data.scenes.remove(ts)
    c.name=old
print('repackaged linked',len(cols))
