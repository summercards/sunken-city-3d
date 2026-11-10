exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
import math, random
# facilities

def linear_part(key, kind, pts, rad, color, role='SEA_Matte'):
    part(key, lambda: tube(kind,pts,rad,color,6,False,taper=.1,role=role))
linear_part('ladder','Ladder',[(-0.0,0,0),(0,0,3.3)],.055,'wood_dark')
linear_part('drainpipe','Drain',[ (0,0,0),(.0,0,4.2),(.25,0,4.8)],.075,'sage_gray')

def utility():
    box('Cabinet',(0,0,0),(1.0,.42,1.2),'wood_mid',b=.03,r=.03)
    box('CabinetDoor',(0,-.24,.1),(.72,.04,.82),'mint_white',b=.02,r=.02)
part('utility_box',utility)
def sign(): box('Sign',(0,0,0),(.72,.08,.5),'butter',b=.012,r=.025,rot=(0,.1,0))
part('sign',sign)
def bench():
    box('Seat',(0,0,.8),(2.0,.55,.14),'wood_mid',b=.03,r=-.06)
    for x in (-.75,.75): box('Leg',(x,0,0),(.16,.16,.8),'wood_dark',b=.02,r=-.06)
part('bench',bench)
def pot():
    box('Pot',(0,0,0),(.72,.72,.75),'coral',b=.035,r=-.08)
part('pot',pot)
def steps():
    box('StepA',(0,0,0),(4.0,1.2,.24),'stone',b=.04,r=.02)
    box('StepB',(0,-.3,.245),(3.2,.9,.24),'lightgray',b=.04,r=.02)
    box('StepC',(0,-.55,.49),(2.4,.65,.24),'stone',b=.04,r=.02)
part('stone_steps',steps)
def pole():
    tube('Pole',[(0,0,0),(0,0,9.4)],.095,'steel',6,False,taper=.25,role='SEA_Metal')
    box('PoleArm',(0,0,8.3),(2.2,.12,.12),'wood_dark',b=.015,r=.02)
part('pole',pole)
def wire():
    # thin no-volume cable with real bevel
    tube('Wire',[(-1.2,0,0),(0,0,.3),(1.2,0,0)],.018,'darkwood',5,True,taper=.1)
part('wire',wire)
# tree is independent from building
def trunk_main():
    tube('MainTrunk',[(0,0,0),(-.5,.2,2),(.3,.0,4),(-.8,.3,6),(-.3,0,8),(1.0,.2,10),(1.8,.3,12)],.85,'bark',8,True,taper=.46)
    tube('RootL',[(-.1,0,.15),(-1.8,-.2,.2),(-3.2,-.6,.18)],.42,'darkwood',6,True,taper=.65)
    tube('RootR',[(.2,0,.15),(1.5,.4,.2),(2.7,.8,.15)],.32,'darkwood',6,True,taper=.65)
part('trunk_main',trunk_main)
def trunk_branch():
    tube('BranchL',[(.2,0,7),(-1.7,.3,9.5),(-3.8,.7,11.2),(-5.4,.8,11.8)],.48,'darkwood',6,True,taper=.7)
    tube('BranchTop',[(1.0,.3,10),(1.8,.5,12.2),(2.2,.6,14)],.40,'darkwood',6,True,taper=.7)
    tube('BranchR',[(.6,.2,6.2),(2.8,1.0,7.2),(5.0,1.4,8.4),(6.7,1.2,9.0)],.42,'darkwood',6,True,taper=.68)
part('trunk_branch',trunk_branch)
def canopy_left():
    for p,s,c in [((0,0,0),(3.5,2.3,1.4),'leaf_mid'),((-2.8,.2,.2),(2.0,1.5,1.0),'leaf'),((2.5,.3,.3),(2.2,1.5,1.1),'leaf_light'),((-.8,-.6,.8),(2.2,1.5,1.0),'leaf_yellow'),((-3.8,.0,-.4),(1.6,1.2,.8),'leaf_dark')]: blob('Canopy',p,s,c,1)
part('canopy_left',canopy_left)
def canopy_top():
    for p,s,c in [((0,0,0),(2.9,2.0,1.0),'leaf_mid'),((-1.8,.2,.1),(1.5,1.2,.8),'leaf'),((1.7,0,.2),(1.6,1.2,.8),'leaf_light')]: blob('Canopy',p,s,c,1)
part('canopy_top',canopy_top)
def canopy_right():
    for p,s,c in [((0,0,0),(3.5,2.0,1.2),'leaf_mid'),((-2,.0,.2),(1.6,1.1,.8),'leaf'),((2,.1,.1),(1.8,1.1,.85),'leaf_light'),((0,-.6,.7),(1.8,1.0,.7),'leaf_yellow')]: blob('Canopy',p,s,c,1)
part('canopy_right',canopy_right)
def vine():
    tube('Vine',[(0,0,2.5),(.1,0,1.8),(-.15,0,1.0),(.05,0,.2)],.045,'forest',5,True,taper=.2)
part('vine',vine)
def moss(): blob('Moss',(0,0,0),(1.5,1.0,.5),'moss',1)
part('moss',moss)
def flowers():
    for i,c in enumerate(['rose','pink','red']):
        tube('Stem',[(i*.18,0,0),(i*.18,0,.55)],.025,'forest',5,True,taper=.1)
        blob('Bloom',(i*.18,0,.62),(.13,.13,.1),c,1,.04)
part('flower_cluster',flowers)
# placement and camera-facing front is -Y
put('door',(-.3,-3.55,.32)); put('window_large',(2.3,-3.56,2.0)); put('window_large',(-2.5,-3.56,2.0))
put('window_small',(-.5,-2.99,6.75)); put('window_upper',(.25,-2.3,11.1)); put('shutter',(2.0,-2.35,6.6),rot=(0,0,-math.pi/2))
put('balcony_lower',(2.75,-.2,5.5)); put('balcony_middle',(-2.25,-.2,10.15)); put('balcony_rail',(2.75,-2.5,6.0))
put('awning',(2.4,-2.7,7.1),rot=(.12,0,0)); put('ladder',(-3.5,-3.55,.3)); put('drainpipe',(3.75,-3.5,5.3),scale=(1,1,.9)); put('utility_box',(3.3,-3.65,2.0)); put('sign',(3.1,-3.63,3.5),rot=(0,.08,0)); put('stone_steps',(-.3,-3.8,.3)); put('bench',(-4.2,-3.7,.3)); put('pot',(4.4,-3.8,.3))
put('pole',(-5.3,1.0,.3)); put('wire',(-5.3,1.0,7.0))
put('trunk_main',(-5.0,1.0,.3)); put('trunk_branch',(-5.0,1.0,.3)); put('canopy_left',(-5.2,1.0,12.8)); put('canopy_top',(-2.3,1.2,15.0)); put('canopy_right',(5.2,1.4,9.2)); put('vine',(2.8,-3.7,4.6)); put('moss',(-2.0,-3.8,5.1)); put('moss',(1.0,-2.8,10.0),scale=(.7,.7,.7)); put('flower_cluster',(-4.0,-3.9,.3))
print('instances',len(instances),'components',len(catalog),'tri_master',sum(x['triangles'] for x in catalog))
