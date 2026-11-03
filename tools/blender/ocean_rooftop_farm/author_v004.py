"""Local state split on live v003. Existing tower and non-upgrade furniture locked."""
import bpy,json,math,ast,random,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/ocean_rooftop_farm/v004';W=R.parent/'sea-work/ocean_rooftop_farm/v004';D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
s=bpy.context.scene;assert 'v003' in s.name,'Run once on backed-up v003'
old=json.loads((D.parent/'v003/component_catalog.json').read_text(encoding='utf-8'))['components'];by={e['key']:dict(e) for e in old};root=next(c for c in s.collection.children if c.name.startswith('ORF3_'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'));qa=next(c for c in root.children if c.name.startswith('90_'))
# Freeze new semantic component plan BEFORE new geometry. Omit removed crop definitions; upper terrace solar stays.
removed_keys={'bed','field','cabbage','seedling','tomato','greenhouse','tank'}
newdefs=[('greenhouse_unbuilt','温室_升级前_待建木料堆','greenhouse_upgrade','unbuilt'),('greenhouse_complete','温室_升级后_完整设施','greenhouse_upgrade','complete'),('water_tower_unbuilt','水塔_升级前_卧放罐体与木支架材料','water_tower_upgrade','unbuilt'),('water_tower_complete','水塔_升级后_已搭建','water_tower_upgrade','complete')]
plan=json.loads((D.parent/'v003/component_plan.json').read_text(encoding='utf-8'));plan.update({'version':'v004','status':'frozen_before_state_geometry','parent_source':'v003/ocean_rooftop_farm_v003.blend','latest_revision':'clear red-framed beds/crops/right rooftop solar to ordinary turf; greenhouse and water tower independent mutually exclusive upgrade states','components':[e for e in plan['components'] if e['key'] not in removed_keys]})
for k,name,family,state in newdefs:
 e={'key':k,'name':name,'asset_id':'SEA-SCENE-ORF2-'+k.upper(),'category':'fixture','component_family':family,'variant_axis':'upgrade_state','variant_value':state,'variant_reason':'independent before/after visual models for future upgrade swap','scope':'scene_local','origin':'bottom_center','front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270],'collision_owner':'future_Godot_upgrade_wrapper_pending','building_class':'above_water'};plan['components'].append(e);by[k]=e
plan['component_budget']={'limit':50,'planned':len(plan['components']),'remaining':50-len(plan['components'])};plan['scope_contract']={'remove':['roof bed frames and soil','outdoor crops','inside-greenhouse crops','six solar panels on main grass roof'],'keep':['two upper-terrace solar panels not circled','tower facade','roof concrete rim','fire escape upper three floors','all stone/timber footpaths','ordinary turf','other furniture/plants'],'upgrade_pairs':['greenhouse','water_tower'],'game_logic':'pending_not_changed'}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
# New output state groups: disabled state collections do not affect source geometry references.
states={}
for family in ['greenhouse','water_tower']:
 parent=bpy.data.collections.new('ORF4_独立升级资产_'+family);out.children.link(parent);states[family]={}
 for state in ['unbuilt','complete']:
  c=bpy.data.collections.new('ORF4_'+family+'_'+state);parent.children.link(c);states[family][state]=c
# capture original built facilities as complete independently editable mesh groups. No external dependency on tower.
def complete(k,oldkey):
 sourceinst=[o for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-'+oldkey.upper()]
 c=bpy.data.collections.new('ORF4_组件_'+k);src.children.link(c);objects=[];points=[]
 for instance in sourceinst:
  for ob in instance.instance_collection.objects:
   if ob.type!='MESH':continue
   cp=ob.copy();cp.data=ob.data.copy();cp.name='ORF4_'+by[k]['name']+'_'+str(len(objects));cp.data.transform(instance.matrix_world@ob.matrix_world);cp.location=(0,0,0);cp.rotation_euler=(0,0,0);cp.scale=(1,1,1);cp.parent=None;c.objects.link(cp);objects.append(cp);points.extend(v.co.copy() for v in cp.data.vertices)
 lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)]);anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for ob in objects:
  for v in ob.data.vertices:v.co-=anchor
 by[k]['collection']=c.name;return c,anchor
builtgh,ghanchor=complete('greenhouse_complete','greenhouse');builtwt,wtanchor=complete('water_tower_complete','tank')
# Remove only authorized instances, preserve other original objects byte-exact geometry/transforms.
removed=[]
for o in list(s.objects):
 if o.instance_type!='COLLECTION':continue
 key=o.get('component_id','').replace('SEA-SCENE-ORF2-','').lower()
 if key in removed_keys or (key=='solar' and o.location.z<63):removed.append({'name':o.name,'key':key});bpy.data.objects.remove(o,do_unlink=True)
# Primitive builder class only, never execute old scene generator.
tr=ast.parse((R/'tools/blender/ocean_rooftop_farm/author_v002.py').read_text(encoding='utf-8'));nd=next(n for n in tr.body if isinstance(n,ast.ClassDef) and n.name=='Geo');exec(compile(ast.Module(body=[nd],type_ignores=[]),'Geo','exec'))
roles=[next(m for c in src.children for ob in c.objects for m in ob.data.materials if m.name=='ORF2_FINAL_'+r) for r in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']];cells={x['name']:x for x in json.loads((R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.json').read_text(encoding='utf-8'))['cells']}
def build(k,g):
 c=bpy.data.collections.new('ORF4_组件_'+k);src.children.link(c);by[k]['collection']=c.name;lo=Vector([min(v[i] for v in g.v) for i in range(3)]);hi=Vector([max(v[i] for v in g.v) for i in range(3)]);offset=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));g.v=[tuple(Vector(v)-offset) for v in g.v]
 for rr in sorted(set(g.r)):
  fi=[i for i,r in enumerate(g.r) if r==rr];used=sorted({v for i in fi for v in g.f[i]});idx={v:i for i,v in enumerate(used)};me=bpy.data.meshes.new('ORF4_'+k);me.from_pydata([g.v[i] for i in used],[],[[idx[v] for v in g.f[i]] for i in fi]);me.update();ob=bpy.data.objects.new('ORF4_'+by[k]['name']+'_'+str(rr),me);c.objects.link(ob);me.materials.append(roles[rr]);uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
  for p,i in zip(me.polygons,fi):
   ce=cells[g.c[i]];n=len(p.loop_indices)
   for j,li in enumerate(p.loop_indices):a=j*math.tau/n;uv.data[li].uv=((ce['column']+.5+.2*math.cos(a))/8,1-(ce['row']+.5-.2*math.sin(a))/8)
  b=ob.modifiers.new('饱满圆角_三段','BEVEL');b.width=.035;b.segments=3
 return c
