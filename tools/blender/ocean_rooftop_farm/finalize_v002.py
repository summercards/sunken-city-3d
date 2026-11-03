import bpy,json,math,random,hashlib
from pathlib import Path
from mathutils import Vector
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v002');W=Path('D:/projects/sea-work/ocean_rooftop_farm/v002');s=bpy.context.scene
root=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'));src=next(c for c in root.children if c.name.startswith('01_制作'))
random.seed(7703)
# soften grass patches and break the visible checkerboard pattern.
cells={x['name']:x for x in json.loads(Path('D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.json').read_text(encoding='utf-8'))['cells']}
def uvcell(me,p,uv,c):
 ce=cells[c];u=ce['column']/8;v=1-(ce['row']+1)/8;n=len(p.loop_indices)
 for j,li in enumerate(p.loop_indices):a=j*math.tau/n;uv.data[li].uv=(u+(.5+.20*math.cos(a))/8,v+(.5+.20*math.sin(a))/8)
for key in ['grass']:
 c=next(c for c in src.children if c.name.startswith('ORF2_组件_'+key))
 for ob in c.objects:
  uv=ob.data.uv_layers.get('PaletteUV')
  for p in ob.data.polygons:uvcell(ob.data,p,uv,'leaf' if p.index%4 else 'leaf_mid')
for i,o in enumerate([o for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-GRASS']):
 o.location.x+=random.uniform(-.8,.8);o.location.y+=random.uniform(-.6,.6);o.scale=(random.uniform(.65,1.25),random.uniform(.65,1.25),.25);o.rotation_euler.z=random.uniform(0,6.2)
 if i%3==0:bpy.data.objects.remove(o,do_unlink=True)
# optical greenhouse glass, maintain SEA_Gloss role for all glass surfaces.
gh=next(c for c in src.children if c.name.startswith('ORF2_组件_greenhouse'))
for o in gh.objects:
 for m in o.data.materials:
  if 'Gloss' in m.name:
   bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Alpha'].default_value=.30
# stronger blocky concrete weathering on piers, still simplified for sea project.
pier=next(c for c in src.children if c.name.startswith('ORF2_组件_pier'))
for o in pier.objects:
 if o.type!='MESH':continue
 uv=o.data.uv_layers.get('PaletteUV')
 for p in o.data.polygons:
  if len(p.vertices)>4:uvcell(o.data,p,uv,'gray' if p.index%2 else 'stone')
# Full tower view now truly contains rooftop room and bottom.
cam=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_全楼'))
cam.data.ortho_scale=115;cam.rotation_euler=(Vector((0,0,35))-cam.location).to_track_quat('-Z','Y').to_euler()
# catalog measurements updated after refinement + unique ownership.
cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
cols={e['key']:next(c for c in src.children if c.name.startswith('ORF2_组件_'+e['key'])) for e in cat}
# component plan includes current shape fields and source signature.
instances=[]
for o in s.objects:
 if o.instance_type=='COLLECTION':instances.append({'name':o.name,'component_id':o['component_id'],'position_m':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','coordinate_mapping':'(x,y,z)->(x,z,-y)','instances':instances},ensure_ascii=False,indent=2),encoding='utf-8')
for e in cat:
 c=cols[e['key']];e['collection']=c.name;e['instance_count']=sum(i['component_id']==e['asset_id'] for i in instances)
 pts=[v.co for o in c.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)];e['bounds_size_m']=[hi[i]-lo[i] for i in range(3)];e['geometry_fingerprint']=hashlib.sha256(repr([[tuple(round(x,6) for x in v.co) for v in o.data.vertices] for o in c.objects if o.type=='MESH']).encode()).hexdigest()
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
# Relative palette path points to the one shared original; no packing/copying.
for m in {m for c in src.children for o in c.objects if o.type=='MESH' for m in o.data.materials}:
 for n in m.node_tree.nodes:
  if n.type=='TEX_IMAGE' and n.image:n.image.filepath='//../../../shared/palettes/sea_cabin_timber_8x8_512.png'
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'));s.render.resolution_percentage=100;s.cycles.samples=40
# source checkpoint before generating independent packages.
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v002.blend'),compress=True)
# write one self-contained scene per component; meshes copied so relative palette remapping does not change live model.
for e in cat:
 c=cols[e['key']];pack=D/'component_packages'/e['key'];pack.mkdir(parents=True,exist_ok=True)
 ps=bpy.data.scenes.new('组件_'+e['key']);pc=bpy.data.collections.new('02_游戏输出_'+e['key']);ps.collection.children.link(pc)
 copied=[]
 for o in c.objects:
  ob=o.copy();ob.data=o.data.copy();ob.parent=None;ob.location=(0,0,0);ob.rotation_euler=(0,0,0);ob.scale=(1,1,1);pc.objects.link(ob);copied.append(ob)
 # absolute image path is portable within project via remap on library write
 images={n.image for ob in copied for m in ob.data.materials for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
 for im in images:im.filepath=str(Path('D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png'))
 source=pack/(e['key']+'.blend');bpy.data.libraries.write(str(source),{ps},path_remap='RELATIVE_ALL',fake_user=True,compress=True)
 manifest=dict(e);manifest.update({'source':str(source),'palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png','building_class':None if e['category']=='flora' else 'above_water','scope':'scene_local','source_validation':'pending_independent_reopen','license':'pending_user_reference_rights_review'})
 (pack/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
 bpy.data.scenes.remove(ps)
 for ob in copied:
  me=ob.data;bpy.data.objects.remove(ob,do_unlink=True)
  if me.users==0:bpy.data.meshes.remove(me)
 bpy.data.collections.remove(pc)
# return image to master relative path before final save
for c in src.children:
 for ob in c.objects:
  for m in ob.data.materials:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:n.image.filepath='//../../../shared/palettes/sea_cabin_timber_8x8_512.png'
# Four final comparison renders.
for prefix,file in [('ORF2_参考图','01_reference_roof.png'),('ORF2_全楼','02_full_building.png'),('ORF2_垂直','03_top_plan.png'),('ORF2_温室','04_greenhouse_detail.png')]:
 s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith(prefix));s.render.filepath=str(W/file);bpy.ops.render.render(write_still=True)
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'))
s['authoring_status']='final_source_pending_independent_reopen';s['components']=39;s['instances']=len(instances)
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v002.blend'),compress=True)
print(json.dumps({'components':39,'instances':len(instances),'packages':39,'renders':4,'source':bpy.data.filepath},ensure_ascii=False))
