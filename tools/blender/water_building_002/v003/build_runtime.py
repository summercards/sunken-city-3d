from __future__ import annotations

import json
import math
import re
import struct
from pathlib import Path
from typing import Any

ROOT = Path("D:/projects/sea")
SOURCE_DIR = ROOT / "art_source/scenes/water_building_002/v003"
CATALOG_PATH = SOURCE_DIR / "catalog.json"
INSTANCES_PATH = SOURCE_DIR / "component_instances.json"
EXPORT_MANIFEST_PATH = SOURCE_DIR / "export/v003/export_manifest.json"
SOURCE_VERIFICATION_PATH = Path("D:/projects/sea-work/water_building_002/v003/source_verification.json")
GODOT = ROOT / "godot"
COMPONENT_DIR = GODOT / "scenes/components/facilities/water_building_002"
ASSEMBLY_PATH = GODOT / "scenes/facilities/water_building_002.tscn"
RUNTIME_DATA_PATH = GODOT / "assets/data/water_building_002_instances.json"
TEST_PATH = GODOT / "tests/test_water_building_002.gd"
CAPTURE_PATH = GODOT / "tools/capture_water_building_002.gd"

ROLES = {
    "SEA_Matte": ("matte", "res://assets/materials/solar_cabin/sunny_matte.tres"),
    "SEA_Metal": ("metal", "res://assets/materials/solar_cabin/sunny_metal.tres"),
    "SEA_Gloss": ("gloss", "res://assets/materials/solar_cabin/sunny_gloss.tres"),
}
GROUP_PATHS = {
    "structure": "Structure",
    "furnishing": "Furnishings",
    "plant": "Plants",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def q(value: Any) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def write_text(path: Path, text: str) -> None:
    if not path.parent.is_dir():
        raise RuntimeError(f"missing output parent: {path.parent}")
    path.write_text(text, encoding="utf-8")


def parse_glb_json(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise RuntimeError(f"invalid GLB header: {path}")
    version, length = struct.unpack_from("<II", data, 4)
    if version != 2 or length != len(data):
        raise RuntimeError(f"invalid GLB version/length: {path}")
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk.rstrip(b" \t\r\n\0").decode("utf-8"))
        offset += 8 + chunk_length
    raise RuntimeError(f"missing GLB JSON chunk: {path}")


def material_role(name: str) -> str:
    match = re.match(r"^(SEA_(?:Matte|Metal|Gloss))(?:\.|$)", name)
    if not match or match.group(1) not in ROLES:
        raise RuntimeError(f"unsupported GLB material role: {name}")
    return match.group(1)


def matrix_mul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def blender_to_godot_matrix(row: dict[str, Any]) -> list[float]:
    x, y, z = (float(v) for v in row["rotation_euler_xyz"])
    cx, sx = math.cos(x), math.sin(x)
    cy, sy = math.cos(y), math.sin(y)
    cz, sz = math.cos(z), math.sin(z)
    rx = [[1.0, 0.0, 0.0], [0.0, cx, -sx], [0.0, sx, cx]]
    ry = [[cy, 0.0, sy], [0.0, 1.0, 0.0], [-sy, 0.0, cy]]
    rz = [[cz, -sz, 0.0], [sz, cz, 0.0], [0.0, 0.0, 1.0]]
    rotation = matrix_mul(rz, matrix_mul(ry, rx))
    scale = [float(v) for v in row["scale"]]
    blender_matrix = [[rotation[i][j] * scale[j] for j in range(3)] for i in range(3)]
    c = [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]]
    c_inverse = [[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]]
    basis = matrix_mul(c, matrix_mul(blender_matrix, c_inverse))
    p = row["position"]
    origin = [float(p[0]), float(p[2]), -float(p[1])]
    # Godot Transform3D serializes basis columns, followed by origin.
    return [basis[r][col] for col in range(3) for r in range(3)] + origin