random.seed(110313)
g=Geo()
# broad stacked aged boards, no greenhouse wall frame assembled.
for layer in range(3):
 for j in range(4):g.box((random.uniform(-.10,.10),-.95+j*.58,.14+layer*.25),(random.uniform(3.6,4.8),.42,.23),['wood_light','wood_mid','wood_dark'][(j+layer)%3],rot=(0,0,random.uniform(-.07,.07)))
for i in range(4):g.box((-1.0+i*.7,.5,.65+i*.05),(.20,2.7,.20),'wood_dark',rot=(0,.03,random.uniform(-.22,.22)))
# salvaged short beams and flat door planks, still a timber pile rather than house.
g.box((1.65,1.25,.23),(1.6,.8,.32),'wood_mid',rot=(0,0,-.18));ghpile=build('greenhouse_unbuilt',g)
g=Geo()
# tank on its side, with separated rings and all structural timber lying flat.
g.rod((-1.15,-.65,1.48),(1.15,-.65,1.48),1.35,'silver',1,24,1.28)
g.rod((-1.27,-.65,1.48),(-1.12,-.65,1.48),1.40,'slate',1,24)
g.rod((1.15,-.65,1.48),(1.28,-.65,1.48),1.34,'slate',1,24)
g.rod((1.30,-.65,1.48),(1.75,-.65,1.48),1.36,'gray',1,24,.08)
# lumber bundle plus diagonal braces: nothing stands up.
for j in range(5):g.box((random.uniform(-.15,.15),1.4+j*.24,.16+(.26 if j%2 else 0)),(3.4,.22,.26),'wood_dark' if j%2 else 'wood_mid',rot=(0,0,random.uniform(-.08,.08)))
for j in range(3):g.box((-.3+j*.45,1.8,.61),(.16,2.3,.18),'wood_light',rot=(0,0,-.20+j*.15))
wtpile=build('water_tower_unbuilt',g)
# Attach paired mutually exclusive state instances using EXACT same socket transform within each pair.
pairs=[]
for family,anchor,before,after in [('greenhouse',ghanchor,'greenhouse_unbuilt','greenhouse_complete'),('water_tower',wtanchor,'water_tower_unbuilt','water_tower_complete')]:
 entries={}
 for state,key in [('unbuilt',before),('complete',after)]:
  o=bpy.data.objects.new('ORF4_'+by[key]['name'],None);states[family][state].objects.link(o);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[by[key]['collection']];o.location=anchor;o['component_id']=by[key]['asset_id'];o['upgrade_family']=family;o['upgrade_state']=state;entries[state]={'asset_id':by[key]['asset_id'],'component_key':key,'instance_name':o.name,'collection':states[family][state].name}
  states[family][state].hide_viewport=state=='complete';states[family][state].hide_render=state=='complete'
 pairs.append({'upgrade_id':'ORF-UPGRADE-'+family.upper(),'family':family,'socket_world_blender':list(anchor),'socket_world_godot':[anchor.x,anchor.z,-anchor.y],'local_pivot':'bottom_center','placement_rotation_euler_xyz':[0,0,0],'placement_scale':[1,1,1],'default_state':'unbuilt','states':entries,'state_switch':'mutually_exclusive_replace_only','runtime_logic':'pending_no_cost_or_production_rules_changed'})
