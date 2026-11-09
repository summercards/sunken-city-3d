"""后台只读验收；仅写工程外报告，不保存、重置或渲染任何 Blender 源。"""
import hashlib
import json
import math
import sys
import traceback
from collections import Counter
from pathlib import Path

import bpy
from mathutils import Matrix


R = Path('D:/projects/sea')
D = R / 'art_source/scenes/bld_20261109_a/v002'
W = Path('D:/projects/sea-work/bld_20261109_a/v002')
SOURCE = D / 'bld_20261109_a_v002.blend'
SCENE_NAME = 'BLDA_编号海上建筑_v002'
V1_CATALOG = R / 'art_source/scenes/bld_20261109_a/v001/catalog.json'
TOL = 2e-5
ROLES = {'SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission'}
IDENTITY = Matrix.Identity(4)
FINGERPRINT_ALGORITHM = 'ordered_vertices_fixed6_sha256'
REPORT = {
    'passed': False, 'technical_passed': False, 'checks': 0, 'errors': [],
    'source_sha256': None, 'palette_sha256': None, 'fingerprint_algorithm': FINGERPRINT_ALGORITHM if 'FINGERPRINT_ALGORITHM' in globals() else None,
    'packages_reopened': 0,
    'components': 0, 'component_budget': {}, 'family_counts': {},
    'instances': 0, 'visible_instances': 0,
    'uv_faces_checked': 0, 'master_triangles': 0,
    'expanded_triangles': 0, 'expanded_polygons': 0, 'exit_code': 1,
    'component_results': [], 'package_results': [], 'instance_results': [],
    'nonzero_rho_keys': [], 'visual_review_evidence': [], 'visual_review': {},
    'actual_form_audit': {},
    'pending': {
        'visual_review': [], 'fingerprint_review': [],
        'runtime': ['Godot 接入、碰撞、可行走性及运行时验收不在本次只读检查范围'],
        'rights': ['参考图商业使用权待确认'],
        'user_final_acceptance': ['用户最终验收待确认'],
    },
    'visibility_contract': '所有 ViewLayer 的可见依赖图条目并集；排除 hide_render、show_self=False 及 display_support。相同层内不去重，相同实例在多层间不重复累计。',
}
VISUAL_REVIEW = {'path': str(W / 'visual_review.json'), 'loaded': False, 'valid': False,
                 'source_sha256_match': False, 'passed': False, 'reviewed_component_keys': []}


def require(ok, label):
    REPORT['checks'] += 1
    if not ok:
        REPORT['errors'].append(label)
    return bool(ok)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def root_path(value):
    path = Path(value)
    return (path if path.is_absolute() else R / path).resolve()


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def ordered_vertices_fixed6_sha256(col):
    digest = hashlib.sha256()
    for obj in col.all_objects:
        if obj.type != 'MESH':
            continue
        for vertex in obj.data.vertices:
            digest.update((','.join(format(float(value), '.6f') for value in vertex.co) + ';').encode())
    return digest.hexdigest()


def geometry_uv_topology_roles_sha256(col):
    payload = []
    for obj in col.all_objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.data
        uv = mesh.uv_layers.get('PaletteUV')
        payload.append({
            'object': obj.name,
            'vertices': [[format(float(value), '.6f') for value in vertex.co] for vertex in mesh.vertices],
            'edges': [list(edge.vertices) for edge in mesh.edges],
            'faces': [list(face.vertices) for face in mesh.polygons],
            'material_roles': [slot.material.get('semantic_role', '') if slot.material else ''
                               for slot in obj.material_slots],
            'face_materials': [face.material_index for face in mesh.polygons],
            'uv': [[format(float(value), '.9f') for value in loop.uv] for loop in uv.data] if uv else None,
        })
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def vector_matches(actual, expected, tolerance=TOL):
    return (isinstance(expected, (list, tuple)) and len(expected) == len(actual)
            and all(finite_number(v) for v in expected)
            and all(abs(a - b) <= tolerance for a, b in zip(actual, expected)))


def identity(matrix):
    return all(math.isfinite(matrix[i][j]) and abs(matrix[i][j] - IDENTITY[i][j]) <= TOL
               for i in range(4) for j in range(4))


def open_readonly(path):
    # 禁止文件内自动脚本；不启用 UI 加载，不连接任何运行中的 Blender。
    result = bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    if result != {'FINISHED'}:
        raise RuntimeError('无法只读打开 ' + str(path))
    require(Path(bpy.data.filepath).resolve() == path.resolve(), '实际打开路径：' + str(path))


def collection_tree(collection):
    yield collection
    for child in collection.children:
        yield from collection_tree(child)


def support_object(obj, marked_collections):
    if obj is None:
        return False
    obj = obj.original
    visited = set()
    while obj is not None and obj.as_pointer() not in visited:
        visited.add(obj.as_pointer())
        if obj.get('display_support', False):
            return True
        if any(c.as_pointer() in marked_collections for c in obj.users_collection):
            return True
        obj = obj.parent
    return False


def marked_support_collections(scene):
    marked = set()

    def visit(col, inherited=False):
        flagged = inherited or bool(col.get('display_support', False))
        if flagged:
            marked.add(col.as_pointer())
        for child in col.children:
            visit(child, flagged)

    visit(scene.collection)
    return marked


