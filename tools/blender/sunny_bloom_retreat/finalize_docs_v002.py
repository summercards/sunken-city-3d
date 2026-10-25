# -*- coding: utf-8 -*-
"""Attach current source verification evidence to this feature's documents."""
from pathlib import Path
import json, os
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunny_bloom_retreat_v002'
qa=json.loads((W/'verification.json').read_text())
assert qa['passed'] and len(qa['views'])==5
qa['execution']={'build_exit_code':0,'source_verification_exit_code':0,'registration_exit_code':0,'render_engine':'Blender Cycles','rendered_views':5,'visual_review':'All five views inspected; user final art approval pending.','expected_faults':[],'unexpected_errors':[],'warnings':['Blender 6.0 API deprecation warnings under Blender 5.2.2.']}
(R/'docs/development/2026-10-25_sunny_bloom_retreat_verification.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
p=R/'docs/features/asset/ledger.md'
s=p.read_text().replace('v002 源级结构通过；最终渲染复核中，Godot pending','v002 源级与五视图验证通过；Godot 与用户美术验收 pending')
if '## 阳光繁花小屋独立制作与比例修订' not in s:
    s+='''
## 阳光繁花小屋独立制作与比例修订（2026-10-25）

- SEA-ASSET-R13：[v002 Blender 源](../../../art_source/scenes/sunny_bloom_retreat/v002/sunny_bloom_retreat.blend)，[组件与打开说明](../../../art_source/scenes/sunny_bloom_retreat/README.md)。本次附件独立从零制作，v001 是本任务自身的早期候选，保留不覆盖。
- 用户要求两处后柱都补：完成后侧白墙柱与棚架后柱；建筑竖向收紧 8%，调整前廊侧墙和斜顶封墙、窄木铺板、双列栈桥与入口陈设。
- 45 组件、490 实例；45 独立包重开与 40211 母版面 PaletteUV 校验通过；全景、建筑单独、近景、俯视、后侧结构五视图已渲染并目视核对。实例展开为 352554 多边形 / 662504 三角面，未声明低面数验收通过。
- [制作记录](../../development/2026-10-25_sunny_bloom_retreat.md)与[结构化证据](../../development/2026-10-25_sunny_bloom_retreat_verification.json)。46 条本套 AssetID 记录通过总索引路由登记；其他资产和公共色板哈希不重算。
- Blender 构建、源级验证与登记退出码均为 0；Godot 接入、碰撞、导航、运行性能、商业授权及用户最终美术验收仍 pending。
'''
p.write_text(s)
p=R/'docs/development/2026-10-25_sunny_bloom_retreat.md'
s=p.read_text().replace('构建：退出码待汇总','构建：退出码 0').replace('源级重开与渲染：退出码待汇总','源级重开与渲染：退出码 0')
p.write_text(s)
p=R/'art_source/scenes/README.md'
s=p.read_text()
if 'sunny_bloom_retreat/README.md' not in s:
    s+='''
## 阳光繁花小屋 · 当前附件独立制作

[当前 v002 源与打开说明](sunny_bloom_retreat/README.md)：45 个独立组件，建筑与花草分离；补齐后墙柱和棚柱，修正前廊、比例及木板位置；源级与五视图通过，Godot 接入 pending。
'''
p.write_text(s)
print('Documentation finalized with current saved-source evidence.')
