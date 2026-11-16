"""将已冻结的 sea native 快照派生为可编辑 Blender 包；不写运行资源。"""
import argparse
import collections
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

import bpy
from mathutils import Vector

STATES = ("fresh", "damaged", "ruined")
ROLES = ("SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission")
HERE = Path(__file__).resolve()
REPO = HERE.parents[3]
ROOT = REPO / "art_source/scenes/building_attachments/v001"
PALETTE = REPO / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
PLAN = REPO / "art_source/scenes/building_attachments/v001/component_plan.json"


def timestamp():
    return datetime.now().astimezone().isoformat()


def native_file(args, uri):
    if uri.startswith("res://"):
        return args.native_project / uri.removeprefix("res://")
    if uri.startswith("user://"):
        prefix = f"user://building_attachments/library/{args.version}/"
        assert uri.startswith(prefix), uri
        return args.manifest.parent / uri.removeprefix(prefix)
    path = Path(uri)
    assert path.is_absolute(), uri
    return path


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write_new(path, value):
    path = Path(path)
    assert path.parent.is_dir(), path.parent
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def mapped(v):
    return (v[0], -v[2], v[1])


def json_prop(block, key, value):
    block[key] = json.dumps(value, ensure_ascii=False, sort_keys=True)


def bounds(points):
    points = list(points)
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    return {"min": low, "max": high, "size": [b-a for a, b in zip(low, high)]}


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def collection(name, parent=None):
    result = bpy.data.collections.new(name)
    if parent:
        parent.children.link(result)
    return result


def material_parameters(project):
    result = {}
    for role, filename in zip(ROLES, ("matte", "metal", "gloss", "emission")):
        path = project / f"assets/materials/solar_cabin/sunny_{filename}.tres"
        text = path.read_text()
        params = {k: float(v) for k, v in re.findall(r"shader_parameter/(\w+) = ([\d.]+)", text)}
        result[role] = {"path": str(path), "sha256": sha(path), "parameters": params,
                        "grid_role": "shader_parameter/grid_role = true" in text,
                        "specular_shader_default": 0.25, "alpha_shader_default": 0.81 if role == "SEA_Gloss" else 1.0}
    return result


def materials(parameters):
    image = bpy.data.images.load(str(PALETTE), check_existing=True)
    image.filepath = str(PALETTE)
    image.colorspace_settings.name = "sRGB"
    result = {}
    for role in ROLES:
        data = parameters[role]
        params = data["parameters"]
        mat = bpy.data.materials.new(role)
        mat.use_nodes = True
        mat.use_backface_culling = False
        mat.diffuse_color = (0.65, 0.65, 0.65, data["alpha_shader_default"])
        nodes = mat.node_tree.nodes
        nodes.clear()
        uv = nodes.new("ShaderNodeUVMap")
        uv.uv_map = "PaletteUV"
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        tex.extension = "EXTEND"
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Roughness"].default_value = params["roughness_value"]
        shader.inputs["Metallic"].default_value = params["metallic_value"]
        shader.inputs["Specular IOR Level"].default_value = 0.25
        shader.inputs["Alpha"].default_value = data["alpha_shader_default"]
        shader.inputs["Emission Strength"].default_value = params["emission_value"]
        mat.node_tree.links.new(uv.outputs["UV"], tex.inputs["Vector"])
        mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
        mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Emission Color"])
        output = nodes.new("ShaderNodeOutputMaterial")
        mat.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
        json_prop(mat, "native_material_contract", data)
        mat["shader_equivalence"] = "PBR标量对应；Godot按色格HSV修色、world_home_lights不在交换材质执行，未声称逐像素等价"
        result[role] = mat
    return result


def mesh_object(name, native_mesh, target, mat, start=0, count=None):
    indices = native_mesh["indices"]
    count = len(indices)//3 if count is None else count
    selected = indices[start*3:(start+count)*3]
    used = list(dict.fromkeys(selected))
    remap = {old: new for new, old in enumerate(used)}
    faces = [(remap[selected[i]], remap[selected[i+2]], remap[selected[i+1]]) for i in range(0, len(selected), 3)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([mapped(native_mesh["vertices"][i]) for i in used], [], faces)
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name="PaletteUV")
    for loop in mesh.loops:
        source = used[loop.vertex_index]
        u, v = native_mesh["uv"][source]
        uv.data[loop.index].uv = (u, 1-v)
    mesh.uv_layers.active_index = 0
    uv.active_render = True
    mesh.normals_split_custom_set_from_vertices([mapped(native_mesh["normals"][i]) for i in used])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    target.objects.link(obj)
    obj["native_material_role"] = native_mesh["material_role"]
    return obj


