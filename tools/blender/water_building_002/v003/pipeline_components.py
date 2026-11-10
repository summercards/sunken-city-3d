import bpy
import bmesh
import hashlib
import json
import math
import os
import shutil
import struct
import sys
from pathlib import Path
from mathutils import Vector

R = Path('D:/projects/sea')
D = R / 'art_source/scenes/water_building_002/v003'
W = Path('D:/projects/sea-work/water_building_002/v003')
TOOLS = R / 'tools/blender/water_building_002/v003'
SOURCE = D / 'water_building_002_v003.blend'
V2_D = R / 'art_source/scenes/water_building_002/v002'
V2_W = Path('D:/projects/sea-work/water_building_002/v002')
V2_SOURCE = V2_D / 'water_building_002_v002.blend'
V2_WITNESS = V2_W / 'taper_witness.json'
WITNESS = W / 'taper_witness.json'
PALETTE = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
PALETTE_META = PALETTE.with_suffix('.json')
OPTIMIZED = D / 'export/v003/water_building_002_optimized_v003.blend'
GLB_ROOT = R / 'godot/assets/models/facilities/water_building_002/components'
EXPORT_MANIFEST = D / 'export/v003/export_manifest.json'
SOURCE_VERIFICATION = W / 'source_verification.json'
VOLUME_REVISION = W / 'volume_revision.json'
CATALOG = D / 'catalog.json'
INSTANCES_JSON = D / 'component_instances.json'

ROLE_NAMES = {'SEA_Matte', 'SEA_Metal', 'SEA_Gloss'}
EPS = 1.0e-12
UV_SAFE = 8.0 / 512.0


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def dump_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def mat_role(obj):
    role = obj.get('semantic_role')
    if role:
        return role
    if obj.type == 'MESH' and obj.data.materials:
        return obj.data.materials[0].get('semantic_role') or obj.data.materials[0].name
    return None


