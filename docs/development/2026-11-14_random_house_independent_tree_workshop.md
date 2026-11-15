# 2026-11-14 随机房屋与独立树木工坊

## 用户要求与交付边界

新增一键随机房屋；恢复完成暂停的树工坊，树制作独立于房屋。先完成制作/保存/导出，之后再考虑嵌入与潜水模型。本轮不打开或改写Main，不修改用户摆位，不把树候选自动登记成正式世界资产。

## 现在的入口

- 房屋：编辑器顶部“老王场景工坊” → “随机房屋”。当前有未保存修改/滑条输入先确认；成功后可撤销，失败或取消原样保持；状态显示本次seed。
- 树木：编辑器顶部独立“树木工坊”（project.godot已启用）。三物种按钮香樟、鸡爪槭、垂枝桦；左参数模块为树形、枝条、叶片、附生、配色、文件，模块单行位于预览上方。
- 树木全部数值HSlider，160ms调度、同拖拽一撤销；seed重抽/随机幅度/开关；单枝选择、高亮、长度/粗度/角度/显隐，所属叶跟随。
- 树配色64格可手动/自动，颜色使用公共PaletteUV；树干/曲面叶/苔藤四本地材质实例，不改建筑四材质。草复用现有几何，UV2只保既有草alpha轮廓，颜色仍来自共享色板。
- 拖动旋转、滚轮缩放、正面/俯视/透视/适配；本地风只在可见树主屏累计时间，隐藏暂停，不写vegetation_*全局。
- 树文件页填写名称并保存；输出recipe/TSCN/manifest，新增revision不覆盖旧版。两个候选根可用：res://outputs/plant_editor、res://scenes/workshop_plants；第二个仍是候选，不是“已正式接入”。

## 核心改动

- 房屋：src/workshop/random_recipe.gd、test_workshop_random.gd、editor_screen/upgrade_verification随机按钮与事务。
- 树：src/plant_authoring六个草稿全面补实，新增leaf.gdshader；addons/plant_editor独立plugin/screen/preview/verification。
- Session唯一状态写入，候选真实生成一次后提交并直接用于preview，不重复probe生成；undo/redo和草稿有稳定指纹。
- JSON指纹1e-9十进制规范处理7.2+0.4浮点尾数，0.001实际尺寸变化仍识别；存储逐节点顶点/索引/法线/UV/UV2/实例/材质外链比较，不以计数代替。
- Store独占tmp、重载验收后原子提交，旧revision immutable，静态导出剔除脚本/相机/灯光/碰撞、风时间归零；草稿先写tmp再提交。
- 各branch/twig/leaf/附生随机流独立；关某枝不重抽其他枝，叶密度不改木枝。
- 树几何并非球团：香樟椭圆全缘叶/宽圆冠，槭树掌裂叶/层状横伸，垂枝桦三角锯齿叶/下垂细枝。叶肉双表面有厚度、曲面采样/法线混合。

## 当前实际验证

| 验证 | 结果 | 工程外report目录 |
|---|---|---|
| 房屋20种seed实际生成矩阵 | 969/0、exit0 | 20261114-025229-random-house-final-reviewed-8e6bf1 |
| 房屋真实编辑器回归 | 955/0、exit0 | 同上 |
| 树内核、流隔离、UV/材质、两版保存及篡改负例 | 210/0、exit0 | 20261114-030657-tree-core-optimized-final-59c0fc |
| 独立树真实双插件、64色、分枝、失败事务、本地风、UI及三样例 | 263/0、exit0 | 20261114-030705-independent-tree-complete-final-251c8a |

各目录在 `/Users/zyq/work/sea-work/verification/`，outer均passed=true/unexpected_errors=[]；树批asset-import exit0。

房屋matrix是headless；树内核用真实Metal以保留MultiMesh数据但不产图，不能冒充视觉验收。两个editor专项实际Metal渲染，树输出整树/裸枝/叶近景/附生近景/64色/860×600/完整Editor截图；主线程已逐图目检。黄色盒是编辑选枝高亮，不会导出。

