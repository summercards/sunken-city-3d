# 家具母版以落地中心为原点，正面朝 -Y；实例摆位由装配脚本负责。


def _raf_ring(name, x, y, z, radius, wire, col, mat='Matte', steps=32):
    points = [(x + radius * cos(2 * pi * i / steps), y,
               z + radius * sin(2 * pi * i / steps)) for i in range(steps + 1)]
    tube(name, points, wire, col, mat, taper=0)


def _raf_crate(name, x, y, z, w, d, h, col='woodlight'):
    box(f'{name} | carton', (x, y, z + h / 2), (w, d, h), col, b=.013)
    box(f'{name} | folded lid', (x, y, z + h - .012), (w + .004, d + .004, .024), 'sand', b=.006)
    box(f'{name} | sealing tape over lid', (x + .022, y, z + h + .002),
        (.040, d + .006, .005), 'honey', b=.002)
    box(f'{name} | folded tape end', (x + .022, y - d / 2 - .002, z + h - .032),
        (.040, .006, .064), 'honey', b=.002)
    lx, ly, lz = x - w * .24, y - d / 2 - .004, z + h * .36
    box(f'{name} | paper tag', (lx, ly, lz), (w * .23, .006, h * .20), 'paper', b=.003)
    for i, width in enumerate((.031, .024)):
        box(f'{name} | tag print {i + 1}', (lx - .003, ly - .004, lz + .007 - .013 * i),
            (width, .003, .004), 'mortar', b=.001)


def _raf_screw(name, x, y, z):
    oval(name, (x, y, z), (.008, .004, .008), 'steel', 'Metal')
    box(f'{name} | slot', (x, y - .004, z), (.010, .002, .002), 'slate', b=.001)


def _raf_arcade_controls(name, y, z, shell, knobs):
    box(f'{name} | pitched control panel', (0, y, z), (.384, .142, .035), shell,
        b=.012, rot=(.23, 0, 0))
    box(f'{name} | cushioned front lip', (0, y - .067, z - .013), (.395, .026, .027),
        'ink', b=.009)
    oval(f'{name} | joystick collar', (-.111, y, z + .021), (.029, .025, .007), 'ink')
    rod(f'{name} | joystick shaft', (-.111, y, z + .022), (-.103, y + .007, z + .067), .008, 'steel', 'Metal')
    oval(f'{name} | ball-top joystick', (-.103, y + .007, z + .073), (.020, .020, .020), knobs[0], 'Gloss')
    for i, (x, dy, col) in enumerate(((.019, -.010, knobs[0]), (.067, .009, knobs[1]),
                                     (.111, .026, knobs[2]), (.144, -.013, knobs[0]))):
        h = z + .020 + .233 * dy
        oval(f'{name} | button bezel {i + 1}', (x, y + dy, h), (.021, .020, .006), 'ink')
        oval(f'{name} | action button {i + 1}', (x, y + dy, h + .005), (.015, .014, .006), col, 'Gloss')


def _raf_crt_point(cx, cy, cz, w, h, tilt, x, z, lift=0):
    bulge = .025 - .010 * ((x / w) ** 2 + (z / h) ** 2) + lift
    return cx + x, cy - bulge * cos(tilt) - z * sin(tilt), cz - bulge * sin(tilt) + z * cos(tilt)


def _raf_crt_glass(name, cx, cy, cz, w, h, tilt, col):
    # 矩形玻璃的四角收圆，中心比边缘更鼓。
    grid = []
    for j in range(17):
        v = j / 8 - 1
        row = []
        for i in range(21):
            u = i / 10 - 1
            x = w * u * (1 - .125 * v ** 10)
            z = h * v * (1 - .144 * u ** 10)
            row.append(_raf_crt_point(cx, cy, cz, w, h, tilt, x, z))
        grid.append(row)
    sheet(name, grid, .028, col, 'Gloss')


def _raf_arcade_screen(name, y, z, trim, body, glass_col, game_col, tilt):
    box(f'{name} | CRT surround', (0, y + .006, z), (.371, .046, .276), trim,
        b=.025, rot=(tilt, 0, 0))
    box(f'{name} | recessed black bezel', (0, y - .015, z), (.322, .027, .221), body,
        b=.023, rot=(tilt, 0, 0))
    screen = (0, y - .028, z, .143, .094, tilt)
    _raf_crt_glass(f'{name} | convex picture glass', *screen, glass_col)
    for i, (x, v) in enumerate(((-.081, .025), (-.054, .038), (-.027, .028), (.037, .043),
                               (.064, .031), (.085, .045), (.019, -.029))):
        box(f'{name} | screen pixel {i + 1}', _raf_crt_point(*screen, x, v, .016),
            (.016, .006, .009 if i != 6 else .013), game_col, b=.001, rot=(tilt, 0, 0))
    box(f'{name} | player paddle', _raf_crt_point(*screen, -.021, -.042, .016),
        (.046, .006, .008), 'warmwhite', b=.002, rot=(tilt, 0, 0))


