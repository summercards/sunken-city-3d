exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())
import os
# display env
disp=bpy.data.collections.get('WB003_90_DisplaySupport_env') or bpy.data.collections.new('WB003_90_DisplaySupport_env')
if disp.name not in top['display'].children: top['display'].children.link(disp)
for n in ('WB003_Cam','WB003_Sun'):
    o=bpy.data.objects.get(n)
    if o:
        for c in list(o.users_collection): c.objects.unlink(o)
        disp.objects.link(o)
# library collections to a hidden master scene
ms=bpy.data.scenes.get('WB003_Masters') or bpy.data.scenes.new('WB003_Masters')
for k,c in cols.items():
    if c.name not in [x.name for x in ms.collection.children]: ms.collection.children.link(c)
# triangle count over evaluated instances
dg=bpy.context.evaluated_depsgraph_get(); tri=0; poly=0; n=0
for inst in dg.object_instances:
    o=inst.object
    if o.type=='MESH':
        me=o.data; me.calc_loop_triangles(); tri+=len(me.loop_triangles); poly+=len(me.polygons); n+=1
print('TRI',tri,'POLY',poly,'MESHINST',n)
(D/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','blender_axes':'XY plane, +Z up, rotate about Z','godot_map':'(x,y,z)->(x,z,-y)','reference_positions':True,'instances':instances},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'tri_count.json').write_text(json.dumps({'triangles':tri,'polygons':poly,'mesh_instances':n,'basis':'depsgraph instances'},indent=1))
bpy.context.window.scene=sc
bpy.ops.wm.save_as_mainfile(filepath=str(D/'water_building_003_v001.blend'))
# independent packages
pk=D/'component_packages'
for k,c in cols.items():
    d=pk/k; d.mkdir(parents=True,exist_ok=True)
    bpy.data.libraries.write(str(d/(k+'.blend')),{c},path_remap='ABSOLUTE',compress=True)
print('saved',len(cols),'packages')
