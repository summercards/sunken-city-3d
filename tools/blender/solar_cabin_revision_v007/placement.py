from pathlib import Path
R=Path(__file__).resolve().parents[3]
s=(R/'tools/blender/solar_cabin_revision_v006/placement.py').read_text(encoding='utf-8').replace('v006','v007').replace('solar_cabin_v1.3','solar_cabin_v1.4').replace('bloom_lower_building/v001','bloom_lower_building/v002')
s=s.replace("scene['uniform_source_scale']=1.15", """# Preserve the user's current Godot-local submerged-base placement in the reference assembly.
import re
facility=(R/'godot/scenes/facilities/solar_cabin.tscn').read_text(encoding='utf-8')
base_section=facility.split('instance=ExtResource(\"base\")]')[1]
match=re.search(r'transform = Transform3D\\(([^)]+)\\)',base_section)
if match:
 vals=[float(x.strip()) for x in match.group(1).split(',')]
 gm=Matrix(((vals[0],vals[3],vals[6],vals[9]),(vals[1],vals[4],vals[7],vals[10]),(vals[2],vals[5],vals[8],vals[11]),(0,0,0,1)))
 for obj in base.objects:obj.matrix_world=C.inverted()@gm@C@obj.matrix_world
scene['uniform_source_scale']=1.15""")
exec(compile(s,__file__,'exec'))
