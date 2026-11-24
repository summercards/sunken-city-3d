# SEA-ASSET · 美术组件生产与登记

[主文档中控](../../../GDD_V1.0.md#sea-asset) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：生产。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：按 AssetID 定位制作源、清单和正式资源。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-ASSET-R01 | 制作源在 art_source，正式运行资源在 godot/assets，二者通过 AssetID 和登记路径关联。 |
| SEA-ASSET-R02 | 每个资产只在一个分账本拥有主记录，共用资产由功能账本引用。 |
| SEA-ASSET-R03 | 源级完成不等于 Godot 接入完成，授权、哈希、版本和验证阶段如实记录。 |
| SEA-ASSET-R04 | sea 新场景源在 art_source/scenes 下独立建套件，建模前冻结组件计划；同件通过 Collection Instance 复用，建筑与花草分别管理，独立组件包可单独打开。 |
| SEA-ASSET-R05 | 清新治愈场景共用 sea 的 512×512、8×8 方格色板；最多四个材质角色，逐面 PaletteUV 有面积且位于单格安全区，外链唯一色板。 |
| SEA-ASSET-R06 | 建筑和设施可见硬边有真实倒角，段数服从用户明确的面数预算，有机花叶用平滑曲面；交付保存后重开、实例/原点/UV检查及真实全景、近景、俯视和建筑分离渲染。 |
| SEA-ASSET-R07 | sea 场景生产 Skill 随工程保存，移除其他项目的路径、尺度与玩法专属约束；场景资产通过总索引路由登记，源级验收与正式接入状态分别维护。 |
| SEA-ASSET-R08 | 太阳能花屋 v002 按全部可见实例和修改器求值后的三角形合计不超过 3000；花叶采用饱满简约轮廓，扩大木平台并记录连续通行净空。 |
| SEA-ASSET-R09 | 太阳能花屋 v003 按用户最新要求回到已保存 v001，先调整参考图色调及花叶样式；锁定建筑几何与摆位，保留 v001/v002 和公共色板，单独记录当前真实面数，不把风格修订标为低面数验收完成。 |
| SEA-ASSET-R10 | 按 2026-10-24 附件制作独立 pastel_flower_harbor 套件：错层奶油花屋、太阳能前廊、双列同向码头；以附件为唯一视觉基准，不自主简化布局与装饰，植物饱满圆润；不制作船。沿用公共色板，建筑与花草分离，完成组件独立包及保存重开和四视图源级验收。 |
| SEA-ASSET-R11 | 按 2026-10-24 附件在 solar_flower_house v004 重做等距小屋：双层白墙体量＋独立屋顶小屋＋单坡太阳能门廊＋浅木栈桥＋黄色渔船；以附件为唯一视觉基准，建筑、固定陈设与花草分集合，48 项组件各自成包，沿用公共色板并完成保存重开与四视图源级验收；本轮以高还原为目标，不设面数上限。 |
| SEA-ASSET-R12 | 新附件热带花屋：建筑/陈设与花草分离，公共色板与 PaletteUV，保留饱满轮廓和倒角并节省次要面数，完成独立包与四视图源级验收；详见下方条款说明。 |
| SEA-ASSET-R13 | 按本次蓝底花屋附件从零制作 sunny_bloom_retreat，不复用其他工作套件；以厚白错层房体、屋顶布棚、太阳能前廊、双列栈桥及饱满花叶还原参考。按用户修订补齐后侧白墙柱和遮阳棚后柱，调整比例、前廊空间及铺板位置；按用户标线将双列栈桥设于前沿偏左，补成连续全宽前平台并保留右侧活动空间；核对窗洞数量与位置、厚圆角太阳能板，花朵使用明亮粉红与白色、朝上或斜上方随机倾斜；建筑与植物分开，公共 PaletteUV 色板，组件独立包及源级多视图验收，Godot 接入另计。 |
| SEA-ASSET-R14 | 按新附件独立制作 bloom_lower_building 下半建筑：按用户追加要求在原四层下方增加三层，共七层、错落厚白窗湾、蓝灰立柱与天蓝窗、浅杏铺砖平屋顶；花草独立归类，饱满花瓣朝上或斜上方，边角藤蔓长短错落。沿用公共色板与真实倒角，冻结组件计划、独立包及多视图源级验收，不自动拼接上半建筑或接入 Godot。 |
| SEA-ASSET-R15 | 将当前游戏海面五个可玩区的静态建筑单元转存为独立 v0.1 Blender 替换参照；远景按重复楼体与附属几何去重为组件母版，位置/旋转/缩放/颜色记为实例，分账明确可玩区与远景背景。保留原运行几何与枢轴，不重着色、不替换正式场景，记录旧自动拆分边界和未复刻的动态效果；独立水下区域不在本轮范围。 |
| SEA-ASSET-R16 | 现状建筑参照库以中文设施名统一 Blender 场景/集合与资产账本 name，英文 asset_key 对应文件名，原 AssetID 与 Godot 来源稳定可追溯；总览按五个设施分组，每设施内部以“设施名字-海上区域 / 设施名字-海下基座”管理，水面拆分合并后保持原形；保留 v0.1 并交付命名整理版 v0.2 及中文账本。 |
| SEA-ASSET-R17 | 按用户截图将绞盘打捞台从太阳能木屋归类与源中拆开，登记两个独立设施，各有“设施名字-海上区域 / 设施名字-海下基座”；按完整连通构件转移绞盘、甲板、立柱与下方基座，保留原世界摆位、表面积和几何覆盖，总览增加独立入口，中文账本与英文文件同步。 |
| SEA-ASSET-R18 | 按用户要求将当前源与运行文件复制备份为 0.1 快照，再以 sunny_bloom_retreat/v003 替换太阳能木屋海上区域；原制作源及外链色板不改，在独立优化源逐组件清理/导出，保持海下基座与独立打捞台。核对 1.15 倍比例、+Z 正面、平台 Y=2.15、实际包围盒，正式 PackedScene 接入并同步泊位/行走/种植点，真实渲染及专项验证后登记。 |
| SEA-ASSET-R19 | 太阳能木屋 v004 相对已接入版本连同后区整体放大50%，去除灰承台、藤蔓和裂叶植物；后区改水泥、灰封顶和宽窗，补后侧平台及连续女儿墙，梯子出口清空；太阳能房加宽加深向前延伸。前平台酒红横向整板、桥暖木整板且分别成组件；仅清桥入口，保留右侧太阳伞、桌椅、箱子和盆栽。独立新版源、四分区、组件导出与正式行走/泊位验证。 |
| SEA-ASSET-R20 | 太阳能木屋 v005 顶楼水泥残柱与下方承重柱同轴延续，前柱低、后两柱高；阳光房整体右移让出梯子，底板加厚圆角且顶面高度不变；桥加长两排整板，侧边垂绳悬挂四个轮胎，两端保留通行。独立新版源、47组件与四分区，正式接入并同步桥头登岸、行走范围和岸线。 |
| SEA-ASSET-R21 | 太阳能木屋v006所有可见地坪及露台铺木板，移除楼顶帆布及挂钩；太阳伞移至平台右前角避开遮阳板，花朵缩小25%；以此前独立制作的七层bloom_lower_building替换旧海下基座，保留海上/海下归类及稳定包装，独立优化逐组件导出并核对接合、颜色、航路和实景。 |
| SEA-ASSET-R22 | 基于用户手改保存的v006派生v007，保留实际摆位与已实体化网格；黄色地坪轻微错落、轮胎绳接回栏绳，前平台珊瑚/橙红不规则交错加一根赭黄；新增低饱和木色与暖米白色板，海下白色同步替换，独立优化后重新接入稳定游戏路径并实测。 |
| SEA-ASSET-R23 | 场景、UI、角色、道具、特效、音乐、音效各自拥有资产分类分账本，未知来源/授权/正式接入保持 pending，不能以功能账本替代。 |

### SEA-ASSET-R12 · 饱满卡通热带花屋

按本轮用户附件制作 `tropical_flower_house/v001` 独立 Blender 套件：奶白双层体量、屋顶露台布棚、双太阳能板、黄白遮阳棚、双列栈桥与宽厚花叶。建筑/设施和花草分别管理，植物不并入墙体或花盆。遵循公共色板、PaletteUV、组件母版复用与独立包规则。优先保持比例、饱满体积和真实倒角，仅在重复铺板、小叶片和细碎装饰处减少面数；不沿用其他任务的 3000 面上限。统计保存文件全部可见实例求值后的面数，执行重开及四视图源级验收；正式 Godot 接入另行登记。
| SEA-ASSET-R24 | 场景资产细分建筑、建筑升级植物附件、可移动摆件及装饰；装饰下分水面植物与动物。每项登记独立组件入口、所属设施、交互状态及来源证据，保留原始资产路径和已登记 AssetID。 |
| SEA-ASSET-R25 | 太阳能木屋的海下基座与海上平台按装配级变换建立三段关系：平台板底浮于水面上方 0.04 米，基座顶面与平台板底齐平，**基座白色顶板尺寸必须大于上层建筑整体投影、四边各超出不小于 0.35 米**（上方俯视可见一圈顶板边框）。基座倍率由该超出关系反推，不得取小于该要求的固定倍数。支撑面（站立面、泊位、种植点高度）随平台同步位移。该关系以世界坐标断言固定，不依赖组件源比例；从源重新导出后断言失败即为待重接的信号。 |

## 所有者、接口与数据

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-ASSET-R29 | 依据2026-10-28水下参考图制作六栋独立纯景观建筑：错层檐线楼、弧角窗廊楼、窄身竖窗楼、L形矮楼、窄顶附楼和后排板楼。每栋包括全部附着细节的实际导出三角面不超过1000；公共色板、PaletteUV、独立母版包与独立另存优化文件，逐栋稳定GLB/PackedScene。登记为 decoration/underwater_buildings，源级和真实游戏渲染分别验证，参考图商业授权 pending。 |
| SEA-ASSET-R30 | 作物（crops）为独立资产域，主记录写入 `assets/registry/ledgers/crops.json`；每品种一行，四阶段模型列在 `stage_models`，运行 GLB 同步登记 `runtime_resource_inventory.json`。作物不得记入 `scenes.json`，也不得在功能代码里内联构造几何。 |
| SEA-ASSET-R31 | 绞盘打捞台的电线杆、绞盘与攀附花叶为可独立平移的表现组，按2026-10-29截图朝右侧水域移出甲板穿插；平台、桌子、舱口及交互点保持原位置，水平摆位由正式TSCN拥有。旧GLB仅按完整连通组件拆组，顶点色、材质、法线、UV与三角形数量保留，记录工具、原哈希与运行补丁。 |

状态/交付所有者：**制作源负责人 / 各域资产账本**。正式代码和资源入口：

- [art_source](../../../art_source)
- [assets/registry](../../../assets/registry)
- [tools/blender](../../../tools/blender)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

当前场景分账本567行，按两类职责索引维护；其中包含总成、组件、历史源和非建筑，不能按行数宣称建筑栋数。未完成的运行接入、资产归属补登、授权及新职责验收仍按账本保留pending。

现有规则继续运行；独立文档、账本和目录归位不代表所有行为已经独立测试，也不代表全部原始目标已实现。阶段事实以本功能账本为准。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)

## 2026-10-27 开始画面UI资产

