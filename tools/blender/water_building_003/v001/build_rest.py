exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())
random.seed(3003)
def trunk():
    tube('Trunk',[(0,0,0),(-.6,-.3,2.7),(.2,-.4,5.7),(-.4,-.2,8.7),(.2,0,11.7),(1.2,.1,12.9)],1.5,'darkwood',8,taper=.5)
    tube('Root1',[(-.2,-.2,.1),(-1.4,-.7,.15),(-2.6,-1.0,.1)],.5,'darkwood',6,taper=.6)
    tube('Root2',[(.3,.3,.1),(1.2,1.1,.12),(1.8,1.8,.1)],.4,'darkwood',6,taper=.6)
    tube('BranchL',[(.1,0,11),(-1.6,.3,12.6),(-3.0,.4,13.9)],.55,'darkwood',6,taper=.6)
    tube('BranchR',[(.4,.3,9.4),(2.0,2.4,10.1),(5.2,3.4,10.7),(8.0,2.4,10.8),(10.4,1.7,11.0)],.6,'darkwood',6,taper=.7)
part('trunk',trunk)
def cl():
    blob('CL_Core',(0,0,0),(4.8,3.8,1.8),'leaf_mid',1)
    for i,(dx,dy,dz,c) in enumerate([(-3.6,.2,.5,'leaf'),(3.4,.3,.9,'leaf_light'),(0,-1.2,1.3,'leaf_yellow'),(-1.6,.8,1.6,'lime'),(1.9,-.8,-.2,'leaf_dark'),(-2.0,-1.0,-.4,'leaf_mid'),(3.9,-.6,-.3,'leaf')]):
        blob('CL_Lobe',(dx,dy,dz),(2.0,1.7,1.05),c,1)
part('crown_left',cl)
def cr():
    blob('CR_Core',(0,0,0),(3.6,3.0,1.2),'leaf_mid',1)
    for dx,dy,dz,c in [(-2.0,0,.3,'leaf'),(2.0,.2,.2,'leaf_yellow'),(.2,-.6,.7,'leaf_light')]:
        blob('CR_Lobe',(dx,dy,dz),(1.3,1.2,.7),c,1)
part('crown_right',cr)
def moss():
    blob('Moss1',(0,0,0),(1.6,1.2,.45),'moss',1); blob('Moss2',(1.2,.3,-.1),(1.0,.8,.35),'leaf_dark',1)
part('moss_mound',moss)
def vine():
    tube('Vine',[(0,0,2.8),(.15,0,2.0),(-.1,0,1.2),(.1,0,.5),(0,0,0)],.05,'forest',4,taper=.2)
    for i,z in enumerate([2.2,1.6,1.0,.4]): blob('VLeaf',((-1)**i*.18,.05,z),(.2,.08,.14),'leaf',0,.05)
part('vine',vine)
def flower():
    for i,(x,y) in enumerate([(0,0),(.35,.1),(-.3,.15)]):
        tube('Stem',[(x,y,0),(x,y,.5)],.03,'forest',4,taper=.1); blob('Bloom',(x,y,.56),(.14,.14,.1),['rose','pink','red'][i],0,.05)
    blob('FlowerLeaf',(0,.05,.12),(.45,.25,.12),'leaf_dark',0,.05)
part('flower',flower)
def leaf():
    for i,a in enumerate((0,1.3,2.6,3.9,5.2)):
        x=math.cos(a)*.35;y=math.sin(a)*.35
        blob('BigLeaf',(x,y,.3),(.5,.18,.3),'leaf' if i%2 else 'leaf_mid',0,.05)
part('big_leaf',leaf)
def pole():
    tube('Pole',[(0,0,0),(0,0,11.2)],.1,'steel',6,False,taper=.35,role='SEA_Metal')
    box('Arm',(0,0,10.0),(3.4,.18,.18),'wood_mid',b=.02,r=.03)
    box('ArmBrace',(0,0,9.6),(1.6,.12,.12),'wood_dark',b=.015,r=.03,rot=(0,.5,0))
part('pole',pole)
def pipe():
    tube('Pipe',[(0,0,0),(0,0,4.6),(.25,0,5.0)],.09,'sage_gray',6,False,taper=.2)
part('pipe',pipe)
def lean():
    box('LeanRoof',(0,0,.8),(3.0,2.6,.14),'wood_mid',b=.03,r=.03,rot=(.12,0,0))
    for x in (-1.3,1.3): box('LeanPost',(x,-1.1,0),(.14,.14,.9),'wood_dark',b=.02,r=.05)
part('lean_to',lean)
def wbox():
    box('Box',(0,0,0),(.9,.4,1.1),'wood_mid',b=.03,r=.03); box('BoxLid',(0,-.0,1.1),(1.0,.46,.1),'wood_dark',b=.02,r=.03)
part('wall_box',wbox)
def sign():
    box('Plate',(0,0,0),(.7,.08,.5),'butter',b=.012,r=.025)
part('sign_plate',sign)
def rub():
    box('Stone',(0,0,0),(.9,.7,.5),'lightgray',b=.04,r=-.06); box('Stone2',(.8,.2,0),(.6,.5,.35),'stone',b=.03,r=-.06)
part('rubble',rub)
def pot():
    box('Pot',(0,0,0),(.8,.8,.9),'coral',b=.04,r=-.08)
part('clay_pot',pot)
def crate():
    box('Crate',(0,0,0),(.9,.7,.7),'wood_light',b=.03,r=-.06); box('CrateStrap',(0,0,.7),(.96,.76,.06),'wood_dark',b=.015,r=-.06)
part('crate',crate)
print(len(catalog), sum(e['triangles'] for e in catalog))
