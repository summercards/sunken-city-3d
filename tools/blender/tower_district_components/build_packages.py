import bpy,json,os,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path('/Users/summercards/WorkBuddy/sea');LIB=ROOT/'art_source/environments/tower_zones/tower_district/source/common_components/v008';BASE=ROOT/'outputs/tower_district/component_migration_v008'
catalog=json.loads((LIB/'component_catalog.json').read_text())['components'];library=str(LIB/'tower_district_components_v008.blend')
for i,meta in enumerate(catalog):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(library,link=False) as (src,dst):dst.collections=[meta['collection']]
 co=dst.collections[0];s=bpy.context.scene;s.name='Component_'+meta['slug'];s.collection.children.link(co)
 s.render.engine='BLENDER_EEVEE';s.render.resolution_x=768;s.render.resolution_y=512;s.render.resolution_percentage=100;s.render.fps=24;s.frame_start=1;s.frame_end=240;s.eevee.taa_render_samples=16
 dims=Vector(meta['bounds_size_m']);span=max(dims);target=Vector((0,0,dims.z*.45))
 preview=bpy.data.collections.new('90_预览灯光相机');s.collection.children.link(preview)
 camd=bpy.data.cameras.new('PreviewCamera');cam=bpy.data.objects.new('PreviewCamera',camd);preview.objects.link(cam);cam.location=target+Vector((span*.72+1,-span*1.1-1,span*.65+1));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camd.lens=42;camd.clip_end=1000;s.camera=cam
 for label,vec,power in [('key',(-.5,-.6,1),1000),('fill',(.7,-.1,.6),500)]:
  ld=bpy.data.lights.new('Preview_'+label,'AREA');ld.energy=power*max(1,span/3)**2;ld.shape='RECTANGLE';ld.size=max(1,span*.7);ld.size_y=max(1,span*.7)
  ob=bpy.data.objects.new(ld.name,ld);preview.objects.link(ob);ob.location=target+Vector(vec)*max(3,span);ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
 s['component_id']=meta['component_id'];s['component_source']=meta['source_room_type_blend'];s['scope']='independent_component_master'
 for a in bpy.context.screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL'
 bpy.ops.wm.save_as_mainfile(filepath=meta['component_blend'])
 print('PACKAGE_SAVED '+json.dumps({'done':i+1,'total':len(catalog),'slug':meta['slug']}),flush=True)
print('ALL_COMPONENT_PACKAGES_SAVED',flush=True)
