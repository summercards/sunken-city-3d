# 2026-11-02 野外渔场模型与升级接入

承接SEA-AQUA-R05–R08、SEA-ASSET-R38、SEA-WORLD-R15、SEA-SAVE-R15。用户指定红框覆盖范围：原木板占地改为野外渔区陆地，电线杆不动，水域布置海面以下的渔网、圆浮漂与中间鱼群，风格厚实、圆润、饱满、软倒角。制作、验收、导入、升级和可行动区域由本任务完成，不追加重复审批。

## 现有功能与冻结范围

既有FisheryModel已经提供100木板+50鱼、背包仓库合并扣费、升级入口和可选unlocked存档；此前外观只是临时旗。本轮保留升级规则，以正式模型替换标记。鱼群为渔区环境表现，不新增投苗、投喂、产出周期或收成数值；这些原规划条款仍保留在SEA-AQUA-R01–R03。

统一runner对正式场景实测木板顶部几何：XZ `[-16.203999,-9.863899] × [10.095800,15.395800]`，约6.3401×5.30米，顶面1.33米。原逻辑矩形为7.5×3.3米，不能当作模型真实占地；本轮升级后的行走域按真实岸坪生成并排除陈设。原登陆点(-11.6,1.33,12.6)、船位(-6.55,1.12,13.9)、木牌(-13.2,1.33,11.4)保留。红框前侧围网按约12×10米、四角1米切角落位，网顶0.96、网底约−1.24米；14条浅水鱼位于中部。所有数值在组件计划先行冻结，未用太阳房通用尺寸覆盖原泊位。

范围探针：`D:/projects/sea-work/verification/20261102-112418-fishery-site-contract-bc96b2/`和`20261102-112536-fishery-deck-contract-bda758/`，分别实测当前节点/泊位及真实板顶面。原GLB和电线杆签名记录在计划及工程外scope_baseline.json；本轮不修改旧GLB。

## Skill与资产交付

采用项目`sea-scene-component-authoring`、`blender-game-prop-standard`和`02b-godot-model-asset-import-standard`，目录、8×8公共色板与米制规则以sea项目为准。12个组件族内均不超过3个，78个Collection Instance：圆角沙岸、草苔、圆石、蒲草、晾鱼架、圆鱼篓、饵料台、圆浮漂、短旗漂、直网、角网和圆润鱼。

- 源母版：`art_source/scenes/wild_fishery/v001/wild_fishery.blend`，独立组件包在同目录`component_packages/`。
- 优化派生：`export/v001/wild_fishery_optimized_v001.blend`，保护原源及色板哈希；逐组件清理重复/退化/孤立几何、有限共面溶解，保留所有未证明不可见的底/背面，再规范化原色格UV。独立母版统计14420→14332三角面，未把三角化称为减面。
- 每组件独立GLB位于`godot/assets/models/fishery/<key>/<key>.glb`，独立包装位于`godot/scenes/components/fishery/`；正式装配为`godot/scenes/facilities/wild_fishery.tscn`，由zone1定点引用。没有导出一整屋GLB，也没有重建原TSCN。
- 优化派生内部再按单个组件合并同材质网格，原制作母版的零件仍可编辑；每个运行组件只保留一个视觉网格，78个实例对应78个视觉网格，避免每根网绳各占一次绘制。
- GLB不含贴图，PaletteUV为唯一UV0。EditorScenePostImport将同源公共色板材质持久化到导入资源，不在游戏流程临时补色。各组件元数据含稳定AssetID、版本与类别。

源级验收：32301检查、7462面逐面UV核验、12独立包逐个重开、母版14,420三角面、全实例79,820三角面，0错误。通用skill附带验证器固定10×10格，故本轮以`verify_source.py`执行sea的8×8/8px安全边完整核验，并通过`validate_game_prop.py`对原skill验证器仅替换8×8单格审计函数，其他材质/活动UV/外链图/自发光/输出检查不变；12独立包均通过，源哈希不变。Blender源和优化版均有全景、背面、侧面、俯视和岸坪近景；亲眼核对优化前后轮廓、圆角、色板及围网无变化。

制作与优化证据：`D:/projects/sea-work/wild_fishery/v001/`；资产来源授权依然按用户截图来源登记pending，模型为本任务独立制作，运行验收状态与参考权属分开维护。

## 接入与通行

FisheryVisual只消费升级状态，拥有表现投影；业务仍由FisheryModel唯一写入。旧合并地上网格升级后隐藏，电线杆/花和海下基础保留。升级/读档/未升级恢复对称切换，模型不会重复生成。旧旗退役。

岸坪用真实圆角轮廓生成WalkArea多边形，并从边缘扣除晾架、工作台和鱼篓占地，复用GroundSpace的真实胶囊地面/边界和导航。围网水域不生成行走地面，水域查询单独声明为围网占用，缓存失效后船、浮木和随机鱼避让，外侧和原泊位航行仍保持。候选存档先按候选unlocked验证水域和角色位置，恢复时在角色复位前建立相应地面；旧升级档的板缘位置在原支持域内就近移回新岸坪。