def gd_transform_text(values: list[float]) -> str:
    # Text resource matrix grammar reads Basis rows; GDScript Basis(Vector3,...) takes columns.
    serialized = [values[col * 3 + row] for row in range(3) for col in range(3)] + values[9:]
    return "Transform3D(" + ", ".join(f"{value:.10g}" for value in serialized) + ")"


def component_mesh_records(entry: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, str]]:
    glb = ROOT / entry["glb_path"]
    document = parse_glb_json(glb)
    if document.get("images") or document.get("textures"):
        raise RuntimeError(f"component contains textures/images: {entry['key']}")
    nodes = document.get("nodes", [])
    scenes = document.get("scenes", [])
    if not scenes or len(scenes[0].get("nodes", [])) == 0:
        raise RuntimeError(f"component has no active scene roots: {entry['key']}")
    root_indices = set(scenes[0].get("nodes", []))
    mesh_records: list[dict[str, Any]] = []
    for node_index, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        mesh = document["meshes"][node["mesh"]]
        surfaces: list[str] = []
        for primitive in mesh.get("primitives", []):
            material_index = primitive.get("material")
            if material_index is None:
                raise RuntimeError(f"mesh primitive has no material: {entry['key']}")
            role = material_role(document["materials"][material_index].get("name", ""))
            surfaces.append(role)
        mesh_records.append({
            "node_index": node_index,
            "name": node.get("name", f"Mesh_{node_index}"),
            "surfaces": surfaces,
            "root_mesh": node_index in root_indices,
        })
    if not mesh_records:
        raise RuntimeError(f"component has no mesh nodes: {entry['key']}")
    return mesh_records, {record["name"]: record["name"] for record in mesh_records}


def build_wrapper(entry: dict[str, Any]) -> str:
    mesh_records, _ = component_mesh_records(entry)
    used_roles = sorted({role for record in mesh_records for role in record["surfaces"]})
    glb_path = "res://" + entry["glb_path"].removeprefix("godot/")
    lines = [f"[gd_scene load_steps={2 + len(used_roles)} format=3]", ""]
    lines.append(f'[ext_resource type="PackedScene" path={q(glb_path)} id="model"]')
    for role in used_roles:
        lines.append(f'[ext_resource type="Material" path={q(ROLES[role][1])} id="{ROLES[role][0]}"]')
    lines.extend(["", f'[node name={q(entry["key"])} type="Node3D"]'])
    building_class = "not_applicable" if entry["group"] == "plant" else "above_water"
    water_layer = "none" if entry["group"] == "plant" else "surface"
    water_role = "none" if entry["group"] == "plant" else "part"
    metadata = [
        ("asset_id", entry["asset_id"]),
        ("component_key", entry["key"]),
        ("source_version", "v003"),
        ("building_class", building_class),
        ("water_layer", water_layer),
        ("water_layer_role", water_role),
        ("category", entry["group"]),
        ("visual_only", entry["group"] == "plant"),
        ("collision", False),
        ("interactive", False),
    ]
    for key, value in metadata:
        if key == "building_class" and entry["group"] == "plant":
            continue
        if isinstance(value, bool):
            lines.append(f"metadata/{key} = {str(value).lower()}")
        else:
            lines.append(f"metadata/{key} = {q(value)}")
    lines.extend(["", '[node name="Visual" parent="." instance=ExtResource("model")]'])
    for record in mesh_records:
        parent = "Visual"
        # Godot scene importer always adds the imported scene root and sanitizes periods.
        imported_name = record["name"].replace(".", "_")
        lines.append(f'[node name={q(imported_name)} parent={q(parent)}]')
        for surface_index, role in enumerate(record["surfaces"]):
            lines.append(f'surface_material_override/{surface_index} = ExtResource("{ROLES[role][0]}")')
        lines.append("cast_shadow = 1")
    return "\n".join(lines) + "\n"


