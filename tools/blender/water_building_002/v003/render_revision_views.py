import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/water_building_002/v003';W=R.parent/'sea-work/water_building_002/v003';S=D/'water_building_002_v003.blend';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();before=sha(S)
if not bpy.data.filepath.replace('\\','/').endswith('water_building_002/v003/water_building_002_v003.blend'):
 bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
sc=bpy.context.scene
cam=sc.camera;original=(cam.location.copy(),cam.rotation_euler.copy(),cam.data.ortho_scale)
for name,pos,target,scale in [('roof_close',(42,-46,65),(1,0,36),32),('top',(0,-.001,90),(0,0,0),43),('back',(-54,65,49),(0,0,19),56)]:
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
cam.location,cam.rotation_euler,cam.data.ortho_scale=original
# Leave the user's viewport in the reference hero view, no resave changes source.
for win in bpy.context.window_manager.windows:
 for area in win.screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False
assert sha(S)==before
(W/'multiview_evidence.json').write_text(json.dumps({'source_sha256':before,'views':['before.png','hero.png','roof_close.png','top.png','back.png'],'source_not_resaved':True},indent=2)+'\n',encoding='utf-8');print('V003_VOLUME_VIEWS_DONE',before)