# detach removed definition collections from authoring tree (old files remain untouched)
for key in removed_keys:
 c=bpy.data.collections[by[key]['collection']]
 if c.name in src.children:src.children.unlink(c)
cat=[]
for eplan in plan['components']:
 key=eplan['key'];e=by[key];c=bpy.data.collections[e['collection']];pts=[v.co for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices];e.update({'component_source':str((D/'component_packages'/key/(key+'.blend')).relative_to(R)).replace('\\','/'),'source_version':'v004','bounds_size_m':[max(v[i] for v in pts)-min(v[i] for v in pts) for i in range(3)],'instance_count':sum(o.instance_type=='COLLECTION' and o.instance_collection==c for o in s.objects),'geometry_fingerprint':hashlib.sha256(repr([[tuple(round(x,6) for x in v.co) for v in ob.data.vertices] for ob in c.objects if ob.type=='MESH']).encode()).hexdigest()});cat.append(e)
assert len(cat)==45 and len(src.children)==45
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
(D/'upgrade_states.json').write_text(json.dumps({'schema':'sea.upgrade_asset_states','source_only':True,'default_state':'unbuilt','pairs':pairs,'constraints':['Only one state for each family may be visible/exported at runtime','Building base export excludes all four upgrade state meshes','Completed greenhouse comprises both old greenhouse modules, zero crop meshes','Water tower state models have no tall erected beams before upgrade'],'removed_instances':removed},ensure_ascii=False,indent=2),encoding='utf-8')
# Independent building base collection boundary; entire clean roof can be exported without upgraded assets.
out['base_collections']=[c.name for c in out.children if not c.name.startswith('ORF4_独立升级')];out['upgrade_manifest']='upgrade_states.json'
s.name='海上屋顶农场_普通草皮与独立升级_v004';root.name='ORF4_屋顶农场_中文资产管理'
# hide source library layer remains set from original scene.
for lc in bpy.context.view_layer.layer_collection.children:
 for ch in lc.children:
  if ch.collection==src:ch.exclude=True
instances=[{'name':o.name,'component_id':o.get('component_id'),'position_m':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale),'upgrade_family':o.get('upgrade_family'),'upgrade_state':o.get('upgrade_state')} for o in s.objects if o.instance_type=='COLLECTION'];(D/'component_instances.json').write_text(json.dumps({'instances':instances,'coordinate_mapping':'(x,y,z)->(x,z,-y)'},ensure_ascii=False,indent=2),encoding='utf-8')
s['upgrade_default_state']='unbuilt';s['upgrade_manifest']=str(D/'upgrade_states.json')
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v004.blend'),compress=True)
print(json.dumps({'file':bpy.data.filepath,'components':len(cat),'removed_instances':len(removed),'upper_terrace_solar_kept':sum(o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-SOLAR' for o in s.objects),'pairs':pairs},ensure_ascii=False))
