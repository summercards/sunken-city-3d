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

## 2026-11-15 晚至11-16 房屋参考默认、冲突确认与配色导航（最终验证pending）

本节只追加本轮房屋工坊，不新建重复开发文档、不改上方树冠与其他历史。已加载sea-contract-ledgers，先读取GDD导航、workshop spec/ledger、相关源码与最近报告，并确认SEA-WORKSHOP-R89–R91未占用后登记。本轮条目状态统一 **`implemented_pending_current_verification`**；主线程仍在最终editor验证，不能拿初1349/0假签当前全部通过。

### 11/15晚用户要求与新建默认

用户“杨光放”按项目阳光房 `solar_cabin` 理解：只让新建初始值和配色参考它，不复制原模型、不把门窗外包当净洞，也不改原阳光房资源。

| 项目 | 本轮约定 |
|---|---|
| 生效入口 | 仅 `Recipe.authoring_defaults()`；旧 `Recipe.defaults()`、缺字段旧档、已保存配方与历史revision保持，不自动迁移。 |
| 建筑尺度 | 层高5.1m、板厚0.2m、净高4.9m、主柱宽0.5m；pilaster宽0.5m仅为粗细近似，不同于原型主柱构造，不签承载。 |
| 净洞 | 保留窗1.5×1.9m、窗台0.95m、门1.6×2.4m；原型门窗外包不是净洞尺寸。 |
| 配色 | palette.slots manual：white `[0,4]`→wall/pillar/band，wood `[1,1]`→slab/roof，teal `[2,3]`→frame，sky `[2,1]`→glass；零基row/column。 |
| 共享资源 | shading空覆盖继承正式四材质，不改公共.tres、shader或色板PNG，不复制材质；clean与其他既有新建功能保留。 |
| 形体合法性 | structure.min=0.030/max=0.059，保原seed与8°；默认12×9m、5.1m单层在原边界合法。0.060略超该单层约0.0597倾角界限，只调整新建常量，不按楼层静默clamp、不改validator容差，其他体量仍严格拒绝。 |

对应SEA-WORKSHOP-R89；源码职责为 `godot/src/workshop/recipe.gd`。旧defaults固定fingerprint回归与新建真实生成由新增专项承接，源码存在不等于最终editor验收。

### 少量数值方案与显式确认事务

对应SEA-WORKSHOP-R90：`godot/src/workshop/generation_adjustment.gd` 提供只读 `evaluate/propose`，先完整 `Recipe.validate` 和真实 `Generator.build` 验证，再给通过同样完整验证的建议；不写Session或修改传入candidate/catalog。最多3个独立参数、共6个数值，alias/derived仍逐项计数披露完整path、中文参数、原→新、单位、原因与kind，不靠隐藏镜像/派生字段冒充“只改一个”。

UI从最后成功snapshot建立候选，仅收basic白名单 `width/depth/floors/floor_height/slab_thickness/wall_thickness/column_width/bay_width/door_width/door_height/bevel_width` 与actual failed/pending窗字段，按global/floor/facade/single真实scope承载。无关roof/identity/plant/组件/plan/形体/配色/柱腰线等保输入和baseline不提交；不能安全分离的无关排队/局部输入或未排队窗差异明确拒绝并点名，不能用旧baseline掩盖与Session的差异。

独立modal双明细：第一块“Session原值→用户输入”披露本次一并提交的白名单，第二块“输入→建议”披露helper修复；两块可滚动/选择，默认取消。提出建议不flush/提交，停止timer；取消、配方/目录/UI输入/scope/token变化导致过期、确认真实生成失败均保原模型/root、配方、历史及输入，不重启timer、不自动重试。用户明确确认后只调用一次真实 `Session.preview_candidate`，同一构建直接给预览，单history，undo回原楼与失败/排队输入，redo及分支历史也要严格隔离。helper验证探针与确认生成分域，不称整条流程只生成一次。

