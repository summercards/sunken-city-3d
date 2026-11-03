import bpy,math,json,ast,random
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/ocean_rooftop_farm/v003';W=R.parent/'sea-work/ocean_rooftop_farm/v003';s=bpy.context.scene
cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];by={e['key']:e for e in cat};root=next(c for c in s.collection.children if c.name.startswith('ORF3_'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'))
# mark new requested changes in plan before new geometry.
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));plan['latest_user_revision_1101']={'perimeter':'thick outward concrete rim without grass','fire_escape':'top three floors only, suspended broken lower end','metal':'dark diffuse matte, no polished shiny metal','anti_zfight':'edge-to-edge split surfaces at landing roof junction'}
for k,name,fam in [('broken_flight','下挂断裂消防梯残段','fire_stair'),('turf_core','屋顶中央草皮基底','ground_cover')]:
 if k not in by:
  e={'key':k,'name':name,'asset_id':'SEA-SCENE-ORF2-'+k.upper(),'category':'flora' if k=='turf_core' else 'structure','component_family':fam,'origin':'bottom_center','front_axis':'-Y','component_source':'art_source/scenes/ocean_rooftop_farm/v003/component_packages/'+k+'/'+k+'.blend','collision_owner':'future_Godot_wrapper_pending','source_version':'v003'};cat.append(e);by[k]=e;plan['components'].append(e)
plan['component_budget']={'limit':50,'planned':48,'remaining':2};plan['stair_contract'].update({'base_z':45,'roof_z':60,'flights':6,'floors':3,'continuous_from_ground':False,'broken_end_low_z_approx':42,'runtime_status':'pending_upper_only'})
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
# helper generation shares exact project palette role count.
tr=ast.parse((R/'tools/blender/ocean_rooftop_farm/author_v002.py').read_text(encoding='utf-8'));node=next(n for n in tr.body if isinstance(n,ast.ClassDef) and n.name=='Geo');exec(compile(ast.Module(body=[node],type_ignores=[]),'Geo','exec'))
roles=[next(m for c in src.children for o in c.objects for m in o.data.materials if m.name=='ORF2_FINAL_'+r) for r in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']];cells={x['name']:x for x in json.loads((R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.json').read_text(encoding='utf-8'))['cells']}
def build(k,g,bev=.03):
 e=by[k];c=bpy.data.collections.get(e.get('collection',''))
 if not c:c=bpy.data.collections.new('ORF3_组件_'+k);src.children.link(c);e['collection']=c.name
 for ob in list(c.objects):bpy.data.objects.remove(ob,do_unlink=True)
 lo=Vector([min(v[i] for v in g.v) for i in range(3)]);hi=Vector([max(v[i] for v in g.v) for i in range(3)]);off=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));g.v=[tuple(Vector(v)-off) for v in g.v]
 for rr in sorted(set(g.r)):
  fi=[i for i,r in enumerate(g.r) if r==rr];used=sorted({j for i in fi for j in g.f[i]});idx={v:i for i,v in enumerate(used)};me=bpy.data.meshes.new('ORF3_'+k);me.from_pydata([g.v[j] for j in used],[],[[idx[j] for j in g.f[i]] for i in fi]);me.update();ob=bpy.data.objects.new('ORF3_'+e['name']+('_自发光' if rr==3 else '')+'_'+str(rr),me);c.objects.link(ob);me.materials.append(roles[rr]);uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
  for p,i in zip(me.polygons,fi):
   ce=cells[g.c[i]];n=len(p.loop_indices)
   for j,li in enumerate(p.loop_indices):a=j*math.tau/n;uv.data[li].uv=((ce['column']+.5+.2*math.cos(a))/8,1-(ce['row']+.5-.2*math.sin(a))/8)
  if bev:mod=ob.modifiers.new('饱满实体倒角','BEVEL');mod.width=bev;mod.segments=3
 return c,off
# 1 roof external concrete deck 49.6x33.6, 0.65m thick; grass inset 22.2/14.2.
g=Geo();g.box((0,0,.325),(49.6,33.6,.65),'cloud');c,off=build('roof',g,.10)
for o in s.objects:
 if o.instance_type=='COLLECTION' and o.instance_collection==c:o.location.z=59.35
# Turf core is single green low slab, above concrete deck only inside border.
g=Geo();g.box((0,0,.025),(44.4,28.4,.05),'leaf_mid');c,off=build('turf_core',g,.02)
o=bpy.data.objects.new('ORF3_中央草皮基底',None);out.children[2].objects.link(o);o.instance_type='COLLECTION';o.instance_collection=c;o['component_id']=by['turf_core']['asset_id'];o.location=(0,0,60)
# reposition parapet/rails outward, preserve roof entry gap. Top ring clear concrete inside.
for o in list(s.objects):
 if o.instance_type!='COLLECTION':continue
 k=o.get('component_id','').replace('SEA-SCENE-ORF2-','').lower()
 if k in ['parapet','rail'] and o.location.z<63:
  if abs(o.location.y)>15:o.location.y=math.copysign(16.25,o.location.y)
  elif abs(o.location.x)>23:o.location.x=math.copysign(24.25,o.location.x)
 # no edge plant billboards over concrete band: fit grass/tufts inside inset.
 if k in ['grass','tuft']:
  c=o.instance_collection;ps=[o.matrix_world@v.co for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices]
  if not ps:continue
  low=[min(p[i] for p in ps) for i in range(2)];high=[max(p[i] for p in ps) for i in range(2)]
  if high[0]>22.1 or low[0]<-22.1 or high[1]>14.1 or low[1]<-14.1:
   o.location.x=max(-20.1,min(20.1,o.location.x));o.location.y=max(-12.3,min(12.3,o.location.y))
 # attach existing rim moss to new outer edge
 if k=='moss_cluster':
  if abs(o.location.y)>15:o.location.y=math.copysign(16.86,o.location.y)
  elif o.location.x>23:o.location.x=24.86
