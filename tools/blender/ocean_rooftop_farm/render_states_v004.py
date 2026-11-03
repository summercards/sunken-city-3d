import bpy,json,math
from pathlib import Path
from mathutils import Vector
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v004');W=Path('D:/projects/sea-work/ocean_rooftop_farm/v004');s=bpy.context.scene;up=json.loads((D/'upgrade_states.json').read_text(encoding='utf-8'))
# Final socket aligns both pre/post bottom to grass surface instead of half-embedded tilted original base.
for p in up['pairs']:
 p['socket_world_blender'][2]=60.05;p['socket_world_godot'][1]=60.05
 for state,e in p['states'].items():s.objects[e['instance_name']].location.z=60.05
(D/'upgrade_states.json').write_text(json.dumps(up,ensure_ascii=False,indent=2),encoding='utf-8')
def state(which):
 for p in up['pairs']:
  for key,e in p['states'].items():
   c=bpy.data.collections[e['collection']];c.hide_render=key!=which;c.hide_viewport=key!=which
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'));s.cycles.samples=32;s.render.resolution_percentage=100
for which,fn in [('unbuilt','01_roof_before_upgrade.png'),('complete','02_roof_after_upgrade.png')]:state(which);s.render.filepath=str(W/fn);bpy.ops.render.render(write_still=True)
# standalone state render uses own meshes at local center, clean transparent studio.
cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
for key in ['greenhouse_unbuilt','greenhouse_complete','water_tower_unbuilt','water_tower_complete']:
 e=next(e for e in cat if e['key']==key);c=bpy.data.collections[e['collection']];ps=bpy.data.scenes.new('ORF4_资产预览_'+key);ps.world=s.world;oc=bpy.data.objects.new('独立资产预览',None);ps.collection.objects.link(oc);oc.instance_type='COLLECTION';oc.instance_collection=c
 ca=bpy.data.cameras.new('独立预览相机');co=bpy.data.objects.new(ca.name,ca);ps.collection.objects.link(co);size=Vector(e['bounds_size_m']);target=Vector((0,0,size.z*.45));co.location=target+Vector((size.x*.85,-size.y*1.1,max(size.x,size.y)*.9));co.rotation_euler=(target-co.location).to_track_quat('-Z','Y').to_euler();ca.type='ORTHO';ca.ortho_scale=max(size.x,size.y)*1.55;ps.camera=co
 ld=bpy.data.lights.new('独立柔光','SUN');ld.energy=2.1;ld.angle=.3;lo=bpy.data.objects.new(ld.name,ld);ps.collection.objects.link(lo);lo.rotation_euler=(.4,-.5,-.3)
 ps.render.engine='CYCLES';ps.cycles.samples=24;ps.cycles.use_denoising=True;ps.render.resolution_x=1100;ps.render.resolution_y=850;ps.render.resolution_percentage=100;ps.render.film_transparent=True;ps.render.image_settings.file_format='PNG';ps.view_settings.view_transform=s.view_settings.view_transform;ps.view_settings.look=s.view_settings.look;ps.render.filepath=str(W/(key+'.png'));bpy.context.window.scene=ps;bpy.ops.render.render(write_still=True);bpy.context.window.scene=s
 for ob in list(ps.objects):bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.scenes.remove(ps)
state('unbuilt');bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v004.blend'),compress=True)
print(json.dumps({'views':6,'default_state':'unbuilt','sockets':[p['socket_world_blender'] for p in up['pairs']]},ensure_ascii=False))
