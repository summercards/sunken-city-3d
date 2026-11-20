# 2026-11-19 · 默认入口切换为最小海面 3C 场景

[主文档](../../GDD_V1.0.md) · [启动](../features/boot/ledger.md) · [世界](../features/world/ledger.md) · [移动](../features/move/ledger.md) · [镜头](../features/camera/ledger.md) · [海面](../features/ocean/ledger.md) · [存档](../features/save/ledger.md) · [资产](../features/asset/ledger.md)

## 怎么玩、怎么编辑

`godot/project.godot` 的 F5 默认运行 `res://scenes/main_minimal.tscn`，不启动旧 `Zones`、`Economy`、`GameState`。场景根只挂海面、平台、斜坡、玩家、镜头、环境和太阳；不挂船、建筑群、道具、旧 HUD、任何经营和存档模块。海面复用现有水材质与运行网格，静态白天光照，独立累计水面时间，无旧昼夜/船尾迹/调参落盘。主场景不改原水材质。

- **WASD／方向键**：镜头相对行走，**Shift**：快跑。开场站在坡脚，按 W 可直接走上平台；回头走或按相反方向下坡。不提供跳跃。侧壁是真实碰撞；开放边缘没有隐形围栏，掉入海面下方后回坡脚，不写存档。
- **右键／中键拖拽**或 **`[` / `]`**：旋转相机；**滚轮／捏合**或 **`-` / `=`**：缩放；**左键拖拽**：手动移镜；**F**：恢复跟随。
- 在编辑器打开 `scenes/main_minimal.tscn`。`Deck` 和 `Ramp` 是两个可独立打开、摆放的 PackedScene。`Deck/RampJoin` 与 `Ramp/UpperJoin` 对齐；`Ramp/LowerJoin` 标出坡底接缝。改变组件内部尺寸时同时调可见资源与静态碰撞；移动组件根时两者一起移动。位置只以 TSCN 为准，初摆见[位置台账](../features/world/placed_positions.md)。旧场景的手摆及区块不参与本入口。
- 1 米指低端站立面至高端平台的**垂直高差**，不是坡长或板厚。平台 8 × 6 m；坡宽 3.2 m、水平坡长 3.6 m（约 15.5°），并包含 2.4 m 长的平坡脚。平台是 `BoxMesh` / `BoxShape3D`；斜坡是可编辑 `CSGPolygon3D`，独立碰撞为凸楔和坡脚盒。角色复用旅人、胶囊（半径 0.22 m、高 1.30 m）和步行动画，采用 Godot `move_and_slide`、重力、贴地；走路/跑步目标速度 2.8 / 4.0768 m/s。独立于旧导航、点击交互及存档。

## 旧入口与备份

**切换前独立备份：** `/Users/zyq/work/sea-work/generation/20261119-183934-2c167e/godot/`。从切换时的工作树复制 Godot 工程和依赖（不是从 Git 历史取文件），保留资源 / 脚本 UID、导入缓存及已存在的必要预览配置。`project.original.godot`、`checksums.json`、`working-tree-status.txt` 位于该目录上一层。备份中原场景 SHA-256 为 `407b04024dc61cad863d9769ea193e750b3db8acc4c02377b577d42456f405f7`；备份项目入口仍是原场景，用户目录单独设为 `sea-main-backup/20261119-183934-2c167e`，不读取真实玩家档。打开备份的 `project.godot` 后按 F5 可独立启动原版。不要把整份备份覆盖回正在工作的工程。

**恢复当前工作树的旧入口：** 关闭 Godot 编辑器，在仓库根执行 `cp -n godot/profiles/legacy_main.cfg godot/override.cfg`，再打开编辑器按 F5。该配置同时恢复原 `main.tscn` 和三个旧 Autoload；单改主场景地址不够。若已有 `override.cfg`，先查阅并合并其中的 `[application]` / `[autoload]`，不要覆盖。恢复原入口后使用原项目的存档目录，正式游玩会按旧规则读写存档。想回到白盒，移走本次复制的本地 `override.cfg` 并重开；配置不入 Git。若裸命令运行旧入口时有新增 GLB 的导入缓存缺失，先让编辑器完成扫描/导入。旧 `main.tscn` 的原路径、UID 和源码均未被本次覆盖；并行的屋顶街机铺接入保留。

