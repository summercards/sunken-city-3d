"""Independent saved-library audit, with destructive-error rejection selftest on in-memory copies."""
import bpy, hashlib, json, os, sys
from pathlib import Path
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_libraries/v001'
P=json.loads((R/'art_source/vegetation/libraries/v001/component_plan.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def sig(me):
 d={'v':[[round(x,6) for x in v.co] for v in me.vertices], 'faces':[list(p.vertices) for p in me.polygons], 'smooth':[p.use_smooth for p in me.polygons], 'mi':[p.material_index for p in me.polygons], 'uv':{l.name:[[round(x,7) for x in v.uv] for v in l.data] for l in me.uv_layers}, 'colors':{a.name:{'domain':a.domain,'type':a.data_type,'values':[[round(x,7) for x in v.color] for v in a.data]} for a in me.color_attributes}}
 return hashlib.sha256(json.dumps(d,sort_keys=True,separators=(',',':')).encode()).hexdigest()
checks=0;fails=[];results=[]
def ck(v,msg):
 global checks
 checks+=1
 if not v:fails.append(msg)
for lib in P['libraries']:
 path=R/lib['path'];man=json.loads(path.with_name('library_manifest.json').read_text(encoding='utf-8'))
 ck(sha(path)==man['sha256'],lib['library_id']+': saved hash')
 bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False)
 ck(len(bpy.data.libraries)==0,'all assets are appended, no hidden external blend links')
 ck(len(bpy.data.scenes)==2,'two scenes gallery/master separation')
 ck(len(man['members'])==man['member_count'],'member count')
 by_asset={}
 for row in man['members']:
  c=bpy.data.collections.get(row['collection']);ck(c is not None,'collection '+row['collection'])
  if not c:continue
  ck(list(c.instance_offset)==[0,0,0],'zero collection offset '+c.name)
  ck(c.get('asset_id')==row['asset_id'],'asset id '+c.name)
  by_asset.setdefault(row['asset_id'],[]).append(row)
  if row['meshes']:
   ck(c.asset_data is not None,'asset browser mark '+c.name)
   ck(len([o for o in c.objects if o.type=='MESH'])==len(row['meshes']),'mesh count '+c.name)
  for m in row['meshes']:
   o=bpy.data.objects.get(m['object']);ck(o is not None,'object '+m['object'])
   if o is None:continue
   ck(o.type=='MESH' and len(o.data.vertices)>0,'real editable geometry '+o.name)
   ck(o.parent is None and all(abs(o.matrix_world[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4)),'identity/root '+o.name)
   o.data.calc_loop_triangles();ck(len(o.data.loop_triangles)==m['triangles'],'triangle count '+o.name)
   ck(len(o.data.polygons)==m['polygons'],'polygon count '+o.name)
   ck(sig(o.data)==m['signature'],'geometry topology UV color fingerprint '+o.name)
   ck([l.name for l in o.data.uv_layers]==m['uv_layers'],'UV layers preserved '+o.name)
   ck([a.name for a in o.data.color_attributes]==m['color_attributes'],'color attributes preserved '+o.name)
   ck(len(o.data.materials)>0,'material slots '+o.name)
  ins=bpy.data.objects.get(row['gallery']['instance']);ck(ins is not None and ins.instance_collection==c,'gallery uses collection instance '+c.name)
 for e in lib['components']:
  ck(e['asset_id'] in by_asset,'planned member included '+e['asset_id'])
 # Cross-language matrix assertion: compare Blender bounds to the independently measured Godot JSON bounds.
 native=json.loads((W/'native_meshes.json').read_text(encoding='utf-8'))['entries']
 for row in man['members']:
  if not row.get('native_key'):continue
  n=next(n for n in native if n['key']==row['native_key'])
  original=n['bounds'];gmin=original['min'];gmax=original['max']
  expected_size=[gmax[0]-gmin[0],gmax[2]-gmin[2],gmax[1]-gmin[1]]
  actual=[row['bounds'][1][i]-row['bounds'][0][i] for i in range(3)]
  ck(max(abs(a-b) for a,b in zip(expected_size,actual))<1e-5,'Godot->Blender measured bound parity '+row['collection'])
  ck(row['triangles']==n['triangles'],'native triangle parity '+row['collection'])
  ck(all(m['material'].get('category')!='unknown' for m in n['meshes']),'native material metadata complete '+row['collection'])
  for source_mesh,target_mesh in zip(n['meshes'],row['meshes']):
   ob=bpy.data.objects[target_mesh['object']];source_colors=source_mesh.get('colors',[])
   if source_colors:
    got=ob.data.color_attributes.get('Color');ck(got is not None and len(got.data)==len(source_colors),'native Color length preserved '+ob.name)
    if got:ck(max(abs(got.data[i].color[j]-v[j]) for i,v in enumerate(source_colors) for j in range(4))<1e-6,'native Color numeric parity '+ob.name)
   material=ob.data.materials[0];bs=material.node_tree.nodes.get('Principled BSDF');original_color=source_mesh['material'].get('base_color',[1,1,1,1]);linear=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in original_color[:3]]
   ck(max(abs(bs.inputs['Base Color'].default_value[i]-linear[i]) for i in range(3))<1e-5,'native material albedo parity '+ob.name)
 for im in bpy.data.images:
  if im.source!='FILE':continue
  p=Path(bpy.path.abspath(im.filepath));ck(p.is_file(),'external image exists '+im.filepath)
  ck(not bool(im.packed_file),'no duplicated packed image '+im.name)
  match=next((x for x in man['images'] if x['name']==im.name),None)
  ck(match is not None and p.is_file() and sha(p)==match['sha256'],'external image hash '+im.name)
 if 'PLANTING' in lib['library_id']:
  crop_ids=[e['asset_id'] for e in lib['components'] if e['domain']=='crops']
  for aid in crop_ids:
   rows=by_asset.get(aid,[])
   stages=[r for r in rows if 'stage_' in r['variant'] or ('stage' in r.get('native_key','') and r['variant']!='收获手持')]
   ck(len(stages)==4,aid+' exactly four distinct stage collections')
   ck(any(r['variant']=='收获手持' for r in rows),aid+' harvested held model')
  ck(sum(1 for r in man['members'] if r.get('instance_count'))==2,'single/six cell instance assemblies')
 else:ck(len(by_asset)==98,'98 distinct vegetation asset IDs')
 # Negative controls: validator must detect an edited vertex, missing UV layer and missing color attribute.
 candidates=[o.data for o in bpy.data.objects if o.type=='MESH' and len(o.data.vertices)>0]
 me=next(m for m in candidates if m.uv_layers)
 cp=me.copy();base=sig(cp);cp.vertices[0].co.x+=.01;ck(sig(cp)!=base,'selftest rejects geometry drift');bpy.data.meshes.remove(cp)
 cp=me.copy();base=sig(cp);cp.uv_layers.remove(cp.uv_layers[0]);ck(sig(cp)!=base,'selftest rejects lost UV');bpy.data.meshes.remove(cp)
 colored=next((m for m in candidates if m.color_attributes),None)
 if colored:
  cp=colored.copy();base=sig(cp);cp.color_attributes.remove(cp.color_attributes[0]);ck(sig(cp)!=base,'selftest rejects lost color');bpy.data.meshes.remove(cp)
 else:
  # Crops legitimately use material colors, not vertex colors. Exercise loss detection on a temporary mesh only.
  cp=me.copy();cp.color_attributes.new(name='SelftestColor',type='FLOAT_COLOR',domain='POINT');base=sig(cp);cp.color_attributes.remove(cp.color_attributes[0]);ck(sig(cp)!=base,'selftest rejects lost synthetic color channel without changing crop');bpy.data.meshes.remove(cp)
 results.append({'library_id':lib['library_id'],'path':lib['path'],'sha256':man['sha256'],'asset_ids':len(by_asset),'collections':man['member_count'],'meshes':sum(len(r['meshes']) for r in man['members']),'polygons':sum(r['polygons'] for r in man['members'] if r['meshes']),'triangles':man['triangles_unique_meshes'],'images':len(man['images'])})
# A clean-file Append round-trip is independent from opening the saved gallery scene.
for lib in P['libraries']:
 path=R/lib['path'];man=json.loads(path.with_name('library_manifest.json').read_text(encoding='utf-8'))
 names=[m['collection'] for m in man['members']]
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(path),link=False) as (available,loaded):
  ck(all(n in available.collections for n in names),'all members available to Append '+lib['library_id'])
  loaded.collections=names
 for c,row in zip(loaded.collections,man['members']):
  ck(c is not None and c.get('asset_id')==row['asset_id'],'clean Append asset identity '+row['collection'])
  if c:bpy.context.scene.collection.children.link(c)
 ck(all(c.library is None and all(o.library is None and (o.data is None or o.data.library is None) for o in c.all_objects) for c in loaded.collections if c),'Append creates editable local collections and meshes '+lib['library_id'])
for p,h in P['protected_inputs'].items():ck((R/p).is_file() and sha(R/p)==h,'original input untouched '+p)
native_protection=json.loads((W/'native_meshes.json').read_text(encoding='utf-8'))['protected_inputs']
for p,h in native_protection.items():ck((R/p).is_file() and sha(R/p)==h,'native procedural input untouched '+p)
report={'native_protected_input_count':len(native_protection),'passed':not fails,'checks':checks,'failures':fails,'libraries':results,'protected_input_count':len(P['protected_inputs']),'scope':'source archive only; no Godot integration or rights promotion','negative_controls':['edited vertex','removed UV layer','removed color attribute']}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('BOTANICAL_LIBRARY_VERIFY '+json.dumps(report,ensure_ascii=False))
if fails:raise RuntimeError(f'{len(fails)} source archive failures')