def mesh_triangles(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def transform_list(m):
    return [[float(m[r][c]) for c in range(4)] for r in range(4)]


def vec_list(v):
    return [float(v.x), float(v.y), float(v.z)]


def component_objects(collection):
    return [o for o in collection.all_objects if o.type == 'MESH']


def component_bounds(collection):
    pts = []
    for obj in component_objects(collection):
        for v in obj.data.vertices:
            pts.append(obj.matrix_world @ v.co)
    if not pts:
        return {'min': None, 'max': None, 'size': [0.0, 0.0, 0.0]}
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return {'min': vec_list(lo), 'max': vec_list(hi), 'size': vec_list(hi - lo)}


def geometry_stats(collection):
    objs = component_objects(collection)
    meshes = []
    tris = 0
    polys = 0
    verts = 0
    roles = set()
    for obj in objs:
        meshes.append(obj.data.name)
        tris += mesh_triangles(obj.data)
        polys += len(obj.data.polygons)
        verts += len(obj.data.vertices)
        role = mat_role(obj)
        if role:
            roles.add(role)
    return {
        'meshes': len(objs),
        'mesh_names': meshes,
        'vertices': verts,
        'polygons': polys,
        'triangles': tris,
        'material_roles': sorted(roles),
        'bounds': component_bounds(collection),
    }


def classification(entry):
    plant = entry['group'] == 'plant'
    return {
        'building_class': None if plant else 'above_water',
        'water_layer': 'none' if plant else 'surface',
        'water_layer_role': 'none' if plant else 'part',
    }


def set_common_scene_metadata(scene, entry):
    c = classification(entry)
    scene['asset_id'] = entry['asset_id']
    scene['source_version'] = 'v003'
    scene['asset_ledger'] = 'assets/registry/ledgers/scenes.json#' + entry['asset_id']
    scene['water_layer'] = c['water_layer']
    scene['water_layer_role'] = c['water_layer_role']
    if c['building_class'] is not None:
        scene['building_class'] = c['building_class']


def set_collection_metadata(collection, entry):
    c = classification(entry)
    collection['asset_id'] = entry['asset_id']
    collection['asset_ledger'] = 'assets/registry/ledgers/scenes.json#' + entry['asset_id']
    collection['water_layer'] = c['water_layer']
    collection['water_layer_role'] = c['water_layer_role']
    if c['building_class'] is not None:
        collection['building_class'] = c['building_class']


def load_palette_cells():
    return {x['name']: x for x in json.loads(PALETTE_META.read_text(encoding='utf-8'))['cells']}


def bottom_center_transform_check(collection, entry):
    objects = component_objects(collection)
    if not objects:
        return {'passed': False, 'reason': 'empty_geometry'}
    non_identity = []
    for obj in objects:
        if any(abs(x) > 1.0e-6 for x in obj.location) or any(abs(x) > 1.0e-6 for x in obj.rotation_euler) or any(abs(x - 1.0) > 1.0e-6 for x in obj.scale):
            non_identity.append(obj.name)
    return {
        'passed': not non_identity and tuple(collection.instance_offset) == (0.0, 0.0, 0.0),
        'contract': 'component mesh masters retain identity object transforms; placement belongs to collection instances',
        'expected_design_pivot': entry.get('design_pivot'),
        'instance_offset': [float(x) for x in collection.instance_offset],
        'non_identity_mesh_objects': non_identity,
    }


def validate_uv_and_materials(collection, cells):
    result = {
        'geometry_non_empty': True,
        'transform_identity': True,
        'bottom_center_transform': True,
        'instance_offset_zero': tuple(collection.instance_offset) == (0.0, 0.0, 0.0),
        'uv_layers_valid': True,
        'uv_faces_positive_area': True,
        'uv_same_color_cell': True,
        'uv_safe_8px': True,
        'closest_external_palette': True,
        'roles': set(),
        'external_images': set(),
        'issues': [],
    }
    design_pivot = collection.get('design_pivot')
    for obj in component_objects(collection):
        me = obj.data
        if len(me.vertices) == 0 or len(me.polygons) == 0:
            result['geometry_non_empty'] = False
            result['issues'].append(obj.name + ':empty_geometry')
        if any(abs(x) > 1.0e-6 for x in obj.location) or any(abs(x) > 1.0e-6 for x in obj.rotation_euler) or any(abs(x - 1.0) > 1.0e-6 for x in obj.scale):
            result['transform_identity'] = False
            result['issues'].append(obj.name + ':non_identity_transform')
        if len(me.uv_layers) != 1 or me.uv_layers[0].name != 'PaletteUV':
            result['uv_layers_valid'] = False
            result['issues'].append(obj.name + ':PaletteUV_not_unique')
            continue
        uv_layer = me.uv_layers[0]
        if getattr(me.uv_layers, 'active_index', 0) != 0 or getattr(me.uv_layers, 'active_render_index', 0) != 0:
            result['uv_layers_valid'] = False
            result['issues'].append(obj.name + ':PaletteUV_not_active_render')
        color = obj.get('palette_color')
        if color not in cells:
            result['uv_same_color_cell'] = False
            result['issues'].append(obj.name + ':unknown_palette_color')
            continue
        cell = cells[color]
        u0 = cell['column'] / 8.0
        u1 = (cell['column'] + 1) / 8.0
        v0 = 1.0 - (cell['row'] + 1) / 8.0
        v1 = 1.0 - cell['row'] / 8.0
        safe = (u0 + UV_SAFE, u1 - UV_SAFE, v0 + UV_SAFE, v1 - UV_SAFE)
        for poly in me.polygons:
            coords = [uv_layer.data[li].uv for li in poly.loop_indices]
            area = 0.0
            for i, a in enumerate(coords):
                b = coords[(i + 1) % len(coords)]
                area += a.x * b.y - b.x * a.y
            if abs(area) * 0.5 <= EPS:
                result['uv_faces_positive_area'] = False
                result['issues'].append(obj.name + ':uv_face_zero_area')
            for uv in coords:
                if not (u0 - 1.0e-6 <= uv.x <= u1 + 1.0e-6 and v0 - 1.0e-6 <= uv.y <= v1 + 1.0e-6):
                    result['uv_same_color_cell'] = False
                    result['issues'].append(obj.name + ':uv_outside_color_cell')
                if not (safe[0] - 1.0e-6 <= uv.x <= safe[1] + 1.0e-6 and safe[2] - 1.0e-6 <= uv.y <= safe[3] + 1.0e-6):
                    result['uv_safe_8px'] = False
                    result['issues'].append(obj.name + ':uv_outside_8px_safe_zone')
        role = mat_role(obj)
        if role:
            result['roles'].add(role)
        for slot in me.materials:
            if slot is None:
                continue
            slot_role = slot.get('semantic_role') or slot.name
            result['roles'].add(slot_role)
            for node in slot.node_tree.nodes if slot.use_nodes else []:
                if node.type == 'TEX_IMAGE':
                    if node.image:
                        result['external_images'].add(str(Path(bpy.path.abspath(node.image.filepath))))
                    if node.interpolation != 'Closest':
                        result['closest_external_palette'] = False
                        result['issues'].append(slot.name + ':image_not_closest')
    result['roles'] = sorted(result['roles'])
    result['external_images'] = sorted(result['external_images'])
    return result


def source_instance_verification(scene, entries_by_key):
    depsgraph = scene.view_layers[0].depsgraph if scene.view_layers else bpy.context.evaluated_depsgraph_get()
    # Force an evaluated graph for every visible collection instance; do not use catalog arithmetic.
    depsgraph.update()
    expanded = {}
    evaluated_meshes = 0
    evaluated_polygons = 0
    evaluated_triangles = 0
    for di in depsgraph.object_instances:
        obj = di.instance_object if di.is_instance else di.object
        if obj is None or obj.type != 'MESH':
            continue
        key = obj.get('component_key')
        if not key or key not in entries_by_key:
            continue
        me = obj.data
        me.calc_loop_triangles()
        expanded.setdefault(key, {'instances': 0, 'polygons': 0, 'triangles': 0})
        expanded[key]['instances'] += 1
        expanded[key]['polygons'] += len(me.polygons)
        expanded[key]['triangles'] += len(me.loop_triangles)
        evaluated_meshes += 1
        evaluated_polygons += len(me.polygons)
        evaluated_triangles += len(me.loop_triangles)
    matrices = []
    for obj in scene.objects:
        if obj.instance_type != 'COLLECTION' or not obj.instance_collection:
            continue
        asset_id = obj.instance_collection.get('asset_id')
        if not asset_id or asset_id not in {e['asset_id'] for e in entries_by_key.values()}:
            continue
        key = next(k for k, e in entries_by_key.items() if e['asset_id'] == asset_id)
        matrices.append({'name': obj.name, 'key': key, 'asset_id': asset_id, 'matrix_world': transform_list(obj.matrix_world), 'instance_offset': [float(x) for x in obj.instance_collection.instance_offset]})
    return {
        'method': 'Blender depsgraph evaluated object_instances; per-instance mesh loop_triangles and polygons',
        'expanded_by_component': expanded,
        'evaluated_mesh_object_instances': evaluated_meshes,
        'evaluated_polygons': evaluated_polygons,
        'evaluated_triangles': evaluated_triangles,
        'instance_matrices': matrices,
    }


def object_mesh_signature(obj):
    me = obj.data
    me.calc_loop_triangles()
    h = hashlib.sha256()
    for v in me.vertices:
        h.update(struct.pack('<3d', float(v.co.x), float(v.co.y), float(v.co.z)))
    for p in me.polygons:
        h.update(struct.pack('<I', len(p.vertices)))
        h.update(struct.pack('<%dI' % len(p.vertices), *p.vertices))
    return {'hash': h.hexdigest(), 'vertices': len(me.vertices), 'polygons': len(me.polygons), 'triangles': len(me.loop_triangles)}


def actual_source_mesh_signatures(path, entries):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    result = {}
    for entry in entries:
        collection = bpy.data.collections.get(entry['collection'])
        if collection is None:
            continue
        for obj in collection.all_objects:
            if obj.type == 'MESH':
                result[entry['key'] + ':' + obj.name] = object_mesh_signature(obj)
    return result


def actual_source_instance_matrices(path, entries_by_key):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    scene = bpy.context.scene
    allowed = {entry['asset_id']: key for key, entry in entries_by_key.items()}
    result = {}
    for obj in scene.objects:
        if obj.instance_type == 'COLLECTION' and obj.instance_collection:
            asset_id = obj.instance_collection.get('asset_id')
            if asset_id in allowed:
                result[obj.name] = {
                    'key': allowed[asset_id],
                    'matrix_world': transform_list(obj.matrix_world),
                    'location': vec_list(obj.location),
                    'scale': [float(x) for x in obj.scale],
                }
    return result


def independent_v2_v3_verification(entries_by_key, expected_volume):
    entries = list(entries_by_key.values())
    v2_meshes = actual_source_mesh_signatures(V2_SOURCE, entries)
    v3_meshes = actual_source_mesh_signatures(SOURCE, entries)
    mesh_keys = sorted(set(v2_meshes) | set(v3_meshes))
    mesh_mismatches = [name for name in mesh_keys if v2_meshes.get(name) != v3_meshes.get(name)]
    v2_instances = actual_source_instance_matrices(V2_SOURCE, entries_by_key)
    v3_instances = actual_source_instance_matrices(SOURCE, entries_by_key)
    crown_keys = {'crown_a', 'crown_b'}
    non_crown_matrix_diffs = []
    for name in sorted(set(v2_instances) | set(v3_instances)):
        a = v2_instances.get(name)
        b = v3_instances.get(name)
        if a is None or b is None:
            non_crown_matrix_diffs.append({'name': name, 'reason': 'instance_missing_in_one_source'})
        elif a['key'] not in crown_keys and a != b:
            non_crown_matrix_diffs.append({'name': name, 'v2': a, 'v3': b})
    crown_instances = [x for x in v3_instances.values() if x['key'] in crown_keys]
    actual = {
        'v2_component_mesh_object_count': len(v2_meshes),
        'v3_component_mesh_object_count': len(v3_meshes),
        'mesh_signature_mismatches': mesh_mismatches,
        'v2_instance_count': len(v2_instances),
        'v3_instance_count': len(v3_instances),
        'non_crown_matrix_diffs': non_crown_matrix_diffs,
        'crown_instance_count': len(crown_instances),
        'crown_scales': sorted([x['scale'] for x in crown_instances], key=lambda s: tuple(s)),
        'v2_depsgraph': None,
        'v3_depsgraph': None,
        'passed': not mesh_mismatches and not non_crown_matrix_diffs and len(v3_instances) == 167 and len(crown_instances) == 18,
    }
    bpy.ops.wm.open_mainfile(filepath=str(V2_SOURCE), load_ui=False)
    actual['v2_depsgraph'] = source_instance_verification(bpy.context.scene, entries_by_key)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
    actual['v3_depsgraph'] = source_instance_verification(bpy.context.scene, entries_by_key)
    actual['depsgraph_expected'] = {'polygons': 6293, 'triangles': 10342}
    actual['depsgraph_counts_passed'] = all(
        x['evaluated_polygons'] == 6293 and x['evaluated_triangles'] == 10342
        for x in (actual['v2_depsgraph'], actual['v3_depsgraph'])
    )
    actual['volume_record_checks'] = {
        'record_source_parent_matches_v2': expected_volume.get('source_parent_sha256') == sha256(V2_SOURCE),
        'record_source_matches_v3': expected_volume.get('source_sha256') == sha256(SOURCE),
        'record_pre_post_signatures_equal': expected_volume.get('topology_and_vertices_identical') is True,
        'record_non_crown_changes_empty': expected_volume.get('non_crown_instance_changes') == [],
        'record_crown_instances_18': expected_volume.get('crown_instances') == 18,
        'record_new_geometry_zero': expected_volume.get('details_added') == 0,
        'record_triangles_10342': expected_volume.get('triangles_before') == 10342 and expected_volume.get('triangles_after') == 10342,
    }
    actual['passed'] = actual['passed'] and actual['depsgraph_counts_passed'] and all(actual['volume_record_checks'].values())
    return actual


def package_from_source(entry, source_sha, palette_sha, cells):
    key = entry['key']
    out_dir = D / 'component_packages' / key
    out = out_dir / (key + '.blend')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(SOURCE), link=False) as (data_from, data_to):
        if entry['collection'] not in data_from.collections:
            raise RuntimeError('missing source collection: ' + entry['collection'])
        data_to.collections = [entry['collection']]
    collection = data_to.collections[0]
    scene = bpy.data.scenes.new('PACKAGE_' + key)
    scene.unit_settings.system = 'METRIC'
    scene.collection.children.link(collection)
    set_common_scene_metadata(scene, entry)
    set_collection_metadata(collection, entry)
    bpy.context.window.scene = scene
    stats = geometry_stats(collection)
    validation = validate_uv_and_materials(collection, cells)
    if validation['issues']:
        raise RuntimeError('package source validation failed: ' + ';'.join(validation['issues'][:5]))
    if not bottom_center_transform_check(collection, entry)['passed']:
        raise RuntimeError('package bottom-center transform validation failed')
    manifest = {
        'schema': 'sea.component_package_manifest',
        'asset_id': entry['asset_id'],
        'asset_ledger': 'assets/registry/ledgers/scenes.json#' + entry['asset_id'],
        'key': key,
        'source_blend': str(SOURCE).replace('\\', '/'),
        'source_version': 'v003',
        'source_sha256': source_sha,
        'source_28_components': 28,
        'source_plant_or_null': True if entry['group'] == 'plant' else None,
        'palette_path': str(PALETTE).replace('\\', '/'),
        'palette_sha256': palette_sha,
        'building_class': classification(entry)['building_class'],
        'water_layer': classification(entry)['water_layer'],
        'water_layer_role': classification(entry)['water_layer_role'],
        'component_collection': entry['collection'],
        'mesh_identity': 'source collection objects/data copied by Blender library load; no geometry edit',
        'stats': stats,
        'validation': {k: v for k, v in validation.items() if k not in {'roles', 'external_images'}},
        'bottom_center_transform': bottom_center_transform_check(collection, entry),
        'source_plant_or_null': True if entry['group'] == 'plant' else None,
        'material_roles': stats['material_roles'],
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(out), compress=True)
    before_reopen = sha256(out)
    # Reopen the actual package and validate it, without saving it again.
    bpy.ops.wm.open_mainfile(filepath=str(out), load_ui=False)
    collection_after = bpy.data.collections.get(entry['collection'])
    if collection_after is None:
        raise RuntimeError('package reopen missing collection')
    after_stats = geometry_stats(collection_after)
    after_validation = validate_uv_and_materials(collection_after, cells)
    after_reopen = sha256(out)
    if before_reopen != after_reopen:
        raise RuntimeError('package hash changed across reopen')
    manifest['package_sha256_before_reopen'] = before_reopen
    manifest['package_sha256_after_reopen'] = after_reopen
    manifest['reopen_stats'] = after_stats
    manifest['reopen_validation'] = {k: v for k, v in after_validation.items() if k not in {'roles', 'external_images'}}
    manifest['reopen_hash_protected'] = True
    dump_json(out_dir / 'asset_manifest.json', manifest)
    return manifest


