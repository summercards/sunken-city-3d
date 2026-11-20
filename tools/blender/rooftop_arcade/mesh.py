import bpy
import bmesh
import random
from math import sin, cos, pi, radians, atan2, sqrt, tau
from mathutils import Vector, Euler, Matrix

PARTS = {}
MATS = {}
GEN = random.Random(4157)
CURRENT = []


def group(parent,name):
    c=bpy.data.collections.new(name); parent.children.link(c); return c


def materials():
    image = bpy.data.images.load(PALETTE, check_existing=True)
    image.filepath = '//../../../shared/palettes/sea_rooftop_arcade_8x8_512.png'
    for role,metal,rough in [('Matte',0,.79),('Metal',.65,.4),('Gloss',.08,.2),('Emission',0,.37)]:
        m=bpy.data.materials.get('SEA_'+role) or bpy.data.materials.new('SEA_'+role)
        m.use_nodes=True; n=m.node_tree.nodes; n.clear(); links=m.node_tree.links
        uv=n.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'; uv.location=(-520,0)
        tex=n.new('ShaderNodeTexImage'); tex.image=image; tex.interpolation='Closest'; tex.location=(-300,0)
        f=n.new('ShaderNodeBsdfPrincipled'); o=n.new('ShaderNodeOutputMaterial'); o.location=(320,0)
        links.new(uv.outputs[0],tex.inputs[0]); links.new(tex.outputs[0],f.inputs['Base Color']); links.new(f.outputs[0],o.inputs[0]); f.inputs['Metallic'].default_value=metal; f.inputs['Roughness'].default_value=rough
        if role=='Gloss': f.inputs['Coat Weight'].default_value=.54
        if role=='Emission':
            links.new(tex.outputs[0],f.inputs['Emission Color']); f.inputs['Emission Strength'].default_value=1.35
        MATS[role]=m


def part(key):
    CURRENT.clear()
    CURRENT.append(PARTS[key])


def new_mesh(name,v,f,col,mat='Matte',b=0,seg=2,smooth=False):
    m=bpy.data.meshes.new(name); m.from_pydata(v,[],f); m.update()
    bm=bmesh.new(); bm.from_mesh(m); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(m); bm.free()
    o=bpy.data.objects.new(name+(' | emission' if mat=='Emission' else ''),m); CURRENT[0].objects.link(o); m.materials.append(MATS[mat]); o['palette_color']=col
    layer=m.uv_layers.new(name='PaletteUV'); layer.active_render=True
    slot=COLORS[col]; x=(slot%8+.5)/8; y=1-(slot//8+.5)/8
    for p in m.polygons:
        p.use_smooth=smooth
        count=len(p.loop_indices)
        for i,j in enumerate(p.loop_indices):
            a=tau*i/count; layer.data[j].uv=(x+.029*cos(a),y+.029*sin(a))
    if b:
        mod=o.modifiers.new('SEA profile bevel','BEVEL'); mod.width=b; mod.segments=seg; mod.limit_method='ANGLE'; mod.harden_normals=True
        norm=o.modifiers.new('SEA weighted corner normals','WEIGHTED_NORMAL'); norm.keep_sharp=True; norm.weight=40
        o['bevel_radius_m']=b; o['bevel_segments']=seg
    return o


def box(name,center,size,col,b=.015,rho=.028,skew=(0,0),rot=(0,0,0),mat='Matte',seg=None):
    a,d,h=(i/2 for i in size); v=[]; r=Euler(rot).to_matrix(); c=Vector(center)
    for j in (-1,1):
        for x,y in ((-a,-d),(a,-d),(a,d),(-a,d)):
            v.append(c+r@Vector((x*(1-rho*(j==1))+skew[0]*(j==1), y*(1-rho*(j==1))+skew[1]*(j==1),j*h)))
    return new_mesh(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],col,mat,min(b,min(size)*.35),seg or (3 if b>=.024 else 1 if b<=.011 else 2))


def extrude(name,points,depth,col,axis=1,offset=0,b=.015,mat='Matte'):
    n=len(points); v=[]
    for k in (-1,1):
        for a,c in points:
            q=offset+k*depth/2; v.append((a,q,c) if axis==1 else (q,a,c) if axis==0 else (a,c,q))
    f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return new_mesh(name,v,f,col,mat,min(b,depth*.31),3 if b>=.024 else 2)


def profile(name,pts,depth,y,col,b=.015,mat='Matte'):
    return extrude(name,pts,depth,col,1,y,b,mat)


def sheet(name,grid,thickness,col,mat='Matte'):
    n=len(grid); m=len(grid[0]); v=[]
    for k in (-1,1):
        for i in range(n):
            for j in range(m):
                a=Vector(grid[i][j]); s=Vector(grid[min(n-1,i+1)][j])-Vector(grid[max(0,i-1)][j]); t=Vector(grid[i][min(m-1,j+1)])-Vector(grid[i][max(0,j-1)]); v.append(a+s.cross(t).normalized()*(k*thickness/2))
    faces=[]; w=n*m
    for i in range(n-1):
        for j in range(m-1):
            a=i*m+j; f=(a,a+1,a+1+m,a+m); faces.extend((f,tuple(w+p for p in reversed(f))))
    rim=list(range(m))+[i*m+m-1 for i in range(1,n)]+[(n-1)*m+j for j in range(m-2,-1,-1)]+[i*m for i in range(n-2,0,-1)]
    faces.extend((j,rim[(i+1)%len(rim)],rim[(i+1)%len(rim)]+w,j+w) for i,j in enumerate(rim))
    return new_mesh(name,v,faces,col,mat,smooth=True)


