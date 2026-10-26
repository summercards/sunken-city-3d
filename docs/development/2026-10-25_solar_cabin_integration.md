# 太阳能木屋 · 阳光繁花小屋正式接入

用户要求先复制备份当前文件为 0.1，再以 sunny_bloom_retreat.blend 的房屋替换太阳能木屋海上部分，核对尺寸范围与朝向。

## 备份与打开入口

- 0.1 备份：`/Users/summercards/WorkBuddy/sea-work/backups/solar_cabin_replacement/v0.1`，原目录保持以保护 Blender 相对链接；backup_manifest.json 逐文件登记并验证。
- 当前 Blender 装配：[solar_cabin_v1.0.blend](../../art_source/scenes/sunny_bloom_retreat/v003/export/v001/placement/solar_cabin/solar_cabin_v1.0.blend)。
- 原始制作源：[sunny_bloom_retreat.blend](../../art_source/scenes/sunny_bloom_retreat/v003/sunny_bloom_retreat.blend)，SHA-256 不变。
- 独立优化源：[solar_cabin_optimized_v001.blend](../../art_source/scenes/sunny_bloom_retreat/v003/export/v001/solar_cabin_optimized_v001.blend)；[导出清单](../../art_source/scenes/sunny_bloom_retreat/v003/export/v001/export_manifest.json)。
- Godot 完整包装：[solar_cabin.tscn](../../godot/scenes/facilities/solar_cabin.tscn)，当前区块手工引用；内部海上和海下部分可分别选择。

## 大小、范围和方向

整体源统一放大 1.15 倍，不改变房体横纵比例；49 个母版和实例的原始相对摆位保留。地板 Y=2.15 米，主墙宽 5.75 米。含植物与双列栈桥的运行包围盒为 X≈10.5904、Z≈13.8165、Y≈8.0022 米，下界约 (-0.0227,1.12,-3.0097)，顶高约 9.1222 米。源前方 -Y 映射为 Godot +Z，yaw=0°。旧海下基座保留；新石平台底部在派生实例中延长 0.248 米以接到 Y=1.12 水面，房屋本体保持统一比例。

## 导出与装配

49 组件各有稳定 GLB 与 PackedScene，整体用组件实例批次绘制；建筑、陈设、花草按元数据管理，不导出一个合并整屋 GLB。四材质绑定公共色板运行副本，PNG 与制作色板 SHA 相同、Nearest、无 mipmap、无损。49 新 GLB 不内嵌贴图；历史基座/打捞台沿用旧顶点色及历史贴图材质。优化副本清理重复/退化几何、删除独立点并溶解低于 0.003 弧度的共面冗余，颜色/材质边界锁定；完整实例展开 703920→688342 三角面，约 2.21% 减少。正、背、侧、顶固定相机保真对照已目视核对。

仅定点编辑 zone1_home_harbor.tscn；旧四模型显式隐藏，未运行旧全量构建器。原海上散落植物退役，保留海下及打捞台植物。同步新平台可走区域、泊位、六格菜箱、建造牌和采集点；海下基座和打捞台为独立包装。角色/经济/经营规则未改。

## 当前实测

- 真实 Metal/Forward+ 渲染：529 条几何、色板、方向、实例、基座和登岸检查通过；正面、背面、俯视和上下文截图。
- surface：30 条航路、338 检查通过；selftest：537 通过，0 失败（含一条预期损坏 JSON 负向错误）。
- click 与 management 专项通过；完整退出码、隔离数据目录、预期/非预期错误见结构化验证 JSON。
- 首次 headless 模型探针读到 dummy renderer 的恒等实例矩阵，改为真实渲染验证；未以 headless 结果签署几何通过。首次发现两格菜箱超出可走边界，已内移并重新验证。采集中断自检的前次拒绝冷却经公开 update 消耗，原断言保留。
- 未执行长期性能基准；不以本次接入证明参考图商业授权，授权字段保持原状态。

所有运行验证经 scripts/run_verification.py，在 Autoload 前隔离用户数据；未读取或覆盖玩家存档。

49 个组件 PackedScene 独立加入场景树验证：259 检查、0 失败；独立包装绑定公共色板正确。49 新 GLB 导入契约均为 embedded_image_handling=0；色板无损且不生成 mipmap。原源/优化源哈希与逐组件 GLB 哈希核对通过。

最终工程契约同步和检查均退出 0：31 功能、365 源资产、281 运行资源哈希，0 问题。最终真实游戏前/后/顶/全景已复核，源固定相机四视图与优化后对照一致。
