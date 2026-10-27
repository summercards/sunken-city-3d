# 2026-10-27 航行指令不再弹提示条

[主文档总目录](../../GDD_V1.0.md#feature-control) · [航行功能](../../features/nav/spec.md) · [航行账本](../../features/nav/ledger.md) · [UI 账本](../../features/ui/ledger.md)

## 用户要求

划船移动时不要显示对话框。

## 判断与实施

这里的「对话框」是 HUD 底部那张横长纸条（`hud.toast`，带「海上的消息」标签），不是模态面板。它盖在画面上，点一次水面就弹一次，属于把玩家的输入原样复述一遍，没有新信息。

删除的是「发出移动指令」时的复述，全部位于 `godot/src/bootstrap/main.gd`：

| 位置 | 原文案 | 触发时机 |
|---|---|---|
| `_try_sail_to` | 划向那里 | 点击开阔水面改道 |
| `_on_destination` | 启航 · <区块> | 点击目的地标记跨区航行 |
| `_on_landing_click` 末尾 | 启航 · <区块> · <上岸点> | 点击某上岸点直接出发 |
| `_handle_prop_click`（鱼群分支） | 驶向鱼群 | 点击鱼群 |
| `_handle_prop_click`（漂流物分支） | 驶向<漂流物> | 点击漂流物资 |

保留的都是「结果或拒绝」，不是「我要动了」：

- 抵达 · <区块>、已停船、回到水面、下潜 —— 状态真的变了才说。
- 就在这儿、无法到达鱼群/漂流物、这里没有可通行航路、远海街町需要先升级船只 —— 拒绝与原因。

移动意图本身已经有视觉反馈：航线丝带 `RouteRibbon` + 落点准星 `Reticle`，不再需要文字复述。

## 未改动

- `hud.toast` 本体、纸条样式、出现时长与「海上的消息」标签：其他功能仍在使用。
- 网页原型 `web/`：该端没有对应的纸条提示（只有小人状态行 `setWorkerStatus`），不涉及。

## 验证

全部经 `scripts/run_verification.py`，独立用户目录，未触碰真实存档。

| 专项 | 结果 | 证据 |
|---|---|---|
| click / surface | PASS exit=0 | `sea-work/verification/20261027-111041-verification-db7961`（改动前基线，含「划向那里」删除后） |
| click / surface / selftest | PASS exit=0 | `sea-work/verification/20261027-111208-verification-83e9e6`（五处提示全部删除后） |

未执行：真实窗口目视复核纸条是否还会在划船时出现。测试只覆盖移动规则与点击路由，不断言提示文案，因此本轮结论以源码检索为准：`hud.toast("划…`、`hud.toast("启航`、`hud.toast("驶向` 在 `main.gd` 中已无匹配。