def face_issue_counts(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    degenerate = []
    duplicate = []
    seen = {}
    for face in bm.faces:
        if len(face.verts) < 3 or face.calc_area() <= EPS:
            degenerate.append(face)
            continue
        signature = tuple(sorted(v.index for v in face.verts))
        if signature in seen:
            duplicate.append(face)
        else:
            seen[signature] = face.index
    loose = [v for v in bm.verts if not v.link_faces]
    return bm, degenerate, duplicate, loose


def optimize_collection(collection):
    before = geometry_stats(collection)
    operations = []
    changed_meshes = 0
    for obj in component_objects(collection):
        me = obj.data
        bm, degenerate, duplicate, loose_before = face_issue_counts(me)
        if degenerate or duplicate or loose_before:
            if degenerate:
                bmesh.ops.delete(bm, geom=degenerate, context='FACES')
                operations.append({'object': obj.name, 'operation': 'remove_degenerate_faces', 'count': len(degenerate)})
            if duplicate:
                bmesh.ops.delete(bm, geom=duplicate, context='FACES')
                operations.append({'object': obj.name, 'operation': 'remove_duplicate_faces', 'count': len(duplicate)})
            loose_after_faces = [v for v in bm.verts if not v.link_faces]
            if loose_after_faces:
                bmesh.ops.delete(bm, geom=loose_after_faces, context='VERTS')
                operations.append({'object': obj.name, 'operation': 'remove_orphan_vertices', 'count': len(loose_after_faces)})
            bm.to_mesh(me)
            me.update()
            changed_meshes += 1
        bm.free()
    after = geometry_stats(collection)
    if not operations:
        zero_reason = 'no_confirmed_degenerate_duplicate_faces_or_orphan_vertices; bevels and silhouette retained'
    else:
        zero_reason = None
    return {
        'before': before,
        'after': after,
        'operations': operations,
        'changed_meshes': changed_meshes,
        'zero_change_reason': zero_reason,
        'bevels_preserved': True,
    }


def optimize_source(entries_by_key, source_sha, palette_sha, cells):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
    source_scene = bpy.context.scene
    # Save an independent copy first. The loaded source filepath remains the source until this explicit save.
    OPTIMIZED.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED), copy=True, compress=True)
    optimization = {}
    for key, entry in entries_by_key.items():
        collection = bpy.data.collections.get(entry['collection'])
        if collection is None:
            raise RuntimeError('optimized source missing collection: ' + entry['collection'])
        optimization[key] = optimize_collection(collection)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED), compress=True)
    optimized_before_reopen = sha256(OPTIMIZED)
    bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED), load_ui=False)
    optimized_scene = bpy.context.scene
    optimized_after_reopen = sha256(OPTIMIZED)
    if optimized_before_reopen != optimized_after_reopen:
        raise RuntimeError('optimized source hash changed across reopen')
    optimized_stats = {}
    optimized_validation = {}
    for key, entry in entries_by_key.items():
        collection = bpy.data.collections.get(entry['collection'])
        if collection is None:
            raise RuntimeError('optimized reopen missing collection: ' + entry['collection'])
        optimized_stats[key] = geometry_stats(collection)
        optimized_validation[key] = validate_uv_and_materials(collection, cells)
    return {
        'source_sha256': source_sha,
        'palette_sha256': palette_sha,
        'optimized_sha256_before_reopen': optimized_before_reopen,
        'optimized_sha256_after_reopen': optimized_after_reopen,
        'optimized_hash_protected': True,
        'optimization_by_component': optimization,
        'optimized_stats': optimized_stats,
        'optimized_validation': optimized_validation,
        'scene_name': optimized_scene.name,
    }