def _raf_arcades():
    part('arcade_blue')
    # YZ 轮廓由分段斜背壳、前踢脚与突出摇杆台共同构成；侧边图案随轮廓收分。
    profile('Tide Run | cabinet shell', [(-.214, .024), (.214, .024), (.222, .691), (.198, 1.018),
            (.178, 1.257), (.117, 1.300), (-.137, 1.300), (-.202, 1.249), (-.218, .705)],
            .391, .047, 'blue', b=.021)
    box('Tide Run | inset kick plinth', (0, .041, .037), (.405, .395, .074), 'navy', b=.013)
    for side in (-1, 1):
        x = side * .214
        tube(f'Tide Run | side {side} wraparound edge trim', [(x, -.155, .080), (x, -.155, .675),
             (x, -.172, .739), (x * .97, -.120, 1.078), (x * .94, -.155, 1.205),
             (x * .94, -.161, 1.254), (x * .89, -.114, 1.293)], .008, 'bluelight')
        tube(f'Tide Run | side {side} wave stripe', [(x, -.114, .169), (x, -.052, .257),
             (x, .022, .354), (x, .108, .435), (x, .199, .491)], .014, 'turquoise', taper=0)
        tube(f'Tide Run | side {side} warm pinstripe', [(x, -.103, .105), (x, -.033, .199),
             (x, .046, .291), (x, .119, .360), (x, .209, .418)], .007, 'gold', taper=0)
    profile('Tide Run | lower access door', [(-.159, .100), (.158, .100), (.170, .524),
            (.146, .598), (-.146, .598), (-.170, .524)], .037, -.150, 'darkblue', b=.014)
    box('Tide Run | coin mech face', (.068, -.177, .478), (.086, .026, .140), 'darksteel', b=.010)
    box('Tide Run | brass coin throat', (.068, -.192, .515), (.044, .009, .015), 'brass', b=.003)
    box('Tide Run | coin slit', (.068, -.198, .515), (.029, .004, .004), 'ink', b=.001)
    box('Tide Run | return flap', (.068, -.194, .441), (.050, .014, .032), 'navy', b=.005)
    for i in range(5):
        box(f'Tide Run | speaker baffle slot {i + 1}', (-.094, -.170, .342 + .025 * i),
            (.069, .010, .009), 'ink', b=.003)
    box('Tide Run | monitor backing', (0, -.121, .922), (.403, .127, .338), 'navy', b=.028,
        rot=(.19, 0, 0))
    _raf_arcade_screen('Tide Run', -.180, .919, 'bluelight', 'ink', 'screenblue', 'cyan', .19)
    _raf_arcade_controls('Tide Run', -.165, .709, 'blue', ('coral', 'amber', 'mintlight'))
    profile('Tide Run | flared marquee hood', [(-.226, 1.132), (.226, 1.132), (.226, 1.265),
            (.193, 1.326), (-.180, 1.326), (-.226, 1.289)], .143, -.132, 'navy', b=.019)
    profile('Tide Run | painted marquee lens', [(-.200, 1.151), (.200, 1.151), (.200, 1.262),
            (.179, 1.300), (-.174, 1.300), (-.200, 1.277)], .014, -.209, 'turquoise', b=.007)
    tube('Tide Run | marquee surf line', [(-.183, -.219, 1.176), (-.145, -.219, 1.173),
         (-.110, -.219, 1.181), (-.080, -.219, 1.191), (-.045, -.219, 1.186),
         (0, -.219, 1.176), (.043, -.219, 1.174), (.088, -.219, 1.185), (.157, -.219, 1.180)],
         .005, 'warmwhite', taper=0)
    mark('Tide Run | marquee wordmark', 'TIDE RUN', (0, -.220, 1.235), .030, 'warmwhite')

    part('arcade_yellow')
    profile('Sun Catch | tapered cabinet body', [(-.202, .025), (.202, .025), (.218, .138),
            (.209, .580), (.178, .746), (.163, 1.103), (.188, 1.195), (.152, 1.276),
            (-.152, 1.276), (-.188, 1.195), (-.163, 1.103), (-.178, .746), (-.209, .580),
            (-.218, .138)], .358, .061, 'yellow', b=.028)
    box('Sun Catch | amber toe plinth', (0, .032, .035), (.398, .409, .070), 'amber', b=.015)
    profile('Sun Catch | rounded lower access panel', [(-.157, .094), (.157, .094), (.199, .145),
            (.191, .493), (.158, .594), (-.158, .594), (-.191, .493), (-.199, .145)],
            .075, -.119, 'gold', b=.021)
    oval('Sun Catch | circular aqua splash medallion', (-.024, -.158, .320), (.115, .008, .115), 'turquoise')
    _raf_ring('Sun Catch | round painted outline', -.024, -.167, .320, .108, .005, 'cream')
    oval('Sun Catch | sun disk', (-.044, -.170, .350), (.042, .003, .042), 'yellow')
    for i in range(7):
        a = .20 + pi * i / 6
        rod(f'Sun Catch | sunray {i + 1}', (-.044 + .053 * cos(a), -.173, .350 + .053 * sin(a)),
            (-.044 + .064 * cos(a), -.173, .350 + .064 * sin(a)), .004, 'yellow')
    for i in range(2):
        tube(f'Sun Catch | sea foam line {i + 1}', [(x, -.169, .301 - .027 * i + .007 * sin(41 * x + i))
             for x in [-.102 + j * .015 for j in range(11)]], .004, 'mintlight', taper=0)
    box('Sun Catch | coin lock plate', (.140, -.162, .411), (.046, .015, .068), 'amber', b=.008)
    box('Sun Catch | coin lock and return', (.140, -.172, .418), (.026, .009, .041), 'ink', b=.005)
    box('Sun Catch | scooped CRT housing', (0, -.094, .906), (.384, .147, .310), 'amber', b=.033,
        rot=(.26, 0, 0))
    _raf_arcade_screen('Sun Catch', -.158, .906, 'yellow', 'olive', 'screengreen', 'lime', .26)
    _raf_arcade_controls('Sun Catch', -.155, .698, 'honey', ('coral', 'mintlight', 'cream'))
    profile('Sun Catch | chamfered gold crown', [(-.197, 1.111), (.197, 1.111), (.220, 1.208),
            (.168, 1.295), (-.168, 1.295), (-.220, 1.208)], .127, -.117, 'amber', b=.020)
    profile('Sun Catch | scalloped marquee inset', [(-.172, 1.132), (.172, 1.132), (.191, 1.202),
            (.150, 1.267), (-.150, 1.267), (-.191, 1.202)], .016, -.185, 'teallight', b=.010)
    profile('Sun Catch | marquee pennant left', [(-.168, 1.175), (-.130, 1.244), (-.080, 1.187)],
            .007, -.196, 'coral', b=.003)
    profile('Sun Catch | marquee pennant right', [(.089, 1.183), (.151, 1.243), (.175, 1.181)],
            .007, -.196, 'yellow', b=.003)
    mark('Sun Catch | marquee wordmark', 'SUN', (0, -.201, 1.207), .038, 'warmwhite')


