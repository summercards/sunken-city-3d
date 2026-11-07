"""Save/reopen source packages and independently inspect actual Blender data."""
import bpy,json,math,hashlib,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
SOURCE=D/'gift_kiosk.blend';cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
checks=0;errors=[];face_count=0;packages=0
def require(ok,label):
 global checks
 checks+=1
 if not ok:errors.append(label)
def inspect(col,e):
 global face_count
 require(col is not None,e['key']+' collection exists')
 if col is None:return
 require(col.instance_offset.length<1e-7,e['key']+' collection offset zero')
 pts=[];triangles=polys=0;roles=set()
 for o in col.objects:
  require(o.type=='MESH',o.name+' mesh')
  if o.type!='MESH':continue
  require(max(abs(o.matrix_world[i][j]-Matrix.Identity(4)[i][j]) for i in range(4) for j in range(4))<1e-6,o.name+' identity transform')
  me=o.data;pts.extend(v.co for v in me.vertices);me.calc_loop_triangles();triangles+=len(me.loop_triangles);polys+=len(me.polygons)
  require(len(me.uv_layers)==1 and me.uv_layers.active.name=='PaletteUV',o.name+' unique active PaletteUV')
  require(me.uv_layers.active_render.name=='PaletteUV' if hasattr(me.uv_layers,'active_render') else me.uv_layers[0].active_render,o.name+' render PaletteUV')
  uv=me.uv_layers.get('PaletteUV')
  if uv:
   for p in me.polygons:
    face_count+=1;coords=[uv.data[i].uv for i in p.loop_indices]
    area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(coords,coords[1:]+coords[:1])))*.5
    require(area>1e-9,o.name+' UV area '+str(p.index))
    cells={(int(v.x*8),int(v.y*8)) for v in coords}
    require(len(cells)==1,o.name+' same UV swatch '+str(p.index))
    require(all(.0156-1e-5<=(v.x% .125)<=.1094+1e-5 and .0156-1e-5<=(v.y% .125)<=.1094+1e-5 for v in coords),o.name+' swatch 8px padding '+str(p.index))
  for mat in me.materials:
   role=mat.get('semantic_role','');roles.add(role)
   require(role in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],o.name+' known role')
   for node in mat.node_tree.nodes:
    if node.type=='TEX_IMAGE':
     require(node.interpolation=='Closest',o.name+' nearest palette')
     require(Path(bpy.path.abspath(node.image.filepath)).resolve()==(R/plan['palette']).resolve(),o.name+' unique shared palette path')
     require(node.image.packed_file is None,o.name+' external palette')
  require(all(math.isfinite(c) for v in me.vertices for c in v.co),o.name+' finite vertices')
 require(bool(pts) and triangles>0,e['key']+' nonempty geometry')
 if pts:
  lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
  require(abs(lo[2])<2e-5 and abs(lo[0]+hi[0])<2e-5 and abs(lo[1]+hi[1])<2e-5,e['key']+' bottom centre origin')
  require(max(abs(hi[i]-lo[i]-e['bounds_size'][i]) for i in range(3))<2e-5,e['key']+' recorded bounds')
 return {'triangles':triangles,'polygons':polys,'roles':sorted(roles)}

# The source is saved with a deliberate hero camera and only four live asset roles.
sc=bpy.data.scenes['海上礼品商亭_v001'];bpy.context.window_manager.windows[0].scene=sc
sc.camera.location=(25,-32,17.4);sc.camera.rotation_euler=(Vector((0,0,2.7))-sc.camera.location).to_track_quat('-Z','Y').to_euler()
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
live={m for e in cat['components'] for o in bpy.data.collections[e['collection']].objects for m in o.data.materials}
for m in live:m.name=m['semantic_role']
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
source_hash=sha(SOURCE);palette_hash=sha(R/plan['palette'])
# Save actual openable scenes, not library-only files whose startup scene is empty.
for e in cat['components']:
 col=bpy.data.collections[e['collection']];e.update(inspect(col,e))
