"""Reopen/validate sources, save independent packages and optimized derivative, export per building."""
import bpy,bmesh,hashlib,json,math,os,struct
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/submerged_neighborhood/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'submerged_neighborhood_v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));C=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
SOURCE=D/'submerged_neighborhood.blend';OPT=D/'export/v001/submerged_neighborhood_optimized.blend'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def check_mesh(o):
    assert o.matrix_world==o.matrix_world.Identity(4) and len(o.modifiers)==0
    me=o.data;me.calc_loop_triangles();assert 0<len(me.loop_triangles)<=1000
    assert me.uv_layers.active.name=='PaletteUV' and me.uv_layers['PaletteUV'].active_render
    uv=me.uv_layers.active.data
    for f in me.polygons:
        q=[uv[li].uv for li in f.loop_indices];cell={(int(p.x*8),int(p.y*8)) for p in q};assert len(cell)==1
        assert abs(sum(q[j].x*q[(j+1)%len(q)].y-q[(j+1)%len(q)].x*q[j].y for j in range(len(q))))>1e-9
        for p in q:assert .015625-1e-6< p.x% .125 <.109375+1e-6 and .015625-1e-6<p.y%.125<.109375+1e-6
    for m in me.materials:
        tex=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE');assert tex.interpolation=='Closest' and not tex.image.packed_file
        assert Path(bpy.path.abspath(tex.image.filepath)).resolve()==(R/P['palette']).resolve()
    return len(me.loop_triangles)
def render_sheets(prefix):
    S=bpy.data.scenes['水下街区_参考布局'];bpy.context.window.scene=S;ST=bpy.data.collections['展示支持_不导出']
    for o in bpy.data.collections['参考布局_建筑实例'].objects:o.hide_render=True
    sheet=[]
    for idx,i in enumerate(C):
        ob=bpy.data.objects.new('独立展示_'+i['key'],None);ST.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=bpy.data.collections[i['asset_id']]
        ob.location=((idx%3)*13-13,(idx//3)*15-8,0);sheet.append(ob)
    S.cycles.samples=8;S.render.resolution_x=1000;S.render.resolution_y=850
    for tag,pos,target,scale in [('front',(37,-58,41),(0,0,8),50),('back',(-38,52,35),(0,0,8),50),('side',(60,4,29),(0,0,8),48),('top',(12,-25,85),(0,0,5),53)]:
        cam=S.camera;cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
        S.render.filepath=str(W/(prefix+'-'+tag+'.png'));bpy.ops.render.render(write_still=True)
    for o in sheet:bpy.data.objects.remove(o,do_unlink=True)
    for o in bpy.data.collections['参考布局_建筑实例'].objects:o.hide_render=False
bpy.context.preferences.filepaths.save_version=0
protected={str(SOURCE):sha(SOURCE),str(R/P['palette']):sha(R/P['palette'])}
rows=[]
for i in C:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    col=bpy.data.collections[i['asset_id']];assert tuple(col.instance_offset)==(0,0,0)
    o=next(iter(col.objects));check_mesh(o)
    pkg=D/'component_packages'/i['key'];pkg.mkdir(parents=True,exist_ok=True)
    sc=bpy.data.scenes.new(i['name']);sc.collection.children.link(col);sc.unit_settings.system='METRIC';bpy.context.window.scene=sc
    for other in list(bpy.data.scenes):
        if other!=sc:bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
    path=pkg/(i['key']+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(path));check_mesh(bpy.data.objects[i['key']])
    write(pkg/'asset_manifest.json',dict(asset_id=i['asset_id'],name=i['name'],source=path.relative_to(R).as_posix(),source_sha256=sha(path),
        version='v001',stage='source_verified_export_pending',category='underwater_scenic_building',triangles=i['triangles'],polygons=i['polygons'],triangle_budget=1000,license=P['reference_license']))
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));render_sheets('source')
# Actual cleanup is confined to a new persistent derivative.
for i in C:
    o=bpy.data.objects[i['key']];before=check_mesh(o);bm=bmesh.new();bm.from_mesh(o.data)
    v0=len(bm.verts);f0=len(bm.faces)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.0000001)
    loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()
    after=check_mesh(o)
    rows.append(dict(i,source=SOURCE.relative_to(R).as_posix(),source_sha256_before=protected[str(SOURCE)],
        optimized_source=OPT.relative_to(R).as_posix(),triangles_before=before,triangles_after=after,
        reduction_ratio=(before-after)/before,operations=['merge duplicate vertices at 1e-6 m','dissolve degenerate edges at 1e-7 m','remove isolated vertices','recalculate outward normals'],
        vertices_before=v0,vertices_after=len(o.data.vertices),faces_before=f0,faces_after=len(o.data.polygons),
        preserved_faces='Bottom/back/slab undersides retained: visible from arbitrary underwater camera. Flat window panels and trim boundaries retained for palette and silhouette fidelity. No unproven hidden-face deletion.',
        zero_reduction_reason='Purpose-built low-poly silhouettes already fit budget; cleanup may weld vertices without changing triangles. Triangulation is not claimed as reduction.'))
OPT.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(OPT),compress=True)
bpy.ops.wm.open_mainfile(filepath=str(OPT));render_sheets('optimized')
for row in rows:
    k=row['key'];bpy.context.window.scene=bpy.data.scenes['独立建筑母版'];bpy.ops.object.select_all(action='DESELECT')
    o=bpy.data.objects[k];o.select_set(True);bpy.context.view_layer.objects.active=o;check_mesh(o)
    target=R/'godot/assets/models/scenery/submerged_neighborhood'/k/(k+'.glb');target.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,
        export_image_format='NONE',export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
    data=target.read_bytes();jslen=struct.unpack_from('<I',data,12)[0];gl=json.loads(data[20:20+jslen]);assert not gl.get('images') and not gl.get('textures')
    count=sum(gl['accessors'][p['indices']]['count']//3 for me in gl['meshes'] for p in me['primitives'])
    assert count==row['triangles_after'] and count<=1000
    row.update(runtime_path=target.relative_to(R).as_posix(),runtime_sha256=sha(target),exported_triangles=count,
        optimized_sha256=sha(OPT),source_sha256_after=sha(SOURCE),geometry_fingerprint=hashlib.sha256(str([list(v.co) for v in o.data.vertices]).encode()+str([list(f.vertices) for f in o.data.polygons]).encode()).hexdigest())
assert all(sha(Path(p))==h for p,h in protected.items())
write(D/'export_manifest.json',dict(source=SOURCE.relative_to(R).as_posix(),source_sha256=sha(SOURCE),optimized_source=OPT.relative_to(R).as_posix(),optimized_sha256=sha(OPT),
    protected_sources_unchanged=True,components=rows,palette=P['palette'],palette_sha256=sha(R/P['palette']),
    fidelity='Identical fixed front/back/side/top source and optimized renders; inspect images before integration',source_validation='6 independent packages reopened; each face UV area/cell margin, texture path, identity transforms, triangle budget validated'))
print('EXPORTED_6_BUILDINGS',[(r['key'],r['exported_triangles']) for r in rows],flush=True)