def inspect_material(mat, label, palette, cache):
    if mat is None:
        require(False, label + '：空材质槽')
        return ''
    role = mat.get('semantic_role', '')
    require(role in ROLES, label + '：合法 semantic_role')
    if mat.as_pointer() in cache:
        return role
    cache.add(mat.as_pointer())
    if not require(mat.use_nodes and mat.node_tree is not None, label + '：节点材质'):
        return role
    tree = mat.node_tree
    textures = [n for n in tree.nodes if n.type == 'TEX_IMAGE']
    require(bool(textures), label + '：存在色盘贴图节点')
    # 不将未知节点组默认为已验证，以免漏查组内的其它贴图或坐标变换。
    require(not any(n.type == 'GROUP' for n in tree.nodes), label + '：无未审计材质节点组')
    outputs = [n for n in tree.nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output]
    reachable = set()

    def upstream(node):
        if node.as_pointer() in reachable:
            return
        reachable.add(node.as_pointer())
        for socket in node.inputs:
            for link in socket.links:
                upstream(link.from_node)

    for output in outputs:
        surface = output.inputs.get('Surface')
        require(surface is not None and surface.is_linked, label + '：有效 Surface 输出')
        if surface:
            for link in surface.links:
                upstream(link.from_node)
    require(bool(outputs), label + '：有效材质输出')
    require(any(n.as_pointer() in reachable for n in textures), label + '：色盘参与实际 Surface 着色')
    for node in textures:
        tag = label + '/' + node.name
        require(node.interpolation == 'Closest', tag + '：Closest 插值')
        image = node.image
        if not require(image is not None, tag + '：贴图存在'):
            continue
        require(image.source == 'FILE', tag + '：外部单文件图片')
        require(image.packed_file is None and not list(image.packed_files), tag + '：未 packed')
        resolved = Path(bpy.path.abspath(image.filepath, library=image.library)).resolve()
        require(resolved.is_absolute() and resolved == palette and resolved.is_file(), tag + '：绝对解析为计划色盘')
        require(tuple(image.size) == (512, 512), tag + '：512×512 色盘')
        vector = node.inputs.get('Vector')
        links = list(vector.links) if vector else []
        # 只接受直接 UVMap 或不改值的 Reroute，不能只检查有一个闲置 PaletteUV 节点。
        seen = set()
        while len(links) == 1 and links[0].from_node.type == 'REROUTE':
            reroute = links[0].from_node
            if reroute.as_pointer() in seen:
                links = []
                break
            seen.add(reroute.as_pointer())
            links = list(reroute.inputs[0].links)
        require(len(links) == 1 and links[0].from_node.type == 'UVMAP'
                and links[0].from_node.uv_map == 'PaletteUV', tag + '：Vector 确实由 PaletteUV 驱动')
    return role


def inspect_style(col, entry, planned, points, scope):
    label = scope + '/' + entry['key']
    kind = planned.get('kind')
    require(isinstance(kind, str) and kind, label + '：计划 kind 非空')
    require(kind in {'plant', 'soft'} or finite_number(planned.get('rho')),
            label + '：非 soft/plant 计划 rho 为有限数值')
    if kind in {'plant', 'soft'}:
        require(abs(float(planned.get('rho', 0.0))) <= TOL, label + '：soft/plant 计划 rho 为0')
    else:
        require(abs(float(planned.get('rho', 0.0))) > TOL, label + '：刚性组件计划 rho 非0')
    if kind == 'linear':
        d0, d1 = planned.get('d_bottom'), planned.get('d_top')
        require(finite_number(d0) and finite_number(d1) and d0 > 0 and d1 > 0,
                label + '：linear 计划 d_bottom/d_top 有效')
        if finite_number(d0) and d0:
            require(abs(float(planned.get('rho')) - (d0 - d1) / d0) <= TOL,
                    label + '：linear 计划 rho 与 d_bottom/d_top 一致')
    audit = REPORT.get('actual_form_audit', {})
    records = audit.get('records_by_component', {}).get(entry['key'], [])
    actual_rhos = [r.get('actual_rho') for r in records if finite_number(r.get('actual_rho'))]
    evidence = {'kind': kind, 'planned_rho': planned.get('rho'), 'audit_records': len(records),
                'actual_rhos': actual_rhos, 'mesh_form_verified': bool(records)}
    if kind in {'plant', 'soft'}:
        evidence['rigid_form_check'] = False
        REPORT['pending'].setdefault('soft_plant_visual_check', []).append({
            'key': entry['key'], 'kind': kind,
            'reason': 'soft/plant 不以 rigid rho 放行，需目视确认实际形态',
        })
    if scope == '主源' and kind not in {'plant', 'soft'}:
        REPORT['visual_review_evidence'].append({
            'key': entry['key'], 'kind': kind, 'actual_rhos': actual_rhos,
            'reason': '实际逐 mesh form audit 已核对；仍需主 agent 目视确认收分/扩张及线性件直径',
        })
    return evidence


