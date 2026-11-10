"""Build exactly two derived botanical Collection libraries. Never save an input source."""
import bpy, hashlib, json, math, os, sys
from pathlib import Path
from mathutils import Matrix, Vector
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_libraries/v001'
P=json.loads((R/'art_source/vegetation/libraries/v001/component_plan.json').read_text(encoding='utf-8'))
STAGES=['seed','sprout','leaf','harvest']
NATIVE_PATH=W/'native_meshes.json'
def dump(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def mesh_signature(me):
 me.calc_loop_triangles()
 payload={'v':[[round(x,6) for x in v.co] for v in me.vertices], 'faces':[list(p.vertices) for p in me.polygons], 'smooth':[p.use_smooth for p in me.polygons], 'mi':[p.material_index for p in me.polygons], 'uv':{l.name:[[round(x,7) for x in d.uv] for d in l.data] for l in me.uv_layers}, 'colors':{a.name:{'domain':a.domain,'type':a.data_type,'values':[[round(x,7) for x in d.color] for d in a.data]} for a in me.color_attributes}}
 return hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def identity(o):return all(abs(o.matrix_world[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4))
def col(name,parent=None):
 c=bpy.data.collections.new(name)
 if parent:parent.children.link(c)
 c.instance_offset=(0,0,0)
 return c

def fix_images(old,src):
 for im in bpy.data.images:
  if im.as_pointer() in old or im.source!='FILE':continue
  if im.packed_file: im.unpack(method='REMOVE')
  raw=im.filepath.replace('\\','/')
  candidates=[Path(bpy.path.abspath(raw,start=str(src.parent))),src.parent/raw.removeprefix('//'),R/raw]
  if im.name.split('.')[0].startswith('sea_'):
   candidates.extend((R/'art_source/shared/palettes').glob('*.png'))
  found=next((p.resolve() for p in candidates if p.is_file()),None)
  if found is None:raise RuntimeError(f'Missing source image {src}: {raw}')
  im.filepath=str(found)
  im['archive_external_sha256']=sha(found)

def append_meshes(src,stage=None):
 oldimg={i.as_pointer() for i in bpy.data.images}
 with bpy.data.libraries.load(str(src),link=False) as (a,b):
  if stage is not None:
   name=next((n for n in a.collections if n.startswith(f'stage_{stage}_')),None)
   assert name,(src,stage,a.collections)
   b.collections=[name]
  else:b.objects=list(a.objects)
 fix_images(oldimg,src)
 objects=list(b.collections[0].all_objects) if stage is not None else [o for o in b.objects if o]
 for o in objects:
  if o.name not in TMP.objects:TMP.objects.link(o)
 bpy.context.view_layer.update()
 dg=bpy.context.evaluated_depsgraph_get()
 result=[]
 for o in objects:
  if o.type not in {'MESH','CURVE','FONT','SURFACE'}:continue
  ev=o.evaluated_get(dg)
  me=bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=dg)
  me.transform(o.matrix_world)
  result.append((o.name,me))
 for o in objects:bpy.data.objects.remove(o,do_unlink=True)
 if stage is not None and b.collections[0]:bpy.data.collections.remove(b.collections[0])
 assert result,src
 return result

def native_matrix(d):
 m=d.get('transform',d.get('matrix',d.get('transform_godot')))
 if m is None:return Matrix.Identity(4)
 if len(m)==4 and isinstance(m[0],list):return Matrix(m)
 if len(m)==12:
  # The extractor explicitly serializes three ROWS (basis columns interleaved with origin).
  return Matrix((m[0:4],m[4:8],m[8:12],(0,0,0,1)))
 if len(m)==16:return Matrix([m[i:i+4] for i in range(0,16,4)])
 raise ValueError(m)

MAT_CACHE={}
def native_material(d,colors,uv_name):
 key=json.dumps(d,sort_keys=True)+str(bool(colors))+uv_name
 if key in MAT_CACHE:return MAT_CACHE[key]
 m=bpy.data.materials.new('SEA_原生派生_'+str(len(MAT_CACHE)+1));m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');n=m.node_tree.nodes;l=m.node_tree.links
 color=d.get('base_color',d.get('albedo',d.get('albedo_color',[1,1,1,1])))
 if isinstance(color,dict):color=[color.get(k,1) for k in ['r','g','b','a']]
 if len(color)==3:color=list(color)+[1]
 # Godot albedo Color is authored as sRGB; Blender socket values are scene-linear.
 color=[(x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4) for x in color[:3]]+[color[3]]
 bs.inputs['Base Color'].default_value=color
 bs.inputs['Roughness'].default_value=d.get('roughness',.82)
 bs.inputs['Metallic'].default_value=d.get('metallic',0)
 m.diffuse_color=color
 tex=d.get('texture',d.get('albedo_texture',''))
 if tex:
  if isinstance(tex,dict):tex=tex.get('path','')
  path=R/'godot'/tex.removeprefix('res://') if tex.startswith('res://') else Path(tex)
  if not path.is_absolute():path=R/path
  if path.is_file():
   t=n.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(path),check_existing=True);t.interpolation='Closest'
   u=n.new('ShaderNodeUVMap');u.uv_map=uv_name;l.new(u.outputs['UV'],t.inputs['Vector']);l.new(t.outputs['Color'],bs.inputs['Base Color'])
 if colors:
  a=n.new('ShaderNodeVertexColor');a.layer_name='Color'
  if any(abs(color[i]-1)>1e-6 for i in range(3)):
   mix=n.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=color;l.new(a.outputs['Color'],mix.inputs[1]);l.new(mix.outputs[0],bs.inputs['Base Color'])
  else:l.new(a.outputs['Color'],bs.inputs['Base Color'])
 m['archive_material']='Godot static material/color representation; shader animation not migrated'
 MAT_CACHE[key]=m
 return m

