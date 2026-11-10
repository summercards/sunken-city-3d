exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())
random.seed(3003)
G=.006
F1X=.25; F2X=-.3; TX=.4
part('deck', lambda: box('Foundation',(-0.4,0,0),(16.6,11.0,.3),'stone',b=.075))
part('wall_f1', lambda: box('WallF1',(F1X,0,.3+G),(9.0,7.0,4.894),'plaster',b=.095,r=.015))
part('slab_f2', lambda: box('SlabF2',(F1X,0,5.2+G),(9.6,7.6,.194),'sage_gray',b=.045,r=.02))
part('wall_f2', lambda: box('WallF2',(F2X,0,5.4+2*G),(5.4,5.6,4.18),'plaster',b=.095,r=.015))
part('slab_f3', lambda: box('SlabF3',(F2X,0,9.6+G),(6.0,6.2,.194),'sage_gray',b=.045,r=.02))
part('wall_tower', lambda: box('WallTower',(TX,0,9.8+2*G),(4.7,4.4,3.58),'plaster',b=.095,r=.015))
part('roof_top', lambda: box('RoofTop',(TX,0,13.4+3*G),(6.4,6.0,.28),'slate',b=.075,r=.03))
# tile skirt roofs (frusta), terracotta
part('roof_low', lambda: frustum('RoofLow',(F1X,0),(11.6,9.4),(9.5,7.5),5.4+2*G,1.3,'ochre',b=.06,r=.03))
part('roof_mid', lambda: frustum('RoofMid',(F2X,0),(7.8,7.8),(5.7,5.9),9.8+2*G,1.2,'ochre',b=.06,r=.03))
for k in ['deck','wall_f1','slab_f2','wall_f2','slab_f3','wall_tower','roof_top','roof_low','roof_mid']:
    put(k)
print(len(instances), sum(e['triangles'] for e in catalog))