def inspect(col, entry, planned, palette, scope, material_cache):
    """沿用 gift_kiosk 的逐面、底心、包络验收，所有测量来自实际数据。"""
    label = scope + '/' + entry['key']
    if not require(col is not None, label + '：collection 存在'):
        return None
    require(col.library is None, label + '：组件为本地 collection')
    require(col.instance_offset.length <= TOL, label + '：collection instance_offset 为零')
    objects = list(col.all_objects)
    require(bool(objects) and all(o.type == 'MESH' for o in objects), label + '：组件仅包含非空网格对象')
    meshes = [o for o in objects if o.type == 'MESH']
    points, geometry = [], []
    roles = set()
    triangles = polygons = 0
    for obj in meshes:
        tag = label + '/' + obj.name
        require(obj.library is None and obj.data.library is None, tag + '：无外链网格')
        require(identity(obj.matrix_world) and identity(obj.matrix_basis)
                and identity(obj.matrix_local), tag + '：网格变换 identity，容差 2e-5')
        mesh = obj.data
        require(all(math.isfinite(c) for v in mesh.vertices for c in v.co), tag + '：有限顶点坐标')
        vertices = [tuple(v.co) for v in mesh.vertices]
        points.extend(vertices)
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        polygons += len(mesh.polygons)
        require(bool(mesh.vertices) and bool(mesh.polygons), tag + '：非空网格')
        uv = mesh.uv_layers.get('PaletteUV')
        require(len(mesh.uv_layers) == 1 and uv is not None
                and mesh.uv_layers.active == uv, tag + '：唯一 active PaletteUV')
        require(uv is not None and uv.active_render, tag + '：render PaletteUV')
        slot_roles = [inspect_material(slot.material, tag + '/材质' + str(i), palette, material_cache)
                      for i, slot in enumerate(obj.material_slots)]
        roles.update(slot_roles)
        for face in mesh.polygons:
            require(face.material_index < len(slot_roles) and bool(slot_roles[face.material_index]),
                    tag + '/面' + str(face.index) + '：有效材质索引')
            if uv is None:
                continue
            REPORT['uv_faces_checked'] += 1
            coords = [tuple(uv.data[i].uv) for i in face.loop_indices]
            face_label = tag + '/面' + str(face.index)
            if not require(all(math.isfinite(c) for point in coords for c in point), face_label + '：有限 UV'):
                continue
            area = abs(sum(a[0] * b[1] - b[0] * a[1]
                           for a, b in zip(coords, coords[1:] + coords[:1]))) * .5
            require(area > 1e-9, face_label + '：UV 面积 > 1e-9')
            cells = {(math.floor(u * 8), math.floor(v * 8)) for u, v in coords}
            valid_cell = len(cells) == 1 and all(0 <= c < 8 for cell in cells for c in cell)
            require(valid_cell, face_label + '：全部 loop 位于同一有效 8×8 色格')
            if valid_cell:
                cx, cy = next(iter(cells))
                require(all(cx * 64 + 8 - 1e-5 <= u * 512 <= (cx + 1) * 64 - 8 + 1e-5
                            and cy * 64 + 8 - 1e-5 <= v * 512 <= (cy + 1) * 64 - 8 + 1e-5
                            for u, v in coords), face_label + '：色格边缘至少 8px')
        geometry.append({
            'vertices': vertices,
            'edges': [tuple(edge.vertices) for edge in mesh.edges],
            'faces': [tuple(face.vertices) for face in mesh.polygons],
            'material_roles': slot_roles,
            'face_materials': [face.material_index for face in mesh.polygons],
            'uv': [tuple(loop.uv) for loop in uv.data] if uv else None,
        })
    require(bool(points) and triangles > 0, label + '：实际几何非空')
    bounds = None
    if points and all(math.isfinite(v) for point in points for v in point):
        low = [min(v[i] for v in points) for i in range(3)]
        high = [max(v[i] for v in points) for i in range(3)]
        bounds = [high[i] - low[i] for i in range(3)]
        require(abs(low[2]) <= TOL and abs(low[0] + high[0]) <= TOL
                and abs(low[1] + high[1]) <= TOL, label + '：底心原点')
        require(vector_matches(bounds, entry['bounds_size']), label + '：实际包络与 catalog 一致')
    for field, actual in (('triangles', triangles), ('polygons', polygons), ('meshes', len(meshes))):
        require(type(entry[field]) is int and actual == entry[field], label + '：实际 ' + field + ' 与 catalog 一致')
    require(sorted(roles) == sorted(entry['material_roles']), label + '：实际材质角色与 catalog 一致')
    # catalog 已明确指定算法：按 collection.objects、每 object.data.vertices 的真实顺序串流更新 SHA256。
    signature = ordered_vertices_fixed6_sha256(col)
    full_signature = geometry_uv_topology_roles_sha256(col)
    recorded_fingerprint = entry['geometry_fingerprint']
    recorded_algorithm = entry.get('fingerprint_algorithm')
    require(recorded_algorithm == FINGERPRINT_ALGORITHM,
            label + '：catalog fingerprint_algorithm 为 ' + FINGERPRINT_ALGORITHM)
    require(isinstance(recorded_fingerprint, str) and len(recorded_fingerprint) == 64
            and all(c in '0123456789abcdefABCDEF' for c in recorded_fingerprint), label + '：catalog geometry_fingerprint 为 SHA256')
    matched_algorithm = FINGERPRINT_ALGORITHM if signature == str(recorded_fingerprint).lower() else None
    require(signature == str(recorded_fingerprint).lower(), label + '：ordered_vertices_fixed6_sha256 实际重算一致')
    if 'geometry_fingerprint' in col:
        require(col['geometry_fingerprint'] == recorded_fingerprint, label + '：collection 摘要与 catalog 一致')
    if 'fingerprint_algorithm' in col:
        require(col['fingerprint_algorithm'] == FINGERPRINT_ALGORITHM,
                label + '：collection fingerprint_algorithm 一致')
    if matched_algorithm is None:
        REPORT['pending']['fingerprint_review'].append({
            'key': entry['key'], 'catalog_fingerprint': recorded_fingerprint,
            'actual_ordered_vertices_fixed6_sha256': signature,
            'reason': '实际指纹与 catalog 不匹配；需制作方核实',
        })
    style = inspect_style(col, entry, planned, points, scope)
    return {'key': entry['key'], 'asset_id': entry['asset_id'], 'scope': scope,
            'triangles': triangles, 'polygons': polygons, 'meshes': len(meshes),
            'bounds_size': bounds, 'material_roles': sorted(roles),
                'geometry_uv_roles_sha256': full_signature,
            'ordered_vertices_fixed6_sha256': signature,
            'catalog_fingerprint_algorithm': FINGERPRINT_ALGORITHM,
            'fingerprint_match': matched_algorithm == FINGERPRINT_ALGORITHM,
            'style': style}