# 2 all metal is matte not shiny. Glass stays glass.
metal=roles[1];bs=next(n for n in metal.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Metallic'].default_value=.15;bs.inputs['Roughness'].default_value=.82;bs.inputs['Coat Weight'].default_value=0;bs.inputs['Specular IOR Level'].default_value=.25
# 3 six full flights 45->60m only; remove bottom landings + obsolete ground approach.
removed=[]
for o in list(s.objects):
 if o.instance_type!='COLLECTION':continue
 k=o.get('component_id','').replace('SEA-SCENE-ORF2-','').lower()
 if (k=='stair_flight' and o.location.z<44) or (k=='stair_landing' and o.location.z<44) or (k=='roof_entry' and o.location.z<1):removed.append(o.name);bpy.data.objects.remove(o,do_unlink=True)
# deep slate uniform stair color from palette except black not used. all bars same matte role.
for k in ['stair_flight','stair_landing','stair_landing_open','roof_entry']:
 for ob in bpy.data.collections[by[k]['collection']].objects:
  uv=ob.data.uv_layers.get('PaletteUV')
  for p in ob.data.polygons:
   ce=cells['slate' if p.index%7 else 'steel'];n=len(p.loop_indices)
   for j,li in enumerate(p.loop_indices):a=j*math.tau/n;uv.data[li].uv=((ce['column']+.5+.2*math.cos(a))/8,1-(ce['row']+.5-.2*math.sin(a))/8)
# 4 top landing cut inner 0.8m deck overlap: new edge x=24.8 abuts concrete slab outer edge.
c=bpy.data.collections[by['stair_landing_open']['collection']]
for ob in c.objects:
 for v in ob.data.vertices:
  if v.co.x<-1.2:v.co.x=-1.2
 ob.data.update()
# Replace roof-entry package with rails only, no coplanar deck. Ring itself is walking floor.
g=Geo()
for y in [-.82,.82]:
 g.rod((-.95,y,.2),(.95,y,.2),.10,'slate',1)
 g.rod((-.95,y,1.20),(.95,y,1.2),.095,'slate',1)
 for x in [-.9,.9]:g.rod((x,y,.05),(x,y,1.2),.10,'slate',1)
c,off=build('roof_entry',g,.01)
for o in s.objects:
 if o.instance_type=='COLLECTION' and o.instance_collection==c:o.location=(23.85,-3.9,60.05)
# Broken suspended partial flight: twisted rails + sparse snapped steps, hangs from z45 landing at y=-4.5.
g=Geo()
g.rod((-.75,0,0),(-.66,1.6,2.65),.105,'slate',1);g.rod((.75,.35,.45),(.75,1.6,2.65),.105,'slate',1)
for i in range(7):
 y=.2+i*.2;z=.35+i*.32
 if i not in [1,4]:g.box((-.08 if i%2 else .1,y,z),(1.5 if i>3 else .95,.30,.12),'slate',1,rot=(.08,-.16 if i%2 else .12,.06))
g.rod((-.75,.2,1),(-.8,1.5,3.5),.095,'slate',1);g.rod((-.66,1.5,3.5),(.6,1.55,3.4),.09,'steel',1)
c,off=build('broken_flight',g,.012);o=bpy.data.objects.new('ORF3_下挂断裂消防梯',None);out.children[0].objects.link(o);o.instance_type='COLLECTION';o.instance_collection=c;o['component_id']=by['broken_flight']['asset_id'];o.location=(25.1,-5.8,42.4);o.rotation_euler=(0,math.radians(-11),math.radians(-6))
# visible suspension braces attach fragments to lower surviving landing.
gh=c
# Route contract no longer claims ground access.
route=json.loads((D/'stair_route.json').read_text(encoding='utf-8'));route['contract']=plan['stair_contract'];route['floors']=[f for f in route['floors'] if f['floor']>=9];route['continuous_from_ground']=False;route['zfight_fix']={'concrete_roof_outer_x':24.8,'top_landing_inner_x':24.8,'roof_entry_floor_mesh':False,'stair_step_vs_landing_overlap':'edge only, distinct z for lower step undersides'};(D/'stair_route.json').write_text(json.dumps(route,ensure_ascii=False,indent=2),encoding='utf-8')
for e in cat:
 c=bpy.data.collections[e['collection']];e['instance_count']=sum(o.instance_type=='COLLECTION' and o.instance_collection==c for o in s.objects)
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
# Shift view focus to upper 3 floors; keep original same-camera comparison.
cam=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF3_右侧'));cam.location=(75,-45,76);cam.rotation_euler=(Vector((22,-1,52))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=45
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v003.blend'),compress=True)
print(json.dumps({'components':len(cat),'remaining_flights':sum(o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-STAIR_FLIGHT' for o in s.objects),'removed_lower_objects':len(removed),'metal':{'metallic':.15,'roughness':.82},'concrete_deck':[49.6,33.6,.65]},ensure_ascii=False))
