# Web 导出启用 GDExtension（dlink 模板）

2026-11-10，导出配置变更，不涉及功能条款。

## 现象

浏览器打开 Web 版直接失败，控制台：

```
GDExtension libraries are not supported by this engine version.
Enable "Extensions Support" for your export preset and/or build your custom
template with "dlink_enabled=yes".
```

## 原因

`Terrain3D` 是 GDExtension（`godot/addons/terrain_3d/terrain.gdextension`），
而 Godot 官方 Web 导出模板出于体积/兼容性不带 GDExtension 支持，只有
`web_dlink_*.zip` 系列（编译时 `dlink_enabled=yes`）才能在运行时 dlopen 扩展模块。
工程 `Web` 预设里 `variant/extensions_support` 原为 `false`，于是打出来的是非 dlink 模板。

判定证据（改前产物）：

- `build/web/index.wasm` = 37,700,666 B，与 `web_nothreads_release.zip` 里 `godot.wasm`
  字节数完全一致；
- 目录里没有 `index.side.wasm`（dlink 模板会把引擎拆成小 `index.wasm` + `index.side.wasm`）。

## 变更

`godot/export_presets.cfg`，仅 `preset.0`（Web）：

```
variant/extensions_support=false  →  true
variant/thread_support=false      保持（与 terrain 的 nothreads wasm 对齐）
```

本机 `%APPDATA%/Godot/export_templates/4.6.3.stable/` 已含
`web_dlink_nothreads_{debug,release}.zip`，无需自行编译模板；打开开关后 Godot 按名字自动选用。

## 实测

`Godot_v4.6.3-stable` 重新 `--export-release "Web"`（exit 0，3m38s），产物：

| 文件 | 大小 |
|---|---|
| index.wasm | 1,509,558 B（小模块） |
| index.side.wasm | 41,130,147 B（引擎主体） |
| index.pck | 275,027,728 B |
| libterrain.web.release.wasm32.nothreads.wasm | 2,117,798 B |

Chrome 无头实测（`python3 -m http.server` 同级的静态服务，未加 COOP/COEP）：

- 无 GDExtension 报错，`GODOT_CONFIG` 正常加载；
- `[render] method=gl_compatibility adapter=WebKit WebGL size=(1600.0, 1000.0)`；
- canvas 1600x1000，截图能进到标题画面 `SEA / 沉没街区上的屋顶生活 / 开始游戏`，3D 场景正常渲染。

单线程模板不需要跨源隔离头，普通静态服务即可；将来若开 `thread_support` 才需要 COOP/COEP。

## 副作用与注意

1. **渲染后端**：工程默认 Forward+，Web 上引擎自动落到 `gl_compatibility`。
   控制台会出现 `WARNING: 2D MSAA is not yet supported for GLES3`（`msaa_3d=2` 不受影响）。
2. **重新导出会覆盖打了补丁的 index.html。** `scripts/daily_release.py:patch_web_pack`
   与 `godot/tools/make_web_dist.py` 之前做的两件事会失效：曝光 LUT 注入、`index.pck → index.bin`
   改名（内网发布白名单不含 .pck）。发布前仍要走其中一条链路，别直接把 `build/web` 扔上服务器。
3. **旧 `index.bin` 会残留**（274 MB，上一版改名的产物）。`patch_web_pack` 会先删再改名，可不管；
   手工上传前应清掉，否则多传 274 MB。
4. **index.js 由 0.3 MB 涨到 5.5 MB**（dlink 模板的 JS 运行时较大），首屏下载量增加。

## 未处理

- 引擎版本口径不一致：本机 `~/bin/godot.cmd` 与导出模板都是 4.6.3，
  而 `godot/project.godot` 声明 `config/features=PackedStringArray("4.7", ...)`；
  `docs/development/2026-10-24_godot_4_7_2_toolchain_upgrade.md` 记录的 F 盘 4.7.2
  已不存在。本次导出在该错配下成功，未在本次统一，留待工具链收敛时处理。
- 未测 Terrain3D 在水下关卡的运行时表现（只到标题画面与主场景首帧），
  也未测移动端浏览器。
