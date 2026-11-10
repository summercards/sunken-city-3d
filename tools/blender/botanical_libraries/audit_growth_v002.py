"""Read-only final source/scope audit plus lossless-aspect review contact sheets."""
import copy,hashlib,json,os,subprocess,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_growth/v002'
checks=0;failures=[]
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ck(v,msg):
 global checks
 checks+=1
 if not v:failures.append(msg)
def strip_new(row,ids):
 value=copy.deepcopy(row)
 if 'library_refs' in value:value['library_refs']=[r for r in value['library_refs'] if r.get('library_id') not in ids]
 return value
manifests=[read(R/f'art_source/{d}/libraries/v002/library_manifest.json') for d in ['vegetation','crops']]
lib_ids={m['library_id'] for m in manifests};names=read(R/'tools/blender/botanical_libraries/plant_names_v002.json')['plants'];name_map={n['asset_id']:n['display_name'] for n in names}
ck(len(names)==len(name_map)==len(set(name_map.values()))==104,'104 unique ids/names')
routes=read(R/'assets/registry/ledger_index.json')['domains'];all_ids=[];expected=set();ref_count=0
for domain in ['scenes','vegetation','crops']:
 before=read(W/'registration_backup'/(domain+'.before.json'));now=read(R/routes[domain]['ledger'])
 ck(len(before['assets'])==len(now['assets']),'record count '+domain)
 ck({k:v for k,v in before.items() if k!='assets'}=={k:v for k,v in now.items() if k!='assets'},'ledger metadata '+domain)
 for a,b in zip(now['assets'],before['assets']):
  all_ids.append(a['asset_id']);ck(strip_new(a,lib_ids)==strip_new(b,lib_ids),'original fields and v001 refs '+a['asset_id'])
  matching=[r for r in a.get('library_refs',[]) if r.get('library_id') in lib_ids]
  if a['asset_id'] in name_map:
   ck(len(matching)==1,'one new ref '+a['asset_id']);ref_count+=len(matching)
   for ref in matching:
    ck(ref['display_name']==name_map[a['asset_id']] and set(ref['growth_forms'])=={'small','medium','large'},'named three forms '+a['asset_id'])
