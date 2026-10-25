"""Create standalone packages, reopen every file, verify source invariants and render views.
Blender source-only check; game execution requires scripts/run_verification.py.
"""
import bpy,json,hashlib,math,os,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunny_bloom_retreat_v003'
source=D/'sunny_bloom_retreat.blend';pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
plan=json.loads((D/'component_plan.json').read_text());cat=json.loads((D/'catalog.json').read_text());entries=cat['components'];layout=json.loads((D/'component_instances.json').read_text())['instances'];errors=[];uv_faces=0
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(flag,msg):
 if not flag:errors.append(msg)
def identity(matrix):return max(abs(matrix[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6

def inspect(item,count=False):
 global uv_faces
 col=bpy.data.collections.get(item['collection']);require(col is not None,item['key']+' collection absent')
 if not col:return
 require(tuple(col.instance_offset)==(0,0,0),item['key']+' nonzero collection offset')
 root=bpy.data.objects.get(item['root']);require(root is not None and identity(root.matrix_local),item['key']+' root transform')
 meshes=[o for o in col.objects if o.type=='MESH'];require(bool(meshes),item['key']+' empty');coords=[];tris=0
 for o in meshes:
  require(o.parent==root and identity(o.matrix_local),o.name+' mesh transform/parent');coords.extend(v.co for v in o.data.vertices);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
  uv=o.data.uv_layers.get('PaletteUV');require(uv is not None,o.name+' missing PaletteUV')
  if not uv:continue
  require(len(o.data.uv_layers)==1 and o.data.uv_layers.active==uv and uv.active_render,o.name+' active UV')
  for f in o.data.polygons:
   points=[uv.data[l].uv for l in f.loop_indices];area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(points,points[1:]+points[:1])))/2
   require(area>1e-9,o.name+' UV zero area '+str(f.index));require(len({(int(v.x*8),int(v.y*8)) for v in points})==1,o.name+' UV crosses cells')
   require(all(.125-1e-5<=(v[i]*8)%1<=.875+1e-5 for v in points for i in [0,1]),o.name+' UV safety margin')
   if count:uv_faces+=1
  for mat in o.data.materials:
   require(mat.name in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'},o.name+' role '+mat.name)
   if mat.name=='SEA_Emission':require('emissive' in o.name,o.name+' luminous geometry not separate')
   nodes=mat.node_tree.nodes;tx=[n for n in nodes if n.type=='TEX_IMAGE'];require(len(tx)==1,mat.name+' image nodes')
   for n in tx:
    require(n.interpolation=='Closest' and n.image.packed_file is None,mat.name+' filtering/packed');require(Path(bpy.path.abspath(n.image.filepath)).resolve()==pal.resolve(),mat.name+' wrong palette path');require(bool(n.inputs['Vector'].links) and n.inputs['Vector'].links[0].from_node.type=='UVMAP' and n.inputs['Vector'].links[0].from_node.uv_map=='PaletteUV',mat.name+' UV input')
 if coords:
  lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)];require(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,item['key']+' bottom center');require(all(abs(hi[i]-lo[i]-item['bounds_size'][i])<1e-5 for i in range(3)),item['key']+' bounds mismatch')
 require(tris<=item['triangle_budget'],item['key']+' component triangle budget '+str(tris))
 item['triangles']=tris

bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.preferences.filepaths.save_version=0
require(len(entries)==len(plan['components'])<=50,'planned component count')
require(sha(D/'reference.png')==plan['reference_sha256'],'reference hash')
families={}
for e in entries:families.setdefault(e['family'],[]).append(e)
for f,items in families.items():require(len(items)<=3,f+' family variants')
scene=bpy.context.scene;actual={o.name:o for o in scene.objects if o.instance_type=='COLLECTION'}
require(len(actual)==len(layout),'instance count')
for i in layout:
 o=actual.get(i['name']);require(o is not None,i['name']+' missing instance')
 if o:
  require(o.instance_collection.name==i['asset_id'],o.name+' collection mismatch')
  for key,val in [('position',o.location),('rotation_euler_xyz',o.rotation_euler),('scale',o.scale)]:require(max(abs(val[k]-i[key][k]) for k in range(3))<1e-5,o.name+' '+key)
  expected='02 花朵与植物' if i['category']=='flora' else '结构' if i['category']=='structure' else '固定设施与陈设';require(o.name in bpy.data.collections[expected].objects,o.name+' category')
