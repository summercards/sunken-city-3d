import bpy, bmesh, json, math, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/water_building_002/v001';W=R.parent/'sea-work/water_building_002/v001';D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
REF=Path(r'C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-11-10T02-51-58-980Z-73413825.jpg')
# Fresh blank Blender session supplied by the user.
for s in list(bpy.data.scenes):
    if s.name!='Scene': bpy.data.scenes.remove(s)
sc=bpy.context.scene
if not (W/'session_before.blend').exists(): bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
sc.name='WB002_编号002水上建筑_v001';sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1.0
# shared palette image + three roles
pal=R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png';
if pal.is_file(): image=bpy.data.images.load(str(pal),check_existing=True)
else: image=None
cells={c['name']:c for c in json.loads(pal.with_suffix('.json').read_text(encoding='utf-8'))['cells']} if pal.with_suffix('.json').is_file() else {}
cell_alias={'wall':'plaster','glass':'deepblue','leaf2':'leaf_light','trunk':'bark','metal':'gray','solar':'solar'}
roles={};
for role,rough,metal in [('SEA_Matte',.72,0),('SEA_Metal',.45,.3),('SEA_Gloss',.25,0)]:
    m=bpy.data.materials.new('WB002_'+role);m['semantic_role']=role;m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
    if image:
        uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=m.node_tree.nodes.new('ShaderNodeTexImage');tx.image=image;tx.interpolation='Closest';m.node_tree.links.new(uv.outputs['UV'],tx.inputs['Vector']);m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color'])
    roles[role]=m
colors={'cream':(0.76,0.72,0.57,1),'wall':(0.72,0.66,0.50,1),'dark':(0.08,0.13,0.14,1),'glass':(0.06,0.22,0.22,1),'blue':(0.05,0.16,0.22,1),'solar':(0.03,0.09,0.14,1),'wood':(0.25,0.12,0.06,1),'leaf':(0.15,0.42,0.05,1),'leaf2':(0.42,0.72,0.05,1),'trunk':(0.20,0.09,0.035,1),'red':(0.65,0.12,0.04,1),'metal':(0.30,0.38,0.36,1)}
top={}
for g,label in [('structure','01_建筑结构'),('furnishing','02_固定设施'),('plant','03_独立植物'),('display','90_展示支持')]:
 c=bpy.data.collections.new('WB002_'+label);sc.collection.children.link(c);top[g]=c
components={};catalog=[];layout=[];current=None

def mat_for(c,role='SEA_Matte'):
 m=roles[role].copy();m.diffuse_color=colors.get(c,colors['wall']);m.name='WB002_'+role+'_'+c;return m

def finish(o,c='wall',role='SEA_Matte',bevel=0):
    me=o.data
    if bevel:
        bm=bmesh.new();bm.from_mesh(me);bmesh.ops.bevel(bm,geom=list(bm.edges),offset=bevel,segments=1,profile=.5,clamp_overlap=True);bm.to_mesh(me);bm.free()
    for old in list(me.uv_layers):me.uv_layers.remove(old)
    uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
    # Map each semantic color into its own shared palette cell with nonzero islands.
    pname=cell_alias.get(c,c); cell=cells.get(pname,{'column':0,'row':0});cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
    for f in me.polygons:
        n=max(3,f.loop_total)
        for j,li in enumerate(f.loop_indices):
            a=2*math.pi*j/n;uv.data[li].uv=(cx+.025*math.cos(a),cy+.025*math.sin(a))
    me.materials.clear();me.materials.append(mat_for(c,role));o['palette_color']=pname;o['semantic_role']=role;o['bevel_segments']=1 if bevel else 0;me.update();return o

def mesh(n,vs,fs,c='wall',role='SEA_Matte',bevel=0):
    me=bpy.data.meshes.new('WB002_'+n);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('WB002_'+n,me);current.objects.link(o);return finish(o,c,role,bevel)

def box(n,p,s,c='wall',role='SEA_Matte',b=.03):
    x,y,z=p;w,d,h=[q/2 for q in s];vs=[(x+a*w,y+bb*d,z+cc*h) for a,bb,cc in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]];return mesh(n,vs,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],c,role,min(b,min(s)*.3))

