"""02b: execute cleanup per component, persist optimized Blend, reopen, export stable GLB.
Source files and palette are immutable. No gameplay/scene writes. Run headless only.
"""
import bpy,bmesh,hashlib,json,math,os,struct
from collections import Counter,defaultdict
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];VERSION=os.environ.get('SEA_SUNKEN_VERSION','v003')
if VERSION not in {'v003','v004'}:raise ValueError('SEA_SUNKEN_VERSION 只支持 v003 或 v004')
D=R/'art_source/scenes/sunken_city'/VERSION;O=D/'export'/VERSION
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunken_city'/VERSION/'import'
RUN=R/'godot/assets/models/scenery/sunken_city'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
INST=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
MAIN=D/f'sunken_city_{VERSION}.blend';PAL=R/P['palette']
VERSION_CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
BUILDING_HEIGHT_LIMIT=max(c['bounds_size_m'][2] for c in VERSION_CAT if c.get('category')=='architecture')/4
assert len(CAT)==50 and len(INST)==388 and len({c['component_id'] for c in CAT})==50
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def limits(me):return [[f(v.co[i] for v in me.vertices) for i in range(3)] for f in (min,max)]
def tris(me):me.calc_loop_triangles();return len(me.loop_triangles)
def colors(me):
    uv=me.uv_layers['PaletteUV'];acc=defaultdict(float)
    for f in me.polygons:
        u=uv.data[f.loop_start].uv;acc[f'{f.material_index}:{int(u.x*8)}:{int(u.y*8)}']+=f.area
    return dict(acc)
def audit(me):
    uv=me.uv_layers.active;assert len(me.uv_layers)==1 and uv.name=='PaletteUV' and uv.active_render
    bad=0
    for f in me.polygons:
        ps=[uv.data[i].uv for i in f.loop_indices];cells={(int(p.x*8),int(p.y*8)) for p in ps}
        ar=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(ps,ps[1:]+ps[:1])))/2
        safe=all(.015625<(p.x%0.125)<.109375 and .015625<(p.y%0.125)<.109375 for p in ps)
        bad+=not(len(cells)==1 and ar>1e-7 and safe)
    assert not bad,'Invalid optimized palette UV'
    return len(me.polygons)
assert bpy.app.background
assert O.is_dir() and W.is_dir() and RUN.is_dir()
protected={str(p.relative_to(R)).replace('\\','/'):sha(p) for p in [MAIN,PAL]+[R/c['component_blend'] for c in CAT]}
for name in ('source','package','skill'):
    q=json.loads((W.parent/(name+'_verification.json')).read_text(encoding='utf-8'));assert q['passed'] is True
