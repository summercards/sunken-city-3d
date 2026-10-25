# -*- coding: utf-8 -*-
"""Freeze the user-reference kit before producing any Blender geometry."""
from pathlib import Path
import json, hashlib, shutil
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/tropical_flower_house/v001'
D.mkdir(parents=True,exist_ok=True)
ref=Path('/var/folders/m6/jk1g96896k79k8kzh51m4hvc0000gn/T/codex-clipboard-18bf0e22-1b03-479c-a366-5627310ed18f.png')
if not (D/'reference.png').exists():shutil.copy2(ref,D/'reference.png')
defs=[('base','平台灰色基座','foundation'),
('dock_support','栈桥灰石基座','foundation'),
('ac_roof','屋顶扁宽空调','air_conditioner'),
('paving','暖橙铺板','paving'),
('house','下层真实开窗墙壳','house'),
('terrace','屋顶露台','terrace'),
('upper_room','屋顶蓝门小屋','house'),
('roof_cap','厚圆角屋顶','roof_cap'),
('parapet','低矮白色花台墙','parapet'),
('porch_roof','太阳能单坡屋顶','porch_roof'),
('dock_plank','双列栈桥木板','paving'),
('post','橙色系绳矮柱','post'),
('shade_post','露台遮阳立柱梁架','shade_post'),
('shade_sail','下垂奶白布棚','shade_sail'),
('window','蓝色推拉窗','window'),
('door','屋顶青蓝门','door'),
('glass_entry','前廊玻璃入口','glass_entry'),
('solar_panel','蓝色太阳能板','solar_panel'),
('awning','黄白条纹软棚','awning'),
('ladder','墙侧圆角木梯','ladder'),
('ac_large','侧墙大空调箱','air_conditioner'),
('ac_small','屋顶小空调箱','air_conditioner'),
('vent','屋顶圆角通风柱','vent'),
('lantern','暖黄壁灯','lantern'),
('bench','奶白木沙发','bench'),
('table','圆角木桌','table'),
('stool','木凳','stool'),
('parasol','黄白遮阳伞','parasol'),
('cooler','蓝色白盖冷藏箱','cooler'),
('pot','奶陶花盆','pot'),
('cup','红色水壶','cup'),
('rug','薄荷太阳图案地垫','rug'),
('leaf_cluster','宽厚圆叶簇','leaf_cluster'),
('vine','短茎垂叶藤','vine'),
('palm','肥厚裂叶棕榈','palm'),
('flower','饱满五瓣粉花','flower'),
('daisy','六瓣白色雏菊','flower'),
('sprout','盆栽宽叶芽','sprout')]
flora={'leaf_cluster','vine','palm','flower','daisy','sprout'}
cs=[]
for slug,name,family in defs:
 cs.append(dict(component_id='SEA-SCENE-TFH-'+slug.upper().replace('_','-'),slug=slug,name=name,category='flora' if slug in flora else 'building',subcategory='vegetation' if slug in flora else ('structure' if slug in {'base','paving','house','terrace','upper_room','roof_cap','parapet','porch_roof','dock_plank'} else 'fixture'),component_family=family,scope='scene_local',variant_axis=None,variant_value=None,variant_reason=None,front_axis='-Y',origin='bottom_center',allowed_rotations_z_deg=[0,90,180,270],budget_triangles=6000))
p=dict(schema='sea.scene.component_plan',version='v001',status='frozen_before_geometry',frozen_date='2026-10-24',feature_id='SEA-ASSET',reference='reference.png',reference_sha256=hashlib.sha256((D/'reference.png').read_bytes()).hexdigest(),reference_license='pending_user_reference_rights_review',component_budget=dict(limit=50,planned=len(cs),remaining=50-len(cs)),dimensions_assumption=dict(main_platform_m=[7.4,6.8],main_house_m=[5.2,3.5,2.85],deck_top_z_m=.68,upper_room_m=[2.35,1.9,2.0],note='单图估算；朝前为-Y；右侧门廊与下层主楼相接，栈桥双列同向，未沿用其他附件布局。'),art_direction=dict(style='Plump cartoon style, rounded shapes, fuller forms, soft geometry, cute proportions, simplified forms, reduced tiny details, clean silhouettes, light volumetric modeling, playful toy-like look',optimization='重复铺板1段倒角，其他2段小倒角/3段主要轮廓；小叶10×6、大花12×8厚曲面；删除不可辨螺钉木纹；实例共享母版；太阳能栅线无倒角',triangle_budget='no user hard cap; report actual evaluated scene'),components=cs)
(D/'component_plan.json').write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
print('PLAN_FROZEN',len(cs))
