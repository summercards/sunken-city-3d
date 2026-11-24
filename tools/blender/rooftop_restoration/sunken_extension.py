"""Author the lower masonry kit and shortened stair against the v013 ranch."""
import hashlib
import json
import math
import os
from pathlib import Path
import random
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).parent))
from geometry import Model

ROOT = Path(__file__).resolve().parents[3]
OLD = ROOT / "art_source/scenes/ocean_rooftop_farm/v013"
SOURCE = OLD.with_name("v014")
WORK = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration/v014"
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
DROP = 1.8
WATER_Z = 5.0 + DROP
PITCH = 4.28
X_EDGE, Y_EDGE = 17.12, 6.42
LABELS = {
    "deep_plate": ("水下楼板", "slab"), "deep_post": ("水下混凝土柱", "column"),
    "deep_post_broken": ("断柱与钢筋", "column"), "deep_beam": ("水下横梁", "beam"),
    "deep_beam_broken": ("露筋断梁", "beam"), "deep_bay": ("破窗砌体", "facade"),
    "deep_bay_spalled": ("斜断窗墙", "facade"), "deep_bay_open": ("抽空窗跨", "facade"),
    "deep_debris": ("塌落楼板碎块", "debris"),
}
PATTERNS = (
    ("右前角脱落", {"F": {6:"spalled",7:"open",8:"open"}, "E": {1:"open",2:"spalled"}},
     {(6,0),(7,0),(7,1)}, {(7,-1),(8,-1)}, {("F",7),("F",8),("E",1)}),
    ("正面中段斜断", {"F": {3:"spalled",4:"open",5:"spalled"}, "B": {2:"open"}},
     {(3,0),(4,0)}, {(4,-1)}, {("F",4),("B",2)}),
    ("西侧纵向塌落", {"W": {1:"spalled",2:"open",3:"open"}, "F": {1:"spalled"}, "B": {8:"spalled"}},
     {(0,1),(0,2),(1,2)}, {(0,1),(0,2)}, {("W",2),("W",3),("B",8)}),
    ("背面大跨缺失", {"B": {3:"open",4:"open",5:"spalled",6:"open"}, "E": {3:"spalled"}},
     {(2,2),(3,2),(4,2),(5,2)}, {(3,3),(4,3)}, {("B",3),("B",4),("B",6)}),
    ("正面多处窗楣断裂", {"F": {1:"spalled",3:"open",6:"spalled",8:"spalled"}, "W": {2:"spalled"}},
     {(1,1),(5,0)}, {(2,-1),(6,-1)}, {("F",3),("F",6)}),
    ("右侧楼板旋落", {"E": {1:"spalled",2:"open",3:"spalled"}, "B": {1:"open",2:"spalled"}},
     {(7,0),(7,1),(7,2),(6,2)}, {(8,1),(8,2)}, {("E",2),("B",1)}),
    ("左前角大缺口", {"F": {1:"open",2:"open",3:"spalled"}, "W": {1:"open",2:"spalled"}},
     {(0,0),(1,0),(0,1)}, {(0,-1),(1,-1),(0,1)}, {("F",1),("F",2),("W",1)}),
)


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fracture(model, name, polygon, width, color, bevel=.028):
    # Extrude the irregular section so fractures expose volume at oblique angles.
    model.panel(name, [(x,-width*.5,z) for x,z in polygon], width, color, bevel=bevel)


def lower_bay(model, state):
    if state == "open":
        fracture(model,"Remaining lower corner", [(-1.85,0),(-.23,0),(-.53,.34),(-1.12,.52),(-1.39,1.03),(-1.85,1.41)],.39,"gray")
        model.bar("Twisted remnant sash",(-1.26,-.03,1.13),(-1.60,.10,2.73),.083,"steel",role="Metal")
        return
    if state == "spalled":
        fracture(model,"Slanted brick break", [(-1.86,0),(1.86,0),(1.86,1.04),(.81,1.18),(.26,.64),(-.41,.81),(-.97,1.72),(-1.86,2.1)], .43,"stone")
        fracture(model,"Deep exposed mortar section",[(-1.57,1.29),(-.88,1.05),(-.51,.65),(-1.57,.58)],.17,"gray")
        model.bar("Bent sash rail",(-1.48,-.16,1.3),(-.52,-.05,2.78),.12,"steel",role="Metal")
        model.box("Retained sill",(.96,-.08,1.12),(1.45,.54,.18),"silver",bevel=.032)
        return
    for row in range(2):
        cuts = ((-1.855,-.85,.28,.99,1.855),(-1.855,-1.31,-.38,.70,1.855))[row]
        for i,(a,b) in enumerate(zip(cuts,cuts[1:])):
            depth = (.40,.48,.42,.33)[(row+i)%4]
            model.box("Dressed stone course",((a+b)/2,-.035,row*.51+.245),(b-a-.014,depth,.49),
                      ("stone","gray","silver","sage_gray")[(row+i)%4],bevel=.041)
    for x in (-1.71,1.71):
        model.box("Deep return",(x,.03,2.42),(.28,.42,3.04),"gray",bevel=.045)
    model.box("Deep stone lintel",(0,.02,3.86),(3.72,.48,.48),"stone",bevel=.05)
    model.box("Broken window sill",(0,-.10,1.10),(3.47,.48,.18),"silver",bevel=.038)
    for i,x in enumerate((-.78,.78)):
        model.box("Recessed sash head",(x,.047,3.41),(1.39,.12,.12),"steel",role="Metal",bevel=.012)
        fracture(model,"Jagged glass retained in frame",
                 [(x-.65,1.22),(x+.64,1.22),(x+.64,1.7+i*.14),(x+.25,1.48),(x-.08,2.02),(x-.44,1.61),(x-.65,1.93)],
                 .024,"ocean",.008)
    model.box("Center sash", (0,.025,2.33),(.11,.12,2.24),"steel",role="Metal",bevel=.015)