## 当前体量与未签边界

样例已在最终tree editor批 `project/outputs/plant_editor/example-{camphor,maple,birch}/revision_0001/` 实际保存重载：

- 香樟：187792三角、608叶、TSCN约25.2MB。
- 鸡爪槭：82456三角、368叶、TSCN约11.0MB。
- 垂枝桦：345972三角、728叶、TSCN约49.2MB。

本次是独立制作端和风格化幼树作者模型，不是群树林低模LOD交付。起初样例约50–97MB且导出使编辑器专项360秒超时；减少冗余叶细分后当前含3样例的完整编辑器专项约140秒完成，未牺牲物种轮廓/曲面/UV门禁。仍需后续按场景预算做LOD/实例化及用户艺术终审。

中间遇到类型警告、隔离资源缺失、Dummy后端MultiMesh不保变换、浮点指纹、首次房屋预览基线以及草卡不透明方块，均保留原失败报告、修复后实跑，不抹成PASS。未执行跨OS进程重启、复杂宿主嵌入、碰撞导航、Main/潜水模型、全群树林移动/Web性能和用户美术终审。

## 本地交付

最终图与报告汇集在 `/Users/zyq/work/sea-work/outputs/house_tree_workshops_final/`。`three_tree_candidate_scenes.zip` 约23.3MB，含三树种候选配方/TSCN/manifest以及按原res路径排列的shader、公共色板与既有草alpha图；这是跨项目查看用候选包，不应拿它覆盖当前工程同路径已有共享资源。当前sea已具备shader/贴图，使用本工程树工坊物种按钮新建并保存即可，不需要解包才能使用。

## 记录

规范：SEA-WORKSHOP-R82–R83、SEA-PLANT-EDITOR-R10–R13；plant ledger状态由planned改为implemented（已实现待完整验收），主导航同步。只登记本轮明确改动的运行文件哈希；其他并行改动/历史漂移不批量刷新。全库契约实际结果追加于两功能账本，不以专项通过代签全库。

## 2026-11-15 继续深化：保色随机、真实破洞、树屋与风动

此节覆盖前文“尚未宿主结合”的历史状态，不删除原证据。

- 随机房屋保留当前palette/shading/aging/组件及各层窗配色，不再随机颜色；四平面/门窗形态联动独立随机。
- 房屋破旧页“结构大洞”提供椭圆、不规则、拱形、豁口及四立面；真实布尔差集/封边/碰撞、交叠门窗整套移除。当前仅墙柱腰线，屋顶/楼板保护。
- 树工坊树形页可编辑2–8米制路径控制点、只读载入已保存building.tscn、按洞口建议路径并检查粗干。完整窗玻璃不允许穿过；根贴真实楼板。所有结合不改变宿主、不自动Main接入，枝叶全部碰撞不在粗干检查范围。
- 文件页可保存静态树，或额外生成只有风runtime的动态旁车，再导出attachment相对引用。配方/宿主坐标成对历史，失败保留输入，recovery先预检再提交，植物保存与结合保存分别清dirty。
- 风只读唯一世界owner、无owner本地fallback，复用游戏传播公式；树干/苔藓固定、叶尖和藤下端动，公共资源不改。
- 路径精度、宿主支撑面/实体内部、预加载脚本闭包、Godot Material外链、相对路径API、编辑器显式采样和无process截图等待等实际失败均已修复并保留历史。

### 叶片性能：优先保持风格和效果

用户补充单片叶的性能担忧。实际已有每主枝Foliage合批，不是每叶节点；默认香樟/槭/桦仅25/23/29个Mesh surface。新增三档入口“树木工坊 → 叶片 → 叶片几何”：

- **balanced（默认）**：索引复用、保守内部曲率简化，保所有叶缘采样、真实厚度与原叶数。
- **high**：保留原面数，仅复用顶点。
- **reference**：原版重复顶点，对照用。

