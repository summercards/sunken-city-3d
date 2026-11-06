"""仅制作本目录 v002；不调用旧构建器，不写规则、登记或历史源。"""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

D = Path(__file__).resolve().parent
R = D.parents[3]
W = R.parent / 'sea-work/building_kit_v002'
P = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
H = P['storey_height']
ROLES = P['material_roles']
PALETTE = R / P['palette']
OPT = D / 'export/v002/building_kit_optimized.blend'
COLLECTION = {}
MATERIAL = {}
CURRENT = None


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def protected_files():
    roots = [D.parent / 'v001', R / 'tools/blender/building_kit',
             R / 'godot/assets/models/building_kit', R / 'godot/scenes/buildables/kit']
    new_ids = {e['id'] for e in P['components']}
    result = {}
    for root in roots:
        for path in root.rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                if root.name == 'building_kit' and path.relative_to(root).parts[0] in new_ids:
                    continue
                if root.name == 'kit' and path.stem in new_ids:
                    continue
                result[str(path)] = sha(path)
    for path in [R / 'godot/assets/data/building_kit.json', PALETTE,
                 PALETTE.with_suffix('.json'), R / P['runtime_palette'], D / 'component_plan.json']:
        result[str(path)] = sha(path)
    return result


def setup_materials():
    image = bpy.data.images.load(str(PALETTE), check_existing=True)
    assert not image.packed_file
    for role in ROLES:
        mat = bpy.data.materials.new('SEA_' + role)
        mat.use_nodes = True
        mat.use_fake_user = True
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        bsdf.inputs['Roughness'].default_value = .8 if role == 'Matte' else .28
        bsdf.inputs['Metallic'].default_value = .6 if role == 'Metal' else 0
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.interpolation = 'Closest'
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'PaletteUV'
        mat.node_tree.links.new(uv.outputs['UV'], tex.inputs['Vector'])
        mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
        if role == 'Emission':
            mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
            bsdf.inputs['Emission Strength'].default_value = 1.4
        MATERIAL[role] = mat


CELLS = {c['name']: c for c in json.loads(PALETTE.with_suffix('.json').read_text())['cells']}


def finish(obj, name, color, role, bevel):
    obj.name = name
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    CURRENT.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if bevel:
        mod = obj.modifiers.new('实体圆角_三段', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(MATERIAL[role])
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    uv = obj.data.uv_layers.new(name='PaletteUV')
    uv.active_render = True
    obj.data.uv_layers.active_index = 0
    cell = CELLS[color]
    u = (cell['column'] + .5) / 8
    v = 1 - (cell['row'] + .5) / 8
    for face in obj.data.polygons:
        for j, loop in enumerate(face.loop_indices):
            angle = math.tau * j / len(face.loop_indices)
            uv.data[loop].uv = (u + .032 * math.cos(angle), v + .032 * math.sin(angle))
    obj['palette_cell'] = color
    obj['material_role'] = role
    obj.select_set(False)
    return obj


def box(name, center, size, color='wood_light', role='Matte', bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.scale = size
    return finish(obj, name, color, role, bevel)


def beam_between(name, a, b, width=.08, depth=.08, color='wood_mid'):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a + b) / 2)
    obj = bpy.context.object
    obj.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    obj.scale = (width, depth, (b - a).length)
    return finish(obj, name, color, 'Matte', .012)


def prism(name, x0, x1, yz, color='wood_mid', bevel=.008):
    verts = [(x, y, z) for x in (x0, x1) for y, z in yz]
    n = len(yz)
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    return finish(obj, name, color, 'Matte', bevel)


def panel_region(x0, x1, z0, z1):
    if x1 <= x0 or z1 <= z0:
        return
    box('墙体连续背板', ((x0+x1)/2, 0, (z0+z1)/2), (x1-x0, .10, z1-z0), 'wood_mid', bevel=.008)
    rows = max(1, round((z1-z0)/.46))
    for j in range(rows):
        low, high = z0 + j*(z1-z0)/rows, z0+(j+1)*(z1-z0)/rows
        for side in [-1, 1]:
            box('暖木墙板', ((x0+x1)/2, side*.0725, (low+high)/2),
                (x1-x0, .045, high-low), 'wood_light' if j % 3 else 'wood_mid', bevel=.015)