def _raf_counter_and_bench():
    part('token_counter')
    box('Token counter | inset wood toe kick', (0, .014, .044), (.814, .380, .088), 'wooddark', b=.015)
    box('Token counter | cabinet body', (0, .020, .326), (.851, .393, .555), 'wood', b=.016)
    for x in (-.394, .394):
        box(f'Token counter | corner stile {x:+.2f}', (x, -.185, .333), (.069, .047, .526), 'woodlight', b=.010)
    for i in range(8):
        x = -.307 + .088 * i
        box(f'Token counter | inset board {i + 1}', (x, -.188, .327), (.079, .027, .443),
            ('wooddark', 'wood', 'woodlight', 'wood')[i % 4], b=.006)
    box('Token counter | lower apron', (0, -.201, .122), (.745, .033, .063), 'wooddark', b=.008)
    box('Token counter | eased oak countertop', (0, 0, .608), (.900, .469, .063), 'woodlight', b=.021)
    box('Token counter | warm edge band', (0, -.221, .582), (.865, .030, .020), 'honey', b=.007)
    box('Token counter | token sign backing', (0, -.208, .410), (.314, .030, .122), 'wooddark', b=.012)
    box('Token counter | amber hand-lettered plaque', (0, -.227, .410), (.290, .017, .101), 'honey', b=.009)
    mark('Token counter | TOKENS letters', 'TOKENS', (0, -.238, .413), .041, 'ink')
    for x in (-.125, .125):
        _raf_screw('Token counter | plaque pin', x, -.238, .410)
    box('Token counter | glass tray oak base', (-.177, -.064, .654), (.415, .262, .027), 'wooddark', b=.011)
    box('Token counter | velvet tray liner', (-.177, -.064, .670), (.375, .221, .008), 'teal', b=.004)
    for i, (x, y, n) in enumerate(((-.311, -.090, 2), (-.258, -.127, 1), (-.239, -.017, 3),
                                    (-.167, -.115, 2), (-.104, -.005, 1), (-.080, -.131, 3), (-.023, -.056, 2))):
        for j in range(n):
            oval(f'Token counter | token stack {i + 1} coin {j + 1}', (x + .002 * j, y, .676 + .006 * j),
                 (.021, .021, .004), 'gold' if j == n - 1 else 'brass', 'Metal')
        oval(f'Token counter | token stamp {i + 1}', (x + .002 * (n - 1), y, .681 + .006 * (n - 1)),
             (.010, .010, .002), 'honey', 'Metal')
    for x in (-.375, .021):
        box('Token counter | clear tray side', (x, -.064, .698), (.011, .243, .060), 'glass', b=.004, mat='Gloss')
    for y in (-.188, .060):
        box('Token counter | clear tray rim', (-.177, y, .692), (.396, .011, .049), 'glass', b=.004, mat='Gloss')
    box('Token counter | cash drawer', (.251, .084, .661), (.207, .177, .044), 'slate', b=.010)
    box('Token counter | raised cash register keypad deck', (.251, .085, .696), (.195, .158, .050),
        'cream', b=.013, rot=(.14, 0, 0))
    for row in range(2):
        for c in range(4):
            box(f'Token counter | register key {row + 1}.{c + 1}', (.197 + .035 * c, .043 + .032 * row,
                .721 + .004 * row), (.027, .024, .010), 'slate' if c < 3 else 'coral', b=.003)
    box('Token counter | green register display', (.250, .140, .728), (.111, .022, .010), 'screengreen',
        b=.004, mat='Gloss', rot=(.14, 0, 0))
    box('Token counter | loose receipt', (.210, -.094, .645), (.057, .083, .010), 'paper', b=.003,
        rot=(0, 0, -.17))

    part('repair_bench')
    for x in (-.319, .319):
        for y in (-.167, .158):
            rod(f'Repair bench | splayed leg {x:+.2f} {y:+.2f}', (x * 1.05, y * 1.11, .031),
                (x, y, .712), .029, 'wooddark')
            box('Repair bench | rubber foot', (x * 1.05, y * 1.11, .019), (.061, .057, .038), 'slate', b=.009)
    box('Repair bench | rear stretcher', (0, .148, .196), (.650, .052, .067), 'wood', b=.009)
    box('Repair bench | green apron', (0, -.172, .659), (.671, .047, .114), 'mintdark', b=.011)
    box('Repair bench | butcher block top', (0, 0, .737), (.742, .450, .066), 'woodlight', b=.018)
    box('Repair bench | parts drawer', (-.169, -.201, .650), (.272, .034, .090), 'teal', b=.010)
    tube('Repair bench | drawer pull', [(-.209, -.218, .648), (-.211, -.238, .648), (-.202, -.246, .648),
         (-.137, -.246, .648), (-.129, -.238, .648), (-.130, -.218, .648)], .008, 'brass', 'Metal')
    box('Repair bench | CRT swivel base', (-.080, .068, .794), (.271, .194, .050), 'beige', b=.014)
    profile('Repair bench | CRT tapered shell', [(-.264, .818), (.098, .818), (.098, 1.048),
            (.055, 1.118), (-.221, 1.118), (-.264, 1.048)], .210, .096, 'cream', b=.022)
    box('Repair bench | monitor front bezel', (-.083, -.025, .968), (.357, .075, .285), 'beige', b=.025,
        rot=(.14, 0, 0))
    box('Repair bench | monitor recessed gasket', (-.092, -.062, .978), (.283, .025, .223), 'slate',
        b=.024, rot=(.14, 0, 0))
    oval('Repair bench | convex teal CRT glass', (-.092, -.080, .978), (.126, .024, .096), 'screenblue',
         'Gloss', rot=(.14, 0, 0))
    for i, width in enumerate((.114, .073, .095)):
        z = 1.012 - .025 * i
        box(f'Repair bench | terminal text line {i + 1}', (-.157 + width / 2, -.106 - (z - .978) * .14, z),
            (width, .005, .006), 'mintlight', b=.001, rot=(.14, 0, 0))
    oval('Repair bench | monitor power lamp', (.044, -.065, .864), (.008, .005, .008), 'lime', 'Emission')
    for i in range(4):
        box(f'Repair bench | CRT top air slot {i + 1}', (-.151 + .042 * i, .128, 1.119),
            (.018, .062, .004), 'wooddark', b=.002)
    box('Repair bench | keyboard angled wedge', (-.076, -.148, .789), (.286, .115, .029),
        'beige', b=.010, rot=(.13, 0, 0))
    for r in range(3):
        for c in range(8):
            if r == 0 and 1 < c < 6:
                continue
            box(f'Repair bench | keyboard key {r + 1}.{c + 1}', (-.194 + .034 * c, -.182 + .026 * r,
                 .803 + .004 * r), (.028, .020, .009), 'sand' if r < 2 else 'cream', b=.003)
    box('Repair bench | space bar', (-.075, -.182, .803), (.130, .020, .009), 'cream', b=.003)
    box('Repair bench | green solder mat', (.237, -.030, .773), (.218, .276, .010), 'olivecloth', b=.010)
    box('Repair bench | solder station', (.263, .102, .816), (.129, .116, .082), 'slate', b=.010)
    box('Repair bench | station faceplate', (.263, .040, .818), (.109, .014, .061), 'steel', b=.006)
    oval('Repair bench | temperature dial', (.288, .029, .817), (.020, .011, .020), 'ink')
    oval('Repair bench | station indicator', (.231, .028, .822), (.009, .005, .009), 'amber', 'Emission')
    box('Repair bench | iron rest', (.260, -.083, .787), (.102, .077, .032), 'darksteel', b=.009)
    rod('Repair bench | iron insulated handle', (.186, -.139, .819), (.247, -.089, .819), .016, 'coral')
    rod('Repair bench | soldering iron tip', (.241, -.094, .819), (.294, -.054, .815), .007, 'steel', 'Metal')
    tube('Repair bench | loose iron lead', [(.216, .035, .801), (.178, -.013, .782), (.159, -.075, .781),
         (.140, -.133, .781), (.149, -.162, .783), (.176, -.157, .804), (.186, -.139, .819)], .004, 'ink')


