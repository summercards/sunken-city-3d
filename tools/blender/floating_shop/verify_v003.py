import bpy,json,hashlib,os,math
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop/v003';source=D/'floating_shop.blend';pal=R/json.loads((D/'component_plan.json').read_text())['palette'];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));layout=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances'];errors=[];uvfaces=meshes=0
base=(R/'tools/blender/floating_shop/verify.py').read_text(encoding='utf-8');exec(base[base.index('def req('):base.index('bpy.ops.wm.open_mainfile(filepath=str(source))')])
bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.data.scenes['海上悬浮商铺_v003'];bpy.context.window_manager.windows[0].scene=sc
actual={o.name:o for o in sc.objects if o.instance_type=='COLLECTION'};req(len(actual)==len(layout)==273,'layout instances');req(len(cat['components'])==32,'32 planned components')
for e in cat['components']:inspect(e,True)
for row in layout:
 o=actual.get(row['name']);req(o is not None,row['name']+' missing')
 if o:
  for k,n in [('position','location'),('rotation_euler_xyz','rotation_euler'),('scale','scale')]:req(max(abs(getattr(o,n)[j]-row[k][j]) for j in range(3))<1e-5,row['name']+' transform')
forbidden={'facade_window','entry','rear_wall','rear_door','shelf','bottle','gift','postcard_rack','vending','mailbox','ice_box','rail_arc','sign_band','sign_gifts','sign_drinks','sign_postcards'}
req(not({r['key'] for r in layout}&forbidden),'old storefront/circular structure retained')
deck=next(e for e in cat['components'] if e['key']=='deck');req(abs(deck['bounds_size'][0]/deck['bounds_size'][1]-4/3)<.005,'deck 4:3')
wall_instances=[r for r in layout if r['key']=='wall_panel'];req(len(wall_instances)==20,'all twenty solid wall panels');req({r['key'] for r in layout}=={e['key'] for e in cat['components']},'every component consumed')
allpts=[];polys=tris=0
for row in layout:
 o=actual[row['name']]
 for m in o.instance_collection.objects:
  if m.type!='MESH':continue
  allpts.extend(o.matrix_world@m.matrix_world@v.co for v in m.data.vertices);polys+=len(m.data.polygons);m.data.calc_loop_triangles();tris+=len(m.data.loop_triangles)
# Front platform corridor stops at the sealed wall; there is intentionally no door.
obstacles=[]
for row in layout:
 if row['key'] in ['deck','under_brace','engine','engine_glow','float_pod','aux_nozzle','aux_glow']:continue
 o=actual[row['name']]
 for m in o.instance_collection.objects:
  if m.type!='MESH':continue
  p=[o.matrix_world@m.matrix_world@v.co for v in m.data.vertices];lo=[min(v[j] for v in p) for j in range(3)];hi=[max(v[j] for v in p) for j in range(3)]
  if lo[0]<1.2 and hi[0]>-1.2 and lo[1]<-4.75 and hi[1]>-7.1 and lo[2]<4.6 and hi[2]>2.56:obstacles.append(row['name']+'/'+m.name)
req(not obstacles,'front deck route blocked '+str(obstacles))
standard=json.loads((R/'.agents/skills/sea-scene-component-authoring/references/building_scale.json').read_text())['measurements'];bykey={e['key']:e for e in cat['components']}
req(abs(deck['bounds_size'][2]-standard['slab_thickness'])<1e-5,'sunroom slab thickness')
req(abs(bykey['wall_panel']['bounds_size'][2]-standard['ground_clear_height'])<1e-5,'sunroom clear storey height')
req(abs(bykey['corner_post']['bounds_size'][0]-standard['main_column_width'])<1e-5 and abs(bykey['corner_post']['bounds_size'][1]-standard['main_column_depth'])<1e-5,'sunroom column cross section')
boards=[o for o in bpy.data.collections[deck['collection']].objects if o.type=='MESH' and o.name.startswith('阳光房标准木板')]
req(len(boards)==32,'32 full-thickness standard planks')
for board in boards:
 size=[max(v.co[j] for v in board.data.vertices)-min(v.co[j] for v in board.data.vertices) for j in range(3)];req(abs(size[1]-standard['platform_board_width'])<1e-5 and abs(size[2]-standard['platform_board_thickness'])<1e-5,board.name+' standard plank size')
previous=json.loads((W/'verification.json').read_text(encoding='utf-8')) if (W/'verification.json').exists() else {}
views=previous.get('views',[]) if previous.get('source_sha256')==sha(source) else []
report={'schema':'sea.scene.source_verification','passed':not errors,'errors':sorted(set(errors)),'source_only':True,'source_sha256':sha(source),'palette_sha256':sha(pal),'reference_sha256':sha(D/'reference.png'),'metrics':{'components':32,'instances':len(layout),'master_meshes':meshes,'uv_faces_checked':uvfaces,'expanded_polygons':polys,'expanded_triangles':tris,'overall_bounds_m':[max(p[j] for p in allpts)-min(p[j] for p in allpts) for j in range(3)],'deck_bounds_m':deck['bounds_size'],'deck_aspect_ratio':deck['bounds_size'][0]/deck['bounds_size'][1],'solid_wall_panels':20,'doors':0,'windows':0,'clear_front_deck_route_m':2.4},'standalone_packages_reopened':0,'views':views,'exit_codes':{},'not_executed':['new walk surface/landing/trade gameplay','reference commercial rights verification','user final art acceptance']}
report['sunroom_dimension_validation']={'single_storey_clear_height_m':bykey['wall_panel']['bounds_size'][2],'floor_to_floor_reference_m':standard['ground_floor_to_floor'],'deck_thickness_m':deck['bounds_size'][2],'roof_floor_plate_thickness_m':standard['slab_thickness'],'column_cross_section_m':bykey['corner_post']['bounds_size'][:2],'board_width_m':standard['platform_board_width'],'board_thickness_m':standard['platform_board_thickness'],'planks_checked':len(boards),'door_outer_frame_reference_only_m':standard['door_frame_outer_height'],'door_added':False}
if errors:
 (W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');raise RuntimeError(str(errors))
for e in cat['components']:
 assert '/v003/component_packages/' in e['component_source'],'refuse writing historical source packages'
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 c=b.collections[0];bpy.context.scene.collection.children.link(c);bpy.context.scene.name=e['name'];bpy.context.scene.unit_settings.system='METRIC';p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal),start=str(p.parent))
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
 e['source_sha256']=sha(p);e['palette']=pal.relative_to(R).as_posix();e['palette_sha256']=sha(pal);e['stage']='source_verified_runtime_pending';e['version']='v003';e['asset_ledger']='assets/registry/ledgers/scenes.json#'+e['asset_id'];(p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 bpy.ops.wm.open_mainfile(filepath=str(p));inspect(e);report['standalone_packages_reopened']+=1
report['passed']=not errors;report['errors']=sorted(set(errors));report['exit_codes']['source_validation']=0 if not errors else 1
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(source));exec((R/'tools/blender/floating_shop/restore_mcp.py').read_text(encoding='utf-8'))
if errors:raise RuntimeError(str(errors))
print('V003_VERIFIED',json.dumps(report['metrics']))
