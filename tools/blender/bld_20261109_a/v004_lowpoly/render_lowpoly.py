import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v004_lowpoly';W=R.parent/'sea-work/bld_20261109_a/v004_lowpoly';S=D/'bld_20261109_a_v004_lowpoly.blend'
W.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
sc=bpy.context.scene; assert sc.name=='BLDA_编号海上建筑_v004_lowpoly'; cam=sc.camera
for name,pos,target,scale in [('hero',(-29,-29,22),(0,0,7),20.6),('close',(-18,-22,11),(-.1,-2,4),13.0),('roof_close',(-18,-22,23),(0,0,11.8),12.8),('top',(0,-.001,40),(0,0,0),15.5),('back',(20,28,21),(0,0,6.8),20.6),('front',(0,-40,13),(0,0,6.5),18.5)]:
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(W/(name+'_v004_lowpoly.png'));bpy.ops.render.render(write_still=True)
plants=next((c for c in sc.collection.children if '03_独立植物' in c.name),None)
if plants:
 plants.hide_render=True
 cam.location=(-29,-29,22);cam.rotation_euler=(Vector((0,0,7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=20.6;sc.render.filepath=str(W/'building_only_v004_lowpoly.png');bpy.ops.render.render(write_still=True);plants.hide_render=False
sha=hashlib.sha256(S.read_bytes()).hexdigest();(W/'view_evidence.json').write_text(json.dumps({'source_sha256':sha,'views':['hero_v004_lowpoly','close_v004_lowpoly','roof_close_v004_lowpoly','top_v004_lowpoly','back_v004_lowpoly','front_v004_lowpoly','building_only_v004_lowpoly'],'source_not_resaved':True},indent=2)+'\n',encoding='utf-8');print('RENDERED',sha)