def expand_scene(scene, entries, rows):
    by_key = {e['key']: e for e in entries}
    by_collection = {e['collection']: e for e in entries}
    marked = marked_support_collections(scene)
    actual = {o.name: o for o in scene.objects if o.instance_type == 'COLLECTION'
              and not support_object(o, marked)}
    require(len(actual) == len(rows), '主源：实例数量与 component_instances.json 一致')
    require(set(actual) == {row['name'] for row in rows}, '主源：实例名称集合完整一致')
    mesh_owners = {}
    for entry in entries:
        col = bpy.data.collections.get(entry['collection'])
        if col:
            for obj in col.all_objects:
                if obj.type == 'MESH':
                    require(obj.as_pointer() not in mesh_owners, obj.name + '：仅属于一个主组件')
                    mesh_owners[obj.as_pointer()] = entry['key']
    visible = set()
    for row in rows:
        name = row['name']
        obj = actual.get(name)
        if not require(obj is not None, name + '：实例存在'):
            continue
        entry = by_key.get(row['key'])
        if not require(entry is not None, name + '：实例引用实际 catalog key'):
            continue
        require(row['asset_id'] == entry['asset_id'], name + '：实例 asset_id 一致')
        require(obj.instance_collection is not None and obj.instance_collection.name == entry['collection'],
                name + '：实际引用正确母版 collection')
        require(vector_matches(obj.location, row['position']), name + '：position 一致')
        require(obj.rotation_mode == 'XYZ', name + '：XYZ 欧拉角契约')
        require(vector_matches(obj.rotation_euler, row['rotation_euler_xyz']), name + '：rotation_euler_xyz 一致')
        require(vector_matches(obj.scale, row['scale']), name + '：scale 一致')
        require(all(math.isfinite(v) for matrix_row in obj.matrix_world for v in matrix_row), name + '：有限世界变换')
        require(abs(obj.matrix_world.determinant()) > 1e-12, name + '：非退化实例变换')
        # 坐标声明不静默猜测为世界坐标：同时记录世界矩阵，定位父级变换问题。
        REPORT['instance_results'].append({
            'name': name, 'key': row['key'], 'asset_id': row['asset_id'],
            'world_matrix': [list(r) for r in obj.matrix_world],
        })
    counts = {name: {'triangles': 0, 'polygons': 0, 'meshes': 0} for name in actual}
    union = set()
    ignored = Counter()
    for layer in scene.view_layers:
        with bpy.context.temp_override(scene=scene, view_layer=layer):
            depsgraph = bpy.context.evaluated_depsgraph_get()
            depsgraph.update()
            for name, obj in actual.items():
                if obj.visible_get(view_layer=layer) and not obj.hide_render:
                    visible.add(name)
            occurrences = Counter()
            for instance in depsgraph.object_instances:
                obj = instance.object
                original = obj.original
                parent = instance.parent.original if instance.parent else None
                if support_object(original, marked) or support_object(parent, marked):
                    ignored['display_support'] += 1
                    continue
                if not instance.show_self or obj.hide_render or (parent and parent.hide_render):
                    ignored['not_visible'] += 1
                    continue
                if obj.type != 'MESH':
                    if obj.type not in {'EMPTY', 'CAMERA', 'LIGHT', 'SPEAKER', 'LIGHT_PROBE'}:
                        require(False, original.name + '：未标 display_support 的非网格几何，不能静默漏计 ' + obj.type)
                    continue
                if not instance.is_instance and not original.visible_get(view_layer=layer):
                    ignored['not_visible'] += 1
                    continue
                if instance.is_instance and parent and parent.name in actual and not parent.visible_get(view_layer=layer):
                    ignored['hidden_instancer'] += 1
                    continue
                signature = (original.as_pointer(), parent.as_pointer() if parent else 0,
                             bool(instance.is_instance), tuple(instance.persistent_id),
                             tuple(v for r in instance.matrix_world for v in r))
                occurrence = occurrences[signature]
                occurrences[signature] += 1
                token = (signature, occurrence)
                if token in union:
                    continue
                union.add(token)
                # 每一依赖图展开条目单独累加；绝不按 mesh 数据块或母版去重。
                mesh = obj.to_mesh()
                try:
                    if not require(mesh is not None, original.name + '：可求值实际网格'):
                        continue
                    mesh.calc_loop_triangles()
                    triangles, polygons = len(mesh.loop_triangles), len(mesh.polygons)
                    REPORT['expanded_triangles'] += triangles
                    REPORT['expanded_polygons'] += polygons
                    owner = parent.name if instance.is_instance and parent and parent.name in actual else None
                    require(owner is not None, original.name + '：非展示几何必须归属已登记的可见组件实例')
                    if owner:
                        counts[owner]['triangles'] += triangles
                        counts[owner]['polygons'] += polygons
                        counts[owner]['meshes'] += 1
                        col = actual[owner].instance_collection
                        entry = by_collection.get(col.name) if col else None
                        require(entry is not None and mesh_owners.get(original.as_pointer()) == entry['key'],
                                owner + '/' + original.name + '：展开网格归属正确组件')
                finally:
                    obj.to_mesh_clear()
    expected_triangles = expected_polygons = 0
    instance_counts = Counter()
    for name, obj in actual.items():
        col = obj.instance_collection
        entry = by_collection.get(col.name) if col else None
        if name not in visible:
            require(counts[name]['meshes'] == 0, name + '：隐藏实例没有误计几何')
            continue
        if not require(entry is not None, name + '：可见实例有 catalog 定义'):
            continue
        instance_counts[entry['key']] += 1
        expected_triangles += entry['triangles']
        expected_polygons += entry['polygons']
        for field in ('triangles', 'polygons', 'meshes'):
            require(counts[name][field] == entry[field], name + '：依赖图实际 ' + field + ' 与单实例 catalog 一致')
    for result in REPORT['instance_results']:
        result.update(counts[result['name']], visible=result['name'] in visible)
    REPORT.update(visible_instances=len(visible), visible_instance_counts=dict(instance_counts),
                  expected_expanded_triangles=expected_triangles, expected_expanded_polygons=expected_polygons,
                  ignored_dependency_entries=dict(ignored))
    require(bool(visible), '主源：至少有一个可见组件实例')
    require(REPORT['expanded_triangles'] == expected_triangles, '主源：全依赖图三角形等于 catalog triangles × 每组件可见实例数之和')
    require(REPORT['expanded_polygons'] == expected_polygons, '主源：全依赖图多边形等于 catalog polygons × 每组件可见实例数之和')


