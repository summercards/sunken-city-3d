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