| 树种 | 原版→balanced顶点 | 原版→balanced三角面 | 叶数 |
|---|---:|---:|---:|
| 香樟 | 492736→243040（-50.7%） | 187792→182992 | 608，不变 |
| 鸡爪槭 | 214680→111384（-48.1%） | 82456→79576 | 368，不变 |
| 垂枝桦 | 912108→419292（-54.0%） | 345972→311412 | 728，不变 |

不降密度、不改seed、色格、轮廓、厚度和杯曲；显式COLOR避免重排顶点后风权重失效。三树种同机位整树/近叶/掠视、静止/风动共36图，逐点轮廓/UV/解析法线及曲面误差验收。CPU数组字节约减半；这不是显存测量。

### 当前可靠报告

所有目录位于`/Users/zyq/work/sea-work/verification/`：

- `20261115-012739-workshop-tree-kernel-delivery-d20b88/report.json`：plant-authoring233/0、plant-integration540/0、host-scene-guard155/0、workshop-random17831/0、workshop-damage1576/0；均exit0。真实Metal逻辑检查，不产图。
- `20261114-235736-house-damage-readable-final-a3f2a3/report.json`：房屋editor991/0、exit0；四轮廓改无遮挡侧立面真实近景，已逐张目检，不以远景遮挡图充数。
- `20261115-011859-tree-leaf-editor-final-2527aa/report.json`：树editor1174/0、exit0、无意外错误；包含三档叶几何UI/实际统计/撤销保存、宿主/风/恢复/紧凑面积全流程，源码快照与当前一致。没有15 ObjectDB泄漏警告，仍有1 unclaimed StringName提示，不签零警告。
- `20261115-012810-leaf-fidelity-performance-delivery-d806c6/report.json`：叶保真+共享候选规模专项546/0、exit0。共享候选刻意关闭local_to_scene并整场更新风材质，不等于Store默认逐实例策略；默认动态策略性能另测、不得拿共享候选FPS冒充实际导出收益。

### 仍未签与使用限制

用户艺术终审、群树林LOD、Main/移动/Web性能、真实GPU计时和跨进程OS重启恢复仍未签。苔藓贴合与参数有效，但近景为明显多边形贴片风格，不称自然苔藓融合完成。局部几何与工坊验收通过不代表全库契约通过；登记与最终检查追加在账本。本轮未改用户Main摆位，未提交推送。

### 默认动态实例最终性能（非共享候选）

`20261115-013756-plant-dynamic-instance-real-1-8-16-6ae784/report.json`：837/0、exit0，48张真实图。保持每实例local_to_scene与真实WindRuntime处理，未强制共享。默认桦树1/8/16棵reference→balanced帧p50为2.979→1.702、5.849→3.403、10.456→5.662ms；p95为6.366→6.218、6.825→6.204、11.196→6.686ms。draw calls仍29/232/464；不声称减批次。Apple M6/Metal、1280×800、4×MSAA、无阴影、无fixed-fps和VSync；两轮反序、至少2.2秒预热与采样，不代表Main/移动/Web，GPU返回0所以未测。早期共享单树曾回归，轻负载不保证稳定提升；没有隐藏该历史结果。

### 最终交付与全库边界

预览：`outputs/house_tree_review_20261115/index.html`；配套ZIP `outputs/house_tree_review_20261115.zip`约3.7MB，包含47张交付图、4份原始报告和可切换A/B页面。运行数据保存在工程外验证目录，不把页面图表当引擎性能原始证据。

29项明确改动的运行源码登记SHA与当前一致，未批量刷新未知资源。最终全库sync/check实际exit1、535/536 issues（46功能/1073源资产/1542运行资源）；无两工坊条款集合错误，但候选输出根scenes/workshop_plants被扫描为缺资源，及其他断链/哈希/资产条款/派生索引仍未清。日志`outputs/workshop_tree_contracts_final_{sync,check}.log`；主场景与project.godot未被本轮编辑器改写，diff-check exit0。

## 2026-11-15 09:02 轻量树冠新方向与09:30生成授权（待验证）

### 用户指令与历史边界