静态保存仍走严格校验/生成失败，不触发auto修复或异步保存；不可解prefab/拓扑、未知输入及超3参数/6数值拒绝，不缩净窗、不关柱/窗/功能、不清覆盖、不换模板。需要拓扑变化且已有单窗ordinal时不重绑定ID。当前UI/历史收紧已在 `editor_screen.gd` 与 `upgrade_verification.gd` 增加实现/断言，但本次未执行，不称最终通过。

### 13目标按钮与不降低面积门禁

对应SEA-WORKSHOP-R91：全部、墙、柱、腰线、框、玻璃、植物、楼板、屋顶、Matte/Metal/Gloss/Emission共13目标，横滚单行+左右箭头+高亮/自动滚入，按钮≥40px高、18px字。main nav正下第二行仅在配色页显示，替换 `views_scroll` 的同一行，不再额外增加常驻行；其他页隐藏目标行、恢复视图行。切目标只切上下文，不更改颜色/生成。

R79–R81真实Control面积验收不变：1280×800、1000×700、860×600的模型预览宽≥52%、高≥60%，16/18px字号保留。最终布局须读实际矩形及父链，不用节点存在、截图非空或缩字号代替，也不拿旧中间版数值覆盖当前结果。

### 两层CSG几何根因与严格回归

新尺度原始两层的实际union实体边界失败来自各part局部居中及CSG分别变换，使原本同一水平接面产生不同world Y浮点平面，不是通过关功能或按层数压小参数即可正确解决。`godot/src/workshop/shell_union_geometry.gd` 的 `_boolean_mesh`在入CSG前bake世界坐标，仅Y统一到既有 `WELD=0.00001m`，XZ不预量化，保留收分窄斜面；audit/validator阈值和既有后处理都不放宽，不以后删面或加容差伪造闭合。

新增 `godot/tests/test_workshop_adjustment.gd` / runner名 `workshop-adjustment`：原始1/2/3层×form开/关、两层柱/腰线四组合与6.8m大窗、manual palette+植被+窗沿关闭、旧L五层、空palette继承、真实Session两层联合修复和静态重载；实际faces的闭合/定向/单连通/nonmanifold与内实外空边界各自校核。这里仅记录已读源码与报告，本次未改production/tests或运行引擎。

### 本次已核对报告与失败保留

全部目录根为 `/Users/zyq/work/sea-work/verification/`，原始外层为各目录 `report.json`。

| 批次 | 结果与证据 | 当前解释 |
|---|---|---|
| `20261115-233320-workshop-humanized-r1-026f4f` | 初editor **1349/0**，exit0、passed=true、completion_marker=true、unexpected_errors=[]，real renderer/import0；内层 `project/outputs/workshop_upgrade_report.json`，日志 `editor-workshop-upgrade.log` | **中间版**。后续审查收紧无关UI/历史及两层几何，最终尚未验；不是当前最终PASS。fixed-fps60只作功能/渲染，不作性能。 |
| `20261116-002844-workshop-adjustment-y-grid-final-34376a` | workshop-adjustment **357/0**，exit0、passed=true、completion_marker=true、unexpected_errors=[]；内层 `project/outputs/workshop_adjustment_report.json` | headless真实几何/静态专项，visual明确未执行。同批shell失败，因此不写整个批次全绿。 |
| 同上旧shell | `workshop-shell.log` **18077 checks / 25 failures**，外层exit1、passed=false、completion_marker=false | 旧auto/weathering fixture假设与新manual slots冲突，colour_errors与四档墙UV互异失败保留；fixture正在维护，未复跑签署，不列为可忽略预期红项。 |
| `20261116-003223-workshop-adjustment-y-grid-union-ab520f` | union **16组合、6291/0**，exit0、passed=true、completion_marker=true、unexpected_errors=[]；内层 `project/outputs/workshop_union_report.json` | headless真实网格、碰撞、静态序列化；不是64全矩阵，不是渲染/性能或完整editor证明。 |

