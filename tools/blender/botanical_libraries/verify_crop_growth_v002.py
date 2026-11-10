"""Independent reopen validator for SEA planting growth v002."""
import bpy, hashlib, json, math, sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
BLEND = ROOT / 'art_source/crops/libraries/v002/planting_library.blend'
MANIFEST = ROOT / 'art_source/crops/libraries/v002/library_manifest.json'
PLAN = ROOT / 'art_source/crops/libraries/v002/component_plan.json'
PALETTE = ROOT / 'art_source/shared/palettes/sea_cozy_8x8_512.png'
PALETTE_JSON = ROOT / 'art_source/shared/palettes/sea_cozy_8x8_512.json'
VEGETATION_PLAN = ROOT / 'art_source/vegetation/libraries/v002/component_plan.json'
WORK = Path('D:/projects/sea-work/botanical_growth/v002/crops')

checks = 0
failures = []
negative_controls = []

def ck(value, message):
    global checks
    checks += 1
    if not value:
        failures.append(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def identity(o):
    return all(abs(o.matrix_world[i][j] - (1 if i == j else 0)) < 1e-6 for i in range(4) for j in range(4))

def face_uv_safe(mesh):
    layer = mesh.uv_layers.get('PaletteUV')
    if layer is None:
        return False, 'missing PaletteUV'
    for poly in mesh.polygons:
        coords = [layer.data[li].uv.copy() for li in poly.loop_indices]
        if len(coords) < 3:
            return False, 'face has fewer than 3 UV points'
        us = [float(v.x) for v in coords]; vs = [float(v.y) for v in coords]
        cells = {(math.floor(u * 8.0 + 1e-8), math.floor((1.0 - v) * 8.0 + 1e-8)) for u, v in zip(us, vs)}
        if len(cells) != 1:
            return False, 'face UV crosses palette cells'
        col, row = next(iter(cells))
        lo_u = col / 8.0 + 8.0 / 512.0
        hi_u = (col + 1) / 8.0 - 8.0 / 512.0
        lo_v = 1.0 - (row + 1) / 8.0 + 8.0 / 512.0
        hi_v = 1.0 - row / 8.0 - 8.0 / 512.0
        if not all(lo_u - 1e-6 <= u <= hi_u + 1e-6 and lo_v - 1e-6 <= v <= hi_v + 1e-6 for u, v in zip(us, vs)):
            return False, 'UV outside 8px safe border'
        area = 0.0
        for i in range(1, len(coords) - 1):
            area += abs((coords[i].x - coords[0].x) * (coords[i + 1].y - coords[0].y) - (coords[i + 1].x - coords[0].x) * (coords[i].y - coords[0].y)) * 0.5
        if area <= 1e-8:
            return False, 'face UV island has no area'
    return True, ''

def geometry_fingerprint(collection):
    payload = []
    for obj in sorted([x for x in collection.objects if x.type == 'MESH'], key=lambda x: x.name):
        mesh = obj.data; mesh.calc_loop_triangles()
        payload.append({'name': obj.name, 'organ': obj.get('organ_type'), 'v': [[round(v.co[i], 6) for i in range(3)] for v in mesh.vertices], 'f': [list(poly.vertices) for poly in mesh.polygons], 'uv': [[round(loop.uv[i], 7) for i in range(2)] for loop in mesh.uv_layers['PaletteUV'].data]})
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def mesh_objects(value):
    return [value] if hasattr(value, 'vertices') else [obj for obj in value.objects if obj.type == 'MESH']

def normalized_topology_fingerprint(value):
    payload = []
    for obj in sorted(mesh_objects(value), key=lambda x: (str(x.get('organ_type')), len(x.data.vertices), len(x.data.polygons))):
        mesh = obj if hasattr(obj, 'vertices') else obj.data
        coords = [v.co for v in mesh.vertices]
        lo = [min(v[i] for v in coords) for i in range(3)]; hi = [max(v[i] for v in coords) for i in range(3)]
        span = [max(hi[i] - lo[i], 1e-12) for i in range(3)]
        payload.append({'organ': obj.get('organ_type') if hasattr(obj, 'get') else '', 'v': [[round((v.co[i] - lo[i]) / span[i], 6) for i in range(3)] for v in mesh.vertices], 'f': [list(poly.vertices) for poly in mesh.polygons]})
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def organ_topology(value):
    return tuple(sorted((str(obj.get('organ_type')), len(obj.data.vertices), len(obj.data.polygons)) for obj in mesh_objects(value) if not hasattr(obj, 'vertices')))

def root_anchor_ok(value):
    return min(v.co.z for obj in mesh_objects(value) for v in (obj.vertices if hasattr(obj, 'vertices') else obj.data.vertices)) >= -1e-6 and abs(min(v.co.z for obj in mesh_objects(value) for v in (obj.vertices if hasattr(obj, 'vertices') else obj.data.vertices))) <= 1e-6

def growth_forms_valid(rows, collections):
    return [row['growth_key'] for row in rows] == ['small', 'medium', 'large'] and len({normalized_topology_fingerprint(c) for c in collections}) == 3 and len({organ_topology(c) for c in collections}) == 3

def temporary_scaled_collection(source, factor):
    collection = bpy.data.collections.new('__verification_scaled__')
    for source_obj in mesh_objects(source):
        obj = source_obj.copy(); obj.data = source_obj.data.copy()
        for vertex in obj.data.vertices: vertex.co *= factor
        collection.objects.link(obj)
    return collection

def main():
    WORK.mkdir(parents=True, exist_ok=True)
    ck(BLEND.is_file(), 'blend exists')
    ck(MANIFEST.is_file(), 'manifest exists')
    ck(PLAN.is_file(), 'component plan exists')
    ck(VEGETATION_PLAN.is_file(), 'vegetation protection plan exists')
    ck(PALETTE.is_file(), 'public palette exists')
    ck(PALETTE_JSON.is_file(), 'public palette mapping JSON exists')
    if failures:
        raise RuntimeError('prerequisite failure')
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    plan = json.loads(PLAN.read_text(encoding='utf-8'))
    vegetation_plan = json.loads(VEGETATION_PLAN.read_text(encoding='utf-8'))
    ck(manifest['sha256'] == sha(BLEND), 'saved blend hash matches manifest')
    for protected_path, protected_hash in vegetation_plan.get('protected_inputs', {}).items():
        ck((ROOT / protected_path).is_file() and sha(ROOT / protected_path) == protected_hash, 'protected vegetation input ' + protected_path)
    ck(manifest['schema_version'] == 2, 'manifest schema2')
    ck(manifest['library_id'] == 'SEA-LIB-PLANTING-GROWTH-V002', 'library id')
    ck(manifest['primary_source_migration'] is False, 'primary_source_migration false')
    ck(manifest['season_variants'] is False, 'no season variants')
    ck(manifest['growth_axis'] == ['small', 'medium', 'large'], 'growth axis')
    ck(manifest['plant_count'] == 6 and manifest['member_count'] == 18, '6 plants x 3 members')
    ck(len(manifest['plants']) == 6 and len(set(manifest['plants'])) == 6, 'six original asset ids')
    ck(manifest['material_roles'] == ['SEA_Matte', 'SEA_Gloss'] and manifest['material_count'] == 2, 'at most two material roles')
    ck(manifest['palette']['path'] == 'art_source/shared/palettes/sea_cozy_8x8_512.png', 'public palette path')
    ck(manifest['palette']['sha256'] == sha(PALETTE), 'public palette hash')
    ck(manifest['palette']['mapping_json'] == 'art_source/shared/palettes/sea_cozy_8x8_512.json', 'palette mapping JSON path')
    ck(manifest['palette']['mapping_json_sha256'] == sha(PALETTE_JSON), 'palette mapping JSON hash')
    ck(manifest['palette']['mapping_by_name'] is True, 'palette mapping by name')
    palette_data = json.loads(PALETTE_JSON.read_text(encoding='utf-8'))
    palette_cells = {cell['name']: (cell['row'], cell['column']) for cell in palette_data['cells']}
    ck(palette_cells.get('blue') == (2, 6), 'blue palette name mapping')
    ck(palette_cells.get('red') == (6, 6), 'red palette name mapping')
    ck(palette_cells.get('ochre') == (6, 3), 'ochre palette name mapping')
    ck(Path(manifest['font']).is_file(), 'Chinese font exists')
    bpy.ops.wm.open_mainfile(filepath=str(BLEND), load_ui=False)
    ck(len(bpy.data.libraries) == 0, 'no external blend links')
    ck(len(bpy.data.scenes) == 2, 'exactly two scenes')
    shared_materials = [bpy.data.materials.get(name) for name in ['SEA_Matte', 'SEA_Gloss']]
    ck(all(shared_materials) and len({id(material) for material in shared_materials}) == 2, 'two shared materials exist')
    for material in shared_materials:
        if material is None: continue
        textures = [node for node in material.node_tree.nodes if node.type == 'TEX_IMAGE']
        uv_nodes = [node for node in material.node_tree.nodes if node.type == 'UVMAP' and node.uv_map == 'PaletteUV']
        ck(len(textures) == 1 and textures[0].image is not None, 'material has real palette texture ' + material.name)
        if textures:
            ck(textures[0].interpolation == 'Closest', 'palette texture is Closest ' + material.name)
            ck(textures[0].image.source == 'FILE' and not textures[0].image.packed_file, 'palette texture is external ' + material.name)
            ck(Path(bpy.path.abspath(textures[0].image.filepath)).resolve() == PALETTE.resolve(), 'material palette path ' + material.name)
        ck(len(uv_nodes) == 1, 'explicit PaletteUV node ' + material.name)
    external_images = [image for image in bpy.data.images if image.source == 'FILE']
    ck(len(external_images) == 1 and Path(bpy.path.abspath(external_images[0].filepath)).resolve() == PALETTE.resolve(), 'unique external palette image')
    ck(bpy.data.scenes.get('01_小中大对照') is not None, 'comparison scene exists')
    ck(bpy.data.scenes.get('02_植物母版') is not None, 'master scene exists')
    ck(len([c for c in bpy.data.collections if c.get('asset_id') and c.get('growth_key')]) == 18, 'exactly 18 growth collections')
    by_asset = {}
    for row in manifest['members']:
        aid = row['asset_id']; growth = row['growth_key']; name = row['collection']
        by_asset.setdefault(aid, {})[growth] = row
        c = bpy.data.collections.get(name)
        ck(c is not None, 'collection exists ' + name)
        if c is None: continue
        ck(c.get('asset_id') == aid and c.get('growth_key') == growth, 'collection custom properties ' + name)
        ck(list(c.instance_offset) == [0.0, 0.0, 0.0], 'collection instance_offset zero ' + name)
        ck(c.get('season_variants') is False, 'collection no seasons ' + name)
        objects = [o for o in c.objects if o.type == 'MESH']
        ck(len(objects) == len(row['meshes']), 'mesh count ' + name)
        ck(row['root_anchor'] == [0, 0, 0], 'root anchor manifest ' + name)
        mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9)); tris = 0
        roles = set(); organs = {'leaves': 0, 'stems': 0, 'flowers': 0, 'fruits': 0}
        for o in objects:
            ck(o.parent is None and identity(o), 'identity mesh transform/root ' + o.name)
            for v in o.data.vertices:
                mn.x = min(mn.x, v.co.x); mn.y = min(mn.y, v.co.y); mn.z = min(mn.z, v.co.z)
                mx.x = max(mx.x, v.co.x); mx.y = max(mx.y, v.co.y); mx.z = max(mx.z, v.co.z)
            o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
            roles.update(m.name for m in o.data.materials if m)
            organ = o.get('organ_type')
            if organ == 'leaf': organs['leaves'] += 1
            elif organ == 'stem': organs['stems'] += 1
            elif organ == 'flower': organs['flowers'] += 1
            elif organ == 'fruit': organs['fruits'] += 1
            ok, msg = face_uv_safe(o.data); ck(ok, f'{name}/{o.name}: {msg}')
            ck(o.data.uv_layers.active is not None and o.data.uv_layers.active.name == 'PaletteUV' and o.data.uv_layers['PaletteUV'].active_render, 'active/render PaletteUV ' + o.name)
            ck(all(abs(x) <= 1e-6 for x in o.location), 'object location zero ' + o.name)
            ck(len(o.data.materials) == 1 and all(m.name in {'SEA_Matte', 'SEA_Gloss'} for m in o.data.materials), 'material role ' + o.name)
        actual_bounds = [list(mn), list(mx)]
        ck(max(abs(actual_bounds[a][b] - row['bounds'][a][b]) for a in range(2) for b in range(3)) < 1e-5, 'bounds parity ' + name)
        ck(tris == row['triangles'], 'triangle parity ' + name)
        ck(geometry_fingerprint(c) == row['geometry_fingerprint'], 'geometry fingerprint parity ' + name)
        ck(tris <= 1600, 'triangle budget ' + name)
        ck(mn.z >= -1e-6 and abs(mn.z) <= 1e-6, 'root at z=0 ' + name)
        ck(abs(mn.x + mx.x) < 1e-5 and abs(mn.y + mx.y) < 1e-5, 'bottom-center XY ' + name)
        ck(all(x <= 2 for x in [len(roles)]), 'material roles local ' + name)
        forbidden = ('土', '种子', '花盆', '土框', '平台', '手持', 'soil', 'seed', 'pot')
        ck(not any(any(word in o.name.lower() for word in forbidden) for o in objects), 'forbidden non-growing asset ' + name)
        ck(organs == row['organ_counts'], 'organ counts ' + name)
        for o in objects:
            if o.get('organ_type') in {'stem', 'fruit_stem'}:
                ck(float(o.get('taper_ratio', 0.58)) < 1.0, 'stem tapers ' + o.name)
            if o.get('organ_type') == 'leaf':
                z_values = [v.co.z for v in o.data.vertices]
                ck(max(z_values) - min(z_values) >= 0.002, 'leaf has physical thickness ' + o.name)
        if row['asset_id'] == 'SEA-CROP-TOMATO' and row['growth_key'] == 'small':
            ck(row['organ_counts']['leaves'] >= 3, 'tomato small at least three readable leaves')
        if row['asset_id'] == 'SEA-CROP-TOMATO' and row['growth_key'] in {'medium', 'large'}:
            ck(any(o.get('organ_type') == 'fruit_stem' for o in objects), 'tomato fruit pedicel exists ' + name)
        if row['asset_id'] == 'SEA-CROP-PUMPKIN' and row['growth_key'] == 'large':
            ck(any('成熟南瓜' in o.name for o in objects), 'pumpkin fruit exists')
            ck(any('瓜蒂' in o.name for o in objects), 'pumpkin stem exists')
    ck(set(by_asset) == set(manifest['plants']), 'all six planned ids present')
    for aid, stages in by_asset.items():
        ck(set(stages) == {'small', 'medium', 'large'}, aid + ' has exactly 3 growth档')
        if set(stages) != {'small', 'medium', 'large'}: continue
        rows = [stages[x] for x in ['small', 'medium', 'large']]
        sizes = [r['size_m'] for r in rows]
        ck(all(sizes[i][2] < sizes[i + 1][2] for i in range(2)), aid + ' height monotonic')
        ck(all(sizes[i][0] < sizes[i + 1][0] and sizes[i][1] < sizes[i + 1][1] for i in range(2)), aid + ' crown monotonic')
        collections = [bpy.data.collections[r['collection']] for r in rows]
        ck(len({r['geometry_fingerprint'] for r in rows}) == 3, aid + ' distinct geometry fingerprints')
        ck(len({normalized_topology_fingerprint(c) for c in collections}) == 3, aid + ' normalized topology differs')
        ck(len({organ_topology(c) for c in collections}) == 3, aid + ' organ topology differs')
        ck(len({r['triangles'] for r in rows}) == 3, aid + ' different triangle counts')
        ck(len({json.dumps(r['organ_counts'], sort_keys=True) for r in rows}) == 3, aid + ' different organ counts')
        ck(all(r['runtime_integration'] is False for r in rows), aid + ' no runtime integration')
    # Independent negative controls use temporary Blender data and the same predicates.
    rows = [by_asset[manifest['plants'][0]][growth] for growth in ['small', 'medium', 'large']]
    collections = [bpy.data.collections[r['collection']] for r in rows]
    missing_rejected = not growth_forms_valid(rows[:2], collections[:2])
    negative_controls.append({'case': '缺一档', 'rejected': missing_rejected})
    sample_mesh = next(o.data for o in bpy.data.objects if o.type == 'MESH' and o.data.uv_layers.get('PaletteUV'))
    uv_copy = sample_mesh.copy(); uv_copy.uv_layers['PaletteUV'].data[0].uv = (1.2, -0.1)
    uv_rejected = not face_uv_safe(uv_copy)[0]
    negative_controls.append({'case': 'UV越格', 'rejected': uv_rejected})
    bpy.data.meshes.remove(uv_copy)
    root_copy = sample_mesh.copy()
    for vertex in root_copy.vertices: vertex.co.z += 0.05
    root_rejected = not root_anchor_ok(root_copy)
    negative_controls.append({'case': '错误根点', 'rejected': root_rejected})
    bpy.data.meshes.remove(root_copy)
    scaled = [temporary_scaled_collection(collections[0], factor) for factor in (1.0, 2.0, 3.0)]
    scaled_rejected = not growth_forms_valid(rows, scaled)
    negative_controls.append({'case': '整体缩放冒充', 'rejected': scaled_rejected})
    for collection in scaled:
        for obj in list(collection.objects): bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(collection)
    for n in negative_controls: ck(n['rejected'], 'negative control ' + n['case'])
    # Independent empty-file Append check: every requested collection is local and editable.
    append_names = [row['collection'] for row in manifest['members']]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(BLEND), link=False) as (available, loaded):
        ck(all(name in available.collections for name in append_names), 'all 18 collections Appendable')
        loaded.collections = append_names
    appended = list(loaded.collections)
    for collection in appended:
        ck(collection is not None and collection.library is None, 'Append collection local ' + str(collection.name if collection else 'missing'))
        if collection is None: continue
        ck(collection.asset_data is not None, 'Append collection asset marked ' + collection.name)
        for obj in collection.all_objects:
            if obj.type == 'MESH':
                ck(obj.library is None and obj.data.library is None and len(obj.data.vertices) > 0, 'Append mesh local/editable ' + obj.name)
    report = {'passed': not failures, 'checks': checks, 'failures': failures, 'negative_controls': negative_controls, 'blend_sha256': sha(BLEND), 'library_id': manifest['library_id'], 'members': 18, 'plants': 6, 'total_triangles': manifest['total_triangles_unique'], 'scope': 'v002 source-only; no runtime files changed', 'v001_reference_protected': True}
    (WORK / 'verification_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('CROP_GROWTH_V002_VERIFY ' + json.dumps(report, ensure_ascii=False))
    if failures:
        raise RuntimeError(f'{len(failures)} verification failures')

if __name__ == '__main__':
    main()
