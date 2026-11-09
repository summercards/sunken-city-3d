"""Measured visual correction pass, executed directly in the active Blender GUI."""
import bpy,json,math,hashlib,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v001'
# Rehydrate helper definitions without running the original scene generator.
import bmesh
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];layout=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
sc=bpy.data.scenes['BLDA_编号海上建筑_v001'];bpy.context.window.scene=sc
components={e['key']:bpy.data.collections[e['collection']] for e in catalog};roles={m['semantic_role']:m for m in bpy.data.materials if m.get('semantic_role')}
T=math.tau;pi=math.pi;palette=R/P['palette'];cells={c['name']:c for c in json.loads(palette.with_suffix('.json').read_text())['cells']};font=next(f for f in bpy.data.fonts if f.filepath.endswith('msyhbd.ttc'));current=None
top={g:next(c for c in sc.collection.children if label in c.name) for g,label in [('structure','01_建筑结构'),('furnishing','02_固定设施'),('plant','03_独立植物'),('display','90_展示支持')]}
src=(R/'tools/blender/bld_20261109_a/build.py').read_text(encoding='utf-8');exec(src[src.index('def finish('):src.index('# STRUCTURE:')])
assert len(components)>=48
# Uniform glyph sizing measured from mesh vertices, not unevaluated font object dimensions.
def fit_text(key,limit_w,limit_h,yshift=0):
 col=components[key];candidates=[o for o in col.objects if any(ch in o.name for ch in ['_字','FONT'])]
 if not candidates:return
 for o in candidates:
  pts=[v.co for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);center=(lo+hi)/2
  fac=min(limit_w/(hi.x-lo.x),limit_h/(hi.z-lo.z),1)
  o.data.transform(Matrix.Translation(center+Vector((0,yshift,0)))@Matrix.Scale(fac,4)@Matrix.Translation(-center))
  print('GLYPH_FIT',key,fac,tuple(hi-lo))
fit_text('main_sign',7.7,1.60,.06);fit_text('fascia',8.45,.65,.015);fit_text('shop_lintel',6.6,.90,.02);fit_text('blade_sign',1.65,.55,.01)
# Move stock close to the display opening, while preserving the clear approach strip.
for o in sc.objects:
 if o.name.startswith('BLDA_I_jar_'):
  o.location.y-=2.0;o.location.z-=.32
 if o.name.startswith('BLDA_I_shelf_'):o.location.y-=.60