`UI-TITLE-SEA-001` 在 `assets/registry/ledgers/ui.json` 独立登记，使用 `UI-FONT-LXGW975YUAN-SC-700`；源为程序化排字布局，参考图仅作风格依据。新增源索引记录，不批量接受历史哈希漂移。[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27：新增独立木板平台 SEA-FARM-CULTIVATION-DECK 与木框土格 SEA-FARM-SOIL-CELL；复用 SEA-SCENE-SBR-COOLER 固定码头出货交互，原授权 pending 保留。[交付记录](../../development/2026-10-27_plot_shipping_loop.md)。

## 2026-10-28 木板厚度与暖木色

| 条款 ID | 规则 |
|---|---|
| SEA-ASSET-R26 | 按旁边家园补给站0.18米浮板参照，将小屋地坪、露台、前平台和栈桥改成约0.22米薄板，暖棕木色与参考同源、轻微深浅错落；保留基座出檐及板底水线关系，支撑面、泊位和交互高度同步，独立源/优化/组件导出与游戏实景验证。 |

## 2026-10-28 绞盘打捞台顶点色回填

| 条款 ID | 规则 |
|---|---|
| SEA-ASSET-R27 | 拆分导出的 GLB 必须保留源里的顶点色；`COLOR_0` 缺失或被写成常量时，允许按世界坐标从**同一几何**的同源 GLB 回填，且不得改动几何、节点层级、材质与导入设置。回填必须在资产分账本登记新的 `runtime_sha256` 与 `runtime_patch_log`，工具留仓库（`tools/restore_salvage_vertex_colors.py`），不得靠手工改二进制。 |

判定依据：`salvage_station.glb` 的 `COLOR_0` 全为 `(1,1,1)`（17115 顶点 1 种颜色），
而材质 `baked_tn_1000` 是 `use_texture=false` 的卡通材质，`ALBEDO` 直接取 `COLOR` ——
顶点色一白，整座设施就是白模。Blender 源 `Color` 属性完好，证明丢失在导出而非美术。

[本轮交付](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 2026-10-28 黄白木船与双桨

| 条款 ID | 规则 |
|---|---|
| SEA-ASSET-R28 | 以本轮用户附件制作独立 reference_skiff/v001：黄白敞口船壳、暖木底板及三排横座、白盖灰紫船外机、绿色行李与浮球，并增加两支木船桨。冻结12组件计划、独立母版/实例与组件包；共用公共方格色板、PaletteUV、真实倒角，保存重开及四视图核验。船壳含舷边保持旧船宽2.574708924×高1.073136871×长5.397479548米及原局部水线、-Z船头；源/独立优化/逐组件GLB与正式TSCN分别登记，保留旧烘焙。正式接入须验证双桨收展、既有灯笼/灯光、角色落点、泊位及航行，商业参考权属保持pending。 |

[本轮交付与验证](../../development/2026-10-28_reference_skiff.md)。

2026-10-29后续修订（SEA-ASSET-R31）：移动后的上段杆身沿原倾斜轴直接延长至原海下深度；删除旧位置的下段立柱。花、绞盘和杆顶不整体缩放。此前“保留三角形数量”仅适用于拆组阶段，本修订允许删除旧下段32三角形。

## 2026-10-30 模块化海上建造套件

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R32 | `ocean_building_kit/v001`包含12结构+10摆件，各一份母版Collection、可打开的独立Blender组件包、稳定GLB与PackedScene及唯一AssetID；按结构/生活摆件分组，共用既有8×8公共色板和PaletteUV、最多四材质角色，可见硬边实体倒角。计划先冻结，保存重开、根变换、非空几何、UV有面积/单格安全区与四视图逐项留证；正式Godot独立加载、模型方向/实际包络和运行功能分别验收。独立制作源不自动重建已有手改场景，功能投影不在游戏里内联生成这些模型。 |

[内容与证据](../../development/2026-10-30_modular_building_kit.md)。

## 2026-10-30 巨手托举纪念品灯塔

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R33 | 按本轮附件独立制作 `liberty_lighthouse/v001`，归类为与阳光房相同的场景建筑组件：8×6米漂浮商铺、双段纪念品招牌、蓝白雨棚、约7米铜锈巨手五指握持约2×5米柱身、直径6米断裂栏杆平台、收窄塔身、玻璃灯室、卫星及通信天线。柱身与巨手竖向重叠，不按7+5米累加。冻结不超过50项的组件计划，使用公共色板、四材质角色、真实倒角、母版Collection及独立包；保存重开、逐面PaletteUV、实例/原点/求值后关键包络及四视图分开核验。仅交付Blender原始文件，Godot、碰撞、导航、商业授权及用户最终美术验收另行登记。 |

[本套件制作、修订与验证](../../development/2026-10-30_liberty_lighthouse.md)。

SEA-ASSET-R32导出补充：PaletteUV必须是唯一UV层，GLB以TEXCOORD_0消费；不能把默认UVMap留作UV0而把色板放到UV1。GLB应保留SEA_Matte/Metal/Gloss/Emission表面角色，Runtime只绑定同源共享色板；灯焰才使用发光材质，玻璃/金属不因角色丢失而统一兜底。源与导出逐mesh色格采样比对，游戏内实际网格UV/材质绑定另验。

## 2026-10-30 海上悬浮商铺

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R34 | 以用户七视角附件及尺寸说明，在 Blender MCP 活跃会话中独立制作 `floating_shop/v001`。整套归 `building/structure`、海上建筑；店体直径约12米，外扩1.2米步行环廊，总高约7.5米，以2×2.2米开放门洞校尺。保留奶黄圆盘体、POSTCARDS/GIFTS/COLD DRINKS弧形招牌、环形蓝白圆垂边雨棚、黄色护栏、10只1米轮胎、左右救生圈、后门电箱、商铺陈列和独立盆栽，以及中央推进器、2只2.5米橙色浮舱、辅助喷口与爬梯。冻结不超过50组件的计划，公共色板与四材质角色、唯一PaletteUV、真实倒角；建筑和植物分集合，重复构件用Collection Instance，组件独立包逐个重开，核查原点/恒等变换/UV单格安全区与全实例实际面数。七参考方向、近景及建筑分离视图由Blender真实渲染；源级与Godot接入分别登记，不自动覆盖正式场景。 |

[本套件制作与证据](../../development/2026-10-30_floating_shop.md)。

SEA-ASSET-R34最新修订：按用户圈图，v002外环平台从1.2米加宽至3.0米（2.5倍），店体直径12米保持；边缘护栏、护舷和爬梯等随外移，正面护栏开约3.43米入口并与2米商铺门对齐。中央通路至少1.95米宽、无陈设挡路、门槛齐甲板；新建v002，保留v001。源/独立包/尺寸/UV及全景、入口、俯视、建筑分离视图复验，运行通行仍待Godot接入专项验证。[修订与实测](../../development/2026-10-30_floating_shop_v002.md)。


## 2026-10-30 海上悬浮商铺接入 main

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R35 | 海上悬浮商铺以 v002 源导出单一运行 GLB：39 组件、248 实例在导出时按 `SEA_Matte` / `SEA_Metal` / `SEA_Gloss` / `SEA_Emission` 四个材质角色烘合并网格，倒角在导出前求值，展示用相机/灯光/背景地面不得进入发行文件。GLB 不内嵌贴图，颜色由 `godot/assets/materials/floating_shop/` 的同源公共色板材质**序列化覆盖**在预制体上，不允许退回「脚本运行时补色」。资产归类 `building/shop`（账本等级＝商店），放置层 `above_water`，正式摆放由 `main.tscn` 的 `World/SeaStructures/floating_shop` 独有：位于阳光房主体（后部方形建筑＋前部倾斜太阳能房）占地中心正南 50 米海面，甲板顶面与家园甲板同高（水面 +0.26 米），板底与推进器沉到水面以下。区块之外的结构没有 ZoneScene 扫描，水面阻挡统一由 `main._water_shapes()` 收集 `World/SeaStructures` 下各结构的 `BlockerSet`，船不得穿过浮店。行走地面、泊位与商店交易界面不属于本轮范围，仍为 pending。注：本条记录的是 v002 事实（39 组件/248 实例、甲板顶 +0.26 米、板底沉水）；v003 起组件/实例数与薄板水线以「2026-10-31 矩形建筑修订」节为准；「行走地面、泊位与商店交易界面仍为 pending」这句只对 v002 当时成立，2026-10-31 已由 R36 与 SEA-WORLD-R14 / SEA-NAV-R12 / SEA-INTERACT-R12 接入，店内空间仍不做。 |

## 2026-10-31 矩形建筑修订（R34 / R35）

本节覆盖早期圆盘外形要求，源版本v003。按用户要求重新设计为约4:3矩形底座与建筑：20×15米甲板、12×9米封闭主体、低坡矩形屋顶及方形主控机箱；移除旧店门、玻璃橱窗与店内陈列。保留宽外廊、前侧护栏开口和海上配色，直线蓝白遮棚/黄栏/护舷/救生圈/植物配合长凳、货箱与系泊柱。32母版、273实例，组件单独成包、建筑与植物分集合；原源保留。

接入沿用R35的稳定四材质网格GLB与PackedScene，必须先逐组件优化、另存并重新打开`v003/export/v001/floating_shop_optimized_v001.blend`，核对源及色板哈希不变、前后同机位保真，再导出；没有把三角化称为减面。序列化的Gloss角色在本轮曾改为不透明釉面；2026-10-31 零售细修（R37）已按用户要求改回透明玻璃，货箱盖则移出 Gloss 槽改走 Metal，两者不再共用同一材质角色。实际摆放和甲板标高保持，水面阻挡按新矩形几何派生，专项须覆盖旧圆盘之外四个新矩形角点，不能只检查中心或沿用旧18.5米包络。行走/泊位/交易不在本次造型替换范围。[本轮设计与证据](../../development/2026-10-31_floating_shop_v003.md)。

R07/R34/R35后续校尺要求：同族海上建筑以正式阳光房v008的最终游戏尺寸为基准。底层净高4.866335米、楼层高5.086335米、楼板及主木板厚0.22米、主柱0.5175米见方、平台板宽0.893551米/节距0.92米；门框整体高3.070845米作为比例参照，不等同净洞口，本建筑继续无门窗。浮店层高校准优先于早期7.5米总高目标；甲板顶仍离水面0.26米，薄板底改为离水面0.04米，覆盖旧厚板必须沉水的R35历史断言。使用阳光房已登记的暖木色板变体，与尺寸标准一并写入项目场景skill（`.agents/skills/sea-scene-component-authoring/`）及其引用文件；本机没有该 skill 的用户级安装副本，不以不存在的副本作为同步对象；不得为校尺修改阳光房本身。注意：v003 全部 blend 实际外链即暖木变体，而贴图 datablock 名仍叫旧名，登记字段以文件路径为准。实际基准与例外口径见[skill尺寸说明](../../../.agents/skills/sea-scene-component-authoring/references/building-scale.md)。

## 2026-10-31 浮店承担最小区块职责

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R36 | 海上悬浮商铺的稳定预制体同时承担两件事：资产装配（4 个 `FSH_SEA_*` 网格 + 预制体上序列化的四份材质覆盖，规则见 R35）与最小区块（WalkArea / LandingPoint / 交互点，规则见 SEA-WORLD-R14、SEA-NAV-R12）。因此根脚本换成 `src/world/sea_supply_zone.gd`（继承 ZoneScene），并且：甲板行走矩形由 v003 的 20×15 米名义甲板派生为「前/后/左/右四条环廊」，封闭主体内部不设行走矩形；`Visual` 下的四个材质角色网格不各自派生阻挡（会得到四份互相重叠的假阻挡），阻挡只由根下那份覆盖整栋建筑的 `Blockers` 提供；结构物不带 Plants / StaticBatch / 建造等级。<br>验收：`floating-shop` 继续检查几何、材质序列化与水面阻挡；`sea-supply` 检查登记、甲板可走/主体不可走、泊位三件套、靠妥到按 E 的完整链路与存档校验。两者都不以截图代替断言。 |

## 2026-10-31 浮店零售细修（摆件 / 广告牌 / 玻璃 / 店内装饰灯）

2026-11-02新增独立渔场套件，不改变浮店内容，详见本页末尾R38。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R37 | 按用户“要上一版的美术感觉、这一版的方形规格，只调摆件、广告牌、玻璃和店内装饰灯”的要求，把 v002 的零售内容移植到 v003 矩形外壳上，**外壳与尺寸一律不动**：<br>· 玻璃：正面 4 个 2 米橱窗单元替换 4 块实墙板（窗带 0.56–4.30 米），Gloss 角色恢复透明（`transparency=1`、`alpha=0.13`、`roughness=0.05`）。**玻璃是陈列面不是入口**：门仍为 0，主体内部仍不可走，由 `sea-supply` 断言。共用的 Gloss 槽必须只承载玻璃，货箱盖改走 Metal。<br>· 广告牌：`sign_gifts` / `sign_drinks` 与既有 `sign_panel` 同高同带（z=7.38），落在 12 米墙两侧各 3.2 米的空档内，不得被遮棚挡住。<br>· 摆件：明信片架、邮筒、售货机、冷藏箱在环廊外侧，避开前侧 3.2 米栏杆开口；店内 4 组货架 + 饮料瓶 + 礼盒玩偶在玻璃内侧可见。<br>· 店内装饰灯：4 盏吊灯 + 1 串橱窗灯，全部用 `SEA_Emission`，且在窗带内（低于 4.30 米），否则会被上部墙板挡掉。<br>组件 32→44、实例 273→296、三角面 429474→520185。<br>· 立体字：广告牌文字必须逐字挤出成实体（厚度 ≥0.08 米、圆角 ≥0.02 米），不得用薄片贴字；三块牌各用一色（深蓝 / 红 / 青绿），允许字超出背板，但缩放必须等比——单轴压扁会把笔画拉细，属于不合格；允许一块牌小幅倾斜（≤5°）。<br>· 字号以 2026-10-31 定稿为准（SEA SUPPLY 0.93、GIFTS 0.99、COLD DRINKS 0.80/0.17 米）：三块牌的实测文字包围盒必须互不侵占，侧牌溢出只允许朝外侧；牌角图标不得删除，可缩小让位（≥0.7 倍）且必须落在字块之外。`verify_v003.py` 必须同时断言「零售件齐全」与「圆形壳体/店门没有回来」。 |

## 2026-11-02 野外渔场独立套件

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R38 | 按用户红框与Plump cartoon风格制作wild_fishery/v001，原板顶6.3401×5.30米变沙土岸坪，保留电线杆与原泊位。计划先冻结12组件、78实例，公共暖木8×8色板、唯一PaletteUV、真实实体倒角、母版Collection/独立组件包及前后侧俯视/近景验收。逐组件在独立优化文件清理、另存重开，核对原源和色板哈希不变后才导出12个无内嵌贴图GLB；每组件独立稳定PackedScene，正式装配TSCN拥有摆位。共享色板采用最近邻、无损、关闭MipMap，导入后持久化材质绑定，组件纯视觉不带未知玩法组。接入FisheryModel.unlocked，替换临时旗并对称恢复外观/岸坪空间；独立加载、原占地/电线杆不变、网低于水面、鱼漂动画、真实胶囊通行、候选存档校验与原生渲染分别验收。来源授权保持pending，运行验收另记。 |

[设计、模型与证据](../../development/2026-11-02_wild_fishery.md)。

## 渔场复用鱼群修订（2026-11-02）

| 条款 ID | 设计与验收 |
|---|---|
| SEA-ASSET-R39 | 围网内复用SEA-DECO-ANIMAL-FISH-SCHOOL既有surface/flat组件，不新增或合并鱼模型。鱼群以独立区块节点实例摆放；wild_fishery正式装配移除14个旧定制鱼，保留11类设施共64实例。Blender源12类78实例为原制作证据原样保留，差异记在装配manifest，正式TSCN拥有当前布局。旧SEA-FISHERY-FISH标记runtime_retired，原包不删除。独立鱼群与收获入口分别进行运行及原生渲染验收。 |

## 水层分类与空间职责（2026-11-02）

用户最新约定：建筑按职责分为水上功能与水下观赏两类，基座明确归水下；跨水线的复合装配不新增第三类。旧五值water_layer迁移记录为历史技术信息。

正式分类以building_class及两个派生账本入口为准，规范全文见 [水层分类与空间职责](../../standards/水层分类与空间职责.md)。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R40 | 仅海上主场景建筑纳入本条，独立海底／潜水场景及范围外参考另外处理。海上建筑只按building_class登记above_water（水上功能）与underwater（水下观赏，含海下基座）；非建筑为null，不构成第三类。主记录唯一保存在scenes分账本，两类入口由AssetID只读视图派生。水上设施在设施层级承接活动区域、泊位、角色／船阻挡和已定义功能；水下各级构件只观赏，不得声明碰撞、可走面、登陆、导航障碍、交互、产出、玩法状态或岸线来源。父水上设施可含水下子件，但不得继承或递归派生其空间功能。旧water_layer／water_layer_role仅保留装配兼容信息，amphibious／backdrop不再是建筑职责类。分类、源级完成、运行验收及授权分别登记，不以旧专项通过认定新职责完整验收；明确基座／底框／水下舱体例外由tools/apply_water_layer.py维护。 |

水上／水下登记入口见[建筑两类账本](../../../assets/registry/BUILDING_CLASSES.md)；本轮分类与运行待验边界见[整理记录](../../development/2026-11-02_building_two_class_contract.md)。

## 2026-11-02 海上屋顶农场独立套件

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R41 | 海上屋顶农场当前登记目标为 `ocean_rooftop_farm/v003`，继续归类为水上功能建筑候选；v001/v002 源、稳定 AssetID 与历史哈希保持不变。v003 固定主文件 `art_source/scenes/ocean_rooftop_farm/v003/ocean_rooftop_farm_v003.blend`，48 个组件沿用 `SEA-SCENE-ORF2-*` 稳定 ID，并新增 `window_cracked`、`window_broken`、`moss_cluster`、`stair_flight`、`stair_landing`、`roof_entry`、`stair_landing_open`、`broken_flight`、`turf_core` 九个组件。按图修正 49.6×33.6×0.65 米厚外挑无草水泥边台、深凹窗、宽主柱、三种破损窗、坡顶高差与不均苔藓；粗杆直径 0.18–0.2 米，金属统一低 metallic 0.15、roughness 0.82。消防梯仅保留 45–60 米上三层 6 段及下挂残梯，取消从地面连续通行；屋顶入口删除共面桥面，边对边接承接板顶 59.97 米。继续排除人物、动物、海洋、天空、远景建筑及其他背景几何，保持公共色板、PaletteUV、最多四材质角色、真实倒角、母版 Collection 与独立组件包。仅登记 Blender 源级完成；登记必须同时满足 `source_verification.json`、`skill_verification.json` 为 passed 且主源哈希匹配，Godot、碰撞、导航、实际玩法功能、商业授权和用户最终美术验收另行登记；当前源验证文档状态先记为 pending。 |

### SEA-ASSET-R41 · v002 登记补充

`ocean_rooftop_farm/v002` 是独立新套件，旧 `v001` 源、AssetID 和哈希保持不变，不覆盖、不更新。v002 计划冻结 39 个组件，水上楼体占地 48×32 米，12 层、每层 5 米、屋顶标高 60 米；包含草地、作物与太阳能组件，排除动物、人物、海面、天空、远景建筑及其他背景几何。组件与总成统一使用 `SEA-SCENE-ORF2-*` 独立 AssetID，登记脚本为 `tools/blender/ocean_rooftop_farm/register_v002.py`。

登记执行前必须确认主源最终稳定；工具执行时才计算 v002 主源和组件源哈希，并要求独立重开主源及39个组件包的130项检查、通用技能验证实际通过。已完成源级验证后仅提升 `source_verification`；Godot、碰撞、商业授权和最终用户美术验收仍保持 `pending`，不得以登记替代运行接入。本轮最终913实例，全部实例求值后681399三角面，四视图已对照参考修正。

### SEA-ASSET-R41 · v003 登记补充

`ocean_rooftop_farm/v003` 是在 v002 稳定 AssetID 上做的当前修订；不更新 v002 源文件、源哈希记录基线或其他资产。主文件为 `art_source/scenes/ocean_rooftop_farm/v003/ocean_rooftop_farm_v003.blend`，组件总数 48（原39＋9个新组件），稳定 ID 仍为 `SEA-SCENE-ORF2-*`。本轮按图完成厚外挑无草水泥边台 49.6×33.6×0.65 米、深凹窗/宽主柱/三种破损窗、坡顶高差、不均苔藓，粗杆直径 0.18–0.2 米；金属统一低 metallic 0.15、roughness 0.82。消防梯仅保留 45–60 米上三层 6 段及下挂残梯，取消地面连续通行；屋顶入口删除原共面桥面，边对边接承接板顶 59.97 米。脚本为 `tools/blender/ocean_rooftop_farm/register_v003.py`。

登记脚本必须先确认 `D:/projects/sea-work/ocean_rooftop_farm/v003/source_verification.json` 与 `skill_verification.json` 均为 `passed: true`，并核对 v003 主源哈希匹配；否则拒绝写入账本与来源索引。源验证文档当前状态保持 `pending`，Godot、碰撞、导航、商业授权和最终用户美术验收仍保持 `pending`，不得以登记替代运行接入。

### SEA-ASSET-R41 · v004 登记准备（pending）

`ocean_rooftop_farm/v004` 是当前待登记修订。主源为 `art_source/scenes/ocean_rooftop_farm/v004/ocean_rooftop_farm_v004.blend`，catalog 冻结为45个组件；旧 v003 的48组件中移除 `bed`、`field`、`cabbage`、`seedling`、`tomato`、`greenhouse`、`tank` 七类，旧作物／菜床／农田记录不删除、不刷新哈希。`greenhouse` 与 `tank` 的旧登记保留 v003 源路径并标记 `superseded_by`，分别指向两组四状态中的两个状态；其余无关 AssetID 保持稳定。

四个新增状态必须各自使用 `component_packages/<key>/<key>.blend` 独立源包，升级组及状态关系只由 `upgrade_states.json` 描述：`greenhouse`、`water_tower` 各含 `unbuilt`／`complete`，两组 socket 共底心定位 `Z=60.05`，默认状态为 `unbuilt`，`game_logic_pending`。基础建筑导出不含四个状态；预期另有 `base_building.blend` 独立登记为 `SEA-SCENE-ORF2-BASE-BUILDING`，但不计入该assembly的45组件catalog。主总成AssetID维持 `SEA-SCENE-ORF2-ASSEMBLY`。

按范围清理屋顶红框菜畦、作物和主屋顶6块太阳能，保留未圈出的上层露台2块太阳能。登记套件为45个组件包＋主总成＋base building，共47条记录。`ledger_index.json` 仅负责账本路由，`current_source_index.json` 独立维护来源索引；执行时保留所有非本任务索引行，不全量重算，并为新状态写入 `upgrade_family`／`upgrade_state`、pair链接和 `game_logic_pending`，保留 `previous_sources`。

`tools/blender/ocean_rooftop_farm/register_v004.py` 默认只做门禁预检，禁止无确认写入。执行前必须确认 `D:/projects/sea-work/ocean_rooftop_farm/v004/source_verification.json` 与 `skill_verification.json` 均为 `passed: true`，主源及45个组件包哈希逐一匹配，并严格复核当前账本与来源索引中待替换的49条旧 ORF2 源哈希；任何漂移都必须报错并拒绝登记。当前 v004 登记、Godot／碰撞／导航／实际升级逻辑、商业授权和用户最终美术验收均为 `pending`，不得以登记替代运行接入。

## 2026-11-02 场景Skill一位小数制作基准（R06/R07）
同族海上生活建筑的新制作按[项目Skill](../../../.agents/skills/sea-scene-component-authoring/SKILL.md)内默认值执行，大尺寸以米、小倒角／板缝以厘米保留一位小数；高精度测量留作溯源。尺寸、源／运行倒角口径、净门洞区别、拼接套件例外及海底范围排除直接写入Skill，项目与用户级安装的Skill和尺寸附件同步。现有模型与运行水线不因取整修改。

## 2026-11-02 水上／水下先分类后加载差异（R06/R07/R40）

海上主场景中的同族水上功能建筑与水下观赏楼／海下基座共用Skill内的一位小数尺寸、倒角、色板、PaletteUV和材质角色；先按building_class判断，再加载水上或水下差异附件。水线偏移只属水上临水平台，水下按真实海面与基座接合摆位且全子树纯观赏；混合设施逐件判断，不从父总成继承功能。独立海底／潜水场景继续排除。[Skill](../../../.agents/skills/sea-scene-component-authoring/SKILL.md)。

## 2026-11-02 水下街景十栋独立套件

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R42 | 按用户文字清单制作 `submerged_street/v001`：断掉的高架桥、L形＋消防梯的破旧公寓楼、快餐车、双拱招牌快餐连锁餐厅、高层公寓楼、红绿灯、电线杆和电线、高速公路路牌、施工中的大楼、普通公寓楼，共十栋独立纯景观建筑。<br>· **风格基准不是目测**：先对阳光房海下基座 `bloom_lower_building/v002` 全部 22 个网格逐面采样 `PaletteUV` 并按面积累计，得到米白三色 82.3%、深蓝玻璃 7.2%、钢灰 1.0%、暖点缀 2.0%、无近黑；十栋按同一分配。<br>· **尺度例外**：层高 2.6 米、窗台 0.4、窗带 1.0、窗宽 1.35、板厚 0.2、承重柱 0.4 米，取自同一份基座实例清单（1.72 源单位节距 × 2.5/1.5/1.5 适配）。这与 SKILL 里 5.1 米层高／0.5 米柱的阳光房水上默认值不同，属用户明确要求按底座比例风格的**登记例外**，不改 SKILL 默认值与其他套件。<br>· 冻结 10 项组件计划后才建几何；公共暖木 8×8 色板外链唯一、`Closest`、不打包；每面 PaletteUV 有面积且完整落在单格 8 像素安全区内；材质仅 `SEA_Matte`/`SEA_Metal`/`SEA_Gloss`，无自发光（废弃街景夜间不得自发亮）。<br>· 逐栋三角面断言 ≤ 预算（预算 700–2400，实测合计 11696），原点在真实包络底心，变换恒等，独立包重开复核，GLB 无内嵌图片且 `PaletteUV` 为 `TEXCOORD_0`。<br>· 自检含两项从实际缺陷反推的检查：单面 >2 m² 且亮度 <0.34 判近黑大面；共面重合面组判 z-fighting。<br>· `building_class=underwater`，全子树无碰撞、可走面、泊位、导航障碍、交互、产出、玩法状态、岸线来源。<br>· 参考图为用户文字清单，双拱标志属商标范畴；授权与商标审核 pending，Godot 摆位／碰撞审查／水下真实渲染／用户美术验收均 pending。 |
| SEA-ASSET-R43 | 沉没街景十栋接入 Godot 主场景并完成观感返工。<br>· **接入**：10 个材质 `.tres` 按 GLB 内 glTF material 名对角色（不靠顺序假设），10 个 `PackedScene` 挂在 `main.tscn` 的 `World/UnderwaterStreet`；位置同时满足四条约束（不压 Zone2 横滨站、不压 Zone1 家园、不压现有六栋水下景观、落在相机可达范围内）。<br>· **高度按屋顶对齐水面**，与现有六栋水下景观同一带：每栋屋脊落在水面下方 1.45 米，底板随自身高度下沉；不允许底板齐平（会让 3.6–16.5 米高的楼顶面沉到水下 11–21 米而完全不可见）。越高越深这条关系写成断言。<br>· **材质覆盖必须落在真正的 `MeshInstance3D`**：写成可编辑子节点再持 `surface_material_override/N`；写在 `Visual` 这类 Node3D 上时，单 surface 旧资产会被引擎占位重映射救回、2–3 个 surface 整组失效，故按逐 surface 校验。<br>· **屋面不得是光板**：水下俯视是街区的主要观看方式，成品屋面须带楼梯间、水塔、空调、通气管等构筑（塌落／拆除类除外）。<br>· **渲染像素级黑块断言**：逐张渲染统计纯黑像素占比 ≤0.15%。逐面 UV／材质审计抓不到"两块板在不同平面共面"的情况（底层窗与门重叠渲染成黑方块，面审计全部合规），只有读像素才成立。<br>· 逐栋取景按实例自身朝向，街面人视按段取景并各自做框内断言；纯景观职责不变，三角面合计 12518，逐栋 ≤ 预算。

[本轮交付、缺陷清单与门禁结果](../../development/2026-11-02_submerged_street.md)。


## 2026-11-04 霓虹花园街区（水上建筑源）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R44 | 按本轮用户参考图制作独立 `neon_garden_quarter/v001` 完整建筑群，明确归海上主场景水上建筑 `above_water`。保留左右高楼夹街、右侧圆弧窗湾／橙色大广告、纵向厚字招牌、后楼屋顶菜园与层叠招贴的结构关系；补全背面／侧面、楼板、屋顶服务间、外部折返楼梯和设施。不制作水体、人物与动物网格。按项目 Skill 使用 5.1 米层高、0.2 米板厚、0.5 米主柱、实体三段圆角、公共暖木 8×8 色板与四材质角色。植物独立于建筑和容器，破损采用大缺角、宽裂缝、断墙与大块残片，不堆细碎结构。广告画明确使用 gpt-image-2；仅印刷面登记 PosterUV／PosterMask 图集例外，PaletteUV 仍逐面有面积并保持活动／渲染层，不复制公共色板。冻结不超过50组件，母版＋独立包重开、逐面UV／变换／原点／图片／几何检查和多视图源级验收后录入场景分账本；Godot／碰撞／导航／功能／性能优化独立待接入。 |


## 2026-11-05 霓虹花园街区 v002 结构修订

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R45 | 按两张反馈图将菜园移至两楼之间的承重连接桥，核对两端承台、同层门洞、桥面通道及下方街巷。右楼以同一弧角贯通地坪、实体墙、七层楼板、玻璃、屋顶和女儿墙，原外挂弧件退役。招牌按店面、墙和桥承台归位，使用实体挂架、完整倾斜变换和可见缺角。建筑采用实际缺失的墙、梁和楼板表现较重破损，地面沿建筑轮廓收边并铺设大块裂板，灯笼破损熄灭并接触地面。保留 R44 的水上分类、公共色板、image-2 图集和植物分离。独立源包重开并检查结构与真实渲染后登记。 |


## 2026-11-05 霓虹花园街区双坡与逐组件接入

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R46 | 按红框扩大两楼间距，在承重连接体上制作双坡菜园、横向屋脊及顺坡种植，保留桥下通道。新版保留独立组件、色板和广告图集，逐组件完成优化另存、重开、GLB 和稳定 PackedScene，并验收源与游戏的结构及材质。 |

## 2026-11-05 家园外围残楼围挡（白盒）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R47 | 在家园四周制作独立 `sea_barrier/v001` 白盒围挡套件，围合同心于阳光房原点，内边界 **240×240 米**（用户三次改口径：150 → 90 → 按红框截图 240）。每边 = 转角腿 10 + 11×20 米件 + 转角腿 10 = 240，整除，无收口件；46 个组件各自独立成包，48 个围合实例。组件按双塌房／斜塌楼／半沉林带三型轮转分配，四条边起点错开。白盒层级：体量、倾斜（6–17°）、真实开洞（窗洞+一层门洞）、墙顶参差破口（0.8–2.8 米）、顶层 30% 整块塌落；不做贴图与倒角细则。共用公共色板与 `SEA_Matte` 单一角色，逐面 PaletteUV 单格安全区。倾斜必须让整栋仍触到水线、楼梯间必须坐在实际存在的顶板上、顶板随墙顶破口下沉。围挡全部落在 240×240 之外，可活动范围内不得有任何几何。**转角只做两条 10×10 腿，不做对角补块** —— 补块按单一朝向手工摆，母版转到需要镜像的那两个对角时会整个落进可活动范围。运行接入（**当前未挂载**）：`godot/scenes/world/sea_barrier.tscn` 曾于 2026-11-05 挂到 `World/SeaStructures`，每段带 `BlockerSet(mode=manual)` 矩形，走既有的 `_collect_water_shapes` 入口挡船，不新建并行通道。同日晚间用户要求「从那个场景里把这套围栏删掉」，已仅从 `main.tscn` 摘除 1 条 ext_resource 与 1 个节点（0 增 3 删，其余逐字节未动），**资产、Blender 源、组件包装、GLB、登记行全部保留**；专项 `sea-barrier` 与 `visual-sea-barrier` 在未挂载时自动降级为只验包装可加载并打印跳过，重新挂回后全部断言与原抓图自动恢复。 2026-11-05 追加（下方结构）：围挡水线以下原只有 2.8 米残堤，再往下是空的。按用户要求补「下方的建筑结构、往下延伸 20 米」：水线下方 -2.8 至 -22.8 米之间做沉没建筑——前后两道带分层窗带与通高破口的外壳墙、两端封口墙、每 3.2 米一层残板、两排按层断开的立柱、每层外挑的残板檐口、底部厚承台；深度 20 米、楼层 6 层（20/3.2）。水下轮廓必须严格收在残堤包络内（y∈[-3.3,3.5]，残堤 y∈[-3.4,3.6]）：一往外扩，整段的对齐基准就从残堤变成水下基脚，被挤走 1 米多、水线处露出可通行窄缝。残堤改为两端各多铺 1.4 米与邻段重叠，堵住转角处 1.3 米的缝。面数：46 件合计 390100 三角面、3320 个网格对象，单件最大 15296（预算 12000／转角 18000）。 |


## 2026-11-05 霓虹花园街区五组件拆分

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R48 | 四个红框分别对应左楼、后楼、右楼、双坡菜园桥。街道地面作为第五个组件独立管理。各组件使用底心原点，独立 Blender 源包和稳定 Godot PackedScene，复用通过 02b 验收的 50 个下层资产，保留结构、植物、设施与招牌的子层。 |


## 2026-11-05 共享植被视效生产协议

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R49 | 后续植物/草地/青苔按[植被视效制作规范](../../standards/植被视效制作规范.md)统一生产：保留公共色板/UV0 与最多四材质角色；风权重、实例通道、LOD、位移包络和材质绑定版本化；新植物复用共享风函数/profile/验证入口，不按套件复制系统。建筑与花盆保持刚性并与植物分离；装饰归 scenes、四阶段作物归 crops；由 ledger_index 路由并查重，保留稳定 AssetID/运行路径。源、优化源、GLB、包装、授权、美术、接入和性能状态分列；旧顶点色与源/运行版本差异先审计，不批量改哈希。实现范围与阶段由 SEA-AMBIENT-R06–R16 承接，本条当前为制作设计。 |

## 2026-11-05 围栏内沉没旧城 Blender 原始资产

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R50 | 按用户七张建筑/场地截图，在活跃 Blender MCP 会话制作独立 `sunken_city/v001`，只交 Blender 原始源，不改正式 Godot 场景。范围为围栏内世界 X/Z 各 -120–120 米；**中央红框仅禁止新增建筑，地板必须完整铺满**，覆盖用户后续圈出的底部和右侧缺块。100 个24×24米独立地面组件实例边对边拼接，180条共边无逻辑缝隙或重叠；街道路口、运河与地坪仍为独立组件，不焊整片。建筑以单栋为组件，商铺贴街、住宅沿巷、高楼退后与组团，保留坍塌空地和院落，不用均匀一格一栋或随机旋转代替城市逻辑。采用项目5.1米层高、0.5米主柱、0.2米楼板及3段实体倒角、暖木公共8×8色板、唯一PaletteUV和三个非发光角色。至少两种实际断体侧倒/断腰组件，部分实例刚性倾斜并按最低世界顶点落地；地面仍正交齐平。道路、高架轨道、电车、车辆、踏板车、电线杆及下垂线、路灯、信号灯、候车亭、售货机、招牌、屋顶水箱/空调/温室和独立海藻苔片不得遗漏；排除动物、人物和背景几何。截图深度用现有60米牧场楼作比例参照，地坪约水面下62.4米（海面1.12、地坪-61.3），该深度为截图估测而非运行精测；组件真实包络另测。冻结≤50组件，独立包逐一保存重开及逐面UV/材质/锚点验收；同机位真实全景/俯视/近景/建筑分离渲染并修正黑缝、穿插、越界和漏地坪。纯水下观赏，全子树无碰撞、导航、可走面、泊位、交互、产出、存档或岸线职责；商业参考授权、Godot水下渲染和性能优化保持pending。 |

### SEA-ASSET-R50 · v002 红框补景与道路横卧（2026-11-05 14:27 用户修订）

按十个红框补充低矮街景、泵柜、售票亭、断墙、大块楼板、废车和独立海藻苔片，形成不同功能与破坏节奏的组团，不用同一套小瓦砾平均填充。新增三个真正绕水平轴90°横卧在车行道上的整楼实例；复用原单栋母版，不复制组件定义，断口保留且按旋转后最低顶点对道路/路沿接地。中央仍不新增完整楼体，仅允许低矮设施和残墙；原100块完整拼接地坪、原37栋楼的实例姿态、原46组件的几何/UV/材质保持签名不变。横卧楼范围内仅8个既有街边设施允许逐项记录后挪开。v001不覆盖；另存v002总源与50独立包，稳定AssetID沿用，升级时保留previous_sources，四种新增低设施另登ID。总源重开、705项局部锁定/接地检查、逐面色板/UV及50包技能验收后再登记；Godot、LOD/性能、商业参考授权继续pending。

### SEA-ASSET-R50 · v003 地形起伏与弯曲断桥（2026-11-05 14:54 用户修订）

最新要求覆盖v002“地坪高度锁定”：围栏内仍100块独立24米域完整铺满，新增4.8米下沉街坊与两侧24米缓坡，原有楼/车/设施保持刚性几何、按局部地形高程落地；不能以整栋纵向缩放、地板错接或随机顶点噪声代替地形。道路在缓坡上保持沥青/路沿连续，180共边按真实网格射线检查普通路沿台阶与运河槽分别声明。已有电车高架从第二段真实端头延伸，复用26米半径45°曲线跨段组成弯曲路线，中段保留名义15米无桥面/轨道的缺口与下方落块；原电车保留，另增两辆置于断口前后完整轨道。50组件预算保持：未用丁字口和运河收口留v002旧源/账本但不在当前布局，新增坡地与曲线高架；当前50组件＋总成升级v003、两个旧定义保留，禁止删历史或改旧哈希。总源/50包重开、逐面材质UV、1061项坡地/轨道结构和全源空间验收后登记，原v001/v002不覆盖。水下纯观赏职责与Godot/LOD性能/授权pending保持。


## 2026-11-05 贴图草皮独立资产域

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R51 | 用户修订后采用柔和草叶/苔藓RGBA贴图和柔性面片，允许该族UV0为BotanicalUV，保留根权重、独立优化源和运行包装；建筑及原花草不改。通过ledger_index新增vegetation独立分账本，逐件登记草叶载体、苔藓载体、共用图集，明确Image-2参考输入、生成描述、原始/处理贴图哈希、源与优化源、实际三角面、消费者及视觉/性能证据。v001被用户否定的实体候选保留源历史并移出运行导出，不登记为已验收复用资产。其余新植物迁移待后续范围。 |


## 2026-11-05 室内房间 bedroom/v001

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R52 | 室内房间按 13 个独立组件包制作：房间壳体（地板／后墙带窗／前墙带门洞／两片侧墙／天花与木梁／玻璃前厅／门框门扇，原点＝室内地面中心、共用房间坐标系）与家具（床／床头柜／台灯／地毯／矮柜，原点＝各自落地中心，便于整体搬动与旋转）。颜色全走 8×8 公共色盘、仅用 Matte/Metal/Gloss/Emission 四角色、GLB 不内嵌贴图；逐包另存独立 `.blend`（`bpy.data.libraries.write` 只写该组件集合，不得整场另存），导出前复核三角面等于源、导出不改源。壳体与家具合计 7888 三角面。灯光、行走面、镜头与碰撞不进 Blender 输出，归正式 TSCN。登记 13 行到 scenes 分账本，`building_class=above_water`、`water_layer=surface`/`role=part`（房间不接触水面，水面阻挡归宿主建筑）。 |

## 2026-11-05 沉没旧城 v003 正式导入（SEA-ASSET-R50 / SEA-WORLD-R20）

用户16:41授权Godot接入，覆盖源级交付时的“未接入”阶段，不改原设计几何。执行02b：50组件各自独立优化另存、重开后才导出50稳定无图GLB，逐组件记录实际清理/前后三角面/源保护/保真；原52份受保护源哈希保持。50稳定PackedScene的材质覆盖必须落在导入GLB真实 `Visual/Root_<key>/Mesh_<key>` 节点，三个非发光StandardMaterial3D角色外链唯一暖木色板，最近邻/不重复、公共贴图无损无MipMap、GLB导入Discard图片。总装50定义/388实例及完整XYZ基变换由运行矩阵断言检查；主场景仅增量挂`World/SunkenCity`，不重建已有手改场景，不给水下件加碰撞/阻挡/导航/交互/存档。原源v001/v002/v003不覆盖，持久优化源归export/v003。按用户随后选择“恢复原水下深度”，仅将编辑器临时上移38.04888米的SunkenCity根Y恢复0，保留其他最新编辑器保存内容并记录单行逆向差异。实际深街面/断桥在现水体吸收下不可清楚辨认，隔水可读性另记待调，不能把无水诊断图冒充正式效果或擅改全局吸收；运行LOD/性能与商业参考授权仍pending。[导入过程与证据](../../development/2026-11-05_sunken_city_godot_import.md)。

## 2026-11-05 沉没旧城 v004 统一限高（SEA-ASSET-R50）

用户后续要求另制浅水可见版并保留现版。新上限只计算一次：`Hcap = max(v003建筑实际高度) / 4 = 14.9147958755m`，不是每件乘0.25；低于上限的两种建筑几何/UV/材质字节不变。超限楼以完整楼层减层并重做屋顶，高处折落残墙做真实断面，不纵向压缩窗门。全部非建筑及坡地/道路/弯桥/电车锁定。v003源与完整运行资产归档保留，v004源/独立优化源新目录，正式模型和预制体仍稳定路径。通过限高/低楼锁定/接地/逐面UV/保真及Godot专项后才登记；原始授权与性能仍分别pending。[v004制作与验收](../../development/2026-11-05_sunken_city_v004.md)。

## 2026-11-06 沉没旧城 v005 连续海床与观赏动物（SEA-ASSET-R50）

用户否定旧城外围追加道路块，v005必须恢复388个原实例；连续海床由Godot Terrain3D独立保存，不伪造Blender源。海床源由4个持久region、作者脚本、独立Terrain3DAssets纹理和PackedScene组成，`collision_mode=0`，不可生成水面阻挡、导航、互动或存档状态。源级海床函数须从实际100个地坪三角几何采样，边缘保留平台后单调向下缓坡。阳光房鱼群和露水建筑海鸥是环境表现独立记录，使用稳定PackedScene和现有procedural fish/bird源；不得接捕捞、库存、经济、交互或存档。

[v005制作与验收](../../development/2026-11-06_sunken_city_v005.md)。

## 2026-11-06 印刷面图集以近景清晰度为准（SEA-ASSET-R53）

| 条款 ID | 规则 |
|---|---|
| SEA-ASSET-R53 | **印刷面图集（广告画、招牌字、招贴）的导入必须无损，近景可读优先于显存占用。** 具体到霓虹花园的 `poster_atlas.png`（2048×2048）：`compress/mode=0`（Lossless），`mipmaps/generate=true` 保留（近景只用 mip0，不损清晰度，但能消远景闪烁），`detect_3d/compress_to=0` **必须保持 0** —— 否则引擎检测到被 3D 材质引用时会把贴图自动转成 VRAM 压缩（实测已发生过一次，`mode` 从 0 被改成 2）。代价是显存由约 2.8 MB 升到约 10.5 MB，这是本条款明确接受的价格。判定依据：这类贴图是玩家贴近阅读的内容，块压缩会在文字边缘与大面积平色处出伪影；而普通色板/地砖贴图不适用本条，仍可走 VRAM 压缩。任何试图"优化"为有损或 VRAM 压缩的改动都必须先得到用户确认，不能以哈希漂移的名义默默发生。 |

[本轮核实与重导入证据](../../development/2026-11-06_doc_drift_sweep.md)。

## 2026-11-06 五米建筑十组件登记（SEA-ASSET-R54）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R54 | `ocean_building_kit/v002` 独立登记平台、实墙、窗墙、门墙、柱、梁、栏杆、楼梯、斜屋顶和平顶十件，配方唯一入口为 `godot/assets/data/building_kit_5m.json`，稳定 AssetID 为 `SEA-KIT-PLATFORM-5X5`、`SEA-KIT-WALL-5M`、`SEA-KIT-WINDOW-WALL-5M`、`SEA-KIT-DOOR-FRAME-5M`、`SEA-KIT-POST-5M`、`SEA-KIT-BEAM-5M`、`SEA-KIT-RAILING-5M`、`SEA-KIT-STAIRS-5M`、`SEA-KIT-ROOF-SLOPE-5X5`、`SEA-KIT-ROOF-FLAT-5X5`。五米模数与精确层高 5.086335 米为本批明确例外；楼梯 27 级、宽 1.5 米，门净洞 1.85×3.1 米，平台以表面中心为原点、其余底心，源米制 1:1，不靠整件非均匀缩放。每件组件源包、GLB `godot/assets/models/building_kit/<id>/<id>.glb` 与 PackedScene `godot/scenes/buildables/kit/<id>.tscn` 分列；归水上功能建筑，实际碰撞/通行由既有建造空间投影拥有，纯视觉 GLB 不重复带阻挡。源重开、PaletteUV、GLB 无内嵌图静态通过仅允许 `stage=source_verified_runtime_final_pending`；最终 Godot 真实运行、通行、UI 与渲染必须由主agent实测并绑定当前文件哈希后独立晋升，不以登记冒充 verified。 |

登记入口为 `tools/register_building_5m.py`，默认只读预检，显式 `--write` 才写入；账本路径从 `ledger_index.json` 解析，来源索引逐字段投影账本现存哈希，不重算其他源。运行清单仅新增十件模型/预制体/新目录、迁移四个建筑 UI 脚本到 `godot/src/building/ui/` 并保留原 `.uid` 与 asset 关联、登记 `building_view`/`building_progress_presenter`，代码哈希严格限定已审阅 building 白名单；main 等并行变更和未知漂移不得顺手接纳。v001 与旧配方原样保留。开发记录由主agent维护于 `docs/development/2026-11-06_building_5m_and_ui.md`。

## 2026-11-07 参考图海上礼品商亭

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R55 | 活跃Blender MCP制作 gift_kiosk/v001：圆角方形甲板/商亭、蓝白圆垂雨棚、三种立体招牌和全部固定配件；47独立组件，结构/陈设/植物分集合，共享既有明亮cozy色板、唯一PaletteUV和四材质角色，饱满3段真实倒角。每组件源包可直接打开，独立优化源重开再导出稳定GLB/PackedScene；浅浮筒和推进器保留参考外观，无水下建筑基座。正式商店沿用sea_supply，旧模型与用户变换保留为旧驿站景观。源、优化、运行、真实渲染、商业参考权属与用户美术验收分列。 |

## 2026-11-07 NPC、住所、花卉资产与内容登记

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R56 | NPC 表现归 characters：`npc_actor.gd` 复用现有 Character/AvatarRig，`npc_accessories.gd` 为七职业各两件配件的正式 Godot 程序源。共用装配、配件库及七职业变体分别登记唯一 AssetID/SourceID，允许同一 source 路径服务多条资产，manifest 回链唯一分账本；外观配置只引用 `npcs.json` 的稳定 ID，不复制外观主表，不覆盖 appearance 所有者的 art_source JSON。 |
| SEA-ASSET-R57 | 住所归 scenes：`resident_harbor` 总装、七独立 house、共用 shell 与 wood/linen/teal 材质分别登记；真实制作源为 `godot/src/residence/author_scenes.py` 与原生 TSCN/TRES，复用已有 5m Kit，不伪造 Blender 源或新增 GLB。港口/房屋/shell 为 above_water，材质非建筑；只在 apply_water_layer 追加本批精确规则。三花归 crops，以 `flower_view.gd` 和三个 flower TSCN 为正式源与变体，保留四阶段节点，不复制前三种作物记录；作物资产合计六种。 |
| SEA-ASSET-R58 | content_index 定点对齐实际8个新增 item、六作物、NPC roster/events/requests/dialogues、residences 与 shops；不复制规则数值。dialogues 主键 npc_id 不伪装成 id：保留 primary_ids 并标注现检查器只支持 id 的 pending 限制。运行清单仅签本轮新增文件与逐项审阅的库存/作物白名单；Main、混合并行 save 及水/鱼/浮店等未知漂移保留原哈希。登记工具默认只读、--write 显式写入并做并发快照守卫；源索引仅从全部既有记录投影，不重算未触源。源登记不等于运行、视觉或商业参考授权通过。 |


## 2026-11-07 礼品商亭室内陈设扩展

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R57 | 商亭增加独立gift_kiosk_interior/v001室内陈设套件：三种PaletteUV配色地砖、圆角L柜台、独立收银机、陈列桌、坐凳、包装柜、海岸主题装饰画、挂钟与壁灯，共11组件；复用原礼品/瓶/卡片/花盆/植物。蓝白地砖以暖黄点缀，真实3段倒角、原cozy公共色板及四材质角色；原47件外观源及运行GLB保持。每件源包能直接打开，另存优化源重开后导出稳定GLB/PackedScene，独立验收UV/优化/保真/运行和实景，不以修改Godot原生几何代替Blender制作。 |

## 2026-11-07 阳光房独立水下区域原生总成登记

既有两条R57作为历史保留，不覆盖或重新编号；本轮接最大R58之后。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R59 | SEA-SCENE-SUNROOM-UNDERWATER-REGION经ledger_index路由scenes唯一登记，manifest回链总成并记录ecology；source_paths为2份TSCN、2份GDScript与水面/局部灯2份shader共6文件，无新blend/优化blend/GLB。旧城50组件388实例、海床、基座、鱼/灯仅复用既有资源，不重复登记、不更新旧源hash；reef12原株/32簇来自旧web baked几何提取，不称新Blender模型。最终67/0运行、89/0真实渲染均exit0/PASS，只签独立场景。父线程以--evidence最终report --write定向写入总成、唯一manifest、source index及分类规则，并仅补六新runtime，building_views未重建。当前50城市组件GLB哈希与旧v005导出50/50一致、source50/50一致、optimized文件50/50存在；未重开，完整优化复用签署/02b、源级完整审阅、原始来源、性能、商业权属和用户美术验收仍pending，不借哈希一致代签。阶段standalone_runtime_verified_provenance_and_production_pending，production_route_integrated=false；原9来源/默认屏蔽不变，全局sync/check待父线程补填，不冒称全工程通过。 |

[最终登记、证据与未验边界](../../development/2026-11-07_sunroom_underwater_region.md)。

## 2026-11-07 阳光房水下 r2 局部美术与碰撞复用边界（已独立验收，产品未接入）

条款沿用R60，追加前最大R59及历史重复R57不重编号，不新增重复AssetID。初填pending为历史时点，当前运行证据与尚待登记分开管理。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R60 | 沿用唯一SEA-SCENE-SUNROOM-UNDERWATER-REGION，父线程正在执行v002定向登记，仅4个JSON目标、15源/17runtime（含2tests），backup/回滚与old history保留；实际写成功/退出码/事务目录待父线程回填，不借专项通过宣称登记成功。总源15文件=原6＋atmosphere相关3（场景/脚本/collision）＋palette/beam/particles/sky/fog/color include六文件；均为本区域原生实现，不伪造Blend/优化源/GLB，不重复登记旧组件。runtime禁用环境雾，以opaque WaterFogPass priority-128及sunroom_underwater_color统一6..110/curve1.3与worldXZ448..500 fade，透明自雾、beam16steps/density基值0.085/soft cap0.23，不回写共享材质；精确碰撞758proxy/85uniqueMeshes/3115351instanceTriangles，physicsrun缓存99/visual158（同精确Basis key因启动浮点拆分而不同，各角色数量/assemblies/triangles一致），50城市源GLB不动。原9图/旧城/base/海床/原GLB共70保护项由父线程在最终核对，未回填前不签全量哈希保护完成；本任务不改Main。Main 可能被并行修改，不要求 Main 字节不变。toplevel/位置/范围/深度保持，production_route_integrated=false。最终232826-signed五入口78/0、264/0、118/0、dive-maps302/0、modules31/0，总793/0全PASS/exit0无unexpected，新区域460/0、回归333/0；运行final已签署。local env/sky/material均resource_local_to_scene，远角像素max0.0078431517/0.0039215982/0.0039215982<0.025、射光开关lit_samples5365>150，不止计数；定向登记实际写入与sync/check真实输出由父线程补。setup1834.253ms/load256.285ms为单次记录，不签FPS；低端/连续performance、rights/user acceptance/完整02b与production仍pending。 |
| SEA-ASSET-R61 | 水下旧城建筑组件必须可封闭：破口、窗洞与缺楼板处补封盖，使网格成为水密闭合曲面（`boundary_edges=0` 且 `nonmanifold_edges=0`），玩家无法进入楼体内部；封盖沿用相邻面的材质槽与 PaletteUV 格，不新增材质、贴图或峰点，且**不得改变顶点包围盒**。限高版另存 `v006` 原地替换运行时 GLB；高楼版另存 `v008` 并单独导出到 `sunken_city_tall`。`v003` 源与 `v003` 运行时导出不得被改动。 |

[最终运行证据、15源/17runtime、定向登记与静态门禁回填](../../development/2026-11-07_sunroom_underwater_art_r2.md)。

## 2026-11-09 B1109A 矩形建筑源级登记

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-ASSET-R62 | `bld_20261109_a/v001` 仅完成源级登记：49 个组件、92 个实例、1 个总成，共 50 行写入 `scenes` 分账本；display name 暂用 `B1109A`，不视为正式命名。源报告 `passed=true`、exit 0、1321844 checks，49 个独立包重开；全实例展开为 390194 三角面 / 204526 多边形。组件植物 `LEAF-CLUSTER` / `SUCCULENT` / `VINE` / `CITRUS` 的 `building_class=null`、`none/none`，其余组件为 `above_water`、`surface/part`，总成为 `above_water`、`surface/entity`。登记保留主源报告哈希与各包 catalog 哈希，补齐组件/总成 `asset_manifest.json`；无新纹理，不登记纹理。阶段为 `source_verified_runtime_integration_pending`，Godot、GLB、运行、碰撞、导航、商业权属和用户最终美术验收均 pending；未修改 Godot、GDD 或主线程 development 文件。详见本轮开发记录链接： [B1109A 登记记录](../../development/2026-11-09_bld_20261109_a.md)。 |

## 2026-11-10 两份专用 Blender 模型组件集合存放

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-ASSET-R63 | 建立两份只读源归档集合：`art_source/vegetation/libraries/v001/vegetation_library.blend`（`SEA-LIB-VEGETATION-V001`，98 AssetID、98 Collection、332 网格、149036 triangles / 80328 polygons，SHA-256 `8703643aaae74e092401d97660621f9f9c70929e14cb11321055247657f4f407`）与 `art_source/crops/libraries/v001/planting_library.blend`（`SEA-LIB-PLANTING-V001`，6品种×4阶段的24组件＋2设施＋6手持＋2装配、34 Collection、8原资产ID、459网格、13364 triangles / 11000 polygons，SHA-256 `dbd4a94c125d775de639e5e14e76d87c1887c4815e6a2bd7fe975e5aee4e6249`）。真实场景名为 `01_组件总览_只摆实例` 与 `02_组件母版_按AssetID追加`，Collection 已 `AssetMark`；展示缩放不改变母版。植物按6语义族分组且每组≤50，未接入源单列，不与正式运行资产混记。三花、42原版植物、荷叶、框、平台、手持均按真实 Godot 静态编辑快照归档，原程序源保持权威，不冒称原有原创 Blend；保留 `PaletteUV` / `BotanicalUV` / 顶点色 / `WindData`，图片只外链，不迁移 Godot 风 shader 与玩法。源验证最终9047 checks/0 failures、`passed=true`；`register.py --write` 已成功，仅为106个原AssetID增加 `library_refs`（`scenes=97`、`crops=6`、`vegetation=3`），旧 `source` / `hash` / `stage` / `runtime` 字段、主记录数量与 `current_source_index` 不变，库成员不重复登记。8个四视图PNG已完成Cycles生成，两个overview与植被top已审阅；不把8图所有细节写成全目视通过。用户美术终审、性能与运行接入仍保持未签；R63不改变既有状态真值保留规则。全库sync/check均因既有 `SEA-SCENE-WATER-BUILDING-001` manifest缺 `asset_ledger` 的KeyError exit1且无同步写入。详见[最终归档记录](../../development/2026-11-10_botanical_collection_libraries.md)。 |

## 2026-11-10 植物命名与三形态模型范围（R64）

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-ASSET-R64 | 植物统一按 104 个稳定 AssetID 采用管理名登记：98 个植被模型来自 `tools/blender/botanical_libraries/plant_names_v002.json`，6 个作物模型来自 `art_source/crops/libraries/v002/component_plan.json`；中文名是项目管理名，不是物种鉴定。每种只制作 `small`/`medium`/`large`（小/中/大）三种静态模型，不做季节变体。三形态必须通过叶、分枝、花蕾、果实等器官拓扑、数量、展开和冠幅变化体现，不得用整体缩放冒充生长；藤蔓使用 `top_center_attachment` 顶心吊挂原点为明确例外，其余植物使用 `bottom_center` 底心原点。v002 模型交付已完成但不接入游戏；纯植物模型不含盆、土、平台或手持表现。既有作物 v001 四阶段保留，v002 三形态不代表运行四阶段覆盖。共享色板外链 `art_source/shared/palettes/sea_cozy_8x8_512.png`，PaletteUV 逐面有面积并留 8px 安全边，使用 `SEA_Matte`/`SEA_Gloss`；原 v001 与原主 source 不迁移、不覆盖。v002 源验证、登记审计与 29 张预览已完成；运行接入、用户审美、性能仍按边界保留，契约 sync/check 仅受既有 `asset_ledger` KeyError 阻塞。 |

## 2026-11-10 编号002水上普通建筑与植被体量修订

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-ASSET-R65 | 按本次原画制作编号002水上普通建筑，稳定AssetID为 `SEA-SCENE-WATER-BUILDING-002`、类别 `above_water`、普通非交互结构。七层米白旧楼、绿窗、屋顶与侧挑太阳能板、方形空调、管线、缠楼树干和分层树冠保留，细碎3D字不做，整栋目标约一万三角面。植被茂盛比例只通过现有18树冠实例体积和位置调整，不新增网格、叶片、枝条或三角形；v003相对v002母版顶点与拓扑不变，非树冠149实例矩阵不变，展开10342三角面/6293多边形。28组件分别独立包、独立优化源与逐组件GLB/PackedScene，建筑/陈设/植物分离；植物6种 `null/none/none`，建筑组件 `above_water/surface/part`，总成 `above_water/surface/entity`。总装增量放入商店旁建筑列、001东侧参考位，后续位置以手改TSCN为准。真实材质覆盖必须序列化到导入后Mesh节点，保留全部XYZ旋转与树冠缩放；正式导入、逐组件加载、实际面数/矩阵/水面阻挡和真实游戏四视图经统一runner核验，不将技术通过等同于用户美术终审、版权或全局接缝穷举。 |

| SEA-ASSET-R66 | 场景模块里的装饰件（作物、藤架、花丛、藤蔓）标 `metadata/visual_only = true`：参与渲染与交互，但不进入 `DerivedWalkArea` 的遮挡判定，也不进入 `BlockerSet` 的水面派生。桥面、楼板、土面、菜床等承重面保留几何身份。模块由 Blender 导出脚本产出时，模板必须一并写入该标记，否则下次重导出会静默覆盖。 |

[制作、体量修订与运行验收记录](../../development/2026-11-10_water_building_002.md)。

## 2026-11-10 参数楼房工坊候选资产登记规则

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-ASSET-R68 | SEA-WORKSHOP V1 生成的楼房是候选资产，不因工坊导出自动成为正式主场景资产。每栋保持独立 `building_id`、版本配方和 `revision_NNNN` 目录，候选固定包含 `building.recipe.json`、`building.tscn`、`catalog_snapshot.json`、`candidate_manifest.json`、`ledger.json`；正式登记由 SEA-ASSET 唯一路由，正式摆位由 SEA-WORLD 负责，`runtime_path=null` 时不得宣称已接入正式运行世界。当前正式样例仅登记 `SEA-SCENE-WORKSHOP-SAMPLE-001` 与 `SEA-SCENE-WORKSHOP-SAMPLE-002` 两个主记录，源为 `art_source/scenes/building_workshop/v001/workshop_sample_001/`、`workshop_sample_002/`，每楼5件候选文件；不得把 `catalog_v1.json` 内部10个组件ID拆作独立正式 Asset 主记录。 |
| SEA-ASSET-R68a | 工坊的原生参数化来源必须如实标为 native/project-authored，不伪造 Blender、GLB 或 02b 生产链；真实 UV 共享色板与 8px 安全边、Native 圆角、`partial_source_style` 与局部空间声明均是当前 V1 工程事实，不等于美术终验、正式导航或全楼可达。水上功能、水下观赏、独立潜水三 profile 的碰撞/走域/水面职责分开记，walk/water 局部声明不能替代正式世界接入。 |

## 2026-11-16 独立建筑外挂32类型与96状态（R69–R73）

全文核号后接最大R68（含R68a），不是接早期R31或R50；旧重复R57与其他历史保持，不新建重复feature。生产范围冻结在 [component_plan.json](../../../art_source/scenes/building_attachments/v001/component_plan.json)，作者源已存在，不追称其在首次建模前已冻结。当前条目统一 `implemented_pending_current_verification`，不代表完整美术Skill、Blender或运行验收通过。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R69 | 以 `godot/data/building_attachments/catalog_v1.json` 的准确type_id/name冻结32个不同轮廓：signage/hvac/water/shelter四族，每族8个明确子族；unique type=32≤50。每type有fresh全新/damaged破损/ruined残破三态，condition axis=3≤5，合计96状态项，不把状态、配色、文字、尺寸、旋转、style计作96个type。逐type计划含唯一planned_key、正式asset_id=null、family/kind/type/mount_mode、底心名义position_bounds、尺寸假设、碰撞责任、三态轮廓、参考来源与hash；后续正式AssetID仅由登记脚本经ledger_index路由scenes并全库查重分配，计划与候选ledger不是正式资产分账本。 |
| SEA-ASSET-R70 | 八类招牌独立style=frame/block/marquee，均可编辑原创粗低面英文实体字，不使用系统字体、第三方字体轮廓、运行TextMesh或运行文字重建脚本；style不是SF档位或新type。当前支持A–Z、0–9、空格及.-!&，最多24字符；不支持、空白招牌或超预算明确拒绝且保留原输入，不静默upper、截断、替字或删字。正面-Z与双面各自外侧须逐字可读不镜像，等比排版、O/B/R保留真实空隙；破损只改载体/框/轨/支架，不删除用户字。未做当前正反面真实视觉不得签读字合格。 |
| SEA-ASSET-R71 | 本套件固定form_style=SF-B，condition三态与SF-A/B/C无关。按用户明确低面预算登记单段实体倒角例外，不改其他套件默认3段；保厚实轮廓、公共暖木8×8色板、逐面有面积PaletteUV与≥8px安全边（原生声明16px）、Closest及solar_cabin四共享角色Matte/Metal/Gloss/Emission，不复制材质/色板。单状态最终全部可见几何默认≤1800 triangles，英文长文>8字符例外≤3500，单glyph≤128，双面字及style边饰也累计。每个真实体量part必须沿最长轴变截面且1%≤abs(rho/taper)≤10%，线性件d_top/d_bottom≤0.953，至少一件反锥；不以常数metadata代替真实截面，不把尖锥rho=1冒充合格，当前自定义锥顶/锥帽等实几何待审。三态必须真实缺件、缺口或弯折，不只重着色/缩放；本次用户授权仅对此外挂套件覆盖旧参考的禁止损伤风格，不修改旧资产或全局规则。 |
| SEA-ASSET-R72 | 作者源为项目原创native代码与版本catalog，不复用旧mesh；既有002、商亭、霓虹花园仅作轮廓/组织参考，旧模型授权/复用pending不能升级为本套件已验复用。计划记录真实源/参考文件SHA-256，商业权属仍pending。每个native JSON保留米制Y-up/-Z/底心、真实meshes/source_parts/collision_proxies/bounds及独立anchorBack/roof；逐part含kind、rho/taper、taper_along、bottom/top、线性d_bottom/d_top、missing_sectors（非圆为显式0或理由）、材质角色、倒角和contacts。attached_to必须有接缝记录，只允许inset/2–20mm clearance/经真实cut_verified的boolean_cut/miter，禁止共面/穿插/flush；未测接触、截面、闭合与实际包络写pending，不补造。Blender由另代理从native快照派生，记derive_pending/derived_native_snapshot并回链源/配方/hash及坐标映射，不能冒称原生Blender创作或已完成02b。 |
| SEA-ASSET-R73 | 每type三态独立静态场景/native JSON/recipe与库manifest计划共96项，保存后独立重载与真实几何/材质/UV/预算/字向/碰撞/脚本安全分别验证。运行层级无脚本、无TextMesh，编辑器controller与生成源不进入静态子树；碰撞仅显式layer256/mask0的逐part简化代理，五类重件可默认开，观赏水下必须显式false且拒绝true。不得从外挂派生WalkArea/导航/泊位/水面阻挡/岸线/泡沫/潜水或玩法状态。候选根与正式库/正式registry分离，不自动正式登记或Main接入；源、衍生Blender、96静态交付、内核、真实视觉、editor、商业权属、用户艺术及性能分域，脚本错误/闭合失败/镜像/未执行hook不被exit0或文件数量掩盖。 |

本轮实读r6报告：核心7712项/10失败、exit1；库96 records且内部passed=true/exit0，但9条脚本错误使outer passed=false；真实视觉484/0、exit0仍有13条unexpected、passed=false。editor在任务交接时无hook执行证据。全部保留 `implemented_pending_current_verification`，不得引用旧工坊1453/0代签。计划中的source_records仅冻结输入，不写资产分账本、runtime清单、派生索引或新AssetID。本次不跑引擎、contracts或style checker，详见[开发记录](../../development/2026-11-16_building_attachments.md)。

## 2026-11-16 v002交付测量与限定例外（R69–R73当前签署）

本节更新旧冻结时点的pending与未登记，不删除r6失败或更改v001计划SHA `246a8a68b51dcd7bf2215475a3c19cf919a377d89391c017cc87742aa7f53fe7`。新增[v002 delivery_validation.json](../../../art_source/scenes/building_attachments/v002/delivery_validation.json)为当前实测及旧计划的明确范围覆盖；不另建FeatureID，不改source/blend目录或注册JSON，全局partial保持。

| 既有条款 | 当前状态 | 实测与登记边界 |
|---|---|---|
| SEA-ASSET-R69 | implemented_verified_in_scope | 四族各8子族仍32type×3态=96项。32个SEA-SCENE-BAT-*正式主记录及32新source index已登记，domain=scenes/category=furnishing；building_class=null、water_layer/role=none/none，tools/apply_water_layer.py:FAMILIES显式SEA-SCENE-BAT-前缀，不自动当水上建筑。v001 asset_id=null是当时计划，不反写。 |
| SEA-ASSET-R70 | implemented_verified_in_scope | 原创stroke实体字与carrier背托，框式/块式/灯泡边饰独立于condition；A–Z/0–9/空格/.-!&最多24字符。中文、小写、未知/超限明确拒绝保输入，不upper/截字；98核心样本=96默认+2改字。破损保原字符串而载体真实缺件，不要求全部笔画断裂；独立字近背板carrier属当前候选美术取舍。 |
| SEA-ASSET-R71 | implemented_verified_in_scope | 当前96项140..1204 triangles、合计45376，221 surfaces、逐件2..4 mesh/surfaces；单件1800/长文3500/glyph128预算门禁保留。SF-B普通box约3.5%、rod约4.8%实形收分与单段倒角；功能锥rho=1、圆件/字形bevel=0及embedded_support必须按下方局部例外承接，不签“全套SF百分百合规”。完整contacts/style及用户美术仍pending。 |
| SEA-ASSET-R72 | implemented_verified_in_scope | native代码/配方/native JSON仍为原创作者与runtime权威；Blender可编辑派生快照32包、1577part、总览96 Collection Instance/0 local mesh，96GLB仅视觉交换。重开exit0/passed=true、90752面UV检查、最小512px²/16px安全边/32px跨度、96GLB无image/texture，最大normal误差0.0001999679≤原0.0003；四图Cycles CPU完成，不称GPU或原生Blender创作。来源/商业权属pending。 |
| SEA-ASSET-R73 | implemented_verified_in_scope | 正式制作库v002有96静态native Godot场景，r10b12103/0完成96冷load+96user重存重载，生产322文件SHA未变；441碰撞代理/15默认碰撞状态。32主记录stage为authoring_library_integrated_art_review_pending_not_world_installed，native源回链保留；初登记313 runtime目标不是当前全库数量，后续librarytest/runner/policy追加由主线程负责。本任务只读不改registry，无生产Main/地图安装。 |

### 对旧计划的显式限定例外（只限本套件v002）

- **BAT-V002-EMBEDDED-SUPPORT**：`geometry.require_connection` 的 `mode=embedded_support` 在字背carrier及少量连接轴/杆使用真实几何嵌入/重叠，clearance=0；这是对v001禁止overlap/interpenetrate的局部覆盖，不是普通宿主挂面净空，更不是任意穿插许可。保逐part contacts/witness和真实修复，不只改metadata伪合规。原生witness只partial，未证明全接缝、全总成无穿插，完整审计继续pending。
- **BAT-V002-FUNCTIONAL-CONE**：锥顶水塔 `tower_conical_roof` 与蘑菇帽 `mushroom_cap` 功能收尖实测rho=1，按功能锥形例外，不将其虚报成普通1%..10%收分；保真实厚度/闭合。
- **BAT-V002-ROUND-GLYPH-BEVEL**：十段圆截面/功能曲面及原创字形实体笔画bevel_segments=0，保低面轮廓和glyph128预算；自定义箭头/拱牌薄挤出按原逐part边处理例外留证。普通box单段真实倒角，不据此宣称每条硬边均已倒角。三态损伤覆盖旧禁止损伤的授权仍仅限此外挂，不改旧资产。

### 内容目录（准确catalog中文名，4×8）

| 分类 | 八种类型 |
|---|---|
| 招牌广告 signage | 横招、竖招、双面悬挑招牌、屋顶架招牌、独立粗字、灯箱、箭头招牌、拱顶吊牌 |
| 机电通信 hvac | 单风扇壁挂机、双风扇壁挂机、屋顶上排风机、墙面轴流风机、接线箱、双计量表、卫星碟、电视天线 |
| 水箱管线 water | 矮圆水箱、锥顶高脚水塔、卧式水箱、拼板矩形水箱、落水管、独立弯管、三通阀管、成束管线 |
| 风管棚盖 shelter | 直风管、转角风管、百叶风口、蘑菇通气帽、烟囱、单坡雨篷、圆拱雨篷、入口柱式棚 |

可用制作源为 `art_source/scenes/building_attachments/v002/components/<type_id>.blend`，每包三态独立view layer、逐part可编辑；总览为 `source/overview.blend`，交换为 `export/<type_id>__<condition>.glb`。运行权威用 `godot/scenes/components/facilities/building_attachments/v002/<type_id>/<condition>.tscn`，不用交换GLB反盖native运行库；Blender不自动参数重建或自动刷新合批。实际改字通过Godot外挂编辑器保存新revision。derived_manifest里早期formal_registration=pending保留为源制作时点，后续正式32登记由本节承接；不能因glTF可导出自动称版权clear。

证据：r10b `/Users/zyq/work/sea-work/verification/20261116-064110-attachments-production-library-r10b-c8e894/report.json`，库12103/0、core11122/0、editor328/0、旧装配78/0、房屋1453/0同工程串行，import/五项exit0、completion=true、unexpected=[]、source_consistent=true；核心有NaN负例警告。视觉r9c507/0、131PNG为当前几何，之前八个悬空bug修闭不等于全接缝美术终审。Blender源独立重开 `/Users/zyq/work/sea-work/building_attachments_source/v002/reopen_validation_final.json`；每state真实bounds/预算/代理与源hash回链由v002补充及原始报告承载，未伪造新测量。使用步骤见[WORLD](../world/spec.md)，[交付页](../../../outputs/building_attachments_review_20261116/index.html)与[开发记录](../../development/2026-11-16_building_attachments.md)。全工程sync/check、性能/GPU、人工/多视口/gizmo、商业权属、艺术终审和生产Main/Walk/shore/boat/dive均未签；不预写历史488为当前门禁。

## 2026-11-19 海上屋顶街机维修铺 · Blender 源与动画

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R74 | `rooftop_arcade/v001` 为 `above_water` 制作源。按同批内外图还原街机维修铺、红砖中段、屋顶卧室和外部梯具；不规则砖、屋顶、布棚和家具以实体网格表达。母版、完整装配、室内剖视与组装动画分场景；底座至屋顶分阶段入位，砖块各自错峰，片尾与静态装配对齐。按共享 8×8 外链 PaletteUV 与四材质角色验收，逐件提供独立 Blender 包和静态交换 GLB。角色净空、泊位、运行接入、整套接缝及参考商业授权不由源级检查签署。 |

[开发和自检记录](../../development/2026-11-19_rooftop_arcade.md)。

### 组装动画修订：工整入位

R74 源资产沿用 v001。实例在动画中保持最终装配朝向、尺寸和平面位置，仅沿 Z 轴缓降；各排砖自下而上、同排按固定顺序进场，不做斜飘、翻转、缩放或落地反弹。动画采用固定正交机位，静态造型、摆位与用色保持原样。

v3 进场规则：全部实例先完整停在画面上沿之外，再沿 Z 轴连续从上方落入；不以显隐切换或缩放代替进场。v3 片尾第 345 帧与静态总装对齐。

v4 按用户反馈缩短装配节奏，保留画外入场与固定镜头，改为加速下落、触地后两次衰减微弹。大件回弹幅度小于砖块和轻型陈设，反弹仅沿 Z，不低于原装配高度；第 222 帧全部与静态总装对齐。

## 海上屋顶街机维修铺 · Godot 接入

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R75 | 沿用 `SEA-SCENE-RAC` 与 41 个组件 ID，以单独的优化 Blend 派生静态 GLB；原始模型和 Blender 组装动画不改。正式总装引用稳定组件 PackedScene，运行材质使用独立共享 8×8 色板；参考图权属仍待确认。游戏落点与空间职责见 SEA-WORLD-R42。 |



## 2026-11-19 最小入口原生平台与斜坡组件

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R76 | 登记 `SEA-SCENE-MIN3C-DECK`、`SEA-SCENE-MIN3C-RAMP` 两个水上结构组件。原生 Godot 白盒以独立 TSCN 为几何源，无 Blender/GLB、成品建筑形体或贴图流程。根保持单位缩放，编辑器可见网格与静态碰撞分离。旧可玩总览登记为可选入口，来源和路径保留。 |

[开发与证据](../../development/2026-11-19_minimal_main.md)。


## 2026-11-19 最小海面入口：海上 3C

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R77 | 白盒直接引用 `SEA-SCENE-SKIFF-ASSEMBLY` 的现有外观、座点与握点，不发行新美术资产 ID。原生碰撞和码头标识属于 `main_minimal.tscn` 的装配。保留模型、源、预制体和商业参考权属 pending。 |

[开发与验证](../../development/2026-11-19_minimal_sea_3c.md)。


## 2026-11-19 现成划桨复用与固定木块补充

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R78 | 一个项目原创 Godot 白盒木块组件、三个实例，登记 `SEA-SCENE-MIN3C-TIMBER`，不复制模型或发三个 ID。木块用严格一致的长方体网格与形状；不套成品建筑造型，也不重做船。 |

[开发与复验](../../development/2026-11-19_minimal_sea_3c.md#补充复验现成划桨与海面木块)。

## 2026-11-20 角色头发资产换版

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R79 | 沿用 characters 分账本的 `SEA-CHAR-HAIR-001`。v003 延续 Godot 原创参数网格制作方式，正式源和消费路径保持一致。头发主体为一张至多 2100 三角面的连续索引网格，发饰独立。以头部局部尺寸制作，通过原挂点随角色缩放。登记当前版本、来源哈希与验证证据。 |

## 2026-11-20 发束走向资产换版

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R80 | 继续使用 `SEA-CHAR-HAIR-001` 与正式源路径。v004 增加曲面取样密度以表现发束隆起和沟槽，当前主体面数上限 3700，承接 v003 的单张连续索引网格与独立发饰。同步记录本版源码哈希和真机图。 |

## 2026-11-20 阳光房 Blender 结构与动画

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R81 | 在 `SEA-SCENE-SBR-ASSEMBLY` 的原制作源按本轮参考调整结构。继续使用原暖木色板和四材质角色，保留对应平台、梯口和栈桥接口。中央多余木板省略，草木由游戏生成。梯后旧洞补实体，梯级留出墙距。落装组件分阶段沿 Z 轴下降，结尾与完成场景对齐。伞面与伞骨循环随风变形，伞杆及底座固定。保存后用 Blender 重开，核验几何及姿态和实帧。 |

## 2026-11-21 建筑组装动画资产标准

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R82 | 每栋建筑交付一段与自身组件及完工姿态相符的建筑组装动画。登记资产 ID、制作源、Godot 场景、动画名、时长、播放状态和验收证据。动画末帧与完工模型对齐。建筑的常驻环境动画可独立播放。触发契机由玩法设计另定，未定时建筑载入即显示完工态。阳光房首个接入，其他已有建筑逐栋补齐和核验。 |

## 2026-11-23 建造目录组件的分件制作

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R83 | 自建组件保留各可独立落地的网格部件。五米套件沿原 Blender 源、原色板、包围盒和安装基准导出分件模型，沿用 AssetID 和稳定预制体。组件预制体拥有模型与成品碰撞，表现层按部件生成落装剪辑。路灯先底座、再灯杆和灯头。五米楼梯先承重件、再由低到高铺设踏步。施工结束后恢复各部件的常驻表现。 |

## 2026-11-23 制造区码头外观

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R84 | 制造区码头木板沿 5 米长边通铺，甲板深 2.5 米。靠船侧配一只取自阳光房栈桥的吊绳轮胎。原色板下分件导出，初始与可建码头共用 Godot 组件。 |

码头使用三条与 5×5 米普通木平台同规格的宽板，单板取同套件源的实际宽度和倒角。

## 2026-11-23 起始种植区与四轮胎护舷

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R85 | 码头复用阳光房栈桥的两根柱子和四只轮胎，轮胎沿靠船一侧等距排布。柱子和轮胎使用原场景成品尺寸与材质，甲板保留原宽板规格。 |

## 2026-11-23 海上屋顶牧场双形态

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R86 | 屋顶牧场 v007 依据参考前两幅制作破损与完工形态，铺地和完工设施取第二幅布局。开场温室架倒塌、罐体侧倒。五处地块、小屋、温室和水塔可各自修复，温室和水塔修复后恢复安装基础。随后新设施按阳光房落装方式垂直下降、回弹并归位。制作源采用海上功能建筑规格、共享暖木色板、独立设施包和可单独播放的 Blender 场景。重开核验制作源、完工外观和各剪辑终点。玩法触发和运行碰撞在正式接入时验收。 |

## 2026-11-23 海上屋顶牧场近景深化

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R87 | v008 在破损态也要保留登顶接板、前沿连通铺面，以及通往小屋、温室和水塔外侧的支路。以内侧塌陷区承接地块复原。地砖使用共享色板邻近色，水塔保持蓝绿色金属罐体。小屋斜置并做实体坡面，按近景参考深化围合、转角破损、烟囱、窗框及红瓦门廊。四个材质角色统一读取共享 PaletteUV 色板。源级以角色胶囊尺寸检查路线，正式运行通行另行验收。 |

## 2026-11-23 屋顶小屋檐口与外墙构件

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R88 | v009 单独深化左侧小屋的破损与完工形态。混凝土压顶保留方截面及平直侧面，破损态有实际缺角和露筋。窗扇分片，剖面区分墙洞、窗框、玻璃和窗台。檐沟、空心落水管、墙面管卡以及带回钩的梯子为独立构件。破损态有缺档、弯折、断管和剩余承台。复核主时间线与独立维修场景的构件切换，并在 Blender 查验正面及斜侧实拍。 |

## 2026-11-23 屋顶小屋大块嵌砖与分件接入

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R89 | v010 侧墙和转角疏排大块嵌砖，使用暖灰、米砂和蓝灰三组共享色板。砖块分别动画并在终点归位。小屋分件从另存优化源导出，每个部件独立 GLB 和包装场景，沿用原四材质与公共色板。核对破损、修复过程和完工各帧，验证正式 Main 实例可播放。 |

## 2026-11-23 顶层牧场整套正式资产

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R90 | 在原始 v010 制作源之外另存并重开优化文件，逐件导出 46 个组件，正式装配保持 390 个独立实例。Godot 使用四个共享材质角色与暖木色板。码头、楼板、护栏、墙、设施和船体阻挡随所属部件；破损地块按实际支撑登记可走面，分件安装完成后启用对应实体。登记正式场景、各组件及来源，验收破损和完工的游戏实拍。 |

## 2026-11-24 顶层牧场主楼结构深化

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R91 | v011 沿统一柱网重做主楼两层柱、层间梁、转角承托、窗过梁与高台收边。窗下采用独立实体错缝砌块。四种窗跨在上下层与相邻跨错开排布，玻璃缺失范围、掉角和凹进砖配合变化。继续使用四种共享材质角色及公共色板。结构组件分开导入，以 Blender 同机位前后对照和 Godot 实拍验收。 |

## 2026-11-24 顶层牧场错缝地砖与温室石基

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R92 | v012 选取局部铺面替换为不同长短的错缝实砖。砖面保持原支撑标高，塌陷区铺面按原区域修复节奏归位。温室底座以高低和出挑略有差异的石基及低门槛接到铺面。分别导出铺面与底座组件，统一沿用共享材质和色板。 |

## 2026-11-24 顶层牧场破损态野生植被

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R93 | v013 复用植物工坊的柔草、草堆及共享苔藓，以成簇布局沿实际开裂铺面、废料、栏根、墙脚和屋檐落位。源文件保留可编辑植物实例，Godot 复用正式植被模型与材质。确认破损和清理后画面。 |

## 2026-11-24 顶层牧场下沉及水下七层

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R94 | 在现有两层下方增加七层，每层采用同一 5.1 米层高并设计不同的缺跨、断柱、断梁及塌板位置。九种水下结构件和改短的登顶梯分别制作、另存优化并独立导出。水下部分归观赏建筑。以实际网格、楼层分布、共享色板及 Blender 与游戏图像验收。 |