def make_export_material(role):
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    bs = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    colors = {'SEA_Matte': (0.58, 0.48, 0.32, 1.0), 'SEA_Metal': (0.34, 0.40, 0.40, 1.0), 'SEA_Gloss': (0.06, 0.28, 0.30, 1.0)}
    bs.inputs['Base Color'].default_value = colors[role]
    bs.inputs['Roughness'].default_value = {'SEA_Matte': 0.78, 'SEA_Metal': 0.55, 'SEA_Gloss': 0.30}[role]
    bs.inputs['Metallic'].default_value = 0.25 if role == 'SEA_Metal' else 0.0
    return m


def parse_glb(path):
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b'glTF':
        raise RuntimeError('not a binary GLB')
    version, length = struct.unpack_from('<II', data, 4)
    if version != 2 or length != len(data):
        raise RuntimeError('invalid GLB header')
    offset = 12
    json_chunk = None
    while offset + 8 <= len(data):
        chunk_len, chunk_type = struct.unpack_from('<II', data, offset)
        chunk = data[offset + 8:offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            json_chunk = json.loads(chunk.rstrip(b' \t\r\n\0').decode('utf-8'))
            break
        offset += 8 + chunk_len
    if json_chunk is None:
        raise RuntimeError('GLB JSON chunk missing')
    accessors = json_chunk.get('accessors', [])
    mesh_records = []
    total_triangles = 0
    for mesh in json_chunk.get('meshes', []):
        mesh_triangles_count = 0
        for primitive in mesh.get('primitives', []):
            mode = primitive.get('mode', 4)
            if mode != 4:
                raise RuntimeError('non-triangle primitive in GLB')
            if 'indices' in primitive:
                count = accessors[primitive['indices']]['count']
            else:
                count = accessors[primitive['attributes']['POSITION']]['count']
            tris = count // 3
            mesh_triangles_count += tris
            total_triangles += tris
        mesh_records.append({'name': mesh.get('name'), 'triangles': mesh_triangles_count, 'primitives': len(mesh.get('primitives', []))})
    return {
        'version': version,
        'meshes': mesh_records,
        'mesh_count': len(mesh_records),
        'triangles': total_triangles,
        'images': len(json_chunk.get('images', [])),
        'textures': len(json_chunk.get('textures', [])),
        'materials': [m.get('name') for m in json_chunk.get('materials', [])],
    }


def export_component_glb(entry, optimized_stats):
    key = entry['key']
    collection = bpy.data.collections.get(entry['collection'])
    if collection is None:
        raise RuntimeError('export source collection missing')
    scene = bpy.data.scenes.new('EXPORT_' + key)
    root = bpy.data.collections.new('EXPORT_COMPONENT_' + key)
    scene.collection.children.link(root)
    export_mats = {role: make_export_material(role) for role in ROLE_NAMES}
    objects = []
    for src in component_objects(collection):
        obj = src.copy()
        obj.data = src.data.copy()
        root.objects.link(obj)
        obj.matrix_world = src.matrix_world.copy()
        role = mat_role(src)
        if role not in export_mats:
            raise RuntimeError('unsupported semantic material role: ' + str(role))
        for i in range(len(obj.data.materials)):
            obj.data.materials[i] = export_mats[role]
        objects.append(obj)
    if not objects:
        raise RuntimeError('empty component export')
    groups = {}
    for obj in objects:
        groups.setdefault(mat_role(obj), []).append(obj)
    # One joined mesh per semantic role, never cross-component and never more than three meshes.
    bpy.context.window.scene = scene
    for role, group in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in group:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.join()
    export_objects = [o for o in root.objects if o.type == 'MESH']
    if len(export_objects) > 3:
        raise RuntimeError('joined export exceeds three meshes')
    for obj in export_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_objects[0]
    out = GLB_ROOT / key / (key + '.glb')
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_materials='EXPORT',
        export_image_format='NONE',
        export_yup=True,
    )
    parsed = parse_glb(out)
    if parsed['images'] != 0 or parsed['textures'] != 0:
        raise RuntimeError('GLB contains images/textures despite export_image_format NONE')
    if parsed['triangles'] != optimized_stats['triangles']:
        raise RuntimeError('GLB triangle mismatch: %s != %s' % (parsed['triangles'], optimized_stats['triangles']))
    bounds = component_bounds(collection)
    result = {
        'path': str(out).replace('\\', '/'),
        'sha256': sha256(out),
        'triangles': parsed['triangles'],
        'meshes': parsed['mesh_count'],
        'bounds': bounds,
        'binary_parse': parsed,
        'material_roles': sorted(groups),
        'export_image_format': 'NONE',
        'images': parsed['images'],
        'textures': parsed['textures'],
        'export_active_scene': True,
    }
    # Do not save the temporary export scene into the optimized source.
    bpy.data.scenes.remove(scene)
    return result


