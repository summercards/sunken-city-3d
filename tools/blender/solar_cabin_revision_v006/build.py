"""Derive v005 from saved v004; all edits are in the new source only."""
import bpy,bmesh,json,math,hashlib,os
from pathlib import Path
from mathutils import Matrix,Vector,Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v006';OLD=D.parent/'v005';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v006';P=json.loads((D/'component_plan.json').read_text());assert P['status']=='frozen_before_geometry'
PAL=R/P['palette'];cells={x['name']:x for x in json.loads(PAL.with_suffix('.json').read_text())['cells']}
oldcat=json.loads((OLD/'catalog.json').read_text())['components'];cat={x['key']:x.copy() for x in oldcat};spec={x['key']:x for x in P['components']}
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunny_bloom_retreat.blend'));bpy.context.preferences.filepaths.save_version=0;S=bpy.context.scene;S.name='太阳能木屋-海上区域-v006';LIB=next(s for s in bpy.data.scenes if s!=S)
M={key:bpy.data.materials['SEA_'+key] for key in ['Matte','Metal','Gloss','Emission']}
def paint(me,color,faces=None):
 uv=me.uv_layers.get('PaletteUV') or me.uv_layers.new(name='PaletteUV')
 for layer in list(me.uv_layers):
  if layer.name!='PaletteUV':me.uv_layers.remove(layer)
 me.uv_layers.active_index=0;uv=me.uv_layers['PaletteUV'];uv.active_render=True;c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in me.polygons if faces is None else faces:
  for k,l in enumerate(f.loop_indices):
   a=2*math.pi*k/len(f.loop_indices);uv.data[l].uv=(u+.025*math.cos(a),v+.025*math.sin(a))
def recolor(key,color,wood_only=False):
 for o in bpy.data.collections[cat[key]['collection']].objects:
  if o.type!='MESH':continue
  fs=list(o.data.polygons);uv=o.data.uv_layers['PaletteUV']
  if wood_only:fs=[f for f in fs if int(uv.data[f.loop_indices[0]].uv.y*8)==6]
  paint(o.data,color,fs)
def select(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def box_mesh(key,dimensions,color,bevel=.045):
 col=bpy.data.collections.get(cat[key]['collection']) if key in cat else None
 if col:
  for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
 else:
  col=bpy.data.collections.new(spec[key]['asset_id']);LIB.collection.children.link(col)
 S.collection.children.link(col)
 bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,dimensions[2]/2));o=bpy.context.object;o.scale=dimensions
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o);select(o);bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
 b=o.modifiers.new('实体倒角','BEVEL');b.width=bevel;b.segments=3;bpy.ops.object.modifier_apply(modifier=b.name)
 for f in o.data.polygons:f.use_smooth=True
 n=o.modifiers.new('加权法线','WEIGHTED_NORMAL');n.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=n.name)
 o.name=key+'_mesh';o.data.materials.clear();o.data.materials.append(M['Matte']);paint(o.data,color)
 root=bpy.data.objects.new('ROOT_'+key,None);col.objects.link(root);o.parent=root;S.collection.children.unlink(col)
 cat[key]=dict(spec[key],collection=col.name,root=root.name,source_anchor=[0,0,0]);return col

# Preserve the full existing thickness, replace solid cement floors with long boards.
def board_floor(key,dims,count):
 w,d,h=dims;col=box_mesh(key,(w,d/count-.014,h),'wood_light',.04)
 ob=next(o for o in col.objects if o.type=='MESH');root=ob.parent
 ob.data.transform(Matrix.Translation((0,-d/2+d/(2*count),0)))
 for i in range(1,count):
  cp=ob.copy();cp.data=ob.data.copy();cp.data.transform(Matrix.Translation((0,i*d/count,0)));col.objects.link(cp);cp.parent=root
board_floor('concrete_slab',(7.5,6.2,.40),12)
board_floor('terrace',(5.20,3.73,.355),8)
byid={e['asset_id']:e['key'] for e in oldcat}
for o in list(S.objects):
 if o.instance_type!='COLLECTION':continue
 k=byid[o.instance_collection.name]
 if k in {'sail','canopy_hook'}:bpy.data.objects.remove(o,do_unlink=True);continue
 if k in {'pink_flower','daisy'}:o.scale*=.75
 # Keep the umbrella table near the front-right deck corner; canopy clears the awning.
 targets={'umbrella':(4.70,-9.00),'table.001':(4.65,-8.55),'stool':(3.50,-8.92),'stool.001':(5.50,-7.70),'bottle':(5.00,-8.40),'cooler':(2.25,-7.95),'foliage.039':(5.50,-6.85),'daisy.002':(5.50,-7.02)}
 if o.name in targets:o.location.x,o.location.y=targets[o.name]
 # Indoor walking floor remains timber too; upper structural walls stay plaster.
 if k=='house':
  for mesh in o.instance_collection.objects:
   if mesh.type=='MESH':paint(mesh.data,'wood_light',[f for f in mesh.data.polygons if max(mesh.data.vertices[v].co.z for v in f.vertices)<.13])
# Update normalized component bounds, per-instance manifests and semantic parts.
byid.update({e['asset_id']:key for key,e in spec.items()});instances=[];used=set()
for o in S.objects:
 if o.instance_type!='COLLECTION':continue
 key=byid[o.instance_collection.name];used.add(key);instances.append(dict(name=o.name,asset_id=spec[key]['asset_id'],position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale),category=spec[key]['category'],module=o['module']))
entries=[]
for key in sorted(used):
 item=dict(cat[key]);item.update(spec[key]);col=bpy.data.collections[item['collection']];vs=[v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[i] for v in vs) for i in range(3)];hi=[max(v[i] for v in vs) for i in range(3)];item.update(bounds_min=lo,bounds_size=[hi[i]-lo[i] for i in range(3)],instance_count=sum(e['asset_id']==item['asset_id'] for e in instances),component_source=str((D/'components'/key/(key+'.blend')).relative_to(R)),triangle_budget=10000)
 item['geometry_fingerprint']=hashlib.sha256(b''.join(repr(tuple(v.co)).encode() for o in col.objects if o.type=='MESH' for v in o.data.vertices)).hexdigest();entries.append(item)
for key,item in cat.items():
 if key not in used:
  col=bpy.data.collections.get(item['collection'])
  if col:bpy.data.collections.remove(col)
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=bpy.path.relpath(str(PAL),start=str(D))
P['components']=[spec[e['key']] for e in entries];(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n');(D/'catalog.json').write_text(json.dumps({'components':entries},ensure_ascii=False,indent=2)+'\n');(D/'component_instances.json').write_text(json.dumps({'coordinate_contract':{'plane':'XY','up':'+Z','godot':'(x,y,z) -> (x,z,-y)'},'instances':instances},ensure_ascii=False,indent=2)+'\n')
S['revision']='v006';S.render.resolution_x=1100;S.render.resolution_y=1100;S.cycles.samples=32;S.camera.data.ortho_scale=24
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunny_bloom_retreat.blend'),compress=True)
(W/'previews').mkdir(exist_ok=True);S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True);print('BUILT',len(entries),len(instances),flush=True)
