import math
import random
from mathutils import Euler, Vector


def rot(x=0, y=0, z=0):
    return Euler(tuple(map(math.radians, (x, y, z)))).to_matrix()


def facade_bay(m):
    for x in (-1.89, 1.89):
        m.box("Recess side wall", (x, .08, 2.45), (.48, .4, 4.9), "gray", bevel=.075)
    for z, h, mat in ((.60, 1.2, "gray"), (4.15, 1.5, "stone")):
        m.box("Window spandrel", (0, .08, z), (3.31, .4, h), mat, bevel=.065)
    m.box("Shadow behind recessed window", (0, .34, 2.31), (3.31, .10, 2.21), "rubber")
    for x in (-1.57, 0, 1.57):
        m.box("Inset metal mullion", (x, -.17, 2.30), (.085, .09, 2.22), "slate", bevel=.014)
    for x in (-.80, .80):
        m.box("Concrete window sill", (x, -.19, 1.25), (1.48, .24, .13), "silver", bevel=.027)
        points = [(x-.69, -.09, 1.40), (x+.69, -.09, 1.40), (x+.69, -.09, 1.85),
                  (x+.41, -.09, 1.59), (x+.12, -.09, 1.95), (x-.22, -.09, 1.68),
                  (x-.48, -.09, 2.26), (x-.69, -.09, 1.93)]
        m.panel("Jagged blue window fragments", points, .024, "deepblue", bevel=.009)
    for x, z in ((-1.82, 4.58), (1.3, .62), (1.80, 3.92)):
        m.panel("Broken plaster edge", [(x-.22,-.15,z),(x+.27,-.15,z+.08),
                (x+.18,-.15,z+.34),(x-.06,-.15,z+.25),(x-.24,-.15,z+.33)], .023,"slate")


def plaster_flakes(m, seeds, wall_y):
    for i,(x,z,w,h) in enumerate(seeds):
        outline = ((-.5,-.18),(-.34,-.48),(.14,-.39),(.48,-.21),(.39,.22),(.11,.47),(-.29,.36))
        m.panel("Irregular exposed render", [(x+a*w,wall_y,z+b*h) for a,b in outline],
                .029,("stone","sand","cloud","gray")[i%4],bevel=.009)


def sash(m,x,y,z,width,height,old=False):
    box=m.box
    paint = "wood_dark" if old else "steel"
    if not old:
        box("Internal shadow reveal",(x,y+.18,z),(width+.025,.041,height+.025),"slate",bevel=.011,kind="opening")
    for side in (-1,1):
        off = side*(width*.5-.048)
        box("Window jamb with visible depth",(x+off,y+.018,z),(.092,.212,height-.192),
            paint,bevel=.014,kind="opening")
        box("Sash head or lower rail",(x,y+.018,z+side*(height*.5-.048)),(width,.212,.091),
            paint,bevel=.015,kind="opening")
    box("Stone head flashing",(x,y+.033,z+height*.5+.020),(width+.080,.278,.048),
        "stone",bevel=.012,kind="opening")
    box("Stone sill with square drip edge",(x,y-.037,z-height*.5-.059),(width+.181,.385,.119),
        "gray" if old else "sage_gray",bevel=.019,kind="opening")
    if old:
        box("Broken sash lower upright",(x-.027,y-.080,z-.31),(.058,.103,.538),
            "wood_mid",rotation=rot(y=-4),bevel=.012,kind="opening")
        box("Loose horizontal sash",(x-width*.137,y-.086,z+.001),(width*.63,.09,.055),
            "wood_dark",rotation=rot(y=5),bevel=.010,kind="opening")
        x0,x1=x-width*.40,x+width*.40
        for points in (
            [(x0,z-.50),(x-.09,z-.50),(x-.14,z-.20),(x-.30,z-.32),(x0,z-.13)],
            [(x+.10,z-.50),(x1,z-.50),(x1,z-.09),(x+.27,z-.27)],
            [(x0,z+.49),(x-.21,z+.49),(x-.31,z+.33),(x0,z+.16)],
        ):
            m.panel("Jagged glazing retained in old sash",[(a,y+.088,b) for a,b in points],
                    .024,"deepblue",role="Gloss",bevel=.008)
        return
    box("Central upright of inset sash",(x,y-.026,z),(.079,.112,height-.199),paint,bevel=.014,kind="opening")
    for side in (-1,1):
        px=x+side*(width*.25+.012)
        box("Rail between inset panes",(px,y-.035,z),(width*.5-.146,.119,.066),
            "wood_edge",bevel=.014,kind="opening")
        for row in (-1,1):
            box("Individual inset glass pane",(px,y+.082,z+row*(height*.245-.019)),
                (width*.5-.163,.026,height*.5-.135),"ocean" if row>0 else "deepblue",
                role="Gloss",bevel=.008,kind="opening")


