# 2026-10-26 · P 面板「光照」页（环境 + 太阳参数）

对应条款：SEA-OCEAN-R09（新增）。相关：SEA-OCEAN-R07 / R08、SEA-UI-R17。

## 要解决的问题

P 键面板原来只有「滤镜」（曝光/亮度/对比度/饱和度四行）和「水面」（着色器 60 项）。
但画面观感的大头其实在另外两处：`WorldEnvironment` 的 **Environment**（环境光、泛光、
环境遮蔽、雾）和 `World/Lights/Sun` 这盏平行光。要调这两块，此前只能改
`assets/materials/world_env.tres` 与 `scenes/main.tscn` 后重启 —— 而调光恰恰是
「看一眼、动一下」的活，重启一次等于把反馈打断了。

## 做了什么

### 1. 新增参数清单 `godot/src/rendering/light_params.gd`

30 项，分两组：

| 组 | 项数 | 内容 |
|---|---|---|
| `environment`（环境） | 19 | 环境光能量/颜色/天空占比、天空亮度、泛光开关/强度/光晕/阈值、环境遮蔽开关/强度/半径/受光、雾开关/颜色/受光/起点/终点/曲率/天空占比 |
| `sun`（太阳） | 11 | 强度、颜色、角径、高度角、方位角、阴影开关/浓度/模糊/偏移/法线偏移/距离 |

为什么单独一份清单，不并进 `water_params.gd`：那份管的是**着色器 uniform**，
读写走 `get/set_shader_parameter`、复位源是 `.tres`、写回是逐行改材质文件；
这份管的是**引擎对象属性**，读写走 `get/set_indexed`、复位源是「打开面板那一瞬的快照」、
写回一处走 `ResourceSaver` 一处走场景文本。两条路径硬合成一张表，每个函数里都要 if。

刻意**不进**清单的属性，理由写在清单头部：`ambient_light_source` / `reflected_light_source` /
`tonemap_mode` / `fog_mode` 是枚举，改了等于换一套光照模型而不是调参；体积雾、SDFGI、
SSIL、SSR 项目没启用；`glow_levels/1..7` 是泛光型号不是日常旋钮。

### 2. 面板扩成三页

`filter` / `light` / `water`。`set_tab()` 接受这三个 id，`--light` 启动参数直接翻到光照页。

控件层做了一次去重：`_add_scalar_row` / `_add_bool_row` / `_add_color_row` /
`_add_vector_row` 改成接受可选的「写入函数 + 控件表 + 落盘函数」，不传就是水面那套，
传了就是光照那套。原来这四行构建器写死了 `_water_write` / `_water_widgets`，
两页各抄一份必然演化成「水面页修了排版 bug，光照页还是老样子」。

### 3. 太阳朝向用角度，不用欧拉角

暴露的是 **高度角**（相对海平面，1°~89°）和 **方位角**（0 = +Z，-180°~180°），
写入时转成方向向量再 `look_at_from_position`。欧拉角跟「太阳多高」隔着一层，
而且和场景里 look_at 出来的基不对应，调参时要在脑子里换算。
两个虚拟轴各自只改自己那一维，另读当前另一维 —— 先拖高度角再拖方位角不会互相抹掉
（探针里有一条断言专门盯这件事）。

### 4. 写入场景：两条路，都不整份重存

- **环境** → `ResourceSaver.save(env, "res://assets/materials/world_env.tres")`。
  存完会把文件行尾改回 CRLF。`ResourceSaver` 一律 LF 落盘，仓库是 CRLF 检出，
  不还原就是整份文件在 diff 里全红（账本 2026-10-24 记过一次这种「幻影漂移」）。
  实测：只改了值那 1 行。
- **太阳** → 按行改 `scenes/main.tscn` 里 `[node name="Sun"]` 那一块，只碰已知的 10 个键。
  实测只动 2 行（`transform`、`light_energy`），节点数、`unique_id`、其它节点原样。
  写后自检：必须还是 `[gd_scene` 文本、Sun 块还在、`[node name=` 计数没变，
  任何一条不成立就整份还原。

### 5. 顺手修掉的存档 bug

`_save_cfg()` 原来是「新建 ConfigFile → 写 `[filter]` → save」。`filter.cfg` 现在同时
住着 `[filter]` / `[environment]` / `[sun]`，照原样会把后两段抹掉 —— 表现是
「调完光照，去拖一下曝光，光照设置全丢」。改成先 `load()` 再写。
探针里有一条断言专门盯这个：拖滤镜值之后 `[sun]` 必须还在。

## 验证

| 项 | 结果 |
|---|---|
| `python3 scripts/run_verification.py lighting-params` | 退出 0，172 checks / 0 failures |
| `python3 scripts/run_verification.py lighting-panel` | 退出 0，22 checks / 0 failures |
| `python3 scripts/run_verification.py ocean` | 退出 0 |
| `python3 scripts/run_verification.py visual-paper-fit` | 退出 0，11 checks / 0 failures |
| `godot --script res://src/ui/verify_island_ui.gd` | 126 项 / 0 失败（新增 6 项光照页断言） |
| `python3 scripts/check_feature_contracts.py` | PASS，31 features，0 issues |

`lighting-params` 干的是静态对账：属性名在 `Environment` / `DirectionalLight3D` 上真的存在、
kind 合法、**范围包得住出厂值**（包不住的话一开面板滑块就贴端点，「复位」还会把场景改坏）、
清单每一项都真的在面板上生成了控件。太阳的出厂值直接从 `main.tscn` 文本里读 ——
不实例化场景，因为 `main.tscn` 的 `_ready` 会起整个世界（岸线图重建 2 秒）。

`lighting-panel` 干的是端到端：滑杆写进 `Environment` 与 `Sun`、朝向两轴互不覆盖、
关面板写出 `[environment]`/`[sun]`、重开能恢复、滤镜页不冲掉光照存档、复位回场景值、
复制参数在无剪贴板环境下不崩。它跑前会挪走 `user://filter.cfg`、跑完还原，
不然会把开发者当前调好的值当成出厂值来比对。

未执行：`visual-sea-style` 本轮未重跑（不涉及画面定版参数）；gl_compatibility 未单独复验
（光照页只改引擎属性，不新增着色器，后端差异不适用）。

## 遗留

- 光照页没有「收藏」整套切换。水面有，是因为 60 个参数靠记忆比对不现实；
  光照 30 项里真正会成套变的（黄昏/阴天/清晨）也确实存在，但那是「天气预设」的语义，
  应当等 SEA-TIME 的世界日历落地后一起做，而不是现在抄一份 `water_presets.cfg` 的结构。
- `world_env.tres` 的写回走 `ResourceSaver`，会重排文件（本次实测排序和原来一致，
  但 Godot 升级后不保证）。真在意 diff 噪声的话，可以照太阳那条路改成逐行替换。
- 太阳只有 `Sun` 一盏进面板。三盏补光（`HemisphereFill` / `VioletShadow` / `GroundBounce`）
  属于「整体光照配方」，调单项容易把配色调歪，留给场景文件。
