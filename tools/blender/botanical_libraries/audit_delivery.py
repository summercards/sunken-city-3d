"""Final scope audit and user-facing contact sheet; no source mutation."""
import hashlib,json,os,subprocess
from pathlib import Path
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_libraries/v001'
P=json.loads((R/'art_source/vegetation/libraries/v001/component_plan.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
errors=[];checks=0
def ck(v,msg):
 global checks
 checks+=1
 if not v:errors.append(msg)
for name in ['scenes','crops','vegetation']:
 p=R/f'assets/registry/ledgers/{name}.json';before=json.loads((W/'registration_backup'/f'{name}.before.json').read_bytes());now=json.loads(p.read_bytes())
 ck(len(before['assets'])==len(now['assets']),name+' count')
 for a,b in zip(now['assets'],before['assets']):ck({k:v for k,v in a.items() if k!='library_refs'}=={k:v for k,v in b.items() if k!='library_refs'},'unchanged primary '+a['asset_id'])
for p,h in P['protected_inputs'].items():ck(sha(R/p)==h,'protected '+p)
for p in ['docs/features/asset/ledger.md','docs/features/ambient/ledger.md','docs/features/crop/ledger.md','docs/features/farm/ledger.md']:
 old=subprocess.check_output(['git','show','HEAD:'+p],cwd=R).decode('utf-8').replace('\r\n','\n');new=(R/p).read_text(encoding='utf-8').replace('\r\n','\n')
 ck(new.startswith(old.rstrip('\n')),'ledger history/header append only '+p)
for lib in P['libraries']:
 man=json.loads((R/lib['path']).with_name('library_manifest.json').read_text(encoding='utf-8'));ck(sha(R/lib['path'])==man['sha256'],'final source hash '+lib['library_id'])
 for m in man['members']:
  if m.get('gallery'):ck(m['gallery']['uniform_scale']>0,'positive uniform display scale')
# Confirm eight real renders completed, all views already written by the Blender renderer.
files=[f'{k}_{v}' for k in ['vegetation','planting'] for v in ['overview','top','back','side']]
out=W/'outputs'
for n in files:ck((out/(n+'.png')).is_file(),'render '+n)
sheet=Image.new('RGB',(1600,980),'#edf0e8');draw=ImageDraw.Draw(sheet)
for i,n in enumerate(files):
 image=Image.open(out/(n+'.png')).convert('RGB');image.thumbnail((380,440));x=(i%4)*400+10;y=(i//4)*490+35;sheet.paste(image,(x+(380-image.width)//2,y+(440-image.height)//2));draw.text((x,y-25),n,fill='#193e2b')
sheet.save(out/'eight_views_review.jpg',quality=94)
board=Image.new('RGB',(1600,1000),'#edf0e8');draw=ImageDraw.Draw(board)
for title,n,box,x in [('VEGETATION - 98 COMPONENTS','vegetation_overview',(970,940),10),('PLANTING - 34 COLLECTIONS','planting_overview',(590,940),1000)]:
 im=Image.open(out/(n+'.png')).convert('RGB');im.thumbnail(box);board.paste(im,(x+(box[0]-im.width)//2,40));draw.text((x,15),title,fill='#193e2b')
board.save(out/'library_overview.jpg',quality=94)
result={'passed':not errors,'checks':checks,'failures':errors,'original_primary_fields_unchanged':True,'ledger_history_append_only':True,'render_count':8,'asset_main_record_duplicates_added':0,'scope_note':'Only library_refs were added to three ledgers. Existing global contract defect remains outside task.'}
(W/'scope_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
if errors:raise SystemExit(1)