def independent_taper_check(source_scene, witness_records):
    checked = 0
    passed = 0
    failures = []
    for rec in witness_records:
        obj = bpy.data.objects.get(rec['object'])
        if obj is None or obj.type != 'MESH':
            failures.append({'object': rec['object'], 'reason': 'object_missing'})
            continue
        samples = rec.get('sample_before', [])
        if len(samples) != len(obj.data.vertices):
            failures.append({'object': rec['object'], 'reason': 'vertex_count_mismatch'})
            continue
        checked += 1
        axis = int(rec['axis'])
        rho = float(rec['rho'])
        lo = float(rec['axis_min'])
        extent = float(rec['extent_before'][axis])
        pivot = Vector(rec.get('pivot', [0.0, 0.0, 0.0]))
        max_error = 0.0
        for before, vertex in zip(samples, obj.data.vertices):
            p = Vector(before)
            t = (p[axis] - lo) / extent
            q = p.copy()
            for j in range(3):
                if j != axis:
                    q[j] = Vector(rec['center'])[j] + (p[j] - Vector(rec['center'])[j]) * (1.0 - rho * t)
            q -= pivot
            max_error = max(max_error, (q - vertex.co).length)
        if max_error <= 1.0e-5:
            passed += 1
        else:
            failures.append({'object': rec['object'], 'max_error': max_error, 'rho': rho})
    return {'method': 'independent recomputation from taper_witness sample_before and saved mesh vertices', 'checked': checked, 'passed': passed, 'failed': len(failures), 'max_error_tolerance': 1.0e-5, 'failures': failures}


