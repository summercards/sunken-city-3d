# 2026-11-07 礼品商亭室内装饰与柜台

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


## 最终运行与实景签署

最终统一runner副本：D:/projects/sea-work/verification/20261107-185311-gift-kiosk-interior-release-bae2ad/report.json。

| 专项 | 检查 / 失败 | 退出码 | runner |
|---|---|---|---|
| gift-kiosk-interior | 349 / 0 | 0 | PASS |
| visual-gift-kiosk-interior | 28 / 0 | 0 | PASS |
| gift-kiosk | 7129 / 0 | 0 | PASS |
| roof-reveal | 364 / 0 | 0 | PASS |

合计7870检查/0失败。四项均无非预期脚本/引擎错误，预期故障为空。实测新柜台、包装柜、陈列桌、坐凳占地不可穿越，入口/中央/柜台前/左过道/包装柜侧实际胶囊均到达；浮动时站立和行走随甲板承载。屋顶78顶部根正常消隐，102地砖和新陈设保留。原379个组件实例矩阵、船阻挡、泊位、原上下船、环廊与补给仍通过。

真实GPU实拍已亲看hero-day、close-day、top-day、checkout-day、checkout-panel和inside-night。白天地砖色差、柜台/收银和挂画均清楚；夜间沿用原暖光，柜台和商品可读。最终PNG位于D:/projects/sea-work/gift_kiosk/interior/v001/final/，其中godot-close-day.png为正式游戏场景实拍。不是Blender预览冒充Godot。

初次184501批次官方import PASS/exit0；室内349/1、render28/1因测试仍检查旧HUD页，而并行Main已经将柜台接到独立ShopPanel。测试改为现行公开is_open/close接口，未改变商店业务。184934批次室内349/0、render28/0、roof364/0通过，旧gift7129/1因旧130帧只够入口外短路程，柜台现移入室内；放长等待上限到600帧并保留原0.20m精确到达断言，最终185311实际到达通过。没有放宽空间判据或传送角色。正式编辑器已完成同一路径GLB导入，11份.glb.import与最终验收副本逐一相同；尝试复制时遇到编辑器文件共享锁，随后核验现有正式导入合同与缓存即可复用，未重建UID。

12个新AssetID和46份本轮审阅运行资源已定向登记，全部仍与最终副本SHA-256一致；母版、优化源、各包和GLB哈希在清单。首次元数据检查发现12份新manifest缺asset_ledger回链，已补齐并重新检查。原源/GLB保护检查通过。源、运行、商业参考权属和用户最终美术接受分列，原参考权属pending保持。

## 相关全局检查与未验边界

相关全世界水层回归D:/projects/sea-work/verification/20261107-185627-gift-kiosk-interior-water-bfe4b1/report.json为2110检查/111失败、exit1；111条全部是并行resident_harbor船只阻挡归属，商亭无失败，不将全世界报告称为PASS。未改住所或水层断言来消掉该遗留。

check_feature_contracts.py --sync为exit1/26问题，随后无参数检查exit1/27问题（多派生索引stale）：未知shop-modules、旧鱼源及住所源漂移、Main/水材质/阳光房/移动/存档/HUD等并行运行漂移和zones内容索引。均不涉及本批GKI资产或46份审阅运行文件，不重算未知哈希掩盖它们；全局摘要同步尚未完成。完整输出在本轮机器签署及工程外static目录。摆位检查发现用户已改霓虹街区Y，按TSCN只更新placed_positions台账实测位、偏差和时间，保留参考位及主场景；随后4结构0警告/exit0。git diff --check exit0，仅CRLF提示。

低端设备性能、完整无关功能套件、商业参考权属终审和用户美术接受未执行/未签署，不冒充全面通过。[机器签署](2026-11-07_gift_kiosk_interior_verification.json)。
