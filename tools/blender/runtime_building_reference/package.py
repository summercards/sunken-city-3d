"""Package deduplicated v0.1 references; keep runtime geometry and source hashes."""
import bpy,json,hashlib,re,os,shutil
import numpy as np
from pathlib import Path
from collections import defaultdict
from mathutils import Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.1'
C=np.array([[1,0,0],[0,0,-1],[0,1,0]],float);C4=np.eye(4);C4[:3,:3]=C
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
old=json.loads((D/'catalog.json').read_text());recovery=json.loads((W/'background_recovery.json').read_text())
assert recovery['matched_instances']>240000 and len(recovery['templates'])==6
write(W/'spatial_candidate_catalog.json',old)
if (D/'background').exists():shutil.move(str(D/'background'),str(W/'spatial_candidates_not_delivered'))
bake=json.loads((R/'godot/assets/world/environment/bake.json').read_text());shared=json.loads((R/'godot/assets/baked/scene.json').read_text())
geo=np.fromfile(R/'godot/assets/baked/geoms.bin',dtype='<f4');idx=np.fromfile(R/'godot/assets/baked/geoms_idx.bin',dtype='<i4');inst=np.fromfile(R/'godot/assets/world/environment/instances.bin',dtype='<f4').reshape(-1,16)
matched={int(k):v for k,v in recovery['matched_instance_to_placement'].items()};matched_parts={int(k):v for k,v in recovery['matched_instance_to_part'].items()}
rows=[];mesh_cache={};mat_cache={};route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes']
def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True);mesh_cache.clear();mat_cache.clear()
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    bpy.context.preferences.filepaths.save_version=0
def stats():
    aa=[];tri=0;vc=0
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH':continue
        a=np.empty(len(ob.data.vertices)*3);ob.data.vertices.foreach_get('co',a);a=a.reshape(-1,3)
        a=a@np.array(ob.matrix_world)[:3,:3].T+np.array(ob.matrix_world)[:3,3];aa.append(a)
        ob.data.calc_loop_triangles();tri+=len(ob.data.loop_triangles);vc+=len(a)
    a=np.concatenate(aa);return dict(vertices=vc,triangles=tri,min=a.min(0).tolist(),max=a.max(0).tolist())
def mesh(gi):
    if gi in mesh_cache:return mesh_cache[gi]
    g=shared['geoms'][gi];n=g['vcount'];v=geo[g['pOff']:g['pOff']+n*3].reshape(-1,3)@C.T
    f=(idx[g['iOff']:g['iOff']+g['icount']] if g['icount'] else np.arange(n)).reshape(-1,3)
    me=bpy.data.meshes.new('RuntimeGeometry_'+str(gi));me.from_pydata(v.tolist(),[],f.tolist());me.update()
    li=np.empty(len(me.loops),dtype=np.int32);me.loops.foreach_get('vertex_index',li)
    if g['tOff']>=0:
        uv=geo[g['tOff']:g['tOff']+n*2].reshape(-1,2);me.uv_layers.new(name='RuntimeUV').data.foreach_set('uv',uv[li].ravel())
    col=geo[g['cOff']:g['cOff']+n*3].reshape(-1,3) if g['cOff']>=0 else np.ones((n,3))
    attr=me.color_attributes.new(name='RuntimeColor',type='FLOAT_COLOR',domain='POINT');attr.data.foreach_set('color',np.column_stack((col,np.ones(n))).ravel())
    if g['nOff']>=0:
        normals=geo[g['nOff']:g['nOff']+n*3].reshape(-1,3)@C.T
        me.normals_split_custom_set_from_vertices(normals.tolist())
    mesh_cache[gi]=me;return me