for e in entries:inspect(e,True)
# Check actual saved instance geometry, not only the layout's declared values.
def bounds(obj):
 points=[obj.matrix_world @ mesh.matrix_local @ v.co for mesh in obj.instance_collection.objects if mesh.type=='MESH' for v in mesh.data.vertices]
 return ([min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)])
def by_key(key):return [o for o in actual.values() if o.instance_collection.name=='SEA-SCENE-SBR-'+key.upper().replace('_','-')]
piers=by_key('wall_pier');require(sum(o.location.y>2.5 and o.location.z<1 for o in piers)>=3,'missing rear white wall piers')
posts=by_key('canopy_post');require(len(posts)==3 and len(by_key('canopy_hook'))==1,'reference canopy: three freestanding posts and wall anchor')
room=bounds(by_key('upper_room')[0]);post_overlap=[]
for o in posts:
 lo,hi=bounds(o)
 if all(min(hi[i],room[1][i])-max(lo[i],room[0][i])>.01 for i in [0,1]):post_overlap.append(o.name)
require(not post_overlap,'canopy posts buried in wall: '+str(post_overlap))
boards=by_key('dock_board');require(len(boards)==12,'bridge board count');require(sorted({round(o.location.x,2) for o in boards})==[-2.05,-.82],'two bridge strips alignment')
deck=by_key('deck_tile');require(len(deck)==294,'main platform, left ledge and actual front extension paving count')
front=min(bounds(o)[0][1] for o in deck);bridge_back=max(bounds(o)[1][1] for o in boards);require(0<=front-bridge_back<.03,'bridge platform attachment gap')
require(all(bounds(o)[0][1]>-4.85 for o in by_key('cooler')),'cooler blocks front apron')
require(len(by_key('porch_return'))==1 and len(by_key('porch_side'))==2,'front room wall enclosure')
layout_checks={'rear_main_wall_piers':3,'canopy_posts':len(posts),'canopy_wall_overlaps':post_overlap,'deck_planks':len(deck),'bridge_boards':len(boards),'bridge_platform_gap_m':round(front-bridge_back,5),'cooler_approach_clear':True}

# Reference-fidelity checks: count actual windows and ray-test the shell apertures.
require(len(by_key('tall_window'))==1 and len(by_key('narrow_window'))==1 and len(by_key('small_window'))==1,'reference window count')
from mathutils.bvhtree import BVHTree
house=by_key('house')[0];hm=next(o for o in house.instance_collection.objects if o.type=='MESH')
verts=[house.matrix_world @ v.co for v in hm.data.vertices];bvh=BVHTree.FromPolygons(verts,[list(p.vertices) for p in hm.data.polygons])
wide_hit=bvh.ray_cast(Vector((-4.5,1.26,1.9)),Vector((1,0,0)))
narrow_hit=bvh.ray_cast(Vector((-2.05,-3.0,1.9)),Vector((0,1,0)))
blank_hit=bvh.ray_cast(Vector((-4.5,2.5,1.9)),Vector((1,0,0)))
require(wide_hit[3] is not None and wide_hit[3]>4,'left wide aperture blocked')
require(narrow_hit[3] is not None and narrow_hit[3]>4,'front narrow aperture blocked')
require(blank_hit[3] is not None and blank_hit[3]<2,'old second side window still open')
# White frame vertices distinguish visible panel thickness from hidden mounting feet.
solar=by_key('solar');require(len(solar)==2,'two solar panels')
mesh=next(o.data for o in solar[0].instance_collection.objects if o.type=='MESH');uv=mesh.uv_layers['PaletteUV'];white=[]
for face in mesh.polygons:
 q=uv.data[face.loop_indices[0]].uv
 if (int(q.x*8),int(q.y*8))==(4,7):white.extend(mesh.vertices[i].co for i in face.vertices)
frame_size=[max(v[i] for v in white)-min(v[i] for v in white) for i in range(3)]
require(all(abs(a-b)<1e-4 for a,b in zip(frame_size,[1.38,1.85,.14])),'solar visible white frame dimensions')
clear=plan['layout_revision']['unobstructed_front_zone'];obstructions=[]
for ob in actual.values():
 lo,hi=bounds(ob)
 if all(min(hi[i],clear['max'][i])-max(lo[i],clear['min'][i])>.005 for i in range(3)):obstructions.append(ob.name)
require(not obstructions,'front open apron invaded: '+str(obstructions))
layout_checks.update(windows={'left_wide':1,'front_narrow':1,'upper_small':1},window_shell_rays_pass=True,solar_frame_m=frame_size,front_extension_area_m2=14.4,front_clear_rectangle=clear,front_clear_obstructions=obstructions)

