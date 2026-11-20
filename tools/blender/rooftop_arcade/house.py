def path(name, pts, radius, color, mat='Matte', sides=12):
    # Rounded corners, with tangent approach and departure instead of square elbows.
    out=[Vector(pts[0])]
    for a,b,c in zip(pts,pts[1:],pts[2:]):
        a,b,c=Vector(a),Vector(b),Vector(c); d=min((a-b).length*.32,(c-b).length*.32,.135)
        p=b+(a-b).normalized()*d; q=b+(c-b).normalized()*d
        out += [(1-t)**2*p+2*t*(1-t)*b+t*t*q for t in (0,.125,.25,.375,.5,.625,.75,.875,1)]
    out.append(Vector(pts[-1])); return tube(name,out,radius,color,mat,sides=sides)


def octagon(w,d,ch):
    return [(-w+ch,-d), (w-ch*1.5,-d), (w,-d+ch*1.3),(w-.025,d-ch), (w-ch,d),(-w+ch*1.1,d),(-w,d-ch*1.2),(-w-.035,-d+ch)]


def architecture():
    part('float_base')
    for label,w,d,z,h,col in [('lower floating collar',2.23,1.69,.125,.25,'navy'),('salvaged lower concrete band',2.28,1.73,.163,.15,'slate'),('walkway rounded apron',2.30,1.82,.310,.186,'tile')]:
        extrude(label,octagon(w,d,.16),h,col,2,z,.038)
    for i in range(4):
        x=-1.74+i*1.16
        box('front rim cast-in break', (x,-1.802,.337),(.038,.025,.112),'graylight',b=.008,rot=(0,.10*(i%2*2-1),0))
    part('deck_surface')
    for i in range(12):
        x=-1.985+i*.36; l=3.28-abs(x)*.04
        box('reclaimed deck slat %02d'%i,(x,.026,.043),(.348,l,.086),('floor','tile','sand','graylight')[i%4],b=.01,skew=(.004*(-1)**i,0))
    part('shop_shell')
    box('west masonry insulated wall',(-1.36,.025,.874),(.17,2.13,1.748),'gray',b=.025,skew=(.046,0))
    box('east masonry insulated wall',(1.36,.025,.874),(.17,2.13,1.748),'gray',b=.025,skew=(-.042,0))
    box('rear plaster wall',(0,1.08,.874),(2.85,.17,1.748),'graylight',b=.027,skew=(.034,-.018))
    for j in range(9):
        x=-1.14+j*.285
        box('joinery lining %02d'%j,(x,.966,.867),(.274,.049,1.72),('wood','wooddark','woodlight','honey')[j%4],b=.01,skew=(.016*(-1)**j,0))
    for y in (-.67,.50):
        box('pitched ceiling trimmer',(0,y,1.675),(2.62,.15,.14),'wooddark',b=.018)
    for j in range(6):
        box('shop soffit planks',(-1.05+j*.42,0,1.725),(.408,2.05,.10),'wood',b=.01)
    for i in range(5):
        box('asymmetrical rear cement repair',(-1.02+.50*i,1.181,.20+.19*(i%3)),(.28,.029,.21),('gray','tile','plaster')[i%3],b=.013,rot=(0,.16*(-1)**i,0))
    part('storefront')
    for x,d in [(-1.374,.15),(1.371,.15)]:
        box('tapered charcoal shop column',(x,-.018,.785),(d,.19,1.57),'darksteel',b=.026,skew=(-x*.023,0))
    box('warm limestone overdoor',(0,-.038,1.698),(2.94,.251,.255),'plaster',b=.034,skew=(.037,0))
    box('shop sign folded frame',(0,-.181,1.528),(1.23,.048,.175),'slate',b=.018,rot=(0,-.025,0))
    box('old chartreuse shop fascia',(0,-.211,1.528),(1.16,.024,.132),'moss',b=.01)
    mark('dim painted storefront characters','PLAY !!!',(0,-.225,1.527),.088,'lime')
    part('shop_door')
    profile('asymmetric lower metal door',[(-.36,.025),(.36,.035),(.349,.646),(-.347,.658)],.050,0,'graylight',b=.019)
    for x in (-.331,.326):
        box('slender door stile',(x,0,1.030),(.064,.057,.785),'graylight',b=.013,skew=(-x*.04,0))
    box('door top rail',(0,0,1.421),(.72,.050,.075),'graylight',b=.017,rot=(0,-.026,0))
    box('thick blue door glass',(0,-.001,1.034),(.598,.04,.687),'glass',b=.015,mat='Gloss')
    path('bent nickel pull',[(-.23,-.017,.555),(-.23,-.073,.55),(-.23,-.076,.408),(-.23,-.02,.395)],.014,'chalk')
    for z in (.16,1.16): box('offset exposed hinge',(.348,.030,z),(.062,.054,.134),'steel',b=.009,mat='Metal')
    path('OPEN plaque hanging cotton',[(-.132,-.039,1.047),(.02,-.04,1.210),(.166,-.039,1.05)],.007,'rope')
    box('cream door ticket',(.017,-.048,1.018),(.324,.024,.119),'cream',b=.009,rot=(0,-.09,0)); mark('raised OPEN type','OPEN',(.017,-.063,1.018),.069,'ink')
    part('brick_mortar')
    profile('front core left jamb',[(-1.45,0),(-.57,0),(-.54,1.18),(-1.412,1.18)],.149,-1.00,'mortar',b=.025)
    profile('front core right jamb',[(.55,0),(1.45,0),(1.412,1.18),(.51,1.18)],.149,-1.00,'mortar',b=.025)
    box('front core below sash',(0,-1.00,.137),(1.118,.148,.268),'mortar',b=.021)
    box('front core above sash',(0,-1.0,1.091),(1.075,.149,.166),'mortar',b=.021)
    for x in (-1.353,1.353): box('side structural brick backing',(x,.018,.590),(.16,1.86,1.18),'mortar',b=.025,skew=(-x*.024,0))
    box('rear structural brick backing',(0,1.015,.590),(2.84,.16,1.18),'mortar',b=.025,skew=(.006,-.018))
    for key,w,h,col in [('brick_a',.325,.113,'brick'),('brick_b',.295,.108,'bricklight'),('brick_c',.313,.112,'brickdark')]:
        part(key); d=.087; a=w/2
        profile('rounded fired brick with tapered chipped corner',[(-a+.018,0),(a-.026,0),(a,.019),(a-.009,h*.81),(a-.035,h),(-a+.017,h*.965),(-a,h*.72),(-a+.007,.015)],d,0,col,b=.010)
    part('quoin')
    profile('irregular rounded limestone key stone',[(-.128,.01),(-.10,0),(.130,0),(.144,.048),(.127,.159),(.08,.18),(-.115,.17),(-.145,.135)],.144,0,'cream',b=.022)
    part('sash')
    profile('deep navy window pocket',[(-.538,.020),(.527,0),(.501,.820),(-.500,.841)],.145,.025,'darkblue',b=.03)
    profile('asymmetrically cut blue glass',[(-.396,.106),(.400,.086),(.371,.678),(-.379,.703)],.040,-.066,'glass',b=.014,mat='Gloss')
    for x in (-.469,.464):
        box('indented limestone window jamb',(x,-.069,.418),(.151,.187,.78),'chalk',b=.025,skew=(-x*.08,0))
    box('irregular limestone lintel',(0,-.078,.792),(1.17,.20,.124),'cream',b=.027,rot=(0,-.039,0))
    box('projecting limestone sill',(0,-.114,.042),(1.18,.24,.127),'chalk',b=.028,rot=(0,.014,0),rho=-.044)
    profile('glass reflection facets',[(-.327,.56),(-.231,.635),(.306,.351),(.310,.276)],.003,-.087,'blue',b=.001,mat='Gloss')
    part('loft_deck')
    box('cream wraparound terrace coping',(0,0,.108),(3.17,2.43,.199),'chalk',b=.045,skew=(.026,0),rho=-.024)
    box('warm lower shadow bead',(0,0,.037),(3.03,2.33,.074),'sand',b=.021)
    for j in range(12):
        x=-1.391+j*.251
        box('upper lodge wood flooring %02d'%j,(x,0,.213),(.243,2.33,.042),('wood','woodlight','honey','wood')[j%4],b=.01,skew=(.005,0))
    part('loft_shell')
    for i in range(11):
        x=-1.205+i*.242; ht=1.47+.14*(x+1.3)/2.6
        box('rear mint salvaged bay %02d'%i,(x,1.019,ht/2),(.234,.153,ht),('mint','mintlight','mint','mintdark')[i%4],b=.017,skew=(.016*(i%2),-.017))
        box('warm rear vertical lining',(x,.921,ht/2),(.228,.040,ht-.042),('wood','honey','wooddark','woodlight')[i%4],b=.009,skew=(.008,0))
    for side in (-1,1):
        for i in range(7):
            y=-.83+i*.282; ht=(1.48 if side<0 else 1.64)-.080*y
            box('staggered mint end panel %d %d'%(side,i),(1.36*side,y,ht/2),(.159,.271,ht),('mintdark','mint','mintlight','mint')[i%4],b=.014,skew=(-.020*side,.019*(-1)**i))
            box('inner end blue or timber batten',(1.26*side,y,ht/2),(.035,.265,ht-.065),('blue','wood','woodlight','wooddark')[i%4],b=.01,skew=(0,.016*(-1)**i))
            if i in (0,1,2,3,5):
                h=.43+.127*(i%3)
                box('offset lap repair strip',(1.45*side,y,h/2+.055),(.052,.26,h),('blue','bluelight','terracotta','rust')[i%4],b=.012,rot=(.05*(-1)**i,.068*side,0),skew=(0,.018))
        for y in (-1.02,1.02):
            box('battered timber corner post',(1.32*side,y,.772),(.136,.141,1.544),'mintdark',b=.021,skew=(-.038*side,0))
    for i in range(8):
        x=-1.13+i*.223
        box('rear harbor blue skirting panel',(x,1.107,.254),(.211,.051,.499+(.039 if i%2 else 0)),('blue','bluelight','navy')[i%3],b=.01,rot=(0,.035*(-1)**i,0))
    for x,z in [(-.76,1.295),(-.40,1.40),(.77,1.19)]:
        profile('irregular sun-faded repaired mint paint',[(x-.08,z+.04),(x+.085,z+.066),(x+.067,z-.033),(x+.020,z-.075),(x-.077,z-.05)],.013,1.102,'mintlight',b=.008)
    for side in (-1,1):
        rod('rear door cross strap',(.34,1.107,.82+side*.43),(1.17,1.113,.82-side*.43),.014,'rope')
    part('loft_front')
    profile('bent mint parapet sheet',[(.185,.014),(1.343,.025),(1.339,1.064),(1.219,1.091),(.217,1.041)],.134,.023,'mint',b=.026)
    for j in range(5):
        x=.304+j*.213; h=.52+.06*(j%3)
        box('scavenged blue and coral boarding',(x,-.065,h/2+.027),(.202,.060,h),('blue','bluelight','blue','terracotta','rust')[j],b=.011,skew=(.032*(-1)**j,0))
    for s in (-1,1): rod('exposed crossed front strapping',(.24,-.049,.75+s*.30),(1.29,-.049,.75-s*.30),.013,'rope')
    profile('wavy header across open sleeping bay',[(-1.374,1.224),(-.16,1.19),(1.352,1.261),(1.357,1.552),(-1.384,1.43)],.147,.023,'mintlight',b=.024)
    box('mint left door side post',(-1.315,.015,.68),(.147,.17,1.36),'mint',b=.024,skew=(.035,0))
    part('loft_roof')
    for j in range(7):
        x=-1.352+j*.450
        grid=[]
        for iy in range(23):
            y=-1.258+iy*.118
            row=[]
            for ix in range(19):
                t=ix/18; zz=.217+.061*cos(t*tau*1.52+.36*j)+.025*sin(y*2.09+j*.85)+.057*x-.052*y
                row.append((x-.231+.455*t+.018*sin(y*3+j),y+.026*sin(t*4+j),zz))
            grid.append(row)
        sheet('hand warped corrugated zinc panel %02d'%j,grid,.042,('slate','mintdark','moss','blue','navy','blue','mintdark')[j])
    for x in (-1.29,-.68,0,.67,1.28):
        rod('protruding roof joist',(x,-1.28,.142+.057*x),(x,1.27,.032+.057*x),.058,'wooddark')
    path('bent front mint eave edging',[(-1.57,-1.254,.112),(-.65,-1.277,.149),(.50,-1.26,.214),(1.56,-1.23,.277)],.047,'mintdark')
    box('stovepipe roof boot',(1.05,.65,.271),(.28,.29,.16),'slate',b=.024,rot=(0,.065,0))
    rod('roof capped chimney',(1.06,.65,.28),(1.026,.65,.657),.063,'steel','Metal'); rod('chimney wide rim',(1.026,.65,.645),(1.025,.65,.677),.076,'darksteel')
    part('exterior_stair')
    for x in (-.345,.345):
        extrude('sloped profile stringer', [(-1.11,.038),(-.60,.038),(1.040,1.066),(1.114,1.257),(.920,1.295),(-.744,.257),(-1.1,.254)],.101,'slate',0,x,.022)
        for y,z in [(-.96,.153),(-.55,.33),(.05,.69),(.67,1.075),(1.01,1.19)]:
            oval('round stair stringer pin',(x+(.055 if x>0 else -.055),y,z),(.016,.026,.026),'steel','Metal')
    box('tapered slate stair landing',(0,-.879,.155),(.88,.526,.200),'navy',b=.034,skew=(.028,0))
    for i in range(8):
        y=-.557+i*.228; z=.256+i*.141
        box('separate worn stair tread %02d'%i,(0,y,z),(.629,.224,.105),('gray','graylight','slate')[i%3],b=.013,skew=(.014*(-1)**i,0))
        box('warm safety nose',(.004,y-.114,z+.028),(.631,.026,.049),'steel',b=.009)
    for x in (-.28,.31):
        rod('sea green stair brace',(x,-1.021,.040),(x,-.833,.206),.031,'teal')
    part('access_ladder')
    for x in (-.187,.195):
        path('tapered green hook ladder rail',[(x,-.017,0),(x,.024,.23),(x*.97,.041,1.26),(x*.93,.057,1.72),(x*.92,.19,1.75)],.036,'moss')
    for i in range(7):
        z=.145+i*.247
        rod('individual warm rung',(-.205,.043,z),(.211,.046,z+.011*(-1)**i),.032,['woodlight','rope','wood'][i%3])
        for x in (-.185,.19):
            rod('ladder rung rope binding',(x-.024,.044,z),(x+.020,.044,z+.003),.039,'olive')
    part('awning')
    grid=[]
    for j in range(22):
        t=j/21; row=[]
        for i in range(61):
            u=i/60; x=(u-.5)*1.40+.035*sin(t*pi); y=.285-.725*t+.027*sin(u*6*pi)*t**5
            z=.323-.139*t-.054*t*t+.030*sin(u*8*pi)*t**3+.014*sin(t*pi*2+u*14)*t
            row.append((x,y,z))
        grid.append(row)
    sheet('patched canvas bowed top',grid,.028,'blue')
    for j in range(7):
        grid=[]
        for row in range(8):
            t=row/7; out=[]
            for i in range(13):
                u=(j+(i/12)*.986)/7; x=(u-.5)*1.4+.013; z=.127+.025*sin(u*8*pi)-t*(.044+.139*sin(pi*i/12)**.72); y=-.442+.021*sin(u*6*pi)-.031*t*sin(pi*i/12)
                out.append((x,y,z))
            grid.append(out)
        sheet('curved individual blue scallop %02d'%j,grid,.022,('bluelight','blue','blue')[j%3])
    for x in (-.54,.54):
        path('canvas underframe bracket',[(x,.294,.07),(x,.282,.233),(x,-.374,.18)],.019,'slate')
    part('utility_pole')
    tube('warm bent utility mast',[(0,0,0),(.016,-.012,1.17),(.044,.006,2.52),(.058,.018,3.83),(.089,.034,5.056)],.087,'wood',taper=.18,sides=12)
    for j,z in enumerate((4.44,4.765)):
        box('rounded pole crossarm',(.07,0,z),(1.031,.113,.092),'slate',b=.021,rot=(0,.028*(1-j*2),0),skew=(.015,0))
        for x in (-.33,.47):
            rod('tapered insulator mount',(x,.001,z+.036),(x,.001,z+.105),.043,'steel')
            oval('ceramic insulator dome',(x,.001,z+.106),(.065,.06,.046),'slate')
            oval('ceramic insulator neck',(x,.001,z+.127),(.04,.04,.041),'darksteel','Gloss')
    for z in (2.67,3.36,4.48,4.79):
        tube('mast clamp',[(.056,0,z-.030),(.056,0,z+.03)],.097,'steel','Metal',sides=12)
    box('pole porcelain junction box',(.047,-.096,3.49),(.218,.109,.339),'gray',b=.020,rot=(0,.071,0))
    box('pole access cover',(.047,-.157,3.49),(.157,.032,.271),'graylight',b=.016,rot=(0,.071,0))
    for x in (-.057,.101): rod('box shelf attachment',(x,-.054,3.35),(x,-.13,3.37),.012,'slate')
    for j in range(4):
        tube('long restrained timber seam',[(.001+j*.021,-.078,1.07+j*.19),(.021+j*.021,-.079,1.78),(.041+j*.021,-.075,2.51-j*.12)],.006,('wooddark','woodlight')[j%2],sides=6)
    part('drainage')
    path('main wrap gutter and uneven downpipe',[(-1.48,1.19,3.023),(-1.54,-1.21,3.018),(-1.39,-1.27,2.995),(1.17,-1.27,3.011),(1.38,-1.24,2.976),(1.39,-1.25,2.69),(1.375,-1.28,1.82),(1.249,-1.23,1.43),(1.23,-1.12,.81),(1.205,-1.12,.023)],.061,'plaster')
    for x,y,z in [(-1.534,-.05,3.021),(-1.54,-.95,3.023),(-.79,-1.27,3.015),(.61,-1.27,3.014),(1.389,-1.25,2.70),(1.377,-1.27,2.102),(1.259,-1.23,1.51),(1.227,-1.12,.41)]:
        a=(x-.044,y,z) if z>2.90 and y<-1.22 else (x,y-.040,z) if z>2.90 else (x,y,z-.040)
        b=(2*x-a[0],2*y-a[1],2*z-a[2]); rod('rolled pipe collar',a,b,.075,'sand')
    path('front cobalt service cable',[(.388,-1.20,2.32),(.95,-1.23,2.31),(.98,-1.265,1.85),(1.42,-1.286,1.80),(1.50,-1.15,1.93),(1.50,-.47,1.96)],.018,'blue')
    path('sagging ochre service cable',[(.45,-1.20,2.40),(1.02,-1.222,2.38),(1.055,-1.25,1.73),(1.44,-1.27,1.66),(1.57,-.95,1.95),(1.56,-.53,.93)],.018,'yellow')
    tube('sagging pole-to-store conduit',[(-1.850+.38*t,-.60-.52*t,3.32-.45*t-.27*sin(pi*t)) for t in [i/28 for i in range(29)]],.020,'gold')
    part('service_hardware')
    for i in range(2):
        x=.54+i*.29
        path('rear bent riser and copper connectors',[(x,.008,0),(x,0,1.71),(x+.04,0,1.94),(x+.04,-.015,2.58),(x+.27,-.032,2.65)],.026,('steel','copper')[i],mat='Metal')
        box('tapered rear junction case',(x,-.029,1.65+i*.15),(.21,.108,.29),'graylight',b=.018,rot=(0,.052*(-1)**i,0))
        box('rear meter window',(x,-.090,1.699+i*.15),(.123,.025,.090),'gray',b=.009)
    for j in range(3):
        box('staggered rear wall repair patch',(-1.06+.26*j,-.018,.45+.13*(j%2)),(.247,.037,.263),('tile','graylight')[j%2],b=.014,rot=(0,.151*(-1)**j,0))
    part('exterior_signs')
    box('hanging tokens deep frame',(0,0,.329),(.487,.082,.655),'slate',b=.03,skew=(.025,0),rot=(0,-.055,0))
    box('tokens rate board',(0,-.047,.329),(.427,.027,.590),'ink',b=.019,skew=(.022,0),rot=(0,-.055,0))
    for tx,z,c,h in [('TOKENS',.548,'yellow',.074),('1 - 25',.431,'mintlight',.068),('4 - 75',.340,'teallight',.068),('9 - 150',.248,'gold',.057),('TRADE IN',.115,'sand',.041)]: mark('raised tokens '+tx,tx,(0,-.066,z),h,c)
    part('mooring')
    path('bent sea cleat',( (0,-.13,.022),(0,-.12,.107),(0,.12,.107),(0,.15,.03) ),.035,'darksteel')
    tube('fender untwisted rim',[(.139*cos(tau*i/32),0,.181+.138*sin(tau*i/32)) for i in range(33)],.044,'navy',sides=12)
    path('fender secured rope',[(-.02,.041,.38),(.04,.015,.353),(.019,0,.314)],.016,'rope')