ck(len(all_ids)==len(set(all_ids)),'no duplicate primary ids');ck(ref_count==104,'104 updated old records')
render_paths=[]
if '--run-contracts' in sys.argv:
 contract_status={}
 for name,args in [('sync',['--sync']),('check',[])]:
  result=subprocess.run([sys.executable,str(R/'scripts/check_feature_contracts.py'),*args],cwd=R,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  log=W/('contracts_'+name+'.log');log.write_bytes(result.stdout);contract_status[name]={'exit_code':result.returncode,'log':str(log)}
 (W/'contract_status.json').write_text(json.dumps(contract_status,indent=2)+'\n',encoding='utf-8')
for domain,m in zip(['vegetation','crops'],manifests):
 report=read(W/domain/'verification_report.json');ck(report['passed'] and not report['failures'],'source verifier '+domain)
 ck(sha(R/m['path'])==m['sha256']==report.get('sha256',report.get('blend_sha256')),'source hash '+domain)
 ck(m['status']=='source_models_reopened_append_verified','verified status '+domain)
 ck(m['season_variants'] is False,'no seasonal changes '+domain)
 ck(sha(Path(m['source_verification']))==m['source_verification_sha256'],'report provenance '+domain)
 grouped={}
 for member in m['members']:
  grouped.setdefault(member['asset_id'],[]).append(member);ck(member['display_name']==name_map[member['asset_id']],'named member '+member['collection'])
 for aid,rows in grouped.items():
  expected.add(aid);ck({r['growth_key'] for r in rows}=={'small','medium','large'} and len(rows)==3,'all three '+aid)
  ck(len({r['geometry_fingerprint'] for r in rows})==3 and len({r['triangles'] for r in rows})==3,'distinct form geometry '+aid)
 rr=read(W/domain/'render_report.json');paths=rr.get('rendered',rr.get('views',[])+rr.get('closeups',[]));ck(len(paths)==rr['count'],'render report count '+domain)
 if 'library_sha256' in rr:ck(rr['library_sha256']==m['sha256'],'rendered current hash '+domain)
 for path in paths:
  p=Path(path);ck(p.is_file(),'render exists '+str(p))
  if p.is_file():
   with Image.open(p) as im:ck(im.width>=1000 and im.height>=600,'readable render '+p.name);im.verify()
  render_paths.append(str(p))
ck(expected==set(name_map),'all named plants modelled')
for plan_path in ['art_source/vegetation/libraries/v002/component_plan.json','art_source/vegetation/libraries/v001/component_plan.json']:
 for p,h in read(R/plan_path)['protected_inputs'].items():ck((R/p).is_file() and sha(R/p)==h,'protected input '+p)
for rel in ['docs/features/asset/ledger.md','docs/features/ambient/ledger.md','docs/features/crop/ledger.md','docs/features/farm/ledger.md']:
 old=subprocess.check_output(['git','show','HEAD:'+rel],cwd=R).decode('utf-8').replace('\r\n','\n');new=(R/rel).read_text(encoding='utf-8').replace('\r\n','\n');ck(new.startswith(old.rstrip('\n')),'append only history/header '+rel)
# These logs are collected from two separate real commands, not the wrapper shell status.
contract_status=read(W/'contract_status.json');ck(set(contract_status)=={'sync','check'},'two actual contract commands recorded')
for name,item in contract_status.items():ck(Path(item['log']).is_file() and isinstance(item['exit_code'],int),'contract evidence '+name)
# Deliverable review sheets, with original aspect ratios and legible Chinese headings.
out=W/'outputs';ck(out.parent.is_dir(),'output parent exists');out.mkdir(exist_ok=True)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',28);small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23)
vp=W/'vegetation/renders';cp=W/'crops/renders'
items=[('阔叶 · 小 / 中 / 大',vp/'detail_broadleaf.png'),('生菜 · 小 / 中 / 大',cp/'comparison_01_生菜.png'),('棕榈 · 小 / 中 / 大',vp/'detail_palm.png'),('番茄 · 小 / 中 / 大',cp/'comparison_02_番茄.png'),('藤蔓 · 小 / 中 / 大',vp/'detail_vine.png'),('南瓜 · 小 / 中 / 大',cp/'comparison_03_南瓜.png')]
def contact(items,path,columns=2,cell=(900,500),title='104 种植物 · 312 个小中大模型 · 暂不制作季节变化'):
 rows=(len(items)+columns-1)//columns;board=Image.new('RGB',(columns*cell[0],rows*cell[1]+80),'#f3f2e9');draw=ImageDraw.Draw(board);draw.text((25,20),title,font=font,fill='#244538')
 for i,(caption,p) in enumerate(items):
  x=i%columns*cell[0];y=i//columns*cell[1]+80;draw.text((x+20,y+12),caption,font=small,fill='#244538');im=Image.open(p).convert('RGB');im.thumbnail((cell[0]-20,cell[1]-60));board.paste(im,(x+(cell[0]-im.width)//2,y+48+(cell[1]-60-im.height)//2))
 board.save(path,quality=95)
contact(items,out/'三档植物模型_总览.jpg')
more=[(p.stem,p) for p in sorted(vp.glob('detail_*.png')) if p.stem.replace('detail_','') in ['broadleaf','flower','palm','vine','grass','reed','moss','kelp','water_leaf','tomato']]+[(p.stem,p) for p in sorted(cp.glob('comparison_*.png'))]
contact(more,out/'植物三档_分类对照.jpg',cell=(1000,540))
result={'passed':not failures,'checks':checks,'failures':failures,'plant_count':104,'model_count':312,'referenced_asset_ids':ref_count,'new_primary_records':0,'original_fields_and_v001_refs_unchanged':True,'ledger_history_append_only':True,'season_variants':False,'runtime_integration':False,'render_count':len(render_paths),'contracts':contract_status,'scope':'source models only; global contract failures remain explicitly separate','deliverables':[str(out/'三档植物模型_总览.jpg'),str(out/'植物三档_分类对照.jpg')]}
(W/'delivery_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(result,ensure_ascii=False,indent=2))
if failures:raise SystemExit(1)
