"""Author six independent low-poly scenery buildings, never regenerate existing TSCN."""
import bpy, bmesh, hashlib, json, math, os
from pathlib import Path
from mathutils import Matrix, Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/submerged_neighborhood/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'submerged_neighborhood_v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert P['status']=='frozen_before_geometry' and sha(D/'reference.jpg')==P['reference_sha256']
assert not (D/'submerged_neighborhood.blend').exists(), 'Preserve authored source; use next version'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene;S.name='水下街区_参考布局';S.unit_settings.system='METRIC'
L=bpy.data.scenes.new('独立建筑母版');L.unit_settings.system='METRIC'
MA=bpy.data.collections.new('建筑_独立纯景观');L.collection.children.link(MA)
AS=bpy.data.collections.new('参考布局_建筑实例');S.collection.children.link(AS)
ST=bpy.data.collections.new('展示支持_不导出');S.collection.children.link(ST)
palette=R/P['palette'];img=bpy.data.images.load(str(palette));img.name='SEA_公共方格色板'
cells={c['name']:c for c in json.loads(palette.with_suffix('.json').read_text())['cells']}
mat=bpy.data.materials.new('SEA_Matte');mat.use_nodes=True;n=mat.node_tree.nodes;n.clear()
bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=.8
tex=n.new('ShaderNodeTexImage');tex.image=img;tex.interpolation='Closest'
uvn=n.new('ShaderNodeUVMap');uvn.uv_map='PaletteUV';out=n.new('ShaderNodeOutputMaterial')
for a,b in [(uvn.outputs['UV'],tex.inputs['Vector']),(tex.outputs['Color'],bs.inputs['Base Color']),(bs.outputs[0],out.inputs[0])]:mat.node_tree.links.new(a,b)
current=None
def active(o):
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
def finish(o,name,color,bevel=0):
    o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    current.objects.link(o);active(o)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        m=o.modifiers.new('实体单段倒角','BEVEL');m.width=bevel;m.segments=1;m.limit_method='ANGLE';bpy.ops.object.modifier_apply(modifier=m.name)
    o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
    o.data.materials.clear();o.data.materials.append(mat)
    for u in list(o.data.uv_layers):o.data.uv_layers.remove(u)
    uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True;c=cells[color];cx=(c['column']+.5)/8;cy=1-(c['row']+.5)/8
    for f in o.data.polygons:
        for j,li in enumerate(f.loop_indices):uv.data[li].uv=(cx+.025*math.cos(math.tau*j/len(f.loop_indices)),cy+.025*math.sin(math.tau*j/len(f.loop_indices)))
    return o
