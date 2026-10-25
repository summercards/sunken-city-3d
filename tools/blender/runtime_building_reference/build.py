"""Read-only runtime -> Blender v0.1 reference snapshots. Run with Blender --background.

This is not a game builder: it never writes godot/. Legacy merged units remain
merged; inferred background boundaries are explicitly recorded, never certified.
"""
import bpy, json, hashlib, re, os, math
from pathlib import Path
from collections import defaultdict, Counter
import numpy as np
from mathutils import Vector, Matrix, Quaternion

R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/runtime_building_reference/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.1'
C=np.array([[1,0,0],[0,0,-1],[0,1,0]],dtype=float)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1
def stats():
    verts=[];tri=0;vc=0
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        a=np.empty(len(o.data.vertices)*3);o.data.vertices.foreach_get('co',a);a=a.reshape(-1,3)
        a=a@np.array(o.matrix_world)[:3,:3].T+np.array(o.matrix_world)[:3,3]
        verts.append(a);o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles);vc+=len(a)
    a=np.concatenate(verts)
    return dict(vertices=vc,triangles=tri,bounds_blender_local=dict(min=a.min(0).tolist(),max=a.max(0).tolist()))
def frame(bounds):
    center=Vector([(a+b)/2 for a,b in zip(bounds['min'],bounds['max'])]);size=max(b-a for a,b in zip(bounds['min'],bounds['max']))
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_location=center
                area.spaces.active.region_3d.view_distance=size*1.65
                area.spaces.active.region_3d.view_rotation=Quaternion((0.88,0.28,0.12,0.34)).normalized()
                area.spaces.active.clip_end=3000
                area.spaces.active.shading.type='MATERIAL'
def save(row):
    root=bpy.data.objects.new('REFERENCE_ROOT__KEEP_PIVOT',None);bpy.context.scene.collection.objects.link(root)
    for o in list(bpy.context.scene.objects):
        if o!=root and o.parent is None:o.parent=root
    root['version']='0.1';root['runtime_origin_godot']=row['origin_godot'];root['category']=row['category']
    root['boundary_status']=row['boundary_status'];root['runtime_source']=row['runtime_source']
    root['axis_mapping']='Godot(x,y,z) -> Blender(x,-z,y); metres'
    bpy.context.scene['reference_only']=True
    bpy.context.scene['runtime_water_level_godot']=1.12
    bpy.context.scene['material_limitations']='Base geometry, vertex colors and textures preserved. Godot toon, depth tint, lighting and dynamic gameplay not reproduced.'
    row['metrics']=stats();frame(row['metrics']['bounds_blender_local'])
    text=bpy.data.texts.new('READ_ME__替换参照.json');text.write(json.dumps(row,ensure_ascii=False,indent=2))
    # Self-contained legacy textures: these are not newly authored PaletteUV assets.
    bpy.ops.file.pack_all()
    p=D/row['relative_blend'];p.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
    row['source']=str(p.relative_to(R));row['source_sha256']=sha(p)
    write(p.parent/'asset_manifest.json',row)
    print('SAVED',row['key'],row['metrics']['triangles'],flush=True)

D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
assert not (D/'catalog.json').exists(),'Frozen baseline exists; use a new version'
inputs={}
def track(p): inputs[str(p.relative_to(R))]=sha(p)
rows=[]
for mp in sorted((R/'godot/assets/models/zones').glob('*/manifest.json')):
    region=mp.parent.name;scene=R/f'godot/scenes/zones/{region}.tscn';source=scene.read_text();track(scene);track(mp)
    manifest=json.loads(mp.read_text())
    zt=re.search(r'transform = Transform3D\(([^)]+)\)',source)
    zone_origin=[float(x.strip()) for x in zt[1].split(',')][9:]
    for u in manifest['units']:
        glb=mp.parent/u['file'];res='res://'+str(glb.relative_to(R/'godot'))
        if res not in source:continue
        match=re.search(r'\[node name="'+re.escape(u['id'])+r'" parent="Models"[^\]]*\]\s*transform = Transform3D\(([^)]+)\)',source)
        assert match, (scene,u['id'])
        vals=[float(x.strip()) for x in match[1].split(',')];assert vals[:9]==[1,0,0,0,1,0,0,0,1]
        track(glb);key=region+'__'+u['id']
        rows.append(dict(key=key,asset_id='SEA-REF-01-'+key.upper().replace('_','-'),version='0.1',category='playable_surface',name=region+' / '+u.get('label',u['id']),boundary_status='existing_runtime_unit_may_contain_multiple_structures',runtime_source=str(glb.relative_to(R)),runtime_sha256=sha(glb),runtime_scene=str(scene.relative_to(R)),runtime_node='Models/'+u['id'],origin_godot=[a+b for a,b in zip(vals[9:],zone_origin)],origin_zone_local_godot=vals[9:],zone_origin_godot=zone_origin,relative_blend=f'playable/{region}/{u["id"]}/{key}_v0.1.blend',material_slots=u['slots']))

