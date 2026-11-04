"""Check the new roof profile and assembly against both the plan and saved v002."""
import bpy,hashlib,json,math,os
from pathlib import Path
from mathutils.bvhtree import BVHTree

root=Path(__file__).resolve().parents[3]
source=root/'art_source/scenes/neon_garden_quarter/v003'
work=Path(os.environ.get('SEA_WORK_ROOT',root.parent/'sea-work'))/'neon_garden_quarter/v003'
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
blend=source/'neon_garden_quarter.blend'
bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.data.scenes['霓虹花园街区_完整装配'];bpy.context.window.scene=scene
bpy.context.view_layer.update()
rows=read(source/'component_instances.json')['instances'];old=read(source.parent/'v002/component_instances.json')['instances'];old_by_name={row['name']:row for row in old}
checks={}
def mesh_data(key,filter_objects=lambda obj:True):
    verts,faces=[],[]
    for row in rows:
        if row['key']!=key:continue
        instance=scene.objects[row['name']]
        for obj in instance.instance_collection.objects:
            if not filter_objects(obj):continue
            start=len(verts);verts.extend(instance.matrix_world@vertex.co for vertex in obj.data.vertices)
            faces.extend([start+i for i in face.vertices] for face in obj.data.polygons)
    return verts,faces

for row in rows:
    key=row['key']
    if key in ['round_storey','round_damaged','round_ruin','round_roof','left_storey','left_damaged']:
        previous=old_by_name[row['name']]
        expected=12 if key.startswith('round') else 0
        checks[row['name']+' horizontal shift']=abs(row['location'][0]-previous['location'][0]-expected)<.001 and row['location'][1:]==previous['location'][1:]
bridge,_=mesh_data('garden_bridge');bridge_min,bridge_max=min(v.x for v in bridge),max(v.x for v in bridge)
checks['bridge reaches both support walls']=bridge_min<-4.6 and bridge_max>16.6
slopes,faces=mesh_data('roof_soil',lambda obj:obj.name.startswith('有厚度的双坡板'))
surface=BVHTree.FromPolygons(slopes,faces)
def roof_z(y):return surface.ray_cast((6,y,32),(0,0,-1))[0].z
front,crest,back=[roof_z(y) for y in [-4.1,-.32,1.7]]
checks['both slopes meet at a raised ridge']=crest>max(front,back)+2.2 and abs(front-back)<.14
checks['roof slopes use real thickness']=all(len(face)>=3 for face in faces) and len(slopes)>16
checks['rear passage stays outside planted roof']=surface.ray_cast((6,2.6,32),(0,0,-1))[0] is None
wall_coords,wall_faces=mesh_data('left_damaged');other,of=mesh_data('round_ruin')
wall_faces.extend([len(wall_coords)+i for i in f] for f in of);wall_coords.extend(other)
wall=BVHTree.FromPolygons(wall_coords,wall_faces)
for y in [2.1,2.5,2.9]:
    checks[f'left door clear at {y}']=wall.ray_cast((-3,y,27.5),(-1,0,0),2)[0] is None
    checks[f'right door clear at {y}']=wall.ray_cast((15,y,27.5),(1,0,0),2)[0] is None
beds=[row for row in rows if row['key']=='crop_bed']
checks['all seven beds follow the front slope']=len(beds)==7 and all(abs(row['euler_xyz'][0]-math.atan(2.45/3.9))<.001 for row in beds)
checks['v002 source and packages preserved']=all(sha(root/path)==digest for path,digest in read(work/'v002_protection.json').items())
record={'passed':all(checks.values()),'checks':checks,'source_sha256':sha(blend),'bridge_span_m':bridge_max-bridge_min,'sampled_roof_yz':[[-4.1,front],[-.32,crest],[1.7,back]],'roof_rise_m':2.45,'right_shift_m':12}
(work/'structure_verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('NGQ v003 structure:',len(checks),'checks,',len([v for v in checks.values() if not v]),'failures')
if not record['passed']:raise RuntimeError([key for key,value in checks.items() if not value])