def build_runtime_data(catalog: list[dict[str, Any]], instances: list[dict[str, Any]], export_manifest: dict[str, Any]) -> dict[str, Any]:
    by_key = {entry["key"]: entry for entry in catalog}
    records = []
    for source in instances:
        entry = by_key[source["key"]]
        group = GROUP_PATHS[entry["group"]]
        records.append(
            {
                "name": source["name"],
                "key": source["key"],
                "asset_id": source["asset_id"],
                "group": group,
                "visual_only": entry["group"] == "plant",
                "position_blender": source["position"],
                "rotation_euler_xyz": source["rotation_euler_xyz"],
                "scale": source["scale"],
                "godot_transform": blender_to_godot_matrix(source),
            }
        )
    independent = {}
    if SOURCE_VERIFICATION_PATH.is_file():
        verification = read_json(SOURCE_VERIFICATION_PATH)
        v3 = verification.get("independent_v2_v3_verification", {})
        source_dg = verification.get("source_depsgraph", {})
        independent = {
            "source_verification_path": str(SOURCE_VERIFICATION_PATH).replace("\\", "/"),
            "source_sha256": verification.get("source_sha256_after"),
            "source_unchanged": verification.get("source_unchanged"),
            "instance_count": v3.get("v3_instance_count"),
            "crown_instances": v3.get("crown_instance_count"),
            "evaluated_triangles": source_dg.get("evaluated_triangles"),
            "evaluated_polygons": source_dg.get("evaluated_polygons"),
            "independent_passed": v3.get("passed"),
            "mesh_signature_mismatches": v3.get("mesh_signature_mismatches", []),
            "non_crown_instance_changes": v3.get("non_crown_matrix_diffs", []),
            "details_added": v3.get("volume_record_checks", {}).get("record_new_geometry_zero"),
        }
    return {
        "schema": "sea.water_building_002.runtime_instances",
        "asset_id": "SEA-SCENE-WATER-BUILDING-002",
        "source_version": "v003",
        "purpose": "initialization_and_test_only_not_production_auto_rehydration",
        "production_auto_rehydrate": False,
        "coordinate_contract": {
            "source": "Blender XY plane, +Z up",
            "godot_mapping": "C(x,y,z)=(x,z,-y)",
            "matrix_conversion": "C*M*C^-1",
            "rotation": "Euler XYZ radians",
        },
        "expected": {
            "components": 28,
            "instances": 167,
            "triangles": export_manifest["source"]["expanded_triangles_depsgraph"],
            "polygons": export_manifest["source"]["expanded_polygons_depsgraph"],
            "crown_instances": 18,
        },
        "independent_source_regression": independent,
        "instances": records,
    }


