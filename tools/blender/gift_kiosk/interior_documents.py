"""Append scoped design clauses without replacing existing feature ledgers."""
from pathlib import Path
R=Path(__file__).resolve().parents[3]
chapters={
'docs/features/asset/spec.md': '''

## 2026-11-07 礼品商亭室内陈设扩展

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R57 | 商亭增加独立gift_kiosk_interior/v001室内陈设套件：三种PaletteUV配色地砖、圆角L柜台、独立收银机、陈列桌、坐凳、包装柜、海岸主题装饰画、挂钟与壁灯，共11组件；复用原礼品/瓶/卡片/花盆/植物。蓝白地砖以暖黄点缀，真实3段倒角、原cozy公共色板及四材质角色；原47件外观源及运行GLB保持。每件源包能直接打开，另存优化源重开后导出稳定GLB/PackedScene，独立验收UV/优化/保真/运行和实景，不以修改Godot原生几何代替Blender制作。 |
''',
'docs/features/asset/ledger.md': '''

## 2026-11-07 礼品商亭室内陈设扩展

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-ASSET-R57 | 已由活跃Blender MCP制作11母版、112新实例及17复用陈设；三色地砖102片，柜台/收银/陈列/包装柜/坐凳/装饰画/挂钟/壁灯。独立源包重开、PaletteUV和优化/GLB审计通过；Godot导入与实景验收进行中。 | [本轮制作与验收](../../development/2026-11-07_gift_kiosk_interior.md)；未完成运行验收前不晋升正式可用。原商业参考权属与用户美术终审pending保持。 |
''',
'docs/features/world/spec.md': '''

## 2026-11-07 商亭室内柜台与行走动线

| 条款 ID | 规则与验收 |
|---|---|
| SEA-WORLD-R27 | 原商亭正式场景增量引用独立室内陈设场景，不重建379个原实例或主场景。柜台补给交互沿原SupplyCounter公开端口移到真实柜台顾客侧，商品、价格、交易和NPC规则不改。行走域扣除新柜台、陈列台、柜子、凳子和花盆的真实占地，保留入口、中央通道、柜台前及陈列台侧过道；实际胶囊绕行和操作柜台须验证。室内陈设随原Visual浮动，屋顶消隐时保持可见；地砖仅为浅镶嵌视觉，不新增水面阻挡、第二层行走面或水下基座。用户手摆设施根、既有泊位、船只阻挡和屋顶控制保持。 |
''',
'docs/features/world/ledger.md': '''

## 2026-11-07 商亭室内柜台与行走动线

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-WORLD-R27 | 正式floating_shop仅增量加Visual/Interior、柜台交互点及家具扣除后的WalkArea；陈列台和附带5件货品在Godot相对Blender参考位向局部+X调0.3m以保留左侧通道，记录source_position与运行位。既有379个实例变换和屋顶标记不动，main.tscn未由本任务编辑。 | [本轮记录](../../development/2026-11-07_gift_kiosk_interior.md)，实际路径、浮动承载和补给交互验收进行中。 |
''',
'GDD_V1.0.md': '''

## 2026-11-07 礼品商亭室内装饰与柜台

按用户要求充实商亭室内：蓝白与暖黄地砖、L形圆角柜台/收银机、礼品陈列桌、包装柜、坐凳、挂钟、海岸装饰画和壁灯，复用原商品与植物。独立11组件室内套件增量挂入原商亭，补给点移到真实柜台前，行走域避开家具并保留动线；屋顶消隐和平台浮动继续作用。归SEA-ASSET-R57、SEA-WORLD-R27。[制作与验收](docs/development/2026-11-07_gift_kiosk_interior.md)。
'''}
for name,chapter in chapters.items():
 p=R/name;heading=chapter.splitlines()[2]
 assert heading not in p.read_text(encoding='utf-8'),name+' chapter already exists'
 with p.open('a',encoding='utf-8',newline='\n') as f:f.write(chapter)
for name in ['docs/features/asset/ledger.md','docs/features/world/ledger.md']:
 p=R/name;raw=p.read_bytes();nl=b'\r\n' if b'\r\n' in raw[:1000] else b'\n';marker=b'  "verification": ['+nl;at=raw.index(marker)+len(marker)
 keys=[k for k in ['gift-kiosk-interior','visual-gift-kiosk-interior'] if ('"'+k+'"').encode() not in raw]
 if keys:
  extra=nl.join(('    "'+k+'",').encode() for k in keys)+nl
  with p.open('r+b') as f:f.seek(at);f.write(extra+raw[at:]);f.truncate()