# Read the ACTUAL environment batch consumed by the game (not a newly generated web scene).
bp=R/'godot/assets/world/environment/bake.json';ip=bp.with_name('instances.bin')
sp=R/'godot/assets/baked/scene.json';gp=sp.with_name('geoms.bin');ixp=sp.with_name('geoms_idx.bin')
for p in [bp,ip,sp,gp,ixp,R/'godot/scenes/world/environment.tscn']:track(p)
bake=json.loads(bp.read_text());shared=json.loads(sp.read_text())
inst=np.fromfile(ip,dtype='<f4').reshape(-1,16);geo=np.fromfile(gp,dtype='<f4');idx=np.fromfile(ixp,dtype='<i4')
gcache={};gsize={}
for gi,g in enumerate(shared['geoms']):
    n=g['vcount'];v=geo[g['pOff']:g['pOff']+n*3].reshape(-1,3).astype(float)
    gsize[gi]=np.ptp(v,axis=0)
    faces=(idx[g['iOff']:g['iOff']+g['icount']] if g['icount'] else np.arange(n)).reshape(-1,3)
    uv=geo[g['tOff']:g['tOff']+n*2].reshape(-1,2) if g['tOff']>=0 else np.zeros((n,2))
    col=geo[g['cOff']:g['cOff']+n*3].reshape(-1,3) if g['cOff']>=0 else np.ones((n,3))
    gcache[gi]=(v,faces,uv,col)
retired={749,750,751,753,754,756,757,758};items=[];seeds=[];candidates=Counter()
for bi,b in enumerate(bake['batches']):
    if b['geom'] in retired or (b['alpha'] and b['geom']==747):continue
    for k in range(b['count']):
        ii=b['instOff']+k;m=inst[ii];basis=m[:12].reshape(3,4)[:,:3]
        size=np.abs(basis)@gsize[b['geom']];scale=np.linalg.norm(basis,axis=0)*gsize[b['geom']]
        x,z=float(m[3]),float(m[11]);items.append((bi,ii))
        # Outer-city authoring provides a uniquely sized footing for each building.
        if np.allclose(scale,[8.6,11,8.4],atol=.002) and abs(float(m[7])+3)<.002:seeds.append((x,z,'footing'))
        elif min(size[0],size[2])>2.8 and max(size[0],size[2])<25:candidates[(round(x,1),round(z,1))]+=1
for (x,z),n in candidates.most_common():
    if n<3:continue
    if all((x-a)**2+(z-b)**2>64 for a,b,_ in seeds):seeds.append((x,z,'repeated_slab_inferred'))
seeds.sort(key=lambda s:(round(s[1],2),round(s[0],2)))
anchors=np.array([s[:2] for s in seeds]);groups=defaultdict(list)
for bi,ii in items:
    x,z=float(inst[ii,3]),float(inst[ii,11]);ds=((anchors-[x,z])**2).sum(1);j=int(ds.argmin())
    key=f'building_{j:04d}' if ds[j]<18**2 else f'context_{math.floor(x/48):+04d}_{math.floor(z/48):+04d}'
    groups[key].append((bi,ii))
