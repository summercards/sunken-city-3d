"""Independent reopened and Append audit for 294 three-growth plant models."""
import bpy,hashlib,json,math,os
from pathlib import Path
R=Path(__file__).resolve().parents[3];OUT=R/'art_source/vegetation/libraries/v002';W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_growth/v002/vegetation'
P=json.loads((OUT/'component_plan.json').read_text(encoding='utf-8'));M=json.loads((OUT/'library_manifest.json').read_text(encoding='utf-8'));checks=0;errors=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ck(v,msg):
 global checks
 checks+=1
 if not v:errors.append(msg)
def bounds(me):return [[min(v.co[i] for v in me.vertices) for i in range(3)],[max(v.co[i] for v in me.vertices) for i in range(3)]]
def geometry_fingerprint(me):
 return hashlib.sha256(json.dumps({'v':[[round(v.co[i],6) for i in range(3)] for v in me.vertices],'f':[list(p.vertices) for p in me.polygons]},sort_keys=True).encode()).hexdigest()
def _mesh_objects(value):
 if hasattr(value,'vertices') and hasattr(value,'polygons'):return [value]
 return [value] if hasattr(value,'data') and value.type=='MESH' else [o for o in value.objects if o.type=='MESH']
def normalized_topology_fingerprint(value):
 payload=[]
 for ob in sorted(_mesh_objects(value),key=lambda o:(o.get('organ_counts',''),len(o.data.vertices),len(o.data.polygons))):
  me=ob.data;bb=bounds(me);span=[max(bb[1][i]-bb[0][i],1e-12) for i in range(3)]
  payload.append({'organ':ob.get('organ_counts',ob.get('organ_type')),'v':[[round((v.co[i]-bb[0][i])/span[i],6) for i in range(3)] for v in me.vertices],'f':[list(p.vertices) for p in me.polygons]})
 return hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def organ_topology(value):
 return tuple(sorted((str(ob.get('organ_counts',ob.get('organ_type'))),len(ob.data.vertices),len(ob.data.polygons)) for ob in _mesh_objects(value)))
def root_anchor_ok(value,anchor):
 objs=_mesh_objects(value);meshes=[o if hasattr(o,'vertices') else o.data for o in objs]
 bb=bounds(meshes[0]) if len(meshes)==1 else [[min(v.co[i] for me in meshes for v in me.vertices) for i in range(3)],[max(v.co[i] for me in meshes for v in me.vertices) for i in range(3)]]
 return abs((bb[1][2] if anchor=='top_center_attachment' else bb[0][2]))<1e-6
def growth_forms_valid(rows,collections):
 if [r['growth_key'] for r in rows]!=['small','medium','large']:return False
 return len({normalized_topology_fingerprint(c) for c in collections})==3 and len({organ_topology(c) for c in collections})==3
def temp_scaled_object(source,factor):
 me=source.data.copy()
 for v in me.vertices:v.co*=factor
 ob=bpy.data.objects.new('__verification_scaled__',me);ob['organ_counts']=source.get('organ_counts','{}')
 return ob
def uv_errors(me):
 out=[];uv=me.uv_layers.get('PaletteUV')
 if not uv:return ['missing PaletteUV']
 for p in me.polygons:
  vals=[uv.data[i].uv for i in p.loop_indices];cells={(int(v.x*8),int(v.y*8)) for v in vals}
  area=abs(sum(vals[i].x*vals[(i+1)%len(vals)].y-vals[(i+1)%len(vals)].x*vals[i].y for i in range(len(vals))))*.5
  if len(cells)!=1 or area<1e-8:out.append(p.index);continue
  cx,cy=next(iter(cells))
  if not all((cx/8+8/512-1e-7)<=v.x<=((cx+1)/8-8/512+1e-7) and (cy/8+8/512-1e-7)<=v.y<=((cy+1)/8-8/512+1e-7) for v in vals):out.append(p.index)
 return out
