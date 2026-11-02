"""Freeze the fishery component/scope contract before authoring geometry."""
import hashlib,json,math,os,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/wild_fishery/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'wild_fishery/v001'
D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
reference=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-de9d2320-8616-4d6d-a80a-2a9cc2250ebc.png')
shutil.copy2(reference,W/'user_reference.png')
probe=Path('D:/projects/sea-work/verification/20261102-112536-fishery-deck-contract-bda758/project/outputs/fishery-site.json')
shutil.copy2(probe,W/'runtime_site_contract.json')
site=json.loads(probe.read_text(encoding='utf-8'))
protected=[R/'godot/assets/models/facilities/legacy_home/salvage_station.glb',R/'godot/scenes/facilities/salvage_station.tscn',R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png']
rows=[
 ('shore','沙土圆角岸坪','terrain','structure',False),
 ('turf','软草苔簇','ground_cover','flora',False),
 ('pebbles','圆石组','shore_rocks','flora',False),
 ('reeds','饱满芦苇','shore_plants','flora',False),
 ('drying_rack','渔具晾架','fishing_furniture','fixture',True),
 ('creel','圆肚鱼篓','fishing_container','fixture',True),
 ('bait_table','饵料工作台','fishing_workbench','fixture',True),
 ('buoy','双色圆浮漂','water_float','water',False),
 ('marker_buoy','标记旗浮漂','water_float','water',False),
 ('net_panel','直段水下网','net_panel','water',False),
 ('net_corner','转角水下网','net_panel','water',False),
 ('fish','圆润浅水鱼','ambient_fish','animal',False),
]
components=[]
for key,name,family,category,blocks in rows:
 components.append({'key':key,'name':name,'asset_id':'SEA-FISHERY-'+key.upper().replace('_','-'),'component_family':family,'category':category,'origin':'bottom_center','front_axis':'Blender +Y / Godot -Z','root_scale':[1,1,1],'collision':'land prop footprint' if blocks else 'visual_only; enclosure blocking belongs to assembly','budget_triangles':12000,'budget_source':'task-authored performance target; not a user-supplied cap','reuse':'scene_local'})
plan={'schema':'sea.scene.component_plan','version':'v001','status':'frozen_before_geometry','scene_id':'wild_fishery','feature_id':'SEA-AQUA','asset_ledger':'assets/registry/ledgers/scenes.json','scene_design_docs':['GDD_V1.0.md','docs/features/aqua/spec.md','docs/features/asset/spec.md'],'scope':'home_supply upgrade visuals; original wooden footprint only, protected utility pole unchanged; forward water net and floats','reference':{'source':'user screenshot','sha256':sha(reference),'archive':str(W/'user_reference.png'),'license':'pending_user_reference_rights_review'},'style':'Plump cartoon style, rounded shapes, fuller forms, soft geometry, cute proportions, simplified forms, reduced tiny details, clean silhouettes, light volumetric modeling, playful toy-like look','palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png','runtime_palette':'res://assets/textures/shared/sea_cabin_timber_8x8_512.png','coordinate_mapping':'Blender(x,y,z)->Godot(x,z,-y)','dimensions_assumption':{'source':str(probe),'source_sha256':sha(probe),'island_bounds_xz':[-16.2039985657,-9.8638992310,10.0958003998,15.3957996368],'surface_y':1.33,'island_size':[6.3400993347,5.3],'island_center':[-13.0339488983,1.33,12.7458000183],'pen_bounds_xz':[-25.2,-13.2,15.8,25.8],'pen_corner_chamfer':1.0,'net_top_y':0.96,'net_bottom_y':-1.24,'water_y':1.12,'walk_rule':'support and paths remain within original deck footprint; keep original board and landing anchor; props excluded from walk domain','building_scale_exception':'existing landing surface 1.33m is retained rather than raising it to the general cabin 1.38m baseline'},'protected_files':{str(p.relative_to(R)):sha(p) for p in protected},'protected_runtime_node':next(r for r in site['site_nodes'] if r['path'].endswith('/PoleAndFlowers')),'geometry_budget':{'maximum_expanded_triangles':120000,'source':'task-authored performance target'},'components':components}
target=D/'component_plan.json'
if target.exists():assert json.loads(target.read_text(encoding='utf-8'))==plan,'Do not silently replace frozen plan'
else:save(target,plan)
save(W/'scope_baseline.json',{'protected_files':plan['protected_files'],'runtime_site_contract':site})
print('FROZEN',len(components),'components',target)
