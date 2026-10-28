"""Reopen source and all packages, render four views, then export an optimized copy.

The new TSCN is initialized once; later hand edits are never regenerated without
an explicit --initialize-runtime flag. Source and public palette hashes are locked.
"""
import bpy, bmesh, json, hashlib, math, os, sys, struct
from pathlib import Path
from mathutils import Matrix, Vector, Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/reference_skiff/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'reference_skiff_v001';W.mkdir(parents=True,exist_ok=True)
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
INS=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
SRC=D/'reference_skiff.blend';checks=0;issues=[];reports=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def check(ok,msg):
    global checks
    checks+=1
    if not ok:issues.append(msg)
def validate(col):
    check(col.instance_offset.length<1e-8,col.name+' offset');faces=0;triangles=0
    for o in col.all_objects:
        check(o.type=='MESH',o.name+' mesh only')
        if o.type!='MESH':continue
        check(all(abs(o.matrix_world[r][c]-(1 if r==c else 0))<1e-7 for r in range(4) for c in range(4)),o.name+' identity')
        me=o.data;check(len(me.vertices)>0 and len(me.polygons)>0,o.name+' nonempty')
        check(me.uv_layers.active.name=='PaletteUV' and me.uv_layers.active.active_render,o.name+' active PaletteUV')
        check(all(m.name in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'} for m in me.materials),o.name+' material roles')
        for m in me.materials:
            imgs=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE'];check(len(imgs)==1,m.name+' one palette')
            for n in imgs:
                check(not n.image.packed_file and Path(bpy.path.abspath(n.image.filepath)).resolve()==(R/P['palette']).resolve(),m.name+' external unique palette')
                check(n.interpolation=='Closest',m.name+' nearest')
                check(any(n.type=='UVMAP' and n.uv_map=='PaletteUV' for n in m.node_tree.nodes),m.name+' explicit UV node')
        uv=me.uv_layers.active.data
        for f in me.polygons:
            pts=[uv[i].uv.copy() for i in f.loop_indices];cells={(int(v.x*8),int(v.y*8)) for v in pts}
            area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(pts,pts[1:]+pts[:1])))*.5
            check(area>1e-8,o.name+' UV area')
            check(len(cells)==1,o.name+' UV single cell')
            check(all(min((v.x*512)%64,64-(v.x*512)%64,(v.y*512)%64,64-(v.y*512)%64)>=8-1e-4 for v in pts),o.name+' 8px margin')
        me.calc_loop_triangles();faces+=len(me.polygons);triangles+=len(me.loop_triangles)
    return {'faces':faces,'triangles':triangles}
source_hash=sha(SRC);palette_hash=sha(R/P['palette'])
bpy.ops.wm.open_mainfile(filepath=str(SRC));bpy.context.preferences.filepaths.save_version=0
scene=bpy.data.scenes['黄白木船_参考装配'];bpy.context.window.scene=scene
check(len([o for o in scene.objects if o.instance_type=='COLLECTION'])==len(INS),'instance count')
bykey={}
for e in CAT:
    stats=validate(bpy.data.collections[e['collection']]);bykey[e['key']]=stats
    check(sum(i['key']==e['key'] for i in INS)==e['instance_count'],e['key']+' reuse')
    check(e['bounds']['min'][2]==0 or abs(e['bounds']['min'][2])<1e-6,e['key']+' bottom origin')
    check(abs(e['bounds']['min'][0]+e['bounds']['max'][0])<1e-6 and abs(e['bounds']['min'][1]+e['bounds']['max'][1])<1e-6,e['key']+' centered origin')
# Actual evaluated dependency graph including every visible collection instance.
dg=bpy.context.evaluated_depsgraph_get();expanded_faces=0;expanded_triangles=0
for inst in dg.object_instances:
    ob=inst.object
    if ob.type!='MESH':continue
    me=ob.to_mesh();me.calc_loop_triangles();expanded_faces+=len(me.polygons);expanded_triangles+=len(me.loop_triangles);ob.to_mesh_clear()
check(expanded_triangles==sum(bykey[i['key']]['triangles'] for i in INS),'evaluated instance triangle total')
check(len(CAT)<=50,'component budget')
if '--render' in sys.argv:
    cam=scene.camera;target=Vector((0,0,.25));preview=W/'previews';preview.mkdir(exist_ok=True)
    views=[('reference',(8,-10,11),9.3),('close',(-7,-8,9),7.9),('top',(0,-.01,15),8.8),('hull_only',(7,-9,7),7.2)]
    for label,loc,scale in views:
        for o in scene.objects:
            if o.instance_type=='COLLECTION':o.hide_render=label=='hull_only' and not o.name.startswith(('hull_','gunwale_','floor_board','bench','rib_'))
        cam.location=loc;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
        scene.render.filepath=str(preview/(label+'.png'));bpy.ops.render.render(write_still=True)
