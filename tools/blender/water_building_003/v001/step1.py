exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())
random.seed(3003)
F1X=.25; F2X=-.3; TX=.4
part('deck', lambda: box('Foundation',(1.0,0,0),(12.6,9.6,.3),'stone',b=.075,r=.015))
part('wall_f1', lambda: box('WallF1',(F1X,0,.3),(9.0,7.0,5.0),'plaster',b=.095,r=.015))
part('slab_f2', lambda: box('SlabF2',(F1X,0,5.2),(9.6,7.6,.2),'sage_gray',b=.045,r=.02))
part('wall_f2', lambda: box('WallF2',(F2X,0,5.4),(5.4,5.6,4.2),'plaster',b=.095,r=.015))
part('slab_f3', lambda: box('SlabF3',(F2X,0,9.6),(6.0,6.2,.2),'sage_gray',b=.045,r=.02))
part('wall_tower', lambda: box('WallTower',(TX,0,9.8),(4.7,4.4,3.6),'plaster',b=.095,r=.015))
part('roof_top', lambda: box('RoofTop',(TX,0,13.4),(6.4,6.0,.3),'slate',b=.075,r=.03))
for k,p in [('deck',(0,0,0)),('wall_f1',(0,0,0)),('slab_f2',(0,0,0)),('wall_f2',(0,0,0)),('slab_f3',(0,0,0)),('wall_tower',(0,0,0)),('roof_top',(0,0,0))]:
    put(k,p)
print(len(instances))