def placement(scene, layers, items, animated=False):
    seq=0
    for key,pos,rot,scale,phase,zone,delay in items:
        seq+=1
        if zone in ('hide','loft_side') and scene.name=='街机屋_室内剖视': continue
        obj=bpy.data.objects.new(('BUILD ' if animated else '')+key+' %03d'%seq,None); layers[zone].objects.link(obj)
        obj.instance_type='COLLECTION'; obj.instance_collection=PARTS[key]; obj.empty_display_size=.08
        obj['asset_key']=key; obj['instance_index']=seq; obj['phase']=phase
        p=Vector((pos[0],pos[1],pos[2]+PARTS[key]['original_min_z']*scale[2])); rz=Euler(rot); orig=Vector(scale)
        obj.location=p; obj.rotation_euler=rz; obj.scale=orig
        if animated:
            assembly_keyframes(scene,obj,p,rz,orig,phase,seq)


def arrangement():
    items=[]
    def a(k,x,y,z,p,zone='structure',r=0,scale=(1,1,1),delay=0,tilt=(0,0)):
        items.append((k,(x,y,z),(tilt[0],tilt[1],r),scale,p,zone,delay))
    a('float_base',0,0,0,0); a('deck_surface',0,0,.334,0,delay=9)
    a('shop_shell',0,0,.42,1); a('storefront',0,-1.096,.421,1,'hide',delay=6)
    a('shop_door',-.993,-1.253,.418,2,'hide',r=-.33)
    a('brick_mortar',0,0,2.26,3,'hide')
    for wall in ('front','back','right','left'):
        nominal=2.77 if wall in ('front','back') else 1.95
        for row in range(10):
            rng=GEN; origin=-nominal/2+.024+(row*.003); end=nominal/2-.024-row*.003
            pos=origin; i=0
            while pos<end-.065:
                width=min(end-pos,max(.091,(.175 if row%2 and i==0 else .32)+rng.uniform(-.026,.035)))
                u=pos+width/2; z=2.270+row*.117+rng.uniform(-.006,.005)
                key=rng.choices(['brick_a','brick_b','brick_c'],weights=[65,22,13])[0]; nw={'brick_a':.325,'brick_b':.295,'brick_c':.313}[key]; gap=.010
                def put(u,w):
                    if w<.06: return
                    if wall=='front': x,y,rr=-u,-1.104,pi
                    elif wall=='back': x,y,rr=u,1.113,pi
                    elif wall=='right': x,y,rr=1.442,u,pi/2
                    else: x,y,rr=-1.442,-u,-pi/2
                    if wall=='front': x,rr=u,0
                    a(key,x,y,z,3,'hide',r=rr+rng.uniform(-.027,.027),scale=((w-gap)/nw,1,rng.uniform(.92,1.05)),delay=3+row*3+rng.randrange(0,8),tilt=(0,rng.uniform(-.029,.029)))
                if wall=='front' and 2<=row<=8:
                    lo=pos; hi=pos+width
                    for l,h in ((lo,min(hi,-.486)),(max(lo,.486),hi)):
                        if h>l: put((l+h)/2,h-l)
                else: put(u,width)
                pos+=width; i+=1
    for s in (-1,1):
        for row in range(6):
            a('quoin',s*(1.363-.008*row),-1.177,2.269+row*.187,3,'hide',scale=(1.04 if row%2 else .78,1,1.0),delay=7+row*4,tilt=(0,s*.041))
            a('quoin',s*1.473,.918,2.268+row*.188,3,'hide',r=s*pi/2,scale=(.79 if row%2 else 1,1,1.0),delay=8+row*4)
    a('sash',.010,-1.156,2.458,3,'hide',delay=11)
    a('loft_deck',0,0,3.424,4)
    a('loft_shell',0,0,3.655,5,'structure')
    a('loft_front',0,-1.072,3.653,5,'hide',delay=9)
    a('loft_roof',0,0,5.154,6,'hide')
    a('exterior_stair',1.835,-.020,2.212,4,delay=8)
    a('access_ladder',1.898,-.929,.560,2,delay=8)
    a('awning',1.717,.244,1.484,2,'hide',r=pi/2,delay=10)
    a('utility_pole',-1.948,-.62,.407,1,delay=10)
    a('drainage',0,0,.419,7,'hide')
    a('service_hardware',0,1.177,.429,7,'hide',r=pi,delay=1)
    a('exterior_signs',-1.936,-.741,1.545,3,delay=8)
    a('mooring',-2.01,-1.69,.001,0,delay=14)
    a('mooring',2.097,1.49,.001,0,r=pi,delay=16)
    a('side_vent',.94,1.196,.558,2,r=pi)
    a('side_vent',1.459,.32,2.604,4,r=pi/2)
    a('vent_fan',.852,1.189,2.751,4,'hide',r=pi)
    a('vent_fan',1.475,.314,4.620,6,'hide',r=pi/2)
    a('arcade_blue',-.955,-.293,.425,2,'furniture',r=.37,delay=1)
    a('arcade_yellow',-.593,.218,.425,2,'furniture',r=.17,delay=5)
    a('token_counter',-.016,.21,.427,2,'furniture',r=-.055,delay=11)
    a('repair_bench',.827,-.474,.425,2,'furniture',r=-.10,delay=8)
    a('tool_board',.091,.901,1.090,2,'furniture',delay=5)
    a('utility_rack',-.864,.781,.425,2,'furniture',delay=2)
    a('heater',.906,.697,.425,2,'furniture',r=-.04,delay=9)
    a('shop_stool',-.106,-.767,.425,2,'furniture',r=.22,delay=10)
    a('shop_stool',.680,-.074,.425,2,'furniture',r=-.28,delay=12)
    a('shipping_crate',1.858,.035,.421,2,'furniture',r=.16,delay=14)
    a('shipping_crate',1.621,.327,.421,2,'furniture',r=-.08,delay=14,scale=(.95,1,.81))
    a('shipping_crate',1.620,.328,.665,2,'furniture',r=.11,delay=16,scale=(.76,.79,.70))
    a('shipping_crate',1.135,.305,.424,2,'furniture',r=-.19,delay=15)
    a('lighting',.113,-.548,1.924,2,'furniture',r=pi/2,scale=(.81,.81,.75),delay=19)
    a('loft_bed',-.759,.093,3.655,5,'furniture',r=.025,delay=6)
    a('coffee_table',.129,-.278,3.656,5,'furniture',r=-.11,delay=10)
    a('loft_shelf',.851,.746,3.656,5,'furniture',r=-.025,delay=10)
    a('vent_fan',.508,.887,4.624,5,'furniture',delay=14)
    a('loft_frames',-.331,.904,4.121,5,'furniture',r=.020,delay=11)
    a('loft_curtain',-.925,-1.098,4.402,6,'furniture',r=-.047,delay=4)
    a('clothesline',1.644,.783,4.144,6,r=pi/2,delay=5)
    a('lighting',-.160,.030,4.715,6,'furniture',delay=3)
    a('shipping_crate',.904,-.865,3.655,5,'furniture',r=.09,delay=15)
    return items


