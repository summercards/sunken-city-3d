# 2026-11-02 八层海上屋顶农场 Blender 源

关联条款：SEA-ASSET-R41。按用户参考图及后续修订，在 Blender 中制作独立水上功能建筑候选。本轮交付制作源、组件包、预览和账本，不自动接入正式游戏场景。

## 范围与最终内容

- 套件：`art_source/scenes/ocean_rooftop_farm/v001/`；母版 `ocean_rooftop_farm.blend`，场景 `海上屋顶农场_制作与装配_v001`。
- 八层可见楼体，3.2 米层高，主屋顶 36×24 米；屋顶含前压顶的实测包络为 36.10×24.05 米，行走面 Z=25.60 米。
- 左后 8×7 米抬高平台底面与主屋顶相接，平台顶 Z=29.00 米；上层小间坐落 Z=29.00 米。水塔罐顶实测 Z=34.49 米，符合约 9 米名义总高。
- 保留红褐屋顶工具房、温室、风力装置、储物、步道、休息区、空田垄与空菜床。按用户最新要求删除全部农作物与太阳能板，不含人物、动物、海洋或远景建筑；普通草地和盆栽保留。
- 大块地砖有真实厚度、缺角、裂缝、磨损和局部裸露基层；房屋及立面有剥落、裂口、露筋、破窗、封窗木板、外露管道和锈蚀。采用饱满、圆润、简化的玩具感卡通几何。

## 组件、材质与尺寸验收

- 44 个唯一组件 Collection，302 个 Collection Instance；80 扇唯一正侧面窗、32 个阳台、8 块楼板。44 个独立 `.blend` 包和对应 `asset_manifest.json` 全部生成并重开。
- 公共色板 `art_source/shared/palettes/sea_cabin_timber_8x8_512.png` 保持外链；仅使用 `SEA_Matte`、`SEA_Metal`、`SEA_Gloss`、`SEA_Emission` 四角色，Closest 采样，每网格只有活动及渲染启用的 PaletteUV。
- `sea-work/ocean_rooftop_farm/v001/verification.json` 最终 `passed=true`、`errors=[]`，共 47320 项检查；6130 个母版面逐面 UV 检查，实例展开为 115208 多边形 / 233672 三角面。没有用户指定的低面数上限。
- 通用验证器 `tools/blender/ocean_rooftop_farm/validate_skill.py` 仅将格网检查适配到 sea 8×8 色板，其余材质、输出、外链图片、活动 UV、自发光与归属规则不变。44 个组件全部通过，见 `skill_prop_verification.json`。
- 五视图 `beauty.png`、`roof_detail.png`、`top.png`、`facade_detail.png`、`building_only.png` 均由最终保存源渲染并目视查看；平台、屋顶设施、水塔支架及温室连接正常，地砖与破损细节可辨。

## 修订及纠错记录

1. 初版三层屋顶农场完成后，按用户反馈改为八层、删除作物和太阳能板、加入旧地砖及建筑破损细节。
2. 修复公共色板路径丢失造成的紫红渲染；修复重复执行造成的屋顶设施二次抬升，使屋顶、平台、小间及水塔恢复连接。
3. 严格验收按含压顶屋顶包络、实际行走面及约 9 米水塔名义尺寸分别核对；修正 `facade_weathering` 微小原点偏差。
4. 失败重跑遗留 6 个重合实例：一份整屋地砖、一份立面破损及四扇破窗。已去重至 302 实例，并在验收中加入五位小数变换签名的重复检查，防止重合闪面。
5. 通用验证器发现发光灯泡名称不含明确灯光标识，将 `暖灯` 改为 `暖灯_UI灯光`，几何不变；重跑两级验收后通过。
6. 活跃 Blender 的 MCP 在反复 `read_factory_settings/open_mainfile` 后停止监听，但 Blender 进程仍在。后续清理、重开、验收与渲染改用独立后台 Blender，没有继续操作该会话。若需继续 MCP 操作，在 Blender 的 BlenderMCP 面板重新连接。

## 登记、边界与复现

