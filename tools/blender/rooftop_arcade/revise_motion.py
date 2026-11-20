# Run inside the already-open Rooftop Arcade project (with motion.py prepended).
import bpy


def revise_motion():
    assert bpy.data.filepath == DEST, 'Open the Rooftop Arcade source before revising it.'
    static = bpy.data.scenes['街机屋_参考装配']
    anim = bpy.data.scenes['街机屋_组装动画']
    targets = {o['instance_index']: o for o in static.objects if o.instance_type == 'COLLECTION'}
    movers = {o['instance_index']: o for o in anim.objects if o.instance_type == 'COLLECTION'}
    assert len(targets) == 355 and targets.keys() == movers.keys()
    eye = anim.camera
    eye.animation_data_clear()
    eye.data.animation_data_clear()
    eye.rotation_mode = static.camera.rotation_mode
    eye.location = static.camera.location.copy()
    eye.rotation_euler = static.camera.rotation_euler.copy()
    eye.data.ortho_scale = static.camera.data.ortho_scale
    anim.frame_set(anim.frame_end)
    for index, obj in movers.items():
        target = targets[index]
        assert obj.instance_collection == target.instance_collection and obj.parent is None
        assembly_keyframes(anim, obj, target.location.copy(), target.rotation_euler.copy(), target.scale.copy(), target['phase'], index)
    assembly_markers(anim)
    anim.frame_set(AIRDROP_END)
    bpy.context.window.scene = anim
    bpy.ops.wm.save_as_mainfile(filepath=DEST, relative_remap=False)
    print('REVISED ASSEMBLY', len(movers), DEST)


revise_motion()
