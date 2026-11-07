"""Incremental, one-time scene import. Never regenerate an authored main scene."""
import argparse,hashlib,json,math,os,re,shutil,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/gift_kiosk/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def gltf(path):
 raw=path.read_bytes();length,kind=struct.unpack_from('<II',raw,12);assert kind==0x4E4F534A
 doc=json.loads(raw[20:20+length]);assert not doc.get('images') and not doc.get('textures'),str(path)+' embedded image'
 return doc

def f(v):return format(float(v),'.9g')
def xf(row):
 # Full Euler XYZ mapping: C*Rx*Ry*Rz*C^-1 (Blender Euler XYZ uses Rz*Ry*Rx).
 x,y,z=row['rotation_euler_xyz'];cx,sx=math.cos(x),math.sin(x);cy,sy=math.cos(y),math.sin(y);cz,sz=math.cos(z),math.sin(z)
 b=[[cz*cy,cz*sy*sx-sz*cx,cz*sy*cx+sz*sx],[sz*cy,sz*sy*sx+cz*cx,sz*sy*cx-cz*sx],[-sy,cy*sx,cy*cx]]
 c=[[1,0,0],[0,0,1],[0,-1,0]]
 mm=lambda a,b:[[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
 b=[[b[i][j]*row['scale'][j] for j in range(3)] for i in range(3)];b=mm(mm(c,b),[list(x) for x in zip(*c)])
 # TSCN's 12-float Transform3D representation serializes basis rows. Godot's
 # Basis(Vector3,Vector3,Vector3) constructor instead takes columns.
 p=row['position'];vals=[b[i][j] for i in range(3) for j in range(3)]+[p[0],p[2],-p[1]]
 return 'Transform3D('+', '.join(f(v) for v in vals)+')'

def walk_rects():
 # Exact sparse partition: rounded deck minus store walls and actual prop feet.
 outer=8.26;inner=5.68
 base=[(-outer,5.68,outer*2,outer-5.68),(-outer,-outer,outer*2,outer-inner),(-outer,-inner,outer-inner,inner*2),(inner,-inner,outer-inner,inner*2),(-4.0,-4.0,8.0,8.0),(-1.13,3.9,2.26,2.1)]
 obstacles=[(-3.42,5.78,1.24,1.1),(-1.95,5.59,1.18,.93),(1.16,5.61,.69,.76),(5.32,1.90,1.22,2.27), # rack/mailbox/bin/ICE
            (-7.62,-1.61,1.14,3.22),(6.48,-2.91,1.14,3.22), # independent bench feet + seats
            (.84,.91,2.94,1.0),(-3.2,7.82,.8,.7),(2.4,7.82,.8,.7)]
 for x in [-7,7]:
  for z in [-7,7]:obstacles.append((x-.62,z-.62,1.24,1.24))
 obstacles.append((-4.76,5.56,.85,.85))
 xs=sorted({round(v,4) for r in base+obstacles for v in [r[0],r[0]+r[2]]}|{-8.26,-7.9,-7.5,-7,-6.7,6.7,7,7.5,7.9,8.26})
 zs=sorted({round(v,4) for r in base+obstacles for v in [r[1],r[1]+r[3]]}|{-8.26,-7.9,-7.5,-7,-6.7,6.7,7,7.5,7.9,8.26})
 inside=lambda p,r:r[0]<p[0]<r[0]+r[2] and r[1]<p[1]<r[1]+r[3]
 rows=[]
 for iz in range(len(zs)-1):
  z0,z1=zs[iz:iz+2];runs=[];start=None
  for ix in range(len(xs)-1):
   x0,x1=xs[ix:ix+2];p=((x0+x1)/2,(z0+z1)/2)
   # Rounded boundary is deliberately inside the real cream deck and rail feet.
   dx=max(abs(p[0])-6.9,0);dz=max(abs(p[1])-6.9,0)
   valid=any(inside(p,r) for r in base) and not any(inside(p,r) for r in obstacles) and dx*dx+dz*dz<=1.36**2
   if valid and start is None:start=x0
   if start is not None and (not valid or ix==len(xs)-2):
    end=x0 if not valid else x1;runs.append((start,z0,end-start,z1-z0));start=None
  for rect in runs:
   joined=False
   for i,previous in enumerate(rows):
    if abs(previous[0]-rect[0])<1e-6 and abs(previous[2]-rect[2])<1e-6 and abs(previous[1]+previous[3]-rect[1])<1e-6:
     rows[i]=(previous[0],previous[1],previous[2],previous[3]+rect[3]);joined=True;break
   if not joined:rows.append(rect)
 return rows,obstacles

def write():
 guard_path=D/'runtime_assembly_receipt.json'
 if guard_path.exists():
  guard=json.loads(guard_path.read_text(encoding='utf-8'))
  changed=[path for path,expected in guard['generated_files'].items() if not (R/path).is_file() or sha(R/path)!=expected]
  assert not changed,'Authored Godot files changed. Refuse regeneration; build an external candidate and review individual changes: '+str(changed)
 manifest=json.loads((D/'export/v001/optimization_manifest.json').read_text(encoding='utf-8'))
 assert manifest.get('exported_components')==47
 assert isinstance(manifest.get('fidelity'),dict) and manifest['fidelity']['passed'],'Fixed-camera fidelity must pass before assembly'
 cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];bykey={e['key']:e for e in cat}
 layout=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
 mats=R/'godot/assets/materials/gift_kiosk';mats.mkdir(parents=True,exist_ok=True)
 palette=R/'godot/assets/textures/shared/sea_cozy_8x8_512.png';assert sha(palette)==sha(R/'art_source/shared/palettes/sea_cozy_8x8_512.png')
 for role,rough,metal in [('matte',.52,0),('metal',.28,.12),('gloss',.13,0),('emission',.35,0)]:
  s='[gd_resource type="StandardMaterial3D" format=3]\n\n[ext_resource type="Texture2D" path="res://assets/textures/shared/sea_cozy_8x8_512.png" id="palette"]\n\n[resource]\nresource_name = "SEA_'+role.capitalize()+'"\nalbedo_texture = ExtResource("palette")\ntexture_filter = 0\nroughness = '+str(rough)+'\nmetallic = '+str(metal)+'\n'
  if role=='gloss':s+='transparency = 1\ncull_mode = 2\nalbedo_color = Color(1, 1, 1, 0.13)\n'
  if role=='emission':s+='emission_enabled = true\nemission_texture = ExtResource("palette")\nemission = Color(1, 1, 1, 1)\nemission_energy_multiplier = 0.65\n'
  (mats/(role+'.tres')).write_text(s,encoding='utf-8')
 lettering=(mats/'metal.tres').read_text(encoding='utf-8')+'disable_receive_shadows = true\n'
 (mats/'metal_lettering.tres').write_text(lettering,encoding='utf-8')
 prefab_dir=R/'godot/scenes/components/facilities/gift_kiosk';prefab_dir.mkdir(parents=True,exist_ok=True)
 for e in cat:
  path=R/f"godot/assets/models/facilities/gift_kiosk/{e['key']}/{e['key']}.glb";doc=gltf(path)
  res='res://'+path.relative_to(R/'godot').as_posix();cache=f"res://.godot/imported/{path.name}-{hashlib.md5(res.encode()).hexdigest()}.scn"
  imp='[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="'+cache+'"\n\n[deps]\nsource_file="'+res+'"\ndest_files=["'+cache+'"]\n\n[params]\nnodes/root_type=""\nnodes/root_name=""\nnodes/apply_root_scale=true\nnodes/root_scale=1.0\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=true\nanimation/import=false\nimport_script/path="res://tools/gift_kiosk_import.gd"\nmaterials/extract=0\n_subresources={}\ngltf/naming_version=2\ngltf/embedded_image_handling=0\n'
  imp_path=Path(str(path)+'.import')
  if not imp_path.exists():imp_path.write_text(imp,encoding='utf-8')
  layer='submerged' if e['building_class']=='underwater' else ('surface' if e['building_class']=='above_water' else 'none')
  body='[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="'+res+'" id="visual"]\n\n[node name="'+e['key']+'" type="Node3D"]\nmetadata/asset_id = "'+e['asset_id']+'"\nmetadata/asset_version = "v001"\nmetadata/water_layer = "'+layer+'"\nmetadata/water_layer_role = "'+('none' if layer=='none' else 'part')+'"\n'
  if e['building_class'] is not None:body+='metadata/building_class = "'+e['building_class']+'"\n'
  if e['building_class']=='underwater':body+='metadata/visual_only = true\n'
  body+='\n[node name="Visual" parent="." instance=ExtResource("visual")]\n'
  (prefab_dir/(e['key']+'.tscn')).write_text(body,encoding='utf-8')
 # New facility is assembled from stable component PackedScenes, never a whole-house GLB.
 header=['[gd_scene format=3]','']
 for e in cat:header.append(f'[ext_resource type="PackedScene" path="res://scenes/components/facilities/gift_kiosk/{e["key"]}.tscn" id="{e["key"]}"]')
 scripts={'structure':'src/facilities/floating_shop_zone.gd','blockers':'src/world/blocker_set.gd','walk':'src/navigation/walk_area.gd','landing':'src/navigation/landing_point.gd','counter':'src/facilities/supply_counter.gd'}
 header += [f'[ext_resource type="Script" path="res://{path}" id="{name}"]' for name,path in scripts.items()]
 body=['','[node name="FloatingGiftKiosk" type="Node3D"]','script = ExtResource("structure")','zone_id = "sea_supply"','zone_label = "海上补给站"','asset_id = "SEA-SCENE-GKS-ASSEMBLY"','role = "shop"','water_layer = "amphibious"','water_layer_role = "entity"','metadata/asset_id = "SEA-SCENE-GKS-ASSEMBLY"','metadata/building_class = "above_water"','metadata/source_version = "v001"','metadata/deck_top_local = 0.3','metadata/deck_size_xz = Vector2(18, 18)','metadata/deck_shape = "rounded_square"','metadata/underwater_architectural_base = false','metadata/component_count = 47','metadata/instance_count = '+str(len(layout)),'','[node name="Visual" type="Node3D" parent="."]']
 for group in ['Structure','Furnishings','Plants','UnderwaterVisual']:
  body += ['',f'[node name="{group}" type="Node3D" parent="Visual"]']
  if group=='UnderwaterVisual':body+=['metadata/visual_only = true','metadata/building_class = "underwater"','metadata/water_layer = "submerged"','metadata/water_layer_role = "part"']
 for row in layout:
  e=bykey[row['key']];group='UnderwaterVisual' if e['building_class']=='underwater' else {'structure':'Structure','furnishing':'Furnishings','plant':'Plants'}[e['group']]
  body+=['',f'[node name="{row["name"]}" parent="Visual/{group}" instance=ExtResource("{row["key"]}")]','transform = '+xf(row)]
 rects,obstacles=walk_rects()
 body+=['','[node name="Blockers" type="Node3D" parent="."]','script = ExtResource("blockers")','mode = "auto"','target_path = NodePath("../Visual/Structure/deck_001")','cell = 0.3','', '[node name="WalkAreas" type="Node3D" parent="."]','','[node name="Walk_sea_supply_deck" type="Node3D" parent="WalkAreas"]','script = ExtResource("walk")','area_id = "sea_supply_deck"','zone_id = "sea_supply"','surface_y = 1.42','span_min = 1.07','span_max = 1.77','rects = ['+', '.join('Rect2('+', '.join(f(v) for v in r)+')' for r in rects)+']','', '[node name="Landing_main" type="Marker3D" parent="WalkAreas/Walk_sea_supply_deck"]','position = Vector3(0, 0.3, 7.9)','script = ExtResource("landing")','landing_label = "海上补给站"','', '[node name="BoatPark" type="Marker3D" parent="WalkAreas/Walk_sea_supply_deck/Landing_main"]','position = Vector3(0, -0.3, 4.3)','', '[node name="DockEdge" type="Marker3D" parent="WalkAreas/Walk_sea_supply_deck/Landing_main"]','position = Vector3(0, 0, 1.1)','', '[node name="Objects" type="Node3D" parent="."]','', '[node name="SupplyCounter" type="Node3D" parent="Objects"]','position = Vector3(0, 0.3, 6.15)','script = ExtResource("counter")','id = "sea_supply_counter"','label = "海上补给站"','verb = "补给"','priority = 4','focus_radius = 2.8','hold_time = 0.0','focus_anchor = "node"']
 for i,p in enumerate([(-2.6,3.1,3.3),(2.6,3.1,3.3),(-3.2,3.1,-2),(3.2,3.1,-2)]):
  body+=['',f'[node name="WarmShopLight{i}" type="OmniLight3D" parent="Objects" groups=["home_lamps"]]','position = Vector3('+', '.join(map(f,p))+')','light_color = Color(1, 0.72, 0.35, 1)','light_energy = 0.8','omni_range = 7.5','omni_attenuation = 1.5']
 new_scene='\n'.join(header+body)+'\n'
 target=R/'godot/scenes/facilities/floating_shop.tscn';backup=W/'before_import';backup.mkdir(exist_ok=True)
 if not (backup/'floating_shop.tscn').exists():shutil.copy2(target,backup/'floating_shop.tscn')
 old=(backup/'floating_shop.tscn').read_text(encoding='utf-8')
 # Old art stays at the exact user-authored transform, with a separate visual-only role.
 rest=old[:old.index('[node name="WalkAreas"')]
 rest=rest.replace('res://src/world/sea_supply_zone.gd','res://src/world/sea_structure.gd')
 for line in rest.splitlines():
  if line.startswith(('zone_id =','zone_label =','water_layer =','water_layer_role =')):rest=rest.replace(line+'\n','')
 rest=rest.replace('role = "shop"','role = "rest_stop"').replace('metadata/classification = "building/shop"','metadata/classification = "building/rest_stop"')
 rest=rest.replace('[node name="海上悬浮商铺"','[node name="OldMarineRestStop"')
 rest=rest.replace('metadata/landing_id = "main"','metadata/water_layer = "amphibious"\nmetadata/water_layer_role = "entity"\nmetadata/building_class = "above_water"\nmetadata/retired_shop = true\nmetadata/activity_role = "navigation_only"\nmetadata/label = "旧海上驿站"')
 (R/'godot/scenes/facilities/floating_rest_stop.tscn').write_text(rest,encoding='utf-8')
 target.write_text(new_scene,encoding='utf-8')
 (D/'runtime_layout_contract.json').write_text(json.dumps({'rects':rects,'prop_obstacles':obstacles,'entry_clear_width_m':2.26,'zone_id':'sea_supply','static_deck_top_local':.3,'motion':'vertical_only'},indent=2)+'\n',encoding='utf-8')
 runtime={'schema':'sea.gift_kiosk.runtime_manifest','version':'v001','components':[{'key':e['key'],'asset_id':e['asset_id'],'prefab':f'res://scenes/components/facilities/gift_kiosk/{e["key"]}.tscn'} for e in cat],'instances':[dict(row,godot_group='UnderwaterVisual' if bykey[row['key']]['building_class']=='underwater' else {'structure':'Structure','furnishing':'Furnishings','plant':'Plants'}[bykey[row['key']]['group']]) for row in layout],'matrix_note':'Raw Blender source transforms; verify Godot basis independently (Blender Rz becomes Godot +Y rotation).'}
 (R/'godot/assets/models/facilities/gift_kiosk/runtime_manifest.json').write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 generated=list(prefab_dir.glob('*.tscn'))+list(mats.glob('*.tres'))+[target,R/'godot/scenes/facilities/floating_rest_stop.tscn']
 guard={'schema':'sea.authored_scene_generation_guard','note':'Only the initial reviewed assembly is reproducible here. Any later Godot edit blocks regeneration; use an external candidate and reviewed per-file changes.','generated_files':{p.relative_to(R).as_posix():sha(p) for p in generated}}
 guard_path.write_text(json.dumps(guard,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'components':len(cat),'instances':len(layout),'walk_rects':len(rects),'facility_scene':str(target)},ensure_ascii=False))

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');a=p.parse_args()
 if a.write:write()
 else:print('Prepared import; use --write after optimized-source and fidelity gates pass.')
