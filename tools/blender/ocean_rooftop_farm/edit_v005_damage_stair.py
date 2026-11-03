import bpy, math, json, os
from mathutils import Vector

SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
OUT='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
# open v005 explicitly when running headless

# ---- materials / collections ----
def mat(name):
    m=bpy.data.materials.get(name)
    if m: return m
    m=bpy.data.materials.new(name); m.diffuse_color=(0.32,0.36,0.34,1); return m
m_conc=mat('ORF2_FINAL_SEA_Matte')
m_rust=mat('ORF2_FINAL_SEA_Metal')

def getcol(name):
    return bpy.data.collections.get(name)

def link_obj(o,c):
    if c and o.name not in c.objects: c.objects.link(o)

# ---- large structural voids on pier mesh ----
def add_chunk(name, loc, scale, rot=(0,0,0), material=None):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o=bpy.context.object; o.name=name; o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if material: o.data.materials.append(material)
    c=getcol('ORF3_组件_pier') or getcol('ORF2_组件_pier.001')
    link_obj(o,c)
    return o

# Make large visible concrete void/peel pieces as real geometry, offset slightly from the pier faces.
# They are not tiny decals: each is 0.65-1.25m wide and 1.1-2.8m tall.
col=getcol('ORF2_组件_pier.001') or getcol('ORF3_组件_pier')
# idempotent delete our prior blocks
for o in list(bpy.data.objects):
    if o.name.startswith('ORF5_柱体大块崩缺_'):
        bpy.data.objects.remove(o,do_unlink=True)

pier_specs=[
    ('p0',(-22.80,-15.02,14.1),(0.48,0.16,1.55),(0.0,0.0,0.12)),
    ('p1',(-7.60,-15.02,31.8),(0.72,0.16,1.10),(0.0,0.0,-0.18)),
    ('p2',(7.60,-15.02,47.2),(0.55,0.16,2.10),(0.0,0.0,0.24)),
    ('p3',(22.80,-15.02,23.5),(0.88,0.16,1.30),(0.0,0.0,-0.10)),
    ('p4',(-22.80,15.02,39.4),(0.62,0.16,1.75),(0.0,0.0,0.20)),
    ('p5',(22.80,15.02,9.8),(0.76,0.16,1.35),(0.0,0.0,-0.22)),
]
for key,loc,sc,rot in pier_specs:
    add_chunk('ORF5_柱体大块崩缺_'+key,loc,sc,rot,m_conc)
# Rust-dark exposed inner aggregate / shadow backing in each void, visibly large.
for i,(key,loc,sc,rot) in enumerate(pier_specs):
    x,y,z=loc
    add_chunk('ORF5_柱体崩口内里_'+key,(x,y-0.035,z),tuple(max(0.18,v*0.70) for v in sc),rot,m_rust)

# ---- keep only one fire-stair flight and one landing above water ----
# Preserve the lower landing at local z=44.8 and first flight to 47.3.
# Hide all other authored stair/landing instances by exact object name if linked empty.
keep_names={'ORF3_实例_stair_flight.018','ORF3_实例_stair_landing.019'}
# The lower visible platform is landing .019 at z=44.8; first flight .018 rises to 47.3.
for o in bpy.data.objects:
    if o.name.startswith('ORF3_实例_stair_flight.') or o.name.startswith('ORF3_实例_stair_landing.'):
        o.hide_render = o.name not in keep_names
        o.hide_viewport = o.name not in keep_names
# top open landing and roof entry are not part of the single exposed segment
for o in bpy.data.objects:
    if o.name.startswith('ORF3_实例_stair_landing.024') or o.name.startswith('ORF3_实例_roof_entry'):
        o.hide_render=True; o.hide_viewport=True
# Keep broken below-water fragment as a visual remnant, but it remains hidden from traversal.
for o in bpy.data.objects:
    if o.name.startswith('ORF3_下挂断裂消防梯'):
        o.hide_render=False; o.hide_viewport=False

# ---- add metadata ----
scene=bpy.context.scene
scene['ORF5_VERSION']='v005'
scene['ORF5_DAMAGE_MODE']='large_structural_pier_voids'
scene['ORF5_STAIR_MODE']='single_exposed_flight_above_water'
scene['ORF5_WATER_LOCAL_Z']=44.54
scene['ORF5_BOARD_DECK_LOCAL_Z']=44.80
scene['ORF5_EXPOSED_FLIGHT_LOW_Z']=44.97
scene['ORF5_EXPOSED_FLIGHT_HIGH_Z']=48.68
scene['ORF5_NOTES']='柱体大块几何缺损；水面以上只保留一段消防梯与下端平台；下沉/上岸定位由Godot包装拥有。'

# save
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print(json.dumps({'saved':OUT,'pier_damage_objects':len([o for o in bpy.data.objects if o.name.startswith('ORF5_柱体')]),'kept_stairs':sorted(keep_names),'scene_meta':{k:scene[k] for k in ['ORF5_VERSION','ORF5_STAIR_MODE','ORF5_WATER_LOCAL_Z','ORF5_BOARD_DECK_LOCAL_Z']}},ensure_ascii=False))
