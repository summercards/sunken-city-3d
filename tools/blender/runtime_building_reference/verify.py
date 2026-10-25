"""Reopen each reference, verify source parity and exact background replay."""
import bpy,json,hashlib,os,re,struct,gzip,shutil
import numpy as np
from pathlib import Path
from mathutils import Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.1'
C=np.array([[1,0,0],[0,0,-1],[0,1,0]],float)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
cat=json.loads((D/'catalog.json').read_text());checks=[];errors=[]
for row in cat['items']:
    p=R/row['source'];bpy.ops.wm.open_mainfile(filepath=str(p));bpy.context.preferences.filepaths.save_version=0
    root=next(o for o in bpy.context.scene.objects if o.name.startswith('REFERENCE_ROOT'))
    aa=[];tri=0;vc=0;edges=0
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH':continue
        a=np.empty(len(ob.data.vertices)*3);ob.data.vertices.foreach_get('co',a);a=a.reshape(-1,3);m=np.array(ob.matrix_world);aa.append(a@m[:3,:3].T+m[:3,3])
        ob.data.calc_loop_triangles();tri+=len(ob.data.loop_triangles);vc+=len(a);edges+=len(ob.data.edges)
    a=np.concatenate(aa);lo=a.min(0);hi=a.max(0);err=max(np.max(abs(lo-row['metrics']['min'])),np.max(abs(hi-row['metrics']['max'])))
    assert tri==row['metrics']['triangles'] and vc==row['metrics']['vertices'] and err<.00001,row['key']
    assert row['collection'] in bpy.data.collections
    for im in bpy.data.images:
        if im.source=='FILE':assert im.packed_file or Path(bpy.path.abspath(im.filepath)).is_file(),im.name
    if row['category']=='playable_surface':
        f=open(R/row['runtime_source'],'rb');f.read(12);n,t=struct.unpack('<II',f.read(8));g=json.loads(f.read(n));n,t=struct.unpack('<II',f.read(8));blob=f.read(n);f.close()
        bounds=[];expected_tri=0;degenerate_tri=0
        for mesh in g['meshes']:
            for prim in mesh['primitives']:
                ac=g['accessors'][prim['attributes']['POSITION']];bounds.extend([ac['min'],ac['max']])
                if prim.get('mode',4)==4:
                    ia=g['accessors'][prim['indices']];iv=g['bufferViews'][ia['bufferView']]
                    dtype={5121:'u1',5123:'<u2',5125:'<u4'}[ia['componentType']]
                    indices=np.frombuffer(blob,dtype=dtype,count=ia['count'],offset=iv.get('byteOffset',0)+ia.get('byteOffset',0)).reshape(-1,3)
                    expected_tri+=len(indices)
                    degenerate_tri+=int(np.sum((indices[:,0]==indices[:,1])|(indices[:,0]==indices[:,2])|(indices[:,1]==indices[:,2])))
        b=np.array(bounds)@C.T;runtime_err=max(np.max(abs(b.min(0)-lo)),np.max(abs(b.max(0)-hi)))
        assert runtime_err<.002 and tri==expected_tri-degenerate_tri,(row['key'],runtime_err,tri,expected_tri,degenerate_tri)
        row['runtime_triangles_including_degenerates']=expected_tri;row['importer_removed_repeated_index_degenerates']=degenerate_tri
        row['geometry_type']='line_context' if not tri else 'existing_runtime_unit'
        row['glb_local_bounds_error_m']=float(runtime_err)
    checks.append(dict(key=row['key'],vertices=vc,triangles=tri,edges=edges,bounds_error_m=float(err),source_sha256=sha(p)))
    write(p.parent/'asset_manifest.json',row)
    print('VERIFIED',row['key'],flush=True)
source_unchanged={p:sha(R/p)==h for p,h in cat['input_hashes'].items()};assert all(source_unchanged.values())
with gzip.open(D/'background_instances.json.gz','rt',encoding='utf-8') as f:data=json.load(f)
raw=np.fromfile(R/'godot/assets/world/environment/instances.bin',dtype='<f4').reshape(-1,16);seen=[];maxerr=0
for entry in data['building_instances']:
    m=np.array(entry['matrix_godot'])
    for p in entry['members']:
        i=p['source_instance'];seen.append(i);actual=np.eye(4);actual[:3]=raw[i,:12].reshape(3,4)
        maxerr=max(maxerr,float(np.max(abs(m@np.array(p['matrix_local_godot'])-actual))))
        assert np.max(abs(np.array(p['color_rgba'])-raw[i,12:16]))<1e-7
for entry in data['detail_instances']:
    i=entry['source_instance'];seen.append(i);actual=np.eye(4);actual[:3]=raw[i,:12].reshape(3,4)
    maxerr=max(maxerr,float(np.max(abs(np.array(entry['matrix_godot'])-actual))))
bake=json.loads((R/'godot/assets/world/environment/bake.json').read_text());active=[]
for b in bake['batches']:
    if b['geom'] in {749,750,751,753,754,756,757,758} or (b['alpha'] and b['geom']==747):continue
    active.extend(range(b['instOff'],b['instOff']+b['count']))
assert len(seen)==len(set(seen)) and set(seen)==set(active) and maxerr<1e-8
cat['background_instances']='background_instances.json.gz';write(D/'catalog.json',cat)
write(W/'verification.json',dict(passed=True,reopened=len(checks),checks=checks,input_hashes_unchanged=source_unchanged,background_instances=len(seen),duplicate_instance_ids=0,unassigned_instance_ids=0,max_exact_replay_matrix_error=maxerr,game_runtime_test='not_run_reference_export_only',godot_shader_pixel_parity='not_claimed'))
print('VERIFY_COMPLETE',len(checks),len(seen),maxerr,flush=True)

for name in ['playable_overview','background_building_library']:
    bpy.ops.wm.open_mainfile(filepath=str(D/(name+'_v0.1.blend')))
    assert all(Path(bpy.path.abspath(lib.filepath)).is_file() for lib in bpy.data.libraries)
    assert len([o for o in bpy.context.scene.objects if o.instance_type=='COLLECTION'])==(17 if name=='playable_overview' else 6)
report=json.loads((W/'verification.json').read_text());report['assemblies_reopened']=2;report['process_exit_code']=0;write(W/'verification.json',report)
print('ASSEMBLIES_VERIFIED',flush=True)