def verify_main(entries, planned, rows, palette):
    open_readonly(SOURCE)
    scene = bpy.data.scenes.get(SCENE_NAME)
    require(len(bpy.data.scenes) == 1 and scene is not None, '主源：仅有指定的自有场景 ' + SCENE_NAME)
    if scene is None:
        return
    require(bpy.context.scene == scene, '主源：指定场景为启动场景')
    linked = {col.as_pointer() for col in collection_tree(scene.collection)}
    materials = set()
    for entry in entries:
        col = bpy.data.collections.get(entry['collection'])
        if col:
            require(col.as_pointer() not in linked, entry['key'] + '：母版 collection 未直接链接进主场景')
            require(any(o.instance_type == 'COLLECTION' and o.instance_collection == col for o in scene.objects),
                    entry['key'] + '：母版被场景实例引用')
        try:
            result = inspect(col, entry, planned[entry['key']], palette, '主源', materials)
            if result:
                REPORT['component_results'].append(result)
                REPORT['master_triangles'] += result['triangles']
        except Exception:
            require(False, entry['key'] + '：主源检查异常\n' + traceback.format_exc())
    REPORT['master_polygons'] = sum(r['polygons'] for r in REPORT['component_results'])
    require(REPORT['master_triangles'] == sum(e['triangles'] for e in entries),
            '主源：' + str(len(entries)) + ' 母版实际三角形总和与 catalog 一致')
    expand_scene(scene, entries, rows)


def load_visual_review(source_sha256, required_keys):
    review_path = W / 'visual_review.json'
    result = {'path': str(review_path), 'loaded': False, 'valid': False,
              'source_sha256_match': False, 'passed': False,
              'reviewed_component_keys': [], 'missing_component_keys': list(required_keys)}
    if not review_path.is_file():
        result['reason'] = '不存在主 agent 目视签署文件'
        return result
    try:
        review = read_json(review_path)
        result['loaded'] = True
        reviewed = review.get('reviewed_component_keys', [])
        result['reviewed_component_keys'] = reviewed if isinstance(reviewed, list) else []
        result['source_sha256_match'] = review.get('source_sha256') == source_sha256
        result['passed'] = review.get('passed') is True
        result['missing_component_keys'] = sorted(set(required_keys) - set(result['reviewed_component_keys']))
        result['extra_component_keys'] = sorted(set(result['reviewed_component_keys']) - set(required_keys))
        result['duplicate_component_keys'] = sorted(key for key, count in Counter(result['reviewed_component_keys']).items()
                                                    if count > 1)
        result['valid'] = (result['source_sha256_match'] and result['passed']
                           and not result['missing_component_keys']
                           and not result['extra_component_keys']
                           and not result['duplicate_component_keys'])
        result['reason'] = 'source_sha256、passed、reviewed_component_keys 均满足' if result['valid'] else '目视签署字段未满足放行条件'
    except Exception:
        result['reason'] = '目视签署文件无法读取或不是有效 JSON：' + traceback.format_exc()
    return result


def verify_visual_review(source_sha256, planned):
    required_keys = sorted(planned)
    REPORT['nonzero_rho_keys'] = sorted(key for key, item in planned.items()
                                        if finite_number(item.get('rho')) and abs(item['rho']) > TOL)
    review = load_visual_review(source_sha256, required_keys)
    REPORT['visual_review'] = review
    if not review['valid']:
        REPORT['pending']['visual_review'].append({
            'required_component_keys': required_keys,
            'reason': review.get('reason', '缺少有效主 agent 目视签署'),
            'visual_review_path': review['path'],
        })
    require(review['valid'], '主 agent 目视签署：source_sha256 匹配、passed=true 且完整包含全部49项组件')


