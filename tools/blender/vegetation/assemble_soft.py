"""Bake dense soft-card turf for the solar cabin only; original flora stays untouched."""
import json,math,random
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v002'
assert not (R/'art_source/vegetation/v003/component_plan.json').exists(), 'v002 is historical; use assemble_meadow.py.'
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def text(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(v,encoding='utf-8')
recipes=[dict(id='upper_roof_meadow',rect=[4.69,-2.66,8.98,1.03],y=10.847,spacing=.105,exclusions=[dict(id='aircon_service',rect=[6.13,-2.05,8.28,.12])]),dict(id='left_parapet',rect=[-.17,-2.7,.25,2.30],y=7.895,spacing=.105,exclusions=[]),dict(id='front_parapet',rect=[.55,2.50,3.25,2.95],y=7.895,spacing=.105,exclusions=[])]
recipe_path=D/'layout_recipes.json'
if recipe_path.exists():recipes=json.loads(recipe_path.read_text(encoding='utf-8'))['regions']
else:write(recipe_path,dict(schema_version=2,scope='solar_cabin',regions=recipes,coordinate_space='facility local Godot XYZ, actual supporting top surface'))
rng=random.Random(110502);rows=[]
def add(key,p,s,yaw=0,tag=''):
 rows.append(dict(id=f'solar_cabin/{tag}/{len(rows):05d}',asset=key,position=[round(v,5) for v in p],scale=[round(v,5) for v in s],yaw=round(yaw,5),phase=round(rng.random(),6),variation=round(rng.random(),6)))
for r in recipes:
 x0,z0,x1,z1=r['rect'];step=r['spacing'];h=r['y']
 for ix in range(math.ceil((x1-x0)/step)):
  for iz in range(math.ceil((z1-z0)/step)):
   x=x0+(ix+.5+rng.uniform(-.33,.33))*step;z=z0+(iz+.5+rng.uniform(-.33,.33))*step
   if x>x1-.025 or z>z1-.025:continue
   if any(a['rect'][0]<=x<=a['rect'][2] and a['rect'][1]<=z<=a['rect'][3] for a in r['exclusions']):continue
   scale=rng.uniform(.85,1.20);height=rng.uniform(1.05,1.6)
   add('grass_soft',[x,h+.002,z],[scale,height,scale],rng.random()*math.tau,r['id']+'/grass')
 # Small textured groundcover patches overlap under the blades, never a solid plinth.
 for ix in range(math.ceil((x1-x0)/.32)):
  for iz in range(math.ceil((z1-z0)/.32)):
   x=x0+(ix+.5)*.32;z=z0+(iz+.5)*.32
   if x>x1-.04 or z>z1-.04:continue
   if any(a['rect'][0]-.04<=x<=a['rect'][2]+.04 and a['rect'][1]-.04<=z<=a['rect'][3]+.04 for a in r['exclusions']):continue
   size=rng.uniform(.40,.56)
   # Keep moss footprint inside narrow ledges.
   size=min(size,(x1-x0)*.9,(z1-z0)*.9)
   add('moss_soft',[x,h+.003+rng.random()*.002,z],[size,1,size],rng.random()*math.tau,r['id']+'/moss')
# Restrained decorative stains beside existing plants at the front edge of the deck.
for x,y,z,size in [(10.92,2.15,5.47,.33),(10.98,2.15,5.90,.25),(1.14,7.236,2.22,.24),(3.32,7.236,2.27,.21)]:
 add('moss_soft',[x,y+.004,z],[size,1,size],rng.random()*math.tau,'moss_accents')
rng.shuffle(rows)
write(R/'godot/data/vegetation/layouts/solar_cabin.json',dict(schema_version=2,wind_contract=2,seed=110502,scope='solar_cabin',chunk_metres=4,regions=recipes,instances=rows))
catalog={}
for key,triangles in [('grass_soft',18),('moss_soft',8)]:
 aid='SEA-VEG-'+key.upper().replace('_','-')
 catalog[key]=dict(asset_id=aid,model=f'res://assets/models/vegetation/{key}.glb',material=f'res://assets/materials/vegetation/{key}.tres',profile='textured_card',characteristic_height=.16,shadow=False)
 text(R/f'godot/scenes/components/vegetation/{key}.tscn',f'''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://src/ambient/vegetation/piece.gd" id="piece"]
[node name="{key}" type="Node3D"]
script = ExtResource("piece")
asset_key = "{key}"
metadata/asset_id = "{aid}"
metadata/visual_only = true
metadata/water_layer = "surface"
metadata/water_layer_role = "none"
''')
 moss=key=='moss_soft'
 text(R/f'godot/assets/materials/vegetation/{key}.tres',f'''[gd_resource type="ShaderMaterial" load_steps=3 format=3]
[ext_resource type="Shader" path="res://shaders/vegetation/soft_cards.gdshader" id="shader"]
[ext_resource type="Texture2D" path="res://assets/textures/vegetation/soft_atlas.png" id="atlas"]
[resource]
shader = ExtResource("shader")
shader_parameter/botanical_atlas = ExtResource("atlas")
shader_parameter/moss_layer = {'true' if moss else 'false'}
shader_parameter/wind_displacement = {0.0 if moss else 0.055}
shader_parameter/tint = Color(0.84, 0.94, 0.79, 1)
''')
write(R/'godot/data/vegetation/catalog.json',catalog)
print('SOFT_LAYOUT_OK',len(rows),'grass',sum(x['asset']=='grass_soft' for x in rows),'moss',sum(x['asset']=='moss_soft' for x in rows))
