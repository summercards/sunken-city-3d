import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(bpy.data.filepath).resolve().parent
OUTPUT = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration" / SOURCE.name
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
ROLES = {"SEA_Matte","SEA_Gloss","SEA_Emission","SEA_Metal"}
checks = 0


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(message)


def near(a, b):
    return (Vector(a) - Vector(b)).length < .00015


def state(obj, expected):
    expected_xyz, expected_angles, expected_scale, visible = expected
    return (near(obj.location, expected_xyz) and near(obj.rotation_euler, expected_angles)
            and near(obj.scale, expected_scale) and obj.hide_render == (not visible)
            and obj.hide_viewport == (not visible))


def audit_palette(*, whole=False):
    images = [image for image in bpy.data.images if image.source == "FILE"]
    check(len(images) == 1, "Expected one external palette image")
    image = images[0]
    check(Path(bpy.path.abspath(image.filepath)).resolve() == PALETTE, image.filepath)
    check(image.packed_file is None, "Palette must stay external")
    check(image.size[0] == image.size[1] == 512, "Palette size")
    roles = {material.name for material in bpy.data.materials}
    check(roles == ROLES if whole else roles and roles <= ROLES, roles)
    for material in bpy.data.materials:
        textures = [node for node in material.node_tree.nodes if node.type=="TEX_IMAGE"]
        check(len(textures)==1,material.name)
        texture = textures[0]
        check(texture.image == image and texture.interpolation == "Closest", material.name)
        check(texture.inputs["Vector"].links[0].from_node.uv_map == "PaletteUV", material.name)
        shader = material.node_tree.nodes.get("Principled BSDF")
        check(shader.inputs["Base Color"].links[0].from_node==texture,material.name)


def audit_collection(coll):
    check(near(coll.instance_offset,(0,0,0)), coll.name)
    check(len(coll.objects) > 0, coll.name)
    lowest = 1e6
    min_x = min_y = 1e6
    max_x = max_y = -1e6
    for obj in coll.objects:
        check(obj.type == "MESH" and obj.parent is None, obj.name)
        check(near(obj.location, (0,0,0)) and near(obj.rotation_euler, (0,0,0))
              and near(obj.scale, (1,1,1)), obj.name)
        uv = obj.data.uv_layers.active
        check(uv.name == "PaletteUV" and uv.active_render, obj.name)
        check(len(obj.data.polygons)>0,obj.name)
        for vertex in obj.data.vertices:
            x,y,z = vertex.co
            min_x,min_y,lowest = min(x,min_x),min(y,min_y),min(z,lowest)
            max_x,max_y = max(x,max_x),max(y,max_y)
        for mod in obj.modifiers:
            if mod.type=="BEVEL":
                check(mod.segments == 3 and mod.width>0, obj.name)
        for poly in obj.data.polygons:
            coords = [uv.data[i].uv for i in poly.loop_indices]
            a,b = (int(coord*8) for coord in coords[0])
            valid = all(a+.125-1e-6 <= u*8 <= a+.875+1e-6
                        and b+.125-1e-6 <= v*8 <= b+.875+1e-6 for u,v in coords)
            uv_area = abs(sum(p.x*q.y-p.y*q.x for p,q in zip(coords,coords[1:]+coords[:1])))
            check(valid and uv_area>1e-7 and poly.area>1e-8,obj.name)
    check(abs(lowest)<.0001 and abs(min_x+max_x)<.0001 and abs(min_y+max_y)<.0001,coll.name)


