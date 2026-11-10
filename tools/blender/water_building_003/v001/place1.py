exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())
import math
g=.006
put('door_main',(-0.4,-3.5-.12-g,.3+g))
put('window_f1',(3.1,-3.5-.1-g,2.1))
put('window_f1',(-3.2,-3.5-.1-g,2.1),)
put('window_f2',(-.9,-2.8-.1-g,7.6))
put('window_tower',(.4,-2.2-.1-g,11.5))
put('shutter_door',(2.4+.1+g,.5,6.9),rot=(0,0,-math.pi/2))
put('balcony',(2.4+.775+g,0,6.7+g))
put('tower_ledge',(.4,-2.2-.45-g,10.95))
put('roof_rail',(.4,-2.7,13.7))
put('step_stones',(-.4,-3.5-.6-.02,.3+g))
print(len(instances))