def bent_tube(m,name,path,radii,color,*,hollow=False):
    points = [Vector(point) for point in path]
    sides = 12
    vertices = []
    for inner in range(2 if hollow else 1):
        for i, (center,radius) in enumerate(zip(points,radii)):
            tangent = (points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
            right = Vector((1,0,0))
            if abs(tangent.x)>.93:
                right=Vector((0,0,1))
            right = (right-tangent*tangent.dot(right)).normalized()
            up = tangent.cross(right)
            ratio=.69 if inner else 1
            for j in range(sides):
                angle=math.tau*j/sides
                vertices.append(center+ratio*radius*(right*math.cos(angle)+up*math.sin(angle)))
    def face(a,b,j,k):
        return a*sides+j,a*sides+k,b*sides+k,b*sides+j
    faces = [face(i,i+1,j,(j+1)%sides) for i in range(len(points)-1) for j in range(sides)]
    if hollow:
        count=len(points)
        faces += [tuple(reversed(face(i,i+1,j,(j+1)%sides)))
                  for i in range(count,count*2-1) for j in range(sides)]
        for i in (0,count-1):
            faces += [face(i,i+count,j,(j+1)%sides)[::(1 if i else -1)] for j in range(sides)]
    else:
        faces.extend((tuple(range(sides-1,-1,-1)),tuple(range(len(vertices)-sides,len(vertices)))))
    m.form.append({"id":name,"kind":"linear","d_bottom":2*radii[0],"d_top":2*radii[-1]})
    return m.mesh(name,vertices,faces,color,role="Metal",smooth=True)


def wall_hardware(m, damaged=False):
    def gutter(name,x0,x1,y,z):
        shape=((-0.092,.045),(-.083,-.039),(-.055,-.078),(.055,-.078),(.092,-.045),(.092,.045),
               (.072,.045),(.072,-.039),(.049,-.058),(-.045,-.058),(-.063,-.027),(-.071,.045))
        vertices=[(x,y+dy*k,z+dz*k) for x,k in ((x0,1),(x1,.974)) for dy,dz in shape]
        n=len(shape)
        faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        m.mesh(name,vertices,faces,"bark",role="Metal",bevel=.009)

    gutter("Square rain channel", -2.92, -.88 if damaged else 4.36, -3.031, 3.46)
    if damaged:
        gutter("Remaining channel east of break",.35,3.94,-3.029,3.385)
        bent_tube(m,"Upper sheared drain",[(-1.29,-3.031,3.44),(-1.29,-3.031,3.24),
                  (-1.29,-2.88,3.14),(-1.29,-2.71,3.04),(-1.29,-2.69,2.43)],
                  [.074,.072,.071,.070,.069],"bark",hollow=True)
        bent_tube(m,"Bent lower drain with open end",[(-1.42,-2.87,1.95),(-1.38,-2.82,1.60),
                  (-1.27,-2.70,1.28),(-1.27,-2.67,.35),(-1.27,-2.79,.14),(-1.27,-2.96,.13)],
                  [.077,.075,.074,.072,.071,.070],"wood_dark",hollow=True)
    else:
        bent_tube(m,"Continuous metal downpipe",[(-1.29,-3.031,3.44),(-1.29,-3.031,3.28),
                  (-1.29,-2.91,3.17),(-1.29,-2.75,3.10),(-1.29,-2.68,3.01),
                  (-1.29,-2.68,.46),(-1.29,-2.72,.32),(-1.29,-2.86,.24),(-1.29,-3.01,.24)],
                  [.078,.077,.076,.075,.074,.073,.072,.071,.071],"wood_dark",hollow=True)
        m.round("Downpipe socket",(-1.29,-2.68,1.27),(-1.29,-2.68,1.41),.084,.080,"bark",role="Metal")
    for x in (-2.77,-1.92,-.98,.48,1.68,3.63):
        if damaged and -.92 < x < .40:
            continue
        m.bar("Gutter support strap",(x,-2.938,3.487),(x,-3.107,3.397),
              .036,"wood_dark",bevel=.008,role="Metal")
    for z in ((.67,2.65) if damaged else (.72,1.64,2.65)):
        m.box("Pipe clamp masonry socket",(-1.29,-2.596,z),(.205,.079,.093),"stone",bevel=.018)
        m.round("Strapped pipe collar",(-1.29,-2.681,z-.032),(-1.29,-2.681,z+.032),
                .088,.083,"bark",role="Metal")


def roof_access(m, damaged=False):
    box, tube=m.box,m.round
    if damaged:
        for side in (-1,1):
            x=side*.343
            m.panel("Broken sill supporting ladder foot",[(x-.21,-.197,.045),(x+.18,-.184,.045),
                (x+.22,.109,.045),(x+.191,.656,.045),(x-.213,.656,.045),(x-.173,.087,.045)],
                .156,"stone",bevel=.016)
            m.bar("Bracket under damaged sill",(x,-.137,-.097),(x,.646,-.390),.101,"bark",bevel=.022)
    else:
        box("Rectangular ladder landing sill",(0,.229,-.045),(1.03,.864,.18),"stone",bevel=.032)
    for side in (-1,1):
        x=side*.343
        if damaged and side<0:
            path=[(x,0,.105),(x,0,1.56),(x-.06,.013,2.40),(x-.09,.047,3.43)]
            radii=[.057,.055,.054,.053]
        else:
            path=[(x,0,.105),(x,0,3.75),(x,.025,3.925),
                  (x,.108,4.044),(x,.233,4.093),(x,.420,4.093),
                  (x,.586,4.021),(x,.706,3.901),(x,.788,3.60)]
            radii=[.058,.057,.056,.056,.055,.055,.054,.054,.053]
        bent_tube(m,"Formed ladder stile with return grip",path,radii,"wood_dark")
        box("Masonry landing foot socket",(x,0,.107),(.18,.19,.118),"slate",bevel=.023)
    for i in range(12):
        if damaged and i in {4,8,10}:
            continue
        z=.315+i*.287
        left=-.343-(.064 if damaged and i>=7 else 0)
        tube("Recessed ladder tread",(left+.021,0,z),(.321,0,z-(.054 if damaged and i in (6,11) else 0)),
             .042,.039,"honey" if not damaged else "wood_mid",role="Metal",bevel=.012)
    for z in (.47,1.91,3.13):
        for side in (-1,1):
            if damaged and z==1.91 and side<0:
                continue
            x=side*.343
            m.bar("Wall stand-off bracket",(x,.060,z),(x,.614,z),.087,"wood_dark",bevel=.016,role="Metal")
            box("Recessed mounting plate and two fasteners",(x,.616,z),(.168,.054,.156),"slate",bevel=.018)
            for dz in (-.048,.048):
                tube("Anchor bolt",(x,.584,z+dz),(x,.548,z+dz),.025,.023,"steel",n=6,role="Metal",bevel=.008)


def roof_eaves(m, damaged=False):
    levels = [(-4.49,-2.89),(-2.879,-.92),(-.909,.94),(.951,2.78),(2.791,4.49)]
    for i,(left,right) in enumerate(levels):
        base=.085
        if damaged and i in (1,2,4):
            outline = [(left,base+.016),(left+.30,base-.033),(left+.54,base+.054),
                       ((left+right)/2-.09,base+.006),(right-.18,base+.074),
                       (right-.082,base+.165),(right-.21,base+.231),
                       (right-.046,.359),(left+.095,.363)]
            m.panel("Fractured concrete eave face",[(x,-2.952,z) for x,z in outline],.394,
                    ("stone","plaster","cloud")[i%3],bevel=.022)
            for j in range(2):
                x=right-.16+j*.048
                m.bar("Bent exposed eave reinforcement",(x,-2.78,.205),
                      (x+.17+j*.04,-2.99,.119-j*.036),.024,"bark",bevel=.008,role="Metal")
            continue
        m.box("Square-front concrete cap segment",((left+right)/2,-2.755,.235),
              (right-left,.398,.300),"plaster" if i%3 else "stone",
              bevel=.028,kind="horizontal_cover")
        m.box("Dark inset drip course",((left+right)/2,-2.72,.087),
              (right-left-.022,.325,.071),"wood_dark",bevel=.012,kind="horizontal_cover")
    m.box("Square rear coping",(0,2.716,.235),(8.95,.386,.300),"stone",
          bevel=.028,kind="horizontal_cover")
    for x in (-4.30,4.30):
        m.box("Square return coping",(x,-.005,.235),(.37,5.067,.30),"plaster",
              bevel=.028,kind="horizontal_cover")


def make_component(key, m):
    box, bar, tube, panel = m.box, m.bar, m.round, m.panel
    if key == "facade_bay":
        facade_bay(m)
    elif key == "corner_pier":
        box("Half metre main post", (0,0,2.45), (.5,.5,4.9), "stone", bevel=.095)
    elif key == "base_slab":
        box("200 mm floor slab", (0,0,.1), (34.4,13.8,.2), "slate", bevel=.044)
    elif key == "facility_footing":
        box("Inlaid fixing stone", (0,0,.08), (.62,.58,.16), "stone", bevel=.049)
        for x in (-.18,.18):
            tube("Fixing stud",(x,0,.163),(x,0,.193),.035,.033,"steel",role="Metal",bevel=.009)
    elif key == "edge_beam":
        box("Continuous deep eave face", (0,0,.29), (4.28,.56,.58), "stone", bevel=.12)
        box("Eave coping", (0,-.01,.66), (4.28,.65,.14), "plaster", bevel=.06)
    elif key == "rail_section":
        for i, x in enumerate((-1.61,-.55,.55,1.61)):
            tube("Iron baluster", (x,0,.05),(x,0,.84), .052,.049,"slate", role="Metal")
            box("Inset baluster shoe", (x,0,.067), (.19,.15,.13),"gray",bevel=.023)
            box("Copper handrail socket", (x,0,.815), (.17,.16,.16),"wood_edge",bevel=.028)
        bar("Warm wooden handrail", (-2.125,0,.87),(2.125,0,.87), .114,"wood_dark", bevel=.035)
        bar("Low horizontal rail", (-2.125,0,.265),(2.125,0,.265), .082,"wood_mid")
    elif key == "rail_pier":
        box("Parapet pier", (0,0,.51), (.67,.66,1.02), "stone", bevel=.121)
        box("Rounded pier cap", (0,0,1.09), (.79,.76,.18), "plaster", bevel=.082)
    elif key.startswith("deck_tile_"):
        colors = {"a":"stone","b":"sand","c":"cloud"}
        box("Beveled 200 mm roof stone", (0,0,.10), (2.143,2.273,.2), colors[key[-1]],
            bevel=.045,rho=.01,kind="horizontal_cover")
        if key.endswith("c"):
            panel("Mineral inset", [(-.83,-.94,.202),(-.54,-.77,.209),(-.64,-.51,.207),
                  (-.92,-.57,.205),(-1.010,-.69,.204)], .010,"stone",bevel=.008)
    elif key == "deck_underframe":
        for x in (-1.07,1.07):
            box("Underfloor bearer", (x,0,.11), (.19,4.55,.22), "gray",bevel=.044)
        for y in (-1.72,0,1.72):
            box("Transverse rib", (0,y,.11), (1.93,.18,.19), "slate",bevel=.037)
    elif key == "terrace_step":
        for i,color in enumerate(("stone","cloud","sand")):
            box("Stone step", (0,(i-1)*.29,(i+1)*.12/2), (4.26,.285,(i+1)*.12),color,bevel=.043)
    elif key == "upper_stair_bridge":
        for i in range(6):
            box("Upper bridge plank",((i-2.5)*.487,0,.10),(.478,1.66,.2),
                ("wood","wood_light","wood_mid")[i%3],bevel=.065,kind="horizontal_cover")
        for y in (-.62,.62):
            box("Upper bridge bearing",(0,y,-.075),(2.88,.16,.14),"wood_dark",bevel=.049)
    elif key == "pier_dock":
        for x in (-1.8,1.8):
            box("Dock support", (x,0,.32), (.5,2.6,.60), "wood_dark",bevel=.095)
        for i in range(6):
            box("Dock board", ((i-2.5)*.77,0,.73), (.75,2.7,.2), "wood_mid" if i%3 else "wood_light",bevel=.094)
        for x in (-2.1,2.1):
            box("Mooring post", (x,-.92,1.05), (.4,.4,.8), "wood_dark",bevel=.055)
    elif key == "access_stairs":
        # Two flights and a midlanding. Steps are load-bearing members, separate from riser gaps.
        for side in (-1,1):
            for i in range(13):
                y = -1.98+i*.30 if side < 0 else 1.64-i*.30
                z = .10+i*.185 + (2.50 if side > 0 else 0)
                box("External stair tread", (side*.72,y,z), (1.36,.285,.20),"wood_mid",bevel=.047)
            for x in (side*.72-.48, side*.72+.48):
                a,b = ((x,-2.07,.0),(x,1.70,2.28)) if side<0 else ((x,1.71,2.37),(x,-2.02,4.77))
                bar("Inclined exterior stringer", a,b,.19,"darkwood",bevel=.046)
            y0,y1 = (-2.0,1.63) if side<0 else (1.63,-2.0)
            z0 = .85 if side<0 else 3.35
            for t in (0,.33,.66,1):
                y=y0+(y1-y0)*t
                tube("Stair rail post",(side*1.39,y,z0-.80+2.22*t),(side*1.39,y,z0+2.22*t),.06,.056,"wood_dark")
            bar("Stair handhold",(side*1.39,y0,z0),(side*1.39,y1,z0+2.22),.105,"wood_light")
        box("Shared turning landing",(0,2.13,2.40),(2.85,.91,.2),"wood",bevel=.094)
        box("Upper stair landing",(.72,-2.43,4.80),(1.36,.59,.2),"wood_light",bevel=.094)
        box("Dock transfer landing",(-.72,-2.44,.1),(1.36,.61,.2),"wood_light",bevel=.092)
    elif key == "house_shell":
        box("Deep west return wall",(-4.11,0,1.55),(.32,4.95,3.1),"plaster",bevel=.079)
        box("Recessed east return wall",(4.11,.26,1.55),(.32,4.43,3.1),"stone",bevel=.079)
        box("Back wall",(0,2.37,1.55),(7.88,.28,3.1),"stone",bevel=.074)
        for x,w,y in ((-3.70,.88,-2.40),(-1.08,1.25,-2.40),(3.03,.34,-2.06),(4.01,.21,-2.06)):
            box("Deep grey plaster bay",(x,y,1.55),(w,.33,3.1),"plaster",bevel=.074)
        box("Corner return at recessed entry",(1.12,-2.25,1.54),(.26,.38,3.08),"stone",bevel=.053)
        for x,w,y in ((-2.43,1.65,-2.40),(.08,1.29,-2.40),(3.57,.81,-2.06)):
            box("Sill masonry",(x,y,.50),(w,.318,1),"stone",bevel=.046)
            box("Lintel masonry",(x,y,2.61),(w,.318,.96),"plaster",bevel=.051)
        box("Header over the recessed doorway",(2.02,-2.06,2.91),(1.67,.33,.34),"sand",bevel=.048)
        for x,y,w in ((-2.52,-2.577,3.01),(-.51,-2.577,1.92),(3.57,-2.24,.90)):
            for i in range(3):
                box("Painted plinth ashlar",(x+(i-1)*w/3,y,.26),(w/3-.012,.074,.49),
                    ("steel","gray","sage_gray")[i%3],bevel=.043)
        for x,y in ((-4.04,-2.575),(1.01,-2.575),(4.08,-2.26)):
            for z in (.38,.95,1.52,2.09,2.66):
                box("Corner quoin",(x,y,z),(.32,.10,.28),"stone",bevel=.042)
        plaster_flakes(m,[(-1.45,1.41,.39,.27),(-1.14,2.34,.40,.49)],-2.571)
        for i in range(5):
            box("Side return plinth ashlar",(-4.284,-1.95+i*.935,.244),(.081,.908,.47),
                ("gray","steel","sage_gray")[i%3],bevel=.028)
        for i,(y,z) in enumerate(((-.28,.98),(1.45,2.19))):
            panel("Side return plaster wear",[(-4.282,y-.29,z-.07),(-4.282,y-.22,z-.19),
                (-4.282,y+.08,z-.23),(-4.282,y+.28,z-.04),(-4.282,y+.14,z+.21),
                (-4.282,y-.17,z+.17)],.019,("stone","sand","cloud")[i%3],bevel=.008)
    elif key == "house_corner_patch":
        box("Rebuilt plaster pier at the doorway corner",(.785,-2.40,1.55),(.415,.317,3.1),"plaster",bevel=.055)
        plaster_flakes(m,[(.78,.64,.26,.25),(.81,2.38,.28,.38)],-2.563)
    elif key.startswith("wall_stone_"):
        color,edge = {"warm":("stone","wood_edge"),"sand":("sand","plaster"),
                      "cool":("sage_gray","gray")}[key.removeprefix("wall_stone_")]
        profile = [(-.47,.06),(.29,.0),(.50,.18),(.46,.57),(.21,.66),(-.39,.61),(-.53,.34)]
        m.panel("Dressed masonry face",[(x,-.108,z) for x,z in profile],.15,
                (color,edge,color,color,edge),bevel=.026)
    elif key == "house_damage":
        sash(m,-2.43,-2.56,1.66,1.53,1.27,old=True)
        sash(m,.08,-2.56,1.66,1.18,1.26,old=True)
        for i,(x,z) in enumerate(((.79,.33),(1.01,.56),(.88,.78),(.67,1.03),(1.04,1.19),
                                  (.93,1.46),(.74,1.70),(.92,2.00),(.76,2.21),(1.12,2.41))):
            box("Brick exposed along broken corner",(x,-2.611,z),(.25+.03*(i%3),.123,.165),
                ("bark","red_dark","wood_mid","gray")[i%4],rotation=rot(y=(i%3-1)*13),bevel=.034)
        for i,(x,z,w,h) in enumerate(((-3.35,1.40,.63,1.06),(-1.98,2.16,.94,.80),(-.20,.47,.63,.77),
                                     (.94,1.68,.73,1.33),(.89,2.73,.58,.55),(-3.52,.55,.65,.84))):
            pts=[(x+w*a,-2.633,z+h*b) for a,b in ((-.55,0),(-.20,-.55),(.20,-.47),(.55,-.13),(.36,.23),(.50,.42),(-.27,.52))]
            panel("Exposed chipped plaster",pts,.054,["gray","stone","slate"][i%3],bevel=.023)
            a=(x,-2.626,z+h*.36)
            b=(x+w*.27,-2.625,z+h*.72)
            c=(x+w*.14,-2.626,z+h*.96)
            branch=(b[0]-w*.24,b[1],b[2]+h*.11)
            for p,q in ((a,b),(b,c),(b,branch)):
                bar("Branching surface fracture",p,q,.027,"darkwood",bevel=.007)
        for j,x in enumerate((1.30,2.85,3.32,3.86)):
            box("Splintered jamb and loose shutter",(x,-2.248,1.39),(.17,.12,2.66-.19*(j%2)),
                ("darkwood","bark","wood_mid")[j%3],rotation=rot(y=(j%3-1)*6),bevel=.031)
        bar("Cracked lintel across unfinished door",(1.27,-2.26,2.72),(2.87,-2.26,2.67),.167,"bark",bevel=.038)
        for i,(x,y) in enumerate(((-3.63,-1.86),(-2.53,-1.34),(-1.17,-1.62),(.66,-1.74),(2.38,-1.53),(3.05,-.96))):
            z=3.319-y*math.tan(math.radians(7))
            panel("Roof moss island",[(x-.32,y-.15,z),(x-.21,y+.22,z),(x+.21,y+.20,z),
                  (x+.32,y+.01,z),(x+.09,y-.17,z)],.018,
                  ("sage","moss","moss_light")[i%3],bevel=.008)
    elif key == "house_roof":
        box("Flat roof structural plate", (0,.11,.1),(8.76,5.20,.20),"stone",bevel=.039)
        box("Chimney mortar body",(-2.35,.86,.61),(.59,.58,.79),"bark",bevel=.038)
        for i in range(5):
            for j in (-1,1):
                box("Staggered chimney brick",(-2.35+j*.169+.025*(i%2),.557,.28+i*.145),(.32,.10,.133),
                    ("red_dark","bark","red","coral","bark")[(i+j)%5],bevel=.021)
            box("Chimney side course",(-2.68,.88,.28+i*.145),(.093,.65,.132),
                ("red_dark","bark","red","coral","bark")[i],bevel=.021)
        box("Wide terracotta chimney cap",(-2.35,.86,1.03),(.88,.82,.15),"red_dark",bevel=.060)
        box("Chimney dark opening",(-2.35,.86,1.108),(.51,.49,.025),"rubber",bevel=.009)
        for x in (-.13,2.09):
            box("Raised roof hatch short curb",(x,.47,.375),(.25,1.58,.37),"plaster",bevel=.029)
        for y in (-.20,1.14):
            box("Raised roof hatch long curb",(.98,y,.375),(1.94,.24,.37),"sand",bevel=.028)
        box("Recess in roof hatch",(.98,.47,.255),(1.91,1.06,.067),"slate",bevel=.025)
        for y, start, posts in ((-2.36,-3.08,(-3.03,0,3.8)),(2.35,-3.93,(-3.8,0,3.8))):
            for x in posts:
                tube("Roof baluster",(x,y,.38),(x,y,.79),.051,.048,"wood_dark")
            bar("Roof handrail",(start,y,.78),(3.93,y,.78),.077,"wood_light")
    elif key in ("house_eaves","house_eaves_damage"):
        roof_eaves(m,key.endswith("_damage"))
    elif key in ("house_pipe","house_pipe_damage"):
        wall_hardware(m,key.endswith("_damage"))
    elif key == "entry_assembly":
        for x,y,w in ((-2.43,-.135,1.55),(.08,-.135,1.21),(3.57,.16,.77)):
            sash(m,x,y,1.66,w,1.29)
        x,y=2.03,.28
        box("Recessed vertical door",(x,y,1.36),(1.51,.18,2.72),"wood_dark",bevel=.049,kind="opening")
        for dx in (-.53,-.26,0,.26,.53):
            box("Raised door panel",(x+dx,y-.11,1.04),(.247,.072,1.91),
                "wood" if dx in (0,.53) else "wood_mid",bevel=.026)
        for dx in (-.779,.779):
            box("Beveled door jamb",(x+dx,y-.13,1.38),(.15,.20,2.76),"bark",bevel=.037,kind="opening")
        box("Amber door glazing",(x,y-.106,2.19),(.91,.070,.70),"slate",bevel=.026)
        for dx in (-.43,0,.43):
            box("Door glazing sash",(x+dx,y-.152,2.19),(.065,.065,.76),"wood_edge",bevel=.017)
        tube("Door handle",(x+.52,y-.15,1.28),(x+.52,y-.27,1.28),.062,.058,"gold",role="Metal")
        for i in range(11):
            x=1.23+i*.273
            for row in range(3):
                y=-1.14+row*.51
                z=2.58+row*.224
                box("Overlapping rounded red tile",(x,y,z),(.266,.60,.119),
                    ("red_dark","red","coral","red")[(i+row)%4],rotation=rot(x=24),bevel=.048,
                    kind="flat_attached",tilt=9)
        for x in (1.15,4.08):
            bar("Diagonal awning bracket",(x,.02,2.18),(x,-1.37,2.52),.12,"bark",bevel=.028)
        for x,y in ((-3.56,-.22),(-.89,-.23),(1.04,-.19),(3.02,.10)):
            tube("Wall lantern cap",(x,y,2.32),(x,y,2.40),.132,.123,"bark")
            box("Warm lantern lens",(x,y,2.17),(.16,.142,.28),"butter",role="Emission",bevel=.045)
            tube("Wall lantern shoe",(x,y,2.02),(x,y,2.067),.129,.121,"bark")
            for dx in (-.070,.070):
                bar("Dark lantern cage",(x+dx,y-.067,2.06),(x+dx,y-.067,2.33),.028,"bark",bevel=.011)
        for dx in (-.5,-.25,0,.25,.5):
            box("Wood threshold slat",(2.03+dx,-.29,.044),(.237,.78,.088),"wood_light",bevel=.028)
    elif key in ("roof_ladder","roof_ladder_damage"):
        roof_access(m,key.endswith("_damage"))
    elif key == "doghouse":
        for x in (-.62,.62):
            box("Kennel side", (x,0,.48),(.14,1.24,.96),"honey",bevel=.044)
        box("Kennel back", (0,.56,.48),(1.12,.13,.96),"wood",bevel=.037)
        for x in (-.45,.45):
            box("Arched entrance cheek",(x,-.60,.44),(.32,.15,.88),"wood_light",bevel=.049)
        panel("Entrance arch header",[(-.58,-.685,.89),(-.36,-.685,.61),(-.24,-.685,.81),
              (0,-.685,.90),(.24,-.685,.81),(.36,-.685,.61),(.58,-.685,.89),(0,-.685,1.31)],.11,"wood",bevel=.026)
        for side in (-1,1):
            for i in range(6):
                box("Blue roof shake",(side*.355,(i-2.5)*.245,1.11),(.86,.232,.13),
                    ("steel","solar","blue")[i%3],rotation=rot(y=side*28),bevel=.036)
        bar("Ridge cap",(0,-.77,1.373),(0,.77,1.373),.12,"ice",bevel=.034)
    elif key == "greenhouse_base":
        for x in (-2.67,2.67):
            box("Blue side sill",(x,0,.42),(.16,6.48,.84),"teal",bevel=.049)
            for i in range(8):
                box("Blue standing seam panel",(x, (i-3.5)*.80,.32),(.19,.758,.60),
                    ("ocean","teal","sage_gray")[i%3],bevel=.038)
            for y in (-1.72,0,1.72):
                box("Growing bench",(x*.70,y,.41),(1.12,1.62,.82),"wood_mid",bevel=.065)
                box("Recessed growing soil",(x*.70,y,.84),(1.0,1.49,.045),"darkwood",bevel=.015)
        for x in (-1.69,1.69):
            for y in (-3.20,3.20):
                box("Teal end sill",(x,y,.41),(1.88,.18,.82),"ocean",bevel=.049)
        box("Tall central greenhouse door", (0,-3.26,1.54),(1.56,.18,3.08),"wood_dark",bevel=.065,kind="opening")
        box("Glazed door inset", (0,-3.373,2.05),(1.24,.035,1.35),"jade",bevel=.011)
        for x in (-.59,0,.59):
            box("Door sash",(x,-3.405,2.05),(.074,.06,1.36),"wood_light",bevel=.019)
        for z in (1.38,2.05,2.72):
            box("Door rail",(0,-3.405,z),(1.29,.06,.074),"wood_edge",bevel=.017)
        tube("Brass pull",(.58,-3.42,1.19),(.58,-3.52,1.19),.070,.066,"gold",role="Metal")
        box("Rear kickboard",(0,3.20,.41),(1.7,.18,.82),"teal",bevel=.044)
    elif key == "greenhouse_glazing":
        arch=[(2.65*math.cos(math.pi*i/12),.88+2.89*math.sin(math.pi*i/12)) for i in range(13)]
        # Short vertical walls put the curved eave above the sill and keep the arch tall.
        arch = [(x,z + .56) for x,z in arch]
        cuts=[-3.23,-2.14,-1.07,0,1.07,2.14,3.23]
        for y in cuts:
            for i, ((x,z),(xx,zz)) in enumerate(zip(arch,arch[1:])):
                bar("Curved timber rib",(x,y,z),(xx,y,zz),.092,"wood_edge",bevel=.029)
            for x in (-2.65,2.65):
                bar("Side upright",(x,y,.86),(x,y,1.44),.105,"wood_light",bevel=.031)
        for i,(x,z) in enumerate(arch):
            bar("Lengthwise glazing rail",(x,cuts[0],z),(x,cuts[-1],z),.071,"stone",bevel=.024)
        for a,b in zip(cuts,cuts[1:]):
            for i,((x,z),(xx,zz)) in enumerate(zip(arch,arch[1:])):
                if i in (1,7) and a == 1.07:
                    continue
                panel("Blue curved glass pane",[(x,a+.048,z),(xx,a+.048,zz),(xx,b-.048,zz),
                      (x,b-.048,z)],.035,("sky","ice","seafoam")[(i+round(a))%3],bevel=.009,role="Gloss")
            for x in (-2.65,2.65):
                panel("Vertical side glazing",[(x,a+.05,.90),(x,b-.05,.90),(x,b-.05,1.42),(x,a+.05,1.42)],
                      .036,"aqua",bevel=.009,role="Gloss")
        for y in (-3.245,3.245):
            for i,((x,z),(xx,zz)) in enumerate(zip(arch,arch[1:])):
                bottom=max(3.15 if min(abs(x),abs(xx))<.81 else .89, .89)
                if min(z,zz) > bottom+.03:
                    panel("Glazed end fan",[(x,y,z-.025),(xx,y,zz-.025),(xx,y,bottom),(x,y,bottom)],
                          .033,"sky",bevel=.009,role="Gloss")
            for x,z in (tuple(arch[2]),tuple(arch[4]),tuple(arch[8]),tuple(arch[10])):
                bar("Front sash",(x,y,.87),(x,y,z),.086,"wood_light",bevel=.026)
    elif key == "greenhouse_debris":
        for i in range(4):
            y=(i-1.5)*1.34
            p=[(-2.68,y,.28),(-1.78,y+.21,.64),(-.77,y+.33,.81),(.23,y+.25,.55),(1.13,y-.02,.20)]
            if i%2:
                p=[(x+1.11,yy+.16,z+.12) for x,yy,z in p]
            for a,b in zip(p,p[1:]):
                bar("Buckled fallen arch",a,b,.109,("stone","wood_edge")[i%2],bevel=.034)
            if i%2==0:
                panel("Fallen triangular glass",[(p[0][0],y-.10,.34),(p[1][0],y+.28,.63),
                      (p[1][0]-.27,y+.87,.35),(p[0][0]+.37,y+.67,.27)],.044,"sky",role="Gloss")
        for i in range(5):
            x=-2.3+i*.89
            box("Twisted blue wall remnant",(x,-2.58+math.sin(i)*.65,.43),(.83,.67,.24),
                "teal", rotation=rot(x=13,y=12,z=i*24),bevel=.045)
        for x,y in ((2.33,1.87),(-2.42,1.43),(.96,2.47),(-.67,-1.48)):
            bar("Fractured loose rafter",(x,y,.17),(x+.53,y+.60,.49),.132,"wood_light")
    elif key == "tower_support":
        for x in (-1,1):
            for y in (-1,1):
                bar("Splayed timber stanchion",(x*1.27,y*1.26,.09),(x*.94,y*.94,2.91),.28,"bark",bevel=.055)
        for s in (-1,1):
            for z in (.64,2.34):
                bar("Water tank transverse brace",(-1.14,s*1.12,z),(1.14,s*1.12,z),.14,"wood_dark",bevel=.039)
            bar("Timber X bracing",(-1.17,s*1.12,.63),(1.04,s*1.01,2.33),.19,"bark",bevel=.036)
            bar("Timber X bracing",(-1.06,s*1.16,2.31),(1.19,s*1.19,.63),.17,"darkwood",bevel=.034)
            bar("Side diagonal support",(s*1.17,-1.13,.62),(s*1.01,1.01,2.38),.17,"wood_dark",bevel=.032)
        for i in range(10):
            box("Inspection platform plank",((i-4.5)*.331,0,2.92),(.319,3.23,.18),"wood_mid",bevel=.047)
        for y in (-1.50,1.50):
            for x in (-1.46,-.75,0,.75,1.46):
                tube("Perimeter post",(x,y,3.02),(x,y,3.55),.043,.040,"wood_dark")
            bar("Platform handrail",(-1.55,y,3.51),(1.55,y,3.51),.073,"wood_light")
        for x in (-1.56,-1.18):
            tube("Tank inspection ladder",(x,1.40,.13),(x,1.17,3.38),.040,.037,"wood_light")
        for i in range(12):
            tube("Inspection rung",(-1.54,1.40-i*.018,.35+i*.244),(-1.20,1.40-i*.018,.35+i*.244),.025,.0235,"honey")
    elif key == "tower_tank":
        m.vessel("Blue-green painted steel tank",(0,0),
                 ((.08,1.252),(.17,1.31),(.43,1.371),(.85,1.387),(1.34,1.32),(1.60,1.23),(1.69,1.184)),
                 ["teal","teal","aqua","teal","ocean","teal"],role="Metal")
        for z,r in ((.16,1.344),(.51,1.405),(1.52,1.273)):
            tube("Rolled tank hoop",(0,0,z),(0,0,z+.081),r,r*.977,"darkwood",n=24,bevel=.023,kind="shell")
        tube("Rounded lower lip of the copper lid",(0,0,1.665),(0,0,1.79),1.414,1.381,
             "red_dark",n=24,bevel=.035,kind="shell")
        tube("Terracotta conical lid",(0,0,1.76),(0,0,2.28),1.39,.18,
             ["red_dark","red","coral","red","bark","red"],n=16,bevel=.048,kind="sculpted")
        tube("Tank top finial",(0,0,2.27),(0,0,2.44),.17,.157,"bark",n=12,bevel=.038)
        for i in range(8):
            a=(i+.3)*math.pi/4
            x,y=math.cos(a),math.sin(a)
            for (z,r),(zz,rr) in zip(((.54,1.382),(.86,1.39),(1.34,1.325)),
                                      ((.86,1.39),(1.34,1.325),(1.52,1.275))):
                bar("Pressed tank seam",(x*r,y*r,z),(x*rr,y*rr,zz),.033,"petrol",bevel=.009,role="Metal")
    elif key == "tower_debris":
        for i,(x,y,d) in enumerate(((-1.36,-1.3,1),(-1.10,.78,-1),(1.28,1.29,-1),(1.20,-1.2,1))):
            bar("Broken braced upright",(x,y,.10),(x+d*.83,y-.48,.53+i*.06),.26,"bark",bevel=.053)
            bar("Broken footing splinter",(x+.09,y+.19,.12),(x+.59,y-.42,.21),.18,"darkwood")
        for x,y,z in ((-.55,-1.67,27),(1.86,.45,112),(.67,1.30,-20)):
            box("Fallen inspection plank",(x,y,.31),(1.25,.34,.16),"wood_mid",rotation=rot(x=7,y=13,z=z),bevel=.041)
    elif key == "windmill":
        for x,y in ((-.65,-.47),(.65,-.47),(.09,.60)):
            bar("Windmill splayed tripod",(x,y,.08),(0,.05,3.54),.17,"bark",bevel=.039)
        for z,w in ((.91,1.03),(1.86,.72),(2.71,.42)):
            bar("Tower bracing",(-w/2,-.31,z),(w/2,-.31,z),.11,"wood_mid")
        hub=(0,-.34,3.67)
        tube("Windmill hub",(0,-.21,3.67),(0,-.57,3.67),.19,.17,"bark",n=12)
        for i in range(8):
            a=math.tau*i/8+.19
            ca,sa=math.cos(a),math.sin(a)
            def p(r,w,y=-.48):
                return (r*ca-w*sa,y,3.67+r*sa+w*ca)
            bar("Blade spoke",hub,p(.96,0),.055,"wood_dark",bevel=.015)
            panel("Painted windmill vane",[p(.43,-.058),p(1.14,-.17,-.55),p(1.14,.18,-.40),p(.54,.12)],
                  .052,("red","plaster","coral","cream")[i%4],bevel=.017)
    elif key == "patio_table":
        tube("Round honey wood table top",(0,0,1.02),(0,0,1.17),1.07,1.012,"honey",n=24,bevel=.052)
        for i in range(4):
            a=i*math.pi/2+.4
            x,y=math.cos(a),math.sin(a)
            bar("Splayed table leg",(x*.74,y*.74,.034),(x*.55,y*.55,1.01),.15,"wood_dark",bevel=.037)
        for i in range(3):
            a=i*math.tau/3+.26
            x,y=1.33*math.cos(a),1.33*math.sin(a)
            tube("Round stool seat",(x,y,.45),(x,y,.55),.36,.34,"wood_light",n=14,bevel=.035)
            for j in range(3):
                a2=j*math.tau/3
                xx,yy=math.cos(a2),math.sin(a2)
                bar("Stool leg",(x+xx*.24,y+yy*.24,.04),(x+xx*.19,y+yy*.19,.45),.096,"bark")
        for x,y,r,col in ((.18,.10,.116,"ice"),(-.25,-.12,.122,"cream"),(-.14,.34,.15,"ochre")):
            tube("Cup and pitcher",(x,y,1.17),(x,y,1.39),r,r*1.07,col,n=12,bevel=.026,kind="freestanding")
        box("Wood tray",(.33,-.25,1.19),(.51,.33,.055),"wood_light",bevel=.020)
    elif key == "bench":
        for x in (-.77,.77):
            for y in (-.28,.29):
                bar("Bench feet",(x,y,.04),(x*.9,y*.84,.50),.13,"bark",bevel=.031)
            bar("Short back support",(x,.29,.47),(x,.40,1.02),.105,"wood_dark")
        for i in range(4):
            box("Seat plank",(0,-.28+i*.17,.53),(1.88,.151,.10),"wood_light",bevel=.037)
        for z in (.76,.96):
            box("Inclined back slat",(0,.39,z),(1.88,.10,.145),"honey",
                rotation=rot(x=-8),bevel=.032,kind="flat_attached",tilt=8)
    elif key == "clothesline":
        for x in (-2.4,2.4):
            tube("Laundry post",(x,0,0),(x,0,2.58),.105,.098,"wood_dark",bevel=.024)
            tube("Post finial",(x,0,2.58),(x,0,2.72),.13,.122,"wood_light")
            box("Post footing",(x,0,.09),(.40,.37,.18),"stone",bevel=.047)
        def sag(x):
            return 2.50-.46*(1-(x/2.4)**2)
        for i in range(24):
            x=-2.38+i*.198
            tube("Sagging rope",(x,0,sag(x)),(x+.194,0,sag(x+.194)),.026,.0246,"wood_edge",n=8,bevel=.008)
        for i,(center,width,h,c) in enumerate(((-1.71,.58,.72,"plaster"),(-.78,.77,.83,"honey"),
                                                (.37,.80,.88,"cream"),(1.47,.69,.80,"blue"))):
            verts=[]
            for j in range(9):
                u=j/8
                x=center+(u-.5)*width
                verts.append((x,0,sag(x)-.02))
                verts.append((center+(u-.5)*width*.96,.085+math.sin(u*math.tau*1.45+i)*.105,sag(center)-h+.09*math.cos(u*math.pi)))
            faces=[(j,j+1,j+3,j+2) for j in range(0,16,2)]
            cloth=m.mesh("Wind curved laundry cloth",verts,faces,c,smooth=True)
            cloth.modifiers.new("Fabric thickness","SOLIDIFY").thickness=.012
            for dx in (-.24,.24):
                box("Clothespin",(center+dx,-.03,sag(center+dx)+.025),(.062,.055,.12),"bark",bevel=.012)
    elif key == "trellis":
        for x in (-1.30,1.30):
            tube("Trellis post",(x,0,.05),(x,0,2.33),.099,.093,"wood_dark")
        for i in range(8):
            x=(i-3.5)*.341
            bar("Trellis reed",(x,0,.52),(x,0,2.25),.046,"wood_mid",bevel=.012)
        for i in range(6):
            z=.59+i*.325
            bar("Horizontal trellis reed",(-1.22,-.043,z),(1.22,-.043,z),.044,"honey",bevel=.012)
        for x,y in ((-.73,.28),(.37,.32)):
            box("Storage crate",(x,y,.27),(.94,.64,.54),"wood_dark",rho=-.044,kind="freestanding",bevel=.042)
            for i in range(3):
                box("Crate front cleat",(x,y-.34,.13+i*.15),(.86,.05,.128),"wood_mid",bevel=.016)
    elif key == "planter":
        box("Wide tapered planter",(0,0,.23),(1.39,.76,.46),"bark",rho=-.055,kind="freestanding",bevel=.087)
        box("Earth inside planter",(0,0,.465),(1.23,.59,.024),"darkwood",bevel=.009,kind="opening")
        for y in (-.387,.387):
            bar("Planter wood rim",(-.68,y,.445),(.68,y,.445),.095,"wood_light",bevel=.033)
        for x in (-.46,0,.46):
            box("Front vertical band",(x,-.396,.20),(.078,.038,.32),"honey",bevel=.017)
    elif key == "barrels":
        for i,(x,y,r,h,color) in enumerate(((-.63,0,.35,.89,"wood_mid"),(.14,.06,.34,.79,"plaster"),(.84,.11,.36,.94,"ocean"))):
            m.vessel("Rounded rain barrel",(x,y),((.04,r),(.15,r*1.09),(h*.48,r*1.17),
                     (h*.70,r*1.151),(h-.06,r*1.11),(h,r*1.06)),color,n=20,kind="freestanding")
            for z,ratio in ((.16,1.112),(h*.60,1.179),(h-.084,1.143)):
                tube("Rain barrel band",(x,y,z),(x,y,z+.050),r*ratio,r*ratio*.977,"slate",n=20,bevel=.018,kind="shell")
            tube("Recessed barrel lid",(x,y,h+.021),(x,y,h+.048),r*.81,r*.76,"wood_dark",n=14)
    elif key in ("flowers","greens"):
        rng=random.Random(92 if key=="flowers" else 101)
        for i in range(20):
            a=i*2.4
            end=(math.cos(a)*rng.uniform(.22,.59),math.sin(a)*rng.uniform(.18,.36),rng.uniform(.19,.58))
            m.leaf("Broad curled leaf",(0,0,.04),end,rng.uniform(.068,.145),
                   ("leaf","leaf_mid","lime","forest","moss")[i%5])
        if key=="flowers":
            for i,(x,y,z) in enumerate(((-.40,-.06,.53),(-.19,.18,.72),(0,-.18,.63),(.17,.13,.80),(.36,-.03,.57))):
                tube("Flower stalk",(x*.4,y*.4,0),(x,y,z),.024,.022,"leaf_dark",n=7,bevel=.009)
                for j in range(6):
                    a=j*math.tau/6
                    m.leaf("Flower petal",(x,y,z),(x+.125*math.cos(a),y+.125*math.sin(a),z+.04),.045,
                           ("butter","yellow","cream","ochre")[i%4])
                tube("Flower center",(x,y,z-.015),(x,y,z+.048),.052,.048,"gold",n=9,bevel=.009)
    elif key == "rubble":
        for i,(x,y,z,k) in enumerate(((-.18,-.20,.15,1),(.21,.02,.13,.7),(-.11,.21,.09,.6),(.29,.33,.08,.45))):
            points=[(x+k*a,y+k*b,z) for a,b in ((-.22,-.14),(.10,-.17),(.22,-.03),(.07,.14),(-.18,.14))]
            panel("Jagged mixed rubble",points,.12*k,("stone","gray","wood_edge","plaster")[i],bevel=.029)
