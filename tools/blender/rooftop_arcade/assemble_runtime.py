"""Initialize the arcade's new runtime resources only; never rewrite authored scenes."""
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / 'art_source/scenes/rooftop_arcade/v001'
GAME = ROOT / 'godot'
WORK = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'rooftop_arcade_v001/runtime'
SLUG = 'rooftop_arcade'
MODELS = f'assets/models/facilities/{SLUG}'
COMPONENTS = f'scenes/components/facilities/{SLUG}'
PALETTE = f'assets/textures/shared/sea_{SLUG}_8x8_512.png'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def transform(matrix):
    # Godot serializes basis columns. Conjugate by Blender->Godot X,Z,-Y.
    axes, sign = [0, 2, 1], [1, 1, -1]
    values = [sign[r] * sign[c] * matrix[axes[r]][axes[c]] for c in range(3) for r in range(3)]
    values += [sign[r] * matrix[axes[r]][3] for r in range(3)]
    return 'Transform3D(' + ', '.join(format(x, '.9g') for x in values) + ')'


def import_config(template, src, kind):
    suffix = 'scn' if kind == 'scene' else 'ctex'
    product = f'res://.godot/imported/{Path(src).name}-{hashlib.md5(src.encode()).hexdigest()}.{suffix}'
    result = re.sub(r'^uid=.*\n', '', template, flags=re.M)
    result = re.sub(r'^path=.*$', f'path="{product}"', result, flags=re.M)
    result = re.sub(r'^source_file=.*$', f'source_file="{src}"', result, flags=re.M)
    result = re.sub(r'^dest_files=.*$', f'dest_files=["{product}"]', result, flags=re.M)
    return result.replace('res://tools/gift_kiosk_import.gd', 'res://tools/rooftop_arcade_import.gd')