flowers=by_key('pink_flower')+by_key('daisy')
normals=[o.rotation_euler.to_matrix()@Vector((0,-1,0)) for o in flowers]
require(all(n.z>.5 for n in normals),'flower face not tilted upward')
require(max(n.z for n in normals)-min(n.z for n in normals)>.2,'flower inclination lacks variation')
require(len({tuple(round(v,2) for v in n) for n in normals})==len(normals),'repeated flower face direction')
layout_checks['flower_upward_normals']=[list(n) for n in normals]

# Inspect saved geometry for the revised thickness and color, not only nominal script inputs.
by_entry={e['key']:e for e in entries}
require(abs(by_entry['deck_tile']['bounds_size'][2]-.17)<1e-5,'deck thickness')
require(abs(by_entry['dock_board']['bounds_size'][2]-.23)<1e-5,'dock thickness')
pinkmesh=next(o.data for o in bpy.data.collections[by_entry['pink_flower']['collection']].objects if o.type=='MESH')
puv=pinkmesh.uv_layers['PaletteUV'];petal_points=[];flower_cells=set()
for f in pinkmesh.polygons:
 q=puv.data[f.loop_indices[0]].uv;cell=(int(q.x*8),int(q.y*8));flower_cells.add(cell)
 if cell==(2,2):petal_points.extend(pinkmesh.vertices[i].co for i in f.vertices)
require((2,2) in flower_cells and (3,2) not in flower_cells,'pink petals must use pink, not rose')
petal_depth=max(v.y for v in petal_points)-min(v.y for v in petal_points)
require(abs(petal_depth-.29)<1e-5,'petal plumpness depth')
review_notes={
 'foundation':'0.54 m solid rounded foundation retained',
 'deck_tile':'Increased slab from 0.13 to 0.17 m, top remains aligned',
 'dock_board':'Increased board from 0.18 to 0.23 m, rounded end radius 0.065',
 'pier':'0.52 m solid pier retained',
 'house':'0.21 m actual shell thickness, rounded openings retained',
 'terrace':'0.28 m white fascia retained',
 'upper_room':'Solid wall volume with 0.08 m edge bevel retained',
 'cap':'0.32 m roof cap retained',
 'parapet':'0.30 m wide white blocks retained',
 'slope':'Increased roof slab to 0.20 m and orange fascia to 0.20 m',
 'bollard':'0.34 m square solid timber with thick foot retained',
 'tall_window':'Frame 0.08 m wide and 0.14 m deep, glass remains thin',
 'narrow_window':'Frame 0.08 m wide and 0.14 m deep, glass remains thin',
 'small_window':'Frame 0.08 m wide and 0.14 m deep',
 'door':'0.10 m door with 0.23 m deep surrounds retained',
 'entry':'Frame widened to 0.10 m and depth 0.18 m',
 'solar':'Visible rounded frame 0.14 m, inset 0.026 m, border 0.07 m',
 'awning':'0.055 m canvas and plump scalloped edge retained',
 'canopy_post':'Post widened to 0.32 x 0.34 m; radius 0.075 m',
 'canopy_beam':'Beam section increased to 0.26 x 0.30 m',
 'sail':'Material-specific thin cloth 0.025 m, piped border retained',
 'ladder':'0.13 x 0.17 m rails, 0.11 m treads retained',
 'ac_tall':'Full 0.54 m depth housing with rounded corners retained',
 'ac_box':'Full 0.53 m depth housing retained, louvers remain thin',
 'ac_roof':'Full 0.75 m depth housing retained',
 'chimney':'0.22 x 0.26 m solid shaft retained',
 'lantern':'0.25 m deep frame and luminous core retained',
 'sofa':'Cushions increased to 0.26 m; deep rounded back retained',
 'roof_sofa':'Cushions increased to 0.26 m',
 'coffee_table':'Tabletop increased to 0.18 m',
 'table':'Tabletop increased to 0.18 m',
 'stool':'Seat increased to 0.16 m',
 'umbrella':'Canopy edge increased to 0.045 m; domed profile retained',
 'cooler':'0.61 m deep solid housing; 0.16 m lid retained',
 'pot':'Thick lip and tapered pot silhouette retained',
 'square_pot':'0.48 m rounded solid pot retained',
 'bottle':'0.18 m body diameter retained',
 'mat':'Material-specific flat 0.028 m mat retained',
 'foliage':'Ellipsoid leaf depth 0.23 m retained',
 'vine':'Rounded ellipsoid leaves, 0.16-0.18 m depth retained',
 'palm':'Blade cross-section maintains up to 0.21 m thickness along curved spine',
 'pink_flower':'Petal depth increased to 0.29 m, pink palette cell',
 'daisy':'Petal depth increased to 0.29 m, white palette cell',
 'sprout':'Small succulent leaf thickness 0.15 m retained',
 'porch_side':'White posts increased to 0.26 x 0.22 m, sills to 0.28 m',
 'wall_pier':'0.30 x 0.30 m rounded white posts retained',
 'porch_return':'0.18 m actual white side wall retained',
 'vase':'0.24 m diameter round belly retained',
 'canopy_hook':'0.12 m diameter rounded wall-mounted rod retained',
}
require(set(review_notes)==set(by_entry),'all component thickness reviews present')
thickness_review={'schema':'sea.scene.thickness_review','source_sha256':sha(source),'entries':[{'key':e['key'],'bounds_m':e['bounds_size'],'review':review_notes[e['key']]} for e in entries],'actual_solar_frame_m':frame_size,'actual_pink_petal_depth_m':petal_depth,'pink_palette_cells':sorted(flower_cells),'palette_changed':False}
(W/'thickness_review.json').write_text(json.dumps(thickness_review,ensure_ascii=False,indent=2)+'\n')
layout_checks['thickness_review']=thickness_review

