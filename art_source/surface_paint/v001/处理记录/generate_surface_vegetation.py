#!/usr/bin/env python3
"""以固定种子绘制苔藓和藤蔓贴图，仅依赖 Pillow，不读取外部素材。"""

import argparse
import math
from pathlib import Path
import random

from PIL import Image, ImageDraw


TILE = 256
SCALE = 3
PAD = 10
ROOT = Path(__file__).resolve().parents[4]
OUTPUT = ROOT / 'godot/assets/textures/vegetation'


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x):
    return max(0.0, min(1.0, x))


def smooth(x):
    x = clamp(x)
    return x * x * (3.0 - 2.0 * x)


def tint(color, delta):
    return tuple(max(0, min(255, round(c + delta * weight)))
                 for c, weight in zip(color, (1.0, 0.94, 0.64)))


def noise_grid(rng, n):
    values = [[rng.random() for _ in range(n)] for _ in range(n)]

    def at(x, y):
        u, v = (x % TILE) * n / TILE, (y % TILE) * n / TILE
        i, j = int(u), int(v)
        s, t = smooth(u - i), smooth(v - j)
        a, b = values[j], values[(j + 1) % n]
        k = (i + 1) % n
        return lerp(lerp(a[i], a[k], s), lerp(b[i], b[k], s), t)

    return at


def raster(draw, points, color):
    draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=color)


def stroke(draw, points, width, color):
    draw.line([(round(x * SCALE), round(y * SCALE)) for x, y in points],
              fill=color, width=max(1, round(width * SCALE)), joint='curve')


def downsample(image, size):
    # 在预乘空间缩放；导出时恢复直通 alpha，避免轮廓混入黑底。
    return image.convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')


def clean_edges(image, wrap=False, radius=5):
    # 近透明像素从相邻实色取色，压住预乘量化杂色；平铺图的取样跨边界。
    w, h = image.size
    pixels = [(r, g, b, a) if a > 4 else (0, 0, 0, 0)
              for r, g, b, a in image.get_flattened_data()]
    # 按相对位移排序，避免等距实色点的取舍受到贴图起点影响。
    offsets = sorted((dx * dx + dy * dy, dy, dx)
                     for dy in range(-radius, radius + 1)
                     for dx in range(-radius, radius + 1)
                     if 0 < dx * dx + dy * dy <= radius * radius)
    for i, (r, g, b, alpha) in enumerate(pixels):
        if alpha >= 56:
            continue
        y, x = divmod(i, w)
        for _, dy, dx in offsets:
            xx, yy = x + dx, y + dy
            if wrap:
                xx, yy = xx % w, yy % h
            elif not (0 <= xx < w and 0 <= yy < h):
                continue
            pr, pg, pb, pa = pixels[yy * w + xx]
            if pa >= 56:
                mix = smooth((alpha - 16) / 40)
                pixels[i] = (round(lerp(pr, r, mix)), round(lerp(pg, g, mix)),
                             round(lerp(pb, b, mix)), alpha)
                break
    image.putdata(pixels)
    return image