def finish_packages():
    bpy.context.preferences.filepaths.save_version = 0
    packages = sorted(SOURCE.glob("component_packages/*/*.blend"))
    for path in packages:
        bpy.ops.wm.open_mainfile(filepath=str(path))
        bpy.context.preferences.filepaths.save_version = 0
        scene = bpy.context.scene
        check(len(bpy.data.scenes) == 1 and scene.name.startswith("Asset | "), path.name)
        coll = scene.collection.children[0]
        audit_palette()
        audit_collection(coll)
        for workspace in bpy.data.workspaces:
            for screen in workspace.screens:
                for area in screen.areas:
                    if area.type == "VIEW_3D":
                        area.spaces.active.region_3d.view_location = (0,0,.75)
                        area.spaces.active.region_3d.view_distance = max(2.8, max(o.dimensions.length for o in coll.objects)*1.4)
                        area.spaces.active.shading.type = "MATERIAL"
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        manifest_path = path.with_name("asset_manifest.json")
        manifest = json.loads(manifest_path.read_text())
        manifest["source_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
        bpy.ops.wm.open_mainfile(filepath=str(path))
        check(bpy.context.scene.name == scene_name(path) and len(bpy.context.scene.objects)>0,path.name)
        audit_palette()
    return len(packages)


def scene_name(path):
    return "Asset | " + path.stem


def route_bvh(scene):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    vertices, faces, labels = [], [], []
    for instance in scene.objects:
        if instance.instance_type != "COLLECTION" or instance.hide_render:
            continue
        if instance.location.z < 4:
            continue
        for source in instance.instance_collection.objects:
            evaluated = source.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            if mesh is None:
                continue
            matrix = instance.matrix_world @ evaluated.matrix_local
            offset = len(vertices)
            vertices.extend(matrix @ vertex.co for vertex in mesh.vertices)
            faces.extend(tuple(index+offset for index in face.vertices) for face in mesh.polygons)
            labels.extend([instance.name]*len(mesh.polygons))
            evaluated.to_mesh_clear()
    return BVHTree.FromPolygons(vertices,faces),labels


def audit_routes(scene, routes):
    text = (ROOT/"godot/src/avatar/avatar_dimensions.gd").read_text()
    radius,height = (float(re.search(rf"const BODY_{key} := ([.\d]+)",text)[1]) for key in ("RADIUS","HEIGHT"))
    down = Vector((0,0,-1))
    allowed = ("Paving ","Terrace Step","Continuous connector","Access Stairs")
    circle = [Vector((math.cos(i*math.tau/8),math.sin(i*math.tau/8),0)) for i in range(8)]
    samples = {}
    for frame in (1,71,112,191,240,300):
        scene.frame_set(frame)
        tree,labels = route_bvh(scene)
        distances = {}
        for name,points in routes.items():
            previous = None
            count, largest_step = 0, 0.0
            for a,b in zip(points,points[1:]):
                a,b = Vector((*a,0)),Vector((*b,0))
                steps = math.ceil((b-a).length/.078)
                for i in range(steps+1):
                    point = a.lerp(b,i/steps)
                    heights = []
                    for offset in (Vector(),*(v*radius*.80 for v in circle)):
                        origin = point+offset+Vector((0,0,11.01))
                        hit, normal, face, _ = tree.ray_cast(origin,down,.98)
                        if hit is not None and normal.z>.60 and labels[face].startswith(allowed):
                            heights.append(hit.z)
                    marker = (frame,name,tuple(round(value,2) for value in point))
                    check(len(heights)>=4,(marker,"no continuous floor support",heights))
                    foot = sorted(heights)[len(heights)//2]
                    if previous is not None:
                        largest_step = max(largest_step,abs(foot-previous))
                        check(abs(foot-previous)<=.18,(marker,"step too tall",foot,previous))
                    previous = foot
                    for level in (radius+.13,height*.62,height-radius):
                        for direction in circle:
                            origin = point+Vector((0,0,foot+level))
                            hit,_,face,_ = tree.ray_cast(origin,direction,radius+.025)
                            check(hit is None,(marker,"horizontal clearance",labels[face] if face is not None else None))
                    count += 1
            distances[name] = {"samples":count,"max_height_change_m":round(largest_step,3)}
        samples[str(frame)] = distances
    return {"capsule_radius_m":radius,"capsule_height_m":height,"samples_by_frame":samples}


def face_swatches(obj):
    swatches = {(c["column"],c["row"]):c["name"]
                for c in json.loads(PALETTE.with_suffix(".json").read_text())["cells"]}
    uv = obj.data.uv_layers["PaletteUV"]
    result = set()
    for face in obj.data.polygons:
        u,v = uv.data[face.loop_start].uv
        result.add(swatches[int(u*8),7-int(v*8)])
    return sorted(result)


def audit_house(main, instance_map):
    def meshes(key, prefix):
        collection = bpy.data.collections["MASTER | " + key]
        return [obj for obj in collection.objects if obj.name.startswith(prefix)]

    caps = meshes("house_eaves", "Square-front concrete cap segment")
    check(len(caps)==5,"Concrete cap segment count")
    for obj in caps:
        bevel = next(mod for mod in obj.modifiers if mod.type=="BEVEL")
        thickness = max(v.co.z for v in obj.data.vertices)-min(v.co.z for v in obj.data.vertices)
        check(bevel.width <= thickness*.11,(obj.name,bevel.width,thickness))
        check(any(face.normal.y<-.97 and face.area>.38 for face in obj.data.polygons),obj.name)
    check(len(meshes("house_eaves_damage","Fractured concrete eave face"))==3,"Fractured eave geometry")
    for key,prefix,count in (("entry_assembly","Individual inset glass pane",12),
                             ("house_damage","Jagged glazing retained in old sash",6),
                             ("roof_ladder","Recessed ladder tread",12),
                             ("roof_ladder_damage","Recessed ladder tread",9)):
        check(len(meshes(key,prefix))==count,(key,prefix))
    for key,prefix,count,hollow in (
        ("house_pipe","Continuous metal downpipe",1,True),
        ("house_pipe_damage","Upper sheared drain",1,True),
        ("house_pipe_damage","Bent lower drain with open end",1,True),
        ("roof_ladder","Formed ladder stile with return grip",2,False),
        ("roof_ladder_damage","Formed ladder stile with return grip",2,False),
    ):
        parts=meshes(key,prefix)
        check(len(parts)==count,(key,prefix))
        for obj in parts:
            mesh=bmesh.new()
            mesh.from_mesh(obj.data)
            check(all(edge.is_manifold and edge.is_contiguous for edge in mesh.edges),obj.name)
            check(mesh.calc_volume(signed=True)>0,obj.name)
            if hollow:
                check(all(len(face.verts)==4 for face in mesh.faces),obj.name)
                check(len(mesh.verts)-len(mesh.edges)+len(mesh.faces)==0,obj.name)
            mesh.free()
    for restored,damaged,frame in (("House Eaves","House Eaves Damage",129),
                                   ("House Pipe","House Pipe Damage",135),
                                   ("Roof Ladder","Roof Ladder Damage",140)):
        for f in range(1,301):
            main.frame_set(f)
            check(main.objects[restored].hide_render==(f<frame)
                  and main.objects[damaged].hide_render==(f>=frame),(restored,f))

    prior_path=SOURCE.parent/"v008"/"component_instances.json"
    prior=json.loads(prior_path.read_text())
    unchanged={}
    for item in instance_map["instances"]:
        key=item["key"]
        if item["area"]=="house" or key.startswith("house_") or key=="roof_ladder_damage":
            continue
        unchanged[item["name"]]=item
    prior_items={item["name"]:item for item in prior["instances"]}
    for name,item in unchanged.items():
        check(item==prior_items[name],name)
    return {"square_eave_segments":len(caps),"intact_window_panes":12,"broken_glass_fragments":6,
            "ladder_rungs":{"intact":12,"damaged":9},"hollow_pipe_meshes":3,
            "state_frames":{"eaves":129,"drainage":135,"ladder":140},
            "other_placement_records_matching_v008":len(unchanged)}


def verify():
    instance_map = json.loads((SOURCE/"component_instances.json").read_text())
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/f"ocean_rooftop_farm_{SOURCE.name}.blend"))
    main = bpy.context.scene
    check(main.name.startswith("00 ") and main.frame_current == 300 and main.render.fps == 30, main.name)
    audit_palette(whole=True)
    for coll in bpy.data.collections:
        if coll.name.startswith("MASTER | "):
            audit_collection(coll)
    items = instance_map["instances"]
    plan = json.loads((SOURCE/"component_plan.json").read_text())
    budgets = {item["key"]:item["budget_triangles"] for item in plan["components"]}
    tracked = {e["name"]:e for e in items}
    visual = {o.name for o in main.objects if o.instance_type=="COLLECTION"}
    check(visual == set(tracked),"Placement list mismatch")
    check(len(bpy.data.scenes) == 1+len(instance_map["areas"]), "Independent scenes missing")
    for frame in range(1,301):
        main.frame_set(frame)
        for entry in items:
            obj = main.objects[entry["name"]]
            check(all(math.isfinite(v) for v in (*obj.location,*obj.rotation_euler,*obj.scale)),entry["name"])
            check(min(obj.scale)>.010,entry["name"])
            if frame in (1,300):
                check(state(obj,entry["before" if frame==1 else "after"]),(obj.name,frame))
            window = instance_map["areas"].get(entry["area"])
            if window:
                start,end = window["frames"]
                if frame < start:
                    check(state(obj,entry["before"]), (obj.name,"early change",frame))
                if frame >= end:
                    check(state(obj,entry["after"]), (obj.name,"late change",frame))
                if entry["area"]=="construction" and frame < entry["keys"][0][0]+1:
                    check(obj.hide_render,(obj.name,"construction reveal before first drop"))
    for entry in items:
        for frame,expected in entry["keys"]:
            main.frame_set(frame)
            check(state(main.objects[entry["name"]],expected),(entry["name"],frame))
        if entry["area"]=="construction":
            first,visible,impact,rebound,finished = [p for _,p in entry["keys"]]
            check(not first[3] and visible[3] and finished[3],entry["name"])
            check(visible[0][2]-impact[0][2]>=2 and rebound[0][2]>impact[0][2],entry["name"])
            check(near(impact[0],finished[0]) and near(impact[1],finished[1]),entry["name"])
    for area,w in instance_map["areas"].items():
        scene = next(s for s in bpy.data.scenes if s.name.startswith(w["scene_prefix"]))
        bpy.context.window.scene = scene
        active = [o for o in scene.objects if o.animation_data and o.animation_data.action]
        expected = {e["name"] for e in items if e["area"]==area}
        check({o["placement_id"] for o in active} == expected,scene.name)
        for frame in (1,5,scene.frame_end):
            scene.frame_set(frame)
            for obj in active:
                entry = tracked[obj["placement_id"]]
                check(state(obj,entry["after" if frame==scene.frame_end else "before"]),(obj.name,frame))
    bpy.context.window.scene = main
    route_report = audit_routes(main,instance_map["walk_routes"])
    house_report = audit_house(main,instance_map)
    main.frame_set(1)
    tank = main.objects["Water tank lying on its side"]
    check(not tank.hide_render and math.degrees(tank.rotation_euler.y)>70,tank.name)
    check(not main.objects["Greenhouse Debris"].hide_render,"Collapsed frame")
    main.frame_set(191)
    check(all(main.objects[e["name"]].hide_render for e in items if e["area"]=="construction"),"Stage ordering")
    check(all(not main.objects[e["name"]].hide_render for e in items if e["key"]=="facility_footing"),"Repaired footings")
    main.frame_set(300)
    house_yaw_deg = math.degrees(main.objects["House Shell"].rotation_euler.z)
    roof = next(obj for obj in bpy.data.collections["MASTER | house_roof"].objects
                if obj.name.startswith("Flat roof structural plate"))
    roof_normal = max(roof.data.polygons,key=lambda face:face.normal.z).normal
    roof_slope_deg = math.degrees(math.acos(roof_normal.z))
    check(6.8<house_yaw_deg<7.2 and 6.8<roof_slope_deg<7.2,(house_yaw_deg,roof_slope_deg))
    tile_colors = {}
    for variant in "abc":
        master = bpy.data.collections["MASTER | deck_tile_"+variant]
        tile = next(obj for obj in master.objects if obj.name.startswith("Beveled 200 mm roof stone"))
        tile_colors[variant] = face_swatches(tile)
    check(tile_colors=={"a":["stone"],"b":["sand"],"c":["cloud"]},tile_colors)
    tank_mesh = next(obj for obj in bpy.data.collections["MASTER | tower_tank"].objects
                     if obj.name.startswith("Blue-green painted steel tank"))
    tank_swatches = face_swatches(tank_mesh)
    check(tank_swatches==["aqua","ocean","teal"] and tank_mesh.active_material.name=="SEA_Metal",tank_swatches)
    step_z = sorted({round(e["after"][0][2],2) for e in items if e["key"].startswith("deck_tile_")})
    check(len(step_z)==2 and abs(step_z[1]-step_z[0]-.36)<.001,step_z)
    check(near(main.objects["LandingPoint | reference only"].location.z * Vector((0,0,1)),(0,0,5.3)),"Water clearance")
    check(main.collection.children["05 碰撞和接口代理"].hide_render,"Proxies hidden")
    context = bpy.context.evaluated_depsgraph_get()
    tri_by_asset = {}
    for coll in bpy.data.collections:
        if not coll.name.startswith("MASTER | "):
            continue
        triangles = 0
        bpy.context.scene.collection.children.link(coll)
        bpy.context.view_layer.update()
        for source in coll.objects:
            obj = source.evaluated_get(context)
            mesh = obj.to_mesh()
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            obj.to_mesh_clear()
        bpy.context.scene.collection.children.unlink(coll)
        tri_by_asset[coll.name.removeprefix("MASTER | ")] = triangles
    check(tri_by_asset.keys()==budgets.keys(),"Plan and evaluated asset sets")
    check(all(0<n<=budgets[key] for key,n in tri_by_asset.items()),tri_by_asset)
    return {
        "checks":checks,"frames_checked":300,"component_count":len(tri_by_asset),
        "placements":len(items),"independent_scenes":len(instance_map["areas"]),
        "materials":sorted(ROLES),"tiles":tile_colors,"tank_swatches":tank_swatches,
        "house_angles_deg":{"footprint":round(house_yaw_deg,2),"roof":round(roof_slope_deg,2)},
        "route_geometry":route_report,
        "house_fittings":house_report,
        "triangles_per_master":tri_by_asset,
        "triangles_by_state":{
            key:sum(tri_by_asset[e["key"]] for e in items if e[key][3]) for key in ("before","after")
        },
        "repairs":{k:sum(e["area"]==k for e in items) for k in instance_map["areas"]},
    }


if __name__ == "__main__":
    if "packages" in sys.argv:
        print(f"Packaged and reopened {finish_packages()} individual files with {checks} checks")
    else:
        result = verify()
        print(json.dumps(result,ensure_ascii=False))
        (OUTPUT/"source_verification.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
