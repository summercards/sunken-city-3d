"""Author source-only modular sunken city directly inside the active Blender MCP session.
No Godot files are read or written by this authoring step. Re-run only before final delivery.
"""
import bpy
import bmesh
import hashlib
import json
import math
import os
import random
from pathlib import Path
from mathutils import Euler, Matrix, Quaternion, Vector

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/sunken_city/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'sunken_city/v001'
P = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
assert P['status'] == 'frozen_before_geometry' and P['component_budget']['planned'] <= 50
assert (W/'pre_task_session.blend').exists(), 'Current session backup required'
assert not (D/'sunken_city_v001.blend').exists(), 'Never overwrite delivered source; create next version'
PAL = R / P['palette']
assert hashlib.sha256(PAL.read_bytes()).hexdigest() == P['palette_sha256']
CELLS = {c['name']: c for c in json.loads(PAL.with_suffix('.json').read_text(encoding='utf-8'))['cells']}

# The initial session was the untouched factory cube; a backup was saved first.
# Do not use read_factory_settings here: it also shuts down the active MCP service.
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
current=bpy.context.scene
for scene in list(bpy.data.scenes):
    if scene!=current:bpy.data.scenes.remove(scene)
for col in list(bpy.data.collections):bpy.data.collections.remove(col)
for mat in list(bpy.data.materials):bpy.data.materials.remove(mat)
for mesh in list(bpy.data.meshes):
    if mesh.users==0:bpy.data.meshes.remove(mesh)
bpy.context.preferences.filepaths.save_version = 0
S = bpy.context.scene
S.name = '沉没旧城_完整参考布局_v001'
S.unit_settings.system = 'METRIC'
MASTER = bpy.data.scenes.new('01_组件母版_独立编辑')
MASTER.unit_settings.system = 'METRIC'
MA = bpy.data.collections.new('01_制作组件_单栋与街段')
MASTER.collection.children.link(MA)
OUT = bpy.data.collections.new('02_游戏输出_组件实例布局')
S.collection.children.link(OUT)
STAGE = bpy.data.collections.new('90_展示与验收_不导出')
S.collection.children.link(STAGE)
ARCH = bpy.data.collections.new('建筑_独立实例')
GROUND = bpy.data.collections.new('街道_逐段拼接实例')
FAC = bpy.data.collections.new('设施车辆_独立实例')
VEG = bpy.data.collections.new('海藻青苔_独立可隐藏')
for col in (ARCH,GROUND,FAC,VEG): OUT.children.link(col)
IMG = bpy.data.images.load(str(PAL), check_existing=True)
IMG.name = 'SEA_公共暖木8x8色板_外链'
MATS = []
for name,metal,rough,coat in [('SEA_Matte',0,.78,0),('SEA_Metal',.15,.82,0),('SEA_Gloss',.08,.3,.3)]:
    m=bpy.data.materials.new(name);m.use_nodes=True
    ns=m.node_tree.nodes; ns.clear();links=m.node_tree.links
    bs=ns.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=metal
    bs.inputs['Roughness'].default_value=rough;bs.inputs['Coat Weight'].default_value=coat
    tex=ns.new('ShaderNodeTexImage');tex.image=IMG;tex.interpolation='Closest'
    uv=ns.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
    out=ns.new('ShaderNodeOutputMaterial')
    links.new(uv.outputs['UV'],tex.inputs['Vector']);links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    links.new(bs.outputs['BSDF'],out.inputs['Surface']);MATS.append(m)

CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
CACHE={}
def box_template(size, bevel):
    key=tuple(round(s,4) for s in size)+(round(bevel,4),)
    if key in CACHE:return CACHE[key]
    sx,sy,sz=(s/2 for s in size)
    vs=[(-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz),(-sx,-sy,sz),(sx,-sy,sz),(sx,sy,sz),(-sx,sy,sz)]
    if not bevel:return vs,CUBE_F,[False]*6
    bm=bmesh.new(); bv=[bm.verts.new(v) for v in vs]
    for f in CUBE_F:bm.faces.new([bv[i] for i in f])
    result=bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(size)*.44),segments=3,affect='EDGES',profile=.5,clamp_overlap=True)
    for f in result.get('faces',[]):f.smooth=True
    bm.verts.ensure_lookup_table();bm.verts.index_update()
    ans=([tuple(v.co) for v in bm.verts],[[v.index for v in f.verts] for f in bm.faces],[f.smooth for f in bm.faces])
    bm.free();CACHE[key]=ans;return ans

