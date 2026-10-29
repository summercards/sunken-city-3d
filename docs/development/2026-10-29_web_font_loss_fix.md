# 2026-10-29 网页版字体豆腐块修复

[主文档](../../GDD_V1.0.md) · [UI 资产账本](../features/asset/ledger.md) · [发布脚本](../../scripts/daily_release.py)。

用户截图：Godot 引擎导出的网页版（`godot/build/web/`，非 `web/` 手工原型）里，屏幕上的大数字、桌子右侧的小字方块全部变成空白/豆腐块。

## 根因

不是"字体没打进包"，而是**代码读了包里根本没有的东西**。

`godot/src/ui/ui_font.gd` 原实现：

```gdscript
var shared := FontFile.new()
shared.data = FileAccess.get_file_as_bytes(EMBEDDED_PATH)  # res://src/ui/fonts/LXGW975YuanSC-700W.ttf
```

- Godot 导出时只打包导入产物 `.godot/imported/LXGW975YuanSC-700W.ttf-<hash>.fontdata`，**源 `.ttf` 不进包**。
- `FileAccess` 不走 `.import` 重映射，在导出包里读源路径只会拿到空字节，`FontFile.data` 为空 → 无字形 → 豆腐块。
- 桌面端有 `allow_system_fallback=true` 的系统字体兜底（本机 Windows 有中文字体），所以**只在网页版暴露**；Web 端没有系统字体，问题 100% 呈现。

包内实测（修复前的 `index.bin`）：2 个 `.fontdata` 都在包里，14.5 MB 字体数据齐备，唯独源 `.ttf` 条目不存在。

## 改动

1. `godot/src/ui/ui_font.gd`：主路径改为 `ResourceLoader.exists()` + `ResourceLoader.load()`，走 `.import` 重映射拿到 `.fontdata`；校验 `data` 非空后才用。保留 `FileAccess` 读源文件作为**工程外隔离副本**（无 `.godot` 缓存）的兜底，但不再是网络版路径。文件头写明这条硬契约。
2. 新增 `scripts/check_pack_assets.py`：对导出的 `.pck`/`.bin` 做静态断言 ——
   - 代码里出现的每个字体，包里必须有原文或它 `.import` 记录的 `.fontdata`；
   - `FileAccess` 直读的 `res://` 路径（含 `const` 间接引用，需常量解析）必须是包内**原样条目**；
   - 包里至少有一个 `.fontdata`。
   - `.tscn`/`.tres` 的编辑器面板读写降级为 WARN（导出后本就不该用，不影响游玩）。
3. `scripts/daily_release.py`：Web 与 Windows 导出后各自执行该检查，失败即写入 `problems` 并让整次发布 `ok=false`。宁可发布失败，也不发一个没字的包。

## 验证

**因果复现（关键证据）**：用修复前代码（`699c7ad^`）单独导出一份 Web 包到 `godot/build/_repro/`，本地 `127.0.0.1:8899` 起服务，无头 Chrome 截图：

| 版本 | HUD 左下角实测 |
|---|---|
| 修复前（`699c7ad^`） | `1月1日 07:00 · 晴 / 瓶盖 60 / 背包 1/24` 全部显示为空白方块 |
| 修复后（`699c7ad`） | 同样位置中文、数字、符号全部正常 |

两轮截图在工程外 `sea-work/release/shots/before_3_panel.png`、`after_3_panel.png`。取证用的 `_repro` 目录已在验证后删除。

**运行时探针**：`--headless` 加载 `ui_font.gd` 后 `FontFile.data.size() == 14884594`，`has_char("海")`、`has_char("A")` 均为 true。

**检查器回归**：对同一份旧包，修复前的代码判 `FAIL`（"字体只能靠直读源文件，而它不在包里"），修复后判 `OK`；Windows 与 Web 两个包均 OK。

**发布结果**（2026-10-29 09:39，退出码 0，`problems` 为空）：commit `699c7ad`，Web 导出 160.7 MiB / `index.bin` 124.4 MiB / `mainpack_patched=true`，`sea-windows.zip` 111.4 MiB。两条链接原地更新，线上 `index.html` 含 `mainPack":"index.bin"`，`index.bin` 与 zip 均 HTTP 200。

## 遗留

`color_grade_panel.gd` 用 `FileAccess` 读写 `res://assets/materials/world_env.tres` 与 `res://scenes/main.tscn`，导出包里不存在。这是调色面板的自助工具，发布版本就不可用，检查器只报 WARN，未改动。