两层实际几何失败、旧shell25失败与中间版通过均如实分列，不抹历史、不拿局部绿签整批。最终editor仍由主线程运行完成后追加报告、退出码、真实截图及审阅结论；本节不猜路径/数字，不因源码测试存在而签通过。白名单/双明细、取消过期失败、精确UI/baseline恢复、历史分支与单次提交、静态保存拒绝、三档面积仍须最终当前证据。

### 本次文档范围与交接

只改四份既有文档：`GDD_V1.0.md`、`docs/features/workshop/{spec,ledger}.md`、本开发记录；GDD末尾追加不动功能同步摘要，ledger仅补登记头两条code_paths与verification并追加R89–R91承接。登记头继续partial，条目 `implemented_pending_current_verification`。本次不运行sync/check、Godot或runner，不改production/tests/registry/memory、清单/hash、用户Main摆位，不commit/push；并行实现/测试改动原样保留，主线程统一最终验证与同步。用户艺术终审、性能、任意prefab/所有8层组合、正式Main/潜水接入及全工程门禁继续未签，旧全库数字不充作本轮结果。

## 2026-11-16 最终当前证据回填：默认与人性化交互范围内已验

本节更新前节“最终待验”的当前结论，前节pending、中间版1349/0、几何失败、旧shell25失败均保留历史，不篡改成通过。**SEA-WORKSHOP-R89/R90/R91逐条当前状态为 `implemented_verified_in_scope`**，功能全局partial与GDD同步摘要不变；不签艺术终审、性能、正式Main接入或全库通过。

### 最终UI与快照一致性

报告 `/Users/zyq/work/sea-work/verification/20261116-015027-workshop-humanized-final-0b50f8/report.json` 及inner `project/outputs/workshop_upgrade_report.json`：**1453/0、editor exit0、passed=true、completion_marker=true、unexpected_errors=[]、import0**。只读字节比较当前editor_screen、upgrade_verification、recipe、generation_adjustment、shell_union_geometry与该隔离snapshot均一致，不拿初中间版代签。

- R89：阳光房仅新建尺度/配色、旧defaults及净洞保持、manual slots真实UV与公共shading继承；结构形体上限0.059不按层静默clamp。CSG输入先bake世界坐标，仅Y统一到既有 **WELD=0.00001m**，XZ不预量化，audit/validator阈值及后处理未放宽。
- R90：完整只读Recipe+Generator建议、≤3独立参数/≤6数值含alias/derived披露、basic+actualfailed/pendingwindow候选、两块明细、取消默认、过期/失败原子保持且不起timer、确认真实Session一次/单history、undo/redo及历史分支/UI baseline恢复、静态保存严格失败，均由最终UI和内核被测范围承接。
- R91：13目标按钮40px/18px、配色时替换views_scroll同一行及其他页隐藏，三档真实预览宽52%/高60%门禁维持。新增墙选色后160ms内切框再选色，两目标颜色分别实际提交、队列不丢、各一条历史；无pending切target零build/零history。有pending先提交原target，不成功不切目标，失败保原target/input/队列/模型/历史；同target不额外flush，repair modal期间不偷切/flush。

这是自动GUI与真实渲染功能专项，不是人工操作/艺术终审；fixed-fps60不作性能证明。本次只读报告，未人工逐图签署。

### 七项headless与失败的第八项必须分开

报告 `/Users/zyq/work/sea-work/verification/20261116-005853-workshop-humanized-integration-f2532e/report.json`：前七项headless均pass、exit0、completion_marker=true、unexpected_errors=[]。

| 入口 | checks / failures |
|---|---:|
| workshop-adjustment | 357 / 0 |
| workshop-union | 24533 / 0；完整64cases、filter空 |
| workshop-shell | 18077 / 0 |
| workshop-random | 17831 / 0 |
| workshop-damage | 1582 / 0 |
| workshop-rules | 879 / 0 |
| workshop-deep | 41 / 0 |

union此批已是完整64组合，不再仅16组合6291/0，但不篡改早批覆盖范围。旧shell25失败的auto/weathering fixture仅由主线程四行维护（两注释、两处 `architecture.palette={}`）恢复显式自动色语义，维持新尺度、真实生成及全部旧断言；新manual slots实际UV另验，不通过放宽断言消红。

