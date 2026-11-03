import bpy
for mn in ['ORF2_FINAL_SEA_Matte','ORF2_FINAL_SEA_Metal']:
 m=bpy.data.materials.get(mn); print('MAT',mn)
 if m and m.use_nodes:
  for n in m.node_tree.nodes:
   if n.type in {'TEX_IMAGE','UVMAP','MAPPING','BSDF_PRINCIPLED'}: print(' NODE',n.name,n.type,'props',[(i.name, getattr(i,'default_value',None)) for i in n.inputs if i.name in {'Base Color','Roughness','Metallic'}], 'uv',getattr(n,'uv_map',None),'img',getattr(getattr(n,'image',None),'filepath',None))
for name in ['ORF3_厚实混凝土结构柱_0','ORF5_柱体大块崩缺_p0','ORF5_柱体崩口内里_p0']:
 o=bpy.data.objects.get(name); print('OBJ',name)
 if o and o.type=='MESH':
  print(' UV layers',[u.name for u in o.data.uv_layers]); u=o.data.uv_layers.get('PaletteUV') or (o.data.uv_layers[0] if o.data.uv_layers else None)
  print(' UV sample',[(round(x.uv.x,3),round(x.uv.y,3)) for x in u.data[:12]] if u else [])
  print('mats',[m.name if m else None for m in o.data.materials])
