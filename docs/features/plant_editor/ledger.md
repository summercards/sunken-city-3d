# SEA-PLANT-EDITOR · 独立植物工坊 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-plant-editor) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-PLANT-EDITOR",
  "status": "implemented",
  "owner": "PlantAuthoringSession拥有树制作配方；EditorPlugin拥有本地预览；运行风/草仍归SEA-AMBIENT，正式资产归SEA-ASSET",
  "code_paths": [
    "godot/src/plant_authoring/recipe.gd",
    "godot/src/plant_authoring/species.gd",
    "godot/src/plant_authoring/geometry.gd",
    "godot/src/plant_authoring/generator.gd",
    "godot/src/plant_authoring/session.gd",
    "godot/src/plant_authoring/store.gd",
    "godot/src/plant_authoring/leaf.gdshader",
    "godot/addons/plant_editor/plugin.gd",
    "godot/addons/plant_editor/editor_screen.gd",
    "godot/addons/plant_editor/preview.gd",
    "godot/addons/plant_editor/editor_verification.gd",
    "godot/tests/test_plant_authoring.gd"
  ],
  "verification": ["plant-authoring", "editor-plant", "editor-workshop-upgrade"]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R01 | planned / 暂停 | 尚无 EditorPlugin、主屏或隔离性验收；不得视为可用编辑器。 |
| SEA-PLANT-EDITOR-R02 | draft | species.gd 记录香樟/鸡爪槭/垂枝桦；植物形态事实来源见 spec。未做实际几何检查。 |
| SEA-PLANT-EDITOR-R03 | draft | recipe/generator 代码草稿；无 Godot 验收。 |
| SEA-PLANT-EDITOR-R04 | draft | 几何 helper 草稿；未渲染，无美术签署。 |
| SEA-PLANT-EDITOR-R05 | draft | 草库资源消费与苔藤代码草稿；未做集成或共享资源不变验证。 |
| SEA-PLANT-EDITOR-R06 | draft | session/store 草稿；未实际保存重载验证。 |
| SEA-PLANT-EDITOR-R07 | planned | 尚无预览风或生命周期验证。 |
| SEA-PLANT-EDITOR-R08 | research | 已读 Sapling/Mtree/Zylann TreeGen/TreeIt 官方说明与风格化叶簇法线文章。无第三方代码导入、无插件安装；网址、许可与取舍见 spec。 |
| SEA-PLANT-EDITOR-R09 | pending | 尚无注册 runner 入口，未启动 Godot 验收，不以子代理静态检查冒充通过。 |

## 2026-11-12 用户暂停

11:28 用户明确要求“植物编辑器先把记录放在一边”，优先修复楼房编辑器。不继续制作植物 UI、导出或验证。上述六个源草稿与调研保留，不删除、不接入 project.godot 或正式世界。恢复时先审查代码并补真实验收。

## 2026-11-14 用户恢复制作 · 独立树木工坊

