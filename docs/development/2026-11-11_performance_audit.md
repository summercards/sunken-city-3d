# 2026-11-11 当前游戏性能审计与无损优化方案

所属：SEA-QUALITY-R01/R02/R03/R04/R05。用户要求深入审计正式游戏实际消耗、找无表现成本，并交付完整优化文档；本轮不实施正式性能改造。工作树原有大量用户/并发修改，未恢复或覆盖，不改手摆transform、玩法、存档结构或正式材质。

## 当前证据

设备：i7-14700KF/RTX4060Ti，Godot4.7.2，Vulkan Forward+。runner在Autoload前隔离用户数据，自动保存关闭；不访问真实玩家槽位。HEAD c966bd9c2a3bf0220be874236d63998b67818647仅用于定位，实际输入以每轮report工作树快照为准。

- `20261111-001328-perf-audit-baseline-20261111-1a102a`：visual-frame-functions、visual-frame-diagnosis均PASS/exit0。Main直接调用中位0.327ms，NPC未变快路0.007ms/首1.746ms，指针0.157ms。正常VSync下泛光开/关/恢复57.51/52.82/51.43FPS、p95约31–32ms；GPU约6.2–6.5ms，不能归罪泛光。
- `20261111-001906-perf-audit-ab-fixed-4e418d`：首次1280×800海面/室内/水下消融PASS/exit0。
- `20261111-002841-perf-audit-confirm-1600-da8a60`：1600×1000确认PASS/exit0，unexpected_errors空。关闭VSync、固定模拟步长60，真实单调时钟测帧。海面p50约9.77–9.89ms、GPU7.28–7.32ms、绘制2410–2450。水面隐藏GPU5.882ms、太阳阴影关闭4.692ms、SunkenCity隐藏6.210ms；这些会改变效果，仅定位，不算无损收益，也不相加。
- 同轮室内A/B/A：5.357→3.940→5.349ms；绘制259/图元65691、GPU约1.627ms不变。B是诊断性粗粒度停室外回调，正式实现必须采用纯表现白名单，不能冻结时钟/经营/NPC业务/存档。1280轮也同向。
- 工坊反证：实际SubViewport模式关闭0→打开4→关闭0；隐藏预览没有持续渲染。不能按preview.gd单行UPDATE_ALWAYS宣称后台GPU浪费。
- 家园海底20/41/80m指定朝向GPU2.808/2.902/2.559ms；80m探针落在楼内，不代表合法游动或最差视角。20m光柱消融差约0.053ms，非当前首要热点。
- Main load13.29s、instantiate92ms、ready8.27s；岸线1536²图各轮约1.34–1.39s。潜水同步诊断准备6.35s不等于生产完整过场时长。
- 引擎静态分配海面317.26MiB→潜水1700.78MiB→返回547.86MiB；渲染资源计数748.46→988.32→846.21MiB。非进程RSS/硬件总显存；打开过工坊，单次往返残留不足以判泄漏。Main同一实例脱树保留并返回。
- `20261111-003212-perf-audit-micro-fixed-7dbd60`：有效30次微基准PASS/exit0。指针p50/p950.154/0.264ms，当前小布局容量预检0.418/0.455ms，快照encode不写盘0.163/0.178ms；大布局、完整保存I/O和连续操作未签。
- `20261111-003106-perf-audit-micro-regression-25bfb7`：building-perf239/0、npc-performance61/0均PASS/exit0。小fixture不代替正式Main整帧。

证据根：`D:/projects/sea-work/verification/`。静态可复算清单与完整报告产物：`D:/projects/sea-work/outputs/performance-audit-20261111/`。报告正文包含OPT-01至OPT-27、三批实施、正确性保护、收益公式、保真矩阵和回退。

## 当前改动

- 新增 `godot/tools/profile_performance_audit.gd`：隔离诊断，不应用生产优化；输出原始帧/GPU数组、相机、节点、内存、实景PNG与可逆消融。环境变量 `SEA_PERF_MICRO_ONLY=1`仅跑直接调用。
- `scripts/run_verification.py`：仅新增`visual-performance-audit`注册，保留既有用户修改。
- SEA-QUALITY账本末尾追加本轮记录，状态保持partial；主文档摘要按统一脚本同步。

## 失败、警告与测量限制

- 首探针 `20261111-001813-perf-audit-ab-20261111-a03539` beams类型推断错误exit1，修正后通过。
- 首微探针误用不存在building_service字段，脚本exit0但runner判FAIL。失败样本capacity耗时无效，修为building后有效0.418ms；失败日志保留，不当作游戏缺陷。
- Performance.TIME_PROCESS/TIME_PHYSICS_PROCESS在fixed-fps协程探针下滞后且与实际帧间隔矛盾，原始值标untrusted，不参与CPU预算归因。
- UID路径回退、NavMesh体素取整与采集点吸附WARNING保留，未批量重导入/更新hash。
- 真实渲染实际产出且目检：海面、室内、20/41/80m及城市隐藏诊断；80m楼内视角限制已登记。冻结预览A/B仍受shader TIME轻微动画影响，不声称逐像素完全一致。
- 未执行：真实玩家档、release/Web新包、低端/集显、功耗/硬件显存、全部机位、主动航行/施工大布局、长时自动存档、10次内存往返。未实施任何正式优化，不签全项目性能完成。

## 最终工程门禁

已执行`check_feature_contracts.py --sync`后无参数检查：同步exit1/75项，无参数exit1/77项。包括SEA-ASSET条款承接不一致、多项既有源与运行资源hash漂移，以及并发SEA-WORKSHOP状态/派生索引变化；未批量更新hash或代改其他功能。当前全局契约不能签通过。`check_placed_positions.py` exit0，6处/0警告；`check_architecture.py` exit0，25独立服务/0问题。审计交付不等于这些既有/并发问题已解决。

## 文档交付

完整Word已生成：`D:/projects/sea-work/outputs/performance-audit-20261111/output/perf-audit/stage3/sea_性能审计与无损优化方案.docx`。11章、27项优化，含当前数据、截图、证据、三批路线、保真矩阵与回退。排版检查96分/通过；转换预检与成品校验通过，471个文本检查项无缺失、56个目录跳转目标全部绑定。原始日志/JSON/静态解析脚本与新探针打包在外部输出目录`sea_性能审计_原始证据.zip`。新建文档转换提示未接入会话备份，不涉及覆盖既有用户文档。

## 下一步

先OPT-01室内纯表现生命周期，再交互缓存/UI与建造dirty，随后岸线/碰撞预烘焙和分批初始化。静态重复构件批次与阴影投射集合在真实A/B后接入；LOD/遮挡/着色器近似要单独画质签署。不能删效果或削弱存档安全换帧率。