**同批第八项editor-scene-assembly仍失败：exit1、passed=false、529条unexpected**，包含全src隔离扫描时Zones/GameState等Autoload未定义，full vs minimal配置冲突未修。不能称该整批通过，也不能用下面独立minimal成功把原失败改成通过。

### 独立minimal装配两次78/0与输入测试边界

独立minimal首12项/1个drop失败保留；后续仅 `godot/tests/test_scene_assembly_editor.gd`维护窗口置顶、window_id、source warp后等两帧、每次reset并断言actual can_drop/drop，产品插件不改。相关因素是遮挡和输入时序，多项测试条件同时调整，非单变量唯一根因；不声称OS focus已激活。

- `20261116-014228-workshop-default-assembly-fix-743e93/report.json`：**78/0、editor0、import0、unexpected_errors=[]**。
- `20261116-014332-workshop-default-assembly-fix-255e0d/report.json`：再次 **78/0、editor0、import0、unexpected_errors=[]**。

两份inner均为同批 `project/outputs/scene_assembly_report.json`，passed=true；main_protection均main_absent=true且使用sea-verification隔离user目录。原70业务断言全留，另加8输入检查；真实建筑/动态树自动GUI拖放、其他静态树/同源实例API补建、工坊保存及undo/redo/编辑器保存重开各自分域。不是人工鼠标/窗口激活/gizmo手感验收，不外推所有遮挡状态。装配测试归SEA-WORLD，不新增重复feature或改产品所有权。

### 当前交付与进行中合并批

主线程minimal串行 `workshop-defaults-delivery`（editor-workshop-upgrade+editor-scene-assembly+adjustment）仍运行，此处只引用上述可靠完成批，不等待、不预签合并批次；最终合并报告由主线程自行追加。交付路径 `outputs/workshop_defaults_review_20261116/index.html` 的final源即将更新，当前仅记路径，不宣称该更新完成。

shared .tres/shader/PNG、Main/project无diff。R89–R91当前范围内已验不等于用户美术终审、真实性能、任意体量/所有平台、正式Main或全工程门禁完成，全库待主线程实际sync。此次只读核对并追加原四文档，ledger补已有 `test_workshop_shell.gd` code_paths；不改code/registry/memory，不运行任何runner/contracts，不commit/push，不改写旧失败历史。

### 主线程收尾：同批串行通过与实际交付

最终 `/Users/zyq/work/sea-work/verification/20261116-015632-workshop-defaults-delivery-90bc20/report.json` 已完成：editor-workshop-upgrade1453/0、editor-scene-assembly78/0、workshop-adjustment357/0，import与各项exit0、unexpected_errors=[]，当前代码与隔离副本一致。完整64组union24533/0及shell18077/0等前七项仍引用005853原报告，原第八项fullsrc无Autoload扫描失败529条不改签。用户可从底栏“调整冲突…”请求建议，先审Session→输入与输入→建议，再显式确认；配色主导航下十三目标仅配色页显示，切换前提交原队列避免快速跨目标丢色，失败保原目标。

主线程已实际审图：新建米白/暖木/青蓝模型、独立两区确认和1280/860配色按钮行，无以随机房屋配色冒充新默认；人工体验与美术终审未签。输出 `outputs/workshop_defaults_review_20261116/index.html`，附7原图与分批原报告/日志，不修改源图。9明确变更定点清单登记，用户Main/共享材质/project无diff，未提交推送。全库sync/check随后记录真实退出码，不因本轮范围内通过批量重签其它资源。

最终全库实际sync488/check489 issues，均exit1；46 features/1073 sources/1563 runtime，421运行漂移、15源漂移、51断链及资产集合/树候选根/派生索引问题保留，无SEA-WORKSHOP条款/本轮入口错误。9项定点源码SHA/bytes一致、非目标清单不刷，完整结果落在 `/Users/zyq/work/sea-work/workshop_defaults_20261116/contracts_results.json` 与同目录原日志。汇总命令exit0只表示记录完成，不能代替内部exit1。当前工作区与最终隔离源码一致，`git diff --check`通过，未提交/推送。