def finite_values(value):
    if isinstance(value, (list, tuple)):
        return bool(value) and all(finite_values(item) for item in value)
    if isinstance(value, dict):
        return bool(value) and all(finite_values(item) for item in value.values())
    return finite_number(value)


def load_actual_form_audit(source_sha256, entries, planned):
    path = W / 'actual_form_audit.json'
    result = {'path': str(path), 'loaded': False, 'valid': False,
              'source_sha256_match': False, 'passed': False, 'checked_meshes': 0,
              'errors': [], 'records': [], 'records_by_component': {}}
    if not path.is_file():
        require(False, 'actual_form_audit.json：文件不存在')
        REPORT['actual_form_audit'] = result
        return result
    try:
        audit = read_json(path)
        result['loaded'] = True
        result['source_sha256_match'] = audit.get('source_sha256') == source_sha256
        result['passed'] = audit.get('passed') is True
        result['checked_meshes'] = audit.get('checked_meshes')
        result['errors'] = audit.get('errors', [])
        result['records'] = audit.get('records', [])
        require(result['source_sha256_match'], 'actual_form_audit：source_sha256 与主源不一致')
        require(result['passed'], 'actual_form_audit：passed 必须为 true')
        require(isinstance(result['errors'], list) and not result['errors'],
                'actual_form_audit：errors 必须为空')
        require(isinstance(result['records'], list), 'actual_form_audit：records 必须为 list')
        require(type(result['checked_meshes']) is int and result['checked_meshes'] == len(result['records']),
                'actual_form_audit：checked_meshes 必须等于 records 数量')
        expected_counts = {entry['key']: entry['meshes'] for entry in entries}
        by_component = {key: [] for key in planned}
        for index, record in enumerate(result['records'] if isinstance(result['records'], list) else []):
            label = 'actual_form_audit/records[' + str(index) + ']'
            require(isinstance(record, dict), label + '：record 必须为对象')
            key = record.get('component_key', record.get('key')) if isinstance(record, dict) else None
            require(key in by_component, label + '：component_key 必须属于49项计划')
            require(isinstance(record.get('mesh_name', record.get('mesh')), str)
                    and record.get('mesh_name', record.get('mesh')), label + '：mesh_name 非空')
            require(record.get('planned_kind') == planned.get(key, {}).get('kind'),
                    label + '：planned_kind 与 component_plan 一致')
            require(finite_number(record.get('actual_rho')), label + '：actual_rho 为有限数值')
            require(isinstance(record.get('axis'), str) and record.get('axis') in {'x', 'y', 'z'},
                    label + '：axis 为 x/y/z')
            require(finite_values(record.get('dimensions')), label + '：dimensions 为有限实际测量')
            if key in by_component:
                by_component[key].append(record)
                kind = planned[key].get('kind')
                actual_rho = float(record['actual_rho'])
                if kind in {'plant', 'soft'}:
                    require(abs(actual_rho) <= TOL, label + '：soft/plant actual_rho 必须为0')
                else:
                    require(abs(actual_rho) > TOL, label + '：非 soft/plant actual_rho 必须非0')
                if kind == 'linear':
                    dims = record.get('dimensions')
                    d0 = record.get('d_bottom')
                    d1 = record.get('d_top')
                    if isinstance(dims, dict):
                        d0 = dims.get('d_bottom', dims.get('d0', d0))
                        d1 = dims.get('d_top', dims.get('d1', d1))
                    elif isinstance(dims, (list, tuple)) and len(dims) >= 2:
                        d0, d1 = dims[0], dims[1]
                    require(finite_number(d0) and finite_number(d1) and d0 > 0 and d1 > 0,
                            label + '：linear 实际 d0/d1 有效')
                    if finite_number(d0) and d0:
                        require(abs(actual_rho - (d0 - d1) / d0) <= TOL,
                                label + '：linear actual_rho 与实际 d0/d1 一致')
        for key, records in by_component.items():
            require(len(records) == expected_counts.get(key),
                    'actual_form_audit：' + key + ' records 数量等于 catalog meshes')
            names = [r.get('mesh_name', r.get('mesh')) for r in records]
            require(len(names) == len(set(names)), 'actual_form_audit：' + key + ' mesh_name 唯一')
        result['records_by_component'] = by_component
        result['valid'] = (result['source_sha256_match'] and result['passed']
                           and not result['errors'] and isinstance(result['records'], list)
                           and type(result['checked_meshes']) is int)
    except Exception:
        require(False, 'actual_form_audit：无法读取或校验\n' + traceback.format_exc())
    REPORT['actual_form_audit'] = result
    return result