- 09:02要求大幅降低性能开销，不再仅做厚叶内部采样优化：提供少量立体叶团、邻近色体块模式，同时保留单叶可辨的观感路线，将单叶转换为贴图。
- 最初指定image2生成后缩小；image2权限失败。09:30用户明确授权image-2.6，追加记录时主线程实际模型为`gpt-image-2.6-sunburst`，仍在生成中；不记成image2成功，不把工具完成当成Godot或艺术验收。
- 追加SEA-PLANT-EDITOR-R25–R28，仅对新volumes/cards覆盖旧R04/R22禁止球团/平卡的限制。前文保真几何优化、叶肉厚度、三档数据和已通过报告作为历史保留，不追溯改写，也不拿旧报告签新模式。

### 配方、图集与合批约定

| 项目 | 本次约定 |
|---|---|
| 模式 | foliage_mode只允许volumes/cards/geometry；新建volumes，旧配方缺字段按geometry，不默换旧外观。leaf_geometry的balanced/high/reference和旧缺字段默认balanced保留，切换新模式不丢该值。 |
| 外观 | volumes以少量立体叶团和邻近色块表达树冠；cards以贴图叶卡保留单叶轮廓。两者不宣称与旧厚叶几何逐像素相同，仍须三树种冠形、配色和风动目检。 |
| 图集 | 512×512 RGBA，2×2左上香樟、右上鸡爪槭、左下垂枝桦、右下藤叶；真实alpha留白，alpha clip而非透明混合，导入和采样均启用mipmap。UV2读轮廓/细节，主色继续走公共PaletteUV。 |
| 源与运行图 | 原始生成输出及生成/缩小处理记录保留art_source/plant_editor_leaf_atlas/v001；缩小图不覆盖原源。运行候选godot/assets/textures/vegetation/workshop_leaf_atlas_512.png的落盘、导入和效果仍待主线程确认。 |
| 合批 | 内核按显示角色与兼容材质合批，保留branch ID、定位节点与根局部bounds，供选枝、高亮、聚焦和宿主定位；不破坏角色显隐、UV/UV2/COLOR、风权重或保存重载。 |
| 预算 | 三树种volumes/cards完整默认树各≤8 surfaces且≤12000 triangles，保留默认树皮/苔/藤/草；geometry不强套预算。这是待Godot计数的目标，不是当前实测结果；surface不等于draw call，逻辑叶数不等于叶团数。 |

### 当前实施记录与后续验证交接

源码侧已有`lightweight_foliage.gd`、`foliage_batch.gd`、`leaf_card.gdshader`与`test_plant_canopy.gd`；recipe/generator包含模式兼容和branch bounds。功能账本登记头补入这四条code_paths和verification名`plant-canopy`，状态为**implemented / 验证pending**：这里只读确认实施入口，不宣称本轮Godot运行、完整UI闭环、图集交付或预算通过。

后续由主线程通过统一runner完成：

1. 旧缺字段geometry、三档保留、显式模式切换、撤销/重做、静动态保存重载及旧工坊回归；合批前后真实数据与branch bounds/角色显隐/选枝定位对照。
2. 生成原源保留、512²真实RGBA/分格/mipmap导入、透明边与渗色检查；三树种同seed同机位整树、单叶近景、掠视及两风帧，图像目检与测试断言分列。
3. 真实渲染性能：volumes/cards各1/16/64棵，geometry仅1/16棵；禁止fixed-fps，VSync off，默认动态实例与共享候选分别说明。记录设备、后端、分辨率、抗锯齿、阴影、预热与采样窗口、wall-clock p50/p95、实际draw calls/primitives、构建耗时及CPU数组字节；保留回归/波动，不由减面率推FPS。geometry64棵未测；GPU读数无效必须写未测，不写零耗时。

本轮尚无新模式Godot报告或真实多树性能数据，工具完成、源码完成、截图存在均不等于验收。Main、潜水接入、移动/Web、群树林LOD、GPU有效计时、用户艺术终审与全工程门禁仍不签。

### 本次文档编辑范围

