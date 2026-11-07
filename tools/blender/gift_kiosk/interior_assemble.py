"""Add the reviewed interior and subtract furniture footprints, never rebuild the shop."""
import hashlib,json,math,os,re,sys
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/gift_kiosk_interior/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001'
sys.path.insert(0,str(Path(__file__).parent));from assemble_godot import xf,gltf
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();f=lambda v:format(float(v),'.9g')
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];rows=json.loads((D/'component_instances.json').read_text(encoding='utf-8'));opt=json.loads((D/'export/v001/optimization_manifest.json').read_text(encoding='utf-8'))
assert json.loads((W/'source_verification.json').read_text())['passed']
assert json.loads((W/'export_audit.json').read_text())['passed']
assert opt['fidelity']['passed']
assert opt['exported_components']==11
oldcat=json.loads((R/'art_source/scenes/gift_kiosk/v001/catalog.json').read_text(encoding='utf-8'))['components'];byid={x['asset_id']:x for x in cat+oldcat}
# Godot owns final layout. Move the display and its five attached goods 0.3m
# towards the centre so the left aisle supports the existing 0.38m clearance.
for row in rows['instances']+rows['reused_instances']:
 if row['key']=='display_table' or row['name'] in ['interior_gift_001','interior_gift_002','interior_gift_003','interior_bottle_004','interior_bottle_005']:
  row['source_position']=row['position'].copy();row['position'][0]+=.3
  row['runtime_layout_adjustment']='display moves +0.3m X for left aisle; source is reference only'
directory=R/'godot/scenes/components/facilities/gift_kiosk_interior';directory.mkdir(parents=True,exist_ok=True)
params=(R/'godot/assets/models/facilities/gift_kiosk/shelf/shelf.glb.import').read_text(encoding='utf-8').split('[params]',1)[1]
for e in cat:
 path=R/f"godot/assets/models/facilities/gift_kiosk_interior/{e['key']}/{e['key']}.glb";gltf(path)
 res='res://'+path.relative_to(R/'godot').as_posix();cache=f'res://.godot/imported/{path.name}-{hashlib.md5(res.encode()).hexdigest()}.scn'
 text=f'[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n\n[deps]\n\nsource_file="{res}"\ndest_files=["{cache}"]\n\n[params]'+params
 path.with_suffix('.glb.import').write_text(text,encoding='utf-8')
 wrapper=f'''[gd_scene format=3]

[ext_resource type="PackedScene" path="{res}" id="model"]

[node name="{e['key']}" type="Node3D"]
metadata/asset_id = "{e['asset_id']}"
metadata/asset_version = "v001"
metadata/interior_role = "{e['family']}"

[node name="Visual" parent="." instance=ExtResource("model")]
'''
 (directory/(e['key']+'.tscn')).write_text(wrapper,encoding='utf-8')
scene=R/plan['runtime']['stable_scene']
keys={row['asset_id'] for row in rows['instances']+rows['reused_instances']}
text='[gd_scene format=3]\n\n'
for aid in sorted(keys):
 e=byid[aid];suite='gift_kiosk_interior' if aid.startswith('SEA-SCENE-GKI-') else 'gift_kiosk'
 text+=f'[ext_resource type="PackedScene" path="res://scenes/components/facilities/{suite}/{e["key"]}.tscn" id="{e["key"]}"]\n'
text+='\n[node name="GiftKioskInterior" type="Node3D"]\nmetadata/asset_id = "SEA-SCENE-GKI-ASSEMBLY"\nmetadata/asset_version = "v001"\nmetadata/facility_id = "SEA-SCENE-GKS-ASSEMBLY"\nmetadata/water_layer = "surface"\nmetadata/water_layer_role = "part"\nmetadata/presentation_only = true\n'
for group in ['Floor','Furnishings','Plants']:text+=f'\n[node name="{group}" type="Node3D" parent="."]\n'
for row in rows['instances']+rows['reused_instances']:
 e=byid[row['asset_id']];group='Floor' if row['key'].startswith('tile_') else ('Plants' if row['key']=='foliage' else 'Furnishings')
 text+=f'\n[node name="{row["name"]}" parent="{group}" instance=ExtResource("{row["key"]}" )]\ntransform = {xf(row)}\n'