for key,entries in sorted(groups.items()):
    if key.startswith('building'):
        j=int(key.split('_')[1]);x,z,kind=seeds[j];origin=[x,0,z]
    else:
        a=inst[[i for b,i in entries]][:,[3,7,11]];origin=[float(a[:,0].mean()),0,float(a[:,2].mean())];kind='context'
    rows.append(dict(key='background__'+key,asset_id='SEA-REF-01-BG-'+key.upper().replace('_','-').replace('+','P'),version='0.1',category='background_context' if kind=='context' else 'background_building',name='远景背景 / '+key,boundary_status='spatial_assignment_review_required',anchor_evidence=kind,runtime_source=str(bp.relative_to(R)),runtime_scene='godot/scenes/world/environment.tscn',runtime_node='StaticBatch',origin_godot=origin,relative_blend=f'background/{key}/{key}_v0.1.blend',batch_instances=entries))
write(D/'export_plan.json',dict(version='0.1',scope='five_surface_zones_and_environment_no_independent_underwater_regions',policy='Immutable runtime references, not newly authored component masters. Preserve source geometry/materials. Background spatial boundaries need review before replacement.',items=rows,input_hashes=inputs,environment_active_instances=len(items),environment_partitioned_instances=sum(len(x) for x in groups.values())))
print('PLAN',len(rows),'files;',len(seeds),'background anchors',flush=True)

def background(row):
    mats={};by=defaultdict(list)
    for bi,ii in row['batch_instances']:
        b=bake['batches'][bi];key=(b['tex'],b['tint'],b['unlit'],b['alpha'],b['doubleSide']);by[key].append((b['geom'],ii))
    for slot,entries in by.items():
        pp=[];ff=[];uu=[];cc=[];offset=0
        for gi,ii in entries:
            v,f,uv,col=gcache[gi];m=inst[ii];basis=m[:12].reshape(3,4)[:,:3]
            pos=(v@basis.T+m[[3,7,11]]-row['origin_godot'])@C.T
            pp.append(pos);ff.append(f+offset);uu.append(uv);cc.append(col*m[12:15]);offset+=len(v)
        p=np.concatenate(pp);f=np.concatenate(ff);uv=np.concatenate(uu);colors=np.concatenate(cc)
        me=bpy.data.meshes.new('Runtime_geometry');me.from_pydata(p.tolist(),[],f.tolist());me.update()
        ob=bpy.data.objects.new('Batch_'+str(len(mats)),me);bpy.context.scene.collection.objects.link(ob)
        loops=np.empty(len(me.loops),dtype=np.int32);me.loops.foreach_get('vertex_index',loops)
        layer=me.uv_layers.new(name='RuntimeUV');layer.data.foreach_set('uv',uv[loops].ravel())
        attr=me.color_attributes.new(name='RuntimeColor',type='FLOAT_COLOR',domain='POINT');rgba=np.column_stack((colors,np.ones(len(colors))));attr.data.foreach_set('color',rgba.ravel())
        mat=bpy.data.materials.new('Runtime_'+str(slot));mat.use_nodes=True;mat['godot_batch_slot']=str(slot)
        nt=mat.node_tree;bs=nt.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.96
        color=nt.nodes.new('ShaderNodeVertexColor');color.layer_name='RuntimeColor';output=color.outputs['Color']
        if slot[0]>=0:
            tex=nt.nodes.new('ShaderNodeTexImage');tp=sp.parent/shared['textures'][slot[0]];track(tp);tex.image=bpy.data.images.load(str(tp),check_existing=True)
            mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;nt.links.new(output,mix.inputs[1]);nt.links.new(tex.outputs['Color'],mix.inputs[2]);output=mix.outputs[0]
        nt.links.new(output,bs.inputs['Base Color'])
        if slot[2]:nt.links.new(output,bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=1
        me.materials.append(mat);mats[slot]=mat

for row in rows:
    clean()
    if row['category']=='playable_surface':bpy.ops.import_scene.gltf(filepath=str(R/row['runtime_source']))
    else:background(row)
    save(row)
write(D/'catalog.json',dict(version='0.1',items=rows,input_hashes=inputs))
print('EXPORT_COMPLETE',len(rows),flush=True)