def moss_tile(phase=(0, 0)):
    rng = random.Random(620483)
    warp_x, warp_y, large, medium, small, grain = (
        noise_grid(rng, n) for n in (3, 3, 5, 9, 20, 51))

    def field(x, y):
        u = x + (warp_x(x, y) - 0.5) * 49
        v = y + (warp_y(x, y) - 0.5) * 49
        a, b, c = large(u, v), medium(u, v), small(x, y)
        # 低矮铺展的连续脊，不以圆形斑块为生长单元。
        ridge = 0.5 + 0.5 * math.sin(math.tau * (u + 2 * v) / TILE + 3.8 * (a - 0.5))
        return 0.46 * a + 0.28 * b + 0.16 * c + 0.10 * ridge, c

    px, py = phase
    base = Image.new('RGBA', (TILE, TILE))
    data = []
    for j in range(TILE):
        for i in range(TILE):
            x, y = i + px + 0.5, j + py + 0.5
            f, c = field(x, y)
            g = grain(x, y)
            opacity = smooth((f + (g - 0.5) * 0.052 - 0.415) / 0.245)
            lit = 25 * smooth((f - 0.43) / 0.31) + 15 * (c - 0.5) + 9 * (g - 0.5)
            data.append((*tint((46, 75, 48), lit), round(opacity * 196)))
    base.putdata(data)

    size = TILE + 2 * PAD
    detail = Image.new('RGBA', (size * SCALE, size * SCALE))
    draw = ImageDraw.Draw(detail)
    greens = ((52, 88, 58), (66, 103, 58), (80, 116, 61), (97, 131, 68),
              (116, 148, 78), (143, 160, 88), (162, 172, 100))
    # 三层短叶：暗层压在底部，中层曲叶形成密垫，亮层只挑少数生长点。
    for count, min_f, scale, lo, hi, alpha in (
            (7100, 0.41, 1.20, 0, 2, (133, 215)),
            (6800, 0.438, 1.00, 1, 4, (172, 245)),
            (2600, 0.50, 0.75, 3, 6, (178, 248))):
        for _ in range(count):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            f, c = field(x, y)
            if rng.random() >= smooth((f - min_f) / 0.19) * (0.58 + 0.42 * c):
                continue
            length = rng.uniform(2.3, 6.6) * scale
            w = rng.uniform(0.65, 1.62) * scale
            angle = rng.uniform(-1.9, 1.35) + 1.4 * (warp_y(x, y) - 0.5)
            dx, dy = math.sin(angle), -math.cos(angle)
            bend = rng.uniform(-0.7, 0.7) * w
            shade = lerp(lo, hi, clamp((f - 0.42) * 2.4 + rng.uniform(0.07, 0.62)))
            ink = tint(greens[round(shade)], rng.uniform(-9, 10))
            rgba = (*ink, rng.randint(*alpha))
            cx, cy = (x - px) % TILE + PAD, (y - py) % TILE + PAD
            for k in (-TILE, 0, TILE):
                if not -9 <= (xx := cx + k) <= size + 9:
                    continue
                for l in (-TILE, 0, TILE):
                    if not -9 <= (yy := cy + l) <= size + 9:
                        continue

                    def q(t, side):
                        s = side * w + bend * t * t
                        return xx + dx * t * length - dy * s, yy + dy * t * length + dx * s

                    raster(draw, [q(0, -0.26), q(.23, -.82), q(.54, -1), q(.85, -.60),
                                  q(1, .12), q(.66, .70), q(.29, .69), q(0, .22)], rgba)
                    if w > 0.94 and rgba[3] > 190:
                        raster(draw, [q(.19, -.52), q(.53, -.85), q(.95, .03), q(.55, -.11)],
                               (*tint(ink, 15), rgba[3]))
    detail = downsample(detail, (size, size)).crop((PAD, PAD, PAD + TILE, PAD + TILE))
    return Image.alpha_composite(base, detail)


def bezier(a, b, c, d, steps=8):
    for i in range(1, steps + 1):
        t = i / steps
        s = 1 - t
        yield tuple(s**3 * p + 3 * s * s * t * q + 3 * s * t * t * r + t**3 * v
                    for p, q, r, v in zip(a, b, c, d))


def chain(start, segments):
    result = [start]
    for b, c, d in segments:
        result.extend(bezier(result[-1], b, c, d))
    return result