if scene.exists():assert scene.read_text(encoding='utf-8')==text,'Authored interior changed; refuse overwrite'
else:scene.write_text(text,encoding='utf-8')
# Physical envelope matches occupied upper volumes; the L counter uses two boxes.
obstacles=[(-3.52,-3.285,3.94,1.75),(-3.40,-2.50,1.22,1.10)]
for row in rows['instances']+rows['reused_instances']:
 if row['key'] not in ['display_table','stool','cubby','pot']:continue
 e=byid[row['asset_id']];sx,sy,_=e['bounds_size'];x,z=row['position'][0],-row['position'][1];wx,depth=sx*row['scale'][0],sy*row['scale'][1]
 obstacles.append((x-wx/2-.04,z-depth/2-.04,wx+.08,depth+.08))
parent=R/plan['runtime']['stable_parent'];before=parent.read_text(encoding='utf-8');assert 'id="interior"' not in before
(W/'floating_shop_before.tscn').write_text(before,encoding='utf-8')
match=re.search(r'^rects = \[(.*?)\]$',before,re.M);assert match
base=[tuple(map(float,x.split(','))) for x in re.findall(r'Rect2\(([^)]+)\)',match.group(1))]
def subtract(a,b):
 x,z,w,d=a;u,v,s,t=b;lo=max(x,u);hi=min(x+w,u+s);near=max(z,v);far=min(z+d,v+t)
 if hi<=lo or far<=near:return [a]
 out=[(x,z,w,near-z),(x,far,w,z+d-far),(x,near,lo-x,far-near),(hi,near,x+w-hi,far-near)]
 return [q for q in out if q[2]>.0001 and q[3]>.0001]
remaining=base
for obstacle in obstacles:remaining=[part for rect in remaining for part in subtract(rect,obstacle)]
walk='rects = ['+', '.join('Rect2('+', '.join(f(n) for n in rect)+')' for rect in remaining)+']'
after=before[:match.start()]+walk+before[match.end():]
after=after.replace('[node name="FloatingGiftKiosk"','[ext_resource type="PackedScene" path="res://scenes/facilities/gift_kiosk_interior.tscn" id="interior"]\n\n[node name="FloatingGiftKiosk"',1)
after+='\n[node name="Interior" parent="Visual" instance=ExtResource("interior")]\n'
header='[node name="SupplyCounter" type="Node3D" parent="Objects"]'
at=after.index(header);end=after.index('\n[node ',at+len(header));block=after[at:end]
block,n=re.subn(r'^position = Vector3\([^\n]+\)', 'position = Vector3(-1.1, 0.3, -0.75)',block,count=1,flags=re.M);assert n==1
block=block.replace('focus_radius = 2.8','focus_radius = 1.8')
after=after[:at]+block+after[end:]
# Edit the existing file in place; retain the exact common prefix and all
# unmodified text, rather than replacing the authored file on disk.
raw=parent.read_bytes();replacement=after.encode('utf-8');prefix=0
while prefix<min(len(raw),len(replacement)) and raw[prefix]==replacement[prefix]:prefix+=1
with parent.open('r+b') as stream:
 stream.seek(prefix);stream.write(replacement[prefix:]);stream.truncate()
manifest={'schema':'sea.scene.interior_runtime','asset_id':plan['asset_id'],'component_count':11,'new_instances':len(rows['instances']),'reused_instances':len(rows['reused_instances']),'components':cat,**rows,'walk_obstacles':obstacles,'counter_customer_local':[-1.1,.3,-.75],'walk_rects_before':len(base),'walk_rects_after':len(remaining),'parent_scene':parent.relative_to(R).as_posix(),'parent_before_sha256':hashlib.sha256(before.encode()).hexdigest(),'parent_after_sha256':sha(parent)}
(R/'godot/assets/models/facilities/gift_kiosk_interior/runtime_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'assembly_review.json').write_text(json.dumps({'changed_parent_fields':['one resource','Visual/Interior instance','walk rects minus new furniture','SupplyCounter position and radius'],'new_obstacles':obstacles,'old_instances_preserved':379,'parent_sha256':sha(parent),'scene_sha256':sha(scene)},indent=2),encoding='utf-8')
print('Added',len(rows['instances'])+len(rows['reused_instances']),'interior instances;',len(base),'->',len(remaining),'walk rectangles')
