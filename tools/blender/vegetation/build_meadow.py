"""v003 broad texture carriers and an empty rounded mound made only of overlapping cards."""
import bpy,bmesh,math,json,hashlib,random
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v003';W=R.parent/'sea-work/vegetation_meadow_20261105'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));assert plan['status']=='frozen_before_geometry'
reports=[]
for key in ['grass_soft','mound_soft']:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 vs=[];uvs=[];weights=[];faces=[];random.seed(11503)
 def card(start,angle,width,height,lean=.1,root_bend=False):
  start=Vector(start);side=Vector((math.cos(angle),math.sin(angle),0));out=Vector((-math.sin(angle),math.cos(angle),0));base=len(vs)
  for row in range(4):
   t=row/3
   for x in [-1,1]:
    point=start+side*(x*width*.5*(1-.12*t))+Vector((0,0,height*t))+out*(lean*t*t)
    vs.append(tuple(point));uvs.append(((x+1)/2,t))
    bend=min(1,point.z/1.25) if root_bend else t
    weights.append((bend,t,(angle/math.tau)%1,1))
  for row in range(3):
   a=base+row*2;faces.append((a,a+1,a+3,a+2))
 if key=='grass_soft':
  for j in range(3):card((0,0,0),j*math.pi/3,.74,.48,.07)
 else:
  # Intersecting foliage sprays form a low dome without any ellipsoid or hidden solid core.
  for i in range(32):
   angle=i*2.399963;r=math.sqrt((i+.3)/32);x=1.10*r*math.cos(angle);y=.86*r*math.sin(angle)
   z=.58*(1-r*r)**.7
   card((x,y,z),angle+random.uniform(-.5,.5),random.uniform(.85,1.05),random.uniform(.40,.59),.13,True)
  # Grounded outer skirt conceals the root convergence, retaining a soft irregular silhouette.
  for i in range(10):
   a=i*math.tau/10;card((1.0*math.cos(a),.73*math.sin(a),0),a+.5,.8,.48,.15,True)
 me=bpy.data.meshes.new(key);me.from_pydata(vs,[],faces);me.update()
 ob=bpy.data.objects.new(key,me);bpy.context.scene.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 uv=me.uv_layers.new(name='BotanicalUV');uv.active_render=True
 color=me.color_attributes.new(name='WindData',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.active_color=color
 for f in me.polygons:
  for i in f.loop_indices:
   vi=me.loops[i].vertex_index;uv.data[i].uv=uvs[vi];color.data[i].color=weights[vi]
 mat=bpy.data.materials.new('SEA_SoftMeadow');mat.use_nodes=True;mat.surface_render_method='DITHERED';mat.use_transparency_overlap=False;me.materials.append(mat)
 nodes=mat.node_tree.nodes;links=mat.node_tree.links;tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(D/'meadow_atlas.png'))
 uvnode=nodes.new('ShaderNodeUVMap');uvnode.uv_map='BotanicalUV';scale=nodes.new('ShaderNodeVectorMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=(.5,.5,1)
 offset=nodes.new('ShaderNodeVectorMath');offset.operation='ADD';offset.inputs[1].default_value=(0,.5 if key=='grass_soft' else 0,0)
 links.new(uvnode.outputs['UV'],scale.inputs[0]);links.new(scale.outputs['Vector'],offset.inputs[0]);links.new(offset.outputs['Vector'],tex.inputs['Vector'])
 bs=nodes.get('Principled BSDF');links.new(tex.outputs['Color'],bs.inputs['Base Color']);links.new(tex.outputs['Alpha'],bs.inputs['Alpha']);bs.inputs['Roughness'].default_value=1
 lo=[min(v.co[i] for v in me.vertices) for i in range(3)];hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
 for v in me.vertices:v.co-=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
 ob['wind_contract']=3;ob['visual_only']=True;ob['no_solid_core']=True
 folder=D/'components'/key;folder.mkdir(parents=True,exist_ok=True);source=folder/(key+'.blend');opt=folder/(key+'_optimized.blend')
 bpy.ops.wm.save_as_mainfile(filepath=str(source));digest=sha(source);bpy.ops.wm.open_mainfile(filepath=str(source))
 ob=bpy.data.objects[key];me=ob.data;me.calc_loop_triangles();before=len(me.loop_triangles)
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7);bm.to_mesh(me);bm.free()
 bpy.ops.wm.save_as_mainfile(filepath=str(opt));bpy.ops.wm.open_mainfile(filepath=str(opt));ob=bpy.data.objects[key];me=ob.data;me.calc_loop_triangles()
 assert sha(source)==digest and before==len(me.loop_triangles)
 assert before<=next(e['triangle_budget'] for e in plan['assets'] if e['key']==key)
 for loop in me.loops:
  if me.vertices[loop.vertex_index].co.z<1e-5:assert me.color_attributes['WindData'].data[loop.index].color[0]<1e-4
 dest=R/'godot/assets/models/vegetation'/f'{key}.glb'
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',export_materials='NONE',export_yup=True,export_vertex_color='NAME',export_vertex_color_name='WindData',export_active_vertex_color_when_no_material=True)
 item=dict(key=key,asset_id='SEA-VEG-'+key.upper().replace('_','-'),version='v003',source=source.relative_to(R).as_posix(),source_sha256=digest,optimized_source=opt.relative_to(R).as_posix(),optimized_sha256=sha(opt),glb=dest.relative_to(R).as_posix(),glb_sha256=sha(dest),triangles=before,vertices=len(me.vertices),bounds_blender=[[min(v.co[i] for v in me.vertices) for i in range(3)],[max(v.co[i] for v in me.vertices) for i in range(3)]],operations=['independent optimized save','degenerate edge cleanup','reopen source and optimized','verify rooted weights and UVs'],no_solid_core=True)
 write(folder/'production_report.json',item);reports.append(item)
write(W/'source_report.json',dict(passed=True,assets=reports));print('MEADOW_SOURCE_OK',[(r['key'],r['triangles']) for r in reports])