def _raf_utility_furniture():
    part('tool_board')
    box('Tool board | deep mounting frame', (0, .015, .269), (.940, .092, .538), 'wooddark', b=.016)
    box('Tool board | inset slate peg panel', (0, -.037, .270), (.871, .032, .465), 'slate', b=.013)
    for r in range(4):
        for c in range(10):
            oval(f'Tool board | dark peg recess {r + 1}.{c + 1}', (-.387 + .086 * c, -.054, .120 + .098 * r),
                 (.007, .003, .007), 'ink')
    for x in (-.412, .412):
        for z in (.086, .456):
            _raf_screw('Tool board | board screw', x, -.057, z)
    for i, (x, top, col) in enumerate(((-.348, .399, 'amber'), (-.252, .365, 'coral'), (-.152, .421, 'woodlight'))):
        tube(f'Tool board | driver {i + 1} hook', [(x - .018, -.050, top), (x - .018, -.087, top),
             (x + .018, -.087, top), (x + .018, -.050, top)], .005, 'steel', 'Metal')
        rod(f'Tool board | driver {i + 1} steel tip', (x, -.087, top - .016),
            (x, -.087, top - .145), .007, 'steel', 'Metal')
        oval(f'Tool board | driver {i + 1} handle', (x, -.088, top - .180), (.019, .018, .046), col)
        oval(f'Tool board | driver {i + 1} grip ring', (x, -.088, top - .157), (.020, .019, .006), 'wooddark')
    for i, (x, z) in enumerate(((-.045, .349), (.040, .386), (.122, .327))):
        _raf_ring(f'Tool board | spanner {i + 1} ring end', x, -.081, z - .128, .018, .006, 'steel', 'Metal', 16)
        rod(f'Tool board | spanner {i + 1} shank', (x, -.081, z - .109), (x, -.081, z - .010), .009, 'steel', 'Metal')
        tube(f'Tool board | spanner {i + 1} open jaws', [(x + .024 * cos(pi + pi * j / 12), -.082,
             z + .024 * sin(pi + pi * j / 12)) for j in range(13)], .007, 'steel', 'Metal', taper=0)
    tube('Tool board | pliers jaw and grips', [(.210, -.091, .422), (.224, -.091, .381), (.243, -.091, .348),
         (.266, -.091, .314), (.278, -.091, .253)], .009, 'steel', 'Metal')
    tube('Tool board | pliers opposing jaw', [(.266, -.096, .420), (.250, -.096, .377), (.235, -.096, .344),
         (.214, -.096, .310), (.202, -.096, .251)], .009, 'steel', 'Metal')
    for x, vx in ((.202, .220), (.278, .262)):
        rod('Tool board | insulated pliers grip', (x, -.093, .250), (vx, -.093, .317), .015, 'coral')
    _raf_screw('Tool board | pliers pivot pin', .239, -.103, .353)
    box('Tool board | short parts ledge', (.284, -.068, .096), (.269, .085, .026), 'woodlight', b=.008)
    box('Tool board | lidded screws tin', (.333, -.064, .132), (.108, .069, .045), 'mintdark', b=.008)
    box('Tool board | tin lid', (.333, -.064, .157), (.115, .075, .014), 'mint', b=.005)

    part('utility_rack')
    for x in (-.324, .324):
        for y in (-.121, .121):
            box('Utility rack | rounded steel upright', (x, y, .720), (.040, .047, 1.440), 'slate', b=.011)
            box('Utility rack | rubber shoe', (x, y, .019), (.052, .056, .038), 'darksteel', b=.008)
    for i, z in enumerate((.108, .471, .814, 1.161)):
        box(f'Utility rack | shelf {i + 1} pine deck', (0, 0, z), (.648, .275, .040), 'woodlight', b=.011)
        box(f'Utility rack | shelf {i + 1} front angle', (0, -.139, z - .009), (.670, .028, .049), 'slate', b=.010)
    rod('Utility rack | rear diagonal brace', (-.312, .128, .178), (.312, .128, 1.382), .011, 'darksteel', 'Metal')
    _raf_crate('Utility rack | bottom supply carton', -.166, -.008, .128, .263, .234, .269)
    _raf_crate('Utility rack | bottom spare carton', .151, .012, .128, .260, .216, .215, 'sand')
    _raf_crate('Utility rack | upper stock carton', .144, .021, .834, .253, .214, .224)
    _raf_crate('Utility rack | top stock carton', -.135, .001, 1.181, .306, .223, .228, 'sand')
    for i, (x, z, w, h, color) in enumerate(((-.156, .491, .258, .174, 'blue'), (.151, .491, .235, .148, 'teal'),
                                             (-.162, .834, .227, .161, 'mintdark'), (.173, 1.181, .186, .147, 'wood'))):
        box(f'Utility rack | bin {i + 1} body', (x, -.006, z + h / 2), (w, .221, h), color, b=.012)
        box(f'Utility rack | bin {i + 1} lid rim', (x, -.006, z + h - .006), (w + .012, .233, .026), color, b=.007)
        box(f'Utility rack | bin {i + 1} inset pull', (x, -.120, z + h * .68), (.069, .012, .026), 'slate', b=.005)

    part('heater')
    for x in (-.088, .088):
        for y in (-.056, .056):
            box('Water heater | formed steel foot', (x, y, .077), (.045, .052, .154), 'darksteel', b=.010)
    # 圆罐截面由多道等角环围合，罐肩比中段收得更紧。
    rings = ((.139, .050), (.153, .101), (.177, .129), (.213, .142), (.337, .145), (.576, .145),
             (.798, .145), (.907, .142), (.952, .130), (.984, .102), (.999, .055))
    sheet('Water heater | rolled enamel pressure vessel', [[(r * cos(2 * pi * i / 32),
          r * sin(2 * pi * i / 32), z) for i in range(33)] for z, r in rings], .010, 'beige')
    for z in (.139, .999):
        oval('Water heater | pressure vessel closure', (0, 0, z), (.059, .059, .014), 'beige')
    for i, z in enumerate((.220, .883)):
        tube(f'Water heater | rolled seam {i + 1}', [(.143 * cos(2 * pi * j / 32),
             .143 * sin(2 * pi * j / 32), z) for j in range(33)], .007, 'steel', 'Metal', taper=0)
    box('Water heater | access thermostat housing', (0, -.141, .345), (.129, .033, .138), 'cream', b=.012)
    oval('Water heater | thermostat knob', (0, -.167, .354), (.027, .013, .027), 'slate')
    oval('Water heater | pilot light', (.037, -.160, .316), (.007, .004, .007), 'amber', 'Emission')
    profile('Water heater | ink hazard triangle border', [(-.066, .525), (.066, .525), (0, .650)],
            .008, -.147, 'ink', b=.005)
    profile('Water heater | yellow hazard triangle', [(-.053, .536), (.053, .536), (0, .633)],
            .007, -.153, 'yellow', b=.003)
    profile('Water heater | electric hazard lightning bolt', [(-.015, .591), (.014, .612), (.009, .584),
            (.025, .584), (-.009, .548), (-.005, .574), (-.021, .574)], .004, -.158, 'ink', b=.001)
    tube('Water heater | upper copper supply with return bend', [(-.053, .023, .989), (-.053, .023, 1.121),
         (-.046, .023, 1.170), (-.021, .023, 1.207), (.018, .023, 1.225), (.079, .023, 1.225),
         (.118, .023, 1.205), (.145, .023, 1.161), (.151, .023, 1.111), (.151, .023, .977)],
         .019, 'copper', 'Metal', taper=0)
    tube('Water heater | vertical cold feed and bottom bend', [(.151, .023, .993), (.151, .023, .297),
         (.148, .023, .231), (.131, .023, .192), (.098, .023, .172), (.061, .023, .171)],
         .017, 'darksteel', 'Metal', taper=0)
    for x, z in ((-.053, 1.051), (-.053, 1.130), (.151, .978), (.151, .400)):
        box('Water heater | brass hex union', (x, .023, z), (.052, .048, .039), 'brass', b=.010, mat='Metal')
    rod('Water heater | shutoff valve stem', (-.053, .018, 1.101), (-.053, -.054, 1.101), .011, 'brass', 'Metal')
    _raf_ring('Water heater | coral valve handwheel', -.053, -.064, 1.101, .040, .007, 'coral')
    rod('Water heater | valve wheel spoke', (-.092, -.064, 1.101), (-.014, -.064, 1.101), .005, 'coral')
    rod('Water heater | valve wheel cross spoke', (-.053, -.064, 1.062), (-.053, -.064, 1.140), .005, 'coral')
    oval('Water heater | pressure gauge rear body', (.031, -.056, 1.125), (.032, .017, .032), 'darksteel', 'Metal')
    rod('Water heater | gauge stem', (.032, -.048, 1.106), (.032, -.048, .990), .009, 'brass', 'Metal')
    oval('Water heater | ivory pressure gauge face', (.031, -.070, 1.125), (.026, .006, .026), 'cream')
    rod('Water heater | pressure needle', (.031, -.077, 1.125), (.044, -.077, 1.139), .002, 'coral')

    part('shop_stool')
    for i in range(3):
        a = -pi / 2 + i * 2 * pi / 3
        x, y = cos(a), sin(a)
        rod(f'Shop stool | splayed timber leg {i + 1}', (.130 * x, .130 * y, .026),
            (.090 * x, .090 * y, .396), .021, 'wooddark')
        oval(f'Shop stool | rubber ferrule {i + 1}', (.130 * x, .130 * y, .021), (.025, .025, .021), 'slate')
    tube('Shop stool | circular footrest', [(.113 * cos(2 * pi * i / 30), .113 * sin(2 * pi * i / 30), .189)
         for i in range(31)], .012, 'darksteel', 'Metal', taper=0)
    oval('Shop stool | turned oak seat', (0, 0, .413), (.151, .151, .037), 'woodlight')
    tube('Shop stool | wrapped seat seam', [(.143 * cos(2 * pi * i / 32), .143 * sin(2 * pi * i / 32), .414)
         for i in range(33)], .005, 'honey', taper=0)

    part('shipping_crate')
    _raf_crate('Shipping crate', 0, 0, 0, .306, .262, .278)
    for i in range(2):
        x = .070 + .040 * i
        profile(f'Shipping crate | upright handling arrow {i + 1}', [(x - .006, .065), (x + .006, .065),
                (x + .006, .105), (x + .014, .105), (x, .124), (x - .014, .105), (x - .006, .105)],
                .004, -.134, 'wooddark', b=.001)