def verify_package(entry, planned, palette, path):
    open_readonly(path)
    REPORT['packages_reopened'] += 1
    label = '独立包/' + entry['key']
    col = bpy.data.collections.get(entry['collection'])
    scene = bpy.context.scene
    require(scene is not None and len(scene.objects) > 0, label + '：启动场景非空')
    objects = list(col.all_objects) if col else []
    component_meshes = {o.as_pointer() for o in objects if o.type == 'MESH'}
    all_meshes = {o.as_pointer() for o in bpy.data.objects if o.type == 'MESH'}
    require(bool(component_meshes) and all_meshes == component_meshes, label + '：文件仅有本组件网格')
    require({m.as_pointer() for m in bpy.data.meshes} == {o.data.as_pointer() for o in objects if o.type == 'MESH'},
            label + '：无其它组件或孤立网格数据块')
    if scene:
        require(col is not None and any(c == col for c in collection_tree(scene.collection)), label + '：本组件链接到启动场景')
        scene_meshes = [o for o in scene.objects if o.type == 'MESH']
        require({o.as_pointer() for o in scene_meshes} == component_meshes, label + '：启动场景展示完整本组件')
        require(bool(scene_meshes) and any(not o.hide_render and o.visible_get(view_layer=layer)
                                          for o in scene_meshes for layer in scene.view_layers), label + '：启动场景有可见组件网格')
    result = inspect(col, entry, planned, palette, '独立包', set())
    if result:
        REPORT['package_results'].append(result)
        master = next((r for r in REPORT['component_results'] if r['key'] == entry['key']), None)
        require(master is not None and result['geometry_uv_roles_sha256'] == master['geometry_uv_roles_sha256'],
                label + '：包内实际顶点、拓扑、逐面 UV 与材质角色和主源一致')
        require(master is not None and result['ordered_vertices_fixed6_sha256'] == master['ordered_vertices_fixed6_sha256'],
                label + '：包内 ordered_vertices_fixed6_sha256 与主源一致')
        require(master is not None and result['bounds_size'] == master['bounds_size'],
                label + '：包与主源实际 Bounds 一致')
        require(result['catalog_fingerprint_algorithm'] == FINGERPRINT_ALGORITHM
                and result['fingerprint_match'],
                label + '：catalog 几何摘要按指定算法真实复算一致')


