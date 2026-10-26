import bpy,json,hashlib,math,os,sys
from pathlib import Path
from mathutils import Vector,Matrix,Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/bloom_lower_building/v001';W=R.parent/'sea-work/solar_cabin_revision_v006';pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';errors=[];uv_faces=0
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(flag,msg):
 if not flag:errors.append(msg)
s=(R/'tools/blender/bloom_lower_building/verify.py').read_text();exec(s[s.index('def identity('):s.index('bpy.ops.wm.open_mainfile(filepath=str(source))')])
cat=json.loads((D/'catalog.json').read_text())['components'];source=D/'bloom_lower_building.blend';bpy.ops.wm.open_mainfile(filepath=str(source))
for e in cat:inspect(e,True)
for e in cat:
 bpy.ops.wm.open_mainfile(filepath=str(R/e['component_source']));inspect(e)
report=dict(passed=not errors,errors=sorted(set(errors)),components=len(cat),uv_faces_checked=uv_faces,packages_reopened=len(cat),source_sha256=sha(source))
(W/'lower_source_verification.json').write_text(json.dumps(report,indent=2));assert not errors,errors
exp=json.loads((D/'export/v001/export_manifest.json').read_text());data=json.loads((R/'godot/assets/models/facilities/bloom_lower_building/instances.json').read_text());C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
for optimized in [False,True]:
 bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene
 names={e['key']:e['collection'] for e in exp['components'] if optimized} if optimized else {e['key']:e['collection'] for e in cat}
 with bpy.data.libraries.load(str(R/exp['optimized_source'] if optimized else source),link=True) as (a,b):b.collections=list(names.values())
 cols={c.name:c for c in b.collections}
 for i,e in enumerate(data['instances']):
  ob=bpy.data.objects.new(str(i),None);sc.collection.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=cols[names[e['component']]];ob.matrix_world=C.inverted()@Matrix(e['transform']+[[0,0,0,1]])@C
 sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='SINGLE';sc.display.shading.single_color=(.7,.7,.7);sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True;sc.world=bpy.data.worlds.new('World');sc.world.color=(.10,.12,.15);sc.display.shading.background_type='WORLD'
 cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));sc.collection.objects.link(cam);cam.data.type='ORTHO';cam.data.ortho_scale=28;sc.camera=cam;sc.render.resolution_x=650;sc.render.resolution_y=750;sc.render.resolution_percentage=100
 for name,offset in [('front',(-20,-25,13)),('back',(20,25,13)),('side',(-25,0,3)),('top',(0,-.01,35))]:
  center=Vector((5.533,-1.6,-7));cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(W/'lower_compare'/(("optimized_" if optimized else "source_")+name+'.png'));bpy.ops.render.render(write_still=True)
print('LOWER_SOURCE_VERIFIED',flush=True)
