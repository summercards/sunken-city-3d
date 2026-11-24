import hashlib
import json
import math
import os
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Vector


ROOT = Path(os.environ.get("SEA_PROJECT_ROOT") or Path(__file__).resolve().parents[3])
VERSION = "v010"
TARGET = ROOT / "art_source/scenes/ocean_rooftop_farm" / VERSION
OUTPUT = Path(os.environ.get("SEA_WORK_ROOT", str(ROOT.parent / "sea-work"))) / "rooftop_restoration" / VERSION
sys.path.insert(0, str(ROOT / "tools/blender/rooftop_restoration"))
from geometry import Model, make_materials
from components import make_component


PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
MAIN = TARGET / f"ocean_rooftop_farm_{VERSION}.blend"
PREVIOUS = TARGET.parent / "v009" / "ocean_rooftop_farm_v009.blend"
USE_LOCKED_BACKUP = OUTPUT / "mcp_before_authoring.blend"
PLAN = json.loads((TARGET / "component_plan.json").read_text())
LABELS = {
    "west": "西侧地块", "center": "中央地块", "east": "露台东侧地块",
    "greenhouse_floor": "温室地块", "tower_floor": "水塔地块",
    "house": "小屋翻新", "greenhouse": "倒塌温室清理", "tower": "倒塌水塔清理",
    "construction": "新设施落装",
}
WINDOWS = {
    "west": (11, 30), "center": (31, 51), "east": (52, 71),
    "greenhouse_floor": (72, 91), "tower_floor": (92, 111),
    "house": (112, 145), "greenhouse": (146, 166), "tower": (167, 188),
    "construction": (194, 300),
}
GROUPS = {"structure": "01 建筑结构", "facility": "02 独立设施",
          "vegetation": "03 独立花草", "support": "04 灯光和机位",
          "collision": "05 碰撞和接口代理"}
HOUSE_YAW = 7
ROOF_SLOPE = math.tan(math.radians(7))
WALK_ROUTES = {
    "front": [(19.26,-4.46),(16.17,-4.46),(16.17,-5.65),(-14.20,-5.65)],
    "house": [(-11.825,-5.65),(-11.825,-1.75)],
    "greenhouse": [(9.11,-5.65),(9.11,-3.01)],
    "tower": [(16.17,-5.65),(16.17,-1.45)],
}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collection(name, parent=None):
    result = bpy.data.collections.new(name)
    if parent:
        parent.children.link(result)
    return result


def euler_degrees(values):
    return tuple(map(math.radians, values))


def pose(location, rotation=(0, 0, 0), scale=(1, 1, 1), visible=True):
    return (tuple(location), euler_degrees(rotation), tuple(scale), visible)


def set_pose(obj, value):
    obj.location, obj.rotation_euler, obj.scale, visible = value
    obj.hide_render = obj.hide_viewport = not visible


def animate(obj, keys):
    for frame, value in keys:
        set_pose(obj, value)
        for field in ("location", "rotation_euler", "scale", "hide_render", "hide_viewport"):
            obj.keyframe_insert(data_path=field, frame=frame)
    action = obj.animation_data.action
    curves = action.layers[0].strips[0].channelbag(obj.animation_data.action_slot).fcurves
    for curve in curves:
        for key in curve.keyframe_points:
            if curve.data_path.startswith("hide_"):
                key.interpolation = "CONSTANT"
            else:
                key.handle_left_type = key.handle_right_type = "AUTO_CLAMPED"
    action.name = obj.name + " | motion"


def camera(name, coll, location, target, scale):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, data)
    coll.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.type, data.ortho_scale = "ORTHO", scale
    return obj


def lamp(name, coll, kind, location, target, power, color, size):
    data = bpy.data.lights.new(name, kind)
    obj = bpy.data.objects.new(name, data)
    coll.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy, data.color = power, color
    if kind == "SUN":
        data.angle = size
    else:
        data.shape, data.size = "DISK", size


def settings(scene, world, cam, frame_end):
    scene.camera, scene.world = cam, world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 18
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 535
    scene.render.resolution_percentage = 100
    scene.render.fps = 30
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    scene.frame_start, scene.frame_end = 1, frame_end
    scene.unit_settings.system = "METRIC"


