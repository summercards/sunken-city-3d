# 2026-10-30 模块化结构与生活摆件

关联SEA-BUILDING / SEA-ASSET / SEA-MOVE。独立布局状态仍只由BuildingService写入；目录、拼接规则、表现和交互适配分别维护。

## 内容计划（制作前冻结）

| ID | 名称 | 占地(米) | 高度 | 木板成本 | 归类/功能 |
|---|---|---|---|---|---|
| raft_4x4 | 4×4木浮台 | [4, 4] | 0.5 | 20 | 2米模数拼接 |
| raft_2x4 | 2×4木浮台 | [2, 4] | 0.5 | 12 | 2米模数拼接 |
| wall | 木板实墙 | [2, 0.16] | 2.8 | 6 | 2米模数拼接 |
| window_wall | 开窗木墙 | [2, 0.16] | 2.8 | 7 | 2米模数拼接 |
| door_frame | 通行门框 | [2, 0.16] | 2.8 | 5 | 2米模数拼接 |
| post | 木立柱 | [0.2, 0.2] | 2.8 | 3 | 2米模数拼接 |
| beam | 承重横梁 | [2, 0.2] | 0.2 | 3 | 2米模数拼接 |
| railing | 交叉栏杆 | [2, 0.14] | 1 | 4 | 2米模数拼接 |
| stairs | 直跑楼梯 | [1.2, 4] | 2.8 | 10 | 2米模数拼接 |
| upper_floor | 二层木楼板 | [2, 2] | 0.18 | 8 | 2米模数拼接 |
| roof_slope | 斜面屋顶 | [2, 4] | 1.25 | 8 | 2米模数拼接 |
| roof_flat | 平顶遮棚 | [4, 4] | 0.16 | 10 | 2米模数拼接 |
| oil_lamp | 桌面油灯 | [0.38, 0.38] | 0.65 | 2 | 真实暖光照明 |
| lamp_post | 立杆油灯 | [0.4, 0.4] | 2.2 | 4 | 真实暖光照明 |
| windmill | 小风车 | [1.05, 0.5] | 1.7 | 4 | 旋转装饰，不发电 |
| flower_pot | 开花陶盆 | [0.55, 0.55] | 0.8 | 2 | 自由布置的装饰 |
| storage_crate | 木储物箱 | [1, 0.65] | 0.7 | 5 | 接入共享保管仓库 |
| water_barrel | 补水木桶 | [0.7, 0.7] | 0.95 | 5 | 免费补满水壶 |
| flag | 小旗杆 | [1.15, 0.35] | 2 | 3 | 自由布置的装饰 |
| table | 圆角木桌 | [1.2, 0.8] | 0.85 | 4 | 自由布置的装饰 |
| stool | 木矮凳 | [0.45, 0.45] | 0.45 | 2 | 自由布置的装饰 |
| wind_chime | 木架风铃 | [0.45, 0.45] | 1.4 | 3 | 轻摆装饰，首版无声音 |

## 拼接与维护设计

旧2.15×2.575米木板兼容；新浮台以2米模数中心吸附，4×4是真实4米见方，可独立海上开工。结构件四向旋转；地面件落在完工甲板并集，边缘构件吸附2米挂点；立柱/墙顶提供2.8米层高承载，横梁/二层楼板/屋顶只能在完整支撑后建造。屋顶不能当二层楼板；楼梯提供地面到2.8米楼层的通行坡面。

每件单独Blender母版Collection与独立包、GLB、PackedScene、AssetID；实例位置由Godot拥有。目录active=false退出新建菜单，既存实例仍可读档/回收；不直接删除被存档引用的定义。结构支撑引用稳定ID，移除支撑先拆上方依附件；不静默连带删除。不把停用等同于破坏历史存档。

摆件按配置识别功能：灯具真实灯光、箱子共享仓库、水桶调用Farm补水；风车与风铃只有动画，不宣称发电或音效。交互命令由组合层注入，资产不直接读Economy/Main。

## 实施与验证

本轮制作、游戏接入、用户反馈修复和桌面专项验收已完成。最新结果以末尾最终验收表和机器证据为准，保留以下过程记录。

