"""Normalize ONLY optimized export names for Godot 4.7, keep source and geometry unchanged."""
import bpy,json,hashlib,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';O=D/'export/v003';E=json.loads((O/'export_manifest.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert bpy.app.background
for e in E['components']:
    p=R/e['optimized_source'];assert sha(p)==e['optimized_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(p),load_ui=False,use_scripts=False);bpy.context.preferences.filepaths.save_version=0
    root=next(o for o in bpy.context.scene.objects if o.type=='EMPTY');o=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    root.name='Root_'+e['key'];o.name='Mesh_'+e['key'];o.data.name='Geometry_'+e['key'];bpy.context.scene.name='Component_'+e['key']
    bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True,relative_remap=False)
    e['optimized_sha256']=sha(p)
    bpy.ops.wm.open_mainfile(filepath=str(p),load_ui=False,use_scripts=False)
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.context.scene.objects:
        if o.type in ('MESH','EMPTY'):o.select_set(True)
    target=R/e['glb']
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_image_format='NONE',export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,export_texcoords=True,export_normals=True,export_tangents=False,export_attributes=False,export_extras=True)
    data=target.read_bytes();n=struct.unpack_from('<I',data,12)[0];d=json.loads(data[20:20+n]);assert not d.get('images')
    exported=sum(d['accessors'][p['indices']]['count']//3 for m in d['meshes'] for p in m['primitives']);assert exported==e['triangles_after']
    e['glb_sha256']=sha(target);e['glb_bytes']=target.stat().st_size;e['mesh_nodes']=[{'node_name':node['name'],'mesh_index':node['mesh'],'roles':[d['materials'][p['material']]['name'] for p in d['meshes'][node['mesh']]['primitives']]} for node in d['nodes'] if 'mesh' in node]
    e['operations']['export_node_names_ascii']=True
    print('NORMALIZED',e['key'],flush=True)
assert all(sha(R/p)==h for p,h in E['protected_sources'].items())
(O/'export_manifest.json').write_text(json.dumps(E,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('ASCII_EXPORTS_COMPLETE',len(E['components']))
