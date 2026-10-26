import bpy,json,math,hashlib,os
from pathlib import Path
from mathutils import Vector,Matrix,Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v007';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v007';pal=R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.png';source=D/'sunny_bloom_retreat.blend'
cat=json.loads((D/'catalog.json').read_text());layout=json.loads((D/'component_instances.json').read_text())['instances'];faces=0
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inspect(col):
 global faces
 for o in col.all_objects:
  if o.type!='MESH':continue
  assert len(o.data.vertices)>0
  uv=o.data.uv_layers['PaletteUV'];assert uv.active_render
  for f in o.data.polygons:
   ps=[uv.data[l].uv for l in f.loop_indices];area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(ps,ps[1:]+ps[:1])))/2
   assert area>1e-9 and len({(int(p.x*8),int(p.y*8)) for p in ps})==1,o.name
   assert all(.1249<=(p[a]*8)%1<=.8751 for p in ps for a in [0,1]);faces+=1
  for m in o.data.materials:
   assert m.name in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'}
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE':assert n.interpolation=='Closest' and not n.image.packed_file and Path(bpy.path.abspath(n.image.filepath)).resolve()==pal.resolve()
for e in cat['components']:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 bpy.context.scene.collection.children.link(b.collections[0]);p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal),start=str(p.parent))
 bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True);bpy.ops.wm.open_mainfile(filepath=str(p));inspect(bpy.data.collections[e['collection']]);e['source_sha256']=sha(p)
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2),encoding='utf-8')
 print('VERIFIED',e['key'],flush=True)
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf-8')
for module in ['rear_building','solar_room','front_platform','bridge']:
 bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene;sc.name=module;sel=[e for e in layout if e['module']==module];names=list({e['asset_id'] for e in sel})
 with bpy.data.libraries.load(str(source),link=True) as (a,b):b.collections=names
 cols={c.name:c for c in b.collections}
 for e in sel:
  o=bpy.data.objects.new(e['name'],None);sc.collection.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=cols[e['asset_id']];o.location=e['position'];o.rotation_euler=e['rotation_euler_xyz'];o.scale=e['scale']
 p=D/'modules'/module/(module+'.blend');p.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True);bpy.ops.wm.open_mainfile(filepath=str(p));assert len(bpy.context.scene.objects)==len(sel)
protected=json.loads((W/'protected_sources.json').read_text());assert all(sha(R/p)==h for p,h in protected.items())
(W/'source_verification.json').write_text(json.dumps({'passed':True,'components':49,'instances':len(layout),'uv_faces_checked':faces,'packages_reopened':49,'modules_reopened':4,'protected_sources_unchanged':True}),encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.context.scene;sc.cycles.samples=16;sc.render.resolution_x=900;sc.render.resolution_y=900
for name,offset,scale in [('front',(-18,-28,19),25),('back',(19,24,19),25),('top',(0,-4,40),28),('ropes',(-12,-22,10),12)]:
 target=Vector((-.15,-3.5,3.8)) if name!='ropes' else Vector((-1.8,-11.7,.7));sc.camera.location=target+Vector(offset);sc.camera.rotation_euler=(target-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=scale;sc.render.filepath=str(W/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
print('SOURCE_VERIFIED',flush=True)
