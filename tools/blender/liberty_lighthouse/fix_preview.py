import bpy,json,hashlib
from pathlib import Path
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';W=R/'sea-work/liberty_lighthouse'
sc=bpy.data.scenes['巨手灯塔_参考装配'];bpy.context.window.scene=sc
for c in bpy.data.collections:
 if not c.name.startswith('SEA-SCENE-LHL-'):continue
 root=next((o for o in c.objects if o.type=='EMPTY'),None)
 if not root:continue
 pts=[o.matrix_world@v.co for o in c.objects if o.type=='MESH' for v in o.data.vertices]
 ctr=[(min(v[i] for v in pts)+max(v[i] for v in pts))/2 for i in [0,1]]+[min(v.z for v in pts)]
 for o in c.objects:
  if o!=root:
   for k in range(3):o.location[k]-=ctr[k]
 root.location=(0,0,0);root.rotation_euler=(0,0,0);root.scale=(1,1,1);root.matrix_parent_inverse.identity();c.instance_offset=(0,0,0)
for m in bpy.data.materials:
 if m.name.startswith('SEA_') and m.use_nodes:
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE' and n.image:n.image.filepath=str(pal);n.image.reload()
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'liberty_lighthouse.blend'),compress=True)
sc.render.filepath=str(W/'beauty_fixed.png');bpy.ops.render.render(write_still=True)
print(json.dumps({'corrected_collections':len([c for c in bpy.data.collections if c.name.startswith('SEA-SCENE-LHL-')]),'palette':str(pal)},ensure_ascii=False))