def build_assembly(catalog: list[dict[str, Any]], instances: list[dict[str, Any]]) -> str:
    by_key = {entry["key"]: entry for entry in catalog}
    lines = [f"[gd_scene load_steps={len(catalog) + 3} format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://src/world/sea_structure.gd" id="structure"]')
    lines.append('[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]')
    for index, entry in enumerate(catalog):
        lines.append(
            f'[ext_resource type="PackedScene" path="res://scenes/components/facilities/water_building_002/{entry["key"]}.tscn" id="c{index}"]'
        )
    lines.extend(["", '[node name="WaterBuilding002" type="Node3D"]', 'script = ExtResource("structure")'])
    root_metadata = [
        ("asset_id", "SEA-SCENE-WATER-BUILDING-002"),
        ("display_number", "002"),
        ("label", "水上普通建筑002"),
        ("asset_version", "v003"),
        ("building_class", "above_water"),
        ("water_layer", "surface"),
        ("water_layer_role", "entity"),
        ("category", "ordinary_building"),
        ("activity_role", "navigation_only"),
        ("source_version", "v003"),
        ("instances", 167),
        ("triangles", 10342),
        ("polygons", 6293),
        ("plants_visual_only", True),
    ]
    lines.append('asset_id = "SEA-SCENE-WATER-BUILDING-002"')
    lines.append('role = "ordinary_building"')
    for key, value in root_metadata:
        if isinstance(value, bool):
            lines.append(f"metadata/{key} = {str(value).lower()}")
        elif isinstance(value, int):
            lines.append(f"metadata/{key} = {value}")
        else:
            lines.append(f"metadata/{key} = {q(value)}")
    lines.extend(
        [
            "",
            '[node name="Visual" type="Node3D" parent="."]',
            'metadata/asset_id = "SEA-SCENE-WATER-BUILDING-002"',
            'metadata/source_version = "v003"',
            'metadata/visual_only = false',
            "",
            '[node name="Structure" type="Node3D" parent="Visual"]',
            'metadata/category = "structure"',
            'metadata/source_version = "v003"',
            'metadata/visual_only = false',
            "",
            '[node name="Furnishings" type="Node3D" parent="Visual"]',
            'metadata/category = "furnishing"',
            'metadata/source_version = "v003"',
            'metadata/visual_only = false',
            "",
            '[node name="Plants" type="Node3D" parent="Visual"]',
            'metadata/category = "plant"',
            'metadata/source_version = "v003"',
            'metadata/visual_only = true',
            "",
        ]
    )
    catalog_index = {entry["key"]: index for index, entry in enumerate(catalog)}
    for source in instances:
        entry = by_key[source["key"]]
        group = GROUP_PATHS[entry["group"]]
        parent = f"Visual/{group}"
        instance_id = source["name"]
        lines.append(
            f'[node name={q(instance_id)} parent={q(parent)} instance=ExtResource("c{catalog_index[source["key"]]}")]'
        )
        lines.append(f"transform = {gd_transform_text(blender_to_godot_matrix(source))}")
        lines.append(f"metadata/instance_id = {q(instance_id)}")
        lines.append(f"metadata/component_key = {q(source['key'])}")
        lines.append(f"metadata/asset_id = {q(source['asset_id'])}")
        lines.append('metadata/source_version = "v003"')
        lines.append(f'metadata/source_group = {q(group)}')
        lines.append(f"metadata/visual_only = {str(entry['group'] == 'plant').lower()}")
        lines.append("")
    lines.extend(
        [
            '[node name="Blockers" type="Node3D" parent="."]',
            'script = ExtResource("blocker")',
            'mode = "auto"',
            'target_path = NodePath("../Visual/Structure")',
            'blocks_water = true',
            'cell = 0.4',
            'metadata/target_root = "../Visual/Structure"',
            'metadata/waterline_source = "actual_source_mesh_intersection"',
            'metadata/activity_role = "navigation_only"',
            'metadata/actor_collision = false',
            'metadata/source_version = "v003"',
            "",
        ]
    )
    return "\n".join(lines)


