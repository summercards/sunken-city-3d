from pathlib import Path
import hashlib,json,shutil,os
from collections import Counter
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/neon_garden_quarter/v001';D=OLD.parent/'v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter/v002'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def put(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
D.mkdir(parents=True,exist_ok=True);(D/'reference').mkdir(exist_ok=True);(W/'renders').mkdir(parents=True,exist_ok=True)
for source,name in [('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-55ccd7b8-10cb-4943-94f1-45f10560fcd0.png','bridge_reference.png'),('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-fa139d78-b0d7-421e-8fd4-14824091ca93.png','rejected_corner.png')]:shutil.copy2(source,D/'reference'/name)
p=json.loads((OLD/'component_plan.json').read_text(encoding='utf8'));p.update(version='v002',reference='reference/bridge_reference.png',reference_sha256=sha(D/'reference/bridge_reference.png'),poster_source='art_source/scenes/neon_garden_quarter/v001/textures/poster_atlas.png',parent_source='art_source/scenes/neon_garden_quarter/v001/neon_garden_quarter.blend',parent_sha256=sha(OLD/'neon_garden_quarter.blend'),status='frozen_before_geometry')
p['retired_components']=['wall_scar','arc_window','round_balcony'];p['components']=[c for c in p['components'] if c['key'] not in p['retired_components']]
for c in p['components']:
 if c['key'] in ['left_storey','back_storey','round_storey']:c['family']=c['key']
 if c['key']=='round_storey':c['triangle_budget']=45000;c['name']='完整弧角楼标准层'
 if c['key']=='charcoal_sign':c['name']='沿完整弧面安装的破损炭火招牌'
for num,key,name,cat,fam in [
 (47,'garden_bridge','两楼间菜园承重连接桥','architecture','garden_bridge'),
 (48,'round_roof','同轮廓弧形楼顶','architecture','round_roof'),
 (49,'round_damaged','弧形楼大缺口层','architecture','round_storey'),
 (50,'round_ruin','弧形楼断梁露空层','architecture','round_storey'),
 (51,'left_damaged','左楼真实断墙缺角层','architecture','left_storey'),
 (52,'sign_bracket','招牌实体挂架','fixtures','sign_support'),
 (53,'fractured_ground','按建筑轮廓收边的破损街巷地面','architecture','street_ground'),
]:p['components'].append(dict(key=key,name=name,asset_id=f'SEA-SCENE-NGQ-{num:03}',category=cat,family=fam,building_class='above_water',origin='bottom_center',front_axis='-Y',triangle_budget=55000,collection=f'NGQ_{num:02}_{name}',scope='scene_local'))
p['revision_contract']=dict(bridge=dict(center=[0,0,25.8],span_x=[-4.7,4.7],depth_y=[-4.2,4.2],slab_m=.2,beam_depth_m=1.0,garden_moves_from_rear_roof=True,street_void_below=True),right_building=dict(center_xy=[8,1],radius_m=4.0,arc_center_local=[-.5,-5],footprint_m=[9,18],storeys=7,one_continuous_rounded_footprint=True,no_applied_arc_window_or_balcony=True),damage='actual removed wall / beam / slab volumes, sparse large debris; bent broken signs, fallen extinguished lanterns',ground='building-shaped foundations and split street paving, no intact rectangular exhibition plinth',signage='host / mounting socket and bracket for every suspended sign; local full Euler tilt retained')
p['material_exception']['atlas']='../v001/textures/poster_atlas.png'
assert len(p['components'])==50 and max(Counter(c['family'] for c in p['components']).values())<=3
put(D/'component_plan.json',p);put(W/'v001_protection.json',{'files':{str(f.relative_to(R)).replace('\\','/'):sha(f) for f in OLD.rglob('*') if f.is_file()}})
print('V002_PLAN_FROZEN',len(p['components']))
