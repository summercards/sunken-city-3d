"""Bake editable turf regions and explicit stable instances. Only these two consumers."""
import json,random,math,re,hashlib,argparse
from pathlib import Path
R=Path(__file__).resolve().parents[3]
P=json.loads((R/'art_source/vegetation/v001/component_plan.json').read_text(encoding='utf-8'))
assert not (R/'art_source/vegetation/v001/REJECTED.md').exists(), 'v001 retired. Use assemble_soft.py for the current approved scope.'
def write(p,v):
 p=R/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def text(p,v):
 p=R/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(v,encoding='utf-8')
def emit_catalog():
 cat={}
 for e in P['components']:
  k=e['key'];profile=e['profile']
  cat[k]=dict(asset_id=e['asset_id'],model=f'res://assets/models/vegetation/{k}.glb',material=f'res://assets/materials/vegetation/{profile}.tres',profile=profile)
  text(f'godot/scenes/components/vegetation/{k}.tscn',f'''[gd_scene load_steps=2 format=3]
 [ext_resource type="Script" path="res://src/ambient/vegetation/piece.gd" id="piece"]
 [node name="{k}" type="Node3D"]
 script = ExtResource("piece")
 asset_key = "{k}"
 metadata/asset_id = "{e['asset_id']}"
 metadata/water_layer = "surface"
 metadata/water_layer_role = "none"
 metadata/visual_only = true
 ''')
 write('godot/data/vegetation/catalog.json',cat)
 contract_path=R/'godot/assets/materials/shader_param_contract.json';contract=json.loads(contract_path.read_text(encoding='utf-8'))
 for profile,angle,light in [('grass',.38,.22),('mound',.18,.15),('leaf',.28,.2),('flower',.20,.18),('base',0,.0)]:
  p=f'godot/assets/materials/vegetation/{profile}.tres'
  text(p,f'''[gd_resource type="ShaderMaterial" load_steps=3 format=3]
 [ext_resource type="Shader" path="res://shaders/vegetation/foliage.gdshader" id="shader"]
 [ext_resource type="Texture2D" path="res://assets/textures/shared/sea_cabin_timber_8x8_512.png" id="palette"]
 [resource]
 resource_name = "SEA_Vegetation_{profile}"
 shader = ExtResource("shader")
 shader_parameter/palette = ExtResource("palette")
 shader_parameter/bend_angle = {angle}
 shader_parameter/roughness_value = 0.92
 shader_parameter/soft_light = {light}
 ''')
  contract['materials'][p]=dict(shader='res://shaders/vegetation/foliage.gdshader',min_params=4,required=['palette','bend_angle','roughness_value','soft_light'],params=dict(palette={'res':'res://assets/textures/shared/sea_cabin_timber_8x8_512.png'},bend_angle=str(angle),roughness_value='0.92',soft_light=str(light)))
 write('godot/assets/materials/shader_param_contract.json',contract)
 

# Authored recipe is tracked; regeneration never requires an external capture directory.
recipe=json.loads((R/'art_source/vegetation/v001/layout_recipes.json').read_text(encoding='utf-8'))
regions=recipe['rooftop_ranch'];solar=recipe['solar_cabin']
def bake(scope,regions):
 rng=random.Random(20261105);rows=[]
 def add(asset,pos,scale,yaw=0,tag=''):
  rows.append(dict(id=f'{scope}/{tag}/{len(rows):05d}',asset=asset,position=[round(v,5) for v in pos],scale=[round(v,5) for v in scale],yaw=round(yaw,5),phase=round(rng.random(),6)))
 for region in regions:
  x0,z0,x1,z1=region['rect'];h=region['y'];spacing=region['spacing']
  if region['base']=='turf_pad':add('turf_pad',[(x0+x1)/2,h-.03,(z0+z1)/2],[x1-x0,1,z1-z0],tag=region['id']+'/cover')
  for ix in range(math.ceil((x1-x0)/spacing)):
   for iz in range(math.ceil((z1-z0)/spacing)):
    x=x0+(ix+.5+rng.uniform(-.38,.38))*spacing;z=z0+(iz+.5+rng.uniform(-.38,.38))*spacing
    if x>x1-.12 or z>z1-.12:continue
    if any(a['rect'][0]<=x<=a['rect'][2] and a['rect'][1]<=z<=a['rect'][3] for a in region['exclusions']):continue
    s=rng.uniform(.65,1.05)
    add('grass_fine' if rng.random()<.6 else 'grass_round',[x,h+.009,z],[s,s,s],rng.random()*math.tau,region['id']+'/grass')
 if scope=='rooftop_ranch':
  # Border islands avoid the center's farming and circulation space.
  for x,z,s in [(-20,-12,1.8),(-18,-13,2.0),(-14,-13,1.6),(-3,-12.7,1.65),(2,-13,1.7),(12,-11.8,1.3),(21,-4,1.5),(21,6,1.8),(19,12.7,1.8),(15,13,1.7),(8,13,1.6),(3,12.6,1.4),(-6,11.8,1.6),(-13,11.8,1.4),(-21,7.5,1.4),(-21,3.2,1.6)]:
   add('mound_round' if rng.random()<.5 else 'mound_spread',[x,60.05,z],[s,s,s],rng.random()*math.tau,'mound')
   if rng.random()<.65:add('daisy',[x+.3,60.08,z+.1],[.8,.8,.8],rng.random()*math.tau,'flowers')
  for position in recipe['potted_plant_roots']:
   add('broadleaf',position,[1.2,1.2,1.2],rng.random()*math.tau,'pot')
 rng.shuffle(rows) # Stable prefix thinning stays spatially distributed inside each chunk.
 doc=dict(schema_version=1,wind_contract=1,seed=20261105,scope=scope,chunk_metres=8,regions=regions,instances=rows)
 write(f'godot/data/vegetation/layouts/{scope}.json',doc)
 return doc
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--layout-only',action='store_true',help='Preserve tuned shared materials and catalog.')
 parser.add_argument('--scope',help='Bake a new facility scope from --recipe.')
 parser.add_argument('--recipe',type=Path,help='JSON with a regions array in facility-local Godot coordinates.')
 args=parser.parse_args()
 if not args.layout_only:emit_catalog()
 if args.scope:
  assert args.recipe and re.fullmatch('[a-z0-9_]+',args.scope),'New scope needs --recipe and a safe scope name.'
  bake(args.scope,json.loads(args.recipe.read_text(encoding='utf-8'))['regions'])
 else:
  bake('rooftop_ranch',regions);bake('solar_cabin',solar)
 print('Vegetation baked layouts written; no runtime plugin required.')
