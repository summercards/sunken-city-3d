# 2026-11-05 · 植物、草地与青苔视效评估及制作设计

[主文档中控](../../GDD_V1.0.md#sea-ambient) · [功能规格](../features/ambient/spec.md) · [功能账本](../features/ambient/ledger.md)

## 用户范围与交付

用户要求先参考本地视频，兼顾风格、视效和性能评估植物/植被/草地优化，提供柔软、能感受到风的草地和青苔，评估 HungryProton/scatter，并把可复用系统的制作方案、文档和账本落下。用户补充确认：**桌面 PC 优先**。

本轮完成设计与静态调查，未进入运行实现。采用既有 SEA-AMBIENT 功能，新增稳定条款 R06–R16；资产生产协议归 SEA-ASSET-R49。未增加重复的植物生命周期功能。

交付文件：

- [评估与实施方案](../features/ambient/vegetation_visual_plan.md)：视频拆解、当前工程事实、方法取舍、共享架构、Scatter 源码审查、性能分级、迁移顺序与验收。
- [统一制作规范](../standards/植被视效制作规范.md)：几何/色板/UV/风权重/实例通道、共享目录、布局清单、资产登记与逐件操作流程。
- [SEA-AMBIENT 规格](../features/ambient/spec.md)和[账本](../features/ambient/ledger.md)、[SEA-ASSET 规格](../features/asset/spec.md)和[账本](../features/asset/ledger.md)：逐条承接，新增能力均为设计/计划状态。
- 主文档末尾追加入口、平台优先级与跨功能关系。未修改各账本登记头或覆盖历史章节。

## 决策

主方案为共享 GPU 风场、有权重的圆润叶簇/分段草簇、固定苔垫加少量短绒、按设施/楼层分块的 MultiMesh 与按投影大小分级。首轮不采用全场毛发壳层、逐草物理/骨骼或另建间接绘制管线。

ProtonScatter 可作为编辑器布置工具，固定版本并转换为中立布局；其缓存不等于已脱离插件的正式烘焙。插件代码未安装进项目、未运行；兼容与美术/性能收益需在后续隔离样板中验证。

后续制作优先完成宽叶、草苔与水边植物小样，再接入渔场和阳光房示范；之后迁移农场、街区与半沉林带。保留公共色板、稳定包装、原玩法状态和手工场景。

## 证据与来源

工程外证据根：`D:/projects/sea-work/vegetation_plan_20261105/`。本轮未设置 SEA_WORK_ROOT，因此使用相邻 sea-work。

| 证据 | 本轮事实 |
|---|---|
| 用户视频 | `C:/Users/zhuangmenghong/Desktop/cdcdae86e4001b75d34fb4f58373ef7f.mp4`，14.666667 s、720×1080、30 FPS、4,099,984 bytes |
| 视频 SHA-256 | `b586549578ed79117367dc27e97b38c22c1a0e49546c614324369bbc946750e6` |
| `reference_contact.jpg` | 约每 2 秒抽帧接触表；供构图/外形比较，末格为空不计作画面 |
| `reference_04s.png` | 4 秒处原尺寸画面，用于草苔轮廓、叶片和花点分析 |
| `reference_motion_3-5s.jpg` | 3–5 秒水边植物区域每 0.25 秒序列；存在镜头变化，不据此声称量出了精确动态参数 |
| `static_asset_audit.json` | 读取 GLB JSON/accessors 的原始三角面、通道和局部包络；现有资产路由与旧植物表数量 |
| `proton_scatter/` | 仅只读源码克隆；HEAD `7198cc00078ebde61307578137c3f35223c6e438`，插件 4.2.0，仓库工程标注 Godot 4.7 / Forward Plus |
| `before_docs/` | 本轮追加前的五份现有文档快照与字节数/SHA-256，用于确认账本历史前缀完整 |

技术依据及对应链接就近写在方案中，优先 Godot 官方文档、插件固定提交源码与 GPU Gems 原作者文章。资料结论与项目静态观察、未来设计、尚未实测项明确区分。

原始网格事实：阳光房 foliage 5,280 面，农场 grass 325 面，moss_cluster 75 面，三者均只有 POSITION/NORMAL/TEXCOORD_0；moss 的 POSITION.z 全部为 0。此统计不包含实例数、运行缩放或屏幕负载，也不意味着三个旧资产都必须弃用。

## 验证状态

运行 shader、游戏截图/录屏、GPU/CPU 性能、Scatter 导出/无插件冷启动、Web/移动设备均**未执行**。本轮为文档交付，不拿历史运行记录签署新条款。

开工前执行 `python3 scripts/check_feature_contracts.py` 因 Windows 默认 GBK 解码 UTF-8 主文档而退出 1；改为进程级 `-X utf8` 后才进入检查，未修改检查器。

进入检查后的基线为 39 个功能、769 个源资产、704 个运行哈希，退出 1，共 6 项：水上建筑派生视图过期、`SEA-SCENE-ORF-ASSEMBLY` 源哈希漂移、`ocean_sky.tres`/`poster_atlas.png.import`/`zone1_home_harbor.tscn` 运行哈希漂移，以及既有 feature_index 过期。本轮不重算这些未知哈希以消除失败。

最终检查如下，完整日志/机器结果在上述工程外证据根：

| 检查 | 退出码 / 结果 | 证据与解释 |
|---|---|---|
| 本轮文档专项静态审计 | 0 / PASS | `documentation_audit.json`；8 份文档本地链接存在，ambient/asset 设计与账本条款集合一致，新 R06–R16/R49 各出现一次，状态仍为 partial；5 份已有文档均完整保留本轮追加前快照的字节前缀 |
| `git diff --check`（本轮已有文档路径） | 0 | 只有工作区 LF/CRLF 提示，没有 whitespace error |
| `python3 -X utf8 scripts/check_feature_contracts.py --sync` | 1 / 4 issues | `feature_sync_final.log`；仍为上述 4 个未知资产源/运行哈希漂移，工具因此未写回全局派生索引 |
| `python3 -X utf8 scripts/check_feature_contracts.py` | 1 / 5 issues | `feature_check_final.log`；同 4 个哈希漂移，加既有派生 feature_index 过期 |

最终全局统计为 39 功能、797 源资产、704 运行哈希；过程中其他工作更新了资产与围挡文件，不能将数量变化记为本轮植被产出。首次文档完成后的检查还发现 SEA-ASSET-R48 规格仍在、账本行缺失；该行在本会话较早读取时存在，故仅按先前读到的原文追加恢复其历史章节，保留当前 R47/R49，不重写账本。恢复后该结构错误消失。

本轮未执行预期故障注入；全局检查中的失败均为如实记录的问题，不归类成“预期故障通过”。没有因本次评估改写源资产、正式场景、着色器、用户数据或未知哈希，也没有用历史帧率替代当前实测。
