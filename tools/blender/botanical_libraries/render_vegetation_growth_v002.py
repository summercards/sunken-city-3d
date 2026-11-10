"""Readable actual Blender comparison plates: same scale for each species' three forms."""
import bpy,json,os,sys,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];OUT=R/'art_source/vegetation/libraries/v002';W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_growth/v002/vegetation';M=json.loads((OUT/'library_manifest.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(R/M['path']),load_ui=False);s=bpy.context.scene;cam=s.camera;s.cycles.samples=16;s.render.resolution_percentage=100
rendered=[]
def shot(name,target,width,height,angle='front',resolution=(2400,1800),only_id=None,only_ids=None):
 # A detail render must not include neighboring species' geometry or labels.
 center=Vector(target);ids=set(only_ids or ([only_id] if only_id else []));centers=[Vector(p['gallery_center']) for p in M['plants'] if p['asset_id'] in ids]
 for ob in bpy.data.collections['小中大_展示实例'].objects:
  ob.hide_render=bool(ids) and (ob.instance_collection is None or ob.instance_collection.get('asset_id') not in ids)
 for ob in bpy.data.collections['展示支持_不导出'].objects:
  if ob.type=='FONT':ob.hide_render=bool(ids) and not any(abs(ob.location.x-c.x)<3 and c.y-2.1<ob.location.y<c.y+.4 for c in centers)
 s.render.resolution_x,s.render.resolution_y=resolution;target=Vector(target);d=max(width,height)
 delta={'front':(0,-d*.85,d*1.1),'top':(0,-.01,d*2),'back':(0,d*.85,d*1.1),'side':(d*1.2,-d*.6,d*.9)}[angle]
 cam.location=target+Vector(delta);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update();inv=cam.matrix_world.inverted();pts=[inv@(target+Vector((x,y,z))) for x in [-width/2,width/2] for y in [-height/2,height/2] for z in [-.5,1.5]];minx=min(v.x for v in pts);maxx=max(v.x for v in pts);miny=min(v.y for v in pts);maxy=max(v.y for v in pts);cam.location+=cam.rotation_euler.to_matrix()@Vector(((minx+maxx)/2,(miny+maxy)/2,0));aspect=resolution[0]/resolution[1];cam.data.ortho_scale=(max(maxx-minx,(maxy-miny)*aspect) if aspect>=1 else max((maxx-minx)/aspect,maxy-miny))*1.08;s.render.filepath=str(W/'renders'/(name+'.png'));bpy.ops.render.render(write_still=True);rendered.append(s.render.filepath)
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
if args and args[0]=='pages':
 for page in range(3):
  lo=page*35;hi=min(98,lo+35);rows=math.ceil((hi-lo)/7);first=M['plants'][lo]['gallery_center'];last=M['plants'][hi-1]['gallery_center'];cy=(first[1]+last[1])/2
  shot('comparison_page_'+str(page+1),(s['review_width']/2,cy-.6,.5),s['review_width']+3,rows*3.9+1,'front',(3500,1200),only_ids=[p['asset_id'] for p in M['plants'][lo:hi]])
elif args and args[0]=='sample':
 keys=['SEA-SCENE-PFH-LEAF-CLUSTER','SEA-SCENE-PFH-VINE','SEA-SCENE-SOLAR-PALM','SEA-SCENE-TFH-FLOWER','SEA-FISHERY-REEDS','SEA-DECO-WATER-LILY','SEA-VEG-GRASS-SOFT','SEA-SCENE-SCITY-KELP-CLUMP']
 for aid in keys:
  p=next(p for p in M['plants'] if p['asset_id']==aid);shot('detail_'+aid.lower(),p['gallery_center'],6.3,2.8,only_id=aid)
else:
 width=s['review_width']+4;height=s['review_depth']+5;target=s['review_target']
 for view in ['front','top','back','side']:shot('overview_'+view,target,width,height,view,(3000,3000))
 # Seven species across, five rows per page keeps all 3 forms readable.
 for page in range(3):
  lo=page*35;hi=min(98,lo+35);rows=math.ceil((hi-lo)/7);first=M['plants'][lo]['gallery_center'];last=M['plants'][hi-1]['gallery_center'];cy=(first[1]+last[1])/2
  shot('comparison_page_'+str(page+1),(s['review_width']/2,cy-.6,.5),s['review_width']+3,rows*3.9+1,'front',(3500,1200),only_ids=[p['asset_id'] for p in M['plants'][lo:hi]])
 # One representative per family/profile, plus user-visible flower and vine shape.
 for fam in ['broadleaf','flower','palm','vine','grass','reed','moss','kelp','water_leaf','tomato']:
  p=next(p for p in M['plants'] if p['family']==fam);shot('detail_'+fam,p['gallery_center'],6.3,2.8,'front',(2000,1000),only_id=p['asset_id'])
if args and args[0]=='pages':rendered=json.loads((W/'render_report.json').read_text(encoding='utf-8'))['rendered']
(W/'render_report.json').write_text(json.dumps({'library_sha256':M['sha256'],'rendered':rendered,'count':len(rendered),'note':'same per-species display scale; seasons omitted'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('VEGETATION_GROWTH_RENDER '+json.dumps({'count':len(rendered)},ensure_ascii=False))
