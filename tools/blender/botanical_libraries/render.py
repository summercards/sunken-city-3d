"""Render real Blender archive views without modifying saved libraries."""
import bpy,json,os,sys,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_libraries/v001'
P=json.loads((R/'art_source/vegetation/libraries/v001/component_plan.json').read_text(encoding='utf-8'))
which=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for lib in P['libraries']:
 if which and which[0].lower() not in lib['library_id'].lower():continue
 bpy.ops.wm.open_mainfile(filepath=str(R/lib['path']),load_ui=False)
 s=bpy.context.scene;cam=s.camera;target=Vector(s['review_target']);width=s['review_width'];depth=s['review_depth'];extent=max(width,depth)
 if 'PLANTING' in lib['library_id']:
  s.render.resolution_x=1600;s.render.resolution_y=2400
 else:
  s.render.resolution_x=2400;s.render.resolution_y=2400
 s.cycles.samples=16
 # A near-orthographic board makes every item readable instead of hiding rear rows.
 views=[('overview',(0,-extent*.55,extent*1.5)),('top',(0,-.01,extent*2)),('back',(0,extent*.45,extent*1.6)),('side',(extent*.8,-extent*.2,extent*1.5))]
 results=[]
 for name,delta in views:
  cam.location=target+Vector(delta);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
  # Fit all gallery bounds in camera space, including side/back projections and portrait aspect.
  bpy.context.view_layer.update();inv=cam.matrix_world.inverted()
  corners=[inv@Vector((x,y,z)) for x in [-1.7,width+1.7] for y in [-depth-1.8,1.6] for z in [-.1,2.5]]
  minx=min(v.x for v in corners);maxx=max(v.x for v in corners);miny=min(v.y for v in corners);maxy=max(v.y for v in corners)
  shift=cam.rotation_euler.to_matrix()@Vector(((minx+maxx)/2,(miny+maxy)/2,0));cam.location+=shift
  aspect=s.render.resolution_x/s.render.resolution_y;cam.data.ortho_scale=max(maxy-miny,(maxx-minx)/aspect)*1.07
  out=W/'outputs'/(("vegetation" if 'VEGETATION' in lib['library_id'] else 'planting')+'_'+name+'.png')
  s.render.filepath=str(out);bpy.ops.render.render(write_still=True);results.append(str(out))
 print('BOTANICAL_VIEWS '+json.dumps({'library':lib['library_id'],'files':results},ensure_ascii=False))