## 当前实测

运行验证均走统一runner、Autoload前隔离用户数据。独立加载、升级、模型/材质、原占地/电线杆保护、真实胶囊到达、围网下沉、鱼漂动画、旧档与跨状态存读均在最终组件输出上实测，见下表。

| 检查 | 当前实测 | 退出码 | 渲染 |
|---|---|---|---|
| 正式资源导入 | 12个GLB，公共色板无损/无MipMap、导入脚本持久化材质，无SCRIPT/SHADER/引擎错误 | 0 | 编辑器导入 |
| fishery-environment | 39项0失败，12件独立加载且每组件1网格，升级/原占地/电线杆/真实胶囊/围网/存读均覆盖 | 0 | headless |
| visual-fishery-environment | 43项0失败，含升级前后、岸坪近景、人物实际到岸边四张原生图 | 0 | 真实渲染 |
| fishery | 26项0失败，既有升级扣料和存读回归 | 0 | headless |
| visual-fishery | 28项0失败，既有改造页及升级效果 | 0 | 真实渲染 |
| minimum-loop | 141项0失败 | 0 | headless |
| ocean-pickups | 48项0失败 | 0 | headless |
| progress-bars | 45项0失败 | 0 | headless |

最终组件/导入专项报告：`D:/projects/sea-work/verification/20261102-140048-fishery-component-final-2c64bb/report.json`。最终集成与每件1网格断言：`D:/projects/sea-work/verification/20261102-140321-fishery-final-integration-4bf4da/report.json`。第一轮39/42项通过记录保留于`20261102-135216-fishery-environment-1b245b`；后续增加实际人物岸边截图，因此最终渲染为43项。

最终实景图均在组件专项目录`project/outputs/`：`fishery-environment-before.png`、`fishery-environment-upgraded.png`、`fishery-shore-close.png`、`fishery-shore-walked.png`。原始模型、独立优化、各组件GLB和稳定场景在13条新增场景资产中一一追溯，运行验收完成、参考权属pending分开记录。

无预期引擎错误；主动坏档由API拒绝，不产生SCRIPT ERROR。初次最终导入复查`20261102-135529-fishery-final-specialists-63eae2`曾因工作区同时新增的save_game.gd归档代码类型推断失败而停止（引擎退出0但runner因错误判失败）；当时源内该行随后已有显式String修复，未改动该归档功能，本轮重新导入及上述专项全部通过。Blender首轮建模曾因误用Vector.distance中止，修正为向量差长度后重建；正式源、独立包及后续验证均重新生成并通过。导航体素精度WARNING单列保留，不记成预期错误。

未执行：养殖投苗/投喂/周期收成玩法、专属音效、手柄/发行平台、长时人工游玩及整套core。没有写入玩家存档。必要集成以本轮实测为准，额外的浮店检查结果单独列于后文，不冒充全部绿色。

## 浮店范围外失败对照

额外集成`sea-supply`为37项、8失败、退出1。失败全部在浮店既有甲板/泊位几何：当前main.tscn浮店根已有旋转、非等比缩放及Y=-18.097904，而旧测试仍按水平20×15米、甲板1.38米、水面船位1.12米的基准断言。该根Transform与开工前`20261102-112418-fishery-site-contract-bc96b2/project/scenes/main.tscn`逐字相同，本次未修改main.tscn或浮店Prefab。

为排除渔场回归，使用同一`scripts/run_verification.py`实现，将只读GODOT_ROOT指向开工前隔离工程（不改正式工程、不写玩家数据），重新跑sea-supply；证据`D:/projects/sea-work/verification/20261102-140617-fishery-prechange-sea-supply-220163/`。原代码/场景也为37项、同样8失败、退出1，且8条失败信息与当前逐条相同。因此这项保持既有浮店几何/旧断言不一致状态，不改用户手工TSCN以凑绿。

## 文档与登记门禁

13条新增资产（12组件+1参考装配）登记到索引解析的scenes分账本，派生current_source_index由全部分账本重建。运行资源只接纳本任务已检查的GLB、包装、导入脚本/材质及共享色板导入契约；编辑器补齐的默认导入元数据经定点核对后同步，没有批量接受其他未知哈希。

功能文档、独立账本、主文档已更新。最终`check_feature_contracts.py --sync`及不带参数检查均退出0：37功能、578源资产、508运行资源哈希，0 issues；`git diff --check`退出0。结果与日志位于最终集成证据目录的`feature-contract-report.json`、`feature-sync.log`、`feature-check.log`、`diff-check.log`。

2026-11-02后续修订：鱼群改用现有彩色海面鱼且独立于设施，二阶段去牌并接自动产鱼/收获。本页12类78实例为原始Blender制作证据，正式运行现为11类64个设施实例加独立20条鱼。最新规则和验收见[渔场产鱼修订](2026-11-02_fishery_production.md)。