# Planned extra fixed eave: same actual corrugation, not an arbitrary flat slab.
if 'side_eave' not in components:
 row={'key':'side_eave','id':'SEA-SCENE-B1109A-SIDE-EAVE','asset_id':'SEA-SCENE-B1109A-SIDE-EAVE','name':'侧窗波纹檐','family':'roofing','component_family':'roofing','group':'furnishing','layer':'ordinary','scope':'scene_local','building_class':'above_water','origin':'bottom_center','front_axis':'-Y','allowed_rotations_z_deg':[0,90,180,270],'loaded_responsibility':'references/above-water.md','collision_responsibility':'pending_Godot_facility_projections_not_in_Blender','bottom':1.0,'top':1.0,'kind':'horizontal_cover'}
 P['components'].append(row);P['component_budget']={'limit':50,'planned':49,'remaining':1};P['stylized_form']['components']=P['components'];(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 def eave():
  vs=[];N=120
  for y,zadd in [(-.56,0),(.22,.15)]:
   for i in range(N+1):
    x=-4.14+8.28*i/N;z=.1+zadd+.045*math.cos(math.tau*i/4);vs.extend([(x,y,z),(x,y,z-.08)])
  fs=[];st=(N+1)*2
  for i in range(N):
   a=2*i;fs.extend([(a,a+2,a+st+2,a+st),(a+st+1,a+st+3,a+3,a+1),(a+1,a+3,a+2,a),(a+st,a+st+2,a+st+3,a+st+1)])
  fs.extend([(0,st,st+1,1),(2*N+1,2*N+st+1,2*N+st,2*N)])
  mesh('侧窗青蓝波纹遮檐',vs,fs,'petrol','SEA_Metal',.008)
 part('side_eave',eave);put('side_eave',(-4.43,0,9.42),-math.pi/2)
# Lower the bulky roof-table carton to its own terrace support instead of towering above scene.
for o in sc.objects:
 if o.name.startswith('BLDA_I_carton_') and o.location.z>11.5:o.location.z-=1.3;o.location.x+=.5
# Restore a dense but geometric advertising border: all colour still via PaletteUV.
current=components['poster_panel'];e=next(c for c in catalog if c['key']=='poster_panel');pv=Vector(e['design_pivot']);oldset=set(current.objects)
for x in [-1.72,2.75]:
 for z in [1.0,1.4,1.8,2.2,2.6,3.0]:
  for j in range(5):
   a=math.tau*j/5;sphere('广告边饰花瓣',(x+.055*math.cos(a),-.235,z+.055*math.sin(a)),(.04,.018,.04),'cream',8,5)
for x in [-1.4,-.8,-.2,.4,1.0,1.6,2.2]:
 for z in [.59,3.50]:
  sphere('广告边饰红花',(x,-.235,z),(.12,.02,.10),'red_dark',10,6)
  tube('广告金色卷叶',[(x-.15,-.24,z),(x-.03,-.24,z+.10),(x+.12,-.24,z+.05)],.018,'gold',sides=6)
for o in set(current.objects)-oldset:o.data.transform(Matrix.Translation(-pv))
# Recompute exact bounds and rebase each modified collection without moving any world geometry.
for e in catalog:
 col=components[e['key']];pts=[v.co for o in col.objects for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 if shift.length>1e-8:
  for o in col.objects:o.data.transform(Matrix.Translation(-shift))
  for o in sc.objects:
   if o.instance_type=='COLLECTION' and o.instance_collection==col:o.location+=o.rotation_euler.to_matrix()@shift
  e['design_pivot']=[e['design_pivot'][i]+shift[i] for i in range(3)]
 e['bounds_size']=list(hi-lo);e['meshes']=len(col.objects);e['triangles']=0;e['polygons']=0;h=hashlib.sha256()
 for o in col.objects:
  o.data.calc_loop_triangles();e['triangles']+=len(o.data.loop_triangles);e['polygons']+=len(o.data.polygons)
  for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
 e['geometry_fingerprint']=h.hexdigest();e['fingerprint_algorithm']='ordered_vertices_fixed6_sha256'
layout=[]
for o in sc.objects:
 if o.instance_type=='COLLECTION':
  e=next(e for e in catalog if e['collection']==o.instance_collection.name);layout.append({'name':o.name,'key':e['key'],'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
sc.camera.location=(-29,-29,22);sc.camera.rotation_euler=(Vector((0,0,7.0))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=20.6
# Light neutral support, match reference's lilac studio rather than the draft slate backdrop.
mat=next(m for m in bpy.data.materials if m.name.startswith('BLDA_StudioBackdrop'));next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.48,.52,.66,1)
for role in roles.values():role.name=role['semantic_role']
# All other scenes are safe in session_before.blend; final source contains only this task scene.
for old in list(bpy.data.scenes):
 if old!=sc:bpy.data.scenes.remove(old)
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians; Z is vertical','godot_mapping':'(x,y,z)->(x,z,-y)','placement_owner':'Godot TSCN after future integration'},'instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
P['stylized_form']['body']['triangles']=sum(e['triangles']*sum(x['key']==e['key'] for x in layout) for e in catalog if e['layer']=='body');(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'bld_20261109_a.blend'),compress=True)
sc.render.filepath=str(W/'hero_refined.png');bpy.ops.render.render(write_still=True)
print('BLDA_REFINED',json.dumps({'components':len(catalog),'instances':len(layout)}),flush=True)
