# P 面板「写入」没效果：三个根因与修复

承接 SEA-OCEAN-R23。触发场景：用户按 P 打开调色室 → 侧栏选「清晨」→ 拖海水色 →
点「写入 watertres」→ 回游戏看，什么都没变；其它页签同样。

## 现场证据

- `godot/assets/materials/water.tres` 的 mtime 是点击那一刻（`2026-10-29 11:05:25`），
  但 `git status` 里它**没有出现在修改列表**。文件被打开了、写过了，内容逐字节相同。
- `user://water.cfg` 同期被重写；`user://light_slots.cfg` 停在 `10-28 18:51`，
  里面 `[spring|clear|dawn]` 只有 `env__*`，一条 `water__*` 都没有。
- 面板底部提示原文就有「海水色与反射只改这一段，泡沫形态仍是全局」——
  说明「这一段」的语义是**差值**，不是文件里的那一行。

## 三个根因

### 1. 水面页的差值从来没落盘

`_water_write` 对归 `DaylightRig` 管的项（海水色、天空反射、太阳高光）走的是
`rig.set_offset(...)`，只置 `_water_dirty = true`。而差值的落盘在
`_save_light_cfg()`，它开头是 `if not _light_dirty: return`。

于是：**只拖水面滑杆的人，关面板那一刻一条差值都没写进 `light_slots.cfg`**。
面板里画面真的变了（差值在内存里生效），重启就没了 —— 这是「调完就消失」的那一半。
滤镜页的「对比度」早在同一份代码里写了 `_light_dirty = true`，水面页漏了这一步。

修：`_water_write` 的偏移分支补 `_light_dirty = true`；`_save_water_cfg()` 末尾
顺手 `rig.save_offset_cfg()`（拖动结束就会调到它，不必等关面板）。

### 2. 「写入」写的是没被动过的基准，却报「已写入 N 项」

`_on_water_save` 遍历全部键写 `_water_read(key)`。对时段驱动的项，`_water_read`
刻意返回 `rig.base_of(...)` —— 09:00 基准。而用户在面板上动的是差值，基准一个字
没改。所以写下去的是**文件里原本就有的那串数**，`written` 照样加一，状态栏照样
报成功。

这不是实现 bug，是**回报撒谎**：N 项里没有一项真的变了。

修：写入前按 `rig.owns("water", key)` 分成「全局项 / 时段项」，时段项跳过不写；
顺手统计「真正与原文不同」的行数 `changed`。回报分三种：只动了时段项 →
明说「这 14 项属「春 / 晴 / 清晨」，已存进 `light_slots.cfg`，这次文件没有变化」；
两者都有 → 报清各几项；纯全局项 → 照常报写了几项、其中几项有变化。
光照页与滤镜页同理（那两页整页都是时代偏移，写入本来就是常量的 no-op），
改成写盘前后比对文件内容，没变就直说。

### 3. 状态栏回报活不过一帧

`_process` 里每帧调 `_set_tab(_tab)`（`Cozy.style_tree` 会把按钮皮肤刷成奶油色，
得靠它刷回深色调试皮肤），而 `_set_tab` 末尾无条件 `_refresh_status()`。

结果：任何 `_flash("已写入 …")` 在下一帧就被常规提示顶掉。用户看到的是**一片沉默**，
比报错更糟 —— 报错至少知道该找谁。

修：`_set_tab` 只在**页签真的变了**时（`_tab_applied != id`）重写状态栏；
`_flash` 另记一个 6 秒的 `_flash_hold`，期间 `_refresh_status` 让位；
换页或换时段这类新意图会清掉它。

## 顺带修掉的隐患

`_apply_water_cfg()` 启动时把 `water.cfg` 里的值逐条喂回 `_water_write`。存档里记的
是**基准**，走差值接口就被当成「目标值」反算出一个非零差值 —— 每次在非 9 点启动
都会给当前时段白加一截偏移，越开越亮且查不到来源。现在两处都跳过 `rig.owns` 的键：
它们的真正存档是 `light_slots.cfg`。

## 证据

`python3 scripts/run_verification.py lighting-panel` —— 67 checks / 0 failures。
本轮新增三条断言（`godot/tools/probe_light_panel.gd` 9b / 9c 段）：

1. 把 `_light_dirty` 手动压回 false、只调水面、关面板 → `light_slots.cfg` 里必须
   出现 `[spring|clear|dawn]` 与键 `water__body_deep`；
2. 点「写入 watertres」后状态栏必须点名 `light_slots.cfg`，不得给出空头承诺；
3. 该次写入后 `water.tres` 逐字节不变（时段项不该被烧进基准），探针自己负责还原。

回归：`daylight`、`ocean`、`lighting-params` 同轮全绿。

## 遗留

- 本轮之前只调过水面的差值**无法找回**：它们从未落盘。`water.cfg` 里那批
  `body_shallow` / `body_deep` 等时段键今后不再回放（留在磁盘上，没有删除）。
- 「复位」按钮对时段项仍是「钉住出厂外观」（存一个 `出厂−当前` 的差值），
  与收藏下拉里「出厂」那项的「清空差值」语义不同。未在本轮统一，等用户拍板。
