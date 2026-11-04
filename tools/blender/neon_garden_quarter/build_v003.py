"""Widen the saved v002 quarter and rebuild the garden around two solid roof slopes."""
import ast,bmesh,bpy,hashlib,json,math,os,random
from pathlib import Path
from mathutils import Euler,Vector

R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/neon_garden_quarter/v003';OLD=D.parent/'v002'
P=json.loads((D/'component_plan.json').read_text(encoding='utf8'))
assert hashlib.sha256((R/P['parent_source']).read_bytes()).hexdigest()==P['parent_sha256']
bpy.ops.wm.open_mainfile(filepath=str(R/P['parent_source']));bpy.context.preferences.filepaths.save_version=0
S=bpy.data.scenes['霓虹花园街区_完整装配'];M=bpy.data.scenes['组件母版_独立编辑'];bpy.context.window.scene=M
LAY={k:bpy.data.collections[n] for k,n in [('architecture','01_建筑结构'),('fixtures','02_固定设施'),('signage','03_招牌与广告画'),('plants','04_独立植物'),('support','90_展示支持_不导出')]}
ROOTS={k:bpy.data.collections['母版_'+k] for k in ['architecture','fixtures','signage','plants']}
oldcat=json.loads((OLD/'component_catalog.json').read_text(encoding='utf8'))['components']
oldinst=json.loads((OLD/'component_instances.json').read_text(encoding='utf8'))['instances']
COLS={c['key']:bpy.data.collections[c['collection']] for c in oldcat};CAT=[];INST=[];CUR=None
MATS={x:bpy.data.materials['SEA_'+x] for x in ['Matte','Metal','Gloss','Emission']}
CELL={c['name']:((c['column']+.5)/8,1-(c['row']+.5)/8) for c in json.loads((R/P['palette']).with_suffix('.json').read_text())['cells']}
for name,functions in [('build.py',{'dump','shade','mesh','box','tube','make','finish'}),('build_v002.py',{'place'})]:
    tree=ast.parse((Path(__file__).parent/name).read_text(encoding='utf8'))
    exec(compile(ast.Module(body=[node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name in functions],type_ignores=[]),name,'exec'))
for key,col in LAY.items():
    if key!='support':
        for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)

def replace_component(key):
    col=COLS.pop(key)
    for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(col)
    make(key)

def widen(x):return x+12*min(1,max(0,(x+3.5)/7))

replace_component('garden_bridge')
box('双坡菜园桥_0.2米承重板',(0,0,1.10),(21.6,8.4,.2),'cream',.044)
for y in [-4,4]:
    box('横跨街巷的边梁',(0,y,.55),(21.6,.65,1.1),'cream',.10)
    box('边梁青色翼缘',(0,y,.25),(21.55,.74,.17),'sage_gray',.05)
for x in [-10.4,10.4]:box('伸入楼体的承台',(x,0,.6),(.8,8.4,1.2),'plaster',.10)
for y in [-2,0,2]:box('桥下次梁',(0,y,.77),(21.25,.32,.42),'teal',.07)
finish('garden_bridge')

# The ridge runs between the buildings. The front slope is the large planted face.
replace_component('roof_soil')
ridge=-.3;ridge_height=2.45;eave_z=26.;front=-4.2;rear=1.8
def pitch(y):return ridge_height/(ridge-front) if y<ridge else -ridge_height/(rear-ridge)
def height(y):return eave_z+ridge_height+(y-ridge)*pitch(y)
def roof_section(name,section,color,bevel):
    count=len(section)
    coords=[(x,y,z) for x in [-10.55,10.55] for y,z in section]
    faces=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    return mesh(name,coords,faces,color,bevel=bevel)

for low,high in [(front,ridge),(ridge,rear)]:
    z1,z2=height(low)-eave_z,height(high)-eave_z
    roof_section('有厚度的双坡板',[(low,z1-.2),(high,z2-.2),(high,z2),(low,z1)],'stone',.042)
    roof_section('顺坡土层',[(low+.13,height(low+.13)-eave_z-.01),(high-.065,height(high-.065)-eave_z-.01),(high-.065,height(high-.065)-eave_z+.18),(low+.13,height(low+.13)-eave_z+.18)],'wood_dark',.028)
for y in [front,rear]:box('低檐挡土木',(0,y,.03),(21.2,.18,.23),'wood_mid',.045)
box('横跨两楼的圆角屋脊',(0,ridge,ridge_height+.04),(21.2,.25,.22),'wood_mid',.05)
for x in [-10.35,-5.25,0,5.25,10.35]:
    tube('三角形屋架斜梁',[(x,front,-.14),(x,ridge,ridge_height-.18),(x,rear,-.14)],.12,'wood_mid')
    tube('三角屋架拉梁',[(x,front,-.14),(x,rear,-.14)],.095,'wood_dark')
finish('roof_soil')