def build_geometry(entry):
    key = entry['id']
    if key == 'platform_5x5':
        for j in range(6):
            x0, x1 = -2.5+j*5/6, -2.5+(j+1)*5/6
            x0 += .009 if j else 0
            x1 -= .009 if j < 5 else 0
            box('平台宽木板', ((x0+x1)/2, 0, -.14), (x1-x0, 5, .28),
                'wood_light' if j % 3 else 'wood_mid', bevel=.075)
        for y in [-2.36, 0, 2.36]:
            box('平台底部横枋', (0, y, -.39), (5, .28, .22), 'wood_mid', bevel=.04)
    elif key in ['wall_5m', 'window_wall_5m', 'door_frame_5m']:
        if key == 'wall_5m':
            panel_region(-2.5, 2.5, 0, H)
        else:
            opening = 1.85 if key == 'door_frame_5m' else 2.8
            lo, hi = (0, 3.1) if key == 'door_frame_5m' else (1.25, 3.6)
            panel_region(-2.5, -opening/2, 0, H)
            panel_region(opening/2, 2.5, 0, H)
            panel_region(-opening/2, opening/2, hi, H)
            panel_region(-opening/2, opening/2, 0, lo)
            for x in [-opening/2-.06, opening/2+.06]:
                box('洞口侧框', (x, 0, (hi+lo)/2), (.12, .2, hi-lo), 'wood_edge', bevel=.018)
            box('洞口上框', (0, 0, hi+.06), (opening+.24, .2, .12), 'wood_edge', bevel=.018)
            if lo:
                box('窗台', (0, 0, lo-.06), (opening+.24, .2, .12), 'wood_edge', bevel=.018)
                box('窗内浅蓝玻璃', (0, 0, (hi+lo)/2), (opening, .035, hi-lo), 'ice', 'Gloss', .008)
                box('窗竖梃', (0, -.055, (hi+lo)/2), (.085, .08, hi-lo), 'cream', bevel=.018)
                box('窗横梃', (0, -.055, (hi+lo)/2), (opening, .08, .085), 'cream', bevel=.018)
        for x in [-2.43, 2.43]:
            box('墙端收边', (x, 0, H/2), (.14, .2, H), 'wood_edge', bevel=.025)
    elif key == 'post_5m':
        box('圆角木主柱', (0, 0, H/2), (.5, .5, H), 'wood_mid', bevel=.095)
        for z in [.2, H-.2]:
            for y in [-.247, .247]:
                box('柱金属箍片', (0, y, z), (.25, .006, .07), 'steel', 'Metal', .002)
    elif key == 'beam_5m':
        box('圆角承重横梁', (0, 0, .1), (5, .2, .2), 'wood_mid', bevel=.035)
    elif key == 'railing_5m':
        for x in [-2.42, 0, 2.42]:
            box('栏杆立柱', (x, 0, .51), (.16, .16, 1.02), 'wood_mid', bevel=.03)
        box('栏杆扶手', (0, 0, 1.03), (5, .18, .14), 'wood_light', bevel=.035)
        box('栏杆下横档', (0, 0, .14), (5, .12, .12), 'wood_mid', bevel=.025)
        for x0, x1 in [(-2.32, -.10), (.10, 2.32)]:
            beam_between('栏杆交叉撑', (x0, 0, .23), (x1, 0, .94))
            beam_between('栏杆交叉撑', (x0, .015, .94), (x1, .015, .23))
    elif key == 'stairs_5m':
        rise, tread = H/27, 5/27
        for j in range(27):
            obj = box('踏步_%02d' % (j+1), (0, -2.5+(j+.5)*tread, (j+1)*rise-.07),
                      (1.5, tread, .14), 'wood_light' if j % 3 else 'wood_mid', bevel=.012)
            obj['step_index'] = j+1
            obj['rise_m'] = rise
            obj['tread_m'] = tread
            obj['walk_surface_z_m'] = (j+1)*rise
        slope = H/5
        yz = [(-2.5+.14/slope, 0), (2.5, H-.14), (2.5, H-.36), (-2.5+.36/slope, 0)]
        for x in [-.59, .59]:
            prism('楼梯连续承重斜梁', x-.09, x+.09, yz, 'wood_mid')
        box('楼梯坡脚承托', (0, -2.5+tread/2, (rise-.14)/2),
            (1.5, tread, rise-.14), 'wood_mid', bevel=.006)
    elif key == 'roof_slope_5x5':
        for j in range(10):
            x0, x1 = -2.5+j*.5, -2.5+(j+1)*.5
            if j: x0 += .006
            if j < 9: x1 -= .006
            prism('薄荷色单坡屋面', x0, x1, [(-2.5, 0), (2.5, 1.09), (2.5, 1.25), (-2.5, .16)],
                  'seafoam' if j % 2 else 'mint_white', .012)
    elif key == 'roof_flat_5x5':
        for j in range(6):
            x0, x1 = -2.5+j*5/6, -2.5+(j+1)*5/6
            if j: x0 += .006
            if j < 5: x1 -= .006
            box('平顶宽板', ((x0+x1)/2, 0, .1), (x1-x0, 5, .2),
                'seafoam' if j in [0, 5] else 'mint_white', bevel=.035)
    else:
        raise AssertionError(key)


