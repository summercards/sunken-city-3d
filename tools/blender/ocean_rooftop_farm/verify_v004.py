"""Read-only independent reopen audit of source, base building and upgrade packages."""
import bpy,json,math,hashlib,ast
from pathlib import Path
from mathutils import Vector
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v004');W=Path('D:/projects/sea-work/ocean_rooftop_farm/v004');palette=Path('D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png');main=D/'ocean_rooftop_farm_v004.blend'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
before=sha(main);cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];up=json.loads((D/'upgrade_states.json').read_text(encoding='utf-8'));scope=json.loads((W/'scope.json').read_text(encoding='utf-8'));checks=[]
def check(n,ok,detail=None):checks.append({'check':n,'passed':bool(ok),'detail':detail})
# Verified independent audit implementation reused, not source generator assertions.
tree=ast.parse(Path('D:/projects/sea/tools/blender/ocean_rooftop_farm/verify_v002.py').read_text(encoding='utf-8'));nd=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='audit');exec(compile(ast.Module(body=[nd],type_ignores=[]),'independent_audit','exec'))
bpy.ops.wm.open_mainfile(filepath=str(main));s=bpy.context.scene;root=next(c for c in s.collection.children if c.name.startswith('ORF4_屋顶'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'))
def enable(lc):
 if lc.collection==src:lc.exclude=False
 for x in lc.children:enable(x)
enable(bpy.context.view_layer.layer_collection);bpy.context.view_layer.update()
check('45_unique_definitions',len(cat)==45 and len(src.children)==45 and len({e['collection'] for e in cat})==45)
check('component_budget_le50',len(cat)<=50)
inst=[o for o in s.objects if o.instance_type=='COLLECTION'];ids=[o.get('component_id') for o in inst]
removed={'SEA-SCENE-ORF2-'+k.upper() for k in ['bed','field','cabbage','seedling','tomato','greenhouse','tank']};check('no_removed_crop_or_old_facility_instances',not (set(ids)&removed),sorted(set(ids)&removed))
solar=[o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-SOLAR'];check('only_uncircled_upper_terrace_2_solar',len(solar)==2 and all(o.location.z>63 for o in solar))
check('ordinary_turf_base_present',any(o.get('component_id')=='SEA-SCENE-ORF2-TURF_CORE' for o in inst))
check('orphan_crop_irrigation_removed',not any(o.get('component_id')=='SEA-SCENE-ORF2-PIPE' and o.location.x>0 for o in inst))
results={};roles=set()
for e in cat:
 c=bpy.data.collections[e['collection']];r=audit(c);results[e['key']]=r;roles.update(r['materials']);check('component_'+e['key'],not r['errors'] and r['faces']>0,r['errors'][:5]);lo=r['bounds_low'];hi=r['bounds_high'];check('origin_'+e['key'],abs(lo[2])<1e-4 and abs(lo[0]+hi[0])<1e-4 and abs(lo[1]+hi[1])<1e-4,{'low':lo,'high':hi})
check('shared_four_roles',len(roles)==4,sorted(roles))
# Unchanged scope protects every unrelated model, only orphan irrigation exception is authorized.
lockbad=[];count=0
for row in scope['locked']:
 if row['name'] in up.get('removed_orphan_irrigation',[]):continue
 o=s.objects.get(row['name'])
 if not o:lockbad.append([row['name'],'missing']);continue
 fp=hashlib.sha256(repr([[tuple(v.co) for v in x.data.vertices] for x in o.instance_collection.objects if x.type=='MESH']).encode()).hexdigest();m=[list(v) for v in o.matrix_world]
 if fp!=row['geom'] or max(abs(m[i][j]-row['matrix'][i][j]) for i in range(4) for j in range(4))>1e-4:lockbad.append([row['name'],'geometry_or_transform'])
 count+=1
check('unrelated_building_and_furniture_locked',not lockbad,{'count':count,'failures':lockbad[:12]})
# Each state asset independent root, one matched shared socket; independent toggles never affect base.
active_counts={};tri_counts={}
for state in ['unbuilt','complete']:
 active=[]
 for pair in up['pairs']:
  obs=[]
  for st,e in pair['states'].items():
   c=bpy.data.collections[e['collection']];c.hide_render=st!=state;c.hide_viewport=st!=state;o=s.objects[e['instance_name']];obs.append(o)
   if not c.hide_render:active.append(o)
  check('matched_socket_'+pair['family']+'_'+state,max(abs(obs[0].matrix_basis[i][j]-obs[1].matrix_basis[i][j]) for i in range(4) for j in range(4))<1e-6 and obs[0].parent is None and obs[1].parent is None)
  check('state_mutually_exclusive_'+pair['family']+'_'+state,sum(not bpy.data.collections[e['collection']].hide_render for e in pair['states'].values())==1)
  check('socket_on_grass_'+pair['family'],abs(obs[0].location.z-60.05)<.001)
 active_counts[state]=len(active)
 state_keys={e['component_key'] for p in up['pairs'] for st,e in p['states'].items() if st==state};tri_counts[state]=sum(r['triangles']*next(e['instance_count'] for e in cat if e['key']==k) for k,r in results.items() if k not in {'greenhouse_unbuilt','greenhouse_complete','water_tower_unbuilt','water_tower_complete'} or k in state_keys)
check('unbuilt_tower_height_below3m',results['water_tower_unbuilt']['bounds_high'][2]<3.0)
check('built_tower_height_above5m',results['water_tower_complete']['bounds_high'][2]>5.5)
check('unbuilt_greenhouse_only_low_lumber',results['greenhouse_unbuilt']['bounds_high'][2]<1.5)
check('built_greenhouse_composite_depth8m',results['greenhouse_complete']['bounds_high'][1]-results['greenhouse_complete']['bounds_low'][1]>7.5)
# base file opened independently cannot carry state meshes by hidden collections or indirect references.
bpy.ops.wm.open_mainfile(filepath=str(D/'base_building.blend'));bs=bpy.context.scene;baseinst=[o for o in bs.objects if o.instance_type=='COLLECTION'];bad=[o.name for o in baseinst if o.get('component_id') in {v['asset_id'] for p in up['pairs'] for v in p['states'].values()}];check('standalone_base_excludes_all_upgrade_states',not bad,bad);check('base740_instances',len(baseinst)==740,len(baseinst))
base_ids={e['asset_id'] for p in up['pairs'] for e in p['states'].values()};dependency_upgrade=[c.name for c in bpy.data.collections if any(o.get('component_id') in base_ids for o in c.objects)];check('base_no_hidden_upgrade_dependency',not dependency_upgrade,dependency_upgrade)
packages=[]
for e in cat:
 f=Path('D:/projects/sea')/e['component_source'];check('package_hash_'+e['key'],sha(f)==e['source_sha256']);bpy.ops.wm.open_mainfile(filepath=str(f));c=next(c for c in bpy.context.scene.collection.children if c.name.startswith('02_游戏输出'));r=audit(c);ok=not r['errors'] and r['faces']>0;check('package_reopen_'+e['key'],ok,r['errors'][:4]);packages.append({'key':e['key'],'passed':ok,'sha256':sha(f),'triangles':r['triangles']})
check('previous_v003_source_unchanged',sha(scope['source'])==scope['old_source_sha256']);check('master_hash_unchanged',sha(main)==before)
report={'passed':all(c['passed'] for c in checks),'source_sha256':before,'base_source_sha256':sha(D/'base_building.blend'),'component_count':len(cat),'instance_count':len(inst),'base_instances':len(baseinst),'visible_state_instances':active_counts,'expanded_triangles_by_state':tri_counts,'material_roles':sorted(roles),'checks':checks,'components':results,'packages':packages,'runtime_status':'pending_no_Godot_import','upgrade_logic_status':'not_implemented_source_asset_states_only'}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print('ORF4_VERIFY',json.dumps({'passed':report['passed'],'checks':len(checks),'failed':[c for c in checks if not c['passed']],'triangles':tri_counts},ensure_ascii=False))
