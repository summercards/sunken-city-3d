"""v002: only flexible texture carriers, never individual modeled grass blades."""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v002';W=R.parent/'sea-work/vegetation_soft_20261105'
assert not (R/'art_source/vegetation/v003/component_plan.json').exists(), 'v002 is historical; use build_meadow.py for the current stable runtime paths.'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert json.loads((D/'component_plan.json').read_text())['status']=='frozen_before_geometry'
report=[]
for key in ['grass_soft','moss_soft']:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 verts=[];uvs=[];weights=[];faces=[]
 if key=='grass_soft':
  for j in range(3):
   angle=j*math.pi/3
   for y in range(4):
    t=y/3
    for x in [-1,1]:
     xx=x*.15*(1-.12*t);zz=.018*t*t
     verts.append((xx*math.cos(angle)-zz*math.sin(angle),xx*math.sin(angle)+zz*math.cos(angle),t*.18))
     uvs.append(((x+1)/2,t));weights.append(t)
   for row in range(3):
    a=j*8+row*2;faces.append((a,a+1,a+3,a+2))
 else:
  for y in range(3):
   for x in range(3):
    z=.009*math.sin(x*math.pi/2)*math.sin(y*math.pi/2)
    verts.append(((x-1)*.5,(y-1)*.5,z));uvs.append((x/2,y/2));weights.append(0.0)
  for y in range(2):
   for x in range(2):
    a=y*3+x;faces.append((a,a+1,a+4,a+3))
 me=bpy.data.meshes.new(key);me.from_pydata(verts,[],faces);me.update()
 ob=bpy.data.objects.new(key,me);bpy.context.scene.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 uv=me.uv_layers.new(name='BotanicalUV');uv.active_render=True
 co=me.color_attributes.new(name='WindData',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.active_color=co
 for f in me.polygons:
  for i in f.loop_indices:
   v=me.loops[i].vertex_index;uv.data[i].uv=uvs[v];co.data[i].color=(weights[v],weights[v],.5,1)
 mat=bpy.data.materials.new('SEA_SoftBotanical');mat.use_nodes=True;me.materials.append(mat)
 mat.surface_render_method='DITHERED';mat.use_transparency_overlap=False
 nodes=mat.node_tree.nodes;links=mat.node_tree.links
 tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(D/'soft_atlas.png'));tex.interpolation='Linear'
 uvnode=nodes.new('ShaderNodeUVMap');uvnode.uv_map='BotanicalUV'
 scale=nodes.new('ShaderNodeVectorMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=(.5,.5,1)
 offset=nodes.new('ShaderNodeVectorMath');offset.operation='ADD';offset.inputs[1].default_value=(0,.5 if key=='grass_soft' else 0,0)
 links.new(uvnode.outputs['UV'],scale.inputs[0]);links.new(scale.outputs['Vector'],offset.inputs[0]);links.new(offset.outputs['Vector'],tex.inputs['Vector'])
 bs=nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=1
 links.new(tex.outputs['Color'],bs.inputs['Base Color']);links.new(tex.outputs['Alpha'],bs.inputs['Alpha'])
 ob['visual_only']=True;ob['wind_contract']=2;ob['texture_uv_exception']='user requested botanical color+alpha cards'
 folder=D/'components'/key;folder.mkdir(parents=True,exist_ok=True)
 source=folder/(key+'.blend');opt=folder/(key+'_optimized.blend')
 bpy.ops.wm.save_as_mainfile(filepath=str(source));digest=sha(source)
 bpy.ops.wm.open_mainfile(filepath=str(source));me=bpy.data.objects[key].data;me.calc_loop_triangles();before=len(me.loop_triangles)
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7);bm.to_mesh(me);bm.free()
 bpy.ops.wm.save_as_mainfile(filepath=str(opt));bpy.ops.wm.open_mainfile(filepath=str(opt));ob=bpy.data.objects[key];me=ob.data;me.calc_loop_triangles()
 assert sha(source)==digest and len(me.loop_triangles)==before
 assert all(v>=0 for c in me.color_attributes['WindData'].data for v in c.color)
 dest=R/'godot/assets/models/vegetation'/f'{key}.glb';dest.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',export_materials='NONE',export_yup=True,export_vertex_color='NAME',export_vertex_color_name='WindData',export_active_vertex_color_when_no_material=True)
 item=dict(asset_id='SEA-VEG-'+key.upper().replace('_','-'),key=key,source=source.relative_to(R).as_posix(),source_sha256=digest,optimized_source=opt.relative_to(R).as_posix(),optimized_sha256=sha(opt),glb=dest.relative_to(R).as_posix(),glb_sha256=sha(dest),triangles=before,vertices=len(me.vertices),operations=['separate persistent optimized save','remove degenerate edges','source and optimized reopened','UV and WindData preserved'],root='bottom_center',geometry='texture carrier only',uv0='BotanicalUV')
 write(folder/'production_report.json',item);report.append(item)
write(W/'source_report.json',dict(passed=True,assets=report));print('SOFT_CARDS_SOURCE_OK',[(r['key'],r['triangles']) for r in report])
