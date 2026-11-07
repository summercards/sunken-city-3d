"""Freeze the reference-led floating gift kiosk contract before making meshes."""
import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'art_source/scenes/gift_kiosk/v001'
WORK = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'gift_kiosk/v001'
REFERENCE = Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-a9725311-5901-437c-9dee-6bcd98f700c9.png')
ITEMS = [
 ('deck', '奶油圆角方形铺砖甲板', 'deck', 'structure'),
 ('hull', '灰色圆角护舷底盘', 'hull', 'structure'),
 ('underframe', '船底十字管梁', 'frame', 'structure'),
 ('pontoon', '橙色圆鼓浮筒', 'flotation', 'structure'),
 ('thruster', '中央圆锥推进器', 'propulsion', 'structure'),
 ('thruster_glow', '推进器暖黄灯芯', 'emission', 'furnishing'),
 ('deck_light', '舷沿胶囊暖黄灯', 'edge_light', 'furnishing'),
 ('rail_post', '球头黄色护栏立柱', 'rail_post', 'furnishing'),
 ('rail_bar', '黄色横栏', 'rail', 'furnishing'),
 ('rail_corner', '圆弧黄色转角栏', 'rail', 'furnishing'),
 ('fender', '黑色轮胎护舷与挂绳', 'fender', 'furnishing'),
 ('ladder', '黄色下水梯与扶手', 'ladder', 'furnishing'),
 ('bollard', '双耳系泊柱', 'mooring', 'furnishing'),
 ('pot', '奶白陶盆', 'planter', 'furnishing'),
 ('foliage', '饱满球簇绿植', 'foliage', 'plant'),
 ('bench', '厚木条长凳', 'bench', 'furnishing'),
 ('glass_bay', '青蓝立框商店橱窗', 'window', 'structure'),
 ('back_panel', '奶黄后墙设备板', 'wall', 'structure'),
 ('column', '青蓝圆角主柱', 'column', 'structure'),
 ('back_door', '后侧灰蓝检修门', 'door', 'structure'),
 ('roof', '圆角平屋顶与檐板', 'roof', 'structure'),
 ('fascia', '奶黄直段招牌灯箱', 'fascia', 'furnishing'),
 ('fascia_corner', '奶黄圆角招牌灯箱', 'fascia', 'furnishing'),
 ('sign_postcards', 'POSTCARDS立体字及信封', 'sign', 'furnishing'),
 ('sign_gifts', 'GIFTS立体字及礼盒', 'sign', 'furnishing'),
 ('sign_drinks', 'COLD DRINKS立体字及饮杯', 'sign', 'furnishing'),
 ('awning_blue', '蓝色圆垂边雨棚条', 'awning', 'furnishing'),
 ('awning_white', '白色圆垂边雨棚条', 'awning', 'furnishing'),
 ('awning_corner', '蓝白转角圆垂雨棚', 'awning', 'furnishing'),
 ('roof_disk', '屋顶黄色圆盘及奶白穹盖', 'roof_machine', 'furnishing'),
 ('spotlight', '深灰弯支架暖黄射灯', 'spotlight', 'furnishing'),
 ('roof_pipe', '屋顶弯管', 'pipe', 'furnishing'),
 ('beacon', '橙色信号灯', 'beacon', 'furnishing'),
 ('electrical_box', '后墙电气盒', 'electrical', 'furnishing'),
 ('life_ring', '红白救生圈', 'safety', 'furnishing'),
 ('postcard_rack', '三面旋转明信片展示架', 'retail_display', 'furnishing'),
 ('mailbox', '红色圆角邮筒', 'mail', 'furnishing'),
 ('ice_box', '白色ICE冰柜', 'ice', 'furnishing'),
 ('bin', '黄色分类垃圾桶', 'bin', 'furnishing'),
 ('shelf', '暖木三层商品架', 'shelf', 'furnishing'),
 ('bottle', '彩色饮料瓶', 'stock_bottle', 'furnishing'),
 ('gift', '红黄礼品盒', 'stock_gift', 'furnishing'),
 ('card', '蓝橙插画明信片', 'stock_card', 'furnishing'),
 ('lantern', '紫色侧挂圆筒灯', 'lantern', 'furnishing'),
 ('plaque', '船底圆角铆钉检修板', 'maintenance', 'furnishing'),
 ('curved_glass', '圆角透明橱窗及边框', 'curved_window', 'structure'),
 ('entry_frame', '开放商亭入口框', 'entry', 'structure'),
]