def main():
    palette = None
    originals = {}
    package_paths = []
    try:
        if not bpy.app.background:
            raise RuntimeError('仅允许独立 --background 进程运行；不会操作 GUI 或 9876 会话')
        if not SOURCE.is_file():
            raise FileNotFoundError('主源尚不存在：' + str(SOURCE))
        originals[SOURCE] = sha(SOURCE)
        REPORT['source_sha256'] = originals[SOURCE]
        plan = read_json(D / 'component_plan.json')
        palette = root_path(plan['palette'])
        originals[palette] = sha(palette)
        REPORT['palette_sha256'] = originals[palette]
        REPORT['palette_path'] = str(palette)
        catalog = read_json(D / 'catalog.json')
        entries = catalog['components']
        if isinstance(entries, dict) and isinstance(entries.get('components'), list):
            entries = entries['components']
        budget = plan.get('component_budget', {})
        planned_count = budget.get('planned')
        budget_limit = budget.get('limit', 50)
        require(type(planned_count) is int and planned_count == 49, '计划：component_budget.planned 必须为49')
        require(type(budget_limit) is int and budget_limit > 0, '计划：component_budget.limit 为正整数')
        require(type(budget_limit) is int and budget_limit <= 50, '计划：component_budget.limit 不超过50')
        require(type(planned_count) is int and type(budget_limit) is int and planned_count <= 50
                and planned_count <= budget_limit, '计划：planned 不超过50且不超过组件预算 limit')
        require(isinstance(entries, list) and len(entries) == planned_count,
                'catalog：实际 components list 数量等于 plan.component_budget.planned=' + str(planned_count))
        if not isinstance(entries, list):
            raise ValueError('catalog.components 必须为 list')
        REPORT['components'] = len(entries)
        REPORT['component_budget'] = {'planned': planned_count, 'limit': budget_limit,
                                      'catalog_count': len(entries)}
        required = {'key', 'asset_id', 'group', 'collection', 'component_source', 'bounds_size',
                    'triangles', 'polygons', 'meshes', 'material_roles', 'geometry_fingerprint',
                    'fingerprint_algorithm', 'source_sha256'}
        for entry in entries:
            if not require(isinstance(entry, dict) and required <= set(entry), 'catalog：组件字段完整'):
                raise ValueError('catalog 组件缺少必需字段')
            require(all(isinstance(entry[f], str) and entry[f] for f in ('key', 'asset_id', 'group', 'collection', 'component_source', 'fingerprint_algorithm')),
                    'catalog：组件身份、路径及 fingerprint_algorithm 字段为非空字符串')
            require(entry['fingerprint_algorithm'] == FINGERPRINT_ALGORITHM,
                    entry['key'] + '：catalog 使用指定 fingerprint_algorithm')
            require(all(type(entry[f]) is int and entry[f] > 0 for f in ('triangles', 'polygons', 'meshes')),
                    entry['key'] + '：catalog 几何统计为正整数')
            require(isinstance(entry['material_roles'], list) and bool(entry['material_roles'])
                    and all(role in ROLES for role in entry['material_roles']), entry['key'] + '：catalog 材质角色合法')
        for field in ('key', 'asset_id', 'collection'):
            require(len({e[field] for e in entries}) == len(entries), 'catalog：' + field + ' 唯一')
        planned = {c['key']: c for c in plan['components']}
        require(len(planned) == planned_count and set(planned) == {e['key'] for e in entries},
                '计划与实际 catalog 的 ' + str(planned_count) + ' 项 key 一致')
        require(all(c.get('asset_id') == 'SEA-SCENE-B1109A-' + c['key'].upper()
                    for c in plan['components']), 'v002 计划复用 v001 stable AssetID，不带 V002')
        try:
            v1_entries = read_json(V1_CATALOG)['components']
            require({c['key']: c['asset_id'] for c in plan['components']} ==
                    {c['key']: c['asset_id'] for c in v1_entries},
                    'v002 49 个 AssetID 与 v001 stable IDs 完全一致')
        except Exception:
            require(False, '无法读取 v001 catalog 以核对 stable AssetID')
        family_counts = Counter(c.get('component_family', c.get('family')) for c in plan['components'])
        REPORT['family_counts'] = dict(family_counts)
        for family, count in family_counts.items():
            require(family and count <= 3, '计划同族不超过3：' + str(family) + '=' + str(count))
        for entry in entries:
            p = planned.get(entry['key'])
            require(p is not None and p.get('asset_id', p.get('id')) == entry['asset_id']
                    and p.get('group') == entry['group'], entry['key'] + '：计划 asset_id/group 一致')
            path = root_path(entry['component_source'])
            require(path.suffix.lower() == '.blend' and path != SOURCE, entry['key'] + '：独立 .blend 组件包路径')
            package_paths.append(path)
            if path.is_file():
                originals[path] = sha(path)
                require(originals[path] == entry['source_sha256'], entry['key'] + '：实际包 SHA256 matches catalog')
            else:
                require(False, entry['key'] + '：组件包文件不存在 ' + str(path))
        require(len(set(package_paths)) == len(entries),
                'catalog：' + str(len(entries)) + ' 个独立组件包路径唯一')
        layout = read_json(D / 'component_instances.json')
        rows = layout['instances']
        if not require(isinstance(rows, list), '实例文件：instances 为 list'):
            raise ValueError('instances 必须为 list')
        REPORT['instances'] = len(rows)
        contract = layout.get('coordinate_contract')
        REPORT['coordinate_contract'] = contract
        require(bool(contract) and isinstance(contract, (str, dict)), '实例文件：声明 coordinate_contract')
        # 这里只核对 XYZ 本地 TRS 原始字段；坐标契约原文随报告保存，不臆造未声明的世界坐标规则。
        REPORT['instance_transform_contract'] = 'position/rotation_euler_xyz/scale 对应 Blender 本地 XYZ TRS；实际 world_matrix 另行记录'
        for row in rows:
            if not require(isinstance(row, dict) and {'name', 'key', 'asset_id', 'position', 'rotation_euler_xyz', 'scale'} <= set(row),
                           '实例文件：实例字段完整'):
                raise ValueError('实例缺少必需字段')
        require(len({row['name'] for row in rows}) == len(rows), '实例文件：实例 name 唯一，实例数不写死')
        load_actual_form_audit(originals[SOURCE], entries, planned)
        require(REPORT['actual_form_audit'].get('valid') is True,
                'actual_form_audit：passed、哈希、checked_meshes、records 与逐 mesh 规则全部满足')
        verify_visual_review(originals[SOURCE], planned)
        try:
            verify_main(entries, planned, rows, palette)
        except Exception:
            require(False, '主源独立检查异常，继续重开其余组件包\n' + traceback.format_exc())
        for entry, path in zip(entries, package_paths):
            if not path.is_file():
                continue
            try:
                verify_package(entry, planned[entry['key']], palette, path)
            except Exception:
                require(False, entry['key'] + '：独立包重开检查异常\n' + traceback.format_exc())
        require(REPORT['packages_reopened'] == planned_count,
                str(planned_count) + ' 个实际组件包全部独立重开')
        require(len(REPORT['component_results']) == planned_count
                and len(REPORT['package_results']) == planned_count,
                '主源和 ' + str(planned_count) + ' 个包均完成 inspect')
    except Exception:
        require(False, '验收中断\n' + traceback.format_exc())
    finally:
        # 即使中途失败也复查文件；不修复、不重存、不回写 catalog/manifest。
        REPORT['file_integrity'] = []
        for path, before in originals.items():
            try:
                after = sha(path)
                unchanged = after == before
                require(unchanged, '只读前后 SHA256 不变：' + str(path))
                REPORT['file_integrity'].append({'path': str(path), 'before': before, 'after': after, 'unchanged': unchanged})
            except Exception as exc:
                require(False, '无法复查文件完整性：' + str(path) + '：' + str(exc))
        REPORT['source_sha256_after'] = next((r['after'] for r in REPORT['file_integrity'] if r['path'] == str(SOURCE)), None)
        REPORT['palette_sha256_after'] = next((r['after'] for r in REPORT['file_integrity'] if palette and r['path'] == str(palette)), None)
        blocking = bool(REPORT['pending']['visual_review'] or REPORT['pending']['fingerprint_review'])
        REPORT['technical_passed'] = not REPORT['errors']
        REPORT['passed'] = REPORT['technical_passed'] and not blocking
        REPORT['exit_code'] = 1 if REPORT['errors'] else (2 if blocking else 0)
        REPORT['status'] = 'failed' if REPORT['errors'] else ('pending_review' if blocking else 'source_verified_runtime_pending')
        W.mkdir(parents=True, exist_ok=True)
        (W / 'source_verification.json').write_text(json.dumps(REPORT, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        print('BLDA_SOURCE_VERIFICATION ' + json.dumps({k: REPORT[k] for k in (
            'passed', 'technical_passed', 'checks', 'packages_reopened', 'components', 'instances',
            'visible_instances', 'master_triangles', 'expanded_triangles', 'expanded_polygons', 'exit_code', 'status')}, ensure_ascii=False), flush=True)
        print('报告：' + str(W / 'source_verification.json'), flush=True)
    return REPORT['exit_code']


if __name__ == '__main__':
    sys.exit(main())
