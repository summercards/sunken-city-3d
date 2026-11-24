"""Stage the v010 ranch assembly and its independently editable Godot components."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration/full-v010"
EXPORT = WORK / "export"
CANDIDATE = WORK / "godot_candidate"
SOURCE = ROOT / "art_source/scenes/ocean_rooftop_farm/v010"
MODELS = Path("assets/models/facilities/rooftop_ranch")
COMPONENTS = Path("scenes/components/facilities/rooftop_ranch")
HEIGHT = 52.04
ACTOR = 8192
HULL = 4096


def write(path, sections):
    target = CANDIDATE / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n\n".join(sections) + "\n")


def vector(values, kind="Vector3"):
    return kind + "(" + ", ".join(f"{v:.8g}" for v in values) + ")"


def surface(x0, x1, z0, z1, y0, y1=None):
    y1 = y0 if y1 is None else y1
    a, b, c, d = (x0, y0, z0), (x0, y1, z1), (x1, y1, z1), (x1, y0, z0)
    return [*a, *c, *b, *a, *d, *c]


def box(center, size):
    return {"center": center, "size": size}


def install_component(key, info, asset_id, version="v010"):
    # Existing house resources keep their stable paths and may still be opened independently.
    folder = "house/v010" if version == "v010" and (ROOT / MODELS / "house/v010" / f"{key}.glb").exists() else version
    model = MODELS / folder / f"{key}.glb"
    target = CANDIDATE / model
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(EXPORT / f"{key}.glb", target)
    model_res = f"res://{model}"
    digest = hashlib.md5(model_res.encode()).hexdigest()
    cache = f"res://.godot/imported/{key}.glb-{digest}.scn"
    write(f"{model}.import", [
        f'[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"',
        f'[deps]\n\nsource_file="{model_res}"\ndest_files=["{cache}"]',
        '[params]\n\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=true\nanimation/import=false'
        '\ngltf/embedded_image_handling=0\nimport_script/path="res://tools/rooftop_ranch_palette_import.gd"\n_subresources={}',
    ])
    solids = info["collision"] + {
        "rail_section": [box((0, .44, 0), (4.25, .89, .14))],
        "pier_dock": [box((x, 1.03, .92), (.40, .8, .40)) for x in (-2.1, 2.1)],
        "access_stairs": [
            box((-1.39, 1.66, .21), (.11, 1.02, 3.89)) | {"pitch": .545},
            box((1.39, 4.18, .24), (.11, 1.02, 3.89)) | {"pitch": -.545},
        ],
    }.get(key, [])
    hull = {
        "base_slab": [box((0, .10, 0), (34.4, .20, 13.8))],
        "facade_bay": [box((0, 2.39, 0), (4.28, 4.78, .30))],
        "corner_pier": [box((0, 2.45, 0), (.50, 4.9, .50))],
        "pier_dock": [
            box((0, .71, 0), (4.60, .20, 2.70)),
            box((-1.8, .30, 0), (.50, .60, 2.60)),
            box((1.8, .30, 0), (.50, .60, 2.60)),
        ],
    }.get(key, [])
    if version == "v011":
        if key.startswith("facade_bay"):
            hull = [box((0, 2.15, 0), (3.74, 4.30, .38))]
        elif key == "corner_pier":
            hull = [box((0, 2.16, 0), (.50, 4.32, .50))]
        elif key == "base_slab":
            hull = [box((0, .10, 0), (34.72, .20, 13.82))]
    faces = {
        "pier_dock": surface(-2.30, 2.30, -1.36, 1.35, .810),
        "access_stairs": (
            surface(-1.39, -.05, 2.05, 2.72, .281)
            + surface(-1.39, -.05, -1.755, 2.05, 2.581, .281)
            + surface(-1.425, 1.425, -2.665, -1.755, 2.581)
            + surface(.05, 1.39, -1.755, 2.05, 2.581, 10.20-5.20871)
            + surface(.05, 1.39, 2.05, 2.645, 10.20-5.20871)
        ),
        "upper_stair_bridge": (
            surface(-1.459, .24, -.83, .83, .332)
            + surface(.24, 1.456, -.27, .83, .332)
        ),
        # Main treads are perpendicular to the paving. The gentle cap is owned by each step.
        "terrace_step": surface(-2.13, 2.13, -.432/.86, .432/.86, .36, 0),
    }.get(key, [])
    if version == "v014" and key == "access_stairs":
        solids = [
            box((-1.39, 1.39, .19), (.11, .89, 3.95)) | {"pitch": .36},
            box((1.39, 2.86, .19), (.11, .89, 3.95)) | {"pitch": -.36},
            box((0, 2.11, -2.54), (2.8, .80, .11)),
        ]
        faces = (
            surface(-1.39, -.05, 2.05, 2.744, .281)
            + surface(-1.39, -.05, -1.755, 2.05, 1.73, .281)
            + surface(-1.425, 1.425, -2.59, -1.755, 1.73)
            + surface(.05, 1.39, -1.755, 2.05, 1.73, 3.19129)
            + surface(.05, 1.39, 2.05, 2.645, 3.19129)
        )
    if key.startswith("deck_tile_"):
        faces = surface(-1.077, 1.077, -1.148, 1.148, .20)
    # Separate bodies keep moving facility solids and the marine hull independent.
    def bodies(name, layer, boxes, mesh_faces):
        if not boxes and not mesh_faces:
            return
        nodes.append(f'[node name="{name}" type="StaticBody3D" parent="."]\ncollision_layer = {layer}\ncollision_mask = 0')
        if mesh_faces:
            resources.append(f'[sub_resource type="ConcavePolygonShape3D" id="{name}Floor"]\n'
                             f'data = {vector(mesh_faces, "PackedVector3Array")}')
            nodes.append(f'[node name="Floor" type="CollisionShape3D" parent="{name}"]\n'
                         f'shape = SubResource("{name}Floor")\nmetadata/walk_surface = true')
        for index, shape in enumerate(boxes):
            sid = f"{name}Box{index}"
            resources.append(f'[sub_resource type="BoxShape3D" id="{sid}"]\nsize = {vector(shape["size"])}')
            pose = f'position = {vector(shape["center"])}'
            if "pitch" in shape:
                pose += f'\nrotation = Vector3({shape["pitch"]}, 0, 0)'
            nodes.append(f'[node name="Segment{index}" type="CollisionShape3D" parent="{name}"]\n'
                         f'{pose}\nshape = SubResource("{sid}")')
    resources = ['[gd_scene format=3]', f'[ext_resource type="PackedScene" path="{model_res}" id="model"]',
                 '[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blockers"]']
    submerged = key.startswith("deep_")
    nodes = [f'[node name="Piece" type="Node3D"]\nmetadata/asset_id = "{asset_id}"'
             + ('\nmetadata/visual_only = true\nmetadata/building_class = "underwater"'
                '\nmetadata/water_layer = "submerged"\nmetadata/water_layer_role = "part"' if submerged else ''),
             '[node name="Visual" parent="." instance=ExtResource("model")]']
    bodies("Solid", ACTOR, solids, faces)
    bodies("Hull", HULL, hull, [])
    if submerged:
        assert not solids and not hull and not faces
        resources.pop()
    else:
        nodes.append('[node name="Blockers" type="Node3D" parent="."]\nscript = ExtResource("blockers")'
                     + ('' if hull else '\nmode = "none"\nblocks_water = false'))
    prefab = COMPONENTS / version / f"{key}.tscn"
    write(prefab, resources + nodes)
    assert hashlib.sha256(target.read_bytes()).hexdigest() == info["glb_sha256"]
    info.update(model=f"godot/{model}", prefab=f"godot/{prefab}", solid=bool(solids or faces), hull=bool(hull))
    return prefab


def collision_initial(part):
    key = part["key"]
    return part["states"][0][4] and key != "house_corner_patch" and (
        not key.startswith("deck_tile_") or part["area"] == "static")


def add_assembly(layout, wrappers):
    resources = ['[gd_scene format=3]']
    for identifier, kind, path in [
        ("zone", "Script", "src/facilities/rooftop_ranch_zone.gd"),
        ("walk", "Script", "src/navigation/walk_area.gd"),
        ("landing", "Script", "src/navigation/landing_point.gd"),
        ("prompt", "Script", "src/facilities/rooftop_ranch_repair_prompt.gd"),
        ("blockers", "Script", "src/world/blocker_set.gd"),
        ("gulls", "PackedScene", "scenes/decorations/animals/rooftop_ranch_gulls.tscn"),
        ("npc", "PackedScene", "scenes/npc/rooftop_npc_stations.tscn"),
        ("docking", "PackedScene", "scenes/components/docking_area.tscn"),
    ]:
        resources.append(f'[ext_resource type="{kind}" path="res://{path}" id="{identifier}"]')
    resources.extend(f'[ext_resource type="PackedScene" path="res://{path}" id="{key}"]' for key, path in wrappers.items())
    nodes = [
        '[node name="RooftopRanch" type="Node3D"]\nposition = Vector3(0, -55.92, 0)\nscript = ExtResource("zone")'
        '\nzone_id = "rooftop_ranch"\nzone_label = "顶层牧场"\nwater_layer = "amphibious"'
        '\nwater_layer_role = "entity"\ngeometry_source = "scene"'
        '\nmetadata/asset_id = "SEA-SCENE-ORF7-ASSEMBLY"\nmetadata/asset_version = "v010"'
        '\nmetadata/building_class = "above_water"\nmetadata/component_instances = 390\nmetadata/component_catalog = 46',
        f'[node name="Models" type="Node3D" parent="."]\nposition = Vector3(0, {HEIGHT}, 0)',
        '[node name="Blockers" type="Node3D" parent="Models"]\nscript = ExtResource("blockers")'
        '\nmode = "none"\nblocks_water = false',
        '[node name="BuildingAnimation" type="AnimationPlayer" parent="."]',
        '[node name="RepairPrompts" type="Node3D" parent="."]',
        '[node name="NpcStations" parent="." instance=ExtResource("npc")]',
        '[node name="RooftopRanchGulls" parent="." instance=ExtResource("gulls")]\n'
        'altitude = 66.9\nradius = Vector2(16.5, 9)',
        '[node name="WalkAreas" type="Node3D" parent="."]',
        '[node name="Walk_rooftop_ranch_access" type="Node3D" parent="WalkAreas"]\n'
        'script = ExtResource("walk")\narea_id = "rooftop_ranch_access"\nscene_collision = true'
        '\nzone_id = "rooftop_ranch"\nlocal_surface_height = true\nsurface_y = 62.24'
        '\nspan_min = 57.04\nspan_max = 63.0',
    ]
    access = "WalkAreas/Walk_rooftop_ranch_access"
    nodes.extend([
        f'[node name="Landing_main" type="Marker3D" parent="{access}"]\nposition = Vector3(18.36, 57.35, 6.28)'
        '\nscript = ExtResource("landing")\nlanding_id = "main"\nlanding_label = "顶层牧场上岸入口"'
        '\nmetadata/check_park_clearance = true',
        f'[node name="BoatPark" type="Marker3D" parent="{access}/Landing_main"]'
        '\nposition = Vector3(0, -0.31, 2.65)\nrotation = Vector3(0, 1.570796327, 0)',
        f'[node name="DockEdge" type="Marker3D" parent="{access}/Landing_main"]\nposition = Vector3(0, -0.01, 0.95)',
        f'[node name="DockingArea" parent="{access}/Landing_main/DockEdge" instance=ExtResource("docking")]'
        '\nposition = Vector3(0, -0.30, 1.45)',
    ])
    points = {
        "west": (-14.3, 10.56, 5.65), "center": (-2.70, 10.20, 5.65), "east": (4.6, 10.20, 5.65),
        "greenhouse_floor": (8.30, 10.20, 5.65), "tower_floor": (15.3, 10.20, 5.65),
        "house": (-11.825, 10.56, 1.72), "greenhouse": (9.11, 10.20, 3.68),
        "tower": (16.17, 10.20, 2.28), "construction": (1.0, 10.20, 5.65),
    }
    for key, point in points.items():
        label = {"house": "屋顶小屋", "construction": "牧场设施"}.get(key, layout["clips"][key]["name"])
        x, y, z = point
        verb = "搭建" if key == "construction" else "清理" if key in {"greenhouse", "tower"} else "修复"
        prompt_id = "rooftop_ranch_house_repair" if key == "house" else f"rooftop_ranch_{key}"
        nodes.append(f'[node name="{key}" type="Node3D" parent="RepairPrompts"]\n'
                     f'position = {vector((x, y + HEIGHT, z))}\nscript = ExtResource("prompt")\n'
                     f'repair_area = "{key}"\nid = "{prompt_id}"\nlabel = "{label}"\nverb = "{verb}"\n'
                     'focus_anchor = "node"\nfocus_radius = 1.25\nauto_radius = false')
    editable = []
    for i, part in enumerate(layout["placements"]):
        key, name = part["key"], part["name"]
        part["node"] = re.sub(r"[^a-zA-Z0-9]+", "_", name).strip("_") + f"_{i:03d}"
        _, pos, rotation, scale, visible = part["states"][0]
        initial = collision_initial(part)
        nodes.append(f'[node name="{part["node"]}" parent="Models" instance=ExtResource("{key}")]\n'
                     f'position = {vector(pos)}\nquaternion = {vector(rotation, "Quaternion")}\nscale = {vector(scale)}\n'
                     f'visible = {str(visible).lower()}\nmetadata/component_key = "{key}"\n'
                     f'metadata/placement = {json.dumps(name, ensure_ascii=False)}')
        info = layout["components"][key]
        if info["solid"] and not initial:
            nodes.append(f'[node name="Solid" parent="Models/{part["node"]}" index="1"]\ncollision_layer = 0')
            editable.append(f'[editable path="Models/{part["node"]}"]')
        if key.startswith("deck_tile_") and name.startswith(("Paving 05.", "Paving 06.")):
            # Trim tile tops beneath the adjacent terrace stair caps so the join is flush.
            left = name.startswith("Paving 05.")
            x0, x1 = (-1.077, -6.912 - pos[0]) if left else (-6.048 - pos[0], 1.077)
            add_instance_floor(resources, nodes, editable, part["node"], surface(x0, x1, -1.148, 1.148, .20))
        if key == "pier_dock":
            # Upper end touches the lowest stair landing, lower end meets the deck.
            extension = surface(-1.20, .14, -1.07, -.42, .99971, .81)
            add_instance_floor(resources, nodes, editable, part["node"],
                               surface(-2.3, 2.3, -1.36, 1.35, .81) + extension)
    write("scenes/facilities/rooftop_ranch.tscn", resources + nodes + list(dict.fromkeys(editable)))
    runtime = {key: layout[key] for key in ("version", "clips")}
    runtime["placements"] = [{k: part[k] for k in ("node", "key", "area", "states")}
                             for part in layout["placements"] if len(part["states"]) > 1]
    write(COMPONENTS / "v010/repair_layout.json", [json.dumps(runtime, separators=(",", ":"), ensure_ascii=False)])


def add_instance_floor(resources, nodes, editable, name, faces):
    identifier = f"Floor_{name}"
    resources.append(f'[sub_resource type="ConcavePolygonShape3D" id="{identifier}"]\n'
                     f'data = {vector(faces, "PackedVector3Array")}')
    nodes.append(f'[node name="Floor" parent="Models/{name}/Solid" index="0"]\nshape = SubResource("{identifier}")')
    editable.append(f'[editable path="Models/{name}"]')


if __name__ == "__main__":
    layout = json.loads((EXPORT / "runtime_layout.json").read_text())
    plan = json.loads((SOURCE / "component_plan.json").read_text())
    ids = {row["key"]: row["asset_id"] for row in plan["components"]}
    wrappers = {key: install_component(key, info, ids[key]) for key, info in layout["components"].items()}
    add_assembly(layout, wrappers)
    (WORK / "installed_assets.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
    print(f"Staged {len(wrappers)} component scenes and {len(layout['placements'])} placements in {CANDIDATE}")
