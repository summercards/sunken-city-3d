# 2026-11-20 · 旅人发型按发束走向重塑

承接 [SEA-AVATAR-R30](../features/avatar/spec.md#2026-11-20-按发束走向重塑) 和 [SEA-ASSET-R80](../features/asset/spec.md#2026-11-20-发束走向资产换版)。v003 用连续网格去掉拼接边界，顶面和后发仍偏平，难以看出从哪里分发和往哪里梳。本次按发根、弧线、宽度和末端定义发束，曲面浮起、沟槽和顶点明暗采用同一发束坐标。

- 侧分和斜刘海有分缝与长短两侧。波波头沿耳侧向下，底缘向里收。微卷增加后发弧线和发尾高低差，长发沿后脑下落成数股。
- 高低马尾和辫子由多方向收进各自扎点，主体沿尾巴弯曲。辫子用交错的三股起伏，丸子头在发髻表面保留盘绕方向。
- 保留原 14 款 ID、头部挂点、染色、发饰、刘海及三项滑杆。主体一张网格、一个材质面。为表现发束截面，主体面数由 v003 的 1400–2064 提到 2772–3556。原版和 v003 均留有源与验证证据。

[同机位发束对比](../../../sea-work/avatar-hair-v004/flow-comparison.jpg) · [前 7 款三视图](../../../sea-work/avatar-hair-v004/styles-01-07.jpg) · [后 7 款三视图](../../../sea-work/avatar-hair-v004/styles-08-14.jpg)

## 验证

通过 `scripts/run_verification.py` 使用隔离项目及用户目录。Godot 4.7.2 的真实画面使用 macOS Metal Forward+。已目检最终侧分、长发、高马尾及辫子的斜前和斜后近景、侧分梳向两端，以及短发、波波头和长发一组的正侧背画面。旧源对照只替换隔离项目发型程序，使用相同机位、灯光和角色配置。

| 验证 | 结果 | 证据 |
|---|---|---|
| avatar-customization、avatar-graphic、avatar、avatar-restart、npc-appearance | 分别 3635、389、192、8、2469 项，均 0 失败，退出码均为 0 | [逻辑与动作报告](../../../sea-work/verification/20261120-203342-hair-flow-check-50a9a4/report.json) |
| visual-avatar-customization | 391 项，0 失败，退出码 0。新增 5 款斜前斜后近景，以及侧分梳向两端。保留 14 款三视图和真实捏人输入 | [v004 渲染报告](../../../sea-work/verification/20261120-203342-hair-flow-render-51a2ef/report.json) |
| visual-avatar-customization 旧源对照 | 391 项，0 失败，退出码 0 | [v003 渲染报告](../../../sea-work/verification/20261120-203342-hair-flow-before-a99891/report.json) |
| visual-minimal-main | 42 项，0 失败，退出码 0 | [默认 F5 报告](../../../sea-work/verification/20261120-203439-hair-flow-f5-08f5fa/report.json) |

预期故障和意外错误均为空。完整主场景保留既有导航半径取整与采集点吸附警告。发行包、其他设备及全部发色和配件组合未执行。

全量契约同步和检查均退出 1，分别报告 586 项和 587 项，与 v003 复验相同。既有资产记录、历史证据链接和其他哈希偏差仍阻止派生索引同步。本次发型及其文件哈希未出现在报错中。[同步日志](../../../sea-work/avatar-hair-v004/contracts-sync.log) · [检查日志](../../../sea-work/avatar-hair-v004/contracts-check.log)
