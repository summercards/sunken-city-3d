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
    "godot/assets/textures/avatar",
    "godot/shaders/avatar_limb.gdshader",
    "art_source/characters/avatar/v002/rig_contract.json",
    "art_source/characters/avatar/v003/customization_contract.json",
    "art_source/characters/avatar/v005/shape_contract.json",
    "art_source/characters/avatar/v006/shoulder_contract.json",
    "godot/shaders/avatar_eye.gdshader",
    "godot/shaders/avatar_mouth.gdshader"
  ],
  "verification": [
    "avatar-graphic",
    "visual-avatar-graphic",
    "visual-avatar-shoulders",
    "avatar-customization",
    "visual-avatar-customization",
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
| SEA-AVATAR-R03 | 9类23槽位147选项、9连续参数；原稳定ID和旧档保留，目录解析和三分辨率真实UI通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R04 | 按用户图冻结比例，功能根与碰撞资源保持；肩肘髋膝及手部求解按共同尺寸表适配，移动/获物动作当前回归 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R05 | 旋转/正面/随机搭配接口；真实旋转与结束归零通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R06 | 旅人证后退、保存失败提示/回滚/重试与原子磁盘读回通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R07 | 根v4独立profile1、旧缺记录迁移、坏档恢复前拒绝、跨进程恢复通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R08 | 暂停菜单真实重开与取消；保留位置、进度并保存整局 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R09 | DIY引用与扩展元数据跨进程往返；当前仅预留引用端口 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R10 | 未来未知ID保留并默认展示；扩展字段不丢失 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R11 | 共享视觉/圆体/滚动，三分辨率真实键鼠37项与无输入穿透通过 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R12 | 独立隔离专项、跨进程、动作回归与原生渲染分别记录；设备边界见交付 | [本轮交付与实测](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R13 | 用户原图/人工标点/六项实测比例、同高同角度/正面/侧面自行目视；历史六项最大偏差1.68%；当前用户最新轮廓由R22与v005契约取代默认，最新投影13项通过 | [本轮比例追加验收](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-AVATAR-R14 | 21骨骼与4张连续封闭网格；80项骨骼专项/92项原生渲染、0–120°截面、单骨GPU变形、原动作及保存回归通过 | [本轮交付](../../development/2026-11-02_avatar_limb_skinning.md) |
| SEA-AVATAR-R15 | 红晕/雀斑/胡茬真实透明贴图，曲面偏移专项与真实画面通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R16 | 4轮廓/头大小/眼距及9参数持久化；旧6参数显式补默认、坏数据拒绝、整局保存恢复通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R17 | 14发型/12眼形/5胡子、刘海/发饰和发型DIY；极值组合、尾根接触与真三视图通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R18 | 分类子页、滑杆、撤销重做、对照、镜头及新增头横宽/臂粗/腿长的三分辨率真实输入通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R19 | 最终3559项混合/动作/密集130姿势及真实物件检测通过；原生三视图/三分辨率另列，未执行项在交付内 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R20 | 12眼形粗线条图集、6情绪/眨眼/视线，GPU实际像素变化和48连续帧验收通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R21 | 实际上臂中心线平直、肩袖/腰胯/腿根接触；连续蒙皮与六动作、真实物件/帽子净空通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R22 | 按最新红线做饱满躯干、低胯短腿；头横宽/臂粗/腿长独立滑杆、旧6参数迁移与实际网格验证通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R23 | 16种嘴型1024×1024透明图集、情绪切帧/开合；所有款式真实渲染和原ID保存通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R24 | 礼帽/渔夫帽挂点下移0.028m、针织帽0.018m；帽下发型/眉眼镜与正侧背当前目视通过 | [最新交付与实测](../../development/2026-11-03_avatar_shape_and_mouth.md) |
| SEA-AVATAR-R25 | 实际蒙皮肩根按红线内收至标准胖体间距0.28937m、降低至0.74125m；肩袖/上胸/腋下修顺，当前4303断言和真三视图/六动作及保存回归通过 | [最新交付与实测](../../development/2026-11-03_avatar_low_shoulders.md) |

| SEA-AVATAR-R26 | 保持最新低肩/饱满躯干/短腿基体与9项参数、147选项ID；优化低饱和配色、布料条纹/袖口/袜口分区与粗糙度、自然呼吸/重心/步伐/换装微反馈、平滑转身；手帐步骤排版与淡入，不缩放按钮扰乱点击热区 | 当前实际网格/密集动作、三视图、三分辨率UI与保存回归；本轮证据见下 |

## 2026-11-04 · 新旅程角色与界面深化

- 不推翻用户已确认的 v006 低肩、内收肩根、饱满衣摆和短腿轮廓，不动碰撞/功能根/骨架绑定。体型仍由既有9个连续参数和4种轮廓定制；本轮不是重新制作 Blender 模型。
- 低饱和海沫青绿、暖杏、焦糖栗棕、深海藏青、帆布米白；原目录稳定ID和旧档兼容不变。布料边缘与条纹柔化，皮肤/头发减少塑料高光；仍以当前真实场景光照验收。
- 待机增加小幅呼吸、重心与环顾，走路增加轻微反向头/身摆动与膝部反馈；换装微反应仅是表现，不写玩法。旋转使用最短角插值，退出后局部yaw归零、世界朝向不变。
- 捏人使用旅人档案布局、三步进度、选中描边、色块、分类子页和滚动；保留撤销/重做/按住对照、随机、参数复原和保存失败重试。页切换与面板淡入不移动点击热区。
- 修复子页滚动跨分类残留、分类重选落到旧子页、按钮最小宽度挤出纸张等真实输入问题，1280×800 / 1600×1000 / 1920×1080分别检查。
- 对照肩位契约的基体/四肢当前仍合规；不是声称全参数笛卡尔积与所有未来服装均无穿模。历史原图六项≤5%不用于新低肩形体：当前肩跨/脸宽投影约9.16%相对偏差落在后续肩位契约允许区间，13项当前投影检查通过，不冒称全部≤5%。
- 最终接受证据共21入口/5675断言（包含相关开场/玩法回归），具体目录与各项数量见[新旅程本轮记录](../onboarding/ledger.md)。角色密集实际网格3559项与原生GUI368项分别exit0，三分辨率/三视图自行目视完成。
- 资产仅对白名单、已核验前身定点登记。标题旧哈希为HEAD文件CRLF版本；HUD旧哈希追溯到33845e7213提交CRLF版本，落后HEAD仅既有屋顶牧场目的地一行，审阅后保留previous并登记当前值。无关场景/天空/zones问题不刷新。

## 维护入口

唯一详细规则以本目录spec.md为准。代码通过已登记目录和公开端口接入，新增内容保留稳定ID；变更后执行本页verification入口，再同步主文档。

## 未执行项

设备/触摸/手柄/真实断电与发行包未验；已按用户要求完成自行比例和画面验收。未来DIY绘图不在本次端口预留实现内。未修改用户实际存档。
