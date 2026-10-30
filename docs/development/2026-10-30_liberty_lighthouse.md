# 2026-10-30 巨手托举纪念品灯塔 Blender 源

关联功能：SEA-ASSET-R33。用户要求按当前附件，在已运行的 Blender 中经 MCP 制作与阳光房同属场景建筑组件的新建筑；本轮先交付原始 Blender 文件，完成后更新账本，不包含 Godot 正式接入。

## 范围与来源

- 套件：`art_source/scenes/liberty_lighthouse/v001/`。
- 母版：`liberty_lighthouse.blend`，场景 `巨手灯塔_制作与装配_v001`。
- 参考：用户剪贴板附件原字节保存为 `reference.png`，SHA-256 `ca3eca8b2e48c3f0ec0d4479320d8b66e56baa961f76e59ca1d3b15658af1a53`；扩展名沿用套件参考命名，没有执行 JPEG 到 PNG 的图像转码。商业使用权 pending。
- 独立新建几何，不复用阳光房的建筑外形；共用既有 `art_source/shared/palettes/sea_cozy_8x8_512.png`。
- 制作前冻结 `component_plan.json`；雨棚原点与净高修订在该文件中追加 as-built 说明，不回写伪造最初冻结状态。
- Blender 4.5.0，经本机 `127.0.0.1:9876` BlenderMCP 裸 TCP JSON 执行；桥接工具 `tools/blender/liberty_lighthouse/mcp.py`。没有修改用户插件配置。

## 交付内容

| 内容 | 结果 |
|---|---|
| 完整 Blender 母版 | 30 个唯一组件 Collection、55 个 Collection Instance；展示海面、相机、灯光不进入独立组件包 |
| 独立组件包 | `component_packages/<slug>/<slug>.blend` 共30份，各有 `asset_manifest.json`，全部保存后单独重开 |
| 漂浮商铺 | 8米驳船长、约6米宽、做旧外壳、11个轮胎实例；2.8米墙壳、开放门口、侧窗/服务窗、告示、ICE柜、消防栓、交通信号及独立广告牌 |
| 招牌与雨棚 | 7×0.8米双段黄底招牌，红色 `SOUVENIRS`、`LIBERTY S...`；蓝白前沿雨棚及侧面条纹 |
| 巨手与柱身 | 青绿色手臂/手掌、四指加拇指握柱、竖槽柱身与检修门；柱身与手掌竖向重叠而非高度相加 |
| 观景平台 | 约6米圆台、厚底板、线脚/托臂、断口栏杆、设备箱、斜置太阳能板 |
| 灯室与天线 | 2.5米收窄塔身、2米多边形玻璃灯室、透镜灯座、3.5米桅杆、1个圆卫星天线及3块矩形通信天线 |
| 数据清单 | `catalog.json` 记录包络、几何指纹、组件包路径与哈希；`component_instances.json` 记录完整位置、Euler XYZ和缩放 |
| 渲染 | `sea-work/liberty_lighthouse/{beauty,detail,shop_detail,top}.png`，均为最终保存源的真实 Blender 渲染 |

组件类别 `structure` / `facility`，装配 `scene_assembly`；范围 `scene_local`，不虚构跨场景共享消费者。组件根位于 XY 居中、局部底面 Z=0，Collection.instance_offset 为零；雨棚装配实例拥有世界下缘 Z=3.50米。重复轮胎、手指、栏杆和通信板使用实例而不是新增母版。

## 尺寸与雨棚复核

源级检查使用求值后的网格包络。母版基座长8米、宽约6米，柱身高约5米，平台直径约6米，塔身2.5米、灯室2米、桅杆3.5米；桅杆顶部天线形成约25.4米总高。关键记录见 `sea-work/liberty_lighthouse/verification.json`。

复核发现初版雨棚后段位置过低。修订后雨棚组件采用局部底部中心原点，装配下缘世界 Z=3.50米；甲板顶面局部最高约1.24米，棚下实际净高约2.26米，接近但不等于原目标2.4米。前沿与商铺招牌的环绕/空间关系仍有后续打磨空间。独立包和装配统一该约定，验证同时检查局部原点与求值后的世界包络。

## 材质、UV与几何验证

- 统一 `SEA_Matte`、`SEA_Metal`、`SEA_Gloss`、`SEA_Emission` 四材质角色；颜色由公共色板的 PaletteUV 决定，不为每色新增材质。
- 母版与独立包所有网格只保留活动且渲染启用的 `PaletteUV`；逐面检查非零面积、单格归属及至少8像素安全边，图片外链、Closest、未打包。
- 最终完整检查：30组件、55实例、48539个母版面UV检查；可见实例求值展开为68759多边形、132596三角面。此任务未指定低面数上限。
- 30个独立包单独重开并重复几何/UV/原点检查；雨棚的世界高度使用修改器求值后的包络，不用未求值坐标代替。
- 验证命令使用 Blender `--background --python-exit-code 1 --python tools/blender/liberty_lighthouse/verify.py`，最终退出码0，报告 `passed=true`、`errors=[]`。
- 最终全景、巨手/柱身近景、商铺近景和俯视均已目视查看：主要竖向层次、五指控柱、招牌、入口、轮胎、平台和天线可辨认，未宣称逐像素还原或用户美术验收通过。

