# 2026-11-23 家园建造组件和落装动画

承接 [SEA-BUILDING-R35](../features/building/spec.md) 与 [SEA-ASSET-R83](../features/asset/spec.md)。范围为建造目录 22 项新建配方及 13 项旧档配方。以[改造前审计](2026-11-23_building_component_audit.md)为对照。

## 组件与播放

五米套件十件从原 Blender 母版的制作集合取件，保存并重开独立派生 Blend 后导出 v003。保留原尺寸、安装基准、PaletteUV 和材质角色。原母版 SHA-256 前后相同，十件使用原 AssetID 和原 Godot 预制体入口。[导出清单](../../godot/assets/models/building_kit/construction_v003/export_manifest.json)记录逐件路径、部件数及 SHA-256。

旧套件保留已分件的模型。拼接木板的五片木板和甲板实体、种植区的六个部件放入可编辑场景，种植预览及图鉴复用成品模型。楼梯由所属组件提供连续坡面实体，二层旧楼板使用连续承重面，小风车补桅杆实体。四个可穿行配方为两个种植区、旗杆、风铃。两个种植区、木储物箱及补水木桶各有自己的交互区域。吸附、承载、导航查询与存档布局继续由建造模块负责。

工期结束时，`BuildingService.completed` 使完工组件播放一次 `construction`。模型按部件交错入场，每件垂直下降约 0.31 秒，触地后达到 112% 再回到原尺寸；按部件数量控制总时长。路灯先底座后灯杆，再组灯头。楼梯先承重件，再由低到高铺踏步。完工实体即时启用，播放期间选取仍以成品位置为准。已完工的存档实例直接显示成品。

## 逐件结果

部件数取自 Godot 正式 Main 所生成的每段剪辑。时长单位为秒。

| 配方 ID | 部件 | 时长 | 范围 |
|---|---:|---:|---|
| `platform_5x5` | 9 | 2.047 | 五米套件 |
| `wall_5m` | 25 | 2.164 | 五米套件 |
| `window_wall_5m` | 69 | 2.280 | 五米套件 |
| `door_frame_5m` | 60 | 2.203 | 五米套件 |
| `post_5m` | 5 | 1.900 | 五米套件 |
| `beam_5m` | 1 | 0.580 | 五米套件 |
| `railing_5m` | 9 | 2.047 | 五米套件 |
| `stairs_5m` | 30 | 2.430 | 五米套件 |
| `roof_slope_5x5` | 10 | 2.065 | 五米套件 |
| `roof_flat_5x5` | 6 | 1.955 | 五米套件 |
| `planter` | 6 | 1.955 | 可新建 |
| `planter_small` | 6 | 1.955 | 可新建 |
| `oil_lamp` | 8 | 2.024 | 可新建 |
| `lamp_post` | 10 | 2.355 | 可新建 |
| `windmill` | 6 | 2.025 | 可新建 |
| `flower_pot` | 23 | 2.158 | 可新建 |
| `storage_crate` | 7 | 1.994 | 可新建 |
| `water_barrel` | 5 | 1.900 | 可新建 |
| `flag` | 3 | 1.320 | 可新建 |
| `table` | 5 | 1.900 | 可新建 |
| `stool` | 4 | 1.690 | 可新建 |
| `wind_chime` | 9 | 2.047 | 可新建 |
| `deck` | 5 | 1.900 | 旧档兼容 |
| `raft_4x4` | 18 | 2.138 | 旧档兼容 |
| `raft_2x4` | 10 | 2.065 | 旧档兼容 |
| `wall` | 7 | 1.994 | 旧档兼容 |
| `window_wall` | 6 | 1.955 | 旧档兼容 |
| `door_frame` | 3 | 1.320 | 旧档兼容 |
| `post` | 1 | 0.580 | 旧档兼容 |
| `beam` | 2 | 0.950 | 旧档兼容 |
| `railing` | 5 | 1.900 | 旧档兼容 |
| `stairs` | 16 | 2.334 | 旧档兼容 |
| `upper_floor` | 8 | 2.024 | 旧档兼容 |
| `roof_slope` | 12 | 2.092 | 旧档兼容 |
| `roof_flat` | 18 | 2.138 | 旧档兼容 |

## 验证

Godot 4.7.2 macOS。全目录 427 个网格部件逐个核对入场顺序、垂直位置轨道、弹性放大和末帧姿态。实体检查覆盖门洞与门柱、风车桅杆和旧二层楼板。实拍使用正式完工事件创建的组件，在独立取景环境中分别采样路灯和楼梯各四帧。[专项报告](../../../sea-work/verification/20261123-130539-construction-verified-b6d994/report.json) · [实拍序列](../../../sea-work/verification/20261123-130539-construction-verified-b6d994/project/outputs/construction-review.jpg)

| 检查 | 断言通过 / 失败 | 退出码 |
|---|---:|---:|
| 资产重新导入 | 导入成功 | 0 |
| `building-construction` | 1998 / 0 | 0 |
| `visual-building-construction` | 2006 / 0 | 0 |
| `building-5m-rules` | 446 / 0 | 0 |
| `building-save-compat` | 39 / 0 | 0 |
| `kit-safety` | 94 / 0 | 0 |
| `building-open-rules` | 122 / 0 | 0 |
| `building-ui-unified` | 66 / 0 | 0 |

界面测试接到现行配置接口后复跑。[界面回归报告](../../../sea-work/verification/20261123-130714-construction-ui-e6afee/report.json)

未通过的旧检查保留原始结果。 `building-5m-experience` 通过目录和十件几何检查，调用已移除的 `actor_controller.ground` 后中止，退出码 1。 `building-kit` 和 `building-integration` 分别在旧 `start_walk` 和 `approach` 调用后超时，退出码 124，后者还报告两条旧点击采集断言失败。本轮未验证发行包和全部配方的逐帧画面。[旧五米体验报告](../../../sea-work/verification/20261123-125542-construction-verify-2467f8/report.json) · [旧套件及集成报告](../../../sea-work/verification/20261123-125917-construction-final-ae8d07/report.json)

全局功能契约同步及检查均退出 1，分别报告 544 和 545 项既有问题，包含旧条款、外部证据缺失及其他资源漂移。普通检查从本轮登记前的 566 项降到 545 项，未新增错误。全局派生索引仍待既有问题清理后同步。[同步日志](../../../sea-work/building_construction/contracts-sync.log) · [检查日志](../../../sea-work/building_construction/contracts-check.log)