def decoration_panels():
    # Build side sale sign in the awning mother; front is turned out by its collection instance.
    part('awning'); p=(.048,.281,.513)
    box('bevelled marine SALE frame',p,(.786,.096,.278),'teal',b=.032,rho=-.038,rot=(0,-.065,0))
    box('SALE enamel insert',(.048,.222,.513),(.718,.037,.221),'turquoise',b=.019,rot=(0,-.065,0))
    mark('raised SALE type','SALE',(.048,.197,.514),.145,'mintlight')
    for x in (-.284,.389): oval('rolled sign fastener',(x,.201,.527),(.017,.010,.017),'teallight')
    part('loft_front')
    tube('loft front loose hanging pale cord',[(x,-.087-.034*sin(pi*i/24),1.42-.202*sin(pi*i/24)**2) for i,x in enumerate([-.81+j*.086 for j in range(25)])],.022,'chalk')
    part('storefront')
    profile('shop threshold worn outline',[(-.69,-.260),(.725,-.260),(.66,.02),(-.61,.028)],.028,.03,'wooddark',b=.009)
    part('loft_shell')
    for x in (-1.07,-.46,.24,.84):
        box('roof room exposed rear ledge',(x,.902,1.47),(.42,.186,.091),'wooddark',b=.012)
    part('exterior_stair')
    for y in (-1.10,.96):
        rod('landing stop and rail terminal',(.345,y,.173 if y<0 else 1.21),(.357,y,.56 if y<0 else 1.52),.033,'slate')
    path('outer bent stair handrail',[(.353,-1.095,.545),(.357,-.657,.545),(.361,.934,1.537),(.364,1.085,1.554)],.035,'slate')


