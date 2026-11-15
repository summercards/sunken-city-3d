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
    "godot/tests/test_plant_authoring.gd",
    "godot/src/plant_authoring/trunk_path.gd",
    "godot/src/plant_authoring/game_wind.gdshaderinc",
    "godot/src/plant_authoring/wind_runtime.gd",
    "godot/src/plant_authoring/host_attachment.gd",
    "godot/src/plant_authoring/host_scene_guard.gd",
    "godot/tests/test_plant_integration.gd",
    "godot/tests/test_host_scene_guard.gd",
    "godot/tests/test_plant_performance.gd",
    "godot/src/plant_authoring/lightweight_foliage.gd",
    "godot/src/plant_authoring/foliage_batch.gd",
    "godot/src/plant_authoring/leaf_card.gdshader",
    "godot/src/plant_authoring/leaf_volume.gdshader",
    "godot/tests/test_plant_canopy.gd"
  ],
  "verification": ["plant-authoring", "plant-integration", "plant-performance", "plant-canopy", "host-scene-guard", "editor-plant", "editor-workshop-upgrade"]
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

## 2026-11-14 树干风动、细节与树屋结合深化

本节覆盖上一轮“未做宿主结合”的实施边界，两套工坊仍独立。当前源码已实现以下条款；最终真实编辑器证据单列追加，不把内核数字当视觉签署。

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R14 | implemented；trunk_path米制控制点、smoothstep横向插值、非均匀环，UI折叠XYZ滑条/插删/自动路径；首尾显式保精度。 | plant-integration路径与几何断言；路径拖拽、撤销及坏输入由editor-plant补验。 |
| SEA-PLANT-EDITOR-R15 | implemented；树皮次色几何、苔藓尺寸/方向/高度/色差，按已知宿主三角面重心定位；不放宽0.00001m贴合门禁。 | 附生三项3–5e-5m误差已修正为面内插值；保留真实Mesh和手动色格检查。 |
| SEA-PLANT-EDITOR-R16 | implemented；只读世界唯一风owner，局部fallback；叶尖权重、藤顶固定、木干/苔藓不动；编辑器@tool只显式采样。 | wind-tool-reload-final内核540/0、exit0；单脚本editor13/0但含current_window/退出RID日志，不能替代完整editor验收。 |
| SEA-PLANT-EDITOR-R17 | implemented；静态三件bundle不变，动态旁车新增唯一根风脚本；本地材质/公共外链/幂等prepare。 | 首次normals≤0.0002，其余逐字段零差；后续精确摘要含同面数篡改负例。10surface测试样例metadata952280→4480B、TSCN3507139→1224626B。 |
| SEA-PLANT-EDITOR-R18 | implemented；只读宿主参考、洞口建议五点路径、真实Mesh与primitive实体检测、根贴楼板；不含全部枝叶碰撞。 | plant-integration；完整玻璃阻挡与真实保存房屋结合走editor-plant。top_level拒绝，宿主不导入树场景。 |
| SEA-PLANT-EDITOR-R19 | implemented；host_scene_guard加载前文本闭包预审，UI全部host载入及cached预检先审计，加载后继续SceneState门禁。 | host-scene-guard152/0、exit0；危险负例未交ResourceLoader执行，不保证TOCTOU防护。 |
| SEA-PLANT-EDITOR-R20 | implemented；规范state fingerprint、完整状态历史、独立recipe/context dirty、失败pending/recovery预检；无私有历史访问。 | 当前plant-authoring233/0、exit0；新增尾差去重/陈旧保存/纯变换/草稿JSON往返。完整UI绑定测试单列追加。 |
| SEA-PLANT-EDITOR-R21 | implemented / 验收进行中；统一runner注册四入口，真实保存宿主和确定风帧，完成哨兵防异常跳过。 | 旧editor深测410checks/18失败保留历史：末高精度、StringName新增键、非tool风placeholder已定位修复；最终以新报告为准。 |

- 内核阶段证据：`/Users/zyq/work/sea-work/verification/20261114-233026-wind-tool-reload-final-3d4190/report.json`（540/0）；`20261114-233736-verification-ea86d5/report.json`（233/0）。均Metal真实后端逻辑测试、无截图。
- 当前未签：用户艺术终审、LOD/群树林性能、移动/Web后端、正式世界/潜水接入、跨进程OS重启恢复。树与房屋候选不会自动登记为正式资产。

### 2026-11-15 深化完整闭环与叶片保真优化