def material(b):
    key=(b['tex'],b['tint'],b['unlit'],b['alpha'],b['doubleSide'])
    if key in mat_cache:return mat_cache[key]
    m=bpy.data.materials.new('Runtime_'+str(key));m.use_nodes=True;m['godot_flags']=str(key);nt=m.node_tree;bs=nt.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.96
    vc=nt.nodes.new('ShaderNodeVertexColor');vc.layer_name='RuntimeColor';obj=nt.nodes.new('ShaderNodeObjectInfo');mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;nt.links.new(vc.outputs['Color'],mix.inputs[1]);nt.links.new(obj.outputs['Color'],mix.inputs[2]);out=mix.outputs[0]
    if b['tex']>=0:
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(R/'godot/assets/baked'/shared['textures'][b['tex']]),check_existing=True)
        blend=nt.nodes.new('ShaderNodeMixRGB');blend.blend_type='MULTIPLY';blend.inputs[0].default_value=1;nt.links.new(out,blend.inputs[1]);nt.links.new(tex.outputs['Color'],blend.inputs[2]);out=blend.outputs[0]
    nt.links.new(out,bs.inputs['Base Color'])
    if b['unlit']:nt.links.new(out,bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=1
    if b['alpha']:nt.links.new(obj.outputs['Alpha'],bs.inputs['Alpha'])
    mat_cache[key]=m;return m
def part(name,bi,ii,matrix):
    b=bake['batches'][bi];me=mesh(b['geom']);ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob)
    if not me.materials:me.materials.append(material(b))
    ob.material_slots[0].link='OBJECT';ob.material_slots[0].material=material(b)
    ob.color=tuple(float(v) for v in inst[ii,12:16]);ob.matrix_world=Matrix(C4@np.array(matrix)@C4.T)
    ob['source_geometry']=b['geom'];ob['source_batch']=bi;ob['source_instance']=ii
    return ob
def save(row):
    scene=bpy.context.scene;scene['reference_only']=True;scene['version']='0.1';scene['godot_water_level']=1.12
    scene['material_limitations']='Base textures/colors preserved; Godot water, toon lighting, depth tint, wind and gameplay states not reproduced.'
    col=bpy.data.collections.new(row['key']);scene.collection.children.link(col)
    objects=list(scene.objects)
    for ob in objects:
        for c in list(ob.users_collection):c.objects.unlink(ob)
        col.objects.link(ob)
    for c in list(bpy.data.collections):
        if c!=col and not c.objects and not c.children:bpy.data.collections.remove(c)
    if row['category']!='playable_surface':
        root=bpy.data.objects.new('REFERENCE_ROOT__KEEP_PIVOT',None);col.objects.link(root)
        for ob in objects:
            if ob.parent is None:ob.parent=root
    else:root=next(ob for ob in objects if ob.name.startswith('REFERENCE_ROOT'))
    root['runtime_origin_godot']=row.get('origin_godot',[0,0,0]);root['origin_godot']=row.get('origin_godot',[0,0,0]);root['category']=row['category'];root['version']='0.1'
    root['runtime_source']=row['runtime_source'];root['axis_mapping']='Godot(x,y,z) -> Blender(x,-z,y), metres'
    bpy.context.view_layer.update();row['metrics']=stats();row['collection']=col.name
    bb=row['metrics'];center=Vector([(a+b)/2 for a,b in zip(bb['min'],bb['max'])]);size=max(b-a for a,b in zip(bb['min'],bb['max']))
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active;space.clip_end=3000;space.region_3d.view_location=center;space.region_3d.view_distance=size*1.6;space.shading.type='MATERIAL'
    for txt in list(bpy.data.texts):bpy.data.texts.remove(txt)
    text=bpy.data.texts.new('READ_ME__替换参照.json');text.write(json.dumps(row,ensure_ascii=False,indent=2))
    bpy.ops.file.pack_all();p=D/row['relative_blend'];p.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
    row.update(source=str(p.relative_to(R)),source_sha256=sha(p),asset_ledger=route['ledger']+'#'+row['asset_id'])
    write(p.parent/'asset_manifest.json',row);rows.append(row);print('PACKAGED',row['key'],flush=True)
for row in old['items']:
    if row['category']!='playable_surface':continue
    bpy.ops.wm.open_mainfile(filepath=str(R/row['source']));bpy.context.preferences.filepaths.save_version=0
    src=(R/row['runtime_scene']).read_text();zt=re.search(r'transform = Transform3D\(([^)]+)\)',src);origin=[float(v) for v in zt[1].split(',')][9:]
    row['origin_zone_local_godot']=row['origin_godot'];row['zone_origin_godot']=origin;row['origin_godot']=[a+b for a,b in zip(row['origin_godot'],origin)]
    row['scope_label']='海面可玩区';save(row)