assert sha(MAIN)==json.loads((W.parent/'source_verification.json').read_text(encoding='utf-8'))['source_sha256']
records=[];failures=[]
for c in CAT:
    key=c['key'];source=R/c['component_blend'];assert sha(source)==c['source_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
    bpy.context.preferences.filepaths.save_version=0
    col=bpy.data.collections[c['collection']];objects=list(col.all_objects);obj=next(o for o in objects if o.type=='MESH')
    # Data mutation is made single-user only in this derived working session, never linked to source.
    obj.data=obj.data.copy();me=obj.data
    tb=tris(me);bb=limits(me);cb=colors(me)
    bm=bmesh.new();bm.from_mesh(me);uv=bm.loops.layers.uv.get('PaletteUV');tag=bm.faces.layers.int.new('sea_palette_cell')
    for f in bm.faces:
        u=f.loops[0][uv].uv;f[tag]=int(u.x*8)+8*int(u.y*8)
    ops={};vbefore=len(bm.verts);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);ops['weld_vertices_1e_minus6']=vbefore-len(bm.verts)
    seen=set();bad=[];zero=0;dup=0
    for f in bm.faces:
        signature=tuple(sorted(tuple(round(a,6) for a in v.co) for v in f.verts))
        if f.calc_area()<1e-12:bad.append(f);zero+=1
        elif signature in seen:bad.append(f);dup+=1
        else:seen.add(signature)
    if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
    ops['zero_area_faces_removed']=zero;ops['duplicate_faces_removed']=dup
    loose=[e for e in bm.edges if not e.link_faces];ops['loose_edges_removed']=len(loose)
    if loose:bmesh.ops.delete(bm,geom=loose,context='EDGES')
    loose=[v for v in bm.verts if not v.link_edges];ops['loose_vertices_removed']=len(loose)
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    # Do NOT dissolve rounded bevels. Restrict to truly coplanar flat faces of same role and palette cell.
    candidates=[]
    for e in bm.edges:
        if len(e.link_faces)!=2:continue
        a,b=e.link_faces
        if not a.smooth and not b.smooth and a.material_index==b.material_index and a[tag]==b[tag] and a.normal.dot(b.normal)>.99999999:
            candidates.append(e)
    oldfaces=len(bm.faces);oldedges=len(bm.edges)
    if candidates:bmesh.ops.dissolve_limit(bm,angle_limit=1e-6,verts=[],edges=candidates,delimit={'NORMAL','MATERIAL'})
    ops['flat_candidate_edges']=len(candidates);ops['coplanar_edges_removed']=oldedges-len(bm.edges);ops['coplanar_faces_reduced']=oldfaces-len(bm.faces)
    # Restore legal independent islands to every face, from retained per-face palette-cell identity.
    for f in bm.faces:
        code=f[tag];cx=(code%8+.5)/8;cy=(code//8+.5)/8
        for j,loop in enumerate(f.loops):
            a=math.tau*j/len(f.loops);loop[uv].uv=(cx+.023*math.cos(a),cy+.023*math.sin(a))
    bm.to_mesh(me);bm.free();me.update()
    ta=tris(me);ba=limits(me);ca=colors(me)
    assert all(abs(x-y)<=1e-4 for a,b in zip(bb,ba) for x,y in zip(a,b)),key+' bbox changed'
    # Duplicate internal surfaces may reduce measured area; never allow new colour area to appear.
    area_drift={k:abs(ca.get(k,0)-v)/max(1,v) for k,v in cb.items()}
    assert max(area_drift.values(),default=0)<.005,key+' color area changed '+str(area_drift)
    assert ta<=tb,key+' cleanup increased triangles'
    audited=audit(me)
    # Scene output wrapper remains explicit; previews are not exported.
    for preview in list(bpy.context.scene.objects):
        if preview.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(preview,do_unlink=True)
    root=next(o for o in col.all_objects if o.type=='EMPTY')
    root.name='Root_'+key
    obj.name='Mesh_'+key
    obj.data.name='Geometry_'+key
    bpy.context.scene.name='Component_'+key
    derived=O/(key+'_optimized.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(derived),compress=True,relative_remap=False)
    dh=sha(derived)
    bpy.ops.wm.open_mainfile(filepath=str(derived),load_ui=False,use_scripts=False)
    col=bpy.data.collections[c['collection']];obj=next(o for o in col.all_objects if o.type=='MESH');me=obj.data
    assert tris(me)==ta and audit(me)==audited and sha(derived)==dh
    bpy.ops.object.select_all(action='DESELECT')
    for o in col.all_objects:o.select_set(True)
    bpy.context.view_layer.objects.active=obj
    target=RUN/key/(key+'.glb');target.parent.mkdir(exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_image_format='NONE',export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,export_texcoords=True,export_normals=True,export_tangents=False,export_attributes=False,export_extras=True)
    raw=target.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);assert not doc.get('images') and not doc.get('textures')
    exported=sum(doc['accessors'][prim['indices']]['count']//3 for meshdoc in doc['meshes'] for prim in meshdoc['primitives'])
    assert exported==ta,(key,exported,ta)
    assert sha(source)==c['source_sha256'] and sha(MAIN)==protected[str(MAIN.relative_to(R)).replace('\\','/')]
    materials={i:m.get('name') for i,m in enumerate(doc.get('materials',[]))}
    mesh_nodes=[]
    for node in doc.get('nodes',[]):
        if 'mesh' in node:
            mesh_nodes.append({'node_name':node['name'],'mesh_index':node['mesh'],'roles':[materials[p['material']] for p in doc['meshes'][node['mesh']]['primitives']]})
    row=dict(key=key,asset_id=c['component_id'],role='optimized',version=VERSION,source=c['component_blend'],source_sha256_before=c['source_sha256'],source_sha256_after=sha(source),optimized_source=str(derived.relative_to(R)).replace('\\','/'),optimized_sha256=dh,
        glb=str(target.relative_to(R)).replace('\\','/'),glb_sha256=sha(target),glb_bytes=len(raw),triangles_before=tb,triangles_after=ta,reduction_ratio=(tb-ta)/tb,operations=ops,bounds_blender=ba,bounds_before=bb,palette_color_area_max_relative_drift=max(area_drift.values(),default=0),material_roles=c['material_roles'],mesh_nodes=mesh_nodes,
        budget=None,budget_source='no numeric runtime budget supplied; preserve approved shape and measure actual cost',retained_faces='All unknown/internal/back/bottom faces retained unless exact duplicates/zero-area; no normal-down deletion. All 3-segment rounded bevels retained. No blanket Decimate.',uv_faces_audited=audited,exported_triangles=exported,embedded_images=0,source_preserved=True,fidelity_status='geometry/color-area/bbox_pass_visual_comparison_pending')
    records.append(row)
    write(O/'export_manifest.json',{'suite':'sunken_city','version':VERSION,'passed':False,'stage':'component_export','protected_sources':protected,'components':records})
    print('SCITY_EXPORT',key,tb,ta,'saved_reopened',flush=True)
assert all(sha(R/p)==h for p,h in protected.items())
write(O/'export_manifest.json',{'suite':'sunken_city','version':VERSION,'passed':True,'stage':'exports_complete_fidelity_visual_pending','protected_sources':protected,'components':records,'triangles_before':sum(x['triangles_before'] for x in records),'triangles_after':sum(x['triangles_after'] for x in records),'source_unchanged':True})
print('SCITY_EXPORT_COMPLETE',len(records),'before',sum(x['triangles_before'] for x in records),'after',sum(x['triangles_after'] for x in records),flush=True)