| 阶段 | 当前证据与结果 |
|---|---|
| Blender源制作 | `tools/blender/building_kit/build.py`新建母版/22包/22GLB；`refine.py`把每包保存为可打开的独立场景。母版保存重开，读取各包场景/集合、PaletteUV非零面积和单格检查；`D:/projects/sea-work/building_kit_v001/refine.log`记录`KIT_REOPEN_UV_PACKAGE_PASS 22`，四视图front/back/top/side位于同目录。源包络修订正在最终核验，不能以旧截图代替最终方向检查。 |
| 规则和真实角色移动 | `20261030-142145-kit-ramp-join-f794f6`：building-kit 73项、ground-space全部PASS，退出0；包含22预制体独立加载、两灯真实光源、缺支撑拒绝、依附支撑不可拆、顺序无关存档、实际胶囊爬楼、共享仓库、补水与内容停用。 |
| 前轮回归 | `20261030-141358-kit-navigation-c341b6`：building-kit、building-integration PASS。 |
| 原待验项，现已关闭 | 全22件正式游戏建成、墙/门通行差异、楼梯视觉同向、装饰包络、真实画面及SHA登记均已完成；最终结果见末节。 |

测试发现并修复：早期手册使用不支持的`%g`格式；首个场地与既有建筑重叠后换隔离空地；楼梯/楼板部分边长不一致使导航接缝不连接，按共边切分；角色胶囊在坡入口接触偏移导致追逐中间路径点与旧平面封口阻挡，增加中间引导容差并仅对明确楼梯接缝开放边界。所有失败轮保留，不计作通过。

本轮运行代码责任：BuildingCatalog/Service/Space/Boundary/World/Access/Controller/Book与新增AssemblyRules/AssemblySurfaces/KitVisual；三维执行的WalkArea、GroundSpace、WalkAction及Main仅接口装配。22组件独立资源在`godot/scenes/buildables/kit`和`godot/assets/models/building_kit`；共享材质在`godot/assets/materials/building_kit`。


## 用户实测后修复：UV与共享材质转交

实际GLB审计确认两个根因：Blender原始几何自带`UVMap`，制作时追加的`PaletteUV`虽为活动渲染层，但导出仍把默认层放在`TEXCOORD_0`，色板层变成`TEXCOORD_1`；Godot StandardMaterial3D读取UV0，导致板面扫过整张色板。另`export_materials=PLACEHOLDER`未保留glTF material记录，运行适配器无法识别Metal/Gloss/Emission，全部静默使用Matte。源PNG与运行共享PNG哈希一致，问题在通道/语义转交。

修复链路：

- `tools/blender/building_kit/fix_palette_export.py`对保存母版和22独立包仅删除非PaletteUV层，保证PaletteUV为唯一UV0；源位置、几何、色格坐标保持。母版先备份到工程外`building_kit_v001/before_uv_transfer_fix/`。
- `export_component.py`在独立transfer scene导出单件，避免母版库与展示实例混入。GLB只含最小命名材质槽`SEA_Matte/Metal/Gloss/Emission`，不嵌入第二份色板；源与GLB的UV0逐mesh色格集合一致，不出现TEXCOORD_1。
- `KitVisual`按真实表面角色严格绑定四种共享材质，缺角色报错，不再静默回退。Matte粗糙度0.8，其余0.28；Emission只给灯焰，使用同一palette作为发光纹理、倍率2，与Blender源相符。两灯真实光源保持原业务。
- `build.py`/`refine.py`改为调用同一导出函数，避免下次重导恢复错误层。Windows写目标用暂存文件原子替换；源包/运行件SHA仅针对本套件回填，不更新其他并行旧资产。

证据：`D:/projects/sea-work/building_kit_v001/uv_transfer_report.json`记录22件源→GLB色格/材质角色通过；同目录`uv_transfer_fix.log`记录`KIT_PALETTE_UV0_ROLE_TRANSFER_PASS 22`。统一runner目录`20261030-165252-kit-uv-transfer-58cecd`：asset-import PASS/退出0，visual-kit-uv 563项0失败/退出0。全部22件独立预制体实际网格UV0、同一色板绑定、材质角色及灯焰发光检查均通过。已查看`project/outputs/kit-uv-{all,raft_4x4,oil_lamp,flower_pot,windmill}.png`：木板无色板条纹，金属灯壳、陶盆/绿茎/花瓣与风车颜色正常。该独立画廊验证只覆盖美术传递，不代替建筑规则和最终鼠标摆放验收。

