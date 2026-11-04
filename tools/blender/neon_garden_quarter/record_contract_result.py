"""Record the actual global check failures without accepting other suites' drift."""
from pathlib import Path
import json,os
R=Path(__file__).resolve().parents[3];W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter/v001'
issues=['SEA-SCENE-ORF-ASSEMBLY: source hash drift','runtime hash drift: godot/assets/data/zones.json','runtime hash drift: godot/assets/materials/ocean_sky.tres','runtime hash drift: godot/scenes/zones/zone1_home_harbor.tscn','content ID drift/duplicate godot/assets/data/zones.json']
report=dict(sync=dict(command='python3 -X utf8 scripts/check_feature_contracts.py --sync',exit_code=1,issues=issues),check=dict(command='python3 -X utf8 scripts/check_feature_contracts.py',exit_code=1,issues=issues+['derived feature index stale; use --sync']),counts=dict(features=39,source_assets=739,runtime_hashes=544),ngq_specific_errors=[],action='Kept all unrelated asset/runtime hash baselines; the checker deliberately writes derived index only with zero issues.')
(W/'feature_contract_results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
note='''

## 全局契约同步结果（本轮实测）

`python3 scripts/check_feature_contracts.py --sync` 已执行，退出1：39功能／739源资产／544运行哈希，5个任务外问题。无参复核退出1，另报派生功能索引过期，共6项。本套件48条登记没有独立错误。

阻断来自 `SEA-SCENE-ORF-ASSEMBLY` 源哈希、`godot/assets/data/zones.json`、`godot/assets/materials/ocean_sky.tres`、`godot/scenes/zones/zone1_home_harbor.tscn` 的运行哈希，以及 zones 内容ID差异。检查器仅在全工程零问题时写派生索引，因此同步没有落盘。没有重算或接受这些任务外文件的哈希；源码／场景／基线保持。源索引从各账本已有登记值派生，不重算他人源文件。完整结果见工程外 `feature_contract_results.json`。

本套件Blender源级和Skill专项仍为通过；全工程文档契约不能标记通过。最终母版已在新的Blender4.5窗口打开，原未保存窗口仍保留。
'''
path=R/'docs/development/2026-11-04_neon_garden_quarter.md'
if '## 全局契约同步结果' not in path.read_text(encoding='utf8'):
 with path.open('a',encoding='utf8') as f:f.write(note)
ledger=R/'docs/features/asset/ledger.md'
if 'R44全局同步' not in ledger.read_text(encoding='utf8'):
 with ledger.open('a',encoding='utf8') as f:f.write('\n\nR44全局同步：已执行sync与无参复核，分别退出1／1；ORF旧源、zones／ocean_sky／zone1运行哈希与zones内容ID差异阻断，派生功能索引因此未更新。本套件源级验收通过，不以刷新任务外哈希掩盖全局失败。详见本轮交付记录。\n')
print('GLOBAL_CONTRACT_BLOCKERS_RECORDED_WITHOUT_HASH_REFRESH')
