# 2026-11-20 · 旅人发型重制

承接 [SEA-AVATAR-R29](../features/avatar/spec.md#2026-11-20-旅人发型重制) 与 [SEA-ASSET-R79](../features/asset/spec.md#2026-11-20-角色头发资产换版)。14 款发型沿用原选项，玩家捏人、默认海面场景与居民共用角色表现。

头顶、刘海、耳侧及后发连续取样，发际线边缘向内收。丸子头、马尾和辫子从头后部的同一张网格延展，共用一圈根部顶点。长发作为整片后发下垂，发尾向后让开衣身和潜水气瓶。侧分、精灵碎发、铲青和自然卷各有独立额角与头顶轮廓，圆弧与浅发束纹理使用现有染色端口。发带顺扎发方向，蝴蝶结贴合发面，均仍为独立选项。戴帽的紧凑轮廓由原帽子选项驱动。

沿用 `AvatarHead/Hair`，头发局部使用参考米制，+Y 向上、+Z 朝前，继承原头部缩放和姿态。头部皮肤、帽子节点和功能碰撞使用原有资源。发型、染色、刘海、发饰及发长、蓬松度、梳向字段可直接读取旧档。造型作者源和正式运行源均为 [avatar_hair.gd](../../godot/src/avatar/avatar_hair.gd)，版本 v003，登记在 [SEA-CHAR-HAIR-001](../../assets/registry/manifests/sea-char-hair-001.json)。旧版由 Git 及同机位复验用源副本保留。

## 实测

头发主体各 1 个 MeshInstance3D、1 个材质面和 1400–2064 个三角面，发饰另计。按旧代码的网格索引数计算，默认波波头从 15 个网格、5736 三角面变为 1 个网格、1400 三角面。28 组款式及发量极值检查逐三角面验证顶点连通、单一发际边界、无退化三角面和面数上限。现有动作专项继续检测眼睛、头、衣身和潜水气瓶等包络。

Godot 4.7.2，使用 `scripts/run_verification.py` 和隔离项目及用户目录。真实渲染为 macOS Metal Forward+。

| 验证 | 结果 | 证据 |
|---|---|---|
| avatar-customization | 3635 项，0 失败，退出码 0 | [角色回归报告](../../../sea-work/verification/20261120-201301-avatar-hair-final-ab9302/report.json) |
| avatar-graphic、avatar、avatar-restart、npc-appearance | 分别 389、192、8、2469 项，均 0 失败，退出码均 0 | 同上 |
| visual-avatar-customization | 368 项，0 失败，退出码 0。25 张原生截图覆盖发型三视图、三款帽子、动作、潜水和三个桌面尺寸的真实捏人操作 | [渲染报告](../../../sea-work/verification/20261120-201301-avatar-hair-final-render-0b8de4/report.json) |
| visual-avatar-customization 旧源对照 | 368 项，0 失败，退出码 0。只替换隔离项目的发型源码，使用相同的镜头、参数和灯光 | [旧版报告](../../../sea-work/verification/20261120-201301-avatar-hair-final-before-b8c1e1/report.json) |
| visual-minimal-main | 42 项，0 失败，退出码 0。3 张原生画面，覆盖默认 F5 入口的旅人装配与坡道移动 | [F5 报告](../../../sea-work/verification/20261120-201650-avatar-hair-f5-a677fe/report.json) |

最终报告中预期故障和意外错误均为空。完整主场景用例记录既有导航半径取整和采集点吸附警告。已目检代表发型的最终同机位对比、长发内侧和三款帽子，较早预览检查过全部 14 款。未穷举每种发型与颜色、帽子及其他配件的组合，未执行发行包、手柄、触屏或其他设备验证。客户端存档由原有功能回归覆盖，未读写实际玩家存档。

仓库全量契约同步和检查均退出 1，分别报告 586 项和 587 项。现有历史证据链接、其他资产哈希、内容索引等问题阻止派生索引同步。发型条款和当前资产哈希已逐条核对，全量报告中没有本次发型条目报错。[同步日志](../../../sea-work/avatar-hair-v003/contracts-sync.log) · [检查日志](../../../sea-work/avatar-hair-v003/contracts-check.log)

[波波头、长发与高马尾对比](../../../sea-work/avatar-hair-v003/before-after.jpg) · [发型三视图上册](../../../sea-work/avatar-hair-v003/styles-01-07.jpg) · [发型三视图下册](../../../sea-work/avatar-hair-v003/styles-08-14.jpg)