def mesh(name,vs,fs,color,bevel=0):
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(name,me);L.collection.objects.link(o)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    return finish(o,name,color,bevel)
def box(name,loc,size,color,bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size
    return finish(o,name,color,bevel)
def prism(name,poly,z,h,color,bevel=0):
    N=len(poly);vs=[(x,y,q) for q in (z,z+h) for x,y in poly]
    fs=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
    return mesh(name,vs,fs,color,bevel)
def footprint(w,d,style):
    if style=='curved':
        pts=[(-w/2,-d/2),(w/2,-d/2),(w/2,d*.06)]
        pts += [(w*.5*math.cos(i*math.pi/6),d*.06+d*.44*math.sin(i*math.pi/6)) for i in range(1,7)]
        return pts
    if style=='L':return [(-w/2,-d/2),(w/2,-d/2),(w/2,d*.08),(w*.05,d*.08),(w*.05,d/2),(-w/2,d/2)]
    c=.24
    return [(-w/2+c,-d/2),(w/2-c,-d/2),(w/2,-d/2+c),(w/2,d/2-c),(w/2-c,d/2),(-w/2+c,d/2),(-w/2,d/2-c),(-w/2,-d/2+c)]
def scale_poly(poly,k):return [(x*k,y*k) for x,y in poly]
catalog=[];collections={}
bpy.context.window.scene=L
for item in P['components']:
    k=item['key'];w,d,h=item['size_blender_xyz'];floors=item['floors'];style=item['style']
    current=bpy.data.collections.new(item['asset_id']);MA.children.link(current);collections[k]=current
    poly=footprint(w-.5,d-.5,style)
    body='aqua' if style in ['curved','annex'] else 'teal'
    prism('青绿混凝土楼壳',poly,0,h-.28,body)
    # Layered broad cornices carry the silhouette; one real bevel only on roof.
    for floor in range(floors+1):
        z=.18+floor*(h-.60)/floors
        prism('层叠外挑檐线_%02d'%floor,scale_poly(poly,1.06),z,.18,'sage_gray' if floor%2 else 'seafoam',.035 if floor==floors else 0)
    roof_z=h-.20
    # Sunken rooftop surface and a broken, low parapet. No miniature house on top.
    prism('低凹屋面',scale_poly(poly,.91),roof_z,.05,'sage_gray')
    for j in range(len(poly)):
        if j%3==1:continue
        a=Vector((*poly[j],roof_z));b=Vector((*poly[(j+1)%len(poly)],roof_z));v=b-a
        if v.length<.7:continue
        o=box('断续女儿墙_%02d'%j,(a+b)*.5+Vector((0,0,.15)),(v.length,.14,.30),'seafoam')
        # Bake the rotation after initial construction and keep object transform identity.
        center=(a+b)*.5+Vector((0,0,.15));o.data.transform(Matrix.Translation(center)@Matrix.Rotation(math.atan2(v.y,v.x),4,'Z')@Matrix.Translation(-center))
    # Recessed-looking window planes are bounded by projecting structural piers.
    for edge in range(len(poly)):
        a=Vector(poly[edge]);b=Vector(poly[(edge+1)%len(poly)]);v=b-a;length=v.length
        if length<.65:continue
        nrm=Vector((v.y,-v.x)).normalized();u=v.normalized()
        cols=max(1,round(length/1.65));step=length/cols
        for floor in range(floors):
            z=.65+floor*(h-.60)/floors;wh=(h-.60)/floors-.93
            for col in range(cols):
                c=a+u*(col+.5)*step+nrm*.018;hw=(step-.26)/2
                vs=[(c.x-u.x*hw,c.y-u.y*hw,z),(c.x+u.x*hw,c.y+u.y*hw,z),
                    (c.x+u.x*hw,c.y+u.y*hw,z+wh),(c.x-u.x*hw,c.y-u.y*hw,z+wh)]
                color='deepblue' if (floor+col+edge)%3 else 'ocean'
                mesh('暗蓝窗格_%d_%d_%d'%(edge,floor,col),vs,[(0,1,2,3)],color)
                # Thin central mullion is a single plane rather than a hidden box.
                if length>3.0:
                    m=.035
                    mesh('竖窗梃',[(c.x-u.x*m+nrm.x*.008,c.y-u.y*m+nrm.y*.008,z),
                        (c.x+u.x*m+nrm.x*.008,c.y+u.y*m+nrm.y*.008,z),
                        (c.x+u.x*m+nrm.x*.008,c.y+u.y*m+nrm.y*.008,z+wh),
                        (c.x-u.x*m+nrm.x*.008,c.y-u.y*m+nrm.y*.008,z+wh)],[(0,1,2,3)],'sky')
        if length>3:
            for f in [.04,.96]:
                c=a+v*f+nrm*.06
                box('立面细柱',(c.x,c.y,(h-.35)/2),(.16,.16,h-.35),'aqua')
    if style=='tiered':
        # Offset front balcony/ledge echoes the right-hand terraced building.
        for f in [1,3]:box('错层挑台',(w*.10,d*.44,.20+f*(h-.60)/floors),(w*.62,1.0,.20),'seafoam',.025)
    if style in ['slender','annex','slab']:
        box('屋顶检修凸台',(-w*.18,-d*.16,h-.04),(w*.32,d*.26,.30),'aqua',.035)
    # Low-cost worn paint islands attached to host facades, never emissive.
    for i in range(6):
        edge=(i*3+1)%len(poly);a=Vector(poly[edge]);b=Vector(poly[(edge+1)%len(poly)]);v=b-a;nrm=Vector((v.y,-v.x)).normalized()
        c=a+v*(.18+(i%3)*.25)+nrm*.025;z=.5+(i*.153%1)*(h-1.2);u=v.normalized();sz=.18+(i%2)*.15
        mesh('残留墙漆',[(c.x-u.x*sz,c.y-u.y*sz,z),(c.x+u.x*sz,c.y+u.y*sz,z+.06),
            (c.x+u.x*sz*.6,c.y+u.y*sz*.6,z+.38),(c.x-u.x*sz*.7,c.y-u.y*sz*.7,z+.25)],[(0,1,2,3)],'lavender' if i%2 else 'jade')
    obs=list(current.objects);bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=k
    # Normalize the actual envelope (roof lip included), not just the design body.
    pts=[v.co for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)])
    off=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));o.data.transform(Matrix.Translation(-off));current.instance_offset=(0,0,0)
    o['asset_id']=item['asset_id'];o['category']='underwater_scenic_building';o.data.calc_loop_triangles()
    tris=len(o.data.loop_triangles);assert tris<=1000,(k,tris)
    row=dict(item,polygons=len(o.data.polygons),triangles=tris,bounds_min=list(lo-off),bounds_max=list(hi-off),
        origin=[0,0,0],material_roles=['SEA_Matte'],collision='none',interactive=False)
    catalog.append(row)
    print(k, row['polygons'],'polygons',tris,'triangles',flush=True)
