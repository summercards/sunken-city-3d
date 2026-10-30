import bpy,json,hashlib,shutil
from pathlib import Path
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';W=R/'sea-work/liberty_lighthouse'
if bpy.data.filepath:
 p=W/'session_safety_before.blend'
 bpy.ops.wm.save_as_mainfile(filepath=str(p),copy=True)
 print('SESSION_BACKUP',str(p))
ref=Path(r'C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-30T08-18-18-499Z-1412399d.jpg')
shutil.copy2(ref,D/'reference.png')
items=[
('barge','漂浮驳船基座','structure','base'),('tire','轮胎护舷','structure','fender'),('shop_shell','开放式商铺墙壳','structure','wall'),
('shop_trim','商铺金属包边','facility','trim'),('awning','蓝白条纹遮阳棚','facility','canopy'),('sign','黄色双段招牌','facility','signage'),
('window','侧墙玻璃窗','facility','window'),('service_window','服务窗口','facility','window'),('notice','手写告示牌','facility','signage'),
('ice_box','ICE内嵌冷藏柜','facility','cooler'),('hydrant','红白消防栓','facility','hydrant'),('traffic_signal','交通信号装置','facility','signal'),
('billboard','立式ICE广告牌','facility','billboard'),('arm','巨手手臂与手掌','structure','hand'),('finger','环握柱身手指','structure','hand'),
('thumb','巨手拇指','structure','hand'),('column','竖槽柱身','structure','column'),('maintenance_door','柱身检修门','facility','door'),
('platform','圆形观景平台','structure','platform'),('platform_trim','平台线脚与托臂','structure','platform'),('railing','断裂观景栏杆','structure','railing'),
('equipment_box','平台设备箱','facility','equipment'),('solar_panel','斜置太阳能板','facility','solar'),('tower_body','上部收窄塔身','structure','tower'),
('lantern','多边形玻璃灯室','structure','lantern'),('lens','灯室透镜灯座','facility','lens'),('antenna_mast','通信天线桅杆','facility','antenna'),
('satellite_dish','圆形卫星天线','facility','antenna'),('panel_antenna','矩形通信天线','facility','antenna'),('roof_cap','灯室顶盖','structure','roof')]
plan={'schema':'sea.scene.component_plan','version':'v001','feature_id':'SEA-ASSET','status':'frozen_before_geometry','reference_sha256':hashlib.sha256((D/'reference.png').read_bytes()).hexdigest(),'reference_license':'pending','reference':'reference.png','source_policy':'Fresh original scene geometry from current reference; same scene-component class as solar cabin, no solar-house visual reuse.','dimension_contract':{'base_m':[8,6,1.2],'shop_wall_height_m':2.8,'awning_projection_m':1.2,'awning_clearance_m':2.4,'hand_arm_height_m':7,'hand_palm_width_m':2.5,'finger_diameter_m':0.8,'column_diameter_m':2,'column_height_m':5,'column_top_z_m':16.4,'platform_diameter_m':6,'platform_thickness_m':0.5,'rail_height_m':1.1,'tower_body_height_m':2.5,'lantern_height_m':2,'mast_height_m':3.5,'overall_height_m':25.0,'overlap_note':'Column overlaps the hand vertically; no 7+5 additive stack.'},'components':[{'key':k,'asset_id':'SEA-SCENE-LHL-'+k.upper().replace('_','-'),'name':n,'category':c,'family':f,'origin':'bottom_center','front_axis':'-Y','allowed_rotation':'full Euler XYZ','scope':'scene_local','triangle_budget':20000} for k,n,c,f in items]}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'scene':bpy.context.scene.name,'filepath':bpy.data.filepath,'planned_components':len(items),'reference_sha256':plan['reference_sha256']},ensure_ascii=False))
