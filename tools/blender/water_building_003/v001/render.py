import bpy, math, sys
from pathlib import Path
from mathutils import Vector
W=Path('D:/projects/sea-work/water_building_003/v001'); sc=bpy.data.scenes['WB003_v001']
if sc.camera is None or sc.camera.name!='WB003_Cam':
    cam=bpy.data.objects.new('WB003_Cam',bpy.data.cameras.new('WB003_Cam')); sc.collection.objects.link(cam); sc.camera=cam
cam=sc.camera; cam.data.type='ORTHO'
if 'WB003_Sun' not in bpy.data.objects:
    l=bpy.data.objects.new('WB003_Sun',bpy.data.lights.new('WB003_Sun','SUN')); sc.collection.objects.link(l)
    l.rotation_euler=(math.radians(50),0,math.radians(-35)); l.data.energy=3.5
sc.world=bpy.data.worlds.get('WB003_W') or bpy.data.worlds.new('WB003_W'); sc.world.use_nodes=True
bg=next((n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND'),None) or sc.world.node_tree.nodes.new('ShaderNodeBackground')
out=next((n for n in sc.world.node_tree.nodes if n.type=='OUTPUT_WORLD'),None) or sc.world.node_tree.nodes.new('ShaderNodeOutputWorld')
if not bg.outputs[0].links: sc.world.node_tree.links.new(bg.outputs[0],out.inputs[0])
bg.inputs[0].default_value=(.95,.97,1,1); bg.inputs[1].default_value=1.0
try: sc.render.engine='BLENDER_EEVEE_NEXT'
except Exception: sc.render.engine='BLENDER_EEVEE'
sc.render.resolution_x=1024; sc.render.resolution_y=1024
def shot(name, loc, tgt, scale):
    cam.location=loc; d=Vector(tgt)-Vector(loc); cam.rotation_euler=d.to_track_quat('-Z','Y').to_euler(); cam.data.ortho_scale=scale
    sc.render.filepath=str(W/(name+'.png')); bpy.ops.render.render(write_still=True)
views={'front':((0,-80,7.5),(0,0,7.5),22),'three_quarter':((-45,-55,30),(0,0,7),24),'back':((30,70,25),(0,0,7),24),'top':((0,-1,90),(0,0,0),20)}
for n in sys.argv[1:] if False else NAMES:
    a,b,c=views[n]; shot(n,a,b,c)
print('rendered',NAMES)