names=['阳台住宅楼','破顶围墙楼','阳台框架楼A','破损楼板楼','阶梯框架楼','阳台框架楼B']
for t in recovery['templates']:
    clean();s=t['source'];key=f'background_building_type_{s:02d}'
    for i,p in enumerate(t['parts']):part(f'Part_{i:04d}',p['batch'],p['instance'],p['matrix_local'])
    row=dict(key=key,asset_id='SEA-REF-01-BG-TYPE-'+str(s).zfill(2),name=names[s],version='0.1',category='background_building_component',scope_label='远景背景·楼体母版',boundary_status='recovered_repeated_template_matrix_verified',runtime_source='godot/assets/world/environment/bake.json',runtime_scene='godot/scenes/world/environment.tscn',runtime_node='StaticBatch',origin_godot=[0,0,0],relative_blend=f'background_components/{key}/{key}_v0.1.blend',source_type=s,part_count=len(t['parts']),placement_count=sum(p['source']==s for p in recovery['placements']),max_replay_matrix_error=recovery['max_matrix_error'])
    save(row)
# Unmatched geometry becomes normalized reusable component masters, never one
# file per placement. Color, transform and source batch remain instance data.
residual=defaultdict(list);payload={}
for row in old['items']:
    if row['category']=='playable_surface':continue
    for bi,ii in row['batch_instances']:
        if ii in matched:continue
        b=bake['batches'][bi];g=shared['geoms'][b['geom']]
        fingerprint=[]
        for name,n in [('pOff',3),('nOff',3),('tOff',2),('cOff',3)]:
            off=g[name];fingerprint.append(geo[off:off+g['vcount']*n].tobytes() if off>=0 else b'NONE')
        fingerprint.append(idx[g['iOff']:g['iOff']+g['icount']].tobytes() if g['icount'] else b'NO_INDEX')
        # Geometry + material role/texture. Per-instance tint is NOT a new asset.
        fingerprint.append(str((b['tex'],b['tint'],b['unlit'],b['alpha'],b['doubleSide'])).encode())
        h=hashlib.sha256(b''.join(fingerprint)).hexdigest();residual[h].append((bi,ii));payload[h]=(bi,ii)
detail_instances=[]
for n,(h,entries) in enumerate(sorted(residual.items())):
    clean();bi,ii=payload[h];key=f'background_part_{n:03d}';ob=part('Geometry',bi,ii,np.eye(4));ob.color=(1,1,1,1)
    row=dict(key=key,asset_id='SEA-REF-01-BG-PART-'+str(n).zfill(3),name=f'背景附属构件 {n:03d} / geometry {bake["batches"][bi]["geom"]}',version='0.1',category='background_detail_component',scope_label='远景背景·附属构件',boundary_status='exact_geometry_and_material_fingerprint',geometry_fingerprint=h,runtime_source='godot/assets/world/environment/bake.json',runtime_scene='godot/scenes/world/environment.tscn',runtime_node='StaticBatch',origin_godot=[0,0,0],relative_blend=f'background_components/{key}/{key}_v0.1.blend',placement_count=len(entries),instance_color_parameter=True,geometry_id=bake['batches'][bi]['geom'])
    save(row)
    for bi,ii in entries:
        raw=inst[ii];m=np.eye(4);m[:3]=raw[:12].reshape(3,4)
        detail_instances.append(dict(component=key,source_batch=bi,source_instance=ii,matrix_godot=m.tolist(),color_rgba=raw[12:16].tolist()))
building_instances=[]
for j,p in enumerate(recovery['placements']):
    members=[]
    for ii,pj in matched.items():
        if pj!=j:continue
        # Exact local matrix retained as correction: baseline replay has no drift.
        raw=inst[ii];m=np.eye(4);m[:3]=raw[:12].reshape(3,4);local=np.linalg.inv(np.array(p['matrix']))@m
        members.append(dict(part=matched_parts[ii],source_instance=ii,matrix_local_godot=local.tolist(),color_rgba=raw[12:16].tolist()))
    building_instances.append(dict(id=p['id'],component=f'background_building_type_{p["source"]:02d}',matrix_godot=p['matrix'],members=members,complete=len(members)==len(recovery['templates'][p['source']]['parts'])))
write(D/'background_instances.json',dict(version='0.1',axis='Godot Y-up, metres; Blender=(x,-z,y)',building_instances=building_instances,detail_instances=detail_instances,active_runtime_instances=len(matched)+len(detail_instances),exact_replay='Use member local matrices and colors; incomplete source instances occur at existing runtime zone boundaries.'))
write(D/'background_templates.json',dict(templates=recovery['templates'],source='current runtime bake; placement formulas only used as candidate locators'))
write(D/'catalog.json',dict(version='0.1',items=rows,input_hashes=old['input_hashes'],scope='five_surface_zones_and_background_components; underwater_regions_excluded',background_active_instances=len(matched)+len(detail_instances)))
print('PACKAGE_COMPLETE',len(rows),'assets;',len(residual),'detail component types',flush=True)
