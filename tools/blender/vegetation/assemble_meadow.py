"""v003: readable broad grass, explicit rooftop mound islands and unchanged solar flowers."""
import json,math,random,re
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v003'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p,v):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def text(p,v):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(v,encoding='utf-8')
recipe=read(D/'layout_recipes.json');catalog=read(R/'godot/data/vegetation/catalog.json')
history=R/'art_source/vegetation/v002/solar_cabin_layout_baked.json'
if not history.exists():history.write_bytes((R/'godot/data/vegetation/layouts/solar_cabin.json').read_bytes())
for key,displacement,row in [('grass_soft',.20,0.0),('mound_soft',.30,.5)]:
 catalog[key]=dict(asset_id='SEA-VEG-'+key.upper().replace('_','-'),model=f'res://assets/models/vegetation/{key}.glb',material=f'res://assets/materials/vegetation/{key}.tres',profile='broad_card_v003',characteristic_height=.48 if key=='grass_soft' else 1.2,shadow=False)
 text(R/f'godot/assets/materials/vegetation/{key}.tres',f'''[gd_resource type="ShaderMaterial" load_steps=3 format=3]
[ext_resource type="Shader" path="res://shaders/vegetation/soft_cards.gdshader" id="shader"]
[ext_resource type="Texture2D" path="res://assets/textures/vegetation/meadow_atlas.png" id="atlas"]
[resource]
shader = ExtResource("shader")
shader_parameter/botanical_atlas = ExtResource("atlas")
shader_parameter/moss_layer = false
shader_parameter/atlas_row = {row}
shader_parameter/wind_displacement = {displacement}
shader_parameter/tint = Color(0.94, 0.98, 0.88, 1)
''')
 text(R/f'godot/scenes/components/vegetation/{key}.tscn',f'''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://src/ambient/vegetation/piece.gd" id="piece"]
[node name="{key}" type="Node3D"]
script = ExtResource("piece")
asset_key = "{key}"
metadata/asset_id = "{catalog[key]['asset_id']}"
metadata/visual_only = true
metadata/water_layer = "surface"
metadata/water_layer_role = "none"
''')
write(R/'godot/data/vegetation/catalog.json',catalog)
contract_path=R/'godot/assets/materials/shader_param_contract.json';contract=read(contract_path)
for key,displacement,row in [('grass_soft',.20,0.0),('mound_soft',.30,.5)]:
 contract['materials'][f'godot/assets/materials/vegetation/{key}.tres']=dict(shader='res://shaders/vegetation/soft_cards.gdshader',min_params=5,required=['botanical_atlas','moss_layer','atlas_row','wind_displacement','tint'],params=dict(botanical_atlas={'res':'res://assets/textures/vegetation/meadow_atlas.png'},moss_layer='false',atlas_row=str(row),wind_displacement=str(displacement),tint='Color(0.94, 0.98, 0.88, 1)'))
write(contract_path,contract)

for scope in ['solar_cabin','rooftop_ranch']:
 rng=random.Random(110503);rows=[];regions=recipe[scope];cuts=[cut for region in regions for cut in region['exclusions']]
 def add(key,p,s,yaw,tag):
  rows.append(dict(id=f'{scope}/{tag}/{len(rows):05d}',asset=key,position=[round(v,5) for v in p],scale=[round(v,5) for v in s],yaw=round(yaw,5),phase=round(rng.random(),6),variation=round(rng.random(),6)))
 for region in regions:
  x0,z0,x1,z1=region['rect'];step=region['spacing'];h=region['y']
  for ix in range(math.ceil((x1-x0)/step)):
   for iz in range(math.ceil((z1-z0)/step)):
    x=x0+(ix+.5+rng.uniform(-.28,.28))*step;z=z0+(iz+.5+rng.uniform(-.28,.28))*step
    if x>x1-.025 or z>z1-.025:continue
    if any(c['rect'][0]<=x<=c['rect'][2] and c['rect'][1]<=z<=c['rect'][3] for c in region['exclusions']):continue
    scale=rng.uniform(.82,1.08)
    add('grass_soft',[x,h+.002,z],[scale,rng.uniform(.80,1.13),scale],rng.random()*math.tau,region['id']+'/grass')
 if scope=='solar_cabin':
  # Preserve all existing moss points; original flowers and bushes are not touched.
  rows += [item for item in read(history)['instances'] if item['asset']=='moss_soft']
 else:
  placements=[]
  def safe(x,z,size):
   radius=1.65*size
   if abs(x)+radius>23.35 or abs(z)+radius>15.35:return False
   for c in cuts:
    a,b,d,e=c['rect']
    if x+radius>a and x-radius<d and z+radius>b and z-radius<e:return False
   return all((x-p[0])**2+(z-p[1])**2>3.0 for p in placements)
  for x,y,z,size in recipe['mounds']:
   candidates=sorted([(x+dx*.5,z+dz*.5) for dx in range(-6,7) for dz in range(-6,7)],key=lambda p:(p[0]-x)**2+(p[1]-z)**2)
   pos=next((p for p in candidates if safe(p[0],p[1],size)),None)
   if pos is None:continue
   placements.append(pos);add('mound_soft',[pos[0],y,pos[1]],[size,size,size],rng.random()*math.tau,'mound')
 rng.shuffle(rows)
 data=dict(schema_version=3,wind_contract=3,scope=scope,seed=110503,chunk_metres=8 if scope=='rooftop_ranch' else 4,regions=regions,instances=rows)
 write(R/f'godot/data/vegetation/layouts/{scope}.json',data);write(D/f'{scope}_layout_baked.json',data)
 print(scope,dict(instances=len(rows),grass=sum(i['asset']=='grass_soft' for i in rows),mounds=sum(i['asset']=='mound_soft' for i in rows)))

# Only attach the new visual layer to the existing hand-authored scene.
p=R/'godot/scenes/facilities/rooftop_ranch.tscn';s=p.read_text(encoding='utf-8')
if 'id="vegetation"' not in s:
 idx=min(i for token in ['[sub_resource','[node '] if (i:=s.find(token))>=0)
 s=s[:idx]+'[ext_resource type="Script" path="res://src/ambient/vegetation/patch.gd" id="vegetation"]\n\n'+s[idx:]
 s=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m[1])+1),s,count=1)
 s+='\n[node name="VegetationTurf" type="Node3D" parent="."]\nscript = ExtResource("vegetation")\nlayout_path = "res://data/vegetation/layouts/rooftop_ranch.json"\nmetadata/visual_only = true\nmetadata/water_layer = "surface"\nmetadata/water_layer_role = "none"\n'
# Old rooftop hard grass remains traceable but stops drawing on top of the broad leaf carpet.
s=re.sub(r'(\[node name="ORF2_实例_(?:grass|tuft)(?:\.\d+)?"[^\n]+\]\n)(?!visible = false)',r'\1visible = false\nmetadata/vegetation_replaced = true\n',s)
p.write_text(s,encoding='utf-8')