def main():
 SOURCE.mkdir(parents=True, exist_ok=True)
 WORK.mkdir(parents=True, exist_ok=True)
 dst = SOURCE / 'reference.png'
 if not dst.exists(): shutil.copy2(REFERENCE, dst)
 plan = {
  'schema':'sea.scene.component_plan', 'feature_id':'SEA-ASSET', 'clause':'SEA-ASSET-R55',
  'version':'v001', 'status':'frozen_before_geometry', 'asset_id':'SEA-SCENE-GKS-ASSEMBLY',
  'reference':'reference.png', 'reference_sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),
  'reference_license':'pending_user_reference_commercial_rights_review',
  'building_class':'above_water', 'loaded_responsibility':'references/above-water.md',
  'palette':'art_source/shared/palettes/sea_cozy_8x8_512.png',
  'palette_exception':'Use the existing bright cozy palette to preserve the user reference yellow/white/blue; no palette is changed or duplicated.',
  'dimensions':{'deck_xy_m':[18,18], 'deck_corner_radius_m':2.0, 'walk_slab_m':0.2,
    'deck_top_above_water_m':0.3, 'kiosk_xy_m':[10.8,10.8], 'kiosk_corner_radius_m':1.5,
    'wall_clear_height_m':4.9, 'column_xy_m':[0.5,0.5], 'outer_fascia_xy_m':[12,12],
    'entry_clear_width_m':2.4, 'entry_clear_height_m':3.4},
  'style':'Saturated toy-like cozy stylization; plump 3-segment real bevels; rounded-square roof and deck; no realistic wear or thin sheet details.',
  'exceptions': ['Thick outer cream hull/rubbing band is separate from the 0.2m walk slab.',
    'Shallow orange flotation pods and central nozzle follow the reference; no underwater architectural base, columns or sunken building is created.',
    'Root datum is the static waterline; individual component geometry is bottom-centred, assembly places the shallow flotation parts below it.'],
  'runtime':{'stable_scene':'godot/scenes/facilities/floating_shop.tscn', 'zone_id':'sea_supply',
    'placement':'Reference only: current sunroom body centre + 200m along southeast (+X,+Z), no change to existing author transforms.',
    'old_shop':'Preserve old GLB and exact author transform as a retired marine rest-stop visual, without duplicate sea_supply identity.',
    'motion':'One facility owner drives gentle vertical heave; visual/deck/collision/landing/interaction move together. ActorController owns support carry; boat remains at waterline.'},
  'components':[{'key':k,'name':n,'family':f,'group':g,'asset_id':'SEA-SCENE-GKS-'+k.upper().replace('_','-'),
    'building_class':('underwater' if k in {'hull','underframe','pontoon','thruster','thruster_glow','plaque'} else ('above_water' if g=='structure' else None)),
    'loaded_responsibility':('references/underwater-scenery.md' if k in {'hull','underframe','pontoon','thruster','thruster_glow','plaque'} else ('references/above-water.md' if g=='structure' else None)),
    'scope':'scene_local','origin':'bottom_center','front_axis':'-Y',
    'allowed_rotation':'Euler XYZ','triangle_budget':None,'collision_responsibility':'Godot facility WalkArea/GroundSpace only; visual package has no gameplay nodes'} for k,n,f,g in ITEMS]
 }
 assert len(ITEMS)<=50
 for fam in {x[2] for x in ITEMS}: assert sum(x[2]==fam for x in ITEMS)<=3
 (SOURCE/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'components':len(ITEMS),'source':str(SOURCE),'work':str(WORK)},ensure_ascii=False))

if __name__=='__main__': main()