def camera(scene,col,name,pos,target,scale):
    d=bpy.data.cameras.new(name); o=bpy.data.objects.new(name,d); col.objects.link(o); o.location=pos; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); d.type='ORTHO'; d.ortho_scale=scale; d.lens=50; return o


def light(col,name,pos,target,power,size,color):
    l=bpy.data.lights.new(name,'AREA'); l.energy=power; l.shape='DISK'; l.size=size; l.color=color
    o=bpy.data.objects.new(name,l); col.objects.link(o); o.location=pos; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()


def stage(scene, kind):
    col=group(scene.collection,'90 展示支持_不导出')
    scene.unit_settings.system='METRIC'; scene.render.engine='CYCLES'; scene.cycles.samples=20; scene.cycles.use_denoising=True; scene.render.resolution_x=1000; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=.46
    w=bpy.data.worlds.new('Cloudy sea light '+kind); w.use_nodes=True; w.node_tree.nodes.get('Background').inputs[0].default_value=(.63,.73,.80,1); w.node_tree.nodes.get('Background').inputs[1].default_value=.46; scene.world=w
    grd=bpy.data.materials.get('Stage only - mist blue')
    if not grd:
        grd=bpy.data.materials.new('Stage only - mist blue'); grd.diffuse_color=(.265,.406,.44,1)
    m=bpy.data.meshes.new('Shadow catcher not exported'); m.from_pydata([(-200,-200,-.03),(200,-200,-.03),(200,200,-.03),(-200,200,-.03)],[],[(0,1,2,3)]); m.materials.append(grd)
    o=bpy.data.objects.new('Backdrop / not exported',m); col.objects.link(o); o.hide_set(True) if scene==bpy.context.scene else None
    light(col,'Sun through coastal clouds',(-4,-6,10),(0,0,2.1),1360,7,(1,.86,.69))
    light(col,'Cool sky return',(5,-1,7),(0,0,2.4),880,5,(.69,.86,1))
    light(col,'Soft rim',(-1,5,8),(0,0,2.4),1220,5,(1,.95,.78))
    light(col,'Bounce under the shop fascia',(-.32,-1.34,1.67),(.04,.73,.89),32,1.1,(1,.82,.64))
    light(col,'Bounce under the bedroom eaves',(-.42,-1.13,4.71),(-.31,.48,4.16),27,.85,(1,.82,.63))
    if kind=='Exterior':
        scene.camera=camera(scene,col,'Hero',(8.7,-12.9,7.5),(0,0,2.72),7.15)
        camera(scene,col,'Front',(0,-14,2.74),(0,0,2.74),6.42)
        camera(scene,col,'Right',(14,0,2.74),(0,0,2.74),6.42)
        camera(scene,col,'Back',(0,14,2.74),(0,0,2.74),6.42)
    elif kind=='Interior':
        scene.camera=camera(scene,col,'Shop',(3.20,-8,3.00),(-.05,.13,1.19),3.52)
        camera(scene,col,'Loft',(-.67,-8.1,5.49),(.02,.21,4.33),3.57)
        camera(scene,col,'Plan',(2.35,-5.07,13),(0,0,2.70),6.24)
        camera(scene,col,'Dollhouse',(2.15,-13,5.75),(0,0,2.66),6.71)
        camera(scene,col,'Utility',(-2.18,-7.72,3.38),(.22,.61,1.01),2.80)
        light(col,'Shop bounce',(.06,-.82,1.78),(.03,.43,.86),80,1.4,(1,.75,.43))
        light(col,'Loft bedside bounce',(-.42,-.47,5.0),(-.31,.48,4.16),42,1.06,(1,.74,.44))
    else:
        scene.camera=camera(scene,col,'Assembly hero',(8.7,-12.9,7.5),(0,0,2.72),7.15)
        # Fixed orthographic framing makes the parallel placement paths easy to read.
    return col


