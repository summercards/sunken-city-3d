"""Create the new packed assembly and independently maintainable component wrappers."""
import hashlib,json,math,shutil
from pathlib import Path

root=Path(__file__).resolve().parents[3]
source=root/'art_source/scenes/neon_garden_quarter/v003'
game=root/'godot'
plan=json.loads((source/'component_plan.json').read_text(encoding='utf8'))
catalog=json.loads((source/'component_catalog.json').read_text(encoding='utf8'))['components']
instances=json.loads((source/'component_instances.json').read_text(encoding='utf8'))['instances']
export=json.loads((source/'export/v003/export_manifest.json').read_text(encoding='utf8'))

def write_new(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists():assert path.read_text(encoding='utf8')==text,f'Review existing hand edits: {path}'
    else:path.write_text(text,encoding='utf8')

def matrix(row,center):
    ax,ay,az=row['euler_xyz'];cx,sx=math.cos(ax),math.sin(ax);cy,sy=math.cos(ay),math.sin(ay);cz,sz=math.cos(az),math.sin(az)
    rotation=((cz*cy,cz*sy*sx-sz*cx,cz*sy*cx+sz*sx),(sz*cy,sz*sy*sx+cz*cx,sz*sy*cx-cz*sx),(-sy,cy*sx,cy*cx))
    scale=row['scale']
    # Blender basis mapped by C B C^-1. Variant text serializes the basis by rows.
    columns=[]
    for j,sign in [(0,1),(2,1),(1,-1)]:
        col=[sign*rotation[i][j]*scale[j] for i in range(3)];columns.append([col[0],col[2],-col[1]])
    values=[columns[j][i] for i in range(3) for j in range(3)]
    x,y,z=row['location'];values.extend([x-center[0],z,-y+center[1]])
    return 'Transform3D('+', '.join(format(value,'.10g') for value in values)+')'

atlas=game/'assets/textures/facilities/neon_garden_quarter/poster_atlas.png'
atlas.parent.mkdir(parents=True,exist_ok=True)
if not atlas.exists():shutil.copyfile(root/plan['poster_source'],atlas)
assert atlas.read_bytes()==(root/plan['poster_source']).read_bytes()

records={item['key']:item for item in export['components']}
wrapper_dir='scenes/components/facilities/neon_garden_quarter'
for item in catalog:
    key=item['key'];record=records[key];glb='res://'+record['glb'].removeprefix('godot/')
    wrapper=f'{wrapper_dir}/{key}.tscn'
    write_new(game/wrapper,f'''[gd_scene format=3]

[ext_resource type="PackedScene" path="{glb}" id="visual"]

[node name="{key}" type="Node3D"]
metadata/asset_id = "{item['asset_id']}"
metadata/asset_version = "v003"

[node name="Visual" parent="." instance=ExtResource("visual")]
''')
    record['prefab']='godot/'+wrapper
    # Editor-generated remap metadata is completed on first import. These parameters are stable.
    path=(root/record['glb']).with_suffix('.glb.import')
    if not path.exists():
        cache=f'res://.godot/imported/{key}.glb-{hashlib.md5(glb.encode()).hexdigest()}.scn'
        path.write_text(f'''[remap]

importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"

[deps]

source_file="{glb}"
dest_files=["{cache}"]

[params]

animation/import=false
meshes/generate_lods=false
meshes/create_shadow_meshes=true
import_script/path="res://tools/neon_garden_quarter_import.gd"
gltf/embedded_image_handling=0
''',encoding='utf8')

center=(6.,1.)  # Midpoint between the left/right wing centers in Blender XY.
lines=['[gd_scene format=3]','','[ext_resource type="Script" path="res://src/world/neon_garden_quarter.gd" id="quarter"]','[ext_resource type="Script" path="res://src/world/blocker_set.gd" id="blockers"]','[ext_resource type="Script" path="res://src/navigation/walk_area.gd" id="walk"]','[ext_resource type="Script" path="res://src/navigation/landing_point.gd" id="landing"]']
for item in catalog:
    key=item['key'];lines.append(f'[ext_resource type="PackedScene" path="res://{wrapper_dir}/{key}.tscn" id="{key}"]')
lines+=['','[node name="NeonGardenQuarter" type="Node3D"]','script = ExtResource("quarter")','zone_id = "neon_garden_quarter"','zone_label = "霓虹花园街区"','water_layer = "surface"','metadata/asset_id = "SEA-SCENE-NGQ-ASSEMBLY"','metadata/asset_version = "v003"','metadata/building_class = "above_water"','', '[node name="Visual" type="Node3D" parent="."]','']
for i,row in enumerate(instances):
    key=row['key'];name='Foundation' if key=='fractured_ground' else f'{key}_{i:03d}'
    lines.extend([f'[node name="{name}" parent="Visual" instance=ExtResource("{key}")]',f'transform = {matrix(row,center)}',''])
lines+=['''[node name="Blockers" type="Node3D" parent="."]
script = ExtResource("blockers")
target_path = NodePath("../Visual/Foundation")
cell = 0.5

[node name="WalkAreas" type="Node3D" parent="."]

[node name="WalkStreetLanding" type="Node3D" parent="WalkAreas"]
script = ExtResource("walk")
area_id = "neon_garden_street_landing"
zone_id = "neon_garden_quarter"
surface_y = 1.42
span_min = 1.30
span_max = 1.56
rects = [Rect2(1, 7.45, 6.5, 2.95)]

[node name="Landing_main" type="Marker3D" parent="WalkAreas/WalkStreetLanding"]
position = Vector3(4.5, 0.3, 9.25)
script = ExtResource("landing")
landing_label = "霓虹花园街口"

[node name="BoatPark" type="Marker3D" parent="WalkAreas/WalkStreetLanding/Landing_main"]
position = Vector3(0, -0.3, 5.5)

[node name="DockEdge" type="Marker3D" parent="WalkAreas/WalkStreetLanding/Landing_main"]
position = Vector3(0, 0, 1.55)
''']
write_new(game/'scenes/facilities/neon_garden_quarter.tscn','\n'.join(lines))
export.update(runtime_assembly='godot/scenes/facilities/neon_garden_quarter.tscn',assembly_anchor_blender=[*center,0],expected_instances=len(instances))
(source/'export/v003/export_manifest.json').write_text(json.dumps(export,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
