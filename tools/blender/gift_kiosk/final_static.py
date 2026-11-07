"""Record requested final static checks without accepting unrelated hash drift."""
import json,os,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001';env=dict(os.environ,PYTHONUTF8='1')
commands=[('feature_sync',[sys.executable,'scripts/check_feature_contracts.py','--sync']),('feature_check',[sys.executable,'scripts/check_feature_contracts.py']),('placed_positions',[sys.executable,'scripts/check_placed_positions.py']),('building_class_policy',[sys.executable,'tools/apply_water_layer.py','--dry-run']),('diff_check',['git','diff','--check'])]
results={}
for name,command in commands:
 p=subprocess.run(command,cwd=R,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,encoding='utf-8',errors='replace');results[name]={'command':command,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr};print(name,'exit='+str(p.returncode));print(p.stdout.strip())
(W/'final_static_checks.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
receipt=R/'docs/development/2026-11-07_gift_kiosk_verification.json';data=json.loads(receipt.read_text(encoding='utf-8'));data['final_static_checks']=results;receipt.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
record=R/'docs/development/2026-11-07_gift_kiosk.md'
if '## 最后静态检查记录' not in record.read_text(encoding='utf-8'):
 with record.open('a',encoding='utf-8',newline='') as stream:
  stream.write('\n\n## 最后静态检查记录\n\n摆放、两类职责策略dry-run和git diff --check通过（exit0；git仅有既有CRLF转换提示）。按要求先sync再无参数复核；全局门禁尚未通过，原始输出保存在机器签署和 `D:/projects/sea-work/gift_kiosk/v001/final_static_checks.json`。当前剩余为三处开工前即存在的鱼群源/water.tres/bootstrap main哈希差异，以及制作期间出现的 `docs/features/shop/spec.md` 主文档未登记；无参数检查另报派生索引过期。上述项没有通过刷新哈希或补写任务外功能来隐藏。本批R55/R24/R25/R18、48条新资产、源/优化/运行身份和两类视图均未报错。\n')