def build_test_script() -> str:
    return r'''extends SceneTree

const PREFIX := "res://scenes/components/facilities/water_building_002/"
const ASSEMBLY := "res://scenes/facilities/water_building_002.tscn"
const RUNTIME_DATA := "res://assets/data/water_building_002_instances.json"
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const ROLE_MATERIALS := {
	"res://assets/materials/solar_cabin/sunny_matte.tres": "SEA_Matte",
	"res://assets/materials/solar_cabin/sunny_metal.tres": "SEA_Metal",
	"res://assets/materials/solar_cabin/sunny_gloss.tres": "SEA_Gloss",
}

var checks := 0
var failures := 0
var main: Node
var assembly: Node3D

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func triangle_count(node: Node) -> int:
	var total := 0
	for visual in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := visual as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			total += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(vertices.size() / 3)
	return total

func serialized_overrides(packed: PackedScene) -> Array:
	var result: Array = []
	var state := packed.get_state()
	for node_index in state.get_node_count():
		for property_index in state.get_node_property_count(node_index):
			var property := str(state.get_node_property_name(node_index, property_index))
			if not property.begins_with("surface_material_override"):
				continue
			var material := state.get_node_property_value(node_index, property_index) as Material
			result.append(material.resource_path if material != null else "")
	return result

func check_components() -> void:
	var files := DirAccess.get_files_at(PREFIX)
	var count := 0
	for file in files:
		if not file.ends_with(".tscn"):
			continue
		count += 1
		var packed := load(PREFIX + file) as PackedScene
		check(packed != null, file + " wrapper loads independently")
		if packed == null:
			continue
		var component := packed.instantiate() as Node3D
		check(component != null and component.transform.is_equal_approx(Transform3D.IDENTITY), file + " root identity")
		check(component.get_meta("source_version", "") == "v003", file + " v003 metadata")
		check(component.get_meta("asset_id", "") != "", file + " asset metadata")
		check(component.get_meta("water_layer", "") != "", file + " water layer metadata")
		check(component.get_meta("category", "") != "", file + " category metadata")
		var meshes := component.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), file + " imported mesh exists")
		for mesh_node in meshes:
			var mesh := mesh_node as MeshInstance3D
			check(mesh.mesh != null, file + " real mesh resource")
			check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, file + " shadow on")
			if mesh.mesh == null:
				component.free()
				continue
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as ShaderMaterial
				check(material != null, file + " serialized role material")
				if material == null:
					continue
				var palette := material.get_shader_parameter("palette") as Texture2D
				check(palette != null and palette.resource_path == PALETTE, file + " unique timber palette")
		var overrides := serialized_overrides(packed)
		check(not overrides.is_empty(), file + " serialized surface override")
		for path in overrides:
			check(ROLE_MATERIALS.has(path), file + " existing three-role material")
		component.free()
	check(count == 28, "28 stable wrappers")

func expected_transform(values: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(float(values[0]), float(values[1]), float(values[2])),
			Vector3(float(values[3]), float(values[4]), float(values[5])),
			Vector3(float(values[6]), float(values[7]), float(values[8]))
		),
		Vector3(float(values[9]), float(values[10]), float(values[11]))
	)

func min_rect_position(rects: Array) -> Vector2:
	var result := Vector2(INF, INF)
	for rect in rects:
		var value := rect as Rect2
		result.x = minf(result.x, value.position.x)
		result.y = minf(result.y, value.position.y)
	return result

func configure_real_main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	if main.cam != null:
		main.cam.set_process(false)
		main.cam.suspend_follow()
	if main.boat != null:
		main.boat.set_process(false)
	if main.hud != null:
		main.hud.hide()
	var economy := root.get_node_or_null("Economy")
	if economy != null:
		economy.set("ticking", false)
	for i in 8:
		await process_frame

func attach_assembly_to_real_main() -> void:
	assembly = main.get_node_or_null("World/SeaStructures/water_building_002") as Node3D
	check(assembly != null, "002 is serialized in production main, not injected by test")
	for i in 4:
		await process_frame

func check_assembly() -> void:
	check(assembly != null, "real main scene has water building assembly")
	if assembly == null:
		return
	check(assembly.get_meta("asset_id", "") == "SEA-SCENE-WATER-BUILDING-002", "assembly asset id")
	check(assembly.get_meta("source_version", "") == "v003", "assembly source version")
	check(assembly.get_meta("building_class", "") == "above_water", "assembly building class")
	check(assembly.get_meta("water_layer", "") == "surface", "assembly water layer")
	check(assembly.get_meta("water_layer_role", "") == "entity", "assembly entity role")
	check(assembly.get_meta("activity_role", "") == "navigation_only", "assembly navigation-only role")
	check(assembly.get_node_or_null("WalkArea") == null and assembly.get_node_or_null("Landing") == null and assembly.get_node_or_null("Zone") == null, "no interaction ownership nodes")
	var runtime := JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_DATA)) as Dictionary
	check(runtime.get("production_auto_rehydrate", true) == false, "runtime JSON is not production auto-rehydration")
	var expected: Dictionary = runtime.get("expected", {})
	check(int(expected.get("instances", -1)) == 167, "runtime expected instance count")
	check(int(expected.get("triangles", -1)) == 10342 and int(expected.get("polygons", -1)) == 6293, "runtime source geometry budget")
	var rows: Array = runtime.get("instances", [])
	check(rows.size() == 167, "runtime has 167 transform records")
	var actual_count := 0
	for group_name in ["Structure", "Furnishings", "Plants"]:
		var group := assembly.get_node("Visual/" + group_name)
		actual_count += group.get_child_count()
	check(actual_count == 167, "assembly has 167 grouped instances")
	var seen := 0
	for row in rows:
		var group_name := str(row.get("group", ""))
		var node := assembly.get_node_or_null("Visual/" + group_name + "/" + str(row.get("name", ""))) as Node3D
		check(node != null, "instance exists " + str(row.get("name", "")))
		if node == null:
			continue
		seen += 1
		check(node.get_meta("component_key", "") == row.get("key", ""), "instance key " + str(row.get("name", "")))
		var expected_xf := expected_transform(row.get("godot_transform", []))
		check(node.transform.is_equal_approx(expected_xf), "C*M*C^-1 transform " + str(row.get("name", "")))
	check(seen == 167, "all runtime transforms resolve")
	var crowns := 0
	var non_uniform_crowns := 0
	for row in rows:
		if str(row.get("key", "")) != "crown_a" and str(row.get("key", "")) != "crown_b":
			continue
		crowns += 1
		var scale: Array = row.get("scale", [])
		if scale.size() == 3 and (not is_equal_approx(float(scale[0]), float(scale[1])) or not is_equal_approx(float(scale[1]), float(scale[2]))):
			non_uniform_crowns += 1
	check(crowns == 18 and non_uniform_crowns >= 17, "18 crown scales retain source non-uniform volume revision")
	check(triangle_count(assembly) == 10342, "actual imported full-scene triangles")
	var role_paths := {}
	var texture_paths := {}
	for mesh_node in assembly.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "all assembly meshes cast shadows")
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			check(material != null, "all surfaces have a serialized shader material")
			if material == null:
				continue
			role_paths[material.resource_path] = true
			var palette := material.get_shader_parameter("palette") as Texture2D
			if palette != null:
				texture_paths[palette.resource_path] = true
	check(role_paths.size() == 3 and role_paths.has("res://assets/materials/solar_cabin/sunny_matte.tres") and role_paths.has("res://assets/materials/solar_cabin/sunny_metal.tres") and role_paths.has("res://assets/materials/solar_cabin/sunny_gloss.tres"), "three unique role materials")
	check(texture_paths.size() == 1 and texture_paths.has(PALETTE), "unique timber palette texture")
	var plants := assembly.get_node("Visual/Plants")
	check(plants.get_meta("visual_only", false), "Plants group visual_only")
	for child in plants.get_children():
		check(child.get_meta("visual_only", false), "plant instance visual_only " + str(child.name))
	check(assembly.find_children("*", "CollisionObject3D", true, false).is_empty(), "navigation-only assembly has no actor collision")

func check_blockers_follow_geometry() -> void:
	var blockers := assembly.get_node("Blockers")
	check(blockers.mode == "auto" and blockers.blocks_water, "Blockers auto water mode")
	check(str(blockers.target_path) == "../Visual/Structure", "Blockers target actual Structure meshes")
	var water_y: float = main.water_node.global_position.y
	assembly.rebuild_blockers(water_y, 1.6)
	check(assembly.water_block_rects.size() > 0, "Blockers rebuild finds actual waterline geometry")
	var shapes: Array = main._water_shapes()
	for rect: Rect2 in assembly.water_block_rects:
		var represented := false
		for shape: Dictionary in shapes:
			if Vector2(float(shape.get("x", INF)), float(shape.get("z", INF))).distance_to(rect.get_center()) < 0.001 and absf(float(shape.get("hx", -1.0)) * 2.0 - rect.size.x) < 0.001 and absf(float(shape.get("hz", -1.0)) * 2.0 - rect.size.y) < 0.001:
				represented = true
				break
		check(represented, "002 footprint collected by actual main water navigation")
	var before := min_rect_position(assembly.water_block_rects)
	assembly.position += Vector3(12.0, 0.0, 16.0)
	assembly.rebuild_blockers(water_y, 1.6)
	var after := min_rect_position(assembly.water_block_rects)
	check((after - before - Vector2(12.0, 16.0)).length() < 0.05, "blockers follow assembly transform, not pinned world coordinates")
	assembly.position -= Vector3(12.0, 0.0, 16.0)
	assembly.rebuild_blockers(water_y, 1.6)

func run() -> void:
	check_components()
	await configure_real_main()
	await attach_assembly_to_real_main()
	check_assembly()
	check_blockers_follow_geometry()
	print("[water-building-002] ", checks, " checks, ", failures, " failures")
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
'''


