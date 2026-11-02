"""Run the installed prop validator with sea's explicit 8x8 UV adapter.

Only the cell-grid audit is adapted; material, external-image, active-UV,
output, emissive and ownership checks remain unchanged. No source save occurs.
"""
import bpy, importlib.util, json, math, sys, os, hashlib
from pathlib import Path

R = Path(__file__).resolve().parents[3]
D = R/'art_source/scenes/ocean_rooftop_farm/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent/'sea-work'))/'ocean_rooftop_farm/v001'
skill = Path.home()/'.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py'
spec = importlib.util.spec_from_file_location('skill_prop_validator', skill)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def audit_grid8(obj):
    layer = obj.data.uv_layers.get('PaletteUV')
    result = {'object':obj.name, 'polygon_count':len(obj.data.polygons),
              'valid_island_polygon_count':0, 'missing_palette_uv':layer is None,
              'active_uv':obj.data.uv_layers.active.name if obj.data.uv_layers.active else '',
              'active_render_uv':next((u.name for u in obj.data.uv_layers if u.active_render), ''),
              'extra_uv_layers':[u.name for u in obj.data.uv_layers if u.name != 'PaletteUV'],
              'bad_polygon_examples':[]}
    if layer is None:
        return result
    for face in obj.data.polygons:
        uvs = [layer.data[li].uv for li in face.loop_indices]
        cells = {(math.floor(uv.x*8), math.floor(uv.y*8)) for uv in uvs}
        safe = len(cells) == 1 and all(.125 <= ((uv.x*8)%1) <= .875 and .125 <= ((uv.y*8)%1) <= .875 for uv in uvs)
        if safe and module.uv_polygon_area(uvs) >= module.MIN_UV_AREA:
            result['valid_island_polygon_count'] += 1
        elif len(result['bad_polygon_examples']) < 8:
            result['bad_polygon_examples'].append(face.index)
    return result

module.audit_palette_uv = audit_grid8
catalog = json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
rows = []
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
for entry in catalog:
    source = R/entry['component_source']
    before = sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    output = bpy.data.collections.new('02_游戏输出_独立组件')
    bpy.context.scene.collection.children.link(output)
    output.children.link(bpy.data.collections[entry['collection']])
    report = W/('skill_prop_'+entry['key']+'.json')
    sys.argv = ['validate_game_prop.py', '--', '--max-materials', '4', '--shared-palette',
                str(R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'), '--json', str(report)]
    try:
        module.main()
    except SystemExit as result:
        assert result.code == 0, entry['key']+' skill prop validation failed'
    assert sha(source) == before
    rows.append({'key':entry['key'], 'passed':True, 'source_hash_unchanged':True, 'report':str(report)})
(W/'skill_prop_verification.json').write_text(json.dumps({'passed':True, 'installed_validator':str(skill),
    'uv_adapter':'sea 8x8 with 8px safe inset; other skill checks unchanged', 'components':rows}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('OCEAN_ROOFTOP_FARM_SKILL_PROP_PASS', len(rows))
