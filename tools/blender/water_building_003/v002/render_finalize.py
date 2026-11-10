exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
from pathlib import Path
import math
from mathutils import Vector
W=Path('D:/projects/sea-work/water_building_003/v002');W.mkdir(parents=True,exist_ok=True)
if bpy.data.objects.get('WB003V2_Camera') is None:
 cam=bpy.data.objects.new('WB003V2_Camera',bpy.data.cameras.new('WB003V2_Camera'));sc.collection.objects.link(cam)
else: cam=bpy.data.objects['WB003V2_Camera']
sc.camera=cam;cam.data.type='ORTHO'
if bpy.data.objects.get('WB003V2_Sun') is None:
 l=bpy.data.objects.new('WB003V2_Sun',bpy.data.lights.new('WB003V2_Sun','SUN'));sc.collection.objects.link(l)
else:l=bpy.data.objects['WB003V2_Sun']
l.rotation_euler=(math.radians(35),math.radians(-25),math.radians(-30));l.data.energy=3
sc.world=bpy.data.worlds.get('WB003V2_W') or bpy.data.worlds.new('WB003V2_W');sc.world.use_nodes=True
nodes=sc.world.node_tree.nodes;links=sc.world.node_tree.links
for n in list(nodes):nodes.remove(n)
bg=nodes.new('ShaderNodeBackground');out=nodes.new('ShaderNodeOutputWorld');bg.inputs[0].default_value=(.94,.97,1,1);bg.inputs[1].default_value=.8;links.new(bg.outputs[0],out.inputs[0])
sc.render.engine='BLENDER_EEVEE_NEXT';sc.render.resolution_x=1024;sc.render.resolution_y=1024;sc.render.resolution_percentage=100

def shot(name,loc,tgt,scale):
 cam.location=loc;cam.rotation_euler=(Vector(tgt)-Vector(loc)).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
shot('front',(0,-80,8),(0,0,8),20);shot('three_quarter',(-35,-55,26),(0,0,8),23);shot('rear',(30,65,22),(0,0,8),23);shot('top',(0,-1,80),(0,0,5),19)
# save and export data
D.joinpath('catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
D.joinpath('component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','blender_axes':'XY plane +Z up','godot_map':'(x,y,z)->(x,z,-y)','instances':instances},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
dg=bpy.context.evaluated_depsgraph_get();tri=poly=mi=0
for inst in dg.object_instances:
 o=inst.object
 if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles);poly+=len(o.data.polygons);mi+=1
D.joinpath('tri_count.json').write_text(json.dumps({'triangles':tri,'polygons':poly,'mesh_instances':mi,'basis':'depsgraph evaluated instances'},indent=2),encoding='utf8')
bpy.ops.wm.save_as_mainfile(filepath=str(D/'water_building_003_v002.blend'))
for k,c in cols.items():
 p=D/'component_packages'/k;p.mkdir(parents=True,exist_ok=True);bpy.data.libraries.write(str(p/(k+'.blend')),{c},path_remap='ABSOLUTE',compress=True)
print('saved',len(catalog),len(instances),'tri',tri,'poly',poly,'meshinst',mi)