仅追加GDD、plant_editor spec/ledger和本记录，并补ledger登记头；历史章节、报告与并行潜水文档改动保留。按本次指令未运行检查或Godot，未改代码、资产哈希、运行清单或记忆；全局摘要和派生索引由主线程最终sync，本次没有新的sync/check通过结论。

## 2026-11-15 10:20 饱满体块与贴图叶卡混合外壳（最新交接，待验）

### 参考图与兼容参数

用户10:20提供游戏树冠截图，明确体块也要参照其饱满形状，外面加叶片贴图。截图仅作风格、冠形和层次参考，不裁切成纹理。新增稳定条款SEA-PLANT-EDITOR-R29并由功能账本承接，不改写R25–R28及旧geometry的历史设计或证据。

- volumes新增`volume_leaf_cards`整数0..16，新建默认12，旧配方缺字段0；0保留纯体块，旧volumes不默加外壳。`foliage_mode`缺字段仍按geometry，原`leaf_geometry`三档保留。
- 混合结构为内部24 triangles闭合低模簇，加各向外壳叶卡，每卡4 triangles；不能只面向单一截图机位。纯单叶cards另为每叶4 triangles叶片+2 triangles平柄，两者成本分别记录。
- 参数需沿用Session预览、撤销重做、保存重载与失败保留机制；branch ID/bounds、角色合批、风权重和局部资源隔离仍需回归。
- 新默认混合7 surfaces、纯体块6 surfaces目前**仅静态结构推算待测**，不是Godot实测或实际draw calls。完整默认树≤8 surfaces、≤12000 triangles仍为目标，包含默认附生与草，不签预算达标。

### image-2.6生成成功与原源保留

按主线程交接，用户更新临时授权凭据后，经用户明确授权的multipart字节上传，实际模型`gpt-image-2.6-sunburst`已成功生成。此状态覆盖此前“生成中/权限阻塞”的当前结论，历史失败不删除、不改写为成功。本次不记录密钥、不读取或请求授权配置。

| 产物 | 位置与当前信息 |
|---|---|
| 原始美术源 | art_source/plant_editor_leaf_atlas/v001/image26_leaf_atlas_source.png；1024×1024，1060810 bytes，保留原始输出。 |
| 生成记录 | art_source/plant_editor_leaf_atlas/v001/generation.json；包含模型、提示词、来源，不含密钥。 |
| 缩小准备记录 | art_source/plant_editor_leaf_atlas/v001/preparation.json；记录原源至运行图的准备流程。 |
| 运行图集 | godot/assets/textures/vegetation/workshop_leaf_atlas_512.png；512×512 RGBA，218744 bytes，2×2三树种+藤叶。 |

当前alpha clip阈值0.42，每个256×256格内有效像素8..247，导入设置启用mipmaps与VRAM压缩。生成/缩小完成和导入配置就绪不等于Godot压缩后透明边、格间渗色、外壳各向效果或用户艺术终审通过。

### 验证进度与未签边界

实际plant-canopy正由主线程串行运行，仍待完成报告，不在本次追加中写成功数字。旧内核preflight为plant-authoring251/0、plant-integration540/0、host-scene-guard155/0，仅覆盖旧几何与逻辑检查；其fixed-fps60预检不能证明新混合树冠、完整树预算或真实性能。

后续仍需三树种整树/单叶近景/掠视/两风帧和人工目检，volumes/cards各1/16/64棵、geometry1/16棵真实后端基准；无fixed-fps、VSync off，实测wall-clock p50/p95和draw calls/primitives，实际动态实例与共享候选分列，GPU无有效计时记未测。Main/潜水接入、移动/Web、群树林LOD、用户艺术终审及全工程门禁保持未签。

本次仅四份文档末尾追加，不改登记头或历史正文，不跑检查/Godot，不修改代码、运行清单、资产哈希或记忆。保留并行潜水改动，全局摘要/派生索引仍留主线程最终sync。

## 2026-11-15 r9完整交付专项与最终文档交接

