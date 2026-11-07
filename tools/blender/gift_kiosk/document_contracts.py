"""Append this delivery's requirements without rewriting historical ledgers."""
from pathlib import Path
R=Path(__file__).resolve().parents[3]
rows={
 'asset':('SEA-ASSET-R55','参考图海上礼品商亭','活跃Blender MCP制作 gift_kiosk/v001：圆角方形甲板/商亭、蓝白圆垂雨棚、三种立体招牌和全部固定配件；47独立组件，结构/陈设/植物分集合，共享既有明亮cozy色板、唯一PaletteUV和四材质角色，饱满3段真实倒角。每组件源包可直接打开，独立优化源重开再导出稳定GLB/PackedScene；浅浮筒和推进器保留参考外观，无水下建筑基座。正式商店沿用sea_supply，旧模型与用户变换保留为旧驿站景观。源、优化、运行、真实渲染、商业参考权属与用户美术验收分列。'),
 'world':('SEA-WORLD-R24','礼品商亭替换、摆放与移动支撑','新商亭沿用floating_shop.tscn和sea_supply身份，初次参考位按阳光房当前主体中心向东南(+X,+Z)200米计算，仅作带入参考；正式TSCN拥有后续摆位。旧模型保留原用户缩放/下沉变换为旧驿站景观，不重复登记sea_supply。新甲板、上岸口、阻挡、泊位及补给交互符合实际模型；单一设施所有者驱动轻柔竖向浮动，同步可视、WalkArea、派生碰撞、导航与交互，船泊位保持实际海面。不开辟第二套航行/上下船流程，不制作水下建筑基座。'),
 'move':('SEA-MOVE-R25','移动浮台承载角色','角色在动态支撑上站立、键盘行走、点击走路或交互时，由ActorController在物理帧消费所属WalkArea支撑高度变化，CharacterMotor执行显式承载位移；路径/目标同步竖向偏移。行走仍使用胶囊扫掠，退出支撑、上船、潜水、恢复位置时清理旧承载，不累计漂移，不让旧平台拉动船上角色。'),
 'nav':('SEA-NAV-R18','浮动商亭靠泊','新商亭沿用sea_supply/main和现有航行→靠妥→上岸链路；landStand与dockEdge随真实甲板起伏，boatPark保持实际水线且位于船只阻挡之外；Zones通过支撑变化事件更新公开泊位快照。远海参考摆位只作带入记录，验证正式TSCN下当前航路、上岸、甲板行走、回船及不可穿过船舷。')}
for feature,(rid,title,rule) in rows.items():
 spec=R/f'docs/features/{feature}/spec.md';ledger=R/f'docs/features/{feature}/ledger.md'
 if f'| {rid} |' not in spec.read_text(encoding='utf-8'):
  with spec.open('a',encoding='utf-8',newline='') as f:f.write(f'\n\n## 2026-11-07 {title}\n\n| 条款 ID | 规则与验收 |\n|---|---|\n| {rid} | {rule} |\n')
 if f'| {rid} |' not in ledger.read_text(encoding='utf-8'):
  with ledger.open('a',encoding='utf-8',newline='') as f:f.write(f'\n\n## 2026-11-07 {title}\n\n| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |\n|---|---|---|\n| {rid} | 制作与接入中，未签署最终验证 | [本轮记录](../../development/2026-11-07_gift_kiosk.md)；源、运行和真实渲染结果分别追加，商业参考权属及用户最终美术验收pending。 |\n')
print('appended 4 feature contracts; historical ledger prefixes untouched')
master=R/'GDD_V1.0.md'
if '## 2026-11-07 参考图海上礼品商亭' not in master.read_text(encoding='utf-8'):
 with master.open('a',encoding='utf-8',newline='') as stream:
  stream.write('\n\n## 2026-11-07 参考图海上礼品商亭\n\n通过活跃Blender MCP完成47组件/379实例的圆角方形商亭、蓝白雨棚、立体招牌及全部配件；源与47包重开、独立优化/GLB审计及Godot正式导入完成。新店沿用sea_supply与floating_shop.tscn，初次参考位按阳光房当前主体中心东南200米计算，后续只认正式TSCN手摆。可上岸、环廊/入口/中央行走及补给；0.269米峰峰竖向浮动同步角色、碰撞、导航和交互，读档重贴当前支撑，回船即脱离。无水下建筑基座；参考浅浮筒仅观赏。旧模型保留完整用户变换，改为R13非区块旧驿站地标，保留几何船只避让，无重复泊位/商店身份。最终7129功能、53真实渲染、1594水层全部0失败/exit0；相关静态移动和最小循环回归通过。商业参考权属、用户美术终审与低端性能另记pending。归SEA-ASSET-R55 / SEA-WORLD-R24 / SEA-MOVE-R25 / SEA-NAV-R18。[交付与验收](docs/development/2026-11-07_gift_kiosk.md) · [机器签署](docs/development/2026-11-07_gift_kiosk_verification.json)。\n')