def set_state_layers(scene, state_collections, source):
    for number, state in enumerate(STATES):
        layer = scene.view_layers[0] if number == 0 else scene.view_layers.new(state)
        layer.name = state
        for item in layer.layer_collection.children:
            if item.collection == source or item.collection in state_collections.values():
                item.exclude = item.collection != state_collections[state]
    if bpy.context.window:
        bpy.context.window.view_layer = scene.view_layers["fresh"]


def save_new(path):
    assert not path.exists(), f"禁止覆盖既有源：{path}"
    bpy.ops.wm.save_as_mainfile(filepath=str(path), check_existing=False)


def derive(args):
    project = args.native_project
    native_manifest = read(args.manifest)
    started_at = timestamp()
    plan = read(PLAN)
    assert len(native_manifest["records"]) == 96
    for name in ("source", "components", "export"):
        assert (ROOT/name).is_dir() and not any((ROOT/name).iterdir()), f"输出目录须为空：{name}"
    parameters = material_parameters(project)
    source_paths = sorted((project/"src/building_attachments").glob("*.gd")) + [project/"data/building_attachments/catalog_v1.json"]
    source_paths += [project/"shaders/sunny_palette.gdshader", project/"shaders/sunny_palette_gloss.gdshader"]
    recorded_sources = {entry["path"].removeprefix("res://"): entry["sha256"] for entry in native_manifest["source"].get("files", [])}
    provenance = []
    for path in source_paths:
        relative = str(path.relative_to(project))
        digest = sha(path)
        expected = recorded_sources.get(relative)
        if expected:
            assert digest == expected, f"冻结源码与库manifest不符：{relative}"
        current_path = REPO/"godot"/relative
        current_sha = sha(current_path)
        provenance.append({"path": str(path), "sha256": digest, "library_recorded_sha256": expected,
                           "matches_library_record": digest == expected if expected else None,
                           "current_repo_path": str(current_path), "current_sha256_at_build": current_sha,
                           "current_matches_snapshot": digest == current_sha})
    manifest = {
        "schema": "sea.building_attachments.blender_derived.v1", "version": args.version,
        "started_at": started_at,
        "native_generator_version": native_manifest["generator_version"],
        "source_hash_scope": "精确冻结库输入与隔离项目字节；current只记录读取时对照，Store后续修复不追认为本库来源，也不声称全部current一致",
        "contact_witness_scope": "原生contact witness仅partial，完整保留；不证明全部接缝、无穿插或全总成合规",
        "overall_plan_reference_only": True,
        "provenance": "derived_native_snapshot_not_original_hand_authored_blender",
        "native_runtime_authority": True, "glb_purpose": "visual_exchange_sample_only_not_runtime_replacement",
        "runtime_integrated": False, "formal_registration": "pending", "asset_ids_allocated": 0,
        "native_project": str(project), "native_manifest": {"path": str(args.manifest), "sha256": sha(args.manifest)},
        "native_source_manifest_records": native_manifest["source"],
        "component_plan": {"path": str(PLAN), "sha256": sha(PLAN), "read_only": True},
        "source_gd_and_catalog": provenance, "blender_version": bpy.app.version_string,
        "mapping": {"godot_to_blender": "(x,y,z)->(x,-z,y)", "blender_to_godot": "(x,y,z)->(x,z,-y)",
                    "determinant": 1, "source_front": "+Y", "source_up": "+Z", "native_front": "-Z",
                    "units": "meter", "origin": "native_bottom_center_preserved_without_recentering",
                    "front_exception": "保留native映射，覆盖项目常规source -Y；若装配按source -Y约定才需绕Blender Z旋转pi（Godot Y yaw pi），本输出不追加旋转，GLB正面仍-Z",
                    "winding": "native clockwise->Blender CCW交换每tri第二三索引；法线同坐标变换",
                    "uv": "native V top-origin -> Blender 1-V；glTF exporter再次转换为top-origin"},
        "palette": {"path": str(PALETTE), "sha256": sha(PALETTE), "external_only": True, "interpolation": "Closest"},
        "materials": parameters, "material_shader_equivalence": "PBR标量和默认alpha对应；动态HSV/world_home_lights未移植，非像素等价",
        "state_policy": "每包三个独立view layer，默认fresh；source隐藏，非运行三态同时常驻；总览单独show_all_states_grid",
        "text_contract": {"source": "godot/src/building_attachments/glyphs.gd", "font": "original_stroke_table_not_BlenderFont_or_OS_font",
                          "editable_parameters": "原生Godot外挂文字接口/recipe.text才会重建字形；Blender自定义属性为追溯快照，改属性不自动重建",
                          "immutable_recipe": "嵌入只读基线JSON与sha256；修改须经Godot文字接口产生新revision，不覆盖基线"},
        "collision": "GLB不含碰撞；native runtime wrapper与代理是权威，Blender只保留外部引用与数量",
        "style_audit": "仅保留native实际几何与例外；contacts/rho/倒角美术合规未在派生阶段签署",
        "validation_status": "pending_saved_file_reopen", "packages": []}
    records = {(r["type_id"], r["condition"]): r for r in native_manifest["records"]}
    for component in plan["components"]:
        type_id = component["type_id"]
        clean()
        mats = materials(parameters)
        scene = bpy.context.scene
        scene.name = type_id + "_三态派生源"
        scene["authorship"] = manifest["provenance"]
        scene["native_runtime_authority"] = True
        scene["source_front_exception"] = "+Y，映射保持；非项目默认-Y，不对native偷偷旋转"
        source_root = collection("01_制作组件_逐part_默认隐藏", scene.collection)
        source_root.hide_viewport = True
        source_root.hide_render = True
        state_collections = {}
        package = {"type_id": type_id, "name": component["name"], "planned_key": component["planned_key"],
                   "asset_id": None, "blend": str(ROOT/"components"/(type_id+".blend")), "states": []}
        for state in STATES:
            record = records[type_id, state]
            native_path = native_file(args, record["native_geometry"])
            recipe_path = native_file(args, record["recipe"])
            assert sha(native_path) == record["sha256"]["native_geometry"]
            assert sha(recipe_path) == record["sha256"]["recipe"]
            native = read(native_path)
            recipe = read(recipe_path)
            output = collection(f"{type_id}__{state}__游戏输出", scene.collection)
            state_collections[state] = output
            output["type_id"] = type_id
            output["condition"] = state
            output["native_json_sha256"] = sha(native_path)
            output["text_snapshot"] = recipe["text"]
            json_prop(output, "immutable_recipe", recipe)
            output["recipe_sha256"] = sha(recipe_path)
            parts_collection = collection(f"{state}_制作part", source_root)
            by_role = {m["material_role"]: m for m in native["meshes"]}
            assert len(by_role) <= 4
            for native_mesh in native["meshes"]:
                mesh_object(f"{state}__{native_mesh['material_role']}", native_mesh, output, mats[native_mesh["material_role"]])
            coverage = collections.defaultdict(list)
            part_records = []
            for index, part in enumerate(native["source_parts"]):
                role = part["material_role"]
                start, count = part["triangle_start"], part["triangle_count"]
                coverage[role].extend(range(start, start+count))
                obj = mesh_object(f"{state}__part{index:03d}__{part['name']}", by_role[role], parts_collection, mats[role], start, count)
                json_prop(obj, "native_part_immutable", part)
                obj["contact_verification"] = part.get("contact_verification", "pending")
                obj["native_part_name"] = part["name"]
                obj["blender_geometry_editable"] = True
                part_records.append({"object": obj.name, "native": part, "actual_triangles": len(obj.data.polygons),
                                     "actual_bounds_blender": bounds(v.co for v in obj.data.vertices),
                                     "contact_audit": "pending_not_verified_by_blender_derivation",
                                     "bevel_audit": "native_geometry_preserved_not_rebuilt_or_added_modifier"})
            for role, mesh in by_role.items():
                assert sorted(coverage[role]) == list(range(len(mesh["indices"])//3)), (type_id, state, role)
            text = bpy.data.texts.new(state + ".immutable.recipe.json")
            text.write(recipe_path.read_text())
            text["sha256"] = sha(recipe_path)
            text["immutable_baseline"] = True
            triangles = sum(len(m["indices"])//3 for m in native["meshes"])
            assert triangles == record["stats"]["triangles"]
            package["states"].append({"condition": state, "damage_description": record["damage_description"],
                "native_json": str(native_path), "native_sha256": sha(native_path), "recipe": str(recipe_path), "recipe_sha256": sha(recipe_path),
                "output_collection": output.name, "source_collection": parts_collection.name,
                "glb": str(ROOT/"export"/(type_id+"__"+state+".glb")), "native_bounds": native["bounds"],
                "actual_bounds_blender": bounds(mapped(v) for m in native["meshes"] for v in m["vertices"]),
                "triangles": triangles, "vertices": sum(len(m["vertices"]) for m in native["meshes"]),
                "material_roles": list(by_role), "node_counts": {"output_meshes": len(by_role), "source_parts": len(part_records), "collision_objects": 0},
                "native_collision_proxies_not_embedded": len(native["collision_proxies"]), "parts": part_records,
                "uv_checks": "pending_reopen", "glb_checks": "pending_export", "mount_anchor_native": native["mount_anchor"]})
        set_state_layers(scene, state_collections, source_root)
        save_new(Path(package["blend"]))
        package["blend_sha256"] = sha(package["blend"])
        # 从真实重开的独立包选择一个状态导出，制作组件及其它状态不参与。
        bpy.ops.wm.open_mainfile(filepath=package["blend"])
        for state_data in package["states"]:
            state = state_data["condition"]
            bpy.context.window.view_layer = bpy.context.scene.view_layers[state]
            bpy.ops.object.select_all(action="DESELECT")
            for obj in bpy.data.collections[state_data["output_collection"]].objects:
                obj.select_set(True)
            path = Path(state_data["glb"])
            assert not path.exists()
            bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                export_image_format="NONE", export_materials="EXPORT", export_yup=True,
                export_normals=True, export_texcoords=True, export_extras=False, export_animations=False,
                export_cameras=False, export_lights=False)
            state_data["glb_sha256"] = sha(path)
        manifest["packages"].append(package)
        print("DERIVED", type_id, flush=True)
    clean()
    overview_scene = bpy.context.scene
    overview_scene.name = "show_all_states_grid"
    overview_scene["grid_contract"] = "4族各8行；每type连续3格fresh/damaged/ruined，96个CollectionInstance，不重复网格"
    grid = collection("02_验收总览_96个CollectionInstance", overview_scene.collection)
    for index, package in enumerate(manifest["packages"]):
        with bpy.data.libraries.load(package["blend"], link=True) as (data_from, data_to):
            data_to.collections = [s["output_collection"] for s in package["states"]]
        for column, state_data in enumerate(package["states"]):
            linked = next(c for c in data_to.collections if c.name == state_data["output_collection"])
            instance = bpy.data.objects.new(package["type_id"]+"__"+state_data["condition"], None)
            instance.instance_type = "COLLECTION"
            instance.instance_collection = linked
            instance.location = ((index//8)*18 + column*5.5, -(index%8)*5.5, 0)
            grid.objects.link(instance)
            state_data["overview_instance"] = {"object": instance.name, "position": list(instance.location), "grid_type_index": index, "state_column": column}
    overview = ROOT/"source/overview.blend"
    save_new(overview)
    manifest["overview"] = {"path": str(overview), "sha256": sha(overview), "instances": 96, "local_meshes": 0}
    manifest["generator"] = {"path": str(HERE), "sha256": sha(HERE)}
    manifest["completed_at"] = timestamp()
    manifest["output_bytes"] = sum(Path(p["blend"]).stat().st_size + sum(Path(s["glb"]).stat().st_size for s in p["states"]) for p in manifest["packages"]) + overview.stat().st_size
    write_new(ROOT/"source/derived_manifest.json", manifest)
    print("BUILD_COMPLETE", flush=True)


def assert_close(actual, expected, tolerance=2e-6):
    assert len(actual) == len(expected)
    assert all(abs(a-b) <= tolerance for a, b in zip(actual, expected)), (actual, expected)


def validate_uv(mesh):
    assert len(mesh.uv_layers) == 1
    uv = mesh.uv_layers.active
    assert uv.name == "PaletteUV" and uv.active_render
    min_area = math.inf
    min_margin = math.inf
    min_span = math.inf
    for polygon in mesh.polygons:
        assert len(polygon.vertices) == 3
        points = [tuple(uv.data[i].uv) for i in polygon.loop_indices]
        cells = [(math.floor(u*8), math.floor(v*8)) for u, v in points]
        assert len(set(cells)) == 1
        col, row = cells[0]
        assert 0 <= col < 8 and 0 <= row < 8
        margin = min(min(u*512-col*64, (col+1)*64-u*512, v*512-row*64, (row+1)*64-v*512) for u, v in points)
        area = abs(sum(points[i][0]*points[(i+1)%3][1]-points[(i+1)%3][0]*points[i][1] for i in range(3)))*512*512/2
        span = min((max(p[a] for p in points)-min(p[a] for p in points))*512 for a in (0, 1))
        assert margin >= 8-1e-5 and area >= 8 and span >= 8
        min_area, min_margin, min_span = min(min_area, area), min(min_margin, margin), min(min_span, span)
    return {"faces_checked": len(mesh.polygons), "min_island_area_px2": min_area, "min_safe_margin_px": min_margin, "min_axis_span_px": min_span, "single_cell": True, "active_and_render": "PaletteUV"}


def check_mesh(obj, native_mesh, start=0, count=None):
    assert obj.type == "MESH" and len(obj.users_collection) == 1
    assert tuple(obj.location) == (0, 0, 0) and tuple(obj.rotation_euler) == (0, 0, 0) and tuple(obj.scale) == (1, 1, 1)
    assert not obj.modifiers and obj.parent is None
    mesh = obj.data
    count = len(native_mesh["indices"])//3 if count is None else count
    assert len(mesh.polygons) == count
    for number, polygon in enumerate(mesh.polygons):
        indices = native_mesh["indices"][(start+number)*3:(start+number+1)*3]
        indices = [indices[0], indices[2], indices[1]]
        for loop_index, source_index in zip(polygon.loop_indices, indices):
            loop = mesh.loops[loop_index]
            assert_close(mesh.vertices[loop.vertex_index].co, mapped(native_mesh["vertices"][source_index]))
            assert_close(mesh.corner_normals[loop_index].vector, mapped(native_mesh["normals"][source_index]), 3e-4)
            u, v = native_mesh["uv"][source_index]
            assert_close(mesh.uv_layers.active.data[loop_index].uv, (u, 1-v))
        a, b, c = [mesh.vertices[i].co for i in polygon.vertices]
        assert (b-a).cross(c-a).normalized().dot(mesh.corner_normals[polygon.loop_start].vector) > 0.999
    assert len(mesh.materials) == 1 and mesh.materials[0].name == native_mesh["material_role"]
    return validate_uv(mesh)


def load_glb(path):
    raw = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<III", raw)
    assert magic == 0x46546c67 and version == 2 and length == len(raw)
    offset, document, binary = 12, None, None
    while offset < length:
        size, kind = struct.unpack_from("<II", raw, offset)
        payload = raw[offset+8:offset+8+size]
        if kind == 0x4e4f534a:
            document = json.loads(payload)
        elif kind == 0x004e4942:
            binary = payload
        offset += 8+size
    return document, binary


def accessor(document, binary, index):
    item = document["accessors"][index]
    view = document["bufferViews"][item["bufferView"]]
    code = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[item["componentType"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[item["type"]]
    fmt = "<" + code*components
    stride = view.get("byteStride", struct.calcsize(fmt))
    offset = view.get("byteOffset", 0)+item.get("byteOffset", 0)
    return [struct.unpack_from(fmt, binary, offset+i*stride) for i in range(item["count"])]


def triangle_signature(positions, normals, uv):
    points = [tuple(round(v, 5) for v in p)+tuple(round(v, 6) for v in t) for p, t in zip(positions, uv)]
    return min(tuple(points[i:]+points[:i]) for i in range(3))


def check_glb(state, native):
    document, binary = load_glb(state["glb"])
    assert not document.get("images") and not document.get("textures")
    assert not document.get("animations") and not document.get("skins") and not document.get("cameras")
    assert not document.get("extensions", {}).get("KHR_lights_punctual")
    names = [m["name"] for m in document.get("materials", [])]
    assert set(names) == set(state["material_roles"]) and len(names) <= 4
    assert len(document["nodes"]) == len(native["meshes"])
    for node in document["nodes"]:
        assert "mesh" in node and not any(k in node for k in ("matrix", "translation", "rotation", "scale", "children"))
        assert not any(s in node["name"].lower() for s in ("collision", "-col", "-convcol"))
    expected = {}
    expected_normals = {}
    for mesh in native["meshes"]:
        normal_lookup = collections.defaultdict(list)
        for position, normal, texcoord in zip(mesh["vertices"], mesh["normals"], mesh["uv"]):
            key = tuple(round(v, 5) for v in position)+tuple(round(v, 6) for v in texcoord)
            normal_lookup[key].append(normal)
        expected_normals[mesh["material_role"]] = normal_lookup
        counter = collections.Counter()
        indices = mesh["indices"]
        for i in range(0, len(indices), 3):
            ids = [indices[i], indices[i+2], indices[i+1]]
            counter[triangle_signature([mesh["vertices"][j] for j in ids], [mesh["normals"][j] for j in ids], [mesh["uv"][j] for j in ids])] += 1
        expected[mesh["material_role"]] = counter
    actual = collections.defaultdict(collections.Counter)
    triangle_count = 0
    max_normal_error = 0.0
    for material in document["materials"]:
        contract = read(ROOT/"source/derived_manifest.json")["materials"][material["name"]]
        params = contract["parameters"]
        pbr = material.get("pbrMetallicRoughness", {})
        assert abs(pbr.get("roughnessFactor", 1.0)-params["roughness_value"]) < 1e-6
        assert abs(pbr.get("metallicFactor", 1.0)-params["metallic_value"]) < 1e-6
        assert abs(pbr.get("baseColorFactor", [1, 1, 1, 1])[3]-contract["alpha_shader_default"]) < 1e-6
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            assert primitive.get("mode", 4) == 4
            attrs = primitive["attributes"]
            p, n, uv = [accessor(document, binary, attrs[key]) for key in ("POSITION", "NORMAL", "TEXCOORD_0")]
            ids = [v[0] for v in accessor(document, binary, primitive["indices"])]
            role = names[primitive["material"]]
            for position, normal, texcoord in zip(p, n, uv):
                key = tuple(round(v, 5) for v in position)+tuple(round(v, 6) for v in texcoord)
                candidates = expected_normals[role][key]
                assert candidates
                error = min(max(abs(a-b) for a, b in zip(normal, expected_normal)) for expected_normal in candidates)
                max_normal_error = max(max_normal_error, error)
                assert error <= 3e-4, (role, normal, error)
            for i in range(0, len(ids), 3):
                tri = ids[i:i+3]
                actual[role][triangle_signature([p[j] for j in tri], [n[j] for j in tri], [uv[j] for j in tri])] += 1
            triangle_count += len(ids)//3
    assert dict(actual) == expected, f"GLB逐三角属性与native不一致：{state['glb']}"
    assert triangle_count == state["triangles"]
    assert sha(state["glb"]) == state["glb_sha256"]
    return {"triangles": triangle_count, "images": 0, "textures": 0, "nodes": len(document["nodes"]), "materials": names,
            "collision_embedded": False, "native_triangle_positions_and_uv_quantized_match": True,
            "normal_tolerance": 3e-4, "max_normal_component_error": max_normal_error, "pbr_parameters_match_tres": True}


def verify(args):
    manifest = read(ROOT/"source/derived_manifest.json")
    assert sha(PLAN) == manifest["component_plan"]["sha256"]
    assert sha(manifest["native_manifest"]["path"]) == manifest["native_manifest"]["sha256"]
    report = {"schema": "sea.building_attachments.blender_validation.v1", "passed": False,
              "version": args.version, "started_at": timestamp(), "validator_sha256": sha(HERE),
              "native_manifest": manifest["native_manifest"],
              "thresholds": {"native_position_tolerance": 2e-6, "normal_component_tolerance": 3e-4,
                             "uv_min_area_px2": 8, "uv_min_margin_px": 8, "uv_min_axis_span_px": 8},
              "blender": bpy.app.version_string, "packages_reopened": 0, "states": [], "face_uv_checks": 0,
              "untested": ["Godot导入/运行/编辑器（本任务不启动引擎）", "逐part接触/布尔/收分与美术倒角全面合规", "用户美术终审/商业权属/性能", "Godot动态HSV和灯光shader像素等价"],
              "failures": []}
    try:
        for package in manifest["packages"]:
            assert sha(package["blend"]) == package["blend_sha256"]
            bpy.ops.wm.open_mainfile(filepath=package["blend"])
            assert bpy.context.scene.unit_settings.scale_length == 1.0
            assert set(layer.name for layer in bpy.context.scene.view_layers) == set(STATES)
            assert len(bpy.data.images) == 1
            for image in bpy.data.images:
                assert not image.packed_file and Path(bpy.path.abspath(image.filepath)).resolve() == PALETTE
                assert tuple(image.size) == (512, 512)
            expected_roles = {role for state in package["states"] for role in state["material_roles"]}
            assert {mat.name for mat in bpy.data.materials} == expected_roles
            assert len(bpy.data.materials) <= 4
            for mat in bpy.data.materials:
                textures = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"]
                assert len(textures) == 1 and textures[0].interpolation == "Closest"
                uvs = [n for n in mat.node_tree.nodes if n.type == "UVMAP"]
                assert len(uvs) == 1 and uvs[0].uv_map == "PaletteUV"
                assert textures[0].inputs["Vector"].links[0].from_node == uvs[0]
                params = manifest["materials"][mat.name]["parameters"]
                shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
                for socket, key in (("Roughness", "roughness_value"), ("Metallic", "metallic_value"), ("Emission Strength", "emission_value")):
                    assert abs(shader.inputs[socket].default_value-params[key]) < 1e-6
            for state in package["states"]:
                native = read(state["native_json"])
                assert sha(state["native_json"]) == state["native_sha256"]
                by_role = {m["material_role"]: m for m in native["meshes"]}
                output = bpy.data.collections[state["output_collection"]]
                source = bpy.data.collections[state["source_collection"]]
                assert tuple(output.instance_offset) == (0, 0, 0)
                assert tuple(source.instance_offset) == (0, 0, 0)
                assert len(output.objects) == len(by_role) <= 4
                assert len(source.objects) == len(native["source_parts"])
                assert source in bpy.data.collections["01_制作组件_逐part_默认隐藏"].children.values()
                assert bpy.data.collections["01_制作组件_逐part_默认隐藏"].hide_render
                assert bpy.data.collections["01_制作组件_逐part_默认隐藏"].hide_viewport
                for layer in bpy.context.scene.view_layers:
                    item = layer.layer_collection.children[output.name]
                    assert item.exclude == (layer.name != state["condition"])
                uv_results = []
                for obj in output.objects:
                    uv_results.append(check_mesh(obj, by_role[obj["native_material_role"]]))
                for part_record in state["parts"]:
                    obj = bpy.data.objects[part_record["object"]]
                    part = part_record["native"]
                    assert json.loads(obj["native_part_immutable"]) == part
                    uv_results.append(check_mesh(obj, by_role[part["material_role"]], part["triangle_start"], part["triangle_count"]))
                immutable = bpy.data.texts[state["condition"]+".immutable.recipe.json"].as_string()
                assert hashlib.sha256(immutable.encode()).hexdigest() == state["recipe_sha256"]
                glb = check_glb(state, native)
                checked = sum(r["faces_checked"] for r in uv_results)
                report["face_uv_checks"] += checked
                report["states"].append({"type_id": package["type_id"], "condition": state["condition"],
                    "uv": {"checked_faces_source_plus_output": checked, "min_area_px2": min(r["min_island_area_px2"] for r in uv_results),
                           "min_margin_px": min(r["min_safe_margin_px"] for r in uv_results), "min_span_px": min(r["min_axis_span_px"] for r in uv_results),
                           "all_single_cell_active_render_closest_external": True}, "glb": glb, "parts": len(state["parts"]),
                    "blend_sha256": package["blend_sha256"], "glb_sha256": state["glb_sha256"], "native_sha256": state["native_sha256"]})
            assert all(obj.type == "MESH" for obj in bpy.data.objects)
            report["packages_reopened"] += 1
            print("VERIFIED", package["type_id"], flush=True)
        bpy.ops.wm.open_mainfile(filepath=manifest["overview"]["path"])
        instances = [o for o in bpy.context.scene.objects if o.instance_type == "COLLECTION"]
        assert len(instances) == 96
        assert not any(o.type == "MESH" for o in bpy.context.scene.objects)
        assert all(m.library is not None for m in bpy.data.meshes)
        assert len({o.instance_collection for o in instances}) == 96
        assert sum(len(o.instance_collection.objects) for o in instances) == sum(len(s["material_roles"]) for p in manifest["packages"] for s in p["states"])
        report["overview"] = {"instances": 96, "scene_mesh_objects": 0, "all_meshes_linked_not_duplicated": True, "reopened": True}
        report["total_triangles"] = sum(s["glb"]["triangles"] for s in report["states"])
        report["glb_files_without_images"] = len(report["states"])
        report["passed"] = True
    except Exception as error:
        report["failures"].append(repr(error))
        raise
    finally:
        report["completed_at"] = timestamp()
        write_new(args.work/args.report_name, report)


def render(args):
    started_at = timestamp()
    manifest = read(ROOT/"source/derived_manifest.json")
    bpy.ops.wm.open_mainfile(filepath=manifest["overview"]["path"])
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world = bpy.data.worlds.new("验收CPU柔光")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.78, 0.85, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    support = collection("90_验收相机灯光_不导出", scene.collection)
    for name, location, energy, size in (("主柔光", (-15, 18, 45), 18000, 35), ("补柔光", (65, -20, 30), 12000, 25)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.shape, light.size = energy, "DISK", size
        obj = bpy.data.objects.new(name, light)
        support.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((30, -18, 0))-obj.location).to_track_quat("-Z", "Y").to_euler()
    cameras = [("overview_front", (32, 70, 65), (32, -18, 0), 58),
               ("overview_oblique", (85, 55, 70), (32, -18, 0), 67),
               ("overview_top", (32, -18, 100), (32, -18, 0), 57)]
    views = []
    for name, position, target, scale in cameras:
        camera = bpy.data.cameras.new(name)
        obj = bpy.data.objects.new(name, camera)
        support.objects.link(obj)
        obj.location = position
        obj.rotation_euler = (Vector(target)-obj.location).to_track_quat("-Z", "Y").to_euler()
        camera.type, camera.ortho_scale = "ORTHO", scale * 1.42
        scene.camera = obj
        path = args.work/(name+".png")
        assert not path.exists()
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        views.append({"path": str(path), "sha256": sha(path), "camera_position": position, "camera_target": target, "orthographic_scale": camera.ortho_scale})
    # 招牌近景只改变验收场景的实例可见性，不修改源包。
    for obj in scene.objects:
        if obj.instance_type == "COLLECTION":
            obj.hide_render = not obj.name.startswith("sign_fascia__")
    camera = bpy.data.cameras.new("sign_close")
    obj = bpy.data.objects.new("sign_close", camera)
    support.objects.link(obj)
    obj.location = (5.5, 12, 5)
    obj.rotation_euler = (Vector((5.5, 0, 0.45))-obj.location).to_track_quat("-Z", "Y").to_euler()
    camera.type, camera.ortho_scale = "ORTHO", 17
    scene.camera = obj
    scene.render.resolution_y = 900
    path = args.work/"sign_close.png"
    assert not path.exists()
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    views.append({"path": str(path), "sha256": sha(path), "camera_position": list(obj.location), "orthographic_scale": 17})
    for obj in scene.objects:
        if obj.instance_type == "COLLECTION":
            obj.hide_render = False
    scene.camera = bpy.data.objects["overview_front"]
    scene.render.resolution_y = 1700
    save_new(args.work/"overview_render_setup.blend")
    write_new(args.work/"render_validation.json", {"renderer": "Cycles CPU", "device": "CPU", "threads": 4, "samples": 16,
              "version": args.version, "started_at": started_at, "completed_at": timestamp(),
              "gpu_render_used": False, "views": views, "source_modified": False, "visual_review": "pending_image_inspection"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("build", "verify", "render"))
    parser.add_argument("--native-project", type=Path, required=True)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--version", default="v001")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--report-name", default="reopen_validation.json")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    global ROOT
    assert re.fullmatch(r"v\d{3}", args.version)
    ROOT = (args.source_root or REPO/"art_source/scenes/building_attachments"/args.version).resolve()
    assert ROOT == REPO/"art_source/scenes/building_attachments"/args.version
    args.native_project = args.native_project.resolve()
    args.manifest = (args.manifest or args.native_project/f"scenes/components/facilities/building_attachments/{args.version}/library_manifest.json").resolve()
    assert args.work.is_dir() and args.native_project.is_dir() and args.manifest.is_file()
    assert Path(args.report_name).name == args.report_name
    {"build": derive, "verify": verify, "render": render}[args.mode](args)


if __name__ == "__main__":
    main()