## 2026-11-19 冲突调整按钮深度优化

用户新增确认口径：可以改数值，但点击按钮后必须先告知会改哪些数值，用户确认“是”后才自动改。实现侧将原“调整冲突…”升级为“查看并调整冲突…”：

- 按钮只读收集当前失败/排队窗口字段、当前可见 scope 的窗口输入和 basic 白名单；不调用 Session 写入、不刷新预览、不自动重试。
- 确认窗分成两块：`Session原值 → 当前输入` 与 `当前输入 → 建议值`。每项包含中文名、完整路径、原值、新值、单位、原因及 alias/derived 归类；正文明确当前没有任何数值被自动修改。
- “是，自动修改并生成”仅在用户确认后调用一次真实 `Session.preview_candidate`；成功才提交一次历史和预览。取消、过期、目标 scope/token/catalog/recipe/输入变化、无稳定 owner、恢复 baseline 漂移、真实生成失败均原子保持。
- 确认按钮显式重新启用，解决部分编辑器主题复用 ConfirmationDialog 后按钮保留 disabled 的不可用问题；取消仍为默认焦点。不得静默缩窗、关柱、清覆盖、换模板、后台重试或吞掉无关输入。

当前 `workshop-adjustment` 实测为 PASS，证据 `/Users/zyq/work/sea-work/verification/20261119-024609-final-conflict-adjustment-core-c0c32d`（asset-import exit0）。`editor-workshop-upgrade` 实测可真实渲染确认窗、确认按钮可用、显示当前值与建议值且未自动修改；当前唯一红项是既有跨文档 surface recovery 身份污染造成的输入历史恢复失败，不属于冲突调整建议/确认逻辑。工作区未提交/推送。

## 2026-11-19 接续：U 形屋顶可生成提示与应用失败不一致

原诊断不看待提交的屋顶边覆盖，屋顶按钮又用已保存形态加界面退台/屋顶，并顺带读取门窗和形体。于是诊断可以对另一栋楼报「可生成」，真正应用时才报退台非法或短边开口越界。现用 `editor_screen.gd` 的同一屋顶候选对齐两个入口；候选按真实几何生成，`Session.preview_candidate` 成功后才写配方和历史。`generation_adjustment.gd` 只建议将非法退台 0 改为关闭，不自动截短开口。诊断确认、取消及应用/撤销由真实 Godot 控件路径覆盖。相邻恢复问题另查明为表面层身份未随会话内房屋 ID 同步；提交、撤销及重做同步身份，保持原植被快照与保存基线，异文档仍严格拒绝。回归夹具也改走完整作品事务。

真实编辑器 1534/0，调整 368/0，架构 3534/0，三批 exit 0；U 形俯视实图已检查，用户自己的原草稿未加载，完整世界回归未执行。早期纯截图失败（macOS 额外原生窗口纹理为空）与中间夹具失败保留原报告；最终 U 形弹窗文案取真实控件，屋顶单独用真实渲染。报告、全库契约阻塞和范围详见[工坊账本](../features/workshop/ledger.md#2026-11-19-u-形屋顶诊断和构造应用)。

## 2026-11-19 模拟建造式改装

参考《模拟人生 4》建造模式的直接选取与工具上下文，不接入外部能力，也不改变功能或配方。`editor_screen.gd` 把常用改装动作集中在视口原第二行，原相机动作进视角菜单；`editor_preview.gd` 的真实射线命中只请求选择，在主屏确认后才换高亮和目标；`surface_paint_input.gd` 保护绘画手势归属和暂停笔划。直达窗、部件和选择配色目标不另增历史，不能跨目标吞掉未通过输入；主场景与原保存出口不改。三档真实布局、断言通过与没有完成的真实外挂/笔划闭环见[工坊账本](../features/workshop/ledger.md#2026-11-19-模拟建造式改装操作)。
