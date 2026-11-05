"""Create v004 from immutable v003: global height cap, complete-storey removal, no scaling."""
import ast,bpy,bmesh,copy,hashlib,json,math,random
from array import array
from pathlib import Path
from mathutils import Euler,Matrix,Vector
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v003';D=OLD.parent/'v004';W=R.parent/'sea-work/sunken_city/v004'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];LOCK=json.loads((W/'scope_lock.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert bpy.app.background and P['status']=='frozen_before_geometry' and not (D/'sunken_city_v004.blend').exists()
assert all(sha(R/p)==h for p,h in LOCK['protected_sources'].items())
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunken_city_v003.blend'),load_ui=False,use_scripts=False)
bpy.context.preferences.filepaths.save_version=0
S=bpy.data.scenes['沉没旧城_完整参考布局_v003'];S.name='沉没旧城_完整参考布局_v004';bpy.context.window.scene=S
MATS=[bpy.data.materials[n] for n in ('SEA_Matte','SEA_Metal','SEA_Gloss')];CELLS={c['name']:c for c in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];CACHE={}
mod=ast.parse(Path(__file__).with_name('build.py').read_text(encoding='utf-8'));names=('box_template','Builder','text_shape','clip','tank','aircon','rail','building');keep=[n for n in mod.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
exec(compile(ast.Module(body=keep,type_ignores=[]),'v004_reuse_geometry_only','exec'),globals())
cap=P['height_cap_contract']['height_cap_m']
def signature(me):
    h=hashlib.sha256()
    for data,field,code,n in [(me.vertices,'co','f',3),(me.loops,'vertex_index','i',1),(me.polygons,'material_index','i',1),(me.uv_layers['PaletteUV'].data,'uv','f',2)]:
        buf=array(code,[0])*(len(data)*n);data.foreach_get(field,buf);h.update(buf.tobytes())
    return h.hexdigest()
def box(me):return [[f(v.co[i] for v in me.vertices) for i in range(3)] for f in (min,max)]
def recenter(me):
    lo,hi=box(me);shift=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
    for v in me.vertices:v.co-=shift
    me.update()
def clean(me):
    bm=bmesh.new();bm.from_mesh(me);seen=set();bad=[]
    for f in bm.faces:
        sig=tuple(sorted(tuple(round(a,4) for a in v.co) for v in f.verts))
        if sig in seen or f.calc_area()<1e-12:bad.append(f)
        else:seen.add(sig)
    if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
    bm.to_mesh(me);bm.free();me.update()
base={c['key']:signature(next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH').data) for c in CAT}
records=[]
for c in CAT:
    col=bpy.data.collections[c['collection']];o=next(o for o in col.objects if o.type=='MESH');before=box(o.data);changed=c['key'] in P['scope_lock']['changed_keys'];method='unchanged'
    if changed and c['key'] not in ('collapsed_residence','fallen_hall'):
        config=copy.deepcopy(c);accepted=None
        # Largest number of complete normal-height storeys fitting the global cap, roof services included.
        for n in range(min(c['floors'],2),0,-1):
            config['floors']=n;B=Builder();building(config)
            if c['style'] in ('tram','balcony','terrace','canal'):
                w,d,_=c['size_design_m'];x=-w*.38;yy=-d*.5-.2
                B.box((x,yy,9),(1.6,.6,3),'teal',.09);text_shape('SEA\nINN',(x,yy-.34,9.8),.65,'cream')
                for zz in (8,10):B.box((x,yy+.4,zz),(.15,1.2,.15),'steel',.025,1)
                B.tube([(w*.38,-d*.47,1),(w*.38,-d*.47,n*5.1-1),(w*.32,-d*.47,n*5.1-.5)],.1,'bark')
            z=[v[2] for v in B.v]
            if max(z)-min(z)<=cap+1e-6:accepted=B;break
        assert accepted is not None,c['key']
        oldname=o.name;oldprops=dict(o.items());bpy.data.objects.remove(o,do_unlink=True);o=accepted.finish(c['name'],col);o.name=oldname;o.parent=bpy.data.objects[c['root_object']]
        for k,v in oldprops.items():o[k]=v
        clean(o.data);recenter(o.data);c['source_floors']=c['floors'];c['floors']=n;method='complete_storey_removal_roof_rebuilt_no_scale'
    elif changed:
        # Preserve folded slabs and ground chunks; only protruding upper remnants fracture below cap.
        bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.get('PaletteUV');tag=bm.faces.layers.int.new('palette_cell')
        for f in bm.faces:
            t=f.loops[0][uv].uv;f[tag]=int(t.x*8)+8*int(t.y*8)
        result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,cap-.35),plane_no=(.008,-.005,1),clear_outer=True,clear_inner=False)
        edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
        if edges:
            fill=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
            for f in fill.get('faces',[]):f.material_index=0;f[tag]=next(iter(CELLS.values()))['column']+8*(7-next(iter(CELLS.values()))['row']);f.smooth=False
        for f in bm.faces:
            code=f[tag];cx=(code%8+.5)/8;cy=(code//8+.5)/8
            for j,l in enumerate(f.loops):a=math.tau*j/len(f.loops);l[uv].uv=(cx+.023*math.cos(a),cy+.023*math.sin(a))
        bm.to_mesh(o.data);bm.free();clean(o.data);recenter(o.data);method='fracture_only_high_remnants_preserve_folded_lower_chunks'
    lo,hi=box(o.data);o.data.calc_loop_triangles()
    if c['category']=='architecture':assert hi[2]-lo[2]<=cap+1e-4,c['key']
    if not changed:assert signature(o.data)==base[c['key']],c['key']+' protected changed'
    c.update(version='v004',bounds_size_m=[hi[i]-lo[i] for i in range(3)],triangles=len(o.data.loop_triangles),polygons=len(o.data.polygons),objects=[c['root_object'],o.name],material_roles=sorted({o.data.materials[f.material_index].name for f in o.data.polygons}),geometry_fingerprint=signature(o.data),source_blend_previous=c.get('component_blend'),component_blend=f'art_source/scenes/sunken_city/v004/component_packages/{c["key"]}/{c["key"]}.blend')
    c.pop('source_sha256',None)
    records.append(dict(key=c['key'],changed=changed,category=c['category'],height_before_m=before[1][2]-before[0][2],height_after_m=hi[2]-lo[2],method=method,signature_before=base[c['key']],signature_after=signature(o.data),floors=c.get('floors')))
# Keep each building's actual lowest contact at its previous level after changing its mesh.
bpy.context.view_layer.update();oldplacements={a['instance_id']:a for a in P['instances']};oldbounds=json.loads((R.parent/'sea-work/sunken_city/v003/probe_report.json').read_text(encoding='utf-8'))['instance_rows'];oldlow={a['name']:a['bounds'][0][2] for a in oldbounds};inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name);a=copy.deepcopy(oldplacements[o.name])
    if c['key'] in P['scope_lock']['changed_keys']:
        me=next(q.data for q in o.instance_collection.objects if q.type=='MESH');low=min((o.matrix_world@v.co).z for v in me.vertices);o.location.z+=oldlow[o.name]-low
    a['position_m']=list(o.location);inst.append(a)
P['instances']=inst
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
P['components']=[{**pc,'floors':next(c.get('floors') for c in CAT if c['key']==pc['key'])} if 'floors' in pc else pc for pc in P['components']]
for f,v in [('component_plan.json',P),('component_catalog.json',dict(schema='sea.component_catalog',components=CAT)),('component_instances.json',dict(schema='sea.component_instances',coordinate_contract=P['coordinate_contract'],terrain_contract=P['terrain_contract'],instances=inst))]:dump(D/f,v)
dump(W/'height_cap_verification.json',dict(passed=True,height_cap_contract=P['height_cap_contract'],components=records,unchanged_keys=P['scope_lock']['geometry_unchanged_keys'],original_sources_preserved=all(sha(R/p)==h for p,h in LOCK['protected_sources'].items()),instances=len(inst)))
# The unchanged terrain/rail has identical geometry and transforms; retain original measured seam proof.
for name in ('floor_seams.json','terrain_bridge_verification.json'):
    v=json.loads((R.parent/'sea-work/sunken_city/v003'/name).read_text(encoding='utf-8'));v.update(reused_geometry_scope='v003 terrain/rail exact geometry and local transform signatures unchanged; global lift owned by Godot root');dump(W/name,v)
for me in list(bpy.data.meshes):
    if me.users==0:bpy.data.meshes.remove(me)
for mat in list(bpy.data.materials):
    if mat.users==0:bpy.data.materials.remove(mat)
for img in list(bpy.data.images):
    if img.users==0 and img.name not in ('Render Result','Viewer Node'):bpy.data.images.remove(img)
S['plan_sha256']=sha(D/'component_plan.json');S.camera=bpy.data.objects['相机_坡地断桥_全景']
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunken_city_v004.blend'),compress=True,relative_remap=False)
oldman=json.loads((OLD/'asset_manifest.json').read_text(encoding='utf-8'));oldman.update(version='v004',name='沉没旧城_统一限高浅水版',source='art_source/scenes/sunken_city/v004/sunken_city_v004.blend',source_sha256=sha(D/'sunken_city_v004.blend'),runtime_integrated=False,source_verified=False,height_cap_contract=P['height_cap_contract']);dump(D/'asset_manifest.json',oldman)
assert all(sha(R/p)==h for p,h in LOCK['protected_sources'].items())
print('V004_SOURCE_SAVED',len(CAT),len(inst),'cap',cap,'changed',sum(r['changed'] for r in records),flush=True)