def build_capture_script() -> str:
    return r'''extends SceneTree

const ASSEMBLY := "res://scenes/facilities/water_building_002.tscn"
const OUTPUT_PREFIX := "res://outputs/water-building-002-"

var checks := 0
var failures := 0
var main: Node
var assembly: Node3D
var evidence := {
	"scene": "res://scenes/main.tscn",
	"assembly": ASSEMBLY,
	"frames": [],
	"daylight_hour": 12.0,
	"hud_disabled": true,
	"main_camera_used": true,
	"ticks_disabled": true,
	"fit_margin": 1.25,
}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for visual in node.find_children("*", "GeometryInstance3D", true, false):
		if visual is MeshInstance3D:
			var mesh := visual as MeshInstance3D
			if mesh.mesh == null:
				continue
			var part: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			result = part if first else result.merge(part)
			first = false
		elif visual is MultiMeshInstance3D:
			var multi := visual as MultiMeshInstance3D
			if multi.multimesh == null or multi.multimesh.mesh == null:
				continue
			for index in multi.multimesh.instance_count:
				var transform: Transform3D = multi.global_transform * multi.multimesh.get_instance_transform(index)
				var part: AABB = transform * multi.multimesh.mesh.get_aabb()
				result = part if first else result.merge(part)
				first = false
	return result

func union_bounds(a: AABB, b: AABB) -> AABB:
	if a.size == Vector3.ZERO:
		return b
	if b.size == Vector3.ZERO:
		return a
	return a.merge(b)

func fit_distance(box: AABB, fov_degrees: float) -> float:
	var half_angle := deg_to_rad(fov_degrees * 0.5)
	var radius := maxf(maxf(box.size.x, box.size.y), box.size.z) * 0.5
	return maxf(radius / tan(half_angle) * 1.25, 12.0)

func frame(eye: Vector3, target: Vector3, fov_degrees: float) -> void:
	main.cam.fov = fov_degrees
	main.cam.near = 0.1
	main.cam.far = 800.0
	main.cam.global_position = eye
	main.cam.look_at(target, Vector3.UP)
	main.cam.make_current()

func shot(name: String, eye: Vector3, target: Vector3, fov_degrees: float) -> void:
	frame(eye, target, fov_degrees)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and image.get_width() >= 1280 and image.get_height() >= 720, "real renderer frame " + name)
	if image != null:
		check(image.save_png(OUTPUT_PREFIX + name + ".png") == OK, "saved frame " + name)
	evidence.frames.append(name)

func configure_main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.suspend_follow()
	main.boat.set_process(false)
	main.hud.hide()
	if main.markers != null:
		main.markers.hide()
	if main.ribbon != null:
		main.ribbon.hide()
	if main._calendar_label != null:
		main._calendar_label.hide()
	var economy := root.get_node_or_null("Economy")
	if economy != null:
		economy.set("ticking", false)
	if main.world_clock != null:
		main.world_clock.paused = true
	if main.weather_service != null:
		main.weather_service.paused = true
	main.daylight_rig.apply(12.0)
	for i in 12:
		await process_frame

func attach_assembly() -> void:
	assembly = main.get_node_or_null("World/SeaStructures/water_building_002") as Node3D
	check(assembly != null, "002 is serialized in production main, not injected by test")
	for i in 8:
		await process_frame

func run() -> void:
	await configure_main()
	await attach_assembly()
	check(assembly != null, "water building is present in isolated real main runner")
	if assembly == null:
		print("[water-building-002-render] ", checks, " checks, ", failures, " failures")
		quit(1)
		return
	var building_box := bounds(assembly)
	check(building_box.size != Vector3.ZERO, "building has measured rendered bounds")
	var building_center := building_box.get_center()
	var hero_distance := fit_distance(building_box, 43.0)
	await shot("hero", building_center + Vector3(hero_distance * 0.78, hero_distance * 0.52, hero_distance * 0.78), building_center, 43.0)
	await shot("back", building_center + Vector3(-hero_distance * 0.78, hero_distance * 0.48, -hero_distance * 0.78), building_center, 43.0)
	var roof_target := building_center + Vector3(0.0, building_box.size.y * 0.10, 0.0)
	var roof_distance := fit_distance(building_box, 48.0)
	await shot("roof", roof_target + Vector3(0.0, roof_distance * 1.45, roof_distance * 0.12), roof_target, 48.0)
	var context := main.get_node_or_null("World/SeaStructures/floating_shop") as Node3D
	var context_box := building_box
	if context != null:
		context_box = union_bounds(building_box, bounds(context))
	var context_center := context_box.get_center()
	var context_distance := fit_distance(context_box, 46.0)
	await shot("shop-context", context_center + Vector3(context_distance * 0.82, context_distance * 0.44, context_distance * 0.82), context_center, 46.0)
	evidence.bounds = {
		"position": building_box.position,
		"size": building_box.size,
		"center": building_center,
	}
	evidence.context = {"floating_shop_present": context != null, "bounds": context_box}
	var file := FileAccess.open("res://outputs/water-building-002-evidence.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "  "))
		file.close()
		check(true, "evidence JSON saved")
	else:
		check(false, "evidence JSON opened")
	print("[water-building-002-render] ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
'''


