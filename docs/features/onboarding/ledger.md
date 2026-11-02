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

## 维护入口

唯一详细规则以本目录spec.md为准。代码通过已登记目录和公开端口接入，新增内容保留稳定ID；变更后执行本页verification入口，再同步主文档。

## 未执行项

设备/触摸/手柄/真实断电与发行包未验；已按用户要求完成自行比例和画面验收。未来DIY绘图不在本次端口预留实现内。未修改用户实际存档。