按本次新指令恢复，以下状态覆盖历史planned/draft但不删除旧证据。功能制作闭环已实现，用户美术终审/正式世界接入仍未签，不把“完成工坊”写成游戏内已植入。

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R01 | implemented；独立plant_editor EditorPlugin“树木工坊”，project已启用；独立Session/World3D/草稿/历史/保存。与房屋插件并行，不消费房屋制作脚本。 | editor-plant真实双插件隔离检查；切换前先初始化房屋预览再冻结基线，实际树/房屋配方及草稿不串。 |
| SEA-PLANT-EDITOR-R02 | implemented；三树种defaults/冠形/互生对生/椭圆掌裂三角锯齿叶真实几何不同，不是球团；来源仍为原登记文字资料。 | 三树种整树与裸枝/叶近景实拍，内核逐面、确定性/形态断言；幼树风格化比例，不签植物生理模拟。 |
| SEA-PLANT-EDITOR-R03 | implemented；主干/主枝/二级枝真实曲管，每branch_id独立RNG和覆盖；开关、粗度、角度、长度带叶更新，密度不重抽木质枝。 | core确定性流/关枝不串其它枝/单枝mesh与leaf/hash；editor单枝选择/高亮/参数自动预览。 |
| SEA-PLANT-EDITOR-R04 | implemented；有厚度双表面叶肉、曲面采样/法线混合，species轮廓不同；树干叶片独立显隐。减重复细分保叶轮廓和弯曲。 | 叶片近景已目检；默认香樟187792、鸡爪槭82456、垂枝桦345972三角面，非低模LOD或群树林性能签署。 |
| SEA-PLANT-EDITOR-R05 | implemented；苔藓裁入真实变径树皮参数域、藤蔓路径附着并下垂；草源几何复制重用，UV2保原alpha轮廓，RGB走PaletteUV。 | core宿主表面/半径跟随、开关、公共模型/材质缓存及字节hash不变；附生近景/草轮廓真实渲染。 |
| SEA-PLANT-EDITOR-R06 | implemented；候选3件bundle（配方/静态TSCN/manifest）版本化、独占tmp、重载校验后rename；旧版immutable；选择默认/场景根均可。 | core两版/坏配方/同count篡改负例、editor文件/2版重载/候选场景根；static无脚本相机灯光碰撞。 |
| SEA-PLANT-EDITOR-R07 | implemented；每build四本地ShaderMaterial，local_time/preview_wind只在可见树预览更新，隐藏暂停时钟和渲染。导出清零且不改原预览实例。 | editor可见/隐藏/恢复、双插件切换与全局写接口静态门禁；无写vegetation_*。 |
| SEA-PLANT-EDITOR-R08 | implemented；沿用11-12已登记研究取舍，只参考算法，无第三方代码/预设图片导入，无新二进制插件。 | species保留原来源；本轮不声称重新安装Sapling/Mtree。 |
| SEA-PLANT-EDITOR-R09 | implemented；注册plant-authoring/editor-plant，独立无Main副本、真实Metal后端与旧房屋回归并列。 | 最终core210/0、editor263/0、house-random969/0、house-editor955/0，全部exit0；截图目检不等于用户美术终审。 |
| SEA-PLANT-EDITOR-R10 | implemented；紧凑松绿主题、六模块在预览上方、16/18字体、全HSlider、160ms调度及单拖一次撤销，错误保留输入/成功模型，可复制完整详情。 | 860×600真实UI检查/实拍、滑条/失败纠正/undo/64格全部UI断言。 |
| SEA-PLANT-EDITOR-R11 | implemented；可选随机/种子/幅度、四色格manual/auto、局部风/细枝数、UV8px单格安全；草alpha专用外链不改旧库。 | core逐面非退化/有限/单位法线/有面积UV/角色/公共PNG与库资源不变，editor64色真实UV断言。 |
| SEA-PLANT-EDITOR-R12 | implemented；公开preview_candidate一次构建提交，排序稳定JSON指纹1e-9十进制；Store逐数据比较，不以count替代；原子草稿、严格根/路径校验。 | 保存7.2+0.4二进制尾数误差已实测修复；大于精度的0.001变动仍识别；core正常/篡改负例/重载闭环。 |
| SEA-PLANT-EDITOR-R13 | implemented；最终三树种静态样例和整树/裸枝/叶/附生/UI图已产出；旧房屋功能独立回归。 | below实际报告。只完成独立制作端，不嵌入房屋、Main或潜水模型，正式AssetID/艺术终审/LOD另计。 |

### 当前最终证据

- 内核：`/Users/zyq/work/sea-work/verification/20261114-030657-tree-core-optimized-final-59c0fc/report.json`，plant-authoring210/0、exit0（真实后端用于MultiMesh数据保留，不产生截图，非视觉验收）。
- 真实编辑器：`/Users/zyq/work/sea-work/verification/20261114-030705-independent-tree-complete-final-251c8a/report.json`，editor-plant263/0、exit0，asset-import exit0；inner `project/outputs/plant_editor_report.json`，unexpected_errors=[]。
- 实拍：该批`project/outputs/plant_editor_evidence/{camphor_whole,maple_whole,birch_whole,bare_branches,leaf_close,epiphyte_close,manual_palette,compact_860x600,editor_main_screen}.png`。主线程已目检整树/树型/叶近景/附生/紧凑与完整UI；黄色盒为选枝高亮，导出无该节点。
- 三树种候选：该批`project/outputs/plant_editor/example-{camphor,maple,birch}/revision_0001/`；TSCN约25.2MB/11.0MB/49.2MB，公共PNG与shader仍外链。候选作者模型不自动游戏化；没有全树林FPS/LOD门禁。
- 预期故障：最终无登记预期红项。中间类型警告、最小隔离依赖缺失、Dummy不保MultiMesh、浮点JSON指纹、首次房屋预览基线、草卡方片、样例导出360秒超时均保留历史；最后以实测修复，未放宽几何/存储/隔离门禁。
- 未执行：用户艺术终审、复杂宿主嵌入/碰撞导航、正式资产接入、潜水模型、移动/网页后端群树林性能、跨进程OS重启恢复验证。插件草稿同进程恢复和独立文件原子写入已检查，不冒充跨进程签署。
- 定点运行清单：本轮17个明确制作源码/插件/验收入口登记到runtime_resource_inventory，0不一致，不发AssetID、不回填其他旧资源hash。全库实际sync/check exit1，533/534 issues（46功能/1073源资产/1527运行资源），无SEA-PLANT-EDITOR或SEA-WORKSHOP条款错误；派生索引受全库错误阻塞未生成。日志`/Users/zyq/work/sea-work/tree_random_contracts_{sync,check}_20261114.log`。详见[开发与使用记录](../../development/2026-11-14_random_house_independent_tree_workshop.md)。
