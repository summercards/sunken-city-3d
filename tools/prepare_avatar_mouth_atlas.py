"""Extract/pad generated original mouth artwork without repainting the artwork."""
import json
from collections import deque
from pathlib import Path
from PIL import Image, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/characters/avatar/v005/graphic_mouth_source.png'
OUTPUT = ROOT / 'godot/assets/textures/avatar/graphic_mouths.png'
IDS = ['smile','wide','calm','oh','open','grin','frown','smirk','cat','joy','laugh','pout','fang','tongue','kiss','zigzag']

image = Image.open(SOURCE).convert('RGBA')
atlas = Image.new('RGBA', (1024, 1024))
for index, name in enumerate(IDS):
    col, row = index % 4, index // 4
    tile = image.crop((col*image.width//4, row*image.height//4, (col+1)*image.width//4, (row+1)*image.height//4))
    # Remove fragments from the neighbouring grid tile, keeping the complete
    # largest alpha-connected mouth symbol.
    alpha = tile.getchannel('A')
    data = alpha.load(); seen = set(); components = []
    for y in range(tile.height):
        for x in range(tile.width):
            if data[x, y] <= 24 or (x, y) in seen:
                continue
            queue = deque([(x, y)]); seen.add((x, y)); component = []
            while queue:
                at = queue.popleft(); component.append(at)
                for nx, ny in [(at[0]-1, at[1]), (at[0]+1, at[1]), (at[0], at[1]-1), (at[0], at[1]+1)]:
                    if 0 <= nx < tile.width and 0 <= ny < tile.height and (nx, ny) not in seen and data[nx, ny] > 24:
                        seen.add((nx, ny)); queue.append((nx, ny))
            components.append(component)
    main = max(components, key=len)
    mask = Image.new('L', tile.size)
    mask_data = mask.load()
    for point in main:
        mask_data[point] = 255
    mask = mask.filter(ImageFilter.MaxFilter(3))
    tile.putalpha(ImageChops.multiply(alpha, mask))
    box = tile.getchannel('A').point(lambda value: 255 if value > 24 else 0).getbbox()
    if box is None:
        raise ValueError('Empty generated mouth: ' + name)
    tile = tile.crop(box)
    tile.thumbnail((214, 184), Image.Resampling.LANCZOS)
    atlas.alpha_composite(tile, (col*256+(256-tile.width)//2, row*256+(256-tile.height)//2))
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
atlas.save(OUTPUT)
manifest = dict(version=1, source=str(SOURCE.relative_to(ROOT)).replace('\\','/'),
                runtime=str(OUTPUT.relative_to(ROOT)).replace('\\','/'), columns=4, rows=4, tile_size=256,
                ids=IDS, style='original thick graphic ink / white sclera; large chunky shapes',
                generation='built-in image generation; reference style described in text; no copied game pixels',
                processing='regular grid crop, largest alpha-connected symbol extraction, aspect-preserving resample and transparent padding',
                animation='per-mouth shader aperture and expression frame selection; independent expression driver; fixed curved mesh')
(SOURCE.parent/'graphic_mouth_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(OUTPUT)