上节验收进行中已收口：`/Users/zyq/work/sea-work/verification/20261115-011859-tree-leaf-editor-final-2527aa/report.json`，editor-plant **1174/0、exit0、unexpected_errors=[]**，资源导入exit0；inner记录源码SHA256，主线程核对generator/geometry/recipe/screen/verification/wind/guard与当前字节一致。R14–R21功能验收完成，艺术终审不代签。

- 已修真实Store的Material基类外链误拒，仍核验实际ShaderMaterial/StandardMaterial3D头和递归闭包；host-scene-guard155/0。已修Godot没有String.path_to_file/path_to，通过受限res路径共同前缀计算attachment相对路径，中文/同目录/跨目录/旧文件保护真实重载覆盖。
- 新恢复负例覆盖不存在宿主/撞墙/非法保存指纹/上下文，失败保持配方、pending、历史、dirty、模型宿主实例及镜头；保存植物与attachment分别清对应dirty。
- 实拍路径：该批`project/outputs/plant_editor_evidence/`。三树种两帧有真实像素变化，木干/树皮/苔藓变化像素为0；树屋全景/洞口近景/苔藓近景/860×600已目检。苔藓仍有多边形色块贴片观感，不称自然苔藓美术终验。之前15 ObjectDB退出泄漏警告未再出现；仍有1 unclaimed StringName提示，不宣称零警告。
- 当前最终核心组合：`20261115-012739-workshop-tree-kernel-delivery-d20b88/report.json`，plant-authoring、plant-integration、host-scene-guard、workshop-random、workshop-damage均passed=true/exit0/unexpected_errors=[]；逻辑测试有真实Metal后端但不出图。

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R22 | implemented；balanced/high/reference三档，默认balanced；索引复用+保守内部自适应，边壁采样不变，叶数/排列/颜色/厚度保持。 | 三树种完整模型顶点492736→243040、214680→111384、912108→419292；三角187792→182992、82456→79576、345972→311412。没有用删叶或平卡替代。 |
| SEA-PLANT-EDITOR-R23 | implemented；作者显式COLOR权重兼容runtime，草/藤同样补齐；UI三档、实际统计、保存撤销重载。 | 真实editor1174/0；高质量保持原面数，reference原版可随时对照，统计不是drawcall估计。 |
| SEA-PLANT-EDITOR-R24 | implemented；plant-performance正式runner注册，真实渲染与wall-clock、无fixed-fps；三树种36图及规模场景，GPU无有效数值明确未测。 | `20261115-012810-leaf-fidelity-performance-delivery-d806c6/report.json`专项546/0、exit0；共享资源基准不是Store默认逐实例风路径，当前动态策略另补测。 |

同种子36图包括整树、单叶近景、掠视厚度和0/1.75秒风。已目检桦树reference/balanced整树，轮廓、层次与颜色无明显改变；量化像素差/边界法线与闭合拓扑测试并列。旧187792/82456/345972面数据现在对应reference，不再是默认balanced面数。

### 实际动态实例性能最终补验

`/Users/zyq/work/sea-work/verification/20261115-013756-plant-dynamic-instance-real-1-8-16-6ae784/report.json`：plant-performance **837/0、exit0、unexpected_errors=[]**，asset-import exit0。主线程核对测试源码与隔离快照逐字节相同。48张实拍，原546项保留，新增默认动态local_to_scene策略1/8/16棵测试；仅测试内存PackedScene，不计磁盘I/O。每实例真实WindRuntime _ready/_process/sample_at，无世界owner时同一fallback，不强制共享或统一apply_sample。

| 默认桦树动态实例 | reference帧p50/p95（ms） | balanced帧p50/p95（ms） | 两档实际draw calls |
|---|---:|---:|---:|
| 1棵 | 2.979 / 6.366 | 1.702 / 6.218 | 29 |
| 8棵 | 5.849 / 6.825 | 3.403 / 6.204 | 232 |
| 16棵 | 10.456 / 11.196 | 5.662 / 6.686 | 464 |

Godot4.7.2、Apple M6、Metal Forward+、1280×800、4×MSAA、无阴影、VSync off、无fixed-fps；每组至少2.2秒预热+2.2秒采样/90帧，两轮顺序反转。GPU读数全0，标未测不解释为零耗时；不代表Main/移动/Web。单树轻负载历史共享基准曾有回归与较大波动，因此不保证每次小场景FPS提升。默认动态实例Mesh/Material资源均为29×棵数，两档drawcall未降低；此轮核心收益是顶点数据/构建和较大负载帧耗时，不宣称完成实例共享或LOD。