# Stretch only the fractured street between the wings. The right foundation stays curved.
ground=COLS['fractured_ground'];shift=Vector(ground['author_origin_shift'])
for obj in ground.objects:
    for vertex in obj.data.vertices:
        world=vertex.co+shift
        if obj.name.startswith('后楼底坪'):world.x+=6
        else:world.x=widen(world.x)
        vertex.co=world
finish('fractured_ground')

# The old inner-wall pier overlapped one side of the doorway. The existing
# bridge-door jamb and header remain the visible support around that opening.
ruin=COLS['round_ruin'];ruin_shift=Vector(ruin['author_origin_shift'])
door_piers=[]
for obj in ruin.objects:
    if not obj.name.startswith('侧面主柱'):continue
    center=sum((v.co for v in obj.data.vertices),Vector())/len(obj.data.vertices)+ruin_shift
    if abs(center.x+4.25)<.1 and abs(center.y-1)<.1:door_piers.append(obj)
assert len(door_piers)==1
bpy.data.objects.remove(door_piers[0],do_unlink=True)
finish('round_ruin')

for row in oldinst:
    key=row['key'];x,y,z=row['location'];name=row['name'];host=row.get('host') or ''
    if key in ['garden_bridge','roof_soil','fractured_ground','crop_bed','cabbage','herb','tomato','trellis']:continue
    scale=list(row['scale'])
    if key=='utility_cable':x+=6;scale[0]*=19/7
    elif host.startswith('back') or (y>=9.05 and abs(x)<3.2) or (y>10.35 and abs(x)<5):x+=6
    elif host.startswith(('right','garden_bridge_right')) or x>=3.15:x+=12
    elif key=='street_lamp' and x>0:x+=12
    else:x=widen(x)
    obj=place(key,(x,y,z),row['euler_xyz'],scale,host=host or None)
    obj.name=name;INST[-1]['name']=obj.name
place('garden_bridge',(6,0,24.6),author=True,tag='加宽_实体菜园桥')
place('roof_soil',(6,0,eave_z),author=True,tag='双坡屋脊菜园')
place('fractured_ground',(0,0,.1),author=True)

# Keep crops and beds as independent instances. Beds follow slope and crops grow upright.
random.seed(364)
for column in range(7):
    x=-2.85+2.95*column
    y=-2.25;tilt=math.atan(pitch(y))
    place('crop_bed',(x,y,height(y)+.13),rot=(tilt,0,0),scale=(.94,.72,1))
    for j in range(5):
        yy=-3.65+j*.70
        for dx in [-.52,.52]:
            key='cabbage' if column in [0,1,4] else 'herb'
            place(key,(x+dx,yy,height(yy)+.43),rot=(0,0,random.random()*math.tau))
    if column in [0,1,3,5,6]:
        y=.25
        place('trellis',(x,y,height(y)+.16),scale=(.90,.9,.90))
        for dx in [-.72,.06,.77]:place('tomato',(x+dx,y-.18,height(y-.18)+.15),rot=(0,0,random.random()),scale=(.9,.9,.94))
    else:
        for yy in [.4,1.15]:
            for dx in [-.65,.1,.7]:place('herb',(x+dx,yy,height(yy)+.15),rot=(0,0,random.random()*math.tau))

done={item['key'] for item in CAT}
for item in oldcat:
    if item['key'] not in done:CAT.append(dict(item))
for item in CAT:
    for field in ['source_sha256','verification','geometry_fingerprint']:item.pop(field,None)
    for field in ['source','manifest']:item[field]=item[field].replace('/v002/','/v003/').replace('/v001/','/v003/')
CAT.sort(key=lambda item:item['asset_id'])
for obj in LAY['support'].objects:
    if obj.type=='CAMERA':
        obj.location.x+=6
        if obj.data.type=='ORTHO':obj.data.ortho_scale+=7
garden=bpy.data.objects['近景_屋顶菜园'];garden.location=(3,-38,39)
garden.rotation_euler=(Vector((6,-.3,27))-garden.location).to_track_quat('-Z','Y').to_euler();garden.data.ortho_scale=30
top=bpy.data.objects['俯视_空间布局'];top.location.x=6;top.data.ortho_scale=47
S['revision']='v003_wide_gabled_garden_bridge';bpy.context.window.scene=S
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.region_3d.view_location=(6,2,18);area.spaces.active.region_3d.view_distance=68
for img in bpy.data.images:
    if img.source=='FILE':img.filepath=bpy.path.relpath(str(R/(P['palette'] if img.name.startswith('SEA_') else P['poster_source'])),start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D/'neon_garden_quarter.blend'),compress=True)
dump(D/'component_catalog.json',dict(schema='sea.component_catalog',version='v003',components=CAT))
dump(D/'component_instances.json',dict(schema='sea.component_instances',coordinate_system='Blender XY ground +Z up; full Euler XYZ; Godot(x,z,-y)',instances=INST))
dump(D/'mounting_manifest.json',json.loads((OLD/'mounting_manifest.json').read_text(encoding='utf8')))
print('V003_BUILD_COMPLETE',len(CAT),len(INST),flush=True)
