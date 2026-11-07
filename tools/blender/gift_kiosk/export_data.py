"""Export optimized bpy meshes as indexed glTF 2.0, without a depsgraph operator."""
import bpy,json,hashlib,struct,os
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk/v001';OD=D/'export/v001';OPT=OD/'gift_kiosk_optimized_v001.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((OD/'optimization_manifest.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
assert Path(bpy.data.filepath).resolve()==OPT.resolve() and sha(OPT)==report['optimized_sha256']
def export_component(e):
 blob=bytearray();views=[];access=[];meshes=[];nodes=[{'name':'Asset_'+e['key'],'children':[]}]
 def add(values,fmt,ctype,kind,target,minmax=False):
  while len(blob)%4:blob.append(0)
  start=len(blob)
  flat=[v for row in values for v in row] if kind!='SCALAR' else values
  blob.extend(struct.pack('<'+fmt*len(flat),*flat));view=len(views)
  views.append({'buffer':0,'byteOffset':start,'byteLength':len(blob)-start,'target':target})
  a={'bufferView':view,'componentType':ctype,'count':len(values),'type':kind}
  if minmax:a.update(min=[min(row[i] for row in values) for i in range(3)],max=[max(row[i] for row in values) for i in range(3)])
  access.append(a);return len(access)-1
 materials=[]
 for role in e['material_roles']:
  positions=[];normals=[];uvs=[];indices=[];cache={}
  for o in bpy.data.collections[e['collection']].objects:
   if o.type!='MESH' or o.get('role')!=role:continue
   me=o.data;me.calc_loop_triangles();uv=me.uv_layers['PaletteUV']
   corner_normals=me.corner_normals
   for tri in me.loop_triangles:
    for li in tri.loops:
     vi=me.loops[li].vertex_index;p=me.vertices[vi].co;n=corner_normals[li].vector;t=uv.data[li].uv
     key=(me.as_pointer(),vi,tuple(round(c,7) for c in n),tuple(round(c,7) for c in t))
     if key not in cache:
      cache[key]=len(positions);positions.append((p.x,p.z,-p.y));normals.append((n.x,n.z,-n.y));uvs.append((t.x,1-t.y))
     indices.append(cache[key])
  # glTF UV V originates at the top; Godot's glTF importer converts it back.
  mat_idx=len(materials);materials.append({'name':role,'pbrMetallicRoughness':{'baseColorFactor':[1,1,1,.13 if role=='SEA_Gloss' else 1],'metallicFactor':.12 if role=='SEA_Metal' else 0,'roughnessFactor':.13 if role=='SEA_Gloss' else (.28 if role=='SEA_Metal' else .52)},'alphaMode':'BLEND' if role=='SEA_Gloss' else 'OPAQUE','doubleSided':role=='SEA_Gloss'})
  pa=add(positions,'f',5126,'VEC3',34962,True);na=add(normals,'f',5126,'VEC3',34962);ua=add(uvs,'f',5126,'VEC2',34962);ia=add(indices,'I',5125,'SCALAR',34963)
  mi=len(meshes);meshes.append({'name':e['key']+'__'+role,'primitives':[{'attributes':{'POSITION':pa,'NORMAL':na,'TEXCOORD_0':ua},'indices':ia,'material':mat_idx,'mode':4}]})
  nodes[0]['children'].append(len(nodes));nodes.append({'name':e['key']+'__'+role,'mesh':mi,'extras':{'semantic_role':role}})
 doc={'asset':{'version':'2.0','generator':'sea Blender MCP optimized data exporter v1'},'scene':0,'scenes':[{'name':e['key'],'nodes':[0]}],'nodes':nodes,'meshes':meshes,'materials':materials,'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':access}
 js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4);blob+=b'\0'*((-len(blob))%4)
 target=R/f"godot/assets/models/facilities/gift_kiosk/{e['key']}/{e['key']}.glb";target.parent.mkdir(parents=True,exist_ok=True)
 target.write_bytes(struct.pack('<III',0x46546C67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4E4F534A)+js+struct.pack('<II',len(blob),0x004E4942)+blob)
 return target,doc,sum(len(mesh['primitives']) for mesh in meshes),sum(access[p['indices']]['count']//3 for mesh in meshes for p in mesh['primitives'])
for row in report['components']:
 e=next(e for e in cat if e['asset_id']==row['asset_id']);target,doc,surfaces,triangles=export_component(e)
 assert triangles==row['triangles_after'],e['key']+' triangle mismatch'
 row.update(optimized_sha256=report['optimized_sha256'],optimized_reopened=True,glb=target.relative_to(R).as_posix(),glb_sha256=sha(target),source_sha256_after=sha(R/e['component_source']),exported_triangles=triangles,exported_surfaces=surfaces)
 print('EXPORTED',e['key'],triangles,flush=True)
for path,expected in report['protected_sources'].items():assert sha(Path(path))==expected,path
assert sha(OPT)==report['optimized_sha256']
report['exported_components']=len(cat);(OD/'optimization_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('GKS_DATA_EXPORTED',len(cat),flush=True)