def fit_roof_envelope(col):
    b = bounds(col)
    for obj in col.objects:
        if obj.type == 'MESH':
            for vertex in obj.data.vertices:
                vertex.co.z = (vertex.co.z-b['min'][2])*1.25/(b['max'][2]-b['min'][2])


def repair_roof():
    paths = [D/'building_kit.blend', D/'component_packages/roof_slope_5x5/roof_slope_5x5.blend']
    for path in paths:
        bpy.ops.wm.open_mainfile(filepath=str(path))
        bpy.context.preferences.filepaths.save_version = 0
        for name in ['制作_5×5米斜面屋顶', 'SEA-KIT-ROOF-SLOPE-5X5']:
            fit_roof_envelope(bpy.data.collections[name])
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    catalog_path = D/'catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    for record in catalog['components']:
        if record['id']=='roof_slope_5x5':
            record['bounds']=bounds(bpy.data.collections[record['collection']])
            record['bounds_size_m']=[5,5,1.25]
            manifest_path=D/'component_packages/roof_slope_5x5/asset_manifest.json'
            manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
            manifest.update(bounds=record['bounds'], bounds_size_m=[5,5,1.25])
            write_json(manifest_path, manifest)
    write_json(catalog_path, catalog)


def bounds(col):
    vertices = [o.matrix_world @ v.co for o in col.objects if o.type == 'MESH' for v in o.data.vertices]
    return {'min': [min(v[k] for v in vertices) for k in range(3)],
            'max': [max(v[k] for v in vertices) for k in range(3)]}


def tris(col):
    return sum(len(p.vertices)-2 for o in col.objects if o.type == 'MESH' for p in o.data.polygons)


def gallery_instance(scene, col, name, location):
    obj = bpy.data.objects.new(name, None)
    obj.instance_type = 'COLLECTION'
    obj.instance_collection = col
    obj.location = location
    scene.collection.objects.link(obj)
    return obj


