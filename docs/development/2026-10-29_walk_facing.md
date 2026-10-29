# 角色行走朝向修复（2026-10-29）

对应功能：SEA-MOVE；条款：SEA-MOVE-R09，并回归 R01/R02/R03/R04。

角色的脸、脚尖位于局部 +Z，原 `WalkAction.step()` 却用 `atan2(-offset.z, offset.x)` 将局部 +X 对齐移动方向，因此所有方向都侧着行走。现在改用 `atan2(offset.x, offset.z)`，保留原有指数平滑转向、2.3m/s 步速和地面路径检查。自动接近及回泊位共用该行走动作；模型、船只和存档结构未改动。

新增 `walk-facing` / `visual-walk-facing` 验证入口：正式角色与控制器在合法测试地面执行八方向、30/60/120 FPS 行走，对比实际位移与头部局部 +Z 的世界方向，核对步速和到达停止；再在正式浅水平台验证反向改道、平滑转身和取消后朝向。真实渲染入口抓取平台往返近景。

## 当前验证

所有运行均由 `scripts/run_verification.py` 创建工程外副本，在 Autoload 前隔离用户数据。证据和截图位于 `D:/projects/sea-work/verification/`。

| 验证 | 结果 / 退出码 | 证据目录（上述根目录下） |
|---|---|---|
| `walk-facing` | 102项，0失败；exit 0 | `20261029-151511-walk-facing-d68db7` |
| `visual-walk-facing` | 106项，0失败；exit 0，Vulkan Forward+ / RTX 4060 Ti | `20261029-151536-walk-facing-render-21d2db` |
| `board-click` | 12项，0失败；exit 0 | `20261029-151611-walk-facing-integration-7a2caf` |
| `save-seed` / `framework-integration` | 存档种子成功；44项，0失败；均exit 0 | 同上 |
| `surface` | 30条航路、456项，1失败；exit 1 | 同上 |
| `click` | 32项，3失败；exit 1 | 同上 |
| 特性文档同步与检查 | 各exit 0；35功能、0 issues | `scripts/check_feature_contracts.py --sync`及不带参数检查 |

### 真实渲染

已亲眼检查1280×800往返近景：前进时正面与脚尖朝前，反向改道后转身朝向返程。两图各有201/202个采样灰度层级（阈值>32），角色投影位于视口中心90%范围，排除空白或取景到画面外的假通过。图像指标见渲染目录的 `image-qa.json`。

- [前进截图](../../../sea-work/verification/20261029-151536-walk-facing-render-21d2db/project/outputs/walk-facing-outward.png)
- [返程截图](../../../sea-work/verification/20261029-151536-walk-facing-render-21d2db/project/outputs/walk-facing-return.png)

### 预期对照失败与现有集成失败

对照目录：`20261029-151723-walk-facing-baseline-5f148b`。通过同一runner仅在工程外副本恢复旧偏航公式；仓库保持修正后的代码。

- 朝向专项在旧公式下有26项失败、exit 1，修复后同一判据全部通过。这是刻意恢复故障的预期失败。
- 新旧公式的 `surface` 均只失败「种植物件是独立场景 home_plot」；`click` 均只失败「新航线取消旧拾取」「航行途中改道」「建造菜单前往并自动交付」。逐条比较报告中的失败列表完全一致；这4项是当前工作区的其他集成问题，未修改相关规则、未宣称通过。
- 首次运行因Windows默认GBK读取UTF-8失败，未启动游戏；后续设置 `PYTHONUTF8=1`。首个实际场景运行因当前 `hud.gd::_service_sort()` 的 `moved` 无法推断类型而编译失败；补上 `bool` 声明后重新完整验证，上表成功项目均无非预期引擎/脚本错误、无预期故障。

### 未执行项与边界

未执行全功能套件、移动设备、正式存档以及潜水视觉验证。本轮结论仅覆盖陆地朝向、平滑转身、停止/取消、上下船与现有状态机集成。证据为上述工作区副本快照；源码再变更须重新核验。