def vecs(a,n):
 if not a:return []
 return a if isinstance(a[0],(list,tuple)) else [a[i:i+n] for i in range(0,len(a),n)]

def native_meshes(e):
 result=[]
 C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
 for j,d in enumerate(e.get('meshes',[])):
  verts=vecs(d.get('vertices',d.get('positions',[])),3)
  indices=d.get('indices',[])
  if not indices:indices=list(range(len(verts)))
  faces=[tuple(reversed(indices[i:i+3])) for i in range(0,len(indices),3)] # Godot clockwise -> Blender CCW
  me=bpy.data.meshes.new(e['key']+f'_mesh{j:03}');me.from_pydata(verts,[],faces);me.update()
  uv=vecs(d.get('uv',d.get('uvs',[])),2)
  uvname=d.get('uv_name','UVMap')
  if uv:
   layer=me.uv_layers.new(name=uvname)
   for lo in me.loops:layer.data[lo.index].uv=uv[lo.vertex_index]
  colors=vecs(d.get('colors',[]),4)
  if colors:
   layer=me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='POINT')
   for k,v in enumerate(colors):layer.data[k].color=v if len(v)==4 else list(v)+[1]
  norms=vecs(d.get('normals',[]),3)
  if norms:
   for p in me.polygons:p.use_smooth=True
   me.normals_split_custom_set_from_vertices(norms)
  me.materials.append(native_material(d.get('material',{}),colors,uvname))
  me.transform(C@native_matrix(d))
  result.append((d.get('name',e['key']+f'_{j:03}'),me))
 assert result,e['key']
 return result

