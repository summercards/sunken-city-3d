"""Optimize every standalone package and export only after reopening the derived Blend."""
import bmesh,bpy,hashlib,json,struct
from pathlib import Path

root=Path(__file__).resolve().parents[3]
source=root/'art_source/scenes/neon_garden_quarter/v003'
out=source/'export/v003';out.mkdir(parents=True,exist_ok=True)
runtime=root/'godot/assets/models/facilities/neon_garden_quarter'
catalog=json.loads((source/'component_catalog.json').read_text(encoding='utf8'))['components']
plan=json.loads((source/'component_plan.json').read_text(encoding='utf8'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def triangles(objects):
    for obj in objects:obj.data.calc_loop_triangles()
    return sum(len(obj.data.loop_triangles) for obj in objects)
def limits(objects):
    coords=[v.co for obj in objects for v in obj.data.vertices]
    return [[f(v[i] for v in coords) for i in range(3)] for f in (min,max)]
def glb_document(path):
    data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+size])

protected=[source/'neon_garden_quarter.blend',root/plan['palette'],root/plan['poster_source']]
initial={p:sha(p) for p in protected}
records=[]
for item in catalog:
    key=item['key'];original=root/item['source'];digest=sha(original)
    assert digest==item['source_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(original));bpy.context.preferences.filepaths.save_version=0
    collection=bpy.data.collections[item['collection']]
    objects=list(collection.objects);before=triangles(objects);bounds=limits(objects)
    roles={};counts={'duplicate_faces':0,'zero_area_faces':0,'loose_edges':0,'loose_vertices':0,'coplanar_edges_reduced':0}
    poster_material=bpy.data.materials.new('SEA_Poster')
    for obj in objects:
        mesh=obj.data
        if 'poster_tile' in obj:
            # Godot gets one UV per surface. Print uses the authored atlas UV, geometry uses PaletteUV.
            mesh.uv_layers.remove(mesh.uv_layers['PaletteUV']);mesh.uv_layers.active_index=0
            mesh.uv_layers[0].name='UVMap';mesh.uv_layers[0].active_render=True
            mesh.materials.clear();mesh.materials.append(poster_material)
        else:
            bm=bmesh.new();bm.from_mesh(mesh)
            # Source palette islands all lie in one cell per object. Dissolve flat interior edges only.
            uv=bm.loops.layers.uv.active
            color_cells={(int(loop[uv].uv.x*8),int(loop[uv].uv.y*8)) for face in bm.faces for loop in face.loops}
            seen=set();bad=[]
            for face in bm.faces:
                signature=tuple(sorted(v.index for v in face.verts))
                if face.calc_area()<1e-12:counts['zero_area_faces']+=1;bad.append(face)
                elif signature in seen:counts['duplicate_faces']+=1;bad.append(face)
                else:seen.add(signature)
            if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
            edges=[edge for edge in bm.edges if not edge.link_faces];counts['loose_edges']+=len(edges)
            if edges:bmesh.ops.delete(bm,geom=edges,context='EDGES')
            points=[vert for vert in bm.verts if not vert.link_edges];counts['loose_vertices']+=len(points)
            if points:bmesh.ops.delete(bm,geom=points,context='VERTS')
            if len(color_cells)==1 and not any(face.smooth for face in bm.faces):
                old_edges=len(bm.edges)
                candidates=[edge for edge in bm.edges if edge.is_manifold and edge.calc_face_angle()<.0001]
                if candidates:bmesh.ops.dissolve_limit(bm,angle_limit=.0001,verts=[],edges=candidates,delimit={'NORMAL','MATERIAL'})
                counts['coplanar_edges_reduced']+=old_edges-len(bm.edges)
                cx,cy=next(iter(color_cells));cx=(cx+.5)/8;cy=(cy+.5)/8
                for face in bm.faces:
                    for i,loop in enumerate(face.loops):
                        import math
                        angle=math.tau*i/len(face.loops);loop[uv].uv=(cx+.019*math.cos(angle),cy+.019*math.sin(angle))
            bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.update()
            mesh.uv_layers[0].name='UVMap'
        roles.setdefault(mesh.materials[0].name,[]).append(obj)
    for role,group in roles.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in group:obj.select_set(True)
        bpy.context.view_layer.objects.active=group[0]
        if len(group)>1:bpy.ops.object.join()
        group[0].name='Surface_'+role
    objects=list(collection.objects);after=triangles(objects)
    assert all(abs(a-b)<.0001 for old,new in zip(bounds,limits(objects)) for a,b in zip(old,new)),key
    derived=out/f'{key}_optimized.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(derived),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(derived))
    assert triangles(bpy.data.collections[item['collection']].objects)==after
    target=runtime/key/f'{key}.glb';target.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_image_format='NONE',export_yup=True,export_animations=False,export_attributes=False,export_texcoords=True,export_normals=True,export_tangents=True)
    document=glb_document(target)
    assert not document.get('images') and not document.get('textures')
    exported=sum(document['accessors'][primitive['indices']]['count']//3 for mesh in document['meshes'] for primitive in mesh['primitives'])
    assert exported==after and sha(original)==digest,(key,exported,after)
    records.append(dict(key=key,asset_id=item['asset_id'],role='optimized',version='v003',source=item['source'],source_sha256_before=digest,source_sha256_after=sha(original),optimized_source=derived.relative_to(root).as_posix(),optimized_sha256=sha(derived),glb=target.relative_to(root).as_posix(),glb_sha256=sha(target),triangles_before=before,triangles_after=after,reduction_ratio=(before-after)/before,operations=counts,mesh_objects_before=sum(len(group) for group in roles.values()),mesh_objects_after=len(roles),bounds=bounds,material_roles=sorted(roles),budget=item['triangle_budget'],budget_source='v003 component_plan.json',retention='Keep silhouette, bevels, back faces, hard edges, printed UVs and organic curvature. Merge draw surfaces by role.',embedded_images=0))
    print('NGQ_EXPORT',key,before,after,len(roles),flush=True)
assert all(sha(path)==digest for path,digest in initial.items())
(out/'export_manifest.json').write_text(json.dumps({'version':'v003','protected_sources':{p.relative_to(root).as_posix():h for p,h in initial.items()},'components':records},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