最终本机热构建中位数（ms）：香樟571.209→250.132、槭266.814→130.962、桦1030.453→395.864；CPU解码数组字节37481216→19445504、16253088→8781216、69484368→33586896，不冒称显存。

### 本轮登记与全库检查收口

定点运行清单29项与当前字节SHA256全部一致（包含本轮源码、测试与runner；不发AssetID、不批量重签其他资源）。最终`check_feature_contracts.py --sync`退出码1、535 issues；正式check退出码1、536 issues，46功能/1073源资产/1542运行资源。两工坊没有条款集合或verification名称错误，仍有`store.gd`候选输出根`scenes/workshop_plants`被静态扫描当成缺资源，以及全库资产条款、断链、其他哈希和派生索引问题；不创建空目录消错。日志`outputs/workshop_tree_contracts_final_{sync,check}.log`。本轮所有相关Godot专项均通过，但不签全工程门禁。

交付对照预览：`outputs/house_tree_review_20261115/index.html`，原版/优化版三树种整树/近景/掠视和两风帧可切换，含四洞型、树屋/苔藓/UI证据及原始JSON；同名ZIP便于整体查看。主场景与project.godot无本轮diff，未提交推送。

## 2026-11-15 09:02 轻量树冠追加 · implemented / 验证pending

09:02用户要求大幅降低性能开销：少量立体叶团/邻近色体块，以及保留单叶观感的贴图叶卡两条新路线。image2生成后缩小的原要求遇权限失败；09:30用户明确授权image-2.6，追加记录时主线程实际模型`gpt-image-2.6-sunburst`仍在生成中。此处记录源码实施与待验边界，**工具完成不等于验收，既有1174/0、837/0等历史报告不覆盖本轮新模式**。

本节只对volumes/cards覆盖R04/R22的球团/平卡禁令，geometry和旧leaf_geometry三档的历史设计与证据保留。登记头status继续为implemented（已实现待完整验收），不能读成新图集、预算或性能已通过。

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R25 | implemented / Godot验证pending；recipe已包含foliage_mode三值、新建volumes、旧缺字段geometry，balanced/high/reference保留；generator提供三路线。 | 当前源码只读确认，不是运行报告；旧档不默换、显式切换/撤销/保存重载及旧几何回归须由主线程补验。 |
| SEA-PLANT-EDITOR-R26 | implemented（叶卡helper/shader代码）/ 图集生成接入与验证pending；lightweight_foliage.gd定义三树种+藤2×2分格，leaf_card.gdshader走alpha clip与mipmap采样。 | 512×512 RGBA运行目标为godot/assets/textures/vegetation/workshop_leaf_atlas_512.png；原始美术源及生成/缩小记录须保留art_source/plant_editor_leaf_atlas/v001。实际模型生成中，不登记为已交付图；真实alpha、导入mipmap、缩小后轮廓/渗色/单叶观感待验。 |
| SEA-PLANT-EDITOR-R27 | implemented / Godot验证pending；foliage_batch.gd按角色内材质合批，generator保留branch定位及bounds，新模式几何由lightweight_foliage.gd承接。 | 三树种volumes/cards完整默认树≤8 surfaces且≤12000 triangles仅为目标，包含默认附生与草；尚无本轮Godot计数，不写达标。合批数据、角色显隐、选枝高亮/聚焦、风权重与保存重载待验；surface不是实测draw call。 |
| SEA-PLANT-EDITOR-R28 | implemented（test_plant_canopy.gd专项代码与本账本入口登记）/ 真实运行和目检pending。 | 新增verification名plant-canopy；主线程须经统一runner真实后端补验volumes/cards各1/16/64棵及geometry1/16棵，无fixed-fps、VSync off。无本轮报告、帧耗时、draw calls或GPU有效数据，不引用旧结果冒充；geometry64棵未测，GPU无效须标未测。 |

### 本次文档补记的未签范围与交接

