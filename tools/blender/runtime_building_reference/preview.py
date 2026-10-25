import bpy,json,os
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.1'
for name,target,offset,scale,color in [
 ('background_building_library',(14,10,-5),(48,-62,48),78,'OBJECT'),
 ('playable_overview',(3,10,-6),(65,-85,80),125,'VERTEX')]:
    p=D/(name+'_v0.1.blend');bpy.ops.wm.open_mainfile(filepath=str(p))
    assert all(Path(bpy.path.abspath(lib.filepath)).is_file() for lib in bpy.data.libraries)
    if name=='background_building_library':
        instances=[o for o in bpy.context.scene.objects if o.instance_type=='COLLECTION']
        bpy.ops.object.select_all(action='DESELECT')
        for ob in instances:ob.select_set(True)
        bpy.context.view_layer.objects.active=instances[0]
        bpy.ops.object.duplicates_make_real(use_base_parent=True,use_hierarchy=True)
        for ob in instances:ob.instance_type='NONE'
    scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type=color;scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.background_type='WORLD'
    if scene.world is None:scene.world=bpy.data.worlds.new('PreviewWorld')
    scene.world.color=(.07,.09,.12)
    cam=bpy.data.objects.new('PreviewCamera',bpy.data.cameras.new('PreviewCamera'));scene.collection.objects.link(cam);center=Vector(target);cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=scale;cam.data.clip_end=3000;scene.camera=cam
    scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
    print('PREVIEW_VERIFIED',name,flush=True)
