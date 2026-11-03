import bpy,json,hashlib
from pathlib import Path
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v002');s=bpy.context.scene;root=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'));src=next(c for c in root.children if c.name.startswith('01_制作'));cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
for e in cat:
 c=bpy.data.collections[e['collection']];folder=D/'component_packages'/e['key'];ps=bpy.data.scenes.new('组件_'+e['key']);pc=bpy.data.collections.new('02_游戏输出_'+e['key']);ps.collection.children.link(pc);copies=[]
 for ob in c.objects:
  no=ob.copy();no.data=ob.data.copy();no.parent=None;no.location=(0,0,0);no.rotation_euler=(0,0,0);no.scale=(1,1,1);pc.objects.link(no);copies.append(no)
 for ob in copies:
  for m in ob.data.materials:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:n.image.filepath='D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
 bpy.data.libraries.write(str(folder/(e['key']+'.blend')),{ps},path_remap='RELATIVE_ALL',fake_user=True,compress=True)
 for ob in copies:
  me=ob.data;bpy.data.objects.remove(ob,do_unlink=True)
  if me.users==0:bpy.data.meshes.remove(me)
 bpy.data.scenes.remove(ps);bpy.data.collections.remove(pc)
for c in src.children:
 for ob in c.objects:
  for m in ob.data.materials:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:n.image.filepath='//../../../shared/palettes/sea_cabin_timber_8x8_512.png'
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v002.blend'),compress=True)
print('REPACKAGE_DONE',len(cat))