- 待主线程完成生成、缩小、运行贴图接入与原始源保留后，补真实Godot报告、同机位三树种整树/单叶近景/掠视/两风帧及人工目检；截图存在或测试文件存在不是通过。
- 性能须按实际默认动态实例策略与共享候选分列，记录wall-clock p50/p95、实际draw calls/primitives、设备及渲染设置，保留单树回归与波动；不以三角面或surface减少推算FPS，不将CPU数组字节冒称显存。
- Main/潜水接入、移动/Web、群树林LOD、GPU真实耗时、用户艺术终审及全工程门禁继续未签；本次不新增正式资产签署。
- 本次仅修改指定四份文档并补本登记头；未运行Godot、契约sync/check或其他检查，未改资产哈希、运行清单、代码或记忆。全局状态摘要/派生索引留主线程最终sync，保留并行潜水文档改动。

### 2026-11-15 09:52 主线程预检与贴图阻塞

- 本轮实际预检：`/Users/zyq/work/sea-work/verification/20261115-095012-canopy-kernel-preflight-800114/report.json`，plant-authoring **251/0**、plant-integration **540/0**、host-scene-guard **155/0**，三个退出码均0、unexpected_errors=[]，导入exit0。真实Metal后端运行的是逻辑/保存检查，没有新模式截图，也不是性能基准（本预检fixed-fps60）。旧实体几何fixture显式geometry以保留原断言。
- 审查修复：卡片按树种轮廓包络校准宽长，4面弯卡+2面平叶柄；补同半球法线和藤风通道一致；闭合体块改独立`leaf_volume.gdshader`背面剔除且无纹理采样/discard。合批默认树根风传播，不宣称与非合批逐枝风场等价。
- 用户已授权的`gpt-image-2.6-sunburst`实际返回`This token has no access to model gpt-image-2.6-sunburst`，生成退出1，无源图或运行图。未执行缩小、图集导入、plant-canopy、完整editor-plant及新模式性能/美术验收；不自动换模型，不制作占位图冒充。源码和待验测试保留，等待模型权限处理。
- 新shader尚需最终纳入定点清单与来源登记；当前源码预算仍仅推算，不签≤12000tri、实际drawcalls或FPS。
- 当前未完成状态运行契约同步/检查：分别547/548 issues、exit1；日志在`/Users/zyq/work/sea-work/plant_canopy_20261115/contracts_{sync,check}.log`。本轮源码待定点清单更新，不能引用上一轮535/536作当前结果，不批量刷新其他未知资源。

## 2026-11-15 10:20 混合树冠与图集生成成功 · 验证pending

本节按主线程最新交接追加：用户10:20提供游戏树冠截图，要求体块参照其饱满形状，并在外面添加叶片贴图。截图仅作风格/冠形参考，不裁切为素材。以下图集生成成功状态覆盖09:52的当前权限阻塞结论，失败过程与旧验收记录不删除。

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R29 | implemented / 新混合模式验证pending；volumes新增volume_leaf_cards整数0..16，新建默认12，旧缺字段0。内部24 triangles闭合低模簇+各向外壳叶卡，每卡4 triangles；0为纯体块。 | 旧volumes配方不静默加外壳，foliage_mode缺字段仍为geometry，leaf_geometry三档不变。纯单叶cards每叶4 triangles叶片+2 triangles平柄另计。默认混合7 surfaces、纯体块6 surfaces仅静态结构推算，不是Godot计数或draw calls；参数历史/保存兼容、饱满冠形、各向外缘、风动与预算待plant-canopy和目检确认。 |
| SEA-PLANT-EDITOR-R26 | 图集原图生成与512²运行图准备已完成；Godot导入效果与艺术验收pending。 | 用户更新临时授权凭据后，经明确授权的multipart字节上传，由gpt-image-2.6-sunburst成功生成；源图及两份记录见下。alpha clip 0.42、每格有效8..247像素、导入mipmaps与VRAM压缩已设置；配置存在不等于压缩后轮廓、透明边或渗色验收通过。 |
| SEA-PLANT-EDITOR-R27 | implemented / 混合完整树预算实测pending。 | ≤8 surfaces且≤12000 triangles仍是含默认附生与草的完整树目标；7/6 surfaces只为静态推算，不补成功数值，不把增加外壳后的面数当成已达标。branch ID/bounds、角色合批与数据/保存不变要求继续有效。 |
| SEA-PLANT-EDITOR-R28 | plant-canopy正由主线程串行运行 / 结果pending。 | 未收到本轮完成报告，不写checks通过数、实测帧耗时、draw calls或FPS。旧preflight 251/0、540/0、155/0仅旧几何与逻辑，不能作为混合外壳或性能证明；该预检fixed-fps60也不能代替无fixed-fps真实基准。 |