def author():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() not in {MAIN, PREVIOUS}:
        raise RuntimeError(f"Open a dedicated authoring session. Current file: {bpy.data.filepath}")
    if not USE_LOCKED_BACKUP.exists():
        bpy.ops.wm.save_as_mainfile(filepath=str(USE_LOCKED_BACKUP), copy=True)
    bpy.context.window.scene = scene
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.orphans_purge(do_recursive=True)

    scene.name = "00 屋顶维修 | 总时间线"
    scene["FeatureID"] = "SEA-ASSET"
    scene["render_water_reference_z"] = 5.0
    scene["reference_axes"] = "Blender XY, Z up, front -Y. Godot (x,z,-y)."
    scene["state_frames"] = "1 = damaged; 191 = repairs complete; 300 = built"
    components = {}
    form = []
    materials, swatches, texture = make_materials(PALETTE)
    for entry in PLAN["components"]:
        key = entry["key"]
        coll = collection("MASTER | " + key)
        coll.use_fake_user = True
        coll["AssetID"] = entry["asset_id"]
        model = Model(coll, materials, swatches)
        make_component(key, model)
        if key in ("house_shell","house_corner_patch"):
            for obj in coll.objects:
                for vertex in obj.data.vertices:
                    vertex.co.x *= 1 - .021 * vertex.co.z / 3.1
                    vertex.co.z *= 1 - vertex.co.y * ROOF_SLOPE / 3.1
        if key in ("house_roof","house_eaves","house_eaves_damage"):
            for obj in coll.objects:
                for vertex in obj.data.vertices:
                    vertex.co.z -= vertex.co.y * ROOF_SLOPE
        origin, bounds = model.recenter()
        components[key] = (entry, coll, origin, bounds)
        form += [{**part, "id": f"{key}/{i + 1}/{part['id']}"} for i, part in enumerate(model.form)]

    groups = {key: collection(name, scene.collection) for key, name in GROUPS.items()}
    supports = groups["support"]
    cam = camera("Reference crop | facade and terrace", supports, (-4,-47,28.5), (0,.15,12.42), 37.8)
    camera("Whole water-side building", supports, (27,-41,28), (2,0,8.0), 46)
    camera("Terrace overhead", supports, (0,-1,46), (0,0,10.3), 37)
    camera("House and repaired paving", supports, (-5,-25,21.5), (-10,1,11.9), 15.0)
    camera("House fittings oblique", supports, (-25,-24,20), (-11.55,1.45,12.42), 12.7)
    camera("House fittings front", supports, (-7.0,-29,16.7), (-11.12,.0,12.70), 10.1)
    camera("Glasshouse and tank", supports, (8,-25,20.5), (11.7,1.5,12.1), 15.5)
    lamp("Warm sun", supports, "SUN", (-14,-19,26), (0,0,8), 3.6, (1,.77,.59), .075)
    lamp("Blue skylight fill", supports, "AREA", (15,-8,24), (0,1,9), 2250, (.62,.81,1), 18)
    lamp("Roof backlight", supports, "AREA", (0,15,22), (0,0,10), 3500, (1,.91,.75), 15)
    world = bpy.data.worlds.new("Clear blue coastal sky")
    world.use_nodes = True
    tree = world.node_tree
    ambient = tree.nodes.get("Background")
    ambient.inputs[0].default_value = (.26,.40,.62,1)
    ambient.inputs[1].default_value = .55
    visible = tree.nodes.new("ShaderNodeBackground")
    visible.inputs[0].default_value = (.081,.30,.86,1)
    visible.inputs[1].default_value = 1.0
    rays = tree.nodes.new("ShaderNodeLightPath")
    mix = tree.nodes.new("ShaderNodeMixShader")
    tree.links.new(rays.outputs["Is Camera Ray"], mix.inputs[0])
    tree.links.new(ambient.outputs[0], mix.inputs[1])
    tree.links.new(visible.outputs[0], mix.inputs[2])
    tree.links.new(mix.outputs[0], tree.nodes.get("World Output").inputs[0])
    settings(scene, world, cam, 300)

    records = []

    def add(key, xyz, *, rotation=(0,0,0), scale=(1,1,1), area=None, damaged=None,
            vanish=False, drop=None, swap=None, masonry=None, name=None, planted=False):
        entry, coll, origin, _ = components[key]
        category = entry["category"]
        unscaled_offset = Euler(euler_degrees(rotation)).to_matrix() @ Vector(tuple(origin[i]*scale[i] for i in range(3)))
        location = Vector(xyz) + unscaled_offset
        final = pose(location, rotation, scale)
        keys = []
        if drop is not None:
            start = pose(location + Vector((0,0,drop[1])), rotation, tuple(v*.88 for v in scale), False)
            rebound = pose(location + Vector((0,0,.16)), rotation, tuple(v*1.025 for v in scale))
            keys = [(drop[0]-1,start), (drop[0],(*start[:3],True)), (drop[0]+12,final),
                    (drop[0]+17,rebound), (drop[0]+25,final)]
            area = "construction"
        elif masonry is not None:
            frame, outward, original = masonry
            start = (*final[:3],original)
            lifted = pose(location+Vector(outward)*.64+Vector((0,0,.40)),rotation,tuple(v*.93 for v in scale))
            if original:
                start = pose(location+Vector(outward)*.04,tuple(a+b for a,b in zip(rotation,(0,6,0))),scale)
            keys = [(frame-1,start),(frame,lifted),(frame+6,final),
                    (frame+9,pose(location+Vector(outward)*.055,rotation,scale)),(frame+12,final)]
        elif swap is not None:
            frame, restored = swap
            start = (*final[:3], not restored)
            final = (*final[:3], restored)
            keys = [(frame-1,start),(frame,final)]
        elif damaged:
            start = pose(location + Vector(damaged[0]), damaged[1], scale)
            a,b = WINDOWS[area]
            keys = [(a,start)]
            if vanish:
                travel = {"greenhouse":(.24,.44,.70),"tower":(.24,.37,.66),"house":(0,.15,.08)}
                retreat = pose(Vector(start[0])+Vector(travel.get(area,(0,0,.32))),
                               tuple(a+b for a,b in zip(damaged[1],(0,-8,12))) if area=="tower" else damaged[1],
                               tuple(s*.023 for s in scale), False)
                keys += [(b-2,(*retreat[:3],True)),(b-1,retreat)]
                final = retreat
            else:
                keys += [(b-7,pose(location+Vector((0,0,.10)),rotation, scale)),(b,final)]
        else:
            start = final
        obj = bpy.data.objects.new(name or key.replace("_"," ").title(), None)
        groups[category].objects.link(obj)
        obj.instance_type, obj.instance_collection = "COLLECTION", coll
        obj.empty_display_size = .17
        obj["asset_key"] = key
        obj["area"] = area or "static"
        obj["placement_id"] = obj.name
        if planted:
            obj["placement_role"] = "independent plant inside planter or growing bench"
        set_pose(obj, final)
        if keys:
            animate(obj, keys)
        records.append((obj, key, start, final, area, keys))
        return obj

    z = 10.20
    # The front crop retains the two-tier masonry façade and broken lower windows.
    for floor in (0, 5.1):
        add("base_slab",(0,0,floor))
        for y,rz in ((-6.54,0),(6.54,180)):
            for i in range(8):
                add("facade_bay",((i-3.5)*4.28,y,floor+.20),rotation=(0,0,rz))
        for x,rz in ((-16.83,-90),(16.83,90)):
            for y in (-4.28,0,4.28):
                add("facade_bay",(x,y,floor+.20),rotation=(0,0,rz))
        for y in (-6.68,6.68):
            for x in (-16.9,-8.56,0,8.56,16.9):
                add("corner_pier",(x,y,floor+.20))
    for y in (-6.60,6.60):
        for i in range(8):
            x=(i-3.5)*4.28
            add("edge_beam",(x,y,z-.59))
            area = {1:"west",3:"center",4:"east",6:"greenhouse_floor",7:"tower_floor"}.get(i)
            if y > 0 and area:
                add("rail_section",(x,y,z),area=area,damaged=((-.08,.08,-.27),(7,-11,3)))
            else:
                add("rail_section",(x,y,z))
        for x in (-16.95,-8.56,0,8.56,16.95):
            add("rail_pier",(x,y,z-.02))
    for x,rz in ((-16.90,-90),(16.90,90)):
        for i,y in enumerate((-4.28,0,4.28)):
            entry_bay = x>0 and i==0
            add("edge_beam",(x,y,z-(.85 if entry_bay else .59)),rotation=(0,0,rz))
            if x < 0:
                add("rail_section",(x,y,z),rotation=(0,0,rz))
            elif i != 0:
                add("rail_section",(x,y,z),rotation=(0,0,rz))
        for y in (-2.13,2.13):
            add("rail_pier",(x,y,z-.02))
    # A separate lip connects the repair candidate to its sea-level entry.
    add("pier_dock",(18.36,-5.88,4.47))
    add("access_stairs",(18.55,-2.06,5.29))
    add("upper_stair_bridge",(18.35,-4.46,z-.187),name="Continuous connector from upper landing")
    areas = {}
    stable_cells = {(i,0) for i in range(16)} | {(1,1),(2,1),(2,2),(12,1),(15,1),(15,2)}
    for i in range(16):
        x=(i-7.5)*2.15
        raised = .36 if i < 5 else 0
        for j in range(6):
            y=(j-2.5)*2.29
            if (i,j) in stable_cells:
                area=offset=tilt=None
            elif i < 5 and j in (1,2):
                area="west"
                tilt=(7+j*5,-12+i*3,(-1)**i*6)
                offset=((i-2)*.15,.25,-.38-.24*(j%3)-.11*(i%2))
            elif 5<=i<=8 and 1<=j<=4:
                area="center"
                tilt=(10*((j%3)-1),15*(-1 if i==5 else 1),7-3*j)
                offset=(.23*(i-6),.18*(j-1),-.52-.27*((i+j)%3))
            elif i in (9,10) and 0<=j<=3:
                area="east"
                tilt=(-9+6*j, (-1)**i*16,4)
                offset=(.13,.16,-.44-.28*((i+j)%2))
            elif 11<=i<=13 and 2<=j<=5:
                area="greenhouse_floor"
                tilt=(-7+j,11*(-1)**i,4*((j%3)-1))
                offset=(-.12,.1,-.45-.19*(j%2))
            elif 14<=i and 1<=j<=5:
                area="tower_floor"
                tilt=(4*j-12,13*(-1)**i,-5)
                offset=(.15,.13,-.56-.15*(j%3))
            else:
                area=offset=tilt=None
            variant=("a","a","b","a","c","b","a","c","a","b","a")[(i*7+j*3+i*j)%11]
            add("deck_tile_"+variant,(x,y,z+raised-.2),area=area,damaged=(offset,tilt) if area else None,
                name=f"Paving {i+1:02d}.{j+1:02d}")
            if area:
                areas.setdefault(area,[]).append((x,y))
        for j in range(3):
            beam_area = ("west" if i<5 and j==1 else "center" if 5<=i<=8 and j>0
                         else "east" if i in (9,10) and j==1 else "greenhouse_floor" if 11<=i<=13 and j>0
                         else "tower_floor" if i==14 else None)
            add("deck_underframe",(x,(j-1)*4.57,z+raised-.425),area=beam_area,
                damaged=((0,0,-1.15),(0,0,0)) if beam_area else None)
    for area, coords in areas.items():
        for i,(x,y) in enumerate(coords[::2]):
            add("rubble",(x+.38,y+.05,z+.07),area=area,damaged=((0,0,0),(13,4,i*52)),
                vanish=True,scale=(.85,.85,.70))
    for y in (-4.32,-.02,4.28):
        add("terrace_step",(-6.48,y,z),rotation=(0,0,90),scale=(1,.86,1))

    hz = z+.36
    house_x,house_y = -11.27,2.94
    house_rotation=(0,0,HOUSE_YAW)
    house_matrix=Euler(euler_degrees(house_rotation)).to_matrix()

    def house_anchor(x,y,height):
        return Vector((house_x,house_y,hz)) + house_matrix @ Vector((x,y,height))

    add("house_shell",house_anchor(0,0,0),rotation=house_rotation,area="house",damaged=((0,0,-.06),(0,0,HOUSE_YAW-2)))
    add("house_corner_patch",house_anchor(0,0,0),rotation=house_rotation,area="house",
        damaged=((.12,.065,-2.31),(0,0,HOUSE_YAW-2)))
    add("house_damage",house_anchor(0,0,0),rotation=house_rotation,area="house",damaged=((0,0,-.06),(0,0,HOUSE_YAW-2)),vanish=True)
    add("house_roof",house_anchor(0,0,3.1),rotation=house_rotation)
    for key, base, frame in (
        ("house_eaves",house_anchor(0,0,3.1),129),
        ("house_pipe",house_anchor(0,0,0),135),
        ("roof_ladder",house_anchor(-3.70,-3.19,0),140),
    ):
        add(key,base,rotation=house_rotation,area="house",swap=(frame,True))
        add(key+"_damage",base,rotation=house_rotation,area="house",swap=(frame,False))
    add("doghouse",(-14.02,-3.14,hz),rotation=(0,0,-7),area="house",damaged=((.10,.04,-.012),(0,0,-12)))
    add("entry_assembly",house_anchor(0,-2.429,0),rotation=house_rotation,drop=(216,4.2))
    for index,(y,h,tone,sz,tilt) in enumerate((
        (-1.89,2.50,"sand",.76,-7),(-1.51,1.68,"warm",.93,6),(-1.90,.78,"cool",.75,-5),
        (-.88,.54,"sand",.61,7),(-.40,2.31,"cool",.76,-6),(.29,1.09,"warm",.81,9),
        (1.24,2.65,"warm",.66,-7),(1.71,.70,"sand",.75,-5),(.95,1.69,"sand",.54,8),
    )):
        outer = house_matrix @ Vector((-1,0,0))
        wall = -4.27*(1-.021*h/3.1)
        add("wall_stone_"+tone,house_anchor(wall,y,h-sz*.31),
            rotation=(0,tilt,HOUSE_YAW-90),scale=(sz,1,sz*.72),area="house",
            masonry=(115+index*2,outer,index in (0,3,7)),name=f"Masonry {index+1:02d}")
    for index,(x,h,tone,sz,tilt) in enumerate((
        (-3.56,2.67,"sand",.63,-6),(-3.72,.93,"cool",.74,4),
        (.90,1.94,"warm",.59,-7),(1.01,.74,"sand",.57,8),
    )):
        add("wall_stone_"+tone,house_anchor(x,-2.59,h-sz*.28),
            rotation=(0,tilt,HOUSE_YAW),scale=(sz,1,sz*.78),area="house",
            masonry=(121+index*3,house_matrix @ Vector((0,-1,0)),False),name=f"Masonry {index+10:02d}")
    for x,y,sz in ((-16.07,2.26,.72),(-9.02,.16,.56),(-13.17,-.35,.60)):
        add("rubble",(x,y,hz+.10),scale=(sz,sz,sz),area="house",
            damaged=((0,0,0),(0,0,x*25)),vanish=True)

    gx,gy = 10.28,1.87
    tx,ty = 14.76,4.16
    for i,(dx,dy) in enumerate(((-2.67,-2.80),(2.67,-2.80),(-2.67,2.80),(2.67,2.80))):
        add("facility_footing",(gx+dx,gy+dy,z-.15),area="greenhouse",
            damaged=((-.16,.10,-.27),(11,-19+i*8,15)),name=f"Greenhouse footing {i+1}")
    for i,(dx,dy) in enumerate(((-1.27,-1.26),(1.27,-1.26),(-1.27,1.26),(1.27,1.26))):
        add("facility_footing",(tx+dx,ty+dy,z-.14),area="tower",
            damaged=((.14,.13,-.22),(9,-12+i*7,-14)),name=f"Tank footing {i+1}")
    add("greenhouse_debris",(gx,gy,z-.37),rotation=(0,0,12),area="greenhouse",
        damaged=((.20,.23,0),(2,6,20)),vanish=True)
    add("tower_debris",(tx,ty,z-.28),area="tower",damaged=((.16,.28,0),(3,-9,6)),vanish=True)
    add("tower_tank",(tx,ty,z-.17),area="tower",damaged=((-.48,-.36,1.30),(11,77,22)),vanish=True,
        name="Water tank lying on its side")
    add("greenhouse_base",(gx,gy,z),drop=(195,4.6))
    add("greenhouse_glazing",(gx,gy,z),drop=(214,6.2))
    add("tower_support",(tx,ty,z),drop=(197,5.5))
    add("tower_tank",(tx,ty,z+3.02),drop=(224,6.6),name="Replacement upright water tank")
    add("windmill",(12.93,5.72,z),scale=(1.12,1.12,1.13),drop=(229,6.3))
    add("patio_table",(1.80,-1.03,z),drop=(237,3.8))
    add("clothesline",(-2.95,5.03,z),drop=(232,4.05))
    add("trellis",(4.86,5.14,z),drop=(238,4.12))
    add("barrels",(13.85,-2.65,z),rotation=(0,0,8),drop=(251,3.7))
    for x,y,hh,angle,frame in ((-7.26,-1.21,hz,0,240),(6.54,1.07,z,-72,242)):
        add("bench",(x,y,hh),rotation=(0,0,angle),drop=(frame,3.7))
    roof_plant=house_anchor(-.55,-1.53,3.30+1.53*ROOF_SLOPE)
    for i,(x,y,hh,rz,s) in enumerate(((-15.42,-1.67,hz,0,1),(-8.30,-.40,hz,10,.8),(-5.63,3.25,z,4,.9),
                        (-.07,-4.23,z,0,1.15),(5.64,3.50,z,4,.84),(10.59,-3.97,z,-6,.80),
                        (14.40,-4.10,z,8,1.08),(*roof_plant,5,.8),
                        (-15.90,-4.13,hz,0,.86),(3.34,5.36,z,0,.74))):
        add("planter",(x,y,hh),rotation=(0,0,rz),scale=(s,s,s),drop=(244+i,3.1))
        for j in (-1,1):
            add("flowers" if (i+j)%3==0 else "greens",(x+j*.31*s,y,hh+.486*s),rotation=(0,0,i*29+j*25),
                scale=(s*.93,s*.97,s*1.04),drop=(261+i,2.1),planted=True)
    for i,x in enumerate((-1.79,1.79)):
        for j,y in enumerate((-2.24,-1.62,-.45,.19,1.39,2.02)):
            add("flowers" if (i+j)%3==0 else "greens",(gx+x,gy+y,z+.87),rotation=(0,0,(i*180+j*67)%360),
                scale=(.80,.76,1.03),drop=(253+j*2,2.0),planted=True)

    # Collision proxies are explicit placeholders for later wrapping and visibility is per collection.
    collisions = groups["collision"]
    collisions.hide_render = collisions.hide_viewport = True
    def proxy(name, location, scale=None):
        obj = bpy.data.objects.new(name, None)
        collisions.objects.link(obj)
        obj.location = location
        obj.empty_display_type = "CUBE" if scale else "ARROWS"
        obj.empty_display_size = .5
        if scale:
            obj.scale = scale
        return obj

    proxy("Pier DockingArea | reference only",(18.36,-8.15,5.0),(4.2,2.5,.75))
    proxy("BoatPark | reference only",(18.36,-8.10,5.0))
    proxy("LandingPoint | reference only",(18.36,-6.28,5.30))
    proxy("Stair bottom connection",(17.83,-4.80,5.30))
    proxy("Stair top connection",(19.27,-4.80,10.20))
    proxy("Permanent front walk east",(5.375,-5.68,z-.1),(23.64,1.5,.2))
    proxy("Permanent front walk west",(-11.83,-5.68,hz-.1),(10.72,1.5,.2))
    proxy("Upper stair bridge walk surface",(18.35,-4.46,z-.087),(2.86,1.5,.2))
    for route, points in WALK_ROUTES.items():
        for n,(x,y) in enumerate(points):
            proxy(f"Route {route} checkpoint {n+1}",(x,y,hz if x<-6.45 else z))
    proxy("Main floor span above water",(0,0,5.2),(34.4,13.8,.2))

    linked_static = collection("COMMON | static modules")
    for obj,_,_,_,area,_ in records:
        if area is None:
            linked_static.objects.link(obj)
    for area,(start,end) in WINDOWS.items():
        short = bpy.data.scenes.new(f"{list(WINDOWS).index(area)+1:02d} {LABELS[area]}")
        short.collection.children.link(supports)
        short.collection.children.link(linked_static)
        short["independent_area"] = area
        settings(short,world,cam,end-start+12)
        local = collection("Editable | " + LABELS[area], short.collection)
        for obj,key,first,final,record_area,keys in records:
            if record_area is None:
                continue
            active = record_area == area
            previous = WINDOWS[record_area][1] < start
            chosen = final if previous else first
            if not active and not chosen[3]:
                continue
            copy = obj.copy()
            copy.animation_data_clear()
            local.objects.link(copy)
            if active:
                shifted = [(1,first)] + [(frame-start+5,value) for frame,value in keys]
                animate(copy, shifted)
                copy.name = key + " | " + LABELS[area]
            else:
                set_pose(copy,chosen)
        short.timeline_markers.new(LABELS[area], frame=5)
        short.frame_set(1)
        scene.timeline_markers.new(LABELS[area],frame=start)
    scene.timeline_markers.new("图一 | 破损状态",frame=1)
    scene.timeline_markers.new("全部区域修复完成",frame=191)
    scene.timeline_markers.new("图二 | 设施完工",frame=300)
    scene.frame_set(300)
    scene.render.filepath = "//"

    # Blend-library writes keep one external shared PaletteUV image across all independent packages.
    texture.filepath = str(PALETTE)
    for key,(entry,coll,origin,bounds) in components.items():
        destination = TARGET / "component_packages" / key
        destination.mkdir(parents=True,exist_ok=True)
        package = bpy.data.scenes.new("Asset | " + key)
        package.collection.children.link(coll)
        package.unit_settings.system = "METRIC"
        package["AssetID"] = entry["asset_id"]
        package["front_axis"] = "-Y"
        package["origin"] = "bottom_center"
        package_path = destination / (key+".blend")
        bpy.data.libraries.write(str(package_path),{package},path_remap="RELATIVE_ALL",fake_user=True,compress=True)
        bpy.data.scenes.remove(package)
        write_json(destination/"asset_manifest.json",{
            **entry,"source":str(package_path.relative_to(ROOT)),"source_sha256":file_hash(package_path),
            "collection":coll.name,"bounds_m":list(bounds),"collection_offset":[0,0,0],
            "authoring_origin_before_recenter":list(origin),"materials":sorted({o.active_material.name for o in coll.objects}),
            "building_class":None if entry["category"]=="vegetation" else "above_water",
            "palette":str(PALETTE.relative_to(ROOT)),
        })

    manifest = {
        "schema":"sea.scene.component_instances","version":VERSION,"axis_mapping":"(x,y,z) -> (x,z,-y)",
        "fps":30,"states":{"before":1,"repaired":191,"after":300},
        "walk_routes":WALK_ROUTES,
        "areas":{area:{"scene_prefix":f"{i+1:02d} ","name":LABELS[area],"frames":list(WINDOWS[area])}
                 for i,area in enumerate(WINDOWS)},
        "instances":[{"name":obj.name,"key":key,"asset_id":components[key][0]["asset_id"],
                      "area":area,"before":first,"after":final,
                      "keys":[[frame,value] for frame,value in keys]}
                     for obj,key,first,final,area,keys in records],
    }
    write_json(TARGET/"component_instances.json",manifest)
    write_json(TARGET/"stylized_form_audit.json",{"stylized_form":{
        "form_style":"SF-B","body":{"width_base":8.54,"width_top":8.54*.979,"height":3.1},
        "components":form,"relief":{"quoin_blocks":15,"layers":1},
        "contacts":[
            {"a":"deck tile at its wide edge","b":"adjacent tile across X","relation":"clearance","gap_m":.007},
            {"a":"deck tile at its long end","b":"adjacent tile across Y","relation":"clearance","gap_m":.017},
        ],
        "source_of_dimensions":"Authored vertex cross-sections from Model.box and Model.round.",
    }})
    bpy.context.window.scene=scene
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                area.spaces.active.region_3d.view_perspective="CAMERA"
                area.spaces.active.overlay.show_overlays=False
                area.spaces.active.shading.type="MATERIAL"
    texture.filepath = bpy.path.relpath(str(PALETTE), start=str(TARGET))
    previous_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(MAIN), compress=True)
    finally:
        bpy.context.preferences.filepaths.save_version = previous_versions
    write_json(TARGET/"asset_manifest.json",{
        "asset_id":"SEA-SCENE-ORF7-ASSEMBLY","version":VERSION,"building_class":"above_water",
        "source":str(MAIN.relative_to(ROOT)),"source_sha256":file_hash(MAIN),
        "plan":"component_plan.json","placement":"component_instances.json","fps":30,"clips":manifest["areas"],
        "review_frames":manifest["states"],"components":list(components),"instances":len(records),
        "runtime_status":"pending","reference_license":"pending",
    })
    print(f"MCP saved {MAIN} | {len(components)} masters, {len(records)} placed instances, {len(bpy.data.scenes)} scenes")


author()
