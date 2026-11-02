# SEA-AVATAR · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-avatar) · [功能设计](spec.md)

```json
{
  "feature_id": "SEA-AVATAR",
  "status": "implemented",
  "owner": "AvatarProfile / AvatarCatalog / AvatarSession",
  "code_paths": [
    "godot/src/avatar",
    "godot/assets/data/avatar_catalog.json",
    "godot/shaders/avatar_limb.gdshader",
    "art_source/characters/avatar/v002/rig_contract.json"
  ],
  "verification": [
    "avatar",
    "avatar-restart",
    "visual-avatar",
    "avatar-proportions",
    "visual-avatar-proportions",
    "avatar-skinning",
    "visual-avatar-skinning"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-AVATAR-R01 | 独立所有者与深拷贝草稿；查询、取消、写失败回滚均通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R02 | 姓名1–12字、非法字符拒绝；空白Enter不跳过，保持输入焦点 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R03 | 8类18槽位95选项解析专项，发型/眼形/帽眼镜真实鼠标专项 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R04 | 按用户图冻结比例，功能根与碰撞资源保持；肩肘髋膝及手部求解按共同尺寸表适配，移动/获物动作当前回归 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R05 | 旋转/正面/随机搭配接口；真实旋转与结束归零通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R06 | 旅人证后退、保存失败提示/回滚/重试与原子磁盘读回通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R07 | 根v4独立profile1、旧缺记录迁移、坏档恢复前拒绝、跨进程恢复通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R08 | 暂停菜单真实重开与取消；保留位置、进度并保存整局 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R09 | DIY引用与扩展元数据跨进程往返；当前仅预留引用端口 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R10 | 未来未知ID保留并默认展示；扩展字段不丢失 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R11 | 共享视觉/圆体/滚动，三分辨率真实键鼠37项与无输入穿透通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R12 | 独立隔离专项、跨进程、动作回归与原生渲染分别记录；设备边界见交付 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R13 | 用户原图/人工标点/六项实测比例、同高同角度/正面/侧面自行目视；六项当前最大偏差1.68%（骨骼版重新实测），每项5%阈值、真实网格投影13项通过 | [本轮比例追加验收](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R14 | 21骨骼与4张连续封闭网格；80项骨骼专项/92项原生渲染、0–120°截面、单骨GPU变形、原动作及保存回归通过 | [本轮交付](../../development/2026-11-02_avatar_limb_skinning.md) |

## 维护入口

唯一详细规则以本目录spec.md为准。代码通过已登记目录和公开端口接入，新增内容保留稳定ID；变更后执行本页verification入口，再同步主文档。

## 未执行项

设备/触摸/手柄/真实断电与发行包未验；已按用户要求完成自行比例和画面验收。未来DIY绘图不在本次端口预留实现内。未修改用户实际存档。
