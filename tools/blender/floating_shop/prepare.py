"""Freeze this reference and its component contract before geometry."""
import json, hashlib, shutil, os
from pathlib import Path
R=Path('D:/projects/sea')
D=R/'art_source/scenes/floating_shop/v001'
W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop'
D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
ref=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-3f27ed4b-b4e7-4e76-ba08-afcc084e8865.png')
shutil.copy2(ref,D/'reference.png')
items=[
('deck','环形厚甲板与分板','structure','deck'),
('roof','浅穹顶设备屋面','structure','roof'),
('facade_window','通透弧形橱窗单元','facility','facade'),
('entry','正面开放式门框','facility','entry'),
('rear_wall','背面封闭墙弧','structure','rear_wall'),
('rear_door','背面检修小门','facility','door'),
('sign_band','环形米黄招牌底带','facility','sign_band'),
('sign_gifts','GIFTS礼物招牌','facility','sign'),
('sign_postcards','POSTCARDS信封招牌','facility','sign'),
('sign_drinks','COLD DRINKS饮料招牌','facility','sign'),
('awning_blue','蓝色弧面圆垂边雨棚条','facility','awning'),
('awning_white','白色弧面圆垂边雨棚条','facility','awning'),
('rail_post','黄色球头护栏立柱','facility','rail_post'),
('rail_arc','双道弧形黄色栏杆','facility','rail'),
('tire','轮胎护舷和挂绳','facility','fender'),
('life_ring','红白救生圈和系绳','facility','safety'),
('ladder','平台至动力层爬梯','facility','ladder'),
('controller','米黄圆柱穹顶主控','facility','controller'),
('spotlight','黑色射灯及叉形支架','facility','light'),
('roof_pipe','弯折管线与阀门','facility','roof_pipe'),
('electrical_box','带合页电气箱','facility','electrical'),
('beacon','屋面橙色信号灯','facility','beacon'),
('engine','中央悬浮主推进舱','facility','engine'),
('engine_glow','主喷口发光内芯','facility','emission'),
('float_pod','橙色球形辅助浮舱','facility','float'),
('aux_nozzle','小型辅助推进器','facility','nozzle'),
('aux_glow','辅助喷口发光内芯','facility','emission'),
('under_brace','底盘辐射支臂及管线','structure','brace'),
('counterweight','悬挂橙色配重柱','facility','counterweight'),
('postcard_rack','双面明信片旋转架','facility','rack'),
('mailbox','红色邮筒','facility','mailbox'),
('ice_box','白色ICE冷藏箱','facility','cooler'),
('vending','黄色投币售货装置','facility','vending'),
('shelf','店内三层陈列架','facility','shelf'),
('bottle','彩色饮料瓶组','facility','stock'),
('gift','礼品盒与玩偶陈列组','facility','stock'),
('pot','米白圆陶盆','facility','pot'),
('foliage','饱满宽叶盆栽','plant','foliage'),
('flowers','小簇暖黄花','plant','flower'),
]
plan={'schema':'sea.scene.component_plan','version':'v001','feature_id':'SEA-ASSET','status':'frozen_before_geometry',
 'reference':'reference.png','reference_sha256':hashlib.sha256(ref.read_bytes()).hexdigest(),'reference_license':'pending_user_reference_rights_review',
 'classification':'building/structure','facility':'海上悬浮商铺','placement':'above_water','front_axis':'-Y',
 'dimension_contract':{'shop_diameter_m':12,'deck_diameter_m':14.4,'walkway_width_m':1.2,'overall_height_m':7.5,'deck_surface_z':2.5,'door_clear_width_m':2,'door_clear_height_m':2.2,'controller_diameter_m':2,'controller_height_m':1.2,'rail_height_m':1.1,'tire_diameter_m':1,'tire_count':10,'float_pod_diameter_m':2.5,'float_count':2,'interpretation':'12m is shop body; perimeter walkway adds 1.2m on each side. Layer junctions overlap; sign and roof fit within the 7.5m total.'},
 'components':[{'key':k,'asset_id':'SEA-SCENE-FSH-'+k.upper().replace('_','-'),'name':n,'category':'upgrade_attachment/plants' if c=='plant' else 'building/structure','source_group':c,'family':f,'origin':'bottom_center','front_axis':'-Y','scope':'scene_local','allowed_rotation':'full Euler XYZ','triangle_budget':25000} for k,n,c,f in items]}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'components':len(items),'source':str(D),'outputs':str(W)},ensure_ascii=False))