def vine_strip():
    width, height = 256, 512
    image = Image.new('RGBA', (width * SCALE, height * SCALE))
    draw = ImageDraw.Draw(image)
    rng = random.Random(910673)
    # 每条路径由上向下，支茎的第一点直接取主茎坐标。
    main = [(-6, 126), (42, 119), (90, 143), (145, 154), (205, 122),
            (257, 113), (309, 137), (365, 151), (419, 136), (475, 126), (501, 138)]

    def x_at(path, y):
        for i, ((y0, x0), (y1, x1)) in enumerate(zip(path, path[1:])):
            if y <= y1:
                ya, xa = path[max(0, i - 1)]
                yb, xb = path[min(len(path) - 1, i + 2)]
                t = clamp((y - y0) / (y1 - y0))
                m0 = (x1 - xa) / (y1 - ya) * (y1 - y0)
                m1 = (xb - x0) / (yb - y0) * (y1 - y0)
                return (lerp(x0, x1, smooth(t)) + t * (1 - t) ** 2 * m0
                        - t * t * (1 - t) * m1)
        return path[-1][1]

    def limb(start, *rest):
        return [(start, x_at(main, start)), *rest]

    left = limb(40, (64, 88), (104, 63), (144, 64), (167, 48), (183, 43))
    right = limb(109, (135, 178), (175, 197), (219, 191), (251, 211), (270, 207))
    lower_l = limb(216, (244, 87), (288, 65), (335, 68), (372, 51), (391, 57))
    lower_r = limb(326, (351, 177), (390, 193), (422, 182), (447, 188), (466, 178))

    def stem(path, thick, base_color):
        y0, y1 = path[0][0], path[-1][0]
        center = [(x_at(path, y), y) for y in range(y0, y1 + 1)]
        widths = [lerp(thick, 0.35, (i / (len(center) - 1)) ** 1.30) for i in range(len(center))]

        def edge(factor):
            return [(x + w * factor, y) for (x, y), w in zip(center, widths)]

        raster(draw, edge(-.50) + edge(.50)[::-1], (*base_color, 255))
        raster(draw, edge(-.30) + edge(.24)[::-1], (*tint(base_color, 25), 255))
        raster(draw, edge(-.31) + edge(-.12)[::-1], (*tint(base_color, 47), 255))

    for path, thick, color in ((left, 4.0, (60, 73, 36)), (right, 4.1, (58, 77, 44)),
                               (lower_l, 3.6, (61, 79, 40)), (lower_r, 3.0, (67, 78, 38)),
                               (main, 6.8, (56, 72, 36))):
        stem(path, thick, color)

    # 叶轮廓用手定的曲线控制点；一款心形、一款浅裂三尖。
    forms = (
        (((-.08, -.16), (-.10, -.53), (.05, -.78)), ((.16, -1.01), (.42, -.83), (.56, -.62)),
         ((.75, -.46), (.90, -.18), (1, 0))),
        (((-.10, -.30), (.01, -.70), (.26, -.97)), ((.23, -.62), (.38, -.55), (.47, -.52)),
         ((.60, -.61), (.87, -.17), (1, 0))),
    )
    leaf_colors = ((48, 91, 56), (58, 109, 65), (73, 125, 68), (87, 137, 65),
                   (107, 148, 76), (121, 157, 74), (138, 164, 82))

    def leaf(path, y, dx, dy, length, half, idx, style, roll):
        ax, ay = x_at(path, y), y
        reach = math.hypot(dx, dy)
        ux, uy = dx / reach, dy / reach
        pet = max(3.5, reach - length)
        bx, by = ax + ux * pet, ay + uy * pet
        join = chain((ax, ay), [((ax + dx * .14, ay + dy * .03),
                                 (bx - ux * 3, by - uy * 1), (bx, by))])
        stroke(draw, join, 1.9 if length > 26 else 1.35, (69, 96, 45, 255))
        stroke(draw, [(x - .32, yy - .25) for x, yy in join], .65, (128, 147, 71, 242))
        outline = chain((0, 0), forms[style])
        turn = rng.uniform(-.17, .17)

        def q(t, s):
            d = (s * (1 + roll if s > 0 else 1 - roll) + turn * t * t) * half
            return bx + ux * t * length - uy * d, by + uy * t * length + ux * d

        a = [q(t, s) for t, s in outline]
        b = [q(t, -s * (.93 + .10 * t)) for t, s in outline]
        color = tint(leaf_colors[idx], rng.uniform(-5, 5))
        raster(draw, a + b[::-1], (*tint(color, -16), 255))
        # 两个不对称的色面与窄叶缘共同表现叶面翻转。
        for side, delta in ((1, 13 - 29 * roll), (-1, -4 + 30 * roll)):
            face = [q(.027 + .94 * t, side * s * .87) for t, s in outline]
            raster(draw, face + [q(.93, 0), q(.57, .012), q(.30, -.015), q(.04, 0)],
                   (*tint(color, delta), 255))
        if roll < .12:
            shape = chain((.13, -.38), [((.13, -.64), (.25, -.74), (.38, -.67)),
                                        ((.51, -.57), (.60, -.37), (.71, -.28)),
                                        ((.45, -.43), (.30, -.49), (.13, -.38))])
            if style:
                shape = [(t, s * .71) for t, s in shape]
            raster(draw, [q(t, s) for t, s in shape], (*tint(color, 25), 255))
        vein = tint(color, 40 if idx < 5 else 27)
        stroke(draw, [q(.04, 0), q(.27, -.012), q(.49, .016), q(.71, .010), q(.89, 0)],
               1.05 if length > 28 else .69, (*vein, 255))
        for side in (-1, 1):
            for t, spread in ((.25, .53), (.44, .43), (.61, .29)):
                if length >= 22 or t == .25:
                    stroke(draw, [q(t, 0), q(t + .09, side * spread * .57),
                                  q(t + .18, side * spread)], .60, (*tint(color, 23), 249))

    # 叶位为构图数据，故意打破对生、等距和左右镜像。越往末端，叶片越小且越少。
    for path, leaves in (
        (left, [(57, -48, 9, 34, 15, 2, 1, -.09), (81, 20, 31, 28, 12, 3, 0, .26),
                (101, -44, 10, 34, 14, 3, 0, -.17), (118, 17, 36, 31, 14, 5, 1, .13),
                (143, -36, 15, 29, 12, 1, 1, .11), (169, 12, 25, 22, 9, 4, 0, -.24)]),
        (right, [(129, 39, -15, 32, 14, 1, 1, .32), (151, 41, 25, 37, 17, 3, 0, -.12),
                 (174, -25, 36, 32, 15, 2, 1, -.35), (201, 45, 13, 34, 14, 5, 1, -.24),
                 (229, -30, 23, 30, 12, 3, 0, .33), (248, 21, 21, 22, 9, 4, 0, .01),
                 (268, -9, 22, 17, 7, 6, 0, -.14)]),
        (lower_l, [(231, -49, 3, 39, 15, 2, 0, .19), (259, 19, 36, 31, 13, 3, 1, -.32),
                   (285, -42, 18, 33, 14, 4, 1, -.05), (321, 24, 26, 27, 12, 2, 0, .31),
                   (350, -30, 18, 27, 12, 2, 1, -.26), (376, 19, 22, 22, 9, 5, 0, .15)]),
        (lower_r, [(347, 32, 23, 27, 12, 2, 0, .20), (375, 39, 16, 31, 13, 4, 1, -.15),
                   (403, -19, 26, 25, 12, 2, 0, -.02), (437, 26, 26, 27, 10, 3, 1, -.31),
                   (463, -7, 19, 15, 6, 5, 0, .16)]),
        (main, [(17, -41, 17, 33, 15, 3, 0, -.15), (35, 37, 15, 32, 13, 4, 1, .13),
                (72, 43, 30, 39, 16, 2, 1, .21), (96, -36, 19, 32, 13, 2, 0, .18),
                (126, -51, 22, 42, 18, 4, 1, -.13), (155, -20, 33, 28, 12, 4, 0, .22),
                (189, 25, 39, 37, 16, 3, 0, -.22), (228, 41, 22, 36, 14, 1, 1, .30),
                (275, -26, 25, 26, 12, 4, 0, -.11), (299, 41, 21, 31, 13, 3, 1, .18),
                (322, -47, 25, 38, 16, 2, 1, -.32), (360, -27, 28, 29, 12, 5, 0, .20),
                (388, 24, 18, 24, 10, 5, 1, .12), (422, -35, 20, 30, 13, 3, 0, -.25),
                (456, 30, 14, 23, 10, 4, 1, .24), (480, -13, 18, 16, 7, 6, 0, -.13)]),
    ):
        for values in leaves:
            leaf(path, *values)
    return downsample(image, (width, height))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=OUTPUT, help='现有输出目录')
    args = parser.parse_args()
    for name, artwork in (('surface_moss_tile_256.png', moss_tile()),
                          ('surface_vine_strip_256.png', vine_strip())):
        clean_edges(artwork, wrap=name == 'surface_moss_tile_256.png').save(
            args.output_dir / name, compress_level=9)


if __name__ == '__main__':
    main()
