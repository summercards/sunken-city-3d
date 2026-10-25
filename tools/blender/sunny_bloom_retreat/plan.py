"""Freeze a fresh kit from this task's single reference, before modeling."""
from pathlib import Path
import json, hashlib, shutil
ROOT=Path(__file__).resolve().parents[3]
D=ROOT/'art_source/scenes/sunny_bloom_retreat/v001'
REF=Path('/var/folders/m6/jk1g96896k79k8kzh51m4hvc0000gn/T/codex-clipboard-9f85cc90-89ae-4133-ab72-180385cf47cf.png')
defs={
'structure': [('foundation','石砌平台块','foundation'),('deck_tile','橙木平台铺板','paving'),('dock_board','双列码头木板','paving'),('pier','码头墩','foundation'),('house','开窗下层墙壳','wall'),('terrace','厚露台楼板','slab'),('upper_room','屋顶小屋墙壳','wall'),('cap','小屋厚帽檐','slab'),('parapet','白花台矮墙','parapet'),('slope','单坡门廊屋面','roof'),('porch_side','门廊厚侧墙与玻璃窗','wall')],
'fixture':[('bollard','双绳圈木柱','post'),('tall_window','下层蓝玻璃窗','window'),('small_window','上层小窗','window'),('door','青蓝门','door'),('entry','玻璃入口框扇','door'),('solar','蓝色光伏板','solar'),('awning','黄白条纹圆边遮阳篷','awning'),('canopy_post','遮阳棚橙木立柱','canopy'),('canopy_beam','遮阳棚横梁','canopy'),('sail','下垂奶白布棚','canopy'),('ladder','橙木圆角爬梯','ladder'),('ac_tall','侧墙高设备箱','aircon'),('ac_box','小立式空调','aircon'),('ac_roof','屋顶卧式空调','aircon'),('chimney','屋顶通风立柱','vent'),('lantern','暖光壁灯','lamp'),('sofa','白垫双人木沙发','seating'),('coffee_table','低木茶几','table'),('table','户外方桌','table'),('stool','方木凳','seating'),('umbrella','黄白圆瓣遮阳伞','umbrella'),('cooler','白盖蓝冷藏箱','cooler'),('pot','圆陶花盆','planter'),('square_pot','方白花盆','planter'),('bottle','红色水瓶','bottle'),('mat','太阳纹薄荷地垫','mat')],
'flora':[('foliage','错落厚叶簇','leaf'),('vine','自然交错垂藤','vine'),('palm','厚裂叶热带棕榈','palm'),('pink_flower','五瓣饱满粉花','flower'),('daisy','六瓣白色小花','flower'),('sprout','盆栽嫩叶','sprout')]}
items=[]
for category,rows in defs.items():
 for key,name,family in rows:
  items.append(dict(key=key,asset_id='SEA-SCENE-SBR-'+key.upper().replace('_','-'),name=name,category=category,family=family,origin='bottom_center',front_axis='-Y',allowed_rotation='full Euler XYZ; normally Z yaw',scope='scene_local',triangle_budget=24000 if key=='palm' else 16000))
D.mkdir(parents=True,exist_ok=True)
shutil.copy2(REF,D/'reference.png')
plan=dict(schema='sea.scene.component_plan',version='v001',feature_id='SEA-ASSET',status='frozen_before_geometry',reference_sha256=hashlib.sha256(REF.read_bytes()).hexdigest(),reference_license='pending',reference='reference.png',source_policy='Fresh geometry and layout from the current attached image only; no previous kit or model reused.',components=items,component_limit=50,dimensions_assumption={'platform_m':[7.2,7.2],'main_house_m':[5.0,3.5,2.85],'upper_room_m':[2.25,1.95,1.95],'deck_top_z':.68,'front':'-Y','note':'Single-image proportions, not measured real-world dimensions'},visual_priorities=['reference silhouette and stepped volumes','plump smooth leaves and petals','physical rounded edges','thick white plaster and warm orange timber','dense roof-edge flowers and trailing greenery','two parallel dock strips'],scene_triangle_limit=None,palette='art_source/shared/palettes/sea_cozy_8x8_512.png')
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
print('FROZEN',len(items),'components',plan['reference_sha256'])