def _raf_blanket_point(u, v, lift=0):
    # U 从左侧垂沿经过床面到右侧垂沿，V 从床尾走向枕边。
    a = -pi / 2 + pi * u
    x = .369 * sin(a)
    y = -.694 + .952 * v + (.017 * sin(7 * pi * u + .40) + .009 * cos(13 * pi * u)) * (1 - v) ** 4
    z = .190 + .188 * max(0, cos(a)) ** .16
    z += (.008 * sin(9 * pi * u + 4 * v) + .004 * cos(15 * pi * u - 3 * v)) * (1 - .43 * v)
    z -= .048 * (1 - v) ** 10
    return x + .0025 * sin(13 * v + 2 * a) * sin(a) ** 4 + lift * sin(a), y, z + lift * cos(a)


def _raf_loft_furniture():
    part('loft_bed')
    for x in (-.296, .296):
        for y in (-.553, .555):
            box('Loft bed | solid ash foot', (x, y, .065), (.077, .101, .130), 'wooddark', b=.012)
    box('Loft bed | low rounded support frame', (0, 0, .148), (.685, 1.310, .126), 'wood', b=.021)
    box('Loft bed | thick upholstered mattress', (0, -.012, .267), (.686, 1.273, .174), 'bluelight', b=.049)
    for x in (-.320, .320):
        rod('Loft bed | mattress welt near head', (x, .232, .268), (x, .573, .268), .006, 'cream')
        box('Loft bed | headboard upright', (x, .635, .246), (.062, .076, .412), 'wooddark', b=.015)
    profile('Loft bed | curved ash headboard', [(-.336, .194), (.336, .194), (.346, .368), (.323, .429),
            (.271, .462), (.120, .478), (-.120, .478), (-.271, .462), (-.323, .429), (-.346, .368)],
            .069, .647, 'wood', b=.017)
    tube('Loft bed | raised headboard crest', [(-.310, .606, .395), (-.274, .606, .433), (-.200, .606, .452),
         (-.100, .606, .460), (.100, .606, .460), (.200, .606, .452), (.274, .606, .433),
         (.310, .606, .395)], .008, 'woodlight')
    for i, (x, y, z, w, d, ang, col) in enumerate(((-.144, .453, .379, .168, .132, -.18, 'cream'),
                                                  (.151, .493, .394, .147, .114, .14, 'beige'))):
        oval(f'Loft bed | pillow {i + 1} soft body', (x, y, z), (w, d, .054), col, rot=(.11, 0, ang))
        tube(f'Loft bed | pillow {i + 1} sewn welt', [(x + .96 * (w * cos(a) * cos(ang) - d * sin(a) * sin(ang)),
             y + .96 * (w * cos(a) * sin(ang) + d * sin(a) * cos(ang)), z + .108 * d * sin(a))
             for a in [2 * pi * j / 32 for j in range(33)]], .004, 'sand', taper=0)
    sheet('Loft bed | folded denim coverlet', [[_raf_blanket_point(i / 32, j / 22)
          for i in range(33)] for j in range(23)], .012, 'blue')
    for i, (v, w, col) in enumerate(((.095, .022, 'cream'), (.139, .015, 'gold'), (.210, .049, 'coral'),
                                     (.285, .015, 'cream'), (.459, .042, 'terracotta'), (.518, .016, 'gold'),
                                     (.611, .020, 'cream'), (.736, .042, 'coral'), (.806, .018, 'gold'))):
        sheet(f'Loft bed | woven coverlet stripe {i + 1}', [[_raf_blanket_point(k / 32, v + w * j / 3, .009)
              for k in range(33)] for j in range(4)], .003, col)
    for v, name in ((0, 'foot hem'), (1, 'fold at pillow edge')):
        tube(f'Loft bed | coverlet {name}', [_raf_blanket_point(i / 36, v, .007) for i in range(37)],
             .006, 'bluelight', taper=0)

    part('coffee_table')
    box('Loft coffee table | woven rug body', (0, 0, .008), (.762, .543, .016), 'terracotta', b=.014)
    box('Loft coffee table | inset rug field', (0, 0, .017), (.673, .451, .006), 'coral', b=.012)
    for y in (-.231, .231):
        box('Loft coffee table | rug border stripe', (0, y, .017), (.701, .014, .006), 'sand', b=.004)
    for x in (-.347, .347):
        box('Loft coffee table | rug selvedge', (x, 0, .017), (.017, .464, .006), 'sand', b=.004)
    for x in (-.198, .198):
        for y in (-.128, .128):
            rod(f'Loft coffee table | angled leg {x:+.2f} {y:+.2f}', (x * 1.09, y * 1.12, .019),
                (x, y, .279), .026, 'wooddark')
    box('Loft coffee table | low shelf', (0, .001, .113), (.412, .279, .031), 'wood', b=.012)
    box('Loft coffee table | rounded elm top', (0, 0, .292), (.530, .388, .056), 'woodlight', b=.025)
    box('Loft coffee table | notebook under table', (.072, -.038, .139), (.153, .096, .020), 'olivecloth',
        b=.006, rot=(0, 0, .19))
    oval('Loft coffee table | kettle flat foot', (-.094, .025, .327), (.074, .074, .007), 'slate')
    oval('Loft coffee table | enamel kettle belly', (-.094, .025, .390), (.086, .079, .070), 'cream', 'Gloss')
    oval('Loft coffee table | kettle fitted lid', (-.094, .025, .451), (.064, .060, .013), 'steel', 'Metal')
    oval('Loft coffee table | turned lid knob', (-.094, .025, .469), (.019, .019, .012), 'wooddark')
    tube('Loft coffee table | kettle curved spout', [(-.157, .007, .370), (-.181, .005, .382),
         (-.204, .000, .402), (-.217, -.007, .427), (-.226, -.016, .447)], .016, 'cream', 'Gloss', taper=.40)
    oval('Loft coffee table | kettle spout mouth', (-.226, -.016, .449), (.010, .011, .005), 'slate',
         rot=(0, -.38, 0))
    tube('Loft coffee table | kettle insulated side handle', [(-.025, .052, .426), (-.004, .066, .441),
         (.022, .065, .433), (.033, .058, .414), (.030, .051, .389), (.012, .043, .371),
         (-.020, .042, .365)], .011, 'wooddark', taper=0)
    for i, (x, y, col) in enumerate(((.134, -.072, 'mint'), (.153, .078, 'coral'))):
        oval(f'Loft coffee table | saucer {i + 1}', (x, y, .327), (.055, .053, .007), 'cream')
        rings = ((.335, .022), (.341, .028), (.356, .032), (.382, .037), (.387, .036))
        sheet(f'Loft coffee table | cup {i + 1} ceramic wall', [[(x + r * cos(2 * pi * j / 24),
               y + r * sin(2 * pi * j / 24), z) for j in range(25)] for z, r in rings], .005, col, 'Gloss')
        oval(f'Loft coffee table | cup {i + 1} tea surface', (x, y, .370), (.030, .030, .004), 'wooddark')
        _raf_ring(f'Loft coffee table | cup {i + 1} handle', x + .039, y, .359, .017, .005, col, steps=20)

    part('loft_shelf')
    for x in (-.316, .316):
        box('Loft shelf | rounded upright side panel', (x, .005, .610), (.058, .269, 1.220), 'wood', b=.014)
    for i in range(5):
        box(f'Loft shelf | tongue-and-groove back board {i + 1}', (-.239 + .1195 * i, .120, .597),
            (.115, .035, 1.151), 'wooddark' if i % 3 == 0 else 'wood', b=.007)
    for i, z in enumerate((.085, .355, .644, .923, 1.201)):
        box(f'Loft shelf | eased shelf board {i + 1}', (0, 0, z), (.641, .280, .038), 'woodlight', b=.012)
    _raf_crate('Loft shelf | blanket carton', -.106, .005, .104, .315, .211, .218, 'sand')
    box('Loft shelf | folded gray towel bottom', (.185, .003, .125), (.168, .195, .042), 'gray', b=.019)
    box('Loft shelf | folded blue towel top', (.185, .013, .162), (.160, .178, .038), 'bluelight', b=.015)
    for i, (x, w, h, col) in enumerate(((-.239, .043, .166, 'teal'), (-.180, .051, .207, 'coral'),
                                         (-.120, .049, .179, 'olivecloth'), (-.060, .046, .194, 'blue'))):
        box(f'Loft shelf | book {i + 1} binding', (x, -.016, .374 + h / 2), (w, .166, h), col, b=.007)
        box(f'Loft shelf | book {i + 1} top page block', (x, -.006, .374 + h - .003), (w - .012, .136, .008),
            'paper', b=.003)
        box(f'Loft shelf | book {i + 1} spine rule', (x, -.100, .374 + h * .20), (.026, .005, .009), 'sand', b=.002)
    box('Loft shelf | glazed blue tea tin', (.166, -.011, .457), (.181, .178, .166), 'teal', b=.020)
    box('Loft shelf | tea tin cap', (.166, -.011, .549), (.192, .187, .026), 'mint', b=.009)
    box('Loft shelf | tea tin label', (.166, -.104, .468), (.094, .008, .046), 'paper', b=.005)
    mark('Loft shelf | tea lettering', 'TEA', (.166, -.111, .469), .019, 'teal')
    for i, (x, w, h) in enumerate(((-.206, .127, .151), (-.048, .144, .117), (.155, .187, .169))):
        _raf_crate(f'Loft shelf | upper archive carton {i + 1}', x, .006, .663, w, .192, h)
    for i, (x, h, col) in enumerate(((-.198, .137, 'cream'), (-.065, .161, 'olive'), (.068, .114, 'aqua'))):
        oval(f'Loft shelf | pantry jar {i + 1}', (x, -.032, .942 + h * .47), (.051, .050, h * .48), col)
        oval(f'Loft shelf | pantry jar {i + 1} cork cap', (x, -.032, .942 + h * .93), (.036, .036, .014), 'honey')