MEMBERS=[]
def make_member(e,meshes,parent,variant='',normalize=True):
 suffix='__'+variant if variant else ''
 name=e['asset_id']+suffix
 c=col(name,parent)
 c['asset_id']=e['asset_id'];c['display_name']=e['name'];c['archive_variant']=variant
 c['original_source']=e.get('source','');c['original_source_sha256']=e.get('source_sha256','')
 c['original_stage']=e.get('original_stage','pending');c['primary_source_unchanged']=True
 pts=[v.co.copy() for _,m in meshes for v in m.vertices]
 mn=Vector(tuple(min(p[i] for p in pts) for i in range(3)));mx=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
 vine='vine' in (e.get('source','')+e.get('name','')).lower() or '藤' in e.get('name','')
 offset=Vector(((mn.x+mx.x)/2,(mn.y+mx.y)/2,mx.z if vine else mn.z)) if normalize else Vector((0,0,0))
 c['archive_anchor_policy']='top_center_attachment' if normalize and vine else ('bottom_center' if normalize else 'original_crop_or_facility_origin')
 c['source_origin_offset']=list(offset)
 meshrows=[]
 for j,(oldname,m) in enumerate(meshes):
  m.transform(Matrix.Translation(-offset));m.update();m.calc_loop_triangles()
  o=bpy.data.objects.new(f'{name}__M{j:03}',m);c.objects.link(o);o['source_object_name']=oldname
  meshrows.append({'object':o.name,'source_object':oldname,'vertices':len(m.vertices),'polygons':len(m.polygons),'triangles':len(m.loop_triangles),'signature':mesh_signature(m),'uv_layers':[l.name for l in m.uv_layers],'color_attributes':[a.name for a in m.color_attributes]})
 c.asset_mark();c.asset_data.description=f"{e['name']} | {variant or '组件母版'} | {e.get('source','')} | 原主源与运行资源不变"
 for tag in ['sea',e.get('domain','scenes'),'derived_library']:c.asset_data.tags.new(tag)
 row={**{k:v for k,v in e.items() if k not in ['meshes','components']},'collection':c.name,'variant':variant,'origin_offset_source':list(offset),'anchor_policy':c['archive_anchor_policy'],'bounds':[list(mn-offset),list(mx-offset)],'meshes':meshrows,'triangles':sum(x['triangles'] for x in meshrows),'polygons':sum(x['polygons'] for x in meshrows)}
 MEMBERS.append(row)
 return c,row

def native_match(native,aid,kind=None):
 entries=[e for e in native if e.get('asset_id')==aid]
 if kind:entries=[e for e in entries if kind in str(e.get('key','')) or kind==e.get('kind') or kind==e.get('variant')]
 return entries

def label(text,location,size=.19):
 cu=bpy.data.curves.new('展示标签','FONT');cu.body=text;cu.size=size;cu.align_x='CENTER';cu.extrude=0
 o=bpy.data.objects.new('LABEL_'+text[:40],cu);SUPPORT.objects.link(o);o.location=location
 cu.materials.append(LABEL_MAT)
 return o

def gallery(c,row,x,y):
 mn=Vector(row['bounds'][0]);mx=Vector(row['bounds'][1]);dims=mx-mn
 scale=min(1.0,2.25/max(dims.x,dims.y,.01),2.3/max(dims.z,.01))
 o=bpy.data.objects.new('展示__'+c.name,None);GALLERY.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=c
 o.scale=(scale,)*3;o.location=(x,y,-mn.z*scale)
 row['gallery']={'position':list(o.location),'uniform_scale':scale,'instance':o.name}
 label(c.name.replace('SEA-SCENE-','').replace('SEA-PLANT-','').replace('ZONES-ZONE','Z').replace('_HOME_HARBOR','').replace('_ARC_FARM','')[:42],(x,y-1.15,.012),.125)
 label(f'{row["triangles"]} tris  |  x{scale:.3g}',(x,y-1.4,.012),.12)

def setup_review(scene,width,depth):
 scene.world=bpy.data.worlds.new('组件库柔光环境');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.73,.68,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.75
 floor=col('展示地面',SUPPORT)
 me=bpy.data.meshes.new('展示地面');me.from_pydata([(-4,-depth-4,-.06),(width+4,-depth-4,-.06),(width+4,4,-.06),(-4,4,-.06)],[],[(0,1,2,3)])
 o=bpy.data.objects.new('展示地面_非资产',me);floor.objects.link(o)
 mat=bpy.data.materials.new('展示奶油背景');mat.diffuse_color=(.79,.82,.74,1);mat.use_nodes=True;mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.79,.82,.74,1);mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9;me.materials.append(mat)
 target=Vector((width/2,-depth/2,.4))
 for i,(pos,power,size) in enumerate([((width/2,-depth/2,25),4000,25),((-10,0,15),2500,18)]):
  ld=bpy.data.lights.new('展示柔光'+str(i),'AREA');ld.energy=power;ld.size=size;o=bpy.data.objects.new(ld.name,ld);SUPPORT.objects.link(o);o.location=pos;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
 ca=bpy.data.cameras.new('总览相机');ca.type='ORTHO';o=bpy.data.objects.new('总览相机',ca);SUPPORT.objects.link(o);scene.camera=o
 scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=2400;scene.render.resolution_y=1800;scene.render.resolution_percentage=100
 scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
 scene['review_target']=list(target);scene['review_width']=width;scene['review_depth']=depth
 for screen in bpy.data.screens:
  for area in screen.areas:
   if area.type=='VIEW_3D':
    area.spaces.active.region_3d.view_location=target;area.spaces.active.region_3d.view_distance=max(width,depth)*1.25
    area.spaces.active.shading.type='MATERIAL'
 return target