def tapered(n,p,s,rho=.02,c='wall',role='SEA_Matte',axis='z',b=.025):
    o=box(n,p,s,c,role,0);lo=p[{'x':0,'y':1,'z':2}[axis]]-s[{'x':0,'y':1,'z':2}[axis]]/2;span=s[{'x':0,'y':1,'z':2}[axis]]
    ai={'x':0,'y':1,'z':2}[axis]
    for v in o.data.vertices:
        t=(v.co[ai]-lo)/span;factor=1-rho*t
        for j in range(3):
            if j!=ai:v.co[j]=p[j]+(v.co[j]-p[j])*factor
    return finish(o,c,role,b)

def tube(n,pts,r=.08,c='trunk',role='SEA_Matte',sides=6):
    pts=[Vector(x) for x in pts];vs=[]
    for i,p in enumerate(pts):
        t=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized();ref=Vector((0,0,1)) if abs(t.z)<.9 else Vector((0,1,0));u=t.cross(ref).normalized();v=t.cross(u).normalized();rr=r*(1-.05*i/max(1,len(pts)-1));vs.extend(tuple(p+rr*(u*math.cos(2*math.pi*j/sides)+v*math.sin(2*math.pi*j/sides))) for j in range(sides))
    fs=[tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))]+[(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(pts)-1) for j in range(sides)]
    return mesh(n,vs,fs,c,role,0)

def ico(n,p,s,c='leaf'):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=p);o=bpy.context.object;o.name='WB002_'+n;current.objects.link(o);bpy.context.collection.objects.unlink(o);o.scale=s;return finish(o,c)

def component(key,group,kind,rho=.02,fn=None):
    global current
    current=bpy.data.collections.new('SEA-SCENE-WATER-BUILDING-002-'+key.upper().replace('_','-'));sc.collection.children.link(current);current['asset_id']='SEA-SCENE-WATER-BUILDING-002-'+key.upper();current['kind']=kind;current['rho']=rho;current['group']=group;fn()
    pts=[v.co.copy() for o in current.all_objects if o.type=='MESH' for v in o.data.vertices]
    lo=Vector((min(v.x for v in pts),min(v.y for v in pts),min(v.z for v in pts)));hi=Vector((max(v.x for v in pts),max(v.y for v in pts),max(v.z for v in pts)));pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for o in current.all_objects:
        if o.type=='MESH':o.data.transform(Matrix.Translation(-pivot))
    current.instance_offset=(0,0,0);components[key]=current;sc.collection.children.unlink(current)
    tris=polys=0;h=hashlib.sha256()
    for o in current.all_objects:
        if o.type!='MESH':continue
        o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
        for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
    catalog.append({'key':key,'asset_id':'SEA-SCENE-WATER-BUILDING-002-'+key.upper(),'collection':current.name,'group':group,'kind':kind,'rho':rho,'bounds_size':list(hi-lo),'triangles':tris,'polygons':polys,'meshes':sum(o.type=='MESH' for o in current.all_objects),'material_roles':sorted({o.get('semantic_role') for o in current.all_objects if o.type=='MESH'}),'geometry_fingerprint':h.hexdigest(),'fingerprint_algorithm':'ordered_vertices_fixed6_sha256','component_source':f'art_source/scenes/water_building_002/v001/component_packages/{key}/{key}.blend'})

def put(k,p,a=0,rot=(0,0,0)):
 e=next(x for x in catalog if x['key']==k);o=bpy.data.objects.new('WB002_I_'+k+'_'+str(sum(q['key']==k for q in layout)+1).zfill(3),None);o.instance_type='COLLECTION';o.instance_collection=components[k];o.location=p;o.rotation_euler=rot if rot!=(0,0,0) else (0,0,a);top[next(x for x in ['structure','furnishing','plant'] if next(y for y in catalog if y['key']==k)['group']==x)].objects.link(o);layout.append({'name':o.name,'key':k,'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':[1,1,1]});return o
