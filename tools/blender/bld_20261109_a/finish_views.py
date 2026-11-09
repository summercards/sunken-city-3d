"""Finish shop visibility and render required views from the active MCP session."""
import bpy,json,math,hashlib,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v001';sc=bpy.context.scene
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));inst=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))
# Anchor actual counter front and jars together; never rely on nominal build pivots.
for o in sc.objects:
 if o.name=='BLDA_I_shelf_001':o.location.y=-3.275
 if o.name=='BLDA_I_shop_lintel_001':o.location.z=3.24
 if o.name.startswith('BLDA_I_jar_'):
  i=int(o.name.rsplit('_',1)[1])-1;o.location.y=-4.38+(i//8)*.46;o.location.z=2.79
 if o.name=='BLDA_I_basket_001':o.rotation_euler=(0,0,0)
 if o.name=='BLDA_I_blade_sign_001':o.location.x=5.06;o.location.y=-4.56;o.location.z=3.15
for row in inst['instances']:
 o=sc.objects[row['name']];row.update(position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale))
(D/'component_instances.json').write_text(json.dumps(inst,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Consistent hero camera; final source saved before temporary preview camera changes.
cam=sc.camera;cam.location=(-29,-29,22);cam.rotation_euler=(Vector((0,0,7.0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=20.6
sc.cycles.samples=48;sc.render.resolution_x=sc.render.resolution_y=1400;sc.render.filepath=str(W/'hero.png');bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(D/'bld_20261109_a.blend'),compress=True)
hero=(cam.location.copy(),cam.rotation_euler.copy(),cam.data.ortho_scale)
views=[('hero',(-29,-29,22),(0,0,7),20.6),('close',(-18,-22,11),(-.1,-2,4.0),13.0),('roof_close',(-18,-22,23),(0,0,11.8),12.8),('top',(0,-.001,40),(0,0,0),15.5),('back',(20,28,21),(0,0,6.8),20.6),('front',(0,-40,13),(0,0,6.5),18.5)]
for name,pos,target,scale in views:
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
plants=next(c for c in sc.collection.children if '03_独立植物' in c.name);plants.hide_render=True;cam.location=hero[0];cam.rotation_euler=hero[1];cam.data.ortho_scale=hero[2];sc.render.filepath=str(W/'building_only.png');bpy.ops.render.render(write_still=True);plants.hide_render=False
cam.location=hero[0];cam.rotation_euler=hero[1];cam.data.ortho_scale=hero[2]
print('BLDA_VIEWS_DONE',len(views)+1,flush=True)