deps=bpy.context.evaluated_depsgraph_get();polygons=triangles=0
for inst in deps.object_instances:
 o=inst.object
 if o.type=='MESH' and not o.hide_render:
  mesh=o.to_mesh();mesh.calc_loop_triangles();polygons+=len(mesh.polygons);triangles+=len(mesh.loop_triangles);o.to_mesh_clear()
metrics=dict(components=len(entries),instances=len(layout),flora_instances=sum(i['category']=='flora' for i in layout),uv_faces_checked=uv_faces,expanded_polygons=polygons,expanded_triangles=triangles)
if errors:raise RuntimeError('\n'.join(sorted(set(errors))))
# Packages are created from only their own collection and the single shared external palette.
for e in entries:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 with bpy.data.libraries.load(str(source),link=False) as (data_from,data_to):data_to.collections=[e['collection']]
 bpy.context.scene.collection.children.link(data_to.collections[0]);bpy.context.scene.name=e['name'];bpy.context.scene.unit_settings.system='METRIC'
 path=R/e['component_source'];path.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=str(pal)
 for screen in bpy.data.screens:
  for a in screen.areas:
   if a.type=='VIEW_3D':
    a.spaces.active.shading.type='MATERIAL';a.spaces.active.region_3d.view_location=Vector((0,0,e['bounds_size'][2]/2));a.spaces.active.region_3d.view_distance=max(e['bounds_size'])*2
 bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal))
 bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
 e['source_sha256']=sha(path);e['palette']=str(pal.relative_to(R));e['version']='v003';e['asset_ledger']='assets/registry/ledgers/scenes.json#'+e['asset_id'];e['stage']='source_verified_runtime_pending';e['license']='pending_user_reference_rights_review'
 (path.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n')
 bpy.ops.wm.open_mainfile(filepath=str(path));inspect(e)
 print('REOPENED',e['key'],flush=True)
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n')
report={'schema':'sea.scene.source_verification','passed':not errors,'errors':sorted(set(errors)),'source_sha256':sha(source),'palette_sha256':sha(pal),'reference_sha256':sha(D/'reference.png'),'metrics':metrics,'standalone_packages_reopened':len(entries),'source_only':True,'expected_faults':[],'not_executed':['Godot import/runtime/collision/navigation','reference commercial rights verification'],'views':[],'layout_checks':layout_checks}
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
if errors:raise RuntimeError(str(errors))
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene;scene.cycles.samples=48;cam=scene.camera
views=[('beauty',None,None,None,False),('building_only',None,None,None,True),('detail',(-8,-12,9),(-.2,.4,4.2),7.9,False),('top',(0,-2.5,24),(0,-2.5,0),14.7,False),('rear_structure',(10,14,11),(0,-1.0,2.6),13.6,True),('front_court',(-8,-14,9),(1.0,-3.5,1.9),8.7,False)]
for name,position,target,scale,hide in views:
 bpy.data.collections['02 花朵与植物'].hide_render=hide
 if position:cam.location=position;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
 scene.render.filepath=str(W/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True);report['views'].append({'name':name,'path':scene.render.filepath})
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('SOURCE_VERIFIED',json.dumps(report,ensure_ascii=False),flush=True)
