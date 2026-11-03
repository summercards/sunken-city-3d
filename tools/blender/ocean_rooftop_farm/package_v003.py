import bpy,json,hashlib
from pathlib import Path
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003');s=bpy.context.scene;cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
for e in cat:
 c=bpy.data.collections[e['collection']]
 # relative origin recenters corrected shape while retaining layout (compensate in world).
 from mathutils import Vector
 pts=[v.co for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);ctr=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 if ctr.length>1e-6:
  for ob in c.objects:
   for v in ob.data.vertices:v.co-=ctr
  for o in s.objects:
   if o.instance_type=='COLLECTION' and o.instance_collection==c:o.location+=o.matrix_world.to_3x3()@ctr
 e['bounds_size_m']=list(hi-lo);e['geometry_fingerprint']=hashlib.sha256(repr([[tuple(round(x,6) for x in v.co) for v in ob.data.vertices] for ob in c.objects]).encode()).hexdigest();e['instance_count']=sum(o.instance_type=='COLLECTION' and o.instance_collection==c for o in s.objects)
 pack=D/'component_packages'/e['key'];pack.mkdir(parents=True,exist_ok=True);ps=bpy.data.scenes.new('组件_'+e['key']);pc=bpy.data.collections.new('02_游戏输出_'+e['key']);ps.collection.children.link(pc);copies=[]
 for ob in c.objects:
  no=ob.copy();no.data=ob.data.copy();no.parent=None;no.location=(0,0,0);no.rotation_euler=(0,0,0);no.scale=(1,1,1);pc.objects.link(no);copies.append(no)
 for ob in copies:
  for m in ob.data.materials:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:n.image.filepath='D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
 file=pack/(e['key']+'.blend');bpy.data.libraries.write(str(file),{ps},path_remap='RELATIVE_ALL',fake_user=True,compress=True);e['source_sha256']=hashlib.sha256(file.read_bytes()).hexdigest()
 manifest=dict(e);manifest.update({'schema':'sea.scene.component_manifest','version':'v003','palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png','runtime_status':'pending','license':'pending_user_reference_rights_review'});(pack/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
 for ob in copies:
  me=ob.data;bpy.data.objects.remove(ob,do_unlink=True)
  if me.users==0:bpy.data.meshes.remove(me)
 bpy.data.scenes.remove(ps);bpy.data.collections.remove(pc)
for e in cat:
 for ob in bpy.data.collections[e['collection']].objects:
  for m in ob.data.materials:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:n.image.filepath='//../../../shared/palettes/sea_cabin_timber_8x8_512.png'
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
instances=[{'name':o.name,'component_id':o.get('component_id'),'position_m':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)} for o in s.objects if o.instance_type=='COLLECTION'];(D/'component_instances.json').write_text(json.dumps({'instances':instances,'coordinate_mapping':'(x,y,z)->(x,z,-y)'},ensure_ascii=False,indent=2),encoding='utf-8')
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'));s.render.resolution_percentage=100;s.cycles.samples=40
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v003.blend'),compress=True)
print(json.dumps({'packages':len(cat),'instances':len(instances),'file':bpy.data.filepath},ensure_ascii=False))