## 验收证据

使用 Godot 4.7.2、`scripts/run_verification.py`，每项在 Autoload 前隔离用户目录。报告与截图位于 `/Users/zyq/work/sea-work/verification/`。

| 实测 | 结果 | 证据目录 |
|---|---|---|
| 独立备份恢复检查 | 旧玩法 `minimum-loop` exit 0，112/0；用备份原默认入口实际启动、真实渲染 120 帧，exit 0 | `20261119-183937-old-main-independent-backup-f107f4`、`20261119-191336-min3c-backup-direct-launch-a69805` |
| 新入口物理与真实按键事件 `minimal-main`（headless，不产图） | exit 0，35/0 | `20261119-185807-min3c-slide-1afa0d` |
| `visual-minimal-main`（真实渲染，1280×800） | exit 0，42/0；目视审阅坡脚、斜坡、平台三图 | `20261119-185931-min3c-render-legacy-cd8305/project/outputs/minimal-main-{apron,slope,deck}.png` |
| 默认启动、不经测试脚本 `minimal-main-launch --visual` | exit 0，120 帧后自动退出 | `20261119-190237-min3c-direct-launch-5f111b` |
| 编辑器隔离导入后再跑 `minimal-main` | 导入 exit 0，物理 exit 0；无新 GLB，两个组件由 TSCN 原生资源组装 | `20261119-190309-min3c-editor-import-a89cfd` |
| 用 `override.cfg` 恢复旧入口 | exit 0，9/0；`minimum-loop` 也 exit 0，112/0 | `20261119-185635-min3c-legacy-override-23301a`、`20261119-185931-min3c-render-legacy-cd8305` |
| 当前树（含并行接入的屋顶街机铺）重新导入后恢复旧入口 | 导入 exit 0，恢复 exit 0，9/0；仅复验入口和节点，不签街机铺玩法 | `20261119-190821-min3c-restore-after-import-228891` |

运行断言覆盖：海面显隐 A/B 像素差、仅最小节点、坡脚落地、玩家胶囊、几何包围、1 m 相对接合、无跳双向通行、连续贴地、平台侧面/坡侧碰撞、无隐形延伸、转向、Shift、跟随/右拖/缩放/F、开放边缘回起点以及不创建旧档或水面配置。失败过程如实保留：初轮 CSG 挤出轴及原 motor `floor_constant_speed` 配置不适合原生 `move_and_slide`；改正后通过。没有用预期故障白名单掩盖引擎错误。旧场景已知导航体素量化和采集点吸附警告仍在。未测试手柄、其他设备、发行包，也未在生产用户目录读写真档；未以编辑器导入代替人工编辑或手感验收。

## 静态门禁（不代替运行）

- `python3 scripts/check_placed_positions.py`：exit 0，9 项、0 警告；`git diff --check`：exit 0。
- `check_feature_contracts.py --sync`：exit 1，543 项；普通检查：exit 1，544 项，未写派生功能索引。前置普通检查已有 543 项；当前唯一新增诊断为并行屋顶街机铺区块的 `zones.json` 内容 ID 尚未同步。白盒新条款、资产分类、资产哈希及源索引未增加诊断；未为通过门禁批量刷新存量哈希。前、后日志位于备份父目录的 `contracts-before.log`、`contracts-sync.log`、`contracts-check.log`。
- 并行街机铺刚接入后，一次裸缓存的旧入口回切出现 GLB 导入产物缺失；只在隔离副本重新导入后恢复测试通过，未覆盖工作树的旧世界内容。
