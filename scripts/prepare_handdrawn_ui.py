#!/usr/bin/env python3
"""Extract the approved gpt-image-2 atlases into transparent UI sprites (Pillow)."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ACTIONS = ['plant', 'water', 'harvest', 'dig', 'hand', 'bag', 'shipping', 'sleep', 'shop', 'fish', 'anchor', 'back']
ITEMS = ['wood', 'parts', 'rope', 'glass', 'seed', 'shell', 'fish', 'vegetable', 'tomato', 'pumpkin', 'pearl', 'lettuce_seed', 'tomato_seed', 'pumpkin_seed', 'water', 'coins']


def extract(source, output):
    output.mkdir(parents=True, exist_ok=True)
    for kind, keys, rows in [('action', ACTIONS, 3), ('pocket', ITEMS, 4)]:
        image = Image.open(source / (kind + '-icons-source.png')).convert('RGB')
        width, height = image.size
        for index, key in enumerate(keys):
            cell = image.crop((index % 4 * width // 4, index // 4 * height // rows,
                               (index % 4 + 1) * width // 4, (index // 4 + 1) * height // rows))
            pixels = []
            for red, green, blue in cell.getdata():
                if kind == 'action':
                    alpha = max(0, min(1, ((red + green + blue) / 3 - 12) / 235))
                    rgb = (255, 255, 255)
                else:
                    spill = max(0, min(red, blue) - green - 25)
                    alpha = 1 - max(0, min(1, spill / 230))
                    # Remove residual near-magenta compression/noise in the flat backdrop.
                    if alpha < .18:
                        alpha = 0
                    rgb = tuple(max(0, min(255, round((c - (1-alpha)*255) / max(alpha, .05))))
                                for c in (red, blue))
                    rgb = (rgb[0], max(0, min(255, round(green / max(alpha, .05)))), rgb[1])
                pixels.append((*rgb, round(alpha * 255) if alpha >= .02 else 0))
            sprite = Image.new('RGBA', cell.size)
            sprite.putdata(pixels)
            bounds = sprite.getchannel('A').point(lambda p: 255 if p > 30 else 0).getbbox()
            sprite = sprite.crop(bounds)
            sprite.thumbnail((220, 220), Image.Resampling.LANCZOS)
            final = Image.new('RGBA', (256, 256))
            final.alpha_composite(sprite, ((256-sprite.width)//2, (256-sprite.height)//2))
            final.save(output / (('action_' if kind == 'action' else 'item_') + key + '.png'))
    manifest = {
        'model': 'gpt-image-2', 'provider': 'Sofunny AIKey', 'generation_mode': 'reference-image API',
        'reference': 'User-supplied pocket screenshot; style reference only; not packaged',
        'source_dir': str(source.resolve()), 'actions': ACTIONS, 'items': ITEMS,
        'processing': 'Equal-cell extraction; chroma/luminance alpha; no redrawing; 256px transparent runtime sprites',
        'license_status': 'pending_provider_terms_review',
        'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob('*.png'))},
        'prompts': {p.name: p.read_text(encoding='utf-8-sig').strip() for p in source.glob('*_prompt.txt')},
    }
    (output / 'provenance.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Extracted', len(manifest['files']), 'sprites')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parents[1] / 'godot/assets/ui/handdrawn')
    args = parser.parse_args()
    extract(args.source_dir, args.output_dir)