def lower_post_broken(m):
    fracture(m,"Broken lower column",[(-.25,0),(.25,0),(.234,1.39),(.09,1.79),(-.058,1.62),(-.238,1.96)],
             .50,"stone",.045)
    for x,y,dx in ((-.13,-.08,-.23),(.13,-.08,.13),(-.09,.09,.04)):
        m.round("Exposed column steel",(x,y,1.45),(x+dx,y-.05,2.34),.025,.023,"bark",role="Metal",bevel=.005)


def lower_beam_broken(m):
    fracture(m,"Fractured beam end",[(-2.13,0),(-.87,0),(-.69,.19),(-.46,.26),(-.79,.54),(-2.13,.56)],
             .64,"stone",.039)
    fracture(m,"Opposite broken beam",[(.89,0),(2.13,0),(2.13,.56),(1.04,.54),(.78,.32)],
             .64,"gray",.04)
    for y in (-.15,.08):
        m.round("Drooping reinforcement",(-.98,y,.29),(.29,y-.04,.02),.028,.025,"bark",role="Metal",bevel=.007)


def lower_debris(m):
    fracture(m,"Detached reinforced slab",[(-1.36,.07),(.40,0),(1.25,.17),(1.06,.40),(-.27,.46),(-1.18,.31)],
             1.22,"stone",.039)
    for i,(x,y,h) in enumerate(((-.93,.65,.19),(.19,-.76,.22),(.76,.61,.27))):
        m.box("Loose masonry",(x,y,h/2),(.51+i*.12,.37,h),("gray","stone","sage_gray")[i],
              bevel=.039,rotation=Euler((.08*i,.12,.3+i*.5)).to_matrix())


def access(m):
    bottom, turn, top = .281, 1.73, 3.19129
    deck = m.box
    for side, start,end,y0,y1 in ((-1,bottom,turn,-1.98,1.64),(1,turn,top,1.64,-1.98)):
        x = side*.72
        for i in range(13):
            t = i/12
            y = y0+(y1-y0)*t
            z = start+(end-start)*t
            deck("Short flight tread",(x,y,z-.1),(1.36,.296,.20),
                 ("wood_mid","wood_mid","wood","wood_light")[i%4],bevel=.042)
        for sx in (x-.48,x+.48):
            m.bar("Short flight stringer",(sx,y0-.035,start-.22),(sx,y1+.035,end-.22),.19,"darkwood",bevel=.038)
        for t in (0,.33,.66,1):
            y,z = y0+(y1-y0)*t,start+(end-start)*t
            m.round("Short flight handrail post",(side*1.39,y,z),(side*1.39,y,z+.83),.052,.048,"wood_dark")
        m.bar("Short flight handrail",(side*1.39,y0,start+.83),(side*1.39,y1,end+.83),.10,"wood_light")
    deck("Turning platform",(0,2.1325,turn-.1),(2.85,.91,.20),"wood",bevel=.068)
    deck("Roof connection platform",(.72,-2.35,top-.1),(1.36,.59,.20),"wood_light",bevel=.068)
    deck("Berth connection platform",(-.72,-2.408,bottom-.1),(1.36,.67,.20),"wood_light",bevel=.068)
    for x in (-1.34,0,1.34):
        m.round("Turning platform rear post",(x,2.54,turn-.02),(x,2.54,turn+.83),.055,.05,"wood_dark")
    m.bar("Turning platform rear rail",(-1.39,2.54,turn+.83),(1.39,2.54,turn+.83),.104,"wood_light")
    m.bar("Turning platform knee rail",(-1.39,2.54,turn+.32),(1.39,2.54,turn+.32),.082,"wood_mid")