doc=R/'docs/development/2026-11-07_gift_kiosk_interior.md';assert not doc.exists()
doc.write_text('''# 2026-11-07 礼品商亭室内装饰与柜台

[主文档](../../GDD_V1.0.md) · [资产设计](../features/asset/spec.md) · [世界设计](../features/world/spec.md)

用户要求室内更充实、地板有不同颜色地砖、增加柜台。沿现有圆角卡通风格制作，使用sea-scene-component-authoring水上差异、blender-mcp-bridge与02b-godot-model-asset-import-standard。

## 范围与制作

新建独立室内陈设套件art_source/scenes/gift_kiosk_interior/v001，共11组件：3种相同几何/不同PaletteUV配色的地砖、L形柜台、独立收银机、椭圆陈列台、坐凳、包装柜、海岸装饰画、挂钟及壁灯。102地砖与10家具/装饰摆位共112个新实例，另复用17个原商品/卡片/植物实例。原47组件的制作源、GLB和379个实例不重生成。新室内组件计划独立计数11≤50，同族地砖3种；旧外观套件仍47。并行NPC制作占用了最初计划的设计条款R56，入账前仅将本批设计条款重新分配为R57，几何和AssetID未变。

公共色板继续引用sea_cozy_8x8_512.png，不复制或改色板。四语义材质角色，所有面为有面积、单格且留8px的PaletteUV。薄镶嵌地砖高2cm、真实倒角0.6cm；家具采用厚实3段圆角。室内地砖顶面为设施局部0.315m，不另建支撑层，原角色支撑面与浮动所有权不改。

柜台单体和收银机分件；灯泡发光几何独立。原商品、瓶子、卡片与植物使用原稳定组件引用。柜台朝入口，位置在后部；正中和入口保持通行。Godot的陈列台和其5件台上货品相对Blender参考向局部X加0.3m，给左侧留可走带。此为Godot正式布局决定，运行清单保留source_position追溯，不反向覆盖Blender参考或用户main.tscn摆位。

## 源级和02b证据

通过活跃Blender GUI MCP创建、查看并修正挂钟与装饰画间距。初稿库包的相对色板路径被独立复核发现并修正；最终11个包均实际保存为可直接打开的场景并重开，82259项检查、26484次面UV检查零错误。新母版1a0ef2632271eee67cde3c93ab9fc584ce46da676d31893b152664028d859567，源包和优化源哈希见各自清单。原资产只作为链接参考，不改写。

Blender GUI连续重开库文件出现原生EXCEPTION_ACCESS_VIOLATION；制作数据和源文件已保存。随后使用新GUI会话继续，只在独立验证进程重开/确认单组件包；模型生产与优化/GLB数据导出均由GUI MCP执行。独立验证的第一次后台启动加载了用户现有插件，出现Tripo端口占用及Rokoko可选依赖告警，单独记录，不将这些告警当作模型失败或隐藏。后续GUI从factory-startup启动。

优化另存export/v001/gift_kiosk_interior_optimized_v001.blend，重开后导出。逐件执行退化/重复面、孤立点与重合点清理；原始网格无可安全删除冗余，17696→17696三角（零减面原因与操作已登记），不把三角化冒充优化。新实例展开39248三角，复用件成本另计。独立GLB审计逐三角比较位置、corner normal、UV和材质，17696三角全部一致，GLB无内嵌图片。五方向固定相机原/优化对照RGB RMS最大0.007303/255，>24差异像素为0，保真通过。

## Godot接入与验收

新组件稳定路径scenes/components/facilities/gift_kiosk_interior，室内稳定场景scenes/facilities/gift_kiosk_interior.tscn，父场景只增量引用。SupplyCounter仍是唯一原补给交互所有者，顾客落点设在真实柜台前；不改商品/价格/NPC规则。原WalkArea从42矩形扣除家具后为66矩形，L柜台分两块占地，其它家具依实际包络；碰撞与导航仍由原GroundSpace派生。

所有Godot运行通过scripts/run_verification.py，隔离用户数据后进入Autoload。导入、真实角色路径、购物、浮动支撑和屋顶消隐实景结果在后续章节追加；未完成前保持pending，不引用历史通过替代当前实测。
''',encoding='utf-8')
p=R/'tools/blender/gift_kiosk/interior_prepare.py';s=p.read_text(encoding='utf-8');s=s.replace("'clause':'SEA-ASSET-R56'","'clause':'SEA-ASSET-R57'");p.write_text(s,encoding='utf-8')
print('Appended design/ledger chapters, added verification entries, created development record')
