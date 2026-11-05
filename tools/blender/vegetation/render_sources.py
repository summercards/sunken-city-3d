"""Read-only source review board, four orthographic views outside the project."""
import bpy,math,json
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];W=R.parent/'sea-work/vegetation_implementation_20261105'
P=json.loads((R/'art_source/vegetation/v001/component_plan.json').read_text(encoding='utf-8'))
bpy.ops.wm.read_factory_settings(use_empty=True);S=bpy.context.scene
for i,e in enumerate(P['components']):
 path=R/'art_source/vegetation/v001/components'/e['key']/(e['key']+'_optimized.blend')
 with bpy.data.libraries.load(str(path),link=False) as (a,b):b.objects=[e['key']]
 o=b.objects[0];S.collection.objects.link(o);o.location=(i%4*1.8-2.7,i//4*1.6-.8,0)
 bpy.ops.object.text_add(location=(o.location.x-.62,o.location.y-.62,0.01));t=bpy.context.object;t.data.body=e['key'];t.data.size=.13
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025));floor=bpy.context.object
m=bpy.data.materials.new('review_sand');m.diffuse_color=(.38,.43,.38,1);floor.data.materials.append(m)
S.world=bpy.data.worlds.new('review_world');S.world.color=(.55,.55,.55)
for pos,power,size in [((1,-3,8),1300,7),((-5,2,5),900,5)]:
 bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();cam=bpy.context.object;S.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=9
S.render.engine='CYCLES';S.cycles.samples=16;S.render.resolution_x=1280;S.render.resolution_y=800;S.render.resolution_percentage=100
S.view_settings.view_transform='Standard';S.view_settings.look='None'
for name,pos in [('front',(0,-7,6)),('back',(0,7,6)),('side',(7,-1,5)),('top',(0,-.1,9))]:
 cam.location=pos;cam.rotation_euler=(Vector((0,0,.2))-cam.location).to_track_quat('-Z','Y').to_euler();S.render.filepath=str(W/('source_'+name+'.png'));bpy.ops.render.render(write_still=True)
print('VEGETATION_SOURCE_VIEWS_OK')