class Builder:
    def __init__(self):self.v=[];self.f=[];self.colors=[];self.roles=[];self.smooth=[]
    def geo(self,vs,fs,color='plaster',role=0,smooth=None):
        n=len(self.v);self.v.extend(tuple(v) for v in vs);self.f.extend(tuple(n+i for i in f) for f in fs)
        self.colors.extend([color]*len(fs));self.roles.extend([role]*len(fs));self.smooth.extend(smooth or [False]*len(fs))
    def box(self,c,size,color='plaster',bevel=0,role=0,rot=None):
        if min(size)<=1e-5:return
        vs,fs,sm=box_template(size,bevel)
        if rot:
            mat=Euler(rot,'XYZ').to_matrix();verts=[Vector(c)+mat@Vector(v) for v in vs]
        else:verts=[(v[0]+c[0],v[1]+c[1],v[2]+c[2]) for v in vs]
        self.geo(verts,fs,color,role,sm)
    def prism(self,poly,z,t,color='plaster',bevel=0,role=0):
        if len(poly)<3:return
        n=len(poly);vs=[(x,y,z) for x,y in poly]+[(x,y,z+t) for x,y in poly]
        fs=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        self.geo(vs,fs,color,role)
    def tube(self,pts,r,color='steel',role=1,sides=7):
        pts=[Vector(p) for p in pts];verts=[];faces=[]
        for i,p in enumerate(pts):
            tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
            up=Vector((0,0,1)) if abs(tangent.z)<.94 else Vector((0,1,0))
            u=tangent.cross(up).normalized();v=tangent.cross(u).normalized()
            verts.extend(p+r*(u*math.cos(math.tau*k/sides)+v*math.sin(math.tau*k/sides)) for k in range(sides))
            if i:
                b=i*sides
                faces.extend((b-sides+k,b-sides+(k+1)%sides,b+(k+1)%sides,b+k) for k in range(sides))
        faces.extend([tuple(range(sides-1,-1,-1)),tuple(range(len(verts)-sides,len(verts)))])
        self.geo(verts,faces,color,role,[True]*(len(faces)-2)+[False]*2)
    def cyl(self,c,r,h,color='silver',role=1,n=12,axis='Z'):
        v=Vector((0,0,h/2)) if axis=='Z' else Vector((0,h/2,0)) if axis=='Y' else Vector((h/2,0,0))
        self.tube([Vector(c)-v,Vector(c)+v],r,color,role,n)
    def finish(self,name,col):
        me=bpy.data.meshes.new(name+'_可编辑网格');me.from_pydata(self.v,[],self.f);me.update()
        for m in MATS:me.materials.append(m)
        uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;me.uv_layers.active_index=0
        for poly,color,role,smooth in zip(me.polygons,self.colors,self.roles,self.smooth):
            poly.material_index=role;poly.use_smooth=smooth
            cell=CELLS[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
            for j,li in enumerate(poly.loop_indices):
                a=math.tau*j/len(poly.loop_indices);uv.data[li].uv=(cx+.023*math.cos(a),cy+.023*math.sin(a))
        obj=bpy.data.objects.new(name+'_主体_金属哑光反光',me);col.objects.link(obj)
        return obj

B=None

def text_shape(txt,c,size,color='cream',rot=(math.pi/2,0,0)):
    curve=bpy.data.curves.new('临时文字','FONT');curve.body=txt;curve.size=size;curve.align_x='CENTER';curve.extrude=.035;curve.bevel_depth=.012;curve.bevel_resolution=1;curve.resolution_u=3
    o=bpy.data.objects.new('临时文字',curve);S.collection.objects.link(o);o.location=c;o.rotation_euler=rot
    bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();me=bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    B.geo([o.matrix_world@v.co for v in me.vertices],[list(f.vertices) for f in me.polygons],color)
    bpy.data.objects.remove(o,do_unlink=True);bpy.data.meshes.remove(me);bpy.data.curves.remove(curve)

def clip(poly,a,b,limit):
    result=[]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        fp=a*p[0]+b*p[1]-limit;fq=a*q[0]+b*q[1]-limit
        if fp<=0:result.append(p)
        if (fp<=0)!=(fq<=0):
            t=fp/(fp-fq);result.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
    return result

def tank(x,y,z):
    for dx in (-.65,.65):
        for dy in (-.65,.65):B.box((x+dx,y+dy,z+.5),(.12,.12,1),'steel',.025,1)
    B.cyl((x,y,z+1.8),1.0,1.8,'silver',1)
    B.cyl((x,y,z+2.75),1.08,.15,'lightgray',1)
    for zz in (z+1.0,z+2.5):B.cyl((x,y,zz),1.025,.1,'steel',1)
    B.tube([(x+1,y,z+.2),(x+1,y,z+2.3),(x+.7,y,z+2.4)],.09,'gray')

def aircon(x,y,z,side=False):
    B.box((x,y,z), (1.4,.8,1.0),'cloud',.06)
    B.cyl((x,y-.43,z),.34,.08,'steel',1,12,'Y')
    for ang in range(0,360,45):
        a=math.radians(ang);B.tube([(x-.31*math.cos(a),y-.49,z-.31*math.sin(a)),(x+.31*math.cos(a),y-.49,z+.31*math.sin(a))],.018,'silver',1,4)
    B.box((x,y,z-.55),(1.65,1,.1),'steel',.02,1)

def rail(a,b,z):
    a=Vector((a[0],a[1],z));b=Vector((b[0],b[1],z));length=(b-a).length
    B.tube([a+Vector((0,0,1.05)),b+Vector((0,0,1.05))],.07,'steel')
    for j in range(int(length/.65)+1):
        p=a.lerp(b,j/max(1,int(length/.65)));B.tube([p,p+Vector((0,0,1.05))],.045,'steel',1,5)

def building(c):
    global B
    w,d,_=c['size_design_m'];w-=1.5;d-=1.3
    floors=c['floors'];damage=c['damage'];style=c['style'];color=c['color']
    rng=random.Random(c['key']);h=5.1
    ishalf=style in ('cutaway','half_tower','canal_shell','frame','foundation')
    nbay=max(3,round(w/3.6));nbay_y=max(3,round(d/3.7))
    plane_a=1;plane_b=.5 if style not in ('canal_shell','half_tower') else -.55
    limits=[]
    for f in range(floors+1):
        frac=f/max(1,floors)
        start=.12 if ishalf else .52
        erosion=max(0,(frac-start)/(1-start))
        limit=w*.58+d*.3 - erosion*(w*(.35+damage*.7))
        if ishalf:limit-=w*.34
        limits.append(limit)
    def survive(x,y,f):return x+plane_b*y<limits[min(f,floors)]-.1
    rect=[(-w/2,-d/2),(w/2,-d/2),(w/2,d/2),(-w/2,d/2)]
    for f in range(floors+1):
        top=f*h+.3
        footprint=clip(rect,plane_a,plane_b,limits[f])
        # Visible broken slab face, with large oblique cut and shallow protruding rebar.
        if len(footprint)>=3:
            B.prism(footprint,top,.2,'stone' if f==0 else 'plaster')
            if f>1 and len(footprint)>4:
                p=footprint[1]
                for k in range(3):B.tube([(p[0]-.3,p[1]+k*.22,top+.1),(p[0]+.7,p[1]+k*.22,top+.03)],.027,'bark',1,5)
        if f==floors:break
        z=top+.2;mid=z+2.45
        # Real walls assembled around recessed openings. Missing bays are actual voids.
        for side,nb,span in [('S',nbay,w),('N',nbay,w),('W',nbay_y,d),('E',nbay_y,d)]:
            for j in range(nb):
                t=-span/2+(j+.5)*span/nb
                x,y=(t,-d/2) if side=='S' else (t,d/2) if side=='N' else (-w/2,t) if side=='W' else (w/2,t)
                if not survive(x,y,f):continue
                bw=span/nb
                exterior_hole=(f>=floors-2 and rng.random()<damage*.42)
                if style=='frame' or (ishalf and f>=floors//2 and side in ('S','E')):
                    # Exposed reinforced concrete column and beam instead of generic dark facade.
                    B.box((x,y,mid),(.5,.5,4.9),'cloud',.095)
                    continue
                # coordinate transformer for a local facade box
                def fb(lx,depth,zz,sx,sy,sz,col,bev=0,role=0):
                    if side=='S':center=(x+lx,y+depth,zz);size=(sx,sy,sz)
                    elif side=='N':center=(x-lx,y-depth,zz);size=(sx,sy,sz)
                    elif side=='W':center=(x+depth,y-lx,zz);size=(sy,sx,sz)
                    else:center=(x-depth,y+lx,zz);size=(sy,sx,sz)
                    B.box(center,size,col,bev,role)
                if exterior_hole:
                    fb(-bw*.38,0,z+1.4,bw*.24,.45,2.8,color,.055)
                    fb(0,0,z+.3,bw,.45,.6,color,.055)
                    # A snapped lintel on only one side, not a repeated complete top edge.
                    fb(bw*.24,0,z+4.4,bw*.45,.45,.55,'stone',.04)
                    continue
                isdoor=f==0 and side=='S' and j==nb//2
                sill=.25 if isdoor else .85
                opening_h=3.3 if isdoor else 2.65
                windoww=bw*.64
                # Between-pier span only: full-bay sill/lintel overlaps the vertical piers and z-fights.
                fb(0,0,z+sill/2,bw*.70,.45,sill,color,.045)
                above=4.9-sill-opening_h
                fb(0,0,z+sill+opening_h+above/2,bw*.70,.45,above,color,.045)
                for dx in (-bw*.425,bw*.425):fb(dx,0,mid,bw*.15,.45,4.9,color,.035)
                # No black planes: recessed blue glass occupies the real opening, not the wall face.
                if not (f>floors*.6 and rng.random()<damage*.9):
                    fb(0,.12,z+sill+opening_h/2,windoww,.07,opening_h,'deepblue' if f%3==0 else 'ocean',0,2)
                    if f%2==0:fb(-windoww*.2,-.06,z+sill+opening_h*.5,.07,.08,opening_h*.85,'sky')
                for dx in (-windoww/2,windoww/2):fb(dx,-.13,z+sill+opening_h/2,.14,.2,opening_h+.15,'cream',.025)
                for zz in (z+sill,z+sill+opening_h):fb(0,-.13,zz,windoww+.15,.2,.14,'cream',.025)
                if not isdoor:fb(0,-.17,z+sill+opening_h*.52,windoww,.16,.1,'cream',.02)
                if style in ('tram','balcony','terrace') and side=='S' and f%2==1 and j%2==0:
                    B.box((x,y-1.1,z+.55),(bw*.9,2.3,.2),'stone',.075)
                    rail((x-bw*.42,y-2.1),(x+bw*.42,y-2.1),z+.65)
                if side=='S' and f%3==1 and j==0:aircon(x,y-.62,z+3.9)
        # Interior partitions become visible at genuinely cut-off upper floors.
        if ishalf and f<max(1,floors-1):
            for xx in (-w*.25,0):
                if survive(xx,0,f):B.box((xx,d*.08,mid),(.22,d*.72,4.9),'mint_white',.03)
    roof_z=floors*h+.5
    # Roof surviving border segments do not bridge the missing slab sector.
    for x,y,sx,sy in [(-w/2,0,.35,d),(w/2,0,.35,d),(0,-d/2,w,.35),(0,d/2,w,.35)]:
        if survive(x,y,floors):B.box((x,y,roof_z+.43),(sx,sy,.86),'stone',.121)
    for xx in (-w*.28,w*.1):
        yy=d*.14
        if survive(xx,yy,floors):
            B.box((xx,yy,roof_z+1.5),(3.1,2.7,3.0),'plaster',.138)
            B.box((xx,yy,roof_z+3.05),(3.5,3.1,.2),'gray',.07)
            B.box((xx,yy-1.38,roof_z+1.3),(1.3,.08,2.4),'sage_gray',.025)
            break
    if survive(-w*.24,-d*.2,floors):tank(-w*.24,-d*.2,roof_z)
    if survive(w*.22,-d*.22,floors):aircon(w*.22,-d*.22,roof_z+.55)
    # Different street identities, not only repeated window grids.
    if style in ('coffee','electronics','greenhouse','cinema','corner','station'):
        labels={'coffee':'COZY COFFEE','electronics':'ELECTRONICS','greenhouse':'GARDEN','cinema':'CINEMA','corner':'DEPARTMENT','station':'OLD STATION'}
        signcolor='red' if style in ('coffee','cinema','greenhouse') else 'teal'
        B.box((-.8,-d/2-.48,4.55),(w*.77,.5,1.8),signcolor,.12)
        text_shape(labels[style],(-.8,-d/2-.77,4.1),.8,'cream')
        # Orange and honey striped awnings with broken ends and thick valance.
        if style in ('coffee','electronics','corner'):
            aw=w*.78
            for j in range(6):
                if not (damage>.45 and j==5):
                    xx=-aw/2+(j+.5)*aw/6-.8
                    B.box((xx,-d/2-1.45,3.45),(aw/6-.02,2.4,.2),'honey' if j%2 else 'coral',.045,rot=(.2,0,0))
                    B.box((xx,-d/2-2.57,3.13),(aw/6-.02,.15,.5),'honey' if j%2 else 'coral',.035)
    if style in ('coffee','terrace','canal','greenhouse','station'):
        # Exterior staircase is attached to this single building and ends at a real surviving landing.
        sx=-w/2-1.25;steps=26;rise=h/steps;run=.46
        for j in range(steps):
            B.box((sx,-d/2+j*run,.35+(j+1)*rise-.1),(2.4,.5,.2),'stone',.044)
        B.box((sx,-d/2+steps*run+.5,h+.3),(2.6,1.8,.2),'stone',.05)
        B.tube([(sx-1.16,-d/2,.35+1),(sx-1.16,-d/2+steps*run,h+1.35)],.065,'steel')
    if style in ('greenhouse','coffee') and survive(-2,2,floors):
        # Open broken greenhouse frame and explicit missing glass panes.
        gz=roof_z+.1
        for xx in (-3,3):
            for yy in (1,5):B.box((xx,yy,gz+2),(.18,.18,4),'steel',.035,1)
        for yy in (1,3,5):
            B.tube([(-3,yy,gz+4),(0,yy,gz+5),(3,yy,gz+4)],.1,'steel')
        B.tube([(-3,1,gz+4),(-3,5,gz+4)],.1,'steel');B.tube([(3,1,gz+4),(3,5,gz+4)],.1,'steel')
        for xx in (-1.5,1.5):
            if xx<0:B.box((xx,3,gz+4.55),(2.9,3.8,.08),'sky',0,2,rot=(0,-.32,0))
    if style in ('workshop','station'):
        for x in (-w*.35,0,w*.35):
            B.tube([(x,-d*.4,roof_z),(x,0,roof_z+1.8),(x,d*.4,roof_z+.5)],.16,'steel')
    # Large jagged surface chips and broad cracks, not dense decal noise.
    for j in range(3):
        xx=-w*.4+j*w*.3;yy=-d/2-.245;zz=1.3+j*2.8
        if survive(xx,yy,int(zz/h)):
            pts=[(xx-.7,yy,zz+.5),(xx-.2,yy,zz+.15),(xx-.4,yy,zz-.3),(xx+.6,yy,zz-.8)]
            B.tube(pts,.035,'bark',0,4)
    for xx in (-w*.5,-w*.2):
        B.box((xx,-d/2-.1,.7),(1.6,.6,1.0),'stone',.09,rot=(.12,.13,.2))

def road(kind):
    if kind=='plaza_tile':
        for ix in range(5):
            for iy in range(5):
                if not(ix==4 and iy==0):B.box((-8+ix*4,-8+iy*4,.25),(3.94,3.94,.5),'stone' if (ix+iy)%3 else 'plaster',.044)
        return
    if kind=='canal_segment':
        for yy in (-5.8,5.8):
            B.box((0,yy,1.55),(20,4.4,.5),'stone',.08)
            B.box((0,yy+(-2.2 if yy>0 else 2.2),.9),(20,.35,1.8),'plaster',.08)
        B.box((0,0,.12),(20,7,.24),'sage_gray',.04)
        for x in (-7,2,8):B.box((x,-5,1.84),(3,.08,.03),'gray')
        return
    if kind in ('viaduct_intact','viaduct_broken'):
        for xx in (-7.7,7.7):B.box((xx,0,5),(1.2,1.8,10),'plaster',.095)
        B.box((0,0,9.65),(19.8,7.2,.6),'steel',.08)
        poly=[(-10,-4.5),(10,-4.5),(10,4.5),(-10,4.5)]
        if kind=='viaduct_broken':poly=[(-10,-4.5),(5,-4.5),(8,-2),(4,.5),(7,4.5),(-10,4.5)]
        B.prism(poly,10,.5,'stone')
        end=10 if kind=='viaduct_intact' else 4.6
        for yy in (-1.1,1.1):
            B.box(((end-10)/2,yy,10.72),(end+10,.13,.25),'steel',.035,1)
        for xx in range(-9,int(end),2):B.box((xx,0,10.57),(.4,3.4,.13),'wood_dark',.035)
        for yy in (-4.25,4.25):rail((-9.8,yy),(end,yy),10.5)
        if kind=='viaduct_broken':
            for yy in (-2,0,2):B.tube([(4,yy,10.3),(8,yy,9.9)],.055,'bark')
        return
    if kind=='stair_link':
        for i in range(40):B.box((0,-6.8+i*.34,.27+i*.263),(3.8,.38,.2),'stone',.044)
        B.tube([(-1.8,-6.8,1.2),(-1.8,6.46,11.5)],.08,'steel')
        return
    w=12 if kind=='junction' else 20;length=12
    if kind=='street_split':
        B.prism([(-10,-6),(-1,-6),(1,-2),(-2,0),(1,6),(-10,6)],0,.48,'gray')
        B.prism([(1.4,-6),(10,-6),(10,6),(2,6),(-.6,0),(2,-2)],.07,.48,'gray')
    else:B.box((0,0,.24),(w,length,.48),'gray',.06)
    for y in (-5.2,5.2):B.box((0,y,.49),(w,1.5,.22),'stone',.044)
    for x in range(-int(w/2)+1,int(w/2),4):
        B.box((x,0,.503),(2,.13,.025),'cream',.006)
    for y in (-3,-2,-1,1,2,3):
        if kind=='junction':B.box((-3.8,y,.505),(1.3,.5,.03),'cream',.008)
    for y in (-5.25,5.25):
        B.box((w*.3,y,.62),(1.1,.65,.035),'steel',.01)
        for xx in range(5):B.box((w*.3-.4+xx*.2,y,.647),(.06,.6,.02),'gray')

def facility(key):
    if key in ('car_sedan','car_van','tram_wreck','scooter'):
        if key=='scooter':
            for x in (-.65,.65):B.cyl((x,0,.4),.38,.18,'slate',0,12,'Y')
            B.box((-.2,0,.82),(1.5,.5,.45),'coral',.15);B.box((-.2,0,1.15),(.7,.55,.18),'wood_dark',.06)
            B.tube([(.7,0,.4),(.45,0,1.5),(.7,0,1.65)],.09,'silver');B.box((.65,0,1.65),(.14,.8,.12),'steel',.03)
            return
        tram=key=='tram_wreck';van=key=='car_van';l=12 if tram else 5.7 if van else 4.8;w=3.8 if tram else 2.5 if van else 2.2
        B.box((0,0,.7),(l,w,.9),'ochre' if tram else 'seafoam' if van else 'coral',.2)
        for x in (-l*.31,l*.31):
            for yy in (-w*.49,w*.49):B.cyl((x,yy,.47),.46 if not tram else .52,.24,'slate',0,12,'Y');B.cyl((x,yy*1.04,.47),.23,.28,'silver',1,10,'Y')
        roof=3.7 if tram else 2.7 if van else 1.8
        B.box((-.25,0,roof),(l*.9 if tram or van else l*.58,w*.96,.18),'plaster',.075)
        for side in (-1,1):
            for i in range(8 if tram else 3):
                x=-l*.4+(i+.5)*l*.8/(8 if tram else 3)
                B.box((x,side*w*.46,(roof+1.15)/2),(.12,.14,roof-1.15),'plaster',.03)
                if i%3!=1:B.box((x+.26,side*w*.445,(roof+1.25)/2),(.6 if tram else .8,.065,roof-1.5),'ocean',0,2)
        for x in (-l*.46,l*.46):B.box((x,0,(roof+1.1)/2),(.12,w*.95,roof-1.1),'sky',.03,2)
        if tram:
            for x in (-4,4):B.box((x,0,roof+.25),(2.3,2,.35),'silver',.08)
            B.tube([(-2,0,roof+.4),(0,0,roof+1.7),(2,0,roof+.4)],.07,'steel')
        else:
            for yy in (-w*.32,w*.32):B.box((l*.51,yy,.85),(.08,.35,.22),'butter',.03)
        return
    if key in ('utility_pole','leaning_pole'):
        lean=key=='leaning_pole';top=6.7 if lean else 9.8;dx=1.2 if lean else 0
        B.tube([(0,0,.2),(dx,0,top)],.19,'wood_dark',0,10)
        for zz in (top-.4,top-1.0):
            B.box((dx,0,zz),(2.6,.18,.18),'steel',.035,1)
            for xx in (-1,0,1):
                B.cyl((dx+xx,0,zz+.18),.12,.3,'cloud',0,8)
        B.box((.35,0,2.3),(.5,.5,.8),'silver',.06)
        return
    if key=='cable_span':
        for yy in (-.35,0,.35):B.tube([(-10,yy,2.5),(-5,yy,.8),(0,yy,0),(5,yy,.8),(10,yy,2.5)],.035,'steel',1,5)
        return
    if key in ('street_lamp','traffic_light','sign_board'):
        top=7 if key=='street_lamp' else 5.6 if key=='traffic_light' else 4.2
        B.cyl((0,0,.13),.5,.26,'stone',0,12)
        B.tube([(0,0,.2),(0,0,top), (2.3,0,top+.2)],.13,'steel')
        if key=='street_lamp':B.box((2.2,0,top),(1.1,.6,.35),'lightgray',.12);B.box((2.2,0,top-.2),(.8,.4,.05),'butter',.02)
        elif key=='traffic_light':
            B.box((2,0,top-.8),(.65,.5,1.8),'slate',.1)
            for zz,col in ((top-.25,'red_dark'),(top-.8,'honey'),(top-1.35,'jade')):B.cyl((2,-.28,zz),.17,.06,col,0,10,'Y')
        else:
            B.box((0,0,3.6),(4.3,.24,1.5),'teal',.1);text_shape('OLD TOWN',(0,-.15,3.35),.47)
        return
    if key=='vending':
        B.box((0,0,1.35),(1.4,1.1,2.7),'aqua',.13)
        B.box((-.12,-.57,1.7),(.95,.05,1.25),'ocean',.03,2)
        for i in range(3):
            for j in range(3):B.cyl((-.43+i*.3,-.63,1.25+j*.36),.09,.21,('coral','butter','seafoam')[(i+j)%3],0,8)
        B.box((0,-.59,.4),(.9,.08,.25),'steel',.03)
        B.box((.5,-.6,1.1),(.18,.09,.55),'honey',.02)
        return
    if key=='bus_shelter':
        for x in (-2.8,2.8):
            for y in (-1,1):B.box((x,y,1.6),(.16,.16,3.2),'steel',.03,1)
        B.box((-.6,0,3.25),(4.7,2.5,.2),'mint_white',.07)
        B.box((0,.95,1.7),(5.4,.1,2.3),'sky',0,2)
        B.box((0,.3,.85),(4.8,.8,.18),'wood',.06)
        for x in (-1.7,1.7):B.box((x,.3,.45),(.2,.65,.8),'steel',.03,1)
        return
    if key=='rubble_cluster':
        for i,(x,y,z,s) in enumerate([(-1.6,-.6,.3,2.8),(.9,.4,.6,3.2),(2,1.1,.3,1.5),(-.6,1.2,1.2,2.1)]):
            B.box((x,y,z),(s,s*.6,.45),'stone' if i%2 else 'plaster',.08,rot=(.1+i*.12,.13, i*.7))
        for i in range(4):B.tube([(-1+i*.4,0,.5),(-.8+i*.4,-.7,1.7)],.035,'bark')
        return
    if key=='corrosion_patch':
        rng=random.Random(71)
        for i in range(9):
            x=rng.uniform(-1.6,1.6);z=rng.uniform(.1,1.8);B.box((x,0,z),(rng.uniform(.15,.65),.045,rng.uniform(.1,.4)),'bark' if i%3==0 else 'stone',.035)
        return
    if key=='moss_patch':
        for i in range(8):
            a=i*2.4;r=.35+(i%3)*.38;B.cyl((math.cos(a)*r,math.sin(a)*r,.1+(i%2)*.04),.5,.16,('sage','moss','jade')[i%3],0,9)
        return
    if key=='kelp_clump':
        for i in range(7):
            a=i*2.3;x=math.cos(a)*.5;y=math.sin(a)*.5;h=1.6+(i%3)*.7
            pts=[(x,y,0),(x+.3*math.cos(a),y,h*.4),(x+.65*math.cos(a),y+.25,h*.75),(x+.1,y+.2,h)]
            # Broad smooth fronds, not terrestrial leafy trees.
            vs=[]
            for j,p in enumerate(pts):
                width=(.1,.3,.32,.01)[j];vs.extend([(p[0]-width,p[1],p[2]),(p[0]+width,p[1]+.08,p[2])])
            B.geo(vs,[(0,1,3,2),(2,3,5,4),(4,5,7,6)],('jade','fern','sage')[i%3],0,[True]*3)
        return
    raise ValueError(key)

CAT=[];COLS={}
for c in P['components']:
    B=Builder();col=bpy.data.collections.new(c['component_id']+'_'+c['name']);MA.children.link(col)
    if c['category']=='architecture':building(c)
    elif c['category']=='ground':road(c['key'])
    else:facility(c['key'])
    obj=B.finish(c['name'],col)
    # Canonical bottom-centre anchor is derived from actual geometry, including fixed accessories.
    lo=Vector(tuple(min(v.co[i] for v in obj.data.vertices) for i in range(3)))
    hi=Vector(tuple(max(v.co[i] for v in obj.data.vertices) for i in range(3)))
    shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for v in obj.data.vertices:v.co-=shift
    root=bpy.data.objects.new(c['component_id']+'_ROOT',None);col.objects.link(root);obj.parent=root
    for o in (root,obj):
        o['asset_id']=c['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False
        o['source_only']=True;o['emission']=False
    root['front_axis']='-Y';col.instance_offset=(0,0,0)
    obj.data.calc_loop_triangles()
    row=dict(c,collection=col.name,root_object=root.name,objects=[root.name,obj.name],bounds_size_m=list(hi-lo),
        local_origin=[0,0,0],authoring_origin_shift=list(shift),triangles=len(obj.data.loop_triangles),polygons=len(obj.data.polygons),
        material_roles=sorted({MATS[f.material_index].name for f in obj.data.polygons}),
        component_blend=f'art_source/scenes/sunken_city/v001/component_packages/{c["key"]}/{c["key"]}.blend',
        palette=P['palette'],version='v001',source_stage='source_authored_verification_pending',
        collision_owner='none_pure_scenery',dependencies=[])
    CAT.append(row);COLS[c['key']]=col
    print('COMPONENT',c['key'],row['triangles'],flush=True)

INST=[]
for a in P['instances']:
    c=next(c for c in CAT if c['key']==a['key']);obj=bpy.data.objects.new(a['instance_id'],None)
    obj.instance_type='COLLECTION';obj.instance_collection=COLS[a['key']]
    dest=ARCH if c['category']=='architecture' else GROUND if c['category']=='ground' else VEG if c['category']=='vegetation' else FAC
    dest.objects.link(obj);obj.location=a['position_m'];obj.rotation_euler=[math.radians(v) for v in a['rotation_euler_deg']]
    obj['asset_id']=c['component_id'];obj['building_class']='underwater';obj['collision']='none';obj['interactive']=False
    INST.append(dict(a,component_id=c['component_id'],source_object=obj.name))

# Frozen cameras: composed to show all the geometry, no water/background mesh disguising details.
def camera(name,pos,target,scale):
    data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);STAGE.objects.link(o)
    o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale
    return o
cams={
 'overview':camera('相机_全景_固定',(205,-250,150),(0,0,-38),310),
 'top':camera('相机_俯视_范围',(0,0,320),(0,0,-35),248),
 'street':camera('相机_电车街近景',(-28,-124,-17),(-77,-49,-39),95),
 'coffee':camera('相机_咖啡楼近景',(-57,-138,-17),(-96,-95,-49),49),
 'canal':camera('相机_运河街近景',(-6,-52,-5),(-59,-13,-40),108),
 'architecture':camera('相机_建筑分离',(205,-250,150),(0,0,-38),310),
}
S.camera=cams['overview'];S.render.engine='CYCLES';S.cycles.samples=24;S.cycles.use_denoising=True
S.render.resolution_x=1800;S.render.resolution_y=1500;S.render.resolution_percentage=100
S.view_settings.view_transform='AgX';S.view_settings.look='AgX - Medium High Contrast';S.view_settings.exposure=.65
world=bpy.data.worlds.new('展示环境_冷青漫射');world.use_nodes=True
background=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs[0].default_value=(.19,.32,.37,1)
background.inputs[1].default_value=.65;S.world=world;MASTER.world=world
sun=bpy.data.lights.new('展示日光','SUN');sun.energy=2.2;sun.angle=math.radians(16)
o=bpy.data.objects.new('展示日光',sun);STAGE.objects.link(o);o.rotation_euler=(.45,-.55,-.4)
area=bpy.data.lights.new('展示暖色大柔光','AREA');area.energy=125000;area.shape='DISK';area.size=180;area.color=(1,.85,.68)
o=bpy.data.objects.new('展示暖色大柔光',area);STAGE.objects.link(o);o.location=(-70,-80,90)
# Non-rendering boundaries explicitly visualize measured scope in the Blender viewport.
for q in P['exclusions']:
    x0,x1,y0,y1=q['xy'];e=bpy.data.objects.new('禁建区_'+q['id'],None);STAGE.objects.link(e)
    e.empty_display_type='CUBE';e.empty_display_size=1;e.location=((x0+x1)/2,(y0+y1)/2,-31);e.scale=((x1-x0)/2,(y1-y0)/2,32);e.color=(1,.12,.06,1)
e=bpy.data.objects.new('围栏内边界_240x240_水深63m',None);STAGE.objects.link(e);e.empty_display_type='CUBE';e.empty_display_size=1;e.location=(0,0,-30.4);e.scale=(120,120,31.5);e.color=(.2,.8,1,1)
S['suite']='sunken_city';S['scope']='source_only_underwater';S['water_level_m']=1.12;S['seabed_depth_estimate_m']=63.02
S['protected_existing_regions']=json.dumps(P['exclusions']);S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest()
S['authored_in_live_mcp']=True
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':
            sp=ar.spaces.active;sp.shading.type='MATERIAL';sp.overlay.show_floor=False
            sp.region_3d.view_perspective='CAMERA'
if bpy.context.window:bpy.context.window.scene=S
for c in CAT:
    n=sum(i['key']==c['key'] for i in INST);c['instance_count']=n
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':CAT},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'instances':INST},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_tree.txt').write_text('\n'.join(c['component_id']+' '+c['name']+' -> component_packages/'+c['key'] for c in CAT)+'\n',encoding='utf-8')
CANDIDATE=W/'sunken_city_working.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(CANDIDATE),compress=True)
print(json.dumps({'built_in_live_blender':True,'components':len(CAT),'instances':len(INST),'working_file':str(CANDIDATE),'master_triangles':sum(c['triangles'] for c in CAT),'layout_triangles':sum(c['triangles']*c['instance_count'] for c in CAT)},ensure_ascii=False))