本节更新前述“运行中/预算推算”当前状态，不删除历史。参考混合已完成生产实现：24 triangles闭合内芯按0.65缩小并全平滑，每簇12张各向四三角叶簇卡，每卡图像9叶而非9片几何；volume_leaf_cards=0为纯体块，cards仍为独立单叶。单叶/叶簇运行图均512²，分别218744/301592 bytes；原源目录保留clusters_preparation.json、prepare_clusters.py及原生成/缩小记录，截图只参考、不裁素材。shader alpha clip+mipmap与真实BC7（BPTC）压缩已验证；用户生成/上传操作授权不等于正式资产来源/授权核验，后者仍pending，未发AssetID。

### 已核对的最终报告

- 完整专项：`/Users/zyq/work/sea-work/verification/20261115-115118-canopy-visible-delivery-r9-1575f8/report.json`及同批`project/outputs/plant_canopy/report.json`：**23253/0、exit0、import0、unexpected_errors=[]**，完整完成标记为true；22轮无丢draw/超时，全部focused。
- 编辑器/必要内核：`/Users/zyq/work/sea-work/verification/20261115-113213-canopy-editor-kernel-delivery-7fe9c2/report.json`：**editor2271/0、authoring260/0、integration540/0、guard155/0**，全部exit0、无unexpected，import0。非法JSON负例改用JSON.new().parse静默返回失败并保回滚；该功能批fixed-fps60不作性能证明。
- R25–R29逐条当前implemented及证据已追加至[功能账本](../features/plant_editor/ledger.md)。香樟/槭/桦混合三角面7128/5510/9688、顶点15304/11946/20616，均7 surfaces；cards三角面6968/4918/8664、pure4728/3782/6232，均6 surfaces。geometry balanced对照182992/79576/311412面。完整默认树含附生/草，已实测达到≤8 surfaces、≤12000 triangles预算。

### 性能只签实际测量范围

Godot4.7.2、M6、Metal Forward+、1280×800、4×MSAA、无阴影、VSync off、无fixed-fps；动态磁盘旁车逐实例资源与风处理，真实SubViewport经TextureRect显示于前台置顶宿主，各模式同成本。采的是自然draw回调间隔，不是GPU fence完成时间或屏幕呈现FPS；两轮反序、每组至少2.2秒预热/2.2秒采样及90帧，加载/实例化不计稳定帧。

桦树16棵混合p50/p95为2.561/6.172ms，对照geometry5.720/6.159ms，实际draw calls112/464；64棵混合3.935/6.182ms、draw448，geometry64未测。单树混合p95为6.999ms，对照6.265ms有回归；16棵混合p95基本持平，cards/pure尾部6.908/6.987ms也回归。不能写“所有负载更快”或屏幕FPS提升，GPU计时无效明确未测。全部采样与模型数据保留在原始报告，不在此复制长表。

### 失败过程保留

r1 generator局部重复size解析失败exit1；r2中断且已有压缩alpha失败；r3旧外观已审不合格、长帧性能中断；r4仅visual-only259/0及54图，不是完整结果；r5测试gpu_valid类型解析失败exit1；r6完整23253/0但比例整数除法显示0及progress.complete标记错误，已修；r7/r8停绘watchdog exit1，失败样本不混入r9；r9通过可见前台宿主解决采样停绘问题。不能因最终通过删除中间失败或把r4当完整签署。

### 交付与未签事项

交付仅登记路径：`outputs/plant_canopy_review_20261115/index.html`、`outputs/plant_canopy_review_20261115/contact_sheet.png`及`outputs/plant_canopy_review_20261115.zip`，主线程当前生成中，不称已完成。艺术终审、Main/潜水接入、Web/mobile、LOD、GPU有效计时及全工程门禁未签；自动截图/像素断言不代替用户艺术认可。

最终全库sync/check由主线程执行，旧547/548不是本次最新最终结果，不写全库完成。本次仅追加四文档并只读核对报告，未运行检查、不改代码/清单/哈希/记忆或全局摘要，保留并行潜水文档改动。