def initialize():
    if bpy.data.filepath==DEST:
        master=bpy.data.scenes['街机屋_组件母版']
        bpy.context.window.scene=master
        for scene in list(bpy.data.scenes):
            if scene!=master: bpy.data.scenes.remove(scene)
        for c in list(bpy.data.collections): bpy.data.collections.remove(c)
        for o in list(bpy.data.objects): bpy.data.objects.remove(o,do_unlink=True)
        for im in list(bpy.data.images):
            if im.name.startswith('sea_rooftop_arcade'): bpy.data.images.remove(im)
    elif bpy.data.filepath or len(bpy.data.scenes)>1 or '街机屋_组件母版' in bpy.data.scenes:
        raise ValueError('Run this rebuild only in the Rooftop Arcade source or an independent factory-startup Blender session.')
    master=bpy.context.scene; master.name='街机屋_组件母版'; master.unit_settings.system='METRIC'
    for o in list(master.objects): bpy.data.objects.remove(o,do_unlink=True)
    for c in list(master.collection.children): bpy.data.collections.remove(c)
    for cat,keys in PLAN.items():
        top=group(master.collection,{'architecture':'01 水上建筑结构','furniture':'02 室内家具与附属设施'}[cat])
        for key in keys:
            p=group(top,'SEA-SCENE-RAC-'+key.upper().replace('_','-')); p['asset_key']=key; PARTS[key]=p
    materials(); architecture(); decoration_panels()
    print('Exterior geometry created', len(PARTS))


