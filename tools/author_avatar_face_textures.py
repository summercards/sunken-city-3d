"""Author deterministic, transparent cosmetic masks (original SEA, 2026-11-03).

Run from any directory; the checked-in PNG files are runtime source assets.
White RGB keeps tinting in the appearance renderer independent of the mask.
"""
from pathlib import Path
import math
from PIL import Image

DEST = Path(__file__).resolve().parents[1] / "godot/assets/textures/avatar"
SIZE = 256


def write(name, alpha_at):
    image = Image.new("RGBA", (SIZE, SIZE))
    image.putdata([(255, 255, 255, max(0, min(255, round(255 * alpha_at(
        (x + .5) / SIZE * 2 - 1, (y + .5) / SIZE * 2 - 1)))))
        for y in range(SIZE) for x in range(SIZE)])
    image.save(DEST / name, optimize=True)


def soft(x, y):
    r = math.hypot(x, y)
    return max(0, 1 - r * r) ** 2 * .70


FRECKLES = [(-.68, -.08, .066), (-.38, .15, .073), (-.08, -.10, .061),
            (.25, .12, .071), (.58, -.11, .062), (-.48, -.37, .049),
            (-.02, -.42, .053), (.44, -.38, .049), (.00, .42, .048)]


def freckles(x, y):
    return max((max(0, min(1, (r - math.hypot(x - a, y - b)) * 150))
                for a, b, r in FRECKLES), default=0) * .86


def stubble(x, y):
    # A stable jittered pattern; no randomness or runtime texture synthesis.
    best = 0
    for row in range(10):
        for col in range(19):
            a = -.94 + col * .103 + math.sin(row * 31 + col * 7) * .018
            b = -.92 + row * .203 + math.cos(row * 13 + col * 17) * .025
            r = .013 + ((row * 7 + col * 11) % 5) * .0018
            best = max(best, max(0, min(1, (r - math.hypot(x - a, y - b)) * 190)))
    return best * max(0, 1 - (x * x + y * y) ** 3) * .82


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    write("blush_soft.png", soft)
    write("freckles.png", freckles)
    write("stubble.png", stubble)
    print(f"Authored 3 transparent 256px avatar masks in {DEST}")