def main():
    for path in (SOURCE, PALETTE, CATALOG, INSTANCES_JSON, PALETTE_META):
        if not path.is_file():
            raise RuntimeError('required file missing: ' + str(path))
    W.mkdir(parents=True, exist_ok=True)
    source_sha_before = sha256(SOURCE)
    palette_sha_before = sha256(PALETTE)
    catalog_data = json.loads(CATALOG.read_text(encoding='utf-8'))
    entries = catalog_data['components']
    if len(entries) != 28:
        raise RuntimeError('catalog component count is not 28')
    entries_by_key = {e['key']: e for e in entries}
    source_instances = json.loads(INSTANCES_JSON.read_text(encoding='utf-8'))['instances']
    if len(source_instances) != 167:
        raise RuntimeError('component_instances count is not 167')
    cells = load_palette_cells()
    package_results = {}
    failures = []

    for entry in entries:
        try:
            package_results[entry['key']] = package_from_source(entry, source_sha_before, palette_sha_before, cells)
        except Exception as exc:
            failures.append({'stage': 'package', 'key': entry['key'], 'error': repr(exc)})
            print('PACKAGE_FAILED', entry['key'], repr(exc), flush=True)

    # Reopen original source for depsgraph verification. No source save operation is performed.
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
    source_scene = bpy.context.scene
    source_depsgraph = source_instance_verification(source_scene, entries_by_key)
    source_validation = {}
    for key, entry in entries_by_key.items():
        col = bpy.data.collections.get(entry['collection'])
        if col is None:
            failures.append({'stage': 'source_validation', 'key': key, 'error': 'collection_missing'})
            continue
        source_validation[key] = {
            'stats': geometry_stats(col),
            'validation': validate_uv_and_materials(col, cells),
            'instance_offset': [float(x) for x in col.instance_offset],
        }
    if not V2_WITNESS.is_file():
        raise RuntimeError('v2 taper witness missing: ' + str(V2_WITNESS))
    W.mkdir(parents=True, exist_ok=True)
    shutil.copy2(V2_WITNESS, WITNESS)
    witness_records = json.loads(WITNESS.read_text(encoding='utf-8')).get('records', [])
    taper_result = independent_taper_check(source_scene, witness_records)
    expected_volume = json.loads(VOLUME_REVISION.read_text(encoding='utf-8')) if VOLUME_REVISION.is_file() else {}
    if expected_volume.get('source_parent_sha256') != sha256(V2_SOURCE):
        failures.append({'stage': 'volume_revision', 'error': 'source_parent_sha256 does not match v2 source'})
    if expected_volume.get('source_sha256') != source_sha_before:
        failures.append({'stage': 'volume_revision', 'error': 'source_sha256 does not match v3 source'})
    independent_verification = independent_v2_v3_verification(entries_by_key, expected_volume)
    if not independent_verification['passed']:
        failures.append({'stage': 'independent_v2_v3_verification', 'error': 'actual v2/v3 mesh, matrix, depsgraph or volume record checks failed'})

    try:
        optimization_result = optimize_source(entries_by_key, source_sha_before, palette_sha_before, cells)
    except Exception as exc:
        failures.append({'stage': 'optimize', 'error': repr(exc)})
        optimization_result = {'error': repr(exc)}

    glb_results = {}
    if 'error' not in optimization_result:
        for entry in entries:
            key = entry['key']
            try:
                glb_results[key] = export_component_glb(entry, optimization_result['optimized_stats'][key])
            except Exception as exc:
                failures.append({'stage': 'glb', 'key': key, 'error': repr(exc)})
                print('GLB_FAILED', key, repr(exc), flush=True)

    source_sha_after = sha256(SOURCE)
    palette_sha_after = sha256(PALETTE)
    source_protection = source_sha_before == source_sha_after
    palette_protection = palette_sha_before == palette_sha_after
    if not source_protection:
        failures.append({'stage': 'protection', 'error': 'source hash changed'})
    if not palette_protection:
        failures.append({'stage': 'protection', 'error': 'palette hash changed'})

    # Update only the explicitly requested catalog package/export hash fields.
    for entry in entries:
        key = entry['key']
        if key in package_results:
            pkg = package_results[key]
            entry['package_sha256'] = pkg['package_sha256_after_reopen']
            entry['package_sha256_before_reopen'] = pkg['package_sha256_before_reopen']
            entry['source_version'] = 'v003'
            entry['component_source'] = f'art_source/scenes/water_building_002/v003/component_packages/{key}/{key}.blend'
            entry['package_manifest'] = f'art_source/scenes/water_building_002/v003/component_packages/{key}/asset_manifest.json'
            entry['package_source_sha256'] = source_sha_before
            entry['package_palette_sha256'] = palette_sha_before
        if key in glb_results:
            entry['glb_sha256'] = glb_results[key]['sha256']
            entry['glb_path'] = f'godot/assets/models/facilities/water_building_002/components/{key}/{key}.glb'
            entry['optimized_triangles'] = glb_results[key]['triangles']
            entry['optimized_meshes'] = glb_results[key]['meshes']
    catalog_after = {'schema': catalog_data.get('schema', 'sea.component_catalog'), 'components': entries}
    dump_json(CATALOG, catalog_after)

    source_verification = {
        'schema': 'sea.source_verification',
        'asset_id': 'SEA-SCENE-WATER-BUILDING-002',
        'source_path': str(SOURCE).replace('\\', '/'),
        'source_sha256_before': source_sha_before,
        'source_sha256_after': source_sha_after,
        'source_unchanged': source_protection,
        'palette_path': str(PALETTE).replace('\\', '/'),
        'palette_sha256_before': palette_sha_before,
        'palette_sha256_after': palette_sha_after,
        'palette_unchanged': palette_protection,
        'catalog_components': len(entries),
        'catalog_instances': len(source_instances),
        'source_depsgraph': source_depsgraph,
        'source_component_validation': source_validation,
        'independent_v2_v3_verification': independent_verification,
        'witness_provenance': {
            'path': str(WITNESS).replace('\\', '/'),
            'copied_from': str(V2_WITNESS).replace('\\', '/'),
            'source_parent_sha256': sha256(V2_SOURCE),
            'provenance_note': 'v2 witness reused because v3 master mesh vertices/topology are unchanged; independent v2/v3 actual mesh verification is recorded separately',
        },
        'packages': {k: {'sha256_before_reopen': v['package_sha256_before_reopen'], 'sha256_after_reopen': v['package_sha256_after_reopen'], 'hash_protected': v['reopen_hash_protected'], 'stats': v['reopen_stats'], 'validation': v['reopen_validation']} for k, v in package_results.items()},
        'optimized': optimization_result,
        'taper_witness': taper_result,
        'volume_revision': {
            'path': str(VOLUME_REVISION).replace('\\', '/'),
            'pre_equals_post': expected_volume.get('topology_and_vertices_identical') is True,
            'changed_crown_instances': expected_volume.get('crown_instances') == 18,
            'new_geometry': expected_volume.get('details_added') == 0,
        },
        'scope': {
            'technical_source_and_asset_checks': 'reported separately from scene-wide seam review',
            'full_scene_seams': 'not exhaustively enumerated; pending',
            'game_import_runtime': 'pending',
            'point_sampling': 'not signed as complete seam/no-intersection proof',
        },
        'failures': failures,
    }
    dump_json(SOURCE_VERIFICATION, source_verification)

    export_manifest = {
        'schema': 'sea.component_export_manifest',
        'asset_id': 'SEA-SCENE-WATER-BUILDING-002',
        'source': {'path': str(SOURCE).replace('\\', '/'), 'sha256': source_sha_before, 'expanded_instances': len(source_instances), 'expanded_triangles_depsgraph': source_depsgraph['evaluated_triangles'], 'expanded_polygons_depsgraph': source_depsgraph['evaluated_polygons']},
        'optimized': {'path': str(OPTIMIZED).replace('\\', '/'), 'sha256': optimization_result.get('optimized_sha256_after_reopen'), 'hash_protected': optimization_result.get('optimized_hash_protected', False)},
        'components': glb_results,
        'export_contract': {'only_component_glbs': True, 'export_root': str(GLB_ROOT).replace('\\', '/'), 'export_image_format': 'NONE', 'images': 0, 'textures': 0, 'export_active_scene': True, 'max_meshes_per_component': 3, 'plants_cross_component_merge': False, 'semantic_material_roles': sorted(ROLE_NAMES)},
        'failures': failures,
    }
    dump_json(EXPORT_MANIFEST, export_manifest)
    print('PIPELINE_RESULT', json.dumps({'source_sha256': source_sha_before, 'source_unchanged': source_protection, 'palette_unchanged': palette_protection, 'components': len(package_results), 'glbs': len(glb_results), 'expanded_triangles': source_depsgraph['evaluated_triangles'], 'failures': len(failures), 'source_verification': str(SOURCE_VERIFICATION), 'export_manifest': str(EXPORT_MANIFEST)}, ensure_ascii=False), flush=True)
    if failures:
        raise RuntimeError('pipeline completed with failures; see source_verification.json and export_manifest.json')


if __name__ == '__main__':
    main()