- `register_sources.py` 仅在主源 QA 通过且哈希一致时执行。已将 44 个组件和 `SEA-SCENE-ORF-ASSEMBLY` 共 45 条记录经索引写入场景分账本，装配清单为 `v001/asset_manifest.json`。
- `tools/apply_water_layer.py` 新增 `SEA-SCENE-ORF-` surface/assembly 家族规则；装配为 `above_water` 实体，组件为其零件。同步后场景账本共 612 条，其中 above_water 367 条。
- 源索引由分账本派生；登记工具断言无关资产旧索引记录不变，没有刷新其他任务哈希。
- 打开说明：`art_source/scenes/ocean_rooftop_farm/README.md`；功能账本：`docs/features/asset/ledger.md`。
- 最终实际执行 `scripts/check_feature_contracts.py --sync` 及两次无参数复核，均退出码 0：`PASS: 39 features, 625 source assets, 515 runtime resource hashes; 0 issues`。日志位于工程外本套件 `feature_contracts_sync.log`、`feature_contracts_check.log`。
- 正式源验收顺序为 `verify.py → validate_skill.py → register_sources.py`，使用 `blender --background --python-exit-code 1 --python <script>`。历史生成/修订脚本不应在已手改母版上随意重跑。

明确未执行：Godot GLB/PackedScene/TSCN 接入、角色及船碰撞、导航、实际生产或交互玩法、运行性能、参考图商业授权和用户最终美术验收。本记录中的“通过”仅指 Blender 源级与通用材质/UV检查。

## 2026-11-04 v006：纠正整楼沉没，不移动消防梯

关联 SEA-WORLD-R17。用户再次明确：梯子保持原位置，整楼下沉，只露出靠屋顶的一小段，能从水边登顶。此条取代上一轮 v005「保留底部单段、屋顶不可达」的误读。

- 正式根节点 Y：`-43.68 → -55.92`，整楼下沉 `12.24m`；海面仍为世界 `1.12m`。
- 公式：`root_y = water_y + deck_clearance - original_top_landing_y = 1.12 + 0.26 - 57.30 = -55.92`。
- 最后梯段原位不动：下平台本地57.30/世界1.38，上平台59.80/世界3.88；草皮真实顶面60.05/世界4.13，高出水面3.01米。原低层梯全部保留，由水深自然遮没，不靠隐藏/下移梯段造假。
- 重新测量GLB踏面，发现旧通行数据的Z方向错误：最后梯段实际从z=-1.20向z=3.00上升，顶平台z=3.00..4.80，原屋顶入口z约3.00..4.80。恢复连续屋顶通行，并修正露台/棚屋/鸡舍占地区域反号；温室/水塔使用两态包络并集，升级逻辑未扩张。
- 场景元数据、main实例、zones查询、Landing/BoatPark同步更新。pier包装移除已不存在的旧缺损节点覆盖，保留当前实际柱损网格材质；不重导任何GLB。
- 新源：`art_source/scenes/ocean_rooftop_farm/v006/ocean_rooftop_farm_v006.blend`；独立重开审计14个梯/平台/入口矩阵与v004相同，全部网格/柱体UV与v005相同。只恢复原可见性、写追溯信息，没有移动源对象。
- 统一隔离验收：`20261104-172053-v006-sunken-top-7399b2` 中rooftop-ranch与ranch-deck-probe通过；专项验证真实踏面射线支撑、正式上岸→末段→屋顶→回平台胶囊实走。
- 真实渲染及回归：`20261104-172147-v006-visual-regression-bbe62c` 中visual-rooftop-ranch、minimum-loop、water-layer、click全部退出0。预览目视确认只露最上一段斜梯，下层梯为水下轮廓，原屋顶入口畅通。
- 交付：`D:/projects/sea-work/ocean_rooftop_farm/v006_delivery/`，含源副本、source_audit.json、下沉全景、梯口近景、屋顶正式行走截图。
- 最终复验：`20261104-172813-v006-final-51759d`，rooftop-ranch **61 checks, 0 failures**，仅剩通用导航agent_radius体素精度警告，没有旧pier节点消失覆盖警告。
- 工程契约已实际执行`--sync`及无参数检查，未通过：6项原始问题（ORF-ASSEMBLY源哈希、source index、zones.json/ocean_sky.tres/zone1运行哈希、zones content ID），无参数复核另报derived feature index stale，共7项。没有批量刷新哈希/ID清单掩盖差异，功能摘要同步仍受阻。
- 边界：本轮不改经营/存档格式，不复验全工程selftest，不代签资产注册及商业授权；上一轮的柱损保留，主体下沉后大部分自然位于水下。

## 2026-11-04 v006 装饰悬空修复

关联 SEA-WORLD-R17。用户红框指出屋顶外悬空藤蔓/苔藓，上一轮的路径检查未覆盖装饰空间，真实缺陷不得以“通行通过”豁免。

