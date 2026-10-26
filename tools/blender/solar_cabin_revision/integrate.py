"""Targeted revision of current facility and its affected placement contracts."""
from pathlib import Path
import json,re,math
R=Path(__file__).resolve().parents[3];G=R/'godot';D=R/'art_source/scenes/sunny_bloom_retreat/v004/export/v001';W=R.parent/'sea-work/solar_cabin_revision_v004';report=json.loads((D/'export_manifest.json').read_text())
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def js(p,v):write(p,json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def point(x,y):
 x=-.72+(x+.72)*1.5;y=.96+(y-.96)*1.5
 return [5.128+1.15*x,2.15,.704-1.15*y]
def rect(x0,x1,y0,y1):
 a=point(x0,y1);b=point(x1,y0);return [a[0],a[2],b[0]-a[0],b[2]-a[2]]
def v3(p):return 'Vector3('+', '.join(f'{v:.6f}' for v in p)+')'
for e in report['components']:
 p=G/f'scenes/components/solar_cabin/{e["key"]}.tscn';write(p,f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{e['glb'].removeprefix('godot/')}" id="visual"]
[node name="{e['name']}" type="Node3D"]
script = ExtResource("bind")
metadata/asset_id = "{e['asset_id']}"
[node name="Visual" parent="." instance=ExtResource("visual")]
''');e['prefab']=str(p.relative_to(R))
# Four separately selectable modules share the same component library.
script=G/'src/world/sunny_bloom_visual.gd';s=script.read_text();s=s.replace('var component_meshes := 0','@export var module_key: String = ""\nvar component_meshes := 0')
s=s.replace(' for entry in data.instances:\n',' for entry in data.instances:\n  if module_key != "" and entry.get("module", "") != module_key: continue\n');script.write_text(s)
parts=[('rear_building','后部方形建筑'),('solar_room','前部倾斜太阳能房'),('front_platform','前方可行动平台-酒红'),('bridge','栈桥-暖木')]
for key,name in parts:
 write(G/f'scenes/facilities/solar_cabin_{key}.tscn',f'''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://src/world/sunny_bloom_visual.gd" id="1"]
[node name="太阳能木屋-{name}" type="Node3D"]
script = ExtResource("1")
module_key = "{key}"
metadata/module = "{key}"
metadata/deck_height = 2.15
''')
s='[gd_scene load_steps=5 format=3]\n'
for key,name in parts:s+=f'[ext_resource type="PackedScene" path="res://scenes/facilities/solar_cabin_{key}.tscn" id="{key}"]\n'
s+='[node name="太阳能木屋-海上区域" type="Node3D"]\nmetadata/asset_id = "SEA-SCENE-SBR-ASSEMBLY"\nmetadata/front_godot = Vector3(0, 0, 1)\nmetadata/deck_height = 2.15\n'
for key,name in parts:s+=f'[node name="{name}" parent="." instance=ExtResource("{key}")]\n'
write(G/'scenes/facilities/solar_cabin_surface.tscn',s)
# This material change is bounded to the newly assigned berry swatch. No
# palette image change and no unrelated scene shader change.
for filename in ['sunny_palette.gdshader','sunny_palette_gloss.gdshader']:
 p=G/'shaders'/filename;s=p.read_text();s=s.replace(' ALBEDO=hsv2rgb(hsv);',''' ALBEDO=hsv2rgb(hsv);
 if (ivec2(floor(UV*8.0))==ivec2(5,5)) {
  vec3 wine=rgb2hsv(ALBEDO);wine.x=fract(wine.x+0.067);wine.y*=0.95;wine.z*=0.75;
  ALBEDO=hsv2rgb(wine);
 }''');p.write_text(s)
# Open left apron and main bridge are walkable; the right lounge stays furnished.
walks=[rect(-3.72,.65,-5.87,-4.02),rect(-3.72,-.80,-4.10,-2.65),rect(-2.59,-.28,-8.66,-5.62)]
stand=point(-1.435,-8.14);edge=point(-1.435,-8.75);park=[stand[0],1.12,edge[2]+2.6];plot=point(-3.05,-3.35)
scene=G/'scenes/zones/zone1_home_harbor.tscn';s=scene.read_text();a=s.index('[node name="Walk_zone1_home_dock"');b=s.index('[node name="Walk_zone1_salvage"');block=s[a:b];block=re.sub(r'^rects = .*$', 'rects = ['+', '.join('Rect2('+', '.join(f'{v:.6f}' for v in r)+')' for r in walks)+']',block,flags=re.M);block=re.sub(r'^polygons = .*$', 'polygons = []',block,flags=re.M);s=s[:a]+block+s[b:]
a=s.index('[node name="Landing_main"');b=s.index('[node name="Landing_salvage"');block=s[a:b]
for name,pos in [('Landing_main',stand),('BoatPark',[park[i]-stand[i] for i in range(3)]),('DockEdge',[edge[i]-stand[i] for i in range(3)])]:
 block=re.sub(r'(\[node name="'+name+r'"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3(pos),block)
s=s[:a]+block+s[b:];s=re.sub(r'(\[node name="home_plot"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3(plot),s);scene.write_text(s)
zones=json.loads((G/'assets/data/zones.json').read_text());z=next(x for x in zones if x['id']=='zone1');z['hover']=[4.3,8.0,-.4];z['camera']=[4.3,4.0,4.2];land=next(x for x in z['landings'] if x['id']=='main');land.update(landStand=stand,dockEdge=edge,boatPark=park,boatYaw=math.pi/2);walk=next(x for x in z['walk'] if x['id']=='zone1_home_dock');walk['rects']=[[r[0],r[0]+r[2],r[1],r[1]+r[3]] for r in walks];walk['polygons']=[];js(G/'assets/data/zones.json',zones)
build=json.loads((G/'assets/data/build_sites.json').read_text());home=next(x for x in build['sites'] if x['id']=='home_cabin');p=point(-1.0,-3.2);home.update(x=p[0],y=p[1],z=p[2]);js(G/'assets/data/build_sites.json',build)
gather=json.loads((G/'assets/data/gather_spots.json').read_text())
for e in gather['spots']:
 if e['id'] in ['zone1_shell','zone1_wood']:
  p=point(.20,-5.45) if e['id']=='zone1_shell' else point(-1.0,-3.6);e.update(x=p[0],y=p[1],z=p[2])
js(G/'assets/data/gather_spots.json',gather)
shore=json.loads((G/'assets/baked/shore.json').read_text());shore['shapes']=[x for x in shore['shapes'] if x.get('asset_id')!='SEA-SCENE-SBR-ASSEMBLY']
for r in [rect(-3.9,3.6,-6.0,3.4),rect(-2.675,-.195,-8.7475,-6.0)]:shore['shapes'].append(dict(x=r[0]+r[2]*.5,z=r[1]+r[3]*.5,hx=r[2]*.5,hz=r[3]*.5,round=False,asset_id='SEA-SCENE-SBR-ASSEMBLY'))
js(G/'assets/baked/shore.json',shore);js(D/'export_manifest.json',report);js(W/'integration.json',dict(version='1.1',source_revision='v004',scale_over_previous=1.5,total_scale=1.725,front_godot='+Z',deck_height=2.15,stand=stand,edge=edge,park=park,home_plot=plot,walk_rects=walks,modules=parts))
print('Integrated four semantic parts, aligned walk/landing/shore, retained right lounge')
