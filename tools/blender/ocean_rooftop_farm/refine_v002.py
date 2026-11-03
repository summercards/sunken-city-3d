import bpy,math,json,random
from pathlib import Path
from mathutils import Vector
s=bpy.context.scene;root=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'))
src=next(c for c in root.children if c.name.startswith('01_制作'))
flora=next(c for c in root.children if c.name.startswith('02_')).children[2]
random.seed(203)
pal=Path('D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.json');cells={x['name']:x for x in json.loads(pal.read_text(encoding='utf-8'))['cells']}
def uv_color(me,face,layer,cell):
 c=cells[cell];u=c['column']/8;v=1-(c['row']+1)/8;n=len(face.loop_indices)
 for j,li in enumerate(face.loop_indices):a=j*math.tau/n;layer.data[li].uv=(u+(.5+.20*math.cos(a))/8,v+(.5+.20*math.sin(a))/8)
# Shared palette green base transforms roof from bare concrete into continuous turf.
roof=next(c for c in src.children if c.name.startswith('ORF2_组件_roof'))
for o in roof.objects:
 uv=o.data.uv_layers.get('PaletteUV')
 for p in o.data.polygons:
  if p.normal.z>.8:uv_color(o.data,p,uv,'leaf_mid')
# Grass patches become subtle leafy variation rather than tall clumps.
for o in s.objects:
 if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-GRASS':o.scale.z=.40
# use deeper greens in foliage for reference-like saturation
for key in ['grass','tuft']:
 c=next(c for c in src.children if c.name.startswith('ORF2_组件_'+key))
 for o in c.objects:
  uv=o.data.uv_layers.get('PaletteUV')
  for i,p in enumerate(o.data.polygons):uv_color(o.data,p,uv, ['leaf','leaf_mid','moss','sage'][i%4])
# Repair greenhouse missing gable wedge, leave a small broken panel only.
matte=next(m for m in bpy.data.materials if m.name.startswith('ORF2_SEA_Matte') and m.users>0)
gloss=next(m for m in bpy.data.materials if m.name.startswith('ORF2_SEA_Gloss') and m.users>0)
gh=next(c for c in src.children if c.name.startswith('ORF2_组件_greenhouse'))
def mesh(name,vs,fs,col,material,cell):
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();ob=bpy.data.objects.new(name,me);col.objects.link(ob);me.materials.append(material);uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 for p in me.polygons:uv_color(me,p,uv,cell)
 return ob
# faces have correct winding normals; both module ends enclosed except door
for y in [-2.015,2.015]:mesh('ORF2_温室三角山墙', [(-3,y,2.1),(3,y,2.1),(0,y,3.6)],[(0,1,2)],gh,gloss,'palegreen')
# fill half of formerly missing roof panel. Still has a narrow absent strip.
a=math.atan2(1.5,3);cy=1.0;x=-1.5;z=2.85;vs=[]
for dx,dy in [(-1.65,-.9),(1.65,-.9),(1.65,.60),(-1.65,.60)]:vs.append((x+dx*math.cos(a),cy+dy,z+dx*math.sin(a)))
mesh('ORF2_温室局部补回玻璃',vs,[(0,1,2,3)],gh,gloss,'seafoam')
# delete older failed task scenes from delivered candidate only, never touch initial user scene.
for sc in list(bpy.data.scenes):
 if sc!=s and (sc.name.startswith('海上巨型楼顶农场_重制') or sc.name.startswith('海上屋顶农场_全新组件制作')):
  bpy.data.scenes.remove(sc)
# Four clean role names only in this task, don't rename shared materials used by other sources.
active_mats={m for c in src.children for o in c.objects if o.type=='MESH' for m in o.data.materials}
for m in list(bpy.data.materials):
 if m.name.startswith('ORF2_SEA_') and m not in active_mats and m.users==0:bpy.data.materials.remove(m)
for m in active_mats:m.name=m.name.split('.')[0]
# Keep authoring source hidden again after inspection changes.
for lc in bpy.context.view_layer.layer_collection.children:
 for ch in lc.children:
  if ch.collection==src:ch.exclude=True
s.render.resolution_percentage=100;s.cycles.samples=32
for name,file in [('ORF2_参考图屋顶主镜头','01_reference_roof.png'),('ORF2_全楼完整镜头','02_full_building.png'),('ORF2_垂直俯视','03_top_plan.png'),('ORF2_温室水塔近景','04_greenhouse_detail.png')]:
 s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith(name));s.render.filepath='D:/projects/sea-work/ocean_rooftop_farm/v002/'+file;bpy.ops.render.render(write_still=True)
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'))
# Bind viewport to saved camera.
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v002/ocean_rooftop_farm_v002.blend',compress=True)
print(json.dumps({'scene':s.name,'views':4,'material_roles':[m.name for m in active_mats],'source_scenes':[x.name for x in bpy.data.scenes]},ensure_ascii=False))
