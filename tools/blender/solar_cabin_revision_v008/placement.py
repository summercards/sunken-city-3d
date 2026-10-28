from pathlib import Path
R=Path(__file__).resolve().parents[3]
s=(R/'tools/blender/solar_cabin_revision_v006/placement.py').read_text(encoding='utf-8').replace('v006','v008').replace('solar_cabin_v1.3','solar_cabin_v1.5').replace('bloom_lower_building/v001','bloom_lower_building/v002')
injection='''
import re
facility=(R/'godot/scenes/facilities/solar_cabin.tscn').read_text(encoding='utf-8')
for marker,collection in [('surface',surface),('base',base)]:
 section=facility.split('instance=ExtResource("'+marker+'")]')[1].split('[node')[0]
 match=re.search(r'transform = Transform3D\\(([^)]+)\\)',section)
 if match:
  v=[float(x.strip()) for x in match.group(1).split(',')];g=Matrix(((v[0],v[3],v[6],v[9]),(v[1],v[4],v[7],v[10]),(v[2],v[5],v[8],v[11]),(0,0,0,1)))
  for child in collection.all_objects:child.matrix_world=C.inverted()@g@C@child.matrix_world
'''
s=s.replace("scene['uniform_source_scale']=1.15",injection+"\nscene['uniform_source_scale']=1.15")
exec(compile(s,__file__,'exec'))
