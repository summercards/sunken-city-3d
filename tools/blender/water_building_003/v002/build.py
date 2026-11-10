exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
random.seed(303)
# main structure: three offset levels, all masses tapered rather than cubic
part('foundation',lambda:box('Foundation',(-.2,0,0),(14.0,10.0,.3),'stone',b=.094,r=.015))
def lower_shell():
 frustum('Lower',(.2,0),(9.2,7.0),(9.02,6.86),.3,4.9,'plaster',b=.095)
 for x in (-4.25,4.65): box('LowerCorner',(x,-3.52,.35),(.22,.24,4.7),'wood_dark',b=.03,r=.02)
 for z in (1.0,3.9): box('LowerBeam',(0,-3.53,z),(8.5,.20,.16),'wood_dark',b=.03,r=.02)
part('lower_shell',lower_shell)
part('lower_slab',lambda:box('LowerSlab',(.2,0,5.2),(9.7,7.5,.2),'wood_edge',b=.045,r=.02))
def middle_shell():
 frustum('Middle',(-.25,0),(7.0,5.9),(6.86,5.78),5.4,4.9,'plaster',b=.095)
 for x in (-3.35,2.85): box('MiddleCorner',(x,-2.98,5.45),(.20,.22,4.7),'wood_dark',b=.03,r=.02)
 box('MiddleBeam',(0,-2.99,8.9),(6.5,.18,.16),'wood_dark',b=.03,r=.02)
part('middle_shell',middle_shell)
part('middle_slab',lambda:box('MiddleSlab',(-.25,0,10.1),(7.5,6.4,.2),'wood_edge',b=.045,r=.02))
def upper_shell():
 frustum('Upper',(.25,0),(5.0,4.5),(4.85,4.37),10.3,3.1,'plaster',b=.095)
 for x in (-2.05,2.55): box('UpperCorner',(x,-2.28,10.35),(.18,.2,2.95),'wood_dark',b=.03,r=.02)
 box('UpperBeam',(.25,-2.29,13.1),(4.6,.18,.16),'wood_dark',b=.03,r=.02)
part('upper_shell',upper_shell)
part('upper_slab',lambda:box('UpperSlab',(.25,0,13.4),(5.6,5.1,.2),'wood_edge',b=.045,r=.02))
part('roof_lower',lambda:(gable_roof('RoofLower',(.2,0),11.2,8.9,5.45,1.55,'ochre',.06),roof_tile_strips('TileLower',(.2,0),11.2,8.9,5.45,1.55,'wood_dark',8)))
part('roof_middle',lambda:(gable_roof('RoofMiddle',(-.25,0),8.8,7.4,10.35,1.25,'ochre',.06),roof_tile_strips('TileMiddle',(-.25,0),8.8,7.4,10.35,1.25,'wood_dark',7)))
part('roof_upper',lambda:(gable_roof('RoofUpper',(.25,0),6.0,5.5,13.6,.85,'slate',.075),roof_tile_strips('TileUpper',(.25,0),6.0,5.5,13.6,.85,'wood_dark',5)))
part('roof_ridge',lambda:box('Ridge',(.25,0,13.95),(5.45,.18,.18),'wood_dark',b=.03,r=.02))
# quoin blocks as separate relief component, four visible corner stones
for key,z,w,d,h in [('lower_quoin',.4,9.2,7.0,4.7),('middle_quoin',5.5,7.0,5.9,4.7),('upper_quoin',10.4,5.0,4.5,2.9)]:
 def q(key=key,z=z,w=w,d=d,h=h):
  for x in (-w/2+.08,w/2-.08):
   for y in (-d/2-.12,d/2+.12): box('Quoin',(x,y,z),(.22,.24,h*.8),'stone',b=.03,r=.02)
 part(key,q)
# opening helpers

def ring(pre,w,h,c='wood_edge'):
 box(pre+'L',(-w/2,0,0),(.16,.22,h),c,b=.025,r=.02);box(pre+'R',(w/2,0,0),(.16,.22,h),c,b=.025,r=.02);box(pre+'T',(0,0,h-.16),(w,.22,.16),c,b=.025,r=.02)
def win_part(key,w,h,glass):
 def f():
  ring('Frame',w,h,'wood_dark');box('Glass',(0,-.015,0),(w-.18,.04,h-.18),glass,'SEA_Gloss',b=.015,r=.02);box('Mullion',(0,-.05,0),(.07,.09,h-.2),'slate',b=.01,r=.02)
 part(key,f)
win_part('window_large',2.6,2.6,'petrol');win_part('window_small',1.6,1.25,'sage_gray');win_part('window_upper',2.5,1.65,'deepblue')
def door():
 ring('Door',2.0,3.1,'wood_dark');box('LeafL',(-.43,-.03,0),(.82,.08,2.94),'jade',b=.025,r=.02);box('LeafR',(.43,-.03,0),(.82,.08,2.94),'jade',b=.025,r=.02)
part('door',door)
def shutter():
 ring('Shutter',1.9,2.6,'wood_edge');box('Panel',(0,-.03,0),(1.7,.08,2.4),'sage',b=.025,r=.02)
 for z in (.5,1,1.5,2):box('Slat',(0,-.1,z),(1.45,.05,.08),'jade',b=.01,r=.02)
part('shutter',shutter)
def balcony():
 box('Deck',(0,0,0),(1.55,4.6,.2),'wood_mid',b=.045,r=.02);box('Rail',(0,-2.3,1.0),(.1,.1,1.0),'wood_dark',b=.02,r=.02)
 for y in (-1.8,-.9,0,.9,1.8):box('Post',(.65,y,0),(.12,.12,1.0),'steel','SEA_Metal',b=.02,r=.03)
part('balcony_lower',balcony);part('balcony_middle',balcony)
def rail():
 for x in (-2,-1,0,1,2):box('Post',(x,0,0),(.12,.12,.9),'steel','SEA_Metal',b=.02,r=.03)
 box('Top',(0,0,.9),(4.5,.12,.12),'silver','SEA_Metal',b=.02,r=.03)
part('balcony_rail',rail)
def awning():box('Awning',(0,0,0),(3.4,2.4,.12),'wood_mid',b=.03,r=.03,rot=(.12,0,0))
part('awning',awning)