for e in CAT:
    path=D/'component_packages'/e['key']/(e['key']+'.blend');bpy.ops.wm.open_mainfile(filepath=str(path))
    col=bpy.data.collections[e['collection']];stats=validate(col)
    check(stats==bykey[e['key']],e['key']+' package geometry equals master');reports.append(dict(key=e['key'],source_sha256=sha(path),**stats))
report=dict(checks=checks,issues=issues,passed=not issues,source_sha256=source_hash,palette_sha256=palette_hash,components=reports,expanded_faces=expanded_faces,expanded_triangles=expanded_triangles,rendered_views=['reference','close','top','hull_only'] if '--render' in sys.argv else [],godot_validation='pending')
write(W/'source_validation.json',report)
if issues:raise RuntimeError('Source validation failed: '+str(issues[:12]))
# Save a separate optimization file before exporting. Never mutate art master.
bpy.ops.wm.open_mainfile(filepath=str(SRC));bpy.context.preferences.filepaths.save_version=0
export_scene=bpy.data.scenes.new('小船_独立优化组件');bpy.context.window.scene=export_scene
for e in CAT:
    col=bpy.data.collections.new('EXPORT_'+e['key']);export_scene.collection.children.link(col)
    for src in list(bpy.data.collections[e['collection']].all_objects):
        ob=src.copy();ob.data=src.data.copy();col.objects.link(ob)
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
        bad=[f for f in bm.faces if f.calc_area()<1e-12]
        if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
        bm.to_mesh(ob.data);bm.free();ob.data.update()
for sc in list(bpy.data.scenes):
    if sc!=export_scene:bpy.data.scenes.remove(sc)
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
optimized=D/'export/v001/reference_skiff_optimized.blend';optimized.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(optimized),compress=True);bpy.ops.wm.open_mainfile(filepath=str(optimized))
OUT=R/'godot/assets/models/boats/reference_skiff';exported=[]
for e in CAT:
    bpy.ops.object.select_all(action='DESELECT');col=bpy.data.collections['EXPORT_'+e['key']]
    for o in col.all_objects:o.select_set(True)
    bpy.context.view_layer.objects.active=next(iter(col.all_objects))
    p=OUT/'components'/e['key']/(e['key']+'.glb');p.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_texcoords=True,export_normals=True,export_cameras=False,export_lights=False,export_extras=True)
    raw=p.read_bytes();n,t=struct.unpack_from('<II',raw,12);g=json.loads(raw[20:20+n]);check(not g.get('images') and not g.get('textures'),e['key']+' no palette copy')
    e['runtime_path']=p.relative_to(R).as_posix();e['runtime_sha256']=sha(p);e['exported_triangles']=sum(g['accessors'][s['indices']]['count']//3 for m in g['meshes'] for s in m['primitives'])
    exported.append(e)
check(sha(SRC)==source_hash and sha(R/P['palette'])==palette_hash,'protected source/palette')
check(all(sha(R/p)==h for p,h in P['legacy_sha256'].items()),'protected old bake')
report.update(checks=checks,issues=issues,passed=not issues,optimized_source=optimized.relative_to(R).as_posix(),optimized_sha256=sha(optimized),exported_triangles=sum(next(e['exported_triangles'] for e in CAT if e['key']==i['key']) for i in INS))
write(W/'source_validation.json',report);write(D/'export_manifest.json',dict(source=SRC.relative_to(R).as_posix(),source_sha256=source_hash,optimized_source=optimized.relative_to(R).as_posix(),optimized_sha256=sha(optimized),palette_sha256=palette_hash,components=exported,validation_report=(W/'source_validation.json').as_posix()))
for e in exported:
    p=D/'component_packages'/e['key']/'asset_manifest.json';m=json.loads(p.read_text(encoding='utf-8'));m.update(stage='source_verified_exported_pending_godot',runtime_path=e['runtime_path'],runtime_sha256=e['runtime_sha256'],source_validation=dict(passed=not issues,checks=checks,evidence=(W/'source_validation.json').as_posix()));write(p,m)
print('SKIFF_VERIFIED_EXPORTED',checks,'checks',len(issues),'issues',expanded_faces,'faces',expanded_triangles,'triangles',flush=True)