# Reference arrangement is traceable; formal Godot scene remains placement owner.
instances=[]
for i in catalog:
    x,y,z=i['placement_godot'];o=bpy.data.objects.new(i['name'],None);AS.objects.link(o)
    o.instance_type='COLLECTION';o.instance_collection=collections[i['key']];o.location=(x,-z,y)
    instances.append(dict(instance_id='home_submerged/'+i['key'],asset_id=i['asset_id'],key=i['key'],
        position=list(o.location),rotation_euler_xyz=[0,0,0],scale=[1,1,1]))
bpy.context.window.scene=S
def stage_setup():
    S.render.engine='CYCLES';S.cycles.samples=16;S.cycles.use_denoising=True
    S.render.resolution_x=1200;S.render.resolution_y=900;S.render.resolution_percentage=100
    S.world=bpy.data.worlds.new('柔和蓝灰展示');S.world.use_nodes=True;S.world.node_tree.nodes['Background'].inputs[0].default_value=(.21,.30,.37,1);S.world.node_tree.nodes['Background'].inputs[1].default_value=.65
    S.view_settings.view_transform='Standard';S.view_settings.look='None';S.view_settings.exposure=0
    for name,loc,power,size in [('主光',(-8,-12,28),3000,18),('补光',(15,5,18),2200,15)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);ST.objects.link(o);o.location=loc;o.rotation_euler=(Vector((3,-8,-7))-o.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('固定参考镜头');o=bpy.data.objects.new('固定参考镜头',data);ST.objects.link(o);S.camera=o;data.type='ORTHO';data.ortho_scale=52
stage_setup()
img.filepath=bpy.path.relpath(str(palette),start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D/'submerged_neighborhood.blend'))
write(D/'catalog.json',{'components':catalog});write(D/'component_instances.json',{'coordinate_system':'Blender XY/+Z; (x,y,z)->(x,z,-y)','instances':instances})
# package_export.py reopens the saved source and safely saves independent packages.
print('SOURCE_COMPLETE', D, flush=True)