def furniture():
    _raf_arcades()
    _raf_counter_and_bench()
    _raf_utility_furniture()
    _raf_loft_furniture()


def fixtures():
    part('vent_fan')
    box('Loft AC | thick rounded motor case', (0, .013, .165), (.327, .200, .330), 'beige', b=.023)
    box('Loft AC | inset cream face', (0, -.094, .166), (.309, .037, .303), 'cream', b=.019)
    oval('Loft AC | deep circular intake', (-.015, -.114, .171), (.129, .017, .129), 'ink')
    for i in range(5):
        a = 2 * pi * i / 5
        pts = [(-.015 + x * cos(a) - z * sin(a), .171 + x * sin(a) + z * cos(a))
               for x, z in ((.020, -.013), (.064, -.033), (.105, -.018), (.118, .001),
                            (.106, .026), (.078, .035), (.049, .023), (.018, .009))]
        profile(f'Loft AC | swept impeller blade {i + 1}', pts, .010, -.134, 'slate', b=.004)
    oval('Loft AC | rounded impeller hub', (-.015, -.145, .171), (.028, .013, .028), 'steel', 'Metal')
    for i in range(12):
        a = 2 * pi * i / 12
        pts = [(-.015 + r * cos(a + d), -.163 + .011 * (r / .131), .171 + r * sin(a + d))
               for r, d in ((.023, .16), (.051, .13), (.082, .07), (.106, .025), (.131, 0))]
        tube(f'Loft AC | radial safety grille spoke {i + 1}', pts, .0045, 'beige', taper=0)
    for i, r in enumerate((.050, .084, .113, .132)):
        _raf_ring(f'Loft AC | concentric guard wire {i + 1}', -.015, -.163 + .011 * (r / .131), .171, r,
                  .006 if i == 3 else .004, 'cream')
    oval('Loft AC | grille center cap', (-.015, -.164, .171), (.021, .010, .021), 'beige')
    for x in (-.131, .132):
        for z in (.046, .288):
            _raf_screw('Loft AC | grille fastener', x, -.116, z)
    for i in range(4):
        box(f'Loft AC | compressor side seam {i + 1}', (.158, .017, .089 + .034 * i),
            (.012, .087, .011), 'mortar', b=.004)

    part('loft_curtain')
    rod('Loft curtain | taut hem rod', (-.326, .018, .463), (.326, .018, .463), .011, 'wooddark')
    for x in (-.325, .325):
        oval('Loft curtain | rod end cap', (x, .018, .463), (.015, .017, .016), 'woodlight')
    # 上口绷直，下摆偏向一侧；振幅沿高度渐增，避免等距机械波纹。
    def curtain_point(u, v):
        x = -.301 + .595 * u + v * (.018 + .012 * sin(2 * pi * u))
        y = .014 - .015 * v + (.007 + .035 * v ** .8) * sin(8 * pi * u + .87 * v)
        y += .010 * v * sin(15 * pi * u - 1.4 * v)
        hem = .042 + .135 * u ** 1.5 - .036 * sin(pi * u) + .014 * sin(7 * pi * u + .45)
        return x, y, .454 * (1 - v) + hem * v
    sheet('Loft curtain | olive cotton asymmetric curtain', [[curtain_point(i / 32, j / 14)
          for i in range(33)] for j in range(15)], .012, 'olivecloth')
    for v, name in ((.055, 'taut stitched header'), (.962, 'folded bottom seam')):
        tube(f'Loft curtain | {name}', [curtain_point(i / 40, v) for i in range(41)], .006, 'olive', taper=0)
    for i in range(6):
        x = -.280 + .112 * i
        _raf_ring(f'Loft curtain | hanging eyelet {i + 1}', x, .002, .458, .012, .003, 'brass', 'Metal', 16)

    part('clothesline')
    def line_top(u):
        return -.237 + .474 * u, .006 - .025 * sin(pi * u), .327 + .060 * (2 * u - 1) ** 2 + .014 * u
    tube('Clothesline | sagged upper line', [line_top(i / 24) for i in range(25)], .008, 'rope', taper=0)
    tube('Clothesline | slack lower guide cable', [(-.237 + .474 * i / 24, .036 - .018 * sin(pi * i / 24),
         .055 + .109 * (2 * i / 24 - 1) ** 2) for i in range(25)], .006, 'rope', taper=0)
    for i, x in enumerate((-.232, .232)):
        box(f'Clothesline | end wall mount {i + 1}', (x, .040, .212), (.027, .041, .424), 'wooddark', b=.008,
            rot=(0, (-1 if i == 0 else 1) * .025, 0))
    def laundry_point(u, v):
        lx, ly, lz = line_top(.133 + .741 * u)
        hem = .094 + .032 * u + .014 * sin(4 * pi * u) - .013 * sin(pi * u)
        return lx + .018 * v * (u - .31), ly - .016 - .053 * sin(pi * v) + (.007 + .016 * v) * sin(7 * pi * u + v), lz * (1 - v) + hem * v
    sheet('Clothesline | hanging slate-gray laundry', [[laundry_point(i / 26, j / 14)
          for i in range(27)] for j in range(15)], .013, 'gray')
    tube('Clothesline | gray cloth sewn hem', [laundry_point(i / 32, .985) for i in range(33)],
         .006, 'graylight', taper=0)
    for i, u in enumerate((.083, .884)):
        x, y, z = laundry_point(u, 0)
        box(f'Clothesline | timber peg {i + 1}', (x, y + .005, z + .007), (.024, .024, .055),
            'woodlight', b=.006, rot=(.18, .16 if i == 0 else -.13, 0))

    part('loft_frames')
    frames = ((-.171, .322, .174, .188, -.073, 'woodlight', 'sky'), (.031, .391, .157, .147, .052, 'wood', 'gray'),
              (.203, .310, .148, .204, -.066, 'woodlight', 'blue'), (-.101, .103, .147, .173, .078, 'wood', 'aqua'),
              (.084, .166, .179, .114, -.053, 'woodlight', 'sky'), (.220, .066, .106, .110, .080, 'wooddark', 'beige'))
    for i, (cx, cz, w, h, ang, wood_col, sky_col) in enumerate(frames):
        name = f'Loft collage | frame {i + 1}'
        def photo_point(x, y, z):
            return cx + x * cos(ang) + z * sin(ang), y, cz - x * sin(ang) + z * cos(ang)
        box(f'{name} | timber surround', (cx, .008, cz), (w, .035, h), wood_col, b=.009, rot=(0, ang, 0))
        box(f'{name} | warm paper mat', (cx, -.014, cz), (w - .023, .010, h - .023), 'paper', b=.005, rot=(0, ang, 0))
        pw, ph = w - .044, h - .044
        box(f'{name} | picture ground', (cx, -.022, cz), (pw, .007, ph), sky_col, b=.003, rot=(0, ang, 0))
        oval(f'{name} | sun in print', photo_point((-.22 if i % 2 else .21) * pw, -.027, .23 * ph),
             (.012, .003, .012), 'honey')
        local = ((-.49, -.46), (.49, -.46), (.49, -.13), (.26, -.18), (.03, .10), (-.22, -.19), (-.49, .02))
        pts = [(x, z) for x, _, z in (photo_point(px * pw, 0, pz * ph) for px, pz in local)]
        profile(f'{name} | layered coastal scene', pts, .004, -.028, 'teal' if i % 2 else 'terracotta', b=.001)

    part('lighting')
    oval('Pendant light | warm opal globe', (0, 0, .058), (.055, .055, .058), 'warmwhite', 'Emission')
    oval('Pendant light | ceramic socket', (0, 0, .120), (.044, .044, .038), 'cream')
    rings = ((.110, .113), (.116, .118), (.133, .131), (.151, .124), (.186, .083), (.203, .047), (.212, .036))
    sheet('Pendant light | spun enamel shade', [[(r * cos(2 * pi * i / 32), r * sin(2 * pi * i / 32), z)
          for i in range(33)] for z, r in rings], .013, 'mintdark', 'Gloss')
    tube('Pendant light | white rolled shade lip', [(.116 * cos(2 * pi * i / 32),
         .116 * sin(2 * pi * i / 32), .113) for i in range(33)], .006, 'cream', taper=0)
    oval('Pendant light | brass stem cap', (0, 0, .224), (.033, .033, .023), 'brass', 'Metal')
    tube('Pendant light | suspension wire', [(0, 0, .234), (.008, .003, .276), (.010, .007, .318),
         (.004, .009, .358), (0, .010, .386)], .007, 'ink', taper=0)
    oval('Pendant light | ceiling canopy', (0, .010, .396), (.063, .062, .017), 'wooddark')

    part('side_vent')
    box('Side vent | rounded rear housing', (0, .016, .140), (.336, .084, .280), 'beige', b=.018)
    box('Side vent | recess behind louvers', (0, -.031, .140), (.286, .022, .222), 'slate', b=.012)
    for s in (-1, 1):
        box('Side vent | raised vertical jamb', (s * .151, -.048, .140), (.032, .043, .250), 'cream', b=.009)
        box('Side vent | horizontal frame rail', (0, -.046, .140 + s * .120), (.320, .045, .032), 'cream', b=.009)
    for i in range(5):
        z = .062 + .039 * i
        box(f'Side vent | pitched rain louver {i + 1}', (0, -.055, z), (.281, .054, .025),
            'beige', b=.007, rot=(.39, 0, 0))
        box(f'Side vent | louver {i + 1} rolled front edge', (0, -.077, z - .008), (.279, .013, .009),
            'cream', b=.003)
    for x in (-.148, .148):
        for z in (.043, .238):
            _raf_screw('Side vent | panel screw', x, -.076, z)