def build(lib,native):
 global TMP,GALLERY,SUPPORT,LABEL_MAT,MEMBERS,MAT_CACHE
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 MEMBERS=[];MAT_CACHE={}
 scene=bpy.context.scene;scene.name='01_组件总览_只摆实例'
 GALLERY=col('01_展示实例_非游戏摆位',scene.collection);SUPPORT=col('03_展示支持_不导出',scene.collection);TMP=col('_IMPORT_TEMP',scene.collection)
 masters_scene=bpy.data.scenes.new('02_组件母版_按AssetID追加');masters=col('02_组件母版',masters_scene.collection)
 LABEL_MAT=bpy.data.materials.new('展示标签深绿');LABEL_MAT.diffuse_color=(.012,.035,.022,1);LABEL_MAT.use_nodes=True;LABEL_MAT.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.012,.035,.022,1)
 groups={};gallery_rows=[]
 for e in lib['components']:
  group=groups.setdefault(e['group'],col(e['group'],masters)) if e['group'] not in groups else groups[e['group']]
  if e['mode']=='blend_component':
   c,row=make_member(e,append_meshes(R/e['source']),group);gallery_rows.append((c,row))
  elif e['mode']=='blend_crop':
   parent=col(e['asset_id']+'__四阶段',group);parent['asset_id']=e['asset_id']
   for i,key in enumerate(STAGES):
    c,row=make_member(e,append_meshes(R/e['source'],i),parent,f'stage_{i}_{key}',False);gallery_rows.append((c,row))
  else:
   matches=native_match(native,e['asset_id'])
   if e['mode']=='native_flower':matches=[n for n in matches if 'harvest_visual' not in n['key'] and n.get('group')!='harvest_visuals' and n.get('kind')!='harvest_visual']
   elif e['mode']=='native_facility':matches=[n for n in matches if 'assembly' not in n['key']]
   for n in matches:
    if e['mode']=='native_flower' and ('handheld' in n['key'] or 'receive' in n['key']):continue
    variant=n.get('variant','')
    if not variant and e['mode']=='native_flower':variant=n['key'].replace(e.get('key','!'),'')
    ee={**e,'native_key':n['key'],'native_sources':n.get('source_paths',[])}
    c,row=make_member(ee,native_meshes(n),group,variant,not e['mode'] in ['native_flower','native_facility']);gallery_rows.append((c,row))
   assert matches,('native missing',e['asset_id'])
 if 'PLANTING' in lib['library_id']:
  hand=col('03_六品种收获手持物',masters)
  for n in native:
   if not ('harvest_visual' in n['key'] or n.get('group')=='harvest_visuals' or n.get('kind')=='harvest_visual' or 'handheld' in n['key']):continue
   e=next(x for x in lib['components'] if x['asset_id']==n['asset_id'])
   c,row=make_member({**e,'native_key':n['key'],'native_sources':n.get('source_paths',[])},native_meshes(n),hand,'收获手持',False);gallery_rows.append((c,row))
  # Assemblies are only Collection Instances of the single soil cell, never six duplicated meshes.
  soil=next((c,row) for c,row in gallery_rows if row['asset_id']=='SEA-FARM-SOIL-CELL')
  assembly=col('04_单格与六格装配',masters)
  for count in [1,6]:
   c=col('SEA-FARM-SOIL-CELL__'+('单格装配' if count==1 else '六格装配'),assembly)
   for i in range(count):
    o=bpy.data.objects.new(f'土格引用_{i+1}',None);c.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=soil[0]
    o.location=(i%3*1.5,-(i//3)*1.15,0)
   c['asset_id']='SEA-FARM-SOIL-CELL';c['assembly_note']='编辑参考装配；正式位置由TSCN拥有，间距不是游戏新摆位'
   row={'asset_id':'SEA-FARM-SOIL-CELL','name':c.name,'collection':c.name,'variant':'reference_assembly_'+str(count),'bounds':[[-.75,-(1.15 if count==6 else 0)-.6,0],[(3.75 if count==6 else .75),.6,.3]],'triangles':soil[1]['triangles']*count,'polygons':soil[1]['polygons']*count,'meshes':[],'instance_count':count,'source':soil[1]['source']}
   MEMBERS.append(row);gallery_rows.append((c,row))
 # Do not lay out the crop parent collections: each stage stays independently reusable.
 cols=10 if 'VEGETATION' in lib['library_id'] else 4
 for i,(c,row) in enumerate(gallery_rows):gallery(c,row,(i%cols)*3.15,-(i//cols)*3.45)
 width=(cols-1)*3.15;depth=max(1,math.ceil(len(gallery_rows)/cols)-1)*3.45
 target=setup_review(scene,width,depth)
 if 'PLANTING' in lib['library_id']:
  scene.render.resolution_x=1600;scene.render.resolution_y=2400
 # Canonicalize image datablocks by the same existing external file; no texture copies/packing.
 canonical={}
 palette_by_hash={sha(p):p for p in (R/'art_source/shared/palettes').glob('*.png')}
 for im in list(bpy.data.images):
  if im.source!='FILE':continue
  current=Path(bpy.path.abspath(im.filepath)).resolve()
  if sha(current) in palette_by_hash:im.filepath=str(palette_by_hash[sha(current)])
  key=str(Path(bpy.path.abspath(im.filepath)).resolve()).lower()
  if key in canonical:
   im.user_remap(canonical[key]);bpy.data.images.remove(im)
  else:canonical[key]=im
 scene['library_id']=lib['library_id'];scene['archive_policy']='原母版不迁移；两个派生归档文件；展示仅Collection Instance'
 bpy.data.collections.remove(TMP)
 path=R/lib['path']
 if path.exists():
  old_manifest=json.loads(path.with_name('library_manifest.json').read_text(encoding='utf-8'))
  assert old_manifest['library_id']==lib['library_id'] and sha(path)==old_manifest['sha256'],'Existing output was edited; refuse overwrite'
  assert '--rebuild-owned' in sys.argv,'Output exists; explicit --rebuild-owned required and hash guard must pass'
 # Resolve every external image before save, then make it relative to this new library.
 images=[]
 for im in bpy.data.images:
  if im.source!='FILE':continue
  p=Path(bpy.path.abspath(im.filepath))
  assert p.is_file(),(im.name,im.filepath)
  images.append({'name':im.name,'path':p.relative_to(R).as_posix() if p.is_relative_to(R) else str(p),'sha256':sha(p)})
  im.filepath='//'+os.path.relpath(p,path.parent).replace('\\','/')
 # Input geometry has already been captured in immutable normalized fingerprints.
 manifest={'schema_version':1,'library_id':lib['library_id'],'path':lib['path'],'primary_source_migration':False,'members':MEMBERS,'images':images,'source_plan':'art_source/vegetation/libraries/v001/component_plan.json','native_extraction':str(NATIVE_PATH),'gallery_instance_count':len(gallery_rows),'member_count':len(MEMBERS),'triangles_unique_meshes':sum(m['triangles'] for m in MEMBERS if m.get('meshes')),'archive_stage':'built_reopen_pending','not_migrated':['Godot shader animation and gameplay','runtime positions','source rights and art acceptance'],'preserved_source_drift':P['preserved_drift']}
 # Save a useful camera on first open; source collections remain in the second scene.
 cam=scene.camera;cam.location=target+Vector((0,-max(width,depth)*.62,max(width,depth)*1.5));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=max(width+5,(depth+5)*scene.render.resolution_x/scene.render.resolution_y)
 bpy.ops.wm.save_as_mainfile(filepath=str(path),check_existing=False)
 manifest['sha256']=sha(path)
 dump(path.with_name('library_manifest.json'),manifest)
 print('LIBRARY_BUILT '+json.dumps({'id':lib['library_id'],'members':len(MEMBERS),'instances':len(gallery_rows),'path':str(path)},ensure_ascii=False))

if __name__=='__main__':
 assert NATIVE_PATH.is_file(),NATIVE_PATH
 raw=json.loads(NATIVE_PATH.read_text(encoding='utf-8'));native=raw.get('entries',raw.get('components',[]))
 assert native,'No native meshes'
 which=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
 for lib in P['libraries']:
  if which and which[0].lower()!='all' and which[0].lower() not in lib['library_id'].lower():continue
  build(lib,native)
