"""Saved-file and every-package gate for sea's 8x8 PaletteUV contract.

The generic skill validator assumes ShellStorm2's 10x10 palette. This project
gate implements sea's required 8x8 cells and eight-pixel inset instead.
"""
import bpy,json,math,hashlib,os,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/wild_fishery/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'wild_fishery/v001';W.mkdir(parents=True,exist_ok=True)
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];LAY=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
checks=0;errors=[];metrics={'faces_uv_checked':0,'triangles':0,'components':len(CAT),'instances':len(LAY),'packages_reopened':0}
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(ok,label):
 global checks
 checks+=1
 if not ok:errors.append(label)
def identity(m):return all(abs(m[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4))
def inspect(e,add_metrics=False):
 col=bpy.data.collections.get(e['collection']);require(col is not None,e['key']+': collection exists')
 if col is None:return
 require(tuple(col.instance_offset)==(0,0,0),e['key']+': collection offset')
 root=bpy.data.objects.get(e['root']);require(root is not None and identity(root.matrix_local),e['key']+': root identity')
 coords=[];tris=0
 for ob in col.objects:
  if ob.type!='MESH':continue
  require(identity(ob.matrix_local),ob.name+': mesh identity');require(ob.parent==root,ob.name+': root ownership');require(len(ob.data.vertices)>0,ob.name+': nonempty')
  require(len(ob.users_collection)==1,ob.name+': unique package ownership');coords.extend(v.co for v in ob.data.vertices)
  uv=ob.data.uv_layers.get('PaletteUV');require(uv is not None,ob.name+': PaletteUV')
  if not uv:continue
  require(len(ob.data.uv_layers)==1 and ob.data.uv_layers.active==uv and uv.active_render,ob.name+': sole active UV0')
  for face in ob.data.polygons:
   points=[uv.data[i].uv for i in face.loop_indices]
   area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(points,points[1:]+points[:1])))/2
   cells={(math.floor(v.x*8),math.floor(v.y*8)) for v in points}
   require(area>1e-8 and len(cells)==1,ob.name+': nonzero UV face '+str(face.index))
   require(all(.124<=((v.x*8)%1)<=.876 and .124<=((v.y*8)%1)<=.876 for v in points),ob.name+': 8px UV inset')
   if add_metrics:metrics['faces_uv_checked']+=1
  for mat in ob.data.materials:
   require(mat.name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],ob.name+': material role')
   tx=[n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'];require(len(tx)==1,mat.name+': one palette')
   require(any(n.type=='UVMAP' and n.uv_map=='PaletteUV' for n in mat.node_tree.nodes),mat.name+': named UV node')
   for node in tx:
    require(node.interpolation=='Closest' and node.image.packed_file is None,mat.name+': external closest palette')
    require(Path(bpy.path.abspath(node.image.filepath)).resolve()==(R/P['palette']).resolve(),mat.name+': exact shared palette')
  ob.data.calc_loop_triangles();tris+=len(ob.data.loop_triangles)
 require(bool(coords),e['key']+': geometry exists')
 if coords:
  lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)]
  require(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,e['key']+': bottom-center origin')
  require(max(abs(lo[i]-e['bounds']['min'][i])+abs(hi[i]-e['bounds']['max'][i]) for i in range(3))<1e-4,e['key']+': saved bounds')
 require(tris==e['triangles'] and tris<=e['budget_triangles'],e['key']+': actual evaluated triangle count and budget')
 if add_metrics:metrics['triangles']+=tris
def render_views(prefix):
 scene=bpy.data.scenes['野外渔场_v001'];bpy.context.window.scene=scene;cam=scene.camera;target=Vector((-5,-4,-.5))
 views={'oblique':(-18,-23,22),'back':(12,13,16),'side':(-27,-1,8),'top':(-5,-4,34),'shore_close':(-8,-9,10)}
 for name,pos in views.items():
  aim=Vector((0,0,.2)) if name=='shore_close' else target
  cam.location=pos;cam.rotation_euler=(aim-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=10 if name=='shore_close' else 24
  scene.render.filepath=str(W/(prefix+'_'+name+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.open_mainfile(filepath=str(D/'wild_fishery.blend'))
families={}
for e in P['components']:families.setdefault(e['component_family'],[]).append(e)
require(len(CAT)==len(P['components'])<=50,'component budget')
require(all(len(v)<=3 for v in families.values()),'family variant budget')
for e in CAT:inspect(e,True)
scene=bpy.data.scenes['野外渔场_v001'];bpy.context.window.scene=scene
actual=[o for o in scene.objects if o.instance_type=='COLLECTION'];require(len(actual)==len(LAY),'instance reuse count')
expanded=0
for instance in bpy.context.evaluated_depsgraph_get().object_instances:
 ob=instance.object
 if not instance.is_instance or ob.type!='MESH':continue
 me=ob.to_mesh();me.calc_loop_triangles();expanded+=len(me.loop_triangles);ob.to_mesh_clear()
metrics['expanded_triangles']=expanded
require(expanded<=P['geometry_budget']['maximum_expanded_triangles'],'expanded runtime geometry budget')
for e in CAT:
 require(sha(R/e['component_blend'])==e['source_sha256'],e['key']+': package hash')
 bpy.ops.wm.open_mainfile(filepath=str(R/e['component_blend']));inspect(e);metrics['packages_reopened']+=1
for path,digest in P['protected_files'].items():require(sha(R/path)==digest,'protected source unchanged '+path)
report={'passed':not errors,'checks':checks,'errors':errors,'metrics':metrics,'source_sha256':sha(D/'wild_fishery.blend'),'palette_sha256':sha(R/P['palette']),'equivalent_validator':'project 8x8 implementation; generic skill script hardcodes 10x10'}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FISHERY_SOURCE_QA',json.dumps(report,ensure_ascii=False),flush=True)
if errors:raise RuntimeError('Source gate failed')
if '--render' in sys.argv:
 bpy.ops.wm.open_mainfile(filepath=str(D/'wild_fishery.blend'));render_views('source')