def source_model(key, row, materials, swatches):
    name = "MASTER | " + key
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    for obj in list(coll.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    m = Model(coll, materials, swatches)
    if key == "deep_plate":
        m.box("Reinforced deck panel",(0,0,.10),(4.268,4.268,.20),"gray",bevel=.044)
    elif key == "deep_post":
        m.box("Tapered primary concrete column",(0,0,2.44),(.5,.5,4.88),"stone",bevel=.095)
    elif key == "deep_beam":
        m.box("Concrete spandrel beam",(0,0,.28),(4.26,.64,.56),"stone",bevel=.045)
    elif key == "deep_post_broken":
        lower_post_broken(m)
    elif key == "deep_beam_broken":
        lower_beam_broken(m)
    elif key == "deep_debris":
        lower_debris(m)
    elif key == "access_stairs":
        access(m)
    else:
        lower_bay(m, key.removeprefix("deep_bay_"))
    vertices = [v.co for obj in coll.objects for v in obj.data.vertices]
    low,high = (Vector(tuple(f(v[i] for v in vertices) for i in range(3))) for f in (min,max))
    # The stair keeps the preceding stair/bridge interface coordinates.
    origin = Vector() if key=="access_stairs" else Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
    for obj in coll.objects:
        for v in obj.data.vertices:
            v.co -= origin
        obj.data.update()
    sc = bpy.data.scenes.new("Asset | "+key)
    sc.collection.children.link(coll)
    sc.unit_settings.system = "METRIC"
    sc["AssetID"] = row["asset_id"]
    folder = SOURCE/"component_packages"/key
    folder.mkdir(parents=True,exist_ok=True)
    package = folder/(key+".blend")
    bpy.data.libraries.write(str(package),{sc},path_remap="RELATIVE_ALL",fake_user=True,compress=True)
    bpy.data.scenes.remove(sc)
    write(folder/"asset_manifest.json",{**row,"version":"v014","source":package.relative_to(ROOT).as_posix(),
          "source_sha256":sha(package),"collection":coll.name,"bounds_m":list(high-low),"form":m.form,
          "authoring_origin_before_recenter":list(origin),"materials":sorted({o.active_material.name for o in coll.objects})})
    return coll, origin


def main():
    assert Path(bpy.data.filepath).resolve().parent == OLD
    WORK.mkdir(parents=True,exist_ok=True)
    plan = read(OLD/"component_plan.json")
    plan.update(version="v014",parent_version="v013",design_clause="SEA-ASSET-R94")
    stair = next(row for row in plan["components"] if row["key"]=="access_stairs")
    stair.update(source_revision="v014",origin="existing_stair_interface",building_class="above_water")
    kit = [{"key":key,"name":label,"component_family":family,"asset_id":"SEA-SCENE-ORF7-"+key.upper().replace("_","-"),
            "category":"structure","scope":"submerged_extension","building_class":"underwater",
            "collision_owner":"visual_only","budget_triangles":12000,"origin":"bottom_center","front_axis":"-Y",
            "form_style":"SF-B"} for key,(label,family) in LABELS.items()]
    plan["submerged_kit"] = kit
    plan["scoped_revision"] = {"keys":["access_stairs",*LABELS],"drop_m":DROP,"water_source_z":WATER_Z,
                               "levels_added":7,"story_height_m":5.1,
                               "reference_sha256":"b79c4673a097ec8bbff33439c4060d6ae73a0127260548cebf2252d655968f59"}
    write(SOURCE/"component_plan.json",plan)
    materials={role:bpy.data.materials["SEA_"+role] for role in ("Matte","Metal","Gloss","Emission")}
    swatches={c["name"]:(c["column"],c["row"]) for c in read(PALETTE.with_suffix(".json"))["cells"]}
    for image in bpy.data.images:
        if image.source=="FILE":
            image.filepath=bpy.path.abspath(image.filepath)
    scene=bpy.context.scene
    models={row["key"]:source_model(row["key"],row,materials,swatches) for row in [stair,*kit]}
    layout=read(OLD/"component_instances.json")
    for row in layout["instances"]:
        if row["key"] in {"pier_dock","access_stairs"}:
            scene.objects[row["name"]].location.z += DROP
            for pose in (row["before"],row["after"]):
                pose[0][2] += DROP
    lower = bpy.data.collections.new("07 | Submerged seven storeys")
    scene.collection.children.link(lower)
    shared=bpy.data.collections["COMMON | static modules"]
    # The lower structure is visible in the total timeline and in its own source view.
    detail=bpy.data.scenes.new("10 Submerged extension")
    detail.collection.children.link(lower)
    detail.world=scene.world
    detail.unit_settings.system="METRIC"
    ids={row["key"]:row["asset_id"] for row in kit}
    rng=random.Random(38114)
    levels=[]
    for i,(name,bays,holes,broken_posts,broken_beams) in enumerate(PATTERNS,1):
        floor=-i*5.10
        group=bpy.data.collections.new(f"Submerged {i:02d} | {name}")
        lower.children.link(group)
        level={"floor":i,"label":name,"datum":floor,"placements":[]}
        levels.append(level)

        def add(key,label,xyz,angles=(0,0,0),scale=(1,1,1)):
            coll,origin=models[key]
            rotation=Euler(tuple(math.radians(v) for v in angles))
            point=Vector(xyz)+rotation.to_matrix()@Vector(tuple(a*b for a,b in zip(origin,scale)))
            obj=bpy.data.objects.new(f"Lower {i:02d} {label}",None)
            group.objects.link(obj)
            obj.instance_type="COLLECTION"
            obj.instance_collection=coll
            obj.location,obj.rotation_euler,obj.scale=point,rotation,scale
            obj.empty_display_size=.12
            obj["asset_id"]=ids[key]
            pose=[list(point),list(rotation),list(scale),True]
            row=dict(name=obj.name,key=key,asset_id=ids[key],area=None,before=pose,after=pose,keys=[],floor=i)
            level["placements"].append(row)
            layout["instances"].append(row)

        for x in range(8):
            for y in range(3):
                px,py=(x-3.5)*PITCH,(y-1)*PITCH
                if (x,y) in holes:
                    if (x+y+i)%3!=0:
                        add("deep_plate",f"fallen slab {x}-{y}",(px,py,floor+.28),(rng.uniform(-17,17),rng.uniform(13,27),rng.uniform(-13,13)),(.75,.80,1))
                    add("deep_debris",f"slab debris {x}-{y}",(px+.34,py-.57,floor+.12),(5,-9,rng.randrange(360)))
                else:
                    add("deep_plate",f"slab {x}-{y}",(px,py,floor))
        for u,v in [*((x,y) for y in (-1,3) for x in range(9)),*((x,y) for x in (0,8) for y in (1,2))]:
            x=(u-4)*PITCH
            y=Y_EDGE if v==3 else -Y_EDGE if v==-1 else (v-1.5)*PITCH
            broken=(u,v) in broken_posts
            add("deep_post_broken" if broken else "deep_post",f"post {u}-{v}",(x,y,floor+.21),(0,0,90 if u in (0,8) else 0))
        for side,n,yaw in (("F",8,0),("B",8,180),("W",3,-90),("E",3,90)):
            for j in range(1,n+1):
                x=(j-4.5)*PITCH*(-1 if side=="B" else 1) if n==8 else (-X_EDGE if side=="W" else X_EDGE)
                y=(-Y_EDGE if side=="F" else Y_EDGE) if n==8 else (j-2)*PITCH*(-1 if side=="W" else 1)
                variant=bays.get(side,{}).get(j,"")
                key="deep_bay" + ("_"+variant if variant else "")
                add(key,f"bay {side}{j}",(x,y,floor+.215),(0,0,yaw))
                add("deep_beam_broken" if (side,j) in broken_beams else "deep_beam",
                    f"beam {side}{j}",(x,y,floor+4.534),(0,0,yaw),(.854 if j in (1,n) else 1,1,1))
        for x in (-X_EDGE,X_EDGE):
            for y in (-Y_EDGE,Y_EDGE):
                add("deep_beam",f"bearing {x:+.2f} {y:+.2f}",(x,y,floor+4.534),(0,0,0),(.148,1,1))
    detail.frame_set(1)
    scene["render_water_reference_z"]=WATER_Z
    scene.frame_set(1)
    for image in bpy.data.images:
        if image.source=="FILE":
            image.filepath="//"+os.path.relpath(image.filepath,SOURCE)
    path=SOURCE/"ocean_rooftop_farm_v014.blend"
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True,relative_remap=False)
    layout.update(version="v014",base_version="v013")
    write(SOURCE/"component_instances.json",layout)
    write(SOURCE/"submerged_levels.json",{"levels":levels})
    manifest=read(OLD/"asset_manifest.json")
    manifest.update(version="v014",base_version="v013",source=path.relative_to(ROOT).as_posix(),
                    source_sha256=sha(path),runtime_status="pending",submerged_levels=7,
                    water_source_z=WATER_Z,submerged_instances=sum(len(level["placements"]) for level in levels))
    write(SOURCE/"asset_manifest.json",manifest)
    print(f"Saved {path.name} with seven individually damaged lower storeys")


main()