# Components
component('deck','structure','slab',.018,lambda:box('水上底座',(0,0,.15),(9.2,7.2,.3),'cream',b=.06))
component('shell','structure','shell',.018,lambda: [tapered('层体',(0,0,1.55+3.0*i),(8.6,6.4,3.0),.018,'wall',b=.045) for i in range(7)])
component('slab','structure','slab',.015,lambda:box('楼板',(0,0,0),(8.8,6.6,.18),'cream',b=.04))
component('roof','structure','roof',-.025,lambda:tapered('顶层屋面',(0,0,.12),(9.0,6.8,.24),-.025,'cream',b=.05))
component('window','furnishing','opening',.025,lambda:[box('绿色窗玻璃',(0,-3.22,1.72),(2.5,.08,1.55),'glass','SEA_Gloss',.015),box('窗框上',(0,-3.28,2.55),(2.7,.14,.12),'cream',b=.02),box('窗框下',(0,-3.28,.89),(2.7,.14,.12),'cream',b=.02),box('窗框左',(-1.3,-3.28,1.72),(.12,.14,1.8),'cream',b=.02),box('窗框右',(1.3,-3.28,1.72),(.12,.14,1.8),'cream',b=.02)])
component('balcony','furnishing','canopy',-.03,lambda:[tapered('阳台板',(0,-3.85,0),(4.2,1.1,.18),-.03,'cream',b=.04),box('阳台栏杆',(0,-4.36,1.0),(4.2,.08,1.2),'metal','SEA_Metal',b=.018),box('阳台侧栏杆',(-2.05,-3.85,1.0),(.08,1.0,1.2),'metal','SEA_Metal',b=.018)])
component('solar_panel','furnishing','solar',.025,lambda:[box('太阳能板',(x,y,.12),(1.8,1.1,.06),'solar','SEA_Gloss',.01) for x in [-2.7,-.9,.9,2.7] for y in [-1.65,-.5,.65,1.8]])
component('ac_unit','furnishing','hvac',.04,lambda:[box('方形空调外机',(0,0,.55),(1.0,.55,1.0),'cream',b=.04),box('矩形百叶',(0,-.30,.55),(.65,.03,.52),'dark',b=.008)])
component('pipe','furnishing','linear',.05,lambda:tube('变径管',[(-.45,0,0),(-.45,0,2.7),(-.25,0,5.8)],.07,'metal','SEA_Metal',6))
component('tree_trunk','plant','plant',.0,lambda:[tube('主树干',[(0,0,.2),(.3,.1,4),(-.15,.05,8),(0,0,12),(.4,.2,16),(.1,.1,20)],.38,'trunk',sides=7),tube('树枝',[(-.05,0,8),(-1.5,-.1,11),(-2.4,-.15,13)],.16,'trunk',sides=6),tube('树枝右',[(0,0,12),(1.3,-.1,15),(2.5,-.15,17)],.18,'trunk',sides=6)])
component('tree_crown','plant','plant',.0,lambda:[ico('树冠',p,s,'leaf2' if i%3==0 else 'leaf') for i,(p,s) in enumerate([((-2,0,13),(1.8,1.4,1.5)),((1.7,0,16),(2.2,1.6,1.8)),((-.4,.2,19),(2.4,1.7,1.5)),((2.1,.3,20),(1.6,1.3,1.4)),((-2,-.2,17),(1.5,1.2,1.2)),((0,0,10),(1.4,1.2,1.3))])])
component('planter','furnishing','container',-.04,lambda:[tapered('花盆',(0,0,.3),(1.0,.8,.6),-.04,'cream',b=.04),box('盆土',(0,0,.62),(.75,.58,.06),'wood',b=.01)])
component('flower_cluster','plant','plant',.0,lambda:[ico('花簇',(.25*i,.1*(i%2),.8+.15*i),(.18,.18,.22),'red' if i%3==0 else 'leaf2') for i in range(8)])
component('roof_equipment','furnishing','equipment',.03,lambda:[box('水箱',(2.1,1.8,.7),(1.0,.8,1.4),'metal','SEA_Metal',b=.04),box('设备箱',(-1.9,1.6,.45),(.8,.7,.9),'cream',b=.03),tube('短排气管',[(1.2,1.8,.8),(1.2,1.8,1.9)],.11,'metal','SEA_Metal',6)])
component('door','furnishing','door',.025,lambda:[box('底层入口门',(0,-3.25,1.35),(1.55,.12,2.5),'wood',b=.03),box('门玻璃',(0,-3.33,1.45),(1.05,.03,1.65),'glass','SEA_Gloss',.01)])
component('stair','furnishing','ladder',.03,lambda:[tube('外侧楼梯边',[(3.2,-3.4,0),(3.2,-3.4,20)],.07,'metal','SEA_Metal',6),tube('外侧楼梯边2',[(4.0,-3.4,0),(4.0,-3.4,20)],.07,'metal','SEA_Metal',6)]+[box('楼梯踏板',(3.6,-3.42,.5+2.8*i),(.9,.35,.08),'metal','SEA_Metal',b=.01) for i in range(7)])
# Layout: keep plants independent; multiple windows and balconies around facade.
put('deck',(0,0,0));put('shell',(0,0,0));
for z in [0,3,6,9,12,15,18]:put('slab',(0,0,z))
put('roof',(0,0,21));put('door',(0,-3.25,0))
for z in [1.5,4.5,7.5,10.5,13.5,16.5,19.5]:
    put('window',(-2.25,-3.25,z));put('window',(2.25,-3.25,z));put('balcony',(0,-3.25,z))