def tube(name,points,rad,col,mat='Matte',taper=.065,sides=10):
    pn=[Vector(p) for p in points]; closed=(pn[-1]-pn[0]).length<.00001
    if closed: pn=pn[:-1]
    n=len(pn); v=[]; f=[]; ref=Vector((0,0,1))
    directions=[(pn[(i+1)%n if closed else min(i+1,n-1)]-pn[(i-1)%n if closed else max(0,i-1)]).normalized() for i in range(n)]
    if max(abs(d.dot(ref)) for d in directions)>.96: ref=Vector((0,1,0))
    if max(abs(d.dot(ref)) for d in directions)>.96: ref=Vector((1,.17,.11)).normalized()
    for i,p in enumerate(pn):
        d=directions[i]; a=d.cross(ref).normalized(); c=d.cross(a).normalized(); rr=rad*(1-taper*i/(n-1))
        for j in range(sides):
            q=tau*j/sides; v.append(p+rr*(a*cos(q)+c*sin(q)))
    for i in range(n if closed else n-1):
        for j in range(sides):
            nxt=(i+1)%n; k=(j+1)%sides; f.append((i*sides+j,i*sides+k,nxt*sides+k,nxt*sides+j))
    if not closed: f.extend([tuple(range(sides-1,-1,-1)),tuple(range((n-1)*sides,n*sides))])
    return new_mesh(name,v,f,col,mat,smooth=True)


def rod(name,a,b,rad,col,mat='Matte'):
    return tube(name,[a,b],rad,col,mat,sides=12)


def oval(name,center,radii,col,mat='Matte',rot=(0,0,0)):
    c=Vector(center); r=Euler(rot).to_matrix(); a,b,h=radii; n=16; m=8
    v=[c+r@Vector((0,0,-h))]; f=[]
    for i in range(1,m):
        q=-pi/2+pi*i/m
        for j in range(n):
            g=tau*j/n; v.append(c+r@Vector((a*cos(q)*cos(g),b*cos(q)*sin(g),h*sin(q))))
    end=len(v); v.append(c+r@Vector((0,0,h)))
    for j in range(n):
        k=(j+1)%n
        f.extend([(0,k+1,j+1),(end,1+(m-2)*n+j,1+(m-2)*n+k)])
        for i in range(m-2):
            x=1+i*n; f.append((x+j,x+k,x+n+k,x+n+j))
    return new_mesh(name,v,f,col,mat,smooth=True)


FONT={
'A':'010/101/111/101/101','B':'110/101/110/101/110','C':'011/100/100/100/011','D':'110/101/101/101/110','E':'111/100/110/100/111','F':'111/100/110/100/100','G':'011/100/101/101/011','H':'101/101/111/101/101','I':'111/010/010/010/111','J':'001/001/001/101/010','K':'101/101/110/101/101','L':'100/100/100/100/111','M':'101/111/111/101/101','N':'101/111/111/111/101','O':'010/101/101/101/010','P':'110/101/110/100/100','Q':'010/101/101/111/011','R':'110/101/110/101/101','S':'011/100/010/001/110','T':'111/010/010/010/010','U':'101/101/101/101/111','V':'101/101/101/101/010','W':'101/101/111/111/101','X':'101/101/010/101/101','Y':'101/101/010/010/010','Z':'111/001/010/100/111','0':'111/101/101/101/111','1':'010/110/010/010/111','2':'110/001/010/100/111','3':'110/001/010/001/110','4':'101/101/111/001/001','5':'111/100/110/001/110','6':'011/100/111/101/111','7':'111/001/010/010/010','8':'111/101/111/101/111','9':'111/101/111/001/110','!':'010/010/010/000/010','-':'000/000/111/000/000'}


def mark(name,text,loc,size,col,mat='Matte'):
    step=size/5; v=[]; f=[]; lx,ly,lz=loc
    for k,ch in enumerate(text.upper()):
        for j,row in enumerate(FONT.get(ch,'000/000/000/000/000').split('/')):
            for i,on in enumerate(row):
                if on!='1': continue
                x=lx+(4*k+i-(len(text)*4-2)/2)*step; z=lz+(2-j)*step; a=step*.462; d=max(.002,step*.24); n=len(v)
                v.extend([(x-a,ly-d,z-a),(x+a,ly-d,z-a),(x+a,ly-d,z+a),(x-a,ly-d,z+a),(x-a,ly+d,z-a),(x+a,ly+d,z-a),(x+a,ly+d,z+a),(x-a,ly+d,z+a)])
                f.extend(tuple(n+i for i in p) for p in ((0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)))
    if v: return new_mesh(name,v,f,col,mat)


def finalize_master(master):
    bpy.context.window.scene=master
    view=bpy.context.view_layer
    for c in PARTS.values():
        work=list(c.objects)
        mn=min(v.co.z for o in work for v in o.data.vertices)
        for o in work:
            for v in o.data.vertices: v.co.z -= mn
            o.data.update()
        view.update()
        for o in work:
            if not o.modifiers: continue
            view.objects.active=o
            for mod in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
        residual=min(v.co.z for o in work for v in o.data.vertices)
        for o in work:
            for v in o.data.vertices: v.co.z -= residual
            o.data.update()
        c['original_min_z']=mn+residual
        c['meters']=True
        c['front_axis']='-Y'
        c['origin']='bottom_center'
        for o in work:
            col=o['palette_color']; m=o.data; slot=COLORS[col]; x=(slot%8+.5)/8; y=1-(slot//8+.5)/8
            layer=m.uv_layers.get('PaletteUV'); layer.active_render=True
            for p in m.polygons:
                count=len(p.loop_indices)
                for i,j in enumerate(p.loop_indices):
                    a=tau*i/count; layer.data[j].uv=(x+.027*cos(a),y+.027*sin(a))