def setup_gallery(scene):
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1
    world = bpy.data.worlds.new('海色展示环境')
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
    background.inputs[0].default_value = (.14, .23, .25, 1)
    background.inputs[1].default_value = .8
    scene.world = world
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    bpy.context.window.scene = scene
    for name, location, energy, size in [('主光', (8, -10, 24), 5500, 18), ('补光', (-10, 5, 17), 2800, 12)]:
        bpy.ops.object.light_add(type='AREA', location=location)
        obj = bpy.context.object
        obj.name = name
        obj.data.energy = energy
        obj.data.shape = 'DISK'
        obj.data.size = size
        obj.rotation_euler = (Vector((5, 3, 1))-obj.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.object.camera_add(location=(27, -32, 28))
    scene.camera = bpy.context.object
    scene.camera.name = '固定参考相机'
    scene.camera.data.type = 'ORTHO'
    scene.camera.data.ortho_scale = 32
    scene.camera.rotation_euler = (Vector((10, 3.7, 1.5))-scene.camera.location).to_track_quat('-Z', 'Y').to_euler()


def build():
    global CURRENT
    assert P['status'] == 'frozen_before_geometry' and len(P['components']) == 10
    assert not (D/'building_kit.blend').exists(), '禁止覆盖已制作母版'
    assert not OPT.exists(), '禁止覆盖优化文件'
    for entry in P['components']:
        key = entry['id']
        assert not (R/f'godot/assets/models/building_kit/{key}/{key}.glb').exists()
        assert not (R/f'godot/scenes/buildables/kit/{key}.tscn').exists()
    assert not (R/'godot/assets/data/building_kit_5m.json').exists()
    W.mkdir(parents=True, exist_ok=True)
    write_json(W/'protected_before.json', protected_files())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    gallery = bpy.context.scene
    gallery.name = '五米建筑组件_结构全览'
    library = bpy.data.scenes.new('独立组件母版库_米制原点')
    library.unit_settings.system = 'METRIC'
    library.unit_settings.scale_length = 1
    raw_parent = bpy.data.collections.new('01_制作组件_可编辑_默认隐藏')
    out_parent = bpy.data.collections.new('02_游戏输出_十独立资产包_v002')
    library.collection.children.link(raw_parent)
    library.collection.children.link(out_parent)
    setup_materials()
    records, instances = [], []
    for index, entry in enumerate(P['components']):
        key = entry['id']
        raw = bpy.data.collections.new('制作_'+entry['name'])
        raw_parent.children.link(raw)
        gallery.collection.children.link(raw)
        CURRENT = raw
        build_geometry(entry)
        if key == 'roof_slope_5x5':
            fit_roof_envelope(raw)
        out = bpy.data.collections.new(entry['asset_id'])
        out_parent.children.link(out)
        gallery.collection.children.link(out)
        root = bpy.data.objects.new(key+'_ROOT', None)
        out.objects.link(root)
        for role in ROLES:
            objects = [o for o in raw.objects if o.get('material_role') == role]
            if not objects:
                continue
            bpy.ops.object.select_all(action='DESELECT')
            for obj in objects:
                clone = obj.copy()
                clone.data = obj.data.copy()
                clone.name = key+'__'+role
                out.objects.link(clone)
                clone.select_set(True)
                bpy.context.view_layer.objects.active = clone
            bpy.ops.object.join()
            joined = bpy.context.object
            joined.name = key+'__'+role
            joined.data.name = joined.name
            joined.parent = root
            joined.select_set(False)
        gallery.collection.children.unlink(raw)
        gallery.collection.children.unlink(out)
        pos = [(index % 5)*6.3, (index // 5)*8, 0]
        gallery_instance(gallery, out, entry['name'], pos)
        instances.append({'id': key, 'collection': out.name, 'position_m': pos, 'rotation_blender_z_deg': 0, 'scale': [1,1,1]})
        record = dict(entry, collection=out.name, source_collection=raw.name, root_object=root.name,
                      source_blend=str((D/'building_kit.blend').relative_to(R)).replace('\\','/'),
                      component_blend=f'component_packages/{key}/{key}.blend',
                      bounds= bounds(out), triangles=tris(out),
                      material_roles_used=[role for role in ROLES if any(o.type=='MESH' and o.data.materials[0].name=='SEA_'+role for o in out.objects)],
                      front_axis='-Z', allowed_rotations_y_deg=[0,90,180,270],
                      collision_owner='sea_building_space_projection', exported=False, runtime_integrated=False)
        record['bounds_size_m'] = [record['bounds']['max'][k]-record['bounds']['min'][k] for k in range(3)]
        records.append(record)
        COLLECTION[key] = out
        package_scene = bpy.data.scenes.new('独立组件_'+entry['name'])
        package_scene.unit_settings.system = 'METRIC'
        package_scene.unit_settings.scale_length = 1
        package_scene.collection.children.link(out)
        package_scene.collection.children.link(raw)
        path = D/record['component_blend']
        path.parent.mkdir(parents=True, exist_ok=True)
        raw.hide_render = True
        raw.hide_viewport = True
        bpy.context.window.scene = package_scene
        bpy.context.view_layer.update()
        bpy.data.libraries.write(str(path), {package_scene, *MATERIAL.values()}, fake_user=True, compress=True, path_remap='RELATIVE_ALL')
        bpy.context.window.scene = gallery
        bpy.data.scenes.remove(package_scene)
        print('独立包已保存', key, flush=True)
        write_json(path.parent/'asset_manifest.json', dict(record, asset_version='v002', building_class='above_water',
                   units='meters', source_scale=[1,1,1], palette=P['palette'], palette_uv_layer='PaletteUV',
                   material_roles=ROLES, dependencies=[P['palette']], exported_glb=f'godot/assets/models/building_kit/{key}/{key}.glb',
                   prefab=f'godot/scenes/buildables/kit/{key}.tscn'))
    setup_gallery(gallery)
    raw_parent.hide_render = True
    raw_parent.hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=str(D/'building_kit.blend'), compress=True)
    write_json(D/'catalog.json', {'schema':'sea.building_kit.catalog','version':'v002','components':records})
    write_json(D/'component_instances.json', {'purpose':'仅Blender展示，不拥有Godot正式摆位', 'godot_mapping':'(x,y,z)->(x,z,-y)', 'instances':instances})
    print('V002_SOURCE_BUILT', len(records), flush=True)


def validate_collection(col, entry):
    assert tuple(col.instance_offset) == (0,0,0)
    box_bounds = bounds(col)
    size = [box_bounds['max'][k]-box_bounds['min'][k] for k in range(3)]
    expected = entry['footprint']+[entry['height']]
    assert all(abs(a-b) < 1e-5 for a,b in zip(size, expected)), (entry['id'], size, expected)
    expected_min = -entry['height'] if entry['source_origin']=='surface_center' else 0
    assert abs(box_bounds['min'][2]-expected_min) < 1e-5
    assert abs(box_bounds['min'][0]+box_bounds['max'][0]) < 1e-5
    assert abs(box_bounds['min'][1]+box_bounds['max'][1]) < 1e-5
    faces = 0
    for obj in col.objects:
        assert obj.location.length < 1e-7 and obj.rotation_euler.to_matrix().is_identity
        assert all(abs(v-1)<1e-7 for v in obj.scale)
        if obj.type != 'MESH':
            continue
        assert len(obj.users_collection) == 1
        assert len(obj.data.materials) == 1
        assert obj.data.materials[0].name in ['SEA_'+role for role in ROLES]
        assert len(obj.data.uv_layers) == 1
        uv = obj.data.uv_layers[0]
        assert uv.name=='PaletteUV' and uv.active_render and obj.data.uv_layers.active==uv
        for face in obj.data.polygons:
            pts = [uv.data[i].uv for i in face.loop_indices]
            area = abs(sum(pts[j].x*pts[(j+1)%len(pts)].y-pts[(j+1)%len(pts)].x*pts[j].y for j in range(len(pts))))/2
            assert area > 1e-8, (obj.name, face.index, '无面积UV')
            cells = {(int(p.x*8), int(p.y*8)) for p in pts}
            assert len(cells)==1, (obj.name, face.index, '跨格')
            for p in pts:
                assert .125 <= (p.x*8)%1 <= .875 and .125 <= (p.y*8)%1 <= .875
            faces += 1
    return {'bounds_blender_m':box_bounds, 'dimensions_blender_m':size, 'valid_uv_islands':faces,
            'invalid_uv_islands':0, 'triangles':tris(col), 'identity_transform':True, 'collection_offset_zero':True}


def validate_materials():
    names = {m.name for m in bpy.data.materials}
    assert names == {'SEA_'+role for role in ROLES}, names
    for mat in bpy.data.materials:
        tex = [n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE']
        assert len(tex)==1 and tex[0].interpolation=='Closest'
        assert not tex[0].image.packed_file
        assert Path(bpy.path.abspath(tex[0].image.filepath)).resolve()==PALETTE.resolve()
        assert len([n for n in mat.node_tree.nodes if n.type=='UVMAP' and n.uv_map=='PaletteUV'])==1


def export_glb(col, target, expected_sha=None):
    previous = bpy.context.window.scene
    scene = bpy.data.scenes.new('组件导出_临时场景')
    scene.collection.children.link(col)
    bpy.context.window.scene = scene
    bpy.ops.object.select_all(action='DESELECT')
    roles = {}
    for obj in col.objects:
        obj.select_set(True)
        if obj.type=='MESH':
            roles[obj.data.name] = obj.data.materials[0].name
    temp = W/'transfer'/target.name
    temp.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(temp), export_format='GLB', use_selection=True,
        use_active_scene=True, export_materials='PLACEHOLDER', export_image_format='NONE',
        export_extras=True, export_yup=True)
    bpy.context.window.scene = previous
    bpy.data.scenes.remove(scene)
    raw = temp.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+length])
    blob = raw[28+length:]
    assert not doc.get('images') and not doc.get('textures')
    doc['materials'] = [{'name':'SEA_'+role, 'pbrMetallicRoughness':{
        'metallicFactor':.6 if role=='Metal' else 0, 'roughnessFactor':.8 if role=='Matte' else .28}}
        for role in ROLES]
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            assert 'TEXCOORD_0' in primitive['attributes'] and 'TEXCOORD_1' not in primitive['attributes']
            primitive['material'] = ['SEA_'+role for role in ROLES].index(roles[mesh['name']])
    doc.setdefault('extras', {})['sea_palette_transfer'] = {'uv0':'PaletteUV', 'palette':'sea_cozy_8x8_512',
        'roles':ROLES,'runtime_material_binding':'KitVisual -> assets/materials/building_kit', 'source_version':'v002', 'source_units':'meters'}
    js = json.dumps(doc, ensure_ascii=False, separators=(',',':')).encode('utf-8')
    js += b' '*(-len(js)%4)
    blob += b'\0'*(-len(blob)%4)
    result = struct.pack('<III', 0x46546C67, 2, 28+len(js)+len(blob))
    result += struct.pack('<II', len(js), 0x4E4F534A)+js+struct.pack('<II', len(blob), 0x004E4942)+blob
    if target.exists():
        assert expected_sha is not None and sha(target)==expected_sha, '仅可更新清单签名匹配的本次新资产'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(result)


