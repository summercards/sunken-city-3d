"""Register derived archive references only. Never replace primary source/runtime hashes or stages."""
import argparse, copy, hashlib, json, os
from pathlib import Path
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_libraries/v001'
P=json.loads((R/'art_source/vegetation/libraries/v001/component_plan.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def dump(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main(write=False):
 report=read(W/'source_verification.json');assert report['passed'],report['failures']
 routes=read(R/'assets/registry/ledger_index.json')['domains']
 relevant={d:R/routes[d]['ledger'] for d in ['scenes','crops','vegetation']}
 raw={d:p.read_bytes() for d,p in relevant.items()};ledgers={d:json.loads(b) for d,b in raw.items()}
 originals=copy.deepcopy(ledgers)
 lookup={a['asset_id']:(d,a) for d,v in ledgers.items() for a in v['assets']}
 manifests=[];refs={}
 for lib in P['libraries']:
  path=R/lib['path'];man=read(path.with_name('library_manifest.json'))
  assert sha(path)==man['sha256'],path
  man['archive_stage']='source_archive_reopened_verified'
  man['source_verification']=str(W/'source_verification.json')
  man['source_verification_sha256']=sha(W/'source_verification.json')
  man['primary_source_migration']=False
  for member in man['members']:
   aid=member['asset_id'];assert aid in lookup,aid
   entry=refs.setdefault(aid,[])
   same=next((x for x in entry if x['library_id']==lib['library_id']),None)
   if same is None:
    same={'library_id':lib['library_id'],'path':lib['path'],'sha256':man['sha256'],'manifest':path.with_name('library_manifest.json').relative_to(R).as_posix(),'collections':[],'kind':'derived_collection_archive_not_primary_source','archive_verification':'source_archive_reopened_verified','original_stage_unchanged':True}
    entry.append(same)
   same['collections'].append(member['collection'])
  manifests.append((path.with_name('library_manifest.json'),man))
 for aid,rr in refs.items():
  d,a=lookup[aid]
  current=a.setdefault('library_refs',[])
  for new in rr:
   old=next((x for x in current if x.get('library_id')==new['library_id']),None)
   if old is not None:current[current.index(old)]=new
   else:current.append(new)
 # Every preexisting field except library_refs must compare exactly, including source/hash/status.
 for d,doc in ledgers.items():
  before=originals[d]
  assert {k:v for k,v in doc.items() if k!='assets'}=={k:v for k,v in before.items() if k!='assets'}
  assert len(doc['assets'])==len(before['assets'])
  for a,b in zip(doc['assets'],before['assets']):
   assert {k:v for k,v in a.items() if k!='library_refs'}=={k:v for k,v in b.items() if k!='library_refs'},a['asset_id']
 for p,h in P['protected_inputs'].items():assert sha(R/p)==h,p
 summary={'passed':True,'write':write,'referenced_asset_ids':len(refs),'counts_by_domain':{d:sum(1 for aid in refs if lookup[aid][0]==d) for d in relevant},'primary_record_count_unchanged':True,'original_source_runtime_stage_unchanged':True,'no_current_source_index_mutation':True,'libraries':[{'path':m['path'],'sha256':m['sha256'],'collections':m['member_count']} for _,m in manifests]}
 if write:
  backup=W/'registration_backup';backup.mkdir(exist_ok=True)
  for d,path in relevant.items():
   assert path.read_bytes()==raw[d],f'Concurrent change: {path}'
   bpath=backup/(d+'.before.json')
   if not bpath.exists():bpath.write_bytes(raw[d])
  for d,path in relevant.items():dump(path,ledgers[d])
  for path,man in manifests:dump(path,man)
  dump(W/'registration.json',summary)
 print(json.dumps(summary,ensure_ascii=False,indent=2))
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--write',action='store_true');main(ap.parse_args().write)