def recover():
    for keys in PLAN.values():
        for k in keys:
            PARTS[k]=bpy.data.collections['SEA-SCENE-RAC-'+k.upper().replace('_','-')]
    for role in ('Matte','Metal','Gloss','Emission'):
        MATS[role]=bpy.data.materials['SEA_'+role]


def build_furnishings():
    recover(); furniture(); fixtures()
    print('Interior furniture created')


def finish_assembly():
    recover(); master=bpy.data.scenes['街机屋_组件母版']
    finalize_master(master)
    all_items=arrangement()
    for name,kind in [('街机屋_参考装配','Exterior'),('街机屋_室内剖视','Interior'),('街机屋_组装动画','Animation')]:
        scene=bpy.data.scenes.new(name); scene.render.fps=24; scene.frame_start=1; scene.frame_end=241
        ls={k:group(scene.collection,n) for k,n in [('structure','01 建筑骨架'),('hide','02 可拆外皮'),('loft_side','03 阁楼侧面'),('furniture','04 家具和陈设')]}
        stage(scene,kind); placement(scene,ls,all_items,kind=='Animation')
        if kind=='Animation':
            assembly_markers(scene)
            scene.frame_set(AIRDROP_END)
    scene=bpy.data.scenes['街机屋_参考装配']
    bpy.context.window.scene=scene
    for ar in bpy.context.screen.areas:
        if ar.type=='VIEW_3D':
            ar.spaces.active.region_3d.view_perspective='CAMERA'; ar.spaces.active.shading.type='MATERIAL'; ar.spaces.active.overlay.show_overlays=False
    for m in list(bpy.data.materials):
        if m.users==0 or m.name=='Material': bpy.data.materials.remove(m)
    bpy.ops.wm.save_as_mainfile(filepath=DEST,relative_remap=False)
    print('SAVED',DEST,'components',len(PARTS),'instances',len(all_items),'meshes',sum(len(c.objects) for c in PARTS.values()))