### 已生成素材与记录（主线程交接）

- 原图：`art_source/plant_editor_leaf_atlas/v001/image26_leaf_atlas_source.png`，1024×1024，1060810 bytes，保留原始输出，不由运行图覆盖。
- 运行图：`godot/assets/textures/vegetation/workshop_leaf_atlas_512.png`，512×512 RGBA，218744 bytes；2×2三树种+藤叶分格不变，每个256×256格内有效范围8..247像素。
- 同源目录的`generation.json`记录模型、提示词和来源，不含密钥；`preparation.json`记录缩小准备流程。本次不读取、记录或请求任何授权凭据/配置。
- 生成成功、缩小完成及导入配置就绪不是Godot新模式或艺术终审通过；待主线程补原始报告及真实图像目检。

### 仍待验与本次范围

性能继续按volumes/cards各1/16/64棵、geometry1/16棵真实后端运行，无fixed-fps，VSync off；共享候选与实际动态实例分列，GPU计时无效写未测。Main/潜水接入、移动/Web、群树林LOD、用户艺术终审和全工程门禁仍不签。本次仅四文档末尾追加，未运行Godot或检查，未改代码、运行清单、资产哈希、记忆或全局摘要；并行潜水内容保留，最终sync仍由主线程处理。

## 2026-11-15 r9最终专项证据与当前实施登记

本节以已读取的真实报告更新前述待验状态，保留历史失败与阶段结论；implemented不等于艺术终审、正式资产或全工程签署。

- **A · 完整树冠**：`/Users/zyq/work/sea-work/verification/20261115-115118-canopy-visible-delivery-r9-1575f8/report.json`及同批`project/outputs/plant_canopy/report.json`，plant-canopy **23253/0、exit0、import0、unexpected_errors=[]**，full_suite_passed=true、progress.complete=true。22轮全部完整、focused，无丢draw或watchdog超时。
- **B · 编辑器与必要内核**：`/Users/zyq/work/sea-work/verification/20261115-113213-canopy-editor-kernel-delivery-7fe9c2/report.json`，editor-plant **2271/0**、plant-authoring **260/0**、plant-integration **540/0**、host-scene-guard **155/0**，全部exit0、unexpected_errors=[]，import0。B为功能回归，不拿其fixed-fps60当性能证据。非法JSON负例已由JSON.parse_string改为JSON.new().parse，静默返回失败并保持回滚，未放宽非法输入门禁。

| 对应设计条款 | 当前实施状态 | 本次证据 / 边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R25 | implemented；三模式、新建默认与旧缺字段兼容、原三档、模式历史及保存重载已纳入最终回归。 | A+B；旧foliage_mode缺字段geometry，volume_leaf_cards缺字段0，不改旧revision。旧251/0预检不再充当新混合证据。 |
| SEA-PLANT-EDITOR-R26 | implemented；单叶/叶簇双512²图集、alpha clip、mipmap及实际BC7（BPTC）压缩/解码alpha已验证。 | A的textures/texture_decodes；原源与派生支持文件保留，正式来源/授权核验pending，未发AssetID，用户艺术终审未签。 |
| SEA-PLANT-EDITOR-R27 | implemented；角色合批、branch bounds与保存数据检查完成，完整默认树预算已由实际模型计数确认。 | A模型表：混合均7 surfaces，cards/pure均6；三树种均≤12000 triangles，含默认附生与草。实测draw calls另列，不由surface估算。 |
| SEA-PLANT-EDITOR-R28 | implemented；完整真实后端专项与22轮自然draw采样完成，失败轮未混入r9。 | A+B；动态磁盘旁车、各模式同展示成本，性能收益与尾部回归并存；GPU无效未测，geometry64未测，不签屏幕FPS或所有负载更快。 |
| SEA-PLANT-EDITOR-R29 | implemented；参考混合生产实现为0.65缩小全平滑内芯+每簇12张四三角叶簇卡，0为纯体块，cards为独立单叶。 | A的volume_cards含0/1/12/16参数检查，B覆盖编辑器闭环。每卡图像9叶不是9片几何；参考方向已制作，不代签用户艺术终审。 |

### 完整默认树实测预算

| 树种 | geometry balanced三角面 | 混合三角面 / 顶点 / surfaces | cards三角面 / surfaces | pure三角面 / surfaces |
|---|---:|---|---|---|
| 香樟 | 182992 | 7128 / 15304 / 7 | 6968 / 6 | 4728 / 6 |
| 鸡爪槭 | 79576 | 5510 / 11946 / 7 | 4918 / 6 | 3782 / 6 |
| 垂枝桦 | 311412 | 9688 / 20616 / 7 | 8664 / 6 | 6232 / 6 |