- 根因：150个带缩放的装饰实例把scale重复乘到origin，且Blender→Godot转换遗漏缩放轴交换。正确`p_g=(x,z,-y)`，`B_g=C·Rz·Ry·Rx·diag(s)·C^-1`。例如藤蔓`.015`错误局部Y=88.7584，正确55.8526；根下沉不能修这种相对位置错误。
- 定点修复24藤蔓、11苔藓、90草丛、25立面破损，共150行Transform；非目标650块逐块SHA256相同，45个GLB及全部源文件未变。没有隐藏装饰、没有改模型原点、没有重生成场景；水线、末段消防梯、碰撞与上岸点不变。
- 可重跑工具`tools/blender/ocean_rooftop_farm/fix_runtime_decoration_transforms.py`，先备份再应用，`--verify-only`独立逐向量旋转复核，重跑零改动；详情`D:/projects/sea-work/ocean_rooftop_farm/v006_attachment_fix/transform_audit.json`。
- 专项加入实际装饰mesh包络检查、草丛/苔藓根部高度、苔藓与女儿墙贴边偏移（不超过0.02m）、藤蔓立面带及实例数量；继续覆盖原上岸登顶往返。当前隔离`20261104-191026-ranch-attachment-fix-247e18`：**525 checks, 0 failures**；真实渲染专项退出0。
- 五个实拍视角输出到同一工程外目录；全景及女儿墙近景已查看，天空悬空绿色装饰消失，苔藓贴外沿、草丛回到屋顶。不能以这些视角宣称全部设施每个三角面都已无接触误差。
- 当前回归`20261104-191202-ranch-attachment-regression-900819`：minimum-loop、water-layer均退出0。再次`--verify-only`通过所有锁区与数学检查，场景字节与首次修复一致。
- 功能契约同步/无参数复核已执行，仍分别报7/8项：ORF-ASSEMBLY源哈希、源索引、zones/ocean_sky/reference_skiff/zone1运行哈希、zones内容ID，另有派生功能索引过期。未刷新无关资产登记；git diff --check无格式错误，仅LF转CRLF提示。
- 仍不改经营与存档规则，不重导Blender/GLB；本次是正式TSCN装配变换纠偏，不创建几何新版本。

## 2026-11-04 全量悬空自检：屋顶栏杆与抬高露台分层

用户再次指出截图中仍有悬空构件，要求“自己进行自检，其它地方也检查”。本轮不再只看红框，扫描牧场 `Models` 全部744个实例、45个GLB、744条源实例记录。

- 红框对象确认是 `ORF2_实例_rail` 栏杆组；截图中的两种高度不是同一组：主屋顶栏杆底部约61.0965，对应女儿墙顶61.1175；`rail.038`–`.043` 属于抬高露台，底部约65.5965，对应露台顶65.8525。之前把后者按主屋顶栏杆规则检查，是断言归属错误，不是用放宽阈值掩盖悬空。
- 全量审计未发现新的天空悬浮实例。既有150个装饰变换纠偏保持通过；全部744个实例源名集合一一对应、位置误差≤0.02m，主屋顶/女儿墙/抬高露台/立面附件分层包络均有归属。
- 另发现2个非装饰旋转基转换漂移：`ORF2_实例_coop`最大基差约0.009734，`ORF3_下挂断裂消防梯`最大基差约0.019945。按源Euler和`C·Rz·Ry·Rx·diag(s)·C^-1`只修正两行Transform；没有改GLB、源Blend、源实例JSON、水线、消防梯相对位置或导航。审计：`rotation_drift_audit.json`。
- 新增失败型断言：主屋顶栏杆检查女儿墙顶与主屋顶边缘；抬高露台栏杆检查露台实体与栏杆底部正面积重叠，允许栏杆合理外伸；栏杆按实际序列化数量43段检查，不能写死不存在的`.033`。
- 最终隔离报告：`20261104-231319-full-ranch-self-audit-final-6ee970`，`rooftop-ranch` **655 checks / 0 failures**；`visual-rooftop-ranch`、`minimum-loop`、`water-layer`均退出0。导航仅保留既有agent_radius体素精度警告，无脚本错误。
- 结论：截图红框构件已按正确高度层级核验；未通过隐藏栏杆或删除装饰解决。工程外完整审计：`D:/projects/sea-work/ocean_rooftop_farm/v006_attachment_fix/full_audit.json`、`full_self_audit_final.json`、`rotation_drift_audit.json`。