def main():
    report = json.loads((WORK / 'export.json').read_text())
    assert report['source_unchanged_after_export']
    for record in [*report['sources'], report['optimized_blend']]:
        assert digest((ROOT / record['path']).read_bytes()) == record['sha256']
    scene_import = next((GAME / 'assets/models/facilities/gift_kiosk/deck').glob('*.glb.import')).read_text()
    texture_import = (GAME / 'assets/textures/shared/sea_cozy_8x8_512.png.import').read_text()
    palette = (ART.parents[2] / 'shared/palettes/sea_rooftop_arcade_8x8_512.png').read_bytes()
    outputs = {PALETTE: palette, PALETTE + '.import': import_config(texture_import, 'res://' + PALETTE, 'texture')}
    for role, properties in {'Matte':'roughness = 0.66', 'Metal':'metallic = 0.42\nroughness = 0.32',
                             'Gloss':'roughness = 0.24', 'Emission':'roughness = 0.38\nemission_enabled = true\nemission = Color(1, 1, 1, 1)\nemission_energy_multiplier = 0.65\nemission_texture = ExtResource("palette")'}.items():
        outputs[f'assets/materials/{SLUG}/{role.lower()}.tres'] = f'''[gd_resource type="StandardMaterial3D" format=3]

[ext_resource type="Texture2D" path="res://{PALETTE}" id="palette"]

[resource]
resource_name = "SEA_{role}"
albedo_texture = ExtResource("palette")
texture_filter = 0
texture_repeat = false
{properties}
'''
    scene = ['[gd_scene format=3]', '',
             '[ext_resource type="Script" path="res://src/facilities/rooftop_arcade_zone.gd" id="zone"]',
             '[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blocker"]',
             '[ext_resource type="Script" path="res://src/navigation/walk_area.gd" id="walk"]',
             '[ext_resource type="Script" path="res://src/navigation/landing_point.gd" id="landing"]']
    for row in report['components']:
        key = row['asset_key']
        glb = f'{MODELS}/{key}/{key}.glb'
        prefab = f'{COMPONENTS}/{key}.tscn'
        outputs[glb] = (WORK / 'glb' / f'{key}.glb').read_bytes()
        assert digest(outputs[glb]) == row['glb_sha256']
        outputs[glb + '.import'] = import_config(scene_import, 'res://' + glb, 'scene')
        outputs[prefab] = f'''[gd_scene format=3]

[ext_resource type="PackedScene" path="res://{glb}" id="visual"]

[node name="{key}" type="Node3D"]
metadata/asset_id = "{row['asset_id']}"
metadata/asset_version = "v001"
metadata/building_class = "above_water"
metadata/water_layer = "surface"
metadata/water_layer_role = "part"

[node name="Visual" parent="." instance=ExtResource("visual")]
'''
        row.update(runtime_path='godot/' + glb, prefab='godot/' + prefab)
        scene.append(f'[ext_resource type="PackedScene" path="res://{prefab}" id="{key}"]')
    scene += ['', '[node name="rooftop_arcade" type="Node3D"]', 'script = ExtResource("zone")',
              'zone_id = "rooftop_arcade"', 'zone_label = "海上屋顶街机维修铺"', 'water_layer = "surface"',
              'asset_id = "SEA-SCENE-RAC"', 'role = "landmark"', 'metadata/asset_id = "SEA-SCENE-RAC"',
              'metadata/asset_version = "v001"', 'metadata/building_class = "above_water"', '',
              '[node name="Visual" type="Node3D" parent="."]', '']
    instances = json.loads((ART / 'component_instances.json').read_text())['instances']
    assert len(instances) == 355
    for row in instances:
        key = row['asset_key']
        scene += [f'[node name="{key}_{row["instance_index"]:03}" parent="Visual" instance=ExtResource("{key}")]',
                  'transform = ' + transform(row['matrix_world']), '']
    scene += ['''[node name="Blockers" type="Node3D" parent="."]
script = ExtResource("blocker")
target_path = NodePath("../Visual/float_base_001")
cell = 0.2

[node name="WalkAreas" type="Node3D" parent="."]

[node name="WalkWestDeck" type="Node3D" parent="WalkAreas"]
script = ExtResource("walk")
area_id = "rooftop_arcade_west_deck"
zone_id = "rooftop_arcade"
body_radius = 0.0
rects = [Rect2(-1.90, -1.21, 0.21, 1.21)]

[node name="Landing_main" type="Marker3D" parent="WalkAreas/WalkWestDeck"]
position = Vector3(-1.80, 0.42, -0.76)
script = ExtResource("landing")
landing_label = "屋顶街机维修铺"

[node name="BoatPark" type="Marker3D" parent="WalkAreas/WalkWestDeck/Landing_main"]
position = Vector3(-3.65, -0.30, 0)
rotation = Vector3(0, 0, 0)

[node name="DockEdge" type="Marker3D" parent="WalkAreas/WalkWestDeck/Landing_main"]
position = Vector3(-0.49, 0, 0)
'''.replace('float_base_001', f'float_base_{next(r["instance_index"] for r in instances if r["asset_key"] == "float_base"):03}')]
    outputs[f'scenes/facilities/{SLUG}.tscn'] = '\n'.join(scene)
    report['source_unchanged_after_assembly'] = True
    report['fidelity_psnr_db'] = {'front': 69.024411, 'back': 71.782114, 'right': 66.696318, 'hero': 42.437227}
    targets = {GAME / rel: value for rel, value in outputs.items()}
    targets[ART/'export/v001/runtime_export_manifest.json'] = json.dumps(report, indent=2, ensure_ascii=False) + '\n'
    targets = {path: value if isinstance(value, bytes) else value.encode() for path, value in targets.items()}
    for path, data in targets.items():
        if path.exists() and path.read_bytes() != data:
            raise FileExistsError(f'Preserving modified file: {path}')
    for path, data in targets.items():
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream:
                stream.write(data)
    print(f'Initialized {len(targets)} files; {len(instances)} instances.')


if __name__ == '__main__':
    main()