ck(sha(R/M['path'])==M['sha256'],'saved file hash');bpy.ops.wm.open_mainfile(filepath=str(R/M['path']),load_ui=False)
ck(len(M['members'])==294,'exactly 294 forms');ck(len(M['plants'])==98,'exactly 98 species');ck(len({p['display_name'] for p in M['plants']})==98,'unique Chinese names');ck(M['season_variants'] is False,'no seasons');ck(len(bpy.data.scenes)==2,'two authoring scenes')
ck(all(v<=50 for v in P['subsuite_component_counts'].values()),'component subplans <=50')
by={}
for m in M['members']:
 by.setdefault(m['asset_id'],[]).append(m);c=bpy.data.collections.get(m['collection']);ck(c is not None,'collection '+m['collection'])
 if c is None:continue
 ck(c.get('growth_key')==m['growth_key'] and c.get('display_name')==m['display_name'],'metadata '+c.name);ck(tuple(c.instance_offset)==(0,0,0),'zero offset '+c.name);ck(c.asset_data is not None,'asset marked '+c.name)
 ob=bpy.data.objects.get(m['object']);ck(ob is not None and ob.type=='MESH','real geometry '+c.name)
 if ob is None:continue
 me=ob.data;me.calc_loop_triangles();ck(len(me.vertices)>10 and len(me.polygons)>5,'nonempty plant '+c.name);ck(ob.parent is None and all(abs(ob.matrix_world[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4)),'identity transform '+ob.name)
 ck(geometry_fingerprint(me)==m['geometry_fingerprint'],'geometry fingerprint '+c.name);ck(len(me.loop_triangles)==m['triangles']<=m['triangle_budget'],'true triangle budget '+c.name);ck(len(me.polygons)==m['polygons'],'polygon count '+c.name);b=bounds(me);ck(max(abs(b[i][j]-m['bounds'][i][j]) for i in range(2) for j in range(3))<1e-6,'bounds '+c.name)
 ck(root_anchor_ok(ob,m['anchor']),'root anchor '+c.name);ck(abs(b[0][0]+b[1][0])<1e-6 and abs(b[0][1]+b[1][1])<1e-6,'centered XY '+c.name)
 ck(not uv_errors(me),'every face UV area single-safe-cell '+c.name);ck(me.uv_layers.active.name=='PaletteUV' and me.uv_layers['PaletteUV'].active_render,'active UV '+c.name);ck([x.name for x in me.materials]==['SEA_Matte','SEA_Gloss'],'shared material roles '+c.name)
 wind=me.color_attributes.get('WindData');ck(wind is not None and wind.domain=='POINT','WindData retained '+c.name)
 if wind:
  roots=[v.index for v in me.vertices if abs(v.co.z)<1e-6];ck(bool(roots) and max(wind.data[i].color[0] for i in roots)<1e-6,'root wind fixed '+c.name);ck(all(0<=x<=1 for d in wind.data for x in d.color),'WindData numeric range '+c.name)
 ins=bpy.data.objects.get(m['gallery_instance']);ck(ins is not None and ins.instance_collection==c,'true collection instance '+c.name)
for aid,rows in by.items():
 rows=sorted(rows,key=lambda x:['small','medium','large'].index(x['growth_key']));cols=[bpy.data.collections[r['collection']] for r in rows];ck([r['growth_key'] for r in rows]==['small','medium','large'],'three growth forms '+aid);ck(len({r['triangles'] for r in rows})==3,'topology really changes '+aid);ck(len({json.dumps(r['organ_counts'],sort_keys=True) for r in rows})==3,'organ count really changes '+aid);ck(len({r['geometry_fingerprint'] for r in rows})==3,'unique geometry '+aid);ck(len({normalized_topology_fingerprint(c) for c in cols})==3,'normalized topology really changes '+aid);ck(len({organ_topology(c) for c in cols})==3,'organ topology really changes '+aid)
 sizes=[[r['bounds'][1][i]-r['bounds'][0][i] for i in range(3)] for r in rows]
 ck(sizes[0][2]<sizes[1][2]<sizes[2][2],'height increasing '+aid);ck(max(sizes[0][:2])<max(sizes[1][:2])<max(sizes[2][:2]),'crown increasing '+aid);ck(len({r['display_scale'] for r in rows})==1,'same display scale shows true growth '+aid)
ck({p['asset_id'] for p in P['plants']}==set(by),'all planned species included')
for mat in [bpy.data.materials.get('SEA_Matte'),bpy.data.materials.get('SEA_Gloss')]:
 ck(mat is not None,'material role present')
 if mat:
  textures=[n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'];ck(len(textures)==1 and textures[0].interpolation=='Closest','palette nearest');ck(len([n for n in mat.node_tree.nodes if n.type=='UVMAP' and n.uv_map=='PaletteUV'])==1,'explicit PaletteUV node')
ck(len([i for i in bpy.data.images if i.source=='FILE'])==1,'unique external palette')
for i in bpy.data.images:
 if i.source=='FILE':ck(Path(bpy.path.abspath(i.filepath)).resolve()==(R/P['palette']).resolve() and not i.packed_file,'external canonical palette')
# Negative controls run on temporary copies, never saved back.
me=bpy.data.objects[M['members'][0]['object']].data;cp=me.copy();cp.uv_layers['PaletteUV'].data[0].uv=(1.2,-.1);ck(bool(uv_errors(cp)),'selftest rejects UV overflow');bpy.data.meshes.remove(cp)
rows=sorted(next(iter(by.values())),key=lambda x:['small','medium','large'].index(x['growth_key']));ck(not growth_forms_valid(rows[:2],[bpy.data.collections[r['collection']] for r in rows[:2]]),'selftest rejects missing form')
source=bpy.data.objects[rows[0]['object']];scaled=[temp_scaled_object(source,f) for f in (1.0,2.0,3.0)];ck(not growth_forms_valid(rows,scaled),'selftest rejects scale-only copies');
for ob in scaled:bpy.data.meshes.remove(ob.data)
vine_row=next(r for r in M['members'] if r['anchor']=='top_center_attachment');vine_me=bpy.data.objects[vine_row['object']].data.copy()
for v in vine_me.vertices:v.co.z+=.05
ck(not root_anchor_ok(vine_me,'top_center_attachment'),'selftest rejects shifted vine root');bpy.data.meshes.remove(vine_me)
# Source file appendability from a clean context, including editable geometry.
names=[r['collection'] for r in M['members']];bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(R/M['path']),link=False) as (src,dst):ck(all(n in src.collections for n in names),'all 294 individually Appendable');dst.collections=names
for c in dst.collections:ck(c is not None and c.library is None and all(o.data.library is None for o in c.objects if o.type=='MESH'),'editable Append '+str(c.name if c else 'missing'))
for p,h in P['protected_inputs'].items():ck(sha(R/p)==h,'protected source '+p)
report={'passed':not errors,'checks':checks,'failures':errors,'plant_count':98,'model_count':294,'triangles':M['triangles'],'polygons':M['polygons'],'sha256':M['sha256'],'season_variants':False,'negative_controls':['missing form','UV overflow','root displacement','scale-only copies'],'runtime_integration':False,'scope':'source model verification only'}
(W/'verification_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('VEGETATION_GROWTH_VERIFICATION '+json.dumps(report,ensure_ascii=False))
if errors:raise RuntimeError(str(len(errors))+' validation failures')
