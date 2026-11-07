# 2026-11-07 主场景帧率排查

用户报告运行时卡顿。所有实测通过隔离 runner，独立存档，当前 RTX 4060 Ti、Forward+、1600×1000，测试时编辑器与其他程序仍运行；统计为隔离场景，不等同于玩家当前存档的实时帧率。runner 使用固定模拟步长，帧时由真实时钟测量。

- `visual-frame-diagnosis` exit 0：泛光开 5.73 FPS、关 5.96 FPS、再开 5.80 FPS；开启时 GPU 中位 6.61 ms、帧时中位 168.10 ms；绘制调用约 3654–3955。
- `visual-frame-process` exit 0：正常 5.88 FPS，暂停场景处理 56.31 FPS，再恢复 5.90 FPS。暂停处理同时会改变画面及绘制量，不能把差额全部归于脚本。
- `visual-frame-subsystems` exit 0：正常 5.93 FPS，关闭物理处理 6.02 FPS，关闭普通处理 56.97 FPS，仅关闭主场景普通处理 52.40 FPS。
- `visual-frame-functions` exit 0：独立调用中位：`sleep_cycle.advance` 75.11 ms、`world_clock.tick` 75.85 ms、`npc_world_presenter.sync_world` 77.62 ms、主场景 `_process` 153.23 ms。时间信号每次触发居民同步；`sleep_cycle.advance` 自身调用一次 `clock.tick`，主场景又调用一次，合计两次。采样为五次顺序调用，具体耗时会受系统负载和场景状态影响。
- 首次函数探针访问不存在的 environment.update_time，退出码 0 但包含脚本错误，runner 正确判失败；修正后复测通过。

证据：`D:/projects/sea-work/verification/20261107-194800-frame_diagnosis-3d4206`、`20261107-195102-frame_process-f9fdb5`、`20261107-195222-frame_subsystems-99c36f`、`20261107-195618-frame_npc-734689`。未测其他位置、玩家存档实时帧率、发行包及低端设备；本轮未改玩法或性能实现。

## 2026-11-07 修复后追加结果（原诊断保留）

以下为后续修复结果，不改写上方旧诊断。Main删除第二次clock.tick，仅sleep_cycle.advance内部至多tick一次并cap23:00睡点，06:00醒/07:00晨次保持；clock.changed经Main._on_npc_clock_changed→notify_world仅小字典，Presenter0.5s按日/分钟、任意日程from/to、conditions hour及21:30边界/天气/关系剧情/Marker/root/support变化检测，每batch单snapshot，support cache带active/surface/revision失效，idle免逐physics投影，force恢复保留。

[修复后报告](../../../sea-work/verification/20261107-211435-npc-fps-after-fix-6e7a56/report.json)的visual-frame-functions与visual-frame-diagnosis均exit0/PASS、unexpected_errors空。RTX4060Ti、Vulkan Forward+、实际viewport1600×1000（启动命令1280×800），固定模拟步长60：泛光开59.943FPS、帧p50 16.681ms/p95 18.097ms，关59.956FPS，再开59.956FPS。泛光最终保留，无降质、无删NPC。

函数五次顺序调用median：Main._process **0.752ms（旧153.23）**；重复npc_sync **0.008ms（旧77.62）**，样本0.007/0.007/0.008/0.019/2.458，包含首轮2.458ms，**不是每次全量sync仅0.008ms**；sleep0.017ms、clock0.012ms。旧~5.7FPS场景仍带住所，新场景已撤，draw3186对旧3654–3955，不能将全部约10倍提升归为纯算法；函数探针直接支持同步阻塞已消除，场景变化独立记录。

[小fixture](../../../sea-work/verification/20261107-204747-npc-performance-final-8687e2/report.json)61/0，120次notify+sync共558μs，不是正式Main每120帧性能；[真实Main时钟回归](../../../sea-work/verification/20261107-212152-npc-clock-once-cc6ca7/report.json)npc-clock301/0、sleep42/0，均exit0。当前合批NPC性能/rules/world/appearance/careers/flowers/sleep PASS，但shop-rules218/7、exit1尚在修；天台integration/save/restart/14截图待主线程，不在此预签。完整证据、稳定SEA-TIME-R12/SEA-RESIDENT-R14及归因/设备边界见[性能修复记录](2026-11-07_npc_performance_fix.md)。

## 最终运行签署追加（保留上方诊断与失败历史）

上节“shop218/7尚在修、天台待验”为当时阶段事实，现已收齐独立新证据：[213213最终shop输入](../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)259/0、exit0，解决原七项UI失败；[214439当前天台交付](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)integration668/0、save618/0、seed408/0、restart202/0、visual381/0，共2277/0，五项PASS/exit0、unexpected_errors空。14PNG已产出，仅主线程实际目检seven-residents、flower-purchase、story-choice三图，其余11图待人工审阅，不称14全目检。

保留上方59.943FPS、Main0.752ms、重复sync0.008ms含首2.458ms和全部归因边界，不将新自动化通过推为持续性能、全设备或发行包通过。NPC/Shop当前运行实现可登记implemented而非verified；住房仍partial/deferred，未恢复未签完成。本轮仅追加文档签署，不重新执行global check。
