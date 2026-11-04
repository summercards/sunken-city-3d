# SEA-ONBOARDING · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-onboarding) · [功能设计](spec.md)

```json
{
  "feature_id": "SEA-ONBOARDING",
  "status": "implemented",
  "owner": "ArrivalFlow / 注入场景端口",
  "code_paths": [
    "godot/src/onboarding"
  ],
  "verification": [
    "onboarding",
    "visual-avatar"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ONBOARDING-R01 | 真实主泊位安全地面站立，不创建第二玩法人物 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R02 | arriving/editing/leaving独立流程，防重入，镜头推近与恢复 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R03 | 锁世界/镜头输入、HUD、时间、经营与自动保存，水面保留 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R04 | 姓名→外观→旅人证，返回保留，首创Esc不能跳过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R05 | 首次保存含码头站位与档案，失败保持创建可重试 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R06 | 完成档案冷启动继续、旧缺档案迁移、未完成进入创建 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R07 | 确认重置后创建，旧姓名/形象随归档保存 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R08 | 注入泊位与相机端口；目录不访问Main/Economy全局 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R09 | 结束/取消释放临时界面、镜头，恢复各层显示/处理状态 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-ONBOARDING-R10 | 23项开场专项、37项真实输入与三分辨率，当前回归和未执行项分列 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |

| SEA-ONBOARDING-R11 | 新局安全甲板朝向小屋，肖像镜头以阳光房为背景；完成后平滑回正并显示三句独白。台词首击补全、次击推进，阻止误触世界/镜头，不叠加欢迎通知或视野百分比；三分辨率真实输入与截图验收 | `godot/tests/test_onboarding.gd`、`godot/tools/capture_avatar.gd`；本轮证据见下 |

## 2026-11-04 · 新旅程体验深化

- 首创位置为主泊位内侧开放甲板 `(3.15, landing_y, 11.2)`；角色根朝向小屋 `PI`，不朝船。编辑时仅 BodyPivot 转向肖像镜头，离开用 0.6 秒回正，不改变世界根朝向。
- 标题保留真实场景，新增克制副标题、悬停颜色/提示位移与 0.45 秒淡出；姓名、穿搭、旅人证按步骤呈现，不重复现有玩法系统。
- 肖像采用小屋背景、左人物右档案；全身/面部/旅人证镜头平滑切换；日常跟随机位保留，不强改存量玩家偏好。
- 开场独白依次说明屋顶落脚处、随身种子/瓶盖、屋前培养箱；支持按钮及空格/回车。叙事期间阻止世界点击、镜头和背包键；既有体力见底单句提示保留原非叙事行为。
- 旧标题专项原先默认新存档也能 1.9 秒直接进入玩法，与不可跳过捏人冲突；现明确使用已完成角色夹具验证续玩，首创由 onboarding 和真实输入专项覆盖。
- 最终验收共21个独立入口、5675项断言，接受项全部exit 0、0失败；这不是一次全项目全绿运行，按下列当前证据分组记录，失败/超时保留在原目录。测试始终由隔离入口创建新用户目录，没有改动真实玩家存档。

| 当前证据目录（均位于 `D:/projects/sea-work/verification/`） | 接受入口与断言 |
|---|---|
| `20261104-134436-onboarding-r9-final-879d3b` | avatar-graphic 389、visual-avatar-graphic 458、visual-avatar-shoulders 31、avatar-skinning 80、visual-avatar-skinning 92、avatar-proportions 10、visual-avatar-proportions 13；不接受该目录密集专项124超时作为通过 |
| `20261104-142602-onboarding-r10-dense-2afffc` | avatar-customization 3559；600秒预算完成，exit0；实际身体/六动作/密集获物网格净空 |
| `20261104-142602-onboarding-r10-flow-0dd4f6` | avatar 192、avatar-restart 8、energy 37、character-motor 42、actor-presentation 31、harvest-receive 80；本目录onboarding/title-screen失败已由r11替代，不计为通过 |
| `20261104-151119-onboarding-r11-accepted-c93b3b` | onboarding 38、title-screen 29、visual-avatar 49；新建/续玩、打字机两次输入语义、台词模态、平滑转身、取消朝向；三分辨率真实渲染 |
| `20261104-151730-onboarding-r11-ui-regression-5b28ba` | visual-avatar-customization 368、title-clock-seed（写入标记）、visual-title-screen-day 28、minimum-loop 141；最终源码一致性已核对 |

- 本轮自我目视：标题、姓名、发型/面部、旅人证、日常小屋朝向、台词三分辨率、肩部三视图均已检查。`avatar-09-dialogue-*.png` 证明台词可完整阅读，底部不再被视野百分比覆盖。
- r10转身检查曾受角度wrap和headless帧间隔影响；改为实际Tween确定性推进采样后r11通过，不放宽角度插值条件。
- 全局门禁保留7项非本轮来源问题：SEA-WORLD账本缺JSON头、SEA-SCENE-ORF-ASSEMBLY源哈希、其来源索引不一致、zones运行哈希、ocean_sky运行哈希、zones内容ID漂移、派生feature_index陈旧。`--sync`因上述问题拒绝写入，未手改派生索引绕过检查。架构17服务门禁与差异格式检查通过。
- 更早的 r8 手工日志与 r9 密集专项 180 秒超时不作为最终通过证据；原生世界资源仍有既存 Unicode 节点名称/导航体素精度警告，不等同本轮零警告。

## 维护入口

唯一详细规则以本目录spec.md为准。代码通过已登记目录和公开端口接入，新增内容保留稳定ID；变更后执行本页verification入口，再同步主文档。

## 未执行项

设备/触摸/手柄/真实断电与发行包未验；已按用户要求完成自行比例和画面验收。未来DIY绘图不在本次端口预留实现内。未修改用户实际存档。