### 性能口径与必须保留的回归

Godot4.7.2、Apple M6、Metal Forward+、1280×800、4×MSAA、无阴影、VSync off、无fixed-fps。SubViewport纹理通过TextureRect显示在前台置顶宿主，各模式同成本；Store.save_animated真实磁盘动态旁车，不强制共享Mesh/Material，每实例真实风处理，稳定采样不含加载/实例化。两轮反序，每组至少2.2秒预热、2.2秒采样/90帧。以下为桦树**自然draw回调间隔**，不是GPU fence或屏幕呈现FPS。

| 实际动态规模 | 混合p50 / p95（ms） | geometry p50 / p95（ms） | 混合 / geometry实际draw calls |
|---|---:|---:|---:|
| 1棵 | 0.976 / 6.999 | 2.381 / 6.265 | 7 / 29 |
| 16棵 | 2.561 / 6.172 | 5.720 / 6.159 | 112 / 464 |
| 64棵 | 3.935 / 6.182 | 未测 | 448 / 未测 |

单树混合p95回归；16棵混合p95基本持平而非改善，cards/pure的p95为6.908/6.987ms，均比geometry6.159ms差。不能将p50收益扩大为所有负载更快，也不能倒算并签署屏幕FPS。GPU有效计时未取得，记未测；geometry64棵未测，不外推。报告中的吞吐或fps_measured字段不改变上述测量边界。

### 双图集、失败历史与交付交接

- 单叶`godot/assets/textures/vegetation/workshop_leaf_atlas_512.png`（512²，218744 bytes）；叶簇同目录`workshop_leaf_clusters_512.png`（512²，301592 bytes）。`art_source/plant_editor_leaf_atlas/v001`保留原图、generation.json、preparation.json、clusters_preparation.json及prepare_clusters.py等支持源；生成/上传已获用户操作授权，正式来源/授权核验仍pending、未发AssetID，不记录密钥。
- 失败历史按阶段保留：r1 generator局部重复size导致parse exit1；r2中断且已有压缩alpha失败；r3旧外观审查不合格、性能长帧中断；r4 visual-only 259/0、54图，不是完整验收；r5测试gpu_valid类型parse exit1；r6虽完整23253/0，但比例整数除法显示0及progress.complete标记有误，后续已修；r7/r8停绘watchdog exit1，样本不混用；r9通过可见前台宿主解决停绘采样问题。
- 交付路径仅登记：`outputs/plant_canopy_review_20261115/index.html`、`outputs/plant_canopy_review_20261115/contact_sheet.png`、`outputs/plant_canopy_review_20261115.zip`；主线程当前生成中，不宣称包已完成。
- 未签：用户艺术终审、Main/潜水接入、Web/mobile、LOD、GPU有效耗时及全工程门禁。全库最终sync/check由主线程另做，旧547/548为历史而非最新最终结果。本次只读报告并追加四文档，未跑检查或修改代码、运行清单、资产哈希、记忆、全局摘要；并行潜水改动保留。

### 主线程最终收口

- 当前r9报告所登记源码与主工作区逐文件SHA核对无差异，两份import已同步真实引擎生成的BPTC/UID/channel字段。运行清单本轮20项（含两PNG/import）一致，仅字节登记不发生产AssetID；源图/生成及派生脚本按功能账本留source pending，正式商用条款待核验。
- 最新全库sync/check分别 **535/536 issues、exit1**（46功能、1073源资产、1551运行资源），日志`/Users/zyq/work/sea-work/plant_canopy_20261115/final_contracts_{sync,check}.log`。未掩盖其他资产/哈希/断链与store候选保存根静态扫描问题，不签全工程通过。
- 最终交付HTML、三树拼图与ZIP已组装：`outputs/plant_canopy_review_20261115/index.html`、同目录`contact_sheet.png`、`outputs/plant_canopy_review_20261115.zip`（页内另含同名ZIP）。当前页面与数据均取r9，明确r4视觉辅助，含209张PNG及5份JSON；链接与ZIP完整性已检查，浏览器交互未自动验收。
- `git diff --check`退出0，Main及project.godot无本轮diff；未提交、未推送，不影响并行潜水改动。