for z in [2,5,8,11,14,17]:put('ac_unit',(-4.45,1.7,z),rot=(0,math.pi/2,0));put('pipe',(-4.15,2.0,z))
put('solar_panel',(0,0,21));put('roof_equipment',(0,0,21));put('stair',(3.6,2.9,0),rot=(0,math.pi,0))
put('tree_trunk',(3.6,2.0,0));put('tree_crown',(3.6,2.0,0));
for p in [(-3.8,-2.5,0),(3.7,-2.5,0),(-3.8,1.5,6),(3.8,1.5,12)]:put('planter',p);put('flower_cluster',(p[0],p[1],p[2]+.62))
# display
current=top['display'];ground=box('展示地面',(0,0,-.2),(80,80,.2),'cream',b=0);ground['display_support']=True
world=bpy.data.worlds.new('WB002_World');world.use_nodes=True;next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.17,.27,.30,1);next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.5;sc.world=world
for nm,pos,energy in [('Key',(-14,-18,30),3000),('Fill',(14,-8,20),1800),('Rim',(0,12,26),2400)]:
 d=bpy.data.lights.new('WB002_'+nm,'AREA');d.energy=energy;d.shape='DISK';d.size=10;o=bpy.data.objects.new('WB002_'+nm,d);top['display'].objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,0,9))-o.location).to_track_quat('-Z','Y').to_euler()
camd=bpy.data.cameras.new('WB002_Camera');cam=bpy.data.objects.new('WB002_Camera',camd);top['display'].objects.link(cam);sc.camera=cam;camd.type='ORTHO';camd.ortho_scale=28;cam.location=(30,-35,28);cam.rotation_euler=(Vector((0,0,10))-cam.location).to_track_quat('-Z','Y').to_euler()
sc.render.engine='BLENDER_EEVEE_NEXT';sc.render.resolution_x=900;sc.render.resolution_y=1100;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.render.film_transparent=False
# plan + instances
plan={'schema':'sea.component_plan','version':'v001','status':'frozen_before_geometry','asset_id':'SEA-SCENE-WATER-BUILDING-002','display_number':'002','building_class':'above_water','water_layer':'surface','water_layer_role':'entity','palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png','reference_image':str(REF),'target_scene_triangles':[8500,11000],'components':[{'key':x['key'],'asset_id':x['asset_id'],'group':x['group'],'kind':x['kind'],'rho':x['rho'],'form_style':'SF-A_lowpoly','taper_along':'z','bottom':1.0,'top':.98,'component_source':x['component_source']} for x in catalog],'rules':['no_unnecessary_3d_lettering','upper_silhouette_preserved','solar_panels_preserved','tree_and_building_separate','square_lowpoly_hvac','lowpoly_target_about_10000']}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','godot_mapping':'(x,y,z)->(x,z,-y)'},'instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sc['asset_id']='SEA-SCENE-WATER-BUILDING-002';sc['source_version']='v001';sc['building_class']='above_water';sc['optimization']='lowpoly_about_10000';sc['reference_image']=str(REF)
bpy.ops.wm.save_as_mainfile(filepath=str(D/'water_building_002_v001.blend'),compress=True)
sc.render.filepath=str(W/'hero_002.png');bpy.ops.render.render(write_still=True)
print(json.dumps({'asset_id':'SEA-SCENE-WATER-BUILDING-002','components':len(catalog),'instances':len(layout),'master_triangles':sum(x['triangles'] for x in catalog),'expanded_triangles':sum(x['triangles']*sum(i['key']==x['key'] for i in layout) for x in catalog),'source':str(D/'water_building_002_v001.blend')},ensure_ascii=False),flush=True)