def main() -> None:
    catalog_data = read_json(CATALOG_PATH)
    instances_data = read_json(INSTANCES_PATH)
    export_manifest = read_json(EXPORT_MANIFEST_PATH)
    catalog = catalog_data["components"]
    instances = instances_data["instances"]
    if len(catalog) != 28:
        raise RuntimeError(f"expected 28 catalog components, got {len(catalog)}")
    if len(instances) != 167:
        raise RuntimeError(f"expected 167 source instances, got {len(instances)}")
    if export_manifest["source"]["expanded_triangles_depsgraph"] != 10342:
        raise RuntimeError("export manifest triangle budget is not 10342")
    if export_manifest["source"]["expanded_polygons_depsgraph"] != 6293:
        raise RuntimeError("export manifest polygon budget is not 6293")
    for entry in catalog:
        glb = ROOT / entry["glb_path"]
        if not glb.is_file():
            raise RuntimeError(f"missing component GLB: {glb}")
        write_text(COMPONENT_DIR / f"{entry['key']}.tscn", build_wrapper(entry))
        import_path = Path(str(glb) + ".import")
        if import_path.is_file():
            settings = import_path.read_text(encoding="utf-8")
            settings = settings.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=0")
            settings = settings.replace("meshes/generate_lods=true", "meshes/generate_lods=false")
            if settings != import_path.read_text(encoding="utf-8"):
                write_text(import_path, settings)
    runtime_data = build_runtime_data(catalog, instances, export_manifest)
    write_text(RUNTIME_DATA_PATH, json.dumps(runtime_data, ensure_ascii=False, indent=2) + "\n")
    write_text(ASSEMBLY_PATH, build_assembly(catalog, instances))
    write_text(TEST_PATH, build_test_script())
    write_text(CAPTURE_PATH, build_capture_script())
    print(
        json.dumps(
            {
                "components": len(catalog),
                "instances": len(instances),
                "triangles": runtime_data["expected"]["triangles"],
                "polygons": runtime_data["expected"]["polygons"],
                "wrappers": str(COMPONENT_DIR).replace("\\", "/"),
                "assembly": str(ASSEMBLY_PATH).replace("\\", "/"),
                "runtime_data": str(RUNTIME_DATA_PATH).replace("\\", "/"),
                "test": str(TEST_PATH).replace("\\", "/"),
                "capture": str(CAPTURE_PATH).replace("\\", "/"),
                "main_modified": False,
                "engine_run": False,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
