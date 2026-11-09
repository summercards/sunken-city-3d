"""Third visual correction: readable signage, shallow sail canopy, visible stock."""
import bpy,bmesh,json,math,hashlib,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];sc=bpy.data.scenes['BLDA_编号海上建筑_v001'];bpy.context.window.scene=sc
if not (W/'before_final_refine.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_final_refine.blend'),copy=True)
components={e['key']:bpy.data.collections[e['collection']] for e in catalog};roles={m['semantic_role']:m for m in bpy.data.materials if m.get('semantic_role')};palette=R/P['palette'];cells={c['name']:c for c in json.loads(palette.with_suffix('.json').read_text())['cells']};font=bpy.data.fonts.load('C:/Windows/Fonts/msyhbd.ttc');T=math.tau;pi=math.pi;current=None
src=(R/'tools/blender/bld_20261109_a/build.py').read_text(encoding='utf-8');exec(src[src.index('def finish('):src.index('# STRUCTURE:')])
top={g:next(c for c in sc.collection.children if label in c.name) for g,label in [('structure','01_建筑结构'),('furnishing','02_固定设施'),('plant','03_独立植物'),('display','90_展示支持')]}
# Rebuild only text in the two signs. Reference's two close characters are twins, not offspring.
for key,body,width,height in [('main_sign','廖孖記',7.3,1.62),('fascia','廖 孖 記 腐 乳 王',8.50,.69),('shop_lintel','廖 孖 記',6.35,1.0)]:
 col=components[key];e=next(e for e in catalog if e['key']==key);current=col
 old=[o for o in col.objects if '_字' in o.name]
 if not old:raise RuntimeError('text mesh missing '+key)
 o=old[0];pts=[v.co for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);ctr=(lo+hi)/2
 for o in old:bpy.data.objects.remove(o,do_unlink=True)
 o=text(body,(0,0,0),width,height,'cream' if key!='shop_lintel' else 'darkwood',.026)
 pts=[v.co for v in o.data.vertices];ll=Vector([min(v[i] for v in pts) for i in range(3)]);hh=Vector([max(v[i] for v in pts) for i in range(3)]);cc=(ll+hh)/2
 sx=width/(hh.x-ll.x);sz=height/(hh.z-ll.z)
 for v in o.data.vertices:v.co=Vector(((v.co.x-cc.x)*sx+ctr.x,v.co.y-cc.y+ctr.y,(v.co.z-cc.z)*sz+ctr.z))
# Put shop sign below the awning and lighten the inside with products rather than area-light tricks.
for o in sc.objects:
 if o.name.startswith('BLDA_I_shop_lintel_'):o.location.z-=.96
 if o.name.startswith('BLDA_I_fascia_'):o.location.y+=.53
 if o.name.startswith('BLDA_I_blade_sign_'):
  # The side sign is attached to the right facade edge, not swallowed by the main canopy.
  o.rotation_euler.z=0;o.location=Vector((4.72,-4.45,3.22))+Vector(next(e for e in catalog if e['key']=='blade_sign')['design_pivot'])
 if o.name.startswith('BLDA_I_jar_'):
  o.location.y=-3.32;o.location.z-=.40
 if o.name.startswith('BLDA_I_shelf_'):o.location.y-=.90
# Canopy same planned component: reduce reach to 1.47 m and change convex barrel to gentle concave sweep.
col=components['awning'];e=next(e for e in catalog if e['key']=='awning');pv=Vector(e['design_pivot'])
for o in col.objects:
 for v in o.data.vertices:
  q=v.co+pv;t=min(1,max(0,-q.y/2.0));q.y*=.735;q.z-=.36*math.sin(math.pi*t);v.co=q-pv
# Same clay-like palette; temper yellow border rather than inventing additional colour material.
current=components['main_sign']
for o in current.objects:
 if o.get('palette_color')=='gold':finish(o,'yellow',o['role'])
# Normalize, record exact geometry, freeze actual per-instance style counts.
layout=[]
for e in catalog:
 col=components[e['key']];pts=[v.co for o in col.objects for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in col.objects:o.data.transform(Matrix.Translation(-shift))
 for o in sc.objects:
  if o.instance_type=='COLLECTION' and o.instance_collection==col:o.location+=o.rotation_euler.to_matrix()@shift
 e['design_pivot']=[e['design_pivot'][i]+shift[i] for i in range(3)];e['bounds_size']=list(hi-lo);e['meshes']=len(col.objects);e['triangles']=e['polygons']=0;h=hashlib.sha256()
 for o in col.objects:
  o.data.calc_loop_triangles();e['triangles']+=len(o.data.loop_triangles);e['polygons']+=len(o.data.polygons)
  for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
 e['geometry_fingerprint']=h.hexdigest()
for o in sc.objects:
 if o.instance_type=='COLLECTION':
  e=next(e for e in catalog if e['collection']==o.instance_collection.name);layout.append({'name':o.name,'key':e['key'],'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
for e in catalog:e['instance_count']=sum(x['key']==e['key'] for x in layout)
P['dimensions']['awning_reach_m']=1.5;P['dimensions']['main_sign_visible_text_m']=[7.3,1.6]
eligible=[x for x in layout if next(e for e in catalog if e['key']==x['key'])['group']!='plant'];selected=[x for x in eligible if next(e for e in catalog if e['key']==x['key']).get('rho',0)]
P['actual_form_selection']={'eligible_instances':len(eligible),'selected_instances':len(selected),'ratio':len(selected)/len(eligible),'definition_ratio':10/45}
assert .20<=len(selected)/len(eligible)<=.25
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians; Z is vertical','godot_mapping':'(x,y,z)->(x,z,-y)','placement_owner':'Godot TSCN after future integration'},'instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Source viewport and source camera stay at the approved reference composition.
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(D/'bld_20261109_a.blend'),compress=True)
sc.render.filepath=str(W/'hero.png');bpy.ops.render.render(write_still=True)
print('BLDA_FINAL',json.dumps({'components':len(catalog),'instances':len(layout),'style':P['actual_form_selection']}),flush=True)