for e in cat['components']:
 path=R/e['component_source'];path.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(SOURCE),link=False) as (a,b):b.collections=[e['collection']]
 ps=bpy.context.scene;ps.name='GKS_PACKAGE_'+e['key'];ps.unit_settings.system='METRIC';ps.collection.children.link(b.collections[0])
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(R/plan['palette']),start=str(path.parent))
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
 e.update(source_sha256=sha(path),palette=plan['palette'],palette_sha256=palette_hash,stage='source_verified_runtime_pending')
 (path.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 require(path.exists(),e['key']+' standalone saved')

(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for e in cat['components']:
 bpy.ops.wm.open_mainfile(filepath=str(R/e['component_source']))
 package_scene=bpy.data.scenes.get('GKS_PACKAGE_'+e['key'])
 require(package_scene is not None,e['key']+' scene reopened')
 require(package_scene is not None and len(package_scene.objects)>0,e['key']+' visible independent package')
 inspect(bpy.data.collections.get(e['collection']),e);packages+=1

bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.window_manager.windows[0].scene=bpy.data.scenes['海上礼品商亭_v001']
require(sha(SOURCE)==source_hash,'source unchanged by package writes/reopen')
require(sha(R/plan['palette'])==palette_hash,'palette unchanged')
instances=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances'];actual={o.name:o for o in bpy.context.scene.objects if o.instance_type=='COLLECTION'}
require(len(actual)==len(instances),'instance count matches frozen layout')
require(len(cat['components'])==47,'47 components within 50')
for row in instances:
 o=actual.get(row['name']);require(o is not None,row['name']+' present')
 if o:
  require(max(abs(o.location[i]-row['position'][i]) for i in range(3))<1e-5,row['name']+' position')
  require(max(abs(o.rotation_euler[i]-row['rotation_euler_xyz'][i]) for i in range(3))<1e-5,row['name']+' Euler')
  require(max(abs(o.scale[i]-row['scale'][i]) for i in range(3))<1e-5,row['name']+' scale')
totals={e['key']:e for e in cat['components']}
expanded_triangles=sum(totals[r['key']]['triangles'] for r in instances)
report={'passed':not errors,'checks':checks,'errors':errors,'source_sha256':source_hash,'palette_sha256':palette_hash,'packages_reopened':packages,'components':47,'instances':len(instances),'uv_faces_checked':face_count,'master_triangles':sum(e['triangles'] for e in cat['components']),'expanded_triangles':expanded_triangles,'exit_code':0 if not errors else 1,'commercial_reference_rights':'pending','user_art_acceptance':'pending'}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Reproducible reference views, using exactly the current saved source.
views=[('hero',(25,-32,17.4),(0,0,2.7),27.6),('front',(0,-36,6),(0,0,2.9),24),('back',(0,36,6),(0,0,2.9),24),('left',(-36,0,6),(0,0,2.9),24),('right',(36,0,6),(0,0,2.9),24),('top',(0,0,40),(0,0,0),23),('bottom',(0,0,-35),(0,0,0),23),('close',(17,-22,10),(1,-2,3.8),17)]
sc=bpy.data.scenes['海上礼品商亭_v001'];floor=next(o for o in sc.objects if o.name.startswith('展示地面'))
for name,pos,target,scale in views:
 floor.hide_render=name=='bottom';sc.camera.location=pos;sc.camera.rotation_euler=(Vector(target)-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=scale
 sc.render.resolution_x=1400;sc.render.resolution_y=1200;sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
floor.hide_render=False
# Separate building view (plant instances only hidden), never an export exclusion shortcut.
plants=bpy.data.collections['GKS_03_独立植物'];plants.hide_render=True
sc.camera.location=(25,-32,17.4);sc.camera.rotation_euler=(Vector((0,0,2.7))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=27.6
sc.render.filepath=str(W/'building_only.png');bpy.ops.render.render(write_still=True);plants.hide_render=False
# Factory-settings package verification unloads the original MCP add-on. Continue
# in a clean GUI using start_gui.py after this callback returns; do not hot-reload
# the add-on while Blender is still unwinding the render/package callback.
print('GKS_SOURCE_VERIFIED',json.dumps(report),flush=True)
if errors:raise RuntimeError(str(errors[:20]))
