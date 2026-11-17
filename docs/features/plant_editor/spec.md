# SEA-PLANT-EDITOR · 独立植物工坊

[主文档中控](../../../GDD_V1.0.md#sea-plant-editor) · [本功能账本](ledger.md)

## 功能目的与边界

按 2026-11-12 用户两张森林参考制作独立 Godot 编辑器主屏。树干、分枝、叶簇和叶片可以编辑；真实树种定义树形，不以任意球团改名充当树种。苔藓、藤蔓与既有草对象组合。不改建筑工坊及玩家手摆场景，不改变 Farm 生长、游戏存档或全局风唯一写入者。

## 设计条款与验收标准

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-PLANT-EDITOR-R01 | 独立插件 `addons/plant_editor`，主屏“植物工坊”；独立 Session、预览 World3D、撤销历史、草稿与 `scenes/workshop_plants` 保存根。与建筑插件同时启用、切换前后配方/预览/草稿不串写；不修改原建筑脚本、不打开或保存当前编辑场景。 |
| SEA-PLANT-EDITOR-R02 | 首批香樟 Cinnamomum camphora、鸡爪槭 Acer palmatum、垂枝桦 Betula pendula；记录来源。分别保留宽圆冠/互生全缘椭圆叶、层状舒展冠/对生掌裂叶、直立主干与下垂小枝/互生三角锯齿叶。幼树景观尺度与夸张叶片尺度明确是游戏参数，不冒称完整植物生理模拟。 |
| SEA-PLANT-EDITOR-R03 | 可编辑主干高度/半径/弯曲、冠幅、首分枝高度、主枝数/伸展/上扬/下垂；每枝稳定 ID，可单独隐藏、改长度/角度/粗度并保存，叶簇随所属枝走。seed 确定性，不同枝/叶/附生流独立，改树叶密度不得重抽树干。 |
| SEA-PLANT-EDITOR-R04 | 叶片与叶簇分层编辑：叶片形状由树种约束、尺寸/密度/叶簇大小/松散度/色差/球形法线混合可调。柔软树冠依赖层叠叶片与统一叶簇法线、上亮下暗和清楚轮廓，不用不透明球体替代所有叶片、不从用户图剪切素材。树干和叶片可独立显隐检查。 |
| SEA-PLANT-EDITOR-R05 | 苔藓为固定树皮附生覆盖、藤蔓为独立路径和叶片；各自开关与密度/长度可调，宿主变化后跟随，不整面苔垫摆动。可组合现有 `grass_soft`/`mound_soft` 资源，复制实例与材质，仅预览局部调整，不改原 GLB/TRES/catalog 或设施 TSCN。 |
| SEA-PLANT-EDITOR-R06 | 配方 JSON 与静态 PackedScene 共同版本化保存；验证输入、路径、有限数/区间/未知字段，生成通过后原子提交历史。连续保存只新增 revision，旧版哈希不变，坏配方/失败/取消保留原文档；导出不含编辑器脚本/相机/灯光/碰撞/游戏业务节点。候选不是正式登记，不自动插 Main。 |
| SEA-PLANT-EDITOR-R07 | 预览风使用本地材质 uniform 时间，不写 `vegetation_*` 全局参数；隐藏主屏暂停预览渲染和时钟，重新打开继续。植物作者层不得依赖 building_workshop、Main、Economy 或 Farm。公共资源只读。 |
| SEA-PLANT-EDITOR-R08 | 制作前阅读文章/工具官方说明并记录采用与不采用原因及授权。Sapling 的分枝层级与 seed、Mtree 分层生成、球形法线等仅作算法/工作流参考；不伪称已安装或拷贝第三方代码。若后续确有复用必须记录具体版本与许可，不随意导入不兼容二进制。 |
| SEA-PLANT-EDITOR-R09 | 通过统一 runner 分列内核、实际编辑器双插件隔离、保存重载、旧建筑回归与真实渲染；至少整树/裸枝/叶片近景/附生近景及多树种对照。测试数字不替代图像目检，性能目标与设备实测分开，用户美术终审保持 pending。 |

## 内核接口（冻结 v1）

- `src/plant_authoring/recipe.gd`：`defaults(species="camphor") -> Dictionary`、`validate(data) -> String`；JSON 扁平参数＋`branch_overrides` 字典。
- `src/plant_authoring/species.gd`：`definitions() -> Dictionary`（深副本），键 camphor/maple/birch，值 name/latin/description/sources。
- `src/plant_authoring/generator.gd`：`build(recipe) -> Dictionary`，返回 ok/reason/root/branches/stats；root 是独立 Node3D，枝干分支 `Trunk`、叶片 `Leaves`、苔藓 `Moss`、藤蔓 `Vines`、草 `Grass`。branches 数组每项 id/name；stats 为 triangles/leaf_count/branch_count。
- `src/plant_authoring/session.gd`：唯一拥有配方。`snapshot()`、`apply_patch(patch)`、`load_recipe(data)`、`new_document(species)`、`undo()`、`redo()`、`is_dirty()`、`mark_saved()`；信号 changed。
- `src/plant_authoring/store.gd`：`save(recipe, root_dir="res://scenes/workshop_plants") -> Dictionary`、`load_recipe(path)`、`list_recipes(root_dir)`；result 含 ok/reason/directory/recipe_path/scene_path。
- 参数：species/seed/name/height/trunk_radius/trunk_curve/crown_radius/branch_start/branch_count/branch_spread/branch_rise/branch_droop/leaf_size/leaf_density/cluster_size/cluster_jitter/normal_blend/color_variation/trunk_visible/leaves_visible/moss_enabled/moss_amount/vine_enabled/vine_count/vine_length/grass_enabled/grass_count/grass_asset/branch_overrides。
- branch_overrides[id]：enabled/length_scale/radius_scale/angle_offset；ID 为 branch_00 等。无自定义脚本输入。

## 参考与取舍

- [Sapling 官方手册（4.1 固定版本）](https://docs.blender.org/manual/en/4.1/addons/add_curve/sapling.html)：树形、分枝层级、seed、半径收分与叶片参数；Blender GPL 工具，只参考工作流，不拷贝插件。
- [Mtree](https://github.com/MaximeHerpin/modular_tree)：TrunkFunction→BranchFunction→二级枝，核心 MIT / Blender 插件 GPLv3；当前不增加编译型运行依赖。
- [Zylann Tree Generator](https://github.com/Zylann/godot_tree_generator_plugin)：官方说明 Godot 4.x 不支持，拒绝直接安装旧 GDNative。
- [TreeIt 官方](https://www.evolved-software.com/treeit/treeit)：独立树木工具可编辑关节、叶片与 LOD，导出 DBO/FBX/OBJ/X；免费不等于开源，不拷贝源或预设素材。
- [Forest Waypoint 制作文章](https://80.lv/articles/forest-waypoint-in-ue4-creating-stylized-landscape-and-materials/)：TreeIt 作树、从包络面转移法线，叶片统一受光；借鉴算法，不把 UE 材质直接当 Godot 插件。
- [香樟资料](https://plants.ces.ncsu.edu/plants/cinnamomum-camphora/)、[鸡爪槭资料](https://plants.ces.ncsu.edu/plants/acer-palmatum/)、[垂枝桦资料](https://plants.ces.ncsu.edu/plants/betula-pendula/)：只提取文字形态事实，不下载第三方 CC-BY-NC 图片作游戏素材。

研究日期 2026-11-12。参考图仅作用户提供的视觉方向，不作为可再分发纹理授权。

## 2026-11-14 恢复制作与独立树木工坊交付边界

用户明确恢复本功能，先完成独立树工坊，再考虑嵌入或潜水模型；本节不自动启用任何宿主接入。树工坊主屏显示名为“树木工坊”，FeatureID和既有路径仍用plant_editor，不混入房屋植物摆放页。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-PLANT-EDITOR-R10 | 主屏保持紧凑：一行工具，模块单行位于模型上方，左侧280–320px滚动参数，中心最大预览，16/18px字号。所有数值HSlider+只读当前值/范围；160ms调度、同拖拽一条撤销、无效输入保留成功模型和输入。状态高亮可复制完整详情，文件页名称/路径仍为文本。 |
| SEA-PLANT-EDITOR-R11 | 新增可选subtwig_count、四角色色格trunk/leaf/moss/vine（0..63）、manual/auto、random_enabled/variation、wind_strength/speed；旧配方补默认，seed非负安全整数且各语义流独立。颜色由公共512²8×8PaletteUV单格8px安全内缩决定，树干/实体叶/苔藤共四本地材质实例共享同一shader/PNG；不改公共四建筑材质。复用草卡仅允许现有meadow_atlas的alpha轮廓进入UV2，RGB仍为公共色板，禁止全局风耦合。 |
| SEA-PLANT-EDITOR-R12 | Session是唯一配方/历史写入者；preview_candidate先真实构建一次再提交并返回同一root。JSON指纹排序、浮点按1e-9十进制规范，保持编辑步长变化可辨且避免7.2+0.4往返误报。Store在outputs/plant_editor或scenes/workshop_plants写候选三件bundle；工程外测试根须显式命名授权；新revision/临时目录/重载检查后提交，不碰旧版。逐节点vertices/indices/normals/UV/UV2/实例变换/材质外链身份核验，不能只比较面数；静态风时间归零，不导出预览节点。 |
| SEA-PLANT-EDITOR-R13 | 内核用plant-authoring，真实双插件编辑器用editor-plant，经统一runner、无Autoload且只写隔离副本；输出三树种整树、裸枝、真实叶片/附生近景、独立UI截图和三树种静态样例。非空截图不等于艺术终验，候选不自动正式登记或植入Main/房屋/潜水模型。 |

## 2026-11-14 树木深化与只读树屋结合

用户本轮明确允许树干从房屋内部穿窗或破墙。本节扩展先前“仅独立制作、暂不结合”的边界，但两套工坊仍独立：树工坊只消费已保存宿主场景，不引入房屋生成器或改动宿主；不自动接入 Main 或潜水模型。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-PLANT-EDITOR-R14 | 手动 trunk_path 为米制2–8个XYZ控制点，首点原点、Y严格递增、末点Y等于height；空数组保持旧自动路径。分段平滑命中控制点且不横向过冲；枝叶、树皮、苔藓、藤蔓跟随实际曲干。路径滑条自动预览、单拖一次历史，非法路径保留最后成功模型及待修输入，不静默裁剪。 |
| SEA-PLANT-EDITOR-R15 | 新增bark_detail/bark_cell及moss_scale/bias/height/color_variation。树皮与苔藓为有限预算真实几何，贴片在宿主三角面裁剪后用该面的重心插值定位，不悬浮或穿皮；五角色独立手动色格与可控自动色差均走公共PaletteUV，不改公共PNG。 |
| SEA-PLANT-EDITOR-R16 | wind_runtime只读唯一vegetation_wind_owner的elapsed/strength/direction；无唯一owner时局部fallback，不注册owner、不写全局uniform。复用游戏soft_cards风传播公式，COLOR编码叶柄/藤顶固定与柔性端权重，木干/苔藓不摆；草UV2遮罩不变。编辑器仅显式sample_at，自动_ready/_process不得改网格材质或推进时钟。 |
| SEA-PLANT-EDITOR-R17 | 静态plant.tscn继续无脚本；显式save_animated额外输出仅根wind_runtime白名单的plant_wind.tscn。版本内原子保存/重载，公共shader和PNG保外链、多实例不串材质。首次准备顶点/索引/UV/UV2严格相等，仅法线压缩尾差容许0.0002；后续prepare/sample相对首次结果逐字段严格不变，摘要不可重复序列化完整几何。 |
| SEA-PLANT-EDITOR-R18 | 只读载入项目内building.tscn，消费openings/damage_openings与实际Mesh/Collision，host reference不混入树导出。提供根→内侧→洞心→外侧→冠顶建议及plant_to_host列主序变换。粗干间隙检测真实三角面与实体内部，完整玻璃必须阻挡；根按真实楼板支撑贴板。只覆盖主干，不代替全部枝叶、导航或结构力学验收；top_level宿主拒绝。 |
| SEA-PLANT-EDITOR-R19 | ResourceLoader之前先纯文本审查宿主依赖闭包，拒绝脚本/危险构造器/二进制资源/路径逃逸/符号链接/嵌套继承场景等，公共PNG及建筑shader仅明确白名单；加载后继续SceneState审计。不声称防御审查与加载之间的并发磁盘替换。 |
| SEA-PLANT-EDITOR-R20 | Session唯一拥有已应用recipe+authoring_context，统一1e-9规范状态指纹、纯变换和配方成对撤销重做；失败保留待应用输入但不换成功模型/位置。recovery先预检同一已应用状态再提交，pending单独恢复。植物保存只清recipe dirty，attachment落盘才清context dirty，过期版本/保存状态拒绝；UI不读写私有历史栈。 |
| SEA-PLANT-EDITOR-R21 | 统一runner并列plant-authoring/plant-integration/host-scene-guard/editor-plant，实际保存房屋作为宿主。验收真实穿墙、玻璃拒绝、楼板贴根、双历史与静动态/attachment导出；渲染两确定风帧与固定树干苔藓对照、近景和860×600展开面板，不以截图存在代替像素变化或面积检查。用户艺术终审、正式世界接入与群树林性能另签。 |

## 2026-11-15 保持风格和效果的叶片性能优化

用户明确补充：优化性能不能牺牲风格和效果。当前不是每片叶一个节点，而是每主枝一个Foliage网格；优化应针对真实顶点/细分/生成与资源开销，不误诊成几百个叶节点。原单叶轮廓、树冠密度、颜色层次与风动为保真基线。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-PLANT-EDITOR-R22 | 可选leaf_geometry为balanced/high/reference，缺字段默认balanced；不改变叶数、排列、seed、尺寸、色格、厚度、杯曲或树种轮廓。high仅索引复用，balanced保守移除内部冗余采样，所有轮廓边采样保留；上下叶肉与侧壁真实存在，不用平卡或大幅删叶冒充优化。相邻面共边规则一致，无T接缝、退化或错绕序。 |
| SEA-PLANT-EDITOR-R23 | 作者网格显式COLOR保存原叶柄固定/叶尖渐进、藤顶固定及草高度权重，避免顶点索引重排破坏旧扫描布局；runtime不重推已有权重。参数域拓扑可缓存但不共享可变配方/随机状态。叶片页三档自动预览/一次撤销/保存重载，显示实数顶点、三角面、Mesh节点及surfaces，不把surface数冒称实际draw calls。 |
| SEA-PLANT-EDITOR-R24 | plant-performance经统一runner真实后端、禁fixed-fps、关VSync；三树种同seed、同机位整树/叶近景/掠视与两风帧A/B，检查同叶数/位置/UV/解析法线/边界/风权重和有界内部曲面误差。记录顶点/面数/CPU数组字节与生成耗时；多树场景记录实际draw calls/primitives、wall-clock p50/p95。明确共享资源测试与实际动态独立实例策略差异，GPU计时无效须标未测，单树回归如实记录；不得直接把减面率换算FPS或冒充Main/移动/Web性能。 |

## 2026-11-15 09:02 轻量树冠与09:30图像模型授权追加

09:02用户要求大幅降低性能开销：新增少量立体叶团、邻近色体块的树冠模式，同时保留单叶观感路线，将昂贵单叶几何转换为贴图叶卡。原要求使用image2生成后缩小；image2权限失败后，09:30用户明确授权image-2.6。追加时主线程正以实际模型`gpt-image-2.6-sunburst`生成，不能将请求发出或工具完成写成图集已通过验收。

本次新指令**仅对新模式volumes/cards覆盖R04/R22中禁止球团或平卡替代的限制**；不是推翻历史，也不把新模式称为原厚叶几何无损优化。geometry及其balanced/high/reference三档继续受旧条款约束，旧档不默换、不覆盖旧revision。树种冠形、配色层次、枝编辑、独立工坊、风所有权和保存隔离边界继续有效。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-PLANT-EDITOR-R25 | 新增可选foliage_mode，合法值volumes/cards/geometry。新建配方默认volumes；读取缺该字段的旧配方必须解释为geometry，不因新建默认值改变旧外观。leaf_geometry的balanced/high/reference及缺字段默认balanced保留，仅控制geometry旧路线；切换新模式不丢弃该值。模式切换经Session统一预览、撤销重做、保存重载，失败保留最后成功模型与输入，不改写旧配方文件或旧revision。volumes以少量立体叶团和邻近色体块表现树种冠形；cards以贴图叶卡保留可辨单叶观感，不能宣称仍有旧叶肉厚度或与geometry逐像素相同。 |
| SEA-PLANT-EDITOR-R26 | cards及其藤叶共用512×512 RGBA、2×2图集，左上香樟、右上鸡爪槭、左下垂枝桦、右下藤叶；保留各自单叶轮廓与透明留白。使用授权模型生成原始美术源，再缩小为运行图集；原始输出及生成、缩小处理记录保留在art_source/plant_editor_leaf_atlas/v001，不用缩小图覆盖原源，不从用户参考图剪切素材。运行候选为godot/assets/textures/vegetation/workshop_leaf_atlas_512.png；采用alpha clip而非透明混合，导入与采样均启用mipmap，UV2按格采轮廓/细节，RGB主色继续服从公共PaletteUV，不改公共色板。验收须确认真实alpha、缩小后轮廓、格间渗色及远近景效果；模型授权/工具返回不等于素材接入或艺术通过。 |
| SEA-PLANT-EDITOR-R27 | 新模式内核按显示角色及兼容材质合批，不跨角色混并而破坏树干/叶/苔/藤/草显隐或风权重；保留稳定branch ID、定位节点与根局部branch bounds，选枝、高亮、聚焦、单枝编辑及宿主定位不依赖已合并的旧Mesh节点。UV/UV2/COLOR、变换与法线须正确保留，导出保存重载不得丢失引用或风隔离。预算目标为三树种volumes/cards各自完整默认树≤8 surfaces且≤12000 triangles，包含默认启用的树皮、苔藓、藤蔓与草，不以关闭附生/藏节点达标；geometry不强套此预算。逻辑叶数、实际叶团/叶卡数、顶点、三角面、Mesh节点及surfaces分列，surfaces不冒称draw calls；预算必须经Godot实际构建计数确认，未验不得写达标。 |
| SEA-PLANT-EDITOR-R28 | 新增统一runner专项plant-canopy，与plant-authoring/plant-integration/plant-performance及真实editor-plant回归并列，覆盖模式兼容、合批前后数据、branch bounds、保存重载、图集和三树种同seed同机位整树/单叶近景/掠视/两风帧。性能使用真实渲染后端、关闭VSync、禁止fixed-fps；volumes/cards分别实测1/16/64棵，geometry对照1/16棵，geometry64棵标未测且不外推。默认动态导出实例策略与刻意共享候选分开；记录设备/后端/分辨率/抗锯齿/阴影、预热采样窗口、wall-clock p50/p95、实际draw calls/primitives、构建耗时和CPU数组字节，保留回归与波动，不将减面率换算FPS。GPU计时无效标未测；源码/工具完成或截图存在均不等于验收，真实Godot报告和图像目检独立留证。Main、潜水接入、移动/Web、群树林LOD、全局门禁和用户艺术终审仍不签。 |

## 2026-11-15 10:20 参考图饱满树冠与混合叶卡外壳

用户提供游戏树冠截图，明确体块也要参考其饱满形状，并在外面添加叶片贴图。截图仅作冠形、层次与风格参考，不从截图裁切纹理素材。本节扩展volumes为低模体块与外壳叶卡混合路线，不增加第四种foliage_mode，不改写R25–R28或旧geometry历史。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-PLANT-EDITOR-R29 | volumes以内部24 triangles闭合低模簇支撑饱满体积，并向各方向布置外壳叶卡，每卡4 triangles，形成参考图方向的饱满冠形与外缘可辨叶片，不只向单一机位铺卡。新增volume_leaf_cards整数参数0..16，新建默认12，旧配方缺字段按0读取，0保留纯体块；不得给旧volumes配方静默增加外壳，foliage_mode缺字段仍按geometry，原leaf_geometry三档保留。参数仅控制volumes外壳，经Session预览、撤销重做与保存重载，保持branch ID/bounds、角色合批、风权重及独立资源边界。外壳使用R26图集；纯单叶cards路线仍为每叶4 triangles叶片+2 triangles平柄，不能与混合外壳卡成本混算。图集alpha clip阈值0.42，每个256×256格的有效像素范围为格内8..247，导入启用mipmaps与VRAM压缩；缩小和压缩后的透明边、远近景、各向轮廓及风动须真实渲染目检。R27完整默认树预算不变，混合默认7 surfaces、纯体块6 surfaces目前仅静态结构推算，必须经plant-canopy实测，不冒称draw calls或验收通过。 |

### 图集最新状态与验收边界

按本次主线程交接，image-2.6在用户更新临时授权凭据后，已通过用户明确授权的multipart字节上传成功生成；实际模型为`gpt-image-2.6-sunburst`。该最新状态取代先前“生成中/权限阻塞”的当前结论，原历史保留。原图为`art_source/plant_editor_leaf_atlas/v001/image26_leaf_atlas_source.png`，1024×1024、1060810 bytes；运行图`godot/assets/textures/vegetation/workshop_leaf_atlas_512.png`为512×512 RGBA、218744 bytes。同源目录保留`generation.json`（模型、提示词及来源，无密钥）与`preparation.json`（缩小准备记录），不得将授权凭据写入文档或生成记录。

plant-canopy正在主线程串行运行，结果仍pending，不追加成功数字。旧内核preflight的251/0、540/0、155/0只说明旧几何与逻辑检查，不能证明新混合外壳、预算或真实性能通过；R28无fixed-fps、GPU无效记未测及Main等未签边界继续有效。

## 2026-11-15 r9交付补充：双图集来源与验收测量口径

本节细化R25–R29，不新增条款或改写历史。当前参考混合生产实现为24 triangles闭合内芯按0.65缩小、全平滑法线，每簇默认12张各向四三角叶簇卡；每张卡的图像含9叶，不等于9片几何叶。volume_leaf_cards=0保留纯体块，cards保持独立单叶4 triangles+平柄2 triangles。旧字段兼容、角色合批与branch bounds要求不变。

- **双图集**：单叶`godot/assets/textures/vegetation/workshop_leaf_atlas_512.png`为512²、218744 bytes，供独立单叶路线；混合外壳改用同目录`workshop_leaf_clusters_512.png`，512²、301592 bytes。此处细化R29“外壳使用R26图集”为使用同一授权生成来源派生的叶簇图集，不把单叶和叶簇当成同一纹理。
- **来源保留**：`art_source/plant_editor_leaf_atlas/v001`保留image-2.6原图、generation.json、preparation.json，以及叶簇派生的clusters_preparation.json、prepare_clusters.py等源支持文件；原始用户截图仅作风格参考，不裁素材，不记录密钥。生成/上传操作授权已获用户确认，但正式资产来源/授权核验仍pending，未发AssetID，不混同两种授权状态。
- **真实贴图路径**：shader采用alpha clip 0.42、格内有效8..247像素与mipmap；r9已验证实际BC7（BPTC）压缩资源及解码alpha，不仅检查导入配置。自动图像/数据断言不代替用户艺术终审。
- **性能测量**：真实SubViewport经TextureRect显示在前台置顶宿主，各模式承担同等展示成本；Store.save_animated实际磁盘动态旁车，保留逐实例资源与风处理。无fixed-fps、无force_draw的自然draw回调间隔是wall-clock采样口径，**不是GPU fence完成时间或屏幕呈现FPS**；合批对照中的force_draw只用于draw calls比较，不混入自然采样。每组至少2.2秒预热、2.2秒采样/90帧，两轮反序；停绘/超时必须判无效，失败轮不得混样。

r9完整专项23253/0，22轮无丢draw/超时且全部focused；editor与必要内核也已完成，具体报告、预算及回归见账本。原“预算仅推算/串行待验”当前状态由本次真实证据更新，历史不删。默认混合三树种实测均≤8 surfaces、≤12000 triangles；不承诺所有负载更快，单树p95回归及16棵cards/pure尾部回归必须保留。GPU计时无效未测，geometry64棵未测；艺术终审、Main/潜水接入、Web/mobile、LOD及全库门禁仍未签。

## 2026-11-15 场景装配薄桥接与静动态保持

| 条款 ID | 规则与验收 |
|---|---|
| SEA-PLANT-EDITOR-R30 | plugin.request_document(path, token) 仅显示原树木工坊并走 screen 既有打开/脏确认；成功后 document_opened 建立 token 绑定，取消/失败由 document_request_finished 返回而不提前改绑；普通打开/新建成功发 token=0 解除旧绑定。save_recipe/save_animated 成功后发 revision_saved，由 SEA-WORLD 单独拥有目标 Placement 的换版事务，不让树 Session/Store 写场景摆位或自动保存 Main。静态实例引用 plant.tscn，动态实例引用 plant_wind.tscn；动态目标遇仅静态保存时保留新版本并提示实例未更新，不能静默降为静态，须显式保存动态风版本。 |

R01/R06 的“不修改场景/不自动插 Main”继续作为工坊自身边界；本次仅增加用户显式装配后的事件桥接，场景写入由 [SEA-WORLD](../world/spec.md) 管理。树库为空提示先保存候选，不自动灌入样例；Placement 无脚本不等于动态 Asset 无 wind_runtime，风所有权与旧宿主只读规则保持。不新增正式 AssetID、WalkArea、航行或潜水接入。

## 2026-11-17 预览工具栏与导航修复

本节细化 R10/R13 的已有预览交互，不扩大植物生成或世界接入范围。正面/俯视/透视/适配工具栏必须与预览渲染区域分离，点击、旋转、平移、缩放后仍可见可点击。SubViewportContainer 只显示纹理，独立上层 Control 拥有 GUI 输入与焦点，裁切限制在预览框内。

左/右拖旋转，中键或 Shift+拖动沿相机屏幕平面平移；滚轮缩放同时支持透视与正交。单击选枝、双击聚焦；预览持有焦点时 F 聚焦选枝，无选择则适配全部（含只读宿主）。隐藏、停用或窗口/控件失焦取消拖动，重建仍保持用户机位。验收须真实 GUI 注入点击/拖动并留点击后整屏截图，不以直接调用处理函数代替输入路由证据。

## 2026-11-17 双工坊切换、失败原子性与草稿保护（R01、R06、R07、R10、R12、R13、R20）

隐藏停止参数计时与滑块合并，但不丢待应用输入；返回仅调度未尝试版本，失败输入不得随切屏反复生成。重复显示幂等。实际祖先可见性同时门控预览渲染、process与材质风开关；首次取景等待真实可见及两帧稳定尺寸，之后保留用户机位。预览结构更新对已就绪旧实例幂等补齐导航层与信号，不重复_ready、不清World3D或模型。

首次预览因资源未就绪失败时保留明确原因，提供「重试预览」；不每帧或每次切屏盲目重建。必须草源缺失/未导入/不合法时生成返回结构化失败，不允许空引用异常后提交残缺成功。可注入候选校验端口由编辑器完成风准备，必须先于Session配方、上下文、历史和changed提交；拒绝释放独立候选、保留旧模型，成功复用已准备网格。静态Store不因此绑定编辑器或自动接入世界。

草稿恢复失败、坏JSON或不可读时禁止自动及退出覆盖原文件，提示先另存配方。测试草稿IO仅在runner令牌、项目根与独立user目录均匹配且无Main/Autoload的专项放行，普通editor-plant仍禁写。统一 `editor-workshop-switch` 以真实主屏标签、滚轮和拖动验证两工坊隔离；模拟旧结构迁移、滑块信号事务与真实物理按住跨控件输入分列，不互相代签。
