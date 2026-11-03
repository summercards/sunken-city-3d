"""Independent saved-file Blender probe. Never modifies the source."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v002');W=Path('D:/projects/sea-work/ocean_rooftop_farm/v002');W.mkdir(parents=True,exist_ok=True)
main=D/'ocean_rooftop_farm_v002.blend';before=hashlib.sha256(main.read_bytes()).hexdigest();palette=Path('D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png');ph=hashlib.sha256(palette.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(main));s=bpy.context.scene
cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));records=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
checks=[]
def check(name,ok,detail=None):checks.append({'check':name,'passed':bool(ok),'detail':detail})
def audit(c):
 bad=[];faces=0;materials=set();images=set();pts=[];tri=0
 for o in c.all_objects:
  if o.type!='MESH':continue
  if any(abs(x)>1e-6 for x in o.location) or any(abs(x)>1e-6 for x in o.rotation_euler) or any(abs(x-1)>1e-6 for x in o.scale):bad.append([o.name,'transform'])
  me=o.data;uv=me.uv_layers.get('PaletteUV')
  if not uv or len(me.uv_layers)!=1 or me.uv_layers.active!=uv or not uv.active_render:bad.append([o.name,'uv_layer']);continue
  for p in me.polygons:
   faces+=1;u=[uv.data[li].uv for li in p.loop_indices];grid={(math.floor(v.x*8),math.floor(v.y*8)) for v in u};area=abs(sum(u[i].x*u[(i+1)%len(u)].y-u[(i+1)%len(u)].x*u[i].y for i in range(len(u))))*.5
   if len(grid)!=1 or area<1e-8 or not all(.125<=((v.x*8)%1)<=.875 and .125<=((v.y*8)%1)<=.875 for v in u):
    if len(bad)<20:bad.append([o.name,p.index,'uv_safety_or_area'])
  for mat in me.materials:
   materials.add(mat.name)
   for n in mat.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:
     imagepath=Path(bpy.path.abspath(n.image.filepath));images.add(str(imagepath))
     if not imagepath.is_file() or imagepath.resolve()!=palette.resolve() or n.interpolation!='Closest' or n.image.packed_file:bad.append([o.name,'external_palette',str(imagepath)])
   uvnodes=[n for n in mat.node_tree.nodes if n.type=='UVMAP']
   if not uvnodes or any(n.uv_map!='PaletteUV' for n in uvnodes):bad.append([o.name,'material_uv_node'])
  pts.extend(o.matrix_world@v.co for v in me.vertices)
  dep=bpy.context.evaluated_depsgraph_get();ev=o.evaluated_get(dep);mesh=ev.to_mesh();mesh.calc_loop_triangles();tri+=len(mesh.loop_triangles);ev.to_mesh_clear()
 return {'faces':faces,'triangles':tri,'materials':sorted(materials),'palette_images':list(images),'errors':bad,'bounds_low':[min(p[i] for p in pts) for i in range(3)] if pts else None,'bounds_high':[max(p[i] for p in pts) for i in range(3)] if pts else None}
root=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'))
check('fresh_source_39_components',len(cat)==39 and len(src.children)==39)
check('budget_under_50',len(cat)<=50)
check('latest_dimension_contract',plan['dimensions']['roof_top_z_m']==60 and plan['dimensions']['building_xy_m']==[48,32])
inst=[o for o in s.objects if o.instance_type=='COLLECTION'];check('instance_manifest_count',len(inst)==len(records),[len(inst),len(records)])
check('output_contains_instances_only',all(o.type=='EMPTY' and o.instance_type=='COLLECTION' for o in out.all_objects))
check('no_animals_people_or_background',not any(any(x in o.name.lower() for x in ['animal','ocean','seabird','person','backgroundmesh']) for o in out.all_objects))
# Temporarily include authoring library for dependency-graph evaluation, without saving.
def activate(lc):
 if lc.collection==src:lc.exclude=False
 for child in lc.children:activate(child)
activate(bpy.context.view_layer.layer_collection);bpy.context.view_layer.update()
results={};total=0
for e in cat:
 c=bpy.data.collections.get(e['collection']);r=audit(c);results[e['key']]=r;total+=r['triangles']*e['instance_count'];check('component_'+e['key'],not r['errors'] and bool(r['faces']) and all(abs(x)<1e-7 for x in c.instance_offset),r['errors'][:5])
 check('origin_'+e['key'],abs(r['bounds_low'][2])<.025 and abs(r['bounds_low'][0]+r['bounds_high'][0])<.06 and abs(r['bounds_low'][1]+r['bounds_high'][1])<.06,r['bounds_low'])
roles=sorted({m for r in results.values() for m in r['materials']});check('four_material_roles',len(roles)<=4,roles)
check('no_dot001_material_roles',all('.001' not in n for n in roles),roles)
# world-space roof and tank inclinations checked from actual instances, not source comments
roofs=[o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-ROOF'];check('roof_top_60m',len(roofs)==1 and abs(roofs[0].location.z+results['roof']['bounds_high'][2]-60)<.001)
green=[o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-GREENHOUSE'];tank=[o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-TANK'];check('greenhouse_3deg',len(green)==2 and all(abs(math.degrees(o.rotation_euler.y)-3)<.001 for o in green));check('water_tower_minus4deg',len(tank)==1 and abs(math.degrees(tank[0].rotation_euler.y)+4)<.001)
# independent component files actually reopened.
packages=[]
for e in cat:
 file=D/'component_packages'/e['key']/(e['key']+'.blend');h=hashlib.sha256(file.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(file));cc=next(c for c in bpy.context.scene.collection.children if c.name.startswith('02_游戏输出'));r=audit(cc);ok=not r['errors'] and r['faces']>0;check('package_reopen_'+e['key'],ok,r['errors'][:4]);packages.append({'key':e['key'],'sha256':h,'passed':ok,'faces':r['faces'],'triangles':r['triangles']})
check('master_hash_unchanged',before==hashlib.sha256(main.read_bytes()).hexdigest());check('palette_hash_unchanged',ph==hashlib.sha256(palette.read_bytes()).hexdigest())
report={'passed':all(x['passed'] for x in checks),'source_sha256':before,'palette_sha256':ph,'checks':checks,'components':results,'packages':packages,'component_count':39,'instance_count':len(inst),'expanded_triangles':total,'material_roles':roles,'runtime_status':'pending_not_imported','commercial_reference_rights':'pending','visual_review':'four_saved_renders_reviewed_separately'}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print('ORF2_VERIFY',json.dumps({'passed':report['passed'],'checks':len(checks),'failed':[c for c in checks if not c['passed']],'triangles':total,'instances':len(inst)},ensure_ascii=False))
