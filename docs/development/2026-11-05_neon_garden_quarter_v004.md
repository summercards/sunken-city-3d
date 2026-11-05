# 2026-11-05 霓虹花园街区五组件拆分

对应 SEA-ASSET-R48 和 SEA-WORLD-R19。图中四个红框为三栋楼和菜园桥，另按要求将街道地面分出。五个模块在 Blender 可独立打开，在 Godot 可独立实例化。

| 组件 | AssetID | 子实例数 | PackedScene |
|---|---|---:|---|
| 左楼 | `SEA-SCENE-NGQ-LEFT-BUILDING` | 198 | `left_building.tscn` |
| 后楼 | `SEA-SCENE-NGQ-REAR-BUILDING` | 92 | `rear_building.tscn` |
| 右楼 | `SEA-SCENE-NGQ-RIGHT-BUILDING` | 59 | `right_building.tscn` |
| 双坡菜园桥 | `SEA-SCENE-NGQ-GARDEN-BRIDGE` | 118 | `garden_bridge.tscn` |
| 街道地面 | `SEA-SCENE-NGQ-STREET-GROUND` | 39 | `street_ground.tscn` |

三栋楼各含屋顶、门窗、挂在楼上的设施与招牌。桥包含双坡屋顶、菜床、作物与桥头附属件。街道包含铺地、路灯、碎石、落地灯笼和共用跨街线缆。独立包以几何底心为原点，内部仍能单独编辑各下层件。源包和模块清单在 `art_source/scenes/neon_garden_quarter/v004/`。Godot 模块在 `godot/scenes/components/facilities/neon_garden_quarter/modules/`。

本轮是既有几何的分组导入。逐件核对了 v003 的 50 个制作源、50 个独立优化源、50 个 GLB、导入配置和原 PackedScene 哈希。运行模块直接引用这些资产。506 个 Blender 变换经重开重放，506 个 Godot 子件的平移经局部偏移精确重建，旋转缩放原值保留。五个模块是正式总成 `neon_garden_quarter.tscn` 的直接视觉实例。

主场景的 XZ 仍是太阳房正东 150 米。工作期间现有主场景标高改为 Y=-21.726082，本轮保留该编辑。街口活动面与泊位仍由总成维护，阻挡目标为 `Visual/Foundation/GroundMesh`。当前实景验收覆盖五件装配、海报和色板、航线、下沉街道零水面阻挡与三张游戏实拍。原街口阻挡、泊位、角色上岸与步行在 Y=1.12 的隔离工况另测，当前主场景街道上岸因下沉未通过。报告为 `D:/projects/sea-work/verification/20261105-105104-ngq-v004-final-d6c9b3/report.json`，制作和实拍证据在 `D:/projects/sea-work/neon_garden_quarter/v004`。

隔离验收通过 359 项逻辑、366 项真实渲染、794 项水层及 141 项最小流程检查。Blender 拆分前后同机位全景与俯视渲染的最大通道 RMS 为 0.082 / 255。资产账本新增五件并更新原总成。功能契约 `--sync` 与无参检查均执行，已有 ORF 源、天空材质、海报导入设置及家园场景四处哈希差异阻断全局索引同步，无参检查另报告派生索引过期。保留这些已有差异，证据见 `contracts_sync.log` 和 `contracts_check.log`。