## 可复现顺序

正式工具顺序为 `prepare.py → build.py → cleanup.py → verify.py`，前3步在任务所属 Blender 会话运行，验证使用独立后台 Blender 重开。`prepare.py` 会备份有文件路径的当前会话；构建仅用于本任务的新套件，不得对已有手改场景全量运行。

`build.py` 的注释已修正为任务所属场景重建说明；早期执行清空了未保存的默认 Cube/Light/Camera 场景，没有保存原默认场景备份，不能宣称它仍被完整保留。早期 `refine_hand.py`、`fix_preview.py`、诊断/UV探针不属于最终重建链路，不应单独反复执行。

`register_sources.py` 仅在 QA `passed=true` 且母版哈希一致时登记；经 `assets/registry/ledger_index.json` 的 `domains.scenes` 路由写入30组件与1装配，AssetID前缀 `SEA-SCENE-LHL-`。源索引从各分账本派生，不重新计算无关资产哈希。

## 目视结论与待打磨

- 巨手具备五指握持识别，但手指解剖轮廓和掌心连接仍偏符号化。
- 雨棚已消除垂边低于甲板的错误，实际净高约2.26米；环绕雨棚、后段衔接及与招牌的空间关系仍可深化。
- 服务窗与部分窗面主要用叠置几何表达，不等同于真实墙壳开洞。
- 铜锈、红褐腐蚀为公共色格及附着几何的简化表现，未达到参考手绘材质的复杂层次。
- 灯室框架与透镜已制作，但当前视角下透镜可见性仍可加强。

以上为后续美术修订项，不影响本轮“可维护 Blender 原始文件”的源级交付定义，但也不被隐藏为已完成。

## 明确未执行

- 未导出或接入 Godot GLB / PackedScene / 正式 TSCN；未替换阳光房或任何正式场景。
- 未制作或验证游戏碰撞、导航、行走、泊位、运行性能。
- 未核验参考图商业使用权。
- 未取得用户最终美术验收。
- 后台 Blender 输出中 Rokoko 缺少 `boto3`、LZ4提示及 Tripo3D 60600端口占用属于环境插件噪声，未修改插件；最终以本资产脚本的 `--python-exit-code 1` 结果为准。

## 登记与工程门禁

功能条款与账本：SEA-ASSET-R33；打开说明：`art_source/scenes/README.md`。开发记录即本文件。

- `register_sources.py` 最终退出码0：经 `assets/registry/ledger_index.json` 的 `domains.scenes` 路由，在 `assets/registry/ledgers/scenes.json` 登记30个组件和 `SEA-SCENE-LHL-ASSEMBLY` 装配，共31条 `SEA-SCENE-LHL-*` 主记录；生成装配级 `asset_manifest.json`。
- `current_source_index.json` 从各分账本派生。登记工具逐项断言其他既有源索引记录不变，没有批量刷新无关资产哈希。保留本任务开始前工作区已有的 `SEA-KIT-*` 账本及其他任务改动。
- 最终会话探针确认雨棚组件局部最低点 Z=0、装配世界最低点 Z=3.50米。Blender 重存曾改变容器字节哈希，已重新运行完整 `verify.py`，30个独立包重开与四视图再次通过；账本使用当前重验文件的哈希，不以旧报告登记新文件。
- 登记脚本已统一使用正斜杠相对路径，并对重复执行按规范化路径判断同一 AssetID；本任务没有新增重复主记录。
- 实际执行 `scripts/check_feature_contracts.py --sync` 与不带参数的检查，二者均退出码1：`35 features, 513 source assets, 457 runtime resource hashes; 55 issues`。
- 55项均为本套件之外的 `SEA-KIT-*` / `godot/assets/models/building_kit/` / `godot/src/building/` / `godot/assets/materials/building_kit/` 既有哈希漂移：22个建造套件 Blender 源、22个对应 GLB、7个建造脚本及4个材质资源。没有本套 `SEA-SCENE-LHL-*` 的缺失、重复 AssetID、源哈希或索引错误，功能条款承接和摘要同步也未报错。
- 按任务边界保留这些其他工作的原哈希基线，不修改或接受未知漂移；因此不能宣称全工程门禁通过。源级灯塔检查通过、账本登记完成与全工程其他工作漂移是三件分别记录的事实。