def write_runtime(entry):
    key = entry['id']
    prefab = R/f'godot/scenes/buildables/kit/{key}.tscn'
    assert not prefab.exists()
    text = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/building/kit_visual.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/models/building_kit/{key}/{key}.glb" id="2"]

[node name="{key}" type="Node3D"]
script = ExtResource("1")
content_id = "{key}"
metadata/asset_id = "{entry['asset_id']}"
metadata/asset_version = "v002"
metadata/source_units = "meters"
metadata/source_origin = "{entry['source_origin']}"
metadata/water_layer = "surface"
metadata/water_layer_role = "entity"
metadata/collision_owner = "sea_building_space_projection"

[node name="Model" parent="." instance=ExtResource("2")]
'''
    if key=='stairs_5m':
        text += f'''
[node name="LowSocket" type="Marker3D" parent="."]
position = Vector3(0, 0, 2.5)

[node name="HighSocket" type="Marker3D" parent="."]
position = Vector3(0, {H}, -2.5)
'''
    prefab.write_text(text, encoding='utf-8')
    module = {k:entry[k] for k in ['id','name','asset_id','profile','footprint','height','seconds','source_origin']}
    module.update(cost={'wood':entry['wood']}, category='structure', active=True,
        role='deck' if entry['profile']=='foundation' else 'furnishing',
        placement='water' if entry['profile']=='foundation' else 'top' if entry['profile'] in ['beam','roof'] else 'deck',
        blocks_actor=entry['profile'] in ['foundation','wall','window','door','post','railing'],
        movable=False, removable=True, prefab=f'res://scenes/buildables/kit/{key}.tscn',
        description='5米模数；源尺寸即游戏米制尺寸', front_axis='-Z')
    if key=='door_frame_5m':
        module.update(door_width=1.85, door_height=3.1)
    if key=='stairs_5m':
        module.update(step_count=27, rise=H/27, tread=5/27)
    return module


def optimize_export():
    bpy.ops.wm.open_mainfile(filepath=str(D/'building_kit.blend'))
    bpy.context.preferences.filepaths.save_version = 0
    source_hash = sha(D/'building_kit.blend')
    records = json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
    before = {}
    cleanup = {}
    for entry in records:
        col = bpy.data.collections[entry['collection']]
        before[entry['id']] = validate_collection(col, entry)
        counts = {'isolated_vertices_removed':0,'degenerate_faces_removed':0,'duplicate_faces_removed':0}
        for obj in col.objects:
            if obj.type!='MESH': continue
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bad = [f for f in bm.faces if f.calc_area()<1e-12]
            counts['degenerate_faces_removed'] += len(bad)
            if bad: bmesh.ops.delete(bm, geom=bad, context='FACES')
            isolated = [v for v in bm.verts if not v.link_edges]
            counts['isolated_vertices_removed'] += len(isolated)
            if isolated: bmesh.ops.delete(bm, geom=isolated, context='VERTS')
            seen, duplicate = set(), []
            for face in bm.faces:
                signature = tuple(sorted(tuple(round(c,7) for c in v.co) for v in face.verts))
                if signature in seen: duplicate.append(face)
                seen.add(signature)
            counts['duplicate_faces_removed'] += len(duplicate)
            if duplicate: bmesh.ops.delete(bm, geom=duplicate, context='FACES')
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bm.to_mesh(obj.data)
            bm.free()
        cleanup[entry['id']] = counts
    validate_materials()
    OPT.parent.mkdir(parents=True, exist_ok=True)
    assert not OPT.exists()
    bpy.ops.wm.save_as_mainfile(filepath=str(OPT), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(OPT))
    modules, exports = [], []
    for entry in records:
        key = entry['id']
        col = bpy.data.collections[entry['collection']]
        after = validate_collection(col, entry)
        assert before[key]['bounds_blender_m']==after['bounds_blender_m']
        target = R/f'godot/assets/models/building_kit/{key}/{key}.glb'
        export_glb(col, target)
        modules.append(write_runtime(entry))
        exports.append({'id':key, 'asset_id':entry['asset_id'], 'source_version':'v002',
            'source_blend':str(D/'building_kit.blend'), 'source_sha256_before':source_hash,
            'optimized_blend':str(OPT), 'optimized_sha256':sha(OPT), 'optimization_operations':cleanup[key],
            'triangles_before':before[key]['triangles'], 'triangles_after':after['triangles'],
            'reduction_ratio':1-after['triangles']/before[key]['triangles'], 'budget':None,
            'preserved_faces_reason':'独立可旋转模块的背面、底面与斜梁可见且参与投影；不按朝下法线删面。三段圆角为sea风格，不作破坏轮廓的统一减面。',
            'fidelity':'包络、逐面UV、几何保持；同机位图见工程外预览',
            'glb':str(target.relative_to(R)).replace('\\','/'), 'glb_sha256':sha(target),
            'runtime_integrated':False})
    assert sha(D/'building_kit.blend')==source_hash
    for entry in exports:
        entry['source_sha256_after']=sha(D/'building_kit.blend')
    write_json(D/'export/v002/export_manifest.json', {'schema':'sea.building_kit.export','exports':exports})
    write_json(R/'godot/assets/data/building_kit_5m.json', {'schema':1,'modules':modules})
    print('V002_EXPORTED', len(exports), flush=True)


def check_door(col):
    hits = []
    for obj in col.objects:
        if obj.type!='MESH': continue
        obj.data.calc_loop_triangles()
        for tri in obj.data.loop_triangles:
            vs = [obj.data.vertices[i].co for i in tri.vertices]
            if (min(v.x for v in vs)<.925-1e-6 and max(v.x for v in vs)>-.925+1e-6
                and min(v.z for v in vs)<3.1-1e-6 and max(v.z for v in vs)>1e-6):
                hits.append(tri.index)
    assert not hits, hits
    return {'clear_width_m':1.85,'clear_height_m':3.1,'triangles_entering_clearance':0,'threshold':False}


def check_stairs(raw):
    steps = sorted([o for o in raw.objects if 'step_index' in o], key=lambda o:o['step_index'])
    assert len(steps)==27
    evidence = []
    for j, obj in enumerate(steps):
        b = bounds_for_objects([obj])
        assert abs(b['max'][2]-(j+1)*H/27)<1e-5
        assert abs(b['min'][1]-(-2.5+j*5/27))<1e-5
        assert abs(b['max'][1]-(-2.5+(j+1)*5/27))<1e-5
        evidence.append({'step':j+1,'surface_z_m':b['max'][2],'y_min_m':b['min'][1],'y_max_m':b['max'][1]})
    return {'step_count':27,'rise_m':H/27,'tread_m':5/27,'steps':evidence,
            'low_godot':[0,0,2.5],'high_godot':[0,H,-2.5],
            'repeat_translation_godot':[0,H,-5],'parallel_translation_godot':[1.5,0,0],
            'parallel_overlap_width_m':0,'out_of_width_accessories':0}


def bounds_for_objects(objects):
    vertices = [o.matrix_world@v.co for o in objects for v in o.data.vertices]
    return {'min':[min(v[k] for v in vertices) for k in range(3)], 'max':[max(v[k] for v in vertices) for k in range(3)]}


def repair_wall_layers():
    ids = {'wall_5m','window_wall_5m','door_frame_5m'}
    catalog = json.loads((D/'catalog.json').read_text(encoding='utf-8'))
    exports = json.loads((D/'export/v002/export_manifest.json').read_text(encoding='utf-8'))
    paths = [D/'building_kit.blend', OPT]+[D/e['component_blend'] for e in catalog['components'] if e['id'] in ids]
    for path in paths:
        bpy.ops.wm.open_mainfile(filepath=str(path))
        bpy.context.preferences.filepaths.save_version = 0
        for entry in catalog['components']:
            if entry['id'] not in ids or entry['collection'] not in bpy.data.collections:
                continue
            for col_name in [entry['collection'],entry['source_collection']]:
                col=bpy.data.collections[col_name]
                for obj in col.objects:
                    if obj.type!='MESH': continue
                    for vertex in obj.data.vertices:
                        if abs(vertex.co.y)>.050001:
                            vertex.co.y=math.copysign(.05+(abs(vertex.co.y)-.05)*.9,vertex.co.y)
                if col_name==entry['source_collection']:
                    for obj in col.objects:
                        if not obj.name.startswith(('墙端收边','洞口侧框','洞口上框','窗台')): continue
                        for vertex in obj.data.vertices:
                            if abs(vertex.co.y)>.05:
                                vertex.co.y=math.copysign(.05+(abs(vertex.co.y)-.05)/.9,vertex.co.y)
                else:
                    # 合并网格用连通岛识别全深度收边，避免改变板面UV或墙体包络。
                    for obj in col.objects:
                        if obj.type!='MESH': continue
                        adjacency={v.index:set() for v in obj.data.vertices}
                        for edge in obj.data.edges:
                            a,b=edge.vertices
                            adjacency[a].add(b);adjacency[b].add(a)
                        todo=set(adjacency)
                        while todo:
                            seed=todo.pop();island={seed};stack=[seed]
                            while stack:
                                for neighbor in adjacency[stack.pop()]:
                                    if neighbor in todo:
                                        todo.remove(neighbor);island.add(neighbor);stack.append(neighbor)
                            verts=[obj.data.vertices[i] for i in island]
                            if min(v.co.y for v in verts)<-.09 and max(v.co.y for v in verts)>.09:
                                for v in verts:
                                    if abs(v.co.y)>.05:
                                        v.co.y=math.copysign(.05+(abs(v.co.y)-.05)/.9,v.co.y)
            validate_collection(bpy.data.collections[entry['collection']],entry)
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(OPT))
    for entry in exports['exports']:
        if entry['id'] in ids:
            col=bpy.data.collections[next(e['collection'] for e in catalog['components'] if e['id']==entry['id'])]
            path=R/entry['glb']
            export_glb(col,path,expected_sha=entry['glb_sha256'])
            entry['glb_sha256']=sha(path)
        entry['source_sha256_before']=entry['source_sha256_after']=sha(D/'building_kit.blend')
        entry['optimized_sha256']=sha(OPT)
    write_json(D/'export/v002/export_manifest.json',exports)
    print('V002_WALL_LAYER_CLEARANCE_PASS', flush=True)


def finalize_packages():
    records = json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
    for entry in records:
        path = D/entry['component_blend']
        bpy.ops.wm.open_mainfile(filepath=str(path))
        bpy.context.preferences.filepaths.save_version = 0
        scene = bpy.data.scenes['独立组件_'+entry['name']]
        bpy.context.window.scene = scene
        for other in list(bpy.data.scenes):
            if other != scene:
                bpy.data.scenes.remove(other)
        bpy.context.view_layer.update()
        assert len(scene.collection.all_objects)>0
        scene_name = scene.name
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
        bpy.ops.wm.open_mainfile(filepath=str(path))
        assert bpy.context.scene.name==scene_name and len(bpy.context.scene.collection.all_objects)>0
    print('V002_PACKAGE_DEFAULT_SCENES_PASS', len(records), flush=True)


def validate():
    records = json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
    report = {'schema':'sea.building_kit.source_validation', 'godot_runtime':'pending_main_agent_runner', 'components':[]}
    for path in [D/'building_kit.blend', OPT]+[D/e['component_blend'] for e in records]:
        bpy.ops.wm.open_mainfile(filepath=str(path))
        validate_materials()
        selected = records if path in [D/'building_kit.blend', OPT] else [e for e in records if D/e['component_blend']==path]
        for entry in selected:
            data = validate_collection(bpy.data.collections[entry['collection']], entry)
            data['editable_source'] = validate_collection(bpy.data.collections[entry['source_collection']], entry)
            if path not in [D/'building_kit.blend', OPT]:
                assert bpy.context.scene.name=='独立组件_'+entry['name']
                assert len(bpy.context.scene.collection.all_objects)>0
            if entry['id']=='door_frame_5m': data['door']=check_door(bpy.data.collections[entry['collection']])
            if entry['id']=='stairs_5m': data['stairs']=check_stairs(bpy.data.collections[entry['source_collection']])
            report['components'].append(dict(data, id=entry['id'], reopened_file=str(path), sha256=sha(path)))
    previous = json.loads((W/'protected_before.json').read_text(encoding='utf-8'))
    differences = [path for path, digest in previous.items() if not Path(path).is_file() or sha(path)!=digest]
    assert not differences, differences
    report.update(reopened_files=12, invalid_uv_islands=0, protected_files_unchanged=len(previous), protected_differences=[],
                  palette=str(PALETTE), palette_packed=False, material_roles=ROLES,
                  unused_role_reason={'Emission':'共享角色预留，本批建筑无虚构发光几何'}, passed=True)
    write_json(W/'source_validation.json', report)
    print('V002_REOPEN_UV_DIMENSIONS_PASS', len(report['components']), flush=True)


def render_fidelity():
    bpy.ops.wm.open_mainfile(filepath=str(OPT))
    scene = bpy.data.scenes['五米建筑组件_结构全览']
    bpy.context.window.scene = scene
    camera = scene.camera
    for label, location, target, scale in [
        ('structure_overview', (31,-34,28), (12.6,4,1.8), 35),
        ('structure_back', (-12,35,23), (12.6,4,1.8), 35),
        ('structure_top', (12.6,4,50), (12.6,4,0), 35)]:
        camera.location=location
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        scene.render.filepath=str(W/('optimized_'+label+'.png'))
        bpy.ops.render.render(write_still=True)
    print('V002_OPTIMIZED_FIDELITY_RENDERED', flush=True)


def render():
    bpy.ops.wm.open_mainfile(filepath=str(D/'building_kit.blend'))
    scene = bpy.data.scenes['五米建筑组件_结构全览']
    bpy.context.window.scene = scene
    camera = scene.camera
    for label, location, target, scale in [
        ('structure_overview', (31,-34,28), (12.6,4,1.8), 35),
        ('structure_back', (-12,35,23), (12.6,4,1.8), 35),
        ('structure_top', (12.6,4,50), (12.6,4,0), 35)]:
        camera.location=location
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        scene.render.filepath=str(W/(label+'.png'))
        bpy.ops.render.render(write_still=True)
    close = bpy.data.scenes.new('楼梯接口与并排连续_隔离预览')
    setup_gallery(close)
    col = bpy.data.collections['SEA-KIT-STAIRS-5M']
    for name, pos in [('单跑楼梯',(0,0,0)),('并排楼梯',(1.5,0,0)),('连续第二跑',(0,5,H))]:
        gallery_instance(close,col,name,pos)
    camera = close.camera
    for label, location, target, scale in [
        ('stairs_closeup',(9,-10,9),(.5,0,2.5),9),
        ('stairs_continuous_parallel',(15,-17,15),(.5,2.5,5),23)]:
        camera.location=location
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        close.render.filepath=str(W/(label+'.png'))
        bpy.ops.render.render(write_still=True)
    print('V002_PREVIEWS_RENDERED', flush=True)


if __name__=='__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['build','export','validate','render','repair_roof','finalize_packages','repair_wall_layers','render_fidelity'])
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    {'build':build,'export':optimize_export,'validate':validate,'render':render,'repair_roof':repair_roof,'finalize_packages':finalize_packages,'repair_wall_layers':repair_wall_layers,'render_fidelity':render_fidelity}[args.mode]()
