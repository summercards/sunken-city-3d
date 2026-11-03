import bpy,json
s=bpy.context.scene;root=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'));src=next(c for c in root.children if c.name.startswith('01_制作'))
canonical={}
for role in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']:
 used=[m for c in src.children for ob in c.objects for m in ob.data.materials if role in m.name]
 # choose the newest source role by its count, not a stale orphan reference
 counts={m:sum(1 for c in src.children for ob in c.objects for ma in ob.data.materials if ma==m) for m in set(used)}
 canonical[role]=max(counts,key=counts.get)
for c in src.children:
 for ob in c.objects:
  for i,m in enumerate(ob.data.materials):
   role=next(r for r in canonical if r in m.name);ob.data.materials[i]=canonical[role]
for role,m in canonical.items():m.name='ORF2_FINAL_'+role
# canonical glass alpha and moderate PBR parameters
bs=next(n for n in canonical['SEA_Gloss'].node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Alpha'].default_value=.30
print(json.dumps({'canonical':{k:v.name for k,v in canonical.items()},'scene':s.name},ensure_ascii=False))
