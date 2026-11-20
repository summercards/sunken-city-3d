# Passed to Blender alongside the modeling or animation-revision entry point.
from mathutils import Euler, Vector

AIRDROP_MODE = 'spring_drop_v4'
AIRDROP_END = 222
CUE_SCALE = .78


def bounce_profile(key, phase):
    # Measured from the original support plane; heavy structures use a low hop.
    if key in ('float_base', 'deck_surface', 'shop_shell', 'brick_mortar', 'loft_deck', 'loft_shell', 'loft_roof', 'utility_pole'):
        return .062, 7, 3
    if key.startswith('brick_') or key == 'quoin':
        return .081, 6, 3
    if phase in (2,5) and key not in ('access_ladder','awning'):
        return .148, 9, 4
    return .103, 7, 3

def assembly_schedule(key, phase, position, index):
    x, y, z = position
    if key in ('brick_a', 'brick_b', 'brick_c'):
        row = round((z - 2.270) / .117)
        along = x if abs(y) > 1.05 else y
        sweep = max(0, min(4, round((along + 1.38) * 1.48)))
        return 84 + row * 4 + sweep, 8, .23
    if key == 'quoin':
        row = round((z - 2.27) / .187)
        return 86 + round(row * 6.3) + int(x > 0) * 2, 9, .24
    fixed = {
        'float_base': (5, 15, .48), 'deck_surface': (20, 12, .30),
        'mooring': (30 + (index % 2) * 3, 9, .19),
        'shop_shell': (32, 14, .36), 'storefront': (40, 12, .30),
        'shop_door': (52, 10, .28), 'brick_mortar': (75, 10, .29),
        'sash': (125, 10, .26), 'exterior_signs': (130, 10, .27),
        'loft_deck': (135, 13, .44), 'loft_shell': (149, 14, .33),
        'loft_front': (158, 13, .30), 'exterior_stair': (145, 13, .34),
        'access_ladder': (65, 11, .32), 'awning': (70, 11, .29),
        'loft_roof': (199, 14, .40), 'utility_pole': (188, 15, .41),
        'drainage': (215, 13, .32), 'service_hardware': (220, 12, .26),
    }
    if key in fixed:
        return fixed[key]
    if phase <= 2:
        return 53 + (index % 5) * 3, 10, .23
    if phase == 4:
        return 144 + (index % 3) * 3, 10, .23
    if phase == 5:
        return 164 + (index % 5) * 4, 11, .25
    return 187 + (index % 3) * 4, 11, .24


def assembly_keyframes(scene, obj, position, rotation, scale, phase, index):
    cue, _, _ = assembly_schedule(obj['asset_key'], phase, position, index)
    start = round(cue * CUE_SCALE)
    cam = scene.camera
    inverse = cam.rotation_euler.to_matrix().transposed()
    edge_y = max(v.y for v in cam.data.view_frame(scene=scene))
    vertical_y = (inverse @ Vector((0, 0, 1))).y
    assert cam.data.type == 'ORTHO' and vertical_y > .7, f'{cam.name}: camera vertical projection {vertical_y:.4f}'
    orient = Euler(rotation, 'XYZ').to_matrix()
    floor_y = min((inverse @ (position - cam.location + orient @ Vector((p.x*scale[0], p.y*scale[1], p.z*scale[2])))).y
                  for mesh in obj.instance_collection.all_objects if mesh.type == 'MESH'
                  for corner in mesh.bound_box for p in (mesh.matrix_basis @ Vector(corner),))
    # Park the entire component above the top of the camera, with overscan for AA.
    height = max(.40, (edge_y + .16 - floor_y) / vertical_y)
    duration = max(13, min(28, round(11 + 5.5 * height**.5)))
    impact = start + duration
    lift, hop, tail = bounce_profile(obj['asset_key'], phase)
    touch_again = impact + hop
    land = touch_again + tail
    assert land < AIRDROP_END
    obj.animation_data_clear()
    obj.rotation_mode = 'XYZ'
    obj.rotation_euler = rotation
    obj.scale = scale
    obj.hide_render = obj.hide_viewport = False
    # Curve legs have constant acceleration, a sharp contact, and two diminishing hops.
    apex = impact + hop * .5
    soft_apex = touch_again + tail * .5
    keys = [(start, height), (impact, 0), (apex, lift), (touch_again, 0), (soft_apex, lift*.19), (land, 0)]
    obj.location = position
    for frame, offset in keys:
        obj.location.z = position.z + offset
        obj.keyframe_insert('location', index=2, frame=frame, group='Gravity and rebound | Z only')
    ad = obj.animation_data
    ad.action.name = 'Spring drop | '+obj.name
    for layer in ad.action.layers:
        for strip in layer.strips:
            bag = strip.channelbag(ad.action_slot)
            for curve in bag.fcurves:
                curve.extrapolation = 'CONSTANT'
                for i in range(len(keys)-1):
                    t0,h0 = keys[i]
                    t1,h1 = keys[i+1]
                    a,b = curve.keyframe_points[i],curve.keyframe_points[i+1]
                    d = (t1-t0)/3
                    h = h1-h0
                    a.interpolation = 'BEZIER'
                    a.handle_right_type = b.handle_left_type = 'FREE'
                    a.handle_right = (t0+d, position.z+h0+(2*h/3 if h>0 else 0))
                    b.handle_left = (t1-d, position.z+h1-(2*h/3 if h<0 else 0))
                curve.update()
    obj['assembly_enter'] = start
    obj['assembly_impact'] = impact
    obj['assembly_bounce_apex'] = apex
    obj['assembly_second_impact'] = touch_again
    obj['assembly_second_apex'] = soft_apex
    obj['assembly_bounce_m'] = lift
    obj['assembly_landed'] = land
    obj['assembly_drop_m'] = height


def assembly_markers(scene):
    scene.timeline_markers.clear()
    for frame, title in [(5,'01 Float'),(32,'02 Shop shell'),(53,'03 Furniture'),(84,'04 Brick courses'),(135,'05 Loft deck'),(149,'06 Loft and bedroom'),(199,'07 Roof'),(215,'08 Pipes and finish')]:
        scene.timeline_markers.new(title, frame=round(frame*CUE_SCALE))
    scene.frame_end = AIRDROP_END
    scene.timeline_markers.new('Complete', frame=AIRDROP_END)
    scene['assembly_motion'] = AIRDROP_MODE
