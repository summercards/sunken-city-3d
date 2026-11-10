exec(open('D:/projects/sea/tools/blender/water_building_003/v001/lib.py',encoding='utf-8').read())

def ring(pre, w, h, t=.14, d=.2, c='wood_edge'):
    box(pre+'L', (-w/2+t/2, d/2, 0), (t, d, h), c, b=.03, r=.02)
    box(pre+'R', (w/2-t/2, d/2, 0), (t, d, h), c, b=.03, r=.02)
    box(pre+'B', (0, d/2, 0), (w-2*t+.0, d, t), c, b=.03, r=.02)
    box(pre+'T', (0, d/2, h-t), (w, d, t), c, b=.03, r=.02)

def door():
    ring('DoorFrame', 2.2, 3.4, .16, .24, 'wood_dark')
    for s in (-1, 1):
        box('DoorLeaf', (s*.46, .12, .16), (.87, .1, 3.07), 'jade', 'SEA_Matte', b=.03, r=.025)
    box('DoorBar', (0, .02, 1.2), (1.9, .05, .1), 'darkwood', b=.01, r=.02)
part('door_main', door)

def win(w, h, glass):
    def f():
        ring('WinFrame', w, h, .12, .2, 'slate')
        box('Pane', (0, .09, .12+.006), (w-.24-.012, .06, h-.24-.012), glass, 'SEA_Gloss', b=.015, r=.025)
        box('Mullion', (0, .06, .12), (.08, .1, h-.24), 'slate', b=.01, r=.025)
    return f
part('window_f1', win(2.3, 2.6, 'petrol'))
part('window_f2', win(1.5, 1.2, 'sage_gray'))
part('window_tower', win(2.4, 1.6, 'deepblue'))

def shut():
    ring('ShutFrame', 1.9, 2.5, .12, .2, 'wood_edge')
    box('ShutLeaf', (0, .1, .12+.006), (1.9-.24-.012, .08, 2.5-.24-.012), 'sage', b=.02, r=.025)
    for z in (.6, 1.1, 1.6): box('Slat', (0, .17, z), (1.5, .05, .08), 'jade', b=.01, r=.02)
part('shutter_door', shut)

def balc():
    box('BalDeck', (0, .0, 0), (1.5, 4.2, .2), 'wood_mid', b=.045, r=.02)
    box('BalRailTop', (.65, 0, 1.0), (.08, 4.2, .1), 'silver', 'SEA_Metal', b=.015, r=.03)
    box('BalRailMid', (.65, 0, .55), (.07, 4.2, .08), 'silver', 'SEA_Metal', b=.015, r=.03)
    for y in (-2.0, -1.0, 0, 1.0, 2.0): box('BalPost', (.65, y, .2), (.12, .12, .8), 'steel', 'SEA_Metal', b=.02, r=.04)
    box('BalRailEnd', (-.1, -2.04, 1.0), (1.4, .08, .1), 'silver', 'SEA_Metal', b=.015, r=.03)
    box('BalRailEnd2', (-.1, 2.04, 1.0), (1.4, .08, .1), 'silver', 'SEA_Metal', b=.015, r=.03)
part('balcony', balc)

def ledge():
    box('LedgeDeck', (0, 0, 0), (3.2, .9, .16), 'wood_mid', b=.04, r=.02)
    box('LedgeRail', (0, -.4, .16), (3.2, .07, .85), 'wood_dark', b=.015, r=.03)
part('tower_ledge', ledge)

def rail():
    for i, x in enumerate((-3.0, -1.5, 0, 1.5, 3.0)): box('RailPost', (x, 0, 0), (.14, .14, .9), 'steel', 'SEA_Metal', b=.02, r=.05)
    box('RailTop', (0, 0, .9), (6.2, .12, .12), 'silver', 'SEA_Metal', b=.02, r=.03)
    box('RailMid', (0, 0, .45), (6.2, .1, .08), 'silver', 'SEA_Metal', b=.02, r=.03)
part('roof_rail', rail)

def steps():
    for i in range(3):
        box('Step', (0, -.6*i, .0+.2*i*0), (4.2-.4*i, 1.0, .25), 'stone', b=.03, r=.02) if False else None
    box('StepA', (0, 0, 0), (4.2, 1.2, .22), 'stone', b=.04, r=.02)
    box('StepB', (0, -.0, .22+.004), (3.4, .9, .22), 'lightgray', b=.04, r=.02)
part('step_stones', steps)
print(len(instances), sum(e['triangles'] for e in catalog))
