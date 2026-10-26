# -*- coding: utf-8 -*-
import bpy,json,os,hashlib
from pathlib import Path
from mathutils import Matrix,Vector,Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v003/export/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_integration';report=json.loads((D/'export_manifest.json').read_text());data=json.loads((R/'godot/assets/models/facilities/solar_cabin/instances.json').read_text())
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;scene=bpy.context.scene;scene.name='太阳能木屋-导入比例与朝向核对';scene.unit_settings.system='METRIC'
with bpy.data.libraries.load(str(R/report['optimized_source']),link=True) as (a,b):b.collections=[e['collection'] for e in report['components']+report['legacy']]
cols={c.name:c for c in b.collections};bykey={e['key']:e for e in report['components']}
top=bpy.data.collections.new('太阳能木屋');scene.collection.children.link(top);surface=bpy.data.collections.new('太阳能木屋-海上区域');base=bpy.data.collections.new('太阳能木屋-海下基座');top.children.link(surface);top.children.link(base)
def add(col,name,collection,m):
 ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=collection;ob.matrix_world=m;return ob
for i,e in enumerate(data['instances']):
 g=Matrix(e['transform']+[[0,0,0,1]]);add(surface,e['component']+'_'+str(i),cols[bykey[e['component']]['collection']],C.inverted()@g@C)
for e in report['legacy']:
 col=base
 if e['key']=='salvage_station':col=bpy.data.collections.new('绞盘打捞台');scene.collection.children.link(col)
 pos=C.inverted()@Vector(e['origin_godot']);add(col,e['key'],cols[e['collection']],Matrix.Translation(pos))
scene['uniform_source_scale']=1.15;scene['front_godot']='+Z';scene['yaw_degrees']=0;scene['deck_height_godot']=2.15
for screen in bpy.data.screens:
 for ar in screen.areas:
  if ar.type=='VIEW_3D':ar.spaces.active.region_3d.view_location=Vector((1,-3,-4));ar.spaces.active.region_3d.view_distance=40;ar.spaces.active.shading.type='MATERIAL'
placement=D/'placement/solar_cabin/solar_cabin_v1.0.blend';placement.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(placement),compress=True)
# Geometry-fidelity comparisons use identical cameras and display settings.
source=R/report['source'];original_instances=json.loads((source.parent/'component_instances.json').read_text())['instances'];source_catalog=json.loads((source.parent/'catalog.json').read_text())['components'];source_names={e['asset_id']:e['collection'] for e in source_catalog};optimized_names={e['asset_id']:e['collection'] for e in report['components']}
for optimized in [False,True]:
 bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene;names=optimized_names if optimized else source_names;path=R/report['optimized_source'] if optimized else source
 with bpy.data.libraries.load(str(path),link=True) as (a,b):b.collections=list(names.values())
 loaded={c.name:c for c in b.collections}
 for i,e in enumerate(original_instances):
  m=Matrix.Translation(Vector(e['position']))@Euler(e['rotation_euler_xyz'],'XYZ').to_matrix().to_4x4()@Matrix.Diagonal(Vector(e['scale']+[1]));add(sc.collection,str(i),loaded[names[e['asset_id']]],m)
 sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='SINGLE';sc.display.shading.single_color=(.7,.7,.7);sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True
 sc.world=bpy.data.worlds.new('ProofWorld');sc.world.color=(.1,.12,.15);sc.display.shading.background_type='WORLD'
 cam=bpy.data.objects.new('ProofCamera',bpy.data.cameras.new('ProofCamera'));sc.collection.objects.link(cam);cam.data.type='ORTHO';cam.data.ortho_scale=17;cam.data.clip_end=500;sc.camera=cam;sc.render.resolution_x=700;sc.render.resolution_y=700;sc.render.resolution_percentage=100
 for name,offset in [('front',(12,-17,12)),('back',(-12,17,10)),('side',(-18,-1,8)),('top',(0,-.01,30))]:
  center=Vector((0,-2.7,2.7));cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(W/'optimization_compare'/(("optimized_" if optimized else "source_")+name+'.png'));bpy.ops.render.render(write_still=True)
manifest=dict(placement_source=str(placement.relative_to(R)),placement_sha256=hashlib.sha256(placement.read_bytes()).hexdigest(),optimized_source=report['optimized_source'],optimized_sha256=report['optimized_sha256'],source_sha256=report['source_sha256'],proof_views=['front','back','side','top'])
(D/'placement_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print('PLACEMENT_AND_PROOFS_COMPLETE',flush=True)
