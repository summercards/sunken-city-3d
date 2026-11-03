import bpy, json, math, random
from pathlib import Path
from mathutils import Vector
random.seed(20261103)
ROOT=Path('D:/projects/sea'); OUT=ROOT/'art_source/scenes/ocean_rooftop_farm/v002'; WORK=ROOT.parent/'sea-work/ocean_rooftop_farm/v002'
OUT.mkdir(parents=True,exist_ok=True); WORK.mkdir(parents=True,exist_ok=True)
# remove only a previous failed r3 scene, preserve user's other scenes
for s in list(bpy.data.scenes):
    if s.name.startswith('海上巨型楼顶农场_重制_v002'):
        bpy.data.scenes.remove(s)
scene=bpy.data.scenes.new('海上巨型楼顶农场_重制_v002'); bpy.context.window.scene=scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1.0
scene.render.engine='BLENDER_EEVEE_NEXT'; scene.render.resolution_x=1500; scene.render.resolution_y=1050; scene.render.resolution_percentage=100; scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
root=bpy.data.collections.new('海上巨型楼顶农场_v002_资产总根'); scene.collection.children.link(root)
def col(name,parent=root):
 c=bpy.data.collections.new(name); parent.children.link(c); return c
c_struct=col('02_游戏输出_独立资产包_v002/01_建筑结构'); c_fac=col('02_游戏输出_独立资产包_v002/02_屋顶固定设施'); c_ag=col('02_游戏输出_独立资产包_v002/03_农业设施与作物'); c_veg=col('02_游戏输出_独立资产包_v002/04_草皮青苔与藤蔓'); c_sup=col('02_游戏输出_独立资产包_v002/05_附属设备'); c_qa=col('90_展示与验收_灯光相机'); c_src=col('01_制作组件_按设施拆分'); c_src.hide_viewport=True; c_src.hide_render=True
PAL=ROOT/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'; PJ=ROOT/'art_source/shared/palettes/sea_cabin_timber_8x8_512.json'
cells={x['name']:x for x in json.loads(PJ.read_text(encoding='utf-8'))['cells']}; image=bpy.data.images.load(str(PAL),check_existing=True); image.filepath=str(PAL)
roles={}
def role(name,metal,rough,coat=0,emit=0):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes=True; n=m.node_tree.nodes; l=m.node_tree.links; n.clear(); out=n.new('ShaderNodeOutputMaterial'); bs=n.new('ShaderNodeBsdfPrincipled'); uv=n.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'; tx=n.new('ShaderNodeTexImage'); tx.image=image; tx.interpolation='Closest'; l.new(uv.outputs['UV'],tx.inputs['Vector']); l.new(tx.outputs['Color'],bs.inputs['Base Color']); l.new(bs.outputs['BSDF'],out.inputs['Surface']); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
 if 'Coat Weight' in bs.inputs: bs.inputs['Coat Weight'].default_value=coat
 if emit: l.new(tx.outputs['Color'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=emit
 roles[name]=m
role('01_精工金属_紫色骨架',.86,.28,.18); role('02_细腻哑光_青绿大面',.03,.72); role('03_清漆反光_紫粉点缀',.16,.16,.68); role('04_柔和自发光_UI灯光',0,.38,0,1.1)
def finish(o,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,smooth=False):
 if hasattr(o.data,'materials'):
  o.data.materials.clear(); o.data.materials.append(roles[r]);
  for old in list(o.data.uv_layers): o.data.uv_layers.remove(old)
  uv=o.data.uv_layers.new(name='PaletteUV'); c=cells[cell]; u0=c['column']/8; v0=1-(c['row']+1)/8; q=[(.28,.28),(.72,.28),(.72,.72),(.28,.72)]
  for p in o.data.polygons:
   for j,li in enumerate(p.loop_indices): uv.data[li].uv=(u0+q[j%4][0]/8,v0+q[j%4][1]/8)
  o.data.uv_layers.active=uv; uv.active_render=True
  for p in o.data.polygons: p.use_smooth=smooth
 if bev and o.type=='MESH': b=o.modifiers.new('项目柔和边角','BEVEL'); b.width=bev; b.segments=2
 return o
def mv(o,t):
 for cc in list(o.users_collection): cc.objects.unlink(o)
 t.objects.link(o); return o
def cube(name,loc,size,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,rot=None,t=c_struct):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name; o.dimensions=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 mv(o,t); return finish(o,cell,r,bev)
def cyl(name,loc,rad,depth,cell='steel',r='01_精工金属_紫色骨架',verts=20,rot=None,t=c_fac,bev=.025,r2=None):
 if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=rad,depth=depth,location=loc)
 else:bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=rad,radius2=r2,depth=depth,location=loc)
 o=bpy.context.object; o.name=name
 if rot:o.rotation_euler=rot
 mv(o,t); return finish(o,cell,r,bev,True)
def sphere(name,loc,scale,cell='leaf',r='02_细腻哑光_青绿大面',t=c_veg):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=loc); o=bpy.context.object; o.name=name; o.scale=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); mv(o,t); return finish(o,cell,r,0,True)
def rod(name,a,b,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_fac):
 a=Vector(a); b=Vector(b); o=cyl(name,(a+b)/2,rad,(b-a).length,cell,r,verts=12,t=t,bev=.008); o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler(); return o
def tube(name,pts,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_fac):
 cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.bevel_depth=rad; cu.bevel_resolution=2; sp=cu.splines.new('POLY'); sp.points.add(len(pts)-1)
 for p,co in zip(sp.points,pts):p.co=(*co,1)
 o=bpy.data.objects.new(name,cu); t.objects.link(o); bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH'); return finish(o,cell,r,0,True)
def emp(name,loc=(0,0,0),t=root):o=bpy.data.objects.new(name,None); t.objects.link(o); o.location=loc; return o
def par(o,p):mw=o.matrix_world.copy(); o.parent=p; o.matrix_world=mw
# keep helpers in a text block for later chunks
src=globals().get('__file__','')
text=bpy.data.texts.get('ORF_R3_HELPERS') or bpy.data.texts.new('ORF_R3_HELPERS')
# Current exec namespace is not serializable; later chunks load this same script from disk via a small helper text created here.
text.clear(); text.write("# helper text marker; stage scripts are self-contained\n")
meta=emp('ASSET_META_海上巨型楼顶农场_v002',t=c_src); meta['asset_id']='SEA-SCENE-ORF-ROOFTOP-FARM-V002'; meta['building_class']='above_water'; meta['water_layer']='surface'; meta['dimensions_m']='48x32 roof; 50.6 roof deck; 60m tower top'; meta['excluded']='animals, people, ocean, distant buildings, background geometry'; meta['palette_path']='art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
print(json.dumps({'scene':scene.name,'collections':len(scene.collection.children),'materials':list(roles),'objects':len(scene.objects)},ensure_ascii=False))