## 手册卡片表现（用户后续要求）

建造书本调整为5列×2行整卡；每卡只显示真实组件图、名称和材料消耗。`RecipeThumbnail`以隔离SubViewport渲染真实GLB/既有板材与土箱纯几何，绑定同一套共享材质，三帧后缓存ImageTexture；headless不创建GPU。分类/分页从目录生成，active停用隐藏。`RecipeCard`只发送选择命令，不持有布局、库存或施工状态。最新UV修复后的GLB为卡片唯一图源；真实鼠标78项已通过，截图已核对。

## 用户实测后修复：旧板承载与4×4贴边

原判断仅把新目录浮台认作承载，固定木面未提供支撑ID；同时4米浮台按世界整数中心吸附，无法与2.15×2.575米的旧板边缘对齐。现在原木面提供合成支撑`@base`，新旧完工木面统一参与承载并集。原六个种植箱保持占地保护。4×4/2×4预览优先吸附实际木面边界，结构局部网格跟随当前承载面原点，保留旧板分数米位置。测试在真实家园新建旧规格板、放油灯、贴边建4×4并验证连续导航；另验证真实0.1米水隙不会被当成通路。

二层摆件同样检查角色当前高度和占地，不能在角色脚下建实体。存档容量预留只给种植配方增加Farm记录，不再把墙、灯等新组件误算成未来种植格。

## 最终验收（2026-10-30）

全部运行使用`scripts/run_verification.py`在Autoload前隔离用户目录，未写入玩家存档。下表各项退出0，预期故障0、非预期错误0；过程中的失败日志仍保留。

| 专项 | 当前证据与结果 |
|---|---|
| 纯规则与旧系统回归 | `20261030-181730-kit-final-regression-c7656e`：kit-safety 72项，building、building-integration、building-open-rules、ground-space、character-space-save全部PASS。 |
| 完整游戏接入/实际渲染 | `20261030-181855-kit-full-content-final-a04f28`：visual-building-kit 120项PASS；22组件均经正式Service开工/完工并投影到World，屋顶完整挂点、墙/门差异和全量布局存档有效。已查看kit-assembly.png，楼梯视觉高端与真实上行方向一致。 |
| 最终二层安全检查 | `20261030-182003-kit-upper-safety-final-e65448`：building-kit 121项PASS，含二层角色占地保护、实际胶囊爬升和整档恢复。 |
| 卡片真实鼠标 | `20261030-174817-recipe-cards-final-8834df`：导入PASS，visual-recipe-cards 78项PASS；点击分类、翻页、整卡选择培养土/新油灯和退出，照片/名字/纯材料检查通过；已查看生活摆件完整页。 |
| UV/材质与图源 | `20261030-165252-kit-uv-transfer-58cecd`：导入PASS，visual-kit-uv 563项PASS；22件源GLB转交报告及全览/近景核对通过。 |

机器结果：[完整证据](2026-10-30_modular_building_verification.json)。截图位于各runner工程外证据目录的`project/outputs/`，源验证位于`D:/projects/sea-work/building_kit_v001/`。22件资产转为`runtime_integrated_verified`，只更新本套件及明确接入文件的SHA；其他功能pending资产保持原状态。

操作：菜单→建造手册→分类→点卡片；R旋转、U切地面/二层摆件，M搬移、Delete拆回，右键回手册、Esc取消。屋顶/楼板自动选2.8米挂点，横梁底部2.6米；先建支撑再建顶部。当前只含基础层与一个二层，风车不发电，风铃无声音。手机触屏和实体手柄专项未执行。

收尾门禁：功能契约`--sync`及无参检查均PASS（35功能、513源资产、459运行期资源哈希、0问题）；架构检查17个独立规则/存储服务、0问题。
