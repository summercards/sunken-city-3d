"""Inspect saved assembly geometry for the feedback-specific regressions."""
import bpy,hashlib,json,math,os
from pathlib import Path
from mathutils.bvhtree import BVHTree

root=Path(__file__).resolve().parents[3]
source=root/'art_source/scenes/neon_garden_quarter/v002'
work=Path(os.environ.get('SEA_WORK_ROOT',root.parent/'sea-work'))/'neon_garden_quarter/v002'
blend=source/'neon_garden_quarter.blend'
bpy.ops.wm.open_mainfile(filepath=str(blend))
scene=bpy.data.scenes['霓虹花园街区_完整装配']
bpy.context.window.scene=scene
bpy.context.view_layer.update()
rows=json.loads((source/'component_instances.json').read_text(encoding='utf8'))['instances']
mounts=json.loads((source/'mounting_manifest.json').read_text(encoding='utf8'))['signs']
checks={}

def mesh_data(row,select=lambda obj:True):
    instance=scene.objects[row['name']]
    vertices,faces=[],[]
    for obj in instance.instance_collection.objects:
        if not select(obj):continue
        offset=len(vertices)
        vertices.extend(instance.matrix_world@vertex.co for vertex in obj.data.vertices)
        faces.extend([offset+i for i in face.vertices] for face in obj.data.polygons)
    return vertices,faces

def bvh(rows):
    vertices,faces=[],[]
    for row in rows:
        coords,polys=mesh_data(row)
        faces.extend([len(vertices)+i for i in face] for face in polys)
        vertices.extend(coords)
    return BVHTree.FromPolygons(vertices,faces)

bridge=next(row for row in rows if row['key']=='garden_bridge')
verts,_=mesh_data(bridge)
checks['bridge_bears_into_both_buildings']=min(v.x for v in verts)<-4.6 and max(v.x for v in verts)>4.6
slab,_=mesh_data(bridge,lambda o:o.name.startswith('菜园承重板'))
checks['bridge_slab_0.2m']=abs(max(v.z for v in slab)-min(v.z for v in slab)-.2)<.001
checks['beam_above_open_street']=min(v.z for v in verts)>24 and sum(row['key']=='garden_bridge' for row in rows)==1
bridge_wings=[row for row in rows if row['key'] in ['left_damaged','round_ruin']]
walls=bvh(bridge_wings)
checks['bridge_doorway_left_open']=walls.ray_cast((-3,2.5,27.5),(-1,0,0),2)[0] is None
checks['bridge_doorway_right_open']=walls.ray_cast((3,2.5,27.5),(1,0,0),2)[0] is None
checks['bridge_walkway_clear']=all(abs(row['location'][1]-2.5)>.6 for row in rows if row['key'] in ['trellis','tomato','crop_bed'])
checks['garden_on_bridge']=sum(row['key']=='crop_bed' and abs(row['location'][1])<2 and 25<row['location'][2]<27 for row in rows)==3
round_levels=[row for row in rows if row['key'] in ['round_storey','round_damaged','round_ruin','round_roof']]
checks['eight_shell_levels']=len(round_levels)==8
for row in round_levels:
    coords,_=mesh_data(row,lambda o:o.name.startswith(('同一弧形轮廓','与七层完全同形')))
    r=[math.hypot(v.x-7.5,v.y+4) for v in coords if v.x<7.45 and v.y< -4.05]
    checks[row['name']+'_full_arc_slab']=len(r)>18 and max(r)<4.01 and sum(abs(value-4)<.09 for value in r)>18
checks['no_applique_curved_bays']=not any(row['key'] in ['round_balcony','arc_window','wall_scar'] for row in rows)
checks['structural_damage_actual_wall_openings']=sum(row['key'] in ['round_damaged','round_ruin','left_damaged'] for row in rows)>=4
checks['signs_have_real_support_objects']=all(scene.objects.get(row['sign']) and len(row['brackets'])>=2 and all(scene.objects.get(name) for name in row['brackets']) for row in mounts)
checks['signs_retain_3d_tilt']=all(abs(row['tilt_euler'][1])>.01 for row in mounts)
terrain=bvh([row for row in rows if row['key']=='fractured_ground'])
checks['street_crack_has_substrate']=terrain.ray_cast((0,-5,2),(0,0,-1))[0] is not None
lanterns=[row for row in rows if row['key']=='lantern']
checks['five_lanterns_fallen']=len(lanterns)==5
for row in lanterns:
    vertices,_=mesh_data(row)
    clearance=[]
    for point in vertices:
        hit=terrain.ray_cast((point.x,point.y,2),(0,0,-1))[0]
        if hit is not None:clearance.append(point.z-hit.z)
    checks[row['name']+'_rests_on_ground']=bool(clearance) and 0<=min(clearance)<.006 and row['euler_xyz'][0]>1.5
    checks[row['name']+'_extinguished']=all(m.name!='SEA_Emission' for o in scene.objects[row['name']].instance_collection.objects for m in o.data.materials)
baseline=json.loads((work/'v001_protection.json').read_text(encoding='utf8'))['files']
checks['v001_disk_files_preserved']=all(hashlib.sha256((root/name).read_bytes()).hexdigest()==digest for name,digest in baseline.items())
report={'passed':all(checks.values()),'source_sha256':hashlib.sha256(blend.read_bytes()).hexdigest(),'checks':checks,'bridge_span_m':round(max(v.x for v in verts)-min(v.x for v in verts),3),'mounted_signs':len(mounts),'fallen_lanterns':len(lanterns)}
(work/'structure_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('NGQ_STRUCTURE',len(checks),'checks',[k for k,v in checks.items() if not v],flush=True)
if not report['passed']:raise RuntimeError('Structural checks failed')
